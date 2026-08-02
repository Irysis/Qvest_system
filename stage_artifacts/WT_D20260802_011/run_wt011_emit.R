# =============================================================================
# run_wt011_emit.R — WT-D20260802_011 산출물 마감
#   1. alpha_package.json vector 주입 (게이트 검증 완료본에 — 스펙 필드 불변)
#   2. alpha_validation.json 저장 (stage_artifacts)
#   3. lineage 기록 (package write 후 — L-194 순서)
#   4. status.json ALPHA_DONE + governance_log append
# 실행: Rscript -e 'source("stage_artifacts/WT_D20260802_011/run_wt011_emit.R")'
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260802_011")
MB  <- file.path(ROOT, "qepm/mailbox/worktask/WT-D20260802_011")
say <- function(fmt, ...) cat(sprintf(paste0("[wt011m] ", fmt, "\n"), ...))

# ── 1. vector 주입 ───────────────────────────────────────────────────────────
pkg <- fromJSON(file.path(MB, "alpha_package.json"), simplifyVector = FALSE)
av  <- fromJSON(file.path(OUT, "alpha_vector_latest.json"), simplifyVector = FALSE)
cv  <- fromJSON(file.path(OUT, "confidence_vector_latest.json"), simplifyVector = FALSE)
stopifnot(length(av) == 328, length(cv) == 328,
          identical(sort(names(av)), sort(names(cv))))
pkg$alpha_vector <- av
pkg$confidence_vector <- cv
write_json(pkg, file.path(MB, "alpha_package.json"), pretty = TRUE,
           auto_unbox = TRUE, digits = NA, null = "null")
say("alpha_package.json vector 주입 완료 — %d종목", length(av))

# ── 2. alpha_validation.json ────────────────────────────────────────────────
R <- readRDS(file.path(OUT, "wt011_eval_results.rds"))
b <- R$bt$SIG_LEVY_PV_63_SM3
b6 <- R$bt$SIG_LEVY_PV_63_SM6
ew <- b$diag_ew_universe
val <- list(
  task_id = "WT-D20260802_011",
  generated_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
  metric_type = "canonical_screen",
  gate_eligible = FALSE,
  selection_type = "chain",
  n_trials = 1,
  preregistration = "stage_artifacts/WT_D20260802_011/preregistration.json (측정 전 고정)",
  inheritance = list(parent = "WT-D20260802_006",
                     reused = c("signature_panel.parquet", "alpha_scores.parquet(base z)",
                                "size_panel.parquet", "평가 프레임"),
                     recomputation = "없음 — 시그니처 재계산 금지 준수"),
  turnover_gate = list(limit_annual = 11.0, observed_sm3 = b$turnover_annual,
                       observed_sm6_diag = b6$turnover_annual,
                       base_quoted = 15.78,
                       verdict = "PASS — 1차 관문 충족 (base 대비 33% 감축)"),
  primary = list(
    factor_id = "SIG_LEVY_PV_63_SM3",
    canonical = list(
      port_t_nw_lag3 = b$portfolio_alpha_t_nw_lag3,
      pvalue = b$portfolio_alpha_t_pvalue,
      n_months = b$n_months,
      net_sr = b$net_sr,
      information_ratio = b$information_ratio,
      turnover_annual = b$turnover_annual),
    subperiod_port_t = R$sub_port_t,
    advisory = list(rank_ic = R$diag$SIG_LEVY_PV_63_SM3$rank_ic,
                    icir = R$diag$SIG_LEVY_PV_63_SM3$icir,
                    ic_t = R$diag$SIG_LEVY_PV_63_SM3$ic_t,
                    monotonicity = R$diag$SIG_LEVY_PV_63_SM3$monotonicity)),
  dual_basis = list(
    cap_w_port_t = b$portfolio_alpha_t_nw_lag3,
    ew_universe_port_t = ew$portfolio_alpha_t_nw_lag3,
    ew_universe_post2017_t = ew$post2017_t_nw_lag3,
    ew_universe_oos_retention_approx = ew$oos_retention_approx,
    cap_tier_weight_share = b$diag_cap_tier$weight_share,
    cap_tier_contrib_annualized = b$diag_cap_tier$contrib_annualized,
    verdict = "양 basis 공멸(cap-w -0.27 / EW-uni -0.45) — 벤치 아티팩트 구제 불가. v8.3 기각-전 확인 의무 이행"),
  smoothing_6m_diagnostic = list(
    port_t = b6$portfolio_alpha_t_nw_lag3,
    ew_uni_t = b6$diag_ew_universe$portfolio_alpha_t_nw_lag3,
    turnover_annual = b6$turnover_annual,
    note = "진단 병기 — 선택 비사용"),
  lag1 = list(sm3_port_t = b$portfolio_alpha_t_nw_lag3,
              lag1_port_t = R$bt_lag1$portfolio_alpha_t_nw_lag3,
              verdict = "신호가 이미 노이즈 대역 — lag 판정 무의미"),
  placebo = R$placebo,
  placebo_note = "Gaussian 치환 5시드 + 동일 3M 평활 파이프라인. SM3는 placebo 분포 안 = 신호 소멸(부호 반전 아님)",
  falsification = R$falsification,
  regime_conditional = R$regime_tab,
  ax001_conditional = R$ax001,
  signal_retention = c(R$retention, list(sm3_vs_base_rank_cor = 0.720,
    verdict = "수익축 소멸(보존율 -0.22) vs flow축 무손실(1.00) — 스펙트럼 분해 실측")),
  base_quoted = R$base_quoted,
  label_direction_ic = R$label_direction_ic,
  min_valid_boundary = list(nv2_share = 0.019, nv3_share = 0.981),
  sidecar_live_with_ast = R$sidecar,
  graduation_hard_gates = list(
    portfolio_alpha_t_nw = list(required = 2.95,
      observed_canonical = b$portfolio_alpha_t_nw_lag3, status = "FAIL",
      note = "canonical screening 실측 — forge 승격 미제출(자본 판정 아님)"),
    oos_retention = list(required = 0.7,
      observed_approx_ew = ew$oos_retention_approx, status = "FAIL_APPROX",
      note = "진단 근사(권위는 essence_score)"),
    calmar = list(required = 0.64, observed = NULL, status = "NOT_COMPUTED",
      note = "PORT_t 미달로 forge 미제출")),
  production_constraints = list(turnover_annual_limit = 11.0,
    observed = b$turnover_annual, verdict = "PASS — 본 라운드의 1차 관문 달성"))
