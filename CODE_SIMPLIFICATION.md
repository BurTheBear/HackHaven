# ECHO code and core loop review

Reviewed after pulling `8be2bc7` (the team's existing readability pass). This update keeps the same scene hierarchy, public signals, enemy modes and save keys. No new manager, dependency or AI framework is introduced.

## Applied changes

- Removed the player chalk system: F/controller action, mark meshes/materials/numbering, tutorial volume, rebinding row, pause-menu hint and map dots. Existing environmental direction arrows and the menu's chalk drawing style remain.
- Manual checkpoint restart and caught-respawn now share one helper, in the same order: place player, clear ripples, restore checkpoint inventory/health/state. Continue-from-save remains separate because it must preserve loaded progress.
- One existing setting, `Settings.damage_enabled`, gates knife pickup/use, health damage, enemy damage and combat HUD. The Gameplay page explicitly offers No Damage and Damage; No Damage is selected for new/reset settings. Disabled knife pickups are hidden and cannot be consumed; toggling combat on restores uncollected knives, including while standing on one. Saved explicit combat preferences still load normally.
- Sound investigation still follows Alert → Investigate → Search → Patrol. A later sound cannot postpone a ripple already due to reach the monster sooner. This avoids repeated footsteps keeping a monster waiting indefinitely. The single pending sound slot is retained; no queue or extra state machine is added.
- Ordinary pursuit now keeps the last known/sounded position when line of sight is lost. It no longer reads the player's live position through rock during its existing three-second loss timer. The separately scripted chase keeps its deliberate chase behavior.

## Ripple cooldown result

The existing cooldown works and was retained: two seconds initially, crystal upgrades down to 0.8 seconds. Immediate repeats and presses just before expiry are blocked; after expiry a new ping succeeds. A buffered press fires once, then starts a fresh cooldown. Whispers have their own cooldown. Pebble ripples retain their own four slots and cannot replace player ripples. No timing or radius values changed.

## The core logic to keep

`Player` owns input, movement and action cooldowns. `Echo` owns ripple slots and sound events. `Listener` owns hearing, movement target and its existing modes. `Game` owns run progress and inventory. `Main` owns scene transitions and checkpoint flow. `UI` presents state; it should not spend inventory or choose enemy targets.

Further simplification should focus on separating the procedural audio generators and HUD drawing from their runtime controllers when those files next need work. That improves navigation without changing gameplay. Replacing the current enemy modes with a behavior tree or merging everything into one manager would add work without simplifying this game.

## Verification

Godot 4.6.1 headless on macOS: 35 gameplay checks passed; both full levels loaded, pinged and simulated with all three dagger pickups per level hidden in stealth mode. The checks cover ripple timing/buffering/upgrades, whisper cooldown, pebble slot isolation, delayed hearing, actual movement toward sound, arrival/search, loss of sight, both combat modes, instant catch and checkpoint inventory. The pre-change recording reproduced hearing delay resetting from 0.4 to 0.868 seconds and a lost-sight target jumping to the player's new position. The updated checks preserve 0.4 seconds and the last known position.

Run checks without touching the player's settings/saves:

```sh
python3 game/tests/run_checks.py /path/to/godot
```

The runner creates a disposable project with a separate application name. The local Godot build prints a macOS certificate-store warning; no GDScript or scene errors occurred in these checks. Browser pointer lock, web rendering/audio and the team's stated 4.7 build still need testing in that environment. Headless smoke checks skip only the UI's mouse-release auto-pause because a headless display cannot capture a pointer.

The polished Blender jumpscare is supplied separately under `assets/listener/jumpscare/`. Its camera, lighting and audio preview are authored assets; this change does not replace the current in-game caught sequence or add a four-second delay to respawns.
