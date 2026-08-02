# =============================================================================
# FQ-108 run_02: 재료 패널 구축
#   (1) factor_db 꼬리-변동성 팩터 — load_month_factors() 경유 (C15). 월별 asof assert.
#         D35_RealVol_63d / D45_Downside_Dev / D05_MaxRet
#   (2) rawdata-파생 63거래일 실현분산 rv63 (레벨 채널) — 월말 t 기준, PIT 안전
#   (3) 종목-홀딩월 실현분산 RV_{i,t+1} (일간 제곱합) = 회귀 target + 전이시험 패널
#   입력: FQ-057 P1 pinned 패널 (재빌드 없음)
#   Output: fq108_factor_panel.parquet / fq108_stock_rv.parquet / fq108_run02_meta.json
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
})
data.table::setDTthreads(1)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(ROOT)
source(file.path(ROOT, "02_Infrastructure/config.R"))
source(file.path(FACTOR_DB_DIR, "factor_db_connector.R"))
OUT_DIR  <- file.path(ROOT, "stage_artifacts/method_frontier")
LANE_OUT <- file.path(ROOT, "stage_artifacts/method_frontier")

REB_FROM <- 200912L; REB_TO <- 202605L
DAILY_CAP <- 0.6
RV63_DAYS <- 63L
FACTORS <- c("D35_RealVol_63d", "D45_Downside_Dev", "D05_MaxRet")

# ---- pinned 입력 -------------------------------------------------------------
dret <- as.data.table(read_parquet(file.path(OUT_DIR, "p1_daily_returns.parquet")))
mr   <- as.data.table(read_parquet(file.path(OUT_DIR, "fq057_monthly_returns.parquet")))

dret <- dret[!is.na(Ret)]
n_cap <- dret[abs(Ret) > DAILY_CAP, .N]
dret[Ret >  DAILY_CAP, Ret :=  DAILY_CAP]
dret[Ret < -DAILY_CAP, Ret := -DAILY_CAP]
dret[, ym := as.integer(format(Date, "%Y")) * 100L + as.integer(format(Date, "%m"))]
setorder(dret, Ticker, Date)
cat("[daily] rows:", nrow(dret), " monster-capped:", n_cap, "\n")

all_days <- sort(unique(dret$Date))
day_ym   <- as.integer(format(all_days, "%Y")) * 100L + as.integer(format(all_days, "%m"))
last_td  <- data.table(Date = all_days, ym = day_ym)[, .(reb_date = max(Date)), by = ym]
setkey(last_td, ym)

yms <- sort(unique(mr$ym))
ym_next <- function(y) { yy <- y %/% 100L; mm <- y %% 100L; if (mm == 12L) (yy + 1L) * 100L + 1L else y + 1L }
reb_months <- yms[yms >= REB_FROM & yms <= REB_TO]
cat("[panel] rebalance months:", length(reb_months), " range:",
    min(reb_months), "..", max(reb_months), "\n")

# =============================================================================
# (3) 종목-월 실현분산 RV_{i,ym} = Σ_d r_d^2  (홀딩월 라벨은 그 달 자체)
# =============================================================================
STOCK_RV <- dret[, .(rv = sum(Ret^2), n_days = .N), by = .(Ticker, ym)]
STOCK_RV <- STOCK_RV[n_days >= 10L & rv > 0]
setnames(STOCK_RV, "ym", "holding_ym")
# 월간수익 (crash/boom 전이시험용)
mrl <- mr[, .(Ticker, holding_ym = ym, ret_m)]
STOCK_RV <- merge(STOCK_RV, mrl, by = c("Ticker", "holding_ym"), all.x = TRUE)
cat("[stock_rv] rows:", nrow(STOCK_RV), " tickers:", uniqueN(STOCK_RV$Ticker),
    " months:", uniqueN(STOCK_RV$holding_ym), "\n")

# =============================================================================
# (2) rv63 = 월말 t 기준 최근 63거래일 실현분산 (월간 스케일 환산: ×21/63)
#     PIT: 월말 t 이하 일간만. rolling sum over trailing 63 obs per ticker.
# =============================================================================
dret[, sq := Ret^2]
setorder(dret, Ticker, Date)
dret[, roll63 := frollsum(sq, RV63_DAYS, align = "right"), by = Ticker]
dret[, nobs63 := frollsum(as.numeric(!is.na(sq)), RV63_DAYS, align = "right"), by = Ticker]
# 월말 트레이딩일 행만 추출
me <- merge(dret[, .(Ticker, Date, ym, roll63, nobs63)],
            last_td[, .(ym, reb_date)], by = "ym")
me <- me[Date == reb_date & !is.na(roll63) & nobs63 == RV63_DAYS]
me[, rv63_m := roll63 * (21 / RV63_DAYS)]          # 월간분산 스케일
RV63 <- me[, .(t_ym = ym, Ticker, rv63_m)]
cat("[rv63] rows:", nrow(RV63), " months:", uniqueN(RV63$t_ym), "\n")

