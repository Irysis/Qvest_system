## WT-R20260829_006 Phase 7 — alpha_package.json + alpha_validation.json 발행
suppressPackageStartupMessages({library(data.table);library(arrow);library(jsonlite)})
setDTthreads(1); try(arrow::set_cpu_count(1),silent=TRUE)
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/config.R")
source("02_Infrastructure/factor_db/factor_db_connector.R")
OUT <- "C:/Users/99922/AppData/Local/Temp/claude/C--Users-99922-OneDrive-Quant-Module-Moltbot/0c0807c3-c2cd-4903-8044-987993f6f62f/scratchpad/wt006"
ART <- "stage_artifacts/WT_R20260829_006"
MBX <- "qepm/mailbox/worktask/WT-R20260829_006"

H  <- fromJSON(file.path(MBX,"alpha_hypothesis.json"), simplifyVector = FALSE)
P2 <- readRDS(file.path(OUT,"p2s_tier1.rds"))
P3 <- readRDS(file.path(OUT,"p3s_tier2.rds"))
P4 <- readRDS(file.path(OUT,"p4s_mech.rds"))
P5 <- readRDS(file.path(OUT,"p5s_candidate.rds"))
P6 <- readRDS(file.path(OUT,"p6s_pit.rds"))
FAMMAP <- fread(file.path(OUT,"p1s_family_map.csv"))
reg <- fromJSON("02_Infrastructure/factor_db/factor_registry.json", simplifyVector = FALSE)
AS_OF <- P5$alpha_vector_meta$as_of
nonmom <- P3$nonmom

## ★AST 리프 = 엔진이 실제로 소비한 팩터의 **전 기간 합집합**(as_of 스냅샷 아님).
##   as_of 한 달만 보면 그 달의 커버리지 구멍이 팩터 정의를 왜곡한다.
USED <- as.data.table(read_parquet(file.path(OUT,"p1s_factor_ls_returns.parquet")))
used_fns <- sort(unique(USED$Factor_Name))
FM <- FAMMAP[Factor_Name %in% used_fns]
zl <- as.data.table(load_month_factors(AS_OF, dedup = TRUE))
present <- sort(unique(zl$Factor_Name))
AS_OF_COV <- FM[, .(n_total = .N, n_at_as_of = sum(Factor_Name %in% present)), by = family][order(family)]
cat("[emit] 소비 팩터 합집합", length(used_fns), " 매핑", nrow(FM), " 계열", uniqueN(FM$family), "\n")
cat("[emit] as_of 커버리지 결손 계열:", paste(AS_OF_COV[n_at_as_of == 0, family], collapse=", "), "\n")
print(AS_OF_COV)

restate_of <- function(fn) {
  e <- reg[[fn]]
  isTRUE(e$restatement_prone) || isTRUE(e$labels$restatement_prone)
}
avail_of <- function(fn) {
  e <- reg[[fn]]
  a <- e$availability
  if (is.null(a)) return("registry availability 미선언 — 보수 판정: 월간 factor_db 승격분(load_month_factors 경유, Usable_Date <= sig_date 강제)")
  paste0(a$type %||% "unknown", ": ", a$rule %||% "rule 미선언")
}
`%||%` <- function(a,b) if (is.null(a)||length(a)==0) b else a

RATIONALE <- c(value="risk_premium", quality="risk_premium", size="risk_premium",
               defense="risk_premium", risk="risk_premium", liquidity="risk_premium",
               leverage="risk_premium", growth="behavioral", consensus="behavioral",
               accrual="behavioral", momentum="behavioral",
               crowding="structural", investor_flow="structural", regime="structural")

## ── factors[] : 계열 합성 13 + 타이밍 가중 생성기 1 ────────────────────────────
mk_family_factor <- function(fam) {
  fns <- sort(FM[family == fam, Factor_Name])
  leaves <- lapply(fns, function(fn) list(leaf = "REGISTRY", factor = fn))
  ast <- list(op = "MUL", args = list(
      list(op = "ADD", args = leaves),
      1/length(fns)))
  list(factor_id = paste0("F_fam_", fam),
       ast = ast, role = "core_signal",
       restatement_exposure = as.integer(sum(vapply(fns, restate_of, logical(1)))),
       n_leaves = length(fns))
}
fac_list <- lapply(nonmom, mk_family_factor)
names(fac_list) <- nonmom

timing <- list(
  factor_id = "F_tsfmom_weights",
  ast = list(leaf = "SPECIAL_OP",
             op_code_path = "stage_artifacts/WT_R20260829_006/engine/phase5_candidate.R",
             walk_forward = TRUE,
             escape_contract = list(escape_type = "SPECIAL_OP",
               op_code_path = "stage_artifacts/WT_R20260829_006/engine/phase5_candidate.R",
               walk_forward = TRUE)),
  role = "conditioning",
  restatement_exposure = 0L,
  n_leaves = 1L)

