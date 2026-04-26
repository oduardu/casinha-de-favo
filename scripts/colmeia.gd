class_name Colmeia
extends Node3D

# Gerencia produção de mel, níveis da colmeia, abelhas ativas e interface de gestão.


# --- SINAIS ---

## Emitido quando o jogador coleta mel com sucesso; 'quantidade' é o total coletado
signal mel_coletado(quantidade: int)

## Emitido quando um CharacterBody3D entra na área de detecção da colmeia
signal jogador_entrou_colmeia

## Emitido quando um CharacterBody3D sai da área de detecção da colmeia
signal jogador_saiu_colmeia


# --- IDENTIFICAÇÃO ---

## ID único desta colmeia — usado como chave no save para múltiplas colmeias no futuro
@export var id_colmeia: String = "colmeia_principal"


# --- CONFIGURAÇÃO ---

## Incremento de progresso de mel por ciclo completo de uma única abelha
const INCREMENTO_POR_ABELHA: float = 0.33

## Custo promocional da primeira abelha comprada no jogo
const CUSTO_PRIMEIRA_ABELHA: int = 30

## Incremento de custo aplicado a cada nova abelha comprada para esta colmeia
const INCREMENTO_CUSTO_POR_ABELHA: int = 20

## Custos de upgrade por nível atual (índice 1..4); nível 5 não tem upgrade
const CUSTO_UPGRADE_POR_NIVEL: Array[int] = [0, 120, 260, 420, 650]

## Capacidade máxima de abelhas por nível da colmeia (níveis 1..5)
const CAPACIDADE_POR_NIVEL: Array[int] = [2, 5, 7, 10, 15]

## Duração do cooldown de upgrade em segundos (5 minutos)
const TEMPO_COOLDOWN_UPGRADE: float = 300.0

## Capacidade de estoque de mel por nível (1..5)
const CAPACIDADE_ESTOQUE_MEL_POR_NIVEL: Array[int] = [5, 15, 35, 75, 150]

## Custo de upgrade do estoque de mel por nível atual (índice 1..4)
const CUSTO_UPGRADE_ESTOQUE_MEL_POR_NIVEL: Array[int] = [0, 70, 170, 360, 720]

## Altura base do voo das abelhas ao redor desta colmeia
@export var altura_voo_abelhas: float = 1.55

## Altura do ponto de entrada/saída das abelhas nesta colmeia
@export var altura_entrada_saida_abelhas: float = 1.35

## Multiplicador de produção de mel por raridade da colmeia
const MULTIPLICADOR_RARIDADE: Dictionary = {
	"comum": 1.0,
	"incomum": 1.2,
	"rara": 1.45,
	"epica": 1.8,
	"lendaria": 2.3,
}

## Multiplicador de duração de upgrade por raridade da colmeia
const MULTIPLICADOR_TEMPO_UPGRADE_RARIDADE: Dictionary = {
	"comum": 1.0,
	"incomum": 1.2,
	"rara": 1.45,
	"epica": 1.8,
	"lendaria": 2.3,
}

## Caminho do recurso de mel produzido por raridade
const RECURSO_MEL_POR_RARIDADE: Dictionary = {
	"comum": "res://resources/mel.tres",
	"incomum": "res://resources/mel_incomum.tres",
	"rara": "res://resources/mel_raro.tres",
	"epica": "res://resources/mel_epico.tres",
	"lendaria": "res://resources/mel_lendario.tres",
}

## Cor base (estoque vazio) por raridade da colmeia
const COR_BASE_RARIDADE: Dictionary = {
	"comum": Color(0.92, 0.70, 0.20),
	"incomum": Color(0.48, 0.82, 0.40),
	"rara": Color(0.38, 0.64, 0.98),
	"epica": Color(0.76, 0.45, 0.94),
	"lendaria": Color(1.00, 0.66, 0.20),
}

## Cor alvo (estoque cheio) por raridade da colmeia
const COR_CHEIA_RARIDADE: Dictionary = {
	"comum": Color(0.98, 0.55, 0.04),
	"incomum": Color(0.20, 0.70, 0.26),
	"rara": Color(0.18, 0.42, 0.90),
	"epica": Color(0.50, 0.20, 0.80),
	"lendaria": Color(1.00, 0.40, 0.05),
}


# --- ESTADO DE MEL ---

## Progresso parcial para gerar a próxima unidade de mel (0.0..1.0)
var progresso_mel: float = 0.0

## Quantidade atualmente armazenada no estoque da colmeia
var mel_armazenado: int = 0

## Nível atual do estoque de mel (1..5)
var nivel_estoque_mel: int = 1

## True quando existe mel armazenado e o jogador pode coletar
var mel_pronto: bool = false


# --- ESTADO DA COLMEIA ---

## Nível atual da colmeia (1..5)
var nivel_colmeia: int = 1

## Quantidade de abelhas atualmente alocadas nesta colmeia
var abelhas_ativas: int = 0

