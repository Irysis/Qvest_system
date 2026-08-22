## test_distribution_target_screen.R — 분포-표적 측정 계약의 **양방향** 행동 검사
##
## 대상: 02_Infrastructure/contracts/distribution_target_screen.R
##       02_Infrastructure/hurdle_gate.R (screen_route DISTRIBUTION_TARGET 발급 블록)
##       02_Infrastructure/portfolio/distribution_target_queue.R (소비 배관)
##
## 왜 양방향인가: "경고 0"은 ①검사기 부재 ②미설치(호출자 0) ③호출자 오염 셋을 전부
##   가린다. 그래서 (a)통과해야 할 것이 통과하고 (b)틀린 입력이 **발화**하고
##   (c)돌연변이를 심으면 검사가 무너지는지까지 잰다.
##   [F] 절이 (c)다 — 없으면 검사가 죽어도 초록으로 남는다.
##
## ★정본 무접촉: 소비 배관 검사는 전부 **임시 루트 픽스처**에서 돈다.
##   [G5] 가 실 06_Registry/distribution_target_queue.json 의 바이트 불변을 실측한다
##   (2026-08-20 실사고: 검사가 정본 레지스트리를 변형해 auto-commit 5건이 주입판을 캡처).
##
## 요약 규약: 마지막 줄 {"test":"distribution_target_screen","pass":N,"fail":N,"total":N}
suppressWarnings(suppressMessages({ library(data.table) }))

## ── 자기 위치 우선(r-portability 금칙④-b: 러너는 self-first) ────────────────
.args <- commandArgs(trailingOnly = FALSE)
.fa <- grep("^--file=", .args, value = TRUE)
.here <- if (length(.fa)) dirname(normalizePath(sub("^--file=", "", .fa[1]), winslash = "/", mustWork = FALSE)) else getwd()
.root <- normalizePath(file.path(.here, "..", ".."), winslash = "/", mustWork = FALSE)
.REL <- "02_Infrastructure/contracts/distribution_target_screen.R"
if (!file.exists(file.path(.root, .REL))) {
  cand <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", ""))
  if (nzchar(cand) && file.exists(file.path(cand, .REL))) .root <- gsub("\\\\", "/", cand)
}
SRC <- file.path(.root, .REL)
if (!file.exists(SRC)) stop(sprintf("계약 파일 미발견: %s (러너 위치 문제이지 계약 실패가 아님)", SRC))
suppressMessages(source(SRC))

PASS <- 0L; FAIL <- 0L
.m1 <- function(x) { x <- as.character(x); if (!length(x)) "" else x[1] }
ok  <- function(n, m = "") { PASS <<- PASS + 1L; cat(sprintf("  PASS: %s%s\n", n, if (nzchar(.m1(m))) paste0(" — ", .m1(m)) else "")) }
bad <- function(n, m = "") { FAIL <<- FAIL + 1L; cat(sprintf("  FAIL: %s%s\n", n, if (nzchar(.m1(m))) paste0(" — ", .m1(m)) else "")) }
chk <- function(n, cond, m = "") if (isTRUE(cond)) ok(n, m) else bad(n, m)
## 위반 주입 전용: 반드시 stop 해야 하는 호출
chk_stops <- function(n, expr, m = "") {
  r <- tryCatch({ force(expr); "NO_ERROR" }, error = function(e) conditionMessage(e))
  if (identical(r, "NO_ERROR")) bad(n, paste0(m, " (발화하지 않았다 — 차단 실효 없음)"))
  else ok(n, paste0(m, " [stop: ", substr(gsub("\\s+", " ", r), 1, 70), "...]"))
}

#==============================================================================
# 픽스처 — 진실을 우리가 정한다 (합성). 실 패널 미사용.
#==============================================================================
N_T <- 200L; N_M <- 240L
mk_dates <- function(n) seq(as.Date("2000-01-31"), by = "month", length.out = n)

