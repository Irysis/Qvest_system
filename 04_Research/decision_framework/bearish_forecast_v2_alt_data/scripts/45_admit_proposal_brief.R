#==============================================================================
# 45_admit_proposal_brief.R — Cycle 15 ADMIT proposal telegram brief
#==============================================================================

suppressPackageStartupMessages({ library(data.table) })

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
source(file.path(PROJECT_ROOT, "02_Infrastructure/config.R"))
source(file.path(PROJECT_ROOT, "02_Infrastructure/telegram/telegram_notify.R"))

CHART_DIR <- file.path(PROJECT_ROOT,
  "04_Research/decision_framework/bearish_forecast_v2_alt_data/outputs/06_reports/charts")

charts <- list(
  file.path(CHART_DIR, "24_v1a_v3_validation.png"),
  file.path(CHART_DIR, "22_gfc_resilient.png"),
  file.path(CHART_DIR, "17_bear_conditional_hybrid.png"),
  file.path(CHART_DIR, "21_kospi_dd_hybrid_spec.png")
)

sections <- list(
  list(title = "🎯 14-cycle 자가발전 완주",
       body = "도훈 mandate 2026-05-19 '자가발전형 무한리서치' 14 cycles → KOSPI_DD_Hybrid_V1aV3 ADMIT-ready 후보 발견. L-332 적립."),
  list(title = "📊 진짜 발견 (Reframe)",
       body = "약세예측 모델 INCIDENTAL (cycle 10 model-free sanity). 진짜 alpha = bear_trigger (KOSPI 6m DD ≤ -10%%) + STR_1715 4-overlay V-shape recovery 약점."),
  list(title = "🏆 Strategy spec",
       body = "if bear_trigger AND trig_run≤2 → pos = max(0, 0.7-3×max(0,-(dd+0.10))) else STR_1715. Dynamic position by DD depth (V1a 재진입 + V3 dynamic)."),
  list(title = "📈 3-window ADMIT_STRICT",
       body = "267m: ΔSR +0.317 MDD 0 t+2.68 / 255m: ΔSR +0.293 t+2.45 / 110m: ΔSR +0.551 MDD +4.10pp t+2.38. ALL STRICT."),
  list(title = "✅ 4-checks deep validation",
       body = "Walk-forward 61%% (141/232) + LOO all positive + Bootstrap CI [+0.091, +0.581] significant + 11/13 episodes WIN avg +6.28pp."),
  list(title = "🎯 GFC failure 해결",
       body = "2008-08~09: V0 -15.34pp → V1a -3.47pp → V1a+V3 -1.57pp residual. Trigger persistence ≤2 + DD-depth position scaling 결합 효과."),
  list(title = "🚀 마일스톤 SR 2.0 달성",
       body = "SR target 2.0 vs Hybrid 267m 2.146 = gap closure 100%% + 0.146 overshoot. CAGR +6.3pp 추가. STR_1715 admit V5 SR 1.83 대비 +0.32."),
  list(title = "⚠️ 잔존 risk 3건",
       body = "(i) STR_1715 admit baseline modification → governor approval / (ii) Codex Critic Round 미진행 / (iii) Pure Function audit 의무."),
  list(title = "🎯 도훈 admit 결정 요청",
       body = "(A) Codex Round + AX-008 + WT 생성 (admit cycle full) / (B) 더 검증 후 admit / (C) 결과 정리 + 종료 (no admit). 자동 진행 시 (A)."),
  list(title = "📚 L-332 적립",
       body = "도훈 audit instinct 21번째 hit (월간 리밸런싱 + 인버스 베팅 reframe → 진짜 발견 path). Charter §10 horizontal switching pattern 첫 도입 후보.")
)

cat("[telegram] Dispatching 14-cycle ADMIT proposal brief (10 sections + 4 charts)...\n")
tg_agent_brief(
  agent = "Q-Lead",
  title = "🎯 약세예측 자가발전 14-cycle ADMIT 후보 발견 (KOSPI_DD_Hybrid_V1aV3)",
  sections = sections,
  charts = charts
)
cat("[telegram] DONE.\n")
