## 09_figures.R — README 그림 · 표: 옛 판독(창 평균 부호) 대 새 판독(|t| ≥ 등록부 문턱) — 같은 as-of 재현(04 산출 replay_daily.rds)
suppressMessages({ library(data.table); library(jsonlite) })
a <- commandArgs(trailingOnly = TRUE); OUT <- a[1]; QM <- a[2]
T_SIG <- as.numeric(fromJSON(file.path(QM, "02_Infrastructure/worktask/constraint_defaults.json"))$tier_graduation[["grade_b_min_portfolio_alpha_t"]])
D <- readRDS(file.path(OUT, "replay_daily.rds"))
fac <- c(SMB = "규모(SMB)", HML = "가치(HML)", RMW = "수익성(RMW)")
yrs <- as.numeric(diff(range(D$Date))) / 365.25
CMP <- rbindlist(lapply(names(fac), function(f) {
  t <- D[[paste0("t_", f)]]; ok <- is.finite(t)
  old <- sign(D[[paste0("w_", f)]])[ok]; new <- ifelse(abs(t[ok]) >= T_SIG, sign(t[ok]), 0)
  ch <- function(x) sum(x[-1] != x[-length(x)])
  dec <- new[new != 0]
  r_new <- rle(new); r_old <- rle(old)
  data.table(factor = f,
             old_changes_per_year = round(ch(old) / yrs, 1), old_median_run_days = median(r_old$lengths),
             new_state_changes_per_year = round(ch(new) / yrs, 1), new_opposite_claims_per_year = round(ch(dec) / yrs, 2),
             new_claim_share = round(mean(new != 0), 3), new_median_claim_run_days = median(r_new$lengths[r_new$values != 0]))
}))
print(CMP); fwrite(CMP, file.path(OUT, "fig_old_vs_new_label.csv"))

png(file.path(OUT, "fig_old_vs_new_label.png"), width = 1300, height = 900)
par(mfrow = c(3, 1), mar = c(2.5, 5, 3, 1), cex.main = 1.35, cex.axis = 1.1, cex.lab = 1.15)
for (f in names(fac)) {
  t <- D[[paste0("t_", f)]]; w <- D[[paste0("w_", f)]]
  yl <- range(c(t, -4, 4), na.rm = TRUE)
  plot(D$Date, t, type = "n", ylim = yl, xlab = "", ylab = "12개월+MTD t",
       main = sprintf("%s — 옛 판독(창 평균 부호: 회색 띠 위 = +, 아래 = −) 대 새 판독(|t| ≥ %.1f 만 단정 · 굵은 선 구간)", fac[[f]], T_SIG))
  rect(min(D$Date), -T_SIG, max(D$Date), T_SIG, col = "gray92", border = NA)
  abline(h = c(-T_SIG, 0, T_SIG), lty = c(2, 3, 2), col = "gray40")
  lines(D$Date, t, col = "gray55", lwd = 1)
  dec <- ifelse(is.finite(t) & abs(t) >= T_SIG, t, NA)
  lines(D$Date, dec, col = ifelse(f == "HML", "steelblue", ifelse(f == "SMB", "firebrick", "darkgreen")), lwd = 2.6)
  ## 옛 판독이 뒤집힌 날(점) — 띠 안에서 대부분 일어난다
  fl <- which(sign(w[-1]) != sign(w[-length(w)])) + 1L
  points(D$Date[fl], t[fl], pch = 16, cex = 0.45, col = "black")
  legend("topleft", bty = "n", cex = 1.05,
         legend = c(sprintf("옛 판독 뒤집힘 %d번(점)", length(fl)), sprintf("새 판독 단정 구간(|t| ≥ %.1f)", T_SIG)),
         pch = c(16, NA), lty = c(NA, 1), lwd = c(NA, 2.6), col = c("black", "gray20"))
}
dev.off()
cat("fig_old_vs_new_label.png written\n")
