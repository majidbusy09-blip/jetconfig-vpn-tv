# JET VPN TV — Prioritized Next Steps

1. Keep the read-only PR validation workflow green for source analysis, tests, and a non-release ARM64 debug APK.
2. Preserve the extracted pure logic for connection state, server ping ranking, profile persistence, update metadata, and pending-update decisions. Avoid unrelated refactors.
3. Phase A and Phase B of update artifact integrity are implemented: optional SHA-256 metadata parsing, digest computation after download, persistence of the expected digest, and revalidation before a pending APK is offered or opened for installation. Legacy manifests without a digest remain accepted but unverified.
4. Next: review the production update-manifest publishing contract and prepare a test-TV rollout plan. Do not edit or publish the production manifest without explicit approval. Only after server-side hashes are published and verified should mandatory digest policy be considered.
5. Maintain a manual TV checklist for real traffic, remote focus/navigation, sleep/resume, profile switching, and APK update/install.

Deferred: tunnel/server/authentication changes without a concrete issue; signing, package identity, version, release, tag, production manifest, or deployment changes without explicit approval.
