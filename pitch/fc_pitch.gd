extends Node3D

## FC Pitch Scene (fc_pitch.tscn)
## All MeshInstance3D nodes, materials, shaders, and collision shapes are declared
## directly in the .tscn scene file and inspector resources, NOT generated at runtime.
## GDScript only handles real-time ad banner scrolling (if enabled).

@export var enable_ad_boards: bool = true
@export var ad_scroll_speed: float = 2.0

var ad_materials: Array[StandardMaterial3D] = []

func _ready() -> void:
	if not enable_ad_boards:
		var panels = get_node_or_null("AdPanels")
		if panels:
			panels.visible = false
		return

	# Collect the materials declared on the scene's ad panel MeshInstances
	var panels = get_node_or_null("AdPanels")
	if panels:
		for b in panels.get_children():
			var mi = b as MeshInstance3D
			if mi and mi.material_override is StandardMaterial3D:
				# Duplicate per-instance so each board scrolls its own UV if needed
				var mat = mi.material_override.duplicate() as StandardMaterial3D
				mi.material_override = mat
				ad_materials.append(mat)

func _process(delta: float) -> void:
	if not enable_ad_boards:
		return
	for mat in ad_materials:
		mat.uv1_offset.x += ad_scroll_speed * delta
