#!/usr/bin/env Rscript
## regime_append_only.R — 국면 계열 append-only 원장 (도훈 지시 2026-08-13 "1번 가자")
##
## **왜 필요한가**: 재서술의 원천이 둘인데 코드 수리는 하나만 닫는다.
##   내부 생성 — MSM 전체표본 디민(commit b514830e 수리) · 파라미터 mtime 선택 · 기타 전체표본 통계
##   외부 개정 — **FRED 가 시계열을 소급 개정한다**. 핀 스냅샷 실측(2026-08-13):
##     2026-07-16 핀 → 2026-08 핀   과거 1,521셀
##     2026-09 핀   → 라이브        과거 **3,000셀** (Chi_Fin_Cond 1,320 · StL_Fin_Stress 1,361 ·
##                                   US_M2 312, 최초 개정일 2000-01-07 = 26년 전 값까지)
##   후자는 우리 코드의 결함이 아니라 외부 사실이라 **어떤 코드 수리로도 제거되지 않는다**.
##   그리고 FRED 는 Regime_Score = layer1 + **0.35*FRED_MRS** + layer3 로 합성의 35%다.
##   ⇒ 외부 개정을 막는 층은 코드가 아니라 **발행 원장(append-only)** 뿐이다.
##   m4 는 m4_append_only.R 로 보호되는데 정작 **그 상류인 국면 계열이 무방비**였다.
##
## **국면 계열 고유 조건 — 진행 중인 구간은 동결하지 않는다**:
##   월간 계열은 월말 날짜로 스탬프되는데 마지막 행이 **진행 중인 달**이다(실측: 오늘 2026-08-13
##   기준 2026-08-31 행 존재). 그 행은 매일 갱신되는 게 정상이므로 동결 대상이 아니다.
##   완료 경계 = 월간이면 현재월 1일, 일간이면 오늘. 그 이전 행만 동결한다.
##   ★이걸 안 나누면 "정상 갱신"을 재서술로 오탐해 매일 차단이 걸린다.
##
## ── ★PIT C11 원장 경로 (2026-09-25 · 판정서 04_Research/01_reports/pit_c11_20260924/ · 결정 PIT-C11-REMEDIATION 안 B) ──
##   구판의 결함 3종(실측 2026-09-24):
##   ① 병합 `live[Date > ft_prev, .SD, .SDcols = names(pub)]` 가 발행본(구 스키마)의 열 목록으로 잘라
##      생산자 표식 계약(행 열 avail_date(Date) · c11_regime_key · 파일 속성 c11_avail_regime_key)을 **매일 삭제**했다
##      → 00:03 이후 라이브는 소비자 C11 가드(overlay_pit_guard c11_panel_status)에 legacy 로 보였다.
##   ② 아침 fred_regime.R 은 원장을 거치지 않고 새 코드로 전 이력을 다시 빌드해 **라이브를 덮었다**
##      → 00:03 = 구 발행본 이력 / 07:10 = 새 코드 이력으로 하루 두 번 교대.
##   ③ C11 이전 epoch 발행본과 C11 epoch 재생성본을 **말없이 이어 붙였다**(구 이력 + 신 꼬리 = 혼합 원장).
##   수리:
##   ① 병합은 후보(생산자 산출)의 스키마·파일 속성을 보존한다. 동결 구간 재서술 검출 규칙(결정값 3열 · 수치 1e-9 ·
##      문자 불일치)은 그대로이고, 같은 규칙을 가용일 열(avail_date)에도 건다(동결 행의 가용일 재서술 = 결정값 재서술).
##   ② 라이브를 쓰는 곳은 원장 병합 하나다 — 재생성본은 후보 경로(.cache/_regime_candidate/)로만 쓴다
##      (regime_ledger_rebuild_publish · --from-candidate). 후보가 없거나 병합이 거부되면 라이브는 그대로 둔다(fail-closed).
##   ③ epoch 가 다르면(발행본 legacy ↔ 후보 C11 · 또는 규칙 키 변경) 병합하지 않고 종료 3 — 재기준선은
##      regime_ledger_republish(dry-run 기본 · --execute 명시)로만: 구 발행 원장 전량을
##      06_Registry/regime_published/_archive_pre_c11_<YYYYMMDD>/ 로 보관(sha256 대조)한 뒤 현행 epoch 판으로 재초기화.
##   ★동결은 되돌리지 않는다: frozen_through 는 단조(과거 --as-of 재실행이 동결 경계를 뒤로 물리지 못한다).
##
## 사용(CLI):
##   Rscript regime_append_only.R [--series monthly|daily] [--as-of YYYY-MM-DD] [--root DIR]
##                                [--candidate PATH | --from-candidate] [--init] [--dry-run]
##   Rscript regime_append_only.R --republish [--series monthly|daily|all] [--rebuild | --candidate-monthly P --candidate-daily P]
##                                [--archive-dir DIR] [--plan-out FILE] [--expect-plan FILE] [--execute]
##     권장 순서: ① --republish --rebuild --plan-out P (dry-run · 후보 = .cache/_regime_candidate/) → 검토
##               ② --republish --candidate-monthly <①후보> --candidate-daily <①후보> --expect-plan P --execute
##   Rscript regime_append_only.R --restore ARCHIVE_DIR [--execute]
## 종료: 0 정상 / 1 동결행 결정값 재서술 검출(발행본 보존) / 2 입력·환경 오류 / 3 epoch 불일치(무기록 — 재기준선 필요)
## 라이브러리: source() 하면 CLI 는 돌지 않고 regime_ledger_* 함수만 정의된다(호출자 전역을 덮지 않게 전부 접두 .rl_ / regime_ledger_).

## ★★arrow 교착 방어 — `ARROW_IO_THREADS=1` ∧ `mmap=FALSE` 에서만 read_parquet 가 자기 교착한다
##   (2026-08-13 2×3 격자 실측. 상세 = m4_append_only.R 상단). 이 스크립트도 mmap=FALSE 를 쓰므로
##   호출자가 =1 을 걸면 daily_refresh 가 조용히 멈춘다. 저장소 관행(reports/ 15개)대로 2로 올린다.
if (suppressWarnings(as.integer(Sys.getenv("ARROW_IO_THREADS", "0"))) %in% 1L) Sys.setenv(ARROW_IO_THREADS = "2")
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)})
try(if (arrow::io_thread_count() < 2L) arrow::set_io_thread_count(2L), silent = TRUE)

