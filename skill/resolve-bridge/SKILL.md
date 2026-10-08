---
name: resolve-bridge
description: Drive a running DaVinci Resolve (free or Studio) through resolve-file-bridge - inspect and edit Fusion comps, render test frames, read/build timelines and queue renders. Use whenever a task involves acting inside the user's Resolve session.
---

# Working in DaVinci Resolve through resolve-file-bridge

The bridge runs Lua inside Resolve. You send code (MCP tool `resolve_run_lua`, or `bridge.py exec/run`),
it runs in Fusion's Lua with one undo step, and you get back JSON: `status`, `error`, `printed`, `result`.

## Before anything
1. `resolve_ping`. No answer → ask the user to run **Workspace > Scripts > Resolve Bridge Listen**.
   Don't keep retrying; the listener is either running or it isn't.
2. Look before you touch: `resolve_list_nodes` (Fusion) or `resolve_timeline_info` (Edit). Learn the user's
   node names and what feeds the output (MediaOut / Saver) before planning changes.

## Rules that keep the user's work safe
- Never rewire what feeds the final output, delete user nodes, or change their parameters without approval.
  Build new branches beside the existing graph, render them for comparison, then ask.
- Name everything you add with a recognisable prefix so the user can find and remove it.
- Prefer one reconnect to switch between old and new - make every change trivially reversible.
- Rendering a whole timeline takes minutes and writes files: confirm output name/location, never overwrite
  an existing deliverable (use _v2, _v3...).

## Verify with pixels, not assumptions
- `resolve_render_frames(tool, [frames])` writes PNGs to `<root>/renders/`. Look at them (crop/zoom around
  the area of interest, compare side by side with the source or the previous version) before claiming success.
- Pick test frames that stress the change (fast motion, edges, overlaps), not just an easy frame.
- Show the user labelled comparisons (which side is which) - they can't see what you looked at.
- If a render looks wildly wrong (e.g. a matte instead of an image), re-render once before debugging -
  Savers occasionally glitch.

## Writing Lua commands
- Set the global `result` to return data. Tables → JSON objects/arrays; userdata → strings.
- Helpers on `bridge` (alias `H`): `comp()`, `tool(name)`, `tools()`, `dump()`, `inputs(name)`, `get/set(name,id,value)`,
  `expr(name,id,text)`, `connect(src,dst,input)`, `add(regid,name)`, `delete(name)`, `seek(frame)`,
  `render(name, frames, prefix)`, `resolve()`, `project()`, `timeline()`.
- `bridge.add` creates tools off-screen on purpose: `AddTool` at a visible position can auto-insert the new
  tool after the selected one and silently rewire the graph. After wiring, read connections back to confirm.
- Connect with `tool:ConnectInput("Input", other)` or `tool.Input:ConnectTo(other.Output)`; verify with
  `inp:GetConnectedOutput():GetTool().Name`.
- `result` and errors from one command are independent of the next; there is no persistent state except the comp.

## Pages
The listener works on every Resolve page. Media pool, timeline and render calls work anywhere; Fusion-node
commands need `comp`, which can be nil (new project) or a stale comp on other pages - check before using it.

## Fusion gotchas (cost real time when unknown)
- Custom Tool: no `iif`; use comparison arithmetic (`(a>b)` is 1 or 0). Channels `r1 g1 b1 a1` … `r3`; only 3 images.
- Custom Tool only computes inside Image1's domain - an empty/smaller Image1 gives black. Edges mode matters.
- Loader + PNG: the PNG reader premultiplies by alpha on load (`Clip1.PNGFormat.PostMultiply`), so treat RGB
  as premultiplied or you get dark outlines.
- MediaIn images are often 8-bit; intermediate maths in a Custom Tool clamps negatives - offset or split nodes.
- Blur `XBlurSize` ≈ 0.83 × Gaussian sigma (measured), not the sigma itself.
- Expressions referencing a node break if that node is deleted and re-created; re-set them.
- Every `comp:Render` pops a "Render completed" dialog in Resolve - batch frames into one command.

## Resolve (Edit/Deliver) API notes
- Render queue: `p:SetCurrentRenderFormatAndCodec("mp4","H264")`, `p:SetRenderSettings({SelectAllFrames=true,
  TargetDir=..., CustomName=...})`, `id = p:AddRenderJob()`, `p:StartRendering(id)`, poll `p:GetRenderJobStatus(id)`.
  Free Resolve: H.264 works; H.265/10-bit settings may fail with "Cannot find appropriate codec".
- A completed job cannot be restarted; add a new one.
- Calls may return nil while a modal dialog is open in Resolve - resend once before assuming failure.
- Editing: build timelines from cut lists with `MediaPool:AppendToTimeline({{mediaPoolItem=, startFrame=, endFrame=}, ...})`
  (endFrame is exclusive; linked audio comes along; a new timeline starts at 01:00:00:00, e.g. frame 108000 at 30 fps);
  there is no blade/trim call - rebuild from ranges or import an FCPXML/EDL instead. Markers via `AddMarker`.

## Reporting
Say what you changed (node names), what you verified (which frames), and what is still the user's decision.
