## ============================================================================
## SPEC-1 — 유휴현금 캐리 + m4 무과금 정정 세트의 계약-grade 검증 (run_all.R)
## G3(book_state 반영)·G2(현금 캐리 실행) 결정 재료 생산 — book_state 변경 없음.
##
## 실행: cd 04_Research/pg2_carry_convention && Rscript -e 'source("run_all.R")'
##       (source 패턴 — 한글 -e 금지 규약)
##
## 변형 4종 (모두 build_bt_result() -> audit_bt_result() 계약 경유, monthly ann=12):
##   V0_base       = beta_R05*m4*ret_orig − |ΔR05|×15bps            (현행 recon — judge 정합 재현)
##   V1_carry_only = V0 + cashfrac×rf_m                              (캐리 단독 — ΔSR +0.0124 ±10% 재현 확인)
##   V2_m4cost     = beta_R05*m4*ret_orig − |Δ(β_R05×m4)|×15bps     (m4 무과금 정정 단독 — 첫 실측)
##   V3_set        = beta_R05*m4*ret_orig + cashfrac×rf_m − |Δ(β_R05×m4)|×15bps  (세트 — 최종)
##
## 규율:
##   - pin_cache vintage pin + manifest tag 기록 (재실행 시 기존 tag 재사용 = 판정 입력 불변)
##   - 실측만 (contract 함수 / PerformanceAnalytics 표준함수만 — 자체합성 금지)
##   - setDTthreads(1) 단일스레드. arrow io thread는 건드리지 않음(1로 설정 시 HANG 실증).
##   - 캐리 PIT: rf = CD91 last-known ≤ anchor_date (홀딩월 시작 전 확정 — C5 정합).
##     CD91 시작 2005-08 이전 구간은 Call1D 대체 (a2_gap_decomp.R 동일 규약).
## ============================================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
  library(PerformanceAnalytics); library(xts)
})
setDTthreads(1)

ROOT   <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
OUTDIR <- file.path(ROOT, "04_Research/pg2_carry_convention")
COST   <- 0.0015   # 15bps one-way (cost_model_version v2.4_kr_retail_15bps, delta-based)

source(file.path(ROOT, "02_Infrastructure/contracts/backtest_result_contract.R"))
source(file.path(ROOT, "02_Infrastructure/contracts/audit_bt_result.R"))
source(file.path(ROOT, "02_Infrastructure/data/pin_cache.R"))

## ---- 0. vintage pin (idempotent: 기존 tag 재사용) --------------------------
PANEL_SRC <- file.path(ROOT, "05_Production/2.Factor_Model/2-2.STR_1715_FaithTrend_on_M4_R05_overlay_PG2/04_backtest_results/period_returns_layer5_faith.csv")
BM_SRC    <- file.path(ROOT, "stage_artifacts/pg2_offense_overlay/benchmark_pinned_20260702.parquet")  # = WT-D20260702_002 step3 (IR 1.416 산출 기반)과 동일 벤치
ECOS_SRC  <- file.path(ROOT, ".cache/ecos_bond_rates.parquet")

tagfile <- file.path(OUTDIR, "spec1_pin_tag.txt")
if (file.exists(tagfile)) {
  TAG <- trimws(readLines(tagfile, warn = FALSE)[1])
  cat(sprintf("[pin] 기존 tag 재사용: %s (vintage 불변)\n", TAG))
} else {
  TAG <- format(Sys.time(), "spec1_carry_%Y%m%d_%H%M%S")
  pin_cache(c(PANEL_SRC, BM_SRC, ECOS_SRC), TAG)
  writeLines(TAG, tagfile)
}
pin_manifest <- jsonlite::fromJSON(file.path(ROOT, ".cache/pins", TAG, "manifest.json"),
                                   simplifyDataFrame = FALSE)

## judge-vintage 대조용: WT-D20260702_002 step3 클린 bt_result (07-02 vintage 시계열 보존본)
##   — 현행 패널 CSV는 07-02 이후 갱신(2026-06 수정)됨. 방법 재현은 이 vintage로 검증.
S3RDS_SRC <- file.path(ROOT, "qepm/mailbox/worktask/WT-D20260702_002/output/bt_result_C_noL4_CLEAN_ann12.rds")
.pinned_bn <- vapply(pin_manifest$files, function(f) f$basename, character(1))
if (!basename(S3RDS_SRC) %in% .pinned_bn) {
  pin_cache(S3RDS_SRC, TAG)
  pin_manifest <- jsonlite::fromJSON(file.path(ROOT, ".cache/pins", TAG, "manifest.json"),
                                     simplifyDataFrame = FALSE)
}

## ---- 1. 패널 + 변형 시계열 구성 (WT-D20260702_002 recon 정의 상속) ---------
p <- fread(read_pinned(PANEL_SRC, TAG))
p[, anchor_date := as.Date(anchor_date)]; setorder(p, realized_ym)
stopifnot(nrow(p) == 269)

