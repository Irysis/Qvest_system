## run_dfa_middle_form_r39.R — R39: T1~T3 중간 형태 (prereg dfa_v24_20260822)
## M2 = 각 선택 팩터가 자기 top-10 만 지명 -> 후보 풀(<=50) -> 목표 포트폴리오 비중 상위 25종 + 상한 0.20
## 단일 자유도 = 후보 풀 형성 방식. 나머지 전부 T3 고정.
suppressPackageStartupMessages({library(data.table); library(arrow); library(xts)})
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
suppressMessages({library(sandwich); library(lmtest)})
source("02_Infrastructure/config.R"); source("02_Infrastructure/factor_db/factor_db_connector.R")
source("02_Infrastructure/contracts/backtest_result_contract.R")
source("02_Infrastructure/contracts/audit_bt_result.R")
source("02_Infrastructure/contracts/essence_score.R")
IRf  <- function(x){ x <- x[is.finite(x)]; if (length(x) < 12) return(NA); mean(x)/sd(x)*sqrt(12) }
nwt  <- function(x){ x <- x[is.finite(x)]; if (length(x) < 12) return(NA)
                     m <- lm(x ~ 1); as.numeric(coeftest(m, vcov=NeweyWest(m, lag=3, prewhite=FALSE))[1,3]) }
MDD  <- function(r){ n <- cumprod(1+r); min(n/cummax(n)-1) }
CAGR <- function(r) prod(1+r)^(12/length(r))-1
NOM <- 10L   # ★사전 고정: 팩터별 지명 폭. 그리드 탐색 금지.

FAC <- c(Value="V12_Composite_Value", Issuance="V21_Composite_Equity_Issuance", Size="S01_Size",
  Momentum="M09_Composite_Mom", ResidMom="M08_Residual_Mom", Reversal="M11_ST_Reversal",
  Quality="Q08_Composite_Quality", GPA="Q01_GPA", EarnStab="Q07_Earnings_Stability",
  Growth="GR07_Composite_Growth", Investment="IN06_Investment_to_Assets", LowVol="D03_RealVol",
  LowBeta="D02_Beta", TailRisk="R05_Tail_Risk", Liquidity="L45_Composite_Liquidity",
  Accrual="AC18_Accrual_Quality", Consensus="C19_Composite_Earnings", SUE="C01_SUE",
  Crowding="CR07_Momentum_Crowding", ForeignFlow="INV01_Foreign_NetBuy_20d", SmartMoney="INV10_Smart_Money_Flow")

R <- as.data.table(read_parquet("outputs/ramp/dfa_index_returns_broad_202608.parquet"))
R[, Date := as.Date(Date)]; setorder(R, Date); R <- R[is.finite(Market)]; R[, ym := format(Date,"%Y-%m")]
fac <- setdiff(names(R), c("Date","ym","as_of_date","source_version","Market"))
mon <- R[, c(lapply(.SD, function(x) prod(1+ifelse(is.finite(x),x,0))-1), .(medate=max(Date))),
         by = ym, .SDcols = c("Market", fac)]
setorder(mon, medate); mon <- mon[ym <= "2026-07"]; NM <- nrow(mon); NF <- length(fac)
S <- matrix(NA_real_, NM, NF)
for (fi in 1:NF) for (m in 12:NM)
  S[m, fi] <- prod(1 + mon[[fac[fi]]][(m-11):m]) / prod(1 + mon$Market[(m-11):m]) - 1

rd <- as.data.table(read_parquet(".cache/rawdata.parquet",
        col_select = c("Date","Ticker","Ret","Size","K200","KQ150")))
rd[, Date := as.Date(Date)]; rd <- rd[is.finite(Ret)]
rd[, inuniv := (!is.na(K200)&K200==1) | (!is.na(KQ150)&KQ150==1)]
rd <- rd[inuniv == TRUE]; rd[, ym := format(Date,"%Y-%m")]
MR  <- rd[, .(mret = prod(1+Ret)-1), by = .(Ticker, ym)]
UNI <- rd[, .SD[which.max(Date)], by = .(Ticker, ym), .SDcols = "Size"]

cap_w <- function(w, cap = 0.20, iters = 200){
  w <- w/sum(w)
  for (i in 1:iters) { ov <- w > cap + 1e-12; if (!any(ov)) break
    ex <- sum(w[ov] - cap); w[ov] <- cap; fr <- !ov
    if (!any(fr) || sum(w[fr]) <= 0) break
    w[fr] <- w[fr] + ex * w[fr]/sum(w[fr]) }
  w/sum(w) }

