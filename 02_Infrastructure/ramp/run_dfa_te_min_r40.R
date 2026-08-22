## run_dfa_te_min_r40.R — R40: 25종 내 추적오차 최소화 선택 (prereg dfa_v25, 본 파일 헤더에 사전등록 명시)
## ── 사전등록 (결과 산출 전 기록) ──────────────────────────────────────────────
##  base   : M0 = T3 (목표 비중 상위 25종 + 상한 0.20, 게이트0 100% 준수)
##  근거   : R39 가 '변환이 시장에서 멀어질수록 OOS 가 나빠진다' 를 확정했고(시장상관-OOS 순위 완전 일치),
##           T3 가 살아남은 이유가 우연히 활성 vol 이 작았기 때문(0.090)이라 진단했다.
##           그렇다면 활성 vol 을 **명시적으로 최소화**하는 선택이 T3 보다 나아야 한다. 그 예측을 시험한다.
##  단일 자유도 : 25종 선택 규칙만 교체(목표비중 상위 -> 추적오차 최소 greedy). 비중은 두 팔 모두
##                '선택된 종목의 목표비중 재정규화 + 상한 0.20' 으로 동일. 신호·리밸·비용 전부 고정.
##  헤드라인    : TE_MIN, 15bps, 벤치=parent, full·clean 양 창 보고
##  판정 4조건  : ①full·clean 양 창 calmar > M0 ②oos_retention >= 0.70 ③full PORT_t >= M0 - 0.10
##                ④게이트0 준수 100%
##  예상 실패모드: 추적오차 최소화는 목표(=지수배분 275종)를 잘 복제하는 것이지 **알파를 키우는 것이 아니다**.
##                R39 구조가 옳다면 이 팔은 T3 보다 시장에 더 가까워지고, OOS 안정성은 오르되
##                PORT_t 는 T0(지수팔)에 수렴하며 calmar 는 크게 안 오를 것이다.
##                ★그 경우에도 정보다 — '복제를 잘하면 지수팔에 수렴한다' 가 확인되면
##                  게이트 0 과 알파의 양립 불가가 한 번 더 독립 확인된다.
##  금지        : 사후 셀 선택 · greedy 파라미터(lookback 36M) 그리드 탐색 · 노출축 동시 변경 · 벤치 교체
## ─────────────────────────────────────────────────────────────────────────────
suppressPackageStartupMessages({library(data.table); library(arrow); library(xts)})
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
suppressMessages({library(sandwich); library(lmtest)})
source("02_Infrastructure/config.R"); source("02_Infrastructure/factor_db/factor_db_connector.R")
source("02_Infrastructure/contracts/backtest_result_contract.R")
source("02_Infrastructure/contracts/audit_bt_result.R")
source("02_Infrastructure/contracts/essence_score.R")
IRf  <- function(x){ x<-x[is.finite(x)]; if(length(x)<12) return(NA); mean(x)/sd(x)*sqrt(12) }
nwt  <- function(x){ x<-x[is.finite(x)]; if(length(x)<12) return(NA)
                     m<-lm(x~1); as.numeric(coeftest(m, vcov=NeweyWest(m,lag=3,prewhite=FALSE))[1,3]) }
MDD  <- function(r){ n<-cumprod(1+r); min(n/cummax(n)-1) }
CAGR <- function(r) prod(1+r)^(12/length(r))-1
LB <- 36L   # ★사전 고정 lookback

FAC <- c(Value="V12_Composite_Value", Issuance="V21_Composite_Equity_Issuance", Size="S01_Size",
  Momentum="M09_Composite_Mom", ResidMom="M08_Residual_Mom", Reversal="M11_ST_Reversal",
  Quality="Q08_Composite_Quality", GPA="Q01_GPA", EarnStab="Q07_Earnings_Stability",
  Growth="GR07_Composite_Growth", Investment="IN06_Investment_to_Assets", LowVol="D03_RealVol",
  LowBeta="D02_Beta", TailRisk="R05_Tail_Risk", Liquidity="L45_Composite_Liquidity",
  Accrual="AC18_Accrual_Quality", Consensus="C19_Composite_Earnings", SUE="C01_SUE",
  Crowding="CR07_Momentum_Crowding", ForeignFlow="INV01_Foreign_NetBuy_20d", SmartMoney="INV10_Smart_Money_Flow")
