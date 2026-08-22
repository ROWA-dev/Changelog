--!strict
local wepType = require(game.ServerStorage.ROWA.Weps.WepBase.types)
type wepTyp = wepType.myself

local dmgConfig = require(script.Parent.Parent.dmgConfig)
local destruction = require(game.ServerStorage.ROWA.Destruction_Stable.Destruction)

return function(this:wepTyp&any): wepType.atkResult
	if this:canTriggerCD("heavy") == false then return end	
	local humObj   = this._humObj
	local hurtbox  = humObj.HurtBox
	
	local anim = this:PlayAnim(script.heavy, 0.08, 1, 1)
	game.ReplicatedStorage.RemoteEvents.VFX:FireAllClients("hshock", humObj.HRootPart)
	
	local Hold = this._model.Hold
	Hold.swish:Play()
	Hold.afterswing2:Play()
	
	local SlashFX = script.Slash:Clone()
	SlashFX.Parent = workspace.Effects
	SlashFX.Weld.Part0 = SlashFX
	SlashFX.Weld.Part1 = humObj.HRootPart
	SlashFX.Transparency = 1
	
	this:indicateAtk()
	
	if this:feintWait(0.22) then this:stopLastAnim(true) return end
	this:triggerCD("heavy")
	Hold.unsheatheReverb:Play()
	if this:feintWait(0.12) then this:stopLastAnim(true) return end
	
	Hold.Swing1:Play()
	Hold.Swing1.Pitch = 1
	Hold.lunge:Play()
	Hold.flamefurst:Play()
	
	SlashFX.PointLight.Enabled = true
	SlashFX.Transparency = 0.8
	--game.ReplicatedStorage.RemoteEvents.VFX:FireAllClients("fistHvy", hurtbox)
	
	local force = this:bodyForce(Vector3.new(0,0,-14), 0.4, true, 0.5)
	local hitLanded = false


	local hitboxOffset = CFrame.new(0, 0, -2)
	local hitboxSize   = Vector3.new(5,4,5)
	
	local aura = Hold.Parent:FindFirstChild("Blade").aura
	local auraVFX = aura:GetChildren()
	local ts = game:GetService("TweenService")
	local isParried = false
	local isHit = {}
	for i = 1,5 do
		local hitbox, hits = this:hitbox(hitboxOffset, hitboxSize)
		for _,enemy in pairs(hits) do
			local found = isHit[enemy]
			if found then
				if found == 0 then
					continue
				end
				isHit[enemy] -= 1
			else
				isHit[enemy] = 1
			end
			local dmgTbl = dmgConfig.heavy

			local attack = this:makeAtk(
				dmgTbl,
				enemy,
				hurtbox.CFrame.LookVector
			)

			task.spawn(function()
				local result = this:executeAttack(attack)
				if attack:isHit() then
					hitLanded = true
				elseif attack:isParried() then
					this:stopLastAnim(true)
					force:destroy()
					isParried = true
				end
			end)
		end
		if i == 3 or isParried then
			local TweenOut = ts:Create(SlashFX, TweenInfo.new(0.4), {Transparency = 1})
			local TweenOut2 = ts:Create(SlashFX.PointLight, TweenInfo.new(0.4), {Brightness = 0})
			TweenOut2:Play()
			TweenOut:Play()
			if isParried then
				break
			end
		end
		if i == 5 then
			for _,v in pairs(auraVFX) do
				v.LockedToPart = false
			end
		end
		if i < 5 then
			for _,v in pairs(auraVFX) do
				if v.Name == "HitDirection" then
					v:Emit(2)
				else
					v:Emit(4)
				end
				v.LockedToPart = true
			end
			this:atkWait(0.1)
		end
	end
	table.clear(isHit)
	game.Debris:AddItem(SlashFX,2)
	if hitLanded == false then
		this:endLag(0.2)
	end
	
	return hitLanded
end