--!strict
-- landing a weapon heavy locks the victim's current or last ability for 2s per damage, multi-hit heavies summed within WINDOW
local baseClass = require(script.Parent:WaitForChild("cardBase"))
local DmgUtils  = require(game.ServerScriptService.Utils.DmgUtils)

export type myself = baseClass.myself & {
	_victim: any,
	_at: number,
	_sum: number,
}

local HEAVY = DmgUtils.dmgFlags.weaponHeavy
local PER_DMG, WINDOW = 2, 0.4
local MIN_LOCK, MAX_LOCK = 30, 240
local CHAIN = script.dispelchain
local TILT, ROW_GAP = math.rad(30), 1
local ENDS = {"Attachment", "Attachment1"}

-- one row per pair of live chains, top down: a pair crosses into an X, a leftover stays flat
local function layout(root: Instance)
	local chains = {}
	for _, c in root:GetChildren() do
		if c.Name == CHAIN.Name then table.insert(chains, c) end
	end
	local n = #chains
	local top = (math.ceil(n / 2) - 1) / 2
	for i, c in chains do
		local row = (i - 1) // 2
		local tilt = if row * 2 + 2 <= n then (if i % 2 == 1 then TILT else -TILT) else 0
		local cf = CFrame.new(0, (top - row) * ROW_GAP, 0) * CFrame.Angles(0, 0, tilt)
		for _, a in ENDS do
			(c :: any)[a].CFrame = cf * (CHAIN :: any)[a].CFrame
		end
	end
end

local module = {}
module.__index = module
setmetatable(module, { __index = baseClass })

function module.new(humObj):myself
	local self:myself = setmetatable(baseClass.new(humObj), module) :: any

	self:addConnection(humObj.onAttack:Connect(function(attack: any)
		if not (attack:isHit() and attack:hasDmgFlag(HEAVY)) then return end
		local victim = attack.enemyEntity
		-- a destroyed ability is a cleared table, so its _cdId reads nil
		local ability = victim and victim.last_ability
		local id = ability and ability._cdId
		-- unregistered id: trigger would pin the lock as its permanent duration
		if id == nil or victim.cooldowns:duration(id) == nil then return end

		-- sliding window off the LAST hit, so every hit of one heavy grows the same lock
		local now, dmg = tick(), attack:CalculateDamage()
		local fresh = victim ~= self._victim or now - self._at > WINDOW
		self._sum = if fresh then dmg else self._sum + dmg
		self._victim, self._at = victim, now
		local lock = math.clamp(self._sum * PER_DMG, MIN_LOCK, MAX_LOCK)
		-- through the ABILITY, not cooldowns, so their hotbar slot draws it
		ability:triggerCD(id, lock)

		-- one chain per locked ability, re-cloned so it lasts as long as that ability's newest lock. makeCorpse strips its beams
		local root = victim.HRootPart
		for _, c in root:GetChildren() do
			if c.Name == CHAIN.Name and c:GetAttribute("id") == id then c:Destroy() end
		end
		local chain = CHAIN:Clone()
		chain:SetAttribute("id", id)
		-- deferred: Destroying fires while it is still parented, so an instant relayout would count it
		chain.Destroying:Connect(function() task.defer(layout, root) end)
		chain.Parent = root
		layout(root)
		if fresh then chain.chains_break:Play() end
		game.Debris:AddItem(chain, lock)
	end), "dispel")

	return self
end

function module.destroy(self:myself)
	self:remConnection("dispel")
	baseClass.destroy(self)
end

return table.freeze(module)
