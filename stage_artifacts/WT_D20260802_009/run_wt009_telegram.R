# =============================================================================
# run_wt009_telegram.R — WT-D20260802_009 Alpha 브리핑 (tg_agent_brief 단일 진입점)
# 실행: Rscript -e 'source("stage_artifacts/WT_D20260802_009/run_wt009_telegram.R")'
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260802_009")
source("02_Infrastructure/telegram/telegram_notify.R")
source("02_Infrastructure/telegram/tg_chart_pack.R")

R <- readRDS(file.path(OUT, "wt009_eval_results.rds"))
b <- R$bt$M01_PATHQ
pr <- as.data.frame(b$period_returns)

charts <- tg_chart_pack(pr, out_dir = file.path(OUT, "charts"),
  title = "WT-009 모멘텀 경로효율 튜닝판 (유일 문턱 통과)",
  metrics_note = sprintf("알파 t값 %+.2f · 순 샤프지수 %.2f · 회전율 연 %.0f%%",
                         b$portfolio_alpha_t_nw_lag3, b$net_sr, 100 * b$turnover_annual))

lab <- c("가치 섹터상대화", "모멘텀 경로효율", "저변동 EWMA", "퀄리티 shrinkage", "배당 shrinkage")
vals <- sapply(c("P1_VALUE", "P2_MOMENTUM", "P3_LOWVOL", "P4_QUALITY", "P5_DIVIDEND"),
               function(p) R$paired[[p]]$paired_t_nw)
ch2 <- tg_chart_sweep(lab, vals, out_dir = file.path(OUT, "charts"),
  title = "WT-009 튜닝 대 표준 paired t값 (5쌍)",
  value_label = "paired t값 (NW lag-3)", hline = 2.0, hline_label = "교체 후보 문턱 2.0",
  highlight = "모멘텀 경로효율")

tg_agent_brief(
  agent = "Alpha",
  title = "WT-D20260802_009 ALPHA_DONE — 스마트베타 5종 수리 튜닝: 1승 1방향양성 3무효",
  sections = list(
    list(type = "summary", emoji = "\U0001F4CC",
         body = "스마트베타 5종 수리 튜닝 paired 검증 — 모멘텀 경로효율만 문턱 통과(+2.03), 상관 개선"),
    list(type = "kv", emoji = "\U0001F4CA", heading = "5쌍 paired t값 (295/263개월, canonical top-25)",
         kv = list(
           "가치: 섹터 상대화" = "-0.77 무효 — 원본의 섹터 베팅 성분이 수익 원천이었음을 실측",
           "모멘텀: 경로효율" = "+2.03 교체 후보 문턱 통과 (연 +2.9%p) — 단 기전 반증 미통과 주의",
           "저변동: EWMA 추정" = "-1.74 음수 — 추정은 개선(예측 승률 92%)됐으나 소비 프레임이 손실",
           "퀄리티: 경험적 수축가중" = "+1.14 방향 양성 (교체 근거 부족)",
           "배당: 경험적 수축가중" = "-1.36 무효 — 방어 지표는 소폭 개선(최대낙폭 47.3→46.5%)",
           "팩터 간 상관" = "평균 0.209 → 0.145 (다양성 개선, 가치 섹터상대화가 주도)")),
    list(type = "bullet", emoji = "\U0001F9E0", heading = "쉬운 설명",
         items = list(
           "같은 자(팩터 정의)를 쓰되 눈금(추정 수학)만 정밀하게 바꾸면 성적이 오르는지 5종 전부에 1대1 비교를 걸었습니다",
           "모멘텀은 '같은 상승이라도 계단식 완만 상승'을 우대하게 바꾸자 성적이 올랐지만, 그 이유가 설계 의도대로인지는 확증 못 했습니다",
           "저변동 팩터는 눈금을 더 정확히 만들수록 오히려 손해 — 원래 방향의 종목 선정 자체가 손실 프레임이라는 뜻입니다",
           "핵심 발견: 표준 팩터 수익의 상당 부분이 '순수 신호'가 아니라 섹터·고변동 같은 구조 베팅에서 나온다는 것을 역으로 실측했습니다")),
    list(type = "bullet", emoji = "\U0001F6A9", heading = "판정 평문 + 주요 결함",
         items = list(
           "판정: 자본 편입 아님 — 스크리닝 실측이며 교체 여부는 도훈 승인 사안",
           "모멘텀 튜닝판은 문턱을 겨우 넘었고(2.03) 개선이 2015년 이전에 편중 — 후속 검증 전 교체 반대",
           "측정 중 사고 1건: 유니버스 필터 누락으로 1차 측정 전체 무효 → 수리 후 재측정 (설계 변경 없음)",
           "병렬 발견: AST 컴파일러가 36%의 달에 한 달 늦은 팩터값을 쓰는 결함 — 별도 수리 과제 발행")),
    list(type = "bullet", emoji = "\U000027A1", heading = "다음 단계",
         items = list(
           "모멘텀 경로효율의 변동성 성분을 제거한 순수판 재검증 (교체 승인의 전제)",
           "EWMA 변동성 추정기는 알파가 아니라 리스크 모델 입력으로 이식",
           "가치 섹터상대화는 단독이 아닌 다팩터 풀에서 재평가 (상관 감소 기여 실측)"))),
  charts = c(charts, ch2))
cat("[tg] 발송 완료\n")
