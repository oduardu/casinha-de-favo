extends CharacterBody3D

const SPEED := 4.0
const GRAVITY := 20.0

# --- REFERÊNCIAS DE CENA ---
@onready var _camera: Camera3D = get_viewport().get_camera_3d()
@onready var _nav: NavigationAgent3D = $NavigationAgent3D
@onready var _model: Node3D = $Model

var _anim: AnimationPlayer  # AnimationPlayer encontrado recursivamente dentro do Model


# --- INVENTÁRIO ---
var inventario: Node = null  # Nó Inventario criado em _ready; outros scripts acessam via duck typing


# --- ITEM NA MÃO ---
var _ponto_da_mao: Node3D = null         # Nó 3D posicionado na mão direita do personagem
var _modelo_na_mao_atual: Node3D = null  # Instância do modelo 3D do item atual; null se não houver


# --- COMPRA DE HEX ---
var hex_tile_compravel: Node = null  # Hex tile bloqueado adjacente que pode ser comprado


# --- INTERAÇÃO COM COLMEIA ---
var colmeia_proxima: Node = null  # Colmeia dentro da área de detecção; null se nenhuma


# --- INTERAÇÃO COM TILE ---
var tile_atual: Node3D = null             # Tile de fazenda onde o jogador está no momento
var esta_plantando: bool = false           # True enquanto o plantio está em andamento
var tempo_de_plantio: float = 10.0        # Duração total do plantio em segundos
var _tempo_plantio_decorrido: float = 0.0 # Acumulador de tempo desde que o plantio começou


# --- BARRA DE PROGRESSO ---
var _barra_container: Node3D = null  # Nó pai dos quads da barra flutuante
var _barra_fill: MeshInstance3D = null  # Quad verde que cresce com o progresso
var _largura_barra: float = 1.2         # Largura total da barra em unidades de mundo


# --- PARTÍCULAS ---
var _poeira: GPUParticles3D = null  # Partículas de poeira durante o plantio


# --- TWEEN DO PLANTIO ---
var _tween_inclinacao: Tween = null  # Tween que inclina o boneco enquanto planta


func _ready() -> void:
	_nav.path_desired_distance = 0.4
	_nav.target_desired_distance = 0.4
	_anim = _find_anim_player(_model)
	_criar_inventario()
	_criar_ponto_da_mao()
	_criar_barra_progresso()
	_criar_particulas()


# --- MOVIMENTO ---

func _unhandled_input(event: InputEvent) -> void:
	# Clique esquerdo: navega até o ponto clicado no chão (bloqueado durante plantio)
	if event is InputEventMouseButton \
			and event.button_index == MOUSE_BUTTON_LEFT \
			and event.pressed:
		if esta_plantando:
			return
		var origin := _camera.project_ray_origin(event.position)
		var dir := _camera.project_ray_normal(event.position)
		if dir.y < 0.0:
			var t: float = -origin.y / dir.y
			var target := origin + dir * t
			target.y = 0.0
			_nav.target_position = target

	# Tecla E (interagir): farm tile → colmeia → hex comprável (prioridade nessa ordem)
	if event.is_action_pressed("interagir"):
		if tile_atual != null:
			_tentar_interagir()
		elif colmeia_proxima != null:
			colmeia_proxima.tentar_coletar(self)
		elif hex_tile_compravel != null:
			hex_tile_compravel.tentar_comprar(self)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta

	# Durante o plantio: para o movimento e atualiza o timer
	if esta_plantando:
		velocity.x = 0.0
		velocity.z = 0.0
		_atualizar_plantio(delta)
		move_and_slide()
		return

	# Movimento normal via NavigationAgent
	if not _nav.is_navigation_finished():
		var next := _nav.get_next_path_position()
		var diff := Vector3(next.x - global_position.x, 0.0, next.z - global_position.z)
		if diff.length_squared() > 0.01:
			var d := diff.normalized()
			velocity.x = d.x * SPEED
			velocity.z = d.z * SPEED
		else:
			velocity.x = 0.0
			velocity.z = 0.0
	else:
		velocity.x = 0.0
		velocity.z = 0.0

	var move_dir := Vector3(velocity.x, 0.0, velocity.z)
	if move_dir.length_squared() > 0.01:
		var target_basis := Basis.looking_at(move_dir.normalized(), Vector3.UP)
		basis = basis.slerp(target_basis, minf(1.0, 12.0 * delta))
		_play_anim("walk")
	else:
		_play_anim("idle")

	move_and_slide()


# --- INTERAÇÃO ---

# Chamado ao pressionar E — o tile decide se aceita a interação com base no item na mão
func _tentar_interagir() -> void:
	if tile_atual == null or esta_plantando:
		return
	# O tile recebe o jogador como argumento e faz toda a validação internamente
	if tile_atual.tentar_interagir(self):
		_iniciar_plantio_visual()


