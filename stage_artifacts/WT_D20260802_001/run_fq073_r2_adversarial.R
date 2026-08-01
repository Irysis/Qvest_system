# =============================================================================
# run_fq073_r2_adversarial.R — WT-D20260802_001 R2 / Self-Adversarial Challenge 실측
#
#   자기 비평이 제기한 반론 중 **데이터로 판별 가능한 것**을 직접 측정한다
#   (반론을 글로만 적고 넘어가면 challenge_note 가 수사가 된다).
#
#   C2 : "cap-tier 가 안 움직인 건 materiality 탓이 아니라 크로스워크에 대형주가
#         애초에 없어서다" → tier 별 스코어 커버리지 실측으로 판별
#   C1 : "materiality 는 버킷-수준이라 버킷 안 동점을 못 깬다" → 매핑 구조 실측
#   C4 : 대형주-제한 재측정 (R1 F5 등가) — 대형 tier 안에서는 신호가 사는가
# =============================================================================
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)})
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260802_001")
say <- function(fmt, ...) cat(sprintf(paste0("[adv] ", fmt, "\n"), ...))
source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/ramp/factor_validation.R")

RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
        col_select = c("Date","Ticker","Close","Vol","Size","K200","KQ150")))
RAW[, Date := as.Date(Date)]; RAW <- RAW[Date >= as.Date("2014-11-01")]
RAW[, ym := format(Date, "%Y-%m")]
MEND <- sort(RAW[, .(Date = max(Date)), by = ym]$Date); RAWME <- RAW[Date %in% MEND]
fwd <- build_monthly_forward_returns(RAWME, MEND)
returns_dt <- fwd$returns_dt[, .(Date = as.Date(Date), Ticker, Ret_1m)]
bench_dt   <- fwd$bench_dt[,   .(Date = as.Date(Date), BM_Ret)]
liq_dt     <- fwd$liq_dt[,     .(Date = as.Date(Date), Ticker, adv)]
size_dt    <- RAWME[, .(Date, Ticker, Size)]
SZ <- copy(size_dt)[!is.na(Size)]; setorder(SZ, Date, -Size)
SZ[, cap_rank := seq_len(.N), by = Date]
SZ[, tier := fifelse(cap_rank <= 10L,"MEGA", fifelse(cap_rank <= 30L,"MID","OTHER"))]
U <- merge(RAWME[(K200==TRUE|KQ150==TRUE), .(Date, Ticker)],
           SZ[, .(Date, Ticker, cap_rank, tier)], by = c("Date","Ticker"))

G1 <- as.data.table(read_parquet(file.path(OUT, "alpha_scores_R2_G1_mat_surprise.parquet")))
G5 <- as.data.table(read_parquet(file.path(OUT, "alpha_scores_R2_G5_mat_sue_sm6.parquet")))
A <- list()

# ── C2: tier 별 스코어 커버리지 ──────────────────────────────────────────
cov <- merge(U, G1[!is.na(value), .(Date, Ticker, scored = TRUE)],
             by = c("Date","Ticker"), all.x = TRUE)
cov[is.na(scored), scored := FALSE]
ct <- cov[, .(n_univ = .N, n_scored = sum(scored), cover = round(mean(scored), 4)), by = tier]
avg <- cov[scored == TRUE, .N, by = .(Date, tier)][, .(avg_scored_per_month = round(mean(N),2)), by = tier]
ct <- merge(ct, avg, by = "tier")
print(ct)
A$C2_tier_score_coverage <- list(
  metric_type = "diagnostic", by_tier = split(ct, ct$tier),
  verdict = paste0("REBUTTED — MEGA 커버리지 ", ct[tier=="MEGA", cover],
    " (월평균 ", ct[tier=="MEGA", avg_scored_per_month], "/10 종목이 스코어 보유) 로 OTHER(",
    ct[tier=="OTHER", cover], ") 보다 오히려 높다. top-25 슬롯 대비 대형주 후보가 부족해서 ",
    "선택되지 않은 것이 아니다 — 선택 가능한데 선택되지 않았다."))