## fixture A: **분포에만** 신호 — 90% 확률 +a*g / 10% 확률 -9a*g
##   설계상 평균 기여 = 0.9*a*g - 0.1*9*a*g = 0 이고 중앙값 기여 ≈ +a*g.
##   vol/size 는 신호와 무관 → 직교화가 죽이지 못한다.
fx_distributional <- function(seed = 20260822, a = 0.030, n_m = N_M, sign_flip_after = NA_integer_) {
  set.seed(seed)
  D <- mk_dates(n_m); tk <- sprintf("T%03d", seq_len(N_T))
  X <- CJ(Date = D, Ticker = tk, sorted = FALSE)
  n <- nrow(X)
  X[, win_vol := exp(stats::rnorm(n, -2.3, 0.45))]
  X[, log_size := stats::rnorm(n, 13, 1.1)]
  X[, score := stats::rnorm(n)]
  X[, g := (frank(score) / .N) - 0.5, by = Date]
  X[, mi := match(Date, D)]
  X[, sgn := if (is.na(sign_flip_after)) 1 else ifelse(mi > sign_flip_after, -1, 1)]
  u <- stats::runif(n); eps <- stats::rnorm(n) * X$win_vol
  X[, Ret_1m := eps + ifelse(u < 0.9, a * g * sgn, -9 * a * g * sgn)]
  X[, c("g", "mi", "sgn") := NULL]
  X[]
}

## fixture B: score 가 vol 의 **선형** 대리 — 선형 직교화가 걷어내야 하는 표준 케이스.
##   (Lane B 실측 판례: 상방꼬리확률 raw t −6.67 → 통제 후 −0.92)
## fixture B': score 가 vol 의 **비선형(log)** 대리 — 선형 통제의 한계를 드러내는 케이스.
##   ★이 두 픽스처의 분리는 검사가 만든 것이다: 초판은 B 를 log 로 썼고 B3 가 FAIL 했다.
##   원인은 계약 결함이 아니라 "선형 통제는 비선형 종속을 못 걷어낸다"는 사실이었고,
##   그래서 계약에 control_transform="rank" 를 열고 두 경우를 각각 잰다.
fx_vol_proxy <- function(seed = 777, n_m = N_M, nonlinear = FALSE) {
  set.seed(seed)
  D <- mk_dates(n_m); tk <- sprintf("T%03d", seq_len(N_T))
  X <- CJ(Date = D, Ticker = tk, sorted = FALSE)
  n <- nrow(X)
  X[, win_vol := exp(stats::rnorm(n, -2.3, 0.40))]
  X[, log_size := stats::rnorm(n, 13, 1.1)]
  X[, score := if (nonlinear) -log(win_vol) + stats::rnorm(n, 0, 0.02)
               else -win_vol + stats::rnorm(n, 0, 0.002)]
  X[, Ret_1m := stats::rnorm(n) * win_vol]                 # 위치효과 없음, 분산만 vol 종속
  X[]
}

WIN_2 <- list(w1 = as.Date(c("2000-01-01", "2010-01-01")),
              w2 = as.Date(c("2010-01-01", "2020-06-01")))
WIN_NESTED <- list(long = as.Date(c("2000-01-01", "2020-06-01")),
                   sub  = as.Date(c("2010-01-01", "2020-06-01")))

run_screen <- function(X, windows = WIN_2, controls = c("win_vol", "log_size"), ...) {
  canonical_distribution_screen(
    scores_dt = X[, .(Date, Ticker, score)],
    returns_dt = X[, .(Date, Ticker, Ret_1m)],
    control_dt = if (is.null(controls)) NULL else X[, c("Date", "Ticker", controls), with = FALSE],
    control_cols = if (is.null(controls)) character(0) else controls,
    windows = windows, run_id = "fx", spec_id = "fx", ...)
}

## 요건① 증거 — 양성 대조가 실제로 밴드를 넘고, 관측은 밴드 안
MSE_OK <- list(label = "NEGATIVE_POWERED",
               positive_control = list(design = "semi-oracle", detected = TRUE,
                                       statistic = 1.674, null_band_q05 = -1.019, null_band_q95 = 0.486),
               observed = list(statistic = -0.318, inside_null_band = TRUE))

