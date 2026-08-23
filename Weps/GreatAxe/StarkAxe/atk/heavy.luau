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


	
	local rootCF = root.CFrame

	local strike = fxModel.strike:Clone()
	strike.Parent = root
	strike.WorldCFrame = fxModel.CFrame * CFrame.new(0, -4, 0) * CFrame.Angles(0,0,0)
	
	
	humObj.walkSpeed:SetMod("stopMoving", -100)
	game.ReplicatedStorage.RemoteEvents.VFX:FireAllClients("hshock", humObj.HRootPart)
	
	--flame.star:Emit(10)


	
	local anim = this:PlayAnim(script.Heavy, 0.1, 1, 0.8)
	task.wait(0.1)

	task.wait(0.6)

	local force = this:bodyForce(Vector3.new(0,10,-15), 1.5, true, 0.8, 1)

	local Hold = this._model.Hold
	
	Hold.Parent.heavy.Enabled = false
	--Hold.Parent.Trail1.Enabled = true
	if this:feintWait(0.67) then this:triggerCD("heavy", 3) this:stopLastAnim(true) humObj.walkSpeed:RemoveMod("stopMoving") force:destroy()  Hold.slideSfx:Stop() Hold.HSWING1:Stop() return end
	
	local highlight = Instance.new("Highlight")
	highlight.Adornee = char
	highlight.FillColor = Color3.fromRGB(255, 255, 150)
	highlight.OutlineColor = Color3.fromRGB(255, 255, 40)

	highlight.FillTransparency = 1
	highlight.OutlineTransparency = 1

	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Parent = char


	humObj:FireVFXClient("tween", 
		highlight,
		{1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out},
		{
			FillTransparency = 0,
			OutlineTransparency = 0,
		})

	
	if not humObj or not humObj.isActive or humObj:inStun() then

		Hold.Parent.heavy.Enabled = false


		if force then
			force:destroy()
		end

		return
	end	
	


	

	Hold.Parent.Trail1.Enabled = false
	Hold.Parent.heavy.Enabled = true




	if force then
		force:destroy()
	end
	
	task.wait(0.5)
	highlight:Destroy()
	--humObj:FireVFXClient("smashLand", humObj.HRootPart.Position )
	
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
	
	

	task.wait(0.5)

	if landed == false then
		this:endLag(0.4)
	end
	this:endLag(0.1)
	
	
	task.wait(0.1)
	humObj.walkSpeed:RemoveMod("stopMoving")

	return
end