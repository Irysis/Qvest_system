suppressPackageStartupMessages({library(data.table);library(arrow);library(jsonlite)})
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
WT<-"WT-R20260829_006"; AR<-"stage_artifacts/WT_R20260829_006"
p <- fromJSON(file.path("qepm/mailbox/worktask",WT,"risk_package.json"), simplifyVector=FALSE)
cat("[pkg] top keys:", paste(names(p),collapse=","),"\n")
req <- c("task_id","as_of_date","exposure_matrix_ref","factor_covariance_ref","specific_risk_ref",
         "security_covariance_ref","risk_summary","diagnostics","challenge_flags","selection_objective")
cat("[pkg] required present:", all(req %in% names(p)), " missing:",
    paste(setdiff(req,names(p)),collapse=","),"\n")
cat("[pkg] selection_objective =", p$selection_objective,
    " enum ok =", p$selection_objective %in% c("condition_number","stress_robust","crowding","shrinkage_quality"),"\n")
cat("[pkg] challenge_flags n =", length(p$challenge_flags),
    " crowding_score_per_factor n =", length(p$risk_summary$crowding_score_per_factor),"\n")
cat("[pkg] method candidates =", p$method_shopping_log$risk_agent$candidates_tried, "(cap 5)\n")
cat("[pkg] size bytes =", file.info(file.path("qepm/mailbox/worktask",WT,"risk_package.json"))$size,"\n")
for (f in c("exposure_matrix.parquet","factor_covariance.parquet","specific_risk.parquet",
            "covariance.parquet","regime_correlation.parquet","sigma_period_heterogeneity.parquet",
            "tail_risk.json")) {
  fp <- file.path(AR,f)
  cat(sprintf("[artifact] %-38s exists=%s size=%s\n", f, file.exists(fp),
      format(file.info(fp)$size, big.mark=",")))
}
CV <- read_parquet(file.path(AR,"covariance.parquet"))
M <- as.matrix(CV[,-1]); rownames(M) <- CV$Ticker
cat("[verify] covariance dim", dim(M), " symmetric =", isTRUE(all.equal(M, t(M), tolerance=1e-10)),
    " min eigen =", signif(min(eigen(M,symmetric=TRUE,only.values=TRUE)$values),4),
    " PD =", min(eigen(M,symmetric=TRUE,only.values=TRUE)$values)>0, "\n")
EX <- read_parquet(file.path(AR,"exposure_matrix.parquet"))
cat("[verify] exposure dim", dim(EX), " tickers match =", identical(EX$Ticker, CV$Ticker),"\n")
SP <- read_parquet(file.path(AR,"specific_risk.parquet"))
cat("[verify] specific_risk rows", nrow(SP), " all finite =", all(is.finite(SP$specific_var)),"\n")
apk <- fromJSON(file.path("qepm/mailbox/worktask",WT,"alpha_package.json"), simplifyVector=TRUE)
cat("[verify] alpha universe coverage =", length(intersect(names(apk$alpha_vector), CV$Ticker)),
    "/", length(apk$alpha_vector), "\n")
## alpha 무수정 검증
cat("[verify] alpha_package mtime =", as.character(file.info(file.path("qepm/mailbox/worktask",WT,"alpha_package.json"))$mtime),"\n")