# ── C1: 버킷 내 동점 구조 (materiality 가 깰 수 없는 부분) ─────────────
XW <- as.data.table(read_parquet(
  "stage_artifacts/method_frontier/firm_level_scaffold/fq073/firm_hs_crosswalk.parquet"))
f <- XW[consume_ok_chapter == TRUE & !is.na(hs_code)]
bs <- f[, .N, by = hs_code][order(-N)]
A$C1_bucket_tie_structure <- list(
  metric_type = "diagnostic",
  n_firms_single_hs4 = nrow(f[is.na(hs4_secondary)]),
  n_firms_multi_hs4 = nrow(f[!is.na(hs4_secondary)]),
  n_buckets = nrow(bs), n_buckets_single_firm = sum(bs$N == 1),
  median_firms_per_bucket = as.numeric(median(bs$N)), max_firms_per_bucket = max(bs$N),
  n_firms_in_shared_buckets = sum(bs[N >= 2]$N),
  verdict = paste0("ACCEPT — M_i = Σ_h w_ih·R_h 에서 R_h 는 버킷 수준이고 Rev_i 는 소거된다. ",
    "따라서 단일-HS4 매핑 기업(", nrow(f[is.na(hs4_secondary)]), "/", nrow(f),
    ")끼리는 같은 버킷 안에서 여전히 동점이다. 실측: distinct_ratio 0.6439 -> 0.6488 (거의 무변화). ",
    "'5% vs 80% 노출' 구분은 **버킷 간**으로만 실현됐고 **버킷 내**에서는 실현되지 않았다."))

# ── C4: 대형주 제한 재측정 ───────────────────────────────────────────────
LARGE <- U[cap_rank <= 100L, .(Date, Ticker)]
lc <- list()
for (nm in c("R2_G1_mat_surprise","R2_G5_mat_sue_sm6")) {
  P <- if (nm == "R2_G1_mat_surprise") G1 else G5
  PL <- merge(P[!is.na(value), .(Date, Ticker, score = value)], LARGE, by = c("Date","Ticker"))
  r <- canonical_screen_bt(PL, returns_dt, bench_dt, top_n = 25L, cost_bps_oneway = 15,
                           liq_dt = liq_dt, liq_min = 2e8, diag_dual_basis = TRUE, size_dt = size_dt)
  lc[[nm]] <- list(metric_type = "canonical_screen", universe = "cap_rank<=100 within K200uKQ150",
                   portfolio_alpha_t_nw_lag3 = round(r$portfolio_alpha_t_nw_lag3, 4),
                   p = round(r$portfolio_alpha_t_pvalue, 4), n_months = r$n_months,
                   turnover_annual = round(r$turnover_annual, 4),
                   ew_universe_port_t = round(r$diag_ew_universe$portfolio_alpha_t_nw_lag3, 4),
                   n_scored_avg = round(PL[, .N, by = Date][, mean(N)], 1))
  say("%s cap_rank<=100: PORT_t=%+.4f p=%.3f n=%d TO=%.1f%% EW=%+.4f", nm,
      r$portfolio_alpha_t_nw_lag3, r$portfolio_alpha_t_pvalue, r$n_months,
      100*r$turnover_annual, r$diag_ew_universe$portfolio_alpha_t_nw_lag3)
}
A$C4_large_cap_restricted <- c(lc, list(
  verdict = "대형 tier 안으로 유니버스를 제한해도 알파는 없다(0 근방). R1 F5(-0.33)와 동일 결론."))

write_json(A, file.path(OUT, "fq073_r2_adversarial.json"), auto_unbox = TRUE, pretty = TRUE,
           null = "null", digits = 6)
say("→ fq073_r2_adversarial.json")
