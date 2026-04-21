extends Node3D

# --- CONFIGURAÇÃO ---

## Raio em tiles da área externa bloqueada ao redor da grade inicial
@export var raio_mundo_externo: int = 8

## Preço base em moedas; o custo real de um tile externo é preco_base * dist²
@export var preco_base: int = 10

## Moedas iniciais adicionadas ao GerenciadorMundo na primeira inicialização do jogo
@export var moedas_debug: int = 500


# --- CONSTANTES ---

## Escala de renderização dos tiles (3× o tamanho original do modelo)
const TILE_SCALE := 3.0

## Limite mínimo de q na grade inicial 4×4
const Q_MIN := -1

## Limite máximo de q na grade inicial 4×4
const Q_MAX := 2

## Limite mínimo de r na grade inicial 4×4
const R_MIN := -1

## Limite máximo de r na grade inicial 4×4
const R_MAX := 2


# --- ESTADO ---

## PackedScene do HexTile carregada em _ready (res://scenes/hex_tile.tscn)
var _hex_tile_cena: PackedScene = null

## PackedScene do FarmTile carregada em _ready (res://scenes/farm_tile.tscn)
var _farm_tile_cena: PackedScene = null

## Script da Colmeia carregado em _ready para ser aplicado em Node3D instanciados
var _colmeia_cena_script: Script = null

## Script do NPC carregado em _ready para ser aplicado em Node3D instanciados
var _npc_script: Script = null

## Dicionário de Vector2i → HexTile, mapeia coordenadas axiais para os nós de tile
var _tiles_por_coord: Dictionary = {}

## Deslocamento em unidades de mundo para centralizar a grade no ponto de origem
var _deslocamento_centro: Vector3 = Vector3.ZERO

## Extremidade mínima (x, z) da grade navegável, usada para construir a NavigationMesh
var _navmesh_min: Vector2 = Vector2.ZERO

## Extremidade máxima (x, z) da grade navegável, usada para construir a NavigationMesh
var _navmesh_max: Vector2 = Vector2.ZERO

## StaticBody3D plano que serve de chão sob a área jogável; recriado ao comprar tiles
var _piso_corpo: StaticBody3D = null


# --- CICLO DE VIDA ---

## Salva ao fechar a janela, já que GerenciadorMundo não é um Node
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		GerenciadorMundo.salvar()


func _ready() -> void:
	_carregar_recursos()
	GerenciadorMundo.carregar()
	# Garante que o jogador começa com pelo menos moedas_debug moedas
	if GerenciadorMundo.moedas < moedas_debug:
		GerenciadorMundo.moedas = moedas_debug
	_calcular_deslocamento()
	_gerar_grade_inicial()
	_gerar_tiles_externos()
	_aplicar_estado_salvo()
	_reconstruir_navmesh()
	_criar_piso()
	_colocar_edificios()
	_colocar_farm_tiles()
	_setup_hotbar()
	_dar_itens_iniciais()

	# Conecta o PathVisualizer ao NavigationAgent3D do jogador
	var agente = $Player.get_node("NavigationAgent3D")
	if agente != null and $PathVisualizer != null:
		$PathVisualizer.setup(agente)


# --- CONFIGURAÇÃO ---

## Carrega todas as cenas e scripts necessários; falhas emitem push_error mas não travam o jogo
func _carregar_recursos() -> void:
	if ResourceLoader.exists("res://scenes/hex_tile.tscn"):
		_hex_tile_cena = load("res://scenes/hex_tile.tscn")
	else:
		push_error("mundo.gd: cena hex_tile.tscn não encontrada em res://scenes/")

	if ResourceLoader.exists("res://scenes/farm_tile.tscn"):
		_farm_tile_cena = load("res://scenes/farm_tile.tscn")
	else:
		push_warning("mundo.gd: cena farm_tile.tscn não encontrada — farm tiles não serão criados.")

	if ResourceLoader.exists("res://scripts/colmeia.gd"):
		_colmeia_cena_script = load("res://scripts/colmeia.gd")
	else:
		push_warning("mundo.gd: colmeia.gd não encontrado.")

	if ResourceLoader.exists("res://scripts/npc.gd"):
		_npc_script = load("res://scripts/npc.gd")
	else:
		push_warning("mundo.gd: npc.gd não encontrado.")


# --- UTILITÁRIOS ---

## Converte coordenadas axiais (q, r) para posição de mundo sem aplicar o deslocamento central
func _axial_para_mundo_raw(q: int, r: int) -> Vector3:
	var x := (q + r * 0.5) * TILE_SCALE
	var z := r * sqrt(3.0) * 0.5 * TILE_SCALE
	return Vector3(x, 0.0, z)


