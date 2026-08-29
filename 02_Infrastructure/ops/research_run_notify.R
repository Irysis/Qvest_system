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
  # 루트 해석: QVEST_NOTIFY_ROOT 를 **먼저** 본다.
  #   ~/.Renviron 이 QM_ROOT 를 pin 해 셸 export 를 R 시작 시점에 덮으므로
  #   env 루트로는 격리가 원리적으로 불가능하다(2026-08-16 카드 · 오늘 재확인).
  #   전용 변수는 Renviron 에 없으므로 통과한다 — 검사가 쓰는 유일한 이음매.
  root <- Sys.getenv("QVEST_NOTIFY_ROOT", "")
  if (!nzchar(root)) root <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", getwd()))  # 금칙 ④: CPD-first
  # ★코드 루트 ≠ 데이터 루트 (2026-08-29 재확인 — root 는 픽스처일 수 있다):
  #   telegram_notify(코드)는 정본 저장소에서 source 한다. root 에서 찾으면 픽스처 검사가
  #   "cannot open the connection" 으로 죽는다(당일 실측 — run_completion_notify 9축).
  setwd(Sys.getenv("QM_ROOT", getwd()))
  source(file.path(Sys.getenv("QM_ROOT", getwd()), "02_Infrastructure", "telegram", "telegram_notify.R"))
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

# ★레인명은 QEPM 파이프라인의 정식 단계·모드 명칭을 쓴다.
#   구어체 축약("이어붙이기" 등) 금지 — 정확도만 낮추고 가독은 안 오른다(도훈 지시 2026-08-22).
#   비전공자 가독은 본문 용어를 풀어 쓰는 게 아니라 **자동 용어 풀이 footer**가 담당한다(SKILL v7 §5.5).
.lane_map <- c(
  qepm_dossier = "QEPM dossier 승계", paper_promotion = "논문 승격",
  method_measure = "방법론 실측",    alpha = "알파 리서치",
  optimizer = "옵티마이저 리서치",   risk = "리스크 리서치",
  regime = "국면 신호 리서치",       all = "리서치 큐")
lane_ko <- if (lane %in% names(.lane_map)) .lane_map[[lane]] else lane

