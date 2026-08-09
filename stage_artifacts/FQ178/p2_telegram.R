## FQ-178+179 텔레그램 보고 (v7 SOT — 표준 5섹션 + 원칙 9 차트 의무)
suppressPackageStartupMessages({ library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/FQ178")
source("02_Infrastructure/config.R")
source("02_Infrastructure/telegram/telegram_notify.R")
source("02_Infrastructure/telegram/tg_chart_pack.R")

R1 <- readRDS(file.path(OUT, "p1.rds"))

## 원칙 9 — 실측 수치 보고이므로 차트 의무. t값 비교 막대 + 기준선 2.0
labs <- c("주판정 (12개월낙폭)", "성분: 퀄리티/성장", "성분: 밸류",
          "대체정의 3개월누적", "대체정의 24개월낙폭", "대체정의 변동성조정",
          "시대 2003-2012", "시대 2013-2026")
vals <- c(R1$t1, R1$fA$t[2], R1$fV$t[2],
          R1$alt[def=="cum3", t], R1$alt[def=="dd24", t], R1$alt[def=="ddvol", t],
          2.072, -0.266)
paths <- tg_chart_sweep(labels = labs, values = round(vals, 3), out_dir = OUT,
                        title = "낙폭심도 -> 팩터 판별력 변화 (t값, 기준선 2.0)",
                        hline = 2.0, highlight = 1L)
cat("[tg] chart:", paste(paths, collapse=", "), "\n")

tg_agent_brief(
  agent = "Q-Lead",
  title = "위기 뒤에는 어떤 종목이 살아나는가 — 낙폭 깊이별 검증 (판정 불가)",
  sections = list(
    list(type = "summary", emoji = "📌",
         body = "시장이 깊게 빠진 뒤 어떤 종목이 더 오르는지 봤는데, 결론 낼 만큼 표본이 없었습니다."),

    list(type = "bullet", emoji = "📖", heading = "쉬운 설명",
         items = c(
           "시도: 도훈님 아이디어 — 위기 신호가 뜰 때 오히려 더 사야 하는가",
           "방법: 하락 폭을 깊이로 재고, 그 다음 달 어떤 종목이 잘 갔는지 확인",
           "결과: 방향은 보이는데 우연과 구별이 안 됨 (t값 1.18, 기준 2.0)",
           "의미: 실제 자본 배정 없음. 다만 기각도 아니라 다음 설계로 넘깁니다")),

    list(type = "kv", emoji = "📊", heading = "핵심 수치",
         kv = list("기울기 t값"   = "+1.177 (기준 2.0 미달)",
                   "검출 하한 대비" = "관측치가 0.59배 — 표본 부족",
                   "성분 비교"    = "퀄리티/성장 1.65 vs 밸류 0.23",
                   "유효표본"     = "4개 -> 38.9개 (연속화 효과)")),

    list(type = "bullet", emoji = "🚩", heading = "주의",
         items = c(
           "부호가 사전 예상과 반대 — 깊은 하락 뒤 밸류가 상대 우위",
           "다만 유의하지 않아 방향 주장 자체가 불가합니다",
           "2003-2012 구간만 t 2.07 — 구간 쪼개면 검정력이 무너져 승격 불가",
           "정보계수는 참고 지표라 어느 방향이든 자본 판정 근거 아님")),

    list(type = "bullet", emoji = "➡️", heading = "다음",
         items = c(
           "판정 불가 — 실제 돈은 넣지 않고 설계를 바꿔 재도전합니다",
           "FQ-180: 어떤 문턱으로도 안 되면 이 방향을 문서로 닫고 반복 중단",
           "도훈님 원 가설(비중 확대)은 여전히 별도 축 — 이번엔 종목 선별만 측정"))
  ),
  charts = paths,
  footer = "📚 산출: stage_artifacts/FQ178/ (사전등록·측정·차트)"
)
cat("[tg] 발송 완료\n")
