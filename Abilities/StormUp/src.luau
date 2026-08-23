--!strict
--- StormUp - a rising lightning spin that launches the victim straight up WITH
--- you. The air-combo opener of the lightning set. rowa1 port: PORT_StormUp.
--- HumObj's automatic air-combo handoff only fires when both parties are
--- ALREADY airborne, and this launches from the ground -- so the handoff is
--- done by hand below, using HumObj's own fields so there is one model.
local baseClass = require(script.Parent.AbilityBase)
export type myself = baseClass.myself
type humObj = baseClass.humObj

local module = {
	Name = "StormUp"
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

--[[ rowa1 "storm": Heavy, lightning, 30 dmg, truestun 0.5 / stun 1.2.
	Note the flag really is `lightning` here, while BoltPunch and JoltKick
	use `magic` for the same fantasy. rowa1 was inconsistent; both are
	carried across as-written so the inconsistency is visible rather than
	quietly resolved. Pick one for the family in a balance pass, not a port. ]]
local STORM = {
	weight   = dmgUtils.weighEnum.Heavy,
	type     = dmgFlag.lightning,
	dmg      = 19,
	stun     = 1.2,
	posMult  = 1,
	parryH   = -0.04,
	onHit    = function(attack)
		hitSfx(attack.enemyEntity.HRootPart, "HardPunchHit", "LightningRelease")
	end,
}

local TARGET_RANGE = 100
--- rowa1 MiniDash((0,1,0) + look/4, 50); bodyForce scales by 5, so 50/5 = 10.
local RISE = 10

--- rowa1's AirCombo:Make, expressed the way HumObj's own onAttacked does it.
local function startAirCombo(me: any, them: any, stun: number)
	local keep = 0.2 + stun
	if them.floating then
		them.floating.Value = keep
		them.targetFloatY.Value = me.HurtBox or me.HRootPart
	end
	if me.floating then
		me.floating.Value = keep
		me.targetFloatY.Value = them.HurtBox or them.HRootPart
	end
end

local function useFunc(this:myself)
	local cooldownID = "stormUp"
	if this:canTriggerCD(cooldownID) ~= true then return end

	local humObj  = this._humObj
	local hurtbox = humObj.HurtBox
	local char: any = hurtbox.Parent
	local anim = this:PlayAnim(script.Anim, 0, 1, 1)

	--[[ targeting is only used to POINT the spin visual and to decide whether
		this is a real launch or a hop. Nil is a normal outcome, not a bail. ]]
	--- rowa1 used GetNearestInDirection3: the SOFT preset, no angle limit.
	local target = Targeting.nearestInDirection(
		hurtbox.Position, hurtbox.CFrame.LookVector, humObj, TARGET_RANGE,
		Targeting.SOFT)

	if target then
		fireVFX("phantom", char, char.PrimaryPart and char.PrimaryPart.CFrame or hurtbox.CFrame)
	end

	--[[ rowa1 passed Char.Attacking -- a BoolValue on the character -- so the
		client knew when to stop spinning. THAT INSTANCE DOES NOT EXIST IN
		ROWA2 (README S5 step 7b). The quiver module takes a duration. ]]
	--[[ !! HRootPart, NOT HurtBox. shockspin hangs an AlignPosition off this
		part to DRAG the caster onto the target across the windup -- that pull
		is what makes StormUp a gap-closer rather than a whiff at range.
		The HurtBox is a massless query volume; constraining it moves nothing,
		so passing it silently disabled the tracking while every visual still
		played. Hitboxes are HurtBox-relative, physics is HRootPart. ]]
	local leftArm = char:FindFirstChild("Left Arm")
	fireVFX("shockspin", humObj.HRootPart, leftArm, 0.8, target and target.HRootPart)

	if this:feintWait(0.12) then
		if anim then anim:Stop(0.1) end
		return
	end

	fireVFX("shockspin2", hurtbox)

	if this:feintWait(0.4) then
		if anim then anim:Stop(0.1) end
		return
	end

	fireVFX("camShake", hurtbox.Position, 200, 0.4, 0.2)

	if this:feintWait(0.2) then
		if anim then anim:Stop(0.1) end
		return
	end

	this:useMana()
	this:triggerCD(cooldownID, 12, true)

	--[[ no target: rowa1 just hopped and ended, with NO attack at all. Kept --
		it is what makes a whiffed StormUp a mobility option rather than a
		punish. ]]
	if target == nil then
		this:bodyForce(Vector3.new(0, 1, 0).Unit * RISE + Vector3.new(0, 0, -RISE / 4), 0.35, true)
		this:endLag(0.2)
		return
	end

	--[[ rowa1 raycast to the MIDPOINT between caster and target and put the
		box at the impact, so the launch catches someone standing behind cover
		at the right spot rather than at the caster's feet. ]]
	local origin = (hurtbox.Position + target.HRootPart.Position) / 2
	local forward = hurtbox.CFrame.LookVector
	local cf = CFrame.new(origin + forward * 5, origin + forward * 10)
	local _, hits = this:hitbox(cf, Vector3.new(8, 8, 8), nil, true)

	local parried = false
	for _, enemy in pairs(hits) do
		local attack = this:makeAtk(STORM, enemy, Vector3.new(0, 1, 0))
		--[[ isRootRelative TRUE and mostly vertical: rowa1 look*2 + (0,18,0),
			at the x0.6 knockback ratio (README S7) = look*1.2 + (0,10.8,0). ]]
		attack.knockback = this:knockback(
			Vector3.new(0, 10.8, -1.2), 0.25, true, -1)
		this:executeAttack(attack)

		if attack:isParried() then
			parried = true
		elseif attack:isHit() or attack:isBlocked() then
			startAirCombo(humObj, enemy, STORM.stun)
		end
	end

	--[[ a parry cancels the caster's own follow-up: no burst, no shake, no
		rise. That asymmetry is the parry reward and it is worth keeping. ]]
	if not parried then
		fireVFX("messySpinShock",
			hurtbox.Position + forward * 2 + Vector3.new(0, 10, 0))
		fireVFX("camShake", hurtbox.Position, 400, 2, 0.2)
		this:bodyForce(Vector3.new(0, 1, 0).Unit * RISE + Vector3.new(0, 0, -RISE / 4), 0.35, true)
	end

	this:endLag(0.25)
end

function module.use(self:myself)
	return baseClass.use(self, useFunc)
end

return table.freeze(module)