## Raridade visual/produtiva da colmeia (comum, incomum, rara, epica, lendaria)
var raridade_colmeia: String = "comum"

## Nível que será aplicado ao terminar o cooldown; 0 indica sem upgrade pendente
var _nivel_pendente_upgrade: int = 0

## Tempo restante do cooldown de upgrade em segundos
var _cooldown_upgrade_restante: float = 0.0

## Acumulador para salvar estado do cooldown em intervalos (evita escrita por frame)
var _acumulador_salvamento_cooldown: float = 0.0

## True enquanto o upgrade aguarda todas as abelhas entrarem para então pausar produção
var _upgrade_aguardando_recolhimento: bool = false


# --- NÓS FILHOS 3D ---

## CSGBox3D que representa visualmente o corpo da colmeia
var _corpo: CSGBox3D = null

## Material do corpo — mantido como referência para alterar a cor dinamicamente
var _mat_corpo: StandardMaterial3D = null

## Todas as abelhas ativas da colmeia
var _abelhas: Array[Abelha] = []

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


# --- NÓS FILHOS UI ---

## CanvasLayer da interface de gestão da colmeia
var _ui_layer: CanvasLayer = null

## Label principal com estado de nível/capacidade da colmeia
var _ui_status: Label = null

## Label secundário com status do cooldown de upgrade
var _ui_cooldown: Label = null

## Label de feedback das ações do jogador
var _ui_feedback: Label = null

## Botão para comprar abelha diretamente para esta colmeia
var _btn_comprar_abelha: Button = null

## Botão para iniciar upgrade da colmeia
var _btn_upgrade: Button = null

## Botão para upgrade do estoque de mel da colmeia
var _btn_upgrade_estoque_mel: Button = null

## Botão para coletar mel diretamente pela interface da colmeia
var _btn_coletar_mel: Button = null

## Referência ao jogador que abriu a interface; usada para coletar mel via GUI
var _jogador_ui: Node = null


# --- CICLO DE VIDA ---

func _ready() -> void:
	add_to_group("colmeia")
	_criar_corpo()
	_criar_barra_progresso()
	_criar_hint_label()
	_criar_area_deteccao()
	_criar_ui_colmeia()
	_carregar_estado()
	_sincronizar_abelhas()
	_atualizar_visual_completo()
	_atualizar_visibilidade_barra_mel()
	_atualizar_ui_colmeia()
	_salvar_estado()
	set_process(true)


func _process(delta: float) -> void:
	if _upgrade_aguardando_recolhimento and _todas_abelhas_dentro_para_upgrade():
		_upgrade_aguardando_recolhimento = false
		_definir_producao_ativa(false)
		_ui_feedback.text = "Upgrade iniciado. Abelhas recolhidas, producao pausada."
		_salvar_estado()
		_atualizar_visibilidade_barra_mel()
		_atualizar_ui_colmeia()

	if _cooldown_upgrade_restante <= 0.0:
		return
	_cooldown_upgrade_restante = maxf(_cooldown_upgrade_restante - delta, 0.0)
	_acumulador_salvamento_cooldown += delta
	if _cooldown_upgrade_restante <= 0.0:
		_finalizar_upgrade()
	elif _acumulador_salvamento_cooldown >= 1.0:
		_acumulador_salvamento_cooldown = 0.0
		_salvar_estado()
	_atualizar_ui_colmeia()


# --- CRIAÇÃO VISUAL 3D ---

## Cria o corpo cúbico da colmeia com material que muda de cor conforme o mel enche
func _criar_corpo() -> void:
	_corpo = CSGBox3D.new()
	_corpo.name = "CorpoColmeia"
	_corpo.size = Vector3(1.0, 0.7, 1.0)
	_corpo.position.y = 0.35  # Apoia a base em y=0
	_corpo.visible = true
	_mat_corpo = StandardMaterial3D.new()
	#_mat_corpo.albedo_color = Color(0.92, 0.70, 0.20)  # Amarelo pálido (colmeia vazia)
	#_corpo.material_override = _mat_corpo
	add_child(_corpo)


## Cria os dois quads 3D billboard que formam a barra de progresso flutuante
func _criar_barra_progresso() -> void:
	_barra_container = Node3D.new()
	_barra_container.name = "BarraMel"
	_barra_container.position = Vector3(0.0, 1.4, 0.0)
	_barra_container.visible = false
	add_child(_barra_container)

	var espessura: float = 0.04
	var altura: float = 0.14

	# Fundo escuro um pouco maior que o fill para criar efeito de borda
	var fundo := MeshInstance3D.new()
	var mesh_fundo := BoxMesh.new()
	mesh_fundo.size = Vector3(_largura_barra + 0.06, altura + 0.04, espessura)
	fundo.mesh = mesh_fundo
	var mat_fundo := StandardMaterial3D.new()
	mat_fundo.albedo_color = Color(0.12, 0.10, 0.08)
	mat_fundo.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat_fundo.no_depth_test = true
	mat_fundo.render_priority = 0
	fundo.material_override = mat_fundo
	fundo.position.z = -0.02
	_barra_container.add_child(fundo)

	# Fill amarelo mel que escala no eixo X de 0 a 1 conforme o progresso
	_barra_fill = MeshInstance3D.new()
	var mesh_fill := BoxMesh.new()
	mesh_fill.size = Vector3(_largura_barra, altura, espessura)
	_barra_fill.mesh = mesh_fill
	var mat_fill := StandardMaterial3D.new()
	mat_fill.albedo_color = Color(0.96, 0.76, 0.08)
	mat_fill.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat_fill.no_depth_test = true
	mat_fill.render_priority = 1
	_barra_fill.material_override = mat_fill
	_barra_fill.position.z = 0.02
	_barra_container.add_child(_barra_fill)


