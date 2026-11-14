# ECHO — Game Design Document

> Hack Club Haven game jam · Theme: **Bounce Back** · Godot 4 · Team: Ritesh, Atharv, Shreyansh, Elias

## 1. One-line pitch
Your lantern died deep underground. The only way to see is to make noise, and every sound bounces back with a piece of the world.

## 2. Genre and key terms
- **Genre:** first-person stealth horror with an echolocation exploration mechanic
- **Core hook:** echolocation / sound-based navigation
- **Risk-reward loop:** every ping shows you the cave *and* tells the monsters where you are
- **Reactive AI:** monsters (Listeners) hunt by sound
- **Physics-based distraction:** pebbles bounce, ping where they land and pull monsters away
- **Real-time reveal shader:** the world only exists where your echo touches it
- **Minimalist neon aesthetic:** neon outlines on pure black
- **Voiced environmental storytelling:** voice logs from a lost explorer, recorded by the team
- **3D positional audio** and **environmental storytelling**, paid off by a full-color reveal at the end

## 3. How it fits "Bounce Back"
1. **Literally:** an echo is sound bouncing back. Pebbles bounce off the walls and send their own echoes.
2. **Figuratively:** you're lost, blind and hunted, and you claw your way back to the surface. The ending is the comeback moment: the dark breaks and the world comes back in full color.

## 4. Design pillars
1. **Sound is sight.** Everything the player sees comes from a sound they chose to make.
2. **Every ping is a decision.** Seeing more always costs safety.
3. **Readable in 10 seconds.** A judge should get it from the first click.
4. **Small but finished.** One polished 5–8 minute run beats a big unfinished one.

## 5. Story and setting
- **The player:** a cave explorer who fell through a sinkhole while mapping a cave called **the Hollow**. The fall smashed their lantern.
- **The Hollow:** an old mine and natural cave, home to the **Listeners**, blind creatures that hunt by sound.
- **Goal:** get back to the surface.
- **Told through the environment, not text:** abandoned mine carts, old rope ladders, chalk arrows left by earlier explorers that only show up in your echoes, the broken lantern at the start, and **Mara's voice logs**: recorders left by an explorer who fell in before you. Her logs tell the story and teach each mechanic.
- **Opening (two lines on a black screen):** "The rope snapped. The lantern's gone." → "Call out. Listen. Find your way back."
- **Ending:** daylight floods the final shaft, the reveal shader switches off, and the whole cave appears in color behind you. Text: "You found your way back."

## 6. Core loop
1. **Listen:** monsters breathing, water dripping, wind from the exit
2. **Ping or throw:** reveal the space around you, or somewhere far away
3. **Read** the outlines before they fade
4. **Move** through the dark from memory
5. **Get caught** (back to the last checkpoint) or **reach a checkpoint** (progress saved)

Each loop takes roughly 10 to 30 seconds.

## 7. Controls
| Action | Keyboard / mouse |
|---|---|
| Move | WASD or arrow keys |
| Look | Mouse (click the game to lock the mouse) |
| Ping | Left click / R2 |
| Jump (landing makes noise unless sneaking) | Space / controller A |
| Throw pebble | Right click or E |
| Whisper ping (small, silent) | Q |
| Sneak (silent footsteps) / Run (loud) | Hold C / Hold Shift |
| Chalk mark | F |
| Pause | Esc or P (the game also pauses whenever the mouse unlocks, see section 14) |

### Horror systems (added after researching Alien: Isolation, Amnesia, Dead Space, Perception)
- **Director** (`scripts/director.gd`): nudges a Listener toward your rough area if you've been quiet too long, and backs them off after ~10 s of high pressure (Alien: Isolation's menace gauge: tension, then release).
- **Dread:** the closer a Listener, the faster the heartbeat, the redder the screen edge and the more the camera trembles.
- **False scares:** drips, scrapes and knocks in the dark, and now and then a phantom red Listener in your echo that's gone on the next ping.
- **Footsteps are noise:** walking is heard within 3 m, running within 9 m, sneaking is silent.
- **Listener variety:** the Hall patroller stops to listen; the Zone 4 Sleeper wakes with a shriek; the Zone 4 Stalker is faster than you walk.
- **Getting caught:** your view snaps to the thing that got you, its echo lights up in your face, a sting plays and the screen flashes red.
- **Audio:** placeholder sounds are synthesized in code (`scripts/sfx.gd`). Replace them with recorded or CC0 files whenever you like.

## 8. Mechanics

