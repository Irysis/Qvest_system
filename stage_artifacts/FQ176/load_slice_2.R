# FQ176 적재 슬라이스 2/4 — metric_type = canonical_screen_diag
# 계약: factor_db parquet 직접 read 금지 → load_month_factors() 경유 (PIT C15)
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
suppressPackageStartupMessages({
  library(data.table)
})

SLICE   <- 2L
OFFSET  <- SLICE + 1L   # 2+1 = 3
STEP    <- 4L
OUT     <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/stage_artifacts/FQ176/slice_2.rds"
JOUT    <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/stage_artifacts/FQ176/slice_2_summary.json"

cat("=== [INPUT 실측] ===\n")

## ---- 1. 팩터 목록 ----
fn_path <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/stage_artifacts/FQ176/factor_set.txt"
FN <- readLines(fn_path, warn = FALSE)
FN <- trimws(FN)
FN <- FN[nzchar(FN)]
cat(sprintf("factor_set.txt: 비어있지 않은 줄 %d개, 고유 %d개\n", length(FN), length(unique(FN))))
cat(sprintf("  head: %s ... tail: %s\n", paste(head(FN, 3), collapse=","), paste(tail(FN, 3), collapse=",")))
FN <- unique(FN)

## ---- 2. 대상 월 ----
pp <- readRDS("C:/Users/99922/OneDrive/Quant_Module_Moltbot/stage_artifacts/WT_D20260809_001/p0_panels.rds")
cat(sprintf("p0_panels.rds: names = %s\n", paste(names(pp), collapse=",")))
ret <- as.data.table(pp$ret)
cat(sprintf("ret: nrow=%d, ncol=%d, cols=%s\n", nrow(ret), ncol(ret), paste(names(ret), collapse=",")))
stopifnot("Date" %in% names(ret))
ret[, Date := as.Date(Date)]
cat(sprintf("ret$Date 범위: %s ~ %s / 고유일자 %d개\n",
            as.character(min(ret$Date, na.rm=TRUE)), as.character(max(ret$Date, na.rm=TRUE)),
            uniqueN(ret$Date)))

all_d <- sort(unique(ret$Date))
d_in  <- all_d[all_d >= as.Date("2003-01-01") & all_d <= as.Date("2026-06-30")]
cat(sprintf("2003-01-01~2026-06-30 고유일자: %d개 (%s ~ %s)\n",
            length(d_in), as.character(min(d_in)), as.character(max(d_in))))
# 관측단위 확인: 월말일인지 (같은 ym 내 1개인지)
ym <- format(d_in, "%Y-%m")
cat(sprintf("  고유 ym 수: %d  → 일자/ym 비율 = %.3f (1.000이면 월간 관측단위)\n",
            uniqueN(ym), length(d_in)/uniqueN(ym)))
dom <- as.integer(format(d_in, "%d"))
cat(sprintf("  day-of-month 범위: %d ~ %d (월말이면 28~31)\n", min(dom), max(dom)))
if (length(d_in) != uniqueN(ym)) {
  cat("  ⚠ ym당 다중 일자 존재 → 월별 최대일(월말)만 사용\n")
  dt_d <- data.table(Date = d_in, ym = ym)
  d_in <- sort(dt_d[, .(Date = max(Date)), by = ym]$Date)
  cat(sprintf("  월말 축약 후: %d개월\n", length(d_in)))
}

N <- length(d_in)
cat(sprintf("대상 월 총수 N = %d (예상 282, %s)\n", N, ifelse(N==282L, "일치", "★불일치")))

idx <- seq(OFFSET, N, by = STEP)
d_slice <- d_in[idx]
cat(sprintf("슬라이스 %d: idx = seq(%d, %d, by=%d) → %d개월\n", SLICE, OFFSET, N, STEP, length(d_slice)))
cat(sprintf("  첫 3: %s / 끝 3: %s\n",
            paste(head(as.character(d_slice),3), collapse=","),
            paste(tail(as.character(d_slice),3), collapse=",")))