## Cria o Label3D de instrução visível quando o mel está pronto para coletar
func _criar_hint_label() -> void:
	_hint_label = Label3D.new()
	_hint_label.name = "HintMel"
	_hint_label.text = "E — abrir gestao"
	_hint_label.font_size = 26
	_hint_label.modulate = Color(1.0, 0.88, 0.15)
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
	forma.radius = 1.8
	forma.height = 3.0
	col.shape = forma
	col.position.y = 1.0

	_area_deteccao.add_child(col)
	_area_deteccao.body_entered.connect(_ao_entrar_area)
	_area_deteccao.body_exited.connect(_ao_sair_area)
	add_child(_area_deteccao)


# --- CRIAÇÃO UI ---

## Cria a interface 2D da colmeia para compra/alocação de abelhas e upgrade.
func _criar_ui_colmeia() -> void:
	_ui_layer = CanvasLayer.new()
	_ui_layer.name = "UICOLMEIA"
	_ui_layer.layer = 25
	_ui_layer.visible = false
	add_child(_ui_layer)

	var raiz := Control.new()
	raiz.name = "RaizUIColmeia"
	raiz.anchors_preset = Control.PRESET_FULL_RECT
	raiz.mouse_filter = Control.MOUSE_FILTER_STOP
	_ui_layer.add_child(raiz)

	var fundo := ColorRect.new()
	fundo.name = "FundoUIColmeia"
	fundo.anchors_preset = Control.PRESET_FULL_RECT
	fundo.color = Color(0.0, 0.0, 0.0, 0.4)
	fundo.mouse_filter = Control.MOUSE_FILTER_STOP
	raiz.add_child(fundo)

	var centro := CenterContainer.new()
	centro.anchors_preset = Control.PRESET_FULL_RECT
	centro.mouse_filter = Control.MOUSE_FILTER_IGNORE
	raiz.add_child(centro)

	var painel := PanelContainer.new()
	painel.custom_minimum_size = Vector2(520.0, 360.0)
	centro.add_child(painel)

	var coluna := VBoxContainer.new()
	coluna.add_theme_constant_override("separation", 10)
	painel.add_child(coluna)

	var titulo := Label.new()
	titulo.text = "GESTAO DA COLMEIA"
	titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	titulo.add_theme_font_size_override("font_size", 26)
	coluna.add_child(titulo)

	_ui_status = Label.new()
	_ui_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	coluna.add_child(_ui_status)

	_ui_cooldown = Label.new()
	_ui_cooldown.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	coluna.add_child(_ui_cooldown)

	_ui_feedback = Label.new()
	_ui_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ui_feedback.add_theme_color_override("font_color", Color(1.0, 0.88, 0.3))
	coluna.add_child(_ui_feedback)

	_btn_coletar_mel = Button.new()
	_btn_coletar_mel.text = "Coletar mel"
	_btn_coletar_mel.custom_minimum_size = Vector2(0.0, 44.0)
	_btn_coletar_mel.pressed.connect(_ao_btn_coletar_mel)
	coluna.add_child(_btn_coletar_mel)

	_btn_comprar_abelha = Button.new()
	_btn_comprar_abelha.text = "Comprar abelha para colmeia"
	_btn_comprar_abelha.custom_minimum_size = Vector2(0.0, 44.0)
	_btn_comprar_abelha.pressed.connect(_ao_btn_comprar_abelha)
	coluna.add_child(_btn_comprar_abelha)

	_btn_upgrade = Button.new()
	_btn_upgrade.text = "Fazer upgrade da colmeia"
	_btn_upgrade.custom_minimum_size = Vector2(0.0, 44.0)
	_btn_upgrade.pressed.connect(_ao_btn_upgrade_colmeia)
	coluna.add_child(_btn_upgrade)

	_btn_upgrade_estoque_mel = Button.new()
	_btn_upgrade_estoque_mel.text = "Aprimorar estoque de mel"
	_btn_upgrade_estoque_mel.custom_minimum_size = Vector2(0.0, 44.0)
	_btn_upgrade_estoque_mel.pressed.connect(_ao_btn_upgrade_estoque_mel)
	coluna.add_child(_btn_upgrade_estoque_mel)

	var btn_fechar := Button.new()
	btn_fechar.text = "Fechar"
	btn_fechar.custom_minimum_size = Vector2(0.0, 44.0)
	btn_fechar.pressed.connect(_fechar_interface_colmeia)
	coluna.add_child(btn_fechar)


