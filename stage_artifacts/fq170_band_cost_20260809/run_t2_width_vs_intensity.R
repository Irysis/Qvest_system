## T2 — 기전 변수는 '폭' 인가 '강도(k)' 인가 (현재 완전 교락)
## 사전등록(측정 전 고정, 이 주석이 정본):
##  설계: zone 규칙({8,9,10} 등)은 사실 "D03 상위" 의 대리물이다. 강도만 남긴 판본 =
##        **top-25 안에서 D03 상위 k 종을 직접 제외**(zone 개념 없음). k in {1,3,5,7,9}.
##  U1 강도가 기전: zone-free k-곡선이 같은 k 의 zone 곡선과 차이 <= 0.5%p (전 k) → 폭은 k 의 대리물일 뿐
##  U2 폭이 추가정보: 어떤 k 에서 zone 판본이 zone-free 를 1.0%p 이상 초과 → 폭에 고유 정보 있음
##  U3 혼합: 그 외
##  U4 자본 자격 주장 금지
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
D[, dR := frank(-D03_EWMA, ties.method="first"), by=Date]   # 1 = D03 최상위(=나쁜 쪽)

COST <- 0.0015; W <- 1/25
ds <- sort(unique(D$Date)); SL <- lapply(ds, function(dt) D[Date==dt][order(rk)])
SL <- SL[sapply(SL,nrow) >= 60L]
cs <- function(h) sapply(seq_along(SL), function(i) {
  cur <- h[[i]]; prv <- if (i==1L) character(0) else h[[i-1]]
  u <- unique(c(cur,prv)); COST*sum(abs(W*(u %in% cur) - W*(u %in% prv))) })
no <- function(h) sapply(seq_along(SL), function(i) mean(SL[[i]][Ticker %in% h[[i]]]$Ret_1m)) - cs(h)
nb <- no(lapply(SL, function(S) S[seq_len(25L)]$Ticker))

rand_at <- function(kv, seed0, nd=50L) {
  M <- matrix(NA_real_, length(SL), nd)
  for (d in seq_len(nd)) { set.seed(seed0+d)
    M[,d] <- no(lapply(seq_along(SL), function(j) {
      S <- SL[[j]]; b <- S[seq_len(25L)]$Ticker; k <- kv[j]
      if (k <= 0L) return(b)
      c(setdiff(b, sample(b,k)), head(setdiff(S$Ticker,b), k)) })) }
  rowMeans(M)
}
rows <- list()
for (k in c(1L,3L,5L,7L,9L)) {
  # zone-free: top-25 안에서 D03 순위 상위 k 종 제외 후 M26 다음 순위로 refill
  hf <- lapply(SL, function(S) {
    b <- S[seq_len(25L)]
    drop <- b[order(dR)][seq_len(min(k, nrow(b)))]$Ticker
    c(setdiff(b$Ticker, drop), head(setdiff(S$Ticker, b$Ticker), length(drop))) })
  nf <- no(hf)
  nr <- rand_at(rep(k, length(SL)), 20260809L + 60000L + 1000L*k)
  rows[[length(rows)+1L]] <- data.table(mode="zone_free", k=k,
    filter_vs_base=round(mean(nf-nb)*12*100,3),
    gap=round(mean(nf-nr)*12*100,3), t_gap=round(.nw_t_mean(nf-nr,lag=3L),3))
}
Z <- rbindlist(rows); print(Z[])

# zone 판본(T1 산출) 과 같은 k 에서 대조
T1 <- fread(file.path(OUT,"t1_decompose.csv"))
cat("\n=== zone 판본 (T1) ===\n"); print(T1[, .(zone, k, filter_vs_base, gap, t_gap)])
cmp <- sapply(seq_len(nrow(T1)), function(i) {
  kk <- T1$k[i]; j <- which.min(abs(Z$k - kk))
  T1$filter_vs_base[i] - Z$filter_vs_base[j] })
cat(sprintf("\nzone - zone_free (같은 k 근사 대조, %%p): %s\n",
            paste(sprintf("%+.3f", cmp), collapse=" ")))
verdict <- {
  if (all(abs(cmp) <= 0.5)) "U1_INTENSITY_IS_MECHANISM"
  else if (any(cmp >= 1.0)) "U2_WIDTH_ADDS_INFORMATION"
  else "U3_MIXED"
}
cat(sprintf("판정: %s\n★U4: 자본 자격 주장 없음\n", verdict))
fwrite(Z, file.path(OUT,"t2_zonefree.csv"))
write_json(list(verdict=verdict, zone_free=Z, zone_minus_zonefree=cmp),
           file.path(OUT,"t2_result.json"), pretty=TRUE, auto_unbox=TRUE, digits=NA)
