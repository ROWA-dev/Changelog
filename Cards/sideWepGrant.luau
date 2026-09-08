--!strict
-- util
local baseClass = require(script.Parent:WaitForChild("cardBase"))
local SideWeps = require(game.ServerStorage.ROWA.SideWeps)

return function(sideWepId: number)
	local module = {}
	module.__index = module
	setmetatable(module, { __index = baseClass })

	function module.new(humObj)
		local abstract = baseClass.new(humObj) :: baseClass.myself
		local self = setmetatable(abstract, module) :: any
		self._granted = SideWeps.newSideWep(sideWepId, humObj)
		humObj:EquipSideWep(self._granted)
		return self
	end

	function module.destroy(self: any)
		local humObj = self._humObj
		-- BY INSTANCE, not by name: only clear the slot if MINE is still in it.
		if humObj and humObj.sideWep == self._granted then
			humObj:EquipSideWep(nil)
		end
		baseClass.destroy(self)
	end

	return table.freeze(module)
end
