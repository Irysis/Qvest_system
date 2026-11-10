## chain_tick.R — 강화 사슬 무인 틱의 읽기 전용 계획기 · 생성 산출 컴파일러 · 틱 장부 · 알림 문안 (v1 · 2026-11-10)
##   결정: decision_register CHAIN-AUTOMATION-STANDING-BOARD-AND-TICK-20261110(도훈 11-10 "만들고 바로 켠다" · 저녁 "사슬 무인틱 구축은 해둬")
##   호출자: 02_Infrastructure/ops/chain_tick.sh(오케스트레이터) · 02_Infrastructure/ops/chain_gen_run.sh(config gen_timeout_sec 만)
##   ★이 파일은 사슬 원장(chain_steps.jsonl)에 쓰지 않는다 — 원장은 round.sh 명령으로만 바뀐다. 쓰는 곳 = 틱 장부(.cache/chain_tick/) ·
##     생성기 작업 폴더(open/*.txt · prompt.md) · 걸음 칸 사양(<사슬>/cells/k<k>.json — 열기 전 한 번 · 원장이 이미 참조하면 거부).
##   판정 규칙은 갖지 않는다 — 다음 행동을 고르는 조건은 코어(04_Research/programs/_lib/round_core/v1/p4.R)의 거부 조건과 같은 식으로 원장에서 읽는다.
##   CLI: Rscript chain_tick.R <명령> [인자]
##     config [key]                         설정(06_Registry/chain_tick.json · CT_CFG) 판독 — key 를 주면 그 값만 · 판독 불가 = 종료 2
##     plan <사슬 디렉터리>                  다음 행동 한 줄 "ACTION<TAB>k<TAB>reason<TAB>detail"(판독 실패도 broken 으로 종료 0)
##     list                                  등록된 사슬마다 plan + last_served_at(TSV)
##     prompt <사슬> <WDIR>                  WDIR/prompt.md = 고정 머리말 + 사슬 판 생성기 step.md(파일 md5 = 사슬 판일 때만 · 아니면 종료 10)
##     compile <사슬> <WDIR> <k>             생성 산출(out.md) 검사 → <사슬>/cells/k<k>.json · WDIR/open/*.txt · stdout "ok" | "reject <code> <한 줄>"(종료 0 | 10)
##     abandon-reason <사슬> <k>             포기 사유 문장(숫자 · 날짜 없음 — 코어 rc_input_issues 통과)
##     notify <사슬> close_wait <reason>     '닫기 대기' prep_send 1통(사슬 · 사유당 한 번 — 발송 성공 뒤 장부 표식) · 발송 = QVEST_UNATTENDED=1 ∧ CT_DRY≠1
##                                           출력 sent | seen | dry(발송 아님 · 표식 없음) | failed(종료 1 · 표식 없음 → 다음 틱 재시도)
##     record <chain_id> <사건> [값]          장부: served · gen_ok · gen_fail <code> · decide_ok · decide_error <k> · mark <key>(new|seen 출력)
##                                           · mark_daily <key>(하루 단위 new|seen — 판독 실패 · 정지 알림용)
##     state <chain_id> <key>                장부 값 한 개
##     backoff-set <reason> · backoff-active  한도 물러남(다음 날 00:00 까지 생성만 멈춤) · yes|no
##     reset <chain_id>                      장부의 생성 차단 · 연속 실패 · 판정 오류만 지운다(원장 무접촉)
##   루트 = CLAUDE_PROJECT_DIR → QM_ROOT → 기본(r-portability.md) · 코드 루트 = 이 파일 위치(같은 저장소)
##   시험 주입: CT_CFG · CT_STATE_DIR · CT_NOW(YYYY-mm-dd HH:MM:SS) · RC_RXG_PATH(생성기 등록부 · 코어 기존) · CT_VINTAGE_STUB(json 파일 — 판 표식 대체)

CT_PREAMBLE_ID <- "ct_preamble_v1"
CT_ACTIONS <- c("skip", "broken", "close_stuck", "blocked", "measure_base", "wait", "close_wait", "decide", "abandon", "measure_step", "open")

