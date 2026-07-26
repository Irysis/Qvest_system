#==============================================================================
# fq064_random_null.R — FQ-064 진단: 음수 PORT_t의 원인이 *신호*인가 *풀*인가
#
#   문제: 헤드카운트/급여 x 3M/6M x ±부호 6-config 전부 PORT_t -1.8~-2.4.
#         신호가 무의미하면 0 근처여야 하는데 그렇지 않다 → 신호가 아니라
#         **매칭 풀(447사)에서 top-25 EW를 뽑는 행위 자체**가 지는지 검정.
#
#   통제: 동일 (Date, Ticker) 적격집합에서 **무작위 score**로 top-25를 뽑아 동일 계약
#         (canonical_screen_bt)으로 측정. 시드 N개의 PORT_t 분포를 신호 config와 비교.
#         - random 분포가 0 근처 → 풀은 중립, 음수는 신호 탓(신호가 역-정보)
#         - random 분포도 -2 근처 → 풀/구성 자체가 원인, 신호 판정 불가(교란)
#   (07-19 R5에서 cap-tilt lift를 반증할 때 쓴 random-null과 동일 통제 논리)
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a)) b else a
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
SCAF <- "stage_artifacts/method_frontier/firm_level_scaffold"
OUT  <- file.path(SCAF, "fq064_out")

nps <- as.data.table(read_parquet(file.path(SCAF, "data_pull", "nps_headcount_raw.parquet")))
xw  <- as.data.table(read_parquet(file.path(SCAF, "firm_crosswalk.parquet")))
.norm <- function(s) gsub("[[:space:]\\-\\.,]", "", gsub("\\(주\\)|㈜|주식회사|\\(유\\)", "", s))
xw[, bizno6 := substr(as.character(bizr_no), 1, 6)]
xw[, corp_norm := .norm(as.character(corp_name))]
nps[, bizno6 := sprintf("%06s", as.character(bizno6))]

cand <- merge(nps, xw[, .(bizno6, Ticker, corp_norm)], by = "bizno6", allow.cartesian = TRUE)
cand[, hit := startsWith(wkpl_norm, corp_norm)]
cand[hit == FALSE, hit := mapply(grepl, corp_norm, wkpl_norm, MoreArgs = list(fixed = TRUE))]
cand <- cand[hit == TRUE]
cand[, .nlen := nchar(corp_norm)]
setorder(cand, data_ym, wkpl_nm, -.nlen)
cand <- unique(cand, by = c("data_ym", "wkpl_nm", "bizno6"))
firm <- cand[, .(member_cnt = sum(hc, na.rm = TRUE), n_wkpl = .N), by = .(Ticker, data_ym)]

setorder(firm, Ticker, data_ym)
firm[, ln_hc := log(pmax(member_cnt, 1))]
firm[, mi := as.integer(substr(data_ym, 1, 4)) * 12L + as.integer(substr(data_ym, 6, 7))]
lagd <- firm[, .(Ticker, mi_t = mi + 3L, ln_lag = ln_hc, nw_lag = n_wkpl)]
firm <- merge(firm, lagd, by.x = c("Ticker", "mi"), by.y = c("Ticker", "mi_t"), all.x = TRUE)
firm[, mom3 := ln_hc - ln_lag]
firm[n_wkpl != nw_lag | abs(mom3) > log(2), mom3 := NA_real_]
{
  .y <- as.integer(substr(firm$data_ym, 1, 4)); .m <- as.integer(substr(firm$data_ym, 6, 7)) + 1L
  .y <- .y + (.m > 12L); .m <- ifelse(.m > 12L, 1L, .m)
  firm[, sig_ym := sprintf("%04d-%02d", .y, .m)]
}

source("02_Infrastructure/ramp/factor_validation.R")
RAW <- as.data.table(read_parquet(".cache/rawdata.parquet",
  col_select = c("Date", "Ticker", "Close", "Vol", "Size", "K200", "KQ150")))
