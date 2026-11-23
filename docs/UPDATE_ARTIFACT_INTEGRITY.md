# TV update artifact integrity — design boundary

## Current behavior

The updater downloads an APK over the configured HTTP(S) URL, writes it to app storage, and records its path, version, version code, channel, byte count, and source URL. Pending-file recovery currently checks existence, a 1,000-byte minimum, the legacy 95% expected-size threshold, and whether the pending version is already installed.

These checks detect some incomplete/stale files. They do **not** establish APK authenticity or byte-for-byte integrity. The 95% rule intentionally remains unchanged for compatibility in this change set.

## Recommended additive integrity contract

1. Extend the update manifest with an optional sha256 field containing exactly 64 hexadecimal characters for the selected APK.
2. Parse and normalize the digest in the pure manifest parser. Reject malformed, non-hex, or wrong-length values as invalid digest metadata; do not silently treat a malformed digest as absent.
3. Compute SHA-256 over the completed downloaded file before persisting it as a pending update. If a valid digest is supplied and the computed digest differs, delete the partial/downloaded file, clear pending metadata, and do not offer installation.
4. Persist the expected digest with pending-update metadata. On every pending-update load, recompute the file digest and compare it again before offering installation. This prevents a file modified after download from being treated as verified.
5. Keep compatibility explicit: when the manifest has no digest, legacy behavior may remain available only as unverified until the server manifest is updated. A future policy may require hashes, but turning that on must be a coordinated server/client rollout.
6. Preserve Android's package installer signature checks. SHA-256 from the manifest detects transfer/storage corruption only to the extent the manifest itself is trusted; it is not a replacement for APK signing or a trusted signing-key policy.
7. Never use a hash supplied by the APK itself. The expected digest must come from the separately fetched update manifest over authenticated HTTPS.

## Rollout sequence

- Phase A: add pure digest-format parsing and hash-comparison tests, with no change to existing manifest compatibility.
- Phase B: calculate the digest after download, persist it, and re-check pending files before offering installation.
- Phase C: publish matching hashes in the server manifest and verify a real update on a test TV.
- Phase D: only after the server-side rollout is confirmed, consider making the digest mandatory. Do not silently flip this requirement in a client-only release.

## Explicit non-goals

No changes to tunnel behavior, server selection, credentials, package identity, version, signing configuration, release workflow, or production manifest. No release or deployment is performed by this design note.