.ct_root <- function() {
  r <- Sys.getenv("CLAUDE_PROJECT_DIR", ""); if (!nzchar(r)) r <- Sys.getenv("QM_ROOT", "")
  if (!nzchar(r)) r <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
  sub("/+$", "", gsub("\\\\", "/", r))
}
.ct_code_root <- function() {
  of <- NULL
  for (i in rev(seq_len(sys.nframe()))) { f <- sys.frame(i); if (!is.null(f$ofile)) { of <- f$ofile; break } }
  if (is.null(of)) { a <- grep("^--file=", commandArgs(FALSE), value = TRUE); if (length(a)) of <- sub("^--file=", "", a[1]) }
  if (is.null(of)) return(.ct_root())
  p <- gsub("\\\\", "/", of); if (!grepl("^([A-Za-z]:|/)", p)) p <- file.path(gsub("\\\\", "/", getwd()), p)
  dirname(dirname(dirname(p)))
}
.ct_or <- function(a, b) if (is.null(a) || !length(a)) b else a
.ct_now <- function() { n <- Sys.getenv("CT_NOW", ""); if (nzchar(n)) as.POSIXct(n, format = "%Y-%m-%d %H:%M:%S") else Sys.time() }
.ct_abs <- function(p, root) { p <- gsub("\\\\", "/", p); if (grepl("^([A-Za-z]:|/)", p)) p else file.path(root, p) }
.ct_rel <- function(p, root) { p <- gsub("\\\\", "/", p); r <- paste0(root, "/"); if (startsWith(tolower(p), tolower(r))) substring(p, nchar(r) + 1L) else p }
.ct_load_core <- function(root, code_root = .ct_code_root()) {
  if (exists("rc_p4_steps_verify", mode = "function") && exists("rx_validate", mode = "function")) return(invisible(TRUE))
  Sys.setenv(QM_ROOT = root)                                                     # 코어 rc_root() = QM_ROOT 우선 — 계획기 루트와 같게
  suppressPackageStartupMessages({ library(jsonlite); library(data.table) })
  invisible(capture.output(suppressMessages(source(file.path(code_root, "04_Research/programs/_lib/round_core/v1/load.R")))))
  if (!exists("rx_validate", mode = "function")) invisible(capture.output(suppressMessages(source(file.path(code_root, "02_Infrastructure/programs/rx_round.R")))))
  invisible(TRUE)
}

## ── 설정 ─────────────────────────────────────────────────────────────────────
ct_config_path <- function(root) { p <- Sys.getenv("CT_CFG", ""); if (nzchar(p)) p else file.path(root, "06_Registry/chain_tick.json") }
ct_config <- function(root = .ct_root(), path = ct_config_path(root)) {
  if (!file.exists(path)) stop("설정 없음: ", path)
  C <- jsonlite::fromJSON(path, simplifyVector = FALSE)
  if (!identical(C$schema, "chain_tick_v1")) stop("설정 schema ≠ chain_tick_v1")
  if (!(is.logical(C$enabled) && length(C$enabled) == 1L && !is.na(C$enabled))) stop("enabled 는 true/false")
  for (k in c("measures_per_tick", "gen_calls_per_chain_per_tick", "gen_timeout_sec")) {
    v <- suppressWarnings(as.integer(C[[k]])); if (length(v) != 1L || is.na(v) || v < 1L) stop("설정 ", k, " 는 1 이상 정수")
    if (!nzchar(as.character(.ct_or(C[[paste0(k, "_source")]], "")))) stop("설정 ", k, " 근거(", k, "_source) 없음")
    C[[k]] <- v
  }
  if (!(is.character(C$lanes_dir) && length(C$lanes_dir) == 1L && nzchar(C$lanes_dir))) stop("lanes_dir 없음")
  if (!(is.character(C$llm_lane) && length(C$llm_lane) == 1L && nzchar(C$llm_lane))) stop("llm_lane 없음")
  C
}

