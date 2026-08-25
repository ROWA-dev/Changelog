--!strict
-- Armor - rip the ground up, wear it, and shove everyone off you as it goes on.
-- THE ABILITY IS THE SMALL HALF: damage reduction, erosion, shedding plates and blood suppression all live in Class/StatusEffects/EarthArmour.
-- HOW MUCH GROUND YOU RIP UP IS HOW MUCH ARMOUR YOU GET, and the plates ARE the ground -- nine real carved chunks keeping their own colour and material.
local baseClass = require(script.Parent.AbilityBase)
export type myself = baseClass.myself
type humObj = baseClass.humObj

local module = {
	Name = "Armor",
	-- 40% of a bar against the 100 maxMana pool.
	manaUse = 40,
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
local statusEffects = require(game.ServerStorage.ROWA.Class.StatusEffects)
local Destruction = require(game.ServerStorage.ROWA.Destruction_Stable.Destruction)
local hitSfx = require(game.ServerStorage.ROWA.Modules.hitSfx)

-- pure shove: BOTH stuns are 0 on purpose, so it buys space rather than a combo.
local KNOCK = {
	weight   = dmgUtils.weighEnum.Heavy,
	type     = dmgFlag.blunt,
	dmg      = 13,
	stun     = 0,
	truestun = 0,
	posMult  = 4,
	onHit    = function(attack)
		hitSfx(attack.enemyEntity.HRootPart, "HardPunchHit")
	end,
}

local WINDUP = 0.7

-- !! the real shape is a 10-RADIUS SPHERE; an OBB cannot express one, so query the box and reject the corners. Taking the box as-is is ~3x the volume.
local BOX_SIZE  = Vector3.new(20, 20, 20)
local RADIUS    = 10
local MAX_HITS  = 10

-- an ELLIPSOID, not a sphere: Y is flattened to 64% of XZ.
-- !! FULL EXTENT, NOT RADII -- Destruction halves this itself, so passing radii digs a crater half the size.
local DIG_SIZE = Vector3.new(16.5, 10.5, 16.5)
-- !! scaled off the SHORT radius, not the long one: this dig is FLATTENED, so scaling off the long axis terminates subdivision vertically and starves Grab of chunks.
local DIG_MINSZ = 3
-- NINE, not five: the chunks CYCLE across a five-plate rig, so most plates get two converging pieces. That overlap reads as rubble collapsing onto you.
local GRAB_COUNT = 9

-- nine chunks is a full suit.
local POOL_PER_PIECE = 12
local POOL_MIN, POOL_MAX = 20, 100
local ARMOUR_TIME = 30

local function useFunc(this:myself)
	local cooldownID = "armor"
	if this:canTriggerCD(cooldownID) ~= true then return end

	local humObj  = this._humObj
	local hurtbox = humObj.HurtBox
	local root    = humObj.HRootPart
	local anim    = this:PlayAnim(script.Anim, 0, 1, 1)

	-- the slam beat inside this lands exactly when the windup ends
	fireVFX("armorShock", root, WINDUP)

	local SLOW_KEY = "armor"
	humObj.walkSpeed:SetMod(SLOW_KEY, -100)
	
	if this:feintWait(WINDUP) then
		if anim then anim:Stop(0.1) end
		humObj.walkSpeed:RemoveMod(SLOW_KEY)
		return
	end

	humObj.walkSpeed:RemoveMod(SLOW_KEY)
	
	this:useMana()
	this:triggerCD(cooldownID, 40, true)

	local origin = hurtbox.Position

	-- dig FIRST: the pieces decide how much armour there is and what colour, so the suit and the shove land together.
	-- Grab hands back a DESCRIPTION of the chunks and withholds them from dbri; DATA, NOT PARTS, since server-owned parts converging would stutter for everyone but the host.
	local _, chunks = Destruction.Grab(
		nil,
		CFrame.new(origin),
		DIG_SIZE,
		DIG_MINSZ,
		nil,
		GRAB_COUNT
	)

	-- the pool is really "how many chunks did I actually get": bare floor gives scraps, open rock gives a full suit.
	local pool = math.clamp(#chunks * POOL_PER_PIECE, POOL_MIN, POOL_MAX)

	humObj.statusEffects:apply(
		statusEffects.EarthArmour,
		ARMOUR_TIME,
		pool,
		chunks
	)

	fireVFX("camShake", origin, 400, 1, 0.1)

	-- query the box, then reject anything outside the real 10-stud sphere
	local _, hits = this:hitbox(
		CFrame.new(origin),
		BOX_SIZE,
		nil,
		true -- world space
	)

	local landed = 0
	for _, enemy in pairs(hits) do
		if landed >= MAX_HITS then break end

		local eroot = enemy.HRootPart
		if eroot == nil then continue end

		local offset = eroot.Position - origin
		if offset.Magnitude > RADIUS then continue end

		-- the shove is deliberately FLAT and the lift comes from the +Y: a radial-in-3D version launches whoever stands on top of you and nobody else.
		local flat = Vector3.new(offset.X, 0, offset.Z)
		local dir = if flat.Magnitude > 0 then flat.Unit else hurtbox.CFrame.LookVector

		local attack = this:makeAtk(KNOCK, enemy, dir)

		-- decayT -1: no linear decay, so there is no snap-back at the end of the shove.
		attack.knockback = this:knockback(
			dir * 24 + Vector3.new(0, 5, 0),
			0.1,
			false,
			-1
		)

		this:executeAttack(attack)
		if attack:isHit() then
			attack.enemyEntity.ragdoll:ragdoll(60, true, attack.atkDir * 10)
		end
		landed += 1
	end

	-- 0.5 keeps this a commitment without freezing you.
	this:endLag(0.5)
end

function module.use(self:myself)
	return baseClass.use(self, useFunc)
end

return table.freeze(module)
