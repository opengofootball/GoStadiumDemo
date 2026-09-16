extends Node3D

## Main scene for the isolated Common Pitch (real-world metres, 1 unit = 1 m).
## The modern_stadium shell is NOT loaded for now. The CommonPitch node is a fully
## self-contained module: turf + regulation lines, LED ad hoardings, corner flags,
## ground collision and the two goals (spawned by CommonPitch from its own exported
## goal_model_scene PackedScene).

@onready var world_env: WorldEnvironment = $WorldEnvironment
@onready var sun_light: DirectionalLight3D = $SunLight
@onready var walk_camera: WalkCamera = $WalkCamera
@onready var common_pitch: Node3D = $CommonPitch

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
