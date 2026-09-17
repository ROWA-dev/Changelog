--!strict
--- Lightning - call a bolt down on a target's position. Four staged client
--- effects, a flash-step, and a finisher flash on connect.
--- NOT a projectile: a delayed world-space AoE at a raycast endpoint, nothing
--- travels.
--- The hitbox runs ONCE; the 4 x 0.1s loop is the WINDUP.
local baseClass = require(script.Parent.AbilityBase)
export type myself = baseClass.myself
type humObj = baseClass.humObj

local module = {
	Name = "Lightning"
}
module.__tostring = baseClass.__tostring
module.__index = module
setmetatable(module, { __index = baseClass })

function module.new(humObj:humObj):myself
	local abstract = baseClass.new(humObj) :: baseClass.myself
	local self:myself = setmetatable(abstract, module) :: any
	return self
end

local dmgUtils  = require(game.ServerScriptService.Utils.DmgUtils)
local dmgFlag   = dmgUtils.dmgFlags
local Targeting = require(game.ServerStorage.ROWA.Modules.Targeting)
local fireVFX   = require(game.ServerStorage.ROWA.Modules.fireVFX)
local hitSfx    = require(game.ServerStorage.ROWA.Modules.hitSfx)

--- BLUE lightning, so the flag is `lightning` and it carries Shock. The yellow
--- pair (BoltPunch, JoltKick) is `magic` and deliberately does not.
local LNING = {
	weight   = dmgUtils.weighEnum.Heavy,
	type     = dmgFlag.lightning,
	dmg      = 16,
	stun     = 1.2,
	--- !! DO NOT remove this again. CalculatePostureDmg is the first line of
	--- HandleAttack and reads `dmg * posMult` unguarded, so a nil posMult throws
	--- into use()'s pcall -- every effect plays and NOBODY IS EVER DAMAGED.
	--- That signature means a dmgTbl field HandleAttack reads unconditionally.
	posMult  = 2,
	onHit    = function(attack)
		hitSfx(attack.enemyEntity.HRootPart, "LightningRelease")
	end,
}

local STRIKE_RANGE = 60
local FX_CHARGE, FX_CANCEL, FX_UP, FX_DOWN = 1, 2, 3, 4

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true

local function useFunc(this:myself)
	local cooldownID = "lightning"
	if this:canTriggerCD(cooldownID) ~= true then return end

	local humObj  = this._humObj
	local hurtbox = humObj.HurtBox
	local char: any = hurtbox.Parent
	local anim = this:PlayAnim(script.Anim, 0, 1, 1)

	fireVFX("lstrike", FX_CHARGE, char)

	if this:feintWait(0.32) then
		if anim then anim:Stop() end
		fireVFX("lstrike", FX_CANCEL, char)
		return
	end

	fireVFX("lstrike", FX_UP, char)

	--[[ the flash-step. ONE module owns both halves -- the hide and the unhide
		0.4s later -- so a dropped second packet cannot leave the caster
		permanently invisible. ]]
	fireVFX("ststep", char, 0.4)

	if this:feintWait(0.4) then
		if anim then anim:Stop() end
		fireVFX("lstrike", FX_CANCEL, char)
		return
	end

	this:useMana()
	this:triggerCD(cooldownID, 14, true)

	--[[ point at whoever is in front, else straight ahead, then raycast so
		the bolt lands on the first thing in the way rather than inside it. ]]
	--- SOFT: no angle limit.
	local target = Targeting.nearestInDirection(
		hurtbox.Position, hurtbox.CFrame.LookVector, humObj, STRIKE_RANGE,
		Targeting.SOFT)

	local dir = hurtbox.CFrame.LookVector
	if target and target.HRootPart then
		dir = (target.HRootPart.Position - hurtbox.Position)
		dir = if dir.Magnitude > 0 then dir.Unit else hurtbox.CFrame.LookVector
	end

	rayParams.FilterDescendantsInstances = { workspace.Effects, char }
	local hit = workspace:Raycast(hurtbox.Position, dir * STRIKE_RANGE, rayParams)
	local endPos = if hit then hit.Position else hurtbox.Position + dir * STRIKE_RANGE
	local origin = CFrame.new(endPos, endPos + dir)

	fireVFX("lstrike", FX_DOWN, char, origin)
	fireVFX("emit", hurtbox, "lvfx3", 20, 1)

	local _, hits = this:hitbox(
		CFrame.new(origin.Position + Vector3.new(0, 1, 0), origin.Position),
		Vector3.new(8, 8, 8), nil, true)

	for _, enemy in pairs(hits) do
		local attack = this:makeAtk(LNING, enemy, Vector3.new(0, 1, 0))
		-- no knockback in the original: the 1.2s stun is the whole effect.
		this:executeAttack(attack)

		if attack:isHit() then
			--[[ Shock marks the BLUE lightning specifically, not the whole
				lightning family. Fulminate was the only source; this is the
				other blue one, so it gets it too. Deliberately NOT given to
				the yellow pair, BoltPunch and JoltKick. ]]
			enemy.statusEffects:apply(enemy.statusEffects.Shock, 3)

			if enemy.HRootPart then
				fireVFX("pauseF2", char, enemy.HRootPart.Parent)
				--- the hit effect goes on the VICTIM, not the caster's emitter.
				fireVFX("emit", enemy.HRootPart, "lvfx3", 20, 1)
			end
		end
	end

	this:endLag(0.2)
end

function module.use(self:myself)
	return baseClass.use(self, useFunc)
end

return table.freeze(module)
