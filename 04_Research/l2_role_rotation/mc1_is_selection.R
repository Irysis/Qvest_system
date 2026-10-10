#==============================================================================
# mc1_is_selection.R — MC1 국면 예측기 판별력 · **IS 전용** 선정 (2026-10-10 · 사전등록 규칙은 아래 RULE, 실행 전 고정)
#
# 설계 = 04_Research/01_reports/l2_role_rotation_redesign_20261010/README.md §2.2(선정 규칙) · §3(MC1)
# 순서 계약: 이 스크립트가 predictor_selection_IS.json 을 쓴 **뒤에만** mc1_oos_diagnostic.R 이 OOS 를 잰다
#   (그 스크립트는 이 파일의 존재·md5 를 확인하고, 선정을 바꾸지 않는다). 여기서는 OOS 월을 읽지도 계산하지도 않는다.
# PIT: 예측기 값 = 결정일 t(보유월 첫날 이전 마지막 한국 거래일) 의 as-of 값(Date <= t). 표적 PS 연대기는 사후(평가 전용).
# 실행: cd 04_Research/l2_role_rotation ; Rscript --no-save -e 'source("mc1_is_selection.R")'
#==============================================================================
source("lib_mc1.R")

RULE <- list(
  registered_at = "2026-10-10T20:59:09+0900",
  registered_note = "규칙·후보 목록은 IS AUC 를 한 번도 계산하기 전에 이 파일에 고정했다(후보 3개의 PIT 판정은 pit_audit.json).",
  is_window = c("2005-01", "2015-12"),
  decision_date = "보유월 m 의 첫날 이전 마지막 한국 거래일 t(.cache/benchmark.parquet 달력) — 예측기 값 = Date <= t 인 마지막 값(as-of)",
  target_direction = "ps_bear[m] — Pagan & Sossounov(2003) https://doi.org/10.1002/jae.664 · bbdetection run_dating_alg 월간 기본값(t_window 8·t_censor 6·t_phase 4·t_cycle 16·max_chng 20) = 02_Infrastructure/contracts/strategy_role.R::sr_regimes 그대로(06_Registry/strategy_role.json regimes.ps_bear). 사후 연대기 = 평가 표적 전용(입력 아님)",
  target_variance = "RV[m] = 월 m 일간 로그수익 표준편차 > IS 월(2005-01~2015-12) 2/3 분위수(type 7) = 상위 3분위",
  auc = "Mann-Whitney AUC(동률 0.5). 방향은 사전 고정: 점수가 클수록 약세/고변동 — 부호 뒤집기 없음(C13 정신)",
  bootstrap = "원형 이동 블록 부트스트랩 · 블록 12개월 · B=5000 · seed 20261010 · 모든 예측기 같은 인덱스(쌍대 비교) · 백분위 CI",
  eligibility = "pit_audit 판정 PIT-clean(또는 lag 적용판) ∧ IS 커버리지 >= 95%",
  selection = "주 예측기 = 적격 후보 중 IS 방향 AUC 점추정 최대. OOS 는 보지 않는다.",
  mc1_pass = "주 예측기의 Bonferroni 보정(K = 적격 후보 수) 양측 블록 부트스트랩 CI 하한 > 0.5 — 즉 백분위 alpha/(2K), alpha = 0.05. 미달 = MC1 FAIL(설계 §3: T 미측정)",
  info_only = "비보정 95% CI · 원형 이동 귀무 p(|이동|>=12개월) · 1위-2위 쌍대 ΔAUC CI · 1거래일 lag 강건성 · 분산 표적 AUC · 순진 참조(후보 아님)")

CANDIDATES <- list(
  JM_BearProb = list(file = ".cache/regime_jump_daily.parquet", col = "Bear_Prob", date_col = "Date",
                     model = "Statistical Jump Model (Shu-Yu-Mulvey 2024 arXiv 2402.05272 · Nystrup-Kolm-Lindström 2021) jm_causal:v1 운영 캐시",
                     provenance = "existing_cache"),
  MSM_asof_CrisisProb = list(file = "04_Research/l2_role_rotation/work/msm_asof_daily.parquet", col = "Crisis_Prob_asof", date_col = "Date",
                             model = "Calvet-Fisher MSM k=10 (msm_update.R 커널) · 모수 = 매년 말 as-of MLE (운영 캐시의 전기간 모수 C1 수리판 · 드라이버 산출)",
                             provenance = "driver_repair"),
  HMM2_asof_StressProb = list(file = "04_Research/l2_role_rotation/work/hmm2_asof_daily.parquet", col = "Stress_Prob_asof", date_col = "Date",
                              model = "2-state Gaussian HMM (Hamilton 1989 · msm_daily_refit.R 추정기·30행 refit) · 필터 확률 as-of (폴백의 평활·덮어쓰기 C1 수리판 · 드라이버 산출)",
                              provenance = "driver_repair"))
