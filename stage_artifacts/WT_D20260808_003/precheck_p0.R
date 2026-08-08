# =============================================================================
# precheck_p0.R — WT-D20260808_003 착수 전 사전 확인 (handoff 제1 사전 조건)
#
#   Q-Lead mandate: required_effect() 필요 효과크기 vs drag 함의 크기(|Δβ| × 실측
#   벤치 드리프트)를 **착수 전** 비교한다. 필요 > 함의면 paired 형태를 착수 전
#   폐기하고 월-횡단면 회귀 형태로 전환한다. (부모 WT-D20260808_001 전 arm
#   INCONCLUSIVE_UNDERPOWERED 의 직접 교훈)
#
#   ★ 이 스크립트는 판정 arm(중립화 Q01 top-N / 필터 arm)의 수익을 계산하지 않는다.
#      paired sd 는 무작위-교체 placebo 계열에서만 얻는다(사전등록 전 본판정 열람 방지).
#   ★ 첫 출력 = 입력 형태 실측(행수·관측단위·범위). 가정 금지 (2026-08-08 규약).
#
# 실행: Rscript -e 'source("stage_artifacts/WT_D20260808_003/precheck_p0.R")'
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
  library(sandwich); library(lmtest)
})
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/WT_D20260808_003")
IN9  <- file.path(ROOT, "stage_artifacts/WT_D20260802_009")
IN1  <- file.path(ROOT, "stage_artifacts/WT_D20260808_001")
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)
say <- function(fmt, ...) cat(sprintf(paste0("[p0] ", fmt, "\n"), ...))

source("02_Infrastructure/config.R")
source("02_Infrastructure/ramp/factor_validation.R")          # build_monthly_forward_returns
source("02_Infrastructure/contracts/required_effect_size.R")

set.seed(20260808L)
RES <- list(generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S"))

# ── 0. 입력 형태 실측 (첫 출력 — 가정 금지) ──────────────────────────────────
shape <- function(d, nm, datecol = "Date") {
  d <- as.data.table(d)
  ud <- sort(unique(as.Date(d[[datecol]])))
  gap <- if (length(ud) > 2) median(as.numeric(diff(ud))) else NA_real_
  unit <- if (is.na(gap)) "UNKNOWN" else if (gap <= 5) "DAILY" else if (gap <= 45) "MONTHLY" else "LOWER"
  say("INPUT %-28s nrow=%9d  관측단위=%s(간격중앙 %.1f일)  n_date=%d  범위 %s~%s",
      nm, nrow(d), unit, gap, length(ud), min(ud), max(ud))
  list(nrow = nrow(d), unit = unit, gap_median_days = gap, n_date = length(ud),
       from = as.character(min(ud)), to = as.character(max(ud)))
}
sh <- list()
BASE  <- as.data.table(read_parquet(file.path(IN9, "base_panel.parquet")))[,  Date := as.Date(Date)]
TUNED <- as.data.table(read_parquet(file.path(IN9, "tuned_panel.parquet")))[, Date := as.Date(Date)]
SEC   <- as.data.table(read_parquet(file.path(IN9, "sector_panel.parquet")))[, Date := as.Date(Date)]
SIZEP <- as.data.table(read_parquet(file.path(IN9, "size_panel.parquet")))[,  Date := as.Date(Date)]
sh$base_panel   <- shape(BASE,  "base_panel.parquet")
sh$tuned_panel  <- shape(TUNED, "tuned_panel.parquet")
sh$sector_panel <- shape(SEC,   "sector_panel.parquet")
sh$size_panel   <- shape(SIZEP, "size_panel.parquet")
say("tuned Factor_Name: %s", paste(sort(unique(TUNED$Factor_Name)), collapse = ", "))
say("base  Factor_Name: %s", paste(sort(unique(BASE$Factor_Name)),  collapse = ", "))

RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
        col_select = c("Date","Ticker","Close","Vol","Size","K200","KQ150")))[, Date := as.Date(Date)]
sh$RAWDATA <- shape(RAW, ".cache/RAWDATA.parquet")
stopifnot(sh$RAWDATA$unit == "DAILY")   # 월간 가정 금지 — 실측으로 확인
RAW[, ym := format(Date, "%Y-%m")]
MEND  <- sort(RAW[, .(Date = max(Date)), by = ym]$Date)
RAWME <- RAW[Date %in% MEND]; rm(RAW); gc(verbose = FALSE)
SIG   <- sort(unique(BASE$Date))
UNIV  <- RAWME[(K200 == TRUE | KQ150 == TRUE), .(Date, Ticker)]
say("유니버스(K200∪KQ150 월말): %d행 / 월평균 %.1f종목", nrow(UNIV), UNIV[, .N, by = Date][, mean(N)])