## 2계층: 결정값이 바뀌면 차단, 입력값 이동은 로그 (m4_append_only.R 와 같은 규약)
REGIME_LEDGER_DECISION_COLS <- c("Regime_Score", "Category", "Cash_Pct")
REGIME_LEDGER_INPUT_COLS    <- c("MSM_Crisis_Prob", "FRED_MRS", "KTRI_Score", "VEA_Score")
## C11 표식 계약(overlay_pit_guard.R C11 층 · regime_signal.R r1): 가용일 열 + epoch 키 열 + 파일 속성
REGIME_LEDGER_AVAIL_COLS    <- c("avail_date")
REGIME_LEDGER_KEY_COL       <- "c11_regime_key"
REGIME_LEDGER_KEY_ATTR      <- "c11_avail_regime_key"
REGIME_LEDGER_ARCHIVE_TAG   <- "pre_c11"

`%||rl%` <- function(a, b) if (is.null(a)) b else a
.rl_say <- function(verbose, ...) if (isTRUE(verbose)) cat(sprintf(...))
.rl_root <- function(root = NULL) {
  r <- if (length(root) == 1L && !is.na(root) && nzchar(root)) root else
    Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
  gsub("\\\\", "/", r)
}
.rl_series_ok <- function(series) {
  if (!(length(series) == 1L && series %in% c("monthly", "daily"))) stop("[regime-append] --series 는 monthly|daily")
  series
}

regime_ledger_paths <- function(series, root = NULL) {
  .rl_series_ok(series); root <- .rl_root(root)
  live_base <- if (series == "monthly") "unified_regime_signal.parquet" else "unified_regime_signal_daily.parquet"
  pubdir <- file.path(root, "06_Registry/regime_published")
  list(root   = root,
       live   = file.path(root, ".cache", live_base),
       cand   = file.path(root, ".cache", "_regime_candidate", live_base),
       pubdir = pubdir,
       pub    = file.path(pubdir, sprintf("regime_signal_%s_published.parquet", series)),
       meta   = file.path(pubdir, sprintf("regime_signal_%s_meta.json", series)),
       side   = file.path(pubdir, sprintf("regime_signal_%s_ledger.jsonl", series)),
       dlog   = file.path(pubdir, "regime_drift_log.jsonl"))
}

## 후보 경로 — 재생성본은 여기에만 쓴다(라이브 파일명과 같은 basename: regime_signal.R 의 regime_current.json
##   발행 조건(basename)이 그대로 성립). fresh=TRUE 는 직전 실행의 잔재 후보를 지운다 — 빌드가 실패했는데
##   어제 후보가 병합되는 일을 막는다(후보 부재 = 병합 없음 = 라이브 불변).
regime_ledger_candidate_paths <- function(root = NULL, fresh = FALSE) {
  p <- list(monthly = regime_ledger_paths("monthly", root)$cand, daily = regime_ledger_paths("daily", root)$cand)
  if (isTRUE(fresh)) for (f in unlist(p)) if (file.exists(f)) {
    if (!isTRUE(file.remove(f))) stop("[regime-append] 잔재 후보 삭제 실패(잠금?): ", f)
  }
  dir.create(dirname(p$monthly), recursive = TRUE, showWarnings = FALSE)
  p
}

## 원자적 쓰기 정본(02_Infrastructure/utils/atomic_parquet.R · atomic_json.R)을 격리 env 로 적재
.rl_util_env <- function(root) {
  e <- new.env(parent = globalenv())
  for (f in c("atomic_parquet.R", "atomic_json.R")) {
    p <- file.path(root, "02_Infrastructure", "utils", f)
    if (!file.exists(p)) stop("[regime-append] 원자적 쓰기 정본 부재(fail-closed): ", p)
    sys.source(p, envir = e)
  }
  e
}
.rl_write_text_atomic <- function(lines, path) {
  tmp <- file.path(dirname(path), sprintf(".%s.tmp%s", basename(path), Sys.getpid()))
  con <- file(tmp, "w", encoding = "UTF-8"); writeLines(lines, con); close(con)
  for (i in 1:8) { if (isTRUE(suppressWarnings(file.rename(tmp, path)))) return(invisible(TRUE)); Sys.sleep(0.02 * 2^(i - 1)) }
  stop("[regime-append] 텍스트 원자적 기록 실패(원본 보존): ", path, " — 기록분 ", tmp)
}
.rl_sha256 <- function(p) {
  if (!file.exists(p)) return(NA_character_)
  if (requireNamespace("digest", quietly = TRUE)) return(digest::digest(file = p, algo = "sha256"))
  unname(as.character(tools::md5sum(p)))   # digest 부재 시 md5 (manifest 에 algo 명시)
}
.rl_hash_algo <- function() if (requireNamespace("digest", quietly = TRUE)) "sha256" else "md5"

## ── 읽기: 파일 속성(표식) 보존 ──────────────────────────────────────────────
##   ★Windows: read_parquet mmap=TRUE 는 같은 경로 쓰기를 막는다(error 1224) — 되쓸 파일은 FALSE
.RL_STRUCT_ATTRS <- c("names", "row.names", "class", ".internal.selfref", "sorted", "index")
.rl_read <- function(p) {
  x <- arrow::read_parquet(p, mmap = FALSE)
  a <- attributes(x); a <- a[setdiff(names(a), .RL_STRUCT_ATTRS)]
  dt <- as.data.table(x); dt[, Date := as.Date(Date)]; setorder(dt, Date)
  list(dt = dt, attrs = a)
}
## epoch 키: 행 열 c11_regime_key 고유값 ∪ 파일 속성 (overlay_pit_guard::c11_panel_keys 와 같은 정의)
.rl_keys <- function(obj) {
  k <- character(0)
  if (REGIME_LEDGER_KEY_COL %in% names(obj$dt)) k <- unique(as.character(obj$dt[[REGIME_LEDGER_KEY_COL]]))
  a <- obj$attrs[[REGIME_LEDGER_KEY_ATTR]]
  if (!is.null(a)) k <- c(k, as.character(a))
  unique(k)
}
## epoch 분류: legacy(키도 가용일 열도 없음) · keyed(단일 비-NA 키 + Date 형 가용일 열) · malformed(그 밖 — 반쪽 표식)
.rl_epoch <- function(obj) {
  k <- .rl_keys(obj)
  has_av <- all(REGIME_LEDGER_AVAIL_COLS %in% names(obj$dt))
  av_ok <- has_av && all(vapply(REGIME_LEDGER_AVAIL_COLS, function(cl) inherits(obj$dt[[cl]], "Date"), logical(1)))
  if (!length(k) && !has_av) return(list(kind = "legacy", key = NA_character_))
  if (length(k) == 1L && !is.na(k) && nzchar(k) && av_ok) return(list(kind = "keyed", key = k))
  list(kind = "malformed", key = paste(k, collapse = ","),
       why = sprintf("키 %d개(%s) · 가용일 열 %s", length(k), paste(k, collapse = ","),
                     if (!has_av) "없음" else if (!av_ok) "Date 형 아님" else "정상"))
}
## 현행 규칙 epoch 키(fred_availability.R::fred_avail_rules_meta) — 격리 env. 해석 불가 = NA
regime_ledger_rules_key <- function(root = NULL) {
  root <- .rl_root(root)
  f <- file.path(root, "02_Infrastructure/data/fred_availability.R")
  rp <- file.path(root, "06_Registry/fred_availability_rules.json")
  if (!file.exists(f) || !file.exists(rp)) return(NA_character_)
  tryCatch({ e <- new.env(parent = globalenv()); sys.source(f, envir = e)
             as.character(e$fred_avail_rules_meta(rp)$regime_key) }, error = function(err) NA_character_)
}