RAW[, Date := as.Date(Date)]; RAW[, ym := format(Date, "%Y-%m")]
.MEND <- sort(RAW[, .(Date = max(Date)), by = ym]$Date)
fwd <- build_monthly_forward_returns(RAW[Date %in% .MEND], .MEND)

me_map <- data.table(ym = format(.MEND, "%Y-%m"), sig_date = .MEND)
firm <- merge(firm, me_map, by.x = "sig_ym", by.y = "ym", all.x = TRUE)
elig <- firm[is.finite(mom3) & !is.na(sig_date), .(Date = sig_date, Ticker)]
cat(sprintf("[null] 적격 (Date,Ticker) %d행 / 종목 %d / 월 %d\n",
            nrow(elig), uniqueN(elig$Ticker), uniqueN(elig$Date)))

source("02_Infrastructure/contracts/backtest_result_contract.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")

NSEED <- as.integer(Sys.getenv("FQ064_NSEED", "20"))
res <- vector("list", NSEED)
for (s in seq_len(NSEED)) {
  set.seed(1000L + s)
  sc <- copy(elig)[, score := runif(.N)]
  r <- canonical_screen_bt(sc, fwd$returns_dt, fwd$bench_dt,
                           top_n = 25L, cost_bps_oneway = 15,
                           liq_dt = fwd$liq_dt, liq_min = 2e8,
                           run_id = sprintf("FQ064_null_%02d", s),
                           strategy_id = sprintf("NPS_RandomNull_%02d", s),
                           diag_dual_basis = TRUE)
  res[[s]] <- data.table(seed = s,
                         port_t = r$portfolio_alpha_t_nw_lag3 %||% NA_real_,
                         ew_uni_t = r$diag_ew_universe$portfolio_alpha_t_nw_lag3 %||% NA_real_,
                         net_sr = r$net_sr %||% NA_real_,
                         turnover = r$turnover_annual %||% NA_real_,
                         n_months = r$n_months %||% NA_integer_)
  cat(sprintf("  seed %02d: PORT_t=%7.3f  EWuni_t=%7.3f  turnover=%6.2f\n",
              s, res[[s]]$port_t, res[[s]]$ew_uni_t, res[[s]]$turnover))
}
R <- rbindlist(res)
cat(sprintf("\n[null] random-25 PORT_t: mean %.3f | median %.3f | [min %.3f, max %.3f] | n=%d\n",
            mean(R$port_t, na.rm = TRUE), median(R$port_t, na.rm = TRUE),
            min(R$port_t, na.rm = TRUE), max(R$port_t, na.rm = TRUE), nrow(R)))
cat(sprintf("[null] random-25 EW-uni t: mean %.3f | median %.3f\n",
            mean(R$ew_uni_t, na.rm = TRUE), median(R$ew_uni_t, na.rm = TRUE)))
cat(sprintf("[null] random-25 turnover: mean %.2f (신호 arm 11.26 대비)\n", mean(R$turnover, na.rm = TRUE)))

SIG <- c(hc_3M_pos = -2.216, hc_3M_neg = -1.930, hc_6M_pos = -2.068,
         hc_6M_neg = -2.364, pay_6M_pos = -1.830, pay_6M_neg = -2.432)
cat("\n[판정] 신호 config 대비 random-null 위치:\n")
for (nm in names(SIG)) {
  pct <- mean(R$port_t <= SIG[[nm]], na.rm = TRUE)
  cat(sprintf("  %-12s %7.3f  → random 분포 하위 비율 %.2f\n", nm, SIG[[nm]], pct))
}
write_json(list(random_null = R, signal_configs = as.list(SIG),
                verdict_basis = "random 분포가 0 근처면 풀 중립(신호 탓) / -2 근처면 풀 교란"),
           file.path(OUT, "fq064_random_null.json"), auto_unbox = TRUE, pretty = TRUE)
cat("\n[out]", file.path(OUT, "fq064_random_null.json"), "\n")
