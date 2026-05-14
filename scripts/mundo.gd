extends Node3D

# --- CONFIGURAÇÃO ---

## Raio em tiles da área externa bloqueada ao redor da grade inicial
@export var raio_mundo_externo: int = 8

## Preço base em moedas; o custo real de um tile externo é preco_base * dist²
@export var preco_base: int = 10

## Moedas iniciais adicionadas ao GerenciadorMundo na primeira inicialização do jogo

## Caminho da trilha sonora ambiente medieval tocada em loop durante o jogo
@export var caminho_soundtrack: String = "res://resources/audio/soundtrack.mp3"

## Volume base da trilha sonora ambiente em dB
@export var volume_soundtrack_db: float = -8.5

## Duração total do ciclo dia/noite em segundos (15 minutos)
@export var duracao_ciclo_dia_noite_segundos: float = 900.0

## Intensidade máxima da luz direcional durante o dia
@export var energia_luz_dia: float = 1.6

## Intensidade da luz direcional durante a noite
@export var energia_luz_noite: float = 0.12


# --- CONSTANTES ---

## Escala de renderização dos tiles (tamanho visual dos hexágonos)
const TILE_SCALE := 5.0

## Limite mínimo de q na grade inicial 4×4
const Q_MIN := -1

## Limite máximo de q na grade inicial 4×4
const Q_MAX := 2

## Limite mínimo de r na grade inicial 4×4
const R_MIN := -1

## Limite máximo de r na grade inicial 4×4
const R_MAX := 2

## Raio do hexágono em unidades de mundo (metade da distância entre centros opostos)
const HEX_RAIO := TILE_SCALE * 0.58

## Tipos visuais usados apenas no grid inicial para dar variedade ao mapa inicial
const TIPOS_VISUAIS_INICIAIS := [
	"grass-hill",
	"grass-forest",
	"dirt-lumber",
	"stone-rocks",
]

## Coordenadas do corredor principal do mapa inicial.
## Esses tiles sempre usam assets de caminho e ficam sem obstáculos de colisão.
const COORDS_CAMINHO_LIVRE: Array[Vector2i] = [
	Vector2i(-1, -1), # Casa
	Vector2i(0, -1),  # NPC
	Vector2i(0, 0),   # Colmeia
	Vector2i(1, 0),
	Vector2i(1, 1),
	Vector2i(2, 1),
	Vector2i(2, 2),
]

## Chance fixa de spawnar uma colmeia ao comprar um novo hexágono (25%)
const CHANCE_SPAWN_COLMEIA_EM_COMPRA: float = 0.25

## Raridades possíveis para colmeias geradas em compra de terreno
const RARIDADES_COLMEIA_SORTEIO: Array[String] = ["comum", "rara", "epica", "lendaria"]

## Distribuição de raridade no centro do mapa (soma 100%).
## Predomínio de comum conforme solicitado.
const DISTRIBUICAO_RARIDADE_CENTRO: Array[float] = [70.0, 18.0, 8.0, 4.0]

## Distribuição de raridade no limite do mapa (soma 100%).
## Comum reduz, demais raridades aumentam ao se afastar.
const DISTRIBUICAO_RARIDADE_BORDA: Array[float] = [40.0, 30.0, 20.0, 10.0]

## Tipo visual de hexágono usado nos tiles que possuem colmeia
const TIPO_TILE_COLMEIA_NORMAL: String = "colmeia-normal"

## Tipo visual de hexágono usado nos tiles de colmeia rara
const TIPO_TILE_COLMEIA_RARA: String = "colmeia-rara"

## Tipo visual de hexágono usado nos tiles de colmeia épica
const TIPO_TILE_COLMEIA_EPICA: String = "colmeia-epica"

## Tipo visual de hexágono usado nos tiles de colmeia lendária
const TIPO_TILE_COLMEIA_LENDARIA: String = "colmeia-lendaria"

## Texto exibido no painel de licenças do menu ESC.
const TEXTO_LICENCAS_MENU: String = """RECURSOS E LICENCAS

1) Kenney (modelos 3D e kits visuais)
- Fontes usadas no projeto:
  - res://obj/kenney_hexagonal/
  - res://obj/kenney_nature_kit/
  - res://obj/kenney_character/
  - res://obj/kenney_bee/
  - res://obj/kenney_food_kit/
- Licenca: Creative Commons Zero (CC0)
- Termos: uso pessoal, educacional e comercial permitido.
- Referencia: https://creativecommons.org/publicdomain/zero/1.0/
- Credito nao obrigatorio, mas recomendado por Kenney.
- Site: https://www.kenney.nl

2) Trilha sonora ambiente
- Arquivo: res://resources/audio/soundtrack.mp3
- Fonte: Free Fantasy Medieval Ambient Music Pack (AlkaKrab)
- Pagina: https://alkakrab.itch.io/free-fantasy-medieval-ambient-music-pack
- Uso sujeito aos termos informados pelo autor na pagina do pacote.

3) Zumbido de abelha
- Arquivo: res://resources/audio/abelha_base.ogg
- Fonte original: https://www.youtube.com/watch?v=0qv-fq5o1H0

4) Engine
- Godot Engine 4.x
- Licenca: MIT
- Site: https://godotengine.org/license
"""


# --- ESTADO ---

## PackedScene do HexTile carregada em _ready (res://scenes/hex_tile.tscn)
var _hex_tile_cena: PackedScene = null

## Script da Colmeia carregado em _ready para ser aplicado em Node3D instanciados
var _colmeia_cena_script: Script = null

## Script do NPC carregado em _ready para ser aplicado em Node3D instanciados
var _npc_script: Script = null

## Dicionário de Vector2i → HexTile, mapeia coordenadas axiais para os nós de tile
var _tiles_por_coord: Dictionary = {}

## Deslocamento em unidades de mundo para centralizar a grade no ponto de origem
var _deslocamento_centro: Vector3 = Vector3.ZERO

## StaticBody3D plano que serve de chão sob a área jogável; recriado ao comprar tiles
var _piso_corpo: StaticBody3D = null

## Menu de pausa criado em runtime (CanvasLayer com botões)
var _menu_pausa: CanvasLayer = null

## Painel principal do menu de pausa (botões de ação)
var _painel_menu_principal: PanelContainer = null

## Painel de licenças aberto a partir do menu de pausa
var _painel_menu_licencas: PanelContainer = null

## RNG para eventos de geração procedural (spawn de colmeia e raridade)
var _rng_eventos: RandomNumberGenerator = RandomNumberGenerator.new()

## Player de áudio 2D global para trilha sonora de ambiente
var _audio_soundtrack: AudioStreamPlayer = null

## Luz direcional principal que representa o sol
var _luz_sol: DirectionalLight3D = null

## Luz direcional secundária que representa a lua
var _luz_lua: DirectionalLight3D = null

## WorldEnvironment principal para ajustar cor/ambiente ao longo do ciclo
var _world_environment: WorldEnvironment = null

## Referência ao comerciante de mel para controlar aparição por período
var _npc_comprador: NPC = null

## Tempo acumulado no ciclo dia/noite atual
var _tempo_ciclo_dia_noite: float = 0.0

## Dia atual do mundo (incrementa ao fim de cada ciclo completo)
var _dia_atual: int = 1

## True quando está de dia no ciclo atual
var _periodo_eh_dia: bool = true

## Área de descanso na casa que permite avançar para o próximo dia à noite
var _area_descanso_casa: Area3D = null

## Label 3D de dica para deitar na casa durante a noite
var _hint_descanso_casa: Label3D = null

## True enquanto o jogador está dentro da área de descanso da casa
var _jogador_perto_descanso: bool = false

## Label do aviso de dormir (filho do painel estilizado)
var _label_aviso_dormir: Label = null

## Container raiz do aviso de dormir (painel + label)
var _container_aviso_dormir: Control = null

## Container raiz do popup de conquista
var _container_conquista: Control = null

## Label do titulo da conquista
var _label_conquista_titulo: Label = null

## Label da descricao da conquista
var _label_conquista_descricao: Label = null


# --- CICLO DE VIDA ---

## Salva ao fechar a janela, já que GerenciadorMundo não é um Node
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_salvar_posicao_jogador()
		_salvar_estado_ciclo_dia_noite()
		var inv_save: Node = get_node_or_null("Player/Inventario")
		if inv_save != null and inv_save.has_method("salvar_inventario"):
			inv_save.salvar_inventario()
		GerenciadorMundo.salvar()


