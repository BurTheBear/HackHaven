# ECHO — Freesound CC0 sound library

28 licensed source recordings, with full converted recordings and edited candidate cues for ECHO. See CREDITS.md for every creator and source link, manifest.json for exact edits and technical validation, and USAGE.csv for event mapping.

## Use in Godot

This library is stored in game/audio/freesound/. That subfolder is intentionally a library: it does not automatically replace the existing sound mix.

The current Sfx loader checks `res://audio/<event>.ogg`, then .wav, then .mp3. To enable a candidate, copy its event-named file one directory up into game/audio/ and test the mix. For example, copy pebble.wav to game/audio/pebble.wav. Only enable one format per event name, and check for an older .ogg that would take priority over a .wav.

Do not use source_step or other full sequences as a single footstep. Use step.wav or its alternate clips. Alternates require selecting different files in the caller; the existing loader does not randomize them automatically. No scripts, scenes or existing audio files are modified by adding this library.

All files are 44.1 kHz. Positional effects are mono; cave ambience, wind, birds, tape hiss and whisper ambience retain stereo. One-shots use 16-bit PCM WAV; long recordings use MP3. No external API or account is needed to play these files in-game.

## Looping and mix

The existing loader automatically loops drone, breath, wind, birdsong and tape_hiss for MP3 streams. The supplied breath excerpt, tape noise, birds and cave atmosphere are loop candidates; audition their joins and crossfade in the final implementation if necessary. Wind's source is described as a seamless loop. Whisper ambience is optional and needs its own loop/playback setup.

Keep the ping the clearest cue. Start cave ambience around -24 dB playback volume and adjust to taste, with dialogue and positional threat sounds above it. Peak targets in the manifest describe file mastering, not perceived loudness; in-game balancing is still needed. Do not play the full horror sting sequence for every catch: sting.wav is the short excerpt.

## What still needs team recording or design

Mara's scripted voice logs, intelligible Listener lines, and the whispered player name still need the team's own performances. whisper_ambience.mp3 is atmospheric texture, not a substitute for those lines. The existing sniff/exhale and Shepard-tone fallbacks remain available; no misleading replacements are supplied for them.

The sounds were license-checked and decoded/probed successfully. They have not been auditioned as a complete in-game mix or tested in the team's web build. Review the transient-selected excerpts before enabling them, especially footsteps, breathing, rope and sting cues.
