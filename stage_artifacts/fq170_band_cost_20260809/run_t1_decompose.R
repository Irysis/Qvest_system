## T1 — 폭 효과 분해: 격차 증가가 (a) 필터 개선인가 (b) 대조군 악화인가
## 사전등록(측정 전 고정, 이 주석이 정본):
##  U1 필터 개선: filter_vs_base 가 폭에 대해 spearman >= 0.70  → S1 유지(폭이 기전)
##  U2 대조군 악화: filter_vs_base spearman < 0.30 ∧ random_vs_base spearman <= -0.70 → **S1 철회**
##  U3 혼합: 그 외 → 부분 귀속, 두 성분 기여도를 함께 보고
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
D[, rk   := frank(-M26_Revenue_Mom, ties.method="first"), by=Date]
D[, q10D := cut(frank(D03_EWMA, ties.method="first"),
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

WID <- list("10"=10L, "9-10"=9:10, "8-10"=8:10, "7-10"=7:10, "6-10"=6:10)
rows <- list()
for (i in seq_along(WID)) {
  bad <- WID[[i]]
  hf <- lapply(SL, function(S) S[!(q10D %in% bad)][seq_len(min(25L,.N))]$Ticker)
  kv <- sapply(SL, function(S) sum(S[seq_len(25L)]$q10D %in% bad))
  nf <- no(hf)
  M <- matrix(NA_real_, length(SL), 50L)
  for (d in 1:50) { set.seed(20260809L + 80000L + 1000L*i + d)
    M[, d] <- no(lapply(seq_along(SL), function(j) {
      S <- SL[[j]]; b <- S[seq_len(25L)]$Ticker; k <- kv[j]
      if (k <= 0L) return(b)
      c(setdiff(b, sample(b,k)), head(setdiff(S$Ticker,b), k)) })) }
  nr <- rowMeans(M)
  rows[[length(rows)+1L]] <- data.table(
    zone=names(WID)[i], width=length(bad), k=round(mean(kv),2),
    filter_vs_base=round(mean(nf-nb)*12*100,3),
    random_vs_base=round(mean(nr-nb)*12*100,3),
    gap=round(mean(nf-nr)*12*100,3),
    t_gap=round(.nw_t_mean(nf-nr, lag=3L),3))
}
R <- rbindlist(rows); print(R[])

sp_f <- suppressWarnings(cor(R$width, R$filter_vs_base, method="spearman"))
sp_r <- suppressWarnings(cor(R$width, R$random_vs_base, method="spearman"))
cat(sprintf("\nspearman(폭, filter_vs_base) = %.3f\nspearman(폭, random_vs_base) = %.3f\n", sp_f, sp_r))
verdict <- {
  if (sp_f >= 0.70) "U1_FILTER_IMPROVES_S1_HELD"
  else if (sp_f < 0.30 && sp_r <= -0.70) "U2_CONTROL_DEGRADES_S1_RETRACTED"
  else "U3_MIXED"
}
cat(sprintf("판정: %s\n★U4: 자본 자격 주장 없음\n", verdict))
fwrite(R, file.path(OUT,"t1_decompose.csv"))
write_json(list(verdict=verdict, spearman_filter=sp_f, spearman_random=sp_r, results=R),
           file.path(OUT,"t1_result.json"), pretty=TRUE, auto_unbox=TRUE, digits=NA)
