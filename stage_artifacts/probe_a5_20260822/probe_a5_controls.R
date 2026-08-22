## probe_a5_controls.R — 프로브 2단: B3w(내재비중) 양성이 신호인지 mega-cap 틸트인지 분리
## 통제군:
##   E1 = 시총 top-25 cap-w (신호 0 — 순수 mega-cap 패시브)
##   E2 = B1 선택(Z-합성) x cap-비례 가중          → "가중법만" 효과
##   E3 = pi 선택/가중인데 w_f = 1/21 고정          → "A5 팩터모멘텀 배분" 효과 (B3w의 대조군)
##   E4 = B3w 선택 유지, 가중만 EW                  → (= 1단 B3, 재게시)
## + EW-유니버스 basis 진단(dual-basis) 전 팔 병기
suppressPackageStartupMessages({library(data.table); library(arrow)})
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
setDTthreads(4)
source("02_Infrastructure/config.R")
source("02_Infrastructure/factor_db/factor_db_connector.R")
source("02_Infrastructure/contracts/backtest_result_contract.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/contracts/weighted_screen_bt.R")
source("02_Infrastructure/ramp/factor_validation.R")
suppressMessages({library(sandwich); library(lmtest)})
OUT <- file.path(QM, "stage_artifacts/probe_a5_20260822")
nwt <- function(x){x<-x[is.finite(x)]; if(length(x)<12) return(NA_real_)
  m<-lm(x~1); as.numeric(coeftest(m, vcov=sandwich::NeweyWest(m, lag=3, prewhite=FALSE))[1,3])}
IRf <- function(x){x<-x[is.finite(x)]; if(length(x)<6) return(NA_real_); mean(x)/sd(x)*sqrt(12)}

P <- readRDS(file.path(OUT,"probe_a5_stock25.rds"))
ZP <- readRDS(file.path(OUT,"_zpanel.rds"))
DEC <- P$DEC; Wapp <- P$Wapp
FAC <- c(Value="V12_Composite_Value", Issuance="V21_Composite_Equity_Issuance", Size="S01_Size",
         Momentum="M09_Composite_Mom", ResidMom="M08_Residual_Mom", Reversal="M11_ST_Reversal",
         Quality="Q08_Composite_Quality", GPA="Q01_GPA", EarnStab="Q07_Earnings_Stability",
         Growth="GR07_Composite_Growth", Investment="IN06_Investment_to_Assets",
         LowVol="D03_RealVol", LowBeta="D02_Beta", TailRisk="R05_Tail_Risk",
         Liquidity="L45_Composite_Liquidity", Accrual="AC18_Accrual_Quality",
         Consensus="C19_Composite_Earnings", SUE="C01_SUE", Crowding="CR07_Momentum_Crowding",
         ForeignFlow="INV01_Foreign_NetBuy_20d", SmartMoney="INV10_Smart_Money_Flow")
facn <- names(FAC)

## 데이터 재구성 (1단과 동일 규약)
RAW <- as.data.table(read_parquet(".cache/rawdata.parquet",
        col_select=c("Date","Ticker","Close","Vol","Size","K200","KQ150")))
RAW[, Date := as.Date(Date)]
RAW <- RAW[Date >= as.Date("2021-01-01") & Date <= as.Date("2026-07-31")]
alld <- sort(unique(RAW$Date)); rym <- format(alld,"%Y-%m")
ME_all <- alld[!duplicated(rym, fromLast=TRUE)]
ME <- ME_all[format(ME_all,"%Y-%m") >= "2021-07" & format(ME_all,"%Y-%m") <= "2026-07"]
ADV20 <- build_adv20_t1(RAW[, .(Date,Ticker,Vol,Close)], at_dates=ME)
RAWME <- RAW[Date %in% ME]; rm(RAW); invisible(gc())
fwd <- build_monthly_forward_returns(RAWME, ME, liq_daily=ADV20)
RET <- fwd$returns_dt[, .(Date=as.Date(Date), Ticker, Ret_1m)]
BEN <- fwd$bench_dt[, .(Date=as.Date(Date), BM_Ret)]
LIQ <- fwd$liq_dt[, .(Date=as.Date(Date), Ticker, adv)]

