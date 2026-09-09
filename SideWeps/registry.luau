--!strict
--[[ SideWeps - the OFF-HAND registry. id -> module, lazily required.

	Same shape as Weps.luau: nothing here loads a side weapon to answer "what
	exists". IDS ARE PERSISTED (a card names one by id): append only, never
	renumber, never reuse.

	A side weapon is worn on the left arm, is NOT in the wielded set, and owns
	exactly one action, fired by the `sideWep` bind. Shield has no action and is
	still one of these: what makes it a side weapon is the arm, not the attack.
]]
local sideWepBase = require(script.SideWepBase)
export type anySideWep = sideWepBase.myself & any

local manifold = script
local sideWepList: {[number]: ModuleScript} = {
	[1] = manifold.Shield,
	[2] = manifold.SideGun,
	[3] = manifold.SideShotgun,
}
table.freeze(sideWepList)

local module = {}

function module.getSideWepClass(id: number)
	local sreq: any = require
	local sideWep = sideWepList[id]
	if sideWep == nil then
		error("sideWep_id[" .. tostring(id) .. "] does not exist")
	end
	return sreq(sideWep)
end

--- `newSideWep`, not `new`: on a REGISTRY that name would read as constructing the
--- registry itself. Same shape as Weps.newWep / Items.newItem / Abilities.newAbility.
function module.newSideWep(id: number, humObj: any): anySideWep
	return module.getSideWepClass(id).new(humObj)
end

return module
