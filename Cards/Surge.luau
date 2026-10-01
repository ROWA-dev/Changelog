--!strict
-- a clean static hit arcs to the 2 targets most ahead of it within RANGE, FALLOFF weaker per arc until dmg <= 0, skipping anyone static reached in the last LOCKOUT s
local baseClass = require(script.Parent:WaitForChild("cardBase"))
local DmgUtils = require(game.ServerScriptService.Utils.DmgUtils)
local HitBox = require(game.ServerScriptService.HitBox)
local AttackClass = require(game.ServerStorage.ROWA.Class.AttackClass)
local DMGS = require(game.ServerStorage.ROWA.Class.DMGS)
local fireVFX = require(game.ServerStorage.ROWA.Modules.fireVFX)
local hitSfx = require(game.ServerStorage.ROWA.Modules.hitSfx)

export type myself = baseClass.myself

local STATIC = DmgUtils.dmgFlags.static
local RANGE, FALLOFF, HOP, LOCKOUT = 30, 5, 0.07, 1
local BOX = Vector3.one * RANGE * 2

-- entity -> last time static reached it. Shared, so two Surges can't ping-pong one target either
local struck = setmetatable({}, { __mode = "k" }) :: {[any]: number}
-- one arc dmgTbl per dmg value, built on first use
local arcs: {[number]: any} = {}

local function onArcHit(attack: any)
	hitSfx(attack.enemyEntity.HRootPart, "SurgeArc")
end

-- arcs are static too, so the caster's onAttack carries the chain on from their hit
local function arc(caster: any, from: any, to: any, dmg: number)
	local a, b = from.HRootPart, to.HRootPart
	if a == nil or b == nil or caster.isActive ~= true then return end
	local tbl = arcs[dmg] or DMGS.new(DMGS.weighEnum.Light, STATIC, dmg, 0.3, 1, onArcHit)
	arcs[dmg] = tbl
	fireVFX("surge", a, b)
	AttackClass.new(tbl, caster, to, b.Position - a.Position):Execute()
end

local module = {}
module.__index = module
setmetatable(module, { __index = baseClass })

function module.new(humObj):myself
	local self:myself = setmetatable(baseClass.new(humObj), module) :: any

	self:addConnection(humObj.onAttack:Connect(function(attack: any)
		if not (attack:isHit() and attack:hasDmgFlag(STATIC)) then return end
		local from, now = attack.enemyEntity, os.clock()
		struck[from] = now
		local dmg = attack.dmgTbl.dmg - FALLOFF
		local root = from.HRootPart
		if dmg <= 0 or root == nil then return end

		-- the two best aligned with the hit direction, so it chains forward
		local dir, pos = attack.atkDir, root.Position
		local best, second, sBest, sSecond = nil, nil, -math.huge, -math.huge
		for _, e in HitBox.hitbox(CFrame.new(pos), BOX, nil, humObj) do
			local r = e.HRootPart
			if r == nil or e.isActive ~= true or now - (struck[e] or -LOCKOUT) < LOCKOUT then continue end
			local off = r.Position - pos
			local m = off.Magnitude
			if m > RANGE then continue end
			local s = dir:Dot(off) / m
			if s > sBest then
				best, second, sBest, sSecond = e, best, s, sBest
			elseif s > sSecond then
				second, sSecond = e, s
			end
		end

		for _, e in {best, second} do
			struck[e] = now
			task.delay(HOP, arc, humObj, from, e, dmg)
		end
	end))

	return self
end

return table.freeze(module)
