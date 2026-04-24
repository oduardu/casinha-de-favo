extends Node3D

# --- CONFIGURAÇÃO ---

## Raio em tiles da área externa bloqueada ao redor da grade inicial
@export var raio_mundo_externo: int = 8

## Preço base em moedas; o custo real de um tile externo é preco_base * dist²
@export var preco_base: int = 10

## Moedas iniciais adicionadas ao GerenciadorMundo na primeira inicialização do jogo
@export var moedas_debug: int = 500


# --- CONSTANTES ---

## Escala de renderização dos tiles (tamanho visual dos hexágonos)
const TILE_SCALE := 5.0

## Limite mínimo de q na grade inicial 4×4
const Q_MIN := -1

## Limite máximo de q na grade inicial 4×4
const Q_MAX := 2

## Limite mínimo de r na grade inicial 4×4
const R_MIN := -1

## Limite máximo de r na grade inicial 4×4
const R_MAX := 2

## Raio do hexágono em unidades de mundo (metade da distância entre centros opostos)
const HEX_RAIO := TILE_SCALE * 0.58


# --- ESTADO ---

## PackedScene do HexTile carregada em _ready (res://scenes/hex_tile.tscn)
var _hex_tile_cena: PackedScene = null

## Script da Colmeia carregado em _ready para ser aplicado em Node3D instanciados
var _colmeia_cena_script: Script = null

## Script do NPC carregado em _ready para ser aplicado em Node3D instanciados
var _npc_script: Script = null

## Dicionário de Vector2i → HexTile, mapeia coordenadas axiais para os nós de tile
var _tiles_por_coord: Dictionary = {}

## Deslocamento em unidades de mundo para centralizar a grade no ponto de origem
var _deslocamento_centro: Vector3 = Vector3.ZERO

## StaticBody3D plano que serve de chão sob a área jogável; recriado ao comprar tiles
var _piso_corpo: StaticBody3D = null

## Menu de pausa criado em runtime (CanvasLayer com botões)
var _menu_pausa: CanvasLayer = null


# --- CICLO DE VIDA ---

## Salva ao fechar a janela, já que GerenciadorMundo não é um Node
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		GerenciadorMundo.salvar()


func _ready() -> void:
	# Permite que este nó processe input mesmo durante pausa (para ESC fechar o menu)
	process_mode = Node.PROCESS_MODE_ALWAYS
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
	_setup_hotbar()
	_criar_menu_pausa()

	# Conecta o PathVisualizer ao NavigationAgent3D do jogador
	var agente = $Player.get_node("NavigationAgent3D")
	if agente != null and $PathVisualizer != null:
		$PathVisualizer.setup(agente)


# --- INPUT ---

## Tecla ESC abre/fecha o menu de pausa
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_alternar_menu_pausa()
		get_viewport().set_input_as_handled()


# --- CONFIGURAÇÃO ---

## Carrega todas as cenas e scripts necessários; falhas emitem push_error mas não travam o jogo
func _carregar_recursos() -> void:
	if ResourceLoader.exists("res://scenes/hex_tile.tscn"):
		_hex_tile_cena = load("res://scenes/hex_tile.tscn")
	else:
		push_error("mundo.gd: cena hex_tile.tscn não encontrada em res://scenes/")

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


## Retorna os 6 vértices de um hexágono pointy-top centrado em 'centro' com raio 'raio'
func _hex_vertices(centro: Vector2, raio: float) -> PackedVector2Array:
	var verts := PackedVector2Array()
	for i in 6:
		var angulo := deg_to_rad(30.0 + i * 60.0)
		verts.append(Vector2(
			centro.x + raio * cos(angulo),
			centro.y + raio * sin(angulo)
		))
	return verts


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
func _gerar_grade_inicial() -> void:
	for q in range(Q_MIN, Q_MAX + 1):
		for r in range(R_MIN, R_MAX + 1):
			_criar_tile(Vector2i(q, r), "grass", true, 0)


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


# --- COLISÃO E NAVEGAÇÃO ---

## Coleta as posições de todos os tiles desbloqueados como Vector2 (x, z)
func _coletar_centros_desbloqueados() -> Array[Vector2]:
	var centros: Array[Vector2] = []
	for coord in _tiles_por_coord:
		var tile := _tiles_por_coord[coord] as HexTile
		if tile.desbloqueado:
			var pos := tile.global_position
			centros.append(Vector2(pos.x, pos.z))
	return centros