func _ready() -> void:
	# Permite que este nó processe input mesmo durante pausa (para ESC fechar o menu)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_configurar_soundtrack()
	_carregar_recursos()
	GerenciadorMundo.carregar()
	# Restaura o inventário do jogador após o save estar carregado
	var inv: Node = $Player.get_node_or_null("Inventario")
	if inv != null and inv.has_method("carregar_do_save"):
		inv.carregar_do_save()
	_rng_eventos.randomize()
	_calcular_deslocamento()
	_gerar_grade_inicial()
	_gerar_tiles_externos()
	_aplicar_estado_salvo()
	_reconstruir_navmesh()
	_criar_piso()
	_colocar_edificios()
	_preparar_ciclo_dia_noite()
	_setup_ui()
	_criar_menu_pausa()

	# Conecta o PathVisualizer ao NavigationAgent3D do jogador
	var agente = $Player.get_node("NavigationAgent3D")
	if agente != null and $PathVisualizer != null:
		$PathVisualizer.setup(agente)
	_restaurar_posicao_jogador()
	set_process(true)


## Atualiza ciclo dia/noite e estado de período enquanto o jogo estiver ativo.
func _process(delta: float) -> void:
	if get_tree().paused:
		return
	if duracao_ciclo_dia_noite_segundos <= 0.1:
		return
	var tempo_anterior: float = _tempo_ciclo_dia_noite
	_tempo_ciclo_dia_noite = fposmod(_tempo_ciclo_dia_noite + delta, duracao_ciclo_dia_noite_segundos)
	if tempo_anterior > _tempo_ciclo_dia_noite:
		_dia_atual += 1
		_salvar_estado_ciclo_dia_noite()
	_aplicar_iluminacao_ciclo_dia_noite()

	var periodo_atual: bool = _calcular_periodo_eh_dia()
	if periodo_atual != _periodo_eh_dia:
		_periodo_eh_dia = periodo_atual
		_aplicar_estado_periodo()
		_salvar_estado_ciclo_dia_noite()


# --- INPUT ---

## Tecla ESC abre/fecha o menu de pausa
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if _fechar_menu_aberto_por_escape():
			get_viewport().set_input_as_handled()
			return
		_alternar_menu_pausa()
		get_viewport().set_input_as_handled()


# --- CONFIGURAÇÃO ---

## Carrega todas as cenas e scripts necessários; falhas emitem push_error mas não travam o jogo
func _carregar_recursos() -> void:
	if ResourceLoader.exists("res://scenes/hex_tile.tscn"):
		_hex_tile_cena = load("res://scenes/hex_tile.tscn")
	else:
		push_error("mundo.gd: cena hex_tile.tscn não encontrada em res://scenes/")

	if ResourceLoader.exists("res://scripts/colmeia.gd"):
		_colmeia_cena_script = load("res://scripts/colmeia.gd")
	else:
		push_warning("mundo.gd: colmeia.gd não encontrado.")

	if ResourceLoader.exists("res://scripts/npc.gd"):
		_npc_script = load("res://scripts/npc.gd")
	else:
		push_warning("mundo.gd: npc.gd não encontrado.")


## Configura a trilha sonora ambiente com base em soundtrack.mp3 e inicia reprodução em loop.
func _configurar_soundtrack() -> void:
	if not ResourceLoader.exists(caminho_soundtrack):
		push_warning("mundo.gd: soundtrack não encontrado em %s" % caminho_soundtrack)
		return
	var stream: AudioStream = load(caminho_soundtrack) as AudioStream
	if stream == null:
		push_warning("mundo.gd: falha ao carregar soundtrack.")
		return
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	elif stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	elif stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
	if _audio_soundtrack != null and is_instance_valid(_audio_soundtrack):
		_audio_soundtrack.queue_free()
	_audio_soundtrack = AudioStreamPlayer.new()
	_audio_soundtrack.name = "AudioSoundtrack"
	_audio_soundtrack.stream = stream
	_audio_soundtrack.bus = "Master"
	_audio_soundtrack.volume_db = volume_soundtrack_db
	_audio_soundtrack.autoplay = false
	add_child(_audio_soundtrack)
	_audio_soundtrack.play()


# --- CICLO DIA/NOITE ---

## Inicializa referências e estado persistido do ciclo de dia/noite.
func _preparar_ciclo_dia_noite() -> void:
	_luz_sol = get_node_or_null("DirectionalLight3D") as DirectionalLight3D
	if _luz_sol == null:
		_luz_sol = DirectionalLight3D.new()
		_luz_sol.name = "DirectionalLight3D"
		add_child(_luz_sol)
	_luz_sol.visible = true
	_luz_sol.shadow_enabled = true
	_luz_sol.shadow_bias = 0.02
	_luz_sol.directional_shadow_max_distance = 80.0

	_luz_lua = get_node_or_null("DirectionalLightLua") as DirectionalLight3D
	if _luz_lua == null:
		_luz_lua = DirectionalLight3D.new()
		_luz_lua.name = "DirectionalLightLua"
		add_child(_luz_lua)
	_luz_lua.visible = true
	_luz_lua.shadow_enabled = false
	_luz_lua.light_color = Color(0.40, 0.55, 0.95)

	_world_environment = get_node_or_null("WorldEnvironment") as WorldEnvironment
	_dia_atual = maxi(GerenciadorMundo.dia_atual, 1)
	# Se não há save (tempo = 0.0 padrão), inicia o ciclo às 06:00 em vez de 05:00
	var tempo_salvo: float = GerenciadorMundo.tempo_ciclo_dia_noite
	if tempo_salvo <= 0.0:
		tempo_salvo = duracao_ciclo_dia_noite_segundos / 24.0
	_tempo_ciclo_dia_noite = clampf(
		tempo_salvo,
		0.0,
		maxf(duracao_ciclo_dia_noite_segundos - 0.001, 0.0)
	)
	_periodo_eh_dia = _calcular_periodo_eh_dia()
	_aplicar_iluminacao_ciclo_dia_noite()
	_aplicar_estado_periodo()
	_salvar_estado_ciclo_dia_noite()


## Retorna true quando o tempo atual do ciclo está no período diurno (05:00–19:00).
func _calcular_periodo_eh_dia() -> bool:
	if duracao_ciclo_dia_noite_segundos <= 0.1:
		return true
	var hora_atual: float = _obter_hora_decimal_ciclo(_tempo_ciclo_dia_noite)
	return hora_atual >= 5.0 and hora_atual < 19.0


## Converte o tempo acumulado do ciclo para hora decimal (0.0 a <24.0).
## O início do ciclo corresponde às 05:00 para manter o começo do jogo durante o dia.
func _obter_hora_decimal_ciclo(tempo_ciclo: float) -> float:
	if duracao_ciclo_dia_noite_segundos <= 0.1:
		return 12.0
	var fracao_ciclo: float = fposmod(tempo_ciclo, duracao_ciclo_dia_noite_segundos) / duracao_ciclo_dia_noite_segundos
	return fposmod(fracao_ciclo * 24.0 + 5.0, 24.0)


## Retorna a hora atual do mundo em formato decimal (0.0 a <24.0).
func obter_hora_do_dia() -> float:
	return _obter_hora_decimal_ciclo(_tempo_ciclo_dia_noite)


## Retorna o minuto do dia atual (0 a 1439) com base no ciclo.
func obter_minuto_do_dia() -> int:
	return int(floor(obter_hora_do_dia() * 60.0))


## Retorna o horário atual formatado em HH:MM para UI/HUD.
func obter_horario_formatado() -> String:
	var minuto_total: int = clampi(obter_minuto_do_dia(), 0, 1439)
	@warning_ignore("integer_division")
	var horas: int = minuto_total / 60
	var minutos: int = minuto_total % 60
	return "%02d:%02d" % [horas, minutos]


## Aplica iluminação e ambiente com base no tempo atual do ciclo (dia 05:00–19:00).
func _aplicar_iluminacao_ciclo_dia_noite() -> void:
	if _luz_sol == null and _luz_lua == null and _world_environment == null:
		return
	var hora_atual: float = _obter_hora_decimal_ciclo(_tempo_ciclo_dia_noite)
	var fator_sol: float = 0.0
	if hora_atual >= 5.0 and hora_atual < 19.0:
		var t_sol: float = (hora_atual - 5.0) / 14.0
		fator_sol = sin(t_sol * PI)

	var fator_lua: float = 0.0
	if hora_atual >= 19.0 or hora_atual < 5.0:
		var hora_noturna: float = hora_atual if hora_atual >= 19.0 else hora_atual + 24.0
		var t_lua: float = (hora_noturna - 19.0) / 10.0
		fator_lua = sin(t_lua * PI)

	# Ângulo X do sol limitado entre -50° e -70° para evitar sombras rasantes entre tiles
	# No meio-dia (t_sol=0.5) o sol fica a -70° (quase vertical); no nascer/pôr a -50°
	var angulo_sol_x: float = -60.0
	if fator_sol > 0.0:
		angulo_sol_x = lerpf(-50.0, -70.0, sin(((hora_atual - 5.0) / 14.0) * PI))

	var angulo_lua_x: float = -55.0

	if _luz_sol != null:
		_luz_sol.rotation_degrees.x = angulo_sol_x
		_luz_sol.rotation_degrees.y = 0.0  # Sombra cai reta, sem diagonal entre tiles
		_luz_sol.light_energy = lerpf(0.0, energia_luz_dia, fator_sol)
		_luz_sol.light_color = Color(1.0, 0.85, 0.55)

	if _luz_lua != null:
		_luz_lua.rotation_degrees.x = angulo_lua_x
		_luz_lua.rotation_degrees.y = 0.0
		_luz_lua.light_energy = lerpf(0.0, energia_luz_noite, fator_lua)

	var fator_iluminacao_ambiente: float = clampf(fator_sol + (fator_lua * 0.18), 0.0, 1.0)
	if _world_environment != null and _world_environment.environment != null:
		var env: Environment = _world_environment.environment
		env.ambient_light_energy = lerpf(0.05, 0.32, fator_iluminacao_ambiente)
		env.background_color = Color(0.06, 0.09, 0.17).lerp(Color(0.12, 0.35, 0.62), fator_iluminacao_ambiente)


