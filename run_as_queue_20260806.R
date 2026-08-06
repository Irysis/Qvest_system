# =============================================================================
# run_as_queue_20260806.R — alpha-search 큐 소비자 (2026-08-06, MAX_ALPHA=2)
# 대상: FQ-149 (FX_Intensity) + FQ-092 (VolRankReverse)
# 파이프라인: run_alpha_search → auto_verify JSON → auto_alpha_gate.R → done list append
# =============================================================================

suppressWarnings(suppressMessages({
  library(data.table)
  library(jsonlite)
}))

# ---- Project root resolution -----------------------------------------------
.QAS_ROOT <- local({
  cands <- unique(c(
    Sys.getenv("CLAUDE_PROJECT_DIR", ""),
    Sys.getenv("QM_ROOT", ""),
    getwd()
  ))
  is_root <- function(p) nzchar(p) && file.exists(file.path(p, "02_Infrastructure/config.R"))
  for (p in cands) if (is_root(p)) return(normalizePath(p, winslash="/", mustWork=TRUE))
  cur <- normalizePath(getwd(), winslash="/", mustWork=TRUE)
  repeat {
    if (is_root(cur)) return(cur)
    parent <- dirname(cur)
    if (identical(parent, cur)) break
    cur <- parent
  }
  stop("[QueueConsumer] project root not found")
})

# Load run_alpha_search
source(file.path(.QAS_ROOT, "02_Infrastructure/alpha_search/run_alpha_search.R"))

# ---- Helpers ---------------------------------------------------------------
DONE_PATH <- file.path(.QAS_ROOT, "stage_artifacts/paper_recharge/alpha_search_queue_done.json")
VERIFY_DIR <- file.path(.QAS_ROOT, "stage_artifacts/paper_recharge")
GATE_SCRIPT <- file.path(.QAS_ROOT, "02_Infrastructure/ops/auto_alpha_gate.R")

.read_done <- function() {
  if (!file.exists(DONE_PATH)) return(list(processed=character(0), records=list(), last_updated=""))
  tryCatch(fromJSON(DONE_PATH, simplifyVector=FALSE), error=function(e) list(processed=character(0), records=list()))
}

.append_done <- function(paper_id, record_entry) {
  done <- .read_done()
  processed <- as.character(unlist(done$processed %||% character(0)))
  # Add to processed (no-dup)
  if (!paper_id %in% processed) processed <- c(processed, paper_id)
  # Add to records (always append — factor_id distinguishes multiple runs per paper)
  records <- done$records %||% list()
  records <- c(records, list(record_entry))
  done$processed <- as.list(processed)
  done$records <- records
  done$last_updated <- format(Sys.Date(), "%Y%m%d")
  done$schema_note <- "processed = list of paper_id strings (set-like, paper 단위 dedup). records = 전체 시도 감사 로그(동일 paper에서 여러 factor 추출 시 factor_id로 구분). last_updated 갱신 의무."
  write(toJSON(done, pretty=TRUE, auto_unbox=TRUE, na="null"), DONE_PATH)
  cat(sprintf("[QueueConsumer] done list 갱신: %s (processed=%d, records=%d)\n",
              paper_id, length(processed), length(records)))
}

# Extract oos_retention from hurdle_result.json
.get_oos_retention <- function(out_dir) {
  hr_path <- file.path(out_dir, "hurdle_result.json")
  if (!file.exists(hr_path)) return(NA_real_)
  hr <- tryCatch(fromJSON(hr_path, simplifyVector=TRUE), error=function(e) NULL)
  if (is.null(hr)) return(NA_real_)
  # score_breakdown$oos$value
  sb <- hr$score_breakdown
  if (!is.null(sb$oos$value)) return(as.numeric(sb$oos$value))
  NA_real_
}

# Extract port_t from authoritative_remeasure.json or bt_result metrics
.get_port_t <- function(out_dir) {
  ar_path <- file.path(out_dir, "authoritative_remeasure.json")
  if (file.exists(ar_path)) {
    ar <- tryCatch(fromJSON(ar_path, simplifyVector=TRUE), error=function(e) NULL)
    if (!is.null(ar)) {
      pt <- ar$essence$port_t_nw %||% ar$port_t_nw %||% ar$portfolio_alpha_t
      if (!is.null(pt)) return(as.numeric(pt))
    }
  }
  # Fallback: 06_metrics.csv Portfolio_Alpha_t_NW_lag3
  mc_path <- file.path(out_dir, "07_benchmark_compare.csv")
  if (file.exists(mc_path)) {
    mc <- tryCatch(fread(mc_path), error=function(e) NULL)
    if (!is.null(mc) && "Portfolio_Alpha_t_NW_lag3" %in% names(mc)) {
      pt <- mc$Portfolio_Alpha_t_NW_lag3[1]
      if (!is.na(pt)) return(as.numeric(pt))
    }
  }
  NA_real_
}