## ── 틱 장부(원장 아님 · 원자적 쓰기 · 깨진 장부 = 빈 장부) ──────────────────────────
ct_state_dir <- function(root) { d <- Sys.getenv("CT_STATE_DIR", ""); if (nzchar(d)) d else file.path(root, ".cache/chain_tick") }
.ct_sf <- function(sd, cid) file.path(sd, "state", paste0(cid, ".json"))
ct_state_read <- function(sd, cid) { f <- .ct_sf(sd, cid); if (!file.exists(f)) return(list()); tryCatch(jsonlite::fromJSON(f, simplifyVector = FALSE), error = function(e) list()) }
.ct_write_json <- function(x, f) {
  dir.create(dirname(f), recursive = TRUE, showWarnings = FALSE); tmp <- paste0(f, ".tmp", Sys.getpid())
  writeLines(enc2utf8(as.character(jsonlite::toJSON(x, auto_unbox = TRUE, null = "null", pretty = TRUE))), tmp, useBytes = TRUE)
  if (!file.rename(tmp, f)) { suppressWarnings(Sys.chmod(f, "666")); unlink(f); if (!file.rename(tmp, f)) stop("장부 쓰기 실패: ", f) }
  invisible(f)
}
ct_state_write <- function(sd, cid, S) .ct_write_json(S, .ct_sf(sd, cid))
ct_record <- function(sd, cid, ev, val = NULL, max_fails = NULL) {
  S <- ct_state_read(sd, cid); now <- format(.ct_now(), "%Y-%m-%dT%H:%M:%S"); out <- ""
  if (is.null(max_fails)) max_fails <- .ct_max_fails()
  switch(ev,
    served = { S$last_served_at <- now },
    gen_ok = { S$consecutive_gen_failures <- 0L; S$last_gen_failures <- list() },
    gen_fail = { n <- as.integer(.ct_or(S$consecutive_gen_failures, 0L)) + 1L; S$consecutive_gen_failures <- n
                 S$last_gen_failures <- c(tail(.ct_or(S$last_gen_failures, list()), 1L), list(.ct_or(val, "?")))
                 if (n >= max_fails) S$gen_blocked <- TRUE
                 out <- if (isTRUE(S$gen_blocked)) "blocked" else sprintf("count=%d", n) },
    decide_ok = { S$decide_errors <- list() },
    decide_error = { de <- .ct_or(S$decide_errors, list()); kk <- as.character(.ct_or(val, "?")); de[[kk]] <- as.integer(.ct_or(de[[kk]], 0L)) + 1L
                     S$decide_errors <- de; out <- if (de[[kk]] >= max_fails) "blocked" else sprintf("count=%d", de[[kk]]) },
    mark = { mk <- .ct_or(S$marks, list()); key <- as.character(.ct_or(val, "?"))
             if (!is.null(mk[[key]])) out <- "seen" else { mk[[key]] <- now; S$marks <- mk; out <- "new" } },
    ## 하루 단위 표식(재수리 11-10 · 판독 실패 · 정지 알림) — 키 = <표식>@YYYYmmdd · 같은 표식의 다른 날 키는 지운다
    ##   단위 = sched_alert_emit 의 하루 스로틀과 같다(영구 표식이면 한 번 회복된 뒤 같은 사유의 재정지가 무음이 된다)
    mark_daily = { mk <- .ct_or(S$marks, list()); b <- as.character(.ct_or(val, "?")); key <- paste0(b, "@", format(.ct_now(), "%Y%m%d"))
                   nm <- as.character(.ct_or(names(mk), character(0))); old <- nm[startsWith(nm, paste0(b, "@")) & nm != key]; if (length(old)) mk[old] <- NULL
                   if (!is.null(mk[[key]])) out <- "seen" else { mk[[key]] <- now; out <- "new" }
                   S$marks <- mk },
    stop("모르는 장부 사건: ", ev))
  ct_state_write(sd, cid, S); out
}
ct_reset <- function(sd, cid) {
  S <- ct_state_read(sd, cid); S$gen_blocked <- NULL; S$consecutive_gen_failures <- 0L; S$last_gen_failures <- list(); S$decide_errors <- list()
  m <- .ct_or(S$marks, list()); if (length(m)) m <- m[!grepl("^(gen_blocked|decide_failed)", names(m))]; S$marks <- m
  ct_state_write(sd, cid, S); invisible(S)
}
.ct_bf <- function(sd) file.path(sd, "llm_backoff.json")
ct_backoff_set <- function(sd, reason) {
  until <- format(as.Date(format(.ct_now(), "%Y-%m-%d")) + 1L, "%Y-%m-%d 00:00:00")
  .ct_write_json(list(until = until, reason = reason, set_at = format(.ct_now(), "%Y-%m-%d %H:%M:%S")), .ct_bf(sd)); until
}
ct_backoff_active <- function(sd) {
  f <- .ct_bf(sd); if (!file.exists(f)) return(FALSE)
  b <- tryCatch(jsonlite::fromJSON(f), error = function(e) NULL); if (is.null(b$until)) return(FALSE)
  u <- as.POSIXct(b$until, format = "%Y-%m-%d %H:%M:%S"); !is.na(u) && .ct_now() < u
}
.ct_max_fails <- function() if (exists("RC_STANDING_MAX_FAILS")) as.integer(RC_STANDING_MAX_FAILS) else {
  ## 코어 상수(standing.R::RC_STANDING_MAX_FAILS)를 적재 없이 읽는다 — 사본 숫자를 두지 않는다
  f <- file.path(.ct_code_root(), "04_Research/programs/_lib/round_core/v1/standing.R")
  l <- grep("^RC_STANDING_MAX_FAILS <- ", readLines(f, encoding = "UTF-8", warn = FALSE), value = TRUE)
  v <- suppressWarnings(as.integer(sub("L.*$", "", sub("^RC_STANDING_MAX_FAILS <- ", "", l[1])))); if (is.na(v)) stop("RC_STANDING_MAX_FAILS 판독 불가"); v }