R <- as.data.table(read_parquet("outputs/ramp/dfa_index_returns_broad_202608.parquet"))
R[, Date:=as.Date(Date)]; setorder(R, Date); R <- R[is.finite(Market)]; R[, ym:=format(Date,"%Y-%m")]
fac <- setdiff(names(R), c("Date","ym","as_of_date","source_version","Market"))
mon <- R[, c(lapply(.SD, function(x) prod(1+ifelse(is.finite(x),x,0))-1), .(medate=max(Date))),
         by=ym, .SDcols=c("Market",fac)]
setorder(mon, medate); mon <- mon[ym<="2026-07"]; NM <- nrow(mon); NF <- length(fac)
S <- matrix(NA_real_, NM, NF)
for (fi in 1:NF) for (m in 12:NM)
  S[m,fi] <- prod(1+mon[[fac[fi]]][(m-11):m])/prod(1+mon$Market[(m-11):m]) - 1
rd <- as.data.table(read_parquet(".cache/rawdata.parquet",
        col_select=c("Date","Ticker","Ret","Size","K200","KQ150")))
rd[, Date:=as.Date(Date)]; rd <- rd[is.finite(Ret)]
rd[, inuniv := (!is.na(K200)&K200==1)|(!is.na(KQ150)&KQ150==1)]; rd <- rd[inuniv==TRUE]
rd[, ym:=format(Date,"%Y-%m")]
MR  <- rd[, .(mret=prod(1+Ret)-1), by=.(Ticker,ym)]
UNI <- rd[, .SD[which.max(Date)], by=.(Ticker,ym), .SDcols="Size"]
MRW <- dcast(MR, ym ~ Ticker, value.var="mret")
setorder(MRW, ym); ymv <- MRW$ym; MRM <- as.matrix(MRW[, -1]); colnames(MRM) <- names(MRW)[-1]

cap_w <- function(w, cap=0.20, it=200){ w<-w/sum(w)
  for (i in 1:it) { ov <- w>cap+1e-12; if(!any(ov)) break
    ex<-sum(w[ov]-cap); w[ov]<-cap; fr<-!ov
    if(!any(fr)||sum(w[fr])<=0) break; w[fr]<-w[fr]+ex*w[fr]/sum(w[fr]) }; w/sum(w) }

