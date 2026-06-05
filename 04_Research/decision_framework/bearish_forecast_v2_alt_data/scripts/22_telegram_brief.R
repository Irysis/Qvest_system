#==============================================================================
# 22_telegram_brief.R — v1.3 백서급 텔레그램 발송 (qvest-telegram skill 정합)
#==============================================================================

suppressPackageStartupMessages({ library(data.table) })

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
source(file.path(PROJECT_ROOT, "02_Infrastructure/config.R"))
source(file.path(PROJECT_ROOT, "02_Infrastructure/telegram/telegram_notify.R"))

CHART_DIR <- file.path(PROJECT_ROOT,
  "04_Research/decision_framework/bearish_forecast_v2_alt_data/outputs/06_reports/charts")

charts <- list(
  file.path(CHART_DIR, "01_progression.png"),
  file.path(CHART_DIR, "02_individual_models.png"),
  file.path(CHART_DIR, "03_dynamic_ensemble.png"),
  file.path(CHART_DIR, "04_feature_importance.png"),
  file.path(CHART_DIR, "05_calibration.png"),
  file.path(CHART_DIR, "06_timeline.png"),
  file.path(CHART_DIR, "07_regime.png")
)

sections <- list(
  list(title = "🎯 Executive",
       body = "v1.3 — 9 sprint 누적 PR-AUC 0.32 → 0.608 (+90%). Trading-grade. M2 Regime-Conditional 5-way."),
  list(title = "📊 핵심 metric",
       body = "OOS PR-AUC 0.608 (baseline 0.21, lift 2.9배). Recall@top20% 49% / Precision 52%. Recall@top10% 30%/Prec 62%."),
  list(title = "🏆 Architecture",
       body = "5-way: XGBoost+CatBoost+RF+BiLSTM+Transformer / 69 enhanced features / M2 Regime-Conditional dynamic weighting."),
  list(title = "🌐 Data 3계층",
       body = "H3 글로벌 매크로 BBVA 4-channel / H6 US sector flow ⭐ XGB gain 81% / H5 KRX 옵션 implied skew·kurt."),
  list(title = "📈 진화 추이",
       body = "v0.4.2 0.32 → v1.0 0.539 → v1.1 0.567 → v1.2 0.581 → v1.3 0.608. 효과 5개 / 효과 없음 7개."),
  list(title = "✅ 효과 enhancement",
       body = "Alt data / Feature engineering / 5-way ensemble / Regime dynamic / Beta calibration (y_onset Gate3 PASS)."),
  list(title = "❌ 효과 없음",
       body = "XGB tuning / multi-horizon / Stack meta / MTL (task conflict) / Hedge / Bayesian Online / Temperature scaling."),
  list(title = "🚦 5 Gates (OOS)",
       body = "DM p~0.34 marginal / BSS +0.056 PASS / Cal slope 1.29 over-conf / Recall 0.487 PASS / PR-AUC 0.608 PASS. 3/5 PASS."),
  list(title = "🎯 후속 권고",
       body = "(A) Phase 2 decision system 진입 + STR_1715 Layer 6 검토. (B) v1.3 final + L-code. (C) MTL variants retry.")
)

cat("[telegram] Dispatching v1.3 whitepaper brief (9 sections + 7 charts)...\n")
tg_agent_brief(
  agent = "Q-Lead",
  title = "📊 KOSPI200 약세 예측 v1.3 — Whitepaper Brief",
  sections = sections,
  charts = charts
)

cat("[telegram] DONE.\n")
