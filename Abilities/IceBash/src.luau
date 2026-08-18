--!strict
--[[ IceBash - rowa1 Items/Ability/IceBash. Port notes: README.md/PORT_IceBash.

	A committed overhead ice smash. Longest reach of the simple set, ragdolls
	on hit, and feeds the Freeze meter (Class/StatusEffects/Freeze) rather
	than carrying an ice stun of its own. ]]
local baseClass = require(script.Parent.AbilityBase)
export type myself = baseClass.myself
type humObj = baseClass.humObj

local module = {
	Name = "IceBash"
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
local statusEffects = require(game.ServerStorage.ROWA.Class.StatusEffects)
local fireVFX = require(game.ServerStorage.ROWA.Modules.fireVFX)
local hitSfx  = require(game.ServerStorage.ROWA.Modules.hitSfx)

-- rowa1 "ice3" was dmg 30 / truestun 0.4 / stun 0.6. The two stun fields
-- collapse to one (README S4.2) and damage is scaled to rowa2's economy,
-- same ~0.65 the three shipped ports landed on.
local ICE3 = {
	weight   = dmgUtils.weighEnum.Heavy,
	type     = bit32.bor(dmgFlag.ice, dmgFlag.blunt),
	dmg      = 19,
	stun     = 0.6,
	posMult  = 2,
	parryH   = -0.04,
	onHit    = function(attack)
		hitSfx(attack.enemyEntity.HRootPart, "IceSplash2")
	end,
}

--- the "icebsh" quiver module switches on this first argument.
local FX_CHARGE, FX_FIZZLE, FX_CONNECT = 1, 2, 3

local function useFunc(this:myself)
	local cooldownID = "iceBash"
	if this:canTriggerCD(cooldownID) ~= true then return end

	local humObj  = this._humObj
	local hurtbox = humObj.HurtBox
	local anim    = this:PlayAnim(script.Anim, 0, 1, 1)

	fireVFX("icebsh", FX_CHARGE, humObj.Hum)

	-- rowa1 was 0.1 + 5*0.1. One call, and now it is cancellable for free.
	if this:feintWait(0.6) then
		if anim then anim:Stop() end
		fireVFX("icebsh", FX_FIZZLE, humObj.Hum)
		return
	end

	this:useMana()
	this:triggerCD(cooldownID, 8, true)

	--[[ rowa1 reached look*7, the longest in the simple set. Extending
		`range` rather than inflating the box keeps the shape honest: range
		grows the OBB along the facing axis only, an 11-deep box would also
		catch people beside you. ]]
	this.range:SetMod(cooldownID, 1)
	local _, hits = this:hitbox(CFrame.new(0, 0, -6), Vector3.new(6, 6, 7))
	this.range:RemoveMod(cooldownID)

	local hitAny = false
	for _, enemy in pairs(hits) do
		local attack = this:makeAtk(ICE3, enemy, hurtbox.CFrame.LookVector)
		-- rowa1 look*8, converted at the x0.6 knockback ratio (see README S7).
		attack.knockback = this:knockback(attack.atkDir * 4.8, 0.15, false, -1)

		this:executeAttack(attack)
		if attack:isHit() then
			hitAny = true
			--[[ !! 0.8 AND false, NOT 60. rowa1's ice3 used the `ragdollWait`
				OnHitFunc, which ragdolls for 0.8 SECONDS FLAT. The other
				OnHitFunc, `ragdtillground`, is the until-you-land one and is
				what every `(60, true)` call in this codebase means -- 60 is a
				CAP, and stopOnGround ends it early.
				`(60, false)` therefore means "sixty seconds flat, never check
				the ground", which is why victims stopped getting up. ]]
			attack.enemyEntity.ragdoll:ragdoll(0.8, false, attack.atkDir * 8)
			--[[ 3 of a 10 meter. IceBash is the SETUP in the ice kit -- a
				solid chunk off one committed heavy, but never a freeze on its
				own. See PORT_Freeze section 1. ]]
			attack.enemyEntity.statusEffects:apply(statusEffects.Freeze, 4, 3)
		end
	end

	--[[ rowa1 used `val == nil` as its hit test, which also counted ABORTED
		attacks as hits (README S3.3). `isHit` is narrower on purpose, so the
		connect flourish now fires slightly less often. That is the fix. ]]
	fireVFX("icebsh", hitAny and FX_CONNECT or FX_FIZZLE, humObj.Hum)

	this:endLag(0.2)
end

function module.use(self:myself)
	return baseClass.use(self, useFunc)
end

return table.freeze(module)