# ── 산출물에서 **알아낸 것**을 뽑는다 ---------------------------------------
# ★코드는 정본 저장소에서, **데이터는 root 에서** 읽는다 — 둘을 섞으면
#   픽스처 검사가 스크립트를 못 찾아 조용히 0건이 된다.
code_root <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", getwd()))  # 금칙 ④: CPD-first
py <- Sys.getenv("QVEST_PY", "")
if (!nzchar(py) || !file.exists(py)) py <- file.path(code_root, ".venv_qvest_ml", "Scripts", "python.exe")
if (!file.exists(py)) py <- "python"
ins <- tryCatch({
  out <- suppressWarnings(system2(py,
    c(file.path(code_root, "02_Infrastructure", "ops", "research_insight_extract.py"),
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
  t <- gsub("[[:space:]]+", " ", trimws(as.character(x %||% "")))
  if (nchar(t) > hi) t <- paste0(substr(t, 1, hi - 1), "…")
  if (nchar(t) < lo) t <- paste0(t, strrep(" ", lo - nchar(t)))
  t
}
# ★긴 서술은 **문장 단위로 쪼개 bullet** 으로 보낸다 — text 섹션은 220자,
#   bullet 항목은 80자 계약이다(tg_agent_brief). 자르는 게 아니라 나눈다.
.to_bullets <- function(x, per = 74L, maxn = 6L) {
  t <- gsub("[[:space:]]+", " ", trimws(as.character(x %||% "")))
  if (!nzchar(t)) return(character(0))
  parts <- unlist(strsplit(t, "(?<=[.!?])[[:space:]]+", perl = TRUE))
  out <- character(0)
  for (q in parts) {
    while (nchar(q) > per) { out <- c(out, substr(q, 1, per)); q <- substr(q, per + 1, nchar(q)) }
    if (nzchar(trimws(q))) out <- c(out, trimws(q))
  }
  if (length(out) > maxn) out <- c(out[seq_len(maxn - 1L)],
        sprintf("(이하 %d줄 생략 — 전문은 stage_artifacts/l_code/)", length(out) - maxn + 1L))
  out
}

# ★섹션 타입은 항목 수가 정한다 — bullet 은 **2개 이상** 요구, 1개면 text 여야 한다
#   (tg_agent_brief 계약). 짧은 서술이 1문장으로 나오는 경우가 실제로 있다.
.sec <- function(emoji, heading, items) {
  items <- items[nzchar(items)]
  if (length(items) == 0L) return(NULL)
  if (length(items) == 1L)
    return(list(type = "text", emoji = emoji, heading = heading,
                body = substr(items[1], 1, 210)))
  list(type = "bullet", emoji = emoji, heading = heading, items = items)
}
.add <- function(lst, x) if (is.null(x)) lst else c(lst, list(x))

head_line <- if (length(lcodes) > 0) {
  .clip(sprintf("[%s] %s", lcodes[[1]]$family %||% "?", lcodes[[1]]$lesson %||% lane_ko))
} else if (length(verdicts) > 0) {
  v <- verdicts[[1]]
  .clip(sprintf("%s %s — %s", v$wt, v$verdict %||% "", v$fail_note %||% ""))
} else if (stopped) {
  .clip(sprintf("%s 중단 — %s", lane_ko,
          if (progressed) "중단 시점까지의 산출은 보존됨" else "산출 없음"))
} else {
  .clip(sprintf("%s 실행 — 적립된 지식 없음", lane_ko))
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
    secs <- .add(secs, .sec("🛑", "막힌 지점", .to_bullets(v$fail_note, maxn = 4L)))
}

# ── ② 배운 것 (이 알림의 본체) --------------------------------------------
for (x in lcodes[seq_len(min(2L, length(lcodes)))]) {
  secs <- .add(secs, .sec("💡",
    sprintf("배운 것 — %s [%s · grade %s]", x$id %||% "?", x$family %||% "?", x$grade %||% "?"),
    .to_bullets(x$lesson %||% "(lesson_text 미기입)")))
  secs <- .add(secs, .sec("🧩", "기전", .to_bullets(x$mechanism, maxn = 4L)))
  secs <- .add(secs, .sec("🔎", "반증 시도", .to_bullets(x$falsify, maxn = 3L)))
}
if (length(lcodes) > 2)
  secs[[length(secs) + 1]] <- list(type = "text", emoji = "\U00002795", heading = "그 외",
    body = sprintf("L-code %d건 추가 적립 — hypothesis_index 조회", length(lcodes) - 2))

# ── ③ 산출이 없으면 그렇다고 말한다 ----------------------------------------
if (!has_insight) {
  why <- if (stopped) "런 중단으로 지식 적립 단계에 미도달"
         else if (progressed) "원장 변화는 있으나 L-code·판정 산출 없음 — 중간 단계 전이로 추정"
         else "이번 회차 산출 없음"
  secs[[length(secs) + 1]] <- list(type = "bullet", emoji = "\U000026A0", heading = "적립 없음",
    items = c(why, "본 알림의 대상은 완주 사실이 아니라 적립된 지식 — 부재 시 부재로 보고"))
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
    # relaxed: L-code 원문에는 전문 용어·식별자가 그대로 들어 있다(MDE·ratio·WT-…).
    #   그것을 지우면 인사이트가 사라진다 — 페이퍼 브리핑 선례와 같은 성격이라 가드를 면제하고,
    #   대신 decode_jargon 을 켜 **자동 용어 풀이**로 비전공자 가독을 지킨다(SKILL v7 §5.5).
    relaxed = TRUE, decode_jargon = TRUE, decode_mode = "inline_first",
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