## Aplica efeitos de gameplay do período: abelhas, NPC, hint da cama e aviso de dormir.
func _aplicar_estado_periodo() -> void:
	for no_colmeia in get_tree().get_nodes_in_group("colmeia"):
		if no_colmeia.has_method("definir_periodo_dia"):
			no_colmeia.definir_periodo_dia(_periodo_eh_dia)
	if _npc_comprador != null and is_instance_valid(_npc_comprador):
		_npc_comprador.definir_disponibilidade_no_periodo(_periodo_eh_dia)
	_atualizar_hint_descanso_casa()
	if not _periodo_eh_dia:
		_mostrar_aviso_dormir()
	else:
		_esconder_aviso_dormir()


## Exibe o aviso de dormir com animação de fade-in e esconde após 5 segundos.
func _mostrar_aviso_dormir() -> void:
	if _container_aviso_dormir == null:
		return
	_container_aviso_dormir.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_container_aviso_dormir.visible = true
	var tween := create_tween()
	tween.tween_property(_container_aviso_dormir, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.8) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_interval(4.0)
	tween.tween_property(_container_aviso_dormir, "modulate", Color(1.0, 1.0, 1.0, 0.0), 1.2) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_callback(_container_aviso_dormir.set_visible.bind(false))


## Esconde o aviso de dormir imediatamente (ex.: quando amanhecer).
func _esconder_aviso_dormir() -> void:
	if _container_aviso_dormir == null:
		return
	_container_aviso_dormir.visible = false


# --- CONQUISTAS ---

## Tenta desbloquear uma conquista; exibe popup se for a primeira vez.
func _desbloquear_conquista(id: String, titulo: String, descricao: String) -> void:
	if GerenciadorMundo.conquistas.has(id):
		return
	GerenciadorMundo.conquistas[id] = true
	GerenciadorMundo.salvar()
	_mostrar_popup_conquista(titulo, descricao)


## Exibe o popup de conquista com fade-in, permanencia e fade-out.
func _mostrar_popup_conquista(titulo: String, descricao: String) -> void:
	if _container_conquista == null:
		return
	_label_conquista_titulo.text = titulo
	_label_conquista_descricao.text = descricao
	_container_conquista.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_container_conquista.scale = Vector2(0.8, 0.8)
	_container_conquista.visible = true
	# Fase 1: fade-in + scale-in em paralelo
	var tween := create_tween()
	tween.tween_property(_container_conquista, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.6) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(_container_conquista, "scale", Vector2.ONE, 0.5) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# Fase 2: espera visível
	tween.tween_interval(8.0)
	# Fase 3: fade-out e esconde
	tween.tween_property(_container_conquista, "modulate", Color(1.0, 1.0, 1.0, 0.0), 1.5) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_callback(_container_conquista.set_visible.bind(false))


## Callback quando qualquer colmeia emite mel_coletado; verifica conquista de primeiro mel.
func _ao_mel_coletado_conquista(_quantidade: int) -> void:
	_desbloquear_conquista(
		"primeiro_mel",
		"\ud83c\udf6f Melzinho na chupeta! \ud83d\udc23",
		"Voce coletou mel pela primeira vez!"
	)


## Persiste o estado atual do ciclo no GerenciadorMundo sem forçar I/O em disco.
func _salvar_estado_ciclo_dia_noite() -> void:
	GerenciadorMundo.dia_atual = _dia_atual
	GerenciadorMundo.tempo_ciclo_dia_noite = _tempo_ciclo_dia_noite
	GerenciadorMundo.periodo_eh_dia = _periodo_eh_dia


## Salva a posição atual do jogador no GerenciadorMundo para persistência.
func _salvar_posicao_jogador() -> void:
	var jogador := get_node_or_null("Player")
	if jogador == null:
		return
	var pos: Vector3 = jogador.global_position
	GerenciadorMundo.posicao_jogador = {"x": pos.x, "y": pos.y, "z": pos.z}


## Restaura a posição do jogador a partir do save, se existir.
func _restaurar_posicao_jogador() -> void:
	var dados: Dictionary = GerenciadorMundo.posicao_jogador
	if dados.is_empty():
		return
	if not dados.has("x") or not dados.has("y") or not dados.has("z"):
		return
	var jogador := get_node_or_null("Player")
	if jogador == null:
		return
	jogador.global_position = Vector3(
		float(dados["x"]),
		float(dados["y"]),
		float(dados["z"])
	)


## Retorna true quando está de dia para uso por outros scripts.
func periodo_esta_dia() -> bool:
	return _periodo_eh_dia


## Tenta descansar na casa para avançar imediatamente para o próximo dia.
func tentar_descansar(_jogador: Node) -> bool:
	if _periodo_eh_dia:
		return false
	if not _jogador_perto_descanso:
		return false
	_avancar_para_proximo_dia_por_descanso()
	return true


## Avança para a manhã do próximo dia (06:00) e reaplica estado visual/gameplay.
func _avancar_para_proximo_dia_por_descanso() -> void:
	_dia_atual += 1
	# Tempo correspondente às 06:00 — 1 hora após o início do ciclo (que começa às 05:00)
	_tempo_ciclo_dia_noite = duracao_ciclo_dia_noite_segundos / 24.0
	_periodo_eh_dia = true
	_aplicar_iluminacao_ciclo_dia_noite()
	_aplicar_estado_periodo()
	_salvar_estado_ciclo_dia_noite()
	GerenciadorMundo.salvar()


# --- UTILITÁRIOS ---

## Converte coordenadas axiais (q, r) para posição de mundo sem aplicar o deslocamento central
func _axial_para_mundo_raw(q: int, r: int) -> Vector3:
	var x := (q + r * 0.5) * TILE_SCALE
	var z := r * sqrt(3.0) * 0.5 * TILE_SCALE
	return Vector3(x, 0.0, z)


## Converte coordenadas axiais (q, r) para posição de mundo centralizada na origem
func _axial_para_mundo(q: int, r: int) -> Vector3:
	return _axial_para_mundo_raw(q, r) - _deslocamento_centro


## Calcula a distância em tiles entre duas coordenadas axiais usando a fórmula cúbica
func _hex_dist(a: Vector2i, b: Vector2i) -> int:
	return (abs(a.x - b.x) + abs(a.y - b.y) + abs(a.x + a.y - b.x - b.y)) / 2


## Retorna true se (q, r) está dentro dos limites da grade inicial 4×4
func _esta_no_grid_inicial(q: int, r: int) -> bool:
	return q >= Q_MIN and q <= Q_MAX and r >= R_MIN and r <= R_MAX


## Retorna o HexTile na coordenada axial 'coord', ou null se não existir
func obter_tile(coord: Vector2i) -> HexTile:
	return _tiles_por_coord.get(coord, null)


## Retorna os 6 vértices de um hexágono pointy-top centrado em 'centro' com raio 'raio'
func _hex_vertices(centro: Vector2, raio: float) -> PackedVector2Array:
	var verts := PackedVector2Array()
	for i in 6:
		var angulo := deg_to_rad(30.0 + i * 60.0)
		verts.append(Vector2(
			centro.x + raio * cos(angulo),
			centro.y + raio * sin(angulo)
		))
	return verts


# --- GERAÇÃO DO MUNDO ---

## Calcula _deslocamento_centro como a média das posições brutas de todos os tiles iniciais,
## garantindo que a grade fique centrada na origem do mundo
func _calcular_deslocamento() -> void:
	var soma := Vector3.ZERO
	var contagem := 0
	for q in range(Q_MIN, Q_MAX + 1):
		for r in range(R_MIN, R_MAX + 1):
			soma += _axial_para_mundo_raw(q, r)
			contagem += 1
	if contagem > 0:
		_deslocamento_centro = soma / float(contagem)
		_deslocamento_centro.y = 0.0


