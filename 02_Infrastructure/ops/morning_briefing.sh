#!/usr/bin/env bash
#==============================================================================
# Morning Regime Briefing — 매일 아침 7시
# 1) 데이터 최신화 (KRX + Naver T+0 + Arrow + KTRI + FRED + Regime Signal)
# 2) 텔레그램 레짐 브리핑 발송
#
# crontab: 10 7 * * 1-5 bash "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot/02_Infrastructure/morning_briefing.sh"
#==============================================================================
set -uo pipefail  # -e 제거: 개별 스텝 실패해도 나머지 계속 실행
LOGFILE="/tmp/qm_morning_briefing_$(date +%Y%m%d).log"
exec > >(tee -a "$LOGFILE") 2>&1

echo "=== Morning Briefing @ $(date) ==="
source "$(dirname "${BASH_SOURCE[0]:-$0}")/resolve_project.sh"
INFRA="$BASE/02_Infrastructure"

# 1. KRX 데이터 최신화
echo "[1/5] KRX Data Update..."
cd "$INFRA"
Rscript --no-save -e '
  source("config.R")
  source("krx_data_collector.R")
  source("krx_build_rawdata.R")
  gap <- krx_detect_gap()
  cat(sprintf("Gap: %s → %s (%d days)\n", gap$last_rawdata_date, gap$end, gap$n_calendar_days))
  if (gap$n_calendar_days > 0) {
    krx_run_pipeline()
  } else {
    cat("RAWDATA already up to date.\n")
  }
'

# 1.5 Naver T+0 보완 (KRX T+1 gap이 남아있으면 Naver로 채움)
echo "[1.5/5] Naver T+0 Supplement..."
cd "$INFRA"
Rscript --no-save -e '
  source("config.R")
  source("naver_data_collector.R")
  tryCatch({
    naver_run_pipeline()
  }, error = function(e) cat(sprintf("Naver pipeline skipped: %s\n", e$message)))
'

# 2. Arrow + KTRI 연장
echo "[2/5] Arrow + KTRI..."
cd "$INFRA"
Rscript --no-save -e '
  source("config.R")
  source("krx_data_collector.R")
  source("krx_arrow_pipeline.R")
  tryCatch({
    krx_extend_arrow()
    cat("Arrow extension complete.\n")
  }, error = function(e) cat(sprintf("Arrow extension skipped: %s\n", e$message)))
'
cd "$BASE"
Rscript --no-save -e '
  tryCatch({
    source("04_Regime_Engine/KTRI_v3_reinforced.R")
    cat("KTRI v3 signals regenerated.\n")
  }, error = function(e) cat(sprintf("KTRI rebuild skipped: %s\n", e$message)))
'

# 3. FRED + Regime Signal 업데이트
echo "[3/5] FRED + Regime Signal..."
cd "$INFRA"
Rscript --no-save -e '
  source("config.R")
  if (file.exists("fred_macro_collector.R")) {
    source("fred_macro_collector.R")
    tryCatch(fred_update_regime(), error = function(e)
      cat(sprintf("FRED update skipped: %s\n", e$message)))
  }
  source("regime_signal.R")
  tryCatch(build_regime_signal_table(), error = function(e)
    cat(sprintf("Regime signal skipped: %s\n", e$message)))
'

# 4. 레짐 브리핑 발송
echo "[4/5] Sending Regime Briefing..."
cd "$INFRA"
Rscript --no-save -e '
  source("config.R")
  source("telegram_notify.R")
  tryCatch(tg_regime_briefing(), error = function(e)
    cat(sprintf("Regime briefing failed: %s\n", e$message)))
'

echo "=== Morning Briefing Done @ $(date) ==="

# Step 3: Production strategy daily NAV report
# NOTE: sleeve_save_helper.R 제거됨. daily_portfolio_nav.R만으로 동작.
Rscript -e 'source("02_Infrastructure/config.R"); source("02_Infrastructure/backtest_harness.R"); source("02_Infrastructure/daily_portfolio_nav.R"); tryCatch(daily_nav_report("STR_905"), error=function(e) cat("[NAV] Skip:", e$message, "\n"))' >> /tmp/qm_morning.log 2>&1
