class_name HexTile
extends Node3D

# --- SINAIS ---

## Emitido quando um CharacterBody3D entra na Area3D de compra deste tile bloqueado
signal jogador_entrou_compravel

## Emitido quando um CharacterBody3D sai da Area3D de compra deste tile bloqueado
signal jogador_saiu_compravel

## Emitido quando o tile é comprado com sucesso; 'custo' é o valor pago
signal comprado(custo: int)


# --- CONSTANTES ---

## Escala de renderização dos tiles (deve coincidir com mundo.gd)
const TILE_SCALE := 5.0

## Caminho do modelo GLB do tile de terra (jogável)
const CAMINHO_DIRT := "res://obj/kenney_hexagonal/dirt.glb"

## Caminho do modelo GLB do tile de grama (externo / bloqueado)
const CAMINHO_GRASS := "res://obj/kenney_hexagonal/grass.glb"


# --- VARIÁVEIS DE ESTADO ---

## Coordenada axial (q, r) do tile na grade hexagonal
var coordenada: Vector2i

## Tipo do tile: "dirt" para jogável, "grass" para externo bloqueado
var tipo: String = "dirt"

## Se true, o tile está desbloqueado e o jogador pode construir nele
var desbloqueado: bool = true

## Custo em moedas para desbloquear este tile; 0 para tiles inicialmente desbloqueados
var preco: int = 0


# --- NÓS FILHOS (criados em _ready) ---

## Nó com o modelo 3D carregado (dirt.glb ou grass.glb)
var _modelo: Node3D = null

## StaticBody3D que bloqueia fisicamente o jogador de entrar no tile enquanto bloqueado
var _corpo_bloqueio: StaticBody3D = null

## Area3D que detecta a proximidade do jogador para exibir a UI de compra
var _area_compra: Area3D = null

## Label3D flutuante mostrando o preço do tile (visível quando o jogador está próximo)
var _label_preco: Label3D = null

## Label3D flutuante mostrando mensagens de erro (sem dinheiro, sem vizinho, etc.)
var _label_erro: Label3D = null


# --- CICLO DE VIDA ---

func _ready() -> void:
	_carregar_modelo()
	if not desbloqueado:
		_aplicar_cor_morta()
		_criar_bloqueio()
		_criar_area_compra()
		_criar_labels()


# --- CARREGAMENTO DO MODELO ---

## Carrega o GLB correspondente ao tipo do tile, aplica escala e posicionamento vertical
func _carregar_modelo() -> void:
	var caminho := CAMINHO_DIRT if tipo == "dirt" else CAMINHO_GRASS
	var recurso = load(caminho)
	if recurso == null:
		push_error("HexTile: não foi possível carregar modelo em '%s'." % caminho)
		return

	_modelo = recurso.instantiate() as Node3D
	_modelo.scale = Vector3(TILE_SCALE, TILE_SCALE, TILE_SCALE)
	# Desloca o modelo para baixo de modo que a superfície superior fique em y=0
	_modelo.position.y = -0.2 * TILE_SCALE
	add_child(_modelo)


# --- API PÚBLICA ---

## Retorna true se o tile está desbloqueado e pode receber construções
func pode_construir() -> bool:
	return desbloqueado


## Desbloqueia o tile: remove obstáculos, restaura a cor e emite o sinal 'comprado'
func desbloquear() -> void:
	desbloqueado = true
	_aplicar_cor_normal()

	# Remove o bloqueio físico se existir
	if is_instance_valid(_corpo_bloqueio):
		_corpo_bloqueio.queue_free()
		_corpo_bloqueio = null

	# Remove a área de detecção de compra se existir
	if is_instance_valid(_area_compra):
		_area_compra.queue_free()
		_area_compra = null

	# Oculta os labels
	if is_instance_valid(_label_preco):
		_label_preco.visible = false
	if is_instance_valid(_label_erro):
		_label_erro.visible = false

	emit_signal("comprado", preco)


## Tenta comprar este tile: valida vizinhança, saldo e executa a compra.
## Mostra mensagem de erro em _label_erro se a condição não for satisfeita.
func tentar_comprar(jogador: Node) -> void:
	if desbloqueado:
		return

	if not _tem_vizinho_desbloqueado():
		_mostrar_erro("Sem acesso!\nDesbloqueie um vizinho primeiro.")
		return

	if not GerenciadorMundo.tem_dinheiro(preco):
		_mostrar_erro("Sem moedas!\nPrecisa de %d 💰" % preco)
		return

	GerenciadorMundo.gastar(preco)
	GerenciadorMundo.registrar_desbloqueio(coordenada)
	desbloquear()


# --- LÓGICA DE VIZINHANÇA ---

## Retorna true se pelo menos um dos 6 vizinhos axiais deste tile está desbloqueado.
## Consulta o nó pai (GeradorMundo / Mundo) via método obter_tile().
func _tem_vizinho_desbloqueado() -> bool:
	# As 6 direções axiais do sistema de coordenadas pointy-top
	var direcoes := [
		Vector2i( 1,  0),
		Vector2i(-1,  0),
		Vector2i( 0,  1),
		Vector2i( 0, -1),
		Vector2i( 1, -1),
		Vector2i(-1,  1),
	]
	var pai := get_parent()
	if pai == null:
		return false

	for dir in direcoes:
		var coord_vizinho: Vector2i = coordenada + dir
		if pai.has_method("obter_tile"):
			var vizinho = pai.obter_tile(coord_vizinho)
			if vizinho != null and vizinho.desbloqueado:
				return true

	return false


