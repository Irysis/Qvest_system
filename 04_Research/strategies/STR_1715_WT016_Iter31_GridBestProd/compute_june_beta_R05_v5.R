## 생산 run_layer5_R05_overlay.R lines 150-250 그대로 — 6월(realized_ym 2026-06) β_R05_V5 산출
## sig_date 2026-05-01 (→ realized_ym 2026-06). V5=regime_x_R05 (실제 admit variant).
suppressPackageStartupMessages({library(data.table); library(arrow); library(lubridate)})
B <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"

asp <- as.data.table(read_parquet(file.path(B,"stage_artifacts/WT_D20260425_010/alpha_scores.parquet")))
r05 <- as.data.table(read_parquet(file.path(B,"stage_artifacts/WT_D20260512_003/alpha_scores_new.parquet")))
asp[, Date := as.Date(Date)]; r05[, Date := as.Date(Date)]
cat("asp range:", as.character(max(asp$Date)), "| r05 range:", as.character(max(r05$Date)), "\n")

# 생산 동일: merge R05_Z onto admit lineage, top20 by score_eff per Date
m <- merge(asp[, .(Date, Ticker, score_eff, regime_state)],
           r05[, .(Date, Ticker, R05_Tail_Risk_Z)], by=c("Date","Ticker"), all.x=TRUE)
m_valid <- m[!is.na(score_eff)]; setorder(m_valid, Date, -score_eff)
top20 <- m_valid[, head(.SD, 20), by=Date]
p_r05 <- top20[, .(R05_z_avg_top20=mean(R05_Tail_Risk_Z, na.rm=TRUE),
                   n_R05_valid=sum(!is.na(R05_Tail_Risk_Z)), regime=regime_state[1]), by=Date]
setorder(p_r05, Date); p_r05[, realized_ym := format(Date %m+% months(1), "%Y-%m")]

# 생산 동일: expanding past-only q20/q50 (sig_date t에서 t 이전만)
expanding_quantile <- function(x, dates, q=0.2) {
  out <- rep(NA_real_, length(x))
  for (i in seq_along(x)) { past <- x[dates < dates[i]]; past <- past[!is.na(past)]
    if (length(past) >= 12) out[i] <- as.numeric(quantile(past, q, na.rm=TRUE)) }
  out
}
p_r05[, R05_q20_past := expanding_quantile(R05_z_avg_top20, Date, 0.20)]
p_r05[, R05_q50_past := expanding_quantile(R05_z_avg_top20, Date, 0.50)]

# 생산 동일: V5 = regime_x_R05 interaction
p_r05[, beta_R05_V5 := fcase(
  regime=="CRISIS"  & R05_z_avg_top20 < R05_q20_past, 0.3,
  regime=="CRISIS",  0.5,
  regime=="CAUTION" & R05_z_avg_top20 < R05_q20_past, 0.5,
  regime=="CAUTION", 0.7,
  regime %in% c("BULL","NORMAL") & R05_z_avg_top20 < R05_q20_past, 0.85,
  default = 1.0)]

cat("\n=== 최근 5개 sig_date → realized_ym, regime, R05_z vs q20, β_R05_V5 ===\n")
print(tail(p_r05[, .(Date, realized_ym, regime, R05_z=round(R05_z_avg_top20,4),
                     q20=round(R05_q20_past,4), z_lt_q20=R05_z_avg_top20<R05_q20_past,
                     beta_R05_V5)], 5))
june <- p_r05[realized_ym=="2026-06"]
cat(sprintf("\n>>> 6월(realized_ym 2026-06, sig_date %s): regime=%s | R05_z=%.4f %s q20=%.4f → β_R05_V5=%.2f <<<\n",
   if(nrow(june)) as.character(june$Date) else "NA", if(nrow(june)) june$regime else "NA",
   if(nrow(june)) june$R05_z_avg_top20 else NA,
   if(nrow(june)&&!is.na(june$R05_q20_past)&&june$R05_z_avg_top20<june$R05_q20_past) "<" else ">=",
   if(nrow(june)) june$R05_q20_past else NA, if(nrow(june)) june$beta_R05_V5 else NA))
