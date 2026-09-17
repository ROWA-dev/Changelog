# DATASTORE - player persistence, serialization & slots
(index: parent ServerStorage/README.md)

How a player's bytes get off the DataStore, into class instances, and back.
If you touch ANY field that ends up saved, read VERSIONING and GOTCHAS first.

## 1. THE PIECES
  ServerStorage/ROWA/Class/plrObj/DataStore.luau   Fetch/Save. The only place
                                                   that talks to DataStoreService
                                                   ABOUT PLAYER DATA -- see
                                                   THE OTHER STORE below.
  ServerStorage/ROWA/Class/plrObj.luau             owns .Data, FetchData/SaveData
  ServerStorage/ROWA/Class/PlrData.luau            the root save object
  ServerStorage/ROWA/Class/PlrData/Slots.luau      compressed slot table
  ServerStorage/ROWA/Class/PlrData/Slots/slotSS.luau  one character slot (server)
  ServerStorage/ROWA/Class/PlrData/PlrStats.luau   lifetime combat counters
  ServerStorage/ROWA/Class/PlrData/flagEnums.luau  bit ids for the SparseBitSet
  ServerStorage/ROWA/Class/SparseBitSet.luau       flags/cards -> EliasFano buffer
  ServerScriptService/PlrHandler.luau              Player -> plrObj registry
  ServerStorage/ROWA/Class/plrObj/replication.luau C2S/S2C data + slot sync
  ServerStorage/ROWA/Class/plrObj/DataUtils.luau   verifyAndMerge for client input

Store: `DataStoreService:GetDataStore("plrDataV3")`, key = `tostring(plr.UserId)`.
MemoryStoreService is required at the top of DataStore.luau but is currently
UNUSED (there is no session lock, see GOTCHAS).

## 1b. THE OTHER STORES  (ROWA/Modules/imgBoard)
  There are TWO DataStoreService callers now. This doc used to say one.

  imgBoard is the phone's image board. It is NOT player data and shares
  nothing with plrDataV3 -- own store names, own keys, no PlrData field, no
  migration path. It can be wiped whole without touching a save, and that is
  the entire reason it is separate.

  It owns TWO store names, both lazy and both wipeable:
    imgBoardV1        posts, pages, comments, the per-player gallery and
                      starred ring. GetDataStore.
    imgBoardStarsV1   star counts only, GetOrderedDataStore, because ranking
                      needs GetSortedAsync and IncrementAsync.

  TWO OF ITS KEY KINDS ARE PER-PLAYER and so are NOT bounded the way the
  board is: `g_<userId>` (Draw's gallery, 128KB cap) and `us_<userId>` (what
  that player starred, 100 ids). They grow with the playerbase, like saves do.
  Still not player data, still wipeable, but count them when reading usage.

  WHAT YOU MUST KNOW HERE: storage is pooled PER EXPERIENCE, so that board
  spends the same budget these saves do. It is bounded on purpose -- a byte
  budget with oldest-page eviction, and a per-post cap. If saves ever start
  throttling, that budget is the first thing to look at.

  Design, limits and the numbers behind them:
  ROWA/Emotes/Phone/rowaPhone/Apps/ImgBoard_Plan.md

## 2. THE OBJECT GRAPH
  plrObj                     (per Player, ServerScriptService/PlrHandler registry)
   |- .Data      : PlrData   (the whole account)
   |   |- version, err, seed, elo, wins, loss
   |   |- flags    : SparseBitSet  (flagEnums: TutorialDone/Moderator/Admin/VIP/BloodEnabled)
   |   |- meta     : { first, last, totalPlaytime, clientInfo?, followedIds?, regionsData? }
   |   |- plrStats : PlrStats      (StatPair per Parry/Block/Dodge/Dmg... + feints)
   |   |- keybindData, touchData?, emoteData (emote id per wheel slot)
   |   |- extra    : {any}
   |   \- slots    : Slots         (ONE zstd buffer holding every slot)
   \- .loadedSlot : slotClass?     (the ONE decompressed slot in play)
      .loadedSlotId : number       (0 == none; `:IsSlotLoaded()`)

Account-level stuff (elo/wins/loss/flags/keybinds) lives on PlrData.
Per-character stuff (inventory, hotbar, lvl/exp, baseStats, cards, lives)
lives on the slot.

