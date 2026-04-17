#==============================================================================
# FIX_1341 — BM+ESBR Weighted Sum + Defense Core
#
# Fix: STR_1341의 pmin() 교차가 지나치게 제한적 → 선별력 소멸 (CAGR 0.98%)
#   pmin(Z[BM], Z[ESBR]) → 0.5*Z[BM] + 0.5*Z[ESBR] 가중합산 전환
#   + Defense 비중 40→20% 축소 (시너지 pillar 80%로 강화)
#
# PIT: C13(Z_Score_Aligned), C14(Usable_Date for IC), C15(load_month_factors)
# Parent: STR_1341 (Grade F, CAGR 0.98%, Sharpe 0.083)
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
})

cat("[factor_engine] FIX_1341: BM+ESBR Weighted Sum + Defense Core...\n")

# ---- Constants ----
DEFENSE_FACTORS <- c("D01_IdioVol", "D02_Beta")
SYNERGY_FACTORS <- c("V01_BM", "C04_ESBR")
DEFENSE_WEIGHT  <- 0.20   # 40→20% (축소)
SYNERGY_WEIGHT  <- 0.80   # 60→80% (강화)
LIQ_THRESHOLD   <- 2e8
SECTOR_NEUTRAL  <- TRUE

# ---- Factor engine function (called per signal date in run_all.R) ----
compute_synergy_defense_scores <- function(sig_d, fdb_month, rawdata_snap) {
  # 1. Extract required factors
  all_needed <- c(DEFENSE_FACTORS, SYNERGY_FACTORS)
  avail <- fdb_month[Factor_Name %in% all_needed]
  avail_factors <- unique(avail$Factor_Name)

  if (!all(SYNERGY_FACTORS %in% avail_factors)) return(NULL)
  if (sum(DEFENSE_FACTORS %in% avail_factors) < 1L) return(NULL)

  # 2. Pivot to wide
  scores_wide <- dcast(avail, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")

  # 3. Liquidity filter (t-1 lagged, C10)
  liq_tickers <- rawdata_snap[!is.na(AvgTV20) & AvgTV20 >= LIQ_THRESHOLD, Ticker]
  scores_wide <- scores_wide[Ticker %in% liq_tickers]
  if (nrow(scores_wide) < 30L) return(NULL)

  # 4. Pillar 1: Defense (EW composite)
  def_cols <- intersect(DEFENSE_FACTORS, names(scores_wide))
  scores_wide[, defense_score := rowMeans(.SD, na.rm = TRUE), .SDcols = def_cols]

  # 5. Pillar 2: Value-Earnings Synergy — FIX: pmin→weighted sum
  #    가중합산으로 BM 또는 ESBR 단독 우수 종목도 포함
  scores_wide[, synergy_score := 0.5 * V01_BM + 0.5 * C04_ESBR]

  # 6. Combined score
  scores_wide[, Score := DEFENSE_WEIGHT * defense_score + SYNERGY_WEIGHT * synergy_score]
  scores_wide <- scores_wide[!is.na(Score)]
  if (nrow(scores_wide) < 30L) return(NULL)

  # 7. Sector neutralization
  if (SECTOR_NEUTRAL) {
    sector_map <- rawdata_snap[, .(Ticker, Sector)]
    scores_wide <- merge(scores_wide, sector_map, by = "Ticker", all.x = TRUE)
    scores_wide[!is.na(Sector), Score := Score - mean(Score, na.rm = TRUE), by = Sector]
  }

  scores_wide[, Date := sig_d]
  scores_wide[, .(Date, Ticker, Score)]
}

cat("[factor_engine] Functions loaded: compute_synergy_defense_scores()\n")
cat(sprintf("  Defense (%.0f%%): %s | Synergy (%.0f%%): 0.5*%s + 0.5*%s\n",
            DEFENSE_WEIGHT * 100, paste(DEFENSE_FACTORS, collapse = "+"),
            SYNERGY_WEIGHT * 100, SYNERGY_FACTORS[1], SYNERGY_FACTORS[2]))
