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

## Caminho do modelo GLB do tile de grama com relevo
const CAMINHO_GRASS_HILL := "res://obj/kenney_hexagonal/grass-hill.glb"

## Caminho do modelo GLB do tile de floresta
const CAMINHO_GRASS_FOREST := "res://obj/kenney_hexagonal/grass-forest.glb"

## Caminho do modelo GLB do tile com madeira
const CAMINHO_DIRT_LUMBER := "res://obj/kenney_hexagonal/dirt-lumber.glb"

## Caminho do modelo GLB do tile com pedras
const CAMINHO_STONE_ROCKS := "res://obj/kenney_hexagonal/stone-rocks.glb"

## Caminho do modelo GLB de trilha reta
const CAMINHO_PATH_STRAIGHT := "res://obj/kenney_hexagonal/path-straight.glb"

## Caminho do modelo GLB de curva de trilha
const CAMINHO_PATH_CORNER := "res://obj/kenney_hexagonal/path-corner.glb"

## Caminho do modelo GLB de cruzamento de trilha
const CAMINHO_PATH_CROSSING := "res://obj/kenney_hexagonal/path-crossing.glb"

## Caminho do modelo GLB do hexágono de colmeia normal
const CAMINHO_COLMEIA_HEX_NORMAL := "res://obj/colmeias/hexagonal_colmeia_normal.glb"

## Caminho do modelo GLB do hexágono de colmeia rara
const CAMINHO_COLMEIA_HEX_RARA := "res://obj/colmeias/hexagonal_colmeia_rara.glb"

## Caminho do modelo GLB padrão de chão (tema chaos)
const CAMINHO_CHAO_CHAOS := "res://obj/chaos/hexagono_chao.glb"


# --- VARIÁVEIS DE ESTADO ---

## Coordenada axial (q, r) do tile na grade hexagonal
var coordenada: Vector2i

## Tipo visual do tile (ex.: "grass", "grass-hill", "grass-forest", "dirt-lumber", "stone-rocks")
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

## StaticBody3D para colisão de obstáculo em tiles decorativos do mapa inicial
var _corpo_obstaculo: StaticBody3D = null

## StaticBody3D para colisões específicas do modelo de hexágono de colmeia
var _corpo_colmeia_normal: StaticBody3D = null

## Label3D flutuante mostrando o preço do tile (visível quando o jogador está próximo)
var _label_preco: Label3D = null

## Label3D flutuante mostrando mensagens de erro (sem dinheiro, sem vizinho, etc.)
var _label_erro: Label3D = null


# --- CICLO DE VIDA ---

func _ready() -> void:
	_carregar_modelo()
	if desbloqueado and _tipo_bloqueia_passagem(tipo):
		_criar_colisao_obstaculo()
	if not desbloqueado:
		_aplicar_cor_morta()
		_criar_bloqueio()
		_criar_area_compra()
		_criar_labels()


# --- CARREGAMENTO DO MODELO ---

## Carrega o GLB correspondente ao tipo do tile, aplica escala e posicionamento vertical
func _carregar_modelo() -> void:
	if _tipo_eh_caminho(tipo):
		_modelo = _instanciar_modelo(CAMINHO_CHAO_CHAOS, "ModeloBase")
		if _modelo == null:
			return
		add_child(_modelo)

		var modelo_caminho := _instanciar_modelo(_obter_caminho_modelo(tipo), "ModeloCaminho")
		if modelo_caminho == null:
			return
		# Leve offset para evitar z-fighting entre o chão base e o path
		modelo_caminho.position.y += 0.03
		add_child(modelo_caminho)
		return

	_modelo = _instanciar_modelo(_obter_caminho_modelo(tipo), "Modelo")
	if _modelo == null:
		return
	add_child(_modelo)
	if _tipo_eh_colmeia(tipo):
		_criar_colisao_colmeia_normal()


## Instancia um modelo de tile, aplica escala padrão e offset vertical de alinhamento.
func _instanciar_modelo(caminho: String, nome_no: String) -> Node3D:
	var recurso: Resource = load(caminho)
	if recurso == null:
		push_error("HexTile: não foi possível carregar modelo em '%s'." % caminho)
		return null

	var modelo := recurso.instantiate() as Node3D
	if modelo == null:
		push_error("HexTile: falha ao instanciar modelo em '%s'." % caminho)
		return null
	modelo.name = nome_no
	modelo.scale = Vector3(TILE_SCALE, TILE_SCALE, TILE_SCALE)
	# Desloca o modelo para baixo de modo que a superfície superior fique em y=0
	modelo.position.y = -0.2 * TILE_SCALE
	return modelo


