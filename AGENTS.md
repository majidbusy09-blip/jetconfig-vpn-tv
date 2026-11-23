# Agent instructions — JET VPN TV

1. Read `docs/PROJECT_CONTEXT.md`, `docs/CURRENT_STATUS.md`, and `docs/NEXT_STEPS.md` before engineering work.
2. Re-fetch the current branch, commit SHA, relevant Dart symbols, `pubspec.yaml`, and CI workflow before changing code.
3. Work on a dedicated branch; never commit directly to `main`.
4. Keep tunnel, server selection, authentication, update/install, signing, package identity, and release behavior out of scope unless explicitly requested and approved.
5. Distinguish analysis, build success, and real Android TV runtime/device testing.
6. Record meaningful changes and exact verification in project docs and PRs.
7. For PRs, rely on `.github/workflows/pr-validation.yml`: read-only permissions, analyzer, optional tests, and ARM64 debug APK build. Never treat this debug build as a release or device-runtime test.

## Safety
- The main-branch workflow triggers on pushes to `main`, has `contents: write`, builds release APKs, and creates a GitHub Release. A merge/push to `main` can publish.
- The PR validation workflow is separate and grants only `contents: read`; it must never be expanded to run release jobs or receive signing secrets.
- Do not dispatch release workflows, create tags/releases, alter signing, or deploy without explicit approval.
- Never expose signing secrets, keystores, or passwords.

## Architecture
- Flutter Android TV / Google TV app; implementation concentrated in `lib/main.dart`.
- `patch_tv.py` patches the generated Android project; `patch_signing.py` handles release signing setup.
- No tracked `test/` directory exists in the inspected baseline; the PR workflow skips tests when none exist.
