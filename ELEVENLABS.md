# ElevenLabs audio plan (sponsor track)

Every voice, sound effect and ambience in ECHO is made with ElevenLabs. This file has every prompt and every line, ready to paste. Owner: Shreyansh.

## Rules
- Generate everything ahead of time on the ElevenLabs website and commit the files. **The game never calls the ElevenLabs API**, so no API key ever ends up in the build.
- If you write a script to batch-generate, keep the API key in a `.env` file (already in `.gitignore`). Never commit a key.
- Make several variations of anything that repeats. The game picks one at random so it never sounds robotic.
- Download as MP3 and use the exact file names below. Godot imports MP3 directly.
- Target: everything generated and imported by hour 2.

## Folders
```
game/audio/vo/     voice logs and whispers
game/audio/sfx/    sound effects
game/audio/amb/    ambience loops
game/audio/ui/     menu sounds
```

## 1. Voices (Voice Design)

### Mara, the lost explorer
- **Prompt:** "A tired woman in her early 40s, whispering and slightly out of breath, scared but determined. She is recording on an old handheld voice recorder deep in a cave: very close to the mic, a little muffled, faint tape hiss."
- Save the voice as **Mara**.
- Text-to-speech settings: lower stability for a shakier, more emotional delivery.

### The Listeners
- **Prompt:** "An inhuman, ancient voice. A very low, dry, rasping whisper, slow and drawn out, like breath forced through stone. Unsettling and quiet, not cartoonish."
- Save the voice as **Listener**.
- Text-to-speech settings: higher stability so every line sounds like the same creature.

If you use the Eleven v3 model, audio tags such as [whispers], [sighs] and [shaky breath] at the start of a line help the delivery.

## 2. Mara's voice logs (text-to-speech, voice: Mara)
Recorders glow gold and are visible without pinging. Walking up to one plays its log.

| File | Where it goes | Line |
|---|---|---|
| `vo/log_01.mp3` | Zone 1, next to the broken lantern | Day three down here. My lantern's dead. If anyone finds this... don't shout. They hear everything. |
| `vo/log_02.mp3` | Zone 1, end of the first tunnel | Make a sound and the cave answers. The walls come back for a second. Use that second. |
| `vo/log_03.mp3` | Zone 2, at the chasm | I can't see the other side. Throw something. Listen to where it lands. |
| `vo/log_04.mp3` | Zone 2, dead end with the extra pebbles | I left a few stones here. Whoever you are, you need them more than I do. |
| `vo/log_05.mp3` | Zone 3, just before the Listening Hall | There's one in the hall. It's huge. It goes where the noise is, not where you are. Throw something left. Stay on the right wall. |
| `vo/log_06.mp3` | Zone 3, at checkpoint 3 | I made it past. My hands won't stop shaking. Keep going up. Always up. |
| `vo/log_07.mp3` | Zone 4, halfway up | Two of them now. One of them is sleeping. Don't wake it. Please don't wake it. |
| `vo/log_08.mp3` | Zone 4, just before the exit | I can feel wind. I'm close. I'm going to make it back... I'm going to— |

Cut log_08 off sharply at the end, then silence.

## 3. Listener whispers (text-to-speech, voice: Listener)
| File | When it plays | Line |
|---|---|---|
| `vo/listener_hear_01.mp3` | A Listener starts investigating | I hear you. |
| `vo/listener_hear_02.mp3` | same | There you are. |
| `vo/listener_hear_03.mp3` | same | Again... |
| `vo/listener_hear_04.mp3` | same | Closer. |
| `vo/listener_hear_05.mp3` | same | So loud. |
| `vo/listener_hear_06.mp3` | same | Little sound... |
| `vo/listener_catch_01.mp3` | The player is caught | Found you. |
| `vo/listener_catch_02.mp3` | same | Quiet now. |
| `vo/listener_catch_03.mp3` | same | You called. I came. |
| `vo/listener_catch_04.mp3` | same | Stay with us. |
| `vo/title_whisper.mp3` | Title screen, looping with the ping | Call out. Something will answer. |

