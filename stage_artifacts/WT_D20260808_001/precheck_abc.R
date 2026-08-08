# =============================================================================
# precheck_abc.R — WT-D20260808_001 착수 전 사전 확인 3건 (handoff 의무)
#   A) p_hit      : base M01 top-25 중 D03/Q01 하위분위 점유율 (≈0 이면 (b) 측정 전 폐기)
#   B) F4 killswitch: 경계 밴드(M01 rank 20~40) 내 D03/Q01 조건부 forward-active 기울기
#                     (<=0 이면 (a) 측정 전 기각 — 사전등록 조건, 사후 완화 금지)
#   C) 검정력     : 무작위-교체 null 로 paired diff sd 실측 → required_effect()
#
#   ★ 이 스크립트는 **성과 arm(D03/Q01 기준 제외필터)의 수익을 계산하지 않는다.**
#      C 의 sd 는 무작위 교체(placebo) 계열에서만 얻는다 — 사전등록 전 본판정 열람 방지.
#   PIT: 패널 = WT-009 산출 월말 신호(trailing only), 수익 = build_monthly_forward_returns 계약.
# 실행: Rscript -e 'source("stage_artifacts/WT_D20260808_001/precheck_abc.R")'
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
  library(sandwich); library(lmtest)
})
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260808_001")
IN9 <- file.path(ROOT, "stage_artifacts/WT_D20260802_009")
say <- function(fmt, ...) cat(sprintf(paste0("[pre] ", fmt, "\n"), ...))

source("02_Infrastructure/config.R")
source("02_Infrastructure/ramp/factor_validation.R")
source("02_Infrastructure/contracts/required_effect_size.R")

# ── 0. 입력 형태 실측 (규약: 첫 출력) ────────────────────────────────────────
BASE <- as.data.table(read_parquet(file.path(IN9, "base_panel.parquet")))[, Date := as.Date(Date)]
TUNED <- as.data.table(read_parquet(file.path(IN9, "tuned_panel.parquet")))[, Date := as.Date(Date)]
SIG <- sort(unique(BASE$Date))
say("INPUT base_panel nrow=%d 관측단위=MONTHLY n_month=%d 범위 %s~%s",
    nrow(BASE), uniqueN(BASE$Date), min(BASE$Date), max(BASE$Date))
say("INPUT tuned_panel nrow=%d 관측단위=MONTHLY n_month=%d 범위 %s~%s",
    nrow(TUNED), uniqueN(TUNED$Date), min(TUNED$Date), max(TUNED$Date))

RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
        col_select = c("Date", "Ticker", "Close", "Vol", "Size", "K200", "KQ150")))[, Date := as.Date(Date)]
say("INPUT RAWDATA nrow=%d 관측단위=DAILY n_day=%d 범위 %s~%s (월간 아님 — 계약함수 경유)",
    nrow(RAW), uniqueN(RAW$Date), min(RAW$Date), max(RAW$Date))
RAW[, ym := format(Date, "%Y-%m")]
MEND <- sort(RAW[, .(Date = max(Date)), by = ym]$Date)
RAWME <- RAW[Date %in% MEND]; rm(RAW); gc(verbose = FALSE)
sig_all <- MEND[MEND >= min(SIG)]
UNIV <- RAWME[(K200 == TRUE | KQ150 == TRUE), .(Date, Ticker)]

FWD_F <- file.path(OUT, "fwd_cache.rds")
if (file.exists(FWD_F)) { fwd <- readRDS(FWD_F); say("fwd 캐시 재사용") } else {
  t0 <- Sys.time(); fwd <- build_monthly_forward_returns(RAWME, sig_all)
  saveRDS(fwd, FWD_F); say("fwd 생성 %.1f분", as.numeric(difftime(Sys.time(), t0, units = "mins")))
}
returns_dt <- as.data.table(fwd$returns_dt)[, .(Date = as.Date(Date), Ticker, Ret_1m)]
bench_dt   <- as.data.table(fwd$bench_dt)[,   .(Date = as.Date(Date), BM_Ret)]
liq_dt     <- as.data.table(fwd$liq_dt)[,     .(Date = as.Date(Date), Ticker, adv)]
say("FWD returns nrow=%d 관측단위=MONTHLY n_month=%d 범위 %s~%s",
    nrow(returns_dt), uniqueN(returns_dt$Date), min(returns_dt$Date), max(returns_dt$Date))

