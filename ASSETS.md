# ECHO asset list

Owner: **Elias**. Hand finished props to **Atharv**, who places them in the level.

**The most important rule:** during play the reveal shader ignores textures and colors, so every detail has to be real geometry. Use chunky shapes and clear silhouettes, and nothing thinner than about 5 cm. Colors only show in the full-color ending, so give every model simple flat colors.

## Specs for every model
- Format: **.glb**. Units in meters, Y-up, origin at the bottom center.
- Props under about 2,000 triangles; the creature under about 8,000. Textures no bigger than 1024 px.
- Save to `game/assets/models/story/`, `props/` or `ending/`. Use snake_case names (`recorder.glb`).
- Collision: simple box or capsule shapes.
- Scale check: the player is 1.7 m tall and tunnels are 3 m wide.

## Priority 1: gameplay pieces (done by 1:30)
| Asset | Size | Look | Used for |
|---|---|---|---|
| Recorder | 25 × 15 × 6 cm | Chunky handheld cassette recorder: box body, round speaker grill, 3 raised buttons, short antenna | Mara's 8 voice logs (gold glow) |
| Lantern shard | 30 × 50 cm | Broken lantern piece: metal ring frame with a jagged glass shard sticking up | Checkpoints (gold glow) |
| Pebble pile | 40 cm wide | Heap of 6–8 lumpy rocks | Pebble pickups (gold glow) |
| Broken lantern | 35 cm tall | Old hurricane lantern on its side, glass smashed | Start of the game, where you fell |
| Daylight shaft | 4 m tall | Wide cone, narrow end down | Light pouring in at the exit |

## Priority 2: the Listener (done by 2:30)
| Asset | Size | Look |
|---|---|---|
| Listener | 2.2 m tall | Thin and hunched, arms reaching the floor, **no eyes**, a head that is mostly huge ear-like fins or a mouth. It must read as "creature" from its outline alone. |

Animations in priority order: walk, idle (slow breathing sway), lunge. A static model is fine if there's no time.
In `listener.tscn`, set every mesh's **Material Override** to `shaders/reveal_listener.tres` so it shows up red.

## Priority 3: landmarks (one or more per zone)
| Asset | Size | Where |
|---|---|---|
| Wooden support frame (2 posts + crossbeam), plus a collapsed version | 3 m wide × 3.2 m tall | Repeated along tunnels, so each ping shows a rhythm of beams |
| Mine cart, upright and tipped-over | 1.4 × 0.9 × 0.9 m | Zone 2 |
| Rails: 2 m straight, 90° curve, broken piece | 1 m gauge | Zone 2 |
| Giant stalactite cluster | 3–5 m | Zone 3 hall |
| Ladder (wooden or rope) | 4 m | Zone 4 climb |
| Rubble pile | 3 m wide | Blocking dead ends |
| Chalk arrows: flat arrow shapes about 1 cm thick (geometry, not a texture) | 50 cm | On walls, pointing the way |
| Mara's backpack, open, with a rope coil | 50 cm | Near the exit, hinting at what happened to her |

## Priority 4: filler (only if ahead)
- Boulders in 3 sizes (0.5, 1.2, 2.5 m), 3 stalactites, 3 stalagmites
- Crates (1 m and 0.6 m), barrel, pickaxe, shovel, tool bag

## Ending (only seen in color)
- 2–3 low-poly trees, bushes and grass clumps outside the exit shaft. Bright, warm colors so the reveal lands.

## Make or download
Modeling everything by hand won't fit in 6 hours.
- **Make yourself:** the Priority 1 story pieces and the Listener (they are unique to ECHO).
- **Download (CC0 only):** support frames, cart, rails, rocks, trees. Good sources: Kenney (kenney.nl), KayKit (kaylousberg.itch.io), Quaternius (quaternius.com), Poly Pizza (CC0 models only).
- Credit every pack in the README's Credits section.

## Hand-off to Atharv
1. Drag the .glb into `assets/models/`.
2. Make a scene in `scenes/props/` (for example `mine_cart.tscn`): a StaticBody3D root, the model as a child, and a collision shape (select the mesh → **Mesh → Create Collision Shape**).
3. Atharv places it under **Level → Geometry**, which gives it the outline look automatically.

## Checklist
- [ ] Recorder, lantern shard, pebble pile, broken lantern, daylight shaft
- [ ] Listener model (+ walk/idle if time)
- [ ] Support frames, mine cart, rails
- [ ] Stalactite cluster, ladder, rubble, chalk arrows, backpack
- [ ] Ending trees and grass
- [ ] Credits in the README