rebal_m <- seq(13, NM, by = 3); HOLD <- list()
for (m in rebal_m) {
  d <- m-1; if (d < 12) next
  s <- S[d, ]; pos <- which(is.finite(s) & s > 0); if (!length(pos)) next
  if (length(pos) > 5) pos <- pos[order(s[pos], decreasing=TRUE)][1:5]
  sd_ <- mon$medate[d]; ymd <- mon$ym[d]
  uni <- UNI[ym == ymd, .(Ticker, Size)]; if (nrow(uni) < 30) next
  f <- tryCatch(as.data.table(load_month_factors(sd_, factor_names = unname(FAC[fac[pos]]))),
                error = function(e) NULL)
  if (is.null(f) || nrow(f) == 0) next
  fm <- merge(f, uni, by = "Ticker"); wf <- s[pos]/sum(s[pos])
  tgt <- list(); nomi <- character(0)
  for (pi in seq_along(pos)) {
    nmf <- fac[pos[pi]]; sub <- fm[Factor_Name == FAC[nmf]]; if (nrow(sub) < 15) next
    thr <- quantile(sub$Z_Score_Aligned, 0.6667, na.rm = TRUE)
    sel <- sub[Z_Score_Aligned >= thr]; sel[, w_in := Size/sum(Size)]
    tgt[[nmf]] <- data.table(Ticker = sel$Ticker, w = wf[pi]*sel$w_in)      # 목표 포트폴리오
    top <- sub[order(-Z_Score_Aligned)][1:min(NOM, .N)]                      # ★팩터별 지명(top-10)
    nomi <- union(nomi, top$Ticker)
  }
  if (!length(tgt)) next
  A0 <- rbindlist(tgt)[, .(w = sum(w)), by = Ticker]; A0[, w := w/sum(w)]
  M0 <- A0[order(-w)][1:min(25, .N)]; M0[, w := cap_w(w, 0.20)]             # T3
  cand <- A0[Ticker %in% nomi]                                              # ★M2 후보 풀 = 지명 종목
  if (nrow(cand) == 0) next
  M2 <- cand[order(-w)][1:min(25, .N)]; M2[, w := cap_w(w, 0.20)]
  HOLD[[as.character(m)]] <- list(m = m, M0 = M0, M2 = M2, npool = nrow(cand))
  if (length(HOLD) %% 15 == 0) cat("  holdings", length(HOLD), "/", length(rebal_m), "\n")
}
cat("리밸 구성:", length(HOLD), "시점 | 평균 후보 풀 =",
    round(mean(sapply(HOLD, function(h) h$npool)), 1), "종\n")

arms <- c("M0","M2")
PR <- matrix(NA_real_, NM, 2, dimnames = list(NULL, arms)); CMP <- list()
prevW <- setNames(vector("list", 2), arms)
for (i in seq_along(HOLD)) {
  h <- HOLD[[i]]; m0 <- h$m; mend <- if (i < length(HOLD)) HOLD[[i+1]]$m - 1 else NM
  for (a in arms) {
    W <- h[[a]]; cur <- setNames(W$w, W$Ticker); pw <- prevW[[a]]
    tov <- if (is.null(pw)) 1 else { allt <- union(names(cur), names(pw))
      sum(abs(ifelse(is.na(cur[allt]),0,cur[allt]) - ifelse(is.na(pw[allt]),0,pw[allt])), na.rm=TRUE) }
    for (mm in m0:mend) {
      rr <- MR[ym == mon$ym[mm]][match(names(cur), Ticker), mret]; rr[!is.finite(rr)] <- 0
      PR[mm, a] <- sum(cur*rr) - (if (mm == m0) (15/1e4)*tov else 0)
      dd <- cur*(1+rr); cur <- dd/sum(dd) }
    prevW[[a]] <- cur
  }
  CMP[[length(CMP)+1]] <- data.table(ym = mon$ym[m0], npool = h$npool,
    M0_n = nrow(h$M0), M0_maxw = max(h$M0$w), M2_n = nrow(h$M2), M2_maxw = max(h$M2$w),
    overlap = length(intersect(h$M0$Ticker, h$M2$Ticker)))
}
CC <- rbindlist(CMP)
cat("\n=== [1] 게이트 0 준수 + 두 팔의 겹침 ===\n")
for (a in arms) cat(sprintf("  %s: 종목수 중앙 %.0f | 최대비중 최대 %.3f | 완전준수 %.0f%%\n",
    a, median(CC[[paste0(a,"_n")]]), max(CC[[paste0(a,"_maxw")]]),
    100*mean(CC[[paste0(a,"_n")]] <= 25 & CC[[paste0(a,"_maxw")]] <= 0.20+1e-9)))
