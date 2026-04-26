class_name Abelha
extends Node3D

# Controla o ciclo de vida de uma abelha ligada a uma colmeia:
# orbita por fora, entra, produz mel, sai — em loop infinito.
# Usa o modelo 3D da abelha (animal-bee.glb) com animação "dance".


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
@export var velocidade_orbita: float = 18.0

## Raio máximo permitido para o voo dentro do hexágono da colmeia
@export var raio_limite_hex: float = 2.35

## Escala aplicada ao modelo da abelha (o modelo original é grande)
@export var escala_modelo: float = 0.15

## Altura base de voo ao redor da colmeia (ajustada para colmeias mais altas)
@export var altura_voo_base: float = 1.55

## Altura do ponto de entrada/saída da colmeia (deve ser o mesmo para entrar e sair)
@export var altura_entrada_colmeia: float = 1.35

## Fator mínimo de velocidade angular no voo (varia a rapidez da trajetória por ciclo)
@export var fator_velocidade_voo_min: float = 0.82

## Fator máximo de velocidade angular no voo (varia a rapidez da trajetória por ciclo)
@export var fator_velocidade_voo_max: float = 1.18

## Probabilidade por segundo de entrar em micro-pairada durante o voo
@export var probabilidade_pairar_por_segundo: float = 0.16

## Duração mínima da micro-pairada em segundos
@export var duracao_pairar_min: float = 0.10

## Duração máxima da micro-pairada em segundos
@export var duracao_pairar_max: float = 0.28

## Fator mínimo de variação no tempo voando (ex.: 0.7 = 30% mais rápido)
@export var fator_aleatorio_voando_min: float = 0.7

## Fator máximo de variação no tempo voando (ex.: 1.4 = 40% mais lento)
@export var fator_aleatorio_voando_max: float = 1.4

## Fator mínimo de variação no tempo dentro da colmeia
@export var fator_aleatorio_dentro_min: float = 0.75

## Fator máximo de variação no tempo dentro da colmeia
@export var fator_aleatorio_dentro_max: float = 1.35


# --- ESTADO INTERNO ---

## Estado atual da máquina de estados da abelha
var estado_atual: EstadoAbelha = EstadoAbelha.VOANDO

## Acumulador de tempo para o estado atual (VOANDO ou DENTRO)
var _tempo_acumulado: float = 0.0

## Parâmetro contínuo da trajetória de voo (radianos, sem reset para evitar salto)
var _angulo_orbita: float = 0.0

## True quando a produção está ativa; false pausa toda a lógica de entrar/sair da colmeia
var _producao_ativa: bool = true

## True quando a colmeia pediu para esta abelha recolher e parar ao entrar
var _recolhimento_solicitado: bool = false

## Fase pseudo-aleatória usada para variar o voo de cada abelha
var _fase_voo: float = 0.0

## Gerador pseudo-aleatório individual desta abelha
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

## Duração efetiva do estado VOANDO para o ciclo atual
var _duracao_voando_atual: float = 0.0

## Duração efetiva do estado DENTRO para o ciclo atual
var _duracao_dentro_atual: float = 0.0

## Direção de voo suavizada para orientar a abelha sem "travar" em um ponto
var _direcao_voo_atual: Vector3 = Vector3.FORWARD

## Direção de voo do frame anterior para calcular inclinação em curva
var _direcao_voo_anterior: Vector3 = Vector3.FORWARD

## Fator de velocidade angular sorteado para o ciclo de voo atual
var _fator_velocidade_voo_atual: float = 1.0

## Tempo restante da micro-pairada atual
var _tempo_pairar_restante: float = 0.0


# --- NÓS FILHOS ---

## Node3D instanciado do modelo 3D da abelha (animal-bee.glb)
var _modelo: Node3D = null

## AnimationPlayer encontrado na hierarquia do modelo; toca "dance" em loop
var _anim: AnimationPlayer = null

## Tween ativo durante as transições ENTRANDO e SAINDO
var _tween: Tween = null


# --- CICLO DE VIDA ---