nw_t <- function(x, lag = 3L) {
  x <- x[is.finite(x)]; if (length(x) < 12L) return(NA_real_)
  fit <- lm(x ~ 1)
  tryCatch(as.numeric(lmtest::coeftest(fit,
    vcov. = sandwich::NeweyWest(fit, lag = lag, prewhite = FALSE))[1, 3]), error = function(e) NA_real_)
}
score_of <- function(f) {
  sc <- if (f %in% BASE$Factor_Name) BASE[Factor_Name == f, .(Date, Ticker, score = z)]
        else TUNED[Factor_Name == f, .(Date, Ticker, score = score)]
  merge(sc[!is.na(score)], UNIV, by = c("Date", "Ticker"))
}

# ── 1. eligible set (canonical_screen_bt 선택 규칙과 동일) ───────────────────
SC_M01 <- score_of("M01_PATHQ")
E <- merge(SC_M01, liq_dt, by = c("Date", "Ticker"), all.x = TRUE)
E <- E[is.na(adv) | adv >= 2e8][, adv := NULL]
setorder(E, Date, -score)
E[, rk := seq_len(.N), by = Date]
E[, n_elig := .N, by = Date]
E <- E[Date %in% returns_dt$Date]     # forward 수익 존재 월만
say("eligible(M01+유동성): %d행 / %d개월 / 월평균 %.1f종목",
    nrow(E), uniqueN(E$Date), E[, .N, by = Date][, mean(N)])

FILT <- c("D03_EWMA", "Q01_EB")
FZ <- rbindlist(lapply(FILT, function(f) score_of(f)[, .(Date, Ticker, fz = score, F_ = f)]))
EF <- merge(E, FZ, by = c("Date", "Ticker"), allow.cartesian = TRUE)
# 분위점은 eligible set 내 해당 팩터 가용분 기준 (사전등록)
EF[, q_rank := frank(fz) / .N, by = .(Date, F_)]

cov_tab <- EF[, .(n_f = .N), by = .(Date, F_)]
cov_tab <- merge(cov_tab, E[, .(n_e = .N), by = Date], by = "Date")
say("필터팩터 커버리지(eligible 대비): %s",
    paste(sapply(FILT, function(f)
      sprintf("%s=%.3f (n_month %d)", f, cov_tab[F_ == f, mean(n_f / n_e)], cov_tab[F_ == f, .N])),
      collapse = " / "))

# ── A) p_hit ─────────────────────────────────────────────────────────────────
say("=== A) p_hit — base M01 top-25 중 필터 하위분위 점유 ===")
TOP <- E[rk <= 25L]
TF <- merge(TOP, EF[, .(Date, Ticker, F_, q_rank)], by = c("Date", "Ticker"), allow.cartesian = TRUE)
p_hit_tab <- rbindlist(lapply(c(0.10, 0.20, 0.30), function(q) {
  TF[, .(q = q, k = sum(q_rank <= q), n_top = .N), by = .(Date, F_)][
     , .(k_mean = mean(k), k_median = median(k), k_max = max(k),
         p_hit = mean(k) / 25, month_share_k_ge1 = mean(k >= 1), month_share_k_ge2 = mean(k >= 2),
         n_month = .N), by = .(F_, q)]
}))
print(p_hit_tab[order(F_, q)])
say("필터팩터 결측 종목(top-25 내, 제외 대상 아님으로 처리): %s",
    paste(sapply(FILT, function(f) sprintf("%s=%.4f", f,
      1 - nrow(TF[F_ == f]) / nrow(TOP))), collapse = " / "))

# ── B) F4 killswitch — 밴드(rank 20~40) 내 조건부 기울기 ─────────────────────
say("=== B) F4 — 경계 밴드 rank 20~40 내 조건부 forward-active 기울기 ===")
RB <- merge(returns_dt, bench_dt, by = "Date")[, .(Date, Ticker, act = Ret_1m - BM_Ret)]
BAND <- E[rk >= 20L & rk <= 40L]
BANDR <- merge(BAND, RB, by = c("Date", "Ticker"))
say("밴드 관측: %d행 / %d개월 / 월평균 %.1f종목", nrow(BANDR), uniqueN(BANDR$Date),
    BANDR[, .N, by = Date][, mean(N)])

