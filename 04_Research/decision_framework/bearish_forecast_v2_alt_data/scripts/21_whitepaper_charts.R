#==============================================================================
# 21_whitepaper_charts.R — 백서급 시각화 7장 생성
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(ggplot2)
  library(patchwork); library(scales); library(gridExtra)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
WS <- file.path(PROJECT_ROOT, "04_Research/decision_framework/bearish_forecast_v2_alt_data")
OUT_DIR <- file.path(WS, "outputs/06_reports/charts")
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

theme_qvest <- theme_minimal(base_size = 12) +
  theme(plot.title = element_text(face = "bold", size = 14),
        plot.subtitle = element_text(color = "gray40"),
        panel.grid.minor = element_blank(),
        plot.background = element_rect(fill = "white", color = NA))

# ── Chart 1: Progression bar ────────────────────────────────
prog <- data.table(
  Version = c("v0.4.2", "v1.0", "v1.0.1", "v1.1", "v1.2", "v1.3"),
  PR_AUC = c(0.320, 0.539, 0.539, 0.567, 0.581, 0.608),
  Method = c("KR factor (null)", "Alt data + XGB", "XGB depth4", "+ 3-way EW",
             "+ LSTM/TFT 5-way", "+ M2 Regime Dynamic")
)
prog[, Version := factor(Version, levels = Version)]
g1 <- ggplot(prog, aes(x = Version, y = PR_AUC, fill = PR_AUC)) +
  geom_bar(stat = "identity", width = 0.7) +
  geom_text(aes(label = sprintf("%.3f", PR_AUC)), vjust = -0.5, size = 4) +
  geom_text(aes(label = Method, y = 0.05), color = "white", size = 3, angle = 90, hjust = 0) +
  geom_hline(yintercept = 0.209, linetype = "dashed", color = "red") +
  annotate("text", x = 1.5, y = 0.23, label = "baseline 0.21 (prevalence)",
           color = "red", size = 3.5) +
  scale_fill_gradient(low = "#FCC", high = "#073B4C") +
  labs(title = "Chart 1 — Evolution of Bearish Forecast Model",
       subtitle = "v0.4.2 (null result) → v1.3 best (PR-AUC 0.608, +90% lift)",
       x = NULL, y = "OOS PR-AUC (y_tail_q15)") +
  scale_y_continuous(limits = c(0, 0.7), expand = c(0, 0)) +
  theme_qvest + theme(legend.position = "none")
ggsave(file.path(OUT_DIR, "01_progression.png"), g1, width = 9, height = 5, dpi = 120)
cat("[Chart 1] Saved\n")

# ── Chart 2: Individual models ──────────────────────────────
ind <- data.table(
  Model = c("XGBoost", "CatBoost", "Ranger RF", "BiLSTM", "Transformer", "MTL-UNC"),
  PR_AUC_tail = c(0.5503, 0.5594, 0.5272, 0.4758, 0.4081, 0.4896),
  PR_AUC_onset = c(0.1027, 0.1111, 0.0958, 0.1443, 0.0856, 0.1085)
)
ind_long <- melt(ind, id.vars = "Model", variable.name = "Target", value.name = "PR_AUC")
ind_long[, Target := gsub("PR_AUC_", "", Target)]
ind_long[, Model := factor(Model, levels = ind$Model)]
g2 <- ggplot(ind_long, aes(x = Model, y = PR_AUC, fill = Target)) +
  geom_bar(stat = "identity", position = position_dodge(0.7), width = 0.6) +
  geom_text(aes(label = sprintf("%.3f", PR_AUC)),
            position = position_dodge(0.7), vjust = -0.5, size = 3) +
  scale_fill_manual(values = c("tail" = "#073B4C", "onset" = "#EF476F")) +
  labs(title = "Chart 2 — Individual Model OOS PR-AUC",
       subtitle = "y_tail_q15 (primary) vs y_onset (secondary)",
       x = NULL, y = "OOS PR-AUC", fill = "Target") +
  theme_qvest +
  theme(axis.text.x = element_text(angle = 0))
