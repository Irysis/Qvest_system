## FQ176 적대검증 — 렌즈 era_split · STEP 5: 내 스트레스 결과 자체를 검증
##  E. 컷 민감도가 진짜 독립검정이었나 (에피소드 공백 때문에 vacuous 아닌가)
##  F. E2 에서 유일하게 자격유지한 쌍 식별
##  G. 4/4 에피소드 부호일관 팩터 = 우연 기대와 비교
##  H. 생존후보(GR02) 의 검정력 바
suppressPackageStartupMessages({ library(data.table) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/FQ176")
say  <- function(fmt, ...) { cat(sprintf(paste0("[era5] ", fmt, "\n"), ...)); flush.console() }

SIG <- fread(file.path(OUT,"signals.csv")); SIG[, Date := as.Date(Date)]
GA  <- fread(file.path(OUT,"adv_era_gate_by_era.csv"))
EW  <- fread(file.path(OUT,"adv_era_episode_decomp.csv"))
IC  <- as.data.table(readRDS(file.path(OUT,"ic_series.rds"))); IC[, Date := as.Date(Date)]
mo  <- sort(unique(SIG$Date))

## ---- E. 컷 민감도 vacuity 검증 ----
say("=== E. 컷 민감도가 독립적 5회 검정이었나 ===")
on_d <- SIG[S3==TRUE]$Date
say("  S3 ON 월 범위: %s ~ %s (총 %d개월)", format(min(on_d)), format(max(on_d)), length(on_d))
gap_lo <- max(on_d[on_d < as.Date("2018-01-01")]); gap_hi <- min(on_d[on_d > as.Date("2010-01-01")])
say("  ★ON 공백구간: %s ~ %s 사이에 ON 월 %d개",
    format(gap_lo), format(gap_hi), sum(on_d > gap_lo & on_d < gap_hi))
cuts <- as.Date(c("2009-12-31","2010-12-31","2012-12-31","2015-12-31","2017-12-31"))
for (cu in cuts) {
  cu <- as.Date(cu, origin="1970-01-01")
  say("   컷 %s -> early ON %d / late ON %d", format(cu), sum(on_d<=cu), sum(on_d>cu))
}
say("  -> 5개 컷 전부 동일한 ON 분할(32/14). 즉 'B의 컷 안정성'은 독립검정 5회가 아니라")
say("     동일검정 5회 = ★vacuous. 나의 앞선 안정성 주장은 여기서 자가정정한다.")
say("  -> 따라서 era_split ≡ 에피소드 분할 {2003,2008-09} vs {2018-19,2022-23}")

## ---- F. E2 자격유지 쌍 ----
say("=== F. 시대별 자격게이트 상세 ===")
for (sc in c("FULL","E1","E2")) {
  X <- GA[scope==sc & eligible==TRUE]
  say("  %s 자격통과 %d쌍: %s", sc, nrow(X),
      ifelse(nrow(X)==0,"(없음)", paste(sprintf("%s/%s", X$factor, X$signal), collapse=" | ")))
}
say("  E1 자격 10쌍 중 FULL 자격에도 있던 쌍: %d",
    sum(paste(GA[scope=="E1"&eligible==TRUE]$factor, GA[scope=="E1"&eligible==TRUE]$signal) %in%
        paste(GA[scope=="FULL"&eligible==TRUE]$factor, GA[scope=="FULL"&eligible==TRUE]$signal)))
say("  ★자격 상실률: FULL 21쌍 -> E1 유지 %d (%.0f%%) · E2 유지 %d (%.0f%%)",
    sum(paste(GA[scope=="E1"&eligible==TRUE]$factor,GA[scope=="E1"&eligible==TRUE]$signal) %in%
        paste(GA[scope=="FULL"&eligible==TRUE]$factor,GA[scope=="FULL"&eligible==TRUE]$signal)),
    100*sum(paste(GA[scope=="E1"&eligible==TRUE]$factor,GA[scope=="E1"&eligible==TRUE]$signal) %in%
        paste(GA[scope=="FULL"&eligible==TRUE]$factor,GA[scope=="FULL"&eligible==TRUE]$signal))/21,
    nrow(GA[scope=="E2"&eligible==TRUE]), 100*nrow(GA[scope=="E2"&eligible==TRUE])/21)

## ---- G. 4/4 에피소드 부호일관 ----
say("=== G. 에피소드 4/4 부호일관 팩터 vs 우연 기대 ===")
E <- as.matrix(EW[, .(e1_2003, e2_2008_09, e3_2018_19, e4_2022_23)])
rownames(E) <- EW$factor
npos <- rowSums(E > 0)
all4 <- names(npos)[npos==4L]; all0 <- names(npos)[npos==0L]
say("  전부 양수 팩터: %d개 %s", length(all4), paste(all4, collapse=", "))
say("  전부 음수 팩터: %d개 %s", length(all0), ifelse(length(all0)==0,"(없음)",paste(all0, collapse=", ")))
n_fac <- nrow(E)
exp_consistent <- n_fac * 2 / 2^4
say("  일관(4/4 동부호) 관측 %d개 vs 우연기대 %.2f개 (%d팩터 x 2/16)",
    length(all4)+length(all0), exp_consistent, n_fac)
say("  -> 관측 일관성이 우연기대 %s -> 에피소드 일관성 자체가 신호 아님",
    ifelse(length(all4)+length(all0) >= exp_consistent, "이상", "★미만"))
say("  npos 분포 (0..4): %s", paste(sprintf("%d개=%d팩터", 0:4, tabulate(npos+1L, 5L)), collapse=" · "))

## ---- H. GR02 검정력 바 ----
say("=== H. 유일 4/4 일관 후보 GR02_Earnings_Growth 의 검정력 ===")
f <- "GR02_Earnings_Growth"
ics <- IC[factor==f][order(Date)]
ICI <- merge(ics[,.(ic_date=Date, ic)], data.table(ic_date=mo, ki=seq_along(mo)), by="ic_date")
A <- data.table(sig_date=mo, k=seq_along(mo), on=SIG[match(mo,Date)]$S3)
A[, ki := k+1L]
M <- merge(A, ICI, by="ki")[order(sig_date)]
for (sc in c("FULL","E1","E2")) {
  MM <- switch(sc, FULL=M, E1=M[sig_date<=as.Date("2012-12-31")], E2=M[sig_date>as.Date("2012-12-31")])
  on <- MM[on==TRUE]$ic; off <- MM[on==FALSE]$ic
  d <- mean(on)-mean(off); se <- sd(MM$ic)*sqrt(1/length(on)+1/length(off))*1.25
  say("  %s: dIC %+.5f · t %+.3f · 필요|dIC|(t=2) %.5f · 관측/필요 %.0f%% · n_ON %d",
      sc, d, d/se, 2*se, 100*abs(d)/(2*se), length(on))
}
## 에피소드를 1관측으로 접은 t (유효표본 = 4)
epi <- data.table(start=as.Date(c("2003-01-30","2008-01-31","2018-10-31","2022-06-30")),
                  end  =as.Date(c("2003-11-28","2009-09-30","2019-01-31","2023-03-31")))
off_mean <- mean(M[on==FALSE]$ic)
dv <- sapply(seq_len(nrow(epi)), function(e)
  mean(M[on==TRUE & sig_date>=epi$start[e] & sig_date<=epi$end[e]]$ic) - off_mean)
say("  에피소드 dIC 4개: %s", paste(sprintf("%+.4f", dv), collapse=" "))
tt <- t.test(dv)
say("  에피소드-수준 t (유효표본 n=4): t %+.3f · p %.3f · 95%%CI [%+.4f, %+.4f]",
    tt$statistic, tt$p.value, tt$conf.int[1], tt$conf.int[2])
say("  -> 유효표본이 4 이므로 이 t 는 판정근거가 아니라 검정력 진단이다.")
say("=== STEP5 완료 ===")
