function widget:GetInfo()
    return {
        name = "Commander Dgun Walk Fix",
        desc = "Stops commander from wandering into dgun target after firing dgun in certain funny angles.",
        author = "Errrrrrr",
        date = "June 2023",
        license = "GNU GPL, v2 or later",
        layer = 999999 + 1,
        handler = true,
        enabled = true,
    }
end

local myAllyTeam = Spring.GetMyAllyTeamID()
local dgunWalkPrevented = 0

function widget:UnitCmdDone(unitID, unitDefID, unitTeam, cmdID, cmdParams, cmdOpts, cmdTag)
    -- only if it's our unit, having done a dgun command
    if unitTeam == myAllyTeam and cmdID == 105 then
        local commands = Spring.GetUnitCommands(unitID, -1)
        if #commands == 0 then
            -- issue a stop command to stop the wandering behavior only if moving
            local x, y, z, length = Spring.GetUnitVelocity(unitID)
            --Spring.Echo("velocity length: ".. tostring(length))

            if length > 0 then
                Spring.GiveOrderToUnit(unitID, 0, {}, {})
                dgunWalkPrevented = dgunWalkPrevented + 1
                Spring.Echo("Dgun walk prevented so far: " .. tostring(dgunWalkPrevented))
            end
        end
    end
end
