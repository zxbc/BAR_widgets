function widget:GetInfo()
    return {
        name    = "Ping Wheel",
        desc    =
        "Displays a ping wheel when a keybind is held down. Default keybind is 'alt-f', rebindable. Left click (or mouse 4) to bring up commands wheel, right click (or mouse 5) for messages wheel. \nNow with two wheel styles! (edit file param to change style)",
        author  = "Errrrrrr",
        date    = "June 27, 2023",
        license = "GNU GPL, v2 or later",
        version = "2.5",
        layer   = 999,
        enabled = true,
        handler = true,
    }
end

-----------------------------------------------------------------------------------------------
-- The wheel is opened by holding the keybind (default: alt-f), left click to select an option.
--
-- Set custom_keybind_mode to true for custom keybind.
-- Bindable action name: ping_wheel_on
--
-- You can add or change the options in the pingWheel tables.
-- the two tables pingCommands and pingMessages are left and right click options respectively.
--
-- NEW: styleChoice determines the style of the wheel. 1 = circle, 2 = ring, 3 = custom
-- NEW: added fade in/out animation (can be turned off by setting both frames numbers to 0)
-- NEW: you can now use mouse 4 and 5 directly for the two wheels!
-- NEW: LOTS OF PRETTY COLORS!
-----------------------------------------------------------------------------------------------
local custom_keybind_mode = false                  -- set to true for custom keybind

local pingCommands = {                             -- the options in the ping wheel, displayed clockwise from 12 o'clock
    { name = "Attack",  color = { 1, 0.5, 0.3, 1 } }, -- color is optional, if no color is chosen it will be white
    { name = "Rally",   color = { 0.4, 0.8, 0.4, 1 } },
    { name = "Defend",  color = { 0.7, 0.9, 1, 1 } },
    { name = "Retreat", color = { 0.9, 0.7, 1, 1 } },
    { name = "Alert",   color = { 1, 1, 0.5, 1 } },
    { name = "Reclaim", color = { 0.7, 1, 0.7, 1 } },
    { name = "Stop",    color = { 1, 0.2, 0.2, 1 } },
    { name = "Wait",    color = { 0.7, 0.6, 0.3, 1 } },
}

local pingMessages = {
    -- let's give these commands rainbow colors!
    { name = "TY!",      color = { 1, 1, 1, 1 } },
    { name = "GJ!",      color = { 1, 0.5, 0, 1 } },
    { name = "DANGER!",  color = { 1, 1, 0, 1 } },
    { name = "Sorry!",   color = { 0, 1, 0, 1 } },
    { name = "LOL",      color = { 0, 1, 1, 1 } },
    { name = "No",       color = { 0, 0, 1, 1 } },
    { name = "OMW",      color = { 0.5, 0, 1, 1 } },
    { name = "For sale", color = { 1, 0, 1, 1 } },
}

local styleChoice = 1 -- 1 = circle, 2 = ring, 3 = custom

-- Custom style parameters
local styleConfig = {
    [1] = {
        name = "Circle",
        bgTexture = "LuaUI/images/glow.dds",
        bgTextureSizeRatio = 2.2,
        bgTextureColor = { 0, 0, 0, 0.9 },
        dividerInnerRatio = 0.45,
        dividerOuterRatio = 1.1,
        dividerColor = { 1, 1, 1, 0.15 },
        textAlignRadiusRatio = 1.1,
    },
    [2] = {
        name = "Ring",
        bgTexture = "LuaUI/images/enemyspotter.dds",
        bgTextureSizeRatio = 1.9,
        bgTextureColor = { 0, 0, 0, 0.66 },
        dividerInnerRatio = 0.6,
        dividerOuterRatio = 1.2,
        dividerColor = { 1, 1, 1, 0.15 },
        textAlignRadiusRatio = 1.1,
    },
    [3] = {
        name = "Custom",
        bgTexture = "",
        bgTextureSizeRatio = 1.6,
        bgTextureColor = { 0, 0, 0, 0.7 },
        dividerInnerRatio = 0.4,
        dividerOuterRatio = 1,
        dividerColor = { 1, 1, 1, 0.15 },
        textAlignRadiusRatio = 0.9,
    },
}

-- On/Off switches
local player_color_mode = true -- set to false to use default pingWheelColor instead of player color
local draw_dividers = true     -- set to false to disable the dividers between options
local draw_line = false       -- set to true to draw a line from the center to the cursor during selection
local draw_circle = false      -- set to false to disable the circle around the ping wheel

