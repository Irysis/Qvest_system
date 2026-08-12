## AD1 — 소비 규칙을 '**인접 좋은 분위 쌍**' 으로 재정의해 5재료 적용
## 사전등록(측정 전 고정, 이 주석이 정본):
##  AC1: argmax-추종은 고원형 재료에서 불안정. D8~D9 는 둘 다 양이라 견고, D4~D6 은 D4/D6 이 ~0 이라 희석.
##  ⇒ 규칙 = 프로파일에서 **연속하며 둘 다 양(+)인 분위 쌍 중 합이 최대**인 쌍을 소비 밴드로.
##     (재료마다 자동 도출. argmax 도 고정 밴드도 아님.)
##  판정 대상 = 그 쌍의 밴드-중립 25종(무작위 x 50 draw) vs 자기 top-25, gross · NW3.
##   AD1a 규칙 유효: HUMP/INVERTED 재료 중 >=2 가 t>=2.0 ∧ MONOTONE 2종은 도출 쌍이 D9~D10 근방(상단)
##   AD1b 규칙 임의적: 그 외
##  ★MONOTONE 재료는 좋은 쌍이 상단이므로 밴드=top 근방 → 개선 없음이 정상(자기 대조).
##  AD1c 자본 자격 주장 금지
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

MATS <- list(M26_Revenue_Mom="MONOTONE_TOP", M01_PATHQ="MONOTONE_TOP",
             Q01_EB="HUMP", z_neutral="HUMP", D03_EWMA="INVERTED")
rows <- list()
for (sc in names(MATS)) {
  D <- X[!is.na(get(sc))]
  D[, nmo := .N, by=Date]; D <- D[nmo >= 125L]
  D[, rk := frank(-get(sc), ties.method="first"), by=Date]
  D[, q  := cut(frank(get(sc), ties.method="first"),
                breaks=quantile(seq_len(.N), probs=seq(0,1,length.out=11L)),
                include.lowest=TRUE, labels=FALSE), by=Date]
  D[, u := mean(Ret_1m), by=Date]
  pr <- D[, .(ex=mean(Ret_1m)-u[1]), by=.(Date,q)][, .(ann=mean(ex)*12*100), by=q][order(q)]
  # 연속 쌍 중 둘 다 양이면서 합 최대
  best <- NULL; bs <- -Inf
  for (i in 1:9) if (pr$ann[i] > 0 && pr$ann[i+1] > 0 && (pr$ann[i]+pr$ann[i+1]) > bs) {
    bs <- pr$ann[i]+pr$ann[i+1]; best <- c(i, i+1) }
  if (is.null(best)) { rows[[length(rows)+1L]] <- data.table(material=sc, shape=MATS[[sc]],
      pair="none", pair_sum=NA_real_, ann=NA_real_, t=NA_real_, n=NA_integer_); next }
  ds <- sort(unique(D$Date)); SL <- lapply(ds, function(dt) D[Date==dt][order(rk)])
  SL <- SL[sapply(SL, function(S) nrow(S)>=60L && sum(S$q %in% best) >= 25L)]
  n_top <- sapply(SL, function(S) mean(S[seq_len(25L)]$Ret_1m))
  M <- matrix(NA_real_, length(SL), 50L)
  for (d in 1:50) { set.seed(20260809L + 12000L + 1000L*match(sc,names(MATS)) + d)
    M[,d] <- sapply(SL, function(S) { Bd <- S[q %in% best]; mean(Bd[sample(.N,25L)]$Ret_1m) }) }
  dm <- rowMeans(M) - n_top
  rows[[length(rows)+1L]] <- data.table(material=sc, shape=MATS[[sc]],
    pair=paste(best, collapse="-"), pair_sum=round(bs,2),
    ann=round(mean(dm)*12*100,3), t=round(.nw_t_mean(dm, lag=3L),3), n=length(SL))
}
R <- rbindlist(rows); print(R[])

nonmono <- R[shape != "MONOTONE_TOP" & !is.na(t)]
mono <- R[shape == "MONOTONE_TOP" & !is.na(t)]
hit <- sum(nonmono$ann > 0 & nonmono$t >= 2.0)
mono_top <- all(sapply(strsplit(mono$pair,"-"), function(z) max(as.integer(z)) >= 9L))
verdict <- if (hit >= 2L && mono_top) "AD1a_RULE_VALID" else "AD1b_RULE_ARBITRARY"
cat(sprintf("\n=== 사전등록 판정 ===\n비-MONOTONE 통과 %d/%d · MONOTONE 쌍이 상단(>=D9) %s\n판정: %s\n★AD1c: 자본 자격 주장 없음\n",
            hit, nrow(nonmono), mono_top, verdict))
fwrite(R, file.path(OUT,"ad1_adjacent_pair.csv"))
write_json(list(verdict=verdict, hits=hit, results=R), file.path(OUT,"ad1_result.json"),
           pretty=TRUE, auto_unbox=TRUE, digits=NA)
