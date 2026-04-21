extends Node3D

const LINE_HEIGHT := 0.05
const DASH_LEN := 0.25
const GAP_LEN := 0.15
const DASH_WIDTH := 0.08

var _agent: NavigationAgent3D
var _update_timer := 0.0
var _path_mat: StandardMaterial3D
var _arrow_mat: StandardMaterial3D

@onready var _line_mesh: MeshInstance3D = $LineMesh
@onready var _arrow_mesh: MeshInstance3D = $ArrowMesh

func _ready() -> void:
	_path_mat = StandardMaterial3D.new()
	_path_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_path_mat.albedo_color = Color(1.0, 0.85, 0.2, 1.0)
	_path_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	_arrow_mat = StandardMaterial3D.new()
	_arrow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_arrow_mat.albedo_color = Color(1.0, 0.6, 0.0, 1.0)
	_arrow_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	_arrow_mesh.visible = false

func setup(agent: NavigationAgent3D) -> void:
	_agent = agent

func _process(delta: float) -> void:
	if _agent == null:
		return
	_update_timer -= delta
	if _update_timer > 0.0:
		return
	_update_timer = 0.1

	if _agent.is_navigation_finished():
		_line_mesh.mesh = null
		_arrow_mesh.visible = false
	else:
		_update_visuals(_agent.get_current_navigation_path())

func _update_visuals(path: PackedVector3Array) -> void:
	if path.size() < 2:
		_line_mesh.mesh = null
		_arrow_mesh.visible = false
		return
	_line_mesh.mesh = _build_dashed_mesh(path)
	_update_arrow(path)

func _build_dashed_mesh(path: PackedVector3Array) -> ArrayMesh:
	var verts := PackedVector3Array()
	var indices := PackedInt32Array()
	var idx: int = 0

	for i in range(path.size() - 1):
		var from := Vector3(path[i].x, LINE_HEIGHT, path[i].z)
		var to := Vector3(path[i + 1].x, LINE_HEIGHT, path[i + 1].z)
		var seg_len: float = from.distance_to(to)
		if seg_len < 0.001:
			continue
		var dir := (to - from) / seg_len
		var perp := dir.cross(Vector3.UP).normalized() * (DASH_WIDTH * 0.5)

		var pos := from
		var remaining: float = seg_len
		var is_dash := true

		while remaining > 0.001:
			var step: float = DASH_LEN if is_dash else GAP_LEN
			step = minf(step, remaining)

			if is_dash:
				var end := pos + dir * step
				verts.push_back(pos - perp)
				verts.push_back(pos + perp)
				verts.push_back(end + perp)
				verts.push_back(end - perp)
				indices.push_back(idx)
				indices.push_back(idx + 1)
				indices.push_back(idx + 2)
				indices.push_back(idx)
				indices.push_back(idx + 2)
				indices.push_back(idx + 3)
				idx += 4

			pos += dir * step
			remaining -= step
			is_dash = !is_dash

	if verts.is_empty():
		return ArrayMesh.new()

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _path_mat)
	return mesh

func _update_arrow(path: PackedVector3Array) -> void:
	var dest := path[-1]
	var prev := path[-2] if path.size() >= 2 else path[0]
	var arrow_dir := Vector3(dest.x - prev.x, 0.0, dest.z - prev.z).normalized()
	if arrow_dir.length_squared() < 0.01:
		_arrow_mesh.visible = false
		return

	_arrow_mesh.mesh = _build_arrow_mesh(arrow_dir)
	_arrow_mesh.global_position = Vector3(dest.x, LINE_HEIGHT, dest.z)
	_arrow_mesh.visible = true

func _build_arrow_mesh(dir: Vector3) -> ArrayMesh:
	var right := dir.cross(Vector3.UP).normalized()

	var tip    := dir * 0.45
	var base_l := dir * 0.15 - right * 0.28
	var base_r := dir * 0.15 + right * 0.28
	var stl    := dir * 0.15 - right * 0.1
	var str_   := dir * 0.15 + right * 0.1
	var sbl    := -dir * 0.25 - right * 0.1
	var sbr    := -dir * 0.25 + right * 0.1

	var verts := PackedVector3Array([
		Vector3(tip.x,    0.0, tip.z),
		Vector3(base_l.x, 0.0, base_l.z),
		Vector3(base_r.x, 0.0, base_r.z),
		Vector3(stl.x,    0.0, stl.z),
		Vector3(str_.x,   0.0, str_.z),
		Vector3(sbl.x,    0.0, sbl.z),
		Vector3(sbr.x,    0.0, sbr.z),
	])
	var indices := PackedInt32Array([0, 1, 2, 3, 5, 4, 4, 5, 6])

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _arrow_mat)
	return mesh
