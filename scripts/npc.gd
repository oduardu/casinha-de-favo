class_name NPC
extends Node3D

# NPC comerciante: o jogador pode vender itens em troca de moedas.
# O valor da venda depende do valor_venda de cada Item.
# Detecta a proximidade do jogador via Area3D e exibe dicas contextuais.


# --- SINAIS ---

## Emitido quando um CharacterBody3D entra na área de detecção do NPC
signal jogador_entrou_npc

## Emitido quando um CharacterBody3D sai da área de detecção do NPC
signal jogador_saiu_npc

## Emitido quando uma venda é concluída com sucesso
signal venda_realizada


# --- REFERÊNCIAS INTERNAS ---

## Caminho da fonte customizada para a interface do mercado
const CAMINHO_FONTE: String = "res://resources/fonts/Fredoka-Bold.ttf"

## Caminho do modelo GLB da compradora de mel.
const CAMINHO_MODELO_COMPRADORA: String = "res://obj/comprador_de_mel/compradora_de_mel.glb"

## Escala base aplicada ao modelo 3D da compradora de mel.
const ESCALA_MODELO_COMPRADORA: Vector3 = Vector3(2.5, 2.5, 2.5)

## Offset vertical aplicado ao modelo para alinhar com o chão dos hex tiles.
const OFFSET_Y_MODELO_COMPRADORA: float = 0.35

## Nó visual principal do corpo do NPC (modelo 3D ou fallback).
var _corpo: Node3D = null

## Area3D que detecta a proximidade do jogador
var _area_deteccao: Area3D = null

## Label3D que mostra a dica contextual ao jogador ("Vender Mel" / "Sem mel")
var _hint_label: Label3D = null

## True enquanto o jogador está dentro da área de detecção
var _jogador_proximo: bool = false

## Referência ao jogador dentro da área (para acessar inventário na venda)
var _jogador_ref: Node = null

## True quando o comerciante está disponível (somente de dia)
var _disponivel_no_periodo: bool = true

## CanvasLayer da interface de venda de mel
var _ui_layer: CanvasLayer = null

## Label principal com resumo de venda
var _ui_status: Label = null

## Container com botões dinâmicos por tipo de mel
var _ui_lista_tipos: VBoxContainer = null

## Label de feedback das ações de venda
var _ui_feedback: Label = null

## Botão para vender todos os tipos de mel de uma vez
var _btn_vender_todos: Button = null

## Fonte customizada para a interface de venda (Fredoka Bold)
var _fonte: Font = null


# --- CICLO DE VIDA ---

func _ready() -> void:
	add_to_group("npc")
	if ResourceLoader.exists(CAMINHO_FONTE):
		_fonte = load(CAMINHO_FONTE) as Font
	_criar_corpo()
	_iniciar_animacao_respiracao()
	_criar_area_deteccao()
	_criar_hint_label()
	_criar_ui_venda()


# --- CRIAÇÃO DOS ELEMENTOS ---

## Cria o corpo do NPC com o modelo GLB da compradora de mel.
## Em caso de falha no carregamento do modelo, cria um placeholder simples.
func _criar_corpo() -> void:
	if ResourceLoader.exists(CAMINHO_MODELO_COMPRADORA):
		var cena_modelo: PackedScene = load(CAMINHO_MODELO_COMPRADORA) as PackedScene
		if cena_modelo != null:
			_corpo = cena_modelo.instantiate() as Node3D
	if _corpo == null:
		var placeholder := CSGBox3D.new()
		placeholder.size = Vector3(0.5, 1.0, 0.5)
		placeholder.position.y = 0.5  # A base do personagem toca y=0
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.545, 0.353, 0.62)  # #8B5A9E — roxo
		placeholder.material_override = mat
		_corpo = placeholder
	_corpo.name = "CorpoNPC"
	_corpo.scale = ESCALA_MODELO_COMPRADORA
	_corpo.position.y += OFFSET_Y_MODELO_COMPRADORA
	add_child(_corpo)


