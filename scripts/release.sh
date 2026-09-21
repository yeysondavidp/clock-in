#!/usr/bin/env bash
# Builds a signed release APK and publishes it as a GitHub Release,
# which the in-app update checker picks up.
#
# Usage: scripts/release.sh <patch|minor|major|current> [--notes-file FILE] [--dry-run] [-y]
#
#   patch|minor|major  bump the version in pubspec.yaml (build number always +1)
#   current            publish the version already in pubspec.yaml
#   --notes-file FILE  release notes (Markdown); default: commit subjects since last tag
#   --dry-run          run every check and build, but don't commit, push or publish
#   -y                 don't ask for confirmation before publishing

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

REPO="yeysondavidp/clock-in"
ASSET_NAME="ClockIn.apk"
APK="build/app/outputs/flutter-apk/app-release.apk"

die() { echo "✗ $*" >&2; exit 1; }
step() { echo; echo "▸ $*"; }

# ─── ARGS ───────────────────────────────────────────────

BUMP="${1:-}"
[[ "$BUMP" =~ ^(patch|minor|major|current)$ ]] || {
  sed -n '5,12p' "$0" | sed 's/^# \{0,1\}//'
  exit 1
}
shift

NOTES_FILE=""
DRY_RUN=false
ASSUME_YES=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --notes-file) NOTES_FILE="${2:-}"; [[ -f "$NOTES_FILE" ]] || die "Notes file not found: $NOTES_FILE"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    -y) ASSUME_YES=true; shift ;;
    *) die "Unknown option: $1" ;;
  esac
done

# ─── PRECONDITIONS ──────────────────────────────────────

step "Checking repository state"
[[ "$(git branch --show-current)" == "main" ]] || die "Releases are made from main"
[[ -z "$(git status --porcelain)" ]] || die "Working tree has uncommitted changes"
gh auth status >/dev/null 2>&1 || die "gh is not authenticated (run: gh auth login)"
git fetch --quiet --tags origin
git merge-base --is-ancestor origin/main HEAD || die "Local main is behind origin/main, pull first"

# ─── VERSION ────────────────────────────────────────────

CURRENT="$(sed -n 's/^version: *//p' pubspec.yaml)"
[[ "$CURRENT" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)\+([0-9]+)$ ]] || die "Unexpected pubspec version: $CURRENT"
MAJOR="${BASH_REMATCH[1]}" MINOR="${BASH_REMATCH[2]}" PATCH="${BASH_REMATCH[3]}" BUILD="${BASH_REMATCH[4]}"

case "$BUMP" in
  major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
  minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
  patch) PATCH=$((PATCH + 1)) ;;
esac
[[ "$BUMP" == "current" ]] || BUILD=$((BUILD + 1))

VERSION="$MAJOR.$MINOR.$PATCH"
TAG="$VERSION"   # existing releases use plain tags (e.g. 1.0.0)

echo "  pubspec: $CURRENT → release: $VERSION+$BUILD"

git rev-parse -q --verify "refs/tags/$TAG" >/dev/null && die "Tag $TAG already exists"

LATEST_TAG="$(gh release view --repo "$REPO" --json tagName -q .tagName 2>/dev/null || true)"
if [[ -n "$LATEST_TAG" ]]; then
  LATEST="${LATEST_TAG#[vV]}"
  NEWEST="$(printf '%s\n%s\n' "$LATEST" "$VERSION" | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)"
  [[ "$NEWEST" == "$VERSION" && "$LATEST" != "$VERSION" ]] \
    || die "Version $VERSION must be greater than the latest release ($LATEST_TAG)"
  echo "  latest published release: $LATEST_TAG"
fi

# ─── TEST & BUILD ───────────────────────────────────────

step "Running tests"
flutter test

step "Building release APK"
flutter build apk --release --build-name="$VERSION" --build-number="$BUILD"
[[ -f "$APK" ]] || die "APK not found at $APK"

