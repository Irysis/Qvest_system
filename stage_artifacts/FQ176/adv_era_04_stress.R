## FQ176 적대검증 — 렌즈 era_split · STEP 4: 내 반증 자체를 스트레스
##  A. 시대별 자격게이트 재계산 (자격 자체가 전표본 구성물인가)
##  B. 절단점 민감도 (2012 컷이 만든 결과인가)
##  C. 에피소드 분해 (시대 = 위기 정체성과 교락되는가)
##  D. 순열검정 (부호반전 13/21 이 우연과 구별되는가)
## metric_type = canonical_screen_diag. 자본 주장 없음.
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/FQ176")
say  <- function(fmt, ...) { cat(sprintf(paste0("[era4] ", fmt, "\n"), ...)); flush.console() }
SE_INFL <- 1.25; T_CRIT <- 2.0

IC  <- as.data.table(readRDS(file.path(OUT,"ic_series.rds"))); IC[, Date := as.Date(Date)]
SIG <- fread(file.path(OUT,"signals.csv")); SIG[, Date := as.Date(Date)]
ELI <- as.data.table(readRDS(file.path(OUT,"eligible.rds")))
mo  <- sort(unique(SIG$Date))
PRIM <- fread(file.path(OUT,"adv_era_measured_all.csv"))[, .(factor, signal, primary)] |> unique()

align_dt <- function(f, s, al) {
  ics <- IC[factor==f][order(Date)]
  ICI <- merge(ics[,.(ic_date=Date, ic)], data.table(ic_date=mo, ki=seq_along(mo)), by="ic_date")
  A <- data.table(sig_date=mo, k=seq_along(mo), on=SIG[match(mo, Date)][[s]])
  A[, ki := k + fifelse(al=="same", 0L, 1L)]
  merge(A, ICI, by="ki")[order(sig_date)]
}
dstat <- function(M) {
  on <- M[on==TRUE]$ic; off <- M[on==FALSE]$ic
  if (length(on)<2 || length(off)<2) return(list(d=NA_real_,t=NA_real_,req=NA_real_,n_on=length(on)))
  sdv <- sd(M$ic); d <- mean(on)-mean(off)
  se <- sdv*sqrt(1/length(on)+1/length(off))*SE_INFL
  list(d=d, t=d/se, req=T_CRIT*se, n_on=length(on))
}

## ---------------- A. 시대별 자격게이트 ----------------
say("=== A. 자격게이트를 시대별로 재계산 (전표본 ic_mean/ic_sd 로 만든 게이트인가) ===")
say("  규칙(원본 그대로): required = 2*ic_sd*sqrt(1/n_ON+1/n_OFF)*1.25 ; 자격 = required <= 2*|ic_mean|")
EF <- sort(unique(IC$factor))
gate <- list()
for (sc in c("FULL","E1","E2")) {
  ICs <- switch(sc, FULL=IC, E1=IC[Date<=as.Date("2012-12-31")], E2=IC[Date>as.Date("2012-12-31")])
  SGs <- switch(sc, FULL=SIG, E1=SIG[Date<=as.Date("2012-12-31")], E2=SIG[Date>as.Date("2012-12-31")])
  ST <- ICs[, .(ic_mean=mean(ic), ic_sd=sd(ic), n=.N), by=factor]
  for (s in c("S1","S2","S3")) {
    non <- sum(SGs[[s]]); noff <- nrow(SGs)-non
    if (non<1 || noff<1) next
    G <- copy(ST)[, `:=`(signal=s, scope=sc,
        required=2*ic_sd*sqrt(1/non+1/noff)*1.25, bar=2*abs(ic_mean))]
    G[, `:=`(ratio=required/bar, eligible=required<=bar)]
    gate[[length(gate)+1L]] <- G
  }
}
GA <- rbindlist(gate)
for (sc in c("FULL","E1","E2"))
  say("  %s: 자격통과 %d / %d쌍", sc, sum(GA[scope==sc]$eligible), nrow(GA[scope==sc]))
key_full <- GA[scope=="FULL" & eligible==TRUE, paste(factor,signal)]
key_e1   <- GA[scope=="E1" & eligible==TRUE, paste(factor,signal)]
key_e2   <- GA[scope=="E2" & eligible==TRUE, paste(factor,signal)]
say("  FULL자격 %d쌍 중 E1 에서도 자격 %d · E2 에서도 자격 %d · 양 시대 모두 %d",
    length(key_full), sum(key_full %in% key_e1), sum(key_full %in% key_e2),
    sum(key_full %in% intersect(key_e1,key_e2)))
