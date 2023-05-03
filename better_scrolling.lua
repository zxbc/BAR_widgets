function widget:GetInfo()
	return {
		name	= "Better Scrolling V2",
		desc	= "A set of enhancements to scrolling, with more customizable settings",
		author	= "Errrrrrr",
		date	= "April 11, 2023",
		license = "GNU GPL, v2 or later",
		layer	= 999999+1,
        handler = true,
		enabled	= true,
	}
end

-- LOADING THIS WIDGET WILL AUTOMATICALLY DISABLE THE DEFAULT "CAMERA MINIMUM HEIGHT" WIDGET 

-- This widget does the following (only affects the "Overhead" and "Spring" camera choices):
-- 1) Removes the unpleasant transition frames from scrolling past minimum camera height, so that scroll wheel can be used to pan the camera at min height
-- 2) Allows for higher scaling of the "Camera Minimum Height" and "Scroll Speed" values in settings
-- 3) Allows for adjustment to shift-scroll speed
-- 4) Allows for a customizable speed for scroll pan speed (the speed at which camera moves towards the direction of mouse cursor while scrolling)

-- Set this to TRUE to only enable the function of camera minimum height limiter (Default: false)
local onlyMinHeight = false

-- Set this to true if you want the camera to adjust instantly when scrolling to min height (Default: false)
-- NOTE: if you are used to the old camera minimum height widget, you may want to set this to true
local snapToMinHeight = false

-- Custom parameters:
-- NOTE: If you change the numbers below, you must type /luaui reload to make changes take effect in game
-- These factors change the scaling of default values in game settings
local scrollSpeedFactor = 1     -- Scroll speed setting is multiplied by this number (Default: 1)
local minHeightFactor = 2       -- Camera minimum height setting is multiplied by this number (Default: 1)
local panSpeedFactor = 1        -- Camera pan speed using scroll wheel is multiplied by this number (Default: 1)
local shiftSpeedFactor = 3      -- How many times faster shift-scroll is over normal scroll (Default: 3)

function widget:Initialize()
    widgetHandler:DisableWidget("Camera Minimum Height") -- disables default min height widget on load
end

function widget:Shutdown()
    widgetHandler:EnableWidget("Camera Minimum Height")
end

function widget:MouseWheel(up)
    local camState = Spring.GetCameraState()

    if (camState.name == "ov") then
        return false
    end

    -- skip if alt, ctrl or meta is held down
    local altDown, ctrlDown, metaDown, shiftDown = Spring.GetModKeyState()
    if (altDown or ctrlDown or metaDown or not camState.name == "ta" or not camState.name == "spring" ) then 
        return false
    end

    local minHeight = Spring.GetConfigInt("MinimumCameraHeight", 1500) * minHeightFactor
    local scrollSpeed = Spring.GetConfigInt("ScrollWheelSpeed", 50) * scrollSpeedFactor 
    scrollSpeed = scrollSpeed * (up and 1 or -1)    -- if not up then down
    scrollSpeed = scrollSpeed * (shiftDown and shiftSpeedFactor or 1)  -- double scroll speed if shift is held
    local snap = false

    local curHeight = minHeight

    if (camState.name == "ta") then 
        curHeight = camState.height
    elseif (camState.name == "spring") then 
        curHeight = camState.dist 
    end

    local nextHeight = curHeight * (1 + scrollSpeed * 0.007)

    if (nextHeight > minHeight) then
        if onlyMinHeight then 
            return false   -- use default scrolling if onlyMinHeight mode
        end 
    elseif (curHeight ~= minHeight) then    -- only snap to minHeight if adjusting from a higher height
        snap = snapToMinHeight
    end

    local mouseX, mouseY = Spring.GetMouseState()
    local _, groundPos = Spring.TraceScreenRay(mouseX, mouseY, true)

    if not groundPos then
        return false
    else
        -- Adjust the camera position based on the ground position of cursor (only during zoom in)
        if up then
            local dx = groundPos[1] - camState.px
            local dy = groundPos[2] - camState.py
            local dz = groundPos[3] - camState.pz
            local speed = 1 / 2 * panSpeedFactor

            camState.px = camState.px + dx * speed
            camState.py = camState.py + dy * speed
            camState.pz = camState.pz + dz * speed
        end
    end

    -- Set the camera height and limit it by min height value
    if (camState.name == "ta") then
        camState.height = math.max(nextHeight, minHeight)
    elseif (camState.name == "spring") then
        camState.dist = math.max(nextHeight, minHeight)
    end

    local transTime = Spring.GetConfigFloat("CameraTransitionTime",1.0)
    if snap then transTime = 0 end
    Spring.SetCameraState(camState, transTime, 2, 3)
    return true
end

