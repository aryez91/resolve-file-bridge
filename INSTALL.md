# Install

## Quick way
- **Windows:** double-click `install.bat` (re-run it after moving the folder; `uninstall.bat` removes it).
- **macOS / Linux:** `./install.sh` (`./install.sh --uninstall` to remove).

The installer creates the runtime folders, writes the Scripts-menu launcher with this folder's path into
Resolve's Scripts/Utility folder, sets `RESOLVE_BRIDGE_ROOT` (Windows), optionally installs the `mcp`
package, can register the MCP server with Claude Desktop / Claude Code, can install the agent skill,
and prints the MCP config for your machine. Then restart Resolve and continue at step 3 below.

## Manual way
1. **Put the folder somewhere local**, e.g. `C:\resolve-file-bridge` (Windows) or `~/resolve-file-bridge`.
   It must be writable; `inbox/ outbox/ archive/ renders/` are created by the client on first use
   (create `inbox` and `outbox` yourself if you only use the Lua side).

2. **Copy the launcher** `resolve/Resolve Bridge Listen.lua` into Resolve's Fusion scripts folder:
   | OS | Folder (typical) |
   |---|---|
   | Windows | `%APPDATA%\Blackmagic Design\DaVinci Resolve\Support\Fusion\Scripts\Utility` |
   | macOS | `~/Library/Application Support/Blackmagic Design/DaVinci Resolve/Fusion/Scripts/Utility` |
   | Linux | `~/.local/share/DaVinciResolve/Fusion/Scripts/Utility` |

   Open the copy and set `ROOT` to your folder. On macOS/Linux also change `[[resolve\resolve_bridge.lua]]`
   to `"resolve/resolve_bridge.lua"`.

3. **Restart Resolve**, open a project, then **Workspace > Scripts > Resolve Bridge Listen**.
   Workspace > Console shows `resolve-file-bridge 0.1.0: listening on ...`.

4. **Test**: `python client/bridge.py --root <folder> ping`  → `"status": "OK"`.

5. **Stop** the listener: `python client/bridge.py stop`. Emergency stop if it is stuck: create a file named
   `stop` in the bridge folder (delete it again before the next start).

## MCP (Claude Desktop, Claude Code, other MCP clients)
```bash
pip install mcp
```
```json
{ "mcpServers": { "resolve": {
    "command": "python",
    "args": ["C:\\resolve-file-bridge\\client\\mcp_server.py"],
    "env": { "RESOLVE_BRIDGE_ROOT": "C:\\resolve-file-bridge" } } } }
```
Give the agent `skill/resolve-bridge/SKILL.md` as a skill or project instructions - it encodes the
safe-editing rules and the gotchas.

## Options (the table passed to the start function in the launcher)
| Option | Default | Meaning |
|---|---|---|
| `root` | - | the bridge folder |
| `minutes` | `0` | stop after N minutes; 0 = until stopped |
| `poll` | `0.5` | seconds between inbox checks |
| `carrier` | `"auto"` | results saved via a temporary comp; `"comp"` = via your open comp (renames it) |
| `once` | `false` | process pending commands once and return |

Settings are passed as a table, not globals, because scripts started from Resolve's Scripts menu run in
their own environment - globals set there are not visible to files they `dofile()`.
