# =============================================================================
# driver_in04_lo_B.R — IN04 다축 상관 (Part B 단독, fresh 프로세스 = 누적메모리 0)
#   Part A(driver_in04_lo_A.R)와 분리 실행. 본 driver는 LS 월간 시계열만 재구성해
#   STR_1715 / value(BM) LS / 풀 주요 모듈과 상관(cor)을 잰다. build_bt_result 없음.
#
#   ★ 메모리 규율(fe_single v2 패턴): RAWDATA에서 universe(.mem) + slim daily Ret(rd_daily)만
#     추출 직후 full RAWDATA 즉시 해제 → factor 일괄로딩(254월) 동안 378MB peak 제거.
#     2-part 통합 driver의 OOM 원인 = rd_daily(full daily) + me_panel + full RAWDATA가
#     factor 루프 내내 co-resident. 본 driver는 LS만 하므로 그 충돌이 없다.
#
#   ★ IN04 LS 월수익은 ls_screen JSON에 *시계열이 저장돼 있지 않아*(summary만) 재산출 불가피.
#     단 재산출은 LS leg(daily decile)만 — 가벼운 단일 패스. self-contained.
#   ★ 자체합성 금지(Return.portfolio/apply.monthly/Return.cumulative 표준함수만).
#
#   판정: max|corr|<0.3 이면 LS 스프레드가 다축 직교(1st eigenmode 무관).
#   호출(PowerShell run_in_background, -f 금지, BOM 없이):
#     Rscript -e "source('stage_artifacts/alpha_search/driver_in04_lo_B.R')"
#   출력: stage_artifacts/alpha_search/in04_multiaxis_corr_B_result.json
# =============================================================================
suppressWarnings(suppressMessages({
  library(data.table); library(xts); library(zoo); library(PerformanceAnalytics); library(jsonlite)
}))
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a

PROJ  <- Sys.getenv("CLAUDE_PROJECT_DIR", "G:/Quant_Module_Moltbot")
INFRA <- file.path(PROJ, "02_Infrastructure")
source(file.path(INFRA, "config.R"))
source(file.path(INFRA, "backtest_harness.R"))                       # load_rawdata, get_execution_date
source(file.path(INFRA, "factor_db", "factor_db_connector.R"))       # load_month_factors

OUT_DIR     <- file.path(PROJ, "stage_artifacts", "alpha_search")
START_DATE  <- as.Date("2005-01-01")
DECILE_FRAC <- 0.10
IN04_F      <- "IN04_Net_Equity_Issuance"
VAL_F       <- "V01_BM"
.fdb_min    <- as.Date("2002-08-01")

cat(sprintf("[IN04-B] 다축 상관 — IN04 LS vs value(BM) LS / STR_1715 / 풀 모듈\n"))

# ---- 1. RAWDATA -> universe(.mem) + slim daily Ret(rd_daily) 추출 직후 full 해제 ----
res <- load_rawdata(use_cache = TRUE); RAWDATA <- res$RAWDATA; rm(res); gc(FALSE)
if (!inherits(RAWDATA$Date, "Date")) RAWDATA[, Date := as.Date(Date)]
setorder(RAWDATA, Ticker, Date)
all_dates <- sort(unique(RAWDATA$Date))

# universe: 멤버십 + 유동성 2e8 (PIT 과거 윈도우) — slim 6열에서만 frollmean
.rd_slim <- RAWDATA[, .(Date, Ticker, Close, Vol, K200, KQ150)]
setorder(.rd_slim, Ticker, Date)
.rd_slim[, .ym := format(Date, "%Y-%m")]
me_dates <- sort(.rd_slim[, .(Date = max(Date)), by = .ym]$Date)
.rd_slim[, .ym := NULL]
me_dates <- me_dates[me_dates >= .fdb_min]
.rd_slim[, .TV := Close * Vol]
.rd_slim[, .AvgTV20 := frollmean(.TV, 20L, align = "right"), by = Ticker]
mem <- .rd_slim[Date %in% me_dates & (K200 == TRUE | KQ150 == TRUE) &
                  !is.na(.AvgTV20) & .AvgTV20 >= 2e8, .(Date, Ticker)]