# --- CONTROLE DA UI ---

## Tenta abrir a interface da colmeia quando o jogador clica nela.
## Retorna true se a interface foi aberta com sucesso.
func tentar_abrir_interface_colmeia(jogador: Node) -> bool:
	if not _jogador_proximo:
		return false
	_jogador_ui = jogador
	_abrir_interface_colmeia()
	return true


## Abre a interface da colmeia e atualiza seu conteúdo.
func _abrir_interface_colmeia() -> void:
	_ui_feedback.text = ""
	_ui_layer.visible = true
	_atualizar_ui_colmeia()


## Fecha a interface da colmeia.
func _fechar_interface_colmeia() -> void:
	if _ui_layer != null:
		_ui_layer.visible = false


## Atualiza textos e estados dos botões da interface da colmeia.
func _atualizar_ui_colmeia() -> void:
	if _ui_status == null:
		return
	var capacidade_abelhas: int = _obter_capacidade_nivel(nivel_colmeia)
	var capacidade_mel: int = _obter_capacidade_estoque_mel(nivel_estoque_mel)
	var bonus_percentual: int = int(round((_obter_multiplicador_raridade() - 1.0) * 100.0))
	var tipo_mel: String = _obter_nome_mel_por_raridade()
	var texto_status := "Raridade: %s (+%d%% mel) | Tipo: %s | Nivel colmeia %d | Abelhas: %d/%d | Estoque mel Nv %d: %d/%d | Moedas: %d" % [
		raridade_colmeia.capitalize(), bonus_percentual, tipo_mel, nivel_colmeia, abelhas_ativas, capacidade_abelhas, nivel_estoque_mel, mel_armazenado, capacidade_mel, GerenciadorMundo.moedas
	]
	_ui_status.text = texto_status

	if _cooldown_upgrade_restante > 0.0:
		_ui_cooldown.text = "Upgrade em andamento para nivel %d. Tempo restante: %s" % [
			_nivel_pendente_upgrade, _formatar_tempo(_cooldown_upgrade_restante)
		]
	else:
		var incremento_real: float = INCREMENTO_POR_ABELHA * _obter_multiplicador_raridade()
		var fator_upgrade: float = _obter_multiplicador_tempo_upgrade_raridade()
		_ui_cooldown.text = "Producao ativa. Cada abelha contribui com +%.2f por ciclo. Tempo de upgrade x%.2f." % [incremento_real, fator_upgrade]

	var custo_abelha: int = _obter_custo_compra_abelha()
	_btn_comprar_abelha.text = "Comprar abelha para colmeia — %d moedas" % custo_abelha
	_btn_comprar_abelha.disabled = abelhas_ativas >= capacidade_abelhas
	_btn_coletar_mel.disabled = mel_armazenado <= 0

	if nivel_colmeia >= 5:
		_btn_upgrade.text = "Upgrade da colmeia (nivel maximo)"
		_btn_upgrade.disabled = true
	else:
		var custo: int = _obter_custo_upgrade(nivel_colmeia)
		_btn_upgrade.text = "Upgrade para nivel %d — %d moedas" % [nivel_colmeia + 1, custo]
		_btn_upgrade.disabled = _cooldown_upgrade_restante > 0.0

	if nivel_estoque_mel >= 5:
		_btn_upgrade_estoque_mel.text = "Estoque de mel (nivel maximo)"
		_btn_upgrade_estoque_mel.disabled = true
	else:
		var custo_estoque: int = _obter_custo_upgrade_estoque_mel(nivel_estoque_mel)
		_btn_upgrade_estoque_mel.text = "Aprimorar estoque para nivel %d — %d moedas" % [nivel_estoque_mel + 1, custo_estoque]
		_btn_upgrade_estoque_mel.disabled = false


## Retorna uma string MM:SS para o tempo restante.
func _formatar_tempo(segundos: float) -> String:
	var total: int = int(ceil(segundos))
	var mm: int = total / 60
	var ss: int = total % 60
	return "%02d:%02d" % [mm, ss]


## Compra uma abelha diretamente para esta colmeia, respeitando o limite do nível.
func _ao_btn_comprar_abelha() -> void:
	var capacidade: int = _obter_capacidade_nivel(nivel_colmeia)
	if abelhas_ativas >= capacidade:
		_ui_feedback.text = "Limite de abelhas atingido neste nivel."
		return
	var custo_compra: int = _obter_custo_compra_abelha()
	if not GerenciadorMundo.tem_dinheiro(custo_compra):
		_ui_feedback.text = "Moedas insuficientes para comprar abelha."
		return
	GerenciadorMundo.gastar(custo_compra)
	abelhas_ativas += 1
	_sincronizar_abelhas()
	_salvar_estado()
	_ui_feedback.text = "Abelha comprada com sucesso para esta colmeia."
	_atualizar_ui_colmeia()


