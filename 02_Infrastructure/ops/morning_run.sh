#!/bin/bash
# morning_run.sh — Consolidated boot-resilient morning runner (도훈 mandate 2026-06-01, 일원화 ②③)
#
# 목적: 머신이 07:10 cron 시각에 꺼져 있어도(늦게 부팅) 그날 1회 모닝 파이프라인을 실행한다.
#   - once-per-day 락: @reboot 트리거 + 정시 cron 둘 다 등록해도 하루 1회만 실행.
#   - 머신이 07:10 이후 부팅 → @reboot가 catch (정시 cron은 이미 지나 미발화) → 그래도 실행됨.
#   - 순서: paper_recharge_daily.sh (논문풀 first-run 보강) → morning_briefing.sh → mrs_daily_briefing.sh.
#   - 기존 3개 morning cron(07:10 P3 / 07:30 레짐 / 00:03 refresh)을 본 러너 하나로 통합.
#
# crontab (morning_run.sh 단일 진입):
#   @reboot      sleep 150 && bash .../02_Infrastructure/ops/morning_run.sh reboot
#   10 7 * * 1-5 bash .../02_Infrastructure/ops/morning_run.sh cron

BASE=$(ls -d /c/Users/99922/OneDrive/Quant_Module_Moltbot /mnt/c/Users/99922/OneDrive/Quant_Module_Moltbot /g/Quant_Module_Moltbot /mnt/g/Quant_Module_Moltbot /mnt/c/Users/*/OneDrive/바탕\ 화면/Quant_Module_Moltbot 2>/dev/null | head -1 || echo "$PWD")
# ★로그는 **스케줄러가 가리키는 곳**에 남긴다 (2026-08-13 수리).
#   구판은 LOG=/tmp/qm_morning_run.log 였는데, 본문 전체가 `} >> "$LOG"`(:193)로 자기 stdout 을
#   삼킨다. 그래서 Qvest_MorningBrief.bat 의 `>> .cache/scheduler_logs/morning_run.log` 에는
#   **아무것도 도달하지 않았다** — 그 파일은 2026-06-08 이후 **0바이트**(66일).
#   ★파이프라인은 정상 동작 중이었다. 죽은 건 관측이다: 다른 스케줄러 로그가 전부 모여 있는
#   자리에 빈 파일이 있으니 "돌긴 했나"를 그 자리에서 답할 수 없고, 빈 로그와 미실행이
#   구분되지 않는다(감사기 hb() 주석이 지적한 바로 그 형태). 게다가 Git Bash 의 /tmp 는
#   프로젝트 밖 휘발성 경로라 진짜 로그도 보존되지 않았다.
#   BASE 해석 실패 시에만 /tmp 로 낙하 — 그때도 어디로 갔는지 한 줄 남긴다.
if [ -n "${BASE:-}" ] && [ -d "$BASE/.cache/scheduler_logs" ]; then
  LOG="$BASE/.cache/scheduler_logs/morning_run.log"
else
  LOG="/tmp/qm_morning_run.log"
  echo "[morning_run] BASE 해석 실패 — 로그를 $LOG 로 낙하(스케줄러가 보는 자리 아님)" >&2
fi
TRIGGER="${1:-manual}"
TODAY=$(date +%Y%m%d)
LOCK="/tmp/qm_morning_run_${TODAY}.lock"
DOW=$(date +%u)   # 1=Mon .. 7=Sun

# (2026-07-26) 단계 결과를 exit 코드만으로 읽으면 안 된다.
#   하위 러너들은 fail-soft 설계라 **실패해도 exit 0** 을 반환한다(경보만 발행).
#   실사고: E2E 완주 테스트에서 체인 요약은 전부 exit=0 인데 alpha_queue 는 실제로
#   spend_limit 으로 실패해 리서치가 한 건도 안 돌았다. 요약만 보면 성공으로 읽힌다.
#   ∴ 각 단계 뒤에 그 컴포넌트가 **오늘 경보 마커를 남겼는지**를 함께 찍는다.
stage_result() {   # $1=표시명 $2=exit코드 $3=경보 컴포넌트명
  local name="$1" rc="$2" comp="${3:-}" mark="" reason=""
  if [ -n "$comp" ]; then
    mark=$(ls -1t "$BASE/.cache/scheduler_alerts/${comp}_"*"_$(date +%Y%m%d).alert" 2>/dev/null | head -1)
  fi
  # ★오케스트레이터 게이트 (2026-08-22 감사 지적): 구판은 마커가 **있는지 보고만** 했다.
  #   그래서 스테이지가 자기 경보를 안 내면 실패가 `exit=1` 한 줄로 흘러갔다 —
  #   실측 `paper_recharge exit=1` 7회 / ★경보발행 0회(그 러너의 경보 커버리지가 1/5).
  #   오케스트레이터는 exit 코드를 알고 있다. 스테이지가 기억하는지에 의존하지 않는다.
  if [ -z "$mark" ] && [ -n "$comp" ] && [ "${rc:-0}" != "0" ]; then
    local adir="$BASE/.cache/scheduler_alerts"; mkdir -p "$adir" 2>/dev/null
    local m2="$adir/${comp}_stage_exit_${rc}_$(date +%Y%m%d).alert"
    if [ ! -f "$m2" ]; then
      {
        echo "ts=$(date -Iseconds)"
        echo "component=$comp"
        echo "reason=stage_exit_${rc}"
        echo "detail=오케스트레이터(morning_run) 관측 — 스테이지 '$name' 이 exit=$rc 로 끝났는데 자기 경보를 남기지 않았습니다. 해당 러너의 경보 커버리지 결손일 수 있습니다. 확인: 그 러너의 당일 로그."
        echo "log=${LOG:-.cache/scheduler_logs/morning_run.log}"
      } > "$m2"
      mark="$m2"; reason="stage_exit_${rc}"
    fi
  fi
  if [ -n "$mark" ]; then
    [ -z "$reason" ] && reason=$(grep -oE '^reason=.*' "$mark" 2>/dev/null | cut -d= -f2-)
    echo "      $name exit=$rc  ★경보발행: ${reason:-unknown} (exit 0 이어도 실질 실패 — fail-soft)"
  else
    echo "      $name exit=$rc"
  fi
}

{
  echo "================ morning_run @ $(date) (trigger=${TRIGGER}) ================"

  # 1) 논문적재 파이프라인은 매일, 브리핑·데이터refresh는 평일만 (도훈 mandate 2026-06-19).
  #    주말엔 paper_recharge/router/tier-2/dispatch만 돌고 morning_briefing/mrs_daily는 skip.
  IS_WEEKEND=0
  [ "$DOW" -ge 6 ] && IS_WEEKEND=1
  [ "$IS_WEEKEND" = "1" ] && echo "weekend (dow=$DOW) — 논문 파이프라인만 실행, 브리핑 skip"

  # 2) once-per-day 락 (atomic). 이미 오늘 실행됐으면 skip → @reboot+cron 중복 방지
  #
  # (2026-07-26 도훈 지시 "오류 나면 재시도할 수 있게") 실사고: 15:21 첫 실행이 인증 만료로
  #   빈 통과했는데 15:24 cron 은 락 때문에 skip 됐고, 사람이 락을 지울 때까지 그날은 끝이었다.
  #   ★락은 '중복 방지'용이지 '실패 확정'용이 아니다 — 실패한 실행이 하루를 소모하면 안 된다.
  #   재시도 허용 조건(둘 중 하나):
  #     ① .done 마커 없음        = 중도 사망(크래시·kill) → 완주 안 했으므로 재시도
  #     ② 오늘 경보 마커 존재    = 어떤 단계가 실질 실패(fail-soft exit 0) → 재시도
  #   무한 재시도 방지: 하루 MAX_RETRY 회까지만 (기본 3).
  MORNING_MAX_RETRY="${MORNING_MAX_RETRY:-3}"
  if ! ( set -o noclobber; echo "$$ @ $(date) trigger=$TRIGGER" > "$LOCK" ) 2>/dev/null; then
    # ── (2026-08-22 수리) ".done 없음 = 중도 사망" 은 **직전 런이 실제로 죽었을 때만** 참이다.
    #   실사고 2026-08-21: 07:06:27 런이 paper_router(최대 50분) 안에서 살아 있는데
    #   07:10:02 cron 이 .done 부재를 사망으로 읽고 재시도해 라우터를 **2개** 띄웠다
    #   (PID 35460 @07:07:49 · 9824 @07:11:27). 둘이 같은 route JSON 을 덮어써 07:19 판
    #   (22,901B · schema route_v2 · autorun 2편 · factor_candidates 4종)이 07:31 판
    #   (16,419B)으로 사라졌고, 07:58 에 3번째 인스턴스까지 떴다.
    #   ★생존 판정에 필요한 PID 는 락 파일 **첫 필드에 이미 적혀 있었다** — 쓰고도 안 읽었다.
    #   존재 검사(.done 유무)로 정체 검사(그 런이 살아있나)를 대체한 전형적 자리.
    _lpid=$(awk '{print $1; exit}' "$LOCK" 2>/dev/null)
    case "${_lpid:-}" in
      ''|*[!0-9]*) : ;;   # PID 를 못 읽으면 구판 경로로 (보수적 — 재시도 허용)
      *)
        if kill -0 "$_lpid" 2>/dev/null; then
          echo "직전 실행(PID=$_lpid) 생존 중 — 재시도하지 않고 종료 (동시 실행 금지, 2026-08-21 실사고)"
          exit 0
        fi
        ;;
    esac
    _retry_reason=""
    [ ! -f "${LOCK}.done" ] && _retry_reason="직전 실행 미완주(.done 없음 — 중도 사망)"
    _alert_reason=""
    if [ -z "$_retry_reason" ]; then
      _alert=$(ls -1 "$BASE/.cache/scheduler_alerts/"*"_${TODAY}.alert" 2>/dev/null | head -1)
      if [ -n "$_alert" ]; then
        _alert_reason=$(grep -oE '^reason=.*' "$_alert" 2>/dev/null | cut -d= -f2-)
        _retry_reason="직전 실행에 경보 발행(${_alert_reason:-unknown})"
      fi
    fi
    # 사유별 상한 — 당일 안 풀리는 원인에 재시도를 낭비하지 않는다.
    if [ -n "$_alert_reason" ]; then
      . "$BASE/02_Infrastructure/ops/_sched_failure_classify.sh" 2>/dev/null || true
      if command -v sched_retry_cap >/dev/null 2>&1; then
        _cap=$(sched_retry_cap "$_alert_reason")
        [ -n "$_cap" ] && MORNING_MAX_RETRY="$_cap"
      fi
      # 재시도 최소 간격 — 창 롤오버 전에 다시 때리면 같은 벽에 부딪힌다.
      #   ★sleep 하지 않는다(스케줄 슬롯 점유·타임아웃 위험). 직전 시도 시각으로부터
      #     간격이 안 지났으면 이번 트리거는 넘기고 다음 트리거(@reboot/cron)가 잡게 한다.
      if command -v sched_retry_backoff_sec >/dev/null 2>&1; then
        _bo=$(sched_retry_backoff_sec "$_alert_reason")
        if [ "${_bo:-0}" -gt 0 ] 2>/dev/null; then
          _last=$(stat -c %Y "$LOCK" 2>/dev/null || echo 0)
          _since=$(( $(date +%s) - ${_last:-0} ))
          if [ "$_since" -lt "$_bo" ] 2>/dev/null; then
            echo "재시도 대기 중 — 직전 시도 ${_since}초 전, ${_alert_reason} 은 ${_bo}초 간격 필요 (다음 트리거에 재진입)"
            exit 0
          fi
        fi
      fi
    fi
    if [ -z "$_retry_reason" ]; then
      echo "already ran today ($LOCK exists, 완주·무경보) — skip"
      exit 0
    fi
    _n=$(cat "${LOCK}.retry" 2>/dev/null || echo 0)
    if [ "${_n:-0}" -ge "$MORNING_MAX_RETRY" ] 2>/dev/null; then
      echo "재시도 상한 도달 (${_n}/${MORNING_MAX_RETRY}) — skip. 사유: $_retry_reason"
      exit 0
    fi
    echo $(( _n + 1 )) > "${LOCK}.retry"
    rm -f "${LOCK}.done" 2>/dev/null
    echo "★재시도 진입 ($(( _n + 1 ))/${MORNING_MAX_RETRY}) — $_retry_reason"
  fi
  # 오래된 락 정리 (7일+)
  find /tmp -maxdepth 1 -name "qm_morning_run_*.lock" -mtime +7 -delete 2>/dev/null || true

  cd "$BASE" || { echo "BASE not found: $BASE"; exit 1; }

  echo "[0/3] paper_recharge_daily.sh (논문풀 first-run 보강)"
  if [ "${QVEST_PAPER_RECHARGE_SKIP:-0}" != "1" ] && [ -f "$BASE/02_Infrastructure/ops/paper_recharge_daily.sh" ]; then
    # ★스테이지 상한 (2026-08-22 실측): 08-22 10:36 런의 [0/3] 이 **51분 점유**했고
    #   morning_run 은 반환을 기다리다 멈췄다 — 그날 파이프라인 통과 0회, 10:39 cron 도
    #   "생존 중" 으로 종료. 실 무인 미완주 6건 중 4건이 이 지점이다.
    #   ★리서치 런의 시간제한(도훈 지시로 제거)과 **다른 층**이다: 거긴 일하는 런을
    #   자르는 문제였고, 여기는 아무 일도 안 하며 줄을 막는 문제다.
    #   상한에 걸려도 체인은 **다음 스테이지로 진행**한다(죽이지 않는다).
    #   QVEST_STAGE_TIMEOUT_MIN=0 이면 무제한(종전 동작).
    _stm="${QVEST_STAGE_TIMEOUT_MIN:-20}"
    if [ "$_stm" != "0" ] && command -v timeout >/dev/null 2>&1; then
      timeout "${_stm}m" bash "$BASE/02_Infrastructure/ops/paper_recharge_daily.sh" >> /tmp/qm_paper_recharge_morning.log 2>&1
      _prc=$?
      if [ "$_prc" -eq 124 ]; then
        echo "      ★[0/3] 스테이지 상한 ${_stm}분 초과 — 다음 스테이지로 진행(체인 보존)"
      fi
    else
      bash "$BASE/02_Infrastructure/ops/paper_recharge_daily.sh" >> /tmp/qm_paper_recharge_morning.log 2>&1
      _prc=$?
    fi
    stage_result "paper_recharge" "$_prc" "paper_recharge"
    # (v10 2026-09-02) 성공 런 뒤 해소 — 오늘 마커를 남기지 않은 성공이면 과거 미해소 마커를 _resolved/ 로 옮긴다.
    #   구판은 paper_recharge 마커를 아무도 옮기지 않아(sched_mark_resolved 호출자 = alpha_queue/recheck/modeq/router 4종만)
    #   curated_sources_missing 7건 + lock_owner_unknown 1건이 digest 에 영구 '열림' 이었다.
    #   ★오늘 마커가 있으면 옮기지 않는다 — 러너는 fail-soft exit 0 이라 방금 쓴 경보를 지우면 안 된다.
    if [ "${_prc:-1}" -eq 0 ] && ! ls "$BASE/.cache/scheduler_alerts/paper_recharge_"*"_$(date +%Y%m%d).alert" >/dev/null 2>&1; then
      . "$BASE/02_Infrastructure/ops/_sched_failure_classify.sh" 2>/dev/null || true
      if command -v sched_mark_resolved >/dev/null 2>&1; then
        _mv=$(sched_mark_resolved "paper_recharge" "$BASE/.cache/scheduler_alerts")
        [ -n "${_mv:-}" ] && echo "      paper_recharge 해소: 미해소 마커 ${_mv}건 _resolved/ 이동 (오늘 경보 0 · 성공 런)"
      fi
    fi
  else
    echo "      paper_recharge skip (disabled or missing)"
  fi

  echo "[0.5/3] paper_router_run.sh (논문 스타일 라우팅 + alpha-search 자동분기, 도훈 mandate 2026-06-18 옵션1)"
  if [ -f "$BASE/02_Infrastructure/ops/paper_router_run.sh" ]; then
    # 내부 게이트: QVEST_PAPER_ROUTER_ENABLE=1 + 당일 신규 다운로드>0 일 때만 헤드리스 claude 라우터 실행.
    bash "$BASE/02_Infrastructure/ops/paper_router_run.sh" >> /tmp/qm_paper_router.log 2>&1
    stage_result "paper_router" "$?" "paper_router"
  else
    echo "      paper_router skip (missing)"
  fi

  # ── ★v10 (2026-08-29 도훈 결정): 무인 파이프라인은 **수집(중복제거·큐 적재)까지만** ──
  #   [0.55] factor_deep_recheck / [0.56] alpha_search_queue(claude -p 자동 리서치) /
  #   [0.57] mode_queue ×2 / [0.6] paper_research_dispatch+backfill 은 **퇴역** —
  #   최초 충실구현·강화는 /qvest 세션이 주도한다(1계층 = run_paper_replication +
  #   reinforce 스킬). 블록 자체를 걷은 이유: mode_queue 는 내부 기본
  #   QVEST_MODE_QUEUE_ENABLE:-1 (ON) 이라 env 정리만으로는 되살아난다.
  #   파일은 전부 사료 존치. 재개 레시피 = git pre-v10-2layer 의 이 구간.
  echo "[0.55/3] factor_deep_recheck — 퇴역 (v10 2026-08-29: 무인은 수집까지만)"
  echo "[0.56/3] alpha_search_queue — 퇴역 (v10: 리서치는 /qvest 세션 주도)"
  echo "[0.57/3] mode_queue ×2 — 퇴역 (v10: 비-alpha 레인 폐지 — 수집은 팩터전략 단일 목적)"

  # -- [0.58/3] 팩터 근거 환류 (2026-08-22, 도훈 지시 "팩터DB 환류 부재도 같이 처리")
  #   .cache/conditional_ic_matrix.csv(327 팩터 실측)가 factor_registry 로 돌아오지 않아
  #   evidence_tier 보유 0/373 이었다. 사이드카로 비파괴 환류하고 원천이 더 새로우면 재빌드.
  #   ★무인 체인은 bootstrap 을 거치지 않는다 — 부트 표면에만 걸면 무인 경로에서 영영 안 돈다.
  echo "[0.58/3] build_factor_evidence.py (IC 실측 → 팩터 근거 사이드카, 원천 갱신 시에만)"
  if [ -f "$BASE/02_Infrastructure/factor_db/build_factor_evidence.py" ] && [ -n "${QVEST_PY:-}" ]; then
    QM_ROOT="$BASE" "$QVEST_PY" "$BASE/02_Infrastructure/factor_db/build_factor_evidence.py" --if-stale >> /tmp/qm_factor_evidence.log 2>&1
    stage_result "factor_evidence" "$?" ""
  else
    echo "      factor_evidence skip (빌더 부재 또는 QVEST_PY 미설정)"
  fi

  echo "[0.6/3] paper_research_dispatch — 퇴역 (v10 2026-08-29: 비-alpha 레인 폐지, 무인은 수집까지)"

  # (2026-07-26) 예약작업 *바깥 경계* 점검. 오늘 배선한 계측은 전부 스크립트 *안*이라
  #   "작업이 아예 안 돌았다 / OS가 죽였다"를 볼 수 없다 — 실측 당시 작업 rc를 읽는 코드 0건이었고
  #   그 상태로 InsiderBackfill이 매일 03:15경 rc=0xC000013A로 죽고 있었다.
  #   ★담체를 StrandedRepairs 하나에 두지 않는 이유: 감시기가 자기가 실린 작업의 실패는 못 본다
  #   (1단계에서 죽으면 3단계가 실행 자체를 안 함). MorningBrief(PT3H)를 2차 담체로 둔다.
  echo "[0.7/3] scheduler_task_health.sh (예약작업 rc/정체 — 스크립트 바깥 한 겹)"
  if [ -f "$BASE/02_Infrastructure/ops/scheduler_task_health.sh" ]; then
    bash "$BASE/02_Infrastructure/ops/scheduler_task_health.sh" --quiet >> /tmp/qm_task_health.log 2>&1
    stage_result "task_health" "$?" "task_health"
  else
    echo "      task_health skip (스크립트 없음)"
  fi

  # (2026-09-05 도훈 지시 — 주간 증류 무인화) 주간 클리너 스윕 직후에 증류 레인이 한 번 돌지만,
  #   그때 강화 무인 러너(ReinforceAutoLoop, ~20분 주기)가 칸을 돌고 있으면 gate 가 **연기**한다.
  #   연기가 곧 소멸이 되지 않게 일간 재시도 훅을 둔다 — 할 일이 없으면 gate 가 exit 0 으로
  #   즉시 물러나므로(claude 미호출) 매일 걸어도 비용이 0 이다.
  echo "[0.75/3] cleaner_distill_run.sh (주간 증류 무인 레인 — 미증류 주가 남아 있을 때만 발화)"
  if [ -f "$BASE/02_Infrastructure/ops/cleaner_distill_run.sh" ]; then
    bash "$BASE/02_Infrastructure/ops/cleaner_distill_run.sh" >> /tmp/qm_cleaner_distill.log 2>&1
    stage_result "cleaner_distill" "$?" "cleaner_distill"
  else
    echo "      cleaner_distill skip (스크립트 없음)"
  fi

  if [ "$IS_WEEKEND" = "1" ]; then
    echo "[1-2/3] 주말 — morning_briefing/mrs_daily(브리핑·데이터refresh·P3·regime) skip (논문 파이프라인만 매일)"
  else
    echo "[1/3] morning_briefing.sh (데이터 refresh + P3 brief)"
    bash "$BASE/02_Infrastructure/ops/morning_briefing.sh" >> /tmp/qm_morning.log 2>&1
    echo "      morning_briefing exit=$?"

    echo "[2/3] mrs_daily_briefing.sh (레짐 brief)"
    bash "$BASE/02_Infrastructure/ops/mrs_daily_briefing.sh" >> /tmp/qm_mrs_daily.log 2>&1
    echo "      mrs_daily exit=$?"
  fi

  # (2026-09-21 도훈 승인 플랜 Part 3 · D0) [3/3] 리서치 디렉터 — 프로그램 수준 진단. 측정 0 · 원장 쓰기 0 · 주말에도 돈다
  #   (데이터 refresh 가 아니라 원장·카탈로그·레지스트리를 읽는다). 산출 = .cache/rf_director_latest.json(부팅 6번째 줄이 읽음)
  #   + 06_Registry/layer_bottleneck_map.md. 실패는 stage_result 가 마커로 남긴다 — exit 0 위장 없음.
  echo "[3/3] rf_director.R (리서치 디렉터 — 진단·권고 · 측정 0)"
  mkdir -p "$BASE/.cache/scheduler_logs" 2>/dev/null
  timeout 300 Rscript "$BASE/02_Infrastructure/ops/rf_director.R" --unattended \
    >> "$BASE/.cache/scheduler_logs/rf_director_$(date +%Y%m%d).log" 2>&1
  stage_result "rf_director" "$?" "rf_director"

  echo "================ morning_run done @ $(date) ================"
} >> "$LOG" 2>&1
# (2026-07-26 probe① 도훈 승인) 완주 마커 — lock은 '시작'만 증명한다(once-per-day 선점).
# 중도 사망 시 lock만 남아 부팅이 "실행됨"으로 오보하던 갭 → done 마커로 시작/완주 구분.
date '+%H:%M:%S' > "${LOCK}.done" 2>/dev/null || true

# ── (2026-08-24 v9.2 S1e) 무인 라인 건강 — **1일 1건 집계** 텔레그램 ─────────────
#   2026-08-23: alpha_queue · mode_queue · paper_dispatch 3단계가 같은 원장 파손으로
#   동시에 죽었는데 아무도 몰랐다. 마커는 남았지만 읽는 면이 없었다.
#   ★스테이지별 N건이 아니라 **집계 1건**이다 — 같은 톤 반복은 학습된 무시를 만든다
#     (sched_failure_annotate:318-320 이 이미 그 기전을 경고한다).
#   ★sched_alert_should_send 가 QVEST_UNATTENDED=1 에서만 발송하므로 수동 실행 오경보 없음.
{
  . "$BASE/02_Infrastructure/ops/_sched_failure_classify.sh" 2>/dev/null || true
  if command -v sched_alert_emit >/dev/null 2>&1; then
    _ADIR="$BASE/.cache/scheduler_alerts"
    _TT=$(date '+%Y%m%d')
    # (v10 2026-09-02) 집계 대상 = **자체 텔레그램이 없는 마커**만. task_health·paper_router 는 sched_alert_emit/scheduler_alert 로
    #   이미 자기 경보를 보내므로 같은 사실이 하루 2번 도달했고, 같은 날 두 번째 morning_run(cron+logon)은 자기 마커
    #   unattended_line_daily_digest_* 를 1건으로 다시 셌다(today=N 부풀림).
    _TN=$(ls "$_ADIR"/*_"${_TT}".alert 2>/dev/null | grep -v -E '/(unattended_line|task_health|paper_router)_' | wc -l | tr -d ' ')
    if [ "${_TN:-0}" -gt 0 ]; then
      _TC=$(ls "$_ADIR"/*_"${_TT}".alert 2>/dev/null | grep -v -E '/(unattended_line|task_health|paper_router)_' | sed "s#.*/##; s#_${_TT}\.alert\$##" \
            | sort -u | paste -sd'; ' - 2>/dev/null)
      # reason 에 날짜를 넣어 **하루 1건**으로 스로틀한다(sched_alert_emit 은 comp+reason 1일 1회).
      sched_alert_emit "unattended_line" "daily_digest_${_TT}" \
        "오늘 무인 라인에서 ${_TN}건의 경보가 발생했습니다. 구성요소: ${_TC:-?}. 상세 = .cache/alerts_digest.md (부팅 5번째 줄에도 표시). 개별 경보를 반복 발송하지 않고 하루 1건으로 집계합니다."
    fi
  fi
} >> "$LOG" 2>&1

# (v9 2026-08-23) 경보 digest 갱신 — 부팅에서 걷어낸 전수 점검의 소비면. 기록만(수리 아님).
#   ★집계 텔레그램 **뒤**에 둔다: digest 는 오늘 마커를 세어 헤더에 today=N 을 쓰므로
#     순서가 바뀌어도 값은 같지만, 발송 실패가 digest 갱신을 막지 않게 분리해 둔다.
bash "$BASE/02_Infrastructure/ops/alerts_digest_build.sh" >/dev/null 2>&1 || true
