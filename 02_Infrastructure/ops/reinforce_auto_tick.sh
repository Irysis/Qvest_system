#!/usr/bin/env bash
# reinforce_auto_tick.sh — 강화 무인 러너 스케줄 진입점 (2026-08-30)
#   스케줄러가 이 파일만 부른다. 러너 자체는 kill switch·claim·daily_cap 을 스스로 본다.
#   1 tick = 1 칸(백테스트 ~15분). daily_cap 이 하루 총량을 막는다.
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
  # ★충실구현 대기가 있으면 먼저 처리한다 — active entry 없이는 강화가 못 돈다.
  #   자체 claim/게이트를 갖고 있어 대기가 없으면 즉시 종료한다.
  bash "$ROOT/02_Infrastructure/ops/rf_replication_auto.sh"
  # ★arm 생성 레인 (v10.2) — 기전 지도가 미측정 칸을 지목할 때만 발화한다.
  #   자체 claim·일 상한(1건)·포화 게이트를 갖고 있어 조건이 없으면 즉시 종료한다.
  bash "$ROOT/02_Infrastructure/ops/rf_overlay_propose.sh"
  # ★B1 설계 레인 (2026-09-04) — 활성 entry 의 B1 이 아직 안 열렸을 때만 1회 발화한다.
  #   자체 claim·게이트·검증을 갖고 있어 조건이 없으면 즉시 종료한다. 실패하면 러너가
  #   규칙 선정으로 돌므로 루프가 서지 않는다.
  bash "$ROOT/02_Infrastructure/ops/rf_b1_design.sh"
  # ★러너 단일화 (2026-09-05 도훈 지시 "분기 제거 — parallel 로 단일화").
  #   구판은 config 의 mode 로 두 러너를 갈랐다. 그런데 v10.4 의 핵심 3종
  #   (B1 LLM 설계 · 블록 전이 설계 · entry 예산 상향 = 25 + max(0, B1칸 − 5))이
  #   parallel 러너에만 들어갔고 순차 러너에는 **같은 도훈 지시를 인용한 주석만** 남았다.
  #   회귀 가드 8종이 두 러너를 문자열로 대조하고 있었는데도 못 막았다 — 그 가드들은
  #   "구판이 남았나"는 보지만 "신판이 안 왔나"는 안 본다. config 가 한 글자 바뀌면
  #   예산 25 고정 · 설계 없는 레인으로 조용히 내려앉는 구조라 분기 자체를 없앤다.
  #   순차 실행이 필요하면 reinforce_auto_config.json::parallel_cells 를 1 로 둔다.
  # ★강화 셀 등재 잠금 해제 (도훈 결정 2026-09-07). 2026-09-07 오전에 판정률 93% 를 이유로
  #   QVEST_RP_REGISTER=0 을 걸었었는데, 그 판단이 층을 섞었다: **방어형 라벨은 사실 기록**이고
  #   (벤치 하락월에 초과수익이 양수이며 유의했다) 배합에서 몇 개를 쓸지는 배분기가 정한다.
  #   카탈로그가 큰 것 자체는 결함이 아니다 — 실측으로 대표 12건이 전량 82건과 상관 0.989 였으니
  #   고르는 것이 가능하다. 재료를 안 쌓는 방식으로 배합 문제를 푸는 것은 해결이 아니라 은폐다.
  #   남은 실제 과제는 배분기 하이퍼 재캘리브(5~10 모듈 기준 · 풀 91에서 희석 예고)이고,
  #   그건 2계층을 처음 돌릴 때 풀 크기를 보고 정한다.
  Rscript "$ROOT/02_Infrastructure/ops/reinforce_auto_parallel.R"
  echo "=== $(date -Iseconds) tick 종료 rc=$? ==="
} >> "$LOG" 2>&1
