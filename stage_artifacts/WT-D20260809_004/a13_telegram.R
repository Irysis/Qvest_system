## A13 — 라운드 완료 텔레그램 (원칙 9: 실측 수치 있으므로 차트 의무)
setwd(Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
suppressPackageStartupMessages({ library(data.table) })
source("02_Infrastructure/config.R")
source("02_Infrastructure/telegram/tg_chart_pack.R")
source("02_Infrastructure/telegram/telegram_notify.R")
OUT <- "stage_artifacts/WT-D20260809_004"
AR <- readRDS(file.path(OUT,"arms.rds")); DG <- readRDS(file.path(OUT,"diagnostics.rds"))

## 차트 1 — arm 서열 비교 막대 (기준선 2.95)
labs <- c("성장 단순 top-25", "섹터정원(틸트 없음)", "결합 λ=0.5", "결합 λ=1.0",
          "틸트 단독(무작위)", "성장 단순 · 전창 284개월")
vals <- c(1.746, 1.090, 1.299, 1.399, -1.163, 2.479)
p1 <- tg_chart_sweep(labels = labs, values = vals, out_dir = OUT,
                     title = "인플레이션 나침반 KR — 층별 실측 t값 (자본 문턱 2.95)",
                     hline = 2.95, highlight = "성장 단순 · 전창 284개월")

## 차트 2 — 발행 알파(층3) 실측 누적수익/연간/낙폭 (계약 산출 period_returns 전달)
pr <- DG$r0_full$period_returns
prr <- data.table(date = pr$date, ret_net = pr$ret_net, benchmark_ret = pr$benchmark_ret)
p2 <- tryCatch(tg_chart_pack(prr, out_dir = OUT,
                title = "발행 알파(컨센서스 성장 합성 · 25종목 동일가중) 실측",
                metrics_note = "t값 2.479 · 정보비율 0.558 · 초과수익 연 8.38% · 회전율 13.55회/년 (canonical_screen_bt)"),
               error = function(e) { cat("chart_pack 실패:", conditionMessage(e), "\n"); character(0) })

charts <- unique(c(p1, p2))
cat("charts:", paste(charts, collapse=" | "), "\n")

tg_agent_brief(
  agent = "Alpha",
  title = "인플레이션 나침반 KR 실측 — 인플레 층은 미확립, 알파는 종목선택 쪽 (도훈 아이디어 FQ-173)",
  sections = list(
    list(type = "text", emoji = "📚", heading = "연구 컨텍스트", body = paste(
      "[연구 목적] 도훈 아이디어 — 인플레이션을 재서 유망 업종을 고르고, 그 업종 안에서 이익성장 상위 종목을 담으면 초과수익이 나는가.",
      "[검토 내용] 미국 기대인플레(5년 손익분기 인플레율)·한국 소비자물가·구리가격 4성분을 합성해 인플레 지수를 만들고, 업종별 인플레 민감도를 60개월 이동창으로 추정해 업종 정원을 연속으로 조절했습니다. 2009년 3월~2026년 7월 209개월, 25종목 동일가중, 거래비용 15bp, 거래대금 2억원 하한.",
      "[결론 1줄] 인플레 층의 기여는 확립되지 않았고(t값 0.98~1.07), 실제 수익은 업종이 아니라 종목선택에서 나왔습니다.", sep = "\n")),

    list(type = "bullet", emoji = "📖", heading = "쉬운 설명", items = c(
      "시도: 물가가 오를 때 유리한 업종을 먼저 고르고, 그 업종에서 이익이 늘어나는 종목을 담는 2단 전략을 검증했습니다",
      "방법: 전략을 세 조각으로 쪼개 각각 따로 재습니다 — 업종 고르기만 / 종목 고르기만 / 둘을 합친 것",
      "결과: 업종 고르기만 하면 수익이 오히려 마이너스였고, 합쳤을 때 늘어난 몫도 우연과 구별되지 않았습니다",
      "의미: 이 아이디어에는 실제 자본을 배정하지 않습니다. 다만 '틀렸다'가 아니라 '아직 판정할 만큼 표본이 충분하지 않다'는 상태로 남깁니다")),

    list(type = "kv", emoji = "📊", heading = "층별 실측 (t값 · 자본 문턱 2.95)", items = list(
      "성장 단순 top-25 (전창 284개월)" = "2.479",
      "성장 단순 top-25 (공통창 209개월)" = "1.746",
      "업종정원 + 종목선택 (틸트 없음)" = "1.090",
      "결합 λ=0.5 / λ=1.0" = "1.299 / 1.399",
      "인플레 틸트 단독 (업종 내 무작위, 20회)" = "-0.889 / -1.163",
      "결합이 종목선택보다 더 번 몫" = "연 +1.09% (t 1.07) / 연 +1.37% (t 0.98)")),

    list(type = "bullet", emoji = "🚩", heading = "정직 고지 3건", items = c(
      "업종 정원 구조 자체가 손해였습니다 — 단순 top-25 대비 연 -2.99%. 인플레 틸트는 그 손해의 일부만 되돌립니다",
      "가설의 핵심 검사(업종별 인플레 민감도 부호가 예측과 맞는가)는 통제 전에는 통과(일치율 0.649)했지만, 자기 적대검증에서 뒤집혔습니다 — 같은 예측표를 그냥 업종 시장민감도로 채점하면 0.822로 더 잘 맞고, 시장 성분을 제거하면 0.600(p 0.085)으로 유의성을 잃습니다. 채널 확인 주장을 철회했습니다",
      "판정 라벨은 '기각'이 아니라 '미확립'입니다 — 필요 효과 대비 관측 효과가 0.39~0.46이라 이 표본으로는 결론을 낼 검정력이 없습니다")),

    list(type = "bullet", emoji = "🔎", heading = "부수 수확", items = c(
      "컨센서스 계열 3종은 모두 당일값 허용 규칙이라, 신호를 같은 달 수익에 맞추면 t값이 13.26으로 부풀고 정상 정렬에서는 5.05입니다 (2.62배). 이 계열을 쓰는 후속 연구는 정렬을 반드시 실증해야 합니다",
      "업종별 인플레 민감도 지도 자체는 시장 성분을 빼도 유틸리티 0.815·건강관리 0.809·철강 0.794로 남습니다 — 선택 알파로는 실패했지만 위험모델 업종 노출 예산이나 오버레이 입력으로는 미측정입니다",
      "설계 원문의 지수 함수는 25종목 정수 격자에서 60~66%의 달에 단 한 자리도 못 바꾸는 크기였습니다. 측정 전에 발견해 스케일을 고정하고 원안도 함께 쟀습니다")),

    list(type = "bullet", emoji = "➡️", heading = "다음", items = c(
      "1안 발행 알파를 동일가중 유니버스 기준으로 재판정 — 시가총액가중 기준에서는 미달이나 동일가중 기준에서는 3.00~3.13이고 보유의 90.6%가 시총 31위 밖입니다",
      "2안 성장 신호 감쇠 진단 — 2003~2014 정보계수 0.041에서 2015년 이후 0.010~0.015로 축소",
      "3안 인플레 틸트 부활 경로 — 창 확대 / 종목-레벨 민감도 랭킹 / 심한 국면 조건부",
      "자본 결정 없음 — governor 미호출, book_state 미변경"))
  ),
  charts = charts
)
cat("텔레그램 발송 완료\n")
