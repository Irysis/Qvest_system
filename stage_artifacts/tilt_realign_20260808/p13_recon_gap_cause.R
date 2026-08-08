# p13_recon_gap_cause.R — 재현 갭 원인 특정: invested = ? × β_R05
# p12 에서 (regime, z) 로만 만든 β_hat 이 실제 invested 를 77.3% 만 재현.
# 불일치는 전부 NORMAL 라벨인데 실제 노출이 0.62~0.78 — 제3 성분(m4 BOCPD 연속가중) 가설 검정.
suppressMessages({ library(data.table); library(arrow) })
options(scipen=999)
setwd(Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
V <- fread("stage_artifacts/tilt_realign_20260808/p12_beta_recon_detail.csv")
V[, eval_date := as.Date(eval_date)]
m4p <- "qepm/mailbox/worktask/WT-D20260430_001/stage_artifacts/alpha_scores.parquet"
stopifnot(file.exists(m4p))
m4 <- as.data.table(read_parquet(m4p)); m4[, Date := as.Date(Date)]
cat(sprintf("[m4] %d행 %s~%s | weight_str1715 분포: min %.3f 중앙 %.3f max %.3f | <1 인 달 %d (%.1f%%)\n",
  nrow(m4), min(m4$Date), max(m4$Date), min(m4$weight_str1715, na.rm=TRUE),
  median(m4$weight_str1715, na.rm=TRUE), max(m4$weight_str1715, na.rm=TRUE),
  sum(m4$weight_str1715 < 0.999, na.rm=TRUE), 100*mean(m4$weight_str1715 < 0.999, na.rm=TRUE)))

# 결정월 기준 m4 (decision_date = eval_date 의 전월 1일 — p12 의 V 는 eval_date 만 보유)
V[, decision_ym := format(seq(eval_date[1], by="month", length.out=1), "%Y-%m")]  # placeholder
dec <- as.Date(cut(V$eval_date, "month")) - 1
V[, dec_month := as.Date(cut(as.Date(cut(eval_date,"month")) - 1, "month"))]
m4[, ym := format(Date, "%Y-%m")]
V[, ym := format(dec_month, "%Y-%m")]
mm <- m4[, .(m4w = weight_str1715[which.max(Date)]), by=ym]
V2 <- merge(V, mm, by="ym", all.x=TRUE)
V2 <- V2[is.finite(m4w)]
cat(sprintf("\n[매칭] %d/%d 개월에 m4 값 존재\n", nrow(V2), nrow(V)))
V2[, recon_full := m4w * beta_hat]
cat(sprintf("[재현 A: β만]      일치 %.1f%% | max|diff| %.4f | cor %.4f\n",
  100*mean(abs(V2$invested - V2$beta_hat) < 1e-6), max(abs(V2$invested - V2$beta_hat)),
  suppressWarnings(cor(V2$invested, V2$beta_hat))))
cat(sprintf("[재현 B: m4 × β]   일치 %.1f%% | max|diff| %.4f | cor %.4f\n",
  100*mean(abs(V2$invested - V2$recon_full) < 1e-6), max(abs(V2$invested - V2$recon_full)),
  suppressWarnings(cor(V2$invested, V2$recon_full))))
cat("\n[개선 확인 — p12 불일치 상위 월]\n")
print(V2[abs(invested-beta_hat) > 0.05][order(-abs(invested-beta_hat))][1:6,
  .(ym=format(eval_date,"%Y-%m"), regime, m4w=round(m4w,3), beta=round(beta_hat,3),
    recon_full=round(recon_full,3), actual=round(invested,3), 잔차=round(invested-recon_full,3))])
cat(sprintf("\n[판정] m4 연속가중을 넣으면 재현이 %s (cor %.4f → %.4f)\n",
  ifelse(cor(V2$invested,V2$recon_full) > cor(V2$invested,V2$beta_hat), "개선", "미개선"),
  cor(V2$invested,V2$beta_hat), cor(V2$invested,V2$recon_full)))
cat(sprintf("[함의] m4 가 %.1f%% 의 달에서 <1 → overlay 는 2성분(라벨×z)이 아니라 **3성분(m4 × 라벨 × z)**.\n",
  100*mean(V2$m4w < 0.999)))