ggsave(file.path(OUT_DIR, "02_individual_models.png"), g2, width = 10, height = 5, dpi = 120)
cat("[Chart 2] Saved\n")

# ── Chart 3: Dynamic ensemble 5 methods ─────────────────────
dyn <- data.table(
  Method = c("Static WEW", "M1 Rolling", "M2 Regime", "M3 Hedge", "M4 Bayesian", "M5 Bandit"),
  PR_AUC = c(0.5814, 0.6063, 0.6078, 0.5510, 0.5525, 0.5798)
)
dyn[, Method := factor(Method, levels = dyn$Method)]
dyn[, Color := ifelse(PR_AUC > 0.5814, "Better", ifelse(PR_AUC < 0.5814, "Worse", "Equal"))]
g3 <- ggplot(dyn, aes(x = Method, y = PR_AUC, fill = Color)) +
  geom_bar(stat = "identity", width = 0.7) +
  geom_text(aes(label = sprintf("%.4f", PR_AUC)), vjust = -0.5, size = 4) +
  geom_hline(yintercept = 0.5814, linetype = "dashed", color = "gray30") +
  annotate("text", x = 1, y = 0.585, label = "Static WEW baseline",
           color = "gray30", size = 3.5, hjust = 0) +
  scale_fill_manual(values = c("Better" = "#06D6A0", "Worse" = "#EF476F", "Equal" = "#FFD166")) +
  labs(title = "Chart 3 — Dynamic Ensemble 5 Methods (y_tail_q15)",
       subtitle = "M2 Regime-Conditional best (PR-AUC 0.6078, +4.5%)",
       x = NULL, y = "OOS PR-AUC") +
  scale_y_continuous(limits = c(0.5, 0.65), oob = oob_keep) +
  theme_qvest +
  theme(legend.position = "none")
ggsave(file.path(OUT_DIR, "03_dynamic_ensemble.png"), g3, width = 9, height = 5, dpi = 120)
cat("[Chart 3] Saved\n")

# ── Chart 4: Feature importance (XGBoost top 10) ────────────
fi <- data.table(
  Feature = c("us_sector_avg_z", "us_sector_dispersion_z", "bbva_market_z",
              "bbva_transmission_z", "bbva_macro_composite",
              "kr_credit_spread", "kr_term_spread", "bbva_sovereign_z",
              "k200_implied_skew_z", "k200_implied_kurt_z"),
  Gain = c(0.58, 0.23, 0.08, 0.05, 0.05, 0.03, 0.02, 0.02, 0.01, 0.01) / 1.08,
  Block = c("H3", "H3", "H6", "H6", "H6", "H4", "H4", "H6", "H5", "H5")
)
fi <- fi[order(Gain)]
fi[, Feature := factor(Feature, levels = Feature)]
g4 <- ggplot(fi, aes(x = Gain * 100, y = Feature, fill = Block)) +
  geom_bar(stat = "identity", width = 0.7) +
  geom_text(aes(label = sprintf("%.1f%%", Gain * 100)), hjust = -0.1, size = 3.5) +
  scale_fill_manual(values = c("H3" = "#EF476F", "H4" = "#FFD166",
                                "H5" = "#06D6A0", "H6" = "#118AB2")) +
  labs(title = "Chart 4 — XGBoost Feature Importance (top 10)",
       subtitle = "US sector flow 81% dominant (avg 54% + dispersion 21%)",
       x = "Gain (%)", y = NULL, fill = "Block") +
  scale_x_continuous(limits = c(0, 65), expand = c(0, 0)) +
  theme_qvest
ggsave(file.path(OUT_DIR, "04_feature_importance.png"), g4, width = 10, height = 5, dpi = 120)
cat("[Chart 4] Saved\n")

