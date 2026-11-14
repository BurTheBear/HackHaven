# HackHaven

Our Hack Club Haven game jam entry: **ECHO**, a first-person stealth-horror game built in Godot 4 where the only way to see is to make noise.

**Full game design doc: [DESIGN.md](DESIGN.md)**

**Asset list (Elias): [ASSETS.md](ASSETS.md)**

## Folders
- `game/`: the Godot project. Open `game/project.godot` in Godot. **Not created yet**, see "Create the project" below.
- `atharv/`, `shreyansh/`, `elias/`: personal notes, sketches and reference.
- Prototype scenes go in `game/sandbox/<your-name>/` so Godot can open them.

## Create the project (Ritesh, once, before anyone else)
Only one person creates `game/project.godot`. If two people create it, the two projects conflict and can't be merged.
1. In Godot's Project Manager, click New Project. Set the project path to the `game` folder inside your clone of this repo, and set the renderer to **Compatibility**.
2. Write the exact Godot version you used (for example 4.3.stable) in the line below, then commit and push.
3. Tell the team it's pushed.

**Team Godot version:** _not set yet_

## Get started (everyone else)
1. Install the Godot version above (exactly that one), plus GitHub Desktop.
2. Clone `BurTheBear/HackHaven` in GitHub Desktop.
3. Once Ritesh has pushed the project: in Godot's Project Manager, click Import and choose `game/project.godot`.

## Team rules
- Pull before you start. Commit and push every time something works.
- Save all scenes (Cmd+S on Mac, Ctrl+S on Windows) before you commit.
- Never commit `game/.godot/` (Godot's local cache) or web export builds. `.gitignore` already skips them.
- Each person works in their own scenes. Only one person edits `main.tscn`.
- Export to web early and test the browser build often.
- Art: CC0 asset packs only (Kenney, Quaternius, KayKit, Poly Pizza, Poly Haven), no AI-generated art. Credit every pack below.
- Sound: CC0 sound packs (Kenney, Freesound CC0, Sonniss) or sounds the team records itself. Credit every source below. The game never calls an external API.

## Godot MCP (optional)
`.mcp.json` connects Claude Code to Godot through the [Godot MCP server](https://github.com/Coding-Solo/godot-mcp). It can launch the editor, run the game and read its errors and debug output.
- **Claude Code:** run `claude` from the repo root and approve the `godot` server when asked. `.mcp.json` uses the `GODOT_PATH` environment variable, and falls back to `/Applications/Godot.app` on a Mac.
- **On Windows (or a Mac with Godot somewhere else):** set `GODOT_PATH` to your Godot executable first, then open a new terminal. For example, on Windows:

```powershell
setx GODOT_PATH "C:\Godot\Godot_v4.3-stable_win64.exe"
```

- **Codex:** add this to `~/.codex/config.toml`, with your own Godot path:

```toml
[mcp_servers.godot]
command = "npx"
args = ["-y", "@coding-solo/godot-mcp"]
env = { GODOT_PATH = "/Applications/Godot.app/Contents/MacOS/Godot" }
```

- Stay within Haven's AI rules: use it to run and debug the game, not to build the game for you.

## Credits
- Sound: list every sound pack or recorded source here
