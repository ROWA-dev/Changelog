# ABILITIES - ServerStorage/ROWA/Abilities

*(index: parent `ServerStorage/README.md`)*

An ability is a class bound to ONE HumObj at construction, entered through
`ability:use(useFunc)`. This file is the framework. Combat feel numbers are
COMBAT.md, footguns are GOTCHAS.md, and neither is repeated here.

**Just want to build one? → `ABILITIES.md/HowMakeAbility.md`.** That is the
copy-paste recipe; this is the reference it points at.

## 1. Tree

```
ROWA/Abilities.luau        REGISTRY: id -> ability ModuleScript, + draft meta
ROWA/Abilities/
  AbilityBase.luau         the ability half of the shared attacker base
    feintwait.luau         thin frozen config over Modules/sharedFeintWait
  <one ModuleScript per ability>
  Template/                Tool + Script + ObjectValue scaffold
```

Each ability OWNS its child instances (Animations, Sounds, emitters, Parts) and
clones them at runtime. Nothing is shared between abilities except through a Module.

## 2. Registry — `ROWA/Abilities.luau`

| call | does |
|---|---|
| `getIds()` | frozen ascending id array. **Requires nothing** — enumerate with this, never by probing `getAbilityClass` in a loop, which loads every module |
| `getAbilityClass(id)` | class table, **errors** on an unknown id |
| `newAbility(id, ...)` | instance; varargs go to `.new`, i.e. the humObj. Also stamps `notWepClass` onto it |
| `moduleToID(module)` | reverse lookup, warns + nil if unregistered |
| `getMeta(id)` | draft metadata, or nil for NOT DRAFTABLE |
| `nameOf(id)` | class Name without holding an instance |
| `catalogue()` | frozen rows, draftable only. Same columns as `Cards.catalogue`, because the codex draws one page for both |
| `supersededBy` / `conflictsOf` / `conflictsWithCard` | reverse maps, built once at load |

Meta fields: `desc`, `req`, `tier`, `replaces`, `reoffersBase`, `excludes`,
`excludesCards`, `notWepClass`.

Read the ids off `abilityList`. They are **persisted on saved items: append only**,
never renumber, never reuse.

Some modules on disk are not in `abilityList` (EarthShot, HitSelf, StrongKick,
StrongShove). `getAbilityClass` errors on those — require the module directly, or
add it to the list.

## 3. The class split

`Class/CombatAction.luau` is the shared attacker base. **WepBase and AbilityBase
both inherit it**, so a fix lands once. Read its header before adding anything to
AbilityBase: if weapons would want it too, it goes one level down.

On CombatAction:

- `canTriggerCD` / `triggerCD` — cooldowns, plus the hotbar slot forward
- `scaledTime` / `atkWait` / `endLag`
- `feintWait` / `windup` — the cancellable windup
- `chargeWait` — hold-to-charge, runs *after* the commit
- `channelBreak` — the interrupt check for sustained actions
- `sweep` — active frames over `:hitbox`
- `makeAtk` / `executeAttack` — `enemy` is an **entity**, not a Humanoid
- `feint` / `bodyForce` / `knockback` / `projectile`

Two subclass constants drive it. Forget them and you get the weapon defaults,
which are the conservative ones:

- `FEINT_CD_ID` — `"feint2"` for abilities, does **not** gate dashing
- `KNOCKBACK_USES_CHARSIZE` — false for abilities, true for weapons

AbilityBase overrides, all on purpose:

- `use` / `useMana` — the lifecycle below
- `hitbox` — its own opts table, §6
- `canTriggerCD` — stamps `_cdId` + `humObj.last_ability` first, for Dispel
- `PlayAnim` — `AnimationPriority.Action4`, and the track is stashed in
  `humObj.lastAbilityAnim` so a weapon swing can kill it (`WepBase:PlayAnim`
  calls `stopAbilityAnims`)
- `onParried` — pushes `canAtkThreshold` to at least `tick()+0.2`, where WepBase
  only warns

`.new(humObj)` gives `atkRate` 1, `atkRateOffset` 0, `knockbackMult` 1, `range` 0
— all AdditiveValues, so `self.atkRate.Value`, mutate with `:SetMod`. `destroy`
destroys all four; `table.clear` alone leaks their mod lists.

### `:use` internals

1. false if `humObj.attacking` or `:canAttack() == false`
2. false if `notWepClass` matches the wielded weapon **family**
3. false if `:manaNow() < manaUse`, and broadcasts the `noMana` tell, throttled to
   one per 0.3s because UseAbility retry-loops
