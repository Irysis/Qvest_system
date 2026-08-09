setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
suppressPackageStartupMessages(library(data.table))

OUT <- "stage_artifacts/FQ176/slice_3.rds"
SLICE <- 3L
OFFSET <- SLICE + 1L   # 3+1 번째부터
STEP <- 4L

## ---- 1. 입력 실측 (가정 금지) ----
FN <- trimws(readLines("stage_artifacts/FQ176/factor_set.txt"))
FN <- FN[nzchar(FN)]
cat("[input] factor_set.txt: n_factors =", length(FN), "| dup =", sum(duplicated(FN)), "\n")

pan <- readRDS("stage_artifacts/WT_D20260809_001/p0_panels.rds")
ret <- as.data.table(pan$ret)
cat("[input] ret panel: nrow =", nrow(ret), "| cols =", paste(names(ret), collapse=","), "\n")
cat("[input] ret Date class =", class(ret$Date)[1],
    "| range =", format(min(ret$Date)), "~", format(max(ret$Date)),
    "| n_unique_date(all) =", length(unique(ret$Date)), "\n")
stopifnot(inherits(ret$Date, "Date"))

ud <- sort(unique(ret$Date))
sel <- ud[ud >= as.Date("2003-01-01") & ud <= as.Date("2026-06-30")]
n_all <- length(sel)
n_ym  <- length(unique(format(sel, "%Y-%m")))
cat("[input] months in [2003-01-01, 2026-06-30]: n =", n_all,
    "| n_unique_ym =", n_ym,
    "| first =", format(sel[1]), "| last =", format(sel[n_all]), "\n")
cat("[input] 관측단위 = 월말일 (day-of-month 분포):\n")
print(table(as.integer(format(sel, "%d"))))
if (n_all != 282L) cat("[WARN] 예상 282개월과 불일치: 실측 ", n_all, "\n")
stopifnot(n_all == n_ym)   # 월당 정확히 1개 날짜

idx <- seq(OFFSET, n_all, by = STEP)
months <- sel[idx]
cat("[slice] slice =", SLICE, "| seq(", OFFSET, ",", n_all, ", by=", STEP, ") -> n =",
    length(months), "| first =", format(months[1]),
    "| last =", format(months[length(months)]), "\n")

## ---- 2. 로드 ----
source("02_Infrastructure/config.R")
source("02_Infrastructure/factor_db/factor_db_connector.R")

res <- vector("list", length(months))
failed <- character(0)
fac_n  <- integer(length(months))
row_n  <- integer(length(months))
t_all <- Sys.time()

for (i in seq_along(months)) {
  d <- months[i]
  ok <- TRUE
  Fx <- NULL
  msg <- NA_character_
  tryCatch({
    Fx <- as.data.table(load_month_factors(d, factor_names = FN))
  }, error = function(e) {
    ok <<- FALSE; msg <<- conditionMessage(e)
  }, warning = function(w) {
    # 경고는 실패 아님 — 기록만
    msg <<- paste0("warn: ", conditionMessage(w))
  })

  if (!ok || is.null(Fx) || nrow(Fx) == 0L) {
    failed <- c(failed, format(d))
    cat(sprintf("[FAIL] %s : %s\n", format(d),
                if (!is.na(msg)) msg else "NULL/0-row return"))
    next
  }

  vcol <- if ("Z_Score_Aligned" %in% names(Fx)) "Z_Score_Aligned" else
          if ("Z_Score" %in% names(Fx)) "Z_Score" else NA_character_
  if (is.na(vcol) || !all(c("Ticker","Factor_Name") %in% names(Fx))) {
    failed <- c(failed, format(d))
    cat(sprintf("[FAIL] %s : 필수 컬럼 부재 (cols=%s)\n", format(d),
                paste(names(Fx), collapse=",")))
    next
  }

  dt <- data.table(Date = d,
                   Ticker = as.character(Fx$Ticker),
                   Factor_Name = as.character(Fx$Factor_Name),
                   z = as.numeric(Fx[[vcol]]))
  res[[i]] <- dt
  fac_n[i] <- length(unique(dt$Factor_Name))
  row_n[i] <- nrow(dt)
  if (i %% 10L == 0L || i == 1L)
    cat(sprintf("[prog] %d/%d  %s  rows=%d  factors=%d  vcol=%s  elapsed=%.1fs\n",
                i, length(months), format(d), nrow(dt), fac_n[i], vcol,
                as.numeric(difftime(Sys.time(), t_all, units="secs"))))
}

res <- res[!vapply(res, is.null, logical(1))]
if (length(res) == 0L) stop("[FATAL] 성공한 월 0개 — 저장 중단")
Z <- rbindlist(res, use.names = TRUE, fill = FALSE)
setkey(Z, Date, Factor_Name, Ticker)
attr(Z, "metric_type") <- "canonical_screen_diag"
attr(Z, "slice") <- SLICE
attr(Z, "value_col_source") <- "Z_Score_Aligned (fallback Z_Score)"

saveRDS(Z, OUT)

## ---- 3. 산출 실측 ----
cat("\n[out] path:", normalizePath(OUT, winslash="/"), "\n")
cat("[out] n_months_processed(성공):", length(res), " / 대상", length(months),
    " | 실패", length(failed), "\n")
cat("[out] n_rows:", nrow(Z), "\n")
cat("[out] n_unique_factors:", length(unique(Z$Factor_Name)), "\n")
cat("[out] n_unique_tickers:", length(unique(Z$Ticker)), "\n")
cat("[out] Date range:", format(min(Z$Date)), "~", format(max(Z$Date)), "\n")
cat("[out] z: NA =", sum(is.na(Z$z)), "| range =",
    sprintf("%.4f ~ %.4f", min(Z$z, na.rm=TRUE), max(Z$z, na.rm=TRUE)), "\n")
cat("[out] 미출현 팩터(전 월 통틀어):",
    paste(setdiff(FN, unique(Z$Factor_Name)), collapse=", "), "\n")
cat("[out] 월별 팩터수 range:", min(fac_n[fac_n>0]), "~", max(fac_n), "\n")
cat("[out] failed_months:", if (length(failed)) paste(failed, collapse=",") else "(none)", "\n")
cat("[out] file size MB:", round(file.info(OUT)$size/1048576, 2), "\n")
cat("[out] metric_type: canonical_screen_diag\n")
cat("[out] total elapsed sec:", round(as.numeric(difftime(Sys.time(), t_all, units="secs")),1), "\n")
