extends Node3D

# --- SINAIS ---
# Emitido quando um CharacterBody3D entra na área de detecção — world.gd conecta ao player
signal jogador_entrou
# Emitido quando o CharacterBody3D sai da área — world.gd conecta ao player para cancelar plantio
signal jogador_saiu
# Emitido ao final do plantio bem-sucedido — pode ser usado por sistemas de progressão/missões
signal plantio_concluido


# --- ENUMERAÇÃO DE ESTADOS ---
enum Estado { VAZIO, PLANTANDO, PLANTADO }


# --- CONFIGURAÇÃO ---
const CAMINHO_MODELO := "res://obj/kenney_hexagonal/building-farm.glb"
const QUANTIDADE_FLORES := 4  # Número de flores geradas ao concluir o plantio
const RAIO_FLORES := 0.9      # Raio máximo de espalhamento das flores sobre o tile

# Tag que define qual tipo de item este tile aceita — deve bater com Item.tipo_interacao
# Para criar novos tipos de interação, basta mudar essa string no tile e criar o item correspondente
var tipo_interacao_aceita: String = "plantar"


# --- ESTADO INTERNO ---
var estado_atual: Estado = Estado.VAZIO  # Controla o que o tile pode fazer no momento


# --- REFERÊNCIAS INTERNAS (criadas em _ready) ---
var _area_deteccao: Area3D = null    # Detecta a proximidade do jogador
var _hint_label: Label3D = null      # Label flutuante com dica de interação
var _flores_container: Node3D = null # Nó pai de todas as flores geradas
var _label_erro: Label3D = null      # Label temporário para mensagens de erro


func _ready() -> void:
	_criar_modelo()
	_criar_area_deteccao()
	_criar_hint_label()
	_flores_container = Node3D.new()
	_flores_container.name = "FloresContainer"
	add_child(_flores_container)
	_criar_label_erro()


# --- INTERFACE PÚBLICA ---

# Retorna true se o tile está vazio e pode receber plantio
func pode_plantar() -> bool:
	return estado_atual == Estado.VAZIO


# Ponto de entrada da interação: chamado pelo player ao pressionar E dentro da área.
# Valida se o jogador tem um item compatível no inventário, consome 1 unidade e inicia o plantio.
# Retorna true se a interação foi aceita (para o player iniciar a animação do seu lado).
func tentar_interagir(jogador: Node) -> bool:
	# Tile já usado ou em processo — não aceita nova interação
	if not pode_plantar():
		return false

	# Busca o inventário no jogador via duck typing — funciona com qualquer nó que tenha "Inventario" filho
	var inv: Node = jogador.get_node_or_null("Inventario")
	if inv == null:
		push_warning("farm_tile: jogador não tem nó 'Inventario'")
		return false

	# Valida se existe item no inventário com o tipo de interação correto
	if not inv.possui_item_com_tipo_interacao(tipo_interacao_aceita):
		var nome_necessario := "uma flor" if tipo_interacao_aceita == "plantar" else tipo_interacao_aceita
		_mostrar_erro("Precisa de " + nome_necessario)
		return false

	# Consome 1 unidade do item compatível no inventário do jogador
	if not inv.consumir_item_por_tipo_interacao(tipo_interacao_aceita, 1):
		_mostrar_erro("Nao foi possivel consumir o item.")
		return false

	# Inicia o estado de plantio e esconde o hint
	iniciar_plantio()
	return true


# Muda o estado para PLANTANDO — chamado internamente por tentar_interagir()
func iniciar_plantio() -> void:
	if not pode_plantar():
		return
	estado_atual = Estado.PLANTANDO
	_hint_label.visible = false


# Finaliza o plantio: gera flores e emite sinal — chamado pelo player após o timer
func finalizar_plantio() -> void:
	if estado_atual != Estado.PLANTANDO:
		return
	estado_atual = Estado.PLANTADO
	_gerar_flores()
	plantio_concluido.emit()


# Reseta para VAZIO se o plantio foi cancelado (jogador saiu da área)
func cancelar_plantio() -> void:
	if estado_atual == Estado.PLANTANDO:
		estado_atual = Estado.VAZIO


# --- CRIAÇÃO DE NÓS ---

# Instancia o modelo GLB do tile de fazenda como filho
func _criar_modelo() -> void:
	var cena: PackedScene = load(CAMINHO_MODELO)
	if cena == null:
		push_warning("farm_tile: modelo não encontrado em " + CAMINHO_MODELO)
		return
	var modelo: Node3D = cena.instantiate() as Node3D
	modelo.name = "BuildingModel"
	add_child(modelo)


