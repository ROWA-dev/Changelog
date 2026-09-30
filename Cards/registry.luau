--!strict
local Requirements = require(game.ReplicatedStorage.Modules.Requirements)

export type card = {
	name: string,
	desc: string?,
	module: ModuleScript?, -- nil = a bare cardBase, for cards that are only `mods`
	-- AdditiveValue name on the humObj -> amount, set through the card so it comes off with it
	mods: {[string]: number}?,
	
	innate: boolean?,
	unObtainable: boolean?,

	-- the SAME gate weapons and abilities use. nil = ungated.
	req: Requirements.req?,

	-- claiming this DROPS that card id, i.e. it is an upgrade of it. Pair it with
	-- `req = { card = <same id> }` or the upgrade can be drafted without the base.
	-- Same contract as an ability's `replaces`; ABILITIES has the long version.
	replaces: number?,

	-- PICK ONE: owning either side hides the other for good. Made symmetric below, so
	-- declare it on the LATER id of the pair and it never points at an unwritten entry.
	excludes: {number}?,
}

type clType = {
	[number]: card
}

local manifold = script

local cardList:clType = {
	[1] = {
		name = "Underdog",
		desc = "take 15% less damage from opponents with more health than you",
		module = manifold.Underdog,
		innate = true,
	},
	[2] = {
		name = "Ping Compensation",
		desc = "yields incoming attacks based on the victim's ping, normalizing the time they get to react",
		module = manifold.PingCompensation,
		innate = true,
	},
	[3] = {
		name = "Quick Reflex",
		desc = "1 second speedboost upon parrying",
		module = manifold.SpeedOnParry,
		innate = true,
	},
	[4] = {
		name = "Supreme Limiter",
		module = manifold.Heavenly_Limiter_of_Air,
		unObtainable = true
	},
	[5] = {
		name = "HEAVEN'S FULL CRESCENT MOON",
		module = manifold.Nick_Amplifier,
		unObtainable = true
	},
	[6] = {
		name = "The Necessary Correction",
		desc = "grants the newly arrived power to challenge the seasoned",
		module = manifold.HeavensEqualizer,
		innate = true,
	},
	[7] = {
		name = "Matias Catalyst",
		module = manifold.Mat_Amplifier,
		unObtainable = true
	},
	[8] = {
		name = "Divine Protection of Projectile Evasion",
		desc = "incoming projectiles bend away and miss",
		module = manifold.ProjectileEvasion,
		unObtainable = true
	},
	[9] = {
		name = "Strength",
		desc = "your basic attacks deal 5% more weapon damage",
		mods = { wepDmgMult = 0.05 }, -- AttackClass reads it for weapon attacks only
		req = {
			strength = 6,
			Or = {
				{hvy = 2}, {med = 2}, {lht = 2}
			} :: {Requirements.req}
		},
	},
	[10] = {
		name = "Haki",
		desc = "+10% weapon damage, +10% weapon posture damage, +20 posture, +10 max health",
		module = manifold.Haki,
		req = { strength = 6, fortitude = 4 },
	},
	[11] = {
		name = "Shield",
		desc = "+40 max posture and a shield that replaces your block stance",
		module = manifold.Shield,
		req = { fortitude = 6 },
	},
	[12] = {
		name = "Frontliner",
		desc = "1 in 5 weapon hits deal 1.5x damage, non-weapon attacks deal 15% less. and a cape",
		module = manifold.Frontliner,
		req = { strength = 4, dexterity = 4 },
	},
	[13] = {
		name = "Six Eyes",
		desc = "+10 max health and 20% faster healing, 4x faster knockdown recovery. Abilities cost HALF mana. Exclusive with Saringan",
		module = manifold.SixEye,
		req = { mind = 6 },
	},
	[14] = {
		name = "Fortitude",
		desc = "+40 max health",
		module = manifold.Fortitude,
		req = { fortitude = 8 },
	},
	[15] = {
		name = "Quick Step",
		desc = "dodging grants a second dodge window, if you keep off the attack. one chain evades 40 damage",
		module = manifold.QuickStep,
		req = { dexterity = 8 },
	},
	[16] = {
		name = "Many-Handed",
		desc = "+1 equippable weapons",
		mods = { maxWeapons = 1 }, -- read on commit, so losing it trims nothing until the next wield
		-- spread, not depth: 4 TOTAL across hvy/med/lht, however it is split.
		req = { dexterity = 2, mind = 2, sum = { weaponStats = 4 } },
	},
	[17] = {
		name = "Side Gun",
		desc = "a flintlock on your off hand. 3 shots, then reload",
		module = manifold.SideGun,
		req = { lht = 4 },
	},
	[18] = {
		name = "Side Shotgun",
		desc = "a sawn-off on your off hand. 3 shells, wider and meaner up close",
		module = manifold.SideShotgun,
		req = { lht = 4, card = 17 }, -- Side Gun
		replaces = 17,
	},
	[19] = {
		name = "Mana Pores",
		desc = "regain mana upon blocking an attack",
		module = manifold.ManaPores,
		req = { mind = 2 },
	},
	[20] = {
		name = "Frenzied Form",
		desc = "hits you land also drain their posture by half the damage dealt. downside: -20 max posture",
		module = manifold.FrenziedForm,
		req = { strength = 4 },
	},
	[21] = {
		name = "Splinter Guard",
		desc = "parrying a strong attack sprays it outward. hits everyone around you except the one you parried",
		module = manifold.SplinterGuard,
		req = { fortitude = 4 },
	},
	[22] = {
		name = "Counterweight",
		desc = "parrying restores 25% more posture",
		module = manifold.Counterweight,
		req = { fortitude = 4 },
	},
	[23] = {
		name = "Rending Blow",
		desc = "breaking a guard makes them bleed, 1 DPS for 10 seconds",
		module = manifold.RendingBlow,
		req = { strength = 8 },
	},
	[24] = {
		name = "Bloodletting",
		desc = "heavy attacking a bleeding enemy ends the bleed and heals you 2x the bleed dmg",
		module = manifold.Bloodletting,
		-- the ELEMENT is spelled `blood`; an unknown name is unsatisfiable, not skipped.
		req = { blood = 8 },
	},
	[25] = {
		name = "Deep Wound",
		desc = "heavy attacking a bleeding enemy extends the bleed by 8 seconds",
		module = manifold.DeepWound,
		req = { blood = 5 },
		excludes = { 24 }, -- Bloodletting
	},
	[26] = {
		name = "First Instinct",
		desc = "the first hit to put you in combat is dodged",
		module = manifold.FirstInstinct,
		req = { dexterity = 8 },
	},
	[27] = {
		name = "Adrenaline",
		desc = "the first hit to put you in combat grants 10 seconds of speed",
		module = manifold.Adrenaline,
		req = { dexterity = 4 },
		excludes = { 26 }, -- First Instinct
	},
	[28] = {
		name = "Piercing Chill",
		desc = "chilled enemies take 5% more damage from you",
		module = manifold.PiercingChill,
		req = { ice = 7 },
	},
	[29] = {
		name = "Second Wind",
		desc = "posture below half recovers twice as fast",
		module = manifold.SecondWind,
		req = { fortitude = 6 },
	},
	[30] = {
		name = "Composure",
		desc = "posture recovers 25% faster",
		mods = { postureHeal = 0.5 }, -- 25% of the base 2
		req = { fortitude = 4 },
		excludes = { 29 }, -- Second Wind
	},
	[31] = {
		name = "Emperor Flame",
		desc = "Strong knockback burns both fighters and detonates on the victim.",
		module = manifold.EmperorFlame,
		req = { flame = 9, strength = 1 },
	},
	[32] = {
		name = "Dispel",
		desc = "landing a weapon heavy puts the ability they are using, or last used, on cooldown for 2 seconds per damage dealt, 30 seconds to 4 minutes",
		module = manifold.Dispel,
		req = { dark = 8 },
	},
	[33] = {
		name = "Purity",
		desc = "harmful status effects on you last half as long and half as strong",
		module = manifold.Purity,
		req = { light = 4 },
	},
	[34] = {
		name = "Charisma",
		desc = "all your hits charm, charmed enemies deal 10% less damage to you",
		module = manifold.Charisma,
		req = { mind = 3 },
	},
	[35] = {
		name = "Azure Flames",
		desc = "your fire moves deal 20% more damage, your burns are 50% stronger, and your fire burns bright blue",
		module = manifold.AzureFlames,
		req = { flame = 4, mind = 4 },
	},
	[36] = {
		name = "Will Power",
		desc = "+20 max health. immune to charm from anyone with equal or less mind than you",
		module = manifold.WillPower,
		req = { mind = 2, fortitude = 3 },
	},
	[37] = {
		name = "All For One",
		desc = "your weapon hits take a random card from whoever you hit, once a second",
		module = manifold.AllForOne,
		unObtainable = true
	},
}
table.freeze(cardList)

