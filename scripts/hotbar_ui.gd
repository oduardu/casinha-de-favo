extends Control

# --- CONSTANTES VISUAIS ---
const TAMANHO_SLOT := 64        # Largura e altura de cada slot em pixels
const ESPACO_ENTRE_SLOTS := 6   # Gap entre slots em pixels
const COR_FUNDO_SLOT := Color(0.1, 0.1, 0.1, 0.75)       # Fundo padrão do slot
const COR_SLOT_SELECIONADO := Color(0.95, 0.8, 0.2, 1.0)  # Borda amarela no slot ativo
const COR_BORDA_NORMAL := Color(0.35, 0.35, 0.35, 1.0)    # Borda cinza nos slots inativos


# --- REFERÊNCIAS ---
var _inventario: Node = null                # Nó Inventario encontrado via grupo
var _container_slots: HBoxContainer = null  # HBox que contém os painéis dos slots
var _paineis: Array[Panel] = []             # Um Panel por slot, para atualizar o estilo
var _icones: Array[TextureRect] = []        # TextureRect do ícone em cada slot
var _labels_qtd: Array[Label] = []          # Label de quantidade em cada slot
var _labels_nome: Array[Label] = []         # Label de nome do item quando não há ícone


func _ready() -> void:
	# Impede que o Control da hotbar absorva cliques do mouse (quebraria o click-to-move)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_inventario = get_tree().get_first_node_in_group("inventario")
	if _inventario == null:
		push_error("HotbarUI: nenhum nó com grupo 'inventario' encontrado")
		return

	_criar_container()
	_criar_slots(_inventario.tamanho_hotbar)
	_reposicionar()  # Calcula posição após saber a quantidade de slots
	_conectar_sinais()
	_atualizar_todos_slots()
	_atualizar_destaque(_inventario.slot_selecionado)


# --- CRIAÇÃO VISUAL ---

# Cria o HBoxContainer sem ancora — a posição é definida em _reposicionar()
func _criar_container() -> void:
	_container_slots = HBoxContainer.new()
	_container_slots.name = "SlotsContainer"
	_container_slots.add_theme_constant_override("separation", ESPACO_ENTRE_SLOTS)
	add_child(_container_slots)


# Posiciona o container no centro inferior da tela usando as dimensões reais da viewport
func _reposicionar() -> void:
	var n: int = _inventario.tamanho_hotbar
	var largura: int = n * TAMANHO_SLOT + (n - 1) * ESPACO_ENTRE_SLOTS
	var tela := get_viewport().get_visible_rect().size
	_container_slots.position = Vector2(
		(tela.x - largura) * 0.5,
		tela.y - TAMANHO_SLOT - 12
	)


# Cria N painéis de slot e os adiciona ao container
func _criar_slots(quantidade: int) -> void:
	for i in quantidade:
		var painel := _criar_painel_slot(i)
		_container_slots.add_child(painel)
		_paineis.append(painel)