4. `using_ability = self`, `attacking = true`, `ChangeBlocking(false)`
5. **pcalls** useFunc and *warns* on error — your errors are not crashes
6. clears `using_ability`, `attacking = false`, returns true

**Mana is not spent here.** Call `this:useMana()` yourself, at the commit point,
after the windup. An ability that never calls it is free, and unless its header
says that is deliberate it is a bug.

### How it gets triggered

`humObj:UseAbility(instance)`:

- **errors** if `ability._humObj ~= self`. Instances are per-HumObj.
- auto-feints your own swing if it is within 0.06s of landing
- waits on `attacking.Changed` if you are mid-action
- then calls `:use()` every frame for up to 0.2s while `attacking` is false.
  **It ignores the return value**, so a useFunc that bails early is called again
  next frame: *the cooldown guard at the top is what stops a double fire.* Your
  useFunc must be idempotent under a failed `use`.

## 4. Authoring shape

```lua
local baseClass = require(script.Parent.AbilityBase)
local module = { Name = "Clap" }          -- Name == script.Name, always
module.__tostring = baseClass.__tostring
module.__index = module
setmetatable(module, { __index = baseClass })

function module.new(humObj)
  return setmetatable(baseClass.new(humObj), module)
end

-- configs are built ONCE at module scope and FROZEN: dmg tables, sweep cfgs,
-- projectile cfgs. Never per cast.
local function useFunc(this)
  local cooldownID = "clap"
  if this:canTriggerCD(cooldownID) ~= true then return end
  -- windup -> commit -> hitbox -> makeAtk -> executeAttack -> endLag
end

function module.use(self)
  return baseClass.use(self, useFunc)   -- RETURN it
end
return table.freeze(module)
```

**The cancel branch owes cleanup.** `feintWait` returns true for a player feint, a
vanished humObj, stun, and "can no longer attack" alike, and nothing tidies up for
you: stop the anim, Debris the cloned VFX, destroy any bodyForce, and **remove
every walkSpeed / atkRate mod on every exit**. A stranded negative walkSpeed is
invisible, permanent, and the most common stuck state there is.

Use a **per-ability mod key**, never the shared `"stopMoving"` — shared keys
clobber each other and whoever removes first wins.

## 5. Cooldowns: tiers only go up

Ability cooldown ids are not pre-registered; the **first** `triggerCD` to name one
creates it. Two properties of `cooldowns.trigger` decide everything:

- it is **monotone** — `last = max(last, now + cd)`
- it **never rewrites a registered duration** once the id exists

So for a move that charges less for a whiff than for a connect:

> pay the **short** tier first, with `dontOverwrite`
> pay the **full** tier at the commit, **without** `dontOverwrite`

Both halves are load-bearing. A "refund" applied after the full price is a silent
no-op. A full price passed with `dontOverwrite` after a short one has been
registered is *also* a no-op, permanently: one whiff pins that id at the cheap
tier for the session. PowerStrike, FireStab, HollowPurple, Zoltraak, Tendrils,
BoulderKick, LionFall and bloodChain are the shape.

## 6. Hitboxes

Both flavours go through `Class/HitboxQuery` and **both return
`(hitboxObj, hits)`** — `local hits = this:hitbox(...)` gets the *object*.

The ability opts are the **plain query**: no charSize scale, no airborne bonus, no
HurtBox→root retry, range used raw with no `+1`. Weapons opt in to all four.
Ability hitboxes are authored at absolute size.

`prevHits` is written for weapons only, and is read by WepBase's whiff detection
and nothing else — an ability is punished for whiffing by its **cooldown**, which
is the whole mechanism.

4th arg `true` = the CFrame is world space; otherwise it is HurtBox-local and
follows you as you turn.

### `:sweep` — active frames

`:hitbox` is one snapshot on one frame, which is right for a move that stands
still and wrong for one that travels: the box lands where the body *was*, and a
target who steps in a frame later is missed.

```lua
local LUNGE = table.freeze({ window = 0.15, lead = 0.07 })
local box, hits = this:sweep(cf, sz, LUNGE)
```

| field | meaning |
|---|---|
| `window` | seconds of frames. **0 or nil is exactly `:hitbox`**, which is what makes adoption safe |
| `lead` | seconds of velocity lookahead, off HRootPart, clamped to 6 studs so a rush or a knockback cannot throw the box off the map |
| `worldSpace` | replaces `:hitbox`'s trailing boolean |

**First contact wins** — it returns the first query that found somebody it could
land on, and never accumulates, which would multiply the damage.

A body mid-**dodge** is not a contact, so i-frames do not spend the window; if the
window expires on one anyway they are still returned, so the dodge *resolves* and
the defender gets their read.

It goes through `self:hitbox`, so a weapon sweep keeps the weapon opts.

