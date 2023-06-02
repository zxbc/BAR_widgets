function widget:GetInfo()
    return {
        name      = "Pipette Build",
        desc      = "Copy a blueprint of the unit/building under the mouse cursor. Default keybind 'shift-q'. If you copy on top of empty space, the previously successfully copied blueprint will be used again.",
        author    = "Errrrrrr",
        date      = "May 20, 2023",
        license   = "GNU GPL, v2 or later",
        version   = "1.0",
        layer     = 0,
        enabled   = true,
        handler   = true
    }
end

-------------------------------------------------------------------------------------
-- Default keybind is "shift-q"
--
-- Set custom_keybind_mode to true for custom keybind.
-- Bindable action name: pipette_build
-------------------------------------------------------------------------------------
local custom_keybind_mode = false

local targetUnitID

local build_sound = 'Sounds/commands/cmd-build.wav'

function widget:Initialize()
    targetUnitID = nil
    widgetHandler.actionHandler:AddAction(self, "pipette_build", pipetteBuild, nil, "p")
end

function widget:Shutdown()
    targetUnitID = nil
end

function pipetteBuild(_, _, args)
  doCopy()
end

function widget:KeyPress(key, mods, isRepeat)
  if not custom_keybind_mode then
    if key == 113 and mods.shift then -- shift + q
        doCopy()
    end
  end
end

function doCopy()
  -- Get the mouse coordinates
  local x, y = Spring.GetMouseState()

  local oldTarget = targetUnitID  -- save it in case blueprint copy fails

  -- Get the unit/building ID under the cursor
  local desc, args = Spring.TraceScreenRay(x, y, false, true, true, true)
  --Spring.Echo("desc: " .. tostring(desc)..", args: "..tableToString(args))
  if desc == "unit" then
      targetUnitID = args  -- Set the target unit ID
  end
  --Spring.Echo("Selected unit/building ID: " .. targetUnitID)
  local success = SetActiveCommandToBuild()
  if not success then targetUnitID = oldTarget end
end

-- returns true if successful
function SetActiveCommandToBuild()
    if targetUnitID then
        -- Check if any selected unit is a builder and can build the target unit
        local selectedUnits = Spring.GetSelectedUnits()
        if #selectedUnits == 0 then return end

        for _, unitID in ipairs(selectedUnits) do
            local unitDefID = Spring.GetUnitDefID(unitID)
            local unitDef = UnitDefs[unitDefID]
            local targetDefID = Spring.GetUnitDefID(targetUnitID)
            local targetDef = UnitDefs[targetDefID]

            if unitDef and unitDef.isBuilder and canBuild(unitDefID, targetDefID) then
                    -- Set the active command to build the target unit
                if Spring.SetActiveCommand('buildunit_'..targetDef.name) then
                    --Spring.Echo("Blueprint successfully copied")
                    Spring.PlaySoundFile(build_sound, 0.3, 'ui')
                    return true
                end
                break
            end
        end
        return false
    end
end

function canBuild(builderDefID, targetDefID)
    local builderDef = UnitDefs[builderDefID]
  
    -- Check if both the builder and target unit definitions exist
    if builderDef and targetDefID then
        -- Check if the target unit's ID is present in the builder's buildOptions
        for _, buildOptionID in ipairs(builderDef.buildOptions) do
            if buildOptionID == targetDefID then
                return true  -- Builder can build the target unit
            end
        end
    end

    return false  -- Builder cannot build the target unit
end

-- helper
function tableToString(t)
    local result = ""
  
    if type(t) ~= "table" then
      result = tostring(t)
    elseif t == nil then
      result = "nil"
    else
      for k, v in pairs(t) do
        result = result .. "[" .. tostring(k) .. "] = "
  
        if type(v) == "table" then
          result = result .. "{"
  
          for k2, v2 in pairs(v) do
            result = result .. "[" .. tostring(k2) .. "] = "
  
            if type(v2) == "table" then
              result = result .. "{"
  
              for k3, v3 in pairs(v2) do
                result = result .. "[" .. tostring(k3) .. "] = " .. tostring(v3) .. ", "
              end
  
              result = result .. "}, "
            else
              result = result .. tostring(v2) .. ", "
            end
          end
  
          result = result .. "}, "
        else
          result = result .. tostring(v) .. ", "
        end
      end
    end
  
    return "{" .. result:sub(1, -3) .. "}"
end