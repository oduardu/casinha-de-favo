extends Control

# HUD com ícones 3D (coin.glb, honey.glb, number-X.glb) renderizados via SubViewport.
# Exibe moedas e mel do jogador no canto superior direito.


# --- CAMINHOS DOS MODELOS ---

const CAMINHO_COIN := "res://obj/kenney_ui/coins/coin.glb"
const CAMINHO_HONEY := "res://obj/kenney_ui/honey/honey.glb"
const PREFIXO_NUMEROS := "res://obj/kenney_ui/numbers/number-"


# --- CONFIGURAÇÃO ---

## Tamanho em pixels de cada SubViewport de ícone
const TAMANHO_ICONE := Vector2i(64, 64)

## Tamanho em pixels de cada SubViewport de dígito
const TAMANHO_DIGITO := Vector2i(36, 48)

## Quantidade máxima de dígitos por contador
const MAX_DIGITOS := 4


# --- REFERÊNCIAS ---

var _inventario: Node = null
var _container: VBoxContainer = null
var _digitos_moedas: Array[SubViewportContainer] = []
var _digitos_mel: Array[SubViewportContainer] = []
var _cenas_digitos: Array[PackedScene] = []
var _moedas_cache: int = -1
var _mel_cache: int = -1


# --- CICLO DE VIDA ---

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_inventario = get_tree().get_first_node_in_group("inventario")
	_pre_carregar_digitos()
	_criar_ui()
	_conectar_sinais()
	_atualizar_tudo()
	set_process(true)


func _process(_delta: float) -> void:
	var moedas_atual := GerenciadorMundo.moedas
	if moedas_atual != _moedas_cache:
		_moedas_cache = moedas_atual
		_atualizar_digitos(_digitos_moedas, moedas_atual)

	var mel_atual := _contar_mel_inventario()
	if mel_atual != _mel_cache:
		_mel_cache = mel_atual
		_atualizar_digitos(_digitos_mel, mel_atual)


# --- PRÉ-CARREGAMENTO ---

func _pre_carregar_digitos() -> void:
	for i in 10:
		var caminho := PREFIXO_NUMEROS + str(i) + ".glb"
		if ResourceLoader.exists(caminho):
			_cenas_digitos.append(load(caminho))
		else:
			_cenas_digitos.append(null)


# --- CRIAÇÃO VISUAL ---

func _criar_ui() -> void:
	_container = VBoxContainer.new()
	_container.name = "ContainerHUD"
	_container.add_theme_constant_override("separation", 4)
	var tela := get_viewport().get_visible_rect().size
	_container.position = Vector2(tela.x - 250.0, 12.0)
	add_child(_container)

	# Linha de moedas
	var linha_moedas := HBoxContainer.new()
	linha_moedas.name = "LinhaCoins"
	linha_moedas.add_theme_constant_override("separation", 2)
	linha_moedas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_container.add_child(linha_moedas)
	linha_moedas.add_child(_criar_icone_3d(CAMINHO_COIN, TAMANHO_ICONE))
	_digitos_moedas = _criar_grupo_digitos(linha_moedas)

	# Linha de mel
	var linha_mel := HBoxContainer.new()
	linha_mel.name = "LinhaHoney"
	linha_mel.add_theme_constant_override("separation", 2)
	linha_mel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_container.add_child(linha_mel)
	linha_mel.add_child(_criar_icone_3d(CAMINHO_HONEY, TAMANHO_ICONE))
	_digitos_mel = _criar_grupo_digitos(linha_mel)


## Cria um SubViewportContainer que renderiza um modelo 3D como ícone.
## Usa apenas DirectionalLight3D — sem WorldEnvironment para não afetar a cena principal.
func _criar_icone_3d(caminho: String, tamanho: Vector2i) -> SubViewportContainer:
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.custom_minimum_size = Vector2(tamanho)
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var sv := SubViewport.new()
	sv.size = tamanho
	sv.transparent_bg = true
	sv.render_target_update_mode = SubViewport.UPDATE_ONCE
	sv.own_world_3d = true  # Isola a renderização — não compartilha com a cena principal
	svc.add_child(sv)

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 1.6
	cam.position = Vector3(0.0, 0.6, 2.0)
	cam.rotation_degrees = Vector3(-15.0, 0.0, 0.0)
	cam.far = 10.0
	sv.add_child(cam)

	# Duas luzes direcionais para iluminação limpa sem WorldEnvironment
	var luz1 := DirectionalLight3D.new()
	luz1.rotation_degrees = Vector3(-40.0, 30.0, 0.0)
	luz1.light_energy = 2.0
	sv.add_child(luz1)

	var luz2 := DirectionalLight3D.new()
	luz2.rotation_degrees = Vector3(-20.0, -60.0, 0.0)
	luz2.light_energy = 0.8
	sv.add_child(luz2)

	if ResourceLoader.exists(caminho):
		var cena: PackedScene = load(caminho)
		if cena != null:
			var modelo: Node3D = cena.instantiate() as Node3D
			modelo.name = "Modelo"
			sv.add_child(modelo)

	return svc


