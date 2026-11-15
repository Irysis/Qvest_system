## 1계층 진행 브리핑(매시 틱 직후 · 무음 1통) — 도훈 11-15 19시 "리서치 진행상황 브리핑을 좀 더 촘촘하게 해줘. 텔레그램으로 보고 싶은데 잘 확인이 안되네. 멈춰있나 싶어"
##   사슬 걸음(설계 · 측정 · 판정)은 chain_tick.sh 가 로그에만 남기고(13행 '푸시 없음(로그만)'), 상설 판은 통과 push · 미달 일 요약만 보낸다 —
##   진행과 대기를 텔레그램에서 볼 길이 없었다(11-15 16:38~ 사슬이 메모리 관문 대기 3틱째인데 텔레그램은 조용했다).
##   호출 = 예약 작업 Qvest_StandingBoard(02_Infrastructure/ops/scheduler/Qvest_StandingBoard.bat 마지막 단계 · 데이터 자가 복구 → 상설 판 → 사슬 틱 다음).
##   싣는 것: 열린 사슬(걸음 수 · 채택 · 기각 · 새 걸음 판정의 IS 증감 · 지금 상태와 대기 사유 · 연속 대기 틱) · 상설 자격 판(항목 · 판정 · 통과 · 대기 · 새 판정)
##            · 충실구현 레인(켜짐 · 처리 중 논문). 수치 = IS(보는 창) 기록만 — 사슬 원장 *_vis · 상설 원장 qualify · visible. OOS 값 · 전기간 등급은 싣지 않는다.
##   보내는 때: 08~23시 = 매시(변화가 없어도 대기 사유를 보낸다 — 멈춤과 대기를 가른다) · 00~07시 = 변화가 있을 때만. 상태 = .cache/l1_progress_brief_state.json
##   실패해도 틱에는 영향 없음(.bat 마지막 단계 · rc 는 작업 로그에만).
## 사용: Rscript 02_Infrastructure/programs/l1_progress_brief.R [--send] [--force]   (--send 없으면 드라이런 출력 · 상태 안 씀 · --force = 시간대 · 변화 무관)
a <- commandArgs(trailingOnly = TRUE); SEND <- "--send" %in% a; FORCE <- "--force" %in% a
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
suppressMessages(library(jsonlite))
STP <- Sys.getenv("L1PB_STATE", ".cache/l1_progress_brief_state.json")   # 시험 주입: L1PB_STATE(상태 파일) · L1PB_HOUR(시각)
now <- Sys.time(); hh <- as.integer(Sys.getenv("L1PB_HOUR", format(now, "%H")))
rj <- function(p) tryCatch(fromJSON(p, simplifyVector = FALSE), error = function(e) NULL)
rjl <- function(p) {
  L <- tryCatch(readLines(p, encoding = "UTF-8", warn = FALSE), error = function(e) character(0)); L <- L[nzchar(trimws(L))]
  Filter(Negate(is.null), lapply(L, function(x) tryCatch(fromJSON(x, simplifyVector = FALSE), error = function(e) NULL)))
}
num <- function(x) { v <- suppressWarnings(as.numeric(unlist(x))[1]); if (length(v) && is.finite(v)) v else NA_real_ }
f2 <- function(x) { v <- num(x); if (is.na(v)) "NA" else formatC(v, format = "f", digits = 2) }
sg <- function(x) { v <- num(x); if (is.na(v)) "NA" else paste0(if (v >= 0) "+" else "−", formatC(abs(v), format = "f", digits = 2)) }
evs <- function(R) vapply(R, function(r) as.character(r$event %||% ""), "")
CAT <- c(value = "밸류", growth = "성장", consensus = "컨센서스", accrual = "발생액", crowding = "쏠림", defense = "방어", investor_flow = "수급",
         leverage = "레버리지", liquidity = "유동성", momentum = "모멘텀", quality = "퀄리티", regime = "국면", risk = "위험", technical = "기술적")