local module = {}

function module.newCard(id:number, humObj:any)
	local card = cardList[id]
	if card == nil then
		error("card_id["..tostring(id).."] does not exist")
	end
	local sreq:any = require
	local obj = sreq(card.module or manifold.cardBase).new(humObj)
	if card.mods then
		for stat, n in card.mods do obj:setMod(humObj[stat], n) end
	end
	return obj
end

-- "unknown #id" for an id that left the registry: ids are persisted, so a stale one must not throw
function module.getCardName(id:number): string
	local card = cardList[id]
	return if card then card.name else "unknown #" .. tostring(id)
end

-- the frozen row, nil for an unknown id
function module.get(id:number): card?
	return cardList[id]
end

-- draftable == obtainable by playing: innate ones are granted at load, unObtainable ones are gifts
function module.isDraftable(id:number): boolean
	local card = cardList[id]
	return card ~= nil and card.innate ~= true and card.unObtainable ~= true
end

-- reverse of replaces, built once from the registry. Requires NOTHING.
local supersededBy: {[number]: number} = {}
-- exclusions, made SYMMETRIC here so a pair is declared once and neither side can drift.
local conflicts: {[number]: {number}} = {}
local function addConflict(a: number, b: number)
	local list = conflicts[a]
	if list == nil then list = {} conflicts[a] = list end
	if not table.find(list, b) then table.insert(list, b) end
