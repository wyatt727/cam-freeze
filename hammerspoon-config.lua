--------------------------------------------------
-- OBS Camera Freeze Toggle (Cmd+Shift+F)
-- Toggles between live camera and frozen frame for Zoom calls
--------------------------------------------------
local frozenIndicator = nil
local camFrozen = false

local function updateFrozenIndicator()
    if frozenIndicator then
        frozenIndicator:delete()
        frozenIndicator = nil
    end
    if camFrozen then
        local screen = hs.screen.mainScreen():frame()
        frozenIndicator = hs.canvas.new({x = screen.w - 130, y = 10, w = 120, h = 32})
        frozenIndicator:level("overlay")
        frozenIndicator:behavior({"canJoinAllSpaces", "stationary"})
        frozenIndicator:appendElements({
            {type = "rectangle", fillColor = {red = 0.9, green = 0.1, blue = 0.1, alpha = 0.9}, roundedRectRadii = {xRadius = 6, yRadius = 6}},
            {type = "text", text = "CAM FROZEN", textColor = {white = 1}, textSize = 14, textFont = "Menlo-Bold", frame = {x = 10, y = 6, w = 100, h = 20}}
        })
        frozenIndicator:show()
    end
end

hs.hotkey.bind({"cmd", "shift"}, "F", function()
    hs.task.new("/usr/local/bin/cam-freeze", function(exitCode, stdout, stderr)
        if stdout and stdout:match("FROZEN") then
            camFrozen = true
            updateFrozenIndicator()
            hs.alert.show("🔴 Camera FROZEN", 1.5)
        elseif stdout and stdout:match("LIVE") then
            camFrozen = false
            updateFrozenIndicator()
            hs.alert.show("🟢 Camera LIVE", 1.5)
        else
            hs.alert.show("⚠️ Error: " .. (stderr or stdout or "unknown"), 2)
        end
    end):start()
end)

print("📹 OBS Freeze Toggle loaded - Press Cmd+Shift+F to freeze/unfreeze camera")
