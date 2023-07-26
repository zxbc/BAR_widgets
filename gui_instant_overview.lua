function widget:GetInfo()
    return {
        name    = "Overview - No Transition Animation",
        desc    = "Press and hold 'tab' to instantly switch to a top-down full map overview. Release 'tab' to return to the original view. You can edit param in file to disable hide UI.",
        author  = "Errrrrrr",
        date    = "2023",
        license = "GNU GPL, v2 or later",
        layer   = 0,
        enabled = true,
        handler = true,
    }
end

local hide_all_ui = false   -- Hide all ui elements when in overview mode
                            -- Set this to false if you only want to disable minimap, advplayerslist and chat

local oldCamState = nil
local oldIconsState = nil
local oldCamDir = nil

local viewSizeX, viewSizeY, _, _ = Spring.GetViewGeometry()
local aspectRatio = viewSizeX / viewSizeY
local mapRatio = Game.mapSizeX / Game.mapSizeZ

--[[ 
-- Rotate a vector by an angle around the Y-axis
function rotateVector(vec, angle)
    local cos = math.cos(angle)
    local sin = math.sin(angle)
    return {
        cos * vec[1] + sin * vec[3],
        vec[2],
        -sin * vec[1] + cos * vec[3]
    }
end

-- Multiply a vector by a scalar
function multiplyVector(vec, scalar)
    return {
        vec[1] * scalar,
        vec[2] * scalar,
        vec[3] * scalar
    }
end

-- Add two vectors
function addVectors(vec1, vec2)
    return {
        vec1[1] + vec2[1],
        vec1[2] + vec2[2],
        vec1[3] + vec2[3]
    }
end

-- Subtract two vectors
function subtractVectors(vec1, vec2)
    return {
        vec1[1] - vec2[1],
        vec1[2] - vec2[2],
        vec1[3] - vec2[3]
    }
end


local function calculateTrapezoidCorners(camState, dir)
    -- Calculate the forward, right, and up vectors
    local forward = {dir[1], dir[2], dir[3]}
    local right = {dir[3], 0, -dir[1]}  -- cross product of dir and up = {0, 1, 0}
    local up = {0, 1, 0}  -- points straight up in Y
    -- normalize direction vectors
    local lenForward = math.sqrt(forward[1]*forward[1] + forward[2]*forward[2] + forward[3]*forward[3])
    forward[1], forward[2], forward[3] = forward[1]/lenForward, forward[2]/lenForward, forward[3]/lenForward

    local lenRight = math.sqrt(right[1]*right[1] + right[2]*right[2] + right[3]*right[3])
    right[1], right[2], right[3] = right[1]/lenRight, right[2]/lenRight, right[3]/lenRight

    local lenUp = math.sqrt(up[1]*up[1] + up[2]*up[2] + up[3]*up[3])
    up[1], up[2], up[3] = up[1]/lenUp, up[2]/lenUp, up[3]/lenUp

    local height = camState.height or 0
    if height == 0 then height = camState.dist end
    local halfWidth = height * math.tan(math.rad(camState.fov / 2))  -- horizontal half-width
    local halfHeight = halfWidth / aspectRatio  -- vertical half-height (adjusted by the aspect ratio)

    -- Calculate the four corners of the trapezoid
    local center = {camState.px, camState.py, camState.pz}
    local d1 = multiplyVector(up, halfHeight)
    local d2 = multiplyVector(right, halfWidth)
    local p1 = addVectors(subtractVectors(center, d1), d2)
    local p2 = addVectors(addVectors(center, d1), d2)
    local p3 = subtractVectors(addVectors(center, d1), d2)
    local p4 = subtractVectors(subtractVectors(center, d1), d2)

    return p1, p2, p3, p4
end
 ]]
