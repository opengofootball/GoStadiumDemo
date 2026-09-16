extends Node3D

## Main scene for the isolated Common Pitch (real-world metres, 1 unit = 1 m).
## The modern_stadium shell is NOT loaded for now - only the CommonPitch (130x90 turf
## with a 105x68 play area + textured LED ad panels) and the two separate goals.

@onready var world_env: WorldEnvironment = $WorldEnvironment
@onready var sun_light: DirectionalLight3D = $SunLight
@onready var walk_camera: WalkCamera = $WalkCamera
@onready var common_pitch: Node3D = $CommonPitch
@onready var goals_root: Node3D = $Goals

# UI nodes
@onready var ui_panel: Control = $HUD/MainPanel
@onready var title_label: Label = $HUD/MainPanel/VBox/Title
@onready var speed_slider: HSlider = $HUD/MainPanel/VBox/SpeedBox/SpeedSlider
@onready var speed_value_label: Label = $HUD/MainPanel/VBox/SpeedBox/SpeedValue
@onready var time_slider: HSlider = $HUD/MainPanel/VBox/TimeBox/TimeSlider
@onready var time_value_label: Label = $HUD/MainPanel/VBox/TimeBox/TimeValue
@onready var coverage_slider: HSlider = $HUD/MainPanel/VBox/CloudBox/CoverageSlider
@onready var density_slider: HSlider = $HUD/MainPanel/VBox/DensityBox/DensitySlider
@onready var mouse_hint_label: Label = $HUD/MouseHint
@onready var message_toast: Label = $HUD/MessageToast

## Small, packed goal model (513 KB, 4 meshes: goalposts + net + 2 net poles).
## Modeled in metres. Exposed as a PackedScene variable: drag a different goal .glb into
## this field in the Inspector to swap goal models without touching code.
@export var goal_model_scene: PackedScene = preload("res://pitch/modern_stadium_goal.glb")

## The goal model's upright posts are 4.928 m apart (center-to-center) and 2.018 m tall:
##   goal_width_scale  4.928 -> 7.32 m (exact FIFA 7.32 m regulation post-to-post mouth width)
##   goal_height_scale 2.018 -> 2.44 m (exact FIFA 2.44 m regulation crossbar height)
@export var goal_width_scale: float = 1.4855
@export var goal_height_scale: float = 1.2091

# Pitch reference (metres) - CommonPitch is centred at the world origin.
const GROUND_Y: float = 0.0
const PLAY_L: float = 105.0
const HALF_LEN: float = PLAY_L * 0.5   # goal lines at +/-52.5

# Goal model geometry (metres):
# In modern_stadium_goal.glb root space:
# - upright posts are centered at local Z = 0.75, X = 0.0 (pillars at X = +/-2.5)
# - the front face of the posts is at local Z = 0.80
# Shifting pivot by -0.75 along Z puts the post center EXACTLY at the goal node's origin (Z = 0),
# which aligns the posts dead-center on the white goal line.
const GOAL_MESH_CENTER_X: float = 0.0
const GOAL_MESH_FRONT_Z: float = 0.75

# Viewpoints (metres)
const VIEWPOINTS = {
	"pitch":    { "pos": Vector3(0.0, 1.8, 0.0), "yaw": 0.0, "pitch": -0.05, "name": "Pitch Center" },
	"aerial":   { "pos": Vector3(48.0, 9.0, 0.0), "yaw": PI * 0.5, "pitch": -0.12, "name": "Sideline View" },
	"overview": { "pos": Vector3(0.0, 55.0, -95.0), "yaw": 0.0, "pitch": -0.5, "name": "Aerial Overview" },
	"goal1":    { "pos": Vector3(0.0, 1.8, -38.0), "yaw": 0.0, "pitch": 0.0, "name": "North Goal" },
	"goal2":    { "pos": Vector3(0.0, 1.8, 38.0), "yaw": PI, "pitch": 0.0, "name": "South Goal" },
}

var sky_material: ShaderMaterial = null
var sun_time: float = 13.5