# forward return: 계약함수 경유만 (손계산 금지). 부모 캐시가 있으면 재사용 + 형태 재확인
FWD_F <- file.path(IN1, "fwd_cache.rds")
if (file.exists(FWD_F)) { fwd <- readRDS(FWD_F); say("fwd 캐시 재사용: %s (부모 WT 산출, build_monthly_forward_returns 계약)", FWD_F)
} else { fwd <- build_monthly_forward_returns(RAWME, MEND[MEND >= min(SIG)]); saveRDS(fwd, file.path(OUT, "fwd_cache.rds")) }
returns_dt <- as.data.table(fwd$returns_dt)[, .(Date = as.Date(Date), Ticker, Ret_1m)]
bench_dt   <- as.data.table(fwd$bench_dt)[,   .(Date = as.Date(Date), BM_Ret)]
liq_dt     <- as.data.table(fwd$liq_dt)[,     .(Date = as.Date(Date), Ticker, adv)]
sh$fwd_returns <- shape(returns_dt, "fwd$returns_dt (Ret_1m)")
sh$fwd_bench   <- shape(bench_dt,   "fwd$bench_dt (BM_Ret)")
RES$input_shapes <- sh

nw_t <- function(x, lag = 3L) { x <- x[is.finite(x)]; if (length(x) < 12L) return(NA_real_)
  f <- lm(x ~ 1); tryCatch(as.numeric(lmtest::coeftest(f, vcov. = sandwich::NeweyWest(f, lag = lag, prewhite = FALSE))[1,3]), error = function(e) NA_real_) }
nw_ci <- function(x, lag = 3L) { x <- x[is.finite(x)]; if (length(x) < 12L) return(c(NA_real_, NA_real_))
  f <- lm(x ~ 1); se <- tryCatch(sqrt(sandwich::NeweyWest(f, lag = lag, prewhite = FALSE)[1,1]), error = function(e) NA_real_)
  mean(x) + c(-1,1)*qt(0.975, df = length(x)-1L)*se }

# ── 1. 벤치 드리프트 실측 (drag 함의의 승수) ─────────────────────────────────
say("=== 1. 벤치 드리프트 실측 (drag = |Δβ| × E[R_bench]) ===")
bm <- bench_dt[is.finite(BM_Ret)][order(Date)]
drift <- list(
  full   = list(n = nrow(bm), mean_monthly = mean(bm$BM_Ret), ann_pct = 100*12*mean(bm$BM_Ret),
                sd_monthly = sd(bm$BM_Ret), t_nw = nw_t(bm$BM_Ret)),
  post2015 = { b <- bm[Date >= as.Date("2015-01-01")]
               list(n = nrow(b), mean_monthly = mean(b$BM_Ret), ann_pct = 100*12*mean(b$BM_Ret),
                    sd_monthly = sd(b$BM_Ret), t_nw = nw_t(b$BM_Ret)) })
say("  전표본 BM: n=%d  월평균 %+.4f (연 %+.2f%%)  월sd %.4f  NW t %+.2f",
    drift$full$n, drift$full$mean_monthly, drift$full$ann_pct, drift$full$sd_monthly, drift$full$t_nw)
say("  post-2015 BM: n=%d  월평균 %+.4f (연 %+.2f%%)  NW t %+.2f",
    drift$post2015$n, drift$post2015$mean_monthly, drift$post2015$ann_pct, drift$post2015$t_nw)
RES$bench_drift <- drift

# ── 2. 신호 구성: raw Q01 / 섹터+사이즈 중립 Q01 ─────────────────────────────
say("=== 2. 신호 구성 (raw Q01_EB vs 섹터+사이즈 중립 Q01) ===")
score_of <- function(f) {
  sc <- if (f %in% BASE$Factor_Name) BASE[Factor_Name == f, .(Date, Ticker, score = z)]
        else TUNED[Factor_Name == f, .(Date, Ticker, score = score)]
  merge(sc[!is.na(score)], UNIV, by = c("Date","Ticker"))
}
E <- merge(score_of("M01_PATHQ"), liq_dt, by = c("Date","Ticker"), all.x = TRUE)
E <- E[is.na(adv) | adv >= 2e8][, adv := NULL]
setorder(E, Date, -score); E[, rk := seq_len(.N), by = Date]
E <- E[Date %in% returns_dt$Date]
say("  eligible set(E, M01 base·유동성 2e8·유니버스): %d행 %d개월 월평균 %.1f종목",
    nrow(E), uniqueN(E$Date), E[, .N, by = Date][, mean(N)])