capw <- function(v, cap=0.20){ w <- v/sum(v)
  for(k in 1:200){ if(max(w) <= cap+1e-12) break
    ex <- pmax(w-cap,0); w <- pmin(w,cap); w <- w + sum(ex)*w/sum(w) }
  w/sum(w) }

## 스코어 생성기 (1단과 동일 로직, wsrc/mode 파라미터화)
mk <- function(mode, wsrc){
  rows <- vector("list", nrow(DEC))
  for(i in seq_len(nrow(DEC))){ d0 <- DEC$d0[i]; z <- ZP[[as.character(d0)]]
    if(is.null(z)) next
    wv <- if(identical(wsrc,"EW")) setNames(rep(1/length(facn),length(facn)),facn)
          else setNames(Wapp[DEC$mrow[i], -1], facn)
    if(sum(wv) <= 1e-12) next
    f <- z$f; tk <- z$uni$Ticker; capv <- setNames(z$uni$cap, z$uni$Ticker)
    sc <- setNames(rep(0,length(tk)),tk); hit <- setNames(rep(0,length(tk)),tk)
    for(nm in facn){ wf <- wv[[nm]]; if(!is.finite(wf)||wf<=0) next
      sub <- f[Factor_Name==FAC[[nm]] & is.finite(Z_Score_Aligned)]; if(nrow(sub)<15) next
      if(mode=="B1"){ v <- setNames(sub$Z_Score_Aligned, sub$Ticker)
        sc[names(v)] <- sc[names(v)] + wf*v; hit[names(v)] <- hit[names(v)] + wf
      } else { thr <- quantile(sub$Z_Score_Aligned, 2/3, na.rm=TRUE)
        H <- sub[Z_Score_Aligned>=thr, Ticker]; if(!length(H)) next
        cw <- capv[H]; sc[H] <- sc[H] + wf*cw/sum(cw); hit[H] <- hit[H] + wf } }
    keep <- hit>0; if(!any(keep)) next
    rows[[i]] <- data.table(Date=d0, Ticker=names(sc)[keep], score=as.numeric(sc[keep]),
                            cap=as.numeric(capv[names(sc)[keep]]))
  }
  rbindlist(rows) }

SB1 <- mk("B1","A5"); SB3 <- mk("B3","A5"); SE3 <- mk("B3","EW")
CAPALL <- rbindlist(lapply(seq_len(nrow(DEC)), function(i){ d0<-DEC$d0[i]; z<-ZP[[as.character(d0)]]
  if(is.null(z)) return(NULL); data.table(Date=d0, Ticker=z$uni$Ticker, score=z$uni$cap, cap=z$uni$cap)}))

## 팔 정의: list(scores, wmode)  wmode in {"EW","CAP","PI"}
build_w <- function(S, wmode){
  s <- merge(S[is.finite(score) & score>0], LIQ, by=c("Date","Ticker"), all.x=TRUE)
  s <- s[is.na(adv) | adv >= 2e8]
  setorder(s, Date, -score); s <- s[, head(.SD, 25L), by=Date]
  s[, w := switch(wmode, EW = rep(1/.N,.N), CAP = capw(cap), PI = capw(score)), by=Date]
  s }
ARMS <- list(
  E1_capw_passive = list(S=CAPALL, wm="CAP"),
  E2_B1sel_capw   = list(S=SB1,    wm="CAP"),
  E3_piEW_ctrl    = list(S=SE3,    wm="PI"),
  B3w_A5          = list(S=SB3,    wm="PI"),
  B3_EW           = list(S=SB3,    wm="EW"),
  B1_EW           = list(S=SB1,    wm="EW"))

