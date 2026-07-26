#==============================================================================
# wt_timeline.R — v7.0 Sprint 6 WT Timeline Builder
#
# Per-WT timeline 산출 (events.jsonl + governance_log.json + cert files +
# codex_critic_response + status.json 통합).
#
# Output: qepm/observability/timelines/wt_{WT_ID}.json
#
# Fields:
#   - events[]      — governance_log + ledger entries chronological
#   - phases[]      — start/end/duration per phase
#   - certs[]       — 5 cert × ISSUED/NOT_ISSUED/REVOKED + reason
#   - failures[]    — codex stance + critical_concerns + abort reason
#   - retry_count   — codex round REVISE 후 재산출 횟수
#   - artifact_lineage[] — alpha → risk → optimizer → forge chain
#
# Usage:
#   Rscript wt_timeline.R --wt-id WT-D20260501_003
#   Rscript wt_timeline.R --rebuild-active-book   # bootstrap 자동
#==============================================================================

suppressPackageStartupMessages({
  library(jsonlite)
})

#──────────────────────────────────────────────────────────────────────────────
# (2026-07-26 WTL-3 수리, probe② 감사 확정 · 도훈 승인) 구 폴백은
#   ① CLAUDE_PROJECT_DIR 를 두 번 읽고(둘째 줄이 첫째와 동일 — QM_ROOT 로 넘어가는
#      의도였으나 실제로는 CPD 를 재조회) ② 최종 default 가 이 머신에 없는
#      "G:/Quant_Module_Moltbot" 하드코딩(r-portability 금칙 ③)이라, 두 env 가 모두
#      비면 존재하지 않는 루트를 조용히 채택하고 WT_ROOT 부재 → 매치 0 → "rebuilt 0" 을
#      정상처럼 출력했다(상수 출력 = 관측 위장).
#   수리: 후보 순회(CPD → QM_ROOT → 스크립트 상대) + **표지 검증** 후 채택,
#         전부 무효면 조용한 폴백 대신 fail-closed 종료.
#──────────────────────────────────────────────────────────────────────────────
.wtl_marker <- "02_Infrastructure/observability/wt_timeline.R"
.wtl_self_root <- local({
  a <- commandArgs(trailingOnly = FALSE)
  m <- grep("^--file=", a, value = TRUE)
  if (length(m) == 0L) return("")
  file.path(dirname(sub("^--file=", "", m[1L])), "..", "..")
})
PROJ_ROOT <- ""
for (.cand in c(Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""),
                .wtl_self_root, getwd())) {
  if (nzchar(.cand) && file.exists(file.path(.cand, .wtl_marker))) {
    PROJ_ROOT <- .cand; break
  }
}
if (!nzchar(PROJ_ROOT)) {
  cat(sprintf(paste0("[FATAL] wt_timeline: PROJECT_ROOT 해석 실패 — 표지 '%s' 를 가진 후보 없음. ",
                     "존재하지 않는 루트로 진행하면 '매치 0' 이 정상처럼 보인다(관측 위장).\n"),
              .wtl_marker))
  quit(status = 1)
}

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a

OBSERVABILITY_DIR <- file.path(PROJ_ROOT, "qepm/observability")
LEDGER_PATH <- file.path(OBSERVABILITY_DIR, "events.jsonl")
TIMELINES_DIR <- file.path(OBSERVABILITY_DIR, "timelines")
WT_ROOT <- file.path(PROJ_ROOT, "qepm/mailbox/worktask")

dir.create(TIMELINES_DIR, recursive = TRUE, showWarnings = FALSE)

