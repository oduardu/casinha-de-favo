extends Node3D

const LINE_HEIGHT := 0.05
const DASH_LEN := 0.25
const GAP_LEN := 0.15
const DASH_WIDTH := 0.12

var _agent: NavigationAgent3D
var _update_timer := 0.0
var _path_mat: StandardMaterial3D
var _arrow_mat: StandardMaterial3D
var _arrow_base_mat: StandardMaterial3D
## Cache do path anterior para evitar rebuild desnecessário
var _path_cache: PackedVector3Array = PackedVector3Array()
## True quando a navegação estava finalizada no frame anterior
var _navegacao_finalizada_cache: bool = true

@onready var _line_mesh: MeshInstance3D = $LineMesh
@onready var _arrow_mesh: MeshInstance3D = $ArrowMesh

func _ready() -> void:
	_path_mat = StandardMaterial3D.new()
	_path_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_path_mat.albedo_color = Color(0.95, 0.75, 0.22, 0.95)
	_path_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	_arrow_mat = StandardMaterial3D.new()
	_arrow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_arrow_mat.albedo_color = Color(0.99, 0.80, 0.33, 1.0)
	_arrow_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	_arrow_base_mat = StandardMaterial3D.new()
	_arrow_base_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_arrow_base_mat.albedo_color = Color(0.60, 0.40, 0.10, 1.0)
	_arrow_base_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	_arrow_mesh.visible = false

func setup(agent: NavigationAgent3D) -> void:
	_agent = agent

func _process(delta: float) -> void:
	if _agent == null:
		return
	_update_timer -= delta
	if _update_timer > 0.0:
		return
	_update_timer = 0.3

	if _agent.is_navigation_finished():
		if not _navegacao_finalizada_cache:
			_line_mesh.mesh = null
			_arrow_mesh.visible = false
			_path_cache = PackedVector3Array()
			_navegacao_finalizada_cache = true
	else:
		_navegacao_finalizada_cache = false
		var path_atual := _agent.get_current_navigation_path()
		if path_atual != _path_cache:
			_path_cache = path_atual
			_update_visuals(path_atual)

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
	_arrow_mesh.global_position = Vector3(dest.x, LINE_HEIGHT + 0.02, dest.z)
	_arrow_mesh.visible = true

func _build_arrow_mesh(dir: Vector3) -> ArrayMesh:
	var right := dir.cross(Vector3.UP).normalized()

	# Camada de base escura + camada de topo clara para simular profundidade 3D
	var tip_base    := dir * 0.52
	var base_l_base := dir * 0.18 - right * 0.34
	var base_r_base := dir * 0.18 + right * 0.34
	var stl_base    := dir * 0.16 - right * 0.14
	var str_base    := dir * 0.16 + right * 0.14
	var sbl_base    := -dir * 0.30 - right * 0.14
	var sbr_base    := -dir * 0.30 + right * 0.14

	var tip_top    := dir * 0.46
	var base_l_top := dir * 0.15 - right * 0.29
	var base_r_top := dir * 0.15 + right * 0.29
	var stl_top    := dir * 0.14 - right * 0.11
	var str_top    := dir * 0.14 + right * 0.11
	var sbl_top    := -dir * 0.24 - right * 0.11
	var sbr_top    := -dir * 0.24 + right * 0.11

	var y_base := 0.0
	var y_top := 0.035

	var verts_base := PackedVector3Array([
		Vector3(tip_base.x,    y_base, tip_base.z),    # 0
		Vector3(base_l_base.x, y_base, base_l_base.z), # 1
		Vector3(base_r_base.x, y_base, base_r_base.z), # 2
		Vector3(stl_base.x,    y_base, stl_base.z),    # 3
		Vector3(str_base.x,    y_base, str_base.z),    # 4
		Vector3(sbl_base.x,    y_base, sbl_base.z),    # 5
		Vector3(sbr_base.x,    y_base, sbr_base.z),    # 6
	])
	var verts_top := PackedVector3Array([
		Vector3(tip_top.x,     y_top, tip_top.z),      # 7
		Vector3(base_l_top.x,  y_top, base_l_top.z),   # 8
		Vector3(base_r_top.x,  y_top, base_r_top.z),   # 9
		Vector3(stl_top.x,     y_top, stl_top.z),      # 10
		Vector3(str_top.x,     y_top, str_top.z),      # 11
		Vector3(sbl_top.x,     y_top, sbl_top.z),      # 12
		Vector3(sbr_top.x,     y_top, sbr_top.z),      # 13
	])

	var indices := PackedInt32Array([
		0, 1, 2, 3, 5, 4, 4, 5, 6
	])
	var arrays_base: Array = []
	arrays_base.resize(Mesh.ARRAY_MAX)
	arrays_base[Mesh.ARRAY_VERTEX] = verts_base
	arrays_base[Mesh.ARRAY_INDEX] = indices

	var arrays_top: Array = []
	arrays_top.resize(Mesh.ARRAY_MAX)
	arrays_top[Mesh.ARRAY_VERTEX] = verts_top
	arrays_top[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays_base)
	mesh.surface_set_material(0, _arrow_base_mat)
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays_top)
	mesh.surface_set_material(1, _arrow_mat)
	return mesh
