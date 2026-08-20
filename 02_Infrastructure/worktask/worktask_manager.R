#==============================================================================
# QEPM Work Task Manager — v1.0
# 2026-04-23 Session 69 Day 1
#
# 1 Work Task = QEPM Full Pipeline 1회 = Alpha → Risk → Optimizer → Forge → Judge → Governor
#
# Usage:
#   source("02_Infrastructure/worktask/worktask_manager.R")
#   wt_create(hypothesis = "Rate Hedge Defense", universe = "KOSPI200_KOSDAQ150_intersection")
#   wt_status("WT20260423_001")
#   wt_advance("WT20260423_001", "ALPHA_DONE")
#==============================================================================

suppressPackageStartupMessages({
  library(jsonlite)
  library(data.table)
})

WT_ROOT <- "qepm/mailbox/worktask"
WT_SCHEMA <- "02_Infrastructure/worktask/schema.json"
WT_CONSTRAINT_DEFAULTS <- "02_Infrastructure/worktask/constraint_defaults.json"

# ─── WT ID 생성 (v1.2 wt_type 4-prefix Charter §10) ───────────────────
# WT-D = Discovery, WT-P = Deployment, WT-S = Sizing-only, WT-H = Hyperparameter-sweep
wt_generate_id <- function(wt_type = "discovery") {
  today <- format(Sys.Date(), "%Y%m%d")
  prefix <- switch(wt_type,
    "discovery" = "WT-D",
    "deployment" = "WT-P",
    "sizing_only" = "WT-S",
    "hyperparameter_sweep" = "WT-H",
    stop(sprintf("[wt_generate_id] Unknown wt_type: %s. Charter §10 enum: discovery/deployment/sizing_only/hyperparameter_sweep", wt_type))
  )
  existing <- list.files(WT_ROOT, pattern = sprintf("^%s%s_", prefix, today))
  seq <- length(existing) + 1
  sprintf("%s%s_%03d", prefix, today, seq)
}

