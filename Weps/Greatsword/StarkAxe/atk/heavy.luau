--!strict
local wepBase = require(game.ServerStorage.ROWA.Weps.WepBase)
local dmgConfig = require(script.Parent.Parent.dmgConfig)


local humanoids = require(game:GetService("ServerScriptService"):WaitForChild("Entities"))
local destruction = require(game.ServerStorage.ROWA.Destruction_Stable.Destruction)
return function(this:wepBase.myself): wepBase.atkResult
	if this:canTriggerCD("heavy") == false then return end	
	local humObj   = this._humObj
	local hurtbox  = humObj.HurtBox
	local char = humObj.HRootPart.Parent
	local fxModel = this._model.Union
	
	
	fxModel.Bottom.WorldCFrame = humObj.HRootPart.CFrame * CFrame.new(0, -3, 0)
	fxModel.Top.WorldCFrame = fxModel.CFrame	
	fxModel.flame.WorldCFrame = fxModel.CFrame
	fxModel.strike.WorldCFrame = fxModel.CFrame * CFrame.new(0, 0.5, 0)
	
	humObj.walkSpeed:SetMod("stopMoving", -100)
	game.ReplicatedStorage.RemoteEvents.VFX:FireAllClients("hshock", humObj.HRootPart)
	
	local leftLeg = char:FindFirstChild("Left Leg")
	for i,v in pairs(fxModel.start:GetChildren()) do
		v.Parent = leftLeg
		if v:IsA("ParticleEmitter") then
			--v:Emit(v:GetAttribute("EmitCount") or 10)
			v.Enabled = true
		end
	end
	local anim = this:PlayAnim(script.Heavy, 0.1, 1, 0.65)
	
	task.wait(1)
	
	
	

	for i,v in pairs(fxModel.Bottom:GetChildren()) do
		if v:IsA("ParticleEmitter") then
			--v:Emit(v:GetAttribute("EmitCount") or 2)
			v.Enabled = true
		end
	end

	

	
	local Hold = this._model.Hold
	--[[
	]]--


	--[[Hold.slideSfx:Play()
	Hold.slideSfx.TimePosition = 0.1
	Hold.wind:Play()]]--
	anim:AdjustSpeed(1)
	fxModel.flame.star:Emit(1)
	
	task.wait(0.3)
	
	
	task.wait(0.2)
	for i,v in pairs(fxModel.flame:GetChildren()) do
		if v:IsA("ParticleEmitter") then
			--v:Emit(v:GetAttribute("EmitCount") or 5)\
			v.Enabled = true
		end
	end
	
	humObj:FireVFXClient(
		"rootImpulse",
		Vector3.new(0,0,0)
	)
	
	task.wait(0.4)
	
	anim:AdjustSpeed(1.5)
	if force then
		force:destroy()
	end
	

	local slamForce = this:bodyForce(Vector3.new(0,-20,0), 1, true, 0.18, 1)
	
	Hold.Parent.Trail1.Enabled = false
	Hold.Parent.heavy.Enabled = true
	
	task.wait(0.3)
	
	if slamForce then
		slamForce:destroy()
	end
	--[[
	slamForce = this:bodyForce(
		Vector3.new(0, -30, 0),
		0.18,
		true,
		0.18,
		1
	)

	if slamForce then
		slamForce:destroy()
	end
	
	task.wait(0.15)
	
	slamForce = this:bodyForce(
		Vector3.new(0, -40, 0),
		0.18,
		true,
		0.18,
		1
	)
	
	if slamForce then
		slamForce:destroy()
	 ]]--
	
	for i,v in pairs(fxModel.Top:GetChildren()) do
		if v:IsA("ParticleEmitter") then
			v:Emit(v:GetAttribute("EmitCount") or 6)
		end
	end
	
	humObj:FireVFXClient(
		"rootImpulse",
		Vector3.new(0,-10,0)
	)	

	Hold.Parent.heavy.Enabled = false
	--Hold.Parent.Trail1.Enabled = true
	if this:feintWait(0.75) then this:triggerCD("heavy", 3) this:stopLastAnim(true) humObj.walkSpeed:RemoveMod("stopMoving") force:destroy() slamForce:destroy() Hold.slideSfx:Stop() Hold.HSWING1:Stop() return end
	
	--attack
	--this:triggerCD("heavy")
	--Hold.slideSfx:Stop()
	
	--local bigSlashCF = hurtbox.CFrame*CFrame.Angles(0,0,math.rad(-20))*CFrame.Angles(0,math.rad(-90),0)
	--local bigSlashSz = Vector3.new(22, 5 ,22)
	--game.ReplicatedStorage.RemoteEvents.VFX:FireAllClients("BigSlash",bigSlashCF, hurtbox,bigSlashSz)
	
	
	local hitboxOffset = CFrame.new(0, -2, -3)
	local hitboxSize   = Vector3.new(11,6,11)
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