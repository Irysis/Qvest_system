#==============================================================================
# cert_rules.R — Qvest v8.1 Certificate Rules Single Source
# 02_Infrastructure/worktask/cert_rules.R
#
# Phase 7 (Sprint 2) — hook auto-cert + Layer 2 backfill 동일 eligibility.
#
# Source: 02_Infrastructure/hooks/policies/cert_rules.json (single source)
#
# 사용:
#   source("02_Infrastructure/worktask/cert_rules.R")
#   qvest_cert_rules_selftest()
#   cr_check_eligibility(cert_name="alpha_discovery", package_path="...")
#   cr_get_role_card(wt_type="discovery") → list(own=, inherit=, exempt=, optional=)
#
# Phase 7 의무: cert_backfill_audit.R + 5 cert PostToolUse hook 본 R script import.
# eligibility 중복 구현 금지.
#
# v1.0 — 2026-05-01 Session 75 Sprint 2 Phase 7
#==============================================================================

suppressPackageStartupMessages({
  library(jsonlite)
})

.qvest_find_root <- function() {
  cand <- c(Sys.getenv("CLAUDE_PROJECT_DIR", unset = ""),
            Sys.getenv("QM_ROOT", unset = ""),
            getwd())
  for (p in cand[nzchar(cand)]) {
    p <- normalizePath(p, winslash = "/", mustWork = FALSE)
    if (dir.exists(file.path(p, "02_Infrastructure")) &&
        dir.exists(file.path(p, "qepm"))) return(p)
  }
  here <- normalizePath(getwd(), winslash = "/", mustWork = FALSE)
  repeat {
    if (dir.exists(file.path(here, "02_Infrastructure")) &&
        dir.exists(file.path(here, "qepm"))) return(here)
    parent <- dirname(here)
    if (identical(parent, here)) break
    here <- parent
  }
  stop("[cert_rules] project root not found. Set CLAUDE_PROJECT_DIR or QM_ROOT.")
}

PROJ_ROOT <- .qvest_find_root()

CR_POLICY_PATH <- file.path(PROJ_ROOT,
                            "02_Infrastructure/hooks/policies/cert_rules.json")

`%||%` <- function(a, b) if (is.null(a)) b else a

.cr_policy_cache <- NULL

cr_load_policy <- function(force_reload = FALSE) {
  if (!is.null(.cr_policy_cache) && !force_reload) {
    return(.cr_policy_cache)
  }
  if (!file.exists(CR_POLICY_PATH)) {
    stop(sprintf("[cert_rules] Policy not found: %s", CR_POLICY_PATH))
  }
  policy <- fromJSON(CR_POLICY_PATH, simplifyVector = FALSE)
  assign(".cr_policy_cache", policy, envir = .GlobalEnv)
  policy
}

# ─────────────────────────────────────────────────────────────────
# v7.1-lite Sprint 0.2 — Generic operator dispatch (qvest_cert_eval.py::apply_operator R port)
# ─────────────────────────────────────────────────────────────────

cr_apply_operator <- function(value, operator, threshold = NULL,
                               expected_value = NULL) {
  if (identical(operator, "exists")) return(!is.null(value))
  if (identical(operator, "exists_numeric")) {
    return(!is.null(value) && is.numeric(value) && !is.logical(value))
  }
  if (identical(operator, "exists_int")) {
    return(!is.null(value) && is.numeric(value) && value == as.integer(value))
  }
  if (is.null(value)) return(FALSE)
  if (operator %in% c("<", ">=", ">", "<=")) {
    if (is.null(threshold)) return(FALSE)
    v <- suppressWarnings(as.numeric(value))
    t <- suppressWarnings(as.numeric(threshold))
    if (is.na(v) || is.na(t)) return(FALSE)
    return(switch(operator,
      "<"  = v <  t,
      ">=" = v >= t,
      ">"  = v >  t,
      "<=" = v <= t
    ))
  }
  if (identical(operator, "==")) return(identical(value, expected_value))
  if (identical(operator, "!=")) return(!identical(value, expected_value))
  FALSE
}