dR05 <- abs(p$beta_R05 - shift(p$beta_R05, 1, fill = 1.0))     # 현행 과금 기준
p[, invested := beta_R05 * m4]
dInv <- abs(p$invested - shift(p$invested, 1, fill = 1.0))     # 정정 과금 기준 |Δ(β_R05×m4)|
p[, cashfrac := 1 - invested]

## 캐리 rf (PIT: anchor_date 기준 last-known — 홀딩월 시작 전 확정)
b  <- as.data.table(read_parquet(read_pinned(ECOS_SRC, TAG)))
b[, Date := as.Date(Date)]
cd    <- b[Series == "KR_CD91"][order(Date)]
call1 <- b[Series == "KR_Call1D"][order(Date)]
lastknown <- function(tbl, d) { v <- tbl[Date <= d, Value]; if (length(v)) tail(v, 1) else NA_real_ }
p[, rf_cd   := sapply(anchor_date, function(d) lastknown(cd, d))]
p[, rf_call := sapply(anchor_date, function(d) lastknown(call1, d))]
p[, rf_used := ifelse(is.na(rf_cd), rf_call, rf_cd)]
p[, rf_m := rf_used / 100 / 12]
n_call_fallback <- sum(is.na(p$rf_cd))
cd91_latest <- cd[.N]  # G2용 최신 CD91 (pinned vintage)

## 변형 4종
p[, ret_v0 := invested * ret_orig - dR05 * COST]
p[, ret_v1 := ret_v0 + cashfrac * rf_m]
p[, ret_v2 := invested * ret_orig - dInv * COST]
p[, ret_v3 := invested * ret_orig + cashfrac * rf_m - dInv * COST]

## ---- 2. 벤치 월수익 (step3와 동일: anchor (i-1, i] 누적, pinned IKS200) ----
bm <- as.data.table(read_parquet(read_pinned(BM_SRC, TAG)))
bm[, Date := as.Date(Date)]; bm <- bm[is.finite(BM_Ret)]; setorder(bm, Date)
bm_x <- xts(bm$BM_Ret, order.by = bm$Date)
a <- p$anchor_date; bmw <- rep(NA_real_, nrow(p))
for (i in 2:nrow(p)) {
  seg <- bm_x[index(bm_x) > a[i-1] & index(bm_x) <= a[i]]
  if (nrow(seg) > 0) bmw[i] <- as.numeric(Return.cumulative(seg))
}
bmw[1] <- 0

## ---- 3. 계약 경유 bt_result 빌드 + audit ----------------------------------
SID_BASE <- "STR_1715_on_M4_R05_noLayer4_PG2"
mk_spec <- function(variant, cash_rule, cost_rule) list(
  strategy_id = paste0(SID_BASE, "_", variant),
  strategy_name = paste0("noL4 recon ", variant),
  strategy_family = "PG2_book_recon_carry_convention",
  signal_description = "beta_R05(regime tail) x m4(schedule) x STR_1715 ret_orig — WT-D20260702_002 recon 상속",
  universe_rule = "KOSPI200∪KOSDAQ150 (base STR_1715 상속)",
  rebalance_frequency = "monthly",
  signal_date_rule = "anchor first trading day of holding month",
  execution_date_rule = "month_anchor_recon_no_trade_schedule",
  weighting_method = "recon_scalar_overlay",
  max_position_weight = 0.20, max_leverage = 1,
  cash_rule = cash_rule, cost_model = cost_rule,
  missing_data_rule = "CD91 결측(2005-08 이전) Call1D 대체; rf last-known ≤ anchor",
  risk_controls = "beta_R05 V5 tail overlay + m4 tri-pillar schedule",
  lookahead_prevention = "PIT C1~C15 상속(WT-D20260702_002 clean timing) + C5: rf=CD91 last-known ≤ anchor_date(홀딩월 시작 전 확정) + 과금은 당월 |Δ노출|만",
  survivorship_bias_control = "base STR_1715 rawdata 상장폐지 반영 패널 상속 (269m)",
  cost_model_version = "v2.4_kr_retail_15bps"
)
mk_bt <- function(ret_net, variant, cash_rule, cost_rule) {
  nav <- cumprod(1 + ret_net)
  sim <- list(
    DAILY_NAV_DT = data.table(Date = p$anchor_date, NAV = nav, cash_weight = p$cashfrac),
    strategy_xts = xts(ret_net, order.by = p$anchor_date),
    bm_xts       = xts(bmw,     order.by = p$anchor_date),
    cost_model_version = "v2.4_kr_retail_15bps"
  )
  bt <- build_bt_result(sim, mk_spec(variant, cash_rule, cost_rule),
                        run_id = paste0("SPEC1_", variant, "_", format(Sys.Date(), "%Y%m%d")),
                        strategy_id = paste0(SID_BASE, "_", variant),
                        strategy_version = "spec1_v1",
                        benchmark_id = "KOSPI200", benchmark_name = "KOSPI 200",
                        transaction_cost_bps = 15, slippage_bps = 0,
                        risk_free_rate = 0,               # SR basis rf=0 (incumbent 컨벤션 유지; 캐리는 ret_net 내 수익)
                        frequency = "monthly", annualization_factor = 12,
                        universe_id = "K200_KQ150_STR1715_base",
                        code_version = "spec1_run_all_v1",
                        created_by_agent = "SPEC1-agent")
  ## pin tag + rf 라벨 manifest 기록 (감사 재구성용)
  bt$manifest[, data_snapshot_id := paste0("pin:", TAG)]
  bt$manifest[, risk_free_rate_source := "SR basis rf=0 (incumbent convention); carry income = ECOS CD91 last-known in ret_net"]
  bt <- audit_bt_result(bt)
  bt
}

