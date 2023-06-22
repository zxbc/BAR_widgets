function widget:GetInfo()
    return {
        name    = "Ping Wheel",
        desc    = "Displays a ping wheel when a keybind is held down. Default keybind is 'alt-f', rebindable.",
        author  = "Errrrrrr",
        date    = "June 21, 2023",
        license = "GNU GPL, v2 or later",
        version = "2.0",
        layer   = 999999,
        enabled = true,
    }
end

-----------------------------------------------------------------------------------------------
-- Ping wheel is a 5-option wheel that allows you to quickly ping the map.
-- The wheel is opened by holding the keybind (default: alt-f), left click to select an option.
--
-- Set custom_keybind_mode to true for custom keybind.
-- Bindable action name: ping_wheel_on, ping_wheel_off (best bound to same key!)
--
-- You can add or change the options in the pingWheel table.
-----------------------------------------------------------------------------------------------
local custom_keybind_mode = false  -- set to true for custom keybind

local player_color_mode = true  -- set to false to use pingWheelColor instead of player color

local pingWheel = { -- the options in the ping wheel, displayed clockwise from 12 o'clock
    {name = "ATTACK"},
    {name = "RALLY"},
    {name = "DEFEND"},
    {name = "HELP"},
    {name = "RETREAT"},
    {name = "OMGSTOPECO"},
    {name = "OMW"},
}

local spamControlFrames = 60   -- how many frames to wait before allowing another ping
local viewSizeX, viewSizeY = Spring.GetViewGeometry()
local pingWheelRadius = 0.1 * math.min(viewSizeX, viewSizeY)    -- 10% of the screen size
local pingWheelThickness = 5    -- thickness of the ping wheel line drawing
local centerDotSize = 20        -- size of the center dot

local pingWheelColor = {0.9, 0.8, 0.5, 0.6}
local pingWheelTextColor = {1, 1, 1, 0.6}
local pingWheelTextSize = 25
local pingWheelTextHighlightColor = {1, 1, 1, 1}
local pingWheelTextSpamColor = {0.9, 0.9, 0.9, 0.4}
local pingWheelFanColor = {0.9, 0.8, 0.5, 0.8}
local pingWheelPlayerColor = {0.9, 0.8, 0.5, 0.8}

local keyDown = false
local displayPingWheel = false

local pingWorldLocation
local pingWheelScreenLocation
local pingWheelSelection = 0
local spamControl = 0 
local gameFrame = 0
local flashFrame = 0
local flashing = false

-- Speedups
local spGetMouseState = Spring.GetMouseState
local spTraceScreenRay = Spring.TraceScreenRay
local atan2 = math.atan2
local floor = math.floor
local pi = math.pi
local sin = math.sin
local cos = math.cos

function widget:Initialize()
    -- add the action handler with argument for press and release using the same function call
    widgetHandler:AddAction("ping_wheel_on", PingWheelAction, {true}, "p")
    widgetHandler:AddAction("ping_wheel_on", PingWheelAction, {false}, "r")
    pingWheelPlayerColor = {Spring.GetTeamColor(Spring.GetMyTeamID())}
    if player_color_mode then
        pingWheelColor = pingWheelPlayerColor
        pingWheelFanColor = pingWheelPlayerColor
    end
end

-- Store the ping location in pingWorldLocation
local function SetPingLocation()
    local mx, my = spGetMouseState()
    local _, pos = spTraceScreenRay(mx, my, true)
    if pos then
        pingWorldLocation = { pos[1], pos[2], pos[3] }
        pingWheelScreenLocation = { x = mx, y = my }

        -- play a UI sound to indicate wheel is open
        Spring.PlaySoundFile("sounds/ui/beep4.wav", 0.1, 'ui')
    end
end

local function TurnOn(reason)
    -- set pingwheel to display
    displayPingWheel = true
    if not pingWorldLocation then
        SetPingLocation()
    end
    --Spring.Echo("Turned on: " .. reason)
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
    flashFrame = 30
    --Spring.Echo("Flashing off: " .. tostring(flashFrame))