## Converte coordenadas axiais (q, r) para posição de mundo centralizada na origem
func _axial_para_mundo(q: int, r: int) -> Vector3:
	return _axial_para_mundo_raw(q, r) - _deslocamento_centro


## Calcula a distância em tiles entre duas coordenadas axiais usando a fórmula cúbica
func _hex_dist(a: Vector2i, b: Vector2i) -> int:
	return (abs(a.x - b.x) + abs(a.y - b.y) + abs(a.x + a.y - b.x - b.y)) / 2


## Retorna true se (q, r) está dentro dos limites da grade inicial 4×4
func _esta_no_grid_inicial(q: int, r: int) -> bool:
	return q >= Q_MIN and q <= Q_MAX and r >= R_MIN and r <= R_MAX


## Retorna o HexTile na coordenada axial 'coord', ou null se não existir
func obter_tile(coord: Vector2i) -> HexTile:
	return _tiles_por_coord.get(coord, null)


# --- GERAÇÃO DO MUNDO ---

## Calcula _deslocamento_centro como a média das posições brutas de todos os tiles iniciais,
## garantindo que a grade fique centrada na origem do mundo
func _calcular_deslocamento() -> void:
	var soma := Vector3.ZERO
	var contagem := 0
	for q in range(Q_MIN, Q_MAX + 1):
		for r in range(R_MIN, R_MAX + 1):
			soma += _axial_para_mundo_raw(q, r)
			contagem += 1
	if contagem > 0:
		_deslocamento_centro = soma / float(contagem)
		_deslocamento_centro.y = 0.0


## Gera os 16 tiles jogáveis da grade inicial (grass, desbloqueados)
## e atualiza os limites da navmesh
func _gerar_grade_inicial() -> void:
	_navmesh_min = Vector2(INF, INF)
	_navmesh_max = Vector2(-INF, -INF)

	for q in range(Q_MIN, Q_MAX + 1):
		for r in range(R_MIN, R_MAX + 1):
			_criar_tile(Vector2i(q, r), "grass", true, 0)
			var pos := _axial_para_mundo(q, r)
			_navmesh_min.x = minf(_navmesh_min.x, pos.x)
			_navmesh_min.y = minf(_navmesh_min.y, pos.z)
			_navmesh_max.x = maxf(_navmesh_max.x, pos.x)
			_navmesh_max.y = maxf(_navmesh_max.y, pos.z)


## Gera os tiles externos bloqueados (grass) ao redor da grade inicial,
## com custo proporcional à distância ao centro
func _gerar_tiles_externos() -> void:
	var margem := raio_mundo_externo + 1
	for q in range(-margem, margem + 1):
		for r in range(-margem, margem + 1):
			if _esta_no_grid_inicial(q, r):
				continue
			var coord := Vector2i(q, r)
			var dist := _hex_dist(coord, Vector2i(0, 0))
			if dist > raio_mundo_externo:
				continue
			var custo := preco_base * dist * dist
			_criar_tile(coord, "grass", false, custo)


## Instancia um HexTile, configura suas propriedades e o adiciona à cena e ao dicionário.
## Para tiles bloqueados, conecta os sinais de compra ao Player e ao mundo.
func _criar_tile(coord: Vector2i, tipo: String, eh_desbloqueado: bool, custo: int) -> void:
	if _hex_tile_cena == null:
		return

	var tile := _hex_tile_cena.instantiate() as HexTile
	if tile == null:
		push_error("mundo.gd: falha ao instanciar HexTile para coord %s." % str(coord))
		return

	tile.coordenada = coord
	tile.tipo = tipo
	tile.desbloqueado = eh_desbloqueado
	tile.preco = custo
	tile.position = _axial_para_mundo(coord.x, coord.y)
	# A posição y do modelo é tratada internamente pelo HexTile (_ready aplica -0.2*TILE_SCALE)

	add_child(tile)
	_tiles_por_coord[coord] = tile

	# Conecta sinais de interação de compra apenas para tiles bloqueados
	if not eh_desbloqueado:
		var jogador := get_node_or_null("Player")
		if jogador != null:
			if jogador.has_method("_ao_entrar_hex_compravel"):
				tile.jogador_entrou_compravel.connect(
					func() -> void: jogador._ao_entrar_hex_compravel(tile)
				)
			if jogador.has_method("_ao_sair_hex_compravel"):
				tile.jogador_saiu_compravel.connect(jogador._ao_sair_hex_compravel)
		tile.comprado.connect(_ao_tile_comprado)


