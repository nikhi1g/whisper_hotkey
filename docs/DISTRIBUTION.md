# Distribution

The public product route is
[`https://nikhi1g.github.io/whisper_hotkey/`](https://nikhi1g.github.io/whisper_hotkey/).
GitHub Pages deploys `site/` through `pages.yml`. The page queries the latest
stable GitHub release and links only the exact `whisper_hotkey.dmg` asset. If
that asset is absent, the page leaves the user on the releases page rather than
silently selecting a source archive or an obsolete application ZIP.

## Signing and notarization policy

Every stable release must be:

- signed with the project's **Developer ID Application** identity;
- signed with secure timestamps and the hardened runtime;
- granted only the hardened-runtime audio-input entitlement required for local
  microphone capture;
- submitted to Apple's notary service with `notarytool`;
- accepted, stapled, and validated before its checksum is written;
- accepted by Gatekeeper as a disk image before publication.

The human download and the in-app updater use the same
`whisper_hotkey.dmg`/`whisper_hotkey.dmg.sha256` pair. Stable releases never
publish an application ZIP, an Apple Development build, an ad-hoc build, or an
unnotarized fallback.

The first Developer ID release changes the designated requirement from the
historical Apple Development identity. The existing updater permits this
one-time migration by accepting a differently signed candidate only when
Gatekeeper trusts it. macOS may still require existing users to regrant
Microphone, Accessibility, and Input Monitoring once after that transition.
The bundle identifier, application name, preference domain, and update asset
names must not change.

## One-time Apple and repository setup

Create a **Developer ID Application** certificate for the project's Apple
Developer team, install it with its private key, and export that identity as a
password-protected PKCS #12 file. Create an Apple ID app-specific password for
`notarytool` and confirm the team ID in the Apple Developer account.

Create a GitHub environment named `release`. Add these environment secrets
under **Settings → Environments → release**:

| Secret | Value |
| --- | --- |
| `APPLE_SIGNING_CERTIFICATE_P12_BASE64` | Base64-encoded Developer ID Application certificate and private key |
| `APPLE_SIGNING_CERTIFICATE_P12_PASSWORD` | Password protecting the PKCS #12 export |
| `NOTARY_APPLE_ID` | Apple ID used by the developer team |
| `NOTARY_PASSWORD` | Apple ID app-specific password |
| `APPLE_TEAM_ID` | Developer team identifier |

Export and upload the certificate without printing its contents:

```sh
/usr/bin/security export -k login.keychain-db -t identities -f pkcs12 \
  -P '<temporary-export-password>' \
  -o ~/Desktop/whisper_hotkey-developer-id.p12
gh secret set --env release APPLE_SIGNING_CERTIFICATE_P12_BASE64 \
  < <(base64 -i ~/Desktop/whisper_hotkey-developer-id.p12)
gh secret set --env release APPLE_SIGNING_CERTIFICATE_P12_PASSWORD
gh secret set --env release NOTARY_APPLE_ID
gh secret set --env release NOTARY_PASSWORD
gh secret set --env release APPLE_TEAM_ID
rm ~/Desktop/whisper_hotkey-developer-id.p12
```

Enter secret values only at the hidden prompts. Never place a certificate,
private key, Apple password, or app-specific password in a tracked file,
command-line argument, release note, issue, or chat.

In **Settings → Pages**, keep **GitHub Actions** as the Pages source. The
personal-site repository needs only its normal `/whisper_hotkey/` link; do not
create a competing directory with the same route in `nikhi1g.github.io`.

## CI preflight

Before the first notarized tag, run `release.yml` manually against the release
commit. `workflow_dispatch` performs the complete build, Developer ID signing,
notarization, stapling, and Gatekeeper assessment but does not create a GitHub
release. A missing credential or rejected submission fails before publication.

Inspect the workflow's `notarytool log` output even when Apple accepts the
submission. Resolve every signing or hardened-runtime warning before tagging.

## Publish a release

1. Update `VERSION`, the embedded login-launcher version, `RELEASE_NOTES.md`,
   `CHANGELOG.md`, and the matching file under `docs/releases/`.
2. Run the complete suite and a local Developer ID/notarization candidate.
3. Commit the release and push the release commit.
4. Run the non-publishing `workflow_dispatch` preflight.
5. Create and push the matching stable tag, such as `v4.2.8`.
6. `release.yml` builds the pinned macOS 14 dependencies, downloads the bundled
   Parakeet checkpoints, tests the project, imports the temporary Developer ID
   identity, notarizes and staples the DMG, then creates the GitHub release.
7. Confirm the release contains the DMG, its checksum, the source archive, and
   its checksum. It must not contain a separately packaged application ZIP.
8. Download the public DMG through a browser and complete the Finder-based
   fresh-install test.

The workflow creates the release only after every notarization and assessment
gate passes. Do not hand-upload a failed, locally substituted, or unnotarized
artifact under the stable asset name.

## Local release-candidate build

Build the pinned whisper.cpp library for the declared macOS 14 deployment
target. `build_app.py` refuses Homebrew's host-targeted `whisper-cpp`, and
`verify_distribution_targets` rejects any bundled binary requiring a newer
macOS version.

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

With the bundled Parakeet checkpoints present in FluidAudio's model cache:

```sh
export WHISPER_HOTKEY_CODESIGN_IDENTITY='Developer ID Application: …'
export NOTARY_APPLE_ID='…'
export NOTARY_PASSWORD='…'
export APPLE_TEAM_ID='…'
WHISPER_HOTKEY_BUNDLE_MODEL=1 WHISPER_HOTKEY_DISTRIBUTION=1 \
  python3 build_app.py
python3 tools/package_dmg.py --notarize
```

For an actual tagged release, create the source archive with:

```sh
python3 tools/package_release.py "v$(cat VERSION)"
```

`package_release.py` refuses a dirty tree and a tag that does not match
`VERSION`. Never replace assets under a published tag. If a release must be
withdrawn, restore the previous release as latest and publish the correction
under a higher version.

## Verification gates

The final public artifact must pass all of these checks:

```sh
codesign --verify --deep --strict --verbose=2 dist/whisper_hotkey.app
codesign --display --verbose=4 dist/whisper_hotkey.app
codesign --display --entitlements :- dist/whisper_hotkey.app
xcrun stapler validate dist/release/whisper_hotkey.dmg
hdiutil verify dist/release/whisper_hotkey.dmg
spctl --assess --type open --context context:primary-signature \
  --verbose=4 dist/release/whisper_hotkey.dmg
shasum -a 256 -c dist/release/whisper_hotkey.dmg.sha256
```

The entitlement output must contain
`com.apple.security.device.audio-input = true`, must not contain
`com.apple.security.get-task-allow = true`, and the code-directory flags must
include `runtime`.

Command-line mounting is not proof of the user installation path. Download the
published DMG through Safari on a clean macOS 14-or-newer VM, open it through
Finder, drag the app to Applications, and launch it. Gatekeeper must not show
**Move to Trash** or require **Open Anyway**. Complete all three permissions,
dictate in TextEdit, Safari, and an Electron application, restart, verify the
login item, and exercise an update from the previous Apple Development-signed
release.

## Guardrails

`tools/package_dmg.py` exposes only two explicit channels:

| Flag | Accepts | Stable asset name allowed |
| --- | --- | --- |
| `--notarize` | Developer ID Application, hardened runtime, audio-input entitlement | yes |
| `--preview` | ad-hoc signature under an explicitly different filename | no |

The packager also requires every bundled model/checkpoint, a valid deep code
signature, an accepted notary response, a stapled ticket, and a successful
Gatekeeper assessment. The checksum is generated only after those steps.
