# run_04_retro_scope.R — 칩 task_972fe292 ①: z 원천 통일 시 **소급 영향 범위**
# 판정 배경(run_01/03 실측):
#   - 동결 z 와 live(factor_db) z 는 **rank 상관 0.9999+** = 같은 신호를 다른 횡단면에서 표준화한 것
#     (동결 pre-era n≈343 부분집합 / live n≈2400 전체시장). 종목 *선별*은 score_eff 로 하므로 무영향.
#   - 바뀌는 건 **top20 평균 z 의 수준** → 문턱(q20) 대비 flag 판정.
# 이 스크립트: 표본 월에서 두 원천의 top20 평균 z 와 **flag 판정 일치율**을 잰다.
#   일치율이 높으면 원천 교체의 소급 영향이 작고(교체 안전), 낮으면 북 β 역사가 바뀐다.
suppressMessages({ library(data.table); library(arrow); library(dplyr) })
options(scipen=999)
setwd(Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
source("02_Infrastructure/config.R"); source("02_Infrastructure/factor_db/factor_db_connector.R")
OUT <- "stage_artifacts/beta_z_source_20260808"
reg <- .load_registry()

asp <- as.data.table(read_parquet("stage_artifacts/WT_D20260425_010/alpha_scores.parquet")); asp[, Date := as.Date(Date)]
frz <- as.data.table(read_parquet("stage_artifacts/WT_D20260512_003/alpha_scores_new.parquet")); frz[, Date := as.Date(Date)]
P <- fread("stage_artifacts/tilt_realign_20260808/p20_flag_spec_panel.csv"); P[, Date := as.Date(Date)]

dates <- sort(unique(P[is.finite(z)]$Date))
samp <- dates[seq(1, length(dates), length.out = min(30, length(dates)))]
cat(sprintf("[표본] %d개월 (%s ~ %s)\n", length(samp), min(samp), max(samp)))

R <- rbindlist(lapply(samp, function(dd) {
  pt <- asp[Date == dd & !is.na(score_eff)]
  if (!nrow(pt)) return(NULL)
  setorder(pt, -score_eff)
  pk <- pt[seq_len(min(20L, nrow(pt)))]$Ticker
  zf <- frz[Date == dd & Ticker %in% pk & is.finite(R05_Tail_Risk_Z), mean(R05_Tail_Risk_Z)]
  f <- tryCatch(load_month_factors(dd, factor_names = "R05_Tail_Risk"), error = function(e) NULL)
  if (is.null(f) || !nrow(f)) return(NULL)
  f <- as.data.table(f)
  if (!("Z_Score" %in% names(f)) && "Z_Score_Aligned" %in% names(f)) setnames(f, "Z_Score_Aligned", "Z_Score")
  if ("Coverage" %in% names(f)) f <- f[Coverage == TRUE]
  f <- f[is.finite(Z_Score)]
  fa <- as.data.table(tryCatch(align_factor_direction(copy(f)[, sig_date := dd], reg, sig_date = dd, min_ic_months = 12L),
                               error = function(e) copy(f)))
  zc <- if ("Z_Score_Aligned" %in% names(fa)) "Z_Score_Aligned" else "Z_Score"
  zl <- mean(fa[[zc]][fa$Ticker %in% pk], na.rm = TRUE)
  data.table(Date = dd, z_frozen = zf, z_live = zl)
}), fill = TRUE)
R <- R[is.finite(z_frozen) & is.finite(z_live)]
setorder(R, Date)
cat(sprintf("[대조 성공] %d개월\n", nrow(R)))

## 각 원천의 **자체 expanding q20** 으로 flag 판정 (원천마다 단위가 다르므로 자체 분포가 정합)
expq <- function(x, p = 0.20, mn = 12L) sapply(seq_along(x), function(i) if (i <= mn) NA_real_ else quantile(x[1:(i-1)], p, names = FALSE, na.rm = TRUE))
R[, `:=`(q_frozen = expq(z_frozen), q_live = expq(z_live))]
R[, `:=`(flag_frozen = is.finite(q_frozen) & z_frozen < q_frozen,
         flag_live   = is.finite(q_live)   & z_live   < q_live)]
V <- R[is.finite(q_frozen) & is.finite(q_live)]
cat(sprintf("\n[flag 판정 일치] %d개월 중 %d 일치 (%.1f%%) | 동결 발화 %d · live 발화 %d\n",
            nrow(V), sum(V$flag_frozen == V$flag_live), 100*mean(V$flag_frozen == V$flag_live),
            sum(V$flag_frozen), sum(V$flag_live)))
cat(sprintf("[수준 대조] 동결 평균 %+.4f (sd %.4f) · live 평균 %+.4f (sd %.4f) | Pearson %.3f · Spearman %.3f\n",
            mean(V$z_frozen), sd(V$z_frozen), mean(V$z_live), sd(V$z_live),
            cor(V$z_frozen, V$z_live), cor(V$z_frozen, V$z_live, method = "spearman")))
if (nrow(V[flag_frozen != flag_live]))
  print(V[flag_frozen != flag_live, .(Date, z_frozen = round(z_frozen,4), q_frozen = round(q_frozen,4), flag_frozen,
                                      z_live = round(z_live,4), q_live = round(q_live,4), flag_live)])
cat(sprintf("\n[판정] 원천 교체 시 소급 영향 = flag 불일치 %.1f%% → %s\n",
  100*mean(V$flag_frozen != V$flag_live),
  ifelse(mean(V$flag_frozen != V$flag_live) < 0.10, "작음 — 교체가 북 역사를 크게 바꾸지 않음",
         "★큼 — 교체는 북 β 역사를 바꾸므로 도훈 판단 필요")))
fwrite(R, file.path(OUT, "retro_scope_sample.csv"))
