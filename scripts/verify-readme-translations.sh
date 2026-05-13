#!/usr/bin/env bash
# Validate localized README freshness and terminology preservation.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
README_EN="$ROOT_DIR/README.md"
LOCALES=(
  ar bs da de es fr it ja km ko no pl pt-BR ru th tr uk vi zh-CN zh-TW
)
TERMS=(
  "terminal"
  "agent"
  "MCP"
  "CocxyCore"
  "Homebrew"
  "Swift"
  "Metal"
  "AppKit"
  "SwiftUI"
  "Zig"
  "macOS"
  "GitHub"
  "SSH"
  "SFTP"
  "tmux"
  "screen"
  "PTY"
  "GPU"
  "CLI"
  "Markdown"
  "Jupyter"
  "WebKit"
  "Foundation Models"
)

expected_hash="$(shasum -a 256 "$README_EN" | awk '{print $1}')"
failures=0

warn() {
  printf '::warning::%s\n' "$*" >&2
  failures=$((failures + 1))
}

require_contains() {
  local file="$1"
  local needle="$2"
  local context="$3"
  if ! grep -Fq "$needle" "$file"; then
    warn "$context missing '$needle' in ${file#$ROOT_DIR/}"
  fi
}

for locale in "${LOCALES[@]}"; do
  file="$ROOT_DIR/README.$locale.md"
  if [[ ! -f "$file" ]]; then
    warn "Missing localized README ${file#$ROOT_DIR/}"
    continue
  fi

  require_contains "$file" "<!-- cocxy-readme-source-sha256: $expected_hash -->" "stale source hash"
  require_contains "$file" "<!-- cocxy-readme-locale: $locale -->" "locale marker"
  require_contains "$file" "[English](README.md)" "language header"
  for other in "${LOCALES[@]}"; do
    require_contains "$file" "(README.$other.md)" "language header"
  done
  for term in "${TERMS[@]}"; do
    require_contains "$file" "$term" "technical terminology"
  done
done

if [[ "$failures" -ne 0 ]]; then
  printf 'README translation verification failed with %d issue(s).\n' "$failures" >&2
  printf 'Run scripts/translate-readme.sh after changing README.md, then review generated files.\n' >&2
  exit 1
fi

printf 'README translation verification passed for %d localized files.\n' "${#LOCALES[@]}"