fmb_slope <- function(dt, xcol) {
  s <- dt[, {
    x <- get(xcol); y <- act
    ok <- is.finite(x) & is.finite(y)
    if (sum(ok) >= 8L && sd(x[ok]) > 1e-8) {
      xz <- (x[ok] - mean(x[ok])) / sd(x[ok])
      .(b = unname(coef(lm(y[ok] ~ xz))[2]), n = sum(ok))
    } else .(b = NA_real_, n = sum(ok))
  }, by = Date]
  s <- s[is.finite(b)]
  list(n_month = nrow(s), mean_b = mean(s$b), t_nw = nw_t(s$b), series = s)
}
band_res <- list()
for (f in FILT) {
  B2 <- merge(BANDR, EF[F_ == f, .(Date, Ticker, fz)], by = c("Date", "Ticker"))
  r <- fmb_slope(B2, "fz")
  band_res[[f]] <- r
  say("  밴드 %s 기울기: 월평균 %+.4f (연 %+.2f%%/1sd) NW t=%+.2f n=%d",
      f, r$mean_b, r$mean_b * 12 * 100, r$t_nw, r$n_month)
}
# 대조: 밴드 내 M01 자기 기울기 (타이브레이커가 덮어쓰는 대상)
B_M01 <- copy(BANDR)[, m01_in_band := score]
r_m01 <- fmb_slope(B_M01, "m01_in_band")
band_res[["M01_PATHQ_selfslope"]] <- r_m01
say("  밴드 M01 자기 기울기(덮어쓰기 대가): 월평균 %+.4f (연 %+.2f%%/1sd) NW t=%+.2f n=%d",
    r_m01$mean_b, r_m01$mean_b * 12 * 100, r_m01$t_nw, r_m01$n_month)
for (f in FILT) {
  kill <- !is.finite(band_res[[f]]$mean_b) || band_res[[f]]$mean_b <= 0
  say("  F4 판정 (a)-%s : %s", f, if (kill) "KILL (밴드 기울기 <= 0 — 사전등록 조건)" else "PASS (측정 진행 자격)")
}

# ── B2) F1 부수관측 — 신호 자기-분위 조건부 forward-active 곡선 (기전 판별) ──
say("=== B2) F1 — 팩터 자기-분위 조건부 active (좌측 국소화 여부) ===")
EFR <- merge(EF, RB, by = c("Date", "Ticker"))
EFR[, qb := cut(q_rank, breaks = c(0, .2, .4, .6, .8, 1), labels = c("Q1_low","Q2","Q3","Q4","Q5_high"),
                include.lowest = TRUE)]
f1 <- EFR[, .(act_m = mean(act)), by = .(Date, F_, qb)]
f1w <- dcast(f1, Date + F_ ~ qb, value.var = "act_m")
f1_tab <- rbindlist(lapply(FILT, function(f) {
  d <- f1w[F_ == f]
  data.table(F_ = f,
    Q1_low = 100 * 12 * mean(d$Q1_low, na.rm = TRUE), Q3 = 100 * 12 * mean(d$Q3, na.rm = TRUE),
    Q5_high = 100 * 12 * mean(d$Q5_high, na.rm = TRUE),
    Q1_minus_Q3_ann = 100 * 12 * mean(d$Q1_low - d$Q3, na.rm = TRUE),
    Q1_minus_Q3_t = nw_t(d$Q1_low - d$Q3),
    Q5_minus_Q3_ann = 100 * 12 * mean(d$Q5_high - d$Q3, na.rm = TRUE),
    Q5_minus_Q3_t = nw_t(d$Q5_high - d$Q3), n_month = nrow(d))
}))
print(f1_tab)

