## AU1 — AD1 규칙의 밴드 폭 확장이 gross 상한 2.642 를 올리는가
## 사전등록(측정 전 고정, 이 주석이 정본):
##  AQ2: 이 arm 의 gross 상한 = 2.642 (< 2.95). 비용·회전·주기 3축 폐쇄. 남은 것은 신호 크기.
##  AD1 규칙은 '연속 양-분위 **쌍**'(D03 → D3~D4). 폭만 확장한다.
##  ★폭 후보를 **사전 고정**: {D3-D4}(기준) · {D2-D4} · {D3-D5} · {D2-D5} · {D1-D4} · {D3-D6}
##    — argmax 사후선택 금지. 6개 고정 후보 전수를 보고 **최대를 고르지 않고 전부 보고**한다.
##  판정량 = m=12 arm 구성에서 refill pool 만 바꾼 gross active(벤치 대비, NW3). 비용 없음(상한 축).
##   AV1 확장 유효: 어느 사전고정 폭이 gross t >= 2.95
##   AV2 상한 불변: 전 후보가 <= 2.70 (기준 2.642 대비 +0.06 이내) → 폭은 레버 아님
##   AV3 부분 개선: 그 외 — 개선폭과 다중검정(6후보) 부담을 함께 보고
##  AV4 자본 자격 주장은 AV1 충족 시에만. 6후보 선택은 selection_type='sweep', n_trials=6 병기.
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
ds <- sort(unique(D$Date))
BMv <- bench[Date %in% ds][order(Date)]$BM_Ret
cat(sprintf("[입력 실측] %d개월 · 벤치 %d\n", length(ds), length(BMv)))

WID <- list("D3-D4"=3:4, "D2-D4"=2:4, "D3-D5"=3:5, "D2-D5"=2:5, "D1-D4"=1:4, "D3-D6"=3:6)
rows <- list()
for (nm in names(WID)) {
  bd <- WID[[nm]]
  g <- sapply(seq_along(ds), function(i) {
    S <- D[Date == ds[i]][order(rk)]
    keep <- S[seq_len(min(13L, .N))]$Ticker                 # 25-12
    pool <- S[q %in% bd & !(Ticker %in% keep)][order(rk)][seq_len(min(12L,.N))]$Ticker
    sel <- c(keep, pool)
    mean(S[Ticker %in% sel]$Ret_1m) })
  ex <- g - BMv
  rows[[length(rows)+1L]] <- data.table(band = nm, width = length(bd),
    gross_ann = round(mean(ex)*12*100,3), gross_t = round(.nw_t_mean(ex, lag=3L),3))
}
R <- rbindlist(rows); print(R[])
base_t <- R[band=="D3-D4", gross_t]; mx <- max(R$gross_t)
cat(sprintf("\n기준(D3-D4) t = %.3f · 최대 t = %.3f (%s) · 개선 %+.3f\n",
            base_t, mx, R[which.max(gross_t), band], mx - base_t))
verdict <- {
  if (mx >= 2.95) "AV1_WIDTH_EXPANSION_WORKS"
  else if (mx <= base_t + 0.06) "AV2_CEILING_UNCHANGED"
  else "AV3_PARTIAL"
}
cat(sprintf("판정: %s\n★AV4: 자본 자격 주장 없음 · selection_type='sweep', n_trials=6 병기\n", verdict))
fwrite(R, file.path(OUT,"au1_band_width.csv"))
write_json(list(verdict=verdict, base_t=base_t, max_t=mx, n_trials=6, results=R),
           file.path(OUT,"au1_result.json"), pretty=TRUE, auto_unbox=TRUE, digits=NA)
