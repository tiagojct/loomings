# Release Integrity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent unstable releases, incomplete license artifacts, excessive CI privileges, blind Docker deploys, and stale native resources.

**Architecture:** A tested release-tag gate runs before publication. A lockfile-driven notice generator supplies web and native artifacts. CI uses least privilege and pinned actions. Builds precede artifact tests. A Docker smoke job probes the real app. Native resource export mirrors source directories.

**Tech Stack:** Node.js ESM, Vitest, GitHub Actions, Docker, nginx, SwiftPM.

**Spec:** `docs/superpowers/specs/2026-11-24-stabilization-design.md`

## Global Constraints

- Preserve public APIs unless a task explicitly replaces them.
- Add a regression test before each behavioral fix.
- Run `npm test` and `npm run typecheck` after each task.
- Keep native-only work separate from web release numbering.
- Do not commit `macos/plans/`.
- Use full commit SHAs for GitHub Actions.
- Keep `package.json` as the only version source.

## Review Focus

- A prerelease tag must fail before Docker or native publication. Task 1 pins this.
- A stable tag that differs from `package.json` must fail. Task 1 pins this.
- A production dependency without license text must fail notice generation. Task 2 pins this.
- A clean CI run must execute tests that inspect built artifacts. Task 5 pins this.
- A deleted native lesson, style, or locale must disappear after export. Task 6 pins this.

---

### Task 1: Validate stable release tags before publication

**Files:**
- Create: `scripts/release-tag.mjs`
- Create: `src/release-tag.test.js`
- Modify: `.github/workflows/docker-publish.yml:17-27`
- Modify: `.github/workflows/macos.yml:18-34`

**Interfaces:**
- Produces: `stableReleaseVersion(refName: string): string | null`.
- Produces: `assertStableRelease(refName: string, packageVersion: string): void`.
- The CLI reads `process.argv[2]` and `package.json`, then exits nonzero on failure.

- [ ] **Step 1: Write failing release-tag tests**

Cover:

- `v2.6.5` returns `2.6.5`.
- `v2.7.0-rc.1`, `v2.7.0-beta.1`, and `v2.7` return `null`.
- `assertStableRelease('v2.6.5', '2.6.5')` succeeds.
- `assertStableRelease('v2.7.0', '2.6.5')` throws.
- `assertStableRelease('v2.7.0-rc.1', '2.7.0')` throws.

- [ ] **Step 2: Run the release-tag tests**

Run: `npx vitest run src/release-tag.test.js`
Expected: FAIL because the module does not exist.

- [ ] **Step 3: Implement the release-tag gate**

Accept only `^v(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$`.
Compare the captured version with `package.json`.
Print a clear error and set `process.exitCode = 1` on CLI failure.

- [ ] **Step 4: Add the gate to both publication workflows**

After checkout in `build-check` and native `test-and-build`, add:

```yaml
- name: Validate release tag
  if: startsWith(github.ref, 'refs/tags/v')
  run: node scripts/release-tag.mjs "$GITHUB_REF_NAME"
```

- [ ] **Step 5: Run tests and typecheck**

Run: `npx vitest run src/release-tag.test.js && npm run typecheck`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add scripts/release-tag.mjs src/release-tag.test.js .github/workflows/docker-publish.yml .github/workflows/macos.yml
git commit -m "fix: reject unstable or mismatched release tags"
```

---

### Task 2: Generate complete third-party notices

**Files:**
- Create: `public/licenses/CPAL-1.0.txt`
- Create: `public/licenses/tryworks-design-LICENSE.txt`
- Create: `public/licenses/OFL-literata.txt`
- Create: `public/licenses/OFL-atkinson-hyperlegible-next.txt`
- Create: `public/licenses/OFL-atkinson-hyperlegible-mono.txt`
- Create: `scripts/build-notices.mjs`
- Create: `src/notices.test.js`
- Modify: `.gitignore`

**Interfaces:**
- Produces: `collectNotices(root: string): Notice[]`.
- Produces: `renderNotices(notices: Notice[]): string`.
- Produces: `writeNotices(target: 'web' | 'native', root?: string): string`.
- `Notice` contains `name`, `version`, `license`, and `text`.

- [ ] **Step 1: Add the full license source files**

Add the OSI CPAL 1.0 text from `https://opensource.org/licenses/CPAL-1.0`.
Add the MIT text for `@tiagojct/tryworks-design`.
Add the Google Fonts OFL texts for Literata, Atkinson Hyperlegible Next, and Atkinson Hyperlegible Mono.