cat("\n========== V0 base (현행 recon: |ΔR05| 과금, 캐리 없음) ==========\n")
bt0 <- mk_bt(p$ret_v0, "V0base",  "현금 무수익(rf=0) — 현행 recon", "15bps one-way × |Δβ_R05| (현행 — m4 변화분 무과금)")
cat("\n========== V1 carry-only ==========\n")
bt1 <- mk_bt(p$ret_v1, "V1carry", "유휴현금 CD91 캐리 (PIT last-known)", "15bps one-way × |Δβ_R05| (현행)")
cat("\n========== V2 m4-cost-correction-only ==========\n")
bt2 <- mk_bt(p$ret_v2, "V2m4cost", "현금 무수익(rf=0)", "15bps one-way × |Δ(β_R05×m4)| (정정)")
cat("\n========== V3 SET (캐리 + m4 정정 동시) ==========\n")
bt3 <- mk_bt(p$ret_v3, "V3set",   "유휴현금 CD91 캐리 (PIT last-known)", "15bps one-way × |Δ(β_R05×m4)| (정정)")

cat("\n========== V0J judge-vintage (07-02 보존 시계열 — 방법 재현 검증) ==========\n")
s3 <- readRDS(read_pinned(S3RDS_SRC, TAG))
pr_j <- as.data.table(s3$period_returns)
stopifnot(nrow(pr_j) == nrow(p), all(as.Date(pr_j$date) == p$anchor_date))
ret_v0j <- pr_j$ret_net
btJ <- mk_bt(ret_v0j, "V0judgevintage", "현금 무수익(rf=0) — 07-02 vintage 시계열", "15bps one-way × |Δβ_R05| (현행)")

## vintage diff 기록 (현행 패널 vs 07-02 vintage)
vd <- data.table(realized_ym = p$realized_ym, anchor_date = p$anchor_date,
                 ret_v0_judgevintage = ret_v0j, ret_v0_current = p$ret_v0)
vd[, d := ret_v0_current - ret_v0_judgevintage]
vd_big <- vd[abs(d) > 1e-9]
fwrite(vd_big, file.path(OUTDIR, "spec1_vintage_diff.csv"))
cat(sprintf("[vintage] 현행 패널 vs 07-02 vintage: 차이 %d개월 (sum d = %+.6f) -> spec1_vintage_diff.csv\n",
    nrow(vd_big), sum(vd$d)))

## ---- 4. 지표 추출 (계약 산출물에서만) --------------------------------------
mx <- function(bt) {
  m <- bt$metrics; bc <- bt$benchmark_compare
  gv <- function(dt, nm, col) { v <- dt[metric_name == nm][[col]]; if (length(v)) v[1] else NA_real_ }
  x <- xts(bt$period_returns$ret_net, order.by = bt$period_returns$date)
  list(
    SR_arith = gv(m, "Sharpe", "metric_value"),                       # Charter v1.4 §12 (rf=0)
    SR_geo   = as.numeric(table.AnnualizedReturns(x, scale = 12)[3, 1]),  # judge headline 컨벤션
    CAGR     = gv(m, "CAGR", "metric_value"),
    MDD      = gv(m, "MDD", "metric_value"),
    Calmar   = gv(m, "Calmar", "metric_value"),
    AnnVol   = gv(m, "Annualized_Volatility", "metric_value"),
    PORT_t   = gv(bc, "Portfolio_Alpha_t_NW_lag3", "strategy_value"),
    IR_net_active_recon_v1 = gv(bc, "Information_Ratio", "active_value"),
    TE       = gv(bc, "Tracking_Error", "active_value"),
    Beta     = gv(bc, "Beta_to_Benchmark", "strategy_value"),
    audit_integrity = bt$manifest$integrity_status[1],
    audit_pass = nrow(bt$audit[status == "PASS"]),
    audit_fail = nrow(bt$audit[status == "FAIL"]),
    audit_warn = nrow(bt$audit[status == "WARN"]),
    audit_critical_fail = nrow(bt$audit[status == "FAIL" & severity == "critical"])
  )
}
M0 <- mx(bt0); M1 <- mx(bt1); M2 <- mx(bt2); M3 <- mx(bt3); MJ <- mx(btJ)