eng_label <- function(p) {
  b <- basename(dirname(as.character(p)))
  if (grepl("^FC_FAM_", b)) { k <- sub("^FC_FAM_", "", b); ic <- grepl("_ICW$", k); k <- sub("_ICW$", "", k)
    l <- unname(CAT[k]); if (is.na(l)) l <- k; return(paste0(l, if (ic) "(IC 가중)" else "")) }
  if (grepl("^FC_TOTAL", b)) return("토탈")
  sub("^RP_AUTO_(CLEAN_)?", "", b)
}
RULE <- c(improve = "종합점수 S 개선 미달", uc_floor = "상승 포착 하한 미달", crisis_no_worse = "위기 하락노출 악화", bull_segments = "강세 구간 참여 미달",
          deep_crisis = "깊은 위기 악화", beta_asym = "하락 β > 상승 β")
JOB <- c("rf_replication_verify.R" = "충실구현 레인 검증", "rf_cell_worker.R" = "셀 측정", "dnn_rolling.py" = "DNN 학습")
hm_of <- function(p) { m <- regmatches(p, regexpr("[0-9]{8}_[0-9]{6}", p)); if (length(m)) paste0(substr(m, 10, 11), ":", substr(m, 12, 13)) else "?" }
st0 <- rj(STP) %||% list(); FIRST <- is.null(st0$sent_at)   # 첫 실행 = 기준선만(과거 기록을 '새' 것으로 세지 않는다)
cap <- function(x, n) if (length(x) > n) c(head(x, n), sprintf("외 %d건(산출물 원장)", length(x) - n)) else x

