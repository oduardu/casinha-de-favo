extends Node3D

# Coordenadas axiais dos 7 tiles de grama: centro + anel de 6 vizinhos
# Esses são os únicos tiles onde o jogador pode andar
const GRASS_COORDS := [
	Vector2i( 0,  0),
	Vector2i( 1,  0), Vector2i( 0,  1), Vector2i(-1,  1),
	Vector2i(-1,  0), Vector2i( 0, -1), Vector2i( 1, -1),
]

# Fator de escala dos tiles — aumenta o tamanho visual e espaçamento dos hexágonos
const TILE_SCALE := 3.0

var _grass_scene: PackedScene
var _water_scene: PackedScene
var _farm_tile_scene: PackedScene  # Cena do tile de fazenda onde o jogador pode plantar

func _ready() -> void:
	# Carrega os modelos de tile uma única vez para reutilizar nas instâncias
	_grass_scene = load("res://obj/kenney_hexagonal/grass.glb")
	_water_scene = load("res://obj/kenney_hexagonal/water.glb")
	_farm_tile_scene = load("res://scenes/farm_tile.tscn")
	_build_map()        # Cria todos os tiles do mapa
	_setup_collision()  # Cria o chão físico para o jogador colidir
	_setup_navigation() # Define a área navegável para o pathfinding
	_place_farm_tiles() # Posiciona os tiles de fazenda no mapa e conecta ao player
	_setup_hotbar()     # Instancia a UI da hotbar numa CanvasLayer
	_dar_itens_iniciais() # Dá flores iniciais ao jogador para teste
	# Conecta o PathVisualizer ao agente de navegação do jogador
	var agent: NavigationAgent3D = $Player.get_node("NavigationAgent3D")
	$PathVisualizer.setup(agent)

# Converte coordenadas axiais (q, r) para posição no mundo 3D (XZ)
# Hexágono pointy-top: centros adjacentes ficam TILE_SCALE unidades de distância
func _axial_to_world(q: int, r: int) -> Vector3:
	return Vector3(
		(float(q) + r * 0.5) * TILE_SCALE,
		0.0,
		r * sqrt(3.0) * 0.5 * TILE_SCALE
	)

# Retorna a distância em passos hexagonais entre a origem e o tile (q, r)
func _hex_dist(q: int, r: int) -> int:
	return (abs(q) + abs(r) + abs(q + r)) / 2

func _build_map() -> void:
	# Monta um set de lookup rápido para saber quais coords são grama
	var grass_set := {}
	for c: Vector2i in GRASS_COORDS:
		grass_set[c] = true

	# Itera sobre um grid quadrado e descarta tiles fora do raio 5 (forma hexagonal)
	for q in range(-6, 7):
		for r in range(-6, 7):
			if _hex_dist(q, r) > 5:
				continue
			var coord := Vector2i(q, r)
			var xz := _axial_to_world(q, r)
			# Tiles dentro do GRASS_COORDS viram grama, os demais viram água
			var scene: PackedScene = _grass_scene if coord in grass_set else _water_scene
			var inst: Node3D = scene.instantiate() as Node3D
			# Offset Y negativo para que o topo do tile fique exatamente em y=0
			inst.position = Vector3(xz.x, -0.2 * TILE_SCALE, xz.z)
			# Escala uniforme para que os hexágonos fiquem proporcionais ao player
			inst.scale = Vector3.ONE * TILE_SCALE
			add_child(inst)

func _setup_collision() -> void:
	# Cria um StaticBody3D plano que serve de chão físico para o jogador
	# Cobre toda a ilha de grama (7 tiles com TILE_SCALE=3 ficam dentro de 10x10)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(10.0, 0.1, 10.0)
	cs.shape = box
	cs.position = Vector3(0.0, -0.05, 0.0) # Centralizado em y=0 (topo do chão)
	body.add_child(cs)
	add_child(body)

func _place_farm_tiles() -> void:
	# Coordenadas axiais dos tiles de grama que receberão um local de plantio
	# Evita o centro (0,0) pois é onde o jogador nasce
	var coordenadas_fazenda := [
		Vector2i(1, 0),   # Tile à direita do centro
	]

	var player: CharacterBody3D = $Player

	for coord: Vector2i in coordenadas_fazenda:
		var pos := _axial_to_world(coord.x, coord.y)
		var tile: Node3D = _farm_tile_scene.instantiate() as Node3D
		tile.position = Vector3(pos.x, 0.0, pos.z)  # y=0 — topo da superfície do chão
		add_child(tile)

		# Conecta os sinais do tile ao player para que ele reaja à proximidade e ao plantio
		tile.jogador_entrou.connect(func(): player._ao_entrar_tile(tile))
		tile.jogador_saiu.connect(player._ao_sair_tile)

func _setup_hotbar() -> void:
	# Cria uma CanvasLayer para garantir que a hotbar renderize em cima de tudo
	var canvas := CanvasLayer.new()
	canvas.name = "UILayer"
	var hotbar_cena: PackedScene = load("res://scenes/hotbar.tscn")
	var hotbar: Control = hotbar_cena.instantiate() as Control
	canvas.add_child(hotbar)
	add_child(canvas)

func _dar_itens_iniciais() -> void:
	# Carrega o item flor e adiciona 5 unidades ao inventário do jogador para teste
	var flor: Item = load("res://resources/flor.tres")
	if flor == null:
		push_warning("world.gd: não encontrou res://resources/flor.tres")
		return
	$Player.inventario.adicionar_item(flor, 5)

func _setup_navigation() -> void:
	# Cria o NavigationMesh manualmente como um hexágono que cobre a ilha de grama
	var nm := NavigationMesh.new()
	nm.agent_radius = 0.3
	nm.agent_height = 1.8
	nm.agent_max_slope = 15.0
	nm.cell_size = 0.25
	nm.cell_height = 0.2

	# Hexágono de raio R=5.0 cobre os 7 tiles escalados (anel externo chega em ~4.5 unidades)
	var R := 5.0
	var verts := PackedVector3Array()
	for i in 6:
		var a := deg_to_rad(90.0 + i * 60.0)
		verts.append(Vector3(R * cos(a), 0.0, R * sin(a)))
	nm.vertices = verts
	nm.add_polygon(PackedInt32Array([0, 1, 2, 3, 4, 5]))
	$NavigationRegion3D.navigation_mesh = nm