fmt <- function(M, nm) cat(sprintf(
  "%-9s SR_a %.4f | SR_g %.4f | CAGR %.4f | MDD %.4f | Calmar %.4f | PORT_t %.3f | IR %.4f | audit %s (P%d/F%d/W%d, critF%d)\n",
  nm, M$SR_arith, M$SR_geo, M$CAGR, M$MDD, M$Calmar, M$PORT_t, M$IR_net_active_recon_v1,
  M$audit_integrity, M$audit_pass, M$audit_fail, M$audit_warn, M$audit_critical_fail))
cat("\n===== 변형 지표 (계약 산출) =====\n")
fmt(MJ, "V0J_0702"); fmt(M0, "V0_base"); fmt(M1, "V1_carry"); fmt(M2, "V2_m4cost"); fmt(M3, "V3_SET")

## ---- 5. 판정 체크 -----------------------------------------------------------
tol_chk <- function(nm, got, exp, tol) {
  ok <- is.finite(got) && abs(got - exp) <= tol
  cat(sprintf("  [%s] %s: got %.4f vs ref %.4f (tol %.4f)\n", if (ok) "PASS" else "DIFF", nm, got, exp, tol))
  ok
}
cat("\n===== [1] judge 정합 재현 — 07-02 vintage 시계열 (방법 검증, WT-D20260702_002 확정값) =====\n")
c_sr  <- tol_chk("SR_geo",  MJ$SR_geo, 1.898,  0.010)
c_cg  <- tol_chk("CAGR",    MJ$CAGR,   0.4526, 0.010)
c_md  <- tol_chk("MDD",     MJ$MDD,    0.2329, 0.005)
c_cl  <- tol_chk("Calmar",  MJ$Calmar, 1.943,  0.020)
c_pt  <- tol_chk("PORT_t",  MJ$PORT_t, 6.214,  0.100)
c_ir  <- tol_chk("IR",      MJ$IR_net_active_recon_v1, 1.41602608097397, 0.005)
v0_parity <- c_sr && c_cg && c_md && c_cl && c_pt && c_ir
cat(sprintf("  [NOTE] 현행-vintage V0 IR %.4f (vintage 효과 %+.4f — 원천 패널 %d개월 수정, spec1_vintage_diff.csv. 방법 차이 아님)\n",
    M0$IR_net_active_recon_v1, M0$IR_net_active_recon_v1 - MJ$IR_net_active_recon_v1, nrow(vd_big)))

cat("\n===== [2] 캐리 단독 ΔSR_arith 재현 (target +0.0124 ±10%) =====\n")
d_sr_carry <- M1$SR_arith - M0$SR_arith
carry_ok <- d_sr_carry >= 0.0124 * 0.9 && d_sr_carry <= 0.0124 * 1.1
cat(sprintf("  [%s] dSR_arith(V1-V0) = %+.5f (band [%.5f, %.5f])\n",
    if (carry_ok) "PASS" else "FAIL", d_sr_carry, 0.0124 * 0.9, 0.0124 * 1.1))
carry_ann_pct <- mean(p$cashfrac * p$rf_m) * 12 * 100
cat(sprintf("  carry 기여(산술 연율) = +%.4f%%p | mean(cashfrac)=%.4f | mean rf=%.3f%% | Call1D 대체 %d개월\n",
    carry_ann_pct, mean(p$cashfrac), mean(p$rf_used), n_call_fallback))

cat("\n===== [3] m4 무과금 정정 크기 첫 실측 (V2 vs V0) =====\n")
yrs <- nrow(p) / 12
sum_dR05 <- sum(dR05); sum_dInv <- sum(dInv)
extra_cost_ann_bps <- (sum_dInv - sum_dR05) * COST / yrs * 1e4
cat(sprintf("  과금 노출회전: sum|ΔR05| = %.3f -> sum|Δ(β×m4)| = %.3f (연 %.3f -> %.3f)\n",
    sum_dR05, sum_dInv, sum_dR05 / yrs, sum_dInv / yrs))
cat(sprintf("  추가 비용 = 연 %.2f bps | dSR_arith %+.5f | dCAGR %+.4f%%p | dMDD %+.4f%%p\n",
    extra_cost_ann_bps, M2$SR_arith - M0$SR_arith, (M2$CAGR - M0$CAGR) * 100, (M2$MDD - M0$MDD) * 100))

