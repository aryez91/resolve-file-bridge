-- Add a Blur after MediaIn1 (side branch, output untouched), render frame 10, then remove it again.
local blur = bridge.add("Blur", "Bridge_TestBlur")
blur:ConnectInput("Input", bridge.tool("MediaIn1"))
blur.XBlurSize = 5
local paths = bridge.render("Bridge_TestBlur", { 10 }, "test_blur_")
blur:Delete()
result = { rendered = paths }