## ── 동결 구간 대조 (구판 규칙 그대로 — 수치 |Δ|>1e-9 · 문자 불일치 · NA 전이는 대상 아님) ──
.rl_cmpcol <- function(pub, live, frz, cl) {
  if (!(cl %in% names(pub)) || !(cl %in% names(live))) return(NULL)
  p <- pub[as.character(Date) %in% frz][order(Date)]; l <- live[as.character(Date) %in% frz][order(Date)]
  x <- p[[cl]]; y <- l[[cl]]
  bad <- if (is.numeric(x) && is.numeric(y)) which(!is.na(x) & !is.na(y) & abs(x - y) > 1e-9)
         else which(as.character(x) != as.character(y))
  if (!length(bad)) return(NULL)
  list(col = cl, n = length(bad),
       mx = if (is.numeric(x) && is.numeric(y)) max(abs(y[bad] - x[bad])) else NA_real_,
       first = as.character(p$Date[bad[1]]), last = as.character(p$Date[bad[length(bad)]]),
       ex = paste(sprintf("%s %s->%s", as.character(p$Date[bad]), x[bad], y[bad])[seq_len(min(3, length(bad)))],
                  collapse = " | "))
}
.rl_compare_frozen <- function(pub, live, ft) {
  frz <- as.character(intersect(as.character(pub[Date <= ft]$Date), as.character(live$Date)))
  hard <- list(); soft <- list()
  for (cl in c(REGIME_LEDGER_DECISION_COLS, REGIME_LEDGER_AVAIL_COLS)) { r <- .rl_cmpcol(pub, live, frz, cl); if (!is.null(r)) hard[[cl]] <- r }
  for (cl in REGIME_LEDGER_INPUT_COLS) { r <- .rl_cmpcol(pub, live, frz, cl); if (!is.null(r)) soft[[cl]] <- r }
  list(n_common = length(frz), hard = hard, soft = soft)
}

.rl_sidecar_lines <- function(final) {
  sd_ <- final[, .SD, .SDcols = intersect(c("Date", REGIME_LEDGER_AVAIL_COLS, REGIME_LEDGER_DECISION_COLS,
                                             REGIME_LEDGER_INPUT_COLS), names(final))][order(Date)]
  for (cl in intersect(c("Date", REGIME_LEDGER_AVAIL_COLS), names(sd_))) set(sd_, j = cl, value = as.character(sd_[[cl]]))
  vapply(seq_len(nrow(sd_)), function(i) as.character(toJSON(as.list(sd_[i]), auto_unbox = TRUE, digits = 10)), "")
}
.rl_apply_attrs <- function(dt, attrs) {
  for (nm in names(attrs)) setattr(dt, nm, attrs[[nm]])
  dt
}
.rl_month_gaps <- function(series, final) {
  if (series != "monthly" || !nrow(final)) return(character(0))
  setdiff(format(seq(min(final$Date), max(final$Date), by = "month"), "%Y-%m"), format(final$Date, "%Y-%m"))
}
.rl_cur_start <- function(series, as_of) if (series == "monthly") as.Date(format(as_of, "%Y-%m-01")) else as_of

