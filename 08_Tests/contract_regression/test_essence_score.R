# ============================================================================
# test_essence_score.R - contract regression for essence_score()
# Target (read-only): 02_Infrastructure/contracts/essence_score.R
# Covered branches:
#   - oos_stat_version v2 (anchored 3-split {55/65/75} median) vs v1 (single 65)
#     with a mathematically exact fixture (periodic block series, period 3
#     divides every cut point -> retention has a closed-form value)
#   - selection_type sweep / chain / NULL-legacy DSR gate application
#   - HARD boundaries: PORT_t 2.95, Calmar 0.64, oos_retention 0.7 (both sides)
#   - oos band [0.5, 0.7) escalation 2/3 evidence, <0.5 unconditional FAIL
#   - grade F (non-positive alpha), uncertain (contract not passed),
#     structural drawdown hard fail, tail_review non-fail
# ============================================================================

suppressPackageStartupMessages({ library(data.table) })

## 자기 위치 해석 (2026-08-08 수리) — 구판은 `--file=` 만 봤다. 헌법(R Execution Pattern)은
## 한글 경로 회피를 위해 `Rscript -e 'source(...)'` 를 강제하는데 그 경로엔 `--file=` 이 없어
## `[1]` 이 NA → "Execution halted" 로만 죽고 **원인이 안 보였다**(실측: 계약 테스트 4개 동일).
.here <- local({
  a <- grep("^--file=", commandArgs(FALSE), value = TRUE)
  if (length(a) && !is.na(a[1]) && nzchar(a[1]))
    return(dirname(normalizePath(sub("^--file=", "", a[1]), winslash = "/", mustWork = FALSE)))
  for (r in c(Sys.getenv("CLAUDE_PROJECT_DIR"), Sys.getenv("QM_ROOT")))
    if (nzchar(r) && dir.exists(file.path(r, "08_Tests", "contract_regression")))
      return(file.path(r, "08_Tests", "contract_regression"))
  if (file.exists(file.path(getwd(), "helpers.R"))) return(getwd())
  stop("자기 위치 해석 실패 — ★도구 경로 실패이지 계약 실패가 아닙니다.")
})
source(file.path(.here, "helpers.R"))
ROOT <- t_root()

source(file.path(ROOT, "02_Infrastructure/contracts/essence_score.R"))

# ---------------------------------------------------------------------------
# Fixture builder: minimal contract-shaped bt_result
# ---------------------------------------------------------------------------
mk_bt <- function(active, bench = rep(0, length(active)),
                  sharpe = 0.9, cagr = 0.20, mdd = 0.20, calmar = 1.0,
                  port_t = 3.5, ir = 0.5, drop_port_t = FALSE) {
  n <- length(active)
  dates <- seq(as.Date("2020-01-01"), by = "month", length.out = n)
  M <- data.table(metric_name  = c("Sharpe", "CAGR", "MDD", "Calmar"),
                  metric_value = c(sharpe, cagr, mdd, calmar))
  bc_names <- c("Information_Ratio", "Portfolio_Alpha_t_NW_lag3")
  bc_vals  <- c(ir, port_t)
  if (drop_port_t) { bc_names <- bc_names[1]; bc_vals <- bc_vals[1] }
  BC <- data.table(metric_name = bc_names, active_value = bc_vals)
  list(metrics = M, benchmark_compare = BC,
       period_returns    = data.table(date = dates, ret_net = active + bench),
       benchmark_returns = data.table(date = dates, benchmark_ret = bench))
}

# Periodic block series (period 3, 20 blocks, n = 60). Cut points floor(60*fr)
# = {33, 39, 45} and remainders {27, 21, 15} are all divisible by 3, so every
# IS/OOS segment is a whole number of blocks: identical means, sd differs only
# by the (n-1) sample-variance denominator -> closed-form retention:
#   retention(k) = sd_is / sd_oos = sqrt( k*(n-k-1) / ((k-1)*(n-k)) )
a_block <- rep(c(0.032, -0.030, 0.001), 20)
exp_ret <- function(k, n = 60) sqrt(k * (n - k - 1) / ((k - 1) * (n - k)))
exp_splits <- vapply(c(33L, 39L, 45L), exp_ret, numeric(1))
exp_median <- stats::median(exp_splits)

# --- ES01/ES02: v2 3-split median -------------------------------------------
res_v2 <- essence_score(mk_bt(a_block))
t_check("essence:ES01_v2_splits_closed_form",
        length(res_v2$oos_retention_splits) == 3L &&
        t_near(res_v2$oos_retention_splits, round(exp_splits, 3), tol = 5e-4))
t_check("essence:ES02_v2_median_and_band_pass",
        t_near(res_v2$essence$oos_retention, round(exp_median, 3), tol = 5e-4) &&
        identical(res_v2$oos_band_status, "pass") &&
        identical(res_v2$oos_stat_version, "v2"))