write_json(val, file.path(OUT, "alpha_validation.json"), pretty = TRUE,
           auto_unbox = TRUE, digits = 6, null = "null")
say("alpha_validation.json 저장")

# ── 3. lineage (package write 후 — L-194 순서) ──────────────────────────────
source("02_Infrastructure/worktask/lineage_utils.R")
record_package_lineage(
  task_id = "WT-D20260802_011",
  package_type = "alpha_package",
  method_selected = "SIG_LEVY_PV_63_SM3 (3M smoothing of WT-006 base, preregistered single primary, chain)",
  input_file_paths = c(
    file.path(ROOT, "stage_artifacts/WT_D20260802_006/alpha_scores.parquet"),
    file.path(ROOT, "stage_artifacts/WT_D20260802_006/signature_panel.parquet"),
    file.path(ROOT, "stage_artifacts/WT_D20260802_006/size_panel.parquet"),
    file.path(ROOT, ".cache/RAWDATA.parquet"),
    file.path(ROOT, ".cache/investor_stock/investor_wide.parquet"),
    file.path(ROOT, ".cache/unified_regime_signal.parquet")))
say("lineage 기록")

# ── 4. status + governance_log ──────────────────────────────────────────────
st <- list(task_id = "WT-D20260802_011", current_phase = "ALPHA_DONE",
           updated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S+0900"),
           blocker = NULL)
write_json(st, file.path(MB, "status.json"), pretty = TRUE, auto_unbox = TRUE,
           null = "null")
gl_path <- file.path(MB, "governance_log.json")
gl <- if (file.exists(gl_path)) fromJSON(gl_path, simplifyVector = FALSE) else list()
gl[[length(gl) + 1L]] <- list(
  ts = format(Sys.time(), "%Y-%m-%dT%H:%M:%S+0900"),
  actor = "alpha-research",
  event = "ALPHA_DONE",
  note = paste0("3M 평활판 판정: TO 10.53<=11.0 충족 / PORT_t -0.27 placebo 대역(신호 소멸) / ",
                "flow 링크 t=+4.09 무손실 보존. gate_eligible=false. ",
                "config_scoped_negative_smoothing_path__flow_link_preserved. ",
                "Self-Adversarial 4건(ACCEPT 1/PARTIAL 3), escalation 0. ",
                "ast_spec_gate 통과(3차 — falsification 객체배열/pit.sig_date 교정 이력 정직 기재)"))
write_json(gl, gl_path, pretty = TRUE, auto_unbox = TRUE, null = "null")
say("status=ALPHA_DONE + governance_log append 완료")