### 8.1 Ping
- Sends a ring of light outward from the player at **18 m/s**, up to a max radius of **22 m**.
- Surfaces glow brightly as the ring passes, then keep a fading **afterglow for 2 s**.
- **Cooldown: 1 s.** A ping lives about 3.2 s (1.2 s for the ring to reach 22 m, plus 2 s of afterglow), so at most 4 of your pings are ever alive at once. Your pings and pebble pings have **separate slots** (section 12), so a pebble never wipes out your own ping mid-afterglow.
- Every ping is **loud**. One simple rule: **if the ring touches a Listener, it hears you.** That's 22 m for your ping and 10 m for a pebble's. The ring also outlines it in red at that moment, so you always see what heard you. Nothing out of sight is ever alerted.

### 8.2 Afterglow and memory
- Once the afterglow fades, the player is moving from memory.
- Assist: **footsteps.** Each step lights the floor within 1.5 m for half a second. Footsteps are quiet, so Listeners never hear them. This keeps "sound is sight" true and stops anyone getting completely lost.

### 8.3 Pebbles
- Start with **3**, carry up to **5**. Pebble piles glow gold and are visible without pinging.
- Thrown as a physics object (RigidBody3D) at **9 m/s**.
- Its **first 2 bounces** each send a smaller ping (radius **10 m**) from the impact point.
- Pebble pings are loud too, which makes them a lure: throw one far away and Listeners go there instead of to you.

### 8.4 Listeners (monsters)
- Invisible except when a ping wave passes over them (red outline instead of cyan).
- **States:** Patrol → Alert → Investigate → Search → back to Patrol.
  - **Alert (0.75 s):** stops, turns toward the sound and whispers ("I hear you..."). It doesn't move yet.
  - **Investigate:** walks to **where the sound came from**, not to the player. If it hears a newer sound on the way, it heads there instead (this is what makes pebble lures work).
  - **Search (4 s):** looks around the spot, then goes back to Patrol.
  - **Sleep (Zone 4 only):** ignores every sound except a ping that starts within **10 m** of it. Then it shrieks and goes to Alert.
- Patrol speed **1.5 m/s**, investigate speed **3.2 m/s**. The player walks at **3.5 m/s**. A Listener chases the sound, not you, and the Alert pause gives you a head start of about 2.6 m. So you can always escape if you move away right after pinging. Standing still on your own ping is what gets you caught.
- Getting within **1.0 m** of the player = caught: a short sting sound, a red flash, then respawn at the last checkpoint.
- They breathe and shuffle using 3D audio, so players can track them by ear.

### 8.5 Checkpoints
- Glowing shards of the broken lantern, visible without pinging.
- Touching one saves your position and pebble count and plays a warm chime.

### 8.6 Optional progression (stretch goal)
- Hidden **echo crystals**, each giving one upgrade: +20% ping radius, -0.2 s cooldown or +1 max pebble.
- Only add this if the core game is finished and fun by hour 4.

### 8.7 Voice logs
- Gold-glowing handheld recorders, visible without pinging, one or two per zone.
- Walking up to one plays a log from Mara in 3D audio. Ambience gets quieter while she talks.
- Listeners whisper ("I hear you...") when they start investigating and when they catch you.
- The log lines and file names are in git history (the old `ELEVENLABS.md`).

## 9. Tuning table
Starting values. Change them during playtests.

| Value | Start |
|---|---|
| Player walk speed | 3.5 m/s |
| Ping speed | 18 m/s |
| Ping max radius | 22 m |
| Ring width | 1.2 m |
| Afterglow duration | 2.0 s |
| Ping cooldown | 1.0 s |
| Listener hearing radius | same as the ping's radius (22 m / 10 m for pebbles) |
| Listener alert pause | 0.75 s |
| Sleeping Listener wake radius | 10 m |
| Listener patrol / investigate speed | 1.5 / 3.2 m/s |
| Listener catch distance | 1.0 m |
| Pebble throw speed | 9 m/s |
| Pebble ping radius | 10 m |
| Starting / max pebbles | 3 / 5 |
| Footstep floor glow | 1.5 m, 0.5 s |

## 10. Level design: the Hollow
Target length: **5 to 8 minutes** for a first-time player.

### Zone 1: The Drop (tutorial, about 1 min)
- Start lying under the hole you fell through, next to the broken lantern.
- Prompt: "Click to call out." The first ping reveals a narrow tunnel with one bend.
- Teaches pinging and afterglow. No danger.
- Ends at a ledge with the first pebble pile and checkpoint 1.

### Zone 2: The Veins (maze, about 2 min)
- Branching tunnels with 3 dead ends. One dead end hides extra pebbles, which rewards exploring.
- Chalk arrows from earlier explorers point the right way. They only show up in echoes.
- A chasm with a narrow bridge. The far side is out of ping range, so the prompt says "Right click to throw a pebble." The pebble's echo reveals the far side.
- Ends at checkpoint 2.

### Zone 3: The Listening Hall (first monster, about 2 min)
- A large hall full of pillars. Players hear breathing before they enter.
- One Listener patrols between the pillars.
- Intended solution: throw a pebble to the far left, then sneak along the right wall while it investigates.
- Players who ping too much get hunted, which teaches the rule fast.
- Checkpoint 3 at the exit.