FACTORS <- c(lapply(fac_list, function(x) x[c("factor_id","ast","role","restatement_exposure")]),
             list(timing[c("factor_id","ast","role","restatement_exposure")]))
names(FACTORS) <- NULL
n_leaf_declared <- sum(vapply(fac_list, function(x) x$n_leaves, integer(1))) + 1L
cat("[emit] 선언 리프 수 =", n_leaf_declared, "\n")

## ── factor_specs ──────────────────────────────────────────────────────────────
WAS <- as.data.table(P5$as_of_weights)
theta_of <- function(f) { v <- WAS[family==f, w]; if (length(v)==0) 0 else round(v[1],6) }
SPECS <- lapply(nonmom, function(fam) {
  fns <- sort(FM[family == fam, Factor_Name])
  list(factor_family = fam,
       proxy = paste0("계열 합성 z (등가중, ", length(fns), "개 팩터: ",
                      paste(head(fns,4), collapse=", "), if (length(fns)>4) ", …" else "", ")"),
       formula = "z_fam(f,i,d) = mean_k Z_Score_Aligned(k,i,d), k ∈ family f",
       lag_rule = "load_month_factors(sig_date) 승격분만 — Usable_Date <= sig_date (C14/C15)",
       winsorization = "Factor DB 승격 규약(3std) 승계",
       neutralization = "none (계열 합성 단계). 진단으로 log(Size) 중립화 IC 병기",
       economic_rationale = unname(RATIONALE[fam]),
       weight_theta = theta_of(fam),
       references = list("Ehsani & Linnainmaa (2022) JF 77:1877-1919",
                         "https://onlinelibrary.wiley.com/doi/abs/10.1111/jofi.13131"))
})
SPECS <- c(SPECS, list(list(
  factor_family = "factor_timing_overlay",
  proxy = "TS-FMOM 지시 계열 가중 w_f(d) = sign(mean r^f over 12-1) / sd_expanding(r^f)",
  formula = "score_i(d) = Σ_f w_f(d)·z_fam(f,i,d) / Σ_f |w_f(d)|",
  lag_rule = "형성창 = 홀딩월 m-12..m-1 실현 팩터수익만 (스킵월 없음, EL2022 게재판 Table 2 사양)",
  winsorization = "none",
  neutralization = "none",
  economic_rationale = "behavioral",
  weight_theta = 1,
  references = list("Ehsani & Linnainmaa (2022) JF 77:1877-1919 Table 2·Table 6 Panel A",
                    "Kozak-Shleifer-Vishny (2018) AR(1) 감정수요"))))

## ── self_pit_check ────────────────────────────────────────────────────────────
all_leaf_fns <- sort(unique(unlist(lapply(nonmom, function(f) FM[family==f, Factor_Name]))))
leaves_checked <- lapply(all_leaf_fns, function(fn) list(
  leaf = fn, availability_rule = avail_of(fn), restatement_prone = restate_of(fn)))
leaves_checked <- c(leaves_checked, list(list(
  leaf = "SPECIAL_OP:F_tsfmom_weights",
  availability_rule = "walk-forward: 형성 부호·변동성 모두 t 이하 실현 팩터수익만 (확장창, full-sample 금지 C1)",
  restatement_prone = FALSE)))
n_restate <- sum(vapply(leaves_checked, function(x) isTRUE(x$restatement_prone), logical(1)))
cat("[emit] self_pit_check 리프", length(leaves_checked), " restatement_prone", n_restate, "\n")

## ── alpha / confidence vector ─────────────────────────────────────────────────
AT <- as.data.table(P5$alpha_table)
alpha_vector <- as.list(setNames(round(AT$alpha_hat, 8), AT$Ticker))
confidence_vector <- as.list(setNames(round(AT$confidence, 4), AT$Ticker))

## ── falsification (스키마 배열형) — 승계 내용 그대로, 형식만 배열화 ────────────
fal <- H$selected$falsification
mk_f <- function(fields, expectation) list(fields = as.list(fields), expectation = expectation)
FALS <- list(
  mk_f(c("FDB-B6_fdb_daily_store","FDB-B1_registry_fundamental_quarterly",
         "FDB-B2_registry_rawdata_price_daily","FDB-B3_registry_consensus_daily",
         "FDB-B4_registry_investor_flow_monthly","FDB-B5_registry_macro"),
       paste0("1급(전제): ", fal$tier1_premise$reject_if)),
  mk_f(c("FDB-B7_ic_history_monthly","FDB-B8_daily_ic_panel_fq055"),
       paste0("2급(스패닝): ", fal$tier2_spanning$reject_if,
              " | 역방향 의무: ", fal$tier2_spanning$reverse_regression_obligation)),
  mk_f(c("A1_RAWDATA_OHLCVS_daily","A3_universe_support_membership_panels","A4_benchmark_kospi200"),
       paste0("(c) σ²_β 전달식: ", fal$ancillary_observables_non_performance[[3]]$observation)),
  mk_f(c("FDB-B6_fdb_daily_store","FDB-B10_registry_meta_and_caches"),
       paste0("(d) 고유값 정렬: ", fal$ancillary_observables_non_performance[[4]]$observation)),
  mk_f(c("E3_macro_regime_monthly","E7_unified_regime_3layer","A4_benchmark_kospi200"),
       paste0("(e) 크래시 동시성: ", fal$ancillary_observables_non_performance[[5]]$observation)),
  mk_f(c("A3_universe_support_membership_panels","A9_liquidity_avgtv20_convention",
         "A2_universe_krx_monthly"),
       paste0("(f) 유니버스·유동성 PIT: ", fal$ancillary_observables_non_performance[[6]]$observation))
)

