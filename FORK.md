# This fork

[driceroland/Search](https://github.com/driceroland/Search), with a few
changes on the `fork` branch. `main` follows the original untouched.

## What's different

- **Live folders of GitHub pull requests**: right-click the pinned rows,
  New Live Folder…, and give it github.com/pulls (your open pull requests),
  github.com/pulls/review-requested, /assigned, /mentioned, a repository's
  Pull requests page, or any of them with a `?q=` from GitHub's search box.
  The folder holds the pull requests open there, each marked Open,
  Approved or Changes (requested) with its comment count, and under them
  the ones merged in the last 24 hours, marked Merged; closed ones leave.
  Refreshed every five minutes, through GitHub's GraphQL search, signed in
  as the account `gh` has active (`gh auth status`); without gh it reads
  nothing and says so. Needs Settings › Spaces & Pins › Pinned rows and
  Folders in pinned rows. `Sources/Search/GitHubPulls.swift`.
- **Scrolling asks less** (PR #1435, closed for now upstream as idea 995:
  they want a page where it measurably changes CPU or frames): the page
  reports its scroll to the window only when the tab's meter would change
  (151 → 47 messages per 150 scrolled frames, measured), Swipe.watch no
  longer lays the page out on every vertical scroll, and the "show
  password" watch skips pages with nothing secret on them.
- **Updates come from this fork, not the feed**: a copy signed by anyone
  but Office Commun never downloads a release (it could never install one);
  it says once per version that the original has a newer one.

The unread badge on pins started here and is upstream since 1.0.19 (#1434),
so the fork no longer carries it.

If upstream takes one of these as it is, the rebase in update-fork.sh drops
the fork's copy on its own. If it is changed on the way in, the rebase stops
with a conflict on that commit: keep upstream's version (`git rebase --skip`),
then run the script again. A conflict in CHANGELOG.md alone: keep upstream's
(`git checkout --ours CHANGELOG.md`); the fork's changes are listed here,
not there.

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
