# FQ-236 Lane D — 사전등록 스펙 실행 드라이버 (rev2 확정판)
#   PRIMARY : Y1b ~ KR_CredSpread_BBB (level), UNION 198m (backfill gate PASS)
#   동반    : Y1a(F_B 형태축) · Y2(보조) · rollz120 강건성 1판
#   진단창  : UNION 133m (F_F leave-backfill-out) · K200 ~306m (성립 근거 사용 금지)
#   보강    : breadth corroboration · F_C flow 기전 · F_D placebo · F_E leave-2026-out · D_G
suppressMessages({library(data.table); library(jsonlite)})
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
OUT  <- file.path(ROOT, "stage_artifacts", "WT-D20260822_001")
source(file.path(OUT, "lane_d_regression.R"))

ANCHOR <- 0.25   # rev2 effect_size_anchor: |b|*sd(S)/sd(Y) >= 0.25

strip <- function(r) { r$series_data <- NULL; r }

grade <- function(r, predicted_sign = -1) {
  if (!is.null(r$error)) return(list(label = "ERROR", why = r$error))
  t <- r$fit$t_nw; std <- r$fit$effect_in_sdY_units
  ci_std <- r$fit$effect_ci95 / r$fit$sd_Y
  plc <- isTRUE(r$F_D_placebo$passes)
  sgn_ok <- sign(t) == predicted_sign
  if (t * predicted_sign >= 2.0 && sgn_ok) {
    if (!plc) return(list(label = "미결_placebo_미통과", why = sprintf("|t|=%.2f <= placebo95=%.2f", abs(t), r$F_D_placebo$abs_t_p95)))
    if (abs(std) < ANCHOR) return(list(label = "성립_소효과(sub-anchor)", why = sprintf("표준화 |%.3f| < 앵커 %.2f", std, ANCHOR)))
    return(list(label = "성립", why = sprintf("t=%.2f, 표준화 %.3f", t, std)))
  }
  if (t * predicted_sign <= -2.0) return(list(label = "기각-부호", why = sprintf("t=%.2f 예측과 반대 방향 유의", t)))
  if (all(abs(ci_std) < ANCHOR)) return(list(label = "효과없음(powered null)",
      why = sprintf("표준화 CI [%.3f, %.3f] ⊂ (-%.2f, +%.2f)", ci_std[1], ci_std[2], ANCHOR, ANCHOR)))
  list(label = "미결(underpowered)", why = sprintf("표준화 CI [%.3f, %.3f] 가 ±%.2f 경계에 걸침", ci_std[1], ci_std[2], ANCHOR))
}

specs <- list(
  list(id = "PRIMARY_Y1b_198m",  y = "Y1b", s = "KR_CredSpread_BBB", tag = "union_liq2e8", a = "2010-02-01", b = "2026-07-01", tr = "level"),
  list(id = "FB_Y1a_198m",       y = "Y1a", s = "KR_CredSpread_BBB", tag = "union_liq2e8", a = "2010-02-01", b = "2026-07-01", tr = "level"),
  list(id = "Y2_198m",           y = "Y2",  s = "KR_CredSpread_BBB", tag = "union_liq2e8", a = "2010-02-01", b = "2026-07-01", tr = "level"),
  list(id = "ROBUST_Y1b_rollz",  y = "Y1b", s = "KR_CredSpread_BBB", tag = "union_liq2e8", a = "2010-02-01", b = "2026-07-01", tr = "rollz120"),
  list(id = "FF_Y1b_133m",       y = "Y1b", s = "KR_CredSpread_BBB", tag = "union_liq2e8", a = "2015-07-01", b = "2026-07-01", tr = "level"),
  list(id = "FF_Y1a_133m",       y = "Y1a", s = "KR_CredSpread_BBB", tag = "union_liq2e8", a = "2015-07-01", b = "2026-07-01", tr = "level"),
  list(id = "BACKFILLSEG_Y1b_65m", y = "Y1b", s = "KR_CredSpread_BBB", tag = "union_liq2e8", a = "2010-02-01", b = "2015-06-01", tr = "level"),
  list(id = "DIAG_K200_Y1b_306m", y = "Y1b", s = "KR_CredSpread_BBB", tag = "k200_liq2e8",  a = "2001-02-01", b = "2026-07-01", tr = "level"),
  list(id = "DIAG_K200_Y1a_306m", y = "Y1a", s = "KR_CredSpread_BBB", tag = "k200_liq2e8",  a = "2001-02-01", b = "2026-07-01", tr = "level"),
  list(id = "CORROB_Y1b_breadth", y = "Y1b", s = "breadth_bear_prob", tag = "union_liq2e8", a = "2014-05-01", b = "2026-07-01", tr = "level"),
  list(id = "CORROB_Y1a_breadth", y = "Y1a", s = "breadth_bear_prob", tag = "union_liq2e8", a = "2014-05-01", b = "2026-07-01", tr = "level")
)