setkey(mem, Date, Ticker)
rm(.rd_slim); gc(FALSE)

# slim daily Ret 패널 (LS leg 보유수익 — 표준 Return.portfolio 입력)
rd_daily <- RAWDATA[Date >= START_DATE & is.finite(Ret), .(Date, Ticker, Ret)]
rm(RAWDATA); gc(FALSE)                              # ★ full RAWDATA 즉시 해제(factor 루프 RAWDATA-free)
setkey(rd_daily, Ticker, Date)

# ---- 2. 월별 IN04 + V01_BM Z_Score_Aligned (universe 한정, full dt 즉시 폐기 — L-534/OOM) ----
in04_list <- vector("list", length(me_dates)); val_list <- vector("list", length(me_dates))
for (i in seq_along(me_dates)) {
  d <- me_dates[i]
  uni_tk <- mem[.(d), Ticker, nomatch = 0L]; if (!length(uni_tk)) next
  fdt <- tryCatch(load_month_factors(d, coverage_min = 0.05), error = function(e) NULL)
  if (is.null(fdt) || nrow(fdt) == 0) { if (!is.null(fdt)) rm(fdt); next }
  fi <- fdt[Factor_Name == IN04_F & Ticker %in% uni_tk & is.finite(Z_Score_Aligned), .(Ticker, Score = Z_Score_Aligned)]
  fv <- fdt[Factor_Name == VAL_F  & Ticker %in% uni_tk & is.finite(Z_Score_Aligned), .(Ticker, Score = Z_Score_Aligned)]
  rm(fdt)
  if (nrow(fi) >= 20L) { fi[, Date := d]; in04_list[[i]] <- fi[, .(Date, Ticker, Score)] }
  if (nrow(fv) >= 20L) { fv[, Date := d]; val_list[[i]]  <- fv[, .(Date, Ticker, Score)] }
  if (i %% 24L == 0L) gc(FALSE)
}
FAC_IN04 <- rbindlist(Filter(Negate(is.null), in04_list), use.names = TRUE)
FAC_VAL  <- rbindlist(Filter(Negate(is.null), val_list),  use.names = TRUE)
rm(in04_list, val_list); gc(FALSE)
FAC_IN04 <- FAC_IN04[Date >= START_DATE]; FAC_VAL <- FAC_VAL[Date >= START_DATE]
cat(sprintf("[IN04-B] FAC_IN04 months=%d rows=%d | FAC_VAL months=%d rows=%d\n",
            uniqueN(FAC_IN04$Date), nrow(FAC_IN04), uniqueN(FAC_VAL$Date), nrow(FAC_VAL)))