- [ ] **Step 2: Write failing notice-generator tests**

Use a temporary fixture with:

- One production package with a license file.
- One production package without a license file.
- One dev-only package without a license file.

Assert:

- The production package appears in rendered output.
- The dev-only package does not appear.
- Missing production license text throws.
- Project, vendored design, font, and CPAL notices appear for the real repository.

- [ ] **Step 3: Run the notice tests**

Run: `npx vitest run src/notices.test.js`
Expected: FAIL because the generator does not exist.

- [ ] **Step 4: Implement lockfile-driven collection**

Read `package-lock.json`.
Select packages where `dev` is not true.
Read each package license field and license file from `node_modules`.
Use `public/licenses/CPAL-1.0.txt` as the full citeproc license text.
Append project, vendored design, font, and CPAL texts.
Fail when a production package has no readable license text.

- [ ] **Step 5: Implement deterministic output**

Sort packages by name.
Use stable headings and UTF-8 text.
Write web output to `public/licenses/THIRD-PARTY-NOTICES.txt`.
Write native output to `macos/Resources/THIRD-PARTY-NOTICES.txt`.
Ignore both generated files in Git.

- [ ] **Step 6: Run notice tests and typecheck**

Run: `npx vitest run src/notices.test.js && npm run typecheck`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add public/licenses scripts/build-notices.mjs src/notices.test.js .gitignore
git commit -m "fix: generate complete third-party license notices"
```

---

### Task 3: Ship notices in web and native artifacts

**Files:**
- Modify: `package.json:6-14`
- Modify: `scripts/citeproc-notice.js:5-6`
- Modify: `vite.config.js:40-45,65-70`
- Modify: `scripts/export-native-resources.mjs:36-57`
- Modify: `vite.citations.config.js:34`
- Modify: `macos/scripts/build-app.sh:31-43`
- Modify: `.dockerignore:11-12`
- Modify: `Dockerfile:1-13`
- Modify: `src/index.html:222`
- Modify: `src/citations/licence.test.js:7-34`
- Modify: `README.md:159-164`

**Interfaces:**
- Consumes: `writeNotices(target, root?)` from Task 2.
- Produces: `npm run build` generates web notices before Vite copies public files.
- Produces: `npm run export:native` generates native notices before app packaging.

- [ ] **Step 1: Write failing artifact-license tests**

Extend `src/citations/licence.test.js` to require:

- `CPAL-1.0.txt` and `THIRD-PARTY-NOTICES.txt` links in About.
- A built `dist/licenses/THIRD-PARTY-NOTICES.txt`.
- `citeproc`, CodeMirror, markdown-it, project MIT, and CPAL text in that file.
- Every built JavaScript chunk and license text file is listed in `dist/sw.js`.

- [ ] **Step 2: Run the license tests**

Run: `npx vitest run src/citations/licence.test.js`
Expected: FAIL because the files and links do not exist.

- [ ] **Step 3: Wire notice generation into builds**

Set:

```json
"predev": "node scripts/build-notices.mjs web",
"dev": "vite",
"prepreview": "node scripts/build-notices.mjs web",
"preview": "vite preview",
"build": "node scripts/build-notices.mjs web && vite build",
"export:native": "vite build --config vite.citations.config.js && node scripts/export-native-resources.mjs && node scripts/build-notices.mjs native"
```

Allow `LICENSE` into the Docker build context and copy it into the build stage.
Generate native notices inside `build-app.sh` before copying resources.
Copy `THIRD-PARTY-NOTICES.txt` and `CPAL-1.0.txt` into native citation resources.
Copy `THIRD-PARTY-NOTICES.txt` into the native app bundle.

- [ ] **Step 4: Update notices and About links**

Make the citeproc banner name CPAL and point to `CPAL-1.0.txt`.
Use `citeprocNotice('CPAL-1.0.txt')` in the native citation build.
Add About links for CPAL and third-party notices.
Add `.txt` to the service-worker precache filter.
Update the README license section.

- [ ] **Step 5: Build and run license tests**

Run: `npm run build && npx vitest run src/citations/licence.test.js`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add package.json scripts/citeproc-notice.js vite.config.js scripts/export-native-resources.mjs macos/scripts/build-app.sh src/index.html src/citations/licence.test.js README.md
git commit -m "fix: include license notices in release artifacts"
```

