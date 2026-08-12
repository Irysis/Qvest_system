## P6c — 강한 재료(core4) 위에서 형태 소비가 되살아나는가 (아크 재출발)
## 사전등록(측정 전 고정, 이 주석이 정본):
##  P5a: core4-EW **+1.635** vs mine5-EW -0.283 (재료 효과 +1.918) ⇒ 재료가 기전.
##  내 아크 9축 폐쇄는 **약한 재료(mine5) 조건부**였을 수 있다.
##  ⇒ core4-EW 를 base 로 두고 **D03 밴드(m=12, D3~D4)** 를 얹어 한계 기여를 잰다.
##     P1e 는 PG2 base 위에서 Δ +0.264(재현율 0.31)를 이미 보였다 — core4 에서도 양수인지.
##  arm 2x2: base ∈ {mine(M26), core4-EW} x 밴드 ∈ {없음, m=12}
##   X1 되살아남: core4 base 에서 Δ >= +0.3 → 형태 소비가 강한 재료에서 유효, 9축 재개
##   X2 감쇠 지속: 0 < Δ < 0.3 → P1e 와 같은 감쇠. 형태는 약한 재료 전용 보정
##   X3 역전: Δ < 0 → 강한 재료에서는 해로움. 형태 소비를 재료 조건부 negative 로 확정
##  ★양성 대조: mine base 가 1.292/2.137 재현. 커버리지 명시. 자본 자격 주장 없음.
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
DATA_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
CODE_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.claude/worktrees/jovial-mcnulty-f7d018"
setwd(DATA_ROOT)
OUT <- file.path(CODE_ROOT, "stage_artifacts/fq170_band_cost_20260809")
source(file.path(CODE_ROOT, "02_Infrastructure/contracts/canonical_screen_bt.R"))
source(file.path(CODE_ROOT, "02_Infrastructure/factor_db/factor_db_connector.R"))

CORE4 <- c("C01_SUE","C02_EPS_Chg_1m","C04_ESBR","C06_TP_Gap")
P <- readRDS("stage_artifacts/WT_D20260809_001/p0_panels.rds")
ret <- as.data.table(P$ret)[!is.na(Ret_1m)]; liq <- as.data.table(P$liq)
bench <- unique(as.data.table(P$bench)[!is.na(BM_Ret), .(Date, BM_Ret)])[order(Date)]
B <- as.data.table(readRDS("stage_artifacts/WT_D20260809_003/merged_panel.rds")); B[, Date := as.Date(Date)]
ds <- sort(unique(B$Date))

acc <- list()
for (i in seq_along(ds)) {
  z <- try(load_month_factors(ds[i], factor_names = CORE4), silent=TRUE)
  if (inherits(z,"try-error")) next
  z <- as.data.table(z)[!is.na(Z_Score_Aligned)]
  acc[[length(acc)+1L]] <- dcast(z, Ticker ~ Factor_Name, value.var="Z_Score_Aligned")[, Date := ds[i]]
}
C4 <- rbindlist(acc, fill=TRUE)

U <- merge(B, ret[, .(Date,Ticker,Ret_1m)], by=c("Date","Ticker"))
U <- merge(U, liq[, .(Date,Ticker,adv)], by=c("Date","Ticker"), all.x=TRUE)
U <- U[is.na(adv) | adv >= 2e8]
U[, nmo := .N, by=Date]; U <- U[nmo >= 125L]
U <- merge(U, C4, by=c("Date","Ticker"), all.x=TRUE)
have4 <- intersect(CORE4, names(U))
U[, q := cut(frank(D03_EWMA, ties.method="first"),
             breaks=quantile(seq_len(.N), probs=seq(0,1,length.out=11L)),
             include.lowest=TRUE, labels=FALSE), by=Date]
UC <- U[complete.cases(U[, have4, with=FALSE]) & !is.na(D03_EWMA)]
UC[, n2 := .N, by=Date]; UC <- UC[n2 >= 125L]
UC[, (have4) := lapply(.SD, function(z){m<-mean(z,na.rm=TRUE);s<-sd(z,na.rm=TRUE);if(!is.finite(s)||s==0) 0 else (z-m)/s}),
   by=Date, .SDcols=have4]
UC[, core4 := rowMeans(as.matrix(.SD), na.rm=TRUE), .SDcols=have4]
cat(sprintf("[유니버스] core4+D03 공통 %d개월\n", uniqueN(UC$Date)))

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
  run(mk(U,  "M26_Revenue_Mom", 0L),  "1_mine_noband"),
  run(mk(U,  "M26_Revenue_Mom", 12L), "2_mine_band12"),
  run(mk(UC, "core4", 0L),  "3_core4_noband"),
  run(mk(UC, "core4", 12L), "4_core4_band12"))))
print(R[])
g <- function(k){v<-R[arm==k,PORT_t]; if(!length(v)) NA_real_ else v}
d_mine <- g("2_mine_band12") - g("1_mine_noband"); d_c4 <- g("4_core4_band12") - g("3_core4_noband")
cat(sprintf("\n양성대조 (1) %.3f/1.292 · (2) %.3f/2.137\n", g("1_mine_noband"), g("2_mine_band12")))
cat(sprintf("밴드 Δ: mine **%+.3f** · core4 **%+.3f** (P1e PG2 base: +0.264)\n", d_mine, d_c4))
ok <- abs(g("1_mine_noband")-1.292)<=0.05 && abs(g("2_mine_band12")-2.137)<=0.05
verdict <- { if (!ok) "X0_POSITIVE_CONTROL_FAILED"
             else if (min(R$coverage)<0.95) "X_INVALID_COVERAGE"
             else if (d_c4 >= 0.30) "X1_SHAPE_REVIVES_ON_STRONG_MATERIAL"
             else if (d_c4 < 0) "X3_HARMFUL_ON_STRONG_MATERIAL"
             else "X2_ATTENUATED" }
cat(sprintf("판정: %s\n★자본 자격 주장 없음\n", verdict))
fwrite(R, file.path(OUT,"p6c_core4_shape.csv"))
write_json(list(verdict=verdict, delta_mine=d_mine, delta_core4=d_c4, results=R),
           file.path(OUT,"p6c_result.json"), pretty=TRUE, auto_unbox=TRUE, digits=NA)
