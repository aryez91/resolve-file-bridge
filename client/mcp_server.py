#!/usr/bin/env python3
"""
MCP server for resolve-file-bridge: lets any MCP client (Claude Desktop, Claude Code, ...) drive
DaVinci Resolve through the file bridge.

    pip install mcp
    RESOLVE_BRIDGE_ROOT=C:\\resolve-file-bridge  python mcp_server.py      (stdio transport)

Example client config (Claude Desktop / Claude Code .mcp.json):
    { "mcpServers": { "resolve": {
        "command": "python", "args": ["C:\\\\resolve-file-bridge\\\\client\\\\mcp_server.py"],
        "env": { "RESOLVE_BRIDGE_ROOT": "C:\\\\resolve-file-bridge" } } } }
"""
import json, os, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from bridge import Bridge  # noqa: E402

try:                                    # mcp >= 2.0
    from mcp.server.mcpserver import MCPServer as _Server
except ImportError:                     # mcp 1.x
    from mcp.server.fastmcp import FastMCP as _Server

INSTRUCTIONS = """Runs Lua inside a running DaVinci Resolve (Fusion page scripting) via resolve-file-bridge.
The user must have started 'Resolve Bridge Listen' from Workspace > Scripts.
In commands: `comp` is the current Fusion comp, `bridge` has helpers (bridge.dump(), bridge.tool(name),
bridge.add(regid,name), bridge.render(tool, frames), bridge.project(), bridge.timeline(), bridge.resolve()).
Set the global `result` to return data; print() output is returned too.
Never change what feeds MediaOut/the final output, or delete user nodes, without the user's approval."""

server = _Server(name="resolve-file-bridge", instructions=INSTRUCTIONS)
_bridge = None


def b():
    global _bridge
    if _bridge is None:
        _bridge = Bridge()
    return _bridge


def _fmt(res):
    return json.dumps(res, indent=1, ensure_ascii=False)


@server.tool()
def resolve_ping() -> str:
    """Check the bridge is listening; returns bridge version, current comp name and Resolve page."""
    return _fmt(b().ping())


@server.tool()
def resolve_run_lua(code: str, timeout_seconds: float = 120) -> str:
    """Run Lua code inside Resolve. Set the global `result` to return data (tables become JSON).
    Changes are wrapped in one undo step on the current comp."""
    return _fmt(b().run(code, timeout_seconds))


@server.tool()
def resolve_list_nodes() -> str:
    """List every tool in the current Fusion comp with its type, connections and expressions."""
    return _fmt(b().run("result = bridge.dump()"))


@server.tool()
def resolve_render_frames(tool_name: str, frames: list[int], prefix: str = "") -> str:
    """Render a tool's output at the given frames to PNGs in <bridge root>/renders/; returns their paths.
    Use this to look at results instead of guessing."""
    pre = prefix or (tool_name + "_")
    code = "result = bridge.render(%s, {%s}, %s)" % (json.dumps(tool_name), ",".join(str(int(f)) for f in frames), json.dumps(pre))
    return _fmt(b().run(code, 600))


@server.tool()
def resolve_timeline_info() -> str:
    """Current project/timeline: name, frame range, fps, and the clips on each video track."""
    code = r'''
local p = bridge.project(); local tl = p:GetCurrentTimeline()
result = { project = p:GetName(), fps = p:GetSetting("timelineFrameRate") }
if tl then
  result.timeline = tl:GetName(); result.start = tl:GetStartFrame(); result["end"] = tl:GetEndFrame()
  result.tracks = {}
  for t = 1, tl:GetTrackCount("video") do
    local items = {}
    for _, it in ipairs(tl:GetItemListInTrack("video", t) or {}) do
      items[#items+1] = { name = it:GetName(), start = it:GetStart(), ["end"] = it:GetEnd(),
                          left_offset = it:GetLeftOffset(), fusion_comps = it:GetFusionCompCount() }
    end
    result.tracks[t] = items
  end
end'''
    return _fmt(b().run(code))


if __name__ == "__main__":
    server.run()