## Gera os 16 tiles jogáveis da grade inicial com variação visual e sem custo
func _gerar_grade_inicial() -> void:
	for q in range(Q_MIN, Q_MAX + 1):
		for r in range(R_MIN, R_MAX + 1):
			var coord := Vector2i(q, r)
			_criar_tile(coord, _escolher_tipo_visual_inicial(coord), true, 0)


## Retorna o tipo visual do tile inicial com base na coordenada axial.
## Garante um corredor livre com assets de caminho e usa variedade no restante.
func _escolher_tipo_visual_inicial(coord: Vector2i) -> String:
	if coord == Vector2i(0, 0):
		return TIPO_TILE_COLMEIA_NORMAL
	if coord == Vector2i(Q_MIN, R_MIN):
		return "path-casa"
	if COORDS_CAMINHO_LIVRE.has(coord):
		return _escolher_tipo_caminho(coord)

	var indice_base: int = abs(coord.x * 31 + coord.y * 17 + coord.x * coord.y * 7)
	return TIPOS_VISUAIS_INICIAIS[indice_base % TIPOS_VISUAIS_INICIAIS.size()]


## Retorna uma variação visual de caminho para o corredor livre.
func _escolher_tipo_caminho(coord: Vector2i) -> String:
	var indice: int = COORDS_CAMINHO_LIVRE.find(coord)
	if indice < 0:
		return "path-straight"

	if indice == 2:
		return "path-crossing"
	if indice % 3 == 0:
		return "path-corner"
	return "path-straight"


## Gera os tiles externos bloqueados (grass) ao redor da grade inicial,
## com custo proporcional à distância ao centro
func _gerar_tiles_externos() -> void:
	var margem := raio_mundo_externo + 1
	for q in range(-margem, margem + 1):
		for r in range(-margem, margem + 1):
			if _esta_no_grid_inicial(q, r):
				continue
			var coord := Vector2i(q, r)
			var dist := _hex_dist(coord, Vector2i(0, 0))
			if dist > raio_mundo_externo:
				continue
			var custo := preco_base * dist * dist
			_criar_tile(coord, "grass", false, custo)


## Instancia um HexTile, configura suas propriedades e o adiciona à cena e ao dicionário.
## Para tiles bloqueados, conecta os sinais de compra ao Player e ao mundo.
func _criar_tile(coord: Vector2i, tipo: String, eh_desbloqueado: bool, custo: int) -> void:
	if _hex_tile_cena == null:
		return

	var tile := _hex_tile_cena.instantiate() as HexTile
	if tile == null:
		push_error("mundo.gd: falha ao instanciar HexTile para coord %s." % str(coord))
		return

	tile.coordenada = coord
	tile.tipo = tipo
	tile.desbloqueado = eh_desbloqueado
	tile.preco = custo
	tile.position = _axial_para_mundo(coord.x, coord.y)

	add_child(tile)
	_tiles_por_coord[coord] = tile

	# Conecta sinais de interação de compra apenas para tiles bloqueados
	if not eh_desbloqueado:
		var jogador := get_node_or_null("Player")
		if jogador != null:
			if jogador.has_method("_ao_entrar_hex_compravel"):
				tile.jogador_entrou_compravel.connect(jogador._ao_entrar_hex_compravel)
			if jogador.has_method("_ao_sair_hex_compravel"):
				tile.jogador_saiu_compravel.connect(jogador._ao_sair_hex_compravel)
		tile.comprado.connect(
			func(custo_compra: int) -> void: _ao_tile_comprado(tile, custo_compra)
		)


## Aplica o estado do save: desbloqueia sem custo os tiles já comprados anteriormente
func _aplicar_estado_salvo() -> void:
	for entrada in GerenciadorMundo.hexagonos_desbloqueados:
		if not entrada is Dictionary:
			continue
		var q: int = entrada.get("q", 0)
		var r: int = entrada.get("r", 0)
		var coord := Vector2i(q, r)
		var tile := obter_tile(coord)
		if tile != null and not tile.desbloqueado:
			# Desbloqueia diretamente sem emitir sinal de compra (evita re-salvar)
			tile.desbloqueado = true
			tile._aplicar_cor_normal()
			if is_instance_valid(tile._corpo_bloqueio):
				tile._corpo_bloqueio.queue_free()
				tile._corpo_bloqueio = null
			if is_instance_valid(tile._area_compra):
				tile._area_compra.queue_free()
				tile._area_compra = null
			if is_instance_valid(tile._label_preco):
				tile._label_preco.visible = false
			if is_instance_valid(tile._label_erro):
				tile._label_erro.visible = false


# --- COLISÃO E NAVEGAÇÃO ---

## Coleta as posições de todos os tiles desbloqueados como Vector2 (x, z)
func _coletar_centros_desbloqueados() -> Array[Vector2]:
	var centros: Array[Vector2] = []
	for coord in _tiles_por_coord:
		var tile := _tiles_por_coord[coord] as HexTile
		if tile.desbloqueado:
			var pos := tile.global_position
			centros.append(Vector2(pos.x, pos.z))
	return centros


## Cria apenas o chão físico sob a área jogável, dimensionado a partir
## do bounding box dos hexágonos desbloqueados (sem piso visual artificial)
func _criar_piso() -> void:
	if is_instance_valid(_piso_corpo):
		_piso_corpo.queue_free()
		_piso_corpo = null

	var centros := _coletar_centros_desbloqueados()
	if centros.is_empty():
		return

	# Calcula bounding box dos centros dos hexágonos desbloqueados
	var bb_min := centros[0]
	var bb_max := centros[0]
	for c in centros:
		bb_min.x = minf(bb_min.x, c.x)
		bb_min.y = minf(bb_min.y, c.y)
		bb_max.x = maxf(bb_max.x, c.x)
		bb_max.y = maxf(bb_max.y, c.y)

	# Margem de um hex inteiro ao redor do bounding box
	var margem := HEX_RAIO * 2.0
	bb_min -= Vector2(margem, margem)
	bb_max += Vector2(margem, margem)

	var cx := (bb_min.x + bb_max.x) * 0.5
	var cz := (bb_min.y + bb_max.y) * 0.5
	var largura := bb_max.x - bb_min.x
	var profund := bb_max.y - bb_min.y

	_piso_corpo = StaticBody3D.new()
	_piso_corpo.name = "PisoJogavel"

	# Colisão: fino BoxShape3D logo abaixo de y=0
	var forma := BoxShape3D.new()
	forma.size = Vector3(largura, 0.1, profund)
	var colisao := CollisionShape3D.new()
	colisao.shape = forma
	colisao.position = Vector3(cx, -0.05, cz)
	_piso_corpo.add_child(colisao)

	add_child(_piso_corpo)


## Reconstrói a NavigationMesh como um polígono que une os hexágonos desbloqueados.
## Usa o convex hull de todos os vértices dos hexágonos para criar a área navegável.
func _reconstruir_navmesh() -> void:
	var nav_region := get_node_or_null("NavigationRegion3D") as NavigationRegion3D
	if nav_region == null:
		push_warning("mundo.gd: NavigationRegion3D não encontrado.")
		return

	var centros := _coletar_centros_desbloqueados()
	if centros.is_empty():
		return

	# Coleta todos os vértices de todos os hexágonos desbloqueados
	var pontos_2d: PackedVector2Array = PackedVector2Array()
	for c in centros:
		var hex_verts := _hex_vertices(c, HEX_RAIO)
		for v in hex_verts:
			pontos_2d.append(v)

	# Calcula o convex hull dos pontos 2D
	var hull := Geometry2D.convex_hull(pontos_2d)
	if hull.size() < 3:
		return

	# Converte o hull 2D para vértices 3D no plano XZ
	var verts_3d := PackedVector3Array()
	for p in hull:
		verts_3d.append(Vector3(p.x, 0.0, p.y))

	var navmesh := NavigationMesh.new()
	navmesh.cell_height = 0.25
	navmesh.vertices = verts_3d

	# Cria um polígono com todos os índices do hull
	var indices := PackedInt32Array()
	for i in verts_3d.size():
		indices.append(i)
	navmesh.add_polygon(indices)

	nav_region.navigation_mesh = navmesh


# --- EDIFICIOS ---

## Ponto de entrada: cria todos os edifícios do mundo
func _colocar_edificios() -> void:
	_criar_casa()
	_criar_colmeia()
	_recriar_colmeias_dinamicas_salvas()
	_criar_npc()