# ─── SIGNATURE CHECK ────────────────────────────────────
# An APK signed with any other key can't update installed copies without
# an uninstall, which would wipe the users' data.

step "Verifying APK signature against the release keystore"
KEY_PROPS="android/key.properties"
[[ -f "$KEY_PROPS" ]] || die "$KEY_PROPS not found"
prop() { sed -n "s/^$1=//p" "$KEY_PROPS" | head -1; }

STORE_FILE="$(prop storeFile)"
[[ "$STORE_FILE" == /* ]] || STORE_FILE="android/app/$STORE_FILE"
[[ -f "$STORE_FILE" ]] || die "Keystore not found: $STORE_FILE"

APKSIGNER="$(ls -d "${ANDROID_HOME:-$HOME/Library/Android/sdk}"/build-tools/*/ | tail -1)apksigner"
[[ -x "$APKSIGNER" ]] || die "apksigner not found in Android build-tools"

APK_SHA="$("$APKSIGNER" verify --print-certs "$APK" | sed -n 's/.*certificate SHA-256 digest: //p' | head -1)"
KEY_SHA="$(KS_PASS="$(prop storePassword)" keytool -list -v -keystore "$STORE_FILE" \
  -alias "$(prop keyAlias)" -storepass:env KS_PASS 2>/dev/null \
  | sed -n 's/.*SHA256: //p' | tr -d ':' | tr 'A-F' 'a-f')"

[[ -n "$APK_SHA" && "$APK_SHA" == "$KEY_SHA" ]] \
  || die "APK is not signed with the release key (apk: ${APK_SHA:-none}, keystore: ${KEY_SHA:-unreadable})"
echo "  ✓ signed with release key (${APK_SHA:0:16}…)"

# ─── RELEASE NOTES ──────────────────────────────────────

NOTES="$(mktemp)"
trap 'rm -f "$NOTES"' EXIT
if [[ -n "$NOTES_FILE" ]]; then
  cp "$NOTES_FILE" "$NOTES"
else
  RANGE="HEAD"
  git rev-parse -q --verify "refs/tags/$LATEST_TAG" >/dev/null 2>&1 && RANGE="$LATEST_TAG..HEAD"
  git log --no-merges --format='- %s' "$RANGE" > "$NOTES"
fi

step "Release notes"
cat "$NOTES"

SIZE_MB="$(du -m "$APK" | cut -f1)"
echo
echo "  Tag:   $TAG"
echo "  APK:   $APK (${SIZE_MB} MB) → $ASSET_NAME"
echo "  Repo:  $REPO (public)"

if $DRY_RUN; then
  echo
  echo "✓ Dry run finished, nothing was committed, pushed or published."
  exit 0
fi

if ! $ASSUME_YES; then
  echo
  read -r -p "Publish $TAG? Users will be offered this update. [y/N] " answer
  [[ "$answer" =~ ^[yY]$ ]] || die "Aborted"
fi

# ─── PUBLISH ────────────────────────────────────────────

if [[ "$CURRENT" != "$VERSION+$BUILD" ]]; then
  step "Committing version bump"
  sed -i '' "s/^version: .*/version: $VERSION+$BUILD/" pubspec.yaml
  git add pubspec.yaml
  git commit -q -m "chore: release $VERSION"
fi

step "Pushing main and tag $TAG"
git tag -a "$TAG" -m "Release $VERSION"
git push --quiet origin main
git push --quiet origin "$TAG"

step "Creating GitHub release"
ASSET_DIR="$(mktemp -d)"
cp "$APK" "$ASSET_DIR/$ASSET_NAME"
gh release create "$TAG" "$ASSET_DIR/$ASSET_NAME" \
  --repo "$REPO" --title "v$VERSION" --notes-file "$NOTES" --latest
rm -rf "$ASSET_DIR"

echo
echo "✓ Released $VERSION: https://github.com/$REPO/releases/tag/$TAG"
