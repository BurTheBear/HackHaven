# ECHO — Listener jumpscare, polished revision

A four-second, 24 fps caught animation using the original rigged Blender Listener. This revision adds a stronger listening head cock and recoil, staggered reaching hands, subtler reveal emission, more directional lighting, skin microdetail and short shutter motion blur.

## Files
- `Listener_Jumpscare.blend`: editable creature, animation, mouth/ear shape keys, mine corridor, camera, lighting, audio strip and timeline markers. Open this file and use the active camera to preview the shot. Frame range 1–96.
- `Listener_Jumpscare.glb`: creature only, with the non-looping `Jumpscare_Caught` animation, 17 bones and two animated morph targets. Embedded geometry/materials; no external textures required.
- `Listener_Jumpscare.mp4`: 1280×720 preview with the synchronized sound mix.
- `Jumpscare_Audio.wav`: four-second stereo 48 kHz mix for the caught sequence.
- `animate_jumpscare.py` and `render_preview.py`: construction and render scripts. The construction script reads `../Listener.blend`; the render script uses Metal on macOS. Change the render device for another platform.

## Timing
- 0.00–1.25 seconds: faint breathing/listening motion in darkness, with a sonar ping.
- 1.25–1.79: the Listener hears the player and cocks its head.
- 1.79–2.00: recoil and anticipation.
- 2.00–2.38: sudden advancing lunge; claws reach on slightly different timings, ears flare and mouth opens.
- 2.38–3.25: close contact, small head motion and camera recoil.
- 3.25–4.00: blackout and fading sound tail.

## Godot use
Import the GLB and play `Jumpscare_Caught` once when the player is caught. The animation already advances the creature toward the camera; suspend normal enemy movement during playback. The Blender staging assumes the camera starts about 6 m in front of the monster; tune the instance position to your game camera.

The GLB contains the creature animation. The cinematic camera, corridor, reveal lighting, blackout and audio are staged in the Blender file and MP4. Reproduce those presentation beats in the caught-state controller when using the GLB in game. The export uses ordinary creature materials, so the game can apply its own sound-reveal treatment.

Validation: imported in Godot 4.6.1, instantiated, and sought to 2.3 seconds without animation errors. Godot reported one clip, four seconds long, with 22 imported animation tracks. GLB inspection confirms bone transforms and morph-weight channels.

Model/animation: procedurally authored in Blender for this project with AI-assisted scripting, based on the existing ECHO Listener asset. Audio consists of edited CC0 recordings; see CREDITS.md. Uploaded as an editable asset package under `assets/listener/jumpscare/`. It does not replace the current in-game caught sequence; doing so is a separate integration task, so existing respawn timing stays intact.