## Aplica o estado do save: desbloqueia sem custo os tiles já comprados anteriormente
func _aplicar_estado_salvo() -> void:
	for entrada in GerenciadorMundo.hexagonos_desbloqueados:
		if not entrada is Dictionary:
			continue
		var q: int = entrada.get("q", 0)
		var r: int = entrada.get("r", 0)
		var coord := Vector2i(q, r)
		var tile := obter_tile(coord)
		if tile != null and not tile.desbloqueado:
			# Desbloqueia diretamente sem emitir sinal de compra (evita re-salvar)
			tile.desbloqueado = true
			tile._aplicar_cor_normal()
			if is_instance_valid(tile._corpo_bloqueio):
				tile._corpo_bloqueio.queue_free()
				tile._corpo_bloqueio = null
			if is_instance_valid(tile._area_compra):
				tile._area_compra.queue_free()
				tile._area_compra = null
			if is_instance_valid(tile._label_preco):
				tile._label_preco.visible = false
			if is_instance_valid(tile._label_erro):
				tile._label_erro.visible = false


# --- GRADE INICIAL ---

## (Veja _gerar_grade_inicial acima — seção separada para clareza)


# --- TILES EXTERNOS ---

## (Veja _gerar_tiles_externos acima — seção separada para clareza)


# --- COLISÃO E NAVEGAÇÃO ---

## Cria o chão plano sob a grade jogável: colisão (StaticBody3D) + malha visual verde
## que cobre quaisquer brechas entre os hexágonos
func _criar_piso() -> void:
	# Remove chão anterior se existir (ex.: após compra de tile)
	if is_instance_valid(_piso_corpo):
		_piso_corpo.queue_free()
		_piso_corpo = null

	_piso_corpo = StaticBody3D.new()
	_piso_corpo.name = "PisoJogavel"

	var cx: float = (_navmesh_min.x + _navmesh_max.x) * 0.5
	var cz: float = (_navmesh_min.y + _navmesh_max.y) * 0.5
	var largura: float = (_navmesh_max.x - _navmesh_min.x) + TILE_SCALE * 2.0
	var profund: float = (_navmesh_max.y - _navmesh_min.y) + TILE_SCALE * 2.0

	# Colisão: fino BoxShape3D logo abaixo de y=0
	var forma := BoxShape3D.new()
	forma.size = Vector3(largura, 0.1, profund)
	var colisao := CollisionShape3D.new()
	colisao.shape = forma
	colisao.position = Vector3(cx, -0.05, cz)
	_piso_corpo.add_child(colisao)

	# Visual: PlaneMesh verde-grama cobrindo toda a área + margem extra
	# Fica em y=-0.30 para aparecer nas brechas entre tiles sem cobri-los
	var mesh_piso := MeshInstance3D.new()
	mesh_piso.name = "MeshPisoVisual"
	var plano := PlaneMesh.new()
	plano.size = Vector2(largura * 1.6, profund * 1.6)
	mesh_piso.mesh = plano
	var mat_piso := StandardMaterial3D.new()
	mat_piso.albedo_color = Color(0.22, 0.52, 0.18)  # Verde grama
	mesh_piso.material_override = mat_piso
	mesh_piso.position = Vector3(cx, -0.30, cz)
	_piso_corpo.add_child(mesh_piso)

	add_child(_piso_corpo)


## Reconstrói a NavigationMesh retangular que cobre a área jogável atual,
## adicionando uma margem de TILE_SCALE * 0.6 para o agente não ficar preso nas bordas
func _reconstruir_navmesh() -> void:
	var nav_region := get_node_or_null("NavigationRegion3D") as NavigationRegion3D
	if nav_region == null:
		push_warning("mundo.gd: NavigationRegion3D não encontrado.")
		return

	var margem := TILE_SCALE * 0.6
	var x_min := _navmesh_min.x - margem
	var x_max := _navmesh_max.x + margem
	var z_min := _navmesh_min.y - margem
	var z_max := _navmesh_max.y + margem

	# Constrói a NavigationMesh com um polígono retangular simples
	var navmesh := NavigationMesh.new()
	navmesh.cell_height = 0.1

	# Os vértices definem o retângulo no plano XZ
	navmesh.vertices = PackedVector3Array([
		Vector3(x_min, 0.0, z_min),
		Vector3(x_max, 0.0, z_min),
		Vector3(x_max, 0.0, z_max),
		Vector3(x_min, 0.0, z_max),
	])

	# Um único polígono (quad) usando os 4 vértices
	navmesh.add_polygon(PackedInt32Array([0, 1, 2, 3]))

	nav_region.navigation_mesh = navmesh


