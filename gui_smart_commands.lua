function widget:GetInfo()
    return {
        name      = "Smart Commands",
        desc      = "Smart cast any command. Key down to set command active, key up to issue command",
        author    = "Errrrrrr",
        date      = "May 2023",
        license   = "GNU GPL, v2 or later",
        version   = "1.0",
        layer     = -9999,
        enabled   = true,
        handler   = true,
    }
end

--------------------------------------------------------------------------------------------
-- insert_mode toggle makes all commands issued automatically inserted at front of queue
-- If you use insert_mode, meta + key will be normal mode
-- Bind action "gui_smart_commands_insert_mode_toggle" to use custom key bind toggle
--------------------------------------------------------------------------------------------
local insert_mode = false

local retain_aiming = false
local enabled = true
local selectedUnits = {}
local active = false
local mouseClicked = false

local echo = Spring.Echo

function widget:Initialize()
    widgetHandler.actionHandler:AddAction(self, "gui_smart_commands_insert_mode_toggle", insertMode, nil, "p")
    widgetHandler.actionHandler:AddAction(self, "gui_smart_commands_onoff_toggle", toggle, nil, "p")
end

function toggle(_,_,args)
    enabled = not enabled
    local status = enabled and "on" or "off"
    echo("Smart Commands toggled ".. status)
end

function insertMode(_,_,args)
    insert_mode = not insert_mode
    echo("Smart Commands - insert_mode changed to : "..tostring(insert_mode))
end

function widget:MousePress(x, y, button)
    if not enabled then return false end

    mouseClicked = true
    --echo("mouse clicked TRUE")
end

function widget:KeyPress(key, mods, isRepeat)
    if key == 8 and mods.alt then   -- alt+backspace
        toggle()
    end

    if not enabled then return false end

    if mouseClicked and not isRepeat then 
        mouseClicked = false 
        --echo("mouse clicked FALSE")
    end
    active = true
    --echo("active")
    return false
end

function widget:KeyRelease(key)
    if not enabled then return false end

    if active and mouseClicked then
        mouseClicked = false 
        --echo("mouseClicked false")
        if not retain_aiming then
            Spring.SetActiveCommand(0)
        end
        return
    end
    local cmdIndex, cmdID, cmdType, cmdName = Spring.GetActiveCommand()
    if cmdID ~= nil and cmdID > 0 then  -- skip build commands
        executeCommand(cmdID)
        active = false
    end
end

function widget:SelectionChanged(sel)
    if not enabled then return false end

    selectedUnits = sel
end

function executeCommand(cmdID)
    if not enabled then return false end

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
    if insert_mode and cmdID ~= 34923 then meta = not meta end -- insert doesn't play nice with set_target
    if meta then
        cmdOpts = GetCmdOpts(alt, ctrl, false, shift, false)
        Spring.GiveOrderToUnitArray(selectedUnits, CMD.INSERT, {0, cmdID, cmdOpts.coded, unpack(params)}, altOpts)
    else
        cmdOpts = GetCmdOpts(alt, ctrl, meta, shift, false)
        Spring.GiveOrderToUnitArray(selectedUnits, cmdID, params, cmdOpts)
    end
    if not retain_aiming then
        Spring.SetActiveCommand(0)
    end
end

function widget:UnitCommand(unitID, unitDefID, unitTeam, cmdID, cmdParams, cmdOpts, cmdTag)
    if not enabled then return false end

    if mouseClicked then
        active = false
        --echo("not active")
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