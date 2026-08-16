## 백서 요약 + 8월 실현 트래킹 텔레그램 — v7 SOT 정합
##  표준 5섹션 + 원칙 8 3장치 + 원칙 9(실측 = 차트 의무). force 미사용(중복차단 유지).
if (identical(as.integer(Sys.getenv("ARROW_IO_THREADS", "0")), 1L)) Sys.setenv(ARROW_IO_THREADS = "2")
ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
setwd(ROOT)
source(file.path(ROOT, "02_Infrastructure/telegram/telegram_notify.R"))
source(file.path(ROOT, "02_Infrastructure/telegram/tg_chart_pack.R"))
DRY <- "--dry-run" %in% commandArgs(TRUE)
OUT <- file.path(ROOT, "stage_artifacts/pg2_repair_20260813")
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)

## 차트 = 실측 3종 비교 (track_aug.R 산출값 — 차트팩은 시각화 전용, 계산 안 함)
png1 <- tg_chart_sweep(
  labels = c("북 전체(현금 79%)", "주식부만", "벤치마크 KOSPI200"),
  values = c(4.0668, 19.3656, 11.2960),
  out_dir = OUT,
  title = "2026-08-03 종가 매수 → 08-14 누적수익 (%)",
  value_label = "누적수익 %",
  highlight = "북 전체(현금 79%)",
  filename = "aug_track_3way.png")

png2 <- tg_chart_sweep(
  labels = c("전기간 오버레이 전", "전기간 오버레이 적용", "최근5년 오버레이 전", "최근5년 오버레이 적용"),
  values = c(40.74, 23.29, 29.20, 19.79),
  out_dir = OUT,
  title = "최대낙폭 MDD (%) — 낮을수록 좋음 · 271개월 백테스팅",
  value_label = "MDD %",
  highlight = "전기간 오버레이 적용",
  filename = "mdd_overlay_effect.png")

res <- tg_agent_brief(
  agent = "Q-Lead",
  title = "PG2 리스크 오버레이 백서 발행 + 8월 실현 트래킹",
  sections = list(
    list(type = "summary", emoji = "📌",
         body = "오버레이 구조를 백서로 정리했습니다. 8월 첫 2주는 그 장치가 수익을 크게 눌렀습니다."),

    list(type = "bullet", emoji = "📖", heading = "쉬운 설명",
         items = c(
           "구조: 종목 고르는 층과 얼마나 투자할지 정하는 층이 나뉘어 있습니다",
           "장치: 시장이 위험하다 판단하면 주식을 줄이고 현금을 늘립니다",
           "이력: 지난 22년 모의운용에선 최대 손실폭을 40.7%→23.3%로 줄였습니다",
           "이번엔: 8월 첫 2주 시장이 크게 올라 현금 79%가 손해로 작용했습니다")),

    list(type = "kv", emoji = "📊", heading = "8월 실현 (08-03 종가 매수 → 08-14)",
         kv = list(
           "북 전체"   = "+4.07% (주식 21% + 현금 79%)",
           "주식부만"  = "+19.37% (오버레이 없었다면)",
           "벤치마크"  = "+11.30% (KOSPI200)",
           "종목 선정" = "벤치 대비 +8.07%p",
           "오버레이"  = "-15.30%p")),

    list(type = "bullet", emoji = "🚩", heading = "주의",
         items = c(
           "9거래일 표본입니다 — 방향을 단정할 구간이 아닙니다",
           "보유 20종목 전부 상승했고 하락 종목은 0건입니다",
           "위기 라벨은 22년 중 5번뿐이고 그중 3번이 올해입니다",
           "백서 수치는 모의운용 기준이며 실계좌 실현이 아닙니다")),

    list(type = "bullet", emoji = "➡️", heading = "다음",
         items = c(
           "자본 조치 없음 — 실주문은 도훈 수동 결정입니다",
           "8월 판정의 옳고 그름은 월말 이후에 판단 가능합니다",
           "백서 전문은 아래 링크에서 확인하실 수 있습니다")),

    list(type = "text", emoji = "🔍", heading = "백서가 담은 것",
         body = paste("세 층의 규칙과 입력, 그리고 22년 발화율을 전부 실측으로 실었습니다.",
                      "설계 논의는 게이트에 쏠려 있었지만 실제로 방어한 층은 꼬리위험 조절이었습니다.",
                      "숨기면 곤란한 한계 8가지도 함께 적었습니다."))
  ),
  charts = c(png1, png2),
  dry_run = DRY,
  footer = "📚 백서: https://claude.ai/code/artifact/86d1a00b-01d6-4072-94c0-72fb9a9e20e1"
)
cat(sprintf("\n[tg] dry_run=%s ok=%s bytes=%s\n", DRY, res$ok, res$bytes))
