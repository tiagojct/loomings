# Web Data Safety Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent wrong-file writes, lost edits, cross-tab draft loss, false deletion success, and citation-marker hangs.

**Architecture:** File pickers return unadopted handles. The editor adopts a handle only after load confirmation. The session serializes saves and adopts snapshots only when the buffer is unchanged. Scratch records use a per-tab key. Document deletion uses one IndexedDB transaction. Citation markers use bounded one-pass allocation.

**Tech Stack:** JavaScript ES modules, CodeMirror 6, IndexedDB, Vitest, fake-indexeddb, happy-dom.

**Spec:** `docs/superpowers/specs/2026-11-24-stabilization-design.md`

## Global Constraints

- Preserve public APIs unless a task explicitly replaces them.
- Add a regression test before each behavioral fix.
- Run `npm test` and `npm run typecheck` after each task.
- Keep changes consistent with existing JavaScript style.
- Do not commit `macos/plans/`.
- Do not change the web version for this work.

## Review Focus

- Cancel Open after picking a new file. Save must still target the old file. Task 1 pins this.
- Edit during Save As or browser Save. The new edit must remain dirty. Task 4 pins this.
- Fire three saves together. Writes must run in order. Task 3 pins this.
- Save one tab while another tab has a draft. The other draft must survive. Task 5 pins this.
- Use every private-use code unit in a cited document. Citation output must terminate. Task 7 pins this.

---

### Task 1: Return file handles without adopting them

**Files:**
- Modify: `src/browser.js:171-267`
- Modify: `src/browser.js:367-391`
- Modify: `src/browser.js:676-742`
- Modify: `src/editor.js:2306-2332`
- Test: `src/browser.test.js:110-130`

**Interfaces:**
- Consumes: existing File System Access handles.
- Produces: `openFile()`, `openHandle(handle)`, and `openRecent(entry)` return `{path, content, handle}`.
- Produces: `adoptFileHandle(handle)` sets the active handle.
- Produces: `forgetFile()` remains the explicit clear operation.

- [ ] **Step 1: Write failing handle-ownership tests**

Add tests that:

- `openHandle(newHandle)` returns `handle: newHandle`.
- `hasFileHandle()` still reports the previous handle after `openHandle`.
- `adoptFileHandle(newHandle)` changes the active handle.
- A failed read never changes the active handle.
- `openRecent(entry)` returns its handle without adopting it.

- [ ] **Step 2: Run the browser tests**

Run: `npx vitest run src/browser.test.js`
Expected: FAIL because returned payloads have no `handle` and no `adoptFileHandle` export exists.

- [ ] **Step 3: Implement unadopted handle payloads**

Remove direct `currentFileHandle` assignments from picker, recent, launch, and drop paths.
Return the selected handle in the payload.
Add `adoptFileHandle(handle)`.

- [ ] **Step 4: Adopt handles after load confirmation**

In `loadFile`, call `adoptFileHandle(payload.handle ?? null)` after discard confirmation.
Call it before `addRecent`.
Keep `forgetFile()` for content with no file.

- [ ] **Step 5: Run browser tests and typecheck**

Run: `npx vitest run src/browser.test.js && npm run typecheck`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add src/browser.js src/editor.js src/browser.test.js
git commit -m "fix: bind opened file handles after load confirmation"
```

---

### Task 2: Capture save targets and abort failed writes

**Files:**
- Modify: `src/browser.js:171-205`
- Modify: `src/editor.js:1215-1232`
- Test: `src/browser.test.js`

**Interfaces:**
- Produces: `saveFile(path, content, handle = currentFileHandle)`.
- Produces: `saveFileAs(content, suggestedName)` returns `{path, handle}` or `null`.
- `saveFileAs` no longer changes the active handle.

- [ ] **Step 1: Write failing save-target tests**

Add tests that:

- Replacing the active handle during `queryPermission` does not redirect `saveFile`.
- `saveFileAs` writes the picked handle and returns it without adopting it.
- A failed `writable.write` calls `writable.abort`.
- A successful write calls `writable.close`.

- [ ] **Step 2: Run the browser tests**

Run: `npx vitest run src/browser.test.js`
Expected: FAIL because `saveFile` reads the mutable global after awaits and `saveFileAs` adopts directly.

- [ ] **Step 3: Capture the handle before the first await**

Use the captured handle for permission, writable creation, write, and close.
Abort the writable stream on write or close failure.

- [ ] **Step 4: Return Save As ownership to the editor**

Return `{path: handle.name, handle}` from the File System Access path.
Return `null` from the download fallback.
Update `handleSaveAs` to adopt the returned handle before `session.adopt(text)`.

- [ ] **Step 5: Run browser tests and typecheck**

Run: `npx vitest run src/browser.test.js && npm run typecheck`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add src/browser.js src/editor.js src/browser.test.js
git commit -m "fix: capture file handles for each save operation"
```

