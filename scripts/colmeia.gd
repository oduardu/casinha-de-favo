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

## Caminho do recurso centralizado de balanceamento da colmeia
const CAMINHO_BALANCEAMENTO_COLMEIA: String = "res://resources/balanceamento_colmeia.tres"

## Altura base do voo das abelhas ao redor desta colmeia
@export var altura_voo_abelhas: float = 1.55

## Altura do ponto de entrada/saída das abelhas nesta colmeia
@export var altura_entrada_saida_abelhas: float = 1.35

## Cor base (estoque vazio) por raridade da colmeia
const COR_BASE_RARIDADE: Dictionary = {
	"comum": Color(0.92, 0.70, 0.20),
	"rara": Color(0.38, 0.64, 0.98),
	"epica": Color(0.76, 0.45, 0.94),
	"lendaria": Color(1.00, 0.66, 0.20),
}

## Cor alvo (estoque cheio) por raridade da colmeia
const COR_CHEIA_RARIDADE: Dictionary = {
	"comum": Color(0.98, 0.55, 0.04),
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

## Raridade visual/produtiva da colmeia (comum, rara, epica, lendaria)
var raridade_colmeia: String = "comum"

## Nível que será aplicado ao terminar o cooldown; 0 indica sem upgrade pendente
var _nivel_pendente_upgrade: int = 0

## Tempo restante do cooldown de upgrade em segundos
var _cooldown_upgrade_restante: float = 0.0

## Acumulador para salvar estado do cooldown em intervalos (evita escrita por frame)
var _acumulador_salvamento_cooldown: float = 0.0

## True enquanto o upgrade aguarda todas as abelhas entrarem para então pausar produção
var _upgrade_aguardando_recolhimento: bool = false

## Recurso de balanceamento com valores centralizados de produção e economia
var _balanceamento: BalanceamentoColmeia = null


# --- NÓS FILHOS 3D ---

## CSGBox3D que representa visualmente o corpo da colmeia
var _corpo: CSGBox3D = null


## Todas as abelhas ativas da colmeia
var _abelhas: Array[Abelha] = []

## Area3D que detecta a proximidade do jogador para exibir hints e permitir coleta
var _area_deteccao: Area3D = null

## Label3D "Pressione E para coletar mel" — visível apenas quando mel_pronto == true
var _hint_label: Label3D = null


## True enquanto o jogador está dentro da área de detecção
var _jogador_proximo: bool = false


# --- NÓS FILHOS UI ---

## CanvasLayer da interface de gestão da colmeia
var _ui_layer: CanvasLayer = null

## Label principal com estado de nível/capacidade da colmeia
var _ui_status: Label = null

## Label secundário com status do cooldown de upgrade
var _ui_cooldown: Label = null

## Label com valor textual do estoque de mel (ex.: 12/35)
var _ui_valor_mel: Label = null

## Label com valor textual da população de abelhas (ex.: 3/7)
var _ui_valor_abelhas: Label = null

## Barra de progresso visual para o estoque de mel
var _ui_barra_mel: ProgressBar = null

## Barra de progresso visual para ocupação de abelhas
var _ui_barra_abelhas: ProgressBar = null

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
	_carregar_balanceamento()
	_criar_corpo()
	_criar_hint_label()
	_criar_area_deteccao()
	_criar_ui_colmeia()
	_carregar_estado()
	_sincronizar_abelhas()
	_atualizar_visual_completo()
	_atualizar_ui_colmeia()
	_salvar_estado()
	# Só ativa _process se houver upgrade em andamento
	set_process(_cooldown_upgrade_restante > 0.0 or _upgrade_aguardando_recolhimento)


## Timer para atualizar a UI do cooldown sem reconstruir todo frame
var _timer_ui_cooldown: float = 0.0


func _process(delta: float) -> void:
	if _upgrade_aguardando_recolhimento and _todas_abelhas_dentro_para_upgrade():
		_upgrade_aguardando_recolhimento = false
		_definir_producao_ativa(false)
		_ui_feedback.text = "Upgrade iniciado. Abelhas recolhidas, producao pausada."
		_salvar_estado()
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

	# Atualiza a UI do cooldown apenas a cada 0.5 segundos, não todo frame
	_timer_ui_cooldown += delta
	if _timer_ui_cooldown >= 0.5:
		_timer_ui_cooldown = 0.0
		_atualizar_ui_colmeia()


# --- BALANCEAMENTO ---

## Carrega o recurso de balanceamento da colmeia e garante fallback seguro.
func _carregar_balanceamento() -> void:
	if ResourceLoader.exists(CAMINHO_BALANCEAMENTO_COLMEIA):
		_balanceamento = load(CAMINHO_BALANCEAMENTO_COLMEIA) as BalanceamentoColmeia
	if _balanceamento == null:
		_balanceamento = BalanceamentoColmeia.new()


## Retorna o recurso de balanceamento sempre válido para evitar null checks espalhados.
func _obter_balanceamento_seguro() -> BalanceamentoColmeia:
	if _balanceamento != null:
		return _balanceamento
	return BalanceamentoColmeia.new()


## Retorna o incremento de progresso de mel por ciclo de abelha.
func _obter_incremento_por_abelha() -> float:
	var balanceamento: BalanceamentoColmeia = _obter_balanceamento_seguro()
	return maxf(balanceamento.incremento_por_abelha, 0.0)


## Aplica os tempos base do ciclo de mel na abelha recém-criada.
func _aplicar_balanceamento_abelha(abelha: Abelha) -> void:
	if abelha == null:
		return
	var balanceamento: BalanceamentoColmeia = _obter_balanceamento_seguro()
	abelha.tempo_voando = maxf(balanceamento.tempo_voando_base, 0.1)
	abelha.tempo_dentro_colmeia = maxf(balanceamento.tempo_dentro_colmeia_base, 0.1)


## Retorna um valor de array de inteiros com fallback seguro para índice fora do range.
func _obter_valor_array_int(valores: Array[int], indice: int, padrao: int) -> int:
	if valores.is_empty():
		return padrao
	var idx: int = clampi(indice, 0, valores.size() - 1)
	return int(valores[idx])


# --- CRIAÇÃO VISUAL 3D ---

## Cria o corpo cúbico da colmeia com material que muda de cor conforme o mel enche
func _criar_corpo() -> void:
	_corpo = CSGBox3D.new()
	_corpo.name = "CorpoColmeia"
	_corpo.size = Vector3(1.0, 0.7, 1.0)
	_corpo.position.y = 0.35  # Apoia a base em y=0
	_corpo.visible = false  # Invisível — o hex tile já fornece o visual da colmeia
	_corpo.use_collision = false  # Sem colisão — evita custo de CSG no physics
	add_child(_corpo)


## Cria os dois quads 3D billboard que formam a barra de progresso flutuante

## Cria o Label3D de instrução visível quando o mel está pronto para coletar
func _criar_hint_label() -> void:
	_hint_label = Label3D.new()
	_hint_label.name = "HintMel"
	_hint_label.text = "(E) Abrir gestao"
	_hint_label.font_size = 42
	_hint_label.modulate = Color(1.0, 0.88, 0.15)
	_hint_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_hint_label.position.y = 3.0
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
	raiz.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	raiz.mouse_filter = Control.MOUSE_FILTER_STOP
	_ui_layer.add_child(raiz)

	var fundo := ColorRect.new()
	fundo.name = "FundoUIColmeia"
	fundo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fundo.color = Color(0.0, 0.0, 0.0, 0.58)
	fundo.mouse_filter = Control.MOUSE_FILTER_STOP
	raiz.add_child(fundo)

	var centro := CenterContainer.new()
	centro.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centro.mouse_filter = Control.MOUSE_FILTER_IGNORE
	raiz.add_child(centro)

	var painel := PanelContainer.new()
	painel.custom_minimum_size = Vector2(820.0, 560.0)
	painel.add_theme_stylebox_override("panel", _criar_stylebox_painel_ui_colmeia())
	painel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	painel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	centro.add_child(painel)

	var centro_painel := CenterContainer.new()
	centro_painel.name = "CentroConteudoColmeia"
	centro_painel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centro_painel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	painel.add_child(centro_painel)

	var coluna := VBoxContainer.new()
	coluna.add_theme_constant_override("separation", 14)
	coluna.alignment = BoxContainer.ALIGNMENT_CENTER
	coluna.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	coluna.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	centro_painel.add_child(coluna)

	var titulo := Label.new()
	titulo.text = "GESTAO DA COLMEIA"
	titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	titulo.add_theme_font_size_override("font_size", 34)
	titulo.add_theme_color_override("font_color", Color(0.47, 0.33, 0.05))
	titulo.add_theme_constant_override("outline_size", 2)
	titulo.add_theme_color_override("font_outline_color", Color(1.0, 0.96, 0.88))
	coluna.add_child(titulo)

	_ui_status = Label.new()
	_ui_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ui_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ui_status.add_theme_font_size_override("font_size", 18)
	_ui_status.add_theme_color_override("font_color", Color(0.29, 0.26, 0.17))
	coluna.add_child(_ui_status)

	_ui_cooldown = Label.new()
	_ui_cooldown.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ui_cooldown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ui_cooldown.add_theme_font_size_override("font_size", 16)
	_ui_cooldown.add_theme_color_override("font_color", Color(0.42, 0.37, 0.25))
	coluna.add_child(_ui_cooldown)

	var painel_barras := GridContainer.new()
	painel_barras.columns = 2
	painel_barras.add_theme_constant_override("h_separation", 14)
	painel_barras.add_theme_constant_override("v_separation", 8)
	painel_barras.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	coluna.add_child(painel_barras)

	var cartao_mel := VBoxContainer.new()
	cartao_mel.add_theme_constant_override("separation", 8)
	painel_barras.add_child(cartao_mel)
	var label_mel := Label.new()
	label_mel.text = "ESTOQUE DE MEL"
	label_mel.add_theme_font_size_override("font_size", 14)
	label_mel.add_theme_color_override("font_color", Color(0.43, 0.33, 0.13))
	cartao_mel.add_child(label_mel)
	_ui_barra_mel = ProgressBar.new()
	_ui_barra_mel.show_percentage = false
	_ui_barra_mel.custom_minimum_size = Vector2(360.0, 24.0)
	_ui_barra_mel.add_theme_stylebox_override("background", _criar_stylebox_barra_fundo_ui_colmeia())
	_ui_barra_mel.add_theme_stylebox_override("fill", _criar_stylebox_barra_fill_ui_colmeia(Color(0.96, 0.72, 0.12)))
	cartao_mel.add_child(_ui_barra_mel)
	_ui_valor_mel = Label.new()
	_ui_valor_mel.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_ui_valor_mel.add_theme_font_size_override("font_size", 15)
	_ui_valor_mel.add_theme_color_override("font_color", Color(0.44, 0.35, 0.16))
	cartao_mel.add_child(_ui_valor_mel)

	var cartao_abelhas := VBoxContainer.new()
	cartao_abelhas.add_theme_constant_override("separation", 8)
	painel_barras.add_child(cartao_abelhas)
	var label_abelhas := Label.new()
	label_abelhas.text = "POPULACAO DE ABELHAS"
	label_abelhas.add_theme_font_size_override("font_size", 14)
	label_abelhas.add_theme_color_override("font_color", Color(0.20, 0.38, 0.17))
	cartao_abelhas.add_child(label_abelhas)
	_ui_barra_abelhas = ProgressBar.new()
	_ui_barra_abelhas.show_percentage = false
	_ui_barra_abelhas.custom_minimum_size = Vector2(360.0, 24.0)
	_ui_barra_abelhas.add_theme_stylebox_override("background", _criar_stylebox_barra_fundo_ui_colmeia())
	_ui_barra_abelhas.add_theme_stylebox_override("fill", _criar_stylebox_barra_fill_ui_colmeia(Color(0.43, 0.74, 0.28)))
	cartao_abelhas.add_child(_ui_barra_abelhas)
	_ui_valor_abelhas = Label.new()
	_ui_valor_abelhas.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_ui_valor_abelhas.add_theme_font_size_override("font_size", 15)
	_ui_valor_abelhas.add_theme_color_override("font_color", Color(0.22, 0.41, 0.19))
	cartao_abelhas.add_child(_ui_valor_abelhas)

	var grade_acoes := GridContainer.new()
	grade_acoes.columns = 2
	grade_acoes.add_theme_constant_override("h_separation", 14)
	grade_acoes.add_theme_constant_override("v_separation", 14)
	grade_acoes.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	coluna.add_child(grade_acoes)

	_btn_upgrade = Button.new()
	_btn_upgrade.text = "Atualizar colmeia"
	_btn_upgrade.custom_minimum_size = Vector2(0.0, 86.0)
	_aplicar_estilo_botao_ui_colmeia(_btn_upgrade, "primario")
	_btn_upgrade.pressed.connect(_ao_btn_upgrade_colmeia)
	grade_acoes.add_child(_btn_upgrade)

	_btn_upgrade_estoque_mel = Button.new()
	_btn_upgrade_estoque_mel.text = "Aumentar estoque"
	_btn_upgrade_estoque_mel.custom_minimum_size = Vector2(0.0, 86.0)
	_aplicar_estilo_botao_ui_colmeia(_btn_upgrade_estoque_mel, "primario")
	_btn_upgrade_estoque_mel.pressed.connect(_ao_btn_upgrade_estoque_mel)
	grade_acoes.add_child(_btn_upgrade_estoque_mel)

	_btn_comprar_abelha = Button.new()
	_btn_comprar_abelha.text = "Comprar abelhas"
	_btn_comprar_abelha.custom_minimum_size = Vector2(0.0, 86.0)
	_aplicar_estilo_botao_ui_colmeia(_btn_comprar_abelha, "natureza")
	_btn_comprar_abelha.pressed.connect(_ao_btn_comprar_abelha)
	grade_acoes.add_child(_btn_comprar_abelha)

	_btn_coletar_mel = Button.new()
	_btn_coletar_mel.text = "Colher mel"
	_btn_coletar_mel.custom_minimum_size = Vector2(0.0, 86.0)
	_aplicar_estilo_botao_ui_colmeia(_btn_coletar_mel, "primario")
	_btn_coletar_mel.pressed.connect(_ao_btn_coletar_mel)
	grade_acoes.add_child(_btn_coletar_mel)

	_ui_feedback = Label.new()
	_ui_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ui_feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ui_feedback.add_theme_color_override("font_color", Color(0.50, 0.34, 0.0))
	_ui_feedback.add_theme_font_size_override("font_size", 15)
	coluna.add_child(_ui_feedback)

	var btn_fechar := Button.new()
	btn_fechar.text = "Fechar"
	btn_fechar.custom_minimum_size = Vector2(0.0, 52.0)
	_aplicar_estilo_botao_ui_colmeia(btn_fechar, "secundario")
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
	if _hint_label != null:
		_hint_label.visible = false
	_atualizar_ui_colmeia()


## Fecha a interface da colmeia.
func _fechar_interface_colmeia() -> void:
	if _ui_layer != null:
		_ui_layer.visible = false
	if _hint_label != null and _jogador_proximo:
		_hint_label.visible = true


## Fecha a interface da colmeia por atalho (ESC) e retorna true se estava aberta.
func fechar_interface_colmeia_por_atalho() -> bool:
	if not interface_esta_aberta():
		return false
	_fechar_interface_colmeia()
	return true


## Retorna true quando a interface de gestão da colmeia está visível.
func interface_esta_aberta() -> bool:
	return _ui_layer != null and _ui_layer.visible


## Atualiza textos e estados dos botões da interface da colmeia.
func _atualizar_ui_colmeia() -> void:
	if _ui_status == null:
		return
	var capacidade_abelhas: int = _obter_capacidade_nivel(nivel_colmeia)
	var capacidade_mel: int = _obter_capacidade_estoque_mel(nivel_estoque_mel)
	var bonus_percentual: int = int(round((_obter_multiplicador_raridade() - 1.0) * 100.0))
	var tipo_mel: String = _obter_nome_mel_por_raridade()
	var texto_status := "Raridade: %s (+%d%% mel)  |  Tipo: %s  |  Nivel da colmeia: %d  |  Moedas: %d" % [
		raridade_colmeia.capitalize(), bonus_percentual, tipo_mel, nivel_colmeia, GerenciadorMundo.moedas
	]
	_ui_status.text = texto_status
	if _ui_barra_mel != null:
		_ui_barra_mel.min_value = 0.0
		_ui_barra_mel.max_value = float(maxi(capacidade_mel, 1))
		_ui_barra_mel.value = float(mel_armazenado)
	if _ui_barra_abelhas != null:
		_ui_barra_abelhas.min_value = 0.0
		_ui_barra_abelhas.max_value = float(maxi(capacidade_abelhas, 1))
		_ui_barra_abelhas.value = float(abelhas_ativas)
	if _ui_valor_mel != null:
		_ui_valor_mel.text = "Nivel %d | %d/%d" % [nivel_estoque_mel, mel_armazenado, capacidade_mel]
	if _ui_valor_abelhas != null:
		_ui_valor_abelhas.text = "%d/%d" % [abelhas_ativas, capacidade_abelhas]

	if _cooldown_upgrade_restante > 0.0:
		_ui_cooldown.text = "Upgrade em andamento para nivel %d. Tempo restante: %s" % [
			_nivel_pendente_upgrade, _formatar_tempo(_cooldown_upgrade_restante)
		]
	else:
		var incremento_real: float = _obter_incremento_por_abelha() * _obter_multiplicador_raridade()
		var fator_upgrade: float = _obter_multiplicador_tempo_upgrade_raridade()
		_ui_cooldown.text = "Producao ativa: +%.2f por ciclo/abelha | Tempo de upgrade x%.2f" % [incremento_real, fator_upgrade]

	var custo_abelha: int = _obter_custo_compra_abelha()
	_btn_comprar_abelha.text = "Comprar abelhas\n%d moedas" % custo_abelha
	_btn_comprar_abelha.disabled = abelhas_ativas >= capacidade_abelhas
	_btn_coletar_mel.disabled = mel_armazenado <= 0

	if nivel_colmeia >= 5:
		_btn_upgrade.text = "Atualizar colmeia\nNivel maximo"
		_btn_upgrade.disabled = true
	else:
		var custo: int = _obter_custo_upgrade(nivel_colmeia)
		_btn_upgrade.text = "Atualizar colmeia (Nv %d)\n%d moedas" % [nivel_colmeia + 1, custo]
		_btn_upgrade.disabled = _cooldown_upgrade_restante > 0.0

	if nivel_estoque_mel >= 5:
		_btn_upgrade_estoque_mel.text = "Aumentar estoque\nNivel maximo"
		_btn_upgrade_estoque_mel.disabled = true
	else:
		var custo_estoque: int = _obter_custo_upgrade_estoque_mel(nivel_estoque_mel)
		_btn_upgrade_estoque_mel.text = "Aumentar estoque (Nv %d)\n%d moedas" % [nivel_estoque_mel + 1, custo_estoque]
		_btn_upgrade_estoque_mel.disabled = false


## Cria o estilo do painel principal da interface de gestão da colmeia.
func _criar_stylebox_painel_ui_colmeia() -> StyleBoxFlat:
	var estilo := StyleBoxFlat.new()
	estilo.bg_color = Color(0.95, 0.92, 0.85, 0.97)
	estilo.border_color = Color(0.52, 0.46, 0.38)
	estilo.border_width_top = 3
	estilo.border_width_right = 3
	estilo.border_width_bottom = 8
	estilo.border_width_left = 3
	estilo.corner_radius_top_left = 16
	estilo.corner_radius_top_right = 16
	estilo.corner_radius_bottom_right = 16
	estilo.corner_radius_bottom_left = 16
	estilo.content_margin_top = 22
	estilo.content_margin_bottom = 22
	estilo.content_margin_left = 24
	estilo.content_margin_right = 24
	return estilo


## Aplica estilo visual de botão para os cards de ação da gestão da colmeia.
func _aplicar_estilo_botao_ui_colmeia(botao: Button, tipo: String) -> void:
	var normal := StyleBoxFlat.new()
	var hover := StyleBoxFlat.new()
	var pressed := StyleBoxFlat.new()

	match tipo:
		"natureza":
			normal.bg_color = Color(0.62, 0.81, 0.42)
			normal.border_color = Color(0.24, 0.42, 0.12)
			hover.bg_color = Color(0.68, 0.86, 0.48)
			hover.border_color = Color(0.24, 0.42, 0.12)
			pressed.bg_color = Color(0.54, 0.72, 0.36)
			pressed.border_color = Color(0.18, 0.33, 0.09)
			botao.add_theme_color_override("font_color", Color(0.14, 0.24, 0.08))
			botao.add_theme_color_override("font_hover_color", Color(0.14, 0.24, 0.08))
			botao.add_theme_color_override("font_pressed_color", Color(0.10, 0.19, 0.06))
		"secundario":
			normal.bg_color = Color(0.96, 0.93, 0.87)
			normal.border_color = Color(0.52, 0.46, 0.38)
			hover.bg_color = Color(0.99, 0.96, 0.90)
			hover.border_color = Color(0.52, 0.46, 0.38)
			pressed.bg_color = Color(0.90, 0.87, 0.81)
			pressed.border_color = Color(0.40, 0.36, 0.29)
			botao.add_theme_color_override("font_color", Color(0.40, 0.28, 0.0))
			botao.add_theme_color_override("font_hover_color", Color(0.40, 0.28, 0.0))
			botao.add_theme_color_override("font_pressed_color", Color(0.33, 0.22, 0.0))
		_:
			normal.bg_color = Color(0.99, 0.72, 0.12)
			normal.border_color = Color(0.50, 0.34, 0.0)
			hover.bg_color = Color(1.0, 0.79, 0.21)
			hover.border_color = Color(0.50, 0.34, 0.0)
			pressed.bg_color = Color(0.93, 0.64, 0.08)
			pressed.border_color = Color(0.40, 0.28, 0.0)
			botao.add_theme_color_override("font_color", Color(0.33, 0.22, 0.0))
			botao.add_theme_color_override("font_hover_color", Color(0.33, 0.22, 0.0))
			botao.add_theme_color_override("font_pressed_color", Color(0.27, 0.18, 0.0))

	for estilo in [normal, hover, pressed]:
		estilo.border_width_top = 2
		estilo.border_width_right = 2
		estilo.border_width_bottom = 6
		estilo.border_width_left = 2
		estilo.corner_radius_top_left = 12
		estilo.corner_radius_top_right = 12
		estilo.corner_radius_bottom_right = 12
		estilo.corner_radius_bottom_left = 12
		estilo.content_margin_top = 12
		estilo.content_margin_bottom = 12
		estilo.content_margin_left = 12
		estilo.content_margin_right = 12

	botao.add_theme_stylebox_override("normal", normal)
	botao.add_theme_stylebox_override("hover", hover)
	botao.add_theme_stylebox_override("pressed", pressed)
	botao.add_theme_font_size_override("font_size", 19)
	botao.add_theme_color_override("font_disabled_color", Color(0.33, 0.22, 0.0))
	botao.alignment = HORIZONTAL_ALIGNMENT_CENTER
	botao.clip_text = false


## Cria o stylebox de fundo da barra de progresso no visual de canal de madeira.
func _criar_stylebox_barra_fundo_ui_colmeia() -> StyleBoxFlat:
	var estilo := StyleBoxFlat.new()
	estilo.bg_color = Color(0.76, 0.68, 0.53)
	estilo.border_color = Color(0.43, 0.36, 0.25)
	estilo.border_width_top = 2
	estilo.border_width_right = 2
	estilo.border_width_bottom = 2
	estilo.border_width_left = 2
	estilo.corner_radius_top_left = 8
	estilo.corner_radius_top_right = 8
	estilo.corner_radius_bottom_right = 8
	estilo.corner_radius_bottom_left = 8
	return estilo


## Cria o stylebox de preenchimento da barra de progresso com a cor solicitada.
func _criar_stylebox_barra_fill_ui_colmeia(cor: Color) -> StyleBoxFlat:
	var estilo := StyleBoxFlat.new()
	estilo.bg_color = cor
	estilo.corner_radius_top_left = 6
	estilo.corner_radius_top_right = 6
	estilo.corner_radius_bottom_right = 6
	estilo.corner_radius_bottom_left = 6
	return estilo


## Retorna uma string MM:SS para o tempo restante.
func _formatar_tempo(segundos: float) -> String:
	var total: int = int(ceil(segundos))
	@warning_ignore("integer_division")
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
	_hint_label.visible = mel_pronto and _jogador_proximo
	_atualizar_visual_completo()

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
	_cooldown_upgrade_restante = _obter_tempo_cooldown_upgrade() * _obter_multiplicador_tempo_upgrade_raridade()
	_acumulador_salvamento_cooldown = 0.0
	_upgrade_aguardando_recolhimento = true
	set_process(true)
	_solicitar_recolhimento_abelhas()
	_ui_feedback.text = "Upgrade iniciado. Aguardando abelhas entrarem para pausar producao."
	_salvar_estado()

	_atualizar_ui_colmeia()


# --- CONTROLE DE ABELHAS ---

## Retorna a capacidade máxima de abelhas para o nível informado.
func _obter_capacidade_nivel(nivel: int) -> int:
	var indice: int = clampi(nivel, 1, 5) - 1
	var balanceamento: BalanceamentoColmeia = _obter_balanceamento_seguro()
	return _obter_valor_array_int(balanceamento.capacidade_abelhas_por_nivel, indice, 1)


## Retorna o custo do upgrade com base no nível atual.
func _obter_custo_upgrade(nivel_atual: int) -> int:
	var indice: int = clampi(nivel_atual, 1, 4)
	var balanceamento: BalanceamentoColmeia = _obter_balanceamento_seguro()
	return _obter_valor_array_int(balanceamento.custo_upgrade_por_nivel, indice, 0)


## Retorna o custo atual da compra de abelha nesta colmeia.
## A cada abelha comprada, o custo da próxima aumenta.
func _obter_custo_compra_abelha() -> int:
	var balanceamento: BalanceamentoColmeia = _obter_balanceamento_seguro()
	var custo_base: int = maxi(balanceamento.custo_primeira_abelha, 0)
	var incremento: int = maxi(balanceamento.incremento_custo_por_abelha, 0)
	return custo_base + (abelhas_ativas * incremento)


## Retorna a capacidade máxima de estoque de mel para o nível informado.
func _obter_capacidade_estoque_mel(nivel: int) -> int:
	var indice: int = clampi(nivel, 1, 5) - 1
	var balanceamento: BalanceamentoColmeia = _obter_balanceamento_seguro()
	return _obter_valor_array_int(balanceamento.capacidade_estoque_mel_por_nivel, indice, 1)


## Retorna o custo de upgrade do estoque de mel com base no nível atual.
func _obter_custo_upgrade_estoque_mel(nivel_atual: int) -> int:
	var indice: int = clampi(nivel_atual, 1, 4)
	var balanceamento: BalanceamentoColmeia = _obter_balanceamento_seguro()
	return _obter_valor_array_int(balanceamento.custo_upgrade_estoque_mel_por_nivel, indice, 0)


## Retorna o tempo base de cooldown do upgrade da colmeia.
func _obter_tempo_cooldown_upgrade() -> float:
	var balanceamento: BalanceamentoColmeia = _obter_balanceamento_seguro()
	return maxf(balanceamento.tempo_cooldown_upgrade, 0.1)


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


## Ajusta o estado das abelhas conforme período do mundo (dia/noite).
func definir_periodo_dia(eh_dia: bool) -> void:
	if not eh_dia:
		_definir_producao_ativa(false)
		return
	if _upgrade_aguardando_recolhimento:
		_solicitar_recolhimento_abelhas()
		return
	if _cooldown_upgrade_restante > 0.0:
		_definir_producao_ativa(false)
		return
	_definir_producao_ativa(true)


## Normaliza a string de raridade, garantindo fallback seguro para "comum".
func _normalizar_raridade(raridade: String) -> String:
	var chave: String = raridade.strip_edges().to_lower()
	var balanceamento: BalanceamentoColmeia = _obter_balanceamento_seguro()
	if balanceamento.multiplicador_raridade.has(chave):
		return chave
	return "comum"


## Retorna o multiplicador de produção baseado na raridade da colmeia.
func _obter_multiplicador_raridade() -> float:
	var chave: String = _normalizar_raridade(raridade_colmeia)
	var balanceamento: BalanceamentoColmeia = _obter_balanceamento_seguro()
	if balanceamento.multiplicador_raridade.has(chave):
		return float(balanceamento.multiplicador_raridade[chave])
	return 1.0


## Retorna o multiplicador de tempo de upgrade baseado na raridade da colmeia.
func _obter_multiplicador_tempo_upgrade_raridade() -> float:
	var chave: String = _normalizar_raridade(raridade_colmeia)
	var balanceamento: BalanceamentoColmeia = _obter_balanceamento_seguro()
	if balanceamento.multiplicador_tempo_upgrade_raridade.has(chave):
		return float(balanceamento.multiplicador_tempo_upgrade_raridade[chave])
	return 1.0


## Retorna o caminho do recurso de mel produzido por esta raridade.
func _obter_caminho_recurso_mel_raridade() -> String:
	var chave: String = _normalizar_raridade(raridade_colmeia)
	var balanceamento: BalanceamentoColmeia = _obter_balanceamento_seguro()
	if balanceamento.recurso_mel_por_raridade.has(chave):
		return String(balanceamento.recurso_mel_por_raridade[chave])
	return "res://resources/mel.tres"


## Retorna o item de mel produzido por esta colmeia, ou null se o recurso não existir.
func _obter_item_mel_raridade() -> Item:
	var caminho_item: String = _obter_caminho_recurso_mel_raridade()
	if not ResourceLoader.exists(caminho_item):
		return null
	var item_mel: Item = load(caminho_item)
	_aplicar_valor_venda_configurado(item_mel)
	return item_mel


## Aplica o valor de venda configurado no balanceamento ao Item de mel.
func _aplicar_valor_venda_configurado(item_mel: Item) -> void:
	if item_mel == null:
		return
	var balanceamento: BalanceamentoColmeia = _obter_balanceamento_seguro()
	var chave: String = _normalizar_raridade(raridade_colmeia)
	if balanceamento.valor_venda_por_raridade.has(chave):
		var valor_configurado: int = int(balanceamento.valor_venda_por_raridade[chave])
		if valor_configurado > 0:
			item_mel.valor_venda = valor_configurado


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
	_aplicar_balanceamento_abelha(abelha)
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
		@warning_ignore("integer_division")
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
	_cooldown_upgrade_restante = 0.0
	set_process(false)
	_sincronizar_abelhas()
	_definir_producao_ativa(true)
	_ui_feedback.text = "Upgrade concluido. Novo nivel da colmeia: %d." % nivel_colmeia
	_salvar_estado()

	_atualizar_ui_colmeia()


# --- CALLBACKS DA ÁREA ---

## Disparado quando um corpo entra na área; exibe barra e emite sinal para o player.
func _ao_entrar_area(body: Node3D) -> void:
	if not (body is CharacterBody3D):
		return
	_jogador_proximo = true
	if _hint_label != null:
		_hint_label.visible = true
	jogador_entrou_colmeia.emit()


## Disparado quando um corpo sai da área; esconde hint e fecha UI da colmeia.
func _ao_sair_area(body: Node3D) -> void:
	if not (body is CharacterBody3D):
		return
	_jogador_proximo = false
	if _hint_label != null:
		_hint_label.visible = false
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
		_hint_label.visible = _jogador_proximo
		_atualizar_visual_completo()

		_atualizar_ui_colmeia()
		_salvar_estado()
		return

	progresso_mel += _obter_incremento_por_abelha() * _obter_multiplicador_raridade()
	while progresso_mel >= 1.0 and mel_armazenado < capacidade_estoque:
		progresso_mel -= 1.0
		mel_armazenado += 1

	if mel_armazenado >= capacidade_estoque:
		mel_armazenado = capacidade_estoque
		progresso_mel = 0.0

	mel_pronto = mel_armazenado > 0
	_hint_label.visible = mel_pronto and _jogador_proximo
	_atualizar_visual_completo()
	if mel_armazenado >= capacidade_estoque:
		_animar_pulso_pronto()

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
	_hint_label.visible = mel_pronto and _jogador_proximo

	_atualizar_visual_completo()
	_animar_feedback_coleta()
	_atualizar_ui_colmeia()

	mel_coletado.emit(quantidade_coletada)
	_salvar_estado()


# --- VISUAL ---

## Placeholder para atualizações visuais futuras (barra removida).
func _atualizar_visual_completo() -> void:
	pass


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
		# Primeira vez — apenas a colmeia principal começa com 1 abelha
		if id_colmeia == "colmeia_principal":
			abelhas_ativas = 1
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

	_hint_label.visible = mel_pronto and _jogador_proximo



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