Q01 <- score_of("Q01_EB")[, .(Date, Ticker, q01 = score)]
Q01 <- merge(Q01, E[, .(Date, Ticker)], by = c("Date","Ticker"))
N <- merge(Q01, SEC, by = c("Date","Ticker"), all.x = TRUE)
N <- merge(N, SIZEP, by = c("Date","Ticker"), all.x = TRUE)
N[is.na(Sector), Sector := "UNKNOWN"]
N[, lsz := ifelse(is.finite(Size) & Size > 0, log(Size), NA_real_)]
say("  중립화 입력 결측: Sector UNKNOWN %.2f%% · log(Size) NA %.2f%%",
    100*mean(N$Sector == "UNKNOWN"), 100*mean(!is.finite(N$lsz)))
N[, q01_n := { ok <- is.finite(q01) & is.finite(lsz)
  r <- rep(NA_real_, .N)
  if (sum(ok) >= 30L && uniqueN(Sector[ok]) >= 2L)
    r[ok] <- residuals(lm(q01[ok] ~ lsz[ok] + factor(Sector[ok])))
  r }, by = Date]
say("  중립화 성공 %d행 / %d개월 (원 %d행)", sum(is.finite(N$q01_n)), uniqueN(N[is.finite(q01_n)]$Date), nrow(N))
say("  raw↔중립 월별 Spearman 중앙값 %.4f",
    N[is.finite(q01) & is.finite(q01_n), cor(q01, q01_n, method = "spearman"), by = Date][, median(V1)])
RES$neutralization <- list(
  rows_raw = nrow(N), rows_neutral = sum(is.finite(N$q01_n)),
  n_month = uniqueN(N[is.finite(q01_n)]$Date),
  sector_unknown_pct = 100*mean(N$Sector == "UNKNOWN"),
  logsize_na_pct = 100*mean(!is.finite(N$lsz)),
  spearman_raw_vs_neutral_median =
    N[is.finite(q01) & is.finite(q01_n), cor(q01, q01_n, method = "spearman"), by = Date][, median(V1)])

# ── 3. F1 사전 실측 — 중립화가 top-분위 β 갭을 닫는가 (B3 격리 조기 판별) ────
say("=== 3. F1 사전 실측 — trailing 60m PIT β (당월 미포함) ===")
RM <- merge(returns_dt, bench_dt, by = "Date")
dts <- sort(unique(E$Date))
beta_l <- vector("list", length(dts))
for (i in seq_along(dts)) {
  if (i <= 36L) next
  w <- RM[Date %in% dts[max(1L, i-60L):(i-1L)]]
  bb <- w[, { ok <- is.finite(Ret_1m) & is.finite(BM_Ret)
    if (sum(ok) >= 24L && var(BM_Ret[ok]) > 0) .(beta = cov(Ret_1m[ok], BM_Ret[ok])/var(BM_Ret[ok]))
    else .(beta = NA_real_) }, by = Ticker][is.finite(beta)]
  bb[, Date := dts[i]]; beta_l[[i]] <- bb[, .(Date, Ticker, beta)]
}
BETA <- rbindlist(beta_l)
say("  β 패널 %d행 / %d개월", nrow(BETA), uniqueN(BETA$Date))

gap_of <- function(dt, zcol) {
  D <- merge(dt[is.finite(get(zcol)), .(Date, Ticker, z = get(zcol))], BETA, by = c("Date","Ticker"))
  D[, q_rank := frank(z)/.N, by = Date]
  s <- D[, .(b_top = median(beta[q_rank > 0.8]), b_med = median(beta),
             b_top25 = { o <- order(-z); median(beta[o[seq_len(min(25L, .N))]]) }), by = Date]
  s <- s[is.finite(b_top) & is.finite(b_med)]
  list(beta_top_quintile = mean(s$b_top), beta_universe_median = mean(s$b_med),
       diff_quintile = mean(s$b_top - s$b_med), t_quintile = nw_t(s$b_top - s$b_med),
       ci_quintile = nw_ci(s$b_top - s$b_med),
       beta_top25 = mean(s$b_top25), diff_top25 = mean(s$b_top25 - s$b_med),
       t_top25 = nw_t(s$b_top25 - s$b_med), ci_top25 = nw_ci(s$b_top25 - s$b_med),
       n_month = nrow(s), series = s)
}
g_raw <- gap_of(N, "q01"); g_neu <- gap_of(N, "q01_n")
for (nm in c("raw","neutral")) {
  g <- if (nm == "raw") g_raw else g_neu
  say("  Q01 %-7s: 최상위분위 β %.3f vs 유니버스 %.3f  차 %+.3f (NW t %+.2f, CI[%+.3f,%+.3f]) | top-25 β %.3f 차 %+.3f (t %+.2f)",
      nm, g$beta_top_quintile, g$beta_universe_median, g$diff_quintile, g$t_quintile,
      g$ci_quintile[1], g$ci_quintile[2], g$beta_top25, g$diff_top25, g$t_top25)
}
# paired: 중립 − raw 의 top-분위 β 차이
mp <- merge(g_raw$series[, .(Date, raw_top = b_top, raw_t25 = b_top25)],
            g_neu$series[, .(Date, neu_top = b_top, neu_t25 = b_top25)], by = "Date")