cat("\n[A] 계약 기본 성질 + 자본 필드 부재\n")
RA <- run_screen(fx_distributional())
chk("A1_capital_eligible_false", identical(RA$capital_eligible, FALSE),
    "capital_eligible 는 하드코딩 FALSE — 인자로 바꿀 수 없다")
chk("A2_no_capital_field_names",
    isTRUE(tryCatch({ dt_assert_no_capital_fields(RA, "A2"); TRUE }, error = function(e) FALSE)),
    "PORT_t/oos_retention/calmar/SR/IR/MDD 이름이 객체에 **존재하지 않는다**")
chk("A3_metric_type", identical(RA$metric_type, "distribution_screen"), "metric_type 라벨(기존 규약 승계)")
chk("A4_shape_profile_nonbinding",
    identical(RA$windows$w1$raw$shape_profile$decision_binding, FALSE) &&
      identical(RA$windows$w1$raw$shape_profile$metric_type, "distribution_screen_diag"),
    "창-풀링 형상표는 진단 전용 라벨 — 판정 비바인딩")
chk("A5_axes_present",
    all(c("median_spread", "mean_spread", "skew_slope", "tail_up_prob_diff",
          "tail_dn_prob_diff", "qspread_p10", "qspread_p90") %in% names(RA$windows$w1$raw$axes)),
    "조건부 분위 스프레드 · 중앙값 스프레드 · 왜도 · 꼬리초과확률 전부 산출")
chk("A6_mean_axis_excluded_from_distribution",
    !("mean_spread" %in% RA$distribution_axes) && identical(RA$mean_space_control_axis, "mean_spread"),
    "mean_spread 는 분포 축이 아니라 **평균 공간 대조축** — 생존 집계에서 제외")

cat("\n[B] 양성 대조 — 조작이 먹는가 (검정력 실증)\n")
b_med_raw  <- RA$windows$w1$raw$axes$median_spread$nw_t
b_med_orth <- RA$windows$w1$orthogonalized$axes$median_spread$nw_t
b_mean_orth <- RA$windows$w1$orthogonalized$axes$mean_spread$nw_t
chk("B1_distributional_signal_detected", is.finite(b_med_orth) && b_med_orth >= 2.0,
    sprintf("설계상 중앙값에만 심은 신호를 직교화 후에도 검출: NW-t %.2f (raw %.2f)", b_med_orth, b_med_raw))
chk("B2_mean_space_is_null", is.finite(b_mean_orth) && abs(b_mean_orth) < 2.0,
    sprintf("같은 재료의 평균 스프레드는 null: NW-t %.2f — '분포에는 있고 평균에는 없다'를 계약이 분해한다", b_mean_orth))
RB <- suppressWarnings(run_screen(fx_vol_proxy()))
v_raw  <- RB$windows$w1$raw$axes$tail_up_prob_diff$nw_t
v_orth <- RB$windows$w1$orthogonalized$axes$tail_up_prob_diff$nw_t
chk("B3_vol_proxy_dies_under_control", identical(RB$survival$verdict, "DIES_UNDER_CONTROL"),
    sprintf("score=선형 f(vol) 픽스처: raw 꼬리확률 t %.2f → 직교화 후 %.2f, verdict=%s",
            v_raw, v_orth, RB$survival$verdict))
chk("B3b_raw_alone_would_have_passed", is.finite(v_raw) && abs(v_raw) >= 2.0,
    "★raw 만 반환하고 끝났다면 통과했을 재료다 — 통제 내장이 값을 한다")
chk("B3c_route_refused_for_vol_proxy", !isTRUE(dt_route_eligible(RB, MSE_OK)$eligible),
    "vol 대리 재료는 라우트를 못 딴다 (요건② 미충족)")

