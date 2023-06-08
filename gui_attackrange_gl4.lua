include("keysym.h.lua")

function widget:GetInfo()
	return {
		name      = "Attack Range GL4",
		desc      = "Displays attack ranges of selected units. Can bind keys to toggle cursor unit range and all unit ranges on and off.",
		author    = "Errrrrrr, Beherith",
		date      = "June 2023",
		version   = "1.0",
		license   = "GPLv2",
		layer     = -100,
		enabled   = true,
		handler   = true,
	}
end
---------------------------------------------------------------------------------------------------------------------------
-- Bindable action:   cursor_range_toggle
---------------------------------------------------------------------------------------------------------------------------
local cursor_unit_range = true    -- displays the range of the unit at the mouse cursor (if there is one)
local group_selection_fade_scale = 0.35 -- can set to 0 to have inner rings not dim at all with large group selection

-- alpha settings
local outer_ring_alpha = 0.88    -- this is the outer edge formed by the stenciled rings
local inner_ring_alpha = 0.15    -- this is the inner rings that overlap from each unit
                                -- note that units with multiple weapons also rely on this to display their short ranges
                                -- if you want to reduce clutter with large unit count, turn up group_selection_fade_scale
local fill_alpha = 0.12        -- this is the solid color in the middle of the stencil

---------------------------------------------------------------------------------------------------------------------------
local show_selected_weapon_ranges = true
local innerRingDim = 1    -- don't change this

------------------ CONFIGURABLES --------------

local buttonConfig = {
    ally = { ground = true, air = true, nuke = true , nano = true},
    enemy = { ground = true, air = true, nuke = true , nano = true}
}

local colorConfig = { --An array of R, G, B, Alpha
    drawStencil = true, -- wether to draw the outer, merged rings (quite expensive!)
    drawInnerRings = true, -- wether to draw inner, per defense rings (very cheap)
    externalalpha = outer_ring_alpha, -- alpha of outer rings
    internalalpha = inner_ring_alpha, -- alpha of inner rings
    distanceScaleStart = 2000, -- Linewidth is 100% up to this camera height
    distanceScaleEnd = 4000, -- Linewidth becomes 50% above this camera height
    ground = {
        color = {1.0, 0.2, 0.2, 1.0},
        fadeparams = { 2000, 6000, 1.0, 0.0}, -- FadeStart, FadeEnd, StartAlpha, EndAlpha
        externallinethickness = 3.0,
        internallinethickness = 2.0,
    },
    air = {
        color = {0.2, 1.0, 0.2, 1.0},
        fadeparams = { 2000, 6000, 0.4, 0.0}, -- FadeStart, FadeEnd, StartAlpha, EndAlpha
        externallinethickness = 3.0,
        internallinethickness = 2.0,
    },
    nuke = {
        color = {0.7, 0.8, 1.0, 1.0},
        fadeparams = {5000, 4000, 0.6, 0.0}, -- FadeStart, FadeEnd, StartAlpha, EndAlpha
        externallinethickness = 4.0,
        internallinethickness = 2.0,
    },
    cannon = {
        color = {1.0, 0.22, 0.05, 1.0},
        fadeparams = {3000, 6000, 1.0, 0.0}, -- FadeStart, FadeEnd, StartAlpha, EndAlpha
        externallinethickness = 3.5,
        internallinethickness = 1.5,
    },
        nano = {
                color = {0.2, 1.0, 0.2, 0.5},
                fadeparams = {2000, 6000, 0.4, 0.0}, -- FadeStart, FadeEnd, StartAlpha, EndAlpha
        externallinethickness = 2.0,
        internallinethickness = 1.0,
        },
}

----------------------------------

local buttonconfigmap ={'ground','air','nuke','ground','nano'}
local DEBUG = false --generates debug message
local weaponTypeMap = {'ground','air','nuke','cannon','nano'}

local unitDefRings = {} --each entry should be  a unitdefIDkey to very specific table:
	-- a list of tables, ideally ranged from 0 where

local mobileAntiUnitDefs = {
	[UnitDefNames.armscab.id ] = true,
	[UnitDefNames.armcarry.id] = true,
	[UnitDefNames.cormabm.id ] = true,
	[UnitDefNames.corcarry.id] = true,
}

local defensePosHash = {} -- key: {poshash=unitID}
-- poshash is 4096 * posx/8 + posz/8

local featureDefIDtoUnitDefID = {} -- this table maps featureDefIDs to unitDefIDs for faster lookups on feature creation

local vtoldamagetag = Game.armorTypes['vtol']
local defaultdamagetag = Game.armorTypes['default']

local function tableToString(t)
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
        result = result .." \n"
      end
    end
  
    return "{" .. result:sub(1, -3) .. "}"
end
local function dumpToFile(obj, prefix, filename)
    local file = assert(io.open(filename, "w"))
    if type(obj) == "table" then
        for k, v in pairs(obj) do
            local key = prefix and (prefix .. "." .. tostring(k)) or tostring(k)
            if type(v) == "function" then
                local info = debug.getinfo(v, "S")
                file:write(key .. " (function) defined in " .. info.source .. " at line " .. info.linedefined .. "\n")
            elseif type(v) == "table" then
                file:write(key .. " (table):\n")
                dumpToFile(v, key, filename)
            else
                file:write(key .. " = " .. tostring(v) .. "\n")
            end
        end
    end
    if type(obj) == "string" then
        file:write(obj)
    end

    file:close()