## Instancia o modelo building-house.glb no tile (Q_MIN, R_MIN).
## Usa a mesma escala dos tiles hexagonais (TILE_SCALE) para encaixar no grid.
## Adiciona colisão física e rotaciona para que a frente fique visível na câmera isométrica.
func _criar_casa() -> void:
	var pos_casa := _axial_para_mundo(Q_MIN, R_MIN)

	var cena_casa: PackedScene = load("res://obj/kenney_hexagonal/building-house.glb")
	if cena_casa == null:
		push_warning("mundo.gd: building-house.glb não encontrado.")
		return

	# Nó raiz para agrupar modelo + colisão
	var casa_raiz := Node3D.new()
	casa_raiz.name = "Casa"
	casa_raiz.position = Vector3(pos_casa.x, 0.0, pos_casa.z)
	add_child(casa_raiz)

	# Modelo visual — mesma escala e offset Y dos tiles hex
	var modelo: Node3D = cena_casa.instantiate() as Node3D
	modelo.name = "ModeloCasa"
	modelo.position.y = -0.2 * TILE_SCALE
	modelo.scale = Vector3.ONE * TILE_SCALE
	modelo.rotation_degrees.y = 180.0
	casa_raiz.add_child(modelo)

	# Colisão física — cilindro que impede o jogador de atravessar a casa
	var fis := StaticBody3D.new()
	fis.name = "CasaColisao"
	var forma := CylinderShape3D.new()
	forma.radius = TILE_SCALE * 0.4
	forma.height = TILE_SCALE * 1.0
	var col := CollisionShape3D.new()
	col.shape = forma
	col.position.y = forma.height * 0.5
	fis.add_child(col)
	casa_raiz.add_child(fis)
	_criar_ponto_descanso_casa(casa_raiz)


## Cria a área de interação para dormir na casa e avançar para o próximo dia.
func _criar_ponto_descanso_casa(casa_raiz: Node3D) -> void:
	_area_descanso_casa = Area3D.new()
	_area_descanso_casa.name = "AreaDescansoCasa"
	var col := CollisionShape3D.new()
	var forma := CylinderShape3D.new()
	forma.radius = 3.5
	forma.height = 4.0
	col.shape = forma
	col.position.y = 2.0
	_area_descanso_casa.add_child(col)
	_area_descanso_casa.body_entered.connect(_ao_entrar_area_descanso_casa)
	_area_descanso_casa.body_exited.connect(_ao_sair_area_descanso_casa)
	casa_raiz.add_child(_area_descanso_casa)

	_hint_descanso_casa = Label3D.new()
	_hint_descanso_casa.name = "HintDescansoCasa"
	_hint_descanso_casa.text = "(E) Deitar para amanhecer"
	_hint_descanso_casa.font_size = 42
	_hint_descanso_casa.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_hint_descanso_casa.modulate = Color(0.82, 0.87, 1.0)
	_hint_descanso_casa.position = Vector3(0.0, 2.0, 0.0)
	_hint_descanso_casa.visible = false
	casa_raiz.add_child(_hint_descanso_casa)


## Callback quando o jogador entra na área da cama da casa.
func _ao_entrar_area_descanso_casa(body: Node3D) -> void:
	if not (body is CharacterBody3D):
		return
	_jogador_perto_descanso = true
	var jogador := get_node_or_null("Player")
	if jogador != null and jogador.has_method("_ao_entrar_ponto_descanso"):
		jogador._ao_entrar_ponto_descanso(self)
	_atualizar_hint_descanso_casa()


## Callback quando o jogador sai da área da cama da casa.
func _ao_sair_area_descanso_casa(body: Node3D) -> void:
	if not (body is CharacterBody3D):
		return
	_jogador_perto_descanso = false
	var jogador := get_node_or_null("Player")
	if jogador != null and jogador.has_method("_ao_sair_ponto_descanso"):
		jogador._ao_sair_ponto_descanso()
	_atualizar_hint_descanso_casa()


## Atualiza visibilidade da dica de descanso conforme distância e período.
func _atualizar_hint_descanso_casa() -> void:
	if _hint_descanso_casa == null:
		return
	_hint_descanso_casa.visible = _jogador_perto_descanso and not _periodo_eh_dia


## Instancia a Colmeia no tile (0, 0) e conecta seus sinais de proximidade ao Player
func _criar_colmeia() -> void:
	_criar_colmeia_em_coord(Vector2i(0, 0), "colmeia_principal", "comum")


## Cria uma colmeia em uma coordenada axial específica com id e raridade definidos.
func _criar_colmeia_em_coord(coord: Vector2i, id_colmeia: String, raridade: String) -> Node3D:
	if _colmeia_cena_script == null:
		push_warning("mundo.gd: script colmeia.gd não carregado — colmeia não será criada.")
		return null
	if _buscar_colmeia_por_id(id_colmeia) != null:
		return null
	var tile: HexTile = obter_tile(coord)
	if tile != null and tile.has_method("definir_tipo_visual"):
		tile.definir_tipo_visual(_obter_tipo_tile_colmeia_por_raridade(raridade))

	var colmeia := Node3D.new()
	colmeia.name = "Colmeia_%s" % id_colmeia
	colmeia.set_script(_colmeia_cena_script)
	colmeia.id_colmeia = id_colmeia
	colmeia.position = _axial_para_mundo(coord.x, coord.y)
	colmeia.position.y = 0.0
	if colmeia.has_method("configurar_raridade_colmeia"):
		colmeia.configurar_raridade_colmeia(raridade)
	add_child(colmeia)
	if colmeia.has_method("definir_periodo_dia"):
		colmeia.definir_periodo_dia(_periodo_eh_dia)

	var jogador := get_node_or_null("Player")
	if jogador != null:
		if colmeia.has_signal("jogador_entrou_colmeia") and jogador.has_method("_ao_entrar_colmeia_area"):
			colmeia.jogador_entrou_colmeia.connect(
				func() -> void: jogador._ao_entrar_colmeia_area(colmeia)
			)
		if colmeia.has_signal("jogador_saiu_colmeia") and jogador.has_method("_ao_sair_colmeia_area"):
			colmeia.jogador_saiu_colmeia.connect(jogador._ao_sair_colmeia_area)

	# Conecta sinal de mel coletado para verificar conquistas
	if colmeia.has_signal("mel_coletado"):
		colmeia.mel_coletado.connect(_ao_mel_coletado_conquista)
	return colmeia


## Recria colmeias dinâmicas já existentes no save em seus respectivos hexágonos.
func _recriar_colmeias_dinamicas_salvas() -> void:
	for chave in GerenciadorMundo.estado_colmeias.keys():
		if not (chave is String):
			continue
		var id_colmeia: String = chave
		if id_colmeia == "colmeia_principal":
			continue
		var coord: Vector2i = _extrair_coord_de_id_colmeia(id_colmeia)
		if coord == Vector2i(999999, 999999):
			continue
		var tile: HexTile = obter_tile(coord)
		if tile == null or not tile.desbloqueado:
			continue
		if _buscar_colmeia_por_id(id_colmeia) != null:
			continue
		var dados_colmeia: Dictionary = GerenciadorMundo.carregar_estado_colmeia(id_colmeia)
		var raridade: String = str(dados_colmeia.get("raridade_colmeia", "comum"))
		_criar_colmeia_em_coord(coord, id_colmeia, raridade)


## Instancia um Node3D com o script NPC na frente da casa (tile 0, -1).
## Conecta os sinais de proximidade ao Player para permitir venda de mel.
func _criar_npc() -> void:
	if _npc_script == null:
		push_warning("mundo.gd: script npc.gd não carregado — NPC não será criado.")
		return

	var npc := Node3D.new()
	npc.name = "NPC"
	npc.set_script(_npc_script)
	npc.position = _axial_para_mundo(Q_MIN + 1, R_MIN)  # (0, -1) — na frente da casa
	npc.position.y = 0.0
	add_child(npc)
	_npc_comprador = npc as NPC

	var jogador := get_node_or_null("Player")
	if jogador != null:
		if npc.has_signal("jogador_entrou_npc") and jogador.has_method("_ao_entrar_npc_area"):
			npc.jogador_entrou_npc.connect(
				func() -> void: jogador._ao_entrar_npc_area(npc)
			)
		if npc.has_signal("jogador_saiu_npc") and jogador.has_method("_ao_sair_npc_area"):
			npc.jogador_saiu_npc.connect(jogador._ao_sair_npc_area)

		var inv: Node = jogador.get_node_or_null("Inventario")
		if inv != null and inv.has_signal("inventario_mudou") and npc.has_method("_ao_inventario_mudou"):
			inv.inventario_mudou.connect(npc._ao_inventario_mudou)
	if _npc_comprador != null and is_instance_valid(_npc_comprador):
		_npc_comprador.definir_disponibilidade_no_periodo(_periodo_eh_dia)


# --- COMPRA DE HEX ---

## Chamado quando um tile externo é comprado com sucesso.
## Reconstrói navmesh/piso e tenta spawnar colmeia dinâmica no novo hex.
func _ao_tile_comprado(tile: HexTile, _custo: int) -> void:
	_reconstruir_navmesh()
	_criar_piso()
	_tentar_spawn_colmeia_em_compra(tile)


