function widget:GetInfo()
    return {
        name    = "Commander Radar",
        desc    =
        "Shows a radar with surrounding enemy positions and commander health. Shift+left click on the radar to drag it around. Scroll up and down on the radar to change radar range. Settings saved through games.",
        author  = "Errrrrrr",
        date    = "June, 2023",
        version = "1.0",
        license = "GNU GPL, v2 or later",
        layer   = 999999,
        enabled = true,
        handler = true
    }
end

local detectionRadius = 1000 -- radius of the radar in game distance
local radarSize = 250        -- size of the radar in pixels
local minDetectionRadius = 500
local maxDetectionRadius = 5000

local commanderIconSize = 18
local healthBarHeight = 10
local healthBarWidth = radarSize

local viewX, viewY, _, _ = Spring.GetViewGeometry()
local radarMargin = viewX - 400 - radarSize       -- 400 offset puts the radar just to the left of playerslist
local drawRatio = radarSize / detectionRadius / 2 -- gives the ratio of pixels to game distance

local commanderID
local commanderHealth = 0
local commanderMaxHealth = 0
local recentlyDamaged = 0 -- number of frames left to render damage indicator
local comVX, comVZ = 0, 0

local comUnitDefIDs = {}
for unitDefID, unitDef in pairs(UnitDefs) do
    if unitDef and unitDef.customParams.iscommander then
        comUnitDefIDs[unitDefID] = true
    end
end

local radarUnits = {}
local radarUnitsPos = {}
local unitDefCache = {}

local gameFrame = 0
local myTeamID = Spring.GetMyTeamID()

local commanderIconArm = "Icons/armcom.png"
local commanderIconCore = "Icons/corcom.png"
local commanderIcon = commanderIconArm
local commanderPos = { 0, 0, 0 }

local selectedUnits = {}
local updateSelection = true

local x1, y1, x2, y2 = radarMargin, radarSize, radarMargin + radarSize, 0
local dragging = false

function widget:Initialize()
    if Spring.IsReplay() or Spring.GetGameFrame() > 0 then
        widgetHandler:RemoveWidget()
    end

    -- get our commander's ID
    local units = Spring.GetTeamUnits(myTeamID)
    for i = 1, #units do
        local unitID = units[i]
        local unitDefID = Spring.GetUnitDefID(unitID)
        if comUnitDefIDs[unitDefID] then
            commanderID = unitID
            break
        end
    end
    -- check if it's an arm or core commander
    if commanderID == nil then
        return
    end
    local unitDefID = Spring.GetUnitDefID(commanderID)
    local unitDef = UnitDefs[unitDefID]

    if unitDef.name == "corcom" then
        commanderIcon = commanderIconCore
    end

    if not commanderID then
        return
    end
end

function widget:MousePress(x, y, button)
    if button == 1 then
        -- check if shift key is down
        local _, _, _, shift = Spring.GetModKeyState()

        if x > x1 and x < x2 and y > y2 and y < y1 then
            --Spring.Echo("Clicked on radar")
            if not shift then
                -- we instantly move camera to commander's position
                Spring.SetCameraTarget(commanderPos[1], commanderPos[2], commanderPos[3], 1)
                return true
            else
                dragging = true
                return true
            end
        end
    end
end

function widget:MouseRelease(x, y, button)
    if button == 1 and dragging then
        if x > x1 and x < x2 and y > y2 and y < y1 then
            --Spring.Echo("Released on radar")
            dragging = false
            return true
        end
    end
end

function widget:MouseMove(x, y, dx, dy, button)
    if dragging then
        x1 = x1 + dx
        x2 = x2 + dx
        y1 = y1 + dy
        y2 = y2 + dy
        return true
    end
end

function widget:MouseWheel(up, value)
    local mx, my = Spring.GetMouseState()
    if mx > x1 and mx < x2 and my > y2 and my < y1 then
        if up then
            detectionRadius = detectionRadius * 0.9
        else
            detectionRadius = detectionRadius * 1.1
        end
        -- we need to clamp detectionRadius to a reasonable value, let's say between 500 and 5000
        detectionRadius = math.max(minDetectionRadius, math.min(maxDetectionRadius, detectionRadius))

        drawRatio = radarSize / detectionRadius / 2
        return true
    end
end

