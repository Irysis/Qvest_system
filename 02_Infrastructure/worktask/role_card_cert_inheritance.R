#==============================================================================
# role_card_cert_inheritance.R — Charter v1.7 §10 Role Card Cert Inheritance Rules
# 02_Infrastructure/worktask/role_card_cert_inheritance.R
#
# 4 role card (discovery / deployment / sizing_only / hyperparameter_sweep) ×
# 5 certificate (alpha_discovery / sr_provenance / schedule_fidelity /
# forge_package_validated / governor_concord)의 자체 발급 vs parent inherit 룰
# 단일 진입점. cert_backfill_audit.R + worktask_manager.R +
# measurement_basis_audit.R + 향후 Hook들이 공통 import.
#
# Reference: Charter v1.7 (2026-04-30) §10 Role Card 표 확장.
#==============================================================================

# Role card별 cert 5종 정의:
#   - own:       자체 발급 의무 (이 cert 부재 시 graduation FAIL)
#   - inherit:   parent WT (discovery 또는 lineage)에서 inherit 가능 (자체 발급 면제)
#   - exempt:    이 cert 발급 불필요 (정상 동작)
#   - optional:  자체 발급 가능하지만 의무 아님

ROLE_CARDS_CERT_RULES <- list(
  discovery = list(
    alpha_discovery = "own",
    sr_provenance = "own",
    schedule_fidelity = "own",
    forge_package_validated = "own",
    governor_concord = "exempt"  # discovery WT는 admit 자체가 아님
  ),
  deployment = list(
    alpha_discovery = "inherit",  # discovery WT에서 inherit
    sr_provenance = "own",
    schedule_fidelity = "own",
    forge_package_validated = "own",
    governor_concord = "own"
  ),
  sizing_only = list(
    alpha_discovery = "exempt",  # parent strategy 동일 alpha 사용
    sr_provenance = "inherit",   # parent WT sr_provenance inherit
    schedule_fidelity = "inherit",  # parent schedule 동일
    forge_package_validated = "optional",
    governor_concord = "own"
  ),
  hyperparameter_sweep = list(
    alpha_discovery = "inherit",  # parent alpha 동일
    sr_provenance = "own",  # 자체 forge run 시 own
    schedule_fidelity = "inherit",  # parent schedule 동일
    forge_package_validated = "own",
    governor_concord = "exempt"  # sweep 결과만, admit 아님
  )
)

#==============================================================================
# get_role_card_rules(wt_type)
# wt_type → cert 5종 inheritance 룰 list 반환
#==============================================================================
get_role_card_rules <- function(wt_type) {
  if (is.null(wt_type) || length(wt_type) != 1) {
    stop("wt_type must be single string")
  }
  if (!wt_type %in% names(ROLE_CARDS_CERT_RULES)) {
    stop(sprintf("Unknown wt_type: '%s'. Valid: %s",
                 wt_type, paste(names(ROLE_CARDS_CERT_RULES), collapse = ", ")))
  }
  ROLE_CARDS_CERT_RULES[[wt_type]]
}

#==============================================================================
# cert_required(wt_type, cert_type) → TRUE/FALSE
# 이 wt_type에서 이 cert가 자체 발급 의무인지
#==============================================================================
cert_required <- function(wt_type, cert_type) {
  rules <- get_role_card_rules(wt_type)
  if (!cert_type %in% names(rules)) {
    stop(sprintf("Unknown cert_type: '%s'", cert_type))
  }
  identical(rules[[cert_type]], "own")
}

#==============================================================================
# cert_inheritable(wt_type, cert_type) → TRUE/FALSE
# 이 wt_type에서 이 cert가 parent WT에서 inherit 가능한지
#==============================================================================
cert_inheritable <- function(wt_type, cert_type) {
  rules <- get_role_card_rules(wt_type)
  identical(rules[[cert_type]], "inherit")
}

#==============================================================================
# cert_exempt(wt_type, cert_type) → TRUE/FALSE
# 이 wt_type에서 이 cert가 발급 불필요한지 (정상)
#==============================================================================
cert_exempt <- function(wt_type, cert_type) {
  rules <- get_role_card_rules(wt_type)
  identical(rules[[cert_type]], "exempt")
}

#==============================================================================
# get_required_certs(wt_type) → character vector
# 이 wt_type에서 자체 발급 의무 cert 목록
#==============================================================================
get_required_certs <- function(wt_type) {
  rules <- get_role_card_rules(wt_type)
  names(rules)[sapply(rules, function(x) identical(x, "own"))]
}

#==============================================================================
# get_inheritable_certs(wt_type) → character vector
# 이 wt_type에서 parent inherit 가능 cert 목록
#==============================================================================
get_inheritable_certs <- function(wt_type) {
  rules <- get_role_card_rules(wt_type)
  names(rules)[sapply(rules, function(x) identical(x, "inherit"))]
}