## Cria a Area3D cilíndrica que detecta o jogador ao se aproximar do NPC
func _criar_area_deteccao() -> void:
	_area_deteccao = Area3D.new()
	_area_deteccao.name = "AreaNPC"

	var col := CollisionShape3D.new()
	var forma := CylinderShape3D.new()
	forma.radius = 2.0   # Raio de detecção ao redor do NPC
	forma.height = 3.0
	col.shape = forma
	col.position.y = 1.0

	_area_deteccao.add_child(col)
	_area_deteccao.body_entered.connect(_ao_entrar_area)
	_area_deteccao.body_exited.connect(_ao_sair_area)
	add_child(_area_deteccao)


## Cria o Label3D de instrução visível quando o jogador está próximo
func _criar_hint_label() -> void:
	_hint_label = Label3D.new()
	_hint_label.name = "HintNPC"
	_hint_label.font_size = 42
	_hint_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_hint_label.position.y = 2.8
	_hint_label.visible = false
	add_child(_hint_label)


# --- CALLBACKS DA ÁREA ---

## Disparado quando um corpo entra na área; exibe hint contextual e emite sinal
func _ao_entrar_area(body: Node3D) -> void:
	if not (body is CharacterBody3D):
		return
	_jogador_proximo = true
	_jogador_ref = body
	_atualizar_hint()
	_hint_label.visible = true
	jogador_entrou_npc.emit()


## Disparado quando um corpo sai da área; esconde hint e emite sinal
func _ao_sair_area(body: Node3D) -> void:
	if not (body is CharacterBody3D):
		return
	_jogador_proximo = false
	_fechar_interface_venda()
	_jogador_ref = null
	_hint_label.visible = false
	jogador_saiu_npc.emit()


# --- VENDA ---

## Chamada pelo Player ao pressionar E próximo ao NPC.
## Vende todo o mel do inventário de uma vez.
## Retorna true se a venda foi realizada com sucesso.
func tentar_vender(jogador: Node) -> bool:
	var inv: Node = jogador.get_node_or_null("Inventario")
	if inv == null:
		return false

	var valor_total: int = _calcular_valor_total_mel(inv)
	if valor_total <= 0:
		_animar_recusa()
		return false

	_remover_todos_os_mels(inv)
	GerenciadorMundo.adicionar_moedas(valor_total)
	venda_realizada.emit()
	_animar_venda()
	_atualizar_hint()
	return true


## Tenta abrir a interface de venda quando o jogador interage com o NPC.
func tentar_abrir_interface_venda(jogador: Node) -> bool:
	if not _disponivel_no_periodo:
		return false
	if not _jogador_proximo:
		return false
	_jogador_ref = jogador
	_abrir_interface_venda()
	return true


## Define se o comerciante está disponível no período atual (dia/noite).
func definir_disponibilidade_no_periodo(disponivel: bool) -> void:
	_disponivel_no_periodo = disponivel
	visible = disponivel
	if _area_deteccao != null:
		_area_deteccao.monitoring = disponivel
		_area_deteccao.monitorable = disponivel
	if not disponivel:
		_jogador_proximo = false
		_jogador_ref = null
		_hint_label.visible = false
		_fechar_interface_venda()
		jogador_saiu_npc.emit()


## Fecha a interface de venda por atalho (ESC) e retorna true se estava aberta.
func fechar_interface_venda_por_atalho() -> bool:
	if not interface_esta_aberta():
		return false
	_fechar_interface_venda()
	return true


## Retorna true quando a interface de venda está visível.
func interface_esta_aberta() -> bool:
	return _ui_layer != null and _ui_layer.visible


## Abre a interface de venda de mel.
func _abrir_interface_venda() -> void:
	if _ui_layer == null:
		return
	_ui_feedback.text = ""
	_ui_layer.visible = true
	_atualizar_ui_venda()


