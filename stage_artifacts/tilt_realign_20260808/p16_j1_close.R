# p16_j1_close.R — J1 종결: 재구성 대신 원장 저장값 직접 대조
# live_book_series.csv 에 beta_R05 · m4 가 **이미 저장**돼 있다. 재현을 추정할 게 아니라
#   ① invested == beta_R05 × m4 인가 (캐리어 ↔ 원장 정합)
#   ② 저장된 beta_R05 를 (regime, z)로 **예측**할 수 있는가 (I1 이 실제로 필요한 것)
# 을 분리해서 본다. ①이 맞으면 내 재현 갭은 전부 ②의 문제로 국소화된다.
suppressMessages({ library(data.table); library(arrow) })
options(scipen=999)
setwd(Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
lb <- fread("06_Registry/live_track/STR_1715_on_M4gAE_R05_noLayer4_PG2/live_book_series.csv")
cat(sprintf("[원장] %d행 | 컬럼 %s\n", nrow(lb), paste(names(lb)[1:12], collapse=",")))
stopifnot(all(c("beta_R05","m4","regime") %in% names(lb)))
lb[, key := as.character(realized_ym)]
car <- as.data.table(read_parquet("06_Registry/book_carrier/carrier_STR_1715_on_M4gAE_R05_noLayer4_PG2.parquet"))
car[, decision_date := as.Date(decision_date)]
ci <- unique(car[, .(decision_date, invested)])
ci[, key := format(as.Date(cut(decision_date, "month")) + 31, "%Y-%m")]  # 결정월+1 = 실현월
ci[, key := format(seq(decision_date[1], by="month", length.out=1), "%Y-%m")]
ci[, key := format(as.Date(paste0(format(decision_date, "%Y-%m"), "-01")) + 32, "%Y-%m")]
M <- merge(ci[, .(key, decision_date, invested)], lb[, .(key, beta_R05, m4, regime)], by="key")
M[, prod_bm := beta_R05 * m4]
cat(sprintf("\n[① 캐리어 invested vs 원장 beta_R05×m4] n=%d | 일치 %.1f%% | max|Δ| %.4f | cor %.4f\n",
  nrow(M), 100*mean(abs(M$invested - M$prod_bm) < 1e-6), max(abs(M$invested - M$prod_bm)),
  suppressWarnings(cor(M$invested, M$prod_bm))))
if (mean(abs(M$invested - M$prod_bm) < 1e-6) < 0.99) {
  cat("[① 불일치 상위]\n")
  print(M[abs(invested-prod_bm) > 1e-6][order(-abs(invested-prod_bm))][1:6,
    .(key, regime, beta_R05, m4, prod=round(prod_bm,3), invested=round(invested,3))])
}
cat(sprintf("\n[② 저장 beta_R05 의 값 분포]\n"))
print(M[, .N, by=.(beta_R05=round(beta_R05,3))][order(-N)])
cat(sprintf("\n[② regime × beta_R05 교차표 — (regime,z) 2×2 표가 실제로 지켜졌나]\n"))
print(dcast(M[, .N, by=.(regime, beta=round(beta_R05,2))], regime ~ beta, value.var="N", fill=0))
cat("\n[해석] 각 regime 행에 값이 2개(표 규칙대로)면 (regime,z) 로 완전 결정 — I1 재개 가능.\n")
cat("       3개 이상이면 z 외 다른 입력이 beta_R05 를 움직인 것 — 그 축을 먼저 특정해야.\n")
fwrite(M, "stage_artifacts/tilt_realign_20260808/p16_j1_close.csv")
