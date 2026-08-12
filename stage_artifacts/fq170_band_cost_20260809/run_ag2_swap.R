## AG2 — 스왑 소비: 북의 D03-상단 노출을 **D03 D3~D4 로 교체**
## 사전등록(측정 전 고정, 이 주석이 정본):
##  이 아크의 두 발견 합류 — 필터(D03 {9,10} 제외, T1 gap +2.537 t 2.586) + 밴드(D3~D4 가 좋음, AD1).
##  기존 fD 는 결원을 **M26 다음 순위**로 채웠다. AG2 는 **D03 D3~D4 안에서 M26 상위**로 채운다.
##  base = M26 top-25 (P1 미검 전제 유지). breadth 25 고정. net 15bps. NW3.
##   AH1 스왑 우위: swap - matched_random > 0 ∧ t>=2.0 ∧ swap > fD(M26-refill, T1 gap 2.537)
##   AH2 동등: 유의하나 fD 초과 못함 → refill 출처는 무관, 기전은 '제외' 단독
##   AH3 미달: t<2.0
##  AH4 자본 자격 주장 금지
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
DATA_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
CODE_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.claude/worktrees/jovial-mcnulty-f7d018"
setwd(DATA_ROOT)
OUT <- file.path(CODE_ROOT, "stage_artifacts/fq170_band_cost_20260809")
source(file.path(CODE_ROOT, "02_Infrastructure/contracts/canonical_screen_bt.R"))

B <- readRDS("stage_artifacts/WT_D20260809_003/merged_panel.rds")
P <- readRDS("stage_artifacts/WT_D20260809_001/p0_panels.rds")
ret <- as.data.table(P$ret)[!is.na(Ret_1m)]; liq <- as.data.table(P$liq)
X <- merge(as.data.table(B), ret[, .(Date,Ticker,Ret_1m)], by=c("Date","Ticker"))
X <- merge(X, liq[, .(Date,Ticker,adv)], by=c("Date","Ticker"), all.x=TRUE)
X <- X[is.na(adv) | adv >= 2e8]
D <- X[!is.na(M26_Revenue_Mom) & !is.na(D03_EWMA)]
D[, nmo := .N, by=Date]; D <- D[nmo >= 125L]
D[, rk := frank(-M26_Revenue_Mom, ties.method="first"), by=Date]
D[, q  := cut(frank(D03_EWMA, ties.method="first"),
              breaks=quantile(seq_len(.N), probs=seq(0,1,length.out=11L)),
              include.lowest=TRUE, labels=FALSE), by=Date]

COST <- 0.0015; W <- 1/25
ds <- sort(unique(D$Date)); SL <- lapply(ds, function(dt) D[Date==dt][order(rk)])
SL <- SL[sapply(SL,nrow) >= 60L]
cs <- function(h) sapply(seq_along(SL), function(i) {
  cur <- h[[i]]; prv <- if (i==1L) character(0) else h[[i-1]]
  u <- unique(c(cur,prv)); COST*sum(abs(W*(u %in% cur) - W*(u %in% prv))) })
no <- function(h) sapply(seq_along(SL), function(i) mean(SL[[i]][Ticker %in% h[[i]]]$Ret_1m)) - cs(h)
nb <- no(lapply(SL, function(S) S[seq_len(25L)]$Ticker))
kv <- sapply(SL, function(S) sum(S[seq_len(25L)]$q %in% 9:10))

# A) 스왑: D03 {9,10} 제외 → D3~D4 안에서 M26 상위로 refill
hA <- lapply(seq_along(SL), function(i) {
  S <- SL[[i]]; b <- S[seq_len(25L)]
  keep <- b[!(q %in% 9:10)]$Ticker; k <- 25L - length(keep)
  if (k <= 0L) return(keep)
  pool <- S[q %in% 3:4 & !(Ticker %in% b$Ticker)][order(rk)]$Ticker
  c(keep, head(pool, k)) })
# B) fD 재현: M26 다음 순위로 refill
hB <- lapply(seq_along(SL), function(i) {
  S <- SL[[i]]; S[!(q %in% 9:10)][seq_len(min(25L,.N))]$Ticker })
# C) matched random
M <- matrix(NA_real_, length(SL), 50L)
for (d in 1:50) { set.seed(20260809L + 13000L + d)
  M[,d] <- no(lapply(seq_along(SL), function(j) {
    S <- SL[[j]]; b <- S[seq_len(25L)]$Ticker; k <- kv[j]
    if (k <= 0L) return(b)
    c(setdiff(b, sample(b,k)), head(setdiff(S$Ticker,b), k)) })) }
nr <- rowMeans(M)
nA <- no(hA); nB <- no(hB)
sz <- mean(sapply(hA, length))
R <- data.table(
  arm = c("swap_D3D4_refill","fD_M26_refill"),
  k_mean = round(mean(kv),2), avg_size = round(sz,1),
  vs_base = c(round(mean(nA-nb)*12*100,3), round(mean(nB-nb)*12*100,3)),
  gap_vs_random = c(round(mean(nA-nr)*12*100,3), round(mean(nB-nr)*12*100,3)),
  t_gap = c(round(.nw_t_mean(nA-nr,lag=3L),3), round(.nw_t_mean(nB-nr,lag=3L),3)))
print(R[])
sw <- R[arm=="swap_D3D4_refill"]; fd <- R[arm=="fD_M26_refill"]
verdict <- {
  if (sw$gap_vs_random > 0 && sw$t_gap >= 2.0 && sw$gap_vs_random > fd$gap_vs_random) "AH1_SWAP_SUPERIOR"
  else if (sw$t_gap >= 2.0) "AH2_EQUIVALENT_REFILL_AGNOSTIC"
  else "AH3_BELOW_THRESHOLD"
}
cat(sprintf("\n판정: %s\n★AH4: 자본 자격 주장 없음\n", verdict))
fwrite(R, file.path(OUT,"ag2_swap.csv"))
write_json(list(verdict=verdict, results=R), file.path(OUT,"ag2_result.json"),
           pretty=TRUE, auto_unbox=TRUE, digits=NA)