# ─── WT 디렉토리 + request.json 생성 ─────────────────────
# v6.1 R1+R13: wt_type 분기 + Discovery/Deployment 이원화
#   wt_type="discovery" → Soft 제약 면제, breadth 허용, alpha 존재 확인 목적
#   wt_type="deployment" → 모든 제약 강제, production 편성 목적
# theme만 주고 hypothesis_title=NULL이면 Alpha Agent Step 0 (Hypothesis Discovery) 자동 활성화
wt_create <- function(hypothesis_title = NULL,
                       theme = NULL,
                       wt_type = "discovery",
                       discovery_of = NULL,
                       hypothesis_description = "",
                       universe = "KOSPI200_KOSDAQ150_intersection",
                       benchmark = "KOSPI200_total_return",
                       as_of_date = Sys.Date(),
                       forecast_horizon = "1M",
                       rebalance_frequency = "monthly",
                       current_portfolio = "STR_1631_80_STR_1656_20",
                       long_only = NULL,
                       max_names = NULL,
                       override_constraints = NULL) {

  if (is.null(hypothesis_title) && is.null(theme)) {
    stop("[wt_create] hypothesis_title 또는 theme 중 최소 하나 필요")
  }
  # v1.2 Charter §10: wt_type 4-way enum
  if (!wt_type %in% c("discovery", "deployment", "sizing_only", "hyperparameter_sweep")) {
    stop("[wt_create] wt_type must be one of: 'discovery', 'deployment', 'sizing_only', 'hyperparameter_sweep' (Charter §10)")
  }
  if (wt_type == "deployment" && is.null(discovery_of)) {
    warning("[wt_create] Deployment WT without discovery_of — graduation_criteria 우회 허용 (검증 완료된 alpha 직접 편성 목적).")
  }
  # v1.2 Charter §10: sizing_only / hyperparameter_sweep은 parent inheritance 필수
  if (wt_type %in% c("sizing_only", "hyperparameter_sweep") && is.null(discovery_of)) {
    warning(sprintf("[wt_create] %s WT는 parent inheritance (discovery_of) 명시 권장. alpha_discovery_certificate 미발급 → PG1 admission 자격 없음 (정상 동작).", wt_type))
  }

  task_id <- wt_generate_id(wt_type = wt_type)
  wt_dir <- file.path(WT_ROOT, task_id)
  dir.create(wt_dir, recursive = TRUE, showWarnings = FALSE)

  # [2026-08-02] stage_artifacts 정본 디렉토리를 생성 시점에 미리 만든다.
  #  실사고: 같은 날 에이전트들이 WT-D...(하이픈) / WT_D...(언더스코어) 표기를 제각각 써서
  #  ① Q-Lead 가 실존 산출물(13파일)을 "산출 0"으로 오판 ② state_machine 아티팩트 검사와
  #  경로가 갈릴 뻔했다. 규약 문서는 갈림을 못 막는다 — **디렉토리가 이미 존재하면 에이전트는
  #  고를 필요가 없다**(정본 = artifact_contract.json "stage_artifacts/WT_{ID}/" 의 언더스코어형).
  # (WT_ROOT 와 동일하게 프로젝트 루트 기준 상대경로 — 이 파일은 루트 wd 실행이 전제)
  sa_dir <- file.path("stage_artifacts", gsub("^WT[-_]", "WT_", task_id))
  dir.create(sa_dir, recursive = TRUE, showWarnings = FALSE)

  # 기본 제약 로드 (v6.1 3-tier)
  defaults <- fromJSON(WT_CONSTRAINT_DEFAULTS, simplifyVector = FALSE)

  # Hypothesis source 결정
  hyp_source <- if (!is.null(hypothesis_title)) "user_defined" else "alpha_agent_discovered"

  # v6.1 R1+R13: wt_type별 제약 분기
  # v1.2 Charter §10: 4-way wt_type branching + pg1_eligibility
  if (wt_type == "discovery") {
    # Discovery: HARD만, SOFT는 null (breadth 허용)
    liquidity_floor <- defaults$tier_hard_mandate$liquidity_floor_won_20d_avg
    effective_max_names <- if (!is.null(max_names)) max_names else NULL
    effective_long_only <- if (!is.null(long_only)) long_only else "configurable"
    effective_bounds <- defaults$discovery_defaults$weight_bounds
    pg1_eligibility <- "certificate_required"  # alpha_discovery_certificate 발급 받아야 진행
  } else if (wt_type == "deployment") {
    # Deployment: HARD + SOFT 모두 강제
    liquidity_floor <- defaults$tier_soft_deployment$liquidity_min_won_20d_avg
    # (2026-08-20) 하드코딩 제거 — 정본은 이미 defaults 로 로드돼 있고, 같은 블록의
    #   liquidity_floor·weight_bounds 는 이미 그것을 읽는다. max_names 만 값을 복제하면서
    #   주석으로 "constraint_defaults.json 정합" 을 *주장*했다 — 정합을 강제하지 않는
    #   주석은 드리프트 경로다(2026-05-29 20→25 변경이 이곳을 수동으로 따라와야 했다).
    #   정본 결측 시에만 25L 폴백(회귀 없음).
    #   ★`$` 는 리스트에서 **부분 일치**를 한다 — max_names 가 빠지면 max_names_rationale
    #   (문자열)에 매칭돼 as.integer 가 NA 를 낸다(폴백이 아니라 그럴듯한 쓰레기).
    #   검사가 도입 당일 이걸 잡았다. [[ ]] 는 기본이 정확 일치라 안전.
    .wt_mn <- defaults[["tier_soft_deployment"]][["max_names"]]
    effective_max_names <- if (is.null(.wt_mn)) 25L else as.integer(.wt_mn)
    effective_long_only <- TRUE
    effective_bounds <- defaults$tier_soft_deployment$weight_bounds
    pg1_eligibility <- "deployment_track"  # 검증 alpha 직접 편성
  } else {
    # sizing_only / hyperparameter_sweep: parent inheritance만, alpha 0건이 정상
    liquidity_floor <- defaults$tier_soft_deployment$liquidity_min_won_20d_avg
    # (2026-08-20) 하드코딩 제거 — 정본은 이미 defaults 로 로드돼 있고, 같은 블록의
    #   liquidity_floor·weight_bounds 는 이미 그것을 읽는다. max_names 만 값을 복제하면서
    #   주석으로 "constraint_defaults.json 정합" 을 *주장*했다 — 정합을 강제하지 않는
    #   주석은 드리프트 경로다(2026-05-29 20→25 변경이 이곳을 수동으로 따라와야 했다).
    #   정본 결측 시에만 25L 폴백(회귀 없음).
    #   ★`$` 는 리스트에서 **부분 일치**를 한다 — max_names 가 빠지면 max_names_rationale
    #   (문자열)에 매칭돼 as.integer 가 NA 를 낸다(폴백이 아니라 그럴듯한 쓰레기).
    #   검사가 도입 당일 이걸 잡았다. [[ ]] 는 기본이 정확 일치라 안전.
    .wt_mn <- defaults[["tier_soft_deployment"]][["max_names"]]
    effective_max_names <- if (is.null(.wt_mn)) 25L else as.integer(.wt_mn)
    effective_long_only <- TRUE
    effective_bounds <- defaults$tier_soft_deployment$weight_bounds
    pg1_eligibility <- "certificate_required"  # alpha_discovery_certificate 미발급 → passive deny
  }

  # Request 조립
  request <- list(
    task_id = task_id,
    wt_type = wt_type,
    pg1_eligibility = pg1_eligibility,  # v1.2 Charter §10 Certification System
    discovery_of = discovery_of,
    graduation_criteria = defaults$tier_graduation,
    theme = theme,
    hypothesis_title = hypothesis_title,
    hypothesis_description = hypothesis_description,
    hypothesis_source = hyp_source,
    as_of_date = format(as.Date(as_of_date), "%Y-%m-%d"),
    forecast_horizon = forecast_horizon,
    rebalance_frequency = rebalance_frequency,
    universe_definition = list(
      label = universe,
      liquidity_min_won_20d_avg = liquidity_floor,
      # KR_ALL_LIQ2E8 = 전종목(LIQ 2e8 필터, ~2005종목 시변) — 도훈 mandate 2026-06-02 (2026-06-10 배선)
      max_names_total = if (identical(universe, "KR_ALL_LIQ2E8")) 2100L else 500L
    ),
    benchmark_definition = benchmark,
    data_lag_rules = defaults$tier_hard_mandate$data_lag_rules_default,
    cost_model_version = defaults$tier_soft_deployment$cost_model_version,
    current_portfolio = current_portfolio,
    hard_mandate = list(
      pit_enforcement = "C1-C15 all enforced",
      liquidity_floor_won_20d_avg = defaults$tier_hard_mandate$liquidity_floor_won_20d_avg,
      mandate_restrictions = defaults$tier_hard_mandate$mandate_restrictions,
      long_only_mandate = effective_long_only
    ),
    hard_constraints = list(
      max_names = effective_max_names,
      weight_bounds = effective_bounds,
      sector_active_weight_cap = if (wt_type == "deployment") defaults$tier_soft_deployment$sector_active_weight_cap else NULL,
      liquidity_min_won_20d_avg = liquidity_floor
    ),
    soft_penalties = if (wt_type == "deployment") list(
      turnover_cap_annual = defaults$tier_soft_deployment$turnover_cap_annual,
      beta_target = 1.0,
      style_exposure_cap = 2.0
    ) else list(),
    capacity_limits = list(
      adv_multiplier = defaults$tier_soft_deployment$capacity_adv_multiplier,
      capacity_max_aum_won = 100e9
    )
  )

  # Override constraints (사용자 정의)
  if (!is.null(override_constraints)) {
    for (k in names(override_constraints)) {
      request$hard_constraints[[k]] <- override_constraints[[k]]
    }
  }

  # request.json 저장
  write_json(request, file.path(wt_dir, "request.json"),
             pretty = TRUE, auto_unbox = TRUE, null = "null")

  # status.json 초기화
  status <- list(
    task_id = task_id,
    current_phase = "SPEC_APPROVED",
    updated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    blocker = NULL
  )
  write_json(status, file.path(wt_dir, "status.json"),
             pretty = TRUE, auto_unbox = TRUE, null = "null")

  # governance_log 초기화
  display_title <- if (!is.null(hypothesis_title)) hypothesis_title else sprintf("[theme] %s (Alpha Agent 자동 발굴)", theme)
  gov_log <- list(
    task_id = task_id,
    events = list(list(
      timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
      agent = "q-lead",
      action = "WT_CREATED",
      summary = sprintf("Work Task 생성: %s | source=%s", display_title, hyp_source)
    ))
  )
  write_json(gov_log, file.path(wt_dir, "governance_log.json"),
             pretty = TRUE, auto_unbox = TRUE, null = "null")

  cat(sprintf("[wt_create] %s 생성 완료: %s\n", task_id, wt_dir))
  cat(sprintf("  WT Type: %s\n", toupper(wt_type)))
  if (!is.null(hypothesis_title)) {
    cat(sprintf("  Hypothesis: %s (user_defined)\n", hypothesis_title))
  } else {
    cat(sprintf("  Theme: %s (alpha_agent_discovered mode)\n", theme))
    cat("  → Alpha Agent Step 0 Hypothesis Discovery 활성화\n")
  }
  if (!is.null(discovery_of)) {
    cat(sprintf("  Discovery parent: %s\n", discovery_of))
  }
  cat(sprintf("  Universe: %s\n", universe))
  cat(sprintf("  Constraints tier: %s\n",
              if (wt_type == "discovery") "HARD mandate only (SOFT 면제, breadth 허용)" else "HARD + SOFT (25종/20%%/15bps 전부 강제)"))
  cat(sprintf("  Current phase: SPEC_APPROVED (Alpha Agent 대기)\n"))

  invisible(task_id)
}

