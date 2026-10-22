# Releasing SuperLaunchpad

Releases are built by [`.github/workflows/release.yml`](../.github/workflows/release.yml)
on GitHub Actions whenever a `v*` tag is pushed. The workflow produces
`SuperLaunchpad-X.Y.Z.dmg`, uploads it as a build artifact and attaches it to a
GitHub Release.

The workflow works in two modes:

| Mode | When | Result |
|---|---|---|
| **Signed** | all seven secrets below are set | app signed with Developer ID + hardened runtime, DMG signed, notarized by Apple and stapled. Opens without Gatekeeper warnings. |
| **Unsigned** | any secret is missing | same DMG as before, unsigned; the run shows an "Unsigned build" warning. macOS blocks it on first launch (users must right-click → Open, or allow it in System Settings → Privacy & Security). |

Signed mode needs a paid [Apple Developer Program](https://developer.apple.com/programs/)
membership (99 USD/year). Only the Account Holder can create Developer ID certificates.

## 1. Create the Developer ID Application certificate

You need a Mac with Keychain Access (Xcode is not required).

1. Open **Keychain Access** → menu **Keychain Access → Certificate Assistant →
   Request a Certificate From a Certificate Authority…**
2. Enter your email and name, leave *CA Email* empty, choose **Saved to disk**,
   and save `CertificateSigningRequest.certSigningRequest`.
3. Go to [developer.apple.com/account/resources/certificates](https://developer.apple.com/account/resources/certificates/list)
   → **+** → **Developer ID Application** → Continue. If asked for a profile
   type, pick **G2 Sub-CA**.
4. Upload the `.certSigningRequest`, then download `developerID_application.cer`.
5. Double-click the `.cer` to install it. In Keychain Access → **login** →
   **My Certificates** you should now see
   `Developer ID Application: <Your Name> (<TEAMID>)` with a private key under it.

> Keep this certificate safe: Apple allows only a few Developer ID certificates
> per account, and everything signed with it is tied to your name.

## 2. Export the certificate as .p12 and base64 it

1. In Keychain Access → **My Certificates**, right-click
   `Developer ID Application: …` → **Export…**
2. Format **Personal Information Exchange (.p12)**, save as `developer-id.p12`.
3. Set a strong export password. This becomes `MACOS_CERTIFICATE_PASSWORD`.
4. Encode the file and copy it to the clipboard (nothing is printed):

   ```bash
   base64 -i developer-id.p12 | pbcopy
   ```

   Paste it as `MACOS_CERTIFICATE_P12_BASE64` (step 5), then delete the `.p12`
   from disk or keep it in a password manager.

## 3. Find your Team ID

[developer.apple.com/account](https://developer.apple.com/account) →
**Membership details** → **Team ID** (10 characters, e.g. `AB12CD34EF`).
It is also the part in parentheses in the certificate name.
This becomes `APPLE_TEAM_ID`.

## 4. Create an App Store Connect API key (for notarization)

1. Go to [App Store Connect → Users and Access → Integrations → App Store Connect API](https://appstoreconnect.apple.com/access/integrations/api)
   (on first visit, click **Request Access** and accept the terms).
2. Under **Team Keys**, click **+** (Generate API Key).
3. Name it e.g. `SuperLaunchpad CI`, Access: **Developer**. Generate.
4. Note the **Key ID** of the new row → `APPSTORE_API_KEY_ID`.
5. Note the **Issuer ID** shown above the table → `APPSTORE_API_ISSUER_ID`.
6. Click **Download API Key** and save `AuthKey_<KEYID>.p8`.
   **It can be downloaded only once.**
7. Encode it and copy it to the clipboard:

   ```bash
   base64 -i AuthKey_XXXXXXXXXX.p8 | pbcopy
   ```

   This becomes `APPSTORE_API_KEY_P8_BASE64`. Keep the `.p8` in a password
   manager; if it leaks, revoke the key in App Store Connect.

## 5. Add the secrets to GitHub

Open the repository on GitHub → **Settings** → **Secrets and variables** →
**Actions** → **New repository secret**, and add each one (names must match exactly):

| Secret | Value |
|---|---|
| `MACOS_CERTIFICATE_P12_BASE64` | base64 of `developer-id.p12` (step 2) |
| `MACOS_CERTIFICATE_PASSWORD` | the `.p12` export password (step 2) |
| `MACOS_KEYCHAIN_PASSWORD` | any random string; it protects the temporary keychain on the CI runner. Generate one with `openssl rand -base64 24 \| pbcopy` |
| `APPLE_TEAM_ID` | your Team ID (step 3) |
| `APPSTORE_API_KEY_P8_BASE64` | base64 of `AuthKey_<KEYID>.p8` (step 4) |
| `APPSTORE_API_KEY_ID` | Key ID (step 4) |
| `APPSTORE_API_ISSUER_ID` | Issuer ID (step 4) |

GitHub masks secret values in logs, and the workflow never prints them. The
certificate and API key files are written to `$RUNNER_TEMP` only for the step
that needs them and deleted afterwards; the temporary keychain is deleted at the
end of the job even if it fails.

## 6. Cut a release

1. Make sure `main` is green and up to date locally.
2. Tag and push (the version comes from the tag, without the `v`):

   ```bash
   git tag v1.2.3
   ```

   ```bash
   git push origin v1.2.3
   ```

3. Watch **Actions → Release**. With secrets set, the notarization step usually
   takes 1–10 minutes.
4. When it finishes, the GitHub Release `v1.2.3` has
   `SuperLaunchpad-1.2.3.dmg` attached with auto-generated release notes.

You can also run the workflow manually (**Actions → Release → Run workflow**,
enter a version). That builds the DMG and uploads it as an artifact but does
**not** publish a GitHub Release.

## What the signed pipeline does

1. Imports the `.p12` into a temporary keychain created in the job.
2. Builds the app with `CODE_SIGN_STYLE=Manual`,
   `CODE_SIGN_IDENTITY="Developer ID Application"`, your Team ID, hardened runtime
   and `--timestamp` (both required for notarization).
3. Verifies the app with `codesign --verify --deep --strict`.
4. Packs the DMG and signs it with the same identity.
5. Submits the DMG with `xcrun notarytool submit --wait`. Apple checks the
   DMG and the signed app inside it in one submission. On failure the
   notarization log is printed and the job fails.
6. Staples the ticket to the DMG (`xcrun stapler staple`), so it passes
   Gatekeeper even offline. The `.app` inside is covered by the same ticket,
   which Gatekeeper looks up online on first launch.
7. Checks the result with `stapler validate`, `codesign --verify` and
   `spctl -a -vv -t install`.

## Verifying a downloaded DMG locally

```bash
spctl -a -vv -t install SuperLaunchpad-1.2.3.dmg
```

Expected: `accepted` and `source=Notarized Developer ID`.

## Troubleshooting

- **"No 'Developer ID Application' identity"**: the `.p12` was exported
  without its private key, or it holds a different certificate type
  (e.g. *Apple Development*). Re-export from **My Certificates**.
- **Notarization status `Invalid`**: open the printed log. Typical causes are
  a missing hardened runtime or secure timestamp on some binary.
- **401 from notarytool**: wrong Key ID / Issuer ID, the key was revoked, or the
  `.p8` was base64-encoded with line breaks lost. Re-encode with `base64 -i`.
- **Certificate expired** (Developer ID certificates last 5 years): create a new
  one (steps 1–2) and update the two `MACOS_CERTIFICATE_*` secrets.
