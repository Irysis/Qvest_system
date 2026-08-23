# ============================================================================
# test_hurdle_gate.R - contract regression for run_hurdle_gate()
# Target (read-only): 02_Infrastructure/hurdle_gate.R
# Sandboxed: PROJECT_ROOT / CLAUDE_PROJECT_DIR / cwd all point to tempdir()
# so no repo file (grade_a_catalog, .cache, axioms) is read or written.
# Covered branches:
#   - verdict$screening: screen_pass TRUE -> STANDALONE_TRACK (grade A/B path),
#     screen_pass FALSE -> route NONE
#   - .drawdown_frequency_profile structural-drawdown branches (프로파일러 자체는 불변):
#     (a) single deep episode -> tail_review only
#     (b) MDD >= 70% catastrophic -> structural_hard_fail 플래그
#     (c) repeated 45%+ episodes >= 15 -> structural_hard_fail 플래그
#     (d) severe episode >= 252 days underwater -> structural_hard_fail 플래그
#   - D004 E2E (★2026-08-23 v9.1 계약 변경): catastrophic crash -> hard_fail **FALSE**,
#     `fail_reasons` 의 "Structural drawdown" 문장과 `screening$structural_dd` 는 생존.
#     MDD 는 리서치 층에서 탈락 권한이 없다(도훈 결정 E-2) — 결합 층 문제로 이관.
#   - Defense 등급 사다리 = 위기 조건부 축(stress-8 outperf + CAPM β), 양방향 + β 돌연변이 통제
#   - D001 insufficient data early return
#   - D000 PIT absolute rejection (SPEC check - see t_check_spec)
# ============================================================================

suppressPackageStartupMessages({
  library(data.table); library(xts); library(PerformanceAnalytics); library(jsonlite)
})

## 자기 위치 해석 (2026-08-08 수리) — 구판은 `--file=` 만 봤다. 헌법은 `source(...)` 를 강제하는데
## 그 경로엔 `--file=` 이 없어 NA → "Execution halted" 로만 죽었다(원인 불가시).
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
REAL_ROOT <- t_root()

SB <- t_sandbox("hurdle_gate")
dir.create(file.path(SB, "02_Infrastructure"), showWarnings = FALSE)  # no .cpp -> R fallback
dir.create(file.path(SB, "strategies"), showWarnings = FALSE)
PROJECT_ROOT <- SB
Sys.setenv(CLAUDE_PROJECT_DIR = SB)   # axiom/family lookups resolve to empty sandbox
setwd(SB)                             # relative .cache lookups stay in sandbox
INFRA_DIR <- file.path(REAL_ROOT, "02_Infrastructure")

source(file.path(REAL_ROOT, "02_Infrastructure/hurdle_gate.R"))

# ---------------------------------------------------------------------------
# Fixture builders (deterministic, no RNG)
# ---------------------------------------------------------------------------
weekday_dates <- function(n, start = as.Date("2017-01-02")) {
  d <- seq(start, by = "day", length.out = ceiling(n * 1.5) + 14)
  d <- d[!format(d, "%u") %in% c("6", "7")]
  d[seq_len(n)]
}

mk_sim <- function(r, rb, pit_shift_days = NULL) {
  n <- length(r)
  d <- weekday_dates(n)
  grp <- format(d, "%Y-%m")
  last_idx <- cumsum(rle(grp)$lengths)
  sig_i <- head(last_idx, -1L)               # last weekday of each month
  sig_dates  <- d[sig_i]
  exec_dates <- d[sig_i + 1L]                # first weekday of next month
  factor_dates <- if (is.null(pit_shift_days)) sig_dates else exec_dates + pit_shift_days
  FACTORS <- rbindlist(lapply(factor_dates, function(fd)
    data.table(Date = fd, Ticker = paste0("T", 1:30), Score = as.numeric(1:30))))
  PLOG <- data.table(Signal_Date = sig_dates, Exec_Date = exec_dates,
                     N_stocks = 20L, Turnover_Pct = 60)
  list(sim = list(strategy_xts = xts(r, d), bm_xts = xts(rb, d),
                  DAILY_NAV_DT = data.table(Date = d, NAV = cumprod(1 + r)),
                  PORTFOLIO_LOG = PLOG),
       FACTORS = FACTORS)
}

run_case <- function(name, r, rb, pit_shift_days = NULL, role_label = NULL) {
  fx <- mk_sim(r, rb, pit_shift_days = pit_shift_days)
  od <- file.path(SB, "strategies", name, "output")
  dir.create(od, recursive = TRUE, showWarnings = FALSE)
  run_hurdle_gate(fx$sim, FACTORS = fx$FACTORS, strategy_name = name,
                  output_dir = od, strict_mode = FALSE, role_label = role_label)
}

