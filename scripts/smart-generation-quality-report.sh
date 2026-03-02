#!/usr/bin/env bash
set -euo pipefail

python3 scripts/smart_generation_quality_report.py \
  --manifest private-docs/benchmarks/smart-generation/scenario-corpus.json \
  --gates private-docs/benchmarks/smart-generation/quality-gates.json \
  "$@"