## ── 계획기(읽기 전용) ─────────────────────────────────────────────────────────────
.ct_vintage <- function(root) {
  stub <- Sys.getenv("CT_VINTAGE_STUB", "")
  vf <- if (nzchar(stub)) function(root) jsonlite::fromJSON(stub, simplifyVector = FALSE) else rc_p4_vintage_default
  .rcp4_vint(vf, root)
}
.ct_out <- function(action, k = NA_integer_, reason = "", detail = "") list(action = action, k = as.integer(k), reason = reason, detail = detail)
ct_plan <- function(chain_dir, root = .ct_root(), sd = ct_state_dir(root), gen_path = NULL, vintage_fun = .ct_vintage) {
  cd <- .ct_abs(chain_dir, root); sp <- file.path(cd, "chain_steps.jsonl")
  if (!file.exists(file.path(cd, "chain_spec.json"))) return(.ct_out("skip", reason = "no_spec", detail = "사슬 판 없음"))
  if (!file.exists(sp)) return(.ct_out("skip", reason = "unregistered", detail = "등록 전(원장 없음) — 등록은 감독 아래"))
  v <- tryCatch(rc_p4_steps_verify(cd), error = function(e) list(ok = FALSE, bad = conditionMessage(e)))
  if (!isTRUE(v$ok)) return(.ct_out("broken", reason = "ledger_broken", detail = "걸음 원장 사슬 끊김 — 격리는 사람(p4-quarantine)"))
  if (identical(v$n, 0L)) return(.ct_out("skip", reason = "unregistered", detail = "원장이 비었다"))
  st <- tryCatch(.rcp4_state(cd, root, need_registered = FALSE), error = function(e) structure(list(), err = conditionMessage(e)))
  if (!is.null(attr(st, "err"))) return(.ct_out("broken", reason = if (grepl("R2", attr(st, "err"))) "spec_changed" else "state_unreadable",
                                                detail = "사슬 상태 판독 불가(사슬 판 변경 등) — 사람이 본다"))
  if (is.null(st$reg) || !identical(st$recs[[1]]$event, "chain_registered")) return(.ct_out("skip", reason = "unregistered", detail = "첫 사건이 등록이 아니다"))
  if (isTRUE(st$closed)) return(.ct_out("skip", reason = "closed", detail = "닫힌 사슬"))
  if (isTRUE(st$closing)) return(.ct_out("close_stuck", reason = "closing", detail = "닫기 중단(chain_closing) — 세션이 p4-close 를 다시 실행해 마무리한다"))
  if (file.exists(file.path(cd, "tick_hold"))) return(.ct_out("skip", reason = "held_by_session", detail = "tick_hold — 세션이 손으로 돌리는 중"))
  mf <- .ct_max_fails(); S <- ct_state_read(sd, st$spec$chain_id)
  if (is.null(st$base_meas)) {
    nbf <- length(.rcp4_ev(st$recs, "base_measure_failed"))
    if (nbf >= mf) return(.ct_out("blocked", 0L, "base_failed", "기준 칸 측정 실패가 상한에 닿았다 — 사람이 본다(기준 칸 포기 경로 없음)"))
  }
  ## 판 표식은 기준 칸 측정 앞에서도 본다(재수리 11-10) — 수리 진행 중 · 판독 불가면 코어도 재지 않는다(p4.R .rcp4_run_cell) → 부르지 않고 기다린다
  v0 <- tryCatch(vintage_fun(root), error = function(e) NULL)
  if (is.null(v0)) return(.ct_out("wait", reason = "vintage_unknown", detail = "팩터 DB 판 표식 판독 불가 — 측정 · 판정 안 함"))
  if (isTRUE(suppressWarnings(as.numeric(v0$n_in_progress)) > 0)) return(.ct_out("wait", reason = "vintage_in_progress", detail = "팩터 DB 수리 진행 중 — 다음 틱"))
  if (is.null(st$base_meas)) return(.ct_out("measure_base", 0L, "", "기준 칸 측정"))
  if (!identical(v0$id, st$base_meas$vintage$id)) return(.ct_out("close_wait", reason = "vintage_changed", detail = "팩터 DB 판이 기준 칸 측정 뒤 바뀌었다 — 이 사슬을 닫고 새 사슬에서"))
  und <- setdiff(st$open_ks, st$decided_ks)
  if (length(und)) {
    k <- min(und)
    if (!is.null(.rcp4_measured_of(st, k))) {
      de <- as.integer(.ct_or(.ct_or(S$decide_errors, list())[[as.character(k)]], 0L))
      if (de >= mf) return(.ct_out("blocked", k, "decide_failed", "걸음 판정 오류가 상한에 닿았다 — 사람이 본다"))
      return(.ct_out("decide", k, "", "측정된 걸음 판정"))
    }
    nf <- length(.rcp4_ev(st$recs, "step_measure_failed", k))
    if (nf >= mf) return(.ct_out("abandon", k, "measure_failed", "측정 실패가 상한에 닿았다 — 포기 기록(가설 기각 아님)"))
    return(.ct_out("measure_step", k, "", "열린 걸음 측정"))
  }
  mx <- suppressWarnings(as.integer(st$spec$budget$max_steps)); nk <- suppressWarnings(as.integer(st$spec$budget$noise_k))
  if (length(mx) != 1L || is.na(mx) || length(nk) != 1L || is.na(nk)) return(.ct_out("broken", reason = "budget_unreadable", detail = "사슬 판 예산 판독 불가"))
  if (length(st$open_ks) >= mx) return(.ct_out("close_wait", reason = "budget_steps", detail = "최대 걸음 수에 닿았다"))
  if (st$noise_streak >= nk) return(.ct_out("close_wait", reason = "budget_noise", detail = "연속 '잡음 이내'가 K 에 닿았다(목표 축 R7)"))
  gv <- tryCatch(rxg_files_md5(rxg_get(st$spec$generator$id, root, gen_path)$dir, root), error = function(e) NULL)
  gs <- st$spec$generator$files
  if (is.null(gv) || !identical(unlist(gv[sort(names(gv))]), unlist(gs[sort(names(gs))]))) return(.ct_out("close_wait", reason = "generator_changed", detail = "생성기 판 파일이 사슬 판과 다르다 — 새 사슬 판은 감독 아래"))
  if (isTRUE(S$gen_blocked)) return(.ct_out("blocked", length(st$open_ks) + 1L, "gen_failures", "생성 연속 실패 상한 — chain_tick.sh --reset <chain_id> 로 푼다"))
  .ct_out("open", length(st$open_ks) + 1L, "", sprintf("다음 걸음 설계(부모 %d)", st$head_k))
}
ct_chains <- function(root) {
  ds <- Sys.glob(file.path(root, "04_Research/programs/P4_ASSEMBLY/*/chain_spec.json")); ds <- dirname(ds)
  ds[!startsWith(basename(ds), "_")]
}
.ct_line <- function(p) paste(p$action, ifelse(is.na(p$k), "-", p$k), ifelse(nzchar(p$reason), p$reason, "-"), gsub("[\t\r\n]+", " ", p$detail), sep = "\t")

