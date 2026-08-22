## FQ-241 blast radius probe 1 — Lane A 분포 형태 수치의 유니버스 오염 재검
## 산출: 3(+1) arm 대조. metric_type = panel_statistic (횡단면 패널 통계 — 성과수치 아님)
## 실행: cd <ROOT> && Rscript -e 'source("stage_artifacts/FQ241_blast_radius_20260822/fq241_recompute.R")'
suppressPackageStartupMessages({library(data.table); library(arrow)})
OUT <- "stage_artifacts/FQ241_blast_radius_20260822"
PAN <- "stage_artifacts/fq233_probe0_20260813/lane_a_feature_panel.parquet"

cat("=== 1) 패널 로드 + long 변환 ===\n")
w <- as.data.table(read_parquet(PAN))
idc <- c("anchor","sig_date","Ticker","fwd_ret_1m")
facs <- setdiff(names(w), idc)
L <- melt(w, id.vars = idc, measure.vars = facs, variable.name = "fac", value.name = "z",
          variable.factor = FALSE)
rm(w); gc(FALSE)
L <- L[is.finite(z) & is.finite(fwd_ret_1m)]
L[, ym := format(as.Date(sig_date), "%Y%m")]
cat(sprintf("  long %d행 · %d팩터 · %d개월\n", nrow(L), uniqueN(L$fac), uniqueN(L$ym)))

cat("\n=== 2) K200 멤버십 (C_k200 arm 용) ===\n")
k2 <- as.data.table(read_parquet(".cache/universe_support/us_k200.parquet"))
k2 <- k2[K200 %in% c(TRUE,1L,1,"1","Y")]
K <- unique(k2[, .(ym = format(as.Date(Date),"%Y%m"), Ticker = as.character(Ticker), inK200 = TRUE)])
L <- merge(L, K, by = c("ym","Ticker"), all.x = TRUE); L[is.na(inK200), inK200 := FALSE]
cat(sprintf("  K200 멤버 행 비중 %.1f%%\n", 100*mean(L$inK200)))

## ── 통계 정의 (r31/r32/r33 과 동일 정의) ────────────────────────────────────
skew <- function(x){ x<-x[is.finite(x)]; n<-length(x); if(n<3) return(NA_real_)
  m<-mean(x); s<-sqrt(sum((x-m)^2)/n); if(s==0) return(NA_real_); sum((x-m)^3)/(n*s^3) }
nw_t <- function(x, L_ = 3L){                    # Newey-West lag-3 t (평균의 t)
  x <- x[is.finite(x)]; n <- length(x); if (n < 12) return(NA_real_)
  e <- x - mean(x); S <- sum(e^2)/n
  for (l in seq_len(L_)) { if (l >= n) break
    S <- S + 2*(1 - l/(L_+1))*sum(e[(l+1):n]*e[1:(n-l)])/n }
  if (!is.finite(S) || S <= 0) return(NA_real_)
  mean(x)/sqrt(S/n)
}
ar1 <- function(x){ x<-x[is.finite(x)]; if(length(x)<12) return(NA_real_)
  suppressWarnings(cor(x[-1], x[-length(x)])) }

arm_stats <- function(D, label){
  cat(sprintf("\n--- arm %s ---\n", label))
  D <- D[, nq := .N, by = .(fac, ym)][nq >= 50]
  if (!nrow(D)) return(NULL)
  D[, q := as.integer(as.character(cut(frank(z, ties.method="average"),
        breaks = quantile(frank(z, ties.method="average"), probs=seq(0,1,.2), na.rm=TRUE),
        include.lowest = TRUE, labels = 1:5))), by = .(fac, ym)]
  pm <- D[, .(mean_r = mean(fwd_ret_1m), med_r = median(fwd_ret_1m), sk = skew(fwd_ret_1m)),
          by = .(fac, ym, q)]
  wq <- dcast(pm, fac + ym ~ q, value.var = c("mean_r","med_r","sk"))
  wq[, `:=`(spread    = mean_r_5 - mean_r_1,
            medspread = med_r_5  - med_r_1,
            skewslope = sk_5     - sk_1)]
  ## m_mono = 인접 5분위 평균의 증가 비율 (0/.25/.5/.75/1)
  mm <- as.matrix(wq[, .(mean_r_1, mean_r_2, mean_r_3, mean_r_4, mean_r_5)])
  wq[, m_mono := rowMeans(t(apply(mm, 1, diff)) > 0)]
  F <- wq[, .(n_month   = .N,
              spread    = mean(spread,    na.rm=TRUE),
              medspread = mean(medspread, na.rm=TRUE),
              skewslope = mean(skewslope, na.rm=TRUE),
              m_mono    = mean(m_mono,    na.rm=TRUE),
              t_spread  = nw_t(spread), t_medspread = nw_t(medspread),
              ar1_spread = ar1(spread), ar1_medspread = ar1(medspread)),
          by = fac]
  F[, gap := medspread - spread]
  cat(sprintf("  팩터 %d · 월 %d (%s ~ %s)\n", nrow(F), uniqueN(wq$ym), min(wq$ym), max(wq$ym)))
  list(F = F, wq = wq, months = uniqueN(wq$ym))
}

