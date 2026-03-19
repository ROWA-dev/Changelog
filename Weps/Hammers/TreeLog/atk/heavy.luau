--!strict
local wepBase = require(game.ServerStorage.ROWA.Weps.WepBase)
local dmgConfig = require(script.Parent.Parent.dmgConfig)


local humanoids = require(game:GetService("ServerScriptService"):WaitForChild("Humanoids"))
local destruction = require(game.ServerStorage.ROWA.Destruction_Stable.Destruction)
return function(this:wepBase.myself): wepBase.atkResult
	if this:canTriggerCD("heavy") == false then return end	
	local humObj   = this._humObj
	local hurtbox  = humObj.HurtBox
	
	local anim = this:PlayAnim(script.Heavy, 0, 1, 1)
	humObj.walkSpeed:SetMod("stopMoving", -100)
	game.ReplicatedStorage.RemoteEvents.VFX:FireAllClients("hshock", humObj.HRootPart)

	if this:feintWait(0.8) then this:stopLastAnim(true) humObj.walkSpeed:RemoveMod("stopMoving") return end
	this:triggerCD("heavy")
	game.ReplicatedStorage.RemoteEvents.VFX:FireAllClients("cyldrshock",
		hurtbox.CFrame*CFrame.Angles(0,math.rad(90),math.rad(90))
	)


	local hitboxOffset = CFrame.new(0, 0, -4)
	local hitboxSize   = Vector3.new(10,10,10)
	local hitbox, hits = this:hitbox(hitboxOffset, hitboxSize)

	local landed = false
	for _,enemhum in pairs(hits) do
		local attack = this:makeAtk(
			dmgConfig.heavy,
			enemhum,
			hurtbox.CFrame.LookVector
		)

		local newkb = this:knockback(
			attack.atkDir*24,
			0.1
		)

		attack.hitbox = hitbox
		attack.knockback = newkb

		this:executeAttack(attack)
		if attack:isHit() then
			landed = true
		end
	end
	--destruction.Sphere(humObj.plrObj.Plr)
	if landed == false then
		this:endLag(0.3)
	end
	this:endLag(0.1)
	humObj.walkSpeed:RemoveMod("stopMoving")
	
	return
end