--!strict
-- Cero - a wide beam cannon: 1.2s charge, then a fixed lane re-queried four times, carving a tunnel through the terrain.
-- NOT a projectile, the hitbox never moves -- the ticks catch someone walking into the beam, they do not sweep it forward.
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

-- bare table on purpose: all of Cero's feel is in the fx module.
local CERO = {
	weight   = dmgUtils.weighEnum.Heavy,
	type     = dmgFlag.magic,
	dmg      = 30,
	stun     = 0.5,
	posMult  = 4,
	--parryH   = -0.04,
	-- no parry stun for this id.
	stunMeOnParried = 0,
}

local TICKS      = 4
local TICK_RATE  = 0.1
local BEAM_STEPS = 6
-- 8 reveal beats x 0.15s
local CHARGE_TIME = 1.2

local function useFunc(this:myself)
	local cooldownID = "cero"
	if this:canTriggerCD(cooldownID) ~= true then return end

	local humObj  = this._humObj
	local hurtbox = humObj.HurtBox
	local char: any = hurtbox.Parent
	local anim = this:PlayAnim(script.Punch, 0, 1, 1.5)

	-- aerialAim no-ops grounded and on NPCs; THE HOLD OUTLIVES THE CHARGE, so budget the whole move plus a margin.
	local releaseAir = aerialAim(humObj, CHARGE_TIME + TICKS * TICK_RATE + 0.5)

	-- !! NOT a full root: a rooted R6 cannot TURN, and Cero samples its direction at RELEASE, so it has to stay re-aimable. Heavy slow, not a weld.
	humObj.walkSpeed:SetMod(cooldownID, -9)

	local leftArm = char:FindFirstChild("Left Arm")

	local chargeSnd = script["OFA Charge Up Smash SFX"]:Clone()
	chargeSnd.Parent = hurtbox
	chargeSnd:Play()
	game.Debris:AddItem(chargeSnd, 4)

	-- stage 1 PUTS the charge on the hand; the reveal cadence is the fx module's business.
	fireVFX("cero", 1, leftArm, CHARGE_TIME)

	if this:feintWait(CHARGE_TIME) then
		if anim then anim:Stop(0.1) end
		releaseAir()
		humObj.walkSpeed:RemoveMod(cooldownID)
		game.Debris:AddItem(chargeSnd, 0)
		-- drop the charge off the hand, or it hangs there forever
		fireVFX("cero", 0, leftArm)
		return
	end
	humObj.walkSpeed:RemoveMod(cooldownID)

	this:useMana()
	this:triggerCD(cooldownID, 16, true)

	local forward = hurtbox.CFrame.LookVector
	local origin  = hurtbox.Position

	-- stage 2 CONSUMES the charge built on the hand, rather than cloning a second and leaving the first glowing.
	fireVFX("cero", 2, hurtbox.CFrame * CFrame.new(-1, 0, -40), leftArm)
	fireVFX("camShake", origin, 400, 3, 0.3)

	local fireSnd = script["CS:GO Incendiary Grenade/Molotov Extinguish"]:Clone()
	fireSnd.Parent = hurtbox
	fireSnd:Play()
	game.Debris:AddItem(fireSnd, 4)

	-- ONE cylinder down the lane, and NO DEBRIS: a cero deletes a wall rather than shattering it, so only the flying chunks are suppressed. Unsupported geometry still falls.
	Destruction.Cylinder(nil, origin + Vector3.new(0, 2, 0), forward,
		12 * BEAM_STEPS, 8, 4.8, nil, true)

	for i = 1, BEAM_STEPS do
		task.spawn(function()
			task.wait(i / 40)
			fireVFX("ceroRing", origin + forward * 12 * i, forward, i)
		end)
	end

	-- !! ONE fixed lane, re-queried: `seen` spans all four ticks, or a target standing in the beam eats the damage four times. :hitbox only dedupes WITHIN one query.
	local cf = CFrame.new(origin + forward * 20, origin + forward * 40)
	local seen: {[number]: boolean} = {}

	for _ = 1, TICKS do
		local _, hits = this:hitbox(cf, Vector3.new(13, 13, 36), nil, true)
		for _, enemy in pairs(hits) do
			if seen[enemy.entityId] then continue end
			seen[enemy.entityId] = true

			local attack = this:makeAtk(CERO, enemy, forward)
			attack.knockback = this:knockback(attack.atkDir * 36, 0.2, false, -1)
			this:executeAttack(attack)
		end
		task.wait(TICK_RATE)
	end

	-- drop the air lock here, after the last tick.
	releaseAir()

	this:endLag(0.4)
end

function module.use(self:myself)
	return baseClass.use(self, useFunc)
end

return table.freeze(module)
