#==============================================================================
# cert_backfill_audit.R — Layer 2 Cert Backfill Audit Script
# 02_Infrastructure/ops/cert_backfill_audit.R
#
# Charter v1.2 §10 Measurement Coherence Health Score 복구용 사후 cert 발급.
# bootstrap.sh DRIFTED 감지 시 자동 호출 OR Q-Lead 수동 호출.
#
# Reference 사고: STR_1715 PG2 admit (2026-04-29) 후 5 cert 모두 부재 → 0/100 DRIFTED.
# 진단 결과 5중 구조적 원인 (Charter timing transition / deployment lifecycle mismatch /
# str_id mismatch / Hook bug / R script 시야 밖). 본 script는 원인 1·2·5 잔존
# (이미 발생한 누락) 사후 복구. 원인 3·4는 Layer 3 + 본 세션 fix에서 해소.
#
# Cert 발급 전략 (Option B): R script가 cert 파일 직접 작성 (Hook bypass).
# 이유: R script의 file.write는 PostToolUse[Write|Edit] Hook 시야 밖 → Hook trigger
# 시도는 무의미. 대신 R script가 hook과 동일 schema로 cert 파일 작성.
#
# Usage:
#   Rscript cert_backfill_audit.R [--auto|--manual|--dry-run] [--target=WT-XXX_NNN]
#
# Modes:
#   --auto    Governor `ELIGIBLE_FOR_ISSUANCE` 명시 cert만 자동 발급 (default)
#   --manual  모든 발급 가능 cert 강제 발급 (Q-Lead 직접 호출)
#   --dry-run 실제 발급 없이 audit만 수행
#
# Targets:
#   --target=WT-XXX_NNN  특정 WT만 처리 (생략 시 book_state admitted_ids 전체 + lineage)
#==============================================================================

suppressPackageStartupMessages({
  library(jsonlite)
  library(data.table)
})

# v7.0 Sprint 1 — cert_rules.R 단일 source 위임. 5 check_*_eligibility wrapper화.
# cert_rules.R가 cert_rules.json import → eligibility logic 중복 0건.
.cert_rules_path_v70 <- "02_Infrastructure/worktask/cert_rules.R"
if (!exists("cr_check_eligibility", mode = "function")) {
  if (file.exists(.cert_rules_path_v70)) {
    suppressMessages(source(.cert_rules_path_v70, local = FALSE))
  } else {
    warning(sprintf("[cert_backfill_audit] cert_rules.R 부재: %s — fallback inline logic 유지",
                    .cert_rules_path_v70))
  }
}