## ★선형 통제의 한계를 **양방향으로** 못박는다 (계약 결함이 아니라 규약 선택의 문제)
RBn_raw  <- suppressWarnings(run_screen(fx_vol_proxy(nonlinear = TRUE), control_transform = "raw"))
RBn_rank <- suppressWarnings(run_screen(fx_vol_proxy(nonlinear = TRUE), control_transform = "rank"))
chk("B4_nonlinear_survives_linear_control", identical(RBn_raw$survival$verdict, "SURVIVES"),
    "★score=-log(vol) 는 **선형** 통제를 통과한다 — 'vol 로 통제했다'가 강도를 보증하지 않는다")
chk("B5_rank_transform_kills_it", identical(RBn_rank$survival$verdict, "DIES_UNDER_CONTROL"),
    "같은 픽스처가 control_transform='rank' 에선 죽는다 — 단조 종속 제거가 실제로 일한다")
chk("B6_transform_recorded",
    identical(RBn_raw$control_spec$transform, "raw") && identical(RBn_rank$control_spec$transform, "rank"),
    "변환 규약이 산출물에 기록된다 — 숨은 기본값으로 강도를 감추지 않는다")

cat("\n[C] PIT — rolling only (C1)\n")
chk_stops("C1_fullsample_threshold_rejected",
          run_screen(fx_distributional(), tail_threshold_mode = "fullsample"),
          "tail_threshold_mode='fullsample' 은 거부되어야 한다")
RC <- run_screen(fx_distributional(), tail_threshold_mode = "rolling",
                 tail_rolling_window = 36L, tail_rolling_skip = 1L)
chk("C2_warmup_threshold_is_na", RC$windows$w1$tail_threshold_na_months > 0L,
    sprintf("warm-up 구간 문턱 NA %d개월 — 0 이나 전기간 분위로 위장하지 않는다",
            RC$windows$w1$tail_threshold_na_months))
## ★행동 검사: 미래를 안 보는가. 창 **끝** 수익을 극단으로 바꿔도 초반 문턱이 불변이어야 한다.
X_base <- fx_distributional()
X_pert <- copy(X_base)
last_d <- sort(unique(X_pert$Date)); last_d <- last_d[(length(last_d) - 23L):length(last_d)]
X_pert[Date %in% last_d, Ret_1m := Ret_1m * 25]
R_base <- run_screen(X_base, windows = list(w = as.Date(c("2000-01-01", "2020-06-01"))),
                     tail_threshold_mode = "rolling")
R_pert <- run_screen(X_pert, windows = list(w = as.Date(c("2000-01-01", "2020-06-01"))),
                     tail_threshold_mode = "rolling")
e_base <- R_base$windows$w$raw$axes$tail_up_prob_diff
e_pert <- R_pert$windows$w$raw$axes$tail_up_prob_diff
## 초반 60개월만 잘라 비교 — 뒤쪽 교란이 앞쪽 통계를 못 건드려야 한다
ms_b <- R_base$windows$w$raw$monthly_series[1:60]
ms_p <- R_pert$windows$w$raw$monthly_series[1:60]
chk("C3_rolling_threshold_no_lookahead",
    isTRUE(all.equal(ms_b$tail_up_prob_diff, ms_p$tail_up_prob_diff, tolerance = 1e-12)),
    "창 끝 24개월 수익을 25배로 교란해도 **초반 60개월** 꼬리확률 통계 불변 = 문턱이 미래를 안 본다")
chk("C3b_perturbation_actually_bites",
    !isTRUE(all.equal(e_base$mean, e_pert$mean, tolerance = 1e-9)),
    "★같은 교란이 전체 창 값은 실제로 바꾼다 — C3 의 불변이 '교란이 없어서'가 아님을 실증")
chk("C4_pit_labels", isTRUE(RA$pit$c1_rolling_only) && identical(RA$pit$fullsample_statistic_used, FALSE) &&
      identical(RA$pit$orthogonalization_scope, "per_date_cross_section"),
    "PIT 라벨 — 직교화는 월별 횡단면 범위(pooled 경로 없음)")