# ─────────────────────────────────────────────────────────────────
# 1. Eligibility check (5 cert) — threshold sourced from cert_rules.json
# ─────────────────────────────────────────────────────────────────

cr_check_alpha_discovery <- function(package_path, wt_root = NULL) {
  # v7.2.2 Sprint — promotion_wt + inherit_certs path 처리 (L-282 + L-283 문맥)
  # Charter v1.7 §10 Role Card 4×5 inherit 명시 implementation
  if (!is.null(wt_root)) {
    inherit_ref_path <- file.path(wt_root, "alpha_package_inherit_ref.json")
    if (file.exists(inherit_ref_path)) {
      inherit_ref <- tryCatch(fromJSON(inherit_ref_path,
                                        simplifyVector = FALSE),
                                error = function(e) NULL)
      if (!is.null(inherit_ref)) {
        inherit_certs <- unlist(inherit_ref$inherit_certs %||% list())
        if ("alpha_discovery" %in% inherit_certs) {
          parent_path <- inherit_ref$parent_alpha_package_path %||%
                         (inherit_ref$parent_alpha_packages %||% list())[[1]]
          parent_sha <- inherit_ref$parent_sha %||% NA_character_
          return(list(
            eligible = TRUE,
            reason = "inherited_via_parent_alpha_package_per_role_card_v1_7",
            payload = list(
              inherit_kind = "alpha_discovery",
              parent_path = parent_path,
              parent_sha = parent_sha,
              inherit_certs_declared = inherit_certs,
              wt_kind_eligible = inherit_ref$wt_kind %||% inherit_ref$wt_type %||% "promotion_wt"
            )
          ))
        }
      }
    }
  }

  if (!file.exists(package_path)) {
    return(list(eligible = FALSE, reason = "alpha_package.json 부재", payload = list()))
  }
  pkg <- tryCatch(fromJSON(package_path, simplifyVector = FALSE),
                  error = function(e) NULL)
  if (is.null(pkg)) {
    return(list(eligible = FALSE, reason = "parse fail", payload = list()))
  }

  # v7.1-lite Sprint 0.2 — threshold from cert_rules.json (data layer)
  policy <- cr_load_policy()
  rules <- policy$certificates$alpha_discovery$eligibility_AND %||% list()
  cor_t <- rules$alpha_inheritance_cor$threshold
  mech_t <- rules$mechanism_cited_chars$threshold
  fs_t <- rules$factor_specs_count$threshold
  ht_t <- rules$harvey_t_specs_pass_count$threshold

  diag <- pkg$diagnostics %||% list()
  cor <- diag$alpha_inheritance_cor
  ht <- diag$harvey_t_specs_pass_count %||% 0L
  factor_specs <- pkg$factor_specs %||% list()
  n_factor <- length(factor_specs)

  mech <- pkg$hypothesis_summary %||% ""
  for (fs in factor_specs) {
    if (is.list(fs)) {
      mech <- paste(mech, fs$economic_rationale %||% "",
                    fs$formula %||% "", sep = " ")
    }
  }
  mech_chars <- nchar(trimws(mech))

  issues <- character()
  if (is.null(cor)) {
    issues <- c(issues, "alpha_inheritance_cor missing")
  } else if (!cr_apply_operator(cor, "<", cor_t)) {
    issues <- c(issues, sprintf("cor=%.4f >= %.2f", cor, cor_t))
  }
  if (!cr_apply_operator(mech_chars, ">=", mech_t)) {
    issues <- c(issues, sprintf("mech %d < %d", mech_chars, as.integer(mech_t)))
  }
  if (!cr_apply_operator(n_factor, ">=", fs_t)) {
    issues <- c(issues, sprintf("factor_specs %d < %d", n_factor, as.integer(fs_t)))
  }
  if (!cr_apply_operator(ht, ">=", ht_t)) {
    issues <- c(issues, sprintf("harvey_t_count %d < %d", ht, as.integer(ht_t)))
  }

  list(
    eligible = length(issues) == 0,
    reason = if (length(issues) > 0) paste(issues, collapse = " | ") else "all_pass",
    payload = list(
      alpha_inheritance_cor = cor,
      mechanism_cited_chars = mech_chars,
      factor_specs_count = n_factor,
      harvey_t_specs_pass_count = ht
    )
  )
}

