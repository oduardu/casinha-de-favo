extends Control

# HUD com ícones 3D (coin.glb, honey.glb) e texto legível via fonte Fredoka Bold.
# Exibe moedas e mel do jogador no canto superior direito.



## Caminho da fonte customizada para números da HUD
const CAMINHO_FONTE := "res://resources/fonts/Fredoka-Bold.ttf"


# --- CONFIGURAÇÃO ---


## Tamanho da fonte dos números de recursos na HUD
const TAMANHO_FONTE_VALOR := 32


# --- REFERÊNCIAS ---

var _inventario: Node = null

## Painel principal da HUD com resumo de recursos
var _painel_resumo: PanelContainer = null

var _container: VBoxContainer = null

## Label de texto que exibe o valor de moedas
var _label_moedas: Label = null

## Label de texto que exibe o valor de mel total
var _label_mel: Label = null

## Fonte customizada carregada em runtime para melhor legibilidade
var _fonte: Font = null

var _moedas_cache: int = -1
var _mel_cache: int = -1
var _dia_cache: int = -1
var _periodo_cache: bool = true
## Cache do minuto do dia para atualizar horário da HUD só quando necessário
var _minuto_dia_cache: int = -1

## Label textual com dia atual, período (dia/noite) e horário do ciclo
var _label_dia_periodo: Label = null

## Painel lateral com a lista dos tipos de mel em posse do jogador
var _painel_tipos_mel: PanelContainer = null

## Lista vertical dinâmica com as linhas de cada tipo de mel
var _lista_tipos_mel: VBoxContainer = null

## Cache do tamanho da tela para reposicionar a HUD apenas quando necessário
var _tamanho_tela_cache: Vector2 = Vector2.ZERO


# --- CICLO DE VIDA ---

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_inventario = get_tree().get_first_node_in_group("inventario")
	_carregar_fonte()
	_criar_ui()
	_conectar_sinais()
	_atualizar_tudo()
	set_process(true)


## Timer interno para atualizar informações periódicas (dia/noite) sem polling todo frame
var _timer_atualizacao: float = 0.0

## Intervalo em segundos entre atualizações periódicas da HUD (moedas, dia/noite)
const INTERVALO_ATUALIZACAO: float = 0.5


func _process(delta: float) -> void:
	var tamanho_tela_atual: Vector2 = get_viewport().get_visible_rect().size
	if tamanho_tela_atual != _tamanho_tela_cache:
		_tamanho_tela_cache = tamanho_tela_atual
		_reposicionar_hud()

	_timer_atualizacao += delta
	if _timer_atualizacao < INTERVALO_ATUALIZACAO:
		return
	_timer_atualizacao = 0.0

	var moedas_atual := GerenciadorMundo.moedas
	if moedas_atual != _moedas_cache:
		_moedas_cache = moedas_atual
		_atualizar_label_valor(_label_moedas, moedas_atual)

	var dia_atual := GerenciadorMundo.dia_atual
	var periodo_atual := GerenciadorMundo.periodo_eh_dia
	var minuto_atual: int = _obter_minuto_do_dia_atual()
	if dia_atual != _dia_cache or periodo_atual != _periodo_cache or minuto_atual != _minuto_dia_cache:
		_dia_cache = dia_atual
		_periodo_cache = periodo_atual
		_minuto_dia_cache = minuto_atual
		_atualizar_label_dia_periodo()


# --- PRÉ-CARREGAMENTO ---

## Carrega a fonte customizada Fredoka Bold para uso na HUD.
func _carregar_fonte() -> void:
	if ResourceLoader.exists(CAMINHO_FONTE):
		_fonte = load(CAMINHO_FONTE) as Font


# --- CRIAÇÃO VISUAL ---