---

### Task 3: Serialize every save through one queue

**Files:**
- Modify: `src/session.js:141-172`
- Test: `src/session.test.js:130-147`

**Interfaces:**
- Produces: `saveNow()` keeps its existing signature and boolean result.
- All calls execute through one promise queue.

- [ ] **Step 1: Write the three-save regression test**

```js
it('serialises three overlapping saves', async () => {
  const pending = [];
  const { session, calls } = makeSession({
    write: () => new Promise((resolve) => pending.push(resolve)),
  });

  session.markEdited();
  const first = session.saveNow();
  const second = session.saveNow();
  const third = session.saveNow();
  expect(calls.written).toHaveLength(1);

  pending.shift()();
  await first;
  expect(calls.written).toHaveLength(2);

  pending.shift()();
  await second;
  expect(calls.written).toHaveLength(3);

  pending.shift()();
  await third;
});
```

- [ ] **Step 2: Run the session tests**

Run: `npx vitest run src/session.test.js`
Expected: FAIL with three writes started after the first completion.

- [ ] **Step 3: Replace the lock check with a promise queue**

Chain each save after the previous settled promise.
Keep generation and content checks inside the queued write.
Ensure a rejected write cannot poison later saves.

- [ ] **Step 4: Run the session suite**

Run: `npx vitest run src/session.test.js`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/session.js src/session.test.js
git commit -m "fix: serialise overlapping document saves"
```

---

### Task 4: Preserve edits made during external saves

**Files:**
- Modify: `src/session.js:119-199`
- Modify: `src/editor.js:1201-1224`
- Test: `src/session.test.js`

**Interfaces:**
- Produces: `adopt(text)` returns `true` when the buffer matches `text`.
- Produces: `adopt(text)` returns `false` when newer edits remain.
- A false result keeps the buffer dirty and rearms scratch and autosave timers.

- [ ] **Step 1: Write failing adoption tests**

Add tests that:

- `adopt('saved')` clears a matching buffer.
- `adopt('saved')` keeps a changed buffer dirty.
- The changed buffer writes its newest text to scratch.
- The changed buffer autosaves to the new home after `SAVE_DELAY`.

- [ ] **Step 2: Run the session tests**

Run: `npx vitest run src/session.test.js`
Expected: FAIL because `adopt` always clears the buffer.

- [ ] **Step 3: Implement snapshot-aware adoption**

Factor timer arming from `markEdited`.
In `adopt`, compare `content()` with the saved snapshot.
Clear only a matching buffer.
Otherwise mark dirty and arm timers for the new home.

- [ ] **Step 4: Use the adoption result in both save paths**

Keep the existing status messages.
Do not clear scratch when `adopt` returns false.
Ensure Save As changes the home before adoption.

- [ ] **Step 5: Run session tests and typecheck**

Run: `npx vitest run src/session.test.js && npm run typecheck`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add src/session.js src/editor.js src/session.test.js
git commit -m "fix: preserve edits made during browser and Save As writes"
```

---

### Task 5: Isolate scratch drafts and report clear failures

**Files:**
- Modify: `src/browser.js:656-668`
- Modify: `src/editor.js:2588-2606`
- Test: `src/browser.test.js:98-108`

**Interfaces:**
- Produces: `saveScratch(content, currentFile, clientId = scratchClientId())`.
- Produces: `readScratch(clientId = scratchClientId())`.
- Produces: `clearScratch(clientId = scratchClientId())` rejects on storage failure.
- Scratch keys use `scratch:<clientId>`.
- `readScratch` falls back to the legacy `scratch` key once.

