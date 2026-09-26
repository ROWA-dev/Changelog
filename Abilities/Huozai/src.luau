--!strict
--- Huozai - 3s flamethrower, six nested bands re-fired every 0.1s. Ultimate.
local baseClass = require(script.Parent.AbilityBase)
export type myself = baseClass.myself
type humObj = baseClass.humObj

local module = {
	Name = "Huozai",
	manaUse = 40
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
local partFx   = require(game.ServerStorage.ROWA.Modules.partFx)

--- Both bands Light with a 0.1 stun on purpose: DoT pressure, not a 3s lock.
local FIRE_NEAR = {
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
local FIRE_FAR = {
	weight   = dmgUtils.weighEnum.Light,
	type     = bit32.bor(dmgFlag.magic, dmgFlag.fire),
	dmg      = 3,
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
local BURN_T      = 60
local SKIN        = 1.5 -- how deep the flame bites into a surface
local LIFT        = 60 -- studs/s off the face: skim plates fill the recess they came from, so sideways alone leaves them lying in it. Apex = LIFT^2/(2*Gravity 140)
local BLOW        = 120 -- studs/s along the face with the flame

-- MAP only: no characters, no effects. Pinned to a permanent folder (GOTCHAS: params hold strong refs)
local MAP = workspace:WaitForChild("MAP")
local scorchParams = OverlapParams.new()
scorchParams.FilterType = Enum.RaycastFilterType.Include
scorchParams.FilterDescendantsInstances = { MAP }
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include
rayParams.FilterDescendantsInstances = { MAP }

-- the hit face's frame on the hit part's own axes, so the skin cuts straight along its edges
local function surfaceCF(hit: RaycastResult): CFrame
	local n, pcf = hit.Normal, (hit.Instance :: BasePart).CFrame
	local u = if math.abs(pcf.XVector:Dot(n)) < 0.7 then pcf.XVector else pcf.ZVector
	return CFrame.fromMatrix(hit.Position, (u - n * u:Dot(n)).Unit, n)
end

-- already skimmed: the hit is inside the ground's original volume, so a skim only ever takes the top layer
local function dug(hit: RaycastResult): boolean
	local o = Destruction.original(hit.Instance :: BasePart)
	if o == nil then return false end
	local p = o.CFrame:PointToObjectSpace(hit.Position):Abs()
	local h = o.Size / 2 - Vector3.one * 0.1
	return p.X < h.X and p.Y < h.Y and p.Z < h.Z
end

local function useFunc(this:myself)
	local cooldownID = "huozai"
	if this:canTriggerCD(cooldownID) ~= true then return end

	local humObj  = this._humObj
	local hurtbox = humObj.HurtBox
	local char: any = hurtbox.Parent
	local anim = this:PlayAnim(script.Anim, 0, 1, 1)

	-- MUST come off on every exit path.
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

		if this:channelBreak() then break end
		if tick() < nextTick then continue end
		nextTick = tick() + TICK_RATE

		local root = hurtbox
		local forward = root.CFrame.LookVector
		--- ONE table across all six bands: :hitbox only dedupes within one query, so this is what stops 6 dmg becoming 36.
		local seen: {[number]: boolean} = {}

		--- ONE carve roll per tick. Per-band rolls came to ~150 carves a cast.
		local carveBand = math.random(1, BANDS - 1)

		for i = 1, BANDS do
			local dist = 2 + 4 * i ^ 1.8
			local size = Vector3.new(3, 3, 3) * (i ^ 1.2) * 2
			local cf = CFrame.new(root.Position + forward * dist, root.Position)

			if i == carveBand then
				-- the flame skims the surface it reaches, a wall ahead or else the ground under the band; never below the original surface
				local hit = workspace:Raycast(root.Position, forward * dist, rayParams)
					or workspace:Raycast(cf.Position, Vector3.new(0, -size.Y / 2 - 4, 0), rayParams)
				if hit and not dug(hit) then
					local w = size.X / (math.random(100, 150) / 100)
					local skin = Vector3.new(w, SKIN * 2, w)
					local skinCF = surfaceCF(hit)
					-- minSz w/4: on a block's own axes the skin cuts clean at any size, so fine blocks only cost time (32 wide: 2.2ms -> 0.07ms)
					local n = hit.Normal
					Destruction.OBB(nil, skinCF, skin, math.max(2, w / 4), n * LIFT + (forward - n * forward:Dot(n)) * (BLOW + math.random(-20,40)), partFx.Burn) --- studs/SECOND: popped off the face, then along it with the flame; rubble flies charred.
					-- rowa1's scorch: twice the cut, parts the cut dwarfs, so the hole chars and a slab's far edges don't
					for _, p in workspace:GetPartBoundsInBox(skinCF, skin * 2, scorchParams) do
						if math.max(p.Size.X, p.Size.Y, p.Size.Z) <= w then
							partFx.apply(p, partFx.Burn, BURN_T)
						end
					end
				end
			end

			local _, hits = this:hitbox(cf, size, nil, true)
			for _, enemy in pairs(hits) do
				if seen[enemy.entityId] then continue end
				seen[enemy.entityId] = true

				--- the outermost band is not an attack, it only ignites.
				if i == BANDS then
					ignite(enemy)
					continue
				end

				local near = (i <= 2)

				--- !! atkDir is WORLD-SPACE here.
				task.spawn(function()
					local attack = this:makeAtk(near and FIRE_NEAR or FIRE_FAR, enemy, forward)
					attack.knockback = this:knockback(
						forward * (near and 10.8 or 3.6), 0.15, false, -1)
					this:executeAttack(attack)
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