## Tenta spawnar uma colmeia ao comprar um hexágono, respeitando a chance fixa de 25%.
func _tentar_spawn_colmeia_em_compra(tile: HexTile) -> void:
	if tile == null or not tile.desbloqueado:
		return
	if _rng_eventos.randf() > CHANCE_SPAWN_COLMEIA_EM_COMPRA:
		return
	var id_colmeia: String = _obter_id_colmeia_para_coord(tile.coordenada)
	if _buscar_colmeia_por_id(id_colmeia) != null:
		return
	var raridade: String = _sortear_raridade_colmeia(tile.coordenada)
	_criar_colmeia_em_coord(tile.coordenada, id_colmeia, raridade)


## Sorteia a raridade da colmeia com distribuição percentual que varia por distância.
## No centro: comum predomina (65%). Na borda: comum cai e as demais sobem.
func _sortear_raridade_colmeia(coord: Vector2i) -> String:
	if RARIDADES_COLMEIA_SORTEIO.is_empty():
		return "comum"
	if RARIDADES_COLMEIA_SORTEIO.size() != DISTRIBUICAO_RARIDADE_CENTRO.size():
		return "comum"
	if RARIDADES_COLMEIA_SORTEIO.size() != DISTRIBUICAO_RARIDADE_BORDA.size():
		return "comum"

	var fator_distancia: float = _obter_fator_distancia_spawn(coord)
	var distribuicao: Array[float] = []
	for i in RARIDADES_COLMEIA_SORTEIO.size():
		var perc_centro: float = maxf(DISTRIBUICAO_RARIDADE_CENTRO[i], 0.0)
		var perc_borda: float = maxf(DISTRIBUICAO_RARIDADE_BORDA[i], 0.0)
		distribuicao.append(lerpf(perc_centro, perc_borda, fator_distancia))

	var soma_distribuicao: float = 0.0
	for percentual in distribuicao:
		soma_distribuicao += maxf(percentual, 0.0)
	if soma_distribuicao <= 0.0:
		return "comum"

	# Normaliza para garantir 100% efetivo mesmo com float/interpolação.
	var fator_normalizacao: float = 100.0 / soma_distribuicao
	var alvo: float = _rng_eventos.randf_range(0.0, 100.0)
	var acumulado: float = 0.0
	for i in RARIDADES_COLMEIA_SORTEIO.size():
		acumulado += maxf(distribuicao[i], 0.0) * fator_normalizacao
		if alvo <= acumulado:
			return RARIDADES_COLMEIA_SORTEIO[i]
	return RARIDADES_COLMEIA_SORTEIO[0]


## Retorna um fator [0..1] da distância ao spawn para ajustar chance de raridade.
func _obter_fator_distancia_spawn(coord: Vector2i) -> float:
	var dist: int = _hex_dist(coord, Vector2i(0, 0))
	var dist_max: float = maxf(float(raio_mundo_externo), 1.0)
	return clampf(float(dist) / dist_max, 0.0, 1.0)


## Retorna o ID canônico da colmeia para uma coordenada axial.
func _obter_id_colmeia_para_coord(coord: Vector2i) -> String:
	return "colmeia_%d_%d" % [coord.x, coord.y]


## Retorna o tipo visual de tile da colmeia com base na raridade.
func _obter_tipo_tile_colmeia_por_raridade(raridade: String) -> String:
	var raridade_normalizada: String = raridade.strip_edges().to_lower()
	if raridade_normalizada == "lendaria":
		return TIPO_TILE_COLMEIA_LENDARIA
	if raridade_normalizada == "epica":
		return TIPO_TILE_COLMEIA_EPICA
	if raridade_normalizada == "rara":
		return TIPO_TILE_COLMEIA_RARA
	return TIPO_TILE_COLMEIA_NORMAL


## Extrai coordenada axial de um id no formato colmeia_q_r.
func _extrair_coord_de_id_colmeia(id_colmeia: String) -> Vector2i:
	var partes: PackedStringArray = id_colmeia.split("_")
	if partes.size() != 3 or partes[0] != "colmeia":
		return Vector2i(999999, 999999)
	if not partes[1].is_valid_int() or not partes[2].is_valid_int():
		return Vector2i(999999, 999999)
	return Vector2i(int(partes[1]), int(partes[2]))


## Busca colmeia existente no mundo pelo id lógico.
func _buscar_colmeia_por_id(id_colmeia: String) -> Node3D:
	for no_colmeia in get_tree().get_nodes_in_group("colmeia"):
		if not (no_colmeia is Node3D):
			continue
		if String(no_colmeia.id_colmeia) == id_colmeia:
			return no_colmeia as Node3D
	return null


# --- UI ---

## Cria o CanvasLayer de UI com contador de moedas/mel
func _setup_ui() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "UILayer"

	if ResourceLoader.exists("res://scenes/ui_mel.tscn"):
		var ui_mel_cena: PackedScene = load("res://scenes/ui_mel.tscn")
		if ui_mel_cena != null:
			canvas.add_child(ui_mel_cena.instantiate())
	else:
		push_warning("mundo.gd: ui_mel.tscn não encontrada.")

	# Painel de aviso para ir dormir no estilo "placa de madeira" (invisível por padrão)
	var raiz_aviso := Control.new()
	raiz_aviso.name = "RaizAvisoDormir"
	raiz_aviso.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	raiz_aviso.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(raiz_aviso)

	_container_aviso_dormir = CenterContainer.new()
	_container_aviso_dormir.name = "ContainerAvisoDormir"
	_container_aviso_dormir.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_container_aviso_dormir.anchor_left = 0.0
	_container_aviso_dormir.anchor_right = 1.0
	_container_aviso_dormir.anchor_top = 0.0
	_container_aviso_dormir.anchor_bottom = 0.0
	_container_aviso_dormir.offset_top = 50.0
	_container_aviso_dormir.offset_bottom = 160.0
	_container_aviso_dormir.offset_left = 0.0
	_container_aviso_dormir.offset_right = 0.0
	_container_aviso_dormir.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_container_aviso_dormir.visible = false
	raiz_aviso.add_child(_container_aviso_dormir)

	var painel_aviso := PanelContainer.new()
	var estilo_aviso := StyleBoxFlat.new()
	estilo_aviso.bg_color = Color(0.91, 0.87, 0.79, 0.96)
	estilo_aviso.border_color = Color(0.52, 0.46, 0.38, 1.0)
	estilo_aviso.border_width_top = 3
	estilo_aviso.border_width_right = 3
	estilo_aviso.border_width_bottom = 6
	estilo_aviso.border_width_left = 3
	estilo_aviso.corner_radius_top_left = 14
	estilo_aviso.corner_radius_top_right = 14
	estilo_aviso.corner_radius_bottom_right = 14
	estilo_aviso.corner_radius_bottom_left = 14
	estilo_aviso.shadow_color = Color(0.0, 0.0, 0.0, 0.22)
	estilo_aviso.shadow_size = 3
	estilo_aviso.content_margin_top = 20
	estilo_aviso.content_margin_bottom = 20
	estilo_aviso.content_margin_left = 36
	estilo_aviso.content_margin_right = 36
	painel_aviso.add_theme_stylebox_override("panel", estilo_aviso)
	painel_aviso.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_container_aviso_dormir.add_child(painel_aviso)

	_label_aviso_dormir = Label.new()
	_label_aviso_dormir.text = "Hora de dormir! Va ate a casa para descansar."
	_label_aviso_dormir.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label_aviso_dormir.add_theme_font_size_override("font_size", 28)
	_label_aviso_dormir.add_theme_color_override("font_color", Color(0.47, 0.33, 0.05))
	_label_aviso_dormir.add_theme_constant_override("outline_size", 2)
	_label_aviso_dormir.add_theme_color_override("font_outline_color", Color(1.0, 0.96, 0.88))
	painel_aviso.add_child(_label_aviso_dormir)

	# Popup de conquista em CanvasLayer próprio acima de todas as UIs (layer 30)
	var canvas_conquista := CanvasLayer.new()
	canvas_conquista.name = "CanvasConquista"
	canvas_conquista.layer = 30
	add_child(canvas_conquista)

	var raiz_conquista := Control.new()
	raiz_conquista.name = "RaizConquista"
	raiz_conquista.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	raiz_conquista.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas_conquista.add_child(raiz_conquista)

	_container_conquista = CenterContainer.new()
	_container_conquista.name = "ContainerConquista"
	_container_conquista.anchor_left = 0.0
	_container_conquista.anchor_right = 1.0
	_container_conquista.anchor_top = 0.0
	_container_conquista.anchor_bottom = 0.0
	_container_conquista.offset_top = 50.0
	_container_conquista.offset_bottom = 200.0
	_container_conquista.offset_left = 0.0
	_container_conquista.offset_right = 0.0
	_container_conquista.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_container_conquista.visible = false
	raiz_conquista.add_child(_container_conquista)

	var painel_conquista := PanelContainer.new()
	var estilo_conquista := StyleBoxFlat.new()
	estilo_conquista.bg_color = Color(0.91, 0.87, 0.79, 0.96)
	estilo_conquista.border_color = Color(0.52, 0.46, 0.38, 1.0)
	estilo_conquista.border_width_top = 3
	estilo_conquista.border_width_right = 3
	estilo_conquista.border_width_bottom = 6
	estilo_conquista.border_width_left = 3
	estilo_conquista.corner_radius_top_left = 14
	estilo_conquista.corner_radius_top_right = 14
	estilo_conquista.corner_radius_bottom_right = 14
	estilo_conquista.corner_radius_bottom_left = 14
	estilo_conquista.shadow_color = Color(0.0, 0.0, 0.0, 0.22)
	estilo_conquista.shadow_size = 3
	estilo_conquista.content_margin_top = 22
	estilo_conquista.content_margin_bottom = 22
	estilo_conquista.content_margin_left = 36
	estilo_conquista.content_margin_right = 36
	painel_conquista.add_theme_stylebox_override("panel", estilo_conquista)
	painel_conquista.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_container_conquista.add_child(painel_conquista)

	var coluna_conquista := VBoxContainer.new()
	coluna_conquista.add_theme_constant_override("separation", 10)
	coluna_conquista.alignment = BoxContainer.ALIGNMENT_CENTER
	painel_conquista.add_child(coluna_conquista)

	var label_conquista_header := Label.new()
	label_conquista_header.text = "Conquista desbloqueada!"
	label_conquista_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label_conquista_header.add_theme_font_size_override("font_size", 20)
	label_conquista_header.add_theme_color_override("font_color", Color(0.55, 0.45, 0.25))
	coluna_conquista.add_child(label_conquista_header)

	_label_conquista_titulo = Label.new()
	_label_conquista_titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label_conquista_titulo.add_theme_font_size_override("font_size", 32)
	_label_conquista_titulo.add_theme_color_override("font_color", Color(0.47, 0.33, 0.05))
	_label_conquista_titulo.add_theme_constant_override("outline_size", 2)
	_label_conquista_titulo.add_theme_color_override("font_outline_color", Color(1.0, 0.96, 0.88))
	coluna_conquista.add_child(_label_conquista_titulo)

	_label_conquista_descricao = Label.new()
	_label_conquista_descricao.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label_conquista_descricao.add_theme_font_size_override("font_size", 22)
	_label_conquista_descricao.add_theme_color_override("font_color", Color(0.55, 0.45, 0.25))
	coluna_conquista.add_child(_label_conquista_descricao)

	add_child(canvas)


