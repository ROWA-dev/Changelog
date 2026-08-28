--!strict
-- bloodChain - hop backwards, spin up a blood chain, hurl it at a locked target; on a connect BOTH parties are yanked to the midpoint, so the hop is a wind-up, not a disengage.
-- the chain WINDS UP as it flies (60 -> 160 studs/s), and parrying REDIRECTS it rather than breaking it.
local baseClass = require(script.Parent.AbilityBase)
export type myself = baseClass.myself
type humObj = baseClass.humObj

local module = {
	Name = "bloodChain"
}
module.__tostring = baseClass.__tostring
module.__index = module
setmetatable(module, { __index = baseClass })

function module.new(humObj:humObj):myself
	local abstract = baseClass.new(humObj) :: baseClass.myself
	local self:myself = setmetatable(abstract, module) :: any
	return self
end

local dmgUtils   = require(game.ServerScriptService.Utils.DmgUtils)
local dmgFlag    = dmgUtils.dmgFlags
local Projectile = require(game.ServerStorage.ROWA.Class.Projectile)
local Targeting  = require(game.ServerStorage.ROWA.Modules.Targeting)
local fireVFX    = require(game.ServerStorage.ROWA.Modules.fireVFX)
local hitSfx     = require(game.ServerStorage.ROWA.Modules.hitSfx)

-- low damage, high posture: a guard-breaking opener, not a damage move. Preserve that shape.
-- !! `blood` is written by NAME, never by bit value.
local CHAIN = {
	weight   = dmgUtils.weighEnum.Heavy,
	type     = bit32.bor(dmgFlag.magic, dmgFlag.blood),
	dmg      = 8,
	stun     = 1,
	posMult  = 3,
	--parryH   = -0.1,
	onHit    = function(attack)
		hitSfx(attack.enemyEntity.HRootPart, "grab")
	end,
}

local WINDUP     = 0.8
local RANGE      = 200
local YANK_TIME  = 1
-- stop pulling once they are this close
local YANK_STOP  = 4
local HOP_FORCE  = 14

-- the mutual yank: two AlignPositions aimed at the midpoint, since bodyForce is fire-and-forget and would overshoot.
-- !! returns a destructor, CALL IT ON EVERY EXIT -- a stranded AlignPosition drags a player around permanently.
local function yankTogether(rootA: BasePart, rootB: BasePart): () -> ()
	local made = {}

	local function pull(part: BasePart)
		local att = Instance.new("Attachment")
		att.Parent = part
		local align = Instance.new("AlignPosition")
		align.Attachment0 = att
		align.Mode = Enum.PositionAlignmentMode.OneAttachment
		align.MaxForce = part.AssemblyMass * 4000
		align.Responsiveness = 40
		align.Parent = part
		table.insert(made, att)
		table.insert(made, align)
		return align
	end

	local alignA, alignB = pull(rootA), pull(rootB)

	local alive = true
	task.spawn(function()
		local endt = tick() + YANK_TIME
		while alive and tick() < endt do
			if rootA.Parent == nil or rootB.Parent == nil then break end
			local mid = (rootA.Position + rootB.Position) / 2
			alignA.Position = mid
			alignB.Position = mid
			-- stop early once they meet
			if (rootA.Position - rootB.Position).Magnitude < YANK_STOP then break end
			task.wait()
		end
		alive = false
		for _, inst in ipairs(made) do inst:Destroy() end
	end)

	return function()
		if not alive then return end
		alive = false
		for _, inst in ipairs(made) do inst:Destroy() end
	end
end

local CHAIN_CFG = table.freeze({
	class       = Projectile.Homing,
	-- winds 60 -> 160 over the flight
	speed       = 60,
	accel       = 100,
	maxSpeed    = 160,
	-- it tracks hard; the chain is not meant to be outrun sideways
	steer       = 8,
	lifetime    = 1,
	maxDistance = 220,
	size        = Vector3.new(3, 3, 3),
	dmgTbl      = CHAIN,
	pierce      = 1,
	-- a chain crosses cover
	stopOnWorld = false,
	-- !! NO fxId: the beam needs the CASTER'S ARM for its near end, and without Attachment0 a Beam renders nothing. bchain is fired by hand below.
	fxId        = nil,
})

