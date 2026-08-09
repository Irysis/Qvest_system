## FQ176 — INCONCLUSIVE 의 정확한 내용: 무엇이 배제됐고 무엇이 안 됐나
suppressPackageStartupMessages({ library(data.table) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/FQ176")
say  <- function(fmt, ...) { cat(sprintf(paste0("[mde] ", fmt, "\n"), ...)); flush.console() }
V <- readRDS(file.path(OUT,"verdict_check.rds")); res <- V$res
EL <- as.data.table(readRDS(file.path(OUT,"eligible.rds")))
IC <- as.data.table(readRDS(file.path(OUT,"ic_series.rds")))

M <- merge(res, EL[, .(factor, signal, ic_mean, ic_sd)], by=c("factor","signal"))
M[, se_stage := abs(d_ic / t)]
M[, se_raw   := se_stage / 1.25]
M[, ci_lo := d_ic - 1.96*se_raw][, ci_hi := d_ic + 1.96*se_raw]
M[, mde    := 2.0 * se_raw]                 # t=2 검출가능 최소효과
M[, mde_rel_to_base := mde / abs(ic_mean)]  # 무조건부 IC 대비 배수
M <- M[order(-abs(t))]

say("=== 21쌍 신뢰구간 / 검출한계 ===")
say("  관측 |dIC| : min %.5f · median %.5f · max %.5f",
    min(abs(M$d_ic)), median(abs(M$d_ic)), max(abs(M$d_ic)))
say("  MDE(t=2)   : min %.5f · median %.5f · max %.5f",
    min(M$mde), median(M$mde), max(M$mde))
say("  ★MDE / 무조건부 ic_mean : min %.2fx · median %.2fx · max %.2fx",
    min(M$mde_rel_to_base), median(M$mde_rel_to_base), max(M$mde_rel_to_base))
say("  -> 즉 '하락 다음달 IC 가 평시의 %.1f~%.1f배' 수준이어야 검출됐다.",
    1+min(M$mde_rel_to_base), 1+median(M$mde_rel_to_base))
say("")
say("  95%%CI 상한 최대 %.5f (%s) · 하한 최소 %.5f (%s)",
    max(M$ci_hi), M$factor[which.max(M$ci_hi)], min(M$ci_lo), M$factor[which.min(M$ci_lo)])
say("  ★배제되지 않은 효과크기: |dIC| 최대 %.4f 까지 (= 무조건부 IC 의 %.1f배) 는 구간 안",
    max(abs(c(M$ci_lo, M$ci_hi))), max(abs(c(M$ci_lo,M$ci_hi)))/median(abs(M$ic_mean)))
say("")
say("=== 상위 6쌍 상세 ===")
for (i in 1:6) say("  %-30s %s  dIC %+.5f  95%%CI [%+.5f, %+.5f]  MDE %.4f  base_ic %.4f",
                   M$factor[i], M$signal[i], M$d_ic[i], M$ci_lo[i], M$ci_hi[i], M$mde[i], M$ic_mean[i])

say("")
say("=== 방향 패턴 (유의성 아님, 기전단서) ===")
grp <- function(f) {
  if (grepl("^(Q0|GR0)", f)) "quality_growth"
  else if (grepl("^(V0)", f)) "value"
  else if (grepl("^(D0|R0)", f)) "risk_vol"
  else if (grepl("^(C0)", f)) "revision"
  else "other"
}
M[, g := sapply(factor, grp)]
print(M[, .(n=.N, n_pos=sum(d_ic>0), mean_dIC=mean(d_ic), max_abs_t=max(abs(t))), by=g][order(-mean_dIC)])
say("  이항검정 (quality_growth 4/4 양수, p=0.5 하): p = %.3f", binom.test(sum(M[g=="quality_growth"]$d_ic>0), nrow(M[g=="quality_growth"]), 0.5)$p.value)

say("")
say("=== ★기전: 구속 제약이 개월수가 아니라 에피소드수임을 수치화 ===")
SIG <- fread(file.path(OUT,"signals.csv")); SIG[, Date := as.Date(Date)]
on_d <- SIG[S3==TRUE]$Date
r <- rle(SIG[order(Date)]$S3); nb <- sum(r$values)
say("  S3: ON 46개월 / 연속블록 %d개 -> 유효독립표본 ~%d", nb, nb)
say("  월단위 se 기준 MDE median %.5f · 에피소드클러스터 se 기준 MDE median %.5f (%.1f배)",
    median(M$mde), median(M$mde)*sqrt(46/4), sqrt(46/4))
say("  -> 클러스터 보정 시 필요효과는 무조건부 IC 의 %.1f배 -> 구조적 검출불가",
    median(M$mde)*sqrt(46/4)/median(abs(M$ic_mean)))
say("=== 완료 ===")