## ── 프롬프트 · 컴파일 ─────────────────────────────────────────────────────────────
CT_PROMPT_PREAMBLE <- function(wdir) paste0("작업 디렉터리: ", gsub("\\\\", "/", wdir), "\n",
                                            "이 디렉터리의 네 파일(design_input.md · investment_philosophy_charter.md · toolbox.md · parent_cell_spec.json)만 Read 로 읽는다. 다른 경로는 읽지 않는다.\n",
                                            "(머리말 판 ", CT_PREAMBLE_ID, ")\n\n")
ct_prompt <- function(chain_dir, wdir, root = .ct_root(), gen_path = NULL) {
  cd <- .ct_abs(chain_dir, root); wd <- .ct_abs(wdir, root); st <- .rcp4_state(cd, root)
  g <- rxg_get(st$spec$generator$id, root, gen_path); gd <- .ct_abs(g$dir, root); gv <- rxg_files_md5(g$dir, root); gs <- st$spec$generator$files
  if (!identical(unlist(gv[sort(names(gv))]), unlist(gs[sort(names(gs))]))) return(list(ok = FALSE, code = "generator_changed"))
  sf <- file.path(gd, "step.md"); if (!file.exists(sf)) return(list(ok = FALSE, code = "no_step_md"))
  body <- readBin(sf, "raw", file.info(sf)$size)
  con <- file(file.path(wd, "prompt.md"), open = "wb"); on.exit(close(con)); writeBin(c(charToRaw(enc2utf8(CT_PROMPT_PREAMBLE(wd))), body), con)
  list(ok = TRUE, code = "ok", path = file.path(wd, "prompt.md"))
}
.ct_rej <- function(code, msg) list(ok = FALSE, code = code, msg = gsub("[\r\n]+", " ", msg))
ct_compile <- function(chain_dir, wdir, k, root = .ct_root(), pool = NULL) {
  cd <- .ct_abs(chain_dir, root); wd <- .ct_abs(wdir, root); k <- suppressWarnings(as.integer(k))
  st <- tryCatch(.rcp4_state(cd, root), error = function(e) NULL); if (is.null(st)) return(.ct_rej("state", "사슬 상태 판독 불가"))
  if (is.na(k) || !identical(k, length(st$open_ks) + 1L) || length(setdiff(st$open_ks, st$decided_ks))) return(.ct_rej("race", "다음 걸음 번호가 아니다(세션과 경합)"))
  gr <- tryCatch(jsonlite::fromJSON(file.path(wd, "gen_result.json")), error = function(e) NULL)
  if (is.null(gr) || !identical(as.integer(gr$rc), 0L)) return(.ct_rej("gen_rc", "생성기 결과 rc ≠ 0 또는 없음"))
  of <- file.path(wd, "out.md"); if (!file.exists(of)) return(.ct_rej("parse", "out.md 없음"))
  txt <- readLines(of, encoding = "UTF-8", warn = FALSE)
  J <- tryCatch(rx_parse_json(txt), error = function(e) NULL); if (is.null(J) || !is.list(J)) return(.ct_rej("parse", "마지막 json 블록 판독 불가"))
  one <- function(x) is.character(x) && length(x) == 1L && !is.na(x) && nzchar(trimws(x))
  if (!(one(J$hypothesis) && one(J$mechanism) && one(J$block_type) && is.list(J$delta) && length(J$delta) && !is.null(names(J$delta)) && all(nzchar(names(J$delta)))))
    return(.ct_rej("schema", "필수 키(hypothesis · mechanism · block_type · delta) 없음 또는 모양 오류"))
  if (!(J$block_type %in% RC_P4_BLOCK_TYPES)) return(.ct_rej("block", paste0("블록 유형 어휘 밖: ", J$block_type)))
  tau <- st$tau
  ci <- rc_input_issues(Filter(Negate(is.null), J[c("hypothesis", "mechanism", "expected_direction", "falsification", "philosophy_alignment")]), tau)
  if (!isTRUE(ci$ok)) return(.ct_rej("contaminated", paste0("처방 입력 금지 정보: ", ci$why)))
  lk <- rc_after_tau_leaks(paste(txt, collapse = "\n"), tau)
  if (length(lk)) return(.ct_rej("contaminated", "산출 전문에 τ_D 뒤 날짜"))
  ## 기저 풀은 기저 신호를 바꾸는 걸음만 쓴다(rx_validate · rc_p4_spec_diff 의 base_signal 검사) — 그 밖에는 읽지 않는다
  if (is.null(pool) && !is.null(J$delta$base_signal)) pool <- tryCatch(rc_p4_base_pool(root), error = function(e) NULL)
  V <- tryCatch(rx_validate(J$delta, root, pool = pool), error = function(e) list(ok = FALSE, errors = conditionMessage(e)))
  if (!isTRUE(V$ok)) return(.ct_rej("invalid", paste(head(unlist(V$errors), 3), collapse = " · ")))
  pf <- file.path(wd, "parent_cell_spec.json"); if (!file.exists(pf)) return(.ct_rej("parent", "parent_cell_spec.json 없음"))
  parent <- rc_json_read(pf)
  cell <- tryCatch(rx_compile_spec(parent, V$delta, code = sprintf("%s_k%d", st$spec$chain_id, k), label = sprintf("%s 걸음 %d", st$spec$chain_id, k),
                                   idea = J$hypothesis, selection_accounting = parent$selection_accounting, root = root), error = function(e) NULL)
  if (is.null(cell)) return(.ct_rej("invalid", "칸 사양 컴파일 실패"))
  dif <- tryCatch(rc_p4_spec_diff(parent, cell, J$block_type, root, pool), error = function(e) list(ok = FALSE, why = conditionMessage(e)))
  if (!isTRUE(dif$ok)) return(.ct_rej("diff", paste(head(unlist(dif$why), 3), collapse = " · ")))
  cf <- file.path(cd, "cells", sprintf("k%d.json", k)); cr <- .ct_rel(cf, root)
  used <- vapply(st$opens, function(r) gsub("\\\\", "/", as.character(.ct_or(r$cell_spec_path, ""))), "")
  if (cr %in% used || .ct_rel(cf, root) %in% vapply(used, .ct_rel, "", root = root)) return(.ct_rej("r2", "원장이 이미 참조하는 칸 사양 파일 — 덮지 않는다(R2)"))
  dir.create(dirname(cf), recursive = TRUE, showWarnings = FALSE); tmp <- paste0(cf, ".tmp", Sys.getpid())
  rc_json_write(cell, tmp); if (file.exists(cf)) { suppressWarnings(Sys.chmod(cf, "666")); unlink(cf) }
  if (!file.rename(tmp, cf)) return(.ct_rej("io", "칸 사양 쓰기 실패"))
  od <- file.path(wd, "open"); dir.create(od, showWarnings = FALSE)
  w <- function(nm, v) { con <- file(file.path(od, nm), open = "wb"); writeBin(charToRaw(enc2utf8(gsub("[\r\n]+", " ", v))), con); close(con) }
  w("hypothesis.txt", J$hypothesis); w("mechanism.txt", J$mechanism); w("block.txt", J$block_type); w("cell.txt", cr)
  w("parent.txt", as.character(st$head_k)); w("generator.txt", st$spec$generator$id); w("k.txt", as.character(k))
  list(ok = TRUE, code = "ok", msg = cr, cell = cf)
}
ct_abandon_reason <- function(chain_dir, k, root = .ct_root()) {
  r <- "정본 셀 워커 측정이 반복해 실패했다 — 무인 틱이 포기를 기록한다(가설 기각 아님 · 원인은 측정 로그)"
  cd <- .ct_abs(chain_dir, root); st <- .rcp4_state(cd, root)
  if (!isTRUE(rc_input_issues(list(r), st$tau)$ok)) stop("포기 사유 문장이 처방 입력 검사를 통과하지 못한다")
  r
}

