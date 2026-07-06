# build_intan_panel.R — WT-D20260706_013 Alpha Research
# Hypothesis: Intangible-adjusted value (Peters-Taylor 2017; Eisfeldt-Papanikolaou 2013).
#   Standard KR value (BM/EP) is dead (AX-003, 24/24 post-2015 decay). Thesis: a large part of that
#   death is INTANGIBLE MISMEASUREMENT — R&D / SG&A (brand, software, org capital) expensed, so book
#   value understated -> intangible-intensive firms look expensive on BM but are actually cheap.
#   Peters-Taylor: capitalize R&D (perpetual inventory) + a fraction of SG&A -> adjusted book/earnings.
#
# ★CORE = large-cap wall-escape test. Standard value is small-cap-tilted (dies like net-issuance).
#   BUT KR intangible-intensive mega-caps (Samsung/Hynix R&D, NAVER/Kakao software, Celltrion/Samsung
#   Bio R&D) may reclassify to "cheap" -> intangible-adj value could tilt LARGE-CAP-LONG-SIDE = the only
#   route through the small-cap wall.
#
# INTANGIBLE CAPITAL CONSTRUCTION (Peters-Taylor 2017 params):
#   Knowledge capital (KC):  KC_t = (1-δ_RD)·KC_{t-1} + R&D_t         δ_RD = 0.15
#     init KC_0 = R&D_0 / (g + δ_RD),  g = 0.10 (steady-state)
#   Organizational capital (OC): OC_t = (1-δ_SGA)·OC_{t-1} + θ·SG&A_t  δ_SGA = 0.20, θ = 0.30
#     init OC_0 = θ·SG&A_0 / (g + δ_SGA)
#   Adjusted book:  B_adj = TotalEquity + KC + OC   (KC/OC = OFF-balance expensed intangibles;
#     on-balance IntangibleAssets already inside TotalEquity -> no double count)
#   Signals:
#     iBM  = B_adj / MarketCap                       (intangible-adj book-to-market; higher=cheaper)
#     iEP  = (NetIncome + θ·SG&A + R&D - amort) / MarketCap
#            amort = δ_RD·KC_{t-1} + δ_SGA·OC_{t-1}  (economic amortization of intangible stock)
#   CONTROL (must reproduce AX-003 death):
#     stdBM = TotalEquity / MarketCap                (standard book-to-market)
#     stdEP = NetIncome / MarketCap                  (standard earnings yield)
#
# DATA REALITY (feasibility scan, see build note): RandD line item collapses post-2016 (~20-34 univ
#   tickers). SGAExpense (~290-308) + TotalEquity (~334-361) + NetIncome (~350) stay strong post-2017.
#   -> Two variants:
#     (V-full)  KC+OC  = full Peters-Taylor. R&D present pre-2016 broadly, sparse post. Where R&D
#               missing, KC contribution = 0 (org-capital-only). Coverage flagged honestly.
#     (V-orgc)  OC-only intangible adj (SG&A-based org capital). Feasible full-period incl. post-2017.
#   Both emitted; screening evaluates both. Financial/utility (no R&D+low-SGA-intangibility) handled
#   by construction: KC=OC=0 -> iBM collapses to stdBM (no spurious reclassification).
#
# PIT DESIGN (C1/C2/C4/C10/C14/C15):
#   - Fundamentals from .cache/fundamental_merged.parquet, Item long format, Factor_Date already
#     PIT-lagged (quarterly ~45d, annual ~May). Signal at month t uses only Factor_Date <= t (as-of roll).
#   - TTM (trailing 4Q sum) for flow items (R&D, SG&A, NetIncome); latest <= t for stock (TotalEquity).
#   - MarketCap = Close*Size at month-end t (PIT at t). Forward Ret_1m realized t->t+1.
#   - Universe/ADV at t (C10). No full-sample stats (C1).

suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT-D20260706_013/panel")
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)

DELTA_RD  <- 0.15
DELTA_SGA <- 0.20
THETA_SGA <- 0.30
G_SS      <- 0.10

# =========================================================================
# 1. RAWDATA -> month-end panel (MarketCap, forward return, universe, adv20, BM_Ret)
cat("[intan] loading RAWDATA...\n"); flush.console()
rd <- as.data.table(read_parquet(".cache/RAWDATA.parquet"))
rd <- rd[, .(Date, Ticker, K200, KQ150, Sector, Close, Vol, Size, Ret, BM_Ret, Float)]
rd[, Date := as.Date(Date)]
setorder(rd, Ticker, Date)