-- Fade and spam frames (set to 0 to disable)
-- NOTE: these are now game frames, not display frames, so always 30 fps
local numFadeInFrames = 4   -- how many frames to fade in
local numFadeOutFrames = 4  -- how many frames to fade out
local numFlashFrames = 7    -- how many frames to flash when spamming
local spamControlFrames = 8 -- how many frames to wait before allowing another ping

local viewSizeX, viewSizeY = Spring.GetViewGeometry()

-- Sizes and colors
local pingWheelRadius = 0.1 * math.min(viewSizeX, viewSizeY) -- 10% of the screen size
local pingWheelThickness = 2                                 -- thickness of the ping wheel line drawing
local centerDotSize = 20                                     -- size of the center dot
local deadZoneRadiusRatio = 0.3                              -- the center "no selection" area as a ratio of the ping wheel radius
local outerLimitRadiusRatio = 5                              -- the outer limit ratio where "no selection" is active

local pingWheelTextColor = { 1, 1, 1, 0.7 }
local pingWheelTextSize = 25
local pingWheelTextHighlightColor = { 1, 1, 1, 1 }
local pingWheelTextSpamColor = { 0.9, 0.9, 0.9, 0.4 }
local pingWheelPlayerColor = { 0.9, 0.8, 0.5, 0.8 }

local pingWheelColor = { 0.9, 0.8, 0.5, 0.6 }
---------------------------------------------------------------
-- End of params

local globalDim = 1     -- this controls global alpha of all gl.Color calls
local globalFadeIn = 0  -- how many frames left to fade in
local globalFadeOut = 0 -- how many frames left to fade out

local bgTexture = "LuaUI/images/glow.dds"
local bgTextureSizeRatio = 1.9
local bgTextureColor = { 0, 0, 0, 0.8 }
local dividerInnerRatio = 0.4
local dividerOuterRatio = 1
local textAlignRadiusRatio = 0.9
local dividerColor = { 1, 1, 1, 0.15 }

local pingWheel = pingCommands
local keyDown = false
local displayPingWheel = false

local pingWorldLocation
local pingWheelScreenLocation
local pingWheelSelection = 0
local spamControl = 0
--local gameFrame = 0
local flashFrame = 0
local flashing = false
local gameFrame = 0

-- Speedups
local spGetMouseState = Spring.GetMouseState
local spGetModKeyState = Spring.GetModKeyState
local spTraceScreenRay = Spring.TraceScreenRay
local atan2 = math.atan2
local floor = math.floor
local pi = math.pi
local sin = math.sin
local cos = math.cos
local sqrt = math.sqrt

local soundDefaultSelect = "sounds/commands/cmd-default-select.wav"
local soundSetTarget = "sounds/commands/cmd-settarget.wav"

local function colourNames(R, G, B)
    local R255 = math.floor(R * 255) --the first \255 is just a tag (not colour setting) no part can end with a zero due to engine limitation (C)
    local G255 = math.floor(G * 255)
    local B255 = math.floor(B * 255)
    if R255 % 10 == 0 then
        R255 = R255 + 1
    end
    if G255 % 10 == 0 then
        G255 = G255 + 1
    end
    if B255 % 10 == 0 then
        B255 = B255 + 1
    end
    return "\255" .. string.char(R255) .. string.char(G255) .. string.char(B255) --works thanks to zwzsg
end

function widget:Initialize()
    -- add the action handler with argument for press and release using the same function call
    widgetHandler.actionHandler:AddAction(self, "ping_wheel_on", PingWheelAction, { true }, "pR")
    widgetHandler.actionHandler:AddAction(self, "ping_wheel_on", PingWheelAction, { false }, "r")
    pingWheelPlayerColor = { Spring.GetTeamColor(Spring.GetMyTeamID()) }
    if player_color_mode then
        pingWheelColor = pingWheelPlayerColor
    end

    -- set the style from config
    local style = styleConfig[styleChoice]
    bgTexture = style.bgTexture
    bgTextureSizeRatio = style.bgTextureSizeRatio
    bgTextureColor = style.bgTextureColor
    dividerInnerRatio = style.dividerInnerRatio
    dividerOuterRatio = style.dividerOuterRatio
    textAlignRadiusRatio = style.textAlignRadiusRatio
    dividerColor = style.dividerColor

    -- we disable the mouse build spacing widget here, sigh
    widgetHandler:DisableWidget("Mouse Buildspacing")
end

-- when widget exits, re-enable the mouse build spacing widget
function widget:Shutdown()
    --:EnableWidget("Mouse Buildspacing")
end

