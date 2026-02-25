#!/bin/bash
set -e

QUARTUS_DIR="${QUARTUS_DIR:-/opt/intelFPGA_lite/18.1/quartus}"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

cd "$PROJECT_DIR"
echo "Building Vector-06C with Quartus 18.1..."
"$QUARTUS_DIR/bin/quartus_sh" --flow compile Vector-06C
