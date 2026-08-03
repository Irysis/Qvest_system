# =============================================================================
# finalize.R — WT-D20260803_007 (FQ-135) 산출물 emit
#   alpha_scores.parquet / charts / alpha_package.json / alpha_validation.json / lineage
# 실행: Rscript stage_artifacts/WT_D20260803_007/finalize.R
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
WT   <- "WT-D20260803_007"
OUT  <- file.path(ROOT, "stage_artifacts/WT_D20260803_007")
MBX  <- file.path(ROOT, "qepm/mailbox/worktask", WT)
SRC5 <- file.path(ROOT, "stage_artifacts/WT_D20260803_005")
dir.create(file.path(OUT, "charts"), recursive = TRUE, showWarnings = FALSE)
say <- function(fmt, ...) cat(sprintf(paste0("[wt007F] ", fmt, "\n"), ...))

MB <- readRDS(file.path(OUT, "memberships.rds"))
AR <- readRDS(file.path(OUT, "arm_results.rds"))
PH <- readRDS(file.path(OUT, "posthoc_results.rds"))
XP <- readRDS(file.path(OUT, "adversarial_probes.rds"))
LAB <- readRDS(file.path(SRC5, "registry_labels.rds"))
MAINP <- as.data.table(read_parquet(file.path(OUT, "composite_main.parquet"))); MAINP[, Date := as.Date(Date)]
SUM <- AR$summary; PAIRS <- AR$pairs
gv <- function(a, col) SUM[arm == a, get(col)]

# ── 1. alpha_scores.parquet ────────────────────────────────────────────────
KEEP <- c("A_REL_TOP","A_REL_BOT","A_ABS_TOP","A_PERP_TOP","SINGLE_BEST","POOL_EW")
SC <- MAINP[arm %in% KEEP]
SC[, `:=`(metric_type = "canonical_screen", task_id = WT,
          combination_rule = "z_score_aligned_equal_weight", is_primary = (arm == "A_REL_TOP"))]
write_parquet(SC, file.path(OUT, "alpha_scores.parquet"))
say("alpha_scores.parquet: %d행 / arm %d / 월 %d (%s ~ %s)", nrow(SC), uniqueN(SC$arm),
    uniqueN(SC$Date), min(SC$Date), max(SC$Date))

# ── 2. alpha_vector / confidence_vector (as-of 최신 월, primary arm) ────────
last_d <- max(MAINP[arm == "A_REL_TOP", Date])
AV <- MAINP[arm == "A_REL_TOP" & Date == last_d][order(-score)]
# alpha_vector: composite z → 월간 기대초과수익 스케일 (실현 mean_active / 상위25 평균 z 로 보정)
top25_z <- mean(head(AV$score, 25L))
scale_k <- gv("A_REL_TOP", "mean_active") / top25_z
alpha_vec <- setNames(round(AV$score * scale_k, 6), AV$Ticker)
# confidence: 횡단면 rank 안정성(직전 12개월 rank 자기상관 대용) x 멤버 커버리지
hist12 <- MAINP[arm == "A_REL_TOP" & Date > last_d - 400]
hist12[, rk := frank(-score) / .N, by = Date]
stab <- hist12[, .(sd_rk = sd(rk), n_obs = .N), by = Ticker]
stab[, conf := pmin(1, pmax(0, (1 - sd_rk / 0.35) * pmin(1, n_obs / 12)))]
CV <- merge(data.table(Ticker = names(alpha_vec)), stab[, .(Ticker, conf)], by = "Ticker", all.x = TRUE)
CV[is.na(conf), conf := 0.3]
conf_vec <- setNames(round(CV$conf, 3), CV$Ticker)
say("alpha_vector: %d 종목 (as-of %s) | 상위 5: %s", length(alpha_vec), last_d,
    paste(head(names(alpha_vec), 5), collapse = ", "))

