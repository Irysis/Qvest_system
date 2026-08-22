#==============================================================================
# distribution_target_queue.R — screen_route=DISTRIBUTION_TARGET **소비 배관**
#
# 2026-08-22 신설. 함께 도입된 것: 계약 02_Infrastructure/contracts/distribution_target_screen.R
#   + 발급 지점 02_Infrastructure/hurdle_gate.R (screen_route).
#
# ★왜 계약과 **같은 세션에** 만드는가:
#   이 저장소의 반복 결함은 "만들었는데 부르는 쪽이 없다"이다. 실측 전례 —
#     · screen_route STANDALONE_TRACK: 소비자 0 으로 후보 1건이 3주+ 방치
#       (Chen-Welch, 2026-08-02 적발)
#     · knowledge_index_freshness: 돌연변이 17/17 검출력인데 **호출자 0**
#       (2026-08-20) → 원래 결함이 운영에 그대로
#     · FQ-181 liq_ruler: 라벨을 발행만 하고 읽는 소비자 0
#   라벨을 만들면서 소비자를 안 만들면 라벨이 아니라 **주석**이다.
#
# 역할:
#   ① 계약 산출물(stage_artifacts/**/distribution_screen_*.json) 전수 수집
#   ② alpha_search 매니페스트/hurdle_result 의 screen_route 라벨 보유분 수집
#   ③ ★자본 우회 감사 — 항목마다 capital_eligible/자본 필드 검사. 자본 주장을 달고
#      들어온 항목은 **큐에 넣지 않고 격리**한다(measurement-graduation §3).
#   ④ 요건 3종 미충족 사유 집계 — "증거 미제출"과 "요건 미달"을 구분해 남긴다
#   → 06_Registry/distribution_target_queue.json
#
# ★★"빈 결과 = 합격" 금지 (저장소 반복 결함): 스캔 소스 디렉터리 자체가 없으면
#   PASS 가 아니라 **UNREPORTED(status)** 다. 잘못된 cwd 에서 돌아 나온 0 이
#   "미처리 없음"으로 읽히는 경로를 차단한다.
#
# 검사기: 08_Tests/contracts/test_distribution_target_screen.R (소비 배관 절 포함)
# Usage: Rscript 02_Infrastructure/portfolio/distribution_target_queue.R [--json] [--no-write]
#==============================================================================
suppressPackageStartupMessages({ library(jsonlite) })

# r-portability ④: CLAUDE_PROJECT_DIR 우선 + **정체성 검사**(marker 실재)로 루트 확정.
#   존재 검사로 정체성 검사를 대체하지 않는다.
.dq_root <- function() {
  cands <- c(Sys.getenv("CLAUDE_PROJECT_DIR", unset = ""),
             Sys.getenv("QM_ROOT", unset = ""), getwd())
  cands <- cands[nzchar(cands)]
  hit <- cands[file.exists(file.path(cands, "02_Infrastructure/contracts/distribution_target_screen.R"))]
  if (!length(hit)) stop("project root 미발견 — CLAUDE_PROJECT_DIR 설정 필요")
  gsub("\\\\", "/", hit[1])
}

DQ_QUEUE_REL <- "06_Registry/distribution_target_queue.json"
DQ_ROUTE     <- "DISTRIBUTION_TARGET"

.dq_chr <- function(x) if (is.null(x) || length(x) == 0L) NA_character_ else as.character(x[1])
.dq_num <- function(x) if (is.null(x) || length(x) == 0L) NA_real_ else suppressWarnings(as.numeric(x[1]))
.dq_dig <- function(d, ...) { cur <- d; for (k in c(...)) { if (!is.list(cur)) return(NULL); cur <- cur[[k]] }; cur }
.dq_json <- function(p) if (file.exists(p)) tryCatch(fromJSON(p, simplifyVector = FALSE), error = function(e) NULL) else NULL
.dq_rel <- function(p, root) {
  p2 <- gsub("\\\\", "/", p); r2 <- sub("/+$", "", gsub("\\\\", "/", root))
  if (nzchar(r2) && startsWith(p2, paste0(r2, "/"))) substring(p2, nchar(r2) + 2L) else p2
}

