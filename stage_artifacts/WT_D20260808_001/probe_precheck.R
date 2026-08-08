# =============================================================================
# probe_precheck.R — FQ-122 착수 전 사전 확인 3건 + 반증 관측 F1/F3/F4
#   alpha_hypothesis.json handoff.next_steps 가 명령한 3건:
#     ① p_hit  : base(M01_PATHQ) top-25 중 D03/Q01 하위분위 점유율 — ≈0 이면 (b) 측정 전 폐기
#     ② F4     : 경계 밴드(M01 rank 20~40) 내 D03/Q01 조건부 forward-active 기울기
#                — ≤0 이면 (a) 측정 전 기각 (사전 킬스위치)
#     ③ 검정력 : paired diff sd 를 **무작위-제외 플라시보**로 추정(효과 미열람) 후
#                required_effect() 로 필요 효과크기 고정 → 사전등록에 기입
#   부수 반증 관측: F1(좌측-국소화) / F3(최상위 분위 β)
#   라벨: metric_type = precheck_diag (성과 주장 아님 · 선택 비사용)
# 실행: Rscript -e 'source("stage_artifacts/WT_D20260808_001/probe_precheck.R")'
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
  library(sandwich); library(lmtest)
})
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260808_001")
say <- function(fmt, ...) cat(sprintf(paste0("[pc] ", fmt, "\n"), ...))
`%||%` <- function(a, b) if (is.null(a)) b else a

source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/ramp/factor_validation.R")   # build_monthly_forward_returns (계약 파생수익)
source("02_Infrastructure/contracts/required_effect_size.R")

nw_t <- function(x, lag = 3L) {
  x <- x[is.finite(x)]
  if (length(x) < 12L) return(NA_real_)
  fit <- lm(x ~ 1)
  tryCatch(as.numeric(lmtest::coeftest(fit,
      vcov. = sandwich::NeweyWest(fit, lag = lag, prewhite = FALSE))[1, 3]),
    error = function(e) NA_real_)
}

# ── 0. 입력 실측 인쇄 (첫 출력 = 입력 형태) ──────────────────────────────────
TUNED <- as.data.table(read_parquet("stage_artifacts/WT_D20260802_009/tuned_panel.parquet"))
TUNED[, Date := as.Date(Date)]
say("INPUT tuned_panel: rows=%d · 관측단위=월간(월말 거래일) · %s ~ %s · 팩터 %d종",
    nrow(TUNED), as.character(min(TUNED$Date)), as.character(max(TUNED$Date)),
    uniqueN(TUNED$Factor_Name))

RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
        col_select = c("Date", "Ticker", "Close", "Vol", "Size", "K200", "KQ150")))
RAW[, Date := as.Date(Date)]; RAW[, ym := format(Date, "%Y-%m")]
MEND <- sort(RAW[, .(Date = max(Date)), by = ym]$Date)
RAWME <- RAW[Date %in% MEND]
rm(RAW); gc(verbose = FALSE)
SIG <- sort(unique(TUNED$Date))
sig_all <- MEND[MEND >= min(SIG)]
UNIV <- RAWME[(K200 == TRUE | KQ150 == TRUE), .(Date, Ticker)]
say("INPUT RAWME 월말: %d월 · UNIV(K200∪KQ150) 월평균 %.0f종목",
    length(MEND), UNIV[, .N, by = Date][, mean(N)])

fwd <- build_monthly_forward_returns(RAWME, sig_all)
returns_dt <- fwd$returns_dt[, .(Date = as.Date(Date), Ticker, Ret_1m)]
bench_dt   <- fwd$bench_dt[,   .(Date = as.Date(Date), BM_Ret)]
liq_dt     <- fwd$liq_dt[,     .(Date = as.Date(Date), Ticker, adv)]
say("INPUT returns_dt rows=%d (Date=신호월말, Ret_1m=익월 수익) · bench %d월",
    nrow(returns_dt), nrow(bench_dt))

# ── 1. 유니버스 제한 + 유동성 필터 후 후보 패널 (base 선별과 동일 규격) ──────
W <- dcast(TUNED[Factor_Name %in% c("M01_PATHQ", "D03_EWMA", "Q01_EB")],
           Date + Ticker ~ Factor_Name, value.var = "score")
W <- merge(W, UNIV, by = c("Date", "Ticker"))
W <- merge(W, liq_dt, by = c("Date", "Ticker"), all.x = TRUE)
W <- W[is.na(adv) | adv >= 2e8]
W <- merge(W, returns_dt, by = c("Date", "Ticker"), all.x = TRUE)
W <- merge(W, bench_dt, by = "Date", all.x = TRUE)
W[, act := Ret_1m - BM_Ret]
CAND <- W[is.finite(M01_PATHQ)]
say("후보 패널(M01 유효·유니버스·유동성): rows=%d · %d월 · 월중앙 %d종목",
    nrow(CAND), uniqueN(CAND$Date), CAND[, .N, by = Date][, as.integer(median(N))])