# Cria um painel individual com ícone, nome fallback e label de quantidade
func _criar_painel_slot(_indice: int) -> Panel:
	var painel := Panel.new()
	painel.custom_minimum_size = Vector2(TAMANHO_SLOT, TAMANHO_SLOT)

	# Fundo com borda arredondada
	var estilo := StyleBoxFlat.new()
	estilo.bg_color = COR_FUNDO_SLOT
	estilo.border_color = COR_BORDA_NORMAL
	estilo.set_border_width_all(2)
	estilo.set_corner_radius_all(6)
	painel.add_theme_stylebox_override("panel", estilo)

	# TextureRect para o ícone do item
	var icone := TextureRect.new()
	icone.name = "Icone"
	icone.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	icone.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icone.set_anchors_preset(Control.PRESET_FULL_RECT)
	icone.offset_left = 6
	icone.offset_top = 6
	icone.offset_right = -6
	icone.offset_bottom = -6
	painel.add_child(icone)
	_icones.append(icone)

	# Label com o nome do item — visível quando não há ícone
	var label_nome := Label.new()
	label_nome.name = "NomeItem"
	label_nome.add_theme_font_size_override("font_size", 11)
	label_nome.add_theme_color_override("font_color", Color.WHITE)
	label_nome.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label_nome.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label_nome.set_anchors_preset(Control.PRESET_FULL_RECT)
	label_nome.offset_left = 4
	label_nome.offset_right = -4
	painel.add_child(label_nome)
	_labels_nome.append(label_nome)

	# Label de quantidade no canto inferior direito
	var label_qtd := Label.new()
	label_qtd.name = "Quantidade"
	label_qtd.add_theme_font_size_override("font_size", 13)
	label_qtd.add_theme_color_override("font_color", Color.WHITE)
	label_qtd.add_theme_color_override("font_shadow_color", Color.BLACK)
	label_qtd.add_theme_constant_override("shadow_offset_x", 1)
	label_qtd.add_theme_constant_override("shadow_offset_y", 1)
	label_qtd.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label_qtd.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	label_qtd.set_anchors_preset(Control.PRESET_FULL_RECT)
	label_qtd.offset_right = -4
	label_qtd.offset_bottom = -2
	painel.add_child(label_qtd)
	_labels_qtd.append(label_qtd)

	return painel


# --- ATUALIZAÇÃO VISUAL ---

# Redesenha todos os slots com os dados atuais do inventário
func _atualizar_todos_slots() -> void:
	if _inventario == null:
		return
	for i in _inventario.slots.size():
		_atualizar_slot(i)


# Atualiza ícone, nome e quantidade de um slot específico
func _atualizar_slot(indice: int) -> void:
	if indice >= _paineis.size():
		return

	var slot: SlotInventario = _inventario.slots[indice]

	if slot.esta_vazio():
		_icones[indice].texture = null
		_labels_nome[indice].text = ""
		_labels_qtd[indice].text = ""
		var estilo := _paineis[indice].get_theme_stylebox("panel") as StyleBoxFlat
		if estilo:
			estilo.bg_color = COR_FUNDO_SLOT
		return

	# Ícone disponível: mostra a textura; sem ícone: mostra o nome com cor de fundo
	if slot.item.icone != null:
		_icones[indice].texture = slot.item.icone
		_labels_nome[indice].text = ""
	else:
		_icones[indice].texture = null
		_labels_nome[indice].text = slot.item.nome_exibicao
		var estilo := _paineis[indice].get_theme_stylebox("panel") as StyleBoxFlat
		if estilo:
			# Cor derivada do hash do id — sempre a mesma cor para o mesmo item
			var h := float(slot.item.id.hash() & 0xFFFF) / float(0xFFFF)
			estilo.bg_color = Color.from_hsv(h, 0.55, 0.35, 0.85)

	_labels_qtd[indice].text = "" if slot.quantidade <= 1 else str(slot.quantidade)


# Atualiza bordas para destacar o slot selecionado
func _atualizar_destaque(slot_ativo: int) -> void:
	for i in _paineis.size():
		var estilo := _paineis[i].get_theme_stylebox("panel") as StyleBoxFlat
		if estilo == null:
			continue
		if i == slot_ativo:
			estilo.border_color = COR_SLOT_SELECIONADO
			estilo.set_border_width_all(3)
			_animar_pulso(_paineis[i])
		else:
			estilo.border_color = COR_BORDA_NORMAL
			estilo.set_border_width_all(2)


# Tween de pulso no slot recém-selecionado
func _animar_pulso(painel: Panel) -> void:
	var tween := create_tween()
	tween.tween_property(painel, "scale", Vector2(1.12, 1.12), 0.08) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(painel, "scale", Vector2.ONE, 0.12) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)


# --- SINAIS ---

# Conecta os sinais do Inventario para manter a UI sincronizada automaticamente
func _conectar_sinais() -> void:
	_inventario.inventario_mudou.connect(_atualizar_todos_slots)
	_inventario.slot_selecionado_mudou.connect(_atualizar_destaque)
