#!/bin/bash

set -e

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

if [ ! -f "./Vector-06C.qpf" ]
then
    echo "What the hell is this directory?"
    exit 1
fi

rm -rf ./db ./incremental_db/

[ -d ./fw ] && make -C fw clean
