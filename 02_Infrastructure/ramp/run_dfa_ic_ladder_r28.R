## run_dfa_ic_ladder_r28.R — R28: CAGR 채널의 신호품질 → calmar 사다리 (Q-Lead 직접 재현)
## 목적: R27 이 'MDD 채널은 완전예지에서도 닫힘 / CAGR 채널만 열림' 을 확정했으므로,
##       그 통로에서 calmar 0.64 에 필요한 신호품질(rank-IC)이 얼마인지를 실측한다.
## 방법: 분포보존 rank 열화 — 각 결정시점에서 완전예지 벡터의 **횡단면 분포는 그대로 두고 순위만** rho 로 흐린다.
##       (분포를 바꾸면 신호 품질이 아니라 스케일이 바뀌어 사다리가 오염된다.)
## 기계는 run_dfa_topk_r20.R 의 run_ens 정본 파라미터 복제, 신호행렬만 교체.
suppressPackageStartupMessages({library(data.table); library(arrow)})
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
MDD  <- function(r){ n <- cumprod(1 + r); min(n / cummax(n) - 1) }
CAGR <- function(r) prod(1 + r)^(12 / length(r)) - 1

R <- as.data.table(read_parquet("outputs/ramp/dfa_index_returns_broad_202608.parquet"))
R[, Date := as.Date(Date)]; setorder(R, Date); R <- R[is.finite(Market)]; R[, ym := format(Date, "%Y-%m")]
fac <- setdiff(names(R), c("Date","ym","as_of_date","source_version","Market"))
mon <- R[, c(lapply(.SD, function(x) prod(1 + ifelse(is.finite(x), x, 0)) - 1)),
         by = ym, .SDcols = c("Market", fac)][ym <= "2026-07"]
NM <- nrow(mon); NF <- length(fac); NAx <- 1 + NF
ACT <- sapply(fac, function(k) mon[[k]] - mon$Market)
RET <- as.matrix(mon[, c("Market", fac), with = FALSE]); RET[!is.finite(RET)] <- 0

S_trail <- matrix(NA_real_, NM, NF)
for (fi in 1:NF) for (m in 12:NM)
  S_trail[m, fi] <- prod(1 + mon[[fac[fi]]][(m-11):m]) / prod(1 + mon$Market[(m-11):m]) - 1
S_or <- matrix(NA_real_, NM, NF)
for (fi in 1:NF) for (m in 1:(NM-3)) S_or[m, fi] <- sum(ACT[(m+1):(m+3), fi])

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
## 분포보존 rank 열화: 순위만 rho 로 흐리고 값 집합은 원본 그대로 재배치
degrade <- function(Sm, rho){
  out <- matrix(NA_real_, nrow(Sm), ncol(Sm))
  for (m in 1:nrow(Sm)) {
    y <- Sm[m, ]; k <- which(is.finite(y)); if (length(k) < 3) next
    v <- y[k]; n <- length(v)
    zy <- qnorm((rank(v) - 0.5) / n)                  # 원 순위의 정규 스코어
    ze <- rnorm(n)
    mix <- rho * zy + sqrt(max(0, 1 - rho^2)) * ze     # 순위 신호를 rho 로 희석
    out[m, k] <- sort(v)[rank(mix, ties.method = "first")]   # ★값 집합 보존, 순서만 교체
  }
  out
}
pooled_ic <- function(Sm){
  ic <- c()
  for (m in 12:(NM - 3)) {
    x <- Sm[m, ]; y <- S_or[m, ]; k <- is.finite(x) & is.finite(y)
    if (sum(k) >= 5) ic <- c(ic, cor(x[k], y[k], method = "spearman"))
  }
  mean(ic)
}
sc <- function(pr){ k <- which(is.finite(pr)); x <- pr[k]
  c(cagr = CAGR(x), mdd = abs(MDD(x)), calmar = CAGR(x)/abs(MDD(x))) }