## 4. Sound effects (Sound Effects)
| File(s) | Variations | Length | Prompt |
|---|---|---|---|
| `sfx/ping_01–05.mp3` | 5 | 2 s | Single sharp sonar ping, a clean high click, in a huge stone cave with a long natural echo tail |
| `sfx/pebble_throw_01–03.mp3` | 3 | 0.5 s | Quick soft whoosh of a small stone thrown by hand |
| `sfx/pebble_bounce_01–05.mp3` | 5 | 0.5 s | Small stone hitting a hard rock floor once, sharp click, slight cave echo |
| `sfx/pebble_pickup.mp3` | 1 | 0.5 s | A handful of small stones scooped up, rattling together |
| `sfx/step_stone_01–06.mp3` | 6 | 0.3 s | Single soft footstep, boot on gritty stone floor, close |
| `sfx/listener_breath_loop.mp3` | 1 | 6 s | Slow, deep, raspy breathing of a large blind creature, wet and heavy, close, in a dark cave |
| `sfx/listener_shriek_01–03.mp3` | 3 | 1.5 s | Sudden piercing inhuman shriek echoing down a stone cave tunnel |
| `sfx/listener_step_01–04.mp3` | 4 | 0.5 s | Heavy dragging footstep of a large creature on stone, claws scraping |
| `sfx/caught_sting.mp3` | 1 | 1.5 s | Sharp horror sting: a distorted low hit with a rising screech, then silence |
| `sfx/checkpoint_chime.mp3` | 1 | 2 s | Warm soft glass chime, gentle and reassuring, small reverb |
| `sfx/recorder_click.mp3` | 1 | 0.3 s | Old cassette recorder play button clicking down |
| `sfx/recorder_hiss_loop.mp3` | 1 | 3 s | Faint tape hiss and crackle from an old handheld recorder |

## 5. Ambience (Sound Effects)
| File(s) | Length | Prompt |
|---|---|---|
| `amb/cave_loop.mp3` | 20 s | Deep cave ambience, distant water drips, low rumble, occasional small stones falling, seamless loop |
| `amb/drip_01–04.mp3` | 1 s | A single water drop falling into a shallow puddle in a cave, with echo |
| `amb/wind_exit_loop.mp3` | 15 s | Cold wind blowing through a narrow cave opening, hollow whistle, seamless loop |
| `amb/surface_end.mp3` | 20 s | Bright outdoor morning, birds singing, light breeze through trees |

If ElevenLabs offers a loop option, turn it on for the loop files. Otherwise trim them in Audacity so the end flows into the start.

## 6. UI
| File | Length | Prompt |
|---|---|---|
| `ui/click.mp3` | 0.2 s | Soft muted menu click, subtle |
| `ui/start.mp3` | 1.5 s | Deep soft whoosh that fades into a cave echo |

## 7. Music (optional, only if time allows)
If your ElevenLabs plan includes music: "Minimal dark ambient drone, slow and sparse, cave atmosphere, no drums, seamless loop, 60 seconds" saved as `amb/music_loop.mp3`. Keep it very quiet under everything else.

## 8. Putting it in Godot
- **Loops:** select the file, open the Import tab, turn on Loop, click Reimport.
- **Variations:** put all variations of a sound (for example the 5 pings) into one **AudioStreamRandomizer** resource with a slight random pitch (0.95–1.05), and play that instead of a single file.
- **3D sounds:** AudioStreamPlayer3D for Listeners, pebbles and recorders, so players can tell where they are.
- **2D sounds:** AudioStreamPlayer for the player's ping, footsteps, stings, UI and ambience.
- **Audio buses:**
  - **Cave:** a Reverb effect (room size about 0.8, wet about 0.35). Pings, footsteps and pebbles go here.
  - **Voice:** no reverb, so Mara's logs stay clear.
  - **Ambience:** turned down while a voice log plays.
- **Mix:** the ping is the loudest sound in the game. Everything else sits under it.

## 9. Credits and sponsor pitch
- **Credit line (README, itch.io page, end screen):** "Voices, sound effects and ambience made with ElevenLabs."
- **Pitch line:** "ECHO is a game about sound, so we made every sound in it with ElevenLabs: the voice of the lost explorer, the whispers of the Listeners, and every echo you hear." Then name the products used: Voice Design, text-to-speech and Sound Effects.

## Checklist
- [ ] Design the Mara and Listener voices
- [ ] Generate the 8 voice logs
- [ ] Generate the 11 Listener lines
- [ ] Generate all sound effects
- [ ] Generate the ambience loops
- [ ] Import, set loops, set up the buses and randomizers
- [ ] Add the credit line
