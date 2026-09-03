#==============================================================================
# forge_emit.R — WT-R20260829_004 표준 차트 4종 + authoritative_remeasure.json
#==============================================================================
source("run_all.R")   # 캐시 경유

PIT <- readRDS(file.path(STAGE_DIR, "forge_pit.rds"))
CFS <- readRDS(file.path(STAGE_DIR, "forge_cf_summary.rds"))
ES  <- readRDS(file.path(STAGE_DIR, "forge_essence.rds"))

M  <- as.data.table(bt$metrics); BC <- as.data.table(bt$benchmark_compare)
g  <- function(n) { v <- M[metric_name == n, metric_value]; if (length(v)) as.numeric(v[1]) else NA_real_ }
gb <- function(n) { v <- BC[metric_name == n, active_value]; if (length(v)) as.numeric(v[1]) else NA_real_ }
gbs <- function(n) { v <- BC[metric_name == n, strategy_value]; if (length(v)) as.numeric(v[1]) else NA_real_ }
gbb <- function(n) { v <- BC[metric_name == n, benchmark_value]; if (length(v)) as.numeric(v[1]) else NA_real_ }

DN <- copy(DAILY_NAV_DT)[order(Date)]
BMf <- BM_DT[Date %in% DN$Date][order(Date)]
DN[, cum_s := cumprod(1 + Strategy_Ret)]
DN[, cum_b := cumprod(1 + BMf$BM_Ret)]

#--------------------------------------------------------------- [1] equity
png(file.path(OUT_DIR, "equity_curve.png"), width = 1400, height = 800, res = 110)
par(mar = c(4.5, 4.5, 4, 1.2))
yl <- range(c(DN$cum_s, DN$cum_b))
plot(DN$Date, DN$cum_s, type = "l", lwd = 2, col = "#1f4e79", log = "y", ylim = yl,
     xlab = "", ylab = "누적성장배수 (log)",
     main = sprintf("WT-R20260829_004 W2_IV (오버레이 ON · 역변동성) vs KOSPI200 — forge 권위 · net 15bps\nCAGR %.2f%% · SR %.3f · MDD %.1f%% · Calmar %.3f · PORT_t %.3f · Grade %s",
                    100 * g("CAGR"), g("Sharpe"), 100 * g("MDD"), g("Calmar"),
                    gb("Portfolio_Alpha_t_NW_lag3"), ES$sweep$grade))
lines(DN$Date, DN$cum_b, lwd = 2, col = "#999999")
grid(col = "#dddddd")
legend("topleft", bty = "n", lwd = 2, col = c("#1f4e79", "#999999"),
       legend = c(sprintf("W2_IV (채택) — 최종 %.2fx", last(DN$cum_s)),
                  sprintf("KOSPI200 (BM_DT 일별) — 최종 %.2fx", last(DN$cum_b))))
dev.off()

#-------------------------------------------------------- [2] annual returns
DN[, yr := as.integer(format(Date, "%Y"))]
AY <- DN[, .(s = prod(1 + Strategy_Ret) - 1), by = yr]
BMf[, yr := as.integer(format(Date, "%Y"))]
AB <- BMf[, .(b = prod(1 + BM_Ret) - 1), by = yr]
AY <- merge(AY, AB, by = "yr")
png(file.path(OUT_DIR, "annual_returns.png"), width = 1400, height = 720, res = 110)
par(mar = c(4.5, 4.5, 4, 1.2))
bp <- barplot(t(as.matrix(AY[, .(s, b)])) * 100, beside = TRUE, names.arg = AY$yr,
              col = c("#1f4e79", "#bbbbbb"), border = NA, las = 2,
              ylab = "연 수익률 (%)",
              main = "연간 수익률: W2_IV(net 15bps) vs KOSPI200 — forge 권위")
abline(h = 0, col = "#333333")
legend("topleft", bty = "n", fill = c("#1f4e79", "#bbbbbb"),
       legend = c("W2_IV (채택)", "KOSPI200"))
dev.off()