build_wt_timeline <- function(wt_id) {
  wt_dir <- file.path(WT_ROOT, wt_id)
  if (!dir.exists(wt_dir)) {
    return(list(error = sprintf("WT dir not found: %s", wt_id)))
  }

  # 1. events from governance_log + events.jsonl
  events <- list()

  gov_path <- file.path(wt_dir, "governance_log.json")
  if (file.exists(gov_path)) {
    gov <- tryCatch(fromJSON(gov_path, simplifyVector = FALSE),
                    error = function(e) NULL)
    if (!is.null(gov$events)) {
      for (e in gov$events) {
        events[[length(events) + 1]] <- list(
          source = "governance_log",
          timestamp = e$timestamp %||% "",
          agent = e$agent %||% "",
          action = e$action %||% "",
          summary = e$summary %||% ""
        )
      }
    }
  }

  #──────────────────────────────────────────────────────────────────────────────
  # (2026-07-26 WTL-4 수리, probe② 감사 확정 · 도훈 승인) ledger 를 나이·내용 검증 없이
  #   소비했다. 실물 qepm/observability/events.jsonl 은 **247바이트 test fixture 1건**
  #   (event_type="test_event", hook_name="test_hook", file_path="/tmp/test.json",
  #   2026-05-01자)뿐 — 실이벤트 적재가 멈춘 stub 인데 timeline 에 **실 이벤트로 편입**됐고
  #   (실증: timelines/wt_WT-D20260501_003.json 에 test_hook 1건), timeline_built_at 이
  #   Sys.time() 으로 신선한 스탬프를 찍어 낡은 픽스처가 현재 관측처럼 보였다.
  #   수리: ① ledger 나이·행수를 timeline 에 기록 ② test_event/test_hook 은 편입 제외
  #        ③ 비었거나 30일+ stale 이면 ledger_status 로 명시.
  #──────────────────────────────────────────────────────────────────────────────
  ledger_status <- "ABSENT"
  ledger_age_days <- NA_real_
  ledger_n_lines <- 0L
  if (file.exists(LEDGER_PATH)) {
    ledger_lines <- tryCatch(readLines(LEDGER_PATH, warn = FALSE),
                              error = function(e) character())
    ledger_n_lines <- length(ledger_lines[nzchar(ledger_lines)])
    ledger_age_days <- tryCatch(
      as.numeric(difftime(Sys.time(), file.info(LEDGER_PATH)$mtime, units = "days")),
      error = function(e) NA_real_)
    ledger_status <- if (ledger_n_lines == 0L) "EMPTY"
                     else if (!is.na(ledger_age_days) && ledger_age_days > 30)
                       sprintf("STALE (%.0f일 미갱신, %d행) — 실이벤트 적재 정지 의심",
                               ledger_age_days, ledger_n_lines)
                     else sprintf("ok (%d행)", ledger_n_lines)
    for (line in ledger_lines) {
      if (!nzchar(line)) next
      entry <- tryCatch(fromJSON(line, simplifyVector = FALSE),
                         error = function(e) NULL)
      if (is.null(entry)) next
      # test fixture 는 관측이 아니다 — 실 이벤트로 편입 금지
      if (identical(entry$event_type %||% "", "test_event") ||
          identical(entry$hook_name %||% "", "test_hook")) next
      if (!is.null(entry$wt_id) && entry$wt_id == wt_id) {
        events[[length(events) + 1]] <- list(
          source = "events_jsonl",
          timestamp = entry$timestamp %||% "",
          agent = entry$agent_role %||% "",
          action = entry$event_type %||% "",
          summary = sprintf("hook=%s decision=%s",
                            entry$hook_name %||% "?", entry$decision %||% "?")
        )
      }
    }
  }

  # Sort events by timestamp
  if (length(events) > 0) {
    ts <- sapply(events, function(x) x$timestamp)
    events <- events[order(ts)]
  }

  # 2. phases — extract PHASE_ADVANCE entries
  phases <- list()
  current_start <- NA
  current_phase <- NA
  for (e in events) {
    if (grepl("PHASE_ADVANCE", e$action %||% "")) {
      if (!is.na(current_phase)) {
        phases[[length(phases) + 1]] <- list(
          phase = current_phase,
          start = current_start,
          end = e$timestamp,
          duration_seconds = NA  # parse 비용 회피
        )
      }
      current_start <- e$timestamp
      m <- regmatches(e$summary, regexec("-> (\\w+)", e$summary))
      if (length(m[[1]]) >= 2) current_phase <- m[[1]][2]
    }
  }
  if (!is.na(current_phase)) {
    phases[[length(phases) + 1]] <- list(
      phase = current_phase, start = current_start, end = NA,
      duration_seconds = NA
    )
  }

  # 3. certs — 5 cert status
  cert_types <- c("alpha_discovery", "sr_provenance", "schedule_fidelity",
                  "forge_package_validated", "governor_concord")
  certs <- list()
  for (ct in cert_types) {
    cert_path <- file.path(wt_dir, sprintf("%s_certificate.json", ct))
    if (file.exists(cert_path)) {
      cert_data <- tryCatch(fromJSON(cert_path, simplifyVector = FALSE),
                             error = function(e) NULL)
      if (!is.null(cert_data)) {
        certs[[ct]] <- list(
          status = if (isTRUE(cert_data$issued)) "ISSUED" else "NOT_ISSUED",
          issued_at = cert_data$issued_at %||% "",
          reason = if (isTRUE(cert_data$issued)) "all_pass" else
                    (cert_data$non_issuance_reason %||% "")
        )
      }
    } else {
      certs[[ct]] <- list(status = "ABSENT", issued_at = "", reason = "")
    }
  }

  # 4. failures — codex stance + critical_concerns
  failures <- list()
  codex_files <- list.files(wt_dir, pattern = "^codex_critic_response_",
                             full.names = TRUE)
  for (cf in codex_files) {
    cresp <- tryCatch(fromJSON(cf, simplifyVector = FALSE),
                       error = function(e) NULL)
    if (is.null(cresp)) next
    if (!is.null(cresp$stance) && cresp$stance != "APPROVE") {
      n_high <- sum(sapply(cresp$critical_concerns %||% list(),
                            function(c) identical(c$severity, "HIGH")))
      failures[[length(failures) + 1]] <- list(
        source = basename(cf),
        agent_role = cresp$agent_role %||% "",
        stance = cresp$stance,
        critical_concerns_count = length(cresp$critical_concerns %||% list()),
        high_count = n_high,
        weakest_assumption = cresp$weakest_assumption %||% ""
      )
    }
  }

  # 5. retry_count — count REVISE events
  retry_count <- if (length(events) == 0) 0L else {
    sum(vapply(events, function(e) {
      isTRUE(grepl("REVISE|REVISION", as.character(e$action %||% "")))
    }, logical(1)))
  }

  # 6. artifact_lineage — alpha → risk → opt → forge → judge → governor
  lineage <- list()
  artifact_files <- list(
    list(role = "alpha", file = "alpha_package.json"),
    list(role = "risk", file = "risk_package.json"),
    list(role = "optimizer", file = "optimization_package.json"),
    list(role = "forge", file = "forge_package.json"),
    list(role = "judge", file = "judge_verdict.json"),
    list(role = "governor", file = "governor_admission.json")
  )
  for (af in artifact_files) {
    fp <- file.path(wt_dir, af$file)
    if (file.exists(fp)) {
      info <- file.info(fp)
      lineage[[length(lineage) + 1]] <- list(
        role = af$role,
        artifact_path = file.path("qepm/mailbox/worktask", wt_id, af$file),
        generated_at = format(info$mtime, "%Y-%m-%dT%H:%M:%S%z"),
        size_bytes = info$size
      )
    }
  }

  status_path <- file.path(wt_dir, "status.json")
  current_status <- if (file.exists(status_path)) {
    tryCatch(fromJSON(status_path, simplifyVector = TRUE),
             error = function(e) NULL)
  } else NULL

  list(
    wt_id = wt_id,
    timeline_built_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    # (WTL-4) built_at 은 항상 신선하다 — 원천 ledger 의 상태를 함께 실어야
    #   "낡은 픽스처가 현재 관측처럼" 보이는 것을 소비자가 알 수 있다.
    ledger_status = ledger_status,
    ledger_age_days = if (is.na(ledger_age_days)) NULL else round(ledger_age_days, 1),
    current_phase = current_status$current_phase %||% "UNKNOWN",
    events = events,
    phases = phases,
    certs = certs,
    failures = failures,
    retry_count = retry_count,
    artifact_lineage = lineage
  )
}

