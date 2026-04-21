class_name Abelha
extends Node3D

# Controla o ciclo de vida de uma abelha ligada a uma colmeia:
# orbita por fora, entra, produz mel, sai — em loop infinito.


# --- SINAIS ---

## Emitido ao fim de cada estadia dentro da colmeia.
## A Colmeia escuta esse sinal para incrementar o progresso de mel.
signal ciclo_mel_completo


# --- ESTADOS DA ABELHA ---

enum EstadoAbelha {
	VOANDO,   # Orbitando ao redor da colmeia
	ENTRANDO, # Animação de voo em direção à entrada (controlado por Tween)
	DENTRO,   # Invisível, dentro da colmeia, timer rodando
	SAINDO,   # Animação de saída (controlado por Tween)
}


# --- CONFIGURAÇÃO ---

## Segundos que a abelha fica orbitando antes de entrar na colmeia
@export var tempo_voando: float = 8.0

## Segundos que a abelha fica dentro produzindo mel
@export var tempo_dentro_colmeia: float = 5.0

## Raio da trajetória circular ao redor da colmeia em unidades de mundo
@export var raio_orbita: float = 0.6

## Duração em segundos de uma volta completa ao redor da colmeia
@export var velocidade_orbita: float = 3.0


# --- ESTADO INTERNO ---

## Estado atual da máquina de estados da abelha
var estado_atual: EstadoAbelha = EstadoAbelha.VOANDO

## Acumulador de tempo para o estado atual (VOANDO ou DENTRO)
var _tempo_acumulado: float = 0.0

## Ângulo atual na órbita circular (radianos, 0..TAU)
var _angulo_orbita: float = 0.0


# --- NÓS FILHOS ---

## CSGSphere3D que representa visualmente o corpo da abelha
var _corpo: CSGSphere3D = null

## Tween ativo durante as transições ENTRANDO e SAINDO
var _tween: Tween = null


# --- CICLO DE VIDA ---

func _ready() -> void:
	_criar_corpo()
	# Começa já na borda da órbita
	position = Vector3(raio_orbita, 0.9, 0.0)


# --- CRIAÇÃO VISUAL ---

## Cria a esfera amarela de ~0.15 unidades de diâmetro que representa a abelha
func _criar_corpo() -> void:
	_corpo = CSGSphere3D.new()
	_corpo.name = "CorpoAbelha"
	_corpo.radius = 0.075  # Diâmetro ≈ 0.15 unidades
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.96, 0.78, 0.26)  # Amarelo mel
	_corpo.material_override = mat
	add_child(_corpo)


# --- PROCESSAMENTO ---

## Atualiza a trajetória (VOANDO) ou o timer (DENTRO) a cada frame
func _process(delta: float) -> void:
	match estado_atual:
		EstadoAbelha.VOANDO:
			_atualizar_voando(delta)
		EstadoAbelha.DENTRO:
			_atualizar_dentro(delta)
		# ENTRANDO e SAINDO são gerenciados por Tween — nada a fazer aqui


# --- ESTADOS ---

## Move a abelha na órbita circular com leve oscilação vertical.
## TAU / velocidade_orbita = radianos por segundo para 1 volta completa.
func _atualizar_voando(delta: float) -> void:
	_angulo_orbita += (TAU / velocidade_orbita) * delta
	if _angulo_orbita > TAU:
		_angulo_orbita -= TAU

	# Trajetória circular; sin(angulo * 2.5) cria oscilação vertical suave
	position.x = cos(_angulo_orbita) * raio_orbita
	position.z = sin(_angulo_orbita) * raio_orbita
	position.y = 0.9 + sin(_angulo_orbita * 2.5) * 0.12

	_tempo_acumulado += delta
	if _tempo_acumulado >= tempo_voando:
		_tempo_acumulado = 0.0
		_entrar_colmeia()


## Conta o tempo passado dentro da colmeia e dispara o sinal ao fim
func _atualizar_dentro(delta: float) -> void:
	_tempo_acumulado += delta
	if _tempo_acumulado >= tempo_dentro_colmeia:
		_tempo_acumulado = 0.0
		ciclo_mel_completo.emit()
		_sair_colmeia()


## Inicia o tween de entrada: voa em direção ao centro/topo da colmeia e some
func _entrar_colmeia() -> void:
	estado_atual = EstadoAbelha.ENTRANDO
	if _tween:
		_tween.kill()
	_tween = create_tween()
	# Voa até o topo do corpo da colmeia (y=0.4 é aproximadamente o topo do CSGBox)
	_tween.tween_property(self, "position", Vector3(0.0, 0.4, 0.0), 0.8) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.tween_callback(func() -> void:
		visible = false
		estado_atual = EstadoAbelha.DENTRO
		_tempo_acumulado = 0.0
	)


## Inicia o tween de saída: aparece no topo da colmeia e voa até a órbita
func _sair_colmeia() -> void:
	estado_atual = EstadoAbelha.SAINDO
	visible = true
	position = Vector3(0.0, 0.4, 0.0)
	if _tween:
		_tween.kill()
	_tween = create_tween()
	# Sai em direção ao ponto atual da órbita para continuidade visual
	var pos_destino := Vector3(
		cos(_angulo_orbita) * raio_orbita,
		0.9,
		sin(_angulo_orbita) * raio_orbita
	)
	_tween.tween_property(self, "position", pos_destino, 0.6) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.tween_callback(func() -> void:
		estado_atual = EstadoAbelha.VOANDO
		_tempo_acumulado = 0.0
	)


# --- PERSISTÊNCIA ---

## Restaura o estado a partir de um dicionário salvo.
## Chamada pela Colmeia durante o carregamento do save.
func restaurar_estado(dados: Dictionary) -> void:
	var estado_salvo: int = dados.get("estado_abelha", 0)
	_tempo_acumulado = dados.get("tempo_acumulado_abelha", 0.0)
	_angulo_orbita = dados.get("angulo_orbita", 0.0)

	# Simplificação segura: qualquer estado não-VOANDO é restaurado como VOANDO
	# para evitar tweens incompletos ao reabrir o jogo
	if estado_salvo == EstadoAbelha.DENTRO:
		visible = false
		position = Vector3(0.0, 0.4, 0.0)
		estado_atual = EstadoAbelha.DENTRO
	else:
		visible = true
		estado_atual = EstadoAbelha.VOANDO
		position = Vector3(cos(_angulo_orbita) * raio_orbita, 0.9, sin(_angulo_orbita) * raio_orbita)


## Retorna o estado atual como dicionário para persistência no save
func obter_estado_para_salvar() -> Dictionary:
	return {
		"estado_abelha": estado_atual as int,
		"tempo_acumulado_abelha": _tempo_acumulado,
		"angulo_orbita": _angulo_orbita,
	}
