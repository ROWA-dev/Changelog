--!strict
--[[ ProjTest - a test harness for Class/Projectile, not a real move.

	Fires 2-4 arcing pellets in a spread, each with its own speed, all of
	them dying on the first wall. Nothing here is ported from rowa1; it
	exists to make the projectile system OBSERVABLE:

	  * several projectiles alive at once, from one cast, so the scheduler's
	    flat array and swap-remove get exercised rather than argued about.
	  * a different speed per pellet, which is the cheapest way to see
	    whether the client's drawn copy and the server's maths agree -- if
	    they drift, pellets land visibly apart from where they hit.
	  * stopOnWorld, so "it vanished at the wall" is the pass condition and
	    needs no instrumentation.
	  * Arcing, whose first customer was BoulderKick and which had none at
	    all before that. A slow, high arc is where an integration mismatch
	    shows up worst, so it is the useful case to have on tap.

	It is ALSO the rig for the FullBlue gravity-well work: a black hole that
	drags projectiles needs something cheap to throw at it from a distance,
	repeatedly, from a known heading.

	KEEP IT REGISTERED BUT KEEP IT HONEST -- it is in the ability list only
	because the admin `ability` command skips anything moduleToID cannot
	resolve, so an unregistered module cannot be handed out in game. It has
	no mana cost and a 1 second cooldown on purpose. ]]
local baseClass = require(script.Parent.AbilityBase)
export type myself = baseClass.myself
type humObj = baseClass.humObj

local module = {
	Name = "ProjTest"
}
module.__tostring = baseClass.__tostring
module.__index = module
setmetatable(module, { __index = baseClass })

function module.new(humObj:humObj):myself
	local abstract = baseClass.new(humObj) :: baseClass.myself
	local self:myself = setmetatable(abstract, module) :: any
	return self
end

local dmgUtils   = require(game.ServerScriptService.Utils.DmgUtils)
local dmgFlag    = dmgUtils.dmgFlags
local hitSfx     = require(game.ServerStorage.ROWA.Modules.hitSfx)
local Projectile = require(game.ServerStorage.ROWA.Class.Projectile)

--- deliberately feeble: this is a test rig, not a damage source
local PELLET = table.freeze({
	weight   = dmgUtils.weighEnum.Light,
	type     = dmgFlag.blunt,
	dmg      = 3,
	stun     = 0.15,
	posMult  = 0.5,
	parryH   = 0.1,
	onHit    = function(attack)
		hitSfx(attack.enemyEntity.HRootPart, "HitSound")
	end,
})

--[[ SLOW AND HIGH. 60 studs/s against 45 of drop is a lazy lob you can walk
	under and watch from the side -- which is the entire point, since a
	mismatch between the server's arc and the drawn one is invisible on
	anything fast and flat. ]]
local BASE = table.freeze({
	class       = Projectile.Arcing,
	speed       = 60,
	gravity     = 45,
	maxDistance = 260,
	lifetime    = 6,
	size        = Vector3.new(2, 2, 2),
	dmgTbl      = PELLET,
	pierce      = 1,
	stopOnWorld = true,
	knockbackForce = 3,
	knockbackTime  = 0.15,
	fxId        = "testBall",
})

local MIN_PELLETS, MAX_PELLETS = 2, 4
--- degrees. Yaw spreads the fan, pitch keeps them from sharing one arc.
local SPREAD_YAW, SPREAD_PITCH = 14, 5
--- +/- on `speed`, so no two pellets land together
local SPEED_JITTER = 0.18

local function useFunc(this:myself)
	local cooldownID = "projTest"
	if this:canTriggerCD(cooldownID) ~= true then return end

	local humObj  = this._humObj
	local hurtbox = humObj.HurtBox

	if this:feintWait(0.17) then return end

	this:triggerCD(cooldownID, 1, true)

	local muzzle = hurtbox.CFrame * CFrame.new(0, 1, -3)
	local n = math.random(MIN_PELLETS, MAX_PELLETS)

	for i = 1, n do
		--[[ every pellet gets its OWN config table. The house rule is to
			freeze one at module scope and reuse it (ABILITY_HITBOX_OPTS,
			CRESCENT, BLDR) and that is still right for a single shot -- but
			speed genuinely varies per pellet here, and mutating a shared
			frozen table is both an error and a race with the pellets already
			in the air. Clone, change the one field, hand it over. ]]
		local cfg = table.clone(BASE)
		cfg.speed = BASE.speed * (1 + (math.random() * 2 - 1) * SPEED_JITTER)
		--- re-frozen before it is handed over, as RPG and IceShards do
		table.freeze(cfg)

		--- fan across the spread rather than randomly, so 2 and 4 both read
		local t = if n == 1 then 0 else (i - 1) / (n - 1) * 2 - 1
		local yaw = math.rad(t * SPREAD_YAW)
		local pitch = math.rad(math.random(-SPREAD_PITCH, SPREAD_PITCH))

		this:projectile(cfg, muzzle * CFrame.Angles(pitch, yaw, 0))
	end

	this:endLag(0.2)
end

function module.use(self:myself)
	return baseClass.use(self, useFunc)
end

return table.freeze(module)