local function DrawRadar()
    if commanderID == nil then return end
    local centerX, centerY = x1 + radarSize / 2, y1 - radarSize / 2
    -- Draw radar background
    if recentlyDamaged % 3 == 0 and recentlyDamaged > 0 then
        gl.Color(1, 0, 0, 0.4)
    else
        gl.Color(0, 0, 0, 0.4)
    end
    gl.Rect(x1, y1, x2, y2)

    local function Circle(r)
        for i = 1, 360 do
            local angle = math.rad(i)
            local x = centerX + math.cos(angle) * r
            local y = centerY + math.sin(angle) * r
            gl.Vertex(x, y)
        end
    end

    -- Draw circle with radius 250 (dgun)
    gl.Color(1, 1, 1, 0.44)
    r1 = 250 * drawRatio
    gl.BeginEnd(GL.LINE_LOOP, Circle, r1)

    -- Draw circle with radius 300 (laser)
    gl.Color(1, 1, 1, 0.33)
    r2 = 300 * drawRatio
    gl.BeginEnd(GL.LINE_LOOP, Circle, r2)

    -- Draw circle with detectionRadius
    gl.Color(1, 1, 1, 0.22)
    r3 = detectionRadius * drawRatio
    gl.BeginEnd(GL.LINE_LOOP, Circle, r3)

    -- Draw some dotted lines extending outward from the center
    gl.Color(1, 1, 1, 0.2)
    gl.BeginEnd(GL.LINES, function()
        gl.Vertex(centerX, centerY)
        gl.Vertex(x1, y1)
        gl.Vertex(centerX, centerY)
        gl.Vertex(x2, y1)
        gl.Vertex(centerX, centerY)
        gl.Vertex(x1, y2)
        gl.Vertex(centerX, centerY)
        gl.Vertex(x2, y2)
    end)

    -- Draw commander icon
    if recentlyDamaged % 3 == 0 and recentlyDamaged > 0 then
        gl.Color(1, 0, 0, 1)
    else
        gl.Color(1, 1, 1, 1)
    end
    gl.Texture(commanderIcon) -- Replace with your commander icon texture
    gl.TexRect(centerX + commanderIconSize / 2, centerY - commanderIconSize / 2,
        centerX - commanderIconSize / 2, centerY + commanderIconSize / 2)
    gl.Texture(false)

    -- Draw the movement vector triangle
    local movementVectorX = comVX
    local movementVectorZ = comVZ
    -- Calculate the angle of the movement vector
    local movementAngle = math.atan2(movementVectorZ, movementVectorX)

    -- Calculate the vertices of the triangle
    local triangleSize = 20 -- Size of the triangle
    local vertex1X = centerX + triangleSize * math.cos(movementAngle)
    local vertex1Y = centerY - triangleSize * math.sin(movementAngle)
    local vertex2X = centerX + triangleSize * math.cos(movementAngle + math.pi * 0.9)
    local vertex2Y = centerY - triangleSize * math.sin(movementAngle + math.pi * 0.9)
    local vertex3X = centerX + triangleSize * math.cos(movementAngle - math.pi * 0.9)
    local vertex3Y = centerY - triangleSize * math.sin(movementAngle - math.pi * 0.9)

    -- Draw the triangle
    -- Set color to orange
    gl.Color(1, 0.5, 0, 0.7)
    gl.BeginEnd(GL.TRIANGLES, function()
        gl.Vertex(vertex1X, vertex1Y)
        gl.Vertex(vertex2X, vertex2Y)
        gl.Vertex(vertex3X, vertex3Y)
    end)


    -- Draw hostile units on radar
    gl.Color(1, 0, 0, 1)
    for i = 1, #radarUnits do
        local unitID = radarUnits[i]
        local unitX, unitY, unitZ = radarUnitsPos[unitID][1], radarUnitsPos[unitID][2], radarUnitsPos[unitID][3]

        -- Calculate unit position on radar
        local posX = x1 + radarSize / 2 + (unitX - commanderPos[1]) * drawRatio / radarSize * radarSize
        local posY = y1 - radarSize / 2 - (unitZ - commanderPos[3]) * drawRatio / radarSize * radarSize -- Invert Y-axis

        local unitDef = unitDefCache[unitID]
        if unitDef then
            -- Draw a small dot on the radar
            -- if the unit is a commander, draw a red version of the commander icon
            if comUnitDefIDs[unitDef.id] then
                gl.Color(1, 0, 0, 1)
                gl.Texture(commanderIcon) -- Replace with your commander icon texture
                gl.TexRect(posX + commanderIconSize / 2, posY - commanderIconSize / 2,
                    posX - commanderIconSize / 2, posY + commanderIconSize / 2)
                gl.Texture(false)
            else
                -- determine the size by the unit's actual size
                local unitSize = unitDef.radius
                gl.PointSize(unitSize / 5)
                local function Vertex()
                    gl.Vertex(posX, posY)
                end
                gl.BeginEnd(GL.POINTS, Vertex)
            end
        end
    end

    -- Draw commander health bar background
    gl.Color(0, 0, 0, 0.5)
    gl.Rect(x1, y1, x1 + healthBarWidth, y1 + healthBarHeight)

    -- Draw commander health bar
    local healthBarColor = { 1 - (commanderHealth / commanderMaxHealth), commanderHealth / commanderMaxHealth, 0, 1 }
    gl.Color(healthBarColor)
    gl.Rect(x1, y1, x1 + healthBarWidth * (commanderHealth / commanderMaxHealth),
        y1 + healthBarHeight)

    gl.Color(1, 1, 1, 1) -- Reset color

    -- Finally we add a small text to the top left denoting the current detectionRadius
    -- if we're at max or min radius, we color it red and denote it with (max) or (min)
    local minMaxString = ""
    if detectionRadius == minDetectionRadius or detectionRadius == maxDetectionRadius then
        gl.Color(1, 0.8, 0.8, 1)
        minMaxString = " (" .. (detectionRadius == minDetectionRadius and "min" or "max") .. ")"
    end
    gl.Text("Radar range: " .. string.format("%.2f", detectionRadius) .. minMaxString, x1, y2 + 12, 12, "o")

    --gl.Text("Radar range: " .. string.format("%.2f", detectionRadius), x1, y2 + 12, 12, "o")