end

function widget:KeyPress(key, mods, isRepeat)
    if not custom_keybind_mode then
        if key == 102 and mods.alt and not isRepeat then -- alt + f
            keyDown = true
        end
    end
end

function widget:KeyRelease(key, mods)
    -- making sure weird lingering display doesn't happen with custom keybind!
    keyDown = false
    --Spring.Echo("keyDown: " .. tostring(keyDown))
end

function widget:MousePress(mx, my, button)
    if button == 1 and keyDown then
        TurnOn("mouse press")
        return true -- block all other mouse presses
    else
        -- set pingwheel to not display
        TurnOff("mouse press")
    end
end


-- when mouse is pressed, issue the ping command
function widget:MouseRelease(mx, my, button)
    if button == 1
        and displayPingWheel
        and pingWorldLocation 
        and spamControl == 0 
    then
        if pingWheelSelection > 0 then
            --Spring.Echo("pingWheelSelection: " .. pingWheel[pingWheelSelection].name)
            local pingText = pingWheel[pingWheelSelection].name
            Spring.MarkerAddPoint(pingWorldLocation[1], pingWorldLocation[2], pingWorldLocation[3], pingText, false)

            -- Spam control is necessary!
            spamControl = spamControlFrames

            -- play a UI sound to indicate ping was issued
            Spring.PlaySoundFile("sounds/ui/mappoint2.wav", 1, 'ui')
            FlashAndOff()
        else
            TurnOff("Selection 0")
        end
    else
        TurnOff("mouse release")
    end
end

function widget:GameFrame(gf)
    gameFrame = gf
end

