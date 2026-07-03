## ============================================================================
## STR_1715 — 2026-06-01 sig_date Iter5 alpha EXTENSION (체인 토대)
## _recompute_may_refresh.R 적응: sig_date 05-01 → 06-01, end-May 데이터(factor_db_202605)
##   PIT: 06-01 결정은 ≤05-29 데이터 → factor_db_202605(Date 2026-05-31, 최종거래 05-29) PIT-clean.
##   기존행(05-01 포함) 전부 보존 + 06-01 추가 → run_all이 May period [05-01,06-01) 마감 가능.
## ============================================================================
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)})
options(scipen = 999); Sys.setenv(TZ = "Asia/Seoul")
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
source(file.path(ROOT, "02_Infrastructure/config.R"))
source(file.path(ROOT, "02_Infrastructure/factor_db/factor_db_connector.R"))
`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0) a else b

SLEEVE_CORE    <- c("C01_SUE", "C02_EPS_Chg_1m", "C04_ESBR", "C06_TP_Gap")
SLEEVE_DEFENSE <- c("Q07_Earnings_Stability", "M08_Residual_Mom", "Q25_Ohlson_O")
JUNE_SIG <- as.Date("2026-06-01")
PIT_REF  <- as.Date("2026-05-29")          # 5월 마지막 영업일
REGIME_JUNE <- "CAUTION"                    # compute_june_regime.R 신선계산
W_CORE <- 0.65; W_DEF <- 0.35
winsor_z <- function(x, sigma=2.5){m<-mean(x,na.rm=T);s<-sd(x,na.rm=T);if(is.na(s)||s<1e-10)return(x);pmax(pmin(x,m+sigma*s),m-sigma*s)}

## 1. Core theta (expanding-IC, PIT Usable_Date < 06-01)
ic <- as.data.table(read_parquet(file.path(ROOT,".cache/factor_db/factor_ic_monthly.parquet")))
ic[, Date:=as.Date(Date)]; ic[, Usable_Date:=as.Date(Usable_Date)]
past_ic <- ic[Usable_Date < JUNE_SIG & !is.na(IC) & Factor_Name %in% SLEEVE_CORE]
icm <- past_ic[, .(mean_IC=mean(IC,na.rm=T), n=.N), by=Factor_Name]
theta_raw <- setNames(pmax(icm$mean_IC,0), icm$Factor_Name)
theta_core <- setNames(rep(0,length(SLEEVE_CORE)), SLEEVE_CORE)
for (fn in names(theta_raw)) theta_core[fn] <- theta_raw[fn]
theta_core <- theta_core/sum(abs(theta_core))
theta_def <- setNames(rep(1/length(SLEEVE_DEFENSE),length(SLEEVE_DEFENSE)), SLEEVE_DEFENSE)
cat("[theta] Core (expanding-IC, Usable_Date<2026-06-01):\n"); print(round(theta_core,4))
cat(sprintf("  (max signal Date = %s)\n", as.character(max(past_ic$Date))))

## 2. end-May Z (Core4 + Q07 + Q25 from 202605)
f5 <- as.data.table(read_parquet(file.path(ROOT,".cache/factor_db/factor_db_202605.parquet"),
  col_select=c("Ticker","Factor_Name","Z_Score","Coverage")))
need <- c(SLEEVE_CORE,"Q07_Earnings_Stability","Q25_Ohlson_O")
f5 <- f5[Factor_Name %in% need & Coverage==TRUE & !is.na(Z_Score), .(Ticker,Factor_Name,Z_Score)]
f5[, sig_date:=JUNE_SIG]
cat(sprintf("[202605] %d rows | factors: %s\n", nrow(f5), paste(sort(unique(f5$Factor_Name)),collapse=",")))

## 3. M08 from 202604 (202605 미보유 — FORCED, 2개월 stale momentum 주의)
f4 <- as.data.table(read_parquet(file.path(ROOT,".cache/factor_db/factor_db_202604.parquet"),
  col_select=c("Ticker","Factor_Name","Z_Score","Coverage")))
m08 <- f4[Factor_Name=="M08_Residual_Mom" & Coverage==TRUE & !is.na(Z_Score), .(Ticker,Factor_Name,Z_Score)]
m08[, sig_date:=JUNE_SIG]
cat(sprintf("[202604] M08: %d rows (FORCED — 06-01엔 2개월 stale momentum, 202605 미보유)\n", nrow(m08)))
fdb <- rbind(f5, m08)

## 4. Direction alignment (C13/C14)
fdb_al <- align_factor_direction(fdb, .load_registry(), sig_date=JUNE_SIG, min_ic_months=12L)
if ("Z_Score_Aligned" %in% names(fdb_al)) { fdb_al[, Z_Score:=Z_Score_Aligned]; fdb_al[, Z_Score_Aligned:=NULL] }
fw <- dcast(fdb_al, sig_date+Ticker ~ Factor_Name, value.var="Z_Score", fill=NA_real_)

## 5. Liquidity (C10, t-1 AvgTV20>=2e8 @ <=05-29)
raw <- as.data.table(read_parquet(file.path(ROOT,".cache/rawdata.parquet"), col_select=c("Date","Ticker","Close","Vol")))
raw[, Date:=as.Date(Date)]; raw[, TV:=Close*Vol]
raw[order(Date), AvgTV20_t:=frollmean(TV,20L,align="right"), by=Ticker]
raw[order(Date), AvgTV20:=shift(AvgTV20_t,1L,type="lag"), by=Ticker]
pit_close <- raw[Date<=PIT_REF, max(Date)]
liq <- raw[Date==pit_close & !is.na(AvgTV20) & AvgTV20>=2e8, .(Ticker)]
cat(sprintf("[liq] PIT close=%s | liquid=%d\n", as.character(pit_close), nrow(liq)))
fw <- merge(fw, liq, by="Ticker")

## 6. Universe (K200 u KQ150, <=05-29)
k200 <- as.data.table(read_parquet(file.path(ROOT,".cache/universe_support/us_k200.parquet")))
kq150<- as.data.table(read_parquet(file.path(ROOT,".cache/universe_support/us_kq150.parquet")))
k200[, Date:=as.Date(Date)]; kq150[, Date:=as.Date(Date)]
k2d<-k200[Date<=PIT_REF,max(Date)]; kqd<-kq150[Date<=PIT_REF,max(Date)]
uni <- unique(c(k200[Date==k2d & K200==1,Ticker], kq150[Date==kqd & KQ150==1,Ticker]))
fw <- fw[Ticker %in% uni]
cat(sprintf("[universe] k200=%s kq150=%s | union=%d | panel=%d\n", as.character(k2d),as.character(kqd),length(uni),nrow(fw)))

## 7. Sleeve composite
agg <- function(df,facs,w){fac<-intersect(names(w),facs);fac<-intersect(fac,names(df));W<-as.numeric(w[fac]);W<-W/sum(W);X<-as.matrix(df[,..fac]);X<-apply(X,2,winsor_z,sigma=2.5);X[is.na(X)]<-0;as.numeric(X%*%W)}
core_p<-intersect(SLEEVE_CORE,names(fw)); def_p<-intersect(SLEEVE_DEFENSE,names(fw))
cat(sprintf("[sleeve] core=%s | defense=%s\n", paste(core_p,collapse=","), paste(def_p,collapse=",")))
fw[, Score_Core:=agg(.SD,core_p,theta_core)]; fw[, Score_Defense:=agg(.SD,def_p,theta_def)]
zc<-function(x){m<-mean(x,na.rm=T);s<-sd(x,na.rm=T);if(is.na(s)||s<1e-10)x-m else (x-m)/s}
fw[, Score_Core_z:=zc(Score_Core)]; fw[, Score_Defense_z:=zc(Score_Defense)]
fw[, score_eff:=W_CORE*Score_Core_z + W_DEF*Score_Defense_z]

## 8. Assemble 06-01 row
june_alpha <- fw[, .(Date=sig_date, Ticker, score_eff, score_core_z=Score_Core_z, score_defense_z=Score_Defense_z,
  Ret_1m=NA_real_, regime_state=REGIME_JUNE,
  theta_core=toJSON(as.list(round(theta_core,4)),auto_unbox=TRUE),
  theta_defense=toJSON(as.list(round(theta_def,4)),auto_unbox=TRUE))]
setkey(june_alpha, Date, Ticker)
cat(sprintf("[june_alpha] %d rows | non-NA score_eff=%d\n", nrow(june_alpha), sum(!is.na(june_alpha$score_eff))))
cat("Top 15 by score_eff:\n"); print(june_alpha[order(-score_eff)][1:15,.(Ticker,score_eff=round(score_eff,4))])

## 9. Splice: 기존 전부 보존 + 06-01 추가 (run_all이 May period 마감)
ap <- file.path(ROOT,"stage_artifacts/WT_D20260425_010/alpha_scores.parquet")
ex <- as.data.table(read_parquet(ap)); ex[, Date:=as.Date(Date)]
ex[, theta_core:=as.character(theta_core)]; ex[, theta_defense:=as.character(theta_defense)]
bk <- file.path(ROOT,"stage_artifacts/WT_D20260425_010/alpha_scores_PRE_june_ext.parquet")
if (!file.exists(bk)) { write_parquet(ex, bk); cat(sprintf("[backup] %s\n", bk)) }
kept <- ex[Date != JUNE_SIG]   # 05-01 등 전부 보존, 기존 06-01만 교체
june_alpha[, theta_core:=as.character(theta_core)]; june_alpha[, theta_defense:=as.character(theta_defense)]
merged <- rbind(kept, june_alpha, use.names=TRUE, fill=TRUE); setkey(merged, Date, Ticker)
# Windows mmap temp-rename
.tmp <- paste0(ap,".tmp"); write_parquet(merged, .tmp)
if (file.exists(ap)) file.remove(ap); file.rename(.tmp, ap)
cat(sprintf("[write] alpha_scores.parquet (%d rows, %s ~ %s | sig_dates=%d)\n",
  nrow(merged), as.character(min(merged$Date)), as.character(max(merged$Date)), uniqueN(merged$Date)))
cat("\n=== June alpha extension DONE ===\n")
