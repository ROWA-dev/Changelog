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
local fireVFX = require(game.ServerStorage.ROWA.Modules.fireVFX)
local function useFunc(this:myself)
	local cooldownID = "Barrage"
	if this:canTriggerCD(cooldownID) ~= true then return end
	local anim = this:PlayAnim(script.Anim, 0, 1, 1.4)
	local humObj = this._humObj
	local hroot = humObj.HRootPart

	local sound2 = script.Swing2:Clone()
	sound2.Parent = hroot
	sound2:Play()
	game.Debris:AddItem(sound2, 4)

	local feinted = this:feintWait(0.42)
	
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
		dmg      = 4,
		stun     = 0.6,
		posMult  = 0.5,
		parryH   = 0.1,
		stunMeOnParried = 0,
		onHit    = require(script.punch),
	}

	local Char = hurtbox.Parent
	fireVFX("hideArms", Char)
	local hitlanded = false
	for i = 1,18 do
		fireVFX("brrgArms", Char)

		local _, hits = this:hitbox(hitboxOffset, hitboxSize)
		for _,enemy in pairs(hits) do
			local attack = this:makeAtk(
				dmgTbl,
				enemy,
				hurtbox.CFrame.LookVector
			)

			--this:executeAttack(attack)
			task.spawn(function()
				this:executeAttack(attack)
				if attack:isHit() then
					hitlanded = true
					dmgTbl.parryH = 1
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

		local why = this:channelBreak()
		if why then
			if anim then anim:Stop() end
			if sound then sound:Stop() end
			fireVFX("showArms", Char)
			-- only a feint owes the recovery; being stunned out of it is punishment enough.
			if why == "feint" and hitlanded == false then
				this:endLag(0.2)
			end
			return true
		end

		if i == 14 then
			fireVFX("showArms", Char)
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
