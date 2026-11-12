# P1R03 이정표 1통(prep_send · 1계층 표제 · 푸시) — 새벽 측정 셸(p1r03_dawn_measure.sh)이 부른다.
#   인자: <단계 키 measured | stale | view_changed | failed> <본문 줄>...
#   measured 면 판정 단일 출처(results/verdict.json)의 기계 요약(summary)을 함께 싣는다 — 판정 해석 · 판단 T2 · 철학 P2 · 정식 보고는 세션(격리 점검 v1 R-4).
args <- commandArgs(trailingOnly = TRUE)
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
suppressMessages(source("04_Research/programs/_lib/round_core/v3/load.R"))
invisible(capture.output(suppressMessages(source("02_Infrastructure/programs/program_report.R"))))
`%||%` <- function(a, b) if (is.null(a) || !length(a)) b else a
key <- args[1] %||% "?"; body <- as.list(args[-1])
RD <- "04_Research/programs/P1_RETURN/P1R03_factor_family_composites"
stage <- switch(key, measured = "측정 · 평가 끝", stale = "자료 낡음 — 측정 대기", view_changed = "측정 중 결합용 뷰 바뀜 — 재측정 필요",
                failed = "측정 실패", key)
nxt <- switch(key,
  measured = "세션: 판정 해석 → 판단 Superfan T2 · 철학 P2 → 정식 보고(철학 줄 포함) → 닫기",
  stale = "07:10 아침 체인 자가 복구(ensure_data_current) → P1R03 다음 시작 창 18:00 · 세션이 열리면 표적 복구",
  view_changed = "세션: 뷰 갱신 원인 확인 → 15칸 재측정", failed = "세션: 측정 로그 확인", "세션 확인")
vl <- NULL
if (identical(key, "measured")) {
  vf <- file.path(RD, "results", "verdict.json")
  if (file.exists(vf)) { V <- tryCatch(rc_json_read(vf), error = function(e) NULL)
    s <- V$summary; if (is.character(s) && length(s)) vl <- paste0("기계 판정(해석 전): ", paste(s, collapse = " · "))
  } else body <- c(body, list("판정 파일 없음 — 평가 연쇄 확인 필요"))
}
r <- prep_send(program = "수익 엔진", target = sprintf("P1R03 팩터 가족 합성 15칸 — %s", stage),
               status = list(stage = stage, position = "P1R03 · 자체 사양 엔진 15(가족 14 + 토탈 1) · 코어 v3", previous = "11-12 밤 등록 · 새벽 측정 셸"),
               verdict_line = vl, next_step = nxt,
               extra = list(list(heading = "지금 상태", type = "bullet",
                                 items = if (length(body) >= 2L) body else c(body, list("상태 = .cache/scheduler_logs/p1r03_dawn_measure_state.txt")))),
               artifact = file.path(RD, "DESIGN.md"), push = TRUE, root = ROOT)
cat(sprintf("[p1r03_milestone] %s ok=%s\n", key, isTRUE((r %||% list())$ok) || identical(Sys.getenv("QVEST_TG_DRY_RUN"), "1")))
