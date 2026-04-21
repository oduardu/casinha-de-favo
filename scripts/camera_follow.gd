extends Camera3D

@export var smoothing: float = 8.0
@export var zoom_min: float = 5.0
@export var zoom_max: float = 14.0
@export var zoom_speed: float = 1.2

const AZIMUTH_DEG := 45.0
const ELEV_CLOSE_DEG := 35.0
const ELEV_FAR_DEG := 65.0
const DISTANCE := 14.0

var _target: Node3D
var _target_size: float
var _cur_elevation: float

func _ready() -> void:
	_target = get_node("../Player")
	_target_size = size
	_cur_elevation = ELEV_CLOSE_DEG

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_target_size = clampf(_target_size - zoom_speed, zoom_min, zoom_max)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_target_size = clampf(_target_size + zoom_speed, zoom_min, zoom_max)

func _process(delta: float) -> void:
	size = lerpf(size, _target_size, smoothing * delta)

	var zoom_t: float = (_target_size - zoom_min) / (zoom_max - zoom_min)
	var target_elev: float = lerpf(ELEV_CLOSE_DEG, ELEV_FAR_DEG, zoom_t)
	_cur_elevation = lerpf(_cur_elevation, target_elev, smoothing * delta)

	var elev_rad: float = deg_to_rad(_cur_elevation)
	var azim_rad: float = deg_to_rad(AZIMUTH_DEG)
	var offset := Vector3(
		DISTANCE * cos(elev_rad) * cos(azim_rad),
		DISTANCE * sin(elev_rad),
		DISTANCE * cos(elev_rad) * sin(azim_rad)
	)

	global_position = global_position.lerp(_target.global_position + offset, smoothing * delta)
	look_at(_target.global_position + Vector3(0, 0.9, 0), Vector3.UP)
