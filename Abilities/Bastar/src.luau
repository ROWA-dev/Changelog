--!strict
--[[ Bastar - rowa1 Items/Ability/Bastar. Notes: README.md/PORT_Bastar.

	A greatsword move in two beats: SLAM someone into the ground and pin them
	on the blade, hold, then hurl the sword down the lane.

	Needs a weapon with a blade.

	The slam's stun is 2.0 in rowa1 -- the longest in its whole table -- which
	exists purely to guarantee the follow-up. Halved: rowa2's stun is a single
	field (README S4.2), so 2.0 there is 2.0 of everything, and the weld
	already guarantees the second beat. ]]
local baseClass = require(script.Parent.AbilityBase)
export type myself = baseClass.myself
type humObj = baseClass.humObj

local module = {
	Name = "Bastar"
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
local destruct = require(game.ServerStorage.ROWA.Modules.rowa1Destruct)

--- rowa1 "bastard": Heavy, slash, 20 dmg, truestun 1.6 / stun 2.0, posMult 4.
local BASTARD = {
	weight   = dmgUtils.weighEnum.Heavy,
	type     = dmgFlag.slash,
	dmg      = 20,
	--- 2.0 halved: see the header
	stun     = 1,
	posMult  = 4,
	parryH   = -0.04,
	onHit    = function(attack)
		hitSfx(attack.enemyEntity.HRootPart, "HitCrush")
	end,
}

--- rowa1 "gsThrow": Heavy, slash, 20 dmg, truestun 0.6 / stun 0.8, posMult 5.
local GS_THROW = {
	weight   = dmgUtils.weighEnum.Heavy,
	type     = dmgFlag.slash,
	dmg      = 20,
	stun     = 0.8,
	posMult  = 4,
	parryH   = -0.04,
	onHit    = function(attack)
		hitSfx(attack.enemyEntity.HRootPart, "BladeStab", "HeavyCut", "BombFall")
	end,
}



local function useFunc(this:myself)
	local cooldownID = "bastar"
	if this:canTriggerCD(cooldownID) ~= true then return end

	local humObj = this._humObj
	if humObj.wielding_weapon == nil then
		return -- greatsword move; rowa1 gated on the Tool having a Blade
	end

	local hurtbox = humObj.HurtBox
	local char: any = hurtbox.Parent
	local anim = this:PlayAnim(script.Part1, 0, 1, 1)

	--- hshock takes a BASEPART in rowa2, not a Humanoid (README S5 step 7e)
	fireVFX("hshock", humObj.HRootPart)
	fireVFX("camShake", hurtbox.Position, 300, 1, 0.1)

	local blade = humObj:GetBlade()
	if blade then
		--- rowa1 tints the blade red for the whole windup
		fireVFX("partOutline", blade, Color3.fromRGB(255, 0, 0), 0.4)
	end

	if this:feintWait(0.55) then
		if anim then anim:Stop() end
		return
	end

	this:useMana()
	this:triggerCD(cooldownID, 12, true)

	local forward = hurtbox.CFrame.LookVector

	--[[ the SLAM. atkDir is DOWNWARD -- HumObj reads it for the victim's
		reaction, and this drives them into the floor rather than away. ]]
	local _, hits = this:hitbox(CFrame.new(0, 0, -5), Vector3.new(5, 7, 7))

	local pinned: {any} = {}
	for _, enemy in pairs(hits) do
		local attack = this:makeAtk(BASTARD, enemy, Vector3.new(0, -1, 0))
		-- rowa1 (0,-10,0), at the x0.6 knockback ratio (README S7)
		attack.knockback = this:knockback(Vector3.new(0, -6, 0), 0.2, false, -1)
		this:executeAttack(attack)

		if attack:isHit() and enemy.grab then
			--[[ !! PINNED ON THE BLADE, not the root. rowa1 welds to
				`gsBlade` and parents the weld there too -- they are IMPALED
				and carried on the sword. Welding to the root instead leaves
				them floating at the caster's waist, which is the whole
				reason this looked wrong.
				The offset is along the blade rather than in front of the
				body, and it falls back to the root if there is no blade. ]]
			--- PURE ROTATION: the blade already IS where they should hang.
			--- rowa1: C0 = CFrame.Angles(90, 0, 180).
			enemy.grab:grab(humObj,
				CFrame.Angles(math.rad(90), 0, math.rad(180)), 2, blade)
			table.insert(pinned, enemy)
		end
	end

	if #pinned == 0 then
		this:endLag(0.25)
		return
	end

	--[[ the hold. rowa1 waits 0.8s pinned before the throw.
		+0.08 because this is an inter-beat wait, not the windup (README 7f).
		THE PIN MUST COME OFF ON EVERY EXIT -- a stranded weld is a player
		who can never move again, and it is silent. ]]
	local function unpin()
		for _, enemy in ipairs(pinned) do
			if enemy.grab then enemy.grab:release() end
		end
	end

	if this:feintWait(0.88) then
		if anim then anim:Stop() end
		unpin()
		return
	end

	unpin()

	if anim then anim:Stop(0.1) end
	this:PlayAnim(script.Part2, 0.05, 1, 1)

	--[[ the lane. rowa1 carves at 6, 12 and 18 studs, at TWO heights each
		(-2 and +4), budgeted the same way Burst's rush is. ]]
	forward = hurtbox.CFrame.LookVector
	for i = 1, 3 do
		local at = hurtbox.Position + forward * 6 * i
		destruct.smallBreak2(at + Vector3.new(0, -2, 0), forward)
		destruct.smallBreak2(at + Vector3.new(0, 4, 0), forward)
	end

	local _, thrown = this:hitbox(CFrame.new(0, 0, -5), Vector3.new(5, 7, 7))
	for _, enemy in pairs(thrown) do
		local attack = this:makeAtk(GS_THROW, enemy, forward)
		-- rowa1 look*40 + (0,8,0), at the x0.6 knockback ratio (README S7)
		attack.knockback = this:knockback(
			attack.atkDir * 24 + Vector3.new(0, 4.8, 0), 0.2, false, -1)
		this:executeAttack(attack)

		if attack:isHit() then
			--- rowa1's gsThrow onHit is ragdtillground: a CAP ended by landing
			attack.enemyEntity.ragdoll:ragdoll(60, true, attack.atkDir * 10)
		end
	end

	this:endLag(0.25)
end

function module.use(self:myself)
	return baseClass.use(self, useFunc)
end

return table.freeze(module)