#------------------------------------------------------------------------------
# 자본 우회 감사 — 계약의 판정기를 **호출**한다(정규식 사본 금지).
#   교훈: 소비처가 자기 정규식 사본을 들면 정본보다 느슨해진다
#   (memory feedback-pattern-audit-of-freeform-fails..., 2026-08-15).
#------------------------------------------------------------------------------
.dq_capital_audit <- function(obj, root, where) {
  if (!exists("dt_assert_no_capital_fields", mode = "function")) {
    f <- file.path(root, "02_Infrastructure/contracts/distribution_target_screen.R")
    if (file.exists(f)) suppressMessages(source(f))
  }
  if (!exists("dt_assert_no_capital_fields", mode = "function")) {
    return(list(checked = FALSE, clean = NA,
                reason = "계약 판정기 미로드 — 감사 불가(사본으로 대체하지 않는다)"))
  }
  r <- tryCatch({ dt_assert_no_capital_fields(obj, where); list(checked = TRUE, clean = TRUE, reason = NA_character_) },
                error = function(e) list(checked = TRUE, clean = FALSE, reason = conditionMessage(e)))
  r
}

#------------------------------------------------------------------------------
# 스캔 — 인자화(root)로 픽스처 호출 가능. 위반 주입 검사기가 이 함수를 때린다.
#------------------------------------------------------------------------------
#' @param root 프로젝트 루트
#' @return list(rows, quarantined, n_*, inputs, status)
distribution_target_scan <- function(root = .dq_root()) {
  sa_dir <- file.path(root, "stage_artifacts")
  inputs <- list(
    stage_artifacts_dir = list(path = .dq_rel(sa_dir, root), exists = dir.exists(sa_dir)),
    contract = list(path = "02_Infrastructure/contracts/distribution_target_screen.R",
                    exists = file.exists(file.path(root, "02_Infrastructure/contracts/distribution_target_screen.R"))),
    issuer   = list(path = "02_Infrastructure/hurdle_gate.R",
                    exists = file.exists(file.path(root, "02_Infrastructure/hurdle_gate.R")))
  )
  # ★소스 부재 = UNREPORTED. 0 을 "미처리 없음"으로 내려앉히지 않는다.
  if (!dir.exists(sa_dir)) {
    return(list(status = "UNREPORTED",
                status_reason = sprintf("스캔 소스 디렉터리 부재: %s — 0건은 '누락 없음'이 아니라 '측정 안 됨'",
                                        .dq_rel(sa_dir, root)),
                rows = list(), quarantined = list(), inputs = inputs,
                n_emitted = 0L, n_labeled = 0L, n_eligible = 0L, n_quarantined = 0L))
  }

  rows <- list(); quar <- list()

  # ── ① 계약 산출물 ─────────────────────────────────────────────────────────
  emits <- list.files(sa_dir, pattern = "^distribution_screen_.*\\.json$",
                      recursive = TRUE, full.names = TRUE)
  for (f in emits) {
    o <- .dq_json(f); if (is.null(o)) next
    aud <- .dq_capital_audit(o, root, paste0("queue_scan:", basename(f)))
    gate <- o$route_gate
    rec <- list(
      source = "contract_emit", src_path = .dq_rel(f, root),
      spec_id = .dq_chr(o$spec_id), run_id = .dq_chr(o$run_id),
      contract_version = .dq_chr(o$contract_version),
      prereg_ref = .dq_chr(o$prereg_ref),
      capital_eligible_declared = isTRUE(o$capital_eligible),
      capital_audit_clean = isTRUE(aud$clean),
      route_eligible = isTRUE(gate$eligible),
      route = .dq_chr(gate$route),
      r1 = isTRUE(.dq_dig(gate, "requirements", "r1_mean_space_powered_null", "pass")),
      r2 = isTRUE(.dq_dig(gate, "requirements", "r2_orthogonal_survival", "pass")),
      r3 = isTRUE(.dq_dig(gate, "requirements", "r3_two_window_sign_agree", "pass")),
      survival_verdict = .dq_chr(.dq_dig(o, "survival", "verdict")),
      survived_axes = unlist(.dq_dig(o, "survival", "survived_axes_any_window")),
      window_independence = .dq_chr(.dq_dig(o, "window_independence", "verdict")),
      unmet_reasons = unlist(gate$reasons),
      emitted_at = .dq_chr(o$emitted_at)
    )
    # ★자본 주장을 달고 들어오면 큐가 아니라 격리로 간다 — 소비를 막는 게 목적
    if (!isTRUE(aud$clean) || isTRUE(o$capital_eligible)) {
      rec$quarantine_reason <- if (isTRUE(o$capital_eligible))
        "capital_eligible=TRUE — 분포 계약 산출물은 항상 FALSE 여야 한다(변조 의심)"
      else paste0("자본 필드 검출: ", .dq_chr(aud$reason))
      quar[[length(quar) + 1L]] <- rec
    } else rows[[length(rows) + 1L]] <- rec
  }

  # ── ② 라벨 보유분 (hurdle_gate 발급면) ────────────────────────────────────
  n_labeled <- 0L
  mfs <- c(Sys.glob(file.path(root, "stage_artifacts/alpha_search/*/strategy_manifest.json")),
           Sys.glob(file.path(root, "stage_artifacts/alpha_search/*/hurdle_result.json")))
  seen <- character(0)
  for (f in mfs) {
    m <- .dq_json(f); if (is.null(m)) next
    scr <- .dq_dig(m, "verdict", "screening")
    if (is.null(scr)) scr <- m$screening
    if (is.null(scr)) next
    rt <- .dq_chr(scr$screen_route)
    if (is.na(rt) || !grepl(DQ_ROUTE, rt, fixed = TRUE)) next
    d <- basename(dirname(f)); if (d %in% seen) next
    seen <- c(seen, d); n_labeled <- n_labeled + 1L
    dtg <- scr$distribution_target
    rows[[length(rows) + 1L]] <- list(
      source = "screen_route_label", src_path = .dq_rel(f, root),
      run_dir = d,
      strategy_id = .dq_chr(m$strategy_id) , strategy_name = .dq_chr(m$strategy_name) ,
      route = rt,
      route_eligible = isTRUE(dtg$eligible),
      capital_eligible_declared = isTRUE(dtg$capital_eligible),
      gate_version = .dq_chr(dtg$gate_version),
      unmet_reasons = unlist(dtg$reasons),
      labeled_at = .dq_chr(m$created_at) )
  }

  n_elig <- sum(vapply(rows, function(r) isTRUE(r$route_eligible), logical(1)))
  list(status = "OK", status_reason = NA_character_,
       rows = rows, quarantined = quar, inputs = inputs,
       n_emitted = length(emits), n_labeled = n_labeled,
       n_eligible = as.integer(n_elig), n_quarantined = length(quar))
}

