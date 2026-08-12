## BW1 — 선별 영역 분리: 두 레버가 서로 다른 종목 영역을 담당하게 한다
## 사전등록(측정 전 고정, 이 주석이 정본):
##  BU1: 겹침은 신호가 아니라 **선별 수준**(둘 다 같은 종목 영역을 고름).
##  ⇒ 영역을 명시 분할한다. base 상위 K종은 **순수 base** 로 채우고, 나머지 (25-K)종만
##     **base 순위 밖(K+1 위 이하)의 D03 밴드(D3~D4)** 에서 뽑는다.
##     기존 AI1 은 K=13 고정에 pool 을 base 순위 무관하게 잡아 상단과 겹쳤다.
##     여기서는 pool 을 **base 순위 26위 이하**로 강제해 상단 중복을 원천 차단한다.
##  arm: K in {13, 18, 21} x pool 하한 {26위 이하} + 대조(AI1 원판 m=12)
##   BX1 분리 유효: 어느 K 에서 PORT_t > 2.137 → 선별 분리가 답, 결합 경로 회복
##   BX2 무효: 전 K 가 <= 2.137 → 선별 분리로도 안 됨. 아크 자체 축 완전 폐쇄
##  ★양성 대조 = AI1 원판이 2.137 재현. 커버리지 명시. 자본 자격 주장은 >=2.95 시에만.
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
U <- merge(B[!is.na(M26_Revenue_Mom) & !is.na(D03_EWMA)], ret[, .(Date,Ticker,Ret_1m)], by=c("Date","Ticker"))
U <- merge(U, liq[, .(Date,Ticker,adv)], by=c("Date","Ticker"), all.x=TRUE)
U <- U[is.na(adv) | adv >= 2e8]
U[, nmo := .N, by=Date]; U <- U[nmo >= 125L]
U[, rk := frank(-M26_Revenue_Mom, ties.method="first"), by=Date]
U[, q  := cut(frank(D03_EWMA, ties.method="first"),
              breaks=quantile(seq_len(.N), probs=seq(0,1,length.out=11L)),
              include.lowest=TRUE, labels=FALSE), by=Date]
cat(sprintf("[유니버스] %d개월\n", uniqueN(U$Date)))

mk <- function(K, pool_min) U[, {
  keep <- .SD[rk <= K]$Ticker
  pool <- .SD[rk >= pool_min & q %in% 3:4 & !(Ticker %in% keep)][order(rk)][seq_len(min(25L-K, .N))]$Ticker
  sel <- c(keep, pool)
  .(Ticker=.SD$Ticker, score=ifelse(.SD$Ticker %in% sel, 1000 - rk, -1e6))
}, by=Date, .SDcols=c("Ticker","rk","q")]
mk_ai1 <- function(m) U[, {
  keep <- .SD[order(rk)][seq_len(min(25L-m,.N))]$Ticker
  pool <- .SD[q %in% 3:4 & !(Ticker %in% keep)][order(rk)][seq_len(min(m,.N))]$Ticker
  sel <- c(keep, pool)
  .(Ticker=.SD$Ticker, score=ifelse(.SD$Ticker %in% sel, 1000 - rk, -1e6))
}, by=Date, .SDcols=c("Ticker","rk","q")]

run <- function(Sc, lab) {
  r <- try(canonical_screen_bt(Sc, ret[, .(Date,Ticker,Ret_1m)], bench, top_n=25L, cost_bps_oneway=15,
        liq_dt=liq[, .(Date,Ticker,adv)], liq_min=2e8, run_id=lab, strategy_id=lab), silent=TRUE)
  if (inherits(r,"try-error")) { cat(lab,"실패\n"); return(NULL) }
  data.table(arm=lab, coverage=round(r$selected_ret_coverage,4),
             PORT_t=round(r$portfolio_alpha_t_nw_lag3,3), alpha_ann=round(r$alpha_annualized*100,3),
             turn=round(r$turnover_annual,2))
}
rows <- list(run(mk_ai1(12L), "AI1_ref_m12"))
for (K in c(13L,18L,21L)) rows[[length(rows)+1L]] <- run(mk(K, 26L), sprintf("split_K%d_pool26", K))
R <- rbindlist(Filter(Negate(is.null), rows)); print(R[])
ref <- R[arm=="AI1_ref_m12", PORT_t]; mx <- max(R[arm!="AI1_ref_m12", PORT_t])
cat(sprintf("\n양성대조 AI1 %.3f / 정본 2.137 · 분리 최대 %.3f\n", ref, mx))
ok <- abs(ref - 2.137) <= 0.05
verdict <- { if (!ok) "BX0_POSITIVE_CONTROL_FAILED"
             else if (min(R$coverage) < 0.95) "BX_INVALID_COVERAGE"
             else if (mx > 2.137) "BX1_SPLIT_WORKS" else "BX2_SPLIT_FAILS_AXES_CLOSED" }
cat(sprintf("판정: %s\n★자본 자격 주장은 PORT_t>=2.95 시에만\n", verdict))
fwrite(R, file.path(OUT,"bw1_split.csv"))
write_json(list(verdict=verdict, ref=ref, max_split=mx, results=R),
           file.path(OUT,"bw1_result.json"), pretty=TRUE, auto_unbox=TRUE, digits=NA)