## ── 알림(닫기 대기 · prep_send 1통 · 사슬 · 사유당 한 번) ──────────────────────────────
ct_notify_close_wait <- function(chain_dir, reason, root = .ct_root(), sd = ct_state_dir(root), detail = "") {
  cd <- .ct_abs(chain_dir, root); st <- .rcp4_state(cd, root); cid <- st$spec$chain_id
  ## 표식은 실제 발송이 성공한 뒤에만 남긴다(재수리 11-10) — 보내기 전 표식 · 반환값 무시 = 일시 실패 한 번에 감독 단계 신호가 영구히 사라졌다
  ##   틱 잠금이 실행을 직렬화하므로 '확인 → 발송 → 표식' 두 단계로 충분하다. 발송이 아닌 실행(수동 · CT_DRY)은 표식을 남기지 않는다(무인 실행의 1통을 막지 않는다)
  mkey <- paste0("close_wait:", reason)
  if (!is.null(.ct_or(ct_state_read(sd, cid)$marks, list())[[mkey]])) return("seen")
  res <- st$results; na <- sum(vapply(res, function(r) identical(r$decision, "accept"), TRUE)); nab <- sum(vapply(res, function(r) isTRUE(r$abandoned), TRUE))
  nr <- length(res) - na - nab
  why <- switch(reason, budget_steps = "최대 걸음 수에 닿았다", budget_noise = "연속 '잡음 이내'가 K 에 닿았다(목표 축 R7)",
                vintage_changed = "팩터 DB 판이 기준 칸 측정 뒤 바뀌었다(새 사슬에서 기준 칸부터)", generator_changed = "생성기 판 파일이 사슬 판과 다르다", reason)
  push <- identical(Sys.getenv("QVEST_UNATTENDED"), "1") && !identical(Sys.getenv("CT_DRY"), "1")
  if (!exists("prep_send", mode = "function")) invisible(capture.output(suppressMessages(source(file.path(.ct_code_root(), "02_Infrastructure/programs/program_report.R")))))
  r <- tryCatch(prep_send(program = "P4_ASSEMBLY", target = cid,
                          status = list(stage = "닫기 대기", position = sprintf("걸음 %d(채택 %d · 기각 %d · 포기 %d)", length(res), na, nr, nab),
                                        previous = if (length(res)) as.character(res[[length(res)]]$decision) else "—"),
                          verdict_line = paste0("닫기 대기 — ", why),
                          next_step = sprintf("세션: 철학 P2 · 판단 T2 뒤 round.sh %s p4-close --regrade-write", .ct_rel(cd, root)),
                          push = push, dry_run = !push, root = root), error = function(e) structure(FALSE, err = conditionMessage(e)))
  if (!is.null(attr(r, "err"))) { cat("notify 실패:", attr(r, "err"), "\n"); return("failed") }
  if (!(is.list(r) && isTRUE(r$ok))) { cat("notify 실패: 발송 결과 ok 아님\n"); return("failed") }      # tg_agent_brief 는 실패를 list(ok = FALSE) 로 돌려준다
  if (!push) return("dry")
  ct_record(sd, cid, "mark", mkey)
  "sent"
}

