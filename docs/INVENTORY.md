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
      {moveItem,transferItem,quickMoveItem}.luau    the 3 RF verbs
      resolveContainer.luau                         their shared auth lookup
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
  * `_container` back-pointer bookkeeping. `set`/`transfer`/`destroy` are
    overridden ONLY to keep `item._container` pointing at its owner. Items
    need it because `item:equip()` fires `self._container.onEquipped`.
  * `onEquipped: Signal<equipping:boolean, item>`: the third signal, server
    only. Fired BY THE ITEM, not by the container.
  * `onCooldown: Signal<item, seconds, cdId>`: the fourth, server only.
    Fired by CombatAction.triggerCD through `item._item`, see §6.
  * `insertItem(item) -> leftover?`: first-fit. Unique items take the first
    nil slot. Returns the item back if there's no room; EVERY caller
    currently just `leftover:destroy()`s it, i.e. overflow = deletion.
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
  it stamps `self.replicationId` and connects all four server signals to
  `FireClient(plr, containerID, <enum>, ...)`. The ItemUpdated payload goes
  through `itm:ToClient()` first. onEquipped carries no index, so it LINEAR
  SCANS slots to find the item: O(sz) per equip, flagged TODO in source.
  onCooldown carries the item too and scans the same way.

  `ContainerClient:initReplicateClient` is the mirror: it stamps
  `self.replicationID` and installs `SubscribedEventCB(enumId, ...)` which
  replays set/move/onEquip locally. It validates nothing; it is a mirror,
  never a source of truth.

  ### The three RemoteFunction verbs (RFHandler manifold)
    moveItem(replicationID, prevIndex, newIndex)
    transferItem(fromId, toId, fromIndex, toIndex)
    quickMoveItem(fromId, fromIndex)              -- shift-click
  All three resolve ids through `RFHandler/resolveContainer`, which returns
  `{loadedSlot.hotbar, loadedSlot.inventory, loadedSlot.openContainer}` and
  the plrObj. A player can only ever name containers they personally have
  loaded or open. That lookup IS the auth model here, and it is sound. It
  used to be copy-pasted into each verb; a new verb calls `resolve.all` +
  `resolve.byId` and does NOT grow a fourth copy.

  `quickMoveItem` names NO destination. The server routes it:
    chest open : hotbar/inventory -> chest,  chest -> inventory then hotbar
    no chest   : hotbar <-> inventory
  and drops it in the first free slot, so it is the only verb that cannot
  be handed an out-of-range index (see the bounds-check gotcha in §8). It
  is also the only one the client does NOT optimistically mirror: it just
  waits for the two itemUpdated that `transfer` fires. If the destination
  is full it returns false and nothing moves, same as minecraft.
  Moving an EQUIPPED item into a chest unequips it first, and a refusing
  `unEquip` (wepItem mid-swing) vetoes the whole move.

  Client uses RF (not RE) because drag-and-drop needs a yes/no back: it
  optimistically reparents the item frame, then rolls the reparent back if
  the server returns falsy. The source already flags the race window.

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
      item is an ability-> item:equip(humObj), return (abilities do not
                           occupy the single equipped-item slot; they
                           self-unequip after use). "is an ability" is
                           `item.aId ~= nil`, NOT `item.ability`, which is
                           lazy and nil until :bind runs.
      otherwise         -> unEquip the current plrObj.equippedItem (BAIL if
                           it refuses), then item:equip(humObj), store it.
    Clicking a hotbar cell with the mouse routes into the same hotbarUse.
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
                    the Backpack (or ServerScriptService if the char is gone)

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

  ### Dragging an item (the client's `carrying`)
    All of this is inventoryUI.luau; nothing about it is replicated.
      hover   InputChanged (MouseMovement OR Touch) -> hoverAt(p) -> sets
              refContainer/refIndex/prevFrame + moves the `selection` frame.
      press   startCarry: reparents the item's Frame INTO `selection` (so it
              rides the highlight) and records sourceFrame/sourceIndex.
      release stopCarryAndSendRequest: moveItem or transferItem, optimistic
              reparent first, rolled back if the server returns falsy.
      abort   cancelCarry: puts the Frame back in sourceFrame and clears
              `carrying`.
    `cancelCarry` is the one to remember. A carried Frame lives in `selection`,
    NOT in its slot, so anything that hides or rebuilds the grid while a drag
    is live has to call it or the item reads as deleted. It is wired into
    triggerbackpack (closing), closeOutsideContainer, and release-over-nothing.
    startCarry also self-heals: if `carrying` exists but its Frame was
    destroyed under it (a server itemUpdated for that slot), it cancels the
    stale carry instead of refusing forever.

    TOUCH has no hover, so press does double duty: hoverAt runs on the press
    itself, and the release decides what it was. Same slot + under TAP_TIME =
    a tap (equip, via the same hotbarUse); moved = a drag; second tap on the
    same slot inside DOUBLE_TAP = quickMoveItem, since there is no shift key.
    ### Hover + a number key (minecraft's slot swap)
    `hotbarSwap(index)` in inventoryUI.luau, tried by the hotbar1..10 binds
    BEFORE hotbarUse; returning false is what falls back to equipping. Only
    fires with the bag open, nothing carried, and `hoverHit` true -- the
    boolean, not refIndex, because refIndex is sticky and a keypress has no
    click to vouch for its position. It is cleared when the bag or a chest
    closes. The hovered slot is the source; hover an EMPTY slot and the roles
    flip so the hotbar item comes to you instead. Same container -> moveItem,
    otherwise transferItem, and like quickMove it is NOT optimistic.
    Works over a chest too, which inherits transferItem's hole: it does NOT
    unEquip on the way in (quickMoveItem is the only verb that does).

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
    the shift key is unbound for the duration; closing restores whatever the
    player had. See ReplicatedStorage/Modules/ShiftLock.

  ### Opening a chest
    Workspace/{Chest,SmallChes}/chest.luau builds ONE NamedContainer at
    server start and stuffs it. ProximityPrompt (16 stud recheck) ->
    plrObj:openChest(container)
      -> closeChest() first, slot.openContainer = container,
         container.replicationId = 3 (HARDCODED),
      -> S2C newContainer with containerID=nil + container:ToClient()
      -> container:initReplicateServer(remote, 3, plr)
    Client builds a fresh ContainerClient at the serialized w/h, calls
    initReplicateClient(remote, 3), ALSO hardcoded 3, opens the backpack
    if closed, and builds an InventoryUI over `otherContainerFrame`.
    Closing (exit button / backpack toggle / new account data) -> C2S
    closeContainer -> plrObj:closeChest() -> calls `container.OnClosed()` if
    present (the chest scripts hang their lid-close tween off it) and nils
    openContainer.

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
    NamedContainer.new(w, h, name) at script scope, `:insertItem(...)`,
    `plrObj:openChest(it)` from your prompt. Set `.OnClosed` for lid VFX.