# ── Chart 5: Calibration plot ───────────────────────────────
preds_path <- file.path(WS, "outputs/03_models/multi_algorithm/predictions_3way_y_tail_q15.parquet")
preds <- as.data.table(read_parquet(preds_path))
oos <- preds[split == "oos"]
bins <- cut(oos$p_ew, breaks = seq(0, 1, length.out = 11), include.lowest = TRUE)
cal_dt <- oos[, .(mean_pred = mean(p_ew), mean_actual = mean(y), n = .N), by = bins]
cal_dt <- cal_dt[!is.na(bins)]
g5 <- ggplot(cal_dt, aes(x = mean_pred, y = mean_actual, size = n)) +
  geom_abline(slope = 1, intercept = 0, linetype = "dashed", color = "gray40") +
  geom_point(color = "#073B4C", alpha = 0.7) +
  geom_line(aes(group = 1), color = "#073B4C", alpha = 0.5) +
  scale_size_continuous(range = c(2, 10)) +
  labs(title = "Chart 5 — Calibration Plot (y_tail_q15, OOS)",
       subtitle = "perfect calibration = diagonal. ECE 0.063 (slight over-confident)",
       x = "Mean predicted probability", y = "Mean actual frequency",
       size = "Sample N") +
  coord_equal(xlim = c(0, 1), ylim = c(0, 1)) +
  theme_qvest
ggsave(file.path(OUT_DIR, "05_calibration.png"), g5, width = 7, height = 6, dpi = 120)
cat("[Chart 5] Saved\n")

# ── Chart 6: OOS timeline (p_bear) ──────────────────────────
oos[, Date := as.Date(Date)]
setorder(oos, Date)
events <- oos[y == 1]
g6 <- ggplot(oos, aes(x = Date, y = p_ew)) +
  geom_line(color = "#073B4C", alpha = 0.6, linewidth = 0.3) +
  geom_rug(data = events, aes(x = Date), sides = "b", color = "#EF476F", alpha = 0.5) +
  geom_hline(yintercept = quantile(oos$p_ew, 0.8, na.rm = TRUE),
             linetype = "dashed", color = "orange") +
  annotate("text", x = max(oos$Date), y = quantile(oos$p_ew, 0.82, na.rm = TRUE),
           label = "top 20% alert threshold", color = "orange", size = 3, hjust = 1) +
  labs(title = "Chart 6 — OOS p_bear timeline (y_tail_q15)",
       subtitle = "2016-01 ~ 2026-04 / red rugs = actual events (530 days)",
       x = NULL, y = "Predicted probability (p_ew 3-way)") +
  theme_qvest
ggsave(file.path(OUT_DIR, "06_timeline.png"), g6, width = 12, height = 5, dpi = 120)
cat("[Chart 6] Saved\n")

# ── Chart 7: Regime distribution (γ3 결과 inherit) ──────────
regime_dt <- data.table(
  Regime = c("Bull (low risk)", "Sideways", "Bear (high risk)"),
  N_OOS = c(775, 870, 846),
  PR_AUC = c(0.5435, 0.4946, 0.4165),
  Color = c("#06D6A0", "#FFD166", "#EF476F")
)
regime_dt[, Regime := factor(Regime, levels = Regime)]
g7 <- ggplot(regime_dt, aes(x = Regime, y = PR_AUC, fill = Color)) +
  geom_bar(stat = "identity", width = 0.6) +
  geom_text(aes(label = sprintf("PR-AUC %.4f\nN=%d", PR_AUC, N_OOS)),
            vjust = -0.2, size = 4) +
  scale_fill_identity() +
  labs(title = "Chart 7 — Regime-Conditional Performance (Macro_Risk_Score split)",
       subtitle = "Bull regime best (model strongest in calm periods)",
       x = NULL, y = "OOS PR-AUC per regime") +
  scale_y_continuous(limits = c(0, 0.65), expand = c(0, 0)) +
  theme_qvest +
  theme(legend.position = "none")
ggsave(file.path(OUT_DIR, "07_regime.png"), g7, width = 9, height = 5, dpi = 120)
cat("[Chart 7] Saved\n")

cat("\n=== All 7 charts saved to:", OUT_DIR, "===\n")
