## FQ-241 stage3 — 검정력·유의성 진단 (차이없음 vs 검출불가 구분 + 지속회귀변수 caveat)
suppressPackageStartupMessages({library(data.table)})
OUT <- "stage_artifacts/FQ241_blast_radius_20260822"
S <- readRDS(file.path(OUT,"fq241_factor_stats.rds")); FA <- S$FA; W <- as.data.table(S$W)

cat("=== A) D03_RealVol arm 별 스프레드 + NW3 t ===\n")
d <- FA[fac=="D03_RealVol", .(arm, n_month,
        mean_spread_ann = round(100*12*spread,2), t_spread = round(t_spread,3),
        med_spread_ann  = round(100*12*medspread,2), t_medspread = round(t_medspread,3),
        skewslope = round(skewslope,4), ar1_spread = round(ar1_spread,3))]
print(d)

cat("\n=== B) arm 별 최소검출효과 (MDE, |t|=2 기준, 평균 스프레드) ===\n")
mde <- FA[, .(n_month = as.integer(round(median(n_month))),
              sd_spread_med = round(median(sd_spread, na.rm=TRUE),5)), by=arm]
mde[, mde_monthly := 2*sd_spread_med/sqrt(n_month)]
mde[, mde_ann_pct := round(100*12*mde_monthly,2)]
print(mde[, .(arm, n_month, sd_spread_med, mde_ann_pct)])
cat("★해석: |t|>2 를 쓰는 지표(#4)는 창이 짧아지면 개수가 기계적으로 줄어든다.\n",
    "  A_early134(135m) 와 B_clean(133m) 은 길이-정합이므로 그 둘의 차이만 era 귀속 가능.\n")

cat("\n=== C) 지속 회귀변수 caveat 진단 (Lane D φ 0.95~0.99 경고 적용 여부) ===\n")
ac <- FA[, .(ar1_spread_med = round(median(ar1_spread,na.rm=TRUE),3),
             ar1_spread_p95 = round(quantile(ar1_spread,.95,na.rm=TRUE),3),
             ar1_spread_max = round(max(ar1_spread,na.rm=TRUE),3),
             ar1_medspread_med = round(median(ar1_medspread,na.rm=TRUE),3),
             n_over_0.5 = sum(ar1_spread > 0.5, na.rm=TRUE),
             n_over_0.9 = sum(ar1_spread > 0.9, na.rm=TRUE)), by=arm]
print(ac)

cat("\n=== D) 지표2 (cor(skewslope, gap)) 팩터-부트스트랩 95% CI ===\n")
set.seed(20260822)
bs <- FA[, {f <- .SD[is.finite(skewslope) & is.finite(gap)]
            v <- replicate(2000, { i <- sample(.N <- nrow(f), nrow(f), TRUE)
                                   suppressWarnings(cor(f$skewslope[i], f$gap[i])) })
            .(cor = round(cor(f$skewslope,f$gap),3),
              lo = round(quantile(v,.025,na.rm=TRUE),3), hi = round(quantile(v,.975,na.rm=TRUE),3))}, by=arm]
print(bs)

cat("\n=== E) 지표1 (부호 갈림) — 창 길이 비민감 확인 + 비대칭비 ===\n")
sd1 <- FA[is.finite(spread)&is.finite(medspread),
          {x <- .SD[sign(medspread)!=sign(spread)]
           .(n_fac=nrow(.SD), n_div=nrow(x), pct=round(100*nrow(x)/nrow(.SD),1),
             medPos_meanNeg=nrow(x[medspread>0&spread<0]), meanPos_medNeg=nrow(x[medspread<0&spread>0]),
             asym_ratio=round(nrow(x[medspread>0&spread<0])/max(1,nrow(x[medspread<0&spread>0])),2),
             binom_p=signif(binom.test(nrow(x[medspread>0&spread<0]), nrow(x), 0.5)$p.value,3))}, by=arm]
print(sd1)
cat("★지표1 은 유의성 문턱을 쓰지 않는다 = 창 길이에 기계적으로 민감하지 않음(부호만 본다).\n")

cat("\n=== F) 지표5 (gap>0 비율) 이항검정 ===\n")
g5 <- FA[is.finite(gap), .(n=.N, k=sum(gap>0), pct=round(100*mean(gap>0),1),
                           binom_p=signif(binom.test(sum(gap>0), .N, 0.5)$p.value,3)), by=arm]
print(g5)

cat("\n=== G) 지표4 (t_med>2 & |t_mean|<2) 길이-정합 대조 ===\n")
m4 <- FA[is.finite(t_medspread)&is.finite(t_spread),
         .(n_fac=.N, n=sum(t_medspread>2 & abs(t_spread)<2),
           of_mean_neg=sum(t_medspread>2 & abs(t_spread)<2 & spread<0),
           n_tmed_over2=sum(t_medspread>2)), by=arm]
print(m4)

saveRDS(list(d=d,mde=mde,ac=ac,bs=bs,sd1=sd1,g5=g5,m4=m4), file.path(OUT,"fq241_diagnostics.rds"))
fwrite(bs, file.path(OUT,"fq241_metric2_bootstrap.csv"))
fwrite(mde, file.path(OUT,"fq241_mde.csv"))
cat("\n[stage3 완료]\n")