say("  ★FULL 자격인데 E2 에서 자격상실: %s",
    paste(setdiff(key_full, key_e2), collapse=" | "))
say("  ★E2 에서 신규 자격(FULL 비자격): %d쌍 %s", length(setdiff(key_e2,key_full)),
    paste(head(setdiff(key_e2,key_full),8), collapse=" | "))
fwrite(GA, file.path(OUT,"adv_era_gate_by_era.csv"))

## ---------------- B. 절단점 민감도 ----------------
say("=== B. 절단점 민감도 (2012 컷이 만든 결과인가) ===")
cuts <- as.Date(c("2009-12-31","2010-12-31","2012-12-31","2015-12-31","2017-12-31"))
sens <- list()
for (i in seq_len(nrow(ELI))) {
  f <- ELI$factor[i]; s <- ELI$signal[i]
  al <- PRIM[factor==f & signal==s]$primary[1]
  M <- align_dt(f,s,al)
  for (cu in cuts) {
    cu <- as.Date(cu, origin="1970-01-01")
    a <- dstat(M[sig_date<=cu]); b <- dstat(M[sig_date>cu])
    sens[[length(sens)+1L]] <- data.table(factor=f, signal=s, cut=cu,
      d_early=a$d, d_late=b$d, t_early=a$t, t_late=b$t,
      n_on_early=a$n_on, n_on_late=b$n_on,
      sign_match=ifelse(is.na(a$d)||is.na(b$d), NA, sign(a$d)==sign(b$d)))
  }
}
SN <- rbindlist(sens)
say("  컷별 부호일치 비율 (판정가능 쌍 기준):")
for (cu in cuts) {
  X <- SN[cut==as.Date(cu, origin="1970-01-01") & !is.na(sign_match)]
  say("   컷 %s: 일치 %d/%d (%.0f%%) · early n_ON 중앙 %.0f / late n_ON 중앙 %.0f",
      format(as.Date(cu,origin="1970-01-01")), sum(X$sign_match), nrow(X),
      100*mean(X$sign_match), median(X$n_on_early), median(X$n_on_late))
}
## risk_vol 6종의 부호 패턴이 컷 전반에 안정적인가
RV <- c("R01_VaR_95","R02_VaR_99","R03_CVaR_95","R04_CVaR_99","D01_IdioVol","D03_RealVol")
say("  ★risk_vol 6종 (전표본 5/6 양수) 의 컷별 early/late 부호:")
for (cu in cuts) {
  X <- SN[cut==as.Date(cu,origin="1970-01-01") & factor %in% RV]
  say("   컷 %s: early 양수 %d/6 · late 양수 %d/6 · 부호일치 %d/6",
      format(as.Date(cu,origin="1970-01-01")), sum(X$d_early>0,na.rm=TRUE),
      sum(X$d_late>0,na.rm=TRUE), sum(X$sign_match,na.rm=TRUE))
}
fwrite(SN, file.path(OUT,"adv_era_cut_sensitivity.csv"))

## ---------------- C. 에피소드 분해 ----------------
say("=== C. 에피소드 분해 (시대 = 위기 정체성과 교락되는가) ===")
v <- SIG$S3; rl <- rle(v); ends <- cumsum(rl$lengths); starts <- ends-rl$lengths+1L
epi_idx <- which(rl$values)
EPI <- data.table(epi=seq_along(epi_idx), start=SIG$Date[starts[epi_idx]],
                  end=SIG$Date[ends[epi_idx]], len=rl$lengths[epi_idx])