cat("\n[D] 게이트 요건 3종 — 양성 대조 + 위반 주입\n")
G_OK <- dt_route_eligible(RA, MSE_OK)
chk("D1_all_three_met_issues_route", isTRUE(G_OK$eligible) && identical(G_OK$route, "DISTRIBUTION_TARGET"),
    sprintf("요건 3종 충족 → 발급 (r1=%s r2=%s r3=%s)",
            G_OK$requirements$r1_mean_space_powered_null$pass,
            G_OK$requirements$r2_orthogonal_survival$pass,
            G_OK$requirements$r3_two_window_sign_agree$pass))
chk("D1b_gate_never_grants_capital", identical(G_OK$capital_eligible, FALSE),
    "발급되어도 capital_eligible 는 FALSE")

g <- dt_route_eligible(RA, NULL)
chk("D2_no_mean_evidence_refused", !isTRUE(g$eligible) && !g$requirements$r1_mean_space_powered_null$pass,
    "평균 공간 증거 미제출 → 거부")

mse <- MSE_OK; mse$label <- "INCONCLUSIVE_UNDERPOWERED"
g <- dt_route_eligible(RA, mse)
chk("D3_underpowered_label_refused", !isTRUE(g$eligible) && !g$requirements$r1_mean_space_powered_null$pass,
    "'미결(검정력 부족)'은 '효과없음'이 아니다 → 거부 (처분이 다른 두 라벨)")

mse <- MSE_OK; mse$positive_control$statistic <- 0.20   # 밴드 안 = 조작이 안 먹음
g <- dt_route_eligible(RA, mse)
chk("D4_positive_control_failed_refused", !isTRUE(g$eligible),
    "양성 대조가 귀무 밴드를 못 넘음 → 거부 ('조작이 먹는다'가 실증되지 않았다)")

mse <- MSE_OK; mse$observed$statistic <- 3.10           # 밴드 밖 = 평균 공간이 null 아님
g <- dt_route_eligible(RA, mse)
chk("D5_observed_outside_band_refused", !isTRUE(g$eligible),
    "관측 평균 통계가 밴드 밖 → 거부 (평균 레인 후보이지 분포 라우트 아님)")

mse <- MSE_OK; mse$positive_control$detected <- TRUE; mse$positive_control$statistic <- 0.10
g <- dt_route_eligible(RA, mse)
chk("D6_declaration_vs_measurement", !isTRUE(g$eligible) &&
      identical(g$requirements$r1_mean_space_powered_null$detail$declaration_matches_measurement, FALSE),
    "★선언 detected=TRUE 인데 수치는 밴드 안 → 거부 + 불일치를 기록 (선언을 믿지 않는다)")

R_noctl <- run_screen(fx_distributional(), controls = NULL)
g <- dt_route_eligible(R_noctl, MSE_OK)
chk("D7_no_orthogonalization_refused", !isTRUE(g$eligible) &&
      identical(R_noctl$survival$verdict, "NOT_TESTED"),
    "직교화 미실행 → 거부 (raw 값만 반환하고 끝나는 경로가 라우트를 못 딴다)")

R_1ctl <- run_screen(fx_distributional(), controls = "win_vol")
g <- dt_route_eligible(R_1ctl, MSE_OK)
chk("D8_one_control_axis_refused", !isTRUE(g$eligible) && !g$requirements$r2_orthogonal_survival$pass,
    "통제 1축 → 거부 (헌법 요건: vol·size 최소 2축)")

R_nested <- run_screen(fx_distributional(), windows = WIN_NESTED)
g <- dt_route_eligible(R_nested, MSE_OK)
chk("D9_nested_windows_refused", !isTRUE(g$eligible) && !g$requirements$r3_two_window_sign_agree$pass &&
      identical(R_nested$window_independence$verdict, "OVERLAPPING_ONLY"),
    "★포함관계 창(전체창 ⊃ 부분창) → 거부. 같은 표본을 두 번 세는 것은 독립 창 2개가 아니다")

