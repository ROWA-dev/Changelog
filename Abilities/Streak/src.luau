--!strict
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

local SHOCK = {
	weight   = dmgUtils.weighEnum.Medium,
	type     = dmgFlag.slash,
	dmg      = 24,
	stun     = 0.9,
	posMult  = 2,
	parryH   = -0.04,
	onHit    = function(attack)
		hitSfx(attack.enemyEntity.HRootPart, "HeavyCut", "SlashHit")
	end,
}

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

	if this:feintWait(0.7) then
		if first then first:Stop() end
		return
	end

	this:useMana()
	this:triggerCD(cooldownID, 10, true)

	if first then first:Stop() end
	this:PlayAnim(script.Second, 0.05, 1, 1)

	local root = humObj.HRootPart
	if root == nil then this:endLag(0.2) return end

	local origin = hurtbox.Position
	local dir = hurtbox.CFrame.LookVector

	Destruction.Cylinder(nil, origin + Vector3.new(0, 1, 0), dir, RANGE, 4, 3, dir * 100)

	rayParams.FilterDescendantsInstances = { workspace.Effects, workspace.Entities }
	local hit = workspace:Raycast(origin, dir * RANGE, rayParams)
	local endp = if hit then hit.Position else origin + dir * RANGE
	local endpDist = (origin - endp).Magnitude

	--- ONE query for the whole lane: this is not a projectile.
	local cf = CFrame.new(origin + dir * 20, origin + dir * 100)
	local _, hits = this:hitbox(cf, Vector3.new(7, 7, 36), nil, true)

	local stopDistance = endpDist

	local landed = false
	for _, enemy in pairs(hits) do
		local eroot = enemy.HRootPart
		if eroot == nil then continue end

		local attack = this:makeAtk(SHOCK, enemy, dir)
		this:executeAttack(attack)

		if attack:isParried() or attack:isBlocked() then
			stopDistance = math.min(stopDistance, (origin - eroot.Position).Magnitude)
		elseif not attack:isDodged() then
			landed = true
			eroot.CFrame = CFrame.new(endp + dir * 2, endp - dir)
		end
	end

	fireVFX("streakFx2", origin, dir, stopDistance)

	local alpha = if endpDist > 0 then math.clamp(stopDistance / endpDist, 0, 1) else 0
	local landing = origin:Lerp(endp, alpha)
	char:PivotTo(CFrame.new(landing, landing + dir))

	if landed == true then
		this:endLag(0.26)
	else
		this:endLag(0.4)
	end
end

function module.use(self:myself)
	return baseClass.use(self, useFunc)
end

return table.freeze(module)