## ═════════════════════════════════════════════════════════════════════════════
## 1. 병합 (append) — 라이브를 쓰는 유일한 경로
## ═════════════════════════════════════════════════════════════════════════════
regime_ledger_append <- function(series = "monthly", root = NULL, as_of = Sys.Date(), candidate = NULL,
                                 init = FALSE, dry_run = FALSE, verbose = TRUE) {
  P <- regime_ledger_paths(series, root); as_of <- as.Date(as_of)
  fail <- function(code, msg, ...) {
    .rl_say(verbose, "[regime-append] %s %s\n", if (code == 3L) "★EPOCH" else "ERROR", msg)
    c(list(status = code, series = series, msg = msg, written = FALSE), list(...))
  }
  src <- if (is.null(candidate)) P$live else candidate
  if (!file.exists(src)) return(fail(2L, sprintf("후보(재생성본) 부재 — 병합 없음·라이브 불변: %s", src)))
  C <- tryCatch(.rl_read(src), error = function(e) e)
  if (inherits(C, "error")) return(fail(2L, sprintf("후보 판독 불가: %s (%s)", src, conditionMessage(C))))
  live <- C$dt
  .rl_say(verbose, "[regime-append] %s 후보 n=%d  %s ~ %s  (%s)\n", series, nrow(live), min(live$Date), max(live$Date),
          if (identical(normalizePath(src, winslash = "/", mustWork = FALSE),
                        normalizePath(P$live, winslash = "/", mustWork = FALSE))) "라이브 자리" else src)
  ec <- .rl_epoch(C)
  if (identical(ec$kind, "malformed")) return(fail(2L, sprintf("후보 표식 계약 위반(반쪽 표식): %s", ec$why)))

  cur_start <- .rl_cur_start(series, as_of)
  completed <- live[Date < cur_start]
  if (!nrow(completed)) return(fail(2L, sprintf("완료 구간이 비어 있음 (경계 %s)", cur_start)))
  ft_new <- max(completed$Date)
  .rl_say(verbose, "[regime-append] 완료 경계 %s → 동결 대상 종점 %s · 진행중 행 %d개 · epoch %s\n",
          cur_start, ft_new, nrow(live[Date >= cur_start]), if (ec$kind == "keyed") ec$key else "legacy(표식 없음)")
  U <- NULL
  if (!dry_run) { U <- tryCatch(.rl_util_env(P$root), error = function(e) e)
                  if (inherits(U, "error")) return(fail(2L, conditionMessage(U))) }
  rules_key <- regime_ledger_rules_key(P$root)

  if (!dir.exists(P$pubdir)) dir.create(P$pubdir, recursive = TRUE, showWarnings = FALSE)
  if (!file.exists(P$pub)) {
    if (!init) return(fail(2L, sprintf("발행 원장 부재 — 최초 1회 --init 로 현재 상태를 기준선으로 동결할 것: %s", P$pub)))
    if (dry_run) return(list(status = 0L, series = series, written = FALSE, init = TRUE, n = nrow(live), frozen_through = as.character(ft_new)))
    fin <- .rl_apply_attrs(copy(live), C$attrs)
    U$qvest_atomic_write_parquet(fin, P$pub, tag = "regime-append/init")
    U$qvest_atomic_write_json(list(series = series, frozen_through = as.character(ft_new),
                                   initialized = as.character(Sys.time()), n = nrow(live),
                                   c11_regime_key = if (ec$kind == "keyed") ec$key else NA_character_,
                                   rules_key_at_write = rules_key, schema = names(live)),
                              P$meta, auto_unbox = TRUE, pretty = TRUE, na = "null")
    .rl_say(verbose, "[regime-append] ★발행 원장 초기화 (n=%d, frozen_through=%s)\n", nrow(live), ft_new)
    return(list(status = 0L, series = series, written = TRUE, init = TRUE, n = nrow(live), frozen_through = as.character(ft_new)))
  }
  PB <- tryCatch(.rl_read(P$pub), error = function(e) e)
  if (inherits(PB, "error")) return(fail(2L, sprintf("발행 원장 판독 불가: %s", conditionMessage(PB))))
  mt <- tryCatch(fromJSON(P$meta), error = function(e) NULL)
  if (is.null(mt) || is.null(mt$frozen_through)) return(fail(2L, sprintf("발행 원장 meta 판독 불가: %s", P$meta)))
  pub <- PB$dt; ft_prev <- as.Date(mt$frozen_through)
  ep <- .rl_epoch(PB)
  .rl_say(verbose, "[regime-append] 발행 원장 n=%d · frozen_through %s · epoch %s\n", nrow(pub), ft_prev,
          if (ep$kind == "keyed") ep$key else ep$kind)

  if (identical(ep$kind, "malformed")) return(fail(2L, sprintf("발행 원장 표식 계약 위반(반쪽 표식): %s", ep$why)))
  ## ── ③ epoch 대조: 다르면 병합하지 않는다(혼합 원장 금지) ───────────────────
  same_epoch <- identical(ep$kind, ec$kind) && (ep$kind == "legacy" || identical(ep$key, ec$key))
  if (!same_epoch)
    return(fail(3L, sprintf(paste0("발행 원장 epoch(%s) ≠ 후보 epoch(%s) — 혼합 원장 금지: 병합·기록 없음, 라이브 불변. ",
                                   "재기준선 = regime_ledger_republish(dry-run 기본 → --execute) · 현행 규칙 키 %s"),
                            if (ep$kind == "keyed") ep$key else ep$kind, if (ec$kind == "keyed") ec$key else ec$kind,
                            rules_key), pub_epoch = ep$key, cand_epoch = ec$key))
  if (ep$kind == "keyed" && !is.null(mt$c11_regime_key) && !is.na(mt$c11_regime_key) && !identical(mt$c11_regime_key, ep$key))
    return(fail(2L, sprintf("발행 원장 parquet epoch(%s) ≠ meta epoch(%s) — 원장 자체 불일치", ep$key, mt$c11_regime_key)))
  if (ec$kind == "keyed" && !is.na(rules_key) && !identical(rules_key, ec$key))
    .rl_say(verbose, "[regime-append] ⚠ 후보 epoch(%s) ≠ 현행 규칙 키(%s) — 원장은 일관되나 소비자 가드는 stale_epoch 로 볼 것(재빌드·재기준선 필요)\n",
            ec$key, rules_key)

  ## ── 동결 구간 대조 (Date <= ft_prev) — 보고만, 적용하지 않음 ─────────────────
  cmpr <- .rl_compare_frozen(pub, live, ft_prev)
  .rl_say(verbose, "[regime-append] 동결 구간 공통 %d행 대조\n", cmpr$n_common)
  hard <- cmpr$hard; soft <- cmpr$soft
  if (length(soft)) {
    .rl_say(verbose, "[regime-append] 입력 드리프트(로그): ")
    for (r in soft) .rl_say(verbose, "%s %d행%s  ", r$col, r$n, if (is.na(r$mx)) "" else sprintf("(최대 Δ%.4g)", r$mx))
    .rl_say(verbose, "\n            └ FRED 소급 개정 등 — 결정값에 닿지 않는 한 통과\n")
  }
  if (length(hard)) {
    .rl_say(verbose, "\n[regime-append] ★★동결 구간 결정값 재서술 시도 — 적용하지 않고 발행본 유지\n")
    for (r in hard) .rl_say(verbose, "   %s: %d행%s\n      %s\n", r$col, r$n,
                            if (is.na(r$mx)) "" else sprintf(" (최대 Δ%.4g)", r$mx), r$ex)
  }

  ## ── 병합: 동결분은 발행본, 그 이후는 후보 ───────────────────────────────────
  if (ep$kind == "legacy") {
    ## legacy 원장(표식 이전 · 배포 전 상태와 비트 동일 규약): 발행본 열 목록 유지
    final <- rbindlist(list(pub[Date <= ft_prev], live[Date > ft_prev, .SD, .SDcols = names(pub)]), use.names = TRUE)
    out_attrs <- PB$attrs
    schema_note <- NULL
  } else {
    ## ① 같은 C11 epoch: 후보(생산자) 스키마가 정본 — 표식 열·파일 속성 보존
    miss_pub <- setdiff(names(live), names(pub)); miss_live <- setdiff(names(pub), names(live))
    schema_note <- if (length(miss_pub) || length(miss_live))
      sprintf("스키마 이동 — 후보에만 [%s] · 발행본에만 [%s]", paste(miss_pub, collapse = ","), paste(miss_live, collapse = ",")) else NULL
    if (!is.null(schema_note)) .rl_say(verbose, "[regime-append] ⚠ %s (동결 행 빈칸 = NA)\n", schema_note)
    final <- tryCatch(rbindlist(list(pub[Date <= ft_prev], live[Date > ft_prev]), use.names = TRUE, fill = TRUE),
                      error = function(e) e)
    if (inherits(final, "error")) return(fail(2L, sprintf("병합 실패(열 형 불일치?): %s", conditionMessage(final))))
    setcolorder(final, c(names(live), setdiff(names(final), names(live))))
    out_attrs <- C$attrs
    for (cl in REGIME_LEDGER_AVAIL_COLS) if (!inherits(final[[cl]], "Date"))
      return(fail(2L, sprintf("병합 후 %s 가 Date 형이 아니다(%s) — 표식 계약 파손", cl, class(final[[cl]])[1])))
    fk <- unique(as.character(final[[REGIME_LEDGER_KEY_COL]]))
    if (!identical(fk, ec$key)) return(fail(2L, sprintf("병합 후 epoch 키 열이 단일하지 않다(%s)", paste(fk, collapse = ","))))
  }
  setorder(final, Date)
  final <- .rl_apply_attrs(final, out_attrs)
  ft_write <- max(ft_prev, ft_new)       # ★동결 단조 — 과거 --as-of 재실행이 경계를 물리지 못한다
  n_newfrozen <- nrow(live[Date > ft_prev & Date <= ft_new])
  n_open      <- nrow(final[Date > ft_write])
  .rl_say(verbose, "[regime-append] 병합: 동결 %d행(발행본) + 신규동결 %d행(후보, 이번에 완료) + 진행중 %d행\n",
          nrow(pub[Date <= ft_prev]), n_newfrozen, n_open)
  gaps <- .rl_month_gaps(series, final)
  if (length(gaps)) .rl_say(verbose, "[regime-append] ★월 결손 %d개: %s\n", length(gaps), paste(utils::head(gaps, 8), collapse = " "))
  status <- if (length(hard)) 1L else 0L
  res <- list(status = status, series = series, written = FALSE, n = nrow(final),
              frozen_through_prev = as.character(ft_prev), frozen_through_new = as.character(ft_write),
              n_newly_frozen = n_newfrozen, n_open = n_open, epoch = if (ec$kind == "keyed") ec$key else "legacy",
              hard = hard, soft = soft, final = final)
  if (dry_run) { .rl_say(verbose, "[regime-append] dry-run — 기록 안 함\n"); return(res) }

  ts <- format(Sys.time(), "%Y%m%d_%H%M%S")
  invisible(file.copy(P$pub, paste0(P$pub, ".bak_", ts), overwrite = FALSE))
  invisible(file.copy(src, paste0(P$live, ".regen_", ts), overwrite = FALSE))   # 재생성본(후보) 증거 — 구판과 같은 이름
  w <- tryCatch({
    U$qvest_atomic_write_parquet(final, P$pub, tag = "regime-append/pub")
    U$qvest_atomic_write_parquet(final, P$live, tag = "regime-append/live")   ## 소비자가 안정된 이력을 보도록 라이브도 발행본으로 동기화
    meta_new <- list(series = series, frozen_through = as.character(ft_write),
                     updated = as.character(Sys.time()), n = nrow(final),
                     c11_regime_key = if (ec$kind == "keyed") ec$key else NA_character_,
                     rules_key_at_write = rules_key, schema = names(final))
    if (!is.null(mt$republished)) meta_new$republished <- mt$republished   # 재기준선 이력은 승계
    U$qvest_atomic_write_json(meta_new, P$meta, auto_unbox = TRUE, pretty = TRUE, na = "null")
    ## git 추적용 텍스트 사이드카 (.parquet 은 gitignore 대상 — 원칙① 증거가 diff 로 남아야 한다)
    .rl_write_text_atomic(.rl_sidecar_lines(final), P$side)
    TRUE }, error = function(e) e)
  if (inherits(w, "error")) return(fail(2L, sprintf("기록 실패: %s", conditionMessage(w))))
  cat(toJSON(list(ts = ts, series = series, frozen_through_prev = as.character(ft_prev),
                  frozen_through_new = as.character(ft_write), n = nrow(final),
                  n_newly_frozen = n_newfrozen, n_open = n_open,
                  epoch = if (ec$kind == "keyed") ec$key else "legacy",
                  candidate = if (is.null(candidate)) "live" else "candidate",
                  schema_note = schema_note,
                  drift_hard = lapply(hard, function(r) list(col = r$col, n = r$n, ex = r$ex)),
                  drift_soft = lapply(soft, function(r) list(col = r$col, n = r$n, max = r$mx))),
             auto_unbox = TRUE, na = "null"), "\n", file = P$dlog, append = TRUE)
  .rl_say(verbose, "[regime-append] 기록 완료 — 원장 n=%d · frozen_through %s → %s · 표식 %s\n",
          nrow(final), ft_prev, ft_write, if (ec$kind == "keyed") ec$key else "legacy")
  res$written <- TRUE
  if (length(hard)) .rl_say(verbose, "[regime-append] 종료 1 — 동결 구간 재서술 시도(발행본 보존). 상류 확인 필요.\n")
  else .rl_say(verbose, "[regime-append] OK\n")
  res
}

