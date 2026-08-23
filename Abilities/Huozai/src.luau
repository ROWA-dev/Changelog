--!strict
--- Huozai - 3s flamethrower, six nested bands re-fired every 0.1s. Ultimate.
--- rowa1 port: README.md/PORT_Huozai. Band select fixes rowa1's shadowed `i`.
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
local fireVFX  = require(game.ServerStorage.ROWA.Modules.fireVFX)
local hitSfx   = require(game.ServerStorage.ROWA.Modules.hitSfx)
local Destruction = require(game.ServerStorage.ROWA.Destruction_Stable.Destruction)

--- Both bands Light with a 0.1 stun on purpose: DoT pressure, not a 3s lock.
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

	-- rowa1 froze input outright; walkSpeed is the rowa2 equivalent. MUST come off on every exit path.
	humObj.walkSpeed:SetMod(SLOW_KEY, -100)

	--- the breath-in is the whole tell; Debris 0 on the cancel path kills it.
	local breath = script.BreathOut:Clone()
	breath.Parent = humObj.HRootPart
	breath:Play()
	game.Debris:AddItem(breath, 4)

	if this:feintWait(1.12) then
		if anim then anim:Stop(0.1) end
		game.Debris:AddItem(breath, 0)
		humObj.walkSpeed:RemoveMod(SLOW_KEY)
		return
	end

	this:useMana()
	this:triggerCD(cooldownID, 45, true)

	--- !! killed by the explicit 0-duration call at the end, not this 3s: the channel breaks out early on stun/feint.
	fireVFX("huozai", char, CHANNEL)

	local started = tick()
	local nextTick = 0

	--- ONE ignite per victim per CAST: onStack is uncapped, so 30 re-applies land ~46 dmg.
	local burned: {[number]: boolean} = {}
	local function ignite(enemy: any)
		local id = enemy.entityId
		if burned[id] then return end
		burned[id] = true
		enemy.statusEffects:apply(humObj.statusEffects.Burn, 6, 3)
	end

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
		--- ONE table across all six bands: :hitbox only dedupes within one query, so this is what stops 6 dmg becoming 36.
		local seen: {[number]: boolean} = {}

		--- one carve roll per tick, not rowa1's per-band 1-in-5 (~150 carves a cast).
		local carveBand = math.random(1, BANDS - 1)

		for i = 1, BANDS do
			local dist = 2 + 4 * i ^ 1.8
			local size = Vector3.new(3, 3, 3) * (i ^ 1.2) * 2
			local cf = CFrame.new(root.Position + forward * dist, root.Position)

			if i == carveBand then
				--- rowa1 BlockBreak2 is genuinely box-shaped, so it maps straight onto OBB.
				local carveSize = size / (math.random(100, 150) / 100)
				Destruction.OBB(nil, cf * CFrame.new(0, size.Y / 3, 0),
					carveSize, math.max(1.5, math.min(carveSize.X, carveSize.Y, carveSize.Z) * 0.6),
					forward * 25) --- studs/SECOND, gentle: flame nudges rubble along the lane.
			end

			local _, hits = this:hitbox(cf, size, nil, true)
			for _, enemy in pairs(hits) do
				if seen[enemy.entityId] then continue end
				seen[enemy.entityId] = true

				--- outermost band is not an attack: rowa1's "burn" dmgID was dmg 0, stun 0.
				if i == BANDS then
					ignite(enemy)
					continue
				end

				local near = (i <= 2)

				--- !! atkDir is WORLD-SPACE here; rowa1's `dir` was a local-space flinch selector, so do not copy its math.random literal.
				task.spawn(function()
					local attack = this:makeAtk(near and FIRE_NEAR or FIRE_FAR, enemy, forward)
					-- rowa1 Root.CFrame.LookVector*18 / *6, at the x0.6 ratio (README S7)
					attack.knockback = this:knockback(
						forward * (near and 10.8 or 3.6), 0.15, false, -1)
					this:executeAttack(attack)
					--- rowa1 burned on both bands too, behind that same guard.
					if attack:isHit() then ignite(enemy) end
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
