extends Control

# Exibe dois contadores de mel no canto superior direito da tela:
# - Mel no inventário atual (consumível, destaque maior)
# - Total de mel coletado desde o início do jogo (estatística, menor)
# Encontra o inventário via grupo e as colmeias via grupo "colmeia".


# --- REFERÊNCIAS ---

## Nó Inventario encontrado via grupo "inventario"
var _inventario: Node = null

## Label grande exibindo o mel atual no inventário (ex: "🍯 x3")
var _label_mel_inv: Label = null

## Label pequena exibindo o total histórico de mel coletado (ex: "Total: 12")
var _label_mel_total: Label = null

## Container vertical dos dois labels
var _container: VBoxContainer = null


# --- CICLO DE VIDA ---

func _ready() -> void:
	# MOUSE_FILTER_IGNORE garante que este Control não consome cliques do mouse.
	# Sem isso, o Control full-screen bloqueia o click-to-move do player.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_inventario = get_tree().get_first_node_in_group("inventario")
	if _inventario == null:
		push_warning("UIMel: nenhum nó no grupo 'inventario' encontrado.")
	_criar_ui()
	_conectar_sinais()
	_atualizar()


# --- CRIAÇÃO VISUAL ---

## Cria os dois labels dentro de um VBoxContainer no canto superior direito
func _criar_ui() -> void:
	_container = VBoxContainer.new()
	_container.name = "ContainerMel"
	# Margem do canto superior direito
	var tela := get_viewport().get_visible_rect().size
	_container.position = Vector2(tela.x - 150.0, 16.0)
	add_child(_container)

	# Label grande: mel no inventário
	_label_mel_inv = Label.new()
	_label_mel_inv.name = "MelInventario"
	_label_mel_inv.add_theme_font_size_override("font_size", 22)
	_label_mel_inv.add_theme_color_override("font_color", Color(1.0, 0.88, 0.15))
	_label_mel_inv.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.7))
	_label_mel_inv.add_theme_constant_override("shadow_offset_x", 1)
	_label_mel_inv.add_theme_constant_override("shadow_offset_y", 1)
	_container.add_child(_label_mel_inv)

	# Label pequena: total histórico
	_label_mel_total = Label.new()
	_label_mel_total.name = "MelTotal"
	_label_mel_total.add_theme_font_size_override("font_size", 13)
	_label_mel_total.add_theme_color_override("font_color", Color(0.85, 0.75, 0.50))
	_container.add_child(_label_mel_total)


# --- SINAIS ---

## Conecta ao inventario_mudou e ao mel_coletado de todas as colmeias do grupo
func _conectar_sinais() -> void:
	if _inventario != null:
		_inventario.inventario_mudou.connect(_atualizar)

	# Conecta ao sinal de cada colmeia já presente na árvore
	for colmeia in get_tree().get_nodes_in_group("colmeia"):
		if colmeia.has_signal("mel_coletado"):
			colmeia.mel_coletado.connect(func(_q: int) -> void: _atualizar())


# --- ATUALIZAÇÃO ---

## Redesenha os dois contadores com os valores atuais
func _atualizar() -> void:
	var mel_inv := _contar_mel_inventario()
	_label_mel_inv.text = "🍯 x%d" % mel_inv
	_label_mel_total.text = "Total coletado: %d" % GerenciadorMundo.total_mel_coletado


## Soma a quantidade do item "mel" em todos os slots do inventário
func _contar_mel_inventario() -> int:
	if _inventario == null:
		return 0
	var total := 0
	for slot in _inventario.slots:
		if not slot.esta_vazio() and slot.item.id == "mel":
			total += slot.quantidade
	return total