# ─── Graduation 검증 (Discovery → Deployment 전환 조건) ──
wt_check_graduation <- function(task_id) {
  wt_dir <- file.path(WT_ROOT, task_id)
  if (!dir.exists(wt_dir)) stop(sprintf("[graduation] %s 없음", task_id))

  req_path <- file.path(wt_dir, "request.json")
  req <- if (file.exists(req_path)) {
    fromJSON(req_path, simplifyVector = FALSE)
  } else {
    # v1.7 fallback — request.json 부재 (legacy WT) 시 governor_admission.json에서 wt_type 추론
    ga_path_fallback <- file.path(wt_dir, "governor_admission.json")
    if (file.exists(ga_path_fallback)) {
      ga_fb <- tryCatch(fromJSON(ga_path_fallback, simplifyVector = FALSE),
                        error = function(e) NULL)
      list(
        wt_type = if (!is.null(ga_fb)) ga_fb$wt_type %||% "unknown" else "unknown",
        pg1_eligibility = NULL,
        graduation_criteria = NULL,
        legacy_fallback = TRUE
      )
    } else {
      cat(sprintf("[graduation] %s — request.json + governor_admission.json 모두 부재\n", task_id))
      return(invisible(list(pass = FALSE, reason = "no_request_or_admission",
                            task_id = task_id)))
    }
  }

  # v1.2 Charter §10: sizing_only / hyperparameter_sweep은 graduation 자격 없음 (passive deny)
  if (req$wt_type %in% c("sizing_only", "hyperparameter_sweep")) {
    cat(sprintf("[graduation] %s WT — alpha_discovery_certificate 발급 불필요 (정상). PG1 admission 자격 없음.\n", req$wt_type))
    return(invisible(list(
      pass = FALSE,
      reason = "wt_type_not_eligible_for_pg1_admission",
      wt_type = req$wt_type,
      pg1_eligibility = req$pg1_eligibility,
      charter_ref = "v1.2 §10 Role Card"
    )))
  }

  # v1.7 Charter §10: deployment WT — 4 cert (sr_provenance + schedule_fidelity +
  # forge_package_validated + governor_concord) 자체 발급 의무 + alpha_discovery는
  # discovery WT inherit. cert_backfill_audit.R 자동 호출 가능 (ELIGIBLE_FOR_ISSUANCE 명시 시).
  if (req$wt_type == "deployment") {
    cat(sprintf("=== Deployment WT Cert Check: %s ===\n", task_id))
    governor_dir <- file.path(dirname(WT_ROOT), "governor")
    cert_status <- list(
      sr_provenance = file.exists(file.path(wt_dir, "sr_provenance_certificate.json")),
      schedule_fidelity = file.exists(file.path(wt_dir, "schedule_fidelity_certificate.json")),
      forge_package_validated = file.exists(file.path(wt_dir, "forge_package_validated_certificate.json")),
      governor_concord = file.exists(file.path(governor_dir, "governor_concord_certificate.json")) ||
                         file.exists(file.path(governor_dir, "governor_concord_with_waiver_certificate.json"))
    )
    issued_count <- sum(unlist(cert_status))
    for (nm in names(cert_status)) {
      cat(sprintf("  %s: %s\n", nm,
                  if (isTRUE(cert_status[[nm]])) "ISSUED" else "MISSING"))
    }
    cat(sprintf("Issued: %d/4\n", issued_count))

    # Governor의 ELIGIBLE_FOR_ISSUANCE 명시 확인 (cert_backfill_audit.R 자동 호출 trigger)
    ga_path <- file.path(wt_dir, "governor_admission.json")
    eligibility_hint <- FALSE
    if (file.exists(ga_path)) {
      ga <- tryCatch(fromJSON(ga_path, simplifyVector = FALSE), error = function(e) NULL)
      if (!is.null(ga)) {
        pg1_check <- ga$pg1_admission_check %||% list()
        for (key in c("sr_provenance_certificate", "schedule_fidelity_certificate",
                      "forge_package_validated_certificate")) {
          status <- (pg1_check[[key]] %||% list())$issuance_status
          if (!is.null(status) && grepl("ELIGIBLE", status, ignore.case = TRUE)) {
            eligibility_hint <- TRUE; break
          }
        }
      }
    }

    pass <- issued_count >= 3  # 최소 3/4 (schedule_fidelity는 weights.csv 없는 archived deployment 면제 가능)
    if (!pass && eligibility_hint) {
      cat("[graduation] Deployment WT cert 부족 + Governor ELIGIBLE 명시 — cert_backfill_audit.R --auto 권장\n")
      cat(sprintf("  Rscript 02_Infrastructure/ops/cert_backfill_audit.R --target=%s --auto\n", task_id))
    }

    return(invisible(list(
      pass = pass,
      reason = if (pass) "deployment_cert_pass" else "deployment_cert_insufficient",
      wt_type = "deployment",
      cert_status = cert_status,
      issued_count = issued_count,
      eligibility_hint = eligibility_hint,
      backfill_recommended = !pass && eligibility_hint,
      charter_ref = "v1.7 §10 Role Card deployment"
    )))
  }

  if (req$wt_type != "discovery") {
    cat("[graduation] Discovery WT만 해당\n")
    return(invisible(list(pass = NA, reason = "not_discovery_wt")))
  }

  alpha_path <- file.path(wt_dir, "alpha_package.json")
  if (!file.exists(alpha_path)) {
    return(list(pass = FALSE, reason = "alpha_package missing"))
  }

  alpha_pkg <- fromJSON(alpha_path, simplifyVector = FALSE)
  criteria <- req$graduation_criteria
  diag <- alpha_pkg$diagnostics

  # v1.2 Charter §10: alpha_discovery_certificate 보유 확인 (PG1 admission 자격 게이트)
  # Hook이 sibling file에 발급한 경우 우선 확인
  cert <- alpha_pkg$alpha_discovery_certificate
  sibling_cert_path <- file.path(wt_dir, "alpha_discovery_certificate.json")
  if ((is.null(cert) || !isTRUE(cert$issued)) && file.exists(sibling_cert_path)) {
    cert <- fromJSON(sibling_cert_path, simplifyVector = FALSE)
  }
  certificate_check <- list(
    actual = if (!is.null(cert) && isTRUE(cert$issued)) "ISSUED" else "NOT_ISSUED",
    threshold = "ISSUED",
    pass = (!is.null(cert) && isTRUE(cert$issued))
  )
  if (!isTRUE(certificate_check$pass)) {
    cat(sprintf("[graduation] %s — alpha_discovery_certificate NOT_ISSUED. PG1 admission 자격 박탈 (Charter §10 passive deny).\n", task_id))
    if (!is.null(cert) && !is.null(cert$non_issuance_reason)) {
      cat(sprintf("  미발급 사유: %s\n", cert$non_issuance_reason))
    }
    return(invisible(list(
      pass = FALSE,
      reason = "certificate_not_issued",
      task_id = task_id,
      certificate_check = certificate_check,
      remediation = "alpha agent rerun + mechanism citation ≥ 50 chars + factor_specs ≥ 1 + harvey_t pass ≥ 3 + alpha_inheritance_cor < 0.95"
    )))
  }

  checks <- list(
    rank_ic = list(
      actual = diag$rank_ic %||% 0,
      threshold = criteria$min_rank_ic,
      pass = (diag$rank_ic %||% 0) >= criteria$min_rank_ic
    ),
    icir = list(
      actual = diag$icir %||% 0,
      threshold = criteria$min_icir,
      pass = (diag$icir %||% 0) >= criteria$min_icir
    ),
    subperiod_stability = list(
      actual = diag$subperiod_stability %||% 0,
      threshold = criteria$min_subperiod_stability,
      pass = (diag$subperiod_stability %||% 0) >= criteria$min_subperiod_stability
    ),
    harvey_t = list(
      actual = diag$harvey_t_stat %||% 0,
      threshold = criteria$min_harvey_t_stat,
      pass = (diag$harvey_t_stat %||% 0) >= criteria$min_harvey_t_stat
    )
  )

  all_pass <- all(sapply(checks, function(x) isTRUE(x$pass)))

  result <- list(
    pass = all_pass,
    task_id = task_id,
    checks = checks
  )

  cat(sprintf("=== Graduation Check: %s ===\n", task_id))
  for (nm in names(checks)) {
    c <- checks[[nm]]
    cat(sprintf("  %s: actual=%.4f / threshold=%.4f | %s\n",
                nm, c$actual, c$threshold,
                if (isTRUE(c$pass)) "PASS" else "FAIL"))
  }
  cat(sprintf("Overall: %s\n", if (all_pass) "GRADUATION PASS" else "NOT READY FOR DEPLOYMENT"))

  invisible(result)
}

