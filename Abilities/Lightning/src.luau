--!strict
--[[ Lightning - rowa1 Items/Ability/Lightning.
	Notes: README.md/PORT_Lightning.

	Call a bolt down on a target's position. Four staged client effects
	(charge / hold / strike-up / strike-down), a flash-step, and a finisher
	flash on connect.

	NOT A PROJECTILE (PLAN_PROJECTILE 2E): the strike is a delayed
	world-space AoE at a raycast endpoint, nothing travels.

	NOTE the earlier port doc said the hitbox was queried four times. It is
	not -- rowa1's `for i = 1,4` is the WINDUP, 4 x 0.1s, and the hitbox runs
	once. Corrected by reading the source. ]]
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

--[[ rowa1 "lning": Heavy, LIGHTNING, 30 dmg, truestun 0.5 / stun 1.2.
	The flag is `lightning` here and `magic` on BoltPunch/JoltKick -- rowa1
	was inconsistent across its own lightning family. Carried as written so
	the inconsistency stays visible; resolve it in a balance pass. ]]
local LNING = {
	weight   = dmgUtils.weighEnum.Heavy,
	type     = dmgFlag.lightning,
	dmg      = 18,
	stun     = 1.2,
	--posMult  = 1,
	--[[ a targeted, no-travel AoE is unavoidable by construction, so this is
		the ability that most needs rowa2's dodge knob -- rowa1 had no such
		field and leaned entirely on the loud 4-stage telegraph. Both. ]]
	dodgeH   = 0.15,
	parryH   = -0.04,
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

	-- rowa1: 4 x 0.1s, re-checking between each.
	if this:feintWait(0.4) then
		if anim then anim:Stop() end
		fireVFX("lstrike", FX_CANCEL, char)
		return
	end

	fireVFX("lstrike", FX_UP, char)

	--[[ the flash-step. rowa1 fired ststep, waited 0.4, then ststep2 to
		unhide. The merged module owns both halves, so a dropped second
		packet can no longer leave the caster permanently invisible. ]]
	fireVFX("ststep", char, 0.4)

	--[[ 0.48, not 0.4: feintWait subtracts 0.08 on EVERY call, which is
		deliberate for the windup above but wrong for a plain inter-beat
		wait. Chained, the two lost 0.16s and the bolt landed early.
		README S7 note 7f. ]]
	if this:feintWait(0.48) then
		if anim then anim:Stop() end
		fireVFX("lstrike", FX_CANCEL, char)
		return
	end

	this:useMana()
	this:triggerCD(cooldownID, 14, true)

	--[[ point at whoever is in front, else straight ahead, then raycast so
		the bolt lands on the first thing in the way rather than inside it. ]]
	--- rowa1 used GetNearestInDirection3: the SOFT preset, no angle limit.
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
				other blue one, so it gets it too. rowa1 had no such status --
				it is a rowa2 addition, and it is deliberately NOT given to
				BoltPunch/JoltKick (which rowa1 flagged `magic` anyway). ]]
			enemy.statusEffects:apply(enemy.statusEffects.Shock, 3)

			if enemy.HRootPart then
				fireVFX("pauseF2", char, enemy.HRootPart.Parent)
				--[[ rowa1 emitted the HIT effect on `selffx` -- the CASTER's
					emitter -- while parenting an unused `hitfx` to the victim.
					A copy-paste slip; the victim never got the effect. Fixed. ]]
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
