# =============================================================================
# run_fu_task2_f2.R — verification_followup ② F2(개인 순매수 집중) 재측정
#
# 적대검증 주장: D03 의 F2 연관은 두 축에서 각각 소멸한다 —
#   (i) 회전율 통제(log 거래대금) 추가 시 t −4.29 → −0.78
#   (ii) 횡단면 순위변환 시 → −0.55
#   반면 Q01 은 강화(−5.39).
# 본 재측정: nb/Size 를 1%/99% 윈저화 + 회전율 통제 포함 사양으로 확정/철회 판정.
#
# ★설계 주의: nb_norm = 월간 개인 순매수 / 시총 은 꼬리가 극단이라(비율 변수)
#   월별 횡단면 회귀가 소수 관측에 지배될 수 있다 → 윈저화가 1차 통제.
#   회전율은 두 정의를 모두 잰다: log(adv 20일) · log(월간 거래대금/시총).
#
# 실행: Rscript -e 'source("stage_artifacts/WT_D20260808_001/verification_followup/run_fu_task2_f2.R")'
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(sandwich); library(lmtest)
})
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260808_001")
FU  <- file.path(OUT, "verification_followup")
IN9 <- file.path(ROOT, "stage_artifacts/WT_D20260802_009")
say <- function(fmt, ...) cat(sprintf(paste0("[fu2] ", fmt, "\n"), ...))
FILT <- c("D03_EWMA", "Q01_EB")

nw_t <- function(x, lag = 3L) {
  x <- x[is.finite(x)]; if (length(x) < 12L) return(NA_real_)
  fit <- lm(x ~ 1)
  tryCatch(as.numeric(lmtest::coeftest(fit, vcov. = sandwich::NeweyWest(fit, lag = lag, prewhite = FALSE))[1,3]),
           error = function(e) NA_real_)
}
nw_ci <- function(x, lag = 3L) {
  x <- x[is.finite(x)]; if (length(x) < 12L) return(c(NA_real_, NA_real_))
  fit <- lm(x ~ 1)
  se <- tryCatch(sqrt(sandwich::NeweyWest(fit, lag = lag, prewhite = FALSE)[1,1]), error = function(e) NA_real_)
  mean(x) + c(-1,1) * qt(0.975, df = length(x) - 1L) * se
}
acf_r1 <- function(x) { x <- x[is.finite(x)]; acf(x, lag.max = 1, plot = FALSE)$acf[2] }
wins <- function(v, p = 0.01) { q <- quantile(v, c(p, 1-p), na.rm = TRUE); pmin(pmax(v, q[1]), q[2]) }
zs <- function(v) (v - mean(v)) / sd(v)
rk <- function(v) { r <- frank(v)/length(v); (r - mean(r))/sd(r) }   # 횡단면 순위 → 표준화

# ── 0. 입력 실측 ─────────────────────────────────────────────────────────────
BASE <- as.data.table(read_parquet(file.path(IN9, "base_panel.parquet")))[, Date := as.Date(Date)]
TUNED <- as.data.table(read_parquet(file.path(IN9, "tuned_panel.parquet")))[, Date := as.Date(Date)]
RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
        col_select = c("Date","Ticker","Close","Vol","Size","K200","KQ150")))[, Date := as.Date(Date)]
say("INPUT RAWDATA nrow=%d DAILY n_day=%d %s~%s", nrow(RAW), uniqueN(RAW$Date), min(RAW$Date), max(RAW$Date))
RAW[, ym := format(Date, "%Y-%m")]
RAW[, val := Vol * Close]
# 월간 거래대금 (회전율 분자) — 일간에서 집계
VALM <- RAW[, .(val_m = sum(val, na.rm = TRUE), n_day = .N), by = .(ym, Ticker)]
MEND <- sort(RAW[, .(Date = max(Date)), by = ym]$Date)
RAWME <- RAW[Date %in% MEND, .(Date, ym, Ticker, Size, K200, KQ150)]; rm(RAW); gc(verbose = FALSE)
UNIV <- RAWME[(K200 == TRUE | KQ150 == TRUE), .(Date, Ticker)]
SIZE <- RAWME[, .(Date, ym, Ticker, Size)]
say("월간 거래대금 패널 %d행 · %d개월", nrow(VALM), uniqueN(VALM$ym))

