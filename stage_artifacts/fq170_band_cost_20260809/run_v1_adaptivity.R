## V1 — 구역 규칙의 우위는 '적응 강도' 인가 '멤버십' 인가
## 사전등록(측정 전 고정, 이 주석이 정본):
##  구역 규칙은 월별 k_t 가 변한다(적응). zone-free 고정 k 는 안 변한다.
##  ⇒ zone-free 를 **k_t 에 일치**시켜(월별 같은 수, 단 D03 원순위 상위에서) 재측정한다.
##   W1 적응성이 기전: k_t 일치 zone-free 가 zone 성능의 >=80% 회복 → '폭' 서술 폐기, 기전=적응 강도
##   W2 멤버십이 기전: 회복 <50% → 어느 종목을 빼는가(구역 멤버십) 자체가 정보
##   W3 혼합: 50~80%
##  W4 자본 자격 주장 금지
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
D[, dR := frank(-D03_EWMA, ties.method="first"), by=Date]
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

rows <- list()
for (bad in list("8-10"=8:10, "6-10"=6:10)) {
  zn <- if (identical(bad, 8:10)) "8-10" else "6-10"
  kv <- sapply(SL, function(S) sum(S[seq_len(25L)]$q10D %in% bad))
  # A) zone 판본
  hA <- lapply(SL, function(S) S[!(q10D %in% bad)][seq_len(min(25L,.N))]$Ticker)
  # B) k_t 일치 zone-free: 같은 달 같은 수를 D03 원순위 상위에서 제외
  hB <- lapply(seq_along(SL), function(i) {
    S <- SL[[i]]; b <- S[seq_len(25L)]; k <- kv[i]
    if (k <= 0L) return(b$Ticker)
    drop <- b[order(dR)][seq_len(min(k, nrow(b)))]$Ticker
    c(setdiff(b$Ticker, drop), head(setdiff(S$Ticker, b$Ticker), length(drop))) })
  a <- mean(no(hA) - nb)*12*100; bb <- mean(no(hB) - nb)*12*100
  ov <- mean(mapply(function(x,y) length(intersect(x,y))/25, hA, hB))
  rows[[length(rows)+1L]] <- data.table(zone=zn, k_mean=round(mean(kv),2),
    zone_ann=round(a,3), kt_matched_zonefree_ann=round(bb,3),
    recovery_pct=round(100*bb/a,1), holdings_overlap=round(ov,3))
}
R <- rbindlist(rows); print(R[])
rec <- mean(R$recovery_pct)
verdict <- {
  if (rec >= 80) "W1_ADAPTIVITY_IS_MECHANISM"
  else if (rec < 50) "W2_MEMBERSHIP_IS_MECHANISM"
  else "W3_MIXED"
}
cat(sprintf("\n평균 회복률 %.1f%%\n판정: %s\n★W4: 자본 자격 주장 없음\n", rec, verdict))
fwrite(R, file.path(OUT,"v1_adaptivity.csv"))
write_json(list(verdict=verdict, recovery_mean=rec, results=R),
           file.path(OUT,"v1_result.json"), pretty=TRUE, auto_unbox=TRUE, digits=NA)