`%||%` <- function(a, b) {
  if (is.null(a)) return(b)
  if (is.atomic(a) && length(a) == 1 && is.na(a)) return(b)
  a
}

# ─── WT 상태 조회 ───────────────────────────────────────
wt_status <- function(task_id) {
  wt_dir <- file.path(WT_ROOT, task_id)
  if (!dir.exists(wt_dir)) {
    stop(sprintf("[wt_status] WT %s 존재하지 않음", task_id))
  }

  status_path <- file.path(wt_dir, "status.json")
  if (!file.exists(status_path)) {
    stop(sprintf("[wt_status] %s/status.json 없음", task_id))
  }

  status <- fromJSON(status_path, simplifyVector = TRUE)

  cat(sprintf("=== %s ===\n", task_id))
  cat(sprintf("  Phase: %s\n", status$current_phase))
  cat(sprintf("  Updated: %s\n", status$updated_at))
  if (!is.null(status$blocker) && nchar(status$blocker) > 0) {
    cat(sprintf("  Blocker: %s\n", status$blocker))
  }

  # 존재 artifact 확인
  artifacts <- list(
    alpha_package = file.exists(file.path(wt_dir, "alpha_package.json")),
    risk_package = file.exists(file.path(wt_dir, "risk_package.json")),
    optimization_package = file.exists(file.path(wt_dir, "optimization_package.json"))
  )
  cat("  Packages:\n")
  for (nm in names(artifacts)) {
    cat(sprintf("    %s: %s\n", nm, if (artifacts[[nm]]) "✓" else "✗"))
  }

  invisible(status)
}