cr_check_sr_provenance <- function(package_path) {
  if (!file.exists(package_path)) {
    return(list(eligible = FALSE, reason = "forge_package.json 부재"))
  }
  pkg <- tryCatch(fromJSON(package_path, simplifyVector = FALSE),
                  error = function(e) NULL)
  if (is.null(pkg)) return(list(eligible = FALSE, reason = "parse fail"))

  required <- c("sr_realized_share_based", "measurement_basis_primary",
                "weights_csv_unique_dates_count", "schedule_density_ratio")
  missing <- required[!required %in% names(pkg)]
  basis_ok <- identical(pkg$measurement_basis_primary, "forge_realized_share_based")

  issues <- character()
  if (length(missing) > 0) issues <- c(issues, paste0("missing: ", paste(missing, collapse = ", ")))
  if (!basis_ok) issues <- c(issues, sprintf("basis='%s' != 'forge_realized_share_based'",
                                              pkg$measurement_basis_primary %||% "NA"))

  list(
    eligible = length(issues) == 0,
    reason = if (length(issues) > 0) paste(issues, collapse = " | ") else "all_4_field_pass",
    payload = list(
      sr_realized_share_based = pkg$sr_realized_share_based,
      measurement_basis_primary = pkg$measurement_basis_primary,
      weights_csv_unique_dates_count = pkg$weights_csv_unique_dates_count,
      schedule_density_ratio = pkg$schedule_density_ratio
    )
  )
}

cr_check_forge_package_validated <- function(package_path) {
  if (!file.exists(package_path)) {
    return(list(eligible = FALSE, reason = "forge_package.json 부재"))
  }
  pkg <- tryCatch(fromJSON(package_path, simplifyVector = FALSE),
                  error = function(e) NULL)
  if (is.null(pkg)) return(list(eligible = FALSE, reason = "parse fail"))

  required_8 <- c("task_id", "backtest_summary", "sr_realized_share_based",
                  "measurement_basis_primary", "weights_csv_unique_dates_count",
                  "alpha_sig_dates_count", "schedule_density_ratio",
                  "schedule_density_pass", "pure_function_violation")
  missing <- required_8[!required_8 %in% names(pkg)]

  list(
    eligible = length(missing) == 0,
    reason = if (length(missing) > 0)
      paste0("missing: ", paste(missing, collapse = ", "))
      else "all_8_field_pass",
    payload = list(validated_fields_count = length(required_8) - length(missing))
  )
}

