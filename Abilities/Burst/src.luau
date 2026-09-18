--!strict
-- Burst - a long active frames lunge and on grab it has a second part where it "bursts away" the grabbed victims
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
-- a feint past the commit RELEASES the charge, so the ball gets a beat to plant instead of going off mid-slide on the input frame.
local FEINT_SETTLE = 0.12
-- !! the call site passes decayT, so this ramps down and the charge reaches its own detonation at ~a third of launch speed. Left as-is deliberately.
local RUSH_FORCE = 20
local RUSH_TIME  = 0.7
-- budgeted so a long rush cannot shred the whole map
local BREAK_BUDGET = 24
local BURN_TIME, BURN_DMG = 6, 3

-- !! 12 keeps this above the forceMag >= 60 scenery gate after Knockback's x5; the (0,5,0) lift stops stopOnGround ending the ragdoll instantly.
local function BLAST_KB(atkDir: Vector3): Vector3
	return atkDir * 12 + Vector3.new(0, 5, 0)
end

-- everyone dragged is in the blast BY IDENTITY, not geometry; the box is for BYSTANDERS, since welded victims hang inside its near face.
local function detonate(this:myself, caught:{any}, seen:{[number]:boolean})
	local humObj = this._humObj
	local forward = humObj.HurtBox.CFrame.LookVector
	local blastBox, blast = this:hitbox(CFrame.new(0, 0, -5), Vector3.new(9, 9, 9))

	table.clear(seen)
	for _, enemy in pairs(blast) do
		seen[enemy.entityId] = true
	end
	-- `caught` is unique by construction, so membership is the only test needed.
	for _, enemy in ipairs(caught) do
		if enemy.isActive == true and not seen[enemy.entityId] then
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
end

local function useFunc(this:myself)
	local cooldownID = "burst"
	if this:canTriggerCD(cooldownID) ~= true then return end

	local humObj  = this._humObj
	local char: any = humObj.HurtBox.Parent
	local anim = this:PlayAnim(script.Punch, 0, 1, 1)

	local rightArm = char:FindFirstChild("Right Arm")
	fireVFX("igniteBall", 1, rightArm, 2)

	local function bail()
		if anim then anim:Stop() end
		fireVFX("igniteBall", 0)
	end

	-- windup, then the shockwave, then 0.2 more
	if this:feintWait(0.42) then
		bail()
		return
	end

	fireVFX("burstRing", humObj.HRootPart, false)

	if this:feintWait(0.2) then
		bail()
		return
	end

	this:useMana()
	this:triggerCD(cooldownID, 12, true)

	-- !! the Humanoid must stop walking for the length of the rush: RUSH_FORCE 20 is only 1.5x walkSpeed 13, so its own input steers the mover and the slide reads rigid. Fulminate does the same.
	humObj.walkSpeed:SetMod(cooldownID, -100)

	-- !! DO NOT set isRootRelative false here: it also arms knockBreakStuff, and at forceMag 120 you would tunnel through the scenery instead of being stopped by it.
	local rush = this:bodyForce(Vector3.new(0, 0, -RUSH_FORCE), RUSH_TIME, true, RUSH_TIME, 0.5)

	-- the flames streaming off the fist for the length of the rush.
	fireVFX("igniteBall", 2, rightArm, RUSH_TIME)

	local caught: {any} = {}
	local seen: {[number]: boolean} = {}
	local breakCount = 0

	local plr = if humObj.plrObj then humObj.plrObj.Plr else nil
	local released = false
	for i = 1, TICKS do
		-- a feint past the commit is an EARLY DETONATE, not a cancel: mana and the cd are already spent. Still costs feint2, so it is a real choice.
		-- a rush holding somebody is not a whiffed feint, so it keeps the cancel flourish off.
		local why = this:channelBreak(#caught > 0)
		if why then
			released = (why == "feint")
			break
		end

		-- the HurtBox, not HRootPart: identity weld, so same CFrame, and it is the one combat already reads.
		local hurtbox = humObj.HurtBox
		if hurtbox == nil then break end
		local forward = hurtbox.CFrame.LookVector

		-- the trench: a CYLINDER carves the run in one call and leaves a continuous trench rather than separate pits.
		if breakCount < BREAK_BUDGET then
			Destruction.Cylinder(plr, hurtbox.Position + forward * 3 + Vector3.new(0, 2, 0),
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

	-- settle BEFORE the release, or a victim walks out of the blast they were dragged into.
	if released and #caught > 0 then
		this:atkWait(FEINT_SETTLE)
	end

	for _, enemy in ipairs(caught) do
		if enemy.grab then enemy.grab:release() end
	end

	if #caught == 0 then
		humObj.walkSpeed:RemoveMod(cooldownID)
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

	-- held through the blast lunge, which is another 12 against walkSpeed 13.
	detonate(this, caught, seen)
	humObj.walkSpeed:RemoveMod(cooldownID)
	this:endLag(0.3)
end

function module.use(self:myself)
	return baseClass.use(self, useFunc)
end

return table.freeze(module)
