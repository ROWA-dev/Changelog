--!strict
--- IceBeam - a sustained freezing beam down a 4x4x40 lane. 19 ticks of tiny
--- damage. rowa1 port: README.md/PORT_IceBeam.
--- THE BEAM DOES NOT STUN, IT FREEZES. rowa1 stunned every tick and then needed
--- four resolver exemptions to stop it being an unbreakable lock. Here each
--- tick pours into the Freeze meter: ~7 connected ticks fill it, the victim
--- freezes ONCE, and a 4s refractory blocks the rest of the beam from refilling
--- it. That is the entire reason StatusEffects/Freeze exists.
local baseClass = require(script.Parent.AbilityBase)
export type myself = baseClass.myself
type humObj = baseClass.humObj

local module = {
	Name = "IceBeam"
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

--[[ rowa1 "ice": Light, ice, 1.5 dmg, truestun 0.1 / stun 0.3, posMult 2.
	stun cut to 0.1 -- see the header. Shipping the meter AND a 0.3s stun
	gives you both problems at once.

	stunMeOnParried 0 is the one-field replacement for rowa1's `noparrystun`
	set: at 19 ticks, parrying one should not stun the caster for the other
	eighteen. ]]
local ICE = {
	weight   = dmgUtils.weighEnum.Light,
	type     = dmgFlag.ice,
	dmg      = 1.5,
	stun     = 0.1,
	posMult  = 0, -- 0 posture dmg (the kb will still apply posture)
	parryH   = 0.1,
	stunMeOnParried = 0,
	onHit    = function(attack)
		hitSfx(attack.enemyEntity.HRootPart, "IceSplash2")
	end,
}

local TICKS       = 19
local TICK_RATE   = 0.1
--- what the client is told the beam will last. See stopBeam below.
local BEAM_TIME   = TICKS * TICK_RATE
--- per tick. ~7 connected ticks reach the threshold of 10.
local FREEZE_FILL = 1.5

local function useFunc(this:myself)
	local cooldownID = "iceBeam"
	if this:canTriggerCD(cooldownID) ~= true then return end

	local humObj  = this._humObj
	local hurtbox = humObj.HurtBox
	local char: any = hurtbox.Parent
	local anim = this:PlayAnim(script.Anim, 0, 1, 1)

	local leftArm = char:FindFirstChild("Left Arm")
	if leftArm then
		fireVFX("icelst", leftArm, 0.9)
	end

	-- rowa1 was 0.5 + 0.2 + 0.2 with a re-check between each. One call.
	if this:feintWait(0.82) then
		if anim then anim:Stop(0.1) end
		--- the hand must stop charging a cast that is not coming
		if leftArm then fireVFX("icelst", leftArm, 0) end
		return
	end

	this:useMana()
	this:triggerCD(cooldownID, 12, true)

	--[[ !! END THE BEAM ON THE REAL END, not on the duration it was started
		with. This channel drops out early on stun and on FEINT, and a client
		told "1.9 seconds" up front kept firing for the remainder -- so a
		feinted IceBeam cancelled the damage and left the beam hanging there,
		which reads as the feint not having worked at all.
		Same shape, same reason, as StoneBall's ststep/bground teardown. ]]
	fireVFX("icelasers", hurtbox, BEAM_TIME)
	local function stopBeam()
		fireVFX("icelasers", hurtbox, 0)
	end

	--[[ fixed-rhythm channel, so this uses the BARRAGE PATTERN for its
		interrupt checks rather than feintWait -- feintWait would fight the
		0.1s cadence. See README S6.2. ]]
	for _ = 1, TICKS do
		--[[ HurtBox-LOCAL, so the beam sweeps as the player turns. rowa1
			recomputed Dir from the root every iteration to get the same
			effect. ]]
		local _, hits = this:hitbox(CFrame.new(0, 0, -20), Vector3.new(4, 4, 38))

		for _, enemy in pairs(hits) do
			task.spawn(function()
				local attack = this:makeAtk(ICE, enemy, hurtbox.CFrame.LookVector)
				-- rowa1 look*6, at the x0.6 ratio (README S7)
				attack.knockback = this:knockback(attack.atkDir * 3.6, 0.1, false, -1)
				this:executeAttack(attack)
				if attack:isHit() then
					attack.enemyEntity.statusEffects:apply(
						statusEffects.Freeze, 4, FREEZE_FILL)
				end
			end)
		end

		task.wait(TICK_RATE)

		if humObj:inStun() then
			if anim then anim:Stop(0.1) end
			stopBeam()
			return
		end
		if this.isFeinted then
			if anim then anim:Stop(0.1) end
			stopBeam()
			this.isFeinted = false
			humObj.cooldowns:trigger("feint2")
			fireVFX("feintfx", char)
			return
		end
	end

	stopBeam()
	if anim then anim:Stop(0.2) end
	this:endLag(0.3)
end

function module.use(self:myself)
	return baseClass.use(self, useFunc)
end

return table.freeze(module)
