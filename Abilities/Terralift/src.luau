--!strict
-- Terralift - bites the ground the caster stands on out of the map and flies it for LIFE s, climbing out of its crater for the first RISE s: WASD steers, jump/crouch climb/sink (its `steer` remote, fired by VFXQuiver/terralift), players on it ride (init/train/ride).
-- casting again or a stun drops it, like a lever, and it shatters (client side); the cooldown runs from the drop. Only off breakable ground right underfoot.
local baseClass = require(script.Parent.AbilityBase)
export type myself = baseClass.myself
type humObj = baseClass.humObj

local module = {
	Name = "Terralift",
	manaUse = 40,
}
module.__tostring = baseClass.__tostring
module.__index = module
setmetatable(module, { __index = baseClass })

function module.new(humObj:humObj):myself
	return setmetatable(baseClass.new(humObj), module) :: any
end

local RS = game:GetService("RunService")
local Destruction = require(game.ServerStorage.ROWA.Destruction_Stable.Destruction)
local glide = require(game.ReplicatedStorage.Modules.glide)
local ground = require(game.ReplicatedStorage.Modules.aimPoint).params -- the world, never bodies or fx
local MAP = workspace:WaitForChild("MAP")

local CD_ID = "terralift"
local WINDUP = 0.5
local RADIUS, MINSZ = 20, 6
local LIFE, CD, FIZZLE_CD = 60, 20, 2
local RISE = 3 -- ~22 studs up at WARM_ACCEL, clear of the 20 deep crater
local WARM, WARM_ACCEL = 8, 2.5 -- s it's sluggish for at first, as if warming up, and its accel then (studs/s^2: full speed in 8s)
local CLIMB, SINK = Vector3.new(18, 7, 18), Vector3.new(18, 20, 18) -- studs/s per steer axis, climbing or sinking: it's heavy, so it sinks faster than it climbs
local DOWN = Vector3.new(0, -4.5, 0) -- root to just under the feet
local GONE = 1 -- s the server's copy outlives the drop, so clients still have it to shatter

local function fly(this: myself, at: Vector3, chunks: { Destruction.chunk })
	local humObj = this._humObj
	local me: any = this
	-- the bite welded to a small anchored pin, `base`, the only part moved (server here, each client off glide), so carving it is DESTRUCTION's boat case.
	-- in its own Folder, which is where pieces cut off it fall, so the drop takes them too
	local folder = Instance.new("Folder")
	folder.Name = "Terralift"
	local rock = Instance.new("Model")
	rock.Name = "Rock"
	rock.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	local base = Instance.new("Part")
	base.Name = "base"
	base.Size, base.CFrame = Vector3.new(2, 2, 2), CFrame.new(at)
	base.Anchored, base.CanCollide, base.CanTouch, base.Transparency = true, false, false, 1
	base:AddTag("nodestroy")
	base.Parent = rock
	rock.PrimaryPart = base
	for _, c in chunks do
		local p = Instance.new("Part")
		p.Size, p.CFrame, p.Color, p.Material = c.size, c.cf, c.color, c.material
		p:AddTag("breakable") -- per part, not the Model, like the train: reglue would take `hitbox` for a piece
		local w = Instance.new("WeldConstraint")
		w.Name = "DestWeld"
		w.Part0, w.Part1 = base, p
		w.Parent = p
		p.Parent = rock
	end
	-- init/train/ride keeps an airborne rider on it while inside this
	local cf, size = rock:GetBoundingBox()
	local hb = Instance.new("Part")
	hb.Name = "hitbox"
	hb.CFrame, hb.Size = cf, size
	hb.CanCollide, hb.CanQuery, hb.CanTouch, hb.Massless, hb.Transparency = false, false, false, true, 1
	local w = Instance.new("WeldConstraint")
	w.Part0, w.Part1 = base, hb
	w.Parent = hb
	hb.Parent = rock
	local pilot: Player? = humObj.plrObj and humObj.plrObj.Plr
	rock:SetAttribute("by", if pilot then pilot.UserId else 0) -- 0 for an NPC
	-- the pilot's input: on the rock, so it lives and dies with it and nothing core carries it
	local steer = Instance.new("RemoteEvent")
	steer.Name = "steer"
	steer.Parent = rock
	glide.steer(rock, workspace:GetServerTimeNow(), Vector3.zero, at, WARM_ACCEL)
	rock:AddTag("terralift")
	rock.Parent = folder
	folder.Parent = MAP

	local ends, rise, warm = os.clock() + LIFE, os.clock() + RISE, os.clock() + WARM
	local vT, want, accel: number? = Vector3.zero, Vector3.zero, WARM_ACCEL
	steer.OnServerEvent:Connect(function(plr: Player, s: any)
		if plr == pilot and typeof(s) == "Vector3" and s.Magnitude <= 1.5 then want = s * (if s.Y < 0 then SINK else CLIMB) end -- also rejects NaN
	end)
	local conn: RBXScriptConnection
	local function drop()
		conn:Disconnect()
		rock:RemoveTag("terralift") -- clients stop drawing it and shatter it
		game.Debris:AddItem(folder, GONE)
		me.lift = nil
		if this._humObj and humObj.isActive then this:triggerCD(CD_ID, CD) end -- not on a destroyed ability or caster
	end
	conn = RS.PreSimulation:Connect(function()
		if humObj.isActive ~= true or os.clock() > ends or humObj:inStun() then return drop() end -- isActive first: inStun throws on a destroyed one
		local now = workspace:GetServerTimeNow()
		local w = if os.clock() < rise then Vector3.new(want.X, CLIMB.Y, want.Z) else want
		local a = if os.clock() < warm then WARM_ACCEL else nil -- warmed up: one re-anchor onto glide's ACCEL
		if w ~= vT or a ~= accel then
			vT, accel = w, a
			glide.steer(rock, now, vT, nil, a)
		end
		base.CFrame = CFrame.new((glide.at(rock, now))) -- no velocity: it would replicate every ramp just for NPC riders, who aren't carried
	end)
	me.lift = drop
end

local function useFunc(this: myself)
	local humObj = this._humObj
	local root = humObj.HRootPart
	if workspace:Raycast(root.Position, DOWN, ground) == nil then return end

	local anim = this:PlayAnim(script.Anim, 0, 1, 1)
	humObj.walkSpeed:SetMod(CD_ID, -100)
	if this:feintWait(WINDUP) then
		if anim then anim:Stop(0.1) end
		humObj.walkSpeed:RemoveMod(CD_ID)
		return
	end
	humObj.walkSpeed:RemoveMod(CD_ID)

	local hit = workspace:Raycast(root.Position, DOWN, ground)
	local chunks = hit and select(2, Destruction.Grab(nil, CFrame.new(hit.Position), Vector3.one * RADIUS * 2, MINSZ, nil, math.huge))
	if not hit or not chunks or #chunks == 0 then -- nothing breakable underfoot: the cheap tier, no mana
		if anim then anim:Stop(0.1) end
		this:triggerCD(CD_ID, FIZZLE_CD) -- no dontOverwrite: under it a registered 20 would win
		return
	end

	this:useMana()
	fly(this, hit.Position, chunks)
	this:endLag(0.3)
end

function module.use(self: myself)
	local lift = (self :: any).lift
	if lift then lift() return true end
	-- the cd guard sits here, not in useFunc: the press that dropped it retries for 0.2s (UseAbility) and must not hit the mana check's noMana tell
	if self:canTriggerCD(CD_ID) ~= true then return false end
	return baseClass.use(self, useFunc)
end

return table.freeze(module)
