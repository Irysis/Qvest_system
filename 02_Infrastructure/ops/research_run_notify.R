#!/usr/bin/env Rscript
# research_run_notify.R — 무인 리서치 런 알림 (도훈 지시 2026-08-22, **v2 재작성**).
#
# ── v1 이 틀린 점 (도훈 지적 2026-08-22 밤):
#   "리서치에서 얻을 수 있는 인사이트는 없고, 그저 완료했다는 얘기만 장황하게 온다."
#   v1 은 런 **상태**만 날랐다 — "한 건이 끝났습니다 / 다음 단계로 넘어갔습니다 /
#   대기 71건 / 종료코드 0". 완주 사실은 그 자체로 정보가 아니다.
#   ⇒ v2 는 **그 런이 알아낸 것**을 나른다. 완주 여부는 꼬리 한 줄로 접는다.
#
# ── 무엇을 나르는가 (재료는 이미 산출물에 있었다):
#   ① L-code `lesson_text`          — 배운 것 (지식 적립 정본)
#   ② L-code `mechanism_hypothesis` — 왜 그런가
#   ③ L-code `falsification_attempts` — 어떻게 반증했나
#   ④ judge `verdict` + `hard_gate_summary` + `beta_controlled_alpha` — 판정과 근거
#   ⑤ 실패 게이트의 `note`          — 무엇에서 막혔나
#   ★재료가 **없으면 없다고 말한다** — 산출 없는 런을 성과처럼 포장하지 않는다.
#
# ★규약: 텔레그램은 `tg_agent_brief()` 단일 진입점(qvest-telegram SKILL §부록 A).
# ★범위: 인사이트는 **런 시작 이후 생성분만** 본다(since 인자). 창을 안 자르면
#   남의 세션 산출을 이 런의 성과로 읽는다 — 오늘 하루 6번 겪은 그 실수.
#
# Usage:
#   Rscript research_run_notify.R <lane> <pending> <n_done> <effect> <rc> [<extra>] [<since_epoch>]

suppressWarnings(suppressMessages({
  root <- Sys.getenv("QM_ROOT", Sys.getenv("CLAUDE_PROJECT_DIR", getwd()))
  setwd(root)
  source(file.path(root, "02_Infrastructure", "telegram", "telegram_notify.R"))
  library(jsonlite)
}))

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || identical(a, "")) b else a

args   <- commandArgs(trailingOnly = TRUE)
lane   <- if (length(args) >= 1 && nzchar(args[1])) args[1] else "all"
pending<- if (length(args) >= 2) suppressWarnings(as.integer(args[2])) else NA_integer_
ndone  <- if (length(args) >= 3) suppressWarnings(as.integer(args[3])) else NA_integer_
effect <- if (length(args) >= 4) args[4] else ""
rc     <- if (length(args) >= 5) suppressWarnings(as.integer(args[5])) else NA_integer_
extra  <- if (length(args) >= 6) args[6] else ""
since  <- if (length(args) >= 7) suppressWarnings(as.numeric(args[7])) else NA_real_
# since 미지정 시 보수적으로 4시간 창 — 넓히면 남의 산출을 내 것으로 읽는다.
if (!is.finite(since)) since <- as.numeric(Sys.time()) - 4 * 3600

.lane_map <- c(
  qepm_dossier = "정식 라운드", paper_promotion = "논문 승격",
  method_measure = "방법 실측",  alpha = "알파 가설",
  optimizer = "비중 방법",       risk = "위험모델",
  regime = "국면 신호",          all = "리서치 큐")
lane_ko <- if (lane %in% names(.lane_map)) .lane_map[[lane]] else lane

# ── 산출물에서 **알아낸 것**을 뽑는다 ---------------------------------------
py <- Sys.getenv("QVEST_PY", "")
if (!nzchar(py) || !file.exists(py)) py <- file.path(root, ".venv_qvest_ml", "Scripts", "python.exe")
if (!file.exists(py)) py <- "python"
ins <- tryCatch({
  out <- suppressWarnings(system2(py,
    c(file.path(root, "02_Infrastructure", "ops", "research_insight_extract.py"),
      root, format(since, scientific = FALSE)), stdout = TRUE, stderr = FALSE))
  if (length(out)) fromJSON(paste(out, collapse = ""), simplifyVector = FALSE) else NULL
}, error = function(e) NULL)

lcodes   <- if (!is.null(ins)) ins$lcodes   else list()
verdicts <- if (!is.null(ins)) ins$verdicts else list()
progressed  <- (!is.na(ndone) && ndone > 0) || identical(effect, "CHANGED")
stopped     <- !is.na(rc) && rc != 0
has_insight <- length(lcodes) > 0 || length(verdicts) > 0

# ── 헤더: 있으면 **발견**을 앞세운다. 완주 사실은 헤더가 아니다 -------------
# ★summary 는 [20,100]자 계약(tg_format_summary). 헤드라인은 **한 줄 결론**만 담고
#   전문은 아래 '배운 것' 본문이 나른다 — 잘라서 버리는 게 아니라 위치를 나눈다.
.clip <- function(x, lo = 20L, hi = 96L) {
  t <- gsub("\s+", " ", trimws(as.character(x %||% "")))
  if (nchar(t) > hi) t <- paste0(substr(t, 1, hi - 1), "…")
  if (nchar(t) < lo) t <- paste0(t, strrep(" ", lo - nchar(t)))
  t
}
head_line <- if (length(lcodes) > 0) {
  .clip(sprintf("[%s] %s", lcodes[[1]]$family %||% "?", lcodes[[1]]$lesson %||% lane_ko))
} else if (length(verdicts) > 0) {
  v <- verdicts[[1]]
  .clip(sprintf("%s %s — %s", v$wt, v$verdict %||% "", v$fail_note %||% ""))
} else if (stopped) {
  .clip(sprintf("%s 가 중간에 멈췄습니다%s", lane_ko,
          if (progressed) " (그때까지 산출은 남음)" else " (남은 산출 없음)"))
} else {
  .clip(sprintf("%s 를 돌렸으나 적립된 지식이 없습니다", lane_ko))
}

