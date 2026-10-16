## P1R02 결과 보고 1통 + 다음 리서치 브리핑 1통(발송 규칙 qvest-telegram §0 · 라운드 결과 = 요약 + 차트 · 결과 뒤 다음 브리핑)
##   수치 = evaluation.json · report_extras.json(계약 산출) 그대로 · 건식 기본(QVEST_TG_DRY_RUN=1) — 실발송은 P1R02_SEND=1
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; Sys.setenv(QM_ROOT = ROOT)
if (!identical(Sys.getenv("P1R02_SEND"), "1")) Sys.setenv(QVEST_TG_DRY_RUN = "1")
suppressPackageStartupMessages({ library(jsonlite); library(data.table) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
RD <- file.path(ROOT, "04_Research/programs/P1_RETURN/P1R02_1801_long_leg")
ev <- fromJSON(file.path(RD, "results/evaluation.json"), simplifyVector = FALSE)
ex <- fromJSON(file.path(RD, "results/report_extras.json"), simplifyVector = FALSE)$visible
P2 <- Sys.getenv("P1R02_P2_LINE", "철학: (P2 대기)")
invisible(capture.output(suppressMessages({
  source(file.path(ROOT, "02_Infrastructure/telegram/telegram_notify.R"))
  source(file.path(ROOT, "02_Infrastructure/programs/program_report.R"))
  source(file.path(ROOT, "02_Infrastructure/contracts/behavior_card.R"))
})))
pct <- function(x, d = 2) sprintf("%+.*f%%", d, 100 * as.numeric(x))
num <- function(x, d = 2) sprintf("%.*f", d, as.numeric(x))
V <- ev$visible; L_DIR <- ev$long_dir
## 카드 = report_extras.R 가 mc_write 로 남긴 MC8 붙은 카드(위기 방어 귀속 줄이 대조를 읽는다) · 없으면 산출물에서 다시 만든다
card <- tryCatch(fromJSON(file.path(L_DIR, "behavior_card.json"), simplifyVector = TRUE), error = function(e) NULL) %||%
  tryCatch(bc_card_from_artifacts(L_DIR), error = function(e) NULL)
charts <- c("롱 레그 누적 수익 vs KOSPI200" = file.path(L_DIR, "equity_curve.png"))
charts <- charts[file.exists(charts)]
extra <- list(
  list(type = "kv", emoji = "📏", heading = "판정 수치(보는 창 2001-02~2022-12 · 사전등록 규칙)", kv = list(
    "롱 레그 β 통제 α" = sprintf("%s/년 · t %s · β %s", pct(V$M1_long$alpha_ann), num(V$M1_long$t), num(V$M1_long$beta)),
    "롱숏(재검증) β 통제 α" = sprintf("%s/년 · t %s", pct(V$M2_long_short$alpha_ann), num(V$M2_long_short$t)),
    "롱 레그 몫" = sprintf("%s · %s", num(V$M3_long_share), V$band))),
  list(type = "bullet", heading = "보고 전용(등록 뒤 추가 · 판정 불변)", items = c(
    sprintf("크기 짝 무작위 바구니 α %s(t %s) · 크기 뺀 선택 알파 %s/년(t %s)", pct(ex$size_matched$alpha_ann), num(ex$size_matched$t),
            pct(ex$selection_long_minus_size$alpha_ann), num(ex$selection_long_minus_size$t)),
    sprintf("크기 짝 플라시보 %d경로 중 롱 레그 t 이상 비율 %s — 무비용 크기 짝 무작위 바구니보다 낮다(비용 1.24%%/년보다 선택 손실이 크다)", as.integer(ex$placebo$n), num(ex$placebo$share_ge_long_t, 2)),
    "노출 분해: 크기(동일가중) +4.79%/년 · 선택 −7.02%/년 · 비용 −1.24%/년 — 소형주 프리미엄을 DNN 선택이 더 깎았다",
    "행동 카드(보는 창): 위기 방어 약함 · 하락 포착 중앙 1.13 · 하락장 β 1.28 > 상승장 β 0.91(역방향) — 위 핵심 수치는 전기간")),
  list(type = "text", emoji = "🔍", heading = "핵심 발견 — 첫 A 가 재구현에서 사라졌다",
       body = paste("1차 구현은 권위 A 였는데, 논문 그대로(팩터마다 고정 방향) 재구현하자 롱숏이 F(보는 창 α t 1.14)가 됐다.",
                    "두 판 사이 차이는 둘(동적 부호 층 · 학습 표본 추출)이라 A 의 원천은 아직 분리되지 않았다 — 단일 차이 A/B 로 가른다.",
                    "확실한 것: 논문 그대로의 DNN 은 이 측정 축에서 F · 충실도 감사가 논문 성과로 잘못 적을 뻔한 A 를 막았다.")),
  .prep_line("철학", P2, "🧭", "수익 엔진", "P1R02"))   # 길이에 맞는 섹션(요약 1줄 · 길면 문단)
r1 <- prep_send(program = "수익 엔진", target = "P1R02 · 1801.01777 롱 레그만",
                status = list(stage = "라운드 종료", position = "판정 · 보고", previous = "1차 롱숏 A → 감사 기각 → 고정 방향 재구현 F"),
                verdict_line = sprintf("H1 기각 — 롱 레그 β 통제 α %s/년 · t %s(보는 창) · 분기 ④ 롱온리 후보 아님", pct(V$M1_long$alpha_ann), num(V$M1_long$t)),
                card = card, artifact = L_DIR, charts = charts, extra = extra, crisis = "chart",
                next_step = "이 논문의 롱 레그 경로는 닫는다 · 단일 차이 A/B(부호만 · 표본만)는 P1 재료 후보(보는 창 근거만) · 다음 = P3R03 판정",
                push = FALSE, root = ROOT)
cat(substr(r1$msg %||% "", 1, 4000), "\n====\n")
r2 <- tg_agent_brief(agent = "AlphaSearch", title = "[1계층] 다음 리서치 브리핑 — 10-17 새벽",
  sections = list(
    list(type = "summary", emoji = "📌", body = "다음: P3R03 판정(측정 중 · 05시 전후) → 철학 P2 → 종료 보고"),
    list(type = "bullet", heading = "대기 · 결정", items = c(
      "P3R03 — DNN 원형 · B6_36 에 HRP · NCO · Michaud · CVaR · ERC(같은 배치 RX0 대비 · 알파 손실 없이 급락기 낙폭 축소?)",
      "1801.01777 재검증판(F) — 충실도 감사 진행 중 · 통과면 재료(수익 엔진 큐) · 동적 부호 층은 별도 가설로",
      "도훈 결정 대기: MSM as-of 전환 D1~D4(결정 기록부 MSM-ASOF-SWITCH-20261017)",
      "유니버스 49일치 수급 완료(64.5분) — 적재는 오늘 밤 갱신 [0b](측정 중 위생 표식 고정)"))),
  relaxed = TRUE, force = TRUE, decode_jargon = FALSE, glossary = FALSE, mute = TRUE,
  dry_run = identical(Sys.getenv("QVEST_TG_DRY_RUN"), "1"))
cat(substr(r2$msg %||% "", 1, 2000), "\n")