fwd <- readRDS(file.path(OUT, "fwd_cache.rds"))
returns_dt <- as.data.table(fwd$returns_dt)[, .(Date = as.Date(Date), Ticker, Ret_1m)]
liq_dt <- as.data.table(fwd$liq_dt)[, .(Date = as.Date(Date), Ticker, adv)]

score_of <- function(f) {
  sc <- if (f %in% BASE$Factor_Name) BASE[Factor_Name == f, .(Date, Ticker, score = z)]
        else TUNED[Factor_Name == f, .(Date, Ticker, score = score)]
  merge(sc[!is.na(score)], UNIV, by = c("Date","Ticker"))
}
E <- merge(score_of("M01_PATHQ"), liq_dt, by = c("Date","Ticker"), all.x = TRUE)
E <- E[is.na(adv) | adv >= 2e8][, adv := NULL]
E <- E[Date %in% returns_dt$Date]
FZ <- rbindlist(lapply(FILT, function(f) score_of(f)[, .(Date, Ticker, fz = score, F_ = f)]))
FZ <- merge(FZ, E[, .(Date, Ticker)], by = c("Date","Ticker"))
say("eligible %d행 / %d개월", nrow(E), uniqueN(E$Date))

IND <- as.data.table(read_parquet(".cache/investor_stock/investor_individual.parquet",
        col_select = c("Date","Ticker","NetBuy")))[, Date := as.Date(Date)]
say("INPUT investor_individual nrow=%d DAILY n_day=%d %s~%s", nrow(IND), uniqueN(IND$Date),
    min(IND$Date), max(IND$Date))
IND[, ym := format(Date, "%Y-%m")]
INM <- IND[, .(nb = sum(NetBuy, na.rm = TRUE)), by = .(ym, Ticker)]; rm(IND); gc(verbose = FALSE)

# 월말 신호일 ↔ 같은 달 개인 순매수 (원 측정과 동일 매핑 — 동시기 연관 진단)
P <- merge(SIZE[Date %in% unique(E$Date)], INM, by = c("ym","Ticker"))
P <- merge(P, VALM[, .(ym, Ticker, val_m)], by = c("ym","Ticker"), all.x = TRUE)
P <- merge(P, liq_dt, by = c("Date","Ticker"), all.x = TRUE)
P <- P[is.finite(Size) & Size > 0]
P[, `:=`(nb_norm = nb/Size, lsz = log(Size),
         ladv = ifelse(is.finite(adv) & adv > 0, log(adv), NA_real_),
         lturn = ifelse(is.finite(val_m) & val_m > 0, log(val_m/Size), NA_real_))]
say("F2 패널 %d행 · %d개월 · ladv 결측 %.2f%% · lturn 결측 %.2f%%",
    nrow(P), uniqueN(P$Date), 100*mean(is.na(P$ladv)), 100*mean(is.na(P$lturn)))
say("nb_norm 분포: q01 %.3e · med %.3e · q99 %.3e · |극단|비 %.1f",
    quantile(P$nb_norm, .01, na.rm=TRUE), median(P$nb_norm, na.rm=TRUE),
    quantile(P$nb_norm, .99, na.rm=TRUE),
    max(abs(P$nb_norm), na.rm=TRUE)/quantile(abs(P$nb_norm), .99, na.rm=TRUE))
say("상관 실측 (전 패널): cor(lturn, ladv)=%.3f · cor(lturn, lsz)=%.3f",
    cor(P$lturn, P$ladv, use = "complete.obs"), cor(P$lturn, P$lsz, use = "complete.obs"))

