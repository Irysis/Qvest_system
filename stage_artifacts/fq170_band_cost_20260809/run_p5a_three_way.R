## P5a — 재료 · 조합 · 가중 3원 분해: PG2 2.855 의 필수 성분은 무엇인가
## 사전등록(측정 전 고정, 이 주석이 정본):
##  P2c: 내 5재료 EW 합성 **-0.154** vs PG2 score_eff **2.855**.
##  P4c: PG2 core 4종은 개별 rank-IC 0 근방/음수(UNCLASSIFIED).
##  ⇒ 2x2 로 분해한다: 재료 ∈ {core4, mine5} x 가중 ∈ {EW, IC-가중(PIT 과거 IC)}
##   arm: (1) core4-EW (2) core4-IC (3) mine5-EW(=P2c 재현) (4) mine5-IC
##   W1 재료가 답: (1) 이 이미 높음(>=2.0) → 가중 없이도 core 재료가 강함
##   W2 가중이 답: (1) 낮은데 (2) 높음 ∧ (4) 도 (3) 보다 크게 개선 → 가중이 일반 레버
##   W3 조합(재료x가중) 필요: (2) 만 높고 (4) 는 여전히 낮음 → 두 성분이 함께 있어야
##  ★IC-가중 = 각 sig_date 에서 **Usable_Date < sig_date 인 과거 IC**로 theta 산출(PIT).
##    빌더(_recompute_may_refresh.R:46) 규약 승계 — 재작성 아님.
##  ★양성 대조: (3) 이 P2c 의 -0.154 를 재현해야 한다. 커버리지 명시. 자본 자격 주장 없음.
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
DATA_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
CODE_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.claude/worktrees/jovial-mcnulty-f7d018"
setwd(DATA_ROOT)
OUT <- file.path(CODE_ROOT, "stage_artifacts/fq170_band_cost_20260809")
source(file.path(CODE_ROOT, "02_Infrastructure/contracts/canonical_screen_bt.R"))
source(file.path(CODE_ROOT, "02_Infrastructure/factor_db/factor_db_connector.R"))

CORE4 <- c("C01_SUE","C02_EPS_Chg_1m","C04_ESBR","C06_TP_Gap")
MINE5 <- c("M26_Revenue_Mom","M01_PATHQ","Q01_EB","D03_EWMA","z_neutral")
P <- readRDS("stage_artifacts/WT_D20260809_001/p0_panels.rds")
ret <- as.data.table(P$ret)[!is.na(Ret_1m)]; liq <- as.data.table(P$liq)
bench <- unique(as.data.table(P$bench)[!is.na(BM_Ret), .(Date, BM_Ret)])[order(Date)]
B <- as.data.table(readRDS("stage_artifacts/WT_D20260809_003/merged_panel.rds"))
B[, Date := as.Date(Date)]
ds <- sort(unique(B$Date))

## core4 를 factor_db 에서 로드(월별)
cat("[core4 로드]\n"); acc <- list()
for (i in seq_along(ds)) {
  z <- try(load_month_factors(ds[i], factor_names = CORE4), silent=TRUE)
  if (inherits(z,"try-error")) next
  z <- as.data.table(z)[!is.na(Z_Score_Aligned)]
  acc[[length(acc)+1L]] <- dcast(z, Ticker ~ Factor_Name, value.var="Z_Score_Aligned")[, Date := ds[i]]
}
C4 <- rbindlist(acc, fill=TRUE)
cat(sprintf("  %d행 · %d개월 · 열 %s\n", nrow(C4), uniqueN(C4$Date), paste(setdiff(names(C4),c("Ticker","Date")), collapse=",")))

U <- merge(B, ret[, .(Date,Ticker,Ret_1m)], by=c("Date","Ticker"))
U <- merge(U, liq[, .(Date,Ticker,adv)], by=c("Date","Ticker"), all.x=TRUE)
U <- U[is.na(adv) | adv >= 2e8]
U[, nmo := .N, by=Date]; U <- U[nmo >= 125L]
U <- merge(U, C4, by=c("Date","Ticker"), all.x=TRUE)
have4 <- intersect(CORE4, names(U))
cat(sprintf("[유니버스] %d개월 · core4 커버리지 %.4f (%d/%d종)\n",
            uniqueN(U$Date), mean(complete.cases(U[, have4, with=FALSE])), length(have4), length(CORE4)))