say("  월별 D03 유효 중앙 %d / Q01 유효 중앙 %d",
    CAND[, sum(is.finite(D03_EWMA)), by = Date][, as.integer(median(V1))],
    CAND[, sum(is.finite(Q01_EB)), by = Date][, as.integer(median(V1))])

TOP_N <- 25L
CAND[, rk_m01 := frank(-M01_PATHQ, ties.method = "first"), by = Date]

# ── 2. ① p_hit — base top-25 중 D03/Q01 하위분위 점유율 ─────────────────────
qs <- c(0.10, 0.20, 0.30)
phit_rows <- list()
for (f in c("D03_EWMA", "Q01_EB")) for (q in qs) {
  D <- CAND[is.finite(get(f))]
  D[, thr := quantile(get(f), q, type = 7, na.rm = TRUE), by = Date]
  D[, is_low := get(f) <= thr]
  mm <- D[, .(n_top = sum(rk_m01 <= TOP_N),
              n_hit = sum(rk_m01 <= TOP_N & is_low)), by = Date][n_top >= 20L]
  phit_rows[[paste(f, q)]] <- data.table(
    factor = f, q = q, n_months = nrow(mm),
    p_hit_mean = mean(mm$n_hit / mm$n_top),
    hits_per_month_mean = mean(mm$n_hit),
    months_with_0hit = sum(mm$n_hit == 0),
    hits_max = max(mm$n_hit))
}
PHIT <- rbindlist(phit_rows)
say("① p_hit (base M01 top-25 중 하위분위 점유):")
print(PHIT)

# ── 3. F1 — 좌측-국소화 (자기 분위별 forward active) ────────────────────────
f1_rows <- list()
for (f in c("D03_EWMA", "Q01_EB")) {
  D <- CAND[is.finite(get(f)) & is.finite(act)]
  D[, qq := cut(frank(get(f)) / .N, breaks = seq(0, 1, 0.2),
                labels = paste0("Q", 1:5), include.lowest = TRUE), by = Date]
  prof <- D[, .(m = mean(act)), by = .(Date, qq)]
  wide <- dcast(prof, Date ~ qq, value.var = "m")
  # 하위 20%(Q1) vs 중앙(Q3)
  d_low_mid <- wide$Q1 - wide$Q3
  f1_rows[[f]] <- data.table(
    factor = f, n_months = sum(is.finite(d_low_mid)),
    Q1_mean_act = mean(wide$Q1, na.rm = TRUE), Q3_mean_act = mean(wide$Q3, na.rm = TRUE),
    Q5_mean_act = mean(wide$Q5, na.rm = TRUE),
    d_Q1_minus_Q3 = mean(d_low_mid, na.rm = TRUE), t_Q1_minus_Q3 = nw_t(d_low_mid),
    d_Q5_minus_Q3 = mean(wide$Q5 - wide$Q3, na.rm = TRUE),
    t_Q5_minus_Q3 = nw_t(wide$Q5 - wide$Q3))
}
F1 <- rbindlist(f1_rows)
say("F1 좌측-국소화 (자기 분위 forward active, Q1=하위20%%):")
print(F1)

# ── 4. F3 — 최상위 분위 β (D03 초저변동 꼬리의 β-drag 경로) ─────────────────
#   β = 종목 월수익 ~ BM_Ret 회귀 기울기 (전표본 pooled, 분위 소속 월만)
f3_rows <- list()
for (f in c("D03_EWMA", "Q01_EB")) {
  D <- CAND[is.finite(get(f)) & is.finite(Ret_1m) & is.finite(BM_Ret)]
  D[, qq := cut(frank(get(f)) / .N, breaks = seq(0, 1, 0.2),
                labels = paste0("Q", 1:5), include.lowest = TRUE), by = Date]
  bq <- D[, {
    fit <- lm(Ret_1m ~ BM_Ret)
    .(beta = as.numeric(coef(fit)[2]), n = .N)
  }, by = qq][order(qq)]
  bq[, factor := f]
  f3_rows[[f]] <- bq
}
F3 <- rbindlist(f3_rows)
say("F3 분위별 β (pooled Ret_1m ~ BM_Ret):"); print(F3)

# ── 5. ② F4 — 경계 밴드(M01 rank 20~40) 내 조건부 기울기 (사전 킬스위치) ────
BAND <- CAND[rk_m01 >= 20L & rk_m01 <= 40L & is.finite(act)]
say("② F4 밴드 패널: rows=%d · %d월 · 월평균 %.1f종목",
    nrow(BAND), uniqueN(BAND$Date), nrow(BAND) / uniqueN(BAND$Date))
