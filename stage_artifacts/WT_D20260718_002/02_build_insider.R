# WT-D20260718_002 — Insider net-sell panel builder (EXCLUSION signal)
# Signal = cumulative insider ON-MARKET net trading value over lookback L, indexed by
#          formation month t (rcept_dt month). Negative cnv = net SELLING (Miller harvest target).
# PIT (C5): for holding month t+1, use filings with rcept_dt month <= t (formation month-end).
#           sig_ym = rcept_dt month => at formation end-of-t we know all filings filed in month<=t.
# scopes: officer (is_officer=TRUE) / all (officer + major holder)
# on-market discretionary only: report_reason contains 장내 (장내매수(+)/장내매도(-)) = informed trades.
suppressWarnings(suppressMessages({library(arrow); library(data.table)}))
setDTthreads(1)
R <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT <- file.path(R, "stage_artifacts/WT_D20260718_002")
INSDIR <- file.path(R, ".cache/dart/insider_backfill")

cat("[1] load insider CSVs...\n")
csvs <- sort(list.files(INSDIR, pattern = glob2rx("*.csv"), full.names = TRUE))
ins <- rbindlist(lapply(csvs, function(f)
  fread(f, colClasses = list(character = "corp_code"), showProgress = FALSE)), fill = TRUE)
cat("   raw rows:", nrow(ins), "\n")

# clean + map
ins[, Ticker := paste0("A", formatC(as.integer(corp_code), width = 6, flag = "0"))]
ins[, qty_change := suppressWarnings(as.numeric(qty_change))]
ins[, price := suppressWarnings(as.numeric(price))]
ins[, is_officer := (tolower(as.character(is_officer)) %in% c("true","t","1"))]
# formation month = rcept_dt month (PIT: info public at filing)
ins[, rcept_dt := as.character(rcept_dt)]
ins[, sig_ym := paste0(substr(rcept_dt,1,4), "-", substr(rcept_dt,5,6))]
# on-market discretionary trades only
ins[, on_market := grepl("장내", report_reason, fixed = TRUE)]
ins <- ins[on_market == TRUE & !is.na(qty_change) & !is.na(price) & is.finite(qty_change*price)]
ins[, trade_value := qty_change * price]  # signed won (sell => negative)
cat("   on-market discretionary rows:", nrow(ins),
    " | net-sell rows(qty<0):", sum(ins$qty_change < 0),
    " net-buy rows(qty>0):", sum(ins$qty_change > 0), "\n")

# monthly net value per ticker x scope
agg_off <- ins[is_officer == TRUE, .(nv = sum(trade_value)), by = .(Ticker, sig_ym)]
agg_all <- ins[, .(nv = sum(trade_value)), by = .(Ticker, sig_ym)]
mkidx <- function(ym) as.integer(substr(ym,1,4))*12L + as.integer(substr(ym,6,7))
agg_off[, midx := mkidx(sig_ym)]; agg_all[, midx := mkidx(sig_ym)]

# formation months from base panel
ym_date <- as.data.table(arrow::read_parquet(file.path(OUT, "ym_date_map.parquet")))
ym_date[, midx := mkidx(ym)]
forms <- sort(unique(ym_date$midx))

# rolling cumulative net value over lookback L (months [t-L+1 .. t]) via frollsum on full grid
roll_cnv <- function(agg, L) {
  tick <- unique(agg$Ticker)
  allm <- seq(min(forms) - 11L, max(forms))    # include pre-history for right-aligned window
  grid <- CJ(Ticker = tick, midx = allm)
  g <- merge(grid, agg[, .(Ticker, midx, nv)], by = c("Ticker","midx"), all.x = TRUE)
  g[is.na(nv), nv := 0]
  setorder(g, Ticker, midx)
  g[, cnv := frollsum(nv, n = L, align = "right"), by = Ticker]
  g[midx %in% forms, .(Ticker, t = midx, cnv)]
}
cat("[2] rolling cnv (off/all x L in 3,6,12)...\n")
panel <- NULL
for (sc in c("off","all")) {
  agg <- if (sc == "off") agg_off else agg_all
  for (L in c(3L,6L,12L)) {
    r <- roll_cnv(agg, L)
    setnames(r, "cnv", paste0("cnv_", sc, "_", L))
    if (is.null(panel)) panel <- r else panel <- merge(panel, r, by = c("Ticker","t"), all = TRUE)
  }
}
# attach formation ym
panel <- merge(panel, ym_date[, .(t = midx, ym, Date)], by = "t")
# fill NA cnv with 0 (no insider activity in window = neutral)
cnvcols <- grep("^cnv_", names(panel), value = TRUE)
for (c0 in cnvcols) panel[is.na(get(c0)), (c0) := 0]
setorder(panel, ym, Ticker)
cat("   insider panel rows:", nrow(panel), " tickers:", uniqueN(panel$Ticker),
    " months:", uniqueN(panel$ym), "\n")
# quick: fraction net sellers (officer L6)
cat("   frac officer net-seller (cnv_off_6<0):", round(mean(panel$cnv_off_6 < 0),4),
    " | any-officer-activity (cnv_off_6!=0):", round(mean(panel$cnv_off_6 != 0),4), "\n")
arrow::write_parquet(panel, file.path(OUT, "insider_sell_panel.parquet"))
cat("[DONE]\n")
