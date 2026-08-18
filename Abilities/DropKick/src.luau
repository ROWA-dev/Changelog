--!strict
--[[ DropKick - rowa1 Items/Ability/DropKick. Notes: README.md/PORT_DropKick.

	Hop up, then dive at the ground on a diagonal, riding the kick until you
	hit something or the floor. Whatever you land on takes it.

	!! NO GRAB. The port doc said "catch someone in the air, ride them into
	the ground" and listed grab semantics as a blocker. rowa1 REQUIRES
	CharAtkWeld at the top of the file and then NEVER CALLS IT -- the require
	is dead. There is nothing to weld; the dive simply sweeps a box.

	The dive ends on the FIRST of: a collidable surface ahead, entering stun,
	or an entity in the swept volume. Whichever it was decides whether the
	landing carves terrain. ]]
local baseClass = require(script.Parent.AbilityBase)
export type myself = baseClass.myself
type humObj = baseClass.humObj

local module = {
	Name = "DropKick"
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
local fireVFX  = require(game.ServerStorage.ROWA.Modules.fireVFX)
local hitSfx   = require(game.ServerStorage.ROWA.Modules.hitSfx)
local destruct = require(game.ServerStorage.ROWA.Modules.rowa1Destruct)

--- rowa1 "dropKick": Heavy, magic+blunt, 40 dmg, truestun 0.2 / stun 0.5.
local DROP_KICK = {
	weight   = dmgUtils.weighEnum.Heavy,
	type     = bit32.bor(dmgFlag.magic, dmgFlag.blunt),
	dmg      = 26,
	stun     = 0.5,
	posMult  = 3,
	parryH   = -0.04,
	onHit    = function(attack)
		hitSfx(attack.enemyEntity.HRootPart, "HardPunchHit", "HitCrush")
	end,
}

--[[ rowa1 drove the dive through a CLIENT mover at 90 studs/s -> the /5
	conversion gives 18.

	An earlier pass applied the "sustained movers want two thirds" rule and
	used 12, but that rule is for something held for a FIXED long duration
	like StoneBall's one-second roll. This dive ends the moment it hits
	SOMETHING, usually well under half a second, so it behaves like an
	impulse and wants the full converted value. At 12 the fall was visibly
	floaty. ]]
local DIVE_FORCE = 18
local MAX_DIVE   = 1.2
--[[ the hop only has to get you off the ground -- the dive is the move.
	rowa1's MiniDash(.., 40) converts to 8, but it held for 0.3s and read as
	a long hang before anything happened. Shorter and softer. ]]
local HOP_FORCE  = 6.5
local HOP_TIME   = 0.18

local diveParams = RaycastParams.new()
diveParams.FilterType = Enum.RaycastFilterType.Exclude
diveParams.IgnoreWater = true

local function useFunc(this:myself)
	local cooldownID = "dropKick"
	if this:canTriggerCD(cooldownID) ~= true then return end

	local humObj  = this._humObj
	local hurtbox = humObj.HurtBox
	local char: any = hurtbox.Parent
	local first = this:PlayAnim(script.First, 0, 1, 1)

	--- the hop. Root-relative so it follows your facing.
	local hop = this:bodyForce(
		(Vector3.new(0, 1, 0) + Vector3.new(0, 0, -0.25)).Unit * HOP_FORCE,
		HOP_TIME, true)

	if this:feintWait(0.42) then
		if first then first:Stop() end
		if hop then hop:destroy() end
		return
	end

	fireVFX("dropKickCharge", char:FindFirstChild("Right Leg"), 1.5)

	--- +0.08: every feintWait after the first needs it back (README S7 7f)
	if this:feintWait(0.28) then
		if first then first:Stop() end
		fireVFX("dropKickCharge", nil, 0)
		return
	end

	this:useMana()
	this:triggerCD(cooldownID, 10, true)

	if first then first:Stop() end
	local loopAnim = this:PlayAnim(script.loop, 0, 1, 1)

	local root = humObj.HRootPart
	--- down and forward: rowa1's dir was UpVector*-10 + LookVector*8
	local dive = this:bodyForce(Vector3.new(0, -1.2, -1).Unit * DIVE_FORCE, MAX_DIVE, true)

	diveParams.FilterDescendantsInstances = { char, workspace.Effects }

	local hits = nil
	local landing = nil
	local started = tick()

	--- fixed-rhythm ride -> BARRAGE PATTERN for the interrupt checks
	while tick() < started + MAX_DIVE do
		task.wait()
		if humObj:inStun() then break end
		root = humObj.HRootPart
		if root == nil then break end

		local dir = root.CFrame.UpVector * -10 + root.CFrame.LookVector * 8
		local result = workspace:Raycast(root.Position, dir, diveParams)
		if result and result.Instance and result.Instance.CanCollide then
			landing = result
			break
		end

		--- rowa1 offset the query by velocity/16 -- "blaze likes relative
		--- position" -- so a fast dive tests where it is ABOUT to be
		local rpos = root.Position + root.AssemblyLinearVelocity / 16
		local cf = CFrame.new(rpos + dir.Unit * 3, rpos + dir.Unit * 6)
		local _, found = this:hitbox(cf, Vector3.new(6, 6, 6), nil, true)
		if #found > 0 then
			hits = found
			break
		end
	end

	if dive then dive:destroy() end
	if loopAnim then loopAnim:Stop(0.1) end
	fireVFX("dropKickCharge", nil, 0)

	root = humObj.HRootPart
	local origin = if landing then landing.Position
		elseif root then root.Position
		else hurtbox.Position
	local dir = if root then (root.CFrame.UpVector * -10 + root.CFrame.LookVector * 8).Unit
		else Vector3.new(0, -1, 0)

	if landing then
		-- rowa1 Destruction:SmallBreak2, CUTTER_SIZE 7^3 -> Sphere r 3.5
		destruct.smallBreak2(origin, dir * 40)
	end
	fireVFX("dropKickLand", origin, dir)

	if hits and not humObj:inStun() then
		for _, enemy in pairs(hits) do
			local attack = this:makeAtk(DROP_KICK, enemy, dir)
			-- rowa1 dir.Unit*50, at the x0.6 knockback ratio (README S7)
			attack.knockback = this:knockback(dir * 30, 0.2, false, -1)
			this:executeAttack(attack)
		end
	end

	this:endLag(0.25)
end

function module.use(self:myself)
	return baseClass.use(self, useFunc)
end

return table.freeze(module)