# ─── WT 단계 전이 ────────────────────────────────────────
# v7.0 Sprint 1 — sm_validated_advance() 위임 강제. transition table + artifact + waiver 검증 통과 시만 phase 변경.
# 우회 불가: state_machine.R 미통합 phase 변경 차단.
# Charter v1.2 §10 GOVERNOR_REJECTED → GOVERNOR_ADMITTED 케이스는 자동 force_waiver=TRUE + challenge_round 증가 + wt_log_user_override() 의무 안내.
wt_advance <- function(task_id, new_phase, blocker = NULL) {
  wt_dir <- file.path(WT_ROOT, task_id)
  if (!dir.exists(wt_dir)) stop(sprintf("[wt_advance] %s 없음", task_id))

  status_path <- file.path(wt_dir, "status.json")
  status <- fromJSON(status_path, simplifyVector = TRUE)
  old_phase <- status$current_phase

  # ── v7.0 Sprint 1: state_machine 위임 (single source 검증) ──
  sm_path <- "02_Infrastructure/worktask/state_machine.R"
  if (!exists("sm_validated_advance", mode = "function")) {
    if (file.exists(sm_path)) {
      source(sm_path, local = FALSE)
    } else {
      stop(sprintf("[wt_advance] state_machine.R 부재 — v7.0 Sprint 1 강제 위임 불가: %s", sm_path))
    }
  }

  # GOVERNOR_REJECTED → GOVERNOR_ADMITTED는 transition table에 없음 (정당한 user override).
  # Charter v1.2 §10 — challenge_round + waiver 5-row 의무. force_waiver=TRUE로 sm 통과.
  override_event <- isTRUE(old_phase == "GOVERNOR_REJECTED") && isTRUE(new_phase == "GOVERNOR_ADMITTED")

  # state machine 검증 — transition + artifact + waiver. 실패 시 stop().
  sm_result <- tryCatch(
    sm_validated_advance(
      wt_id = task_id,
      from = old_phase,
      to = new_phase,
      force_waiver = override_event
    ),
    error = function(e) {
      stop(sprintf("[wt_advance] state_machine BLOCKED %s: %s -> %s | %s",
                   task_id, old_phase, new_phase, conditionMessage(e)))
    }
  )

  status$current_phase <- new_phase
  status$updated_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  status$blocker <- blocker
  if (is.null(status$challenge_round)) status$challenge_round <- 0L
  if (is.null(status$challenge_history)) status$challenge_history <- list()

  # v1.2 Charter §10: GOVERNOR_REJECTED → GOVERNOR_ADMITTED 직접 전이 시 challenge_round + 1 + flag
  if (override_event) {
    status$challenge_round <- as.integer(status$challenge_round) + 1L
    status$last_governor_override_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
    cat(sprintf("[wt_advance] ⚠ GOVERNOR_REJECTED → GOVERNOR_ADMITTED user override (force_waiver=TRUE). challenge_round=%d. wt_log_user_override() 호출 의무 (waiver 5-row 명시).\n",
                status$challenge_round))
  }

  write_json(status, status_path, pretty = TRUE, auto_unbox = TRUE, null = "null")

  # governance_log 업데이트
  gov_path <- file.path(wt_dir, "governance_log.json")
  gov <- fromJSON(gov_path, simplifyVector = FALSE)
  action_label <- if (override_event) "PHASE_ADVANCE_VIA_GOVERNOR_OVERRIDE" else "PHASE_ADVANCE"
  gov$events[[length(gov$events) + 1]] <- list(
    timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    agent = "q-lead",
    action = action_label,
    summary = sprintf("%s -> %s%s", old_phase, new_phase,
                      if (override_event) sprintf(" (challenge_round=%d, waiver 5-row 명시 의무)",
                                                   status$challenge_round) else "")
  )
  write_json(gov, gov_path, pretty = TRUE, auto_unbox = TRUE, null = "null")

  cat(sprintf("[wt_advance] %s: %s -> %s\n", task_id, old_phase, new_phase))
  invisible(new_phase)
}

