--!strict
--- Cero - a wide beam cannon. 1.2s charge, then a 15x15x40 lane re-queried
--- four times, carving a tunnel through the terrain. rowa1's biggest hit.
--- rowa1 port: README.md/PORT_Cero.
--- NOT a projectile: the hitbox never moves. One CFrame in front of the caster,
--- re-queried four times at 0.1s on one dedupe list -- the ticks catch someone
--- walking into the beam, they do not sweep it forward.
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
local aerialAim = require(game.ServerStorage.ROWA.Modules.aerialAim)
local Destruction = require(game.ServerStorage.ROWA.Destruction_Stable.Destruction)

--- rowa1 "cero" was 60 dmg, the highest single hit in its table.
--- posMult 6 -> 4 like StrongerLeft: 6 was tuned against a 100 posture pool and
--- rowa2's max is 80, so it would guard-break instantly through a block.
--- Bare table on purpose -- all of Cero's feel is in the fx module.
local CERO = {
	weight   = dmgUtils.weighEnum.Heavy,
	type     = dmgFlag.magic,
	dmg      = 32,
	stun     = 0.5,
	posMult  = 4,
	--parryH   = -0.04,
	--- replaces rowa1's `noparrystun` membership for this id.
	stunMeOnParried = 0,
}

local TICKS      = 4
local TICK_RATE  = 0.1
local BEAM_STEPS = 6
--- rowa1: 8 MIDDLE emitters x 0.15s, and the declared Attacking.Time agrees
local CHARGE_TIME = 1.2

local function useFunc(this:myself)
	local cooldownID = "cero"
	if this:canTriggerCD(cooldownID) ~= true then return end

	local humObj  = this._humObj
	local hurtbox = humObj.HurtBox
	local char: any = hurtbox.Parent
	local anim = this:PlayAnim(script.Punch, 0, 1, 1.5)

	--[[ AERIAL AIM. rowa1 locked the caster into a client hover
		("arialControll") for the whole cast, but ONLY when already airborne.
		Modules/aerialAim is that, rebuilt -- it no-ops on the ground and on
		NPCs, so there is no branch here, only a destructor to call.

		THE HOLD OUTLIVES THE CHARGE. rowa1 releases at the very END, after
		the last beam tick, not when the beam fires -- so the caster is still
		hanging while the lane resolves. Budget the whole move plus a margin;
		the client self-releases on that ceiling if anything throws. ]]
	local releaseAir = aerialAim(humObj, CHARGE_TIME + TICKS * TICK_RATE + 0.5)

	--[[ !! NOT -13. That was a full root, and a rooted R6 character cannot
		TURN -- AutoRotate only yaws you while you are actually moving -- so
		the beam always fired wherever you happened to be facing when the
		cast started. Cero samples its direction at RELEASE, which is
		pointless if you are physically unable to re-aim during the 1.2s
		charge. Heavy slow, not a weld. (Airborne, the hover above is doing
		the aiming instead and walkSpeed is irrelevant.) ]]
	humObj.walkSpeed:SetMod(cooldownID, -9)

	local leftArm = char:FindFirstChild("Left Arm")

	local chargeSnd = script["OFA Charge Up Smash SFX"]:Clone()
	chargeSnd.Parent = hurtbox
	chargeSnd:Play()
	game.Debris:AddItem(chargeSnd, 4)

	--[[ rowa1's charge is 8 MIDDLE emitters revealed one every 0.15s, i.e.
		1.2s -- which is exactly the Attacking.Time it declared. One
		feintWait, and the reveal cadence is the fx module's business.
		Stage 1 is what actually PUTS it on the hand; without this call the
		whole wind-up was invisible. ]]
	fireVFX("cero", 1, leftArm, CHARGE_TIME)

	if this:feintWait(CHARGE_TIME) then
		if anim then anim:Stop(0.1) end
		releaseAir()
		humObj.walkSpeed:RemoveMod(cooldownID)
		game.Debris:AddItem(chargeSnd, 0)
		--- drop the charge off the hand, or it hangs there forever
		fireVFX("cero", 0, leftArm)
		return
	end
	humObj.walkSpeed:RemoveMod(cooldownID)

	this:useMana()
	this:triggerCD(cooldownID, 16, true)

	local forward = hurtbox.CFrame.LookVector
	local origin  = hurtbox.Position

	--- stage 2 CONSUMES the charge built on the hand, rather than cloning a
	--- second CeroVFX and leaving the first one glowing
	fireVFX("cero", 2, hurtbox.CFrame * CFrame.new(-1, 0, -40), leftArm)
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
	--[[ NO DEBRIS. A cero does not shatter a wall, it deletes one -- rubble
		spraying out of a hole that was burned clean through reads as the
		beam having merely shoved it. The carve still happens and anything
		left unsupported still falls; only the flying chunks are suppressed.
		It is also the widest single carve in the game, so this is the one
		place where drawing nothing is both righter AND cheaper. ]]
	Destruction.Cylinder(nil, origin + Vector3.new(0, 2, 0), forward,
		12 * BEAM_STEPS, 8, 4.8, nil, true)

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

	--- rowa1 drops the air lock here, after the last tick, and only then
	--- clears Attacking
	releaseAir()

	this:endLag(0.4)
end

function module.use(self:myself)
	return baseClass.use(self, useFunc)
end

return table.freeze(module)
