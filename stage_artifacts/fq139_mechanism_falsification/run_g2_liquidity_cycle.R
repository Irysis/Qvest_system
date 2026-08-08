# run_g2_liquidity_cycle.R — G2: 국면 의존의 대안 기전 = 소형주 유동성 사이클인가
# 배경: F2/H2 에서 외국인 수급은 FQ-138 국면 의존을 설명 못함이 확정(상호작용 p=0.338, 표본 2.1배 불변).
#   큐 가설문이 예비한 대안이 '소형주 유동성 사이클'이다. 두 단계로 시험한다:
#   ①broad(ms_lag1<=0) 국면에서 소형주 유동성이 실제로 확대되는가  ← 전제
#   ②그 확대가 계약 알파 강도(월별 IC)와 동행하는가                ← 기전 연결
#   ①이 거짓이면 대안 기전도 기각. ①만 참이고 ②가 거짓이면 '국면=유동성'이나 알파와는 무관.
suppressMessages({ library(data.table); library(arrow) })
options(scipen=999)
setwd(Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
FQ <- "04_Research/method_frontier/fq002_contract_magnitude"
OUT <- "stage_artifacts/fq139_mechanism_falsification"

Rg <- as.data.table(read_parquet(file.path(FQ,"gridx_returns.parquet"))); Rg[, Date := as.Date(Date)]
SZ <- as.data.table(read_parquet(file.path(FQ,"gridx_universe_size.parquet"))); SZ[, Date := as.Date(Date)]
LQ <- as.data.table(read_parquet(file.path(FQ,"gridx_liq.parquet"))); LQ[, Date := as.Date(Date)]
cat(sprintf("[gridx_liq] %d행 cols=%s | %s~%s\n", nrow(LQ), paste(names(LQ),collapse=","), min(LQ$Date), max(LQ$Date)))

X <- merge(Rg, SZ, by=c("Date","Ticker"))[is.finite(Ret_1m) & Ret_1m<=5 & Ret_1m>=-1 & is.finite(Size)]
X[, rk := frank(-Size, ties.method="first"), by=Date]
M <- X[, .(ms = mean(Ret_1m[rk<=10]) - median(Ret_1m)), by=Date][order(Date)]
M[, `:=`(ms_lag1 = shift(ms,1), ym = format(Date,"%Y%m"))]

## ① 소형주 유동성: 유니버스 내 size 하위 50% 의 유동성(adv) 대 전체 중앙값 비
lcol <- setdiff(names(LQ), c("Date","Ticker"))[1]
cat(sprintf("[유동성 열] %s\n", lcol))
L <- merge(SZ, LQ, by=c("Date","Ticker"))
L <- L[is.finite(Size) & is.finite(get(lcol)) & get(lcol) > 0]
L[, srk := frank(Size, ties.method="first")/.N, by=Date]     # 낮을수록 소형
LIQ <- L[, .(small_liq = median(get(lcol)[srk <= 0.5]),
             large_liq = median(get(lcol)[srk > 0.5]),
             n = .N), by=Date]
LIQ[, `:=`(sl_ratio = small_liq/pmax(large_liq,1e-12), ym = format(Date,"%Y%m"))]
D <- merge(M[, .(ym, Date, ms_lag1)], LIQ[, .(ym, small_liq, large_liq, sl_ratio)], by="ym")[is.finite(ms_lag1)]
D[, broad := ms_lag1 <= 0]
cat(sprintf("\n[① 국면별 소형주 유동성] broad %d개월 · mega %d개월\n", sum(D$broad), sum(!D$broad)))
print(D[, .(개월=.N, 소형유동성=round(median(small_liq)/1e8,2), 대형유동성=round(median(large_liq)/1e8,2),
            소형대형비=round(median(sl_ratio),4)), by=broad])
t1 <- t.test(D[broad==TRUE, sl_ratio], D[broad==FALSE, sl_ratio])
w1 <- suppressWarnings(wilcox.test(D[broad==TRUE, sl_ratio], D[broad==FALSE, sl_ratio]))
cat(sprintf("  소형/대형 유동성비: broad %.4f vs mega %.4f | t=%.2f p=%.4f | Wilcoxon p=%.4f → %s\n",
  mean(D[broad==TRUE, sl_ratio]), mean(D[broad==FALSE, sl_ratio]), t1$statistic, t1$p.value, w1$p.value,
  ifelse(t1$p.value < 0.05, "전제 성립(국면=유동성 사이클 신호 있음)", "★전제 미성립")))

## ② 계약 알파 월별 IC 와 유동성의 동행
P <- as.data.table(read_parquet(file.path(FQ,"panelx_A.parquet")))
P[, mi := as.integer(substr(ym,1,4))*12L + as.integer(substr(ym,6,7))]
FR <- Rg[, .(Ticker, Ret_1m, mi = as.integer(format(Date,"%Y"))*12L + as.integer(format(Date,"%m")))]
J <- merge(P[, .(Ticker, mi, ym, w_amt)], FR, by=c("Ticker","mi"))
J <- J[is.finite(w_amt) & is.finite(Ret_1m)]
IC <- J[, .(ic = if (.N >= 15) suppressWarnings(cor(frank(w_amt), frank(Ret_1m))) else NA_real_, n=.N), by=ym]
IC <- IC[is.finite(ic)]
cat(sprintf("\n[② 월별 IC] %d개월 | 평균 %.4f\n", nrow(IC), mean(IC$ic)))
K <- merge(IC, D[, .(ym, broad, sl_ratio, ms_lag1)], by="ym")
cat(sprintf("  국면별 IC: broad %.4f (n=%d) vs mega %.4f (n=%d) | t=%.2f p=%.4f\n",
  mean(K[broad==TRUE, ic]), sum(K$broad), mean(K[broad==FALSE, ic]), sum(!K$broad),
  t.test(K[broad==TRUE, ic], K[broad==FALSE, ic])$statistic,
  t.test(K[broad==TRUE, ic], K[broad==FALSE, ic])$p.value))
ct <- suppressWarnings(cor.test(K$ic, K$sl_ratio, method="spearman"))
cat(sprintf("  IC ↔ 소형/대형 유동성비 상관(Spearman): rho=%.4f p=%.4f → %s\n", ct$estimate, ct$p.value,
  ifelse(ct$p.value < 0.05, "★동행 확인 — 유동성 사이클이 대안 기전 후보로 생존",
         "동행 없음 — 유동성 사이클도 알파 강도를 설명 못함")))
fwrite(K, file.path(OUT, "g2_liquidity_cycle.csv"))
