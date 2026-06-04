# Homebrew Tap Integration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Move VibeBar Homebrew distribution updates from repo-local cask commits to the shared `yelog/homebrew-tap` repository.

**Architecture:** Keep `release-app.yml` as the single release orchestrator. Stable releases update `yelog/homebrew-tap` after the GitHub Release is created, while appcast updates remain in the main repository. Remove the separate post-release cask workflow and repo-local cask ownership.

**Tech Stack:** GitHub Actions, Homebrew Cask Ruby file updates, shell, Python, GitHub Release assets.

---

### Task 1: Document The Design

**Files:**
- Create: `docs/plans/2026-06-04-homebrew-tap-design.md`
- Create: `docs/plans/2026-06-04-homebrew-tap.md`

**Step 1: Write the design document**

Create `docs/plans/2026-06-04-homebrew-tap-design.md` with the approved design: independent tap repository, stable-only updates, `HOMEBREW_TAP_TOKEN`, removal of duplicate update paths, and README command updates.

**Step 2: Write this implementation plan**

Create `docs/plans/2026-06-04-homebrew-tap.md` with exact implementation steps.

**Step 3: Verify docs are present**

Run: `test -f docs/plans/2026-06-04-homebrew-tap-design.md && test -f docs/plans/2026-06-04-homebrew-tap.md`

Expected: command exits successfully.

### Task 2: Update Release Workflow

**Files:**
- Modify: `.github/workflows/release-app.yml`

**Step 1: Remove repo-local cask update from appcast commit step**

In `Commit and push appcast changes`, remove the block that edits `Casks/vibebar.rb` and remove `Casks/vibebar.rb` from `git add`.

Expected `git add` line:

```bash
git add docs/appcast-beta.xml docs/appcast.xml
```

**Step 2: Add shared tap update step after GitHub Release creation**

Add a stable-only step after `Create GitHub Release`:

```yaml
      - name: Update Homebrew tap
        if: ${{ steps.release_type.outputs.is_prerelease == 'false' }}
        env:
          HOMEBREW_TAP_TOKEN: ${{ secrets.HOMEBREW_TAP_TOKEN }}
        run: |
          if [ -z "$HOMEBREW_TAP_TOKEN" ]; then
            echo "Skipping Homebrew tap update (HOMEBREW_TAP_TOKEN not set)"
            exit 0
          fi

          VERSION="${{ steps.update_appcast.outputs.version }}"
          SHA256=$(awk '{print $1}' "dist/VibeBar-${VERSION}-universal.dmg.sha256")

          git clone "https://x-access-token:${HOMEBREW_TAP_TOKEN}@github.com/yelog/homebrew-tap.git" homebrew-tap

          python3 - "$VERSION" "$SHA256" <<'PY'
          import pathlib
          import re
          import sys

          version, sha256 = sys.argv[1:3]
          cask_path = pathlib.Path("homebrew-tap/Casks/vibebar.rb")
          content = cask_path.read_text(encoding="utf-8")
          content = re.sub(r'version "[^"]+"', f'version "{version}"', content, count=1)
          content = re.sub(r'sha256 "[0-9a-f]+"', f'sha256 "{sha256}"', content, count=1)
          cask_path.write_text(content, encoding="utf-8")
          PY

          if git -C homebrew-tap diff --quiet; then
            echo "Homebrew tap already up to date"
            exit 0
          fi

          git -C homebrew-tap config user.name "github-actions[bot]"
          git -C homebrew-tap config user.email "github-actions[bot]@users.noreply.github.com"
          git -C homebrew-tap add Casks/vibebar.rb
          git -C homebrew-tap commit -m "Update vibebar to ${VERSION}"
          git -C homebrew-tap push origin HEAD
```

**Step 3: Remove obsolete comment**

Remove the final comment that says Homebrew cask update is integrated into the appcast commit step.

**Step 4: Validate YAML shape**

Run: `ruby -e 'require "yaml"; YAML.load_file(".github/workflows/release-app.yml"); puts "ok"'`

Expected: prints `ok`.

### Task 3: Remove Duplicate Cask Workflow And Repo-Local Cask

**Files:**
- Delete: `.github/workflows/update-cask.yml`
- Delete: `Casks/vibebar.rb`

**Step 1: Delete duplicate workflow**

Delete `.github/workflows/update-cask.yml` because stable release tap updates now happen in `release-app.yml`.

**Step 2: Delete repo-local cask**

Delete `Casks/vibebar.rb` after confirming the independent tap is the authoritative cask location.

**Step 3: Verify no workflow references repo-local cask**

Run: `rg 'Casks/vibebar.rb|update-cask' .github README*.md AGENTS.md docs/plans`

Expected: no live workflow references to repo-local cask remain; plan docs may mention the removed files historically.

### Task 4: Update Documentation

**Files:**
- Modify: `README.md`
- Modify: `README_zh.md`
- Modify: `README_ja.md`
- Modify: `README_ko.md`
- Modify: `AGENTS.md`

**Step 1: Update English README commands**

Replace:

```bash
brew tap yelog/vibebar https://github.com/yelog/vibebar.git
brew install --cask yelog/vibebar/vibebar
```

With:

```bash
brew tap yelog/tap
brew install --cask vibebar
```

Replace upgrade command with:

```bash
brew upgrade --cask vibebar
```

**Step 2: Update localized README commands**

Apply the same command changes to `README_zh.md`, `README_ja.md`, and `README_ko.md`.

**Step 3: Add release guidance**

Add a release note to `AGENTS.md` explaining that Homebrew Cask distribution lives in `yelog/homebrew-tap` and stable release tags update it when `HOMEBREW_TAP_TOKEN` is configured.

**Step 4: Verify docs references**

Run: `rg 'yelog/vibebar|yelog/tap|brew install --cask|brew upgrade --cask' README*.md AGENTS.md`

Expected: Homebrew install commands use `yelog/tap` and `vibebar`.

### Task 5: Final Verification

**Files:**
- Inspect all changed files.

**Step 1: Check git diff**

Run: `git diff -- .github/workflows/release-app.yml README.md README_zh.md README_ja.md README_ko.md AGENTS.md docs/plans/2026-06-04-homebrew-tap-design.md docs/plans/2026-06-04-homebrew-tap.md`

Expected: changes match the approved design.

**Step 2: Check working tree**

Run: `git status --short`

Expected: only intended files changed or deleted.

**Step 3: Do not run Swift tests**

No Swift source changes are made. Workflow syntax and docs verification are sufficient.