function widget:Update(dt)
    if (gameFrame % 3 == 1) and displayPingWheel then

        local mx, my = spGetMouseState()
        if not pingWheelScreenLocation then
            return
        end
        -- calculate where the mouse is relative to the pingWheelScreenLocation, remember top is the first selection
        local dx = mx - pingWheelScreenLocation.x
        local dy = my - pingWheelScreenLocation.y
        local angle = math.atan2(dy, dx)
        local angleDeg = floor(angle * 180 / pi + 0.5)
        if angleDeg < 0 then
            angleDeg = angleDeg + 360
        end
        local selection = (floor((360-angleDeg) / 360 * #pingWheel)+2) % #pingWheel + 1
        if selection ~= pingWheelSelection then
            pingWheelSelection = selection
        end

        -- if the mouse is within 0.75 of the radius, then set pingWheelSelection to nothing
        local dist = math.sqrt(dx*dx + dy*dy)
        if dist < 0.75 * pingWheelRadius then
            pingWheelSelection = 0
        end


        --Spring.Echo("pingWheelSelection: " .. pingWheel[pingWheelSelection].name)

        if flashing and displayPingWheel then
            if flashFrame > 0 then
                flashFrame = flashFrame - 3
            else
                flashing = false
                TurnOff("flashFrame update")
            end
        end
    end
    if (gameFrame % 10 == 1) and spamControl > 0 then
        spamControl = (spamControl == 0) and 0 or (spamControl - 10)
    end
end

-- GL speedups
local glColor = gl.Color
local glLineWidth = gl.LineWidth
local glPushMatrix = gl.PushMatrix
local glPopMatrix = gl.PopMatrix
local glBlending = gl.Blending
local glDepthTest = gl.DepthTest
local glBeginEnd = gl.BeginEnd
local glText = gl.Text
local glVertex = gl.Vertex
local glPointSize = gl.PointSize
local GL_LINES    = GL.LINES
local GL_LINE_LOOP = GL.LINE_LOOP
local GL_POINTS = GL.POINTS
local GL_SRC_ALPHA = GL.SRC_ALPHA
local GL_ONE_MINUS_SRC_ALPHA = GL.ONE_MINUS_SRC_ALPHA

function widget:DrawScreen()
    glPushMatrix()

    -- if keyDown then draw a dot at where mouse is
    if keyDown and not displayPingWheel then
        -- draw dot at mouse location
        local mx, my = spGetMouseState()
        glColor(pingWheelColor)
        glPointSize(centerDotSize)
        glBeginEnd(GL_POINTS, glVertex, mx, my)
        -- also draw a billboard label next to the mouse saying "Ping Wheel"
        glColor(1, 1, 1, 1)
        glText("Ping Wheel", mx + 10, my + 10, 12, "O")

    end
    -- we draw a wheel at the pingWheelScreenLocation divided into #pingWheel slices, with the first slice starting at the top
    if displayPingWheel and pingWheelScreenLocation then
        -- draw a smooth circle at the pingWheelScreenLocation with 128 vertices
        glColor(pingWheelColor)
        glLineWidth(pingWheelThickness)

        local function Circle(r)
            for i = 1, 128 do
                local angle = (i - 1) * 2 * math.pi / 128
                glVertex(pingWheelScreenLocation.x + r * sin(angle), pingWheelScreenLocation.y + r * cos(angle))
            end
        end

        glBeginEnd(GL_LINE_LOOP, Circle, pingWheelRadius * 0.75)
        glLineWidth(0.5)
        glBeginEnd(GL_LINE_LOOP, Circle, pingWheelRadius)
        glLineWidth(pingWheelThickness)
        glBeginEnd(GL_LINE_LOOP, Circle, pingWheelRadius * 1.3)

        -- draw the center dot
        glColor(pingWheelColor)
        glPointSize(centerDotSize)
        glBeginEnd(GL_POINTS, glVertex, pingWheelScreenLocation.x, pingWheelScreenLocation.y)

        -- draw two lines denoting the delineation of the slices of the currently selected slice
        -- first angle should be half a selection ahead of the current selection
        -- second angle should be half a selection behind of the current selection
        -- only draw if pingWheelSelection is not 0
        if pingWheelSelection ~= 0 then
            local angle1 = (pingWheelSelection -0.5) * 2 * pi / #pingWheel
            local angle2 = (pingWheelSelection -1.5) * 2 * pi / #pingWheel
            glColor(pingWheelFanColor)
            glLineWidth(pingWheelThickness * 0.3)
            local function Line(angle)
                glVertex(pingWheelScreenLocation.x, pingWheelScreenLocation.y)
                glVertex(pingWheelScreenLocation.x + pingWheelRadius * 1.3 * sin(angle), pingWheelScreenLocation.y + pingWheelRadius * 1.3 * cos(angle))
            end
            glBeginEnd(GL_LINES, Line, angle2)
            glBeginEnd(GL_LINES, Line, angle1)
        end

        -- draw the text for each slice and highlight the selected one
        -- also flash the text color to indicate ping was issued
        local textColor = pingWheelTextColor
        if flashing and (flashFrame % 5 == 0)then
            textColor = { 1, 1, 1, 0}
        else
            textColor = pingWheelTextHighlightColor
        end
        local angle = (pingWheelSelection -1) * 2 * pi / #pingWheel
        glColor(textColor)
        if pingWheelSelection ~= 0 then
            glText(pingWheel[pingWheelSelection].name, pingWheelScreenLocation.x + pingWheelRadius * sin(angle), pingWheelScreenLocation.y + pingWheelRadius * cos(angle), pingWheelTextSize, "co")
        end

        glColor(pingWheelTextColor)
        if spamControl > 0 then
            glColor(pingWheelTextSpamColor)
        end
        for i = 1, #pingWheel do
            if i ~= pingWheelSelection or pingWheelSelection == 0 then
                angle = (i - 1) * 2 * math.pi / #pingWheel
                glText(pingWheel[i].name, pingWheelScreenLocation.x + pingWheelRadius * math.sin(angle), pingWheelScreenLocation.y + pingWheelRadius * math.cos(angle), pingWheelTextSize, "co")
            end
        end
        glLineWidth(1)
    end
    glPopMatrix()
end