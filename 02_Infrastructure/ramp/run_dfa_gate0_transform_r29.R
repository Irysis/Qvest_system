## run_dfa_gate0_transform_r29.R — R29: 게이트 0(배포 형태) 제약 내재화 변환 (prereg dfa_v20_20260822)
## T0 지수배분(대조) / T1 팩터별 5종 배정 / T2 목표비중 상위25 복제 / T3 = T2 + 비중상한 0.20
## ★06-19 4접근과의 차이: 저쪽은 선택규칙이 전부 '합성 z-score 랭킹' 이었다. 여기선 합성 랭킹을 안 쓴다.
suppressPackageStartupMessages({library(data.table); library(arrow)})
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
suppressMessages({library(sandwich); library(lmtest)})
source("02_Infrastructure/config.R"); source("02_Infrastructure/factor_db/factor_db_connector.R")
IRf  <- function(x){ x <- x[is.finite(x)]; if (length(x) < 12) return(NA); mean(x)/sd(x)*sqrt(12) }
nwt  <- function(x){ x <- x[is.finite(x)]; if (length(x) < 12) return(NA)
                     m <- lm(x ~ 1); as.numeric(coeftest(m, vcov = NeweyWest(m, lag = 3, prewhite = FALSE))[1,3]) }
MDD  <- function(r){ n <- cumprod(1 + r); min(n / cummax(n) - 1) }
CAGR <- function(r) prod(1 + r)^(12/length(r)) - 1

FAC <- c(Value="V12_Composite_Value", Issuance="V21_Composite_Equity_Issuance", Size="S01_Size",
  Momentum="M09_Composite_Mom", ResidMom="M08_Residual_Mom", Reversal="M11_ST_Reversal",
  Quality="Q08_Composite_Quality", GPA="Q01_GPA", EarnStab="Q07_Earnings_Stability",
  Growth="GR07_Composite_Growth", Investment="IN06_Investment_to_Assets", LowVol="D03_RealVol",
  LowBeta="D02_Beta", TailRisk="R05_Tail_Risk", Liquidity="L45_Composite_Liquidity",
  Accrual="AC18_Accrual_Quality", Consensus="C19_Composite_Earnings", SUE="C01_SUE",
  Crowding="CR07_Momentum_Crowding", ForeignFlow="INV01_Foreign_NetBuy_20d", SmartMoney="INV10_Smart_Money_Flow")

R <- as.data.table(read_parquet("outputs/ramp/dfa_index_returns_broad_202608.parquet"))
R[, Date := as.Date(Date)]; setorder(R, Date); R <- R[is.finite(Market)]; R[, ym := format(Date, "%Y-%m")]
fac <- setdiff(names(R), c("Date","ym","as_of_date","source_version","Market"))
mon <- R[, c(lapply(.SD, function(x) prod(1+ifelse(is.finite(x),x,0))-1), .(medate = max(Date))),
         by = ym, .SDcols = c("Market", fac)]
setorder(mon, medate); mon <- mon[ym <= "2026-07"]; NM <- nrow(mon); NF <- length(fac)
S <- matrix(NA_real_, NM, NF)
for (fi in 1:NF) for (m in 12:NM)
  S[m, fi] <- prod(1 + mon[[fac[fi]]][(m-11):m]) / prod(1 + mon$Market[(m-11):m]) - 1

## 종목 월수익 (적용월 실현분) + 월말 유니버스
rd <- as.data.table(read_parquet(".cache/rawdata.parquet",
        col_select = c("Date","Ticker","Ret","Size","K200","KQ150")))
rd[, Date := as.Date(Date)]; rd <- rd[is.finite(Ret)]
rd[, inuniv := (!is.na(K200) & K200 == 1) | (!is.na(KQ150) & KQ150 == 1)]
rd <- rd[inuniv == TRUE]; rd[, ym := format(Date, "%Y-%m")]
MR <- rd[, .(mret = prod(1 + Ret) - 1), by = .(Ticker, ym)]           # 종목 월수익
UNI <- rd[, .SD[which.max(Date)], by = .(Ticker, ym), .SDcols = c("Size")]  # 월말 시총

cap_weights <- function(w, cap = 0.20, iters = 200){
  w <- w / sum(w)
  for (i in 1:iters) {
    over <- w > cap + 1e-12
    if (!any(over)) break
    ex <- sum(w[over] - cap); w[over] <- cap
    fr <- !over
    if (!any(fr) || sum(w[fr]) <= 0) break
    w[fr] <- w[fr] + ex * w[fr]/sum(w[fr])
  }
  w / sum(w)
}

