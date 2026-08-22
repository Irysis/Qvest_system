#==============================================================================
# auto_spawn_queue.R — 개선 라운드 스폰 큐 (Layer 2, L1 자동 스폰 — 도훈 승인 2026-08-16)
#
# 역할: 미승격 전략 라벨을 "스폰 후보"로 자격 판정해 06_Registry/auto_spawn_queue.json 에
#   적재한다. 기계는 평가·적재·판정까지 — **라운드 개시는 세션**(/improve-drain 스킬 소비,
#   부트 주입으로 노출). LLM 무인 개시는 L1 범위 밖 (설계안 Layer 3 — cleaner 전례 승계).
#   SOT: 04_Research/01_reports/auto_spawn_orchestration_design_20260816.md.
#
# kind 4종:
#   overlay_drain          — overlay 큐 status=queued (미실측 신규 라벨) → 기계 실측 대기
#   register_module_induce — ★D2 재정의(도훈 2026-08-16): FR_RCMA = "register_module 유도
#                            라벨". 라벨 보유 ∧ module_catalog 부재 → 등재 유도 (세션 소비).
#                            이 kind 가 FR_RCMA 의 소비자다 (구 "소비자 0" 해소).
#   fr_disposition_suggest — FR_RCMA ∧ catalog 등재(fr_eligible) ∧ 처분 미기록 → 라벨이
#                            이행됐으므로 st_record_disposition("fr_routed") 제안 (세션 1클릭)
#   standalone_review      — STANDALONE_TRACK 미처분 중 PORT_t 실측 보유 상위 → HARD 심사 대기
#
# 하드 가드 (설계안 §4):
#   - 자본 경계: 이 파일은 book_state/05_Production 에 도달하는 코드가 없다 (쓰기 = 큐/로그만)
#   - kill switch: 06_Registry/auto_spawn_config.json {enabled:false} → 적재 전면 정지
#   - capacity: kind 별 pending 상한 (기본 5)
#   - 중복: entry id = <kind>:<candidate_id>, 재빌드 시 in_progress/done 상태 보존(리셋 금지)
#   - 내구 기록: build/claim 사건은 06_Registry/auto_spawn_log.jsonl append
#   - claim: mutex-dir(dir.create 원자성) 선점 + stale 6h 재점유 (cleaner_claim.R 전례)
#   - dohoon_decision: 이 큐의 원천(라벨·overlay 큐)에는 해당 플래그가 없다 — FQ 큐는
#     원천이 아니며(세션 임의 착수 금지 플래그는 FQ 소비 시 별도 준수), 여기 명시로 문서화.
#
# Usage:
#   Rscript 02_Infrastructure/ops/auto_spawn_queue.R                # build
#   Rscript 02_Infrastructure/ops/auto_spawn_queue.R --status-line  # 부트 표면 (읽기만)
#   Rscript 02_Infrastructure/ops/auto_spawn_queue.R --claim=<id> --owner=<who>
#==============================================================================
suppressPackageStartupMessages({ library(jsonlite); library(data.table) })