## Fecha a interface de venda de mel.
func _fechar_interface_venda() -> void:
	if _ui_layer != null:
		_ui_layer.visible = false


# --- VISUAL ---

## Atualiza o texto do hint conforme o item na mão do jogador
func _atualizar_hint() -> void:
	if _hint_label == null or _jogador_ref == null:
		return

	var inv: Node = _jogador_ref.get_node_or_null("Inventario")
	if inv == null:
		_hint_label.text = "..."
		return

	var valor_total: int = _calcular_valor_total_mel(inv)
	if valor_total > 0:
		_hint_label.text = "(E) Abrir mercado de mel (%d moeda)" % valor_total
		_hint_label.modulate = Color(1.0, 0.88, 0.15)  # Amarelo dourado
	else:
		_hint_label.text = "(E) Abrir mercado de mel"
		_hint_label.modulate = Color(0.75, 0.65, 0.85)  # Lilás suave


## Atualiza a UI de venda com botões por tipo de mel e valor total.
func _atualizar_ui_venda() -> void:
	if _ui_status == null or _ui_lista_tipos == null:
		return
	if _jogador_ref == null:
		_ui_status.text = "Jogador nao encontrado."
		_limpar_lista_tipos_ui()
		if _btn_vender_todos != null:
			_btn_vender_todos.disabled = true
		return

	var inv: Node = _jogador_ref.get_node_or_null("Inventario")
	if inv == null:
		_ui_status.text = "Inventario indisponivel."
		_limpar_lista_tipos_ui()
		if _btn_vender_todos != null:
			_btn_vender_todos.disabled = true
		return

	var total_moedas: int = _calcular_valor_total_mel(inv)
	var tipos: Array[Dictionary] = _listar_tipos_mel_no_inventario(inv)
	_ui_status.text = "Mercado de Mel  |  Total de venda: %d moedas" % total_moedas
	_limpar_lista_tipos_ui()

	if tipos.is_empty():
		var vazio := Label.new()
		vazio.text = "Sem mel para vender."
		vazio.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vazio.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		vazio.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vazio.size_flags_vertical = Control.SIZE_EXPAND_FILL
		vazio.add_theme_font_size_override("font_size", 20)
		vazio.add_theme_color_override("font_color", Color(0.50, 0.40, 0.25))

		_ui_lista_tipos.add_child(vazio)
		if _btn_vender_todos != null:
			_btn_vender_todos.text = "Vender todos os tipos"
			_btn_vender_todos.disabled = true
		return

	for dado in tipos:
		var id_item: String = String(dado.get("id", ""))
		var nome: String = String(dado.get("nome", "Mel"))
		var quantidade: int = int(dado.get("quantidade", 0))
		var valor_total_tipo: int = int(dado.get("valor_total", 0))
		var botao := Button.new()
		botao.text = "%s x%d\nVender por %d moedas" % [nome, quantidade, valor_total_tipo]
		botao.custom_minimum_size = Vector2(580.0, 58.0)
		botao.alignment = HORIZONTAL_ALIGNMENT_LEFT
		_aplicar_estilo_botao_ui_mercado(botao, "item")
		botao.pressed.connect(_ao_btn_vender_tipo.bind(id_item))
		_ui_lista_tipos.add_child(botao)

	if _btn_vender_todos != null:
		_btn_vender_todos.text = "Vender todos os tipos — %d moedas" % total_moedas
		_btn_vender_todos.disabled = total_moedas <= 0


## Retorna uma lista com dados de cada tipo de mel presente no inventário.
func _listar_tipos_mel_no_inventario(inv: Node) -> Array[Dictionary]:
	var lista: Array[Dictionary] = []
	for id_item in inv.listar_ids_itens():
		if not String(id_item).begins_with("mel"):
			continue
		var quantidade: int = inv.contar_item_por_id(id_item)
		if quantidade <= 0:
			continue
		var item: Item = inv.obter_item_por_id(id_item)
		if item == null:
			continue
		var valor_unitario: int = maxi(item.valor_venda, 1)
		lista.append({
			"id": String(id_item),
			"nome": item.nome_exibicao if not item.nome_exibicao.is_empty() else String(id_item),
			"quantidade": quantidade,
			"valor_unitario": valor_unitario,
			"valor_total": quantidade * valor_unitario,
		})
	return lista