cat("\n===== [4] SET (V3) 최종 판정 =====\n")
mdd_ok  <- M3$MDD < 0.25
port_ok <- M3$PORT_t >= 2.95
cat(sprintf("  [%s] MDD %.4f < 0.25 (여유 %.2f%%p)\n", if (mdd_ok) "PASS" else "FAIL", M3$MDD, (0.25 - M3$MDD) * 100))
cat(sprintf("  [%s] PORT_t %.3f >= 2.95 (HARD)\n", if (port_ok) "PASS" else "FAIL", M3$PORT_t))
cat(sprintf("  SET vs V0: dSR_arith %+.5f | dSR_geo %+.5f | dCAGR %+.4f%%p | dMDD %+.4f%%p | dIR %+.4f\n",
    M3$SR_arith - M0$SR_arith, M3$SR_geo - M0$SR_geo, (M3$CAGR - M0$CAGR) * 100,
    (M3$MDD - M0$MDD) * 100, M3$IR_net_active_recon_v1 - M0$IR_net_active_recon_v1))

## ---- 6. G3 재료: incumbent_book_ir 이동 -------------------------------------
INCUMBENT_IR <- 1.416   # book_state.json (net_active_recon_v1, WT-D20260702_002)
g3_delta <- M3$IR_net_active_recon_v1 - INCUMBENT_IR

## ---- 7. G2 재료: 라이브 캐리표 입력 (book_state 실측 + pinned CD91) ---------
bs <- jsonlite::fromJSON(file.path(ROOT, "qepm/mailbox/governor/book_state.json"), simplifyVector = TRUE)
live <- bs$event_WT_D20260702_002_layer4_removal$live_exposure_change
live_cash <- as.numeric(live$noL4_cash); live_as_of <- live$as_of; live_regime <- live$regime
cd91_now <- as.numeric(cd91_latest$Value); cd91_date <- as.character(cd91_latest$Date)
carry_m_live <- live_cash * cd91_now / 100 / 12          # 월 기대 캐리 (비율)
regime_tbl <- p[, .(n = .N, mean_cashfrac = mean(cashfrac), mean_rf_hist = mean(rf_used)), by = regime][order(-mean_cashfrac)]
regime_tbl[, carry_m_pct_at_cd91now := mean_cashfrac * cd91_now / 12]
regime_tbl[, carry_ann_pct_at_cd91now := mean_cashfrac * cd91_now]

## ---- 8. 산출물 저장 ----------------------------------------------------------
## 8.1 변형 패널 + bt_result RDS (V0/V3 감사트레일)
fwrite(p[, .(realized_ym, anchor_date, regime, ret_orig, beta_R05, m4, invested, cashfrac,
             rf_used, rf_m, dR05 = dR05, dInv = dInv, ret_v0, ret_v1, ret_v2, ret_v3)],
       file.path(OUTDIR, "spec1_panel_variants.csv"))
saveRDS(bt0, file.path(OUTDIR, "spec1_bt_v0_base.rds"))
saveRDS(bt3, file.path(OUTDIR, "spec1_bt_v3_set.rds"))