---

### Task 4: Apply least privilege and pin CI actions

**Files:**
- Modify: `.github/workflows/ci.yml`
- Modify: `.github/workflows/docker-publish.yml`
- Modify: `.github/workflows/macos.yml`

**Interfaces:**
- Produces: read-only default permissions for all workflows.
- Produces: a separate native `publish` job with `contents: write`.
- Produces: full-SHA action references.

- [ ] **Step 1: Write failing workflow-policy tests**

Create `src/ci-policy.test.js` and assert:

- Every workflow sets `permissions: contents: read` at workflow level.
- Every `uses:` reference contains a 40-character SHA.
- The native test job has no `contents: write`.
- The native publish job has `contents: write` and `environment: release`.

- [ ] **Step 2: Run the workflow-policy tests**

Run: `npx vitest run src/ci-policy.test.js`
Expected: FAIL because permissions and pins are missing.

- [ ] **Step 3: Pin all actions**

Use these exact SHAs:

| Action | SHA |
|---|---|
| `actions/checkout` | `11d5960a326750d5838078e36cf38b85af677262` |
| `actions/setup-node` | `49933ea5288caeca8642d1e84afbd3f7d6820020` |
| `actions/upload-artifact` | `ea165f8d65b6e75b540449e92b4886f43607fa02` |
| `actions/download-artifact` | `d3f86a106a0bac45b974a628896c90dbdf5c8093` |
| `docker/setup-qemu-action` | `c7c53464625b32c7a7e944ae62b3e17d2b600130` |
| `docker/setup-buildx-action` | `8d2750c68a42422c14e847fe6c8ac0403b4cbd6f` |
| `docker/login-action` | `c94ce9fb468520275223c153574b00df6fe4bcc9` |
| `docker/metadata-action` | `c299e40c65443455700f0fdfc63efafe5b349051` |
| `docker/build-push-action` | `10e90e3645eae34f1e60eeb005ba3a3d33f178e8` |

Keep version comments beside each SHA.

- [ ] **Step 4: Split native publication from testing**

Make `test-and-build` read-only.
Upload `Loomings-mac-arm64.zip` as artifact `Loomings-mac-arm64` on stable tags.
Set `if-no-files-found: error`.
Add a `publish` job that needs `test-and-build`, uses `environment: release`, and has `contents: write`.
Download artifact `Loomings-mac-arm64` into the repository root.
Attach it to the release.

- [ ] **Step 5: Run policy tests and typecheck**

