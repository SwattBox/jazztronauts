module( "jazzvoid", package.seeall )

local refractParams = {
	//["$basetexture"] = "_rt_FullFrameFB",
	["$basetexture"] = "concrete/concretefloor001a",
	["$normalmap"] = "sunabouzu/JazzShell_dudv",
	//["$normalmap"] = "sunabouzu/jazzSpecks_n", //concrete/concretefloor001a_normal, "effects/fisheyelense_normal", "glass/reflectiveglass002_normal"
	["$refracttint"] = "[1 1 1]",
	["$additive"] = 0,
	["$vertexcolor"] = 1,
	["$vertexalpha"] = 0,
	["$refractamount"] = 0.03,
	["$bluramount"] = 2,
	["$model"] = 1,
}
local refract = CreateMaterial("RefractBrushModel" .. FrameNumber(), "Refract", refractParams)
void_mat = refract
snatch.void_mat = void_mat

-- Performance convars
convar_drawprops = CreateClientConVar("jazz_void_drawprops", "1", true, false, "Render additional props/effects in the jazz void.")
convar_drawonce = CreateClientConVar("jazz_void_drawonce", "0", true, false, "Don't render the void for water reflections, mirrors, or additional scenes. Will introduce rendering artifacts in water/mirrors, but is much faster.")

-- Re
local surfaceMaterial = Material("sunabouzu/JazzShell") //glass/reflectiveglass002 brick/brick_model
local sizeX = ScrW() -- Size of the void rendertarget. Expose scale?
local sizeY = ScrH()
local rt = irt.New("jazz_snatch_voidbg", ScrW(), ScrH())

void_prop_count = 10
void_view_offset = Vector()


//rt:SetAlphaBits( 8 )
rt:EnableDepth( true, true )
local rtTex = rt:GetTarget()

function GetVoidTexture()
	return rt:GetTarget()
end

function GetVoidOverlay()
	return void_mat, surfaceMaterial
end

local function SharedRandomVec(seed)
	return Vector(
		util.SharedRandom("x", 0, 1, seed),
		util.SharedRandom("y", 0, 1, seed),
		util.SharedRandom("z", 0, 1, seed))
end

local function ModVec(vec, mod)
	vec.x = vec.x % mod
	vec.y = vec.y % mod
	vec.z = vec.z % mod
	return vec
end

local function MapVec(vec, func)
	vec.x = func(vec.x)
	vec.y = func(vec.y)
	vec.z = func(vec.z)
	return vec
end

-- Render the entire void scene
local propProximityFade = 200
local range = 4000.0
local hRangeVec = Vector(range/2, range/2, range/2)
local function renderFollowCats(plyPos)

	local skull = ManagedCSEnt("jazz_snatchvoid_skull", "models/krio/jazzcat1.mdl")
	skull:SetNoDraw(true)
	skull:SetModelScale(4)

	for i=1, void_prop_count do

		-- Create a "treadmill" so they don't move until they get far away, then wrap around
		local modvec = ModVec(plyPos + SharedRandomVec(i) * range, range)
		local p = plyPos - modvec + hRangeVec

		skull:SetPos(p)

		-- Face the player
		local ang = (skull:GetPos() - plyPos):Angle()
		skull:SetAngles(ang)
		skull:SetupBones()

		-- Calculate the 'distance' from the center by where they are in the offset
		local d = MapVec(math.pi * modvec / range, math.sin)

		-- Fade out if it's super close
		local dfade = MapVec( modvec - hRangeVec, math.abs) / propProximityFade

		-- Apply blending and draw
		local distFade = math.max(0, 2.0 - dfade:Length())
		local alpha = math.min(d.x, d.y, d.z) - distFade
		if alpha >= 0 then
			render.SetBlend(alpha)
			skull:DrawModel()
		end

	end
