#==============================================================================
# QEPM v6.1 Compliance Audit — L-203 (2026-04-24)
#
# Purpose: 8 원칙(P1~P8) 자동 검증. WT 전수 또는 개별 WT 감사.
#
#   P1: Selection Freedom  — method_shopping_log 전수 + candidates 분포
#   P2: Data Separation    — lockbox access audit zero-violation
#   P3: Role-specific Obj  — selection_objective 도메인 준수
#   P4: Challenge Obligation — challenge_note count ≥ 1 (Risk/Opt)
#   P5: Book-level Primacy — Governor admission에 book_state 참조 필수
#   P6: Hard vs Soft       — Discovery SOFT 면제 + Deployment 전수 적용
#   P7: Lineage            — artifact_lineage.json git_commit + hash 전수
#   P8: Monitoring         — admitted 2개월+ monitoring 누락 없음
#==============================================================================

suppressPackageStartupMessages({
  library(jsonlite)
  library(data.table)
})

`%||%` <- function(a, b) if (!is.null(a)) a else b

#─── 경로 해석 (r-portability.md 금칙 ③) ──────────────────────────────────────
# 2026-08-02 수리. 구 구현의 두 결함:
#   (1) LOCKBOX_LOG_PATTERN 이 선행 슬래시 tmp 경로 리터럴이었다
#       → Windows R 은 선행 `/` 를 현재 드라이브 기준으로 해석해 C:/tmp 를 읽는데,
#         실제 기록자인 bash 훅은 MSYS `/tmp`(=AppData\Local\Temp)에 쓴다.
#         실측: bash 쪽 4건 / C:/tmp 0건 → `!file.exists()` 가 항상 참 →
#         **P2 는 237/237 WT 에서 구조적으로 pass=TRUE**. 실패 자체가 불가능했다.
#   (2) WT_ROOT / BOOK_STATE / MONITORING_DIR 이 **상대경로**
#       → cwd 가 루트가 아니면 136KB 실파일이 있는데도 P8 이 "no_book_state_yet" 으로 통과.
#         실측: cwd 를 한 단계 위로 옮기면 그대로 재현.
# 공통 기전은 같다 — **결손을 정상값으로 내려앉히는 것**. 아래는 경로를 절대화하고,
# 나아가 "못 쟀다"를 PASS 가 아니라 NA(SKIP)로 보고하도록 판정 의미까지 바꾼다.
.v61_find_root <- function() {
  marker <- "02_Infrastructure/hooks/qvest_hook_router.py"   # 존재검사 아닌 정체성 검사
  cands <- c(Sys.getenv("CLAUDE_PROJECT_DIR", unset = ""),
             Sys.getenv("QM_ROOT", unset = ""))
  for (cand in cands[nzchar(cands)]) {
    p <- normalizePath(gsub("\\\\", "/", cand), winslash = "/", mustWork = FALSE)
    if (file.exists(file.path(p, marker))) return(p)
  }
  here <- normalizePath(getwd(), winslash = "/", mustWork = FALSE)
  repeat {
    if (file.exists(file.path(here, marker))) return(here)
    parent <- dirname(here)
    if (identical(parent, here)) break
    here <- parent
  }
  stop("[v61_compliance_audit] project root 미발견 — CLAUDE_PROJECT_DIR 또는 QM_ROOT 설정 필요")
}
V61_ROOT <- .v61_find_root()

# lockbox 접근기록 경로는 bash 훅과 공유 → 리터럴을 여기 두지 않는다(단일 정의 경유).
source(file.path(V61_ROOT, "02_Infrastructure/worktask/lockbox_paths.R"))

WT_ROOT        <- file.path(V61_ROOT, "qepm/mailbox/worktask")
BOOK_STATE     <- file.path(V61_ROOT, "qepm/mailbox/governor/book_state.json")
MONITORING_DIR <- file.path(V61_ROOT, "qepm/mailbox/monitoring/reports")

