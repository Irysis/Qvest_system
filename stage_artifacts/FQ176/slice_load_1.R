setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
suppressPackageStartupMessages({library(data.table)})

SLICE  <- 1L
OFFSET <- 1L + 1L   # seq(1+1, 282, by=4)
BY     <- 4L
OUT    <- "stage_artifacts/FQ176/slice_1.rds"

# ---------------- 입력 실측 ----------------
FN <- trimws(readLines("stage_artifacts/FQ176/factor_set.txt")); FN <- FN[nzchar(FN)]
pn  <- readRDS("stage_artifacts/WT_D20260809_001/p0_panels.rds")
ret <- as.data.table(pn$ret)
ud  <- sort(unique(as.Date(ret$Date)))
sel <- ud[ud >= as.Date("2003-01-01") & ud <= as.Date("2026-06-30")]
idx <- seq(OFFSET, length(sel), by = BY)
MONTHS <- sel[idx]

cat("[INPUT] factors requested   :", length(FN), "unique =", length(unique(FN)), "\n")
cat("[INPUT] ret panel rows      :", nrow(ret), " cols =", paste(names(ret), collapse=","), "\n")
cat("[INPUT] ret obs unit        : month-end (uniq dates", length(ud),
    ", diff median", median(as.integer(diff(ud))), "d)\n")
cat("[INPUT] in-range months     :", length(sel), " range",
    format(min(sel)), "~", format(max(sel)), "\n")
cat("[SLICE] slice", SLICE, "months     :", length(MONTHS), " first",
    format(MONTHS[1]), " last", format(MONTHS[length(MONTHS)]), "\n")
flush.console()

# ---------------- 커넥터 (C15: parquet 직접 read 금지) ----------------
source("02_Infrastructure/config.R")
source("02_Infrastructure/factor_db/factor_db_connector.R")

res     <- vector("list", length(MONTHS))
failed  <- character(0)
fail_rs <- character(0)
meta    <- vector("list", length(MONTHS))

for (i in seq_along(MONTHS)) {
  d <- MONTHS[i]
  ok <- tryCatch({
    Fx <- as.data.table(load_month_factors(d, factor_names = FN))
    vcol <- if ("Z_Score_Aligned" %in% names(Fx)) "Z_Score_Aligned" else
            if ("Z_Score" %in% names(Fx)) "Z_Score" else NA_character_
    if (is.na(vcol)) stop("no value column; got: ", paste(names(Fx), collapse=","))
    if (nrow(Fx) == 0L) stop("zero rows returned")
    asof <- attr(Fx, "factor_db_asof_date")
    fnm  <- attr(Fx, "factor_db_file")
    dt <- data.table(Date = d, Ticker = Fx$Ticker,
                     Factor_Name = Fx$Factor_Name, z = Fx[[vcol]])
    res[[i]] <- dt
    meta[[i]] <- data.table(Date = d, n_row = nrow(dt),
                            n_factor = uniqueN(dt$Factor_Name),
                            n_ticker = uniqueN(dt$Ticker),
                            vcol = vcol,
                            db_file = if (is.null(fnm)) NA_character_ else fnm,
                            asof = if (is.null(asof)) as.Date(NA) else as.Date(asof))
    TRUE
  }, error = function(e) {
    failed  <<- c(failed, format(d))
    fail_rs <<- c(fail_rs, paste0(format(d), ": ", conditionMessage(e)))
    FALSE
  })
  if (i %% 10L == 0L || i == length(MONTHS))
    cat("  [", i, "/", length(MONTHS), "] ", format(d), " ok=", ok, "\n", sep=""); flush.console()
}

res  <- res[!vapply(res, is.null, logical(1))]
meta <- rbindlist(meta[!vapply(meta, is.null, logical(1))])
ALL  <- rbindlist(res, use.names = TRUE)
setcolorder(ALL, c("Date","Ticker","Factor_Name","z"))

# ---------------- 산출 실측 ----------------
cat("\n[OUT] rows          :", nrow(ALL), "\n")
cat("[OUT] months ok     :", uniqueN(ALL$Date), " / requested ", length(MONTHS), "\n")
cat("[OUT] unique factors:", uniqueN(ALL$Factor_Name), " (requested ", length(FN), ")\n")
miss <- setdiff(FN, unique(ALL$Factor_Name))
cat("[OUT] never-present :", if (length(miss)) paste(miss, collapse=",") else "(none)", "\n")
cat("[OUT] unique tickers:", uniqueN(ALL$Ticker), "\n")
cat("[OUT] z NA          :", sum(is.na(ALL$z)),
    " range [", paste(round(range(ALL$z, na.rm=TRUE),4), collapse=", "), "]\n")
cat("[OUT] Date range    :", format(min(ALL$Date)), "~", format(max(ALL$Date)), "\n")

# 침묵 대체 검거: 요청월 != DB 파일월 (커넥터가 결손 시 closest 로 폴백)
meta[, req_ym := format(Date, "%Y%m")]
meta[, file_ym := sub("^factor_db_(\\d{6})\\.parquet$", "\\1", db_file)]
vm <- meta[req_ym != file_ym]
cat("[OUT] vintage substitution months :", nrow(vm), "\n")
if (nrow(vm)) print(vm[, .(Date, db_file, asof)])
cat("[OUT] asof != month-end months    :",
    nrow(meta[!is.na(asof) & format(asof,"%Y%m") != req_ym]), "\n")
cat("[OUT] per-month rows  min/med/max :",
    paste(c(min(meta$n_row), median(meta$n_row), max(meta$n_row)), collapse=" / "), "\n")
cat("[OUT] per-month factors min/max   :",
    paste(c(min(meta$n_factor), max(meta$n_factor)), collapse=" / "), "\n")

attr(ALL, "metric_type")   <- "canonical_screen_diag"
attr(ALL, "slice")         <- SLICE
attr(ALL, "slice_spec")    <- sprintf("seq(%d, %d, by=%d) of 282 in-range month-ends", OFFSET, length(sel), BY)
attr(ALL, "months_meta")   <- meta
attr(ALL, "failed_months") <- failed
attr(ALL, "failed_reasons")<- fail_rs
attr(ALL, "value_column")  <- "Z_Score_Aligned"
saveRDS(ALL, OUT)
cat("[OUT] saved         :", normalizePath(OUT, winslash="/"), "\n")
cat("[OUT] failed months :", if (length(failed)) paste(failed, collapse=",") else "(none)", "\n")
if (length(fail_rs)) cat(paste0("  ", fail_rs, collapse="\n"), "\n")

cat("\n@@JSON@@", sprintf(
  '{"slice":%d,"n_months":%d,"n_rows":%d,"n_factors":%d,"failed_months":[%s]}',
  SLICE, uniqueN(ALL$Date), nrow(ALL), uniqueN(ALL$Factor_Name),
  if (length(failed)) paste0('"', failed, '"', collapse=",") else ""), "\n")
