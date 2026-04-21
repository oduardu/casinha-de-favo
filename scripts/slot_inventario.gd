class_name SlotInventario
extends RefCounted

# O item guardado neste slot; null = slot vazio
var item: Item = null
# Quantos itens existem neste slot no momento
var quantidade: int = 0


# Retorna true se o slot não tem nenhum item
func esta_vazio() -> bool:
	return item == null or quantidade <= 0


# Tenta adicionar 'quantos' itens ao slot.
# Retorna o que sobrou caso o slot já esteja cheio ou o stack transborde.
# Chamado por Inventario.adicionar_item()
func adicionar(quantos: int) -> int:
	if item == null:
		return quantos  # Slot sem item definido não pode receber

	var espaco_disponivel := item.quantidade_maxima - quantidade
	var adicionar_de_fato := mini(quantos, espaco_disponivel)
	quantidade += adicionar_de_fato
	return quantos - adicionar_de_fato  # Sobra que não coube


# Tenta remover 'quantos' itens do slot.
# Retorna true se conseguiu remover a quantidade pedida.
# Zera o item quando a quantidade chega a zero.
# Chamado por Inventario.remover_item_na_mao()
func remover(quantos: int) -> bool:
	if quantidade < quantos:
		return false  # Não tem itens suficientes

	quantidade -= quantos
	if quantidade <= 0:
		quantidade = 0
		item = null  # Slot fica vazio quando não sobra nenhum
	return true