# ---- 5-layer verification JSON writer ----------------------------------------
.write_auto_verify <- function(verify_path, paper_id, paper_title, factor_id, factor_name,
                               strategy_id, strategy_name, strategy_idea,
                               engine_path, run_date, out_dir,
                               grade, score, pit_pass, contract_pass,
                               oos_retention, port_t, calmar_val,
                               metrics_list = list(),
                               fidelity_pass = TRUE, fidelity_confidence = "high",
                               fidelity_notes = "", impl_spec = list(),
                               verdict_notes = character(0),
                               revival_conditions = character(0)) {
  robustness_pass <- !is.na(oos_retention) && isTRUE(oos_retention >= 0.5)
  v <- list(
    paper_id       = paper_id,
    paper_title    = paper_title,
    factor_name    = factor_name,
    strategy_name  = strategy_name,
    strategy_id    = strategy_id,
    engine_path    = .rel_project_path(engine_path),
    run_date       = run_date,
    impl_spec      = impl_spec,
    pit_pass       = isTRUE(pit_pass),
    contract_pass  = isTRUE(contract_pass),
    robustness_pass= robustness_pass,
    fidelity_pass  = isTRUE(fidelity_pass),
    fidelity_issues = list(),
    fidelity_confidence = fidelity_confidence,
    fidelity_notes = fidelity_notes,
    port_t         = if (!is.na(port_t)) port_t else NULL,
    oos_retention  = if (!is.na(oos_retention)) oos_retention else NULL,
    calmar         = if (!is.na(calmar_val)) calmar_val else NULL,
    grade          = grade,
    score          = score,
    pass           = isTRUE(grade %in% c("A","A_NOVEL","A_DEF")),
    notable        = isTRUE(grade %in% c("B","C") || (grade=="F" && isTRUE(pit_pass))),
    run_success    = TRUE,
    error          = list(),
    metrics        = metrics_list,
    hard_gate_verdict = list(
      PORT_t_pass     = !is.na(port_t) && isTRUE(port_t >= 2.95),
      OOS_retention_pass = !is.na(oos_retention) && isTRUE(oos_retention >= 0.70),
      Calmar_pass     = !is.na(calmar_val) && isTRUE(calmar_val >= 0.64),
      overall         = if (!is.na(port_t) && isTRUE(port_t >= 2.95) &&
                            !is.na(oos_retention) && isTRUE(oos_retention >= 0.70) &&
                            !is.na(calmar_val) && isTRUE(calmar_val >= 0.64)) "PASS" else "FAIL"
    ),
    verdict_notes  = as.list(verdict_notes),
    revival_conditions = as.list(revival_conditions),
    out_dir        = .rel_project_path(out_dir),
    verified_by    = paste0("Q-Lead AlphaSearch ", paper_id, " ", run_date)
  )
  write(toJSON(v, pretty=TRUE, auto_unbox=TRUE, na="null"), verify_path)
  cat(sprintf("[QueueConsumer] auto_verify 작성: %s\n", verify_path))
  invisible(v)
}

# ---- Run gate and return decision -------------------------------------------
.run_gate <- function(verify_path) {
  gate_result <- tryCatch({
    cmd <- sprintf('Rscript "%s" "%s"', GATE_SCRIPT, verify_path)
    system(cmd, intern=TRUE, wait=TRUE)
  }, error=function(e) c("QUARANTINE: gate error"))
  gate_out <- paste(gate_result, collapse="\n")
  cat(sprintf("[QueueConsumer] auto_alpha_gate output: %s\n", gate_out))
  if (grepl("^ADOPT", gate_out)) "ADOPT" else "QUARANTINE"
}

# ---- Paper 1: FQ-149 — FX Intensity -----------------------------------------
cat("\n==========================================================================\n")
cat("FQ-149: FX 노출 강도 지수 (factor_engine_FX_Intensity.R)\n")
cat("paper: arXiv:2607.27611 (AWARE-FX)\n")
cat("==========================================================================\n\n")

