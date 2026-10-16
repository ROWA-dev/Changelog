--!strict
-- EarthStab - a rupture crawls to the target over any surface and erupts as a MAP spike. A hit that would knock kills instead, and the body hangs off the spike.
local baseClass = require(script.Parent.AbilityBase)
export type myself = baseClass.myself
type humObj = baseClass.humObj

local module = {
	Name = "EarthStab"
}
module.__tostring = baseClass.__tostring
module.__index = module
setmetatable(module, { __index = baseClass })

function module.new(humObj:humObj):myself
	return setmetatable(baseClass.new(humObj), module) :: any
end

local dmgUtils  = require(game.ServerScriptService.Utils.DmgUtils)
local dmgFlag   = dmgUtils.dmgFlags
local Targeting = require(game.ServerStorage.ROWA.Modules.Targeting)
local hitSfx    = require(game.ServerStorage.ROWA.Modules.hitSfx)
local crawlMotion = require(game.ReplicatedStorage.Modules.crawlMotion)
local burrow    = require(script.burrow)
local MAP       = workspace:WaitForChild("MAP")

local SPIKE = table.freeze({
	weight  = dmgUtils.weighEnum.Heavy,
	type    = bit32.bor(dmgFlag.blunt, dmgFlag.earth),
	dmg     = 22,
	stun    = 0.8,
	posMult = 3,
	dodgeH  = -0.1,
	onHit   = function(attack)
		local victim = attack.enemyEntity
		hitSfx(victim.HRootPart, "HitCrush", "BladeStab")
		-- no knockdown: after Damage, so Health = 0 still dies through onAttacked with credit (RUPTURE impales them)
		if victim.isKnocked and victim:isKnocked() then victim.Hum.Health = 0 end
		-- a long CAP, ended by landing
		victim.ragdoll:ragdoll(60, true, attack.atkDir * 10)
	end,
})

-- the fist meets the ground on this frame of the anim
local WINDUP   = 0.5
local RANGE    = 80

-- the spike: length, base width, blocks, seconds it stays. Where it roots and its lean are burrow's
local SPIKE_LEN, SPIKE_W, SEGS, SPIKE_LIFE = 14, 4.5, 5, 60
-- how far up it a body it kills is run through, back first so the point comes out of the chest
local IMPALE_AT = SPIKE_LEN - 1.5
local CORNER_UP = CFrame.fromRotationBetweenVectors(Vector3.one.Unit, Vector3.yAxis)

local bodies = OverlapParams.new()
bodies.FilterType = Enum.RaycastFilterType.Include
bodies.FilterDescendantsInstances = { workspace:WaitForChild("Entities") } -- permanent folder, set once (GOTCHAS)

-- each block turns solid and queryable (so carvable) once nobody is inside it: the impaled are never shoved out of it, nor knockBreak'd into it by their own launch
local function solidify(model: Model)
	repeat
		task.wait(0.25)
		local soft = false
		for _, p in model:GetChildren() do
			if not p:IsA("BasePart") or p.CanCollide then continue end
			if #workspace:GetPartBoundsInBox(p.CFrame, p.Size, bodies) == 0 then p.CanCollide, p.CanQuery = true, true else soft = true end
		end
	until not soft or model.Parent == nil
end