INELIGIBLE <- c("MSM_prod_CrisisProb(.cache/msm_daily_latest.parquet)", "regime_forecast_series(v1)", "regime_forecast_series_v1vix",
                "regime_forecast_series_v2", "regime_forecast_series_v3", "AE ae_regime_signal_ext", "unified_regime_signal(_daily) Category/Regime_Score")

# PIT 판정은 감사 산출물에서 읽는다(손 라벨 금지) — 감사 파일이 없거나 후보 판정이 없으면 중단
AUD_PATH <- file.path(L2DIR, "pit_audit.json")
if (!file.exists(AUD_PATH)) stop("[MC1 IS] pit_audit.json 부재 — pit_audit_compile.R 먼저")
AUD <- fromJSON(AUD_PATH, simplifyVector = FALSE)
for (nm in names(CANDIDATES)) {
  v <- AUD$candidate_verdicts[[nm]]$verdict
  if (is.null(v)) stop("[MC1 IS] pit_audit.json 에 후보 판정 없음: ", nm)
  CANDIDATES[[nm]]$pit <- v
}

t_run <- Sys.time()
bm <- load_bm()
months <- format(seq(as.Date(paste0(RULE$is_window[1], "-01")), as.Date(paste0(RULE$is_window[2], "-01")), by = "month"), "%Y-%m")
DT <- decision_table(months, bm$Date)
stopifnot(all(DT$t < as.Date(paste0(months, "-01"))))

PS <- ps_chronology()
y_dir <- PS$ps_bear[match(months, PS$ym)]
RV <- monthly_rv(bm)
rv <- RV$rv[match(months, RV$ym)]
q_var <- unname(quantile(rv, 2 / 3, type = 7))
y_var <- rv > q_var
stopifnot(!anyNA(y_dir), !anyNA(y_var))

# ── 예측기 패널 (as-of) ─────────────────────────────────────────────────────
get_series <- function(spec) {
  x <- as.data.table(read_parquet(file.path(ROOT, spec$file)))
  x[, Date := as.Date(get(spec$date_col))]
  setorder(x, Date)
  x
}
P <- data.table(ym = months, t = DT$t, t_lag1 = DT$t_lag1, y_dir = y_dir, rv = rv, y_var = y_var)
pit_checks <- list()
for (nm in names(CANDIDATES)) {
  s <- CANDIDATES[[nm]]; x <- get_series(s)
  a <- asof_value(x$Date, x[[s$col]], P$t); a1 <- asof_value(x$Date, x[[s$col]], P$t_lag1)
  P[, (nm) := a$value]; P[, (paste0(nm, "__lag1")) := a1$value]
  chk <- list(n_na = sum(is.na(a$value)), src_le_t = all(a$src_date <= P$t, na.rm = TRUE),
              src_eq_t = mean(a$src_date == P$t, na.rm = TRUE))
  if ("fit_date" %in% names(x)) {
    fd <- asof_value(x$Date, as.numeric(x$fit_date), P$t)$value
    chk$fit_date_le_t <- all(as.Date(fd, origin = "1970-01-01") <= P$t, na.rm = TRUE)
  }
  if ("JM_Fit_Date" %in% names(x)) {
    fd <- asof_value(x$Date, as.numeric(as.Date(x$JM_Fit_Date)), P$t)$value
    chk$fit_date_lt_t <- all(as.Date(fd, origin = "1970-01-01") < P$t, na.rm = TRUE)
    P[, JM_State__diag := asof_value(x$Date, x$JM_State, P$t)$value]
  }
  stopifnot(isTRUE(chk$src_le_t), is.null(chk$fit_date_le_t) || isTRUE(chk$fit_date_le_t),
            is.null(chk$fit_date_lt_t) || isTRUE(chk$fit_date_lt_t))
  pit_checks[[nm]] <- chk
}
# 순진 참조(후보 아님): 직전 20거래일 실현변동성(Moreira & Muir 2017 https://doi.org/10.1111/jofi.12513) ·
#   직전 252거래일 수익의 음수(TSMOM 12개월 — Moskowitz, Ooi & Pedersen 2012 https://doi.org/10.1016/j.jfineco.2011.11.003)
lr <- c(NA_real_, diff(log(bm$BM_Close)))
vol20 <- frollapply(lr, 20L, sd, align = "right")
ret252 <- bm$BM_Close / shift(bm$BM_Close, 252L) - 1
P[, REF_vol20 := asof_value(bm$Date, vol20, t)$value]
P[, REF_negret12m := -asof_value(bm$Date, ret252, t)$value]
# 민감도(후보 아님 · 선정 무관): MSM as-of 의 식별 관문 없는 최고 우도 판(build_msm_asof.R — 관문은 AUC 계산 전에 고정)
ma_raw <- as.data.table(read_parquet(file.path(WORK, "msm_asof_daily.parquet"))); ma_raw[, Date := as.Date(Date)]
P[, SENS_MSM_asof_raw := asof_value(ma_raw$Date, ma_raw$Crisis_Prob_asof_raw, t)$value]