## Cria o chão plano sob a área jogável, dimensionado a partir
## do bounding box dos hexágonos desbloqueados
func _criar_piso() -> void:
	if is_instance_valid(_piso_corpo):
		_piso_corpo.queue_free()
		_piso_corpo = null

	var centros := _coletar_centros_desbloqueados()
	if centros.is_empty():
		return

	# Calcula bounding box dos centros dos hexágonos desbloqueados
	var bb_min := centros[0]
	var bb_max := centros[0]
	for c in centros:
		bb_min.x = minf(bb_min.x, c.x)
		bb_min.y = minf(bb_min.y, c.y)
		bb_max.x = maxf(bb_max.x, c.x)
		bb_max.y = maxf(bb_max.y, c.y)

	# Margem de um hex inteiro ao redor do bounding box
	var margem := HEX_RAIO * 2.0
	bb_min -= Vector2(margem, margem)
	bb_max += Vector2(margem, margem)

	var cx := (bb_min.x + bb_max.x) * 0.5
	var cz := (bb_min.y + bb_max.y) * 0.5
	var largura := bb_max.x - bb_min.x
	var profund := bb_max.y - bb_min.y

	_piso_corpo = StaticBody3D.new()
	_piso_corpo.name = "PisoJogavel"

	# Colisão: fino BoxShape3D logo abaixo de y=0
	var forma := BoxShape3D.new()
	forma.size = Vector3(largura, 0.1, profund)
	var colisao := CollisionShape3D.new()
	colisao.shape = forma
	colisao.position = Vector3(cx, -0.05, cz)
	_piso_corpo.add_child(colisao)

	# Visual: PlaneMesh verde-grama cobrindo toda a área
	var mesh_piso := MeshInstance3D.new()
	mesh_piso.name = "MeshPisoVisual"
	var plano := PlaneMesh.new()
	plano.size = Vector2(largura * 1.4, profund * 1.4)
	mesh_piso.mesh = plano
	var mat_piso := StandardMaterial3D.new()
	mat_piso.albedo_color = Color(0.22, 0.52, 0.18)
	mesh_piso.material_override = mat_piso
	mesh_piso.position = Vector3(cx, -0.30, cz)
	_piso_corpo.add_child(mesh_piso)

	add_child(_piso_corpo)


## Reconstrói a NavigationMesh como um polígono que une os hexágonos desbloqueados.
## Usa o convex hull de todos os vértices dos hexágonos para criar a área navegável.
func _reconstruir_navmesh() -> void:
	var nav_region := get_node_or_null("NavigationRegion3D") as NavigationRegion3D
	if nav_region == null:
		push_warning("mundo.gd: NavigationRegion3D não encontrado.")
		return

	var centros := _coletar_centros_desbloqueados()
	if centros.is_empty():
		return

	# Coleta todos os vértices de todos os hexágonos desbloqueados
	var pontos_2d: PackedVector2Array = PackedVector2Array()
	for c in centros:
		var hex_verts := _hex_vertices(c, HEX_RAIO)
		for v in hex_verts:
			pontos_2d.append(v)

	# Calcula o convex hull dos pontos 2D
	var hull := Geometry2D.convex_hull(pontos_2d)
	if hull.size() < 3:
		return

	# Converte o hull 2D para vértices 3D no plano XZ
	var verts_3d := PackedVector3Array()
	for p in hull:
		verts_3d.append(Vector3(p.x, 0.0, p.y))

	var navmesh := NavigationMesh.new()
	navmesh.cell_height = 0.1
	navmesh.vertices = verts_3d

	# Cria um polígono com todos os índices do hull
	var indices := PackedInt32Array()
	for i in verts_3d.size():
		indices.append(i)
	navmesh.add_polygon(indices)

	nav_region.navigation_mesh = navmesh


# --- EDIFICIOS ---

## Ponto de entrada: cria todos os edifícios do mundo
func _colocar_edificios() -> void:
	_criar_casa()
	_criar_colmeia()
	_criar_npc()