## ── CLI ─────────────────────────────────────────────────────────────────────
if (sys.nframe() == 0L) {
  a <- commandArgs(trailingOnly = TRUE); cmd <- if (length(a)) a[1] else ""
  ROOT <- .ct_root(); SD <- ct_state_dir(ROOT)
  die <- function(code, ...) { cat(..., "\n", sep = ""); quit(save = "no", status = code) }
  suppressPackageStartupMessages(library(jsonlite))
  if (identical(cmd, "config")) {
    C <- tryCatch(ct_config(ROOT), error = function(e) die(2L, "config_unreadable\t", conditionMessage(e)))
    if (length(a) >= 2L) { v <- C[[a[2]]]; if (is.null(v)) die(2L, "config_key_missing\t", a[2]); cat(if (is.logical(v)) tolower(as.character(v)) else as.character(v), "\n", sep = "") }
    else cat("ok\n"); quit(save = "no", status = 0L)
  }
  if (identical(cmd, "record")) { cat(ct_record(SD, a[2], a[3], if (length(a) >= 4L) a[4] else NULL), "\n", sep = ""); quit(save = "no", status = 0L) }
  if (identical(cmd, "state")) { v <- ct_state_read(SD, a[2])[[a[3]]]; cat(if (is.null(v)) "" else paste(unlist(v), collapse = ","), "\n", sep = ""); quit(save = "no", status = 0L) }
  if (identical(cmd, "backoff-set")) { cat(ct_backoff_set(SD, .ct_or(a[2], "usage_limit")), "\n", sep = ""); quit(save = "no", status = 0L) }
  if (identical(cmd, "backoff-active")) { cat(if (ct_backoff_active(SD)) "yes" else "no", "\n", sep = ""); quit(save = "no", status = 0L) }
  if (identical(cmd, "reset")) { ct_reset(SD, a[2]); cat("reset ", a[2], " — 장부의 생성 차단 · 연속 실패 · 판정 오류를 지웠다(원장 무접촉)\n", sep = ""); quit(save = "no", status = 0L) }
  .ct_load_core(ROOT)
  switch(cmd,
    plan = { p <- tryCatch(ct_plan(a[2], ROOT, SD), error = function(e) .ct_out("broken", reason = "plan_error", detail = conditionMessage(e))); cat(.ct_line(p), "\n", sep = "") },
    list = { for (d in ct_chains(ROOT)) { p <- tryCatch(ct_plan(d, ROOT, SD), error = function(e) .ct_out("broken", reason = "plan_error", detail = conditionMessage(e)))
               cid <- basename(d); cat(.ct_rel(d, ROOT), "\t", .ct_line(p), "\t", .ct_or(ct_state_read(SD, cid)$last_served_at, "-"), "\n", sep = "") } },
    prompt = { r <- ct_prompt(a[2], a[3], ROOT); if (!isTRUE(r$ok)) die(10L, "reject ", r$code); cat("ok\n") },
    compile = { r <- tryCatch(ct_compile(a[2], a[3], a[4], ROOT), error = function(e) .ct_rej("error", conditionMessage(e)))
                if (!isTRUE(r$ok)) die(10L, "reject ", r$code, " ", r$msg); cat("ok ", r$msg, "\n", sep = "") },
    "abandon-reason" = cat(ct_abandon_reason(a[2], a[3], ROOT), "\n", sep = ""),
    notify = { if (!identical(a[3], "close_wait")) die(2L, "notify: close_wait 만")
               nr <- tryCatch(ct_notify_close_wait(a[2], a[4], ROOT, SD), error = function(e) { cat("notify 실패:", conditionMessage(e), "\n"); "failed" })
               cat(nr, "\n", sep = ""); if (identical(nr, "failed")) quit(save = "no", status = 1L) },
    die(2L, "usage: chain_tick.R config|plan|list|prompt|compile|abandon-reason|notify|record|state|backoff-set|backoff-active|reset"))
}
