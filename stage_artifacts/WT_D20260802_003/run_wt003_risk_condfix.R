## run_wt003_risk_condfix.R — Sigma eigen-floor conditioning (cond 645 -> <=500)
## failure_rules: cond>500 시 shrinkage 재추정 의무. eigen-floor = qvest-risk-style 명시 허용 기법.
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)})
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
OUT <- "stage_artifacts/WT_D20260802_003"; MBX <- "qepm/mailbox/worktask/WT-D20260802_003"

cov_dt <- as.data.table(read_parquet(file.path(OUT, "covariance.parquet")))
ids <- cov_dt$security_id
S <- as.matrix(cov_dt[, -1]); rownames(S) <- ids
eg <- eigen(S, symmetric=TRUE)
cond_before <- max(eg$values)/min(eg$values)
floor_v <- max(eg$values)/500
ev2 <- pmax(eg$values, floor_v)
S2 <- eg$vectors %*% diag(ev2) %*% t(eg$vectors)
S2 <- (S2 + t(S2))/2
dimnames(S2) <- dimnames(S)
eg2 <- eigen(S2, symmetric=TRUE, only.values=TRUE)$values
cond_after <- max(eg2)/min(eg2)
psd_after <- min(eg2) > 0
n_floored <- sum(eg$values < floor_v)
delta_fro <- norm(S2 - S, "F")/norm(S, "F")
cat(sprintf("eigen-floor: cond %.1f -> %.1f | psd=%s | floored %d/%d eigvals | rel Frobenius delta=%.5f\n",
    cond_before, cond_after, psd_after, n_floored, length(ev2), delta_fro))
stopifnot(psd_after, cond_after <= 500 + 1e-6)

out_dt <- data.table(security_id=ids, as.data.table(S2))
write_parquet(out_dt, file.path(OUT, "covariance.parquet"))
write_parquet(out_dt, file.path(MBX, "covariance.parquet"))

rp <- fromJSON(file.path(MBX, "risk_package.json"), simplifyVector=FALSE)
rp$diagnostics$condition_number <- round(cond_after, 1)
rp$diagnostics$condition_number_before_floor <- round(cond_before, 1)
rp$diagnostics$conditioning <- sprintf(
  "eigen_floor(target cond<=500): %d/%d eigenvalues floored, rel Frobenius delta=%.5f — PSD 유지, BOmegaB'+D 구조 대비 미세 변형(문서화)",
  n_floored, length(ev2), delta_fro)
rp$sigma_estimator$sigma_cond <- round(cond_after, 1)
rp$sigma_estimator$sigma_cond_before_floor <- round(cond_before, 1)
rp$challenge_flags[[length(rp$challenge_flags)+1]] <- list(
  id="RF-WT003-TE-CRASH", severity="MEDIUM",
  flag="Iran_War(2026-02~04) active -41.8% (ret_net -7.6% vs BM +33.5%) — SMALL-국소 알파의 벤치 megacap 랠리 추적 실패형 TE-crash. active skew -2.70, CF-VaR99(active) 30.4%/m. 시장하락 위험 아닌 벤치-괴리 위험")
write_json(rp, file.path(MBX, "risk_package.json"), pretty=TRUE, auto_unbox=TRUE, digits=6, null="null")
cat("risk_package.json updated (conditioning + TE-crash flag)\n")