-- tapering blocks of the ground up an axis leaning at the victim, each twisted so it reads as rock, a cube on its corner for the point.
-- clients grow it off the blocks' tag and the model's root/born/life attributes, never a sent instance: one born this instant arrives nil under StreamingEnabled
local function spike(c: crawlMotion.state, axis: Vector3)
	local base = CFrame.new(c.pos) * CFrame.fromRotationBetweenVectors(Vector3.yAxis, axis)
	local model = Instance.new("Model")
	model.Name = "EarthSpike"
	model:SetAttribute("root", base)
	model:SetAttribute("born", workspace:GetServerTimeNow())
	model:SetAttribute("life", SPIKE_LIFE)
	local parts = table.create(SEGS + 1)
	local function block(name: string, cf: CFrame, size: Vector3)
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
		p.Material, p.Color, p.Size, p.CFrame = c.hit.Material, c.col, size, cf
		p:AddTag("earthStab")
		p.Parent = model
		table.insert(parts, p)
	end
	local step = SPIKE_LEN / SEGS
	for i = 0, SEGS - 1 do
		local w = SPIKE_W * (1 - i / SEGS) + 0.6
		local twist = CFrame.Angles(math.rad(math.random(-5, 5)), math.random() * math.pi, math.rad(math.random(-5, 5)))
		block("Rock", base * CFrame.new(0, (i + 0.5) * step, 0) * twist, Vector3.new(w, step * 1.3, w))
	end
	-- centred on the last block's top face (1.3x overlap puts it 0.15 step past SPIKE_LEN) and wide enough to swallow it
	block("Tip", base * CFrame.new(0, SPIKE_LEN + step * 0.15, 0) * CORNER_UP, Vector3.one * (SPIKE_W / SEGS + 0.6) * 1.25)
	model.Parent = MAP

	task.spawn(solidify, model)
	-- the originals too: a carved one waits in RuntimeStorage, and regen skips one with no parent
	task.delay(SPIKE_LIFE, function()
		for _, p in parts do p:Destroy() end
		model:Destroy()
	end)
	return parts[SEGS]
end

-- welded under the torso so the corpse clone keeps it (plrObj/makeCorpse); the limbs stay ragdolled and dangle
local function impale(char: Instance, rock: BasePart, c: crawlMotion.state, axis: Vector3)
	local torso = char:FindFirstChild("Torso") :: BasePart?
	if torso == nil then return end
	local w = Instance.new("Weld")
	w.Name = "impale"
	w.Part0, w.Part1 = rock, torso
	w.C0 = rock.CFrame:ToObjectSpace(CFrame.lookAlong(c.pos + axis * IMPALE_AT, axis, c.t))
	w.Parent = torso
end

-- a crawling Projectile (burrow) whose hit volume is the spike it would raise: size.Y is the spike's reach, point included
local RUPTURE = table.freeze({
	class       = burrow,
	speed       = 55,
	accel       = 50,
	maxSpeed    = 100,
	steer       = 5,
	maxDistance = (RANGE + 20) * 2,
	size        = Vector3.new(3, SPIKE_LEN + 2, 3),
	dmgTbl      = SPIKE,
	knockbackForce = 8,
	knockbackLift  = 5,
	knockbackTime  = 0.2,
	fxId        = "earthStab",
	-- every result surfaces the spike, or a dodge lets it circle back and home in again
	onHit       = function(proj: any, attack: any)
		proj:kill(false, true)
		-- exactly where the hit volume was
		local c, axis = burrow.spikeAt(proj.crawl)
		local rock = spike(c, axis)
		-- it killed them; a reflected one killed the caster, who is nowhere near it
		local victim, hum = attack.enemyEntity, attack.enemyEntity.Hum
		if attack:isHit() and victim ~= proj.humObj and hum and hum.Health <= 0 then impale(hum.Parent, rock, c, axis) end
	end,
})

local function useFunc(this:myself)
	local cooldownID = "earthStab"
	if this:canTriggerCD(cooldownID) ~= true then return end

	local humObj  = this._humObj
	local hurtbox = humObj.HurtBox
	local anim = this:PlayAnim(script.Anim, 0, 1, 1)
	humObj.walkSpeed:SetMod(cooldownID, -100)

	if this:feintWait(WINDUP) then
		if anim then anim:Stop(0.1) end
		humObj.walkSpeed:RemoveMod(cooldownID)
		return
	end

	this:useMana()
	this:triggerCD(cooldownID, 12)

	local look = hurtbox.CFrame.LookVector
	local from = hurtbox.Position + look * 2
	local target = Targeting.nearestInDirection(hurtbox.Position, look, humObj, RANGE, Targeting.TIGHT)

	-- no lock: it burrows straight ahead
	local cfg, aim = RUPTURE, from + look
	if target and target.HRootPart then
		local c = table.clone(RUPTURE)
		c.target = target
		cfg, aim = table.freeze(c), target.HRootPart.Position
	end
	this:projectile(cfg, CFrame.lookAt(from, aim))

	this:endLag(0.3)
	humObj.walkSpeed:RemoveMod(cooldownID)
end

function module.use(self:myself)
	return baseClass.use(self, useFunc)
end

return table.freeze(module)
