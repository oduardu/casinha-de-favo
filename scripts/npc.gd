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

## Caixa roxa que representa visualmente o corpo do NPC (placeholder)
var _corpo: CSGBox3D = null

## Area3D que detecta a proximidade do jogador
var _area_deteccao: Area3D = null

## Label3D que mostra a dica contextual ao jogador ("Vender Mel" / "Sem mel")
var _hint_label: Label3D = null

## True enquanto o jogador está dentro da área de detecção
var _jogador_proximo: bool = false

## Referência ao jogador dentro da área (para acessar inventário na venda)
var _jogador_ref: Node = null


# --- CICLO DE VIDA ---

func _ready() -> void:
	add_to_group("npc")
	_criar_corpo()
	_iniciar_animacao_respiracao()
	_criar_area_deteccao()
	_criar_hint_label()


# --- CRIAÇÃO DOS ELEMENTOS ---

## Cria o corpo do NPC como uma CSGBox3D roxa apoiada na superfície do tile
func _criar_corpo() -> void:
	_corpo = CSGBox3D.new()
	_corpo.name = "CorpoNPC"
	_corpo.size = Vector3(0.5, 1.0, 0.5)
	_corpo.position.y = 0.5  # A base do personagem toca y=0

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.545, 0.353, 0.62)  # #8B5A9E — roxo
	_corpo.material_override = mat

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
	_hint_label.font_size = 22
	_hint_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_hint_label.position.y = 1.7
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
		_hint_label.text = "E — Vender todo mel (%d moeda)" % valor_total
		_hint_label.modulate = Color(1.0, 0.88, 0.15)  # Amarelo dourado
	else:
		_hint_label.text = "Compro mel!"
		_hint_label.modulate = Color(0.75, 0.65, 0.85)  # Lilás suave


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


# --- ANIMAÇÃO ---

## Inicia um tween em loop que escala levemente o corpo no eixo Y,
## simulando uma respiração suave
func _iniciar_animacao_respiracao() -> void:
	var tween := create_tween()
	tween.set_loops()  # Repete indefinidamente

	# Escala de 1.0 → 0.95 → 1.05 → 0.95 → volta, ciclo de 2 segundos no total
	tween.tween_property(_corpo, "scale:y", 0.95, 0.5) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT) \
		.from(1.0)
	tween.tween_property(_corpo, "scale:y", 1.05, 0.5) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(_corpo, "scale:y", 0.95, 0.5) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(_corpo, "scale:y", 1.0, 0.5) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## Feedback visual de venda bem-sucedida: pulso no corpo
func _animar_venda() -> void:
	var tween := create_tween()
	tween.tween_property(_corpo, "scale", Vector3(1.2, 1.2, 1.2), 0.12) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_corpo, "scale", Vector3.ONE, 0.2) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)


## Feedback visual de recusa: balança lateralmente indicando que não aceita o item
func _animar_recusa() -> void:
	var tween := create_tween()
	tween.tween_property(_corpo, "position:x", 0.08, 0.06)
	tween.tween_property(_corpo, "position:x", -0.08, 0.06)
	tween.tween_property(_corpo, "position:x", 0.05, 0.06)
	tween.tween_property(_corpo, "position:x", 0.0, 0.06)
