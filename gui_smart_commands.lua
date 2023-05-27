function widget:GetInfo()
    return {
        name      = "Smart Commands",
        desc      = "Smart cast any command. Key down to set command active, key up to issue command. Alt+backspace to toggle on and off.",
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
-- Default alt+'backspace' to toggle on and off
-- 
-- Key bind actions: "gui_smart_commands_onoff_toggle"
--------------------------------------------------------------------------------------------

local enabled = true
local selectedUnits = {}
local active = false
local mouseClicked = false
local metaDown = false
local shiftDown = true

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
local GetKeySymbol = Spring.GetKeySymbol
local GetKeyBindings = Spring.GetKeyBindings


local function tableToString(t)
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
        result = result .." \n"
      end
    end
  
    return "{" .. result:sub(1, -3) .. "}"
end

local function dumpToFile(obj, prefix, filename)
    local file = assert(io.open(filename, "w"))
    if type(obj) == "table" then
        for k, v in pairs(obj) do
            local key = prefix and (prefix .. "." .. tostring(k)) or tostring(k)
            if type(v) == "function" then
                local info = debug.getinfo(v, "S")
                file:write(key .. " (function) defined in " .. info.source .. " at line " .. info.linedefined .. "\n")
            elseif type(v) == "table" then
                file:write(key .. " (table):\n")
                dumpToFile(v, key, filename)
            else
                file:write(key .. " = " .. tostring(v) .. "\n")
            end
        end
    end
    if type(obj) == "string" then
        file:write(obj)
    end

    file:close()
end

local keyBindings = GetKeyBindings() -- Get the key bindings from the game

-- let's make a lookup table for faster cmd lookup
local keyToBinding = {}
for _, binding in pairs(keyBindings) do
    local key = binding["boundWith"]
    local cmd = binding["command"]
    if key and cmd then
        if keyToBinding[key] == nil then keyToBinding[key] = cmd
        else
            -- if there's clash, we need to add to existing
            local value = keyToBinding[key]
            if type(value) == "table" then  -- already more than one entry
                value[#value+1] = cmd
                keyToBinding[key] = value
            elseif type(value) == "string" then  -- one entry only
                local newValue = {value, cmd}
                keyToBinding[key] = newValue
            end
        end
    end
end

table.save(keyToBinding, "LuaUI/config/keyToBinding.txt", "Smart Commands")

local skipFeatureCmd = {    -- these cannot be set on featureID
    [CMD.ATTACK]=true, [CMD.PATROL]=true, [CMD.FIGHT]=true, [CMD.MANUALFIRE]=true
}

local skipAltogether = {
    [10010]=true,   -- CMD_BUILD
    [30100]=true,   -- CMD_AREA_MEX
}

function widget:Initialize()
    selectedUnits = GetSelectedUnits()
    widgetHandler.actionHandler:AddAction(self, "gui_smart_commands_onoff_toggle", toggle, nil, "p")
end

function toggle(_,_,args)
    enabled = not enabled
    local status = enabled and "on" or "off"
    echo("Smart Commands toggled ".. status)
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

    if mods.meta then
        metaDown = true 
        local keyString = GetKeySymbol(key)
        if keyString then 
            local keyString = "sc_"..keyString
            local cmdName = keyToBinding[keyString]
            --echo("keyString: "..keyString..", cmdName: "..tostring(cmdName))
            if cmdName then
                --if (cmdID and cmdID < 0) or (cmdID and skipAltogether[cmdID]) then return false end
                echo("command set through keybind search: "..tableToString(cmdName))
                if type(cmdName) == "table" then -- we have multiple commands possible
                    local cmd, result
                    for i=1, #cmdName do
                        cmd = cmdName[i]
                        result = SetActiveCommand(cmd)
                        if result then break end
                    end
                    if not result then echo("Error in finding bound command!") end
                elseif type(cmdName) == "string" then -- only one command bound
                    SetActiveCommand(cmdName)
                end
                active = true
                --echo("active")
            end
        end
    end

    if key == 32 then 
        ---echo("meta down")
        metaDown = true 
    end

    if key == 304 then
        --echo("shift down")
        shiftDown = true
    end

    -- Iterate through the key bindings and check if the pressed key matches any of the bindings



    if mouseClicked and not isRepeat then 
        mouseClicked = false 
        --echo("mouse clicked FALSE")
    end
    active = true
    --local cmdIndex, cmdID, cmdType, cmdName = GetActiveCommand()

    return false
end

function widget:KeyRelease(key)
    if not enabled then return false end
    if key == 122 or key == 120 or key == 118 or key == 99 then return false end -- z x c v keys, hardcoded for now...

    local alt, ctrl, meta, shift = GetModKeys()

    if key == 304 then
        --echo("shift up")
        shiftDown = false 
        return
    end
    if key == 32 then 
        --echo("meta up")
        metaDown = false 
        return
    end
    
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
    if cmdID ~= 34923 then meta = false end -- insert doesn't play nice with set_target
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


