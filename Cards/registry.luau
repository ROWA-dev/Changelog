--!strict
local Requirements = require(game.ReplicatedStorage.Modules.Requirements)

export type card = {
	name: string,
	desc: string?,
	module: ModuleScript,
	
	innate: boolean?,
	unObtainable: boolean?,

	-- the SAME gate weapons and abilities use. nil = ungated.
	req: Requirements.req?,

	-- claiming this DROPS that card id, i.e. it is an upgrade of it. Pair it with
	-- `req = { card = <same id> }` or the upgrade can be drafted without the base.
	-- Same contract as an ability's `replaces`; DOC_ABILITIES has the long version.
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
		desc = "take 20% less damage against higher hp opponents",
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
		desc = "your basic attacks deal 5% more damage",
		module = manifold.Strength,
		-- 6 strength AND 2 in ANY weapon weight
		req = {
			strength = 6,
			Or = {
				{hvy = 2}, {med = 2}, {lht = 2}
			} :: {Requirements.req}
		},
	},
	[10] = {
		name = "Haki",
		desc = "+15% basic weapon damage, +10% weapon posture damage, +20 posture, +10 max health",
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
		desc = "1 in 5 weapon hits deal double damage, everything else deals 15% less. and a cape",
		module = manifold.Frontliner,
		req = { strength = 4, dexterity = 4 },
	},
	[13] = {
		name = "Six Eyes",
		desc = "+10 max health and 20% faster healing, quadrupled while nearly dead",
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
		desc = "dodging grants a second dodge window, if you keep off the attack",
		module = manifold.QuickStep,
		req = { dexterity = 6 },
	},
	[16] = {
		name = "Many-Handed",
		desc = "commit to a second weapon at once",
		module = manifold.ManyHanded,
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
		-- the UPGRADE shape: gated on owning the flintlock, and it eats it on claim.
		req = { lht = 4, card = 17 }, -- Side Gun
		replaces = 17,
	},
	[19] = {
		name = "Mana Pores",
		desc = "no matter how impenetrable your defense may be, there will always be holes. regain mana upon blocking an attack",
		module = manifold.ManaPores,
		req = { mind = 4 },
	},
	[20] = {
		name = "Frenzied Form",
		desc = "you crave aggression, oppressing all defenses at the cost of your own. dealing damage lowers posture, and 10% less max posture",
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
		desc = "breaking a guard makes them bleed, 1 damage a second for 10 seconds",
		module = manifold.RendingBlow,
		req = { strength = 8 },
	},
	[24] = {
		name = "Bloodletting",
		desc = "heavy attacking a bleeding enemy ends the bleed and heals you for what it had left",
		module = manifold.Bloodletting,
		-- the ELEMENT is spelled `blood`; an unknown name is unsatisfiable, not skipped.
		req = { blood = 8 },
	},
	[25] = {
		name = "Deep Wound",
		desc = "heavy attacking a bleeding enemy extends the bleed by 4 seconds",
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
		module = manifold.Composure,
		req = { fortitude = 4 },
		excludes = { 29 }, -- Second Wind
	},
}
table.freeze(cardList)

local module = {
	--cardList = cardList
}

function module.getCardClass(id:number)
	local sreq:any = require
	local card = cardList[id]
	
	if card == nil then
		error("card_id["..tostring(id).."] does not exist")
	end
	
	local cardClass = sreq(card.module)
	return cardClass
end

function module.getCardName(id:number): string
	local card = cardList[id]
	return card.name
end

-- nil-safe on purpose, unlike getCardName: UI asks for these by id and a card
-- without a desc is normal, not an error
function module.getCardDesc(id:number): string?
	local card = cardList[id]
	return card and card.desc
end

-- nil-safe like getCardDesc: an ungated card is normal, not an error.
function module.getCardReq(id:number): Requirements.req?
	local card = cardList[id]
	return card and card.req
end

-- what claiming `id` DROPS, if it is an upgrade.
function module.getCardReplaces(id:number): number?
	local card = cardList[id]
	return card and card.replaces
end

--- PICK ONE. One line per pair, read left-or-right; owning either hides the other for good.
local EXCLUSIVE = {
	{24, 25}, -- Bloodletting  | Deep Wound
	{26, 27}, -- First Instinct | Adrenaline
	{29, 30}, -- Second Wind   | Composure
}

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

-- card ids that CANNOT be owned alongside this one. Symmetric, so asking either side works.
function module.getCardConflicts(id:number): {number}?
	return conflicts[id]
end

-- which upgrade eats this card, if any. The draft asks so it never re-offers a base
-- card to someone who already upgraded past it (claiming the upgrade clears the base).
function module.getCardSupersededBy(id:number): number?
	return supersededBy[id]
end

-- draftable == obtainable by playing: innate ones are granted at load, unObtainable
-- ones are gifts. Neither needs a new field to say so.
function module.getDraftableCardIds(): {number}
	local ids = {}

	for id, card in pairs(cardList) do
		if card.innate ~= true and card.unObtainable ~= true then
			table.insert(ids, id)
		end
	end
	table.sort(ids)

	return ids
end

function module.getInnateCardIds(): {number}
	local ids = {}

	for id, card in pairs(cardList) do
		if card.innate == true then
			table.insert(ids, id)
		end
	end

	return ids
end

-- ARRAY of {id, name, desc, reqText, req, replaces, excludes}, sorted, NEVER keyed by
-- id: card ids are gapped
-- (26 cards, max id 30) and a gapped numeric table does not survive a remote intact,
-- same rule as Emotes.catalogue. desc falls back to "" because a nil mid-row would
-- gap the ROW the same way. describe() runs HERE, where the card namer is registered:
-- the client has none and would print "card #17" instead of "Side Gun".
-- Draftable only -- innate ones arrive at load, unObtainable ones are gifts.
-- Built once, shared, and lazily: nothing pays for it until a Grimoire opens.
-- The RAW req rides along so the client can draw a bar per gate leaf through
-- Requirements.breakdown; `{}` not nil, because a nil would gap the row AND nil
-- means "inherit" to Requirements while {} means FREE.
local catalogue:{{any}}
function module.catalogue(): {{any}}
	if catalogue == nil then
		local built = {}
		for _, id in ipairs(module.getDraftableCardIds()) do
			local card = cardList[id]
			-- replaces/excludes are NOT part of `req`, so describe never mentions them,
			-- yet eligible() enforces both. "" not nil, or the row gaps.
			local drops = card.replaces and module.getCardName(card.replaces) or ""
			local picks = {}
			for _, other in ipairs(conflicts[id] or {}) do
				table.insert(picks, module.getCardName(other))
			end
			table.insert(built, {id, card.name, card.desc or "", Requirements.describe(card.req),
				card.req or {}, drops, table.concat(picks, ", ")})
		end
		catalogue = table.freeze(built)
	end
	return catalogue
end

-- `req = { card = id }` prints a name instead of a number. Registry is ServerStorage,
-- Requirements is shared, so the name is pushed rather than required.
Requirements.setNamer("card", module.getCardName)

return module
