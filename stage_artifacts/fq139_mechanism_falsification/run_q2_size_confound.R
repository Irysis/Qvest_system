# run_q2_size_confound.R — Q2: '비유동성 조건화'가 실은 'size 교락'인가
# G2 발견: 월별 IC ↔ 소형/대형 유동성비 Spearman −0.3449(p=0.0021), 방향은 직관과 반대.
# 교락 가설: 비유동 국면 = 소형주 국면이고, 계약 알파가 소형주에 편중돼 있다면 그 상관은
#   유동성 상태가 아니라 size 구성의 그림자다.
# 판별: size 반절 안에서 각각 IC 를 계산해 유동성비와의 상관이 **양쪽 모두** 유지되는가.
#   한쪽(소형)에서만 나오면 size 교락, 양쪽에서 나오면 유동성 상태 효과.
suppressMessages({ library(data.table); library(arrow) })
options(scipen=999)
setwd(Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
FQ <- "04_Research/method_frontier/fq002_contract_magnitude"
OUT <- "stage_artifacts/fq139_mechanism_falsification"

Rg <- as.data.table(read_parquet(file.path(FQ,"gridx_returns.parquet"))); Rg[, Date := as.Date(Date)]
SZ <- as.data.table(read_parquet(file.path(FQ,"gridx_universe_size.parquet"))); SZ[, Date := as.Date(Date)]
LQ <- as.data.table(read_parquet(file.path(FQ,"gridx_liq.parquet"))); LQ[, Date := as.Date(Date)]
P  <- as.data.table(read_parquet(file.path(FQ,"panelx_A.parquet")))
mi_of <- function(d) as.integer(format(d,"%Y"))*12L + as.integer(format(d,"%m"))

# 유동성 상태 (월)
L <- merge(SZ, LQ, by=c("Date","Ticker"))[is.finite(Size) & is.finite(adv) & adv > 0]
L[, srk := frank(Size, ties.method="first")/.N, by=Date]
LS <- L[, .(sl_ratio = median(adv[srk<=0.5])/pmax(median(adv[srk>0.5]),1e-12)), by=Date]
LS[, ym := format(Date, "%Y%m")]

# 계약 신호 × 익월 수익 × size
FR <- Rg[, .(Ticker, Ret_1m, mi = mi_of(Date))]
SZm <- SZ[, .(Ticker, Size, mi = mi_of(Date))]
P[, mi := as.integer(substr(ym,1,4))*12L + as.integer(substr(ym,6,7))]
J <- merge(P[, .(Ticker, mi, ym, w_amt)], FR, by=c("Ticker","mi"))
J <- merge(J, SZm, by=c("Ticker","mi"))
J <- J[is.finite(w_amt) & is.finite(Ret_1m) & is.finite(Size)]
J[, size_half := ifelse(frank(Size, ties.method="first")/.N > 0.5, "대형", "소형"), by=ym]
cat(sprintf("[결합] %d건 | %d개월 | 소형 %d · 대형 %d\n", nrow(J), uniqueN(J$ym),
            sum(J$size_half=="소형"), sum(J$size_half=="대형")))

ic_by <- function(sub) sub[, .(ic = if (.N >= 12) suppressWarnings(cor(frank(w_amt), frank(Ret_1m))) else NA_real_,
                               n = .N), by=ym][is.finite(ic)]
res <- list()
for (g in c("전체","소형","대형")) {
  sub <- if (g=="전체") J else J[size_half == g]
  IC <- ic_by(sub)
  K <- merge(IC, LS[, .(ym, sl_ratio)], by="ym")
  if (nrow(K) < 20) { cat(sprintf("  %s: 표본 부족(%d개월)\n", g, nrow(K))); next }
  ct <- suppressWarnings(cor.test(K$ic, K$sl_ratio, method="spearman"))
  res[[length(res)+1L]] <- data.table(그룹=g, 개월=nrow(K), 평균IC=round(mean(K$ic),4),
    rho=round(as.numeric(ct$estimate),4), p=round(ct$p.value,4))
}
R <- rbindlist(res)
cat("\n===== size 반절별: IC ↔ 소형/대형 유동성비 =====\n"); print(R)
sm <- R[그룹=="소형"]; lg <- R[그룹=="대형"]
cat(sprintf("\n[판정] 소형 rho=%.4f(p=%.4f) · 대형 rho=%.4f(p=%.4f) → %s\n",
  sm$rho, sm$p, lg$rho, lg$p,
  ifelse(sm$p < 0.05 && lg$p < 0.05, "양쪽 모두 유지 — **유동성 상태 효과**(size 교락 배제)",
    ifelse(sm$p < 0.05 && lg$p >= 0.05, "★소형에서만 — **size 교락 의심**(비유동성 아닌 소형주 편중으로 재서술)",
      ifelse(lg$p < 0.05 && sm$p >= 0.05, "대형에서만 — 예상과 반대, 별도 진단 필요",
             "양쪽 모두 미유지 — 전체 상관이 구성 효과였을 가능성")))))
cat(sprintf("[참고] 그룹별 평균 IC: 소형 %.4f vs 대형 %.4f (알파의 size 편중 여부)\n", sm$평균IC, lg$평균IC))
fwrite(R, file.path(OUT, "q2_size_confound.csv"))