func _criar_ui() -> void:
	_painel_resumo = PanelContainer.new()
	_painel_resumo.name = "PainelResumoHUD"
	_painel_resumo.custom_minimum_size = Vector2(300.0, 0.0)
	_painel_resumo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_painel_resumo.add_theme_stylebox_override("panel", _criar_stylebox_painel_resumo())
	add_child(_painel_resumo)

	_container = VBoxContainer.new()
	_container.name = "ContainerHUD"
	_container.add_theme_constant_override("separation", 10)
	_painel_resumo.add_child(_container)

	var titulo := Label.new()
	titulo.text = "RECURSOS"
	titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	titulo.add_theme_font_size_override("font_size", 22)
	titulo.add_theme_color_override("font_color", Color(0.47, 0.33, 0.05))

	_container.add_child(titulo)

	# Linha de moedas
	var card_moedas := PanelContainer.new()
	card_moedas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_moedas.add_theme_stylebox_override("panel", _criar_stylebox_card_recurso())
	_container.add_child(card_moedas)

	var linha_moedas := HBoxContainer.new()
	linha_moedas.name = "LinhaCoins"
	linha_moedas.add_theme_constant_override("separation", 10)
	linha_moedas.alignment = BoxContainer.ALIGNMENT_CENTER
	linha_moedas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_moedas.add_child(linha_moedas)

	linha_moedas.add_child(_criar_icone_label("💰", 40))

	var placa_moedas: PanelContainer
	placa_moedas = _criar_placa_valor()
	_label_moedas = placa_moedas.get_child(0) as Label
	linha_moedas.add_child(placa_moedas)

	# Linha de mel
	var card_mel := PanelContainer.new()
	card_mel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_mel.add_theme_stylebox_override("panel", _criar_stylebox_card_recurso())
	_container.add_child(card_mel)

	var linha_mel := HBoxContainer.new()
	linha_mel.name = "LinhaHoney"
	linha_mel.add_theme_constant_override("separation", 10)
	linha_mel.alignment = BoxContainer.ALIGNMENT_CENTER
	linha_mel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_mel.add_child(linha_mel)

	linha_mel.add_child(_criar_icone_label("🍯", 40))

	var placa_mel: PanelContainer
	placa_mel = _criar_placa_valor()
	_label_mel = placa_mel.get_child(0) as Label
	linha_mel.add_child(placa_mel)

	# Linha de dia/noite
	var card_dia := PanelContainer.new()
	card_dia.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_dia.add_theme_stylebox_override("panel", _criar_stylebox_card_recurso())
	_container.add_child(card_dia)

	_label_dia_periodo = Label.new()
	_label_dia_periodo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label_dia_periodo.add_theme_font_size_override("font_size", 16)
	_label_dia_periodo.add_theme_color_override("font_color", Color(0.40, 0.28, 0.0))

	card_dia.add_child(_label_dia_periodo)
	_atualizar_label_dia_periodo()

	_criar_painel_tipos_mel()
	_tamanho_tela_cache = get_viewport().get_visible_rect().size
	_reposicionar_hud()


## Cria um label emoji como ícone de recurso na HUD.
func _criar_icone_label(emoji: String, tamanho: int) -> Label:
	var lbl := Label.new()
	lbl.text = emoji
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.custom_minimum_size = Vector2(tamanho, tamanho)
	lbl.add_theme_font_size_override("font_size", tamanho - 8)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lbl


## Cria uma placa (PanelContainer) com Label interno para exibir valores numéricos na HUD.
## O Label é o primeiro filho do PanelContainer retornado.
func _criar_placa_valor() -> PanelContainer:
	var placa_valor := PanelContainer.new()
	placa_valor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	placa_valor.custom_minimum_size = Vector2(120.0, 50.0)
	placa_valor.add_theme_stylebox_override("panel", _criar_stylebox_placa_valor())

	var lbl := Label.new()
	lbl.text = "0"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lbl.add_theme_font_size_override("font_size", TAMANHO_FONTE_VALOR)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.95, 0.7))
	placa_valor.add_child(lbl)

	return placa_valor


## Atualiza o texto numérico de um label de valor da HUD.
func _atualizar_label_valor(lbl: Label, valor: int) -> void:
	if lbl == null:
		return
	lbl.text = str(maxi(valor, 0))


# --- SINAIS ---

func _conectar_sinais() -> void:
	if _inventario != null:
		_inventario.inventario_mudou.connect(_atualizar_tudo)
	for colmeia in get_tree().get_nodes_in_group("colmeia"):
		if colmeia.has_signal("mel_coletado"):
			colmeia.mel_coletado.connect(func(_q: int) -> void: _atualizar_tudo())
	for npc in get_tree().get_nodes_in_group("npc"):
		if npc.has_signal("venda_realizada"):
			npc.venda_realizada.connect(_atualizar_tudo)


func _atualizar_tudo() -> void:
	_moedas_cache = GerenciadorMundo.moedas
	_atualizar_label_valor(_label_moedas, _moedas_cache)
	_mel_cache = _contar_mel_inventario()
	_atualizar_label_valor(_label_mel, _mel_cache)
	_dia_cache = GerenciadorMundo.dia_atual
	_periodo_cache = GerenciadorMundo.periodo_eh_dia
	_minuto_dia_cache = _obter_minuto_do_dia_atual()
	_atualizar_label_dia_periodo()
	_atualizar_lista_tipos_mel()
	_reposicionar_hud()


