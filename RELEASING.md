# Releasing flyt

flyt updates itself with [Sparkle](https://sparkle-project.org). A release is a
zip attached to a GitHub Release, plus an entry in `docs/appcast.xml`, which
GitHub Pages serves at `https://ctenhove.github.io/flyt/appcast.xml` (the
`SUFeedURL` in the app).

## One-time setup

### 1. Generate the signing key

Sparkle verifies every update against an EdDSA key. Xcode downloads Sparkle's
command-line tools with the package; build the app once, then:

```bash
~/Library/Developer/Xcode/DerivedData/flyt-*/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys
```

The private key is stored in your login keychain; the command prints the
public key. Paste the public key into `Resources/Info.plist` as the value of
`SUPublicEDKey` (the empty `<string></string>` under that key) and commit it —
it's public, so it's safe in the repository.

**Back up the private key.** Export it and keep it somewhere safe (a password
manager):

```bash
.../Sparkle/bin/generate_keys -x flyt-sparkle-private-key
```

If it's lost, installed copies of flyt can never verify another update, and
everyone has to download the app by hand again.

Until `SUPublicEDKey` is set, the app doesn't start the updater and the
"Check for Updates…" menu item stays disabled.

### 2. Turn on GitHub Pages

Repository → Settings → Pages → Source: *Deploy from a branch*, branch
`main`, folder `/docs`. The appcast is then live at
`https://ctenhove.github.io/flyt/appcast.xml`.

## Each release

```bash
scripts/release.sh 0.6.0
```

This archives the app, zips it, signs the zip with your key and adds an item
to `docs/appcast.xml`. It then prints the two commands to publish:

```bash
gh release create v0.6.0 build/release/flyt-0.6.0.zip --title "flyt 0.6.0" --generate-notes
git add docs/appcast.xml && git commit -m "Appcast: 0.6.0" && git push
```

Publish the GitHub Release **before** pushing the appcast, so the download
exists by the time anyone is offered it.

The build number (`CURRENT_PROJECT_VERSION`) must go up with every release —
Sparkle compares it, not the marketing version, to decide what's newer. The
script defaults it to the number of commits on the branch; pass your own as
the second argument if you need to.

## Notes

- flyt isn't notarized. Sparkle installs updates without the Gatekeeper
  quarantine flag, so users only go through the first-launch "Open anyway"
  step once. Notarizing later would remove that step for new installs too.
- yt-dlp and ffmpeg live in `~/Library/Application Support/flyt`, outside the
  app bundle, so updating the app leaves them (and saved preferences and
  download history) alone.
- To test an update locally, install an older build, then publish a newer one
  to a throwaway appcast and point `SUFeedURL` at it.