# ── 3. 차트 ────────────────────────────────────────────────────────────────
pr <- function(a) as.data.table(AR$res_period_returns[[a]])[, .(date, active = ret_net - benchmark_ret)]
png(file.path(OUT, "charts/arm_cum_active.png"), width = 1200, height = 700, res = 110)
par(mar = c(4.2, 4.4, 3.2, 1.2))
arms_p <- c("A_REL_TOP","A_REL_BOT","SINGLE_BEST","POOL_EW","A_PERP_TOP")
cols <- c("#1f77b4","#d62728","#7f7f7f","#2ca02c","#9467bd")
CU <- lapply(arms_p, function(a) { p <- pr(a); data.table(date = p$date, cum = cumsum(p$active)) })
LV <- data.table(date = PH$period_returns$date, cum = cumsum(PH$period_returns$active))
yl <- range(c(unlist(lapply(CU, function(x) x$cum)), LV$cum))
plot(CU[[1]]$date, CU[[1]]$cum, type = "n", ylim = yl, xlab = "", ylab = "누적 초과수익 (합, cap-w 벤치 대비)",
     main = "WT-D20260803_007 — era-robust 성분 선별 arm 별 OOS 누적 초과수익 (167개월)")
abline(h = 0, col = "grey70", lty = 2)
for (i in seq_along(CU)) lines(CU[[i]]$date, CU[[i]]$cum, col = cols[i], lwd = 2)
lines(LV$date, LV$cum, col = "#ff7f0e", lwd = 2, lty = 3)
legend("topleft", bty = "n", lwd = 2, cex = 0.85,
  col = c(cols, "#ff7f0e"), lty = c(rep(1,5), 3),
  legend = c(sprintf("A_REL_TOP (era-robust 상위) PORT_t %.2f", gv("A_REL_TOP","port_t")),
             sprintf("A_REL_BOT (하위) %.2f", gv("A_REL_BOT","port_t")),
             sprintf("SINGLE_BEST (단일 최강) %.2f", gv("SINGLE_BEST","port_t")),
             sprintf("POOL_EW (무선별 285) %.2f", gv("POOL_EW","port_t")),
             sprintf("A_PERP_TOP (level-직교 robust) %.2f", gv("A_PERP_TOP","port_t")),
             sprintf("[사후] LEVEL_TOP_K20 (IS 강함 상위20) %.2f", PH$port_t)))
dev.off()

png(file.path(OUT, "charts/discriminants.png"), width = 1200, height = 620, res = 110)
par(mar = c(8.5, 4.4, 3.2, 1.2))
db <- data.table(
  lbl = c("(a) TOP−BOT", "(b) TOP−SINGLE_BEST", "[사후] TOP−LEVEL_TOP_K20",
          "K=10 (a)", "K=40 (a)", "W=24 (a)", "W=48 (a)",
          "단일분할 (a)", "위반주입 FULLSAMPLE−BOT", "위반주입 ORACLE−BOT"),
  t = c(AR$disc$a_t, AR$disc$b_t, PH$pairs[pair == "A_REL_TOP - LEVEL_TOP_K20", t_nw_lag3],
        PAIRS[pair == "A_REL_TOP_K10 - A_REL_BOT_K10", t_nw_lag3],
        PAIRS[pair == "A_REL_TOP_K40 - A_REL_BOT_K40", t_nw_lag3],
        XP$ap1[grepl("^W24_TOP - W24_BOT", pair), t_nw_lag3],
        XP$ap1[grepl("^W48_TOP - W48_BOT", pair), t_nw_lag3],
        PAIRS[pair == "SS_A_REL_TOP - SS_A_REL_BOT", t_nw_lag3],
        PAIRS[pair == "LEAK_FULLSAMPLE - A_REL_BOT", t_nw_lag3],
        PAIRS[pair == "LEAK_ORACLE_OOS - A_REL_BOT", t_nw_lag3]))
bp <- barplot(db$t, names.arg = db$lbl, las = 2, cex.names = 0.78,
  col = ifelse(seq_len(nrow(db)) >= 9, "#c9c9c9", ifelse(db$t >= 2, "#2ca02c", "#1f77b4")),
  ylim = c(min(db$t) - 0.6, max(db$t) + 0.8), ylab = "paired NW(lag=3) t",
  main = "판별식 실측 — 사전등록 문턱 t ≥ +2.0 (회색 = 위반 주입)")
abline(h = 2, col = "#d62728", lwd = 2, lty = 2); abline(h = 0, col = "grey60")
text(bp, db$t + ifelse(db$t >= 0, 0.22, -0.28), sprintf("%+.2f", db$t), cex = 0.78)
dev.off()

