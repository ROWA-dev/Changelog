--!strict
--[[ Rend - a two-beat ground rend: hop, slam, hop higher, slam again. Both
	hits are GROUND-anchored rather than root-anchored, which is why the move
	catches prone and low targets that a normal forward box misses. ]]
local baseClass = require(script.Parent.AbilityBase)
export type myself = baseClass.myself
type humObj = baseClass.humObj

local module = {
	Name = "Rend"
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

--- bodyForce multiplies by 5 internally (Knockback.luau, "scale to make it
--- aproximate to studs"), so these read as studs/second. Guessing them off
--- StrongLeft came out ~20% short and read as "movement feels weak".
local HOP_1 = 40 / 5
local HOP_2 = 50 / 5

--[[ 14 + 14, and beat 1's 1.2s stun GUARANTEES beat 2 -- so this is really a
	single 28 that cannot be interrupted between halves. Price it as one hit,
	not two, and keep the two tables identical unless you mean to split them. ]]
local REND_1 = {
	weight   = dmgUtils.weighEnum.Heavy,
	type     = dmgFlag.blunt,
	dmg      = 14,
	stun     = 1.2,
	posMult  = 2,
	parryH   = -0.04,
	onHit    = function(attack)
		hitSfx(attack.enemyEntity.HRootPart, "HardPunchHit")
	end,
}
local REND_2 = {
	weight   = dmgUtils.weighEnum.Heavy,
	type     = dmgFlag.blunt,
	dmg      = 14,
	stun     = 1.2,
	posMult  = 2,
	onHit    = function(attack)
		hitSfx(attack.enemyEntity.HRootPart, "HardPunchHit")
	end,
}

local HIT_SIZE = Vector3.new(12, 10, 12)
local GROUND_PROBE = 4

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
groundParams.FilterDescendantsInstances = { workspace.Entities, workspace.Effects }
groundParams.IgnoreWater = true

--- drop to the floor so the box sits on the ground.
local function groundUnder(pos: Vector3): Vector3
	local hit = workspace:Raycast(pos, Vector3.new(0, -GROUND_PROBE, 0), groundParams)
	return if hit then hit.Position else pos - Vector3.new(0, 3, 0)
end

local function slam(this: myself, dmgTbl: any, origin: Vector3, forward: Vector3)
	--[[ world-space hitbox. `isRelativeToWorldSpace` is the least-used
		argument on :hitbox and this is one of the two abilities that needs
		it -- the box must sit on the FLOOR, not on the hurtbox. ]]
	local cf = CFrame.new(origin + forward * 6, origin + forward * 12)
	local _, hits = this:hitbox(cf, HIT_SIZE, nil, true)

	--[[ NO KNOCKBACK, deliberately -- the RAGDOLL is the whole reaction. An
		earlier pass invented `atkDir*7 + (0,6,0)` here, which turned a
		ground-pin into a launcher and fought the second beat: you knocked them
		out of the box you were about to slam. ]]
	for _, enemy in pairs(hits) do
		local attack = this:makeAtk(dmgTbl, enemy, forward)
		this:executeAttack(attack)
		if attack:isHit() then
			--- 0.8s flat. See IceBash for why (45, false) meant 45 seconds of
			--- lying there.
			attack.enemyEntity.ragdoll:ragdoll(0.8, false, attack.atkDir * 6)
		end
	end
end

local function useFunc(this:myself)
	local cooldownID = "rend"
	if this:canTriggerCD(cooldownID) ~= true then return end

	local humObj  = this._humObj
	local hurtbox = humObj.HurtBox
	local anim    = this:PlayAnim(script.Anim, 0, 1, 1)

	--- isRootRelative, so the hop is a LOCAL vector. kb/kbd already own the
	--- client-side movers.
	local hop = this:bodyForce(Vector3.new(0, 0.5, -1).Unit * HOP_1, 0.1, true)

	if this:feintWait(0.57) then
		if anim then anim:Stop() end
		if hop then hop:destroy() end
		return
	end

	this:useMana()
	this:triggerCD(cooldownID, 10, true)

	local forward = hurtbox.CFrame.LookVector
	local origin  = groundUnder(hurtbox.Position)

	fireVFX("rend", hurtbox)
	slam(this, REND_1, origin, forward)

	local anim2 = this:PlayAnim(script.Anim2, 0.1, 1, 1)

	--[[ !! THE GAP IS 1.1s, NOT 0.45s -- a fresh window opened AFTER the first
		slam, not an offset from the move's start. The hop fires 0.2s INTO that
		window and lasts 0.4s, leaving ~0.5s of hang before the ground hits.
		That spacing is the move. The two waits below add up to it. ]]
	if this:feintWait(0.2) then
		if anim2 then anim2:Stop() end
		return
	end

	local hop2 = this:bodyForce(Vector3.new(0, 0.3, -1).Unit * HOP_2, 0.4, true)

	if this:feintWait(0.9) then
		if anim2 then anim2:Stop() end
		if hop2 then hop2:destroy() end
		return
	end

	forward = hurtbox.CFrame.LookVector
	origin  = groundUnder(hurtbox.Position)

	fireVFX("rend", hurtbox)
	slam(this, REND_2, origin, forward)

	this:endLag(0.2)
end

function module.use(self:myself)
	return baseClass.use(self, useFunc)
end

return table.freeze(module)
