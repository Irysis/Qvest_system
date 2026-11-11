## round_core v3 · freshness — 측정 경로 데이터 신선도 차단(2026-11-10 · 감사 레인 E1)
##
## 왜: 측정 경로(round.sh measure · 상설 측정 · P4 기준 칸 · 걸음 측정)는 리프레시 '완료 줄'과 배리어 잠금만 봤다 — 데이터가 낡았는지는
##   아무도 재지 않았다(실측 11-10: RAWDATA 최신 = 11-06(금) · 11-09(월) 세션이 통째로 빠진 채 배리어는 free). 낡은 가격으로 잰 칸은
##   지문이 측정 앞뒤로 같아도(둘 다 낡음) 정상 측정으로 원장에 남는다.
## 무엇: rc_data_freshness(root, today) — 가격 자료(RAWDATA) · 벤치(KOSPI200)가 직전 거래일 세션까지 와 있는가를 판정한다. 측정 경로 넷이
##   이 함수 하나를 부른다(round.sh measure = driver fresh-check · standing-measure = 같은 단계 1회 + rc_standing_measure_item ·
##   p4-base-measure · p4-step-measure = .rcp4_run_cell).
## 규칙 출처(복제 없음): 아침 신선도 감사기 02_Infrastructure/ops/morning_steps/freshness_audit.R(데이터 레인 소유).
##   ① 운영(today 미지정) = 그 파일의 판정 전용 진입점 `--check --items rawdata,benchmark`(종료 0/3/1 · 발송 없음)를 자식 R 로 부른다.
##   ② 진입점이 없는 판 · 날짜를 주입한 시험 = 그 파일을 구문 트리로 읽어 정의만 꺼낸다 —
##   기준일 as_of(직전 평일 → 거래 달력 휴일 보정) · 휴장일 정본(06_Registry/krx_holidays.json) · 세션 지연 .sess_lag · 판정 check_freshness ·
##   그리고 그 파일의 audits$rawdata · audits$benchmark 호출(경로 · 열 · 달력 여유 · 세션 여유 max_sess)을 그대로 평가한다.
##   감사기 본문의 JSON 기록 · 텔레그램 발송(tg_send)은 평가하지 않는다(정의 · 그 두 호출만 · 발송 없음).
##   read_parquet 만 날짜 열만 읽는 판으로 가린다(426MB 전체 적재 대신 Date 열 — 판정 값은 같다: 쓰는 것은 그 열의 최댓값뿐).
## 판정(fail-closed): ① = 진입점 종료 0 ∧ status=FRESH 만 ok(3 = stale · 그 밖 = unreadable).
##   ② = 두 항목 모두 status = FRESH ∧ 세션 축을 실제로 쟀다(sess_lag 가 수치 · max_sess 설정) 일 때만 ok.
##   ⚠ ①은 세션 축 미측정(sess NA)을 달력 축만으로 FRESH 라 한다(감사기 계약) — ②보다 느슨하다(감사 보고 패치 제안: max_sess 설정 항목의 sess NA = unreadable).
##   STALE · MISSING · PARSE_FAIL = stale · 세션 축 미측정(휴장일 연도 미수록 등) · 정의 꺼내기 실패 · 평가 오류 = unreadable — 둘 다 측정 거부.
##   ★우회 인자 없음 — 시험은 호출자의 freshness 인자에 판정 함수를 넣는다(배리어 · 지문 주입과 같은 자리).

RC_FRESH_SOURCE <- "02_Infrastructure/ops/morning_steps/freshness_audit.R"
RC_FRESH_ITEMS  <- c("rawdata", "benchmark")
RC_FRESH_DEFS   <- c(".prev_bd", "as_of", ".cal", ".krx_hol", ".sess_lag", "check_freshness")