func _ready() -> void:
	if world_env and world_env.environment and world_env.environment.sky:
		sky_material = world_env.environment.sky.sky_material

	_spawn_goals()
	if title_label:
		title_label.text = "⚽ Common Pitch (130×90 m)"
	teleport_to_viewpoint("pitch")

	if walk_camera:
		walk_camera.speed_changed.connect(_on_camera_speed_changed)
		walk_camera.mouse_capture_changed.connect(_on_mouse_capture_changed)
		_on_camera_speed_changed(walk_camera.move_speed)

	update_time_of_day(13.5)
	if coverage_slider and sky_material:
		coverage_slider.value = sky_material.get_shader_parameter("cloud_coverage")
	if density_slider and sky_material:
		density_slider.value = sky_material.get_shader_parameter("cloud_density")

func _spawn_goals() -> void:
	for c in goals_root.get_children():
		goals_root.remove_child(c)
		c.queue_free()

	if goal_model_scene == null:
		push_warning("Goal model PackedScene is not assigned in the Inspector.")
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
	goals_root.add_child(node)

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

func teleport_to_viewpoint(vp_key: String) -> void:
	if VIEWPOINTS.has(vp_key):
		var vp = VIEWPOINTS[vp_key]
		walk_camera.teleport_to(vp["pos"], vp["yaw"], vp["pitch"])
		show_toast("Viewpoint: " + vp["name"])

func update_time_of_day(hour: float) -> void:
	sun_time = hour
	if time_slider:
		time_slider.value = hour
	if time_value_label:
		var hours_int = int(hour)
		var mins_int = int((hour - hours_int) * 60)
		time_value_label.text = "%02d:%02d" % [hours_int, mins_int]

	var sun_angle = ((hour - 6.0) / 24.0) * TAU
	if sun_light:
		sun_light.rotation.x = -sin(sun_angle) * (PI * 0.45)
		sun_light.rotation.y = sun_angle
		var elevation = sin(sun_angle)
		if elevation > 0:
			sun_light.light_energy = clampf(elevation * 1.5, 0.1, 1.2)
		else:
			sun_light.light_energy = 0.02

	if sky_material:
		sky_material.set_shader_parameter("cloud_time_offset", hour * 10.0)

func _process(delta: float) -> void:
	if sky_material:
		var current_offset: float = sky_material.get_shader_parameter("cloud_time_offset")
		sky_material.set_shader_parameter("cloud_time_offset", current_offset + delta * 0.5)

func _input(event: InputEvent) -> void:
	# Defensive input handling: never call is_action_pressed() on an action that
	# might be absent from the InputMap (e.g. if project.godot is out of sync on
	# another machine), because Godot throws a C++ assertion in that case.
	# Each action has a hard-coded physical-key fallback so the control always works.
	if _action_pressed(event, "toggle_gui", KEY_F1):
		ui_panel.visible = not ui_panel.visible
	elif _action_pressed(event, "view_pitch", KEY_1):
		teleport_to_viewpoint("pitch")

func _action_pressed(event: InputEvent, action: StringName, fallback_keycode: Key) -> bool:
	# Prefer the mapped action when it exists in the InputMap...
	if InputMap.has_action(action) and event.is_action_pressed(action):
		return true
	# ...otherwise fall back to the raw physical key so we never error out.
	var key_event := event as InputEventKey
	return key_event != null and key_event.pressed and not key_event.echo and key_event.physical_keycode == fallback_keycode

func _on_camera_speed_changed(new_speed: float) -> void:
	if speed_slider:
		speed_slider.value = new_speed
	if speed_value_label:
		speed_value_label.text = "%.1f" % new_speed

func _on_mouse_capture_changed(captured: bool) -> void:
	if mouse_hint_label:
		if captured:
			mouse_hint_label.text = "Press [ESC] to release mouse for UI"
		else:
			mouse_hint_label.text = "Press [ESC] or Click 3D view to recapture mouse"

func _on_speed_slider_value_changed(value: float) -> void:
	if walk_camera:
		walk_camera.move_speed = value
		_on_camera_speed_changed(value)

func _on_time_slider_value_changed(value: float) -> void:
	update_time_of_day(value)

func _on_coverage_slider_value_changed(value: float) -> void:
	if sky_material:
		sky_material.set_shader_parameter("cloud_coverage", value)

func _on_density_slider_value_changed(value: float) -> void:
	if sky_material:
		sky_material.set_shader_parameter("cloud_density", value)

func show_toast(msg: String) -> void:
	if message_toast:
		message_toast.text = msg
		message_toast.visible = true
		var tween = create_tween()
		tween.tween_interval(3.0)
		tween.tween_callback(func(): message_toast.visible = false)
