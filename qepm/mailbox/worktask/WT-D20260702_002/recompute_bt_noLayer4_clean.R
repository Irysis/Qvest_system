## ============================================================================
## WT-D20260702_002 Step 3 — noLayer4 book(R05×m4) 클린 bt_result 재계산
## ★frequency=monthly 정확 연율화(annualization_factor=12). RDS 06_metrics의 252 버그 회피.
## build_bt_result 계약 함수(build_metrics / build_benchmark_compare) 경유 — self-synth 금지.
## judge 확정값(SR 1.898 / Calmar 1.943 / CAGR 0.4526 / PORT_t 6.21)과 대조 검증.
##
## noL4 series = beta_R05 × m4 × ret_orig − |Δbeta_R05|×15bps  (deepdive와 동일 정의)
##   ↑ Layer4(β_faith/β_AR) 제거. 5-panel 07_period_returns_layer5_faith.csv 재사용(269월).
## metric_type = backtested(contract). PerformanceAnalytics 표준함수만(계약 내부).
## ============================================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
  library(PerformanceAnalytics); library(xts); library(lubridate)
})
ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
OUT <- file.path(ROOT, "qepm/mailbox/worktask/WT-D20260702_002/output")
source(file.path(ROOT, "02_Infrastructure/contracts/backtest_result_contract.R"))
COST <- 0.0015

## --- 1. panel + noL4 series 재구성 (deepdive와 동일) ---
p <- fread(file.path(ROOT,"05_Production/2.Factor_Model/2-2.STR_1715_FaithTrend_on_M4_R05_overlay_PG2/04_backtest_results/period_returns_layer5_faith.csv"))
p[, anchor_date := as.Date(anchor_date)]; setorder(p, realized_ym); stopifnot(nrow(p)==269)
dR05 <- abs(p$beta_R05 - shift(p$beta_R05,1,fill=1.0))
p[, ret_noL4 := beta_R05*m4*ret_orig - dR05*COST]

## --- 2. benchmark (pinned IKS200, 계약 month-return anchored) ---
BM_PIN <- file.path(ROOT, "stage_artifacts/pg2_offense_overlay/benchmark_pinned_20260702.parquet")
bm <- as.data.table(read_parquet(BM_PIN)); bm[, Date := as.Date(Date)]
bm <- bm[is.finite(BM_Ret)]; setorder(bm, Date)
bm_x <- xts(bm$BM_Ret, order.by=bm$Date)
## 월별 벤치: anchor_date[i-1] < window <= anchor_date[i] 누적 (deepdive [I]와 동일)
a <- p$anchor_date; bmw <- rep(NA_real_, nrow(p))
for(i in 2:nrow(p)){ seg <- bm_x[index(bm_x)>a[i-1] & index(bm_x)<=a[i]]; if(nrow(seg)>0) bmw[i] <- as.numeric(Return.cumulative(seg)) }
bmw[1] <- 0

## --- 3. 계약 shape period_returns_tbl + benchmark_returns_tbl (monthly) ---
RID <- "STR_1715_on_M4_R05_noLayer4_PG2_20260702"; SID <- "STR_1715_on_M4_R05_noLayer4_PG2"
pr <- data.table(run_id=RID, strategy_id=SID, date=p$anchor_date, frequency="monthly",
                 ret_gross=p$ret_noL4, ret_net=p$ret_noL4, risk_free_ret=0,
                 excess_ret_net=p$ret_noL4, turnover=NA_real_, cost_ret=0,
                 cash_weight=NA_real_, leverage=NA_real_, n_holdings=NA_integer_)
br <- data.table(benchmark_id="KOSPI200", benchmark_name="KOSPI 200", date=p$anchor_date,
                 benchmark_ret=bmw, benchmark_nav=cumprod(1+ifelse(is.na(bmw),0,bmw)),
                 risk_free_ret=0, benchmark_excess_ret=bmw, frequency="monthly")

## --- 4. 계약 함수 경유 지표 (★annualization_factor=12) ---
nav_v <- cumprod(1 + pr$ret_net)
nav_tbl <- data.table(run_id=RID, strategy_id=SID, date=pr$date, frequency="monthly",
                      nav_gross=nav_v, nav_net=nav_v, drawdown=NA_real_)
hold_tbl <- data.table(matrix(nrow=0, ncol=length(HOLDINGS_COLS), dimnames=list(NULL,HOLDINGS_COLS)))
metrics <- build_metrics(nav_tbl, pr, hold_tbl, RID, SID, frequency="monthly", annualization_factor=12)
bcmp    <- build_benchmark_compare(pr, br, RID, SID, annualization_factor=12)

gv <- function(dt, mn, col="metric_value"){ v <- dt[metric_name==mn][[col]]; if(length(v)) v[1] else NA_real_ }
SR     <- gv(metrics, "Sharpe")   ## Charter v1.4 §12: mean(ER)/sd(ER)*sqrt(12) — book_state incumbent 정의와 동일
CAGR   <- gv(metrics, "CAGR")
MDD    <- gv(metrics, "MDD")
CALMAR <- gv(metrics, "Calmar")
## judge/deepdive/3-way headline 정의 = table.AnnualizedReturns (geometric): 별도 산출해 양 정의 기록
x_noL4 <- xts(pr$ret_net, order.by=pr$date)
SR_geo <- as.numeric(table.AnnualizedReturns(x_noL4, scale=12)[3,1])  ## = judge 1.898
PORT_t <- bcmp[metric_name=="Portfolio_Alpha_t_NW_lag3"]$strategy_value[1]
IR     <- bcmp[metric_name=="Information_Ratio"]$active_value[1]
ALPHA  <- bcmp[metric_name=="Alpha_Annualized"]$strategy_value[1]
BETA   <- bcmp[metric_name=="Beta_to_Benchmark"]$strategy_value[1]