# integer month key (avoid cut.Date segfault)
ud <- sort(unique(rd$Date)); lt <- as.POSIXlt(ud)
ym_map <- data.table(Date = ud, ym = as.Date(sprintf("%04d-%02d-01", lt$year + 1900L, lt$mon + 1L)))
rd <- merge(rd, ym_map, by = "Date", all.x = TRUE)
setorder(rd, Ticker, Date)
rd[, dvalue := Close * Vol]
rd[, adv20 := frollmean(dvalue, 20, align = "right"), by = Ticker]

is_last <- rd[, .I[.N], by = .(Ticker, ym)]$V1
me <- rd[is_last]
setorder(me, Ticker, ym)
me[, close_prev := shift(Close, 1), by = Ticker]
me[, mret := Close / close_prev - 1]
me[, Ret_1m := shift(mret, -1), by = Ticker]              # forward 1M realized
me[, in_univ := (K200 == 1 | KQ150 == 1)]
me[, MarketCap := Close * Size]                            # PIT market cap at month-end
# float-adjusted cap for cap-w benchmark (free-float weighting)
me[, ff := fifelse(is.finite(Float) & Float > 0, Float/100, 1)]
me[, MCap_ff := MarketCap * ff]
cat("[intan] month-end rows:", nrow(me), " univ months:", uniqueN(me[in_univ==TRUE]$ym), "\n"); flush.console()

# =========================================================================
# 2. Fundamentals: build TTM flows + latest stock, per ticker × Factor_Date (PIT)
cat("[intan] loading fundamentals...\n"); flush.console()
F <- as.data.table(read_parquet(".cache/fundamental_merged.parquet"))
F[, Factor_Date := as.Date(Factor_Date)]
F[, Period_Date := as.Date(Period_Date)]
keep_items <- c("RandD","SGAExpense","TotalEquity","NetIncome")
F <- F[Item %chin% keep_items & is.finite(Value)]
setorder(F, Ticker, Item, Period_Date)

# Deduplicate: one value per Ticker×Item×Period (keep latest Factor_Date restatement <= use)
F <- F[, .SD[.N], by = .(Ticker, Item, Period)]
setorder(F, Ticker, Item, Period_Date)

# TTM for flow items (R&D, SG&A, NetIncome) = trailing 4-quarter sum; require 4 finite quarters.
flow_ttm <- function(dt_item) {
  d <- copy(dt_item)
  setorder(d, Ticker, Period_Date)
  d[, v4 := frollsum(Value, 4, align = "right"), by = Ticker]
  d[, n4 := frollsum(as.integer(is.finite(Value)), 4, align = "right"), by = Ticker]
  d[, ttm := fifelse(is.finite(n4) & n4 == 4L, v4, NA_real_)]
  d[is.finite(ttm), .(Ticker, Factor_Date, Period_Date, ttm)]
}
rd_ttm  <- flow_ttm(F[Item=="RandD"])
sga_ttm <- flow_ttm(F[Item=="SGAExpense"])
ni_ttm  <- flow_ttm(F[Item=="NetIncome"])
# TotalEquity = latest stock value (not summed)
eq_pit  <- F[Item=="TotalEquity", .(Ticker, Factor_Date, Period_Date, eq = Value)]

cat(sprintf("[intan] TTM built: RandD=%d  SGA=%d  NI=%d  Equity=%d rows\n",
            nrow(rd_ttm), nrow(sga_ttm), nrow(ni_ttm), nrow(eq_pit))); flush.console()

# =========================================================================
# 3. Perpetual inventory of intangible capital — annual cadence per ticker.
#    We compute KC/OC on the ANNUAL fiscal series (use Dec-quarter TTM as the fiscal-year flow),
#    then carry the resulting stock forward via PIT Factor_Date.
#    Fiscal year = year of Period_Date; annual flow = TTM ending Q4 (Dec) if available, else latest TTM in year.
annual_flow <- function(ttm_dt, val = "ttm") {
  d <- copy(ttm_dt)
  d[, fyr := as.integer(substr(as.character(Period_Date),1,4))]
  # pick the TTM whose period ends latest in the fiscal year (annual flow)
  setorder(d, Ticker, fyr, Period_Date)
  a <- d[, .SD[.N], by = .(Ticker, fyr)]
  a[, .(Ticker, fyr, flow = get(val), avail = Factor_Date)]
}
rd_a  <- annual_flow(rd_ttm)
sga_a <- annual_flow(sga_ttm)