## Coleta mel pela interface da colmeia quando disponível.
func _ao_btn_coletar_mel() -> void:
	if mel_armazenado <= 0:
		_ui_feedback.text = "Ainda nao ha mel pronto para coleta."
		return
	if _jogador_ui == null:
		_ui_feedback.text = "Jogador nao encontrado para coletar mel."
		return
	var mel_antes: int = mel_armazenado
	tentar_coletar(_jogador_ui)
	if mel_armazenado == mel_antes:
		_ui_feedback.text = "Mochila de mel cheia."
	else:
		_ui_feedback.text = "Mel coletado com sucesso."
	_atualizar_ui_colmeia()


## Aprimora o estoque de mel da colmeia para aumentar a capacidade máxima.
func _ao_btn_upgrade_estoque_mel() -> void:
	if nivel_estoque_mel >= 5:
		_ui_feedback.text = "Estoque de mel ja esta no nivel maximo."
		return
	var custo: int = _obter_custo_upgrade_estoque_mel(nivel_estoque_mel)
	if not GerenciadorMundo.tem_dinheiro(custo):
		_ui_feedback.text = "Moedas insuficientes para aprimorar o estoque."
		return

	GerenciadorMundo.gastar(custo)
	nivel_estoque_mel += 1
	var nova_capacidade: int = _obter_capacidade_estoque_mel(nivel_estoque_mel)
	mel_armazenado = mini(mel_armazenado, nova_capacidade)
	mel_pronto = mel_armazenado > 0
	_hint_label.visible = mel_pronto
	_atualizar_visual_completo()
	_atualizar_visibilidade_barra_mel()
	_salvar_estado()
	_ui_feedback.text = "Estoque de mel aprimorado para nivel %d." % nivel_estoque_mel
	_atualizar_ui_colmeia()


## Inicia upgrade da colmeia com cooldown de 5 minutos sem produção.
func _ao_btn_upgrade_colmeia() -> void:
	if nivel_colmeia >= 5:
		_ui_feedback.text = "Esta colmeia ja esta no nivel maximo."
		return
	if _cooldown_upgrade_restante > 0.0:
		_ui_feedback.text = "Upgrade ja em andamento."
		return

	var custo: int = _obter_custo_upgrade(nivel_colmeia)
	if not GerenciadorMundo.tem_dinheiro(custo):
		_ui_feedback.text = "Moedas insuficientes para upgrade."
		return

	GerenciadorMundo.gastar(custo)
	_nivel_pendente_upgrade = nivel_colmeia + 1
	_cooldown_upgrade_restante = TEMPO_COOLDOWN_UPGRADE * _obter_multiplicador_tempo_upgrade_raridade()
	_acumulador_salvamento_cooldown = 0.0
	_upgrade_aguardando_recolhimento = true
	_solicitar_recolhimento_abelhas()
	_ui_feedback.text = "Upgrade iniciado. Aguardando abelhas entrarem para pausar producao."
	_salvar_estado()
	_atualizar_visibilidade_barra_mel()
	_atualizar_ui_colmeia()


# --- CONTROLE DE ABELHAS ---

## Retorna a capacidade máxima de abelhas para o nível informado.
func _obter_capacidade_nivel(nivel: int) -> int:
	var indice: int = clampi(nivel, 1, 5) - 1
	return CAPACIDADE_POR_NIVEL[indice]


## Retorna o custo do upgrade com base no nível atual.
func _obter_custo_upgrade(nivel_atual: int) -> int:
	var indice: int = clampi(nivel_atual, 1, 4)
	return CUSTO_UPGRADE_POR_NIVEL[indice]


## Retorna o custo atual da compra de abelha nesta colmeia.
## A cada abelha comprada, o custo da próxima aumenta.
func _obter_custo_compra_abelha() -> int:
	return CUSTO_PRIMEIRA_ABELHA + (abelhas_ativas * INCREMENTO_CUSTO_POR_ABELHA)


## Retorna a capacidade máxima de estoque de mel para o nível informado.
func _obter_capacidade_estoque_mel(nivel: int) -> int:
	var indice: int = clampi(nivel, 1, 5) - 1
	return CAPACIDADE_ESTOQUE_MEL_POR_NIVEL[indice]


## Retorna o custo de upgrade do estoque de mel com base no nível atual.
func _obter_custo_upgrade_estoque_mel(nivel_atual: int) -> int:
	var indice: int = clampi(nivel_atual, 1, 4)
	return CUSTO_UPGRADE_ESTOQUE_MEL_POR_NIVEL[indice]


## Retorna o percentual de preenchimento do estoque de mel (0.0..1.0).
func _obter_percentual_estoque_mel() -> float:
	var capacidade: int = _obter_capacidade_estoque_mel(nivel_estoque_mel)
	if capacidade <= 0:
		return 0.0
	return clampf(float(mel_armazenado) / float(capacidade), 0.0, 1.0)


