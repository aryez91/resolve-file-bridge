-- Queue and start a render of the current timeline (H.264 MP4 works in the free version).
local TARGET = [[C:\renders]]          -- edit
local NAME   = "my_render_v1"           -- never reuse an existing name
local p = bridge.project()
assert(p:SetCurrentRenderFormatAndCodec("mp4", "H264"), "format/codec not accepted")
assert(p:SetRenderSettings({ SelectAllFrames = true, TargetDir = TARGET, CustomName = NAME,
                             ExportVideo = true, ExportAudio = true }), "render settings not accepted")
local id = p:AddRenderJob()
p:StartRendering(id)
bmd.wait(3)
result = { job = id, status = p:GetRenderJobStatus(id) }
-- poll later with:  result = bridge.project():GetRenderJobStatus("<job id>")