cat(sprintf("  후보 풀 중앙 %.0f종 | M0∩M2 겹침 중앙 %.0f종 (M2 가 실제로 다른 종목을 담는지)\n",
    median(CC$npool), median(CC$overlap)))

k <- which(apply(PR, 1, function(v) all(is.finite(v)))); mk <- mon$Market[k]; ymk <- mon$ym[k]
cat("\n=== [2] 성과 (parent 기준) ===\n")
for (w in c("full","clean")) {
  kk <- if (w == "full") k else k[ymk >= "2015-07"]; b <- mon$Market[kk]
  cat(sprintf("\n[%s] n=%d\n", w, length(kk)))
  for (a in arms) { x <- PR[kk,a]
    cat(sprintf("  %-4s CAGR %+.4f MDD %.4f calmar %.4f | PORT_t %+.3f IR %+.3f\n",
        a, CAGR(x), MDD(x), CAGR(x)/abs(MDD(x)), nwt(x-b), IRf(x-b))) }
}
cat("\n=== [3] 계약 경유 + 사전등록 4조건 ===\n")
md <- as.Date(sapply(as.Date(paste0(ymk,"-01")), function(z) as.character(seq(z, by="month", length.out=2)[2]-1)))
ES <- list()
for (a in arms) { p <- PR[k,a]
  sim <- list(DAILY_NAV_DT=data.table(Date=md, Strategy_Ret=p, NAV=cumprod(1+p)),
              strategy_xts=xts(p, order.by=md), bm_xts=xts(mk, order.by=md), cost_model_version="dfa_r39")
  spec <- list(strategy_name=paste0("DFA_R39_",a), description="중간 형태 종목 전파",
    universe="K200 U KQ150 (<=25)", rebalance="quarterly", cost="15bps", signal="top-quintile k=5")
  bt <- build_bt_result(sim, spec, run_id=paste0("dfa_r39_",tolower(a)), strategy_id=paste0("DFA_R39_",a),
    benchmark_id="CAPW_PARENT", benchmark_name="parent", transaction_cost_bps=15, slippage_bps=0,
    frequency="monthly", universe_id="K200_KQ150", code_version="run_dfa_middle_form_r39.R",
    created_by_agent="Q-Lead")
  ES[[a]] <- essence_score(bt, n_trials_cumulative=2, selection_type="chain")
  cat(sprintf("  %s: PORT_t %.3f | oos %.3f {%s} | calmar %.3f\n", a,
      ES[[a]]$essence$portfolio_alpha_t_nw_lag3, ES[[a]]$essence$oos_retention,
      paste(sprintf("%.2f", ES[[a]]$oos_retention_splits), collapse=","), ES[[a]]$essence$calmar)) }
kc <- k[ymk >= "2015-07"]
c1 <- (CAGR(PR[k,"M2"])/abs(MDD(PR[k,"M2"])) > CAGR(PR[k,"M0"])/abs(MDD(PR[k,"M0"]))) &&
      (CAGR(PR[kc,"M2"])/abs(MDD(PR[kc,"M2"])) > CAGR(PR[kc,"M0"])/abs(MDD(PR[kc,"M0"])))
c2 <- ES$M2$essence$oos_retention >= 0.70
c3 <- nwt(PR[k,"M2"]-mk) >= nwt(PR[k,"M0"]-mk) - 0.10
c4 <- mean(CC$M2_n <= 25 & CC$M2_maxw <= 0.20+1e-9) == 1
cat(sprintf("\n  ①calmar 양창 개선 %s | ②oos>=0.70 %s | ③PORT_t >= M0-0.10 %s | ④게이트0 100%% %s\n",
    ifelse(c1,"PASS","FAIL"), ifelse(c2,"PASS","FAIL"), ifelse(c3,"PASS","FAIL"), ifelse(c4,"PASS","FAIL")))
cat(sprintf("  ★판정: %s\n", ifelse(all(c1,c2,c3,c4), "채택", "기각 (M0=T3 유지)")))
saveRDS(list(PR=PR, CC=CC, mon=mon, k=k, ES=ES), ".cache/_dfa_r39.rds")
fwrite(CC, "outputs/ramp/dfa_middle_form_r39_20260822.csv")
cat("\nR39_DONE\n")