end

function widget:GameFrame(n)
    gameFrame = n
end

function widget:Update(dt)
    -- if we already have at least one commander, we might want to check if we have and are selecting another
    if gameFrame % 30 == 0 and updateSelection then
        updateSelection = false
        for i = 1, #selectedUnits do
            local unitID = selectedUnits[i]
            if comUnitDefIDs[Spring.GetUnitDefID(unitID)] then
                commanderID = unitID
                return
            end
        end
    end

    -- update our commander and radar units positions every 3 frames
    if gameFrame % 3 == 2 and commanderID then
        commanderPos[1], commanderPos[2], commanderPos[3] = Spring.GetUnitPosition(commanderID)
        if commanderPos[1] == nil then
            commanderHealth = 0
            commanderMaxHealth = 0
            commanderID = nil
            return
        end
        radarUnits = Spring.GetUnitsInCylinder(commanderPos[1], commanderPos[3], detectionRadius, Spring.ENEMY_UNITS)
        commanderHealth, commanderMaxHealth, _, _, _ = Spring.GetUnitHealth(commanderID)
        comVX, _, comVZ = Spring.GetUnitVelocity(commanderID)

        -- update unit positions
        for i = 1, #radarUnits do
            local unitID = radarUnits[i]
            if unitDefCache[unitID] == nil then
                unitDefCache[unitID] = UnitDefs[Spring.GetUnitDefID(unitID)]
            end

            local x, y, z = Spring.GetUnitPosition(unitID)
            if not radarUnitsPos[unitID] then
                radarUnitsPos[unitID] = {}
            end
            radarUnitsPos[unitID][1], radarUnitsPos[unitID][2], radarUnitsPos[unitID][3] = x, y, z
        end
        -- finally let's also update drawRatio
        drawRatio = radarSize / (detectionRadius * 2)
    end

    -- update our recentlyDamaged counter every 10 frames
    if gameFrame % 10 == 1 then
        recentlyDamaged = recentlyDamaged - 10
    end
end

function widget:DrawScreen()
    DrawRadar()
end

-- if a commander is gifted, we may need to update the commanderID
function widget:UnitGiven(unitID, unitDefID, newTeam, oldTeam)
    if comUnitDefIDs[unitDefID] and (newTeam == myTeamID) then
        if commanderID then
            return -- don't update if we already have a commander
        end
        commanderID = unitID
    end
end

-- if a commander is destroyed, we may need to update the commanderID
function widget:UnitDestroyed(unitID, unitDefID, unitTeam)
    if comUnitDefIDs[unitDefID] and (unitID == commanderID) then
        commanderID = nil
    end
end

-- if a commander is created (rezzed), we may need to update the commanderID
function widget:UnitCreated(unitID, unitDefID, unitTeam)
    if comUnitDefIDs[unitDefID] and (unitTeam == myTeamID) then
        if commanderID then
            return -- don't update if we already have a commander
        end
        commanderID = unitID
    end
end

-- if a commander is found through issuing commands, we may need to update the commanderID
function widget:UnitCommand(unitID, unitDefID, unitTeam, cmdID, cmdParams, cmdOpts, cmdTag)
    if comUnitDefIDs[unitDefID] and (unitTeam == myTeamID) then
        if commanderID then
            return -- don't update if we already have a commander
        end
        commanderID = unitID
    end
end

-- if commander is damaged we increment the recentlyDamaged counter
function widget:UnitDamaged(unitID, unitDefID, unitTeam, damage, paralyzer, weaponID, attackerID,
                            attackerDefID, attackerTeam)
    if unitID == commanderID then
        recentlyDamaged = 60 -- 60 frames = 2 seconds
    end
end

-- If we're selecting a commander we might want to display that commander's radar range
function widget:SelectionChanged(sel)
    selectedUnits = sel
    updateSelection = true
end

-- save the x1, y1, x2, y2 values for the radar to config so next time widget loads from it
function widget:GetConfigData()
    return { x1, y1, x2, y2, detectionRadius }
end

-- load the x1, y1, x2, y2 values for the radar from config
function widget:SetConfigData(data)
    if data then
        x1, y1, x2, y2 = data[1] or radarMargin, data[2] or radarSize, data[3] or radarMargin + radarSize, data[4] or 0
        detectionRadius = data[5] or 1000
    else
        x1, y1, x2, y2 = radarMargin, radarSize, radarMargin + radarSize, 0
        detectionRadius = 1000
    end
end
