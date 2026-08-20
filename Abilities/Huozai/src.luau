--!strict
--[[ Huozai - rowa1 Items/Ability/Huozai. Notes: README.md/PORT_Huozai.

	A 3-second forward flamethrower. Six nested bands of increasing size step
	away from the caster and are re-fired every 0.1s. 60-second cooldown --
	this is an ultimate.

	!! A REAL ROWA1 BUG IS FIXED HERE.
	  rowa1's band loop is `for i = 1,6 do ... for i,v in pairs(Stuff) do`.
	  The inner loop SHADOWS `i`, so the band selection underneath
	  (`if i == 6 ... elseif i == 1 or i == 2`) reads the PART INDEX inside
	  the query result, not the band. Which damage table you got was
	  therefore effectively random and had nothing to do with how far away
	  you were stood. Ported as the obvious intent -- close bands push hard,
	  far bands chip, the outermost only burns.

	!! CROSS-BAND DEDUPE IS LOAD-BEARING.
	  rowa1 shares ONE humsH across all six bands, so a target in the overlap
	  is hit once per tick, not six times. :hitbox only dedupes WITHIN one
	  query, so the `seen` table below is what stops 6 damage becoming 36.
	  Same trap as Cero and Freeze. ]]
local baseClass = require(script.Parent.AbilityBase)
export type myself = baseClass.myself
type humObj = baseClass.humObj

