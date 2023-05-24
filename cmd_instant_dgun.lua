function widget:GetInfo()
    return {
        name      = "Instant Dgun",
        desc      = "Aims when you press key down, fires when you release. Default keybind 'd', rebindable.",
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
-- Set retain_aiming to true if you want the dgun aim to stay up after firing
--------------------------------------------------------------------------------
local custom_keybind_mode = false
local retain_aiming = false

local isCommander = {}
for unitDefID, unitDef in pairs(UnitDefs) do
	if unitDef.customParams.iscommander then
		isCommander[unitDefID] = true
	end
end

local commID

function widget:Initialize()
    if custom_keybind_mode then
        widgetHandler.actionHandler:AddAction(self, "instant_dgun_press", showDgun, nil, "R")
        widgetHandler.actionHandler:AddAction(self, "instant_dgun_release", fireDgun, nil, "r")
    end
end

function dgunPress(_, _, args)
    showDgun()
end

function dgunRelease(_, _, args)
    fireDgun()
end

function widget:KeyPress(key, mods, isRepeat)
    if not custom_keybind_mode and key == 100 and isRepeat then
        return showDgun()   -- blocks other keypress if showDgun finds commander
    end
end

function widget:KeyRelease(key)
    if not custom_keybind_mode and key == 100 then
        local result = fireDgun()
    end
end

function showDgun()
    if commID then
        Spring.SetActiveCommand('dgun')
        return true
    end
    
end

function widget:SelectionChanged(sel)
    
    if #sel == 1 and isCommander[Spring.GetUnitDefID(sel[1])] then
        commID = sel[1]
    else
        commID = nil
    end
end


-- return true if selecting only commander and command was successful
function fireDgun()
    if commID then
        local mouseX, mouseY = Spring.GetMouseState()
        local desc, args = Spring.TraceScreenRay(mouseX, mouseY, true)
        
        local params
        if desc and desc == "unit" then
            params = {args}
        elseif desc and desc == "ground" then
            params = {args[1], args[2], args[3]}
        end
    
        local alt, ctrl, meta, shift = GetModKeys()
        local cmdOpts = GetCmdOpts(alt, ctrl, meta, shift, false)
        local altOpts = GetCmdOpts(true, false, false, false, false)
        Spring.GiveOrderToUnit(commID, CMD.INSERT, {0, CMD.DGUN, cmdOpts.coded, unpack(params)}, altOpts)
        --Spring.GiveOrderToUnit(commID, CMD.DGUN, params, cmdOpts)
        if not retain_aiming then
            Spring.SetActiveCommand(0)
        end
        return true
    else
        return false
    end
  
end

function GetModKeys()
    local alt, ctrl, meta, shift = Spring.GetModKeyState()
  
    if Spring.GetInvertQueueKey() then -- Shift inversion
        shift = not shift
    end
  
    return alt, ctrl, meta, shift
end

function GetCmdOpts(alt, ctrl, meta, shift, right)
    local opts = { alt=alt, ctrl=ctrl, meta=meta, shift=shift, right=right }
    local coded = 0
  
    if alt   then coded = coded + CMD.OPT_ALT   end
    if ctrl  then coded = coded + CMD.OPT_CTRL  end
    if meta  then coded = coded + CMD.OPT_META  end
    if shift then coded = coded + CMD.OPT_SHIFT end
    if right then coded = coded + CMD.OPT_RIGHT end
  
    opts.coded = coded
    return opts
end
