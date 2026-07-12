#==============================================================================
# N2 / FQ-021 delta-ext — Step 0: inspect existing artifacts (no recompute)
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow) })
setDTthreads(1L); try(arrow::set_io_thread_count(2L), silent=TRUE)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT  <- file.path(ROOT, "stage_artifacts/WT_D20260711_002")
CACHE <- file.path(OUT, "text_cache")

# 1) text_cache columns + one part sample
parts <- list.files(CACHE, pattern="^metrics_part_.*\\.parquet$", full.names=TRUE)
cat("[insp] n parts:", length(parts), "\n")
s1 <- as.data.table(read_parquet(parts[1]))
cat("[insp] text_cache columns:\n"); print(names(s1))
cat("[insp] sample rows:\n"); print(head(s1[, .(rcept_no, Ticker, fy, rcept_dt, status, m1_avg_sentence_len_chars)], 5))

# 2) combine all, corp-year m1 availability
M <- rbindlist(lapply(parts, function(p) as.data.table(read_parquet(p))), fill=TRUE)
M <- unique(M, by="rcept_no")
cat("[insp] total unique rcept:", nrow(M), " ok:", sum(M$status=="ok"),"\n")
Mok <- M[status=="ok" & !is.na(m1_avg_sentence_len_chars)]
cat("[insp] ok+m1 rows:", nrow(Mok), " unique tickers:", uniqueN(Mok$Ticker), "\n")
cat("[insp] fy range:", min(Mok$fy), "-", max(Mok$fy), "\n")
# consecutive-year pairs count
setorder(Mok, Ticker, fy)
Mok[, fy_prev := shift(fy, 1L), by=Ticker]
Mok[, m1_prev := shift(m1_avg_sentence_len_chars, 1L), by=Ticker]
Mok[, is_consec := !is.na(fy_prev) & (fy - fy_prev == 1L)]
cat("[insp] consecutive-year Δm1 pairs available:", sum(Mok$is_consec), "\n")
cat("[insp] tickers with >=1 consec pair:", uniqueN(Mok[is_consec==TRUE]$Ticker), "\n")
cat("[insp] consec pairs by fy:\n"); print(Mok[is_consec==TRUE, .N, by=fy][order(fy)])

# 3) monthly panel structure
mp <- readRDS(file.path(OUT,"monthly_panel.rds"))
cat("[insp] monthly_panel names:", paste(names(mp), collapse=", "), "\n")
cat("[insp] me columns:", paste(names(mp$me), collapse=", "), "\n")
cat("[insp] bench_m columns:", paste(names(mp$bench_m), collapse=", "), "\n")
cat("[insp] me ym range:", min(mp$me$ym), "-", max(mp$me$ym), "\n")

# 4) signal_panel columns (confirm corp-year absent)
P <- readRDS(file.path(OUT,"signal_panel.rds"))
cat("[insp] signal_panel columns:", paste(names(P), collapse=", "), "\n")
cat("[insp] signal_panel: has fy?", "fy" %in% names(P), " rows:", nrow(P), "\n")
cat("[insp] DONE\n")
