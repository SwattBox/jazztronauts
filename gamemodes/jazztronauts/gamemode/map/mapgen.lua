module( 'mapgen', package.seeall )

SpawnedShards = SpawnedShards or {}
InitialShardCount = InitialShardCount or 0

-- No two shards can ever be closer than this
local MinShardDist = 500

function GetShardCount()
	return table.Count(SpawnedShards), InitialShardCount
end

function GetShards()
    return SpawnedShards 
end

function CanSnatch(ent)

	--Accept only this kinda stuff
	if not IsValid(ent) then return false end
	if not ent:IsValid() then return false end
    if ent:IsNPC() then return true end  
    if ent:GetClass() == "npc_antlion_grub" then return true end
    if ent:GetClass() == "npc_grenade_frag" then return true end
    if ent:GetClass() == "prop_combine_ball" then return true end
    if ent:GetClass() == "jazz_static_proxy" then return true end
    if ent:GetClass() == "physics_cannister" then return true end

    if ent:IsWeapon() and ent:GetParent() and ent:GetParent():IsPlayer() then return false end
    if CLIENT and ent:IsWeapon() and ent:IsCarriedByLocalPlayer() then return false end
    //if SERVER and not IsValid(ent:GetPhysicsObject()) then return false end

    if ent:GetClass() == "hunter_flechette" then return true end
	if ent:GetClass() == "prop_physics" then return true end
	if ent:GetClass() == "prop_physics_multiplayer" then return true end
    if ent:GetClass() == "prop_physics_respawnable" then return true end
	if ent:GetClass() == "prop_dynamic" then return true end
	if ent:GetClass() == "prop_ragdoll" then return true end
    if ent:GetClass() == "prop_door_rotating" then return true end
    if string.find(ent:GetClass(), "weapon_") ~= nil then return true end
    if string.find(ent:GetClass(), "prop_vehicle") ~= nil then return true end
    //if string.find(ent:GetClass(), "jazz_bus_") ~= nil then return true end
    if string.find(ent:GetClass(), "item_") ~= nil then return true end
	//if ent:IsPlayer() and ent:Alive() then return true end -- you lost your privileges

    return false
end

