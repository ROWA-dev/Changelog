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
	dmg      = 20,
	stun     = 1,
	posMult  = 2,
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
	local anim    = this:PlayAnim(script.Anim, 0, 1, 0.9)

	fireVFX("boltp", FX_CHARGE, humObj.Hum)

	local dash = this:bodyForce(Vector3.new(0, 0, -7.5), 0.4, true)

	if this:feintWait(0.5) then
		if anim then anim:Stop() end
		if dash then dash:destroy() end
		fireVFX("boltp", FX_FIZZLE, humObj.Hum)
		return
	end

	this:useMana()
	this:triggerCD(cooldownID, 10, true)

	local _, hits
	for i = 1,3 do
		_, hits = this:hitbox(CFrame.new(0, 0, -4), Vector3.new(6, 6, 6))
		if #hits ~= 0 then
			break
		end
		task.wait(0.05)
	end

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