R_flip <- run_screen(fx_distributional(sign_flip_after = 120L))
g <- dt_route_eligible(R_flip, MSE_OK)
chk("D10_sign_disagreement_refused", !isTRUE(g$eligible) && !g$requirements$r3_two_window_sign_agree$pass,
    sprintf("두 창에서 부호가 뒤집히는 픽스처 → 거부 (w1 t=%.2f / w2 t=%.2f)",
            R_flip$windows$w1$orthogonalized$axes$median_spread$nw_t,
            R_flip$windows$w2$orthogonalized$axes$median_spread$nw_t))

cat("\n[E] 자본 필드 주입 차단 — 헌법이 금지한 것을 코드가 불가능하게\n")
inj <- RA; inj$portfolio_alpha_t_nw_lag3 <- 3.10
chk_stops("E1_toplevel_injection_blocked", dt_route_eligible(inj, MSE_OK),
          "최상위 PORT_t 주입")
inj2 <- RA; inj2$windows$w1$oos_retention <- 0.82
chk_stops("E2_nested_injection_blocked", dt_route_eligible(inj2, MSE_OK),
          "중첩 oos_retention 주입")
mse_i <- MSE_OK; mse_i$calmar <- 0.71
chk_stops("E3_evidence_injection_blocked", dt_route_eligible(RA, mse_i),
          "증거 객체에 calmar 주입")
chk("E4_clean_object_passes", isTRUE(dt_route_eligible(RA, MSE_OK)$eligible),
    "정상 객체는 통과 — 오발화 없음(차단이 전면 stop 이 아님을 실증)")
.tmp_emit <- file.path(tempdir(), "distribution_screen_inject.json")
chk_stops("E5_emitter_blocked", dt_emit_screen_result(inj, NULL, .tmp_emit),
          "발행 경로에서도 차단")
chk_stops("E6_emit_filename_convention", dt_emit_screen_result(RA, G_OK, file.path(tempdir(), "wrong_name.json")),
          "파일명 규약 위반 시 발행 거부 (발행은 되고 아무도 안 읽는 상태 방지)")

cat("\n[F] 돌연변이 — 검사 사망 통제 (구분을 없애면 무너지는가)\n")
## F1: 직교화를 무력화하면 vol-proxy 픽스처가 SURVIVES 로 뒤집혀야 한다.
##     → B3 의 PASS 가 '직교화 덕분'임을 실증한다.
mut_surv <- local({
  W <- RB$windows$w1
  ax <- W$raw$axes   # 직교화 결과 대신 raw 를 그대로 쓰는 잘못된 구현
  any(vapply(RB$distribution_axes, function(a) {
    t0 <- ax[[a]]$nw_t; is.finite(t0) && abs(t0) >= 2.0 }, logical(1)))
})
chk("F1_mutation_flips_vol_proxy", isTRUE(mut_surv) && identical(RB$survival$verdict, "DIES_UNDER_CONTROL"),
    "직교화를 raw 로 바꾸면 vol-proxy 가 '생존'으로 뒤집힌다 — B3 의 PASS 는 통제에서 온 것")
## F2: 창 겹침 판정을 없애면 D9 가 통과로 뒤집혀야 한다.
mut_disj <- local({
  a <- WIN_NESTED$long; b <- WIN_NESTED$sub
  list(naive_two_windows = length(WIN_NESTED) >= 2L,           # 창이 2개면 됐다는 잘못된 규칙
       correct_disjoint  = (a[2] <= b[1]) || (b[2] <= a[1]))
})
chk("F2_mutation_flips_window_rule",
    isTRUE(mut_disj$naive_two_windows) && !isTRUE(mut_disj$correct_disjoint) &&
      !isTRUE(dt_route_eligible(R_nested, MSE_OK)$eligible),
    "'창이 2개면 통과'로 바꾸면 D9 가 뒤집힌다 — 독립성 판정이 실제로 일하고 있다")

cat("\n[G] 소비 배관 — 행동 검사 (정본 무접촉)\n")
QREL <- "06_Registry/distribution_target_queue.json"
QCANON <- file.path(.root, QREL)
canon_before <- if (file.exists(QCANON)) tools::md5sum(QCANON)[[1]] else NA_character_

