#!/usr/bin/env Rscript
## 판 2(P1S02) 진행 상황 텔레그램 주기 보고 — 1회분(도훈 11-12 "텔레 주기적으로 보내")
##   상태를 읽기만 한다: 등록 여부 · 초안 · 점검 기록 · 상설 원장(항목 · 측정 · 판정 개수) · 시드 감시 셸 상태 · 데이터 신선도 · 레인 GPU 슬롯.
##   지난 발송과 상태 지문이 다르거나 마지막 발송 뒤 HEARTBEAT(기본 2시간)가 지났으면 prep_send 1통(무음).
##   이정표(단계 · 측정 기록 · 판정 · 평가 실패 개수)가 바뀌면 푸시. 첫 발송 · 마지막 발송도 푸시.
##   측정 · 판정 · 발송 외 쓰기 없음(원장 · 등록부 · 저널 무접촉 · 상태 파일 하나만) · 성과 수치는 싣지 않는다(판정 결과는 상설 판 보고가 따로 보낸다).
## 사용: Rscript <이 파일> [--force] [--dry-run] [--final "<사유>"]
##   종료 0 = 정상(보냈거나 바뀐 것 없음) · 10 = 시드 판정이 모두 끝나 마지막 보고를 보냈다(반복 셸이 멈춘다) · 1 = 오류
## 상태 = .cache/scheduler_logs/p1s02_tg_progress_state.json(마지막 발송 지문 · 시각 · 이정표 · 마지막 여부)
a <- commandArgs(trailingOnly = TRUE)
FORCE <- "--force" %in% a; DRY <- "--dry-run" %in% a
FINAL <- if ("--final" %in% a) a[which(a == "--final") + 1L] else NA_character_
ROOT <- gsub("\\\\", "/", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")); setwd(ROOT)
suppressMessages(source("04_Research/programs/_lib/round_core/v3/load.R"))
invisible(capture.output(suppressMessages(source("02_Infrastructure/programs/program_report.R"))))   # prep_send(1계층 발송 정본 · qvest-telegram §0)
HEARTBEAT_H <- suppressWarnings(as.numeric(Sys.getenv("P1S02_TG_HEARTBEAT_H", "2"))); if (!is.finite(HEARTBEAT_H)) HEARTBEAT_H <- 2
INTERVAL_MIN <- round(suppressWarnings(as.numeric(Sys.getenv("P1S02_TG_INTERVAL_S", "1800"))) / 60)
D <- "04_Research/programs/P1_RETURN/P1S02_standing_qualification"
SA <- "stage_artifacts/programs/P1_RETURN/P1S02_standing_qualification"
STATE <- ".cache/scheduler_logs/p1s02_tg_progress_state.json"
now <- Sys.time(); stamp <- format(now, "%m-%d %H:%M")
safe <- function(expr, default = NA) tryCatch(expr, error = function(e) default)

## ── 1. 판 2 단계 ─────────────────────────────────────────────────────────────
registered <- file.exists(file.path(SA, "prereg.json"))
drafts <- safe(rc_json_read(file.path(D, "drafts.json")), NULL)
dv <- if (is.list(drafts)) vapply(drafts$versions, function(v) sprintf("v%s %s", v$version, (v$review %||% list())$verdict %||% "점검 전"), "") else character(0)
last_rev <- if (is.list(drafts) && length(drafts$versions)) (drafts$versions[[length(drafts$versions)]]$review %||% list())$verdict %||% NA_character_ else NA_character_
rev2_file <- file.exists(file.path(D, "prereg_draft_review_v2.md"))

## ── 2. 상설 원장(등록 뒤) — 개수만 ─────────────────────────────────────────────
ledger <- file.path(SA, "standing_ledger.jsonl")
recs <- if (file.exists(ledger)) safe(rc_standing_ledger_read(ledger), list()) else list()
evn <- function(e) sum(vapply(recs, function(r) identical(r$event, e), TRUE))
n_meas <- evn("measure"); n_evalfail <- evn("eval_failed"); n_verdict <- evn("verdict")
n_meas_ok <- sum(vapply(recs, function(r) identical(r$event, "measure") && isTRUE(r$ok) && isTRUE(r$fp_same), TRUE))
I <- if (length(recs)) safe(rc_standing_items(recs), list()) else list()
src <- vapply(I, function(it) as.character(it$source %||% "?"), "")
n_seed <- sum(src == "seed"); n_scan <- sum(src == "scan")
vq <- Filter(Negate(is.null), lapply(I, function(it) it$verdict))
n_pass <- sum(vapply(vq, function(v) isTRUE(v$qualify), TRUE))
n_fail <- sum(vapply(vq, function(v) !isTRUE(v$qualify) && identical(as.character(v$status %||% ""), "evaluated"), TRUE))
n_untested <- length(vq) - n_pass - n_fail
seed_judged <- n_seed > 0L && all(vapply(I[src == "seed"], function(it) !is.null(it$verdict), TRUE))
n_reported <- evn("reported")

## ── 3. 시드 감시 셸 · 데이터 · 레인 ────────────────────────────────────────────
ws <- ".cache/scheduler_logs/p1s02_seed_watch_state.txt"
watch <- if (file.exists(ws)) { x <- readLines(ws, warn = FALSE, encoding = "UTF-8")[1]; p <- strsplit(x, "\t", fixed = TRUE)[[1]]
  list(at = p[1], state = p[2] %||% "?", age_min = round(as.numeric(difftime(now, file.mtime(ws), units = "mins")))) } else list(at = NA, state = "아직 띄우지 않음", age_min = NA)
watch_state <- gsub("P1S02_E2_C0", "시드 E2", gsub("P1S02_E3_RX0", "시드 E3", watch$state))
fr <- safe(rc_data_freshness(ROOT), list(state = "판독 불가", as_of = NA, ok = FALSE))
py <- Sys.getenv("QVEST_PY", ""); if (!nzchar(py)) py <- "python"
lane <- safe({
  o <- suppressWarnings(system2(py, c("-X", "utf8", "02_Infrastructure/ops/rf_replication_slots.py", "status", "--json"), stdout = TRUE, stderr = FALSE))
  j <- jsonlite::fromJSON(paste(o, collapse = "\n"), simplifyVector = FALSE)
  s <- Filter(function(x) identical(x$slot, "gpu1"), j$slots)
  if (length(s)) list(claim = as.character(s[[1]]$claim %||% "?"), paper = as.character(s[[1]]$paper %||% "-")) else list(claim = "슬롯 없음", paper = "-")
}, list(claim = "판독 불가", paper = "-"))
lease <- safe(rc_json_read(".cache/gpu_lease.json")$holder %||% "", "")

## ── 4. 단계 판정(사람이 읽는 말) ───────────────────────────────────────────────
stage_key <- local({   # (최상위에서 줄 머리 else 는 구문 오류 — 블록 안에 둔다)
  if (!registered) { if (identical(last_rev, "ok")) "ready_to_register" else "draft_review" }
  else if (seed_judged) "judged"
  else if (n_meas_ok > 0L && n_verdict == 0L && !grepl("^M ", watch$state)) "measured_wait_judge"
  else if (grepl("^M ", watch$state)) "measuring"
  else "registered_waiting"
})
stage_label <- switch(stage_key,
  draft_review = "등록 전 — 사전등록 초안 점검",
  ready_to_register = "등록 전 — 점검 ok · 등록 대기",
  registered_waiting = "등록됨 — 시드 측정 대기(감시 셸)",
  measuring = "시드 측정 중(감시 셸)",
  measured_wait_judge = "측정 끝 — 판정 전 점검 · 판정 대기(세션)",
  judged = "시드 판정 끝")
verdict_line <- switch(stage_key,
  draft_review = sprintf("초안 %s · %s", paste(dv, collapse = " → "), if (rev2_file) "격리 교차 점검 v2 파일 있음(기록 전)" else "격리 교차 점검 v2 진행 중"),
  ready_to_register = sprintf("초안 %s — 판 폴더 커밋 → 등록 → 시드 넣기", paste(dv, collapse = " → ")),
  registered_waiting = sprintf("항목 %d(시드 %d · 레인 %d) · 측정 기록 %d(정상 %d) · 판정 %d", length(I), n_seed, n_scan, n_meas, n_meas_ok, length(vq)),
  measuring = sprintf("항목 %d · 측정 기록 %d(정상 %d) · 판정 %d — %s", length(I), n_meas, n_meas_ok, length(vq), watch_state),
  measured_wait_judge = sprintf("측정 정상 %d · 판정 %d — 판정 전 점검 10항목을 본 뒤 judge", n_meas_ok, length(vq)),
  judged = sprintf("판정 %d(통과 %d · 미달 %d · 미시험 %d) · 보고 기록 %d", length(vq), n_pass, n_fail, n_untested, n_reported))
next_step <- switch(stage_key,
  draft_review = "격리 교차 점검 v2 수령 → 점검 기록 → 판 폴더 커밋(tick_hold 포함) → 등록 → 시드 넣기 → 감시 셸",
  ready_to_register = "판 폴더 커밋 → 등록 → 등록 커밋 → 시드 넣기 → 감시 셸 분리 실행",
  registered_waiting = "감시 셸: 낮 창(08:20~11:45 시작) · 자료 신선 · 레인 GPU 빔 · 메모리 ≥ 16 GB 가 서면 시드 E2 → E3 측정",
  measuring = "측정 끝 → 판정 전 점검 10항목 → judge → 상설 판 보고(세션)",
  measured_wait_judge = "판정 전 점검(기대값: 첫 엔진 신호일 2004-07-30 · 신호일 268) → judge → 상설 판 보고 → 판단 T2 · 철학 P2",
  judged = "판단 T2 · 철학 P2 → 판 1 정리 · S3 레인 출력 계약 → S7")

## ── 5. 지문 · 이정표 · 보낼지 ─────────────────────────────────────────────────
norm_watch <- gsub("[0-9]+", "#", watch$state)
fp <- paste(stage_key, length(I), n_meas, n_meas_ok, n_verdict, n_evalfail, n_reported, norm_watch, fr$state %||% "?", lane$claim, lane$paper, nzchar(lease), sep = "|")
mile <- paste(stage_key, n_meas, n_meas_ok, n_verdict, n_evalfail, sep = "|")
S0 <- safe(rc_json_read(STATE), NULL)
first <- is.null(S0)
if (!first && isTRUE(S0$final) && is.na(FINAL)) { cat(sprintf("[%s] 마지막 보고를 이미 보냈다 — 아무것도 안 함\n", stamp)); quit(status = 10L) }
since_h <- if (first) Inf else as.numeric(difftime(now, as.POSIXct(S0$sent_at, format = "%Y-%m-%dT%H:%M:%S"), units = "hours"))
changed <- first || !identical(S0$fp, fp)
milestone <- first || !identical(S0$mile, mile) || !is.na(FINAL) || (stage_key == "judged" && !isTRUE(S0$judged_sent))
send <- FORCE || changed || !is.finite(since_h) || since_h >= HEARTBEAT_H || !is.na(FINAL) || milestone
if (!send) { cat(sprintf("[%s] 바뀐 것 없음 · 마지막 발송 %.1f시간 전 — 보내지 않음\n", stamp, since_h)); quit(status = 0L) }

## ── 6. 보내기(prep_send · 1계층 표제) ─────────────────────────────────────────
items <- c(sprintf("초안: %s", if (length(dv)) paste(dv, collapse = " → ") else "없음"),
           sprintf("등록: %s", if (registered) "됨" else "아직"),
           if (registered) sprintf("원장: 항목 %d(시드 %d · 레인 %d) · 측정 %d(정상 %d) · 평가 실패 %d · 판정 %d(통과 %d · 미달 %d · 미시험 %d)",
                                   length(I), n_seed, n_scan, n_meas, n_meas_ok, n_evalfail, length(vq), n_pass, n_fail, n_untested),
           sprintf("시드 감시 셸: %s%s", watch_state, if (is.finite(watch$age_min %||% NA)) sprintf("(%d분 전 갱신)", as.integer(watch$age_min)) else ""),
           sprintf("데이터: %s · 기준일 %s", switch(as.character(fr$state %||% "?"), fresh = "신선", stale = "낡음 — 측정 관문이 막는다", as.character(fr$state %||% "?")), fr$as_of %||% "?"),
           sprintf("레인 GPU: %s%s", switch(lane$claim, live = "측정 중", free = "비어 있음", lane$claim), if (!identical(lane$paper, "-") && identical(lane$claim, "live")) paste0(" · ", lane$paper) else ""),
           if (nzchar(lease)) sprintf("GPU 임대: %s", sub("^rc_standing:P1S02:", "상설 판 2 ", lease)))
extra <- list(list(heading = "지금 상태", type = "bullet", items = unname(items)))
if (first || !is.na(FINAL))
  extra[[length(extra) + 1L]] <- list(heading = "주기 보고", type = "text",
    body = if (!is.na(FINAL)) FINAL else sprintf("%d분마다 확인 · 바뀌면 1통(무음) · 바뀐 것이 없어도 %s시간마다 1통(무음) · 단계 · 측정 · 판정 · 실패가 바뀌면 푸시 · 시드 판정이 끝나면 마지막 1통", INTERVAL_MIN, format(HEARTBEAT_H)))
prev <- if (first) "판 1(P1S01) 판정 0건 · 보류 · 판 2 리허설 통과(11-12 21:33)" else sprintf("지난 보고 %s", format(as.POSIXct(S0$sent_at, format = "%Y-%m-%dT%H:%M:%S"), "%m-%d %H:%M"))
push <- milestone || first || !is.na(FINAL)
r <- prep_send(program = "수익 엔진", target = sprintf("상설 자격 판 2 진행 상황 %s", stamp),
               status = list(stage = stage_label, position = "상설 자격 판 2 · 코어 v3 · 시드 2(2002.06975 DNN 계보)", previous = prev),
               verdict_line = verdict_line, next_step = next_step, extra = extra,
               artifact = "04_Research/01_reports/portfolio_paper_layer_split_20261112/BUILD_EDITION2.md", push = push, dry_run = DRY, root = ROOT)
ok <- isTRUE((r %||% list())$ok) || isTRUE(DRY)
cat(sprintf("[%s] 보냄 ok=%s · 푸시=%s · 단계 %s · 지문 바뀜 %s\n", stamp, ok, push, stage_key, changed))
if (ok && !DRY) rc_json_write(list(schema = "p1s02_tg_progress_state_v1", sent_at = format(now, "%Y-%m-%dT%H:%M:%S"), fp = fp, mile = mile,
                                    stage = stage_key, final = !is.na(FINAL) || stage_key == "judged", judged_sent = stage_key == "judged"), STATE)
quit(status = if (!ok) 1L else if (stage_key == "judged" || !is.na(FINAL)) 10L else 0L)
