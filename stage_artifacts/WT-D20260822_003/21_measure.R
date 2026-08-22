## WT-D20260822_003 / FQ-234 NP2 — 분포-표적 계약 첫 소비 (측정)
## 사전등록: PREREG_NP2.json (창·규격) + PREREG_NP2_transform_decision.json (정본 변환)
## ★신규 계약을 만들지 않는다 — canonical_distribution_screen() 을 **호출**한다.
## ★자본 수치 산출 없음. 계약이 물리적으로 차단하며 우회 시도 없음.
suppressMessages({ library(data.table); library(arrow); library(jsonlite) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
SRC <- file.path(ROOT, "stage_artifacts/WT-D20260813_006")
OUT <- file.path(ROOT, "stage_artifacts/WT-D20260822_003")
source("02_Infrastructure/contracts/distribution_target_screen.R")

PR  <- fromJSON(file.path(OUT, "PREREG_NP2.json"), simplifyVector = FALSE)
TD  <- fromJSON(file.path(OUT, "PREREG_NP2_transform_decision.json"), simplifyVector = FALSE)
PRIMARY   <- TD$rule_application$primary_transform
COMPANION <- TD$rule_application$companion_transform
stopifnot(PRIMARY %in% c("raw", "rank"), COMPANION %in% c("raw", "rank"), PRIMARY != COMPANION)
cat("[prereg] primary transform =", PRIMARY, " companion =", COMPANION, "\n")

## ── 재료 (신규 생성 없음) ────────────────────────────────────────────────────
S <- as.data.table(read_parquet(file.path(SRC, "alpha_scores.parquet")))
S[, Date := as.Date(Date)]
fwd <- readRDS(file.path(SRC, "fwd.rds"))
RET <- as.data.table(fwd$returns_dt)[, .(Date = as.Date(Date), Ticker, Ret_1m)]
LIQ <- as.data.table(fwd$liq_dt)[, .(Date = as.Date(Date), Ticker, adv)]
setattr(LIQ, "liq_ruler", attr(fwd$liq_dt, "liq_ruler", exact = TRUE))

SCORES  <- S[is.finite(absorb_raw), .(Date, Ticker, score = absorb_raw)]
CONTROL <- S[, .(Date, Ticker, win_vol, log_size)]

WIN2 <- list(early = as.Date(c("2000-01-01", "2015-12-01")),
             late  = as.Date(c("2015-12-01", "2026-06-01")))
WIN3 <- list(w1_k200_only        = as.Date(c("2000-01-01", "2010-02-01")),
             w2_kq150_backfilled = as.Date(c("2010-02-01", "2015-12-01")),
             w3_kq150_recorded   = as.Date(c("2015-12-01", "2026-06-01")))

run <- function(windows, transform, run_id, tail_mode = "fixed") {
  canonical_distribution_screen(
    scores_dt = SCORES, returns_dt = RET,
    control_dt = CONTROL, control_cols = c("win_vol", "log_size"),
    control_transform = transform,
    n_quantiles = 5L, q_hi = 5L, q_lo = 1L,
    quantile_probs = c(0.10, 0.90),
    tail_threshold_mode = tail_mode,
    tail_fixed_up = 0.20, tail_fixed_dn = -0.20,
    tail_rolling_window = 36L, tail_rolling_prob = 0.90, tail_rolling_skip = 1L,
    winsorize_probs = c(0.01, 0.99),
    liq_dt = LIQ, liq_min = 2e8,
    windows = windows, nw_lag = 3L, t_min_survive = 2.0,
    run_id = run_id, spec_id = "FQ234_absorb_w3_corr",
    prereg_ref = "stage_artifacts/WT-D20260822_003/PREREG_NP2.json")
}

## ── 요건① 증거 (Lane B 승계 — 재산출 없음). 자본 필드명 미사용. ─────────────
MEAN_EV <- list(
  label = "NEGATIVE_POWERED",
  basis_window = "long_315m",
  source = "stage_artifacts/WT-D20260813_006/alpha_validation.json",
  positive_control = list(
    design = "semi-oracle PC1 (realized rank-IC 0.0413) vs AR(1)-matched placebo band (rho 0.8315, 200 draw)",
    detected = TRUE,
    statistic = 1.674,
    null_band_q05 = -1.019,
    null_band_q95 = 0.486),
  observed = list(statistic = -0.318, inside_null_band = TRUE),
  ceiling_note = paste0("같은 양성 대조가 창-도달가능성 상한을 드러낸다: IC 0.04 급 진짜 평균 신호가 ",
                        "이 창에서 1.674 에 그친다 ⇒ 2.95 는 원리적으로 도달 불가. 평균 '효과없음' 라벨은 ",
                        "효과 **검출** 축에만 붙고, 자본 등급 축은 '미결' 이다."))

## ── R1 PRIMARY (판정) ────────────────────────────────────────────────────────
cat("\n[R1] primary gate —", PRIMARY, "/ 2 disjoint windows\n")
r1 <- run(WIN2, PRIMARY, paste0("NP2_primary_", PRIMARY))
g1 <- dt_route_eligible(r1, MEAN_EV)
dt_emit_screen_result(r1, g1, file.path(OUT, "distribution_screen_np2_primary.json"))

## ── R2 COMPANION (비바인딩) ──────────────────────────────────────────────────
cat("[R2] companion —", COMPANION, "\n")
r2 <- run(WIN2, COMPANION, paste0("NP2_companion_", COMPANION))
g2 <- dt_route_eligible(r2, MEAN_EV)
dt_emit_screen_result(r2, g2, file.path(OUT, "distribution_screen_np2_companion.json"))

## ── R3 3창 진단 (비바인딩) ───────────────────────────────────────────────────
cat("[R3] 3-way diagnostic\n")
r3a <- run(WIN3, PRIMARY,   paste0("NP2_diag3_", PRIMARY))
r3b <- run(WIN3, COMPANION, paste0("NP2_diag3_", COMPANION))
dt_emit_screen_result(r3a, NULL, file.path(OUT, "distribution_screen_np2_diag3_primary.json"))
dt_emit_screen_result(r3b, NULL, file.path(OUT, "distribution_screen_np2_diag3_companion.json"))

## ── R4 rolling 꼬리문턱 스트레스 (비바인딩) ──────────────────────────────────
cat("[R4] rolling tail threshold stress\n")
r4 <- run(WIN2, PRIMARY, paste0("NP2_rolltail_", PRIMARY), tail_mode = "rolling")
dt_emit_screen_result(r4, NULL, file.path(OUT, "distribution_screen_np2_rolltail.json"))

## ── 요약 (판정 근거 한 곳에 모음) ────────────────────────────────────────────
ax_t <- function(res, wn, space) {
  a <- res$windows[[wn]][[space]]$axes
  if (is.null(a)) return(NULL)
  vapply(a, function(z) as.numeric(z$nw_t), numeric(1))
}
tab <- function(res, tag) {
  out <- list()
  for (wn in names(res$windows)) out[[wn]] <- list(
    window = res$windows[[wn]]$window,
    n_months = res$windows[[wn]]$n_months_raw,
    raw = as.list(ax_t(res, wn, "raw")),
    orthogonalized = as.list(ax_t(res, wn, "orthogonalized")))
  list(tag = tag, transform = res$control_spec$transform,
       tail_mode = res$tail_spec$mode,
       windows = out,
       survived_any = res$survival$survived_axes_any_window,
       survived_all = res$survival$survived_axes_all_windows,
       survival_verdict = res$survival$verdict,
       window_independence = res$window_independence$verdict,
       sign_agreement = res$sign_agreement$verdict,
       agreed_axes = res$sign_agreement$agreed_axes)
}

SUM <- list(
  wt_id = "WT-D20260822_003", fq_ref = "FQ-234 NP2",
  metric_type = "distribution_screen",
  capital_eligible = FALSE,
  capital_note = "screening tier. PORT_t/oos_retention/calmar 는 산출도 근사도 하지 않았다.",
  contract_version = DTS_CONTRACT_VERSION,
  prereg = list(spec = "PREREG_NP2.json", transform_decision = "PREREG_NP2_transform_decision.json",
                primary_transform = PRIMARY, companion_transform = COMPANION),
  liquidity_dropped = r1$liquidity$n_dropped,
  R1_primary_binding   = tab(r1, "R1_PRIMARY(binding)"),
  R2_companion         = tab(r2, "R2_COMPANION(non-binding)"),
  R3_diag3_primary     = tab(r3a, "R3_DIAG3_primary(non-binding)"),
  R3_diag3_companion   = tab(r3b, "R3_DIAG3_companion(non-binding)"),
  R4_rolltail          = tab(r4, "R4_ROLLING_TAIL(non-binding)"),
  route_gate_primary   = g1,
  route_gate_companion_non_binding = g2,
  generated_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"))

dt_assert_no_capital_fields(SUM, "NP2 summary")
write_json(SUM, file.path(OUT, "np2_summary.json"),
           auto_unbox = TRUE, pretty = TRUE, digits = NA, na = "null", null = "null")

cat("\n=== R1 PRIMARY (", PRIMARY, ") gate eligible:", g1$eligible, "===\n")
cat("  survived_any:", paste(r1$survival$survived_axes_any_window, collapse = ", "), "\n")
cat("  survived_all:", paste(r1$survival$survived_axes_all_windows, collapse = ", "), "\n")
cat("  agreed:", paste(r1$sign_agreement$agreed_axes, collapse = ", "), "\n")
if (length(g1$reasons)) cat("  reasons:\n   -", paste(g1$reasons, collapse = "\n   - "), "\n")
cat("[done]\n")