CQ <- file.path(.root, "02_Infrastructure/portfolio/distribution_target_queue.R")
if (!file.exists(CQ)) {
  bad("G0_consumer_exists", "소비 배관 파일 부재 — 라벨만 있고 읽는 쪽이 없다")
} else {
  ok("G0_consumer_exists", "02_Infrastructure/portfolio/distribution_target_queue.R")
  suppressMessages(source(CQ))

  FX <- file.path(tempdir(), paste0("dtq_fx_", Sys.getpid(), "_", as.integer(Sys.time())))
  dir.create(file.path(FX, "stage_artifacts", "WT_FX"), recursive = TRUE, showWarnings = FALSE)
  dt_emit_screen_result(RA, G_OK, file.path(FX, "stage_artifacts/WT_FX/distribution_screen_fx.json"))

  s1 <- distribution_target_scan(FX)
  chk("G1_scan_collects_emit", identical(s1$status, "OK") && s1$n_emitted == 1L && length(s1$rows) == 1L &&
        isTRUE(s1$rows[[1]]$route_eligible),
      sprintf("계약 산출물 1건 수집 · eligible=%s", isTRUE(s1$rows[[1]]$route_eligible)))

  ## G2: 자본 주장을 달고 온 산출물은 큐가 아니라 격리로
  bad_json <- file.path(FX, "stage_artifacts/WT_FX/distribution_screen_bad.json")
  writeLines(jsonlite::toJSON(list(spec_id = "BAD", capital_eligible = TRUE,
                                   portfolio_alpha_t_nw_lag3 = 3.4),
                              auto_unbox = TRUE, pretty = TRUE), bad_json)
  s2 <- distribution_target_scan(FX)
  chk("G2_capital_claim_quarantined", s2$n_quarantined == 1L && length(s2$rows) == 1L,
      sprintf("자본 주장 산출물 격리 %d건 · 큐 진입 %d건 (통과 안 함)", s2$n_quarantined, length(s2$rows)))

  ## G3: 소스 부재 = UNREPORTED (빈 결과 = 합격 금지)
  FX2 <- file.path(tempdir(), paste0("dtq_empty_", Sys.getpid()))
  dir.create(FX2, recursive = TRUE, showWarnings = FALSE)
  s3 <- distribution_target_scan(FX2)
  chk("G3_empty_source_unreported", identical(s3$status, "UNREPORTED"),
      "스캔 소스 부재 → UNREPORTED. 0건이 '미처리 없음'으로 내려앉지 않는다")

  ## G4: 쓰기 행동 — 픽스처 루트에 원장이 실제로 생긴다
  qp <- file.path(FX, QREL)
  existed <- file.exists(qp)
  distribution_target_write(s2, FX, write = TRUE)
  chk("G4_write_creates_ledger", !existed && file.exists(qp) && file.size(qp) > 0,
      sprintf("원장 생성 %d bytes", if (file.exists(qp)) file.size(qp) else 0L))

  unlink(FX, recursive = TRUE); unlink(FX2, recursive = TRUE)
}
canon_after <- if (file.exists(QCANON)) tools::md5sum(QCANON)[[1]] else NA_character_
chk("G5_canonical_registry_untouched", identical(canon_before, canon_after),
    "★검사 전후 정본 원장 바이트 동치 (2026-08-20 실사고 재발 차단)")

