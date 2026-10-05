--!strict
export type myself = {
	_humObj: any,
	_key: string,
	_cons: {any}?,
	_avs: {any}?,
	_until: number?,
	_hp: number?,
	_knobs: {[string]: number}?,

	addConnection: (self:myself, con:any) -> (),
	setMod: (self:myself, av:any, n:number) -> (),
	timedMod: (self:myself, av:any, n:number, t:number) -> (),
	addMaxHealth: (self:myself, n:number) -> (),

	new: (humObj:any)->myself,
	destroy: (self:myself)->(),
}

local module = {}
module.__index = module

local nextKey = 0
function module.new(humObj:any):myself
	nextKey += 1
	return setmetatable({ _humObj = humObj, _key = "card" .. nextKey }, module) :: any
end

-- undoes everything handed to addConnection/setMod/addMaxHealth and the row's knobs, so most cards need no destroy of their own
function module.destroy(self:myself)
	local hp = self._hp
	local hum:Humanoid? = hp and self._humObj.Hum
	if hp and hum and hum.Parent then
		hum.MaxHealth = math.max(1, hum.MaxHealth - hp)
		hum.Health = math.min(hum.Health, hum.MaxHealth)
	end
	if self._cons then
		for _, con in self._cons do con:Disconnect() end
	end
	if self._avs then
		for _, av in self._avs do av:RemoveMod(self._key) end
	end
	if self._knobs then
		for k in self._knobs do self._humObj[k] = nil end
	end
	table.clear(self)
	setmetatable(self, nil)
end

function module.addConnection(self:myself, con:any)
	local cons = self._cons
	if cons == nil then cons = {} self._cons = cons end
	table.insert(cons, con)
end

-- keyed by this card instance; setting the same AdditiveValue again replaces
function module.setMod(self:myself, av:any, n:number)
	av:SetMod(self._key, n)
	local avs = self._avs
	if avs == nil then avs = {} self._avs = avs end
	if not table.find(avs, av) then table.insert(avs, av) end
end

-- +n MaxHealth and Health now, taken back by destroy
function module.addMaxHealth(self:myself, n:number)
	local hum:Humanoid? = self._humObj.Hum
	if hum == nil or hum.Parent == nil then return end
	hum.MaxHealth += n
	hum.Health = math.min(hum.Health + n, hum.MaxHealth)
	self._hp = (self._hp or 0) + n
end

-- setMod that comes off t seconds after the LAST call, so a re-trigger extends instead of being cut short
function module.timedMod(self:myself, av:any, n:number, t:number)
	self:setMod(av, n)
	local stamp = tick() + t
	self._until = stamp
	task.delay(t, function()
		if self._until == stamp then av:RemoveMod(self._key) end
	end)
end

return table.freeze(module)