save_wt_timeline <- function(wt_id) {
  tl <- build_wt_timeline(wt_id)
  if (!is.null(tl$error)) {
    cat(sprintf("[ERROR] %s\n", tl$error))
    return(invisible(FALSE))
  }
  out <- file.path(TIMELINES_DIR, sprintf("wt_%s.json", wt_id))
  write_json(tl, out, pretty = TRUE, auto_unbox = TRUE, null = "null")
  cat(sprintf("[OK] timeline saved: %s (events=%d phases=%d certs=%d failures=%d)\n",
              out, length(tl$events), length(tl$phases),
              length(tl$certs), length(tl$failures)))
  invisible(TRUE)
}

rebuild_active_book <- function() {
  bs_path <- file.path(PROJ_ROOT, "qepm/mailbox/governor/book_state.json")
  if (!file.exists(bs_path)) {
    cat("[INFO] book_state not found — skip\n")
    return(invisible(FALSE))
  }
  bs <- tryCatch(fromJSON(bs_path, simplifyVector = FALSE),
                 error = function(e) NULL)
  if (is.null(bs) || length(bs$admitted_ids %||% list()) == 0) {
    cat("[INFO] no admitted_ids — skip\n")
    return(invisible(FALSE))
  }
  count <- 0
  matched_via_lineage <- 0
  n_admitted <- length(bs$admitted_ids %||% list())
  # 계보 폴백용 resolver — 측정 정본(measurement_basis_audit v1.12) 재사용, 사본 금지
  if (!exists(".lineage_related", inherits = TRUE)) {
    for (cand in c("02_Infrastructure/portfolio/measurement_basis_audit.R",
                   file.path(Sys.getenv("CLAUDE_PROJECT_DIR", ""),
                             "02_Infrastructure/portfolio/measurement_basis_audit.R"))) {
      if (nzchar(cand) && file.exists(cand)) { try(source(cand), silent = TRUE); break }
    }
  }
  for (str_id in bs$admitted_ids) {
    str_id <- as.character(str_id)
    # find lineage WT_id
    candidate_dirs <- list.dirs(WT_ROOT, full.names = FALSE, recursive = FALSE)
    for (wt in candidate_dirs) {
      ga <- file.path(WT_ROOT, wt, "governor_admission.json")
      if (!file.exists(ga)) next
      ga_data <- tryCatch(fromJSON(ga, simplifyVector = FALSE),
                           error = function(e) NULL)
      if (is.null(ga_data)) next
      #──────────────────────────────────────────────────────────────────────
      # (2026-07-26 WTL-1/WTL-5 수리, probe② 감사 확정 · 도훈 승인)
      #   join 키가 1세대 스키마(str_id)뿐이었다. 2세대 governor_admission 은
      #   "strategy_id" 를 쓰고, 현행 admitted id 'STR_1715_on_M4gAE_R05_noLayer4_PG2'
      #   는 어느 governor_admission.json 에도 없다(07-19 D3 수동 swap-in 은 ga 미발행 —
      #   event_D3_swapin.json 만 존재). 결과: 매치 0 → "[OK] rebuilt 0" → 부팅
      #   "0 active book WTs" 가 **정상처럼** 출력됐고, active book 관측이 07-02 이후
      #   침묵 사망이었다(timelines/ 최신이 07-18 WT-D20260714_006).
      #   수리: ① 키 확장(str_id %||% strategy_id) ② 계보 토큰경계 폴백(CBA-01 동일 처방)
      #   ③ WTL-5: save 성공만 계상.
      #──────────────────────────────────────────────────────────────────────
      ga_sid <- as.character(ga_data$str_id %||% ga_data$strategy_id %||% "")
      hit <- identical(ga_sid, str_id) ||
             str_id %in% names(ga_data$allocation_decided %||% list())
      if (!hit && nzchar(ga_sid) && exists(".lineage_related", inherits = TRUE)) {
        legacy_root <- sub("(_WT|_Iter|_M|_S|_v).*$", "", str_id)
        hit <- isTRUE(.lineage_related(str_id, ga_sid, legacy_root))
        if (hit) matched_via_lineage <- matched_via_lineage + 1
      }
      if (hit) {
        # WTL-5: save_wt_timeline 이 FALSE(빌드 실패)여도 구판은 count 를 올려
        #   "rebuilt N" 이 성공 수가 아니라 **매치 수**였다. 성공만 계상.
        if (isTRUE(save_wt_timeline(wt))) count <- count + 1
        else cat(sprintf("[WARN] timeline 저장 실패: %s (count 미계상)\n", wt))
      }
    }
  }
  cat(sprintf("[OK] rebuilt %d active book timelines%s\n", count,
              if (matched_via_lineage > 0)
                sprintf(" (계보 폴백 매치 %d)", matched_via_lineage) else ""))
  # ★핵심 가드: admitted 가 있는데 매치 0 = 관측 사망이지 "정상 0" 이 아니다.
  if (n_admitted > 0 && count == 0) {
    cat(sprintf(paste0("[WARN] admitted %d건인데 lineage 매치 0 — active book 관측 사망. ",
                       "governor_admission 스키마(str_id/strategy_id) 또는 ga 미발행 확인 ",
                       "(수동 swap-in WT 는 event_*.json 만 남길 수 있음)\n"), n_admitted))
  }
  invisible(count)
}

# CLI
if (!interactive()) {
  args <- commandArgs(trailingOnly = TRUE)
  if (length(args) == 0) {
    cat("Usage: Rscript wt_timeline.R --wt-id WT-XXX | --rebuild-active-book\n")
    quit(status = 1)
  }
  if ("--rebuild-active-book" %in% args) {
    rebuild_active_book()
  } else {
    idx <- which(args == "--wt-id")
    if (length(idx) == 1 && idx + 1 <= length(args)) {
      save_wt_timeline(args[idx + 1])
    } else {
      cat("[ERROR] missing --wt-id <ID>\n")
      quit(status = 1)
    }
  }
}