end
local function renderVoid(eyePos, eyeAng, fov)

	local oldW, oldH = ScrW(), ScrH()
	local sizeX, sizeY = rt.width, rt.height
	render.Clear( 0, 0, 0, 0, true, true )
	render.SetViewPort( 0, 0, sizeX, sizeY )

	local eyeOffset = eyePos + void_view_offset

	render.SuppressEngineLighting(true)

	-- Skybox pass
	cam.Start3D(Vector(), eyeAng, fov, 0, 0, sizeX, sizeY)
		-- Render the sky first, don't write to depth so everything draws over it
		render.OverrideDepthEnable(true, false)
			hook.Call("JazzPreDrawVoidSky", GAMEMODE)

			local tunnel = ManagedCSEnt("jazz_snatchvoid_tunnel", "models/props/jazz_dome.mdl")
			tunnel:SetNoDraw(true)
			tunnel:SetPos(Vector())
			tunnel:SetupBones()

			-- Draw the background with like a million different materials because
			-- fuck it they're all additive and look pretty
			tunnel:SetMaterial("sunabouzu/JazzLake01")
			tunnel:DrawModel()

			tunnel:SetMaterial("sunabouzu/JazzSwirl01")
			tunnel:DrawModel()

			tunnel:SetMaterial("sunabouzu/JazzSwirl02")
			tunnel:DrawModel()

			tunnel:SetMaterial("sunabouzu/JazzSwirl03")
			tunnel:DrawModel()
		
		hook.Call("JazzPostDrawVoidSky", GAMEMODE)
		render.OverrideDepthEnable(true, true)
	cam.End3D()


	-- Random props pass
	if convar_drawprops:GetBool() then
	
	-- Pre draw void with movement offset
	cam.Start3D(eyeOffset, eyeAng, fov, 0, 0, sizeX, sizeY)
		hook.Call("JazzPreDrawVoidOffset", GAMEMODE)
		
		renderFollowCats(eyeOffset)
	cam.End3D()

	-- Pre draw and draw void without movement offset
	cam.Start3D(eyePos, eyeAng, fov, 0, 0, sizeX, sizeY)
		hook.Call("JazzPreDrawVoid", GAMEMODE)

		render.SetBlend(1) -- Finished, reset blend
		render.ClearDepth()

		render.OverrideDepthEnable(false)
		hook.Call("JazzDrawVoid", GAMEMODE)

	cam.End3D()	

	-- Draw void WITH movement offset
	cam.Start3D(eyeOffset, eyeAng, fov, 0, 0, sizeX, sizeY)
		hook.Call("JazzDrawVoidOffset", GAMEMODE)
	cam.End3D()

	end
	render.OverrideDepthEnable(false)
	render.SuppressEngineLighting(false)

	render.SetViewPort( 0, 0, oldW, oldH )
end

-- Render the brush lines, keeping performant by only rendering a few at a time over the span of many frames
local offset = 0
local maxlinecount = 25
local nextgrouptime = 0
local groupFadeTime = 0.25
local function renderBrushLines()
	if #snatch.removed_brushes == 0 then return end

	if RealTime() > nextgrouptime then 
		nextgrouptime = RealTime() + groupFadeTime

		offset = (offset + maxlinecount) % #snatch.removed_brushes
	end

	local mtx = Matrix()
	local p = (nextgrouptime - RealTime()) / groupFadeTime

	for i=1, math.min(maxlinecount, #snatch.removed_brushes) do
		local curidx = ((offset + i - 1) % #snatch.removed_brushes) + 1
		local v = snatch.removed_brushes[curidx]

		mtx:SetTranslation( v.center )

		cam.PushModelMatrix( mtx )
		v:Render(HSVToColor((CurTime() * 50 + curidx * 1) % 360, 1, p), true, nil, true)
		cam.PopModelMatrix()
	end
end

function UpdateVoidTexture(origin, angles, fov)
	rt:Render(renderVoid, origin, angles, fov)
end

-- Draw the spooky jazz world to its own texture
hook.Add("RenderScene", "snatch_void_inside", function(origin, angles, fov)
	-- If draw once is enabled, draw it once here when the scene begins
	if convar_drawonce:GetBool() then
		UpdateVoidTexture(origin, angles, fov)
	end

	-- Also make sure this is always set
	if void_mat:GetTexture("$basetexture"):GetName() != rtTex:GetName() then
		print("Setting void basetexture")
		void_mat:SetTexture("$basetexture", rtTex)
	end
end )

-- Keep track of if we're currently rendering 3D sky so we don't draw extra
-- The 'sky' arg in PostDrawOpaqueRenderables returns true on maps without a skybox, 
-- so we keep track of it ourselves
local isInSky = false
hook.Add("PreDrawSkyBox", "JazzDisableSkyDraw", function()
	isInSky = true
end )
hook.Add("PostDrawSkyBox", "JazzDisableSkyDraw", function()
	isInSky = false
end)

-- Render the inside of the jazz void with the default void material
-- This void material has a rendertarget basetexture we update each frame
hook.Add( "PostDrawOpaqueRenderables", "snatch_void", function(depth, sky) 
	if isInSky then return end
	
	-- Re-render this for every new scene if not drawing once
	if not convar_drawonce:GetBool() then
		UpdateVoidTexture(EyePos(), EyeAngles(), nil)
	end

	//render.UpdateScreenEffectTexture()
	render.SetMaterial(void_mat)
	render.SuppressEngineLighting(true)

	-- Draw all map meshes
	for _, v in pairs(snatch.map_meshes) do
		v:Get():Draw()
	end

	-- Draw again with overlay
	render.SetMaterial(surfaceMaterial)
	for _, v in pairs(snatch.map_meshes) do
		v:Get():Draw()
	end

	render.SuppressEngineLighting(false)

	//renderBrushLines()

end )

hook.Add( "PreDrawEffects", "snatch_void_lines", function()
	//renderBrushLines()
end)