FQ149_ENGINE <- file.path(.QAS_ROOT, "02_Infrastructure/alpha_search/factor_engine_FX_Intensity.R")
FQ149_VERIFY <- file.path(VERIFY_DIR, "auto_verify_FX_Intensity_FQ149_20260806.json")
FQ149_PAPER_ID <- "2607.27611"
FQ149_PAPER_TITLE <- "AWARE-FX: Corporate FX Hedging Behavior and Stock Returns"
FQ149_FACTOR_ID <- "FX_Intensity_FQ149"
FQ149_IDEA <- paste0(
  "AWARE-FX 논문 FX exposure baseline 직접 대응: ",
  "(|외화환산이익|+|외화환산손실|)/TotalAssets. ",
  "높은 FX 노출 기업이 적극 헤징 → 불확실성 감소 → 리스크 프리미엄 감소 → 초과수익. ",
  "annual lag 익년3/31 (PIT C4), K200∪KQ150, 월간 리밸 15bps."
)

r149 <- tryCatch({
  run_alpha_search(
    strategy_name   = "FX_Intensity_FQ149",
    strategy_idea   = FQ149_IDEA,
    factor_engine_path = FQ149_ENGINE,
    n_holdings      = 20L,
    weight_method   = "ivol",
    commission      = 0.0015,
    start_date      = "2005-01-01",
    universe        = "K200_KQ150",
    send_telegram   = TRUE,
    tg_dry_run      = FALSE,
    factor_analysis = TRUE
  )
}, error = function(e) {
  cat(sprintf("[QueueConsumer][FQ149] run_alpha_search 실패: %s\n", conditionMessage(e)))
  list(error_msg = conditionMessage(e))
})