## ── 사슬 ─────────────────────────────────────────────────────────────────────────────
TL <- head(sort(Sys.glob(".cache/scheduler_logs/chain_tick_2*.log"), decreasing = TRUE), 24)
TLX <- lapply(TL, function(p) tryCatch(readLines(p, encoding = "UTF-8", warn = FALSE), error = function(e) character(0)))
classify <- function(z) {
  if (grepl("메모리 관문 대기", z, fixed = TRUE)) {
    hit <- unique(regmatches(z, gregexpr("rf_replication_verify\\.R|rf_cell_worker\\.R|dnn_rolling\\.py", z, perl = TRUE))[[1]])
    js <- unique(unname(JOB[hit]))
    return(list(kind = "wait_mem", why = if (length(js)) paste0("메모리 관문 대기(먼저 뜬 ", paste(js, collapse = " · "), ")") else "메모리 관문 대기(가용 메모리 부족)"))
  }
  if (grepl("생성 물러남", z, fixed = TRUE)) return(list(kind = "wait", why = "대기(생성기 사용 한도로 물러남)"))
  if (grepl("측정 예산 0", z, fixed = TRUE)) return(list(kind = "wait", why = "대기(이번 틱 측정 예산 소진)"))
  if (grepl("신선도 미달", z, fixed = TRUE)) return(list(kind = "wait", why = "대기(데이터 신선도 미달 — 밤 갱신 뒤)"))
  if (grepl("판정 —", z, fixed = TRUE)) return(list(kind = "step", why = "이번 틱에 걸음 판정"))
  if (grepl("measured", z, fixed = TRUE) || grepl("측정 —", z, fixed = TRUE)) return(list(kind = "step", why = "이번 틱에 걸음 측정"))
  if (grepl("열림", z, fixed = TRUE)) return(list(kind = "step", why = "이번 틱에 걸음 설계"))
  if (grepl("생성기 호출", z, fixed = TRUE)) return(list(kind = "step", why = "걸음 설계 중(생성기 호출)"))
  list(kind = "other", why = "틱 실행(걸음 변화 없음)")
}
CH <- list()
for (sp in Sys.glob("04_Research/programs/P4_ASSEMBLY/*/chain_steps.jsonl")) {
  cdir <- dirname(sp); id <- basename(cdir); R <- rjl(sp); ev <- evs(R)
  spec <- rj(file.path(cdir, "chain_spec.json")); held <- file.exists(file.path(cdir, "tick_hold"))
  closed <- any(ev == "chain_closed"); closing <- any(ev == "chain_closing")
  base <- if (!is.null(spec$base$engine_path)) eng_label(spec$base$engine_path) else "?"
  blend <- identical(unlist(spec$step_policy$blocks), "blend")
  label <- sprintf("%s 사슬(%s 기저)", if (blend) "블렌딩" else "강화", base)
  opens <- R[ev == "step_open"]; res <- R[ev == "step_result"]
  parts_of <- function(k) { o <- Filter(function(r) identical(as.integer(r$k), as.integer(k)), opens); if (!length(o)) return("?")
    cs <- rj(o[[1]]$cell_spec_path); p <- unlist(cs$base_signal$paths); if (length(p)) paste(vapply(p, eng_label, ""), collapse = " + ") else "?" }
  step_line <- function(r) {
    t <- r$table %||% list(); rl <- r$rules %||% list()
    bad <- unname(RULE[intersect(names(RULE), names(rl)[vapply(rl, function(v) isFALSE(v), TRUE)])])
    sprintf("걸음 %s %s(%s) — S %s(%s) · 상승 포착 Δ%s · 위기 하락노출 Δ%s%s", r$k, if (identical(r$decision, "accept")) "채택" else "기각",
            parts_of(r$k), f2(t$S_vis), sg(t$dS_vis), sg(t$d_uc_vis), sg(t$d_dd_capture_median_vis),
            if (length(bad)) paste0(" · 미달: ", paste(bad, collapse = " · ")) else "")
  }
  n0 <- as.integer(st0$chains[[id]]$n %||% 0L); new_idx <- if (length(R) > n0) seq.int(n0 + 1L, length(R)) else integer(0)
  new_res <- if (FIRST) list() else R[new_idx][ev[new_idx] == "step_result"]
  ## 지금 상태 = 이 사슬을 언급한 가장 최근 틱 로그 · 연속 메모리 관문 대기 틱 수
  per_tick <- lapply(seq_along(TL), function(i) { x <- TLX[[i]][grepl(paste0("[", id, "]"), TLX[[i]], fixed = TRUE)]; if (length(x)) classify(paste(x, collapse = "\n")) else NULL })
  hit <- which(!vapply(per_tick, is.null, TRUE)); cur <- if (length(hit)) per_tick[[hit[1]]] else NULL; cur_at <- if (length(hit)) hm_of(TL[hit[1]]) else "?"
  streak <- 0L; since <- cur_at
  for (i in hit) { if (identical(per_tick[[i]]$kind, "wait_mem")) { streak <- streak + 1L; since <- hm_of(TL[i]) } else break }
  state <- if (closed) "닫힘" else if (closing) "닫기 대기(손 단계)" else if (held) "보류(손 단계)" else if (is.null(cur)) "틱 기록 없음"
           else if (streak >= 2L) sprintf("%s · %d틱 연속(%s부터)", cur$why, streak, since) else sprintf("%s(%s 틱)", cur$why, cur_at)
  CH[[id]] <- list(id = id, n = length(R), label = label, held = held, closed = closed, state = state,
                   n_acc = sum(vapply(res, function(r) identical(r$decision, "accept"), TRUE)), n_rej = sum(vapply(res, function(r) identical(r$decision, "reject"), TRUE)),
                   last = if (length(res)) step_line(res[[length(res)]]) else "아직 판정한 걸음 없음",
                   new = vapply(new_res, step_line, ""), wait = isTRUE(cur$kind == "wait_mem"), streak = streak)
}
OPEN <- Filter(function(x) !x$held && !x$closed, CH); HELD <- Filter(function(x) x$held && !x$closed, CH)

