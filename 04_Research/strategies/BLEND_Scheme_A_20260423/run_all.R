cat("=== BLEND_Scheme_A: 3-sleeve blend Core60+Div17+Def23 | LIQ_THRESHOLD <- 2e8 ===\n")
## 핵심아이디어: STR_1631(60%) + STR_1656(17%) + STR_1689(23%)
##   Cross-section Z-score weighted → top 20 EW monthly rebalance
##   C10: LIQ_THRESHOLD <- 2e8, 20d rolling mean frollmean (t-1 lag)
QEPM_AUTO_COMMIT <- TRUE
LIQ_THRESHOLD <- 2e8
N_HOLDINGS    <- 20L
COMMISSION    <- 0.0015
W_1631 <- 0.60; W_1656 <- 0.17; W_1689 <- 0.23
BLEND_START <- as.Date("2008-01-01")
BLEND_END   <- as.Date("2025-12-31")

suppressPackageStartupMessages({
  library(data.table); library(ggplot2); library(jsonlite)
})

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
STRATEGY_DIR <- file.path(PROJECT_ROOT, "04_Research/strategies/BLEND_Scheme_A_20260423")
OUTPUT_DIR   <- file.path(STRATEGY_DIR, "output")
dir.create(OUTPUT_DIR, showWarnings=FALSE, recursive=TRUE)

source(file.path(PROJECT_ROOT, "02_Infrastructure/config.R"))
source(file.path(PROJECT_ROOT, "02_Infrastructure/backtest_harness.R"))
source(file.path(PROJECT_ROOT, "02_Infrastructure/validation/preflight_memory.R"))
tryCatch(preflight_check("BLEND_Scheme_A_20260423", family="blend_multi_sleeve"),
         error=function(e) cat("[preflight] skipped:", conditionMessage(e), "\n"))

# ── 1. RAWDATA ────────────────────────────────────────────────────────────────
cat("[1] RAWDATA 로드...\n")
rw <- load_rawdata(use_cache=TRUE)
RAWDATA <- rw$RAWDATA; BM_DT <- rw$BM_DT
setDT(RAWDATA); setkey(RAWDATA, Date, Ticker)

# C10: 20일 평균 거래대금 >= LIQ_THRESHOLD (frollmean, t-1 lag)
if (!"LiqPass" %in% names(RAWDATA)) {
  RAWDATA[, AvgTV20 := frollmean(shift(Size, 1L, type="lag"), n=20L,
                                  algo="exact", na.rm=TRUE), by=Ticker]
  RAWDATA[, LiqPass := (!is.na(AvgTV20) & AvgTV20 >= LIQ_THRESHOLD)]
}
cat(sprintf("    %s rows | %s ~ %s\n",
            format(nrow(RAWDATA), big.mark=","), min(RAWDATA$Date), max(RAWDATA$Date)))

# ── 2. STR_1631 score ─────────────────────────────────────────────────────────
cat("[2] STR_1631 score (factors_detail.csv)...\n")
sc1631 <- fread(file.path(PROJECT_ROOT,
  "04_Research/strategies/STR_1631_SYN_05_2002/output/factors_detail.csv"))
setnames(sc1631, c("Date","Ticker","Score"))
sc1631[, Date := as.Date(Date)]
sc1631 <- sc1631[Date >= BLEND_START & Date <= BLEND_END]
cat(sprintf("    %d rows | %s ~ %s\n", nrow(sc1631), min(sc1631$Date), max(sc1631$Date)))

# ── 3. STR_1656 score ─────────────────────────────────────────────────────────
cat("[3] STR_1656 score (s5_scores_B.csv)...\n")
sc1656r <- fread(file.path(PROJECT_ROOT,
  "04_Research/strategies/STR_1656_MLRA/output/s5_scores_B.csv"))