end
local function initializeUnitDefRing(unitDefID)

	local weapons = UnitDefs[unitDefID].weapons
	unitDefRings[unitDefID]['rings'] = {}
	local weaponCount = #weapons or 0
	for weaponNum = 1, #weapons do
		local weaponDefID = weapons[weaponNum].weaponDef
		local weaponDef = WeaponDefs[weaponDefID]

		local range = weaponDef.range
		local dps = 0
		local weaponType = unitDefRings[unitDefID]['weapons'][weaponNum]
		--Spring.Echo(weaponType)
		if weaponType ~= nil and weaponType > 0 then
			local damage = 0
			if weaponType == 2 then --AA
				damage = weaponDef.damages[vtoldamagetag]
			elseif weaponType == 3 then -- antinuke
				damage = 0
				range = weaponDef.coverageRange
				--Spring.Echo("init antinuke", range)
			else
				damage = weaponDef.damages[defaultdamagetag]
			end
			dps = damage * (weaponDef.salvoSize or 1) / (weaponDef.reload or 1)
			local color = colorConfig[weaponTypeMap[weaponType]].color
			local fadeparams =  colorConfig[weaponTypeMap[weaponType]].fadeparams

			local isCylinder = 0
 			if weaponDef.cylinderTargeting and weaponDef.cylinderTargeting > 0 then -- all non-cannon ground weapons are spheres, aa and antinuke are cyls
				isCylinder = 1
				Spring.Echo("cylinder weapon found!")
			end

			local customParams = weaponDef.customParams
			if customParams and customParams.bogus then
				--Spring.Echo("bogus weapon!")
				range = 0
			end 
			--Spring.Echo("weaponNum: ".. weaponNum ..", name: " .. tableToString(weaponDef.name))
		
--[[ 			local name = tostring(weaponDef.name)
			if string.find(name, "bogus") then
				--Spring.Echo("bogus name found!")
				range = 0
			end ]]

			local ringParams = {range, color[1],color[2], color[3], color[4],
				fadeparams[1], fadeparams[2], fadeparams[3], fadeparams[4],
				weaponDef.projectilespeed or 1,
				isCylinder,
				weaponDef.heightBoostFactor or 0,
				weaponDef.heightMod or 0 }
			unitDefRings[unitDefID]['rings'][weaponNum] = ringParams
		end
	end
	
	-- for builders, we need to add a special nano ring def
	local unitDef = UnitDefs[unitDefID]
	if unitDef.isBuilder then
		local range = unitDef.buildDistance
		local color = colorConfig['air'].color
		local fadeparams = colorConfig['air'].fadeparams
		local ringParams = {range, color[1],color[2], color[3], color[4],
			fadeparams[1], fadeparams[2], fadeparams[3], fadeparams[4],
			1,
			false,
			0,
			0 }
		unitDefRings[unitDefID]['rings'][weaponCount + 1] = ringParams	-- weaponCount + 1 is nano
		--Spring.Echo("added builder! "..tableToString(unitDefRings[unitDef.id]))
	end

end

local function initUnitList()
	unitDefRings = {}

	for unitDefID, _ in pairs(unitDefRings) do
		initializeUnitDefRing(unitDefID)
	end
	-- Initialize Colors too
	local scavlist = {}
	for k,_ in pairs(unitDefRings) do
		scavlist[k] = true
	end
	-- add scavs
	for k,_ in pairs(scavlist) do
		--Spring.Echo(k, UnitDefs[k].name)
		if UnitDefNames[UnitDefs[k].name .. '_scav'] then
			unitDefRings[UnitDefNames[UnitDefs[k].name .. '_scav'].id] = unitDefRings[k]
		end
	end

	local scavlist = {}
	for k,_ in pairs(mobileAntiUnitDefs) do
		scavlist[k] = true
	end
	for k,v in pairs(scavlist) do
		mobileAntiUnitDefs[UnitDefNames[UnitDefs[k].name .. '_scav'].id] = mobileAntiUnitDefs[k]
	end

	-- Initialize featureDefIDtoUnitDefID
	local wreckheaps = {"_dead","_heap"}
	for unitDefID,_ in pairs(unitDefRings) do
		local unitDefName = UnitDefs[unitDefID].name
		for i, suffix in pairs(wreckheaps) do
			if FeatureDefNames[unitDefName..suffix] then
				featureDefIDtoUnitDefID[FeatureDefNames[unitDefName..suffix].id] = unitDefID
				--Spring.Echo(FeatureDefNames[unitDefName..suffix].id, unitDefID)
			end
		end
	end

end

--Button display configuration
--position only relevant if no saved config data found

local myAllyTeam = Spring.GetMyAllyTeamID()

--------------------------------------------------------------------------------

local glDepthTest           = gl.DepthTest
local glLineWidth           = gl.LineWidth
local glTexture             = gl.Texture
local glClear				= gl.Clear
local glColorMask			= gl.ColorMask
local glStencilTest			= gl.StencilTest
local glStencilMask			= gl.StencilMask
local glStencilFunc			= gl.StencilFunc
local glStencilOp			= gl.StencilOp
local GL_STENCIL_BUFFER_BIT = GL.STENCIL_BUFFER_BIT
local GL_TRIANGLE_FAN 		= GL.TRIANGLE_FAN
local GL_LEQUAL 			= GL.LEQUAL
local GL_LINE_LOOP			= GL.LINE_LOOP
local GL_NOTEQUAL			= GL.NOTEQUAL

local GL_KEEP = 0x1E00 --GL.KEEP
local GL_REPLACE = GL.REPLACE --GL.KEEP