n_days <- 1560L  # ~6.2 years of weekdays

# NOTE on fixture design: run_hurdle_gate D071 calls compute_dsr() with the
# ANNUALIZED Sharpe but daily skew/kurtosis; its sr_se = sqrt(1 - skew*SR +
# (ekurt/4)*SR^2) goes NaN (unguarded "if (sr_se > 1e-08)" crash) whenever
# |skew*SR| or platykurtosis is large (e.g. SR_ann > ~1.4 with two-point
# returns). Fixtures below deliberately keep SR/skew inside the valid region;
# the fragility itself is a target-code robustness issue (reported, not fixed).

# ============================================================================
# H1: strong deterministic uptrend -> screening PASS via standalone track
#     (zig-zag carrier: CAGR ~15%, SR ~1.05, negligible drawdown)
# ============================================================================
zig   <- rep(c(1, -1), n_days / 2)
r_up  <- 0.0006 + 0.0090 * zig
rb_up <- 0.0002 + 0.0050 * zig
# ★role_label="other" 를 **명시**한다(2026-08-23). 구판은 인자를 비워 두고 내부 axis
#   휴리스틱(axis_risk 우위 → "defense")에 맡겼는데, 이 픽스처는 MDD 0.84% 라 우연히
#   defense 분기로 들어가 `mdd<=0.45` 하나로 B_DEF 를 받고 있었다. v9.1 이 defense 판정을
#   위기 조건부 축(stress-8 outperf + CAPM β)으로 옮기자 β=1.8(=0.0090/0.0050)인 이 픽스처가
#   defense 자격을 잃고 C 로 떨어져 이 단언이 깨졌다 — **테스트가 재는 대상이 흐렸던 것**이
#   드러난 것이다. H1 이 재려던 것은 "강한 신호 → STANDALONE_TRACK"(Core 사다리)이므로
#   역할을 명시해 그 축만 재고, defense 축은 아래 H7 에서 따로(양방향으로) 잰다.
res_up <- run_case("TCASE_H1", r_up, rb_up, role_label = "other")
scr_up <- res_up$verdict$screening
t_check("hurdle:H1_screening_fields_present",
        is.list(scr_up) && is.logical(scr_up$screen_pass) &&
        is.character(scr_up$screen_route) && nzchar(scr_up$note))
t_check("hurdle:H1_strong_signal_screen_pass",
        isTRUE(scr_up$screen_pass) &&
        identical(scr_up$screen_route, "STANDALONE_TRACK") &&
        res_up$grade %in% c("A", "A_NOVEL", "A_DEF", "B", "B_DEF"))
# v9.1 S2a: 라우팅은 등급에서 분리됐다. 낙폭이 작은 이 케이스는 OVERLAY_CANDIDATE 를
#   받으면 안 된다 — 병기 로직이 "항상 붙이기"로 퇴화하면 overlay 큐가 전건으로 오염된다.
t_check("hurdle:H1_low_dd_no_overlay_label",
        !grepl("OVERLAY_CANDIDATE", scr_up$screen_route, fixed = TRUE) &&
        identical(scr_up$structural_dd, FALSE))
t_check("hurdle:H1_not_authoritative_label",
        identical(res_up$authoritative, FALSE) &&
        identical(res_up$grade_basis, "proxy_diagnostic_18component"))

# ============================================================================
# H2: flat noise -> screening FAIL, route NONE
# ============================================================================
r_flat  <- 2e-5 * rep(c(1, -1), n_days / 2)
rb_flat <- rep(0, n_days)
res_flat <- run_case("TCASE_H2", r_flat, rb_flat)
t_check("hurdle:H2_no_signal_screen_fail_route_none",
        identical(res_flat$verdict$screening$screen_pass, FALSE) &&
        identical(res_flat$verdict$screening$screen_route, "NONE"))

