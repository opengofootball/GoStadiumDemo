extends Node3D

## Common Pitch Scene (common_pitch.tscn)
## PitchMesh, GroundCollision, and AdPanels are declared directly as first-class nodes
## in the scene tree (.tscn), NOT generated in GDScript.
## This script only handles optional real-time UV scrolling for the ad panels.

@export var enable_ad_boards: bool = true
@export var ad_scroll_speed: float = 2.0

var ad_materials: Array[StandardMaterial3D] = []

func _ready() -> void:
	var panels = get_node_or_null("AdPanels")
	if not enable_ad_boards:
		if panels:
			panels.visible = false
		return

	# Collect the materials declared on the scene's ad panel MeshInstances
	if panels:
		for b in panels.get_children():
			var mi = b as MeshInstance3D
			if mi and mi.material_override is StandardMaterial3D:
				var mat = mi.material_override.duplicate() as StandardMaterial3D
				mi.material_override = mat
				ad_materials.append(mat)

func _process(delta: float) -> void:
	if not enable_ad_boards:
		return
	for mat in ad_materials:
		mat.uv1_offset.x += ad_scroll_speed * delta
