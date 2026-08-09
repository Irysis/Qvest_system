## FQ-182 텔레그램 (v7 SOT — 표준 5섹션 + 원칙 9 차트 의무)
suppressPackageStartupMessages({ library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/FQ182")
source("02_Infrastructure/config.R")
source("02_Infrastructure/telegram/telegram_notify.R")
source("02_Infrastructure/telegram/tg_chart_pack.R")

## 원칙 9 — 실측 수치 보고이므로 차트 의무. 전방창별 효과(부호 반전) 비교 막대.
labs <- c("1일", "2일", "3일", "5일", "10일", "20일", "60일")
vals <- c(0.580, 0.386, 0.214, 0.081, -0.027, -0.437, -1.070)
paths <- tg_chart_sweep(labels = labs, values = vals, out_dir = OUT,
                        title = "낙폭 뒤 왜도 차이 — 보유기간별 (1~2일만 양수, 60일은 반대)",
                        hline = 0, highlight = 7L)
cat("[tg] chart:", paste(paths, collapse=", "), "\n")

tg_agent_brief(
  agent = "Q-Lead",
  title = "위기 때 오히려 사야 하나 — 6라운드 검증 종료 (결론: 근거 없음)",
  sections = list(
    list(type = "summary", emoji = "📌",
         body = "위기 뒤에 더 사야 한다는 아이디어를 6번 다르게 검증했고, 지지 근거를 못 찾았습니다."),

    list(type = "bullet", emoji = "📖", heading = "쉬운 설명",
         items = c(
           "시도: 시장이 크게 빠진 뒤 주식을 더 사면 유리한지 확인",
           "방법: 36년 일간 데이터로 하락 깊이별 그 다음 수익 분포를 측정",
           "결과: 평균은 안 오르고 위험만 2~3배 커짐 — 오히려 줄여야 유리",
           "의미: 실제 돈은 이 방향으로 넣지 않습니다")),

    list(type = "kv", emoji = "📊", heading = "핵심 수치",
         kv = list("최적 비중"   = "위기 때가 평시보다 낮음 (12/12)",
                   "평균 변화"   = "통계적으로 구별 안 됨",
                   "변동성 변화" = "2.9~3.5배 증가",
                   "60일 보유"   = "효과 부호가 반대로 뒤집힘")),

    list(type = "bullet", emoji = "🚩", heading = "주의 — 제 오류 2건",
         items = c(
           "사전에 정한 1급 지표가 떨어지자 다른 지표로 갈아타 보고했습니다",
           "그 대체 지표는 하루치 관측이 99%를 만든 값이었습니다",
           "그 하루는 지수만 20% 뛰고 종목은 4%인 데이터 결함일이었습니다",
           "적대검증 5개 팀이 전부 반증 판정 — 제 보고가 틀렸습니다")),

    list(type = "bullet", emoji = "➡️", heading = "다음",
         items = c(
           "결론 = 위기 때 비중 확대는 근거 없음. 자본 배정 없습니다",
           "하락 깊이가 깊을수록 강해지는 패턴 1건은 살아남아 후속 검증",
           "2026 지수 데이터 결함은 별도 수리 작업으로 분리했습니다"))
  ),
  charts = paths,
  footer = "📚 산출: stage_artifacts/FQ182/ · 적대검증 wf_03dc6cd7-f14"
)
cat("[tg] 발송 완료\n")
