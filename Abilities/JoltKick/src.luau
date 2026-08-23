--!strict
--- JoltKick - a charged lightning roundhouse. If the first kick connects it
--- chains into a second animation and a second jolt on the SAME victim, with
--- the caster dragged along behind them. rowa1 port: README.md/PORT_JoltKick.
--- feintWait gets the honest 0.7 windup; rowa1 declared 0.1, which is what the
--- trade logic reads, so the old version won trades it had no business winning.
local baseClass = require(script.Parent.AbilityBase)
export type myself = baseClass.myself
type humObj = baseClass.humObj

local module = {
	Name = "JoltKick"
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
local pinTo    = require(game.ServerStorage.ROWA.Modules.pinTo)

--- rowa1 "jolt": Heavy, blunt+magic, 30 dmg, truestun 0.4 / stun 0.9.
local JOLT = {
	weight   = dmgUtils.weighEnum.Heavy,
	type     = bit32.bor(dmgFlag.blunt, dmgFlag.magic),
	dmg      = 16,
	stun     = 0.9,
	posMult  = 2,
	parryH   = -0.04,
	onHit    = function(attack)
		hitSfx(attack.enemyEntity.HRootPart, "HitSound", "JoltH")
	end,
}

--- the JoltFx burst, fired twice (once per kick).
local function joltBurst(root: BasePart)
	local stpos = root.Position + Vector3.new(0, -1, 0)
	fireVFX("joltfx",
		CFrame.new(stpos + root.CFrame.LookVector * 6.5,
		           stpos + root.CFrame.LookVector * 10))
end

--[[ rowa1 pinned the caster to the victim with a BodyPosition for the whole
	0.6s follow-up, so the second kick could not whiff. Modules/pinTo is that,
	with a guaranteed destructor -- a stranded AlignPosition drags the player
	around permanently and there is no error to notice. ]]

local function useFunc(this:myself)
	local cooldownID = "joltKick"
	if this:canTriggerCD(cooldownID) ~= true then return end

	local humObj  = this._humObj
	local hurtbox = humObj.HurtBox
	local char: any = hurtbox.Parent
	local anim = this:PlayAnim(script.Anim, 0, 1, 1)

	--[[ rowa1 gated on holding a Tool with a Model and then immediately did
		`tool = nil` with the comment "litearlly useless". The gate was
		disabled in the original, so it is not ported. ]]

	local rightLeg = char:FindFirstChild("Right Leg")
	if rightLeg then fireVFX("joltCharge", rightLeg) end

	if this:feintWait(0.62) then
		if anim then anim:Stop() end
		return
	end

	this:useMana()
	this:triggerCD(cooldownID, 8, true)

	joltBurst(hurtbox)

	local _, hits = this:hitbox(CFrame.new(0, 0, -4), Vector3.new(6,6, 7))

	local connected = nil
	for _, enemy in pairs(hits) do
		local attack = this:makeAtk(JOLT, enemy, hurtbox.CFrame.LookVector)
		attack.knockback = this:knockback(attack.atkDir * 14, 0.2, false, -1)
		this:executeAttack(attack)
		if attack:isHit() or attack:isBlocked() then
			connected = enemy
		end
	end

	if connected == nil then
		this:endLag(0.2)
		return
	end

	--[[ CHECK isActive BEFORE THE SECOND BEAT. 0.6s is long enough for the
		victim to die or be destroyed, and a destroyed entity is a bare empty
		table rather than nil (DOC_GOTCHAS) -- so `connected ~= nil` is not
		enough on its own. ]]
	local eroot = connected.HRootPart
	if connected.isActive ~= true or eroot == nil then
		this:endLag(0.2)
		return
	end

	if anim then anim:Stop() end
	this:PlayAnim(script.Anim2, 0.1, 1, 1)

	--[[ !! HRootPart, NOT HurtBox. The pin is an AlignPosition and the
		HurtBox is a massless query volume -- constraining it moves nothing,
		so the caster never actually homed onto the victim and the second
		kick whiffed at range. Exact same slip as StormUp's shockspin.
		Hitboxes are HurtBox-relative; PHYSICS IS HRootPart. ]]
	local myRoot = humObj.HRootPart
	local unpin = pinTo(myRoot, function()
		if eroot.Parent == nil or myRoot.Parent == nil then return nil end
		return eroot.Position - myRoot.CFrame.LookVector * 4
	end, { maxTime = 1.2 })

	--- plain 0.3s beats between the two kicks, exactly as rowa1.
	if this:feintWait(0.3) then
		unpin()
		return
	end

	local leftLeg = char:FindFirstChild("Left Leg")
	if leftLeg then fireVFX("joltCharge", leftLeg) end

	if this:feintWait(0.3) then
		unpin()
		return
	end

	joltBurst(hurtbox)

	if connected.isActive == true then
		local attack = this:makeAtk(JOLT, connected, hurtbox.CFrame.LookVector)
		attack.knockback = this:knockback(attack.atkDir * 14, 0.2, false, -1)
		this:executeAttack(attack)
	end

	unpin()

	-- rowa1 MiniDash(look, 40); bodyForce scales by 5, so 40/5 = 8.
	this:bodyForce(Vector3.new(0, 0, -8), 0.2, true)
	this:endLag(0.2)
end

function module.use(self:myself)
	return baseClass.use(self, useFunc)
end

return table.freeze(module)