# ─── wt_log_user_override (v1.2 Charter §10 Governor Concord Waiver) ──
# Governor REJECTED scenario를 user override로 진행 시 challenge entry 강제.
# book_state.json 변경과 별도로 governance_log에 risk waiver 5-row 명시.
# Reference: STR_1715 OVERRIDE_005/006 — Governor Option B Probe 10pct REJECTED 우회 사고.
wt_log_user_override <- function(task_id, override_id, directive,
                                 waiver_checklist = list(),
                                 schedule_review_days = c(1, 7)) {
  wt_dir <- file.path(WT_ROOT, task_id)
  if (!dir.exists(wt_dir)) stop(sprintf("[wt_log_user_override] %s 없음", task_id))

  required_keys <- c("stress_negative_acknowledged", "lockbox_divergence_acknowledged",
                     "ax_triangulation_2of3_acknowledged",
                     "tdc_diversification_forfeit_acknowledged",
                     "to_marginal_acknowledged")
  missing_keys <- setdiff(required_keys, names(waiver_checklist))
  if (length(missing_keys) > 0) {
    warning(sprintf("[wt_log_user_override] waiver_checklist 5-row 누락: %s. governor_concord_with_waiver_certificate 발급 불가.",
                    paste(missing_keys, collapse = ", ")))
  }

  gov_path <- file.path(wt_dir, "governance_log.json")
  gov <- fromJSON(gov_path, simplifyVector = FALSE)
  gov$events[[length(gov$events) + 1]] <- list(
    timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    agent = "user",
    action = "USER_OVERRIDE_WITH_WAIVER",
    override_id = override_id,
    directive_quote = directive,
    waiver_5row = waiver_checklist,
    schedule_review_days = schedule_review_days,
    charter_ref = "v1.2 §10 Governor Concord Waiver"
  )
  write_json(gov, gov_path, pretty = TRUE, auto_unbox = TRUE, null = "null")

  cat(sprintf("[wt_log_user_override] %s | override=%s | waiver_5row keys=%d/5\n",
              task_id, override_id, length(intersect(names(waiver_checklist), required_keys))))
  if (length(missing_keys) == 0) {
    cat("  ✓ waiver 5-row 완전. governor_concord_with_waiver_certificate 발급 자격.\n")
  } else {
    cat(sprintf("  ⚠ 누락 %d종 — concord_pending. 추가 명시 후 재호출.\n", length(missing_keys)))
  }
  invisible(missing_keys)
}