rebal_m <- seq(13, NM, by=3); HOLD <- list()
for (m in rebal_m) {
  d <- m-1; if (d<12) next
  s <- S[d,]; pos <- which(is.finite(s)&s>0); if(!length(pos)) next
  if (length(pos)>5) pos <- pos[order(s[pos],decreasing=TRUE)][1:5]
  sd_ <- mon$medate[d]; ymd <- mon$ym[d]
  uni <- UNI[ym==ymd, .(Ticker,Size)]; if (nrow(uni)<30) next
  f <- tryCatch(as.data.table(load_month_factors(sd_, factor_names=unname(FAC[fac[pos]]))),
                error=function(e) NULL)
  if (is.null(f)||nrow(f)==0) next
  fm <- merge(f, uni, by="Ticker"); wf <- s[pos]/sum(s[pos]); tgt <- list()
  for (pi in seq_along(pos)) { nmf <- fac[pos[pi]]; sub <- fm[Factor_Name==FAC[nmf]]
    if (nrow(sub)<15) next
    thr <- quantile(sub$Z_Score_Aligned, 0.6667, na.rm=TRUE); sel <- sub[Z_Score_Aligned>=thr]
    sel[, w_in := Size/sum(Size)]; tgt[[nmf]] <- data.table(Ticker=sel$Ticker, w=wf[pi]*sel$w_in) }
  if (!length(tgt)) next
  A0 <- rbindlist(tgt)[, .(w=sum(w)), by=Ticker]; A0[, w:=w/sum(w)]
  M0 <- A0[order(-w)][1:min(25,.N)]; M0[, w:=cap_w(w,0.20)]                    # T3
  ## ★TE_MIN: 인과 trailing 36M 수익으로 목표 시계열 복제하는 greedy 25종 선택
  wi <- which(ymv <= ymd); wi <- wi[max(1,length(wi)-LB+1):length(wi)]
  cn <- intersect(A0$Ticker, colnames(MRM))
  Rm <- MRM[wi, cn, drop=FALSE]; Rm[!is.finite(Rm)] <- 0
  tw <- A0$w[match(cn, A0$Ticker)]; tw <- tw/sum(tw)
  rt <- as.numeric(Rm %*% tw)                                                   # 목표 수익 시계열
  if (nrow(Rm) < 12 || length(cn) < 25) { TE <- copy(M0) } else {
    chosen <- integer(0); rem <- seq_along(cn)
    for (step in 1:25) {
      best <- NA_integer_; bv <- Inf
      for (j in rem) {
        idx <- c(chosen, j); w <- tw[idx]; w <- w/sum(w)
        v <- var(as.numeric(Rm[, idx, drop=FALSE] %*% w) - rt)
        if (is.finite(v) && v < bv) { bv <- v; best <- j } }
      if (is.na(best)) break
      chosen <- c(chosen, best); rem <- setdiff(rem, best) }
    tk <- cn[chosen]; ww <- A0$w[match(tk, A0$Ticker)]
    TE <- data.table(Ticker=tk, w=cap_w(ww, 0.20)) }
  HOLD[[as.character(m)]] <- list(m=m, M0=M0, TE=TE)
  if (length(HOLD)%%15==0) cat("  holdings", length(HOLD), "/", length(rebal_m), "\n")
}
cat("리밸 구성:", length(HOLD), "시점\n")
arms <- c("M0","TE"); PR <- matrix(NA_real_, NM, 2, dimnames=list(NULL,arms))
CMP <- list(); prevW <- setNames(vector("list",2), arms)
for (i in seq_along(HOLD)) { h <- HOLD[[i]]; m0 <- h$m
  mend <- if (i<length(HOLD)) HOLD[[i+1]]$m-1 else NM
  for (a in arms) { W <- h[[a]]; cur <- setNames(W$w, W$Ticker); pw <- prevW[[a]]
    tov <- if (is.null(pw)) 1 else { al <- union(names(cur), names(pw))
      sum(abs(ifelse(is.na(cur[al]),0,cur[al]) - ifelse(is.na(pw[al]),0,pw[al])), na.rm=TRUE) }
    for (mm in m0:mend) { rr <- MR[ym==mon$ym[mm]][match(names(cur),Ticker), mret]; rr[!is.finite(rr)] <- 0
      PR[mm,a] <- sum(cur*rr) - (if (mm==m0) (15/1e4)*tov else 0)
      dd <- cur*(1+rr); cur <- dd/sum(dd) }
    prevW[[a]] <- cur }
  CMP[[length(CMP)+1]] <- data.table(ym=mon$ym[m0], M0_n=nrow(h$M0), M0_maxw=max(h$M0$w),
    TE_n=nrow(h$TE), TE_maxw=max(h$TE$w), overlap=length(intersect(h$M0$Ticker,h$TE$Ticker))) }
CC <- rbindlist(CMP)
k <- which(apply(PR,1,function(v) all(is.finite(v)))); mk <- mon$Market[k]; ymk <- mon$ym[k]
cat("\n=== [1] 게이트 0 + 겹침 ===\n")
for (a in arms) cat(sprintf("  %s: 종목 중앙 %.0f | 최대비중 최대 %.3f | 완전준수 %.0f%%\n", a,
  median(CC[[paste0(a,"_n")]]), max(CC[[paste0(a,"_maxw")]]),
  100*mean(CC[[paste0(a,"_n")]]<=25 & CC[[paste0(a,"_maxw")]]<=0.20+1e-9)))