`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0 && !all(is.na(a))) a else b

LOG_PATH <- "/tmp/cert_backfill_audit.log"
LOG_FH <- NULL

log_init <- function() {
  LOG_FH <<- file(LOG_PATH, open = "a")
  log_msg(sprintf("=== cert_backfill_audit.R run at %s ===",
                  format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")))
}

log_close <- function() {
  if (!is.null(LOG_FH)) { close(LOG_FH); LOG_FH <<- NULL }
}

log_msg <- function(msg) {
  if (!is.null(LOG_FH)) writeLines(msg, LOG_FH)
  cat(msg, "\n")
}

#--- Cert schema constants ----------------------------------------------------
# ★v10 2026-09-03: governor_concord 는 벡터에 남기되 발급은 아래 루프에서 RETIRED 가드로 차단한다
#   (wt_timeline.R·role_card_cert_inheritance.R 이 같은 enum 을 쓰므로 벡터 자체는 유지).
CERT_TYPES <- c("alpha_discovery", "sr_provenance", "schedule_fidelity",
                "forge_package_validated", "governor_concord")
CHARTER_REF <- "v1.2 §10 (backfilled by cert_backfill_audit.R)"

#==============================================================================
# 1. Lineage discovery — str_id로부터 모든 관련 WT 발견
#==============================================================================
#──────────────────────────────────────────────────────────────────────────────
# (2026-07-26 CBA-01 수리, probe② 감사 확정) 이 파일의 resolver 는 형제 파일
#   measurement_basis_audit.R 이 v1.12(07-24)에서 고친 **절단 버그를 그대로 갖고 있었다**.
#   str_id_root <- sub("(_WT|_Iter|_M|_S|_v).*$", "", str_id) 는 현행 북
#   'STR_1715_on_M4gAE_R05_noLayer4_PG2' 를 첫 '_M' 에서 잘라 'STR_1715_on' 으로 만들고,
#   substring 매칭이 terminal ga str_id 와 어긋난다.
#   ★실측 확정(2026-07-26): `Admitted IDs: STR_1715_on_M4gAE_R05_noLayer4_PG2` 인데
#     `Targets: 0 WT(s)` — coherence 가 DRIFTED 로 떨어지는 순간 --auto 백필은 0건 처리
#     후 "0 cert(s) issued" 만 출력하고, bootstrap WARN 이 권하는 --manual 도 같은
#     resolver 라 똑같이 0건. 즉 **자동수리 계층 전체가 현행 북에 대해 구조적 no-op** 였다.
#   수리: 수리된 resolver(.lineage_anchor / .lineage_related — 토큰 경계 매칭)를
#   재사용한다. 그 함수들은 08_Tests/portfolio/test_lineage_resolver.R(24 assert,
#   위반 주입 5축)이 이미 지키고 있어 여기서 별도 사본을 만들지 않는다.
#   ※ 형제 파일을 source 하면 CLI entrypoint 는 commandArgs(trailingOnly)>0 가드로
#     발화하지 않는다(확인). 로드 실패 시엔 legacy 절단 root 로 폴백하되 로그를 남긴다.
#──────────────────────────────────────────────────────────────────────────────
.cba_load_resolver <- function() {
  if (exists(".lineage_related", inherits = TRUE)) return(TRUE)
  # ★이 파일은 PROJECT_ROOT 를 정의하지 않는다(상대경로 스타일 — cert_rules.R 로드와 동일).
  #   초판이 PROJECT_ROOT 를 썼다가 미정의로 조용히 폴백될 참이었다. 후보를 **표지 검증**으로
  #   확인한다(r-portability 금칙 ③④ — 존재≠정체, CLAUDE_PROJECT_DIR 우선).
  rel <- "02_Infrastructure/portfolio/measurement_basis_audit.R"
  mba <- ""
  for (cand in c(rel,
                 file.path(Sys.getenv("CLAUDE_PROJECT_DIR", ""), rel),
                 file.path(Sys.getenv("QM_ROOT", ""), rel))) {
    if (nzchar(cand) && file.exists(cand)) { mba <- cand; break }
  }
  if (!nzchar(mba)) return(FALSE)
  ok <- tryCatch({ source(mba); exists(".lineage_related", inherits = TRUE) },
                 error = function(e) FALSE)
  isTRUE(ok)
}

audit_str_lineage <- function(str_id, wt_root) {
  wt_dirs <- list.dirs(wt_root, full.names = TRUE, recursive = FALSE)
  wt_dirs <- wt_dirs[grepl("/WT-", wt_dirs)]

  # legacy 절단 root — 비-STR 계열 fallback 전용 (STR-family 는 anchor 가 대체)
  str_id_root <- sub("(_WT|_Iter|_M|_S|_v).*$", "", str_id)
  .have_resolver <- .cba_load_resolver()
  if (!.have_resolver) {
    log_msg(sprintf(paste0("WARN: lineage resolver 로드 실패 — legacy 절단 root('%s') 폴백. ",
                           "오버레이 접미 id 는 매칭 실패 가능(CBA-01 재발)"), str_id_root))
  }
  # 계보 일치 판정 단일 진입점: resolver 가용 시 토큰경계 anchor, 아니면 구 substring
  .lin_match <- function(candidate) {
    if (!nzchar(as.character(candidate %||% ""))) return(FALSE)
    if (.have_resolver) return(isTRUE(.lineage_related(str_id, candidate, str_id_root)))
    grepl(str_id, candidate, fixed = TRUE) || grepl(str_id_root, candidate, fixed = TRUE)
  }

  matched <- list()
  for (wd in wt_dirs) {
    ga_path <- file.path(wd, "governor_admission.json")
    if (!file.exists(ga_path)) next
    ga <- tryCatch(fromJSON(ga_path, simplifyVector = FALSE), error = function(e) NULL)
    if (is.null(ga)) next

    ga_str_id <- as.character(ga$str_id %||% "")
    discovery_of <- as.character(ga$discovery_of %||%
                                  ga$wt_lifecycle$discovery_of %||% "")

    # 추가 매칭 — forge_package.json의 deployment_lineage 필드도 점검
    fp_path <- file.path(wd, "forge_package.json")
    fp_lineage_match <- FALSE
    if (file.exists(fp_path)) {
      fp <- tryCatch(fromJSON(fp_path, simplifyVector = FALSE),
                     error = function(e) NULL)
      if (!is.null(fp)) {
        dl <- fp$deployment_lineage %||% list()
        al <- fp$alpha_lineage_chain %||% list()
        lineage_text <- paste(unlist(dl), unlist(al), collapse = " ")
        if (nchar(lineage_text) > 0 && .lin_match(lineage_text)) {
          fp_lineage_match <- TRUE
        }
      }
    }

    is_match <- FALSE
    role <- "unknown"
    if (identical(ga_str_id, str_id)) {
      is_match <- TRUE
      role <- ga$wt_type %||% "unknown"
    } else if (nchar(ga_str_id) > 0 && .lin_match(ga_str_id)) {
      is_match <- TRUE
      role <- "lineage_partial_match"
    } else if (.lin_match(discovery_of)) {
      is_match <- TRUE
      role <- "discovery_or_upgrade_via_lineage"
    } else if (fp_lineage_match) {
      is_match <- TRUE
      role <- "forge_package_deployment_lineage_match"
    }

    if (is_match) {
      matched[[basename(wd)]] <- list(
        wt_dir = wd,
        wt_id = basename(wd),
        ga_str_id = ga_str_id,
        wt_type = ga$wt_type %||% "unknown",
        role = role,
        generated_at = ga$generated_at %||% ""
      )
    }
  }
  matched
}

#==============================================================================
# 2. Cert 발급 가능 여부 검사 (v7.0 Sprint 1 — cert_rules.R 위임)
#
# v7.0 정합 강제: 5 check_*_eligibility는 cert_rules.R::cr_check_* 호출 wrapper.
# eligibility logic은 cert_rules.json (data) → cert_rules.R (apply) 단일 source.
# payload field name은 backward compat (기존 cert 발급 schema 보존).
#==============================================================================
check_alpha_discovery_eligibility <- function(wt_dir) {
  alpha_path <- file.path(wt_dir, "alpha_package.json")
  if (!exists("cr_check_alpha_discovery", mode = "function")) {
    return(list(eligible = FALSE, reason = "cert_rules.R 미로드"))
  }
  # v7.2.2 — wt_root 전달하여 inherit_certs path 인식 (L-283)
  res <- cr_check_alpha_discovery(alpha_path, wt_root = wt_dir)
  # payload field name backward compat (cert_backfill 기존 schema)
  if (isTRUE(res$eligible) && !is.null(res$payload)) {
    if (!is.null(res$payload$inherit_kind)) {
      # Inherited path payload
      res$payload <- list(
        inherit_kind = res$payload$inherit_kind,
        parent_path = res$payload$parent_path,
        parent_sha = res$payload$parent_sha,
        inherited_via_role_card_v1_7 = TRUE
      )
    } else {
      res$payload <- list(
        inheritance_cor_actual = res$payload$alpha_inheritance_cor,
        mechanism_cited_chars = res$payload$mechanism_cited_chars,
        factor_specs_new_count = res$payload$factor_specs_count,
        harvey_t_specs_pass_count = res$payload$harvey_t_specs_pass_count
      )
    }
  }
  res
}

check_sr_provenance_eligibility <- function(wt_dir) {
  fp_path <- file.path(wt_dir, "forge_package.json")
  if (!exists("cr_check_sr_provenance", mode = "function")) {
    return(list(eligible = FALSE, reason = "cert_rules.R 미로드"))
  }
  res <- cr_check_sr_provenance(fp_path)
  if (isTRUE(res$eligible)) {
    # backward compat: keep "all_4_fields_pass" plural (기존 사용)
    res$reason <- "all_4_fields_pass"
  }
  res
}

check_schedule_fidelity_eligibility <- function(wt_dir) {
  # v7.2.2 Sprint — promotion_wt + inherit_certs path 우선 처리 (L-283)
  inherit_ref_path <- file.path(wt_dir, "alpha_package_inherit_ref.json")
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
        return(list(
          eligible = TRUE,
          reason = "inherited_via_parent_alpha_package_per_role_card_v1_7",
          payload = list(
            inherit_kind = "schedule_fidelity",
            parent_path = parent_path,
            parent_sha = parent_sha,
            inherited_via_role_card_v1_7 = TRUE
          )
        ))
      }
    }
  }

  weights_path <- file.path(wt_dir, "weights.csv")
  alpha_path <- file.path(wt_dir, "alpha_package.json")

  if (!file.exists(weights_path)) {
    weights_path_alt <- file.path(wt_dir, "judge_ready", "weights.csv")
    if (file.exists(weights_path_alt)) {
      weights_path <- weights_path_alt
    } else {
      return(list(eligible = FALSE, reason = "weights.csv 부재 (root + judge_ready/)"))
    }
  }
  if (!file.exists(alpha_path)) {
    return(list(eligible = FALSE, reason = "alpha_package.json 부재"))
  }

  weights_dt <- tryCatch(fread(weights_path, select = 1L),
                          error = function(e) NULL)
  if (is.null(weights_dt) || nrow(weights_dt) == 0) {
    return(list(eligible = FALSE, reason = "weights.csv 읽기 실패"))
  }
  weights_dates <- length(unique(weights_dt[[1]]))

  alpha <- tryCatch(fromJSON(alpha_path, simplifyVector = FALSE),
                    error = function(e) NULL)
  if (is.null(alpha)) {
    return(list(eligible = FALSE, reason = "alpha_package.json parse 실패"))
  }
  diag <- alpha$diagnostics %||% list()
  sig_dates <- diag$sig_dates_count %||% diag$n_sig_dates %||%
               (alpha$alpha_summary %||% list())$n_sig_dates %||%
               alpha$n_sig_dates %||% 0L

  if (sig_dates == 0) {
    return(list(eligible = FALSE, reason = "alpha_package sig_dates_count=0"))
  }

  # v7.0: threshold 0.95 = cert_rules.json single source (backfill도 같은 값 사용)
  threshold <- tryCatch(
    cr_load_policy()$certificates$schedule_fidelity$eligibility_OR$density$threshold,
    error = function(e) 0.95
  )
  ratio <- weights_dates / sig_dates
  if (ratio < threshold) {
    has_infeas <- !is.null(alpha$infeasibility_report) ||
                  !is.null(diag$schedule_skip_justified)
    if (!has_infeas) {
      return(list(eligible = FALSE,
                  reason = sprintf("density %.3f < %.2f + no infeasibility_report",
                                   ratio, threshold)))
    }
  }

  list(
    eligible = TRUE,
    reason = sprintf("density=%.3f", ratio),
    payload = list(
      weights_csv_unique_dates_count = weights_dates,
      alpha_sig_dates_count = sig_dates,
      schedule_density_ratio = round(ratio, 3),
      infeasibility_report_cited = ratio < threshold
    )
  )
}

check_forge_package_validated_eligibility <- function(wt_dir) {
  fp_path <- file.path(wt_dir, "forge_package.json")
  if (!exists("cr_check_forge_package_validated", mode = "function")) {
    return(list(eligible = FALSE, reason = "cert_rules.R 미로드"))
  }
  res <- cr_check_forge_package_validated(fp_path)
  if (isTRUE(res$eligible)) {
    # backward compat: 기존 reason "all_8_fields_pass" + payload validated_fields_count=8L
    res$reason <- "all_8_fields_pass"
    res$payload <- list(validated_fields_count = 8L)
  }
  res
}

check_governor_concord_eligibility <- function(book_state_path,
                                                governor_dir,
                                                wt_root) {
  bs <- tryCatch(fromJSON(book_state_path, simplifyVector = FALSE),
                 error = function(e) NULL)
  if (is.null(bs)) {
    return(list(eligible = FALSE, reason = "book_state parse 실패"))
  }
  admitted_ids <- bs$admitted_ids %||% list()
  weights <- bs$book_weights %||% list()

  if (length(admitted_ids) == 0) {
    return(list(eligible = FALSE, reason = "no admitted_ids"))
  }

  details <- list()
  all_match <- TRUE
  for (sid in admitted_ids) {
    sid <- as.character(sid)
    lineage <- audit_str_lineage(sid, wt_root)
    if (length(lineage) == 0) {
      all_match <- FALSE
      details[[length(details) + 1]] <- list(
        str_id = sid, match = FALSE, reason = "no governor_admission found"
      )
      next
    }
    primary <- NULL
    for (item in lineage) {
      if (identical(item$ga_str_id, sid)) { primary <- item; break }
    }
    if (is.null(primary)) primary <- lineage[[1]]
    ga <- tryCatch(fromJSON(file.path(primary$wt_dir, "governor_admission.json"),
                            simplifyVector = FALSE), error = function(e) NULL)
    if (is.null(ga)) {
      all_match <- FALSE
      details[[length(details) + 1]] <- list(
        str_id = sid, match = FALSE, reason = "ga parse 실패", wt_dir = primary$wt_dir
      )
      next
    }
    expected <- (ga$allocation_decided %||% list())[[sid]]
    actual <- weights[[sid]]
    is_match <- !is.null(expected) && !is.null(actual) && abs(expected - actual) < 0.01
    if (!is_match) all_match <- FALSE
    details[[length(details) + 1]] <- list(
      str_id = sid,
      admitted_scenario = ga$admission_scenario %||% "",
      expected_weight = expected,
      actual_weight = actual,
      match = is_match,
      wt_dir = primary$wt_dir
    )
  }

  list(
    eligible = all_match,
    reason = if (all_match) "all_admitted_match" else "some_mismatch",
    payload = list(
      concord_type = if (all_match) "match" else "with_waiver_required",
      all_admitted_match = all_match,
      details = details
    )
  )
}

#==============================================================================
# 3. Cert 직접 발급 (Option B — Hook bypass)
#==============================================================================
issue_cert_directly <- function(cert_path, cert_type, wt_id, payload, dry_run = FALSE) {
  cert_data <- list(
    issued = TRUE,
    wt_id = wt_id,
    issued_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    issued_by = "cert_backfill_audit.R v1.0 (R direct write — Hook bypass)",
    charter_ref = CHARTER_REF,
    backfill_provenance = list(
      lineage_transparency_note = "Direct R write per Layer 2 design (R script file write가 PostToolUse Hook 시야 밖이라 manual issue). Schema는 hook과 동일.",
      no_new_backtest_executed = TRUE,
      payload_source = "live audit of WT artifacts"
    )
  )
  cert_data <- c(cert_data, payload)

  if (dry_run) {
    log_msg(sprintf("    [DRY] would issue %s → %s", cert_type, cert_path))
    return(invisible(TRUE))
  }

  write_json(cert_data, cert_path, auto_unbox = TRUE, pretty = TRUE)
  log_msg(sprintf("    [ISSUED] %s → %s", cert_type, basename(cert_path)))
  invisible(TRUE)
}

#==============================================================================
# 4. WT 단위 backfill — 각 WT의 누락 cert 5종 검사 + 발급
#==============================================================================
backfill_wt <- function(wt_dir, book_state_path, governor_dir, wt_root,
                         mode = "auto", dry_run = FALSE) {
  wt_id <- basename(wt_dir)
  log_msg(sprintf("--- backfill WT %s (%s) ---", wt_id, mode))

  ga_path <- file.path(wt_dir, "governor_admission.json")
  if (!file.exists(ga_path)) {
    log_msg(sprintf("  governor_admission.json 부재 — skip (admission lifecycle 외)"))
    return(list(wt_id = wt_id, skipped = TRUE, reason = "no_admission"))
  }
  ga <- tryCatch(fromJSON(ga_path, simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(ga)) {
    log_msg(sprintf("  ga parse 실패 — skip"))
    return(list(wt_id = wt_id, skipped = TRUE, reason = "ga_parse_fail"))
  }

  wt_type <- ga$wt_type %||% "unknown"
  is_deployment <- identical(wt_type, "deployment")

  # Governor의 ELIGIBLE_FOR_ISSUANCE 명시 확인 (auto mode 우선순위)
  pg1_check <- ga$pg1_admission_check %||% list()
  charter_compliance <- (ga$charter_compliance %||%
                          list())$v1_2_section_10_5_certificate_system %||% list()
  cert_eligibility_hints <- list()
  for (ct in CERT_TYPES) {
    key <- paste0(ct, "_certificate")
    h1 <- (pg1_check[[key]] %||% list())$issuance_status
    h2 <- charter_compliance[[key]]
    cert_eligibility_hints[[ct]] <- !is.null(h1) || !is.null(h2)
  }

  results <- list()
  for (cert_type in CERT_TYPES) {
    cert_path <- file.path(wt_dir, paste0(cert_type, "_certificate.json"))

    # 이미 issued=TRUE면 skip
    if (file.exists(cert_path)) {
      cert_existing <- tryCatch(fromJSON(cert_path, simplifyVector = FALSE),
                                 error = function(e) NULL)
      if (!is.null(cert_existing) && isTRUE(cert_existing$issued)) {
        log_msg(sprintf("  [SKIP] %s already issued", cert_type))
        results[[cert_type]] <- list(action = "skip_existing", issued = TRUE)
        next
      }
    }

    # alpha_discovery: deployment WT는 면제 (Charter §10 role card)
    if (cert_type == "alpha_discovery" && is_deployment) {
      log_msg(sprintf("  [N/A] alpha_discovery — deployment WT 면제 (discovery WT inherit)"))
      results[[cert_type]] <- list(action = "exempt_deployment_inherit", issued = NA)
      next
    }

    # ★RETIRED (v10 2026-09-03): governor 폐지 — 신규 발급 중단. 이 가드가 없으면 bootstrap 7c(--auto)가
    #   legacy 동결 디렉터리(qepm/mailbox/governor/)에 새 cert 를 쓴다(book_write_guard 는 Claude Write 도구만 막는다).
    if (cert_type == "governor_concord") {
      log_msg("  [RETIRED v10] governor_concord — 발급 중단(governor 폐지 2026-08-29)")
      results[[cert_type]] <- list(action = "retired_v10", issued = FALSE)
      next
    }

    # (사료) governor_concord: WT_DIR이 아니라 governor_dir에 발급
    if (FALSE) {
      cert_path_global <- file.path(governor_dir, "governor_concord_certificate.json")
      if (file.exists(cert_path_global)) {
        log_msg(sprintf("  [SKIP] governor_concord already at governor_dir"))
        results[[cert_type]] <- list(action = "skip_existing_global", issued = TRUE)
        next
      }
    }

    # auto mode: ELIGIBLE 명시 우선 + eligibility check
    if (mode == "auto" && !isTRUE(cert_eligibility_hints[[cert_type]]) &&
        cert_type != "governor_concord") {
      # Governor가 명시 안 했으면 auto에서 skip (manual로 강제 가능)
      log_msg(sprintf("  [PASS_AUTO] %s — Governor ELIGIBLE 명시 없음 (manual mode로 강제 가능)",
                      cert_type))
      results[[cert_type]] <- list(action = "skip_auto_no_hint", issued = NA)
      next
    }

    elig <- switch(cert_type,
      alpha_discovery = check_alpha_discovery_eligibility(wt_dir),
      sr_provenance = check_sr_provenance_eligibility(wt_dir),
      schedule_fidelity = check_schedule_fidelity_eligibility(wt_dir),
      forge_package_validated = check_forge_package_validated_eligibility(wt_dir),
      governor_concord = check_governor_concord_eligibility(book_state_path,
                                                              governor_dir, wt_root)
    )

    if (!isTRUE(elig$eligible)) {
      log_msg(sprintf("  [INELIGIBLE] %s: %s", cert_type, elig$reason))
      results[[cert_type]] <- list(action = "ineligible",
                                     reason = elig$reason, issued = FALSE)
      # alpha_discovery NOT_ISSUED는 별도 cert 파일 작성 (passive deny 명시)
      if (cert_type == "alpha_discovery") {
        cert_data <- list(
          issued = FALSE,
          wt_id = wt_id,
          issued_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
          issued_by = "cert_backfill_audit.R v1.0",
          charter_ref = CHARTER_REF,
          non_issuance_reason = elig$reason,
          remediation = "alpha agent rerun: cor < 0.95 + mechanism >= 50 chars + factor_specs >= 1 + harvey_t pass >= 3"
        )
        cert_data <- c(cert_data, elig$payload %||% list())
        if (!dry_run) write_json(cert_data, cert_path,
                                  auto_unbox = TRUE, pretty = TRUE)
      }
      next
    }

    cert_path_final <- if (cert_type == "governor_concord") {
      file.path(governor_dir, "governor_concord_certificate.json")
    } else {
      cert_path
    }

    issue_cert_directly(cert_path_final, cert_type, wt_id,
                        payload = elig$payload, dry_run = dry_run)
    results[[cert_type]] <- list(action = "issued", issued = TRUE)
  }

  list(wt_id = wt_id, wt_type = wt_type, results = results)
}

#==============================================================================
# 5. governance_log 기록
#==============================================================================
record_governance_log <- function(governor_dir, run_summary, dry_run = FALSE) {
  log_path <- file.path(governor_dir, "governance_log.json")
  entry <- list(
    timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    action = "RETROACTIVE_CERT_ISSUANCE",
    triggered_by = "cert_backfill_audit.R Layer 2",
    charter_ref = CHARTER_REF,
    summary = run_summary
  )

  if (dry_run) {
    log_msg("  [DRY] governance_log entry not written")
    return(invisible(NULL))
  }

  #──────────────────────────────────────────────────────────────────────────────
  # (2026-07-26 CBA-04 수리, probe② 감사 확정 · 도훈 승인) 구현은 파스 실패를
  #   `error = function(e) list()` 로 흡수한 뒤 그 빈 list 를 **원본에 덮어썼다**.
  #   governance_log.json 이 일시적으로 읽기 불가(OneDrive 자리표시자/락/부분 쓰기/파손)인
  #   상태에서 백필이 1회 돌면 admission_log·event_* 등 **거버넌스 이력 전체가 무경고 소실**된다.
  #   fail-open 중에서도 파괴적 부류 — 되돌릴 수 없다.
  #   원칙: 읽을 수 없는 것은 덮어쓰지 않는다. 파스 실패/스키마 이상 시
  #     ① 원본 무수정 ② 사이드카(governance_log_backfill_pending.json)에 엔트리 격리
  #     ③ log_msg 로 명시 — 다음 실행이 아니라 사람이 판단할 문제.
  #   정상 경로에서도 덮어쓰기 직전 원본 바이트 백업을 남긴다(.bak.<ts>).
  #──────────────────────────────────────────────────────────────────────────────
  .quarantine <- function(reason) {
    side <- file.path(dirname(log_path), "governance_log_backfill_pending.json")
    prev <- if (file.exists(side))
      tryCatch(fromJSON(side, simplifyVector = FALSE), error = function(e) list()) else list()
    if (!is.list(prev)) prev <- list()
    prev[[length(prev) + 1]] <- list(quarantined_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
                                     reason = reason, entry = entry)
    tryCatch(write_json(prev, side, auto_unbox = TRUE, pretty = TRUE),
             error = function(e) log_msg(sprintf("  ★사이드카 기록마저 실패: %s", conditionMessage(e))))
    log_msg(sprintf(paste0("  ★governance_log 덮어쓰기 **중단** — %s. 원본 무수정 유지, ",
                           "엔트리를 사이드카로 격리: %s (사람이 병합 판단)"), reason, side))
  }

  if (file.exists(log_path)) {
    parsed <- tryCatch(fromJSON(log_path, simplifyVector = FALSE),
                       error = function(e) structure(list(msg = conditionMessage(e)),
                                                     class = "gl_parse_fail"))
    if (inherits(parsed, "gl_parse_fail")) {
      .quarantine(sprintf("파스 실패(%s)", parsed$msg)); return(invisible(FALSE))
    }
    if (!is.list(parsed) || is.null(names(parsed))) {
      .quarantine("스키마 이상(named list 아님 — 배열형/스칼라)"); return(invisible(FALSE))
    }
    existing <- parsed
    # 덮어쓰기 전 원본 바이트 백업 (비가역 변경 직전 스냅샷)
    bak <- sprintf("%s.bak.%s", log_path, format(Sys.time(), "%Y%m%d_%H%M%S"))
    tryCatch(file.copy(log_path, bak, overwrite = FALSE),
             error = function(e) log_msg(sprintf("  WARN: 백업 실패 %s", conditionMessage(e))))
  } else {
    existing <- list()   # 신규 생성 — 소실 위험 없음
  }

  retro_logs <- existing$retroactive_cert_issuances %||% list()
  retro_logs[[length(retro_logs) + 1]] <- entry
  existing$retroactive_cert_issuances <- retro_logs

  write_json(existing, log_path, auto_unbox = TRUE, pretty = TRUE)
  log_msg(sprintf("  governance_log updated: %s", log_path))
}

#==============================================================================
# 6. 진입점 — main 함수
#==============================================================================
cert_backfill_main <- function(book_state_path,
                                wt_root = "qepm/mailbox/worktask",
                                governor_dir = NULL,
                                mode = "auto",
                                target_wt = NULL,
                                dry_run = FALSE) {
  log_init(); on.exit(log_close(), add = TRUE)

  if (is.null(governor_dir)) governor_dir <- dirname(book_state_path)

  bs <- tryCatch(fromJSON(book_state_path, simplifyVector = FALSE),
                 error = function(e) NULL)
  if (is.null(bs)) {
    log_msg("ERROR: book_state.json parse 실패")
    return(invisible(list(error = "book_state_parse_fail")))
  }
  admitted_ids <- as.character(bs$admitted_ids %||% list())

  wt_targets <- if (!is.null(target_wt)) {
    # target_wt: 콤마 구분 또는 단일 WT ID
    targets <- strsplit(target_wt, ",")[[1]]
    targets <- trimws(targets)
    targets <- targets[nchar(targets) > 0]
    file.path(wt_root, targets)
  } else {
    # admitted_ids 전체 lineage 수집
    all_wts <- character()
    for (sid in admitted_ids) {
      lineage <- audit_str_lineage(sid, wt_root)
      all_wts <- c(all_wts, sapply(lineage, function(x) x$wt_dir))
    }
    unique(all_wts)
  }

  log_msg(sprintf("Mode: %s | Targets: %d WT(s) | Dry-run: %s",
                  mode, length(wt_targets), dry_run))
  log_msg(sprintf("Admitted IDs: %s", paste(admitted_ids, collapse = ", ")))

  all_results <- list()
  for (wd in wt_targets) {
    if (!dir.exists(wd)) {
      log_msg(sprintf("  SKIP %s — directory missing", wd))
      next
    }
    res <- backfill_wt(wd, book_state_path, governor_dir, wt_root,
                       mode = mode, dry_run = dry_run)
    all_results[[basename(wd)]] <- res
  }

  # governance_log
  summary <- list(
    mode = mode,
    target_wt = target_wt %||% "all_admitted_lineage",
    n_wts_processed = length(all_results),
    per_wt = all_results
  )
  if (!dry_run) record_governance_log(governor_dir, summary, dry_run = FALSE)

  # 최종 audit re-run (measurement_basis_audit.R)
  log_msg("\n=== Post-backfill measurement_basis_audit re-run ===")
  audit_script <- file.path(dirname(dirname(getwd())), "02_Infrastructure",
                             "portfolio", "measurement_basis_audit.R")
  if (!file.exists(audit_script)) {
    audit_script <- "02_Infrastructure/portfolio/measurement_basis_audit.R"
  }
  if (file.exists(audit_script)) {
    # (2026-07-26 CBA-06 수리, r-portability 기지 항목의 행동 실증) Windows R 의 system()
    #   은 셸을 경유하지 않아 "2>&1 | grep -E ..." 가 내부 Rscript 의 **리터럴 argv** 로
    #   전달됐다. measurement_basis_audit.R 이 args[3+] 를 무시해서 우연히 동작했고,
    #   로그에는 grep 필터가 전혀 안 걸린 전체 출력이 남아 있었다(실증). 내부 스크립트가
    #   argv 검증을 도입하는 순간 조용히 파손된다. 또 stderr 미캡처 + system() 실패는
    #   warning 으로만 삼켜져 내부 감사가 'Tier:' 전에 죽으면 원인 추적이 불가했다.
    #   → system2 인자 벡터 + stdout/stderr 캡처 + exit status 명시 검사, 필터는 R 에서.
    audit_raw <- suppressWarnings(
      system2("Rscript", args = c(audit_script, book_state_path, wt_root),
              stdout = TRUE, stderr = TRUE))
    audit_st <- attr(audit_raw, "status")
    if (!is.null(audit_st) && audit_st != 0) {
      log_msg(sprintf("  ★내부 coherence 감사 exit=%s — 아래 판정은 신뢰 불가 (출력 말미: %s)",
                      audit_st, paste(utils::tail(audit_raw, 2), collapse = " | ")))
    }
    audit_out <- grep("Book score|Tier", audit_raw, value = TRUE)
    log_msg(paste(audit_out, collapse = "\n"))
  }

  invisible(all_results)
}

#==============================================================================
# 7. CLI 진입점
#==============================================================================
parse_cli_args <- function(args) {
  res <- list(mode = "auto", target = NULL, dry_run = FALSE,
              book_state = "qepm/mailbox/governor/book_state.json",
              wt_root = "qepm/mailbox/worktask")
  for (a in args) {
    if (a == "--auto") res$mode <- "auto"
    else if (a == "--manual") res$mode <- "manual"
    else if (a == "--dry-run") res$dry_run <- TRUE
    else if (grepl("^--target=", a)) res$target <- sub("^--target=", "", a)
    else if (grepl("^--book=", a)) res$book_state <- sub("^--book=", "", a)
    else if (grepl("^--wt-root=", a)) res$wt_root <- sub("^--wt-root=", "", a)
  }
  res
}

if (!interactive() && length(commandArgs(trailingOnly = TRUE)) >= 0) {
  args <- commandArgs(trailingOnly = TRUE)
  cli <- parse_cli_args(args)
  cat(sprintf("=== cert_backfill_audit.R Layer 2 ===\n"))
  cat(sprintf("Mode: %s | Target: %s | Dry-run: %s\n",
              cli$mode, cli$target %||% "all", cli$dry_run))
  cert_backfill_main(book_state_path = cli$book_state,
                      wt_root = cli$wt_root,
                      mode = cli$mode,
                      target_wt = cli$target,
                      dry_run = cli$dry_run)
}
