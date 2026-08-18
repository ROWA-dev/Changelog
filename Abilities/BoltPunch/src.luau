--!strict
--[[ BoltPunch - rowa1 Items/Ability/BoltPunch. Notes: README.md/PORT_BoltPunch.

	A lunging lightning straight. The dash fires BEFORE the windup and runs
	across it, so you commit your position at frame 0 -- that is the move's
	identity and its risk, not an accident. ]]
local baseClass = require(script.Parent.AbilityBase)
export type myself = baseClass.myself
type humObj = baseClass.humObj

local module = {
	Name = "BoltPunch"
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

--[[ rowa1 "bolt": Heavy, blunt+MAGIC, 38 dmg, truestun 0.5 / stun 1.0.
	The magic flag (not lightning) is carried across deliberately -- rowa1
	tagged the whole punch family that way and `isElemental` catches both, so
	changing it is a balance decision, not a port fix. Flagged in the doc.

	The onHit was a FORTY-LINE inline function in rowa1's damage table: it
	cloned an fx part, emitted eleven emitters, fired CamShake and spawned a
	coroutine that crackled the victim for 0.7s. All of that is the
	`bolthit` quiver module now -- see VFXQuiver/bolthit. ]]
local BOLT = {
	weight   = dmgUtils.weighEnum.Heavy,
	type     = bit32.bor(dmgFlag.blunt, dmgFlag.magic),
	dmg      = 24,
	stun     = 1,
	posMult  = 3,
	parryH   = -0.04,
	onHit    = function(attack, source: any)
		local eroot = attack.enemyEntity.HRootPart
		hitSfx(eroot, "LightningClash")
		fireVFX("bolthit", eroot, source and source.HRootPart)
	end,
}

local FX_CHARGE, FX_FIZZLE = 1, 2

local function useFunc(this:myself)
	local cooldownID = "boltPunch"
	if this:canTriggerCD(cooldownID) ~= true then return end

	local humObj  = this._humObj
	local hurtbox = humObj.HurtBox
	local anim    = this:PlayAnim(script.Anim, 0, 1, 1)

	fireVFX("boltp", FX_CHARGE, humObj.Hum)

	--[[ isRootRelative TRUE, so the vector is in the ROOT's local space and
		the lunge follows you as you turn. Passing a world-space LookVector
		locks the direction at frame 0 and the dash becomes unsteerable --
		which is not what rowa1 did either: its "rmove" proxy took a LOCAL
		vector and the client applied it relative to the root every frame.

		KEEP THE HANDLE. bodyForce returns a mover with :destroy(); without
		it the player keeps sliding for the full 0.3s after a cancel.

		8 not 7: rowa1's MiniDash2 used power 40, and rowa2's bodyForce scales
		by 5 internally, so 40/5 = 8. ]]
	local dash = this:bodyForce(Vector3.new(0, 0, -8), 0.3, true)

	if this:feintWait(0.45) then
		if anim then anim:Stop() end
		if dash then dash:destroy() end
		fireVFX("boltp", FX_FIZZLE, humObj.Hum)
		return
	end

	this:useMana()
	this:triggerCD(cooldownID, 10, true)

	local _, hits = this:hitbox(CFrame.new(0, 0, -4), Vector3.new(5, 5, 6))

	for _, enemy in pairs(hits) do
		local attack = this:makeAtk(BOLT, enemy, hurtbox.CFrame.LookVector)
		--[[ no knockback, matching rowa1. The dash already closed the gap and
			a launch would undo it -- that is why a 38-damage heavy shipped
			without one. ]]
		this:executeAttack(attack)
	end

	this:endLag(0.15)
end

function module.use(self:myself)
	return baseClass.use(self, useFunc)
end

return table.freeze(module)
