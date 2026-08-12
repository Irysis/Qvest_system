## Z2 — 기전이 '나쁜 종목 제외' 인가 '분포 **꼬리 절단**' 인가
## 사전등록(측정 전 고정, 이 주석이 정본):
##  Y3 에서 흩어진 {1,8,10} 은 t 0.776, 연속 {8,9,10} 은 t 2.597(Z1). 같은 재료·유사 강도인데 갈렸다.
##  ⇒ D03 에서 **크기 3 고정**하고 배치만 바꿔 비교한다.
##   연속 상단: {8,9,10}   연속 중간: {4,5,6}   연속 하단: {1,2,3}
##   흩어짐: {1,5,10} · {2,6,9} · {1,8,10}(Y3 재현)
##   Z2a 꼬리절단: 연속 상단만 t>=2.0 ∧ 흩어진 3종 전부 t<2.0 → 기전 = 상단 꼬리 절단
##   Z2b 위치무관: 흩어진 것 중 t>=2.0 이 있음 → 연속성은 기전이 아니고 다른 요인
##   Z2c 혼합
##  Z2d 자본 자격 주장 금지
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
D[, qq := cut(frank(D03_EWMA, ties.method="first"),
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

ZONES <- list("연속상단 8-10"=8:10, "연속중간 4-6"=4:6, "연속하단 1-3"=1:3,
              "흩어짐 1,5,10"=c(1L,5L,10L), "흩어짐 2,6,9"=c(2L,6L,9L), "흩어짐 1,8,10"=c(1L,8L,10L))
rows <- list()
for (i in seq_along(ZONES)) {
  Z <- ZONES[[i]]
  kv <- sapply(SL, function(S) sum(S[seq_len(25L)]$qq %in% Z))
  nf <- no(lapply(SL, function(S) S[!(qq %in% Z)][seq_len(min(25L,.N))]$Ticker))
  M <- matrix(NA_real_, length(SL), 50L)
  for (d in 1:50) { set.seed(20260809L + 20000L + 1000L*i + d)
    M[,d] <- no(lapply(seq_along(SL), function(j) {
      S <- SL[[j]]; b <- S[seq_len(25L)]$Ticker; k <- kv[j]
      if (k <= 0L) return(b)
      c(setdiff(b, sample(b,k)), head(setdiff(S$Ticker,b), k)) })) }
  gp <- nf - rowMeans(M)
  rows[[length(rows)+1L]] <- data.table(zone=names(ZONES)[i],
    contiguous = i <= 3L, k_mean=round(mean(kv),2),
    filter_vs_base=round(mean(nf-nb)*12*100,3),
    gap=round(mean(gp)*12*100,3), t_gap=round(.nw_t_mean(gp, lag=3L),3))
}
R <- rbindlist(rows); print(R[])

top <- R[zone=="연속상단 8-10", t_gap]
scat <- R[contiguous==FALSE]
verdict <- {
  if (top >= 2.0 && all(scat$t_gap < 2.0)) "Z2a_TAIL_TRUNCATION"
  else if (any(scat$t_gap >= 2.0)) "Z2b_POSITION_AGNOSTIC"
  else "Z2c_MIXED"
}
cat(sprintf("\n=== 사전등록 판정 ===\n연속상단 t %.3f · 흩어짐 최대 t %.3f\n판정: %s\n★Z2d: 자본 자격 주장 없음\n",
            top, max(scat$t_gap), verdict))
fwrite(R, file.path(OUT,"z2_contiguity.csv"))
write_json(list(verdict=verdict, results=R), file.path(OUT,"z2_result.json"),
           pretty=TRUE, auto_unbox=TRUE, digits=NA)