- [ ] **Step 1: Write failing scratch-isolation tests**

Add tests that:

- Two client IDs store independent drafts.
- Clearing client A leaves client B unchanged.
- A failed delete rejects from `clearScratch`.
- The legacy `scratch` key remains readable when no namespaced key exists.

- [ ] **Step 2: Run the browser tests**

Run: `npx vitest run src/browser.test.js`
Expected: FAIL because all operations use one key and clear failures are swallowed.

- [ ] **Step 3: Add a per-tab client ID**

Use `sessionStorage` with key `loomings_scratch_client`.
Generate a UUID when the key is absent.
Use the namespaced key for save, read, and clear.

- [ ] **Step 4: Contain recovery clear failures**

Catch `clearScratch` failure in `offerScratchRecovery`.
Show a status message and keep the draft.

- [ ] **Step 5: Run browser and session tests**

Run: `npx vitest run src/browser.test.js src/session.test.js`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add src/browser.js src/editor.js src/browser.test.js
git commit -m "fix: isolate scratch drafts between browser tabs"
```

---

### Task 6: Delete browser documents atomically

**Files:**
- Modify: `src/browser.js:484-490`
- Modify: `src/editor.js:2511-2518`
- Test: `src/browser.test.js:87-96`

**Interfaces:**
- Produces: `deleteDocument(id)` resolves only after both writes commit.
- Produces: `deleteDocument(id)` rejects on either failed write.

- [ ] **Step 1: Write failing partial-delete tests**

Add tests that force failure when:

- The content delete fails.
- The document index put fails.

For each case, expect rejection and no partial successful state.

- [ ] **Step 2: Run the browser tests**

Run: `npx vitest run src/browser.test.js`
Expected: FAIL because `Promise.allSettled` hides failures.

- [ ] **Step 3: Use one readwrite transaction**

Read the index, delete the content key, and put the filtered index in one transaction.
Resolve on `tx.oncomplete`.
Reject on request error, transaction error, or abort.

- [ ] **Step 4: Report deletion failure in the menu**

Wrap `deleteDocument` in `try/catch`.
Show `Delete failed: <message>`.
Show `Deleted` only after success.

- [ ] **Step 5: Run browser tests and typecheck**

Run: `npx vitest run src/browser.test.js && npm run typecheck`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add src/browser.js src/editor.js src/browser.test.js
git commit -m "fix: delete browser documents in one transaction"
```

---

### Task 7: Bound citation marker allocation

**Files:**
- Modify: `src/citations/output.js:278-310`
- Test: `src/citations/output.test.js:130-175`

**Interfaces:**
- Produces: `markerPair(source)` returns `[open, close]` or `null`.
- `applyCitations` uses direct citation Markdown when no pair exists.
- The fallback `fill(html)` returns `html` unchanged.

- [ ] **Step 1: Write failing marker-exhaustion tests**

Add tests that:

- A source containing every private-use character returns no marker pair.
- `applyCitations` terminates and uses citation Markdown.
- The fallback `fill` leaves renderer HTML unchanged.
- A normal source still receives private-use markers.

- [ ] **Step 2: Run the citation output tests**

Run: `npx vitest run src/citations/output.test.js`
Expected: FAIL or hang on the exhausted source.

- [ ] **Step 3: Allocate markers in one pass**

Collect used UTF-16 code units in a `Set`.
Scan candidate pairs from `U+E000` through `U+F8FF`.
Return the first pair whose units are unused.
Return `null` when the private-use range is exhausted.

- [ ] **Step 4: Add the no-marker fallback**

Replace citation ranges with `citations[i].markdown`.
Return an identity `fill` function.
Keep the existing marker path unchanged when a pair exists.

- [ ] **Step 5: Run citation tests and typecheck**

Run: `npx vitest run src/citations/output.test.js && npm run typecheck`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add src/citations/output.js src/citations/output.test.js
git commit -m "fix: bound citation marker allocation"
```

---

## Final verification

- [ ] Run `npm test`.
- [ ] Run `npm run typecheck`.
- [ ] Run `npm run build`.
- [ ] Manually test canceled Open in Chrome or Edge.
- [ ] Manually test edits during Save As and browser Save.
- [ ] Manually test two tabs with independent drafts.
