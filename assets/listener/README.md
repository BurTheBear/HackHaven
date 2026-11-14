# ECHO / The Hollow Choir
Original Listener creature asset created in Blender at Atharv’s request. This folder stores the asset and its standalone review project; it does not replace gameplay scenes.
## Files
- `Listener.blend`: editable Blender 5.1 source, packed textures, studio and 17-bone rig.
- `Listener.glb`: full mesh, 39,460 triangles, embedded 2K albedo and normal maps.
- `Listener_Web.glb`: lighter 18,939-triangle mesh with the same rig and textures.
- Four animations: `Idle_Breathe`, `Walk_Stalk`, `Alert_Listen`, `Sleep_Dormant`.
- Beauty, front, back, side and red echo preview renders.
- `project.godot`: standalone Godot review project. F5 to run; drag to orbit; N switches animation; Tab switches studio/echo; Space sends a pulse.
- Blender construction scripts, manifest and validation results are included.
## Integration
Copy the chosen GLB into the game’s model directory and instance it as a visual child of the existing Listener. Preserve the existing collision, navigation and AI. Assign the game’s red reveal material to its MeshInstance3D. The model is about 3.36 m tall; scale the visual uniformly to 0.72 for about 2.4 m. It faces +Z after glTF conversion; rotate the visual 180 degrees around Y if the controller expects -Z.
Loop breathing, walking and sleeping; play Alert once. The gait is in-place. Fingers move with the hand, without individual finger controls. Check gait speed and tunnel clearance in-game.
Imported and exercised using Godot 4.6.1 Compatibility on Apple M1 Max. No game integration or browser export testing has been performed.
## Provenance
This is an AI-authored procedural asset, not a CC0 asset-pack model. No Sketchfab mesh, textures or animation were copied. The visual reference was Ruslan Abbasov’s [Abomination Horror Monster](https://sketchfab.com/3d-models/abomination-horror-monster-efef3970184f4766ae8d7da0b14ee6ee).
The repository’s existing rules prohibit AI-generated models. This asset is added under the user’s explicit request and must not be represented as compliant with those rules without the team resolving that policy.
