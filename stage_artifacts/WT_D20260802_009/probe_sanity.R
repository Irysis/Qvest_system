# probe_sanity.R — (a) ret_net 의미 검증 (b) random-25 통제 (c) 2008 실측치
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260802_009")
source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/ramp/factor_validation.R")
R <- readRDS(file.path(OUT, "wt009_eval_results.rds"))
pr <- as.data.table(R$bt$D03_RealVol$period_returns)
cat("D03 period_returns cols:", paste(names(pr), collapse = ","), "\n")
cat("2008 rows:\n")
print(pr[format(date, "%Y") == "2008"])
cat(sprintf("ret_net: mean(ann)=%.3f sd(ann)=%.3f min=%.3f\n",
    12 * mean(pr$ret_net), sqrt(12) * sd(pr$ret_net), min(pr$ret_net)))
cat(sprintf("bench:   mean(ann)=%.3f min=%.3f\n",
    12 * mean(pr$benchmark_ret), min(pr$benchmark_ret)))
# random-25 통제 (시드 3개)
BASE <- as.data.table(read_parquet(file.path(OUT, "base_panel.parquet")))
BASE[, Date := as.Date(Date)]
RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
        col_select = c("Date", "Ticker", "Close", "Vol", "Size", "K200", "KQ150")))
RAW[, Date := as.Date(Date)]
RAW[, ym := format(Date, "%Y-%m")]
MEND <- sort(RAW[, .(Date = max(Date)), by = ym]$Date)
RAWME <- RAW[Date %in% MEND]
rm(RAW); gc(verbose = FALSE)
SIG <- sort(unique(BASE$Date))
fwd <- build_monthly_forward_returns(RAWME, MEND[MEND >= min(SIG)])
returns_dt <- fwd$returns_dt[, .(Date = as.Date(Date), Ticker, Ret_1m)]
bench_dt   <- fwd$bench_dt[,   .(Date = as.Date(Date), BM_Ret)]
liq_dt     <- fwd$liq_dt[,     .(Date = as.Date(Date), Ticker, adv)]
UNIV <- RAWME[(K200 == TRUE | KQ150 == TRUE), .(Date, Ticker)]
uni <- merge(BASE[Factor_Name == "V01_BM", .(Date, Ticker)], UNIV, by = c("Date", "Ticker"))
for (seed in 1:3) {
  set.seed(9000 + seed)
  rnd <- copy(uni)[, score := runif(.N)]
  r <- canonical_screen_bt(rnd, returns_dt, bench_dt, top_n = 25L,
        cost_bps_oneway = 15, liq_dt = liq_dt, liq_min = 2e8,
        run_id = "WT-D20260802_009_rnd", strategy_id = sprintf("WT_D20260802_009_rnd%d", seed),
        diag_dual_basis = FALSE)
  cat(sprintf("random-25 seed%d: PORT_t=%+.2f netSR=%+.3f TO=%.0f%% n=%d\n",
      seed, r$portfolio_alpha_t_nw_lag3, r$net_sr, 100 * r$turnover_annual, r$n_months))
}
