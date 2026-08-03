# Distribution

The public product route is
[`https://nikhi1g.github.io/whisper_hotkey/`](https://nikhi1g.github.io/whisper_hotkey/).
GitHub Pages deploys the static files in `site/` through `pages.yml`. The page
queries the latest GitHub release and sends its primary button to the exact
`whisper_hotkey.dmg` asset; it falls back to the releases page until that asset
exists.

## One-time repository setup

In **Settings → Pages**, select **GitHub Actions** as the Pages source. In
**Settings → Secrets and variables → Actions**, add:

| Secret | Value |
| --- | --- |
| `DEVELOPER_ID_APPLICATION_P12_BASE64` | Base64-encoded Developer ID Application certificate and private key exported as PKCS #12 |
| `DEVELOPER_ID_APPLICATION_P12_PASSWORD` | Password used for that PKCS #12 export |
| `NOTARY_APPLE_ID` | Apple ID used for notarization |
| `NOTARY_PASSWORD` | App-specific password for that Apple ID |
| `APPLE_TEAM_ID` | Apple Developer Team ID belonging to the certificate |

The certificate must be a **Developer ID Application** identity. An Apple
Development certificate or the local self-signed identity created by `run.sh`
cannot produce an internet-distributable app.

The personal-site repository only needs a normal link to
`/whisper_hotkey/`. GitHub serves this project repository's Pages site at that
route automatically; do not create a competing directory with the same name in
`nikhi1g.github.io`.

## Publish a release

1. Update `VERSION`, the embedded login-launcher version, release notes, and the
   matching file under `docs/releases/`.
2. Run `swift test` and `python3 build_app.py` locally with a stable development
   identity.
3. Commit the release, then create and push the matching tag, such as `v3.1.0`.
4. The `release.yml` workflow builds pinned whisper.cpp 1.9.1 for the declared
   macOS 14 deployment target, downloads Base English, verifies its pinned
   SHA-256, tests the project, and imports the temporary Developer ID identity.
5. The workflow builds with hardened runtime and secure timestamps, creates and
   signs the DMG, waits for Apple notarization, staples the ticket, performs a
   Gatekeeper assessment, and uploads the DMG, checksums, and source archive to
   the matching GitHub release.

The stable download URL used outside the product page is:

```text
https://github.com/nikhi1g/whisper_hotkey/releases/latest/download/whisper_hotkey.dmg
```

Never publish an ad-hoc, Apple Development, or self-signed build as that asset.
`tools/package_dmg.py` intentionally refuses an app that is not signed by a
Developer ID Application identity or does not contain the verified Base model.