local spGetPositionLosState = Spring.GetPositionLosState
local spGetUnitDefID        = Spring.GetUnitDefID
local spGetUnitPosition     = Spring.GetUnitPosition
local spGetUnitAllyTeam		= Spring.GetUnitAllyTeam
local spFindUnitCmdDesc		= Spring.FindUnitCmdDesc
local spGetMouseState 		= Spring.GetMouseState
local spTraceScreenRay		= Spring.TraceScreenRay

local chobbyInterface

function widget:TextCommand(command)
	local mycommand=false --buttonConfig["enemy"][tag]

	if string.find(command, "defrange", nil, true) then
		mycommand = true
		local ally = 'ally'
		local rangetype = 'ground'
		local enabled = false
		if string.find(command, "enemy", nil, true) then
			ally = 'enemy'
		end
		if string.find(command, "air", nil, true) then
			rangetype = 'air'
		elseif string.find(command, "nuke", nil, true) then
			rangetype = 'nuke'
		end
		if string.find(command, "+", nil, true) then
			enabled = true
		end
		buttonConfig[ally][rangetype]=enabled
		Spring.Echo("Range visibility of "..ally.." "..rangetype.." defenses set to",enabled)
		return true
	end

	return false
end

------ GL4 THINGS  -----
-- nukes and cannons:
local largeCircleVBO = nil
local largeCircleSegments = 512

-- others:
local smallCircleVBO = nil
local smallCircleSegments = 128

local weaponTypeToString = {"ground","air","nuke","cannon","nano"}
local allyenemypairs = {"ally","enemy"}
local defenseRangeClasses = {'enemyair','enemyground','enemynuke','enemynano', 'allyair','allyground','allynuke','enemycannon','allycannon','allynano'}
local defenseRangeVAOs = {}

local circleInstanceVBOLayout = {
		  {id = 1, name = 'posscale', size = 4}, -- a vec4 for pos + scale
		  {id = 2, name = 'color1', size = 4}, --  vec4 the color of this new
		  {id = 3, name = 'visibility', size = 4}, --- vec4 heightdrawstart, heightdrawend, fadefactorin, fadefactorout
		  {id = 4, name = 'projectileParams', size = 4}, --- heightboost gradient
		  {id = 5, name = 'instData', size = 4, type = GL.UNSIGNED_INT},
		}

local luaShaderDir = "LuaUI/Widgets/Include/"
local LuaShader = VFS.Include(luaShaderDir.."LuaShader.lua")
VFS.Include(luaShaderDir.."instancevbotable.lua")
local attackRangeShader = nil


local function goodbye(reason)
  Spring.Echo("DefenseRange GL4 widget exiting with reason: "..reason)
  widgetHandler:RemoveWidget()
end

