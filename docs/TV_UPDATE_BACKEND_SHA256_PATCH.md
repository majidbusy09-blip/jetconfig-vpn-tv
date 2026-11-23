# JET VPN TV backend SHA-256 patch record

## Source discovery

- Source archive supplied in the conversation: `JetConfig_LATEST_20261118(1).zip`.
- Backend panel source: `webadmin/app_update_tv.php`.
- Public metadata URL shown by the panel: `https://majid6064.ir/app_version_tv.json`.
- The PHP panel generates/updates the JSON manifest; the archive did not contain a standalone `app_version_tv.json` source file.
- No corresponding backend Git repository or staging host was identified. The patch is therefore maintained as a separate handoff bundle, not committed as executable backend code to this Flutter TV repository.

## Patch contents

- Patched `webadmin/app_update_tv.php`.
- New helper to install at `webadmin/includes/tv_update_integrity.php`.
- Local test scripts for digest validation and manifest contract.
- Persian installation/rollback instructions and unified diff.

The panel adds an optional SHA-256 field and publishes a top-level `sha256` value. Nonblank values must contain exactly 64 hexadecimal characters; values are normalized to lowercase. Blank values remain compatible with legacy manifests. The digest must describe the exact APK URL selected by the TV client. The client currently prefers `urls.arm32`; its current parser consumes one top-level digest, not a per-ABI digest map.

## Local verification evidence

- Digest helper tests: 11 checks passed.
- Manifest contract tests: 5 checks passed.
- Panel integration simulation: 4 checks passed.
- PHP syntax checks: no syntax errors in the patched panel or helper.
- No live server was modified. No production JSON or APK was published.

## Deployment handoff

1. Back up the current panel file and relevant manifest before any deployment.
2. On a staging copy, replace `webadmin/app_update_tv.php` and add `webadmin/includes/tv_update_integrity.php` at that exact path.
3. Verify the PHP runtime supports the syntax/features used by the existing panel and run the included checks in the staging environment.
4. Enter the SHA-256 of the exact APK selected by the TV client and verify the generated manifest.
5. Exercise matching and mismatching digest cases on a physical test TV.
6. Only after separate approval should production deployment be considered.

The project owner confirmed there is no staging access and asked to treat this blocked stage as complete for purposes of moving to subsequent work. Record it as **waived/not performed**, never as a successful live deployment or physical-device test.

## Security note

SHA-256 detects byte mismatches between the expected digest and downloaded APK, but does not authenticate the manifest publisher. HTTPS trust and Android package/signature validation remain necessary. Do not treat this mechanism as a replacement for signed metadata or APK signing.