# ── C) 검정력 — 무작위 교체 null 로 paired diff sd 실측 ─────────────────────
say("=== C) 검정력 — 무작위 교체 placebo 로 paired diff sd 실측 ===")
port_from_w <- function(W, cost_bps = 15) {
  WR <- merge(W, returns_dt, by = c("Date", "Ticker"), all.x = TRUE)
  WR[is.na(Ret_1m), Ret_1m := 0]
  port <- WR[, .(port_gross = sum(w * Ret_1m)), by = Date]
  dts <- sort(unique(W$Date)); traded <- numeric(length(dts)); names(traded) <- as.character(dts)
  prev <- data.table(Ticker = character(0), w = numeric(0))
  for (i in seq_along(dts)) {
    cur <- W[Date == dts[i], .(Ticker, w)]
    m <- merge(cur, prev, by = "Ticker", all = TRUE, suffixes = c("_cur","_prev"))
    m[is.na(w_cur), w_cur := 0]; m[is.na(w_prev), w_prev := 0]
    traded[i] <- sum(abs(m$w_cur - m$w_prev)); prev <- cur
  }
  port[, traded := traded[as.character(Date)]]
  port[, ret_net := port_gross - traded * cost_bps / 1e4]
  setorder(port, Date); port[]
}
W_BASE <- E[rk <= 25L, .(Date, Ticker, w = 1/25)]
P_BASE <- port_from_w(W_BASE)
say("base(M01 top-25) 월수 %d / net 연평균 %+.2f%% / turnover %.2f/yr",
    nrow(P_BASE), 100 * 12 * mean(P_BASE$ret_net), 12 * mean(P_BASE$traded))

# 월별 교체 규모 k = 사전등록 q=0.20 의 실측 k (팩터별) — 그 규모로 무작위 교체
k_tab <- TF[, .(k = sum(q_rank <= 0.20)), by = .(Date, F_)]
placebo_sd <- function(f, seeds = 20L) {
  kk <- k_tab[F_ == f]
  sds <- numeric(seeds)
  for (s in seq_len(seeds)) {
    set.seed(1000L + s)
    Wp <- E[, {
      kd <- kk[Date == .BY$Date, k]; kd <- if (length(kd) == 0) 0L else kd[1]
      top <- Ticker[rk <= 25L]
      pool <- Ticker[rk > 25L]
      kd <- min(kd, length(top), length(pool))
      if (kd > 0L) {
        drop <- sample(top, kd)
        keep <- setdiff(top, drop)
        add <- pool[seq_len(kd)]           # M01 차순위로 충원 (필터 arm 과 동일 충원 규칙)
        tk <- c(keep, add)
      } else tk <- top
      .(Ticker = tk, w = rep(1/length(tk), length(tk)))
    }, by = Date]
    Pp <- port_from_w(Wp)
    d <- merge(P_BASE[, .(Date, b = ret_net)], Pp[, .(Date, p = ret_net)], by = "Date")
    sds[s] <- sd(d$p - d$b)
  }
  sds
}
pw <- list()
for (f in FILT) {
  sds <- placebo_sd(f)
  n_m <- nrow(P_BASE)
  req <- required_effect(n = n_m, t_threshold = 2.0, sd_monthly = median(sds), design = "full")
  pw[[f]] <- list(placebo_sd_median = median(sds), placebo_sd_range = range(sds),
                  n_months = n_m, required_monthly = req$required_monthly,
                  required_annual = req$required_annual,
                  k_mean = k_tab[F_ == f, mean(k)])
  say("  %s: 교체규모 k 평균 %.2f/25 · placebo diff sd(월) %.5f [%.5f, %.5f] · n=%d",
      f, k_tab[F_ == f, mean(k)], median(sds), min(sds), max(sds), n_m)
  say("     → t=2.0 도달 필요 효과: 월 %+.4f = 연 %+.2f%%  (25EW 쌍 기본 sd 대비 %.2f배 유리)",
      req$required_monthly, 100 * req$required_annual, SPREAD_SD_MONTHLY_25EW / median(sds))
}
req_default <- required_effect(n = nrow(P_BASE), design = "full")
say("  [대조] 무관 25EW 쌍 기본 sd 0.0394 기준 필요 연효과 %+.2f%% (본 설계는 paired 라 훨씬 유리)",
    100 * req_default$required_annual)

saveRDS(list(p_hit = p_hit_tab, band = band_res, f1 = f1_tab, power = pw,
             base_port = P_BASE, k_tab = k_tab, cov_tab = cov_tab),
        file.path(OUT, "precheck_results.rds"))
say("=== 사전 확인 3건 완료 → precheck_results.rds ===")
