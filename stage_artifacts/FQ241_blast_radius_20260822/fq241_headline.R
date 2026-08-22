## FQ-241 stage2 — 5+1 헤드라인 수치의 arm 대조 + A_orig 재현 확인
## 입력: fq241_quintile_stats.rds (stage1)
## metric_type = panel_statistic
suppressPackageStartupMessages({library(data.table)})
OUT <- "stage_artifacts/FQ241_blast_radius_20260822"
PM <- as.data.table(readRDS(file.path(OUT, "fq241_quintile_stats.rds")))

nw_t <- function(x, L_ = 3L){                       # Newey-West lag-3 t (평균의 t)
  x <- x[is.finite(x)]; n <- length(x); if (n < 12) return(NA_real_)
  e <- x - mean(x); S <- sum(e^2)/n
  for (l in seq_len(L_)) { if (l >= n) break
    S <- S + 2*(1 - l/(L_+1))*sum(e[(l+1):n]*e[1:(n-l)])/n }
  if (!is.finite(S) || S <= 0) return(NA_real_)
  mean(x)/sqrt(S/n)
}
ar1 <- function(x){ x<-x[is.finite(x)]; if(length(x)<12) return(NA_real_)
  suppressWarnings(cor(x[-1], x[-length(x)])) }

W <- dcast(PM, arm + fac + ym ~ q, value.var = c("mean_r","med_r","sk"))
W[, `:=`(spread = mean_r_5 - mean_r_1, medspread = med_r_5 - med_r_1, skewslope = sk_5 - sk_1)]
mm <- as.matrix(W[, .(mean_r_1, mean_r_2, mean_r_3, mean_r_4, mean_r_5)])
W[, m_mono := rowMeans(t(apply(mm, 1, diff)) > 0)]

F <- W[, .(n_month = .N,
           spread = mean(spread, na.rm=TRUE), medspread = mean(medspread, na.rm=TRUE),
           skewslope = mean(skewslope, na.rm=TRUE), m_mono = mean(m_mono, na.rm=TRUE),
           t_spread = nw_t(spread), t_medspread = nw_t(medspread),
           ar1_spread = ar1(spread), ar1_medspread = ar1(medspread),
           sd_spread = sd(spread, na.rm=TRUE)),
       by = .(arm, fac)]
F[, gap := medspread - spread]
## ★공통 팩터 집합 — arm 간 팩터 구성 차이가 개수 차이로 위장하지 않게 고정
MINM <- 60L
keep <- F[n_month >= MINM, .N, by = fac][N == uniqueN(F$arm), fac]
cat(sprintf("공통 팩터 집합: %d종 (각 arm 월수 >= %d)\n", length(keep), MINM))
FA <- F[fac %in% keep]
saveRDS(list(F = F, FA = FA, W = W, keep = keep), file.path(OUT, "fq241_factor_stats.rds"))

headline <- function(f){
  f <- f[is.finite(spread) & is.finite(medspread)]
  sd_ <- f[sign(medspread) != sign(spread)]
  msn <- f[is.finite(t_medspread) & is.finite(t_spread) & t_medspread > 2 & abs(t_spread) < 2]
  data.table(
    n_months = as.integer(round(median(f$n_month))), n_factors = nrow(f),
    `1_sign_div_n` = nrow(sd_), `1_pct` = round(100*nrow(sd_)/nrow(f),1),
    `1_medPos_meanNeg` = nrow(sd_[medspread>0 & spread<0]),
    `1_meanPos_medNeg` = nrow(sd_[medspread<0 & spread>0]),
    `2_cor_skewslope_gap` = round(suppressWarnings(cor(f$skewslope, f$gap, use="complete.obs")),3),
    `3_mono_ge_0.8` = sum(f$m_mono >= 0.8, na.rm=TRUE),
    `3_m_mono_median` = round(median(f$m_mono, na.rm=TRUE),4),
    `4_medsig_meannot_n` = nrow(msn), `4_pct` = round(100*nrow(msn)/nrow(f),1),
    `4_of_which_mean_neg` = nrow(msn[spread<0]),
    `5_gap_pos_n` = sum(f$gap>0, na.rm=TRUE), `5_gap_pos_pct` = round(100*mean(f$gap>0, na.rm=TRUE),1),
    gap_median_ann_pct = round(100*12*median(f$gap, na.rm=TRUE),2),
    ar1_spread_med = round(median(f$ar1_spread, na.rm=TRUE),3),
    ar1_medspread_med = round(median(f$ar1_medspread, na.rm=TRUE),3),
    sd_spread_med = round(median(f$sd_spread, na.rm=TRUE),5))
}
TAB <- FA[, headline(.SD), by = arm]
setcolorder(TAB, c("arm","n_months","n_factors"))
cat("\n=== 3(+1) arm 대조표 — 공통 팩터 집합 ===\n"); print(t(TAB))
fwrite(TAB, file.path(OUT,"fq241_3arm_table.csv"))

