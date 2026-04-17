suppressPackageStartupMessages({
  library(data.table); library(arrow); library(ggplot2); library(patchwork)
})
source("02_Infrastructure/config.R")
source("02_Infrastructure/backtest_harness.R")
source("02_Infrastructure/telegram_notify.R")

cat("=== Regime v1 vs v2: MDD + Benchmark ===\n")

regime <- as.data.table(read_parquet(FRED_REGIME_CACHE))
setorder(regime, Date)

res <- load_rawdata(use_cache = TRUE)
bm <- unique(res$BM_DT[, .(Date, BM_Ret)])
setorder(bm, Date)
bm[, YM := format(Date, "%Y-%m")]
bm_m <- bm[, .(BM_Ret = prod(1 + BM_Ret, na.rm=TRUE) - 1), by = YM]
bm_m[, Date := as.Date(cut(as.Date(paste0(YM,"-01")) + 31, "month")) - 1]
setorder(bm_m, Date)

# v1 scores
regime[, v1 := 0L]
if ("VIX_Regime" %in% names(regime))
  regime[, v1 := v1 + fifelse(!is.na(VIX_Regime) & VIX_Regime=="crisis", 30L,
    fifelse(!is.na(VIX_Regime) & VIX_Regime=="elevated", 15L, 0L))]
if ("YC_Inversion" %in% names(regime))
  regime[, v1 := v1 + fifelse(!is.na(YC_Inversion) & YC_Inversion, 25L, 0L)]
if ("Credit_Stress" %in% names(regime))
  regime[, v1 := v1 + fifelse(!is.na(Credit_Stress) & Credit_Stress, 25L, 0L)]
if ("KRW_Stress" %in% names(regime))
  regime[, v1 := v1 + fifelse(!is.na(KRW_Stress) & KRW_Stress, 20L, 0L)]
regime[, v2 := Macro_Risk_Score]

dt <- merge(regime[, .(Date, v1, v2)], bm_m[, .(Date, BM_Ret)], by="Date")
dt <- dt[!is.na(BM_Ret)]
setorder(dt, Date)

# Exposure
dt[, exp_v1 := fifelse(v1>=30, 0, fifelse(v1>=15, 0.5, 1.0))]
dt[, exp_v2 := fifelse(v2>=30, 0, fifelse(v2>=15, 0.5, 1.0))]

dt[, r_bm := BM_Ret]
dt[, r_v1 := BM_Ret * exp_v1]
dt[, r_v2 := BM_Ret * exp_v2]

dt[, c_bm := cumprod(1+r_bm)]
dt[, c_v1 := cumprod(1+r_v1)]
dt[, c_v2 := cumprod(1+r_v2)]

dd <- function(x) x / cummax(x) - 1
dt[, d_bm := dd(c_bm)]
dt[, d_v1 := dd(c_v1)]
dt[, d_v2 := dd(c_v2)]

# Stats
perf <- function(r, nm) {
  n <- length(r); cagr <- prod(1+r)^(12/n)-1; vol <- sd(r)*sqrt(12)
  data.table(Name=nm, CAGR=cagr, Vol=vol, SR=cagr/vol, MDD=min(dd(cumprod(1+r))))
}
st <- rbindlist(list(perf(dt$r_bm,"KOSPI200"), perf(dt$r_v1,"v1(4축)"), perf(dt$r_v2,"v2(9축)")))
cat("\n"); print(st[, .(Name, CAGR=sprintf("%.1f%%",CAGR*100), Vol=sprintf("%.1f%%",Vol*100),
  SR=sprintf("%.3f",SR), MDD=sprintf("%.1f%%",MDD*100))])

# Prediction: score vs next month loss
dt[, next_r := shift(BM_Ret, -1)]
cor1 <- cor(dt$v1, -dt$next_r, use="complete.obs")
cor2 <- cor(dt$v2, -dt$next_r, use="complete.obs")
cat(sprintf("\nMDD Prediction (score ~ -next_ret): v1=%.3f v2=%.3f\n", cor1, cor2))

# ── Charts ──
out <- file.path(PROJECT_ROOT, "research_output", "regime_analysis")
dir.create(out, showWarnings=FALSE, recursive=TRUE)

thm <- theme_minimal(base_size=11) + theme(legend.position="bottom",
  plot.title=element_text(face="bold",size=13))

# Panel 1: Cumulative
pd1 <- melt(dt[,.(Date,KOSPI200=c_bm,`v1(4축)`=c_v1,`v2(9축)`=c_v2)],
  id="Date", variable.name="Model", value.name="Growth")
