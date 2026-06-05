cat("=== STR_1551 S5: Defense Sleeve Mutations + 2-Sleeve Portfolio Test ===\n")
options(scipen=999); Sys.setenv(TZ="Asia/Seoul"); set.seed(1551)
SCRIPT_DIR <- tryCatch(dirname(sys.frame(1)$ofile), error=function(e) getwd())
INFRA_DIR <- file.path(SCRIPT_DIR, "..", "..", "..", "02_Infrastructure")
if (!file.exists(file.path(INFRA_DIR, "config.R")))
  INFRA_DIR <- file.path(Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot")), "02_Infrastructure")
source(file.path(INFRA_DIR, "config.R"))
source(file.path(INFRA_DIR, "backtest_harness.R"))
library(data.table); library(xts); library(arrow); library(dplyr)

res <- load_rawdata(use_cache=TRUE)
RAWDATA <- res$RAWDATA; BM_DT <- res$BM_DT; RAWDATA_ORIG <- copy(RAWDATA)
rm(res); gc(verbose=FALSE)

sim_parent <- readRDS(file.path(SCRIPT_DIR, "sim_result.rds"))

run_overlay <- function(exp_vec, name, dir_name) {
  rr <- as.numeric(sim_parent$strategy_xts); rr[is.na(rr)] <- 0
  rd <- as.Date(index(sim_parent$strategy_xts))
  fr <- rr * exp_vec
  cx <- xts(fr, order.by=rd); names(cx) <- "Strategy"
  sim2 <- sim_parent; sim2$strategy_xts <- cx
  od <- file.path(SCRIPT_DIR, dir_name); dir.create(od, showWarnings=F, recursive=T)
  p <- summarise_perf(cx, name)
  cat(sprintf("  %s: SR=%.3f CAGR=%.2f%% MDD=%.1f%%\n", name, p$Sharpe, p$CAGR, p$MDD))
  generate_charts(sim2, output_dir=od, strategy_name=name)
  fwrite(rbind(p, summarise_perf(sim2$bm_xts, "BM")), file.path(od, "performance.csv"))
  saveRDS(sim2, file.path(od, "sim_result.rds"))
  source(file.path(INFRA_DIR, "hurdle_gate.R"))
  h <- run_hurdle_gate(sim_result=sim2, strategy_name=name, output_dir=od)
  jsonlite::write_json(h, file.path(od, "hurdle_result.json"), auto_unbox=T, pretty=T)
  list(perf=p, hurdle=h)
}

AR <- list()

# M1: DD 12/30 gentle (SR 0.449 → gentle DD)
cat("\n--- M1: DD 12/30 gentle ---\n")
rr <- as.numeric(sim_parent$strategy_xts); rr[is.na(rr)] <- 0; nf <- length(rr)
nav <- cumprod(1+rr); dd <- 1-nav/cummax(nav); dd_lag <- c(0, dd[-nf])
dd_exp_gentle <- fifelse(dd_lag<=0.12, 1, fifelse(dd_lag>=0.30, 0.30, pmax(0.30, 1-(dd_lag-0.12)/(0.30-0.12)*0.70)))
r <- run_overlay(dd_exp_gentle, "M1_DD12_30", "output_s5_M1"); if(!is.null(r)) AR[["M1"]] <- r

# M2: DD 8/22 tight
cat("\n--- M2: DD 8/22 tight ---\n")
dd_exp_tight <- fifelse(dd_lag<=0.08, 1, fifelse(dd_lag>=0.22, 0.30, pmax(0.30, 1-(dd_lag-0.08)/(0.22-0.08)*0.70)))
r <- run_overlay(dd_exp_tight, "M2_DD8_22", "output_s5_M2"); if(!is.null(r)) AR[["M2"]] <- r

# M3: Regime v7.1 only
cat("\n--- M3: Regime only ---\n")
tryCatch({
  source(file.path(REGIME_DIR, "regime_signal.R"))
  sdt <- load_regime_signal()
  rd <- as.Date(index(sim_parent$strategy_xts))
  cp <- numeric(nf)
  for(j in seq_len(nf)) { row <- sdt[Date<=rd[j]]; if(nrow(row)>0) cp[j] <- tail(row$Cash_Pct,1) else cp[j] <- 0 }
  cl <- c(0, cp[-nf]); re <- 1 - cl
  r <- run_overlay(re, "M3_Regime", "output_s5_M3"); if(!is.null(r)) AR[["M3"]] <- r
}, error=function(e) cat("M3 ERR:", e$message, "\n"))

# M4: DD 12/30 + Regime
cat("\n--- M4: DD 12/30 + Regime ---\n")
tryCatch({
  r <- run_overlay(dd_exp_gentle * re, "M4_DD12_30_Regime", "output_s5_M4"); if(!is.null(r)) AR[["M4"]] <- r
}, error=function(e) cat("M4 ERR:", e$message, "\n"))

# M5: DD 8/22 + Regime
cat("\n--- M5: DD 8/22 + Regime ---\n")
tryCatch({
  r <- run_overlay(dd_exp_tight * re, "M5_DD8_22_Regime", "output_s5_M5"); if(!is.null(r)) AR[["M5"]] <- r
}, error=function(e) cat("M5 ERR:", e$message, "\n"))

# ===== 2-SLEEVE PORTFOLIO TEST =====
cat("\n\n========================================\n")
cat("  2-Sleeve Portfolio: Core(50%) + Defense(50%)\n")
cat("========================================\n\n")

# Load Core Alpha sim (STR_1550 M4 DD 8/22)
core_sim_path <- file.path(dirname(SCRIPT_DIR), "STR_1550_consensus_core_alpha", "output_s5_M4", "sim_result.rds")
if (!file.exists(core_sim_path)) {
  cat("Core sim not found at:", core_sim_path, "\n")
  core_sim_path <- file.path(dirname(SCRIPT_DIR), "STR_1550_consensus_core_alpha", "sim_result.rds")
}

if (file.exists(core_sim_path)) {
  core_sim <- readRDS(core_sim_path)

  # Best defense variants to combine
  for (def_var in c("M1", "M2", "M4", "M5")) {
    def_sim_path <- file.path(SCRIPT_DIR, paste0("output_s5_", def_var), "sim_result.rds")
    if (!file.exists(def_sim_path)) next

    def_sim <- readRDS(def_sim_path)

    # Align dates
    common_dates <- intersect(as.Date(index(core_sim$strategy_xts)), as.Date(index(def_sim$strategy_xts)))
    common_dates <- sort(as.Date(common_dates))

    core_ret <- as.numeric(core_sim$strategy_xts[as.character(common_dates)])
    def_ret <- as.numeric(def_sim$strategy_xts[as.character(common_dates)])
    core_ret[is.na(core_ret)] <- 0; def_ret[is.na(def_ret)] <- 0

    # 50/50 blend
    port_ret <- 0.5 * core_ret + 0.5 * def_ret
    port_xts <- xts(port_ret, order.by=common_dates); names(port_xts) <- "Portfolio"

    port_nav <- cumprod(1 + port_ret)
    port_mdd <- max(1 - port_nav / cummax(port_nav))
    port_sr <- mean(port_ret) / sd(port_ret) * sqrt(252)
    port_cagr <- (tail(port_nav,1))^(252/length(port_ret)) - 1

    # Correlation
    cor_val <- cor(core_ret, def_ret, use="complete.obs")

    cat(sprintf("  Core(50%%) + Defense_%s(50%%): SR=%.3f CAGR=%.2f%% MDD=%.1f%% Corr=%.3f\n",
                def_var, port_sr, port_cagr*100, port_mdd*100, cor_val))

    # Save best 2-sleeve
    od2 <- file.path(SCRIPT_DIR, paste0("output_2sleeve_Core_Def", def_var))
    dir.create(od2, showWarnings=F)
    sim_2s <- list(strategy_xts=port_xts, bm_xts=core_sim$bm_xts[as.character(common_dates)])
    p2 <- summarise_perf(port_xts, paste0("2Sleeve_Core_Def", def_var))
    fwrite(rbind(p2, summarise_perf(sim_2s$bm_xts, "BM")), file.path(od2, "performance.csv"))
    saveRDS(sim_2s, file.path(od2, "sim_result.rds"))
    generate_charts(sim_2s, output_dir=od2, strategy_name=paste0("2Sleeve_", def_var))
  }
} else {
  cat("Core sim (STR_1550 M4) not found. Skipping 2-sleeve test.\n")
}

# Summary
cat("\n\n=== STR_1551 S5 SUMMARY ===\n")
cat(sprintf("%-6s|%-6s|%7s|%8s|%7s\n","Mut","Grade","SR","CAGR%","MDD%"))
cat(sprintf("%-6s|%-6s|%7.3f|%8.2f|%7.1f\n","Base","C",0.449,7.38,53.69))
for(mn in c("M1","M2","M3","M4","M5")) {
  if(mn %in% names(AR)) {
    r <- AR[[mn]]
    g <- r$hurdle$grade %||% r$hurdle$verdict$grade %||% "?"
    cat(sprintf("%-6s|%-6s|%7.3f|%8.2f|%7.1f\n", mn, g, r$perf$Sharpe, r$perf$CAGR, r$perf$MDD))
  }
}
cat("\n=== COMPLETE ===\n")
