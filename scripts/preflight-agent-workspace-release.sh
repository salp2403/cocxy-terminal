#!/usr/bin/env bash
set -euo pipefail

# Read-only preflight for the Agent Workspace OS v1.18.0 release target.
#
# This does not bump versions, build artifacts, tag, publish, notarize, deploy,
# or call external services. It only records whether local release-target
# evidence already exists for the private Agent Workspace OS plan.

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_VERSION="${COCXY_AGENT_WORKSPACE_RELEASE_VERSION:-1.18.0}"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
ARTIFACT_ROOT="${COCXY_AGENT_WORKSPACE_RELEASE_PREFLIGHT_ARTIFACTS:-${PROJECT_ROOT}/build/agent-workspace-release-preflight/${TIMESTAMP}}"
SUMMARY="${ARTIFACT_ROOT}/summary.tsv"
APP_BUNDLE="${COCXY_AGENT_WORKSPACE_RELEASE_APP:-${PROJECT_ROOT}/build/CocxyTerminal.app}"
DMG_PATH="${COCXY_AGENT_WORKSPACE_RELEASE_DMG:-${PROJECT_ROOT}/build/CocxyTerminal-${TARGET_VERSION}.dmg}"
APPCAST_PATH="${COCXY_AGENT_WORKSPACE_RELEASE_APPCAST:-${PROJECT_ROOT}/build/appcast.xml}"
CELLS_CLOUD_PREFLIGHT_ROOT="${COCXY_CELLS_CLOUD_PREFLIGHT_ROOT:-${PROJECT_ROOT}/build/cells-cloud-preflight}"

usage() {
  cat <<'USAGE'
usage: scripts/preflight-agent-workspace-release.sh

Environment overrides:
  COCXY_AGENT_WORKSPACE_RELEASE_VERSION=1.18.0
  COCXY_AGENT_WORKSPACE_RELEASE_APP=build/CocxyTerminal.app
  COCXY_AGENT_WORKSPACE_RELEASE_DMG=build/CocxyTerminal-1.18.0.dmg
  COCXY_AGENT_WORKSPACE_RELEASE_APPCAST=build/appcast.xml
  COCXY_CELLS_CLOUD_PREFLIGHT_ROOT=build/cells-cloud-preflight

This is read-only. It never bumps versions, tags, publishes, notarizes, deploys,
or calls external services. It verifies local artifacts only.
USAGE
}

plist_value() {
  local plist="$1"
  local key="$2"
  if [ -f "$plist" ] && [ -x /usr/libexec/PlistBuddy ]; then
    /usr/libexec/PlistBuddy -c "Print :${key}" "$plist" 2>/dev/null || true
  fi
}

emit() {
  local requirement="$1"
  local status="$2"
  local evidence="$3"
  local detail="$4"
  printf '%s\t%s\t%s\t%s\n' "$requirement" "$status" "$evidence" "$detail" >> "$SUMMARY"
}

require_equal() {
  local requirement="$1"
  local evidence="$2"
  local actual="$3"
  if [ "$actual" = "$TARGET_VERSION" ]; then
    emit "$requirement" "ok" "$evidence" "$actual"
  else
    emit "$requirement" "blocked" "$evidence" "expected ${TARGET_VERSION}, got ${actual:-missing}"
  fi
}

relative_path() {
  local path="$1"
  printf '%s\n' "${path#${PROJECT_ROOT}/}"
}

emit_command_check() {
  local requirement="$1"
  local evidence="$2"
  local detail_ok="$3"
  shift 3

  local log_file="${ARTIFACT_ROOT}/${requirement}.log"
  if "$@" > "$log_file" 2>&1; then
    emit "$requirement" "ok" "$evidence" "$detail_ok"
  else
    emit "$requirement" "blocked" "$evidence" "failed; see $(relative_path "$log_file")"
  fi
}

artifact_field() {
  local file="$1"
  local field="$2"
  sed -n "s/^${field}=//p" "$file" | tail -1
}

cells_cloud_provider_count() {
  local preflight="$1"
  local summary
  summary="$(dirname "$preflight")/summary.tsv"
  if [ ! -f "$summary" ]; then
    echo 0
    return 0
  fi

  awk -F '\t' 'NR > 1 { count++ } END { print count + 0 }' "$summary"
}

cells_cloud_complete_row_count() {
  local preflight="$1"
  local summary
  summary="$(dirname "$preflight")/summary.tsv"
  if [ ! -f "$summary" ]; then
    echo 0
    return 0
  fi

  awk -F '\t' 'NR > 1 && $2 == "complete" { count++ } END { print count + 0 }' "$summary"
}

latest_cells_cloud_all_preflight() {
  local directory="$CELLS_CLOUD_PREFLIGHT_ROOT"
  if [ ! -d "$directory" ]; then
    return 1
  fi

  local file
  while IFS= read -r file; do
    if [ "$(cells_cloud_provider_count "$file")" = "5" ]; then
      printf '%s\n' "$file"
      return 0
    fi
  done < <(
    find "$directory" -maxdepth 2 -type f -name preflight.txt -exec sh -c '
      for path do
        mtime="$(stat -f "%m" "$path" 2>/dev/null || stat -c "%Y" "$path" 2>/dev/null || echo 0)"
        printf "%s\t%s\n" "$mtime" "$path"
      done
    ' sh {} + 2>/dev/null |
      LC_ALL=C sort -rn |
      cut -f2-
  )

  return 1
}

