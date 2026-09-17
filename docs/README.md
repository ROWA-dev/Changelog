# ROWA - DOCS INDEX
This file is the index: where things live, plus the 60-second mental model.
Detail lives in the sibling docs.

House style, the no-redundancy rule, the testing policy and what has already
been decided against live in `ServerStorage/AGENTS.md`. Read that before
writing anything.

## DOC MAP
| doc | covers |
|---|---|
| GOTCHAS.md | READ FIRST. footguns, naming traps, silent failures |
| CLASSES.md | Entity -> HumObjClient -> HumObj, combat primitives |
| WEAPONS.md | Weps tree, WepBase, authoring a weapon |
| ABILITIES.md | Abilities tree, the CombatAction/AbilityBase split, authoring an ability |
| COMBAT.md | the fight from the player's side. read before touching any feel number |
| VFX.md | inline VFX vs the networked Quiver |
| DATASTORE.md | plrDataV3, PlrData + Slots serialization, migration |
| Progression.md | level, point investment and draft gate |
| INVENTORY.md | containers, items, equip, chests. read before touching any container |
| EMOTES.md | emote tree, the saved wheel loadout, the vendored piano |
| ARCHITECTURE.md | the require graph. read before adding a require to the combat pipeline |
| ADMIN.md | the slash-command admin. read before authoring a command or an arg type |
| howIsaveRuntimeRAM.md | the allocation playbook |
| tricksThatSaveNetwork.md | the wire playbook. read before adding a remote, a broadcast or a per-frame send |

## 60-SECOND MENTAL MODEL
Everything is a Luau metatable class with `.new()` + `:destroy()`, using
`setmetatable(module, { __index = baseClass })` inheritance. Subclass
`.new()` builds the base instance first, then re-`setmetatable`s that SAME
table onto itself, so one instance carries every tier's methods.

The four moving parts:

  1. HumObj: the authoritative per-Humanoid combat object (server).
     Registry: `require(ServerScriptService.Entities).Get(hum)`.
     Owns stats, cooldowns, posture/mana, hurtbox, ragdoll, cards,
     the currently wielded weapon and the in-use ability.

  2. Weapon (WepBase subclass): long-lived, equipped onto a HumObj.
     Entry point: `wep:attack(atkTypeEnum, optionalAtkFunc)`.

  3. Ability (AbilityBase subclass): bound to a HumObj at construction.
     Entry point: `ability:use(useFunc)`.

     WepBase and AbilityBase BOTH inherit `ROWA/Class/CombatAction`, which
     owns everything an attacker does regardless of what it is holding:
     cooldowns, the timing helpers, feintWait/windup, sweep, channelBreak,
     makeAtk/executeAttack, knockback, bodyForce, projectile. If a change
     would suit both, it belongs there and not in either subclass.

  4. Attack (AttackClass): one discrete "hit". A weapon/ability builds it
     with `:makeAtk(dmgTbl, enemyHum, atkDir)` then fires it with
     `:executeAttack(atk)`, which lands in `HumObj:HandleAttack` where
     parry/dodge/block/hit is resolved.

The universal swing loop:

    play anim  ->  :feintWait(windup)  ->  :hitbox(cf, sz)
               ->  for each hum hit: :makeAtk(...) + :executeAttack(...)
               ->  :endLag(t)

`feintWait` returning true means CANCELLED. Early-return and clean up your
VFX on that branch.

