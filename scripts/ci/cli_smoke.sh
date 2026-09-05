#!/usr/bin/env bash
set -euo pipefail
export MACPARAKEET_TELEMETRY=0
CLI="${1:?Usage: cli_smoke.sh PATH_TO_CLI}"
mkdir -p .ci-logs
"$CLI" --help > .ci-logs/cli-help.txt
"$CLI" spec --json > .ci-logs/cli-spec.json
python3 - <<'PY'
import json
from pathlib import Path
spec = json.loads(Path('.ci-logs/cli-spec.json').read_text())
commands = {tuple(command['path']): command for command in spec['commands']}
mode = commands[('meetings', 'export')]['jsonMode']
if mode != '--stdout --format json':
    raise SystemExit(f'Unexpected meetings export jsonMode: {mode!r}')
PY
