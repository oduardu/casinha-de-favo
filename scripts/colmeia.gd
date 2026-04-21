class_name Colmeia
extends Node3D

# Gerencia a produção de mel: controla a Abelha, acumula progresso,
# detecta o jogador e permite a coleta quando o mel está pronto.


# --- SINAIS ---

## Emitido quando o jogador coleta mel com sucesso; 'quantidade' é sempre 1 por coleta
signal mel_coletado(quantidade: int)

## Emitido quando um CharacterBody3D entra na área de detecção da colmeia
signal jogador_entrou_colmeia

## Emitido quando um CharacterBody3D sai da área de detecção da colmeia
signal jogador_saiu_colmeia


# --- IDENTIFICAÇÃO ---

## ID único desta colmeia — usado como chave no save para múltiplas colmeias no futuro
@export var id_colmeia: String = "colmeia_principal"


# --- CONFIGURAÇÃO DE PRODUÇÃO ---

## Quanto progresso cada ciclo da abelha adiciona (0.0..1.0).
## Com 0.25 são necessários 4 ciclos para encher a colmeia.
@export var incremento_por_ciclo: float = 0.25


# --- ESTADO DE MEL ---

## Progresso atual de mel (0.0 = vazia, 1.0 = cheia e pronta para coletar)
var progresso_mel: float = 0.0

## True quando progresso_mel >= 1.0 e o jogador pode coletar
var mel_pronto: bool = false


# --- NÓS FILHOS ---

## CSGBox3D que representa visualmente o corpo da colmeia
var _corpo: CSGBox3D = null

## Material do corpo — mantido como referência para alterar a cor dinamicamente
var _mat_corpo: StandardMaterial3D = null

## Abelha filha que controla o ciclo de voo e produção
var _abelha: Abelha = null

## Area3D que detecta a proximidade do jogador para exibir hints e permitir coleta
var _area_deteccao: Area3D = null

## Label3D "Pressione E para coletar mel" — visível apenas quando mel_pronto == true
var _hint_label: Label3D = null

## Node3D pai dos quads da barra de progresso flutuante
var _barra_container: Node3D = null

## MeshInstance3D do fill amarelo que cresce com o progresso (0.0..1.0 no scale.x)
var _barra_fill: MeshInstance3D = null

## Largura total da barra de progresso em unidades de mundo
var _largura_barra: float = 1.0

## True enquanto o jogador está dentro da área de detecção
var _jogador_proximo: bool = false


# --- CICLO DE VIDA ---

func _ready() -> void:
	add_to_group("colmeia")
	_criar_corpo()
	_criar_barra_progresso()
	_criar_hint_label()
	_criar_area_deteccao()
	_criar_abelha()
	_carregar_estado()
	_atualizar_visual_completo()


# --- CRIAÇÃO VISUAL ---

## Cria o corpo cúbico da colmeia com material que muda de cor conforme o mel enche
func _criar_corpo() -> void:
	_corpo = CSGBox3D.new()
	_corpo.name = "CorpoColmeia"
	_corpo.size = Vector3(1.0, 0.7, 1.0)
	_corpo.position.y = 0.35  # Apoia a base em y=0
	_mat_corpo = StandardMaterial3D.new()
	_mat_corpo.albedo_color = Color(0.92, 0.70, 0.20)  # Amarelo pálido (colmeia vazia)
	_corpo.material_override = _mat_corpo
	add_child(_corpo)


## Cria os dois quads 3D billboard que formam a barra de progresso flutuante
func _criar_barra_progresso() -> void:
	_barra_container = Node3D.new()
	_barra_container.name = "BarraMel"
	_barra_container.position = Vector3(0.0, 1.4, 0.0)
	_barra_container.visible = false
	add_child(_barra_container)

	var espessura := 0.04
	var altura := 0.14

	# Fundo escuro um pouco maior que o fill para criar efeito de borda
	var fundo := MeshInstance3D.new()
	var mesh_fundo := BoxMesh.new()
	mesh_fundo.size = Vector3(_largura_barra + 0.06, altura + 0.04, espessura)
	fundo.mesh = mesh_fundo
	var mat_fundo := StandardMaterial3D.new()
	mat_fundo.albedo_color = Color(0.12, 0.10, 0.08)
	mat_fundo.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	fundo.material_override = mat_fundo
	_barra_container.add_child(fundo)

	# Fill amarelo mel que escala no eixo X de 0 a 1 conforme o progresso
	_barra_fill = MeshInstance3D.new()
	var mesh_fill := BoxMesh.new()
	mesh_fill.size = Vector3(_largura_barra, altura, espessura)
	_barra_fill.mesh = mesh_fill
	var mat_fill := StandardMaterial3D.new()
	mat_fill.albedo_color = Color(0.96, 0.76, 0.08)  # Amarelo mel vivo
	mat_fill.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_barra_fill.material_override = mat_fill
	_barra_container.add_child(_barra_fill)


## Cria o Label3D de instrução visível quando o mel está pronto para coletar
func _criar_hint_label() -> void:
	_hint_label = Label3D.new()
	_hint_label.name = "HintMel"
	_hint_label.text = "E — coletar mel"
	_hint_label.font_size = 26
	_hint_label.modulate = Color(1.0, 0.88, 0.15)  # Amarelo dourado
	_hint_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_hint_label.position.y = 1.7
	_hint_label.visible = false
	add_child(_hint_label)


