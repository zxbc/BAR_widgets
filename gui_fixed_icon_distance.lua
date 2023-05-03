function widget:GetInfo()
    return {
       name = "Fixed Icon Distance",
       desc = "Makes it so all icons will fade in/out at the same camera distance. V2 improved a few things.",
       author = "Errrrrrr",
       version = "2.0",
       date = "April 27, 2023",
       license = "GNU GPL, v2 or later",
       layer = 0,
       enabled = true,
    }
end

------------------------------------------------------------------------------
-- Version 2 changes update interval to 0.2s, consolidated code, fixed bugs
------------------------------------------------------------------------------

local iconDistanceSetting = 2700 -- default to 2700 which is also options settings default
local lastCamHeight = 0
local lastIconHeight = 0

local spSendCommands = Spring.SendCommands
local spGetCameraState = Spring.GetCameraState

local reverted = false

function setIconHeight(height)
    if (height == lastIconHeight) then return end   -- no need for any adjustment

    --spSendCommands("iconfadestart " .. height)
    spSendCommands("iconfadevanish " .. height)
    lastIconHeight = height
    -- Spring.Echo("icon fade height changed to: " .. height)
end

function getCamHeight()
    local cs = spGetCameraState()
    local ch = 0

    if (cs.name == "ta") then
        ch = cs.height
    elseif (cs.name == "spring") then
        ch = cs.dist
    elseif (cs.name == "ov") then
        ch = 15000
    end
    return ch
end

function widget:Initialize()
    iconDistanceSetting = Spring.GetConfigInt("UnitIconFadeVanish", 2700) -- Save default camera distance first
    -- Spring.Echo("Icon distance setting read: " .. iconDistanceSetting) 
end

function widget:Shutdown()
	setIconHeight(iconDistanceSetting)  -- change settings back to default
end

function revert()
    if reverted then return end
    reverted = true
    --Spring.SetConfigInt("UnitIconFadeStart", iconDistanceSetting)
    Spring.SetConfigInt("UnitIconFadeVanish", iconDistanceSetting)
end

local delay = 0
function widget:Update(dt)

    delay = delay + dt
    if delay < 0.2 then return end  -- don't update more frequently than every 0.2s

    delay = 0

    if (WG['options'].isvisible()) then
        revert()
    end

    if reverted then
        -- Need to read from settings again since user might have changed it
        iconDistanceSetting = Spring.GetConfigInt("UnitIconFadeVanish", 2700)
        reverted = false
    end

    local curHeight = getCamHeight()
    if (curHeight == lastCamHeight) then return end -- do nothing if no change to camera height

    if (curHeight > iconDistanceSetting) then
        setIconHeight(1)    -- bruteforce show all icons
    else
        setIconHeight(15000)    -- bruteforce hide all icons
    end
    lastCamHeight = curHeight
end



