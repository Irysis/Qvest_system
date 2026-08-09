## ============================================================================
## FQ-165 P0b — 두 패널의 시간축 정렬을 **가정하지 않고 실측**한다.
## base panel Date = 월초(decision), M26 panel Date = 월말(signal). 정확 일치 0건이므로
## ym 오프셋을 후보로 놓고 (a) 종목집합 겹침 (b) Ret_1m 일치 로 정렬을 특정한다.
## ★"그럴듯한 오프셋"을 고르지 않는다 — Ret_1m 완전 일치(cor≈1)가 유일 판별 기준.
## ============================================================================
suppressMessages({library(data.table); library(arrow); library(jsonlite)})
options(scipen = 999)
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- "stage_artifacts/FQ165_m26_book_marginal"
P <- readRDS(file.path(OUT, "p0_inputs.rds"))
ap <- P$ap; m26 <- P$m26

ym <- function(d) as.integer(format(d, "%Y")) * 12L + as.integer(format(d, "%m"))
ap[,  ymi := ym(Date)]
m26[, ymi := ym(Date)]

cat("=== [B1] ym 오프셋 스캔: base(ymi) = m26(ymi) + k ===\n")
res <- rbindlist(lapply(-2:2, function(k) {
  mm <- copy(m26)[, ymi_j := ymi + k]
  j <- merge(ap[!is.na(score_eff), .(ymi, Ticker, ret_base = Ret_1m, score_eff)],
             mm[, .(ymi_j, Ticker, ret_m26 = Ret_1m, M26 = M26_Revenue_Mom)],
             by.x = c("ymi","Ticker"), by.y = c("ymi_j","Ticker"))
  jj <- j[is.finite(ret_base) & is.finite(ret_m26)]
  data.table(k = k, n_rows = nrow(j), n_ret_pairs = nrow(jj),
             cor_ret = if (nrow(jj) > 100) cor(jj$ret_base, jj$ret_m26) else NA_real_,
             max_abs_diff = if (nrow(jj) > 0) max(abs(jj$ret_base - jj$ret_m26)) else NA_real_,
             frac_exact = if (nrow(jj) > 0) mean(abs(jj$ret_base - jj$ret_m26) < 1e-8) else NA_real_)
}))
print(res)

k_star <- res[which.max(fifelse(is.na(cor_ret), -Inf, cor_ret))]$k
cat(sprintf("\n[B1] 선택 오프셋 k=%d (cor_ret=%.6f · exact 일치 비율=%.4f)\n",
            k_star, res[k == k_star]$cor_ret, res[k == k_star]$frac_exact))
cat("     해석: base decision(월초 M) 의 forward 1M 수익 == M26 signal(월말 M-1) 의 Ret_1m 이면 k=+1.\n")

## --- B2. 정렬 확정 하 커버리지 ---
mm <- copy(m26)[, ymi_j := ymi + k_star]
cov_dt <- merge(ap[!is.na(score_eff), .N, by = ymi],
                mm[!is.na(M26_Revenue_Mom), .(n_m26 = .N), by = .(ymi = ymi_j)],
                by = "ymi", all.x = TRUE)
setorder(cov_dt, ymi)
j <- merge(ap[!is.na(score_eff), .(ymi, Date, Ticker, score_eff)],
           mm[!is.na(M26_Revenue_Mom), .(ymi = ymi_j, Ticker, M26 = M26_Revenue_Mom)],
           by = c("ymi","Ticker"))
covr <- j[, .(n_joint = .N), by = .(ymi, Date)]
covr <- merge(covr, ap[!is.na(score_eff), .(n_base = .N), by = .(ymi)], by = "ymi")
covr[, frac := n_joint / n_base]
cat(sprintf("\n[B2] 결합 커버리지: 월 %d개 · 중앙 %.3f · 5%%분위 %.3f · 최소 %.3f\n",
            nrow(covr), median(covr$frac), quantile(covr$frac, .05), min(covr$frac)))
cat(sprintf("     첫 달 %s · 마지막 달 %s\n", min(covr$Date), max(covr$Date)))
print(head(covr[order(Date)], 5)); print(tail(covr[order(Date)], 3))

## --- B3. 직교성 사전확인: 월별 cross-sectional spearman(score_eff, M26) ---
sp <- j[, .(rho = if (.N >= 20) suppressWarnings(cor(score_eff, M26, method = "spearman")) else NA_real_),
        by = .(ymi, Date)][is.finite(rho)]
cat(sprintf("\n[B3] 횡단면 spearman(score_eff, M26): 월 %d · 평균 %+.4f · 중앙 %+.4f · sd %.4f · |평균| < 0.30 : %s\n",
            nrow(sp), mean(sp$rho), median(sp$rho), sd(sp$rho), abs(mean(sp$rho)) < 0.30))

## --- B4. 상위 20 슬롯에서의 겹침 (선별면 직교성) ---
top_ov <- j[, {
  o <- order(-score_eff); tb <- Ticker[o][seq_len(min(20L, .N))]
  o2 <- order(-M26);      tm <- Ticker[o2][seq_len(min(20L, .N))]
  .(n_overlap = length(intersect(tb, tm)))
}, by = .(ymi, Date)]
cat(sprintf("[B4] top-20 base vs top-20 M26 겹침: 평균 %.2f 종목 / 20 (중앙 %.0f · 최대 %d)\n",
            mean(top_ov$n_overlap), median(top_ov$n_overlap), max(top_ov$n_overlap)))

saveRDS(list(k_star = k_star, align = res, cov = covr, spearman = sp, top_ov = top_ov, joint = j),
        file.path(OUT, "p0b_align.rds"))
fwrite(res, file.path(OUT, "p0b_offset_scan.csv"))
cat("\n[saved] p0b_align.rds / p0b_offset_scan.csv\n")