HYP <- list(
  statement = H$selected$hypothesis_description,
  mechanism = H$selected$mechanism,
  falsification = FALS,
  regime_scope = H$selected$regime_scope,
  inherited_verbatim_note = paste0(
    "mechanism / regime_scope 는 alpha-hypothesis 산출(alpha_hypothesis.json)을 재작성 없이 승계. ",
    "falsification 은 내용 불변·형식만 schema 배열형으로 변환(원문은 alpha_hypothesis.json::selected.falsification)."),
  inherited_falsification_source = "qepm/mailbox/worktask/WT-R20260829_006/alpha_hypothesis.json::selected.falsification"
)

## ── diagnostics ───────────────────────────────────────────────────────────────
d5 <- P5$diagnostics; c5 <- P5$canonical; b5 <- P5$beta_controlled
DIAG <- list(
  canonical_port_t_nw_lag3 = round(c5$portfolio_alpha_t_nw_lag3, 6),
  canonical_port_t_pvalue  = round(c5$portfolio_alpha_t_pvalue, 6),
  canonical_n_months = as.integer(c5$n_months),
  rank_ic = round(d5$rank_ic, 6),
  icir = round(d5$icir, 6),
  monotonicity = round(d5$monotonicity, 6),
  subperiod_stability = round(d5$subperiod_stability, 6),
  turnover_proxy = round(c5$turnover_annual, 4),
  harvey_t_stat = round(d5$harvey_t, 4),
  deflated_sharpe_ratio = round(d5$dsr, 6),
  post_neutralization_ic = round(d5$post_neutralization_ic, 6),
  alpha_inheritance_cor = round(abs(P6$alpha_inheritance$spearman_mean), 6),
  portfolio_alpha_t_separate_note = paste0(
    "★rank-IC t(", round(d5$ic_t,3), ") 와 portfolio-alpha t(", round(c5$portfolio_alpha_t_nw_lag3,3),
    ") 를 구분 보고 (Cycle 2 교훈). 권위 = portfolio-alpha t. forge 재측정이 authoritative."),
  beta_controlled_alpha_ann = round(b5$alpha_ann, 6),
  beta_controlled_t_alpha = round(b5$t_alpha, 4),
  beta = round(b5$beta, 4),
  net_sr_active = round(c5$net_sr, 6),
  information_ratio = round(c5$information_ratio, 6),
  diag_ew_universe_port_t = tryCatch(round(c5$diag_ew_universe$portfolio_alpha_t_nw_lag3,4), error=function(e) NA_real_),
  diag_ew_universe_post2017_t = tryCatch(round(c5$diag_ew_universe$post2017_t_nw_lag3,4), error=function(e) NA_real_)
)

PKG <- list(
  task_id = "WT-R20260829_006",
  as_of_date = AS_OF,
  forecast_horizon = "1M",
  spec_version = "ast_v1.1",
  pit = list(sig_date = AS_OF, decision_ts = AS_OF),
  hypothesis = HYP,
  factors = FACTORS,
  combination_rule = "z_score_aligned_weighted_sum",
  verdict = "designed",
  self_pit_check = list(performed = TRUE, leaves_checked = leaves_checked,
    verdict = if (n_restate > 0) "warn_restatement" else "clean",
    notes = paste0("리프 ", length(leaves_checked), "개 전수 점검. restatement_prone ", n_restate,
      "개 — 전부 factor_db 월간 승격분(load_month_factors 경유·Usable_Date <= sig_date 강제)이라 ",
      "구조적 look-ahead 는 없고 재작성(restatement) 노출만 남는다. SPECIAL_OP 는 확장창 walk-forward.")),
  alpha_vector = alpha_vector,
  confidence_vector = confidence_vector,
  signal_matrix_ref = "stage_artifacts/WT_R20260829_006/alpha_scores.parquet",
  factor_specs = SPECS,
  diagnostics = DIAG,
  selection_objective = "canonical_port_t",
  alpha_discovery_count = 1L,
  challenge_flags = list()   # phase7b 에서 주입
)
saveRDS(list(PKG=PKG, n_leaf_declared=n_leaf_declared, n_restate=n_restate, as_of_cov=AS_OF_COV),
        file.path(OUT,"p7s_pkg_base.rds"))
cat("[emit] 기본 패키지 구성 완료 — challenge_flags 주입은 phase7b\n")