# --- MENU DE PAUSA ---

## Cria o menu de pausa (oculto por padrão) com botões Continuar e Reiniciar
func _criar_menu_pausa() -> void:
	_menu_pausa = CanvasLayer.new()
	_menu_pausa.name = "MenuPausa"
	_menu_pausa.layer = 10  # Acima de tudo
	_menu_pausa.visible = false
	add_child(_menu_pausa)

	# Raiz em Control para garantir layout por âncoras relativo à viewport inteira
	var raiz_ui := Control.new()
	raiz_ui.name = "RaizMenuPausa"
	raiz_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	raiz_ui.mouse_filter = Control.MOUSE_FILTER_STOP  # Bloqueia input no jogo ao fundo
	_menu_pausa.add_child(raiz_ui)

	# Fundo semitransparente que escurece o jogo
	var fundo := ColorRect.new()
	fundo.name = "Fundo"
	fundo.color = Color(0.0, 0.0, 0.0, 0.6)
	fundo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fundo.mouse_filter = Control.MOUSE_FILTER_STOP  # Bloqueia cliques no jogo
	raiz_ui.add_child(fundo)

	# Centraliza o menu na tela independentemente da resolução
	var centro := CenterContainer.new()
	centro.name = "CentroMenu"
	centro.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centro.mouse_filter = Control.MOUSE_FILTER_IGNORE
	raiz_ui.add_child(centro)

	# Painel central no estilo da UI de referência (madeira clara com borda)
	var painel := PanelContainer.new()
	painel.name = "PainelMenuPausa"
	painel.custom_minimum_size = Vector2(560.0, 420.0)
	painel.add_theme_stylebox_override("panel", _criar_stylebox_painel_menu_pausa())
	painel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	painel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	centro.add_child(painel)
	_painel_menu_principal = painel

	var centro_painel := CenterContainer.new()
	centro_painel.name = "CentroConteudoMenu"
	centro_painel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centro_painel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	painel.add_child(centro_painel)

	# Container vertical para os botões
	var container := VBoxContainer.new()
	container.name = "ContainerMenu"
	container.alignment = BoxContainer.ALIGNMENT_CENTER
	container.add_theme_constant_override("separation", 16)
	container.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	container.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	centro_painel.add_child(container)

	# Título
	var titulo := Label.new()
	titulo.text = "MENU"
	titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	titulo.add_theme_font_size_override("font_size", 44)
	titulo.add_theme_color_override("font_color", Color(0.50, 0.34, 0.0))
	titulo.add_theme_constant_override("outline_size", 2)
	titulo.add_theme_color_override("font_outline_color", Color(1.0, 0.97, 0.88))
	container.add_child(titulo)

	# Botão Continuar
	var btn_continuar := Button.new()
	btn_continuar.name = "BtnContinuar"
	btn_continuar.text = "Continuar"
	btn_continuar.custom_minimum_size = Vector2(320, 54)
	_aplicar_estilo_botao_menu_pausa(btn_continuar, "primario")
	btn_continuar.pressed.connect(_fechar_menu_pausa)
	container.add_child(btn_continuar)

	# Botão Reiniciar
	var btn_reiniciar := Button.new()
	btn_reiniciar.name = "BtnReiniciar"
	btn_reiniciar.text = "Reiniciar Mapa"
	btn_reiniciar.custom_minimum_size = Vector2(320, 54)
	_aplicar_estilo_botao_menu_pausa(btn_reiniciar, "secundario")
	btn_reiniciar.pressed.connect(_reiniciar_jogo)
	container.add_child(btn_reiniciar)

	# Botão Licenças
	var btn_licencas := Button.new()
	btn_licencas.name = "BtnLicencas"
	btn_licencas.text = "Licencas"
	btn_licencas.custom_minimum_size = Vector2(320, 54)
	_aplicar_estilo_botao_menu_pausa(btn_licencas, "secundario")
	btn_licencas.pressed.connect(_abrir_licencas_menu_pausa)
	container.add_child(btn_licencas)

	# Checkbox para som das abelhas
	var check_som_abelhas := CheckBox.new()
	check_som_abelhas.name = "CheckSomAbelhas"
	check_som_abelhas.text = "  Som das abelhas"
	check_som_abelhas.button_pressed = GerenciadorMundo.som_abelhas_ativo
	check_som_abelhas.add_theme_font_size_override("font_size", 22)
	check_som_abelhas.add_theme_color_override("font_color", Color(0.47, 0.33, 0.05))
	check_som_abelhas.add_theme_color_override("font_hover_color", Color(0.47, 0.33, 0.05))
	check_som_abelhas.add_theme_color_override("font_pressed_color", Color(0.47, 0.33, 0.05))
	check_som_abelhas.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	check_som_abelhas.toggled.connect(_ao_alternar_som_abelhas)
	container.add_child(check_som_abelhas)

	# Botão Sair
	var btn_sair := Button.new()
	btn_sair.name = "BtnSair"
	btn_sair.text = "Sair"
	btn_sair.custom_minimum_size = Vector2(320, 54)
	_aplicar_estilo_botao_menu_pausa(btn_sair, "perigoso")
	btn_sair.pressed.connect(_sair_jogo)
	container.add_child(btn_sair)

	_criar_painel_licencas_menu_pausa(centro)


