function widget:GetInfo()
	return {
        name	= "Cloaked spy/comm default move",
        desc	= "Changes default command of cloaked spies and commanders to move",
        author	= "Errrrrrr, BrainDamage",
        version = "1.0",
        date	= "April 19, 2023",
        license	= "GNU GPL, v2 or later",
        layer	= 0,
        enabled	= true,
	}
end

local unitSelectedLimit = 12  -- SKIP widget behavior if selected unit count is greater than this number

local isCommander = {}
for unitDefID, unitDef in pairs(UnitDefs) do
	if unitDef.customParams.iscommander then
		isCommander[unitDefID] = true
	end
end

local isSpy = {
    [UnitDefNames.armspy.id] = true,
    [UnitDefNames.corspy.id] = true,
}

local spGetSelectedUnitsSorted = Spring.GetSelectedUnitsSorted
local spGetUnitStates = Spring.GetUnitStates
local spGetSelectedUnitsCount = Spring.GetSelectedUnitsCount
local spGetMyTeamID = Spring.GetMyTeamID

local spySelected = false
local commSelected = false
local gameStarted = false
local selectionChanged = false

local CMD_MOVE = CMD.MOVE
local CMD_CLOAK = 37382

function maybeRemoveSelf()
    if Spring.GetSpectatingState() and (Spring.GetGameFrame() > 0 or gameStarted) then
        widgetHandler:RemoveWidget()
    end
end

function widget:GameStart()
    gameStarted = true
    maybeRemoveSelf()
end

function widget:PlayerChanged(playerID)
    maybeRemoveSelf()
end

function widget:Initialize()
    if Spring.IsReplay() or Spring.GetGameFrame() > 0 then
        maybeRemoveSelf()
    end
end

function widget:SelectionChanged(sel)
	selectionChanged = true
end

local selChangedSec = 0
function widget:Update(dt)

	selChangedSec = selChangedSec + dt
	if selectionChanged and selChangedSec > 0.1 then
		selChangedSec = 0
		selectionChanged = false
        spySelected = false
        commSelected = false

        local numberSelected = spGetSelectedUnitsCount()
        if numberSelected > unitSelectedLimit then return end -- skip if selecting too many units

        local selectedUnitTypes = spGetSelectedUnitsSorted()
        for unitDefID, units in pairs(selectedUnitTypes) do
            if isCommander[unitDefID] or isSpy[unitDefID] then
                for _, unitID in pairs(units) do
                    -- we only care if any of them is actually cloaked
                    if select(5,spGetUnitStates(unitID,false,true)) then


                        if isSpy[unitDefID] then spySelected = true end
                        if isCommander[unitDefID] then commSelected = true end
                    end
                end
            end
        end
        --Spring.Echo("Selection has comm: "..tostring(commSelected)..", has spy: "..tostring(spySelected))
	end
end

-- We must detect cloak commands to update behavior even when selection is unchanged
function widget:UnitCommand(unitID, unitDefID, teamID, cmdID, cmdParams, cmdOpts, cmdTag, playerID, fromSynced, fromLua)
	if (cmdID == CMD_CLOAK) and (isCommander[unitDefID] or isSpy[unitDefID]) and (teamID == spGetMyTeamID()) then
        --Spring.Echo("cloak command used!!")
        selectionChanged = true
    end
end

function widget:DefaultCommand()
    if spySelected or commSelected then 
        return CMD_MOVE
    end
end