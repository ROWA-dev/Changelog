--!strict
local wepBase = require(script.WepBase)
export type anyWep = wepBase.myself & {id:number} & any
--export type serialWep = {id:number} & any
type list = {
	[number]: ModuleScript
}

local manifold = script
local wepList:list = {
	[1] = manifold.Light.Fists.Fist,
	[2] = manifold.Medium.Swords.Katana,
	[3] = manifold.Light.Fists.Vise,
	[4] = manifold.Light.Dagger.Canine,
	[5] = manifold.Light.Fists.Rah,
	[6] = manifold.Medium.Staff.bostaff,
	[7] = manifold.Heavy.Hammers.Mace,
	[8] = manifold.Heavy.Hammers.Hammer,
	[9] = manifold.Medium.Spear.Spear,
	[10] = manifold.Medium.Swords.Claymore,
	[11] = manifold.Light.Rapier.Rapier,
	[12] = manifold.Heavy.Greatsword.Executer,
	[13] = manifold.Light.Dagger.Dagger,
	-- rowa1 weapon port. See ServerStorage/rowa1OldPlanToPort/README.md/
	-- PORTW_00_WEAPONS for the checklist. IDS ARE PERSISTED: append only.
	--- Heavy/GreatAxe, NOT Medium/Swords. It was first modelled on Claymore
	--- and moved once it read as an axe closer to Executer. See GreatAxe.
	[14] = manifold.Heavy.GreatAxe.Oblitar,
	[15] = manifold.Heavy.Greatsword.Slayer,
}
table.freeze(wepList)

local module = {
	wepList = wepList
}

function module.getWepClass(id:number)
	local sreq:any = require
	local wep = wepList[id]
	
	if wep == nil then
		error("wep_id["..tostring(id).."] does not exist")
	end
	
	return sreq(wep)
end

function module.newWep(id:number): anyWep
	local wepClass = module.getWepClass(id)
	local itmInst = wepClass.new()
	return itmInst
end

return module