func _criar_grupo_digitos(pai: HBoxContainer) -> Array[SubViewportContainer]:
	var grupo: Array[SubViewportContainer] = []
	for i in MAX_DIGITOS:
		var svc := _criar_digito_viewport()
		svc.visible = false
		pai.add_child(svc)
		grupo.append(svc)
	return grupo


func _criar_digito_viewport() -> SubViewportContainer:
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.custom_minimum_size = Vector2(TAMANHO_DIGITO)
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var sv := SubViewport.new()
	sv.name = "SV"
	sv.size = TAMANHO_DIGITO
	sv.transparent_bg = true
	sv.render_target_update_mode = SubViewport.UPDATE_ONCE
	sv.own_world_3d = true  # Isola a renderização
	svc.add_child(sv)

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 1.2
	cam.position = Vector3(0.0, 0.5, 2.0)
	cam.rotation_degrees = Vector3(-10.0, 0.0, 0.0)
	cam.far = 10.0
	sv.add_child(cam)

	var luz1 := DirectionalLight3D.new()
	luz1.rotation_degrees = Vector3(-40.0, 30.0, 0.0)
	luz1.light_energy = 2.0
	sv.add_child(luz1)

	var luz2 := DirectionalLight3D.new()
	luz2.rotation_degrees = Vector3(-20.0, -60.0, 0.0)
	luz2.light_energy = 0.8
	sv.add_child(luz2)

	return svc


# --- ATUALIZAÇÃO DOS DÍGITOS ---

func _atualizar_digitos(grupo: Array[SubViewportContainer], valor: int) -> void:
	var texto := str(maxi(valor, 0))
	var offset := MAX_DIGITOS - texto.length()

	for i in MAX_DIGITOS:
		var svc := grupo[i]
		var sv: SubViewport = svc.get_node("SV")
		var pos_texto := i - offset

		if pos_texto < 0 or pos_texto >= texto.length():
			svc.visible = false
			continue

		svc.visible = true
		var digito := int(texto[pos_texto])

		var modelo_antigo := sv.get_node_or_null("Digito")
		if modelo_antigo != null:
			if modelo_antigo.has_meta("valor") and modelo_antigo.get_meta("valor") == digito:
				continue
			modelo_antigo.queue_free()

		if digito >= 0 and digito < _cenas_digitos.size() and _cenas_digitos[digito] != null:
			var novo: Node3D = _cenas_digitos[digito].instantiate() as Node3D
			novo.name = "Digito"
			novo.set_meta("valor", digito)
			sv.add_child(novo)
			# Força re-render do SubViewport após trocar o modelo
			sv.render_target_update_mode = SubViewport.UPDATE_ONCE


# --- SINAIS ---

func _conectar_sinais() -> void:
	if _inventario != null:
		_inventario.inventario_mudou.connect(_atualizar_tudo)
	for colmeia in get_tree().get_nodes_in_group("colmeia"):
		if colmeia.has_signal("mel_coletado"):
			colmeia.mel_coletado.connect(func(_q: int) -> void: _atualizar_tudo())


func _atualizar_tudo() -> void:
	_moedas_cache = GerenciadorMundo.moedas
	_atualizar_digitos(_digitos_moedas, _moedas_cache)
	_mel_cache = _contar_mel_inventario()
	_atualizar_digitos(_digitos_mel, _mel_cache)


func _contar_mel_inventario() -> int:
	if _inventario == null:
		return 0
	var total := 0
	for slot in _inventario.slots:
		if not slot.esta_vazio() and slot.item.id == "mel":
			total += slot.quantidade
	return total
