-- Launcher template for resolve-file-bridge (the installers generate a ready-made copy of this).
-- Manual install: copy into Resolve's Fusion "Scripts/Utility" folder (see INSTALL.md) and edit ROOT.
-- Start: Workspace > Scripts > Resolve Bridge Listen     Stop: python client/bridge.py stop
local ROOT = [[C:\resolve-file-bridge\]]       -- <-- edit: the bridge folder (contains resolve\, inbox\, outbox\)
dofile(ROOT .. [[resolve\resolve_bridge.lua]])({
  root    = ROOT,
  minutes = 0,          -- 0 = listen until stopped (client/bridge.py stop)
  carrier = "auto",     -- "comp" = old behaviour (renames the open comp)
})
