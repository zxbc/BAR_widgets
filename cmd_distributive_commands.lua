function widget:GetInfo()
    return {
      name      = "Distributive Commands",
      desc      = "Distribute multiple commands onto selected units evenly. Press meta during shift queuing to distribute currently queued commands; press alt during shift to distribtue the longest queue among selected units.",
      author    = "Errrrrrr",
      version   = "1.0",
      license   = "GNU GPL, v2 or later",
      layer     = 0,
      enabled   = true,
	    handler 	= true,
    }
end

-------------------------------------------------------------------------------------
-- Press meta during shift queuing to distribute current queue to selected units
-- Press alt during shift to distribute the longest queue among selected units
-- Build commands are not processed (there is split build widget!)
-- Distribute after an area command will split the command onto units/features in area
-- Commands are always assigned to the closest units, with reasonable optimization
-- 
-- Custom keybind actions: 
--          distributive_orders_distribute
--          distributive_orders_longestqueue
-------------------------------------------------------------------------------------

-- params
local custom_keybind_mode = false

local split_area_mode = true  -- this mode allows for the distribute key to split area commands
                              -- *highly* recommend keeping this on, because distributeLongest
                              --  cannot distribute area settarget (it won't be in queue)
local insert_mode = false  -- this is a legacy mode, no longer viable


-- How long should algorithms take. (0.05+ gives visible stutter, default: 0.03)
local maxHngTime = 0.03 -- Desired maximum time for hungarian algorithm
local maxNoXTime = 0.03 -- Strict maximum time for backup algorithm

-- Hungarian algorithm params
local defaultHungarianUnits	= 20 -- Need a baseline to start from when no config data saved
local maxHungarianUnits = defaultHungarianUnits -- Also set when loading config
local minHungarianUnits		= 10 -- If we kept reducing maxUnits it can get to a point where it can never increase, so we enforce minimums on the algorithms.
local unitIncreaseThresh	= 0.85 -- We only increase maxUnits if the units are great enough for time to be meaningful


-- Vars
local cmdStash = {} -- { number id, params = table params, options = table opts }
local selectedUnits = {} -- {number unitID1, number unitID2, ...}
local nodes = {} --{number x, number y, number z, cmdItem cmd}

local selChanged = false
local heldDown = false

local osclock = os.clock
local tsort = table.sort
local floor = math.floor
local ceil = math.ceil
local sqrt = math.sqrt
local sin = math.sin
local cos = math.cos
local max = math.max
local huge = math.huge
local pi2 = 2*math.pi

-- Shortcuts
local echo = Spring.Echo
local maxUnits = Game.maxUnits
local spGetUnitPosition = Spring.GetUnitPosition
local spGetModKeyState = Spring.GetModKeyState
local spGetInvertQueueKey = Spring.GetInvertQueueKey
local spGetCommandQueue = Spring.GetCommandQueue
local spGetUnitPosition = Spring.GetUnitPosition
local spGetActiveCommand = Spring.GetActiveCommand
local spSetActiveCommand = Spring.SetActiveCommand
local spGetDefaultCommand = Spring.GetDefaultCommand
local spGetFeaturePosition = Spring.GetFeaturePosition
local spGetUnitCommands = Spring.GetUnitCommands
local spGiveOrderArrayToUnitArray = Spring.GiveOrderArrayToUnitArray
local spAreTeamsAllied = Spring.AreTeamsAllied
local spGetUnitsInCylinder = Spring.GetUnitsInCylinder
local spGetFeaturesInCylinder = Spring.GetFeaturesInCylinder
local spGetMyTeamID = Spring.GetMyTeamID
local spGetUnitTeam = Spring.GetUnitTeam
local spAreTeamsAllied = Spring.AreTeamsAllied
local GetUnitDefID = Spring.GetUnitDefID


local CMD_SETTARGET = 34923
-- What commands can be issued at a position or unit/feature ID (Only used by GetUnitPosition)
local positionCmds = {
  [CMD.MOVE]=true,		[CMD.ATTACK]=true,		[CMD.RECLAIM]=true,		[CMD.RESTORE]=true,		[CMD.RESURRECT]=true,
  [CMD.PATROL]=true,		[CMD.CAPTURE]=true,		[CMD.FIGHT]=true, 		[CMD.MANUALFIRE]=true, [CMD.REPAIR]=true,
  [CMD.UNLOAD_UNIT]=true,	[CMD.UNLOAD_UNITS]=true,[CMD.LOAD_UNITS]=true,	[CMD.GUARD]=true,		[CMD.AREA_ATTACK] = true,
  [CMD_SETTARGET] = true -- set target
}
-- classification of possible area commands
-- the unclassified area commands should be issued at position
local hostileCmds = {
  [CMD.ATTACK]=true, [CMD.CAPTURE]=true, [CMD_SETTARGET]=true
}

local friendlyCmds = { -- this is questionably useful
  --[CMD.REPAIR]=true
}
local featureCmds = {
  [CMD.RECLAIM]=true, [CMD.RESURRECT]=true
}

-- converts table 3 deep to string
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

-- deepcopy a table
local function deepCopy(original)
  if type(original) ~= 'table' then
      return original
  end
  local copy = {}
  for key, value in next, original, nil do
      copy[deepCopy(key)] = deepCopy(value)
  end
  return setmetatable(copy, getmetatable(original))
end

local function GetUnitDef(unitID)
    local unitDefID = GetUnitDefID(unitID)
    if unitDefID then
        local unitDef = UnitDefs[unitDefID]
        return unitDef
    end
    return nil
end

-- Initialize the widget
function widget:Initialize()
  selectedUnits = {}
  cmdStash = {}
  nodes = {}

  if custom_keybind_mode then
    widgetHandler.actionHandler:AddAction(self, "distributive_cmds_distribute", distribute, nil, "p")
    widgetHandler.actionHandler:AddAction(self, "distributive_cmds_longestqueue", distributeLongest, nil, "p")
    widgetHandler.actionHandler:AddAction(self, "distributive_cmds_toggle_split_area", toggleSplitAreaMode, nil, "p")
  end
end

function widget:Shutdown()
  selectedUnits = {}
  cmdStash = {}
  nodes = {}
end

function widget:SelectionChanged(sel)
  selChanged = true
  selectedUnits = sel
  cmdStash = {}
  nodes = {}
end

function toggleSplitAreaMode(_, _, args)
  split_area_mode = not split_area_mode
  echo("Distributive Orders - Split Area Mode: "..(split_area_mode and "on" or "off"))
end

local function GetUnitWithLongestQueue()
  local longestQueueUnitID = nil
  local longestQueueLength = 0
  local longestCommands = nil

  for i = 1, #selectedUnits do
      local unitID = selectedUnits[i]
      local unitDef = GetUnitDef(unitID)
      if unitDef and not unitDef.isBuilder then

        local commands = spGetUnitCommands(unitID, -1)
        if commands then 
          local queueLength = #commands

          if queueLength > longestQueueLength then
              longestQueueUnitID = unitID
              longestQueueLength = queueLength
              longestCommands = commands
          end
        end
      end
  end

  return longestQueueUnitID, longestCommands
end

function distributeLongest(_, _, args)
  --if not heldDown then return end

  local unitID, commands = GetUnitWithLongestQueue()
      
  if commands then
    cmdStash = commands
    updateNodes()
    executeCommands(true)
  end
end

function distribute(_, _, args)
  if not heldDown then return end
  executeCommands(true)
end


function widget:KeyPress(key, mods, isRepeat)
  if key == 304 then
    heldDown = true
  end

  if not custom_keybind_mode then
--[[     if mods.alt and key == 105 then -- alt-i
      toggleSplitAreaMode()
    end ]]

    if key == 308 then
      distributeLongest()
    end

    if key == 32 then
      distribute()
    end

  end
end


function widget:KeyRelease(key, mods)
  if heldDown and key == 304 then
    heldDown = false
    cmdStash = {}
    nodes = {}
  end
end

-- Execute all cmds in cmdStash
function executeCommands(noShift)

  if #cmdStash == 0 then return end

  local unitArr = {}
  local orderArr = {}
  
  local numUnits = #selectedUnits
  local numCmds= #cmdStash

  local orders
  if (numUnits <= maxHungarianUnits) then
      orders = GetOrdersHungarian(nodes, selectedUnits, numUnits, false)
  else
      orders = GetOrdersNoX(nodes, selectedUnits, numUnits, false)
  end

  for i=1, #orders do
    local orderPair = orders[i]
    local unitID = orderPair[1]
    local nodeItem = orderPair[2]
    local cmdItem = nodeItem[4]
    local cmdID = cmdItem[1] or cmdItem.id
    local options = cmdItem.options
    local params = cmdItem.params
    local altOpts = GetCmdOpts(true, false, false, false, false)
    local cmdOpts 

    if insert_mode and (cmdItem[1] ~= 34923) and not queueSplit then -- settarget cannot be inserted
      cmdOpts = GetCmdOpts(false, false, true, true, false)
      GiveNotifyingOrderToUnit(unitArr, orderArr, orderPair[1], CMD.INSERT, {0, cmdID, cmdOpts.coded, unpack(params)}, altOpts)
    else
      if cmdItem[1] == 34923 or noShift then -- settarget must not be queued
        cmdOpts = GetCmdOpts(options.alt, options.ctrl, false, false, false)
      else
        cmdOpts = GetCmdOpts(options.alt, options.ctrl, options.meta, not noShift, false)
      end
      GiveNotifyingOrderToUnit(unitArr, orderArr, unitID, cmdID, cmdItem.params, cmdOpts)
    end
    
      if (i == #orders and #unitArr > 0) or #unitArr >= 100 then
        spGiveOrderArrayToUnitArray(unitArr, orderArr, true)
        unitArr = {}
        orderArr = {}
    end
  end

  spGiveOrderArrayToUnitArray(unitArr, orderArr, true)
 
  cmdStash = {}   -- empty cmdStash when we're done
  nodes = {}
end

-- This turns cmds into nodes for matching alg
function updateNodes()
  local numUnits = #selectedUnits
  local numCmds = #cmdStash 
  local numPerGroup = floor(numUnits/numCmds) 
  local numLeftOvers = numUnits % numCmds
  local numInGroup = {} -- the precise number in each group
  for i = 1, numCmds do
    numInGroup[i] = numPerGroup
    if i <= numLeftOvers then numInGroup[i] = numPerGroup + 1 end
  end

  if numUnits == 0 or numCmds == 0 then
    nodes = {}
    return false
  end

  -- bin nodes into coordinates of CmdStash elements
  local count = 1
  for i, cmdItem in ipairs(cmdStash) do
    local cx, cy, cz = GetCommandPos(cmdItem)
    -- node format: {number x, number y, number z, cmdItem cmd}
    local curCommandNode = {cx, cy, cz, cmdItem}
    for j = count, count + numInGroup[i] - 1 do
      nodes[j] = curCommandNode
    end
    count = count + numInGroup[i]
  end

  --echo("nodes updated!: "..tableToString(nodes))
end


function isHostile(unitID)
  local myTeamID = spGetMyTeamID()
  local unitTeamID = spGetUnitTeam(unitID)
  
  -- Check if the unit's team is not allied with your team
  return not spAreTeamsAllied(myTeamID, unitTeamID)
end

-- intercept commands issued during heldDown and save them
function widget:CommandNotify(id, cmdParams, cmdOpts)

    -- if build id and shift + meta are held down, 
    -- we skip this whole thing because split build could be used
    local alt, ctrl, meta, shift = GetModKeys()
    if id < 0 then  -- skip builds
      heldDown = false
      cmdStash = {}
      nodes = {}
      return false
    end

    -- OTHERWISE:
    -- add command to cmdStash if keys held
    if heldDown then
      -- { number id, params = table params, options = table opts }
      cmdOpts = GetCmdOpts(cmdOpts.alt, cmdOpts.ctrl, cmdOpts.meta,cmdOpts.shift,false)
      local cmdItem = { id, params = cmdParams, options = cmdOpts } 
      if split_area_mode and cmdParams[4] then
        -- figure out what kind of units to filter
        local areaUnits = spGetUnitsInCylinder(cmdParams[1],cmdParams[3],cmdParams[4])
        local areaFeatures = spGetFeaturesInCylinder(cmdParams[1],cmdParams[3],cmdParams[4])

        -- feature command
        if featureCmds[id] then
          -- simply grab all features and create commands
          for i=1, #areaFeatures do
            local cmdCopy = deepCopy(cmdItem)
            cmdCopy.params = {areaFeatures[i]+32000}
            if #cmdStash < #selectedUnits then cmdStash[#cmdStash+1] = cmdCopy end
          end
        end

        -- friendly command
        if friendlyCmds[id] then
          for i=1, #areaUnits do
            local unitID = areaUnits[i]
            if not isHostile(unitID) then
              local cmdCopy = deepCopy(cmdItem)
              cmdCopy.params = {unitID}
              if #cmdStash < #selectedUnits then cmdStash[#cmdStash+1] = cmdCopy end
            end
          end
        end

        -- hostile command
        if hostileCmds[id] then
          for i=1, #areaUnits do
            local unitID = areaUnits[i]
            if isHostile(unitID) then
              local cmdCopy = deepCopy(cmdItem)
              cmdCopy.params = {unitID}
              if #cmdStash < #selectedUnits then cmdStash[#cmdStash+1] = cmdCopy end
            end
          end
        end
        updateNodes()
        return false
      end

      if #cmdStash < #selectedUnits then  -- we will not queue more if we have more cmds than units
        cmdStash[#cmdStash+1] = cmdItem
        updateNodes()
        --echo("CMD added! cmdID: "..tostring(id)..", name: "..tostring(CMD[id])..", cmdParams: "..tableToString(cmdParams)..", cmdOpts"..tableToString(cmdOpts))
      end
      return false -- to block or not to block
    end
end

---------------------------------------------------------------------------------------------------------
-- Matching Algorithms
---------------------------------------------------------------------------------------------------------
function GetOrdersNoX(nodes, units, unitCount, shifted)

  -- Remember when  we start
  -- This is for capping total time
  -- Note: We at least complete initial assignment
  local startTime = osclock()

  ---------------------------------------------------------------------------------------------------------
  -- Find initial assignments
  ---------------------------------------------------------------------------------------------------------
  local unitSet = {}
  local fdist = -1
  local fm

  for u = 1, unitCount do

    -- Get unit position
    local ux, uz
    if shifted then
        ux, _, uz = GetUnitFinalPosition(units[u])
    else
        ux, _, uz = spGetUnitPosition(units[u])
    end
    if ux then
      unitSet[u] = {ux, units[u], uz, -1} -- Such that x/z are in same place as in nodes (So we can use same sort function)

      -- Work on finding furthest points (As we have ux/uz already)
      for i = u - 1, 1, -1 do

        local up = unitSet[i]
        local vx, vz = up[1], up[3]
        local dx, dz = vx - ux, vz - uz
        local dist = dx*dx + dz*dz

        if (dist > fdist) then
          fdist = dist
          fm = (vz - uz) / (vx - ux)
        end
      end
    end
  end

  -- Maybe nodes are further apart than the units
  for i = 1, unitCount - 1 do

    local np = nodes[i]
    local nx, nz = np[1], np[3]

    for j = i + 1, unitCount do

        local mp = nodes[j]
        local mx, mz = mp[1], mp[3]
        local dx, dz = mx - nx, mz - nz
        local dist = dx*dx + dz*dz

        if (dist > fdist) then
            fdist = dist
            fm = (mz - nz) / (mx - nx)
        end
    end
  end

  local function sortFunc(a, b)
      -- y = mx + c
      -- c = y - mx
      -- c = y + x / m (For perp line)
      return (a[3] + a[1] / fm) < (b[3] + b[1] / fm)
  end

  tsort(unitSet, sortFunc)
  tsort(nodes, sortFunc)

  for u = 1, unitCount do
      unitSet[u][4] = nodes[u]
  end

  ---------------------------------------------------------------------------------------------------------
  -- Main part of algorithm
  ---------------------------------------------------------------------------------------------------------

  -- M/C for each finished matching
  local Ms = {}
  local Cs = {}

  -- Stacks to hold finished and still-to-check units
  local stFin = {}
  local stFinCnt = 0
  local stChk = {}
  local stChkCnt = 0

  -- Add all units to check stack
  for u = 1, unitCount do
      stChk[u] = u
  end
  stChkCnt = unitCount

  -- Begin algorithm
  while ((stChkCnt > 0) and (osclock() - startTime < maxNoXTime)) do

      -- Get unit, extract position and matching node position
      local u = stChk[stChkCnt]
      local ud = unitSet[u]
      local ux, uz = ud[1], ud[3]
      local mn = ud[4]
      local nx, nz = mn[1], mn[3]

      -- Calculate M/C
      local Mu = (nz - uz) / (nx - ux)
      local Cu = uz - Mu * ux

      -- Check for clashes against finished matches
      local clashes = false

      for i = 1, stFinCnt do

          -- Get opposing unit and matching node position
          local f = stFin[i]
          local fd = unitSet[f]
          local tn = fd[4]

          -- Get collision point
          local ix = (Cs[f] - Cu) / (Mu - Ms[f])
          local iz = Mu * ix + Cu

          -- Check bounds
          if ((ux - ix) * (ix - nx) >= 0) and
                  ((uz - iz) * (iz - nz) >= 0) and
                  ((fd[1] - ix) * (ix - tn[1]) >= 0) and
                  ((fd[3] - iz) * (iz - tn[3]) >= 0) then

              -- Lines cross

              -- Swap matches, note this retains solution integrity
              ud[4] = tn
              fd[4] = mn

              -- Remove clashee from finished
              stFin[i] = stFin[stFinCnt]
              stFinCnt = stFinCnt - 1

              -- Add clashee to top of check stack
              stChkCnt = stChkCnt + 1
              stChk[stChkCnt] = f

              -- No need to check further
              clashes = true
              break
          end
      end

      if not clashes then

          -- Add checked unit to finished
          stFinCnt = stFinCnt + 1
          stFin[stFinCnt] = u

          -- Remove from to-check stack (Easily done, we know it was one on top)
          stChkCnt = stChkCnt - 1

          -- We can set the M/C now
          Ms[u] = Mu
          Cs[u] = Cu
      end
  end

  ---------------------------------------------------------------------------------------------------------
  -- Return orders
  ---------------------------------------------------------------------------------------------------------
  local orders = {}
  for i = 1, unitCount do
      local unit = unitSet[i]
      orders[i] = {unit[2], unit[4]}
  end
  return orders
end

function GetOrdersHungarian(nodes, units, unitCount, shifted)
  -------------------------------------------------------------------------------------
  -------------------------------------------------------------------------------------
  -- (the following code is written by gunblob)
  --   this code finds the optimal solution (slow, but effective!)
  --   it uses the hungarian algorithm from http://www.public.iastate.edu/~ddoty/HungarianAlgorithm.html
  --   if this violates gpl license please let gunblob and me know
  -------------------------------------------------------------------------------------
  -------------------------------------------------------------------------------------
  local t = osclock()

  --------------------------------------------------------------------------------------------
  --------------------------------------------------------------------------------------------
  -- cache node<->unit distances

  local distances = {}
  --for i = 1, unitCount do distances[i] = {} end

  for i = 1, unitCount do

      local uID = units[i]
      local ux, uz

      if shifted then
          ux, _, uz = GetUnitFinalPosition(uID)
      else
          ux, _, uz = spGetUnitPosition(uID)
      end
    if ux then
      distances[i] = {}
      local dists = distances[i]
      for j = 1, unitCount do

        local nodePos = nodes[j]
        local dx, dz = nodePos[1] - ux, nodePos[3] - uz
        dists[j] = floor(sqrt(dx*dx + dz*dz) + 0.5)
        -- Integer distances = greatly improved algorithm speed
      end
    end
  end

  --------------------------------------------------------------------------------------------
  --------------------------------------------------------------------------------------------
  -- find optimal solution and send orders
  local result = findHungarian(distances, unitCount)

  --------------------------------------------------------------------------------------------
  --------------------------------------------------------------------------------------------
  -- determine needed time and optimize the maxUnits limit

  local delay = osclock() - t

  if (delay > maxHngTime) and (maxHungarianUnits > minHungarianUnits) then

      -- Delay is greater than desired, we have to reduce units
      maxHungarianUnits = maxHungarianUnits - 1
  else
      -- Delay is less than desired, so thats OK
      -- To make judgements we need number of units to be close to max
      -- Because we are making predictions of time and we want them to be accurate
      if (#units > maxHungarianUnits*unitIncreaseThresh) then

          -- This implementation of Hungarian algorithm is O(n3)
          -- Because we have less than maxUnits, but are altering maxUnits...
          -- We alter the time, to 'predict' time we would be getting at maxUnits
          -- We then recheck that against maxHngTime

          local nMult = maxHungarianUnits / #units

          if ((delay*nMult*nMult*nMult) < maxHngTime) then
              maxHungarianUnits = maxHungarianUnits + 1
          else
              if (maxHungarianUnits > minHungarianUnits) then
                  maxHungarianUnits = maxHungarianUnits - 1
              end
          end
      end
  end

  -- Return orders
  local orders = {}
  for i = 1, unitCount do
      local rPair = result[i]
      orders[i] = {units[rPair[1]], nodes[rPair[2]]}
  end

  return orders
end

function findHungarian(array, n)

  -- Vars
  local colcover = {}
  local rowcover = {}
  local starscol = {}
  local primescol = {}

  -- Initialization
  for i = 1, n do
      rowcover[i] = false
      colcover[i] = false
      starscol[i] = false
      primescol[i] = false
  end

  -- Subtract minimum from rows
  for i = 1, n do

      local aRow = array[i]
      local minVal = aRow[1]
      for j = 2, n do
          if aRow[j] < minVal then
              minVal = aRow[j]
          end
      end

      for j = 1, n do
          aRow[j] = aRow[j] - minVal
      end
  end

  -- Subtract minimum from columns
  for j = 1, n do

      local minVal = array[1][j]
      for i = 2, n do
          if array[i][j] < minVal then
              minVal = array[i][j]
          end
      end

      for i = 1, n do
          array[i][j] = array[i][j] - minVal
      end
  end

  -- Star zeroes
  for i = 1, n do
      local aRow = array[i]
      for j = 1, n do
          if (aRow[j] == 0) and not colcover[j] then
              colcover[j] = true
              starscol[i] = j
              break
          end
      end
  end

  -- Start solving system
  while true do

      -- Are we done ?
      local done = true
      for i = 1, n do
          if not colcover[i] then
              done = false
              break
          end
      end

      if done then
          local pairings = {}
          for i = 1, n do
              pairings[i] = {i, starscol[i]}
          end
          return pairings
      end

      -- Not done
      local r, c = stepPrimeZeroes(array, colcover, rowcover, n, starscol, primescol)
      stepFiveStar(colcover, rowcover, r, c, n, starscol, primescol)
  end
end
function doPrime(array, colcover, rowcover, n, starscol, r, c, rmax, primescol)

  primescol[r] = c

  local starCol = starscol[r]
  if starCol then

      rowcover[r] = true
      colcover[starCol] = false

      for i = 1, rmax do
          if not rowcover[i] and (array[i][starCol] == 0) then
              local rr, cc = doPrime(array, colcover, rowcover, n, starscol, i, starCol, rmax, primescol)
              if rr then
                  return rr, cc
              end
          end
      end

      return
  else
      return r, c
  end
end
function stepPrimeZeroes(array, colcover, rowcover, n, starscol, primescol)

  -- Infinite loop
  while true do

      -- Find uncovered zeros and prime them
      for i = 1, n do
          if not rowcover[i] then
              local aRow = array[i]
              for j = 1, n do
                  if (aRow[j] == 0) and not colcover[j] then
                      local i, j = doPrime(array, colcover, rowcover, n, starscol, i, j, i-1, primescol)
                      if i then
                          return i, j
                      end
                      break -- this row is covered
                  end
              end
          end
      end

      -- Find minimum uncovered
      local minVal = huge
      for i = 1, n do
          if not rowcover[i] then
              local aRow = array[i]
              for j = 1, n do
                  if (aRow[j] < minVal) and not colcover[j] then
                      minVal = aRow[j]
                  end
              end
          end
      end

      -- There is the potential for minVal to be 0, very very rarely though. (Checking for it costs more than the +/- 0's)

      -- Covered rows = +
      -- Uncovered cols = -
      for i = 1, n do
          local aRow = array[i]
          if rowcover[i] then
              for j = 1, n do
                  if colcover[j] then
                      aRow[j] = aRow[j] + minVal
                  end
              end
          else
              for j = 1, n do
                  if not colcover[j] then
                      aRow[j] = aRow[j] - minVal
                  end
              end
          end
      end
  end
end
function stepFiveStar(colcover, rowcover, row, col, n, starscol, primescol)

  -- Star the initial prime
  primescol[row] = false
  starscol[row] = col
  local ignoreRow = row -- Ignore the star on this row when looking for next

  repeat
      local noFind = true

      for i = 1, n do

          if (starscol[i] == col) and (i ~= ignoreRow) then

              noFind = false

              -- Unstar the star
              -- Turn the prime on the same row into a star (And ignore this row (aka star) when searching for next star)

              local pcol = primescol[i]
              primescol[i] = false
              starscol[i] = pcol
              ignoreRow = i
              col = pcol

              break
          end
      end
  until noFind

  for i = 1, n do
      rowcover[i] = false
      colcover[i] = false
      primescol[i] = false
  end

  for i = 1, n do
      local scol = starscol[i]
      if scol then
          colcover[scol] = true
      end
  end
end

-- Helper functions from here
function GetModKeys()
  local alt, ctrl, meta, shift = spGetModKeyState()

  if spGetInvertQueueKey() then -- Shift inversion
      shift = not shift
  end

  return alt, ctrl, meta, shift
end

function GetUnitFinalPosition(uID)
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

function GiveNotifyingOrderToUnit(uArr, oArr, uID, cmdID, cmdParams, cmdOpts)
  for _, w in ipairs(widgetHandler.widgets) do
      if w.UnitCommandNotify and w:UnitCommandNotify(uID, cmdID, cmdParams, cmdOpts) then
          return
      end
  end

  uArr[#uArr + 1] = uID
  oArr[#oArr + 1] = {cmdID, cmdParams, cmdOpts.coded}
  return
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

function GetUnitOrFeaturePosition(id)
	if id <= Game.maxUnits then
		return Spring.GetUnitPosition(id)
	else
		return Spring.GetFeaturePosition(id-Game.maxUnits)
	end
end

function GetCommandPos(command)
  local cmdID = command[1] or command.id
  if not cmdID then
    --echo("Error in getting pos for command: "..tableToString(command))
    return -10,-10,-10
  end
  if (cmdID < 0) or positionCmds[cmdID] then
    if table.getn(command.params) >= 3 then
		  return command.params[1], command.params[2], command.params[3]			
	  elseif table.getn(command.params) >= 1 then
		  return GetUnitOrFeaturePosition(command.params[1])
	  end	
	end
  return -10,-10,-10
end

-- Defunct inefficient alg for grouping stuff
function groupPoints(X, N)
  -- Function to calculate the Euclidean distance between two points
  local function calculateDistance(point1, point2)
      local dx = point2.x - point1.x
      local dy = point2.y - point1.y

      return math.sqrt(dx * dx + dy * dy)
  end

  -- Step 1: Translate centroid of N onto the centroid of X
  local centroidX = {x = 0, y = 0}
  local centroidN = {x = 0, y = 0}

  for _, point in ipairs(X) do
      centroidX.x = centroidX.x + point.x
      centroidX.y = centroidX.y + point.y
  end
  centroidX.x = centroidX.x / #X
  centroidX.y = centroidX.y / #X

  for _, point in ipairs(N) do
      centroidN.x = centroidN.x + point.x
      centroidN.y = centroidN.y + point.y
  end
  centroidN.x = centroidN.x / #N
  centroidN.y = centroidN.y / #N

  local translation = {x = centroidX.x - centroidN.x, y = centroidX.y - centroidN.y}
  local NN = {}

  for _, point in ipairs(N) do
      local translatedPoint = {x = point.x + translation.x, y = point.y + translation.y}
      table.insert(NN, translatedPoint)
  end

  -- Step 2: Split X into groups closest to points in NN
  local groups = {}
  local assignedCount = {}
  local groupCount = #NN

  -- Initialize group counts
  for i = 1, groupCount do
      assignedCount[i] = 0
      groups[i] = {}
  end

  -- Iterate through points in X and assign them to the closest group
  for _, pointX in ipairs(X) do
      local minDistance = math.huge
      local closestGroup

      for i, pointN in ipairs(NN) do
          local distance = calculateDistance(pointX, pointN)

          if distance < minDistance and assignedCount[i] < math.ceil(#X / groupCount) then
              minDistance = distance
              closestGroup = i
          end
      end

      table.insert(groups[closestGroup], pointX)
      assignedCount[closestGroup] = assignedCount[closestGroup] + 1
  end

  -- Remove duplicates from the groups
  for i, group in ipairs(groups) do
      local uniqueGroup = {}
      local uniquePoints = {}

      for _, point in ipairs(group) do
          local key = point.x .. "," .. point.y

          if not uniquePoints[key] then
              table.insert(uniqueGroup, point)
              uniquePoints[key] = true
          end
      end

      groups[i] = uniqueGroup
  end

  return groups
end