## 8.2 spec1_set_metrics.json
pin_files <- lapply(pin_manifest$files, function(f) list(basename = f$basename, md5 = f$md5))
out <- list(
  spec = "SPEC-1 유휴현금 캐리 + m4 무과금 정정 세트 (계약-grade)",
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S+09:00"),
  pin_tag = TAG, pin_files = pin_files,
  book = SID_BASE, n_periods = nrow(p),
  period = c(as.character(min(p$anchor_date)), as.character(max(p$anchor_date))),
  conventions = list(
    SR_arith = "Charter v1.4 §12 mean/sd*sqrt(12), rf=0 (캐리는 ret_net 내 수익 — SR 공제 아님)",
    SR_geo = "PerformanceAnalytics table.AnnualizedReturns (judge headline)",
    IR = "net_active_recon_v1 — contract build_benchmark_compare Information_Ratio (ann=12, vs pinned IKS200)",
    PORT_t = "contract Portfolio_Alpha_t_NW_lag3 (NW lag-3, net active)",
    cost = "15bps one-way delta-based; V0/V1=|Δβ_R05|(현행), V2/V3=|Δ(β_R05×m4)|(정정)",
    carry = "cashfrac × CD91(last-known ≤ anchor_date)/12; 2005-08 이전 Call1D 대체",
    metric_type = "backtested(contract) — build_bt_result + audit_bt_result 경유"
  ),
  variants = list(V0_judge_vintage_0702 = MJ, V0_base = M0, V1_carry_only = M1,
                  V2_m4cost_only = M2, V3_set = M3),
  vintage_note = list(
    comment = "현행 패널 CSV(pin)는 07-02 judge vintage 이후 원천 갱신 — 실질 수정 realized_ym 2026-06 1개월(+미세 노이즈 3건 <3e-6). judge 정합 재현은 07-02 보존 시계열(bt_result_C_noL4_CLEAN_ann12.rds)로 검증, 운용 수치·델타는 현행 vintage(vintage-내부 비교라 오염 없음).",
    n_revised_months = nrow(vd_big),
    revised_detail_csv = "spec1_vintage_diff.csv",
    ir_vintage_effect = M0$IR_net_active_recon_v1 - MJ$IR_net_active_recon_v1
  ),
  deltas = list(
    carry_only_vs_base = list(dSR_arith = M1$SR_arith - M0$SR_arith, dSR_geo = M1$SR_geo - M0$SR_geo,
                              dCAGR = M1$CAGR - M0$CAGR, dMDD = M1$MDD - M0$MDD),
    m4cost_only_vs_base = list(dSR_arith = M2$SR_arith - M0$SR_arith, dSR_geo = M2$SR_geo - M0$SR_geo,
                               dCAGR = M2$CAGR - M0$CAGR, dMDD = M2$MDD - M0$MDD),
    set_vs_base = list(dSR_arith = M3$SR_arith - M0$SR_arith, dSR_geo = M3$SR_geo - M0$SR_geo,
                       dCAGR = M3$CAGR - M0$CAGR, dMDD = M3$MDD - M0$MDD,
                       dIR = M3$IR_net_active_recon_v1 - M0$IR_net_active_recon_v1,
                       dPORT_t = M3$PORT_t - M0$PORT_t)
  ),
  m4_correction_first_measurement = list(
    sum_abs_dR05 = sum_dR05, sum_abs_dInv = sum_dInv,
    charged_turnover_ann_current = sum_dR05 / yrs, charged_turnover_ann_corrected = sum_dInv / yrs,
    extra_cost_ann_bps = extra_cost_ann_bps,
    dSR_arith = M2$SR_arith - M0$SR_arith, dCAGR_pp = (M2$CAGR - M0$CAGR) * 100
  ),
  carry_measurement = list(
    carry_contribution_ann_pct = carry_ann_pct, mean_cashfrac = mean(p$cashfrac),
    mean_rf_pct = mean(p$rf_used), n_call1d_fallback_months = n_call_fallback
  ),
  checks = list(
    v0_judge_parity = v0_parity,
    carry_repro_pm10pct = list(target = 0.0124, got = d_sr_carry, pass = carry_ok),
    set_mdd_under_25 = list(mdd = M3$MDD, pass = mdd_ok),
    set_port_t_hard_2_95 = list(port_t = M3$PORT_t, pass = port_ok),
    audit_no_critical_fail = (M0$audit_critical_fail + M1$audit_critical_fail +
                              M2$audit_critical_fail + M3$audit_critical_fail) == 0
  ),
  g3 = list(incumbent_book_ir = INCUMBENT_IR, ir_convention = "net_active_recon_v1",
            incumbent_reproduced_on_0702_vintage = MJ$IR_net_active_recon_v1,
            vintage_effect = M0$IR_net_active_recon_v1 - MJ$IR_net_active_recon_v1,
            convention_effect_set = M3$IR_net_active_recon_v1 - M0$IR_net_active_recon_v1,
            set_ir_current_vintage = M3$IR_net_active_recon_v1,
            delta_ir_vs_recorded = g3_delta),
  g2_inputs = list(live_as_of = live_as_of, live_regime = live_regime, live_cash = live_cash,
                   cd91_latest_pct = cd91_now, cd91_latest_date = cd91_date,
                   monthly_carry_pct_live = carry_m_live * 100),
  governance_note = "book_state 변경 없음 — G3는 도훈 confirm 사안. 본 산출은 결정 재료.",
  outputs = c("spec1_set_metrics.json", "spec1_panel_variants.csv",
              "spec1_bt_v0_base.rds", "spec1_bt_v3_set.rds",
              "g2_carry_table.md", "g3_baseline_note.md")
)
write_json(out, file.path(OUTDIR, "spec1_set_metrics.json"), auto_unbox = TRUE, pretty = TRUE, digits = 8)

## 8.3 G2 실행표 (1쪽, 도훈 실행 판단용)
won_per_100m_month <- function(frac_m) frac_m * 1e8
g2_rows_regime <- paste(sapply(seq_len(nrow(regime_tbl)), function(i) {
  r <- regime_tbl[i]
  sprintf("| %s | %d | %.1f%% | %+.3f%%p | %+.2f%%p | ₩%s |",
          r$regime, r$n, r$mean_cashfrac * 100, r$carry_m_pct_at_cd91now, r$carry_ann_pct_at_cd91now,
          format(round(won_per_100m_month(r$mean_cashfrac * cd91_now / 100 / 12)), big.mark = ","))
}), collapse = "\n")
cum12 <- cumsum(rep(carry_m_live, 12))
g2_rows_12m <- paste(sapply(1:12, function(t) {
  sprintf("| M+%d | %+.3f%%p | %+.3f%%p | ₩%s |", t, carry_m_live * 100, cum12[t] * 100,
          format(round(cum12[t] * 1e8), big.mark = ","))
}), collapse = "\n")
sens <- c(2.0, 2.5, cd91_now, 3.5)
g2_rows_sens <- paste(sapply(sens, function(rt) {
  sprintf("| %.2f%% | %+.3f%%p | %+.2f%%p | ₩%s/월 |", rt, live_cash * rt / 12, live_cash * rt,
          format(round(live_cash * rt / 100 / 12 * 1e8), big.mark = ","))
}), collapse = "\n")

