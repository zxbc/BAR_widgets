function widget:GetInfo()
    return {
        name    = "Better Build Pathing",
        desc    =
        "Optimizes builder's pathing when the builder needs to move out of the way of the building location. The builder(s) will always move towards the shortest distance vector outward from the center of the building.",
        author  = "Errrrrrr",
        date    = "June, 2023",
        version = "1.1",
        license = "GNU GPL, v2 or later",
        layer   = 10,
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

-- debug drawing globals for build target and builder
local buildTargetVertexes = { 0, 0, 0, 0 }
local builderVertexes = { 0, 0, 0, 0 }
local drawBoxes = false

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
    [CMD.MOVE] = true,
    [CMD.ATTACK] = true,
    [CMD.RECLAIM] = true,
    [CMD.RESTORE] = true,
    [CMD.RESURRECT] = true,
    [CMD.PATROL] = true,
    [CMD.CAPTURE] = true,
    [CMD.FIGHT] = true,
    [CMD.MANUALFIRE] = true,
    [CMD.UNLOAD_UNIT] = true,
    [CMD.UNLOAD_UNITS] = true,
    [CMD.LOAD_UNITS] = true,
    [CMD.GUARD] = true,
    [CMD.AREA_ATTACK] = true,
    [CMD_SETTARGET] = true -- set target
}

-- this requires modification if we want to only use CMD.MOVE
local function GetUnitFinalPosition(uID)
    --Spring.Echo("GetUnitFinalPosition")
    local ux, uy, uz = spGetUnitPosition(uID)

    local cmds = spGetCommandQueue(uID, 5000)
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

                        if pID > 32000 then
                            px, py, pz = spGetFeaturePosition(pID - 32000)
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

-- this function determines whether the building location is obstructed by the supplied unitID
local function isObstructed(builderID, buildtargetID, builderX, builderZ, buildX, buildZ, buildFacing)
    -- use the size of builderID and buildtargetID and the build location as well as buildFacing to determine if the build location is obstructed by the builder
    local builderDef = UnitDefs[spGetUnitDefID(builderID)]
    local buildtargetDef = UnitDefs[buildtargetID]

    local builderSizeX, builderSizeZ = builderDef.xsize, builderDef.zsize
    local buildtargetSizeX, buildtargetSizeZ = buildtargetDef.xsize, buildtargetDef.zsize

    -- if buildFacing is odd, flip the buildTargetSizeX and buildTargetSizeZ
    if buildFacing % 2 == 1 then
        buildtargetSizeX, buildtargetSizeZ = buildtargetSizeZ, buildtargetSizeX
    end

    -- determine if the area occupied by the builder is overlapping with the area occupied by the building
    local builderMinX, builderMinZ = builderX - builderSizeX / 2, builderZ - builderSizeZ / 2
    local builderMaxX, builderMaxZ = builderX + builderSizeX / 2, builderZ + builderSizeZ / 2

    local buildtargetMinX, buildtargetMinZ = buildX - buildtargetSizeX / 2, buildZ - buildtargetSizeZ / 2
    local buildtargetMaxX, buildtargetMaxZ = buildX + buildtargetSizeX / 2, buildZ + buildtargetSizeZ / 2

    -- we want to set some tolerance for the overlap, so we add tolerance to every direction of the checking
    local tolerance = 1
    if builderMinX > buildtargetMaxX + tolerance or builderMaxX < buildtargetMinX - tolerance then return false end
    if builderMinZ > buildtargetMaxZ + tolerance or builderMaxZ < buildtargetMinZ - tolerance then return false end

    --Spring.Echo("isObstructed: true")
    return true
end

