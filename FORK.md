# This fork

[driceroland/Search](https://github.com/driceroland/Search), with a few
changes on the `fork` branch. `main` follows the original untouched.

## What's different

- **Unread badge on pins** (proposed upstream: issue #1433, PR #1434):
  Settings › Appearance › Tabs › Show counts on pins puts the count a page
  writes at the front of its title (`(3) WhatsApp`) as a red badge on the
  corner of its pin's icon, in the column and in the tab bar. Off by
  default, as upstream wants new features; switch it on in Settings.
  `Sources/Search/UnreadBadge.swift`.
- **Scrolling asks less** (proposed upstream: PR #1435): the page reports its
  scroll to the window only when the tab's meter would change (151 → 47
  messages per 150 scrolled frames, measured), Swipe.watch no longer lays
  the page out on every vertical scroll, and the "show password" watch
  skips pages with nothing secret on them.

If upstream merges one of these as it is, the rebase in update-fork.sh drops
the fork's copy on its own. If it is changed on the way in, the rebase stops
with a conflict on that commit: keep upstream's version (`git rebase --skip`),
then run the script again.
- **Updates come from this fork, not the feed**: a copy signed by anyone
  but Office Commun never downloads a release (it could never install one);
  it says once per version that the original has a newer one.

## What this build doesn't have

Signed with a personal Apple Development certificate, not Office Commun's
Developer ID, so: no Sync with iCloud, no passkeys (security keys still
work), no automatic updates. Same bundle id, so settings, history, pins,
sessions and site logins carry over from the official app. Passwords saved
by the official app ask the keychain once each; ones imported into this
build are its own.

## Updating

```sh
~/Search-fork/update-fork.sh
```

Fetches the original, rebases `fork` onto it, pushes both branches here,
builds (about 5 minutes), quits Search the way ⌘Q does, installs, reopens.
The build it replaced is kept in
`~/Library/Application Support/Search-fork-backups/Search-previous.app`,
next to `Search-official-1.0.18.app`, the official app this fork replaced.

If a change no longer applies on the new original, the script stops before
building: `git rebase main` by hand, then run it again.

## Going back to the official app

Quit Search, put `Search-official-1.0.18.app` back as `/Applications/Search.app`
(or download it from officecommun.com/search), open it.