# ─── Challenge Loop (R3) ────────────────────────────────
# Risk/Optimizer 에이전트가 Alpha/Risk 설계에 반론 제기.
# challenge_round >= 3 시 Hook이 block → Q-Lead 수동 개입.
# wt_challenge(task_id, from_agent, to_agent, reason)
wt_challenge <- function(task_id, from_agent, to_agent, reason) {
  stopifnot(from_agent %in% c("risk", "optimizer"))
  stopifnot(to_agent %in% c("alpha", "risk"))

  wt_dir <- file.path(WT_ROOT, task_id)
  if (!dir.exists(wt_dir)) stop(sprintf("[wt_challenge] %s 없음", task_id))
  status_path <- file.path(wt_dir, "status.json")
  status <- fromJSON(status_path, simplifyVector = FALSE)

  round_n <- (status$challenge_round %||% 0L) + 1L
  if (is.null(status$challenge_history)) status$challenge_history <- list()

  new_phase <- switch(to_agent,
    "alpha" = "ALPHA_REVISE_REQUIRED",
    "risk" = "RISK_REVISE_REQUIRED"
  )

  status$current_phase <- new_phase
  status$challenge_round <- round_n
  status$challenge_history[[length(status$challenge_history) + 1]] <- list(
    round = round_n,
    from_agent = from_agent,
    to_agent = to_agent,
    timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    challenge_reason = reason,
    resolution = NULL
  )
  status$updated_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")

  write_json(status, status_path, pretty = TRUE, auto_unbox = TRUE, null = "null")

  # challenge_note artifact (target agent가 읽음)
  note_path <- file.path(wt_dir, sprintf("%s_challenge_note.json", to_agent))
  note <- list(
    task_id = task_id,
    round = round_n,
    from_agent = from_agent,
    to_agent = to_agent,
    timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    challenge_reason = reason,
    resolution_required = TRUE
  )
  write_json(note, note_path, pretty = TRUE, auto_unbox = TRUE, null = "null")

  # governance_log
  gov_path <- file.path(wt_dir, "governance_log.json")
  gov <- fromJSON(gov_path, simplifyVector = FALSE)
  gov$events[[length(gov$events) + 1]] <- list(
    timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    agent = from_agent,
    action = "CHALLENGE_RAISED",
    summary = sprintf("Round %d: %s -> %s | %s", round_n, from_agent, to_agent, substr(reason, 1, 100))
  )
  write_json(gov, gov_path, pretty = TRUE, auto_unbox = TRUE, null = "null")

  cat(sprintf("[wt_challenge] %s round %d: %s -> %s\n", task_id, round_n, from_agent, to_agent))
  if (round_n >= 2) cat("  WARN: round 2 도달 — Q-Lead 개입 검토 권장\n")
  if (round_n >= 3) cat("  BLOCK: round 3 — Hook이 차단. 수동 개입 필수\n")
  invisible(round_n)
}

# GAP-1 대응: Challenge 검토 완료 기록 (NO_OBJECTION 포함).
# Risk/Optimizer가 challenge 발행 여부와 무관하게 "반론 검토 수행"을 명시 기록.
# P4 audit 통과 조건 = CHALLENGE_REVIEWED 또는 CHALLENGE_RAISED 이벤트 ≥ 1.
wt_record_challenge_review <- function(task_id, from_agent,
                                         objection = FALSE,
                                         reason = NA,
                                         targets_reviewed = character(0)) {
  stopifnot(from_agent %in% c("risk", "optimizer"))
  wt_dir <- file.path(WT_ROOT, task_id)
  if (!dir.exists(wt_dir)) stop(sprintf("[wt_record_challenge_review] %s 없음", task_id))

  gov_path <- file.path(wt_dir, "governance_log.json")
  gov <- fromJSON(gov_path, simplifyVector = FALSE)

  review_summary <- if (isTRUE(objection)) {
    sprintf("Review: %s raised objection — %s",
            from_agent, substr(reason %||% "", 1, 100))
  } else {
    sprintf("Review complete: %s — no formal challenge (targets=%s)",
            from_agent, paste(targets_reviewed, collapse = ","))
  }

  gov$events[[length(gov$events) + 1]] <- list(
    timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    agent = from_agent,
    action = "CHALLENGE_REVIEWED",
    summary = review_summary,
    objection_raised = isTRUE(objection),
    reason = reason,
    targets_reviewed = as.list(targets_reviewed)
  )
  write_json(gov, gov_path, pretty = TRUE, auto_unbox = TRUE, null = "null")

  cat(sprintf("[challenge_review] %s / %s / objection=%s\n",
              task_id, from_agent, isTRUE(objection)))
  invisible(TRUE)
}

