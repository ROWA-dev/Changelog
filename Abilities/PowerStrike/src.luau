--!strict
--[[ PowerStrike - rowa1 Items/Ability/PowerStrike.
	Notes: README.md/PORT_PowerStrike.

	A two-stage weapon flourish: blade shine, one committed slash, then a
	bigger launching slash a beat later. Needs a weapon.

	THE HALF-COOLDOWN IS THE POINT. Stage 1 takes half the cooldown, stage 2
	overwrites it with the full one -- so landing only the opener costs you
	much less than committing to both. That is `dontOverwrite` true then
	absent, which is exactly the pair of flags cooldowns:trigger takes.

	(This file started as an unregistered single-stage scratch. Reconciled
	rather than replaced.) ]]
local baseClass = require(script.Parent.AbilityBase)
export type myself = baseClass.myself
type humObj = baseClass.humObj

local module = {
	Name = "PowerStrike"
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
local dmgFlag  = dmgUtils.dmgFlags
local fireVFX = require(game.ServerStorage.ROWA.Modules.fireVFX)
local hitSfx  = require(game.ServerStorage.ROWA.Modules.hitSfx)

-- rowa1 "gold": Medium, slash, 20 dmg, truestun 0.2 / stun 0.8, posMult 2.
-- Used by BOTH stages in the original; kept shared here for the same reason.
local GOLD = {
	weight   = dmgUtils.weighEnum.Medium,
	type     = dmgFlag.slash,
	dmg      = 13,
	stun     = 0.8,
	posMult  = 2,
	parryH   = -0.1,
	onHit    = function(attack)
		hitSfx(attack.enemyEntity.HRootPart, "HitSound", "HitChop", "SlashHit")
	end,
}

local CD_HALF, CD_FULL = 6, 12

local function useFunc(this:myself)
	local cooldownID = "powerStrike"
	if this:canTriggerCD(cooldownID) ~= true then return end

	local humObj = this._humObj
	if humObj.wielding_weapon == nil then
		return -- weapon flourish; rowa1 gated on the Tool having a Model
	end

	local hurtbox = humObj.HurtBox
	local anim    = this:PlayAnim(script.Anim, 0, 1, 1)

	-- nil-degrade: no blade just means no shine, same as FireStab.
	local blade = humObj:GetBlade()
	if blade then
		fireVFX("fsShine", blade, hurtbox.Parent)
	end

	if this:feintWait(0.45) then
		if anim then anim:Stop() end
		return
	end

	this:useMana()
	--- stage 1: HALF cooldown, and dontOverwrite so a re-entrant call cannot
	--- stack a second one on top.
	this:triggerCD(cooldownID, CD_HALF, true)

	fireVFX("fstrike", hurtbox)

	local _, hits = this:hitbox(CFrame.new(0, 0, -4), Vector3.new(5, 5, 6))
	for _, enemy in pairs(hits) do
		local attack = this:makeAtk(GOLD, enemy, hurtbox.CFrame.LookVector)
		attack.knockback = this:knockback(
			-- rowa1 look*8 + (0,2,0), at the x0.6 ratio (README S7)
			attack.atkDir * 4.8 + Vector3.new(0, 1.2, 0), 0.1, false, -1)
		this:executeAttack(attack)
	end

	--[[ rowa1 set Attacking=false between the two slashes, which is how the
		player could be interrupted mid-sequence. AbilityBase owns that flag
		now, so DO NOT touch it -- feintWait restores the interruptibility
		without lying to the rest of the system. ]]
	if this:feintWait(0.35) then
		if anim then anim:Stop() end
		return
	end

	--- stage 2: overwrite with the FULL cooldown. No dontOverwrite here --
	--- that is the whole mechanism.
	this:triggerCD(cooldownID, CD_FULL)

	fireVFX("fstrike2", hurtbox)

	local _, hits2 = this:hitbox(CFrame.new(0, 0, -5), Vector3.new(7, 7, 7))
	for _, enemy in pairs(hits2) do
		local attack = this:makeAtk(GOLD, enemy, hurtbox.CFrame.LookVector)
		attack.knockback = this:knockback(
			-- rowa1 look*16 + (0,8,0), at the x0.6 ratio (README S7)
			attack.atkDir * 9.6 + Vector3.new(0, 4.8, 0), 0.15, false, -1)
		this:executeAttack(attack)
	end

	this:endLag(0.1)
end

function module.use(self:myself)
	return baseClass.use(self, useFunc)
end

return table.freeze(module)
