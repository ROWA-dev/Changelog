--!strict
local wepBase = require(game.ServerStorage.ROWA.Weps.WepBase)
local dmgConfig = require(script.Parent.Parent.dmgConfig)


local humanoids = require(game:GetService("ServerScriptService"):WaitForChild("Entities"))
local destruction = require(game.ServerStorage.ROWA.Destruction_Stable.Destruction)
return function(this:wepBase.myself): wepBase.atkResult
	if this:canTriggerCD("heavy") == false then return end	
	local humObj   = this._humObj
	local hurtbox  = humObj.HurtBox
	
	local anim = this:PlayAnim(script.Heavy, 0.1, 1, 1)

	humObj.walkSpeed:SetMod("stopMoving", -100)
	game.ReplicatedStorage.RemoteEvents.VFX:FireAllClients("hshock", humObj.HRootPart)
	task.wait(0.5)

	local force = this:bodyForce(Vector3.new(0,75,0), 0.6, true, 0.6, 1)
	
	local Hold = this._model.Hold
	Hold.Parent.Trail1.Enabled = false
	Hold.Parent.heavy.Enabled = true
	--[[
	]]--


	--[[Hold.slideSfx:Play()
	Hold.slideSfx.TimePosition = 0.1
	Hold.wind:Play()]]--
	
	task.wait(0.65)
	humObj:FireVFXClient(
		"rootImpulse",
		Vector3.new(0,40,0)
	)
	
	Hold.Parent.heavy.Enabled = false
	Hold.Parent.Trail1.Enabled = true
	if this:feintWait(0.75) then this:triggerCD("heavy", 3) this:stopLastAnim(true) humObj.walkSpeed:RemoveMod("stopMoving") force:destroy() Hold.slideSfx:Stop() Hold.HSWING1:Stop() return end
	
	--attack
	--this:triggerCD("heavy")
	--Hold.slideSfx:Stop()
	
	--local bigSlashCF = hurtbox.CFrame*CFrame.Angles(0,0,math.rad(-20))*CFrame.Angles(0,math.rad(-90),0)
	--local bigSlashSz = Vector3.new(22, 5 ,22)
	--game.ReplicatedStorage.RemoteEvents.VFX:FireAllClients("BigSlash",bigSlashCF, hurtbox,bigSlashSz)
	
	
	local hitboxOffset = CFrame.new(0, 0, -3.5)
	local hitboxSize   = Vector3.new(9,9,9)
	local hitbox, hits = this:hitbox(hitboxOffset, hitboxSize)

	local landed = false
	for _,enemy in pairs(hits) do
		local attack = this:makeAtk(
			dmgConfig.heavy,
			enemy,
			hurtbox.CFrame.LookVector
		)

		local newkb = this:knockback(
			attack.atkDir*8,
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
		this:endLag(0.4)
	end
	this:endLag(0.1)
	humObj.walkSpeed:RemoveMod("stopMoving")
	if force and force.destroy then
		force:destroy()
	end
	return
end