## Define a raridade da colmeia e atualiza visual/UI imediatamente.
func configurar_raridade_colmeia(raridade: String) -> void:
	raridade_colmeia = _normalizar_raridade(raridade)
	_atualizar_visual_completo()
	_atualizar_ui_colmeia()


## Normaliza a string de raridade, garantindo fallback seguro para "comum".
func _normalizar_raridade(raridade: String) -> String:
	var chave: String = raridade.strip_edges().to_lower()
	if MULTIPLICADOR_RARIDADE.has(chave):
		return chave
	return "comum"


## Retorna o multiplicador de produção baseado na raridade da colmeia.
func _obter_multiplicador_raridade() -> float:
	var chave: String = _normalizar_raridade(raridade_colmeia)
	if MULTIPLICADOR_RARIDADE.has(chave):
		return float(MULTIPLICADOR_RARIDADE[chave])
	return 1.0


## Retorna o multiplicador de tempo de upgrade baseado na raridade da colmeia.
func _obter_multiplicador_tempo_upgrade_raridade() -> float:
	var chave: String = _normalizar_raridade(raridade_colmeia)
	if MULTIPLICADOR_TEMPO_UPGRADE_RARIDADE.has(chave):
		return float(MULTIPLICADOR_TEMPO_UPGRADE_RARIDADE[chave])
	return 1.0


## Retorna o caminho do recurso de mel produzido por esta raridade.
func _obter_caminho_recurso_mel_raridade() -> String:
	var chave: String = _normalizar_raridade(raridade_colmeia)
	if RECURSO_MEL_POR_RARIDADE.has(chave):
		return String(RECURSO_MEL_POR_RARIDADE[chave])
	return "res://resources/mel.tres"


## Retorna o item de mel produzido por esta colmeia, ou null se o recurso não existir.
func _obter_item_mel_raridade() -> Item:
	var caminho_item: String = _obter_caminho_recurso_mel_raridade()
	if not ResourceLoader.exists(caminho_item):
		return null
	var item_mel: Item = load(caminho_item)
	return item_mel


## Retorna o nome de exibição do mel produzido por esta raridade.
func _obter_nome_mel_por_raridade() -> String:
	var item_mel: Item = _obter_item_mel_raridade()
	if item_mel != null and not item_mel.nome_exibicao.is_empty():
		return item_mel.nome_exibicao
	return "Mel"


## Retorna a cor base da colmeia para a raridade atual.
func _obter_cor_base_raridade() -> Color:
	var chave: String = _normalizar_raridade(raridade_colmeia)
	if COR_BASE_RARIDADE.has(chave):
		return COR_BASE_RARIDADE[chave] as Color
	return Color(0.92, 0.70, 0.20)


## Retorna a cor de estoque cheio da colmeia para a raridade atual.
func _obter_cor_cheia_raridade() -> Color:
	var chave: String = _normalizar_raridade(raridade_colmeia)
	if COR_CHEIA_RARIDADE.has(chave):
		return COR_CHEIA_RARIDADE[chave] as Color
	return Color(0.98, 0.55, 0.04)


## Sincroniza a quantidade de nós Abelha com o valor de abelhas_ativas.
func _sincronizar_abelhas() -> void:
	var capacidade: int = _obter_capacidade_nivel(nivel_colmeia)
	abelhas_ativas = clampi(abelhas_ativas, 0, capacidade)

	while _abelhas.size() < abelhas_ativas:
		_adicionar_abelha()
	while _abelhas.size() > abelhas_ativas:
		_remover_abelha()

	_atualizar_formacao_abelhas()
	if _upgrade_aguardando_recolhimento:
		_solicitar_recolhimento_abelhas()
	elif _cooldown_upgrade_restante > 0.0:
		_definir_producao_ativa(false)
	else:
		_definir_producao_ativa(true)


## Cria uma nova abelha, conecta seu sinal e adiciona na lista interna.
func _adicionar_abelha() -> void:
	var abelha := Abelha.new()
	abelha.name = "Abelha%d" % (_abelhas.size() + 1)
	abelha.altura_voo_base = altura_voo_abelhas
	abelha.altura_entrada_colmeia = altura_entrada_saida_abelhas
	abelha.ciclo_mel_completo.connect(_ao_ciclo_mel_completo)
	add_child(abelha)
	_abelhas.append(abelha)


## Remove a última abelha da lista interna e libera seu nó.
func _remover_abelha() -> void:
	if _abelhas.is_empty():
		return
	var abelha: Abelha = _abelhas.pop_back() as Abelha
	if abelha != null and is_instance_valid(abelha):
		abelha.queue_free()


## Distribui abelhas em órbitas para evitar sobreposição visual.
func _atualizar_formacao_abelhas() -> void:
	var total: int = _abelhas.size()
	if total <= 0:
		return
	for i in total:
		var abelha: Abelha = _abelhas[i]
		abelha.altura_voo_base = altura_voo_abelhas
		abelha.altura_entrada_colmeia = altura_entrada_saida_abelhas
		var camada: int = i / 5
		abelha.raio_orbita = 1.55 + float(camada) * 0.24
		var angulo: float = TAU * float(i) / float(total)
		abelha.definir_angulo_inicial(angulo)


