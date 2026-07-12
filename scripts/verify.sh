#!/usr/bin/env bash
set -euo pipefail

: "${DEVECO_SDK_HOME:=/Applications/DevEco-Studio.app/Contents/sdk}"
: "${JAVA_HOME:=/Applications/DevEco-Studio.app/Contents/jbr/Contents/Home}"
export DEVECO_SDK_HOME JAVA_HOME
export PATH="$JAVA_HOME/bin:$PATH"

HVIGOR="${HVIGOR:-/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw}"
OHPM="${OHPM:-/Applications/DevEco-Studio.app/Contents/tools/ohpm/bin/ohpm}"

"$OHPM" install
"$HVIGOR" --stop-daemon || true
"$HVIGOR" --mode module -p module=entry@default -p product=default test --analyze=normal
"$HVIGOR" --mode module -p module=entry@default -p product=default assembleHap --analyze=normal
