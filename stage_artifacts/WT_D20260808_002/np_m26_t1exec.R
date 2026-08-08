## T+1 실행앵커 재측정 — ast_verify FAIL_LOOKAHEAD(컨센서스 보수 T-1 = avail t+1d) 정면 대응
##
## 왜: 검증기는 컨센서스 33종(★북 incumbent C01/C02/C04 포함)에 대해 avail = sig_date + 1d 로
##     보수 판정한다(registry 자인 known_discrepancy — 선언 T-1 vs 코드 same-day, 제공시각 미상).
##     따라서 "월말 종가에 신호를 알고 그 종가로 매수"하는 통상 컨벤션은 정적검증을 통과 못 한다.
##     ★TS_LAG 를 AST 에 선언만 하고 측정은 안 하면 거짓 선언이다. 그래서 실제로 늦춰서 잰다.
##
## 설계(측정 전 선언): 신호 = 월말 M 팩터(불변). 수익 = 익월 M+1 **첫 거래일 종가** →
##                     M+2 첫 거래일 종가. 즉 의사결정 후 1거래일 뒤 체결하는 실행 컨벤션.
##                     병합 = align_signal_return_ym(off=+1, return_dating="realized_month").
## ★주판정 대체 아님 — 사전등록 주판정은 불변, 본 측정은 PIT 강건성 축으로 병기한다.
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- file.path(ROOT,"stage_artifacts/WT_D20260808_002")
say <- function(fmt,...) { cat(sprintf(paste0("[t1] ",fmt,"\n"),...)); flush.console() }
source("02_Infrastructure/config.R")
source("02_Infrastructure/ramp/factor_validation.R")
source("02_Infrastructure/contracts/align_signal_return_ym.R")
nw_t <- function(x, lag=3L){ x<-x[is.finite(x)]; n<-length(x); if(n<20) return(NA_real_)
  m<-mean(x); e<-x-m; s<-sum(e^2)/n
  for(l in 1:lag) s <- s + 2*(1-l/(lag+1))*sum(e[(l+1):n]*e[1:(n-l)])/n; m/sqrt(s/n) }
FACS <- c("C01_SUE","C02_EPS_Chg_1m","C04_ESBR","M26_Revenue_Mom")

## ---- 입력 실측 ----
A <- as.data.table(read_parquet(file.path(OUT,"alpha_scores.parquet")))
A[, Date := as.Date(Date)]
say("★입력 실측: 신호 패널 %d행 · %d개월 · 관측단위 (월말 신호 Date × Ticker) · %s ~ %s",
    nrow(A), uniqueN(A$Date), min(A$signal_ym), max(A$signal_ym))

RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
        col_select=c("Date","Ticker","Close","Vol","Size","K200","KQ150")))
RAW[, Date := as.Date(Date)]
say("RAWDATA %d행 · 고유 Date %d ⇒ 일간", nrow(RAW), uniqueN(RAW$Date))

## 각 캘린더월의 **첫 거래일** 앵커
FD <- RAW[, .(Date = min(Date)), by=.(ym = format(Date,"%Y-%m"))][order(Date)]
say("첫-거래일 앵커 %d개 · %s ~ %s", nrow(FD), min(FD$Date), max(FD$Date))
RAWFD <- RAW[Date %in% FD$Date]; rm(RAW); gc(FALSE)
fwd1 <- build_monthly_forward_returns(RAWFD, FD$Date)
r1 <- fwd1$returns_dt[, .(Date=as.Date(Date), Ticker, Ret_1m)]
say("T+1 실행앵커 수익 패널: %d행 · %d개월 · %s ~ %s (Date = 체결 시작 거래일)",
    nrow(r1), uniqueN(r1$Date), min(r1$Date), max(r1$Date))
say("  ★이 패널의 Date 는 신호월(M)이 아니라 **체결월(M+1) 첫 거래일** ⇒ realized_month · off=+1")

## ---- 병합 (표준 헬퍼, look-ahead 가드가 off<=0 를 거부한다) ----
S <- A[, c("Date", "Ticker", FACS), with=FALSE]
setnames(S, "Date", "signal_date")
M <- align_signal_return_ym(S, r1, signal_date_col="signal_date", return_date_col="Date",
                            id_col="Ticker", off=1L, return_dating="realized_month",
                            coverage_min=0.90, vintage_label="t1_exec_anchor_v1")
say("병합 %d행 · 월 coverage %.3f · 행 coverage %.3f", nrow(M),
    attr(M,"align_coverage_month"), attr(M,"align_coverage_row"))
D <- M[is.finite(Ret_1m) & complete.cases(M[, ..FACS])]
mm <- D[, .N, by=signal_ym]; D <- D[signal_ym %in% mm[N>=30L, signal_ym]]
say("★complete-case %d 종목-월 · %d개월 (%s ~ %s) · 월중앙 종목수 %.0f",
    nrow(D), uniqueN(D$signal_ym), min(D$signal_ym), max(D$signal_ym), median(mm$N))

## ---- FMB ----
f <- as.formula(paste("Ret_1m ~", paste(FACS, collapse=" + ")))
CF <- D[, { fit <- lm(f, data=.SD); cf <- coef(fit); .(term=names(cf), est=as.numeric(cf)) },
        by=signal_ym, .SDcols=c("Ret_1m", FACS)]
tab <- CF[term!="(Intercept)", .(n=.N, mean=mean(est), sd=sd(est), t_nw3=nw_t(est), pos=mean(est>0)), by=term]
say("--- T+1 실행앵커 4-팩터 FMB ---")
for (i in seq_len(nrow(tab))) with(tab[i], say(
  "  %-18s n=%3d · mean %+.5f · t_NW3 %+.2f · 부호>0 %.1f%%", term, n, mean, t_nw3, pos*100))
TT <- tab[term=="M26_Revenue_Mom"]
say("★★T+1 주판정량 z(M26) FMB NW3 t = %+.3f (기준 월말종가 앵커 +2.555) ⇒ 유지율 %.2f",
    TT$t_nw3, TT$t_nw3/2.555)
ic <- D[, .(ic=suppressWarnings(cor(M26_Revenue_Mom, Ret_1m, method="spearman", use="complete.obs"))), by=signal_ym][is.finite(ic)]
say("  M26 단독 rank IC: 평균 %+.4f · t_NW3 %+.2f (기준 +0.0179 / +2.97)", mean(ic$ic), nw_t(ic$ic))

fwrite(CF,  file.path(OUT,"m26_t1exec_coefs.csv"))
fwrite(tab, file.path(OUT,"m26_t1exec_summary.csv"))
saveRDS(list(tab=tab, ic=ic, n_months=TT$n), file.path(OUT,"m26_t1exec.rds"))
say("저장 완료")
