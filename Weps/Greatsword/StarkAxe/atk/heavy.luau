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
	local root = humObj.HRootPart

	fxModel.Bottom.WorldCFrame = humObj.HRootPart.CFrame * CFrame.new(0, -3, 0)
	fxModel.Top.WorldCFrame = fxModel.CFrame	
	fxModel.flame.WorldCFrame = fxModel.CFrame  * CFrame.new(0, -3.5, 0)
	fxModel.strike.WorldCFrame = fxModel.CFrame * CFrame.new(0, -5, 0)
	
	humObj.walkSpeed:SetMod("stopMoving", -100)
	game.ReplicatedStorage.RemoteEvents.VFX:FireAllClients("hshock", humObj.HRootPart)
	
	fxModel.flame.star:Emit(1)
	
	local leftLeg = char:FindFirstChild("Left Leg")
	for i,v in pairs(fxModel.start:GetChildren()) do
		v.Parent = leftLeg
		if v:IsA("ParticleEmitter") then
			v:Emit(v:GetAttribute("EmitCount") or 10)
		
		end
	end
	

	
	
	

	for i,v in pairs(fxModel.Bottom:GetChildren()) do
		if v:IsA("ParticleEmitter") then
			v.Enabled = true
			
		end
	end


	
	
	local anim = this:PlayAnim(script.Heavy, 0.1, 1, 0.8)
	task.wait(0.1)
	
	for i,v in pairs(fxModel.Bottom:GetChildren()) do
		if v:IsA("ParticleEmitter") then
			v.Enabled = false

		end
	end
	
	task.wait(0.6)
	local force = this:bodyForce(Vector3.new(0,10,-15), 1.5, true, 0.8, 1)
	--root.CFrame = root.CFrame + root.CFrame.LookVector * 0.5 + Vector3.new(0, 0.3, 0)
	--local force = this:bodyForce(Vector3.new(0,2,-15), 1.5, true, 0.8, 1)
	
	local Hold = this._model.Hold
	
	Hold.Parent.heavy.Enabled = false
	--Hold.Parent.Trail1.Enabled = true
	if this:feintWait(0.75) then this:triggerCD("heavy", 3) this:stopLastAnim(true) humObj.walkSpeed:RemoveMod("stopMoving") force:destroy()  Hold.slideSfx:Stop() Hold.HSWING1:Stop() return end
	
	
	if not humObj or not humObj.isActive or humObj:inStun() then

		Hold.Parent.heavy.Enabled = false


		if force then
			force:destroy()
		end

		return
	end	
	for i,v in pairs(fxModel.strike:GetChildren()) do
		if v:IsA("ParticleEmitter") then
			v.Enabled = true
		end
	end


	


	

	local rootCF = root.CFrame

	local forward = rootCF.LookVector



	Hold.Parent.Trail1.Enabled = false
	Hold.Parent.heavy.Enabled = true

	for i,v in pairs(fxModel.strike:GetChildren()) do
		if v:IsA("ParticleEmitter") then
			v.Enabled = false
		end
	end


	if force then
		force:destroy()
	end
	
	task.wait(0.7)
	local hitboxOffset = CFrame.new(0, -1, 0)
	local hitboxSize   = Vector3.new(20,7,20)
	local hitbox, hits = this:hitbox(hitboxOffset, hitboxSize)

	local landed = false
	for _,enemy in pairs(hits) do
		local attack = this:makeAtk(
			dmgConfig.heavy,
			enemy,
			hurtbox.CFrame.LookVector
		)
		local direction = (enemy.HRootPart.Position - root.Position).Unit
		
		local newkb = this:knockback(
			direction*20+Vector3.new(0,25,0),
			0.25
		)
		attack.enemyEntity.ragdoll:ragdoll(200, true, direction*10)
		
		attack.hitbox = hitbox
		attack.knockback = newkb

		this:executeAttack(attack)
		if attack:isHit() then
			landed = true
		end
	end
	
	
	for i,v in pairs(fxModel.Top:GetChildren()) do
		if v:IsA("ParticleEmitter") then
			v.Enabled = true
		end
	end
	task.wait(0.1)
	
	
	
	if landed == false then
		this:endLag(0.4)
	end
	this:endLag(0.1)


	task.wait(0.1)
	humObj.walkSpeed:RemoveMod("stopMoving")
	for i,v in pairs(fxModel.Top:GetChildren()) do
		if v:IsA("ParticleEmitter") then
			v.Enabled = false
		end
	end
	--[[for i = 1,5 do
		if not humObj or not humObj.isActive or humObj:inStun() then
			
			Hold.Parent.heavy.Enabled = false
			

			if force then
				force:destroy()
			end

			return
		end	
		
		

		for i,v in pairs(fxModel.strike:GetChildren()) do
			if v:IsA("ParticleEmitter") then
				--v.Enabled = true
			end
		end


		local rootCF = root.CFrame

		local forward = rootCF.LookVector

		

		Hold.Parent.Trail1.Enabled = false
		Hold.Parent.heavy.Enabled = true


		
		for i,v in pairs(fxModel.Top:GetChildren()) do
			if v:IsA("ParticleEmitter") then
				v.Enabled = true
			end
		end
		
		if force then
			force:destroy()
		end
		local hitboxOffset = CFrame.new(0, -1, -3)
		local hitboxSize   = Vector3.new(9,7,9)
		local hitbox, hits = this:hitbox(hitboxOffset, hitboxSize)

		local landed = false
		for _,enemy in pairs(hits) do
			local attack = this:makeAtk(
				dmgConfig.heavy,
				enemy,
				hurtbox.CFrame.LookVector
			)

			local newkb = this:knockback(
				attack.atkDir*1.2,
				0.05
			)

			attack.hitbox = hitbox
			attack.knockback = newkb

			this:executeAttack(attack)
			if attack:isHit() then
				landed = true
			end
		end
		task.wait(0.1)
		--destruction.Sphere(humObj.plrObj.Plr)
		if landed == false then
			this:endLag(0.4)
		end
		this:endLag(0.1)
		
		for i,v in pairs(fxModel.Top:GetChildren()) do
			if v:IsA("ParticleEmitter") then
				v.Enabled = false
			end
		end
		
	end
	humObj.walkSpeed:RemoveMod("stopMoving")]]--
	return
end