func _contar_mel_inventario() -> int:
	if _inventario == null:
		return 0
	return _inventario.contar_total_mel()


## Atualiza o texto do contador de dia e período atual (dia/noite).
func _atualizar_label_dia_periodo() -> void:
	if _label_dia_periodo == null:
		return
	var periodo: String = "DIA" if GerenciadorMundo.periodo_eh_dia else "NOITE"
	var horario: String = _obter_horario_do_mundo_formatado()
	_label_dia_periodo.text = "DIA %d  |  %s  |  %s" % [maxi(GerenciadorMundo.dia_atual, 1), periodo, horario]


## Retorna o nó do mundo atual para consultar horário e duração de ciclo.
func _obter_mundo_atual() -> Node:
	var cena_atual: Node = get_tree().current_scene
	if cena_atual != null and cena_atual.has_method("obter_horario_formatado"):
		return cena_atual
	return null


## Retorna o minuto atual do dia (0..1439) para controle de atualização da HUD.
func _obter_minuto_do_dia_atual() -> int:
	var mundo: Node = _obter_mundo_atual()
	if mundo != null and mundo.has_method("obter_minuto_do_dia"):
		return int(mundo.obter_minuto_do_dia())

	var duracao_ciclo_padrao: float = 900.0
	var fracao_ciclo: float = 0.0
	if duracao_ciclo_padrao > 0.1:
		fracao_ciclo = fposmod(GerenciadorMundo.tempo_ciclo_dia_noite, duracao_ciclo_padrao) / duracao_ciclo_padrao
	var hora_decimal: float = fposmod(fracao_ciclo * 24.0 + 5.0, 24.0)
	return int(floor(hora_decimal * 60.0))


## Retorna o horário formatado em HH:MM para exibição no card de dia/noite.
func _obter_horario_do_mundo_formatado() -> String:
	var mundo: Node = _obter_mundo_atual()
	if mundo != null and mundo.has_method("obter_horario_formatado"):
		return String(mundo.obter_horario_formatado())

	var minuto_total: int = clampi(_obter_minuto_do_dia_atual(), 0, 1439)
	@warning_ignore("integer_division")
	var horas: int = minuto_total / 60
	var minutos: int = minuto_total % 60
	return "%02d:%02d" % [horas, minutos]


# --- LISTA LATERAL DE MELS ---

## Cria o painel lateral de tipos de mel no canto direito da tela.
func _criar_painel_tipos_mel() -> void:
	_painel_tipos_mel = PanelContainer.new()
	_painel_tipos_mel.name = "PainelTiposMel"
	_painel_tipos_mel.visible = false
	_painel_tipos_mel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_painel_tipos_mel.custom_minimum_size = Vector2(260.0, 0.0)
	_painel_tipos_mel.add_theme_stylebox_override("panel", _criar_stylebox_painel_tipos_mel())
	add_child(_painel_tipos_mel)

	var coluna := VBoxContainer.new()
	coluna.add_theme_constant_override("separation", 8)
	_painel_tipos_mel.add_child(coluna)

	var titulo := Label.new()
	titulo.text = "TIPOS DE MEL"
	titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	titulo.add_theme_font_size_override("font_size", 20)
	titulo.add_theme_color_override("font_color", Color(0.47, 0.33, 0.05))

	coluna.add_child(titulo)

	_lista_tipos_mel = VBoxContainer.new()
	_lista_tipos_mel.add_theme_constant_override("separation", 6)
	coluna.add_child(_lista_tipos_mel)


## Cria o stylebox do painel de tipos de mel no padrão visual do jogo.
func _criar_stylebox_painel_tipos_mel() -> StyleBoxFlat:
	var estilo := StyleBoxFlat.new()
	estilo.bg_color = Color(0.95, 0.92, 0.85, 0.94)
	estilo.border_color = Color(0.52, 0.46, 0.38)
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
	return estilo


## Cria o stylebox do painel de resumo de recursos da HUD.
func _criar_stylebox_painel_resumo() -> StyleBoxFlat:
	var estilo := StyleBoxFlat.new()
	estilo.bg_color = Color(0.95, 0.92, 0.85, 0.95)
	estilo.border_color = Color(0.52, 0.46, 0.38)
	estilo.border_width_top = 3
	estilo.border_width_right = 3
	estilo.border_width_bottom = 8
	estilo.border_width_left = 3
	estilo.corner_radius_top_left = 14
	estilo.corner_radius_top_right = 14
	estilo.corner_radius_bottom_right = 14
	estilo.corner_radius_bottom_left = 14
	estilo.content_margin_top = 12
	estilo.content_margin_bottom = 12
	estilo.content_margin_left = 12
	estilo.content_margin_right = 12
	return estilo


