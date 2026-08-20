#==============================================================================
# Quant Module — Telegram Notification Module
# telegram_notify.R
#
# SOT: .claude/skills/qvest-telegram/SKILL.md (v6, 2026-05-07)
#   - 양식 / 약어 풀이 / Hook 정책 / caller 예시
#   - 본 파일 .TG_CONFIG list와 SKILL.md §3 매직 상수 1:1 동기화 의무
#   - 규칙 변경 시 SKILL.md 먼저 수정, R 동기화. 역방향 금지.
#
# Public API (caller 진입점):
#   tg_agent_brief(agent, title, sections, ...)    — 단일 진입점 ⭐
#   tg_send_photo(path, caption)                   — 사진 (tg_agent_brief charts= 권장)
#
# Internal helpers (caller 직접 호출 금지 — Hook telegram_direct_call_guard.sh 차단):
#   tg_send / tg_send_rich / tg_format_table / tg_decode_jargon
#   tg_text_smart_break / tg_format_summary
#
# Legacy (retain, 신규 caller 사용 금지):
#   tg_strategy_result_with_chart / tg_pass_analysis
#   tg_full_briefing / tg_regime_briefing
#==============================================================================

suppressPackageStartupMessages(library(httr))
suppressPackageStartupMessages(library(jsonlite))

# ─── UTF-8 locale 가드 (이모지/한글 보존, 2026-06-25) ─────────────────────────
# 근본원인: 스케줄러(Task Scheduler)가 LC_ALL/LANG=C(또는 C.UTF-8→Windows 미지원→C 폴백)로
#   Rscript 를 띄우면, 본문 이모지(byte 리터럴 "\xf0\x9f...")가 jsonlite(httr encode="json")
#   직렬화에서 바이트별 Latin 오해석되어 파괴된다(실측: C locale toJSON("📊")→"p\n").
#   또한 tg_send_rich 의 [가-힣] PCRE gsub 가 C locale 에서 컴파일 실패한다([[project-telegram-locale-pcre-korean]]).
# 수리: 모듈 로드 시 LC_CTYPE 를 UTF-8 locale 로 강제(세션 지속). 이미 UTF-8 이면 no-op.
.tg_ensure_utf8_ctype <- function() {
  if (grepl("utf-?8", Sys.getlocale("LC_CTYPE"), ignore.case = TRUE)) return(invisible(TRUE))
  for (loc in c("English_United States.utf8", "Korean_Korea.utf8",
                "English_United States.1252", "C.UTF-8", "en_US.UTF-8")) {
    r <- suppressWarnings(tryCatch(Sys.setlocale("LC_CTYPE", loc), error = function(e) ""))
    if (nzchar(r)) {
      cat(sprintf("[telegram_notify] LC_CTYPE 강제 → %s (이모지/한글 보존)\n", r))
      return(invisible(TRUE))
    }
  }
  cat("[telegram_notify] WARN UTF-8 locale 설정 실패 — 이모지 깨질 수 있음\n")
  invisible(FALSE)
}
.tg_ensure_utf8_ctype()

