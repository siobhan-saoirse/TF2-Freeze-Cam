-- port of tf2's deathcam, but modified
hook.Add("CalcView", "DeathCamView", function(ply, pos, angles, fov)
    if not IsValid(ply) then return end
    if ply:Team() == TEAM_SPECTATOR then return end
    if ply:GetObserverMode() ~= OBS_MODE_DEATHCAM then return end

	local ragdoll = ply:GetNWEntity("RagdollEntity")
	
	if (!IsValid(ragdoll)) then
		ragdoll = ply:GetRagdollEntity()
	end
    -- Setup
    local killer = ply:GetObserverTarget()
    local eyeOrigin = pos
    local eyeAngles = angles
    local origin = ply:GetPos() + Vector(0, 0, 64)
	if (IsValid(ragdoll)) then
		origin = ragdoll:GetPos() + Vector(0, 0, 15)
	end
    local forward = Angle(eyeAngles.p, eyeAngles.y, eyeAngles.r)
    local interpolation = math.Clamp((CurTime() - (ply:GetNWFloat("DeathTime",0) or 0)) / 1.0, 0, 1)
    interpolation = math.ease.InOutCubic(interpolation)

    -- Setup chase distances
    local chaseMin = 40
    local chaseMax = 96
    local chaseDistance = ply:GetNWInt("ChaseDistance",40) or chaseMin

    if IsValid(killer) and killer.GetModelScale then
        local scale = killer:GetModelScale()
        local scaleSqr = scale * scale
        chaseMin = chaseMin * scaleSqr
        chaseMax = chaseMax * scaleSqr
    end

    chaseDistance = math.Clamp(chaseDistance + FrameTime() * 48, chaseMin, chaseMax)
    ply:SetNWFloat("ChaseDistance",chaseDistance)

    -- If player has a decapitated head entity (optional feature)
    if IsValid(ply.HeadGib) then
        local phys = ply.HeadGib:GetPhysicsObject()
        if IsValid(phys) then
            local massCenter = phys:GetMassCenter()
            local worldCenter = ply.HeadGib:LocalToWorld(massCenter)
            ply.HeadGib:AddEffects(EF_NODRAW)

            eyeOrigin = worldCenter + Vector(0, 0, 6)

            local headAng = ply.HeadGib:GetAngles()
            local bodyVec
            if IsValid(ply.Ragdoll) then
                bodyVec = ply.Ragdoll:GetPos() - eyeOrigin
            else
                bodyVec = ply.HeadGib:GetPos() - eyeOrigin
            end

            local bodyAng = bodyVec:Angle()
            eyeAngles = LerpAngle(interpolation, headAng, bodyAng)

            return {
                origin = eyeOrigin,
                angles = eyeAngles,
                fov = ply:GetFOV()
            }
        end
    end

    -- Interpolate toward killer
    if IsValid(killer) and killer ~= ply then
        local toKiller = killer:EyePos() - origin
        local killerAng = toKiller:Angle()
        eyeAngles = LerpAngle(interpolation, forward, killerAng)
    end

    -- Calculate camera offset
    local viewForward = eyeAngles:Forward()
    viewForward:Normalize()
    eyeOrigin = origin - viewForward * chaseDistance

    -- Ray trace against world
    local tr = util.TraceHull({
        start = origin,
        endpos = eyeOrigin,
        mins = Vector(-4, -4, -4),
        maxs = Vector(4, 4, 4),
        mask = MASK_SOLID,
        filter = ply
    })

    if tr.Fraction < 1.0 then
        eyeOrigin = tr.HitPos
        ply.ChaseDistance = (origin - eyeOrigin):Length()
    end

    return {
        origin = eyeOrigin,
        angles = eyeAngles,
        fov = ply:GetFOV()
    }
end)
local tbl = {}
function getAlivePlayers(ply)
    tbl = {}
    for k,v in ipairs(ents.GetAll()) do
        if (v:Health() > 1 and (v:IsPlayer() or v:IsNPC() or v:IsNextBot()) and v:EntIndex() != ply:EntIndex()) then
            table.insert(tbl,v)
        end
    end
    return tbl