## ═════════════════════════════════════════════════════════════════════════════
## 2. 재생성 → 원장 (아침 fred_regime.R · self_heal.R · 수동) — 라이브를 원장 밖에서 덮지 않는다
## ═════════════════════════════════════════════════════════════════════════════
##   build_regime_signal_table(regime_signal.R)은 호출자가 적재한다(config.R 전역 CACHE_DIR 등 필요).
##   재생성본은 후보 경로에만 쓰고, 병합이 라이브를 쓴다. 빌드 실패 = 후보 부재 = 그 계열 라이브 불변.
regime_ledger_build_candidates <- function(root = NULL, series = c("monthly", "daily"), verbose = TRUE) {
  if (!exists("build_regime_signal_table", mode = "function"))
    stop("[regime-append] build_regime_signal_table 미적재 — regime_signal.R 을 먼저 source 할 것")
  cand <- regime_ledger_candidate_paths(root, fresh = TRUE)
  built <- setNames(rep(FALSE, length(series)), series)
  for (s in series) {
    ok <- tryCatch({ build_regime_signal_table(save_path = cand[[s]], daily = identical(s, "daily")); file.exists(cand[[s]]) },
                   error = function(e) { cat(sprintf("Regime signal %s skipped: %s\n", s, conditionMessage(e))); FALSE })
    built[[s]] <- isTRUE(ok)
  }
  list(paths = cand, built = built)
}
regime_ledger_rebuild_publish <- function(root = NULL, as_of = Sys.Date(), series = c("monthly", "daily"), verbose = TRUE) {
  b <- regime_ledger_build_candidates(root, series, verbose)
  out <- list()
  for (s in series) {
    r <- if (!isTRUE(b$built[[s]])) list(status = 2L, series = s, written = FALSE, msg = "빌드 실패 — 후보 없음·라이브 불변") else
      tryCatch(regime_ledger_append(s, root = root, as_of = as_of, candidate = b$paths[[s]], verbose = verbose),
               error = function(e) list(status = 2L, series = s, written = FALSE, msg = conditionMessage(e)))
    r$final <- NULL
    cat(sprintf("[regime-ledger/%s] %s\n", s, switch(as.character(r$status),
      "0" = "OK — 라이브 = 원장",
      "1" = "!! 동결 구간 재서술 시도 검출 — 발행본 보존됨(상류 확인 필요) · 라이브 = 원장",
      "3" = "!! epoch 불일치 — 병합·기록 없음(라이브 불변) · 재기준선 필요(regime_ledger_republish)",
      sprintf("XX 원장 경로 실패(rc=%s) — 라이브 불변 · %s", r$status, r$msg %||rl% ""))))
    out[[s]] <- r
  }
  invisible(out)
}

