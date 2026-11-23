# TV update SHA-256 rollout checklist

## Scope and verified client contract

- The TV client fetches update metadata from `https://majid6064.ir/app_version_tv.json`.
- The current client channel is `arm32`.
- The metadata parser accepts a top-level optional `sha256` field containing exactly 64 hexadecimal characters; it normalizes valid values to lowercase.
- The APK URL is selected from `urls.arm32`, then `urls.armeabi-v7a`, `urls.arm64`, and `urls.universal`; legacy aliases are also supported.
- The client computes SHA-256 over the downloaded APK bytes and compares it with the manifest value before saving the APK as pending.
- A pending APK is hashed again when loaded and immediately before the install flow is opened.
- A missing or null digest remains backward-compatible but means the APK is not digest-verified. A malformed present digest rejects the manifest.

## Backend source discovery and patch status

The publishing backend was located in the user-provided archive `JetConfig_LATEST_20261118(1).zip`, at `webadmin/app_update_tv.php`. The panel creates/updates the public `app_version_tv.json`; the manifest is not a separately maintained static file in that archive.

A server-side patch bundle was prepared outside this repository. It:
- adds an optional top-level `sha256` field to the TV update metadata;
- validates a nonblank digest as exactly 64 hexadecimal characters and normalizes it to lowercase;
- preserves legacy behavior when the field is blank/null;
- adds an optional SHA-256 input to the TV update admin form;
- places the helper at `webadmin/includes/tv_update_integrity.php`.

The patch was validated locally: 11 digest-helper checks, 5 manifest-contract checks, 4 panel integration checks, and PHP syntax checks passed. This is local/simulated validation only.

**Staging status:** no staging host or panel access was available. The project owner elected to close the staging-access task for planning purposes. No live backend deployment, production manifest change, real HTTP round-trip, or physical-TV verification is claimed. Treat the backend patch as prepared and locally validated, not deployed.

## Example test manifest (synthetic only)

Use a test endpoint and a test APK. Replace every example value with metadata for the exact test artifact; never copy this fixture into production unchanged.

```json
{
  "enabled": true,
  "version": "tv-test-1.0.15",
  "version_code": 115,
  "title": "JET TV test update",
  "changelog": "SHA-256 verification test",
  "force": false,
  "urls": {
    "arm32": "https://test.example.invalid/jet-tv-test.apk"
  },
  "sha256": "REPLACE_WITH_THE_64_CHARACTER_SHA256_OF_THE_EXACT_SERVED_APK"
}
```

The placeholder above is intentionally invalid and must be replaced before parser acceptance. The digest must be computed from the final APK bytes that the URL actually serves—not from an intermediate build, an archive containing the APK, or a different ABI.

## Server-side publication procedure

1. Build and sign the intended APK using the approved release process.
2. Record the final APK's exact byte size and compute its SHA-256.
3. Upload that exact APK to the test download location.
4. Download the uploaded artifact back from the test URL and compute SHA-256 again. The two digests must match.
5. Publish a test manifest whose selected URL points to that exact file and whose top-level `sha256` equals the verified digest.
6. Confirm the test manifest is served over HTTPS and that its URL/redirect chain serves the expected APK bytes.
7. Do not change the production manifest as part of this test.

## Test-TV verification matrix

| Case | Test setup | Expected result |
|---|---|---|
| Valid digest | Manifest hash matches the served APK | Download completes; pending APK is accepted; installation prompt can be opened |
| Wrong digest | Change one hex character in the manifest hash | Downloaded APK is deleted; pending metadata is cleared; install is blocked |
| Missing digest | Omit `sha256` | Legacy-compatible download remains possible, but is explicitly unverified |
| Null digest | Set `sha256` to JSON null | Same legacy-compatible behavior as missing digest |
| Malformed digest | Use a non-hex value or a length other than 64 | Manifest is rejected |
| Pending-file tamper | Modify a byte after a matching-hash download but before reopening the pending update | Pending APK is deleted and cannot be offered for installation |
| Re-download | Restore the correct manifest and exact APK | A fresh download verifies and becomes pending |
| Android installer | Install the valid test APK over the expected existing app signature/package | Android's normal package/signature checks still apply; SHA-256 does not replace them |

Record the TV model, Android version, app version before/after, manifest URL, APK URL, expected digest, observed digest, and outcome for each run. Never record credentials or private signing material in this checklist.

## Rollout gates

- [x] Backend source located in the user-provided archive; patch prepared and locally validated.
- [x] Staging-access task closed by project owner because no staging access is available. This does not mean live staging verification passed.
- [ ] Test endpoint and test APK are available without changing production.
- [ ] Downloaded test APK digest matches the digest computed from the final release artifact.
- [ ] Valid and negative cases pass on a physical Android TV.
- [ ] Android package/signature compatibility is confirmed.
- [ ] Production publication is separately approved by the project owner.
- [ ] Only after production hashes are consistently published and observed should a separate change propose making `sha256` mandatory.

## Safety boundary

This checklist does not authorize editing the production manifest, changing the update endpoint, publishing an APK, dispatching a release workflow, changing signing configuration, or making the digest mandatory. Those are separate actions requiring explicit approval.
