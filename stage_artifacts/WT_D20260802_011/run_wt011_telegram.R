# =============================================================================
# run_wt011_telegram.R — WT-D20260802_011 Alpha 브리핑 (tg_agent_brief 단일 진입점)
# 실행: Rscript -e 'source("stage_artifacts/WT_D20260802_011/run_wt011_telegram.R")'
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260802_011")
source("02_Infrastructure/telegram/telegram_notify.R")
source("02_Infrastructure/telegram/tg_chart_pack.R")

R <- readRDS(file.path(OUT, "wt011_eval_results.rds"))
b <- R$bt$SIG_LEVY_PV_63_SM3
pr <- as.data.frame(b$period_returns)

charts <- tg_chart_pack(pr, out_dir = file.path(OUT, "charts"),
  title = "WT-011 시그니처 3M 평활판",
  metrics_note = sprintf("알파 t값 %+.2f · 순 샤프지수 %+.2f · 회전율 연 %.0f%% (제약 1100%% 충족)",
                         b$portfolio_alpha_t_nw_lag3, b$net_sr, 100 * b$turnover_annual))

lab <- c("원판 1M (WT-006)", "3M 평활 (판정)", "6M 평활 (진단)", "3M lag1",
         paste0("난수 대조군 ", 1:5))
vals <- c(1.225, b$portfolio_alpha_t_nw_lag3,
          R$bt$SIG_LEVY_PV_63_SM6$portfolio_alpha_t_nw_lag3,
          R$bt_lag1$portfolio_alpha_t_nw_lag3,
          sapply(R$placebo, `[[`, "port_t"))
ch2 <- tg_chart_sweep(lab, vals, out_dir = file.path(OUT, "charts"),
  title = "WT-011 평활 창별 알파 t값과 난수 대조군",
  value_label = "포트폴리오 알파 t값", hline = 2.95, hline_label = "자본 게이트 2.95",
  highlight = "3M 평활 (판정)")

tg_agent_brief(
  agent = "Alpha",
  title = "WT-D20260802_011 ALPHA_DONE — 시그니처 3M 평활: 회전 충족·수익 신호 소멸·수급 링크 보존",
  sections = list(
    list(type = "summary", emoji = "\U0001F4CC",
         body = "WT-006 후속 관문 라운드 — 3개월 평활로 회전율 제약은 충족했으나 수익 신호가 무신호 대조군 수준으로 소멸. 반면 수급 예측 링크는 무손실 보존."),
    list(type = "kv", emoji = "\U0001F4CA", heading = "핵심 실측 (257개월, canonical)",
         kv = list(
           "회전율 (1차 관문)" = "연 1053% — 제약 1100% 충족 (원판 1578%에서 33% 감축)",
           "포트폴리오 알파 t값" = "-0.27 (원판 +1.23) — 난수 대조군 범위 [-1.22, -0.24] 안 = 신호 소멸",
           "동일가중 벤치 기준" = "-0.45, 2017년 이후 -0.08 — 양쪽 기준 공멸",
           "신호 보존율" = "수익축 -0.22 (소멸) / 수급축 1.00 (무손실)",
           "수급 기전 링크" = "익월 기관+외인 매집 t값 +4.09 (원판 +4.08) — 완전 보존",
           "6개월 평활 (진단)" = "+0.37 — 창을 늘려도 소생 없음")),
    list(type = "bullet", emoji = "\U0001F9E0", heading = "쉬운 설명",
         items = list(
           "신호를 3개월 평균으로 눌러 매매 횟수를 줄이는 실험입니다 — 횟수는 규정 안으로 들어왔습니다",
           "그런데 이 신호의 수익 정보는 한 달을 못 가는 짧은 유통기한이라, 평균을 내는 순간 수익 예측력이 사라졌습니다",
           "반면 어떤 종목에 기관·외국인 돈이 들어올지 맞히는 능력은 3개월 묵은 신호로도 그대로였습니다",
           "결론: 이 신호는 주식 선정용이 아니라 수급 예측·감시용으로 쓰는 것이 맞습니다")),
    list(type = "bullet", emoji = "\U0001F6A9", heading = "판정 평문 + 주요 결함",
         items = list(
           "판정: 종목 선정 편입 불가 — 평활 경로의 수익 신호는 현 설정에서 소멸 확정",
           "회전 제약과 신호 유통기한(1개월 미만)이 이 설정에서 양립 불가함을 실측으로 확정",
           "자기 적대 검증 4건 처리 (수용 1 / 부분수용 3) — 상부 보고 필요 결함 0건",
           "부활 조건: 회전 규정이 다른 소비 경로(오버레이·모니터링) 신설 시, 또는 신호 나이별 감쇠 곡선에서 당월 성분 단독 유효 실측 시")),
    list(type = "bullet", emoji = "\U000027A1", heading = "다음 단계",
         items = list(
           "1순위: 수급 예측 소비면 라운드 — 매집 신호를 감시 경보·수급 팩터 강화에 사용 (2라운드 연속 t값 +4.1 실측)",
           "2순위: 신호 나이별 감쇠 곡선 — 당월/1개월/2개월 성분별 알파 분해로 유통기한 정밀 실측",
           "2순위: 시간-가격 면적 역방향 가설 (WT-006 계승, 부호 사전 고정 독립 라운드)"))),
  charts = c(charts, ch2))
cat("[tg] 발송 완료\n")