## ENTRY POINTS / WHERE THINGS GET KICKED OFF
  ServerScriptService/Core/Inputs.luau        client input -> wep:attack(...)
  ServerScriptService/Entities.luau           THE entity registry. Keyed by
                                              Model; Get() also takes a
                                              Humanoid or any child part.
                                              Register/Get/Unregister/GetAll.
                                              (was Humanoids.luau, deleted)
  ServerScriptService/HitBox.luau             raw GetPartBoundsInBox query
  ServerScriptService/Knockback.luau          raw body-force / knockback impl
  ServerScriptService/Utils/DmgUtils.luau     dmg flags, weight + return enums
  ServerStorage/ROWA/Class/SimpleEntity.luau  non-player entity (boss, big
                                              creature). Model-only, no
                                              Humanoid needed. Copy this,
                                              not HumObj. Tag the Model
                                              `entity_simple` to register it.
  ServerStorage/ROWA/Weps.luau                weapon id -> class registry
  ServerStorage/ROWA/Abilities.luau           ability id -> class registry
  ServerStorage/ROWA/Items.luau               item id -> class registry
  ServerStorage/ROWA/SideWeps.luau            OFF-HAND id -> class registry. Left
                                              arm, outside the wielded set, one
                                              action on the `sideWep` bind (V).
                                              A card only GRANTS one; the class
                                              owns model, weld and action.
                                              Shield is id 1.
  ServerStorage/ROWA/Emotes.luau              emote id -> class registry. The
                                              wheel loadout is per-account and
                                              SAVED (PlrData.emoteData); the
                                              StayInPlace ones cancel on dash.
  ServerStorage/ROWA/Modules/draftOffer       the level-up draft, abilities AND
                                              cards. canClaim is the ONLY grant
                                              gate; rows carry `k` (Draft kind)
                                              because the two id spaces overlap.
                                              audit() is the un-grant: slot load
                                              re-grades saved picks and refunds.
  ReplicatedStorage/Modules/Requirements      the `req` gate shape for weps +
                                              abilities. Flat; stat names are
                                              unique across tracks. `card = id`
                                              and `ability = id` are the two
                                              non-stat, server-side gates.
  ReplicatedStorage/Class/baseContainer.luau  the grid container base, shared
                                              by server + client mirror
  ReplicatedStorage/Class/HumObjClient/replIds  THE CharacterRepli wire id
                                              registry. Two spaces, S2C and
                                              C2S; HumObj and HumObjClient
                                              both read it. Append only,
                                              never renumber a live id.
  ReplicatedStorage/Class/Combatant.luau      defender contract + inert
                                              defaults. Read before touching
                                              enemyEntity.<anything>
  ReplicatedStorage/Modules/ShiftLock.luau    shiftlock POLICY. `block(reason,on)`
                                              frees the cursor, `freezeCharacter
                                              (reason,on)` stops it steering you
                                              (true stun). Desktop's stock lock is
                                              unreachable and NEUTRALISED, not off:
                                              read that file's header first.
  ReplicatedStorage/Modules/TopbarIcons.luau  topbar buttons. Icons REGISTER
                                              (name/order/touchOnly/onClick)
                                              and the row lays itself out;
                                              nobody hardcodes an X anymore.
                                              settings, emotes, inventory.
  ROWA/Class/HitboxClass/types.luau           hitbox TYPES only, requires
                                              nothing. Keep it that way,
                                              see ARCHITECTURE.md
  ServerStorage/ROWA/Class/CombatAction.luau  THE shared attacker base, under
                                              BOTH WepBase and AbilityBase.
                                              Read its header before adding a
                                              method to either.
  ServerStorage/ROWA/Modules/sharedFeintWait  the one windup impl; the two
                                              old paths forward to it
  ServerStorage/ROWA/Class/plrObj/DataStore   PLAYER DATA's DataStoreService
                                              caller. One of TWO now.
  ServerStorage/ROWA/Modules/imgBoard         the other one. The phone's image
                                              board, own store, own budget,
                                              wipeable. Never player data.
  ServerStorage/ROWA/Modules/filterText       THE user-text filter. Was inlined
                                              in plrObj/replication; lifted out
                                              when ImgBoard needed it too.
                                              Fails closed: nil means DROP.
  ReplicatedFirst/LocalCore.luau              client bootstrap (VFX, blood, HUD)
  StarterGui/settings/terminalModule          the settings window. Pages are
                                              DISCOVERED, not registered. Page
                                              contract is at the top of that file.