end
-- rlly easy copy and paste from my branch of TF2 gamemode with some edits
hook.Add( "OnNPCKilled", "TF2_DeathTime_NPC", function( npc, attacker, inflictor )
    timer.Simple(0, function()
        for k,v in ipairs(player.GetAll()) do
            if (!v.index) then v.index = 1 end
            if (v:GetObserverTarget() == npc and v:GetObserverMode() != OBS_MODE_DEATHCAM and v:GetObserverMode() != OBS_MODE_FREEZECAM) then
                timer.Stop("ChaseAnotherEntity"..v:EntIndex())
                timer.Create("ChaseAnotherEntity"..v:EntIndex(), 1.5, 1, function()
                    if (v:Alive()) then return end
                    if (v.index > table.Count(getAlivePlayers(v))) then
                        v.index = 0
                    end
                    local plr = getAlivePlayers(v)[v.index]
                    v.index = v.index + 1
                    v:SpectateEntity(plr)
                    v:SetObserverMode(OBS_MODE_CHASE)
                end)
            end
        end
    end)
end)
hook.Add("DoPlayerDeath","TF2_DeathTime",function(ply, attacker, dmginfo)
    ply:SetNWFloat("DeathTime",CurTime())
    timer.Simple(0, function()
        for k,v in ipairs(player.GetAll()) do
            if (!v.index) then v.index = 1 end
            if (v:GetObserverTarget() == ply and v:GetObserverMode() != OBS_MODE_DEATHCAM and v:GetObserverMode() != OBS_MODE_FREEZECAM) then
                timer.Stop("ChaseAnotherEntity"..v:EntIndex())
                timer.Create("ChaseAnotherEntity"..v:EntIndex(), 1.5, 1, function()
                    if (v:Alive()) then return end
                    if (v.index > table.Count(getAlivePlayers(v))) then
                        v.index = 1
                    end
                    local plr = getAlivePlayers(v)[v.index]
                    v.index = v.index + 1
                    v:SpectateEntity(plr)
                    v:SetObserverMode(OBS_MODE_CHASE)
                end)
            end
        end
        if (!ply:Alive()) then
            ply:Spectate(OBS_MODE_DEATHCAM)
            if (IsValid(attacker) and (attacker:IsPlayer() or attacker:IsNPC() or attacker:IsNextBot()) and attacker:EntIndex() ~= ply:EntIndex()) then
                ply:SpectateEntity(attacker)
                timer.Simple(1.0, function()
                    if (!IsValid(attacker)) then return end
                    if (!ply:Alive()) then
                        ply:SetObserverMode(OBS_MODE_FREEZECAM)
                        ply:SendLua([[surface.PlaySound("ui/freeze_cam.wav")]])
                        timer.Simple(4.0, function()
                            if (ply:Alive()) then return end
                            if (ply.index > table.Count(getAlivePlayers(ply))) then
                                ply.index = 1
                            end
                            local plr = getAlivePlayers(ply)[ply.index]
                            ply.index = ply.index + 1
                            ply:SpectateEntity(plr)
                            ply:SetObserverMode(OBS_MODE_CHASE)
                        end)
                    end
                end)
            else
                ply:SpectateEntity(nil)
                timer.Simple(5.5, function()
                    if (ply:Alive()) then return end
                    if (ply.index > table.Count(getAlivePlayers(ply))) then
                        ply.index = 1
                    end
                    local plr = getAlivePlayers(ply)[ply.index]
                    ply.index = ply.index + 1
                    ply:SpectateEntity(plr)
                    ply:SetObserverMode(OBS_MODE_CHASE)
                end)
            end
        end
    end)
end)