cat("=== R28 신호품질 → calmar 사다리 (분포보존 rank 열화) ===\n")
b <- sc(run_ens(S_trail)); ic_b <- pooled_ic(S_trail)
cat(sprintf("[대조] 정본 trailing: rank-IC %.4f | CAGR %.4f MDD %.4f calmar %.4f  (R20 재현 %s)\n\n",
            ic_b, b["cagr"], b["mdd"], b["calmar"],
            ifelse(abs(b["calmar"] - 0.2996) < 0.01, "PASS", "FAIL")))
RHO <- c(0, 0.10, 0.20, 0.30, 0.40, 0.50, 0.65, 0.80, 1.00)
NDRAW <- as.integer(Sys.getenv("R28_NDRAW", "20"))
set.seed(20260822)
res <- list()
for (rho in RHO) {
  ics <- numeric(0); cals <- numeric(0); cags <- numeric(0); mdds <- numeric(0)
  nd <- if (rho == 1.0) 1L else NDRAW               # rho=1 은 결정적
  for (i in seq_len(nd)) {
    Sd <- if (rho == 1.0) S_or else degrade(S_or, rho)
    ics <- c(ics, pooled_ic(Sd)); s <- sc(run_ens(Sd))
    cals <- c(cals, s["calmar"]); cags <- c(cags, s["cagr"]); mdds <- c(mdds, s["mdd"])
  }
  res[[length(res)+1]] <- data.table(rho = rho, n = nd,
    ic_med = median(ics), calmar_med = median(cals),
    calmar_p95 = as.numeric(quantile(cals, 0.95)), calmar_max = max(cals),
    cagr_med = median(cags), mdd_med = median(mdds),
    p_reach = mean(cals >= 0.64))
  cat(sprintf("  rho=%.2f (n=%2d): IC %.4f | calmar med %.4f p95 %.4f max %.4f | CAGR %.4f MDD %.4f | P(>=0.64)=%.3f\n",
    rho, nd, median(ics), median(cals), as.numeric(quantile(cals,0.95)), max(cals),
    median(cags), median(mdds), mean(cals >= 0.64)))
}
T <- rbindlist(res)
fwrite(T, "outputs/ramp/dfa_ic_calmar_ladder_r28_20260822.csv")

cat("\n[교차 IC — calmar 0.64 를 median 으로 넘기는 신호품질]\n")
lo <- T[calmar_med < 0.64][.N]; hi <- T[calmar_med >= 0.64][1]
if (nrow(lo) && nrow(hi) && is.finite(hi$ic_med)) {
  w <- (0.64 - lo$calmar_med) / (hi$calmar_med - lo$calmar_med)
  ic_x <- lo$ic_med + w * (hi$ic_med - lo$ic_med)
  cat(sprintf("  교차 IC = %.4f | 현 신호 IC = %.4f | **필요 배수 = %.2f배**\n", ic_x, ic_b, ic_x/ic_b))
} else cat("  격자 안에서 median 교차점 미발생 — 격자 확장 필요\n")
cat(sprintf("\n[현 신호의 사다리상 위치] IC %.4f 등급 대비 실측 calmar %.4f\n", ic_b, b["calmar"]))
near <- T[which.min(abs(ic_med - ic_b))]
cat(sprintf("  같은 IC 등급(rho=%.2f, IC %.4f)의 calmar med %.4f / p95 %.4f / max %.4f\n",
            near$rho, near$ic_med, near$calmar_med, near$calmar_p95, near$calmar_max))
cat(sprintf("  ⇒ 같은 신호를 다르게 써서 남은 여지 ≈ %+.4f calmar (문턱까지 갭 %.4f 의 %.1f%%)\n",
            near$calmar_max - b["calmar"], 0.64 - b["calmar"],
            100*(near$calmar_max - b["calmar"])/(0.64 - b["calmar"])))
cat("\nR28_DONE\n")
