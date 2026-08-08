# Distribution

The public product route is
[`https://nikhi1g.github.io/whisper_hotkey/`](https://nikhi1g.github.io/whisper_hotkey/).
GitHub Pages deploys the static files in `site/` through `pages.yml`. The page
queries the latest GitHub release and sends its primary button to the
`whisper_hotkey.dmg` asset, falling back to `whisper_hotkey.zip` for older
releases and then to the releases page.

The ZIP was dropped from new releases in 3.6.0. It existed because an
unnotarized disk image was believed not to mount; a quarantined DMG was
tested and mounts normally, and the app copied out of it carries only
`com.apple.provenance` rather than the `com.apple.quarantine` flag the ZIP
path propagated. Shipping one asset also halves the upload.

## Signing status

This project has no paid Apple Developer Program membership, so releases cannot
be notarized. Every release is signed with a stable **Apple Development**
identity instead. That choice is deliberate:

- A stable identity keeps the app's designated requirement constant, which is
  what `SoftwareUpdateInstaller` checks before it will install an update, and
  what keeps Microphone, Accessibility, and Input Monitoring grants attached
  across versions. Ad-hoc signing would break both.
- Without an Apple ticket, Gatekeeper blocks the first launch. Users clear it
  once through **System Settings → Privacy & Security → Open Anyway**. The
  README and the product page both document that step.
- `spctl --assess` reports `rejected` for these artifacts. That is the expected
  state, not a regression.

The ZIP is the human download because macOS 15 and later block an unnotarized
disk image *before it mounts*, which leaves the user with a "Move to Trash"
dialog and no obvious recovery. The DMG is still published under its exact
historical name because the in-app updater fetches
`whisper_hotkey.dmg` and `whisper_hotkey.dmg.sha256` and mounts them directly,
where no quarantine flag is involved.

Apple Development certificates expire after about a year. A reissued certificate
changes the designated requirement, so in-app updates from older versions will
stop working and those users need a manual download.

## One-time repository setup

In **Settings → Pages**, select **GitHub Actions** as the Pages source. In
**Settings → Secrets and variables → Actions**, add:

| Secret | Value |
| --- | --- |
| `APPLE_SIGNING_CERTIFICATE_P12_BASE64` | Base64-encoded signing certificate and private key exported as PKCS #12 |
| `APPLE_SIGNING_CERTIFICATE_P12_PASSWORD` | Password used for that PKCS #12 export |

Export the same identity that signed the previous release, otherwise existing
installs lose in-app updates:

```sh
/usr/bin/security export -k login.keychain-db -t identities -f pkcs12 \
  -P '<choose-a-password>' -o ~/Desktop/whisper_hotkey-signing.p12
gh secret set APPLE_SIGNING_CERTIFICATE_P12_BASE64 \
  --body "$(base64 -i ~/Desktop/whisper_hotkey-signing.p12)"
gh secret set APPLE_SIGNING_CERTIFICATE_P12_PASSWORD --body '<same-password>'
rm ~/Desktop/whisper_hotkey-signing.p12
```

The personal-site repository only needs a normal link to
`/whisper_hotkey/`. GitHub serves this project repository's Pages site at that
route automatically; do not create a competing directory with the same name in
`nikhi1g.github.io`.

## Publish a release

1. Update `VERSION`, the embedded login-launcher version, release notes, and the
   matching file under `docs/releases/`.
2. Run `swift test` and `python3 build_app.py` locally with a stable development
   identity.
3. Commit the release, then create and push the matching tag, such as `v3.2.3`.
4. The `release.yml` workflow builds pinned whisper.cpp 1.9.1 for the declared
   macOS 14 deployment target, downloads Base English, verifies its pinned
   SHA-256, tests the project, and imports the temporary signing identity.
5. The workflow builds with secure timestamps, packages the ZIP and the DMG, and
   uploads both with their checksums and the source archive to the matching
   GitHub release.

### Publishing without CI

This is the current route. The workflow secrets are not set, so `release.yml`
exits in ~15 seconds at "Validate release ref and secrets" on every tag push,
before it touches the release. That failure is expected and harmless; the
assets below are what actually ship.

First build the pinned whisper.cpp for the declared deployment target.
`build_app.py` refuses Homebrew's `whisper-cpp` because it targets the host
macOS, and `verify_distribution_targets` rejects anything above macOS 14 — that
guardrail is what keeps the release runnable on macOS 14 and later:

```sh
git clone --depth 1 --branch v1.9.1 \
  https://github.com/ggml-org/whisper.cpp.git /tmp/whisper.cpp
test "$(git -C /tmp/whisper.cpp rev-parse HEAD)" \
  = "f049fff95a089aa9969deb009cdd4892b3e74916"
cmake -S /tmp/whisper.cpp -B /tmp/whisper.cpp-build \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
  -DCMAKE_INSTALL_PREFIX=/tmp/whisper.cpp-install \
  -DWHISPER_BUILD_EXAMPLES=OFF -DWHISPER_BUILD_TESTS=OFF \
  -DGGML_METAL=ON -DGGML_OPENMP=OFF -DBUILD_SHARED_LIBS=ON
cmake --build /tmp/whisper.cpp-build --parallel
cmake --install /tmp/whisper.cpp-build
export WHISPER_CPP_PREFIX=/tmp/whisper.cpp-install
export GGML_PREFIX=/tmp/whisper.cpp-install
export HOMEBREW_PREFIX="$(brew --prefix)"
```

Then produce and upload the assets on the release commit:

```sh
WHISPER_HOTKEY_BUNDLE_MODEL=1 WHISPER_HOTKEY_DISTRIBUTION=1 \
  WHISPER_HOTKEY_UNNOTARIZED=1 python3 build_app.py
python3 tools/package_zip.py
python3 tools/package_dmg.py --unnotarized
python3 tools/package_release.py "v$(cat VERSION)"
gh release create "v$(cat VERSION)" --title "whisper_hotkey $(cat VERSION)" \
  --notes-file RELEASE_NOTES.md --verify-tag
gh release upload "v$(cat VERSION)" --clobber dist/release/*
```

`package_release.py` refuses a dirty tree and a tag that does not match
`VERSION`, so commit and tag before packaging. The ZIP and DMG are ~1.2 GB
each; uploading them in separate `gh release upload` calls makes a failure
easier to retry. Confirm what landed with
`shasum -a 256 -c dist/release/*.sha256` and by diffing the published
`.sha256` files against the local ones.

## Guardrails

`tools/package_dmg.py` requires exactly one channel and refuses to blur them:

| Flag | Accepts | Asset name |
| --- | --- | --- |
| `--notarize` | Developer ID Application only | `whisper_hotkey.dmg` |
| `--unnotarized` | any named identity, never ad-hoc | `whisper_hotkey.dmg` |
| `--preview` | ad-hoc signature only | must not be `whisper_hotkey.dmg` |

It also refuses any app that does not contain the pinned, verified Base model.
Never publish an ad-hoc or self-signed build as the release asset: it changes the
designated requirement on every build and silently breaks in-app updates.