-- This function returns the vector flag that the builder should move to for minimal movement
local function CalculateMovement(builderPos, buildTargetPos, builderID, buildID, buildFacing, tolerance)
    -- get unit definitions
    local buildDef = UnitDefs[buildID] -- remember buildID is actually the unitDefID of the build target!!!
    local builderDef = UnitDefs[Spring.GetUnitDefID(builderID)]

    if not buildDef or not builderDef then return end

    local builderXSize, builderZSize = builderDef.xsize, builderDef.zsize
    local buildXSize, buildZSize = buildDef.xsize, buildDef.zsize

    if buildFacing % 2 == 1 then
        buildXSize, buildZSize = buildZSize, buildXSize
    end

    -- Get xsize and zsize for both units
    local builderSizeX = builderXSize * 0.5 -- Spring uses full footprint sizes, while we want radius-like sizes.
    local builderSizeZ = builderZSize * 0.5
    local buildTargetSizeX = buildXSize * 0.5
    local buildTargetSizeZ = buildZSize * 0.5

    -- calculate the difference in positions
    local dx = buildTargetPos[1] - builderPos[1]
    local dz = buildTargetPos[3] - builderPos[3]

    -- calculate the minimal non-overlapping distances in both axes
    local minDistX = buildTargetSizeX + builderSizeX
    local minDistZ = buildTargetSizeZ + builderSizeZ

    -- Now, we have to decide in which direction we want to move our builder unit
    -- We choose the direction where we have to move the least.

    -- calculate the current overlaps (if any)
    local overlapX = minDistX - math.abs(dx)
    local overlapZ = minDistZ - math.abs(dz)
    -- print debug info
    --Spring.Echo("minDistX: " .. minDistX .. " minDistZ: " .. minDistZ)

    -- Initialize the movement vector
    local moveVector = { 0, 0, 0 }

    -- Now decide where to move.
    if math.abs(overlapX) > math.abs(overlapZ) then
        -- Move along x
        moveVector[1] = 1
    else
        -- Move along z
        moveVector[3] = 1
    end
    --Spring.Echo("Line vector for unitID: ".. builderID..", : " .. moveVector[1] .. ", " .. moveVector[3])

    return moveVector
end

function widget:CommandNotify(cmdID, cmdParams, cmdOpts)
    if #selectedUnits > max_builders_affected then return end
    if #cmdParams < 3 then return end

    if (cmdID > 0) then return false end
    -- obtain the unitID of the unit being built through cmdID
    local buildID = -cmdID
    local buildUnitDef = UnitDefs[buildID]

    local buildFacing = Spring.GetBuildFacing()

    -- the following gives us 0 if obstructed by a unit, 1 if obstructed by a feature, and 2 if not obstructed
    local obstructed2 = Spring.TestBuildOrder(buildID, cmdParams[1], cmdParams[2], cmdParams[3], buildFacing)

    -- for now we only double check the first builder's final position in queue, maybe in future we'll include all builders
    local builder1 = selectedUnits[1]
    local builder1X, _, builder1Z = GetUnitFinalPosition(builder1)
    local obstructed = isObstructed(builder1, buildID, builder1X, builder1Z, cmdParams[1], cmdParams[3], buildFacing)

    if not obstructed and obstructed == 2 then return end -- not obstructed by anything

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

    local builderPos = { 0, 0, 0 }
    for _, unitID in ipairs(assistants) do
        local x, y, z
        if cmdOpts.shift then
            builderPos[1], builderPos[2], builderPos[3] = GetUnitFinalPosition(unitID)
        else
            builderPos[1], builderPos[2], builderPos[3] = spGetUnitPosition(unitID)
        end

        if buildID == nil then return end
        local builderID = unitID
        local buildTargetPos = { cmdParams[1], cmdParams[2], cmdParams[3] }


        local lineVector = { buildTargetPos[1] - builderPos[1], 0,
            buildTargetPos[3] - builderPos[3] }
        local lineVectorLength = math.sqrt(lineVector[1] ^ 2 + lineVector[2] ^ 2 + lineVector[3] ^ 2)
        local lineVectorUnit = {
            lineVector[1] / lineVectorLength,
            lineVector[2] / lineVectorLength,
            lineVector[3] / lineVectorLength
        }

        -- calculate the line vector of the movement of the builder, we want the builder to move only along the x and z axis (because buildings are always rectangular)
        local lineVector2 = CalculateMovement(builderPos, buildTargetPos, builderID, buildID, buildFacing)

        local offset = isABuilder[unitID] and 11 or 14 -- being safe is never a bad idea
        --[[         local canTurnInPlace = UnitDefs[spGetUnitDefID(unitID)].turnInPlace
        if canTurnInPlace then offset = offset - 1 end ]]

        -- account for buildFacing, if it's odd number, we switch x and z
        local xsize = buildUnitDef.xsize
        local zsize = buildUnitDef.zsize
        if buildFacing % 2 == 1 then
            xsize, zsize = zsize, xsize
        end
        local buildTargetPos = { -- we are removing y component, as well one of the other components
            buildTargetPos[1] - lineVectorUnit[1] * xsize * offset * lineVector2[1],
            buildTargetPos[2],
            buildTargetPos[3] - lineVectorUnit[3] * zsize * offset * lineVector2[3]
        }

        --Spring.MarkerAddPoint(buildTargetPos[1], buildTargetPos[2], buildTargetPos[3], "!")

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

-- helper
function tableToString(t)
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
