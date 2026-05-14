class_name BalanceamentoColmeia
extends Resource

# Recurso central de balanceamento para ajustar producao, custos e tempos da colmeia.


# --- PRODUCAO ---

## Incremento de progresso de mel por ciclo completo de uma abelha
@export var incremento_por_abelha: float = 0.33

## Segundos que a abelha fica voando por ciclo
@export var tempo_voando_base: float = 8.0

## Segundos que a abelha fica dentro da colmeia produzindo mel por ciclo
@export var tempo_dentro_colmeia_base: float = 5.0


# --- ECONOMIA ---

## Custo promocional da primeira abelha comprada
@export var custo_primeira_abelha: int = 30

## Incremento de custo aplicado a cada nova abelha comprada
@export var incremento_custo_por_abelha: int = 20

## Custos de upgrade por nivel atual (indice 1..4)
@export var custo_upgrade_por_nivel: Array[int] = [0, 120, 260, 420, 650]

## Capacidade maxima de abelhas por nivel da colmeia (niveis 1..5)
@export var capacidade_abelhas_por_nivel: Array[int] = [2, 5, 7, 10, 15]

## Duracao do cooldown de upgrade em segundos
@export var tempo_cooldown_upgrade: float = 300.0

## Capacidade de estoque de mel por nivel (1..5)
@export var capacidade_estoque_mel_por_nivel: Array[int] = [5, 15, 35, 75, 150]

## Custo de upgrade do estoque de mel por nivel atual (indice 1..4)
@export var custo_upgrade_estoque_mel_por_nivel: Array[int] = [0, 70, 170, 360, 720]


# --- RARIDADES ---

## Multiplicador de producao de mel por raridade da colmeia
@export var multiplicador_raridade: Dictionary = {
	"comum": 1.0,
	"rara": 1.45,
	"epica": 1.8,
	"lendaria": 2.3,
}

## Multiplicador de duracao do upgrade por raridade da colmeia
@export var multiplicador_tempo_upgrade_raridade: Dictionary = {
	"comum": 1.0,
	"rara": 1.45,
	"epica": 1.8,
	"lendaria": 2.3,
}

## Caminho do recurso de mel produzido por raridade
@export var recurso_mel_por_raridade: Dictionary = {
	"comum": "res://resources/mel.tres",
	"rara": "res://resources/mel_raro.tres",
	"epica": "res://resources/mel_epico.tres",
	"lendaria": "res://resources/mel_lendario.tres",
}

## Valor de venda configuravel por raridade (aplicado no Item em runtime)
@export var valor_venda_por_raridade: Dictionary = {
	"comum": 10,
	"rara": 20,
	"epica": 30,
	"lendaria": 45,
}
