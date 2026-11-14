# Agent instructions

- The game is a Godot 4 project in `game/`: GDScript, Compatibility renderer, exported to the web.
- Use Godot 4 APIs only (CharacterBody3D, @export, @onready, await, signal.connect). Never Godot 3 syntax.
- Each teammate owns their own scenes and scripts. Only change the files you were asked about, and don't edit `main.tscn` unless asked.
- Art comes from CC0 asset packs only. Never generate images, textures or models with AI.
- Audio comes from ElevenLabs (see `ELEVENLABS.md`) and is generated ahead of time. The game must never call the ElevenLabs API or contain an API key.