## Remove todos os botões/labels da lista dinâmica de tipos de mel.
func _limpar_lista_tipos_ui() -> void:
	if _ui_lista_tipos == null:
		return
	for filho in _ui_lista_tipos.get_children():
		filho.queue_free()


## Callback do botão de venda de um tipo específico de mel.
func _ao_btn_vender_tipo(id_item: String) -> void:
	if _jogador_ref == null:
		return
	var inv: Node = _jogador_ref.get_node_or_null("Inventario")
	if inv == null:
		return
	var quantidade: int = inv.contar_item_por_id(id_item)
	if quantidade <= 0:
		_ui_feedback.text = "Esse tipo de mel acabou."
		_atualizar_ui_venda()
		return
	var item: Item = inv.obter_item_por_id(id_item)
	if item == null:
		return
	var valor_unitario: int = maxi(item.valor_venda, 1)
	var removidos: int = inv.remover_todos_por_id(id_item)
	if removidos <= 0:
		return
	var valor_venda: int = removidos * valor_unitario
	GerenciadorMundo.adicionar_moedas(valor_venda)
	venda_realizada.emit()
	_animar_venda()
	_atualizar_hint()
	_ui_feedback.text = "Vendido: %s x%d por %d moedas." % [item.nome_exibicao, removidos, valor_venda]
	_atualizar_ui_venda()


## Callback do botão de venda total (todos os tipos de mel).
func _ao_btn_vender_todos() -> void:
	if _jogador_ref == null:
		return
	var vendeu: bool = tentar_vender(_jogador_ref)
	if vendeu:
		_ui_feedback.text = "Venda total concluida."
	else:
		_ui_feedback.text = "Nao ha mel para vender."
	_atualizar_ui_venda()


## Calcula o valor total de venda considerando todos os tipos de mel no inventário.
func _calcular_valor_total_mel(inv: Node) -> int:
	var total: int = 0
	for id_item in inv.listar_ids_itens():
		if not String(id_item).begins_with("mel"):
			continue
		var quantidade: int = inv.contar_item_por_id(id_item)
		if quantidade <= 0:
			continue
		var item: Item = inv.obter_item_por_id(id_item)
		if item == null:
			continue
		total += quantidade * maxi(item.valor_venda, 1)
	return total


## Remove todos os itens de mel (incluindo raridades) do inventário.
func _remover_todos_os_mels(inv: Node) -> void:
	for id_item in inv.listar_ids_itens():
		if String(id_item).begins_with("mel"):
			inv.remover_todos_por_id(id_item)


## Atualiza o hint quando o inventário do jogador muda (item trocado, mel vendido, etc.)
func _ao_inventario_mudou() -> void:
	if _jogador_proximo:
		_atualizar_hint()
	if interface_esta_aberta():
		_atualizar_ui_venda()


