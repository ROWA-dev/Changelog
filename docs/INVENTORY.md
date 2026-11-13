# INVENTORY - containers, items, equipping & the inventory network
(index: parent ServerStorage/README.md)

the game is a competative and fast paced so inputs should be fast and efficient...

Grid containers, the items inside them, and the S2C/C2S traffic that keeps
a client mirror in sync. Persistence is DATASTORE's job; this doc stops
at `slot:Serialize()`.

## 1. THE PIECES
  ReplicatedStorage/Class/baseContainer.luau        grid + 2 signals. shared base
  ServerStorage/ROWA/Class/Container.luau           server container (auth)
  ServerStorage/ROWA/Class/NamedContainer.luau      + name/width/height (chests)
  StarterGui/inventory/inventoryUI/Class/ContainerClient.luau
                                                    client mirror (dumb, no auth)
  ServerStorage/ROWA/Items.luau                     item id -> class registry
  ServerStorage/ROWA/Items/itemBase.luau            equip/unEquip/serialize contract
  ServerStorage/ROWA/Items/stackItem.luau           stackable base, WIRED (§8)
  ServerStorage/ROWA/Items/stackItem/bananaItem.luau  the 1 stackable item
  ServerStorage/ROWA/Items/uniqueItem.luau          non-stackable base
  ServerStorage/ROWA/Items/uniqueItem/{tool,wep,ablity}Item.luau   the 3 unique items
  ServerStorage/ROWA/Class/PlrData/Slots/slotSS.luau  OWNS inventory+hotbar
  ServerStorage/ROWA/Class/plrObj.luau              openChest/closeChest, LoadSlot
  ServerScriptService/Core.luau                     Inventory RemoteEvent handler
  ServerScriptService/Core/RFHandler/
      {moveItem,transferItem,quickMoveItem,         the 6 RF verbs
       splitItem,collectItem,dropItem}.luau
      resolveContainer.luau                         their shared auth + bounds + unequip
  ServerStorage/ROWA/Modules/chest.luau             world chest prompt + lid, (model, container, onOpen?)
  ServerStorage/ROWA/Modules/groundItem.luau        an item on the floor: model copy, walk-over pickup, 120s despawn
  Workspace/Dev/TestChest                           a normal chest (keeps items, 50 bananas) to test with
  ReplicatedStorage/Modules/TopbarIcons.luau        topbar button registry
  ReplicatedStorage/Modules/CooldownClaims.luau     who draws which cooldown
  ReplicatedStorage/Modules/ShiftLock.luau          camera lock + suppression
  StarterGui/cooldownsUI/cooldownVisual.luau        the generic cooldown list
  ReplicatedStorage/RemoteEvents/Inventory          the RemoteEvent + `enums` child
  StarterGui/inventory/inventoryUI.luau             THE client driver (drag, keys)
  StarterGui/inventory/inventoryUI/Class/ContainerUI.luau  grid of frames
  .../{InventoryUI,HotbarUI}.luau                   the 2 ContainerUI subclasses

## 2. 60-SECOND MODEL
A container is a FLAT array `slots[1..sz]`, `sz = width*height`. 2D is a UI
fiction: ContainerUI/InventoryUI recover (row,col) from mouse position with
`floor(x/65)` + `floor(y/65)` and flatten back to `row*columns+col+1`.

Server holds LIVE item class instances. Client holds the SERIALIZED tables
those items produced via `:ToClient()`. Both sides subclass the same
`baseContainer`, so `set/move/transfer` behave identically. That is the whole
trick: the server mutates, sends the same call over the wire, the client
replays it on its mirror, ContainerUI listens to the mirror's signals.

    server Container  --(Inventory RemoteEvent, enum + args)-->  ContainerClient
           |                                                            |
    ItemUpdated/ItemMoved/onEquipped                     ItemUpdated/ItemMoved/onEquip
           |                                                            |
     initReplicateServer                                        ContainerUI (frames)

Ownership chain:
    plrObj.loadedSlot (slotSS)
      |- .inventory : Container (10 x 3)   replicationId 1
      |- .hotbar    : Container (10 x 1)   replicationId 2
      \- .openContainer : Container?       replicationId 3  (borrowed, see §6)