## Cria o painel de licenças do menu ESC no mesmo estilo do painel principal.
func _criar_painel_licencas_menu_pausa(centro: CenterContainer) -> void:
	_painel_menu_licencas = PanelContainer.new()
	_painel_menu_licencas.name = "PainelLicencas"
	_painel_menu_licencas.custom_minimum_size = Vector2(760.0, 500.0)
	_painel_menu_licencas.add_theme_stylebox_override("panel", _criar_stylebox_painel_menu_pausa())
	_painel_menu_licencas.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_painel_menu_licencas.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_painel_menu_licencas.visible = false
	centro.add_child(_painel_menu_licencas)

	var conteudo := VBoxContainer.new()
	conteudo.name = "ConteudoLicencas"
	conteudo.add_theme_constant_override("separation", 16)
	conteudo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	conteudo.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_painel_menu_licencas.add_child(conteudo)

	var titulo := Label.new()
	titulo.text = "LICENCAS"
	titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	titulo.add_theme_font_size_override("font_size", 40)
	titulo.add_theme_color_override("font_color", Color(0.50, 0.34, 0.0))
	titulo.add_theme_constant_override("outline_size", 2)
	titulo.add_theme_color_override("font_outline_color", Color(1.0, 0.97, 0.88))
	conteudo.add_child(titulo)

	var scroll := ScrollContainer.new()
	scroll.name = "ScrollLicencas"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(680.0, 320.0)
	scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	scroll.focus_mode = Control.FOCUS_ALL
	conteudo.add_child(scroll)

	var texto := RichTextLabel.new()
	texto.name = "TextoLicencas"
	texto.bbcode_enabled = false
	texto.fit_content = true
	texto.scroll_active = false
	texto.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	texto.add_theme_font_size_override("normal_font_size", 18)
	texto.add_theme_color_override("default_color", Color(0.33, 0.22, 0.0))
	texto.text = TEXTO_LICENCAS_MENU
	texto.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texto.size_flags_vertical = Control.SIZE_FILL
	texto.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll.add_child(texto)

	var btn_voltar := Button.new()
	btn_voltar.name = "BtnVoltarLicencas"
	btn_voltar.text = "Voltar"
	btn_voltar.custom_minimum_size = Vector2(280.0, 52.0)
	btn_voltar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_aplicar_estilo_botao_menu_pausa(btn_voltar, "secundario")
	btn_voltar.pressed.connect(_fechar_licencas_menu_pausa)
	conteudo.add_child(btn_voltar)


## Alterna a visibilidade do menu de pausa e pausa/despausa o jogo
func _alternar_menu_pausa() -> void:
	if _menu_pausa == null:
		return
	var abrindo := not _menu_pausa.visible
	_menu_pausa.visible = abrindo
	if abrindo:
		_fechar_licencas_menu_pausa()
	# Pausa/despausa toda a simulação enquanto o menu está aberto
	get_tree().paused = abrindo


## Fecha o menu aberto com ESC e retorna true quando algo foi fechado.
func _fechar_menu_aberto_por_escape() -> bool:
	if _painel_licencas_esta_aberto():
		_fechar_licencas_menu_pausa()
		return true
	if _menu_pausa != null and _menu_pausa.visible:
		_fechar_menu_pausa()
		return true

	for colmeia in get_tree().get_nodes_in_group("colmeia"):
		if colmeia.has_method("fechar_interface_colmeia_por_atalho"):
			if bool(colmeia.fechar_interface_colmeia_por_atalho()):
				return true

	for npc in get_tree().get_nodes_in_group("npc"):
		if npc.has_method("fechar_interface_venda_por_atalho"):
			if bool(npc.fechar_interface_venda_por_atalho()):
				return true
	return false


## Fecha o menu de pausa e retoma o jogo
func _fechar_menu_pausa() -> void:
	if _menu_pausa != null:
		_menu_pausa.visible = false
	_fechar_licencas_menu_pausa()
	get_tree().paused = false


## Callback do checkbox de som das abelhas; atualiza o flag global e salva.
func _ao_alternar_som_abelhas(ativo: bool) -> void:
	GerenciadorMundo.som_abelhas_ativo = ativo
	GerenciadorMundo.salvar()


## Abre o painel de licenças e oculta o painel principal do menu de pausa.
func _abrir_licencas_menu_pausa() -> void:
	if _painel_menu_principal != null:
		_painel_menu_principal.visible = false
	if _painel_menu_licencas != null:
		_painel_menu_licencas.visible = true


## Fecha o painel de licenças e retorna ao painel principal do menu de pausa.
func _fechar_licencas_menu_pausa() -> void:
	if _painel_menu_licencas != null:
		_painel_menu_licencas.visible = false
	if _painel_menu_principal != null:
		_painel_menu_principal.visible = true


## Retorna true quando o painel de licenças do menu ESC está aberto.
func _painel_licencas_esta_aberto() -> bool:
	return _painel_menu_licencas != null and _painel_menu_licencas.visible


## Encerra o jogo a partir do menu de pausa.
func _sair_jogo() -> void:
	_salvar_posicao_jogador()
	_salvar_estado_ciclo_dia_noite()
	GerenciadorMundo.salvar()
	get_tree().paused = false
	get_tree().quit()


## Reseta todo o save e recarrega a cena do zero
func _reiniciar_jogo() -> void:
	# Reseta os dados globais
	GerenciadorMundo.moedas = 100
	GerenciadorMundo.total_mel_coletado = 0
	GerenciadorMundo.hexagonos_desbloqueados = []
	GerenciadorMundo.estado_colmeias = {}
	GerenciadorMundo.dia_atual = 1
	GerenciadorMundo.tempo_ciclo_dia_noite = duracao_ciclo_dia_noite_segundos / 24.0
	GerenciadorMundo.periodo_eh_dia = true
	GerenciadorMundo.posicao_jogador = {}
	GerenciadorMundo.conquistas = {}
	GerenciadorMundo.som_abelhas_ativo = true
	GerenciadorMundo.inventario_jogador = []

	# Apaga o save do disco
	if FileAccess.file_exists(GerenciadorMundo.CAMINHO_SAVE):
		DirAccess.remove_absolute(GerenciadorMundo.CAMINHO_SAVE)

	# Despausa antes de recarregar
	get_tree().paused = false
	get_tree().reload_current_scene()


## Cria o estilo do painel central de pausa no visual "placa de madeira".
func _criar_stylebox_painel_menu_pausa() -> StyleBoxFlat:
	var estilo := StyleBoxFlat.new()
	estilo.bg_color = Color(0.91, 0.87, 0.79, 0.96)
	estilo.border_color = Color(0.52, 0.46, 0.38, 1.0)
	estilo.border_width_top = 4
	estilo.border_width_right = 4
	estilo.border_width_bottom = 8
	estilo.border_width_left = 4
	estilo.corner_radius_top_left = 18
	estilo.corner_radius_top_right = 18
	estilo.corner_radius_bottom_right = 18
	estilo.corner_radius_bottom_left = 18
	estilo.shadow_color = Color(0.0, 0.0, 0.0, 0.22)
	estilo.shadow_size = 4
	estilo.content_margin_top = 30
	estilo.content_margin_bottom = 30
	estilo.content_margin_left = 34
	estilo.content_margin_right = 34
	return estilo


## Aplica estilos dos botões do menu de pausa baseados no tipo visual.
func _aplicar_estilo_botao_menu_pausa(botao: Button, tipo: String) -> void:
	botao.add_theme_font_size_override("font_size", 24)
	botao.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	botao.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0))
	botao.add_theme_color_override("font_pressed_color", Color(1.0, 1.0, 1.0))

	var normal := StyleBoxFlat.new()
	var hover := StyleBoxFlat.new()
	var pressed := StyleBoxFlat.new()

	match tipo:
		"secundario":
			normal.bg_color = Color(0.97, 0.95, 0.89)
			normal.border_color = Color(0.50, 0.34, 0.0)
			hover.bg_color = Color(1.0, 0.98, 0.92)
			hover.border_color = Color(0.50, 0.34, 0.0)
			pressed.bg_color = Color(0.92, 0.88, 0.80)
			pressed.border_color = Color(0.40, 0.28, 0.0)
			botao.add_theme_color_override("font_color", Color(0.50, 0.34, 0.0))
			botao.add_theme_color_override("font_hover_color", Color(0.50, 0.34, 0.0))
			botao.add_theme_color_override("font_pressed_color", Color(0.40, 0.28, 0.0))
		"perigoso":
			normal.bg_color = Color(0.73, 0.10, 0.10)
			normal.border_color = Color(0.58, 0.00, 0.04)
			hover.bg_color = Color(0.82, 0.16, 0.16)
			hover.border_color = Color(0.58, 0.00, 0.04)
			pressed.bg_color = Color(0.60, 0.06, 0.06)
			pressed.border_color = Color(0.44, 0.00, 0.02)
		_:
			normal.bg_color = Color(0.99, 0.70, 0.09)
			normal.border_color = Color(0.50, 0.34, 0.0)
			hover.bg_color = Color(1.0, 0.77, 0.18)
			hover.border_color = Color(0.50, 0.34, 0.0)
			pressed.bg_color = Color(0.93, 0.63, 0.06)
			pressed.border_color = Color(0.40, 0.28, 0.0)

	for estilo in [normal, hover, pressed]:
		estilo.border_width_top = 2
		estilo.border_width_right = 2
		estilo.border_width_bottom = 6
		estilo.border_width_left = 2
		estilo.corner_radius_top_left = 10
		estilo.corner_radius_top_right = 10
		estilo.corner_radius_bottom_right = 10
		estilo.corner_radius_bottom_left = 10
		estilo.content_margin_left = 18
		estilo.content_margin_right = 18

	botao.add_theme_stylebox_override("normal", normal)
	botao.add_theme_stylebox_override("hover", hover)
	botao.add_theme_stylebox_override("pressed", pressed)