-- Store the ping location in pingWorldLocation
local function SetPingLocation()
    local mx, my = spGetMouseState()
    local _, pos = spTraceScreenRay(mx, my, true)
    if pos then
        pingWorldLocation = { pos[1], pos[2], pos[3] }
        pingWheelScreenLocation = { x = mx, y = my }

        -- play a UI sound to indicate wheel is open
        Spring.PlaySoundFile(soundSetTarget, 0.1, 'ui')
    end
end

local function FadeIn()
    if numFadeInFrames == 0 then return end
    globalFadeIn = numFadeInFrames
    globalFadeOut = 0
end

local function FadeOut()
    if numFadeOutFrames == 0 then return end
    globalFadeIn = 0
    globalFadeOut = numFadeOutFrames
end

local function TurnOn(reason)
    -- set pingwheel to display
    displayPingWheel = true
    if not pingWorldLocation then
        SetPingLocation()
    end
    --Spring.Echo("Turned on: " .. reason)
    -- turn on fade in
    FadeIn()
    return true
end

local function TurnOff(reason)
    if displayPingWheel then
        displayPingWheel = false
        pingWorldLocation = nil
        pingWheelScreenLocation = nil
        pingWheelSelection = 0
        --Spring.Echo("Turned off: " .. reason)
        return true
    end
end

function PingWheelAction(_, _, _, args)
    if args[1] then
        keyDown = true
        --Spring.Echo("keyDown: " .. tostring(keyDown))
    else
        --keyDown = false
        --Spring.Echo("keyDown: " .. tostring(keyDown))
    end
end

-- sets flashing effect to true and turn off wheel display
local function FlashAndOff()
    flashing = true
    flashFrame = numFlashFrames
    --FadeOut()
    --Spring.Echo("Flashing off: " .. tostring(flashFrame))
end

function widget:KeyPress(key, mods, isRepeat)
    if not custom_keybind_mode then
        if key == 102 and mods.alt then -- alt + f
            keyDown = true
        end
    end
end

function widget:KeyRelease(key, mods)
    -- making sure weird lingering display doesn't happen with custom keybind!
    keyDown = false
    --TurnOff("key release")
    --Spring.Echo("keyDown: " .. tostring(keyDown))
end

function widget:MousePress(mx, my, button)
    if keyDown or button == 4 or button == 5 then
        -- functionality of mouse build spacing is put in here, sigh
        -- check if alt is pressed
        local alt, ctrl, meta, shift = spGetModKeyState()
        if (button == 4 or button == 5) and alt then
            if button == 4 then
                Spring.SendCommands("buildspacing inc")
            elseif button == 5 then
                Spring.SendCommands("buildspacing dec")
            end
            return
        end

        if button == 1 or button == 4 then
            pingWheel = pingCommands
        elseif button == 3 or button == 5 then
            pingWheel = pingMessages
        end
        TurnOn("mouse press")
        return true -- block all other mouse presses
    else
        -- set pingwheel to not display
        --TurnOff("mouse press")
        FadeOut()
    end
end

-- when mouse is pressed, issue the ping command
function widget:MouseRelease(mx, my, button)
    if displayPingWheel
        and pingWorldLocation
        and spamControl == 0
    then
        if pingWheelSelection > 0 then
            --Spring.Echo("pingWheelSelection: " .. pingWheel[pingWheelSelection].name)
            local pingText = pingWheel[pingWheelSelection].name
            local color = pingWheel[pingWheelSelection].color or pingWheelColor
            Spring.MarkerAddPoint(pingWorldLocation[1], pingWorldLocation[2], pingWorldLocation[3],
                colourNames(color[1], color[2], color[3]) .. pingText, false)

            -- Spam control is necessary!
            spamControl = spamControlFrames

            -- play a UI sound to indicate ping was issued
            --Spring.PlaySoundFile("sounds/ui/mappoint2.wav", 1, 'ui')
            FlashAndOff()
        else
            --TurnOff("Selection 0")
            FadeOut()
        end
    else
        --TurnOff("mouse release")
        FadeOut()
    end
end

--[[ function widget:GameFrame(gf)
    gameFrame = gf
end ]]

