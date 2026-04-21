class_name NPC
extends Node3D

# --- REFERÊNCIAS INTERNAS ---

## Caixa roxa que representa visualmente o corpo do NPC (placeholder)
var _corpo: CSGBox3D = null


# --- CICLO DE VIDA ---

func _ready() -> void:
	_criar_corpo()
	_iniciar_animacao_respiracao()


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