# perpetual inventory (annual) for a flow series
perp_inv <- function(af, delta, invest_frac = 1.0) {
  af <- copy(af)[is.finite(flow)]
  setorder(af, Ticker, fyr)
  af[, invest := invest_frac * flow]
  af[, stock := {
    s <- numeric(.N)
    if (.N > 0) {
      s[1] <- invest[1] / (G_SS + delta)          # steady-state init
      if (.N > 1) for (i in 2:.N) s[i] <- (1 - delta) * s[i-1] + invest[i]
    }
    s
  }, by = Ticker]
  # amort_t = delta * stock_{t-1} ; prior_stock for iEP
  af[, prior_stock := shift(stock, 1), by = Ticker]
  af[, amort := delta * fifelse(is.finite(prior_stock), prior_stock, stock / (1 - delta) * delta)]
  af
}
kc <- perp_inv(rd_a,  DELTA_RD,  1.0)        # knowledge capital (R&D 100%)
oc <- perp_inv(sga_a, DELTA_SGA, THETA_SGA)  # organizational capital (30% of SG&A)
setnames(kc, c("stock","amort","flow","invest","prior_stock"),
             c("KC","KC_amort","RD_flow","RD_inv","KC_prior"))
setnames(oc, c("stock","amort","flow","invest","prior_stock"),
             c("OC","OC_amort","SGA_flow","SGA_inv","OC_prior"))

# annual intangible table keyed by (Ticker, fyr) with PIT avail (max of KC/OC avail = when both known)
intan_a <- merge(kc[, .(Ticker, fyr, KC, KC_amort, RD_flow, avail_kc = avail)],
                 oc[, .(Ticker, fyr, OC, OC_amort, SGA_flow, avail_oc = avail)],
                 by = c("Ticker","fyr"), all = TRUE)
# PIT availability = when the LATER of the two annual filings is known.
intan_a[, avail := pmax(avail_kc, avail_oc, na.rm = TRUE)]
# where R&D missing (post-2016 cliff): KC=0 (org-capital-only variant), and full variant KC=NA->0 flagged
intan_a[, has_rd := is.finite(KC)]
intan_a[, KC0 := fifelse(is.finite(KC), KC, 0)]
intan_a[, KCamort0 := fifelse(is.finite(KC_amort), KC_amort, 0)]
intan_a[, RD0 := fifelse(is.finite(RD_flow), RD_flow, 0)]
intan_a[, OC0 := fifelse(is.finite(OC), OC, 0)]
intan_a[, OCamort0 := fifelse(is.finite(OC_amort), OC_amort, 0)]
intan_a[, SGA0 := fifelse(is.finite(SGA_flow), SGA_flow, 0)]
intan_a <- intan_a[is.finite(avail)]
setorder(intan_a, Ticker, avail)
cat(sprintf("[intan] annual intangible rows: %d  (has_rd=%.1f%%)\n",
            nrow(intan_a), 100*mean(intan_a$has_rd, na.rm=TRUE))); flush.console()

# =========================================================================
# 4. As-of merge onto month-end t (latest Factor_Date <= t), per ticker.
me_u <- me[in_univ == TRUE & is.finite(MarketCap) & MarketCap > 0,
           .(Ticker, Date = ym, MarketCap, adv20, Ret_1m, Size, Sector)]
setorder(me_u, Ticker, Date)

# intangible stock as-of
ia <- intan_a[, .(Ticker, avail, KC0, KCamort0, RD0, OC0, OCamort0, SGA0, has_rd)]
setkey(ia, Ticker, avail); setkey(me_u, Ticker, Date)
mm <- ia[me_u, on = .(Ticker, avail = Date), roll = TRUE]
setnames(mm, "avail", "Date")

# equity (stock) as-of
eqp <- eq_pit[, .(Ticker, avail = Factor_Date, eq)]
setorder(eqp, Ticker, avail); setkey(eqp, Ticker, avail)
mm <- eqp[mm, on = .(Ticker, avail = Date), roll = TRUE]
setnames(mm, "avail", "Date")

# net income TTM as-of
nip <- ni_ttm[, .(Ticker, avail = Factor_Date, ni = ttm)]
setorder(nip, Ticker, avail); setkey(nip, Ticker, avail)
mm <- nip[mm, on = .(Ticker, avail = Date), roll = TRUE]
setnames(mm, "avail", "Date")

# =========================================================================
# 5. Construct signals.
#   B_adj_full = eq + KC + OC ;  B_adj_orgc = eq + OC (org-capital only, R&D-independent)
mm[, B_adj_full := fifelse(is.finite(eq), eq, NA_real_) + KC0 + OC0]
mm[, B_adj_orgc := fifelse(is.finite(eq), eq, NA_real_) + OC0]

# value signals (higher = cheaper). Require positive book & mktcap.
mm[, stdBM := fifelse(is.finite(eq) & eq > 0, eq / MarketCap, NA_real_)]
mm[, iBM_full := fifelse(is.finite(B_adj_full) & B_adj_full > 0, B_adj_full / MarketCap, NA_real_)]
mm[, iBM_orgc := fifelse(is.finite(B_adj_orgc) & B_adj_orgc > 0, B_adj_orgc / MarketCap, NA_real_)]

