--!strict
local baseClass = require(script.Parent.AbilityBase)
export type myself = baseClass.myself
type humObj = baseClass.humObj

local module = {
	Name = "Barrage"
}
module.__tostring = baseClass.__tostring
module.__index = module
setmetatable(module, { __index = baseClass })

function module.new(humObj:humObj):myself
	local abstract = baseClass.new(humObj) :: baseClass.myself
	local self:myself = setmetatable(abstract, module) :: any
	return self
end

local dmgUtils = require(game.ServerScriptService.Utils.DmgUtils)
local dmgFlag = dmgUtils.dmgFlags
local function useFunc(this:myself)
	local cooldownID = "Barrage"
	if this:canTriggerCD(cooldownID) ~= true then return end
	print("USE ABILITY!")
	local anim = this:PlayAnim(script.Anim, 0, 1, 1.2)
	local humObj = this._humObj
	local hroot = humObj.HRootPart

	local sound2 = script.Swing2:Clone()
	sound2.Parent = hroot
	sound2:Play()
	game.Debris:AddItem(sound2, 4)

	local st = tick()
	local feinted = this:feintWait(0.6, function(dt: number)
		local t = tick()-st
		--Idle.Squash = NumberSequence.new(t-0.4)
		--Idle:Emit(1)
	end)
	
	if anim then anim:AdjustSpeed(0.9) end

	if feinted then
		if anim then
			anim:Stop()
		end
		return
	end

	local sound = script.barrage:Clone()
	sound.Parent = hroot
	sound:Play()
	game.Debris:AddItem(sound, 4)

	this:useMana()
	this:triggerCD(cooldownID, 6, true)


	local hurtbox  = humObj.HurtBox
	local hitboxOffset = CFrame.new(0, 0, -3)
	local hitboxSize   = Vector3.new(5,5,5)
	local dmgTbl = {
		weight   = dmgUtils.weighEnum.Light,
		type     = bit32.bor(dmgFlag.blunt),
		dmg      = 2.5,
		stun     = 0.5,
		posMult  = 0.5,
		parryH   = 0.1,
		stunMeOnParried = 0,
		onHit    = require(script.punch),
	}

	local Char = hurtbox.Parent
	local FxRemote = game.ReplicatedStorage.RemoteEvents.VFX
	--FxRemote:FireAllClients("hideArms", Char)
	local hitlanded = false
	for i = 1,18 do
		FxRemote:FireAllClients("brrgArms", Char)

		local hits = this:hitbox(hitboxOffset, hitboxSize)
		for _,enemhum in pairs(hits) do
			local attack = this:makeAtk(
				dmgTbl,
				enemhum,
				hurtbox.CFrame.LookVector
			)

			--this:executeAttack(attack)
			task.spawn(function()
				this:executeAttack(attack)
				if attack:isHit() then
					hitlanded = true
				elseif attack:isParried() then
					if attack.enemyEntity.attacking and attack.enemyEntity.attacking.Value == true then
						dmgTbl.stunMeOnParried = 0.1
					end
					hitlanded = false
					dmgTbl.parryH = 1
				end
			end)
		end

		task.wait(0.08)
		if humObj:inStun() then
			if anim then anim:Stop() end
			if sound then sound:Stop() end
			return true
		end
		local wantedFeint = this.isFeinted
		if wantedFeint == true then
			if anim then anim:Stop() end
			if sound then sound:Stop() end
			this.isFeinted = false
			--humObj.canAtkThreshold = tick() + 0.1

			humObj.cooldowns:trigger("feint2")

			local now = tick()
			if wantedFeint and now > st + 0.18 then
				game.ReplicatedStorage.RemoteEvents.VFX:FireAllClients("feintfx", this._humObj.Hum.Parent)
			end
			if hitlanded == false then
				this:endLag(0.2)
			end
			return true
		end

		if i == 14 then
			--FxRemote:FireAllClients("showArms", Char)
		end
	end

	if hitlanded == false then
		this:endLag(0.2)
	end
	
	return true
end

function module.use(self:myself)
	return baseClass.use(self, useFunc)
end


return table.freeze(module)