#==============================================================================
# check_wt_cert_compliance(wt_dir, wt_type, lineage_wts = NULL)
# 이 WT가 role card 룰에 따라 cert 의무 충족하는지 검사
# Return: list(compliant, missing_own, eligible_inherit_pending, exempt_skipped)
#==============================================================================
check_wt_cert_compliance <- function(wt_dir, wt_type, lineage_wts = NULL,
                                       governor_dir = NULL) {
  rules <- get_role_card_rules(wt_type)
  cert_files <- list(
    alpha_discovery = "alpha_discovery_certificate.json",
    sr_provenance = "sr_provenance_certificate.json",
    schedule_fidelity = "schedule_fidelity_certificate.json",
    forge_package_validated = "forge_package_validated_certificate.json"
  )

  missing_own <- character(0)
  inherit_pending <- character(0)
  exempt_skipped <- character(0)
  ok_certs <- character(0)

  for (cert_type in names(rules)) {
    rule <- rules[[cert_type]]

    # governor_concord는 governor_dir에 위치
    if (cert_type == "governor_concord") {
      if (rule == "exempt") {
        exempt_skipped <- c(exempt_skipped, cert_type)
      } else if (rule == "own" && !is.null(governor_dir)) {
        gc_path <- file.path(governor_dir, "governor_concord_certificate.json")
        gc_waiver <- file.path(governor_dir,
                                "governor_concord_with_waiver_certificate.json")
        if (file.exists(gc_path) || file.exists(gc_waiver)) {
          ok_certs <- c(ok_certs, cert_type)
        } else {
          missing_own <- c(missing_own, cert_type)
        }
      }
      next
    }

    cert_path <- file.path(wt_dir, cert_files[[cert_type]])
    if (rule == "exempt") {
      exempt_skipped <- c(exempt_skipped, cert_type)
    } else if (rule == "own") {
      if (file.exists(cert_path)) {
        ok_certs <- c(ok_certs, cert_type)
      } else {
        missing_own <- c(missing_own, cert_type)
      }
    } else if (rule == "inherit") {
      if (file.exists(cert_path)) {
        ok_certs <- c(ok_certs, cert_type)
      } else if (!is.null(lineage_wts) && length(lineage_wts) > 0) {
        # parent에서 inherit 가능 여부 확인
        inherited <- FALSE
        for (lw in lineage_wts) {
          if (file.exists(file.path(lw, cert_files[[cert_type]]))) {
            inherited <- TRUE; break
          }
        }
        if (inherited) {
          ok_certs <- c(ok_certs, cert_type)
        } else {
          inherit_pending <- c(inherit_pending, cert_type)
        }
      } else {
        inherit_pending <- c(inherit_pending, cert_type)
      }
    }
    # optional은 ok_certs에 자동 포함 (compliance 영향 없음)
  }

  compliant <- length(missing_own) == 0 && length(inherit_pending) == 0

  list(
    compliant = compliant,
    wt_type = wt_type,
    rules_applied = rules,
    ok_certs = ok_certs,
    missing_own = missing_own,
    inherit_pending = inherit_pending,
    exempt_skipped = exempt_skipped
  )
}

#==============================================================================
# print_role_card_summary(wt_type)
# Charter §10 role card 요약 표 출력 (디버그/문서용)
#==============================================================================
print_role_card_summary <- function(wt_type = NULL) {
  cat("=== Charter v1.7 §10 Role Card Cert Inheritance Rules ===\n")
  cat(sprintf("%-22s | %-15s %-15s %-19s %-23s %-15s\n",
              "wt_type", "alpha_discovery", "sr_provenance",
              "schedule_fidelity", "forge_package_validated", "governor_concord"))
  cat(strrep("-", 110), "\n")
  types <- if (is.null(wt_type)) names(ROLE_CARDS_CERT_RULES) else wt_type
  for (wt in types) {
    rules <- ROLE_CARDS_CERT_RULES[[wt]]
    cat(sprintf("%-22s | %-15s %-15s %-19s %-23s %-15s\n",
                wt,
                rules$alpha_discovery, rules$sr_provenance,
                rules$schedule_fidelity, rules$forge_package_validated,
                rules$governor_concord))
  }
  cat("\nRule meanings:\n")
  cat("  own       — 자체 발급 의무 (부재 시 graduation FAIL)\n")
  cat("  inherit   — parent WT (discovery 또는 lineage)에서 inherit 가능\n")
  cat("  exempt    — 발급 불필요 (정상 동작)\n")
  cat("  optional  — 자체 발급 가능하지만 의무 아님\n")
}

#==============================================================================
# CLI 진입점 — 단순 print_role_card_summary 호출
#==============================================================================
if (!interactive() && length(commandArgs(trailingOnly = TRUE)) >= 0) {
  args <- commandArgs(trailingOnly = TRUE)
  wt_arg <- if (length(args) > 0) args[1] else NULL
  print_role_card_summary(wt_arg)
}
