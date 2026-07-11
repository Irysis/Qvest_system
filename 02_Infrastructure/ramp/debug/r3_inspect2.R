## r3_inspect2.R — pure_factor_scores 스키마 + tail/EP 팩터 커버리지 + family 매핑
suppressPackageStartupMessages({library(data.table); library(arrow)})
setDTthreads(1); try(arrow::set_cpu_count(1),silent=TRUE); try(arrow::set_io_thread_count(2),silent=TRUE)
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)

cat("=== pure_factor_scores schema (open_dataset, no full load) ===\n")
ds<-arrow::open_dataset("outputs/ramp/pure_factor_scores.parquet")
print(ds$schema)

cat("\n=== distinct factor_id (via arrow) ===\n")
# assume long format with factor_id column
sch_names <- names(ds$schema)
cat("cols:", paste(sch_names, collapse=", "), "\n")
fac_col <- intersect(c("factor_id","factor","factor_name"), sch_names)[1]
fam_col <- intersect(c("family","economic_group","group","econ_group"), sch_names)[1]
cat("factor col:", fac_col, " | family col:", fam_col, "\n")

library(dplyr)
tgt <- c("D47_CVaR_5pct","D48_VaR_5pct","D49_VaR_1pct","R01_VaR_95","R02_VaR_99",
         "R03_CVaR_95","R04_CVaR_99","R05_Tail_Risk","D25_Left_Tail_Beta",
         "V02_EP","V15_NetDebt_Adj_EP")
sel_cols <- c(fac_col, fam_col)
sel_cols <- sel_cols[!is.na(sel_cols)]
sub <- ds %>% filter(.data[[fac_col]] %in% tgt) %>%
  select(all_of(c(sel_cols, intersect(c("signal_date","security_id","z_pure","pure_z","z","score","z_score"), sch_names)))) %>%
  collect() %>% as.data.table()
cat("collected rows for target factors:", nrow(sub), "\n")
zcol <- intersect(c("z_pure","pure_z","z","score","z_score"), names(sub))[1]
cat("z col:", zcol, "\n")
if(nrow(sub)){
  sm <- sub[, .(n_rows=.N, n_months=uniqueN(signal_date), n_sec=uniqueN(security_id),
                fam=if(!is.na(fam_col)) paste(unique(get(fam_col)),collapse=";") else NA,
                dmin=min(as.Date(signal_date)), dmax=max(as.Date(signal_date))),
            by=fac_col]
  print(sm)
}

cat("\n=== full distinct factor list in pure_factor_scores ===\n")
allf <- ds %>% select(all_of(fac_col)) %>% distinct() %>% collect()
cat("n distinct factors:", nrow(allf), "\n")
print(sort(allf[[fac_col]]))