## 감사기 구문 트리 → 평가할 식(순서 보존): 정의 대입 · as_of 보정 if 문(audits <- list() 앞) · audits <- list() · audits$<항목> 대입
.rcf_exprs <- function(path, items) {
  ex <- parse(path, keep.source = FALSE, encoding = "UTF-8")
  lhs <- function(x) if (is.call(x) && (identical(x[[1]], as.name("<-")) || identical(x[[1]], as.name("="))) && length(x) == 3L) x[[2]] else NULL
  keep <- list(); seen_audits <- FALSE; got <- character(0)
  for (x in ex) {
    l <- lhs(x)
    if (is.name(l) && as.character(l) %in% RC_FRESH_DEFS) { keep[[length(keep) + 1L]] <- x; got <- c(got, as.character(l)); next }
    if (is.name(l) && identical(as.character(l), "audits")) { keep[[length(keep) + 1L]] <- x; seen_audits <- TRUE; next }
    if (!seen_audits && is.call(x) && identical(x[[1]], as.name("if")) && "as_of" %in% all.names(x)) { keep[[length(keep) + 1L]] <- x; next }
    if (is.call(l) && identical(l[[1]], as.name("$")) && identical(l[[2]], as.name("audits")) && as.character(l[[3]]) %in% items) {
      keep[[length(keep) + 1L]] <- x; got <- c(got, paste0("audits$", as.character(l[[3]])))
    }
  }
  miss <- setdiff(c(RC_FRESH_DEFS, paste0("audits$", items)), got)
  if (length(miss) || !seen_audits) stop("감사기 정의를 찾지 못했다(", paste(c(miss, if (!seen_audits) "audits <- list()"), collapse = ","), ") — 감사기가 바뀌었다(이 판정도 따라가야 한다)")
  keep
}
## ① 판정 전용 진입점(감사기 소유 · 11-10 데이터 레인 A 추가) — `Rscript freshness_audit.R --check --items rawdata,benchmark`
##   계약(그 파일 머리): 마지막 줄 FA_CHECK<TAB>status=FRESH|STALE|ERROR<TAB>as_of=…<TAB>stale=…<TAB>unreadable=… · 종료 0 신선 · 3 낡음 · 1 판독 불가 · 텔레그램 · JSON 없음.
##   진입점이 있는지 = 소스에 FA_CHECK · "--check" 표식. 자식 R 은 R_ENVIRON_USER = 빈 파일 · QM_ROOT = root(~/.Renviron 이 루트를 덮지 않게 · 금칙 ① 때문에 env= 대신 Sys.setenv 후 복원).
.rcf_has_check <- function(src) { t <- paste(readLines(src, warn = FALSE, encoding = "UTF-8"), collapse = "\n"); grepl("FA_CHECK", t, fixed = TRUE) && grepl("\"--check\"", t, fixed = TRUE) }
.rcf_cli <- function(src, root, items) {
  ev <- tempfile("rcf_renv_"); writeLines("", ev); on.exit(unlink(ev), add = TRUE)
  ks <- c("QM_ROOT", "R_ENVIRON_USER", "CLAUDE_PROJECT_DIR", "QVEST_FRESHNESS_CHECK", "QVEST_FRESHNESS_ITEMS"); old <- Sys.getenv(ks, unset = NA, names = TRUE)
  on.exit(for (k in ks) if (is.na(old[[k]])) Sys.unsetenv(k) else do.call(Sys.setenv, stats::setNames(list(old[[k]]), k)), add = TRUE)
  Sys.setenv(QM_ROOT = root, R_ENVIRON_USER = ev, CLAUDE_PROJECT_DIR = root); Sys.unsetenv(c("QVEST_FRESHNESS_CHECK", "QVEST_FRESHNESS_ITEMS"))
  o <- suppressWarnings(system2(file.path(R.home("bin"), "Rscript"), c("--no-save", shQuote(src), "--check", "--items", paste(items, collapse = ",")), stdout = TRUE, stderr = TRUE))
  rc <- attr(o, "status") %||% 0L; ln <- utils::tail(grep("^FA_CHECK\t", o, value = TRUE), 1L)
  kv <- if (length(ln)) { p <- strsplit(sub("^FA_CHECK\t", "", ln), "\t", fixed = TRUE)[[1]]; stats::setNames(sub("^[^=]*=", "", p), sub("=.*$", "", p)) } else character(0)
  list(rc = as.integer(rc), line = ln, kv = as.list(kv))
}
## 날짜 열만 읽는 read_parquet(판정에 쓰는 값 = 그 열의 최댓값 · 전체 적재 회피) — 날짜 열이 없으면 첫 열(→ 감사기가 PARSE_FAIL)
.rcf_read_parquet <- function(file, ...) {
  ## mmap = FALSE 필수 — Windows 는 열린 매핑이 남은 파일의 덮어쓰기를 거부한다(오류 1224 · 시험에서 실측). 판정 직후 리프레시가 RAWDATA 를 쓰면 막힐 수 있다.
  rd <- arrow::ParquetFileReader$create(file, mmap = FALSE); nm <- rd$GetSchema()$names; rm(rd)
  cs <- intersect(nm, c("Date", "DATE", "date")); if (!length(cs)) cs <- nm[1]
  x <- arrow::read_parquet(file, col_select = tidyselect::all_of(cs), mmap = FALSE); invisible(gc(verbose = FALSE)); x
}

