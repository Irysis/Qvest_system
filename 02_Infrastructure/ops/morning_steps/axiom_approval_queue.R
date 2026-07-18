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
