## FQ-143 P6 — (a) incumbent 위 한계기여 (b) 오라클 천장 -> 필요 정밀도 역산 (c) 검정력 공식기록
suppressPackageStartupMessages({ library(data.table); library(arrow); library(xts); library(PerformanceAnalytics) })
ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
DIR  <- file.path(ROOT, "stage_artifacts/fq143_tail_overlay_20260809")
source(file.path(ROOT, "02_Infrastructure/contracts/required_effect_size.R"))
p2 <- readRDS(file.path(DIR, "p4_panel_labeled.rds")); setDT(p2); setorder(p2, hold_ym)
COST <- 0.0015
nw_t <- function(x, lag = 3L) {
  x <- x[is.finite(x)]; n <- length(x); m <- mean(x); e <- x - m; s <- sum(e^2)/n
  for (l in 1:lag) { w <- 1 - l/(lag+1); s <- s + 2*w*sum(e[(l+1):n]*e[1:(n-l)])/n }
  se <- sqrt(s/n); c(t = m/se, mean = m, se = se)
}
ser <- function(sv) { ds <- abs(sv - shift(sv, 1, fill = 1.0)); sv * p2$ret_orig - ds * COST }
p2[, scale_cur := beta_R05 * m4]

cat("=== [P6-a] incumbent(M4xR05) 위 tail-label 한계기여 (진단) ===\n")
inc <- ser(p2$scale_cur)
bmx <- xts(p2$bm_ret, order.by = as.Date(paste0(p2$hold_ym, "-01")))
ir_of <- function(r) { a <- r - p2$bm_ret; mean(a)/sd(a)*sqrt(12) }
res <- rbindlist(lapply(c(0.30, 0.50, 0.70), function(dp) {
  sv  <- p2$scale_cur * ifelse(p2$lab_on, 1 - dp, 1)
  new <- ser(sv); d <- new - inc; s <- nw_t(d)
  data.table(arm = sprintf("incumbent x (라벨ON시 -%.0f%%)", dp*100),
             paired_t_nw3 = s[["t"]], mean_monthly = s[["mean"]], ann_pct = s[["mean"]]*12*100,
             IR_inc = ir_of(inc), IR_new = ir_of(new), dIR = ir_of(new) - ir_of(inc))
}))
## 오라클도 같은 형식으로 (천장)
for (ev in c(-0.05, -0.10)) {
  sv <- p2$scale_cur * ifelse(p2$ret_orig < ev, 0.5, 1); new <- ser(sv); d <- new - inc; s <- nw_t(d)
  res <- rbind(res, data.table(arm = sprintf("ORACLE incumbent x (실현<%.0f%% 시 -50%%)", ev*100),
    paired_t_nw3 = s[["t"]], mean_monthly = s[["mean"]], ann_pct = s[["mean"]]*12*100,
    IR_inc = ir_of(inc), IR_new = ir_of(new), dIR = ir_of(new) - ir_of(inc)))
}
res[, sign_agree := sign(paired_t_nw3) == sign(dIR)]
print(res[, .(arm, t = round(paired_t_nw3,3), ann_pct = round(ann_pct,2),
              dIR = round(dIR,4), sign_agree)])

cat("\n=== [P6-b] 천장 -> 필요 정밀도 역산 ===\n")
## 이 레버의 손익 = (축소분) x (-E[ret_orig | 발화]). 발화 집합을 어떻게 고르든 부호는
## E[ret_orig|발화] 가 결정한다. t=2.0 을 넘기려면 발화 집합의 조건부 평균이 얼마나 음수여야 하나.
n <- nrow(p2)
for (frac in c(0.05, 0.10, 0.20)) {
  k <- round(n*frac)
  ## 발화 k개월, 깊이 50% 일 때 t=2.0 에 필요한 E[ret_orig|발화]
  ## d_i = -0.5*ret_i (발화월), 0 (그외).  mean(d) = -0.5*k/n*E[ret|발화]
  ## sd(d) ~ 0.5*sqrt(k/n)*sd(ret|발화) (근사)  -> 실측 sd 대입
  sdon <- sd(p2$ret_orig[p2$lab_on])
  se_apx <- 0.5*sqrt(k/n)*sdon/sqrt(n)*NW_INFLATION_DEFAULT
  need_mean <- 2.0*se_apx / (0.5*k/n)
  cat(sprintf("  발화 %4.1f%% (%3d개월), 깊이 -50%%: t=2.0 에 필요한 E[ret_orig|발화] = %+.4f/월 (%+.1f%%/yr)\n",
              frac*100, k, -need_mean, -need_mean*12*100))
}
cat(sprintf("  실측 E[ret_orig|라벨ON] = %+.4f/월 (%+.1f%%/yr)  <- 부호가 반대\n",
            mean(p2$ret_orig[p2$lab_on]), mean(p2$ret_orig[p2$lab_on])*12*100))
cat(sprintf("  실측 E[ret_orig|실현<-10%%] = %+.4f/월 (오라클만 도달 가능)\n", mean(p2$ret_orig[p2$ret_orig < -0.10])))

cat("\n=== [P6-c] 검정력 공식 기록 (verdict_with_power) ===\n")
d_real <- ifelse(p2$lab_on, -0.5*p2$ret_orig, 0); s <- nw_t(d_real)
v <- verdict_with_power(observed_t = s[["t"]], observed_monthly = s[["mean"]], n = n,
                        t_threshold = 2.0, sd_monthly = sd(d_real), design = "full")
cat(sprintf("  observed t=%.3f  mean=%+.5f  n=%d\n", s[["t"]], s[["mean"]], n))
cat(sprintf("  verdict = %s\n  note    = %s\n", v$verdict, v$note))
cat(sprintf("  required_monthly=%+.5f (%.2f%%/yr)  implied_t_threshold=%.2f  bar_restates_t=%s\n",
            v$required$required_monthly, v$required$required_annual*100,
            v$implied_t_threshold, v$bar_restates_t))
fwrite(res, file.path(DIR, "p6_increment.csv"))
cat("\n[P6 DONE]\n")
