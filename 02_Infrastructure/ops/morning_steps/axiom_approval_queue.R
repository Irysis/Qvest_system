# axiom_approval_queue.R — morning_briefing 스텝: Axiom(DIST) 승인 대기 노출
#
# INV-6 재정의(도훈 confirm 2026-07-04): "무인 정제 금지" → "무인 *활성화* 금지".
#   lifecycle: pending_5axis → [자동초안 + 적대검증] → proposed(주입 안 됨)
#              → [도훈 승인] → distilled(주입 가능) → promoted|expired.
#   본 스텝은 status=proposed 인 DIST 초안을 사람이 읽는 요약으로 모닝브리핑에 노출한다.
#   ★ 활성화(distilled 전환)는 도훈 배치 승인 게이트 — 본 스텝은 노출만(읽기 전용).
#
# 외부 .R 파일화 이유(다른 morning_steps와 동일): 인라인 Rscript -e 의 한글/이모지 리터럴이
#   bash→Windows-R 코드페이지 변환에서 깨져 "Execution halted"/SIGSEGV. 파일은 UTF-8 정상 read.
# 전제: morning_briefing.sh 가 cd "$BASE" 후 호출 (CWD = project root). fail-soft.
#
# 텔레그램: 본 스텝은 stdout(모닝브리핑 로그) 노출까지만 수행한다. 별도 tg 발송은
#   기존 브리핑 tg 규약(tg_agent_brief 단일 진입점) 정합 검토가 필요하며, morning_briefing.sh는
#   현재 데이터 갱신 + 개별 send 스크립트 분리 구조이므로 별도 발송은 후속(deferred)으로 둔다.