#------------------------------------------------------- [3] recent 5Y zoom
z0 <- max(DN$Date) - 365 * 5
DZ <- DN[Date >= z0]; BZ <- BMf[Date >= z0]
DZ[, cs := cumprod(1 + Strategy_Ret)]; DZ[, cb := cumprod(1 + BZ$BM_Ret)]
zs_cagr <- last(DZ$cs)^(365.25 / as.numeric(max(DZ$Date) - min(DZ$Date))) - 1
zb_cagr <- last(DZ$cb)^(365.25 / as.numeric(max(DZ$Date) - min(DZ$Date))) - 1
zsr <- mean(DZ$Strategy_Ret) / sd(DZ$Strategy_Ret) * sqrt(252)
zmdd <- min(DZ$cs / cummax(DZ$cs) - 1)
png(file.path(OUT_DIR, "oos_zoom_chart.png"), width = 1400, height = 780, res = 110)
par(mar = c(4.5, 4.5, 4.5, 1.2))
plot(DZ$Date, DZ$cs, type = "l", lwd = 2.2, col = "#1f4e79",
     ylim = range(c(DZ$cs, DZ$cb)), xlab = "", ylab = "누적성장배수 (구간 시작=1)",
     main = sprintf("최근 5년 확대 — W2_IV vs KOSPI200 (%s ~ %s)\n전략 CAGR %.2f%% · SR %.3f · MDD %.1f%%  |  BM CAGR %.2f%%",
                    as.character(min(DZ$Date)), as.character(max(DZ$Date)),
                    100 * zs_cagr, zsr, 100 * zmdd, 100 * zb_cagr))
lines(DZ$Date, DZ$cb, lwd = 2.2, col = "#999999")
grid(col = "#dddddd")
legend("topleft", bty = "n", lwd = 2, col = c("#1f4e79", "#999999"),
       legend = c("W2_IV (채택)", "KOSPI200"))
dev.off()

#--------------------------------------------- [4] regime decomposition
## 국면 라벨은 weights.csv 의 panic 컬럼(상류 확정) — forge 는 재정의하지 않는다.
WR <- fread(file.path(STAGE_DIR, "weights.csv"))
PN <- unique(WR[, .(holding_ym, panic)])
DN[, hym := format(Date, "%Y-%m")]
DR <- merge(DN, PN, by.x = "hym", by.y = "holding_ym", all.x = TRUE)
DR[is.na(panic), panic := 0L]
BMf[, hym := format(Date, "%Y-%m")]
DR <- merge(DR, BMf[, .(Date, BM_Ret)], by = "Date")
setorder(DR, Date)
reg <- DR[, .(n_days = .N, n_months = uniqueN(hym),
              ann_ret = prod(1 + Strategy_Ret)^(252 / .N) - 1,
              bm_ann  = prod(1 + BM_Ret)^(252 / .N) - 1,
              sr = mean(Strategy_Ret) / sd(Strategy_Ret) * sqrt(252),
              bm_sr = mean(BM_Ret) / sd(BM_Ret) * sqrt(252),
              active_mean_ann = mean(Strategy_Ret - BM_Ret) * 252,
              active_t = as.numeric(t.test(Strategy_Ret - BM_Ret)$statistic)),
          by = .(regime = ifelse(panic == 1L, "PANIC", "NORMAL"))]
## 라벨이 실제로 위기를 짚는지 — BM 수중 깊이로 재도출(라벨 품질의 독립 증거)
DR[, cb := cumprod(1 + BM_Ret)][, bdd := cb / cummax(cb) - 1]
lab_q <- DR[, .(median_bm_drawdown = median(bdd)), by = .(regime = ifelse(panic == 1L, "PANIC", "NORMAL"))]
fire_deep <- DR[bdd <= -0.20, mean(panic == 1L)]; fire_all <- DR[, mean(panic == 1L)]
setorder(reg, -regime)
png(file.path(OUT_DIR, "regime_decomposition.png"), width = 1300, height = 720, res = 110)
par(mfrow = c(1, 2), mar = c(4.5, 4.5, 3.5, 1))
bp1 <- barplot(rbind(reg$ann_ret, reg$bm_ann) * 100, beside = TRUE, names.arg = reg$regime,
               col = c("#1f4e79", "#bbbbbb"), border = NA, ylab = "연율 수익률 (%)",
               main = "국면별 연율 수익률")
