## run_dfa_ex2026_restate_r45.R — R45: clean 창 수치의 2026 제외 판본 병기 (소급 재산출)
## R43/R44 가 2026 을 유효 데이터이나 극단 이상치(일별 vol 0.658 = 역사 중앙 3.93배)로 확정했다.
## 그 7개월(clean 표본의 5.3%)이 판정을 떠받치므로 제외 판본을 병기한다.
suppressPackageStartupMessages({library(data.table)})
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
suppressMessages({library(sandwich); library(lmtest)})
source("02_Infrastructure/contracts/no_signal_control.R")
IRf  <- function(x){ x<-x[is.finite(x)]; mean(x)/sd(x)*sqrt(12) }
nwt1 <- function(x){ x<-x[is.finite(x)]; m<-lm(x~1); as.numeric(coeftest(m,vcov=NeweyWest(m,lag=3,prewhite=FALSE))[1,3]) }
MDD  <- function(r){ n<-cumprod(1+r); min(n/cummax(n)-1) }
CAGR <- function(r) prod(1+r)^(12/length(r))-1
ab   <- function(x,b){ f<-lm(x~b); ct<-coeftest(f,vcov=NeweyWest(f,lag=3,prewhite=FALSE))
                       c(alpha=12*ct[1,1], beta=ct[2,1], t_alpha=ct[1,3]) }

Z29 <- readRDS(".cache/_dfa_r29.rds"); Z39 <- readRDS(".cache/_dfa_r39.rds")
Z33 <- readRDS(".cache/_dfa_r33.rds"); Z41 <- readRDS(".cache/_dfa_r41.rds")
mon <- Z29$mon; ym <- mon$ym
k <- intersect(intersect(Z29$k, Z39$k), Z41$kk); ymk <- ym[k]
ARM <- list(`index(비용수리)` = Z33$armC, T0 = Z29$PR[,"T0"], T1 = Z29$PR[,"T1"],
            M2 = Z39$PR[,"M2"], T3 = Z29$PR[,"T3"], `BIG25(무신호)` = Z41$BIG)

cat("=== clean 창 (2015-07~) 2026 포함 vs 제외 — 전 팔 ===\n")
cat(sprintf("  %-16s %-8s %4s %8s %8s %8s %9s %9s %8s\n",
    "팔","판본","n","CAGR","MDD","calmar","PORT_t","alpha","t(alpha)"))
RES <- list()
for (a in names(ARM)) {
  for (v in c("포함","제외")) {
    kk <- k[ymk >= "2015-07" & (v == "포함" | ymk < "2026-01")]
    x <- ARM[[a]][kk]; b <- mon$Market[kk]
    ok <- is.finite(x) & is.finite(b); x <- x[ok]; b <- b[ok]
    if (length(x) < 24) next
    z <- ab(x, b)
    cat(sprintf("  %-16s %-8s %4d %+8.4f %8.4f %8.4f %+9.3f %+9.4f %+8.3f\n",
        a, v, length(x), CAGR(x), MDD(x), CAGR(x)/abs(MDD(x)), nwt1(x-b), z["alpha"], z["t_alpha"]))
    RES[[paste(a,v)]] <- c(n=length(x), calmar=CAGR(x)/abs(MDD(x)), port_t=nwt1(x-b), z)
  }
  cat("\n")
}
cat("=== ★핵심 판정 — 2026 제외 시 알파 부재가 더 확실해지는가 ===\n")
for (a in c("index(비용수리)","T0","T3","BIG25(무신호)")) {
  i <- RES[[paste(a,"포함")]]; e <- RES[[paste(a,"제외")]]
  if (is.null(i)||is.null(e)) next
  cat(sprintf("  %-16s t(alpha) %+.3f -> %+.3f | PORT_t %+.3f -> %+.3f | calmar %.3f -> %.3f\n",
      a, i["t_alpha"], e["t_alpha"], i["port_t"], e["port_t"], i["calmar"], e["calmar"]))
}
cat("\n=== 무신호 대조 게이트 — 두 판본 ===\n")
ctl <- Z41$BIG
for (v in c("포함","제외")) {
  kk <- k[ymk >= "2015-07" & (v == "포함" | ymk < "2026-01")]
  g <- no_signal_gate(Z29$PR[kk,"T3"], ctl[kk], mon$Market[kk])
  cat(sprintf("  [%s] n=%d | T3-무신호 %+.4f/yr NW-t %+.3f | verdict %s\n",
      v, g$n, g$diff_ann, g$diff_nw_t, g$verdict))
}
cat("\n=== 유의 팔 census (|t(alpha)| >= 1.96) ===\n")
for (v in c("포함","제외")) {
  sig <- names(which(sapply(names(ARM), function(a){
    r <- RES[[paste(a,v)]]; !is.null(r) && abs(r["t_alpha"]) >= 1.96 })))
  cat(sprintf("  %s: %s\n", v, if (length(sig)) paste(sig, collapse=", ") else "**0건**"))
}
cat("\nR45_DONE\n")
