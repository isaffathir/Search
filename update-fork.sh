#!/bin/bash
# Brings this fork up to the original Search and installs it as the Search
# in /Applications. See FORK.md.
#
#   ./update-fork.sh           fetch upstream, rebase `fork` onto it, push,
#                              build signed, install, reopen
#   ./update-fork.sh build     the same, without installing
#   ./update-fork.sh install   install the last build as it is
#
# Signed with the Apple Development certificate in the login keychain
# (SEARCH_SIGN_IDENTITY names another): a signature that stays the same from
# build to build, so the keychain's "Always Allow" survives an update, which
# an ad-hoc one would not.
set -euo pipefail
cd "$(dirname "$0")"
# swiftly's shim, first on PATH here, points at a toolchain that isn't installed.
export PATH="/usr/bin:$PATH"

STEP="${1:-all}"
case "$STEP" in all|build|install) ;; *) echo "usage: $0 [build|install]" >&2; exit 1 ;; esac

# From the login keychain only: another keychain earlier in the search list
# holding the same certificate (an Expo build's "xdl-signing") had codesign
# ask for that keychain's password, which nobody knows.
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
IDENTITY="${SEARCH_SIGN_IDENTITY:-$(security find-identity -v -p codesigning "$KEYCHAIN" 2>/dev/null \
  | awk '/Apple Development/ { print $2; exit }' || true)}"
[ -n "$IDENTITY" ] || { echo "no Apple Development certificate in the login keychain" >&2; exit 1; }

# build.sh signs ad hoc (it looks for a Developer ID); signed again here.
sign() {
  codesign --force --deep --timestamp --options runtime \
    --entitlements Search.entitlements --keychain "$KEYCHAIN" --sign "$IDENTITY" build/Search.app
}

if [ "$STEP" != install ]; then
  [ -z "$(git status --porcelain)" ] || { echo "uncommitted changes here: commit or stash them first" >&2; exit 1; }
  git fetch -q upstream
  git checkout -q main
  git merge -q --ff-only upstream/main
  git checkout -q fork
  if ! git rebase -q main; then
    git rebase --abort
    echo "a fork change no longer applies on the new upstream: rebase by hand (git rebase main)" >&2
    exit 1
  fi
  if ! { git push -q origin main && git push -q --force-with-lease origin fork; }; then
    echo "push to GitHub skipped (offline?); the build goes on" >&2
  fi
  SEARCH_SIGN_IDENTITY= ./build.sh release
  sign
fi
[ "$STEP" = build ] && exit 0

APP="build/Search.app"
TARGET="/Applications/Search.app"
# A build made by ./build.sh alone is ad hoc: signed here before it goes in,
# or the keychain would ask again after every one.
codesign -dv "$APP" 2>&1 | grep -q '^TeamIdentifier=[A-Z0-9]' || sign
codesign --verify --strict "$APP"

# Quit the way ⌘Q does, so the session is saved and comes back.
if pgrep -f "^$TARGET/Contents/MacOS/Search" >/dev/null; then
  osascript -e 'tell application id "com.officecommun.search" to quit' >/dev/null 2>&1 || true
  for _ in $(seq 60); do pgrep -f "^$TARGET/Contents/MacOS/Search" >/dev/null || break; sleep 0.5; done
  if pgrep -f "^$TARGET/Contents/MacOS/Search" >/dev/null; then
    echo "Search is still open (a question on screen?): quit it, then run: $0 install" >&2
    exit 1
  fi
fi

# The one before, kept beside the official 1.0.18 the fork replaced.
BACKUPS="$HOME/Library/Application Support/Search-fork-backups"
mkdir -p "$BACKUPS"
if [ -d "$TARGET" ]; then
  rm -rf "$BACKUPS/Search-previous.app"
  mv "$TARGET" "$BACKUPS/Search-previous.app"
fi
ditto "$APP" "$TARGET"
open -b com.officecommun.search
echo "installed: $(defaults read "$TARGET/Contents/Info.plist" CFBundleShortVersionString) build $(defaults read "$TARGET/Contents/Info.plist" CFBundleVersion), $(git rev-parse --short HEAD)"