# --- EDIFICIOS ---

## Ponto de entrada: cria todos os edifícios do mundo
func _colocar_edificios() -> void:
	_criar_casa()
	_criar_colmeia()
	_criar_npc()


## Constrói a casa com CSGBox3D (corpo + telhado + porta + chaminé) e colisão precisa.
## Ocupa visualmente os tiles (2,2) e (2,1) — base 2.8×2.8, telhado em duas águas.
func _criar_casa() -> void:
	var pos_casa := _axial_para_mundo(Q_MAX, R_MAX)  # Tile (2, 2)

	# Raiz visual da casa; todos os elementos são filhos deste nó
	var casa := Node3D.new()
	casa.name = "Casa"
	casa.position = pos_casa
	add_child(casa)

	# --- Paredes ---
	var corpo := CSGBox3D.new()
	corpo.size = Vector3(2.8, 2.5, 2.8)
	corpo.position.y = 1.25  # Base apoiada em y=0
	var mat_parede := StandardMaterial3D.new()
	mat_parede.albedo_color = Color(0.95, 0.90, 0.80)  # Creme
	corpo.material_override = mat_parede
	casa.add_child(corpo)

	# Material compartilhado do telhado (terracota)
	var mat_teto := StandardMaterial3D.new()
	mat_teto.albedo_color = Color(0.65, 0.25, 0.15)

	# --- Telhado esquerdo (inclinação ≈ 46°) ---
	# Dois painéis formam o telhado em duas águas; ângulo calculado para ridge em y≈4.0
	var teto_esq := CSGBox3D.new()
	teto_esq.size = Vector3(2.15, 0.18, 3.2)
	teto_esq.rotation_degrees.z = 46.0
	teto_esq.position = Vector3(-0.7, 3.25, 0.0)
	teto_esq.material_override = mat_teto
	casa.add_child(teto_esq)

	# --- Telhado direito ---
	var teto_dir := CSGBox3D.new()
	teto_dir.size = Vector3(2.15, 0.18, 3.2)
	teto_dir.rotation_degrees.z = -46.0
	teto_dir.position = Vector3(0.7, 3.25, 0.0)
	teto_dir.material_override = mat_teto
	casa.add_child(teto_dir)

	# --- Porta (face frontal z negativo) ---
	var porta := CSGBox3D.new()
	porta.size = Vector3(0.75, 1.5, 0.25)
	porta.position = Vector3(0.0, 0.75, -1.53)
	var mat_porta := StandardMaterial3D.new()
	mat_porta.albedo_color = Color(0.42, 0.26, 0.10)  # Madeira escura
	porta.material_override = mat_porta
	casa.add_child(porta)

	# --- Chaminé ---
	var chamine := CSGBox3D.new()
	chamine.size = Vector3(0.38, 1.1, 0.38)
	chamine.position = Vector3(0.85, 3.65, 0.65)
	var mat_chamine := StandardMaterial3D.new()
	mat_chamine.albedo_color = Color(0.48, 0.33, 0.23)  # Tijolo
	chamine.material_override = mat_chamine
	casa.add_child(chamine)

	# --- Colisão física (separada do visual, tamanho do corpo principal) ---
	var fis := StaticBody3D.new()
	fis.name = "CasaColisao"
	var forma := BoxShape3D.new()
	forma.size = Vector3(2.8, 4.2, 2.8)
	var col := CollisionShape3D.new()
	col.shape = forma
	col.position.y = 2.1
	fis.add_child(col)
	casa.add_child(fis)


## Instancia a Colmeia no tile (0, 0) e conecta seus sinais de proximidade ao Player
func _criar_colmeia() -> void:
	if _colmeia_cena_script == null:
		push_warning("mundo.gd: script colmeia.gd não carregado — colmeia não será criada.")
		return

	var colmeia := Node3D.new()
	colmeia.name = "Colmeia"
	colmeia.set_script(_colmeia_cena_script)
	colmeia.position = _axial_para_mundo(0, 0)
	colmeia.position.y = 0.0
	add_child(colmeia)

	# Conecta os sinais de proximidade da colmeia ao Player
	var jogador := get_node_or_null("Player")
	if jogador != null:
		if colmeia.has_signal("jogador_entrou_colmeia") and jogador.has_method("_ao_entrar_colmeia_area"):
			colmeia.jogador_entrou_colmeia.connect(
				func() -> void: jogador._ao_entrar_colmeia_area(colmeia)
			)
		if colmeia.has_signal("jogador_saiu_colmeia") and jogador.has_method("_ao_sair_colmeia_area"):
			colmeia.jogador_saiu_colmeia.connect(jogador._ao_sair_colmeia_area)


