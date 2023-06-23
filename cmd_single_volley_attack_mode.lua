function widget:GetInfo()
    return {
        name    = "Single Volley Attack Mode",
        desc    = "Sets units to single volley attack mode. Alt-Q to toggle. V1.2 added a new separate bindable command 'single_volley_attack_command'",
        author  = "Errrrrrr",
        date    = "June 22, 2023",
        license = "GNU GPL, v2 or later",
        version = "1.2",
        layer   = 9999,
        enabled = true,
        handler = true
    }
end

---------------------------------------------------------------------------------------------
-- Default keybind is "alt-q"
-- Set custom_keybind_mode to true for custom keybind.
-- Bindable action name: single_volley_attack_toggle
--
-- Version 1.2: Added a new bindable command "single_volley_attack_command"
-- The new bindable command simply performs one volley of attack (when it's a ground attack)
-- You can bind the new command to your default attack key (e.g. "a")
-- Icon drawing is disabled now, if you want to use the old toggle mode, set drawIcons to true
---------------------------------------------------------------------------------------------
local custom_keybind_mode = false
local drawIcons = true

local degen_mode = false   -- deprecated, no need

local gameFrame = 0
local overWatched = {}  -- this table contains all the units that are on single volley mode
local overWatchedCmdCount = {}  -- this table contains the number of single volley commands in the command queue of the overwatched units
local overWatchedUpdate = {}  -- this table indicates whether the overwatched units need to be updated
local myAllyTeamID

local singleVolleyAttackActive = false

-- speed ups
local spSetActiveCommand = Spring.SetActiveCommand
local spGetActiveCommand = Spring.GetActiveCommand
local spGetSelectedUnits = Spring.GetSelectedUnits
local spGiveOrder        = Spring.GiveOrder
local spGetUnitWeaponState = Spring.GetUnitWeaponState
local spGetUnitPosition    = Spring.GetUnitPosition
local spGetUnitDefID       = Spring.GetUnitDefID
local spGetUnitCommands    = Spring.GetUnitCommands
local spGetUnitStates      = Spring.GetUnitStates
local spGiveOrderToUnit    = Spring.GiveOrderToUnit
local spEcho               = Spring.Echo

local CMD_ATTACK = CMD.ATTACK
local CMD_REMOVE = CMD.REMOVE
local CMD_STOP = CMD.STOP

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
      end
    end
  
    return "{" .. result:sub(1, -3) .. "}"
end

local function GiveNotifyingOrder(cmdID, cmdParams, cmdOpts)

    if widgetHandler:CommandNotify(cmdID, cmdParams, cmdOpts) then
        return
    end

    spGiveOrder(cmdID, cmdParams, cmdOpts.coded)
end

local function RemoveOverwatchedUnit(unitID)
    overWatched[unitID] = nil
    overWatchedCmdCount[unitID] = 0
    overWatchedUpdate[unitID] = nil
    --spEcho("Unit "..tostring(unitID).." removed from single volley overwatch")
end

function widget:Initialize()
    myAllyTeamID = Spring.GetMyAllyTeamID()
    widgetHandler.actionHandler:AddAction(self,"single_volley_attack_toggle", SingleVolleyAttackToggle, nil, "p")
    widgetHandler.actionHandler:AddAction(self,"single_volley_attack_command", SingleVolleyAttackCommand, nil, "p")
end

function SingleVolleyAttackToggle(_,_,_,args)
    local selUnits = spGetSelectedUnits()
    -- add all units to overWatched table, with their unitID as index and their current weapon 1's reloadFrame as value
    for i, unitID in ipairs(selUnits) do
        local reloadFrame = spGetUnitWeaponState(unitID, 1, "reloadFrame")
        local unitDef = UnitDefs[spGetUnitDefID(unitID)]
        if not overWatched[unitID] then
            overWatched[unitID] = reloadFrame
            overWatchedCmdCount[unitID] = 999999
            Spring.Echo("Unit "..tostring(unitID).." (" .. unitDef.name .. ") added to single volley overwatch")
        else
            overWatched[unitID] = nil
            overWatchedCmdCount[unitID] = 0
            Spring.Echo("Unit "..tostring(unitID).." (" .. unitDef.name .. ") removed from single volley overwatch")
        end
    end
end

function SingleVolleyAttackCommand(_,_,_,args)
    singleVolleyAttackActive = true
    spSetActiveCommand("attack", 1)
end

function widget:KeyPress(key, mods, isRepeat)
    if custom_keybind_mode then return end
    if (key == 113) and (mods.alt) then -- alt + q
        SingleVolleyAttackToggle()
    end
end

function widget:GameFrame(frame)
    gameFrame = frame
end

function widget:Update(dt)
    if gameFrame % 3 == 0 then
        -- iterate through all of overWatched table, and check if the current weapon 1's reloadFrame is different from the one stored in the table
        for unitID, reloadFrame in pairs(overWatched) do
            local currentReloadFrame = spGetUnitWeaponState(unitID, 1, "reloadFrame")
            if currentReloadFrame ~= reloadFrame then
                --spEcho("unit "..tostring(unitID).." has fired a volley at time "..tostring(gameFrame).."!")
                overWatched[unitID] = currentReloadFrame
                -- remove the current command from queue if it is a single volley attack ground command
                local commands = spGetUnitCommands(unitID, -1)
                if #commands > 0 then
                    local cmdID = commands[1].id
                    local params = commands[1].params
                    if ((cmdID == CMD_ATTACK) and (params[#params] == 666666)) or (overWatchedCmdCount[unitID] > 1000) then
                        --spEcho("detected single volley attack command from unit "..tostring(unitID))
                        overWatchedCmdCount[unitID] = overWatchedCmdCount[unitID] - 1
                        spGiveOrderToUnit(unitID, CMD_REMOVE, {commands[1].tag, 555555}, 0)
                        --spEcho("unit "..tostring(unitID).." has "..tostring(overWatchedCmdCount[unitID]).." single volley attack commands left in queue")
                        -- if the unit's repeat state is set to true, we re-add this command to the end of the command queue
                        local unitStates = spGetUnitStates(unitID)
                        if unitStates["repeat"] then
                            spGiveOrderToUnit(unitID, CMD_ATTACK, params, {"shift"})
                        end
                    end
                end
                -- remove the unit from the overWatched table if it has no more single volley attack commands in queue
                if (overWatchedCmdCount[unitID] <= 0) or (#commands == 0) then
                    RemoveOverwatchedUnit(unitID)
                end
            end
        end
    end
    if gameFrame % 2 == 1 then
        if singleVolleyAttackActive then
            local index, cmd_id, cmd_type, cmd_name = spGetActiveCommand()
            --spEcho("cmd_id: "..tostring(cmd_id))
            if not cmd_id then
                singleVolleyAttackActive = false
            end
        end
    end
end

local icon = "LuaUI/Images/groupicons/weaponexplo.png"
-- draw this icon at the top left corner of the unit's model in the world if it is on single volley mode
function widget:DrawWorld()
    -- degens don't need graphics
    if degen_mode or not drawIcons then return end

    for unitID, reloadFrame in pairs(overWatched) do
        local x, y, z = spGetUnitPosition(unitID)
        gl.PushMatrix()
        gl.Translate(x, y, z)
        gl.Billboard()
        gl.Color(1, 1, 1, 1)
        gl.Texture(icon)
        gl.TexRect(-40, 10, -20, 30)
        gl.PopMatrix()
    end
end

function widget:CommandNotify(cmdID, cmdParams, cmdOpts)
    if singleVolleyAttackActive then -- if it is a ground attack command
        --singleVolleyAttackActive = false

        if (cmdID == CMD_ATTACK) and (#cmdParams >= 3) then
            -- we add an additional param to the command, indicating this is a single volley attack command
            -- what's the worst that could happen?
            cmdParams[#cmdParams+1] = 666666

            --spEcho("Single volley attack command issued at frame "..tostring(gameFrame).."!")
            spGiveOrder(cmdID, cmdParams, cmdOpts)  -- simply give the modified command

            return true
        end
    end
end

-- when unit receives a command, check if it is a single volley attack command
function widget:UnitCommand(unitID, unitDefID, unitTeam, cmdID, cmdParams, cmdOpts, cmdTag, playerID, fromSynced, fromLua)
    --spEcho("Unit "..tostring(unitID)..", cmdID: "..tostring(cmdID).. ", cmdParams: "..tableToString(cmdParams)..", cmdOpts: "..tableToString(cmdOpts)..", cmdTag: "..tostring(cmdTag).. ", fromSynced: "..tostring(fromSynced)..", fromLua: "..tostring(fromLua))
    
    if (cmdID == CMD_ATTACK) and (cmdParams[#cmdParams] == 666666) and (unitTeam == myAllyTeamID) then
        -- add the unit to overWatched table
        overWatched[unitID] = spGetUnitWeaponState(unitID, 1, "reloadFrame")
        if overWatchedCmdCount[unitID] == nil then
            overWatchedCmdCount[unitID] = 1
        else
            overWatchedCmdCount[unitID] = overWatchedCmdCount[unitID] + 1
        end
        --spEcho("Unit "..tostring(unitID).."'s overWatchedCmdCount is "..tostring(overWatchedCmdCount[unitID]))
        return true
    end

    -- if it's a stop or remove command, check the unit's overWatchedCmdCount and update it
    if ((cmdID == CMD_STOP) or (cmdID == CMD_REMOVE)) and (cmdParams[2] ~= 555555) then
        -- get the command queue of the unit, figure out if the removed command is a single volley attack command, decrement the overWatchedCmdCount if it is
        local commands = spGetUnitCommands(unitID, -1)
        local cmdIndex = 0
        if cmdID == CMD_STOP then
            RemoveOverwatchedUnit(unitID)
        elseif cmdID == CMD_REMOVE then
            for i = 1, #commands do
                if commands[i].tag == cmdParams[1] then
                    cmdIndex = i
                    break
                end
            end
        end
        if cmdIndex > 0 then
            cmdID = commands[cmdIndex].id
            local params = commands[cmdIndex].params
            if (cmdID == CMD_ATTACK) and (params[#params] == 666666) then
                --spEcho("detected single volley attack command from unit "..tostring(unitID))
                if overWatched[unitID] then
                    overWatchedCmdCount[unitID] = overWatchedCmdCount[unitID] - 1
                end
                --spEcho("unit "..tostring(unitID).." has "..tostring(overWatchedCmdCount[unitID]).." single volley attack commands left in queue")
            end
        end
    end
end


-- if unit is destroyed, remove it from overWatched table
function widget:UnitDestroyed(unitID, unitDefID, unitTeam)
    overWatched[unitID] = nil
end

-- add new units to overWatched table if degen_mode
function widget:UnitCreated(unitID, unitDefID, unitTeam)
    if degen_mode and unitTeam == myAllyTeamID then
        local reloadFrame = spGetUnitWeaponState(unitID, 1, "reloadFrame")
        overWatched[unitID] = reloadFrame
    end
end 

-- add gifted units also
function widget:UnitGiven(unitID, unitDefID, unitTeam, oldTeam)
    if degen_mode and unitTeam == myAllyTeamID then
        local reloadFrame = spGetUnitWeaponState(unitID, 1, "reloadFrame")
        overWatched[unitID] = reloadFrame
    end
end

-- add units captured too, because we're truly degenerate
function widget:UnitCaptured(unitID, unitDefID, unitTeam, oldTeam)
    if degen_mode and unitTeam == myAllyTeamID then
        local reloadFrame = spGetUnitWeaponState(unitID, 1, "reloadFrame")
        overWatched[unitID] = reloadFrame
    end
end