## 3. baseContainer - THE SHARED BASE
  fields: width, height, sz, slots, ItemUpdated, ItemMoved
  ItemUpdated(index, item?)      something now occupies (or vacated) index
  ItemMoved(prevIndex, newIndex) an in-container reorder happened

  set(item?, index)   DESTROYS whatever was there, then fires ItemUpdated.
                      `set(nil, i)` is the delete verb.
  move(prev, new)     swap if occupied, else move. Fires ItemMoved ONLY.
  transfer(prev, other, otherIndex)
                      cross-container. Delegates to `move` if other == self.
                      Fires TWO ItemUpdated (one per container), NOT ItemMoved.
                      Returns false if the source slot is empty.
  destroy()           pcalls :destroy on every item, clears, kills signals.

  Note the asymmetry: move emits ItemMoved, transfer emits ItemUpdated.
  ContainerUI handles them as two separate animations. If you add a verb,
  pick one of those two shapes; don't invent a third signal.

## 4. Container (SERVER) - what it adds
  * `_container` back-pointer bookkeeping. `set`/`transfer` are overridden
    ONLY to keep `item._container` pointing at its owner (a destroyed item
    clears its own). Items need it because `item:equip()` fires
    `self._container.onEquipped`.
  * `onEquipped: Signal<equipping:boolean, item>`: the third signal, server
    only. Fired BY THE ITEM, not by the container.
  * `onCooldown: Signal<item, seconds, cdId>`: the fourth, server only.
    Fired by CombatAction.triggerCD through `item._item`, see §6.
  * `insertItem(item) -> leftover?`: first-fit. Unique items take the first
    nil slot. Returns the item back if there's no room; EVERY caller
    currently just `leftover:destroy()`s it, i.e. overflow = deletion.
  * `absorb(i, from, n) -> moved` + `settle(i)`: THE stack primitive. absorb
    moves up to n off `from` into slot i (tops up the same id, or splits a
    Clone into an empty slot) without replicating `from`; settle then
    replicates `from`'s slot once, deleting it (unEquip first) if drained.
    insertItem, the split/collect/quickMove verbs and bananaItem.eat use them.
  * `take(i, n) -> item?`: the inverse, up to n off slot i as a LOOSE item
    (the original if it all goes, else a split Clone), never destroyed. dropItem uses it.
  * `Serialize` / `deSerialize(data, w, h)` / `ToClient`.
  * `initReplicateServer(remote, containerID, plr)`: see §5.

  ### Serial shape
  Array-of-pairs, NOT a sparse array: `{ s = { {i, payload}, {i, payload} } }`
  because JSON/zstd can't round-trip a gapped numeric array. `ToClient` adds
  `replicationId`; NamedContainer's `ToClient` also adds width/height/name.
  Items with `.temp == true` are SKIPPED by Serialize but NOT by ToClient, so
  temp items are visible and usable but never persist.

