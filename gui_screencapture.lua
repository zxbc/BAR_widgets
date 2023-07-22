function widget:GetInfo()
    return {
        name    = "AutoScreenshot - Fixed Camera and Cropped Output",
        desc    = "Makes a screenshot every x frames. Shift+alt+p to toggle on/off. Shift+alt+o to toggle fullscreen capture on/off.",
        author  = "Errrrrrr",
        date    = "2023",
        license = "GNU GPL, v2 or later",
        layer   = 0,
        enabled = true,
        handler = true,
    }
end

local toggle_key = "shift+alt+p" -- The key to toggle the widget on/off
local fullscreen_key = "shift+alt+o" -- The key to toggle fullscreen capture on/off

local active = false -- The widget is inactive by default
local framesPerScreenshot = 150 
local format = "jpeg"
local quality = 95
local takeScreenshot = false
local screenshotFolder = "screenshots"
local prevUIState = nil
local screenshotIndex = 0
local initialCamState = nil -- Store the camera state when the widget is activated

local fullScreenCapture = false -- By default, we capture the boxed region of the battlefield
local spSendCommands = Spring.SendCommands

function widget:Initialize()
    -- GUI shader doesn't play nice with screenshots
    widgetHandler:DisableWidget('GUI Shader')

    widgetHandler.actionHandler:AddAction(self, "toggle_screenshot_widget", Toggle, nil, "p") -- Add the action to the widgetHandler
    widgetHandler.actionHandler:AddAction(self, "toggle_full_screen_capture", ToggleFullScreenCapture, nil, "p") -- Add the action to the widgetHandler

end

function ToggleFullScreenCapture()
    fullScreenCapture = not fullScreenCapture
    if fullScreenCapture then
        Spring.Echo("AutoScreenshot widget will capture the full screen.") -- Print a console message
    else
        Spring.Echo("AutoScreenshot widget will capture the battlefield region.") -- Print a console message
    end
    return true
end


function Toggle()
    active = not active
    if active then
        -- toggling off all the intruding UI widgets
        widgetHandler:DisableWidget('Grid menu')
        widgetHandler:DisableWidget('Order menu')

        initialCamState = Spring.GetCameraState()
        Spring.SendCommands("viewicons") -- Keep icons on
        Spring.Echo("AutoScreenshot widget has been turned ON. Fullscreen mode: " .. tostring(fullScreenCapture)) -- Print a console message
    else
        -- toggling on all the intruding UI widgets
        widgetHandler:EnableWidget('Grid menu')
        widgetHandler:EnableWidget('Order menu')

        Spring.Echo("AutoScreenshot widget has been turned OFF.") -- Print a console message
    end
    return true
end

function widget:GameFrame(n)
    if active and n % framesPerScreenshot == 0 then
        takeScreenshot = true
    end
end

local updates = 0
function widget:Update()
    updates = updates + 1
    if updates > 30 then
        spSendCommands({"bind " .. toggle_key .. " toggle_screenshot_widget"}) -- Use Spring's command to bind the hotkey
        spSendCommands({"bind " .. fullscreen_key .. " toggle_full_screen_capture"}) -- Use Spring's command to bind the hotkey
    end
    if active then
        -- Keep the camera fixed
        -- get camera state and check against initial state
        local camState = Spring.GetCameraState()

        -- if camera has moved, reset it
        if camState.px ~= initialCamState.px or camState.py ~= initialCamState.py or camState.pz ~= initialCamState.pz or
                camState.rx ~= initialCamState.rx or camState.ry ~= initialCamState.ry or camState.rz ~= initialCamState.rz or
                camState.vx ~= initialCamState.vx or camState.vy ~= initialCamState.vy or camState.vz ~= initialCamState.vz then
            Spring.SetCameraState(initialCamState, 0)
        end

        --Spring.SetCameraState(initialCamState, 0)
    end
end

function widget:DrawScreen()
    if takeScreenshot then
        local minX, minY, width, height
        if fullScreenCapture then
            -- Full screen capture
            local viewSizeX, viewSizeY, _, _ = Spring.GetViewGeometry()
            minX = 0
            minY = 0
            width = viewSizeX
            height = viewSizeY
        else
            -- Battlefield region capture
            local x1, y1 = Spring.WorldToScreenCoords(0, 0, 0)
            local x2, y2 = Spring.WorldToScreenCoords(Game.mapSizeX, 0, 0)
            local x3, y3 = Spring.WorldToScreenCoords(0, 0, Game.mapSizeZ)
            local x4, y4 = Spring.WorldToScreenCoords(Game.mapSizeX, 0, Game.mapSizeZ)

            -- Calculate bounding box in screen space
            minX = math.min(x1, x2, x3, x4)
            minY = math.min(y1, y2, y3, y4)
            local maxX = math.max(x1, x2, x3, x4)
            local maxY = math.max(y1, y2, y3, y4)

            -- Define margin as a percentage of width and height (e.g., 5%)
            local marginX = 0.05 * (maxX - minX)
            local marginY = 0.05 * (maxY - minY)

            -- Adjust bounding box with margins
            minX = minX - marginX
            maxX = maxX + marginX
            minY = minY - marginY
            maxY = maxY + marginY

            -- Calculate width and height of bounding box
            width = maxX - minX
            height = maxY - minY
        end
        -- Save current UI state and disable UI elements
        prevUIState = Spring.GetConfigString("InputTextGeo")
        Spring.SendCommands("inputtextgeo 0 0 0 0") -- command to hide the UI

        -- Get the name of the map
        local mapName = Game.mapName or "unknown"

        -- Save screenshot to file
        local fileName = screenshotFolder .. "/" .. mapName .. "_" .. tostring(screenshotIndex) .. '.' .. format
        if fullScreenCapture then
            spSendCommands('screenshot '.. format .. ' ' .. quality)
        else
            gl.SaveImage(minX, minY, width, height, fileName, {alpha = true, yflip = true})
        end
        

        -- Increment screenshot index
        screenshotIndex = screenshotIndex + 1

        -- Restore previous UI state
        Spring.SendCommands("inputtextgeo " .. prevUIState) -- command to restore the UI

        takeScreenshot = false
    end
end

function widget:GetConfigData()
	return fullScreenCapture
end

function widget:SetConfigData(data)
    if data ~= nil then
        fullScreenCapture = data
    end
end


