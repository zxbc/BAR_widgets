function widget:GetInfo()
    return {
       name = "Dynamic graphical settings",
       desc = "Automatically dials down graphical settings to increase fps. Dials settings back up when fps is good. Only affects shadow, ssao and bloom for now.",
       author = "Errrrrrr",
       date = "May 8, 2023",
       version = "1.1",
       license = "GNU GPL, v2 or later",
       layer = 0,
       enabled = true,
       handler = true
    }
end

------------------------------------------------------------------------------------------------------
-- Version 1.1:
--
-- This widget will monitor your fps and turn down shadow, ssao and bloom settings when fps is low
-- Only changes "quality" settings, and does not touch other ones such as strength and brightness
-- Settings will be turned down when fps drops below targetFPS for a while
-- Settings will be turned back up to normal after fps stays above normalFPS for a while
-- adjustmentSpeed determines how long it waits when above/below normal/target before changes are made
--
-- 1.1: 
-- You can now set lowestSettings to restrict adjustment from going below these values
------------------------------------------------------------------------------------------------------

--[[ 
    There are at least two ways to use this widget:

    1. Simply set targetFPS to 30 and normalFPS to 60 or higher, so that your settings will only be turned 
    down when game becomes unplayable

    2. You could set targetFPS to an "acceptable FPS" level such as 60, and normalFPS to +30 at 90, and
    then turn shadow, ssao and bloom to highest settings in the options and let the widget find your ideal
    settings automatically at all times. This might result in frequent adjustments though, so you may want
    to test a few different FPS gaps to see which gives you the best result.

    If you run the game at 60fps max, then you may want to set targetFPS to 30 and normalFPS to 50. You can
    also opt to activate it only at extreme lag by setting targetFPS to a low number like 10 and normalFPS
    to something like 30.
 ]]

local targetFPS = 45                   -- Below this FPS the settings will start to be turned down
local normalFPS = targetFPS + 13        -- Above this FPS the settings will be turned back up
                                        -- NOTE: normalFPS should be at least 15-20 FPS above targetFPS to avoid ping pong adjustments
local adjustmentSpeed = 5       -- The number of consecutive seconds to wait before adjustment is made both up and down
local consoleOutput = true      -- set to false to prevent printout to console when adjustment is made

local lowestSettings = {    -- The lowest settings of each allowed. 0 means to turn it off (only for ssao and bloom)
        shadow = 1,         -- shadow range is from 1 to 6
        ssao = 1,           -- ssao range is from 0 to 3
        bloom = 1           -- bloom range is from 0 to 3
}

-- local vars
local slow = 0
local normal = 0
local inLowSetting = false
local inNormalSetting = true
local settingsChanged = false

local fakeFPS = 50

-- original saved settings
local savedConfig = {
    ssao = 0, bloom = 0, shadow = 1
}

-- current settings
local curConfig = {
    ssao = 0, bloom = 0, shadow = 1
}

-- shadow quality values
local quality = {
    [1] = 2048, [2] = 3584, [3] = 6144, [4] = 8192, [5] = 10240, [6] = 12288
}

-- helper functions copied over from gui_options.lua
function saveOptionValue(widgetName, widgetApiName, widgetApiFunction, configVar, configValue, widgetApiFunctionParam)
	-- if widgetApiFunctionParam not defined then it uses configValue
	if widgetHandler.configData[widgetName] == nil then
		widgetHandler.configData[widgetName] = {}
	end
	if widgetHandler.configData[widgetName][configVar[1]] == nil then
		widgetHandler.configData[widgetName][configVar[1]] = {}
	end
	if configVar[2] ~= nil and widgetHandler.configData[widgetName][configVar[1]][configVar[2]] == nil then
		widgetHandler.configData[widgetName][configVar[1]][configVar[2]] = {}
	end
	if configVar[2] ~= nil then
		if configVar[3] ~= nil then
			widgetHandler.configData[widgetName][configVar[1]][configVar[2]][configVar[3]] = configValue
		else
			widgetHandler.configData[widgetName][configVar[1]][configVar[2]] = configValue
		end
	else
		widgetHandler.configData[widgetName][configVar[1]] = configValue
	end
	if widgetApiName ~= nil and WG[widgetApiName] ~= nil and WG[widgetApiName][widgetApiFunction] ~= nil then
		if widgetApiFunctionParam ~= nil then
			WG[widgetApiName][widgetApiFunction](widgetApiFunctionParam)
		else
			WG[widgetApiName][widgetApiFunction](configValue)
		end
	end
