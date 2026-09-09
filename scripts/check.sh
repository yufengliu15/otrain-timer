#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift format lint --strict --recursive Sources Tests Package.swift scripts/generate-icon.swift
bash -n scripts/build-app.sh scripts/build-dmg.sh scripts/check.sh
swift build
swift test
