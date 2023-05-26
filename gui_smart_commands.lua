function widget:GetInfo()
    return {
        name      = "Smart Commands",
        desc      = "Smart cast any command. Key down to set command active, key up to issue command. Alt+backspace to toggle on and off. Alt+i to toggle insert mode.",
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
-- Default alt+'backspace' to toggle on and off, alt+'1' to toggle insert_mode
-- insert_mode toggle makes all commands issued automatically inserted at front of queue
-- If you use insert_mode, meta + key will be normal mode
-- Key bind actions: "gui_smart_commands_insert_mode_toggle"
--                   "gui_smart_commands_onoff_toggle"
--------------------------------------------------------------------------------------------
local insert_mode = false

local enabled = true
local selectedUnits = {}
local active = false
local mouseClicked = false
local metaDown = false

-- shortcuts
local echo = Spring.Echo
local GetActiveCommand = Spring.GetActiveCommand
local GetSelectedUnits = Spring.GetSelectedUnits
local GetUnitPosition = Spring.GetUnitPosition
local GetFeaturePosition = Spring.GetFeaturePosition
local GetModKeyState = Spring.GetModKeyState
local GetInvertQueueKey = Spring.GetInvertQueueKey
local GetMouseState = Spring.GetMouseState
local GiveOrderToUnitArray = Spring.GiveOrderToUnitArray
local SetActiveCommand = Spring.SetActiveCommand
local TraceScreenRay = Spring.TraceScreenRay

local skipFeatureCmd = {    -- these cannot be set on featureID
    [CMD.ATTACK]=true, [CMD.PATROL]=true, [CMD.FIGHT]=true, [CMD.MANUALFIRE]=true
}

local skipAltogether = {
    [10010]=true,   -- CMD_BUILD
    [30100]=true,   -- CMD_AREA_MEX
}

function widget:Initialize()
    selectedUnits = GetSelectedUnits()
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
    if key == 105 and mods.alt then  -- alt+'i'
        insertMode()
    end

    if mods.meta then 
        --echo("meta down")
        metaDown = true 
    end

    if mouseClicked and not isRepeat then 
        mouseClicked = false 
        --echo("mouse clicked FALSE")
    end
    local cmdIndex, cmdID, cmdType, cmdName = GetActiveCommand()
    if (cmdID and cmdID < 0) or (cmdID and skipAltogether[cmdID]) then return false end
    active = true
    --echo("active")
    return false
end

function widget:KeyRelease(key)
    if not enabled then return false end
    if key == 122 or key == 120 or key == 118 or key == 99 then return false end -- z x c v keys, hardcoded for now...

    local alt, ctrl, meta, shift = GetModKeys()
    
    local cmdIndex, cmdID, cmdType, cmdName = GetActiveCommand()
    if active and mouseClicked then
        mouseClicked = false 
        --echo("mouseClicked false")
        if cmdID and cmdID > 0 and not skipAltogether[cmdID] then
            SetActiveCommand(0)
        end
        return
    end

    if active and cmdID ~= nil and cmdID > 0 and not skipAltogether[cmdID] then  -- skip build commands
        executeCommand(cmdID)
        active = false
    end
    if not meta then 
        --echo("meta up")
        metaDown = false 
    end
end

function widget:SelectionChanged(sel)
    if not enabled then return false end

    selectedUnits = sel
end

function executeCommand(cmdID)
    if not enabled then return false end

    local mouseX, mouseY = GetMouseState()
    local desc, args = TraceScreenRay(mouseX, mouseY, false)
    if desc == nil then 
        return 
    end

    local params = {}
    if desc == "unit" then
        params = {args}
        if CMD.FIGHT == cmdID or CMD.PATROL == cmdID then
            local fx, fy, fz = GetUnitPosition(args, true)
            params = {fx, fy, fz}
        end
    elseif desc == "feature" then
        params = {args+32000} -- seriously wtf
        if skipFeatureCmd[cmdID] then
            local fx, fy, fz = GetFeaturePosition(args, true)
            params = {fx, fy, fz}
        end
    else
        params = {args[1], args[2], args[3]}
    end
    local alt, ctrl, meta, shift = GetModKeys()
    local cmdOpts
    local altOpts = GetCmdOpts(true, false, false, false, false)
    if insert_mode and cmdID ~= 34923 then meta = false end -- insert doesn't play nice with set_target
    if metaDown then
        cmdOpts = GetCmdOpts(alt, ctrl, false, shift, false)
        GiveOrderToUnitArray(selectedUnits, CMD.INSERT, {0, cmdID, cmdOpts.coded, unpack(params)}, altOpts)
    else
        cmdOpts = GetCmdOpts(alt, ctrl, meta, shift, false)
        GiveOrderToUnitArray(selectedUnits, cmdID, params, cmdOpts)
    end
    -- echo("executeCommand set0")
    SetActiveCommand(0)
end

function widget:CommandNotify(id, cmdParams, cmdOpts)
    if not enabled then return false end

    if active and id > 0 then
        SetActiveCommand(0)
    end
end

function GetModKeys()
    local alt, ctrl, meta, shift = GetModKeyState()
  
    if GetInvertQueueKey() then -- Shift inversion
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