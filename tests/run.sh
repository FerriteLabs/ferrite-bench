#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

python3 -m unittest discover -s tests -p 'test_*.py'

for test_script in tests/test_*.sh; do
    [[ -e "$test_script" ]] || continue
    bash "$test_script"
done