## A_orig 를 r32 공표치(320팩터/258개월)와 대조 — 재현 확인
r32 <- data.table(metric = c("sign_div_n","sign_div_pct","medPos_meanNeg","meanPos_medNeg",
                             "cor_skewslope_gap","mono_ge_0.8","m_mono_median",
                             "medsig_meannot_n","medsig_meannot_pct","of_which_mean_neg",
                             "gap_pos_n","gap_pos_pct","gap_median_ann_pct"),
                  r32_published = c(123,38.4,102,21,-0.728,0,0.5029,99,30.9,46,233,72.8,2.97))
a <- TAB[arm=="A_orig"]
r32[, A_orig_recomputed := c(a$`1_sign_div_n`, a$`1_pct`, a$`1_medPos_meanNeg`, a$`1_meanPos_medNeg`,
                             a$`2_cor_skewslope_gap`, a$`3_mono_ge_0.8`, a$`3_m_mono_median`,
                             a$`4_medsig_meannot_n`, a$`4_pct`, a$`4_of_which_mean_neg`,
                             a$`5_gap_pos_n`, a$`5_gap_pos_pct`, a$gap_median_ann_pct)]
cat("\n=== A_orig 재현 확인 (vs r32_general_fixedframe_result.json) ===\n"); print(r32)
fwrite(r32, file.path(OUT,"fq241_A_orig_reproduction_check.csv"))

## r33 — D03_RealVol 5분위 프로파일 arm 별
P33 <- PM[fac=="D03_RealVol", .(ann_mean_pct = round(100*12*mean(mean_r,na.rm=TRUE),3),
                                ann_med_pct  = round(100*12*mean(med_r, na.rm=TRUE),3),
                                skew         = round(mean(sk, na.rm=TRUE),4),
                                n_month = .N), by=.(arm,q)][order(arm,q)]
cat("\n=== r33 D03_RealVol 5분위 평균(연%) ===\n")
print(dcast(P33, arm + n_month ~ q, value.var="ann_mean_pct"))
cat("\n=== r33 D03_RealVol 5분위 중앙값(연%) ===\n")
print(dcast(P33, arm ~ q, value.var="ann_med_pct"))
cat("\n=== r33 D03_RealVol 5분위 왜도 ===\n")
print(dcast(P33, arm ~ q, value.var="skew"))
SH <- P33[, .(peak_q = q[which.max(ann_mean_pct)], trough_q = q[which.min(ann_mean_pct)],
              mean_spread_51 = round(ann_mean_pct[q==5]-ann_mean_pct[q==1],2),
              med_spread_51  = round(ann_med_pct[q==5]-ann_med_pct[q==1],2),
              skewslope_51   = round(skew[q==5]-skew[q==1],4),
              skew_monotone_decreasing = all(diff(skew[order(q)]) < 0),
              n_month = n_month[1]), by=arm]
cat("\n=== r33 형태 판정 ===\n"); print(SH)
fwrite(P33, file.path(OUT,"fq241_r33_profile_3arm.csv")); fwrite(SH, file.path(OUT,"fq241_r33_shape_3arm.csv"))
cat("\n[stage2 완료]\n")
