--!strict
local wepBase = require(game.ServerStorage.ROWA.Weps.WepBase)
local dmgConfig = require(script.Parent.Parent.dmgConfig)

local function cannonFx(this)
	local blade = this._model:FindFirstChild("Blade", true)
	if blade == nil then return end
	local top = blade.Top
	local endt = tick() + 0.64
	blade.piston:Play()
	top.charge:Emit(1)
	task.wait(0.2)
	top.PointLight.Enabled = true
	local endtForHeatBlocs = endt - 0.2
	local onWillShoot = endt - 0.14
	local p = false
	local i = 0
	while blade and blade.Parent and this._humObj and this._humObj.attacking.Value == true and tick() < endt do
		top.bigGlow:Emit(1)
		top.flame:Emit(1)
		top.glow:Emit(1)
		top.smoke:Emit(1)

		local now = tick()
		if now < endtForHeatBlocs then
			i += 1
			if i%2 == 0 then
				top.heatBlobs:Emit(1)
			end
		end
		if now > onWillShoot and p == false then p = true
			top.willShoot:Emit(1)
		end
		task.wait()
	end
	top.PointLight.Enabled = false
end

local function cannonFxShot(this)
	local blade = this._model:FindFirstChild("Blade", true)
	if blade == nil then return end
	local top = blade.Top

	blade.Explosion.PlaybackSpeed = 1.8
	blade.Explosion:Play()
	blade.far:Play()
	blade.far.TimePosition = 0.28
	top.bigsmoke:Emit(20)
	top.shoot_smoke:Emit(10)

	top.shoot_big:Emit(1)
	top.shoot_big2:Emit(1)
	top.shoot_shoc2:Emit(1)
	top.shoot_shock:Emit(1)
	top.shoot_shine:Emit(6)

	local endt = tick() + 2.8
	while blade and blade.Parent and top and top.Parent and top:FindFirstChild("endSmoke") and tick() < endt do
		top.endSmoke:Emit(1)
		task.wait()
	end
end

-- TODO REM these...
local humanoids = require(game.ServerScriptService.Humanoids)
local destruction = require(game.ServerStorage.ROWA.Destruction_Stable.Destruction)

local function cannonFlourish(this:wepBase.myself&any)
	if this.flourishHook and this:flourishHook() == true then return end
	local humObj = this._humObj
	local hurtbox = humObj.HurtBox
	task.spawn(cannonFx, this)
	
	humObj.walkSpeed:SetMod("stopMoving", -100)
	this:PlayAnim(script.shoot, 0.2, 1, 0.9)
	this.m1cycle = 0
	
	if this:feintWait(0.65) then humObj.walkSpeed:RemoveMod("stopMoving"); return end
	
	local t = 0.5
	this:bodyForce(Vector3.new(0,0,20), t, true, t, 3)
	humObj.walkSpeed:RemoveMod("stopMoving")

	task.spawn(cannonFxShot, this)

	local plr = nil
	if humObj.plrObj and humObj.plrObj.plr then
		plr = humObj.plrObj.plr
	end		
	local hitboxOffset = CFrame.new(0,0,-16)
	local hitboxSize   = Vector3.new(7,7,25)
	local hitbox, hits = this:hitbox(hitboxOffset, hitboxSize)

	local velo = hurtbox.CFrame.LookVector*200
	local destructionOffset = CFrame.new(0,3.5,-16)
	local destructionSize   = Vector3.new(12,12,36)
	destruction.Ellipsoid(plr, hurtbox.CFrame*destructionOffset, destructionSize, 3, velo)

	local hitLanded = false
	for _,enemhum in pairs(hits) do
		local attack = this:makeAtk(
			dmgConfig.cannon,
			enemhum,
			hurtbox.CFrame.LookVector
		)
		attack.hitbox = hitbox
		attack.knockback = this:knockback(hurtbox.CFrame.LookVector*16, 0.3)
		this:executeAttack(attack)
		if attack:isHit() then
			attack.enemyEntity.ragdoll:ragdoll(0.6)
			hitLanded = true
		end
	end
	if hitLanded == false then
		task.wait(0.4)
	end
	return hitLanded
end

return function(this:wepBase.myself&any): wepBase.atkResult
	local function indicator()
		this:indicateAtk()
	end
	
	if tick() > this.lastAttacked + this.atkRate.Value then this.m1cycle = 0 end

	if this.m1cycle == 3 then 
		return cannonFlourish(this)
	end
	
	local atkCB = function(atk:any)
		local lookVec = atk.myEntity.HRootPart.CFrame.LookVector
		atk.knockback = this:knockback(lookVec*6, 0.1)
	end
	
	return this.basicAtks.m1(
		this,
		script, -- animsParent
		4, -- m1CycleCount
		dmgConfig.m1,
		0.62, -- windup
		CFrame.new(0,0,-3), -- hitboxoffset
		Vector3.new(5.5,6,5.5), -- hitbox sz
		indicator,
		-- anim stuff
		0.2, -- fadetime
		1,   -- weight
		1,   -- speed
		0.1, -- endlag
		atkCB
	)
end