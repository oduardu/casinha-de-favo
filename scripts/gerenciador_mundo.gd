class_name GerenciadorMundo

# Classe estática de dados globais — acesse via GerenciadorMundo.moedas etc.
# Não precisa ser AutoLoad; o class_name torna acessível em qualquer script.


# --- DADOS DO JOGADOR ---

## Saldo atual de moedas do jogador
static var moedas: int = 100

## Total histórico de mel coletado — nunca diminui, é estatística do jogo
static var total_mel_coletado: int = 0

## Lista de dicionários {"q": int, "r": int} com coordenadas axiais dos hexágonos comprados
static var hexagonos_desbloqueados: Array = []

## Estado individual de cada colmeia; chave = id_colmeia, valor = dict com progresso e abelha
## Ex: { "colmeia_principal": { "progresso_mel": 0.5, "estado_abelha": 0, ... } }
static var estado_colmeias: Dictionary = {}

## Dia atual do ciclo de mundo (inicia no dia 1)
static var dia_atual: int = 1

## Tempo acumulado dentro do ciclo dia/noite atual em segundos
static var tempo_ciclo_dia_noite: float = 0.0

## True quando o mundo está em período diurno; false para noturno
static var periodo_eh_dia: bool = true

## Posição do jogador no momento do último save (Vector3 serializado como dict)
static var posicao_jogador: Dictionary = {}

## Conquistas desbloqueadas pelo jogador; chave = id da conquista, valor = true
static var conquistas: Dictionary = {}

## True quando o som de zumbido das abelhas está ativado
static var som_abelhas_ativo: bool = true

## Estado do inventário do jogador; lista de {"id": String, "quantidade": int, "recurso": String}
static var inventario_jogador: Array = []


# --- CONSTANTES ---

## Caminho do arquivo de save no diretório do usuário
const CAMINHO_SAVE := "user://save_mundo.json"


# --- SAVE / LOAD ---

## Salva todos os dados em JSON no disco.
## Chamado automaticamente a cada evento importante (compra, coleta, fechar jogo).
static func salvar() -> void:
	var dados := {
		"moedas": moedas,
		"total_mel_coletado": total_mel_coletado,
		"hexagonos_desbloqueados": hexagonos_desbloqueados.duplicate(true),
		"estado_colmeias": estado_colmeias.duplicate(true),
		"dia_atual": dia_atual,
		"tempo_ciclo_dia_noite": tempo_ciclo_dia_noite,
		"periodo_eh_dia": periodo_eh_dia,
		"posicao_jogador": posicao_jogador,
		"conquistas": conquistas.duplicate(true),
		"som_abelhas_ativo": som_abelhas_ativo,
		"inventario_jogador": inventario_jogador.duplicate(true),
	}
	var arquivo := FileAccess.open(CAMINHO_SAVE, FileAccess.WRITE)
	if arquivo == null:
		push_error("GerenciadorMundo.salvar: não foi possível abrir '%s' para escrita." % CAMINHO_SAVE)
		return
	arquivo.store_string(JSON.stringify(dados, "\t"))
	arquivo.close()