suppressWarnings(suppressMessages(tryCatch({

  source("02_Infrastructure/ops/morning_steps/_root.R")
  source("02_Infrastructure/axiom/distilled.R")

  `%||%` <- function(a, b) if (is.null(a) || length(a) == 0 || (length(a) == 1 && is.na(a))) b else a

  # ── proposed 목록 수집 ─────────────────────────────────────────────────────
  # 1차: distilled.R::list_proposed() (자동초안 그룹이 추가하는 정규 진입점).
  # 폴백: 아직 list_proposed()가 미배선이면 인덱스에서 status=="proposed" 직접 필터
  #       (본 스텝이 사이블링 그룹 배선 전에도 무해하게 동작하도록).
  proposed <- tryCatch({
    if (exists("list_proposed", mode = "function")) {
      lp <- list_proposed()
      # list_proposed()가 data.frame이면 리스트-of-list로 정규화, 이미 리스트면 그대로.
      if (is.data.frame(lp)) {
        if (nrow(lp) == 0) list() else split(lp, seq_len(nrow(lp)))
      } else {
        lp %||% list()
      }
    } else {
      idx <- load_distilled_index()
      Filter(function(e) identical(e$status %||% "", "proposed"), idx$entries %||% list())
    }
  }, error = function(e) {
    cat(sprintf("[axiom-approval] list 수집 실패(fail-soft): %s\n", conditionMessage(e)))
    list()
  })

  n <- length(proposed)

  # 필드 안전 추출 헬퍼 (data.frame row / named list 양쪽 지원, 후보 key 순차 탐색).
  # list_proposed() 스키마(statement/n_support)와 index-entry 스키마(statement_refined/n_supporting)를
  # 모두 커버 — 사이블링 그룹 배선(list_proposed) 전/후 무관하게 동일 출력.
  fget <- function(e, keys, default = NA) {
    for (key in keys) {
      v <- tryCatch(e[[key]], error = function(err) NULL)
      if (is.null(v) || length(v) == 0) next
      v <- v[[1]]
      if (is.null(v) || (length(v) == 1 && is.na(v))) next
      return(v)
    }
    default
  }

  if (n == 0) {
    cat("[Axiom 승인 대기] 승인 대기 없음\n")
  } else {
    cat(sprintf("[Axiom 승인 대기 %d건] — 자동초안+적대검증 완료, 도훈 활성화 승인 대기(주입 안 됨)\n", n))
    for (e in proposed) {
      did   <- fget(e, "dist_id", "?")
      stmt  <- fget(e, c("statement", "statement_refined", "statement_draft"), "(statement 없음)")
      stmt  <- gsub("[\r\n]+", " ", as.character(stmt))
      if (nchar(stmt) > 120) stmt <- paste0(substr(stmt, 1, 120), "…")
      verd  <- fget(e, "adversarial_verdict", "(적대검증 미기록)")
      nsup  <- fget(e, c("n_support", "n_supporting"), NA)
      if (is.na(nsup)) {
        sl <- tryCatch(e[["supporting_l_codes"]], error = function(err) NULL)
        nsup <- if (is.null(sl)) 0L else length(sl)
      }
      expiry <- fget(e, c("expiry", "expires_at"), "(만료일 미기록)")
      cat(sprintf("  · %s | %s\n", did, stmt))
      cat(sprintf("      적대검증: %s | supporting L-code %s건 | 만료: %s\n",
                  as.character(verd), as.character(nsup), as.character(expiry)))
    }
    cat("\n  승인: Rscript -e 로 approve_proposed(c('DIST-...'[, ...])) 실행 또는 /cleaner 스킬\n")
    cat("  (승인 시 status=proposed → distilled 전환 = 주입/hypothesis_index/strategic_truths 소비 활성화)\n")
  }

  # ── v9.1 공리 활성/보류 통지 (2026-08-23 커밋16 · §7-S4b) ───────────────────
  # 구 v9: "승인 대기 N건 — 도훈 1줄 confirm". v9.1 은 사람 승인을 refine_statement.R 의
  #   R0~R6 품질 게이트로 대체했다(E-1). 그래서 이 스텝이 물어야 할 것도 바뀐다:
  #     ① **무엇이 새로 활성화됐나** — 사람이 사후에 diff 를 볼 대상(승인이 아니라 통지)
  #     ② **무엇이 왜 보류(HELD)됐나** — /cleaner 가 소비해 *입력*을 고치는 큐
  #   ★파일명은 axiom_approval_queue.R 로 유지한다(morning_briefing.sh 호출부 확인 전
  #     개명 금지). 바뀐 것은 내용이지 배선이 아니다.
  tryCatch({
    # 별도 env 로 적재 — 이 스텝의 `%||%`/헬퍼를 promote.R 판본이 덮어쓰지 않게.
    # PROMOTE_SOURCED 는 promote.R CLI 자동실행 가드(원상복구 필수 — 자식 스폰에 샌다).
    .had_ps <- Sys.getenv("PROMOTE_SOURCED", NA_character_)
    Sys.setenv(PROMOTE_SOURCED = "1")
    .pxe <- new.env(parent = globalenv())
    suppressWarnings(suppressMessages(sys.source("02_Infrastructure/axiom/promote.R", envir = .pxe)))
    if (is.na(.had_ps)) Sys.unsetenv("PROMOTE_SOURCED") else Sys.setenv(PROMOTE_SOURCED = .had_ps)

    ax_active <- if (exists("list_active_axioms", envir = .pxe, mode = "function"))
      .pxe$list_active_axioms() else list()
    .unatt <- identical(Sys.getenv("QVEST_AXIOM_UNATTENDED", "1"), "1")
    if (!length(ax_active)) {
      cat(sprintf("\n[공리 활성 0건] — 무인 활성화 %s. 정제 게이트(R0~R6) 통과분 없음\n",
                  if (.unatt) "ON" else "OFF(QVEST_AXIOM_UNATTENDED=0)"))
    } else {
      cat(sprintf("\n[공리 활성 %d건] — 무인 활성화 %s · 주입면 도달분(사후 통지, 승인 아님)\n",
                  length(ax_active), if (.unatt) "ON" else "OFF"))
      for (p in ax_active) {
        cat(sprintf("  · %s (%s/%s | refine=%s)\n", as.character(p$axiom_id), as.character(p$mode),
                    as.character(p$polarity), as.character(p$refine_verdict)))
        cat(sprintf("      %s\n", as.character(p$statement_inject)))
      }
      cat("  되돌리기: deactivate_axiom(c('AX-...'), reason='...') 또는 QVEST_AXIOM_UNATTENDED=0\n")
    }

    # 보류(HELD) — 사유별로 묶어 /cleaner 가 무엇을 고쳐야 하는지 보이게 한다.
    ax_props <- if (exists("list_proposed_axioms", envir = .pxe, mode = "function"))
      .pxe$list_proposed_axioms() else list()
    if (!length(ax_props)) {
      cat("[공리 정제 보류 0건]\n")
    } else {
      .rd <- function(pth) tryCatch(jsonlite::fromJSON(pth, simplifyVector = FALSE), error = function(e) NULL)
      cat(sprintf("[공리 정제 보류 %d건] — R0~R6 미통과. **입력을 고치면 다음 주간 스윕이 자동 재시도**한다\n",
                  length(ax_props)))
      for (p in ax_props) {
        d <- .rd(as.character(p$path))
        fl <- if (!is.null(d)) paste(unlist(d$refine_failing %||% list()), collapse = ",") else ""
        cat(sprintf("  · %s (%s | supporting %s건) 미통과=%s\n",
                    as.character(p$axiom_id), as.character(p$mode), as.character(p$n_support),
                    if (nzchar(fl)) fl else "미기록(정제 미실행)"))
      }
      cat("  고치는 곳 = 멤버 L-code(next_probe·live_trigger·반증 시도)와 클러스터 polarity 라벨. 수동 해제: approve_axiom(c('AX-...'))\n")
    }
  }, error = function(e) {
    cat(sprintf("[공리 활성/보류 통지] 섹션 실패(fail-soft): %s\n", conditionMessage(e)))
  })

  # ── 재부상 섹션 (anti-ossification): live_trigger 충족 실패지식 재도전 시점 노출 ──
  # 계획서 G(2026-07-04). failure_revival_monitor.R를 소비 — distilled/proposed negative의
  #   live_trigger를 revival_signals 레지스트리 경유로 평가한 발화 목록.
  #   모니터를 여기서 1회 실행(fresh)한 뒤 산출(.cache/failure_revival_flags.json)을 렌더.
  #   fail-soft: 모니터/파일 실패는 이 섹션만 조용히 건너뛴다.
  tryCatch({
    old_opt <- getOption("rev_no_autorun", FALSE)
    options(rev_no_autorun = TRUE)   # source 시 이중 자동실행 억제 — 아래서 명시 호출.
    on.exit(options(rev_no_autorun = old_opt), add = TRUE)
    withCallingHandlers(
      suppressMessages(source("02_Infrastructure/ops/failure_revival_monitor.R", local = TRUE)),
      message = function(m) invokeRestart("muffleMessage"))
    flags_path <- file.path(".cache", "failure_revival_flags.json")
    fired <- list(); np_spec <- 0L
    if (exists("revival_monitor_run", mode = "function")) {
      pay <- tryCatch(revival_monitor_run(write_flags = TRUE, verbose = FALSE),
                      error = function(e) NULL)
      if (!is.null(pay)) {
        fired <- pay$fired %||% list()
        np_spec <- suppressWarnings(as.integer(pay$n_pending_spec %||% 0L)) %||% 0L
      }
    } else if (file.exists(flags_path)) {
      pay <- tryCatch(jsonlite::fromJSON(flags_path, simplifyVector = FALSE), error = function(e) NULL)
      if (!is.null(pay)) {
        fired <- pay$fired %||% list()
        np_spec <- suppressWarnings(as.integer(pay$n_pending_spec %||% 0L)) %||% 0L
      }
    }
    nf <- length(fired)
    if (nf == 0) {
      cat("\n[재도전 시점 도달 0건] — 휴면 실패지식 live_trigger 미충족(재부상 없음)\n")
    } else {
      cat(sprintf("\n[재도전 시점 도달 %d건] — 봉투 안 frontier 재도전 권고 (실패는 생성적, 원리4)\n", nf))
      for (fd in fired) {
        did  <- fget(fd, "dist_id", "?")
        sid  <- fget(fd, "signal_id", "?")
        cond <- fget(fd, "condition", "?")
        cur  <- fget(fd, "current_value", "?")
        fr   <- fget(fd, "frontier", "(frontier 미기록)")
        cat(sprintf("  · %s: [트리거 %s '%s' 충족 (현재 %s)] → 봉투 안 재도전 권고\n",
                    as.character(did), as.character(sid), as.character(cond), as.character(cur)))
        cat(sprintf("      frontier(미탐색 인접): %s\n", as.character(fr)))
      }
      cat("  (재부상 ≠ 자동 재실행. 도훈/Q 판단으로 봉투 안 차별점 명시 후 진행 — 제약 완화 레버 금지)\n")
    }
    # 승인대기와 동렬 노출: revival_spec 원소가 pending(참조 signal_id 명부 미확정/미배선 스텁)이면
    # 자동감시가 안 도는 상태 — verbose 전용 경고를 모닝 표면으로 승격.
    if (np_spec > 0L)
      cat(sprintf("\n[부활신호 미배선 스텁 %d건] — revival_spec 원소의 참조 signal_id가 pending 스텁(자동감시 미가동). revival_signals.json 신호원 확정(active 등록) + draft_proposed 재작성 시 활성화\n",
                  np_spec))
  }, error = function(e) {
    cat(sprintf("[재도전 시점] 재부상 섹션 실패(fail-soft): %s\n", conditionMessage(e)))
  })

}, error = function(e) {
  cat(sprintf("[axiom-approval] 스텝 실패(fail-soft): %s\n", conditionMessage(e)))
})))