mp[, `:=`(d_q = neu_top - raw_top, d_25 = neu_t25 - raw_t25)]
say("  paired Δβ(중립−raw): 최상위분위 %+.3f (NW t %+.2f) · top-25 %+.3f (NW t %+.2f)  n=%d",
    mean(mp$d_q), nw_t(mp$d_q), mean(mp$d_25), nw_t(mp$d_25), nrow(mp))
RES$F1_precheck <- list(
  raw = g_raw[setdiff(names(g_raw), "series")], neutral = g_neu[setdiff(names(g_neu), "series")],
  paired_dbeta_quintile = mean(mp$d_q), paired_dbeta_quintile_t = nw_t(mp$d_q),
  paired_dbeta_top25 = mean(mp$d_25), paired_dbeta_top25_t = nw_t(mp$d_25), n_month = nrow(mp))

# ── 4. drag 함의 크기 = |Δβ| × 실측 벤치 드리프트 ────────────────────────────
say("=== 4. drag 함의 크기 (측정 전 고정) ===")
mu_bm <- drift$full$mean_monthly
imp <- list(
  inherited_gap_0249 = list(dbeta = 0.249, ann_pct = 100*12*0.249*mu_bm),
  measured_top25     = list(dbeta = mean(mp$d_25), ann_pct = 100*12*mean(mp$d_25)*mu_bm),
  measured_quintile  = list(dbeta = mean(mp$d_q),  ann_pct = 100*12*mean(mp$d_q)*mu_bm))
for (k in names(imp)) say("  %-20s Δβ=%+.3f → 함의 연 %+.2f%%", k, imp[[k]]$dbeta, imp[[k]]$ann_pct)
RES$drag_implication <- imp

# ── 5. paired 검정력 — 무작위-교체 placebo 로 diff sd 실측 ───────────────────
say("=== 5. paired 검정력 (placebo 무작위-교체 — 판정 arm 미열람) ===")
RETM <- merge(returns_dt, bench_dt, by = "Date")[, act := Ret_1m - BM_Ret]
# 5-a. 두 top-25 바스켓의 실제 교체 규모 k (수익 미사용, 신호만)
top25 <- function(dt, zcol) dt[is.finite(get(zcol))][order(Date, -get(zcol)), head(.SD, 25L), by = Date, .SDcols = c("Ticker")]
t_raw <- top25(N, "q01"); t_neu <- top25(N, "q01_n")
ov <- merge(t_raw[, .(Date, Ticker, a = TRUE)], t_neu[, .(Date, Ticker, b = TRUE)],
            by = c("Date","Ticker"), all = TRUE)
kswap <- ov[, .(k = sum(is.na(b))), by = Date]     # raw 에는 있고 중립에는 없는 종목 수
say("  raw-top25 vs 중립-top25 교체 규모 k: 평균 %.2f / 25 (중앙 %.0f, 범위 %d~%d)",
    mean(kswap$k), median(kswap$k), min(kswap$k), max(kswap$k))
# 필터면(B5): 하위분위 제외 시 base top-25 에서 빠지는 종목 수
N[, `:=`(qr_raw = frank(q01)/.N), by = Date]
N[is.finite(q01_n), qr_neu := frank(q01_n)/.N, by = Date]
base25 <- E[order(Date, -score), head(.SD, 25L), by = Date, .SDcols = c("Ticker","score")]
ph <- merge(base25, N[, .(Date, Ticker, qr_raw, qr_neu)], by = c("Date","Ticker"), all.x = TRUE)
k_filt <- ph[, .(k_raw = sum(qr_raw <= 0.2, na.rm = TRUE), k_neu = sum(qr_neu <= 0.2, na.rm = TRUE)), by = Date]
say("  필터면 제거 종목수 k: raw q20 %.2f / 중립 q20 %.2f (of 25)", mean(k_filt$k_raw), mean(k_filt$k_neu))

