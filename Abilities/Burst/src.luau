--!strict
-- Burst - light a fireball on your fist and CHARGE; anyone you run through is welded to the ball and dragged along until it detonates.
-- the dash IS the move, it grabs continuously over 13 ticks, and it only detonates IF SOMEONE WAS CAUGHT -- a whiffed Burst is just a dash.
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

-- posMult 5: still a guard breaker, but not a two-touch break off a move that can catch you repeatedly.
local BRST1 = {
	weight   = dmgUtils.weighEnum.Medium,
	-- the blunt half only picks the block sound (resolution/resolveBlock), nothing else.
	type     = bit32.bor(dmgFlag.fire, dmgFlag.blunt),
	dmg      = 4,
	stun     = 1,
	posMult  = 5,
	-- positive: a wide telegraphed charge, so it is meant to be parryable
	parryH   = 0.1,
	stunMeOnParried = 0,
	onHit    = function(attack)
		hitSfx(attack.enemyEntity.HRootPart, "grab")
	end,
}

-- the detonation.
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
-- !! the call site passes decayT, so this ramps down and the charge reaches its own detonation at ~a third of launch speed. Left as-is deliberately.
local RUSH_FORCE = 20
local RUSH_TIME  = 0.7
-- budgeted so a long rush cannot shred the whole map
local BREAK_BUDGET = 24
-- the burn applied by the detonation
local BURN_TIME, BURN_DMG = 6, 3

-- !! 12 keeps this above the forceMag >= 60 scenery gate after Knockback's x5; the (0,5,0) lift stops stopOnGround ending the ragdoll instantly.
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

	-- windup, then the shockwave, then 0.2 more
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

	-- !! DO NOT set isRootRelative false here: it also arms knockBreakStuff, and at forceMag 120 you would tunnel through the scenery instead of being stopped by it.
	local rush = this:bodyForce(Vector3.new(0, 0, -RUSH_FORCE), RUSH_TIME, true, RUSH_TIME, 0.5)

	-- the flames streaming off the fist for the length of the rush.
	fireVFX("igniteBall", 2, rightArm, RUSH_TIME)

	local caught: {any} = {}
	local seen: {[number]: boolean} = {}
	local breakCount = 0

	local plr = if humObj.plrObj then humObj.plrObj.Plr else nil
	for i = 1, TICKS do
		if humObj:inStun() then break end
		-- a feint past the commit is an EARLY DETONATE, not a cancel: mana and the cd are already spent. Still costs feint2, so it is a real choice.
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

		-- the trench: a CYLINDER carves the run in one call and leaves a continuous trench rather than separate pits. Budgeted, see BREAK_BUDGET.
		if breakCount < BREAK_BUDGET then
			Destruction.Cylinder(plr,root.Position + forward * 3 + Vector3.new(0, 2, 0),
				-- velo is studs/SECOND, thrown along the rush
				forward, 12, 3.5, 4, forward * 45)
			breakCount += 1
		end

		-- the catch box CLOSES as the rush goes on, so it sweeps people onto the ball rather than pushing them ahead of it.
		local reach = 9 - i / 3
		local _, hits = this:hitbox(CFrame.new(0, 0, -reach), Vector3.new(5, 5, 6))

		for _, enemy in pairs(hits) do
			if seen[enemy.entityId] then continue end
			seen[enemy.entityId] = true

			local attack = this:makeAtk(BRST1, enemy, forward)
			this:executeAttack(attack)

			if attack:isHit() and enemy.grab then
				-- !! stuck to the ARM not the root, with a PURE ROTATION: the arm is already out front holding the ball, so translating on top shoves them into space. maxTime is a dead-man switch.
				enemy.grab:grab(humObj,
					CFrame.Angles(math.rad(90), 0, math.rad(180)), 2, rightArm)
				-- TRUE stun for the ride: :Stun alone is refused under hyper armour, so an armoured victim rides it swinging. Guarded, not in Combatant.
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

	-- only detonates if the rush actually caught someone
	if #caught == 0 then
		fireVFX("igniteBall", 0)
		this:endLag(0.25)
		return
	end

	fireVFX("igniteBall", 3)
	-- consume a feint that lands in the TAIL so it cannot leak into the next action, then detonate anyway.
	this.isFeinted = false
	
	fireVFX("burstRing", humObj.HRootPart, true)

	if anim then anim:Stop() end
	this:PlayAnim(script.Blast, 0, 1, 1)
	-- an IMPULSE, not a held force
	this:bodyForce(Vector3.new(0, 0, -12), 0.1, true)

	local forward = hurtbox.CFrame.LookVector
	local blastBox, blast = this:hitbox(CFrame.new(0, 0, -5), Vector3.new(9, 9, 9))

	-- everyone dragged is in the blast BY IDENTITY, not geometry; the box is for BYSTANDERS, since welded victims hang inside its near face.
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
			-- a CAP ended by landing; the release happens BEFORE the attack so the knockback has a free body to push. Guarded, ragdoll is not in Combatant.
			if attack.enemyEntity.ragdoll then
				attack.enemyEntity.ragdoll:ragdoll(60, true, attack.atkDir * 12)
			end
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