# ─── Credentials (.env 로드, hardcoded 금지 — 2026-04-17 rotation) ───────────
.tg_load_env <- function() {
  candidates <- c(
    file.path(Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")), ".env"),
    Sys.getenv("QVEST_PROJECT_DIR", ""),
    getwd()
  )
  for (p in candidates) {
    if (!nzchar(p)) next
    # dir.exists 가드: p가 디렉토리면 file.exists(p)=TRUE라 readLines(디렉토리) crash (2026-06-10 fix)
    env_path <- if (file.exists(p) && !dir.exists(p)) p else file.path(p, ".env")
    if (file.exists(env_path)) {
      lines <- readLines(env_path, warn = FALSE)
      for (ln in lines) {
        ln <- trimws(ln)
        if (!nzchar(ln) || startsWith(ln, "#") || !grepl("=", ln, fixed = TRUE)) next
        kv <- strsplit(ln, "=", fixed = TRUE)[[1]]
        if (length(kv) >= 2 && !nzchar(Sys.getenv(kv[1]))) {
          do.call(Sys.setenv, setNames(list(paste(kv[-1], collapse = "=")), kv[1]))
        }
      }
      break
    }
  }
}
.tg_load_env()

.TG_TOKEN      <- Sys.getenv("TG_BOT_TOKEN", "")
.TG_CHAT_ID    <- Sys.getenv("TG_CHAT_ID", "")  # 비공개 채널 (전략 브리핑 채널)
.TG_PERSONAL   <- Sys.getenv("TG_PERSONAL_CHAT_ID", "1355291682")   # 개인 DM fallback
if (!nzchar(.TG_TOKEN) || !nzchar(.TG_CHAT_ID)) {
  warning("[telegram_notify] TG_BOT_TOKEN / TG_CHAT_ID 미설정. .env 확인.")
}
.TG_BASE       <- sprintf("https://api.telegram.org/bot%s", .TG_TOKEN)
.TG_API        <- paste0(.TG_BASE, "/sendMessage")

# ─── SOT 매직 상수 (.claude/skills/qvest-telegram/SKILL.md §3와 1:1 동기화) ───
# v6 (2026-05-07): 가독성 개편. v5 강제값 완화 (1200→400, 4→2, 50→30, 3→2).
# v6.1 (2026-05-08): 모바일 짤림 강제 — text/bullet/kv 상한선 추가, ncol 2 default.
# 변경 시 SKILL.md §3 표 먼저 수정하고 본 list 동기화. 역방향 금지.
.TG_CONFIG <- list(
  MIN_BYTES        = 400L,    # 메시지 최소 바이트 (skeleton 차단)
  MIN_SECTIONS     = 2L,      # 비어있지 않은 섹션 최소 수
  TEXT_MIN         = 30L,     # text body 최소 자수
  TEXT_MAX         = 220L,    # v6.1 신규 — text body 최대 자수 (모바일 가독)
  BULLET_MIN       = 2L,      # bullet 항목 최소 수
  BULLET_ITEM_MAX  = 80L,     # v6.1 신규 — bullet 한 항목 최대 자수
  KV_MIN           = 2L,      # kv 항목 최소 수
  KV_VALUE_MAX     = 60L,     # v6.1 신규 — kv 값 최대 자수
  MAX_NCOL         = 2L,      # v6.1 — table 최대 열 (3→2 강화, 모바일 짤림 방지)
  MAX_TOTAL_WIDTH  = 28L,     # v6.1 — table 합산 폭 (32→28 강화)
  MAX_COL_WIDTH    = 13L,     # v6.1 — table 개별 열 (20→13 강화)
  EMOJI_MIN        = 5L,      # 메시지당 emoji 최소
  SUMMARY_MIN      = 20L,     # summary type 최소 자수 (1줄 헤드라인)
  SUMMARY_MAX      = 100L,    # v6.1 — summary 최대 (200→100 강화, 1줄 의무)
  CODE_MIN         = 20L,     # code body 최소 자수
  TABLE_NROW_MIN   = 2L,      # table nrow 최소
  GLOSSARY_MAX_BYTES = 900L   # v7 — 자동 용어 풀이 footer 최대 바이트 (SKILL.md §5.5)
)

`%||%` <- function(a, b) if (!is.null(a)) a else b

# ─── 전략명+아이디어 추출 헬퍼 ───────────────────────────────────────────────
.extract_strategy_display <- function(strategy_name, output_dir) {
  # output_dir = .../STR_XXX/output/STR_XXX → run_all.R은 2단계 위
  str_dir <- dirname(output_dir)
  # run_all.R 탐색: 현재 dir → 상위 → 2단계 상위
  run_path <- ""
  for (candidate in c(str_dir, dirname(str_dir), dirname(dirname(str_dir)))) {
    p <- file.path(candidate, "run_all.R")
    if (file.exists(p)) { run_path <- p; str_dir <- candidate; break }
  }
  display <- strategy_name
  idea <- ""

  # 1. run_all.R cat("=== STR_XXX: Description ===\n")
  if (file.exists(run_path)) {
    tryCatch({
      lines <- readLines(run_path, n = 15, warn = FALSE)
      m <- grep("cat.*===.*STR_\\d+", lines, value = TRUE)
      if (length(m) > 0) {
        extracted <- regmatches(m[1], regexpr("STR_\\d+[^=]+", m[1]))
        if (length(extracted) > 0) {
          extracted <- trimws(sub("[: ]+$", "", extracted[1]))
          if (nchar(extracted) > nchar(strategy_name) + 2)
            display <- extracted
        }
      }
      # run_all.R ## 주석에서 핵심아이디어 추출 (2~5번째 줄)
      if (idea == "") {
        comment_lines <- grep("^##\\s+", lines, value = TRUE)
        comment_lines <- comment_lines[!grepl("^##\\s*STR_\\d+", comment_lines)]  # 제목줄 제외
        if (length(comment_lines) > 0) {
          idea <- trimws(sub("^##\\s*", "", comment_lines[1]))
          idea <- gsub("^[\"']|[\"']$", "", idea)  # 따옴표 제거
        }
      }
    }, error = function(e) NULL)
  }

  # 2. factor_engine.R cat("[factor_engine] STR_XXX: Description...\n")
  fe_path <- file.path(str_dir, "factor_engine.R")
  if (file.exists(fe_path)) {
    tryCatch({
      lines <- readLines(fe_path, n = 10, warn = FALSE)
      m <- grep("cat.*factor_engine.*STR_\\d+", lines, value = TRUE)
      if (length(m) > 0) {
        extracted <- regmatches(m[1], regexpr("STR_\\d+:\\s*[^.\"]+", m[1]))
        if (length(extracted) > 0) {
          idea <- trimws(sub("^STR_\\d+:\\s*", "", extracted[1]))
        }
      }
      # Also try comment headers: ## STR_XXX  Description
      if (display == strategy_name) {
        hdr <- grep("^##?\\s*STR_\\d+", lines, value = TRUE)
        if (length(hdr) > 0) {
          cleaned <- sub("^##?\\s*", "", hdr[1])
          if (nchar(cleaned) > nchar(strategy_name) + 2)
            display <- trimws(cleaned)
        }
      }
    }, error = function(e) NULL)
  }

  # 3. hurdle_result.json에서 전략 설명 추출
  if (idea == "") {
    hr_path <- file.path(output_dir, "hurdle_result.json")
    if (file.exists(hr_path)) {
      tryCatch({
        hr <- jsonlite::fromJSON(hr_path, simplifyVector = FALSE)
        # role + grade + metrics로 자동 설명 생성
        role <- hr$role %||% "core"
        grade <- hr$grade %||% "?"
        m <- hr$metrics %||% list()
        n_sleeves <- length(list.files(str_dir, pattern = "^sim_sleeve_.*\\.rds$"))
        if (n_sleeves == 0) n_sleeves <- length(list.files(dirname(str_dir), pattern = "^sim_sleeve_.*\\.rds$"))

        # 전략 구조 설명
        struct <- if (n_sleeves >= 3) sprintf("%d-Sleeve Ensemble", n_sleeves)
                  else if (n_sleeves == 2) "2-Sleeve"
                  else "Single Factor"

        idea <- sprintf("%s | %s | SR %.3f | CAGR %.1f%% | MDD %.1f%%",
                        struct, role,
                        as.numeric(m$Sharpe %||% 0),
                        as.numeric(m$CAGR %||% 0),
                        as.numeric(m$MDD %||% 0))
      }, error = function(e) NULL)
    }
  }

  # 4. Directory name fallback: STR_559_entropy_gate → "Entropy Gate"
  if (display == strategy_name) {
    dir_name <- basename(str_dir)
    parts <- strsplit(dir_name, "_")[[1]]
    if (length(parts) >= 3) {
      desc_parts <- parts[3:length(parts)]
      desc_parts <- sapply(desc_parts, function(w)
        paste0(toupper(substr(w, 1, 1)), substr(w, 2, nchar(w))))
      display <- paste(strategy_name, paste(desc_parts, collapse = " "))
    }
  }

  # idea가 display와 거의 같으면 중복 제거
  if (nchar(idea) > 0 && grepl(gsub("[^a-zA-Z0-9]", "", idea),
                                gsub("[^a-zA-Z0-9]", "", display), fixed = TRUE))
    idea <- ""

  list(display = display, idea = idea)
}

# ─── Core send function ───────────────────────────────────────────────────────
.tg_serial_enabled <- function() {
  tolower(Sys.getenv("QVEST_TG_SERIAL_LOCK", "true")) %in% c("1", "true", "yes")
}

.tg_lock_held <- function() identical(Sys.getenv("QVEST_TG_LOCK_HELD", ""), "1")

.tg_lock_root <- function() {
  # 2026-07-25 수리: 구현은 전역 PROJECT_ROOT를 dir.exists()만으로 신뢰했다. 그 검사는
  #   *어떤* 디렉토리에도 통과하므로, PROJECT_ROOT가 하위 디렉토리로 오염되면(중첩 source의
  #   sys.frame(1)$ofile 오염 — memory_health_check.R 2026-07-25 수리와 동일 계열) 락이
  #   <오염root>/stage_artifacts/telegram_locks 에 생성된다. 결과는 단순 잔재가 아니라
  #   **직렬화 무력화** — root가 서로 다른 두 프로세스가 각자 다른 락을 잡고 동시 발송한다.
  #   (실측: 02_Infrastructure/stage_artifacts/telegram_locks 생성)
  #   → 프로젝트 루트 표지(02_Infrastructure)로 검증한 후보만 채택한다.
  #   경로 정규화는 슬래시 치환으로만 한다 (한글경로 정책 — 경로 정규화 함수 미사용).
  .valid <- function(p) {
    length(p) == 1L && !is.na(p) && nzchar(p) &&
      dir.exists(p) && dir.exists(file.path(p, "02_Infrastructure"))
  }
  cands <- c(
    if (exists("PROJECT_ROOT")) tryCatch(as.character(get("PROJECT_ROOT")), error = function(e) "") else "",
    Sys.getenv("CLAUDE_PROJECT_DIR", ""),
    Sys.getenv("QM_ROOT", "")
  )
  for (p in cands) if (.valid(p)) return(sub("/+$", "", gsub("\\\\", "/", p)))
  tempdir()
}

tg_with_serial_lock <- function(scope = "telegram_global", expr,
                                timeout_sec = 900,
                                stale_sec = 1800,
                                owner = NULL) {
  expr <- substitute(expr)
  env <- parent.frame()
  if (!.tg_serial_enabled() || .tg_lock_held()) return(eval(expr, env))

  lock_root <- file.path(.tg_lock_root(), "stage_artifacts", "telegram_locks")
  lock_dir <- file.path(lock_root, "global_send.lock")
  dir.create(lock_root, recursive = TRUE, showWarnings = FALSE)

  started <- Sys.time()
  acquired <- FALSE
  repeat {
    acquired <- dir.create(lock_dir, showWarnings = FALSE)
    if (isTRUE(acquired)) {
      meta <- c(
        sprintf("scope=%s", scope %||% "telegram_global"),
        sprintf("owner=%s", owner %||% "unknown"),
        sprintf("pid=%s", Sys.getpid()),
        sprintf("started=%s", format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"))
      )
      try(writeLines(meta, file.path(lock_dir, "owner.txt")), silent = TRUE)
      break
    }

    info <- suppressWarnings(file.info(lock_dir))
    if (nrow(info) == 1L && !is.na(info$mtime)) {
      age <- as.numeric(difftime(Sys.time(), info$mtime, units = "secs"))
      if (is.finite(age) && age > stale_sec) {
        cat(sprintf("[tg_serial_lock] stale lock removed (age %.0fs)\n", age))
        unlink(lock_dir, recursive = TRUE, force = TRUE)
        next
      }
    }

    waited <- as.numeric(difftime(Sys.time(), started, units = "secs"))
    if (is.finite(waited) && waited > timeout_sec) {
      cat(sprintf("[tg_serial_lock] timeout after %.0fs — sending without serial lock\n", waited))
      return(eval(expr, env))
    }
    Sys.sleep(runif(1L, 0.4, 1.2))
  }

  old_held <- Sys.getenv("QVEST_TG_LOCK_HELD", unset = NA_character_)
  Sys.setenv(QVEST_TG_LOCK_HELD = "1")
  on.exit({
    if (is.na(old_held)) Sys.unsetenv("QVEST_TG_LOCK_HELD") else Sys.setenv(QVEST_TG_LOCK_HELD = old_held)
    if (isTRUE(acquired)) unlink(lock_dir, recursive = TRUE, force = TRUE)
  }, add = TRUE)
  eval(expr, env)
}

# ─── 발송 실패 내구 기록 (2026-08-16 신설, TG-01) ────────────────────────────
#   구판 tg_send 는 HTTP 400 을 cat 으로만 흘리고 invisible(resp) 를 돌려줬다.
#   R 에러가 아니므로 호출부의 tryCatch(error=) 가 발화하지 않는다 —
#   cache_freshness_audit.R 이 2026-07-26 CFA-04 로 만들어 둔 alert_delivery="FAILED"
#   표면도 그래서 도달 불가였다(실측 2026-08-16: 400 거부된 런의 latest JSON 에
#   alert_delivery 필드 자체가 부재). 결과: 경보 채널이 죽은 채로 last_sent_at 만
#   갱신돼, 07-03~08-15 최소 20건이 무발송으로 쌓이는 동안 어느 표면도 그것을
#   드러내지 못했다("경보 시스템 자신의 실패는 감시 대상이어야 한다"의 실패).
#   ⇒ 실패는 stdout 이 아니라 내구 원장에 남긴다 — 무인 런의 stdout 은 아무도 안 읽는다.
#   루트 해석은 기존 포장도로(.tg_lock_root)를 재사용한다(PROJECT_ROOT 오염 방어 포함).
.TG_FAIL_LEDGER <- "qepm/observability/telegram_send_failures.jsonl"
.tg_record_send_failure <- function(kind, detail, msg_head, parse_mode,
                                    status = NA_integer_) {
  tryCatch({
    d <- file.path(.tg_lock_root(), "qepm", "observability")
    if (!dir.exists(d)) dir.create(d, recursive = TRUE, showWarnings = FALSE)
    rec <- list(
      ts         = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
      kind       = kind,
      status     = if (is.na(status)) NULL else as.integer(status),
      parse_mode = if (nzchar(parse_mode %||% "")) parse_mode else "plain",
      msg_head   = substr(gsub("[\r\n]+", " ", as.character(msg_head)), 1L, 160L),
      detail     = substr(as.character(detail), 1L, 500L),
      # (2026-08-20) 원장 자기라벨링 — 검사 픽스처가 죽은 포트로 쏘면 그 실패도 여기 쌓인다
      #   (실측: 7줄 중 3줄이 127.0.0.1:1 테스트 노이즈). 기록을 **막지는 않는다**:
      #   test_telegram_send_contract 의 T2 가 "실패가 원장에 적립되는가"를 보는 축이라,
      #   테스트 기록을 빼면 그 검증이 죽는다(검증기를 건너뛰는 수리 = 이 저장소 반복 실패).
      #   대신 실경로 여부를 필드로 남겨 진짜 장애만 골라낼 수 있게 한다.
      live       = startsWith(.TG_API %||% "", "https://api.telegram.org")
    )
    cat(jsonlite::toJSON(rec, auto_unbox = TRUE, null = "null"), "\n", sep = "",
        file = file.path(d, "telegram_send_failures.jsonl"), append = TRUE)
  }, error = function(e) invisible(NULL))
}

#' tg_send — 반환 계약 (2026-08-16 TG-01):
#'   invisible(list(ok=<lgl>, kind=<"sent"|"http_error"|"exception">,
#'                  status=<int|NA>, error=<chr|NA>))
#'   ok=FALSE 는 **호출부가 반드시 검사**해야 한다. 구판은 invisible(resp) 였고
#'   반환값을 소비하는 호출부가 0/115 였다(2026-08-16 전수) — 그래서 계약 변경이 안전.
tg_send <- function(msg, parse_mode = "", silent = FALSE,
                     validate_emoji = TRUE, emoji_min = 1L) {
  .tg_ensure_utf8_ctype()  # 발송 직전 재보증 (중간 locale 리셋 방어; UTF-8이면 no-op)
  if (.tg_serial_enabled() && !.tg_lock_held()) {
    return(tg_with_serial_lock(
      scope = "tg_send",
      owner = substr(gsub("\\s+", " ", as.character(msg %||% "")), 1L, 80L),
      tg_send(msg, parse_mode = parse_mode, silent = silent,
              validate_emoji = validate_emoji, emoji_min = emoji_min)
    ))
  }
  # 2026-04-23: 기본 parse_mode "" (plain). HTML은 <, > 기호로 parse error 유발.
  # 2026-04-24: validate_emoji — 이모지 0개 감지 시 warning log (Judge/Risk 누락 방지)
  if (validate_emoji) {
    # Unicode emoji 범위 (1F300~1F9FF 확장 + 2600~27BF 기본)
    emoji_n <- tryCatch(
      length(regmatches(msg, gregexpr("[\U0001F300-\U0001F9FF☀-➿]", msg, perl = TRUE))[[1]]),
      error = function(e) 0L  # Windows R: astral-range regex invalid → 검증 skip, 발송은 진행
    )
    if (!is.finite(emoji_n)) emoji_n <- 0L
    if (emoji_n < emoji_min) {
      warn_line <- sprintf(
        "%s [tg_send WARN] emoji count %d < min %d (msg first 60: '%s')",
        format(Sys.time(), "%Y-%m-%dT%H:%M:%S"),
        emoji_n, emoji_min, substr(msg, 1, 60)
      )
      cat(warn_line, "\n", sep = "")
      try(cat(warn_line, "\n", file = "/tmp/qvest_tg_emoji_warn.log",
              append = TRUE, sep = ""),
          silent = TRUE)
    }
  }

  tryCatch({
    resp <- POST(.TG_API, body = list(
      chat_id    = .TG_CHAT_ID,
      text       = msg,
      parse_mode = parse_mode
    ), encode = "json")
    if (http_error(resp)) {
      .body <- content(resp, "text", encoding = "UTF-8")
      if (!silent) cat(sprintf("[tg] Send failed: %s\n", .body))
      # silent 여도 원장에는 남긴다 — silent 는 "조용히"이지 "없던 일"이 아니다.
      .tg_record_send_failure("http_error", .body, msg, parse_mode, status_code(resp))
      invisible(list(ok = FALSE, kind = "http_error",
                     status = status_code(resp), error = .body))
    } else {
      invisible(list(ok = TRUE, kind = "sent",
                     status = status_code(resp), error = NA_character_))
    }
  }, error = function(e) {
    cat(sprintf("[tg] Error: %s\n", e$message))
    .tg_record_send_failure("exception", e$message, msg, parse_mode)
    invisible(list(ok = FALSE, kind = "exception",
                   status = NA_integer_, error = e$message))
  })
}

# ─── 표 포맷 헬퍼 (Step 6, 2026-04-24; v2 CJK-aware width guard 2026-04-24) ──
# data.frame → <pre> HTML 블록. 고정폭 공백 정렬. tg_send_rich와 함께 사용.
#
# 모바일 텔레그램 HTML <pre>는 가로폭 제한. 한글(CJK)은 font width 2칸 차지.
# - max_col_width: 개별 column 상한 (default 20, 초과 시 "…" 축약)
# - max_total_width: 표 전체 폭 상한 (default 40, 초과 시 stderr 경고)
# - CJK 2-width 계산: han/kana/hangul 범위 U+1100~U+11FF, U+3040~U+30FF,
#   U+3400~U+4DBF, U+4E00~U+9FFF, U+AC00~U+D7A3, U+F900~U+FAFF 등 2칸
.cjk_width <- function(s) {
  if (is.na(s) || length(s) == 0) return(0L)
  s <- as.character(s)
  cps <- utf8ToInt(s)
  # ASCII + Latin + 기본 punctuation = 1, 그 외 CJK 블록 = 2
  ranges <- list(
    c(0x1100, 0x115F), c(0x2E80, 0x303E), c(0x3041, 0x33FF),
    c(0x3400, 0x4DBF), c(0x4E00, 0x9FFF), c(0xA000, 0xA4CF),
    c(0xAC00, 0xD7A3), c(0xF900, 0xFAFF), c(0xFE30, 0xFE4F),
    c(0xFF00, 0xFF60), c(0xFFE0, 0xFFE6), c(0x20000, 0x2FFFD)
  )
  is_wide <- vapply(cps, function(cp) {
    any(vapply(ranges, function(r) cp >= r[1] && cp <= r[2], logical(1)))
  }, logical(1))
  sum(ifelse(is_wide, 2L, 1L))
}

.truncate_width <- function(s, max_w) {
  if (is.na(s)) return("")
  s <- as.character(s)
  if (.cjk_width(s) <= max_w) return(s)
  # 뒤에서 1자씩 제거하며 "…" 포함 폭이 max_w 이내인지 확인
  ellipsis <- "…"  # …
  cps <- utf8ToInt(s)
  for (k in seq(length(cps) - 1, 1, by = -1)) {
    cand <- paste0(intToUtf8(cps[seq_len(k)]), ellipsis)
    if (.cjk_width(cand) <= max_w) return(cand)
  }
  ellipsis
}

tg_format_table <- function(df, separator = "-",
                              max_col_width = .TG_CONFIG$MAX_COL_WIDTH,
                              max_total_width = .TG_CONFIG$MAX_TOTAL_WIDTH,
                              auto_escape = TRUE,
                              ncol_max = .TG_CONFIG$MAX_NCOL) {
  if (!is.data.frame(df) || nrow(df) == 0) return("")
  cols <- names(df)

  # v6 SOT (.TG_CONFIG$MAX_NCOL): ncol 초과 시 차단. caller가 kv 또는 행 분할 사용.
  if (length(cols) > ncol_max) {
    stop(sprintf("[tg_format_table] v6 SOT: ncol=%d > %d cap. 모바일 가독성. kv 또는 long-format으로 reformat 필요.",
                 length(cols), ncol_max))
  }

  # v5: max_col_width 자동 fit — 총 너비가 cap 넘지 않게 floor 계산
  # 총 너비 = sum(widths) + 2 * (ncol - 1)
  # → max width per col = floor((cap - 2*(ncol-1)) / ncol)
  ncol_n <- length(cols)
  auto_max_col <- as.integer(floor((max_total_width - 2L * (ncol_n - 1L)) / ncol_n))
  if (auto_max_col < 6L) auto_max_col <- 6L  # 최소 보장
  effective_max_col <- as.integer(min(max_col_width, auto_max_col))

  char_df <- as.data.frame(lapply(df, function(x) as.character(x)),
                            stringsAsFactors = FALSE)

  # 1) 값 truncate (effective_max_col, v5 자동 fit)
  char_df[] <- lapply(char_df, function(vals) {
    vapply(vals, .truncate_width, character(1), max_w = effective_max_col)
  })

  # 1.5) HTML auto-escape (2026-04-24 v3, raw <>& 로 HTML 파싱 깨짐 방지)
  # Telegram HTML parse_mode는 <pre> 블록 내부도 escape 필요.
  # 예: "Harvey t>3" → <pre> 안에서 "t<tag>3..." 오인 파싱.
  # 너비 계산은 escape 전 기준 (시각적 너비 보존), escape는 최종 렌더 단계에서만.
  if (isTRUE(auto_escape)) {
    cols_escaped <- vapply(cols, tg_html_escape, character(1))
    char_df_escaped <- as.data.frame(
      lapply(char_df, function(vals) vapply(vals, tg_html_escape, character(1))),
      stringsAsFactors = FALSE
    )
  } else {
    cols_escaped <- cols
    char_df_escaped <- char_df
  }

  # 2) CJK-aware 너비 계산 (header + truncated values, effective_max_col 적용)
  widths <- mapply(function(colname, vals) {
    header_w <- .cjk_width(colname)
    val_w <- if (length(vals) == 0) 0L else max(vapply(vals, .cjk_width, integer(1)))
    as.integer(min(max(header_w, val_w), effective_max_col))
  }, cols, char_df, USE.NAMES = FALSE)

  # 3) 총 폭 체크 (v6 SOT .TG_CONFIG$MAX_TOTAL_WIDTH) — cap 초과 시 stop()
  total_w <- sum(widths) + 2L * (length(widths) - 1L)
  if (total_w > max_total_width) {
    stop(sprintf("[tg_format_table] v6 SOT: total width %d > %d cap (ncol=%d, effective_max_col=%d). 모바일 가독성 위반. kv/long-format reformat 필요.",
                 total_w, max_total_width, ncol_n, effective_max_col))
  }

  # pad: 시각적 너비 기준. escape된 entity(e.g. &gt;)는 pre 렌더 시 1자 보이므로
  # pad용 width 계산은 "escape 해제 후" 기준 (원본 cjk width 사용).
  pad <- function(s_escaped, s_original, w) {
    spc <- w - .cjk_width(s_original)
    if (spc > 0) paste0(s_escaped, strrep(" ", spc)) else s_escaped
  }

  header <- paste(mapply(pad, cols_escaped, cols, widths), collapse = "  ")
  sep_line <- paste(sapply(widths, function(w) strrep(separator, w)),
                     collapse = "  ")
  body_rows <- vapply(seq_len(nrow(char_df)), function(i) {
    paste(mapply(pad,
                 as.character(char_df_escaped[i, , drop = TRUE]),
                 as.character(char_df[i, , drop = TRUE]),
                 widths),
          collapse = "  ")
  }, character(1))

  paste0("<pre>",
         paste(c(header, sep_line, body_rows), collapse = "\n"),
         "</pre>")
}

# ─── Rich send (HTML parse_mode) ───────────────────────────────────────────
# <pre> 표 / <b> 강조 등 HTML 허용. Message 내 &, <, > 는 caller가 escape 필수
# (tg_format_table는 이미 plain 입력).
#
# 2026-04-24 v3 — &quot; guard: Telegram Bot API HTML parser 일부 버전에서
# &quot; entity 거부 → 전체 메시지 plain text fallback → <pre> 태그 문자로 보임.
# auto_sanitize=TRUE면 &quot; → " (U+0022), 그리고 지원 안 되는 다른 entity 경고.
tg_send_rich <- function(msg, silent = FALSE,
                          validate_emoji = TRUE, emoji_min = 1L,
                          auto_sanitize = TRUE) {
  if (isTRUE(auto_sanitize)) {
    original <- msg
    # 1) Telegram HTML는 &lt; / &gt; / &amp; 만 공식 지원. &quot;는 raw " 로 대체.
    msg <- gsub("&quot;", '"', msg, fixed = TRUE)

    # 2) Plain text 내 raw "<", ">" escape (2026-04-24 v4).
    #    HTML 유효 태그는 보존, 그 외 "<" 뒤에 숫자/한글/공백이면 entity 오인 가능 → escape.
    #    Telegram HTML supported tags: b, i, u, s, del, strike, pre, code, a, em, strong,
    #    tg-spoiler, tg-emoji, span class=... (+ 닫는 tag: </b> 등)
    valid_tag <- "b|i|u|s|del|strike|pre|code|a|em|strong|tg-spoiler|tg-emoji|span"
    # "<" 뒤에 유효 태그(또는 /) + space/attr/> 가 아니면 escape
    # 예: "<40" → "&lt;40", "<b>" → 보존, "</code>" → 보존
    pattern_lt <- sprintf("<(?!/?(?:%s)(?:\\s[^>]*)?/?>)", valid_tag)
    msg <- gsub(pattern_lt, "&lt;", msg, perl = TRUE)
    # ">" 다음이 숫자/한글/공백이고 바로 앞이 유효 태그 닫는 것이 아닐 때 escape
    # 보수적으로: ">" 앞뒤에 HTML 태그 패턴이 없으면 escape (예: "42.9% > Gate D" 같은 비교)
    # 단순하게: 텍스트에서 자주 쓰이는 "X > Y" "X >=" 패턴 escape
    msg <- gsub("(?<=[\\s0-9A-Za-z가-힣])\\s+>\\s+(?=[\\s0-9A-Za-z가-힣])", " &gt; ", msg, perl = TRUE)
    msg <- gsub("(?<=[0-9])>(?=[0-9])", "&gt;", msg, perl = TRUE)

    # 3) 기타 위험한 entity 경고 (예: &nbsp; &copy; 등)
    #
    # 2026-08-02 수리 — 오프셋 계통 결함. 위반 주입 테스트:
    #   08_Tests/hooks/test_telegram_entity_scan.R (배터리 등재).
    #
    #   구판은 TRE(기본 엔진)로 gregexpr 했다. Windows R 의 TRE 는 위치를 wchar_t =
    #   **UTF-16 코드유닛**으로 세는데, regmatches/substr 은 **코드포인트**로 자른다.
    #   → 매치 앞에 non-BMP 문자(이모지 U+1F4CC 등)가 N개 있으면 추출 창이 정확히
    #     N칸 오른쪽으로 밀린다. tg_agent_brief 는 머리말·섹션마다 이모지를 넣으므로
    #     이 경로로 나가는 사실상 모든 메시지가 해당된다.
    #   실측(WT-D20260802_012 R43, 4658 bytes): '&lt;' 실제 char 위치 1664 · TRE 보고
    #     1670 (앞선 non-BMP 6개 = 📡📅📌📖📊🚩) → 추출 '턱 1.' → 정상 escape 된 &lt; 가
    #     "미지원 entity"로 오경보. /tmp/qvest_tg_entity_warn.log 의 07-26~08-02 경보
    #     20건은 전부 이 유령이다('t;1/', 'lt;2', '5% —' 등 = 밀린 창의 내용).
    #   ★ 반대 방향이 더 위험하다: 창이 밀리면 **진짜** 미지원 entity(&le; 등)는 결코
    #     이름이 불리지 않고, 밀린 창이 우연히 &lt;/&gt;/&amp; 위에 떨어지면 아래 setdiff
    #     가 그것을 걸러낸다 — 발화해야 할 때 조용해진다("빈/틀린 결과가 합격으로 읽힘").
    #
    #   수리 3중:
    #     ① perl=TRUE — PCRE2 는 코드포인트로 색인하므로 substr 과 정합 (실측 1664 일치).
    #     ② 길이 상한 {0,9} — 병리적 장거리 스팬 차단.
    #     ③ 추출-후 자기검증 — 뽑힌 토큰이 entity 모양이 아니면 그것은 "위반 없음"이
    #        아니라 **색인기 고장**이다. 침묵 대신 별도 ERROR 로 드러낸다.
    # 로그 경로는 env 로 우회 가능 — 검사기가 운영 원장에 픽스처를 섞으면 나중에
    # 이 원장을 forensic 으로 읽을 때(이번 수리가 그렇게 진단됐다) 오독을 부른다.
    .warn_entity <- function(txt) {
      message(txt)
      log_f <- Sys.getenv("QVEST_TG_ENTITY_LOG", unset = "/tmp/qvest_tg_entity_warn.log")
      tryCatch(cat(sprintf("%s %s\n", format(Sys.time()), txt), file = log_f, append = TRUE),
               error = function(e) NULL)
    }
    ent_re <- "&[A-Za-z][A-Za-z0-9]{0,9};"
    risky  <- regmatches(msg, gregexpr(ent_re, msg, perl = TRUE))[[1]]

    # ③ 자기검증: 추출물은 자신이 매치됐다는 바로 그 패턴을 다시 만족해야 한다.
    corrupt <- risky[!grepl(sprintf("^%s$", ent_re), risky, perl = TRUE)]
    if (length(corrupt) > 0) {
      .warn_entity(sprintf(
        paste0("[tg_send_rich] ERROR entity-scan 색인 붕괴 — 추출물이 entity 모양이 ",
               "아님: %s (스캔 결과 신뢰 불가)"),
        paste(encodeString(corrupt), collapse = ", ")))
    }

    risky <- setdiff(unique(risky), c("&lt;", "&gt;", "&amp;"))
    if (length(risky) > 0) {
      .warn_entity(sprintf("[tg_send_rich] WARN unsupported HTML entity: %s.",
                           paste(risky, collapse = ", ")))
    }
    if (!identical(original, msg)) {
      message("[tg_send_rich] INFO auto-sanitize applied. See /tmp/qvest_tg_entity_warn.log")
    }
  }
  tg_send(msg, parse_mode = "HTML", silent = silent,
          validate_emoji = validate_emoji, emoji_min = emoji_min)
}

# HTML-safe escape 헬퍼 (표 밖 일반 텍스트에 < > & 있을 때 사용)
tg_html_escape <- function(x) {
  x <- gsub("&", "&amp;", x, fixed = TRUE)
  x <- gsub("<", "&lt;", x, fixed = TRUE)
  x <- gsub(">", "&gt;", x, fixed = TRUE)
  x
}

# ─── Mobile-safe Gate 표 (2026-04-24, Telegram 모바일 가독성 영구 수정) ────
# 긴 Note column이 모바일에서 줄바꿈 → 정렬 붕괴 원인.
# Gate 결과는 2-column 컴팩트 표 + Note는 별도 bullet list(prose)로 분리.
# 사용: gates <- list(list(name="A PIT", verdict="PASS", note="..."), ...)
#       tg_format_gate_block(gates) → "<pre>표</pre>\n\n• A PIT: note..."
tg_format_gate_block <- function(gates, max_note_chars = 46L) {
  if (length(gates) == 0) return("")
  # 2-column 컴팩트 표 (Gate / Verdict만)
  df <- data.frame(
    Gate    = vapply(gates, function(g) as.character(g$name), character(1)),
    Verdict = vapply(gates, function(g) as.character(g$verdict), character(1)),
    stringsAsFactors = FALSE
  )
  tbl <- tg_format_table(df)

  # Note는 bullet list로 분리 (모바일에서 자연 줄바꿈 허용)
  notes <- vapply(gates, function(g) {
    n <- as.character(g$note %||% "")
    if (nchar(n) == 0) return(NA_character_)
    if (nchar(n) > max_note_chars) n <- paste0(substr(n, 1, max_note_chars - 1), "…")
    sprintf("  • %s: %s", g$name, tg_html_escape(n))
  }, character(1))
  notes <- notes[!is.na(notes)]

  if (length(notes) == 0) return(tbl)
  paste0(tbl, "\n", paste(notes, collapse = "\n"))
}

# NULL-coalescing helper (handle vectors + NA safely)
`%||%` <- function(a, b) {
  if (is.null(a) || length(a) == 0) return(b)
  if (length(a) == 1 && is.character(a) && !nzchar(a)) return(b)
  a
}

# ─── Agent Brief — 단일 진입점 (2026-04-24 v1, SOT) ────────────────────────────
# 모든 agent (Alpha/Risk/Optimizer/Forge/Judge/Governor/Q-Lead)는
# 이 함수만 호출. 직접 tg_send_rich + tg_format_table 조립 금지.
# 내부에서 auto_escape + auto_sanitize + emoji 검증 + Single-Dispatch + 모바일 guard 자동.
#
# 사용법:
#   tg_agent_brief(
#     agent = "Risk",
#     title = "WT-D20260424_003 Σ + Hedge 완료",
#     as_of = "2026-04-24",
#     sections = list(
#       list(emoji = "🔬", heading = "Covariance 자율 비교",
#            type = "table",
#            df = data.frame(Estimator=c("LW","Gerber"), Cond=c("11","128")),
#            max_col_width = 15L,
#            notes = c("Primary: LW Oracle", "Backup: Sample")),
#       list(emoji = "💡", heading = "핵심 발견",
#            type = "text",
#            body = "FF3 retention 10.5%..."),
#       list(emoji = "🚨", heading = "Challenges",
#            type = "bullet",
#            items = c("REGIME_DISCREPANCY MEDIUM", "FF3_INFO"))
#     ),
#     charts = c("stage_artifacts/WT_X/chart.png"),
#     footer = "➡️ Next: Optimizer"
#   )
#
# Return: list(ok=TRUE/FALSE, error=NULL/str, bytes=int)
.AGENT_EMOJI_MAP <- list(
  "Q-Lead"   = "🎯",
  "Alpha"    = "🔬",
  "Risk"     = "🛡️",
  "Optimizer" = "⚖️",
  "Forge"    = "🔨",
  "Judge"    = "⚖️",
  "Governor" = "👑",
  "Scout"    = "📚",
  "Execution" = "🎬",
  "Monitoring" = "📡",
  "Architect" = "🏛️",
  "AlphaSearch" = "🔭"
)

# ─── Emoji Catalog v1 (2026-04-24) — SOT for tg_agent_brief sections ────────
# 카테고리별 표준 이모지. Caller는 tg_emoji() 또는 tg_emoji_*() helper 사용.
.EMOJI_CATALOG <- list(
  # Status (verdict / gate / flag)
  status = list(
    pass = "✅", fail = "❌", warn = "⚠️", info = "ℹ️",
    progress = "🔄", pending = "⏳", block = "🚧",
    cond = "🟡", mixed = "🔵"
  ),
  # Section heading (의미별 권장)
  section = list(
    metrics = "📊",        # 수치/통계
    up = "📈",              # 상승
    down = "📉",            # 하락
    target = "🎯",          # 목표
    research = "🔬",        # 리서치/방법론
    risk = "🛡️",           # 리스크
    config = "🎛️",         # 구성/설정
    alert = "🚨",           # 경보
    flag = "🚩",            # red flag
    insight = "💡",         # insight
    integration = "🔗",     # 통합/매핑
    stress = "🌪️",         # stress test
    new = "✨",             # 신규/최신
    reference = "📚",       # 참조/문헌
    ranking = "🏆",         # 순위/shortlist
    test = "🧪",            # test
    challenge = "⚔️",       # challenge loop
    next_step = "➡️",       # next step
    date = "📅",            # date
    folder = "📂",          # path
    package = "📦",         # package
    tool = "🛠️",           # tool/fix
    sparkle = "✨",         # new feature
    lock = "🔒",            # lockbox
    trophy = "🏆",          # final
    chart = "📈"            # chart
  ),
  # Performance grade (수치 → 이모지)
  performance_sr = list(
    superior = "🚀",    # SR >= 2.0
    good = "✨",         # 1.5 <= SR < 2.0
    acceptable = "✅",   # 1.0 <= SR < 1.5
    weak = "⚠️"         # SR < 1.0
  ),
  performance_mdd = list(
    low = "✅",          # MDD < 20%
    medium = "⚠️",       # 20% <= MDD < 35%
    high = "❌"          # MDD >= 35%
  ),
  performance_cagr = list(
    target = "🎯",       # CAGR >= 16%
    acceptable = "✅",   # 10% <= CAGR < 16%
    weak = "⚠️"         # CAGR < 10%
  ),
  # Regime (MRS score)
  regime = list(
    crisis = "🚨",       # >= 60
    stress = "🔥",       # 40~60
    caution = "🟡",      # 25~40
    normal = "🟢",       # 15~25
    easy = "💚"          # < 15
  )
)

# Helper: category + key → emoji
# 예: tg_emoji("status", "pass") → "✅"
tg_emoji <- function(category, key) {
  if (!category %in% names(.EMOJI_CATALOG)) {
    warning(sprintf("[tg_emoji] Unknown category '%s'. Available: %s",
                    category, paste(names(.EMOJI_CATALOG), collapse = ", ")))
    return("")
  }
  cat_map <- .EMOJI_CATALOG[[category]]
  if (!key %in% names(cat_map)) {
    warning(sprintf("[tg_emoji] Unknown key '%s' in '%s'. Available: %s",
                    key, category, paste(names(cat_map), collapse = ", ")))
    return("")
  }
  cat_map[[key]]
}

# Performance grade emoji (자동 계산)
# 예: tg_emoji_perf(sr = 1.8, mdd = 0.22, cagr = 0.18) → list(sr="✨", mdd="⚠️", cagr="🎯")
tg_emoji_perf <- function(sr = NULL, mdd = NULL, cagr = NULL) {
  result <- list()
  if (!is.null(sr) && !is.na(sr)) {
    result$sr <- if (sr >= 2.0) "🚀"
                 else if (sr >= 1.5) "✨"
                 else if (sr >= 1.0) "✅"
                 else "⚠️"
  }
  if (!is.null(mdd) && !is.na(mdd)) {
    abs_mdd <- abs(mdd)  # allow -0.25 or 0.25 both
    result$mdd <- if (abs_mdd < 0.20) "✅"
                  else if (abs_mdd < 0.35) "⚠️"
                  else "❌"
  }
  if (!is.null(cagr) && !is.na(cagr)) {
    result$cagr <- if (cagr >= 0.16) "🎯"
                   else if (cagr >= 0.10) "✅"
                   else "⚠️"
  }
  result
}

# Regime emoji from MRS score (0~100)
tg_emoji_regime <- function(score) {
  if (is.null(score) || is.na(score)) return("")
  if (score >= 60) return("🚨")
  if (score >= 40) return("🔥")
  if (score >= 25) return("🟡")
  if (score >= 15) return("🟢")
  "💚"
}

# Verdict emoji from string ("PASS"/"FAIL"/"WARN"/"COND"/etc)
# 순서 중요: COND_FAIL → 🟡 / MIXED_PASS → 🔵 / 순수 FAIL → ❌
tg_emoji_verdict <- function(verdicts) {
  vapply(verdicts, function(v) {
    v_up <- toupper(as.character(v))
    # Compound verdict (우선순위 높음)
    if (grepl("COND", v_up)) return("🟡")       # CONDITIONAL_*  → 🟡 (모든 COND 먼저)
    if (grepl("MIXED", v_up)) return("🔵")      # MIXED_*
    if (grepl("BLOCK", v_up)) return("🚧")
    # Pure states
    if (grepl("PASS", v_up)) return("✅")
    if (grepl("FAIL", v_up)) return("❌")
    if (grepl("WARN", v_up)) return("⚠️")
    if (grepl("INFO", v_up)) return("ℹ️")
    if (grepl("PROGRESS|PROG", v_up)) return("🔄")
    if (grepl("PENDING", v_up)) return("⏳")
    ""
  }, character(1))
}

# ─── v6 SOT 약어 풀이 사전 (.claude/skills/qvest-telegram/SKILL.md §5와 동기화) ───
# 정통 한글 퀀트 용어 (Harvey 2016 / Lopez de Prado 표기 한글화).
# 변경 시 SKILL.md §5 표 먼저 수정하고 본 list 동기화.
.JARGON_DICT <- list(
  # 내부 식별자 (long pattern 먼저 — overlap 방지)
  list(pattern = "WT-D[0-9]{8}_[0-9]{3}",  ko = "발견형 작업"),
  list(pattern = "WT-P[0-9]{8}_[0-9]{3}",  ko = "운용형 작업"),
  list(pattern = "STR_[0-9]{4}",            ko = "전략"),
  list(pattern = "AX-[0-9]{3}",             ko = "공리"),
  list(pattern = "L-[0-9]{2,4}",            ko = "교훈"),
  list(pattern = "RF-[A-Z][0-9]+",          ko = "위험신호"),
  list(pattern = "\\bPG[0-3]\\b",           ko = "운용단계"),

  # 계량 지표 (정통 한글)
  list(pattern = "\\bICIR\\b",              ko = "정보계수 안정성"),
  list(pattern = "\\bCAGR\\b",              ko = "연복리수익률"),
  list(pattern = "\\bMDD\\b",               ko = "최대낙폭"),
  list(pattern = "\\bDSR\\b",               ko = "디플레이티드 샤프"),
  list(pattern = "\\bSR\\b",                ko = "샤프지수"),
  list(pattern = "\\bIC\\b",                ko = "정보계수"),
  list(pattern = "Harvey[- ]?t\\b",         ko = "다중검정 t값"),
  list(pattern = "\\bt_NW\\b",              ko = "Newey-West t값"),
  list(pattern = "Bailey[- ]?LdP\\b",       ko = "Lopez de Prado 검정"),
  list(pattern = "\\bTDC\\b",               ko = "꼬리 의존성"),
  list(pattern = "\\bMRS\\b",               ko = "시장 국면 점수"),
  list(pattern = "\\bSUE\\b",               ko = "표준화 어닝 서프라이즈"),
  list(pattern = "\\bESBR\\b",              ko = "이익 변경률"),
  list(pattern = "\\bADV\\b",               ko = "평균 거래대금"),
  list(pattern = "\\bFF[35]\\b",            ko = "Fama-French 팩터"),
  list(pattern = "\\bBAB\\b",               ko = "저베타"),
  list(pattern = "\\bBM_Ret\\b",            ko = "벤치마크 수익률"),
  list(pattern = "\\bOOS\\b",               ko = "표본 외 검증"),
  list(pattern = "Σ",                       ko = "공분산"),
  list(pattern = "\\bcovariance\\b",         ko = "공분산")
  # VaR / ES / CVaR / IVOL / TE / PnL / NAV 등 한국 통용 영문 약어는 retain (decode X)
)

# tg_decode_jargon: SKILL.md §5 정책 — 약어 첫 등장 1회 한글 풀이 (default)
#  mode "inline_first": 본문 첫 등장에 "약어 (한글)" 부착 (이후는 그대로)
#  mode "footer":       본문 미변환 + 등장 약어 합쳐 footer 부착
#  mode "off":          변환 없음 (정통 보고서)
tg_decode_jargon <- function(text, mode = c("inline_first", "footer", "off")) {
  mode <- match.arg(mode)
  if (mode == "off" || !is.character(text) || length(text) != 1 || !nzchar(text)) return(text)

  # <pre>...</pre> 블록 보호 (마스킹 후 복원)
  pre_pattern <- "<pre>[\\s\\S]*?</pre>"
  pre_locs <- gregexpr(pre_pattern, text, perl = TRUE)[[1]]
  pre_blocks <- character(0)
  if (pre_locs[1] != -1) {
    pre_blocks <- regmatches(text, gregexpr(pre_pattern, text, perl = TRUE))[[1]]
    for (i in seq_along(pre_blocks)) {
      text <- sub(pre_blocks[i], sprintf("PRE%d", i), text, fixed = TRUE)
    }
  }

  if (mode == "inline_first") {
    for (entry in .JARGON_DICT) {
      m <- regexpr(entry$pattern, text, perl = TRUE)
      if (m > 0) {
        start <- as.integer(m)
        len   <- attr(m, "match.length")
        end   <- start + len - 1L
        tail  <- substr(text, end + 1L, min(end + 40L, nchar(text)))
        # 이미 직후 괄호로 한글 풀이가 있으면 skip
        already <- grepl("^\\s*\\([가-힣].*\\)", tail, perl = TRUE)
        if (!already) {
          matched <- substr(text, start, end)
          repl    <- sprintf("%s (%s)", matched, entry$ko)
          text <- paste0(substr(text, 1L, start - 1L),
                          repl,
                          substr(text, end + 1L, nchar(text)))
        }
      }
    }
  } else if (mode == "footer") {
    found_pairs <- character(0)
    for (entry in .JARGON_DICT) {
      m <- regexpr(entry$pattern, text, perl = TRUE)
      if (m > 0) {
        start <- as.integer(m)
        end   <- start + attr(m, "match.length") - 1L
        label <- substr(text, start, end)
        # 일반화 short label 추출 (e.g., WT-D20260504_001 → WT-D / STR_1715 → STR_)
        short <- if (grepl("^WT-", label)) substr(label, 1, 4)
                  else if (grepl("^STR_", label)) "STR_"
                  else if (grepl("^AX-", label)) "AX-"
                  else if (grepl("^L-", label)) "L-"
                  else if (grepl("^RF-", label)) "RF-"
                  else label
        pair <- sprintf("%s=%s", short, entry$ko)
        if (!pair %in% found_pairs) found_pairs <- c(found_pairs, pair)
      }
    }
    if (length(found_pairs) > 0) {
      footer_str <- paste0("\U0001F4DA 약어: ", paste(found_pairs, collapse = " / "))
      text <- paste(text, footer_str, sep = "\n\n")
    }
  }

  # <pre> 복원
  if (length(pre_blocks) > 0) {
    for (i in seq_along(pre_blocks)) {
      text <- sub(sprintf("PRE%d", i), pre_blocks[i], text, fixed = TRUE)
    }
  }
  text
}

# ─── v7 (2026-07-10 도훈 mandate) — 용어 뜻 사전 (SKILL.md §5.5와 1:1 동기화) ───
# .JARGON_DICT(약어→한글명 변환)와 별개 층위: 한글명/용어 → 쉬운 뜻 + 판정 기준.
# 비전공자 가독 장치 ③: tg_agent_brief()가 최종 본문 스캔 → 등장 용어만 footer 자동 부착.
# 변경 시 SKILL.md §5.5 표 먼저 수정하고 본 list 동기화 (역방향 금지).
# 순서 중요: 구체(긴) 패턴 → 일반(짧은) 패턴. 매치 후 마스킹으로 중첩 재매치 방지.
.METRIC_MEANING <- list(
  list(pattern = "다중검정 t값|PORT_t|portfolio[- ]alpha t|포트폴리오 알파 t",
       term = "다중검정 t값",   meaning = "초과수익이 우연이 아닐 확신도. 2.95 이상이어야 자본 투입 자격"),
  list(pattern = "표본외 유지율|oos_retention",
       term = "표본외 유지율",  meaning = "개발 기간 성과가 새 기간에도 유지되는 비율. 0.7 이상 합격"),
  list(pattern = "표본 외 검증|\\bOOS\\b",
       term = "표본 외 검증",   meaning = "개발에 쓰지 않은 기간으로 치르는 모의고사"),
  list(pattern = "디플레이티드 샤프|\\bDSR\\b",
       term = "디플레이티드 샤프", meaning = "여러 번 시도한 보정을 반영해 깎아서 본 샤프지수"),
  list(pattern = "샤프지수|\\bSR\\b|\\bSharpe\\b",
       term = "샤프지수",       meaning = "감수한 출렁임 대비 수익 효율. 1 이상 양호, 2 이상 우수"),
  list(pattern = "최대낙폭|\\bMDD\\b",
       term = "최대낙폭",       meaning = "고점에서 저점까지 최대 하락률. 작을수록 안전"),
  list(pattern = "연복리수익률|\\bCAGR\\b",
       term = "연복리수익률",   meaning = "매년 평균 몇 %씩 복리로 불었는지"),
  list(pattern = "정보계수 안정성|\\bICIR\\b",
       term = "정보계수 안정성", meaning = "예측 적중의 꾸준함 (정보계수 평균 대비 변동)"),
  list(pattern = "정보계수|\\bIC\\b",
       term = "정보계수",       meaning = "예측 점수와 실제 수익의 들어맞는 정도. 0.05면 유의미"),
  list(pattern = "정보비율|\\bIR\\b",
       term = "정보비율",       meaning = "시장 대비 초과수익의 꾸준함. 0.5 이상 양호"),
  list(pattern = "칼마|\\bCalmar\\b",
       term = "칼마",           meaning = "연수익을 최대낙폭으로 나눈 값. 0.64 이상 합격"),
  list(pattern = "회전율|\\bTurnover\\b|\\bTO\\b",
       term = "회전율",         meaning = "1년에 포트폴리오를 갈아치우는 비율. 높을수록 거래비용 부담"),
  list(pattern = "벤치마크|\\bBM\\b",
       term = "벤치마크",       meaning = "성과 비교 기준이 되는 시장 지수"),
  list(pattern = "백테스팅|\\bBacktest\\b",
       term = "백테스팅",       meaning = "과거 데이터로 전략을 모의 운용해 보는 검증"),
  list(pattern = "미래참조|look[- ]ahead",
       term = "미래참조",       meaning = "그 시점엔 몰랐을 미래 정보가 섞여 성과가 부풀려지는 오류"),
  list(pattern = "\\bPIT\\b|시점 정합",
       term = "PIT",            meaning = "그 시점에 실제로 알 수 있던 정보만 쓰는 원칙 (미래 정보 반입 금지)"),
  list(pattern = "오버레이|\\boverlay\\b",
       term = "오버레이",       meaning = "기존 포트폴리오 위에 얹는 보조 장치 (예: 위험 신호 시 현금 확대)"),
  list(pattern = "알파|\\balpha\\b",
       term = "알파",           meaning = "시장 평균을 넘어서는 초과수익, 또는 그 원천"),
  list(pattern = "팩터",
       term = "팩터",           meaning = "종목을 고르는 기준 신호 (예: 저평가, 이익 개선)"),
  list(pattern = "graduation|자본 졸업",
       term = "graduation",     meaning = "실제 자본을 배정받을 자격 심사 통과"),
  list(pattern = "screen[- _]?tier|스크린 등급",
       term = "screen-tier",    meaning = "신호는 있으나 자본 투입 기준 미달 — 참고용 보관 등급"),
  list(pattern = "admission|\\badmit\\b",
       term = "admission",      meaning = "실제 운용 목록(북) 편입 승인"),
  list(pattern = "운용 북|\\bbook\\b",
       term = "운용 북",        meaning = "실제 자본이 배정된 전략 묶음"),
  list(pattern = "lockbox",
       term = "lockbox",        meaning = "검증 전 결과를 미리 못 보게 봉인하는 장치"),
  list(pattern = "long[- ]only|롱온리",
       term = "long-only",      meaning = "매수만 하는 운용 (공매도 없음)"),
  list(pattern = "워크포워드|walk[- ]forward",
       term = "워크포워드",     meaning = "시간 순서대로 한 구간씩 전진하며 검증하는 방식"),
  list(pattern = "잔차|\\bresidual\\b",
       term = "잔차",           meaning = "시장·공통 요인으로 설명되고 남은 고유 부분"),
  list(pattern = "국면|\\bregime\\b",
       term = "국면",           meaning = "시장의 상태 구분 (예: 강세장 / 위기)"),
  list(pattern = "유니버스",
       term = "유니버스",       meaning = "투자 대상으로 허용된 종목 집합"),
  list(pattern = "교훈 코드|\\bL-[A-Z0-9]",
       term = "교훈 코드",      meaning = "실험에서 얻은 교훈의 일련번호"),
  list(pattern = "공분산",
       term = "공분산",         meaning = "종목들이 함께 움직이는 정도 (분산투자 계산의 재료)"),
  list(pattern = "플라시보|placebo",
       term = "플라시보",       meaning = "가짜 신호로 같은 실험을 돌려 진짜 신호와 구별하는 검사"),
  list(pattern = "t값",
       term = "t값",            meaning = "결과가 우연이 아닐 확신도. 2 이상이면 통계적으로 의미 있음")
)

# tg_build_glossary: v7 자동 용어 풀이 footer 빌더 (SKILL.md §5.5 동작 규칙)
#  - 최종 msg에서 .METRIC_MEANING 패턴 스캔 → 등장 순서대로 수집 (매치 후 마스킹 = 중첩 재매치 방지)
#  - max_bytes 초과분은 등장 순서 뒤쪽부터 절삭 / 대상 없으면 "" 반환 (에러 아님)
tg_build_glossary <- function(msg, max_bytes = .TG_CONFIG$GLOSSARY_MAX_BYTES) {
  if (!is.character(msg) || length(msg) != 1 || !nzchar(msg)) return("")
  work <- msg
  found <- list()
  for (entry in .METRIC_MEANING) {
    m <- regexpr(entry$pattern, work, perl = TRUE)
    if (m > 0) {
      found[[length(found) + 1L]] <- list(term = entry$term,
                                          meaning = entry$meaning,
                                          pos = as.integer(m))
      # 마스킹: 같은 텍스트가 더 일반적인 후속 패턴(예: "t값")에 재매치되는 것 방지
      work <- gsub(entry$pattern, strrep("░", 3L), work, perl = TRUE)
    }
  }
  if (length(found) == 0) return("")
  ord <- order(vapply(found, function(x) x$pos, integer(1)))
  header <- "\U0001F4D6 <b>용어 풀이</b>"
  out <- header
  for (i in ord) {
    line <- sprintf("  • %s = %s", found[[i]]$term, found[[i]]$meaning)
    cand <- paste(out, line, sep = "\n")
    if (nchar(cand, type = "bytes") > max_bytes) break
    out <- cand
  }
  if (identical(out, header)) return("")   # 예산 내 항목 0개면 미부착
  out
}

# tg_text_smart_break: SKILL.md §2 원칙 6 — 개조식 자동 줄바꿈
# 마침표/감탄/물음표 + space, 한국어 종결어미, " / ", " → ", "; " 분리.
# <pre> 블록 보존.
tg_text_smart_break <- function(text) {
  if (!is.character(text) || length(text) != 1 || !nzchar(text)) return(text)

  pre_pattern <- "<pre>[\\s\\S]*?</pre>"
  pre_locs <- gregexpr(pre_pattern, text, perl = TRUE)[[1]]
  pre_blocks <- character(0)
  if (pre_locs[1] != -1) {
    pre_blocks <- regmatches(text, gregexpr(pre_pattern, text, perl = TRUE))[[1]]
    for (i in seq_along(pre_blocks)) {
      text <- sub(pre_blocks[i], sprintf("PRE%d", i), text, fixed = TRUE)
    }
  }

  # 1) 마침표/감탄/물음표 + space + 비공백 → \n (한글/숫자/영문 통합)
  text <- gsub("([.!?]) +(?=\\S)", "\\1\n", text, perl = TRUE)
  # 2) " / " → "\n  • " (개조식 bullet)
  text <- gsub(" / ", "\n  • ", text, fixed = TRUE)
  # 3) " → " → "\n  → "
  text <- gsub(" → ", "\n  → ", text, fixed = TRUE)
  # 4) "; " (세미콜론) → \n
  text <- gsub("; +", "\n", text, perl = TRUE)

  # <pre> 복원
  if (length(pre_blocks) > 0) {
    for (i in seq_along(pre_blocks)) {
      text <- sub(sprintf("PRE%d", i), pre_blocks[i], text, fixed = TRUE)
    }
  }
  text
}

# tg_format_summary: summary section type 단일 helper (1줄 헤드라인)
tg_format_summary <- function(text, emoji = "\U0001F4CC") {
  if (!is.character(text) || length(text) != 1) stop("[tg_format_summary] single string required")
  n <- nchar(text)
  if (n < .TG_CONFIG$SUMMARY_MIN || n > .TG_CONFIG$SUMMARY_MAX) {
    stop(sprintf("[tg_format_summary] body must be [%d, %d] chars (got %d). 1줄 헤드라인용.",
                  .TG_CONFIG$SUMMARY_MIN, .TG_CONFIG$SUMMARY_MAX, n))
  }
  sprintf("%s <b>%s</b>", emoji, tg_html_escape(text))
}

# ── v6.6 (2026-05-27) — Quant 고유명사 whitelist 확장 (도훈 mandate) ──────────
# 퀀트 리서치 자주 쓰는 영어 고유명사 면제 list. bullet + kv key 양쪽 적용.
.QUANT_WHITELIST <- c(
  # 머신러닝 모델 (기존 v6.5)
  "LightGBM", "XGBoost", "CatBoost", "Ridge", "LASSO", "ElasticNet", "Ensemble",
  "RandomForest", "GBT", "NGBoost", "RNN", "LSTM", "GRU", "CNN", "Transformer",
  "BERT", "GPT", "MLP", "DNN",
  # 분포 / 시계열 모델
  "Hansen", "Skewed-t", "Skew-t", "Cauchy", "GMM", "MoG", "Mixture",
  "Bayesian", "MCMC", "TPE", "Optuna", "ACI", "EnbPI", "CQR", "SCP", "ECDF",
  "ARIMA", "ARMA", "ARMAX", "VAR", "VECM", "GBM", "BOCPD", "Markov", "HMM",
  "GARCH", "EGARCH", "EWMA", "Kalman", "PCA", "FA", "ICA", "EM",
  # 분포 검정
  "Kupiec", "Christoffersen", "McNeil-Frey", "Berkowitz", "Diebold-Mariano",
  "DM-test", "KS-test", "JB-test", "ADF", "KPSS", "Ljung-Box",
  # 거리/메트릭
  "Wasserstein", "Hellinger", "Bhattacharyya", "KL", "Mahalanobis",
  "CRPS", "NLL", "ELBO", "RMSE", "MAE", "MAPE", "R2", "AUC", "AUROC", "ROC",
  "PR-AUC", "F1",
  # 운용 메트릭
  "Sharpe", "Sortino", "Calmar", "Sterling", "Treynor", "Jensen", "Omega",
  "Newey-West", "Hansen-Hodrick", "Harvey-t", "Harvey", "Fama-MacBeth",
  "Diebold-Mariano-West", "MDD", "IC", "ICIR", "DSR", "TE", "IR",
  "VaR", "ES", "CVaR", "CAGR", "CTR", "TO", "PnL", "NAV", "AUM",
  # 최적화
  "HRP", "MVO", "ERC", "RP", "TWAP", "VWAP", "POV", "BL", "Black-Litterman",
  "Kelly", "Pareto", "Markowitz", "Tobin",
  # 알파 / 팩터 (학술)
  "FF3", "FF4", "FF5", "Carhart", "AQR", "SMB", "HML", "UMD", "RMW", "CMA",
  "BAB", "MOM", "REV", "LIQ", "IDIO", "EP", "BP", "GP", "FP", "ROE", "ROA",
  "ROIC", "EBIT", "EBITDA", "NOPAT", "FCFE", "FCFF", "FCF", "DCF", "WACC",
  "CAPM", "APT", "Beta", "SUE", "Novy-Marx", "Frazzini-Pedersen", "Piotroski",
  "Fama-French", "Carhart-1997", "Asness", "Moskowitz",
  # 시장 / 자산
  "KOSPI", "KOSPI200", "KOSDAQ", "KOSDAQ150", "SP500", "NASDAQ", "DJIA",
  "FTSE", "Russell", "MSCI", "STOXX", "ETF", "REIT", "ADR", "IPO",
  "KRW", "USD", "JPY", "EUR", "GBP", "CNY", "VIX",
  # 데이터/통계
  "PIT", "OOS", "IS", "WF", "CV", "Backtest", "EW",
  "JSON", "YAML", "CSV", "API", "SQL", "GPU", "CPU", "RAM",
  "ML", "NN", "RL", "AI",
  # 통계 분포/특성
  "Skew", "Kurtosis", "Quantile", "CDF", "PDF", "QQ", "Hessian",
  # Agent / WT system
  "Q-Lead", "Q_Lead", "Alpha", "Risk", "Optimizer", "Forge", "Judge",
  "Governor", "Scout", "Execution", "Monitoring", "Architect", "Codex",
  # 학술 저널
  "JF", "JFE", "JFQA", "RFS", "JPM", "FAJ", "RAS", "QJE", "AER", "JBF",
  "RAJ", "JFM", "JoF",
  # Macro / regime
  "MRS", "ESBR", "ADV", "NFCI", "FRED", "FOMC", "ECB", "BOJ", "BOK",
  # 기타 통상
  "TDC", "ROC", "PnL"
)
.QUANT_WHITELIST_PATTERN <- paste0(
  "\\b(?:",
  paste(gsub("-", "[-]?", .QUANT_WHITELIST), collapse = "|"),
  ")\\b"
)

tg_agent_brief <- function(agent,
                             title,
                             sections = list(),
                             as_of = format(Sys.Date(), "%Y-%m-%d"),
                             charts = NULL,
                             footer = NULL,
                             emoji_min = .TG_CONFIG$EMOJI_MIN,
                             dry_run = FALSE,
                             force = FALSE,
                             lock_scope = NULL,
                             # ─── v6 SOT (2026-05-07) — SKILL.md §5/§6 동기화 ───
                             decode_jargon = TRUE,
                             decode_mode = "inline_first",  # inline_first / footer / off
                             smart_break = TRUE,
                             # 페이퍼 적재 브리핑 전용 요건 완화 (도훈 mandate 2026-06-18):
                             #   bullet 길이(BULLET_ITEM_MAX)·영어 약어 가드·kv 값 길이·kv 영어비율 면제
                             #   (영어 논문 제목 등 고유 콘텐츠 허용). 기본 FALSE = 기존 한글 규율·길이 제한 유지
                             #   (타 에이전트 영향 0). 구조 안전망(4096 byte 가드·skeleton 가드)은 relaxed여도 유지.
                             relaxed = FALSE,
                             # v7 (2026-07-10 도훈 mandate) — 비전공자 가독 장치 ③:
                             #   본문 등장 전문용어 자동 스캔 → "📖 용어 풀이" footer 부착 (.METRIC_MEANING, SKILL.md §5.5).
                             #   기본 TRUE. FALSE는 내부 디버그 발송만.
                             glossary = TRUE) {
  if (!isTRUE(dry_run) && .tg_serial_enabled() && !.tg_lock_held()) {
    return(tg_with_serial_lock(
      scope = sprintf("tg_agent_brief_%s", agent),
      owner = sprintf("%s · %s", agent, substr(title, 1L, 80L)),
      tg_agent_brief(
        agent = agent,
        title = title,
        sections = sections,
        as_of = as_of,
        charts = charts,
        footer = footer,
        emoji_min = emoji_min,
        dry_run = dry_run,
        force = force,
        lock_scope = lock_scope,
        decode_jargon = decode_jargon,
        decode_mode = decode_mode,
        smart_break = smart_break,
        relaxed = relaxed,
        glossary = glossary
      )
    ))
  }

  # ── 0. Single-Dispatch lock (2026-04-24 v2, 물리적 강제) ─────────────────────
  # 같은 agent + title prefix 중복 호출 차단. Forge 2번 발송 사례 방지.
  # lock_scope가 NULL이면 "agent + title 첫 40자"로 scope 생성.
  # force=TRUE로 override 가능 (수동 재전송 허용).
  if (!isTRUE(dry_run)) {
    scope_key <- if (!is.null(lock_scope)) lock_scope else {
      # Extract WT-id or title prefix
      # ★perl=TRUE 필수 (금칙 ⑥, 02_Infrastructure/docs/rules/r-portability.md).
      #   Windows TRE 는 매치 위치를 UTF-16 코드유닛으로 돌려주는데 regmatches 는
      #   코드포인트로 자른다 → title 의 WT-id **앞**에 이모지가 N개 있으면 추출 창이
      #   N칸 밀려 lock scope_key 가 열화한다(실측: WT-D20260802_012 → T-D20260802_012
      #   → 0802_012 R43). 중복 발송 차단이 조용히 무력해지는 형태다.
      #   현재는 **잠복이지 발화 아님**: stage_artifacts + qepm/mailbox 의 title="..." 452건
      #   중 non-BMP 포함은 1건뿐이고(WT-D20260426_004 … R2 Final ⚖️🔒) 그마저 이모지가
      #   WT-id **뒤**라 선행 non-BMP = 0 (2026-08-02 실측). 머리말에 이모지를 넣는 관행이
      #   title 로 번지는 순간 발화하므로 한 토큰으로 미리 닫는다.
      wt_match <- regmatches(title, regexpr("WT-[DP]?[0-9]{8}_?[0-9]*", title, perl = TRUE))
      if (length(wt_match) > 0 && nzchar(wt_match[1])) {
        sprintf("%s_%s", agent, wt_match[1])
      } else {
        sprintf("%s_%s", agent,
                 gsub("[^A-Za-z0-9]", "_", substr(title, 1, 40)))
      }
    }
    # tg lock: /tmp(Windows는 C:/tmp로 해석·TTL 없어 영구잔존) → 프로젝트 .cache/tg_locks + TTL.
    #   run_id 고유화로 scope 충돌은 이미 해결됐고, 본 변경은 경로 크로스플랫폼화 + stale 자동 무시(위생). 2026-06-05.
    #   2026-07-25: 같은 PROJECT_ROOT 오염 취약점의 두 번째 실례였다(위 .tg_lock_root() 주석 참조).
    #   검증된 루트 해석기를 재사용한다 — 지역 변수명이 그 함수를 가리지 않도록 이름을 분리.
    .tg_lock_base <- .tg_lock_root()
    .tg_lock_dir  <- file.path(.tg_lock_base, ".cache", "tg_locks")
    dir.create(.tg_lock_dir, recursive = TRUE, showWarnings = FALSE)
    lock_file <- file.path(.tg_lock_dir, sprintf("qvest_tg_lock_%s.lock", scope_key))
    .TG_LOCK_TTL_SEC <- 1800L   # 30분 — 이보다 오래된 lock은 stale로 간주, 차단하지 않음(영구잔존 방지)

    if (file.exists(lock_file) && !isTRUE(force)) {
      .lock_age <- tryCatch(as.numeric(difftime(Sys.time(), file.info(lock_file)$mtime, units = "secs")),
                            error = function(e) Inf)
      if (is.finite(.lock_age) && .lock_age < .TG_LOCK_TTL_SEC) {
        first_call <- tryCatch(readLines(lock_file, n = 2),
                                error = function(e) c("unknown", "unknown"))
        warn_msg <- sprintf("[tg_agent_brief] BLOCKED duplicate dispatch. agent=%s scope=%s first_call=%s (age %.0fs < %ds). Use force=TRUE to override.",
                             agent, scope_key, first_call[1], .lock_age, .TG_LOCK_TTL_SEC)
        message(warn_msg)
        log_f <- file.path(.tg_lock_dir, "_duplicate_dispatch.log")
        tryCatch(cat(sprintf("%s %s\n", format(Sys.time()), warn_msg),
                      file = log_f, append = TRUE),
                  error = function(e) NULL)
        return(invisible(list(ok = FALSE, error = "DUPLICATE_DISPATCH_BLOCKED",
                               scope = scope_key, first_call = first_call[1])))
      }
      # stale lock (age >= TTL) — 무시하고 진행 (§5.5에서 새 lock으로 덮어씀)
    }
  }

  # ── 1. Agent tag + header ────────────────────────────────────────────────────
  if (!agent %in% names(.AGENT_EMOJI_MAP)) {
    stop(sprintf("[tg_agent_brief] Unknown agent '%s'. Valid: %s",
                 agent, paste(names(.AGENT_EMOJI_MAP), collapse = ", ")))
  }
  agent_emoji <- .AGENT_EMOJI_MAP[[agent]]

  # v6 SOT 헤더 단순화 — `🎯 Q-Lead · 제목\n📅 2026-XX-XX`
  hdr <- sprintf("%s <b>%s · %s</b>\n\U0001F4C5 %s",
                 agent_emoji, agent, title, as_of)

  # ── 2. 섹션 렌더 ─────────────────────────────────────────────────────────────
  # 이모지 자동 추천: emoji 미지정 시 heading keyword 기반 default 선택
  .guess_section_emoji <- function(heading_str) {
    if (is.null(heading_str) || !nzchar(heading_str)) return("📊")
    h <- tolower(heading_str)
    keyword_map <- list(
      "risk|리스크|flag" = "🚩",
      "challenge|반론|challenge" = "⚔️",
      "stress|위기|regime|crisis" = "🌪️",
      "alert|경보|alarm" = "🚨",
      "insight|핵심|발견|finding" = "💡",
      "method|방법|비교|covariance|estimator" = "🔬",
      "hedge|overlay|beta|β" = "🛡️",
      "config|설정|제약|constraint|option" = "🎛️",
      "stress|regime|국면" = "🌪️",
      "performance|성과|ir|sr|cagr|mdd" = "📈",
      "integration|통합|mapping|매핑" = "🔗",
      "new|latest|최신|supplement" = "✨",
      "reference|참조|논문|paper" = "📚",
      "shortlist|ranking|top|순위" = "🏆",
      "test|검증|validation" = "🧪",
      "audit|검사|verify" = "🛠️",
      "next|action|계획" = "➡️",
      "compare|vs|비교" = "🔍",
      "gate|verdict|판정" = "⚖️",
      "lockbox|oos|seal" = "🔒",
      "diagnosis|진단|diagnostic" = "📊"
    )
    for (pattern in names(keyword_map)) {
      if (grepl(pattern, h, perl = TRUE)) return(keyword_map[[pattern]])
    }
    "📊"  # default: metrics
  }

  section_blocks <- vapply(sections, function(s) {
    heading <- s$heading %||% ""
    emoji <- s$emoji %||% .guess_section_emoji(heading)
    type <- s$type %||% "text"
    head_line <- if (nzchar(heading)) sprintf("%s <b>%s</b>", emoji, heading) else ""

    body <- switch(
      type,
      "table" = {
        if (!is.data.frame(s$df)) stop("[tg_agent_brief] 'table' section requires df (data.frame)")
        if (nrow(s$df) < .TG_CONFIG$TABLE_NROW_MIN) stop(sprintf("[tg_agent_brief] 'table' section heading='%s' requires nrow >= %d (got %d). 1행 표는 모바일에서 붕괴.",
                                            heading, .TG_CONFIG$TABLE_NROW_MIN, nrow(s$df)))
        if (ncol(s$df) < 2L) stop(sprintf("[tg_agent_brief] 'table' section heading='%s' requires ncol >= 2 (got %d). 1열 = bullet 권장 (type='bullet').",
                                            heading, ncol(s$df)))
        max_col <- s$max_col_width %||% 18L
        tbl <- tg_format_table(s$df, max_col_width = as.integer(max_col),
                                auto_escape = TRUE)
        notes <- s$notes
        if (!is.null(notes) && length(notes) > 0) {
          bullets <- paste0("  • ", tg_html_escape(notes), collapse = "\n")
          paste(tbl, bullets, sep = "\n")
        } else tbl
      },
      "text" = {
        # plain text — auto_sanitize이 <>& 처리.
        body_str <- as.character(s$body %||% "")
        n_chars <- nchar(body_str)
        if (n_chars < .TG_CONFIG$TEXT_MIN) {
          stop(sprintf("[tg_agent_brief] 'text' section heading='%s' requires body >= %d chars (got %d). 짧으면 'summary' / 'bullet' / 'kv' 사용.",
                        heading, .TG_CONFIG$TEXT_MIN, n_chars))
        }
        # v6.1 SOT — TEXT_MAX 강제 (모바일 짤림 방지)
        if (n_chars > .TG_CONFIG$TEXT_MAX) {
          stop(sprintf("[tg_agent_brief] 'text' section heading='%s' body %d chars > %d max. 분할: bullet (≤%d 자/항목) 또는 별도 섹션.",
                        heading, n_chars, .TG_CONFIG$TEXT_MAX, .TG_CONFIG$BULLET_ITEM_MAX))
        }
        # v6 SOT — tg_text_smart_break() 통합 줄바꿈
        if (isTRUE(smart_break)) body_str <- tg_text_smart_break(body_str)
        body_str
      },
      "summary" = {
        # v6 SOT 신규 — 1줄 헤드라인 (tg_format_summary helper)
        body_str <- as.character(s$body %||% "")
        emoji_lead <- s$emoji %||% "\U0001F4CC"  # 📌
        tg_format_summary(body_str, emoji = emoji_lead)
      },
      "bullet" = {
        items <- s$items %||% character(0)
        if (length(items) < .TG_CONFIG$BULLET_MIN) {
          stop(sprintf("[tg_agent_brief] 'bullet' section heading='%s' requires items >= %d (got %d). 1개면 'summary' / 'text' 사용.",
                        heading, .TG_CONFIG$BULLET_MIN, length(items)))
        }
        item_chars <- as.character(items)
        # relaxed=TRUE (페이퍼 적재 브리핑) → bullet 길이·영어약어 가드 면제 (영어 논문 제목 허용).
        if (!isTRUE(relaxed)) {
          # v6.1 SOT — BULLET_ITEM_MAX 강제 (모바일 한 줄)
          too_long <- which(nchar(item_chars) > .TG_CONFIG$BULLET_ITEM_MAX)
          if (length(too_long) > 0) {
            stop(sprintf("[tg_agent_brief] 'bullet' section heading='%s' items %s > %d 자 max. 분할 또는 축약 의무.",
                          heading, paste(too_long, collapse=","), .TG_CONFIG$BULLET_ITEM_MAX))
          }
          # v6.3 SOT — bullet 안 영어 약어 라벨 금지 (예: AX-007, RF-A3, STR_055, C13)
          # v6.5 (2026-05-15) — 통상 영어 표기 OK
          # v6.6 (2026-05-27) — 도훈 mandate: quant 고유명사 whitelist 확장 (.QUANT_WHITELIST)
          abbrev_pattern <- "\\b[A-Z]{2,5}[-_]?[A-Z0-9]{1,5}\\b"
          exempt_pattern <- paste0(
            "WT[-_][DPSH]?[0-9_]{4,15}|WT_[0-9]+",
            # 학술 저자-연도 (e.g., "Asness 2013", "Frazzini-Pedersen 2014")
            "|[A-Z][a-z]{2,}(?:[- ][A-Z][a-z]+)*\\s+(?:19|20)[0-9]{2}",
            # Quant 고유명사 whitelist (v6.6)
            "|", .QUANT_WHITELIST_PATTERN
          )
          bad_idx <- which(vapply(item_chars, function(it) {
            # 1) 면제 패턴 먼저 마스킹
            masked <- gsub(exempt_pattern, "_EXEMPT_", it, perl = TRUE)
            # 2) 잔여에서 약어 검사
            matches <- regmatches(masked, gregexpr(abbrev_pattern, masked))[[1]]
            length(matches) >= 2
          }, logical(1)))
          if (length(bad_idx) > 0) {
            stop(sprintf("[tg_agent_brief] 'bullet' section heading='%s' items %s 영어 약어 ≥2건 (예: AX-/RF-/STR_/C13). v6.3 SOT: 한글 풀어 쓰기 의무. 학술 인용/WT 식별자/agent name 면제.",
                          heading, paste(bad_idx, collapse=",")))
          }
        }
        # relaxed(페이퍼 적재 브리핑) → 항목 사이 빈 줄 삽입(긴 영어 제목 모바일 가독, 도훈 2026-06-18). 일반은 단일 줄바꿈.
        # [2026-07-18 도훈] caller가 넣은 <b></b> 강조는 escape 후 복원 (그 외 <,>는 안전하게 escape 유지)
        .items_esc <- tg_html_escape(item_chars)
        .items_esc <- gsub("&lt;b&gt;", "<b>", .items_esc, fixed = TRUE)
        .items_esc <- gsub("&lt;/b&gt;", "</b>", .items_esc, fixed = TRUE)
        paste0("  • ", .items_esc, collapse = if (isTRUE(relaxed)) "\n\n" else "\n")
      },
      "kv" = {
        kv <- s$kv
        if (!is.list(kv) || is.null(names(kv)) || any(!nzchar(names(kv)))) {
          stop(sprintf("[tg_agent_brief] 'kv' section heading='%s' requires named list (kv = list(key1='val1', ...)).",
                        heading))
        }
        if (length(kv) < .TG_CONFIG$KV_MIN) {
          stop(sprintf("[tg_agent_brief] 'kv' section heading='%s' requires length(kv) >= %d (got %d).",
                        heading, .TG_CONFIG$KV_MIN, length(kv)))
        }
        kv_vals <- vapply(kv, as.character, character(1))
        # relaxed=TRUE (페이퍼 적재 브리핑) → kv 값 길이·키 영어비율 가드 면제.
        if (!isTRUE(relaxed)) {
          # v6.1 SOT — KV_VALUE_MAX 강제
          too_long <- which(nchar(kv_vals) > .TG_CONFIG$KV_VALUE_MAX)
          if (length(too_long) > 0) {
            stop(sprintf("[tg_agent_brief] 'kv' section heading='%s' values %s > %d 자 max. 축약 의무.",
                          heading, paste(names(kv)[too_long], collapse=","), .TG_CONFIG$KV_VALUE_MAX))
          }
          # v6.3 SOT (2026-05-08) — kv key 한글 비율 강제
          # v6.5 (2026-05-15) — 통상 quant 용어 면제
          # v6.6 (2026-05-27) — 도훈 mandate: quant 고유명사 whitelist 확장 (.QUANT_WHITELIST)
          kv_keys <- names(kv)
          academic_cite_pattern <- "[A-Z][a-z]{2,}(?:[- ][A-Z][a-z]+)*\\s+(?:19|20)[0-9]{2}"
          ascii_heavy <- vapply(kv_keys, function(k) {
            # 학술 인용 + quant whitelist 매칭 시 마스킹 후 비율 측정
            masked <- gsub(academic_cite_pattern, "", k, perl = TRUE)
            masked <- gsub(.QUANT_WHITELIST_PATTERN, "", masked, perl = TRUE)
            n_total <- nchar(masked)
            n_ascii_alpha <- length(regmatches(masked, gregexpr("[A-Za-z]", masked))[[1]])
            if (n_total == 0) return(FALSE)
            # v6.6 (2026-05-27) — 도훈 mandate: 임계 0.4 → 0.6 완화 (고유명사 OK)
            (n_ascii_alpha / n_total) > 0.6
          }, logical(1))
          if (any(ascii_heavy)) {
            stop(sprintf("[tg_agent_brief] 'kv' section heading='%s' keys %s 영어 비율 > 40%%. v6.3 SOT: 한글 정통 용어 의무 (예: '샤프지수' / '정보계수' / '회전율'). 학술 인용 (Asness 2013 / Frazzini-Pedersen 2014)은 면제.",
                          heading, paste(kv_keys[ascii_heavy], collapse=" / ")))
          }
        }
        kv_lines <- vapply(seq_along(kv), function(i) {
          sprintf("  • <b>%s</b>: %s",
                  tg_html_escape(names(kv)[i]),
                  tg_html_escape(kv_vals[i]))
        }, character(1))
        paste(kv_lines, collapse = "\n")
      },
      "code" = {
        code_str <- as.character(s$body %||% "")
        if (nchar(code_str) < .TG_CONFIG$CODE_MIN) {
          stop(sprintf("[tg_agent_brief] 'code' section heading='%s' requires body >= %d chars (got %d).",
                        heading, .TG_CONFIG$CODE_MIN, nchar(code_str)))
        }
        paste0("<pre>", tg_html_escape(code_str), "</pre>")
      },
      stop(sprintf("[tg_agent_brief] Unknown section type '%s'. v6 SOT 6종: summary / text / bullet / kv / table / code.", type))
    )
    if (nzchar(head_line)) paste(head_line, body, sep = "\n") else body
  }, character(1))

  # ── 3. Footer ────────────────────────────────────────────────────────────────
  parts <- c(hdr, section_blocks)
  if (!is.null(footer) && nzchar(footer)) parts <- c(parts, footer)

  msg <- paste(parts, collapse = "\n\n")

  # ── 3.5. v6 SOT 약어 풀이 (default inline_first, 첫 등장 1회) ─────────────────
  if (isTRUE(decode_jargon) && decode_mode != "off") {
    msg <- tg_decode_jargon(msg, mode = decode_mode)
  }

  # ── 3.6. v7 자동 용어 풀이 footer (SKILL.md §5.5 — 비전공자 가독, 도훈 mandate 2026-07-10) ──
  # 메시지 4096 byte 근접 시 glossary 우선 절삭 (본문 보호).
  if (isTRUE(glossary)) {
    .base_bytes <- nchar(msg, type = "bytes")
    .gl_budget  <- min(.TG_CONFIG$GLOSSARY_MAX_BYTES, max(0L, 3950L - .base_bytes))
    if (.gl_budget >= 60L) {
      .gl <- tg_build_glossary(msg, max_bytes = .gl_budget)
      if (nzchar(.gl)) msg <- paste(msg, .gl, sep = "\n\n")
    }
  }

  # v7 원칙 8-② warn-level — "쉬운 설명" 섹션 부재 경고 (기존 자동 caller 비파괴, stop 아님)
  .has_plain_section <- any(vapply(sections, function(s)
    grepl("쉬운", s$heading %||% "", fixed = TRUE), logical(1)))
  if (!.has_plain_section && !isTRUE(relaxed)) {
    message(sprintf("[tg_agent_brief] v7 WARN agent=%s: '쉬운 설명' 섹션 없음 — SKILL.md 원칙 8-② (에이전트 브리핑은 시도/방법/결과/의미 평문 bullet 의무, warn-level).", agent))
  }

  # ── 4. Width/bytes 사전 체크 (Telegram 4096 bytes 제한) ──────────────────────
  msg_bytes <- nchar(msg, type = "bytes")
  if (msg_bytes > 4000) {
    warning(sprintf("[tg_agent_brief] WARN msg %d bytes — close to 4096 Telegram limit. Consider shorter sections.",
                    msg_bytes))
  }

  # ── 4.5. Empty / Skeleton guard (v6 SOT, .TG_CONFIG 참조) ─────────────────
  # 사례: Pilot 6 Alpha 115 bytes / Risk 475 bytes / WT-005 Optimizer 477 bytes (v4 1200 상향).
  # v6 (2026-05-07): MIN_BYTES 1200→400, MIN_SECTIONS 4→2 (간결 허용). force=TRUE 우회.
  # SKILL.md §3와 .TG_CONFIG 1:1 동기화 의무.
  n_sections_nonempty <- sum(vapply(sections, function(s) {
    if (length(s) == 0) return(FALSE)
    body <- s$body %||% ""
    items <- s$items %||% character(0)
    kv <- s$kv
    type <- s$type %||% "text"
    has_df <- is.data.frame(s$df) && nrow(s$df) >= .TG_CONFIG$TABLE_NROW_MIN && ncol(s$df) >= 2L
    has_body_text <- type == "text" && is.character(body) &&
                      length(body) == 1 && nchar(body) >= .TG_CONFIG$TEXT_MIN
    has_body_summary <- type == "summary" && is.character(body) &&
                        length(body) == 1 && nchar(body) >= .TG_CONFIG$SUMMARY_MIN
    has_body_code <- type == "code" && is.character(body) &&
                      length(body) == 1 && nchar(body) >= .TG_CONFIG$CODE_MIN
    has_items <- length(items) >= .TG_CONFIG$BULLET_MIN
    has_kv <- is.list(kv) && length(kv) >= .TG_CONFIG$KV_MIN && !is.null(names(kv))
    has_df || has_body_text || has_body_summary || has_body_code || has_items || has_kv
  }, logical(1)))

  if (msg_bytes < .TG_CONFIG$MIN_BYTES || n_sections_nonempty < .TG_CONFIG$MIN_SECTIONS) {
    err_msg <- sprintf("[tg_agent_brief] BLOCKED skeleton brief. agent=%s bytes=%d (min %d) nonempty_sections=%d (min %d). v6 SOT: summary(>=%d 자) / text(>=%d 자) / bullet(>=%d) / kv(>=%d) / table(nrow>=%d,ncol>=2) 중 %d개 이상.",
                        agent, msg_bytes, .TG_CONFIG$MIN_BYTES, n_sections_nonempty, .TG_CONFIG$MIN_SECTIONS,
                        .TG_CONFIG$SUMMARY_MIN, .TG_CONFIG$TEXT_MIN, .TG_CONFIG$BULLET_MIN, .TG_CONFIG$KV_MIN,
                        .TG_CONFIG$TABLE_NROW_MIN, .TG_CONFIG$MIN_SECTIONS)
    log_f <- "/tmp/qvest_tg_skeleton_warn.log"
    tryCatch(cat(sprintf("%s %s\n%s\n---\n", format(Sys.time()), err_msg, msg),
                  file = log_f, append = TRUE),
              error = function(e) NULL)
    if (!isTRUE(force)) {
      stop(err_msg)
    } else {
      message(sprintf("[tg_agent_brief] WARN force=TRUE override: %s", err_msg))
    }
  }

  if (isTRUE(dry_run)) {
    cat("=== dry_run output (", msg_bytes, "bytes) ===\n", sep = "")
    cat(msg, "\n")
    return(invisible(list(ok = TRUE, bytes = msg_bytes, dry_run = TRUE, msg = msg)))
  }

  # ── 5. 발송 (tg_send_rich auto_sanitize) ─────────────────────────────────────
  result <- tryCatch({
    tg_send_rich(msg, emoji_min = emoji_min)
    list(ok = TRUE, bytes = msg_bytes, error = NULL)
  }, error = function(e) {
    log_f <- "/tmp/qvest_tg_brief.log"
    tryCatch(cat(sprintf("%s [tg_agent_brief] %s ERR %s\n",
                          format(Sys.time()), agent, e$message),
                  file = log_f, append = TRUE),
              error = function(e2) NULL)
    list(ok = FALSE, bytes = msg_bytes, error = conditionMessage(e))
  })

  # ── 5.5. 발송 성공 시 lock 파일 + full body 로깅 (깨짐 사후 추적) ────────────
  if (isTRUE(result$ok) && exists("lock_file")) {
    tryCatch({
      writeLines(c(format(Sys.time()),
                    sprintf("bytes=%d", msg_bytes),
                    sprintf("agent=%s", agent),
                    sprintf("title=%s", title)),
                  lock_file)
    }, error = function(e) NULL)

    # Full body 아카이브 (깨짐 발생 시 /tmp/qvest_tg_body_ARCHIVE/ 경유 조회 가능)
    archive_dir <- "/tmp/qvest_tg_body_ARCHIVE"
    tryCatch({
      if (!dir.exists(archive_dir)) dir.create(archive_dir, recursive = TRUE)
      scope_safe <- gsub("[^A-Za-z0-9_-]", "_",
                          if (exists("scope_key")) scope_key else "unknown")
      archive_file <- file.path(archive_dir,
                                  sprintf("%s_%s.html",
                                          format(Sys.time(), "%Y%m%d_%H%M%S"),
                                          scope_safe))
      writeLines(msg, archive_file)
    }, error = function(e) NULL)
  }

  # ── 6. Charts (text 발송 후 이어서) ──────────────────────────────────────────
  if (!is.null(charts) && length(charts) > 0) {
    for (chart in charts) {
      if (file.exists(chart)) {
        cap <- sprintf("[%s] %s", agent, basename(chart))
        tg_send_photo(chart, caption = cap)
      }
    }
  }

  cat(sprintf("[tg_agent_brief] %s · %d bytes · ok=%s\n",
              agent, msg_bytes, result$ok))
  invisible(result)
}

# ─── Photo / Document send ────────────────────────────────────────────────────
tg_send_photo <- function(image_path, caption = "", parse_mode = "") {
  if (.tg_serial_enabled() && !.tg_lock_held()) {
    return(tg_with_serial_lock(
      scope = "tg_send_photo",
      owner = sprintf("photo:%s", basename(image_path %||% "")),
      tg_send_photo(image_path, caption = caption, parse_mode = parse_mode)
    ))
  }
  if (!file.exists(image_path)) {
    cat(sprintf("[tg] Photo not found: %s\n", image_path))
    return(invisible(NULL))
  }
  tryCatch({
    resp <- POST(
      paste0(.TG_BASE, "/sendPhoto"),
      body = list(
        chat_id    = .TG_CHAT_ID,
        photo      = upload_file(image_path),
        caption    = caption,
        parse_mode = parse_mode
      ),
      encode = "multipart"
    )
    if (http_error(resp)) {
      cat(sprintf("[tg] Photo failed: %s\n", content(resp, "text", encoding = "UTF-8")))
    }
    invisible(resp)
  }, error = function(e) cat(sprintf("[tg] Photo error: %s\n", e$message)))
}

tg_send_document <- function(file_path, caption = "") {
  if (.tg_serial_enabled() && !.tg_lock_held()) {
    return(tg_with_serial_lock(
      scope = "tg_send_document",
      owner = sprintf("document:%s", basename(file_path %||% "")),
      tg_send_document(file_path, caption = caption)
    ))
  }
  if (!file.exists(file_path)) return(invisible(NULL))
  tryCatch({
    resp <- POST(
      paste0(.TG_BASE, "/sendDocument"),
      body = list(
        chat_id  = .TG_CHAT_ID,
        document = upload_file(file_path),
        caption  = caption
      ),
      encode = "multipart"
    )
    invisible(resp)
  }, error = function(e) cat(sprintf("[tg] Doc error: %s\n", e$message)))
}

# ─── Strategy result (텍스트 + 점수 세부) ─────────────────────────────────────
tg_strategy_result <- function(strategy_name, hurdle_result) {
  verdict_str <- if (isTRUE(hurdle_result$pass)) "✅ PASS" else "❌ FAIL"
  # Use [["score"]] to avoid R partial matching ($score → $score_breakdown)
  score  <- as.numeric(hurdle_result[["score"]] %||% hurdle_result[["total_score"]] %||% 0)
  v      <- hurdle_result[["verdict"]] %||% hurdle_result
  m      <- v[["metrics"]] %||% list()
  sb     <- v[["score_breakdown"]] %||% list()

  .n <- function(x) { val <- as.numeric(x); if (length(val) == 0 || is.na(val[1])) 0 else val[1] }

  # Hard fail 사유
  hard_fail_str <- if (isTRUE(v[["hard_fail"]])) {
    fr <- v[["fail_reasons"]]
    if (is.list(fr)) fr <- unlist(fr)
    sprintf("\n⛔ Hard Fail: %s", paste(fr, collapse = " | "))
  } else ""

  # ── 점수 세부 (score_breakdown 있을 때만) ──
  score_detail_str <- ""
  if (length(sb) > 0) {
    # 라벨 정의
    labels <- list(
      sharpe      = list(label = "SR",      max = 20),
      ir          = list(label = "IR",      max = 15),
      cagr        = list(label = "CAGR",    max = 15),
      rolling     = list(label = "Roll",    max = 15),
      stress      = list(label = "Stress",  max = 10),
      mdd         = list(label = "MDD",     max = 10),
      calmar      = list(label = "Calmar",  max = 10),
      params      = list(label = "Params",  max = 5),
      alpha_trend  = list(label = "Trend",   max = 10),  # [-10 ~ +10]
      oos          = list(label = "OOS",     max = 8),   # [-8 ~ +8]
      ic_stability = list(label = "ICSt",   max = 6)    # [-6 ~ +6]
    )
    # 효율(score/max) 기준 정렬해서 강점 2개, 약점 2개 추출
    eff <- sapply(names(labels), function(nm) {
      s  <- as.numeric(sb[[nm]]$score %||% 0)
      mx <- as.numeric(labels[[nm]]$max)
      s / mx
    })
    sorted_names <- names(sort(eff))  # 오름차순 = 약점 먼저

    fmt_item <- function(nm) {
      lbl <- labels[[nm]]$label
      s   <- as.numeric(sb[[nm]]$score %||% 0)
      mx  <- as.numeric(labels[[nm]]$max)
      # 조정 항목 (음수 가능): 부호 명시
      if (nm %in% c("alpha_trend", "oos", "ic_stability")) {
        icon <- if (s > 1) "↑" else if (s < -1) "↓" else "→"
        sprintf("%s%s%+.1f/%d", icon, lbl, s, mx)
      } else {
        sprintf("%s %.1f/%d", lbl, s, mx)
      }
    }

    weak2   <- sorted_names[1:min(2, length(sorted_names))]
    strong2 <- rev(sorted_names)[1:min(2, length(sorted_names))]

    # 주요 항목 한줄 표시 (alpha_trend 포함)
    main_items <- c("sharpe", "ir", "cagr", "rolling", "alpha_trend")
    main_row <- paste(sapply(intersect(main_items, names(sb)), fmt_item), collapse = " │ ")

    score_detail_str <- sprintf(
      "\n─────────────\n📊 점수 세부 (%.1f/100)\n%s\n✅ 강점: %s\n⚠️ 약점: %s",
      score,
      main_row,
      paste(sapply(strong2, fmt_item), collapse = " │ "),
      paste(sapply(weak2,   fmt_item), collapse = " │ ")
    )
  }

  # Family info (from auto-commit hook context)
  family_str <- ""
  if (exists(".qepm_last_family") && nzchar(.qepm_last_family %||% "")) {
    family_str <- sprintf("\nFamily: %s", .qepm_last_family)
  }

  msg <- sprintf(
    "[백테스트 완료] %s\n%s (%.1f/100)%s\n─────────────\nCAGR: %.1f%% │ Sharpe: %.3f\nMDD: %.1f%% │ IR: %.3f │ Calmar: %.3f%s%s",
    strategy_name, verdict_str, score, hard_fail_str,
    .n(m$CAGR), .n(m$Sharpe), .n(m$MDD), .n(m$IR), .n(m$Calmar),
    family_str, score_detail_str
  )
  tg_send(msg)
}

# ─── Strategy Commentary (5줄 인사이트) ─────────────────────────────────────
tg_strategy_commentary <- function(strategy_name, hurdle_result, output_dir) {
  v  <- hurdle_result[["verdict"]] %||% hurdle_result
  m  <- v[["metrics"]] %||% list()
  sb <- v[["score_breakdown"]] %||% list()
  .n <- function(x) { val <- as.numeric(x); if (length(val) == 0 || is.na(val[1])) 0 else val[1] }

  passed <- isTRUE(hurdle_result[["pass"]])
  score  <- .n(hurdle_result[["score"]] %||% hurdle_result[["total_score"]])
  cagr   <- .n(m$CAGR)
  sharpe <- .n(m$Sharpe)
  mdd    <- .n(m$MDD)
  ir     <- .n(m$IR)
  d061   <- .n(sb$alpha_trend$score)
  d062   <- .n(sb$oos$score)

  # ── 코멘트 생성 ──
  # strategy_name은 이미 [코멘트] 헤더에 표시되므로 중복 제목 제거
  lines <- character(0)

  # 1. 한줄 요약 판정
  if (passed) {
    lines <- c(lines, sprintf("✅ 허들 통과! 실전 후보 등록 (%.1f점)", score))
  } else if (score >= 55) {
    lines <- c(lines, sprintf("🟡 근접 (%.1f점) — 앙상블 후보로 가치 있음", score))
  } else if (score >= 40) {
    lines <- c(lines, sprintf("🟠 중간 (%.1f점) — 팩터 신호 자체는 유의미", score))
  } else {
    lines <- c(lines, sprintf("🔴 약함 (%.1f점) — 단독 운용 불가", score))
  }

  # 2. MDD 분석
  if (abs(mdd) > 45) {
    lines <- c(lines, sprintf("⛔ MDD %.1f%% — 하드페일. 레짐 게이팅 강화 필요", mdd))
  } else if (abs(mdd) > 40) {
    lines <- c(lines, sprintf("⚠️ MDD %.1f%% — 경계선. 방어 팩터 블렌딩 고려", mdd))
  } else {
    lines <- c(lines, sprintf("🛡 MDD %.1f%% — 양호. 방어력 우수", mdd))
  }

  # 3. 최근 트렌드
  if (d061 > 3) {
    lines <- c(lines, "📈 최근 성과 급상승 — 현재 시장에 매우 적합")
  } else if (d061 > 0) {
    lines <- c(lines, "📊 최근 성과 개선 — 긍정적 추세")
  } else if (d061 < -3) {
    lines <- c(lines, "📉 최근 성과 급락 — 팩터 구조 변화 가능성")
  } else {
    lines <- c(lines, "➡️ 최근 성과 보합 — 안정적이나 알파 약화")
  }

  # 4. 알파 진단
  if (ir > 0.3) {
    lines <- c(lines, sprintf("💎 IR %.3f — 벤치마크 대비 강한 알파", ir))
  } else if (ir > 0) {
    lines <- c(lines, sprintf("📌 IR %.3f — 약한 알파, 볼 관리가 핵심", ir))
  } else {
    lines <- c(lines, sprintf("❌ IR %.3f — 알파 부재, BM 대비 언더퍼폼", ir))
  }

  # 5. 앙상블 활용 제안
  if (!passed && score >= 40 && abs(mdd) < 55) {
    lines <- c(lines, "🔧 앙상블 후보: 방어 팩터 블렌딩으로 MDD 개선 가능")
  } else if (passed) {
    lines <- c(lines, "🏆 단독 운용 가능. 다른 PASS 전략과 포트폴리오 조합 권장")
  } else {
    lines <- c(lines, "📝 참고 수준. 팩터 신호는 다른 전략의 보조 인자로 활용")
  }

  msg <- sprintf("[코멘트] %s\n%s", strategy_name, paste(lines, collapse = "\n"))
  tg_send(msg)
}

# ─── 누적 교훈 발송 (10개 단위, 새 교훈만) ──────────────────────────────────
tg_cumulative_lessons <- function() {
  lesson_file <- file.path(PROJECT_ROOT, "04_Research", "lessons_sent.json")
  postmortem_file <- file.path(PROJECT_ROOT, "04_Research", "strategy_postmortem.md")

  # 포스트모템 파일에서 교훈 파싱
  if (!file.exists(postmortem_file)) return(invisible(NULL))
  pm_lines <- readLines(postmortem_file, warn = FALSE)
  lesson_lines <- grep("^###\\s*(Lesson\\s+)?L-", pm_lines, value = TRUE)
  if (length(lesson_lines) == 0) return(invisible(NULL))

  # 이미 보낸 교훈 ID 로드
  sent_ids <- character(0)
  if (file.exists(lesson_file)) {
    sent_data <- tryCatch(jsonlite::fromJSON(lesson_file), error = function(e) list(sent = character(0)))
    sent_ids <- sent_data$sent %||% character(0)
  }

  # 새 교훈만 추출
  new_lessons <- character(0)
  new_ids     <- character(0)
  for (ll in lesson_lines) {
    lid <- regmatches(ll, regexpr("L-\\d+", ll))
    if (length(lid) > 0 && !lid %in% sent_ids) {
      new_lessons <- c(new_lessons, ll)
      new_ids     <- c(new_ids, lid)
    }
  }

  # 10개 이상 쌓였을 때만 발송
  if (length(new_lessons) < 10) return(invisible(NULL))

  # 10개씩 묶어서 발송
  batch <- new_lessons[1:10]
  batch_ids <- new_ids[1:10]
  msg <- sprintf(
    "[누적 교훈 업데이트] 새 교훈 %d건\n─────────────\n%s",
    length(batch),
    paste(gsub("^###\\s*(Lesson\\s+)?", "- ", batch), collapse = "\n")
  )
  tg_send(msg)

  # 보낸 ID 저장
  all_sent <- c(sent_ids, batch_ids)
  writeLines(jsonlite::toJSON(list(sent = all_sent), auto_unbox = TRUE), lesson_file)
  cat(sprintf("[tg] Sent %d new lessons (total sent: %d)\n", length(batch), length(all_sent)))
}

# ─── Strategy result + 차트 2장 + 코멘트 (equity curve + annual returns) ─────
tg_strategy_result_with_chart <- function(strategy_name, hurdle_result, output_dir) {
  # 전략명+아이디어 자동 추출
  info <- .extract_strategy_display(strategy_name, output_dir)
  display_name <- info$display
  if (nchar(info$idea) > 0)
    display_name <- sprintf("%s\n  %s", display_name, info$idea)

  # 1. 텍스트 + 점수 세부
  tg_strategy_result(display_name, hurdle_result)
  Sys.sleep(0.5)

  verdict <- if (isTRUE(hurdle_result[["pass"]])) "PASS" else "FAIL"

  # 2. Equity curve
  equity_path <- file.path(output_dir, "equity_curve.png")
  if (file.exists(equity_path)) {
    tg_send_photo(equity_path,
                  caption = sprintf("%s — Equity Curve (%s)", display_name, verdict))
    Sys.sleep(0.3)
  }

  # 3. Annual returns
  annual_path <- file.path(output_dir, "annual_returns.png")
  if (file.exists(annual_path)) {
    tg_send_photo(annual_path,
                  caption = sprintf("%s — Annual Returns (%s)", display_name, verdict))
    Sys.sleep(0.3)
  }

  # 4. 5줄 코멘트 (NEW)
  Sys.sleep(0.3)
  tg_strategy_commentary(display_name, hurdle_result, output_dir)

  # 5. PASS 전략은 팩터 분석 요약도 전송
  if (isTRUE(hurdle_result[["pass"]])) {
    tg_pass_analysis(strategy_name, output_dir)
  }

  # 6. 누적 교훈 체크 (10개 단위 발송)
  tryCatch(tg_cumulative_lessons(), error = function(e) {
    cat(sprintf("[tg] Lesson check skipped: %s\n", e$message))
  })
}

# ─── PASS 전략 팩터 분석 요약 (strategy_analyzer.R 산출물) ────────────────────
# analysis_report.md에서 IC/Rolling/Stress/Turnover 핵심 수치 추출해서 전송
tg_pass_analysis <- function(strategy_name, output_dir) {
  Sys.sleep(0.3)

  # analysis_report.md 파싱
  report_path <- file.path(output_dir, "analysis_report.md")
  ic_str <- rolling_str <- stress_str <- turnover_str <- hhi_str <- NA_character_

  if (file.exists(report_path)) {
    lines <- readLines(report_path, warn = FALSE)

    .grab <- function(pattern) {
      hit <- grep(pattern, lines, value = TRUE)
      if (length(hit) == 0) return(NA_character_)
      # Strip markdown bold (**) and leading "- "
      trimws(gsub("\\*\\*|^- ", "", hit[1]))
    }

    ic_str      <- .grab("IC Mean")
    rolling_str <- .grab("1Y Rolling Sharpe")
    stress_str  <- .grab("Outperform rate vs BM")
    turnover_str <- .grab("Avg Period Turnover")
    hhi_str     <- .grab("Avg Sector HHI")
  }

  # analysis_ic.csv에서 직접 읽기 (fallback)
  if (is.na(ic_str)) {
    ic_path <- file.path(output_dir, "analysis_ic.csv")
    if (file.exists(ic_path)) {
      ic_dt <- tryCatch(read.csv(ic_path), error = function(e) NULL)
      if (!is.null(ic_dt) && nrow(ic_dt) > 0) {
        ic_mean <- round(mean(ic_dt$IC, na.rm = TRUE), 4)
        icir    <- round(mean(ic_dt$IC, na.rm = TRUE) / sd(ic_dt$IC, na.rm = TRUE), 3)
        pos_r   <- round(mean(ic_dt$IC > 0, na.rm = TRUE) * 100, 1)
        ic_str <- sprintf("IC Mean: %.4f │ ICIR: %.3f │ IC>0: %.1f%%",
                          ic_mean, icir, pos_r)
      }
    }
  }

  # analysis_stress.csv에서 직접 읽기 (fallback)
  if (is.na(stress_str)) {
    stress_path <- file.path(output_dir, "analysis_stress.csv")
    if (file.exists(stress_path)) {
      st_dt <- tryCatch(read.csv(stress_path), error = function(e) NULL)
      if (!is.null(st_dt) && nrow(st_dt) > 0 && "Outperform" %in% names(st_dt)) {
        n_out <- sum(st_dt$Outperform, na.rm = TRUE)
        n_tot <- nrow(st_dt)
        stress_str <- sprintf("Stress 아웃퍼폼: %d/%d (%.0f%%)",
                              n_out, n_tot, n_out / n_tot * 100)
      }
    }
  }

  lines_out <- c()
  if (!is.null(ic_str)      && !is.na(ic_str))      lines_out <- c(lines_out, sprintf("📈 %s", ic_str))
  if (!is.null(rolling_str) && !is.na(rolling_str)) lines_out <- c(lines_out, sprintf("🔄 %s", rolling_str))
  if (!is.null(stress_str)  && !is.na(stress_str))  lines_out <- c(lines_out, sprintf("🛡 %s", stress_str))
  if (!is.null(turnover_str)&& !is.na(turnover_str)) lines_out <- c(lines_out, sprintf("🔁 %s", turnover_str))
  if (!is.null(hhi_str)     && !is.na(hhi_str))     lines_out <- c(lines_out, sprintf("🗂 %s", hhi_str))

  # FMB regression results with grade emoji
  fmb_path <- file.path(output_dir, "analysis_fmb_summary.csv")
  if (file.exists(fmb_path)) {
    fmb_dt <- tryCatch(read.csv(fmb_path), error = function(e) NULL)
    if (!is.null(fmb_dt) && nrow(fmb_dt) > 0) {
      score_row <- fmb_dt[fmb_dt$Variable == "Score", ]
      if (nrow(score_row) > 0) {
        t_val <- score_row$t_stat_NW
        sig_star <- if (isTRUE(score_row$Significant)) "*" else ""
        # FMB grade: t>2.58=A, t>1.96=B, t>1.65=C, else D
        fmb_grade <- if (abs(t_val) >= 2.58) "\U0001f525A"
                     else if (abs(t_val) >= 1.96) "\u2705B"
                     else if (abs(t_val) >= 1.65) "\U0001f7e1C"
                     else "\u26a0\ufe0fD"
        fmb_str <- sprintf("FMB [%s] t=%.2f%s | lambda=%.5f | R2=%.3f",
                           fmb_grade, t_val, sig_star,
                           score_row$Lambda_Mean, score_row$Avg_R2)
        lines_out <- c(lines_out, sprintf("📊 %s", fmb_str))
      }
    }
  }

  # Multi-factor regression results with alpha grade
  mf_path <- file.path(output_dir, "analysis_multifactor.csv")
  if (file.exists(mf_path)) {
    mf_dt <- tryCatch(read.csv(mf_path), error = function(e) NULL)
    if (!is.null(mf_dt) && nrow(mf_dt) > 0) {
      for (j in seq_len(nrow(mf_dt))) {
        r <- mf_dt[j, ]
        t_a <- abs(r$Alpha_tstat)
        sig <- if (t_a >= 1.96) "*" else ""
        # Alpha grade: t>2.58=A, t>1.96=B, t>1.65=C, else D
        a_grade <- if (t_a >= 2.58) "\U0001f525"
                   else if (t_a >= 1.96) "\u2705"
                   else if (t_a >= 1.65) "\U0001f7e1"
                   else "\u26aa"
        mf_str <- sprintf("%s %s: a=%.1f%%/yr (t=%.2f%s) R2=%.3f",
                          a_grade, r$Model, r$Alpha_Annual_Pct, r$Alpha_tstat, sig, r$Adj_R2)
        lines_out <- c(lines_out, mf_str)
      }
    }
  }

  if (length(lines_out) == 0) return(invisible(NULL))

  msg <- sprintf("[팩터 분석] %s\n─────────────\n%s",
                 strategy_name, paste(lines_out, collapse = "\n"))
  tg_send(msg)
}

# ─── DART 수집 진행률 ──────────────────────────────────────────────────────────
tg_dart_progress <- function(done, total, ok_count = NULL, fail_count = NULL) {
  pct   <- round(done / total * 100, 1)
  extra <- if (!is.null(ok_count))
    sprintf("\nOK: %d │ FAIL: %d", ok_count, fail_count) else ""
  msg <- sprintf("[DART 수집] %d/%d (%.1f%%)%s", done, total, pct, extra)
  tg_send(msg)
}

# ─── DART 완료 ────────────────────────────────────────────────────────────────
tg_dart_complete <- function(ok_count, empty_count, fail_count) {
  msg <- sprintf(
    "[DART 수집 완료] ✅\nOK: %d │ EMPTY: %d │ FAIL: %d\n펀더멘털 팩터 계산 준비 완료",
    ok_count, empty_count, fail_count
  )
  tg_send(msg)
}

# ─── 논문 분석 완료 ────────────────────────────────────────────────────────────
tg_paper_analyzed <- function(paper_id, title, idea_summary = NULL) {
  extra <- if (!is.null(idea_summary)) sprintf("\n💡 %s", idea_summary) else ""
  msg <- sprintf("[논문 분석] %s\n%s%s", paper_id, title, extra)
  tg_send(msg)
}

# ─── 오류 알림 ────────────────────────────────────────────────────────────────
tg_error <- function(strategy_name, error_msg) {
  msg <- sprintf("[오류] %s\n<code>%s</code>",
                 strategy_name, substr(error_msg, 1, 300))
  tg_send(msg)
}

# ─── 단순 브리핑 ──────────────────────────────────────────────────────────────
tg_briefing <- function(content, slot = "AM") {
  header <- sprintf("[%s 브리핑] %s", slot, format(Sys.Date(), "%Y-%m-%d"))
  msg <- paste(header, content, sep = "\n─────────────\n")
  tg_send(msg)
}

# ─── 전체 브리핑 (전략 스코어보드 + 리서치 진행률 + DART + 베스트 차트) ──────
tg_full_briefing <- function(slot = "AM") {
  cat("[tg_briefing] Generating full briefing...\n")
  today <- format(Sys.Date(), "%Y-%m-%d")

  # ── 1. 전략 스코어보드 ──
  reg_path <- file.path(PROJECT_ROOT, "06_Registry", "strategy_registry.json")
  strats   <- NULL
  score_text <- "전략 없음"

  if (file.exists(reg_path)) {
    strats <- tryCatch(jsonlite::fromJSON(reg_path), error = function(e) NULL)
    if (!is.null(strats) && is.data.frame(strats) && nrow(strats) > 0) {
      n_pass <- sum(as.logical(strats$hurdle_pass), na.rm = TRUE)
      n_fail <- nrow(strats) - n_pass

      # PASS 전략 먼저, 그 다음 FAIL 상위 — 합쳐서 5개
      pass_rows <- strats[as.logical(strats$hurdle_pass) %in% TRUE, ]
      fail_rows <- strats[!as.logical(strats$hurdle_pass) %in% TRUE, ]
      pass_rows <- pass_rows[order(-pass_rows$hurdle_score), ]
      fail_rows <- fail_rows[order(-fail_rows$hurdle_score), ]

      n_show <- 5
      top <- rbind(
        head(pass_rows, min(n_show, nrow(pass_rows))),
        head(fail_rows, max(0, n_show - nrow(pass_rows)))
      )

      rows <- apply(top, 1, function(r) {
        icon <- if (isTRUE(as.logical(r["hurdle_pass"]))) "✅" else "❌"
        cagr_val <- suppressWarnings(as.numeric(r["cagr"]))
        sr_val   <- suppressWarnings(as.numeric(r["sharpe"]))
        mdd_val  <- suppressWarnings(as.numeric(r["mdd"]))
        sc_val   <- suppressWarnings(as.numeric(r["hurdle_score"]))
        sprintf("%s %s %.0f점 │ CAGR %.1f%% │ SR %.2f │ MDD %.1f%%",
                icon, r["id"], sc_val %||% 0, cagr_val %||% 0,
                sr_val %||% 0, abs(mdd_val %||% 0))
      })

      score_text <- paste(
        c(sprintf("전략 현황 (%d개 │ ✅%d ❌%d)", nrow(strats), n_pass, n_fail),
          rows),
        collapse = "\n"
      )
    }
  }

  # ── 2. 리서치 진행률 ──
  research_text <- ""
  paper_path <- file.path(PROJECT_ROOT, "06_Registry", "paper_registry.json")
  if (file.exists(paper_path)) {
    papers <- tryCatch(jsonlite::fromJSON(paper_path), error = function(e) NULL)
    if (!is.null(papers) && is.data.frame(papers)) {
      n_total    <- nrow(papers)
      n_analyzed <- sum(papers$status == "analyzed", na.rm = TRUE)
      idea_path  <- file.path(PROJECT_ROOT, "06_Registry", "idea_registry.json")
      n_ideas    <- if (file.exists(idea_path)) {
        nrow(tryCatch(jsonlite::fromJSON(idea_path), error = function(e) data.frame()))
      } else 0L
      research_text <- sprintf(
        "리서치 진행률\n논문: %d/%d 분석 (%.0f%%) │ 아이디어: %d개",
        n_analyzed, n_total, n_analyzed / n_total * 100, n_ideas
      )
    }
  }

  # ── 3. DART 수집 상태 ──
  dart_text <- ""
  dart_log  <- file.path(PROJECT_ROOT, "dart_collect.log")
  if (file.exists(dart_log)) {
    last_lines <- tail(readLines(dart_log, warn = FALSE), 5)
    progress_line <- tail(grep("^  \\[", last_lines, value = TRUE), 1)
    if (length(progress_line) > 0) {
      dart_text <- sprintf("DART 수집\n%s", progress_line)
    }
  }

  full_msg <- paste(
    c(sprintf("[%s 브리핑] %s", slot, today),
      "─────────────",
      score_text, "",
      research_text, "",
      dart_text),
    collapse = "\n"
  )
  tg_send(full_msg)
  Sys.sleep(0.5)

  # ── 4. PASS 전략 베스트 차트 2장 전송 ──
  if (!is.null(strats) && is.data.frame(strats) && nrow(strats) > 0) {
    pass_only <- strats[as.logical(strats$hurdle_pass) %in% TRUE, ]
    if (nrow(pass_only) > 0) {
      best_id <- pass_only$id[which.max(pass_only$hurdle_score)]
      chart_base <- Sys.glob(file.path(PROJECT_ROOT, "04_Research", "strategies",
                                        paste0(best_id, "*"), "output"))
      if (length(chart_base) > 0) {
        equity_f <- file.path(chart_base[1], "equity_curve.png")
        annual_f <- file.path(chart_base[1], "annual_returns.png")
        caption  <- sprintf("Best: %s (Score %.1f)", best_id,
                             max(pass_only$hurdle_score, na.rm = TRUE))
        if (file.exists(equity_f)) { tg_send_photo(equity_f, caption); Sys.sleep(0.3) }
        if (file.exists(annual_f)) { tg_send_photo(annual_f, caption); Sys.sleep(0.3) }
      }
    }
  }

  cat("[tg_briefing] Done.\n")
}

#==============================================================================
# Quantitative Trigger Alerts — Lawbook v1.4.2 Ch.13
# Detects significant changes in portfolio KPIs and sends auto-alerts.
# Compare current vs previous snapshot: trigger if delta exceeds threshold.
#==============================================================================

.TG_TRIGGER_CACHE <- file.path(
  ifelse(exists("CACHE_DIR"), CACHE_DIR,
         file.path(Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot")), ".cache")),
  "tg_trigger_snapshot.json"
)

tg_trigger_check <- function(current_metrics, strategy_name = "Portfolio") {
  # current_metrics: list with Sharpe, ES99_d, MDD, Turnover
  # Compares to previous snapshot and fires alerts if thresholds exceeded
  #
  # Thresholds (Lawbook Ch.13):
  #   Sharpe_ann  +0.10  → improvement alert
  #   ES99_d      -0.30%p → risk deterioration
  #   MDD         -2.0%p  → drawdown deepened
  #   Turnover    +100%p/yr → cost surge

  THRESHOLDS <- list(
    Sharpe   = list(delta =  0.10, dir = "up",   label = "Sharpe improved"),
    Sharpe_d = list(delta = -0.10, dir = "down", label = "Sharpe deteriorated"),
    ES99_d   = list(delta =  0.30, dir = "up",   label = "ES99 risk increased"),
    MDD      = list(delta =  2.00, dir = "up",   label = "MDD deepened"),
    Turnover = list(delta = 100.0, dir = "up",   label = "Turnover surged")
  )

  # Load previous snapshot
  prev <- if (file.exists(.TG_TRIGGER_CACHE)) {
    tryCatch(fromJSON(.TG_TRIGGER_CACHE, simplifyDataFrame = FALSE), error = function(e) list())
  } else list()

  alerts <- character(0)

  # Check each metric
  if (!is.null(current_metrics$Sharpe) && !is.null(prev$Sharpe)) {
    d <- current_metrics$Sharpe - prev$Sharpe
    if (d >= 0.10) alerts <- c(alerts,
      sprintf("\U0001f4c8 Sharpe +%.3f (%.3f → %.3f)", d, prev$Sharpe, current_metrics$Sharpe))
    if (d <= -0.10) alerts <- c(alerts,
      sprintf("\u26a0\ufe0f Sharpe %.3f (%.3f → %.3f)", d, prev$Sharpe, current_metrics$Sharpe))
  }

  if (!is.null(current_metrics$ES99_d) && !is.null(prev$ES99_d)) {
    d <- current_metrics$ES99_d - prev$ES99_d  # positive = risk increased
    if (d >= 0.30) alerts <- c(alerts,
      sprintf("\U0001f6a8 ES99 +%.2f%%p (%.2f%% → %.2f%%)", d, prev$ES99_d, current_metrics$ES99_d))
  }

  if (!is.null(current_metrics$MDD) && !is.null(prev$MDD)) {
    d <- current_metrics$MDD - prev$MDD  # positive = deeper drawdown
    if (d >= 2.0) alerts <- c(alerts,
      sprintf("\U0001f4c9 MDD +%.1f%%p (%.1f%% → %.1f%%)", d, prev$MDD, current_metrics$MDD))
  }

  if (!is.null(current_metrics$Turnover) && !is.null(prev$Turnover)) {
    d <- current_metrics$Turnover - prev$Turnover
    if (d >= 100) alerts <- c(alerts,
      sprintf("\U0001f504 Turnover +%.0f%%p (%.0f%% → %.0f%%)", d, prev$Turnover, current_metrics$Turnover))
  }

  # Save current as new snapshot
  snapshot <- list(
    strategy  = strategy_name,
    Sharpe    = current_metrics$Sharpe,
    ES99_d    = current_metrics$ES99_d,
    MDD       = current_metrics$MDD,
    Turnover  = current_metrics$Turnover,
    timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  )
  tryCatch(
    write_json(snapshot, .TG_TRIGGER_CACHE, auto_unbox = TRUE, pretty = TRUE),
    error = function(e) NULL
  )

  # Send alerts
  if (length(alerts) > 0) {
    msg <- sprintf("[KPI Trigger Alert] %s\n─────────────\n%s",
                   strategy_name, paste(alerts, collapse = "\n"))
    tg_send(msg)
    cat(sprintf("[tg_trigger] %d alert(s) sent for %s\n", length(alerts), strategy_name))
  } else {
    cat("[tg_trigger] No triggers fired.\n")
  }

  invisible(list(alerts = alerts, snapshot = snapshot))
}

#==============================================================================
# tg_regime_briefing() — Regime 브리핑 표준 양식 (Session 32 확정)
# Chart 1: Regime Score + Cash (24M 바차트)
# Chart 2: 3-Layer Signal (MSM/KTRI 라인 + FRED 바)
# Chart 3: KTRI 9사분면 (Level x Direction, 일간 궤적)
# + 이모지 포함 텍스트 코멘터리
# 날짜: 최신 데이터 기준 (월말 아님)
#==============================================================================
tg_regime_briefing <- function(regime_dt = NULL, ktri_daily = NULL) {
  suppressPackageStartupMessages({
    library(data.table); library(arrow); library(ggplot2); library(scales); library(gridExtra)
  })

  # ── Load data ──
  if (is.null(regime_dt)) {
    cache_path <- file.path(
      ifelse(exists("CACHE_DIR"), CACHE_DIR,
             file.path(PROJECT_ROOT, ".cache")),
      "unified_regime_signal.parquet")
    if (!file.exists(cache_path)) {
      cat("[regime_briefing] unified_regime_signal.parquet not found. Run build_regime_signal_table() first.\n")
      return(invisible(NULL))
    }
    regime_dt <- as.data.table(arrow::read_parquet(cache_path))
  }
  setorder(regime_dt, Date)

  if (is.null(ktri_daily)) {
    ktri_paths <- c(
      file.path(PROJECT_ROOT, "04_Regime_Engine/output/ktri_v3_signals.csv"),
      file.path(PROJECT_ROOT, "04_Research/regime_comparison/output/ktri_v3_signals.csv")
    )
    kp <- ktri_paths[file.exists(ktri_paths)]
    if (length(kp) > 0) {
      ktri_daily <- fread(kp[1])
      ktri_daily[, Date := as.Date(DATE)]
    }
  }

  out_dir <- file.path(
    ifelse(exists("RESEARCH_OUTPUT"), RESEARCH_OUTPUT,
           file.path(PROJECT_ROOT, "04_Research")),
    "regime_analysis")
  if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)

  latest <- regime_dt[.N]

  # ── ref_date: 최신 데이터 기준 날짜 (월말 X) ──
  raw_date <- tryCatch({
    rp <- ifelse(exists("RAWDATA_CACHE"), RAWDATA_CACHE,
                 file.path(PROJECT_ROOT, ".cache", "RAWDATA.parquet"))
    if (file.exists(rp)) max(as.data.table(arrow::read_parquet(rp))$Date) else NULL
  }, error = function(e) NULL)

  ktri_date <- if (!is.null(ktri_daily) && nrow(ktri_daily) > 0) max(ktri_daily$Date) else NULL

  # 가장 최신 날짜 사용 (RAWDATA > KTRI > regime 월말)
  ref_date <- max(c(raw_date, ktri_date), na.rm = TRUE)
  if (is.na(ref_date) || length(ref_date) == 0) ref_date <- latest$Date

  # ── Chart 1 (v2.3 2026-04-24): Daily Regime Score + Cash (12M) ──
  # unified_regime_signal_daily.parquet 기반 최근 12개월 일간 — 월간 24M block을 완전 대체
  daily_signal_path_c1 <- file.path(
    ifelse(exists("CACHE_DIR"), CACHE_DIR, file.path(PROJECT_ROOT, ".cache")),
    "unified_regime_signal_daily.parquet")
  cat_colors <- c(RISK_ON = "#43A047", NEUTRAL = "#9E9E9E",
                  CAUTION = "#FFB300", RISK_OFF = "#E53935", CRISIS = "#B71C1C")

  chart1_ok <- FALSE
  if (file.exists(daily_signal_path_c1)) {
    tryCatch({
      d1_all <- as.data.table(read_parquet(daily_signal_path_c1))
      setorder(d1_all, Date)
      d1 <- d1_all[Date >= (Sys.Date() - 365)]
      if (nrow(d1) > 20) {
        d1[, Category_f := factor(Category,
             levels = c("RISK_ON", "NEUTRAL", "CAUTION", "RISK_OFF", "CRISIS"))]
        latest_d1 <- d1[.N]
        # long-format: Regime_Score_smooth + Regime_Score raw → Line 범례용
        d1_long <- rbind(
          d1[, .(Date, Series = "EWMA smooth", Value = Regime_Score_smooth)],
          d1[, .(Date, Series = "Raw", Value = Regime_Score)]
        )
        d1_long[, Series := factor(Series, levels = c("EWMA smooth", "Raw"))]

        p1 <- ggplot() +
          # (1) Category 배경 색띠
          {
            d1[, cat_grp := rleid(Category)]
            cat_bands <- d1[, .(xmin = min(Date), xmax = max(Date),
                                 Category = Category[1]), by = cat_grp]
            geom_rect(data = cat_bands,
                      aes(xmin = xmin, xmax = xmax, ymin = -Inf, ymax = Inf,
                          fill = Category), alpha = 0.12, inherit.aes = FALSE)
          } +
          scale_fill_manual(values = cat_colors, name = "Regime (background)",
                            guide = guide_legend(override.aes = list(alpha = 0.5),
                                                 order = 2)) +
          # (2) Regime_Score Raw + EWMA smooth 2 line (범례 포함)
          geom_line(data = d1_long, aes(x = Date, y = Value, color = Series,
                                         linewidth = Series, alpha = Series)) +
          scale_color_manual(values = c("EWMA smooth" = "#0D47A1",
                                         "Raw" = "#455A64"),
                             name = "Score line",
                             guide = guide_legend(order = 1)) +
          scale_linewidth_manual(values = c("EWMA smooth" = 1.2, "Raw" = 0.35),
                                  guide = "none") +
          scale_alpha_manual(values = c("EWMA smooth" = 1.0, "Raw" = 0.5),
                              guide = "none") +
          # (3) Threshold 수평선
          geom_hline(yintercept = c(30, 50, 70),
                     linetype = "dashed", color = "gray60", linewidth = 0.35) +
          # (4) Latest dot
          geom_point(data = latest_d1, aes(x = Date, y = Regime_Score_smooth),
                     color = "#0D47A1", fill = "#FFEB3B",
                     shape = 21, size = 5, stroke = 1.3,
                     inherit.aes = FALSE) +
          annotate("label",
                   x = latest_d1$Date, y = latest_d1$Regime_Score_smooth,
                   label = sprintf("NOW %.1f\n%s",
                                   latest_d1$Regime_Score_smooth,
                                   latest_d1$Category),
                   hjust = 1.1, vjust = 0.5, size = 3.1, fontface = "bold",
                   color = "#0D47A1",
                   fill = scales::alpha("white", 0.92), linewidth = 0.3,
                   label.padding = unit(0.25, "lines")) +
          scale_y_continuous(
            name = "Regime Score 0~100",
            limits = c(0, 100),
            breaks = c(0, 30, 50, 70, 100)) +
          labs(title = "Daily Regime Score (12M)",
               subtitle = sprintf(
                 "Data: %s | Score %.1f | %s",
                 format(latest_d1$Date),
                 latest_d1$Regime_Score_smooth,
                 latest_d1$Category),
               x = "") +
          theme_minimal(base_size = 13) +
          theme(plot.title = element_text(face = "bold", size = 15),
                plot.subtitle = element_text(size = 10, color = "gray25"),
                legend.position = "bottom",
                legend.box = "horizontal",
                panel.grid.major = element_line(color = "gray92", linewidth = 0.3),
                panel.grid.minor = element_blank())
        ggsave(file.path(out_dir, "regime_score_24m.png"),
               p1, width = 11, height = 5.8, dpi = 150)
        chart1_ok <- TRUE
      }
    }, error = function(e) {
      cat(sprintf("[regime_briefing] chart 1 daily 12M failed: %s\n", e$message))
    })
  }
  if (!chart1_ok) {
    # Legacy fallback (월간 24M) — daily 파일 없을 때만
    r24 <- tail(regime_dt, 24)
    r24[, Category_f := factor(Category, levels = c("RISK_ON", "NEUTRAL", "CAUTION", "RISK_OFF"))]
    p1 <- ggplot(r24, aes(x = Date)) +
      geom_col(aes(y = Regime_Score, fill = Category_f), width = 25, alpha = 0.85) +
      geom_line(aes(y = Cash_Pct * 100), color = "red", linewidth = 1.2, linetype = "dashed") +
      geom_point(aes(y = Cash_Pct * 100), color = "red", size = 2) +
      scale_fill_manual(values = cat_colors, name = "Regime") +
      scale_y_continuous(name = "Regime Score",
        sec.axis = sec_axis(~ . / 100, name = "Cash %", labels = percent)) +
      labs(title = "Regime Score & Cash Allocation (24M) [Monthly Fallback]",
           subtitle = sprintf("Data: %s | Score %.1f | %s | Cash %.1f%%",
                              ref_date, latest$Regime_Score, latest$Category, latest$Cash_Pct * 100)) +
      theme_minimal(base_size = 13) +
      theme(plot.title = element_text(face = "bold", size = 15),
            legend.position = "bottom",
            axis.title.y.right = element_text(color = "red"))
    ggsave(file.path(out_dir, "regime_score_24m.png"), p1, width = 10, height = 5.5, dpi = 150)
  }

  # ── Chart 2 (v2.4 2026-04-24): 24M 월말 + 마지막 일간 붙여서 3-Layer ──
  # 월말 기준 long-series + 최근 일간 row (월말 아니어도 붙임) hybrid
  chart2_ok <- FALSE
  if (file.exists(daily_signal_path_c1)) {
    tryCatch({
      d2_all <- as.data.table(read_parquet(daily_signal_path_c1))
      setorder(d2_all, Date)

      # 월말 aggregate (24개월): 각 YM 마지막 거래일
      d2_all[, YM := format(Date, "%Y-%m")]
      d2_monthly <- d2_all[, .SD[which.max(Date)], by = YM]
      d2_monthly <- tail(d2_monthly, 24)

      # 최신 일간 row (월말 아니어도 붙임)
      latest_d2 <- d2_all[.N]
      if (latest_d2$YM != d2_monthly[.N, YM]) {
        # 다른 월이면 그대로 추가
        d2_combined <- rbind(d2_monthly, latest_d2, fill = TRUE)
      } else if (latest_d2$Date > d2_monthly[.N, Date]) {
        # 같은 월인데 월말 이후 일간 data 있으면 마지막 monthly row를 daily로 교체
        d2_combined <- rbind(d2_monthly[-.N], latest_d2, fill = TRUE)
      } else {
        d2_combined <- d2_monthly
      }
      setorder(d2_combined, Date)

      # v2.5: MSM / KTRI / VEA 3-line + 화려한 MRS panel + latest value labels
      d2_long <- melt(d2_combined, id.vars = "Date",
                      measure.vars = c("MSM_Crisis_Prob", "KTRI_Score", "VEA_Score"),
                      variable.name = "Layer", value.name = "Value")
      d2_long[Layer == "MSM_Crisis_Prob", Value := Value * 100]
      d2_long[, Layer := factor(Layer,
        levels = c("MSM_Crisis_Prob", "KTRI_Score", "VEA_Score"),
        labels = c("MSM Crisis %", "KTRI Score", "VEA Score"))]
      d2_long <- d2_long[!is.na(Value)]

      last_points <- d2_long[Date == max(Date)]
      # 라벨 y-offset: MSM 상단, KTRI 중단, VEA 하단 (충돌 방지)
      last_points[, y_offset := fifelse(Layer == "MSM Crisis %", 5,
                               fifelse(Layer == "KTRI Score", -5, -12))]

      layer_colors <- c("MSM Crisis %" = "#E53935",
                        "KTRI Score"   = "#1E88E5",
                        "VEA Score"    = "#43A047")

      p2_top <- ggplot(d2_long, aes(x = Date, y = Value, color = Layer)) +
        # Background threshold zone
        annotate("rect", xmin = -Inf, xmax = Inf, ymin = 70, ymax = 100,
                 fill = "#FFCDD2", alpha = 0.25) +
        annotate("rect", xmin = -Inf, xmax = Inf, ymin = 30, ymax = 70,
                 fill = "#FFF9C4", alpha = 0.15) +
        annotate("rect", xmin = -Inf, xmax = Inf, ymin = 0, ymax = 30,
                 fill = "#C8E6C9", alpha = 0.25) +
        geom_line(linewidth = 1.1) +
        geom_point(size = 1.8) +
        # 마지막 일간 point — 각 layer 색상 그대로 굵게 (yellow fill 제거)
        geom_point(data = last_points, aes(color = Layer),
                   size = 3.8, stroke = 1.0) +
        # Value labels (점 옆)
        geom_text(data = last_points,
                  aes(x = Date, y = Value + y_offset,
                      label = sprintf("%.1f", Value),
                      color = Layer),
                  hjust = 1.1, size = 3.7, fontface = "bold",
                  show.legend = FALSE) +
        geom_hline(yintercept = 50, linetype = "dotted", color = "gray40",
                   linewidth = 0.4) +
        scale_color_manual(values = layer_colors, name = "Layer") +
        scale_y_continuous(name = "Score / Prob 0~100",
                           limits = c(0, 105),
                           breaks = c(0, 30, 50, 70, 100)) +
        labs(title = "3-Layer Signal Decomposition (Month-end + Latest Daily)",
             subtitle = sprintf(
               "MSM %.1f%% | KTRI %.1f | VEA %.1f | FRED MRS %.1f  (latest: %s)",
               latest_d2$MSM_Crisis_Prob * 100,
               latest_d2$KTRI_Score, latest_d2$VEA_Score,
               latest_d2$FRED_MRS,
               format(latest_d2$Date)),
             x = "") +
        theme_minimal(base_size = 13) +
        theme(plot.title = element_text(face = "bold", size = 15),
              plot.subtitle = element_text(size = 10, color = "gray25"),
              legend.position = "bottom",
              panel.grid.major = element_line(color = "gray92", linewidth = 0.3),
              panel.grid.minor = element_blank())

      # 하단 FRED_MRS (v2.7 polish): month-end + latest daily hybrid, 세련된 스타일
      d2_combined[, fred_band := fifelse(FRED_MRS >= 70, "Stress",
                                   fifelse(FRED_MRS >= 50, "Caution",
                                     fifelse(FRED_MRS >= 30, "Normal", "Calm")))]
      latest_mrs <- d2_combined[.N]
      prev_mrs <- if (nrow(d2_combined) >= 2) d2_combined[.N - 1] else latest_mrs
      mrs_delta <- latest_mrs$FRED_MRS - prev_mrs$FRED_MRS

      # Y 축 상한: latest 기준 탄력적 (최소 50, 최대 100)
      y_max <- max(50, min(100, latest_mrs$FRED_MRS * 1.8))
      x_right <- max(d2_combined$Date) + 15

      p2_bot <- ggplot(d2_combined, aes(x = Date, y = FRED_MRS)) +
        # Background threshold zone (subtle saturation)
        annotate("rect", xmin = -Inf, xmax = Inf, ymin = 70, ymax = 100,
                 fill = "#EF5350", alpha = 0.12) +
        annotate("rect", xmin = -Inf, xmax = Inf, ymin = 50, ymax = 70,
                 fill = "#FFA726", alpha = 0.12) +
        annotate("rect", xmin = -Inf, xmax = Inf, ymin = 30, ymax = 50,
                 fill = "#FDD835", alpha = 0.12) +
        annotate("rect", xmin = -Inf, xmax = Inf, ymin = 0, ymax = 30,
                 fill = "#66BB6A", alpha = 0.12) +
        # Band labels 우측 (axis 밖)
        annotate("text", x = x_right, y = 85, label = "Stress",
                 color = "#C62828", size = 3.2, fontface = "bold", hjust = 0) +
        annotate("text", x = x_right, y = 60, label = "Caution",
                 color = "#E65100", size = 3.2, fontface = "bold", hjust = 0) +
        annotate("text", x = x_right, y = 40, label = "Normal",
                 color = "#9E7C00", size = 3.2, fontface = "bold", hjust = 0) +
        annotate("text", x = x_right, y = 15, label = "Calm",
                 color = "#2E7D32", size = 3.2, fontface = "bold", hjust = 0) +
        # Line (Deep Purple — MSM 빨강/KTRI 파랑/VEA 녹색과 조화)
        geom_line(color = "#5E35B1", linewidth = 1.4, alpha = 0.95,
                  lineend = "round") +
        geom_point(color = "#5E35B1", size = 2.3, alpha = 0.9) +
        # Threshold dashed
        geom_hline(yintercept = c(30, 50, 70),
                   linetype = "dashed", color = "gray55", linewidth = 0.3,
                   alpha = 0.7) +
        # Latest 2-tier halo (glow effect) — 동일 색상 계열
        geom_point(data = latest_mrs,
                   color = "#5E35B1", size = 7.2, alpha = 0.25) +
        geom_point(data = latest_mrs,
                   color = "#5E35B1", size = 4.5, stroke = 0) +
        # Latest value label (box)
        geom_label(data = latest_mrs,
                   aes(label = sprintf("NOW  %.1f\n%s  (5d %+.1f)",
                                       FRED_MRS, fred_band, mrs_delta)),
                   hjust = 1.08, vjust = -0.3, size = 3.6, fontface = "bold",
                   color = "#5E35B1",
                   fill = scales::alpha("white", 0.94),
                   label.size = 0.4, label.r = unit(0.15, "lines"),
                   label.padding = unit(0.3, "lines")) +
        scale_y_continuous(name = "FRED MRS",
                           limits = c(0, y_max),
                           breaks = c(0, 30, 50, 70, 100),
                           expand = c(0, 0)) +
        scale_x_date(expand = expansion(mult = c(0.01, 0.08))) +
        labs(x = "",
             subtitle = "Month-end + Latest Daily — 0~100 composite (VIX/HY/Term/FFR/BBB/NFCI)") +
        theme_minimal(base_size = 12) +
        theme(plot.subtitle = element_text(size = 9, color = "gray35",
                                            margin = margin(b = 4)),
              legend.position = "none",
              axis.title.y = element_text(face = "bold", color = "#5E35B1",
                                          size = 11),
              panel.grid.major.y = element_line(color = "gray90", linewidth = 0.25),
              panel.grid.major.x = element_line(color = "gray95", linewidth = 0.2),
              panel.grid.minor = element_blank(),
              plot.margin = margin(t = 5, r = 35, b = 5, l = 5))

      p2 <- arrangeGrob(p2_top, p2_bot, heights = c(2.5, 1.3))
      ggsave(file.path(out_dir, "regime_3layer_24m.png"),
             p2, width = 11, height = 8.0, dpi = 150)
      chart2_ok <- TRUE
    }, error = function(e) {
      cat(sprintf("[regime_briefing] chart 2 monthly+latest failed: %s\n", e$message))
    })
  }
  if (!chart2_ok) {
    # Legacy fallback (월간 24M)
    r24 <- tail(regime_dt, 24)
    r24_long <- melt(r24, id.vars = "Date",
                     measure.vars = c("MSM_Crisis_Prob", "KTRI_Score"),
                     variable.name = "Layer", value.name = "Value")
    r24_long[Layer == "MSM_Crisis_Prob", Value := Value * 100]
    r24_long[, Layer := factor(Layer,
      levels = c("MSM_Crisis_Prob", "KTRI_Score"),
      labels = c("MSM Crisis %", "KTRI Score"))]
    p2_top <- ggplot(r24_long, aes(x = Date, y = Value, color = Layer)) +
      geom_line(linewidth = 1.1) + geom_point(size = 1.5) +
      geom_hline(yintercept = 50, linetype = "dotted", color = "gray40") +
      scale_color_manual(values = c("MSM Crisis %" = "#E53935", "KTRI Score" = "#1E88E5")) +
      labs(title = "3-Layer Signal Decomposition [Monthly Fallback]",
           y = "Score / Prob") +
      theme_minimal(base_size = 13) +
      theme(plot.title = element_text(face = "bold", size = 15), legend.position = "bottom")
    p2_bot <- ggplot(r24, aes(x = Date, y = FRED_MRS)) +
      geom_col(fill = "#FF7043", alpha = 0.7, width = 25) +
      labs(y = "FRED MRS", x = "") + theme_minimal(base_size = 11)
    p2 <- arrangeGrob(p2_top, p2_bot, heights = c(3, 1))
    ggsave(file.path(out_dir, "regime_3layer_24m.png"),
           p2, width = 10, height = 6.5, dpi = 150)
  }

  # ── Chart 3: KTRI x VEA 9-Quadrant (from KTRI_breadth_9grid.R) ──
  ktri_latest <- NULL
  if (!is.null(ktri_daily) && nrow(ktri_daily) > 0) {
    suppressPackageStartupMessages(library(dplyr))
    x <- as.data.frame(ktri_daily[!is.na(KTRI) & !is.na(VEA)])
    x <- x[order(x$Date), ]

    # forward 20d return for zone labels
    x$fwd20 <- dplyr::lead(x$IKS200, 20) / x$IKS200 - 1

    # 9-grid bins: KTRI <40/40-60/>60, VEA <60/60-70/>70
    x$K_bin <- cut(x$KTRI, breaks = c(-Inf, 40, 60, Inf), labels = c("K_Low","K_Mid","K_High"), right = FALSE)
    x$V_bin <- cut(x$VEA,  breaks = c(-Inf, 60, 70, Inf), labels = c("V_Low","V_Mid","V_High"), right = FALSE)
    x$K_num <- as.numeric(x$KTRI)
    x$V_num <- as.numeric(x$VEA)

    # Zone summary table
    tbl <- x %>% filter(!is.na(K_bin), !is.na(V_bin)) %>%
      group_by(K_bin, V_bin) %>%
      summarise(n = n(), avg_fwd20 = mean(fwd20, na.rm = TRUE), .groups = "drop")
    all_grid <- expand.grid(K_bin = c("K_Low","K_Mid","K_High"),
                            V_bin = c("V_Low","V_Mid","V_High"), stringsAsFactors = FALSE)
    tbl2 <- all_grid %>% left_join(tbl, by = c("K_bin","V_bin")) %>% mutate(
      zone = case_when(
        K_bin == "K_High" & V_bin == "V_Low"  ~ "Strong Add",
        K_bin == "K_High" & V_bin == "V_Mid"  ~ "Add (Scaled)",
        K_bin == "K_High" & V_bin == "V_High" ~ "Trend Up / Vol Risk",
        K_bin == "K_Mid"  & V_bin == "V_Low"  ~ "Neutral+",
        K_bin == "K_Mid"  & V_bin == "V_Mid"  ~ "Neutral",
        K_bin == "K_Mid"  & V_bin == "V_High" ~ "Neutral-Defensive",
        K_bin == "K_Low"  & V_bin == "V_Low"  ~ "Weakness Easing",
        K_bin == "K_Low"  & V_bin == "V_Mid"  ~ "Defensive Bias",
        TRUE ~ "Strong Hedge"))

    # Trailing 252d (zone stats + 과거 회색) + 최근 60d (빨강 경로)
    trail_all <- x %>% filter(!is.na(K_num), !is.na(V_num)) %>% tail(252)
    trail_old <- head(trail_all, max(0, nrow(trail_all) - 60)) %>% mutate(t_idx = row_number())
    trail <- trail_all %>% tail(60) %>% mutate(t_idx = row_number())
    ktri_latest_row <- tail(trail, 1)
    ktri_latest <- list(
      KTRI = ktri_latest_row$K_num, VEA = ktri_latest_row$V_num,
      Date = ktri_latest_row$Date,
      Delta_KTRI = if ("Delta_KTRI" %in% names(ktri_latest_row)) ktri_latest_row$Delta_KTRI else NA,
      Action_v3 = if ("Action_v3" %in% names(ktri_latest_row)) ktri_latest_row$Action_v3
                  else if ("Action" %in% names(ktri_latest_row)) ktri_latest_row$Action else "NA")

    latest_action <- ktri_latest$Action_v3

    # Determine current zone (before chart)
    ktri_latest$zone <- tbl2$zone[tbl2$K_bin == as.character(cut(ktri_latest$KTRI, c(-Inf,40,60,Inf),
                        labels=c("K_Low","K_Mid","K_High"), right=FALSE)) &
                        tbl2$V_bin == as.character(cut(ktri_latest$VEA, c(-Inf,60,70,Inf),
                        labels=c("V_Low","V_Mid","V_High"), right=FALSE))]
    now_zone <- if (length(ktri_latest$zone) > 0) ktri_latest$zone else latest_action

    # Start/End date labels only
    date_labels <- trail[c(1, nrow(trail)), , drop = FALSE] %>%
      mutate(anchor_lbl = format(Date, "%y/%m/%d"))

    # 5d direction
    recent5 <- tail(trail, min(5, nrow(trail)))
    dk5 <- if (nrow(recent5) >= 2) recent5$K_num[nrow(recent5)] - recent5$K_num[1] else 0
    dv5 <- if (nrow(recent5) >= 2) recent5$V_num[nrow(recent5)] - recent5$V_num[1] else 0
    dir5 <- if (dk5 >= 0 & dv5 <= 0) "Risk-On tilt"
            else if (dk5 <= 0 & dv5 >= 0) "Risk-Off tilt" else "Mixed"

    # Zone label positions
    label_df <- tbl2 %>% mutate(
      x = case_when(K_bin == "K_Low" ~ 20, K_bin == "K_Mid" ~ 50, TRUE ~ 80),
      y = case_when(V_bin == "V_Low" ~ 30, V_bin == "V_Mid" ~ 65, TRUE ~ 85),
      lbl = paste0(zone, "\nFwd20: ", sprintf("%.2f%%", 100 * ifelse(is.na(avg_fwd20), 0, avg_fwd20))))

    # ── 9-quadrant chart (60d trail + line) ──
    p3 <- ggplot() +
      # Bottom row (VEA Low: calm)
      annotate("rect", xmin=0,xmax=40,ymin=0,ymax=60,fill="#ECEFF1",alpha=0.7) +
      annotate("rect", xmin=40,xmax=60,ymin=0,ymax=60,fill="#E3F2FD",alpha=0.7) +
      annotate("rect", xmin=60,xmax=100,ymin=0,ymax=60,fill="#E8F5E9",alpha=0.7) +
      # Middle row (VEA Mid: transitional)
      annotate("rect", xmin=0,xmax=40,ymin=60,ymax=70,fill="#FBE9E7",alpha=0.6) +
      annotate("rect", xmin=40,xmax=60,ymin=60,ymax=70,fill="#FAFAFA",alpha=0.6) +
      annotate("rect", xmin=60,xmax=100,ymin=60,ymax=70,fill="#F1F8E9",alpha=0.6) +
      # Top row (VEA High: stress)
      annotate("rect", xmin=0,xmax=40,ymin=70,ymax=100,fill="#FFCDD2",alpha=0.55) +
      annotate("rect", xmin=40,xmax=60,ymin=70,ymax=100,fill="#FFE0B2",alpha=0.5) +
      annotate("rect", xmin=60,xmax=100,ymin=70,ymax=100,fill="#DCEDC8",alpha=0.5) +
      # Grid boundaries
      geom_vline(xintercept = c(40, 60), linetype = "dashed", color = "gray45", linewidth = 0.6) +
      geom_hline(yintercept = c(60, 70), linetype = "dashed", color = "gray45", linewidth = 0.6) +
      # Old 192d scatter (gray gradient)
      geom_point(data = trail_old, aes(K_num, V_num, alpha = t_idx),
                 color = "gray60", size = 1.3) +
      scale_alpha_continuous(range = c(0.15, 0.45), guide = "none") +
      # 60d path line (trajectory)
      geom_path(data = trail, aes(K_num, V_num), color = "#B71C1C", linewidth = 0.7, alpha = 0.4) +
      # 60d scatter with gradient
      geom_point(data = trail, aes(K_num, V_num, color = t_idx), size = 1.8, alpha = 0.8) +
      scale_color_gradient(low = "#FFCCBC", high = "#C62828", guide = "none") +
      # Start dot (yellow, white border)
      geom_point(data = head(trail, 1), aes(K_num, V_num), shape = 21, fill = "#FDD835",
                 color = "#424242", size = 5, stroke = 1.2) +
      # Latest dot (yellow, white border)
      geom_point(data = tail(trail, 1), aes(K_num, V_num), shape = 21, fill = "#FDD835",
                 color = "#424242", size = 5, stroke = 1.2) +
      # Zone labels (text only)
      geom_text(data = label_df, aes(x, y, label = lbl), size = 3.2, fontface = "bold",
                color = "gray30", alpha = 0.7) +
      # Connector lines: dot → label (black)
      geom_segment(data = date_labels,
                   aes(x = K_num, y = V_num, xend = K_num + 2.5, yend = V_num - 2.5),
                   color = "gray30", linewidth = 0.4) +
      # Start/End date labels (white box, black text)
      geom_label(data = date_labels, aes(K_num, V_num, label = anchor_lbl),
                 size = 2.4, fontface = "bold", color = "black",
                 fill = scales::alpha("white", 0.85), linewidth = 0.2,
                 label.padding = unit(0.12, "lines"),
                 nudge_x = 2.5, nudge_y = -2.5, hjust = 0) +
      # TODAY badge (top-left) — zone name
      annotate("label", x = 2, y = 98,
               label = sprintf("NOW: %s\nK = %.1f  |  V = %.1f", now_zone,
                               ktri_latest$KTRI, ktri_latest$VEA),
               hjust = 0, vjust = 1, size = 4, fontface = "bold",
               color = "#B71C1C", fill = scales::alpha("white", 0.9), linewidth = 0.3) +
      coord_cartesian(xlim = c(0, 100), ylim = c(0, 100), clip = "off") +
      labs(title = sprintf("KTRI-VEA 9-Quadrant (252d, data: %s)", ref_date),
           subtitle = sprintf("5D Change: KTRI %+.1f | VEA %+.1f | %s", dk5, dv5, dir5),
           x = expression(bold("KTRI  ") * "(Weakness" %<-% "" %->% "Strength)"),
           y = expression(bold("VEA  ") * "(Calm" %<-% "" %->% "Stress)")) +
      theme_minimal(base_size = 12) +
      theme(plot.title = element_text(face = "bold", size = 14),
            plot.subtitle = element_text(size = 11, face = "bold", color = "gray30"),
            axis.title = element_text(size = 11),
            panel.grid.major = element_line(color = "gray90", linewidth = 0.3),
            panel.grid.minor = element_blank())

    ggsave(file.path(out_dir, "ktri_9quad.png"), p3, width = 9, height = 6.8, dpi = 140)

    ktri_latest$dir5 <- dir5
  }

  # ── Chart 4 (v2.2 enhanced 2026-04-24): Daily Regime Score 6M (화려 버전) ──
  # unified_regime_signal_daily.parquet 기반 최근 6개월 일간 Regime Score + smooth
  # Category 배경 색띠 + threshold band + gradient fill + Crisis_Prob subline + latest annotation
  daily_signal_path <- file.path(
    ifelse(exists("CACHE_DIR"), CACHE_DIR, file.path(PROJECT_ROOT, ".cache")),
    "unified_regime_signal_daily.parquet")
  daily_dt_cached <- NULL  # 재사용 (message 본문 + chart 5에서 참조)
  latest_daily <- NULL
  prev5_daily <- NULL
  if (file.exists(daily_signal_path)) {
    tryCatch({
      daily_dt_cached <- as.data.table(read_parquet(daily_signal_path))
      setorder(daily_dt_cached, Date)
      latest_daily <- daily_dt_cached[.N]
      # 5d 전 (weekday 기준이 아닌 index 기반; daily 파일은 calendar day 포함)
      idx5 <- max(1, nrow(daily_dt_cached) - 5)
      prev5_daily <- daily_dt_cached[idx5]

      daily_6m <- daily_dt_cached[Date >= (Sys.Date() - 183)]
      if (nrow(daily_6m) > 5) {
        # Category 색상 (5종)
        cat_palette <- c(
          "RISK_ON" = "#43A047",
          "NEUTRAL" = "#9E9E9E",
          "CAUTION" = "#FFB300",
          "RISK_OFF" = "#E53935",
          "CRISIS" = "#B71C1C"
        )
        daily_6m[, cat_color := cat_palette[Category]]
        latest_d <- daily_6m[.N]

        # 5d delta (Score / Crisis_Prob)
        d5_idx <- max(1, nrow(daily_6m) - 5)
        d5_score <- latest_d$Regime_Score_smooth - daily_6m[d5_idx]$Regime_Score_smooth
        d5_crisis <- latest_d$MSM_Crisis_Prob - daily_6m[d5_idx]$MSM_Crisis_Prob
        d5_label <- sprintf("5d \xce\x94 Score %+.1f | Crisis %+.1f%%", d5_score, d5_crisis * 100)

        # Category 배경 색띠 segmentation: 연속된 같은 Category 묶어서 xmin~xmax
        daily_6m[, cat_grp := rleid(Category)]
        cat_bands <- daily_6m[, .(xmin = min(Date), xmax = max(Date),
                                   Category = Category[1]), by = cat_grp]

        # Crisis_Prob 축 정규화: 0~1 → 0~100 scale (secondary axis)
        daily_6m[, Crisis_Scaled := MSM_Crisis_Prob * 100]

        p4 <- ggplot(daily_6m, aes(x = Date)) +
          # (1) Category 배경 색띠 (alpha 0.12)
          geom_rect(data = cat_bands,
                    aes(xmin = xmin, xmax = xmax,
                        ymin = -Inf, ymax = Inf, fill = Category),
                    alpha = 0.12, inherit.aes = FALSE) +
          scale_fill_manual(values = cat_palette, name = "Category",
                            guide = guide_legend(override.aes = list(alpha = 0.5))) +
          # (2) Score threshold band (수평 구분선)
          geom_hline(yintercept = c(30, 50, 70),
                     linetype = "dashed", color = "gray60", linewidth = 0.4) +
          annotate("text", x = min(daily_6m$Date), y = 15, label = "RISK_ON",
                   color = "#2E7D32", size = 3, hjust = 0, alpha = 0.6, fontface = "bold") +
          annotate("text", x = min(daily_6m$Date), y = 40, label = "NEUTRAL",
                   color = "#616161", size = 3, hjust = 0, alpha = 0.6, fontface = "bold") +
          annotate("text", x = min(daily_6m$Date), y = 60, label = "CAUTION",
                   color = "#EF6C00", size = 3, hjust = 0, alpha = 0.6, fontface = "bold") +
          annotate("text", x = min(daily_6m$Date), y = 85, label = "RISK_OFF",
                   color = "#C62828", size = 3, hjust = 0, alpha = 0.6, fontface = "bold") +
          # (3) Crisis_Prob subline (얇은 빨강, secondary indicator)
          geom_line(aes(y = Crisis_Scaled), color = "#D32F2F",
                    linewidth = 0.4, alpha = 0.55, linetype = "dotdash") +
          # (4) Raw Regime_Score 얇은 회색 line
          geom_line(aes(y = Regime_Score), color = "#455A64",
                    linewidth = 0.4, alpha = 0.45) +
          # (5) EWMA smooth 굵은 colored line
          geom_line(aes(y = Regime_Score_smooth), color = "#0D47A1",
                    linewidth = 1.3) +
          # (6) Area fill under smooth line (subtle depth)
          geom_ribbon(aes(ymin = pmin(Regime_Score_smooth, 30),
                          ymax = Regime_Score_smooth),
                      fill = "#0D47A1", alpha = 0.08) +
          # (7) Latest point 큰 도트
          geom_point(data = latest_d,
                     aes(y = Regime_Score_smooth),
                     color = "#0D47A1", fill = "#FFEB3B",
                     shape = 21, size = 5, stroke = 1.3) +
          # (8) Latest annotation
          annotate("label",
                   x = latest_d$Date, y = latest_d$Regime_Score_smooth,
                   label = sprintf("NOW %.1f\n%s\n%s",
                                   latest_d$Regime_Score_smooth,
                                   latest_d$Category,
                                   latest_d$Active_Layers),
                   hjust = 1.1, vjust = 0.5, size = 3.2, fontface = "bold",
                   color = "#0D47A1",
                   fill = scales::alpha("white", 0.92), linewidth = 0.3,
                   label.padding = unit(0.25, "lines")) +
          # (9) 5d delta annotation (top-right)
          annotate("label",
                   x = max(daily_6m$Date),
                   y = 95,
                   label = d5_label,
                   hjust = 1, vjust = 1, size = 3.1, fontface = "bold",
                   color = ifelse(d5_score >= 0, "#C62828", "#2E7D32"),
                   fill = scales::alpha("white", 0.9), linewidth = 0.2) +
          scale_y_continuous(
            name = "Regime Score 0~100",
            limits = c(0, 100),
            breaks = c(0, 30, 50, 70, 100),
            sec.axis = sec_axis(~ . / 100, name = "Crisis Prob",
                                 breaks = c(0, 0.3, 0.5, 0.7, 1.0),
                                 labels = percent)) +
          labs(title = "Daily Regime Score \xe2\x80\x94 Active Layers (6M)",
               subtitle = sprintf(
                 "Latest: Score %.1f / %s / %s | Crisis_Prob %.1f%% | thin=raw, thick=EWMA smooth, dotdash=Crisis_Prob",
                 latest_d$Regime_Score_smooth,
                 latest_d$Category, latest_d$Active_Layers,
                 latest_d$MSM_Crisis_Prob * 100),
               x = "") +
          theme_minimal(base_size = 12) +
          theme(plot.title = element_text(face = "bold", size = 14),
                plot.subtitle = element_text(size = 10, color = "gray25"),
                legend.position = "bottom",
                legend.title = element_text(face = "bold", size = 10),
                panel.grid.major = element_line(color = "gray92", linewidth = 0.3),
                panel.grid.minor = element_blank(),
                axis.title.y.right = element_text(color = "#D32F2F", face = "bold"),
                axis.text.y.right = element_text(color = "#D32F2F"))

        ggsave(file.path(out_dir, "regime_score_daily_6m.png"),
               p4, width = 11, height = 5.8, dpi = 150)
      } else {
        cat("[regime_briefing] daily 6m data insufficient (", nrow(daily_6m), "rows) \xe2\x80\x94 skip chart 4\n")
      }
    }, error = function(e) {
      cat(sprintf("[regime_briefing] chart 4 daily 6M failed: %s\n", e$message))
    })
  } else {
    cat("[regime_briefing] unified_regime_signal_daily.parquet not found \xe2\x80\x94 skip chart 4 (Step 5 \xec\x84\xa0\xed\x96\x89 \xed\x95\x84\xec\x9a\x94)\n")
  }

  # ── Chart 5 (v2.3 2026-04-24): FRED_MRS Composite Single Line (6M Daily) ──
  # unified_regime_signal_daily.parquet 기반 FRED_MRS 0~100 단독 composite line
  # Color band (녹/연황/황/적) + area fill + latest dot + 5d delta annotation
  # 6 series (VIX/HY/Term/FFR/BBB/NFCI) 합성된 composite score만 표시 — 분해 X
  fred_wide_path <- file.path(
    ifelse(exists("CACHE_DIR"), CACHE_DIR, file.path(PROJECT_ROOT, ".cache")),
    "fred_macro_wide.parquet")
  fred_latest_row <- NULL
  fred_prev5_row <- NULL
  # Sentiment 섹션용 raw FRED snapshot (기존 유지)
  if (file.exists(fred_wide_path)) {
    tryCatch({
      fred_dt <- as.data.table(read_parquet(fred_wide_path))
      setorder(fred_dt, Date)
      get_latest <- function(col) {
        v <- fred_dt[[col]]; d <- fred_dt$Date; ok <- !is.na(v)
        if (any(ok)) list(val = tail(v[ok], 1), dt = tail(d[ok], 1))
        else list(val = NA_real_, dt = NA)
      }
      get_prev5 <- function(col) {
        v <- fred_dt[[col]]; d <- fred_dt$Date; ok <- !is.na(v)
        if (sum(ok) < 6) return(NA_real_)
        latest_d_x <- tail(d[ok], 1); target <- latest_d_x - 5
        idxs <- which(ok & d <= target)
        if (length(idxs) == 0) return(NA_real_)
        v[tail(idxs, 1)]
      }
      fred_latest_row <- list(
        VIX = get_latest("VIX"),
        HY_Spread = get_latest("HY_Spread"),
        US_10Y_Yield = get_latest("US_10Y_Yield"),
        KRW_USD = get_latest("KRW_USD"))
      fred_prev5_row <- list(
        VIX = get_prev5("VIX"),
        HY_Spread = get_prev5("HY_Spread"),
        US_10Y_Yield = get_prev5("US_10Y_Yield"),
        KRW_USD = get_prev5("KRW_USD"))
    }, error = function(e) {
      cat(sprintf("[regime_briefing] fred snapshot read failed: %s\n", e$message))
    })
  }

  # Chart 5 본체: daily composite FRED_MRS 단독
  daily_signal_path_c5 <- file.path(
    ifelse(exists("CACHE_DIR"), CACHE_DIR, file.path(PROJECT_ROOT, ".cache")),
    "unified_regime_signal_daily.parquet")
  if (file.exists(daily_signal_path_c5)) {
    tryCatch({
      d5_all <- as.data.table(read_parquet(daily_signal_path_c5))
      setorder(d5_all, Date)
      d5 <- d5_all[Date >= (Sys.Date() - 183) & !is.na(FRED_MRS)]
      if (nrow(d5) > 20) {
        latest_d5 <- d5[.N]
        # 5d delta
        idx5_c5 <- max(1, nrow(d5) - 5)
        prev_d5 <- d5[idx5_c5]
        mrs_d5 <- latest_d5$FRED_MRS - prev_d5$FRED_MRS

        # Color band segments (0~30 / 30~50 / 50~70 / 70~100)
        band_df <- data.frame(
          xmin = min(d5$Date), xmax = max(d5$Date),
          ymin = c(0, 30, 50, 70),
          ymax = c(30, 50, 70, 100),
          band = c("Calm", "Normal", "Caution", "Stress"),
          fill = c("#66BB6A", "#FFF59D", "#FFB74D", "#E57373"))

        # FRED raw sub-component latest snapshot (VIX/HY/Term 3종 — 주요만)
        vix_txt <- if (!is.null(fred_latest_row) && !is.na(fred_latest_row$VIX$val))
          sprintf("VIX %.1f", fred_latest_row$VIX$val) else "VIX N/A"
        hy_txt <- if (!is.null(fred_latest_row) && !is.na(fred_latest_row$HY_Spread$val))
          sprintf("HY %.2f%%", fred_latest_row$HY_Spread$val) else "HY N/A"
        y10_txt <- if (!is.null(fred_latest_row) && !is.na(fred_latest_row$US_10Y_Yield$val))
          sprintf("Term(10Y) %.2f%%", fred_latest_row$US_10Y_Yield$val) else "Term N/A"
        comp_breakdown <- paste(vix_txt, hy_txt, y10_txt, sep = " \xe2\x80\xa2 ")

        delta_color <- if (mrs_d5 >= 0) "#C62828" else "#2E7D32"
        delta_txt <- sprintf("5d \xce\x94 %+.2f", mrs_d5)

        p5 <- ggplot(d5, aes(x = Date, y = FRED_MRS)) +
          # (1) Color band (수평 배경, alpha 0.12)
          geom_rect(data = band_df,
                    aes(xmin = xmin, xmax = xmax,
                        ymin = ymin, ymax = ymax, fill = band),
                    alpha = 0.12, inherit.aes = FALSE) +
          scale_fill_manual(
            values = c("Calm" = "#66BB6A", "Normal" = "#FFF59D",
                       "Caution" = "#FFB74D", "Stress" = "#E57373"),
            breaks = c("Calm", "Normal", "Caution", "Stress"),
            name = "Regime Band",
            guide = guide_legend(override.aes = list(alpha = 0.5))) +
          # (2) Threshold 수평선
          geom_hline(yintercept = c(30, 50, 70),
                     linetype = "dashed", color = "gray55", linewidth = 0.4) +
          # (3) Area fill 아래 (gradient depth)
          geom_area(aes(y = FRED_MRS), fill = "#1565C0", alpha = 0.18) +
          # (4) Single composite line (굵은 파랑)
          geom_line(color = "#0D47A1", linewidth = 1.15) +
          # (5) Latest yellow dot
          geom_point(data = latest_d5,
                     aes(y = FRED_MRS),
                     color = "#0D47A1", fill = "#FFEB3B",
                     shape = 21, size = 5, stroke = 1.3) +
          # (6) Latest annotation — score + 5d delta + component
          annotate("label",
                   x = latest_d5$Date, y = latest_d5$FRED_MRS,
                   label = sprintf("NOW %.1f\n%s", latest_d5$FRED_MRS, delta_txt),
                   hjust = 1.1, vjust = 0.5, size = 3.3, fontface = "bold",
                   color = "#0D47A1",
                   fill = scales::alpha("white", 0.92), linewidth = 0.3,
                   label.padding = unit(0.25, "lines")) +
          # (7) 5d delta annotation (top-right)
          annotate("label",
                   x = max(d5$Date), y = 95,
                   label = sprintf("MRS %s", delta_txt),
                   hjust = 1, vjust = 1, size = 3.1, fontface = "bold",
                   color = delta_color,
                   fill = scales::alpha("white", 0.9), linewidth = 0.2) +
          # (8) Band labels (left margin)
          annotate("text", x = min(d5$Date), y = 15, label = "Calm",
                   color = "#2E7D32", size = 3, hjust = 0, alpha = 0.7, fontface = "bold") +
          annotate("text", x = min(d5$Date), y = 40, label = "Normal",
                   color = "#9E8A00", size = 3, hjust = 0, alpha = 0.7, fontface = "bold") +
          annotate("text", x = min(d5$Date), y = 60, label = "Caution",
                   color = "#EF6C00", size = 3, hjust = 0, alpha = 0.7, fontface = "bold") +
          annotate("text", x = min(d5$Date), y = 85, label = "Stress",
                   color = "#C62828", size = 3, hjust = 0, alpha = 0.7, fontface = "bold") +
          scale_y_continuous(
            name = "FRED_MRS 0~100 (Composite)",
            limits = c(0, 100),
            breaks = c(0, 30, 50, 70, 100)) +
          labs(title = "Daily FRED_MRS \xe2\x80\x94 Macro Regime Composite (6M)",
               subtitle = sprintf(
                 "FRED MRS \xe2\x80\x94 6 series composite (VIX/HY/Term/FFR/BBB/NFCI)  |  NOW %.1f  |  %s",
                 latest_d5$FRED_MRS, comp_breakdown),
               x = "") +
          theme_minimal(base_size = 12) +
          theme(plot.title = element_text(face = "bold", size = 14),
                plot.subtitle = element_text(size = 10, color = "gray25"),
                legend.position = "bottom",
                legend.title = element_text(face = "bold", size = 10),
                panel.grid.major = element_line(color = "gray92", linewidth = 0.3),
                panel.grid.minor = element_blank())

        ggsave(file.path(out_dir, "regime_mrs_daily_6m.png"),
               p5, width = 11, height = 5.8, dpi = 150)
      } else {
        cat("[regime_briefing] daily MRS 6m insufficient \xe2\x80\x94 skip chart 5\n")
      }
    }, error = function(e) {
      cat(sprintf("[regime_briefing] chart 5 MRS composite failed: %s\n", e$message))
    })
  } else {
    cat("[regime_briefing] unified_regime_signal_daily.parquet not found \xe2\x80\x94 skip chart 5\n")
  }

  cat("[regime_briefing] Charts generated.\n")

  # ── v2.2 Emoji text commentary (일간 최신 기준으로 전면 교체) ──
  # 기본: daily 파일이 있으면 latest_daily 사용, 없으면 legacy (월간 latest) fallback
  use_daily <- !is.null(latest_daily)
  msg_latest <- if (use_daily) latest_daily else latest
  msg_ref_date <- if (use_daily) latest_daily$Date else ref_date

  cat_emoji <- switch(as.character(msg_latest$Category),
    RISK_ON  = "\xf0\x9f\x9f\xa2",   # green circle
    NEUTRAL  = "\xe2\x9a\xaa",        # white circle
    CAUTION  = "\xf0\x9f\x9f\xa1",    # yellow circle
    RISK_OFF = "\xf0\x9f\x94\xb4",    # red circle
    CRISIS   = "\xf0\x9f\x94\xb4",    # red circle
    "\xe2\x9d\x93")

  # Daily 5d delta — unified_regime_signal_daily 기반
  score_delta_5d <- 0
  crisis_delta_5d <- 0
  ktri_delta_5d <- 0
  if (use_daily && !is.null(prev5_daily)) {
    score_delta_5d <- msg_latest$Regime_Score_smooth - prev5_daily$Regime_Score_smooth
    crisis_delta_5d <- (msg_latest$MSM_Crisis_Prob - prev5_daily$MSM_Crisis_Prob) * 100
    ktri_delta_5d <- msg_latest$KTRI_Score - prev5_daily$KTRI_Score
  }

  arrow_fn <- function(d, eps = 2) {
    if (is.na(d)) return("\xe2\x9e\xa1\xef\xb8\x8f")
    if (d > eps) "\xe2\xac\x86\xef\xb8\x8f"
    else if (d < -eps) "\xe2\xac\x87\xef\xb8\x8f"
    else "\xe2\x9e\xa1\xef\xb8\x8f"
  }

  score_trend <- sprintf("%s %+.1f", arrow_fn(score_delta_5d, 2), score_delta_5d)
  crisis_trend <- sprintf("%s %+.1f%%p", arrow_fn(crisis_delta_5d, 3), crisis_delta_5d)
  ktri_trend <- sprintf("%s %+.1f", arrow_fn(ktri_delta_5d, 2), ktri_delta_5d)

  # 3-Layer icons (daily Active_Layers 기반)
  active_layers_str <- if (use_daily) as.character(msg_latest$Active_Layers) else "L1+L2+L3"
  has_l1 <- grepl("L1", active_layers_str)
  has_l2 <- grepl("L2", active_layers_str)
  has_l3 <- grepl("L3", active_layers_str)
  l1_icon <- if (has_l1) "\xe2\x9c\x85" else "\xe2\x9a\xaa"
  l2_icon <- if (has_l2) "\xe2\x9c\x85" else "\xe2\x9a\xaa"
  l3_icon <- if (has_l3) "\xe2\x9c\x85" else "\xe2\x9a\xaa"

  # Current values (daily)
  cur_score <- if (use_daily) msg_latest$Regime_Score_smooth else msg_latest$Regime_Score
  cur_cash <- msg_latest$Cash_Pct * 100
  cur_category <- as.character(msg_latest$Category)
  cur_msm <- msg_latest$MSM_Crisis_Prob * 100
  cur_fred <- msg_latest$FRED_MRS
  cur_ktri <- msg_latest$KTRI_Score
  cur_vea <- msg_latest$VEA_Score

  # KTRI 9-quad 섹션 (9-quad 차트 데이터가 있으면 유지)
  ktri_str <- ""
  if (!is.null(ktri_latest)) {
    qzone <- if (!is.null(ktri_latest$zone) && length(ktri_latest$zone) > 0) ktri_latest$zone else "N/A"
    dir_label <- if (!is.null(ktri_latest$dir5)) ktri_latest$dir5 else ""
    ktri_arrow <- arrow_fn(ktri_latest$Delta_KTRI, 1)
    ktri_str <- sprintf(
      "\n\n\xf0\x9f\x93\x8d [KTRI-VEA 9-Quad]\nKTRI: %.1f %s | VEA: %.1f\nZone: %s | Action: %s\n5D: %s",
      ktri_latest$KTRI, ktri_arrow, ktri_latest$VEA,
      qzone, ktri_latest$Action_v3, dir_label)
  }

  # ── Market Sentiment Review (Factor Tilt 대체) ──
  sentiment_str <- ""
  if (!is.null(fred_latest_row)) {
    # Helper: val + arrow + trend
    fred_line <- function(label, latest_val, prev_val, icon, unit = "", fmt = "%.2f",
                          up_is_bad = TRUE, eps = 0.1) {
      if (is.na(latest_val)) return(sprintf("%s %s: N/A", icon, label))
      delta <- if (!is.na(prev_val)) latest_val - prev_val else NA_real_
      arrow_txt <- if (is.na(delta)) "\xe2\x9e\xa1\xef\xb8\x8f"
                   else if (delta > eps) "\xe2\xac\x86\xef\xb8\x8f"
                   else if (delta < -eps) "\xe2\xac\x87\xef\xb8\x8f"
                   else "\xe2\x9e\xa1\xef\xb8\x8f"
      delta_txt <- if (is.na(delta)) "" else sprintf(" (5d %+.2f)", delta)
      sprintf(paste0("%s %s: ", fmt, "%s %s%s"),
              icon, label, latest_val, unit, arrow_txt, delta_txt)
    }

    vix_line <- fred_line("VIX", fred_latest_row$VIX$val, fred_prev5_row$VIX,
                          "\xf0\x9f\x8c\x8a", "", "%.1f", up_is_bad = TRUE, eps = 0.5)
    hy_line  <- fred_line("HY Spread", fred_latest_row$HY_Spread$val,
                          fred_prev5_row$HY_Spread,
                          "\xf0\x9f\x92\xb3", "%", "%.2f", up_is_bad = TRUE, eps = 0.05)
    y10_line <- fred_line("10Y Yield", fred_latest_row$US_10Y_Yield$val,
                          fred_prev5_row$US_10Y_Yield,
                          "\xf0\x9f\x93\x8f", "%", "%.2f", up_is_bad = FALSE, eps = 0.05)
    krw_line <- fred_line("KRW/USD", fred_latest_row$KRW_USD$val,
                          fred_prev5_row$KRW_USD,
                          "\xf0\x9f\x87\xb0\xf0\x9f\x87\xb7", "", "%.0f",
                          up_is_bad = TRUE, eps = 5)

    # Overall sentiment — VIX + HY 기반 heuristic
    overall_tag <- tryCatch({
      v <- fred_latest_row$VIX$val
      h <- fred_latest_row$HY_Spread$val
      if (is.na(v) || is.na(h)) "Mixed \xe2\x80\x94 data gap"
      else if (v >= 28 || h >= 5.0) "Risk-Off \xe2\x80\x94 stress elevated"
      else if (v >= 22 || h >= 4.0) "Cautious \xe2\x80\x94 macro tension rising"
      else if (v <= 15 && h <= 3.0) "Calm \xe2\x80\x94 macro benign"
      else "Neutral \xe2\x80\x94 mixed signals"
    }, error = function(e) "Mixed")

    sentiment_str <- sprintf(paste0(
      "\xf0\x9f\x92\xa1 [Market Sentiment Review]\n",
      "%s\n%s\n%s\n%s\n",
      "Overall: %s"),
      vix_line, hy_line, y10_line, krw_line, overall_tag)
  } else {
    sentiment_str <- "\xf0\x9f\x92\xa1 [Market Sentiment Review]\nFRED macro data unavailable"
  }

  # Verdict
  n_alerts <- sum(c(has_l1, has_l2, has_l3))
  verdict <- if (cur_category %in% c("RISK_OFF", "CRISIS")) {
    "\xf0\x9f\x94\xb4 RISK_OFF \xe2\x80\x94 \xec\xb5\x9c\xeb\x8c\x80 \xed\x97\xa4\xec\xa7\x80 \xea\xb6\x8c\xea\xb3\xa0"
  } else if (cur_category == "CAUTION") {
    sprintf("\xe2\x9a\xa0\xef\xb8\x8f CAUTION \xe2\x80\x94 %d/3 Active. Score 70 \xe2\x86\x92 RISK_OFF", n_alerts)
  } else if (cur_category == "NEUTRAL") {
    "\xf0\x9f\x94\x8d NEUTRAL \xe2\x80\x94 \xec\xa3\xbc\xec\x9d\x98 \xea\xb4\x80\xec\xb0\xb0"
  } else {
    "\xf0\x9f\x9f\xa2 RISK_ON \xe2\x80\x94 \xec\xa0\x95\xec\x83\x81 \xec\x9a\xb4\xec\x9a\xa9"
  }

  msg <- sprintf(paste0(
    "%s Regime Briefing (%s)\n\n",
    "\xf0\x9f\x93\x8a [Regime Score]\n",
    "Score: %.1f (5d %s)\n",
    "Category: %s\n\n",
    "\xf0\x9f\x94\x8d [3-Layer Signal]\n",
    "%s L1 MSM Crisis: %.1f%%\n",
    "%s L2 FRED MRS: %.1f\n",
    "%s L3 KTRI: %.1f | VEA: %.1f\n",
    "Active: %s",
    "%s\n\n",
    "\xf0\x9f\x93\x85 [Trend 5d]\n",
    "Score: %s | Crisis: %s | KTRI: %s\n\n",
    "%s\n\n",
    "\xf0\x9f\x8e\xaf [Verdict]\n%s"),
    cat_emoji, format(msg_ref_date),
    cur_score, score_trend,
    cur_category,
    l1_icon, cur_msm,
    l2_icon, cur_fred,
    l3_icon, cur_ktri, cur_vea,
    active_layers_str,
    ktri_str,
    score_trend, crisis_trend, ktri_trend,
    sentiment_str,
    verdict)

  # ── Send: text + 3 charts (v2.4 — Chart 4/5 삭제, 핵심 3종만) ──
  tg_send(msg)
  Sys.sleep(3)
  tg_send_photo(file.path(out_dir, "regime_score_24m.png"), "Daily Regime Score (12M)")
  Sys.sleep(2)
  tg_send_photo(file.path(out_dir, "regime_3layer_24m.png"), "3-Layer Signal (Month-end + Latest Daily)")
  Sys.sleep(2)
  ktri_chart <- file.path(out_dir, "ktri_9quad.png")
  if (file.exists(ktri_chart)) {
    tg_send_photo(ktri_chart, "KTRI 9-Quadrant Map (252d)")
  }

  n_charts_sent <- sum(file.exists(c(
    file.path(out_dir, "regime_score_24m.png"),
    file.path(out_dir, "regime_3layer_24m.png"),
    file.path(out_dir, "ktri_9quad.png"))))
  cat(sprintf("[regime_briefing] Sent: text + %d charts\n", n_charts_sent))
  invisible(list(regime = latest, daily = latest_daily, ktri = ktri_latest,
                 fred = fred_latest_row, ref_date = msg_ref_date, charts = out_dir))
}

cat("[telegram_notify] Loaded. Bot: @quant12323413245_bot | Channel: -1003850915447\n")
cat("[telegram_notify] +tg_trigger_check(), +tg_regime_briefing()\n")
