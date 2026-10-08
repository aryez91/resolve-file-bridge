-- Project, timeline range and the clips on each video track
local p = bridge.project(); local tl = p:GetCurrentTimeline()
result = { project = p:GetName(), fps = p:GetSetting("timelineFrameRate") }
if tl then
  result.timeline = tl:GetName(); result.start = tl:GetStartFrame(); result["end"] = tl:GetEndFrame()
  result.video_tracks = {}
  for t = 1, tl:GetTrackCount("video") do
    local items = {}
    for _, it in ipairs(tl:GetItemListInTrack("video", t) or {}) do
      items[#items + 1] = { name = it:GetName(), start = it:GetStart(), ["end"] = it:GetEnd() }
    end
    result.video_tracks[t] = items
  end
end