cat("\n===== noLayer4 클린 재계산 (계약 함수, annualization=12) =====\n")
cat(sprintf("  n_periods         = %d (%s ~ %s)\n", nrow(pr), min(pr$date), max(pr$date)))
cat(sprintf("  Sharpe (Charter §12 arith) = %.4f   [book_state incumbent 정의]\n", SR))
cat(sprintf("  Sharpe (geometric table)   = %.4f   [judge/3-way headline 1.898]\n", SR_geo))
cat(sprintf("  CAGR              = %.4f   [judge 0.4526]\n", CAGR))
cat(sprintf("  MDD               = %.4f   [judge 0.2329]\n", MDD))
cat(sprintf("  Calmar            = %.4f   [judge 1.943]\n", CALMAR))
cat(sprintf("  PORT_t (NW lag3)  = %.4f   [judge 6.214]\n", PORT_t))
cat(sprintf("  Information Ratio = %.4f   [judge 6.49 / decision 1.326?]\n", IR))
cat(sprintf("  Alpha (annualized)= %.4f\n", ALPHA))
cat(sprintf("  Beta to KOSPI200  = %.4f\n", BETA))

## --- 5. 대조 판정 (tolerance) ---
chk <- function(nm, got, exp, tol){ ok <- is.finite(got) && abs(got-exp) <= tol
  cat(sprintf("  [%s] %s: got %.4f vs judge %.4f (tol %.3f)\n", if(ok)"PASS"else"DIFF", nm, got, exp, tol)); ok }
cat("\n===== judge 정합 대조 (judge 헤드라인 = geometric convention) =====\n")
ok_sr <- chk("SR_geometric", SR_geo, 1.898, 0.01)  ## judge 1.898 = table.AnnualizedReturns
ok_cg <- chk("CAGR", CAGR, 0.4526, 0.01)
ok_cl <- chk("Calmar", CALMAR, 1.943, 0.02)
ok_pt <- chk("PORT_t", PORT_t, 6.214, 0.10)
all_ok <- ok_sr && ok_cg && ok_cl && ok_pt
cat(sprintf("  [INFO] SR(Charter §12 arith)=%.4f — book_state incumbent 정의(≠judge headline, 정상 컨벤션 차이)\n", SR))
cat(sprintf("\n[OVERALL] judge 정합: %s\n", if(all_ok)"PASS (재계산값 = judge 확정값, convention 명시)" else "REVIEW (차이 발생 — 조사 필요)"))

## --- 6. bt_result 조립 + 저장 (계약 shape, monthly) ---
bt <- list(
  manifest = data.table(run_id=RID, strategy_id=SID, frequency="monthly",
    transaction_cost_bps=15, benchmark_ids="KOSPI200",
    note="noLayer4 = R05×m4 (Layer4 β_faith 제거). monthly annualization=12."),
  period_returns=pr, benchmark_returns=br, nav=nav_tbl,
  metrics=metrics, benchmark_compare=bcmp)
saveRDS(bt, file.path(OUT, "bt_result_C_noL4_CLEAN_ann12.rds"))
fwrite(metrics, file.path(OUT, "06_metrics_noL4_clean_ann12.csv"))
fwrite(bcmp, file.path(OUT, "07_benchmark_compare_noL4_clean_ann12.csv"))
write_json(list(
  wt="WT-D20260702_002", step="3_clean_bt_recompute",
  book="STR_1715_on_M4_R05_noLayer4_PG2",
  annualization_factor=12, frequency="monthly", n_periods=nrow(pr),
  metric_type="backtested(contract)",
  sharpe_convention_note="SR_charter_v14 = mean(ER)/sd(ER)*sqrt(12) [book_state incumbent 정의]. SR_geometric = table.AnnualizedReturns [judge/3-way headline]. 같은 시계열·정상 컨벤션 차이(arith vs geo).",
  metrics=list(SR_charter_v14_arith=round(SR,4), SR_geometric_table=round(SR_geo,4),
    CAGR=round(CAGR,4), MDD=round(MDD,4),
    Calmar=round(CALMAR,4), PORT_t_NW_lag3=round(PORT_t,4),
    IR=round(IR,4), alpha_ann=round(ALPHA,4), beta=round(BETA,4)),
  judge_reference=list(SR_headline_geometric=1.898, CAGR=0.4526, MDD=0.2329, Calmar=1.943, PORT_t=6.214),
  judge_parity_pass=all_ok,
  rds_bug_note="bt_result_C_noL4.rds 06_metrics는 annualization=252 버그(CAGR/Calmar 폭주). 본 재계산은 factor=12 정확."),
  file.path(OUT, "step3_clean_recompute_meta.json"), auto_unbox=TRUE, pretty=TRUE)
cat(sprintf("\n[DONE] 저장: bt_result_C_noL4_CLEAN_ann12.rds + step3_clean_recompute_meta.json\n"))