## Cria o stylebox dos cards individuais de recursos (moedas e mel total).
func _criar_stylebox_card_recurso() -> StyleBoxFlat:
	var estilo := StyleBoxFlat.new()
	estilo.bg_color = Color(0.99, 0.96, 0.89, 0.95)
	estilo.border_color = Color(0.62, 0.54, 0.40)
	estilo.border_width_top = 1
	estilo.border_width_right = 1
	estilo.border_width_bottom = 4
	estilo.border_width_left = 1
	estilo.corner_radius_top_left = 10
	estilo.corner_radius_top_right = 10
	estilo.corner_radius_bottom_right = 10
	estilo.corner_radius_bottom_left = 10
	estilo.content_margin_top = 6
	estilo.content_margin_bottom = 6
	estilo.content_margin_left = 10
	estilo.content_margin_right = 10
	return estilo


## Cria o fundo do valor numérico para aumentar o contraste e sensação de profundidade.
func _criar_stylebox_placa_valor() -> StyleBoxFlat:
	var estilo := StyleBoxFlat.new()
	estilo.bg_color = Color(0.36, 0.27, 0.16, 0.95)
	estilo.border_color = Color(0.75, 0.63, 0.44, 0.9)
	estilo.border_width_top = 1
	estilo.border_width_right = 1
	estilo.border_width_bottom = 4
	estilo.border_width_left = 1
	estilo.corner_radius_top_left = 8
	estilo.corner_radius_top_right = 8
	estilo.corner_radius_bottom_right = 8
	estilo.corner_radius_bottom_left = 8
	estilo.content_margin_top = 4
	estilo.content_margin_bottom = 4
	estilo.content_margin_left = 8
	estilo.content_margin_right = 8
	return estilo


## Reposiciona os painéis da HUD no canto direito respeitando o tamanho atual da tela.
func _reposicionar_hud() -> void:
	var tela: Vector2 = get_viewport().get_visible_rect().size
	if _painel_resumo != null:
		_painel_resumo.position = Vector2(tela.x - 324.0, 14.0)
	if _painel_tipos_mel != null and _painel_resumo != null:
		var y_tipos: float = _painel_resumo.position.y + _painel_resumo.size.y + 10.0
		_painel_tipos_mel.position = Vector2(tela.x - 286.0, y_tipos)


## Atualiza a lista de tipos de mel exibindo apenas os tipos com quantidade maior que zero.
func _atualizar_lista_tipos_mel() -> void:
	if _painel_tipos_mel == null or _lista_tipos_mel == null:
		return

	for filho in _lista_tipos_mel.get_children():
		filho.queue_free()

	if _inventario == null:
		_painel_tipos_mel.visible = false
		return

	var possui_algum_mel: bool = false
	for id_item in _inventario.listar_ids_itens():
		var id_texto: String = String(id_item)
		if not id_texto.begins_with("mel"):
			continue
		var quantidade: int = _inventario.contar_item_por_id(id_texto)
		if quantidade <= 0:
			continue
		var item: Item = _inventario.obter_item_por_id(id_texto)
		var nome_exibicao: String = id_texto
		if item != null and not item.nome_exibicao.is_empty():
			nome_exibicao = item.nome_exibicao

		var capacidade_tipo: int = 0
		if _inventario.has_method("obter_capacidade_por_id"):
			capacidade_tipo = int(_inventario.call("obter_capacidade_por_id", id_texto))

		var card := PanelContainer.new()
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_theme_stylebox_override("panel", _criar_stylebox_card_recurso())
		_lista_tipos_mel.add_child(card)

		var linha := HBoxContainer.new()
		linha.add_theme_constant_override("separation", 8)
		card.add_child(linha)

		var lbl_nome := Label.new()
		lbl_nome.text = nome_exibicao
		lbl_nome.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl_nome.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		lbl_nome.add_theme_font_size_override("font_size", 15)
		lbl_nome.add_theme_color_override("font_color", Color(0.33, 0.22, 0.0))

		linha.add_child(lbl_nome)

		var lbl_qtd := Label.new()
		if capacidade_tipo > 0:
			lbl_qtd.text = "%d/%d" % [quantidade, capacidade_tipo]
		else:
			lbl_qtd.text = str(quantidade)
		lbl_qtd.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		lbl_qtd.add_theme_font_size_override("font_size", 15)
		lbl_qtd.add_theme_color_override("font_color", Color(0.50, 0.34, 0.0))

		linha.add_child(lbl_qtd)
		possui_algum_mel = true

	_painel_tipos_mel.visible = possui_algum_mel