## Ativa/desativa produção em todas as abelhas da colmeia.
func _definir_producao_ativa(ativa: bool) -> void:
	for abelha in _abelhas:
		abelha.definir_producao_ativa(ativa)


## Solicita que todas as abelhas recolham e aguardem dentro da colmeia.
func _solicitar_recolhimento_abelhas() -> void:
	for abelha in _abelhas:
		abelha.solicitar_recolhimento_para_pausa()


## Retorna true quando todas as abelhas ativas já estão dentro da colmeia.
func _todas_abelhas_dentro_para_upgrade() -> bool:
	for abelha in _abelhas:
		if not abelha.esta_dentro_colmeia():
			return false
	return true


## Finaliza o upgrade após cooldown, sobe o nível e reativa a produção.
func _finalizar_upgrade() -> void:
	_upgrade_aguardando_recolhimento = false
	if _nivel_pendente_upgrade > nivel_colmeia:
		nivel_colmeia = _nivel_pendente_upgrade
	_nivel_pendente_upgrade = 0
	_sincronizar_abelhas()
	_definir_producao_ativa(true)
	_ui_feedback.text = "Upgrade concluido. Novo nivel da colmeia: %d." % nivel_colmeia
	_salvar_estado()
	_atualizar_visibilidade_barra_mel()
	_atualizar_ui_colmeia()


# --- CALLBACKS DA ÁREA ---

## Disparado quando um corpo entra na área; exibe barra e emite sinal para o player.
func _ao_entrar_area(body: Node3D) -> void:
	if not (body is CharacterBody3D):
		return
	_jogador_proximo = true
	_atualizar_visibilidade_barra_mel()
	_atualizar_fill_barra(_obter_percentual_estoque_mel())
	jogador_entrou_colmeia.emit()


## Disparado quando um corpo sai da área; esconde barra e fecha UI da colmeia.
func _ao_sair_area(body: Node3D) -> void:
	if not (body is CharacterBody3D):
		return
	_jogador_proximo = false
	_atualizar_visibilidade_barra_mel()
	_jogador_ui = null
	_fechar_interface_colmeia()
	jogador_saiu_colmeia.emit()


# --- PRODUÇÃO DE MEL ---

## Chamado por qualquer abelha ao concluir um ciclo.
func _ao_ciclo_mel_completo() -> void:
	if _cooldown_upgrade_restante > 0.0:
		return
	var capacidade_estoque: int = _obter_capacidade_estoque_mel(nivel_estoque_mel)
	if mel_armazenado >= capacidade_estoque:
		progresso_mel = 0.0
		mel_pronto = true
		_hint_label.visible = true
		_atualizar_visual_completo()
		_atualizar_visibilidade_barra_mel()
		_atualizar_ui_colmeia()
		_salvar_estado()
		return

	progresso_mel += INCREMENTO_POR_ABELHA * _obter_multiplicador_raridade()
	while progresso_mel >= 1.0 and mel_armazenado < capacidade_estoque:
		progresso_mel -= 1.0
		mel_armazenado += 1

	if mel_armazenado >= capacidade_estoque:
		mel_armazenado = capacidade_estoque
		progresso_mel = 0.0

	mel_pronto = mel_armazenado > 0
	_hint_label.visible = mel_pronto
	_atualizar_visual_completo()
	if mel_armazenado >= capacidade_estoque:
		_animar_pulso_pronto()
	_atualizar_visibilidade_barra_mel()
	_atualizar_ui_colmeia()
	_salvar_estado()


# --- COLETA ---

## Chamada pelo Player ao pressionar E próximo à colmeia quando existe mel armazenado.
## Adiciona ao inventário até o limite da mochila e atualiza o contador global.
func tentar_coletar(jogador: Node) -> void:
	if mel_armazenado <= 0:
		return
	var quantidade_solicitada: int = mel_armazenado
	var quantidade_coletada: int = 0

	var inv: Node = jogador.get_node_or_null("Inventario")
	if inv != null:
		var item_mel: Item = _obter_item_mel_raridade()
		if item_mel != null:
			var restante: int = inv.adicionar_item(item_mel, quantidade_solicitada)
			quantidade_coletada = quantidade_solicitada - restante

	if quantidade_coletada <= 0:
		return

	GerenciadorMundo.total_mel_coletado += quantidade_coletada

	mel_armazenado = maxi(mel_armazenado - quantidade_coletada, 0)
	mel_pronto = mel_armazenado > 0
	_hint_label.visible = mel_pronto
	_atualizar_visibilidade_barra_mel()
	_atualizar_visual_completo()
	_animar_feedback_coleta()
	_atualizar_ui_colmeia()

	mel_coletado.emit(quantidade_coletada)
	_salvar_estado()


# --- VISUAL ---