## Instancia um Node3D com o script NPC e o posiciona no tile (2, 1)
func _criar_npc() -> void:
	if _npc_script == null:
		push_warning("mundo.gd: script npc.gd não carregado — NPC não será criado.")
		return

	var npc := Node3D.new()
	npc.name = "NPC"
	npc.set_script(_npc_script)
	npc.position = _axial_para_mundo(Q_MAX, R_MAX - 1)  # (2, 1)
	npc.position.y = 0.0
	add_child(npc)


# --- FARM TILES ---

## Instancia o FarmTile em (1, -1) e conecta seus sinais ao Player
func _colocar_farm_tiles() -> void:
	if _farm_tile_cena == null:
		push_warning("mundo.gd: farm_tile.tscn não carregado — farm tiles não serão criados.")
		return

	var jogador := get_node_or_null("Player")

	var farm_tile = _farm_tile_cena.instantiate()
	farm_tile.name = "FarmTile_1_neg1"
	farm_tile.position = _axial_para_mundo(1, -1)
	farm_tile.position.y = 0.0
	add_child(farm_tile)

	# Conecta os sinais de entrada/saída do farm tile ao Player
	# jogador_entrou não passa o tile como argumento — passamos farm_tile via closure
	if jogador != null:
		if farm_tile.has_signal("jogador_entrou") and jogador.has_method("_ao_entrar_tile"):
			farm_tile.jogador_entrou.connect(
				func() -> void: jogador._ao_entrar_tile(farm_tile)
			)
		if farm_tile.has_signal("jogador_saiu") and jogador.has_method("_ao_sair_tile"):
			farm_tile.jogador_saiu.connect(jogador._ao_sair_tile)


# --- SAVE/LOAD ---

## (Save/Load é delegado ao autoload GerenciadorMundo — veja gerenciador_mundo.gd)


# --- COMPRA DE HEX ---

## Chamado quando um tile externo é comprado com sucesso.
## Expande os limites da navmesh e reconstrói o chão e a navegação.
func _ao_tile_comprado(_custo: int) -> void:
	# Recalcula os limites incluindo todos os tiles desbloqueados
	for coord in _tiles_por_coord:
		var tile := _tiles_por_coord[coord] as HexTile
		if tile.desbloqueado:
			var pos := tile.global_position
			_navmesh_min.x = minf(_navmesh_min.x, pos.x)
			_navmesh_min.y = minf(_navmesh_min.y, pos.z)
			_navmesh_max.x = maxf(_navmesh_max.x, pos.x)
			_navmesh_max.y = maxf(_navmesh_max.y, pos.z)

	_reconstruir_navmesh()
	_criar_piso()  # _criar_piso já libera e recria o chão


# --- HOTBAR E INVENTÁRIO ---

## Cria o CanvasLayer de UI com a hotbar e o contador de mel
func _setup_hotbar() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "UILayer"

	# Hotbar de inventário
	if ResourceLoader.exists("res://scenes/hotbar.tscn"):
		var hotbar_cena: PackedScene = load("res://scenes/hotbar.tscn")
		if hotbar_cena != null:
			canvas.add_child(hotbar_cena.instantiate())
	else:
		push_warning("mundo.gd: hotbar.tscn não encontrada.")

	# Contador de mel (canto superior direito)
	if ResourceLoader.exists("res://scenes/ui_mel.tscn"):
		var ui_mel_cena: PackedScene = load("res://scenes/ui_mel.tscn")
		if ui_mel_cena != null:
			canvas.add_child(ui_mel_cena.instantiate())
	else:
		push_warning("mundo.gd: ui_mel.tscn não encontrada — contador de mel não será exibido.")

	add_child(canvas)


## Dá ao jogador 5 itens do tipo Flor como ponto de partida
func _dar_itens_iniciais() -> void:
	if not ResourceLoader.exists("res://resources/flor.tres"):
		push_warning("mundo.gd: flor.tres não encontrado — itens iniciais não serão dados.")
		return

	var jogador := get_node_or_null("Player")
	if jogador == null:
		return
	if not jogador.has_method("get") or jogador.get("inventario") == null:
		return

	var flor = load("res://resources/flor.tres")
	if flor != null:
		jogador.inventario.adicionar_item(flor, 5)