## Instancia o modelo building-house.glb no tile (Q_MIN, R_MIN).
## Usa a mesma escala dos tiles hexagonais (TILE_SCALE) para encaixar no grid.
## Adiciona colisão física e rotaciona para que a frente fique visível na câmera isométrica.
func _criar_casa() -> void:
	var pos_casa := _axial_para_mundo(Q_MIN, R_MIN)

	var cena_casa: PackedScene = load("res://obj/kenney_hexagonal/building-house.glb")
	if cena_casa == null:
		push_warning("mundo.gd: building-house.glb não encontrado.")
		return

	# Nó raiz para agrupar modelo + colisão
	var casa_raiz := Node3D.new()
	casa_raiz.name = "Casa"
	casa_raiz.position = Vector3(pos_casa.x, 0.0, pos_casa.z)
	add_child(casa_raiz)

	# Modelo visual — mesma escala e offset Y dos tiles hex
	var modelo: Node3D = cena_casa.instantiate() as Node3D
	modelo.name = "ModeloCasa"
	modelo.position.y = -0.2 * TILE_SCALE
	modelo.scale = Vector3.ONE * TILE_SCALE
	modelo.rotation_degrees.y = 180.0
	casa_raiz.add_child(modelo)

	# Colisão física — cilindro que impede o jogador de atravessar a casa
	var fis := StaticBody3D.new()
	fis.name = "CasaColisao"
	var forma := CylinderShape3D.new()
	forma.radius = TILE_SCALE * 0.4
	forma.height = TILE_SCALE * 1.0
	var col := CollisionShape3D.new()
	col.shape = forma
	col.position.y = forma.height * 0.5
	fis.add_child(col)
	casa_raiz.add_child(fis)


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

	var jogador := get_node_or_null("Player")
	if jogador != null:
		if colmeia.has_signal("jogador_entrou_colmeia") and jogador.has_method("_ao_entrar_colmeia_area"):
			colmeia.jogador_entrou_colmeia.connect(
				func() -> void: jogador._ao_entrar_colmeia_area(colmeia)
			)
		if colmeia.has_signal("jogador_saiu_colmeia") and jogador.has_method("_ao_sair_colmeia_area"):
			colmeia.jogador_saiu_colmeia.connect(jogador._ao_sair_colmeia_area)


## Instancia um Node3D com o script NPC na frente da casa (tile 0, -1).
## Conecta os sinais de proximidade ao Player para permitir venda de mel.
func _criar_npc() -> void:
	if _npc_script == null:
		push_warning("mundo.gd: script npc.gd não carregado — NPC não será criado.")
		return

	var npc := Node3D.new()
	npc.name = "NPC"
	npc.set_script(_npc_script)
	npc.position = _axial_para_mundo(Q_MIN + 1, R_MIN)  # (0, -1) — na frente da casa
	npc.position.y = 0.0
	add_child(npc)

	var jogador := get_node_or_null("Player")
	if jogador != null:
		if npc.has_signal("jogador_entrou_npc") and jogador.has_method("_ao_entrar_npc_area"):
			npc.jogador_entrou_npc.connect(
				func() -> void: jogador._ao_entrar_npc_area(npc)
			)
		if npc.has_signal("jogador_saiu_npc") and jogador.has_method("_ao_sair_npc_area"):
			npc.jogador_saiu_npc.connect(jogador._ao_sair_npc_area)

		var inv: Node = jogador.get_node_or_null("Inventario")
		if inv != null and inv.has_signal("inventario_mudou") and npc.has_method("_ao_inventario_mudou"):
			inv.inventario_mudou.connect(npc._ao_inventario_mudou)
		if inv != null and inv.has_signal("item_na_mao_mudou") and npc.has_method("_ao_inventario_mudou"):
			inv.item_na_mao_mudou.connect(func(_item: Item) -> void: npc._ao_inventario_mudou())


# --- COMPRA DE HEX ---

## Chamado quando um tile externo é comprado com sucesso.
## Reconstrói a navmesh e o piso baseado nos novos hexágonos desbloqueados.
func _ao_tile_comprado(_custo: int) -> void:
	_reconstruir_navmesh()
	_criar_piso()


# --- HOTBAR E INVENTÁRIO ---

