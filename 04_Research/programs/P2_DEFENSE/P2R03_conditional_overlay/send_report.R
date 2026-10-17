## P2R03 결과 보고 1통(요약 + 차트 3장) + 다음 리서치 브리핑 1통 — 수치 = evaluation_visible.json(평가 계약) 그대로 · 건식 기본(P2R03_SEND=1 이면 실발송)
##   읽기 · 다음 단계 문장은 환경변수로 받는다(P2R03_READ_1..4 · P2R03_NEXT · P2R03_NEXT_ITEMS(‖ 구분) · P2R03_P2_LINE) — 판정을 본 뒤 Q 가 쓰고 수치는 표에서만.
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; Sys.setenv(QM_ROOT = ROOT)
if (!identical(Sys.getenv("P2R03_SEND"), "1")) Sys.setenv(QVEST_TG_DRY_RUN = "1")
suppressPackageStartupMessages({ library(jsonlite); library(data.table) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
RD  <- file.path(ROOT, "04_Research/programs/P2_DEFENSE/P2R03_conditional_overlay")
SA  <- file.path(ROOT, "stage_artifacts/programs/P2_DEFENSE/P2R03_conditional_overlay")
VIS <- file.path(SA, "visual")
P2  <- Sys.getenv("P2R03_P2_LINE", "철학: (P2 대기 — 건식 자리 표시) · 실패 형태 미정")
invisible(capture.output(suppressMessages({
  source(file.path(ROOT, "02_Infrastructure/telegram/telegram_notify.R"))
  source(file.path(ROOT, "02_Infrastructure/programs/program_report.R"))
})))
ev <- fromJSON(file.path(RD, "results/evaluation_visible.json"), simplifyVector = FALSE)
C <- fread(file.path(VIS, "p2r03_cells.csv"))
pj <- function(x) { x <- unlist(x); if (length(x)) paste(x, collapse = " · ") else "없음" }
## 항목 = 한 줄 80자 안팎(메시지 4096바이트 상한 — 넘으면 서식기가 글머리 항목을 비운다 · 10-18 건식 실측) · 전체 표는 ROUND_REPORT.md
fr <- function(s, n) ifelse(is.finite(s) & is.finite(n) & n > 0, sprintf("%d/%d", as.integer(round(s * n)), as.integer(n)), "NA")
row <- function(D, i) with(D[i], sprintf("%s %s %s — %s · β 짝 깊은 위기 %s · 빠른 급락 %s · α %s%%",
  sub(" ·.*$", "", engine), dev, sub("^D[0-9] ", "", as.character(device)), verdict, fr(beta_deep, n_beta_deep), fr(fast, n_fast),
  ifelse(is.finite(da), sprintf("%+.1f", 100 * da), "NA")))
SHOW <- strsplit(Sys.getenv("P2R03_SHOW_DEVS", "D5,D7"), ",", fixed = TRUE)[[1]]
ord <- C[dev %in% SHOW][order(dev, engine)]
top <- seq_len(nrow(ord))
charts <- c("누적 수익 — 장치 7종 vs RX0 vs KOSPI200" = file.path(VIS, "p2r03_cum_pnl.png"),
            "위기 방어 과반 비율(위기 개선 · β 짝 깊은 위기 · 빠른 급락)" = file.path(VIS, "p2r03_crisis_defense.png"),
            "증분 β 통제 알파(변형 − RX0)" = file.path(VIS, "p2r03_incremental_alpha.png"))
reads <- Filter(nzchar, vapply(1:4, function(i) Sys.getenv(sprintf("P2R03_READ_%d", i)), ""))
extra <- list(
  list(type = "bullet", heading = sprintf("판정 %s — 두 엔진 통과 %s · 한 엔진 %s · lag-1 보류 %s · 선택 %s",
                                          ev$verdict_label %||% ev$verdict, pj(ev$pass_both), pj(ev$pass_one), pj(ev$held_lag1_slow),
                                          if (length(ev$selected)) ev$selected[[1]]$device %||% "있음" else "없음"),
       items = c(vapply(top, function(i) row(ord, i), ""), Filter(nzchar, Sys.getenv("P2R03_REST_LINE")))),
  if (length(reads) >= 2L) list(type = "bullet", heading = "읽기", items = reads) else if (length(reads) == 1L) list(type = "text", heading = "읽기", body = reads),
  .prep_line("철학", P2, "🧭", "방어 엔진", "P2R03"))
extra <- Filter(Negate(is.null), extra)
r1 <- prep_send(program = "방어 엔진", target = "P2R03 · 조건부 시변 노출 층 7종 × DNN 2엔진",
                status = list(stage = "라운드 종료", position = "판정 · 보고", previous = "P3R03 구성 5종 = 노출(β) 방어 · 빠른 급락 0/20"),
                verdict_line = Sys.getenv("P2R03_VERDICT_LINE", sprintf("%s(판정 %s/%s)", ev$verdict_label %||% ev$verdict, ev$n_judged %||% "?", ev$n_total %||% "?")),
                artifact = SA, charts = charts, extra = extra,
                next_step = Sys.getenv("P2R03_NEXT", "(다음 단계 — 판정 뒤 작성)"), push = identical(Sys.getenv("P2R03_PUSH"), "1"), root = ROOT)
cat(substr(r1$msg %||% "", 1, 3500), "\n====\n")
nx <- strsplit(Sys.getenv("P2R03_NEXT_ITEMS", ""), "‖", fixed = TRUE)[[1]]; nx <- nx[nzchar(nx)]
if (length(nx) >= 2L) {
  r2 <- tg_agent_brief(agent = "AlphaSearch", title = "[1계층] 다음 리서치 브리핑 — P2R03 뒤",
    sections = list(list(type = "summary", emoji = "📌", body = Sys.getenv("P2R03_BRIEF_HEAD", Sys.getenv("P2R03_NEXT", "다음 라운드"))),
                    list(type = "bullet", heading = "탐침 · 결정", items = nx)),
    relaxed = TRUE, force = TRUE, decode_jargon = FALSE, glossary = FALSE, mute = TRUE,
    dry_run = identical(Sys.getenv("QVEST_TG_DRY_RUN"), "1"))
  cat(substr(r2$msg %||% "", 1, 1500), "\n")
}