local module = {
	Name = "Huozai"
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

--[[ rowa1 "fire1"/"fire2": both Light, magic+fire, stun 0.1, posMult 0.5.
	BOTH BANDS ARE LIGHT WITH A 0.1 STUN, and that is what stops a 3-second
	channel being a lock -- it is DoT pressure, not control. Do not raise the
	stun to make it "feel better"; the counterplay is walking around them. ]]
local FIRE_NEAR = {
	weight   = dmgUtils.weighEnum.Light,
	type     = bit32.bor(dmgFlag.magic, dmgFlag.fire),
	dmg      = 10,
	stun     = 0.1,
	posMult  = 0.5,
	parryH   = 0.1,
	stunMeOnParried = 0,
	onHit    = function(attack)
		hitSfx(attack.enemyEntity.HRootPart, "HitSound")
	end,
}
local FIRE_FAR = {
	weight   = dmgUtils.weighEnum.Light,
	type     = bit32.bor(dmgFlag.magic, dmgFlag.fire),
	dmg      = 6,
	stun     = 0.1,
	posMult  = 0.5,
	parryH   = 0.1,
	stunMeOnParried = 0,
	onHit    = function(attack)
		hitSfx(attack.enemyEntity.HRootPart, "HitSound")
	end,
}

local BANDS       = 6
local CHANNEL     = 3
local TICK_RATE   = 0.1
local SLOW_KEY    = "huozai"

local function useFunc(this:myself)
	local cooldownID = "huozai"
	if this:canTriggerCD(cooldownID) ~= true then return end

	local humObj  = this._humObj
	local hurtbox = humObj.HurtBox
	local char: any = hurtbox.Parent
	local anim = this:PlayAnim(script.Anim, 0, 1, 1)

	-- rowa1 froze input outright for the whole cast; walkSpeed is the rowa2
	-- equivalent. MUST come off on every exit path.
	humObj.walkSpeed:SetMod(SLOW_KEY, -100)

	--[[ THE BREATH IN. rowa1's first act after the anim is to clone BreathOut
		onto the root and play it -- 1.2 seconds of drawing breath is the
		entire tell for this move, and without it the flame arrives with no
		warning at all. The sound is longer than the windup on purpose; it
		carries under the first bands of fire.
		rowa1 calls sound:Stop() on its interrupt path, so a cancelled cast
		does not keep breathing. Debris 0 is the rowa2 spelling of that
		(StrongLeft and StrongerLeft both do it this way). ]]
	local breath = script.BreathOut:Clone()
	breath.Parent = humObj.HRootPart
	breath:Play()
	game.Debris:AddItem(breath, 4)

	if this:feintWait(1.2) then
		if anim then anim:Stop(0.1) end
		game.Debris:AddItem(breath, 0)
		humObj.walkSpeed:RemoveMod(SLOW_KEY)
		return
	end

	this:useMana()
	this:triggerCD(cooldownID, 45, true)

	--[[ !! END THE PLUME ON THE REAL END, not on the duration it was started
		with. This channel breaks out early on stun and on FEINT, and the
		client was told "3 seconds" up front -- so a feinted Huozai stopped
		dealing damage while the flamethrower, the camera shake and the
		pushed FOV all carried on. The feint looked like it did nothing.
		rowa1 could stop it whenever it liked: its signal was a TAG it
		removed, not a duration (README S5 step 7b). This is that tag.
		Same shape as StoneBall's ststep/bground teardown. ]]
	fireVFX("huozai", char, CHANNEL)

	local started = tick()
	local nextTick = 0

	while tick() < started + CHANNEL do
		task.wait()

		if humObj:inStun() then break end
		if this.isFeinted then
			this.isFeinted = false
			humObj.cooldowns:trigger("feint2")
			fireVFX("feintfx", char)
			break
		end
		if tick() < nextTick then continue end
		nextTick = tick() + TICK_RATE

		local root = hurtbox
		local forward = root.CFrame.LookVector
		--- ONE table across all six bands -- see the header.
		local seen: {[number]: boolean} = {}

		--[[ rowa1 rolled a 1-in-5 destruction chance PER BAND PER TICK: up to
			five carves every 0.1s for three seconds. That is ~150 carve
			attempts a cast and it will stall a busy server. One roll per
			tick, on a random band. ]]
		local carveBand = math.random(1, BANDS - 1)

		for i = 1, BANDS do
			local dist = 2 + 4 * i ^ 1.8
			local size = Vector3.new(3, 3, 3) * (i ^ 1.2) * 2
			local cf = CFrame.new(root.Position + forward * dist, root.Position)

			if i == carveBand then
				--- rowa1 BlockBreak2 took its size as an argument and is
				--- genuinely box-shaped, so it maps straight onto OBB.
				local carveSize = size / (math.random(100, 150) / 100)
				Destruction.OBB(nil, cf * CFrame.new(0, size.Y / 3, 0),
					carveSize, math.max(1.5, math.min(carveSize.X, carveSize.Y, carveSize.Z) * 0.6),
					--[[ studs/SECOND. Gentler than the impact moves: this is
						a flame washing over the ground, so the rubble should
						be nudged along the lane rather than blown off it. ]]
					forward * 25)
			end

			local _, hits = this:hitbox(cf, size, nil, true)
			for _, enemy in pairs(hits) do
				if seen[enemy.entityId] then continue end
				seen[enemy.entityId] = true

				--[[ the outermost band is NOT an attack. rowa1 resolved a
					dmgID called "burn" with dmg 0 and stun 0 whose only job
					was to make the resolver call BurnEnemy. One line here. ]]
				if i == BANDS then
					enemy.statusEffects:apply(humObj.statusEffects.Burn, 6, 3)
					continue
				end

				local near = (i <= 2)

				--[[ !! DO NOT COPY rowa1's `vector.create(math.random(-1,1),0,0)`.
					rowa1's `dir` is a LOCAL-SPACE FLINCH SELECTOR -- victimHitAnims
					reads dir.Z > 0.8 as "front", dir.X < 0 as "left", dir.X > 0 as
					"right" -- so that literal means "pick a random left/right hit
					animation", not a direction.
					rowa2's atkDir is a WORLD-SPACE vector (HumObj does
					myTorso.CFrame:VectorToObjectSpace(attack.atkDir) and also uses
					it as extraVelo). Porting the literal across gave every band a
					knockback pointing along world -X regardless of facing.
					A flamethrower pushes along the CASTER'S FACING. ]]
				task.spawn(function()
					local attack = this:makeAtk(near and FIRE_NEAR or FIRE_FAR, enemy, forward)
					-- rowa1 Root.CFrame.LookVector*18 / *6, at the x0.6 ratio (README S7)
					attack.knockback = this:knockback(
						forward * (near and 10.8 or 3.6), 0.15, false, -1)
					this:executeAttack(attack)
				end)
			end
		end
	end

	fireVFX("huozai", char, 0)
	humObj.walkSpeed:RemoveMod(SLOW_KEY)
	if anim then anim:Stop(0.2) end
	this:endLag(0.3)
end

function module.use(self:myself)
	return baseClass.use(self, useFunc)
end

return table.freeze(module)