# --- APARÊNCIA ---

## Aplica um material cinza dessaturado recursivamente em todos os MeshInstance3D filhos,
## indicando que o tile está bloqueado
func _aplicar_cor_morta() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 0.45, 0.45)
	_aplicar_material_recursivo(_modelo, mat)


## Remove o material_override de todos os MeshInstance3D filhos,
## restaurando as texturas originais do modelo
func _aplicar_cor_normal() -> void:
	_aplicar_material_recursivo(_modelo, null)


## Percorre recursivamente a subárvore de 'no' e aplica 'material' como material_override
## em cada MeshInstance3D encontrado
func _aplicar_material_recursivo(no: Node, material) -> void:
	if no == null:
		return
	if no is MeshInstance3D:
		(no as MeshInstance3D).material_override = material
	for filho in no.get_children():
		_aplicar_material_recursivo(filho, material)


# --- CRIAÇÃO DE FÍSICA ---

## Cria um StaticBody3D com CylinderShape3D para impedir o jogador de caminhar
## sobre o tile enquanto ele estiver bloqueado
func _criar_bloqueio() -> void:
	_corpo_bloqueio = StaticBody3D.new()
	_corpo_bloqueio.name = "BloqueioFisico"

	var forma := CylinderShape3D.new()
	forma.radius = 1.3 * TILE_SCALE / 3.0  # Raio proporcional ao tile
	forma.height = 2.0                       # Altura suficiente para bloquear o personagem

	var colisao := CollisionShape3D.new()
	colisao.shape = forma
	colisao.position.y = 1.0  # Centraliza verticalmente no tile

	_corpo_bloqueio.add_child(colisao)
	add_child(_corpo_bloqueio)


## Cria uma Area3D levemente maior que o bloqueio para detectar quando o jogador
## se aproxima e pode tentar comprar o tile
func _criar_area_compra() -> void:
	_area_compra = Area3D.new()
	_area_compra.name = "AreaCompra"

	var forma := CylinderShape3D.new()
	forma.radius = 1.8 * TILE_SCALE / 3.0  # Raio ligeiramente maior que o bloqueio
	forma.height = 3.0

	var colisao := CollisionShape3D.new()
	colisao.shape = forma
	colisao.position.y = 1.5  # Centraliza verticalmente

	_area_compra.add_child(colisao)
	_area_compra.body_entered.connect(_ao_entrar_area)
	_area_compra.body_exited.connect(_ao_sair_area)
	add_child(_area_compra)


# --- CRIAÇÃO DE LABELS ---

## Cria os dois Label3D: _label_preco (amarelo) e _label_erro (vermelho),
## ambos em modo billboard para sempre ficarem de frente para a câmera
func _criar_labels() -> void:
	var altura_base := 1.5 * TILE_SCALE / 3.0

	# Label de preço
	_label_preco = Label3D.new()
	_label_preco.name = "LabelPreco"
	_label_preco.text = "💰 %d" % preco
	_label_preco.position.y = altura_base
	_label_preco.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label_preco.modulate = Color(1.0, 0.85, 0.0)  # Amarelo
	_label_preco.font_size = 18
	_label_preco.visible = false
	add_child(_label_preco)

	# Label de erro (um pouco acima do label de preço)
	_label_erro = Label3D.new()
	_label_erro.name = "LabelErro"
	_label_erro.text = ""
	_label_erro.position.y = altura_base + 0.4
	_label_erro.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label_erro.modulate = Color(1.0, 0.2, 0.2)  # Vermelho
	_label_erro.font_size = 16
	_label_erro.visible = false
	add_child(_label_erro)


# --- CALLBACKS DE ÁREA ---

## Chamado quando um corpo entra na Area3D de compra.
## Exibe o label de preço e emite o sinal de aproximação se for o jogador.
func _ao_entrar_area(body: Node) -> void:
	if body is CharacterBody3D:
		if is_instance_valid(_label_preco):
			_label_preco.visible = true
		emit_signal("jogador_entrou_compravel")


## Chamado quando um corpo sai da Area3D de compra.
## Oculta o label de preço e emite o sinal de afastamento se for o jogador.
func _ao_sair_area(body: Node) -> void:
	if body is CharacterBody3D:
		if is_instance_valid(_label_preco):
			_label_preco.visible = false
		emit_signal("jogador_saiu_compravel")


# --- FEEDBACK DE ERRO ---

## Exibe 'msg' no _label_erro e o faz desaparecer gradualmente após 1.5 segundos
func _mostrar_erro(msg: String) -> void:
	if not is_instance_valid(_label_erro):
		return

	_label_erro.text = msg
	_label_erro.modulate = Color(1.0, 0.2, 0.2, 1.0)
	_label_erro.visible = true

	# Cancela qualquer tween anterior de erro antes de criar um novo
	var tween := create_tween()
	tween.tween_interval(1.5)
	tween.tween_property(_label_erro, "modulate:a", 0.0, 0.4) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_callback(func() -> void:
		if is_instance_valid(_label_erro):
			_label_erro.visible = false
			_label_erro.modulate.a = 1.0
	)
