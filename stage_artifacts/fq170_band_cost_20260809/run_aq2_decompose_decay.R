## AQ2 — 보유기간 연장의 감쇠가 (a) 신호 감쇠인가 (b) 비용 구조인가
## 사전등록(측정 전 고정, 이 주석이 정본):
##  AK2: h 1→6 에서 회전 -71%, net PORT_t -48%. net 만 봐서 두 채널이 섞여 있다.
##  ⇒ 같은 보유집합에서 **gross** 와 **net** 을 분리해 h별로 낸다.
##   AR1 신호 감쇠: gross 도 h 에 대해 단조 감소(gross 감소폭 >= net 감소폭의 70%)
##       → 회전 레버 닫힘 확정(비용을 0 으로 해도 안 됨)
##   AR2 비용 구조: gross 는 평평/증가인데 net 만 감소 → 비용이 범인이고, 비용 저감 구성이 레버
##   AR3 혼합: 그 외
##  ★비용 채널 크기 = gross - net (연율). h별로 함께 보고.
##  AR4 자본 자격 주장 없음
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
DATA_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
CODE_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.claude/worktrees/jovial-mcnulty-f7d018"
setwd(DATA_ROOT)
OUT <- file.path(CODE_ROOT, "stage_artifacts/fq170_band_cost_20260809")
source(file.path(CODE_ROOT, "02_Infrastructure/contracts/canonical_screen_bt.R"))

P <- readRDS("stage_artifacts/WT_D20260809_001/p0_panels.rds")
ret <- as.data.table(P$ret)[!is.na(Ret_1m)]; liq <- as.data.table(P$liq)
bench <- unique(as.data.table(P$bench)[!is.na(BM_Ret), .(Date, BM_Ret)])[order(Date)]
B <- as.data.table(readRDS("stage_artifacts/WT_D20260809_003/merged_panel.rds"))
D <- merge(B[!is.na(M26_Revenue_Mom) & !is.na(D03_EWMA)], ret[, .(Date,Ticker,Ret_1m)], by=c("Date","Ticker"))
D <- merge(D, liq[, .(Date,Ticker,adv)], by=c("Date","Ticker"), all.x=TRUE)
D <- D[is.na(adv) | adv >= 2e8]
D[, nmo := .N, by=Date]; D <- D[nmo >= 125L]
D[, rk := frank(-M26_Revenue_Mom, ties.method="first"), by=Date]
D[, q  := cut(frank(D03_EWMA, ties.method="first"),
              breaks=quantile(seq_len(.N), probs=seq(0,1,length.out=11L)),
              include.lowest=TRUE, labels=FALSE), by=Date]
ds <- sort(unique(D$Date)); BM <- bench[Date %in% ds][order(Date)]
cat(sprintf("[입력 실측] %d개월 · 벤치 정합 %d\n", length(ds), nrow(BM)))

pick <- function(dt, m = 12L) {
  S <- D[Date == dt][order(rk)]
  keep <- S[seq_len(min(25L-m, .N))]$Ticker
  pool <- S[q %in% 3:4 & !(Ticker %in% keep)][order(rk)][seq_len(min(m,.N))]$Ticker
  c(keep, pool)
}
COST <- 0.0015; W <- 1/25
rows <- list()
for (h in c(1L,2L,3L,6L)) {
  hold <- vector("list", length(ds)); last <- NULL
  for (i in seq_along(ds)) { if ((i-1L) %% h == 0L || is.null(last)) last <- pick(ds[i]); hold[[i]] <- last }
  g <- sapply(seq_along(ds), function(i) mean(D[Date == ds[i] & Ticker %in% hold[[i]]]$Ret_1m))
  cc <- sapply(seq_along(ds), function(i) {
    cur <- hold[[i]]; prv <- if (i==1L) character(0) else hold[[i-1]]
    u <- unique(c(cur,prv)); COST*sum(abs(W*(u %in% cur) - W*(u %in% prv))) })
  ag <- g - BM$BM_Ret            # gross active
  an <- (g - cc) - BM$BM_Ret     # net active
  rows[[length(rows)+1L]] <- data.table(h = h,
    gross_ann = round(mean(ag)*12*100,3), gross_t = round(.nw_t_mean(ag, lag=3L),3),
    net_ann   = round(mean(an)*12*100,3), net_t   = round(.nw_t_mean(an, lag=3L),3),
    cost_ann  = round(mean(cc)*12*100,3), turn = round(sum(cc)/COST/length(ds)*12,2))
}
R <- rbindlist(rows); print(R[])

dg <- R$gross_t[1] - R$gross_t[nrow(R)]
dn <- R$net_t[1]   - R$net_t[nrow(R)]
cat(sprintf("\nt 감소폭: gross %.3f · net %.3f · 비율 %.2f\n", dg, dn, dg/dn))
verdict <- {
  if (dn <= 0) "AR3_MIXED"
  else if (dg >= 0.70*dn) "AR1_SIGNAL_DECAY"
  else if (dg <= 0.30*dn) "AR2_COST_STRUCTURE"
  else "AR3_MIXED"
}
cat(sprintf("판정: %s\n★AR4: 자본 자격 주장 없음\n", verdict))
fwrite(R, file.path(OUT,"aq2_decay_decompose.csv"))
write_json(list(verdict=verdict, gross_t_drop=dg, net_t_drop=dn, results=R),
           file.path(OUT,"aq2_result.json"), pretty=TRUE, auto_unbox=TRUE, digits=NA)