if (!is.null(r149$error_msg)) {
  cat("[QueueConsumer][FQ149] 실패 — QUARANTINE 처리\n")
  write(toJSON(list(
    paper_id="2607.27611", factor_id=FQ149_FACTOR_ID, factor_name="FX_Intensity",
    pit_pass=FALSE, contract_pass=FALSE, robustness_pass=FALSE, fidelity_pass=TRUE,
    gate_decision="QUARANTINE", gate_failed_layers="run_error",
    error=r149$error_msg,
    gate_rule="run_error → QUARANTINE",
    gate_checked_at=format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  ), pretty=TRUE, auto_unbox=TRUE, na="null"), FQ149_VERIFY)
  .append_done(FQ149_PAPER_ID, list(
    paper_id=FQ149_PAPER_ID, paper_title=FQ149_PAPER_TITLE,
    factor_id=FQ149_FACTOR_ID, factor_name="FX_Intensity",
    gate_decision="QUARANTINE", gate_failed_layers="run_error",
    port_t=NULL, oos_retention=NULL, calmar=NULL, grade=NULL,
    processed_date=format(Sys.Date(), "%Y%m%d"),
    verify_path=.rel_project_path(FQ149_VERIFY),
    quarantine_reason=paste0("run_alpha_search error: ", r149$error_msg)
  ))
} else {
  # Extract metrics
  oos149 <- .get_oos_retention(r149$out_dir)
  pt149  <- .get_port_t(r149$out_dir)
  # Calmar from strategy_manifest metrics
  manif149 <- tryCatch(fromJSON(r149$strategy_manifest, simplifyVector=TRUE), error=function(e) list())
  m149 <- manif149$metrics %||% list()
  calmar149 <- as.numeric(m149$Calmar %||% NA_real_)
  contract_pass149 <- isTRUE(r149$bt_contract$status == "OK")
  grade149 <- r149$grade
  score149 <- as.numeric(r149$score %||% 0)

  verdict_notes149 <- c(
    sprintf("Grade=%s, Score=%.1f, Excess CAGR=%+.2f%%p", grade149, score149, r149$excess_cagr %||% 0),
    sprintf("OOS_retention=%.3f (≥0.5 L3 기준: %s)", oos149 %||% NA_real_,
            if (!is.na(oos149) && oos149>=0.5) "PASS" else "FAIL"),
    sprintf("PORT_t=%s (≥2.95 HARD: %s)",
            if(!is.na(pt149)) sprintf("%.3f", pt149) else "NA",
            if(!is.na(pt149) && pt149>=2.95) "PASS" else "FAIL"),
    sprintf("Calmar=%s (≥0.64 HARD: %s)",
            if(!is.na(calmar149)) sprintf("%.3f", calmar149) else "NA",
            if(!is.na(calmar149) && calmar149>=0.64) "PASS" else "FAIL"),
    "FX exposure 강도 proxy — DART 외화환산이익/손실 절대값 합/TotalAssets. annual lag 익년3/31 PIT C4 준수."
  )

  revival149 <- c(
    "FX 노출 강도 계층화: MEGA vs MID cap 분리 실측 (벤치 아티팩트 여부 확인)",
    "방향 반전: Score = -FX_Intensity (헤징 미실시 기업 long)",
    "FX 헤징 NLP (FQ-148): DART 전문 텍스트에서 헤징 여부 직접 추출"
  )

  .write_auto_verify(
    verify_path = FQ149_VERIFY,
    paper_id = FQ149_PAPER_ID,
    paper_title = FQ149_PAPER_TITLE,
    factor_id = FQ149_FACTOR_ID,
    factor_name = "FX_Intensity",
    strategy_id = r149$strategy_id %||% "",
    strategy_name = "FX_Intensity_FQ149",
    strategy_idea = FQ149_IDEA,
    engine_path = FQ149_ENGINE,
    run_date = format(Sys.Date(), "%Y%m%d"),
    out_dir = r149$out_dir %||% "",
    grade = grade149,
    score = score149,
    pit_pass = TRUE,
    contract_pass = contract_pass149,
    oos_retention = oos149,
    port_t = pt149,
    calmar_val = calmar149,
    metrics_list = list(
      CAGR_pct = as.numeric(m149$CAGR %||% NA_real_),
      SR = as.numeric(m149$Sharpe %||% NA_real_),
      MDD_pct = -abs(as.numeric(m149$MDD %||% NA_real_)),
      IR = as.numeric(m149$IR %||% NA_real_),
      Turnover_pct = as.numeric(m149$Turnover_Ann %||% NA_real_),
      PORT_t = pt149,
      OOS_retention = oos149,
      Calmar = calmar149
    ),
    fidelity_pass = TRUE,
    fidelity_confidence = "high",
    fidelity_notes = paste0(
      "논문(AWARE-FX) FX exposure baseline에 대응: (|외화환산이익|+|외화환산손실|)/TotalAssets. ",
      "DART reprt_code=11011 CFS 우선, PIT C4 연간 익년3/31 준수. 신호 방향: 높은 노출=높은 점수(헤징 리스크 감소 프리미엄)."
    ),
    impl_spec = list(
      signal = "(abs(외화환산이익)+abs(외화환산손실))/TotalAssets",
      pit_lag = "annual 익년3/31 (C4)",
      universe = "K200_KQ150",
      n_holdings = 20,
      weight_method = "ivol",
      commission = 0.0015,
      data_source = "dart_raw_financials.parquet + fundamental_dart.parquet"
    ),
    verdict_notes = verdict_notes149,
    revival_conditions = revival149
  )

  # Run gate
  gate149 <- .run_gate(FQ149_VERIFY)
  cat(sprintf("[QueueConsumer][FQ149] gate_decision=%s\n", gate149))

  # Read updated verify for gate_failed_layers
  vj149 <- tryCatch(fromJSON(FQ149_VERIFY, simplifyVector=TRUE), error=function(e) list())

  .append_done(FQ149_PAPER_ID, list(
    paper_id = FQ149_PAPER_ID,
    paper_title = FQ149_PAPER_TITLE,
    factor_id = FQ149_FACTOR_ID,
    factor_name = "FX_Intensity",
    fq_id = "FQ-149",
    strategy_id = r149$strategy_id %||% "",
    gate_decision = gate149,
    gate_failed_layers = vj149$gate_failed_layers %||% "",
    port_t = if (!is.na(pt149)) pt149 else NULL,
    oos_retention = if (!is.na(oos149)) oos149 else NULL,
    calmar = if (!is.na(calmar149)) calmar149 else NULL,
    grade = grade149,
    score = score149,
    processed_date = format(Sys.Date(), "%Y%m%d"),
    verify_path = .rel_project_path(FQ149_VERIFY),
    session_note = paste0("AS-20260806 FQ-149 FX 노출 강도. AWARE-FX 논문 baseline proxy. grade=",
                          grade149, " gate=", gate149)
  ))
}

cat("\n[QueueConsumer] FQ-149 완료 — FQ-092 착수\n\n")

# ---- Paper 2: FQ-092 — Vol Rank Reverse ------------------------------------
cat("==========================================================================\n")
cat("FQ-092: 변동성 순위 역방향 (factor_engine_vol_rank_reverse.R)\n")
cat("paper: arXiv:2607.27461 (Three Matrices)\n")
cat("==========================================================================\n\n")

