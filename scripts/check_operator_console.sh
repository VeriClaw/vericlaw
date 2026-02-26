#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
console_dir="${project_root}/operator-console"

required_files=(index.html styles.css app.js)
for file in "${required_files[@]}"; do
  if [[ ! -f "${console_dir}/${file}" ]]; then
    echo "Missing operator console file: ${console_dir}/${file}" >&2
    exit 1
  fi
done

bash -n "${project_root}/scripts/serve_operator_console.sh"

if command -v node >/dev/null 2>&1; then
  node --check "${console_dir}/app.js" >/dev/null
else
  echo "Skipping JavaScript syntax check: node not installed." >&2
fi

grep -q "Local-only scaffold" "${console_dir}/index.html"
echo "Operator console scaffold checks passed."