#------------------------------------------------------------------------------
# 원장 기록
#------------------------------------------------------------------------------
distribution_target_write <- function(scan, root = .dq_root(), write = TRUE) {
  q <- list(
    schema_version = "distribution_target_queue_v1",
    generated_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
    status = scan$status, status_reason = scan$status_reason,
    route = DQ_ROUTE,
    producer_ref = paste0("02_Infrastructure/hurdle_gate.R verdict$screening$screen_route ",
                          "(+ verdict$screening$distribution_target) — 판정 권위는 ",
                          "02_Infrastructure/contracts/distribution_target_screen.R::dt_route_eligible()"),
    consumer_ref = paste0("본 파일(02_Infrastructure/portfolio/distribution_target_queue.R). ",
                          "다음 라운드 설계 입력: 요건 미충족 사유(unmet_reasons)가 곧 next_probe 다."),
    capital_boundary = paste0("★이 큐의 어떤 항목도 자본 자격을 갖지 않는다 ",
                              "(.claude/rules/measurement-graduation.md §3). graduation HARD 3종은 ",
                              "forge-authoritative 포트폴리오 수치로만 판정한다. ",
                              "자본 주장을 달고 들어온 항목은 quarantined 로 격리된다."),
    counts = list(emitted = scan$n_emitted, labeled = scan$n_labeled,
                  eligible = scan$n_eligible, quarantined = scan$n_quarantined,
                  queued = length(scan$rows)),
    inputs = scan$inputs,
    rows = scan$rows,
    quarantined = scan$quarantined
  )
  if (isTRUE(write)) {
    qp <- file.path(root, DQ_QUEUE_REL)
    dir.create(dirname(qp), recursive = TRUE, showWarnings = FALSE)
    write_json(q, qp, auto_unbox = TRUE, pretty = TRUE, digits = NA, null = "null", na = "null")
  }
  q
}

# ── CLI ───────────────────────────────────────────────────────────────────────
if (!interactive() && sys.nframe() == 0L) {
  .a <- commandArgs(trailingOnly = TRUE)
  .root <- .dq_root()
  .s <- distribution_target_scan(.root)
  .q <- distribution_target_write(.s, .root, write = !("--no-write" %in% .a))
  if ("--json" %in% .a) {
    cat(toJSON(.q$counts, auto_unbox = TRUE), "\n")
  } else {
    cat(sprintf("[distribution_target_queue] status=%s emitted=%d labeled=%d eligible=%d quarantined=%d queued=%d\n",
                .s$status, .s$n_emitted, .s$n_labeled, .s$n_eligible, .s$n_quarantined, length(.s$rows)))
    if (identical(.s$status, "UNREPORTED")) cat("  ", .s$status_reason, "\n")
    for (r in .s$quarantined) cat(sprintf("  QUARANTINE %s — %s\n", r$src_path, r$quarantine_reason))
  }
  if (identical(.s$status, "UNREPORTED")) quit(status = 1L)
}
