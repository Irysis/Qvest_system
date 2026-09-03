# S2c — 등재 팩터 로드 (C15: load_month_factors() 경유 의무)
#   M02_Mom_6_1 (기저 신호 · 2급 arm 정의) / M06_High_52w (F11 원문 Table 6 대응)
#   L-family 5종 (design_constants #11 직교성 배터리)
suppressWarnings(suppressMessages({library(data.table); library(arrow); library(dplyr)}))
ROOT <- Sys.getenv("QM_ROOT"); if (!nzchar(ROOT)) ROOT <- getwd()
setwd(ROOT); Sys.setenv(CLAUDE_PROJECT_DIR = ROOT)
source(file.path(ROOT, "02_Infrastructure/config.R"))
source(file.path(ROOT, "02_Infrastructure/factor_db/factor_db_connector.R"))
OUT <- file.path(ROOT, "stage_artifacts/WT_R20260829_011")
S2 <- readRDS(file.path(OUT, "s2_objects.rds")); ME <- S2$ME; rm(S2); gc(verbose = FALSE)
WANT <- c("M02_Mom_6_1","M06_High_52w","L01_Amihud","L02_Turnover","L11_Kyle_Lambda",
          "L15_Turnover_252d","L16_Turnover_Vol")
PART <- file.path(OUT, "s2c_parts"); dir.create(PART, showWarnings = FALSE)
t0 <- Sys.time()
for (i in seq_along(ME)) {
  d <- ME[i]; fp <- file.path(PART, sprintf("%s.rds", format(d, "%Y%m")))
  if (file.exists(fp)) next
  f <- tryCatch(load_month_factors(d, factor_names = WANT), error = function(e) { message("ERR ", d, ": ", conditionMessage(e)); NULL })
  if (is.null(f) || !nrow(f)) { saveRDS(data.table(), fp); next }
  f <- as.data.table(f)
  vn <- if ("Z_Score_Aligned" %in% names(f)) "Z_Score_Aligned" else "Z_Score"
  saveRDS(f[, .(Date = d, Ticker, Factor_Name, z = get(vn))], fp)
  rm(f); if (i %% 10 == 0) gc(verbose = FALSE)
}
FL <- rbindlist(lapply(list.files(PART, full.names = TRUE), readRDS), fill = TRUE)
FW <- dcast(FL[Factor_Name %chin% WANT], Date + Ticker ~ Factor_Name, value.var = "z",
            fun.aggregate = function(x) mean(x, na.rm = TRUE))
saveRDS(FW, file.path(OUT, "s2c_factors.rds"))
cat(sprintf("\n[S2c] factors %d rows | %d months | elapsed %.0fs\n",
            nrow(FW), uniqueN(FW$Date), as.numeric(difftime(Sys.time(), t0, units = "secs"))))
for (k in setdiff(names(FW), c("Date","Ticker"))) cat(sprintf("   %-20s coverage %.1f%%\n", k, 100*mean(is.finite(FW[[k]]))))