## 3. LOAD PATH
  Players.PlayerAdded  (ServerScriptService/Core.luau OnPlrAdd)
    -> plrHandler.Get(plr)           -- registers, plrObj.new
    -> plrObj:initReplicateServer(PlayerRepli)
    -> plrObj.OnDataLoaded:Once(...) -- clientInfo + FollowUserId bookkeeping
    -> plrObj:FetchData()            -- YIELDS, GetAsync
    -> plrObj:LoadData(data)         -- sets .Data, fires OnDataLoaded

  FetchData == DataStore.Fetch -> plrDataFetch:
    pcall GetAsync
      fail  -> new PlrData with `.err = "[ERR] ..."`   (NEVER saved, see below)
      nil   -> brand new PlrData (first-time player)
      table -> PlrData.deSerialize(plr, serial) -> migrateData

  Slot load is client-driven: C2S.LoadSlot -> plrObj:LoadSlot(id)
    -> Data.slots:getAndLoadSlot(id)  (decompress + slotSS.deSerialize)
    -> inventory/hotbar :initReplicateServer, :clearTemp, re-insert Backpack tools
    -> _onLoadSlot fires -> draftOffer.audit(slot) re-grades saved cards/abilities
       against today's reqs, THEN S2C.SlotData (ZstdUtil.compress(slot:ToClient()))
       + loadChar(char, slot, self)

