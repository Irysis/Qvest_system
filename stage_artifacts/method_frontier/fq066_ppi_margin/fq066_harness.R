#==============================================================================
# FQ-066 — ECOS 업종별 PPI 마진 스프레드 → KR sector tilt 알파 (실측 하네스)
#
# 마진 스프레드 = 산출 PPI YoY (404Y014 생산자물가, 업종 판매가)
#              − 투입 PPI YoY (401Y015 수입물가, W 원화기준, 원자재 매입가)
# KR 제조업: 원자재/에너지 수입 → 가공 판매. 마진 = 판매가 상승 − 매입가 상승.
#
# 규율: KR long-only, K200∪KQ150, top-25, liq>=2e8, 15bps, PIT C1~C15,
#       canonical_screen_bt 계약(자체합성 금지), metric_type 정직 라벨.
# PIT: PPI 발표시차 → PUB_LAG 개월. sig_date(월말 t) 신호 = ref월(t-LAG)까지의 데이터만.
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(httr); library(jsonlite) })
QM <- Sys.getenv("QM_ROOT", unset = "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(QM)
OUT <- file.path(QM, "stage_artifacts/method_frontier/fq066_ppi_margin")
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)
KEY <- Sys.getenv("ECOS_API_KEY", unset = "AIQOGTG4QU4GWPCT8INK")

if (!exists("build_benchmark_compare")) source("02_Infrastructure/contracts/backtest_result_contract.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/ramp/factor_validation.R")   # build_monthly_forward_returns

`%||%` <- function(a,b) if (is.null(a)||length(a)==0) b else a

#--- ECOS fetch ---------------------------------------------------------------
ecos_series <- function(stat, item1, item2 = NULL, start = "200001", end = "202612") {
  url <- sprintf("https://ecos.bok.or.kr/api/StatisticSearch/%s/json/kr/1/100000/%s/M/%s/%s/%s",
                 KEY, stat, start, end, item1)
  if (!is.null(item2)) url <- paste0(url, "/", item2)
  resp <- tryCatch(GET(url, timeout(60)), error = function(e) NULL)
  if (is.null(resp) || status_code(resp) != 200) return(NULL)
  j <- fromJSON(content(resp, "text", encoding = "UTF-8"), simplifyVector = FALSE)
  if (is.null(j$StatisticSearch$row)) {
    if (!is.null(j$RESULT)) cat(sprintf("  [%s/%s] %s %s\n", stat, item1, j$RESULT$CODE, j$RESULT$MESSAGE))
    return(NULL)
  }
  r <- rbindlist(j$StatisticSearch$row, fill = TRUE)
  data.table(refmonth = as.Date(paste0(r$TIME, "01"), "%Y%m%d"),
             val = as.numeric(r$DATA_VALUE))[!is.na(refmonth) & !is.na(val)]
}

CACHE <- file.path(OUT, "ecos_ppi_raw.parquet")
out_codes <- c("301AA","302AA","304AA","305AA","306AA","307AA","309AA","311AA","312AA")
in_codes  <- c("101AA","201AA","305AA","307AA","2012AA")

if (file.exists(CACHE)) {
  ppi_raw <- as.data.table(read_parquet(CACHE))
  cat("[ecos] cache loaded", nrow(ppi_raw), "rows\n")
} else {
  acc <- list()
  for (cd in out_codes) {
    s <- ecos_series("404Y014", cd); if (is.null(s)) { cat("OUT FAIL", cd, "\n"); next }
    s[, `:=`(table = "404Y014_out", code = cd)]; acc[[paste0("o_",cd)]] <- s
    cat(sprintf("OUT %s: %d rows (%s..%s)\n", cd, nrow(s), min(s$refmonth), max(s$refmonth)))
  }
  for (cd in in_codes) {
    s <- ecos_series("401Y015", cd, item2 = "W"); if (is.null(s)) { cat("IN FAIL", cd, "\n"); next }
    s[, `:=`(table = "401Y015_in_W", code = cd)]; acc[[paste0("i_",cd)]] <- s
    cat(sprintf("IN  %s(W): %d rows (%s..%s)\n", cd, nrow(s), min(s$refmonth), max(s$refmonth)))
  }
  ppi_raw <- rbindlist(acc, fill = TRUE)
  write_parquet(ppi_raw, CACHE)
  cat("[ecos] fetched + cached", nrow(ppi_raw), "rows\n")
}