func _ready() -> void:
	_criar_modelo()
	_rng.randomize()
	_rng.seed = int(get_instance_id()) * 7919 + int(_rng.randi())
	_fase_voo = fposmod(float(get_instance_id()) * 0.6180339, TAU)
	_sortear_duracao_voando()
	_sortear_duracao_dentro()
	# Inicia cada abelha em um ponto diferente do próprio timer para quebrar sincronização.
	_tempo_acumulado = _rng.randf_range(0.0, _duracao_voando_atual)
	# Começa em posição de voo já variada ao redor da colmeia
	position = _calcular_posicao_voo(_angulo_orbita)
	_direcao_voo_atual = position.normalized()
	_direcao_voo_anterior = _direcao_voo_atual


# --- CRIAÇÃO VISUAL ---

## Instancia o modelo da abelha (animal-bee.glb), aplica escala e inicia a animação "dance"
func _criar_modelo() -> void:
	var cena_abelha: PackedScene = load("res://obj/kenney_bee/animal-bee.glb")
	if cena_abelha == null:
		push_warning("abelha.gd: modelo animal-bee.glb não encontrado.")
		return

	_modelo = cena_abelha.instantiate() as Node3D
	_modelo.name = "ModeloAbelha"
	# Ajusta escala e corrige o "frente" do modelo para alinhar com o look_at da órbita
	_modelo.scale = Vector3(escala_modelo, escala_modelo, escala_modelo)
	_modelo.rotation_degrees.y = 180.0
	add_child(_modelo)

	# Busca o AnimationPlayer e inicia a animação "dance" em loop
	call_deferred("_iniciar_animacao")


## Busca o AnimationPlayer na hierarquia e inicia "dance" em loop contínuo
func _iniciar_animacao() -> void:
	_anim = _encontrar_anim_player(self)
	if _anim == null:
		return
	var anim := _anim.get_animation("dance")
	if anim:
		anim.loop_mode = Animation.LOOP_LINEAR  # Força loop contínuo da animação
	_anim.play("dance")


## Busca recursivamente um AnimationPlayer em qualquer nível da hierarquia
func _encontrar_anim_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var resultado := _encontrar_anim_player(child)
		if resultado:
			return resultado
	return null


# --- PROCESSAMENTO ---

## Atualiza a trajetória (VOANDO) ou o timer (DENTRO) a cada frame
func _process(delta: float) -> void:
	if not _producao_ativa:
		return
	match estado_atual:
		EstadoAbelha.VOANDO:
			_atualizar_voando(delta)
		EstadoAbelha.DENTRO:
			_atualizar_dentro(delta)
		# ENTRANDO e SAINDO são gerenciados por Tween — nada a fazer aqui


# --- ESTADOS ---

## Move a abelha na órbita circular com leve oscilação vertical.
## TAU / velocidade_orbita = radianos por segundo para 1 volta completa.
## Orienta o modelo na direção do movimento.
func _atualizar_voando(delta: float) -> void:
	if _recolhimento_solicitado:
		_entrar_colmeia()
		return

	if _tempo_pairar_restante > 0.0:
		_tempo_pairar_restante = maxf(_tempo_pairar_restante - delta, 0.0)
	else:
		var chance_pairar: float = clampf(probabilidade_pairar_por_segundo * delta, 0.0, 1.0)
		if _rng.randf() < chance_pairar:
			_tempo_pairar_restante = _rng.randf_range(duracao_pairar_min, duracao_pairar_max)

	if _tempo_pairar_restante <= 0.0:
		_angulo_orbita += (TAU / velocidade_orbita) * _fator_velocidade_voo_atual * delta

	# Voo mais orgânico (não circular), limitado ao interior do hexágono da colmeia.
	var pos_anterior: Vector3 = position
	position = _calcular_posicao_voo(_angulo_orbita)

	# Orienta a abelha pela direção real de deslocamento com suavização.
	var tangente: Vector3 = position - pos_anterior
	if tangente.length_squared() > 0.000001:
		var dir_frame: Vector3 = tangente.normalized()
		_direcao_voo_atual = _direcao_voo_atual.slerp(dir_frame, minf(delta * 9.0, 1.0))
		var alvo: Vector3 = global_position + _direcao_voo_atual
		var base_alvo: Basis = Basis.looking_at(_direcao_voo_atual, Vector3.UP)
		basis = basis.slerp(base_alvo, minf(delta * 10.0, 1.0))
		_atualizar_postura_organica(tangente, delta)
		_direcao_voo_anterior = _direcao_voo_atual
	else:
		_atualizar_postura_organica(Vector3.ZERO, delta)

	_tempo_acumulado += delta
	if _tempo_acumulado >= _duracao_voando_atual:
		_tempo_acumulado = 0.0
		_entrar_colmeia()