# =============================================================================
# (1) factor_db — load_month_factors() 경유 (C15). asof 월별 assert.
# =============================================================================
fac_rows <- list(); asof_rows <- list()
t0 <- Sys.time()
for (t_ym in reb_months) {
  reb_date <- last_td[.(t_ym), reb_date]
  if (is.na(reb_date)) stop("[fatal] no trading day for ym=", t_ym)
  lmf <- tryCatch(load_month_factors(reb_date, coverage_min = 0.05, factor_names = FACTORS),
                  error = function(e) { warning(sprintf("[lmf] %d: %s", t_ym, conditionMessage(e))); NULL })
  if (is.null(lmf) || nrow(lmf) == 0L) {
    asof_rows[[length(asof_rows) + 1L]] <- data.table(
      t_ym = t_ym, reb_date = reb_date, asof = as.Date(NA), n_rows = 0L, ok = 0L)
    next
  }
  asof <- attr(lmf, "factor_db_asof_date")
  # ---- PIT 가드 (fail-closed): asof 는 리밸 월 t 이내 ∧ 월말 트레이딩일 이하 ----
  if (is.na(asof)) stop("[PIT-GUARD] factor_db_asof_date = NA at ym=", t_ym, " (fail-closed)")
  asof_ym <- as.integer(format(asof, "%Y")) * 100L + as.integer(format(asof, "%m"))
  if (asof > reb_date) stop(sprintf("[PIT-GUARD] asof(%s) > reb_date(%s) at ym=%d — 미래참조",
                                    format(asof), format(reb_date), t_ym))
  if (asof_ym != t_ym) stop(sprintf("[PIT-GUARD] asof month(%d) != rebalance month(%d) — stale/skew vintage",
                                    asof_ym, t_ym))
  asof_rows[[length(asof_rows) + 1L]] <- data.table(
    t_ym = t_ym, reb_date = reb_date, asof = asof, n_rows = nrow(lmf), ok = 1L)
  d <- as.data.table(lmf)[, .(t_ym = t_ym, Ticker, Factor_Name, z = Z_Score_Aligned)]
  fac_rows[[length(fac_rows) + 1L]] <- d
  if (match(t_ym, reb_months) %% 48 == 0)
    cat(sprintf("[lmf] %d done (%.1f min)\n", t_ym,
                as.numeric(difftime(Sys.time(), t0, units = "mins"))))
}
FAC <- rbindlist(fac_rows)
ASOF <- rbindlist(asof_rows)
cat("[factors] rows:", nrow(FAC), " months ok:", sum(ASOF$ok), "/", nrow(ASOF), "\n")
print(FAC[, .(n = .N, n_months = uniqueN(t_ym)), by = Factor_Name])

# ---- wide + 부호 반전 (aligned 는 higher=better → 위험 서술은 higher=위험 크게) ----
FW <- dcast(FAC, t_ym + Ticker ~ Factor_Name, value.var = "z")
for (f in FACTORS) if (!(f %in% names(FW))) FW[, (f) := NA_real_]
FW[, g_d35 := -get("D35_RealVol_63d")]      # 높을수록 고변동
FW[, g_d45 := -get("D45_Downside_Dev")]     # 높을수록 하방편차 큼
FW[, g_d05 := -get("D05_MaxRet")]           # 높을수록 복권형(고 MAX)
FW <- FW[, .(t_ym, Ticker, g_d35, g_d45, g_d05)]

PANEL <- merge(FW, RV63, by = c("t_ym", "Ticker"), all = TRUE)
cat("[panel] merged rows:", nrow(PANEL),
    " with g_d35:", PANEL[!is.na(g_d35), .N],
    " with rv63:", PANEL[!is.na(rv63_m), .N], "\n")

# ---- 재료 정합 진단: g_d35 vs log(rv63) 횡단면 상관 (WT-020 의 cor 0.939 대조) ----
chk <- PANEL[!is.na(g_d35) & !is.na(rv63_m) & rv63_m > 0,
             .(cor_sp = suppressWarnings(cor(g_d35, log(rv63_m), method = "spearman")),
               n = .N), by = t_ym]
cat("[material-check] spearman(g_d35, log rv63) median:",
    round(median(chk$cor_sp, na.rm = TRUE), 4),
    " | q10:", round(quantile(chk$cor_sp, 0.10, na.rm = TRUE), 4),
    " q90:", round(quantile(chk$cor_sp, 0.90, na.rm = TRUE), 4), "\n")

write_parquet(PANEL,    file.path(LANE_OUT, "fq108_factor_panel.parquet"))
write_parquet(STOCK_RV, file.path(LANE_OUT, "fq108_stock_rv.parquet"))
write_parquet(ASOF,     file.path(LANE_OUT, "fq108_asof_audit.parquet"))

meta <- list(
  pin_tag = "fq057_20260718_171024",
  built_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
  factors = FACTORS,
  c15_route = "load_month_factors(reb_date, factor_names=...) — parquet 직접 load 없음",
  pit_guard = "월별 assert: asof 비NA ∧ asof <= 월말 트레이딩일 ∧ asof 월 == 리밸 월 (fail-closed stop)",
  n_factor_rows = nrow(FAC), n_months_ok = sum(ASOF$ok), n_months_total = nrow(ASOF),
  rv63_rule = sprintf("trailing %d 거래일 Σr² × 21/%d (월간분산 스케일), 월말 t 기준 (rawdata 파생, C15 무관)",
                      RV63_DAYS, RV63_DAYS),
  stock_rv_rule = "홀딩월 일간 Σr² (n_days>=10)",
  material_check_spearman_g_d35_vs_logrv63_median = round(median(chk$cor_sp, na.rm = TRUE), 4),
  monster_capped_daily = n_cap
)
write_json(meta, file.path(LANE_OUT, "fq108_run02_meta.json"), auto_unbox = TRUE, pretty = TRUE)
cat("[done] run_02 —", round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 1), "min\n")
