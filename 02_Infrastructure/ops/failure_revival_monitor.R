# failure_revival_monitor.R — 실패 지식 재부상(anti-ossification) live 트리거 모니터
#
# 계획서 G (2026-07-04, failure_knowledge_architecture_plan_20260704.md):
#   원리4 "영구 판결 없음 — live 트리거로 자동 부활". 시장은 순환(value 死→生).
#   휴면 실패 지식(distilled/proposed negative DIST)의 live_trigger를 현 상태와 대조해
#   충족분을 시스템이 *먼저* un-bury 한다. 발화분 → .cache/failure_revival_flags.json.
#
# ★핵심 설계 (도훈 mandate — "하드코딩된 멍청이가 아닌 발전하는 아키텍처"):
#   트리거 type을 코드에 하드코딩(switch(type, regime=..., spread=..., time=...))하지 않는다.
#   신호원 레지스트리(06_Registry/revival_signals.json) 경유:
#     - DIST의 live_trigger = {signal_id, condition}.
#     - signal_id가 레지스트리에 있으면 그 extractor(kind)로 현재값 로드 → condition 대조.
#     - 없으면 graceful skip(신호원 미등록 — 추후 레지스트리에 add만 하면 자동 소비).
#   → 새 신호원 추가 = 레지스트리 항목 1개 등록(코드 수정 불필요). 열린 스키마.
#   generic 로더는 kind별로만 존재(신규 kind만 loader 추가, 개별 signal_id는 불필요).
#
# fail-soft: 어떤 실패(파일 없음·parse 실패·신호원 부재·condition 오류)도 전체를 중단시키지
#   않는다. 발화 0건도 정상(휴면 실패의 트리거 미충족 = 재도전 시점 미도달).
#
# 인라인 Rscript -e 한글 리터럴 금지(코드페이지 SIGSEGV) — 본 파일은 UTF-8로 read.
#   호출: Rscript --no-save -e 'source("02_Infrastructure/ops/failure_revival_monitor.R")'
#   또는 함수 직접: revival_monitor_run().

suppressWarnings(suppressMessages({
  suppressPackageStartupMessages(library(jsonlite))
}))

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0 || (length(a) == 1 && is.na(a))) b else a

.rev_root <- function() {
  cands <- c(Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""),
             "C:/Users/99922/OneDrive/Quant_Module_Moltbot", getwd())
  for (p in cands) if (nzchar(p) && dir.exists(p)) return(p)
  getwd()
}

.rev_registry_path <- function(root) file.path(root, "06_Registry", "revival_signals.json")
.rev_dist_dir      <- function(root) file.path(root, "qepm", "memory", "axioms", "distilled")
.rev_flags_path    <- function(root) file.path(root, ".cache", "failure_revival_flags.json")
.rev_history_path  <- function(root) file.path(root, ".cache", "failure_revival_history.jsonl")