# ---- 3. LS 월간 시계열 (long top-decile − short bottom-decile, EW; 표준함수) ----
build_leg_daily <- function(FAC, side) {
  sd <- sort(unique(FAC$Date)); sd <- sd[sd %in% me_dates]
  dl <- vector("list", length(sd))
  for (i in seq_along(sd)) {
    d <- sd[i]; md <- FAC[Date == d & is.finite(Score)]; n <- nrow(md); if (n < 20L) next
    k <- max(2L, as.integer(ceiling(n * DECILE_FRAC)))
    setorder(md, -Score)
    picks <- if (side == "long") head(md$Ticker, k) else tail(md$Ticker, k)
    exec_date <- get_execution_date(d, all_dates); if (is.na(exec_date)) next
    next_exec <- if (i < length(sd)) get_execution_date(sd[i + 1L], all_dates) else NA_Date_
    hold_end  <- if (!is.na(next_exec)) all_dates[all_dates < next_exec] else all_dates
    hold_end  <- max(hold_end[hold_end >= exec_date], exec_date)
    sub <- rd_daily[Ticker %in% picks & Date >= exec_date & Date <= hold_end, .(Date, Ticker, Ret)]
    if (!nrow(sub)) next
    w <- dcast(sub, Date ~ Ticker, value.var = "Ret"); setorder(w, Date)
    rmat <- as.matrix(w[, -1, with = FALSE]); rmat[!is.finite(rmat)] <- 0
    rx <- xts(rmat, order.by = w$Date)
    pr <- tryCatch(Return.portfolio(rx, weights = rep(1/ncol(rx), ncol(rx)), rebalance_on = NA), error = function(e) NULL)
    if (is.null(pr)) next
    dl[[i]] <- data.table(Date = as.Date(index(pr)), Ret = as.numeric(pr[, 1]))
  }
  out <- rbindlist(Filter(Negate(is.null), dl), use.names = TRUE)
  if (!nrow(out)) return(NULL); setorder(out, Date); out[, .(Ret = mean(Ret)), by = Date]
}
to_monthly_ym <- function(dt) {   # 표준: apply.monthly + Return.cumulative -> ym keyed
  x <- xts(dt$Ret, order.by = dt$Date); m <- apply.monthly(x, Return.cumulative)
  data.table(ym = format(as.Date(index(m)), "%Y-%m"), ret = as.numeric(m[, 1]))
}
ls_monthly <- function(FAC) {
  ld <- build_leg_daily(FAC, "long"); sd <- build_leg_daily(FAC, "short")
  if (is.null(ld) || is.null(sd)) return(NULL)
  m <- merge(ld[, .(Date, L = Ret)], sd[, .(Date, S = Ret)], by = "Date", all = TRUE)
  m[!is.finite(L), L := 0]; m[!is.finite(S), S := 0]; m[, Ret := L - S]; setorder(m, Date)
  to_monthly_ym(m[, .(Date, Ret)])
}
in04_ls_m <- ls_monthly(FAC_IN04); setnames(in04_ls_m, "ret", "in04_ls")
val_ls_m  <- ls_monthly(FAC_VAL);  if (!is.null(val_ls_m)) setnames(val_ls_m, "ret", "val_ls")
rm(rd_daily); gc(FALSE)
cat(sprintf("[IN04-B] in04_ls months=%d | val_ls months=%s\n",
            nrow(in04_ls_m), if (!is.null(val_ls_m)) nrow(val_ls_m) else "NA"))

# ---- 4. 비교 시계열 로드 (저장본): STR_1715 CSV + 풀 모듈 sim_result.rds ----
str1715_path <- file.path(PROJ, "04_Research", "strategies", "STR_1715_WT016_Iter31_GridBestProd",
                          "output", "03_period_returns.csv")
s1715 <- tryCatch({
  z <- fread(str1715_path); z[, ym := format(as.Date(date), "%Y-%m")]; z[, .(ym, str1715 = ret_net)]
}, error = function(e) { cat("[IN04-B] STR_1715 CSV 로드 실패:", conditionMessage(e), "\n"); NULL })

pool_ids <- c("STR_1439_1047_to_fix", "STR_1033_nco", "STR_1550_consensus_core_alpha",
              "STR_1393_esbr_sue_adaptive", "STR_1562_gerber_dcc_hrp_c11fix")
pool_monthly <- function(sid) {
  p <- file.path(PROJ, "04_Research", "strategies", sid, "sim_result.rds")
  if (!file.exists(p)) return(NULL)
  sr <- tryCatch(readRDS(p), error = function(e) NULL); if (is.null(sr)) return(NULL)
  dn <- sr$DAILY_NAV_DT
  if (is.null(dn) || !all(c("Date", "Strategy_Ret") %in% names(dn))) return(NULL)
  dn <- as.data.table(dn); dn[, Date := as.Date(Date)]
  x <- xts(dn$Strategy_Ret, order.by = dn$Date)
  m <- apply.monthly(x, function(z) prod(1 + z[is.finite(z)]) - 1)   # 구간복리(Return.cumulative 동등)
  data.table(ym = format(as.Date(index(m)), "%Y-%m"), ret = as.numeric(m[, 1]))
}

