## run_dfa_costaware_r34.R — R34: 비용-인지 팩터 선택 (prereg dfa_v21_20260822)
## base = R33 비용 수리판. 단일 자유도 = 선택 신호에 **예상 미래 비용** 항 추가.
##   s_fwd(f) = trailing12M_net_active(f) - 12 * trailing12M_mean_turnover(f) * 15bps
suppressPackageStartupMessages({library(data.table); library(arrow)})
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
suppressMessages({library(sandwich); library(lmtest)})
IRf  <- function(x){ x <- x[is.finite(x)]; if (length(x) < 12) return(NA); mean(x)/sd(x)*sqrt(12) }
nwt  <- function(x){ x <- x[is.finite(x)]; if (length(x) < 12) return(NA)
                     m <- lm(x ~ 1); as.numeric(coeftest(m, vcov=NeweyWest(m, lag=3, prewhite=FALSE))[1,3]) }
MDD  <- function(r){ n <- cumprod(1+r); min(n/cummax(n)-1) }
CAGR <- function(r) prod(1+r)^(12/length(r))-1
BPS <- 15

Z <- readRDS(".cache/_dfa_r33.rds"); monC <- Z$monC        # 비용 차감 월 지수수익
fac <- setdiff(names(monC), c("ym","medate","Market")); NM <- nrow(monC); NF <- length(fac); NAx <- 1+NF
TV <- fread("outputs/ramp/dfa_index_turnover_r31_20260822.csv", encoding="UTF-8")
TW <- dcast(TV, ym ~ factor, value.var = "turnover")
TM <- matrix(NA_real_, NM, NF, dimnames = list(NULL, fac))
for (f in fac) { i <- match(monC$ym, TW$ym); TM[, f] <- if (f %in% names(TW)) TW[[f]][i] else NA_real_ }

## 신호 2종
S_net <- matrix(NA_real_, NM, NF)                        # G0: trailing 12M net active
for (fi in 1:NF) for (m in 12:NM)
  S_net[m, fi] <- prod(1 + monC[[fac[fi]]][(m-11):m]) / prod(1 + monC$Market[(m-11):m]) - 1
S_fwd <- S_net                                            # G1: - 예상 연간 비용
for (fi in 1:NF) for (m in 12:NM) {
  tv <- TM[(m-11):m, fi]; tv <- tv[is.finite(tv)]
  if (length(tv) >= 6) S_fwd[m, fi] <- S_net[m, fi] - 12 * mean(tv) * BPS/1e4
}
RET <- as.matrix(monC[, c("Market", fac), with = FALSE]); RET[!is.finite(RET)] <- 0

run_ens <- function(Suse, keep = NULL, K = 5, freq = 3, ncoh = 3, bps = BPS, dec_lag = 1, start0 = 13){
  ok <- if (is.null(keep)) seq_len(NF) else which(fac %in% keep)
  pr_c <- matrix(NA_real_, ncoh, NM)
  for (cc in 0:(ncoh-1)) {
    st <- start0+cc; wprev <- rep(1/NAx, NAx); wcur <- NULL
    for (m in st:NM) {
      d <- m-dec_lag; if (d < 1) next
      if (is.null(wcur) || ((m-st) %% freq == 0)) {
        s <- Suse[d, ]; s[setdiff(seq_len(NF), ok)] <- NA_real_
        pos <- which(is.finite(s) & s > 0)
        if (!is.na(K) && length(pos) > K) pos <- pos[order(s[pos], decreasing=TRUE)][1:K]
        w <- rep(0, NAx); if (length(pos) == 0) w[1] <- 1 else w[1+pos] <- s[pos]/sum(s[pos])
        wcur <- w }
      ri <- RET[m, ]; dlt <- sum(abs(wcur-wprev))
      pr_c[cc+1, m] <- sum(wcur*ri) - (bps/1e4)*dlt
      wd <- wcur*(1+ri); wprev <- wd/sum(wd); wcur <- wprev } }
  pr <- rep(NA_real_, NM)
  for (m in (start0+ncoh-1):NM) if (all(is.finite(pr_c[,m]))) pr[m] <- mean(pr_c[,m])
  pr }

