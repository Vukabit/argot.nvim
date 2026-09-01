#!/bin/sh
# One source of truth for gloss's version markers.
#
#   scripts/version.sh check        verify every marker agrees (CI gate)
#   scripts/version.sh set <x.y.z>  bump every marker at once
#
# Markers: M.version in lua/gloss/init.lua, the doc/gloss.txt header line,
# and the newest CHANGELOG.md section heading. The latest git tag is
# compared informationally: it may lag mid-cycle, but must equal v<version>
# when a release is cut.

set -eu
cd "$(dirname "$0")/.."

lua_v=$(grep -o 'M.version = "[0-9.]*"' lua/gloss/init.lua | grep -o '[0-9][0-9.]*')
doc_v=$(grep -o '^gloss\.nvim [0-9.]*' doc/gloss.txt | awk '{print $2}')
log_v=$(grep -m1 '^## [0-9]' CHANGELOG.md | awk '{print $2}')

case "${1:-check}" in
check)
  status=0
  [ "$lua_v" = "$doc_v" ] || { echo "version mismatch: init.lua=$lua_v doc/gloss.txt=$doc_v"; status=1; }
  [ "$lua_v" = "$log_v" ] || { echo "version mismatch: init.lua=$lua_v CHANGELOG.md=$log_v"; status=1; }
  tag=$(git describe --tags --abbrev=0 2>/dev/null || true)
  if [ -n "$tag" ] && [ "$tag" != "v$lua_v" ]; then
    echo "note: latest tag is $tag, working version is v$lua_v (fine mid-cycle; must match at release)"
  fi
  [ "$status" -eq 0 ] && echo "version markers agree: $lua_v"
  exit "$status"
  ;;
set)
  new="${2:?usage: scripts/version.sh set <x.y.z>}"
  perl -pi -e "s/M\\.version = \"[0-9.]+\"/M.version = \"$new\"/" lua/gloss/init.lua
  perl -pi -e "s/^gloss\\.nvim [0-9.]+/gloss.nvim $new/" doc/gloss.txt
  if ! grep -q "^## $new" CHANGELOG.md; then
    tmp=$(mktemp)
    { head -1 CHANGELOG.md; printf '\n## %s (unreleased)\n' "$new"; tail -n +2 CHANGELOG.md; } > "$tmp"
    mv "$tmp" CHANGELOG.md
    echo "CHANGELOG.md: added '## $new (unreleased)' section stub"
  fi
  echo "version markers set to $new"
  ;;
*)
  echo "usage: scripts/version.sh check | scripts/version.sh set <x.y.z>"
  exit 2
  ;;
esac
