# =============================================================================
# run_wt013_telegram.R — WT-D20260802_013 Alpha 브리핑 (tg_agent_brief 단일 진입점)
# 실행: Rscript -e 'source("stage_artifacts/WT_D20260802_013/run_wt013_telegram.R")'
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260802_013")
source("02_Infrastructure/telegram/telegram_notify.R")
source("02_Infrastructure/telegram/tg_chart_pack.R")

R <- readRDS(file.path(OUT, "wt013_eval_results.rds"))
b <- R$bt$M01_PATHQ_RESID
pr <- as.data.frame(b$period_returns)

charts <- tg_chart_pack(pr, out_dir = file.path(OUT, "charts"),
  title = "WT-013 경로효율 vol-잔차 순수판 (단독 성과)",
  metrics_note = sprintf("알파 t값 %+.2f · 순 샤프지수 %.2f · 회전율 연 %.0f%%",
                         b$portfolio_alpha_t_nw_lag3, b$net_sr, 100 * b$turnover_annual))

# paired t 비교: 원판 / 잔차판 / placebo 5시드
lab <- c("원판 (WT-009)", "vol-잔차 순수판", "placebo 시드1", "placebo 시드2",
         "placebo 시드3", "placebo 시드4", "placebo 시드5")
vals <- c(R$paired_pathq_parity$paired_t_nw, R$paired_resid$paired_t_nw,
          vapply(R$paired_placebo, `[[`, numeric(1), "paired_t_nw"))
ch2 <- tg_chart_sweep(lab, vals, out_dir = file.path(OUT, "charts"),
  title = "WT-013 base 대비 paired t값 — 잔차판과 미소-섭동 통제군",
  value_label = "paired t값 (NW lag-3)", hline = 2.0, hline_label = "사전등록 문턱 2.0",
  highlight = "vol-잔차 순수판")

tg_agent_brief(
  agent = "Alpha",
  title = "WT-D20260802_013 ALPHA_DONE — 경로효율 순수판 판별: 문턱 미달, 교체 보류 확정",
  sections = list(
    list(type = "summary", emoji = "\U0001F4CC",
         body = "경로효율 순수판 paired t +1.72 문턱 미달 — 교체 보류. 실사유는 통계 취약성 + 2015 이전 편중"),
    list(type = "kv", emoji = "\U0001F4CA", heading = "판별 실측 (295개월, canonical top-25, 순비용 기준)",
         kv = list(
           "잔차판 paired t값" = "+1.72 (문턱 2.0 미달) — 연 +2.9%p, 원판 +2.03 대비 유의성 하락",
           "변동성 적재 실측" = "-0.060 (저변동 반대 부호) — 편승 성분 자체가 없었음",
           "잔차화 순효과" = "잔차판 대 원판 t -0.02 — 사실상 동일 (상관 0.974)",
           "placebo 통제 5시드" = "t +1.87~+2.80 (표준편차 0.38) — 미소 변화로 문턱 넘나듦",
           "부기간 분해" = "2015이전 +3.20 / 15~19 -0.33 / 20~ +0.27 — 편중 잔존",
           "기전 반증 재검 (F2)" = "+1.92 (원판 +1.05) — 경계선 개선, 확증 미달",
           "잔차판 단독 알파 t값" = "+2.14 (원판 +2.05) — 졸업 문턱 2.95 미달")),
    list(type = "bullet", emoji = "\U0001F9E0", heading = "쉬운 설명",
         items = list(
           "교체 후보(완만한 경로의 모멘텀 우대)에 '저변동 종목 편승' 혐의가 있어 수술로 확인했습니다",
           "변동성 성분을 제거한 순수판을 만들어 표준 모멘텀과 재대결시킨 것입니다",
           "결과: 제거할 변동성 성분 자체가 거의 없었습니다 — 혐의 자체는 무죄",
           "대신 진짜 문제 발견 — 종목 선정을 살짝만 흔들어도(무작위 5회) 점수가 1.9~2.8을 오르내림",
           "원판의 '문턱 통과 +2.03'은 견고한 결과가 아니라 문턱 근처의 우연한 한 표본이었습니다",
           "개선분도 2015년 이전에 몰려 있어 최근 10년엔 0과 구분 불가 — 교체 실익이 없습니다")),
    list(type = "bullet", emoji = "\U0001F6A9", heading = "판정 평문 + 결함 플래그",
         items = list(
           "판정: 사전등록 문턱 미달 — 교체안 상정 않음 (M01 표준 유지). 자본 편입 아님",
           "사전등록 문구(미달=변동성 편승 확정)와 실측 기전 불일치 — 의사결정은 규칙대로 집행",
           "기전 귀속은 사전등록 통제 실측으로 정정 기록 (challenge_note C1)",
           "동월 누출 점검: lag1 감쇠 -21%로 모멘텀 계열 정상 범위, 누출 지문 없음",
           "회전율 연 793% (상한 1100% 이내) — 교체 보류로 소멸")),
    list(type = "bullet", emoji = "\U000027A1", heading = "다음 단계 (next_probe)",
         items = list(
           "교체류 판정 프레임 강화: 선정-섭동 paired 분포의 하한으로 판정하는 규약 사전등록 (P1)",
           "점프-비중 직접 팩터화: 경계선(+1.92) 경로-질 기전을 표적 신호로 재설계 (P2)",
           "부활 조건: 섭동-분포 하한 > 0 또는 2015 이후 paired t > 1.5 성립 시 재상정"))),
  charts = c(charts, ch2))
cat("[tg] 발송 완료\n")
