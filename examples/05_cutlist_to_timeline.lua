-- Build a NEW timeline from a cut list (source frame ranges of one media-pool clip).
-- The original timeline is not touched. Edit CLIP_NAME and CUTS.
-- Verified on Resolve (free, Windows): endFrame is EXCLUSIVE - {0, 150} gives 150 frames. Audio comes along.
local CLIP_NAME = "lecture.mov"
local CUTS = { {0, 250}, {400, 1200}, {1500, 3000} }   -- {startFrame, endFrame) in source frames, end exclusive

local mp = bridge.project():GetMediaPool()
local function find(folder)
  for _, c in ipairs(folder:GetClipList() or {}) do if c:GetName() == CLIP_NAME then return c end end
  for _, sub in ipairs(folder:GetSubFolderList() or {}) do local r = find(sub); if r then return r end end
end
local item = assert(find(mp:GetRootFolder()), "clip not found in media pool: " .. CLIP_NAME)
local tl = assert(mp:CreateEmptyTimeline("Bridge cut " .. os.date("%H%M%S")), "could not create timeline")
local infos = {}
for _, c in ipairs(CUTS) do infos[#infos + 1] = { mediaPoolItem = item, startFrame = c[1], endFrame = c[2] } end
local appended = mp:AppendToTimeline(infos)
result = { timeline = tl:GetName(), clips = appended and #appended or 0 }