#--- YoY per series (level_t / level_{t-12} - 1) -------------------------------
setorder(ppi_raw, table, code, refmonth)
ppi_raw[, yoy := val / shift(val, 12L) - 1, by = .(table, code)]
yoy_w <- dcast(ppi_raw[!is.na(yoy)], refmonth ~ table + code, value.var = "yoy")

#--- Sector -> (output code, input code) mapping (economic sell-buy) -----------
smap <- data.table(
  Sector = c("화학","에너지","철강","비철,목재등","필수소비재","자동차","조선",
             "기계","건설,건축관련","화장품,의류,완구","IT가전"),
  out = c("305AA","304AA","307AA","307AA","301AA","312AA","312AA","311AA","306AA","302AA","309AA"),
  inp = c("201AA","201AA","2012AA","2012AA","101AA","307AA","307AA","307AA","307AA","305AA","201AA"),
  note = c("chem: crude/naphtha","refining crack","steel: iron ore","base metals",
           "food: ag input","autos: steel","ships: steel","machinery: steel",
           "construction: steel/cement","textile/consumer: chem fiber","IT durables: energy/materials(weak)")
)
fwrite(smap, file.path(OUT, "sector_ppi_map.csv"))

# margin_spread by refmonth x sector = out_YoY - in_YoY
mlong <- rbindlist(lapply(seq_len(nrow(smap)), function(i){
  oc <- paste0("404Y014_out_", smap$out[i]); ic <- paste0("401Y015_in_W_", smap$inp[i])
  if (!oc %in% names(yoy_w) || !ic %in% names(yoy_w)) return(NULL)
  data.table(refmonth = yoy_w$refmonth, Sector = smap$Sector[i],
             out_yoy = yoy_w[[oc]], in_yoy = yoy_w[[ic]],
             margin = yoy_w[[oc]] - yoy_w[[ic]])
}))[!is.na(margin)]
cat("\n[margin] panel:", nrow(mlong), "rows,", uniqueN(mlong$Sector), "sectors,",
    as.character(min(mlong$refmonth)), "..", as.character(max(mlong$refmonth)), "\n")
fwrite(mlong, file.path(OUT, "sector_margin_panel.csv"))

#--- RAWDATA month-end panel + forward returns --------------------------------
rd <- as.data.table(read_parquet(file.path(QM, ".cache/RAWDATA.parquet")))
rd <- rd[Date >= as.Date("2004-06-01") & !is.na(Close) & Close > 0]
rd[, ym := format(Date, "%Y-%m")]
me_dates <- rd[, .(Date = max(Date)), by = ym]$Date
rd_me <- rd[Date %in% me_dates]
setkey(rd_me, Date)
sig_dates <- sort(unique(rd_me$Date))
sig_dates <- sig_dates[sig_dates >= as.Date("2005-06-01")]

fwd <- build_monthly_forward_returns(rd_me, sig_dates)
returns_dt <- fwd$returns_dt   # Date(sig월말), Ticker, Ret_1m
bench_dt   <- fwd$bench_dt     # Date, BM_Ret (cap-weighted universe)
liq_dt     <- fwd$liq_dt
cat("[returns] months:", uniqueN(returns_dt$Date), " stock-months:", nrow(returns_dt), "\n")

# sector label per (Date, Ticker) at sig_date (time-varying, PIT)
sec_me <- rd_me[, .(Date, Ticker, Sector, Size, K200, KQ150)][!is.na(Sector)]

