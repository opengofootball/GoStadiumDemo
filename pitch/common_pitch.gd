extends Node3D

## Common Pitch Scene (common_pitch.tscn)
## A self-contained football pitch module: turf + regulation lines (PitchMesh), ground
## collision, double-sided rotating LED ad hoardings (AdPanels), corner flags, and the
## two goals (Goals). PitchMesh, GroundCollision, AdPanels and CornerFlags are declared
## directly in the scene tree; only the goals are instantiated from an exported PackedScene
## so the goal model can be swapped in the Inspector without touching code.

@export_group("Ad Boards")
@export var enable_ad_boards: bool = true
@export var ad_change_interval: float = 5.0
# Sinks the whole pitch (grass + lines + goals + ad boards + flags + collision) a
# little below the stadium floor so the turf is not riding too high at the seam.
@export var pitch_y_offset: float = -0.20
## Sponsor banners cycled by the LED boards. Left empty, the script auto-loads the
## banners from res://assets/ads/. Drag more PNGs into this array to extend the rotation.
@export var ad_textures: Array[Texture2D] = []

@export_group("Dugout Cutout (per-stadium)")
## Discards grass inside the two sunken team-dugout pits so it never floods the
## seats/footwell. Bounded on both min and max |Z| so the midfield gap between the
## home and away dugouts stays grassed. Tune these per stadium; set dugout_max_z = 0
## to disable the cutout entirely (e.g. a stadium with a running track, like Neftyanik).
## Modern Stadium default (measured from the concrete pit walls):
@export var dugout_min_x: float = -39.1   # back wall of the pit
@export var dugout_max_x: float = -35.3   # front curb of the pit
@export var dugout_min_z: float = 8.25    # inner edge (toward midfield)
@export var dugout_max_z: float = 16.85   # outer edge (toward the corner)

@export_group("Goals")
## Goal model, authored in metres (513 KB, 4 meshes: goalposts + net + 2 net poles).
## Drag a different goal .glb/.tscn into this slot in the Inspector to swap goal models.
@export var goal_model_scene: PackedScene = preload("res://pitch/modern_stadium_goal.glb")
## The goal model's upright posts are 4.928 m apart (center-to-center) and 2.018 m tall:
##   goal_width_scale  4.928 -> 7.32 m (exact FIFA post-to-post mouth width)
##   goal_height_scale 2.018 -> 2.44 m (exact FIFA crossbar height)
@export var goal_width_scale: float = 1.4855
@export var goal_height_scale: float = 1.2091

# Regulation pitch (metres). CommonPitch is centred at the world origin; long axis = Z.
const PLAY_L: float = 105.0
const HALF_LEN: float = PLAY_L * 0.5   # goal lines at +/-52.5
const GROUND_Y: float = 0.0

# Goal model geometry (metres): upright posts are centered at local Z = 0.75 in the model
# root, so shifting the pivot by -0.75 along Z puts the post center exactly on the goal
# node's origin (on the white goal line).
const GOAL_MESH_CENTER_X: float = 0.0
const GOAL_MESH_FRONT_Z: float = 0.75

var _touch_panels: Array[Node3D] = []
var _goal_panels: Array[Node3D] = []
var _timer: float = 0.0
var _phase: int = 0

func _ready() -> void:
	# Sink/raise the entire pitch assembly (all children move with the node).
	position.y = pitch_y_offset

	_apply_dugout_cutout()
	_setup_ad_panels()
	_spawn_goals()

func _apply_dugout_cutout() -> void:
	var grass := get_node_or_null("PitchMesh") as MeshInstance3D
	if grass == null:
		return
	var mat := grass.material_override as ShaderMaterial
	if mat == null:
		return
	mat.set_shader_parameter("dugout_min_x", dugout_min_x)
	mat.set_shader_parameter("dugout_max_x", dugout_max_x)
	mat.set_shader_parameter("dugout_min_z", dugout_min_z)
	mat.set_shader_parameter("dugout_max_z", dugout_max_z)

func _process(delta: float) -> void:
	if not enable_ad_boards or ad_textures.size() < 2:
		return
	_timer += delta
	if _timer >= ad_change_interval:
		_timer -= ad_change_interval
		_phase += 1
		_apply_phase()

