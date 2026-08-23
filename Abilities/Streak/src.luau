--!strict
--- Streak - a blink-slash. Cut a 40-stud lane, DRAG everyone caught to the far
--- end, arrive there yourself. rowa1 port: README.md/PORT_Streak.
--- BLOCKING OR PARRYING STOPS THE BLINK -- the caster only travels as far as
--- whoever blocked, so a good block plants them in front of you. The counterplay.
--- No execute helper: rowa1's own finisher branch is commented out, so it never
--- had one, whatever the doc says. The `canStreak` tag gate is not ported
--- either -- it is a per-character unlock, which would be a card here.
local baseClass = require(script.Parent.AbilityBase)
export type myself = baseClass.myself
type humObj = baseClass.humObj

local module = {
	Name = "Streak"
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

--- rowa1 "shock": Medium, slash, 40 dmg, truestun 0.4 / stun 0.9, posMult 2.
local SHOCK = {
	weight   = dmgUtils.weighEnum.Medium,
	type     = dmgFlag.slash,
	dmg      = 26,
	stun     = 0.9,
	posMult  = 2,
	parryH   = -0.04,
	onHit    = function(attack)
		hitSfx(attack.enemyEntity.HRootPart, "HeavyCut", "SlashHit")
	end,
}

--- rowa1 rays 8*5 studs
local RANGE = 40

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true

local function useFunc(this:myself)
	local cooldownID = "streak"
	if this:canTriggerCD(cooldownID) ~= true then return end

	local humObj = this._humObj
	if humObj.wielding_weapon == nil then
		return -- it is a blade move
	end

	local hurtbox = humObj.HurtBox
	local char: any = hurtbox.Parent
	local first = this:PlayAnim(script.First, 0, 1, 1)

	local blade = humObj:GetBlade()
	if blade then
		fireVFX("streakFx", blade, humObj.HRootPart)
	end

	--- rowa1: 7 x 0.1
	if this:feintWait(0.62) then
		if first then first:Stop() end
		return
	end

	this:useMana()
	this:triggerCD(cooldownID, 10, true)

	if first then first:Stop() end
	this:PlayAnim(script.Second, 0.05, 1, 1)

	local root = humObj.HRootPart
	if root == nil then this:endLag(0.2) return end

	local origin = root.Position
	local dir = root.CFrame.LookVector

	--- the lane. rowa1 gives up after two successful breaks.
	--[[ rowa1 stepped eight 8^3 BlockBreaks down the lane and gave up after
		two landed. rowa2 has a real cylinder, so the whole lane is ONE call
		-- no stepping, no scalloped edge, and no need to count successes. ]]
	--- velo is studs/SECOND: the lane debris should fly with the dash
	Destruction.Cylinder(nil, origin + Vector3.new(0, 1, 0), dir, RANGE, 4, 2.4, dir * 50)

	rayParams.FilterDescendantsInstances = { workspace.Effects, workspace.Entities }
	local hit = workspace:Raycast(origin, dir * RANGE, rayParams)
	local endp = if hit then hit.Position else origin + dir * RANGE
	local endpDist = (origin - endp).Magnitude

	--[[ ONE query for the whole lane -- rowa1 does the same, this is not a
		projectile (PLAN_PROJECTILE 2A does not apply). ]]
	local cf = CFrame.new(origin + dir * 20, origin + dir * 100)
	local _, hits = this:hitbox(cf, Vector3.new(7, 7, 36), nil, true)

	local stopDistance = endpDist

	for _, enemy in pairs(hits) do
		local eroot = enemy.HRootPart
		if eroot == nil then continue end

		local attack = this:makeAtk(SHOCK, enemy, dir)
		this:executeAttack(attack)

		if attack:isParried() or attack:isBlocked() then
			--[[ !! THE BLINK STOPS HERE. A good block plants the caster in
				front of the blocker instead of letting them pass through.
				Take the NEAREST such stop, not the last one iterated. ]]
			stopDistance = math.min(stopDistance, (origin - eroot.Position).Magnitude)

		elseif not attack:isDodged() then
			--[[ dragged to the far end of the lane, facing back down it.
				Set the ROOT's CFrame, not the entity's -- an entity is a
				Lua object, not an Instance, so it has no PivotTo. rowa1 used
				SetPrimaryPartCFrame; moving the root moves the assembly. ]]
			eroot.CFrame = CFrame.new(endp + dir * 2, endp - dir)
		end
	end

	fireVFX("streakFx2", origin, dir, stopDistance)

	--- arrive: only as far as the nearest block allowed
	local alpha = if endpDist > 0 then math.clamp(stopDistance / endpDist, 0, 1) else 0
	local landing = origin:Lerp(endp, alpha)
	char:PivotTo(CFrame.new(landing, landing + dir))

	this:endLag(0.28)
end

function module.use(self:myself)
	return baseClass.use(self, useFunc)
end

return table.freeze(module)