# earnings yields. std EP = NI/MktCap. intangible-adj EP adds back intangible investment, subtracts amort.
mm[, stdEP := fifelse(is.finite(ni), ni / MarketCap, NA_real_)]
mm[, iEP_full := fifelse(is.finite(ni),
      (ni + RD0 + THETA_SGA*SGA0 - KCamort0 - OCamort0) / MarketCap, NA_real_)]
mm[, iEP_orgc := fifelse(is.finite(ni),
      (ni + THETA_SGA*SGA0 - OCamort0) / MarketCap, NA_real_)]

# reclassification spread: how much iBM_full re-ranks vs stdBM (cross-sectional, per month rank shift)
# (computed downstream in screen; here just carry raw)

# =========================================================================
# 6. size percentile per month (for large-cap decomposition)
mm[, size_pctile := frank(MarketCap, ties.method="average")/.N, by = Date]  # 1 = largest
mm[, size_rank   := frank(-MarketCap, ties.method="first"), by = Date]      # 1 = largest

# intangible intensity per ticker (for orthogonality / reclassification diagnostics)
mm[, intan_intensity := fifelse(is.finite(eq) & eq > 0, (KC0 + OC0) / eq, NA_real_)]

scores <- mm[, .(Date, Ticker, MarketCap, adv20, Sector, size_pctile, size_rank,
                 eq, ni, KC0, OC0, RD0, SGA0, has_rd, intan_intensity,
                 stdBM, iBM_full, iBM_orgc, stdEP, iEP_full, iEP_orgc,
                 B_adj_full, B_adj_orgc)]

# =========================================================================
# 7. returns / universe / benchmarks — cap-w (float) + EW, FRESH from universe (RAMP R1 learning:
#    do NOT rely solely on rawdata.BM_Ret; compute cap-w from universe float-cap weights).
returns_monthly <- me[!is.na(Ret_1m) & in_univ == TRUE, .(Date = ym, Ticker, Ret_1m, MCap_ff)]
universe_flags  <- me[in_univ == TRUE, .(Date = ym, Ticker, adv20, Size, MarketCap, MCap_ff)]

# cap-w benchmark: float-cap-weighted forward return of the universe (weights at t, return t->t+1)
bm_capw <- returns_monthly[is.finite(Ret_1m) & is.finite(MCap_ff) & MCap_ff > 0,
                           .(BM_Ret = sum(MCap_ff * Ret_1m) / sum(MCap_ff)), by = Date]
# EW benchmark: equal-weighted universe forward return
bm_ew   <- returns_monthly[is.finite(Ret_1m), .(BM_Ret = mean(Ret_1m, na.rm=TRUE)), by = Date]

# also carry rawdata BM_Ret (K200 cap-w official) fwd for cross-check
bmraw <- unique(rd[!is.na(BM_Ret), .(Date, ym, BM_Ret)], by = "Date")
bmraw_m <- bmraw[, .(bm_mret = prod(1 + BM_Ret) - 1), by = ym]
setorder(bmraw_m, ym); bmraw_m[, BM_Ret_fwd := shift(bm_mret, -1)]
bm_raw <- bmraw_m[!is.na(BM_Ret_fwd), .(Date = ym, BM_Ret = BM_Ret_fwd)]

# ---- write ----
write_parquet(scores,          file.path(OUT, "intan_scores_monthly.parquet"))
write_parquet(returns_monthly, file.path(OUT, "returns_monthly.parquet"))
write_parquet(bm_capw,         file.path(OUT, "benchmark_capw.parquet"))
write_parquet(bm_ew,           file.path(OUT, "benchmark_ew.parquet"))
write_parquet(bm_raw,          file.path(OUT, "benchmark_raw.parquet"))
write_parquet(universe_flags,  file.path(OUT, "universe_flags.parquet"))

cat(sprintf("[intan] scores: %d rows / %d months (%s..%s)\n",
    nrow(scores), uniqueN(scores$Date), as.character(min(scores$Date)), as.character(max(scores$Date))))
for (s in c("stdBM","iBM_full","iBM_orgc","stdEP","iEP_full","iEP_orgc")) {
  cat(sprintf("[intan]   %-10s non-NA=%d\n", s, sum(is.finite(scores[[s]]))))
}
# coverage post-2017 sanity
p17 <- scores[Date >= as.Date("2017-01-01")]
cat(sprintf("[intan] POST-2017: months=%d  iBM_orgc non-NA=%d  iBM_full non-NA=%d  has_rd frac=%.2f\n",
    uniqueN(p17$Date), sum(is.finite(p17$iBM_orgc)), sum(is.finite(p17$iBM_full)),
    mean(p17$has_rd, na.rm=TRUE)))
cat("[intan] DONE\n")