Run: `npx vitest run src/ci-policy.test.js && npm run typecheck`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add .github/workflows/ci.yml .github/workflows/docker-publish.yml .github/workflows/macos.yml src/ci-policy.test.js
git commit -m "fix: reduce CI privileges and pin actions"
```

---

### Task 5: Test built artifacts and smoke-test Docker

**Files:**
- Create: `src/deployment.test.js`
- Modify: `.github/workflows/ci.yml:19-22`
- Modify: `.github/workflows/docker-publish.yml:24-27`
- Modify: `Dockerfile:25-26`
- Modify: `docker-compose.yml:11-15`

**Interfaces:**
- Produces: a `docker-smoke` CI job.
- Produces: `/app/` as the container health target.
- Produces: build-before-test ordering in both Node CI jobs.

- [ ] **Step 1: Write failing deployment-policy tests**

Assert:

- `npm run build` appears before `npm test` in both Node jobs.
- Dockerfile and Compose healthchecks request `/app/`.
- The smoke job probes `/`, `/app/`, `/app/sw.js`, and `/app/manifest.webmanifest`.
- The smoke job checks CSP, `nosniff`, and Referrer-Policy headers.

- [ ] **Step 2: Run deployment-policy tests**

Run: `npx vitest run src/deployment.test.js`
Expected: FAIL because the order, health target, and smoke job are missing.

- [ ] **Step 3: Reorder CI steps**

Use `npm ci`, `npm run typecheck`, `npm run build`, then `npm test`.
Apply the same order to Docker publish `build-check`.

- [ ] **Step 4: Add the Docker smoke job**

Build the image without pushing.
Run it on loopback port `8081`.
Probe the four required paths.
Fetch `/app/` headers and assert the three security headers.
Remove the container in an `always()` cleanup step.

- [ ] **Step 5: Change healthchecks to `/app/`**

Update Dockerfile and Compose.
Keep the existing interval, timeout, start period, and retries.

- [ ] **Step 6: Run deployment tests and typecheck**

Run: `npx vitest run src/deployment.test.js && npm run typecheck`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add src/deployment.test.js .github/workflows/ci.yml .github/workflows/docker-publish.yml Dockerfile docker-compose.yml
git commit -m "fix: test built artifacts and smoke-test Docker"
```

---

### Task 6: Mirror native resources and expand CI triggers

**Files:**
- Modify: `scripts/export-native-resources.mjs:6,32-40`
- Create: `src/native-resources.test.js`
- Modify: `.github/workflows/macos.yml:9-11,27-30`

**Interfaces:**
- Produces: `mirrorDirectory(source: string, destination: string): void`.
- The exporter uses it for lessons, styles, and locales.

- [ ] **Step 1: Write failing mirror tests**

Create temporary source and destination directories.
Assert:

- A stale destination file is removed.
- A current source file is copied.
- A removed source file stays absent.
- A failed source read does not leave a partial destination.

- [ ] **Step 2: Run the mirror tests**

Run: `npx vitest run src/native-resources.test.js`
Expected: FAIL because `mirrorDirectory` does not exist.

- [ ] **Step 3: Implement mirrored export**

Export `mirrorDirectory`.
Copy the source into a temporary sibling directory.
Replace the destination only after the copy succeeds.
Remove the temporary directory on failure and keep the previous destination.
Use it for lessons, styles, and locales.
Keep atomic single-file writes for palettes, example, manifests, and notices.

- [ ] **Step 4: Expand native workflow inputs and checks**

Add these paths to push and pull-request filters:

- `src/palettes.js`
- `src/teaching/**`
- `src/qr.js`
- `lessons/**`
- `examples/**`
- `public/licenses/**`
- `scripts/build-notices.mjs`
- `LICENSE`
- `vendor/tryworks-design/**`

Change the generated diff check to `macos/Resources`.

- [ ] **Step 5: Run mirror tests, full tests, and typecheck**

Run: `npx vitest run src/native-resources.test.js && npm test && npm run typecheck`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add scripts/export-native-resources.mjs src/native-resources.test.js .github/workflows/macos.yml
git commit -m "fix: mirror native resources and expand CI triggers"
```

---

## Final verification

- [ ] Run `npm test`.
- [ ] Run `npm run typecheck`.
- [ ] Run `npm run build`.
- [ ] Run `node scripts/release-tag.mjs v2.6.5`.
- [ ] Confirm `node scripts/release-tag.mjs v2.6.5-rc.1` exits nonzero.
- [ ] Run `npm run export:native`.
- [ ] Run `git diff --exit-code -- macos/Resources`.
- [ ] Run `docker build -t loomings-release-test .`.
- [ ] Start the image and probe `/`, `/app/`, `/app/sw.js`, and security headers.
- [ ] Run `swift test --package-path macos`.
- [ ] Run `./macos/scripts/build-app.sh`.
- [ ] Run the native `--self-test`.