# P2 위반 판정 대상 역할. **lockbox-scope mandate(도훈 2026-05-09)와 정합**:
#   적용  = alpha / risk / optimizer (정규 리서치)
#   폐기  = judge(접근권) / forge / monitoring / execution / Q-Lead (운용·트래킹)
# ⚠ 구 패턴은 `forge` 를 위반으로 셌다 — 이 파일이 2026-04-24 작성분이라 05-09 mandate
#   이전 판정이 남아 있던 것이다. `selection_contamination_detector.sh` 는 이미 forge 를
#   allow 하고 있어 훅과 감사가 서로 다른 규칙을 쓰고 있었다. mandate 쪽으로 통일한다.
#   (되돌리려면 이 상수에 |forge 를 다시 넣으면 된다 — 판정 의미가 한 곳에만 있다.)
P2_VIOLATION_PATTERN <- "\\| *(alpha|risk|optimizer|opt_)"

# ─── P1 Selection Freedom ───────────────────────────────
audit_p1_selection_freedom <- function(wt_id) {
  wt_dir <- file.path(WT_ROOT, wt_id)
  log_path <- file.path(wt_dir, "method_shopping_log.json")
  alpha_path <- file.path(wt_dir, "alpha_package.json")

  if (!file.exists(log_path)) {
    return(list(principle = "P1", pass = FALSE,
                reason = "method_shopping_log.json missing"))
  }
  log <- fromJSON(log_path, simplifyVector = FALSE)

  limits <- list(alpha_agent = 5, risk_agent = 5, optimizer_agent = 10)
  issues <- c()
  for (agent in names(limits)) {
    n <- log[[agent]]$candidates_tried %||% 0
    if (n > limits[[agent]]) {
      issues <- c(issues, sprintf("%s candidates_tried %d > %d",
                                   agent, n, limits[[agent]]))
    }
  }

  list(
    principle = "P1",
    pass = length(issues) == 0,
    reason = if (length(issues) == 0) "within_limits" else paste(issues, collapse = "; "),
    details = log
  )
}

# ─── P2 Data Separation — ★RETIRED (v10 2026-08-29) ─────────────────────────
# lockbox 제도 폐지(도훈 "lock box 개념은 삭제. 반박 금지") — 이 축은 판정 대상이
# 사라졌다. 항상 pass = NA + reason = "retired" 를 반환한다(축 번호는 보존 —
# 리포트 스키마 호환). 구 3분기 판정 로직은 git 사료(pre-v10-2layer).
audit_p2_data_separation <- function(wt_id) {
  return(list(principle = "P2", pass = NA,
              reason = "retired: lockbox 제도 폐지 (v10 2026-08-29 도훈 지시) — 판정 대상 없음"))
}

.audit_p2_data_separation_retired_v9 <- function(wt_id) {
  trail <- qvest_lockbox_trail_state(root = V61_ROOT)
  log_path <- qvest_lockbox_log(wt_id, root = V61_ROOT)

  # 아직 수리 안 된 writer 탐지 — 레거시 위치에 새 파일이 생기면 표면화(판정 evidence 아님)
  legacy <- qvest_lockbox_legacy_logs()
  legacy_warn <- if (length(legacy) > 0)
    sprintf(" [WARN legacy_trail=%d: %s]", length(legacy),
            paste(basename(legacy), collapse = ",")) else ""

  if (!file.exists(log_path)) {
    if (!isTRUE(trail$live)) {
      return(list(principle = "P2", pass = NA,
                  reason = sprintf("unmeasured: audit-trail 발화 기록 없음 (heartbeat 부재, dir=%s)%s",
                                   trail$dir, legacy_warn),
                  trail_dir = trail$dir))
    }
    return(list(principle = "P2", pass = TRUE,
                reason = sprintf("no_lockbox_access (trail live, last_fire=%s)%s",
                                 trail$last %||% "NA", legacy_warn),
                trail_dir = trail$dir))
  }

  lines <- readLines(log_path, warn = FALSE)
  violations <- grep(P2_VIOLATION_PATTERN, lines, value = TRUE)
  list(
    principle = "P2",
    pass = length(violations) == 0,
    reason = if (length(violations) == 0)
               sprintf("no_research_stage_access (entries=%d)%s", length(lines), legacy_warn)
             else sprintf("CONTAMINATION: %d research-stage accesses (of %d entries)%s",
                          length(violations), length(lines), legacy_warn),
    violations = violations,
    log_path = log_path
  )
}

