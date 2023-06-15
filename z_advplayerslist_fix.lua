function widget:GetInfo()
	return {
		name	= "z Advplayerslist widget fix",
		desc	= "This just reloads that widget 1s after loading to fix it so you don't have to do the slower /luaui reload",
		author	= "Errrrrrr",
		date	= "June 2023",
		license = "GNU GPL, v2 or later",
		layer	= 999999+1,
        handler = true,
		enabled	= true,
	}
end

function widget:Initialize()
    widgetHandler:DisableWidget("AdvPlayersList")
end

local gameFrame = 0
function widget:Update(dt)
	gameFrame = gameFrame + 1
	if gameFrame == 30 then
		widgetHandler:EnableWidget("AdvPlayersList")
		widgetHandler:RemoveWidgetCallIn("Update", self)
	end
end