if SERVER then 
    util.AddNetworkString("jazz_shardcollect")

    function CollectShard(ply, shardent)

        -- It's gotta be one of our shards ;)
        local res = table.RemoveByValue(SpawnedShards, shardent, ply)
        if not res then return nil, nil end

        progress.CollectShard(game.GetMap(), shardent.ShardID, ply)
        UpdateShardCount()

        return #SpawnedShards, InitialShardCount
    end

    function CollectProp(ply, ent)
        if !CanSnatch(ent) then return nil end

        local worth = ent.JazzWorth or 1
        return worth
    end

    function UpdateShardCount(ply)
        net.Start("jazz_shardcollect")
			net.WriteUInt(#SpawnedShards, 16)
            for _, v in pairs(SpawnedShards) do
                net.WriteEntity(v)
            end

			net.WriteUInt(InitialShardCount, 16)
        if IsValid(ply) then net.Send(ply) else net.Broadcast() end
    end

    local function checkAreaTrace(pos, ang)
        local mask = bit.bor(MASK_SOLID, CONTENTS_PLAYERCLIP, CONTENTS_SOLID, CONTENTS_GRATE)
        local traces = {}
        local tdist = 1000000
        table.insert(traces, util.TraceLine( {
            start = pos,
            endpos = pos + ang:Up() * tdist,
            mask = mask
        }))

        table.insert(traces, util.TraceLine( {
            start = pos,
            endpos = pos + ang:Up() * -tdist,
            mask = mask
        }))

        table.insert(traces, util.TraceLine( {
            start = pos,
            endpos = pos + ang:Right() * tdist,
            mask = mask
        }))

        table.insert(traces, util.TraceLine( {
            start = pos,
            endpos = pos + ang:Right() * -tdist,
            mask = mask
        }))

        table.insert(traces, util.TraceLine( {
            start = pos,
            endpos = pos + ang:Forward() * tdist,
            mask = mask
        }))

        table.insert(traces, util.TraceLine( {
            start = pos,
            endpos = pos + ang:Forward() * -tdist,
            mask = mask
        }))

        local num = 0
        for _, v in pairs(traces) do num = num + (v.HitSky and 1 or 0) end

        -- If more than 3 cardinal directions are skybox
        -- this might be some utility entity the player can't reach
        if num >= 3 then return false end

        -- Ensure there's enough space for a player to grab this from different sides
        local minBounds = 32
        local areaUp = (traces[1].Fraction + traces[2].Fraction) * tdist
        local areaFwd = (traces[3].Fraction + traces[4].Fraction) * tdist
        local areaRight = (traces[5].Fraction + traces[6].Fraction) * tdist
        if (areaUp < minBounds or areaFwd < minBounds or areaRight < minBounds) then return false end

        return true
    end

    -- Return true if the value has any matching flags
    local function maskAny(val, ...)
        local args = {...}
        for k, v in pairs(args) do
            if bit.band(val, v) == v then return true end
        end

        return false
    end

    -- Return true if the entity will spawn within a trigger teleport
    -- This usually makes it impossible to get to
    local function isWithinTrigger(ent)
        local pos = ent:GetPos()
        local tps = ents.FindByClass("trigger_teleport*")
        for _, v in pairs(tps) do
            local min = v:LocalToWorld(v:OBBMins())
            local max = v:LocalToWorld(v:OBBMaxs())

            if pos:WithinAABox(min, max) then
                return true
            end
        end

        return false
    end

    local function findValidSpawn(ent)
        local pos = ent:GetPos() + Vector(0, 0, 16)

        -- If moving the entity that small amount up puts it out of the world -- nah
        if !util.IsInWorld(pos) then return nil end

        -- If the point is inside something solid -- also nah
        if maskAny(util.PointContents(pos), CONTENTS_PLAYERCLIP, CONTENTS_SOLID, CONTENTS_GRATE) then return end

        -- Don't spawn inside a trigger_teleport either
        if isWithinTrigger(ent) then return end

        -- Check if they're near a suspicious amount of sky
        if !checkAreaTrace(pos, ent:GetAngles()) then return end

        return { pos = pos, ang = ent:GetAngles() }
    end

    local function isInSkyBox(ent)
        if ent:GetClass() == "sky_camera" then return true end

        local skycam = ents.FindByClass("sky_camera")
        if #skycam == 0 then return false end -- Map has no skybox

        return skycam[1]:TestPVS(ent)
    end

    local function spawnShard(transform, id)
        if transform == nil then return nil end

        local shard = ents.Create( "jazz_shard" )
	    shard:SetPos(transform.pos)
	    shard:SetAngles(transform.ang)
        
        shard.ShardID = id
        shard:Spawn()
        shard:Activate()

        return shard
    end
    
    -- Calculate the size of this map and how many shards it's worth
    function CalculateShardCount()
        return 8 -- #TODO
    end

    function CalculatePropValues(mapWorth)
        local props = ents.GetAll()
        local counts = {}
        local function getKey(ent) return ent:GetClass() .. "_" .. (ent:GetModel() or "") end

        for _, v in pairs(props) do
            if not CanSnatch(v) then continue end

            local k = getKey(v)
            counts[k] = counts[k] or 0
            counts[k] = counts[k] + 1
        end

        PrintTable(counts)

        for _, v in pairs(props) do
            local count = counts[getKey(v)]
            if not count then continue end

            local worth = (mapWorth / table.Count(counts)) / count
            v.JazzWorth = worth
        end
        
    end

    function GetSpawnPoint(ent)
        if !IsValid(ent) or !ent:CreatedByMap() then return nil end
        if isInSkyBox(ent) then return nil end -- god wouldn't that suck

        return findValidSpawn(ent)
    end

    -- Depending on the map, there might be certain entities that automatically
    -- Make for great shard spawn locations. These will take preference over 
    -- the default shard generation algorithm
    function GetPreferredSpawns(seed)
        local prefix = string.Split(game.GetMap(), "_")[1]
        return hook.Call("JazzGetShardSpawnOverrides", GAMEMODE, prefix, seed)
    end

    local function minDistance2(posang, postbl)
        local mindist = math.huge
        for _, v in pairs(postbl) do
            if v == posang then continue end
            mindist = math.min(mindist, (posang.pos - v.pos):LengthSqr())
        end
        
        return mindist
    end

    function GenerateShards(count, seed, shardtbl)
        for _, v in pairs(SpawnedShards) do
            if IsValid(v) then v:Remove() end
        end
        seed = seed or math.random(1, 1000)
        math.randomseed(seed)
        SpawnedShards = {}

        -- Get preferred spawns, if there are any
        local preferredSpawns = GetPreferredSpawns(seed) or {}

        -- Go through every _map_ entity, filter bad spots, and go from there
        local validSpawns = {}
        for _, v in pairs(ents.GetAll()) do
            local posang = GetSpawnPoint(v)

            -- Bad spawnpoints are nil and are not eligible to spawn at
            if posang != nil  then

                -- Ensure this position isn't already near a spawnpoint
                local mindist2 = MinShardDist^2
                if minDistance2(posang, preferredSpawns) > mindist2 and
                   minDistance2(posang, validSpawns) > mindist2
                then 
                    table.insert(validSpawns, posang)
                end
            end
        end

        -- Select count random spawns and go
        local n = 0
        local function registerShard(posang)
            count = count - 1
            if count < 0 then return false end
            n = n + 1

            print(minDistance2(posang, validSpawns))

            -- Create a new shard only if it hasn't been collected
            local shard = nil
            if not shardtbl or not tobool(shardtbl[n].collected) then 
                shard = spawnShard(posang, n)
            end

            table.insert(SpawnedShards, shard)
            return true
        end

        -- Spawn as many high priority shards as we can
        for k, v in RandomPairs(preferredSpawns) do
            if not registerShard(v) then break end
        end

        -- Fill up the rest
        for k, v in RandomPairs(validSpawns) do   
            if not registerShard(v) then break end
        end

        InitialShardCount = n
        UpdateShardCount()
        
        print("Generated " .. InitialShardCount .. " shards. Happy hunting!")
        return InitialShardCount
    end

    function LoadHubProps()
        local hubdata = progress.LoadHubPropData()
        for _, v in pairs(hubdata) do
            mapgen.SpawnHubProp(v.model, v.transform.pos, v.transform.ang, v.toy == "1")
        end
    end

    function SaveHubProps()
        local props = {}
        for _, v in pairs(ents.GetAll()) do
            if v.JazzHubSpawned then table.insert(props, v) end
        end

        progress.SaveHubPropData(props)
    end

    function SpawnHubProp(model, pos, ang, inSphere)
        local etype = inSphere and "jazz_prop_sphere" or "prop_physics"
        local ent = ents.Create(etype)
        ent:SetModel(model)
        ent:SetPos(pos)
        ent:SetAngles(ang)
        ent:Spawn()
        ent:Activate()
        ent:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
        ent.JazzHubSpawned = true

        return ent
    end

else //CLIENT
    net.Receive("jazz_shardcollect", function(len, ply)
        SpawnedShards = {}
		local left = net.ReadUInt(16)
        for i=1, left do
            table.insert(SpawnedShards, net.ReadEntity())
        end
        local total = net.ReadUInt(16)

        surface.PlaySound("ambient/alarms/warningbell1.wav")
        InitialShardCount = total

		-- Broadcast update
		--hook.Call("JazzShardCollected", GAMEMODE, left, total)
	end )


end