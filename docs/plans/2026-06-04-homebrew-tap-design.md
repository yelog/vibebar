# Homebrew Tap Integration Design

## Context

`rust-redis-desktop` keeps Homebrew distribution in `yelog/homebrew-tap`. Its tag-driven release workflow builds release artifacts, creates the GitHub Release, and then updates `Casks/rust-redis-desktop.rb` in the tap only for stable tags when `HOMEBREW_TAP_TOKEN` is configured.

VibeBar currently has two Homebrew update paths:

- `release-app.yml` updates `Casks/vibebar.rb` in the main repository while committing appcast changes.
- `update-cask.yml` runs after a published release, downloads the DMG, computes SHA256, and updates the same cask again.

This creates duplicate ownership, possible race conditions, and less standard install commands.

## Decision

Use the same independent tap model as `rust-redis-desktop`.

Homebrew Cask distribution for VibeBar will live in `yelog/homebrew-tap`. The VibeBar repository will no longer maintain a repo-local `Casks/vibebar.rb` as the authoritative cask. Stable VibeBar releases will update the tap from `release-app.yml` after the GitHub Release has been created.

## Release Flow

- Continue building and signing `dist/VibeBar-<version>-universal.dmg` in `release-app.yml`.
- Continue updating Sparkle appcasts in the main repository.
- Continue publishing the GitHub Release with the DMG and `.sha256` sidecar.
- For stable releases only, clone `yelog/homebrew-tap` with `HOMEBREW_TAP_TOKEN`.
- Update `homebrew-tap/Casks/vibebar.rb` with the release version and SHA256 from the built DMG sidecar.
- Commit and push only when the tap cask changes.
- If `HOMEBREW_TAP_TOKEN` is not configured, skip tap updates without failing the release.

## Repository Cleanup

- Remove the release-time update of repo-local `Casks/vibebar.rb`.
- Delete the separate `update-cask.yml` workflow to avoid duplicate updates.
- Delete repo-local `Casks/vibebar.rb` after the tap repository has the cask.
- Update README install commands to use `brew tap yelog/tap` and `brew install --cask vibebar`.

## Requirements

- `yelog/homebrew-tap` must contain `Casks/vibebar.rb`.
- `HOMEBREW_TAP_TOKEN` must be configured with push access to `yelog/homebrew-tap` for automatic stable release updates.
- The tap cask URL should point to `https://github.com/yelog/VibeBar/releases/download/v#{version}/VibeBar-#{version}-universal.dmg`.

## Risks

- If the token is missing, release succeeds but Homebrew remains unchanged. The workflow logs this explicitly.
- If the tap cask path does not exist, the update step fails for stable releases. This is intentional because the release would otherwise silently skip a configured distribution channel.
- Pre-release tags do not update Homebrew; users on beta builds continue receiving updates through Sparkle beta appcast and GitHub prereleases.