## PIT IC-가중: 각 Date 에서 **그 이전** 월들의 (z, fwd ret) rank 상관 누적 평균
ic_weight <- function(D, cols) {
  ics <- D[, lapply(.SD, function(z) suppressWarnings(cor(z, Ret_1m, method="spearman", use="complete.obs"))),
           by=Date, .SDcols=cols]
  setorder(ics, Date)
  for (cc in cols) ics[, (cc) := shift(frollmean(get(cc), 60L, na.rm=TRUE, align="right"), 1L)]  # ★과거만
  ics
}
mk_score <- function(D, cols, mode) {
  X <- copy(D)
  X[, (cols) := lapply(.SD, function(z) { m<-mean(z,na.rm=TRUE); s<-sd(z,na.rm=TRUE); if(!is.finite(s)||s==0) 0 else (z-m)/s }),
    by=Date, .SDcols=cols]
  if (mode == "EW") { X[, sc := rowMeans(as.matrix(.SD), na.rm=TRUE), .SDcols=cols]; return(X[, .(Date,Ticker,score=sc)]) }
  W <- ic_weight(D, cols)
  X <- merge(X, W, by="Date", suffixes=c("", "_ic"))
  X[, sc := {
    num <- 0; den <- 0
    for (cc in cols) { w <- pmax(get(paste0(cc,"_ic")), 0); w[!is.finite(w)] <- 0
                       v <- get(cc); v[!is.finite(v)] <- 0; num <- num + w*v; den <- den + w }
    ifelse(den > 0, num/den, NA_real_) }]
  X[, .(Date, Ticker, score=sc)]
}
run <- function(Sc, lab) {
  Sc <- Sc[is.finite(score)]
  r <- try(canonical_screen_bt(Sc, ret[, .(Date,Ticker,Ret_1m)], bench, top_n=25L, cost_bps_oneway=15,
        liq_dt=liq[, .(Date,Ticker,adv)], liq_min=2e8, run_id=lab, strategy_id=lab), silent=TRUE)
  if (inherits(r,"try-error")) { cat(lab,"실패:", conditionMessage(attr(r,"condition")),"\n"); return(NULL) }
  data.table(arm=lab, n=r$n_months, coverage=round(r$selected_ret_coverage,4),
             PORT_t=round(r$portfolio_alpha_t_nw_lag3,3), alpha_ann=round(r$alpha_annualized*100,3))
}
U4 <- U[complete.cases(U[, have4, with=FALSE])]
R <- rbindlist(Filter(Negate(is.null), list(
  run(mk_score(U4, have4, "EW"), "1_core4_EW"),
  run(mk_score(U4, have4, "IC"), "2_core4_IC"),
  run(mk_score(U,  MINE5, "EW"), "3_mine5_EW"),
  run(mk_score(U,  MINE5, "IC"), "4_mine5_IC"))))
print(R[])
g <- function(k){v<-R[arm==k,PORT_t]; if(!length(v)) NA_real_ else v}
cat(sprintf("\n양성대조 (3) mine5_EW %.3f / P2c -0.154\n", g("3_mine5_EW")))
cat(sprintf("재료 효과(EW 고정): core4 %.3f - mine5 %.3f = **%+.3f**\n", g("1_core4_EW"), g("3_mine5_EW"), g("1_core4_EW")-g("3_mine5_EW")))
cat(sprintf("가중 효과: core4 %+.3f · mine5 %+.3f\n", g("2_core4_IC")-g("1_core4_EW"), g("4_mine5_IC")-g("3_mine5_EW")))
verdict <- { if (is.na(g("1_core4_EW"))) "W_UNDEF"
             else if (g("1_core4_EW") >= 2.0) "W1_MATERIAL"
             else if (g("2_core4_IC") >= 2.0 && (g("4_mine5_IC")-g("3_mine5_EW")) >= 0.5) "W2_WEIGHTING"
             else "W3_INTERACTION" }
cat(sprintf("판정: %s\n★자본 자격 주장 없음\n", verdict))
fwrite(R, file.path(OUT,"p5a_three_way.csv"))
write_json(list(verdict=verdict, results=R), file.path(OUT,"p5a_result.json"),
           pretty=TRUE, auto_unbox=TRUE, digits=NA)