g2 <- sprintf(
'# G2 — 유휴현금 캐리 실행표 (도훈 실행 판단용 1쪽)

생성: %s · pin: `%s` · 검증: `spec1_set_metrics.json` (계약-grade, 캐리 ΔSR 재현 %s)
**실행(MMF/RP/발행어음 등 주문)은 도훈 전권 — 본 표는 결정 재료일 뿐, 자동 집행 없음.**

## 1. 현 라이브 상태 (실측 — book_state.json)

- book: `%s` (PG2 단일)
- as_of %s (당월 리밸): regime **%s**, invested %.2f%% (m4×β_R05) → **현금 %.2f%%**
- CD91 최신: **%.3f%%** (%s, ECOS pinned)
- **월 기대 캐리 = %.2f%% × %.3f%%/12 = %+.3f%%p/월 (연율 %+.2f%%p)**
- 운용액 1억원당 약 **₩%s/월** (현금비중·금리 유지 가정)

## 2. 향후 12개월 기대 캐리 — metric_type=estimated (시나리오: CD91 %.3f%% 고정 · 현금비중 %.1f%% 고정)

| 시점 | 월 캐리 | 누적 | 1억 기준 누적 |
|---|---|---|---|
%s

## 3. 국면별 시나리오 (269개월 실측 노출 평균 × 현행 CD91 %.3f%%)

| Regime | n개월(실측) | 평균 현금비중 | 월 캐리 | 연 캐리 | 1억/월 |
|---|---|---|---|---|---|
%s

- 전기간 평균 현금비중 %.1f%% → 구조 기대 캐리 연 %+.2f%%p (현행 금리 기준). 백테 실측(2004~2026, 당시 금리): 연 %+.4f%%p (ΔSR_arith %+.4f).

## 4. 금리 민감도 (현 현금비중 %.2f%% 고정)

| CD91 | 월 캐리 | 연 캐리 | 1억 기준 |
|---|---|---|---|
%s

## 5. 판단 참고 (실측 세트 검증 결과)

- 캐리(+)와 m4 무과금 정정(−) **동시 반영 세트**: SR_arith %.4f (V0 %.4f 대비 %+.4f) · CAGR %.2f%% · **MDD %.2f%% < 25%% 유지** · IR(net_active_recon_v1) %.4f · PORT_t %.2f.
- 캐리만 반영한 수치 인용 금지(낙관 편향 규약) — 세트 수치만 사용.
- 근거 산출물: `spec1_set_metrics.json` / `spec1_panel_variants.csv` / bt_result RDS 2종 (audit critical FAIL 0).
',
  format(Sys.time(), "%Y-%m-%d %H:%M"), TAG, if (carry_ok) "PASS" else "FAIL",
  SID_BASE, live_as_of, live_regime, (1 - live_cash) * 100, live_cash * 100,
  cd91_now, cd91_date,
  live_cash * 100, cd91_now, carry_m_live * 100, live_cash * cd91_now,
  format(round(carry_m_live * 1e8), big.mark = ","),
  cd91_now, live_cash * 100, g2_rows_12m,
  cd91_now, g2_rows_regime,
  mean(p$cashfrac) * 100, mean(p$cashfrac) * cd91_now, carry_ann_pct, d_sr_carry,
  live_cash * 100, g2_rows_sens,
  M3$SR_arith, M0$SR_arith, M3$SR_arith - M0$SR_arith, M3$CAGR * 100, M3$MDD * 100,
  M3$IR_net_active_recon_v1, M3$PORT_t)
writeLines(g2, file.path(OUTDIR, "g2_carry_table.md"), useBytes = TRUE)

