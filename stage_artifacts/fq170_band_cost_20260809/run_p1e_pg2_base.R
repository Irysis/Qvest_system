## P1e — PG2 base 위에서 D03 밴드가 재현되는가 (아크 마지막 외적 타당성 관문)
## 사전등록(측정 전 고정, 이 주석이 정본):
##  해소된 장벽: ym 겹침 270개월(P1a) · 방향 정합 forward(P1n, PG2 base 0.9992) · vintage clean(P1q).
##  남은 전제: 내 base 가 **M26 top-25 사후선택**. ⇒ production PG2 base(score_eff)로 갈아끼운다.
##  arm 2x2: base ∈ {M26(내 정본), PG2 score_eff} x 밴드 ∈ {없음, D03 D3~D4 m=12}
##   U1 재현: PG2 base 에서도 밴드 Δ(밴드-무밴드)가 **양수 ∧ 내 Δ(+0.845)의 50% 이상**
##            → 아크 외적 타당성 확보
##   U2 부호 반전: PG2 base 에서 Δ < 0 → 아크는 M26 사후선택 산물. 전량 재판정
##   U3 감쇠: 0 < Δ < 0.4225 → 부분 재현, 크기 진술 하향
##  ★양성 대조: 내 base arm 이 1.292 / 2.137 을 재현해야 PG2 arm 을 해석한다(BL1 교훈).
##  ★커버리지 전 arm 명시. 자본 자격 주장은 PORT_t>=2.95 시에만.
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

## PG2 base — ym 키로 내 날짜축에 매핑(P1a 정합 확인 완료)
A <- as.data.table(read_parquet("stage_artifacts/WT_D20260425_010/alpha_scores.parquet"))
A[, Date := as.Date(Date)][, ym := format(Date, "%Y-%m")]
A <- A[!is.na(score_eff), .(ym, Ticker, pg2 = score_eff)]

U <- merge(B[!is.na(M26_Revenue_Mom) & !is.na(D03_EWMA)], ret[, .(Date,Ticker,Ret_1m)], by=c("Date","Ticker"))
U <- merge(U, liq[, .(Date,Ticker,adv)], by=c("Date","Ticker"), all.x=TRUE)
U <- U[is.na(adv) | adv >= 2e8]
U[, nmo := .N, by=Date]; U <- U[nmo >= 125L]
U[, q := cut(frank(D03_EWMA, ties.method="first"),
             breaks=quantile(seq_len(.N), probs=seq(0,1,length.out=11L)),
             include.lowest=TRUE, labels=FALSE), by=Date]
U <- merge(U, A, by=c("ym","Ticker"), all.x=TRUE)
cat(sprintf("[유니버스] %d행 · %d개월 · pg2 커버리지 %.4f\n",
            nrow(U), uniqueN(U$Date), mean(!is.na(U$pg2))))
UP <- U[!is.na(pg2)]
UP[, nmo2 := .N, by=Date]; UP <- UP[nmo2 >= 125L]
cat(sprintf("[PG2 유효] %d행 · %d개월\n", nrow(UP), uniqueN(UP$Date)))

mk <- function(D, bc, band) D[, {
  o <- order(-get(bc)); tk <- .SD$Ticker[o]; qq <- .SD$q[o]
  keep <- tk[seq_len(min(25L-band, .N))]; pool <- tk[qq %in% 3:4 & !(tk %in% keep)]
  sel <- c(keep, head(pool, band))
  .(Ticker=.SD$Ticker, score=ifelse(.SD$Ticker %in% sel, 1000-frank(-.SD[[bc]], ties.method="first"), -1e6))
}, by=Date, .SDcols=c("Ticker","q",bc)]
run <- function(Sc, lab) {
  r <- try(canonical_screen_bt(Sc, ret[, .(Date,Ticker,Ret_1m)], bench, top_n=25L, cost_bps_oneway=15,
        liq_dt=liq[, .(Date,Ticker,adv)], liq_min=2e8, run_id=lab, strategy_id=lab), silent=TRUE)
  if (inherits(r,"try-error")) { cat(lab,"실패\n"); return(NULL) }
  data.table(arm=lab, n=r$n_months, coverage=round(r$selected_ret_coverage,4),
             PORT_t=round(r$portfolio_alpha_t_nw_lag3,3), alpha_ann=round(r$alpha_annualized*100,3))
}
R <- rbindlist(Filter(Negate(is.null), list(
  run(mk(U,  "M26_Revenue_Mom", 0L),  "1_M26_noband"),
  run(mk(U,  "M26_Revenue_Mom", 12L), "2_M26_band12"),
  run(mk(UP, "pg2", 0L),  "3_PG2_noband"),
  run(mk(UP, "pg2", 12L), "4_PG2_band12"))))
print(R[])
g <- function(k) R[arm==k, PORT_t]
d_my  <- g("2_M26_band12") - g("1_M26_noband")
d_pg2 <- g("4_PG2_band12") - g("3_PG2_noband")
cat(sprintf("\n양성대조: M26 무밴드 %.3f/1.292 · M26 밴드 %.3f/2.137\n", g("1_M26_noband"), g("2_M26_band12")))
cat(sprintf("밴드 Δ: 내 base **%+.3f** · PG2 base **%+.3f** · 재현율 %.2f\n", d_my, d_pg2, d_pg2/d_my))
ok <- abs(g("1_M26_noband")-1.292)<=0.05 && abs(g("2_M26_band12")-2.137)<=0.05
verdict <- { if (!ok) "U0_POSITIVE_CONTROL_FAILED"
             else if (min(R$coverage)<0.95) "U_INVALID_COVERAGE"
             else if (d_pg2 < 0) "U2_SIGN_FLIP_ARC_INVALIDATED"
             else if (d_pg2 >= 0.5*d_my) "U1_REPRODUCED"
             else "U3_ATTENUATED" }
cat(sprintf("판정: %s\n★자본 자격 주장은 PORT_t>=2.95 시에만\n", verdict))
fwrite(R, file.path(OUT,"p1e_pg2_base.csv"))
write_json(list(verdict=verdict, delta_mine=d_my, delta_pg2=d_pg2, results=R),
           file.path(OUT,"p1e_result.json"), pretty=TRUE, auto_unbox=TRUE, digits=NA)