cat(sprintf("  M0∩TE 겹침 중앙 %.0f/25종\n", median(CC$overlap)))
cat("\n=== [2] 성과 + 시장 근접도 ===\n")
for (w in c("full","clean")) { kk <- if (w=="full") k else k[ymk>="2015-07"]; b <- mon$Market[kk]
  cat(sprintf("\n[%s] n=%d\n", w, length(kk)))
  for (a in arms) { x <- PR[kk,a]
    cat(sprintf("  %-3s CAGR %+.4f MDD %.4f calmar %.4f | PORT_t %+.3f IR %+.3f | 시장상관 %.4f 활성vol %.4f\n",
      a, CAGR(x), MDD(x), CAGR(x)/abs(MDD(x)), nwt(x-b), IRf(x-b), cor(x,b), sd(x-b)*sqrt(12))) } }
cat("\n=== [3] 계약 + 사전등록 4조건 ===\n")
md <- as.Date(sapply(as.Date(paste0(ymk,"-01")), function(z) as.character(seq(z,by="month",length.out=2)[2]-1)))
ES <- list()
for (a in arms) { p <- PR[k,a]
  sim <- list(DAILY_NAV_DT=data.table(Date=md,Strategy_Ret=p,NAV=cumprod(1+p)),
              strategy_xts=xts(p,order.by=md), bm_xts=xts(mk,order.by=md), cost_model_version="dfa_r40")
  spec <- list(strategy_name=paste0("DFA_R40_",a), description="추적오차 최소화 25종 선택",
    universe="K200 U KQ150 (<=25)", rebalance="quarterly", cost="15bps", signal="top-quintile k=5")
  bt <- build_bt_result(sim,spec,run_id=paste0("dfa_r40_",tolower(a)),strategy_id=paste0("DFA_R40_",a),
    benchmark_id="CAPW_PARENT", benchmark_name="parent", transaction_cost_bps=15, slippage_bps=0,
    frequency="monthly", universe_id="K200_KQ150", code_version="run_dfa_te_min_r40.R", created_by_agent="Q-Lead")
  ES[[a]] <- essence_score(bt, n_trials_cumulative=2, selection_type="chain")
  cat(sprintf("  %s: PORT_t %.3f | oos %.3f | calmar %.3f\n", a,
    ES[[a]]$essence$portfolio_alpha_t_nw_lag3, ES[[a]]$essence$oos_retention, ES[[a]]$essence$calmar)) }
kc <- k[ymk>="2015-07"]
c1 <- (CAGR(PR[k,"TE"])/abs(MDD(PR[k,"TE"])) > CAGR(PR[k,"M0"])/abs(MDD(PR[k,"M0"]))) &&
      (CAGR(PR[kc,"TE"])/abs(MDD(PR[kc,"TE"])) > CAGR(PR[kc,"M0"])/abs(MDD(PR[kc,"M0"])))
c2 <- ES$TE$essence$oos_retention >= 0.70
c3 <- nwt(PR[k,"TE"]-mk) >= nwt(PR[k,"M0"]-mk) - 0.10
c4 <- mean(CC$TE_n<=25 & CC$TE_maxw<=0.20+1e-9)==1
cat(sprintf("\n  ①calmar 양창 %s | ②oos>=0.70 %s | ③PORT_t %s | ④게이트0 %s → 판정: %s\n",
  ifelse(c1,"PASS","FAIL"), ifelse(c2,"PASS","FAIL"), ifelse(c3,"PASS","FAIL"), ifelse(c4,"PASS","FAIL"),
  ifelse(all(c1,c2,c3,c4), "채택", "기각 (M0=T3 유지)")))
saveRDS(list(PR=PR,CC=CC,mon=mon,k=k,ES=ES), ".cache/_dfa_r40.rds")
cat("\nR40_DONE\n")