local sec, sec2 = 0, 0
function widget:Update(dt)
    sec = sec + dt
    -- we need smooth update of fade frames
    if (sec > 0.017) and globalFadeIn > 0 or globalFadeOut > 0 then
        sec = 0
        if globalFadeIn > 0 then
            globalFadeIn = globalFadeIn - 1
            if globalFadeIn < 0 then globalFadeIn = 0 end
            globalDim = 1 - globalFadeIn / numFadeInFrames
        end
        if globalFadeOut > 0 then
            globalFadeOut = globalFadeOut - 1
            if globalFadeOut <= 0 then
                globalFadeOut = 0
                TurnOff("globalFadeOut 0")
            end
            globalDim = globalFadeOut / numFadeOutFrames
        end
    end

    sec2 = sec2 + dt
    if (sec2 > 0.03) and displayPingWheel then
        sec2 = 0
        if globalFadeOut == 0 and not flashing then -- if not flashing and not fading out
            local mx, my = spGetMouseState()
            if not pingWheelScreenLocation then
                return
            end
            -- calculate where the mouse is relative to the pingWheelScreenLocation, remember top is the first selection
            local dx = mx - pingWheelScreenLocation.x
            local dy = my - pingWheelScreenLocation.y
            local angle = math.atan2(dx, dy)
            local angleDeg = floor(angle * 180 / pi + 0.5)
            if angleDeg < 0 then
                angleDeg = angleDeg + 360
            end
            local offset = 360 / #pingWheel / 2
            local selection = (floor((360 + angleDeg + offset) / 360 * #pingWheel)) % #pingWheel + 1
            -- deadzone is no selection
            local dist = sqrt(dx * dx + dy * dy)
            if (dist < deadZoneRadiusRatio * pingWheelRadius)
                or (dist > outerLimitRadiusRatio * pingWheelRadius)
            then
                pingWheelSelection = 0
                --Spring.SetMouseCursor("cursornormal")
            elseif selection ~= pingWheelSelection then
                pingWheelSelection = selection
                Spring.PlaySoundFile(soundDefaultSelect, 0.3, 'ui')
                --Spring.SetMouseCursor("cursorjump")
            end

            --Spring.Echo("pingWheelSelection: " .. pingWheel[pingWheelSelection].name)
        end
        if flashing and displayPingWheel then
            if flashFrame > 0 then
                flashFrame = flashFrame - 1
            else
                flashing = false
                FadeOut()
            end
        end
        if spamControl > 0 then
            spamControl = (spamControl == 0) and 0 or (spamControl - 1)
        end
    end
end

local glColor2 = gl.Color
local function MyGLColor(r, g, b, a)
    if type(r) == "table" then
        r, g, b, a = r[1], r[2], r[3], r[4]
    end
    if not r or not g or not b or not a then
        return
    end
    -- new alpha is globalDim * a, clamped between 0 and 1
    local a2 = a * globalDim
    if a2 > 1 then a = 1 end
    if a2 < 0 then a = 0 end
    glColor2(r, g, b, a2)
end

-- GL speedups
--local glColor = gl.Color
local glColor                = MyGLColor
local glLineWidth            = gl.LineWidth
local glPushMatrix           = gl.PushMatrix
local glPopMatrix            = gl.PopMatrix
local glBlending             = gl.Blending
local glDepthTest            = gl.DepthTest
local glBeginEnd             = gl.BeginEnd
local glBeginText            = gl.BeginText
local glEndText              = gl.EndText
local glTexture              = gl.Texture
local glTexRect              = gl.TexRect
local glText                 = gl.Text
local glVertex               = gl.Vertex
local glPointSize            = gl.PointSize
local GL_LINES               = GL.LINES
local GL_LINE_LOOP           = GL.LINE_LOOP
local GL_POINTS              = GL.POINTS
local GL_SRC_ALPHA           = GL.SRC_ALPHA
local GL_ONE_MINUS_SRC_ALPHA = GL.ONE_MINUS_SRC_ALPHA

function widget:DrawScreen()
    -- if keyDown then draw a dot at where mouse is
    glPushMatrix()
    if keyDown and not displayPingWheel then
        -- draw dot at mouse location
        local mx, my = spGetMouseState()
        glColor2(pingWheelColor)
        glPointSize(centerDotSize)
        glBeginEnd(GL_POINTS, glVertex, mx, my)
        -- draw two hints at the top left and right of the location
        glColor2(1, 1, 1, 1)
        glText("R-click\nMsgs", mx + 15, my + 11, 12, "os")
        glText("L-click\nCmds", mx - 15, my + 11, 12, "ros")
    end
    -- we draw a wheel at the pingWheelScreenLocation divided into #pingWheel slices, with the first slice starting at the top
    if displayPingWheel and pingWheelScreenLocation then
        -- add the blackCircleTexture as background texture
        glBlending(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)
        glColor(bgTextureColor) -- inverting color for the glow texture :)
        glTexture(bgTexture)
        -- use pingWheelRadius as the size of the background texture
        local halfSize = pingWheelRadius * bgTextureSizeRatio
        glTexRect(pingWheelScreenLocation.x - halfSize, pingWheelScreenLocation.y - halfSize,
            pingWheelScreenLocation.x + halfSize, pingWheelScreenLocation.y + halfSize)
        glTexture(false)

        -- draw a smooth circle at the pingWheelScreenLocation with 128 vertices
        --glColor(pingWheelColor)
        glColor(1, 1, 1, 0.25)
        glLineWidth(pingWheelThickness)

        local function Circle(r)
            for i = 1, 128 do
                local angle = (i - 1) * 2 * math.pi / 128
                glVertex(pingWheelScreenLocation.x + r * sin(angle), pingWheelScreenLocation.y + r * cos(angle))
            end
        end

        -- draw the dead zone circle
        if draw_circle then
            glBeginEnd(GL_LINE_LOOP, Circle, pingWheelRadius * deadZoneRadiusRatio)
        end

        -- draw the center dot
        glColor(pingWheelColor)
        glPointSize(centerDotSize)
        glBeginEnd(GL_POINTS, glVertex, pingWheelScreenLocation.x, pingWheelScreenLocation.y)
        glPointSize(1)

        local function line(x1, y1, x2, y2)
            glVertex(x1, y1)
            glVertex(x2, y2)
        end
        -- draw a dotted line connecting from center of wheel to the mouse location
        if draw_line and pingWheelSelection > 0 then
            glColor(1, 1, 1, 0.5)
            glLineWidth(pingWheelThickness / 4)
            local mx, my = spGetMouseState()
            glBeginEnd(GL_LINES, line, pingWheelScreenLocation.x, pingWheelScreenLocation.y, mx, my)
        end

        -- draw divider lines between slices
        if draw_dividers then
            local function Line2(angle)
                glVertex(pingWheelScreenLocation.x + pingWheelRadius * dividerInnerRatio * sin(angle),
                    pingWheelScreenLocation.y + pingWheelRadius * dividerInnerRatio * cos(angle))
                glVertex(pingWheelScreenLocation.x + pingWheelRadius * dividerOuterRatio * sin(angle),
                    pingWheelScreenLocation.y + pingWheelRadius * dividerOuterRatio * cos(angle))
            end

            glColor(dividerColor)
            glLineWidth(pingWheelThickness * 1)
            for i = 1, #pingWheel do
                local angle2 = (i - 1.5) * 2 * math.pi / #pingWheel
                glBeginEnd(GL_LINES, Line2, angle2)
            end
        end

        -- draw the text for each slice and highlight the selected one
        -- also flash the text color to indicate ping was issued
        local textColor = pingWheelTextColor
        local flashBlack = false
        if flashing and (flashFrame % 2 == 0) then
            textColor = { 1, 1, 1, 0 }
            flashBlack = true
        else
            textColor = pingWheelTextHighlightColor
        end
        local angle = (pingWheelSelection - 1) * 2 * pi / #pingWheel

        --glColor(textColor)
        glBeginText()
        if pingWheelSelection ~= 0 then
            local text = pingWheel[pingWheelSelection].name
            local color = pingWheel[pingWheelSelection].color or textColor
            color[4] = 1
            if flashBlack then
                color = { 0, 0, 0, 0 }
            end
            glColor(color)
            glText(text, pingWheelScreenLocation.x + pingWheelRadius * textAlignRadiusRatio * sin(angle),
                pingWheelScreenLocation.y + pingWheelRadius * textAlignRadiusRatio * cos(angle), pingWheelTextSize * 2,
                "cvos")
        end

        --glColor(pingWheelTextColor)
        if spamControl > 0 then
            glColor(pingWheelTextSpamColor)
        end

        for i = 1, #pingWheel do
            if i ~= pingWheelSelection or pingWheelSelection == 0 then
                angle = (i - 1) * 2 * math.pi / #pingWheel
                local text = pingWheel[i].name
                local color = pingWheel[i].color or pingWheelTextColor
                color[4] = 0.75
                glColor(color)
                glText(text, pingWheelScreenLocation.x + pingWheelRadius * textAlignRadiusRatio * math.sin(angle),
                    pingWheelScreenLocation.y + pingWheelRadius * textAlignRadiusRatio * math.cos(angle),
                    pingWheelTextSize, "cvos")
            end
        end
        glEndText()

        glLineWidth(1)
        glBlending(false)
    end
    glPopMatrix()
end
