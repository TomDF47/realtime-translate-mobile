#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT_DIR"

status=0

echo "Checking Markdown local links..."
while IFS='|' read -r file raw_target; do
  [[ -z "${file:-}" || -z "${raw_target:-}" ]] && continue

  case "$raw_target" in
    http://*|https://*|mailto:*|tel:*|"#"*|"")
      continue
      ;;
  esac

  target="${raw_target%%#*}"
  target="${target#<}"
  target="${target%>}"
  [[ -z "$target" ]] && continue

  if [[ "$target" == /* ]]; then
    path=".$target"
  else
    path="$(dirname "$file")/$target"
  fi

  if [[ ! -e "$path" ]]; then
    echo "Missing link target: $file -> $raw_target"
    status=1
  fi
done < <(
  find . \
    -path ./.git -prune -o \
    -path ./build -prune -o \
    -name '*.md' -type f -print0 |
  xargs -0 perl -ne 'while (/\[[^\]]+\]\(([^)]+)\)/g) { print "$ARGV|$1\n" }'
)

echo "Checking for likely committed OpenAI secret patterns..."
secret_hits="$(
  find . \
    -path ./.git -prune -o \
    -path ./build -prune -o \
    -path ./assets/mockups -prune -o \
    -type f -print0 |
  xargs -0 perl -ne 'while (/(sk-[A-Za-z0-9_-]{20,}|sess-[A-Za-z0-9_-]{20,}|ek_[A-Za-z0-9_-]{20,})/g) { print "$ARGV:$.:$1\n" }'
)"

if [[ -n "$secret_hits" ]]; then
  echo "$secret_hits"
  echo "Potential secret-like token found. Replace real secrets with placeholders."
  status=1
fi

if [[ "$status" -ne 0 ]]; then
  exit "$status"
fi

echo "Docs checks passed."
