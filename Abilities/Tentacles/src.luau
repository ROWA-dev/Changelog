--!strict
-- Barrage of tentacles
local baseClass = require(script.Parent.AbilityBase)
export type myself = baseClass.myself
type humObj = baseClass.humObj

local module = {
	Name = "Tentacles"
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

--- stunMeOnParried 0: at 19 ticks, parrying one must not stun the caster for
--- the other eighteen.
local DARK = {
	weight   = dmgUtils.weighEnum.Light,
	type     = dmgFlag.shadow,
	dmg      = 2,
	stun     = 0.4,
	posMult  = 0, -- 0 posture dmg (the kb will still apply posture)
	parryH   = 0.1,
	stunMeOnParried = 0,
	onHit    = function(attack)
		hitSfx(attack.enemyEntity.HRootPart, "wet_punch2")
	end,
}

local TICKS     = 19
local TICK_RATE = 0.1
--- inward drag per tick, and the distance it gives up at: inside that they
--- are already on you and another yank only jitters them through your body.
local PULL      = 3.6
local PULL_STOP = 6
--- what the client is told the lash will last. See stopLash below.
local LASH_TIME = TICKS * TICK_RATE

local function useFunc(this:myself)
	local cooldownID = "tentacles"
	if this:canTriggerCD(cooldownID) ~= true then return end

	local humObj  = this._humObj
	local hurtbox = humObj.HurtBox
	local anim = this:PlayAnim(script.Anim, 0, 1, 1)

	-- TODO no windup tell yet: IceBeam charges icelst up the left arm, and the
	-- Tentacles asset has no charge stage. Dark charge fx, or open the portal early.
	if this:feintWait(0.82) then
		if anim then anim:Stop(0.1) end
		return
	end

	this:useMana()
	this:triggerCD(cooldownID, 12, true)

	--- END ON THE REAL END, not on the duration it was started with: this
	--- channel drops out early on stun and on feint. VFX.md, sustained ids.
	fireVFX("tentacles", hurtbox, LASH_TIME)
	local function stopLash()
		fireVFX("tentacles", hurtbox, 0)
	end

	--- fixed-rhythm channel, so :channelBreak does the interrupt checks --
	--- feintWait would fight the 0.1s cadence.
	for _ = 1, TICKS do
		--- HurtBox-LOCAL, so the lane sweeps as the player turns.
		local _, hits = this:hitbox(CFrame.new(0, 0, -20), Vector3.new(6, 6, 38))

		for _, enemy in pairs(hits) do
			task.spawn(function()
				local attack = this:makeAtk(DARK, enemy, hurtbox.CFrame.LookVector)
				--- atkDir stays the STRIKE direction -- parry, block and the hit
				--- reaction all read it -- and only the knockback turns around.
				local eroot = enemy.HRootPart
				local toMe = eroot and (hurtbox.Position - eroot.Position) * Vector3.new(1, 0, 1)
				if toMe and toMe.Magnitude > PULL_STOP then
					attack.knockback = this:knockback(toMe.Unit * PULL, TICK_RATE, false, -1)
				end
				this:executeAttack(attack)
				-- TODO PAYOFF: 19 ticks of 1.5 with no stun needs one. The pull
				-- is half of it; Blind is the dark-flavoured meter (Blight's).
			end)
		end

		task.wait(TICK_RATE)

		if this:channelBreak() then
			if anim then anim:Stop(0.1) end
			stopLash()
			return
		end
	end

	stopLash()
	if anim then anim:Stop(0.2) end
	this:endLag(0.3)
end

function module.use(self:myself)
	return baseClass.use(self, useFunc)
end

return table.freeze(module)