# ─── P3 Role-specific Objective ─────────────────────────
audit_p3_role_objective <- function(wt_id) {
  wt_dir <- file.path(WT_ROOT, wt_id)
  packages <- list(
    alpha = list(
      path = file.path(wt_dir, "alpha_package.json"),
      allowed = c("canonical_port_t", "rank_ic", "icir", "monotonicity", "subperiod_stability")  # v8.3 M1 2026-07-10: canonical_port_t 추가 (role_objective_guard.sh·schema.json enum 정합)
    ),
    risk = list(
      path = file.path(wt_dir, "risk_package.json"),
      allowed = c("condition_number", "stress_robust", "crowding", "shrinkage_quality")
    ),
    optimizer = list(
      path = file.path(wt_dir, "optimization_package.json"),
      allowed = c("net_ir", "to_adj_ret", "uncertainty_penalty", "crowding_adj_ret")
    )
  )

  issues <- c()
  for (agent in names(packages)) {
    p <- packages[[agent]]
    if (!file.exists(p$path)) next
    pkg <- fromJSON(p$path, simplifyVector = FALSE)
    obj <- pkg$selection_objective %||% NA
    if (is.na(obj) || !obj %in% p$allowed) {
      issues <- c(issues, sprintf("%s selection_objective='%s' not in [%s]",
                                   agent, obj, paste(p$allowed, collapse = ",")))
    }
  }

  list(
    principle = "P3",
    pass = length(issues) == 0,
    reason = if (length(issues) == 0) "all_agents_within_domain" else paste(issues, collapse = "; ")
  )
}

# ─── P4 Challenge Obligation ────────────────────────────
# Risk & Optimizer가 최소 한 번 반론 검토 (null이어도 명시)
audit_p4_challenge <- function(wt_id) {
  wt_dir <- file.path(WT_ROOT, wt_id)
  gov_path <- file.path(wt_dir, "governance_log.json")
  if (!file.exists(gov_path)) {
    return(list(principle = "P4", pass = FALSE, reason = "governance_log_missing"))
  }
  gov <- fromJSON(gov_path, simplifyVector = FALSE)
  events <- gov$events %||% list()
  # GAP-1 수정: CHALLENGE_REVIEWED 도 인정 (NO_OBJECTION 명시 기록 포함)
  challenges <- Filter(function(e) {
    e$action %in% c("CHALLENGE_RAISED", "CHALLENGE_NO_OBJECTION", "CHALLENGE_REVIEWED")
  }, events)
  # Risk / Optimizer 각각 최소 1회 review 필수
  reviewers <- unique(sapply(challenges, function(e) e$agent %||% ""))
  has_risk <- "risk" %in% reviewers
  has_opt <- "optimizer" %in% reviewers
  pass <- has_risk && has_opt
  list(
    principle = "P4",
    pass = pass,
    reason = sprintf("challenge_events=%d / risk=%s / optimizer=%s (둘 다 필수)",
                     length(challenges), has_risk, has_opt),
    details = challenges
  )
}

# ─── P5 Book-level Primacy ──────────────────────────────
audit_p5_book_primacy <- function(wt_id) {
  wt_dir <- file.path(WT_ROOT, wt_id)
  adm_path <- file.path(wt_dir, "governor_admission.json")
  if (!file.exists(adm_path)) {
    return(list(principle = "P5", pass = NA, reason = "not_yet_admitted"))
  }
  adm <- fromJSON(adm_path, simplifyVector = FALSE)
  has_ref <- !is.null(adm$book_state_ref) || !is.null(adm$book_state_snapshot)
  list(
    principle = "P5",
    pass = has_ref,
    reason = if (has_ref) "book_state_referenced" else "book_state_missing_in_admission"
  )
}