## Atualiza ao mesmo tempo a cor do corpo (amarelo pálido → laranja mel) e o fill da barra.
func _atualizar_visual_completo() -> void:
	if _mat_corpo == null:
		return
	var percentual_estoque: float = _obter_percentual_estoque_mel()
	var cor_vazia: Color = _obter_cor_base_raridade()
	var cor_cheia: Color = _obter_cor_cheia_raridade()
	_mat_corpo.albedo_color = cor_vazia.lerp(cor_cheia, percentual_estoque)
	_atualizar_fill_barra(percentual_estoque)


## Ajusta o scale.x do fill e sua posição para simular barra que cresce da esquerda.
func _atualizar_fill_barra(progresso: float) -> void:
	if _barra_fill == null:
		return
	_barra_fill.scale.x = maxf(progresso, 0.001)
	_barra_fill.position.x = (progresso - 1.0) * (_largura_barra * 0.5)


## Pulsa o corpo 3 vezes para indicar ao jogador que o mel está pronto.
func _animar_pulso_pronto() -> void:
	var tween := create_tween().set_loops(3)
	tween.tween_property(_corpo, "scale", Vector3(1.12, 1.12, 1.12), 0.18) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(_corpo, "scale", Vector3.ONE, 0.18) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)


## Feedback "squash and stretch" ao coletar: encolhe horizontalmente e volta.
func _animar_feedback_coleta() -> void:
	var tween := create_tween()
	tween.tween_property(_corpo, "scale", Vector3(0.8, 1.25, 0.8), 0.12) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_corpo, "scale", Vector3.ONE, 0.22) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)


# --- PERSISTÊNCIA ---

## Carrega o estado salvo da colmeia via GerenciadorMundo; se não existir, usa padrão.
func _carregar_estado() -> void:
	var dados := GerenciadorMundo.carregar_estado_colmeia(id_colmeia)
	if dados.is_empty():
		return

	progresso_mel = float(dados.get("progresso_mel", 0.0))
	mel_armazenado = maxi(int(dados.get("mel_armazenado", 0)), 0)
	if not dados.has("mel_armazenado") and progresso_mel >= 1.0:
		mel_armazenado = 1
		progresso_mel = 0.0
	nivel_estoque_mel = clampi(int(dados.get("nivel_estoque_mel", 1)), 1, 5)
	var capacidade_estoque: int = _obter_capacidade_estoque_mel(nivel_estoque_mel)
	mel_armazenado = mini(mel_armazenado, capacidade_estoque)
	mel_pronto = mel_armazenado > 0

	nivel_colmeia = clampi(int(dados.get("nivel_colmeia", 1)), 1, 5)
	abelhas_ativas = maxi(int(dados.get("abelhas_ativas", 0)), 0)
	raridade_colmeia = _normalizar_raridade(str(dados.get("raridade_colmeia", raridade_colmeia)))
	_cooldown_upgrade_restante = maxf(float(dados.get("cooldown_upgrade_restante", 0.0)), 0.0)
	_acumulador_salvamento_cooldown = 0.0
	_nivel_pendente_upgrade = clampi(int(dados.get("nivel_pendente_upgrade", 0)), 0, 5)
	_upgrade_aguardando_recolhimento = bool(dados.get("upgrade_aguardando_recolhimento", false))

	if _cooldown_upgrade_restante > 0.0 and _nivel_pendente_upgrade <= nivel_colmeia and nivel_colmeia < 5:
		_nivel_pendente_upgrade = nivel_colmeia + 1

	_hint_label.visible = mel_pronto
	_atualizar_visibilidade_barra_mel()


## Retorna o estado atual serializado para salvar via GerenciadorMundo.
func _obter_estado() -> Dictionary:
	return {
		"progresso_mel": progresso_mel,
		"mel_armazenado": mel_armazenado,
		"nivel_estoque_mel": nivel_estoque_mel,
		"nivel_colmeia": nivel_colmeia,
		"abelhas_ativas": abelhas_ativas,
		"raridade_colmeia": raridade_colmeia,
		"cooldown_upgrade_restante": _cooldown_upgrade_restante,
		"nivel_pendente_upgrade": _nivel_pendente_upgrade,
		"upgrade_aguardando_recolhimento": _upgrade_aguardando_recolhimento,
	}


## Persiste o estado atual desta colmeia no GerenciadorMundo.
func _salvar_estado() -> void:
	GerenciadorMundo.salvar_estado_colmeia(id_colmeia, _obter_estado())


# --- VISIBILIDADE DA BARRA ---

## Retorna true quando a colmeia está em processo de aprimoramento (esperando recolhimento ou cooldown).
func _esta_aprimorando() -> bool:
	return _upgrade_aguardando_recolhimento or _cooldown_upgrade_restante > 0.0


## Atualiza a visibilidade da barra de mel respeitando o estado de aprimoramento.
func _atualizar_visibilidade_barra_mel() -> void:
	if _barra_container == null:
		return
	if _esta_aprimorando():
		_barra_container.visible = false
		return
	_barra_container.visible = _jogador_proximo or mel_armazenado > 0