### Zone 4: The Long Climb (finale, about 2 min)
- A rising switchback path toward the faint sound of wind from the exit.
- Two Listeners: one patrolling, and one asleep (Sleep state, section 8.4). It only wakes if a ping starts within 10 m of it, so players have to cross its area without pinging, or throw a pebble past it.
- Last 20 m: a straight run. Daylight from the exit is visible, which tempts players to rush.
- Reaching the exit triggers the ending.

### Level building rules
- Block out the whole cave with **CSG** nodes first (CSGBox3D, CSGCylinder3D, CSGCombiner3D). The reveal shader makes simple shapes look great.
- Add props from free CC0 packs (mine carts, crates, rails, pillars) for recognizable silhouettes.
- Keep tunnels **at least 2.5 m wide** so first-person movement doesn't feel cramped.
- Give every zone one clear landmark (a mine cart, a giant stalactite, a ladder) so players can get their bearings.

## 11. Visual direction
- **World:** pure black. Nothing is visible without sound.
- **Ping color:** cyan (#3df5ff), with white at the leading edge of the ring.
- **Listeners:** red (#ff3b4e).
- **Pickups and checkpoints:** warm gold (#ffc845), always faintly visible. The only warm color in the cave.
- **Style:** grid lines across surfaces so each echo looks like a scan.
- **Ending:** real lighting, sky and the models' original colors switch on. The contrast is the payoff.

## 12. The reveal shader (spec)
- One **unshaded** spatial ShaderMaterial, applied by a script as the material override on every level mesh (every MeshInstance3D under the Level node, or everything in the group `revealable`).
- **Global shader parameters** (Project Settings → Shader Globals), updated by the Echo system every frame:
  - `ping_0` to `ping_7` (vec4): xyz = ping origin, w = age in seconds (negative = inactive)
  - `ping_radius_0` to `ping_radius_7` (float): max radius of each ping (22 for player pings, 10 for pebbles)
  - **Slots 0–3 are for player pings, slots 4–7 for pebble pings.** A new ping replaces the oldest one in its own group only.
  - `player_pos` (vec3) and `step_glow` (float, 0–1): for the footstep floor glow. The Echo system sets `step_glow` to 1 on each footstep and fades it to 0 over 0.5 s. Only light surfaces facing up (world normal y > 0.7) within 1.5 m of `player_pos`.
- **Per pixel:**
  - Get the world position in the vertex shader (model matrix × vertex) and pass it to the fragment shader.
  - For each active ping: ring radius = age × speed, capped at that ping's max radius. Brightness = a soft band around the ring, plus an afterglow inside the ring that fades with age.
  - Add grid lines from the world position for the scanned look.
  - Final color = ping color × brightness. Everything else stays black.
- Listeners use the same shader with a red color uniform.
- Pass ping ages from the script instead of using the shader's built-in TIME, so the shader and the game clock never disagree.
- **Test it in a web export in the first hour.** If it fails in the browser, use the fallback in section 18.

## 13. Audio design
Audio is half the game. It comes from CC0 sound packs or sounds the team records itself.
- **Voices:** Mara (the lost explorer's voice logs) and the Listeners (inhuman whispers), recorded by teammates and pitched or filtered in Audacity.
- **Sound effects and ambience:** CC0 packs, with several variations of each.
- Everything is committed as files. The game never calls an external API.
- **Mix:** pings, footsteps and pebbles go through a "Cave" bus with reverb; voice logs stay dry and clear; ambience gets quieter while a log plays. The ping is the loudest sound in the game.

## 14. UI and screens
- **Title:** a black screen where a ping ripples out every few seconds and reveals the word ECHO. "Click to begin." Browsers only allow locking the mouse and starting audio after a click, so this click does both. The title whisper stays silent until then.
- **HUD:** pebble count as small gold dots (bottom left) and a cooldown ring around the crosshair. Nothing else.
- **Tutorial prompts:** small text that fades in once and fades out after the player does it.
- **Caught:** red flash, "The Hollow heard you.", respawn.
- **Pause:** Resume / Restart / Quit to title. In a browser, Esc always unlocks the mouse first and the game may never see the key press. So **the game pauses whenever the mouse gets unlocked** (Esc, alt-tab, clicking outside), not only on the `pause` action. Check `Input.mouse_mode` every frame. Resume needs a click, because browsers only re-lock the mouse on a click.
- **End screen:** "You found your way back." plus time taken and times caught, and a Play again button.

## 15. Technical architecture (Godot)

**Project settings**
- Renderer: **Compatibility** (required for the web export).
- Web export: single-threaded (the default). Test on itch.io early.
- Input map: `move_forward`, `move_back`, `move_left`, `move_right`, `ping`, `throw`, `pause`.

**Autoloads (singletons)**
- `Echo` (`scripts/echo_system.gd`): `emit_ping(position, max_radius, loud, is_pebble)` puts the ping in the right slot group, updates the shader globals and emits the signal `ping_emitted(position, max_radius, loud)`. Listeners connect to that signal and react when the ring reaches them: when the ping's age × 18 m/s ≥ their distance from it, if that distance is within `max_radius`. `step()` sets the footstep glow.
- `Game` (`scripts/game_state.gd`): game state (Title, Playing, Caught, Won), current checkpoint, pebble count, times caught and the run timer. Signals: `player_caught`, `checkpoint_reached`, `game_won`.

**Scene tree**
```
main.tscn            (Ritesh: wires everything together; the only person who edits it)
├─ WorldEnvironment  (black background, no ambient light)
├─ Level             (level.tscn, Atharv)
│  ├─ Zone1 … Zone4  (CSG blockout + props)
│  ├─ Checkpoints    (Area3D, group "checkpoint")
│  ├─ PebblePiles    (Area3D)
│  ├─ Listeners      (listener.tscn instances)
│  └─ Exit           (Area3D)
├─ Player            (player.tscn, Elias)
├─ UI                (ui.tscn on a CanvasLayer, Shreyansh)
└─ Ambience          (AudioStreamPlayer nodes, Shreyansh)
```

**Folders inside `game/`**
```
scenes/  scripts/  shaders/  audio/  assets/models/  sandbox/<name>/
```

## 16. Team ownership
| Person | Owns | First-hour goal |
|---|---|---|
| Ritesh | Echo system, reveal shader, main scene, ending | Shader working in a test room **and in a web export** |
| Elias | Player controller, pebbles, Listener AI | Walking, mouse look, and the ping input calling `Echo.emit_ping` |
| Atharv | Level: 4 zones, checkpoints, pickups, exit | Zones 1 and 2 blocked out in CSG |
| Shreyansh | Audio (voices, logs, effects), UI, web export, itch.io page, pitch | Mara and Listener voices recorded, first ping sounds collected |

Rule: only edit your own scenes and scripts. Ask before touching someone else's.

## 17. Schedule (6 hours)
| Time | Milestone |
|---|---|
| 0:00–1:00 | **M1:** shader works in the browser, player walks, Zones 1–2 blocked out, sounds collected |
| 1:00–3:00 | **M2:** pings, pebbles, Listeners, all 4 zones. **A full playthrough by 3:00** |
| 3:00–4:30 | **M3:** audio pass, UI, juice, the color ending |
| 4:30–5:30 | **M4:** outside playtests, tune the section 9 numbers, fix only what players trip on |
| 5:30–6:00 | **M5:** feature freeze, final web export, itch.io page, rehearse the pitch |

**Definition of done:** someone who has never seen the game can finish it in the browser, without help, in under 10 minutes.

## 18. Risks and fallbacks
| Risk | Fallback |
|---|---|
| Reveal shader doesn't work in the browser | Each ping spawns an OmniLight3D whose range grows, then fades. Less stylish, always works |
| Players get lost | Make the floor outline near the player stronger and add more chalk arrows |
| Listeners too hard | Lower their investigate speed or hearing radius |
| Listeners too easy | Raise their hearing radius, or add a second Listener to Zone 3 |
| Running out of time | Cut Zone 4 down to the final run, but keep the color ending: it's the payoff |
| Merge conflicts | Only Ritesh edits main.tscn; everyone else works in their own scene |

## 19. Stretch goals (in priority order)
1. More chalk-arrow storytelling and landmark props
2. Echo crystals (section 8.6)
3. A "whisper" ping: hold to charge a small, quiet ping that Listeners can't hear
4. Speedrun timer on the end screen
5. A second level

## 20. Pitch (60 seconds)
1. **Hook (10 s):** "What if the only way to see was to make noise?"
2. **Live demo (30 s):** the first ping in the tunnel, then the Listening Hall: throw a pebble, sneak past.
3. **Theme (10 s):** "Echoes bounce back, and so do you. You're blind, hunted, and clawing your way back to the surface."
4. **Tech (10 s):** "A real-time reveal shader, AI that hunts by sound, physics pebbles, and hand-recorded voices and sound, built in Godot in 6 hours." End on the color reveal.

## 21. itch.io page
- **Title:** ECHO
- **Short description:** Lost in the dark. Every sound you make shows you the cave, and tells the monsters where you are.
- **Tags:** horror, stealth, first-person, atmospheric, exploration, echolocation, short, 3D, Godot
- **Screenshots:** a ping mid-ring, a red Listener outline, the pebble lure, the color ending

## 22. Credits
Built with Godot 4. Credit every sound source. List every asset pack used, here and in the main README.
