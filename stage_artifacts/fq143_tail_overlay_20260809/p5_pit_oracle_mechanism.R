## FQ-143 P5 — PIT 3종 + 오라클 양성대조 + 기전 분해
##
## 관문(P4)이 배포창 소비를 막았으므로 primary(book-marginal paired) 는 **측정하지 않는다**
##  (규율 4: 자격 없는 정의로 소비면 측정 금지 — 결과가 양수든 음수든 해석 불가).
## 대신 (1) 관문 판정 자체의 PIT 무결성 (2) 하네스 생존 실증 (3) 왜 그런가 를 잰다.
suppressPackageStartupMessages({ library(data.table); library(arrow); library(xts); library(PerformanceAnalytics) })
ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
DIR  <- file.path(ROOT, "stage_artifacts/fq143_tail_overlay_20260809")
source(file.path(ROOT, "02_Infrastructure/contracts/label_eligibility_gate.R"))
source(file.path(ROOT, "02_Infrastructure/contracts/required_effect_size.R"))
source(file.path(ROOT, "02_Infrastructure/validation/overlay_pit_guard.R"))
S <- readRDS(file.path(DIR, "p3.rds")); u <- S$u; bmm <- S$bmm
p2 <- readRDS(file.path(DIR, "p4_panel_labeled.rds")); setDT(p2); setorder(p2, hold_ym)

## Newey-West lag-3 t (평균 차이) — 자체합성 아님: OLS 절편 + NW HAC
nw_t <- function(x, lag = 3L) {
  x <- x[is.finite(x)]; n <- length(x); if (n < 12) return(c(t = NA, mean = NA, se = NA))
  m <- mean(x); e <- x - m; g0 <- sum(e^2)/n; s <- g0
  for (l in 1:lag) { w <- 1 - l/(lag + 1); s <- s + 2*w*sum(e[(l+1):n]*e[1:(n-l)])/n }
  se <- sqrt(s/n); c(t = m/se, mean = m, se = se)
}

cat("=== [P5-1] PIT 검증 ① assert_overlay_pit (HARD) ===\n")
## 사용한 신호 컷오프 = 홀딩월 직전 월말(라벨 Date). 홀딩월 시작 = hold_ym 1일.
used_cut  <- as.Date(paste0(p2$sig_ym, "-01")) + 0   # 라벨 관측월 시작(보수적으로 월초로 잡아도 통과해야 함)
lab_dates <- u[match(p2$sig_ym, u$ym)]$Date          # 실제 라벨 관측 시각(월말)
hold_start <- overlay_signal_cutoff(p2$hold_ym)
ok <- tryCatch({ assert_overlay_pit(lab_dates, hold_start, label = "unified_regime CRISIS|CAUTION"); TRUE },
               error = function(e) { cat("  ", conditionMessage(e), "\n"); FALSE })
cat(sprintf("  라벨 관측시각(월말) < 홀딩월 시작 : %s  (최대 간격 %d일, 최소 %d일)\n",
            if (ok) "PASS" else "FAIL",
            max(as.numeric(hold_start - lab_dates)), min(as.numeric(hold_start - lab_dates))))

cat("\n=== [P5-2] PIT 검증 ② strict-PIT A/B (동월정렬 vs C5정렬) ===\n")
tab3 <- fread(file.path(DIR, "p3_eligibility_table.csv"))
for (ev in unique(tab3$event)) {
  a <- tab3[alignment == "A_same" & event == ev]$lift
  b <- tab3[alignment == "B_clean" & event == ev]$lift
  ab <- overlay_lookahead_ab(a, b, metric_name = sprintf("lift[%s]", ev), rel_tol = 0.05)
  cat("  ", ab$message, "\n")
}

cat("\n=== [P5-3] PIT 검증 ③ lag1 스트레스 (라벨을 1개월 더 뒤로) ===\n")
mk_lag <- function(extra) {
  m <- merge(u[, .(ym, lab_on)], bmm[, .(ym, k = .I)], by = "ym")
  m[, k_evt := k + 1L + extra]
  m <- merge(m, bmm[, .(k_evt = .I, evt_ret = bm_ret)], by = "k_evt"); setorder(m, k); m[]
}
for (extra in 0:2) {
  m <- mk_lag(extra)
  g5  <- label_eligibility(m$lab_on, m$evt_ret < -0.05)
  g10 <- label_eligibility(m$lab_on, m$evt_ret < -0.10)
  cat(sprintf("  lag+%d:  <-5%% lift %.3f (p %.2e, %s)   <-10%% lift %.3f (p %.2e, %s)\n",
              extra, g5$lift, g5$fisher_p, substr(g5$verdict,1,8),
              g10$lift, g10$fisher_p, substr(g10$verdict,1,8)))
}