## ── 상설 자격 판 ──────────────────────────────────────────────────────────────────────
BD <- list()
for (d in Sys.glob("04_Research/programs/P1_RETURN/P1S*")) {
  if (!file.exists(file.path(d, "prereg.json")) || file.exists(file.path(d, "tick_hold"))) next
  id <- basename(d); L <- file.path("stage_artifacts/programs/P1_RETURN", id, "standing_ledger.jsonl"); if (!file.exists(L)) next
  R <- rjl(L); ev <- evs(R)
  enq <- R[ev == "enqueue"]; codes <- unique(vapply(enq, function(r) as.character(r$code), ""))
  pk <- setNames(vapply(enq, function(r) as.character(r$paper$paper_key %||% r$paper$title %||% r$code), ""), vapply(enq, function(r) as.character(r$code), ""))
  vi <- which(ev == "verdict"); last <- list(); for (i in vi) last[[as.character(R[[i]]$code)]] <- R[[i]]
  q <- vapply(last, function(r) isTRUE(r$qualify), TRUE); okv <- vapply(last, function(r) identical(r$status, "evaluated"), TRUE)
  n0 <- as.integer(st0$boards[[id]]$n %||% 0L); newv <- if (FIRST) list() else R[vi[vi > n0]]
  nl <- vapply(newv, function(r) { v <- r$visible %||% list(); nm <- unname(pk[as.character(r$code)]); if (is.na(nm)) nm <- as.character(r$code)
    if (grepl("^FC_", nm)) nm <- paste0(eng_label(file.path(nm, "engine.R")), " 엔진")
    sprintf("새 판정: %s — %s(IS β-통제 t(α) %s · 상승 포착 %s)", nm, if (isTRUE(r$qualify)) "자격 통과" else if (identical(r$status, "evaluated")) "미달" else "미시험",
            f2(v$t_alpha_vis), f2(v$uc_vis)) }, "")
  BD[[id]] <- list(id = id, n = length(R), label = if (grepl("own_spec", id)) "자체 사양 엔진" else "충실구현 엔진",
                   items = length(codes), judged = length(last), pass = sum(q), fail = sum(!q & okv), untested = sum(!okv),
                   pending = length(setdiff(codes, names(last))), new = nl, n_newv = length(newv))
}

## ── 충실구현 레인 ─────────────────────────────────────────────────────────────────────
cfg <- rj("06_Registry/reinforce_auto_config.json"); lane_on <- isTRUE(cfg$replication_lane$enabled)
py <- Sys.getenv("QVEST_PY"); if (!nzchar(py) || !file.exists(py)) py <- file.path(ROOT, ".venv_qvest_ml/Scripts/python.exe"); if (!file.exists(py)) py <- "python"
so <- tryCatch(suppressWarnings(system2(py, c("-X", "utf8", "02_Infrastructure/ops/rf_replication_slots.py", "status", "--json"), stdout = TRUE, stderr = FALSE, timeout = 90)),
               error = function(e) character(0))
SL <- tryCatch(fromJSON(paste(so, collapse = "\n"), simplifyVector = FALSE), error = function(e) NULL)
live <- Filter(function(s) identical(s$claim, "live"), SL$slots %||% list())
papers <- unique(vapply(live, function(s) as.character(s$paper %||% s$target %||% s$code %||% "?"), ""))
lane_txt <- (if (is.null(SL)) "상태 판독 불가" else if (!lane_on && !length(papers)) "꺼짐"
             else if (length(papers)) sprintf("%s — 처리 중 %s", if (lane_on) "켜짐" else "꺼짐(마무리 중)", paste(papers, collapse = " · ")) else "켜짐 — 대기(처리 중 논문 없음)")
new_papers <- setdiff(papers, unlist(st0$lane$papers %||% list()))

## ── 보낼지 ────────────────────────────────────────────────────────────────────────────
n_new_steps <- sum(vapply(CH, function(x) length(x$new), 0L)); n_new_v <- sum(vapply(BD, function(x) x$n_newv, 0L))
changed <- FIRST || n_new_steps > 0L || n_new_v > 0L || length(new_papers) > 0L || !identical(isTRUE(st0$lane$on), lane_on) ||
  any(vapply(CH, function(x) !identical(as.integer(st0$chains[[x$id]]$n %||% -1L), x$n), TRUE))
if (!FORCE && hh < 8L && !changed) { cat("[진행 브리핑] 밤 · 변화 없음 — 보내지 않음\n"); quit(status = 0) }

## ── 본문 ──────────────────────────────────────────────────────────────────────────────
sec <- function(heading, x) if (length(x) >= 2L) list(heading = heading, type = "bullet", items = unname(x)) else list(heading = heading, type = "text", body = x[1])
chg <- c(if (n_new_steps) sprintf("사슬 걸음 판정 %d(채택 %d)", n_new_steps, sum(vapply(CH, function(x) sum(grepl("^걸음 [0-9]+ 채택", x$new)), 0L))),
         if (n_new_v) sprintf("상설 자격 판정 %d", n_new_v), if (length(new_papers)) sprintf("레인 새 논문 %s", paste(new_papers, collapse = " · ")))