# Challenge 해결 기록 (Alpha/Risk가 revise 완료 후 호출)
wt_resolve_challenge <- function(task_id, resolution_note) {
  wt_dir <- file.path(WT_ROOT, task_id)
  status_path <- file.path(wt_dir, "status.json")
  status <- fromJSON(status_path, simplifyVector = FALSE)

  n_hist <- length(status$challenge_history %||% list())
  if (n_hist == 0) {
    cat("[wt_resolve_challenge] challenge_history 비어있음\n")
    return(invisible(FALSE))
  }
  status$challenge_history[[n_hist]]$resolution <- resolution_note
  status$updated_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")

  write_json(status, status_path, pretty = TRUE, auto_unbox = TRUE, null = "null")
  cat(sprintf("[wt_resolve_challenge] %s round %d resolved\n", task_id, n_hist))
  invisible(TRUE)
}

# ─── Package 검증 (schema 기반) ──────────────────────────
wt_validate_package <- function(task_id, package_type) {
  wt_dir <- file.path(WT_ROOT, task_id)
  pkg_path <- file.path(wt_dir, sprintf("%s.json", package_type))

  if (!file.exists(pkg_path)) {
    return(list(valid = FALSE, reason = "file_missing"))
  }

  pkg <- tryCatch(fromJSON(pkg_path, simplifyVector = TRUE),
                  error = function(e) NULL)
  if (is.null(pkg)) {
    return(list(valid = FALSE, reason = "invalid_json"))
  }

  # 필수 필드 (스키마 일부만 간단 체크)
  required_fields <- switch(package_type,
    "alpha_package" = c("task_id", "as_of_date", "alpha_vector", "factor_specs", "diagnostics"),
    "risk_package" = c("task_id", "as_of_date", "factor_covariance_ref", "risk_summary", "diagnostics"),
    "optimization_package" = c("task_id", "as_of_date", "method_selected", "expected_tracking_error"),
    character(0)
  )

  missing <- setdiff(required_fields, names(pkg))
  if (length(missing) > 0) {
    return(list(valid = FALSE, reason = "missing_fields",
                missing = missing))
  }

  list(valid = TRUE)
}

# ─── WT 전수 목록 (v6.1 WT-D/WT-P + legacy WT 모두 지원) ─
wt_list <- function(include_completed = FALSE) {
  wts <- list.files(WT_ROOT,
                    pattern = "^WT-?[DP]?[0-9]{8}_[0-9]{3}$",
                    full.names = FALSE)
  if (length(wts) == 0) {
    cat("(WT 없음)\n")
    return(invisible(character(0)))
  }

  cat(sprintf("=== Work Tasks (%d) ===\n", length(wts)))
  for (id in wts) {
    status_path <- file.path(WT_ROOT, id, "status.json")
    if (file.exists(status_path)) {
      st <- tryCatch(fromJSON(status_path, simplifyVector = TRUE),
                     error = function(e) NULL)
      if (is.null(st)) next
      # v1.7 fix — legacy WT (current_phase 없음) 호환: phase / stage 필드도 fallback
      phase_val <- st$current_phase
      if (is.null(phase_val) || (length(phase_val) == 1 && is.na(phase_val))) {
        phase_val <- st$phase %||% st$stage %||% "UNKNOWN"
      }
      if (!include_completed && phase_val %in% c("COMPLETED", "ABORTED")) next
      type_tag <- if (grepl("^WT-D", id)) "[D]" else if (grepl("^WT-P", id)) "[P]" else "[L]"
      cat(sprintf("  %s %s | %s | updated %s\n",
                  type_tag, id, phase_val, st$updated_at %||% "n/a"))
    }
  }
  invisible(wts)
}

cat("[worktask_manager.R] Loaded. Functions:\n")
cat("  wt_create(hypothesis_title, wt_type='discovery'|'deployment', ...)\n")
cat("  wt_status(task_id)\n")
cat("  wt_advance(task_id, new_phase, blocker=NULL)\n")
cat("  wt_challenge(task_id, from_agent, to_agent, reason)\n")
cat("  wt_record_challenge_review(task_id, from_agent, objection=F, reason=NA, targets_reviewed=c())\n")
cat("  wt_resolve_challenge(task_id, resolution_note)\n")
cat("  wt_check_graduation(task_id)\n")
cat("  wt_validate_package(task_id, package_type)\n")
cat("  wt_list(include_completed=FALSE)\n")
