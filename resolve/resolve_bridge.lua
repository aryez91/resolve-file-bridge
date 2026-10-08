--[=[
resolve-file-bridge : listener that runs INSIDE DaVinci Resolve (Fusion page Lua, free or Studio)

An external program (bridge.py, an MCP server, an AI agent...) drops numbered Lua files into
<root>/inbox/. This listener runs them inside Resolve and writes the result back to
<root>/outbox/ as a .comp file whose CustomData carries a hex-encoded JSON payload.

Why so indirect? Resolve's embedded Lua has no io library, no os.remove/os.rename and no
directory listing. It CAN dofile() a script, test bmd.fileexists(), and save a comp - so a
comp file is the only way to get data out.

This file RETURNS a start function (Scripts-menu scripts run in their own environment, so settings
can't be passed through globals):
    dofile([[C:\resolve-file-bridge\resolve\resolve_bridge.lua]])({ root = [[C:\resolve-file-bridge\]] })
Options:
  root     folder containing inbox/ outbox/ renders/   (default: this file's folder/.., if detectable)
  minutes  how long to listen; 0 = until bridge.stop() or a "stop" file   (default 0)
  poll     seconds between inbox checks                          (default 0.5)
  carrier  "auto"  - save results via a short-lived temporary comp (leaves your comp untouched),
                     falling back to the current comp if that fails                (default)
           "comp"  - always save via the current comp (renames the open comp to cmd_NNNNNN.comp)
  once     true = process pending commands once and return
]=]

local VERSION = "0.1.0"
local fu = fusion or fu or app

local function start(cfg)
  cfg = cfg or {}

  -- ---------- paths ----------
  local function script_dir()
    -- Resolve's Lua has no `debug` library; only use it where it exists
    if type(debug) ~= "table" or type(debug.getinfo) ~= "function" then return nil end
    local ok, info = pcall(debug.getinfo, 1, "S")
    if ok and info and info.source and info.source:sub(1, 1) == "@" then
      return info.source:sub(2):match("^(.*[/\\])")
    end
  end
  local ROOT = cfg.root
  if not ROOT then
    local d = script_dir()
    if d then ROOT = d:gsub("[/\\]resolve[/\\]$", "") end
  end
  assert(ROOT, "resolve-file-bridge: pass { root = [[<bridge folder>]] } to the start function")
  local SEP = ROOT:find("\\", 1, true) and "\\" or "/"
  if ROOT:sub(-1) ~= SEP then ROOT = ROOT .. SEP end
  local INBOX, OUTBOX, RENDERS = ROOT .. "inbox" .. SEP, ROOT .. "outbox" .. SEP, ROOT .. "renders" .. SEP
  local STATE, STOP = ROOT .. "state.lua", ROOT .. "stop"
  local MINUTES = cfg.minutes or 0
  local POLL = cfg.poll or 0.5
  local CARRIER = cfg.carrier or "auto"
  local stop_requested = false
  local ONCE = cfg.once

  local function exists(p) return bmd.fileexists(p) end
  local function C() return fu:GetCurrentComp() end
  local function name_of(n) return string.format("cmd_%06d", n) end

  -- ---------- JSON encoder (results go out as JSON) ----------
  local function jstr(s)
    return '"' .. s:gsub('[%c"\\]', function(ch)
      local m = { ['"'] = '\\"', ['\\'] = '\\\\', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t' }
      return m[ch] or string.format("\\u%04x", ch:byte())
    end) .. '"'
  end
  local function json(v, depth, seen)
    depth, seen = depth or 0, seen or {}
    local t = type(v)
    if v == nil then return "null"
    elseif t == "boolean" then return tostring(v)
    elseif t == "number" then
      if v ~= v or v == math.huge or v == -math.huge then return "null" end
      if v == math.floor(v) and math.abs(v) < 1e15 then return string.format("%d", v) end
      return string.format("%.14g", v)
    elseif t == "string" then return jstr(v)
    elseif t == "table" then
      if seen[v] then return '"<cycle>"' end
      if depth > 12 then return '"<too deep>"' end
      seen[v] = true
      local n, count = #v, 0
      for _ in pairs(v) do count = count + 1 end
      local parts = {}
      if count == 0 then seen[v] = nil; return "[]" end
      if n > 0 and n == count then
        for i = 1, n do parts[i] = json(v[i], depth + 1, seen) end
        seen[v] = nil
        return "[" .. table.concat(parts, ",") .. "]"
      end
      for k, x in pairs(v) do parts[#parts + 1] = jstr(tostring(k)) .. ":" .. json(x, depth + 1, seen) end
      seen[v] = nil
      return "{" .. table.concat(parts, ",") .. "}"
    else
      return jstr(tostring(v))   -- userdata (tools, inputs...), functions
    end
  end
  local function hex(s) return (s:gsub(".", function(ch) return string.format("%02x", ch:byte()) end)) end

  -- ---------- helpers available to commands as `bridge` (alias `H`) ----------
  local B = { version = VERSION, root = ROOT, renders = RENDERS }
  function B.comp() return C() end
  function B.resolve() return resolve or (fu.GetResolve and fu:GetResolve()) end
  function B.project() return B.resolve():GetProjectManager():GetCurrentProject() end
  function B.timeline() return B.project():GetCurrentTimeline() end
  function B.tool(name)
    local t = C():FindTool(name)
    if not t then error("no tool named " .. tostring(name)) end
    return t
  end
  function B.tools()
    local out = {}
    for _, t in pairs(C():GetToolList(false)) do out[#out + 1] = t end
    return out
  end
  function B.dump()
    -- every tool: name, type, passthrough, and each connected/expression input
    local res = {}
    for _, t in ipairs(B.tools()) do
      local a = t:GetAttrs()
      local e = { name = a.TOOLS_Name, type = a.TOOLS_RegID, passthrough = a.TOOLB_PassThrough and true or false, inputs = {} }
      for _, inp in pairs(t:GetInputList()) do
        local id = inp:GetAttrs().INPS_ID
        local src = inp:GetConnectedOutput()
        local info
        if src then info = { from = src:GetTool().Name .. "." .. (src:GetAttrs().OUTS_ID or "") } end
        local ok, ex = pcall(function() return inp:GetExpression() end)
        if ok and ex and ex ~= "" then info = info or {}; info.expr = ex end
        if info then e.inputs[id] = info end
      end
      res[#res + 1] = e
    end
    return res
  end
  function B.inputs(name, frame)
    local t, f, res = B.tool(name), frame or C().CurrentTime, {}
    for _, inp in pairs(t:GetInputList()) do
      local id = inp:GetAttrs().INPS_ID
      local ok, v = pcall(function() return inp[f] end)
      if ok and type(v) ~= "userdata" then res[id] = v end
    end
    return res
  end
  function B.get(name, id, frame) return B.tool(name)[id][frame or C().CurrentTime] end
  function B.set(name, id, value, frame)
    local t = B.tool(name)
    if frame then t:SetInput(id, value, frame) else t:SetInput(id, value) end
  end
  function B.expr(name, id, text) B.tool(name)[id]:SetExpression(text) end
  function B.connect(src, dst, input)
    local d = B.tool(dst)
    if src then d:ConnectInput(input or "Input", B.tool(src)) else d[input or "Input"]:ConnectTo(nil) end
  end
  function B.add(regid, name)
    -- NOTE: always created off-screen; AddTool at a visible position can auto-connect to the selected tool
    local t = C():AddTool(regid, -32768, -32768)
    if name then t:SetAttrs({ TOOLS_Name = name }) end
    return t
  end
  function B.delete(name) B.tool(name):Delete() end
  function B.stop() stop_requested = true end   -- listener exits after the current command
  function B.seek(frame) C().CurrentTime = frame end
  function B.render(name, frames, prefix)
    -- render a tool's output to PNG(s) in <root>/renders/<prefix>NNNN.png ; returns list of paths
    local c = C()
    if type(frames) ~= "table" then frames = { frames } end
    prefix = prefix or (name .. "_")
    local sv = c:AddTool("Saver", -32768, -32768)
    local paths = {}
    local ok, err = pcall(function()
      sv.Clip = RENDERS .. prefix .. ".png"
      sv:ConnectInput("Input", B.tool(name))
      pcall(function() sv:SetInput("OutputFormat", "PNGFormat") end)
      for _, f in ipairs(frames) do
        c:Render({ Start = f, End = f, Tool = sv, Wait = true })
        paths[#paths + 1] = RENDERS .. prefix .. string.format("%04d", f) .. ".png"
      end
    end)
    sv:Delete()
    if not ok then error(err) end
    return paths
  end
  bridge, H = B, B

  -- ---------- running one command ----------
  local function save_result(c, base, payload)
    local path = OUTBOX .. base .. ".comp"
    if CARRIER ~= "comp" or not c then   -- "auto"; also when no comp is open (e.g. empty timeline)
      local ok, saved = pcall(function()
        local tc = fu:NewComp(true, false, false)  -- quiet, no autoclose; a *hidden* comp refuses to Save()
        if not tc then return false end
        tc:SetData("ResolveBridge", { id = base, payload = payload })
        local s = tc:Save(path)
        tc:Close()
        return s
      end)
      if ok and saved then return true, "temp" end
      if not c then return false, "none" end
    end
    c:SetData("ResolveBridge", { id = base, payload = payload })
    local s = c:Save(path)
    c:SetData("ResolveBridge", nil)
    return s, "comp"
  end

  local function run(n)
    local base = name_of(n)
    local lines, oldprint = {}, print
    print = function(...)
      local parts = {}
      for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
      lines[#lines + 1] = table.concat(parts, "\t")
    end
    result = nil
    comp = C()
    local c = comp
    local t0 = os.clock()
    if c then c:StartUndo("bridge " .. base) end
    local ok, err = pcall(dofile, INBOX .. base .. ".lua")
    if c then c:EndUndo(true) end
    print = oldprint
    local out = { id = n, status = ok and "OK" or "ERROR", error = (not ok) and tostring(err) or nil,
                  printed = lines, result = result, elapsed = os.clock() - t0, bridge = VERSION }
    local jok, js = pcall(json, out)
    if not jok then js = json({ id = n, status = "ERROR", error = "could not encode result: " .. tostring(js), printed = lines }) end
    local saved, how = save_result(C() or c, base, hex(js))
    print(string.format("resolve-file-bridge: %s -> %s%s%s", base, out.status,
          out.error and ("  " .. out.error) or "", saved and "" or "  (WARNING: result could not be saved)"))
    return saved
  end

  local function first_pending()
    if not exists(STATE) then return 1 end
    local ok, st = pcall(dofile, STATE)
    if ok and type(st) == "table" and tonumber(st.first_pending) then return tonumber(st.first_pending) end
    return 1
  end

  -- ---------- main loop ----------
  print(string.format("resolve-file-bridge %s: listening on %s (%s)", VERSION, ROOT,
        ONCE and "once" or (MINUTES > 0 and (MINUTES .. " min") or "until stopped")))
  if exists(STOP) then print("resolve-file-bridge: a 'stop' file exists - delete it to keep listening") end
  local n = first_pending()
  local started = os.time()
  while true do
    local fp = first_pending()
    if fp > n then n = fp end
    while exists(OUTBOX .. name_of(n) .. ".comp") do n = n + 1 end
    if exists(INBOX .. name_of(n) .. ".lua") then
      run(n); n = n + 1
      if stop_requested then break end
    else
      if ONCE then break end
      if exists(STOP) then break end
      if MINUTES > 0 and os.difftime(os.time(), started) > MINUTES * 60 then break end
      bmd.wait(POLL)
    end
  end
  print("resolve-file-bridge: stopped")
end

return start
