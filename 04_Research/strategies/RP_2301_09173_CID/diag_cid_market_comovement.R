# diag_cid_market_comovement.R — CID 충격(u)과 KOSPI200 월수익 동행 진단 (2026-09-02 세션 진단, 권위 값 아님)
#   입력: 프로젝트 루트 cid_smoke.rds ($C = 엔진 CIDT: ymi, CID, dC, u) + .cache/rawdata.parquet BM_Ret
#   실행: Rscript -e 'source("<이 파일 절대경로>")'  (★ -e 문자열에 | 나 개행 금지 — Windows Rscript 가 cmd 로 재전달)
suppressMessages({library(data.table); library(arrow)})
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
x <- readRDS("cid_smoke.rds"); C <- as.data.table(x$C)
B <- as.data.table(read_parquet(".cache/rawdata.parquet", col_select = c("Date", "BM_Ret")))
B <- unique(B[is.finite(BM_Ret)], by = "Date"); B[, Date := as.Date(Date)]
B[, ymi := year(Date) * 12L + month(Date)]
M <- B[, .(bm = prod(1 + BM_Ret) - 1), by = ymi]
J <- merge(C, M, by = "ymi"); J[, yr := (ymi - 1L) %/% 12L]
cat(sprintf("n_u=%d  cor(u,mkt)=%.3f  cor(CID,mkt)=%.3f  cor(dCID,mkt)=%.3f  cor(u,abs(mkt))=%.3f\n",
            sum(is.finite(J$u)), cor(J$u, J$bm, use = "complete.obs"), cor(J$CID, J$bm, use = "complete.obs"),
            cor(J$dC, J$bm, use = "complete.obs"), cor(J$u, abs(J$bm), use = "complete.obs")))
for (rg in list(c(2005, 2010), c(2011, 2016), c(2017, 2021), c(2022, 2026))) {
  s <- J[yr >= rg[1] & yr <= rg[2] & is.finite(u)]
  cat(sprintf("  %d-%d: cor(u,mkt)=%.3f  cor(u,abs(mkt))=%.3f  mean CID=%.4f  n=%d\n",
              rg[1], rg[2], cor(s$u, s$bm), cor(s$u, abs(s$bm)), mean(s$CID), nrow(s)))
}
q <- J[is.finite(u)]
q[, ubin := cut(u, quantile(u, c(0, .2, .8, 1)), include.lowest = TRUE, labels = c("u_low", "u_mid", "u_high"))]
print(q[, .(n = .N, mean_mkt_pct = round(100 * mean(bm), 2), sd_mkt_pct = round(100 * sd(bm), 2),
            frac_mkt_up = round(mean(bm > 0), 2)), by = ubin][order(ubin)])
# 어느 달에 u 가 가장 컸나 (상위 8)
setorder(q, -u); print(q[1:8, .(ym = sprintf("%d-%02d", (ymi - 1L) %/% 12L, (ymi - 1L) %% 12L + 1L), u = round(u, 4), CID = round(CID, 4), mkt_pct = round(100 * bm, 1))])