print(EPI)
epi_rows <- list()
for (i in seq_len(nrow(ELI))) {
  f <- ELI$factor[i]; s <- ELI$signal[i]
  if (s != "S3") next
  al <- PRIM[factor==f & signal==s]$primary[1]
  M <- align_dt(f,s,al)
  off_mean <- mean(M[on==FALSE]$ic)
  for (e in seq_len(nrow(EPI))) {
    onv <- M[on==TRUE & sig_date>=EPI$start[e] & sig_date<=EPI$end[e]]$ic
    epi_rows[[length(epi_rows)+1L]] <- data.table(factor=f, epi=e,
      window=sprintf("%s~%s", format(EPI$start[e]), format(EPI$end[e])),
      n=length(onv), ic_on=mean(onv), d_vs_off=mean(onv)-off_mean)
  }
}
EP <- rbindlist(epi_rows)
EW <- dcast(EP, factor ~ epi, value.var="d_vs_off")
setnames(EW, c("1","2","3","4"), c("e1_2003","e2_2008_09","e3_2018_19","e4_2022_23"))
say("  팩터별 에피소드 dIC (OFF 평균 대비):")
for (i in seq_len(nrow(EW)))
  say("   %-29s 2003 %+.4f | 2008-09 %+.4f | 2018-19 %+.4f | 2022-23 %+.4f",
      EW$factor[i], EW$e1_2003[i], EW$e2_2008_09[i], EW$e3_2018_19[i], EW$e4_2022_23[i])
say("  에피소드별 양수 팩터 수 (총 %d): 2003 %d · 2008-09 %d · 2018-19 %d · 2022-23 %d",
    nrow(EW), sum(EW$e1_2003>0), sum(EW$e2_2008_09>0), sum(EW$e3_2018_19>0), sum(EW$e4_2022_23>0))
say("  ★에피소드 간 상관 (팩터 프로파일): 2003vs2008 %+.2f · 2018vs2022 %+.2f · E1평균vsE2평균 %+.2f",
    cor(EW$e1_2003, EW$e2_2008_09), cor(EW$e3_2018_19, EW$e4_2022_23),
    cor((EW$e1_2003+EW$e2_2008_09)/2, (EW$e3_2018_19+EW$e4_2022_23)/2))
fwrite(EW, file.path(OUT,"adv_era_episode_decomp.csv"))

## ---------------- D. 순열검정 ----------------
say("=== D. 순열검정: 관측 부호반전 13/21 이 우연 대비 이례적인가 ===")
set.seed(20260809)
WD <- fread(file.path(OUT,"adv_era_reproduction.csv"))
obs_match <- sum(WD$sign_match, na.rm=TRUE); n_pair <- sum(!is.na(WD$sign_match))
say("  관측: 부호일치 %d / %d", obs_match, n_pair)
## 귀무 = 신호 라벨을 블록 단위로 순환이동 (ON 군집구조 보존)
NPERM <- 500L
perm_match <- integer(NPERM)
S3v <- SIG$S3; nT <- length(S3v)
pairs_use <- WD[!is.na(sign_match) & signal=="S3", .(factor, alignment)]
for (p in seq_len(NPERM)) {
  shiftk <- sample.int(nT-1L, 1L)
  sv <- c(S3v[(nT-shiftk+1):nT], S3v[1:(nT-shiftk)])
  SP <- data.table(Date=SIG$Date, S3p=sv)
  cnt <- 0L; den <- 0L
  for (j in seq_len(nrow(pairs_use))) {
    f <- pairs_use$factor[j]; al <- pairs_use$alignment[j]
    ics <- IC[factor==f][order(Date)]
    ICI <- merge(ics[,.(ic_date=Date, ic)], data.table(ic_date=mo, ki=seq_along(mo)), by="ic_date")
    A <- data.table(sig_date=mo, k=seq_along(mo), on=SP[match(mo,Date)]$S3p)
    A[, ki := k + fifelse(al=="same",0L,1L)]
    M <- merge(A, ICI, by="ki")
    a <- dstat(M[sig_date<=as.Date("2012-12-31")]); b <- dstat(M[sig_date>as.Date("2012-12-31")])
    if (!is.na(a$d) && !is.na(b$d)) { den <- den+1L; if (sign(a$d)==sign(b$d)) cnt <- cnt+1L }
  }
  perm_match[p] <- cnt
}
say("  순열(블록 순환이동, %d회) 하 부호일치 분포: mean %.2f · sd %.2f · [q05 %.0f, q95 %.0f] (분모 %d)",
    NPERM, mean(perm_match), sd(perm_match), quantile(perm_match,.05), quantile(perm_match,.95), den)
obs_s3 <- sum(WD[signal=="S3"]$sign_match, na.rm=TRUE)
say("  관측(S3 만) %d vs 순열평균 %.2f -> 양측 p = %.3f",
    obs_s3, mean(perm_match), mean(abs(perm_match-mean(perm_match)) >= abs(obs_s3-mean(perm_match))))
say("=== STEP4 완료 ===")
