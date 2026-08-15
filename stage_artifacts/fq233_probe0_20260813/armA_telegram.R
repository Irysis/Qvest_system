## arm A 결과 텔레그램 발송 (qvest-telegram v7 — 표준 5섹션 + 원칙 9 차트 의무)
suppressPackageStartupMessages({library(data.table)})
source("02_Infrastructure/config.R")
source("02_Infrastructure/telegram/telegram_notify.R")
source("02_Infrastructure/telegram/tg_chart_pack.R")
OUT <- "stage_artifacts/fq233_probe0_20260813"

res <- readRDS(file.path(OUT, "armA_canonical_result.rds"))
bas <- readRDS(file.path(OUT, "armA_basis.rds"))
pr  <- as.data.frame(res$period_returns)

paths <- tg_chart_pack(
  period_returns = pr, out_dir = OUT,
  title = "arm A — 평균-표적 ML (대조군)",
  metrics_note = sprintf("total SR %.3f · PORT_t %.2f · MDD %.1f%% · 198개월 (canonical_screen)",
                         bas$sr_total, as.numeric(res$portfolio_alpha_t_nw_lag3), 100*bas$mdd))
cat("차트:", paste(basename(paths), collapse = ", "), "\n")

tg_agent_brief(
  agent = "Q-Lead",
  title = "분포-표적 연구 1단계 — 기존 방식 기준선 재현 성공",
  sections = list(
    list(type = "summary", emoji = "📌",
         body = "ML로 다음 달 수익을 맞히는 기존 방식이 목표 대역을 재현했습니다. 비교 기준선 확보."),

    list(type = "bullet", emoji = "📖", heading = "쉬운 설명",
         items = c(
           "시도: 예측 표적을 평균에서 분포로 바꾸면 더 나은지 보려 합니다",
           "먼저: 비교 대상인 기존 평균 방식부터 다시 재봤습니다",
           "방법: 2010~2026년 198개월을 시간 순서대로 전진하며 모의 운용",
           "결과: 샤프지수 0.60 — 예상 대역(0.30~0.70) 안에 들어왔습니다",
           "의미: 이제 분포 방식이 나은지 비교할 자가 생겼습니다")),

    list(type = "kv", emoji = "📊", heading = "핵심 수치",
         kv = list("샤프지수" = "0.604 (기준 0.49)",
                   "다중검정 t값" = "0.63 (자본선 2.95)",
                   "최대낙폭" = "-64.0%",
                   "회전율" = "1674%/년",
                   "검증 기간" = "198개월")),

    list(type = "bullet", emoji = "🚩", heading = "주의",
         items = c(
           "이건 대조군입니다 — 실제 자본은 배정하지 않습니다",
           "최대낙폭 64%는 운용 한도 25%를 크게 넘습니다",
           "다중검정 t값 0.63으로 자본 투입선 2.95에 한참 못 미칩니다",
           "측정 중 제 실수 2건을 자체 적발해 고쳤습니다 (아래)")),

    list(type = "bullet", emoji = "🔧", heading = "자체 적발한 오류",
         items = c(
           "성과 기준축을 혼동해 '재현 실패'로 낼 뻔했습니다",
           "벤치마크가 일별인데 월간처럼 써서 기간이 절반 잘렸습니다",
           "둘 다 수정 후 재측정 — 기간 198/199개월 회복")),

    list(type = "bullet", emoji = "➡️", heading = "다음",
         items = c(
           "분포 표적(분위 예측) 검증 진행 중 — 결과 나오면 별도 보고",
           "판정은 두 방식의 월별 수익 차이로 냅니다 (사전 등록 완료)",
           "이 단계에서 돈이 움직이는 변화는 없습니다"))
  ),
  charts = paths,
  footer = "📚 사전등록 PREREG_armA_20260813.md · 산출 armA_result.json · FQ-233 Lane A"
)
cat("텔레그램 발송 완료\n")