**It yields**: a move adopting a window owes that time back out of its next beat or
its endLag. `window` scales by `atkRate`/`timeScale`, `lead` does **not** —
bodyForce already scales by timeScale, so the velocity carries it.

Not for lanes: a 40-stud beam box is a snapshot by design.

## 7. Windups, channels, and the commit

`:feintWait(t)` returns **true on cancel**; `:windup(t)` is the same thing the
readable way round and returns **true on success**. Semantics and the
weapon/ability config differences live in GOTCHAS and in
`Modules/sharedFeintWait` — fix bugs there, once.

A sustained action runs on its own rhythm and **cannot** call `feintWait`, which
would fight the cadence. It calls `channelBreak` between beats:

```lua
local why = this:channelBreak()   -- "feint" | "stun" | nil
if why then --[[ stop your fx ]] break end
```

It clears `isFeinted`, triggers `FEINT_CD_ID` and fires the cancel flourish; pass
`true` to suppress that flourish for a release that visibly did something.

**Past the commit, a feint is a RELEASE, not a cancel.** The mana and the cooldown
are already spent and are never given back; all that ends is the channel. What
"release" means is the move's business — Burst detonates where it stands, a beam
simply stops.

**End every channel effect on the real end.** A channel that told the client
"3 seconds" up front and then broke out early leaves the beam firing, the dust
pouring and the caster invisible. Send the explicit 0-duration teardown on every exit.

If your action has **no windup at all**, set `self.isFeinted = false` at entry: the
flag is only ever cleared by `feintWait` and `channelBreak`, so without a windup
you inherit a stale one and self-cancel on frame one.

## 8. Counters

A counter subscribes to `humObj.beforeAttacked`, sets
`atk.status = returnEnum.aborted`, and answers. Guard it with:

```lua
if not humObj:canCounter() then return end
```

which is "no reversal out of pressure" — 0.2s off the last **hit** and the last
**block**, read from the `_lastHit` and `_lastBlocked` stamps. Do **not** write
this by hand against `stun.Value`: that is a deadline other code overwrites (a
parry zeroes it outright), which is why countering out of hitstun used to work.

## 9. How an ability reaches a player

As an `ablityItem` in a container slot. The item persists the **id only** (`aId`);
the live instance is lazy and built by `ablityItem:bind(humObj)` on equip, because
an ability binds its humObj at construction and slot deSerialize has none.
Identify an ability item by `.aId`, never `.ability`.

Grants come from the level-up draft, `ROWA/Modules/draftOffer`, gated by
`meta.req` (shape: `ReplicatedStorage/Modules/Requirements`). **req gates offering
and slot load, never use**: a granted ability stays usable for the session, and
`draftOffer.audit` re-grades it on the next load.

| field | effect |
|---|---|
| `replaces = id` | claiming **drops** that ability. Always pair with `req = { ability = <same id> }` or the upgrade can be drafted by someone who never owned the base |
| `reoffersBase` | the base returns to the pool, so a **pair** can be held |
| `excludes` | pick one, declared on one side, made symmetric at load. Gates *offering* only — an admin grant can still hold both |
| `excludesCards` | the same, across the card pool |
| `notWepClass` | a weapon **family** you may not wield. Checked by the draft *and* by `AbilityBase.use`, so it cannot be bypassed by swapping weapons after the claim |

`req = { card = id }` is how a card, rather than a stat, opens an ultimate.

## 10. Decided — do not re-propose without new evidence

- A feint past the commit is a **release**. It never refunds.
- Whiff pricing is **tiers, not refunds**. §5.
- Abilities are **not** punished for whiffing by atkRate. The cooldown is it.
- `grab` = welded to a limb. `pinTo` = dragged toward a point. A move may
  legitimately use both.
- Ice is the **only metered element**: chips build, the ice ultimate detonates,
  and the full encase puts out Burn. Burn and Shock stay dumb. Do not grow a meter
  for them without a reason.
- The counter guard reads **stamps**, never `stun.Value`.
- `window` scales with atkRate, `lead` never does.

## 11. Known bad, tracked

- `resolveHit`'s mutual-hit reset **bare-writes** `stun.Value = tick()+0.1`,
  shortening a real stun and bypassing `:Stun`, so `onStunned` never fires.
  `canCounter` is immune to it now; `canDash` is not.
- `attackHelpers/arial` and `/sprint` still gate on `stun.Value + 0.2`. Arguably an
  intended parry punish — decide, do not blanket-fix.
- Blaze (id 2) is WIP: its `triggerCD` is commented out and it spends no mana, so
  it is spammable. It has no meta, so it is not draftable.