end

function GetWidgetToggleValue(widgetname)
	if widgetHandler.orderList[widgetname] == nil or widgetHandler.orderList[widgetname] == 0 then
		return false
	elseif widgetHandler.orderList[widgetname] >= 1
		and widgetHandler.knownWidgets ~= nil
		and widgetHandler.knownWidgets[widgetname] ~= nil then
		if widgetHandler.knownWidgets[widgetname].active then
			return true
		else
			return 0.5
		end
	end
end

-- update the live settings in game
function applySettings()
    if curConfig.ssao == 0 then
        widgetHandler:DisableWidget('SSAO')
    else
        widgetHandler:EnableWidget('SSAO')
        saveOptionValue('SSAO', 'ssao', 'setPreset', { 'preset' }, curConfig.ssao)
        --ssao = WG['ssao'].setPreset(curConfig.ssao)
    end

    if curConfig.bloom == 0 then
        widgetHandler:DisableWidget('Bloom Shader Deferred')
    else
        widgetHandler:EnableWidget('Bloom Shader Deferred')
        saveOptionValue('Bloom Shader Deferred', 'bloomdeferred', 'setPreset', { 'preset' }, curConfig.bloom)
        --bloom = WG['bloomdeferred'].setPreset(curConfig.bloom)
    end

    if curConfig.shadow == nil then
        curConfig.shadow = 1
        Spring.Echo("shadow nil!")
    end
    if curConfig.shadow < 1 then
        curConfig.shadow = 1
    end
    --Spring.SendCommands("shadows 1 " .. quality[curConfig.shadow])
	--Spring.SetConfigInt("Shadows", 1)
    Spring.SetConfigInt("ShadowMapSize", quality[curConfig.shadow])
    if consoleOutput then 
        Spring.Echo("Graphical settings adjusted! Shadow: " .. curConfig.shadow .. ", SSAO: " .. curConfig.ssao .. ", Bloom: " .. curConfig.bloom)
    end
end

-- make incremental adjustment to settings
function adjustGraphics(down)
    -- For now we adjust all three by 1 every step, maybe change to finer tuning in the future

    local op = down and -1 or 1

    local result = 0

    if ((curConfig.ssao > lowestSettings.ssao) and down) or ((curConfig.ssao < savedConfig.ssao) and (not down)) then
        curConfig.ssao = curConfig.ssao + op
        result = result + 1
    end

    if ((curConfig.bloom > lowestSettings.bloom) and down) or ((curConfig.bloom < savedConfig.bloom) and (not down)) then
        curConfig.bloom = curConfig.bloom + op
        result = result + 1

    end

    if ((curConfig.shadow > lowestSettings.shadow) and down) or ((curConfig.shadow < savedConfig.shadow) and (not down)) then
        curConfig.shadow = curConfig.shadow + op
        result = result + 1
    end

    if result > 0 then
        applySettings()
    end

    --Spring.Echo("adjustments made: ".. result)
    return result
end

-- load saved settings into current settings
function restoreSettings()
    curConfig.ssao = savedConfig.ssao
    curConfig.bloom = savedConfig.bloom
    curConfig.shadow = savedConfig.shadow
    --Spring.Echo("curConfig restored to savedConfig!")

    inLowSetting = false
    inNormalSetting = true
    slow = 0
    normal = 0
    applySettings()
end

