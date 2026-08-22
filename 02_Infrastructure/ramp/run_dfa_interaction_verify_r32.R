## run_dfa_interaction_verify_r32.R — R32: 검증 워크플로가 보고한 '구성축 x 노출축 상호작용' 독립 재현
## 주장: freq=1 · K=1 + PIT-청정 무파라미터 현금규칙(직전 3M 시장 누적수익<0 -> 전액 현금)
##       = full calmar 0.6375 (PORT_t 2.707, MDD 0.2884) / clean calmar 0.6169
## 그리고 그 팔이 extra-lag +1M 에서 0.6375 -> 0.3290 으로 붕괴한다는 취약성 주장도 함께 재현한다.
suppressPackageStartupMessages({library(data.table); library(arrow)})
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
suppressMessages({library(sandwich); library(lmtest)})
IRf  <- function(x){ x <- x[is.finite(x)]; if (length(x) < 12) return(NA); mean(x)/sd(x)*sqrt(12) }
nwt  <- function(x){ x <- x[is.finite(x)]; if (length(x) < 12) return(NA)
                     m <- lm(x ~ 1); as.numeric(coeftest(m, vcov = NeweyWest(m, lag = 3, prewhite = FALSE))[1,3]) }
MDD  <- function(r){ n <- cumprod(1 + r); min(n / cummax(n) - 1) }
CAGR <- function(r) prod(1 + r)^(12/length(r)) - 1

R <- as.data.table(read_parquet("outputs/ramp/dfa_index_returns_broad_202608.parquet"))
R[, Date := as.Date(Date)]; setorder(R, Date); R <- R[is.finite(Market)]; R[, ym := format(Date, "%Y-%m")]
fac <- setdiff(names(R), c("Date","ym","as_of_date","source_version","Market"))
mon <- R[, c(lapply(.SD, function(x) prod(1+ifelse(is.finite(x),x,0))-1)), by = ym,
         .SDcols = c("Market", fac)][ym <= "2026-07"]
NM <- nrow(mon); NF <- length(fac); NAx <- 1 + NF
S <- matrix(NA_real_, NM, NF)
for (fi in 1:NF) for (m in 12:NM)
  S[m, fi] <- prod(1 + mon[[fac[fi]]][(m-11):m]) / prod(1 + mon$Market[(m-11):m]) - 1
RET <- as.matrix(mon[, c("Market", fac), with = FALSE]); RET[!is.finite(RET)] <- 0
MKT <- mon$Market

