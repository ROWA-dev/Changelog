--!strict
--[[ Blight - rowa1 Items/Ability/Blight. Notes: README.md/PORT_Blight.

	Launch a blinding orb; it travels ~22 studs over 0.3s and detonates in a
	20-stud sphere. Weak damage, wide area, long cooldown -- a zoning poke.

	THE ORB DOES NOT DAMAGE IN FLIGHT. rowa1's travel loop has no hit query in
	it at all; the whole move is one delayed AoE at the end point. So this is
	NOT a projectile (PLAN_PROJECTILE section 2E) and does not wait on that
	class -- the client draws the orb, the server schedules one hitbox. ]]
local baseClass = require(script.Parent.AbilityBase)
export type myself = baseClass.myself
type humObj = baseClass.humObj

local module = {
	Name = "Blight"
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

-- rowa1 "blight": Light, magic, 5 dmg, stun 0.4, posMult 1. Already tiny;
-- kept as-is rather than scaled, because there is nothing to scale.
local BLIGHT = {
	weight   = dmgUtils.weighEnum.Light,
	type     = dmgFlag.magic,
	dmg      = 5,
	stun     = 0.4,
	posMult  = 1,
}

local TRAVEL_TIME  = 0.3
local TRAVEL_DIST  = 22   -- rowa1: 30 steps of a decelerating 1.5..0 stud stride
local BLAST_RADIUS = 20

local function useFunc(this:myself)
	local cooldownID = "blight"
	if this:canTriggerCD(cooldownID) ~= true then return end

	local humObj  = this._humObj
	local hurtbox = humObj.HurtBox
	local anim    = this:PlayAnim(script.Anim, 0, 1, 1)

	if this:feintWait(TRAVEL_TIME) then
		if anim then anim:Stop() end
		return
	end

	--[[ rowa1 took the cooldown BEFORE the windup, so feinting Blight still
		burned all 20 seconds. Every other ability takes it after. Ported as
		the correct behaviour, not the bug. ]]
	this:useMana()
	this:triggerCD(cooldownID, 13, true)

	local origin  = hurtbox.Position
	local forward = hurtbox.CFrame.LookVector
	local endPos  = origin + forward * TRAVEL_DIST

	fireVFX("blightOrb", hurtbox.CFrame, forward, TRAVEL_DIST, TRAVEL_TIME)

	--[[ The detonation OUTLIVES the ability call -- rowa1 cleared Attacking
		before the travel finished and so does this. `:use()` returning does
		not cancel a task.delay, so the behaviour carries over.

		This DOES capture `this`, and that is fine here: 0.3s is far inside the
		ability instance's own lifetime (it lives on the humObj until unequip).
		PLAN_PROJECTILE 3.4's "never hold the ability" rule is about things
		that fly for SECONDS and can outlive an unequip or a death -- a real
		projectile must hold the entity and a frozen table instead.
		The guard below is what makes the short capture safe. ]]
	task.delay(TRAVEL_TIME, function()
		if humObj.isActive ~= true or this._humObj == nil then
			return
		end

		--[[ :hitbox is an OBB and rowa1's GetNear was a SPHERE. Query the
			bounding box, then reject the corners by distance -- three lines,
			versus 8 studs of error at r=20 if you just eyeball a cube. ]]
		local _, hits = this:hitbox(
			CFrame.new(endPos),
			Vector3.one * (BLAST_RADIUS * 2),
			nil,
			true -- world space
		)

		for _, enemy in pairs(hits) do
			local eroot = enemy.HRootPart
			if eroot == nil then continue end
			if (eroot.Position - endPos).Magnitude > BLAST_RADIUS then continue end

			local dir = eroot.Position - endPos
			dir = if dir.Magnitude > 0 then dir.Unit else forward

			local attack = this:makeAtk(BLIGHT, enemy, dir)
			this:executeAttack(attack)
		end
	end)

	this:endLag(0.1)
end

function module.use(self:myself)
	return baseClass.use(self, useFunc)
end

return table.freeze(module)
