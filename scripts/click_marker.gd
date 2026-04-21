extends Node3D

const DURATION := 0.7

var _time := 0.0
var _active := false

@onready var _mat: StandardMaterial3D = $MeshInstance3D.get_surface_override_material(0)

func show_at(pos: Vector3) -> void:
	global_position = Vector3(pos.x, 0.02, pos.z)
	scale = Vector3.ONE
	_time = 0.0
	_active = true
	visible = true

func _process(delta: float) -> void:
	if not _active:
		return
	_time += delta
	var t: float = clamp(_time / DURATION, 0.0, 1.0)
	if t >= 1.0:
		_active = false
		visible = false
		return
	scale = Vector3(1.0 + t * 0.8, 1.0, 1.0 + t * 0.8)
	_mat.albedo_color.a = 1.0 - t