if (ncol(sc1656r) == 4L) { setnames(sc1656r, c("Date","Ticker","Size","Score"))
} else                   { setnames(sc1656r, c("Date","Ticker","Score")) }
sc1656 <- sc1656r[, .(Date=as.Date(Date), Ticker, Score)]
sc1656 <- sc1656[Date >= BLEND_START & Date <= BLEND_END]
cat(sprintf("    %d rows | %s ~ %s\n", nrow(sc1656), min(sc1656$Date), max(sc1656$Date)))

# ── 4. STR_1689 score (factor_engine inline: Q01+Q04+Q25 3-axis) ──────────────
cat("[4] STR_1689 factor score (Q01+Q04+Q25 inline)...\n")
source(file.path(PROJECT_ROOT, "02_Infrastructure/factor_db/factor_db_connector.R"))

sig_dates_1689 <- RAWDATA[Date >= BLEND_START & Date <= BLEND_END,
  .(sig_date=max(Date)), by=.(ym=format(Date,"%Y-%m"))][, sort(sig_date)]
req_fac <- c("Q01_GPA","Q04_Piotroski_F","Q25_Ohlson_O")

FDB1689 <- rbindlist(lapply(sig_dates_1689, function(sd) {
  dt <- tryCatch(load_month_factors(sd), error=function(e) NULL)
  if (is.null(dt) || nrow(dt)==0L) return(NULL)
  dt <- dt[Factor_Name %in% req_fac]; if (nrow(dt)==0L) return(NULL)
  dt[, Date:=sd]; dt
}), use.names=TRUE, fill=TRUE)

if (!is.null(FDB1689) && nrow(FDB1689) > 0L) {
  setkey(FDB1689, Date, Ticker)
  LIQ1689 <- RAWDATA[Date %in% sig_dates_1689 & LiqPass==TRUE, .(Date,Ticker)]
  WD <- dcast(FDB1689, Date+Ticker~Factor_Name, value.var="Z_Score_Aligned", fill=NA_real_)
  setkey(WD, Date, Ticker)
  WD <- WD[LIQ1689, on=c("Date","Ticker"), nomatch=NULL]
  rm(FDB1689); gc(verbose=FALSE)

  q01c <- grep("Q01_GPA",       names(WD), value=TRUE)[1L]
  q04c <- grep("Q04_Piotroski", names(WD), value=TRUE)[1L]
  q25c <- grep("Q25_Ohlson",    names(WD), value=TRUE)[1L]

  wsz <- function(x) {
    q <- quantile(x, c(0.01,0.99), na.rm=TRUE)
    xw <- pmax(pmin(x,q[2L]),q[1L]); m <- mean(xw,na.rm=TRUE); s <- sd(xw,na.rm=TRUE)
    if (is.na(s)||s<1e-10) x else (xw-m)/s
  }
  if (!is.na(q01c)) WD[, z_Q01:=wsz(get(q01c)), by=Date]
  if (!is.na(q04c)) WD[, z_Q04:=wsz(get(q04c)), by=Date]
  if (!is.na(q25c)) WD[, z_Q25:=wsz(get(q25c)), by=Date]
  WD[, cv1 := 0.33*z_Q01 + 0.33*z_Q04 + 0.34*z_Q25]
  sc1689 <- WD[!is.na(cv1), .(Date, Ticker, Score=cv1)]
  cat(sprintf("    %d rows | %s ~ %s\n", nrow(sc1689), min(sc1689$Date), max(sc1689$Date)))
} else {
  cat("    [WARN] FDB1689 empty — defense sleeve skipped\n")
  sc1689 <- data.table(Date=as.Date(character()), Ticker=character(), Score=numeric())
  W_1689 <- 0; W_1631 <- W_1631/(W_1631+W_1656); W_1656 <- 1-W_1631
}

# ── 5. 공통 dates ────────────────────────────────────────────────────────────
common_dates <- sort(as.Date(Reduce(intersect, list(
  as.character(unique(sc1631$Date)),
  as.character(unique(sc1656$Date)),
  as.character(unique(sc1689$Date))
))))
cat(sprintf("[5] 공통 dates: %d | %s ~ %s\n",
            length(common_dates), min(common_dates), max(common_dates)))

