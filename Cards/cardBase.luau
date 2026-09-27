--!strict
export type myself = {
	_humObj: any,
	_key: string,
	_cons: {any}?,
	_avs: {any}?,
	_until: number?,

	addConnection: (self:myself, con:any) -> (),
	setMod: (self:myself, av:any, n:number) -> (),
	timedMod: (self:myself, av:any, n:number, t:number) -> (),

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

-- undoes everything handed to addConnection/setMod, so most cards need no destroy of their own
function module.destroy(self:myself)
	if self._cons then
		for _, con in self._cons do con:Disconnect() end
	end
	if self._avs then
		for _, av in self._avs do av:RemoveMod(self._key) end
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
