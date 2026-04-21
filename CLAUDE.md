# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Cozy 3D apiculture game in Godot 4. Isometric-style orthographic camera, low-poly Kenney assets, GDScript throughout. No build system — open the project in the Godot 4 editor and press F5 to run.

## Code conventions

- Variable and function names in **Portuguese** (`tile_atual`, `esta_plantando`, `jogador_entrou`).
- All variables and functions must have comments explaining what they do.
- Use section comments to separate logical blocks: `# --- MOVIMENTO ---`, `# --- INTERAÇÃO ---`.
- Strong typing with `: Type` annotations. Use `:=` only when the type is unambiguous from the right-hand side; otherwise annotate explicitly.
- Nodes that need to be found without a direct scene reference use `get_tree().get_first_node_in_group("group_name")` or `get_node_or_null("Name")`.

## Architecture

### Scene tree (world.tscn)
```
World (Node3D) — world.gd
├── Player (CharacterBody3D) — player.gd
│   ├── Model (character_keeper_2.tscn) — hand nodes: hand-right, hand-left
│   ├── NavigationAgent3D
│   └── Inventario (Node) — inventario.gd  [group: "inventario"]
├── Bee (Node3D) — bee.gd
├── Camera3D — camera_follow.gd
├── NavigationRegion3D  (mesh built at runtime in world.gd)
├── PathVisualizer — path_visualizer.gd
├── FarmTile (Node3D) — farm_tile.gd  (spawned by world.gd)
└── UILayer (CanvasLayer)  (created at runtime)
    └── HotbarUI (Control) — hotbar_ui.gd
```

### Movement
Click-to-move via `NavigationAgent3D`. The camera uses orthographic projection with scroll-wheel zoom; zoom is handled in `camera_follow.gd` — do not intercept scroll events in other scripts.

### Inventory system
- `Item` (Resource, `item.gd`) — data object; `tipo_interacao` string is the key that connects items to world objects.
- `SlotInventario` (RefCounted, `slot_inventario.gd`) — one slot with item + quantity.
- `Inventario` (Node, `inventario.gd`) — hotbar array, selection state, input (keys 1–6 and Q). Emits `item_na_mao_mudou(item)`, `inventario_mudou`, `slot_selecionado_mudou(index)`.
- `HotbarUI` (Control, `hotbar_ui.gd`) — finds `Inventario` via group, builds slot panels at runtime, shows item name as colour-coded fallback when no icon texture exists.

### Interaction pattern
World objects expose `tentar_interagir(jogador: Node) -> bool`. The player calls this on `tile_atual` when E is pressed. The object validates `jogador.get_node("Inventario").obter_item_na_mao().tipo_interacao` against its own `tipo_interacao_aceita` string, consumes the item, and returns `true` if accepted. The player then runs its own planting animation/timer. This pattern is intentionally extensible: new interactable objects only need to implement `tentar_interagir`.

### World generation
`world.gd._ready()` builds everything at runtime: hex tile grid (axial coordinates, `TILE_SCALE = 3.0`), flat `StaticBody3D` collision, `NavigationMesh` polygon, farm tiles, hotbar CanvasLayer, and initial inventory items.

### Item hand model
`player.gd` searches the Model hierarchy for a node whose name contains `"hand"` (case-insensitive) to use as the attachment point (`hand-right` in `character_keeper_2.tscn`). When `item_na_mao_mudou` fires, the previous model is freed and the new `item.modelo_3d` is instanced as a child of that node with a scale-in tween.

## Input actions (must be configured in Project Settings → Input Map)

| Action | Key |
|---|---|
| `interagir` | E |
| `slot_anterior` | Q |
| `hotbar_1` … `hotbar_6` | 1 … 6 |

## Asset paths

- Hex tiles: `res://obj/kenney_hexagonal/*.glb`
- Flowers: `res://obj/kenney_nature_kit/flower_*.glb`
- Character: `res://obj/kenney_character/character_keeper_2.tscn`
- Item resources: `res://resources/*.tres`

## Rules

Always use Context7 when I need library/API documentation, code generation, setup or configuration steps without me having to explicitly ask.
