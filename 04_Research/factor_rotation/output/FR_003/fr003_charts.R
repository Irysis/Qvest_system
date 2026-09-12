#!/usr/bin/env Rscript
suppressPackageStartupMessages({ library(data.table); library(ggplot2); library(patchwork) })
PROJ <- Sys.getenv("CLAUDE_PROJECT_DIR", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
OUT  <- file.path(PROJ, "04_Research/factor_rotation/output"); DIR <- file.path(OUT, "FR_003")
source(file.path(PROJ, "02_Infrastructure/telegram/tg_chart_pack.R"))
bt <- readRDS(file.path(OUT, "FR_003_bt_result.rds"))
p_std <- tg_chart_pack_from_bt(bt, out_dir = DIR,
  metrics_note = "FR_003 · essence Grade C · PORT_t 0.853 · Calmar 0.40 · oos_ret -0.521 (계약 산출)")
cat("std:", paste(p_std, collapse=" | "), "\n")

## ── 커스텀 ①: MC3 — 방어형 편입분의 국면별 비중이 가설과 반대로 간다 ───────────────
D <- fread(file.path(DIR, "FR_003_dispatch_diag.csv"))
S <- D[, .(w_def = mean(w_defensive), share = mean(n_defensive_avail/n_avail), n = .N), by = regime]
S <- S[order(-n)][n >= 2]
S[, regime := factor(regime, levels = c("RISK_ON","NEUTRAL","CAUTION","CRISIS","RISK_OFF"))]
M <- melt(S[, .(regime, `방어형 합산비중` = w_def, `풀 내 방어형 두수비중` = share)], id.vars="regime")
g1 <- ggplot(M, aes(regime, value, fill = variable)) +
  geom_col(position = position_dodge(width=.7), width=.6) +
  geom_text(aes(label = sprintf("%.3f", value)), position = position_dodge(width=.7),
            vjust = -0.4, size = 3) +
  scale_fill_manual(values = c("#2c6fbb", "#b8c6d9")) +
  labs(title = "MC3 — 방어형 비중이 위기에서 오히려 낮다 (가설과 반대)",
       subtitle = "두 막대가 사실상 겹친다 = 배분규칙이 방어형 축을 전혀 싣지 않는다 (r = 0.9997)",
       x = NULL, y = "비중", fill = NULL) +
  theme_minimal(base_size = 11) + theme(legend.position = "top")

## ── 커스텀 ②: 벤치 심도 구간별 초과수익 — 방어형 97개를 넣었더니 방어가 약해졌다 ──
g <- function(a){ b <- readRDS(file.path(OUT, paste0(a,"_bt_result.rds")))
  pr <- as.data.table(b$period_returns)[,.(date, r=ret_net)]
  br <- as.data.table(b$benchmark_returns)[,.(date, bm=benchmark_ret)]
  m <- merge(pr, br, by="date"); m[, act := r - bm]; m[, arm := a]; m }
A <- rbind(g("FR_003_armC_flooronly"), g("FR_003"))
A[, bucket := cut(bm, breaks=c(-Inf,-0.10,-0.05,0,Inf),
                  labels=c("벤치 ≤ -10%","-10%~-5%","-5%~0%","벤치 ≥ 0%"))]
B <- A[, .(excess = 100*mean(act), n = .N), by=.(bucket, arm)]
B[, arm := factor(arm, levels=c("FR_003_armC_flooronly","FR_003"),
                  labels=c("대조 arm_C (18모듈)","처치 arm_T (115모듈·방어형 97)"))]
g2 <- ggplot(B, aes(bucket, excess, group=arm, color=arm)) +
  geom_hline(yintercept=0, color="grey60") +
  geom_line(linewidth=1) + geom_point(size=3) +
  geom_text(aes(label=sprintf("%+.2f", excess)), vjust=-0.9, size=3, show.legend=FALSE) +
  scale_color_manual(values=c("#1a7f37","#cc3311")) +
  labs(title="심도별 월평균 초과수익 — 방어형을 넣을수록 깊은 하락에서 방어가 약해진다",
       subtitle="벤치 -10% 이하 6개월: 대조 +5.63%/월 → 처치 +3.82%/월 (계약 period_returns 진단)",
       x=NULL, y="월평균 초과수익 (%)", color=NULL) +
  theme_minimal(base_size=11) + theme(legend.position="top")

p <- g1 / g2
ggsave(file.path(DIR, "FR_003_mc3_defensive_inversion.png"), p, width=9, height=8.5, dpi=140)
cat("custom:", file.path(DIR, "FR_003_mc3_defensive_inversion.png"), "\n")
