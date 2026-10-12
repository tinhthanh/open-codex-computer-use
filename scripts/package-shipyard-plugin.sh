#!/usr/bin/env bash
# Package open-computer-use as Shipyard's "computer" plugin: a folder (and a
# .tar.gz of it) with berth-plugin.json pinning the MCP binary and the
# berth-computer skill by sha256, ready for ~/.berth/plugins/computer.
#
#   scripts/package-shipyard-plugin.sh --os darwin            # uses dist/Open Computer Use.app
#   scripts/package-shipyard-plugin.sh --os linux --arch arm64
#
# macOS: build and sign the app first, so its Accessibility / Screen Recording
# grants follow a stable identity:
#   OPEN_COMPUTER_USE_CODESIGN_MODE=identity OPEN_COMPUTER_USE_CODESIGN_IDENTITY="Apple Development: …" \
#     scripts/build-open-computer-use-app.sh --configuration release
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
os="$(uname -s | tr '[:upper:]' '[:lower:]')"
arch="$(uname -m)"
out_dir="${repo_root}/dist/shipyard-plugin"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --os) os="${2:?--os requires a value}"; shift 2 ;;
    --arch) arch="${2:?--arch requires a value}"; shift 2 ;;
    --out-dir) out_dir="${2:?--out-dir requires a value}"; shift 2 ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done
case "${arch}" in
  x86_64) arch="amd64" ;;
  aarch64) arch="arm64" ;;
esac

version="$(node -e "console.log(require('${repo_root}/plugins/open-computer-use/.codex-plugin/plugin.json').version)")"
commit="$(git -C "${repo_root}" rev-parse --short HEAD)"
plugin_dir="${out_dir}/computer"
rm -rf "${plugin_dir}"
mkdir -p "${plugin_dir}/skills/berth-computer"

case "${os}" in
  darwin)
    app="${repo_root}/dist/Open Computer Use.app"
    if [[ ! -d "${app}" ]]; then
      echo "Missing ${app}; build it with scripts/build-open-computer-use-app.sh first." >&2
      exit 1
    fi
    codesign --verify --deep --strict "${app}"
    ditto "${app}" "${plugin_dir}/Open Computer Use.app"
    command="Open Computer Use.app/Contents/MacOS/OpenComputerUse"
    # Run with no args, the app opens its permission window; `doctor --json`
    # reports allGranted. Shipyard starts it when the plugin is allowed.
    setup_json=',
  "setup": {
    "server": "computer",
    "args": [],
    "status": ["doctor", "--json"],
    "ready": "allGranted",
    "label": "Allow Accessibility and Screen Recording for Open Computer Use"
  }'
    ;;
  linux)
    "${repo_root}/scripts/build-open-computer-use-linux.sh" --arch "${arch}" --out-dir "${out_dir}/.linux" >/dev/null
    install -D -m 0755 "${out_dir}/.linux/${arch}/open-computer-use" "${plugin_dir}/bin/open-computer-use"
    rm -rf "${out_dir}/.linux"
    command="bin/open-computer-use"
    setup_json=""
    ;;
  *)
    echo "Unsupported --os ${os} (use darwin or linux)" >&2
    exit 1
    ;;
esac

cp "${repo_root}/plugins/shipyard/computer/skills/berth-computer/SKILL.md" "${plugin_dir}/skills/berth-computer/SKILL.md"

sha256() { shasum -a 256 "$1" | awk '{print $1}'; }
bin_sha="$(sha256 "${plugin_dir}/${command}")"
skill_sha="$(sha256 "${plugin_dir}/skills/berth-computer/SKILL.md")"

cat > "${plugin_dir}/berth-plugin.json" <<JSON
{
  "name": "Computer use",
  "version": "${version}",
  "description": "Lets agents use desktop apps through the accessibility tree (open-computer-use ${version}, ${commit}, ${os}-${arch}).",
  "mcp": {
    "computer": {
      "command": "${command}",
      "args": ["mcp"],
      "sha256": "${bin_sha}"
    }
  },
  "skills": {
    "berth-computer": {
      "path": "skills/berth-computer/SKILL.md",
      "sha256": "${skill_sha}"
    }
  }${setup_json}
}
JSON

archive="${out_dir}/computer-${version}-${os}-${arch}.tar.gz"
tar -C "${out_dir}" -czf "${archive}" computer
(cd "${out_dir}" && shasum -a 256 "$(basename "${archive}")" > "$(basename "${archive}").sha256")
echo "Plugin folder: ${plugin_dir}"
echo "Archive:       ${archive}"
echo "MCP binary sha256: ${bin_sha}"
