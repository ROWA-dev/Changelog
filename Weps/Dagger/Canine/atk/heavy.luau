--!strict
local wepType = require(game.ServerStorage.ROWA.Weps.WepBase.types)
type wepTyp = wepType.myself

local dmgConfig = require(script.Parent.Parent.dmgConfig)
local destruction = require(game.ServerStorage.ROWA.Destruction_Stable.Destruction)

return function(this:wepTyp&any): wepType.atkResult
	if this:canTriggerCD("heavy") == false then return end	
	local humObj   = this._humObj
	local hurtbox  = humObj.HurtBox
	
	local anim = this:PlayAnim(script.heavy, 0.08, 1, 1.2)
	game.ReplicatedStorage.RemoteEvents.VFX:FireAllClients("hshock", humObj.HRootPart)
	
	local Hold = this._model.Hold
	Hold.swish:Play()
	Hold.afterswing2:Play()
	
	if this:feintWait(0.4) then this:stopLastAnim(true) humObj.walkSpeed:RemoveMod("stopMoving") return end
	this:triggerCD("heavy")
	
	--game.ReplicatedStorage.RemoteEvents.VFX:FireAllClients("fistHvy", hurtbox)
	
	local force = this:bodyForce(Vector3.new(0,0,-10), 0.5, true, 0.5, 2)
	this:atkWait(0.04)

	local hitLanded = false


	local hitboxOffset = CFrame.new(0, 0, -3)
	local hitboxSize   = Vector3.new(6,6,6)
	
	local first = true
	for i = 1,4 do
		Hold.Swing1q:Play()
		Hold.Swing1q.TimePosition = 0.3
		if humObj and humObj.isActive and humObj:inStun() == false then
		else
			if humObj and humObj.isActive then
				humObj.walkSpeed:RemoveMod("stopMoving")
			end
			force:destroy()
			anim:Stop()
			return
		end
		local hitbox, hits = this:hitbox(hitboxOffset, hitboxSize)
		for _,enemhum in pairs(hits) do
			local dmgTbl = dmgConfig.heavy

			local attack = this:makeAtk(
				dmgTbl,
				enemhum,
				hurtbox.CFrame.LookVector
			)

			if first == true then
				this:executeAttack(attack)
			else
				task.spawn(this.executeAttack, this, attack)
			end
			first = false
			if attack:isHit() then hitLanded = true end
		end
		this:atkWait(0.12)
	end
	
	if hitLanded == false then
		this:endLag(0.4)
	--else
		--this:endLag(0.2)
	end
	
	humObj.walkSpeed:RemoveMod("stopMoving")
	return hitLanded
end