placebo_sd <- function(k_mean, n_seed = 20L, pool_extra = 25L) {
  k <- max(1L, round(k_mean))
  ELIG <- merge(E[, .(Date, Ticker, score, rk)], RETM[, .(Date, Ticker, act)], by = c("Date","Ticker"))
  sds <- numeric(n_seed)
  for (s in seq_len(n_seed)) {
    set.seed(1000L + s)
    d <- ELIG[rk <= (25L + pool_extra)][, {
      base_ix <- which(rk <= 25L)
      if (length(base_ix) < 25L) .(diff = NA_real_) else {
        drop_ <- sample(base_ix, k)
        cand <- which(rk > 25L)
        addn <- head(cand[order(rk[cand])], k)
        if (length(addn) < k) .(diff = NA_real_) else
          .(diff = (sum(act[setdiff(base_ix, drop_)]) + sum(act[addn]))/25 - sum(act[base_ix])/25)
      }
    }, by = Date]
    sds[s] <- sd(d$diff, na.rm = TRUE)
  }
  list(k = k, sd_monthly = median(sds), sd_range = range(sds), n_seed = n_seed)
}
pl_basket <- placebo_sd(mean(kswap$k))
pl_filter <- placebo_sd(mean(k_filt$k_neu))
say("  placebo diff sd — 바스켓형(k=%d): %.5f (범위 %.5f~%.5f)", pl_basket$k, pl_basket$sd_monthly, pl_basket$sd_range[1], pl_basket$sd_range[2])
say("  placebo diff sd — 필터형(k=%d): %.5f (범위 %.5f~%.5f)", pl_filter$k, pl_filter$sd_monthly, pl_filter$sd_range[1], pl_filter$sd_range[2])

n_months <- uniqueN(N[is.finite(q01_n)]$Date)
req <- list(
  basket_paired = required_effect(n = n_months, sd_monthly = pl_basket$sd_monthly, design = "full"),
  filter_paired = required_effect(n = n_months, sd_monthly = pl_filter$sd_monthly, design = "full"),
  generic_25ew  = required_effect(n = n_months, design = "full"))
for (k in names(req)) say("  required_effect %-14s n=%d sd=%.5f → 필요 연 %+.2f%% (t=2.0, NW k=1.25)",
                          k, req[[k]]$n, req[[k]]$sd_monthly, 100*req[[k]]$required_annual)
RES$power_precheck <- list(k_swap_basket_mean = mean(kswap$k), k_filter_raw_mean = mean(k_filt$k_raw),
  k_filter_neutral_mean = mean(k_filt$k_neu), placebo_basket = pl_basket, placebo_filter = pl_filter,
  n_months = n_months,
  required_annual_pct = lapply(req, function(r) 100*r$required_annual))

# ── 6. 판정: 필요 vs 함의 ────────────────────────────────────────────────────
say("=== 6. 착수 전 판정 — 필요 효과 vs drag 함의 ===")
cmp <- data.table(
  form = c("B1 바스켓 paired (중립 top-25 vs raw top-25)",
           "B5 필터 paired (중립 q20 제외 vs base)"),
  required_ann_pct = c(100*req$basket_paired$required_annual, 100*req$filter_paired$required_annual),
  implied_ann_pct  = c(abs(imp$measured_top25$ann_pct), abs(imp$measured_top25$ann_pct)*mean(k_filt$k_neu)/25))
cmp[, ratio := implied_ann_pct/required_ann_pct]
cmp[, verdict := fifelse(ratio >= 1, "POWERED — paired 유지", "UNDERPOWERED — paired 착수 전 폐기")]
print(cmp)
RES$decision_table <- as.list(cmp)
RES$decision <- if (all(cmp$ratio < 1)) "ABANDON_PAIRED_SWITCH_TO_CROSS_SECTIONAL" else "KEEP_PAIRED"
say("★ 결정: %s", RES$decision)

saveRDS(list(N = N, BETA = BETA, E = E, returns_dt = returns_dt, bench_dt = bench_dt,
             liq_dt = liq_dt, kswap = kswap, k_filt = k_filt),
        file.path(OUT, "p0_panels.rds"))
write_json(RES, file.path(OUT, "precheck_p0.json"), pretty = TRUE, auto_unbox = TRUE, digits = NA)
say("=== P0 완료 → precheck_p0.json + p0_panels.rds ===")