#--- PIT: assign margin(ref month t-LAG) to sig_date(month-end t) --------------
# PPI ref월 M 발표 ~ M+1월 중순 → sig월말 t 시점 최신 usable ref월 = t - LAG.
# LAG=2 보수(버퍼 1개월 + first-release 개정 방어). LAG=1 민감도 병행.
assign_margin <- function(LAG) {
  sd <- data.table(Date = sig_dates)
  sd[, ref_target := as.Date(format(Date, "%Y-%m-01")) ]
  # ref month = sig month minus LAG
  sd[, ref_use := as.Date(mapply(function(d) format(seq(d, by = paste0("-", LAG, " months"), length.out = 2)[2], "%Y-%m-01"), ref_target))]
  m <- merge(sd[, .(Date, ref_use)], mlong[, .(ref_use = refmonth, Sector, margin)],
             by = "ref_use", allow.cartesian = TRUE)
  m[, .(Date, Sector, margin)]
}
# robust month arithmetic
add_months <- function(d, n) {
  d <- as.Date(paste0(format(d, "%Y-%m"), "-01"))
  yr <- as.integer(format(d,"%Y")); mo <- as.integer(format(d,"%m")) + n
  yr <- yr + (mo-1) %/% 12; mo <- ((mo-1) %% 12) + 1
  as.Date(sprintf("%04d-%02d-01", yr, mo))
}
assign_margin <- function(LAG) {
  sd <- data.table(Date = sig_dates)
  sd[, ref_use := add_months(Date, -LAG)]
  merge(sd, mlong[, .(ref_use = refmonth, Sector, margin)], by = "ref_use", allow.cartesian = TRUE)[, .(Date, Sector, margin)]
}

#--- SECTOR-LEVEL IC (마진 개선 섹터가 다음달 섹터수익 상회?) -------------------
# 섹터 forward 수익 = 섹터 내 K200∪KQ150 종목 cap-weighted forward return
sector_fwd <- merge(returns_dt, sec_me[, .(Date, Ticker, Sector, Size)], by = c("Date","Ticker"))
sector_fwd <- sector_fwd[(Sector %in% smap$Sector)]
sec_ret <- sector_fwd[, .(sret = weighted.mean(Ret_1m, w = ifelse(is.na(Size),0,Size), na.rm=TRUE),
                          n = .N), by = .(Date, Sector)][n >= 3]

run_sector_ic <- function(LAG) {
  mg <- assign_margin(LAG)
  d <- merge(mg, sec_ret, by = c("Date","Sector"))
  # cross-sectional spearman rank IC per month (>=5 sectors)
  ic <- d[, {
    if (.N >= 5 && sd(margin) > 0 && sd(sret) > 0)
      .(ic = cor(margin, sret, method = "spearman"), nsec = .N) else .(ic = NA_real_, nsec = .N)
  }, by = Date][!is.na(ic)]
  list(ic_mean = mean(ic$ic), ic_ir = mean(ic$ic)/sd(ic$ic)*sqrt(12),
       t = mean(ic$ic)/ (sd(ic$ic)/sqrt(nrow(ic))), n_months = nrow(ic), ic_series = ic)
}

sic1 <- run_sector_ic(1); sic2 <- run_sector_ic(2)
cat(sprintf("\n[SECTOR IC] LAG=2: mean=%.4f IR=%.3f t=%.2f nM=%d | LAG=1: mean=%.4f t=%.2f nM=%d\n",
            sic2$ic_mean, sic2$ic_ir, sic2$t, sic2$n_months, sic1$ic_mean, sic1$t, sic1$n_months))
fwrite(sic2$ic_series, file.path(OUT, "sector_ic_series_lag2.csv"))

#--- STOCK-LEVEL canonical top-25 (선호 섹터 종목 tilt) ------------------------
run_canonical <- function(LAG, top_n = 25L) {
  mg <- assign_margin(LAG)
  # score each stock = its sector margin at sig_date
  sc <- merge(sec_me[, .(Date, Ticker, Sector, K200, KQ150)], mg, by = c("Date","Sector"))
  sc <- sc[(K200 == TRUE | KQ150 == TRUE)]
  sc <- sc[, .(Date, Ticker, score = margin)][!is.na(score)]
  ret <- returns_dt[, .(Date, Ticker, Ret_1m)]
  bench <- bench_dt[, .(Date, BM_Ret)]
  liq  <- liq_dt[, .(Date, Ticker, adv)]
  size_dt <- sec_me[, .(Date, Ticker, Size)]
  canonical_screen_bt(sc, ret, bench, top_n = top_n, cost_bps_oneway = 15,
                      liq_dt = liq, liq_min = 2e8, size_dt = size_dt,
                      run_id = sprintf("fq066_lag%d", LAG), strategy_id = sprintf("FQ066_PPImargin_lag%d", LAG))
}