end
for id, card in pairs(cardList) do
	if card.replaces then supersededBy[card.replaces] = id end
	for _, other in ipairs(card.excludes or {}) do
		addConflict(id, other)
		addConflict(other, id)
	end
end
table.freeze(supersededBy)
table.freeze(conflicts)

-- symmetric at load, so asking either side of a pair works.
function module.getCardConflicts(id:number): {number}?
	return conflicts[id]
end

-- which upgrade eats this card, if any. The draft asks so it never re-offers a base
-- card to someone who already upgraded past it (claiming the upgrade clears the base).
function module.getCardSupersededBy(id:number): number?
	return supersededBy[id]
end

-- built once and frozen, ascending, like Abilities.getIds
local draftable, innate = {}, {}
for id, card in cardList do
	if card.innate == true then
		table.insert(innate, id)
	elseif module.isDraftable(id) then
		table.insert(draftable, id)
	end
end
table.sort(draftable)
table.freeze(draftable)
table.freeze(innate)

function module.getDraftableCardIds(): {number}
	return draftable
end

function module.getInnateCardIds(): {number}
	return innate
end

-- ARRAY of {id, name, desc, reqText, req, replaces, excludes}, never KEYED by id: they
-- are gapped, and a gapped numeric table does not survive a remote intact.
local catalogue:{{any}}
function module.catalogue(): {{any}}
	if catalogue == nil then
		local built = {}
		for _, id in ipairs(module.getDraftableCardIds()) do
			local card = cardList[id]
			-- replaces/excludes are NOT part of `req`, so describe never mentions them; eligible() does.
			local drops = card.replaces and module.getCardName(card.replaces) or ""
			local picks = {}
			for _, other in ipairs(conflicts[id] or {}) do
				table.insert(picks, module.getCardName(other))
			end
			-- describe() runs HERE, where the namer is; a client prints "card #17" instead.
			-- DENSE: "" and {} never nil -- a nil gaps the row, and a nil req means INHERIT.
			table.insert(built, {
				id,
				card.name,
				card.desc or "",
				Requirements.describe(card.req),
				card.req or {},
				drops,
				table.concat(picks, ", ")
			})
		end
		catalogue = table.freeze(built)
	end
	return catalogue
end

-- `req = { card = id }` prints a name instead of a number. Registry is ServerStorage,
-- Requirements is shared, so the name is pushed rather than required.
Requirements.setNamer("card", module.getCardName)

return module
