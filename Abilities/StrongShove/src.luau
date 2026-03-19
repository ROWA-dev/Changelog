--!strict
local baseClass = require(script.Parent.AbilityBase)
export type myself = baseClass.myself
type humObj = baseClass.humObj

local module = {
	Name = "StrongShove"
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
	local cooldownID = "impale"
	if this:canTriggerCD(cooldownID) ~= true then return end
	print("USE ABILITY!")
	local anim = this:PlayAnim(script.anim, 0, 1, 1)
	local humObj = this._humObj
	local root = humObj.HurtBox
	
	humObj.walkSpeed:SetMod("stopMoving", -100)
	local st = tick()
	local feinted = this:feintWait(0.6, function(dt: number)
		local t = tick()-st
		--Idle.Squash = NumberSequence.new(t-0.4)
		--Idle:Emit(1)
	end)
	
	humObj.walkSpeed:RemoveMod("stopMoving")
	if feinted then
		if anim then
			anim:Stop()
		end
		return
	end
	
	--this:triggerCD(cooldownID, 6, true)
	
	local hurtbox  = humObj.HurtBox
	
	local hitboxOffset = CFrame.new(0, 0, -4)
	local hitboxSize   = Vector3.new(6,7,7)
	local hits		   = this:hitbox(hitboxOffset, hitboxSize)
	
	local dmgTbl = {
		weight   = dmgUtils.weighEnum.Medium,
		type     = bit32.bor(dmgFlag.blunt, dmgFlag.fire),
		dmg      = 30,
		stun     = 1,
		posMult  = 2,
		--parryH   = -0.1
		
		onHit    = require(script.punch),
	}
	
	for _,enemhum in pairs(hits) do
		local attack = this:makeAtk(
			dmgTbl,
			enemhum,
			hurtbox.CFrame.LookVector
		)
		
		local newkb = this:knockback(
			attack.atkDir*16,
			0.1,
			false,
			-1
		)
		attack.knockback = newkb

		this:executeAttack(attack)
		--[[if attack:isHit() then
			attack.enemyEntity.ragdoll:ragdoll(60, true, attack.atkDir*10)
		end]]
	end
	
	--humObj.canAtkThreshold = tick() + 0.24
	this:endLag(0.1)
end

function module.use(self:myself)
	baseClass.use(self, useFunc)
end


return table.freeze(module)