#' 데이터 신선도 판정 — 반환 list(ok, state = fresh | stale | unreadable, as_of, today, items(항목별 감사 기록), reason, source, source_md5)
rc_data_freshness <- function(root = rc_root(), today = NULL, items = RC_FRESH_ITEMS) {
  src <- file.path(root, RC_FRESH_SOURCE); today_in <- today; today <- as.Date(today %||% Sys.Date())
  out <- function(state, reason, as_of = NA_character_, recs = list())
    list(ok = identical(state, "fresh"), state = state, as_of = as.character(as_of), today = format(today), items = recs, reason = reason,
         source = RC_FRESH_SOURCE, source_md5 = if (file.exists(src)) rc_md5(src) else NA_character_)
  if (!file.exists(src)) return(out("unreadable", paste0("신선도 감사기 없음: ", RC_FRESH_SOURCE)))
  ## ① 오늘 날짜 판정(운영 기본)이고 진입점이 있으면 그것을 부른다 · ② 날짜를 주입한 호출(시험) · 진입점이 없는 판은 정의를 꺼내 평가한다
  if (is.null(today_in) && .rcf_has_check(src)) {
    r <- tryCatch(.rcf_cli(src, root, items), error = function(e) list(rc = -1L, line = character(0), kv = list(), err = conditionMessage(e)))
    kv <- r$kv; ao <- kv$as_of %||% NA_character_
    rs <- sprintf("[감사기 --check] status=%s · 기준일 %s · 낡음 %s · 판독 불가 %s", kv$status %||% "?", ao, kv$stale %||% "?", kv$unreadable %||% "?")
    if (!length(r$line)) return(out("unreadable", paste0("감사기 --check 출력 판독 불가(rc ", r$rc, ")", if (!is.null(r$err)) paste0(" · ", r$err) else "")))
    st <- if (identical(r$rc, 0L) && identical(kv$status, "FRESH")) "fresh" else if (identical(r$rc, 3L) && identical(kv$status, "STALE")) "stale" else "unreadable"
    return(out(st, rs, ao, list(stale = kv$stale, unreadable = kv$unreadable, via = "check", rc = r$rc)))
  }
  ## ② 진입점이 아직 없으면 그 파일의 판정 정의를 꺼내 평가한다
  ex <- tryCatch(.rcf_exprs(src, items), error = function(e) e)
  if (inherits(ex, "error")) return(out("unreadable", paste0("신선도 규칙 판독 불가 — ", conditionMessage(ex))))
  e <- new.env(parent = globalenv()); e$today <- today; e$read_parquet <- .rcf_read_parquet
  e$.fa_items <- items; e$FA_CHECK <- TRUE        # 감사기의 항목 선택(--items)과 같은 뜻 — 꺼낸 check_freshness 가 이 두 이름을 본다(없는 판이면 무시된다)
  e$`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
  wd <- getwd(); on.exit(setwd(wd), add = TRUE)
  r <- tryCatch({ setwd(root); for (x in ex) eval(x, envir = e); NULL }, error = function(z) z)
  if (inherits(r, "error")) return(out("unreadable", paste0("신선도 판정 평가 오류: ", conditionMessage(r))))
  recs <- lapply(items, function(k) e$audits[[k]]); names(recs) <- items
  bad <- character(0); unk <- character(0)
  for (k in items) {
    a <- recs[[k]]
    if (!is.list(a) || is.null(a$status)) { unk <- c(unk, sprintf("%s: 감사 기록 없음", k)); next }
    if (!identical(a$status, "FRESH")) { bad <- c(bad, sprintf("%s %s(최신 %s · 기준일 %s · 달력 지연 %s일 · 세션 지연 %s)", k, a$status, a$last_date %||% "?",
                                                         format(e$as_of), a$lag_days %||% "?", if (is.null(a$sess_lag) || is.na(a$sess_lag)) "?" else a$sess_lag)); next }
    if (is.null(a$max_sess) || is.null(a$sess_lag) || is.na(a$sess_lag))
      unk <- c(unk, sprintf("%s: 거래 세션 축 미측정(휴장일 정본 연도 미수록 · max_sess 미설정) — 직전 거래일 도달을 확인할 수 없다", k))
  }
  if (length(bad)) return(out("stale", paste0("데이터 낡음 — ", paste(bad, collapse = " · ")), e$as_of, recs))
  if (length(unk)) return(out("unreadable", paste0("신선도 판독 불가 — ", paste(unk, collapse = " · ")), e$as_of, recs))
  out("fresh", sprintf("직전 거래일(%s) 세션까지 도달 — %s", format(e$as_of), paste(sprintf("%s 최신 %s", items, vapply(recs, function(a) a$last_date %||% "?", "")), collapse = " · ")),
      e$as_of, recs)
}
## 측정 직전 공통 판정(호출자 주입 · 오류 = 판독 불가) — 반환 = rc_data_freshness 모양
rc_fresh_gate <- function(freshness, root) {
  f <- tryCatch(freshness(root), error = function(e) list(ok = FALSE, state = "unreadable", reason = paste("신선도 판정 오류:", conditionMessage(e))))
  if (!is.list(f) || !is.logical(f$ok) || length(f$ok) != 1L) f <- list(ok = FALSE, state = "unreadable", reason = "신선도 판정 반환 모양 오류")
  if (!isTRUE(f$ok) && !(f$state %||% "") %in% c("stale", "unreadable")) f$state <- "unreadable"
  f
}