emit_cells_cloud_account_readiness() {
  local preflight
  local expected="expected provider-count=5 complete=5 blocked=0 before v${TARGET_VERSION} release target"
  preflight="$(latest_cells_cloud_all_preflight || true)"

  if [ -z "$preflight" ]; then
    emit "cells-cloud-account-readiness" "blocked" "-" "$expected"
    return 0
  fi

  local status
  local blocked
  local complete
  local provider_count
  local complete_rows
  status="$(artifact_field "$preflight" status)"
  blocked="$(artifact_field "$preflight" blocked)"
  complete="$(artifact_field "$preflight" complete)"
  provider_count="$(cells_cloud_provider_count "$preflight")"
  complete_rows="$(cells_cloud_complete_row_count "$preflight")"

  if [ "$status" = "complete" ] &&
     [ "$provider_count" = "5" ] &&
     [ "$complete" = "5" ] &&
     [ "$blocked" = "0" ] &&
     [ "$complete_rows" = "5" ]; then
    emit "cells-cloud-account-readiness" "ok" "$(relative_path "$preflight")" "provider-count=5 complete=5 blocked=0"
    return 0
  fi

  emit "cells-cloud-account-readiness" "blocked" "$(relative_path "$preflight")" \
    "${expected}; got status=${status:-missing} provider-count=${provider_count} complete=${complete:-missing} blocked=${blocked:-missing} complete-rows=${complete_rows}"
}

case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
  "")
    ;;
  *)
    usage
    exit 2
    ;;
esac

mkdir -p "$ARTIFACT_ROOT"
printf 'requirement\tstatus\tevidence\tdetail\n' > "$SUMMARY"

resource_version="$(plist_value "${PROJECT_ROOT}/Resources/Info.plist" "CFBundleShortVersionString")"
require_equal "resources-info-version" "Resources/Info.plist" "$resource_version"

fallback_version="$(
  sed -n 's/.*fallbackVersion = "\([^"]*\)".*/\1/p' \
    "${PROJECT_ROOT}/CLI/Lib/ArgumentParser.swift" | head -1
)"
require_equal "cli-fallback-version" "CLI/Lib/ArgumentParser.swift" "$fallback_version"

if [ -d "$APP_BUNDLE" ]; then
  bundle_version="$(plist_value "${APP_BUNDLE}/Contents/Info.plist" "CFBundleShortVersionString")"
  require_equal "bundle-info-version" "${APP_BUNDLE#${PROJECT_ROOT}/}/Contents/Info.plist" "$bundle_version"

  if [ -x "${PROJECT_ROOT}/scripts/verify-app-bundle.sh" ]; then
    emit_command_check \
      "bundle-contents-verification" \
      "$(relative_path "$APP_BUNDLE")" \
      "scripts/verify-app-bundle.sh passed" \
      "${PROJECT_ROOT}/scripts/verify-app-bundle.sh" "$APP_BUNDLE"
  else
    emit "bundle-contents-verification" "blocked" "scripts/verify-app-bundle.sh" "missing or not executable"
  fi

  if command -v codesign >/dev/null 2>&1; then
    emit_command_check \
      "bundle-codesign-verification" \
      "$(relative_path "$APP_BUNDLE")" \
      "codesign --verify --deep --strict passed" \
      codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
  else
    emit "bundle-codesign-verification" "blocked" "$(relative_path "$APP_BUNDLE")" "codesign not found"
  fi
else
  emit "bundle-info-version" "blocked" "${APP_BUNDLE#${PROJECT_ROOT}/}" "app bundle missing"
  emit "bundle-contents-verification" "blocked" "${APP_BUNDLE#${PROJECT_ROOT}/}" "app bundle missing"
  emit "bundle-codesign-verification" "blocked" "${APP_BUNDLE#${PROJECT_ROOT}/}" "app bundle missing"
fi

if [ -x "${APP_BUNDLE}/Contents/Resources/cocxy" ]; then
  cli_version="$("${APP_BUNDLE}/Contents/Resources/cocxy" --version 2>/dev/null | awk '{print $2}' | head -1)"
  require_equal "bundle-cli-version" "${APP_BUNDLE#${PROJECT_ROOT}/}/Contents/Resources/cocxy" "$cli_version"
else
  emit "bundle-cli-version" "blocked" "${APP_BUNDLE#${PROJECT_ROOT}/}/Contents/Resources/cocxy" "bundle-local CLI missing or not executable"
fi

emit_cells_cloud_account_readiness

