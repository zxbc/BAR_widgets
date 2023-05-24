function widget:GetInfo()
    return {
        name      = "Smart Commands",
        desc      = "Smart cast any command. Key down to set command active, key up to issue command",
        author    = "Errrrrrr",
        date      = "May 2023",
        license   = "GNU GPL, v2 or later",
        layer     = -9999,
        enabled   = true,
        handler   = true,
    }
end

local retain_aiming = false

local selectedUnits = {}
local curCmd
local active = false
local mouseClicked = false

function widget:MousePress(x, y, button)
    if active then
        mouseClicked = true
    end
end

function widget:KeyPress(key, mods, isRepeat)
    if isRepeat then
        active = true
    end
    return false
end

function widget:KeyRelease(key)
    local cmdIndex, cmdID, cmdType, cmdName = Spring.GetActiveCommand()
    if cmdID ~= nil and cmdID > 0 then  -- skip build commands
        curCmd = cmdID
        executeCommand()
    end
end

function widget:SelectionChanged(sel)
    selectedUnits = sel
end

function executeCommand()
    if mouseClicked then -- this is kind of a hack to reset active command
        mouseClicked = false
        Spring.SetActiveCommand(0)
        return 
    end
    if curCmd ~= nil then
        local mouseX, mouseY = Spring.GetMouseState()
        local desc, args = Spring.TraceScreenRay(mouseX, mouseY, false)
        if desc == nil then 
            return 
        end

        local params = {}
        if desc == "unit" then
            params = {args}
        elseif desc == "feature" then
            params = {args+32000} -- seriously wtf
        else
            params = {args[1], args[2], args[3]}
        end
        local alt, ctrl, meta, shift = GetModKeys()
        local cmdOpts
        local altOpts = GetCmdOpts(true, false, false, false, false)
        if meta then
            cmdOpts = GetCmdOpts(alt, ctrl, false, shift, false)
            Spring.GiveOrderToUnitArray(selectedUnits, CMD.INSERT, {0, curCmd, cmdOpts.coded, unpack(params)}, altOpts)
        else
            cmdOpts = GetCmdOpts(alt, ctrl, meta, shift, false)
            Spring.GiveOrderToUnitArray(selectedUnits, curCmd, params, cmdOpts)
        end
        if not retain_aiming then
            Spring.SetActiveCommand(0)
        end
        curCmd = nil
    end
end

function widget:UnitCommand(unitID, unitDefID, unitTeam, cmdID, cmdParams, cmdOpts, cmdTag)
    if mouseClicked then
        active = false
        curCmd = nil
        Spring.SetActiveCommand(0)
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