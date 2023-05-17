function widget:GetInfo()
    return {
       name = "Toggle Simple Team Colors",
       desc = "Turns simple team colors option on and off with a keybind. Default toggle key is 'o', rebindable through custom keybind, using action 'toggle_simple_team_colors'",
       author = "Errrrrrr",
       date = "May, 2023",
       license = "GNU GPL, v2 or later",
       layer = 0,
       enabled = true,
       handler = true
    }
end

--------------------------------------------------------------
-- Default key is "o" (the letter)
--
-- Set below to true to use your own keybind
-- Keybind name to use: "toggle_simple_team_colors"
local custom_keybind_mode = false
--------------------------------------------------------------


function widget:Initialize()
    widgetHandler.actionHandler:AddAction(self, "toggle_simple_team_colors", toggleTeamColors, nil, "p")
end

function toggleTeamColors(_, _, args)
    local teamColorsSetting = Spring.GetConfigInt("SimpleTeamColors", 0)
    if not teamColorsSetting then return end
    teamColorsSetting = (teamColorsSetting + 1) % 2
    Spring.SetConfigInt("SimpleTeamColors", teamColorsSetting)
    Spring.SetConfigInt("UpdateTeamColors", 1)
end

function widget:KeyPress(key, mods, isRepeat)
    if not custom_keybind_mode then
        if key == 111 then   -- key 'o'
            toggleTeamColors()
        end
    end
end 