# Cria a área cilíndrica que detecta o jogador se aproximando
func _criar_area_deteccao() -> void:
	_area_deteccao = Area3D.new()
	_area_deteccao.name = "DetectionArea"

	var colisao := CollisionShape3D.new()
	var forma := CylinderShape3D.new()
	forma.radius = 1
	forma.height = 2.5
	colisao.shape = forma
	colisao.position.y = 1.0

	_area_deteccao.add_child(colisao)
	add_child(_area_deteccao)

	_area_deteccao.body_entered.connect(_ao_entrar_area)
	_area_deteccao.body_exited.connect(_ao_sair_area)


# Cria o Label3D de dica que aparece ao entrar na área
func _criar_hint_label() -> void:
	_hint_label = Label3D.new()
	_hint_label.name = "HintLabel"
	_hint_label.text = "Pressione E para plantar"
	_hint_label.font_size = 24
	_hint_label.modulate = Color(1.0, 0.95, 0.4)
	_hint_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_hint_label.position.y = 1.2
	_hint_label.visible = false
	add_child(_hint_label)


# Cria o Label3D de erro reutilizável (fica invisível até ser chamado)
func _criar_label_erro() -> void:
	_label_erro = Label3D.new()
	_label_erro.name = "LabelErro"
	_label_erro.font_size = 22
	_label_erro.modulate = Color(1.0, 0.35, 0.35)  # Vermelho suave
	_label_erro.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label_erro.position.y = 1.0
	_label_erro.visible = false
	add_child(_label_erro)


# --- CALLBACKS DA ÁREA ---

# Disparado quando um corpo entra na área de detecção
func _ao_entrar_area(body: Node3D) -> void:
	if not (body is CharacterBody3D):
		return
	jogador_entrou.emit()
	if pode_plantar():
		_hint_label.visible = true


# Disparado quando um corpo sai da área de detecção
func _ao_sair_area(body: Node3D) -> void:
	if not (body is CharacterBody3D):
		return
	_hint_label.visible = false
	jogador_saiu.emit()


# --- FEEDBACK DE ERRO ---

# Exibe uma mensagem vermelha flutuante por 1.5 segundos
func _mostrar_erro(mensagem: String) -> void:
	_label_erro.text = mensagem
	_label_erro.visible = true
	_label_erro.modulate.a = 1.0

	# Fade out após 1.5s e esconde
	var tween := create_tween()
	tween.tween_interval(1.0)
	tween.tween_property(_label_erro, "modulate:a", 0.0, 0.5)
	tween.tween_callback(func(): _label_erro.visible = false)


# --- GERAÇÃO DE FLORES ---

# Gera flores low-poly (CSGCylinder + CSGSphere) com tween de aparecimento em cascata
func _gerar_flores() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()

	var cores := [
		Color(1.0, 0.3, 0.5),
		Color(1.0, 0.9, 0.2),
		Color(0.5, 0.3, 1.0),
		Color(1.0, 0.5, 0.1),
		Color(1.0, 1.0, 1.0),
	]

	for i in QUANTIDADE_FLORES:
		var angulo := rng.randf_range(0.0, TAU)
		var distancia := rng.randf_range(0.2, RAIO_FLORES)
		var pos_xz := Vector3(cos(angulo) * distancia, 0.0, sin(angulo) * distancia)

		var caule := CSGCylinder3D.new()
		caule.radius = 0.045
		caule.height = 0.45
		caule.position = pos_xz + Vector3(0.0, 0.225, 0.0)
		caule.scale = Vector3.ZERO  # Começa invisível para o tween

		var mat_caule := StandardMaterial3D.new()
		mat_caule.albedo_color = Color(0.2, 0.7, 0.2)
		caule.material_override = mat_caule
		_flores_container.add_child(caule)

		var flor := CSGSphere3D.new()
		flor.radius = 0.14
		flor.position = Vector3(0.0, 0.32, 0.0)

		var mat_flor := StandardMaterial3D.new()
		mat_flor.albedo_color = cores[rng.randi() % cores.size()]
		flor.material_override = mat_flor
		caule.add_child(flor)

		# Aparecimento em cascata: cada flor com atraso de 0.18s
		var tween := create_tween()
		tween.tween_interval(i * 0.18)
		tween.tween_property(caule, "scale", Vector3.ONE, 0.45) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
