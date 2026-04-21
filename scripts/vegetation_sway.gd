extends Node3D

var _speed: float
var _amount: float
var _phase: float
var _t: float = 0.0

func _ready() -> void:
	_speed = randf_range(0.5, 1.2)
	_amount = randf_range(0.015, 0.04)
	_phase = randf_range(0.0, TAU)

func _process(delta: float) -> void:
	_t += delta
	rotation.z = sin(_t * _speed + _phase) * _amount
	rotation.x = sin(_t * _speed * 0.7 + _phase + 1.0) * _amount * 0.4