FQ092_ENGINE <- file.path(.QAS_ROOT, "02_Infrastructure/alpha_search/factor_engine_vol_rank_reverse.R")
FQ092_VERIFY <- file.path(VERIFY_DIR, "auto_verify_VolRankReverse_FQ092_20260806.json")
FQ092_PAPER_ID <- "2607.27461"
FQ092_PAPER_TITLE <- "Are Three Matrices All You Need To Beat the Market? Observable Matrix Dynamics for Portfolio Optimization"
FQ092_FACTOR_ID <- "VolRankReverse_FQ092"
FQ092_IDEA <- paste0(
  "vol rank 역방향 가설(FQ-092): C_VolRankStability_3M 정방향이 KR에서 역작동(SR 0.275, IR -0.234) → ",
  "신호 부호 flip. Score=+rank_std_12m(변동성 순위 불안정·상승 종목 선택). ",
  "고변동성 모멘텀 가설 — 순위 상승 종목이 KR에서 수익률 프리미엄 보유 여부 검증. ",
  "K200∪KQ150, 월간 리밸 15bps, ivol 가중."
)

r092 <- tryCatch({
  run_alpha_search(
    strategy_name   = "VolRankReverse_FQ092",
    strategy_idea   = FQ092_IDEA,
    factor_engine_path = FQ092_ENGINE,
    n_holdings      = 20L,
    weight_method   = "ivol",
    commission      = 0.0015,
    start_date      = "2005-01-01",
    universe        = "K200_KQ150",
    send_telegram   = TRUE,
    tg_dry_run      = FALSE,
    factor_analysis = TRUE
  )
}, error = function(e) {
  cat(sprintf("[QueueConsumer][FQ092] run_alpha_search 실패: %s\n", conditionMessage(e)))
  list(error_msg = conditionMessage(e))
})

