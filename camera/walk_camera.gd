class_name WalkCamera
extends Camera3D

@export var mouse_sensitivity: float = 0.002
@export var move_speed: float = 8.0
@export var sprint_factor: float = 3.0
@export var acceleration: float = 12.0

var _velocity: Vector3 = Vector3.ZERO
var _pitch: float = 0.0
var _yaw: float = 0.0
var _is_mouse_captured: bool = true

signal speed_changed(new_speed: float)
signal mouse_capture_changed(captured: bool)

func _ready() -> void:
	far = 350.0
	near = 0.15
	capture_mouse()
	_yaw = rotation.y
	_pitch = rotation.x

func capture_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_is_mouse_captured = true
	mouse_capture_changed.emit(true)

func release_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_is_mouse_captured = false
	mouse_capture_changed.emit(false)

func toggle_mouse() -> void:
	if _is_mouse_captured:
		release_mouse()
	else:
		capture_mouse()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_mouse"):
		toggle_mouse()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton and event.pressed:
		if not _is_mouse_captured and event.button_index == MOUSE_BUTTON_LEFT:
			# Left click back into the game window recaptures mouse
			capture_mouse()
			get_viewport().set_input_as_handled()
			return
		elif _is_mouse_captured:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				move_speed = clampf(move_speed * 1.15, 1.0, 60.0)
				speed_changed.emit(move_speed)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				move_speed = clampf(move_speed / 1.15, 1.0, 60.0)
				speed_changed.emit(move_speed)

	if _is_mouse_captured and event is InputEventMouseMotion:
		_yaw -= event.relative.x * mouse_sensitivity
		_pitch -= event.relative.y * mouse_sensitivity
		_pitch = clampf(_pitch, -deg_to_rad(89.0), deg_to_rad(89.0))
		
		rotation.y = _yaw
		rotation.x = _pitch

func _process(delta: float) -> void:
	var input_dir: Vector3 = Vector3.ZERO

	if Input.is_action_pressed("move_forward"):
		input_dir -= transform.basis.z
	if Input.is_action_pressed("move_backward"):
		input_dir += transform.basis.z
	if Input.is_action_pressed("move_left"):
		input_dir -= transform.basis.x
	if Input.is_action_pressed("move_right"):
		input_dir += transform.basis.x
	if Input.is_action_pressed("move_up"):
		input_dir += Vector3.UP
	if Input.is_action_pressed("move_down"):
		input_dir += Vector3.DOWN

	if input_dir.length_squared() > 0.001:
		input_dir = input_dir.normalized()

	var current_speed: float = move_speed
	if Input.is_action_pressed("sprint"):
		current_speed *= sprint_factor

	var target_velocity: Vector3 = input_dir * current_speed
	_velocity = _velocity.lerp(target_velocity, clampf(delta * acceleration, 0.0, 1.0))
	position += _velocity * delta

func teleport_to(new_pos: Vector3, new_yaw: float = 0.0, new_pitch: float = 0.0) -> void:
	position = new_pos
	_yaw = new_yaw
	_pitch = new_pitch
	rotation.y = _yaw
	rotation.x = _pitch
	_velocity = Vector3.ZERO