## 5. THE NETWORK
  ONE RemoteEvent for state (`RemoteEvents.Inventory`) + ONE RemoteFunction
  for player-initiated moves (`ReplicatedStorage.RemoteFunction`). Verbs live
  in `RemoteEvents/Inventory/enums`:

    1 selectHotbar     C2S  hotbar index pressed
    2 itemUpdated      S2C  (index, serialItem?)
    3 itemMoved        S2C  (prevIndex, newIndex)
    4 itemEquip        S2C  (equipping:boolean, index)
    5 openInventory    C2S  (isOpen:boolean)   -- cosmetic floater only
    6 newContainer     S2C  (serialContainer)  -- a chest opened
    7 closeContainer   C2S  (replicationId)    -- chest UI dismissed
    8 itemCooldown     S2C  (index, seconds, cdId) -- draw a cd ON the slot

  WIRE SHAPE, S2C: `(containerID, enumId, ...)`. The client demuxes on
  containerID in inventoryUI.luau: 1 -> inventory, 2 -> hotbar, 3 -> the
  open chest, and `containerID == nil` is the special case meaning "no
  container exists yet", which is how `newContainer` arrives.

  WIRE SHAPE, C2S (this remote): `(enumId, ...)`, NO container id, because
  every C2S verb here is about the player's own single loaded slot.
  Handled at the bottom of ServerScriptService/Core.luau.

  `Container:initReplicateServer` is the ONLY thing that writes to the wire:
  it stamps `self.replicationId` (first feed only: the owner's) and connects all four server signals to
  `FireClient(plr, containerID, <enum>, ...)`, returning a handle whose
  `:Disconnect()` drops all four. The ItemUpdated payload goes
  through `itm:ToClient()` first. onEquipped carries no index, so it LINEAR
  SCANS slots to find the item: O(sz) per equip, flagged TODO in source.
  onCooldown carries the item too and scans the same way.

  `ContainerClient:initReplicateClient` is the mirror: it stamps
  `self.replicationID` and installs `SubscribedEventCB(enumId, ...)` which
  replays set/move/onEquip locally. It validates nothing; it is a mirror,
  never a source of truth.

  ### The six RemoteFunction verbs (RFHandler manifold)
    moveItem(replicationID, prevIndex, newIndex)
    transferItem(fromId, toId, fromIndex, toIndex)
    quickMoveItem(fromId, fromIndex)              -- shift-click
    splitItem(fromId, fromIndex, per, toId, toIndex, ...)  -- `per` into EACH target
    collectItem(toId, toIndex)                    -- double-click
    dropItem(n, fromId?, fromIndex?)              -- bind `drop` (Backspace); no slot = the equipped hotbar item
  splitItem is every partial move (drop, one, merge, spread); a full or
  wrong target just absorbs less, and `per * targets <= stack` caps a call.
  dropItem only takes from your own hotbar/inventory, never abilities or Fist.
  The client sends the carried stack, else the hovered slot, else (bag shut)
  no slot and the server finds the equipped item. Shift = whole stack (Ctrl slides). Touch: drag
  it out of the bag. Pickup is groundItem's zone Touched by the root (the only
  touchable body part), reach-checked server-side against the picker's hurtbox
  because a touch is the client's word. Never saved; the timings and caps are
  groundItem's constants. It tosses from the dropper's hurtbox too, and landing
  on a part an anchored root carries (a train car) welds it to that root, so it
  rides whatever moves the root; itmpick then animates in that root's space.
  Both ends are client fx off tags, attribute `by` = who, one module
  (ReplicatedStorage/VFXQuiver/itmpick, itmdrop aliases it): `itmdrop` the toss,
  untagged after it lands so stream-ins don't replay it, `itmpick` the fly-in.
  A dropped Tool is CLONED to the ground and the original parked in PlayerGui
  for a few seconds: nil'ing it kills its LocalScript before Unequipped runs.
  All six resolve ids through `RFHandler/resolveContainer`, which returns
  `{loadedSlot.hotbar, loadedSlot.inventory, loadedSlot.openContainer}` and
  the plrObj. A player can only ever name containers they personally have
  loaded or open. That lookup IS the auth model here, and it is sound. It
  used to be copy-pasted into each verb; a new verb calls `resolve.all` +
  `resolve.byId` and does NOT grow a fourth copy. byId is POSITIONAL (its
  `AT` table), never the container's `replicationId` field: a viewed
  inventory is its owner's 1 too.
  `resolve.canHold` keeps ability items (`aId`) in the slot's own hotbar/
  inventory; transferItem checks both legs of a swap, quickMoveItem its dest.

  `quickMoveItem` names NO destination. The server routes it:
    chest open : hotbar/inventory -> chest,  chest -> inventory then hotbar
    no chest   : hotbar <-> inventory
  and tops up matching stacks, then drops the rest in the first free slot.
  If the destination is full it returns false and nothing moves, same as
  minecraft.
  An item crossing owners (into or out of a chest) goes through
  `resolve.cross` -> `release`: unequipped and dropped from its holder's
  wielded set, same as dropItem. A refusing `unEquip` (wepItem mid-swing)
  vetoes the whole move. transferItem checks both legs.

  No verb is optimistic on the client; see the carry in §6 for why it
  still looks instant.