-- read from graphical settings in options, and also set into current settings 
function loadSettings()
    local shadowMapSize = tonumber(Spring.GetConfigInt("ShadowMapSize", 2048) or 2048)

    local index = nil
    for i, v in pairs(quality) do
        if v == shadowMapSize then
            index = i
            break
        end
    end
    savedConfig.shadow = index

    local bloom = 3
    local ssao = 3

    if not GetWidgetToggleValue("SSAO") then
        ssao = 0
    else
        --ssao = WG['ssao'].getPreset()
        ssao = widgetHandler.configData['SSAO']['preset']
    end
    savedConfig.ssao = ssao

    if not GetWidgetToggleValue("Bloom Shader Deferred") then
        bloom = 0
    else
        --bloom = WG['bloomdeferred'].getPreset()
        bloom = widgetHandler.configData['Bloom Shader Deferred']['preset']
    end
    savedConfig.bloom = bloom

    --Spring.Echo("Settings loaded into savedConfig!")
    restoreSettings()

end

--FOR DEBUG TESTING ONLY
--[[ function changeTargetFPS(change)
    targetFPS = targetFPS + change
    normalFPS = targetFPS + 30
    Spring.Echo("targetFPS: " .. targetFPS.. "normalFPS: " .. normalFPS)
end

function widget:KeyPress(key, mods, isRepeat)
    if key == 111 then -- 'o'
        --Spring.Echo("o key pressed!")
        changeTargetFPS(1)
    end
	if key == 112 then -- 'p'
        --Spring.Echo("p key pressed!")
        changeTargetFPS(-1)
    end
    if key == 91 then -- '['
        --Spring.Echo("[ key pressed!")
        Spring.Echo("cur SSAO: "..curConfig.ssao..", cur bloom: "..curConfig.bloom..", cur shadow: "..curConfig.shadow)
        Spring.Echo("saved SSAO: "..savedConfig.ssao..", saved bloom: "..savedConfig.bloom..", saved shadow: "..savedConfig.shadow)
    end
end ]]

function widget:Initialize()
    -- check these to make sure user didn't put in bad values
    if lowestSettings.shadow < 1 then lowestSettings.shadow = 1 end
    if lowestSettings.ssao < 0 then lowestSettings.ssao = 0 end
    if lowestSettings.bloom < 0 then lowestSettings.bloom = 0 end

    loadSettings()

--[[     widgetHandler:RegisterGlobal('KeyPress', function(key, mods, isRepeat)
        return self:KeyPress(key, mods, isRepeat)
    end) ]]
end

function widget:Shutdown()
    restoreSettings()
end

local delay = 0
function widget:Update(dt)

    delay = delay + dt
    if delay > 0.1 then     -- frequent update here to check if options menu is open
        if (WG['options'].isvisible()) then
            delay = 0
            if (not settingsChanged) then
                restoreSettings()   -- restore original settings if users is in options
                settingsChanged = true
            end
            return  -- we always skip everything else if options menu is opened
        end
    end

    if delay > 1 then   -- update every 1s to sample fps and make adjustments
        
        delay = 0
        -- if settings changed we need to reinitialize
        if settingsChanged then
            loadSettings()
            settingsChanged = false
        end

        -- read fps, update states
        local fps = Spring.GetFPS()
        --local fps = fakeFPS -- for debug testing
        if fps < targetFPS then 
            slow = slow + 1
            normal = 0
        else 
            slow = 0
            if fps >= (normalFPS) then
                normal = normal + 1
            else
                normal = 0
            end
        end

        -- to avoid spikes triggering adjustments, we only count consecutive lagging updates
        -- if lag x updates in a row it means we're really lagging, otherwise skip and wait
        if slow >= adjustmentSpeed and not inLowSetting then
            --Spring.Echo("FPS low, reducing settings")
            local adjustment = adjustGraphics(true)
           
            if adjustment == 0 then
                inLowSetting = true
            else
                inNormalSetting = false
                slow = 0
            end
        elseif normal >= adjustmentSpeed and not inNormalSetting then
            -- maintained good fps for x consecutive udpates, should be good to increase graphics settings
            --Spring.Echo("FPS normal, increasing settings")
            local adjustment = adjustGraphics(false)
            
            if adjustment == 0 then
                inNormalSetting = true
            else
                inLowSetting = false
                normal = 0
            end
        end
    end
end