## Cria a interface interativa de venda por tipo de mel.
func _criar_ui_venda() -> void:
	_ui_layer = CanvasLayer.new()
	_ui_layer.name = "UIMercadoMel"
	_ui_layer.layer = 24
	_ui_layer.visible = false
	add_child(_ui_layer)

	var raiz := Control.new()
	raiz.name = "RaizUIMercado"
	raiz.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	raiz.mouse_filter = Control.MOUSE_FILTER_STOP
	_ui_layer.add_child(raiz)

	var fundo := ColorRect.new()
	fundo.name = "FundoMercado"
	fundo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fundo.color = Color(0.0, 0.0, 0.0, 0.56)
	fundo.mouse_filter = Control.MOUSE_FILTER_STOP
	raiz.add_child(fundo)

	var centro := CenterContainer.new()
	centro.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centro.mouse_filter = Control.MOUSE_FILTER_IGNORE
	raiz.add_child(centro)

	var painel := PanelContainer.new()
	painel.custom_minimum_size = Vector2(760.0, 520.0)
	painel.add_theme_stylebox_override("panel", _criar_stylebox_painel_ui_mercado())
	painel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	painel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	centro.add_child(painel)

	var coluna := VBoxContainer.new()
	coluna.add_theme_constant_override("separation", 12)
	coluna.alignment = BoxContainer.ALIGNMENT_CENTER
	painel.add_child(coluna)

	var titulo := Label.new()
	titulo.text = "MERCADO DE MEL"
	titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	titulo.add_theme_font_size_override("font_size", 34)
	titulo.add_theme_color_override("font_color", Color(0.47, 0.33, 0.05))
	titulo.add_theme_constant_override("outline_size", 2)
	titulo.add_theme_color_override("font_outline_color", Color(1.0, 0.96, 0.88))

	coluna.add_child(titulo)

	_ui_status = Label.new()
	_ui_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ui_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ui_status.add_theme_font_size_override("font_size", 18)
	_ui_status.add_theme_color_override("font_color", Color(0.29, 0.26, 0.17))

	coluna.add_child(_ui_status)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(650.0, 300.0)
	coluna.add_child(scroll)

	_ui_lista_tipos = VBoxContainer.new()
	_ui_lista_tipos.add_theme_constant_override("separation", 8)
	_ui_lista_tipos.alignment = BoxContainer.ALIGNMENT_CENTER
	_ui_lista_tipos.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ui_lista_tipos.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_ui_lista_tipos.custom_minimum_size = Vector2(650.0, 290.0)
	scroll.add_child(_ui_lista_tipos)

	_ui_feedback = Label.new()
	_ui_feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ui_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ui_feedback.add_theme_color_override("font_color", Color(0.50, 0.34, 0.0))
	_ui_feedback.add_theme_font_size_override("font_size", 15)
	coluna.add_child(_ui_feedback)

	_btn_vender_todos = Button.new()
	_btn_vender_todos.text = "Vender todos os tipos"
	_btn_vender_todos.custom_minimum_size = Vector2(0.0, 52.0)
	_aplicar_estilo_botao_ui_mercado(_btn_vender_todos, "primario")
	_btn_vender_todos.pressed.connect(_ao_btn_vender_todos)
	coluna.add_child(_btn_vender_todos)

	var btn_fechar := Button.new()
	btn_fechar.text = "Fechar"
	btn_fechar.custom_minimum_size = Vector2(0.0, 52.0)
	_aplicar_estilo_botao_ui_mercado(btn_fechar, "secundario")
	btn_fechar.pressed.connect(_fechar_interface_venda)
	coluna.add_child(btn_fechar)


## Cria o estilo do painel principal da interface de mercado de mel.
func _criar_stylebox_painel_ui_mercado() -> StyleBoxFlat:
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


