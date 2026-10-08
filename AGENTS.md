# Agent instructions for resolve-file-bridge

This repo lets you run Lua inside a running DaVinci Resolve (free or Studio).

**Before acting in Resolve, read [`skill/resolve-bridge/SKILL.md`](skill/resolve-bridge/SKILL.md)** - it has the
workflow, the safety rules and the Fusion/Resolve gotchas.

How to send commands:
- MCP tools (if the `resolve` server is registered): `resolve_ping`, `resolve_run_lua`, `resolve_list_nodes`,
  `resolve_render_frames`, `resolve_timeline_info`.
- Otherwise the CLI: `python client/bridge.py ping`, `... exec "<lua>"`, `... run <file.lua>`
  (bridge folder from `--root` or `$RESOLVE_BRIDGE_ROOT`).

If `ping` times out, ask the user to start **Workspace > Scripts > Resolve Bridge Listen** in Resolve.

Hard rules: build beside the user's work, verify with rendered frames, never change what feeds their final
output, delete their nodes/timelines, or overwrite an existing render without asking.

Working on the bridge code itself: the listener (`resolve/resolve_bridge.lua`) runs in Resolve's sandboxed
Lua (LuaJIT 5.1; no `io`, no `debug`, no `os.remove`, no directory listing; Scripts-menu globals don't reach
`dofile`d files). Keep `client/bridge.py` standard-library only.
