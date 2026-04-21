class_name Inventario
extends Node

# --- SINAIS ---
# Emitido sempre que o conteúdo do inventário muda — a HotbarUI escuta para redesenhar
signal inventario_mudou
# Emitido quando o slot selecionado troca — a HotbarUI escuta para atualizar o destaque
signal slot_selecionado_mudou(novo_indice: int)
# Emitido quando o item que está na mão muda — o player escuta para trocar o modelo 3D
signal item_na_mao_mudou(novo_item: Item)


# --- CONFIGURAÇÃO ---
@export var tamanho_hotbar: int = 6  # Quantos slots existem na hotbar


# --- ESTADO ---
var slots: Array[SlotInventario] = []  # Array com todos os slots da hotbar
var slot_selecionado: int = 0          # Índice do slot ativo no momento


func _ready() -> void:
	# Registra no grupo para que a HotbarUI possa encontrar este nó sem referência direta
	add_to_group("inventario")

	# Cria os slots vazios conforme o tamanho configurado
	for i in tamanho_hotbar:
		slots.append(SlotInventario.new())

	# Emite o estado inicial para sincronizar qualquer UI já conectada
	inventario_mudou.emit()


# --- SELEÇÃO DE SLOT ---

# Seleciona o slot pelo índice; ignora se o índice for inválido
func selecionar_slot(indice: int) -> void:
	if indice < 0 or indice >= tamanho_hotbar:
		return
	slot_selecionado = indice
	slot_selecionado_mudou.emit(slot_selecionado)
	item_na_mao_mudou.emit(obter_item_na_mao())


# Avança para o próximo slot em loop circular
func proximo_slot() -> void:
	selecionar_slot((slot_selecionado + 1) % tamanho_hotbar)


# Volta para o slot anterior em loop circular
func slot_anterior() -> void:
	selecionar_slot((slot_selecionado - 1 + tamanho_hotbar) % tamanho_hotbar)


# --- MANIPULAÇÃO DE ITENS ---

# Retorna o item do slot selecionado, ou null se o slot estiver vazio
func obter_item_na_mao() -> Item:
	if slots.is_empty():
		return null
	return slots[slot_selecionado].item


# Adiciona 'quantidade' unidades do item ao inventário.
# Tenta empilhar em slots que já têm o mesmo item primeiro.
# Depois preenche slots vazios. Retorna o que não coube (0 = tudo adicionado).
func adicionar_item(novo_item: Item, quantidade: int) -> int:
	var restante := quantidade

	# Tentativa 1: empilhar em slots existentes com o mesmo item
	if novo_item.empilhavel:
		for slot in slots:
			if not slot.esta_vazio() and slot.item.id == novo_item.id:
				restante = slot.adicionar(restante)
				if restante <= 0:
					inventario_mudou.emit()
					return 0

	# Tentativa 2: preencher slots vazios
	for slot in slots:
		if slot.esta_vazio():
			slot.item = novo_item
			slot.quantidade = 0
			restante = slot.adicionar(restante)
			if restante <= 0:
				inventario_mudou.emit()
				return 0

	# O que sobrou não coube em nenhum slot
	inventario_mudou.emit()
	return restante


# Remove 'quantidade' itens do slot selecionado.
# Retorna true se conseguiu remover. Emite sinais para atualizar UI e modelo 3D.
func remover_item_na_mao(quantidade: int = 1) -> bool:
	if slots.is_empty():
		return false
	var sucesso := slots[slot_selecionado].remover(quantidade)
	if sucesso:
		inventario_mudou.emit()
		item_na_mao_mudou.emit(obter_item_na_mao())
	return sucesso


# --- INPUT ---

# Captura as teclas de seleção de slot (1–6, Q, scroll do mouse)
func _unhandled_input(event: InputEvent) -> void:
	# Teclas numéricas selecionam diretamente o slot correspondente
	for i in tamanho_hotbar:
		if event.is_action_pressed("hotbar_%d" % (i + 1)):
			selecionar_slot(i)
			get_viewport().set_input_as_handled()
			return

	# Tecla Q: slot anterior
	if event.is_action_pressed("slot_anterior"):
		slot_anterior()
		get_viewport().set_input_as_handled()