cat("\n=== [P5-4] 오라클 양성대조 (하네스 생존 실증) ===\n")
## 오라클 = 홀딩월 실현 하락을 아는 라벨(PIT 위반, 대조 전용). 하네스가 살아 있으면 큰 양수 t 가 나와야 한다.
mk_arm <- function(on, depth = 0.50, lab = "") {
  d <- ifelse(on, -depth * p2$ret_orig, 0)
  s <- nw_t(d)
  data.table(arm = lab, n_on = sum(on), depth = depth,
             mean_monthly = s[["mean"]], paired_t_nw3 = s[["t"]], ann_effect = s[["mean"]]*12)
}
arms <- rbindlist(list(
  mk_arm(p2$ret_orig < -0.10, 0.50, "ORACLE  실현 ret_orig < -10%"),
  mk_arm(p2$ret_orig < -0.05, 0.50, "ORACLE  실현 ret_orig < -5%"),
  mk_arm(p2$lab_on,            0.50, "REAL    CRISIS∪CAUTION (C5-clean)"),
  mk_arm(p2$Category == "CRISIS", 0.50, "REAL    CRISIS only (더 깊고 드문 표적)"),
  mk_arm(rep(c(TRUE, FALSE), length.out = nrow(p2)), 0.50, "NULLCTL 교대(정보 0)")
))
print(arms[, .(arm, n_on, mean_monthly = round(mean_monthly,5),
               paired_t_nw3 = round(paired_t_nw3,3), ann_effect_pct = round(ann_effect*100,2))])
cat("  ※ 부호 규약: 양수 = 노출축소가 base 대비 이득. 오라클이 큰 양수여야 계측 생존.\n")

cat("\n=== [P5-5] 기전 분해 — 라벨은 방향이 아니라 분산을 잰다 ===\n")
p2[, era := ifelse(hold_ym < "2015-01", "2004-2014", "2015-2026")]
cat(sprintf("  배포창 전체: E[ret_orig|ON]=%+.4f  E[ret_orig|OFF]=%+.4f  gap=%+.4f\n",
            mean(p2$ret_orig[p2$lab_on]), mean(p2$ret_orig[!p2$lab_on]),
            mean(p2$ret_orig[p2$lab_on]) - mean(p2$ret_orig[!p2$lab_on])))
cat(sprintf("  배포창 전체: sd[ret_orig|ON]=%.4f  sd[ret_orig|OFF]=%.4f  비율=%.2fx\n",
            sd(p2$ret_orig[p2$lab_on]), sd(p2$ret_orig[!p2$lab_on]),
            sd(p2$ret_orig[p2$lab_on])/sd(p2$ret_orig[!p2$lab_on])))
## 전표본(1990~)에서도 같은 축을 — 창-정합 후 비교
mf <- mk_lag(0)
cat(sprintf("  전표본(시장): E[r|ON]=%+.4f  E[r|OFF]=%+.4f  gap=%+.4f  |  sd ON %.4f / OFF %.4f = %.2fx\n",
            mean(mf$evt_ret[mf$lab_on]), mean(mf$evt_ret[!mf$lab_on]),
            mean(mf$evt_ret[mf$lab_on]) - mean(mf$evt_ret[!mf$lab_on]),
            sd(mf$evt_ret[mf$lab_on]), sd(mf$evt_ret[!mf$lab_on]),
            sd(mf$evt_ret[mf$lab_on])/sd(mf$evt_ret[!mf$lab_on])))
cat("\n  -- 시대별 (★분할 = 저검정력. 판정 아님, 신호 소재 진단) --\n")
mf[, era := ifelse(ym < "2004-01", "pre-2004", "post-2004")]
print(mf[, .(n = .N, n_on = sum(lab_on),
             mean_on = round(mean(evt_ret[lab_on]),4), mean_off = round(mean(evt_ret[!lab_on]),4),
             lift_m10 = round(label_eligibility(lab_on, evt_ret < -0.10)$lift, 3),
             p_m10 = signif(label_eligibility(lab_on, evt_ret < -0.10)$fisher_p, 3)), by = era])

cat("\n=== [P5-6] MDD/회전 부수효과 (2차 — primary 대체 아님) ===\n")
COST <- 0.0015
p2[, scale_cur := beta_R05 * m4]
mk_series <- function(scale_vec) {
  ds <- abs(scale_vec - shift(scale_vec, 1, fill = 1.0))
  scale_vec * p2$ret_orig - ds * COST
}
variants <- list(
  base_no_overlay = rep(1, nrow(p2)),
  incumbent_M4xR05 = p2$scale_cur,
  tail_target_CC50 = ifelse(p2$lab_on, 0.50, 1.0),
  tail_target_CRISIS30 = ifelse(p2$Category == "CRISIS", 0.30, 1.0)
)
out <- rbindlist(lapply(names(variants), function(nm) {
  sv <- variants[[nm]]; r <- mk_series(sv)
  x <- xts(r, order.by = as.Date(paste0(p2$hold_ym, "-01")))
  data.table(variant = nm,
             ann_ret = as.numeric(Return.annualized(x, scale = 12)),
             ann_sd  = as.numeric(StdDev.annualized(x, scale = 12)),
             SR      = as.numeric(SharpeRatio.annualized(x, scale = 12)),
             MDD     = as.numeric(maxDrawdown(x)),
             turnover_scale = sum(abs(sv - shift(sv, 1, fill = 1.0)))/ (nrow(p2)/12))
}))
out[, Calmar := ann_ret/MDD]
print(out[, .(variant, ann_ret = round(ann_ret,4), SR = round(SR,3), MDD = round(MDD,4),
              Calmar = round(Calmar,3), to_per_yr = round(turnover_scale,3))])
cat("  metric_type = canonical_screen_diag (배포 base 시계열 위 진단. 자본 주장 아님)\n")

fwrite(arms, file.path(DIR, "p5_oracle_arms.csv"))
fwrite(out,  file.path(DIR, "p5_variant_diag.csv"))
cat("\n[P5 DONE]\n")
