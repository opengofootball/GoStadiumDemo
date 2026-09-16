extends Node3D

## Modern Stadium scene
## Wraps the resized (uniform 0.024) modern_stadium.glb shell around the shared
## CommonPitch module. The stadium's own grass, field markings and perimeter plates
## are hidden so they do not double-draw over (or occlude) the CommonPitch turf,
## its shader-drawn regulation lines, or the LED ad hoardings.

@export_file("*.glb") var stadium_scene: String = "res://stadiums/modern_stadium/modern_stadium.glb"

# Offset applied to the imported model so its pitch center lands on the
# CommonPitch origin (0,0,0). The resized model (uniform 0.024) no longer contains
# the grass/line meshes, so this is derived from the original pitch-center world
# position (X=1251.05, Y=-59.055, Z=-2062.93) scaled by 0.024 and negated.
@export var model_offset: Vector3 = Vector3(-30.025, 2.16, 49.510)

# Material names for the stadium's own turf, field markings and perimeter plates.
# The resized model (uniform 0.024) dropped the grass/line meshes entirely, so these
# only guard against re-appearing if a fuller model export is used later.
const HIDE_MATERIALS := [
	"trawa_03_1", "auto_1", "auto_30",           # grass + field markings
	"auto_25", "auto_15", "auto_26", "auto_27",  # perimeter plates / run-off boards
	"auto_36", "auto_37", "auto_38", "auto_39",
]

# Mesh node names used by the resized model's grass / markings / perimeter plates.
const HIDE_MESH_NAMES := []

func _ready() -> void:
	_build_stadium()

func _build_stadium() -> void:
	var existing := get_node_or_null("StadiumModel")
	if existing:
		existing.queue_free()

	if not ResourceLoader.exists(stadium_scene):
		push_warning("ModernStadium: stadium model not found: %s" % stadium_scene)
		return

	var scn := load(stadium_scene) as PackedScene
	if scn == null:
		push_warning("ModernStadium: could not load stadium model.")
		return

	var model := scn.instantiate() as Node3D
	model.name = "StadiumModel"
	add_child(model)
	model.position = model_offset

	_hide_pitch_geometry(model)

func _hide_pitch_geometry(root: Node) -> void:
	for child in root.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		for s in range(mi.mesh.get_surface_count()):
			var mat := mi.mesh.surface_get_material(s)
			if mat and _is_pitch_material(mat.resource_name):
				mi.visible = false
				break

func _is_pitch_material(mat_name: String) -> bool:
	var lower := mat_name.to_lower()
	for hidden in HIDE_MATERIALS:
		if hidden in lower:
			return true
	return false
