class_name Inventario
extends Node

# Inventário simplificado: sem hotbar e sem item na mão.
# Mantém contagem por id e limite por tipo de mel na mochila.


# --- SINAIS ---

# Emitido sempre que o conteúdo do inventário muda
signal inventario_mudou


# --- CONFIGURAÇÃO ---

# Capacidade base do mel comum na mochila do jogador
@export var capacidade_mel_mochila: int = 30

# Valor base de venda do mel comum usado para calcular a capacidade por tipo
const VALOR_BASE_MEL_COMUM: int = 10


# --- ESTADO ---

# Quantidade por id do item; ex: {"mel": 12, "flor": 3}
var _quantidades_por_id: Dictionary = {}

# Referência de Item por id para preservar metadados (valor_venda, tipo_interacao etc.)
var _itens_por_id: Dictionary = {}


# True após o inventário ter sido carregado do save; impede salvar antes da hora
var _pronto_para_salvar: bool = false


func _ready() -> void:
	# Registra no grupo para a HUD localizar o inventário sem referência direta
	add_to_group("inventario")
	# NÃO carrega aqui — o pai (mundo.gd) chama carregar_do_save() após GerenciadorMundo.carregar()
	inventario_mudou.connect(_ao_inventario_mudar)
	inventario_mudou.emit()


# Callback para salvar o inventário sempre que houver mudança de conteúdo.
func _ao_inventario_mudar() -> void:
	if _pronto_para_salvar:
		salvar_inventario()


# Chamado externamente por mundo.gd após GerenciadorMundo.carregar() garantir dados válidos.
func carregar_do_save() -> void:
	_carregar_inventario()
	_pronto_para_salvar = true



# --- MANIPULAÇÃO DE ITENS ---

# Adiciona itens no inventário e retorna o restante que não coube.
# Para mel, respeita a capacidade específica do tipo de mel.
func adicionar_item(novo_item: Item, quantidade: int) -> int:
	if novo_item == null or quantidade <= 0:
		return quantidade

	var id_item: String = novo_item.id
	if id_item.is_empty():
		return quantidade

	var quantidade_atual: int = contar_item_por_id(id_item)
	var quantidade_para_adicionar: int = quantidade
	if _id_eh_mel(id_item):
		var capacidade_tipo: int = obter_capacidade_por_item(novo_item)
		var espaco_disponivel: int = maxi(capacidade_tipo - quantidade_atual, 0)
		quantidade_para_adicionar = mini(quantidade, espaco_disponivel)

	if quantidade_para_adicionar <= 0:
		return quantidade

	_quantidades_por_id[id_item] = quantidade_atual + quantidade_para_adicionar
	_itens_por_id[id_item] = novo_item
	inventario_mudou.emit()

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


# Retorna a capacidade máxima para um tipo de item de mel com base no valor de venda.
# Exemplo: mel comum (valor 10) com capacidade base 30 -> 30;
# mel raro (valor 20) -> 20.
func obter_capacidade_por_item(item: Item) -> int:
	if item == null or not _id_eh_mel(item.id):
		return 0
	var valor_item: int = maxi(item.valor_venda, 1)
	var diferenca_valor: int = maxi(valor_item - VALOR_BASE_MEL_COMUM, 0)
	return maxi(capacidade_mel_mochila - diferenca_valor, 1)


# Retorna a capacidade máxima para um tipo de mel já conhecido no inventário.
func obter_capacidade_por_id(id_item: String) -> int:
	if not _id_eh_mel(id_item):
		return 0
	var item: Item = obter_item_por_id(id_item)
	if item == null:
		return maxi(capacidade_mel_mochila, 1)
	return obter_capacidade_por_item(item)


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


# --- PERSISTÊNCIA ---

# Salva o estado do inventário no GerenciadorMundo para ser persistido em disco.
func salvar_inventario() -> void:
	var dados: Array = []
	for id_item in _quantidades_por_id.keys():
		var quantidade: int = contar_item_por_id(String(id_item))
		if quantidade <= 0:
			continue
		var item: Item = obter_item_por_id(String(id_item))
		if item == null:
			continue
		var caminho_recurso: String = item.resource_path
		if caminho_recurso.is_empty():
			continue
		dados.append({
			"id": String(id_item),
			"quantidade": quantidade,
			"recurso": caminho_recurso,
		})
	GerenciadorMundo.inventario_jogador = dados
	GerenciadorMundo.salvar()


# Restaura o inventário a partir do GerenciadorMundo após carregar o save.
func _carregar_inventario() -> void:
	var dados: Array = GerenciadorMundo.inventario_jogador
	if dados.is_empty():
		return
	for entrada in dados:
		if not (entrada is Dictionary):
			continue
		var caminho: String = str(entrada.get("recurso", ""))
		var quantidade: int = maxi(int(entrada.get("quantidade", 0)), 0)
		if caminho.is_empty() or quantidade <= 0:
			continue
		if not ResourceLoader.exists(caminho):
			continue
		var item: Item = load(caminho) as Item
		if item == null:
			continue
		adicionar_item(item, quantidade)
