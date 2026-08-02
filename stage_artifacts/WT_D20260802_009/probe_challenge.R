# probe_challenge.R — Self-Adversarial C1 판정 진단
#   (a) P2 score-diff(M01_PATHQ - M01 z)가 D03 base z(저변동 방향)와 정렬되어 있나
#   (b) base M01 자체 lag1 (P2 lag1 붕괴의 대칭 비교)
#   (c) P3 sign 상속 부호 분포 (해석 확정용)
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260802_009")
source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/ramp/factor_validation.R")
BASE <- as.data.table(read_parquet(file.path(OUT, "base_panel.parquet")))
BASE[, Date := as.Date(Date)]
TUNED <- as.data.table(read_parquet(file.path(OUT, "tuned_panel.parquet")))
TUNED[, Date := as.Date(Date)]
SIG <- sort(unique(BASE$Date))

# (a) diff-vs-lowvol 정렬
m01b <- BASE[Factor_Name == "M01_Mom_12_1", .(Date, Ticker, zb = z)]
m01t <- TUNED[Factor_Name == "M01_PATHQ", .(Date, Ticker, zt = score)]
d03b <- BASE[Factor_Name == "D03_RealVol", .(Date, Ticker, zv = z)]
m <- merge(merge(m01b, m01t, by = c("Date", "Ticker")), d03b, by = c("Date", "Ticker"))
m[, diff := zt - zb]
rc <- m[, .(r = suppressWarnings(cor(diff, zv, method = "spearman")), n = .N), by = Date]
cat(sprintf("(a) cor(P2 diff, D03z[저변동+]) mean=%+.3f sd=%.3f 월수=%d\n",
    rc[, mean(r, na.rm = TRUE)], rc[, sd(r, na.rm = TRUE)], nrow(rc)))

# (b) base M01 lag1 (universe-제한 하네스 동일)
RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
        col_select = c("Date", "Ticker", "Close", "Vol", "Size", "K200", "KQ150")))
RAW[, Date := as.Date(Date)]
RAW[, ym := format(Date, "%Y-%m")]
MEND <- sort(RAW[, .(Date = max(Date)), by = ym]$Date)
RAWME <- RAW[Date %in% MEND]
rm(RAW); gc(verbose = FALSE)
UNIV <- RAWME[(K200 == TRUE | KQ150 == TRUE), .(Date, Ticker)]
fwd <- build_monthly_forward_returns(RAWME, MEND[MEND >= min(SIG)])
returns_dt <- fwd$returns_dt[, .(Date = as.Date(Date), Ticker, Ret_1m)]
bench_dt   <- fwd$bench_dt[,   .(Date = as.Date(Date), BM_Ret)]
liq_dt     <- fwd$liq_dt[,     .(Date = as.Date(Date), Ticker, adv)]
sig_idx <- setNames(seq_along(SIG), as.character(SIG))
sc <- merge(m01b[, .(Date, Ticker, score = zb)], UNIV, by = c("Date", "Ticker"))
l1 <- copy(sc)[, i := sig_idx[as.character(Date)] + 1L]
l1 <- l1[i <= length(SIG)][, Date := SIG[i]][, i := NULL]
r <- canonical_screen_bt(l1, returns_dt, bench_dt, top_n = 25L,
      cost_bps_oneway = 15, liq_dt = liq_dt, liq_min = 2e8,
      run_id = "WT-D20260802_009_lag1b", strategy_id = "WT_D20260802_009_M01_base_lag1",
      diag_dual_basis = FALSE)
cat(sprintf("(b) base M01 lag1: +1.30 -> %+.2f\n", r$portfolio_alpha_t_nw_lag3))

# (c) P3 sign 분포
om <- readRDS(file.path(OUT, "orientation_meta.rds"))
cat(sprintf("(c) P3 s=+1 월 %d / s=-1 월 %d | P2 s=+1 %d / s=-1 %d\n",
    om$sign_p3[s > 0, .N], om$sign_p3[s < 0, .N],
    om$sign_p2[s > 0, .N], om$sign_p2[s < 0, .N]))
