--!strict
--[[ Turns incoming projectiles aside in flight. Uses `deflect` because it
already re-points the shot, drops the homing lock, opens a grace window and
calls tellClients (so the drawn copy corrects itself), clears `seen`, grants
one bounce and sets `deflected` for the next hit. Not a hit-time abort:
beforeAttacked is too late, and aborting spends pierce, which reads as an
absorb rather than a miss. ]]

local baseClass = require(script.Parent:WaitForChild("cardBase"))
local Projectile = require(game.ServerStorage.ROWA.Class.Projectile)
local RunService = game:GetService("RunService")

export type myself = baseClass.myself & {}

local module = {}
module.__index = module
setmetatable(module, { __index = baseClass })

-- Must clear hurtbox half-diagonal + widest projectile half-diagonal (RPG's
-- (4,4,12) = 6.63). Raise if a bigger projectile is added; to balance, lower
-- ENGAGE. Hurtbox half is read live because hurtboxSize is an AdditiveValue.
local BIGGEST_PROJ = 7

-- margin over exact grazing so one deflect settles it; exact grazing can
-- leave the ray inside by float error and stutter on re-deflect
local CLEAR = 1.3

-- studs of run-up, purely how it reads; `speed * dt` below is the hard floor
local ENGAGE = 70

local CONN_ID = "projEvade"

-- Turn `dir` aside until the forward ray grazes the sphere; nil if it already
-- misses (one packet per shot, not per frame). asin(r/d) is a property of the
-- line, so unlike a force it holds at any speed.
local function turnAside(pos: Vector3, dir: Vector3, toC: Vector3, d: number,
	r: number): Vector3?
	local along = dir:Dot(toC)
	if along <= 0 then return nil end -- past it or moving away

	local need = if d <= r then math.pi * 0.5 else math.asin(math.clamp(r / d, -1, 1))
	local cur = math.acos(math.clamp(along, -1, 1))
	local delta = need - cur
	if delta <= 1e-4 then return nil end -- already clears the sphere

	-- dir x toC turns toward the centre, hence the negative angle; degenerates
	-- head-on, so fall back to any perpendicular axis
	local axis = dir:Cross(toC)
	if axis.Magnitude <= 1e-6 then
		axis = toC:Cross(Vector3.yAxis)
		if axis.Magnitude <= 1e-6 then
			axis = toC:Cross(Vector3.xAxis)
		end
	end
	return CFrame.fromAxisAngle(axis.Unit, -delta):VectorToWorldSpace(dir)
end

function module.new(humObj):myself
	local abstract = baseClass.new(humObj) :: baseClass.myself
	local self:myself = setmetatable(abstract, module) :: any

	self:addConnection(RunService.Heartbeat:Connect(function()
		if Projectile.activeCount() == 0 then return end

		local anchor = humObj.HurtBox or humObj.HRootPart
		if anchor == nil or anchor.Parent == nil then return end
		local centre = anchor.Position
		local far = (anchor.Size.Magnitude * 0.5 + BIGGEST_PROJ) * CLEAR

		Projectile.forEach(function(p)
			if p.humObj == humObj then return end -- own shots aren't incoming

			local rel = centre - p.pos
			local d = rel.Magnitude
			if d < 1e-3 then return end

			-- engage before the frame it would cross in; Heartbeat gives no
			-- dt, so bound it
			if d > math.max(ENGAGE, far + p.speed * 0.1) then return end

			local newDir = turnAside(p.pos, p.dir, rel / d, d, far)
			if newDir == nil then return end

			p:deflect(newDir)
		end)
	end), CONN_ID)

	return self
end

-- must run before baseClass.destroy clears the table, while _humObj and
-- randID still exist to name the connection with
function module.destroy(self:myself)
	self:remConnection(CONN_ID)
	baseClass.destroy(self)
end

return table.freeze(module)