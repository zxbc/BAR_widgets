function widget:GetInfo()
    return {
        name      = "Selected Units Weapon Range",
        desc      = "Displays the range of selected units' weapons. Press \\ key to toggle on/off, press ] key to cycle through colors",
        author    = "Errrrrrr",
        date      = "May 2023",
        version   = "1.0",
        license   = "GNU GPL, v2 or later",
        layer     = 0,
        enabled   = true,
        handler   = true,
    }
end

---------------------------------------------------------------------------------
-- Version 1.0:
-- Only displays the range of the first weapon of a unit for now
-- Press '\' key to toggle on and off range display of selected units (default on)
-- Press ']' key to cycle between white, red, green, and blue color modes
-- maxDrawDistance default at 5000
-- maxNumRanges default at 50 (lonest 50 ranges will be displayed if selected more)
-- Alpha default at 0.06 (remember circles overlap and become denser!)
---------------------------------------------------------------------------------

local maxDrawDistance = 5000    -- Max camera distance at which to draw ranges of selected units
local maxNumRanges = 50         -- Max number of ranges to display. Too high a value can cause fps drop!
                                -- If you select more than this number of units, only this many will be drawn, sorted by longest ranges
local alpha = 0.06

-- Vars
local WEAPON_RANGE_TYPES = {"Ground", "Air", "Submerged"}  -- Types of weapon ranges to display
local selChanged = false
local selectedUnits = {}
local weaponRanges = {}

local toggle = true
local colorMode = 0
local colorModeNames = { "white", "red", "green", "blue" }

-- Initialize the widget
function widget:Initialize()
    selectedUnits = {}
    weaponRanges = {}
    widgetHandler:RegisterGlobal('KeyPress', function(key, mods, isRepeat)
        return self:KeyPress(key, mods, isRepeat)
    end)
end

function widget:Shutdown()
    selectedUnits = {}
    weaponRanges = {}
end

function widget:SelectionChanged(sel)
    selChanged = true
end

function toggleRange()
    toggle = not toggle
    Spring.Echo("Weapon range toggled on: " .. tostring(toggle))
end

function cycleColorMode()
    colorMode = (colorMode + 1) % 4
    Spring.Echo("Weapon range color switched to: " .. colorModeNames[colorMode+1])
end

function widget:KeyPress(key, mods, isRepeat)
    if key == 92 then -- 92 is forward slash '\'
        toggleRange()
    end
    if key == 93 then -- 93 is right bracket ']'
        cycleColorMode()
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
        local weaponRange = Spring.GetUnitWeaponState(unitID, 1, "range")
        if weaponRange then
            table.insert(weaponRanges, {unitID = unitID, range = weaponRange})
        end
    end
end

--[[ function drawCircle(uID, coverageRange, x, y, z, camX, camY, camZ)
	local lineOpacityMultiplier = transparency * 2

	if lineOpacityMultiplier > 0 then
        local circleColor = {1, 1, 0, 0.5}

		glColor(circleColor[1],circleColor[2],circleColor[3], lineOpacityMultiplier)
		glLineWidth(1)
		glDrawGroundCircle(x, y, z, coverageRange, 128)
	end
end ]]

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
    gl.Texture(0, "$heightmap")

    local camX, camY, camZ = Spring.GetCameraPosition()
    for i, weaponRange in ipairs(weaponRanges) do
        local unitID = weaponRange.unitID
        local range = weaponRange.range
        local x, y, z = Spring.GetUnitPosition(unitID)
        if not x or not y or not z then break end

        local dist = math.sqrt((x - camX) ^ 2 + (y - camY) ^ 2 + (z - camZ) ^ 2)

        if dist < maxDrawDistance then
            gl.PushMatrix()
            gl.Translate(x, y, z)
      
            c = 5 / #weaponRanges * range / 1000    -- some reduction to saturation based on range and num units selected
            c = c > 1 and 1 or c
            if colorMode == 0 then
                gl.Color(c, c, c, alpha)
            elseif colorMode == 1 then
                gl.Color(c, 0, 0, alpha)
            elseif colorMode == 2 then
                gl.Color(0, c, 0, alpha)
            elseif colorMode == 3 then
                gl.Color(0, 0, c, alpha)
            end

            gl.BeginEnd(GL.TRIANGLE_FAN, function()
              local numSegments = 32
              local angleStep = (2 * math.pi) / numSegments
              for i = 0, numSegments do
                local angle = i * angleStep
                gl.Vertex(math.sin(angle) * range, 0, math.cos(angle) * range)
              end
            end)

            gl.PopMatrix()
        end
    end
    gl.Texture(0, false)
    gl.DepthTest(true)
end


