extends Node3D

## Common Pitch Scene (common_pitch.tscn)
## PitchMesh, GroundCollision, and AdPanels are declared directly as first-class nodes
## in the scene tree (.tscn), NOT generated in GDScript.
## This script rotates the LED ad panels like real broadcast hoardings: each board
## displays a static sponsor banner for ad_change_interval seconds, then flips to the
## next one. Touchline (W/E) and goal-line (N/S) boards run inverted against each other.

@export var enable_ad_boards: bool = true
@export var ad_change_interval: float = 5.0
## Sponsor banners cycled by the LED boards. Left empty, the script auto-loads the
## banners from res://assets/ads/. Drag more PNGs into this array to extend the rotation.
@export var ad_textures: Array[Texture2D] = []

## Panels keep a constant horizontal tiling of sponsor logos across the board length.
## The repeat count is computed dynamically from the banner's aspect ratio and the
## board dimensions so banners are never stretched (see _set_banner).

var _touch_panels: Array[MeshInstance3D] = []
var _goal_panels: Array[MeshInstance3D] = []
var _timer: float = 0.0
var _phase: int = 0

func _ready() -> void:
	var panels = get_node_or_null("AdPanels")
	if not enable_ad_boards:
		if panels:
			panels.visible = false
		return

	_ensure_textures()

	if panels:
		for b in panels.get_children():
			var mi = b as MeshInstance3D
			if mi == null or not (mi.material_override is StandardMaterial3D):
				continue
			# Duplicate so each panel owns its material and can show a different banner
			var mat = mi.material_override.duplicate() as StandardMaterial3D
			mi.material_override = mat
			if mi.name.begins_with("AdPanel_Touch"):
				_touch_panels.append(mi)
			elif mi.name.begins_with("AdPanel_Goal"):
				_goal_panels.append(mi)

	_apply_phase()

func _process(delta: float) -> void:
	if not enable_ad_boards or ad_textures.size() < 2:
		return
	_timer += delta
	if _timer >= ad_change_interval:
		_timer -= ad_change_interval
		_phase += 1
		_apply_phase()

func _apply_phase() -> void:
	var n := ad_textures.size()
	# Touchlines start on banner 0, goal lines start on banner 1 (inverted rotation)
	var touch_idx := _phase % n
	var goal_idx := (_phase + 1) % n
	for mi in _touch_panels:
		_set_banner(mi, ad_textures[touch_idx])
	for mi in _goal_panels:
		_set_banner(mi, ad_textures[goal_idx])

func _set_banner(mi: MeshInstance3D, tex: Texture2D) -> void:
	var mat := mi.material_override as StandardMaterial3D
	if mat == null or tex == null:
		return
	mat.albedo_texture = tex
	if mat.emission_enabled:
		mat.emission_texture = tex

	# Compute the number of horizontal repeats so each banner keeps its native aspect
	# ratio and is never stretched. The board's physical size is taken from its QuadMesh.
	var board_size := Vector2.ZERO
	if mi.mesh is QuadMesh:
		board_size = (mi.mesh as QuadMesh).size

	var board_len: float = board_size.x
	var board_h: float = board_size.y
	var tw: int = tex.get_width()
	var th: int = tex.get_height()

	if board_len > 0.0 and board_h > 0.0 and tw > 0 and th > 0:
		# One banner block spans (board_h * aspect) metres wide to keep the texture square.
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