png(file.path(OUT, "charts/random_null.png"), width = 1150, height = 620, res = 110)
par(mar = c(4.2, 4.4, 3.2, 1.2))
h <- hist(AR$rand$port_t, breaks = 30, col = "#d9e6f2", border = "white",
  xlab = "OOS canonical PORT_t (cap-w 벤치)", ylab = "무작위 draw 수",
  main = "무작위 K=20 composite 귀무분포 200 draw 대비 arm 위치")
abline(v = mean(AR$rand$port_t), col = "grey40", lwd = 2, lty = 2)
vs <- c(A_REL_TOP = gv("A_REL_TOP","port_t"), A_REL_BOT = gv("A_REL_BOT","port_t"),
        SINGLE_BEST = gv("SINGLE_BEST","port_t"), POOL_EW = gv("POOL_EW","port_t"),
        A_PERP_TOP = gv("A_PERP_TOP","port_t"), LEVEL_TOP_K20 = PH$port_t)
cl <- c("#1f77b4","#d62728","#7f7f7f","#2ca02c","#9467bd","#ff7f0e")
for (i in seq_along(vs)) { abline(v = vs[i], col = cl[i], lwd = 2)
  text(vs[i], max(h$counts) * (1 - 0.09*i), names(vs)[i], col = cl[i], cex = 0.75, pos = 4) }
legend("topleft", bty = "n", cex = 0.8, lty = 2, lwd = 2, col = "grey40",
       legend = sprintf("무작위 평균 %.2f (cap-w 벤치 구조적 음수 드리프트)", mean(AR$rand$port_t)))
dev.off()
say("차트 3종 저장")