## PIT-청정 현금 규칙: 적용월 m 의 노출은 결정시점 d=m-1 까지의 **직전 3개월 시장 누적수익** 부호로 결정
##  cash_lag=0 -> 창 = (d-2):d  (d 는 m-1 이므로 적용월 이전 정보만 사용)
##  cash_lag=L -> 창을 L 개월 더 과거로 밀어 적시성 의존을 시험
expo_vec <- function(cash_lag = 0L){
  e <- rep(1, NM)
  for (m in 1:NM) {
    d <- m - 1 - cash_lag
    if (d - 2 < 1) next
    cum3 <- prod(1 + MKT[(d-2):d]) - 1
    e[m] <- if (is.finite(cum3) && cum3 < 0) 0 else 1
  }
  e
}
run_arm <- function(K = 5, freq = 3, ncoh = 3, bps = 15, dec_lag = 1,
                    use_cash = FALSE, cash_lag = 0L, start0 = 13){
  e <- if (use_cash) expo_vec(cash_lag) else rep(1, NM)
  pr_c <- matrix(NA_real_, ncoh, NM)
  for (cc in 0:(ncoh - 1)) {
    st <- start0 + cc; wprev <- rep(1/NAx, NAx); wcur <- NULL; eprev <- 1
    for (m in st:NM) {
      d <- m - dec_lag; if (d < 1) next
      if (is.null(wcur) || ((m - st) %% freq == 0)) {
        s <- S[d, ]; pos <- which(is.finite(s) & s > 0)
        if (!is.na(K) && length(pos) > K) pos <- pos[order(s[pos], decreasing = TRUE)][1:K]
        w <- rep(0, NAx); if (length(pos) == 0) w[1] <- 1 else w[1 + pos] <- s[pos]/sum(s[pos])
        wcur <- w
      }
      ri <- RET[m, ]
      dlt <- sum(abs(wcur - wprev)) * eprev + abs(e[m] - eprev)   # 배분 회전 + 노출 변경 둘 다 과금
      gross <- e[m] * sum(wcur * ri)                              # 현금 rf = 0%
      pr_c[cc + 1, m] <- gross - (bps/1e4) * dlt
      wd <- wcur * (1 + ri); wprev <- wd/sum(wd); wcur <- wprev; eprev <- e[m]
    }
  }
  pr <- rep(NA_real_, NM)
  for (m in (start0 + ncoh - 1):NM) if (all(is.finite(pr_c[, m]))) pr[m] <- mean(pr_c[, m])
  list(pr = pr, e = e)
}
rep_arm <- function(o, lab){
  for (win in c("full","clean")) {
    k <- which(is.finite(o$pr)); if (win == "clean") k <- k[mon$ym[k] >= "2015-07"]
    x <- o$pr[k]; a <- x - MKT[k]
    cat(sprintf("  %-34s [%-5s] n=%3d | CAGR %+.4f MDD %.4f **calmar %.4f** | PORT_t %+.3f IR %+.3f | 평균노출 %.3f\n",
      lab, win, length(x), CAGR(x), MDD(x), CAGR(x)/abs(MDD(x)), nwt(a), IRf(a), mean(o$e[k])))
  }
}
cat("=== R32 [양성 대조] 정본 재현 ===\n")
rep_arm(run_arm(K = 5, freq = 3), "정본 freq=3 K=5 (무오버레이)")
cat("  ★R20 기록 full calmar 0.2996 · PORT_t 2.882 대비 재현 확인\n")

cat("\n=== [주변부 A] 구성축 단독 ===\n")
rep_arm(run_arm(K = 1, freq = 1), "freq=1 K=1 (무오버레이)")

cat("\n=== [주변부 B] 노출축 단독 (정본 구성 위) ===\n")
rep_arm(run_arm(K = 5, freq = 3, use_cash = TRUE), "freq=3 K=5 + 3M현금규칙")

cat("\n=== [상호작용] 워크플로 주장 팔 ===\n")
rep_arm(run_arm(K = 1, freq = 1, use_cash = TRUE), "freq=1 K=1 + 3M현금규칙 ★주장")
cat("  ★주장: full calmar 0.6375 (PORT_t 2.707, MDD 0.2884) / clean 0.6169\n")

cat("\n=== [취약성] extra-lag 스트레스 — 주장 팔의 적시성 의존 ===\n")
for (L in 0:3) {
  o <- run_arm(K = 1, freq = 1, use_cash = TRUE, cash_lag = L)
  k <- which(is.finite(o$pr)); x <- o$pr[k]
  cat(sprintf("  cash_lag=+%dM: full calmar %.4f | MDD %.4f | PORT_t %+.3f | 평균노출 %.3f\n",
              L, CAGR(x)/abs(MDD(x)), MDD(x), nwt(x - MKT[k]), mean(o$e[k])))
}
cat("  ★주장: +1M 에서 0.6375 -> 0.3290 붕괴 (무오버레이 0.4608 보다도 낮음)\n")

cat("\n=== [평균노출 매칭 상수-e 대조] 타이밍인가 단순 축소인가 ===\n")
o <- run_arm(K = 1, freq = 1, use_cash = TRUE); ke <- which(is.finite(o$pr)); em <- mean(o$e[ke])
base <- run_arm(K = 1, freq = 1)
kb <- which(is.finite(base$pr)); xb <- base$pr[kb] * em          # 상수 노출 em (현금 rf=0)
cat(sprintf("  상수노출 e=%.3f: full calmar %.4f | MDD %.4f | PORT_t %+.3f\n",
            em, CAGR(xb)/abs(MDD(xb)), MDD(xb), nwt(xb - MKT[kb])))
cat("  ⇒ 타이밍 규칙이 같은 평균노출의 상수 축소를 유의하게 넘어야 '타이밍' 이라 부를 수 있다.\n")
cat("\nR32_DONE\n")
