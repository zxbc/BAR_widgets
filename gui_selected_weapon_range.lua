function widget:GetInfo()
    return {
        name      = "Selected Units Weapon Range",
        desc      = "Displays range circles of selected units' weapons at all time. Press m key to toggle on/off; press , key to cycle through colors; press . key to cycle through display modes. All keys rebindable, please read file for details.",
        author    = "Errrrrrr",
        date      = "May 2023",
        version   = "1.4",
        license   = "GNU GPL, v2 or later",
        layer     = 0,
        enabled   = true,
        handler   = true,
    }
end

-----------------------------------------------------------------------------------------
-- Version 1.4:
-- What's new: 
-- -- Optimized some code and increased max number of ranges displayed by default to 100
-- -- Added display of build ranges.
-- -- Now displays max weapon range for all units.
-- -- Displays a separate dgun range for commander. Comm alpha set to max to stand out.
-- -- Tweaked max and min saturation (should no longer see overly bright or dim display).
-- 
-- Set "custom_keybind_mode" to true to use your own keys.
-- Bindable actions:   weapon_range_toggle
--                     weapon_range_cycle_color_mode
--                     weapon_range_cycle_display_mode
--
-- Default keybinds: 
-- Press 'm' key to toggle on and off range display of selected units (default on)
-- Press ',' key to cycle between white, red, green, and blue color modes (default white)
-- Press '.' key to cycle between filled, empty and combined modes (default filled)
-----------------------------------------------------------------------------------------

local maxDrawDistance = 5000    -- Max camera distance at which to draw ranges of selected units (default 5000)
local maxNumRanges = 80         -- Max number of ranges to display (default 100)
                                -- If you select more than this number of units, only this many will be drawn, starting from highest ranges
local alpha = 0.07              -- Alpha value for the drawing (default at 0.07)
                                -- Remember circles overlap and become denser in color!
local custom_keybind_mode = false  -- set to true if you want to use custom keybinds
                                  -- set to false to enable default keybinds

-- Vars
local selChanged = true
local selectedUnits = {}
local weaponRanges = {}

local toggle = true
local colorMode = 0
local colorModeNames = { "white", "red", "green", "blue" }
local displayMode = 0

local isCommander = {}
for unitDefID, unitDef in pairs(UnitDefs) do
	if unitDef.customParams.iscommander then
		isCommander[unitDefID] = true
	end
end

-- speed up
local Echo = Spring.Echo
local GetSelectedUnits = Spring.GetSelectedUnits
local GetUnitWeaponState = Spring.GetUnitWeaponState
local GetUnitDefID = Spring.GetUnitDefID
local GetCameraPosition = Spring.GetCameraPosition
local GetUnitPosition = Spring.GetUnitPosition
local GetCameraState = Spring.GetCameraState

local glDepthTest = gl.DepthTest
local glBlending = gl.Blending
local glColor = gl.Color
local glCulling = gl.Culling
local glBeginEnd = gl.BeginEnd
local glDrawGroundCircle = gl.DrawGroundCircle
local glLineWidth = gl.LineWidth
local glPopMatrix = gl.PopMatrix
local glPushMatrix = gl.PushMatrix
local glTranslate = gl.Translate
local glVertex = gl.Vertex
local GLTRIANGLE_FAN = GL.TRIANGLE_FAN
local GLBACK = GL.BACK

local sqrt = math.sqrt
local sin = math.sin
local cos = math.cos
local pi = math.pi

local insert = table.insert
local remove = table.remove
local sort = table.sort

local function GetUnitDef(unitID)
    local unitDefID = GetUnitDefID(unitID)
    if unitDefID then
        local unitDef = UnitDefs[unitDefID]
        return unitDef
    end
    return nil
end

-- Initialize the widget
function widget:Initialize()
    selectedUnits = {}
    weaponRanges = {}

    if custom_keybind_mode then
        widgetHandler.actionHandler:AddAction(self, "weapon_range_toggle", toggleRange, nil, "p")
        widgetHandler.actionHandler:AddAction(self, "weapon_range_cycle_color_mode", cycleColorMode, nil, "p")
        widgetHandler.actionHandler:AddAction(self, "weapon_range_cycle_display_mode", cycleDisplayMode, nil, "p")
    end
end

function widget:Shutdown()
    selectedUnits = {}
    weaponRanges = {}
end

function widget:SelectionChanged(sel)
    selChanged = true
end

function toggleRange(_, _, args)
    toggle = not toggle
    Echo("Weapon range toggled on: " .. tostring(toggle))
end

function cycleColorMode(_, _, args)
    colorMode = (colorMode + 1) % 4
    Echo("Weapon range color switched to: " .. colorModeNames[colorMode+1])
end

