#!/usr/bin/env bash
# Publish Shipyard's "computer" plugin as a GitHub release Shipyard installs
# from (Settings → Plugins → Install from URL…): the universal app (Apple
# silicon + Intel), signed with your Apple Development identity so the
# Accessibility and Screen Recording grants a Mac gave it carry over to
# updates, packaged with its .sha256 beside it.
#
#   OPEN_COMPUTER_USE_CODESIGN_IDENTITY="Apple Development: …" scripts/release-shipyard-plugin.sh
#   scripts/release-shipyard-plugin.sh --dry-run    # build and package only
#
# It runs here, not in CI: the signing identity lives in this Mac's keychain.
# The release is tagged shipyard-plugin-v<version>, the version being the
# plugin's (plugins/open-computer-use/.codex-plugin/plugin.json).
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dry_run=0
[[ "${1:-}" == "--dry-run" ]] && dry_run=1
identity="${OPEN_COMPUTER_USE_CODESIGN_IDENTITY:-}"
if [[ -z "${identity}" ]]; then
  echo "Set OPEN_COMPUTER_USE_CODESIGN_IDENTITY to your Apple Development identity (security find-identity -v -p codesigning)." >&2
  exit 1
fi

version="$(node -e "console.log(require('${repo_root}/plugins/open-computer-use/.codex-plugin/plugin.json').version)")"
tag="shipyard-plugin-v${version}"
if [[ "${dry_run}" == 0 ]] && gh release view "${tag}" >/dev/null 2>&1; then
  echo "Release ${tag} exists already: bump the plugin's version first." >&2
  exit 1
fi

OPEN_COMPUTER_USE_CODESIGN_MODE=identity OPEN_COMPUTER_USE_CODESIGN_IDENTITY="${identity}" \
  "${repo_root}/scripts/build-open-computer-use-app.sh" --configuration release --arch universal
"${repo_root}/scripts/package-shipyard-plugin.sh" --os darwin

out="${repo_root}/dist/shipyard-plugin"
archive="${out}/computer-${version}-darwin-universal.tar.gz"
[[ -f "${archive}" && -f "${archive}.sha256" ]] || { echo "Missing ${archive} or its .sha256" >&2; exit 1; }
lipo -archs "${out}/computer/Open Computer Use.app/Contents/MacOS/OpenComputerUse"
codesign --verify --deep --strict "${out}/computer/Open Computer Use.app"
cat "${archive}.sha256"

if [[ "${dry_run}" == 1 ]]; then
  echo "Dry run: ${archive} is ready; not releasing."
  exit 0
fi
gh release create "${tag}" "${archive}" "${archive}.sha256" \
  --title "Shipyard computer plugin ${version}" \
  --notes "Shipyard's computer plugin ${version} for macOS (Apple silicon and Intel). In Shipyard: Settings → Plugins → Install from URL…, with the link to the .tar.gz (its SHA-256 is read from the .sha256 beside it). It is off until you allow it; then allow Accessibility and Screen Recording on each Mac once."
echo "Released ${tag}."