# Chamado pelo _tentar_interagir após o tile confirmar que a interação é válida
# Inicia a animação, barra de progresso e partículas do lado do jogador
func _iniciar_plantio_visual() -> void:
	esta_plantando = true
	_tempo_plantio_decorrido = 0.0

	# Para a navegação imediatamente
	_nav.target_position = global_position

	# Orienta o jogador em direção ao tile
	var direcao := tile_atual.global_position - global_position
	direcao.y = 0.0
	if direcao.length_squared() > 0.01:
		basis = Basis.looking_at(direcao.normalized(), Vector3.UP)

	_barra_container.visible = true
	_atualizar_fill_barra(0.0)
	_iniciar_animacao_plantio()
	_poeira.emitting = true


# Atualiza o timer e a barra a cada frame durante o plantio
func _atualizar_plantio(delta: float) -> void:
	_tempo_plantio_decorrido += delta
	var progresso := clampf(_tempo_plantio_decorrido / tempo_de_plantio, 0.0, 1.0)
	_atualizar_fill_barra(progresso)

	if _tempo_plantio_decorrido >= tempo_de_plantio:
		_concluir_plantio()


# Finaliza o plantio: avisa o tile e libera o jogador
func _concluir_plantio() -> void:
	esta_plantando = false
	if tile_atual:
		tile_atual.finalizar_plantio()
	_limpar_estado_plantio()


# Cancela o plantio em andamento (saiu da área)
func _cancelar_plantio() -> void:
	if not esta_plantando:
		return
	esta_plantando = false
	if tile_atual:
		tile_atual.cancelar_plantio()
	_limpar_estado_plantio()


# Reseta todos os feedbacks visuais e libera o estado de plantio
func _limpar_estado_plantio() -> void:
	_barra_container.visible = false
	_poeira.emitting = false
	_tempo_plantio_decorrido = 0.0
	if _tween_inclinacao:
		_tween_inclinacao.kill()
	var tween_reset := create_tween()
	tween_reset.tween_property(_model, "rotation:x", 0.0, 0.25)


# --- CALLBACKS DE TILE ---

# Conectado ao sinal jogador_entrou do farm_tile via world.gd
func _ao_entrar_tile(tile: Node3D) -> void:
	tile_atual = tile


# Conectado ao sinal jogador_saiu do farm_tile via world.gd
func _ao_sair_tile() -> void:
	_cancelar_plantio()
	tile_atual = null


# Conectado ao sinal jogador_entrou_compravel do HexTile — armazena referência ao tile comprável
func _ao_entrar_hex_compravel(tile: Node) -> void:
	hex_tile_compravel = tile


# Conectado ao sinal jogador_saiu_compravel do HexTile — limpa referência
func _ao_sair_hex_compravel() -> void:
	hex_tile_compravel = null


# Conectado ao sinal jogador_entrou_colmeia via mundo.gd — armazena a colmeia próxima
func _ao_entrar_colmeia_area(colmeia: Node) -> void:
	colmeia_proxima = colmeia


# Conectado ao sinal jogador_saiu_colmeia via mundo.gd — limpa a referência
func _ao_sair_colmeia_area() -> void:
	colmeia_proxima = null


# --- INVENTÁRIO ---

# Cria o nó Inventario como filho do player e conecta o sinal de troca de item
func _criar_inventario() -> void:
	inventario = Inventario.new()
	inventario.name = "Inventario"
	add_child(inventario)
	# Escuta quando o item na mão muda para atualizar o modelo 3D
	inventario.item_na_mao_mudou.connect(_ao_item_na_mao_mudado)


# --- ITEM NA MÃO ---

# Localiza o nó de mão dentro do model e armazena em _ponto_da_mao.
# Busca por qualquer nó cujo nome contenha "hand" (case-insensitive).
# Se não encontrar, cria um Node3D fallback com posição aproximada.
func _criar_ponto_da_mao() -> void:
	_ponto_da_mao = _find_node_by_name_part(_model, "hand")
	if _ponto_da_mao != null:
		return
	# Fallback: nó manual se o modelo não tiver nó com "hand" no nome
	push_warning("player.gd: nó 'hand' não encontrado no model — usando posição aproximada")
	var fallback := Node3D.new()
	fallback.name = "PontoDaMaoFallback"
	fallback.position = Vector3(0.35, 0.85, 0.15)
	add_child(fallback)
	_ponto_da_mao = fallback


# Busca recursivamente o primeiro nó cujo nome contenha 'parte' (sem distinção de maiúsculas)
func _find_node_by_name_part(node: Node, parte: String) -> Node3D:
	if node.name.to_lower().contains(parte.to_lower()):
		if node is Node3D:
			return node as Node3D
	for child in node.get_children():
		var resultado := _find_node_by_name_part(child, parte)
		if resultado != null:
			return resultado
	return null


