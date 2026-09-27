--!strict
--- WindSlash - the first wind move: a heavy right-to-left sweep that cuts up close and throws a faint wind disk that boomerangs home.
local baseClass = require(script.Parent.AbilityBase)
export type myself = baseClass.myself
type humObj = baseClass.humObj

local module = {
	Name = "WindSlash"
}
module.__tostring = baseClass.__tostring
module.__index = module
setmetatable(module, { __index = baseClass })

function module.new(humObj:humObj):myself
	return setmetatable(baseClass.new(humObj), module) :: any
end

local dmgUtils = require(game.ServerScriptService.Utils.DmgUtils)
local dmgFlag  = dmgUtils.dmgFlags
local fireVFX  = require(game.ServerStorage.ROWA.Modules.fireVFX)

-- windSlash stages
local FX_GATHER, FX_FIZZLE, FX_RELEASE, FX_HIT = 1, 2, 3, 4

local WINDUP   = 0.6
local ANIM_HIT = 0.53 -- anim time the arms cross the front; the track is slowed to land on WINDUP

local function windHit(attack)
	fireVFX("windSlash", FX_HIT, attack.enemyEntity.HRootPart)
end

local SWING = {
	weight   = dmgUtils.weighEnum.Heavy,
	type     = bit32.bor(dmgFlag.wind, dmgFlag.slash),
	dmg      = 16,
	stun     = 0.7,
	posMult  = 2,
	onHit    = windHit,
}

-- boomerang: out SPREAD right, an eased 180+2*SPREAD left bend, back SPREAD left, then it homes on you and is caught
local SPREAD = math.rad(20) -- solved with REACH/ARC so the loop is symmetric about your look and closes on the release point; re-solve if you change them
local REACH  = 20 -- straight studs before it bends
local ARC    = 80 -- studs the bend is eased over; shorter bends harder

local GUST = table.freeze({
	speed          = 100,
	steer          = 6, -- rad/s chasing you once the bend is done
	lifetime       = 2.5, -- ceilings: it normally ends caught, ~1.2s
	maxDistance    = 250,
	curve          = table.freeze({ from = REACH, len = ARC, angle = math.pi + 2 * SPREAD }),
	size           = Vector3.new(16, 5, 5),
	pierce         = 4,
	knockbackForce = 10,
	knockbackTime  = 0.1,
	fxId           = "windSlashProj",
	dmgTbl = {
		weight   = dmgUtils.weighEnum.Medium,
		type     = bit32.bor(dmgFlag.wind, dmgFlag.slash),
		dmg      = 8,
		stun     = 0.4,
		posMult  = 1,
		onHit    = windHit,
	},
	onHit = function(proj, attack)
		if attack:isParried() then proj:parryHome(attack.enemyEntity) end
	end,
})

local function useFunc(this:myself)
	local cooldownID = "windSlash"
	if this:canTriggerCD(cooldownID) ~= true then return end

	local humObj  = this._humObj
	local hurtbox = humObj.HurtBox
	local root    = humObj.HRootPart
	local anim    = this:PlayAnim(script.anim, 0, 1, ANIM_HIT / WINDUP)

	humObj.walkSpeed:SetMod(cooldownID, -100)
	fireVFX("windSlash", FX_GATHER, root, this:scaledTime(WINDUP))
	local feinted = this:feintWait(WINDUP)
	humObj.walkSpeed:RemoveMod(cooldownID)
	if feinted then
		if anim then anim:Stop() end
		fireVFX("windSlash", FX_FIZZLE, root)
		return
	end

	this:useMana()
	this:triggerCD(cooldownID, 8)

	-- snapshot, gust and fx before any executeAttack: a hit can hold a ping, the gust leaves on the swing
	local _, hits = this:hitbox(CFrame.new(0, 0, -4.5), Vector3.new(12, 7, 8))
	local cfg = table.clone(GUST) -- frozen and shared, so the per-cast target (you) goes on a clone
	cfg.target = humObj
	local gust = this:projectile(table.freeze(cfg), hurtbox.CFrame * CFrame.new(0, 0, -2) * CFrame.Angles(0, -SPREAD, 0))
	fireVFX("windSlash", FX_RELEASE, root)

	-- one swing, one hit: the gust carries on past whoever the blade already cut
	if gust then
		for _, enemy in hits do gust.seen[(enemy :: any).entityId] = true end
	end
	for _, enemy in hits do
		local attack = this:makeAtk(SWING, enemy, hurtbox.CFrame.LookVector)
		attack.knockback = this:knockback(attack.atkDir * 12, 0.1, false, -1)
		this:executeAttack(attack)
	end

	this:endLag(0.25)
end

function module.use(self:myself)
	return baseClass.use(self, useFunc)
end

return table.freeze(module)
