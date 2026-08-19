--!strict
--[[ Cero - rowa1 Items/Ability/Cero. Notes: README.md/PORT_Cero.

	A wide beam cannon. 1.2s charge, then a 15x15x40 lane re-queried four
	times, carving a tunnel through the terrain. The biggest single hit in
	rowa1's table. 				blaze was here

	NOT A PROJECTILE (PLAN_PROJECTILE section 2D). The hitbox never moves:
	rowa1 computes ONE CFrame in front of the caster and re-queries it four
	times at 0.1s, sharing one dedupe list. The four ticks exist to catch
	someone walking into the beam, not to sweep it forward. ]]
local baseClass = require(script.Parent.AbilityBase)
export type myself = baseClass.myself
type humObj = baseClass.humObj

local module = {
	Name = "Cero"
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
local Destruction = require(game.ServerStorage.ROWA.Destruction_Stable.Destruction)

--[[ rowa1 "cero": Heavy, magic, 60 dmg, truestun 0.3 / stun 0.5, posMult 6.
	60 is the highest single hit in the whole table.

	posMult pulled 6 -> 4 for the same reason as StrongerLeft: 6 was tuned
	against a 100 posture pool and rowa2's maxPosture is 80, so 6 x 38 damage
	guard-breaks anything instantly through a block.

	rowa1's row has no sounds and no onHit -- all of Cero's feel is in the
	fx module, which is why this is the one ported ability with a bare
	table. ]]
local CERO = {
	weight   = dmgUtils.weighEnum.Heavy,
	type     = dmgFlag.magic,
	dmg      = 38,
	stun     = 0.5,
	posMult  = 4,
	parryH   = -0.04,
	--- replaces rowa1's `noparrystun` membership for this id.
	stunMeOnParried = 0,
}

local TICKS      = 4
local TICK_RATE  = 0.1
local BEAM_STEPS = 6

local function useFunc(this:myself)
	local cooldownID = "cero"
	if this:canTriggerCD(cooldownID) ~= true then return end

	local humObj  = this._humObj
	local hurtbox = humObj.HurtBox
	local char: any = hurtbox.Parent
	local anim = this:PlayAnim(script.Punch, 0, 1, 1)

	--[[ rowa1 locked the caster into a client hover ("arialControll") for the
		whole charge, but ONLY when already airborne. rowa2 has no such
		module and should not grow one for this: a walkSpeed root reads the
		same on the ground and does not fight network ownership.
		See PORT_Cero step 3. ]]
	humObj.walkSpeed:SetMod(cooldownID, -13)

	local leftArm = char:FindFirstChild("Left Arm")

	local chargeSnd = script["OFA Charge Up Smash SFX"]:Clone()
	chargeSnd.Parent = hurtbox
	chargeSnd:Play()
	game.Debris:AddItem(chargeSnd, 4)

	--[[ rowa1's charge is 8 MIDDLE emitters revealed one every 0.15s, i.e.
		1.2s -- which is exactly the Attacking.Time it declared. One
		feintWait, and the reveal cadence is the fx module's business. ]]
	if this:feintWait(1.2) then
		if anim then anim:Stop(0.1) end
		humObj.walkSpeed:RemoveMod(cooldownID)
		game.Debris:AddItem(chargeSnd, 0)
		return
	end
	humObj.walkSpeed:RemoveMod(cooldownID)

	this:useMana()
	this:triggerCD(cooldownID, 16, true)

	local forward = hurtbox.CFrame.LookVector
	local origin  = hurtbox.Position

	fireVFX("cero", hurtbox.CFrame * CFrame.new(-1, 0, -40), leftArm)
	fireVFX("camShake", origin, 400, 3, 0.3)

	local fireSnd = script["CS:GO Incendiary Grenade/Molotov Extinguish"]:Clone()
	fireSnd.Parent = hurtbox
	fireSnd:Play()
	game.Debris:AddItem(fireSnd, 4)

	--[[ rowa1 called Destruction:Cero SIX times, stepping 12 studs each, to
		fake a tunnel out of overlapping cubes. rowa2 has the shape: ONE
		Cylinder down the lane, which is cheaper and loses the scalloped edge
		the stepped version left. See README S10.4. ]]
	--[[ rowa1 stepped a 16^3 cube SIX times down the lane to fake a tunnel.
		rowa2 has the shape: ONE cylinder, which is cheaper and loses the
		scalloped edge the stepped version left. ]]
	Destruction.Cylinder(nil, origin + Vector3.new(0, 2, 0), forward,
		12 * BEAM_STEPS, 8, 4.8)

	for i = 1, BEAM_STEPS do
		task.spawn(function()
			task.wait(i / 40)
			fireVFX("ceroRing", origin + forward * 12 * i, forward, i)
		end)
	end

	--[[ ONE fixed lane, re-queried. `seen` spans all four ticks exactly as
		rowa1's shared humsH did -- WITHOUT it a target standing in the beam
		eats 38 damage four times. Same trap as Huozai and Freeze; :hitbox
		only dedupes WITHIN one query. ]]
	local cf = CFrame.new(origin + forward * 20, origin + forward * 40)
	local seen: {[number]: boolean} = {}

	for _ = 1, TICKS do
		local _, hits = this:hitbox(cf, Vector3.new(13, 13, 36), nil, true)
		for _, enemy in pairs(hits) do
			if seen[enemy.entityId] then continue end
			seen[enemy.entityId] = true

			local attack = this:makeAtk(CERO, enemy, forward)
			-- rowa1 look*60, at the x0.6 knockback ratio (README S7)
			attack.knockback = this:knockback(attack.atkDir * 36, 0.2, false, -1)
			this:executeAttack(attack)
		end
		task.wait(TICK_RATE)
	end

	this:endLag(0.4)
end

function module.use(self:myself)
	return baseClass.use(self, useFunc)
end

return table.freeze(module)