local function useFunc(this:myself)
	local cooldownID = "bloodChain"
	if this:canTriggerCD(cooldownID) ~= true then return end

	local humObj  = this._humObj
	local now = tick()

	if now < humObj.stun.Value + 0.4 then -- cant use 0.4s after stun
		return
	end

	if now < humObj._lastBlocked + 0.4 then -- 0.4s
		return
	end
	
	local hurtbox = humObj.HurtBox
	local char: any = hurtbox.Parent
	local anim = this:PlayAnim(script.Anim, 0, 1, 1)
	-- the fx module KEYS ON this part, so all four stages must be handed the same one. Looked up once.
	local arm = char:FindFirstChild("Right Arm")

	-- the backward wind-up hop, root-relative so it follows your facing
	local hop = this:bodyForce(Vector3.new(0, 0.5, 1).Unit * HOP_FORCE, 0.3, true)

	fireVFX("bchainWindup", humObj.HRootPart, arm, WINDUP)

	if this:feintWait(WINDUP) then
		if anim then anim:Stop(0.1) end
		if hop then hop:destroy() end
		fireVFX("bchainWindup", nil, nil, 0)
		return
	end

	this:useMana()
	this:triggerCD(cooldownID, 12, true)

	-- aimed slightly DOWN: the chain is thrown at chest height, not along the eyeline.
	local aimDir = (hurtbox.CFrame.LookVector + Vector3.new(0, -0.3, 0)).Unit
	local target = Targeting.nearestInDirection(
		hurtbox.Position, aimDir, humObj, RANGE, Targeting.TIGHT)

	-- no target: refund most of the cost.
	if target == nil or target.HRootPart == nil then
		this:triggerCD(cooldownID, 2)
		this:endLag(0.2)
		return
	end

	local myRoot = humObj.HRootPart
	local cfg = table.clone(CHAIN_CFG)
	cfg.target = target
	cfg.onHit = function(proj, attack)
		-- PARRIED: the chain is SLAPPED ASIDE, not cut -- whipped onto somebody else it keeps the read and hands the parrier the aim.
		if attack:isParried() then
			local proot = attack.enemyEntity.HRootPart
			if proot == nil then
				Projectile.kill(proj)
				return
			end
			local look = proot.CFrame.LookVector
			-- !! passing the CASTER here excludes both people the chain must not pick: the caster (zero-length draw) and the parrier (search origin, distance 0).
			local newTarget = Targeting.nearestInDirection(
				proot.Position, look, humObj, RANGE, Targeting.TIGHT)
			-- blended heading with the head-on case handled. See parryDir.
			proj:deflect(proj:parryDir(look), newTarget, 0.15, attack.enemyEntity)
			-- no fxId (see CHAIN_CFG), so stage 3 is how the drawn chain is turned.
			fireVFX("bchain", 3, arm, proj.pos, proj.dir,
				newTarget and newTarget.HRootPart or nil)
			return
		end

		if not attack:isHit() then
			-- only a DODGE keeps it flying; anything else ends it
			if not attack:isDodged() then Projectile.kill(proj) end
			return
		end

		local eroot = attack.enemyEntity.HRootPart
		if eroot == nil or myRoot == nil or myRoot.Parent == nil then return end

		-- a DEFLECTED chain can run back into its own thrower, and there is nothing to yank in that case, so it takes its damage and drops.
		if eroot == myRoot then
			Projectile.kill(proj)
			return
		end

		fireVFX("bchainYank", myRoot, eroot)
		-- LATCH the flying chain onto them for the pull, or the yank plays with nothing visibly connecting the two.
		fireVFX("bchain", 2, arm, eroot, YANK_TIME)
		local release = yankTogether(myRoot, eroot)
		-- hard stop: the yank must never outlive its own window
		task.delay(YANK_TIME + 0.2, release)
	end

	local originCF = CFrame.new(myRoot.Position, target.HRootPart.Position)

	local p = this:projectile(table.freeze(cfg), originCF)

	-- fired by hand because the beam's NEAR end must be the caster's hand, and AFTER the projectile so the chain can be handed its `id`.
	fireVFX("bchain", 1, originCF, CHAIN_CFG.speed, CHAIN_CFG.maxDistance,
		{ steer = CHAIN_CFG.steer, accel = CHAIN_CFG.accel,
			maxSpeed = CHAIN_CFG.maxSpeed },
		arm, target.HRootPart, p and p.id)

	this:endLag(0.25)
end

function module.use(self:myself)
	return baseClass.use(self, useFunc)
end

return table.freeze(module)
