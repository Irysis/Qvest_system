#!/usr/bin/env bash
# reinforce_auto_tick.sh — 1계층·2계층 무인 레인 스케줄 진입점 (2026-08-30 · ★v10.01 2026-10-13 재편)
#   스케줄러(Qvest_ReinforceAutoLoop)가 이 파일만 부른다 — 경로를 유지해 예약작업을 고치지 않아도 되게 했다.
#   ★v10.01: 고정 격자 강화 러너(reinforce_auto_parallel.R)와 블록 설계 레인(B1 · B5 · arm 생성)은 퇴역했다.
#   남는 것 = 충실구현 레인(rf_replication_auto.sh · 자기 스위치 replication_lane.enabled) + 2계층 레인(rf_l2_auto.sh · l2_auto.enabled).
set -uo pipefail
ROOT="${QM_ROOT:-C:/Users/99922/OneDrive/Quant_Module_Moltbot}"
cd "$ROOT" || exit 1
TODAY=$(date +%Y%m%d)
LOG="$ROOT/.cache/scheduler_logs/reinforce_auto_${TODAY}.log"
mkdir -p "$(dirname "$LOG")"
{
  echo "=== $(date -Iseconds) tick 시작 ==="
  # ★주간 증류 레인과의 역방향 충돌 차단 (2026-09-05 도훈 '운용상 충돌없게').
  #   증류 게이트는 "강화 중이면 증류를 연기" 하는데, 그 반대(증류 중 강화 착수)는 안 막혀 있었다.
  #   둘 다 L-code 원장과 distilled_knowledge.json 을 읽고 쓴다 — 겹치면 lost update 다.
  #   증류 claim(distill_status=in_progress · owner=auto_distill)이 **신선할 때만** 물러난다:
  #   레인이 죽은 채 claim 을 쥐고 있으면 강화가 stale 6h 까지 서 버리므로 1h 로 끊는다
  #   (그 뒤는 증류 쪽 stale 재점유 규약이 처리한다). 주 1회 · 20분짜리라 tick 1~2회 손실이 전부다.
  CDP="$ROOT/.cache/cleaner_pending.json"
  if [ -f "$CDP" ] && grep -q '"distill_status"[[:space:]]*:[[:space:]]*"in_progress"' "$CDP" 2>/dev/null; then
    CDO=$(grep -oE '"distill_owner"[[:space:]]*:[[:space:]]*"[^"]*"' "$CDP" | head -1 | sed -E 's/.*:[[:space:]]*"([^"]*)"/\1/')
    CDA=$(grep -oE '"distill_claimed_at"[[:space:]]*:[[:space:]]*"[^"]*"' "$CDP" | head -1 | sed -E 's/.*:[[:space:]]*"([^"]*)"/\1/')
    CDS=""; [ -n "$CDA" ] && CDS=$(date -d "$CDA" +%s 2>/dev/null || echo "")
    if [ "$CDO" = "auto_distill" ] && [ -n "$CDS" ] && [ $(( $(date +%s) - CDS )) -lt 3600 ]; then
      echo "[rf_tick] halt_distill_active — 무인 증류 레인 진행 중(claimed_at=$CDA). 원장 동시쓰기 회피로 이번 tick 물러남"
      echo "=== $(date -Iseconds) tick 종료 rc=0 (distill 양보) ==="
      exit 0
    fi
  fi
  # ★리프레시 배리어 — 틱 수준 1차 (도훈 결정 OPS-RUNNER-REFRESH-BARRIER · 2026-09-24).
  #   daily_refresh 가 잠금을 쥔 동안([0b] 퀀티 증분 ~ [3/7] 유니버스 매핑 사이 RAWDATA K200/KQ150 NA 창 포함) 또는
  #   아침 RAWDATA writer(krx_update·naver_supplement·self_heal) 잠금이 살아 있는 동안 **틱 전체**를 건너뛴다.
  #   아래 어떤 레인도 부르기 전(사전 등록 전)이라 시도 예산을 안 태운다. 판정 정본 = refresh_barrier.sh
  #   (stale = 대기 안 함 + 로그 · 보유자 자손 = 진행 · 판정기 부재 = fail-closed · 잠금 없음 = 아무것도 안 한다).
  #   판정기는 이 파일 옆에서 먼저 찾는다 — QM_ROOT 가 샌드박스(검사)여도 코드 정본을 쓴다.
  RB_SH="$(dirname "${BASH_SOURCE[0]:-$0}")/refresh_barrier.sh"
  [ -f "$RB_SH" ] || RB_SH="$ROOT/02_Infrastructure/ops/refresh_barrier.sh"
  RB_JLOG="$ROOT/.cache/reinforce_auto_log.jsonl"
  if [ -f "$RB_SH" ] && . "$RB_SH"; then
    rb_status
    case "$RB_STATE" in
      held)
        rb_jlog "$RB_JLOG" halt_refresh_lock tick
        echo "[rf_tick] halt_refresh_lock — $(rb_line)"
        echo "=== $(date -Iseconds) tick 종료 rc=0 (리프레시 배리어 양보) ==="
        exit 0 ;;
      stale)
        rb_jlog "$RB_JLOG" refresh_lock_stale tick "note=보유자 없음 — 대기하지 않고 진행"
        echo "[rf_tick] refresh_lock_stale — $(rb_line)" ;;
    esac
  else
    printf '{"ts":"%s","event":"halt_refresh_lock","src":"tick","state":"error","reason":"barrier_helper_missing"}\n' "$(date +%Y-%m-%dT%H:%M:%S%z)" >> "$RB_JLOG"
    echo "[rf_tick] halt_refresh_lock — 판정기(refresh_barrier.sh) 부재 · fail-closed"
    echo "=== $(date -Iseconds) tick 종료 rc=0 (배리어 판정기 부재) ==="
    exit 0
  fi
  # ★충실구현 레인 — 대기 요청이 있으면 처리한다(자체 스위치 · claim · 게이트 · 대기가 없으면 즉시 종료).
  #   (v10.01) 구 주석 'active entry 없이는 강화가 못 돈다' 는 고정 격자 러너와 함께 퇴역 — 결과는 리서치 프로그램 재료 큐로 간다.
  bash "$ROOT/02_Infrastructure/ops/rf_replication_auto.sh"
  # (v10.01 2026-10-13) arm 생성 · B1 설계 · B5 설계 레인 호출 삭제 — 고정 격자 강화와 함께 퇴역(롤백 태그 pre-v10.01-prescription-20261013).
  # ★2계층 무인 레인 (2026-09-21 도훈 승인 플랜 Part 3 · D2) — 06_Registry/l2_unit_request.json 이 pending 이고
  #   config l2_auto.enabled + R1(selection_type) 결정이 기록됐을 때만 발화한다. 드라이버(rf_l2_auto.R)는 구 러너 claim 을
  #   그대로 쥔다(v10.01: 그 claim 을 같이 쥐던 고정 격자 러너는 퇴역 — 지금은 2계층 실행끼리의 중복 방지만 한다).
  #   레인 파일 부재/조건 미충족 = 즉시 종료. 순서 = 충실구현 → 2계층(검사 test_rf_l2_auto.sh ⑤).
  [ -f "$ROOT/02_Infrastructure/ops/rf_l2_auto.sh" ] && bash "$ROOT/02_Infrastructure/ops/rf_l2_auto.sh"
  # (v10.01 2026-10-13) 강화 러너(reinforce_auto_parallel.R) 호출 삭제 — 1계층은 리서치 프로그램(06_Registry/research_programs.json) 단위로
  #   세션이 돌린다(.claude/skills/research-program/SKILL.md). 무인 부분 = 위 두 레인 + 아침 체인의 논문 수집 · 트리아지 · 재료 동기화 · 메커니즘 지도.
  echo "=== $(date -Iseconds) tick 종료 rc=$? ==="
} >> "$LOG" 2>&1