# --- ES03: v1 legacy single 65/35 split --------------------------------------
res_v1 <- essence_score(mk_bt(a_block), oos_stat_version = "v1")
t_check("essence:ES03_v1_single_split",
        length(res_v1$oos_retention_splits) == 1L &&
        t_near(res_v1$oos_retention_splits, round(exp_ret(39L), 3), tol = 5e-4))

# --- ES04-ES07: selection_type DSR gate branches -----------------------------
# Block series has low annualized active IR (~0.14) -> DSR < 0.5 already at
# n_trials = 50 (sr0 ~ 0.30 per period >> sr_m ~ 0.039). Metrics injected so
# a_core passes; only the DSR gate differs across selection_type.
res_chain <- essence_score(mk_bt(a_block), n_trials_cumulative = 50,
                           selection_type = "chain")
t_check("essence:ES04_chain_gate_exempt_dsr_diagnostic",
        identical(res_chain$dsr_gate_applied, FALSE) &&
        is.finite(res_chain$essence$dsr) && res_chain$essence$dsr < 0.5 &&
        identical(res_chain$grade, "A"))

res_sweep <- essence_score(mk_bt(a_block), n_trials_cumulative = 50,
                           selection_type = "sweep")
t_check("essence:ES05_sweep_gate_blocks_A",
        identical(res_sweep$dsr_gate_applied, TRUE) &&
        identical(res_sweep$grade, "B") &&
        any(grepl("DSR<0.5(sweep)", res_sweep$reasons, fixed = TRUE)))

res_legacy <- essence_score(mk_bt(a_block), n_trials_cumulative = 50,
                            selection_type = NULL)
t_check("essence:ES06_legacy_ntrials_heuristic_sweep",
        identical(res_legacy$dsr_gate_applied, TRUE) &&
        identical(res_legacy$grade, "B"))

res_single <- essence_score(mk_bt(a_block))  # no trials, no selection_type
t_check("essence:ES07_single_trial_no_gate_dsr_na",
        identical(res_single$dsr_gate_applied, FALSE) &&
        is.na(res_single$essence$dsr) &&
        identical(res_single$grade, "A"))

# --- ES08-ES11: PORT_t 2.95 / Calmar 0.64 HARD boundaries --------------------
t_check("essence:ES08_port_t_at_2.95_passes_A",
        identical(essence_score(mk_bt(a_block, port_t = 2.95))$grade, "A"))
t_check("essence:ES09_port_t_below_2.95_drops_to_B",
        identical(essence_score(mk_bt(a_block, port_t = 2.9499))$grade, "B"))
t_check("essence:ES10_calmar_at_0.64_passes_A",
        identical(essence_score(mk_bt(a_block, calmar = 0.64))$grade, "A"))
t_check("essence:ES11_calmar_below_0.64_drops_to_B",
        identical(essence_score(mk_bt(a_block, calmar = 0.6399))$grade, "B"))

# --- ES12-ES15: oos_retention 0.7 boundary + band escalation -----------------
ev_full <- list(trailing_port_t = 1.2, placebo_p = 0.01,
                book_marginal_delta_sr = 0.08, cor_vs_book = 0.10)
res12 <- essence_score(mk_bt(a_block), oos_is_ratio_override = 0.70)
t_check("essence:ES12_oos_at_0.70_passes_A",
        identical(res12$grade, "A") && identical(res12$oos_band_status, "pass"))
res13 <- essence_score(mk_bt(a_block), oos_is_ratio_override = 0.69)
t_check("essence:ES13_band_no_evidence_fails_to_B",
        identical(res13$grade, "B") &&
        identical(res13$oos_band_status, "band_fail") &&
        any(grepl("OOS_ret", res13$reasons, fixed = TRUE)))
res14 <- essence_score(mk_bt(a_block), oos_is_ratio_override = 0.69,
                       escalation_evidence = ev_full)
t_check("essence:ES14_band_escalated_2of3_passes_A",
        identical(res14$grade, "A") &&
        identical(res14$oos_band_status, "band_escalated"))
res15 <- essence_score(mk_bt(a_block), oos_is_ratio_override = 0.49,
                       escalation_evidence = ev_full)
t_check("essence:ES15_below_band_unconditional_fail",
        identical(res15$grade, "B") && identical(res15$oos_band_status, "fail"))

# weak evidence (1/3) must not escalate
ev_weak <- list(trailing_port_t = 1.2, placebo_p = 0.50,
                book_marginal_delta_sr = -0.01, cor_vs_book = 0.10)
res15b <- essence_score(mk_bt(a_block), oos_is_ratio_override = 0.69,
                        escalation_evidence = ev_weak)
t_check("essence:ES15b_band_weak_evidence_1of3_fails",
        identical(res15b$grade, "B") &&
        identical(res15b$oos_band_status, "band_fail"))