# ── 레지스트리 로드 ─────────────────────────────────────────────────────────
.rev_load_registry <- function(root) {
  rp <- .rev_registry_path(root)
  if (!file.exists(rp)) return(list())
  reg <- tryCatch(fromJSON(rp, simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(reg)) return(list())
  sigs <- reg$signals %||% list()
  # signal_id -> spec 맵으로 정규화(active 만).
  out <- list()
  for (s in sigs) {
    sid <- s$signal_id %||% NA
    if (is.na(sid) || !nzchar(sid)) next
    if (!identical(s$status %||% "active", "active")) next
    out[[sid]] <- s
  }
  out
}

# ── generic 신호값 로더 (kind별. signal_id 별 분기 없음 — 열린 스키마) ────────
# 반환: list(ok=TRUE/FALSE, value=<현재값>, note=<진단>).
.rev_read_parquet <- function(path, cols = NULL) {
  # OneDrive/Windows arrow 안정화: 단일 IO 스레드(parquet read HANG 방지 —
  #   [[project-ramp-fullcycle-graduation]] set_io_thread_count(1)이 HANG 해소책).
  #   arrow가 num_threads<2 경고를 내지만 본 monitor는 소형 신호 parquet만 읽어 무해 → suppress.
  if (!requireNamespace("arrow", quietly = TRUE)) return(NULL)
  suppressWarnings(tryCatch(arrow::set_io_thread_count(1L), error = function(e) NULL))
  suppressWarnings(tryCatch({
    if (is.null(cols)) arrow::read_parquet(path)
    else arrow::read_parquet(path, col_select = dplyr::all_of(cols))
  }, error = function(e) {
    # col_select 실패(컬럼 부재 등) 시 전체 read 폴백.
    tryCatch(arrow::read_parquet(path), error = function(e2) NULL)
  }))
}

.rev_extract_value <- function(spec, root) {
  kind <- spec$kind %||% ""
  if (identical(kind, "time_now")) {
    return(list(ok = TRUE, value = Sys.Date(), note = "wall clock"))
  }
  sp <- spec$source_path %||% NA
  # file_exists: source_path 파일 존재 여부를 value=TRUE/FALSE로 반환(데이터 도착 트리거용).
  #   부재 자체가 유효한 신호값(FALSE) — 다른 kind와 달리 파일 없음이 ok=FALSE(로드 실패)가 아니다.
  if (identical(kind, "file_exists")) {
    if (is.na(sp) || !nzchar(sp)) return(list(ok = FALSE, value = NULL, note = "source_path 없음(file_exists)"))
    path <- if (grepl("^([A-Za-z]:|/|\\\\)", sp)) sp else file.path(root, sp)
    ex <- file.exists(path)
    return(list(ok = TRUE, value = ex, note = sprintf("file_exists(%s)=%s", sp, ex)))
  }
  if (is.na(sp) || !nzchar(sp)) return(list(ok = FALSE, value = NULL, note = "source_path 없음"))
  path <- if (grepl("^([A-Za-z]:|/|\\\\)", sp)) sp else file.path(root, sp)
  if (!file.exists(path)) return(list(ok = FALSE, value = NULL, note = sprintf("source 파일 없음: %s", sp)))

  if (kind %in% c("parquet_last", "parquet_percentile")) {
    vcol <- spec$value_col %||% NA
    if (is.na(vcol)) return(list(ok = FALSE, value = NULL, note = "value_col 없음"))
    df <- .rev_read_parquet(path)
    if (is.null(df)) return(list(ok = FALSE, value = NULL, note = "parquet read 실패(arrow 부재/오류)"))
    if (!(vcol %in% names(df))) return(list(ok = FALSE, value = NULL, note = sprintf("value_col '%s' 부재", vcol)))
    # 정렬: sort_col 지정 or 자동추론(Date/date/YM).
    sc <- spec$sort_col %||% NA
    if (is.na(sc)) { for (c in c("Date", "date", "YM")) if (c %in% names(df)) { sc <- c; break } }
    if (!is.na(sc) && sc %in% names(df)) {
      df <- df[order(df[[sc]]), , drop = FALSE]
    }
    vals <- df[[vcol]]
    vals <- vals[!is.na(vals)]
    if (!length(vals)) return(list(ok = FALSE, value = NULL, note = "value_col 전부 NA"))
    if (identical(kind, "parquet_last")) {
      return(list(ok = TRUE, value = vals[length(vals)], note = sprintf("last of %s", vcol)))
    } else {
      # percentile: 현재(마지막) 값의 전체(or window) 대비 백분위(0~1).
      w <- spec$window %||% NA
      series <- if (!is.na(w) && is.numeric(vals) && length(vals) > w) tail(vals, as.integer(w)) else vals
      cur <- vals[length(vals)]
      if (!is.numeric(series)) return(list(ok = FALSE, value = NULL, note = "percentile은 numeric만"))
      pct <- mean(series <= cur)
      return(list(ok = TRUE, value = pct, note = sprintf("percentile of %s (cur=%.4g)", vcol, cur)))
    }
  }

  if (identical(kind, "json_field")) {
    fp <- spec$field_path %||% NA
    if (is.na(fp)) return(list(ok = FALSE, value = NULL, note = "field_path 없음"))
    j <- tryCatch(fromJSON(path, simplifyVector = TRUE), error = function(e) NULL)
    if (is.null(j)) return(list(ok = FALSE, value = NULL, note = "json read 실패"))
    cur <- j
    for (k in strsplit(fp, ".", fixed = TRUE)[[1]]) {
      cur <- tryCatch(cur[[k]], error = function(e) NULL)
      if (is.null(cur)) return(list(ok = FALSE, value = NULL, note = sprintf("field_path '%s' 부재", fp)))
    }
    return(list(ok = TRUE, value = cur, note = fp))
  }

  list(ok = FALSE, value = NULL, note = sprintf("미지원 kind: '%s' (loader 추가 필요)", kind))
}

# ── condition 안전 평가 (화이트리스트) ──────────────────────────────────────
# condition은 로드값을 'x'로 참조하는 비교/논리 표현식. 임의 함수 호출 차단.
.rev_eval_condition <- function(condition, x) {
  if (is.null(condition) || !nzchar(condition)) return(list(fired = FALSE, note = "condition 없음"))
  # 허용 토큰만: x, 숫자/문자 리터럴, 비교/논리 연산(%in% 포함), as.Date, Sys.Date, 백분위 소수, 괄호.
  #   c() = 순수 벡터 생성자(부작용 無) — regime set-membership 'x %in% c(...)' 관용구 지원(2026-07-05
  #   배선: draft_proposed 자동생성이 regime condition을 c(...)로 emit하는데 whitelist 누락 시 미발화).
  allow_fns <- c("c", "as.Date", "Sys.Date", "as.numeric", "as.character")
  # 위험 패턴 차단: system/file/source/<-/(정의되지 않은 함수 호출).
  bad <- "system|file\\.|readLines|source\\(|eval\\(|parse\\(|<-|`|\\$|::|library|require|unlink|write"
  if (grepl(bad, condition)) return(list(fired = FALSE, note = "condition 안전 위반 — 차단"))
  # 함수 호출 토큰 추출 후 화이트리스트 밖이면 차단.
  calls <- regmatches(condition, gregexpr("[A-Za-z_][A-Za-z0-9_.]*\\s*\\(", condition))[[1]]
  calls <- gsub("\\s*\\($", "", calls)
  for (fn in calls) if (!(fn %in% allow_fns)) return(list(fired = FALSE, note = sprintf("허용 안 된 함수: %s", fn)))
  env <- new.env(parent = baseenv())
  env$x <- x
  res <- tryCatch(eval(parse(text = condition), envir = env),
                  error = function(e) structure(FALSE, note = conditionMessage(e)))
  fired <- isTRUE(as.logical(res)[1])
  list(fired = fired, note = sprintf("x=%s → %s", format(x), if (fired) "TRUE" else "FALSE"))
}

# ── DIST 수집: distilled ∨ proposed ∧ negative ∧ live_trigger 有 ─────────────
.rev_collect_dists <- function(root) {
  dd <- .rev_dist_dir(root)
  if (!dir.exists(dd)) return(list())
  files <- list.files(dd, pattern = "^DIST-.*\\.json$", full.names = TRUE)
  out <- list()
  for (f in files) {
    d <- tryCatch(fromJSON(f, simplifyVector = FALSE), error = function(e) NULL)
    if (is.null(d)) next
    st <- d$status %||% ""
    if (!(st %in% c("distilled", "proposed"))) next
    if (!identical(d$polarity %||% "", "negative")) next
    lt <- d$live_trigger

    # ── revival_spec (신규 machine 소스, 2026-07-05 구현 A) ────────────────────
    #   revival_spec = 배열. 각 원소 = {signal_id, condition, from_trigger, status('active'|'pending')}.
    #   draft_proposed가 live_trigger(산문)+expiry로 자동생성한다(병렬 작업 — 이 monitor는 소비만).
    #   revival_spec이 있으면 그것을 machine 소스로 사용. 없으면 하위호환 단일객체 live_trigger 경로.
    #   ★ live_trigger(산문 배열/객체)는 절대 변경하지 않는다 — inject/search 표시용으로 그대로 둔다.
    rspec_raw <- d$revival_spec
    rspec <- list()
    if (!is.null(rspec_raw)) {
      # jsonlite simplifyVector=FALSE → list of lists. 단일객체가 아닌 배열만 정상.
      elems <- if (is.list(rspec_raw) && !is.null(rspec_raw$signal_id)) list(rspec_raw) else rspec_raw
      for (el in elems) {
        if (!is.list(el)) next
        esid  <- el$signal_id %||% NA
        econd <- el$condition %||% NA
        est   <- el$status %||% "active"
        eft   <- el$from_trigger %||% NA
        if (is.na(esid) || !nzchar(esid)) next   # signal_id 없는 원소 무효
        rspec[[length(rspec) + 1L]] <- list(
          signal_id = esid, condition = econd, status = est, from_trigger = eft)
      }
    }
    has_rspec <- length(rspec) > 0L

    # ── 하위호환: 단일객체 live_trigger {signal_id, condition} (revival_spec 부재 시만 사용) ──
    #   (2026-07-05 감사) 실제 DIST 다수는 live_trigger가 배열-산문형(원소 키=type/condition/monitored_source,
    #   signal_id 없음)이라 기계평가 불가 → has_machine_spec=FALSE로 표식(가시화).
    #   단 expiry 기반 시간 부활(만료 도달=재검토)은 live_trigger 형태 무관하게 아래 run에서 작동.
    sid  <- if (is.list(lt) && !is.null(lt$signal_id)) (lt$signal_id %||% NA) else NA
    cond <- if (is.list(lt) && !is.null(lt$condition)) (lt$condition %||% NA) else NA
    has_machine <- has_rspec || !(is.na(sid) || !nzchar(sid) || is.na(cond) || !nzchar(cond))
    exp0 <- d$expiry %||% NA
    if (is.null(lt) && !has_rspec && is.na(exp0)) next   # 부활 근거(트리거/spec/만료) 전무 → skip
    out[[length(out) + 1L]] <- list(
      dist_id = d$dist_id %||% basename(f),
      status = st,
      signal_id = sid,
      condition = cond,
      revival_spec = rspec,
      has_revival_spec = has_rspec,
      has_machine_spec = has_machine,
      has_live_trigger = !is.null(lt),
      frontier = d$frontier %||% NULL,
      statement = d$statement_refined %||% d$statement_draft %||% "",
      expiry = exp0)
  }
  out
}

# ── 메인 ────────────────────────────────────────────────────────────────────
revival_monitor_run <- function(root = .rev_root(), write_flags = TRUE, verbose = TRUE) {
  res <- tryCatch({
    reg   <- .rev_load_registry(root)
    dists <- .rev_collect_dists(root)
    fired <- list()
    checked <- 0L; skipped_no_signal <- 0L; needs_machine <- 0L; n_pending <- 0L

    # 신호값 캐시(같은 signal_id 재로드 방지).
    val_cache <- list()
    .get_val <- function(sid) {
      if (is.null(val_cache[[sid]])) val_cache[[sid]] <<- .rev_extract_value(reg[[sid]], root)
      val_cache[[sid]]
    }

    for (dc in dists) {
      fr <- dc$frontier
      fr_txt <- if (is.null(fr)) "(frontier 미기록)" else paste(unlist(fr), collapse = " | ")
      stmt <- substr(gsub("[\r\n]+", " ", dc$statement), 1, 200)

      # revival_spec에 from_trigger='expiry' 원소가 있으면 expiry는 그 경로로 일원화(중복발화 방지).
      #   없을 때만 아래 (A) 직접 expiry 폴백 발화가 작동.
      rspec <- dc$revival_spec %||% list()
      has_rspec_expiry <- FALSE
      if (length(rspec)) {
        for (el in rspec) if (identical(el$from_trigger %||% "", "expiry")) { has_rspec_expiry <- TRUE; break }
      }

      # (A) expiry 기반 보편 부활(폴백) — revival_spec에 expiry 원소가 없을 때만 직접 발화.
      #   모든 negative DIST가 갖는 기계필드(expiry)를 직접 평가 → 산문 파싱 없이 확실히 작동.
      if (!is.na(dc$expiry) && !has_rspec_expiry) {
        ed <- tryCatch(as.Date(dc$expiry), error = function(e) NA)
        if (!is.na(ed) && Sys.Date() >= ed) {
          fired[[length(fired) + 1L]] <- list(
            dist_id = dc$dist_id, status = dc$status, signal_id = "expiry",
            condition = sprintf("Sys.Date() >= %s", dc$expiry),
            current_value = format(Sys.Date()), frontier = fr_txt, statement = stmt,
            expiry = as.character(dc$expiry),
            note = "expiry 도달 → 재검토 시점(휴면 실패 재부상)",
            source = "expiry_direct",
            detected_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"))
        }
      }

      # (B1) revival_spec 배열 소비(신규 machine 경로, 2026-07-05 구현 A) ─────────
      #   각 원소 signal_id → 명부 resolve → 값 로드 → condition eval → 발화.
      #   status='pending' 원소는 skip하되 n_pending 카운트+로그로 가시화(조용한 소실 금지).
      if (length(rspec)) {
        for (el in rspec) {
          if (identical(el$status %||% "active", "pending")) { n_pending <- n_pending + 1L; next }
          esid  <- el$signal_id
          econd <- el$condition %||% NA
          checked <- checked + 1L
          if (is.null(reg[[esid]])) { skipped_no_signal <- skipped_no_signal + 1L; next }  # 미등록 → skip
          if (is.na(econd) || !nzchar(econd)) next   # condition 없는 원소 무발화
          ext <- .get_val(esid)
          if (!isTRUE(ext$ok)) next   # 신호원 로드 실패 → fail-soft skip
          ev <- .rev_eval_condition(econd, ext$value)
          if (isTRUE(ev$fired)) {
            fired[[length(fired) + 1L]] <- list(
              dist_id = dc$dist_id, status = dc$status, signal_id = esid,
              condition = econd, from_trigger = el$from_trigger %||% NA,
              current_value = format(ext$value), frontier = fr_txt, statement = stmt,
              expiry = as.character(dc$expiry), note = ev$note,
              source = "revival_spec",
              detected_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"))
          }
        }
        next   # revival_spec이 machine 소스 — 하위호환 단일 live_trigger 경로 건너뜀
      }

      # (B2) 하위호환: 단일객체 live_trigger {signal_id, condition} (revival_spec 부재 시만).
      #   산문-배열형은 기계spec 부재로 가시화(조용한 소실 금지).
      if (!isTRUE(dc$has_machine_spec)) {
        if (isTRUE(dc$has_live_trigger)) needs_machine <- needs_machine + 1L
        next
      }
      checked <- checked + 1L
      sid <- dc$signal_id
      if (is.null(reg[[sid]])) { skipped_no_signal <- skipped_no_signal + 1L; next }  # 미등록 → skip
      ext <- .get_val(sid)
      if (!isTRUE(ext$ok)) next   # 신호원 로드 실패 → 조용히 skip(fail-soft)
      ev <- .rev_eval_condition(dc$condition, ext$value)
      if (isTRUE(ev$fired)) {
        fired[[length(fired) + 1L]] <- list(
          dist_id = dc$dist_id,
          status = dc$status,
          signal_id = sid,
          condition = dc$condition,
          current_value = format(ext$value),
          frontier = fr_txt,
          statement = stmt,
          expiry = as.character(dc$expiry),
          note = ev$note,
          source = "live_trigger_legacy",
          detected_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"))
      }
    }

    payload <- list(
      schema_version = "failure_revival_flags_v1",
      generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
      note = paste0("failure_revival_monitor.R 산출 — distilled/proposed negative DIST의 expiry + revival_spec/live_trigger를 ",
                    "revival_signals 레지스트리 경유 평가한 발화 목록. 발화 = 봉투 안 frontier 재도전 시점 도달. ",
                    "n_needs_machine_spec = live_trigger가 산문-배열형이며 revival_spec 미생성이라 기계 spec 미배선 건수. ",
                    "n_pending_spec = revival_spec 원소 중 참조 signal_id가 명부 pending 스텁이라 감시 미배선 건수."),
      n_dists_with_trigger = checked,
      n_skipped_unregistered = skipped_no_signal,
      n_needs_machine_spec = needs_machine,
      n_pending_spec = n_pending,
      n_fired = length(fired),
      fired = fired)

    if (write_flags) {
      fp <- .rev_flags_path(root)
      dir.create(dirname(fp), showWarnings = FALSE, recursive = TRUE)
      write_json(payload, fp, pretty = TRUE, auto_unbox = TRUE, null = "null")
      # 발화 이력 append-only 보존(JSONL 1행=1발화·detected_at 포함) — flags는 매 실행
      #   덮어쓰기라 최초 발화일/재발 여부(지속기간) 감사가 불가하던 것을 이력으로 보완.
      if (length(fired)) {
        tryCatch({
          hp <- .rev_history_path(root)
          dir.create(dirname(hp), showWarnings = FALSE, recursive = TRUE)
          con <- file(hp, open = "a", encoding = "UTF-8")
          try(for (fd in fired)
            writeLines(as.character(toJSON(fd, auto_unbox = TRUE, null = "null")), con),
            silent = TRUE)
          close(con)   # try 후 무조건 close — 커넥션 누수 방지
        }, error = function(e) NULL)   # 이력 실패는 본 산출(flags)에 영향 없음(fail-soft)
      }
    }

    if (verbose) {
      cat(sprintf("[revival-monitor] 기계트리거 %d건 검사 · 미등록신호 skip %d · pending spec %d · 산문트리거(기계spec 부재) %d · 발화 %d건\n",
                  checked, skipped_no_signal, n_pending, needs_machine, length(fired)))
      if (needs_machine > 0L)
        cat(sprintf("      ⚠ %d개 negative DIST의 live_trigger가 산문-배열형(revival_spec 미생성) — 자동감시 미배선(expiry 부활만 작동). draft_proposed 자동생성 필요.\n", needs_machine))
      if (n_pending > 0L)
        cat(sprintf("      ⚠ revival_spec 원소 %d개가 pending(참조 signal_id 명부 미확정 스텁) — 신호원 확정 시 자동 활성화.\n", n_pending))
      for (fd in fired) {
        cat(sprintf("  · %s [%s] signal=%s cond='%s' (현재 %s) → 재도전 권고\n",
                    fd$dist_id, fd$status, fd$signal_id, fd$condition, fd$current_value))
        cat(sprintf("      frontier: %s\n", fd$frontier))
      }
    }
    payload
  }, error = function(e) {
    if (verbose) cat(sprintf("[revival-monitor] 실패(fail-soft): %s\n", conditionMessage(e)))
    invisible(list(schema_version = "failure_revival_flags_v1", n_fired = 0L, fired = list(),
                   error = conditionMessage(e)))
  })
  invisible(res)
}

# 자동 실행 정책:
#   - `local = TRUE` source(예: axiom_approval_queue.R)는 revival_monitor_run()을 *직접* 호출하므로
#     자동실행 억제(옵션 rev_no_autorun=TRUE). 이중 실행 방지.
#   - 그 외 top-level source() / CLI Rscript = 1회 자동 실행(모닝브리핑 독립 스텝 패턴).
if (!isTRUE(getOption("rev_no_autorun", FALSE))) {
  revival_monitor_run()
}