rebal_m <- seq(13, NM, by = 3)
HOLD <- list()   # 각 리밸 시점의 팔별 (Ticker, w)
for (m in rebal_m) {
  d <- m - 1; if (d < 12) next
  s <- S[d, ]; pos <- which(is.finite(s) & s > 0); if (!length(pos)) next
  if (length(pos) > 5) pos <- pos[order(s[pos], decreasing = TRUE)][1:5]
  sd_ <- mon$medate[d]; ymd <- mon$ym[d]
  uni <- UNI[ym == ymd, .(Ticker, Size)]; if (nrow(uni) < 30) next
  f <- tryCatch(as.data.table(load_month_factors(sd_, factor_names = unname(FAC[fac[pos]]))),
                error = function(e) NULL)
  if (is.null(f) || nrow(f) == 0) next
  fm <- merge(f, uni, by = "Ticker")
  wf <- s[pos]/sum(s[pos])
  sets <- list(); t1 <- list()
  for (pi in seq_along(pos)) {
    nmf <- fac[pos[pi]]; sub <- fm[Factor_Name == FAC[nmf]]
    if (nrow(sub) < 15) next
    thr <- quantile(sub$Z_Score_Aligned, 0.6667, na.rm = TRUE)
    sel <- sub[Z_Score_Aligned >= thr]
    sel[, w_in := Size/sum(Size)]
    sets[[nmf]] <- data.table(Ticker = sel$Ticker, w = wf[pi] * sel$w_in)     # T0 목표 포트폴리오
    top5 <- sub[order(-Z_Score_Aligned)][1:min(5, .N)]                         # T1: 팩터 자기 상위 5종
    t1[[nmf]] <- data.table(Ticker = top5$Ticker, w = wf[pi] / nrow(top5))
  }
  if (!length(sets)) next
  A0 <- rbindlist(sets)[, .(w = sum(w)), by = Ticker]; A0[, w := w/sum(w)]
  A1 <- rbindlist(t1)[, .(w = sum(w)), by = Ticker];  A1[, w := w/sum(w)]
  A2 <- A0[order(-w)][1:min(25, .N)]; A2[, w := w/sum(w)]                      # T2: 비중 상위 25 재정규화
  A3 <- copy(A2); A3[, w := cap_weights(w, 0.20)]                              # T3: 상한 0.20
  HOLD[[as.character(m)]] <- list(m = m, T0 = A0, T1 = A1, T2 = A2, T3 = A3)
  if (length(HOLD) %% 10 == 0) cat("  holdings", length(HOLD), "/", length(rebal_m), "\n")
}
cat("리밸 구성 완료:", length(HOLD), "시점\n")

## 월별 수익 (분기 보유 · 월간 드리프트 없이 리밸 시점 비중 유지 — 단순 buy&hold within quarter)
arms <- c("T0","T1","T2","T3")
PR <- matrix(NA_real_, NM, length(arms)); colnames(PR) <- arms
TOv <- matrix(NA_real_, NM, length(arms)); colnames(TOv) <- arms
CMP <- list()
prevW <- setNames(vector("list", length(arms)), arms)
for (i in seq_along(HOLD)) {
  h <- HOLD[[i]]; m0 <- h$m
  mend <- if (i < length(HOLD)) HOLD[[i+1]]$m - 1 else NM
  for (a in arms) {
    W <- copy(h[[a]]); setnames(W, "w", "w0")
    cur <- W$w0; names(cur) <- W$Ticker
    pw <- prevW[[a]]
    tov <- if (is.null(pw)) 1 else {
      allt <- union(names(cur), names(pw))
      sum(abs(ifelse(is.na(cur[allt]), 0, cur[allt]) - ifelse(is.na(pw[allt]), 0, pw[allt])), na.rm = TRUE) }
    for (mm in m0:mend) {
      ymm <- mon$ym[mm]
      rr <- MR[ym == ymm][match(names(cur), Ticker), mret]
      rr[!is.finite(rr)] <- 0
      gross <- sum(cur * rr)
      cost <- if (mm == m0) (15/1e4) * tov else 0
      PR[mm, a] <- gross - cost; TOv[mm, a] <- if (mm == m0) tov else 0
      d <- cur * (1 + rr); cur <- d/sum(d)
    }
    prevW[[a]] <- cur
  }
  ci <- h$T2; ch <- h$T3
  CMP[[length(CMP)+1]] <- data.table(ym = mon$ym[m0],
    T0_n = nrow(h$T0), T0_maxw = max(h$T0$w),
    T1_n = nrow(h$T1), T1_maxw = max(h$T1$w),
    T2_n = nrow(ci),   T2_maxw = max(ci$w),
    T3_n = nrow(ch),   T3_maxw = max(ch$w))
}
CC <- rbindlist(CMP)
cat("\n=== [1] 게이트 0 제약 준수율 (리밸 시점", nrow(CC), "개) ===\n")
for (a in arms) {
  n <- CC[[paste0(a,"_n")]]; w <- CC[[paste0(a,"_maxw")]]
  cat(sprintf("  %s: 종목수 중앙 %5.0f (<=25 준수 %3.0f%%) | 단일비중 최대 %.3f (<=0.20 준수 %3.0f%%) | 완전준수 %3.0f%%\n",
    a, median(n), 100*mean(n <= 25), max(w), 100*mean(w <= 0.20 + 1e-9),
    100*mean(n <= 25 & w <= 0.20 + 1e-9)))
}
cat("\n=== [2] 성과 (parent 기준, 15bps) ===\n")
k <- which(apply(PR, 1, function(v) all(is.finite(v))))
mk <- mon$Market[k]
for (a in arms) {
  x <- PR[k, a]; act <- x - mk
  cat(sprintf("  %s: n=%3d | CAGR %+.4f MDD %.4f calmar %.4f | PORT_t %+.3f IR %+.3f | TO %.2f\n",
    a, length(x), CAGR(x), MDD(x), CAGR(x)/abs(MDD(x)), nwt(act), IRf(act), mean(TOv[k,a])*4))
}
cat("\n=== [3] 변환 손실 (T0 대비) — 06-19 4접근은 -0.64 ~ -3.13 전부 음수였다 ===\n")
base_t <- nwt(PR[k,"T0"] - mk)
for (a in c("T1","T2","T3")) {
  t_a <- nwt(PR[k,a] - mk)
  cat(sprintf("  %s: PORT_t %+.3f (T0 %+.3f 대비 %+.3f) | 양수 여부 %s\n",
              a, t_a, base_t, t_a - base_t, ifelse(t_a > 0, "양수 ★", "음수")))
}
saveRDS(list(PR = PR, TOv = TOv, mon = mon, CC = CC, k = k), ".cache/_dfa_r29.rds")
fwrite(CC, "outputs/ramp/dfa_gate0_compliance_r29_20260822.csv")
cat("\nR29_DONE\n")
