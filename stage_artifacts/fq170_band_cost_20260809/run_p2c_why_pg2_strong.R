## P2c — PG2 base 2.855 vs 내 M26 1.292: '합성' 때문인가 '재료 선택' 때문인가
## 사전등록(측정 전 고정, 이 주석이 정본):
##  P1e: PG2 base 2.855 · M26 단독 1.292 (같은 계약 경로, 커버리지 1.0).
##  PG2 score_eff 는 core/defense 다중팩터 합성. 내 M26 은 단일 재료.
##  ⇒ 두 가설을 분리한다:
##    H_합성: 여러 재료를 합쳐서 강하다 → **내 5재료를 합성**하면 M26 단독보다 크게 오를 것
##    H_재료: PG2 가 고른 재료가 더 좋다 → 내 5재료 합성으로는 2.855 근처에 못 감
##  arm: (1) M26 단독 (2) 내 5재료 EW-Z 합성 (3) PG2 score_eff (4) PG2 의 core/defense 성분 단독(가능시)
##   V1 합성이 기전: (2) 가 (1) 대비 +1.0 이상 ∧ (3) 의 70% 이상 도달
##   V2 재료가 기전: (2) 가 (3) 의 50% 미만 → PG2 재료 선택이 우위
##   V3 혼합
##  ★양성 대조 (1)=1.292 · (3)=2.855 재현 필수. 커버리지 명시. 자본 자격 주장 없음.
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
DATA_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
CODE_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.claude/worktrees/jovial-mcnulty-f7d018"
setwd(DATA_ROOT)
OUT <- file.path(CODE_ROOT, "stage_artifacts/fq170_band_cost_20260809")
source(file.path(CODE_ROOT, "02_Infrastructure/contracts/canonical_screen_bt.R"))

P <- readRDS("stage_artifacts/WT_D20260809_001/p0_panels.rds")
ret <- as.data.table(P$ret)[!is.na(Ret_1m)]; liq <- as.data.table(P$liq)
bench <- unique(as.data.table(P$bench)[!is.na(BM_Ret), .(Date, BM_Ret)])[order(Date)]
B <- as.data.table(readRDS("stage_artifacts/WT_D20260809_003/merged_panel.rds"))
B[, Date := as.Date(Date)][, ym := format(Date, "%Y-%m")]
A <- as.data.table(read_parquet("stage_artifacts/WT_D20260425_010/alpha_scores.parquet"))
A[, Date := as.Date(Date)][, ym := format(Date, "%Y-%m")]
cat("[PG2 열]", paste(intersect(c("score_eff","score_core_z","score_defense_z"), names(A)), collapse=", "), "\n")

U <- merge(B, ret[, .(Date,Ticker,Ret_1m)], by=c("Date","Ticker"))
U <- merge(U, liq[, .(Date,Ticker,adv)], by=c("Date","Ticker"), all.x=TRUE)
U <- U[is.na(adv) | adv >= 2e8]
U[, nmo := .N, by=Date]; U <- U[nmo >= 125L]
U <- merge(U, A[, .(ym, Ticker, pg2=score_eff, core=score_core_z, def=score_defense_z)],
           by=c("ym","Ticker"), all.x=TRUE)
UP <- U[!is.na(pg2)]; UP[, n2 := .N, by=Date]; UP <- UP[n2 >= 125L]
cat(sprintf("[유니버스] 내 %d개월 · PG2 유효 %d개월\n", uniqueN(U$Date), uniqueN(UP$Date)))

## 내 5재료 EW-Z 합성 (동일 유니버스 UP 에서 — 창 교락 제거)
M5 <- c("M26_Revenue_Mom","M01_PATHQ","Q01_EB","D03_EWMA","z_neutral")
UP[, mine5 := rowMeans(scale(as.matrix(.SD)), na.rm=TRUE), by=Date, .SDcols=M5]

run <- function(D, col, lab) {
  Sc <- D[!is.na(get(col)), .(Date, Ticker, score = get(col))]
  r <- try(canonical_screen_bt(Sc, ret[, .(Date,Ticker,Ret_1m)], bench, top_n=25L, cost_bps_oneway=15,
        liq_dt=liq[, .(Date,Ticker,adv)], liq_min=2e8, run_id=lab, strategy_id=lab), silent=TRUE)
  if (inherits(r,"try-error")) { cat(lab,"실패\n"); return(NULL) }
  data.table(arm=lab, n=r$n_months, coverage=round(r$selected_ret_coverage,4),
             PORT_t=round(r$portfolio_alpha_t_nw_lag3,3), alpha_ann=round(r$alpha_annualized*100,3))
}
rows <- list(run(UP,"M26_Revenue_Mom","1_M26_solo"), run(UP,"mine5","2_mine5_composite"),
             run(UP,"pg2","3_PG2_score_eff"))
if ("core" %in% names(UP) && sum(!is.na(UP$core))>1000) rows[[length(rows)+1L]] <- run(UP,"core","4_PG2_core")
if ("def"  %in% names(UP) && sum(!is.na(UP$def)) >1000) rows[[length(rows)+1L]] <- run(UP,"def", "5_PG2_defense")
R <- rbindlist(Filter(Negate(is.null), rows)); print(R[])
g <- function(k) { v <- R[arm==k, PORT_t]; if (!length(v)) NA_real_ else v }
gain <- g("2_mine5_composite") - g("1_M26_solo"); frac <- g("2_mine5_composite")/g("3_PG2_score_eff")
cat(sprintf("\n합성 이득(내 5재료) %+.3f · PG2 대비 도달률 %.2f\n", gain, frac))
verdict <- { if (!is.finite(frac)) "V_UNDEF"
             else if (gain >= 1.0 && frac >= 0.70) "V1_COMPOSITION_IS_MECHANISM"
             else if (frac < 0.50) "V2_MATERIAL_SELECTION_IS_MECHANISM"
             else "V3_MIXED" }
cat(sprintf("판정: %s\n★자본 자격 주장 없음\n", verdict))
fwrite(R, file.path(OUT,"p2c_why_strong.csv"))
write_json(list(verdict=verdict, gain=gain, frac=frac, results=R),
           file.path(OUT,"p2c_result.json"), pretty=TRUE, auto_unbox=TRUE, digits=NA)
