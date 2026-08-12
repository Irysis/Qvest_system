## BN3 — 이 아크의 canonical_screen_bt 호출 전수 커버리지 점검
## 사전등록(측정 전 고정, 이 주석이 정본):
##  BL1 이 커버리지 60.1% 로 무효였다. 같은 계약을 호출한 다른 라운드(AE1 · AI1 · AK2)도 확인한다.
##  ★핵심 차이 가설: BL1 은 **팩터 DB 전역**에 점수를 줬고, AE1/AI1/AK2 는 **merged_panel 기반**
##    (이미 K200∪KQ150 ∩ 수익 ∩ adv 필터를 거친 패널)이라 오염이 없을 것이다.
##  ⇒ 대표 arm 을 재실행해 **selected_ret_coverage** 필드를 직접 읽는다(경고 유무가 아니라 값으로).
##   BO1 청정: 전 arm coverage >= 0.95 → 아크 결론 유지, BL1 만 무효
##   BO2 오염: 어느 arm 이든 < 0.95 → 그 라운드 재판정 필요
##  ★값을 읽는다. 경고 문구 유무로 판정하지 않는다(경고는 조건부 출력일 수 있다).
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

mkscore <- function(m) D[, {
  keep <- .SD[order(rk)][seq_len(min(25L-m,.N))]$Ticker
  pool <- .SD[q %in% 3:4 & !(Ticker %in% keep)][order(rk)][seq_len(min(m,.N))]$Ticker
  sel <- c(keep, pool)
  .(Ticker = .SD$Ticker,
    score = ifelse(.SD$Ticker %in% sel, 1000 - frank(-.SD$M26_Revenue_Mom, ties.method="first"), -1e6))
}, by = Date]

rows <- list()
for (lab in c("AI1_m0","AI1_m12","AE1_band_D3D4")) {
  Sc <- if (lab == "AE1_band_D3D4") D[, .(Date, Ticker, score = -abs(q - 3.5))]
        else mkscore(if (lab == "AI1_m0") 0L else 12L)
  r <- try(canonical_screen_bt(Sc, ret[, .(Date,Ticker,Ret_1m)], bench,
        top_n=25L, cost_bps_oneway=15, liq_dt=liq[, .(Date,Ticker,adv)], liq_min=2e8,
        run_id=lab, strategy_id=lab), silent=TRUE)
  if (inherits(r,"try-error")) { cat(sprintf("%s 실패\n", lab)); next }
  rows[[length(rows)+1L]] <- data.table(arm=lab, n=r$n_months,
    coverage=round(r$selected_ret_coverage,4),
    PORT_t=round(r$portfolio_alpha_t_nw_lag3,3))
}
R <- rbindlist(rows); print(R[])
cat("\n[대조 — 기록된 값]  AI1 m=0 1.292 · m=12 2.137 · AE1 band 1.713\n")
mn <- min(R$coverage, na.rm=TRUE)
verdict <- if (mn >= 0.95) "BO1_CLEAN" else "BO2_CONTAMINATED"
cat(sprintf("\n최소 커버리지 = %.4f\n판정: %s\n", mn, verdict))
fwrite(R, file.path(OUT,"bn3_coverage.csv"))
write_json(list(verdict=verdict, min_coverage=mn, results=R),
           file.path(OUT,"bn3_result.json"), pretty=TRUE, auto_unbox=TRUE, digits=NA)