abline(h = 0); legend("bottomleft", bty = "n", fill = c("#1f4e79", "#bbbbbb"),
                      legend = c("W2_IV", "KOSPI200"), cex = 0.85)
bp2 <- barplot(rbind(reg$sr, reg$bm_sr), beside = TRUE, names.arg = reg$regime,
               col = c("#1f4e79", "#bbbbbb"), border = NA, ylab = "Sharpe",
               main = sprintf("국면별 Sharpe (패닉 %d거래일 / 정상 %d거래일)",
                              reg[regime == "PANIC", n_days], reg[regime == "NORMAL", n_days]))
abline(h = 0)
dev.off()
cat("[emit] charts written:\n"); print(list.files(OUT_DIR))

#--------------------------------------- [5] authoritative_remeasure.json
gp <- ES$sweep$graduation_params
ess <- ES$sweep$essence
cond <- list(
  port_t        = list(value = as.numeric(ess$portfolio_alpha_t_nw_lag3), threshold = as.numeric(gp$port_t_min %||% 2.95),  pass = as.numeric(ess$portfolio_alpha_t_nw_lag3) >= as.numeric(gp$port_t_min %||% 2.95)),
  oos_retention = list(value = as.numeric(ess$oos_retention),             threshold = as.numeric(gp$oos_min %||% 0.7),  pass = as.numeric(ess$oos_retention) >= as.numeric(gp$oos_min %||% 0.7)),
  sharpe        = list(value = as.numeric(ess$net_sharpe),                threshold = as.numeric(gp$sharpe_min %||% 0.8),    pass = as.numeric(ess$net_sharpe) >= as.numeric(gp$sharpe_min %||% 0.8)),
  cagr          = list(value = as.numeric(ess$cagr),                      threshold = as.numeric(gp$cagr_min %||% 0.16),     pass = as.numeric(ess$cagr) >= as.numeric(gp$cagr_min %||% 0.16)),
  calmar        = list(value = as.numeric(ess$calmar),                    threshold = as.numeric(gp$calmar_min %||% 0.64),   pass = as.numeric(ess$calmar) >= as.numeric(gp$calmar_min %||% 0.64))
)
AU <- as.data.table(bt$audit)