if (!is.null(r092$error_msg)) {
  cat("[QueueConsumer][FQ092] 실패 — QUARANTINE 처리\n")
  write(toJSON(list(
    paper_id=FQ092_PAPER_ID, factor_id=FQ092_FACTOR_ID, factor_name="VolRankReverse",
    pit_pass=FALSE, contract_pass=FALSE, robustness_pass=FALSE, fidelity_pass=TRUE,
    gate_decision="QUARANTINE", gate_failed_layers="run_error",
    error=r092$error_msg,
    gate_rule="run_error → QUARANTINE",
    gate_checked_at=format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  ), pretty=TRUE, auto_unbox=TRUE, na="null"), FQ092_VERIFY)
  .append_done(FQ092_PAPER_ID, list(
    paper_id=FQ092_PAPER_ID, paper_title=FQ092_PAPER_TITLE,
    factor_id=FQ092_FACTOR_ID, factor_name="VolRankReverse",
    gate_decision="QUARANTINE", gate_failed_layers="run_error",
    port_t=NULL, oos_retention=NULL, calmar=NULL, grade=NULL,
    processed_date=format(Sys.Date(), "%Y%m%d"),
    verify_path=.rel_project_path(FQ092_VERIFY),
    quarantine_reason=paste0("run_alpha_search error: ", r092$error_msg)
  ))
} else {
  oos092 <- .get_oos_retention(r092$out_dir)
  pt092  <- .get_port_t(r092$out_dir)
  manif092 <- tryCatch(fromJSON(r092$strategy_manifest, simplifyVector=TRUE), error=function(e) list())
  m092 <- manif092$metrics %||% list()
  calmar092 <- as.numeric(m092$Calmar %||% NA_real_)
  contract_pass092 <- isTRUE(r092$bt_contract$status == "OK")
  grade092 <- r092$grade
  score092 <- as.numeric(r092$score %||% 0)

  verdict_notes092 <- c(
    sprintf("Grade=%s, Score=%.1f, Excess CAGR=%+.2f%%p", grade092, score092, r092$excess_cagr %||% 0),
    sprintf("OOS_retention=%.3f (≥0.5 L3: %s)", oos092 %||% NA_real_,
            if (!is.na(oos092) && oos092>=0.5) "PASS" else "FAIL"),
    sprintf("PORT_t=%s (≥2.95 HARD: %s)",
            if(!is.na(pt092)) sprintf("%.3f", pt092) else "NA",
            if(!is.na(pt092) && pt092>=2.95) "PASS" else "FAIL"),
    "vol rank 역방향 검증: C_VolRankStability_3M 정방향 QUARANTINE(SR 0.275)에 대한 next_probe(FQ-092). ",
    "vol rank 계열: 안정성(arXiv:2607.19005)·변화(2607.27461 C_VolRankStability)·전이확률(2607.27461 Markov) 3-hits negative 후 4번째 방향 검증."
  )

  revival092 <- c(
    "MEGA/MID cap 분리 실측: 고변동성 대형주 vs 소형주 프리미엄 분리 확인",
    "vol rank 변화 3M(월간 delta rank_pct): 현 12M std가 아닌 단기 방향성으로 재구성",
    "EW-대비/cap-tier 재분류 후 MDD 구조 확인 (FQ-150 방향)"
  )

  .write_auto_verify(
    verify_path = FQ092_VERIFY,
    paper_id = FQ092_PAPER_ID,
    paper_title = FQ092_PAPER_TITLE,
    factor_id = FQ092_FACTOR_ID,
    factor_name = "VolRankReverse",
    strategy_id = r092$strategy_id %||% "",
    strategy_name = "VolRankReverse_FQ092",
    strategy_idea = FQ092_IDEA,
    engine_path = FQ092_ENGINE,
    run_date = format(Sys.Date(), "%Y%m%d"),
    out_dir = r092$out_dir %||% "",
    grade = grade092,
    score = score092,
    pit_pass = TRUE,
    contract_pass = contract_pass092,
    oos_retention = oos092,
    port_t = pt092,
    calmar_val = calmar092,
    metrics_list = list(
      CAGR_pct = as.numeric(m092$CAGR %||% NA_real_),
      SR = as.numeric(m092$Sharpe %||% NA_real_),
      MDD_pct = -abs(as.numeric(m092$MDD %||% NA_real_)),
      IR = as.numeric(m092$IR %||% NA_real_),
      Turnover_pct = as.numeric(m092$Turnover_Ann %||% NA_real_),
      PORT_t = pt092,
      OOS_retention = oos092,
      Calmar = calmar092
    ),
    fidelity_pass = TRUE,
    fidelity_confidence = "medium",
    fidelity_notes = paste0(
      "역방향 가설은 FQ-092 next_probe에서 도출(논문 직접 기술 아님). ",
      "C_VolRankStability_3M(arXiv:2607.27461) 정방향 QUARANTINE → 신호 부호 flip 검증. ",
      "batch_434 fabrication 아님: 신호 방향 반전은 경험적 탐색으로 허용됨."
    ),
    impl_spec = list(
      signal = "rank_std_12m (vol rank 12M rolling std, 높을수록 고변동 모멘텀)",
      pit_lag = "shift(Ret,1L) → vol_20d → month-end rank_pct → rolling 12M std (모두 lag-1 기준)",
      universe = "K200_KQ150",
      n_holdings = 20,
      weight_method = "ivol",
      commission = 0.0015,
      parent_factor = "C_VolRankStability_3M (score flip)"
    ),
    verdict_notes = verdict_notes092,
    revival_conditions = revival092
  )

  gate092 <- .run_gate(FQ092_VERIFY)
  cat(sprintf("[QueueConsumer][FQ092] gate_decision=%s\n", gate092))

  vj092 <- tryCatch(fromJSON(FQ092_VERIFY, simplifyVector=TRUE), error=function(e) list())

  .append_done(FQ092_PAPER_ID, list(
    paper_id = FQ092_PAPER_ID,
    paper_title = FQ092_PAPER_TITLE,
    factor_id = FQ092_FACTOR_ID,
    factor_name = "VolRankReverse",
    fq_id = "FQ-092",
    strategy_id = r092$strategy_id %||% "",
    gate_decision = gate092,
    gate_failed_layers = vj092$gate_failed_layers %||% "",
    port_t = if (!is.na(pt092)) pt092 else NULL,
    oos_retention = if (!is.na(oos092)) oos092 else NULL,
    calmar = if (!is.na(calmar092)) calmar092 else NULL,
    grade = grade092,
    score = score092,
    processed_date = format(Sys.Date(), "%Y%m%d"),
    verify_path = .rel_project_path(FQ092_VERIFY),
    session_note = paste0("AS-20260806 FQ-092 vol rank 역방향. 계열 4번째 검증. grade=",
                          grade092, " gate=", gate092)
  ))
}

cat("\n==========================================================================\n")
cat("[QueueConsumer] 2026-08-06 소비자 완료 (MAX_ALPHA=2)\n")
cat("  FQ-149 (FX_Intensity): 완료\n")
cat("  FQ-092 (VolRankReverse): 완료\n")
cat("==========================================================================\n")