# ── 4. alpha_package.json ──────────────────────────────────────────────────
cf <- list(
  list(flag = "DISCRIMINANT_A_FAIL", severity = "HIGH",
       note = sprintf("(a) era-robust 상위 − 하위 OOS paired NW t = %+.3f < 사전등록 문턱 +2.0. 지표는 방향(부호 +)은 맞으나 문턱 미달.", AR$disc$a_t)),
  list(flag = "DISCRIMINANT_B_FAIL", severity = "HIGH",
       note = sprintf("(b) ★진짜 관문 — era-robust 상위 − 단일 최강 OOS paired NW t = %+.3f < +2.0. 구성이 단일 성분을 유의하게 이기지 못함.", AR$disc$b_t)),
  list(flag = "ROBUSTNESS_ADDS_NOTHING_OVER_LEVEL", severity = "HIGH",
       note = sprintf("사후 귀속: A_REL_TOP − LEVEL_TOP_K20(IS level 상위20) paired t = %+.3f (음수). level-직교 arm A_PERP_TOP standalone PORT_t = %+.3f. 두 독립 경로가 동일 결론 — 우위의 원천은 era-robustness 가 아니라 IS level.", PH$pairs[pair=="A_REL_TOP - LEVEL_TOP_K20", t_nw_lag3], gv("A_PERP_TOP","port_t"))),
  list(flag = "PERP_METRIC_DEGENERACY", severity = "MEDIUM",
       note = sprintf("level 제거 후 지표는 '조용한(inert) factor 선택기'로 퇴화 — 선택 멤버 평균 |era t| %.3f < 풀 평균 %.3f, cor(perp, era_sd) = %.2f~%.2f, family 는 defense 0.34/quality 0.20/liquidity 0.14 (WT-005 최저 지속률 family). 사전에 metric ④(분산 단독)의 실패모드로 예고했던 것이 ③-잔차화에서 실현.", XP$ap2_mabs$perp, XP$ap2_mabs$pool, min(XP$ap2$cor_perp_erasd), max(XP$ap2$cor_perp_erasd))),
  list(flag = "CAPW_BENCH_STRUCTURAL_NEGATIVE", severity = "MEDIUM",
       note = sprintf("cap-w 벤치 하 무작위 K=20 composite 귀무 평균 PORT_t = %.3f (POOL_EW %.3f, placebo %.3f) — 본 하네스의 귀무는 0 이 아니다. A_REL_TOP 0.897 은 귀무 99.0 백분위이고 EW-유니버스 basis 로는 %.3f. 단 판별식 (a)/(b) 는 paired 차라 벤치가 정확히 상쇄(AP5 잔차 %.1e) — basis 선택이 판정을 뒤집지 못함.",
            mean(AR$rand$port_t), gv("POOL_EW","port_t"), AR$placebo$port_t, gv("A_REL_TOP","ew_port_t"), max(XP$ap5$value))),
  list(flag = "POWER_LIMIT_167M", severity = "MEDIUM",
       note = sprintf("블록 부트스트랩(block=12, B=2000): (a) t 중앙값 %.2f [%.2f, %.2f], P(t>=2)=%.3f / (b) %.2f [%.2f, %.2f], P=%.3f. 167개월로는 '효과 없음'을 증명하지 못한다 — 점추정 미달과 넓은 CI 를 함께 보고. 반면 사후 귀속(TOP−LEVEL_TOP_K20)은 P(t>=2)=%.4f 로 훨씬 조밀.",
            XP$ap4$boot_median[1], XP$ap4$boot_q05[1], XP$ap4$boot_q95[1], XP$ap4$p_reach_2[1],
            XP$ap4$boot_median[2], XP$ap4$boot_q05[2], XP$ap4$boot_q95[2], XP$ap4$p_reach_2[2],
            XP$ap4$p_reach_2[3])),
  list(flag = "TURNOVER_CEILING_BREACH", severity = "MEDIUM",
       note = sprintf("A_REL_TOP 실측 회전율 %.2f/yr > Production Constraints 상한 11.0 (SINGLE_BEST %.2f, LEVEL_TOP_K20 %.2f). 현 형태로는 구현 규율 위반 — 구성 lane 이 살아났더라도 별도 관문.", gv("A_REL_TOP","turnover_annual"), gv("SINGLE_BEST","turnover_annual"), PH$turnover)),
  list(flag = "LAG1_DECAY_NOT_LEAK", severity = "LOW",
       note = sprintf("A_REL_TOP lag1 PORT_t 0.897→0.134. 누출 혐의 검사: rank IC 보존율 A_REL_TOP %.3f vs POOL_EW %.3f vs A_PERP_TOP %.3f — 하네스 수준 미래참조면 전 arm 이 붕괴해야 하나 통제군 보존. consensus/EPS-revision 편중 arm 의 신호 horizon 감쇠로 귀속.", XP$ap3[arm=="A_REL_TOP", ic_retention], XP$ap3[arm=="POOL_EW", ic_retention], XP$ap3[arm=="A_PERP_TOP", ic_retention])),
  list(flag = "IC_TO_PORT_T_WALL_REPRODUCED", severity = "LOW",
       note = sprintf("POOL_EW rank IC %.4f (t %.2f) > A_REL_TOP %.4f (t %.2f) 이나 PORT_t 는 역전(%.2f vs %.2f) — v8.3 전이 벽을 본 라운드가 독립 재현. rank-IC 는 advisory 로만 소비.", XP$ap3[arm=="POOL_EW", ic_lag0], XP$ap3[arm=="POOL_EW", t_ic_lag0], XP$ap3[arm=="A_REL_TOP", ic_lag0], XP$ap3[arm=="A_REL_TOP", t_ic_lag0], gv("POOL_EW","port_t"), gv("A_REL_TOP","port_t"))),
  list(flag = "AX001_V2_CONDITIONAL", severity = "LOW",
       note = sprintf("AX-001 v2 조건부 병기 — A_REL_TOP BM<0 월(n=%d) active 연 %+.2f%%p (t %.2f) vs BM>=0 월 %+.2f%%p. 방어 family 는 WT-005 에서 최저 지속률(0.465)이나 그 저지속은 위기 캘린더 종속(cor +0.842) — 전기간 지표로 방어형을 채점하지 않았음을 명시.",
            AR$cond[arm=="A_REL_TOP", n_bad], 100*AR$cond[arm=="A_REL_TOP", active_bad_ann], AR$cond[arm=="A_REL_TOP", t_bad], 100*AR$cond[arm=="A_REL_TOP", active_good_ann])),
  list(flag = "NOT_A_RECOMMENDATION", severity = "LOW",
       note = "alpha_vector 는 schema 필수 필드 충족을 위한 primary arm(A_REL_TOP) 최신월 실측 composite 이며 편입 권고가 아니다. verdict = 부정. gate_eligible=FALSE, capital_claim=none."))