# ── AUC · 부트스트랩 ───────────────────────────────────────────────────────
# 적격 판정은 AUC 계산 전에 확정(PIT 판정 = 감사 산출 · 커버리지 = 값 유무만)
elig <- names(CANDIDATES)[vapply(names(CANDIDATES), function(nm)
  CANDIDATES[[nm]]$pit %in% c("PIT-clean", "usable-with-lag") && mean(is.finite(P[[nm]])) >= 0.95, logical(1))]
if (!length(elig)) stop("[MC1 IS] 적격 후보 0 — 선정 불가")
n <- nrow(P); IDX <- cbb_indices(n, L = 12L, B = 5000L, seed = 20261010L)
K <- length(elig); alpha <- 0.05
stat_block <- function(score, y) {
  bt <- boot_auc(score, y, IDX)
  sh <- shift_null_p(score, y, L = 12L)
  list(auc = auc_mw(score, y), ci95 = ci_q(bt, 0.025, 0.975), ci_bonf = ci_q(bt, alpha / (2 * K), 1 - alpha / (2 * K)),
       boot_na = sum(!is.finite(bt)), p_shift_one_sided = sh$p_one_sided, shift_null_q95 = sh$null_q95, coverage = mean(is.finite(score)),
       .boot = bt)
}
res <- list(); boots <- list()
for (nm in c(names(CANDIDATES), "REF_vol20", "REF_negret12m", "SENS_MSM_asof_raw")) {
  sd_ <- stat_block(P[[nm]], P$y_dir); sv_ <- stat_block(P[[nm]], P$y_var)
  boots[[nm]] <- sd_$.boot
  r <- list(direction = sd_[setdiff(names(sd_), ".boot")], variance = sv_[setdiff(names(sv_), ".boot")])
  if (nm %in% names(CANDIDATES)) {
    l1 <- P[[paste0(nm, "__lag1")]]
    r$direction_lag1_auc <- auc_mw(l1, P$y_dir); r$variance_lag1_auc <- auc_mw(l1, P$y_var)
    r$pit_checks <- pit_checks[[nm]]
    r$spec <- CANDIDATES[[nm]][c("file", "col", "model", "provenance", "pit")]
  } else r$role <- if (startsWith(nm, "SENS_")) "sensitivity_not_candidate (unguarded MLE)" else "reference_only_not_candidate"
  res[[nm]] <- r
}
res$JM_BearProb$diag_JM_State_direction_auc <- auc_mw(P$JM_State__diag, P$y_dir)
res$JM_BearProb$diag_JM_State_variance_auc <- auc_mw(P$JM_State__diag, P$y_var)