## 6. FULL LIFECYCLES
  ### Login -> inventory on screen
    plrObj:LoadSlot(id)
      -> Data.slots:getAndLoadSlot(id)      (zstd decompress + slotSS.deSerialize
                                             -> Container.deSerialize x2)
      -> inventory:initReplicateServer(remote, 1, plr)
         hotbar   :initReplicateServer(remote, 2, plr)
      -> slot:clearTemp()                   (drop last session's temp items)
      -> re-insert every Tool in plr.Backpack via slot:insertTool
      -> _onLoadSlot -> replication.luau -> S2C.SlotData (PlayerRepli, zstd)
    Client: plrObj.slotLoaded fires in inventoryUI.luau
      -> FIRST TIME ONLY: initReplicateClient on both mirrors, using the
         replicationId that came inside the serial payload
      -> uploadSerialData + UI:update() on both

    `initReplicateClient` runs once ever (`replicationInit` latch) but
    `uploadSerialData` runs on every slot load, so a re-load reuses the same
    two client container objects. `plrObj.onDataRecieve` (account-level data)
    blanks both mirrors and closes any open chest.

  ### Pressing a hotbar key
    keybindEnums.hotbar1..10 -> bindFuncs lambda -> hotbarUse(i)
      -> RE selectHotbar(i)
    Core.luau: needs loadedSlot AND humObj.isActive, else silently returns.
      item.equipped     -> item:unEquip()
      item is an ability-> item:cast(humObj), return (abilities do not
                           occupy the single equipped-item slot; they
                           self-unequip after use). "is an ability" is
                           `item.aId ~= nil`, NOT `item.ability`, which is
                           lazy and nil until :bind runs.
      otherwise         -> unEquip the current plrObj.equippedItem (BAIL if
                           it refuses), then item:equip(humObj), store it.
    Clicking a hotbar cell with the mouse routes into the same hotbarUse.
    E (keybindEnums.ability) casts the first ablityItem:isReady ability, left to right, and nothing while one is queued/casting (Core/Inputs startAbility).
    With the BAG OPEN the same keys mean something else first: see
    `hotbarSwap` in §6 (minecraft's hover-a-slot-press-a-number).

  ### equip -> the border lights up
    itemBase.equip sets `.equipped = true` and fires `_container.onEquipped`
    -> initReplicateServer -> S2C itemEquip -> ContainerClient.onEquip
    -> ContainerUI -> ItemUI:select(true) (border UIStroke + tint).
    Subclasses override equip/unEquip and CALL THE BASE. That base call is
    what emits the signal. Forget it and the item equips invisibly.

    What the three items actually do on equip:
      wepItem    -> entity:EquipWeapon(self.wep), which SELECTS and never
                    fails: a weapon already in the wielded set goes straight
                    to hand and is usable; one that is not is merely HELD OUT
                    (right hand, inert) until the player clicks to commit.
                    The stat gate lives on that commit (HumObj:WieldWeapon /
                    :canWield), NOT here. Set cap = humObj.maxWeapons, an
                    AdditiveValue (default 1) a card can raise; committing
                    past the cap EVICTS the oldest, it does not refuse.
                    Membership persists as wepItem's `wl` (wep.committed),
                    and eviction CLEARS it -- which is why loadChar's
                    commitFrom stops at the cap rather than committing
                    everything and letting the evictions sort it out. A
                    shrunk cap must not delete the save's other weapon.
                    unEquip calls wep:stow(), which holsters a committed
                    weapon and fully removes a merely-held one.
                    See WEAPONS 4 for the four poses.
      ablityItem -> :bind(entity) to build the live ability, then
                    task.spawn(entity:UseAbility(ability)) and immediately
                    unEquips itself
      toolItem   -> reparents the Tool into the character and watches
                    AncestryChanged to auto-unEquip; unEquip puts it back in
                    the Backpack (or ServerScriptService if the char is gone),
                    no-op if not equipped. Tools in UNEQUIP_ON_STUN (glider)
                    also drop on onStunned and refuse to equip while stunned

  ### An ability's cooldown landing on its slot
    The cooldown is NOT matched by name on the client. It cannot be: the id is
    a magic local inside each ability's useFunc ("strongLeft"), and plenty of
    them break the camelCase pattern ("Barrage", "ToshiCounter"). So the
    server says WHICH SLOT, and the client never has to know an ability's id
    at all.

      ablityItem:bind            ability._item = self     (back-pointer, like
                                                           item._container)
      CombatAction.triggerCD  -> item._container.onCooldown:Fire(item, secs, id)
      initReplicateServer     -> S2C itemCooldown(index, secs, id)
      ContainerClient         -> onCooldown
      ContainerUI             -> claims.claim(id) + ItemUI:cooldown(secs)
      ItemUI:cooldown         -> one linear tween wiping a `cd` overlay frame

    Two instances, both on the ITEM's frame, both built in code unless a `cd`
    Frame / `cdText` TextLabel exists under ItemUI to restyle them in studio:
      cd      the wipe, ZIndex 5, drains top-down
      cdText  the readout, ZIndex 6, SIBLING of the wipe, pinned bottom-centre
    Sibling because it used to be the wipe's CHILD and rode it down the slot.
    The text is still the TOTAL and still never ticks; the wipe is the
    progress. The "s" is dimmed inline with RichText, so cdText needs it on.

    Duration is read back off the cooldown (`cooldowns:remaining(id)`), NOT
    from customCD, because `cooldowns:trigger` IGNORES customCD when
    dontOverwrite is true. customCD is a lie about half the time.

    `_item` is deliberately NOT set on wepItem. A weapon triggers a cooldown
    on every feint and swing and would strobe its own slot.

    The generic list (StarterGui/cooldownsUI/cooldownVisual) skips any id in
    ReplicatedStorage/Modules/CooldownClaims, which is how "on the item
    INSTEAD of in the list" is enforced. The two arrive on DIFFERENT remotes,
    so the list can win the race on the very first use of an ability; that is
    what `setOnClaim` cleans up.

  ### The carry (the client's `carrying`, minecraft controls)
    All of this is inventoryUI.luau. A carry is `{sourceContainer,
    sourceIndex, amount}` and NEVER leaves its slot server-side: pickup sends
    nothing, the slot draws `stack - amount` (ContainerUI:hold, hidden at 0)
    and a ghost ItemUI rides `selection`. So cancelCarry is pure UI and
    nothing can be lost on close/death. Each placement is ONE RF call
    (`spend`); the last one parks the ghost on the target slot and keeps the
    hold until the reply, which is what makes it look instant.
      left press / right press   pick up all / half (ceil)
      release elsewhere          placeAll: whole stack -> move/transfer
                                 (swap) or merge; partial -> splitItem onto
                                 empty or the same item, never a swap
      release on its own slot    STICKY (click-to-pick-up). Then a press
                                 starts a sweep over empty/same slots:
                                 left = 1 slot placeAll, more = even split;
                                 right = one each. Remainder stays held.
      press its own slot         put back (right: one); within DOUBLE_TAP of
                                 the pickup = collectItem
      press off the grid         cancel
    Client stacks match on `name` + a `stack` field (sameStack); the server
    re-checks by id. A recount of the same stack relabels the ItemUI in
    place instead of rebuilding it.

    TOUCH has no hover, so press does double duty: hoverAt runs on the press
    itself, and the release decides what it was. Same slot + under TAP_TIME =
    a tap (equip, via the same hotbarUse); moved = a drag; second tap on the
    same slot inside DOUBLE_TAP = quickMoveItem, since there is no shift key.
    Holding still for LONG_PRESS takes half, touch's right-click. Touch
    never goes sticky.
    ### Hover + a number key (minecraft's slot swap)
    `hotbarSwap(index)` in inventoryUI.luau, tried by the hotbar1..10 binds
    BEFORE hotbarUse; returning false is what falls back to equipping. Only
    fires with the bag open, nothing carried, and `hoverHit` true -- the
    boolean, not refIndex, because refIndex is sticky and a keypress has no
    click to vouch for its position. It is cleared when the bag or a chest
    closes. The hovered slot is the source; hover an EMPTY slot and the roles
    flip so the hotbar item comes to you instead. Same container -> moveItem,
    otherwise transferItem, and like quickMove it is NOT optimistic.
    Works over a chest too, released like any crossing (resolve.cross).

    hoverAt returns FALSE on a miss and the press records nothing on a miss,
    because refIndex is sticky and would otherwise aim a tap at whatever was
    hovered last.

  ### Opening the UI at all
    Keyboard: the ` key (Backquote), in inventoryUI.luau.
    Touch: the topbar icon, `StarterGui/inventory/TopbarIcon`, registered with
    ReplicatedStorage/Modules/TopbarIcons as `touchOnly`. There was NO touch
    entry point before it. Shift-click's mobile stand-in is the double tap
    above.

    Opening also calls `shiftLock.block("inventory", true)`. Shift belongs to
    shift-click while the bag is open, so the camera lock is turned off AND
    the shiftlock bind is sunk for the duration; closing restores whatever the
    player had. See ReplicatedStorage/Modules/ShiftLock.

  ### Opening a chest
    No real world chest exists yet. Both are TEMP DEV chests, don't build on them:
    Workspace/MAP/IslandMain/Systems/Chest/chest hands out every wepList weapon
    (restocked on open, at most once per REGEN s; anything else put in is
    destroyed, Fist too since ROWA/Modules/defaultWep grants it), and
    Workspace/Dev/TestChest keeps items. The flow below is the real one.
    Prompt + lid are ROWA/Modules/chest. ProximityPrompt (16 stud recheck) ->
    plrObj:openChest(container)
      -> closeChest() first, slot.openContainer = container,
      -> S2C newContainer with containerID=nil + container:ToClient()
      -> container:initReplicateServer(remote, 3, plr), handle kept as
         plrObj connection "chest"
    Client builds a fresh ContainerClient at the serialized w/h, calls
    initReplicateClient(remote, 3), ALSO hardcoded 3, opens the backpack
    if closed, and builds an InventoryUI over `otherContainerFrame`.
    Closing (exit button / backpack toggle / new account data) -> C2S
    closeContainer -> plrObj:closeChest() -> calls `container.OnClosed()` if
    present (the chest scripts hang their lid-close tween off it), drops the
    "chest" connection and nils openContainer.
    A newContainer replacing an open one does NOT echo closeContainer: the
    server already closed it, and the echo used to close the NEW one.
    `/viewInv` `/viewHotbar` (admin) open a player's LIVE container down this
    same path, editable. Their slot unloading closes it server-side (else
    drags land in a destroyed container); the client window goes stale, inert.
    Taken items leave the owner's `equippedItem` stale, which only bites if
    the taker equips it before the owner's next hotbar press (it gets put away).

## 7. AUTHORING
  ### A new item type
    1. Copy `Items/uniqueItem/wepItem.luau` (or `stackItem/bananaItem.luau`
       for a stackable -- it's the reference impl, only `new`/`deSerialize`/
       `equip` need overriding, `Serialize`/`ToClient`/`Clone` are generic
       on `stackItem` and work off the runtime metatable).
    2. APPEND it to `itmList` in Items.luau. NEVER renumber; those ids are
       persisted inside slots (GOTCHAS "IDS ARE PERSISTED").
    3. Implement `new`, `Serialize`, `deSerialize`, `ToClient`, and override
       `equip`/`unEquip` if it does anything on equip, always calling
       `baseClass.equip(self, entity)` / `baseClass.unEquip(self)`.
    4. `ToClient` must return `{name = ...}` or ContainerUI falls back to
       `tostring(item)`. It is the ONLY item data the client ever sees; put
       nothing exploitable in it.
    6. `stackable = true` on its own just means Container merges/splits it
       (see \u00a78) -- it does NOT change how Core.luau equips it. bananaItem
       is a normal held item: `equip` reparents a Tool into the character
       (HOLD IT OUT, exactly like toolItem) and `Tool.Activated` (a click
       while it's out) is what actually consumes one. It occupies
       `plrObj.equippedItem` like anything else; there is no more
       stackable-specific branch in Core.luau. An instant-use-on-equip
       consumable is still possible (do the effect inside `equip` and
       `unEquip` yourself, ability-style) but bananaItem is not that.
    5. `unEquip` returning `false` VETOES the swap in Core.luau. wepItem uses
       that to refuse unequipping mid-swing.

  ### Giving an item
    local items = require(game.ServerStorage.ROWA.Items)
    local leftover = plrObj.loadedSlot:insertItem(items.newItem(2, wepId))
    if leftover then leftover:destroy() end
  slotSS:insertItem tries hotbar first, then inventory. `insertTool(tool,
  temp?)` is the Tool-shaped wrapper and dedupes against both containers;
  plrObj also auto-calls it for any Tool that lands in plr.Backpack.
  Set `.temp = true` on anything that must not persist (all admin-granted
  abilities do); `clearTemp` sweeps them on the next LoadSlot.
  In-game: the `/item [targets] <item> <amount>` admin command
  (`loadRowaAdmin/commands/item.luau`) wraps this for any
  `stackable == true` item, resolved by name via `types.item` (a
  `resource()` over `Items.getIds()`, filtered to stackables so a unique
  item's missing constructor args can't be hit by accident). `amount` is
  REQUIRED (no default), same reasoning as `/giveXp`'s amount -- an
  optional trailing number here would compete with the leading optional
  `targets` for the binder's one spare token and lose, see commands.luau's
  comment on that command.

  ### A new chest
    Copy Workspace/Dev/TestChest: NamedContainer.new(w, h, name) at script
    scope, `:insertItem(...)`, then `require(Modules.chest)(model, it)`. It
    owns `.OnClosed`; restock-style logic goes in the 3rd arg, `onOpen`.

## 8. GOTCHAS
  * A chest is one server-wide container; two players inside it edit the
    same slots with no locking.
  * replicationId 3 is hardcoded in THREE places (resolveContainer's `AT`,
    plrObj.replicateChestOpen, inventoryUI.openOutsideContainer). Only one
    outside container can exist per player because of it.
  * `replicationId` (server, lowercase d) vs `replicationID` (client,
    capital D) are DIFFERENT FIELD NAMES on different classes. Not a typo to
    "fix". Grep before renaming either.
  * Any verb that WRITES a client index into `slots` must pass
    `resolve.slot(c, i)` first; an index outside 1..sz parks the item where
    Serialize/ToClient never iterate (invisible, unsaveable). Reads are safe.
  * `moveItem` returns `true` whenever a slot is loaded, even if no container
    matched the id. `transferItem` returns the real boolean.
  * `set()` DESTROYS the displaced item. It is not a swap. Use `move` /
    `transfer` for anything you want to keep.
  * Overflow deletes. `insertItem` hands the item back and every caller
    destroys it. Only dropItem puts things on the floor.
  * "drop" is overloaded: `slotSS:dropAbility` DELETES, `HumObj:DropWeapon`
    un-wields, the client's cancelCarry is UI only. The world drop is
    dropItem/groundItem.
  * STACKING IS WIRED (bananaItem, id 4). `insertItem`'s fill-empty branch
    places the ORIGINAL item straight into an empty slot when the whole
    stack fits (no clone, no RAM churn); `:Clone()` (via absorb) runs only
    when a stack is split. Clone copies `id` and `temp`; anything else a
    leaf needs on a split it must copy itself.
    `stackItem.deSerialize`/`Serialize`/`ToClient`/`Clone` are generic and
    correct to inherit; `new`/`deSerialize` are NOT for a leaf that overrides
    behaviour (`equip` etc) -- they hardcode the target metatable, so a leaf
    must re-`setmetatable` itself after calling the base version, same as
    wepItem/ablityItem already do. bananaItem does this; copy it.
  * `slotSS:insertItem` passes `anyItem`, not `leftover`, to the second
    container. NOT currently a bug: every `Container.insertItem` return
    path hands back the SAME reference it was given (mutated `.stack`) or
    nil, never a distinct object, so `anyItem == leftover` always holds.
    Would break the moment `insertItem` ever returns a genuinely different
    leftover object.
  * `wepItem` persists `wl = 1` when its weapon is in the wielded set, and
    OMITS the key otherwise. The flag lives on the WEAPON (`wep.committed`),
    not the item, so HumObj needs no back-pointer -- `_item` is taken by the
    cooldown path. Set eagerly in `WieldWeapon`, never queried at save time,
    because `UnloadSlot` runs before `SaveData` and a leaving player's
    HumObj may already be gone. Restored in `plrObj/loadChar` by
    `commitFrom`, AFTER cards (one may raise maxWeapons), landing HOLSTERED:
    which hotbar slot was selected is not persisted, so wielding one would
    leave every slot border dark. Absent on old saves = not committed, so
    no slot version bump was needed.
  * Respawn and rejoin are the SAME path here. `onCharacterRemoving` calls
    `UnloadSlot`, which `slot:Serialize()`s into the zstd blob, so items are
    destroyed and rebuilt on every death, not just on a relog.
  * `ablityItem` persists as `aId` (registry id) + `name` (display cache),
    same shape as wepItem's `wId`. It is CONSTRUCTED id-first --
    `items.newItem(3, aId, humObj?)` -- and `.ability` is LAZY: the live
    instance is built by `:bind(humObj)` from `:equip`, because an ability
    binds its humObj at construction and deSerialize runs before loadChar
    has one (and on a respawn the one there is the DEAD one). Consequences:
    test `.aId` to identify an ability item, nil-guard `.ability`, and read
    the label through `:getName()` (which avoids requiring the class when a
    serialized name is present).
    It DID silently fail to save until this was fixed: Serialize wrote only
    `data.name` while deSerialize demanded `data.aId`, and every giver set
    `.temp = true`, which Container.Serialize skips outright.
  * `toolItem.deSerialize` finds its Tool by NAME scanning
    `ServerStorage/ROWA/Tools:GetDescendants()` and errors (item dropped) if
    it's missing. Renaming a Tool deletes it from every save; any other Tool
    source (e.g. `/weapon`'s Template, used for unregistered weps) must be
    inserted `temp`.
  * `plrObj.equippedItem` is written in Core.luau, is NOT in plrObj's type,
    and is NOT cleared on death or UnloadSlot. Expect a stale reference.
  * The client mirror stores SERIAL TABLES, not item objects. `.equipped`,
    `.id`, `:destroy()` do not exist there. Only `.name` is safe to read.
  * Grid sizes are duplicated: `Container.new(10,3)/(10,1)` in slotSS and
    `container.new(10,3)/(10,1)` in inventoryUI.luau, plus CELL_SIZE 65 in
    Inventory/HotbarUI and 60 in the ContainerUI base. Change one, change all.
  * A slot cooldown dies with its ItemUI. ContainerUI rebuilds the ItemUI on
    every itemUpdated except a same-name recount, so moving an item
    mid-cooldown loses the wipe. Equipping does NOT rebuild it (that path is
    onEquipped), and an ability self-unequips, so the common case survives.
    The recount exception keys on the SLOT: swapping two same-name stacks
    across containers leaves an equip border where it was.
  * CooldownClaims is PERMANENT for the session and has no release. An id
    that has ever been drawn on a slot never returns to the list, even if
    the item is gone. That is intentional; don't add a release without
    thinking about the two-remote race in §6.
  * The three CELL_SIZE constants are still duplicated, and `hoverAt` reads
    all three grids every mouse move. Fine at 10x3, watch it if grids grow.
  * `quickMoveItem` is deliberately NOT optimistic. If you make it so,
    you have to predict the server's destination slot, which is the one
    thing the verb exists to avoid.
  * The inventory topbar icon sits in the `inventory` ScreenGui, which has
    IgnoreGuiInset = FALSE unlike settings/EmoteUi. TopbarIcons subtracts
    the inset back out per-gui, so do not "fix" its Y by hand; set `order`
    and let layout() place it.
  * `openInventory` (enum 5) is purely the floating "inventory" billboard
    over the character. It gates NO inventory logic; the server never tracks
    whether your bag is open.
