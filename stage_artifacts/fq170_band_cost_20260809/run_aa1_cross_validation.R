## AA1 — 병렬 아크(세션 ba4a1c30)의 주 주장을 **밴드-중립 선별**로 재실행
## 사전등록(측정 전 고정, 이 주석이 정본):
##  그쪽 주 주장: Q01_EB(HUMP, argmax D8) **D8~D9 밴드 vs 자기 top-25** = +5.62%p, t_NW3 +2.570 (gross)
##  내 H1: 밴드 내 '점수 상위 25' 는 밴드가 아니라 **밴드 top edge** 를 잰다 → 밴드-중립 필요
##  ⇒ 같은 밴드(D8~D9)·같은 base(자기 top-25)에서 선별만 3가지로 비교한다:
##     (a) 점수상위25  (그쪽/내 A1 방식 재현)
##     (b) 무작위25 x draw 50 (밴드-중립)
##     (c) 밴드 전체 EW (breadth 다름, 참고)
##  ★음성대조: M26(MONOTONE_TOP) 동일 처리 — 그쪽도 음(-4.14)으로 보고했다.
##   AB1 견고: (b) 가 (a) 의 >=70% 유지 ∧ t>=2.0 → 그쪽 확립 견고, 내 H1 붕괴는 밴드 위치 탓
##   AB2 붕괴: (b) 가 (a) 의 <50% → 그쪽 주 주장도 top-edge 산물, 두 카드 함께 강등
##   AB3 혼합: 50~70%
##  AB4 자본 자격 주장 금지 (그쪽도 밴드 절대 PORT_t 0.97 < 2.95 로 자본 한정 명시)
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

BAND <- 8:9                                  # ★그쪽 밴드 그대로
rows <- list()
for (sc in c("Q01_EB","M26_Revenue_Mom")) {
  D <- X[!is.na(get(sc))]
  D[, nmo := .N, by=Date]; D <- D[nmo >= 125L]
  D[, rk := frank(-get(sc), ties.method="first"), by=Date]     # ★자기 랭킹 = 그쪽 base
  D[, qq := cut(frank(get(sc), ties.method="first"),
                breaks=quantile(seq_len(.N), probs=seq(0,1,length.out=11L)),
                include.lowest=TRUE, labels=FALSE), by=Date]
  ds <- sort(unique(D$Date)); SL <- lapply(ds, function(dt) D[Date==dt][order(rk)])
  SL <- SL[sapply(SL, function(S) nrow(S) >= 60L && sum(S$qq %in% BAND) >= 25L)]
  gm <- function(sel) sapply(seq_along(SL), function(i) mean(sel[[i]]))   # gross (그쪽 주장이 gross)
  top <- lapply(SL, function(S) S[seq_len(25L)]$Ret_1m)
  n_top <- gm(top)
  # (a) 점수상위25
  a <- lapply(SL, function(S) S[qq %in% BAND][order(rk)][seq_len(25L)]$Ret_1m)
  # (b) 무작위25 x 50 draw
  bm <- matrix(NA_real_, length(SL), 50L)
  for (d in 1:50) { set.seed(20260809L + 11000L + d)
    bm[,d] <- gm(lapply(SL, function(S) { Bd <- S[qq %in% BAND]; Bd[sample(.N,25L)]$Ret_1m })) }
  # (c) 밴드 전체 EW
  cc <- gm(lapply(SL, function(S) S[qq %in% BAND]$Ret_1m))
  ann <- function(v) mean(v - n_top)*12*100
  tt  <- function(v) .nw_t_mean(v - n_top, lag=3L)
  rows[[length(rows)+1L]] <- data.table(material=sc, n=length(SL),
    a_score25_ann=round(ann(gm(a)),3),   a_t=round(tt(gm(a)),3),
    b_rand25_ann=round(ann(rowMeans(bm)),3), b_t=round(tt(rowMeans(bm)),3),
    c_bandEW_ann=round(ann(cc),3),       c_t=round(tt(cc),3),
    band_n=round(mean(sapply(SL, function(S) sum(S$qq %in% BAND))),1))
}
R <- rbindlist(rows); print(R[])

q <- R[material=="Q01_EB"]
keep <- if (q$a_score25_ann != 0) 100*q$b_rand25_ann/q$a_score25_ann else NA_real_
cat(sprintf("\nQ01 밴드-중립 유지율 = %.1f%% (a %.3f → b %.3f), b 의 t = %.3f\n",
            keep, q$a_score25_ann, q$b_rand25_ann, q$b_t))
verdict <- {
  if (!is.finite(keep)) "AB_UNDEFINED"
  else if (keep >= 70 && q$b_t >= 2.0) "AB1_PARALLEL_CLAIM_ROBUST"
  else if (keep < 50) "AB2_ALSO_TOP_EDGE_ARTIFACT"
  else "AB3_MIXED"
}
cat(sprintf("판정: %s\n★AB4: 자본 자격 주장 없음\n", verdict))
fwrite(R, file.path(OUT,"aa1_cross_validation.csv"))
write_json(list(verdict=verdict, retention_pct=keep, results=R),
           file.path(OUT,"aa1_result.json"), pretty=TRUE, auto_unbox=TRUE, digits=NA)