p1 <- ggplot(pd1, aes(Date, Growth, color=Model)) + geom_line(linewidth=0.7) +
  scale_color_manual(values=c("gray50","#E74C3C","#2E86C1")) +
  scale_y_log10(labels=scales::comma) +
  labs(title="Cumulative Growth (log scale)", y="Growth of 1", x=NULL) + thm

# Panel 2: Drawdown
pd2 <- melt(dt[,.(Date,KOSPI200=d_bm*100,`v1(4축)`=d_v1*100,`v2(9축)`=d_v2*100)],
  id="Date", variable.name="Model", value.name="DD")
p2 <- ggplot(pd2, aes(Date, DD, color=Model)) + geom_line(linewidth=0.5) +
  scale_color_manual(values=c("gray50","#E74C3C","#2E86C1")) +
  geom_hline(yintercept=-25, linetype="dashed", alpha=0.3) +
  labs(title="Drawdown (%)", y="DD%", x=NULL) + thm

# Panel 3: Risk Score comparison
pd3 <- melt(dt[,.(Date,`v1(4축)`=v1,`v2(9축)`=v2)],
  id="Date", variable.name="Version", value.name="Score")
p3 <- ggplot(pd3, aes(Date, Score, color=Version)) + geom_line(linewidth=0.5, alpha=0.7) +
  scale_color_manual(values=c("#E74C3C","#2E86C1")) +
  geom_hline(yintercept=c(15,30,70), linetype="dashed", alpha=0.3,
    color=c("orange","red","darkred")) +
  annotate("text", x=min(dt$Date)+400, y=c(17,32,72),
    label=c("HALF","SKIP","BUDDHA"), size=3, color=c("orange","red","darkred")) +
  labs(title="Macro Risk Score", y="Score", x=NULL) + thm

# Panel 4: Score vs next month return scatter
pd4 <- dt[!is.na(next_r), .(v1, v2, next_r)]
pd4m <- melt(pd4, id="next_r", variable.name="Version", value.name="Score")
pd4m[, Version := factor(Version, levels=c("v1","v2"), labels=c("v1(4축)","v2(9축)"))]
p4 <- ggplot(pd4m, aes(Score, next_r*100, color=Version)) +
  geom_point(alpha=0.3, size=1) +
  geom_smooth(method="lm", se=FALSE, linewidth=0.8) +
  scale_color_manual(values=c("#E74C3C","#2E86C1")) +
  geom_hline(yintercept=0, alpha=0.3) +
  labs(title=sprintf("MDD Prediction: Score vs Next Month Return (cor: v1=%.3f, v2=%.3f)", cor1, cor2),
       x="Risk Score", y="Next Month Return (%)") + thm

combined <- (p1 | p4) / p2 / p3 +
  plot_annotation(
    title="Regime Engine v1(4-axis) vs v2(9-axis) — KOSPI200 Benchmark",
    subtitle=sprintf("v1: CAGR %.1f%% SR %.3f MDD %.1f%% | v2: CAGR %.1f%% SR %.3f MDD %.1f%% | BM: CAGR %.1f%% MDD %.1f%%",
      st[2]$CAGR*100, st[2]$SR, st[2]$MDD*100,
      st[3]$CAGR*100, st[3]$SR, st[3]$MDD*100,
      st[1]$CAGR*100, st[1]$MDD*100),
    theme=theme(plot.title=element_text(face="bold",size=14))
  )

chart_path <- file.path(out, "regime_v1_vs_v2_mdd.png")
ggsave(chart_path, combined, width=14, height=11, dpi=150, bg="white")
cat(sprintf("\nChart: %s\n", chart_path))

tryCatch({
  tg_send_photo(chart_path, caption=paste0(
    "\xF0\x9F\x93\x8A Regime v1\xe2\x86\x92v2 MDD Benchmark\n\n",
    sprintf("KOSPI200: CAGR %.1f%% MDD %.1f%%\n", st[1]$CAGR*100, st[1]$MDD*100),
    sprintf("v1(4\xec\xb6\x95): CAGR %.1f%% SR %.3f MDD %.1f%%\n", st[2]$CAGR*100, st[2]$SR, st[2]$MDD*100),
    sprintf("v2(9\xec\xb6\x95): CAGR %.1f%% SR %.3f MDD %.1f%%\n\n", st[3]$CAGR*100, st[3]$SR, st[3]$MDD*100),
    sprintf("MDD Prediction cor: v1=%.3f v2=%.3f\n", cor1, cor2),
    sprintf("MDD Improvement: %.1f%%p", (st[3]$MDD - st[2]$MDD)*100)
  ))
  cat("TG sent!\n")
}, error=function(e) cat("TG error:", e$message, "\n"))
cat("=== Done ===\n")
