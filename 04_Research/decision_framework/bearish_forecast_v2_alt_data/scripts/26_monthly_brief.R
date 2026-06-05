#==============================================================================
# 26_monthly_brief.R — 월간 리밸런싱 예측력 결과 텔레그램 브리핑 (≤220자/섹션)
#==============================================================================

suppressPackageStartupMessages({ library(data.table) })

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
source(file.path(PROJECT_ROOT, "02_Infrastructure/config.R"))
source(file.path(PROJECT_ROOT, "02_Infrastructure/telegram/telegram_notify.R"))

CHART_DIR <- file.path(PROJECT_ROOT,
  "04_Research/decision_framework/bearish_forecast_v2_alt_data/outputs/06_reports/charts")

charts <- list(
  file.path(CHART_DIR, "09_monthly_rebal_eval.png"),
  file.path(CHART_DIR, "08_recent_12m_timeline.png"),
  file.path(CHART_DIR, "06_timeline.png")
)

sections <- list(
  list(title = "⚠️ Q-Lead 자체 inaccuracy 인정",
       body = "shift(x,-1,'lead')는 LAG(1)이지 LEAD가 아님. 만약 이전에 IC -0.5 보고했다면 그건 버그 결과. 수정 후 정확한 monthly IC = +0.110."),
  list(title = "🎯 정확한 월간 예측력 (110m)",
       body = "Snapshot 2017-02~2026-04, 매 월말 p_bear → 다음달 close-to-close ret. Pearson +0.110 / Spearman -0.022 (random). 모델 monthly forecast 능력 사실상 없음."),
  list(title = "📊 Tercile 결과 (WRONG SIGN)",
       body = "Top30%% (alert) mean_ret = +2.54%% / Bot30%% +1.32%% / Spread +1.22pp. 기대는 Top<Bot인데 반대 방향. monthly close return 측면에서 alert가 더 잘 가는 달."),
  list(title = "📉 Hit Rate (Top30 alert)",
       body = "Bear=ret<-3%% 기준: Precision 0.15 (baseline 0.22 미만) / Recall 0.21. 월간 bear 5개 중 1개만 사전 alert 잡음."),
  list(title = "🔬 본질 이유 — Target mismatch",
       body = "모델 target = 21d forward Q15 (purged) — daily tail timing 신호. monthly close 1축은 별개. 같은 21d 안 V-shape이면 monthly + 가능. Daily PR-AUC 0.608 ≠ monthly forecast."),
  list(title = "📅 최근 6m snap detail",
       body = "12/30 a=0.46→1월 +24%% FP / 1/30 a=0.46→2월 +20%% FP / 2/27 p=0.27 just below→3월 -19%% (alert 1m 빨랐음) / 3/31 p=0.18→4월 +32%% TN / 4/30 a=0.37→5월 +12%% partial."),
  list(title = "🚨 4/30 → 5월 (live)",
       body = "p=0.371 (alert ON, thr=0.278). Regime=bear. 실제 5/19까지 partial close-to-close +12.33%%. BUT 5/15→5/19 -6%% sharp drop 진행. monthly로는 FP 가능, daily tail로는 부분 적중."),
  list(title = "💡 권고",
       body = "(A) 월간 게이트 사용 부적합 / (B) y_month_q15 target 재정의 + 재학습 / (C) daily p_bear의 월간 max/avg를 feature로 monthly model / (D) daily drawdown depth로 평가 시 결과 다를 수 있음."),
  list(title = "🤔 정직 평가",
       body = "daily 0.608 / monthly IC~0 둘 다 진짜. 별개 측정. 모델은 monthly 리밸런싱 게이트로 weak. 도훈 직감이 모델 application boundary 정확히 짚음.")
)

cat("[telegram] Dispatching monthly rebal eval brief (9 sections + 3 charts)...\n")
tg_agent_brief(
  agent = "Q-Lead",
  title = "📊 약세예측모델 — 월간 리밸런싱 평가 (정정)",
  sections = sections,
  charts = charts
)
cat("[telegram] DONE.\n")
