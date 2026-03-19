--!strict
local wepBase = require(game.ServerStorage.ROWA.Weps.WepBase)
local dmgConfig = require(script.Parent.Parent.dmgConfig)

return function(this:wepBase.myself): wepBase.atkResult
	if this:canTriggerCD("heavy") == false then return end
	local humObj   = this._humObj
	local hurtbox  = humObj.HurtBox
	
	local anim = this:PlayAnim(script.Heavy,0,1,1)
	anim.Priority = Enum.AnimationPriority.Action2

	humObj.limbTrails:indicatorLeft()
	humObj.walkSpeed:SetMod("stopMoving", -100)

	local atkrate = this.atkRate.Value
	if this:feintWait(0.5) then humObj.walkSpeed:RemoveMod("stopMoving") anim:Stop() return end
	this:triggerCD("heavy")
	humObj.walkSpeed:RemoveMod("stopMoving")
	
	local hitboxOffset = CFrame.new(0,0,-3)
	local hitboxSize   = Vector3.new(5,5,5)
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
	game.ReplicatedStorage.RemoteEvents.VFX:FireAllClients("windShock", hurtbox)
	if isHit and isHit:isHit() then
		humObj.walkSpeed:SetMod("stopMoving", -100)
		local victimHumObj = isHit.enemyEntity
		local victimHum = victimHumObj.Hum
		local victimAnim = victimHumObj:LoadAnimation(script.victim)
		victimHumObj:TrueStun(1)
		local grabClass = victimHumObj.grab
		local grab = grabClass:grab(humObj)
		--grab.C1 = CFrame.Angles(0, math.rad(180),0) * CFrame.new(0,0.5,3)
		
		victimAnim:Play()
		if this:feintWait(0.7) then grabClass:release() victimHumObj.stun.value = 0 victimHumObj.trueStun.Value = 0 victimAnim:Stop() humObj.walkSpeed:RemoveMod("stopMoving") return end
		
		local attack = this:makeAtk(
			dmgConfig.smash,
			victimHum,
			hurtbox.CFrame.LookVector
		)
		
		game.ReplicatedStorage.RemoteEvents.VFX:FireAllClients("smallGroundSmash", hurtbox)
		grabClass:release()
		
		task.spawn(function()
			this:executeAttack(attack)
			if attack:isHit() then
				attack.enemyEntity.ragdoll:ragdoll(60, true, attack.atkDir*10)
			end
		end)
		
		humObj.walkSpeed:RemoveMod("stopMoving")
		this:endLag(0.15)
	elseif anim then
		anim:AdjustWeight(1)
		anim:Stop(0.7)
		this:endLag(0.4)
	end
	
	return isHit ~= nil
end