# ── 1. 사양별 FMB ────────────────────────────────────────────────────────────
# 사양 정의 (전부 월별 횡단면 회귀 → 계수 계열의 NW lag-3 t; 창 비겹침이라 lag-3 적정)
SPECS <- list(
  M0_raw            = list(y = "z",     x = "z",  ctl = character(0)),
  M1_wins           = list(y = "wz",    x = "z",  ctl = character(0)),
  M2_wins_size      = list(y = "wz",    x = "z",  ctl = c("lsz")),
  M3_wins_size_adv  = list(y = "wz",    x = "z",  ctl = c("lsz","ladv")),
  M4_wins_size_turn = list(y = "wz",    x = "z",  ctl = c("lsz","lturn")),
  M5_wins_all       = list(y = "wz",    x = "z",  ctl = c("lsz","ladv","lturn")),
  M6_rank_only      = list(y = "rank",  x = "rank", ctl = character(0)),
  M7_rank_size_turn = list(y = "rank",  x = "rank", ctl = c("lsz","lturn")),
  M8_rank_all       = list(y = "rank",  x = "rank", ctl = c("lsz","ladv","lturn"))
)
RES <- list(meta = list(script = "verification_followup/run_fu_task2_f2.R",
  run_at = as.character(Sys.time()), metric_type = "diag",
  design = "월별 횡단면 회귀 계수의 FMB(NW lag-3). 창 비겹침 → lag-3 적정(계수 계열 ACF 병기).",
  caveat = "동시기(contemporaneous) 연관 진단. 예측 주장 아님."))

for (f in FILT) {
  D0 <- merge(FZ[F_ == f, .(Date, Ticker, fz)], P[, .(Date, Ticker, nb_norm, lsz, ladv, lturn)],
              by = c("Date","Ticker"))
  say("=== [%s] 회귀 패널 %d행 · %d개월 ===", f, nrow(D0), uniqueN(D0$Date))
  for (nm in names(SPECS)) {
    sp <- SPECS[[nm]]
    need <- c("fz","nb_norm", sp$ctl)
    D <- D0[complete.cases(D0[, ..need])]
    s <- D[, {
      ok <- rep(TRUE, .N)
      if (sum(ok) >= 30L && sd(fz) > 1e-8 && sd(nb_norm) > 1e-12) {
        yv <- if (sp$y == "z") zs(nb_norm) else if (sp$y == "wz") zs(wins(nb_norm)) else rk(nb_norm)
        xv <- if (sp$x == "rank") rk(fz) else zs(fz)
        dd <- data.table(y = yv, x = xv)
        for (cc in sp$ctl) dd[[cc]] <- zs(get(cc))
        fml <- as.formula(paste("y ~ x", if (length(sp$ctl)) paste("+", paste(sp$ctl, collapse=" + ")) else ""))
        cf <- tryCatch(coef(lm(fml, data = dd))["x"], error = function(e) NA_real_)
        .(b = unname(cf), n = .N)
      } else .(b = NA_real_, n = .N)
    }, by = Date][is.finite(b)]
    tt <- nw_t(s$b); ci <- nw_ci(s$b)
    RES$f2[[f]][[nm]] <- list(spec = nm, y = sp$y, x = sp$x, controls = sp$ctl,
      mean_b = mean(s$b), t_nw_lag3 = tt, ci_lo = ci[1], ci_hi = ci[2],
      n_month = nrow(s), n_avg = mean(s$n), coef_series_acf_r1 = acf_r1(s$b))
    say("  %-18s b %+.4f  t %+7.2f  CI[%+.4f, %+.4f]  n=%d개월 · 월평균 %.0f종목 · 계수ACF r1 %.2f",
        nm, mean(s$b), tt, ci[1], ci[2], nrow(s), mean(s$n), acf_r1(s$b))
  }
}

saveRDS(RES, file.path(FU, "fu_task2_results.rds"))
say("=== ② 완료 → verification_followup/fu_task2_results.rds ===")