secs <- list(list(type = "summary", emoji = "\U0001F52C", body = head_line))

# ── ① 판정 --------------------------------------------------------------
for (v in verdicts[seq_len(min(2L, length(verdicts)))]) {
  kv <- list("대상" = v$wt %||% "?",
             "판정" = paste0(v$verdict %||% "?",
                             if (nzchar(v$grade %||% "")) sprintf(" · grade %s", substr(v$grade, 1, 30)) else ""))
  if (!is.null(v$port_t))
    kv[["HARD 3종"]] <- sprintf("PORT_t %s · oos %s · calmar %s", v$port_t, v$oos, v$calmar)
  if (!is.null(v$t_alpha))
    kv[["β-통제 α"]] <- sprintf("t(α) %.3f · β %.3f · α %.2f%%/yr",
                                as.numeric(v$t_alpha), as.numeric(v$beta),
                                100 * as.numeric(v$alpha_ann %||% 0))
  secs[[length(secs) + 1]] <- list(type = "kv", emoji = "\U00002696", heading = "판정", kv = kv)
  if (nzchar(v$fail_note %||% ""))
    secs[[length(secs) + 1]] <- list(type = "text", emoji = "\U0001F6D1",
                                     heading = "막힌 지점", body = substr(v$fail_note, 1, 320))
}

# ── ② 배운 것 (이 알림의 본체) --------------------------------------------
for (x in lcodes[seq_len(min(2L, length(lcodes)))]) {
  secs[[length(secs) + 1]] <- list(type = "text", emoji = "\U0001F4A1",
    heading = sprintf("배운 것 — %s [%s · grade %s]",
                      x$id %||% "?", x$family %||% "?", x$grade %||% "?"),
    body = x$lesson %||% "(lesson_text 없음)")
  if (nzchar(x$mechanism %||% ""))
    secs[[length(secs) + 1]] <- list(type = "text", emoji = "\U0001F9E9",
                                     heading = "기전", body = x$mechanism)
  if (nzchar(x$falsify %||% ""))
    secs[[length(secs) + 1]] <- list(type = "text", emoji = "\U0001F50E",
                                     heading = "반증 시도", body = x$falsify)
}
if (length(lcodes) > 2)
  secs[[length(secs) + 1]] <- list(type = "text", emoji = "\U00002795", heading = "그 외",
    body = sprintf("L-code %d건 추가 적립 — hypothesis_index 조회", length(lcodes) - 2))

# ── ③ 산출이 없으면 그렇다고 말한다 ----------------------------------------
if (!has_insight) {
  why <- if (stopped) "런이 중단돼 적립 단계에 도달하지 못했습니다"
         else if (progressed) "원장은 바뀌었으나 L-code·판정 산출은 없습니다(중간 단계 전이일 수 있습니다)"
         else "이번 회차 산출이 없습니다"
  secs[[length(secs) + 1]] <- list(type = "bullet", emoji = "\U000026A0", heading = "적립 없음",
    items = c(why, "이 알림은 '완주' 가 아니라 '무엇을 알아냈나' 를 나릅니다 — 없으면 없다고 적습니다"))
}

if (nzchar(extra))
  secs[[length(secs) + 1]] <- list(type = "text", emoji = "\U0001F4DD",
                                   heading = "비고", body = substr(extra, 1, 260))

# ── 꼬리: 런 상태 (v1 은 이게 본문이었다) -----------------------------------
secs[[length(secs) + 1]] <- list(type = "kv", emoji = "\U0001F4CB", heading = "런 상태",
  kv = list("레인" = lane_ko,
            "대기" = if (is.na(pending)) "미상" else sprintf("%d건", pending),
            "적립" = sprintf("L-code %d · 판정 %d", length(lcodes), length(verdicts)),
            "종료" = if (is.na(rc)) "미상" else if (rc == 0) "정상" else sprintf("rc=%d", rc)))

res <- tryCatch(
  tg_agent_brief(
    agent = "Q-Lead",
    title = if (has_insight) sprintf("리서치 적립 — %s", lane_ko)
            else sprintf("무인 런 — %s (적립 없음)", lane_ko),
    dry_run = identical(Sys.getenv("QVEST_RUN_NOTIFY_DRYRUN"), "1"),
    lock_scope = sprintf("research_run_%s_%s", lane, format(Sys.time(), "%Y%m%d_%H%M")),
    sections = secs,
    footer = "\U0001F4DA 전문: hypothesis_index · judge_package.json · stage_artifacts/l_code/"
  ),
  error = function(e) { cat("[notify] 발송 실패:", conditionMessage(e), "\n"); NULL })

cat(sprintf("[notify] lane=%s pending=%s done=%s effect=%s rc=%s lcode=%d verdict=%d ok=%s\n",
            lane, pending, ndone, effect, rc, length(lcodes), length(verdicts),
            if (is.list(res)) isTRUE(res$ok) else FALSE))
