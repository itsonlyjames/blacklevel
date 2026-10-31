#!/bin/bash
# Builds, signs, notarises and uploads a GitHub release of both apps.
#   ./release.sh 1.1.0             draft release: check it on GitHub, then press Publish
#   ./release.sh 1.1.0 --publish   publish straight away
#   ./release.sh 1.1.0 --dry-run   build, sign and notarise only: no commit, tag, push or upload
# Notes come from release/<version>/NOTES.md. Signing uses the Developer ID certificate and the
# "blacklevel" notarytool profile in your keychain; neither leaves this Mac.
set -euo pipefail
cd "$(dirname "$0")"

VERSION=${1:-}
PUBLISH=0 DRY=0
for arg in "${@:2}"; do
  case $arg in
    --publish) PUBLISH=1 ;;
    --dry-run) DRY=1 ;;
    *) echo "Unknown option $arg" >&2; exit 1 ;;
  esac
done
[[ $VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Usage: ./release.sh <x.y.z> [--publish | --dry-run]" >&2; exit 1; }

TAG=v$VERSION
OUT=release/$VERSION
NOTES=$OUT/NOTES.md
PLIST=menubar/Resources/Info.plist
MANIFEST=launcher/app/AndroidManifest.xml
APP=menubar/build/BlacklevelRemote.app
ZIP=$OUT/BlacklevelRemote-$VERSION-macOS.zip
APK=$OUT/BlacklevelHome-$VERSION.apk
PROFILE=blacklevel

fail() { echo "✗ $*" >&2; exit 1; }
step() { printf '\n→ %s\n' "$*"; }

step "Checking"
[[ $(git branch --show-current) == main ]] || fail "Not on main"
# The version files are put back with git checkout at the end, so they can't hold unsaved edits.
[[ -z $(git status --porcelain -- "$PLIST" "$MANIFEST") ]] || fail "Commit or stash your changes to $PLIST and $MANIFEST first"
! git rev-parse -q --verify "refs/tags/$TAG" >/dev/null || fail "$TAG already exists"
IDENTITY=$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application/ {print $2; exit}')
[[ -n $IDENTITY ]] || fail "No Developer ID Application certificate in the keychain"
xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1 || fail "No working notarytool profile \"$PROFILE\""
if (( !DRY )); then
  [[ -z $(git status --porcelain --untracked-files=no) ]] || fail "Commit or stash your changes first"
  gh auth status >/dev/null 2>&1 || fail "gh isn't logged in"
  [[ -s $NOTES ]] || fail "Write the release notes in $NOTES first"
  # The release commit and tag are public, so they mustn't carry a personal address.
  [[ $(git config user.email) == *@users.noreply.github.com ]] || fail "git user.email isn't your GitHub noreply address"
  git fetch -q origin main
  git merge-base --is-ancestor origin/main HEAD || fail "main is behind origin/main: pull first"
fi

step "Setting version $VERSION"
# Until the release commit, put the version files back however the script ends.
trap 'git checkout -q -- "$PLIST" "$MANIFEST"' EXIT
BUILD=$(( $(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$PLIST") + 1 ))
CODE=$(( $(sed -nE 's/.*android:versionCode="([0-9]+)".*/\1/p' "$MANIFEST") + 1 ))
sed -i '' -E \
  -e "s|(<key>CFBundleShortVersionString</key><string>)[^<]*|\1$VERSION|" \
  -e "s|(<key>CFBundleVersion</key><string>)[^<]*|\1$BUILD|" "$PLIST"
sed -i '' -E \
  -e "s/android:versionCode=\"[0-9]+\"/android:versionCode=\"$CODE\"/" \
  -e "s/android:versionName=\"[^\"]*\"/android:versionName=\"$VERSION\"/" "$MANIFEST"
mkdir -p "$OUT"

step "Building and signing Blacklevel Remote"
SIGN_IDENTITY=$IDENTITY RELEASE=1 menubar/build.sh
codesign --verify --strict --deep "$APP"

step "Notarising (usually a few minutes)"
rm -f "$ZIP"
ditto -c -k --keepParent --norsrc --noextattr "$APP" "$ZIP"
RESULT=$(xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait --output-format json)
STATUS=$(plutil -extract status raw -o - - <<<"$RESULT")
if [[ $STATUS != Accepted ]]; then
  xcrun notarytool log "$(plutil -extract id raw -o - - <<<"$RESULT")" --keychain-profile "$PROFILE" || true
  fail "Notarisation: $STATUS"
fi
xcrun stapler staple -q "$APP"
spctl --assess --type execute "$APP" || fail "Gatekeeper rejects the stapled app"
# Zip again so the download carries the stapled ticket and opens offline.
rm "$ZIP"
ditto -c -k --keepParent --norsrc --noextattr "$APP" "$ZIP"

step "Building Blacklevel Home"
launcher/build.sh >/dev/null
cp launcher/build/home.apk "$APK"

(cd "$OUT" && shasum -a 256 "$(basename "$ZIP")" "$(basename "$APK")" > SHA256SUMS.txt)

step "Ready: $TAG"
ls -lh "$ZIP" "$APK" | awk '{print "  " $5 "\t" $9}'
sed 's/^/  /' "$OUT/SHA256SUMS.txt"
if (( DRY )); then
  echo
  echo "Dry run: stopped before commit, tag, push and upload. Files are in $OUT."
  exit 0
fi
echo
echo "Notes ($NOTES):"
head -n 8 "$NOTES" | sed 's/^/  /'
(( PUBLISH )) && KIND=published || KIND=draft
echo
read -r -p "Commit, tag $TAG, push and create a $KIND release? [y/N] " answer
[[ $answer == [yY] ]] || fail "Stopped. Nothing was committed or uploaded."

git add "$PLIST" "$MANIFEST"
git commit -q -m "Release $VERSION"
trap - EXIT
git tag -a "$TAG" -m "Blacklevel $VERSION"
git push -q origin main "$TAG"
(( PUBLISH )) && DRAFT=--draft=false || DRAFT=--draft
gh release create "$TAG" "$DRAFT" --verify-tag --title "Blacklevel $VERSION" --notes-file "$NOTES" \
  "$ZIP" "$APK" "$OUT/SHA256SUMS.txt"
