#!/bin/bash
#==============================================================================
# regime_data_refresh.sh — 매일 아침 일괄 regime 데이터 갱신 (Session 70 Step 8)
# 2026-04-24 신규
#
# Cron 등록 예시 (※ 자동 등록 금지 — 사용자 승인 필요):
#   30 6 * * * bash /mnt/c/Users/*/OneDrive/바탕\ 화면/Quant_Module_Moltbot/02_Infrastructure/ops/regime_data_refresh.sh
#
# 실행 순서:
#   1. FRED robust fetch (22 series)
#   2. MSM daily refit (benchmark → HMM)
#   3. KTRI v3 builder (breadth + volatility)
#   4. regime_signal v2 (3-layer merge: daily + monthly)
#   5. regime_healthcheck (상태 검증 + Telegram alert on fail)
#
# 각 단계는 독립 tryCatch — 하나 실패해도 나머지 진행. 최종 healthcheck 에서 종합 alert.
#
# 금지:
#   - 기존 regime 모듈 수정 금지
#   - 실패 시 silent 통과 금지 — 모두 log + healthcheck alert
#==============================================================================

set -u
LOG=/tmp/qm_regime_refresh.log
TS=$(date -Iseconds)
DIR=$(ls -d /mnt/c/Users/*/OneDrive/바탕\ 화면/Quant_Module_Moltbot 2>/dev/null | head -1)

if [ -z "$DIR" ]; then
  echo "$TS [regime_refresh] PROJECT_ROOT not found" >> "$LOG"
  exit 1
fi

cd "$DIR" || exit 1
echo "" >> "$LOG"
echo "=========================================================" >> "$LOG"
echo "=== Regime Refresh @ $TS ===" >> "$LOG"
echo "=========================================================" >> "$LOG"

Rscript -e '
  PROJECT_ROOT <- Sys.getenv("PROJECT_ROOT",
    unset = "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")
  setwd(PROJECT_ROOT)
  source("02_Infrastructure/config.R")

  cat("\n[1/5] FRED robust fetch...\n")
  tryCatch({
    source("02_Infrastructure/regime/fred_robust.R")
    fred_robust_fetch_all()
    cat("[1/5] FRED robust fetch: OK\n")
  }, error = function(e) cat("[1/5] FRED robust FAIL:", conditionMessage(e), "\n"))

  cat("\n[2/5] MSM daily refit...\n")
  tryCatch({
    source("02_Infrastructure/regime/msm_daily_refit.R")
    refit_msm_daily()
    cat("[2/5] MSM daily refit: OK\n")
  }, error = function(e) cat("[2/5] MSM daily refit FAIL:", conditionMessage(e), "\n"))

  cat("\n[3/5] KTRI v3 builder...\n")
  tryCatch({
    source("02_Infrastructure/regime/ktri_v3_builder.R")
    build_ktri_v3_safe()
    cat("[3/5] KTRI v3 builder: OK\n")
  }, error = function(e) cat("[3/5] KTRI v3 builder FAIL:", conditionMessage(e), "\n"))

  cat("\n[4/5] regime_signal v2 (daily + monthly)...\n")
  tryCatch({
    source("02_Infrastructure/regime/regime_signal.R")
    tryCatch(build_regime_signal_table(daily = TRUE),
             error = function(e) cat("  daily signal FAIL:", conditionMessage(e), "\n"))
    tryCatch(build_regime_signal_table(daily = FALSE),
             error = function(e) cat("  monthly signal FAIL:", conditionMessage(e), "\n"))
    cat("[4/5] regime_signal v2: OK (or partial)\n")
  }, error = function(e) cat("[4/5] regime_signal FAIL:", conditionMessage(e), "\n"))

  cat("\n[5/5] regime_healthcheck + alert...\n")
  tryCatch({
    source("02_Infrastructure/regime/regime_healthcheck.R")
    res <- regime_health_check(alert_on_fail = TRUE,
                                severity_threshold = "WARN")
    cat(sprintf("[5/5] healthcheck: issues=%s alerted=%s\n",
                as.character(attr(res, "issues_n") %||% NA),
                as.character(attr(res, "alerted") %||% NA)))
  }, error = function(e) cat("[5/5] healthcheck FAIL:", conditionMessage(e), "\n"))

  cat("\n=== regime_data_refresh done ===\n")
' >> "$LOG" 2>&1

RC=$?
TS_END=$(date -Iseconds)
echo "$TS_END [regime_refresh] exit=$RC" >> "$LOG"
exit $RC
