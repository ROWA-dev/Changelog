--!strict
--[[ PiercingStab - rowa1 Items/Ability/PiercingStab.
	Notes: README.md/PORT_PiercingStab.

	The slowest single hit in the set. A 0.65s telegraph you are rooted
	through, paid for with high damage and a -0.1 parry window. Needs a
	weapon. ]]
local baseClass = require(script.Parent.AbilityBase)
export type myself = baseClass.myself
type humObj = baseClass.humObj

local module = {
	Name = "PiercingStab"
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
local fireVFX = require(game.ServerStorage.ROWA.Modules.fireVFX)
local hitSfx  = require(game.ServerStorage.ROWA.Modules.hitSfx)

-- rowa1 "pblow": Medium, slash, 32 dmg, truestun 0.3 / stun 0.85, posMult 3.
local PBLOW = {
	weight   = dmgUtils.weighEnum.Medium,
	type     = dmgFlag.slash,
	dmg      = 20,
	stun     = 0.85,
	posMult  = 3,
	onHit    = function(attack)
		hitSfx(attack.enemyEntity.HRootPart, "HeavyCut", "SlashHit")
	end,
}

--[[ NOT "stopMoving". That key is shared and something else can already be
	holding it during this window (DOC_GOTCHAS); clobbering it would strand
	whoever set it. A per-ability key can only ever fight itself. ]]
local SLOW_KEY = "piercingStab"

local function useFunc(this:myself)
	local cooldownID = "piercingStab"
	if this:canTriggerCD(cooldownID) ~= true then return end

	local humObj = this._humObj
	if humObj.wielding_weapon == nil then
		return -- needs a weapon, same gate as rowa1 (which walked the char for a Tool)
	end

	local hurtbox = humObj.HurtBox
	local anim    = this:PlayAnim(script.Anim, 0, 1, 1)

	local blade = humObj:GetBlade()
	if blade then
		fireVFX("fsShine3", blade, hurtbox.Parent)
	end

	-- rowa1 froze input outright. A walkSpeed mod is the rowa2 equivalent.
	humObj.walkSpeed:SetMod(SLOW_KEY, -13)

	--[[ THE MOD MUST COME OFF ON EVERY EXIT. A stranded negative walkSpeed is
		invisible, permanent and the single most common stuck state in this
		codebase. ]]
	if this:feintWait(0.57) then
		if anim then anim:Stop() end
		humObj.walkSpeed:RemoveMod(SLOW_KEY)
		return
	end
	humObj.walkSpeed:RemoveMod(SLOW_KEY)

	this:useMana()
	this:triggerCD(cooldownID, 9, true)

	fireVFX("pstab", hurtbox)

	local _, hits = this:hitbox(CFrame.new(0, 0, -5), Vector3.new(5, 5, 7))
	for _, enemy in pairs(hits) do
		local attack = this:makeAtk(PBLOW, enemy, hurtbox.CFrame.LookVector)
		-- no knockback in the original: it is a thrust, they stay on the point.
		this:executeAttack(attack)
	end

	this:endLag(0.15)
end

function module.use(self:myself)
	return baseClass.use(self, useFunc)
end

return table.freeze(module)
