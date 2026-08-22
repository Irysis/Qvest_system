#!/usr/bin/env Rscript
# research_run_notify.R — 무인 리서치 런 **완주 알림** (도훈 지시 2026-08-22 "완주할 때마다").
#
# 왜 있나: 지금까지 텔레그램은 **실패**(scheduler_alert)에만 나갔다. 그래서 무인 레인이
#   무엇을 해냈는지는 도훈에게 도달하지 않았다 — 오늘 하루 반복 확인된 "기록은 되는데
#   읽는 쪽이 없다" 의 텔레그램 판본이다. 완주도 도달시킨다.
#
# ★규약: 텔레그램은 `tg_agent_brief()` 단일 진입점만 허용(qvest-telegram SKILL §부록 A,
#   PreToolUse 훅이 직접 호출을 차단). 여기서도 그 함수만 부른다.
# ★원칙 9(실측 시각화) 적용 경계: 이 알림은 **상태 전이·큐 갱신**이라 charts 면제 대상이다.
#   성과 수치를 실어 나르지 않고, 어디를 보면 되는지만 가리킨다. 수치를 넣으려면 차트 의무가
#   따라붙고, 그건 각 레인의 판정 보고가 할 일이지 완주 알림이 할 일이 아니다.
#
# Usage:
#   Rscript research_run_notify.R <lane> <pending> <n_done> <effect> <rc> [<extra>]
#     effect: CHANGED | SAME | (빈값)

suppressWarnings(suppressMessages({
  root <- Sys.getenv("QM_ROOT", Sys.getenv("CLAUDE_PROJECT_DIR", getwd()))
  setwd(root)
  source(file.path(root, "02_Infrastructure", "telegram", "telegram_notify.R"))
}))

args   <- commandArgs(trailingOnly = TRUE)
lane   <- if (length(args) >= 1 && nzchar(args[1])) args[1] else "all"
pending<- if (length(args) >= 2) suppressWarnings(as.integer(args[2])) else NA_integer_
ndone  <- if (length(args) >= 3) suppressWarnings(as.integer(args[3])) else NA_integer_
effect <- if (length(args) >= 4) args[4] else ""
rc     <- if (length(args) >= 5) suppressWarnings(as.integer(args[5])) else NA_integer_
extra  <- if (length(args) >= 6) args[6] else ""

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a

# ── 레인별 평문 이름 — 비전공자 가독(원칙 8-①). 코드 라벨만 쓰지 않는다.
lane_ko <- c(
  qepm_dossier    = "정식 라운드 이어붙이기",
  paper_promotion = "논문 승격(경량 → 정식)",
  method_measure  = "등재된 방법 실측",
  alpha           = "알파 가설 설계",
  optimizer       = "비중 결정 방법 검토",
  risk            = "위험모델 방법 검토",
  regime          = "국면 신호 검토",
  all             = "리서치 큐 전체"
)[[lane]] %||% lane

# ── 진척 판정: 마커(자기보고) 아니면 원장 지문. 오늘 오경보 사고의 수리 결과를 그대로 쓴다.
progressed <- (!is.na(ndone) && ndone > 0) || identical(effect, "CHANGED")
head_line <- if (isTRUE(progressed)) {
  sprintf("%s 한 건이 끝났습니다. 다음 단계로 넘어갔습니다.", lane_ko)
} else if (!is.na(rc) && rc != 0) {
  sprintf("%s 가 중간에 멈췄습니다. 큐는 그대로 보존됩니다.", lane_ko)
} else {
  sprintf("%s 를 돌렸는데 바뀐 것이 없습니다. 확인이 필요합니다.", lane_ko)
}

how <- if (!is.na(ndone) && ndone > 0) {
  "에이전트가 완료 표시를 남겼습니다"
} else if (identical(effect, "CHANGED")) {
  "완료 표시는 없었지만 원장이 바뀐 것으로 확인했습니다"
} else {
  "완료 표시도 원장 변화도 없었습니다"
}

result_ko <- if (isTRUE(progressed)) "다음 단계로 넘어갈 재료가 생겼습니다" else "이번 회차 산출이 없습니다"
mean_ko   <- if (isTRUE(progressed)) {
  "실제 자본은 움직이지 않습니다 — 자본 편입은 도훈님 수동 승인입니다"
} else {
  "실제 자본과는 무관합니다. 다음 회차에 같은 항목을 다시 시도합니다"
}

secs <- list(
  list(type = "summary", emoji = "\U0001F4CC", body = head_line),
  list(type = "bullet", emoji = "\U0001F4D6", heading = "쉬운 설명",
       items = c(
         sprintf("시도: 무인 리서치 큐에서 %s 를 한 건 처리했습니다", lane_ko),
         sprintf("확인: %s", how),
         sprintf("결과: %s", result_ko),
         sprintf("의미: %s", mean_ko))),
  list(type = "kv", emoji = "\U0001F4CA", heading = "처리 현황",
       kv = list(
         "레인"   = lane_ko,
         "대기"   = if (is.na(pending)) "미상" else sprintf("%d건", pending),
         "이번처리" = if (is.na(ndone)) "미상" else sprintf("%d건", ndone),
         "원장변화" = if (identical(effect, "CHANGED")) "있음" else if (identical(effect, "SAME")) "없음" else "미측정",
         "종료코드" = if (is.na(rc)) "미상" else as.character(rc)))
)

if (nzchar(extra)) {
  secs[[length(secs) + 1]] <- list(type = "text", emoji = "\U0001F4DD", heading = "비고",
                                   body = substr(extra, 1, 200))
}

secs[[length(secs) + 1]] <- list(
  type = "bullet", emoji = "\U000027A1", heading = "다음",
  items = c(
    "판정·수치는 원장에서 확인합니다 (method_registry · module_catalog · WT status)",
    "자본 편입(governor)은 이 경로가 건드리지 않습니다 — 수동 승인 유지"))

res <- tryCatch(
  tg_agent_brief(
    agent = "Q-Lead",
    title = sprintf("무인 리서치 완주 — %s", lane_ko),
    lock_scope = sprintf("research_run_%s_%s", lane, format(Sys.time(), "%Y%m%d_%H%M")),
    sections = secs,
    footer = sprintf("\U0001F4DA 로그: .cache/scheduler_logs/ · 큐: research-queue-pending --lane %s", lane)
  ),
  error = function(e) { cat("[notify] 발송 실패:", conditionMessage(e), "\n"); NULL })

cat(sprintf("[notify] lane=%s pending=%s done=%s effect=%s rc=%s ok=%s\n",
            lane, pending, ndone, effect, rc,
            if (is.list(res)) isTRUE(res$ok) else FALSE))
