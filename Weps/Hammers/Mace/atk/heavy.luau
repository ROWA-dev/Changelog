--!strict
local wepBase = require(game.ServerStorage.ROWA.Weps.WepBase)
local dmgConfig = require(script.Parent.Parent.dmgConfig)


local function cannonFx(this)
	local blade = this._model:FindFirstChild("Blade", true)
	if blade == nil then return end
	local top = blade.Top
	local endt = tick() + 0.2
	blade.piston:Play()
	top.PointLight.Enabled = true
	
	local boost = blade.boost
	boost.charge:Emit(1)
	
	while blade and blade.Parent and this._humObj and this._humObj.attacking.Value == true and tick() < endt do
		top.flame:Emit(1)
		top.glow:Emit(1)
		task.wait()
	end
	top.PointLight.Enabled = false
end

local function cannonFxShot(this)
	local blade = this._model:FindFirstChild("Blade", true)
	if blade == nil then return end
	local top = blade.Top
	local boost = blade.boost

	blade.Explosion.PlaybackSpeed = 1.4
	blade.Explosion:Play()
	--blade.far:Play()
	--blade.far.TimePosition = 0.28
	
	boost.shoot_big2:Emit(10)
	boost.shoot_smoke:Emit(10)
	
	local endt = tick() + 2.8
	while blade and blade.Parent and top and top.Parent and top:FindFirstChild("endSmoke") and tick() < endt do
		top.endSmoke:Emit(1)
		task.wait()
	end
end

local humanoids = require(game:GetService("ServerScriptService"):WaitForChild("Humanoids"))
local destruction = require(game.ServerStorage.ROWA.Destruction_Stable.Destruction)
return function(this:wepBase.myself&any): wepBase.atkResult
	if this:canTriggerCD("heavy") == false then return end	
	local humObj   = this._humObj
	local hurtbox:BasePart  = humObj.HurtBox
	task.spawn(cannonFx, this)
	local anim = this:PlayAnim(script.windup, 0, 1, 1)
	if this:feintWait(0.3) then this:stopLastAnim(true) return end
	
	this:triggerCD("heavy", 4)
	this:bodyForce(Vector3.new(0,0,-10),1, true, 0.5)
	--local rootpart:BasePart = humObj.HRootPart
	--rootpart:ApplyImpulse(Vector3.new(0,1000*workspace.Gravity,0) * rootpart.AssemblyMass)
	humObj:FireVFXClient(
		"rootImpulse",
		Vector3.new(0,40,0)
	)
	
	anim:Stop()
	local part2:AnimationTrack = this:PlayAnim(script.part2, 0.1, 1, 1, true)
	local force = this:bodyForce(Vector3.new(0,0,-20), 0.8, true, 0.8, 1)
	
	task.spawn(cannonFxShot, this)
	
	if this:feintWait(0.5) then
		if humObj:inStun() then
			humObj.HRootPart.AssemblyLinearVelocity = Vector3.zero
			force:destroy()
		end
		humObj.canAtkThreshold = 0
		this:stopLastAnim(true)
		return
	end
	
	this:triggerCD("heavy")
	part2:AdjustSpeed(0.2)
	local down, endp, norm = nil, hurtbox.Position, Vector3.new(0,1,0)
	local st = tick()
	local endt = st + 1
	local ignoreList = {hurtbox.Parent, workspace.Effects}
	while down == nil and tick() < endt do
		down, endp , norm = workspace:FindPartOnRayWithIgnoreList(
			Ray.new(hurtbox.Position, Vector3.new(0,-8,0) + hurtbox.CFrame.LookVector*3),
			ignoreList
		)
		task.wait()
	end
	part2:AdjustSpeed(1)
	
	local diff = tick()-st
	local ttw = 0.2-diff
	if ttw > 0 then
		this:atkWait(ttw)
	end
	
	if down then
		local plr = nil
		if humObj.plrObj and humObj.plrObj.plr then
			plr = humObj.plrObj.plr
		end		
		
		local velo = hurtbox.CFrame.LookVector*100-- + Vector3.new(0,100,0)
		
		local destructionSize = Vector3.new(18,18,3)
		local offst = hurtbox.CFrame.LookVector*10 --+ Vector3.new(0,2,0)
		local effectPos = endp + offst
		game.ReplicatedStorage.RemoteEvents.VFX:FireAllClients("windySmash", effectPos)
		destruction.Ellipsoid(plr, CFrame.new(effectPos, effectPos + norm), destructionSize, 3, velo)
	end
	

	local hitboxOffset = CFrame.new(0, -4, -9)
	local hitboxSize   = Vector3.new(16,14,16)
	local hitbox, hits = this:hitbox(hitboxOffset, hitboxSize)
	
	local hitLanded = false
	for _,enemhum in pairs(hits) do
		local dmgTbl = dmgConfig.heavy
		local attack = this:makeAtk(
			dmgTbl,
			enemhum,
			hurtbox.CFrame.LookVector
		)
		attack.hitbox = hitbox
		local newkb = this:knockback(Vector3.new(0,26,0), 0.5, false, 0.5)
		attack.knockback = newkb
		
		this:executeAttack(attack)
		if attack:isHit() or attack:isBlocked() then
			if hitLanded == false then
				this:bodyForce(Vector3.new(0,26,0), 0.5, false, 0.5)
				humObj.floating.Value = 1
			end
			attack.enemyEntity.floating.Value = 1
			hitLanded = true
		end
	end
	
	this.lastAttacked = tick()
	
	if hitLanded == false then
		this:endLag(0.3)
	else
		this:endLag(0.2)
	end
	
	return hitLanded
end