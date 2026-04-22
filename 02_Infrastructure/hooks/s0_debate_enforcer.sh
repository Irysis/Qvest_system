#!/usr/bin/env bash
# s0_debate_enforcer.sh — Phase C3.5 shim
# 기존 settings.json 등록 경로 호환. 실제 로직은 s0_enforcer/s0_enforcer.sh로 분리됨.
# 원본 v46 (980L)은 02_Infrastructure/hooks/_archive_4_6/s0_debate_enforcer.sh.v46 보존.

trap 'echo "{}"; exit 0' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
exec bash "$SCRIPT_DIR/s0_enforcer/s0_enforcer.sh"
