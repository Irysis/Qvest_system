## P3R03 결과 보고 1통(요약 + 차트 3장) + 다음 리서치 브리핑 1통 — 수치 = evaluation.json(평가 계약) 그대로 · 건식 기본(P3R03_SEND=1 이면 실발송)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; Sys.setenv(QM_ROOT = ROOT)
if (!identical(Sys.getenv("P3R03_SEND"), "1")) Sys.setenv(QVEST_TG_DRY_RUN = "1")
suppressPackageStartupMessages({ library(jsonlite); library(data.table) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
RD  <- file.path(ROOT, "04_Research/programs/P3_CONSTRUCTION/P3R03_advanced_construction")
VIS <- file.path(ROOT, "stage_artifacts/programs/P3_CONSTRUCTION/P3R03_advanced_construction/visual")
P2  <- Sys.getenv("P3R03_P2_LINE", "철학: (P2 대기 — 건식 자리 표시) · 실패 형태 미정")
invisible(capture.output(suppressMessages({
  source(file.path(ROOT, "02_Infrastructure/telegram/telegram_notify.R"))
  source(file.path(ROOT, "02_Infrastructure/programs/program_report.R"))
})))
C <- fread(file.path(VIS, "p3r03_cells.csv"))
lab <- c(pass = "통과", mild_only = "완만한 위기만", not_decisive = "결정적 미달")
row <- function(e, m) { z <- C[engine == e & method == m]; sprintf("%s %s — %s · 위기 포착 %.2f/%.2f · 증분 α %+.2f%% · 집중 %s",
  sub(" ·.*$", "", e), m, lab[[z$verdict]], z$cap_v, z$cap_r, 100 * z$da, if (z$conc == "clear") "정상" else "위반") }
E3 <- "E3 · B6_36(DNN 계보)"; E2 <- "E2 · DNN 원형"
charts <- c("누적 수익 — 구성 5종 vs RX0 vs KOSPI200" = file.path(VIS, "p3r03_cum_pnl.png"),
            "위기 하락 포착 중앙값(변형 vs RX0)" = file.path(VIS, "p3r03_crisis_capture.png"),
            "증분 β 통제 알파(변형 − RX0)" = file.path(VIS, "p3r03_incremental_alpha.png"))
extra <- list(
  list(type = "bullet", heading = "E3(B6_36) 통과 3 · E2(DNN 원형) 통과 0 — 보는 창", items = c(
    row(E3, "HRP"), row(E3, "NCO"), row(E3, "Michaud 재표집"), row(E2, "HRP"))),
  list(type = "bullet", heading = "읽기", items = c(
    "위기 하락 포착은 10칸 전부 줄고 증분 β 통제 α 는 전부 양(+) — 알파 손실 없음",
    "그러나 β 짝 대조(RX0 를 같은 β 로 낮추고 나머지 현금)를 10칸 모두 못 넘었다 — E3 통과 3칸은 '노출(β) 방어 · 느린 약세 · 경로 방어'",
    "빠른 깊은 급락(2008-05 · 2020-01)은 10칸 모두 같은 β 현금 사본보다 나빴다(0/20) — 구성 레버가 포화(추정기를 바꿔도 같은 종목에서 잃음)",
    "집중 위반(깊은 위기 한 종목 −10% 초과 = 후보 제외): NCO · Michaud · CVaR")),
  .prep_line("철학", P2, "🧭", "구성", "P3R03"))
r1 <- prep_send(program = "구성", target = "P3R03 · 고도화 구성 5종 × DNN 2엔진",
                status = list(stage = "라운드 종료", position = "판정 · 보고", previous = "P3R02 정제 공분산 최소분산 = 반증(중앙값만 개선)"),
                verdict_line = "partial(판정 10/10) — 두 엔진 공통 통과 0 · 선정 후보 없음 · E3 에서 HRP · NCO · Michaud 통과",
                artifact = file.path(ROOT, "stage_artifacts/programs/P3_CONSTRUCTION/P3R03_advanced_construction"), charts = charts, extra = extra,
                next_step = "구성 라운드는 멈춘다 — HRP(E3)를 구성 기저로 두고 방어 엔진(P2)의 시변 · 비대칭 노출 층 라운드를 새 세션에서 설계",
                push = FALSE, root = ROOT)
cat(substr(r1$msg %||% "", 1, 3500), "\n====\n")
r2 <- tg_agent_brief(agent = "AlphaSearch", title = "[1계층] 다음 리서치 브리핑 — P3R03 뒤",
  sections = list(
    list(type = "summary", emoji = "📌", body = "다음: HRP(E3) 기저 위 방어 엔진 시변 · 비대칭 노출 층 라운드 설계 — 새 세션에서"),
    list(type = "bullet", heading = "탐침 · 결정", items = c(
      "구성 라운드 중단 — 빠른 급락에서 구성 레버 포화(β 짝 0/20 · 획일화 · 크기 원천은 엔진)",
      "새 라운드 판정에 β 짝 사본 대비 깊은 위기 과반 · 하락장 β < 상승장 β 를 판정으로 넣는다",
      "1801.01777 단일 차이 A/B(부호 층만 · 학습 표본만) — 수익 엔진 재료(보는 창 근거만)",
      "도훈 결정 대기: MSM as-of 전환 D1~D4 · 헌장 빈칸 3건(급락 속도 · 강세 참여 단위 · β 방어 범위)"))),
  relaxed = TRUE, force = TRUE, decode_jargon = FALSE, glossary = FALSE, mute = TRUE,
  dry_run = identical(Sys.getenv("QVEST_TG_DRY_RUN"), "1"))
cat(substr(r2$msg %||% "", 1, 1500), "\n")
