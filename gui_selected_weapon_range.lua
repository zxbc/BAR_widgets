function widget:GetInfo()
    return {
        name      = "Selected Units Weapon Range",
        desc      = "Displays range circles of selected units' weapons at all time. Press m key to toggle on/off; press , key to cycle through colors; press . key to cycle through display modes.",
        author    = "Errrrrrr",
        date      = "May 2023",
        version   = "1.2",
        license   = "GNU GPL, v2 or later",
        layer     = 0,
        enabled   = true,
        handler   = true,
    }
end

-----------------------------------------------------------------------------------------
-- Version 1.2:
-- Only displays the range of the first weapon of a unit for now
-- *ADDED CUSTOM KEYBINDS SUPPORT. 
--  Set "custom_keybind_mode" to true to use your own keys
--  Bindable actions:  weapon_range_toggle
--                     weapon_range_cycle_color_mode
--                     weapon_range_cycle_display_mode
--
-- Default keybinds: 
-- Press 'm' key to toggle on and off range display of selected units (default on)
-- Press ',' key to cycle between white, red, green, and blue color modes (default white)
-- Press '.' key to cycle between filled, empty and combined modes (default filled)
-----------------------------------------------------------------------------------------

local maxDrawDistance = 5000    -- Max camera distance at which to draw ranges of selected units (default 5000)
local maxNumRanges = 50         -- Max number of ranges to display (default 50)
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

-- Initialize the widget
function widget:Initialize()
    selectedUnits = {}
    weaponRanges = {}
    widgetHandler:RegisterGlobal('KeyPress', function(key, mods, isRepeat)
        return self:KeyPress(key, mods, isRepeat)
    end)
    widgetHandler.actionHandler:AddAction(self, "weapon_range_toggle", toggleRange, nil, "p")
    widgetHandler.actionHandler:AddAction(self, "weapon_range_cycle_color_mode", cycleColorMode, nil, "p")
    widgetHandler.actionHandler:AddAction(self, "weapon_range_cycle_display_mode", cycleDisplayMode, nil, "p")
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
    Spring.Echo("Weapon range toggled on: " .. tostring(toggle))
end

function cycleColorMode(_, _, args)
    colorMode = (colorMode + 1) % 4
    Spring.Echo("Weapon range color switched to: " .. colorModeNames[colorMode+1])
end

function cycleDisplayMode(_, _, args)
    displayMode = (displayMode + 1) % 3
    Spring.Echo("Weapon range display mode switched to: " .. displayMode)
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
    selectedUnits = Spring.GetSelectedUnits()
    --Spring.Echo("units selected: " .. #selectedUnits)
    weaponRanges = {}

    -- Loop through each selected unit and get its weapon ranges
    for i, unitID in ipairs(selectedUnits) do
        --local weaponRange = Spring.GetUnitWeaponState(unitID, 1, "range")
        local unitDef = GetUnitDef(unitID)
        if unitDef then
            local weaponRange = unitDef.maxWeaponRange
            if weaponRange then
                table.insert(weaponRanges, {unitID = unitID, range = weaponRange})
            end
        end
    end
end

-- Draw stuff
function widget:DrawWorldPreUnit()
    if not selectedUnits or not weaponRanges or not toggle then return end
    if #weaponRanges > maxNumRanges then   -- too many ranges to render
        -- let's sort by range, high to low
        table.sort(weaponRanges, function(a, b) return a.range > b.range end)
        while #weaponRanges > maxNumRanges do
            table.remove(weaponRanges)  -- default removes from end (shortest)
          end
    end
    --Spring.Echo("weaponRanges to draw: " .. #weaponRanges)

    gl.DepthTest(false)
    gl.Culling(GL.BACK)

    local camX, camY, camZ = Spring.GetCameraPosition()
    for i, weaponRange in ipairs(weaponRanges) do
        local unitID = weaponRange.unitID
        local range = weaponRange.range
        local x, y, z = Spring.GetUnitPosition(unitID)
        if not x or not y or not z then break end

        local dist = math.sqrt((x - camX) ^ 2 + (y - camY) ^ 2 + (z - camZ) ^ 2)

        if dist < maxDrawDistance then
            gl.PushMatrix()
            gl.Blending ("alpha")

            c = range / 600   -- some reduction to saturation based on range and num units selected
            c = c / (#weaponRanges * 0.15)
            c = c > 1 and 1 or c
            local cColor = {1, 1, 1, 0.5}
            if colorMode == 0 then
                cColor = {1, 1, 1, c*alpha}
            elseif colorMode == 1 then
                cColor = {1, 0, 0, c*alpha}
            elseif colorMode == 2 then
                cColor = {0, 1, 0, c*alpha}
            elseif colorMode == 3 then
                cColor = {0, 0, 1, c*alpha}
            end

            -- display modes: 0 - empty circles, 1 - filled circles, 2 - combined
            -- draw empty circle
            if displayMode ~= 0 then
                gl.Color(cColor[1], cColor[2], cColor[3], alpha * 1.2)
                gl.LineWidth(3)
                gl.DrawGroundCircle(x, y, z, range, 32)
            end

            -- draw filled circle
            if displayMode ~= 1 then
                gl.Translate(x, y, z)
                gl.Color(cColor[1], cColor[2], cColor[3], cColor[4])
                gl.BeginEnd(GL.TRIANGLE_FAN, function()
                local numSegments = 32
                local angleStep = (2 * math.pi) / numSegments
                for i = 0, numSegments do
                    local angle = i * angleStep
                    gl.Vertex(math.sin(angle) * range, 0, math.cos(angle) * range)
                end
                end)
            end
            gl.Blending ("reset")
            gl.PopMatrix()
        end
    end
    gl.DepthTest(true)
end

function GetUnitDef(unitID)
    local unitDefID = Spring.GetUnitDefID(unitID)
    if unitDefID then
        local unitDef = UnitDefs[unitDefID]
        return unitDef
    end
    return nil
end


