--!strict
local wepType = require(game.ServerStorage.ROWA.Weps.WepBase.types)
type wepTyp = wepType.myself

local dmgConfig = require(script.Parent.Parent.dmgConfig)
local function start(this:wepTyp): wepType.atkResult
	if this:canTriggerCD("heavy") == false then return end
	
	local humObj = this._humObj
	if humObj.chargingAnim then
		humObj.chargingAnim:Stop(0)
		humObj.chargingAnim = nil
	end
	
	local stCharge = tick()
	local canLetGo = stCharge + 0.3
	
	humObj.chargingKatana = true
	humObj.startCharge = stCharge
	this:indicateAtk()
	
	local anim:AnimationTrack = this:PlayAnim(script.HeavyStart, 0.08, 1, 1, true)
	local charging:AnimationTrack = nil
	
	humObj.walkSpeed:SetMod("stopMoving", -100)
	
	local tickMultiple = stCharge + 0.9
	local multiple = false
	while this._humObj and humObj and humObj.isActive and (humObj._wantHeavy == true or tick() < canLetGo) and not humObj:inStun() do
		if charging == nil and tick() > canLetGo then
			charging = this:PlayAnim(script.HeavyCharge, 0.1, 1, 1, true)
		end
		if multiple == false and tick() > tickMultiple then multiple = true
			warn("MULTILE!")
			this._model.Hold.shine:Play()
			this:indicateAtk()
		end
		task.wait()
	end
	
	local inStun = humObj:inStun()
	if anim then
		anim:Stop(0)
	end
	
	if humObj.chargingAnim then
		humObj.chargingAnim:Stop()
		humObj.chargingAnim = nil
	end
	
	if inStun then
		humObj.chargingKatana = nil
		humObj.startCharge = nil
		if charging then
			charging:Stop()
		end
		this:endLag(0.2)
	else
		humObj.chargingAnim = charging
	end
	
	if humObj and humObj.isActive then
		humObj.walkSpeed:RemoveMod("stopMoving")
	end
	
	return nil
end

--


local function fastSlash(this:wepTyp&any, humObj):wepType.atkResult
	if this:canTriggerCD("heavy") == false then return end
	this:triggerCD("heavy")
	
	local hurtbox  = humObj.HurtBox


	local anim = this:PlayAnim(script.HeavyHit, 0, 1, 0.8)
	local force1 = this:bodyForce(Vector3.new(0,0,-10), 0.45, true, 0.45, 1)
	this:indicateAtk()
	this._model.Hold.dashingslice:Play()
	this._model.Hold.dashingslice.TimePosition = 0.1
	--this._model.Hold.heavySlice:Play()
	if this:feintWait(0.25) then force1:destroy() this:stopLastAnim(true) humObj.walkSpeed:RemoveMod("stopMoving") this._model.Hold.dashingslice:Stop() return end
	local mover = this:bodyForce(Vector3.new(0,0,-14), 0.4, true, 0.4, 1)

	local hitboxOffset = CFrame.new(0, 0, -3)
	local hitboxSize   = Vector3.new(6,5,6)
	local hitbox, hits = this:hitbox(hitboxOffset, hitboxSize)
	local endt = tick() + 0.2

	while #hits == 0 and tick() < endt do
		task.wait()
		hitbox, hits = this:hitbox(hitboxOffset, hitboxSize)
	end
	
	if this._humObj:inStun() == true then
		force1:destroy() this:stopLastAnim(true) humObj.walkSpeed:RemoveMod("stopMoving")
		return
	end

	local hitLanded = false
	for _,enemhum in pairs(hits) do
		local attack = this:makeAtk(
			dmgConfig.heavy,
			enemhum,
			hurtbox.CFrame.LookVector
		)
		attack.hitbox = hitbox
		this:executeAttack(attack)
		if attack:isHit() then
			hitLanded = true
		elseif attack:isParried() or attack:isBlocked() then
			mover:destroy()
		end
	end

	if hitLanded == false then
		this:endLag(0.4)
	else
		this:endLag(0.2)
	end

	humObj.walkSpeed:RemoveMod("stopMoving")
	return hitLanded
end

local function multipleSlash(this:wepTyp&any, humObj):wepType.atkResult
	if this:canTriggerCD("heavy") == false then return end
	
	local hurtbox  = humObj.HurtBox
	local anim = this:PlayAnim(script.heavyMultiple, 0, 1, 0.8, true)
	this:indicateAtk()
	--this._model.Hold.dashingslice:Play()
	--this._model.Hold.dashingslice.TimePosition = 0.1
	--this._model.Hold.heavySlice:Play()
	
	humObj.walkSpeed:SetMod("stopMoving", -100)
	this._model.Hold.longwindyslash:Play()
	if this:feintWait(0.2) then this:stopLastAnim(true) humObj.walkSpeed:RemoveMod("stopMoving") this._model.Hold.longwindyslash:Stop() return end
	this:triggerCD("heavy", 8)
	game.ReplicatedStorage.RemoteEvents.VFX:FireAllClients("rHandWepFlicker", humObj.Hum, true, this._model, hurtbox)
	
	local hitLanded = false
	local cancelBarrage = false
	local blade:any = this._model:FindFirstChild("Blade", true)
	local bladeWind = blade:FindFirstChild("wind")
	for i = 1,18 do
		if this._humObj:inStun() == true then
			cancelBarrage = true
			break
		end
		task.spawn(function()
			this._humObj.attackAt = tick() + 0.05
			local hitboxOffset = CFrame.new(0, 0, -14)
			local hitboxSize   = Vector3.new(14,12,26)
			local hitbox, hits = this:hitbox(hitboxOffset, hitboxSize)
			for _,enemhum in pairs(hits) do
				local attack = this:makeAtk(
					dmgConfig.multiple,
					enemhum,
					hurtbox.CFrame.LookVector
				)
				attack.hitbox = hitbox
				this:executeAttack(attack)
				if attack:isHit() then
					hitLanded = true
				end
			end
			if bladeWind then
				bladeWind:Emit(2)
			end
		end)
		task.wait(0.05)
	end
	if cancelBarrage == true then
		this:stopLastAnim(true)
	end
	game.ReplicatedStorage.RemoteEvents.VFX:FireAllClients("rHandWepFlicker", humObj.Hum, false, this._model)
	humObj.walkSpeed:RemoveMod("stopMoving")
	task.wait(0.2)
	
	return hitLanded
end

local function stop(this:wepTyp&any):wepType.atkResult
	local humObj = this._humObj
	if humObj.chargingAnim then
		humObj.chargingAnim:Stop(0)
		humObj.chargingAnim = nil
	end
	if humObj.chargingKatana ~= true then
		return
	end
	local chargedTime = tick()-humObj.startCharge
	warn("chargeTime:", chargedTime)

	humObj.startCharge = nil
	humObj.chargingKatana = nil
	
	if chargedTime < 1 then
		warn("flash!")
		return fastSlash(this, humObj)
	else
		warn("multiple!")
		return multipleSlash(this, humObj)
	end
end

return {
	start = start,
	stop = stop
}