local function makeCircleVBO(circleSegments)
	circleSegments  = circleSegments -1 -- for po2 buffers
	local circleVBO = gl.GetVBO(GL.ARRAY_BUFFER,true)
	if circleVBO == nil then goodbye("Failed to create circleVBO") end

	local VBOLayout = {
	 {id = 0, name = "position", size = 4},
	}

	local VBOData = {}

	for i = 0, circleSegments  do -- this is +1
		VBOData[#VBOData+1] = math.sin(math.pi*2* i / circleSegments) -- X
		VBOData[#VBOData+1] = math.cos(math.pi*2* i / circleSegments) -- Y
		VBOData[#VBOData+1] = i / circleSegments -- circumference [0-1]
		VBOData[#VBOData+1] = 0
	end

	circleVBO:Define(
		circleSegments + 1,
		VBOLayout
	)
	circleVBO:Upload(VBOData)
	return circleVBO
end

local vsSrc = [[
	#version 420
	#extension GL_ARB_uniform_buffer_object : require
	#extension GL_ARB_shader_storage_buffer_object : require
	#extension GL_ARB_shading_language_420pack: require
	#line 10000
	
	//__DEFINES__
	
	layout (location = 0) in vec4 circlepointposition;
	layout (location = 1) in vec4 posscale;
	layout (location = 2) in vec4 color1;
	layout (location = 3) in vec4 visibility; // FadeStart, FadeEnd, StartAlpha, EndAlpha
	layout (location = 4) in vec4 projectileParams; // projectileSpeed, iscylinder!!!! , heightBoostFactor , heightMod
	layout (location = 5) in uvec4 instData;
	
	uniform float lineAlphaUniform = 1.0;
	uniform float cannonmode = 0.0;
	
	uniform sampler2D heightmapTex;
	uniform sampler2D losTex; // hmm maybe?
	
	out DataVS {
		flat vec4 blendedcolor;
		vec4 circleprogress;
	};
	
	//__ENGINEUNIFORMBUFFERDEFS__
	
	
	layout(std140, binding=0) readonly buffer MatrixBuffer {
		mat4 UnitPieces[];
	};
	
	
	#line 11000
	
	float heightAtWorldPos(vec2 w){
		vec2 uvhm =  heighmapUVatWorldPos(w);
		return textureLod(heightmapTex, uvhm, 0.0).x;
	}
	
	float GetRangeFactor(float projectileSpeed) { // returns >0 if weapon can shoot here, <0 if it cannot, 0 if just right
		// on first run, with yDiff = 0, what do we get?
		float speed2d = projectileSpeed * 0.707106;
		float gravity =  120.0 	* (0.001111111);
		return ((speed2d * speed2d) * 2.0 ) / (gravity);
	}
	
	float GetRange2DCannon(float yDiff,float projectileSpeed,float rangeFactor,float heightBoostFactor) { // returns >0 if weapon can shoot here, <0 if it cannot, 0 if just right
		// on first run, with yDiff = 0, what do we get?
	
		//float factor = 0.707106;
		float smoothHeight = 100.0;
		float speed2d = projectileSpeed*0.707106;
		float speed2dSq = speed2d * speed2d;
		float gravity = -1.0*  (120.0 /900);
	
		if (heightBoostFactor < 0){
			heightBoostFactor = (2.0 - rangeFactor) / sqrt(rangeFactor);
		}
	
		if (yDiff < -100.0){
			yDiff = yDiff * heightBoostFactor;
		}else {
			if (yDiff < 0.0) {
				yDiff = yDiff * (1.0 + (heightBoostFactor - 1.0 ) * (-1.0 * yDiff) * 0.01);
			}
		}
	
		float root1 = speed2dSq + 2 * gravity *yDiff;
		if (root1 < 0.0 ){
			return 0.0;
		}else{
			return rangeFactor * ( speed2dSq + speed2d * sqrt( root1 ) ) / (-1.0 * gravity);
		}
	}
	
	//float heightMod  default: 0.2 (0.8 for #Cannon, 1.0 for #BeamLaser and #LightningCannon)
	//Changes the spherical weapon range into an ellipsoid. Values above 1.0 mean the weapon cannot target as high as it can far, values below 1.0 mean it can target higher than it can far. For example 0.5 would allow the weapon to target twice as high as far.
	
	//float heightBoostFactor default: -1.0
	//Controls the boost given to range by high terrain. Values > 1.0 result in increased range, 0.0 means the cannon has fixed range regardless of height difference to target. Any value < 0.0 (i.e. the default value) result in an automatically calculated value based on range and theoretical maximum range.
	
	#define RANGE posscale.w
	#define PROJECTILESPEED projectileParams.x
	#define ISCYLINDER projectileParams.y
	#define HEIGHTBOOSTFACTOR projectileParams.z
	#define HEIGHTMOD projectileParams.w
	#define YGROUND posscale.y
	
	#define OUTOFBOUNDSALPHA alphaControl.y
	#define FADEALPHA alphaControl.z
	#define MOUSEALPHA alphaControl.w
	
	
	void main() {
		// Get the center pos of the unit
		uint baseIndex = instData.x; // this tells us which unit matrix to find
		mat4 modelMatrix = UnitPieces[baseIndex]; // This gives us the models  world pos and rot matrix
		vec3 modelWorldPos = modelMatrix[3].xyz;
		
		circleprogress.xy = circlepointposition.xy;
		circleprogress.w = circlepointposition.z;
		blendedcolor = color1;
		
		// translate to world pos:
		vec4 circleWorldPos = vec4(1.0);
		circleWorldPos.xz = circlepointposition.xy * RANGE +  modelWorldPos.xz;
	
		vec4 alphaControl = vec4(1.0);
	
		// get heightmap
		circleWorldPos.y = heightAtWorldPos(circleWorldPos.xz);
	
	
		if (cannonmode > 0.5){
	
			// BAR only has 3 distinct ballistic projectiles, heightBoostFactor is only a handful from -1 to 2.8 and 6 and 8
			// gravity we can assume to be linear
	
			float heightDiff = (circleWorldPos.y - YGROUND) * 0.5;
	
			float rangeFactor = RANGE /  GetRangeFactor(PROJECTILESPEED); //correct
			if (rangeFactor > 1.0 ) rangeFactor = 1.0;
			if (rangeFactor <= 0.0 ) rangeFactor = 1.0;
			float radius = RANGE;// - heightDiff;
			float adjRadius = GetRange2DCannon(heightDiff * HEIGHTMOD, PROJECTILESPEED, rangeFactor, HEIGHTBOOSTFACTOR);
			float adjustment = radius * 0.5;
			float yDiff = 0;
			float adds = 0;
			//for (int i = 0; i < mod(timeInfo.x/8,16); i ++){ //i am a debugging god
			for (int i = 0; i < 16; i ++){
					if (adjRadius > radius){
						radius = radius + adjustment;
						adds = adds + 1;
					}else{
						radius = radius - adjustment;
						adds = adds - 1;
					}
					adjustment = adjustment * 0.5;
					circleWorldPos.xz = circlepointposition.xy * radius + modelWorldPos.xz;
					float newY = heightAtWorldPos(circleWorldPos.xz );
					yDiff = abs(circleWorldPos.y - newY);
					circleWorldPos.y = max(0, newY);
					heightDiff = circleWorldPos.y - modelWorldPos.y;
					adjRadius = GetRange2DCannon(heightDiff * HEIGHTMOD, PROJECTILESPEED, rangeFactor, HEIGHTBOOSTFACTOR);
			}
		}else{
			if (ISCYLINDER < 0.5){ // isCylinder
				//simple implementation, 4 samples per point
				//for (int i = 0; i<mod(timeInfo.x/4,30); i++){
				for (int i = 0; i<8; i++){
					// draw vector from centerpoint to new height point and normalize it to range length
					vec3 tonew = circleWorldPos.xyz - modelWorldPos.xyz;
					tonew.y *= HEIGHTMOD;
					tonew = normalize(tonew) * RANGE;
					circleWorldPos.xz = modelWorldPos.xz + tonew.xz;
					circleWorldPos.y = heightAtWorldPos(circleWorldPos.xz);
				}
			}
		}
	
		circleWorldPos.y += 6; // lift it from the ground
	
		// -- MAP OUT OF BOUNDS
		vec2 mymin = min(circleWorldPos.xz,mapSize.xy - circleWorldPos.xz);
		float inboundsness = min(mymin.x, mymin.y);
		OUTOFBOUNDSALPHA = 1.0 - clamp(inboundsness*(-0.02),0.0,1.0);
	
	
		//--- DISTANCE FADE ---
		vec4 camPos = cameraViewInv[3];
		float distToCam = length(modelWorldPos.xyz - camPos.xyz); //dist from cam
		// FadeStart, FadeEnd, StartAlpha, EndAlpha
		float fadeDist = visibility.y - visibility.x;
		FADEALPHA  = clamp((visibility.y - distToCam)/(fadeDist),0,1);//,visibility.z,visibility.w);
	
		//--- Optimize by anything faded out getting transformed back to origin with 0 range?
		//seems pretty ok!
		if (FADEALPHA < 0.001) {
			circleWorldPos.xyz = modelWorldPos.xyz;
		}
	
		if (cannonmode > 0.5){
		// cannons should fade distance based on their range
			float cvmin = max(visibility.x, 2* RANGE);
			float cvmax = max(visibility.y, 4* RANGE);
			//FADEALPHA = clamp((cvmin - distToCam)/(cvmax - cvmin + 1.0),visibility.z,visibility.w);
		}
	
		blendedcolor = color1;
	
		// -- DARKEN OUT OF LOS
		vec4 losTexSample = texture(losTex, vec2(circleWorldPos.x / mapSize.z, circleWorldPos.z / mapSize.w)); // lostex is PO2
		float inlos = dot(losTexSample.rgb,vec3(0.33));
		inlos = clamp(inlos*5 -1.4	, 0.5,1.0); // fuck if i know why, but change this if LOSCOLORS are changed!
		//blendedcolor.rgb *= inlos;
	
		// --- YES FOG
		float fogDist = length((cameraView * vec4(circleWorldPos.xyz,1.0)).xyz);
		float fogFactor = clamp((fogParams.y - fogDist) * fogParams.w, 0, 1);
		blendedcolor.rgb = mix(fogColor.rgb, vec3(blendedcolor), fogFactor);
	
	
		// -- IN-SHADER MOUSE-POS BASED HIGHLIGHTING
		//float disttomousefromunit = 1.0 - smoothstep(48, 64, length(modelWorldPos.xz - mouseWorldPos.xz));
		// this will be positive if in mouse, negative else
		//float highightme = clamp( (disttomousefromunit ) + 0.0, 0.0, 1.0);
		MOUSEALPHA = 0.1;
	
		// ------------ dump the stuff for FS --------------------
		//worldPos = circleWorldPos;
		//worldPos.a = RANGE;
		alphaControl.x = circlepointposition.z; // save circle progress here
		gl_Position = cameraViewProj * vec4(circleWorldPos.xyz, 1.0);
	
	
		//lets blend the alpha here, and save work in FS:
		float outalpha = OUTOFBOUNDSALPHA * (MOUSEALPHA + FADEALPHA *  lineAlphaUniform);
		blendedcolor.a *= outalpha ;
		//blendedcolor.rgb = vec3(fract(distToCam/100));
	}
	]]
	
	local fsSrc =  [[
	#version 330
	
	#extension GL_ARB_uniform_buffer_object : require
	#extension GL_ARB_shading_language_420pack: require
	
	//_DEFINES__
	
	#line 20000
	
	uniform float drawAlpha = 0.1; // 0.0 is default, 1.0 is stipple circle, 2.0 is shade disc
	uniform vec4 drawColor = vec4(0.0, 0.0, 0.0, 0.0);
	
	uniform sampler2D discTex;
	
	//_ENGINEUNIFORMBUFFERDEFS__
	
	in DataVS {
		flat vec4 blendedcolor;
		vec4 circleprogress;
	};
	
	out vec4 fragColor;
	
	void main() {
		//fragColor = vec4(drawColor.x,drawColor.y,drawColor.z, drawColor.w * drawAlpha);
		fragColor = vec4(blendedcolor.x, blendedcolor.y, blendedcolor.z, blendedcolor.w * drawAlpha);
	}
	]]



local cacheTable = {}
for i=1,20 do cacheTable[i] = 0 end

-- code for selected units start here

local selectedUnits = {}
local selUnits = {}
local updateSelection = false
local selections = {}  -- contains params for added vaos
local mouseUnit
local mouseovers = {}	-- mirroring selections, but for mouseovers

local unitsOnOff = {}	-- unit weapon toggle states, tracked from CommandNotify
local myTeam = Spring.GetMyTeamID()

local function GetUnitDef(unitID)
    local unitDefID = spGetUnitDefID(unitID)
    if unitDefID then
        local unitDef = UnitDefs[unitDefID]
        return unitDef
    end
    return nil
end

-- mirrors functionality of UnitDetected
local function AddSelectedUnit(unitID, mouseover)
	if not show_selected_weapon_ranges then return end
	local collections = selections
	if mouseover then
		collections = mouseovers
	end

	local unitDef = GetUnitDef(unitID)
	if not unitDef then return end
	if collections[unitID] ~= nil then return end

	--local alliedUnit = (spGetUnitAllyTeam(unitID) == myAllyTeam)
	--local x, y, z, mpx, mpy, mpz, apx, apy, apz = spGetUnitPosition(unitID, true, true)
	local weapons = unitDef.weapons
	if (not weapons or #weapons == 0) and not unitDef.isBuilder then return end -- no weapons and not builder, nothing to add
	-- we want to add to unitDefRings here if it doesn't exist
	if not unitDefRings[unitDef.id] then
		-- read weapons and add them to weapons table, then add to entry   
		local entry = { weapons = {} }
		for weaponNum = 1, #weapons do
			local weaponDefID = weapons[weaponNum].weaponDef
			local weaponDef = WeaponDefs[weaponDefID]
			local range = weaponDef.range
			if range > 0 then 
				if weaponDef.type == "Cannon" then
					entry.weapons[weaponNum] = 4	-- weaponTypeMap[4] is "cannon"
				else 
					entry.weapons[weaponNum] = 1 	-- weaponTypeMap[1] is "ground"
				end
			end
		end
		-- builder can have no weapon but still need to be added
		if unitDef.isBuilder then
			local wt = entry.weapons
			wt[#wt+1] = 2	-- 5 is nano
		end

		unitDefRings[unitDef.id] = entry	-- we insert the entry so we can reuse existing code
		--Spring.Echo("unitDefRings entry added: "..tableToString(entry))
		-- we need to initialize the other params
		initializeUnitDefRing(unitDef.id)
	end

	local alliedUnit = (spGetUnitAllyTeam(unitID) == myAllyTeam)
	local x, y, z, mpx, mpy, mpz, apx, apy, apz = spGetUnitPosition(unitID, true, true)

	--for weaponNum = 1, #weapons do
	local addedrings = 0
	for j, weaponType in pairs(unitDefRings[unitDef.id]['weapons']) do
		local drawIt = true
		-- we need to check if the unit has toggled weapon state, and only add the one active
		local weaponOnOff = unitsOnOff[unitID] or 0
		local weaponState = weaponOnOff + 1 -- OnOff starts from 0, we want to get index starting from 1
		if weaponState ~= j then drawIt = false end
		local unitIsOnOff = spFindUnitCmdDesc(unitID, 85) ~= nil	-- if this unit can toggle weapons

		local allystring = alliedUnit and "ally" or "enemy"
		local ringParams = unitDefRings[unitDef.id]['rings'][j]
		if not unitIsOnOff or (unitIsOnOff and drawIt) or ringParams[1] > 0 then
			--local weaponType = unitDefRings[unitDefID]['weapons'][weaponNum]
			cacheTable[1] = mpx
			cacheTable[2] = mpy
			cacheTable[3] = mpz
			local vaokey = allystring ..weaponTypeToString[weaponType]

			for i = 1,13 do
				cacheTable[i+3] = ringParams[i]
			end
			if false then
				local s = ' '
				for i = 1,16 do
					s = s .. "; " ..tostring(cacheTable[i])
				end
				if true then 
					Spring.Echo("Adding rings for", unitID, x,z)
					Spring.Echo("added",vaokey,s)
				end
			end
			local instanceID = 10000000 * (mouseover and 1 or 0) + 1000000 * weaponType + unitID + 100000 * j -- weapon index needs to be included here for uniqueness
			pushElementInstance(defenseRangeVAOs[vaokey], cacheTable, instanceID, true,  false, unitID)
			addedrings = addedrings + 1
			if collections[unitID] == nil then
				--lazy creation
				collections[unitID] = { posx = mpx, posy = mpy, posz = mpz, vaokeys = {}, allied = alliedUnit, unitDefID = unitDef.id}
			end
			collections[unitID].vaokeys[instanceID] = vaokey
		end
	end

	if addedrings == 0 then
		return
	end
end

local function RemoveSelectedUnit(unitID, mouseover)
	if not show_selected_weapon_ranges then return end
	local collections = selections
	if mouseover then collections = mouseovers end

	-- we have to check to make sure this is a selection unit and not a defense unit
	if collections[unitID] then
		local collection = collections[unitID]
		if not collection then return end
		for instanceKey,vaoKey in pairs(collection.vaokeys) do
			--Spring.Echo(vaoKey,instanceKey)
			popElementInstance(defenseRangeVAOs[vaoKey],instanceKey)
		end
		collections[unitID] = nil
		--Spring.Echo("removed rings from unitID: "..tostring(unitID))
	end
end

function widget:SelectionChanged(sel)
	updateSelection = true
	--Spring.Echo("selection changed!")
end


local function makeShaders()
	local engineUniformBufferDefs = LuaShader.GetEngineUniformBufferDefs()
	vsSrc = vsSrc:gsub("//__ENGINEUNIFORMBUFFERDEFS__", engineUniformBufferDefs)
	fsSrc = fsSrc:gsub("//__ENGINEUNIFORMBUFFERDEFS__", engineUniformBufferDefs)
	attackRangeShader =  LuaShader(
	{
		vertex = vsSrc:gsub("//__DEFINES__", "#define MYGRAVITY "..tostring(Game.gravity+0.1)),
		fragment = fsSrc,
		--geometry = gsSrc, no geom shader for now
		uniformInt = {
			heightmapTex = 0,
			losTex = 1,
		},
		uniformFloat = {
			lineAlphaUniform = 1,
			cannonmode = 0,
		},
	},
	"attackRangeShader GL4"
	)
	shaderCompiled = attackRangeShader:Initialize()
	if not shaderCompiled then
		goodbye("Failed to compile attackRangeShader GL4 ")
		return false
	end
	return true
end

local function initGL4()
	smallCircleVBO = makeCircleVBO(smallCircleSegments)
	largeCircleVBO = makeCircleVBO(largeCircleSegments)
	for i,defRangeClass in ipairs(defenseRangeClasses) do
		defenseRangeVAOs[defRangeClass] = makeInstanceVBOTable(circleInstanceVBOLayout,16,defRangeClass, 5) -- 5 is unitIDattribID (instData)
		if defRangeClass:find("cannon", nil, true) or defRangeClass:find("nuke", nil, true) then
			defenseRangeVAOs[defRangeClass].vertexVBO = largeCircleVBO
			defenseRangeVAOs[defRangeClass].numVertices = largeCircleSegments
		else
			defenseRangeVAOs[defRangeClass].vertexVBO = smallCircleVBO
			defenseRangeVAOs[defRangeClass].numVertices = smallCircleSegments
		end
		local newVAO = makeVAOandAttach(defenseRangeVAOs[defRangeClass].vertexVBO,defenseRangeVAOs[defRangeClass].instanceVBO)
		defenseRangeVAOs[defRangeClass].VAO = newVAO
	end
	return makeShaders()
end

function toggleCursorRange(_, _, args)
	cursor_unit_range = not cursor_unit_range
	Spring.Echo("Cursor unit range set to: " ..(cursor_unit_range and "ON" or "OFF"))
end

function widget:Initialize()
	initUnitList()

	if initGL4() == false then
		return
	end

	widgetHandler.actionHandler:AddAction(self, "cursor_range_toggle", toggleCursorRange, nil, "p")

--[[ 	WG['defrange'] = {}
	for _,ae in ipairs({'ally','enemy'}) do
		local Ae = string.upper(string.sub(ae, 1, 1)) .. string.sub(ae, 2)
		for _,wt in ipairs({'ground','air','nuke'}) do
			local Wt = string.upper(string.sub(wt, 1, 1)) .. string.sub(wt, 2)
			WG['defrange']['get'..Ae..Wt] = function() return buttonConfig[ae][wt] end
			WG['defrange']['set'..Ae..Wt] = function(value)
				buttonConfig[ae][wt] = value
				Spring.Echo(string.format("Defense Range GL4 Setting %s%s to %s",Ae,Wt, value and 'on' or 'off'))
				if WG['unittrackerapi'] and WG['unittrackerapi'].visibleUnits then
					widget:VisibleUnitsChanged(WG['unittrackerapi'].visibleUnits, nil)
				end
			end
		end
	end ]]
	myAllyTeam = Spring.GetMyAllyTeamID()
	local allyteamlist = Spring.GetAllyTeamList( )
	--Spring.Echo("# of allyteams = ", #allyteamlist)
	numallyteams = #allyteamlist

	selectedUnits = Spring.GetSelectedUnits()
	updateSelection = true
end

local gameFrame = 0

function widget:GameFrame(gf)
	gameFrame = gf
end

function widget:Update(dt)

	if updateSelection and gameFrame % 3 == 2 then
		selectedUnits = Spring.GetSelectedUnits()
		updateSelection = false
		if innerRingDim ~= 0 then
			local numUnitsSelected = #selectedUnits
			if numUnitsSelected == 0 then numUnitsSelected = 1 end
			if numUnitsSelected > 25 then numUnitsSelected = 25 end
			innerRingDim = group_selection_fade_scale * 0.1 * numUnitsSelected
		end

		local newSelUnits = {}
		-- add to selection
		for i, unitID in ipairs(selectedUnits) do
			newSelUnits[unitID] = true
			if not selUnits[unitID] then
				AddSelectedUnit(unitID)
			end
		end
		-- remove from selection
		for unitID, _ in pairs(selUnits) do
			if not newSelUnits[unitID] then
				RemoveSelectedUnit(unitID)
			end
		end
		selUnits = newSelUnits
	end

	if cursor_unit_range and gameFrame % 3 == 1 then
        local mx, my = spGetMouseState()
        local desc, args = spTraceScreenRay(mx, my, false)
        local mUnitID
        if desc and desc == "unit" then
            mUnitID = args
        else
            mUnitID = nil
			RemoveSelectedUnit(mouseUnit, true)
            mouseUnit = nil
        end
        if mUnitID and (mUnitID ~= mouseUnit) then
			RemoveSelectedUnit(mouseUnit, true)
			if not selections[mUnitID] then
            	AddSelectedUnit(mUnitID, true)
			end
			mouseUnit = mUnitID
        end
    end

end

function widget:UnitCommand(unitID, unitDefID, unitTeam, cmdID, cmdParams, cmdOpts, cmdTag)
	if unitTeam == myTeam and cmdID == 85 then -- my unit, "OnOff" command
		unitsOnOff[unitID] = cmdParams[1]
		RemoveSelectedUnit(unitID)	-- need to refresh this unit's ring
		AddSelectedUnit(unitID)
	end
end

function widget:RecvLuaMsg(msg, playerID)
	if msg:sub(1,18) == 'LobbyOverlayActive' then
		chobbyInterface = (msg:sub(1,19) == 'LobbyOverlayActive1')
	end
end
local drawcounts = {}

local cameraHeightFactor = 0

local function GetCameraHeightFactor() -- returns a smoothstepped value between 0 and 1 for height based rescaling of line width.
	--local camX, camY, camZ = Spring.GetCameraPosition()
	--local camheight = camY - math.max(Spring.GetGroundHeight(camX, camZ), 0)
	-- Smoothstep to half line width as camera goes over 2k height to 4k height
	--genType t;  /* Or genDType t; */
    --t = clamp((x - edge0) / (edge1 - edge0), 0.0, 1.0);
    --return t * t * (3.0 - 2.0 * t);

	--camheight = math.max(0.0, math.min(1.0, (camheight - colorConfig.distanceScaleStart) / (colorConfig.distanceScaleEnd - colorConfig.distanceScaleStart)))
	--return camheight * camheight * (3 - 2 *camheight)
	return 1
end

local groundnukeair = {"ground","air","nuke","nano"}
local function DRAWRINGS(primitiveType, linethickness)
	local stencilMask
	attackRangeShader:SetUniform("cannonmode",0)
	for i,allyState in ipairs(allyenemypairs) do
		for j, wt in ipairs(groundnukeair) do
			local defRangeClass = allyState..wt
			local iT = defenseRangeVAOs[defRangeClass]
			stencilMask = 2 ^ ( 4 * (i-1) + (j-1)) -- from 1 to 128
			drawcounts[stencilMask] = iT.usedElements
			if iT.usedElements > 0 and buttonConfig[allyState][wt] then
				if linethickness then
					glLineWidth(colorConfig[wt][linethickness] * cameraHeightFactor)
				end
				glStencilMask(stencilMask)  -- only allow these bits to get written
				glStencilFunc(GL_NOTEQUAL, stencilMask, stencilMask) -- what to do with the stencil
				iT.VAO:DrawArrays(primitiveType,iT.numVertices,0,iT.usedElements,0) -- +1!!!
			end
		end
	end

	attackRangeShader:SetUniform("cannonmode",1)
	for i,allyState in ipairs(allyenemypairs) do
		local defRangeClass = allyState.."cannon"
		local iT = defenseRangeVAOs[defRangeClass]
		stencilMask = 2 ^ ( 4 * (i-1) + 3)
		drawcounts[stencilMask] = iT.usedElements
		if iT.usedElements > 0 and buttonConfig[allyState]["ground"] then
			if linethickness then
				glLineWidth(colorConfig['cannon'][linethickness] * cameraHeightFactor)
			end
			glStencilMask(stencilMask)
			glStencilFunc(GL.NOTEQUAL, stencilMask, stencilMask)
			iT.VAO:DrawArrays(primitiveType,iT.numVertices,0,iT.usedElements,0) -- +1!!!
		end
	end
end

function widget:DrawWorldPreUnit()
	--if fullview and not enabledAsSpec then
	--	return
	--end
	if chobbyInterface then return end
	if not Spring.IsGUIHidden() and (not WG['topbar'] or not WG['topbar'].showingQuit()) then
		cameraHeightFactor = GetCameraHeightFactor() * 0.5 + 0.5
		glTexture(0, "$heightmap")
		glTexture(1, "$info")
		--glTexture(2, texture)

		-- Stencil Setup
		-- 	-- https://learnopengl.com/Advanced-OpenGL/Stencil-testing
		if colorConfig.drawStencil then
			glClear(GL_STENCIL_BUFFER_BIT) -- clear prev stencil
			glDepthTest(false) -- always draw
			--glColorMask(false, false, false, false) -- disable color drawing
			glStencilTest(true) -- enable stencil test
			glStencilMask(255) -- all 8 bits
			glStencilOp(GL_KEEP, GL_KEEP, GL_REPLACE) -- Set The Stencil Buffer To 1 Where Draw Any Polygon

			attackRangeShader:Activate()
			attackRangeShader:SetUniform("drawAlpha", fill_alpha)
			DRAWRINGS(GL_TRIANGLE_FAN) -- FILL THE CIRCLES
			--glLineWidth(math.max(0.1,4 + math.sin(gameFrame * 0.04) * 10))
			glColorMask(true, true, true, true)	-- re-enable color drawing
			glStencilMask(0)

			attackRangeShader:SetUniform("lineAlphaUniform",colorConfig.externalalpha)
			glDepthTest(GL_LEQUAL) -- test for depth on these outside cases
			
			attackRangeShader:SetUniform("drawAlpha", 1.0)
			DRAWRINGS(GL_LINE_LOOP, 'externallinethickness') -- DRAW THE OUTER RINGS
			glStencilTest(false)

		end

		if colorConfig.drawInnerRings then
			local drawDim = 1
			if innerRingDim ~= 0 then
				drawDim = colorConfig.internalalpha / innerRingDim
				if drawDim > 1.0 then drawDim = 1.0 end
			end
			attackRangeShader:SetUniform("lineAlphaUniform", math.min(colorConfig.internalalpha, drawDim))
			attackRangeShader:SetUniform("drawAlpha", drawDim)
			DRAWRINGS(GL_LINE_LOOP, 'internallinethickness') -- DRAW THE INNER RINGS
		end

		attackRangeShader:Deactivate()

		glTexture(0, false)
		glTexture(1, false)
		glDepthTest(false)
		if false and Spring.GetDrawFrame() % 60 == 0 then
			local s = 'drawcounts: '
			for k,v in pairs(drawcounts) do s = s .. " " .. tostring(k) .. ":" .. tostring(v) end
			Spring.Echo(s)
		end
	end
end

--- SHIT THAT NEEDS TO BE IN CONFIG:

-- ALLY/ENEMY
-- AIR/NUKE/GROUND
-- OPACITY
-- ENABLE IN SPEC MODE
-- LINEWIDTH
-- internalrings
-- nostencil mode




--SAVE / LOAD CONFIG FILE
function widget:GetConfigData()
	local data = {}
	data["enabled"] = buttonConfig
	return data
end

function widget:SetConfigData(data)
	if data ~= nil then
		if data["enabled"] ~= nil then
			buttonConfig = data["enabled"]
			--printDebug("enabled config found...")
		end
	end
end