cr_check_schedule_fidelity <- function(package_path, weights_csv = NULL,
                                       alpha_package_path = NULL,
                                       wt_root = NULL) {
  # v7.2.2 Sprint — promotion_wt + inherit_certs path 처리 (L-283)
  if (!is.null(wt_root)) {
    inherit_ref_path <- file.path(wt_root, "alpha_package_inherit_ref.json")
    if (file.exists(inherit_ref_path)) {
      inherit_ref <- tryCatch(fromJSON(inherit_ref_path,
                                        simplifyVector = FALSE),
                                error = function(e) NULL)
      if (!is.null(inherit_ref)) {
        inherit_certs <- unlist(inherit_ref$inherit_certs %||% list())
        if ("schedule_fidelity" %in% inherit_certs) {
          parent_path <- inherit_ref$parent_alpha_package_path %||%
                         (inherit_ref$parent_alpha_packages %||% list())[[1]]
          parent_sha <- inherit_ref$parent_sha %||% NA_character_
          # Verify schedule_density 1.0 in optimization_package as supplementary
          opt_density <- 1.0
          if (file.exists(package_path)) {
            opt_pkg <- tryCatch(fromJSON(package_path, simplifyVector = FALSE),
                                 error = function(e) NULL)
            if (!is.null(opt_pkg)) {
              opt_density <- opt_pkg$schedule_density %||% 1.0
            }
          }
          return(list(
            eligible = TRUE,
            reason = "inherited_via_parent_alpha_package_per_role_card_v1_7",
            payload = list(
              inherit_kind = "schedule_fidelity",
              parent_path = parent_path,
              parent_sha = parent_sha,
              optimization_package_schedule_density_supplementary = opt_density,
              inherit_certs_declared = inherit_certs
            )
          ))
        }
      }
    }
  }

  if (!file.exists(package_path)) {
    return(list(eligible = FALSE, reason = "optimization_package.json 부재"))
  }
  pkg <- tryCatch(fromJSON(package_path, simplifyVector = FALSE),
                  error = function(e) NULL)
  if (is.null(pkg)) return(list(eligible = FALSE, reason = "parse fail"))

  sched <- pkg$schedule_fidelity %||% list()
  wcd <- sched$weights_csv_unique_dates_count %||% 0L
  sdc <- sched$alpha_sig_dates_count %||% 0L

  if (sdc == 0) {
    return(list(eligible = FALSE, reason = "alpha_sig_dates_count=0"))
  }

  ratio <- wcd / sdc
  has_infeas <- !is.null(sched$infeasibility_report) ||
    !is.null(sched$schedule_skip_justified) ||
    isTRUE(sched$schedule_skip_justified)

  # v7.1-lite Sprint 0.2 — threshold from cert_rules.json (data layer)
  policy <- cr_load_policy()
  density_t <- policy$certificates$schedule_fidelity$eligibility_OR$density$threshold

  if (!cr_apply_operator(ratio, ">=", density_t) && !has_infeas) {
    return(list(eligible = FALSE,
                reason = sprintf("density %.3f < %.2f + no infeasibility",
                                 ratio, density_t),
                payload = list(schedule_density_ratio = round(ratio, digits = 3L))))
  }

  list(
    eligible = TRUE,
    reason = sprintf("density=%.3f", ratio),
    payload = list(
      weights_csv_unique_dates_count = wcd,
      alpha_sig_dates_count = sdc,
      schedule_density_ratio = round(ratio, digits = 3L),
      infeasibility_report_cited = !cr_apply_operator(ratio, ">=", density_t)
    )
  )
}

cr_check_governor_concord <- function(book_state_path, governor_dir = NULL,
                                      wt_root = NULL) {
  if (!file.exists(book_state_path)) {
    return(list(eligible = FALSE, reason = "book_state.json 부재"))
  }
  bs <- tryCatch(fromJSON(book_state_path, simplifyVector = FALSE),
                 error = function(e) NULL)
  if (is.null(bs)) return(list(eligible = FALSE, reason = "parse fail"))

  admitted_ids <- unlist(bs$admitted_ids %||% list())
  weights <- bs$book_weights %||% list()

  if (length(admitted_ids) == 0) {
    return(list(eligible = FALSE, reason = "no admitted_ids"))
  }

  if (is.null(wt_root)) {
    wt_root <- file.path(PROJ_ROOT, "qepm/mailbox/worktask")
  }

  details <- list()
  all_match <- TRUE
  for (sid in admitted_ids) {
    sid <- as.character(sid)
    # Find governor_admission for sid (best-effort lineage)
    ga_paths <- list.files(wt_root, pattern = "^governor_admission\\.json$",
                           recursive = TRUE, full.names = TRUE)
    ga_match <- NULL
    for (p in ga_paths) {
      ga <- tryCatch(fromJSON(p, simplifyVector = FALSE), error = function(e) NULL)
      if (!is.null(ga) && (identical(ga$str_id, sid) ||
                           sid %in% names(ga$allocation_decided %||% list()))) {
        ga_match <- ga
        break
      }
    }
    if (is.null(ga_match)) {
      all_match <- FALSE
      details[[length(details) + 1]] <- list(
        str_id = sid, match = FALSE, reason = "no governor_admission found"
      )
      next
    }
    expected <- (ga_match$allocation_decided %||% list())[[sid]]
    actual <- weights[[sid]]
    is_match <- !is.null(expected) && !is.null(actual) &&
      abs(as.numeric(expected) - as.numeric(actual)) < 0.01
    if (!is_match) all_match <- FALSE
    details[[length(details) + 1]] <- list(
      str_id = sid,
      expected_weight = expected,
      actual_weight = actual,
      match = is_match
    )
  }

  list(
    eligible = all_match,
    reason = if (all_match) "all_admitted_match" else "some_mismatch",
    payload = list(
      concord_type = if (all_match) "match" else "with_waiver_required",
      details = details
    )
  )
}