# ─── P6 Hard vs Soft Tier ───────────────────────────────
audit_p6_tier <- function(wt_id) {
  wt_dir <- file.path(WT_ROOT, wt_id)
  req_path <- file.path(wt_dir, "request.json")
  if (!file.exists(req_path)) {
    return(list(principle = "P6", pass = FALSE, reason = "request.json missing"))
  }
  req <- fromJSON(req_path, simplifyVector = FALSE)
  wt_type <- req$wt_type %||% NA
  hc <- req$hard_constraints %||% list()

  if (wt_type == "discovery") {
    # SOFT 면제: max_names NULL 또는 SOFT 기록 금지
    if (!is.null(hc$max_names) && !is.na(hc$max_names) && hc$max_names > 0) {
      # discovery가 max_names 20 적용했다면 SOFT 주입 의심
      return(list(principle = "P6", pass = TRUE,
                  reason = sprintf("discovery with max_names=%s (allowed if user override)",
                                   hc$max_names)))
    }
    return(list(principle = "P6", pass = TRUE, reason = "discovery_soft_exempt"))
  } else if (wt_type == "deployment") {
    # SOFT 전수 강제
    issues <- c()
    if (is.null(hc$max_names) || hc$max_names > 20) issues <- c(issues, "max_names>20")
    bounds <- hc$weight_bounds %||% c(NA, NA)
    if (length(bounds) < 2 || bounds[2] > 0.20) issues <- c(issues, "weight_bound>0.20")
    lfloor <- hc$liquidity_min_won_20d_avg %||% 0
    if (lfloor < 2e8) issues <- c(issues, "liquidity<2e8")
    list(
      principle = "P6",
      pass = length(issues) == 0,
      reason = if (length(issues) == 0) "deployment_all_soft_enforced" else paste(issues, collapse = "; ")
    )
  } else {
    list(principle = "P6", pass = FALSE, reason = sprintf("invalid_wt_type=%s", wt_type))
  }
}

# ─── P7 Lineage ─────────────────────────────────────────
audit_p7_lineage <- function(wt_id) {
  wt_dir <- file.path(WT_ROOT, wt_id)
  lin_path <- file.path(wt_dir, "artifact_lineage.json")
  if (!file.exists(lin_path)) {
    return(list(principle = "P7", pass = FALSE, reason = "artifact_lineage.json missing"))
  }
  lin <- fromJSON(lin_path, simplifyVector = FALSE)
  entries <- lin$entries %||% list()
  if (length(entries) == 0) {
    return(list(principle = "P7", pass = FALSE, reason = "no_entries"))
  }
  # 전수 git_commit + file_hash 확인
  missing <- Filter(function(e) {
    is.null(e$git_commit) || is.null(e$file_hash_sha256) ||
      e$git_commit %in% c("unknown", "") || nchar(e$file_hash_sha256 %||% "") < 16
  }, entries)

  list(
    principle = "P7",
    pass = length(missing) == 0 && length(entries) >= 3,
    reason = sprintf("entries=%d missing_hash_or_commit=%d",
                     length(entries), length(missing))
  )
}

# ─── P8 Monitoring Coverage ─────────────────────────────
audit_p8_monitoring <- function() {
  # 구 구현은 BOOK_STATE 가 **상대경로**라 cwd 가 루트가 아니면 실파일(135,968 B)이 있는데도
  # "no_book_state_yet" 으로 PASS 했다. 절대경로화 + "못 쟀다"의 분리(NA)로 수리.
  if (!file.exists(BOOK_STATE)) {
    gov_dir <- dirname(BOOK_STATE)
    if (!dir.exists(gov_dir)) {
      return(list(principle = "P8", pass = NA,
                  reason = sprintf("unmeasured: governor mailbox 부재 (%s)", gov_dir)))
    }
    return(list(principle = "P8", pass = TRUE,
                reason = sprintf("no_book_state_yet (%s)", BOOK_STATE)))
  }
  bs <- fromJSON(BOOK_STATE, simplifyVector = FALSE)
  admitted <- bs$admitted_ids %||% list()
  if (length(admitted) == 0) {
    return(list(principle = "P8", pass = TRUE, reason = "no_admitted_wts"))
  }
  # 최근 2개월 내 monitoring_report 존재 여부
  now <- Sys.Date()
  last_2m <- seq(now, by = "-1 month", length.out = 3)[-1]
  months <- format(c(now, last_2m), "%Y%m")

  reports <- list.files(MONITORING_DIR, pattern = "monitoring_report_", full.names = TRUE)
  if (length(reports) == 0 && length(admitted) > 0) {
    return(list(principle = "P8", pass = FALSE,
                reason = sprintf("%d admitted WTs with no monitoring reports (dir=%s, exists=%s)",
                                 length(admitted), MONITORING_DIR, dir.exists(MONITORING_DIR))))
  }

  recent <- reports[sapply(reports, function(p) {
    any(sapply(months, function(m) grepl(m, p)))
  })]

  list(
    principle = "P8",
    pass = length(recent) >= 1,
    reason = sprintf("recent_reports=%d (expected ≥ 1 within 2 months)",
                     length(recent))
  )
}

