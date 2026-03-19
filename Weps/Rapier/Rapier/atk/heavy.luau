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
	Hold.inhale:Play()
	
	humObj.walkSpeed:SetMod("stopMoving", -100)
	if this:feintWait(0.46) then this:stopLastAnim(true) humObj.walkSpeed:RemoveMod("stopMoving") return end
	this:triggerCD("heavy")
	
	local hitboxOffset = CFrame.new(0, 0, -3)
	local hitboxSize   = Vector3.new(4,6,7)
	
	local hitLanded = false
	local first = true
	for i = 1,5 do
		if humObj and humObj.isActive and humObj:inStun() == false then
		else
			if humObj and humObj.isActive then
				humObj.walkSpeed:RemoveMod("stopMoving")
			end
			anim:Stop()
			return
		end
		
		local dwing = Hold.Swing2:Clone()
		dwing.TimePosition = 0.2
		dwing.PlaybackSpeed = math.random(9,11)/10
		dwing:Play()
		dwing.Parent = Hold
		game.Debris:AddItem(dwing, 4)
		
		local model = this._model
		model.Blade.Bottom.spike:Emit(1)
		model.Blade.Bottom.spike2:Emit(1)
		model.Blade.Bottom.shock:Emit(1)
		
		local hitbox, hits = this:hitbox(hitboxOffset, hitboxSize)
		for _,enemhum in pairs(hits) do
			local dmgTbl = dmgConfig.heavy
			if first == true then
				dmgTbl = dmgConfig.firstHeavy
			elseif i == 5 then
				dmgTbl = dmgConfig.lastHeavy
			end
			first = false
			
			local attack = this:makeAtk(
				dmgTbl,
				enemhum,
				hurtbox.CFrame.LookVector
			)

			task.spawn(this.executeAttack, this, attack)
			if attack:isHit() then hitLanded = true end
		end
		this:atkWait(0.09)
	end
	
	if hitLanded == false then
		this:endLag(0.4)
	--else
		--this:endLag(0.2)
	end
	
	humObj.walkSpeed:RemoveMod("stopMoving")
	return hitLanded
end