## ═════════════════════════════════════════════════════════════════════════════
## 3. 재기준선 (republish) — 구 발행 원장 전량 보관 → 현행 C11 epoch 판으로 재초기화 (dry-run 기본)
## ═════════════════════════════════════════════════════════════════════════════
##   근거: 결정 PIT-C11-REMEDIATION(안 B 표적 재빌드) — 구 발행본의 동결 이력은 C11 이전 코드(미국 동일 세션·
##   주간 LOCF·동월 CPI)로 만든 값이라 append-only 가 **미래참조를 동결**하고 있다. 재기준선은 코드가 아니라
##   epoch 전환이므로 자동으로 하지 않는다(병합은 epoch 불일치에서 종료 3 으로 멈춘다).
.rl_diff_summary <- function(pub, cand) {
  com <- intersect(as.character(pub$Date), as.character(cand$Date))
  per <- list()
  for (cl in c(REGIME_LEDGER_DECISION_COLS, REGIME_LEDGER_INPUT_COLS)) {
    r <- .rl_cmpcol(pub, cand, com, cl)
    per[[cl]] <- if (is.null(r)) list(n = 0L) else list(n = r$n, first = r$first, last = r$last,
                                                        max_abs = if (is.na(r$mx)) NULL else r$mx)
  }
  list(n_pub = nrow(pub), n_cand = nrow(cand), n_common = length(com),
       n_only_pub = length(setdiff(as.character(pub$Date), com)),
       n_only_cand = length(setdiff(as.character(cand$Date), com)),
       per_col = per)
}
regime_ledger_republish <- function(series = c("monthly", "daily"), root = NULL, as_of = Sys.Date(),
                                    candidates = NULL, execute = FALSE, archive_dir = NULL,
                                    rules_key = NULL, plan_out = NULL, reason = "PIT-C11-REMEDIATION 안 B — C11 epoch 재기준선",
                                    expect_plan = NULL, verbose = TRUE) {
  ## expect_plan = 검토한 dry-run 계획(JSON). 주면 후보 해시·보관 목록(파일·해시)이 그 계획과 같아야 실행한다
  ##   — "검토한 것 = 실행한 것"(dry-run 이후 후보가 재빌드되거나 원장 디렉터리가 바뀌면 거부).
  root <- .rl_root(root); as_of <- as.Date(as_of)
  for (s in series) .rl_series_ok(s)
  pubdir <- regime_ledger_paths("monthly", root)$pubdir
  if (is.null(rules_key)) rules_key <- regime_ledger_rules_key(root)
  if (is.null(archive_dir)) archive_dir <- file.path(pubdir, sprintf("_archive_%s_%s", REGIME_LEDGER_ARCHIVE_TAG, format(as_of, "%Y%m%d")))
  plan <- list(mode = if (execute) "execute" else "dry-run", ts = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
               root = root, as_of = as.character(as_of), rules_key = rules_key, reason = reason,
               archive_dir = archive_dir, hash_algo = .rl_hash_algo(), series = list(), problems = character(0))
  prob <- function(...) plan$problems <<- c(plan$problems, sprintf(...))
  if (is.na(rules_key)) prob("현행 규칙 키 해석 불가(fred_availability.R · rules json)")
  if (dir.exists(archive_dir)) prob("보관 디렉터리가 이미 있다(덮어쓰지 않음): %s", archive_dir)
  for (s in series) {
    P <- regime_ledger_paths(s, root)
    src <- if (!is.null(candidates[[s]])) candidates[[s]] else P$live
    S <- list(candidate = src, candidate_hash = .rl_sha256(src))
    if (!file.exists(src)) { prob("%s 후보 부재: %s", s, src); plan$series[[s]] <- S; next }
    C <- tryCatch(.rl_read(src), error = function(e) e)
    if (inherits(C, "error")) { prob("%s 후보 판독 불가: %s", s, conditionMessage(C)); plan$series[[s]] <- S; next }
    ec <- .rl_epoch(C)
    S$candidate_epoch <- ec$key; S$candidate_kind <- ec$kind
    if (!identical(ec$kind, "keyed")) prob("%s 후보가 C11 표식 판이 아니다(%s) — --rebuild 로 현행 코드 재빌드 필요", s, ec$kind)
    else if (!identical(ec$key, rules_key)) prob("%s 후보 epoch(%s) ≠ 현행 규칙 키(%s) — --rebuild 필요", s, ec$key, rules_key)
    cur_start <- .rl_cur_start(s, as_of)
    comp <- C$dt[Date < cur_start]
    if (!nrow(comp)) prob("%s 후보 완료 구간이 비어 있음(경계 %s)", s, cur_start)
    S$n <- nrow(C$dt); S$date_min <- as.character(min(C$dt$Date)); S$date_max <- as.character(max(C$dt$Date))
    S$frozen_through <- if (nrow(comp)) as.character(max(comp$Date)) else NA_character_
    S$n_open <- nrow(C$dt[Date >= cur_start]); S$schema <- names(C$dt)
    S$avail_na <- if ("avail_date" %in% names(C$dt)) sum(is.na(C$dt$avail_date)) else NA_integer_
    S$month_gaps <- .rl_month_gaps(s, C$dt)
    if (file.exists(P$pub)) {
      PB <- tryCatch(.rl_read(P$pub), error = function(e) e)
      if (inherits(PB, "error")) prob("%s 구 발행본 판독 불가: %s", s, conditionMessage(PB)) else {
        epb <- .rl_epoch(PB)
        S$old_epoch <- if (epb$kind == "keyed") epb$key else epb$kind
        S$old_meta <- tryCatch(fromJSON(P$meta), error = function(e) NULL)
        S$diff_vs_old <- .rl_diff_summary(PB$dt, C$dt)
      }
    } else S$old_epoch <- "absent"
    plan$series[[s]] <- S
  }
  ## 보관 목록 — 발행 원장 디렉터리의 **전량**(하위 디렉터리 = 이전 보관본 제외). 핵심 파일 = 복사 후 교체,
  ##   .bak_* = 이동(같은 볼륨 rename — 원본 손실 없음). 드리프트 로그 = 복사(원장 밖 이력 · 이후 append 계속).
  fl <- list.files(pubdir, all.files = TRUE, no.. = TRUE, full.names = TRUE)
  fl <- fl[!dir.exists(fl)]
  plan$archive <- lapply(fl, function(f) {
    b <- basename(f)
    list(file = b, bytes = unname(file.size(f)), hash = .rl_sha256(f),
         action = if (grepl("\\.bak_", b)) "move" else if (identical(b, ".gitignore")) "copy_keep" else "copy")
  })
  ## Windows MAX_PATH(260 — OS 한계, 조정 수치 아님): 보관 경로가 넘으면 rename/copy 가 중간에 실패한다
  ##   (실측 2026-09-24 미러 — 긴 스크래치 경로에서 .bak 이동 실패). 실행 전에 거부한다.
  if (identical(.Platform$OS.type, "windows") && length(plan$archive)) {
    lp <- max(nchar(file.path(archive_dir, vapply(plan$archive, function(a) a$file, ""))))
    if (lp >= 260L) prob("보관 경로 길이 %d자 ≥ Windows MAX_PATH 260 — 보관 디렉터리를 짧은 경로로(--archive-dir)", lp)
  }
  if (!is.null(expect_plan)) {
    X <- tryCatch(fromJSON(expect_plan, simplifyVector = FALSE), error = function(e) NULL)
    if (is.null(X)) prob("검토 계획 판독 불가: %s", expect_plan) else {
      for (s in names(plan$series)) if (!identical(plan$series[[s]]$candidate_hash, X$series[[s]]$candidate_hash))
        prob("%s 후보가 검토 계획과 다르다(해시 %s ≠ 계획 %s) — dry-run 을 다시 돌려 검토할 것", s,
             plan$series[[s]]$candidate_hash, as.character(X$series[[s]]$candidate_hash %||rl% "없음"))
      fh <- function(L) sort(vapply(L, function(a) paste(a$file, a$hash), ""))
      if (!identical(fh(plan$archive), fh(X$archive %||rl% list())))
        prob("발행 원장 디렉터리가 검토 계획 이후 바뀌었다(보관 목록 불일치) — dry-run 을 다시 돌려 검토할 것")
      if (!identical(as.character(X$rules_key), as.character(rules_key)))
        prob("규칙 키가 검토 계획(%s)과 다르다(%s)", as.character(X$rules_key), rules_key)
    }
  }
  if (!is.null(plan_out)) write_json(plan, plan_out, auto_unbox = TRUE, pretty = TRUE, na = "null", digits = 10)
  if (length(plan$problems)) {
    .rl_say(verbose, "[regime-republish] ★거부 — 문제 %d건:\n%s\n", length(plan$problems), paste("   ·", plan$problems, collapse = "\n"))
    plan$status <- 2L; return(invisible(plan))
  }
  for (s in names(plan$series)) {
    S <- plan$series[[s]]; D <- S$diff_vs_old
    .rl_say(verbose, "[regime-republish] %s: 후보 n=%d (%s~%s) · epoch %s · frozen_through %s · 진행중 %d · 구 발행본 %s%s\n",
            s, S$n, S$date_min, S$date_max, S$candidate_epoch, S$frozen_through, S$n_open, S$old_epoch,
            if (is.null(D)) "" else sprintf(" (공통 %d행 · 구 발행본에만 %d행 · 후보에만 %d행 · Regime_Score 재서술 %d행 · Category %d행 · Cash_Pct %d행)",
                                            D$n_common, D$n_only_pub, D$n_only_cand, D$per_col$Regime_Score$n,
                                            D$per_col$Category$n, D$per_col$Cash_Pct$n))
  }
  .rl_say(verbose, "[regime-republish] 보관 %d파일(이동 %d · 복사 %d) → %s\n", length(plan$archive),
          sum(vapply(plan$archive, function(a) a$action == "move", logical(1))),
          sum(vapply(plan$archive, function(a) a$action != "move", logical(1))), archive_dir)
  if (!execute) { .rl_say(verbose, "[regime-republish] dry-run — 기록 안 함 (--execute 로 실행)\n"); plan$status <- 0L; return(invisible(plan)) }

  ## ── 실행 ────────────────────────────────────────────────────────────────
  U <- .rl_util_env(root)
  dir.create(archive_dir, recursive = TRUE, showWarnings = FALSE)
  if (!dir.exists(archive_dir)) stop("[regime-republish] 보관 디렉터리 생성 실패: ", archive_dir)
  ## 보관은 전부 되거나 전혀 안 된 상태로 끝난다 — 중간 실패 시 이동분은 되돌리고 복사분은 지운 뒤 중단(원장 미교체)
  done <- list()
  arc <- tryCatch({
    for (a in plan$archive) {
      from <- file.path(pubdir, a$file); to <- file.path(archive_dir, a$file)
      ok <- if (a$action == "move") isTRUE(suppressWarnings(file.rename(from, to))) else
        isTRUE(suppressWarnings(file.copy(from, to, overwrite = FALSE, copy.date = TRUE)))
      if (ok) done[[length(done) + 1L]] <- a
      if (!ok || !identical(.rl_sha256(to), a$hash)) stop(sprintf("보관 실패·해시 불일치: %s", a$file))
    }
    TRUE }, error = function(e) e)
  if (inherits(arc, "error")) {
    for (a in rev(done)) {
      to <- file.path(archive_dir, a$file); from <- file.path(pubdir, a$file)
      if (a$action == "move") suppressWarnings(file.rename(to, from)) else suppressWarnings(file.remove(to))
    }
    if (!length(list.files(archive_dir, all.files = TRUE, no.. = TRUE))) unlink(archive_dir, recursive = TRUE)
    stop(sprintf("[regime-republish] %s — 되돌림 %d건 후 중단(원장 미교체)", conditionMessage(arc), length(done)))
  }
  manifest <- c(plan[c("ts", "root", "as_of", "rules_key", "reason", "hash_algo")],
                list(archived = plan$archive, series = lapply(plan$series, function(S) S[c("candidate", "candidate_hash", "candidate_epoch",
                                                                                            "old_epoch", "old_meta", "n", "frozen_through")]),
                     restore = sprintf("Rscript 02_Infrastructure/regime/regime_append_only.R --restore %s --execute", archive_dir)))
  U$qvest_atomic_write_json(manifest, file.path(archive_dir, "MANIFEST.json"), auto_unbox = TRUE, pretty = TRUE, na = "null", digits = 10)
  for (s in names(plan$series)) {
    P <- regime_ledger_paths(s, root); S <- plan$series[[s]]
    C <- .rl_read(S$candidate)
    if (!identical(.rl_sha256(S$candidate), S$candidate_hash)) stop("[regime-republish] 후보가 계획 이후 바뀌었다 — 중단: ", S$candidate)
    fin <- .rl_apply_attrs(copy(C$dt), C$attrs)
    U$qvest_atomic_write_parquet(fin, P$pub, tag = "regime-republish/pub")
    if (!identical(normalizePath(S$candidate, winslash = "/", mustWork = FALSE), normalizePath(P$live, winslash = "/", mustWork = FALSE)))
      U$qvest_atomic_write_parquet(fin, P$live, tag = "regime-republish/live")
    U$qvest_atomic_write_json(list(series = s, frozen_through = S$frozen_through, updated = as.character(Sys.time()), n = nrow(fin),
                                   c11_regime_key = S$candidate_epoch, rules_key_at_write = rules_key, schema = names(fin),
                                   republished = list(at = plan$ts, archive_dir = archive_dir, old_epoch = S$old_epoch, reason = reason)),
                              P$meta, auto_unbox = TRUE, pretty = TRUE, na = "null")
    .rl_write_text_atomic(.rl_sidecar_lines(fin), P$side)
    cat(toJSON(list(ts = format(Sys.time(), "%Y%m%d_%H%M%S"), series = s, event = "republish", archive_dir = archive_dir,
                    old_epoch = S$old_epoch, epoch = S$candidate_epoch, n = nrow(fin), frozen_through_new = S$frozen_through,
                    diff_vs_old = S$diff_vs_old), auto_unbox = TRUE, na = "null", digits = 10),
        "\n", file = P$dlog, append = TRUE)
    ## 사후 대조 — 되읽어 표식·행 수 확인
    chk <- .rl_read(P$pub); ek <- .rl_epoch(chk)
    if (nrow(chk$dt) != nrow(fin) || !identical(ek$key, S$candidate_epoch)) stop("[regime-republish] 사후 대조 실패: ", P$pub)
    .rl_say(verbose, "[regime-republish] %s 재초기화 완료 — n=%d · frozen_through %s · epoch %s\n", s, nrow(fin), S$frozen_through, ek$key)
  }
  plan$status <- 0L
  invisible(plan)
}