if [ -f "$DMG_PATH" ]; then
  emit "dmg-artifact" "ok" "${DMG_PATH#${PROJECT_ROOT}/}" "present"
  if command -v hdiutil >/dev/null 2>&1; then
    emit_command_check \
      "dmg-image-verification" \
      "$(relative_path "$DMG_PATH")" \
      "hdiutil imageinfo passed" \
      hdiutil imageinfo "$DMG_PATH"
  else
    emit "dmg-image-verification" "blocked" "$(relative_path "$DMG_PATH")" "hdiutil not found"
  fi

  if command -v codesign >/dev/null 2>&1; then
    emit_command_check \
      "dmg-codesign-verification" \
      "$(relative_path "$DMG_PATH")" \
      "codesign --verify --strict passed" \
      codesign --verify --strict --verbose=2 "$DMG_PATH"
  else
    emit "dmg-codesign-verification" "blocked" "$(relative_path "$DMG_PATH")" "codesign not found"
  fi
else
  emit "dmg-artifact" "blocked" "${DMG_PATH#${PROJECT_ROOT}/}" "missing"
  emit "dmg-image-verification" "blocked" "${DMG_PATH#${PROJECT_ROOT}/}" "missing"
  emit "dmg-codesign-verification" "blocked" "${DMG_PATH#${PROJECT_ROOT}/}" "missing"
fi

if [ -f "$APPCAST_PATH" ]; then
  dmg_basename="$(basename "$DMG_PATH")"
  if grep -q "sparkle:shortVersionString=\"${TARGET_VERSION}\"" "$APPCAST_PATH"; then
    emit "appcast-version" "ok" "${APPCAST_PATH#${PROJECT_ROOT}/}" "$TARGET_VERSION"
  else
    appcast_version="$(sed -n 's/.*sparkle:shortVersionString="\([^"]*\)".*/\1/p' "$APPCAST_PATH" | head -1)"
    emit "appcast-version" "blocked" "${APPCAST_PATH#${PROJECT_ROOT}/}" "expected ${TARGET_VERSION}, got ${appcast_version:-missing}"
  fi
  if grep -q "$dmg_basename" "$APPCAST_PATH"; then
    emit "appcast-dmg-reference" "ok" "${APPCAST_PATH#${PROJECT_ROOT}/}" "$dmg_basename"
  else
    emit "appcast-dmg-reference" "blocked" "${APPCAST_PATH#${PROJECT_ROOT}/}" "missing ${dmg_basename}"
  fi
  if grep -Eq 'sparkle:edSignature="[^"]+"' "$APPCAST_PATH"; then
    emit "appcast-sparkle-signature" "ok" "${APPCAST_PATH#${PROJECT_ROOT}/}" "present"
  else
    emit "appcast-sparkle-signature" "blocked" "${APPCAST_PATH#${PROJECT_ROOT}/}" "missing sparkle:edSignature"
  fi
  if grep -Eq 'length="[0-9]+"' "$APPCAST_PATH"; then
    emit "appcast-enclosure-length" "ok" "${APPCAST_PATH#${PROJECT_ROOT}/}" "present"
  else
    emit "appcast-enclosure-length" "blocked" "${APPCAST_PATH#${PROJECT_ROOT}/}" "missing enclosure length"
  fi
else
  emit "appcast-version" "blocked" "${APPCAST_PATH#${PROJECT_ROOT}/}" "missing"
  emit "appcast-dmg-reference" "blocked" "${APPCAST_PATH#${PROJECT_ROOT}/}" "missing"
  emit "appcast-sparkle-signature" "blocked" "${APPCAST_PATH#${PROJECT_ROOT}/}" "missing"
  emit "appcast-enclosure-length" "blocked" "${APPCAST_PATH#${PROJECT_ROOT}/}" "missing"
fi

if [ -f "${PROJECT_ROOT}/CHANGELOG.md" ]; then
  if grep -Eq "^## \\[?v?${TARGET_VERSION}\\]?" "${PROJECT_ROOT}/CHANGELOG.md"; then
    emit "changelog-version" "ok" "CHANGELOG.md" "$TARGET_VERSION"
  else
    emit "changelog-version" "blocked" "CHANGELOG.md" "missing ${TARGET_VERSION} release entry"
  fi
else
  emit "changelog-version" "blocked" "CHANGELOG.md" "missing"
fi

if git -C "$PROJECT_ROOT" show-ref --tags --verify --quiet "refs/tags/v${TARGET_VERSION}"; then
  emit "local-release-tag" "ok" "refs/tags/v${TARGET_VERSION}" "present"
else
  emit "local-release-tag" "blocked" "refs/tags/v${TARGET_VERSION}" "missing"
fi

blocked_count="$(awk -F '\t' 'NR > 1 && $2 == "blocked" { count++ } END { print count + 0 }' "$SUMMARY")"

{
  if [ "$blocked_count" -eq 0 ]; then
    echo "status=ok"
  else
    echo "status=blocked"
  fi
  echo "targetVersion=${TARGET_VERSION}"
  echo "artifactRoot=${ARTIFACT_ROOT}"
  echo "summary=${SUMMARY}"
  echo "blocked=${blocked_count}"
  echo "next=complete local v${TARGET_VERSION} release-target evidence or keep plan marked not complete"
} | tee "${ARTIFACT_ROOT}/preflight.txt"

cat "$SUMMARY"

if [ "$blocked_count" -eq 0 ]; then
  exit 0
fi
exit 1