# ---- 5. 상관 (공통 ym 교집합, IN04 LS 기준) ----
cor_pair <- function(a_dt, a_col, b_dt, b_col) {
  if (is.null(a_dt) || is.null(b_dt)) return(NA_real_)
  m <- merge(a_dt[, .(ym, a = get(a_col))], b_dt[, .(ym, b = get(b_col))], by = "ym")
  m <- m[is.finite(a) & is.finite(b)]; if (nrow(m) < 24L) return(NA_real_)
  as.numeric(cor(m$a, m$b))
}
corr_results <- list(
  vs_value_bm_ls = list(corr = round(cor_pair(in04_ls_m, "in04_ls", val_ls_m, "val_ls"), 4),
                        n = if (!is.null(val_ls_m)) nrow(merge(in04_ls_m, val_ls_m, by = "ym")) else 0L),
  vs_STR_1715    = list(corr = round(cor_pair(in04_ls_m, "in04_ls", s1715, "str1715"), 4),
                        n = if (!is.null(s1715)) nrow(merge(in04_ls_m, s1715, by = "ym")) else 0L)
)
for (sid in pool_ids) {
  pm <- pool_monthly(sid)
  corr_results[[paste0("vs_", sid)]] <- list(
    corr = round(cor_pair(in04_ls_m, "in04_ls", pm, "ret"), 4),
    n = if (!is.null(pm)) nrow(merge(in04_ls_m, pm, by = "ym")) else 0L)
}
cat("\n[IN04-B] 다축 상관 (IN04 LS 기준):\n")
for (nm in names(corr_results)) cat(sprintf("  %-32s corr=%7s  n=%d\n", nm,
     format(corr_results[[nm]]$corr), corr_results[[nm]]$n))

multi_axis_corrs <- sapply(corr_results, function(z) z$corr)
max_abs_corr <- suppressWarnings(max(abs(multi_axis_corrs), na.rm = TRUE))
ortho_corr_pass <- is.finite(max_abs_corr) && max_abs_corr < 0.30

out <- list(
  experiment = "IN04 Net Equity Issuance 다축 상관 (Part B 단독, fresh 프로세스 OOM 우회)",
  factor = IN04_F, metric_type = "backtested_gross_LS", universe = "K200_KQ150",
  start_date = as.character(START_DATE), in04_ls_months = nrow(in04_ls_m),
  multi_axis_corr = corr_results,
  ortho_corr = list(max_abs_corr = round(max_abs_corr, 4), ortho_corr_pass = ortho_corr_pass,
                    threshold = 0.30),
  partA_reference = "long-only top25 OOS retention -0.983 (붕괴; value -0.517보다 더 나쁨) → 직교는 LS-only",
  verdict = if (ortho_corr_pass)
      "LS 스프레드는 다축 직교(max|corr|<0.3)이나 long-only 붕괴 → LS-only 직교원(long-only 슬리브 불가)"
    else
      "LS 스프레드도 한 축 이상서 비직교(max|corr|>=0.3) + long-only 붕괴 → 직교원 아님",
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S"))
write_json(out, file.path(OUT_DIR, "in04_multiaxis_corr_B_result.json"),
           auto_unbox = TRUE, pretty = TRUE, digits = 6, na = "null")
cat(sprintf("\n[IN04-B-VERDICT] max_abs_corr=%.3f (<0.3=%s) | partA OOS_ret(LO)=-0.983(붕괴)\n",
            max_abs_corr, ortho_corr_pass))
cat("[SAVED] in04_multiaxis_corr_B_result.json\n")