## 재기준선 되돌리기 — 보관본의 핵심 파일을 복원하고 .bak_* 를 되돌린다(dry-run 기본). 드리프트 로그는 append-only 라
##   복원하지 않고 restore 사건을 덧붙인다(보관본 사본은 그대로 남는다).
regime_ledger_restore <- function(archive_dir, root = NULL, execute = FALSE, verbose = TRUE) {
  root <- .rl_root(root); pubdir <- regime_ledger_paths("monthly", root)$pubdir
  mf <- file.path(archive_dir, "MANIFEST.json")
  if (!file.exists(mf)) stop("[regime-restore] MANIFEST.json 없음: ", archive_dir)
  M <- fromJSON(mf, simplifyVector = FALSE)
  acts <- list()
  for (a in M$archived) {
    if (identical(a$file, "regime_drift_log.jsonl") || identical(a$action, "copy_keep")) next
    src <- file.path(archive_dir, a$file)
    if (!identical(.rl_sha256(src), a$hash)) stop("[regime-restore] 보관본 해시 불일치 — 중단: ", a$file)
    acts[[length(acts) + 1L]] <- list(file = a$file, action = if (identical(a$action, "move")) "move_back" else "copy_back")
  }
  .rl_say(verbose, "[regime-restore] %d파일 복원 계획 (%s)\n", length(acts), if (execute) "execute" else "dry-run")
  if (!execute) return(invisible(list(status = 0L, actions = acts)))
  U <- .rl_util_env(root)
  for (x in acts) {
    src <- file.path(archive_dir, x$file); dst <- file.path(pubdir, x$file)
    if (x$action == "move_back") { if (!isTRUE(file.rename(src, dst))) stop("[regime-restore] 이동 실패: ", x$file) }
    else {
      tmp <- file.path(pubdir, sprintf(".%s.tmp%s", x$file, Sys.getpid()))
      if (!isTRUE(file.copy(src, tmp, overwrite = TRUE)) || !isTRUE(file.rename(tmp, dst))) stop("[regime-restore] 복사 실패: ", x$file)
    }
  }
  for (s in c("monthly", "daily")) {
    P <- regime_ledger_paths(s, root)
    if (file.exists(P$pub)) { R <- .rl_read(P$pub); U$qvest_atomic_write_parquet(.rl_apply_attrs(R$dt, R$attrs), P$live, tag = "regime-restore/live") }
    cat(toJSON(list(ts = format(Sys.time(), "%Y%m%d_%H%M%S"), series = s, event = "restore", archive_dir = archive_dir),
               auto_unbox = TRUE), "\n", file = P$dlog, append = TRUE)
  }
  .rl_say(verbose, "[regime-restore] 복원 완료\n")
  invisible(list(status = 0L, actions = acts))
}