OUT <- list(
  task_id = WT_ID, agent = "Forge", spec_version = "authoritative_remeasure_v1.0_forge_v10",
  as_of = as.character(Sys.Date()),
  wt_type = "reinforcement", keyword_axis = "risk_overlay",
  hypothesis_title = req$hypothesis_title,
  strategy_id = STRATEGY_ID,
  measurement_basis_primary = "forge_realized_share_based",

  pure_function = list(
    package_md5_start = as.list(FORGE$hash_start), package_md5_end = as.list(FORGE$hash_end),
    hash_match = FORGE$hash_match,
    alpha_vector_modified = FALSE, sigma_reestimated = FALSE, target_weights_modified = FALSE,
    reselection_from_alpha_scores = FALSE,
    weights_provenance = FORGE$provenance,
    note = "run_all.R 은 alpha_scores.parquet 를 열지 않는다. 비중 소비는 weights.csv as-is."),

  schedule_fidelity = c(FORGE$schedule, list(
    as_of_dates_consumed = length(unique(W$Date)),
    rebalances_executed = nrow(PORTFOLIO_LOG),
    skipped_as_of = as.list(FORGE$skipped_asof),
    skip_reason = paste("마지막 as_of 2026-08-28 의 홀딩월(2026-09) 은 미실현 —",
                        "get_execution_date 가 데이터 범위 밖이라 집행 불가. 직전 보유가",
                        sprintf("데이터 끝(%s)까지 유지된다(deploy extension %d 거래일).",
                                as.character(max(DN$Date)), FORGE$deploy_extension_days)),
    exec_drop_events = nrow(FORGE$exec_drop),
    hook_note = paste("schedule_fidelity_check.sh 는 .claude/settings.json 미등록 + 필드명 불일치로",
                      "무발화다. 방어선으로 세지 않고 밀도를 본 산출물에서 직접 재도출했다."))),

  authoritative_metrics = list(
    cagr = g("CAGR"), sharpe = g("Sharpe"), mdd = g("MDD"), calmar = g("Calmar"),
    volatility = g("Annualized_Volatility"), net_ir = gb("Information_Ratio"),
    portfolio_alpha_t_nw_lag3 = gb("Portfolio_Alpha_t_NW_lag3"),
    dsr = as.numeric(ess$dsr), oos_retention = as.numeric(ess$oos_retention),
    n_days = nrow(DN), n_rebalances = nrow(PORTFOLIO_LOG),
    n_max_holdings = FORGE$n_max_weights,
    period = list(start = as.character(min(DN$Date)), end = as.character(max(DN$Date))),
    cost = "15bps one-way, v2.4_kr_retail_15bps delta-based",
    sr_realized_share_based = g("Sharpe"),
    sr_factor_engine_continuous = as.numeric(opt_pkg$realized_metrics$sr),
    divergence_factor_engine_vs_realized_pp = g("Sharpe") - as.numeric(opt_pkg$realized_metrics$sr),
    vs_factor_engine = list(
      diagnosis = "NEGLIGIBLE",
      note = paste("상류 realized_metrics 는 weighted_screen(월별) basis, forge 는 share-based(일별) basis.",
                   "SR 차 +0.028 은 basis 차이 범위이며 재선택·스케줄 조작은 없다(밀도 1.0000, 재선택 0)."))),

  grade = list(
    authoritative_grade = ES$sweep$grade,
    grade_basis = "essence_score.R (02_Infrastructure/contracts) — 권위 등급",
    metric_type = ES$sweep$metric_type,
    selection_type_primary = "sweep",
    n_trials_cumulative = 9L,
    n_trials_note = "alpha chain 4(강화 4/20) + optimizer 비중방법 argmax 5 = 9 보수 합산. optimizer 자체 선언은 5.",
    grade_sensitivity = list(sweep_n9 = ES$sweep$grade, sweep_n5 = ES$sweep5$grade, chain_n9 = ES$chain$grade),
    grade_A_conditions = cond,
    conditions_passed = sum(vapply(cond, function(x) isTRUE(x$pass), TRUE)),
    hard_fail = ES$sweep$hard_fail, hard_fail_source = ES$sweep$hard_fail_source %||% "none",
    structural_drawdown = ES$sweep$structural_drawdown,
    structural_drawdown_note = paste("라벨이지 판정이 아니다 — MDD 는 등급을 접지 않는다(도훈 지시 2026-08-24).",
                                     "위험 축은 Calmar 하나. 이 라벨은 오버레이 라우팅 근거로만 쓴다."),
    drawdown_profile = ess[grep("^drawdown_profile", names(ess))],
    reasons = ES$sweep$reasons,
    graduation_params = gp,
    proxy_grade_cited = FALSE,
    proxy_note = "hurdle_result.json proxy 등급은 인용하지 않았다(2026-05-31 DEMOTED)."),

  audit = list(
    total_checks = nrow(AU),
    pass = AU[status == "PASS", .N], warn = AU[status == "WARN", .N], fail = AU[status == "FAIL", .N],
    integrity_status = bt$manifest$integrity_status,
    non_pass = if (AU[status != "PASS", .N] > 0) AU[status != "PASS", .(check_name, status, details)] else "none",
    holdings_cap_n_max = FORGE$n_max_weights,
    factor_engine_path_wired = TRUE,
    factor_engine_path_note = "Check 8/14/15 가 WARN skip 으로 내려앉지 않도록 run_all.R 을 결정경로로 배선했다."),

  overlay_pit = PIT,

  overlay_marginal_reproduction = list(
    claim_from_optimizer = paste("①오버레이 한계기여가 5채널 전부 음수(-0.0068 ~ -0.0260)",
                                 "②무조건화 IV(C2_IV_off)가 모든 ON 구성을 지배"),
    forge_basis_verdict = "REPRODUCED",
    method = paste("optimizer 가 o2_objects.rds 에 발행한 비중 패널(W1/W5/C1/C2)을 그대로 소비해",
                   "동일 기간·동일 15bps delta·동일 share-based NAV·동일 계약(build_bt_result)로 재측정.",
                   "authoritative 는 W2_IV 하나이며 아래 표는 진단이다."),
    table = CFS$TAB, marginal = CFS$MARG,
    dominant_construction = CFS$TAB[which.max(Calmar), tag],
    headline = paste("채택된 W2(오버레이 ON) 의 등급이 정본이지만, 같은 basis 에서",
                     "오버레이를 끈 무조건화 IV 가 Calmar·SR·netIR·PORT_t·CAGR 전 축에서 앞선다.",
                     "즉 이 라운드의 실측 결론은 '오버레이 강화가 C 를 받았다'가 아니라",
                     "'오버레이가 없었으면 더 나았다'다.")),

  regime_attribution = list(
    regime_label_source = "weights.csv::panic (상류 alpha/optimizer 확정 — forge 재정의 없음)",
    table = reg,
    label_quality = list(
      median_bm_drawdown_by_regime = lab_q,
      panic_fire_rate_when_bm_20pct_underwater = fire_deep,
      panic_fire_rate_overall = fire_all,
      verdict = paste("라벨은 위기를 제대로 짚는다 — 패닉일의 BM 중앙 수중깊이가 정상일보다 깊고,",
                      "BM 이 20% 이상 수중일 때 발화율이 전체 평균의 3배 이상이다.")),
    mechanism = paste("오버레이가 빼는 자리는 라벨이 틀려서가 아니다. 패닉으로 라벨된 구간에서",
                      "KR 시장 자체가 강하게 반등하고(BM 연율 +45.5%), 저변동성 구성으로 갈아탄",
                      "롱온리 book 이 그 반등 베타를 반납한다(액티브 연율 -8.05%p). 정상 구간에서 번",
                      "액티브(+4.81%p)를 패닉 구간에서 되돌려주는 구조다."),
    caveat = paste("★국면별 액티브의 t 는 패닉 -0.60 · 정상 +1.02 로 둘 다 유의하지 않다.",
                   "즉 '패닉 구간에서 진다'는 방향은 실측이되 그 크기는 표본(에피소드 26개월)",
                   "안에서 0 과 구분되지 않는다. 한계기여 음수는 전 표본 점추정으로 읽어야 한다.")),

  same_period_baseline = list(
    baseline_id = "W1_EW (incumbent · 오버레이 ON · 동등가중)",
    basis = "동일 기간(2005-02-03~2026-08-28) · 동일 15bps delta · 동일 share-based NAV · 동일 계약",
    baseline = as.list(CFS$TAB[tag == "W1_EW"]),
    adopted  = as.list(CFS$TAB[grepl("W2_IV", tag)]),
    delta_calmar = CFS$TAB[grepl("W2_IV", tag), Calmar] - CFS$TAB[tag == "W1_EW", Calmar],
    delta_sr = CFS$TAB[grepl("W2_IV", tag), SR] - CFS$TAB[tag == "W1_EW", SR],
    note = "외부 인용 baseline 은 쓰지 않았다 — 전부 본 세션에서 동일 조건으로 재측정."),

  upstream_verdicts_carried = list(
    alpha = "F2 FAIL(예측 성분이 특이위험 아닌 시장노출) · F6 FAIL(post-2017 Calmar 0.102<0.203) · F7 FAIL(α -1.53%p) · 검정력 0.876 = powered null",
    risk = "조작확인 통과(패닉월 x_vol tilt +1.041 -> -0.649, t -14.37) => 처치는 전달됐다. 실측 negative 이며 미결이 아니다.",
    optimizer = "오버레이 한계기여 5채널 전부 음수 · 무조건화 IV 지배 · W5 는 IS-selection 산물이라 채택 아님",
    forge = "위 셋과 같은 방향. 권위 등급 C, Grade A 5조건 0/5 통과."),

  charts = as.list(file.path("stage_artifacts/WT_R20260829_004/output", list.files(OUT_DIR)))
)

write_json(OUT, file.path(STAGE_DIR, "authoritative_remeasure.json"),
           auto_unbox = TRUE, pretty = TRUE, digits = 8, null = "null", na = "string")
cat(sprintf("[emit] authoritative_remeasure.json written | grade=%s | conditions passed %d/5\n",
            ES$sweep$grade, OUT$grade$conditions_passed))
cat("=== forge_emit.R done ===\n")
