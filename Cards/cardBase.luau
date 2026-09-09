--!strict
local humObjClass = require(game.ServerStorage.ROWA.Class.HumObj)
export type humObjTyp = humObjClass.myself
export type myself = {
	_humObj: humObjTyp,
	randID: number,
	
	addConnection: (self:myself, con:any, id:string) -> (),
	remConnection: (self:myself, id:string) -> (),
	
	new: (humObj:humObjTyp)->myself,
	destroy: (self:myself)->(),
}

local module = {
	Name = "Card Base",
}
module.__index = module

function module.new(humObj:humObjTyp):myself
	local randID = math.random(1, 65536)
	local self = setmetatable({
		_humObj = humObj,
		randID = randID
	}, module) :: any&myself
	return self
end

function module.destroy(self:myself)
	table.clear(self)
	setmetatable(self, nil)
end

--

local CONNECTION_PREFIX = "c_"
function module.addConnection(self:myself, con:any, id:string)
	if self._humObj == nil then return end -- TODO disconnect con if humobj doesnt exist??
	self._humObj:AddConnection(con, CONNECTION_PREFIX..id..tostring(self.randID))
end

function module.remConnection(self:myself, id:string)
	if self._humObj == nil then return end -- TODO disconnect con if humobj doesnt exist??
	self._humObj:RemConnection(CONNECTION_PREFIX..id..tostring(self.randID))
end

return table.freeze(module)