f4_rows <- list()
for (f in c("D03_EWMA", "Q01_EB", "M01_PATHQ")) {
  D <- BAND[is.finite(get(f))]
  # 월별 밴드-내 표준화 후 월별 기울기 → 월계열 NW t (Fama-MacBeth 형)
  D[, xz := { s <- sd(get(f)); if (!is.finite(s) || s <= 0) NA_real_ else (get(f) - mean(get(f))) / s }, by = Date]
  sl <- D[is.finite(xz), {
    if (.N < 8L) .(b = NA_real_) else {
      fit <- lm(act ~ xz); .(b = as.numeric(coef(fit)[2]))
    }
  }, by = Date]
  f4_rows[[f]] <- data.table(factor = f, n_months = sum(is.finite(sl$b)),
    slope_monthly = mean(sl$b, na.rm = TRUE), slope_t_nw = nw_t(sl$b),
    slope_annual_pct = 100 * 12 * mean(sl$b, na.rm = TRUE))
}
F4 <- rbindlist(f4_rows)
say("② F4 밴드-내 조건부 기울기 (월별 FM, 밴드-내 z 1sd 당 월 active):")
print(F4)

# ── 6. ③ 검정력 — 무작위-제외 플라시보로 paired diff sd 추정 (효과 미열람) ──
#   실제 필터 arm 은 열지 않는다. 월별 '제외 개수'만 실제와 동일하게 맞춘 무작위 제외로
#   paired active diff 계열을 만들고 그 sd 를 쓴다 (sd 는 방해모수 — 효과와 무관).
build_base_picks <- function(dt, n_top = TOP_N) {
  setorder(dt, Date, -M01_PATHQ)
  dt[, .(Ticker = Ticker[seq_len(min(n_top, .N))],
         w = rep(1 / min(n_top, .N), min(n_top, .N))), by = Date]
}
port_active <- function(picks) {
  m <- merge(picks, CAND[, .(Date, Ticker, Ret_1m, BM_Ret)], by = c("Date", "Ticker"))
  m <- m[is.finite(Ret_1m) & is.finite(BM_Ret)]
  m[, .(pr = sum(w * Ret_1m) / sum(w), bm = BM_Ret[1]), by = Date][, .(Date, act = pr - bm)]
}
base_picks <- build_base_picks(copy(CAND))
base_act <- port_active(base_picks)
say("base(M01 top-25 EW, gross-of-cost) 월수 %d · 평균 active %+.4f/월",
    nrow(base_act), mean(base_act$act))

# 실제 제외 개수 프로파일 (q=0.20 기준, 두 팩터)
excl_profile <- function(f, q = 0.20) {
  D <- CAND[is.finite(get(f))]
  D[, thr := quantile(get(f), q, type = 7, na.rm = TRUE), by = Date]
  D[get(f) <= thr, .(Date, Ticker)]
}
set.seed(20260808L)
sd_rows <- list()
for (f in c("D03_EWMA", "Q01_EB")) {
  EX <- excl_profile(f, 0.20)
  nex <- merge(base_picks[, .(Date, Ticker)], EX, by = c("Date", "Ticker"))[, .N, by = Date]
  nex_map <- setNames(nex$N, as.character(nex$Date))
  diffs <- list()
  for (s in 1:8) {
    keep <- CAND[, {
      k <- nex_map[as.character(.BY$Date)]; k <- if (is.na(k)) 0L else as.integer(k)
      # base top-25 중 무작위 k개를 '제외 대상'으로 지정 → 그 다음 순위로 대체
      tops <- Ticker[order(-M01_PATHQ)]
      drop <- if (k > 0 && length(tops) > TOP_N) sample(tops[seq_len(TOP_N)], k) else character(0)
      sel <- setdiff(tops, drop)[seq_len(min(TOP_N, length(tops) - length(drop)))]
      .(Ticker = sel, w = rep(1 / length(sel), length(sel)))
    }, by = Date]
    pa <- port_active(keep)
    d <- merge(base_act, pa, by = "Date", suffixes = c("_b", "_p"))
    diffs[[s]] <- data.table(seed = s, sd_d = sd(d$act_p - d$act_b), n = nrow(d))
  }
  DS <- rbindlist(diffs)
  sd_rows[[f]] <- data.table(factor = f, n_months = DS$n[1],
    sd_diff_median = median(DS$sd_d), sd_diff_min = min(DS$sd_d), sd_diff_max = max(DS$sd_d),
    excl_hits_per_month = mean(nex$N))
}
SDT <- rbindlist(sd_rows)
say("③ 플라시보 기반 paired diff sd (무작위 제외, 8 seed — 실제 효과 미열람):")
print(SDT)

POW <- SDT[, {
  r <- required_effect(n = n_months, t_threshold = 2.0, sd_monthly = sd_diff_median,
                       design = "full")
  .(factor = factor, n = n_months, sd_used = sd_diff_median,
    required_monthly = r$required_monthly, required_annual_pct = 100 * r$required_annual)
}, by = seq_len(nrow(SDT))][, seq_len := NULL][]
say("③ required_effect (t=2.0, design=full, NW팽창 1.25):")
print(POW)
say("   대조 — 무작위 top-25 쌍 sd 0.0394 기준 필요 연효과: %+.2f%%",
    100 * required_effect(n = SDT$n_months[1], design = "full")$required_annual)

saveRDS(list(PHIT = PHIT, F1 = F1, F3 = F3, F4 = F4, SDT = SDT, POW = POW,
             base_act = base_act, n_months = nrow(base_act)),
        file.path(OUT, "probe_precheck.rds"))
say("저장: probe_precheck.rds — 완료")
