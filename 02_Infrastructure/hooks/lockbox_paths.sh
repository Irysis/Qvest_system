#!/usr/bin/env bash
#==============================================================================
# lockbox_paths.sh — Lockbox audit-trail 경로 계약 (bash 측 단일 정의)
# 2026-08-02
#
# 짝 = 02_Infrastructure/worktask/lockbox_paths.R (R 측). 사유·근거는 그 파일 헤더 참조.
# 요약: `/tmp` 는 bash(MSYS)=AppData\Local\Temp, Windows R=C:/tmp 로 **다른 디렉토리**다.
#       훅이 쓰고 R 감사가 읽는 구조라 이 리터럴을 공유하면 읽는 쪽이 영원히 빈 손이 되고,
#       그 공허함이 "위반 없음"으로 읽혀 감사가 죽었다(2026-08-02 실측, P2 237/237 구조적 PASS).
#       → 프로젝트-상대 경로로 이전. 양쪽이 각자 marker 로 루트를 검증해 같은 곳에 도달한다.
#
# Usage: source "$(dirname "${BASH_SOURCE[0]:-$0}")/lockbox_paths.sh"
#        → QVEST_LOCKBOX_DIR / qvest_lockbox_log_file <wt_id> / qvest_lockbox_touch_heartbeat
#==============================================================================

# ★공유 리터럴 — lockbox_paths.R 의 QVEST_LOCKBOX_SUBDIR 과 반드시 같아야 한다.
#   (동기화는 08_Tests/hooks/test_lockbox_audit_path.R 가 강제)
QVEST_LOCKBOX_SUBDIR=".cache/lockbox"
QVEST_LOCKBOX_HEARTBEAT="_trail_heartbeat"

# 루트 해석은 hooks 판 resolve_project.sh 에 위임 (CPD → QM_ROOT → 자기위치 → glob,
# 전 tier marker 게이트). 실패해도 훅을 죽이지 않는다 — 관측성은 guard 가 아니다.
if [ -z "${PROJECT:-}" ]; then
  # shellcheck source=./resolve_project.sh
  source "$(dirname "${BASH_SOURCE[0]:-$0}")/resolve_project.sh" 2>/dev/null || true
fi

QVEST_LOCKBOX_DIR=""
if [ -n "${PROJECT:-}" ]; then
  QVEST_LOCKBOX_DIR="${PROJECT}/${QVEST_LOCKBOX_SUBDIR}"
fi

# 로그 파일 경로를 stdout 으로. 루트 미해석이면 빈 문자열 + rc 1 (호출자가 조용히 삼키지 말 것).
qvest_lockbox_log_file() {
  local _wt="${1:-unknown}"
  [ -n "$QVEST_LOCKBOX_DIR" ] || return 1
  printf '%s/qvest_lockbox_access_%s.log' "$QVEST_LOCKBOX_DIR" "$_wt"
}

# 트레일 발화 사실 기록 — "기록 0건"과 "검출기 사망"의 구별자.
# R 감사(audit_p2_data_separation)가 이 파일로 trail liveness 를 판정한다.
qvest_lockbox_touch_heartbeat() {
  [ -n "$QVEST_LOCKBOX_DIR" ] || return 1
  mkdir -p "$QVEST_LOCKBOX_DIR" 2>/dev/null || return 1
  date -Iseconds > "${QVEST_LOCKBOX_DIR}/${QVEST_LOCKBOX_HEARTBEAT}" 2>/dev/null || return 1
  return 0
}
