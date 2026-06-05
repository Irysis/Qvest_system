## Batch S3: STR_1479 + STR_1480
cat("=== Batch S3: STR_1479, STR_1480 ===\n")

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
INFRA_DIR <- file.path(PROJECT_ROOT, "02_Infrastructure")
source(file.path(INFRA_DIR, "config.R"))
source(file.path(INFRA_DIR, "backtest_harness.R"))
source(file.path(FACTOR_DB_DIR, "factor_db_connector.R"))
LIQ_THRESHOLD <- 2e8

res <- load_rawdata(use_cache = TRUE)
RAWDATA <- res$RAWDATA; BM_DT <- res$BM_DT

run_s3 <- function(strat_id, factor_id, component_factors) {
  cat(sprintf("\n======== S3: %s (%s) ========\n", strat_id, factor_id))
  strat_dir <- file.path(PROJECT_ROOT, "04_Research/strategies", strat_id)
  art_dir <- file.path(strat_dir, "stage_artifacts")
  source(file.path(strat_dir, "factor_engine.R"))

  latest_date <- max(FACTORS$Date)
  latest_scores <- FACTORS[Date == latest_date, .(Ticker, Score)]
  new_factor_z <- setNames(latest_scores$Score, latest_scores$Ticker)
  cat(sprintf("[S3] Latest: %s | N: %d\n", latest_date, length(new_factor_z)))

  fdt <- load_month_factors(latest_date, coverage_min = 0.01)
  fdt_wide <- dcast(fdt, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")
  new_dt <- data.table(Ticker = names(new_factor_z), New_Z = as.numeric(new_factor_z))
  merged <- merge(fdt_wide, new_dt, by = "Ticker")
  factor_cols <- setdiff(names(merged), c("Ticker", "New_Z", component_factors))
  cat(sprintf("[S3] Excluding: %s | Comparing %d\n", paste(component_factors, collapse=","), length(factor_cols)))

  corr_list <- lapply(factor_cols, function(fc) {
    valid <- !is.na(merged[[fc]]) & !is.na(merged$New_Z)
    if (sum(valid) < 20) return(data.table(Factor_Name=fc, Corr=NA_real_))
    data.table(Factor_Name=fc, Corr=cor(merged[[fc]][valid], merged$New_Z[valid], method="spearman"))
  })
  pairwise <- rbindlist(corr_list)[!is.na(Corr)]
  max_idx <- which.max(abs(pairwise$Corr))
  max_corr <- abs(pairwise$Corr[max_idx])
  max_factor <- pairwise$Factor_Name[max_idx]
  independence <- ifelse(max_corr < 0.3, "independent", ifelse(max_corr < 0.6, "partial", "redundant"))

  pairwise[, Category := gsub("^([A-Z]+)\\d+.*", "\\1", Factor_Name)]
  cat_corr <- pairwise[, .(Max_Corr = max(abs(Corr), na.rm=TRUE)), by=Category]
  setorder(cat_corr, -Max_Corr)
  top10 <- pairwise[order(-abs(Corr))][1:min(10, nrow(pairwise))]

  cat(sprintf("[S3] max: %.3f (vs %s) | %s\n", max_corr, max_factor, independence))
  for (j in 1:min(5, nrow(top10))) cat(sprintf("  %d. %s: %.3f\n", j, top10$Factor_Name[j], top10$Corr[j]))

  # Multi-date
  all_dates <- sort(unique(FACTORS$Date), decreasing=TRUE)
  check_dates <- all_dates[seq_len(min(3, length(all_dates)))]
  multi_results <- lapply(check_dates, function(d) {
    z_d <- setNames(FACTORS[Date==d]$Score, FACTORS[Date==d]$Ticker)
    if (length(z_d)<30) return(NULL)
    fdt_d <- tryCatch(load_month_factors(d, coverage_min=0.01), error=function(e) NULL)
    if (is.null(fdt_d)) return(NULL)
    fdt_w <- dcast(fdt_d, Ticker~Factor_Name, value.var="Z_Score_Aligned")
    m_d <- merge(fdt_w, data.table(Ticker=names(z_d), New_Z=as.numeric(z_d)), by="Ticker")
    if (nrow(m_d)<30) return(NULL)
    fc_d <- setdiff(names(m_d), c("Ticker","New_Z", component_factors))
    cc <- sapply(fc_d, function(fc) {
      v <- !is.na(m_d[[fc]])&!is.na(m_d$New_Z); if(sum(v)<20) NA_real_ else cor(m_d[[fc]][v],m_d$New_Z[v],method="spearman")
    })
    cc <- cc[!is.na(cc)]; if(length(cc)==0) return(NULL)
    mx <- which.max(abs(cc))
    data.table(Date=d, max_corr=abs(cc[mx]), max_factor=names(cc)[mx])
  })
  multi_dt <- rbindlist(multi_results[!sapply(multi_results, is.null)])
  avg_corr <- ifelse(nrow(multi_dt)>0, mean(multi_dt$max_corr), max_corr)

  # Component max_corrs
  comp_max_corrs <- list()
  for (cf in component_factors) {
    if (cf %in% names(merged)) {
      cf_vec <- merged[[cf]]
      if (!all(is.na(cf_vec))) {
        cf_corrs <- sapply(factor_cols[1:min(50, length(factor_cols))], function(fc) {
          v <- !is.na(merged[[fc]])&!is.na(cf_vec); if(sum(v)<20) NA_real_ else cor(merged[[fc]][v],cf_vec[v],method="spearman")
        })
        cf_corrs <- cf_corrs[!is.na(cf_corrs)]
        top5_cf <- sort(abs(cf_corrs), decreasing=TRUE)[1:min(5, length(cf_corrs))]
        comp_max_corrs[[cf]] <- as.list(setNames(round(cf_corrs[names(top5_cf)],3), paste0("vs_",names(top5_cf))))
      }
    }
  }

  s3 <- list(
    factor_id=factor_id, strategy_id=strat_id,
    components=as.list(component_factors),
    max_abs_corr_db=round(max_corr,4), most_correlated_factor=max_factor,
    component_max_corrs=comp_max_corrs,
    top5_corr=as.list(setNames(round(top10$Corr[1:min(5,nrow(top10))],4), top10$Factor_Name[1:min(5,nrow(top10))])),
    category_max_corr=as.list(setNames(round(cat_corr$Max_Corr,4), cat_corr$Category)),
    independence_class=independence,
    value_matrix_cell=paste0(ifelse(max_corr<0.3,"Independent",ifelse(max_corr<0.6,"Partial","Redundant")),"_S2"),
    n_compared=nrow(pairwise), n_months_analyzed=nrow(multi_dt),
    avg_max_corr_multidate=round(avg_corr,4), computed_date=as.character(Sys.Date()),
    scout_note=sprintf("max %.3f(vs %s). %s. avg %.3f. N=%d.", max_corr, max_factor, independence, avg_corr, length(new_factor_z))
  )
  jsonlite::write_json(s3, file.path(art_dir, sprintf("s3_orthogonality_%s.json", factor_id)), auto_unbox=TRUE, pretty=TRUE)
  cat(sprintf("[S3] Artifact saved.\n"))
  list(strat_id=strat_id, factor_id=factor_id, max_corr=max_corr, max_factor=max_factor, independence=independence)
}

r1 <- run_s3("STR_1479_short_pressure_alpha", "MF18_ShortPressure", "CR05_Short_Pressure_Proxy")
r2 <- run_s3("STR_1480_cashflow_accrual_quality", "MF19_CashflowAccrual", "AC21_CF_to_Accrual_Ratio")

cat("\n========== BATCH SUMMARY ==========\n")
for (r in list(r1,r2)) {
  if (!is.null(r)) cat(sprintf("  %s | %.3f vs %s | %s\n", r$strat_id, r$max_corr, r$max_factor, r$independence))
}