# ============================================================================
# H3 E2E: catastrophic crash (zig-zag carrier + crash drift; crash segment
#         pair factor (1.004)(0.988)^165 -> dd ~73.6% >= 70%)
#
# ★[2026-08-23 v9.1 / S2b, 도훈 결정 E-2] 계약이 바뀌었다: MDD 는 리서치 층에서
#   **탈락·차단 권한이 없다**. 구판 단언(`hard_fail == TRUE`)은 이제 규범 위반이다.
#   근거: v9 lean 첫날 FMT-01(MDD>45%)이 14/14 발화 — KR 25종 롱온리에서 상수이고,
#   상수를 탈락 사유로 쓰면 게이트가 판정을 그만둔다. MDD 는 결합 층(오버레이·
#   멀티팩터 composite)에서 푸는 문제로 이관됐다.
# 이 테스트가 지금 지키는 것(더 좁고 더 날카롭다):
#   ① hard_fail 이 **안 켜진다**(탈락 권한 제거가 실제로 적용됐나)
#   ② 그런데 `fail_reasons` 의 "Structural drawdown" 문장은 **살아 있다** —
#      auto_alpha_gate · lean_verify_build · L-code · 텔레그램 4곳이 이 문자열을 읽는다.
#      권한만 없애고 증거까지 지우면 결합 층이 재료를 식별할 근거를 잃는다.
#   ③ `screening$structural_dd == TRUE` — "구조 낙폭이 있었다"와 "게이트가 막았다"를
#      구분하는 새 상태의 식별자.
# ============================================================================
r_crash <- c(rep(c(0.0088, -0.0072), 350),   # pre-crash uptrend (700d)
             rep(c(0.0040, -0.0120), 165),   # crash (330d, cum ~-73.6%)
             rep(c(0.0086, -0.0074), 265))   # recovery (530d)
res_crash <- run_case("TCASE_H3", r_crash, rb_up)
t_check("hurdle:H3_catastrophic_dd_is_not_hard_fail",
        identical(res_crash$verdict$hard_fail, FALSE) &&
        res_crash$verdict$metrics$MDD > 70)
t_check("hurdle:H3_structural_dd_evidence_survives",
        any(grepl("Structural drawdown", res_crash$verdict$fail_reasons,
                  fixed = TRUE)) &&
        identical(res_crash$verdict$screening$structural_dd, TRUE) &&
        any(vapply(res_crash$verdict$diagnostics,
                   function(x) identical(x$code, "D004"), logical(1))))
# 등급은 여전히 F 지만 사유가 다르다 — MDD 가 아니라 **점수 미달**이다(SR 음수·CAGR 음수).
t_check("hurdle:H3_pass_false",
        identical(res_crash$pass, FALSE) && identical(res_crash$grade, "F") &&
        res_crash$verdict$total_score < 15)

# ============================================================================
# H4 unit: .drawdown_frequency_profile branches (thresholds are code SOT:
#          severe 0.45 / extreme 0.55 / catastrophic 0.70 / counts 15,6 /
#          day frac 0.25 / max underwater 252d)
# ============================================================================
# (a) single ~48.8% episode -> tail_review only
r_tail <- c(rep(0.001, 300), rep(-0.0055, 130), rep(0.001, 600))
p_a <- .drawdown_frequency_profile(xts(r_tail, weekday_dates(length(r_tail))))
t_check("hurdle:H4a_single_deep_episode_tail_review_not_structural",
        isTRUE(p_a$tail_review) && identical(p_a$structural_hard_fail, FALSE) &&
        identical(p_a$severe_count, 1L) && identical(p_a$catastrophic, FALSE) &&
        p_a$mdd > 0.45 && p_a$mdd < 0.55)

# (b) catastrophic depth
p_b <- .drawdown_frequency_profile(xts(r_crash, weekday_dates(length(r_crash))))
t_check("hurdle:H4b_catastrophic_structural",
        isTRUE(p_b$catastrophic) && isTRUE(p_b$structural_hard_fail) &&
        p_b$mdd >= 0.70)

# (c) repeated severe episodes: initial drop below -45%, then 15 cycles
#     oscillating across the -45% line -> 16 distinct severe episodes >= 15
r_rep <- c(rep(-0.008, 78), rep(c(0.037, -0.0355), 15))
p_c <- .drawdown_frequency_profile(xts(r_rep, weekday_dates(length(r_rep))))
nav_c <- cumprod(1 + r_rep); dd_c <- nav_c / cummax(nav_c) - 1
exp_episodes <- sum(rle(dd_c <= -0.45)$values)   # independent episode count
t_check("hurdle:H4c_repeated_severe_episodes_structural",
        identical(p_c$severe_count, as.integer(exp_episodes)) &&
        p_c$severe_count >= 15L && isTRUE(p_c$structural_hard_fail) &&
        identical(p_c$catastrophic, FALSE) && p_c$mdd < 0.55)

# (d) single episode but >= 252 days underwater below -45% -> structural
r_long <- c(rep(-0.008, 78), rep(0, 260), rep(0.002, 1200))
p_d <- .drawdown_frequency_profile(xts(r_long, weekday_dates(length(r_long))))
t_check("hurdle:H4d_long_underwater_structural",
        isTRUE(p_d$structural_hard_fail) && identical(p_d$catastrophic, FALSE) &&
        p_d$severe_max_days >= 252L &&
        p_d$severe_day_frac < p_d$severe_day_hard_frac)