E <- list(full = rep(TRUE, NM), clean = monC$ym >= "2015-07")
rep1 <- function(pr, lab){
  for (w in c("full","clean")) {
    k <- which(is.finite(pr) & E[[w]]); x <- pr[k]; a <- x - monC$Market[k]
    cat(sprintf("  %-26s [%-5s] n=%3d | CAGR %+.4f MDD %.4f calmar %.4f | PORT_t %+.3f IR %+.3f\n",
      lab, w, length(x), CAGR(x), MDD(x), CAGR(x)/abs(MDD(x)), nwt(a), IRf(a))) } }

cat("=== R34 비용-인지 팩터 선택 (prereg dfa_v21, base = R33 수리판) ===\n")
cat("[헤드라인 사전지정: G1, 15bps, dec_lag=1]\n")
HI <- c("Reversal","SmartMoney","ForeignFlow")
A <- list(G0 = run_ens(S_net), G1 = run_ens(S_fwd), G2 = run_ens(S_net, keep = setdiff(fac, HI)))
rep1(A$G0, "G0_control(net)"); rep1(A$G1, "G1_costaware ★헤드라인")
cat("\n[진단 전용 — 헤드라인 승격 금지 (사후 관측)]\n"); rep1(A$G2, "G2_diag_exclude_top3")

cat("\n[대응표본]\n")
for (p in list(c("G1","G0"), c("G2","G0"))) for (w in c("full","clean")) {
  k <- which(is.finite(A[[p[1]]]) & is.finite(A[[p[2]]]) & E[[w]]); dd <- (A[[p[1]]]-A[[p[2]]])[k]
  cat(sprintf("  %s - %s [%-5s] n=%3d mean %+.4f%%/월 NW-t %+.3f\n", p[1], p[2], w, length(k), 100*mean(dd), nwt(dd))) }

cat("\n[선택 팩터 분포 — 비용-인지가 실제로 선택을 바꾸는가]\n")
cnt <- function(Suse){
  tab <- setNames(rep(0L, NF), fac)
  for (m in seq(13, NM, by = 3)) { d <- m-1; if (d < 12) next
    s <- Suse[d, ]; pos <- which(is.finite(s) & s > 0)
    if (length(pos) > 5) pos <- pos[order(s[pos], decreasing=TRUE)][1:5]
    tab[fac[pos]] <- tab[fac[pos]] + 1L }
  tab }
c0 <- cnt(S_net); c1 <- cnt(S_fwd)
D <- data.table(factor = fac, G0_선택수 = as.integer(c0), G1_선택수 = as.integer(c1),
                차이 = as.integer(c1 - c0),
                월회전 = round(sapply(fac, function(f) mean(TM[, f], na.rm = TRUE)), 3))
print(D[order(-abs(차이))][1:8])
cat(sprintf("  선택 조합 불일치 분기 = %d / %d\n", sum(c0 != c1) > 0, length(seq(13, NM, by = 3))))

cat("\n[전 셀 전수 — full 창 IR]\n")
cat(sprintf("  %-6s %-6s %s\n", "arm", "cost", "lag0     lag1     lag2     lag3"))
for (nm in c("G0","G1","G2")) for (bp in c(5,15,25)) {
  Su <- if (nm == "G1") S_fwd else S_net; kp <- if (nm == "G2") setdiff(fac, HI) else NULL
  v <- sapply(0:3, function(dl){ pr <- run_ens(Su, keep = kp, bps = bp, dec_lag = dl)
    k <- which(is.finite(pr)); IRf(pr[k] - monC$Market[k]) })
  cat(sprintf("  %-6s %-6s %s\n", nm, paste0(bp,"bps"), paste(sprintf("%+8.3f", v), collapse=" "))) }
saveRDS(list(A=A, monC=monC, D=D), ".cache/_dfa_r34.rds")
cat("\nR34_DONE\n")
