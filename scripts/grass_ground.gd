extends MultiMeshInstance3D

@export var tile_size: float = 1.0
@export var grid_size: int = 40

func _ready() -> void:
	multimesh.instance_count = grid_size * grid_size
	var half := grid_size * tile_size * 0.5 - tile_size * 0.5
	var idx := 0
	for x in grid_size:
		for z in grid_size:
			var pos := Vector3(x * tile_size - half, 0.0, z * tile_size - half)
			multimesh.set_instance_transform(idx, Transform3D(Basis(), pos))
			idx += 1