headline <- function(F, label, n_months){
  F <- F[is.finite(spread) & is.finite(medspread)]
  sd_ <- F[sign(medspread) != sign(spread)]
  d03t <- nrow(sd_[medspread > 0 & spread < 0]); opp <- nrow(sd_[medspread < 0 & spread > 0])
  cs  <- suppressWarnings(cor(F$skewslope, F$gap, use="complete.obs"))
  msn <- F[is.finite(t_medspread) & is.finite(t_spread) & t_medspread > 2 & abs(t_spread) < 2]
  data.table(
    arm = label, n_months = n_months, n_factors = nrow(F),
    sign_div_n = nrow(sd_), sign_div_pct = round(100*nrow(sd_)/nrow(F),1),
    med_pos_mean_neg = d03t, mean_pos_med_neg = opp,
    cor_skewslope_gap = round(cs, 3),
    mono_over_0.8 = sum(F$m_mono >= 0.8, na.rm=TRUE), m_mono_median = round(median(F$m_mono, na.rm=TRUE),4),
    medsig_meannot_n = nrow(msn), medsig_meannot_pct = round(100*nrow(msn)/nrow(F),1),
    medsig_mean_neg  = nrow(msn[spread < 0]),
    gap_pos_n = sum(F$gap > 0, na.rm=TRUE), gap_pos_pct = round(100*mean(F$gap > 0, na.rm=TRUE),1),
    gap_median_ann_pct = round(100*12*median(F$gap, na.rm=TRUE), 2),
    ar1_spread_median = round(median(F$ar1_spread, na.rm=TRUE),3),
    ar1_medspread_median = round(median(F$ar1_medspread, na.rm=TRUE),3))
}

cat("\n=== 3) arm 실행 ===\n")
arms <- list(
  A_orig     = L,                                   # 전기간 K200∪KQ150 (원 창)
  A_early134 = L[ym <= "201603"],                   # ★길이-정합 통제 (오염창 포함, 134개월)
  B_clean    = L[ym >= "201507"],                   # 청정창
  C_k200     = L[inK200 == TRUE]                    # K200 단독(진단 통제)
)
res <- list(); tabs <- list()
for (nm in names(arms)) { r <- arm_stats(arms[[nm]], nm); res[[nm]] <- r
  tabs[[nm]] <- headline(r$F, nm, r$months); print(tabs[[nm]]) }
TAB <- rbindlist(tabs)
saveRDS(list(res = res, TAB = TAB), file.path(OUT, "fq241_arms.rds"))
fwrite(TAB, file.path(OUT, "fq241_3arm_table.csv"))
cat("\n=== 3 arm 대조표 ===\n"); print(TAB)

cat("\n=== 4) r33 — D03_RealVol 5분위 프로파일 (arm 별) ===\n")
p33 <- rbindlist(lapply(names(res), function(nm){
  wq <- res[[nm]]$wq; D <- arms[[nm]][fac == "D03_RealVol"]
  D <- D[, nq := .N, by = ym][nq >= 50]
  D[, q := as.integer(as.character(cut(frank(z, ties.method="average"),
      breaks = quantile(frank(z, ties.method="average"), probs=seq(0,1,.2), na.rm=TRUE),
      include.lowest = TRUE, labels = 1:5))), by = ym]
  pm <- D[, .(mean_r = mean(fwd_ret_1m), med_r = median(fwd_ret_1m), sk = skew(fwd_ret_1m)), by=.(ym,q)]
  pr <- pm[, .(ann_mean_pct = round(100*12*mean(mean_r, na.rm=TRUE),3),
               ann_med_pct  = round(100*12*mean(med_r,  na.rm=TRUE),3),
               skew         = round(mean(sk, na.rm=TRUE),4)), by=q][order(q)]
  pr[, arm := nm][, n_months := uniqueN(D$ym)][]
}))
print(dcast(p33, arm + n_months ~ q, value.var="ann_mean_pct"))
shape <- p33[, .(peak_q = q[which.max(ann_mean_pct)],
                 mean_spread_51 = round(ann_mean_pct[5]-ann_mean_pct[1],2),
                 med_spread_51  = round(ann_med_pct[5]-ann_med_pct[1],2),
                 skewslope_51   = round(skew[5]-skew[1],4)), by=.(arm,n_months)]
cat("\n"); print(shape)
fwrite(p33, file.path(OUT,"fq241_r33_profile_3arm.csv")); fwrite(shape, file.path(OUT,"fq241_r33_shape_3arm.csv"))
cat("\n완료.\n")
