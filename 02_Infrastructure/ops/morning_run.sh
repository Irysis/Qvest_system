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
  if [ -n "$mark" ]; then
    reason=$(grep -oE '^reason=.*' "$mark" 2>/dev/null | cut -d= -f2-)
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
    bash "$BASE/02_Infrastructure/ops/paper_recharge_daily.sh" >> /tmp/qm_paper_recharge_morning.log 2>&1
    stage_result "paper_recharge" "$?" "paper_recharge"
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

  echo "[0.55/3] factor_deep_recheck_run.sh (2축 tier-2: tier-1 uncertain 더미 심층 재검 → testable 승격, 도훈 mandate 2026-06-19)"
  if [ "${QVEST_FACTOR_RECHECK_ENABLE:-0}" = "1" ] && [ -f "$BASE/02_Infrastructure/ops/factor_deep_recheck_run.sh" ]; then
    bash "$BASE/02_Infrastructure/ops/factor_deep_recheck_run.sh" >> /tmp/qm_factor_recheck.log 2>&1
    stage_result "factor_recheck" "$?" "factor_recheck"
  else
    echo "      factor_recheck skip (QVEST_FACTOR_RECHECK_ENABLE!=1 or missing)"
  fi

  echo "[0.56/3] alpha_search_queue_run.sh (팩터추출 → alpha-search 모드 가동: 큐 testable 자동 백테 + 5층 게이트, 도훈 mandate 2026-06-19)"
  if [ "${QVEST_ALPHA_QUEUE_ENABLE:-0}" = "1" ] && [ -f "$BASE/02_Infrastructure/ops/alpha_search_queue_run.sh" ]; then
    bash "$BASE/02_Infrastructure/ops/alpha_search_queue_run.sh" >> /tmp/qm_alpha_queue.log 2>&1
    stage_result "alpha_queue" "$?" "alpha_queue"
  else
    echo "      alpha_queue skip (QVEST_ALPHA_QUEUE_ENABLE!=1 or missing)"
  fi

  echo "[0.6/3] paper_research_dispatch.R (라우터 큐 → 리서치 액션: optimizer Σ-A/B 자동 + risk/regime flag, 도훈 mandate 2026-06-18)"
  if [ "${QVEST_PAPER_DISPATCH_ENABLE:-0}" = "1" ] && [ -f "$BASE/02_Infrastructure/ops/paper_research_dispatch.R" ]; then
    # (2026-08-08) LC_ALL 고정 — cron 은 C 로케일로 들어와 R 이 스크립트의 UTF-8 한글 리터럴을
    #   **파싱 시점에** 망가뜨린다(실측: LC_ALL=C 에서 "가중 레버 아님" → "j0", 저장된
    #   research_status_*.json 의 verdict 와 정확히 일치). ★출력단 UTF-8 쓰기로는 못 고친다 —
    #   손상이 parse 에서 끝나 enc2utf8 이 복구할 게 없다(양쪽 arm 실측 확인). 1252 로케일은
    #   반대로 바이너리 UTF-8 쓰기를 깨므로 로케일 고정이 유일 정답.
    #   문자열은 paper_router_run.sh:85 선례와 동일( 'C.UTF-8' 은 이 Windows R 에서 C 로 폴백 — 사용 금지).
    OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 ARROW_NUM_THREADS=1 R_DATATABLE_NUM_THREADS=1 \
      LC_ALL='English_United States.utf8' \
      Rscript "$BASE/02_Infrastructure/ops/paper_research_dispatch.R" >> /tmp/qm_paper_dispatch.log 2>&1
    stage_result "paper_dispatch" "$?" "paper_dispatch"
    # (2026-08-13) 백로그 소급 — 위 호출은 **오늘 큐**만 본다. 소비자가 생산자(라우터)보다 먼저
    #   도는 날이 있고(08-13 실측: dispatch 06:47 → 라우터 큐 07:02), 그날 안에 뒤 틱이 없으면
    #   그 큐는 영구 미소비로 남는다(06-19 25편 · 07-05 18편 실측). 라우터는 07-10 에 7일 백로그
    #   스캔을 받았는데 **소비자에는 안 들어가 있었다** — 그 비대칭을 여기서 닫는다.
    #   창 밖 날짜는 실행하지 않되 목록으로 찍힌다(무음 절단 금지). 전 기간 드레인은 수동 --all.
    if [ -f "$BASE/02_Infrastructure/ops/paper_dispatch_backfill.sh" ]; then
      bash "$BASE/02_Infrastructure/ops/paper_dispatch_backfill.sh" >> /tmp/qm_paper_dispatch.log 2>&1
      stage_result "paper_dispatch_backfill" "$?" "paper_dispatch_backfill"
    fi
  else
    echo "      paper_dispatch skip (QVEST_PAPER_DISPATCH_ENABLE!=1 or missing)"
  fi

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

  echo "================ morning_run done @ $(date) ================"
} >> "$LOG" 2>&1
# (2026-07-26 probe① 도훈 승인) 완주 마커 — lock은 '시작'만 증명한다(once-per-day 선점).
# 중도 사망 시 lock만 남아 부팅이 "실행됨"으로 오보하던 갭 → done 마커로 시작/완주 구분.
date '+%H:%M:%S' > "${LOCK}.done" 2>/dev/null || true