## 4. SAVE PATH
  PlayerRemoving (Core.luau) -> plrHandler.Unregister(plr) -> plrObj:destroy()
    destroy() order: UnloadSlot -> destroy signals -> SaveData -> closeChest
  Admin command `saveData` (ROWA/Modules/loadRowaAdmin/commands/save) also
  calls plrObj:SaveData() on demand.

  DataStore.Save early-returns TRUE (a no-op "success") when:
    * self.Data == nil             -- data never finished loading
    * newData.err ~= nil           -- poisoned load, refuse to overwrite
    * slots:countValidSlots() == 0 -- nothing worth writing

  Then it:
    1. if a slot is loaded, archives it: slots:setSlot(loadedSlotId, loadedSlot)
    2. folds sessionTime into meta.totalPlaytime, sets meta.last, ZEROES
       self.sessionTime (deliberate, so a re-save can't double-count)
    3. if workspace:GetAttribute("region") and session > 30s, updates
       meta.regionsData[region] = { first, last, ping, playTime }
    4. serial = PlrData.Serialize(newData)   (table.freeze'd)
    5. prints payload size via Utils/tableToBytes
    6. UpdateAsync: if deepEqual(oldData, serial) it returns oldData and
       SKIPS the write; otherwise writes and logs a deepCompare diff
    7. on pcall failure -> warn + Webhook.basicMessage2("dataSave Error")

  sessionTime accrues in plrObj.TriggerPing (ping deltas under 10s only).

## 5. SERIALIZATION FORMAT
  PlrData.Serialize -> plain table, frozen. flags/slots/plrStats become
  their own compact forms:
      flags     -> SparseBitSet:Serialize() -> EliasFano buffer
      plrStats  -> array of 10 entries (8 StatPairs then feints, feint2s),
                   POSITIONAL. Appending is safe, reordering is not.
      slots     -> a single `buffer`

  Slots is the interesting one: it keeps `_slotsCompressed`, a zstd(level 22)
  buffer of JSONEncode({ [slotId] = slotSerial }). It NEVER holds live slot
  objects. Every getSlot/setSlot/countValidSlots decompresses, works, and
  (for setSlot) recompresses. Cheap to store, NOT cheap to poll in a loop.

  ToClient variants are separate and censored:
    PlrData:ToClient()  -> version, slots:ToClient(), elo/wins/loss, keybinds,
                           touch, emoteData
    Slots:ToClient()    -> compressed array of just `{ name = ... }` per slot
    slot:ToClient()     -> full slot, sent only for the slot you actually loaded

  NOTE PlrData:ToClient() does NOT include plrStats, flags, meta or extra. The
  client cannot see any of them by default; see the SlotInfo pull in section 7.

## 6. VERSIONING & MIGRATION
  CURRENT_PLR_DS_VERSION = 52   (PlrData.luau, line 2)
  CURRENT_SLOT_VERSION   = 6    (Slots/slotSS.luau, line 2)

  PlrData.deSerialize rebuilds a fresh object, copies fields across, then
  calls migrateData(key, new). migrateData:
    * no-ops if version >= CURRENT
    * otherwise builds `module.new()` as the up-to-date reference and
      `deepMerge(outDated, upToDateReference, "data")`, so old values win where
      they exist and new defaults fill the gaps, then stamps the new version.

  So: ADDING a field = bump CURRENT_PLR_DS_VERSION and give it a default in
  `.new()`. That's it. RENAMING or RETYPING a field is NOT handled by
  deepMerge; you need bespoke code before the merge.

  Slots migrate inside slotSS.deSerialize. The v5 migration preserves saved
  prog/stats/cards while normalizing old slots to Progression.md. Its pre-v6
  branches are UNREACHABLE while the wipe below is live (nothing under 6
  survives the sweep); left in deliberately, delete with the sweep.

  WIPE_BELOW_VERSION (Slots.luau) is the GLOBAL slot wipe: Slots.deSerialize
  sweeps the decompressed table on load and rebuilds every slot stamped below
  it from defaults, keeping only name + meta. Account data is untouched -- it
  is not in that buffer. Deliberately NOT CURRENT_SLOT_VERSION, so bumping
  that for a new field never wipes.

  TO WIPE AGAIN: set BOTH to the same next number, CURRENT_SLOT_VERSION
  (slotSS.luau line 2) and WIPE_BELOW_VERSION (Slots.luau). They must stay
  EQUAL. If WIPE_BELOW ends up ABOVE CURRENT_SLOT, fresh slots stamp the lower
  number, the sweep matches them again, and EVERY PLAYER WIPES ON EVERY JOIN,
  silently, with a zstd-22 recompress each time. Nothing iterates the
  DataStore: an account wipes when it next loads and persists on its next
  save. Verify by joining twice; the wipe warn must print exactly once.

  The sweep is pcall'd because PlrData.deSerialize is NOT protected
  (DataStore.luau plrDataFetch) and a throw there fails the login. It is
  TEMPORARY; delete it once the playerbase has rolled over.

## 7. CLIENT-WRITABLE DATA (attack surface)
  Only four C2S paths mutate saved account data, all in plrObj/replication.luau:
    C2S.SaveKeybinds   -> DataUtils.verifyAndMerge + verifyKeybinds
    C2S.SaveTouchData  -> DataUtils.verifyAndMerge + VerifyTouchData
    C2S.SaveEmotes     -> DataUtils.verifyAndMerge + verifyEmotes
    C2S.ResetKeybinds  -> defaults
  PlrData.deSerialize runs ALL THREE through the same verifyAndMerge on LOAD, via
  its `merged` helper. They used to be assigned raw, so a save predating a field
  had no entry for it and the consumers -- which walk the SAVED table -- silently
  dropped it: a new bind was unpressable AND unrebindable (setupBinds skips it,
  the settings list `continue`s past it) until a keybind reset. Same for a new
  touch button or wheel slot. Adding one now needs a default and nothing else.
  On LOAD the fallback is the SAVE, not the defaults: a load must never wipe.
  (On SAVE the fallback is refusal, which is why that side webhooks instead.)

  verifyAndMerge NEVER trusts the client table: it clones the default, merges
  the input into the clone, runs the verifier, and returns nil+err on failure
  (which webhooks a "Data Format Violation"). Keep that shape for any new
  client-writable field. Bounds: keybinds are whole numbers in [-1, 1048],
  touch buttons are whole numbers in [0, 255], emote ids must be REGISTERED
  (Emotes.isValidId), and deepMerge pins the loadout to the default's LENGTH,
  so a client can reorder slots but never add one.

  Slot mutations (AllocateStat / AllocateWeaponStat / AllocateElement) are
  server-validated inside slotSS (allocPts > 0, MAX_STAT = 10).

  DESTRUCTIVE and client-triggered: C2S.WipeSlot (settings Slot tab) forwards to
  plrObj:WipeSlot, the same call the wipeslot admin command makes. It takes NO id
  -- it wipes loadedSlotId, so there is nothing on the wire to aim at another slot.
  Gated on a slot being loaded (inverse of NewSlot) plus a 2s float. The two-click
  confirm is CLIENT side only; treat the route itself as unconfirmed.

  READ-ONLY but still client-triggered: C2S.RequestSlotInfo -> S2C.SlotInfo,
  the settings Slot tab's data source (replication.luau buildSlotInfo).
  Returns account plrStats as two labelled groups (taken/dealt), account
  elo/wins/loss/playtime, live slot elo/kills/lives/credits, resolved card
  NAMES and flag names. Rate-gated to 1s per player by one float.

  It is a PULL on purpose. plrStats increments on EVERY hit (loadChar's
  onAttack/onAttacked hooks), so pushing it would cost a packet per swing.
  It also carries elo/wins/loss/lives/credits, which never go through
  applyPatch and are otherwise frozen at slot-load time on the client.

  The payload is assembled server-side because SparseBitSet, ROWA/Cards and
  PlrStats/StatPair all live in ServerStorage. Resolving there is what keeps
  the client from needing any of them. Keep that shape if you extend it.
  Card ids are persisted and Cards.getCardName THROWS on an id that left the
  registry, so that lookup is pcall'd.

## 8. GOTCHAS
  * NO SESSION LOCKING. Two servers holding the same player will both
    UpdateAsync and last-write-wins. MemoryStoreService is imported but never
    used. Don't assume duplicate-login safety.
  * `err` is a tombstone. Any PlrData carrying `.err` is permanently
    unsaveable for that session. Intentional (better to lose a session than
    to nuke a real save), but it means "my progress didn't save" reports
    start by grepping join logs for "[ERR]".
  * Serialize returns a FROZEN table. Mutating the result throws. Mutate
    `.Data` and re-serialize instead.
  * BindToClose (Core.luau) only `wait(15)`; it does NOT save. Saves ride on
    PlayerRemoving -> Unregister -> destroy. On shutdown that wait is the
    only thing giving those saves time to land.
  * plrObj:destroy() calls UnloadSlot BEFORE SaveData. That ordering is what
    archives the live slot back into Data.slots. Don't reorder.
  * Save zeroes self.sessionTime. A second save in the same session
    contributes 0 playtime, by design.
  * migrateData sets `upToDateReference.touchData = module.cloneDefaultKeybinds()`
    (KEYBINDS, not cloneDefaultTouchButtons). Looks like a copy-paste bug; it
    only affects the "did touchData change from default" comparison, but
    verify before touching it.
  * Slots type declares `deSerialize: (plr, data)` but the implementation is
    `deSerialize(data)`. Call it with one arg (PlrData does).
  * Slots.deSerialize silently returns a BRAND NEW slot set if the stored
    value isn't a buffer ("data is old..."). That's a wipe path; pre-buffer
    saves are already gone. Remember it if you change compression again.
  * countValidSlots deserializes every slot just to count them, and it runs
    on every save. Don't call it casually.
  * Slots.deSerialize now decompresses on EVERY load for the wipe sweep. That
    cost is the reason the sweep is temporary. Re-check it if you keep it.
  * Item/weapon/ability numeric ids are persisted inside slots. See
    GOTCHAS "IDS ARE PERSISTED, NEVER RENUMBER". Same rule for
    flagEnums: only append.
  * The zstd path (Slots, ZstdUtil) round-trips through JSON, so it can't
    preserve sparse/mixed array keys, NaN, inf, or non-string table keys.
    Slot ids survive only because they're re-indexed after decompression, so
    don't lean on numeric key identity there.
  * The commented-out msgpack + EncodingService block in DataStore.Save is a
    parked experiment for compressing the whole payload. Leave it or delete
    it, but don't half-enable it.

## 9. ADDING A NEW SAVED FIELD (checklist)
  1. Add it to `serialData` AND `myself` types in PlrData.luau.
  2. Default it in `module.new()`.
  3. Copy it in `Serialize` and `deSerialize`.
  4. Decide if the client needs it -> `ToClient` (censor anything exploitable).
  5. Bump CURRENT_PLR_DS_VERSION.
  6. If clients can write it, add a verifier + DataUtils.verifyAndMerge path.
  7. Join on an existing account, confirm the migrate log prints once and the
     field survives a rejoin.