## Aplica o estilo de botão padrão do design system para o mercado de mel.
func _aplicar_estilo_botao_ui_mercado(botao: Button, tipo: String) -> void:
	var normal := StyleBoxFlat.new()
	var hover := StyleBoxFlat.new()
	var pressed := StyleBoxFlat.new()

	match tipo:
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
		"item":
			normal.bg_color = Color(0.99, 0.72, 0.12)
			normal.border_color = Color(0.50, 0.34, 0.0)
			hover.bg_color = Color(1.0, 0.79, 0.21)
			hover.border_color = Color(0.50, 0.34, 0.0)
			pressed.bg_color = Color(0.93, 0.64, 0.08)
			pressed.border_color = Color(0.40, 0.28, 0.0)
			botao.add_theme_color_override("font_color", Color(0.33, 0.22, 0.0))
			botao.add_theme_color_override("font_hover_color", Color(0.33, 0.22, 0.0))
			botao.add_theme_color_override("font_pressed_color", Color(0.27, 0.18, 0.0))
		_:
			normal.bg_color = Color(0.62, 0.81, 0.42)
			normal.border_color = Color(0.24, 0.42, 0.12)
			hover.bg_color = Color(0.68, 0.86, 0.48)
			hover.border_color = Color(0.24, 0.42, 0.12)
			pressed.bg_color = Color(0.54, 0.72, 0.36)
			pressed.border_color = Color(0.18, 0.33, 0.09)
			botao.add_theme_color_override("font_color", Color(0.14, 0.24, 0.08))
			botao.add_theme_color_override("font_hover_color", Color(0.14, 0.24, 0.08))
			botao.add_theme_color_override("font_pressed_color", Color(0.10, 0.19, 0.06))

	for estilo in [normal, hover, pressed]:
		estilo.border_width_top = 2
		estilo.border_width_right = 2
		estilo.border_width_bottom = 6
		estilo.border_width_left = 2
		estilo.corner_radius_top_left = 12
		estilo.corner_radius_top_right = 12
		estilo.corner_radius_bottom_right = 12
		estilo.corner_radius_bottom_left = 12
		estilo.content_margin_top = 10
		estilo.content_margin_bottom = 10
		estilo.content_margin_left = 12
		estilo.content_margin_right = 12

	botao.add_theme_stylebox_override("normal", normal)
	botao.add_theme_stylebox_override("hover", hover)
	botao.add_theme_stylebox_override("pressed", pressed)
	botao.add_theme_color_override("font_disabled_color", Color(0.33, 0.22, 0.0))
	botao.add_theme_font_size_override("font_size", 18)


# --- ANIMAÇÃO ---

## Inicia tweens em loop que simulam respiração (scale Y) e um leve balançar (rotação Y),
## dando vida ao NPC mesmo sem animação skeletal.
func _iniciar_animacao_respiracao() -> void:
	# Respiração: scale Y sobe e desce suavemente
	var tween_resp := create_tween()
	tween_resp.set_loops()
	tween_resp.tween_property(_corpo, "scale:y", ESCALA_MODELO_COMPRADORA.y * 0.97, 0.8) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT) \
		.from(ESCALA_MODELO_COMPRADORA.y)
	tween_resp.tween_property(_corpo, "scale:y", ESCALA_MODELO_COMPRADORA.y * 1.02, 0.8) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween_resp.tween_property(_corpo, "scale:y", ESCALA_MODELO_COMPRADORA.y, 0.8) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	# Balançar lateral: rotação Y oscila levemente como se olhasse ao redor
	var tween_balanco := create_tween()
	tween_balanco.set_loops()
	tween_balanco.tween_property(_corpo, "rotation_degrees:y", 8.0, 1.5) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT) \
		.from(0.0)
	tween_balanco.tween_property(_corpo, "rotation_degrees:y", -8.0, 3.0) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween_balanco.tween_property(_corpo, "rotation_degrees:y", 0.0, 1.5) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## Feedback visual de venda bem-sucedida: pulso no corpo
func _animar_venda() -> void:
	var tween := create_tween()
	tween.tween_property(_corpo, "scale", ESCALA_MODELO_COMPRADORA * 1.15, 0.12) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_corpo, "scale", ESCALA_MODELO_COMPRADORA, 0.2) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)


## Feedback visual de recusa: balança lateralmente indicando que não aceita o item
func _animar_recusa() -> void:
	var tween := create_tween()
	tween.tween_property(_corpo, "position:x", 0.08, 0.06)
	tween.tween_property(_corpo, "position:x", -0.08, 0.06)
	tween.tween_property(_corpo, "position:x", 0.05, 0.06)
	tween.tween_property(_corpo, "position:x", 0.0, 0.06)