## Conta o tempo passado dentro da colmeia e dispara o sinal ao fim
func _atualizar_dentro(delta: float) -> void:
	if _recolhimento_solicitado:
		return
	_tempo_acumulado += delta
	if _tempo_acumulado >= _duracao_dentro_atual:
		_tempo_acumulado = 0.0
		ciclo_mel_completo.emit()
		_sair_colmeia()


## Inicia o tween de entrada: voa em direção ao centro/topo da colmeia e some
func _entrar_colmeia() -> void:
	if estado_atual == EstadoAbelha.ENTRANDO or estado_atual == EstadoAbelha.DENTRO:
		return
	estado_atual = EstadoAbelha.ENTRANDO
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_sortear_duracao_dentro()
	# Voa até o ponto alto de entrada da colmeia para manter continuidade com o novo modelo.
	_tween.tween_property(self, "position", _obter_ponto_entrada_saida_colmeia(), 0.8) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.tween_callback(func() -> void:
		visible = false
		estado_atual = EstadoAbelha.DENTRO
		_tempo_acumulado = 0.0
		_aplicar_postura_neutra()
	)


## Inicia o tween de saída: aparece no topo da colmeia e voa até a órbita
func _sair_colmeia() -> void:
	estado_atual = EstadoAbelha.SAINDO
	visible = true
	position = _obter_ponto_entrada_saida_colmeia()
	if _tween:
		_tween.kill()
	_tween = create_tween()
	# Sai em direção ao ponto atual da trajetória de voo para continuidade visual
	var pos_destino := _calcular_posicao_voo(_angulo_orbita)
	_tween.tween_property(self, "position", pos_destino, 0.6) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.tween_callback(func() -> void:
		estado_atual = EstadoAbelha.VOANDO
		_tempo_acumulado = 0.0
		_sortear_duracao_voando()
		_direcao_voo_anterior = _direcao_voo_atual
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
		position = _obter_ponto_entrada_saida_colmeia()
		estado_atual = EstadoAbelha.DENTRO
	else:
		visible = true
		estado_atual = EstadoAbelha.VOANDO
		position = _calcular_posicao_voo(_angulo_orbita)


## Retorna o estado atual como dicionário para persistência no save
func obter_estado_para_salvar() -> Dictionary:
	return {
		"estado_abelha": estado_atual as int,
		"tempo_acumulado_abelha": _tempo_acumulado,
		"angulo_orbita": _angulo_orbita,
	}


# --- CONTROLE EXTERNO ---

## Define um ângulo inicial na órbita para distribuir múltiplas abelhas ao redor da colmeia.
func definir_angulo_inicial(angulo: float) -> void:
	_angulo_orbita = fposmod(angulo, TAU)
	if estado_atual == EstadoAbelha.VOANDO:
		position = _calcular_posicao_voo(_angulo_orbita)


## Ativa/desativa a produção desta abelha.
## Quando desativa, interrompe tweens e mantém a abelha visível fora da colmeia.
func definir_producao_ativa(ativa: bool) -> void:
	_producao_ativa = ativa
	if ativa:
		_recolhimento_solicitado = false
		if estado_atual == EstadoAbelha.DENTRO:
			visible = true
			estado_atual = EstadoAbelha.VOANDO
			position = _calcular_posicao_voo(_angulo_orbita)
			_tempo_acumulado = 0.0
			_sortear_duracao_voando()
			_aplicar_postura_neutra()
		return
	if _tween:
		_tween.kill()
	visible = false
	estado_atual = EstadoAbelha.DENTRO
	_tempo_acumulado = 0.0
	_aplicar_postura_neutra()


## Pede para a abelha recolher e permanecer dentro da colmeia para pausa de produção.
func solicitar_recolhimento_para_pausa() -> void:
	_recolhimento_solicitado = true
	if estado_atual == EstadoAbelha.VOANDO:
		_entrar_colmeia()


## Retorna true quando a abelha já está dentro da colmeia.
func esta_dentro_colmeia() -> bool:
	return estado_atual == EstadoAbelha.DENTRO


## Calcula uma posição de voo variada usando combinação de senos (Lissajous deformada)
## e mantém a abelha dentro do raio limite do hexágono da colmeia.
func _calcular_posicao_voo(param: float) -> Vector3:
	var escala: float = clampf(raio_orbita / 1.2, 0.75, 1.6)
	var x: float = (
		1.35 * sin(param * 1.17 + _fase_voo) +
		0.66 * sin(param * 2.41 + _fase_voo * 1.9) +
		0.30 * sin(param * 4.73 + _fase_voo * 0.6)
	) * escala
	var z: float = (
		1.28 * sin(param * 1.63 + _fase_voo * 0.7) +
		0.74 * sin(param * 2.87 + _fase_voo * 1.5) +
		0.22 * sin(param * 5.11 + _fase_voo * 2.2)
	) * escala
	var plano := Vector2(x, z)
	var limite: float = maxf(raio_limite_hex - 0.08, 0.2)
	if plano.length() > limite:
		plano = plano.normalized() * limite
	var y: float = altura_voo_base \
		+ sin(param * 2.35 + _fase_voo * 0.8) * 0.12 \
		+ sin(param * 4.90 + _fase_voo * 1.3) * 0.04
	return Vector3(plano.x, y, plano.y)


## Retorna o ponto local único de entrada/saída da colmeia para manter o ciclo consistente.
func _obter_ponto_entrada_saida_colmeia() -> Vector3:
	return Vector3(0.0, altura_entrada_colmeia, 0.0)


## Sorteia a duração do próximo trecho VOANDO usando fator aleatório individual.
func _sortear_duracao_voando() -> void:
	var fator_min: float = minf(fator_aleatorio_voando_min, fator_aleatorio_voando_max)
	var fator_max: float = maxf(fator_aleatorio_voando_min, fator_aleatorio_voando_max)
	var fator: float = _rng.randf_range(fator_min, fator_max)
	_duracao_voando_atual = maxf(tempo_voando * fator, 0.1)
	var vel_min: float = minf(fator_velocidade_voo_min, fator_velocidade_voo_max)
	var vel_max: float = maxf(fator_velocidade_voo_min, fator_velocidade_voo_max)
	_fator_velocidade_voo_atual = _rng.randf_range(vel_min, vel_max)
	_tempo_pairar_restante = 0.0


## Sorteia a duração da próxima estadia DENTRO usando fator aleatório individual.
func _sortear_duracao_dentro() -> void:
	var fator_min: float = minf(fator_aleatorio_dentro_min, fator_aleatorio_dentro_max)
	var fator_max: float = maxf(fator_aleatorio_dentro_min, fator_aleatorio_dentro_max)
	var fator: float = _rng.randf_range(fator_min, fator_max)
	_duracao_dentro_atual = maxf(tempo_dentro_colmeia * fator, 0.1)


## Aplica inclinação orgânica no corpo da abelha com base em curva e variação vertical.
func _atualizar_postura_organica(deslocamento: Vector3, delta: float) -> void:
	if _modelo == null:
		return
	var dir_anterior: Vector3 = _direcao_voo_anterior.normalized()
	var dir_atual: Vector3 = _direcao_voo_atual.normalized()
	var giro_horizontal: float = dir_anterior.cross(dir_atual).y
	var vel_vertical: float = 0.0
	if delta > 0.0001:
		vel_vertical = deslocamento.y / delta
	var inclinacao_x: float = clampf((-vel_vertical * 0.35) + sin(_angulo_orbita * 1.9 + _fase_voo) * 0.05, -0.30, 0.30)
	var inclinacao_z: float = clampf((-giro_horizontal * 3.2) + sin(_angulo_orbita * 2.7 + _fase_voo * 1.4) * 0.04, -0.45, 0.45)
	_modelo.rotation.x = lerpf(_modelo.rotation.x, inclinacao_x, minf(delta * 10.0, 1.0))
	_modelo.rotation.z = lerpf(_modelo.rotation.z, inclinacao_z, minf(delta * 10.0, 1.0))


## Reseta inclinações locais para evitar postura congelada fora do voo.
func _aplicar_postura_neutra() -> void:
	if _modelo == null:
		return
	_modelo.rotation.x = 0.0
	_modelo.rotation.z = 0.0
