--!strict
local wepType = require(game.ServerStorage.ROWA.Weps.WepBase.types)
type wepTyp = wepType.myself

local dmgConfig = require(script.Parent.Parent.dmgConfig)
local hitboxClass = require(game.ServerStorage.ROWA.Class.HitboxClass)
local destruction = require(game.ServerStorage.ROWA.Destruction_Stable.Destruction)

return function(this:wepTyp): wepType.atkResult
	if this:canTriggerCD("heavy") == false then return end
	this:indicateAtk()
	local humObj = this._humObj
	local anim:AnimationTrack = this:PlayAnim(script.heavy, 0, 1, 1)
	humObj.walkSpeed:SetMod("stopMoving", -100)
	
	local vfx = script.vfx:Clone()
	vfx.Parent = this._model:FindFirstChild("Blade", true)
	
	local floorVfx = script.FloorFX:Clone()
	floorVfx.Parent = humObj.HRootPart
	
	game.ReplicatedStorage.RemoteEvents.VFX:FireAllClients("hshock", humObj.HRootPart)
	
	if this:feintWait(0.5) then vfx:Destroy() floorVfx:Destroy() humObj.walkSpeed:RemoveMod("stopMoving") anim:Stop() return end

vfx["Critical Hit"]:Play()
	local particles = {}
	local oneTime = {}
	for _,v:Instance in pairs(vfx:GetDescendants()) do
		if v:IsA("ParticleEmitter") then
			local emitC = tonumber(v:GetAttribute("EmitCount"))
			if emitC == 0 then
				table.insert(oneTime, v)
				continue
			end
			
			local rate = v.Lifetime.Max
			if v.Name == "Spec1" or v.Name == "Flame1" or v.Name == "Flame2" then
				rate = 0.1
			end
			table.insert(particles, {
				p = v,
				last = 0,
				r = rate,
				ec = emitC
			})
		end
	end
	
	local lastfloorVfx = 0
	local function cb(dt)
		local now = tick()
		if now > lastfloorVfx then lastfloorVfx = now + 0.1
			floorVfx.crescent:Emit(1)
			floorVfx.flipbook:Emit(1)
		end
		for _,v in pairs(particles) do
			if now > v.last then v.last = now + v.r
				v.p:Emit(v.ec)
			end
		end
	end
	cb(0)
	for _,v in pairs(oneTime) do
		v:Emit(1)
	end
	
	--

	local hurtbox:BasePart = humObj.HurtBox


	--// VFX POOL SETUP
	local VFX_POOL_SIZE = 25
	local vfxPool = table.create(VFX_POOL_SIZE)
	local poolIndex = 1

	for i = 1, VFX_POOL_SIZE do
		local fx = script.vfx2:Clone()
		fx.CFrame = hurtbox.CFrame
		fx.Parent = workspace.Effects
		vfxPool[i] = fx
	end

	-- Helper to fetch next pooled VFX
	local function getVFX()
		local fx = vfxPool[poolIndex]
		poolIndex += 1
		if poolIndex > VFX_POOL_SIZE then
			poolIndex = 1
		end
		return fx
	end


	--
	
	if this:feintWait(0.64, cb) then
		humObj.walkSpeed:RemoveMod("stopMoving")
		anim:Stop()
		
		game.Debris:AddItem(floorVfx, 4)
		for _,v in pairs(particles) do
			v.p.LockedToPart = false
		end
		game.Debris:AddItem(vfx, 10)
		
		for _, fx in pairs(vfxPool) do
			game.Debris:AddItem(fx, 4)
		end
		table.clear(vfxPool)
		
		return
	end
	vfx["hit sound"]:Play()
	vfx.firework:Play()
	vfx.firework.TimePosition = 0.24
	task.delay(0.1, function()
		for _,v in pairs(particles) do
			v.p.LockedToPart = false
		end
		game.Debris:AddItem(vfx, 10)
	end)
	
	this:triggerCD("heavy")

	local st = tick()
	local endt = st + 0.25
	local hitboxSpeed = 300
	
	local alreadyHit = {}
	local hitLanded = false

	local ogCF = hurtbox.CFrame
	local lastDist = 0
	local total = 0
	
	local hitSound = vfx["hit sound"]
	local fireworks = vfx.firework
	
	while tick() < endt do
		local elapsed = tick() - st
		--print(elapsed)
		local dist = elapsed*hitboxSpeed
		local delta = dist - lastDist
		lastDist = dist
		
		local hitboxSize = Vector3.new(9,20,delta)
		local hitboxCF = ogCF * CFrame.new(0, 0, -(lastDist - delta/2))
		
		local h,endp,norm = workspace:FindPartOnRayWithIgnoreList(
			Ray.new(hitboxCF.Position + Vector3.new(0,20,0), Vector3.new(0,-40,0)),
			{workspace.Effects, workspace.Entities}
		)
		
		local destSz = hitboxSize*Vector3.new(0.5,1,1)
		hitboxCF = CFrame.new(endp) * hitboxCF.Rotation + Vector3.new(0,destSz.Y/2 - 2,0)
		
		--[[local data = destruction.OBB(
			nil,
			hitboxCF * CFrame.new(0,2,-4),
			destSz,
			5,
			ogCF.LookVector*100 + Vector3.new(0,40,0)
		)
		total += #data]]
		
		local vfxCF =  CFrame.new(endp) * hitboxCF.Rotation
		local vfx2 = getVFX()--script.vfx2:Clone()
		vfx2.CFrame = vfxCF
		vfx2.Size = hitboxSize*Vector3.new(0,0,1)
		vfx2.Parent = workspace.Effects
		hitSound.Parent = vfx2
		fireworks.Parent = vfx2
		
		local len = hitboxSize.Z/2
		--vfx2.debri:Emit(len)
		vfx2.Spec1:Emit(len)
		vfx2.sparks:Emit(len)
		vfx2.wall:Emit(len)
		vfx2.rightwind:Emit(len)
		vfx2.leftwind:Emit(len)
		
		game.Debris:AddItem(vfx2, 4)
		
		--local hitbox, hits = this:hitbox(hitboxOffset, hitboxSize, nil, true)
		local hitbox = hitboxClass.new(hitboxCF, hitboxSize, nil, humObj.Hum)
		local hits = hitbox:hit()

		for _,enemhum in pairs(hits) do
			if alreadyHit[enemhum] then
				continue
			end
			alreadyHit[enemhum] = true
			
			local attack = this:makeAtk(
				dmgConfig.heavy,
				enemhum,
				hurtbox.CFrame.LookVector
			)
			local newkb = this:knockback(hurtbox.CFrame.LookVector*16, 0.3)
			attack.knockback = newkb
			attack.hitbox = hitbox

			task.spawn(function()
				this:executeAttack(attack)
				if attack:isHit() then hitLanded = true end
			end)
		end
		
		if total > 70 then
			print("RAH too much to break")
			break
		end
		task.wait()
	end
	
	for _, vfx in pairs(vfxPool) do
		game.Debris:AddItem(vfx, 4)
	end
	table.clear(vfxPool)


	table.clear(alreadyHit)
	
	if hitLanded == false then
		this:endLag(0.25)
	else
		this:endLag(0.1)
	end
	
	humObj.walkSpeed:RemoveMod("stopMoving")

	--humObj.walkSpeed:RemoveMod("stopMoving")
	return hitLanded
end