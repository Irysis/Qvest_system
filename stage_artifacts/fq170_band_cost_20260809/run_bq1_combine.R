## BQ1 — 강화 base(+0.723) x D03 밴드(+0.845) 결합: 두 축은 독립인가
## 사전등록(측정 전 고정, 이 주석이 정본):
##  BN1: m26 1.292 → m26+MONOTONE 부차군 **2.015**(+0.723, 커버리지 1.0)
##  AI1: m26 base 에 D03 밴드 m=12 → **2.137**(+0.845)
##  ⇒ 강화 base 위에 같은 밴드(m=12)를 얹어 4-셀 2x2 를 만든다.
##     arm: (1) m26 단독 (2) 강화base (3) m26+밴드 (4) **강화base+밴드**
##  ★단순 합 가정 금지. 상호작용 = (4) - (2) - (3) + (1) 을 명시 계산해 보고한다.
##   BR1 가법 근접: (4) >= 2.80 ∧ |상호작용| <= 0.25 → 두 축 독립, 문턱 근접
##   BR2 중복: 상호작용 <= -0.30 → 같은 정보를 두 번 씀. base 축만 남긴다
##   BR3 시너지: 상호작용 >= +0.30
##  ★양성 대조: (1) 이 1.292, (3) 이 2.137 을 재현해야 (2)(4) 를 해석한다(BL1 교훈).
##  ★커버리지를 전 arm 명시 기록. BQ4 자본 자격 주장은 PORT_t>=2.95 시에만.
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
DATA_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
CODE_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.claude/worktrees/jovial-mcnulty-f7d018"
setwd(DATA_ROOT)
OUT <- file.path(CODE_ROOT, "stage_artifacts/fq170_band_cost_20260809")
source(file.path(CODE_ROOT, "02_Infrastructure/contracts/canonical_screen_bt.R"))
source(file.path(CODE_ROOT, "02_Infrastructure/factor_db/factor_db_connector.R"))

S <- fread(file.path(OUT, "az1_shape_census.csv"))
SEC <- grep("^M0[12]", S[shape=="MONOTONE_TOP"]$Factor_Name, value=TRUE, invert=TRUE)
P <- readRDS("stage_artifacts/WT_D20260809_001/p0_panels.rds")
ret <- as.data.table(P$ret)[!is.na(Ret_1m)]; liq <- as.data.table(P$liq)
bench <- unique(as.data.table(P$bench)[!is.na(BM_Ret), .(Date, BM_Ret)])[order(Date)]
B <- as.data.table(readRDS("stage_artifacts/WT_D20260809_003/merged_panel.rds"))
U <- merge(B[!is.na(M26_Revenue_Mom) & !is.na(D03_EWMA)], ret[, .(Date,Ticker,Ret_1m)], by=c("Date","Ticker"))
U <- merge(U, liq[, .(Date,Ticker,adv)], by=c("Date","Ticker"), all.x=TRUE)
U <- U[is.na(adv) | adv >= 2e8]
U[, nmo := .N, by=Date]; U <- U[nmo >= 125L]
U[, q := cut(frank(D03_EWMA, ties.method="first"),
             breaks=quantile(seq_len(.N), probs=seq(0,1,length.out=11L)),
             include.lowest=TRUE, labels=FALSE), by=Date]
ds <- sort(unique(U$Date))
cat(sprintf("[유니버스] %d개월\n", length(ds)))

## 강화 점수(부차군 합성) 사전 계산
acc <- list()
for (i in seq_along(ds)) {
  dt <- ds[i]
  z <- try(load_month_factors(dt, factor_names = SEC), silent=TRUE)
  zc <- if (inherits(z,"try-error")) NULL else
        as.data.table(z)[!is.na(Z_Score_Aligned), .(zc = mean(Z_Score_Aligned)), by=Ticker]
  m <- U[Date == dt, .(Ticker, m26 = M26_Revenue_Mom, q)]
  m <- if (is.null(zc)) m[, zc := 0] else merge(m, zc, by="Ticker", all.x=TRUE)[is.na(zc), zc := 0]
  m[, base_plain := scale(m26)[,1]]
  m[, base_strong := (scale(m26)[,1] + scale(zc)[,1])/2]
  acc[[length(acc)+1L]] <- m[, .(Date=dt, Ticker, q, base_plain, base_strong)]
}
A <- rbindlist(acc)

mk <- function(bcol, band) A[, {
  o <- order(-get(bcol))
  tk <- .SD$Ticker[o]; qq <- .SD$q[o]
  keep <- tk[seq_len(min(25L - band, .N))]
  pool <- tk[qq %in% 3:4 & !(tk %in% keep)]
  sel <- c(keep, head(pool, band))
  .(Ticker = .SD$Ticker,
    score = ifelse(.SD$Ticker %in% sel, 1000 - frank(-.SD[[bcol]], ties.method="first"), -1e6))
}, by = Date, .SDcols = c("Ticker","q",bcol)]

run <- function(Sc, lab) {
  r <- try(canonical_screen_bt(Sc, ret[, .(Date,Ticker,Ret_1m)], bench, top_n=25L,
        cost_bps_oneway=15, liq_dt=liq[, .(Date,Ticker,adv)], liq_min=2e8,
        run_id=lab, strategy_id=lab), silent=TRUE)
  if (inherits(r,"try-error")) { cat(lab, "실패\n"); return(NULL) }
  data.table(arm=lab, n=r$n_months, coverage=round(r$selected_ret_coverage,4),
             PORT_t=round(r$portfolio_alpha_t_nw_lag3,3), IR=round(r$information_ratio,3),
             alpha_ann=round(r$alpha_annualized*100,3))
}
R <- rbindlist(list(
  run(mk("base_plain",  0L), "1_plain_nobandd"),
  run(mk("base_strong", 0L), "2_strong_noband"),
  run(mk("base_plain", 12L), "3_plain_band12"),
  run(mk("base_strong",12L), "4_strong_band12")))
print(R[])
g <- function(k) R[arm==k, PORT_t]
inter <- g("4_strong_band12") - g("2_strong_noband") - g("3_plain_band12") + g("1_plain_nobandd")
cat(sprintf("\n양성대조: (1) %.3f vs 정본 1.292 · (3) %.3f vs 정본 2.137\n", g("1_plain_nobandd"), g("3_plain_band12")))
cat(sprintf("상호작용 = (4)-(2)-(3)+(1) = %+.3f · 최종 (4) = %.3f\n", inter, g("4_strong_band12")))
ok <- abs(g("1_plain_nobandd")-1.292) <= 0.05 && abs(g("3_plain_band12")-2.137) <= 0.05
verdict <- { if (!ok) "BR0_POSITIVE_CONTROL_FAILED"
             else if (min(R$coverage) < 0.95) "BR_INVALID_COVERAGE"
             else if (g("4_strong_band12") >= 2.80 && abs(inter) <= 0.25) "BR1_ADDITIVE_NEAR_THRESHOLD"
             else if (inter <= -0.30) "BR2_REDUNDANT"
             else if (inter >= 0.30) "BR3_SYNERGY" else "BR4_PARTIAL" }
cat(sprintf("판정: %s\n★BQ4: 자본 자격 주장은 PORT_t>=2.95 시에만\n", verdict))
fwrite(R, file.path(OUT,"bq1_combine.csv"))
write_json(list(verdict=verdict, interaction=inter, final=g("4_strong_band12"), results=R),
           file.path(OUT,"bq1_result.json"), pretty=TRUE, auto_unbox=TRUE, digits=NA)
