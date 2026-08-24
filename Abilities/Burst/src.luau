--!strict
--- Burst - light a fireball on your fist and CHARGE. Anyone you run through is
--- welded to the ball and dragged along, carving a trench, until it detonates.
--- rowa1 port: README.md/PORT_Burst (which calls it a grab-then-detonate; it is
--- not -- the dash IS the move and it grabs continuously over 13 ticks).
--- The detonation only happens IF SOMEONE WAS CAUGHT. A whiffed Burst is a dash.
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

--- rowa1 posMult 10 (the highest in its table) at 4 dmg is half a rowa2 guard
--- bar off a move that can catch you repeatedly. Cut to 5: still a breaker,
--- no longer a two-touch break.
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
--- rowa1 held 120 studs/s FLAT for 0.6s, so 120/5 = 24.
--- !! but the call site passes decayT, so bodymover ramps this down and the
--- charge reaches its own detonation at ~a third of launch speed. Left as-is
--- deliberately: removing the decay is a real speed change and wants its own pass.
local RUSH_FORCE = 20
local RUSH_TIME  = 0.7
--- rowa1 budgets its carving so a long rush cannot shred the whole map
local BREAK_BUDGET = 24
--- the burn rowa1 hardcoded in the resolver for brst2
local BURN_TIME, BURN_DMG = 6, 3

--- !! 12, not the straight x0.6 of rowa1's 17. rowa1 only ran its
--- smash-through-the-scenery pass above `pow > 16` and brst2 sat one unit over
--- that gate on purpose; rowa2's equivalent gate is forceMag >= 60 after
--- Knockback's x5, so 10.2 landed silently just under it. The (0,5,0) lift
--- stops stopOnGround ending the ragdoll instantly. decayT -1 = flat, safe
--- because nothing follows the blast.
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
	if this:feintWait(0.42) then
		if anim then anim:Stop() end
		fireVFX("igniteBall", 0)
		return
	end

	fireVFX("burstRing", humObj.HRootPart, false)

	if this:feintWait(0.2) then
		if anim then anim:Stop() end
		fireVFX("igniteBall", 0)
		return
	end

	this:useMana()
	this:triggerCD(cooldownID, 12, true)

	--- !! DO NOT set isRootRelative false here to get a world-fixed line. It
	--- reads like a direction flag but it also arms knockBreakStuff, which only
	--- escapes on `isRootRelative` or forceMag < 60 -- this is 24, x5 = 120. You
	--- would tunnel through the scenery instead of being stopped by it.
	--- The steering is a known open gap, not something to fix by toggling this.
	local rush = this:bodyForce(Vector3.new(0, 0, -RUSH_FORCE), RUSH_TIME, true, RUSH_TIME, 0.5)

	--- the flames streaming off the fist for the length of the rush.
	fireVFX("igniteBall", 2, rightArm, RUSH_TIME)

	local caught: {any} = {}
	local seen: {[number]: boolean} = {}
	local breakCount = 0

	local plr = if humObj.plrObj then humObj.plrObj.Plr else nil
	for i = 1, TICKS do
		if humObj:inStun() then break end
		--- a feint past the commit is an EARLY DETONATE, not a cancel: mana and
		--- the cd are already spent and someone may be welded on. Still costs
		--- feint2, so it is a real choice. The cancel puff fires on a WHIFF only.
		if this.isFeinted then
			this.isFeinted = false
			humObj.cooldowns:trigger("feint2")
			if #caught == 0 then
				fireVFX("feintfx", char)
			end
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
			Destruction.Cylinder(plr,root.Position + forward * 3 + Vector3.new(0, 2, 0),
				--- velo is studs/SECOND, thrown along the rush
				forward, 12, 3.5, 4, forward * 45)
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
				--[[ !! STUCK TO THE ARM, not the root, so they ride ahead of the
					caster on the fireball rather than clipping through their
					chest (the ball is client-side, the arm is its anchor).
					maxTime is a dead-man switch -- a Burst that errors mid-rush
					must not leave someone stuck to a player. ]]
				--[[ PURE ROTATION, no translation. The anchor part IS the
					position -- the arm is already out in front holding the
					ball, so translating on top of it shoves them into space.
					rowa1: C0 = CFrame.Angles(90, 0, 180), which lays them
					flat across the fist. ]]
				enemy.grab:grab(humObj,
					CFrame.Angles(math.rad(90), 0, math.rad(180)), 2, rightArm)
				--[[ TRUE stun for the ride: :Stun alone is refused under hyper
					armour, so an armoured victim rode the fireball swinging.
					Duration is what is left of the rush; the blast's own stun
					takes over. GUARDED: not in the Combatant contract. ]]
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
	--[[ a feint that lands in the TAIL -- on the last tick, or during the
		task.wait after it -- misses the branch above and used to fall into a
		`return` here, which ate the whole detonation after the rush had
		already paid for it. Same rule as above: consume the flag so it cannot
		leak into the next action, then blow up anyway. ]]
	this.isFeinted = false
	
	fireVFX("burstRing", humObj.HRootPart, true)

	if anim then anim:Stop() end
	this:PlayAnim(script.Blast, 0, 1, 1)
	--- rowa1 MiniDash2(look, 60, 0.1): an IMPULSE, so the full /5 applies
	this:bodyForce(Vector3.new(0, 0, -12), 0.1, true)

	local forward = hurtbox.CFrame.LookVector
	local blastBox, blast = this:hitbox(CFrame.new(0, 0, -5), Vector3.new(9, 9, 9))

	--- everyone dragged is in the blast BY IDENTITY, not geometry -- the box is
	--- for BYSTANDERS. Re-finding welded victims is what made the detonation
	--- whiff: they hang at ~0 and the box's near face is 0.5 studs in front.
	--- `seen` is reused, not reallocated: it already holds every id the rush touched.
	table.clear(seen)
	for _, enemy in pairs(blast) do
		seen[enemy.entityId] = true
	end
	for _, enemy in ipairs(caught) do
		if enemy.isActive == true and not seen[enemy.entityId] then
			seen[enemy.entityId] = true
			table.insert(blast, enemy)
		end
	end

	for _, enemy in pairs(blast) do
		local attack = this:makeAtk(BRST2, enemy, forward)
		attack.hitbox = blastBox
		attack.knockback = this:knockback(BLAST_KB(attack.atkDir), 0.1, false, -1)
		this:executeAttack(attack)

		if attack:isHit() then
			--- a CAP ended by landing. The release happens BEFORE the attack
			--- (above) so the knockback has a free body to push. Guarded:
			--- `ragdoll` is not in the Combatant contract, and use()'s pcall would
			--- silently eat the burn, the remaining victims and the endLag.
			if attack.enemyEntity.ragdoll then
				attack.enemyEntity.ragdoll:ragdoll(60, true, attack.atkDir * 12)
			end
			--- rowa1 hardcoded this burn inside the resolver, keyed on the dmgID.
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
