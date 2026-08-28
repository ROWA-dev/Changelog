--!strict
--- DropKick - hop up, then dive at the ground on a diagonal, riding the kick
--- until you hit something or the floor. rowa1 port: README.md/PORT_DropKick.
--- NO GRAB, whatever the doc says: rowa1 requires CharAtkWeld and never calls
--- it. The dive just sweeps a box.
--- It ends on the FIRST of: a collidable surface ahead, entering stun, or an
--- entity in the swept volume -- and which one decides if the landing carves.
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
local Destruction = require(game.ServerStorage.ROWA.Destruction_Stable.Destruction)

--- rowa1 "dropKick": Heavy, magic+blunt, 40 dmg, truestun 0.2 / stun 0.5.
local DROP_KICK = {
	weight   = dmgUtils.weighEnum.Heavy,
	type     = bit32.bor(dmgFlag.magic, dmgFlag.blunt),
	dmg      = 20,
	stun     = 0.5,
	posMult  = 3,
	parryH   = -0.04,
	onHit    = function(attack)
		hitSfx(attack.enemyEntity.HRootPart, "HardPunchHit", "HitCrush")
	end,
}

--[[ rowa1 drove the dive through a CLIENT mover at 90 studs/s -> /5 gives 18.
	The "sustained movers want two thirds" rule does NOT apply: that is for a
	fixed long hold like StoneBall's roll. This ends the moment it hits
	something, so it behaves like an impulse and wants near the full value. ]]
local DIVE_FORCE = 16
local MAX_DIVE   = 2
--[[ the hop only has to get you off the ground -- the dive is the move.
	rowa1's MiniDash(.., 40) converts to 8, but it held for 0.3s and read as
	a long hang before anything happened. Shorter and softer. ]]
local HOP_FORCE  = 10
local HOP_TIME   = 0.1

local diveParams = RaycastParams.new()
diveParams.FilterType = Enum.RaycastFilterType.Exclude
diveParams.IgnoreWater = true

local function useFunc(this:myself)
	local cooldownID = "dropKick"
	if this:canTriggerCD(cooldownID) ~= true then return end

	local humObj  = this._humObj
	local now = tick()

	if now < humObj.stun.Value + 0.4 then -- cant use 0.4s after stun
		return
	end

	if now < humObj._lastBlocked + 0.4 then -- 0.4s
		return
	end
	
	local hurtbox = humObj.HurtBox
	local char: any = hurtbox.Parent
	local first = this:PlayAnim(script.First, 0, 1, 1.2)

	--- the hop. Root-relative so it follows your facing.
	local hop = this:bodyForce(
		(Vector3.new(0, 1, 0) + Vector3.new(0, 0, -0.25)).Unit * HOP_FORCE,
		HOP_TIME, true)

	if this:feintWait(0.34) then
		if first then first:Stop() end
		if hop then hop:destroy() end
		return
	end
	
	first:AdjustSpeed(1)

	fireVFX("dropKickCharge", char:FindFirstChild("Right Leg"), 1.5)

	if this:feintWait(0.2) then
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

	--- !! A BODY IS NOT THE FLOOR, and this is why the kick missed. A root is
	--- CanCollide + CanQuery in the Default group, so diving AT someone made
	--- THEM the landing surface: the loop broke with `hits` still nil and the
	--- kick carved, played everything and dealt nothing. Entities is excluded so
	--- only world geometry ends the ride; people are answered by the hitbox.
	diveParams.FilterDescendantsInstances = { char, workspace.Effects, workspace.Entities }

	local hits = nil
	local landing = nil
	local started = tick()

	--[[ rowa1 offset the query by velocity/16 -- "blaze likes relative
		position" -- so a fast dive tests where it is ABOUT to be, not where
		it was one frame ago. ]]
	local function sweepAhead(from: BasePart, dir: Vector3)
		local rpos = from.Position + from.AssemblyLinearVelocity / 16
		local cf = CFrame.new(rpos + dir.Unit * 3, rpos + dir.Unit * 6)
		local _, found = this:hitbox(cf, Vector3.new(7,7,7), nil, true)
		return found
	end

	--- fixed-rhythm ride -> BARRAGE PATTERN for the interrupt checks
	while tick() < started + MAX_DIVE do
		task.wait()
		if humObj:inStun() then break end
		root = humObj.HRootPart
		if root == nil then break end

		local dir = root.CFrame.UpVector * -10 + root.CFrame.LookVector * 8

		--[[ PEOPLE ARE ASKED FIRST. They used to be asked second, after the
			surface ray had already broken the loop -- and this ray is 12.8
			studs long against a hop that only clears a few, so on most dives
			the floor answered on the FIRST iteration and the hitbox below
			never ran once. Whoever you are diving at decides the dive, not the
			ground they happen to be standing on. ]]
		local found = sweepAhead(root, dir)
		if #found > 0 then
			hits = found
			break
		end

		local result = workspace:Raycast(root.Position, dir, diveParams)
		if result and result.Instance and result.Instance.CanCollide then
			landing = result
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
		--- rowa1 SmallBreak2 cut with a 7^3 cube; r3.5 is its inscribed sphere
		Destruction.Sphere(nil, origin, 3.5, 2.1, dir * 40)
	end
	fireVFX("dropKickLand", origin, dir)

	--[[ THE IMPACT ITSELF STILL SWINGS: the loop leaves `hits` nil on a
		landing, so without this a kick slammed down next to someone did
		nothing. Lifted 2 studs to cover a standing target's body rather than
		being buried in the floor it just cratered. ]]
	if hits == nil and not humObj:inStun() then
		local _, found = this:hitbox(
			CFrame.new(origin + Vector3.new(0, 2, 0)),
			Vector3.new(7, 7, 7), nil, true)
		if #found > 0 then hits = found end
	end

	if hits and not humObj:inStun() then
		for _, enemy in pairs(hits) do
			local attack = this:makeAtk(DROP_KICK, enemy, dir)
			-- rowa1 dir.Unit*50, at the x0.6 knockback ratio (README S7)
			attack.knockback = this:knockback(dir * 20, 0.2, false, -1)
			this:executeAttack(attack)
			if attack:isHit() then
				attack.enemyEntity.ragdoll:ragdoll(60, true, attack.atkDir*10)
			end
		end
		
		this:endLag(0.25)
	else -- miss
		this:endLag(0.4)
	end
end

function module.use(self:myself)
	return baseClass.use(self, useFunc)
end

return table.freeze(module)
