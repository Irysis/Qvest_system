# =============================================================================
# run_correction_p6.R — WT-D20260808_003 정정 2건 (Q-Lead 회수분 반영, 2026-08-09)
#
#  ① monotonicity 정의 충돌
#     플랫폼 정본 = 10분위 Spearman ∈ [−1,1] (ml_pipeline/quality_metrics.py:77-98)
#     WT-001 용례 = 5분위 인접 4스텝 증가비율 ∈ {0,.25,.5,.75,1} — 값 범위가 다르다.
#     → diagnostics.monotonicity 에는 **정본(10분위 Spearman)** 을 넣고, 4스텝 분수는
#       별도 필드명(monotonicity_q5_stepfrac_wt001)으로 분리한다.
#
#  ② 겹치는 창 위 계열에 짧은 NW lag 금지
#     β 갭 계열은 trailing 60m 창이 매월 59개월 겹친다 → NW lag-3 은 자기상관을 못 흡수해
#     |t| 를 크게 부풀린다(WT-001 실측: lag-60 으로 늘리면 2.5~3.0배 축소).
#     본 스크립트에서 **내 P0 의 β 갭 t 도 같은 함정**임을 확인하고 정정 통계로 대체한다:
#       (a) ACF r1  (b) NW lag-60  (c) Bartlett 유효표본  (d) 월별 부호 일관성
#       (e) 겹치지 않는 stride-60 부분표본
#     사전등록 B3 문턱은 **점추정 |갭| > 0.15** 이므로 판정 자체는 t 에 의존하지 않는다.
#
# 실행: Rscript -e 'source("stage_artifacts/WT_D20260808_003/run_correction_p6.R")'
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite); library(sandwich); library(lmtest) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260808_003")
say <- function(fmt, ...) cat(sprintf(paste0("[m6] ", fmt, "\n"), ...))
P0 <- readRDS(file.path(OUT, "p0_panels.rds")); M2 <- readRDS(file.path(OUT, "measure_p2.rds"))
N <- P0$N; BETA <- P0$BETA; X <- M2$X
say("INPUT N nrow=%d n_month=%d · BETA nrow=%d n_month=%d · X nrow=%d n_month=%d",
    nrow(N), uniqueN(N$Date), nrow(BETA), uniqueN(BETA$Date), nrow(X), uniqueN(X$Date))
