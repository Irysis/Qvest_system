## AS2 — D03 밴드 신호의 반감기 (리밸 주기 최적 확정)
## 사전등록(측정 전 고정, 이 주석이 정본):
##  AQ2: gross alpha 가 h=1 9.609 → h=6 5.153 (반감 근처). 반감기를 직접 잰다.
##  측정 = 밴드 선택 시점(t) 기준 **forward k개월 누적 초과수익**(gross, 벤치 대비), k=1..6.
##   월별 편입 코호트를 고정하고 k 개월 뒤까지 홀드했을 때의 초과를 k별로 낸다.
##   AT1 월간 최적: k=1 의 월평균 초과가 최대이고 k 증가에 단조 감소 → 월간이 자연 주기
##   AT2 더 짧은 주기 유리: k=1 이 최대이나 감소가 급격(k=2 에서 <50%) → 주간 검토 가치
##   AT3 더 긴 주기 유리: 최대가 k>=2 → 월간이 과잉 회전
##  ★gross 로만 본다(비용은 AQ2 에서 이미 채널 분리 완료).
##  AT4 자본 자격 주장 없음
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
RET <- ret[Date %in% ds]; setkey(RET, Date, Ticker)
BMv <- bench[Date %in% ds][order(Date)]$BM_Ret; names(BMv) <- as.character(ds)
cat(sprintf("[입력 실측] %d개월\n", length(ds)))

pick <- function(i, m = 12L) {
  S <- D[Date == ds[i]][order(rk)]
  keep <- S[seq_len(min(25L-m, .N))]$Ticker
  pool <- S[q %in% 3:4 & !(Ticker %in% keep)][order(rk)][seq_len(min(m,.N))]$Ticker
  c(keep, pool)
}
sel <- lapply(seq_along(ds), pick)

rows <- list()
for (k in 1:6) {
  ex <- numeric(0)
  for (i in seq_len(length(ds) - k + 1L)) {
    tk <- sel[[i]]
    # i 시점 편입분을 k개월째에 보유했을 때의 그 달 초과 (코호트-연령 k)
    j <- i + k - 1L
    r <- RET[.(ds[j], tk), on = .(Date, Ticker), nomatch = 0L]
    if (nrow(r) < 20L) next
    ex <- c(ex, mean(r$Ret_1m) - BMv[j])
  }
  rows[[length(rows)+1L]] <- data.table(age_k = k, n = length(ex),
    mean_ex_ann = round(mean(ex)*12*100,3), t_nw3 = round(.nw_t_mean(ex, lag=3L),3))
}
R <- rbindlist(rows); print(R[])
r1 <- R$mean_ex_ann[1]; R[, ratio_vs_k1 := round(mean_ex_ann/r1, 3)]
cat("\n감쇠 프로파일 (k=1 대비):", paste(R$ratio_vs_k1, collapse=" "), "\n")
half <- which(R$ratio_vs_k1 <= 0.5)[1]
cat(sprintf("반감 도달 age = %s\n", if (is.na(half)) ">6개월" else paste0(half, "개월")))
verdict <- {
  if (which.max(R$mean_ex_ann) != 1L) "AT3_LONGER_CYCLE_BETTER"
  else if (!is.na(half) && half <= 2L) "AT2_SHORTER_CYCLE_WORTH_TESTING"
  else "AT1_MONTHLY_NATURAL"
}
cat(sprintf("판정: %s\n★AT4: 자본 자격 주장 없음\n", verdict))
fwrite(R, file.path(OUT,"as2_halflife.csv"))
write_json(list(verdict=verdict, half_life_months=half, results=R),
           file.path(OUT,"as2_result.json"), pretty=TRUE, auto_unbox=TRUE, digits=NA)
