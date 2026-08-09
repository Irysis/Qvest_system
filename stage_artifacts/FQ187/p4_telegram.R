suppressPackageStartupMessages({ library(data.table) })
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- file.path(ROOT,"stage_artifacts/FQ187")
source("02_Infrastructure/config.R"); source("02_Infrastructure/telegram/telegram_notify.R")
source("02_Infrastructure/telegram/tg_chart_pack.R")
R <- fread(file.path(OUT,"p2_clean_allocation.csv"))
labs <- sprintf("%.0f%% / 위험회피%g", R$thr, R$g)
paths <- tg_chart_sweep(labels = labs, values = round(R$clean_diff,3), out_dir = OUT,
  title = "위기 상태의 최적 주식비중 차이 (음수 = 줄여야 유리)", hline = 0, highlight = 1L)
cat("[tg] chart:", paths, "\n")
tg_agent_brief(
  agent = "Q-Lead",
  title = "위기 때 더 사야 하나 — 7라운드 최종 결론 (오염 걷어낸 뒤 재확인)",
  sections = list(
    list(type="summary", emoji="📌",
      body="도훈님 아이디어를 7번 검증했습니다. 위기 때는 늘리는 게 아니라 줄이는 편이 유리합니다."),
    list(type="bullet", emoji="📖", heading="쉬운 설명",
      items=c("시도: 시장이 크게 빠졌을 때 주식을 더 사면 유리한지 확인",
              "방법: 35년 일간 데이터에서 오염된 구간을 걷어내고 최적 비중을 계산",
              "결과: 9개 경우 전부 위기 때 비중이 더 낮게 나왔습니다",
              "의미: 이 방향으로는 자본을 배정하지 않습니다")),
    list(type="kv", emoji="📊", heading="핵심 수치",
      kv=list("최적비중 방향"="위기 때가 더 낮음 (9/9)",
              "정제 효과"="걷어내니 격차가 더 벌어짐",
              "평균 수익"="위기 전후 차이 없음",
              "변동성"="위기 뒤 2~3배 증가")),
    list(type="bullet", emoji="🚩", heading="주의 — 파다가 나온 것",
      items=c("2026년 지수 데이터에 결함 발견 — 별도 수리 작업으로 분리",
              "제가 실패로 버린 지표가 사실 그 결함에 눌려 있었습니다",
              "되살려보니 하루짜리 효과라 실제로는 쓸 수 없었습니다",
              "앞선 보고에서 비용을 연 37.5%로 말한 건 오류 — 실제 연 0.18%")),
    list(type="bullet", emoji="➡️", heading="다음",
      items=c("결론 = 위기 시 비중 확대 근거 없음. 실제 자본 배정 없습니다",
              "반대 방향(얼마나 줄일지)은 아직 안 쟀습니다 — 후속 과제",
              "데이터 결함 수리 후 포함판으로 다시 확인할 예정입니다"))),
  charts = paths,
  footer = "📚 산출: stage_artifacts/FQ187/ · 아크 7라운드 FQ-182/187"
)
cat("[tg] 발송 완료\n")