# ---------------------------------------------------------------------------
# Ad panels (double-sided rotating LED hoardings)
# ---------------------------------------------------------------------------

func _setup_ad_panels() -> void:
	var panels = get_node_or_null("AdPanels")
	if not enable_ad_boards:
		if panels:
			panels.visible = false
		return

	_ensure_textures()

	if panels:
		for b in panels.get_children():
			var holder = b as Node3D
			if holder == null:
				continue
			# Give each face its own material instance so all four boards can be
			# driven independently (front/back stay in sync within a board).
			for face_name in ["Front", "Back"]:
				var face = holder.get_node_or_null(face_name) as MeshInstance3D
				if face and face.material_override is StandardMaterial3D:
					face.material_override = (face.material_override as StandardMaterial3D).duplicate()
			if holder.name.begins_with("AdPanel_Touch"):
				_touch_panels.append(holder)
			elif holder.name.begins_with("AdPanel_Goal"):
				_goal_panels.append(holder)

	_apply_phase()

func _apply_phase() -> void:
	var n := ad_textures.size()
	# Touchlines start on banner 0, goal lines start on banner 1 (inverted rotation)
	var touch_idx := _phase % n
	var goal_idx := (_phase + 1) % n
	for holder in _touch_panels:
		_set_banner(holder, ad_textures[touch_idx])
	for holder in _goal_panels:
		_set_banner(holder, ad_textures[goal_idx])

func _set_banner(holder: Node3D, tex: Texture2D) -> void:
	if tex == null:
		return
	for face_name in ["Front", "Back"]:
		var face := holder.get_node_or_null(face_name) as MeshInstance3D
		if face == null:
			continue
		var mat := face.material_override as StandardMaterial3D
		if mat == null:
			continue
		mat.albedo_texture = tex

		# Compute horizontal repeats so each banner keeps its native aspect ratio
		# and is never stretched. Board size comes from the face's QuadMesh.
		var board_size := Vector2.ZERO
		if face.mesh is QuadMesh:
			board_size = (face.mesh as QuadMesh).size
		var board_len: float = board_size.x
		var board_h: float = board_size.y
		var tw: int = tex.get_width()
		var th: int = tex.get_height()
		if board_len > 0.0 and board_h > 0.0 and tw > 0 and th > 0:
			var banner_width_m := board_h * (float(tw) / float(th))
			var repeats := int(round(board_len / banner_width_m))
			mat.uv1_scale = Vector3(maxi(1, repeats), 1.0, 1.0)

func _ensure_textures() -> void:
	if ad_textures.size() > 0:
		return
	for path in ["res://assets/ads/ad_banner_0.png", "res://assets/ads/ad_banner_1.png"]:
		if ResourceLoader.exists(path):
			var tex = load(path)
			if tex is Texture2D:
				ad_textures.append(tex)

# ---------------------------------------------------------------------------
# Goals (instantiated from the exported PackedScene)
# ---------------------------------------------------------------------------

func _spawn_goals() -> void:
	var goals_root := get_node_or_null("Goals")
	if goals_root == null:
		goals_root = Node3D.new()
		goals_root.name = "Goals"
		add_child(goals_root)

	for c in goals_root.get_children():
		goals_root.remove_child(c)
		c.queue_free()

	if goal_model_scene == null:
		push_warning("CommonPitch: goal_model_scene is not assigned.")
		return

	# The goal model opens toward +Z (mouth at +Z, net recedes toward -Z) and its width
	# spans X. Place each goal node exactly on the corresponding goal line (Z = +/-52.5)
	# and rotate so the mouth faces the pitch centre:
	#   North goal line (min Z): mouth faces +Z -> rotation.y = 0
	#   South goal line (max Z): mouth faces -Z -> rotation.y = PI
	_spawn_goal_instance(goal_model_scene, "GoalNorth",
		Vector3(0.0, GROUND_Y, -HALF_LEN), 0.0)
	_spawn_goal_instance(goal_model_scene, "GoalSouth",
		Vector3(0.0, GROUND_Y, HALF_LEN), PI)

