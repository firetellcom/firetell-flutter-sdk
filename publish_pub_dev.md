# Releasing a New Version (via GitHub Actions)

Follow these steps whenever you release a new version of **`firetell_flutter_sdk`** to [pub.dev](https://pub.dev/packages/firetell_flutter_sdk).

---

## Step 1: Bump Version and Update Changelog

1. Open `pubspec.yaml` and bump the `version` field (following [Semantic Versioning](https://semver.org/)):
   ```yaml
   version: 1.0.2
   ```

2. Open `CHANGELOG.md` and add release notes for the new version at the top:
   ```markdown
   ## [1.0.2] - YYYY-MM-DD

   ### Added / Fixed / Changed
   - Describe notable changes and improvements...
   ```

---

## Step 2: Local Verification

Run static analysis and a dry-run publish to ensure zero errors or warnings:

```bash
# Check code style and analysis rules
flutter analyze

# Verify package layout and publish readiness
flutter pub publish --dry-run
```

> **Expected output:** `Package has 0 warnings.`

---

## Step 3: Commit and Push to `main`

```bash
git add .
git commit -m "chore: release version 1.0.2"
git push origin main
```

---

## Step 4: Create and Push Git Tag to Trigger CI/CD

Create a release tag matching the pattern `v*.*.*` and push it:

```bash
git tag v1.0.2
git push origin v1.0.2
```

🚀 **GitHub Actions Automation:**
- The tag triggers `.github/workflows/publish.yml` using the official `dart-lang/setup-dart` workflow.
- It sets up the environment, resolves dependencies, and validates the package.
- It authenticates with pub.dev via Google OpenID Connect (OIDC) without requiring static API keys or secrets.
- The new release will be live on pub.dev within 1–2 minutes!

---

## Manual Publishing (Fallback)

If you need to publish manually from your local machine:

```bash
# 1. Ensure clean working directory and zero warnings
flutter pub publish --dry-run

# 2. Publish to pub.dev
flutter pub publish
```

*When prompted, press `y` and authenticate in your browser using a Google account associated with the `firetell.com` publisher.*

---

## Pre-Publish Checklist

Before releasing, make sure:

- [ ] Version in `pubspec.yaml` is bumped and follows semver.
- [ ] `CHANGELOG.md` contains notes for the new version.
- [ ] `flutter analyze` passes with `No issues found!`.
- [ ] Internal documentation directory is named `doc/` (singular, pub.dev standard).
- [ ] Main documentation file is named `README.md` (uppercase).
- [ ] Git repository is clean before creating and pushing the release tag.
- [ ] `flutter pub publish --dry-run` completes with `Package has 0 warnings.`.
