--!strict
local wepBase = require(game.ServerStorage.ROWA.Weps.WepBase)
local dmgConfig = require(script.Parent.Parent.dmgConfig)

return function(this:wepBase.myself)
	if this:canTriggerCD("heavy") == false then return end
	local humObj   = this._humObj
	local hurtbox  = humObj.HurtBox
	
	local anim = this:PlayAnim(script.anim,0,1,0.9)

	humObj.limbTrails:indicatorLeft()
	humObj.walkSpeed:SetMod("stopMoving", -100)

	local atkrate = this.atkRate.Value
	if this:feintWait(0.6) then humObj.walkSpeed:RemoveMod("stopMoving") anim:Stop() return end
	this:triggerCD("heavy")
	humObj.walkSpeed:RemoveMod("stopMoving")
	
	local hitboxOffset = CFrame.new(0,0,-3.5)
	local hitboxSize   = Vector3.new(5.5,6,5.5)
	local hitbox, hits = this:hitbox(hitboxOffset, hitboxSize)

	if anim then
		anim:AdjustSpeed(0)
	end
	local isHit = nil
	for _,enemhum in pairs(hits) do
		local attack = this:makeAtk(
			dmgConfig.heavy,
			enemhum,
			hurtbox.CFrame.LookVector
		)
		attack.hitbox = hitbox

		this:executeAttack(attack)
		if attack:isHit() then
			isHit = attack
		end
	end
	if anim then
		anim:AdjustSpeed(1)
	end
	
	--game.ReplicatedStorage.RemoteEvents.VFX:FireAllClients("windShock", hurtbox)
	game.ReplicatedStorage.RemoteEvents.VFX:FireAllClients("bostaffShock", hurtbox.CFrame * CFrame.new(0,0,-6))

	local function enableMotor()
		this._model.mtr.Enabled = true
		this._model.mtr.Part1.Anchored = false
	end
	
	local function disableMotor()
		this._model.mtr.Enabled = false
		this._model.mtr.Part1.Anchored = true
	end
	
	if isHit and isHit:isHit() then
		print("RAH IS HIT!", isHit)
		humObj.walkSpeed:SetMod("stopMoving", -100)
		local victimHumObj = isHit.enemyEntity
		local victimHum = victimHumObj.Hum
		local victimAnim = victimHumObj:LoadAnimation(script.victim)
		victimHumObj:TrueStun(2)
		local grabClass = victimHumObj.grab
		local grab = grabClass:grab(humObj)
		grab.C1 = CFrame.Angles(0, math.rad(180),0) * CFrame.new(0,0,4.5)
		victimAnim:Play(0,1,1)
		if this:feintWait(0.55) then grabClass:release() victimHumObj.stun.value = 0 victimHumObj.trueStun.Value = 0 victimAnim:Stop() humObj.walkSpeed:RemoveMod("stopMoving") enableMotor() return end
		
		game.ReplicatedStorage.RemoteEvents.VFX:FireAllClients("bostaffShock", hurtbox.CFrame * CFrame.new(0,0,-6))

		local attack1 = this:makeAtk(
			dmgConfig.heavySecond,
			victimHum,
			hurtbox.CFrame.LookVector
		)
		task.spawn(this.executeAttack, this, attack1)
		
		if this:feintWait(1) then grabClass:release() victimHumObj.stun.value = 0 victimHumObj.trueStun.Value = 0 victimAnim:Stop() humObj.walkSpeed:RemoveMod("stopMoving") enableMotor() return end
		print("THROW UP! bostaff")
		
		victimHumObj:TrueStun(2)
		disableMotor()
		
		local swiftKick = this:makeAtk(
			dmgConfig.heavyPunch,
			victimHum,
			hurtbox.CFrame.LookVector
		)
		task.spawn(this.executeAttack, this, swiftKick)
		
		
		if this:feintWait(0.5) then grabClass:release() victimHumObj.stun.value = 0 victimHumObj.trueStun.Value = 0 victimAnim:Stop() humObj.walkSpeed:RemoveMod("stopMoving") enableMotor() return end
		
		local attack2 = this:makeAtk(
			dmgConfig.heavyPunch,
			victimHum,
			hurtbox.CFrame.LookVector
		)
		task.spawn(this.executeAttack, this, attack2)
		
		if this:feintWait(0.7) then grabClass:release() victimHumObj.stun.value = 0 victimHumObj.trueStun.Value = 0 victimAnim:Stop() humObj.walkSpeed:RemoveMod("stopMoving") enableMotor() return end
		
		game.ReplicatedStorage.RemoteEvents.VFX:FireAllClients("bostaffShock", hurtbox.CFrame * CFrame.new(0,0,-6) * CFrame.Angles(0,math.rad(90),0))
		
		grabClass:release()
		local attack3 = this:makeAtk(
			dmgConfig.heavyFlourish,
			victimHum,
			hurtbox.CFrame.LookVector
		)
		local newkb = this:knockback(
			-hurtbox.CFrame.RightVector*16 + Vector3.new(0,4,0),
			0.1,
			false,
			-1
		)
		attack3.knockback = newkb

		--game.ReplicatedStorage.RemoteEvents.VFX:FireAllClients("smallGroundSmash", hurtbox)
		task.spawn(function()
			this:executeAttack(attack3)
			if attack3:isHit() then
				attack3.enemyEntity.ragdoll:ragdoll(60, true, attack3.atkDir*10)
			end
		end)
		
		task.wait(0.8)
		
		print("grab back")
		enableMotor()
		
		
		humObj.walkSpeed:RemoveMod("stopMoving")
		this:endLag(0.15)
	else
		warn("MISS STOP ANIM", anim)
		if anim then
			anim:AdjustWeight(1)
			anim:Stop(0.7)
		end
		this:endLag(0.4)
	end
	
	return isHit
end