function widget:GetInfo()
    return {
        name    = "Ping Wheel",
        desc    = "Displays a ping wheel when a keybind is held down. Default keybind is 'alt-f', rebindable.",
        author  = "Errrrrrr",
        date    = "June 21, 2023",
        license = "GNU GPL, v2 or later",
        version = "1.0",
        layer   = 999999,
        enabled = true,
        handler = true
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
local custom_keybind_mode = false   -- set to true for custom keybind

local pingWheel = { -- the options in the ping wheel, displayed clockwise from 12 o'clock
    {name = "ATTACK"},
    {name = "RALLY"},
    {name = "DEFEND"},
    {name = "HELP"},
    {name = "RETREAT"},
}

local spamControlFrames = 120   -- how many frames to wait before allowing another ping
local viewSizeX, viewSizeY = Spring.GetViewGeometry()
local pingWheelRadius = 0.1 * math.min(viewSizeX, viewSizeY)    -- 10% of the screen size
local pingWheelThickness = 5    -- thickness of the ping wheel line drawing

local pingWheelColor = {0.9, 0.8, 0.5, 0.6}
local pingWheelTextColor = {1, 1, 1, 0.6}
local pingWheelTextSize = 25
local pingWheelTextHighlightColor = {1, 1, 1, 1}
local pingWheelTextSpamColor = {0.9, 0.9, 0.9, 0.4}

local displayPingWheel = false

local pingWorldLocation
local pingWheelScreenLocation
local pingWheelSelection = 1
local spamControl = 0 
local gameFrame = 0
local flashFrame = 0

-- Speedups
local spGetMouseState = Spring.GetMouseState
local spTraceScreenRay = Spring.TraceScreenRay
local atan2 = math.atan2
local floor = math.floor
local pi = math.pi
local sin = math.sin
local cos = math.cos

function widget:Initialize()
    widgetHandler.actionHandler:AddAction(self, "ping_wheel_off", PingWheelOff, nil, "r")
    widgetHandler.actionHandler:AddAction(self, "ping_wheel_on", PingWheelOn, nil, "p")
end

-- Store the ping location in pingWorldLocation
function SetPingLocation()
    local mx, my = spGetMouseState()
    local _, pos = spTraceScreenRay(mx, my, true)
    if pos then
        pingWorldLocation = { pos[1], pos[2], pos[3] }
        pingWheelScreenLocation = { x = mx, y = my }

        -- play a UI sound to indicate wheel is open
        Spring.PlaySoundFile("sounds/ui/beep4.wav", 0.5, 'ui')
    end
end

function PingWheelOn(_, _, args)
    -- set pingwheel to display
    displayPingWheel = true
    if not pingWorldLocation then
        SetPingLocation()
    end
end

function PingWheelOff(_, _, args)
    -- set pingwheel to not display
    if displayPingWheel then
        displayPingWheel = false
        pingWorldLocation = nil
        pingWheelScreenLocation = nil
        pingWheelSelection = 1
    end
end

-- sets flashing effect to true and turn off wheel display
function FlashAndOff()
    flashFrame = 60
end

function widget:KeyPress(key, mods, isRepeat)
    if not custom_keybind_mode then
        if key == 102 and mods.alt then -- alt + f
            PingWheelOn()
        end
    end
end

function widget:KeyRelease(key, mods)
    -- making sure weird lingering display doesn't happen with custom keybind!
    PingWheelOff()
end

-- when mouse is pressed, issue the ping command
function widget:MousePress(mx, my, button)
    if displayPingWheel and pingWorldLocation and spamControl == 0 and button == 1 then
        --Spring.Echo("pingWheelSelection: " .. pingWheel[pingWheelSelection].name)
        local pingText = pingWheel[pingWheelSelection].name
        Spring.MarkerAddPoint(pingWorldLocation[1], pingWorldLocation[2], pingWorldLocation[3], pingText, false)

        -- Spam control is necessary!
        spamControl = spamControlFrames

        -- play a UI sound to indicate ping was issued
        Spring.PlaySoundFile("sounds/ui/mappoint2.wav", 1, 'ui')
        FlashAndOff()
    elseif button == 3 then
        PingWheelOff()
    end

end

function widget:GameFrame(gf)
    gameFrame = gf
end

function widget:Update(dt)
    if (gameFrame % 3 == 1) and displayPingWheel then
        -- calculate where the mouse is to decide which slice of the wheel is selected
        local mx, my = spGetMouseState()
        if not pingWheelScreenLocation then
            return
        end
        local angle = atan2(mx - pingWheelScreenLocation.x, my - pingWheelScreenLocation.y)
        pingWheelSelection = (floor((angle + pi) / (2 * pi / #pingWheel)) + 3 ) % #pingWheel + 1
        --Spring.Echo("pingWheelSelection: " .. pingWheel[pingWheelSelection].name)

        flashFrame = (flashFrame == 0) and 0 or (flashFrame - 3)
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
    -- we draw a wheel at the pingWheelScreenLocation divided into #pingWheel slices, with the first slice starting at the top
    if displayPingWheel and pingWheelScreenLocation then
        glPushMatrix()
        glDepthTest(false)
        -- we don't want to blend this with the background
        glBlending(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)
        -- draw a smooth circle at the pingWheelScreenLocation with 64 vertices
        glColor(pingWheelColor)
        glLineWidth(pingWheelThickness)

        local function Circle(r)
            for i = 1, 64 do
                local angle = (i - 1) * 2 * math.pi / 64
                glVertex(pingWheelScreenLocation.x + r * sin(angle), pingWheelScreenLocation.y + r * cos(angle))
            end
        end

        glBeginEnd(GL_LINE_LOOP, Circle, pingWheelRadius * 0.75)
        glLineWidth(0.5)
        glBeginEnd(GL_LINE_LOOP, Circle, pingWheelRadius)
        glLineWidth(pingWheelThickness)
        glBeginEnd(GL_LINE_LOOP, Circle, pingWheelRadius * 1.3)

        -- draw a dot at the center denoting where the ping will happen in the world
        glColor(1, 1, 1, 1)
        glPointSize(10)
        local function Dot()
            glVertex(pingWheelScreenLocation.x, pingWheelScreenLocation.y)
        end
        glBeginEnd(GL_POINTS, Dot)

        -- draw a line extending from the center to the one being selected
        local angle = (pingWheelSelection - 1) * 2 * pi / #pingWheel
        glColor(pingWheelColor)
        glLineWidth(pingWheelThickness/2)
        local function Line()
            glVertex(pingWheelScreenLocation.x, pingWheelScreenLocation.y)
            glVertex(pingWheelScreenLocation.x + pingWheelRadius * sin(angle), pingWheelScreenLocation.y + pingWheelRadius * cos(angle))
        end
        glBeginEnd(GL_LINES, Line)

        -- draw the text for each slice and highlight the selected one
        -- also flash the text color to indicate ping was issued
        local textColor = pingWheelTextColor
        if flashFrame > 0 and (flashFrame % 5 == 0) then
            textColor = { 0, 0, 0, 0}
        else
            textColor = pingWheelTextHighlightColor
        end
        glColor(textColor)
        glText(pingWheel[pingWheelSelection].name, pingWheelScreenLocation.x + pingWheelRadius * sin(angle), pingWheelScreenLocation.y + pingWheelRadius * cos(angle), pingWheelTextSize, "co")
        
        glColor(pingWheelTextColor)
        if spamControl > 0 then
            glColor(pingWheelTextSpamColor)
        end
        for i = 1, #pingWheel do
            if i ~= pingWheelSelection then
                angle = (i - 1) * 2 * math.pi / #pingWheel
                glText(pingWheel[i].name, pingWheelScreenLocation.x + pingWheelRadius * math.sin(angle), pingWheelScreenLocation.y + pingWheelRadius * math.cos(angle), pingWheelTextSize, "co")
            end
        end
        glPopMatrix()
    end
end