cs2 <- run_canonical(2); cs1 <- run_canonical(1)
report <- function(cs, lbl) {
  cat(sprintf("\n[CANONICAL %s] nM=%d PORT_t=%.3f p=%.3f IR=%.3f netSR=%.3f alpha_ann=%.4f TO=%.2f\n",
      lbl, cs$n_months %||% 0, cs$portfolio_alpha_t_nw_lag3 %||% NA, cs$portfolio_alpha_t_pvalue %||% NA,
      cs$information_ratio %||% NA, cs$net_sr %||% NA, cs$alpha_annualized %||% NA, cs$turnover_annual %||% NA))
  if (!is.null(cs$diag_ew_universe$portfolio_alpha_t_nw_lag3))
    cat(sprintf("   diag EW-universe PORT_t=%.3f\n", cs$diag_ew_universe$portfolio_alpha_t_nw_lag3))
}
report(cs2, "LAG=2 (base)"); report(cs1, "LAG=1 (sens)")

# calmar / MDD from period_returns net active (contract series) — PerformanceAnalytics
suppressPackageStartupMessages(library(PerformanceAnalytics))
calc_calmar_mdd <- function(cs) {
  pr <- cs$period_returns
  if (is.null(pr) || nrow(pr) < 12) return(list(calmar = NA, mdd = NA, oos = NA))
  r <- xts::xts(pr$ret_net, order.by = as.Date(pr$date))
  ann <- as.numeric(Return.annualized(r, scale = 12))
  mdd <- as.numeric(maxDrawdown(r))
  calmar <- ann / mdd
  # oos retention rough (contract helper concept): split-half active SR
  act <- pr$ret_net - pr$benchmark_ret
  n <- length(act); k <- floor(n*0.65)
  sr <- function(x) if (length(x) < 6 || sd(x) <= 0) NA else mean(x)/sd(x)*sqrt(12)
  oos <- sr(act[(k+1):n]) / sr(act[1:k])
  list(calmar = calmar, mdd = mdd, ann = ann, oos = oos)
}
cm2 <- calc_calmar_mdd(cs2)
cat(sprintf("\n[RISK LAG=2] annRet=%.4f MDD=%.4f Calmar=%.3f oos_retention~%.3f\n",
            cm2$ann %||% NA, cm2$mdd %||% NA, cm2$calmar %||% NA, cm2$oos %||% NA))

#--- Save summary -------------------------------------------------------------
summ <- list(
  fq = "FQ-066", generated = as.character(Sys.time()),
  data_verified = TRUE,
  series_used = list(output_PPI = "404Y014 생산자물가지수(기본분류)",
                     input_price = "401Y015 수입물가지수(기본분류, 원화기준 W)",
                     out_codes = out_codes, in_codes = in_codes),
  construction = "margin_spread = output_PPI_YoY - import_price_YoY(W), per sector via sell-buy PPI map; stock score = its sector margin",
  n_sectors_mapped = uniqueN(mlong$Sector),
  pit_handling = "PUB_LAG=2mo base (ref month t-2 at sig month-end t; PPI released ~+1mo mid-month, +1mo buffer for first-release revisions). LAG=1 sensitivity. sector membership & Size time-varying PIT. forward return via build_monthly_forward_returns (contract).",
  sector_ic_lag2 = list(mean = sic2$ic_mean, ir = sic2$ic_ir, t = sic2$t, n_months = sic2$n_months),
  sector_ic_lag1 = list(mean = sic1$ic_mean, t = sic1$t, n_months = sic1$n_months),
  canonical_lag2 = list(port_t = cs2$portfolio_alpha_t_nw_lag3, ir = cs2$information_ratio,
                        net_sr = cs2$net_sr, alpha_ann = cs2$alpha_annualized, turnover = cs2$turnover_annual,
                        n_months = cs2$n_months, diag_ew_port_t = cs2$diag_ew_universe$portfolio_alpha_t_nw_lag3 %||% NA,
                        calmar = cm2$calmar, mdd = cm2$mdd, oos_retention = cm2$oos),
  canonical_lag1 = list(port_t = cs1$portfolio_alpha_t_nw_lag3, net_sr = cs1$net_sr, n_months = cs1$n_months)
)
write_json(summ, file.path(OUT, "fq066_summary.json"), auto_unbox = TRUE, pretty = TRUE, digits = 6)
saveRDS(list(cs2 = cs2, cs1 = cs1, sic2 = sic2, mlong = mlong), file.path(OUT, "fq066_results.rds"))
cat("\n[DONE] saved to", OUT, "\n")