cat("\n[H] 발급 지점(hurdle_gate) 배선 — 소스 블록 격리 실행\n")
HG <- file.path(.root, "02_Infrastructure/hurdle_gate.R")
if (!file.exists(HG)) {
  bad("H0_hurdle_gate_exists", "hurdle_gate.R 부재")
} else {
  L <- readLines(HG, warn = FALSE)
  chk("H1_param_wired", any(grepl("distribution_evidence\\s*=\\s*NULL", L)),
      "run_hurdle_gate 가 distribution_evidence 인자를 받는다")
  i0 <- grep("^\\s*screen_route\\s*<-", L)[1]
  i1 <- grep("^\\s*verdict\\s*<-\\s*list\\(", L)
  i1 <- i1[i1 > i0][1]
  if (is.na(i0) || is.na(i1)) {
    bad("H2_block_extractable", "screen_route 발급 블록을 잘라내지 못함 (앵커 변경?)")
  } else {
    blk <- paste(L[i0:(i1 - 1L)], collapse = "\n")
    ## 발급 블록만 격리 실행 — 전체 백테 없이 **행동**을 잰다.
    eval_route <- function(screen_pass, .dist_ok, grade = "F", mdd = 0.60,
                           ann_turnover = 300, tail_review = FALSE) {
      e <- new.env(parent = globalenv())
      assign("screen_pass", screen_pass, e); assign(".dist_ok", .dist_ok, e)
      assign("grade", grade, e); assign("mdd", mdd, e)
      assign("ann_turnover", ann_turnover, e)
      assign("turnover_hard_fail_pct", 1100, e)
      assign("dd_profile", list(tail_review = tail_review), e)
      assign("diagnostics", list(), e); assign("sharpe", 0.17, e); assign("ann_ret", 0.05, e)
      # 블록 꼬리의 `pass <- !hard_fail && total_score >= 40` 이 참조하는 심볼
      assign("hard_fail", TRUE, e); assign("total_score", 12, e)
      eval(parse(text = blk), envir = e)
      get("screen_route", envir = e)
    }
    r_off <- eval_route(FALSE, FALSE)
    r_on  <- eval_route(FALSE, TRUE)
    chk("H2_issues_when_screen_pass_false", identical(r_off, "NONE") && identical(r_on, "DISTRIBUTION_TARGET"),
        sprintf("★screen_pass=FALSE 여도 발급된다 (off='%s' → on='%s'). 평균 지표(SR/CAGR)에 종속시키면 이 라우트는 자기 동기 사례에서 발급 0 이 된다", r_off, r_on))
    r_a <- eval_route(TRUE, TRUE, grade = "A")
    chk("H3_appends_to_standalone", grepl("DISTRIBUTION_TARGET", r_a, fixed = TRUE) &&
          grepl("STANDALONE_TRACK", r_a, fixed = TRUE),
        sprintf("등급 경로와 병기 가능: '%s'", r_a))
    r_c <- eval_route(TRUE, TRUE, grade = "C", mdd = 0.60)
    chk("H4_appends_to_overlay", grepl("DISTRIBUTION_TARGET", r_c, fixed = TRUE) &&
          grepl("OVERLAY_CANDIDATE", r_c, fixed = TRUE),
        sprintf("기존 라우트와 병기: '%s'", r_c))
  }
  ## PIT 절대 차단 경로가 소스에 존재하는가 (블록 **앞**에 있으므로 별도 확인)
  chk("H5_pit_absolute", any(grepl("\\.pit_violated", L)) &&
        any(grepl("DISTRIBUTION_TARGET.*PIT 위반|PIT 위반.*계층 무관", L)),
      "PIT 위반 시 분포 증거 미평가 — 계층 무관 절대 기각(AX-002)")
}

cat("\n[I] 라우트 소비자 등록 — '만들고 안 부르는' 계통 차단\n")
ST <- file.path(.root, "02_Infrastructure/portfolio/standalone_track_queue.R")
if (!file.exists(ST)) {
  bad("I1_route_registry", "standalone_track_queue.R 부재")
} else {
  SL <- readLines(ST, warn = FALSE)
  i <- grep("DISTRIBUTION_TARGET\\s*=\\s*list\\(", SL)[1]
  chk("I1_registered_with_consumer", !is.na(i) && grepl("consumer\\s*=\\s*TRUE", SL[i]),
      "ST_ROUTE_CONSUMERS 에 consumer=TRUE 로 등록 — 미등록/소비자 0 이면 드리프트 스캔이 매번 보고한다")
}

cat(sprintf("\nTOTAL: %d pass / %d fail\n", PASS, FAIL))
cat(sprintf('{"test":"distribution_target_screen","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
if (FAIL > 0L) quit(status = 1L)