## Carrega o save do disco com fallback seguro para campos ausentes (compatibilidade retroativa).
## Chamado por mundo.gd no início do _ready().
static func carregar() -> void:
	if not FileAccess.file_exists(CAMINHO_SAVE):
		return  # Primeira execução — sem save ainda

	var arquivo := FileAccess.open(CAMINHO_SAVE, FileAccess.READ)
	if arquivo == null:
		push_warning("GerenciadorMundo.carregar: não foi possível abrir '%s'." % CAMINHO_SAVE)
		return

	var conteudo := arquivo.get_as_text()
	arquivo.close()

	var resultado: Variant = JSON.parse_string(conteudo)
	if resultado == null or not resultado is Dictionary:
		push_warning("GerenciadorMundo.carregar: JSON inválido — usando valores padrão.")
		return

	# Moedas — JSON pode retornar float, converte para int
	if resultado.has("moedas"):
		moedas = int(resultado["moedas"])

	# Total de mel coletado — campo novo; fallback = 0
	if resultado.has("total_mel_coletado"):
		total_mel_coletado = int(resultado["total_mel_coletado"])

	# Hexágonos desbloqueados
	if resultado.has("hexagonos_desbloqueados") and resultado["hexagonos_desbloqueados"] is Array:
		hexagonos_desbloqueados = resultado["hexagonos_desbloqueados"]

	# Estado das colmeias — campo novo; fallback = dict vazio
	if resultado.has("estado_colmeias") and resultado["estado_colmeias"] is Dictionary:
		estado_colmeias = resultado["estado_colmeias"]

	# Dia atual — fallback = 1
	if resultado.has("dia_atual"):
		dia_atual = maxi(int(resultado["dia_atual"]), 1)

	# Tempo do ciclo dia/noite — fallback = 0.0
	if resultado.has("tempo_ciclo_dia_noite"):
		tempo_ciclo_dia_noite = maxf(float(resultado["tempo_ciclo_dia_noite"]), 0.0)

	# Estado atual do período (dia/noite) — fallback = true
	if resultado.has("periodo_eh_dia"):
		periodo_eh_dia = bool(resultado["periodo_eh_dia"])

	# Posição do jogador — fallback = dict vazio (spawn padrão)
	if resultado.has("posicao_jogador") and resultado["posicao_jogador"] is Dictionary:
		posicao_jogador = resultado["posicao_jogador"]

	# Conquistas desbloqueadas — fallback = dict vazio
	if resultado.has("conquistas") and resultado["conquistas"] is Dictionary:
		conquistas = resultado["conquistas"]

	# Som das abelhas — fallback = true (ativado)
	if resultado.has("som_abelhas_ativo"):
		som_abelhas_ativo = bool(resultado["som_abelhas_ativo"])

	# Inventário do jogador — fallback = array vazio
	if resultado.has("inventario_jogador") and resultado["inventario_jogador"] is Array:
		inventario_jogador = resultado["inventario_jogador"]


# --- OPERAÇÕES DE MOEDAS ---

## Retorna true se o jogador tiver pelo menos 'valor' moedas disponíveis
static func tem_dinheiro(valor: int) -> bool:
	return moedas >= valor


## Subtrai 'valor' do saldo de moedas e salva imediatamente.
## Use tem_dinheiro() antes de chamar.
static func gastar(valor: int) -> void:
	moedas -= valor
	salvar()


## Adiciona 'valor' ao saldo de moedas e salva imediatamente
static func adicionar_moedas(valor: int) -> void:
	moedas += valor
	salvar()


# --- CONTROLE DE HEXÁGONOS ---

## Retorna true se a coordenada axial 'coord' já estiver na lista de desbloqueados
static func esta_desbloqueado(coord: Vector2i) -> bool:
	for entrada in hexagonos_desbloqueados:
		if entrada is Dictionary and entrada.get("q") == coord.x and entrada.get("r") == coord.y:
			return true
	return false


## Adiciona 'coord' à lista de hexágonos desbloqueados e salva.
static func registrar_desbloqueio(coord: Vector2i) -> void:
	if esta_desbloqueado(coord):
		return  # Evita duplicatas
	hexagonos_desbloqueados.append({"q": coord.x, "r": coord.y})
	salvar()


# --- CONTROLE DE COLMEIAS ---

## Salva o estado de uma colmeia específica e persiste no disco.
## 'id' é o id_colmeia da Colmeia; 'dados' contém progresso_mel, estado_abelha, etc.
static func salvar_estado_colmeia(id: String, dados: Dictionary) -> void:
	estado_colmeias[id] = dados
	salvar()


## Retorna o dicionário de estado salvo de uma colmeia, ou {} se não existir.
## A Colmeia usa o retorno em restaurar_estado() e para checar se há save.
static func carregar_estado_colmeia(id: String) -> Dictionary:
	if estado_colmeias.has(id):
		var val: Variant = estado_colmeias[id]
		if val is Dictionary:
			return val
	return {}