## Resolve o tipo de tile para o caminho do GLB correspondente.
## Em caso de tipo desconhecido, mantém fallback para grass para evitar tile invisível.
func _obter_caminho_modelo(tipo_tile: String) -> String:
	match tipo_tile:
		"dirt":
			return CAMINHO_CHAO_CHAOS
		"grass":
			return CAMINHO_CHAO_CHAOS
		"grass-hill":
			return CAMINHO_CHAO_CHAOS
		"grass-forest":
			return CAMINHO_CHAO_CHAOS
		"dirt-lumber":
			return CAMINHO_CHAO_CHAOS
		"stone-rocks":
			return CAMINHO_CHAO_CHAOS
		"path-straight":
			return CAMINHO_PATH_STRAIGHT
		"path-corner":
			return CAMINHO_PATH_CORNER
		"path-crossing":
			return CAMINHO_PATH_CROSSING
		"path-casa":
			return CAMINHO_PATH_CORNER
		"colmeia-normal":
			return CAMINHO_COLMEIA_HEX_NORMAL
		"colmeia-rara":
			return CAMINHO_COLMEIA_HEX_RARA
		_:
			push_warning("HexTile: tipo desconhecido '%s', usando grass." % tipo_tile)
			return CAMINHO_CHAO_CHAOS


## Retorna true quando o tipo visual representa um obstáculo sólido.
func _tipo_bloqueia_passagem(tipo_tile: String) -> bool:
	return tipo_tile == "grass-forest" \
		or tipo_tile == "dirt-lumber" \
		or tipo_tile == "stone-rocks"


## Retorna true quando o tipo visual é um path usado como sobreposição de trilha.
func _tipo_eh_caminho(tipo_tile: String) -> bool:
	return tipo_tile == "path-straight" \
		or tipo_tile == "path-corner" \
		or tipo_tile == "path-crossing"


## Retorna true quando o tipo visual representa um hexágono de colmeia.
func _tipo_eh_colmeia(tipo_tile: String) -> bool:
	return tipo_tile == "colmeia-normal" \
		or tipo_tile == "colmeia-rara"


# --- API PÚBLICA ---

## Retorna true se o tile está desbloqueado e pode receber construções
func pode_construir() -> bool:
	return desbloqueado


## Troca o tipo visual do tile em tempo de execução e recarrega o(s) modelo(s) 3D.
func definir_tipo_visual(novo_tipo: String) -> void:
	tipo = novo_tipo
	_limpar_modelos_visuais()
	_carregar_modelo()


## Remove os nós de modelo visual atuais para permitir recarga limpa do tipo.
func _limpar_modelos_visuais() -> void:
	_limpar_colisao_colmeia_normal()
	for filho in get_children():
		if not (filho is Node3D):
			continue
		var nome_filho: String = String(filho.name)
		if nome_filho == "Modelo" or nome_filho == "ModeloBase" or nome_filho == "ModeloCaminho":
			filho.queue_free()
	_modelo = null


## Cria colisão apenas para os meshes "Cylinder" e "Cylinder_001" do hex de colmeia.
func _criar_colisao_colmeia_normal() -> void:
	_limpar_colisao_colmeia_normal()
	if _modelo == null:
		return

	_corpo_colmeia_normal = StaticBody3D.new()
	_corpo_colmeia_normal.name = "ColisaoColmeiaNormal"
	add_child(_corpo_colmeia_normal)

	var nomes_mesh: Array[String] = ["Cylinder", "Cylinder_001"]
	var meshes_alvo: Array[MeshInstance3D] = _coletar_meshes_por_nome(_modelo, nomes_mesh)
	for mesh_alvo in meshes_alvo:
		if mesh_alvo == null or mesh_alvo.mesh == null:
			continue
		var shape: ConvexPolygonShape3D = mesh_alvo.mesh.create_convex_shape()
		if shape == null:
			continue
		var colisao := CollisionShape3D.new()
		colisao.shape = shape
		_corpo_colmeia_normal.add_child(colisao)
		colisao.global_transform = mesh_alvo.global_transform


## Remove o corpo de colisão do hex de colmeia, se existir.
func _limpar_colisao_colmeia_normal() -> void:
	if is_instance_valid(_corpo_colmeia_normal):
		_corpo_colmeia_normal.queue_free()
		_corpo_colmeia_normal = null


## Coleta recursivamente MeshInstance3D cujo nome está em 'nomes'.
func _coletar_meshes_por_nome(raiz: Node, nomes: Array[String]) -> Array[MeshInstance3D]:
	var resultado: Array[MeshInstance3D] = []
	_coletar_meshes_por_nome_recursivo(raiz, nomes, resultado)
	return resultado


## Implementação recursiva de busca de meshes por nome.
func _coletar_meshes_por_nome_recursivo(no: Node, nomes: Array[String], saida: Array[MeshInstance3D]) -> void:
	if no is MeshInstance3D and nomes.has(String(no.name)):
		saida.append(no as MeshInstance3D)
	for filho in no.get_children():
		_coletar_meshes_por_nome_recursivo(filho, nomes, saida)


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

## Cria uma colisão central para tiles decorativos com obstáculo.
## A largura foi calibrada para bloquear o objeto sem fechar totalmente os corredores.
func _criar_colisao_obstaculo() -> void:
	_corpo_obstaculo = StaticBody3D.new()
	_corpo_obstaculo.name = "ObstaculoFisico"

	var forma := CylinderShape3D.new()
	forma.radius = 0.9 * TILE_SCALE / 3.0
	forma.height = 1.8

	var colisao := CollisionShape3D.new()
	colisao.shape = forma
	colisao.position.y = 0.9

	_corpo_obstaculo.add_child(colisao)
	add_child(_corpo_obstaculo)


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
