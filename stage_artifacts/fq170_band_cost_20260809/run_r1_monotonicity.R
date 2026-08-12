## R1 — 나쁜구역 **폭**이 기전 변수인가 (승자 재검정이 아니라 단조 예측의 반증 검정)
##
## 사전등록 (측정 전 고정, 이 주석이 정본):
##  배경: P2 에서 {10} 0.299(t 0.962) → {9,10} 1.330(t 1.699) → {8,9,10} 2.655(t 2.652) 단조 증가.
##        {8,9,10} 을 그냥 다시 재면 **3변형 중 승자 재검정**이라 사후선택을 못 씻는다.
##  ⇒ 검정 대상은 승자가 아니라 **단조 예측**이다. 폭이 기전 변수라면 미측정 폭
##     {7..10} · {6..10} 에서도 패턴이 이어지거나 고원에 도달해야 한다.
##     사후선택 노이즈라면 새 점에서 **깨진다**(비단조·급락).
##
##  S1 지지: 5폭 계열의 효과가 폭에 대해 spearman >= 0.80 ∧ 최대 t >= 2.0 (draw 100)
##  S2 고원: 단조가 {8,9,10} 까지만이고 이후 평탄(|Δ| < 0.5%p) — 폭에 최적점 존재로 해석
##  S3 기각: 새 점에서 비단조 붕괴(spearman < 0.50) → 사후선택 산물로 확정, 필터 축 강등
##  S4 draw: 전표본 draw=100 (P2 의 20→50 반전 재발 방지). 부분창은 draw=50, 3분할
##  S5 자본 자격 주장 금지
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
cat(sprintf("[입력 실측] %d행 · %d개월\n", nrow(D), uniqueN(D$Date)))

COST <- 0.0015; W <- 1/25
cell <- function(Dsub, badset, ndraw, seed0) {
  ds <- sort(unique(Dsub$Date))
  SL <- lapply(ds, function(dt) Dsub[Date==dt][order(rk)]); SL <- SL[sapply(SL,nrow) >= 60L]
  if (length(SL) < 24L) return(NULL)
  cs <- function(h) sapply(seq_along(SL), function(i) {
    cur <- h[[i]]; prv <- if (i==1L) character(0) else h[[i-1]]
    u <- unique(c(cur,prv)); COST*sum(abs(W*(u %in% cur) - W*(u %in% prv))) })
  no <- function(h) sapply(seq_along(SL), function(i) mean(SL[[i]][Ticker %in% h[[i]]]$Ret_1m)) - cs(h)
  hf <- lapply(SL, function(S) S[!(q10D %in% badset)][seq_len(min(25L,.N))]$Ticker)
  kv <- sapply(SL, function(S) sum(S[seq_len(25L)]$q10D %in% badset))
  nf <- no(hf)
  M <- matrix(NA_real_, length(SL), ndraw)
  for (d in seq_len(ndraw)) {
    set.seed(seed0 + d)
    M[, d] <- no(lapply(seq_along(SL), function(i) {
      S <- SL[[i]]; b <- S[seq_len(25L)]$Ticker; k <- kv[i]
      if (k <= 0L) return(b)
      c(setdiff(b, sample(b,k)), head(setdiff(S$Ticker,b), k)) }))
  }
  dm <- nf - rowMeans(M)
  list(n=length(SL), k=mean(kv), ann=mean(dm)*12*100, t=.nw_t_mean(dm, lag=3L))
}

WID <- list("10"=10L, "9-10"=9:10, "8-10"=8:10, "7-10"=7:10, "6-10"=6:10)
rows <- list()
for (i in seq_along(WID)) {
  r <- cell(D, WID[[i]], 100L, 20260809L + 90000L + 1000L*i)
  rows[[length(rows)+1L]] <- data.table(zone=names(WID)[i], width=length(WID[[i]]),
                                        window="full", n=r$n, k=round(r$k,2),
                                        ann=round(r$ann,3), t=round(r$t,3), ndraw=100L)
}
Rf <- rbindlist(rows); print(Rf[])
sp <- suppressWarnings(cor(Rf$width, Rf$ann, method="spearman"))
cat(sprintf("\n폭 vs 효과 spearman = %.3f · 최대 t = %.3f\n", sp, max(Rf$t)))

# 부분창 3분할 — 상위 2폭만 (draw 50)
cat("\n=== 부분창 3분할 (상위 2폭, draw 50) ===\n")
qs <- quantile(as.numeric(D$Date), c(1/3, 2/3)); brk <- as.Date(qs, origin="1970-01-01")
top2 <- Rf[order(-t)][1:2]$zone
rows2 <- list()
for (z in top2) for (w in 1:3) {
  Dsub <- if (w==1L) D[Date < brk[1]] else if (w==2L) D[Date >= brk[1] & Date < brk[2]] else D[Date >= brk[2]]
  r <- cell(Dsub, WID[[z]], 50L, 20260809L + 95000L + 100L*w)
  if (is.null(r)) next
  rows2[[length(rows2)+1L]] <- data.table(zone=z, tercile=w, n=r$n,
                                          ann=round(r$ann,3), t=round(r$t,3))
}
Rs <- rbindlist(rows2); print(Rs[])
sign_ok <- all(sapply(top2, function(z) { v <- Rs[zone==z]$ann; length(v)==3L && all(sign(v)==sign(v[1])) }))

verdict <- {
  if (sp >= 0.80 && max(Rf$t) >= 2.0) "S1_WIDTH_IS_MECHANISM"
  else if (sp < 0.50) "S3_POST_SELECTION_ARTIFACT"
  else "S2_PLATEAU_OR_INCONCLUSIVE"
}
cat(sprintf("\n=== 사전등록 판정 ===\nspearman %.3f · max t %.3f · 3분할 부호일치 %s\n판정: %s\n★S5: 자본 자격 주장 없음\n",
            sp, max(Rf$t), sign_ok, verdict))
fwrite(Rf, file.path(OUT,"r1_width_full.csv")); fwrite(Rs, file.path(OUT,"r1_width_terciles.csv"))
write_json(list(verdict=verdict, spearman=sp, max_t=max(Rf$t), sign_consistent=sign_ok,
                full=Rf, terciles=Rs), file.path(OUT,"r1_result.json"),
           pretty=TRUE, auto_unbox=TRUE, digits=NA)
