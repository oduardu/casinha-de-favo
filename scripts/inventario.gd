class_name Inventario
extends Node

# Inventário simplificado: sem hotbar e sem item na mão.
# Mantém contagem por id e limite total de itens de mel na mochila.


# --- SINAIS ---

# Emitido sempre que o conteúdo do inventário muda
signal inventario_mudou

# Mantido por compatibilidade com scripts antigos que ainda conectam esse sinal
signal slot_selecionado_mudou(novo_indice: int)

# Mantido por compatibilidade com scripts antigos que ainda conectam esse sinal
signal item_na_mao_mudou(novo_item: Item)


# --- CONFIGURAÇÃO ---

# Capacidade inicial de mel na mochila do jogador
@export var capacidade_mel_mochila: int = 30


# --- ESTADO ---

# Quantidade por id do item; ex: {"mel": 12, "flor": 3}
var _quantidades_por_id: Dictionary = {}

# Referência de Item por id para preservar metadados (valor_venda, tipo_interacao etc.)
var _itens_por_id: Dictionary = {}


func _ready() -> void:
	# Registra no grupo para a HUD localizar o inventário sem referência direta
	add_to_group("inventario")
	inventario_mudou.emit()


# --- API LEGADA (COMPATIBILIDADE) ---

# Hotbar foi removida, então não existe item na mão
func obter_item_na_mao() -> Item:
	return null


# Hotbar foi removida, então essa operação não existe mais
func remover_item_na_mao(_quantidade: int = 1) -> bool:
	return false


# Hotbar foi removida, função mantida só para não quebrar chamadas antigas
func selecionar_slot(_indice: int) -> void:
	return


# Hotbar foi removida, função mantida só para não quebrar chamadas antigas
func proximo_slot() -> void:
	return


# Hotbar foi removida, função mantida só para não quebrar chamadas antigas
func slot_anterior() -> void:
	return


# --- MANIPULAÇÃO DE ITENS ---

# Adiciona itens no inventário e retorna o restante que não coube.
# Para mel, respeita a capacidade da mochila.
func adicionar_item(novo_item: Item, quantidade: int) -> int:
	if novo_item == null or quantidade <= 0:
		return quantidade

	var id_item: String = novo_item.id
	if id_item.is_empty():
		return quantidade

	var quantidade_atual: int = contar_item_por_id(id_item)
	var quantidade_para_adicionar: int = quantidade
	if _id_eh_mel(id_item):
		var espaco_disponivel: int = maxi(capacidade_mel_mochila - contar_total_mel(), 0)
		quantidade_para_adicionar = mini(quantidade, espaco_disponivel)

	if quantidade_para_adicionar <= 0:
		return quantidade

	_quantidades_por_id[id_item] = quantidade_atual + quantidade_para_adicionar
	_itens_por_id[id_item] = novo_item
	inventario_mudou.emit()
	item_na_mao_mudou.emit(null)
	return quantidade - quantidade_para_adicionar


# Retorna quantas unidades de um item existem no inventário pelo id
func contar_item_por_id(id_item: String) -> int:
	if not _quantidades_por_id.has(id_item):
		return 0
	return maxi(int(_quantidades_por_id[id_item]), 0)


# Retorna quantos itens de mel existem somando todos os tipos/raridades.
func contar_total_mel() -> int:
	var total: int = 0
	for id_item_variant in _quantidades_por_id.keys():
		var id_item: String = String(id_item_variant)
		if not _id_eh_mel(id_item):
			continue
		total += contar_item_por_id(id_item)
	return total


# Remove uma quantidade específica por id e retorna quanto foi removido de fato
func remover_item_por_id(id_item: String, quantidade: int) -> int:
	if quantidade <= 0:
		return 0

	var atual: int = contar_item_por_id(id_item)
	if atual <= 0:
		return 0

	var removidos: int = mini(quantidade, atual)
	var restante: int = atual - removidos
	if restante <= 0:
		_quantidades_por_id.erase(id_item)
		_itens_por_id.erase(id_item)
	else:
		_quantidades_por_id[id_item] = restante

	inventario_mudou.emit()
	item_na_mao_mudou.emit(null)
	return removidos


# Remove todas as unidades de um item pelo id e retorna a quantidade removida
func remover_todos_por_id(id_item: String) -> int:
	return remover_item_por_id(id_item, contar_item_por_id(id_item))


# Retorna todos os ids de item presentes no inventário.
func listar_ids_itens() -> Array[String]:
	var ids: Array[String] = []
	for id_item_variant in _quantidades_por_id.keys():
		ids.append(String(id_item_variant))
	return ids


# Retorna a referência do item por id para acessar metadados
func obter_item_por_id(id_item: String) -> Item:
	if not _itens_por_id.has(id_item):
		return null
	return _itens_por_id[id_item] as Item


# Retorna true quando existe pelo menos 1 item com o tipo_interacao informado
func possui_item_com_tipo_interacao(tipo_interacao: String) -> bool:
	for id_item in _quantidades_por_id.keys():
		var quantidade: int = contar_item_por_id(String(id_item))
		if quantidade <= 0:
			continue
		var item: Item = obter_item_por_id(String(id_item))
		if item != null and item.tipo_interacao == tipo_interacao:
			return true
	return false


# Consome a quantidade pedida do primeiro item encontrado com esse tipo_interacao
func consumir_item_por_tipo_interacao(tipo_interacao: String, quantidade: int = 1) -> bool:
	if quantidade <= 0:
		return false
	for id_item in _quantidades_por_id.keys():
		var item: Item = obter_item_por_id(String(id_item))
		if item == null or item.tipo_interacao != tipo_interacao:
			continue
		var removidos: int = remover_item_por_id(String(id_item), quantidade)
		return removidos == quantidade
	return false


# Retorna true quando o id representa um item de mel (comum ou raridades).
func _id_eh_mel(id_item: String) -> bool:
	return id_item.begins_with("mel")