`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0 && !all(is.na(a))) a else b

.asq_root <- function() {
  cands <- c(Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""),
             "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
  cands <- cands[nzchar(cands)]
  hit <- cands[file.exists(file.path(cands, "02_Infrastructure/hooks/qvest_hook_router.py"))]
  if (!length(hit)) stop("[auto_spawn] project root 미발견")
  hit[1]
}

ASQ_QUEUE_REL  <- "06_Registry/auto_spawn_queue.json"
ASQ_CONFIG_REL <- "06_Registry/auto_spawn_config.json"
ASQ_LOG_REL    <- "06_Registry/auto_spawn_log.jsonl"
ASQ_IP_REL     <- "06_Registry/improvement_potential.json"
ASQ_STALE_H    <- 6

.asq_json <- function(p) if (file.exists(p)) tryCatch(fromJSON(p, simplifyVector = FALSE), error = function(e) NULL) else NULL

.asq_atomic_write <- function(obj, path) {
  tmp <- paste0(path, ".tmp", Sys.getpid())
  write_json(obj, tmp, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = 6)
  if (file.exists(path)) suppressWarnings(file.remove(path))
  if (!isTRUE(suppressWarnings(file.rename(tmp, path)))) {
    ok <- suppressWarnings(file.copy(tmp, path, overwrite = TRUE)); suppressWarnings(file.remove(tmp))
    if (!isTRUE(ok)) stop("[auto_spawn] 원자 기록 실패: ", path)
  }
  invisible(TRUE)
}

# 내구 로그 — 무인 런 stdout 은 아무도 안 읽는다 (paper_research_dispatch.R:703 계보)
.asq_log <- function(root, event, detail = list()) {
  rec <- c(list(ts = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), event = event), detail)
  cat(toJSON(rec, auto_unbox = TRUE), "\n",
      file = file.path(root, ASQ_LOG_REL), append = TRUE, sep = "")
}

.asq_config <- function(root) {
  cp <- file.path(root, ASQ_CONFIG_REL)
  d <- .asq_json(cp)
  if (is.null(d)) {
    d <- list(schema_version = "auto_spawn_config_v1",
              `_doc` = "kill switch + capacity. enabled=false 면 적재 전면 정지 (설계안 §4 가드 7).",
              enabled = TRUE, capacity_pending_per_kind = 5L)
    .asq_atomic_write(d, cp)
  }
  d
}

#------------------------------------------------------------------------------
# 빌더 — 상태 보존 재생성 (pending 재계산, in_progress/done 은 id 로 이월)
#------------------------------------------------------------------------------
build_auto_spawn_queue <- function(root = .asq_root(), write = TRUE) {
  cfg <- .asq_config(root)
  if (!isTRUE(cfg$enabled)) {
    cat("[auto_spawn] kill switch OFF (enabled=false) — 적재 정지\n")
    .asq_log(root, "build_skipped_disabled")
    return(invisible(NULL))
  }
  cap <- as.integer(cfg$capacity_pending_per_kind %||% 5L)

  # 원천 로드 — 부재 = 미측정 stop (빈 결과 = 합격 아님)
  ov <- .asq_json(file.path(root, "06_Registry/overlay_candidate_queue.json"))
  if (is.null(ov)) stop("[auto_spawn] overlay 큐 부재/파싱 실패 (미측정, PASS 아님)")
  ipreg <- .asq_json(file.path(root, ASQ_IP_REL))
  ip_of <- function(id) (ipreg$entries %||% list())[[id]]

  # standalone 스캔 — 라벨 전수·처분·catalog 정합은 정본 스캐너 재사용 (root 인자화 픽스처 가능).
  #   ★코드는 코드 루트(.asq_root)에서 소싱 — root 인자는 데이터 루트다 (픽스처 루트에
  #   코드가 없어도 동작해야 함).
  if (!exists("standalone_track_scan", mode = "function")) {
    stq <- file.path(.asq_root(), "02_Infrastructure/portfolio/standalone_track_queue.R")
    if (!file.exists(stq)) stop("[auto_spawn] standalone_track_queue.R 부재")
    source(stq)
  }
  s <- standalone_track_scan(root)
  cat_mods <- (.asq_json(file.path(root, "06_Registry/module_catalog.json")) %||% list())$modules %||% list()

  ents <- list()
  add <- function(kind, cid, payload) {
    eid <- paste0(kind, ":", cid)
    ents[[eid]] <<- c(list(id = eid, kind = kind, candidate_id = cid,
                           status = "pending",
                           created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")),
                      payload)
  }

  # ① overlay_drain — 미실측 신규 라벨 (status != measured)
  for (cd in (ov$candidates %||% list())) {
    if (identical(cd$status %||% "", "measured")) next
    ipb <- ip_of(cd$id %||% "")
    ## ★2026-08-22: 무신호 대조 verdict 를 payload 에 실어 **스폰된 세션이 즉시 보게** 한다
    ##   (measurement-graduation §3). 우선순위 로직은 바꾸지 않는다 — 정보만 전달한다.
    ##   INDISTINGUISHABLE = 그 성과가 신호가 아니라 대형주 노출일 수 있음 → 사이클 배분 판단에 쓸 것.
    ns <- cd$no_signal %||% list()
    nsv <- ns$verdict %||% "NOT_AUDITED"
    add("overlay_drain", cd$id %||% "?",
        list(strategy_name = cd$strategy_name %||% "",
             action = "Rscript 02_Infrastructure/regime/overlay_candidate_drain.R <candidate_id> (기계 실측 — dv_v1 판정 동반)",
             improvement_potential = ipb,
             no_signal_verdict = nsv,
             no_signal_note = if (identical(nsv, "INDISTINGUISHABLE_FROM_NO_SIGNAL"))
               "★무신호 대조와 구별 불가 — 대형주 노출일 수 있음. 사이클 투입 전 EV 재평가 권고(§3)"
             else if (identical(nsv, "NOT_AUDITED"))
               "무신호 대조 미확인(통과 아님) — run_nosignal_queue_audit_r46.R 로 감사 후 판단 가능"
             else "무신호 대조 통과 — 신호 기여 실증됨"))
  }

  # ② FR_RCMA 재정의 소비 (D2, 도훈 2026-08-16)
  fr_rows <- s$tracked[grepl("FR_RCMA", route, fixed = TRUE)]
  if (nrow(fr_rows)) for (i in seq_len(nrow(fr_rows))) {
    r <- fr_rows[i]
    cm <- cat_mods[[r$strategy_id]]
    if (is.null(cm)) {
      add("register_module_induce", r$strategy_id,
          list(route = r$route, proxy_grade = r$proxy_grade,
               action = "register_module() 계약 floor 충족 여부 확인 후 등재 — FR_RCMA 라벨의 소비 (D2 재정의)",
               src_path = r$src_path))
    } else if (isTRUE(cm$fr_eligible) && identical(r$disposition, "none")) {
      add("fr_disposition_suggest", r$strategy_id,
          list(action = sprintf("st_record_disposition('%s','fr_routed') — 라벨 이행 기록 (catalog fr_eligible 실재)", r$strategy_id)))
    }
  }

  # ③ standalone_review — 미처분 중 PORT_t 실측 보유 상위
  U <- copy(s$unconsumed)[is.finite(port_t_nw3)]
  if (nrow(U)) {
    setorder(U, -port_t_nw3)
    for (i in seq_len(min(nrow(U), cap))) {
      r <- U[i]
      add("standalone_review", r$strategy_id,
          list(port_t_nw3 = r$port_t_nw3, oos_retention = r$oos_retention, calmar = r$calmar,
               action = "graduation HARD 3종 심사 → st_record_disposition 기록",
               improvement_potential = ip_of(r$strategy_id)))
    }
  }

  # 상태 이월 + capacity — 기존 in_progress/done 보존, pending 은 kind 별 상한
  prev <- .asq_json(file.path(root, ASQ_QUEUE_REL))
  prev_ents <- prev$entries %||% list()
  for (eid in names(prev_ents)) {
    st <- prev_ents[[eid]]$status %||% "pending"
    if (st %in% c("in_progress", "done") ) ents[[eid]] <- prev_ents[[eid]]
  }
  ## ★2026-08-22: 이월 엔트리도 무신호 대조 verdict 로 **재보강**한다.
  ##   실측 갭: 신규 엔트리에만 붙이면 이미 done/in_progress 로 이월된 건이 영구히 정보 없이 남는다
  ##   (배선 당일 확인 — overlay_drain 5건 전부 이월분이라 verdict=None 이었다).
  ##   ★부분 배선을 완전 배선으로 착각하지 않기 위한 보정. 우선순위 로직은 여전히 안 바꾼다(정보만).
  {
    ovc <- (ov$candidates %||% list())
    ns_by_id <- setNames(lapply(ovc, function(x) x$no_signal %||% list()),
                         vapply(ovc, function(x) x$id %||% "", character(1)))
    for (eid in names(ents)) {
      if (!identical(ents[[eid]]$kind, "overlay_drain")) next
      cid <- ents[[eid]]$candidate_id %||% ""
      nsv <- (ns_by_id[[cid]] %||% list())$verdict %||% "NOT_AUDITED"
      ents[[eid]]$no_signal_verdict <- nsv
      ents[[eid]]$no_signal_note <- if (identical(nsv, "INDISTINGUISHABLE_FROM_NO_SIGNAL"))
          "★무신호 대조와 구별 불가 — 대형주 노출일 수 있음. 사이클 투입 전 EV 재평가 권고(§3)"
        else if (identical(nsv, "NOT_AUDITED"))
          "무신호 대조 미확인(통과 아님) — run_nosignal_queue_audit_r46.R 로 감사 후 판단 가능"
        else "무신호 대조 통과 — 신호 기여 실증됨"
    }
  }
  by_kind <- split(names(ents), vapply(ents, function(e) e$kind, character(1)))
  for (k in names(by_kind)) {
    pend <- Filter(function(eid) identical(ents[[eid]]$status, "pending"), by_kind[[k]])
    if (length(pend) > cap) for (eid in pend[(cap + 1L):length(pend)]) ents[[eid]] <- NULL
  }

  q <- list(schema_version = "auto_spawn_queue_v1",
            generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
            `_doc` = paste("Layer 2 스폰 큐 — 기계는 적재까지, 개시는 세션(/improve-drain).",
                           "governor/book_state 도달 경로 없음. SOT = auto_spawn_orchestration_design_20260816.md"),
            config_ref = ASQ_CONFIG_REL,
            counts = as.list(table(vapply(ents, function(e) paste0(e$kind, ".", e$status), character(1)))),
            entries = ents)
  if (isTRUE(write)) {
    .asq_atomic_write(q, file.path(root, ASQ_QUEUE_REL))
    .asq_log(root, "build", list(n = length(ents)))
    cat(sprintf("[auto_spawn] wrote %s — %d entries (%s)\n", ASQ_QUEUE_REL, length(ents),
                paste(sprintf("%s=%s", names(q$counts), unlist(q$counts)), collapse = " ")))
  }
  invisible(q)
}

#------------------------------------------------------------------------------
# claim — mutex-dir 원자 선점 (cleaner_claim.R 전례) + stale 재점유
#------------------------------------------------------------------------------
auto_spawn_claim <- function(entry_id, owner, root = .asq_root(), stale_hours = ASQ_STALE_H) {
  if (!nzchar(owner %||% "")) stop("[auto_spawn] owner 필수")
  qp <- file.path(root, ASQ_QUEUE_REL)
  mux <- file.path(root, ".cache", "auto_spawn_claim.lock")
  dir.create(dirname(mux), recursive = TRUE, showWarnings = FALSE)
  got <- dir.create(mux, showWarnings = FALSE)
  if (!got) {
    age_h <- suppressWarnings(as.numeric(difftime(Sys.time(), file.info(mux)$mtime, units = "hours")))
    if (is.finite(age_h) && age_h > stale_hours) { unlink(mux, recursive = TRUE); got <- dir.create(mux, showWarnings = FALSE) }
  }
  if (!got) stop("[auto_spawn] claim mutex 선점 실패 — 동시 claim 진행 중")
  on.exit(unlink(mux, recursive = TRUE), add = TRUE)

  q <- .asq_json(qp); if (is.null(q)) stop("[auto_spawn] 큐 부재: ", qp)
  e <- q$entries[[entry_id]]
  if (is.null(e)) stop("[auto_spawn] entry 미발견: ", entry_id)
  st <- e$status %||% "pending"
  if (identical(st, "in_progress")) {
    age_h <- suppressWarnings(as.numeric(difftime(Sys.time(),
              as.POSIXct(e$claimed_at %||% "1970-01-01", format = "%Y-%m-%dT%H:%M:%S"), units = "hours")))
    if (!is.finite(age_h) || age_h <= stale_hours)
      stop(sprintf("[auto_spawn] 이미 claim 됨 (owner=%s, %.1fh) — stale %dh 전 재점유 불가",
                   e$owner %||% "?", age_h %||% NA, as.integer(stale_hours)))
  } else if (identical(st, "done")) stop("[auto_spawn] 이미 done: ", entry_id)
  q$entries[[entry_id]]$status <- "in_progress"
  q$entries[[entry_id]]$owner <- owner
  q$entries[[entry_id]]$claimed_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  .asq_atomic_write(q, qp)
  chk <- .asq_json(qp)   # 기록 후 재읽기 확인
  if (!identical(chk$entries[[entry_id]]$owner, owner))
    stop("[auto_spawn] claim 기록 후 재읽기 불일치 — 유실")
  .asq_log(root, "claim", list(entry = entry_id, owner = owner))
  cat(sprintf("[auto_spawn] claimed: %s ← %s\n", entry_id, owner))
  invisible(chk$entries[[entry_id]])
}

auto_spawn_done <- function(entry_id, note = "", root = .asq_root()) {
  qp <- file.path(root, ASQ_QUEUE_REL)
  q <- .asq_json(qp); if (is.null(q)) stop("[auto_spawn] 큐 부재")
  if (is.null(q$entries[[entry_id]])) stop("[auto_spawn] entry 미발견: ", entry_id)
  q$entries[[entry_id]]$status <- "done"
  q$entries[[entry_id]]$done_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  if (nzchar(note)) q$entries[[entry_id]]$done_note <- note
  .asq_atomic_write(q, qp)
  .asq_log(root, "done", list(entry = entry_id, note = note))
  invisible(TRUE)
}

auto_spawn_status_line <- function(root = .asq_root()) {
  cfg <- tryCatch(.asq_config(root), error = function(e) NULL)
  if (!is.null(cfg) && !isTRUE(cfg$enabled)) return("AutoSpawn: OFF (kill switch)")
  q <- .asq_json(file.path(root, ASQ_QUEUE_REL))
  if (is.null(q)) return("AutoSpawn: 큐 미생성 — build 필요 (auto_spawn_queue.R)")
  sts <- vapply(q$entries %||% list(), function(e) e$status %||% "?", character(1))
  kinds <- vapply(q$entries %||% list(), function(e) e$kind %||% "?", character(1))
  np <- sum(sts == "pending")
  if (np == 0L) return(sprintf("AutoSpawn: pending 0 (in_progress %d / done %d)",
                               sum(sts == "in_progress"), sum(sts == "done")))
  kd <- table(kinds[sts == "pending"])
  sprintf("AutoSpawn: pending %d (%s) — /improve-drain 소비 권장", np,
          paste(sprintf("%s %d", names(kd), as.integer(kd)), collapse = " · "))
}

# ── CLI ──────────────────────────────────────────────────────────────────────
.asq_invoked_directly <- function() {
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", a[grepl("^--file=", a)])
  length(f) > 0L && identical(basename(f[1]), "auto_spawn_queue.R")
}
if (.asq_invoked_directly()) {
  args <- commandArgs(trailingOnly = TRUE)
  root <- .asq_root()
  if ("--status-line" %in% args) {
    cat(auto_spawn_status_line(root), "\n", sep = ""); quit(save = "no", status = 0L)
  }
  cl <- grep("^--claim=", args, value = TRUE)
  if (length(cl)) {
    ow <- sub("^--owner=", "", grep("^--owner=", args, value = TRUE)[1] %||% "")
    auto_spawn_claim(sub("^--claim=", "", cl[1]), ow, root)
    quit(save = "no", status = 0L)
  }
  dn <- grep("^--done=", args, value = TRUE)
  if (length(dn)) {
    nt <- sub("^--note=", "", grep("^--note=", args, value = TRUE)[1] %||% "")
    auto_spawn_done(sub("^--done=", "", dn[1]), nt, root)
    quit(save = "no", status = 0L)
  }
  build_auto_spawn_queue(root, write = !("--no-write" %in% args))
}
