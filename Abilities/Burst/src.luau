--!strict
--[[ Burst - rowa1 Items/Ability/Burst. Notes: README.md/PORT_Burst.

	Light a fireball on your fist and CHARGE. Anyone you run through is
	welded to the ball and dragged along with you, carving a trench, until
	the whole thing detonates.

	!! IT IS A RUSH, NOT A CATCH-THEN-DETONATE. The doc described "catch
	someone in a short-range grab, then a rushing explosion". The grab is not
	a separate beat -- the dash IS the move, and it grabs CONTINUOUSLY: a
	13-tick loop with a hitbox that closes from 9 studs to 5 as you go, so
	victims pile onto the ball as you pass through them.

	The detonation only happens IF SOMEONE WAS CAUGHT. A whiffed Burst is
	just a dash. ]]
local baseClass = require(script.Parent.AbilityBase)
export type myself = baseClass.myself
type humObj = baseClass.humObj

local module = {
	Name = "Burst"
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
local statusEffects = require(game.ServerStorage.ROWA.Class.StatusEffects)
local fireVFX  = require(game.ServerStorage.ROWA.Modules.fireVFX)
local hitSfx   = require(game.ServerStorage.ROWA.Modules.hitSfx)
local Destruction = require(game.ServerStorage.ROWA.Destruction_Stable.Destruction)

--[[ rowa1 "brst1": Medium, fire, 4 dmg, stun 1.0, posMult 10, parryH 0.1.
	posMult 10 is the highest multiplier in rowa1's whole table -- at 4 dmg
	that is 40 posture, HALF a rowa2 guard bar, off a move that can catch
	you repeatedly. Cut to 5. It is still a guard-breaker, which is the
	point; it is no longer a two-touch break. ]]
local BRST1 = {
	weight   = dmgUtils.weighEnum.Medium,
	--- rowa1's row is bor(fire, blunt); the blunt half was dropped on the way
	--- over. It picks the block sound (resolution/resolveBlock), nothing else.
	type     = bit32.bor(dmgFlag.fire, dmgFlag.blunt),
	dmg      = 4,
	stun     = 1,
	posMult  = 5,
	--- positive: it is a wide telegraphed charge and rowa1 wanted it parryable
	parryH   = 0.1,
	stunMeOnParried = 0,
	onHit    = function(attack)
		hitSfx(attack.enemyEntity.HRootPart, "grab")
	end,
}

--- rowa1 "brst2": Heavy, fire+blunt, 26 dmg, truestun 0.4 / stun 0.6.
local BRST2 = {
	weight   = dmgUtils.weighEnum.Heavy,
	type     = bit32.bor(dmgFlag.fire, dmgFlag.blunt),
	dmg      = 17,
	stun     = 0.6,
	posMult  = 3,
	parryH   = -0.04,
	onHit    = function(attack)
		hitSfx(attack.enemyEntity.HRootPart, "HardPunchHit")
	end,
}

local TICKS      = 13
local TICK_RATE  = 0.05
--[[ rowa1 BodyVelocity at 120 studs/s held FLAT for 0.6s, so 120/5 = 24.

	An earlier pass used 16, applying a "sustained movers want two thirds"
	rule -- but that rule came from ONE data point (StoneBall's one-second
	roll) and does not generalise. rowa1 sets a BodyVelocity, which reaches
	its target speed immediately and holds it.

	!! THE CALL SITE DOES NOT DO THAT. It passes decayT = RUSH_TIME+0.2, so
	bodymover scales VectorVelocity by (remaining/decayT)^0.8 every frame and
	the charge arrives at its own detonation on ~a third of its launch speed.
	rowa1 lines 108-120 are flat: Velocity = Dir*120, wait 0.6, MaxForce = 0.
	Left as-is on purpose for now -- removing the decay is a real speed change
	and wants to be felt on its own, not smuggled in with something else.

	rowa1's MaxForce is `abs(Dir) * mass * 10000` -- force only along the
	TRAVEL axes, so gravity is untouched. A root-relative horizontal vector
	is the same thing: bodymover flattens Y when forceVector.Y == 0. ]]
local RUSH_FORCE = 24
local RUSH_TIME  = 0.6
--- rowa1 budgets its carving so a long rush cannot shred the whole map
local BREAK_BUDGET = 24
--- the burn rowa1 hardcoded in the resolver for brst2
local BURN_TIME, BURN_DMG = 6, 3

--[[ THE DETONATION THROW. rowa1 `Knockback(Hum, EnemyHum, look*17)`.

	!! 17 IS NOT AN ARBITRARY NUMBER AND THE STRAIGHT x0.6 CONVERSION THREW
	IT AWAY. rowa1's Knockback only runs its smash-through-the-scenery pass
	-- the ray, the Destruction call, the Shockwave and the CamShake -- when
	`pow > 16`. brst2 sits ONE unit over that gate on purpose: the whole
	read of the finisher is that the explosion puts someone THROUGH
	something. StrongLeft's look*16 is on the other side of the same gate,
	deliberately, so this is a distinction rowa1 was making, not noise.

	rowa2's equivalent gate is knockBreakStuff's `if forceMag < 60 then
	return`, measured AFTER Knockback's x5. So the intent needs |force| >= 12
	and the honest-looking 10.2 landed at 51 -- just under, silently, with
	the entire impact pass never running. That is the missing "recoil".

	The (0,5,0) lift is the launch shape Slayer's finisher and StrongLeft
	both use. Without it the throw is perfectly horizontal, the victim never
	leaves the floor, and RowaRagdoll's stopOnGround ray finds ground the
	instant its 0.5s floor expires -- which is the "why is it not
	ragdolling" failure its own comment records against Divide.

	decayT -1 = flat, no ramp: a throw commits its whole velocity at once
	(StrongLeft's comment). Safe here because nothing follows the blast --
	README 7h's warning is about a launch that has to fall back into a
	FOLLOW-UP hitbox, and this is the last beat. ]]
local function BLAST_KB(atkDir: Vector3): Vector3
	return atkDir * 12 + Vector3.new(0, 5, 0)
end

local function useFunc(this:myself)
	local cooldownID = "burst"
	if this:canTriggerCD(cooldownID) ~= true then return end

	local humObj  = this._humObj
	local hurtbox = humObj.HurtBox
	local char: any = hurtbox.Parent
	local anim = this:PlayAnim(script.Punch, 0, 1, 1)

	local rightArm = char:FindFirstChild("Right Arm")
	fireVFX("igniteBall", 1, rightArm, 2)

	--- rowa1: 0.1 + 0.4 then the shockwave, then 0.2 more
	if this:feintWait(0.5) then
		if anim then anim:Stop() end
		fireVFX("igniteBall", 0)
		return
	end

	fireVFX("burstRing", humObj.HRootPart, false)

	if this:feintWait(0.28) then
		if anim then anim:Stop() end
		fireVFX("igniteBall", 0)
		return
	end

	this:useMana()
	this:triggerCD(cooldownID, 12, true)

	--[[ !! DO NOT SET isRootRelative FALSE HERE TO GET A WORLD-FIXED LINE.

		It reads like a pure direction flag and it is not. Knockback.luau
		spawns knockBreakStuff BEFORE it does anything else, and that module's
		only two escapes are `if isRootRelative then return end` and
		`if forceMag < 60 then return end`. This force is 24, and Knockback
		multiplies by 5 on the way in -> 120. So flipping the flag arms the
		smash pass ON THE CASTER'S OWN ROOT: a shock1 ring at your feet, and a
		FOUR SECOND loop (endt = st + 4, not t) raycasting ahead of you that
		fires destruction.Sphere into whatever the charge is pointed at.
		You tunnel through the scenery instead of being stopped by it.

		Every other sustained mover in the game is root-relative for this
		reason. The two world-vector callers, StrongLeft (6 -> 30) and HitSelf
		(14 -> 70), sit either side of the same gate.

		So the steering is a known, still-open gap, not something to fix by
		toggling this argument -- see the note by the catch loop. ]]
	local rush = this:bodyForce(Vector3.new(0, 0, -RUSH_FORCE), RUSH_TIME, true, RUSH_TIME+0.2)

	--[[ the trailing burn. rowa1 fired this as its own `igniteBFx` id at the
		moment the charge starts moving -- it is the flames you see streaming
		off the fist for the length of the rush, and it was missing. ]]
	fireVFX("igniteBall", 2, rightArm, RUSH_TIME + 0.05)

	local caught: {any} = {}
	local seen: {[number]: boolean} = {}
	local breakCount = 0

	for i = 1, TICKS do
		if humObj:inStun() then break end
		if this.isFeinted then
			this.isFeinted = false
			humObj.cooldowns:trigger("feint2")
			fireVFX("feintfx", char)
			break
		end

		local root = humObj.HRootPart
		if root == nil then break end
		local forward = root.CFrame.LookVector

		--[[ the trench. rowa1 carves at 4, 9, 14 and 19 studs ahead and
			BUDGETS it -- once breakCount passes 80 it stops entirely, which
			is what keeps a full-length rush from shredding a whole arena. ]]
		--[[ the trench. rowa1 fired three separate 7^3 SmallBreaks per tick at
			4, 9 and 14 studs; a CYLINDER carves the same run in one call and
			leaves a continuous trench rather than three pits.
			Still budgeted -- a full-length rush should not shred a whole arena. ]]
		if breakCount < BREAK_BUDGET then
			Destruction.Cylinder(nil,
				root.Position + forward * 3 + Vector3.new(0, 2, 0),
				--- velo is studs/SECOND, thrown along the rush
				forward, 12, 3.5, 2.1, forward * 45)
			breakCount += 1
		end

		--[[ the catch box CLOSES as the rush goes on: 9 studs ahead on the
			first tick down to about 5 on the last, so it sweeps people onto
			the ball rather than pushing them ahead of it. ]]
		local reach = 9 - i / 3
		local _, hits = this:hitbox(CFrame.new(0, 0, -reach), Vector3.new(5, 5, 6))

		for _, enemy in pairs(hits) do
			if seen[enemy.entityId] then continue end
			seen[enemy.entityId] = true

			local attack = this:makeAtk(BRST1, enemy, forward)
			this:executeAttack(attack)

			if attack:isHit() and enemy.grab then
				--[[ !! STUCK TO THE ARM, not the root. rowa1 welds them to
					`igniteballFX` -- the fireball on the fist -- and parents
					the weld there, so they ride ahead of the caster on the
					ball rather than clipping through their chest.
					The ball itself is client-side now, so the ARM is the
					server-side equivalent anchor; it is the same place.
					maxTime is a dead-man switch -- a Burst that errors
					mid-rush must not leave someone stuck to a player. ]]
				--[[ PURE ROTATION, no translation. The anchor part IS the
					position -- the arm is already out in front holding the
					ball, so translating on top of it shoves them into space.
					rowa1: C0 = CFrame.Angles(90, 0, 180), which lays them
					flat across the fist. ]]
				enemy.grab:grab(humObj,
					CFrame.Angles(math.rad(90), 0, math.rad(180)), 2, rightArm)
				--[[ TRUE stun for the ride (ToshiCounter's shape). :Stun alone
					is refused under hyper armour, so an armoured victim rode
					the fireball swinging. Duration is exactly what is left of
					the rush -- they are released the moment it ends, and the
					blast's own stun takes over from there.
					GUARDED: TrueStun is not in the Combatant contract
					(SimpleEntity has no :TrueStun). ]]
				if enemy.TrueStun then
					enemy:TrueStun((TICKS - i) * TICK_RATE)
				end
				table.insert(caught, enemy)
			end
		end

		task.wait(TICK_RATE)
	end

	if rush then rush:destroy() end
	for _, enemy in ipairs(caught) do
		if enemy.grab then enemy.grab:release() end
	end

	--- rowa1 only detonates if the rush actually caught someone
	if #caught == 0 then
		fireVFX("igniteBall", 0)
		this:endLag(0.25)
		return
	end

	fireVFX("igniteBall", 3)
	if this.isFeinted then
		this:endLag(0.1)
		return
	end
	
	fireVFX("burstRing", humObj.HRootPart, true)

	if anim then anim:Stop() end
	this:PlayAnim(script.Blast, 0, 1, 1)
	--- rowa1 MiniDash2(look, 60, 0.1): an IMPULSE, so the full /5 applies
	this:bodyForce(Vector3.new(0, 0, -12), 0.1, true)

	local forward = hurtbox.CFrame.LookVector
	local blastBox, blast = this:hitbox(CFrame.new(0, 0, -5), Vector3.new(9, 9, 9))
	for _, enemy in pairs(blast) do
		local attack = this:makeAtk(BRST2, enemy, forward)
		attack.hitbox = blastBox
		attack.knockback = this:knockback(BLAST_KB(attack.atkDir), 0.2, false, -1)
		this:executeAttack(attack)

		if attack:isHit() then
			--[[ rowa1's onHit is ragdtillground: a CAP ended by landing.
				SAME SHAPE AS Slayer's heavy launch (dmgConfig/launch.luau) --
				both are "carried on a grab, released, then thrown" finishers,
				and both need the release to happen BEFORE the attack (it does,
				above) so the knockback has a free body to push.

				GUARDED like Slayer's is. `ragdoll` is not in the Combatant
				contract -- a SimpleEntity has none -- and AbilityBase.use pcalls
				the whole useFunc, so indexing it raw did not error loudly, it
				silently ate the burn, every remaining victim and the endLag. ]]
			if attack.enemyEntity.ragdoll then
				attack.enemyEntity.ragdoll:ragdoll(60, true, attack.atkDir * 12)
			end
			--[[ rowa1 hardcoded `if dmgID == "brst2" then BurnEnemy(...)`
				INSIDE the resolver. One line at the call site here. ]]
			attack.enemyEntity.statusEffects:apply(
				humObj.statusEffects.Burn, BURN_TIME, BURN_DMG)
		end
	end

	this:endLag(0.3)
end

function module.use(self:myself)
	return baseClass.use(self, useFunc)
end

return table.freeze(module)