# Chamado pelo sinal item_na_mao_mudou do Inventario
# Remove o modelo anterior e instancia o novo modelo 3D do item
func _ao_item_na_mao_mudado(novo_item: Item) -> void:
	# Remove o modelo anterior se existir
	if _modelo_na_mao_atual != null and is_instance_valid(_modelo_na_mao_atual):
		_modelo_na_mao_atual.queue_free()
		_modelo_na_mao_atual = null

	# Se o novo item não tem modelo 3D, nada aparece na mão
	if novo_item == null or novo_item.modelo_3d == null:
		return

	# Instancia o novo modelo e aplica tween de aparecimento
	_modelo_na_mao_atual = novo_item.modelo_3d.instantiate() as Node3D
	_modelo_na_mao_atual.scale = Vector3.ZERO  # Começa invisível
	_ponto_da_mao.add_child(_modelo_na_mao_atual)

	var tween := create_tween()
	tween.tween_property(_modelo_na_mao_atual, "scale", Vector3.ONE, 0.2) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# --- BARRA DE PROGRESSO ---

# Cria os dois quads (fundo e preenchimento) que formam a barra flutuante
func _criar_barra_progresso() -> void:
	_barra_container = Node3D.new()
	_barra_container.name = "BarraProgresso"
	_barra_container.position = Vector3(0.0, 2.6, 0.0)
	_barra_container.visible = false
	add_child(_barra_container)

	var altura_barra := 0.14
	var espessura := 0.02

	var fundo := MeshInstance3D.new()
	var mesh_fundo := BoxMesh.new()
	mesh_fundo.size = Vector3(_largura_barra + 0.06, altura_barra + 0.04, espessura)
	fundo.mesh = mesh_fundo
	var mat_fundo := StandardMaterial3D.new()
	mat_fundo.albedo_color = Color(0.15, 0.15, 0.15)
	mat_fundo.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	fundo.material_override = mat_fundo
	_barra_container.add_child(fundo)

	_barra_fill = MeshInstance3D.new()
	var mesh_fill := BoxMesh.new()
	mesh_fill.size = Vector3(_largura_barra, altura_barra, espessura)
	_barra_fill.mesh = mesh_fill
	var mat_fill := StandardMaterial3D.new()
	mat_fill.albedo_color = Color(0.2, 0.85, 0.3)
	mat_fill.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_barra_fill.material_override = mat_fill
	_barra_container.add_child(_barra_fill)


# Atualiza o fill da barra conforme o progresso (0.0 = vazio, 1.0 = cheio)
func _atualizar_fill_barra(progresso: float) -> void:
	if _barra_fill == null:
		return
	_barra_fill.scale.x = maxf(progresso, 0.001)
	_barra_fill.position.x = (progresso - 1.0) * (_largura_barra * 0.5)


# --- PARTÍCULAS ---

# Cria GPUParticles3D de poeira que emite ao redor do jogador durante o plantio
func _criar_particulas() -> void:
	_poeira = GPUParticles3D.new()
	_poeira.name = "PoeiraPlantar"
	_poeira.amount = 24
	_poeira.lifetime = 1.2
	_poeira.fixed_fps = 30
	_poeira.emitting = false
	_poeira.position.y = 0.1

	var processo := ParticleProcessMaterial.new()
	processo.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	processo.emission_ring_radius = 0.4
	processo.emission_ring_height = 0.05
	processo.emission_ring_axis = Vector3.UP
	processo.initial_velocity_min = 0.4
	processo.initial_velocity_max = 1.0
	processo.direction = Vector3(0.0, 1.0, 0.0)
	processo.spread = 60.0
	processo.gravity = Vector3(0.0, -2.0, 0.0)
	processo.scale_min = 0.06
	processo.scale_max = 0.14
	processo.color = Color(0.7, 0.55, 0.3, 0.8)
	_poeira.process_material = processo

	var mesh_particula := SphereMesh.new()
	mesh_particula.radius = 0.05
	mesh_particula.height = 0.1
	_poeira.draw_pass_1 = mesh_particula

	add_child(_poeira)


# --- ANIMAÇÃO DE PLANTIO ---

# Inclina o boneco para frente e para trás simulando o gesto de plantar
# Usa a animação "plant" se existir, senão cria um tween em loop
func _iniciar_animacao_plantio() -> void:
	if _anim and _anim.has_animation("plant"):
		_anim.play("plant")
		return

	_tween_inclinacao = create_tween().set_loops()
	_tween_inclinacao.tween_property(_model, "rotation:x", deg_to_rad(25.0), 0.5) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween_inclinacao.tween_property(_model, "rotation:x", deg_to_rad(0.0), 0.5) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


# --- UTILITÁRIOS ---

# Busca recursivamente um AnimationPlayer na hierarquia de filhos
func _find_anim_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var result := _find_anim_player(child)
		if result:
			return result
	return null


# Toca uma animação pelo nome, evitando reiniciar se já estiver tocando
func _play_anim(anim_name: String) -> void:
	if _anim and _anim.current_animation != anim_name:
		_anim.play(anim_name)