wl <- Filter(function(x) x$wait, OPEN)
verdict <- (if (FIRST) "첫 진행 브리핑 — 지금 상태입니다(다음부터 지난 브리핑 뒤 변화를 싣는다)."
            else if (length(chg)) paste0("지난 브리핑 뒤 변화: ", paste(chg, collapse = " · "), ".")
            else if (length(wl)) sprintf("변화 없음 — %s: %s.", wl[[1]]$label, wl[[1]]$state)
            else "변화 없음 — 대기 항목 없이 다음 틱을 기다립니다.")
ex <- list()
if (length(OPEN)) ex[[length(ex) + 1L]] <- sec("P4 조립 사슬", vapply(OPEN, function(x) sprintf("%s — 걸음 %d(채택 %d · 기각 %d) · 지금: %s · 마지막: %s",
                                                                                  x$label, x$n_acc + x$n_rej, x$n_acc, x$n_rej, x$state, x$last), ""))
nw <- cap(unlist(lapply(OPEN, function(x) x$new)), 5L); if (length(nw)) ex[[length(ex) + 1L]] <- sec("새 걸음 판정(IS)", nw)
bl <- c(vapply(BD, function(x) sprintf("%s — 항목 %d · 판정 %d(통과 %d · 미달 %d · 미시험 %d) · 측정 대기 %d", x$label, x$items, x$judged, x$pass, x$fail, x$untested, x$pending), ""),
        cap(unlist(lapply(BD, function(x) x$new)), 8L))
if (length(bl)) ex[[length(ex) + 1L]] <- sec("P1 상설 자격 심사", bl)
ex[[length(ex) + 1L]] <- list(heading = "충실구현 레인", type = "text", body = sprintf("레인 %s — 끝난 논문은 P1 상설 자격(충실구현 엔진)이 입구 후보로 본다.%s", lane_txt,
                              if (length(HELD)) sprintf(" 보류 중 사슬 %d개(손 단계).", length(HELD)) else ""))
pos <- if (length(OPEN)) paste(vapply(OPEN, function(x) sprintf("%s — %s", x$label, x$state), ""), collapse = " / ") else "열린 사슬 없음"
prev <- if (length(OPEN)) paste(vapply(OPEN, function(x) x$last, ""), collapse = " / ") else "—"
nxt <- format(if (as.integer(format(now, "%M")) < 37L) now else now + 3600, "%H:37")   # 틱 = 매시 37분(Qvest_StandingBoard)
invisible(capture.output(suppressMessages(source("02_Infrastructure/programs/program_report.R"))))
prep_send(program = "진행", target = sprintf("1계층 리서치 진행 — %s 기준", format(now, "%m-%d %H:%M")),
          status = list(stage = "P4 조립 사슬 · P1 상설 자격 · 충실구현 레인 무인 운영", position = pos, previous = prev),
          verdict_line = verdict, extra = ex, next_step = sprintf("다음 틱 %s · 다음 진행 브리핑은 그 틱 직후", nxt),
          push = FALSE, dry_run = !SEND)
if (SEND) {
  st <- list(schema = "l1_progress_brief_state_v1", sent_at = format(now, "%Y-%m-%dT%H:%M:%S%z"),
             chains = lapply(CH, function(x) list(n = x$n)), boards = lapply(BD, function(x) list(n = x$n)),
             lane = list(on = lane_on, papers = as.list(papers)))
  tmp <- paste0(STP, ".tmp"); writeLines(toJSON(st, auto_unbox = TRUE, pretty = TRUE), tmp, useBytes = TRUE); file.rename(tmp, STP)
}
cat(sprintf("[진행 브리핑] %s · 사슬 %d(열림 %d) · 상설 판 %d · 레인 %s · 변화 %s\n", if (SEND) "발송" else "드라이런", length(CH), length(OPEN), length(BD),
            if (lane_on) "켜짐" else "꺼짐", if (changed) "있음" else "없음"))