## Cria o CanvasLayer de UI com a hotbar e o contador de mel
func _setup_hotbar() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "UILayer"

	if ResourceLoader.exists("res://scenes/hotbar.tscn"):
		var hotbar_cena: PackedScene = load("res://scenes/hotbar.tscn")
		if hotbar_cena != null:
			canvas.add_child(hotbar_cena.instantiate())
	else:
		push_warning("mundo.gd: hotbar.tscn não encontrada.")

	if ResourceLoader.exists("res://scenes/ui_mel.tscn"):
		var ui_mel_cena: PackedScene = load("res://scenes/ui_mel.tscn")
		if ui_mel_cena != null:
			canvas.add_child(ui_mel_cena.instantiate())
	else:
		push_warning("mundo.gd: ui_mel.tscn não encontrada.")

	add_child(canvas)


# --- MENU DE PAUSA ---

## Cria o menu de pausa (oculto por padrão) com botões Continuar e Reiniciar
func _criar_menu_pausa() -> void:
	_menu_pausa = CanvasLayer.new()
	_menu_pausa.name = "MenuPausa"
	_menu_pausa.layer = 10  # Acima de tudo
	_menu_pausa.visible = false
	add_child(_menu_pausa)

	# Fundo semitransparente que escurece o jogo
	var fundo := ColorRect.new()
	fundo.name = "Fundo"
	fundo.color = Color(0.0, 0.0, 0.0, 0.6)
	fundo.anchors_preset = Control.PRESET_FULL_RECT
	fundo.mouse_filter = Control.MOUSE_FILTER_STOP  # Bloqueia cliques no jogo
	_menu_pausa.add_child(fundo)

	# Container central para os botões
	var container := VBoxContainer.new()
	container.name = "ContainerMenu"
	container.alignment = BoxContainer.ALIGNMENT_CENTER
	container.anchors_preset = Control.PRESET_CENTER
	container.offset_left = -120.0
	container.offset_right = 120.0
	container.offset_top = -80.0
	container.offset_bottom = 80.0
	container.add_theme_constant_override("separation", 16)
	_menu_pausa.add_child(container)

	# Título
	var titulo := Label.new()
	titulo.text = "PAUSA"
	titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	titulo.add_theme_font_size_override("font_size", 32)
	titulo.add_theme_color_override("font_color", Color(1.0, 0.92, 0.5))
	container.add_child(titulo)

	# Botão Continuar
	var btn_continuar := Button.new()
	btn_continuar.name = "BtnContinuar"
	btn_continuar.text = "Continuar"
	btn_continuar.custom_minimum_size = Vector2(240, 48)
	btn_continuar.pressed.connect(_fechar_menu_pausa)
	container.add_child(btn_continuar)

	# Botão Reiniciar
	var btn_reiniciar := Button.new()
	btn_reiniciar.name = "BtnReiniciar"
	btn_reiniciar.text = "Reiniciar Jogo"
	btn_reiniciar.custom_minimum_size = Vector2(240, 48)
	btn_reiniciar.pressed.connect(_reiniciar_jogo)
	container.add_child(btn_reiniciar)


## Alterna a visibilidade do menu de pausa e pausa/despausa o jogo
func _alternar_menu_pausa() -> void:
	if _menu_pausa == null:
		return
	var abrindo := not _menu_pausa.visible
	_menu_pausa.visible = abrindo
	get_tree().paused = abrindo


## Fecha o menu de pausa e retoma o jogo
func _fechar_menu_pausa() -> void:
	if _menu_pausa != null:
		_menu_pausa.visible = false
	get_tree().paused = false


## Reseta todo o save e recarrega a cena do zero
func _reiniciar_jogo() -> void:
	# Reseta os dados globais
	GerenciadorMundo.moedas = moedas_debug
	GerenciadorMundo.total_mel_coletado = 0
	GerenciadorMundo.hexagonos_desbloqueados = []
	GerenciadorMundo.estado_colmeias = {}

	# Apaga o save do disco
	if FileAccess.file_exists(GerenciadorMundo.CAMINHO_SAVE):
		DirAccess.remove_absolute(GerenciadorMundo.CAMINHO_SAVE)

	# Despausa antes de recarregar
	get_tree().paused = false
	get_tree().reload_current_scene()