## EW-유니버스 벤치(dual-basis 진단) — 계약 내부 헬퍼와 동일 정의(월별 유니버스 EW 수익)
UNIV <- rbindlist(lapply(seq_len(nrow(DEC)), function(i){ d0<-DEC$d0[i]; z<-ZP[[as.character(d0)]]
  if(is.null(z)) return(NULL); data.table(Date=d0, Ticker=z$uni$Ticker)}))
EWB <- merge(UNIV, RET, by=c("Date","Ticker"))[, .(EW_Ret=mean(Ret_1m)), by=Date]

res <- rbindlist(lapply(names(ARMS), function(nm){ a <- ARMS[[nm]]
  W <- build_w(a$S, a$wm)
  ws <- weighted_screen_bt(W[, .(Date,Ticker,w)], RET, BEN, cost_bps_oneway=15,
        run_id=paste0("probe2_",tolower(nm)), strategy_id=paste0("PROBE2_",nm))
  pr <- as.data.table(ws$period_returns); act <- pr$ret_net - pr$benchmark_ret
  pe <- merge(pr, EWB, by.x="date", by.y="Date"); acte <- pe$ret_net - pe$EW_Ret
  conc <- W[, .(top1=max(w), eff_n=1/sum(w^2), n=.N), by=Date]
  data.table(arm=nm, n=ws$n_months,
    PORT_t=ws$portfolio_alpha_t_nw_lag3, IR=ws$information_ratio,
    active_ann=100*mean(act)*12, netSR=IRf(pr$ret_net), TO=ws$turnover_annual,
    ewuni_t=nwt(acte), ewuni_active_ann=100*mean(acte)*12,
    top1_w=mean(conc$top1), eff_n=mean(conc$eff_n)) }))
cat("\n== 프로브 2단 통제군 (2021-08~2026-07, 60개월, top-25 long-only, 15bps, adv20>=2e8) ==\n")
print(res, digits=3)

## 시장(cap-w)·EW-유니버스 기준자
mkt <- BEN[Date %in% DEC$d0]
cat(sprintf("\n[기준] cap-w 벤치 연평균 %+.2f%% | EW-유니버스 연평균 %+.2f%% (n=%d)\n",
  100*mean(mkt$BM_Ret)*12, 100*mean(EWB$EW_Ret)*12, nrow(mkt)))

## paired NW-t : B3w_A5 vs E3(팩터모멘텀 무배분 대조군) / vs E1(패시브)
gp <- function(nm){ a<-ARMS[[nm]]; W<-build_w(a$S,a$wm)
  ws<-weighted_screen_bt(W[,.(Date,Ticker,w)],RET,BEN,cost_bps_oneway=15,
      run_id="p",strategy_id="p"); as.data.table(ws$period_returns) }
pa <- gp("B3w_A5"); pc <- gp("E3_piEW_ctrl"); pp <- gp("E1_capw_passive")
m1 <- merge(pa[,.(date,a=ret_net)], pc[,.(date,c=ret_net)], by="date")
m2 <- merge(pa[,.(date,a=ret_net)], pp[,.(date,p=ret_net)], by="date")
cat(sprintf("[paired NW-t] B3w_A5 − E3(w_f=1/21 대조군) = %+.3f (Δ연평균 %+.2f%%p)\n",
  nwt(m1$a-m1$c), 100*mean(m1$a-m1$c)*12))
cat(sprintf("[paired NW-t] B3w_A5 − E1(mega-cap 패시브)  = %+.3f (Δ연평균 %+.2f%%p)\n",
  nwt(m2$a-m2$p), 100*mean(m2$a-m2$p)*12))

fwrite(res, file.path(OUT,"probe_a5_controls_results.csv"))
saveRDS(list(res=res, EWB=EWB, pa=pa, pc=pc, pp=pp), file.path(OUT,"probe_a5_controls.rds"))
cat("\nPROBE_A5_CTRL_DONE\n")