# ── 6. Cross-section Z-score + blend ─────────────────────────────────────────
xcs <- function(dt, zcol) {
  d2 <- dt[Date %in% common_dates]
  d2[, (zcol) := {
    x <- Score; q <- quantile(x,c(0.01,0.99),na.rm=TRUE)
    xw <- pmax(pmin(x,q[2L]),q[1L]); m <- mean(xw,na.rm=TRUE); s <- sd(xw,na.rm=TRUE)
    if (is.na(s)||s<1e-10) x else (xw-m)/s
  }, by=Date]
  d2[, .(Date, Ticker, z=get(zcol))]
}
z1 <- xcs(sc1631,"z1631"); setnames(z1,"z","z_1631")
z2 <- xcs(sc1656,"z1656"); setnames(z2,"z","z_1656")
z3 <- xcs(sc1689,"z1689"); setnames(z3,"z","z_1689")

SC <- merge(z1, z2, by=c("Date","Ticker"), all=FALSE)
SC <- merge(SC, z3, by=c("Date","Ticker"), all=FALSE)
LIQ_BLD <- RAWDATA[Date %in% common_dates & LiqPass==TRUE, .(Date,Ticker)]
SC <- SC[LIQ_BLD, on=c("Date","Ticker"), nomatch=NULL]
SC[, Z_combined := W_1631*z_1631 + W_1656*z_1656 + W_1689*z_1689]
cat(sprintf("[6] Combined: %d rows | %d dates\n", nrow(SC), uniqueN(SC$Date)))

FACTORS_BLEND <- SC[!is.na(Z_combined), .(Date, Ticker, Score=Z_combined)]
setkey(FACTORS_BLEND, Date, Ticker)

# ── 7. Simulation ─────────────────────────────────────────────────────────────
cat("[7] Backtest (EW N=20 comm=15bps)...\n")
options(mc.cores=1L)
sim <- run_monthly_simulation(RAWDATA, BM_DT, FACTORS_BLEND,
  n_holdings=N_HOLDINGS, commission=COMMISSION, weight_method="ew")

# ── 8. 성과 ───────────────────────────────────────────────────────────────────
perf <- summarise_perf(sim, BM_DT)
cat(sprintf("\nCAGR %.2f%% | SR %.3f | MDD %.2f%% | TO %.0f%%\n",
            perf$CAGR*100, perf$Sharpe, perf$MDD*100, perf$Turnover*100))

# ── 9. Stress ─────────────────────────────────────────────────────────────────
navd <- setDT(copy(sim$daily_nav))
if ("nav"  %in% names(navd)) setnames(navd,"nav","NAV")
if ("date" %in% names(navd)) setnames(navd,"date","Date")
navd[, Date:=as.Date(Date)]

slist <- list(
  list("GFC_2008","2008-09-01","2009-03-31"),
  list("EU_Crisis","2011-07-01","2011-12-31"),
  list("EM_Selloff","2015-06-01","2016-02-29"),
  list("COVID_2020","2020-02-01","2020-05-31"),
  list("Rate_Hike","2022-01-01","2022-12-31")
)
stress_res <- rbindlist(lapply(slist, function(s) {
  sub <- navd[Date>=as.Date(s[[2]]) & Date<=as.Date(s[[3]])]
  if (nrow(sub)<5L) return(data.table(Period=s[[1]], Ret_pct=NA_real_))
  data.table(Period=s[[1]], Ret_pct=round((sub$NAV[.N]/sub$NAV[1]-1)*100,2))
}))
fwrite(stress_res, file.path(OUTPUT_DIR,"analysis_stress.csv"))
print(stress_res)

