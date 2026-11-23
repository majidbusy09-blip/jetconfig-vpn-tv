# TV update artifact integrity — design and rollout

## Current behavior

The updater downloads an APK over the configured HTTP(S) URL, writes it to app storage, and records its path, version, version code, channel, byte count, and source URL. Pending-file recovery also checks existence, a 1,000-byte minimum, the legacy 95% expected-size threshold, and whether the pending version is already installed.

These checks alone do **not** establish APK authenticity or byte-for-byte integrity. The 95% rule remains unchanged for compatibility.

## Implemented phases

### Phase A — manifest digest contract

- The update manifest may include `sha256` with exactly 64 hexadecimal characters.
- The parser normalizes valid digests to lowercase.
- Missing or null digest preserves legacy behavior; malformed present values reject the manifest.

### Phase B — client-side file verification

- When a manifest supplies a digest, the client computes SHA-256 over the completed APK before saving it as pending.
- A mismatch deletes the downloaded file, clears pending metadata, and prevents the install prompt.
- The expected digest is stored with pending metadata.
- Every pending-update load recomputes the file digest; a mismatch deletes the file and clears metadata.
- Both the already-downloaded and just-downloaded install paths revalidate pending state immediately before opening the Android package installer.
- Manifests without a digest remain compatible but explicitly unverified; no locally calculated digest is treated as a trusted expected value.

## Remaining rollout

- Phase C: publish matching hashes in the update server manifest and verify a real update on a test TV. This requires explicit approval before changing the production manifest.
- Phase D: only after server-side rollout is confirmed, consider making the digest mandatory. Do not silently change this requirement in a client-only update.

## Security boundary

The expected digest comes from the separately fetched update manifest over authenticated HTTPS, never from the APK itself. SHA-256 detects corruption or substitution relative to that manifest, but it does not independently establish who authored the manifest. Android package installer signature checks remain essential; this digest is not a replacement for APK signing or a trusted signing-key policy.

## Explicit non-goals

No changes to tunnel behavior, server selection, credentials, package identity, app version, signing configuration, release workflow, or production manifest. No release or deployment is performed.