# ── 선정 (사전등록 규칙) ─────────────────────────────────────────────────────
aucs <- vapply(elig, function(nm) res[[nm]]$direction$auc, numeric(1))
primary <- elig[which.max(aucs)]
runner <- setdiff(elig[order(-aucs)], primary)
paired <- lapply(runner, function(o) { d <- boots[[primary]] - boots[[o]]
  list(vs = o, delta_auc = res[[primary]]$direction$auc - res[[o]]$direction$auc, ci95 = ci_q(d, 0.025, 0.975),
       share_boot_primary_better = mean(d > 0, na.rm = TRUE)) })
lb <- res[[primary]]$direction$ci_bonf[1]
mc1_pass <- isTRUE(is.finite(lb) && lb > 0.5)

cor_m <- suppressWarnings(cor(as.matrix(P[, c(names(CANDIDATES), "REF_vol20", "REF_negret12m", "SENS_MSM_asof_raw"), with = FALSE]), method = "spearman", use = "pairwise.complete.obs"))
out <- list(
  schema = "l2_mc1_predictor_selection_IS_v1",
  written_at = now_kst(),
  stage = "IS_SELECTION (OOS 미열람)",
  design_ref = "04_Research/01_reports/l2_role_rotation_redesign_20261010/README.md §2.2·§3",
  rule = RULE,
  pit_audit_ref = "04_Research/l2_role_rotation/pit_audit.json",
  ineligible_not_measured = INELIGIBLE,
  sample = list(months = c(first(months), last(months)), n_months = n, n_bear = sum(P$y_dir), share_bear = mean(P$y_dir),
                n_highvol = sum(P$y_var), rv_tercile_threshold_IS = q_var, first_decision_date = as.character(min(P$t)),
                last_decision_date = as.character(max(P$t)), K_eligible = K, bonferroni_percentiles = c(alpha / (2 * K), 1 - alpha / (2 * K))),
  results = res,
  spearman_IS = cbind(var = rownames(cor_m), as.data.frame(round(cor_m, 3))),
  pit_audit_md5 = unname(tools::md5sum(AUD_PATH)),
  selection = list(eligible = elig, primary = primary, primary_auc_direction = unname(aucs[primary]),
                   primary_ci_bonf = res[[primary]]$direction$ci_bonf, primary_ci95 = res[[primary]]$direction$ci95,
                   mc1_pass = mc1_pass,
                   mc1_verdict = if (mc1_pass) "PASS — 방향 판별력이 우연 대비 유의(Bonferroni 하한 > 0.5)" else "FAIL — 설계 §3: T 미측정",
                   paired_vs_others = paired,
                   rule_applied = RULE$selection),
  inputs = list(benchmark = file_sig(".cache/benchmark.parquet"), jm = file_sig(".cache/regime_jump_daily.parquet"),
                msm_asof = file_sig("04_Research/l2_role_rotation/work/msm_asof_daily.parquet"),
                hmm2_asof = file_sig("04_Research/l2_role_rotation/work/hmm2_asof_daily.parquet"),
                code = lapply(c("mc1_is_selection.R", "lib_mc1.R", "build_msm_asof.R", "build_hmm2_asof.R", "msm_fast_kernel.cpp"),
                              function(f) file_sig(file.path(L2DIR, f))),
                strategy_role_contract = file_sig("02_Infrastructure/contracts/strategy_role.R")),
  elapsed_sec = round(as.numeric(difftime(Sys.time(), t_run, units = "secs")), 1))
fwrite(P, file.path(WORK, "mc1_panel_IS.csv"))
write_json_atomic(out, file.path(L2DIR, "predictor_selection_IS.json"))
cat(sprintf("[MC1 IS] n=%d bear=%d highvol=%d | primary=%s AUC=%.3f CIbonf=[%.3f, %.3f] -> MC1 %s\n", n, sum(P$y_dir), sum(P$y_var),
            primary, aucs[primary], res[[primary]]$direction$ci_bonf[1], res[[primary]]$direction$ci_bonf[2], if (mc1_pass) "PASS" else "FAIL"))
for (nm in names(res)) cat(sprintf("  %-22s dir %.3f [%.3f,%.3f] p_shift %.3f | var %.3f [%.3f,%.3f]\n", nm,
  res[[nm]]$direction$auc, res[[nm]]$direction$ci95[1], res[[nm]]$direction$ci95[2], res[[nm]]$direction$p_shift_one_sided,
  res[[nm]]$variance$auc, res[[nm]]$variance$ci95[1], res[[nm]]$variance$ci95[2]))