## 8. GOTCHAS
  * SHARED CHESTS LEAK CONNECTIONS. `openChest` calls `initReplicateServer`
    EVERY time ANY player opens the chest, and `closeChest` disconnects
    NOTHING. Open a chest N times and its signals fire N times, to every
    player who ever opened it, forever. The container is one server-wide
    instance; two players inside it edit the same slots with no locking.
    Fix this before shipping chests widely.
  * replicationId 3 is hardcoded in THREE places (plrObj.openChest,
    plrObj.replicateChestOpen, inventoryUI.openOutsideContainer). Only one
    outside container can exist per player because of it.
  * `replicationId` (server, lowercase d) vs `replicationID` (client,
    capital D) are DIFFERENT FIELD NAMES on different classes. Not a typo to
    "fix". Grep before renaming either.
  * NO INDEX BOUNDS CHECK on move/transfer, client-side or server-side.
    `newIndex` comes from the client and is written straight into `slots`.
    An index outside 1..sz silently parks the item where Serialize/ToClient
    never iterate. It still exists in memory but is invisible and
    unsaveable. Clamp in `moveItem`/`transferItem` if you harden anything.
  * `moveItem` returns `true` whenever a slot is loaded, even if no container
    matched the id, so the client's optimistic reparent sticks on a no-op.
    `transferItem` returns the real boolean.
  * `set()` DESTROYS the displaced item. It is not a swap. Use `move` /
    `transfer` for anything you want to keep.
  * Overflow deletes. `insertItem` hands the item back and every caller
    destroys it. There is no "drop on the floor" path.
  * STACKING IS WIRED (bananaItem, id 4). `insertItem`'s fill-empty branch
    places the ORIGINAL item straight into an empty slot when the whole
    stack fits (no clone, no RAM churn); `:Clone()` is called ONLY when a
    stack bigger than `maxStack` has to split across multiple empty slots.
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
    `ServerStorage/ROWA/Tools:GetDescendants()` and indexes nil if the Tool
    was renamed or removed. Renaming a Tool breaks every save holding it.
  * `plrObj.equippedItem` is written in Core.luau, is NOT in plrObj's type,
    and is NOT cleared on death or UnloadSlot. Expect a stale reference.
  * The client mirror stores SERIAL TABLES, not item objects. `.equipped`,
    `.id`, `:destroy()` do not exist there. Only `.name` is safe to read.
  * Grid sizes are duplicated: `Container.new(10,3)/(10,1)` in slotSS and
    `container.new(10,3)/(10,1)` in inventoryUI.luau, plus CELL_SIZE 65 in
    Inventory/HotbarUI and 60 in the ContainerUI base. Change one, change all.
  * A slot cooldown dies with its ItemUI. ContainerUI destroys and rebuilds
    the ItemUI on every itemUpdated, so moving an item mid-cooldown loses
    the wipe. Equipping does NOT rebuild it (that path is onEquipped), and
    an ability self-unequips, so the common case survives.
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
