# HackHaven

Our Hack Club Haven game jam entry: **ECHO**, a first-person stealth-horror game built in Godot 4 where the only way to see is to make noise.

**Full game design doc: [DESIGN.md](DESIGN.md)**

**Audio plan for the ElevenLabs sponsor track: [ELEVENLABS.md](ELEVENLABS.md)**

**Asset list (Elias): [ASSETS.md](ASSETS.md)**

## Folders
- `game/`: the Godot project. Open `game/project.godot` in Godot.
- `atharv/`, `shreyansh/`, `elias/`: personal notes, sketches and reference.
- Prototype scenes go in `game/sandbox/<your-name>/` so Godot can open them.

## Get started
1. Install the same Godot 4 version as the rest of the team, plus GitHub Desktop.
2. Clone `BurTheBear/HackHaven` in GitHub Desktop.
3. In Godot's Project Manager, click Import and choose `game/project.godot`.

## Team rules
- Pull before you start. Commit and push every time something works.
- Save all scenes (Cmd+S) before you commit.
- Each person works in their own scenes. Only one person edits `main.tscn`.
- Export to web early and test the browser build often.
- Art: CC0 asset packs only (Kenney, Quaternius, KayKit, Poly Pizza, Poly Haven), no AI-generated art. Credit every pack below.
- Sound: made with ElevenLabs for the sponsor track. Every prompt and line is in [ELEVENLABS.md](ELEVENLABS.md). Generate the files ahead of time; the game never calls the API.

## Godot MCP (optional)
`.mcp.json` connects Claude Code to Godot through the [Godot MCP server](https://github.com/Coding-Solo/godot-mcp). It can launch the editor, run the game and read its errors and debug output.
- **Claude Code:** run `claude` from the repo root and approve the `godot` server when asked. If Godot isn't installed at `/Applications/Godot.app`, set `GODOT_PATH` to your Godot executable first.
- **Codex:** add this to `~/.codex/config.toml`:

```toml
[mcp_servers.godot]
command = "npx"
args = ["-y", "@coding-solo/godot-mcp"]
env = { GODOT_PATH = "/Applications/Godot.app/Contents/MacOS/Godot" }
```

- Stay within Haven's AI rules: use it to run and debug the game, not to build the game for you.

## Credits
- Voices, sound effects and ambience: made with [ElevenLabs](https://elevenlabs.io)