function cycleDisplayMode(_, _, args)
    displayMode = (displayMode + 1) % 3
    Echo("Weapon range display mode switched to: " .. displayMode)
end

function widget:KeyPress(key, mods, isRepeat)
    if not custom_keybind_mode then
        if key == 109 then -- 109 is m
            toggleRange()
        end
        if key == 44 then -- 44 is ,
            cycleColorMode()
        end
        if key == 46 then -- 46 is .
            cycleDisplayMode()
        end
    end
end

-- Update the widget with the latest information at 0.1s intervals
local delaySec = 0
function widget:Update(dt)
    delaySec = delaySec + dt
    if delaySec < 0.1 or not selChanged then return end

    delaySec = 0
    selChanged = false
    selectedUnits = GetSelectedUnits()
    --Echo("units selected: " .. #selectedUnits)
    weaponRanges = {}

    -- Loop through each selected unit and get its weapon ranges
    local j = 1
    for i=1, #selectedUnits do
        --local weaponRange = GetUnitWeaponState(unitID, 1, "range")
        local unitID = selectedUnits[i]
        local unitDef = GetUnitDef(unitID)
        if unitDef then
            local weaponRange = nil
            -- if it's a builder, we display build range instead
            if unitDef.isBuilder then
                weaponRange = unitDef.buildDistance
            else -- normal unit
                weaponRange = unitDef.maxWeaponRange
            end

            -- Commander and units with very long range always get displayed
            if weaponRange and (#weaponRanges < maxNumRanges or isCommander[unitDef.id] or weaponRange > 800) then
                if isCommander[unitDef.id] then -- let's also add dgun range
                    local dgunRange = GetUnitWeaponState(unitID, 3, "range")
                    local fireRange = unitDef.maxWeaponRange
                    weaponRanges[j] = {unitID = unitID, range = weaponRange, factor = 50}
                    weaponRanges[j+1] = {unitID = unitID, range = dgunRange, factor = 50}
                    weaponRanges[j+2] = {unitID = unitID, range = fireRange, factor = 50}
                    j = j + 3
                else
                    weaponRanges[j] = {unitID = unitID, range = weaponRange, factor = 1}
                    j = j + 1
                end
            end

        end
    end
end

-- Draw stuff
function widget:DrawWorldPreUnit()
    if not selectedUnits or not weaponRanges or not toggle then return end

    local curHeight
    local camState = GetCameraState()
    if (camState.name == "ta") then 
        curHeight = camState.height
    elseif (camState.name == "spring") then 
        curHeight = camState.dist 
    end
    if curHeight and curHeight > maxDrawDistance then return end

--[[     if #weaponRanges > maxNumRanges then   -- too many ranges to render
        -- let's sort by range, long to short
        local function longToShort()
            return a.range > b.range
        end
        sort(weaponRanges, longToShort)
    end ]]

    glDepthTest(false)
    --glCulling(GLBACK)
    glBlending ("alpha")

    for i, weaponRange in ipairs(weaponRanges) do
        local unitID = weaponRange.unitID
        local range = weaponRange.range
        local x, y, z = GetUnitPosition(unitID)
        if not x or not y or not z then break end

        glPushMatrix()

        c = range / 800   -- some reduction to saturation based on range and num units selected
        c = c / (#weaponRanges * 0.22) * weaponRange.factor
        c = c > 1 and 1 or c
        c = c < 0.1 and 0.1 or c
        local cColor = {1, 1, 1, 0.5}
        if colorMode == 0 then
            cColor = {1, 1, 1, c*alpha}
        elseif colorMode == 1 then
            cColor = {0.7, 0.3, 0.3, c*alpha}
        elseif colorMode == 2 then
            cColor = {0.3, 0.7, 0.3, c*alpha}
        elseif colorMode == 3 then
            cColor = {0.3, 0.3, 0.7, c*alpha}
        end

        -- display modes: 0 - filled, 1 - empty, 2 - combined
        -- draw empty circle
        if displayMode ~= 0 then
            glColor(cColor[1], cColor[2], cColor[3], alpha * 1.5)
            glLineWidth(3)
            glDrawGroundCircle(x, y, z, range, 32)
        end

        local function drawCircle()
            local numSegments = 32
            local angleStep = (2 * pi) / numSegments
            for i = 0, numSegments do
                local angle = i * angleStep
                glVertex(sin(angle) * range, 0, cos(angle) * range)
            end
        end

        -- draw filled circle
        if displayMode ~= 1 then
            glTranslate(x, y, z)
            glColor(cColor[1], cColor[2], cColor[3], cColor[4])
            glBeginEnd(GLTRIANGLE_FAN, drawCircle)
        end
        glPopMatrix()
    end
    glBlending ("reset")
    glDepthTest(true)
end