## Cria a Area3D cilíndrica que detecta o jogador ao se aproximar da colmeia
func _criar_area_deteccao() -> void:
	_area_deteccao = Area3D.new()
	_area_deteccao.name = "AreaColmeia"

	var col := CollisionShape3D.new()
	var forma := CylinderShape3D.new()
	forma.radius = 1.8   # Raio de detecção — ligeiramente maior que a colmeia visual
	forma.height = 3.0
	col.shape = forma
	col.position.y = 1.0

	_area_deteccao.add_child(col)
	_area_deteccao.body_entered.connect(_ao_entrar_area)
	_area_deteccao.body_exited.connect(_ao_sair_area)
	add_child(_area_deteccao)


## Instancia a Abelha como filha e conecta o sinal de ciclo completo
func _criar_abelha() -> void:
	_abelha = Abelha.new()
	_abelha.name = "Abelha"
	_abelha.ciclo_mel_completo.connect(_ao_ciclo_mel_completo)
	add_child(_abelha)


# --- CALLBACKS DA ÁREA ---

## Disparado quando um corpo entra na área; exibe barra e emite sinal para o player
func _ao_entrar_area(body: Node3D) -> void:
	if not (body is CharacterBody3D):
		return
	_jogador_proximo = true
	_barra_container.visible = true
	_atualizar_fill_barra(progresso_mel)
	jogador_entrou_colmeia.emit()


## Disparado quando um corpo sai da área; esconde barra (exceto se mel pronto) e emite sinal
func _ao_sair_area(body: Node3D) -> void:
	if not (body is CharacterBody3D):
		return
	_jogador_proximo = false
	if not mel_pronto:
		_barra_container.visible = false
	jogador_saiu_colmeia.emit()


# --- PRODUÇÃO DE MEL ---

## Chamado pela Abelha a cada ciclo concluído; incrementa o progresso e salva
func _ao_ciclo_mel_completo() -> void:
	progresso_mel = minf(progresso_mel + incremento_por_ciclo, 1.0)
	_atualizar_visual_completo()

	if progresso_mel >= 1.0 and not mel_pronto:
		mel_pronto = true
		_barra_container.visible = true  # Mantém barra visível mesmo sem jogador próximo
		_hint_label.visible = true
		_animar_pulso_pronto()

	GerenciadorMundo.salvar_estado_colmeia(id_colmeia, _obter_estado())


# --- COLETA ---

## Chamada pelo Player ao pressionar E próximo à colmeia quando mel_pronto == true.
## Adiciona 1 mel ao inventário, incrementa contador global e reseta a produção.
func tentar_coletar(jogador: Node) -> void:
	if not mel_pronto:
		return

	# Adiciona o item Mel ao inventário do jogador via duck typing
	var inv: Node = jogador.get_node_or_null("Inventario")
	if inv != null and ResourceLoader.exists("res://resources/mel.tres"):
		var item_mel: Item = load("res://resources/mel.tres")
		if item_mel != null:
			inv.adicionar_item(item_mel, 1)

	# Atualiza o contador global (salvo automaticamente pela próxima chamada)
	GerenciadorMundo.total_mel_coletado += 1

	# Reseta o estado de produção
	mel_pronto = false
	progresso_mel = 0.0
	_hint_label.visible = false
	if not _jogador_proximo:
		_barra_container.visible = false
	_atualizar_visual_completo()
	_animar_feedback_coleta()

	mel_coletado.emit(1)
	GerenciadorMundo.salvar_estado_colmeia(id_colmeia, _obter_estado())


# --- VISUAL ---

## Atualiza ao mesmo tempo a cor do corpo (amarelo pálido → laranja mel) e o fill da barra
func _atualizar_visual_completo() -> void:
	if _mat_corpo == null:
		return
	# Interpola entre amarelo pálido (0.0) e laranja mel vivo (1.0)
	var cor_vazia := Color(0.92, 0.70, 0.20)
	var cor_cheia := Color(0.98, 0.55, 0.04)
	_mat_corpo.albedo_color = cor_vazia.lerp(cor_cheia, progresso_mel)
	_atualizar_fill_barra(progresso_mel)


## Ajusta o scale.x do fill e sua posição para simular uma barra que cresce da esquerda
func _atualizar_fill_barra(progresso: float) -> void:
	if _barra_fill == null:
		return
	_barra_fill.scale.x = maxf(progresso, 0.001)
	_barra_fill.position.x = (progresso - 1.0) * (_largura_barra * 0.5)


## Pulsa o corpo 3 vezes para indicar ao jogador que o mel está pronto
func _animar_pulso_pronto() -> void:
	var tween := create_tween().set_loops(3)
	tween.tween_property(_corpo, "scale", Vector3(1.12, 1.12, 1.12), 0.18) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(_corpo, "scale", Vector3.ONE, 0.18) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)


## Feedback "squash and stretch" ao coletar: encolhe horizontalmente e volta
func _animar_feedback_coleta() -> void:
	var tween := create_tween()
	tween.tween_property(_corpo, "scale", Vector3(0.8, 1.25, 0.8), 0.12) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_corpo, "scale", Vector3.ONE, 0.22) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)


# --- PERSISTÊNCIA ---

## Carrega o estado salvo da colmeia via GerenciadorMundo; se não existir, começa do zero
func _carregar_estado() -> void:
	var dados := GerenciadorMundo.carregar_estado_colmeia(id_colmeia)
	if dados.is_empty():
		return

	progresso_mel = dados.get("progresso_mel", 0.0)
	mel_pronto = progresso_mel >= 1.0

	if mel_pronto:
		_hint_label.visible = true
		_barra_container.visible = true

	# Restaura o estado da abelha se os dados existirem
	if _abelha != null:
		_abelha.restaurar_estado(dados)


## Retorna o estado atual serializado para salvar via GerenciadorMundo
func _obter_estado() -> Dictionary:
	var dados: Dictionary = {"progresso_mel": progresso_mel}
	if _abelha != null:
		dados.merge(_abelha.obter_estado_para_salvar())
	return dados