# ============================================================================
# H7: Defense 등급 사다리 = **위기 조건부 축** (2026-08-23 v9.1 / S2b, AX-001)
#     구판은 defense 를 `mdd <= 0.35/0.45/0.55` 로 갈랐다 — AX-001("방어형을 전기간
#     SR/CAGR/MDD 로 기각하지 말 것")과 정면 충돌이고, 실제로는 낙폭만 작으면 시장
#     β 1.8 짜리 고베타 전략도 B_DEF 를 받았다(구 H1 픽스처가 그 상태였다).
#     새 축 = ①유효 위기구간 >= 3 ②stress-8 아웃퍼폼율 ③CAPM β.
#     ★양방향으로 잰다 — 양성 대조 하나만 두면 "β 검사를 통째로 지워도" 초록이 뜬다.
# ============================================================================
zig_d   <- rep(c(1, -1), n_days / 2)
rb_def  <- 0.0002 + 0.0090 * zig_d                   # 벤치: 일 변동 0.90%
r_lowb  <- 0.00023 + 0.0036 * zig_d                  # β = 0.0036/0.0090 = 0.40, SR_ann ~1.0
res_def_ok <- run_case("TCASE_H7a", r_lowb, rb_def, role_label = "defense")
dm_ok <- res_def_ok$verdict$defense_metrics
t_check("hurdle:H7a_low_beta_crisis_outperf_gets_defense_grade",
        res_def_ok$grade %in% c("A_DEF", "B_DEF") &&
        dm_ok$stress_8_n_total >= 3L &&
        dm_ok$stress_8_outperf_rate >= (3/8) &&
        !is.na(dm_ok$capm_beta) && dm_ok$capm_beta <= 0.95)
# ★위반 주입: 위기 아웃퍼폼은 **동일하게 좋은데** 시장 노출만 크다(β 1.8).
#   방어형의 정의는 "덜 떨어졌다"가 아니라 "시장을 덜 타면서 위기에 버텼다"이므로 탈락해야 한다.
#   이 단언이 없으면 β 조건을 삭제해도 스위트가 초록이다(돌연변이 통제).
res_def_hb <- run_case("TCASE_H7b", r_up, rb_up, role_label = "defense")
dm_hb <- res_def_hb$verdict$defense_metrics
t_check("hurdle:H7b_high_beta_denied_defense_grade",
        !is.na(dm_hb$capm_beta) && dm_hb$capm_beta > 1.05 &&
        dm_hb$stress_8_outperf_rate >= (3/8) &&
        !(res_def_hb$grade %in% c("A_DEF", "B_DEF")))
# 전기간 MDD 는 더 이상 defense 판정 축이 아니다 — H7a 는 MDD 로는 걸릴 게 없고,
#   H7b 는 MDD 0.84% 로 구판 기준(<=0.45)을 여유롭게 통과하는데도 탈락한다.
t_check("hurdle:H7b_mdd_no_longer_decides_defense",
        res_def_hb$verdict$metrics$MDD < 45)

# ============================================================================
# H5: insufficient data early return (< 60 trading days)
# ============================================================================
res_short <- run_case("TCASE_H5", rep(0.001, 40), rep(0.0005, 40))
t_check("hurdle:H5_insufficient_data_hard_fail",
        identical(res_short$pass, FALSE) && res_short$score == 0 &&
        isTRUE(res_short$verdict$hard_fail))

# ============================================================================
# H6 SPEC: PIT absolute rejection (D000). Factor signal dates are set AFTER
# their execution dates (blatant look-ahead). Per spec (pit.md /
# measurement-graduation "PIT only is absolute across tiers" + D000 comment
# "Each factor date should be < its corresponding exec date") this must
# hard-fail with a "PIT violation" reason and screen_pass FALSE.
# NOTE: the detector at hurdle_gate.R:325-331 filters exec_dates > fd and then
# tests min(matched_exec) < fd, which is unsatisfiable by construction - if
# this shows [DEFECT], the detection is dead code (target-code bug, reported
# upstream; NOT fixed by this suite).
# ============================================================================
res_pit <- run_case("TCASE_H6", r_up, rb_up, pit_shift_days = 40L)
t_check_spec("hurdle:H6_pit_violation_absolute_rejection",
             isTRUE(res_pit$verdict$hard_fail) &&
             any(grepl("PIT violation", res_pit$verdict$fail_reasons,
                       fixed = TRUE)) &&
             identical(res_pit$verdict$screening$screen_pass, FALSE),
             note = paste("D000 PIT detector never fires:",
                          "exec_dates[exec_dates > fd] then min(.) < fd is",
                          "always FALSE -> look-ahead signals pass the gate"))

t_summary("test_hurdle_gate")