# ─────────────────────────────────────────────────────────────────
# 2. Unified eligibility check (cert_name dispatch)
# ─────────────────────────────────────────────────────────────────

cr_check_eligibility <- function(cert_name, package_path,
                                 weights_csv = NULL, alpha_package_path = NULL,
                                 wt_root = NULL) {
  switch(cert_name,
    "alpha_discovery" = cr_check_alpha_discovery(package_path,
                                                  wt_root = wt_root),
    "sr_provenance" = cr_check_sr_provenance(package_path),
    "forge_package_validated" = cr_check_forge_package_validated(package_path),
    "schedule_fidelity" = cr_check_schedule_fidelity(package_path, weights_csv,
                                                     alpha_package_path,
                                                     wt_root = wt_root),
    "governor_concord" = cr_check_governor_concord(package_path,
                                                    wt_root = wt_root),
    list(eligible = FALSE, reason = sprintf("unknown cert: %s", cert_name))
  )
}

# ─────────────────────────────────────────────────────────────────
# 3. Role Card (wt_type → cert ownership)
# ─────────────────────────────────────────────────────────────────

# ─────────────────────────────────────────────────────────────────
# v7.0 Sprint 3 — Schema validation wrapper (router 위임)
# ─────────────────────────────────────────────────────────────────

cr_validate_schema <- function(schema_name, package_path) {
  router <- file.path(PROJ_ROOT, "02_Infrastructure/hooks/qvest_hook_router.py")
  if (!file.exists(router)) {
    return(list(valid = FALSE, reason = "router not found"))
  }
  # Normalize to absolute path (한글 경로 escape 회피)
  # [fix 2026-07-25] 구 검사 startsWith(package_path, "/")는 Windows drive-letter
  # 절대경로("C:/...", "C:\...")를 상대경로로 오판해 PROJ_ROOT를 덧붙였다 →
  # 존재하는 파일도 "package not found"로 기각(절대경로 호출자 전건 실패).
  .is_abs <- function(p) {
    grepl("^([A-Za-z]:)?[/\\\\]", p) || grepl("^~", p)
  }
  if (!.is_abs(package_path)) {
    package_path <- file.path(PROJ_ROOT, package_path)
  }
  if (!file.exists(package_path)) {
    return(list(valid = FALSE, reason = sprintf("package not found: %s", package_path)))
  }
  # [fix 2026-07-05] bare "python3" Windows Store 스텁(9009) → QVEST_PY 우선 (state_machine.R 동형)
  py_bin <- Sys.getenv("QVEST_PY", unset = "")
  if (!nzchar(py_bin) || !file.exists(py_bin)) py_bin <- "python3"
  # [fix 2026-07-25] system2(env=)는 Windows에서 환경변수를 설정하지 않고 문자열을
  # *첫 인자로 앞에 붙인다* → python이 "CLAUDE_PROJECT_DIR=..."를 스크립트 경로로
  # 오인(rc 2). 그 에러문이 stderr로 out에 담겨 length(out)==0 가드를 통과하므로
  # 실패가 "router output parse fail"이라는 엉뚱한 사유로 위장됐다.
  # → Sys.setenv + 복원 (state_machine.R:248-252 동형).
  .old_cpd <- Sys.getenv("CLAUDE_PROJECT_DIR", unset = NA)
  Sys.setenv(CLAUDE_PROJECT_DIR = PROJ_ROOT)
  on.exit({
    if (is.na(.old_cpd)) Sys.unsetenv("CLAUDE_PROJECT_DIR")
    else Sys.setenv(CLAUDE_PROJECT_DIR = .old_cpd)
  }, add = TRUE)
  out <- tryCatch(
    system2(py_bin,
            args = c(shQuote(router), "validate-schema",
                     "--schema", schema_name,
                     "--package", shQuote(package_path)),
            stdout = TRUE, stderr = TRUE),
    error = function(e) NULL
  )
  if (is.null(out) || length(out) == 0) {
    return(list(valid = FALSE, reason = "router invocation fail"))
  }
  parsed <- tryCatch(fromJSON(paste(out, collapse = "\n"), simplifyVector = TRUE),
                     error = function(e) NULL)
  if (is.null(parsed) || is.null(parsed$valid)) {
    return(list(valid = FALSE, reason = sprintf("router output parse fail: %s",
                                                substring(paste(out, collapse = " "), 1, 100))))
  }
  list(valid = isTRUE(parsed$valid), reason = parsed$reason %||% "")
}