function widget:KeyPress(key, mods, isRepeat)
    if key == Spring.GetKeyCode("tab") then
        if not oldCamState then
            -- Save the original camera state and icons state
            oldCamState = Spring.GetCameraState()
            oldIconsState = Spring.GetConfigInt("icons", 1)

            -- Save the current camera direction
            oldCamDir = {Spring.GetCameraDirection()}

            -- Hide the chat using the chat widget's function
            if WG['chat'] then
                WG['chat'].setHide(true)
            end

            -- Disable the engine's minimap
            Spring.SendCommands("minimap minimize 1")
            -- Disable advplayerslist widget
            --widgetHandler:DisableWidget('AdvPlayersList')

            if hide_all_ui then
                Spring.SendCommands("HideInterface")
            end

            -- Switch to the custom view
            local camState = Spring.GetCameraState()
            camState.name = "ta"
            camState.mode = 1
            camState.px = Game.mapSizeX * 0.5
            camState.py = Spring.GetGroundHeight(Game.mapSizeX * 0.5, Game.mapSizeZ * 0.5)
            camState.pz = Game.mapSizeZ * 0.5
            camState.rx = oldCamState.rx or 0
            camState.ry = oldCamState.ry or 0
            camState.rz = oldCamState.rz or 0

            if mapRatio > aspectRatio then
                camState.height = Game.mapSizeX / (2 * math.tan(math.rad(camState.fov / 2)))
            else
                camState.height = Game.mapSizeZ / (2 * math.tan(math.rad(camState.fov / 2))) * aspectRatio
            end

            camState.height = camState.height * 0.6

            camState.angle = 0.0
            Spring.SetCameraState(camState, 0)
            Spring.SendCommands("viewicons") -- enable icons
        end
        return true -- block the event from other widgets or game default functionality
    end
    return false
end

function widget:KeyRelease(key)
    if key == Spring.GetKeyCode("tab") then
        if oldCamState then
            -- Restore the original camera state and icons state
            Spring.SetCameraState(oldCamState, 0)
            Spring.SendCommands("icons " .. oldIconsState) -- restore icons state
            oldCamState = nil
            oldIconsState = nil
            oldCamDir = nil

            -- Show the chat using the chat widget's function
            if WG['chat'] then
                WG['chat'].setHide(false)
            end

            -- Re-enable the engine's minimap
            Spring.SendCommands("minimap minimize 0")
            -- Re-enable advplayerslist widget
            --widgetHandler:EnableWidget('AdvPlayersList')

            if hide_all_ui then
                Spring.SendCommands("HideInterface")
            end
        end
        return true -- block the event from other widgets or game default functionality
    end
    return false
end

function widget:DrawWorld()
    if oldCamState then
        -- Calculate the previous camera's position
        local px, py, pz = oldCamState.px, oldCamState.py, oldCamState.pz

        -- Setup circle parameters
        local maxRadius = oldCamState.height or 0
        if maxRadius == nil then maxRadius = oldCamState.dist or 0 end -- maximum radius of the circle is now the camera's height
        if maxRadius == 0 then maxRadius = 1000
        else maxRadius = maxRadius / 2 end  -- if the camera's height is 0, set the maximum radius to 1000
        local shrinkTime = 0.5  -- how long it takes for the circle to shrink to the center, halved for a faster shrink
        local pauseTime = 1  -- pause time in seconds between each shrink

        -- Draw the pulsing circle
        gl.Color(0, 1, 0, 1)  -- green color
        -- Calculate a shrinking radius
        local time = Spring.GetGameSeconds()
        local phase = time % (shrinkTime + pauseTime)  -- phase of the shrink-pause cycle
        if phase < shrinkTime then  -- during the shrinking animation
            local radius = (1 - phase / shrinkTime) * maxRadius
            -- Draw the circle
            gl.DrawGroundCircle(px, py, pz, radius, 128)  -- 128 is the number of vertices, adjust for performance
        end
        gl.Color(1, 1, 1, 1)  -- reset color to white
    end
end






