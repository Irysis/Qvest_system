# run_q1_sealed.R — Q1 실행 (사전등록 Q1_PREREGISTRATION.md 사양 그대로, 변경 없음)
# 판정: 블록 부트스트랩(block=6, B=4000) rho 분포의 q05 < 0 ∧ 점추정 rho <= -0.20 → PASS
#       q05 < 0 이나 |rho| < 0.20 → 부분(방향만) / 그 외 FAIL
# ★사양 외 변형·서브샘플 탐색 금지(사전등록 §3). 결과와 무관하게 이 규칙으로 보고한다.
suppressMessages({ library(data.table); library(arrow) })
options(scipen=999)
setwd(Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
FQ <- "04_Research/method_frontier/fq002_contract_magnitude"
OUT <- "stage_artifacts/fq139_mechanism_falsification"
set.seed(20260808)

Rg <- as.data.table(read_parquet(file.path(FQ,"gridx_returns.parquet"))); Rg[, Date := as.Date(Date)]
SZ <- as.data.table(read_parquet(file.path(FQ,"gridx_universe_size.parquet"))); SZ[, Date := as.Date(Date)]
LQ <- as.data.table(read_parquet(file.path(FQ,"gridx_liq.parquet"))); LQ[, Date := as.Date(Date)]
P  <- as.data.table(read_parquet(file.path(FQ,"panelx_A.parquet")))
mi_of <- function(d) as.integer(format(d,"%Y"))*12L + as.integer(format(d,"%m"))

L <- merge(SZ, LQ, by=c("Date","Ticker"))[is.finite(Size) & is.finite(adv) & adv > 0]
L[, srk := frank(Size, ties.method="first")/.N, by=Date]
LS <- L[, .(sl_ratio = median(adv[srk<=0.5])/pmax(median(adv[srk>0.5]),1e-12)), by=Date]
LS[, ym := format(Date,"%Y%m")]

FR <- Rg[, .(Ticker, Ret_1m, mi = mi_of(Date))]
P[, mi := as.integer(substr(ym,1,4))*12L + as.integer(substr(ym,6,7))]
J <- merge(P[, .(Ticker, mi, ym, w_amt)], FR, by=c("Ticker","mi"))[is.finite(w_amt) & is.finite(Ret_1m)]
IC <- J[, .(ic = if (.N >= 12) suppressWarnings(cor(frank(w_amt), frank(Ret_1m), method="spearman")) else NA_real_,
            n = .N), by=ym][is.finite(ic)]
K <- merge(IC, LS[, .(ym, sl_ratio)], by="ym"); setorder(K, ym)
cat(sprintf("[사양 확인] 신호=w_amt · 수익=Ret_1m(익월) · 유동성=adv · 월표본>=12 · n_months=%d (%s~%s)\n",
            nrow(K), K$ym[1], K$ym[nrow(K)]))

rho_hat <- suppressWarnings(cor(K$ic, K$sl_ratio, method="spearman"))
blk <- 6L; B <- 4000L; n <- nrow(K); nb <- ceiling(n/blk)
boot <- replicate(B, {
  st <- sample.int(n - blk + 1L, nb, replace=TRUE)
  idx <- unlist(lapply(st, function(s) s:(s+blk-1L)))[seq_len(n)]
  suppressWarnings(cor(K$ic[idx], K$sl_ratio[idx], method="spearman"))
})
boot <- boot[is.finite(boot)]
q <- quantile(boot, c(0.05, 0.50, 0.95), names=FALSE)
cat(sprintf("\n[결과] 점추정 rho = %.4f | 부트스트랩(block=%d, B=%d) q05=%.4f · 중앙=%.4f · q95=%.4f\n",
            rho_hat, blk, B, q[1], q[2], q[3]))
pass <- (q[1] < 0) && (rho_hat <= -0.20)
part <- (q[1] < 0) && !pass
cat(sprintf("[사전등록 판정 규칙] q05<0 = %s · rho<=-0.20 = %s\n", q[1] < 0, rho_hat <= -0.20))
cat(sprintf("\n★[판정] %s\n", if (pass) "PASS — 조건화 재료 자격 인정(자본 편입 아님, PORT_t 별도)" else
  if (part) "부분 — 방향만 인정, 크기 미확정 → 소비 불가" else "FAIL — config-scoped negative 로 기록"))
write(jsonlite::toJSON(list(schema="q1_sealed_v1", prereg="Q1_PREREGISTRATION.md",
  spec=list(signal="w_amt", ret="Ret_1m(익월)", liq="adv", min_month_n=12, block=blk, B=B, seed=20260808),
  n_months=nrow(K), rho=rho_hat, q05=q[1], q50=q[2], q95=q[3],
  verdict=if (pass) "PASS" else if (part) "PARTIAL" else "FAIL",
  note="다중비교 맥락 — 점추정 p 단독 판정 금지, 분포 q05 로 판정(FQ-109 규약)"),
  pretty=TRUE, auto_unbox=TRUE), file.path(OUT, "q1_sealed_result.json"))
fwrite(K, file.path(OUT, "q1_monthly_panel.csv"))
cat(sprintf("[saved] q1_sealed_result.json + q1_monthly_panel.csv\n"))