# ── 10. 차트 ─────────────────────────────────────────────────────────────────
p1 <- ggplot(navd, aes(x=Date, y=NAV/1e8)) +
  geom_line(color="#1f77b4", linewidth=0.8) +
  labs(title="BLEND_Scheme_A Equity Curve (Core60+Div17+Def23)", x=NULL, y="NAV (억원)") +
  theme_minimal()
ggsave(file.path(OUTPUT_DIR,"equity_curve.png"), p1, width=12, height=5, dpi=120)

navd[, Year:=as.integer(format(Date,"%Y"))]
ar <- navd[, .(ar=(NAV[.N]/NAV[1])^(252/.N)-1), by=Year]
p2 <- ggplot(ar, aes(x=factor(Year), y=ar*100, fill=ar>=0)) +
  geom_col(show.legend=FALSE) +
  scale_fill_manual(values=c("TRUE"="#2ca02c","FALSE"="#d62728")) +
  labs(title="Annual Returns", x=NULL, y="%") + theme_minimal() +
  theme(axis.text.x=element_text(angle=45, hjust=1))
ggsave(file.path(OUTPUT_DIR,"annual_returns.png"), p2, width=12, height=5, dpi=120)

# ── 11. Holdings ──────────────────────────────────────────────────────────────
if (!is.null(sim$holdings_log))
  fwrite(rbindlist(sim$holdings_log, fill=TRUE), file.path(OUTPUT_DIR,"monthly_holdings.csv"))

# ── 12. JSON ─────────────────────────────────────────────────────────────────
write_json(list(
  strategy_id="BLEND_Scheme_A_20260423", strategy_type="blend_multi_sleeve",
  blend_weights=list(STR_1631=W_1631,STR_1656=W_1656,STR_1689=W_1689),
  period=list(start=as.character(min(common_dates)),end=as.character(max(common_dates))),
  CAGR=round(perf$CAGR,4), Sharpe=round(perf$Sharpe,4),
  MDD=round(perf$MDD,4), Turnover=round(perf$Turnover,4),
  N_holdings=N_HOLDINGS, commission=COMMISSION, timestamp=as.character(Sys.time())
), file.path(OUTPUT_DIR,"hurdle_result.json"), auto_unbox=TRUE, pretty=TRUE)

write_json(list(
  artifact_type="blended_backtest", strategy_id="BLEND_Scheme_A_20260423",
  sleeves=list(
    list(id="STR_1631_SYN_05_2002", role="core",           weight=W_1631),
    list(id="STR_1656_MLRA_s5_B",   role="ml_diversifier", weight=W_1656),
    list(id="STR_1689_v3_var1",     role="defense",        weight=W_1689)
  ),
  combination_method="cross_section_zscore_weighted", n_holdings=N_HOLDINGS,
  common_period=list(start=as.character(min(common_dates)),end=as.character(max(common_dates))),
  performance=list(CAGR=round(perf$CAGR,4),Sharpe=round(perf$Sharpe,4),
                   MDD=round(perf$MDD,4),Turnover=round(perf$Turnover,4)),
  timestamp=as.character(Sys.time())
), file.path(STRATEGY_DIR,"stage_artifacts","blended_backtest_scheme_A_20260423.json"),
   auto_unbox=TRUE, pretty=TRUE)

# ── mailbox ───────────────────────────────────────────────────────────────────
mbdone <- file.path(PROJECT_ROOT,"qepm/mailbox/forge/done")
dir.create(mbdone, showWarnings=FALSE, recursive=TRUE)
write_json(list(
  task="DONE_BLEND_A_20260423", strategy_id="BLEND_Scheme_A_20260423",
  result=sprintf("CAGR %.2f%% / SR %.3f / MDD %.2f%% / TO %.0f%%",
                  perf$CAGR*100,perf$Sharpe,perf$MDD*100,perf$Turnover*100),
  timestamp=as.character(Sys.time())
), file.path(mbdone,"DONE_BLEND_A_20260423.json"), auto_unbox=TRUE, pretty=TRUE)

cat("=== BLEND_Scheme_A 완료 ===\n")
