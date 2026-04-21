extends Node3D

# Velocidade do movimento orbital da abelha (radianos por segundo)
@export var speed: float = 1.2
# Raio horizontal da trajetória em torno da origem
@export var radius: float = 2.0
# Amplitude da oscilação vertical
@export var height_range: float = 3.2

var _t: float = 0.0          # Parâmetro de tempo acumulado para calcular a trajetória
var _anim: AnimationPlayer   # Referência ao AnimationPlayer encontrado na hierarquia

func _ready() -> void:
	# Usa call_deferred para garantir que os filhos já foram adicionados à cena
	call_deferred("_start_anim")

func _start_anim() -> void:
	# Busca o AnimationPlayer na hierarquia de filhos e inicia a animação em loop
	_anim = _find_anim_player(self)
	if _anim:
		var anim := _anim.get_animation("dance")
		if anim:
			anim.loop_mode = Animation.LOOP_LINEAR # Força loop contínuo da animação
		_anim.play("dance")

# Busca recursivamente um AnimationPlayer em qualquer nível da hierarquia
func _find_anim_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var result := _find_anim_player(child)
		if result:
			return result
	return null

func _process(delta: float) -> void:
	# Avança o tempo e calcula a posição numa trajetória 3D tipo lemniscata
	_t += delta * speed
	var x := radius * cos(_t)
	var z := radius * 0.5 * sin(2.0 * _t)  # Figura-8 no plano horizontal
	# absf garante que a abelha nunca desce abaixo de y=0.5 (não entra no chão)
	var y := absf(height_range * sin(_t)) + 0.5
	position = Vector3(x, y, z)

	# Orienta a abelha na direção do movimento calculando a tangente da trajetória
	var tangent := Vector3(
		-radius * sin(_t),
		height_range * cos(_t),
		radius * cos(2.0 * _t)
	)
	if tangent.length_squared() > 0.01:
		var t_norm := tangent.normalized()
		if abs(t_norm.dot(Vector3.UP)) < 0.99:
			look_at(global_position + t_norm, Vector3.UP)
