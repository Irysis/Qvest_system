#==============================================================================
# Optimizer Charts — WT-D20260426_008
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
  library(ggplot2)
})

PROJECT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_ID   <- "WT-D20260426_008"
WT_DIR  <- file.path(PROJECT, "qepm/mailbox/worktask", WT_ID)
SA_DIR  <- file.path(PROJECT, "stage_artifacts", "WT_D20260426_008")
setwd(PROJECT)

ws <- readRDS(file.path(SA_DIR, "optimizer_workspace.rds"))
mm <- ws$method_metrics
selected <- ws$selected

# Method comparison bar chart (net_IR)
mc_dt <- rbindlist(lapply(mm, function(m) {
  data.table(Method = m$method, netIR = m$net_ir, MDD = m$mdd %||% NA,
             TO = m$turnover_ann %||% NA, CVaR = m$cvar_d_5 %||% NA,
             pass_TO = m$pass_to_cap %||% FALSE,
             pass_CV = m$pass_cvar_cap %||% FALSE,
             pass_MDD = m$pass_mdd_cap %||% FALSE)
}))
`%||%` <- function(a, b) if (is.null(a) || (length(a) == 1 && is.na(a))) b else a
mc_dt <- mc_dt[!is.na(netIR)]
mc_dt[, sel := Method == selected]
setorder(mc_dt, -netIR)

p1 <- ggplot(mc_dt, aes(x = reorder(Method, netIR), y = netIR, fill = sel)) +
  geom_col() +
  geom_text(aes(label = sprintf("%.3f", netIR)), hjust = -0.1, size = 3) +
  scale_fill_manual(values = c("TRUE" = "#E63946", "FALSE" = "#7FB069"), guide = "none") +
  coord_flip() +
  labs(title = sprintf("WT-%s — Method Comparison (net_IR)", WT_ID),
       subtitle = sprintf("Selected: %s (10 methods evaluated, hierarchical selection)", selected),
       x = NULL, y = "net_IR (annualized)") +
  ylim(0, max(mc_dt$netIR, na.rm = TRUE) * 1.15) +
  theme_minimal(base_size = 11)

ggsave(file.path(WT_DIR, "method_comparison.png"), p1,
       width = 9, height = 5, dpi = 110)
cat("method_comparison.png saved\n")

# Cap PASS heatmap
cap_long <- melt(mc_dt[, .(Method, pass_TO, pass_CV, pass_MDD)],
                  id.vars = "Method", variable.name = "Cap", value.name = "Pass")
cap_long[, Cap := factor(Cap, levels = c("pass_TO", "pass_CV", "pass_MDD"),
                          labels = c("TO≤6.0", "CVaR≤2.5%", "MDD≤45%"))]
cap_long[, Method := factor(Method, levels = mc_dt[order(netIR)]$Method)]

p2 <- ggplot(cap_long, aes(x = Cap, y = Method, fill = Pass)) +
  geom_tile(color = "white", size = 0.6) +
  scale_fill_manual(values = c("TRUE" = "#7FB069", "FALSE" = "#E63946"),
                    labels = c("FAIL", "PASS")) +
  labs(title = sprintf("WT-%s — Hard Cap PASS Matrix", WT_ID),
       subtitle = "Selection rule: max(net_IR) ∧ pass_TO ∧ pass_MDD (CVaR mandate structurally infeasible)",
       x = NULL, y = NULL, fill = NULL) +
  theme_minimal(base_size = 11)

ggsave(file.path(WT_DIR, "cap_pass_matrix.png"), p2,
       width = 8, height = 5, dpi = 110)
cat("cap_pass_matrix.png saved\n")

# Weights distribution (selected method, last sig_date)
weights_dt <- fread(file.path(WT_DIR, "weights.csv"))
last_d <- max(weights_dt$Date)
last_w <- weights_dt[Date == last_d][order(-Weight)]

p3 <- ggplot(last_w, aes(x = reorder(Ticker, Weight), y = Weight)) +
  geom_col(fill = "#264653") +
  geom_hline(yintercept = 0.05, color = "#7FB069", linetype = "dashed") +
  geom_hline(yintercept = 0.20, color = "#E63946", linetype = "dashed") +
  coord_flip() +
  labs(title = sprintf("WT-%s — %s Weights at %s", WT_ID, selected, last_d),
       subtitle = "Dashed: green=EW (0.05), red=hard cap (0.20)",
       x = NULL, y = "Weight") +
  theme_minimal(base_size = 10)

ggsave(file.path(WT_DIR, "selected_weights_lastdate.png"), p3,
       width = 8, height = 6, dpi = 110)
cat("selected_weights_lastdate.png saved\n")
