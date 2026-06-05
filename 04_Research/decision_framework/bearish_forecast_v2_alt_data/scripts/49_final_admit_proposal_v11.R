#==============================================================================
# 49_final_admit_proposal_v11.R — Cycle 19 PRIMARY (v1.1) admit proposal brief
#==============================================================================

suppressPackageStartupMessages({ library(data.table) })

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
source(file.path(PROJECT_ROOT, "02_Infrastructure/config.R"))
source(file.path(PROJECT_ROOT, "02_Infrastructure/telegram/telegram_notify.R"))

CHART_DIR <- file.path(PROJECT_ROOT,
  "04_Research/decision_framework/bearish_forecast_v2_alt_data/outputs/06_reports/charts")

charts <- list(
  file.path(CHART_DIR, "27_final_grid.png"),
  file.path(CHART_DIR, "26_3m_5pct_validation.png"),
  file.path(CHART_DIR, "25_multi_trigger.png"),
  file.path(CHART_DIR, "24_v1a_v3_validation.png")
)

sections <- list(
  list(title = "🎯 18-cycle PRIMARY upgrade",
       body = "Cycle 15 v1.0 spec (6m/-10%%) 발표 후에도 멈추지 않고 cycle 16-18 진화 → TRUE BEST 발견. L-333 적립 (L-332 v1.0 supersede)."),
  list(title = "🏆 Final strategy v1.1",
       body = "KOSPI_DD_Hybrid_V1aV3_2M_5PCT. Trigger: 2m DD ≤ -5%% (≡ 전월 KOSPI200 return ≤ -5%%). V1a (exit after 2m) + V3 dynamic position."),
  list(title = "📈 267m metrics",
       body = "SR 1.83→2.696 (Δ+0.867) / MDD -23.3%%→-15.56%% (+7.73pp 개선) / CAGR 38.2%%→51.2%% (+13pp). Harvey-t +4.779 STRICT_HARVEY 3.0 통과."),
  list(title = "✅ 3-window ALL STRICT_HARVEY",
       body = "267m: dSR +0.867 t+4.78 / 255m: dSR +0.770 t+3.82 / 110m: dSR +0.891 t+2.71. 2017+ data 3m/-5%% subsumed by 2m/-5%%."),
  list(title = "🎯 Local optimum 확정 (cycle 18)",
       body = "2m/-5%% TRUE LOCAL OPTIMUM: 2m/-4%% SR 2.669 / 2m/-6%% 2.401 / 3m/-5%% 2.561 / 4 neighbors all lower SR. Not grid edge artifact."),
  list(title = "📊 vs Canonical v1.0 upgrade",
       body = "v1.0 (6m/-10%%): SR 2.146 dSR +0.317 MDD -23.3%%. v1.1 (2m/-5%%): SR 2.696 dSR +0.867 MDD -15.6%%. ΔdSR +0.55 / ΔdMDD +7.7pp."),
  list(title = "🚀 마일스톤 큰 폭 overshoot",
       body = "SR 2.0 → 2.696 = 0.70 overshoot (v1.0 0.15) / MDD -25%% → -15.6%% = 9.4pp better / CAGR 16%% → 51%% = 35pp overshoot. 모든 dim 큰 폭 통과."),
  list(title = "🔬 Walk-forward 99%%",
       body = "267m × 36m rolling 231/232 windows POSITIVE (canonical 61%%). median dSR +0.767. 27/34 episodes WIN. Bootstrap CI [+0.325, +1.159] significant."),
  list(title = "💡 단순 reframe 발견",
       body = "2m DD ≤ -5%% = previous_month_kospi200_return ≤ -5%% (수학적 등가). 1개 단순 indicator → STR_1715 V-shape 약점 빠르게 보완."),
  list(title = "🎯 도훈 결정 요청 (PRIMARY)",
       body = "(A) Codex Round + AX-008 + WT 생성 admit cycle / (B) 더 강건성 검증 / (C) 결과 정리 + 종료. Auto 시 (B) 추가 검증. PRIMARY_CANDIDATE_PRE_CODEX status.")
)

cat("[telegram] Dispatching v1.1 PRIMARY admit proposal (10 sections + 4 charts)...\n")
tg_agent_brief(
  agent = "Q-Lead",
  title = "🏆 약세예측 18-cycle FINAL — KOSPI_DD_Hybrid_V1aV3_2M_5PCT (TRUE BEST)",
  sections = sections,
  charts = charts
)
cat("[telegram] DONE.\n")