# --- ES16: Sharpe A-core boundary --------------------------------------------
t_check("essence:ES16_sharpe_below_0.8_drops_to_B",
        identical(essence_score(mk_bt(a_block, sharpe = 0.79))$grade, "B"))

# --- ES17/ES18: F non-positive alpha / uncertain (no contract) ---------------
res17 <- essence_score(mk_bt(a_block, port_t = -0.5))
t_check("essence:ES17_nonpositive_alpha_F",
        identical(res17$grade, "F") &&
        any(grepl("non-positive alpha", res17$reasons, fixed = TRUE)))
## ★v9.21 §1-b — 등급 enum 을 A/B/C/F 4값으로 일원화했다. 계약 미경유는 **등급 미발행(NA)**
##   이고 "왜 없는지"는 metric_type='uncertain' 이 보존한다(같은 사실을 두 필드에 중복
##   기록하던 것을 하나로). 이 축은 **둘 다** 단언한다 — 등급이 NA 인 것만 보면 원인이
##   사라지고, metric_type 만 보면 등급 오염을 못 잡는다.
res18 <- essence_score(mk_bt(a_block, drop_port_t = TRUE))
t_check("essence:ES18_no_contract_grade_NA",
        is.na(res18$grade) &&
        identical(res18$metric_type, "uncertain"))
## ★enum 정합 단방향 검사 — 등급이 A/B/C/F/NA 밖의 값을 내면 lcode_schema.R:57 의
##   LCODE_VALID_GRADES 가 validate_lcode 에서 적립을 통째로 막는다. 그 재발을 여기서 잡는다.
t_check("essence:ES18b_grade_enum_4values",
        is.na(res18$grade) || res18$grade %in% c("A", "B", "C", "F"))

# --- ES19: ★MDD 는 등급을 접지 않는다 (2026-08-24 도훈 지시 — 판정 방향 반전) ----
#   구 ES19 는 "catastrophic MDD >= 70% -> grade F" 를 단언했다. 그 단언이 곧
#   **MDD 탈락**이었고, 도훈 지시 "hard_fail 조건에서 MDD만 걷어내면 되는거 아냐?" 로
#   제거됐다(essence_score.R 의 drawdown 추론 삭제. hurdle_gate.R:465 가 2026-08-23 에
#   리서치 층에서 한 것과 같은 절단).
#   ★이 축은 세 가지를 한꺼번에 지킨다 — 하나만 보면 되살아난다:
#     (a) MDD 가 등급을 F 로 접지 않는다      = 지시 이행
#     (b) 구조 정보가 라벨로 **남아 있다**     = 조용한 정보 소실 방지
#     (c) 사유 문자열에도 남는다               = 하류 오버레이 라우팅 근거 보존
a_cat <- c(rep(-0.20, 6), rep(0.02, 54))   # nav trough 0.8^6 = 0.262 -> dd 73.8%
res19 <- essence_score(mk_bt(a_cat, mdd = 0.74))
t_check("essence:ES19_catastrophic_mdd_does_not_grade_F",
        !identical(res19$grade, "F") || !isTRUE(res19$hard_fail))
t_check("essence:ES19b_mdd_not_hard_fail_and_source_none",
        identical(res19$hard_fail, FALSE) &&
        identical(res19$hard_fail_source, "none"))
t_check("essence:ES19c_structural_label_survives",
        isTRUE(res19$essence$drawdown_profile$structural_hard_fail) &&
        isTRUE(res19$structural_drawdown))
t_check("essence:ES19d_structural_reason_survives_in_text",
        grepl("structural_drawdown", paste(c("", res19$reasons), collapse = ""), fixed = TRUE))
# ★돌연변이 통제 — 추론을 되살리면 이 축이 실제로 뒤집히는가.
#   되살린 판(hard_fail 주입 = 추론 결과와 동일 입력)이 F 를 내야 위 단언이 무언가를 재고 있다.
res19m <- essence_score(mk_bt(a_cat, mdd = 0.74), hard_fail = TRUE)
t_check("essence:ES19e_mutation_control_reinstated_inference_flips",
        identical(res19m$grade, "F") && identical(res19m$hard_fail_source, "injected"))

# --- ES20: single deep episode -> tail_review, NOT hard fail -----------------
a_tail <- c(rep(-0.108, 6), rep(0.04, 54)) # trough dd ~49.6%, one episode
res20 <- essence_score(mk_bt(a_tail, mdd = 0.496, calmar = 0.70),
                       oos_is_ratio_override = 0.9)
t_check("essence:ES20_tail_review_single_episode_not_hard_fail",
        identical(res20$hard_fail, FALSE) &&
        isTRUE(res20$essence$drawdown_profile$tail_review) &&
        identical(res20$grade, "A"))

# --- ES21: externally injected hard_fail wins --------------------------------
t_check("essence:ES21_injected_hard_fail_F",
        identical(essence_score(mk_bt(a_block), hard_fail = TRUE)$grade, "F"))

t_summary("test_essence_score")