res <- list()
for (sp in specs) {
  cat("\n=== ", sp$id, " ===\n", sep = "")
  r <- laned_run(sp$tag, sp$y, sp$s, sp$a, sp$b, sp$tr, n_placebo = 200L, label = sp$id)
  if (!is.null(r$error)) { cat("  ERROR:", r$error, "\n"); res[[sp$id]] <- r; next }
  g <- grade(r)
  r$verdict <- g
  cat(sprintf("  n=%d  b=%.6f  se=%.6f  t_NW=%.3f  R2=%.4f\n", r$spec$n, r$fit$b, r$fit$se_nw, r$fit$t_nw, r$fit$r2))
  cat(sprintf("  effect/1sd(S) = %.5f  (표준화 %.3f sdY)  CI95 [%.5f, %.5f]\n",
              r$fit$effect_per_1sd_S, r$fit$effect_in_sdY_units, r$fit$effect_ci95[1], r$fit$effect_ci95[2]))
  cat(sprintf("  placebo(AR1 phi=%.3f): |t|obs=%.2f vs p95=%.2f -> %s | 양성대조 xs_sd t=%.2f (alive=%s)\n",
              r$F_D_placebo$phi_ar1, r$F_D_placebo$abs_t_obs, r$F_D_placebo$abs_t_p95,
              ifelse(r$F_D_placebo$passes, "PASS", "FAIL"),
              r$F_D_placebo$positive_control$t_nw, r$F_D_placebo$positive_control$alive))
  cat(sprintf("  lag1 t=%.2f | 오염판(월말정보) t=%.2f | leave2026out t=%s (flip=%s)\n",
              r$pit_stress$lag1$t_nw, r$pit_stress$contaminated_end_of_month$t_nw,
              if (is.null(r$F_E_leave2026out)) "NA" else sprintf("%.2f", r$F_E_leave2026out$t_nw),
              if (is.null(r$F_E_leave2026out)) "NA" else r$F_E_leave2026out$sign_flip))
  cat(sprintf("  D_G C_top=%.3f (기준 0.333) | Kish 유효개월 %.1f/%d | 요구 t재진술=%s\n",
              r$identification_concentration$D_G_C_top_upper_tercile,
              r$identification_concentration$effective_months_kish, r$spec$n, r$power$bar_restates_t))
  cat(sprintf("  ★판정: %s — %s\n", g$label, g$why))
  res[[sp$id]] <- strip(r)
}

# ── F_C 기전 부수관측: FlowAsym ~ S ─────────────────────────────────────────
cat("\n=== F_C flow mechanism ===\n")
fc <- fread(file.path(OUT, "FC_flow_panel.csv"))
fc[, ym_d := as.Date(paste0(ym, "-01"))]
fc <- fc[ym_d <= as.Date("2026-06-01")]        # investor_wide 종단 2026-07-24 → 2026-07 부분월 제외
Sp <- S_ALL[series == "KR_CredSpread_BBB", .(ym_d, s = S)]
fcm <- merge(fc[, .(ym_d, y = FlowAsym)], Sp, by = "ym_d")
fc_res <- list()
for (w in list(c("2010-02-01", "2026-06-01"), c("2001-02-01", "2026-06-01"))) {
  dd <- fcm[ym_d >= as.Date(w[1]) & ym_d <= as.Date(w[2])]
  f <- .nw_fit(dd$y, dd$s)
  cat(sprintf("  %s..%s  n=%d  b=%.5f  t_NW=%+.2f  (기전 예측: +)  R2=%.3f\n",
              w[1], w[2], f$n, f$b, f$t, f$r2))
  fc_res[[paste(w, collapse = "..")]] <- list(n = f$n, b = f$b, t_nw = f$t, r2 = f$r2,
    verdict = if (f$t >= 2.0) "채널 지지" else if (f$t <= -2.0) "채널 기각" else "채널 미결(advisory)")
}
cat(sprintf("  FlowAsym 기저: mean=%.4f  min=%.4f  max=%.4f  (음수 = 개인 역추세 매수)\n",
            mean(fcm$y), min(fcm$y), max(fcm$y)))
res[["F_C_flow"]] <- list(baseline_mean = mean(fcm$y), windows = fc_res,
                          coverage_note = "investor_wide 종단 2026-07-24 → 2026-07 부분월 제외")

write_json(res, file.path(OUT, "lane_d_results.json"), auto_unbox = TRUE, pretty = TRUE, digits = 8, na = "null")
cat("\nWROTE", file.path(OUT, "lane_d_results.json"), "\n")
