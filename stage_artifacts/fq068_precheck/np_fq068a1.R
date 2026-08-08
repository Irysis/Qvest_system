## FQ-068a1 — 하위군 분할 대신 **전표본 상호작용**으로 군 간 차이 추정 (오늘 규약 첫 적용)
## 모형: Ret_1m ~ score + score:grp  (반도체 전체 패널, 월 고정효과는 횡단면 demean 으로 대체)
## 분할이면 군당 26~71개월이지만, 상호작용이면 전 표본 2,244 종목-월을 유지한다.
suppressPackageStartupMessages({ library(data.table); library(arrow); library(lubridate) })
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- file.path(ROOT,"stage_artifacts/fq068_precheck")
say <- function(fmt,...) cat(sprintf(paste0("[068a1] ",fmt,"\n"),...))
source("02_Infrastructure/config.R"); source("02_Infrastructure/ramp/factor_validation.R")

GRP <- list(
  장비   = c("A036930","A240810","A095610","A084370","A319660","A403870","A042700",
             "A039030","A348210","A420770","A089030","A079370","A253590","A036810"),
  소재   = c("A005290","A357780","A166090","A074600","A064760","A101490","A183300"),
  후공정 = c("A036540","A067310","A131970","A095340","A058470","A131290","A232140"),
  설계IDM= c("A005930","A000660","A000990","A080220","A399720","A402340"))
map <- rbindlist(lapply(names(GRP), function(g) data.table(Ticker=GRP[[g]], grp=g)))

RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
        col_select=c("Date","Ticker","Close","Vol","Size","K200","KQ150")))
RAW[, Date := as.Date(Date)]; RAW[, ym := format(Date,"%Y-%m")]
ME <- sort(RAW[, .(Date=max(Date)), by=ym]$Date); RAWME <- RAW[Date %in% ME]; rm(RAW); gc(FALSE)
fwd <- build_monthly_forward_returns(RAWME, ME)
ret <- fwd$returns_dt[, .(Date=as.Date(Date), Ticker, Ret_1m)]
U <- RAWME[(K200==TRUE|KQ150==TRUE) & !is.na(Size)&Size>0, .(Date,Ticker)]
P <- merge(U, ret, by=c("Date","Ticker")); P[, ym := format(Date,"%Y-%m")]

ppi <- as.data.table(read_parquet(file.path(OUT,"fq068_ppi_raw.parquet")))
ppi <- ppi[Series_ID=="PCU334413334413"][order(Date)]
ppi[, `:=`(dppi=Value/shift(Value,1)-1, mom6=Value/shift(Value,6)-1)]
ppi[, ref_ym := format(Date,"%Y-%m")]; ppi[, hold_ym := format(Date %m+% months(2), "%Y-%m")]

R <- merge(P[, .(ym,Ticker,Ret_1m)], ppi[, .(ref_ym,dppi)], by.x="ym", by.y="ref_ym")
setorder(R, Ticker, ym); W <- 36L
R[, beta_ppi := { n<-.N; o<-rep(NA_real_,n)
  if (n>=W) for (i in W:n) { idx<-(i-W+1):i; y<-Ret_1m[idx]; x<-dppi[idx]
    if (sum(is.finite(y)&is.finite(x))>=24 && sd(x,na.rm=TRUE)>0)
      o[i] <- cov(y,x,use="complete.obs")/var(x,use="complete.obs") }
  o }, by=Ticker]

S <- merge(R[, .(ym,Ticker,beta_ppi,Ret_1m)], ppi[, .(hold_ym,mom6_pit=mom6)], by.x="ym", by.y="hold_ym")
S <- merge(S, map, by="Ticker")[is.finite(beta_ppi) & is.finite(mom6_pit) & is.finite(Ret_1m)]
S[, score := beta_ppi * sign(mom6_pit)]
## 월별 횡단면 표준화(월 고정효과 대체) — 시장 공통성분 제거
S[, `:=`(z = (score - mean(score))/pmax(sd(score),1e-9),
         y = Ret_1m - mean(Ret_1m)), by=ym]
S <- S[is.finite(z) & is.finite(y)]
S[, grp := factor(grp, levels=c("장비","소재","후공정","설계IDM"))]
say("전표본 %d 종목-월 · %d개월 · 군별 %s", nrow(S), uniqueN(S$ym),
    paste(sprintf("%s=%d", levels(S$grp), table(S$grp)), collapse=" "))

say("--- ① 전표본 단일 기울기 (대조) ---")
m0 <- lm(y ~ z, data=S); c0 <- summary(m0)$coefficients
say("  z 계수 %+.5f (t %.2f, p %.3f) · n=%d", c0["z","Estimate"], c0["z","t value"], c0["z","Pr(>|t|)"], nrow(S))

say("--- ② 전표본 상호작용: z x 군 (기준=장비) ---")
m1 <- lm(y ~ z * grp, data=S); c1 <- summary(m1)$coefficients
rows <- rownames(c1)[grepl("^z", rownames(c1))]
for (rn in rows) say("  %-18s %+.5f (t %+.2f, p %.3f)", rn, c1[rn,"Estimate"], c1[rn,"t value"], c1[rn,"Pr(>|t|)"])
say("--- ③ 군 간 차이 전체 유의성 (F-test: 상호작용항 동시 0) ---")
a <- anova(m0, m1)
say("  F = %.2f · df = %d · p = %.4f", a$F[2], a$Df[2], a$`Pr(>F)`[2])
say("--- 검정력 대조: 분할 설계는 군당 26~71개월이었으나 상호작용은 전표본 %d 관측 ---", nrow(S))
