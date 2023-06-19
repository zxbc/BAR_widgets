function widget:GetInfo()
    return {
        name    = "Single Volley Attack Mode",
        desc    = "Sets units to single volley attack mode. Alt + q to toggle on a unit.",
        author  = "Errrrrrr",
        date    = "June 19, 2023",
        license = "GNU GPL, v2 or later",
        version = "1.0",
        layer   = 9999,
        enabled = true,
        handler = true
    }
end

---------------------------------------------------------------------------
-- Default keybind is "alt-q"
-- Set custom_keybind_mode to true for custom keybind.
-- Bindable action name: single_volley_attack_toggle
---------------------------------------------------------------------------
local custom_keybind_mode = false


local gameFrame = 0
local overWatched = {}  -- this table contains all the units that are on single volley mode

function widget:Initialize()
    widgetHandler.actionHandler:AddAction(self, "single_volley_attack_toggle", SingleVolleyAttackToggle, nil, "p")
end

function SingleVolleyAttackToggle(_,_,args)
    local selUnits = Spring.GetSelectedUnits()
    -- add all units to overWatched table, with their unitID as index and their current weapon 1's reloadFrame as value
    for i, unitID in ipairs(selUnits) do
        local reloadFrame = Spring.GetUnitWeaponState(unitID, 1, "reloadFrame")
        local unitDef = UnitDefs[Spring.GetUnitDefID(unitID)]
        if not overWatched[unitID] then
            overWatched[unitID] = reloadFrame
            --Spring.Echo("Unit "..tostring(unitID).." (" .. unitDef.name .. ") added to single volley overwatch")
        else
            overWatched[unitID] = nil
            --Spring.Echo("Unit "..tostring(unitID).." (" .. unitDef.name .. ") removed from single volley overwatch")
        end
    end
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
    if gameFrame % 3 == 1 then
        -- iterate through all of overWatched table, and check if the current weapon 1's reloadFrame is different from the one stored in the table
        for unitID, reloadFrame in pairs(overWatched) do
            local currentReloadFrame = Spring.GetUnitWeaponState(unitID, 1, "reloadFrame")
            if currentReloadFrame ~= reloadFrame then
                -- if it is different, then the unit has fired, so remove it from the table
                --Spring.Echo("Unit "..tostring(unitID).." has fired volley at gameFrame: "..tostring(gameFrame))
                overWatched[unitID] = currentReloadFrame
                -- remove the current command from queue if it is an area attack command
                local commands = Spring.GetUnitCommands(unitID, -1)
                if #commands > 0 then
                    local cmdID = commands[1].id
                    local params = commands[1].params
                    if cmdID == CMD.ATTACK and #params > 1 then
                        Spring.GiveOrderToUnit(unitID, CMD.REMOVE, {commands[1].tag}, {})
                        -- if the unit's repeat state is set to true, we re-add this command to the end of the command queue
                        local unitStates = Spring.GetUnitStates(unitID)
                        if unitStates["repeat"] then
                            Spring.GiveOrderToUnit(unitID, CMD.ATTACK, params, {"shift"})
                        end
                    end
                end
            end
        end
    end
end

local icon = "LuaUI/Images/groupicons/weaponexplo.png"
-- draw this icon at the top left corner of the unit's model in the world if it is on single volley mode
function widget:DrawWorld()
    for unitID, reloadFrame in pairs(overWatched) do
        local x, y, z = Spring.GetUnitPosition(unitID)
        gl.PushMatrix()
        gl.Translate(x, y, z)
        gl.Billboard()
        gl.Color(1, 1, 1, 1)
        gl.Texture(icon)
        gl.TexRect(-40, 10, -10, 40)
        gl.PopMatrix()
    end
end

-- if unit is destroyed, remove it from overWatched table
function widget:UnitDestroyed(unitID, unitDefID, unitTeam)
    overWatched[unitID] = nil
end