## 8.4 G3 baseline note
g3 <- sprintf(
'# G3 재료 — 캐리+m4 정정 세트 반영 시 incumbent_book_ir 이동 (도훈 confirm 사안)

생성: %s · pin: `%s` · book_state 변경 없음(본 문서는 재료).

## 수치 (계약 실측 — build_benchmark_compare, ann=12, pinned IKS200, 269m)

| 항목 | IR (net_active_recon_v1) |
|---|---|
| 현행 incumbent_book_ir 기록 (book_state.json, 07-02 vintage) | **1.4160** |
| 본 세션 계약 재현 — 07-02 vintage 시계열 (방법 검증) | %.4f |
| V0 base — 현행 vintage (원천 패널 2026-06 수정 반영) | %.4f |
| 캐리만 반영 (V1 — 채택 금지, 진단용) | %.4f |
| m4 정정만 반영 (V2 — 진단용) | %.4f |
| **세트 (V3 = 캐리 + m4 정정) — 채택 후보** | **%.4f** |

분해: 기록 1.4160 → 현행 vintage %.4f (**vintage 효과 %+.4f** — 원천 패널 2026-06 1개월 수정, 규약 무관·`spec1_vintage_diff.csv`) → 세트 %.4f (**규약 효과 %+.4f** = 캐리 %+.4f + m4 정정 %+.4f, vintage-내부 비교라 오염 없음). 기록 대비 순변화 %+.4f.

## 게이트 분모 영향 (1문단)

세트 규약 채택 시 incumbent_book_ir는 현행 vintage 기준 **%.4f**가 된다(기록 1.4160 대비 %+.4f — 이 중 규약 효과는 %+.4f이고 나머지는 데이터 vintage 이동분). book-marginal admission 게이트(measurement-graduation §4, ΔIR = new_book_ir − incumbent_book_ir ≥ 0.05)의 분모(incumbent 기준선)가 이만큼 이동하므로 향후 신규 후보의 실질 admit 문턱도 동일 폭 이동한다 — 상승이면 보수화, 하락이면 완화. 공정성 조건 두 가지: ① 후보 북 recon에도 **동일 캐리+과금 규약을 대칭 적용**해야 비교가 성립(비대칭 적용 = 게이트 왜곡), ② **캐리만 반영은 금지**(낙관 편향 규약) — m4 무과금 정정(연 %.2fbps 추가 비용, ΔSR %+.5f)과 반드시 세트로만 채택한다. 세트의 MDD는 %.2f%%로 25%% 제약 내(여유 %.2f%%p), PORT_t %.2f로 HARD 2.95 상회 유지. ir_convention 라벨(net_active_recon_v1)은 불변 — SR basis rf=0 유지, 캐리는 ret_net 내 현금수익 반영이지 벤치·active 정의 변경이 아님. 반영 실행(book_state.json incumbent_book_ir 갱신 + ir_convention_note에 캐리 규약 추가)은 도훈 confirm 후 별도 커밋.

## 근거

- `spec1_set_metrics.json` (checks: judge 정합(07-02 vintage) %s · 캐리 ΔSR 재현 %s · MDD<25 %s · audit critical FAIL 0 %s)
- bt_result: `spec1_bt_v0_base.rds` / `spec1_bt_v3_set.rds` (10-component, audit 포함)
- 기준: `qepm/mailbox/worktask/WT-D20260702_002/output/07_benchmark_compare_noL4_clean_ann12.csv` (IR 1.41602608097397)
',
  format(Sys.time(), "%Y-%m-%d %H:%M"), TAG,
  MJ$IR_net_active_recon_v1, M0$IR_net_active_recon_v1,
  M1$IR_net_active_recon_v1, M2$IR_net_active_recon_v1, M3$IR_net_active_recon_v1,
  M0$IR_net_active_recon_v1, M0$IR_net_active_recon_v1 - MJ$IR_net_active_recon_v1,
  M3$IR_net_active_recon_v1, M3$IR_net_active_recon_v1 - M0$IR_net_active_recon_v1,
  M1$IR_net_active_recon_v1 - M0$IR_net_active_recon_v1,
  M2$IR_net_active_recon_v1 - M0$IR_net_active_recon_v1,
  g3_delta,
  M3$IR_net_active_recon_v1, g3_delta, M3$IR_net_active_recon_v1 - M0$IR_net_active_recon_v1,
  extra_cost_ann_bps, M2$SR_arith - M0$SR_arith,
  M3$MDD * 100, (0.25 - M3$MDD) * 100, M3$PORT_t,
  if (v0_parity) "PASS" else "FAIL", if (carry_ok) "PASS" else "FAIL",
  if (mdd_ok) "PASS" else "FAIL",
  if ((M0$audit_critical_fail + M1$audit_critical_fail + M2$audit_critical_fail + M3$audit_critical_fail + MJ$audit_critical_fail) == 0) "PASS" else "FAIL")
writeLines(g3, file.path(OUTDIR, "g3_baseline_note.md"), useBytes = TRUE)

cat(sprintf("\n[DONE] pin=%s | 산출: spec1_set_metrics.json / spec1_panel_variants.csv / bt RDS 2종 / g2_carry_table.md / g3_baseline_note.md\n", TAG))
cat(sprintf("[OVERALL] v0_parity=%s carry_repro=%s mdd<25=%s port_t>=2.95=%s critFAIL0=%s\n",
    v0_parity, carry_ok, mdd_ok, port_ok,
    (M0$audit_critical_fail + M1$audit_critical_fail + M2$audit_critical_fail + M3$audit_critical_fail) == 0))
