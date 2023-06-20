function widget:GetInfo()
    return {
        name    = "Better Build Pathing",
        desc    = "Optimizes builder's pathing when the builder needs to move out of the way of the building location. The builder(s) will always move towards the shortest distance vector outward from the center of the building.",
        author  = "Errrrrrr",
        date    = "June, 2023",
        version = "1.0",
        license = "GNU GPL, v2 or later",
        layer   = 1,
        enabled = true,
    }
end

-------------------------------------------------------------------------------------------
-- If the number of selected builders exceeds max_builders_affected, the widget is disabled
-- This is because the default scatter pathing is more effective for large group sizes
-------------------------------------------------------------------------------------------
local max_builders_affected = 8

local selectedUnits = {}

local spGetUnitPosition = Spring.GetUnitPosition
local spGetCommandQueue = Spring.GetCommandQueue
local spGetFeaturePosition = Spring.GetFeaturePosition
local spGetUnitDefID = Spring.GetUnitDefID
local spGiveOrderToUnit = Spring.GiveOrderToUnit

function widget:Initialize()
    selectedUnits = Spring.GetSelectedUnits()
end

function widget:SelectionChanged(sel)
    selectedUnits = sel
end

-- this returns if unitDef is a builder and not a factory
local function IsBuilder(unitDef)
    if not unitDef then return false end
    if unitDef.isFactory and #unitDef.buildOptions > 0 then
        return false
    end
    return unitDef.isBuilder and (unitDef.canAssist or unitDef.canReclaim)
end

local function canBuild(builderDefID, targetDefID)
    local builderDef = UnitDefs[builderDefID]

    -- Check if both the builder and target unit definitions exist
    if builderDef and targetDefID then
        -- Check if the target unit's ID is present in the builder's buildOptions
        for _, buildOptionID in ipairs(builderDef.buildOptions) do
            if buildOptionID == targetDefID then
                return true -- Builder can build the target unit
            end
        end
    end

    return false -- Builder cannot build the target unit
end

-- What commands can be issued at a position or unit/feature ID (Only used by GetUnitPosition)
local CMD_SETTARGET = 34923
local positionCmds = {
    [CMD.MOVE]=true,		[CMD.ATTACK]=true,		[CMD.RECLAIM]=true,		[CMD.RESTORE]=true,		[CMD.RESURRECT]=true,
    [CMD.PATROL]=true,		[CMD.CAPTURE]=true,		[CMD.FIGHT]=true, 		[CMD.MANUALFIRE]=true,
    [CMD.UNLOAD_UNIT]=true,	[CMD.UNLOAD_UNITS]=true,[CMD.LOAD_UNITS]=true,	[CMD.GUARD]=true,		[CMD.AREA_ATTACK] = true,
    [CMD_SETTARGET] = true -- set target
}
local function GetUnitFinalPosition(uID)

    local ux, uy, uz = spGetUnitPosition(uID)

    local cmds = spGetCommandQueue(uID,5000)
	if cmds then
		for i = #cmds, 1, -1 do

			local cmd = cmds[i]
			if (cmd.id < 0) or positionCmds[cmd.id] then

				local params = cmd.params
				if #params >= 3 then
					return params[1], params[2], params[3]
				else
					if #params == 1 then

						local pID = params[1]
						local px, py, pz

						if pID > maxUnits then
							px, py, pz = spGetFeaturePosition(pID - maxUnits)
						else
							px, py, pz = spGetUnitPosition(pID)
						end

						if px then
							return px, py, pz
						end
					end
				end
			end
		end
	end

    return ux, uy, uz
end