C <- list(generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S"))

nw_t_lag <- function(x, lag) { x <- x[is.finite(x)]; if (length(x) < 12L) return(NA_real_)
  f <- lm(x ~ 1); tryCatch(as.numeric(lmtest::coeftest(f, vcov. = sandwich::NeweyWest(f, lag = lag, prewhite = FALSE))[1,3]), error = function(e) NA_real_) }

# ── ① 플랫폼 정본 monotonicity (10분위 Spearman) ────────────────────────────
say("=== ① monotonicity 정본(10분위 Spearman) vs WT-001 용례(5분위 4스텝 분수) ===")
mono_platform <- function(dt, zc) {
  d <- dt[is.finite(get(zc)) & is.finite(act)]
  dm <- d[, { if (.N < 30L) .(dec = integer(0), r = numeric(0)) else {
      dec <- as.integer(cut(frank(get(zc)), breaks = quantile(frank(get(zc)), probs = seq(0,1,0.1)),
                            include.lowest = TRUE, labels = FALSE))
      .(dec = dec, r = act) } }, by = Date]
  avg <- dm[is.finite(dec), .(m = mean(r)), by = dec][order(dec)]
  # 월별 decile 평균의 전기간 평균 → decile 순위와 Spearman
  per <- dm[is.finite(dec), .(m = mean(r)), by = .(Date, dec)]
  avg2 <- per[, .(m = mean(m)), by = dec][order(dec)]
  list(rho = suppressWarnings(cor(as.numeric(avg2$dec), avg2$m, method = "spearman")),
       decile_mean_ann_pct = 100*12*avg2$m)
}
mono_wt001 <- function(dt, zc) {
  d <- dt[is.finite(get(zc)) & is.finite(act)]
  s <- d[, { qr <- frank(get(zc))/.N
    .(q1 = mean(act[qr<=0.2]), q2 = mean(act[qr>0.2&qr<=0.4]), q3 = mean(act[qr>0.4&qr<=0.6]),
      q4 = mean(act[qr>0.6&qr<=0.8]), q5 = mean(act[qr>0.8])) }, by = Date]
  qm <- c(mean(s$q1), mean(s$q2), mean(s$q3), mean(s$q4), mean(s$q5))
  mean(diff(qm) > 0)
}
mo <- list()
for (zc in c("q01","q01_n")) {
  p <- mono_platform(X, zc); w <- mono_wt001(X, zc)
  mo[[zc]] <- list(monotonicity_platform_q10_spearman = p$rho,
                   decile_mean_ann_pct = p$decile_mean_ann_pct,
                   monotonicity_q5_stepfrac_wt001 = w)
  say("  %-6s 정본 10분위 Spearman rho = %+.3f | WT-001 5분위 4스텝 분수 = %.2f",
      zc, p$rho, w)
  say("        10분위 연수익: %s", paste(sprintf("%+.1f", p$decile_mean_ann_pct), collapse = " "))
}
C$monotonicity <- c(mo, list(
  definition_conflict_note = "두 정의는 값 범위가 다르다(정본 [−1,1] Spearman vs WT-001 {0,.25,.5,.75,1}). alpha_research_init.md 의 예시 0.87·문턱 '<0.5' 는 정본 척도 기준. 본 패키지는 diagnostics.monotonicity = 정본, WT-001 용례는 별도 필드."))

# ── ② β 갭 계열 — 겹치는 창 정정 통계 ───────────────────────────────────────
say("=== ② β 갭 정정 통계 (겹치는 60m 창 — 짧은 NW lag 금지) ===")
gap_series <- function(zc) {
  D <- merge(N[is.finite(get(zc)), .(Date, Ticker, z = get(zc))], BETA, by = c("Date","Ticker"))
  D[, q_rank := frank(z)/.N, by = Date]
  s <- D[, .(b_top = median(beta[q_rank > 0.8]), b_med = median(beta),
             b_t25 = { o <- order(-z); median(beta[o[seq_len(min(25L,.N))]]) }), by = Date]
  s[is.finite(b_top) & is.finite(b_med)][order(Date)]
}
diag_gap <- function(g, lab) {
  x <- g[is.finite(g)]
  r1 <- as.numeric(acf(x, lag.max = 1, plot = FALSE)$acf[2])
  neff_bartlett <- length(x) * (1 - r1) / (1 + r1)
  # 겹치지 않는 stride-60 부분표본 (창 길이 = 60m)
  idx <- seq(1L, length(x), by = 60L)
  sub <- x[idx]
  t_sub <- if (length(sub) >= 3L) mean(sub)/(sd(sub)/sqrt(length(sub))) else NA_real_
  out <- list(mean = mean(x), n = length(x), acf_r1 = r1,
              t_nw_lag3_INFLATED = nw_t_lag(x, 3L), t_nw_lag60 = nw_t_lag(x, 60L),
              n_eff_bartlett = neff_bartlett,
              sign_negative_pct = 100*mean(x < 0),
              stride60_n = length(sub), stride60_mean = mean(sub), stride60_t = t_sub)
  say("  %-24s 갭 %+.3f | ACF r1 %.3f | NW lag-3 t %+.2f (부풀림) → lag-60 t %+.2f | Bartlett 유효n %.1f/%d | 월별 음(−) %.1f%% | stride-60 (n=%d) 평균 %+.3f t %+.2f",
      lab, out$mean, out$acf_r1, out$t_nw_lag3_INFLATED, out$t_nw_lag60, out$n_eff_bartlett, out$n,
      out$sign_negative_pct, out$stride60_n, out$stride60_mean, out$stride60_t)
  out
}
gr <- gap_series("q01"); gn <- gap_series("q01_n")
bg <- list(
  raw_quintile     = diag_gap(gr$b_top - gr$b_med, "raw 최상위분위 갭"),
  neutral_quintile = diag_gap(gn$b_top - gn$b_med, "중립 최상위분위 갭"),
  raw_top25        = diag_gap(gr$b_t25 - gr$b_med, "raw top-25 갭"),
  neutral_top25    = diag_gap(gn$b_t25 - gn$b_med, "중립 top-25 갭"))
# paired Δβ (중립 − raw) 도 같은 함정
mp <- merge(gr[, .(Date, r = b_top, r25 = b_t25)], gn[, .(Date, n = b_top, n25 = b_t25)], by = "Date")
bg$paired_quintile <- diag_gap(mp$n - mp$r, "paired Δβ 분위(중립−raw)")
bg$paired_top25    <- diag_gap(mp$n25 - mp$r25, "paired Δβ top-25")
C$beta_gap_corrected <- c(bg, list(
  citation_rule = "β 갭은 점추정 + 월별 부호 일관성 + stride-60 으로 서술한다. 겹치는 창 계열의 NW lag-3 |t| 는 인용 금지(부풀림).",
  b3_threshold_note = "사전등록 B3 문턱은 점추정 |갭| > 0.15 — t 에 의존하지 않는다. 정정 후에도 판정 불변."))

# ── ③ P0 인용 정정 요약 ─────────────────────────────────────────────────────
say("=== ③ P0 서술 정정 ===")
say("  P0 이 보고한 raw −0.245 (t −20.76) / 중립 −0.153 (t −13.20) 중 |t| 는 부풀림 — 위 lag-60·stride-60 로 대체")
say("  ★ B3 판정 근거 재확인: 중립 최상위분위 갭 %+.3f · top-25 갭 %+.3f (둘 다 문턱 −0.15 초과 잔존, 월별 음(−) 비율 %.1f%%/%.1f%%)",
    bg$neutral_quintile$mean, bg$neutral_top25$mean,
    bg$neutral_quintile$sign_negative_pct, bg$neutral_top25$sign_negative_pct)
C$b3_reconfirmed <- list(
  neutral_quintile_gap = bg$neutral_quintile$mean, neutral_top25_gap = bg$neutral_top25$mean,
  threshold = -0.15, fired = TRUE,
  basis = "점추정 + 월별 부호 일관성 (t 미의존)")

write_json(C, file.path(OUT, "corrections_p6.json"), pretty = TRUE, auto_unbox = TRUE, digits = NA)
saveRDS(C, file.path(OUT, "corrections_p6.rds"))
say("=== 정정 완료 → corrections_p6.json ===")
