## run_dfa_oracle_verify_r27.R — R27: 워크플로 진단의 하중 큰 주장 2건을 Q-Lead 가 독립 재현
##  주장① 동일 기계(분기·3코호트·k=5·s비례·15bps·dec_lag=1)에 완전예지 신호를 넣어도 MDD 는 0.2603 까지만 내려간다
##          ⇒ CAGR 고정 + MDD 만 줄여 calmar 0.64 에 도달하는 경로는 IC=1 에서도 닫혀 있다(필요 MDD 0.2192)
##  주장② 채택팔 신호의 pooled rank-IC = 0.0997
## ★기계는 run_dfa_topk_r20.R 의 run_ens 를 정본 파라미터 그대로 복제하고 **신호행렬만** 교체한다.
suppressPackageStartupMessages({library(data.table); library(arrow)})
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
MDD  <- function(r){ n <- cumprod(1 + r); min(n / cummax(n) - 1) }
CAGR <- function(r) prod(1 + r)^(12 / length(r)) - 1

R <- as.data.table(read_parquet("outputs/ramp/dfa_index_returns_broad_202608.parquet"))
R[, Date := as.Date(Date)]; setorder(R, Date); R <- R[is.finite(Market)]
R[, ym := format(Date, "%Y-%m")]
fac <- setdiff(names(R), c("Date","ym","as_of_date","source_version","Market"))
mon <- R[, c(lapply(.SD, function(x) prod(1 + ifelse(is.finite(x), x, 0)) - 1)),
         by = ym, .SDcols = c("Market", fac)]
mon <- mon[ym <= "2026-07"]
NM <- nrow(mon); NF <- length(fac); NAx <- 1 + NF
ACT <- sapply(fac, function(k) mon[[k]] - mon$Market)      # NM x NF 팩터 active
RET <- as.matrix(mon[, c("Market", fac), with = FALSE]); RET[!is.finite(RET)] <- 0

## 신호행렬 2종 — 동일 shape (NM x NF)
S_trail <- matrix(NA_real_, NM, NF)                        # 정본: trailing 12M active
for (fi in 1:NF) for (m in 12:NM)
  S_trail[m, fi] <- prod(1 + mon[[fac[fi]]][(m-11):m]) / prod(1 + mon$Market[(m-11):m]) - 1
S_oracle <- matrix(NA_real_, NM, NF)                       # 완전예지: forward 3M active (실현 불가·상한 전용)
for (fi in 1:NF) for (m in 1:(NM-3)) S_oracle[m, fi] <- sum(ACT[(m+1):(m+3), fi])

## 정본 기계 (run_dfa_topk_r20.R run_ens 복제 — 파라미터 불변)
run_ens <- function(Suse, K = 5, bps = 15, dec_lag = 1, freq = 3, ncoh = 3, start0 = 13){
  pr_c <- matrix(NA_real_, ncoh, NM)
  for (cc in 0:(ncoh - 1)) {
    st <- start0 + cc; wprev <- rep(1/NAx, NAx); wcur <- NULL
    for (m in st:NM) {
      d <- m - dec_lag; if (d < 1) next
      if (is.null(wcur) || ((m - st) %% freq == 0)) {
        s <- Suse[d, ]; pos <- which(is.finite(s) & s > 0)
        if (!is.na(K) && length(pos) > K) pos <- pos[order(s[pos], decreasing = TRUE)][1:K]
        w <- rep(0, NAx); if (length(pos) == 0) w[1] <- 1 else w[1 + pos] <- s[pos]/sum(s[pos])
        wcur <- w
      }
      ri <- RET[m, ]; dlt <- sum(abs(wcur - wprev))
      pr_c[cc + 1, m] <- sum(wcur * ri) - (bps/1e4) * dlt
      wd <- wcur * (1 + ri); wprev <- wd / sum(wd); wcur <- wprev
    }
  }
  pr <- rep(NA_real_, NM)
  for (m in (start0 + ncoh - 1):NM) if (all(is.finite(pr_c[, m]))) pr[m] <- mean(pr_c[, m])
  pr
}

score <- function(pr, lab){
  k <- which(is.finite(pr)); x <- pr[k]
  cat(sprintf("  %-34s n=%3d | CAGR %+.4f  MDD %.4f  calmar %.4f\n",
              lab, length(x), CAGR(x), MDD(x), CAGR(x)/abs(MDD(x))))
  invisible(c(cagr = CAGR(x), mdd = abs(MDD(x)), calmar = CAGR(x)/abs(MDD(x)), n = length(x)))
}

cat("=== R27 [양성 대조] 회귀 확인 — 정본 신호로 채택팔이 재현되는가 ===\n")
b <- score(run_ens(S_trail), "정본 trailing (재현 대조)")
cat(sprintf("  ★R20 기록 calmar 0.298~0.300 · MDD 0.468 대비 → %s\n\n",
            ifelse(abs(b["calmar"] - 0.2996) < 0.01 && abs(b["mdd"] - 0.4682) < 0.01,
                   "재현 PASS", "재현 FAIL(측정 무효)")))

cat("=== 주장① 동일 기계 + 완전예지 신호 (실현 불가 · 상한 측정 전용) ===\n")
o <- score(run_ens(S_oracle), "완전예지 forward-3M (PC1)")
need_mdd <- b["cagr"] / 0.64
cat(sprintf("\n  필요 MDD (현 CAGR %.4f 고정 시) = %.4f\n", b["cagr"], need_mdd))
cat(sprintf("  완전예지 MDD 하한             = %.4f\n", o["mdd"]))
cat(sprintf("  ⇒ %s\n", ifelse(o["mdd"] > need_mdd,
  sprintf("완전예지조차 필요치보다 %.1f%% 큰 MDD — 'CAGR 고정 + MDD 만 축소' 경로는 이 기계 안에서 IC=1 에서도 닫힘",
          100*(o["mdd"]/need_mdd - 1)),
  "완전예지로는 필요치 달성 — 경로가 열려 있음")))

cat("\n=== 주장② 채택팔 신호의 pooled rank-IC (신호 vs forward 3M active) ===\n")
ics <- c()
for (m in 12:(NM - 3)) {
  x <- S_trail[m, ]; y <- S_oracle[m, ]
  k <- is.finite(x) & is.finite(y)
  if (sum(k) >= 5) ics <- c(ics, cor(x[k], y[k], method = "spearman"))
}
cat(sprintf("  결정시점 %d개 · 평균 rank-IC = %.4f · sd %.4f · IC-t %.3f · 양수비율 %.1f%%\n",
            length(ics), mean(ics), sd(ics), mean(ics)/sd(ics)*sqrt(length(ics)), 100*mean(ics > 0)))

cat("\n=== 참고: 다른 기계(월별 argmax 22자산) 상한 — 내가 앞서 인용한 값의 출처 ===\n")
mk <- apply(RET, 1, max)
kk <- 13:NM
cat(sprintf("  월별 사후최고 자산 보유 (무비용): CAGR %+.4f  MDD %.4f  calmar %.4f\n",
            CAGR(mk[kk]), MDD(mk[kk]), CAGR(mk[kk])/abs(MDD(mk[kk]))))
cat("  ⇒ 이 값은 **다른 기계**(월별·단일자산·무비용)의 상한이므로 DFA 기계의 도달가능성 근거로 쓸 수 없다.\n")
cat("\nR27_DONE\n")