## ═════════════════════════════════════════════════════════════════════════════
## CLI
## ═════════════════════════════════════════════════════════════════════════════
.rl_main <- function(a = commandArgs(TRUE)) {
  getarg <- function(k, d = NA) { i <- which(a == k); if (length(i) && length(a) > i[1]) a[i[1] + 1L] else d }
  root <- .rl_root(getarg("--root", NA))
  as_of <- as.Date(getarg("--as-of", as.character(Sys.Date())))
  series <- getarg("--series", "monthly")
  if ("--restore" %in% a) {
    r <- regime_ledger_restore(getarg("--restore"), root = root, execute = "--execute" %in% a)
    return(r$status)
  }
  if ("--republish" %in% a) {
    ss <- if (identical(series, "all") || !("--series" %in% a)) c("monthly", "daily") else series
    if ("--rebuild" %in% a) {
      if (!exists("build_regime_signal_table", mode = "function")) {
        owd <- setwd(root); on.exit(setwd(owd), add = TRUE)
        Sys.setenv(QM_ROOT = root)
        sys.source(file.path(root, "02_Infrastructure/config.R"), envir = globalenv())
        sys.source(file.path(root, "02_Infrastructure/regime/regime_signal.R"), envir = globalenv())
      }
      b <- regime_ledger_build_candidates(root, ss)
      if (!all(b$built)) { cat("[regime-republish] 재빌드 실패:", names(b$built)[!b$built], "\n"); return(2L) }
      cand <- b$paths[ss]
    } else cand <- list(monthly = getarg("--candidate-monthly", NULL), daily = getarg("--candidate-daily", NULL))
    cand <- cand[!vapply(cand, function(x) is.null(x) || is.na(x), logical(1))]
    r <- regime_ledger_republish(ss, root = root, as_of = as_of, candidates = cand, execute = "--execute" %in% a,
                                 archive_dir = getarg("--archive-dir", NULL), plan_out = getarg("--plan-out", NULL),
                                 expect_plan = getarg("--expect-plan", NULL))
    return(r$status)
  }
  cand <- if ("--from-candidate" %in% a) regime_ledger_paths(series, root)$cand else getarg("--candidate", NULL)
  if (length(cand) && is.na(cand)) cand <- NULL
  r <- regime_ledger_append(series, root = root, as_of = as_of, candidate = cand,
                            init = "--init" %in% a, dry_run = "--dry-run" %in% a)
  r$status
}
if (sys.nframe() == 0L) {
  .rc <- tryCatch(.rl_main(), error = function(e) { cat(sprintf("[regime-append] ERROR %s\n", conditionMessage(e))); 2L })
  quit(status = as.integer(.rc), save = "no")
}
