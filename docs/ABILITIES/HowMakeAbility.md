# HowMakeAbility — the 5-minute version

*(index: parent `ServerStorage/README.md/ABILITIES.md`)*

Cookbook. Every rule here has a reason and the reason is in ABILITIES.md —
this file is just the order you do things in.

## 1. Make the ModuleScript

In `ServerStorage/ROWA/Abilities/`, named exactly what the ability is called.
Drop its assets in as **children**: `Anim`, sounds, particle emitters, parts.
The ability clones them at runtime; nothing is shared with other abilities.

## 2. Copy this

```lua
--!strict
local baseClass = require(script.Parent.AbilityBase)
export type myself = baseClass.myself
type humObj = baseClass.humObj

local module = { Name = "MyAbility" }   -- == script.Name, always
module.__tostring = baseClass.__tostring
module.__index = module
setmetatable(module, { __index = baseClass })

function module.new(humObj:humObj):myself
	return setmetatable(baseClass.new(humObj), module) :: any
end

local dmgUtils = require(game.ServerScriptService.Utils.DmgUtils)
local dmgFlag  = dmgUtils.dmgFlags
local hitSfx   = require(game.ServerStorage.ROWA.Modules.hitSfx)

-- built ONCE, at module scope, never per cast
local DMG = {
	weight   = dmgUtils.weighEnum.Heavy,      -- Light / Medium / Heavy
	type     = bit32.bor(dmgFlag.blunt),      -- by NAME, never a bit value
	dmg      = 18,
	stun     = 0.8,
	posMult  = 2,                             -- posture. NEVER nil.
	parryH   = -0.04,                         -- negative = harder to parry
	onHit    = function(attack)               -- HIT branch only
		hitSfx(attack.enemyEntity.HRootPart, "HardPunchHit")
	end,
}

local function useFunc(this:myself)
	local cooldownID = "myAbility"
	if this:canTriggerCD(cooldownID) ~= true then return end

	local humObj  = this._humObj
	local hurtbox = humObj.HurtBox
	local anim    = this:PlayAnim(script.Anim, 0, 1, 1)

	--- WINDUP. true means they CANCELLED, so clean up everything you made.
	if this:feintWait(0.4) then
		if anim then anim:Stop() end
		return
	end

	--- COMMIT. Spend here, never earlier.
	this:useMana()
	this:triggerCD(cooldownID, 10)

	--- HIT. Returns TWO values, the box and the list.
	local _, hits = this:hitbox(CFrame.new(0, 0, -4), Vector3.new(6, 6, 6))
	for _, enemy in hits do
		local attack = this:makeAtk(DMG, enemy, hurtbox.CFrame.LookVector)
		attack.knockback = this:knockback(attack.atkDir * 10, 0.15, false, -1)
		this:executeAttack(attack)

		if attack:isHit() then
			-- ragdoll / status / follow-up goes here
		end
	end

	this:endLag(0.2)
end

function module.use(self:myself)
	return baseClass.use(self, useFunc)
end

return table.freeze(module)
```

## 3. Register it

`ROWA/Abilities.luau`, two places:

```lua
-- abilityList: APPEND a new id. Never renumber, never reuse. They are saved.
[47] = manifold.MyAbility,

-- abilityMeta: no entry == not draftable, so nobody can ever get it
[manifold.MyAbility] = {
	desc = "One line, shown in the draft.",
	req  = { strength = 4 },   -- {} is FREE. nil INHERITS, which you don't want.
},
```

## 4. Play test it

`:use` runs your useFunc inside a **pcall**, so a mistake is a `warn` in the
output and an ability that silently does nothing. Check the console first.

---

## The five that will bite you

1. **The cancel branch cleans up after itself.** `feintWait` returns true for a
   feint, a death, a stun and "can't attack" alike. Stop the anim, Debris the
   VFX, `:destroy()` the bodyForce, remove every walkSpeed mod. Nothing else will.
2. **Spend at the commit, never before the windup.** Mana AND cooldown.
3. **Keep the cooldown guard at the top.** The input layer calls `:use()` every
   frame for 0.2s and ignores the result — that guard is the only thing stopping
   a double fire.
4. **`:hitbox` returns `(box, hits)`.** `local hits = this:hitbox(...)` gets you
   the box, and a silent no-op.
5. **Use your own walkSpeed key** (`"myAbility"`), never `"stopMoving"`. Shared
   keys clobber each other and whoever removes first wins.

## I want to make…

| …this | use | see |
|---|---|---|
| a lunge, or any hit that travels | `:sweep(cf, sz, CFG)` with a `window` | ABILITIES §6 |
| a beam / aura / rush that lasts | your own loop + `:channelBreak()` between beats | §7 |
| something that flies | `this:projectile(CFG, originCF)` | CombatAction header |
| hold-to-charge | `this:chargeWait(max, min)` after the commit | CombatAction header |
| a counter | `beforeAttacked` + `humObj:canCounter()` | §8 |
| an AoE at a point | world-space hitbox (4th arg `true`), then reject by distance | §6 |
| burn / freeze / shock / bleed | `enemy.statusEffects:apply(effect, t, n)` | Class/StatusEffects |
| to break the map | `Destruction.Sphere / OBB / Cylinder / Ellipsoid` | Destruction_Stable |
| to hold somebody | `grab` welds them to a limb, `pinTo` drags them to a point | §10 |
| to knock them down | `enemy.ragdoll:ragdoll(t, stopOnGround, dir)` | CLASSES.md |
| a cheaper price for a whiff | tiers: short first, full at the commit | §5 |
| a screen shake, a flash, anything seen | `fireVFX(id, ...)` | VFX.md |

## Naming your cooldown

`cooldownID` is a free string and **`canTriggerCD` returns true for an id that
doesn't exist** — a typo is a permanently open gate, not an error. Use the
ability's own name and use the same spelling in both calls.