## ---- 3. 로드 ----
cat("\n=== [LOAD] ===\n")
source("02_Infrastructure/config.R")
source("02_Infrastructure/factor_db/factor_db_connector.R")

res <- vector("list", length(d_slice))
failed <- character(0)
fail_msg <- character(0)
val_col_used <- character(0)

for (i in seq_along(d_slice)) {
  d <- d_slice[i]
  out <- tryCatch({
    Fx <- load_month_factors(d, factor_names = FN)
    if (is.null(Fx)) stop("load_month_factors returned NULL")
    Fx <- as.data.table(Fx)
    if (nrow(Fx) == 0L) stop("0 rows returned")
    vc <- if ("Z_Score_Aligned" %in% names(Fx)) "Z_Score_Aligned" else if ("Z_Score" %in% names(Fx)) "Z_Score" else NA_character_
    if (is.na(vc)) stop(sprintf("no value column; cols=%s", paste(names(Fx), collapse=",")))
    if (!all(c("Ticker","Factor_Name") %in% names(Fx)))
      stop(sprintf("missing key cols; cols=%s", paste(names(Fx), collapse=",")))
    val_col_used <<- c(val_col_used, vc)
    data.table(Date = d, Ticker = Fx[["Ticker"]], Factor_Name = Fx[["Factor_Name"]], z = Fx[[vc]])
  }, error = function(e) {
    failed <<- c(failed, as.character(d))
    fail_msg <<- c(fail_msg, sprintf("%s: %s", as.character(d), conditionMessage(e)))
    NULL
  })
  res[[i]] <- out
  if (i %% 10L == 0L || i == length(d_slice))
    cat(sprintf("  [%d/%d] %s  누적행=%s  실패=%d\n", i, length(d_slice), as.character(d),
                format(sum(vapply(res, function(x) if (is.null(x)) 0L else nrow(x), integer(1)))), length(failed)))
}

DT <- rbindlist(Filter(Negate(is.null), res), use.names = TRUE, fill = TRUE)

cat("\n=== [OUTPUT 실측] ===\n")
cat(sprintf("처리 성공 월수: %d / 시도 %d\n", length(d_slice) - length(failed), length(d_slice)))
cat(sprintf("총 행수: %d\n", nrow(DT)))
cat(sprintf("고유 팩터수: %d (요청 %d)\n", uniqueN(DT$Factor_Name), length(FN)))
missing_f <- setdiff(FN, unique(DT$Factor_Name))
if (length(missing_f)) cat(sprintf("  ★미반환 팩터 %d종: %s\n", length(missing_f), paste(missing_f, collapse=",")))
cat(sprintf("값컬럼 사용: %s\n", paste(unique(val_col_used), collapse=",")))
cat(sprintf("고유 Ticker: %d / z NA비율 %.4f\n", uniqueN(DT$Ticker), mean(is.na(DT$z))))
cat(sprintf("Date 범위: %s ~ %s / 고유월 %d\n", as.character(min(DT$Date)), as.character(max(DT$Date)), uniqueN(DT$Date)))
if (length(failed)) { cat("실패 월:\n"); cat(paste0("  ", fail_msg, collapse="\n"), "\n") }

attr(DT, "metric_type") <- "canonical_screen_diag"
attr(DT, "slice") <- SLICE
saveRDS(DT, OUT)
cat(sprintf("saved: %s (%.1f MB)\n", OUT, file.info(OUT)$size/1e6))

summ <- list(slice = SLICE, n_months = length(d_slice) - length(failed),
             n_months_attempted = length(d_slice), n_rows = nrow(DT),
             n_factors = uniqueN(DT$Factor_Name), failed_months = failed,
             fail_msg = fail_msg, N_total_months = N,
             value_col = unique(val_col_used), metric_type = "canonical_screen_diag")
writeLines(jsonlite::toJSON(summ, auto_unbox = TRUE, pretty = TRUE), JOUT)
cat("DONE\n")
