class_name Item
extends Resource

# --- IDENTIFICAÇÃO ---
@export var id: String = ""                      # Identificador único usado em lógica (ex: "flor", "mel")
@export var nome_exibicao: String = ""           # Nome legível mostrado na UI (ex: "Flor de Lavanda")

# --- VISUAL ---
@export var icone: Texture2D = null              # Ícone 2D exibido na hotbar
@export var modelo_3d: PackedScene = null        # Modelo instanciado na mão do personagem; pode ser null

# --- EMPILHAMENTO ---
@export var empilhavel: bool = true              # Se vários podem ocupar o mesmo slot
@export var quantidade_maxima: int = 99          # Limite de itens por slot quando empilhável

# --- INTERAÇÃO ---
@export var tipo_interacao: String = ""          # Tag que determina o que esse item pode fazer
                                                  # Ex: "plantar", "regar", "coletar"
                                                  # Objetos do mundo verificam essa tag antes de aceitar a interação