function widget:CommandNotify(cmdID, cmdParams, cmdOpts)
    if #selectedUnits > max_builders_affected then return end
    if #cmdParams < 3 then return end

    if (cmdID > 0) then return false end
    -- obtain the unitID of the unit being built through cmdID
    local buildID = -cmdID
    local buildUnitDef = UnitDefs[buildID]

    local obstructed = Spring.TestBuildOrder(buildID, cmdParams[1], cmdParams[2], cmdParams[3], 0)
    obstructed = obstructed + Spring.TestBuildOrder(buildID, cmdParams[1], cmdParams[2], cmdParams[3], 1)

    if obstructed == 4 then return end -- not obstructed by anything (safely)

    -- add to a list of all the builders that can build this unit
    -- add to a list of all the assistants that can assist this unit
    local builders = {}
    local isABuilder = {}
    local assistants = {}
    --local assistDefs = {}
    for _, unitID in ipairs(selectedUnits) do
        local unitDefID = spGetUnitDefID(unitID)
        if canBuild(unitDefID, buildID) and IsBuilder(UnitDefs[unitDefID]) then
            table.insert(builders, unitID)
            isABuilder[unitID] = true
        end
        if UnitDefs[unitDefID].canAssist and IsBuilder(UnitDefs[unitDefID]) then
            table.insert(assistants, unitID)
            --assistDefs[unitID] = UnitDefs[unitDefID]
        end
    end

    --Spring.Echo("Number of assistants: " .. #assistants)
    --Spring.Echo("Number of builders: " .. #builders)

    --local mainBuilder = builders[1]
    --table.remove(assistants, mainBuilder)

    for _, unitID in ipairs(assistants) do
        local x, y, z
        if cmdOpts.shift then
            x, y, z = GetUnitFinalPosition(unitID)
        else
            x, y, z = spGetUnitPosition(unitID)
        end
        local builderPos = { x, y, z }

        -- check if the current builder is obstructing the build target location
        if buildID == nil then return end

        local buildTarget = cmdParams
        local buildTargetPos = { buildTarget[1], buildTarget[2], buildTarget[3] }

        -- calculate the line vector from builder to build target, then move the builder back along this line until it no longer obstructs the build target
        local lineVector = { buildTarget[1] - builderPos[1], buildTarget[2] - builderPos[2],
            buildTarget[3] - builderPos[3] }
        local lineVectorLength = math.sqrt(lineVector[1] ^ 2 + lineVector[2] ^ 2 + lineVector[3] ^ 2)
        local lineVectorUnit = { 
            lineVector[1] / lineVectorLength,
            lineVector[2] / lineVectorLength,
            lineVector[3] / lineVectorLength
        }

        local offset = isABuilder[unitID] and 10 or 14 -- being safe is never a bad idea
        local buildTargetPos = {
            buildTargetPos[1] - lineVectorUnit[1] * buildUnitDef.xsize * offset,
            buildTargetPos[2],
            buildTargetPos[3] - lineVectorUnit[3] * buildUnitDef.zsize * offset
        }

        -- detect if command is inserted or not
        if not cmdOpts.meta then
            -- issue command move
            spGiveOrderToUnit(unitID, CMD.MOVE, buildTargetPos, cmdOpts)
            -- Spring.Echo("Moving builder to: " .. buildTargetPos[1] .. ", " .. buildTargetPos[2] .. ", " .. buildTargetPos[3])
            -- let's also draw something shiny at the location we want to move to
            --Spring.MarkerAddPoint(buildTargetPos[1], buildTargetPos[2], buildTargetPos[3], "*")

            -- we add build command if it's the mainBuilder, otherwise we add assist command
            spGiveOrderToUnit(unitID, cmdID, cmdParams, { "shift" })
        else
            spGiveOrderToUnit(unitID, CMD.INSERT,
                { 0, CMD.MOVE, CMD.OPT_SHIFT, buildTargetPos[1], buildTargetPos[2], buildTargetPos[3] }, { "alt" })
            --Spring.MarkerAddPoint(buildTargetPos[1], buildTargetPos[2], buildTargetPos[3], "*")


            spGiveOrderToUnit(unitID, CMD.INSERT,
                { 1, cmdID, CMD.OPT_SHIFT, cmdParams[1], cmdParams[2], cmdParams[3] }, { "alt" })
        end
    end
    return true
end