func _spawn_goal_instance(scn: PackedScene, node_name: String, world_pos: Vector3, rot_y: float) -> void:
	# Outer node sits exactly on the goal line; rotation.y aims the mouth toward the pitch.
	var node = Node3D.new()
	node.name = node_name
	node.position = world_pos
	node.rotation.y = rot_y
	get_node("Goals").add_child(node)

	# Inner pivot applies independent width/height scale (metres are 1:1) and re-centres the
	# mesh so the mouth plane sits exactly on the goal node's origin (on the goal line).
	var sx: float = goal_width_scale
	var sy: float = goal_height_scale
	var pivot = Node3D.new()
	pivot.name = node_name + "_Pivot"
	pivot.scale = Vector3(sx, sy, sx)
	pivot.position = Vector3(-GOAL_MESH_CENTER_X * sx, 0.0, -GOAL_MESH_FRONT_Z * sx)
	node.add_child(pivot)

	var model = scn.instantiate()
	pivot.add_child(model)

	_build_goal_frame_collision(model, pivot, node, node_name)

func _build_goal_frame_collision(model: Node, pivot: Node3D, host: Node3D, node_name: String) -> void:
	# Compute a combined AABB in the model-root local space using ONLY local transforms
	# (accumulated up the parent chain), so it is valid synchronously at _ready time.
	var local_combined := AABB()
	var first := true
	for child in model.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi == null:
			continue
		var xf := Transform3D.IDENTITY
		var n: Node = mi
		while n != null and n != model:
			var node3d := n as Node3D
			if node3d == null:
				break
			xf = node3d.get_transform() * xf
			n = n.get_parent()
		var a: AABB = xf * mi.get_aabb()
		if first:
			local_combined = a
			first = false
		else:
			local_combined = local_combined.merge(a)
	if first:
		return

	# Convert to the goal node's (host's) local space by applying the pivot transform.
	var pt: Transform3D = pivot.get_transform()
	var combined: AABB = pt * local_combined

	# Geometry helpers (host-local, metres). Mouth plane is at host-local Z = 0.
	var hw := combined.size.x * 0.5
	var base_y := combined.position.y
	var frame_height := combined.size.y
	var frame_depth := combined.size.z
	var post_thick := clampf(combined.size.x * 0.02, 0.08, 0.16)
	var mouth_z := 0.0

	# Post/crossbar frame collision (thin boxes, so shots pass into the net).
	var body := StaticBody3D.new()
	body.name = node_name + "_FrameCollision"
	body.add_child(_make_box_collision("Post_L",
		Vector3(-hw + post_thick * 0.5, base_y + frame_height * 0.5, mouth_z),
		Vector3(post_thick, frame_height, post_thick)))
	body.add_child(_make_box_collision("Post_R",
		Vector3(hw - post_thick * 0.5, base_y + frame_height * 0.5, mouth_z),
		Vector3(post_thick, frame_height, post_thick)))
	body.add_child(_make_box_collision("Crossbar",
		Vector3(0, combined.position.y + frame_height - post_thick * 0.5, mouth_z),
		Vector3(combined.size.x, post_thick, post_thick)))
	host.add_child(body)

	# Scoring volume: a box recessed behind the goal line, inside the aperture.
	var score := Area3D.new()
	score.name = node_name + "_ScoreArea"
	score.collision_layer = 4
	score.collision_mask = 0
	var scol := CollisionShape3D.new()
	var sbox := BoxShape3D.new()
	sbox.size = Vector3(combined.size.x - post_thick * 2.0, frame_height - post_thick, frame_depth * 0.6)
	scol.shape = sbox
	scol.position = Vector3(0, base_y + (frame_height - post_thick) * 0.5, -frame_depth * 0.3)
	score.add_child(scol)
	host.add_child(score)

func _make_box_collision(shape_name: String, center: Vector3, size: Vector3) -> CollisionShape3D:
	var c := CollisionShape3D.new()
	c.name = shape_name
	var b := BoxShape3D.new()
	b.size = size
	c.shape = b
	c.position = center
	return c