# ─── Full audit per WT ──────────────────────────────────
audit_wt <- function(wt_id, verbose = TRUE) {
  results <- list(
    p1 = audit_p1_selection_freedom(wt_id),
    p2 = audit_p2_data_separation(wt_id),
    p3 = audit_p3_role_objective(wt_id),
    p4 = audit_p4_challenge(wt_id),
    p5 = audit_p5_book_primacy(wt_id),
    p6 = audit_p6_tier(wt_id),
    p7 = audit_p7_lineage(wt_id)
  )

  if (verbose) {
    cat(sprintf("\n=== v6.1 Compliance Audit: %s ===\n", wt_id))
    for (k in names(results)) {
      r <- results[[k]]
      mark <- if (isTRUE(r$pass)) "✓" else if (is.na(r$pass)) "—" else "✗"
      cat(sprintf("  %s %s: %s — %s\n",
                  mark, r$principle, if (isTRUE(r$pass)) "PASS" else if (is.na(r$pass)) "SKIP" else "FAIL",
                  r$reason))
    }
  }

  # Pass ratio (NA 제외)
  passes <- sapply(results, function(r) isTRUE(r$pass))
  skips <- sapply(results, function(r) is.na(r$pass))
  pass_count <- sum(passes)
  total_count <- sum(!skips)
  pass_rate <- if (total_count == 0) NA else pass_count / total_count

  list(
    task_id = wt_id,
    results = results,
    pass_count = pass_count,
    total_count = total_count,
    pass_rate = pass_rate,
    all_pass = all(passes | skips)
  )
}

# ─── Full audit across all active WTs + P8 global ────────
audit_all <- function() {
  wts <- list.files(WT_ROOT,
                    pattern = "^WT-?[DP]?[0-9]{8}_[0-9]{3}$",
                    full.names = FALSE)

  cat(sprintf("=== QEPM v6.1 Compliance Audit — %s ===\n",
              format(Sys.time(), "%Y-%m-%d %H:%M")))
  cat(sprintf("WTs audited: %d\n\n", length(wts)))

  per_wt <- lapply(wts, audit_wt, verbose = TRUE)
  names(per_wt) <- wts

  p8 <- audit_p8_monitoring()
  .mark <- function(x) if (isTRUE(x)) "✓" else if (is.na(x)) "—" else "✗"
  .word <- function(x) if (isTRUE(x)) "PASS" else if (is.na(x)) "SKIP" else "FAIL"
  cat(sprintf("\n=== Global P8 Monitoring ===\n"))
  cat(sprintf("  %s P8: %s — %s\n", .mark(p8$pass), .word(p8$pass), p8$reason))

  # Aggregate
  pass_counts <- sapply(per_wt, function(x) x$pass_count)
  total_counts <- sapply(per_wt, function(x) x$total_count)

  cat(sprintf("\n=== Aggregate ===\n"))
  cat(sprintf("  Per-WT passes: %d / %d total checks\n",
              sum(pass_counts), sum(total_counts)))
  cat(sprintf("  P8 global: %s\n", .word(p8$pass)))

  invisible(list(per_wt = per_wt, p8 = p8))
}

cat("[v61_compliance_audit.R] L-203 Loaded. Functions:\n")
cat("  audit_wt(wt_id)      — single WT P1~P7 audit\n")
cat("  audit_all()          — all WTs + P8 global\n")
cat("  audit_p1..audit_p8   — individual principle\n")