cr_get_role_card <- function(wt_type) {
  policy <- cr_load_policy()
  card <- policy$role_card_4x5[[wt_type]]
  if (is.null(card)) {
    return(list(error = sprintf("unknown wt_type: %s", wt_type)))
  }
  list(
    own = unlist(card$own %||% list()),
    inherit = unlist(card$inherit %||% list()),
    exempt = unlist(card$exempt %||% list()),
    optional = unlist(card$optional %||% list())
  )
}

# ─────────────────────────────────────────────────────────────────
# 4. Selftest
# ─────────────────────────────────────────────────────────────────

qvest_cert_rules_selftest <- function() {
  cat("=== Qvest v8.1 Cert Rules Selftest ===\n")

  policy <- tryCatch(cr_load_policy(force_reload = TRUE),
                     error = function(e) {
                       cat("[FAIL] policy load:", conditionMessage(e), "\n")
                       NULL
                     })
  if (is.null(policy)) return(invisible(FALSE))

  certs <- names(policy$certificates %||% list())
  cat(sprintf("[PASS] policy loaded: %d certs\n", length(certs)))

  # Test each cert eligibility check (synthetic — file 부재 시 fail expected)
  for (cert in certs) {
    res <- cr_check_eligibility(cert, "/nonexistent/path.json")
    if (!res$eligible) {
      cat(sprintf("[PASS] %s: file 부재 detection\n", cert))
    }
  }

  # Test role card
  for (wt_type in c("discovery", "deployment", "sizing_only", "hyperparameter_sweep")) {
    card <- cr_get_role_card(wt_type)
    if (!is.null(card$error)) {
      cat(sprintf("[FAIL] role_card %s: %s\n", wt_type, card$error))
    } else {
      cat(sprintf("[PASS] role_card %s: own=%d inherit=%d\n",
                  wt_type, length(card$own), length(card$inherit)))
    }
  }

  # Test active book BHEQ (real WT_001 alpha_package — if exists)
  alpha_pkg <- file.path(PROJ_ROOT,
                         "qepm/mailbox/worktask/WT-D20260501_003/alpha_package.json")
  if (file.exists(alpha_pkg)) {
    res <- cr_check_eligibility("alpha_discovery", alpha_pkg)
    cat(sprintf("[INFO] WT_003 alpha cert eligibility: %s | %s\n",
                if (res$eligible) "PASS" else "FAIL", res$reason))
  }

  cat("\n=== Selftest PASS ===\n")
  invisible(TRUE)
}

cat("[cert_rules.R] Loaded. Functions:\n")
cat("  cr_load_policy(force_reload=FALSE)\n")
cat("  cr_check_eligibility(cert_name, package_path, ...)\n")
cat("  cr_check_alpha_discovery / sr_provenance / schedule_fidelity / forge_package_validated / governor_concord\n")
cat("  cr_get_role_card(wt_type)\n")
cat("  qvest_cert_rules_selftest()\n")