pkg <- list(
  task_id = WT, as_of_date = "2026-08-03", forecast_horizon = "1M",
  spec_version = "ast_v1.1",
  hypothesis = list(
    statement = "era 를 사전에 맞힐 수 없다면(WT-006), era 가 바뀌어도 덜 죽는 성분을 골라 EW 로 합성하는 것이 대안이다. era-demean 후 각 era 의 최저 PORT_t(minimax)가 높은 factor 20종의 z 평균 composite 은, 그렇지 않은 집합·무작위 집합·단일 최강 성분보다 OOS 에서 낫다.",
    mechanism = list(
      agent = "펀더멘털 재평가를 늦게 반영하는 KR 기관·개인 혼합 수급 (factor 별로 오분류를 만드는 주체가 다르며, era 전환은 그 주체 구성비가 바뀌는 사건)",
      friction = "KR 공매도 제약으로 long-only 차익거래만 가능 + 유동성 하한 2e8원 + 25종목 상한 → 어떤 단일 factor 도 자기 era 밖에서는 되돌림을 막지 못한다. 이 마찰이 era 별 성과 편차를 지속시킨다.",
      path = "era 마다 죽는 factor 가 다르므로, 모든 era 에서 최저 성과가 덜 나쁜 factor 를 골라 합성하면 era 전환 시점의 낙폭이 완화되어 다음 era 진입까지 누적 초과수익이 보존된다."),
    falsification = "메커니즘이 참이면 성과 외에 부수 관측이 따라야 한다 — (i) era-demean 지표 상위 집합의 era 별 최저 PORT_t 가 하위 집합보다 OOS 에서도 높아야 하고 (ii) 그 우위가 IS level(전기간 PORT_t)로 설명되지 않는 잔차 성분(A_PERP_TOP)에도 남아야 한다. (ii)가 음수이면 '어느 era 에서도 덜 죽는다'가 아니라 '평균적으로 강했다'를 재선택한 것이므로 기전 기각.",
    regime_scope = list(
      holds_in = list("neutral", "recovery"),
      weakens_or_reverses_in = list("crisis", "mega_cap_concentration"),
      boundary_rationale = "위기 국면은 유동성 청산이 factor 서열을 일시 붕괴시켜 era 구분 자체를 무의미하게 만들고, 초대형주 집중 국면(KR 2025-26)에서는 cap-w 벤치 대비 EW top-25 의 구조적 음수 드리프트가 성분 선별의 효과를 압도한다.")),
  factors = list(list(
    factor_id = "F1_era_robust_ew_composite",
    ast = list(op = "MEAN", args = list(list(leaf = "SPECIAL_OP"))),
    escape_contract = list(
      escape_type = "SPECIAL_OP",
      op_code_path = "stage_artifacts/WT_D20260803_007/build_composites.R",
      walk_forward = TRUE,
      note = "멤버십 = walk-forward IS-only 선택자(era-demean minimax). 리프는 factor_registry factor_id 20종(step 별 가변)이며 각각 load_month_factors() Z_Score_Aligned(C13/C14/C15). 집합이 시변이므로 고정 AST 로 환원 불가 → SPECIAL_OP 로 정직 선언."),
    role = "core_signal", restatement_exposure = 0L)),
  combination_rule = "z_score_aligned_equal_weight",
  verdict = "designed",
  self_pit_check = list(
    performed = TRUE,
    leaves_checked = list(
      list(leaf = "SPECIAL_OP", availability_rule = "walk-forward: step b 멤버십은 IS_b(1..is_end) canonical net-active 만 사용, OOS 블록 수익 미투입", restatement_prone = FALSE),
      list(leaf = "factor_registry:Z_Score_Aligned(285 pool)", availability_rule = "fixed: load_month_factors(sig_date) — Usable_Date <= sig_date (C14), NEGATE/FLIP 없음 (C13), parquet 직접 load 없음 (C15)", restatement_prone = TRUE),
      list(leaf = "RAWDATA:adv_20d", availability_rule = "fixed: t-1 ADV (C10) — canonical_screen_bt liq_dt", restatement_prone = FALSE)),
    verdict = "clean",
    evidence = "위반 주입 2종 발화(LEAK_FULLSAMPLE paired t 1.212→2.092, LEAK_ORACLE_OOS→4.367) = IS-only 규율이 실구속. lag1 붕괴는 통제군(POOL_EW rank IC 보존율 0.899) 대조로 하네스 누출 아닌 신호 감쇠로 귀속."),
  alpha_vector = as.list(alpha_vec),
  confidence_vector = as.list(conf_vec),
  signal_matrix_ref = "stage_artifacts/WT_D20260803_007/alpha_scores.parquet",
  factor_specs = list(list(
    factor_family = "multi_family_composite",
    proxy = "era-demean minimax worst-era PORT_t 상위 20 factor 의 Z_Score_Aligned 등가중 평균",
    formula = "score_i = mean_{f in S_b} Z_Score_Aligned(i, f, t);  S_b = argtop20_f min_e ( t_{f,e} - mean_g t_{g,e} ), e = IS_b 내 비중첩 36개월 era",
    lag_rule = "load_month_factors(sig_date) 각 factor 고유 lag (연간 익년 3/31 · 분기 45d · 가격 t-1)",
    winsorization = "connector 내부 Z_Score_Aligned 기준",
    neutralization = "none (factor 별 registry 정의 그대로)",
    economic_rationale = "era 전환 비대칭 손실 완화 — era 마다 죽는 factor 가 다르다는 WT-005 실측(유지 전이 0.959 vs 전환 0.304)에서 도출한 minimax 구성",
    redundancy_cluster_id = "wt007_era_robust_ew",
    weight_theta = 1.0,
    references = list("Harvey-Liu-Zhu (2016)", "McLean-Pontiff (2016)", "Bai-Perron (1998)", "WT-D20260803_005 (FQ-131)", "WT-D20260803_006 (FQ-133)"))),
  diagnostics = list(
    canonical_port_t_nw_lag3 = gv("A_REL_TOP", "port_t"),
    canonical_port_t_pvalue = gv("A_REL_TOP", "p_val"),
    canonical_n_months = gv("A_REL_TOP", "n_months"),
    canonical_port_t_ew_universe_basis = gv("A_REL_TOP", "ew_port_t"),
    rank_ic = XP$ap3[arm == "A_REL_TOP", ic_lag0],
    icir = NA,
    monotonicity = NA,
    subperiod_stability = NA,
    turnover_proxy = gv("A_REL_TOP", "turnover_annual"),
    harvey_t_stat = XP$ap3[arm == "A_REL_TOP", t_ic_lag0],
    post_neutralization_ic = NA,
    net_sr = gv("A_REL_TOP", "net_sr"),
    information_ratio = gv("A_REL_TOP", "ir"),
    discriminant_a_paired_t = AR$disc$a_t,
    discriminant_b_paired_t = AR$disc$b_t,
    posthoc_robustness_increment_t = PH$pairs[pair == "A_REL_TOP - LEVEL_TOP_K20", t_nw_lag3],
    random_null_percentile = 99.0,
    metric_type = "canonical_screen"),
  alpha_discovery_count = 0L,
  selection_objective = "canonical_port_t",
  challenge_flags = cf)
write_json(pkg, file.path(MBX, "alpha_package.json"), pretty = TRUE, auto_unbox = TRUE, digits = 8, na = "null")
say("alpha_package.json 저장 (challenge_flags %d)", length(cf))

# ── 5. lineage (package write *후*) ────────────────────────────────────────
source("02_Infrastructure/worktask/lineage_utils.R")
tryCatch(record_package_lineage(task_id = WT, package_type = "alpha_package",
  method_selected = "era-demean worst-era minimax top-20 EW composite (walk-forward IS-only), 5-arm + 200 random null",
  input_file_paths = c("stage_artifacts/WT_D20260803_005/canonical_pool.rds",
                       "stage_artifacts/WT_D20260803_005/persistence_results.rds",
                       "stage_artifacts/WT_D20260803_005/pool_meta.rds",
                       ".cache/RAWDATA.parquet",
                       "stage_artifacts/WT_D20260803_007/composite_main.parquet")),
  error = function(e) say("lineage 경고: %s", conditionMessage(e)))
say("완료")
