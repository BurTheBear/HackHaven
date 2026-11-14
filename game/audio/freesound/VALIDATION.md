# Audio validation

- 76 audio files decoded successfully with FFmpeg; every file contained finite, non-silent samples.
- All 76 files imported and loaded as AudioStream resources with positive duration in Godot 4.6.1 Compatibility (headless).
- 44.1 kHz; short cues are 16-bit PCM WAV, long recordings and loop candidates are MP3.
- 28 source recordings; 48 edited cues and variations; approximately 13.32 MiB audio total, largest audio file 1.53 MiB.
- CC0 license link verified on each selected Freesound sound page on November 14, 2026.
- This is an asset library. Existing game files and active sound choices are preserved.
- No complete in-game listening pass or web export test has been performed. Listen to cue excerpts, loop joins and mix levels before enabling them.

The headless engine also logged a macOS system certificate lookup warning unrelated to local audio loading; all 76 local audio loads completed.
