function widget:GetInfo()
    return {
        name      = "Instant Dgun",
        desc      = "Instantly fire dgun. Default keybind 'd', rebindable.",
        author    = "Errrrrrr",
        date      = "May 23, 2023",
        license   = "GNU GPL, v2 or later",
        layer     = -9999,
        enabled   = true,
        handler   = true,
    }
end

--------------------------------------------------------------------------------
-- Set custom_keybind_mode to false to use default 'd' keybind
-- Custom keybind action name: instant_dgun
--------------------------------------------------------------------------------
local custom_keybind_mode = false

local isCommander = {}
for unitDefID, unitDef in pairs(UnitDefs) do
	if unitDef.customParams.iscommander then
		isCommander[unitDefID] = true
	end
end

function widget:Initialize()
    if custom_keybind_mode then
        widgetHandler.actionHandler:AddAction(self, "instant_dgun", dgunBind, nil, "p")
    end
end

function dgunBind(_, _, args)
    fireDgun()
end

function widget:KeyPress(key, mods, isRepeat)
    if not custom_keybind_mode and key == 100 and not isRepeat then
        fireDgun()
    end
end

-- return true if selecting only commander and command was successful
function fireDgun()
    local selectedUnits = Spring.GetSelectedUnits()
        if #selectedUnits == 1 then
            local selectedUnitID = selectedUnits[1]
            if isCommander[Spring.GetUnitDefID(selectedUnitID)] then
                local mouseX, mouseY = Spring.GetMouseState()
                local desc, args = Spring.TraceScreenRay(mouseX, mouseY, true)
                
                if desc and desc == "unit" then
                    local targetUnitID = args
                    Spring.GiveOrderToUnit(selectedUnitID, CMD.DGUN, { targetUnitID }, {})
                elseif desc and desc == "ground" then
                    Spring.GiveOrderToUnit(selectedUnitID, CMD.DGUN, { args[1],args[2],args[3] }, {})
                end             
                return true
            end
        end
end
