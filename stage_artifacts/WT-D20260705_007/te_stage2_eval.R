#!/usr/bin/env Rscript
# =============================================================================
# te_stage2_eval.R — WT-D20260705_007 Stage 2
# TE net-sink 신호 -> 중립화(raw/residual) -> canonical PORT_t + 진단.
#   canonical_screen_bt 경유 실측(metric_type=canonical_screen).
# 입력: te_netsink_raw.rds (Date,Ticker,Score) + pinned RAWDATA/BM.
# =============================================================================
suppressWarnings(suppressMessages({
  library(data.table); library(arrow); library(dplyr); library(jsonlite)
}))
data.table::setDTthreads(2L)
try(arrow::set_cpu_count(2L), silent = TRUE)
.flog <- function(...) { cat(sprintf(...), file = stderr()); flush(stderr()) }
`%||%` <- function(a,b) if (is.null(a)||length(a)==0||(length(a)==1&&is.na(a))) b else a

PROJ  <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
CACHE <- file.path(PROJ, ".cache")
OUT   <- file.path(PROJ, "stage_artifacts", "WT-D20260705_007")

source(file.path(PROJ, "02_Infrastructure", "contracts", "canonical_screen_bt.R"))

FAC <- readRDS(file.path(OUT, "te_netsink_raw.rds"))
setDT(FAC); FAC[, Date := as.Date(Date)]
cat(sprintf("[s2] raw signal rows=%d dates=%d\n", nrow(FAC), uniqueN(FAC$Date)))

# ---- RAWDATA (중립화 특성 + forward 1M 수익) ----
RAWDATA <- open_dataset(file.path(CACHE, "RAWDATA_pin20260703.parquet")) %>%
  filter(Date >= as.Date("2003-06-01")) %>%
  select(Date, Ticker, K200, KQ150, Sector_Lv2, Size, Close, Vol, Ret) %>%
  collect() %>% as.data.table()
RAWDATA[, Date := as.Date(Date)]
setorder(RAWDATA, Ticker, Date)
.flog("[s2] RAWDATA rows=%d\n", nrow(RAWDATA))
RAWDATA[, TradingValue := Close * Vol]
RAWDATA[, AvgTV20 := frollmean(TradingValue, 20L, align = "right"), by = Ticker]

# 월말 달력 + forward 1M 수익 (sig_date t -> t+1 월 실현)
RAWDATA[, ym := format(Date, "%Y-%m")]
cal <- RAWDATA[, .(MEnd = max(Date)), by = ym]; setorder(cal, MEnd)
cal[, nxt_ym := shift(ym, 1L, type = "lead")]
MR <- RAWDATA[is.finite(Ret), .(MRet = prod(1 + Ret) - 1), by = .(Ticker, ym)]

# sig_date 시점 종목 특성 (PIT: 그 달의 값)
# beta: trailing 60일 시장(BM) 회귀 β — 여기선 간이(월간수익 vs 시장 월간수익 롤링). 대체로 size/sector/vol 중립화가 핵심.
# vol: trailing 20d 일간수익 표준편차(연율화 아님, 횡단면 rank용)
RAWDATA[, ret_vol20 := frollapply(Ret, 20L, sd, align = "right"), by = Ticker]
me_feat <- RAWDATA[Date %in% cal$MEnd,
                   .(Date, Ticker, Sector = Sector_Lv2, Size, AvgTV20, ret_vol20, K200, KQ150)]

# ---- signal + 특성 병합 ----
S <- merge(FAC, me_feat, by = c("Date","Ticker"), all.x = TRUE)
# 유니버스: K200∪KQ150 PIT + 유동성 2e8 (t 시점 ADV20; canonical_screen_bt에도 liq_dt 전달)
S <- S[(K200 == 1 | KQ150 == 1) & is.finite(Size) & Size > 0]
cat(sprintf("[s2] after K200∪KQ150: rows=%d dates=%d tickers=%d\n",
            nrow(S), uniqueN(S$Date), uniqueN(S$Ticker)))

# ---- 중립화: 횡단면(당월) 회귀 잔차 ----
# residual TE = raw Score를 log(Size) + log(vol20) + Sector 더미에 회귀한 잔차.
#   (beta 중립화는 size/sector가 대부분 흡수 — 간결성 위해 size/vol/sector 3축.)
S[, lsize := log(pmax(Size, 1))]
S[, lvol  := log(pmax(ret_vol20, 1e-6))]
neutralize_one <- function(d) {
  d <- copy(d)
  if (nrow(d) < 15L) { d[, Score_resid := scale(Score)[,1]]; return(d) }
  ok <- is.finite(d$Score) & is.finite(d$lsize) & is.finite(d$lvol)
  d2 <- d[ok]
  # 섹터 더미(레벨 1개면 제외)
  hasSec <- length(unique(d2$Sector)) > 1L
  frm <- if (hasSec) Score ~ lsize + lvol + factor(Sector) else Score ~ lsize + lvol
  fit <- tryCatch(lm(frm, data = d2), error = function(e) NULL)
  d[, Score_resid := NA_real_]
  if (!is.null(fit)) {
    d[ok, Score_resid := as.numeric(residuals(fit))]
  } else {
    d[ok, Score_resid := scale(Score[ok])[,1]]
  }
  # 표준화(횡단면 z)
  mu <- mean(d$Score_resid, na.rm = TRUE); sg <- sd(d$Score_resid, na.rm = TRUE)
  if (is.finite(sg) && sg > 0) d[, Score_resid := (Score_resid - mu)/sg]
  d
}
S <- S[, neutralize_one(.SD), by = Date]
cat("[s2] neutralization done.\n")

# ---- forward 1M 수익 병합 (IC + returns_dt 용) ----
S <- merge(S, cal[, .(MEnd, nxt_ym)], by.x = "Date", by.y = "MEnd", all.x = TRUE)
S <- merge(S, MR, by.x = c("Ticker","nxt_ym"), by.y = c("Ticker","ym"), all.x = TRUE)
setnames(S, "MRet", "FwdRet")

# ---- benchmark: 월간 (sig_date t -> t+1 월 BM 실현) ----
BM_DT <- as.data.table(read_parquet(file.path(CACHE, "benchmark_pin20260703.parquet")))
BM_DT[, Date := as.Date(Date)]
BM_DT[, ym := format(Date, "%Y-%m")]
BM_M <- BM_DT[is.finite(BM_Ret), .(BM_MRet = prod(1 + BM_Ret) - 1), by = ym]
# sig_date t의 벤치는 t+1 월(nxt_ym) 수익 — returns_dt와 동일 시점축
BM_for_screen <- unique(S[, .(Date, nxt_ym)])
BM_for_screen <- merge(BM_for_screen, BM_M, by.x = "nxt_ym", by.y = "ym", all.x = TRUE)
bench_dt <- BM_for_screen[is.finite(BM_MRet), .(Date, BM_Ret = BM_MRet)]

# ---- returns_dt: canonical_screen_bt는 (Date,Ticker,Ret_1m). Ret_1m = sig_date t의 forward 1M ----
returns_dt <- unique(S[is.finite(FwdRet), .(Date, Ticker, Ret_1m = FwdRet)])
# liq_dt: t 시점 ADV20
liq_dt <- unique(S[, .(Date, Ticker, adv = AvgTV20)])

# =============================================================================
# 진단: rank-IC / ICIR / subperiod (advisory)
# =============================================================================
compute_ic <- function(scoretab) {
  d <- merge(scoretab[is.finite(score)], returns_dt, by = c("Date","Ticker"))
  ics <- d[, .(ic = if (.N >= 10L) cor(score, Ret_1m, method = "spearman", use = "complete.obs") else NA_real_,
               n = .N), by = Date][is.finite(ic)]
  list(mean_ic = mean(ics$ic), icir = mean(ics$ic)/sd(ics$ic),
       t_ic = mean(ics$ic)/(sd(ics$ic)/sqrt(nrow(ics))),
       harvey_t = mean(ics$ic)/(sd(ics$ic)/sqrt(nrow(ics))),  # NW 미적용 간이 (advisory)
       hit = mean(ics$ic > 0), n = nrow(ics), ics = ics)
}

# 두 변형: raw net-sink / residual net-sink
var_raw   <- S[, .(Date, Ticker, score = Score)]
var_resid <- S[, .(Date, Ticker, score = Score_resid)]

ic_raw   <- compute_ic(var_raw)
ic_resid <- compute_ic(var_resid)
cat(sprintf("[s2][IC advisory] RAW:   meanIC=%.4f ICIR=%.3f t=%.2f hit=%.0f%% n=%d\n",
            ic_raw$mean_ic, ic_raw$icir, ic_raw$t_ic, 100*ic_raw$hit, ic_raw$n))
cat(sprintf("[s2][IC advisory] RESID: meanIC=%.4f ICIR=%.3f t=%.2f hit=%.0f%% n=%d\n",
            ic_resid$mean_ic, ic_resid$icir, ic_resid$t_ic, 100*ic_resid$hit, ic_resid$n))

# =============================================================================
# canonical PORT_t (metric_type=canonical_screen) — top_n 20/25, raw/resid
# =============================================================================
run_canon <- function(scoretab, top_n, label) {
  sc <- scoretab[is.finite(score)]
  r <- tryCatch(
    canonical_screen_bt(scores_dt = sc, returns_dt = returns_dt, bench_dt = bench_dt,
                        top_n = top_n, cost_bps_oneway = 15,
                        liq_dt = liq_dt, liq_min = 2e8,
                        run_id = paste0("te_", label), strategy_id = paste0("te_", label),
                        periods_per_year = 12L),
    error = function(e) { cat("[canon]", label, "ERR:", conditionMessage(e), "\n"); NULL })
  if (is.null(r)) return(NULL)
  cat(sprintf("[s2][CANON %s top%d] PORT_t=%.3f IR=%.3f netSR=%.3f alpha_ann=%.4f TO=%.1f n_mo=%d\n",
              label, top_n, r$portfolio_alpha_t_nw_lag3 %||% NA, r$information_ratio %||% NA,
              r$net_sr %||% NA, r$alpha_annualized %||% NA, r$turnover_annual %||% NA, r$n_months))
  r
}
`%||%` <- function(a,b) if (is.null(a)||length(a)==0||(length(a)==1&&is.na(a))) b else a

res <- list()
res[["raw_top20"]]   <- run_canon(var_raw,   20L, "raw_top20")
res[["raw_top25"]]   <- run_canon(var_raw,   25L, "raw_top25")
res[["resid_top20"]] <- run_canon(var_resid, 20L, "resid_top20")
res[["resid_top25"]] <- run_canon(var_resid, 25L, "resid_top25")
# 확인: 저-sink(reverse) — 신호 방향 검정 (net-sink 하위 = 정보 빠른 종목)
res[["resid_top20_rev"]] <- run_canon(var_resid[, .(Date,Ticker,score=-score)], 20L, "resid_top20_rev")

# =============================================================================
# subperiod: 최적 변형(resid_top20)으로 pre2017/2017+/2022+ PORT_t
# =============================================================================
subperiod_port <- function(scoretab, top_n) {
  sc <- scoretab[is.finite(score)]
  splits <- list(pre2017 = c("2005-01-01","2016-12-31"),
                 p2017   = c("2017-01-01","2026-12-31"),
                 p2022   = c("2022-01-01","2026-12-31"))
  out <- list()
  for (nm in names(splits)) {
    lo <- as.Date(splits[[nm]][1]); hi <- as.Date(splits[[nm]][2])
    scs <- sc[Date >= lo & Date <= hi]
    rd  <- returns_dt[Date >= lo & Date <= hi]
    bd  <- bench_dt[Date >= lo & Date <= hi]
    ld  <- liq_dt[Date >= lo & Date <= hi]
    r <- tryCatch(canonical_screen_bt(scs, rd, bd, top_n = top_n, cost_bps_oneway = 15,
                                      liq_dt = ld, liq_min = 2e8,
                                      run_id = paste0("te_sub_", nm), strategy_id = paste0("te_sub_", nm)),
                  error = function(e) NULL)
    out[[nm]] <- if (is.null(r)) NA else list(port_t = r$portfolio_alpha_t_nw_lag3,
                                              ir = r$information_ratio, net_sr = r$net_sr, n_mo = r$n_months)
  }
  out
}
sub_resid <- subperiod_port(var_resid, 20L)
cat("[s2][subperiod resid_top20]\n")
for (nm in names(sub_resid)) {
  s <- sub_resid[[nm]]
  if (is.list(s)) cat(sprintf("  %s: PORT_t=%.3f IR=%.3f netSR=%.3f n_mo=%d\n",
                              nm, s$port_t %||% NA, s$ir %||% NA, s$net_sr %||% NA, s$n_mo))
}

# ---- 직교성: TE 신호 vs 시장(BM) — 포트 active 상관 없음, 신호 자체 IC 기반만 ----
# 저장
save_res <- function(r) if (is.null(r)) NULL else
  list(metric_type = r$metric_type, port_t = r$portfolio_alpha_t_nw_lag3,
       port_t_pvalue = r$portfolio_alpha_t_pvalue, ir = r$information_ratio,
       net_sr = r$net_sr, alpha_ann = r$alpha_annualized, turnover_ann = r$turnover_annual,
       n_months = r$n_months)

validation <- list(
  wt_id = "WT-D20260705_007",
  as_of_date = "2026-07-05",
  data_vintage_pin = "RAWDATA_pin20260703",
  universe = "K200_KQ150 (PIT time-varying) + 2e8 ADV20 liq",
  n_sig_dates = uniqueN(S$Date),
  cand_per_month = round(nrow(unique(S[,.(Date,Ticker)]))/uniqueN(S$Date)),
  ic_diagnostics = list(
    raw   = list(mean_ic = ic_raw$mean_ic, icir = ic_raw$icir, t_ic = ic_raw$t_ic, hit = ic_raw$hit, n = ic_raw$n),
    resid = list(mean_ic = ic_resid$mean_ic, icir = ic_resid$icir, t_ic = ic_resid$t_ic, hit = ic_resid$hit, n = ic_resid$n)),
  canonical_port_t = lapply(res, save_res),
  subperiod_resid_top20 = sub_resid,
  metric_type_authoritative = "canonical_screen (portfolio_alpha_t_nw_lag3). forge build_bt_result 아님 — screening 실측.",
  note = "TE net-sink 첫 canonical PORT_t. 선행 STR_AS_TE는 proxy 게이트만(PORT_t NA)."
)
write_json(validation, file.path(OUT, "alpha_validation.json"),
           auto_unbox = TRUE, pretty = TRUE, digits = 6, na = "null")

# alpha_scores.parquet (최종 변형 = residual, 최근 sig_date 전수 score)
last_dt <- max(S$Date)
scores_out <- S[Date == last_dt, .(Date, Ticker, score_raw = Score, score_resid = Score_resid,
                                   Size, sector = Sector, adv20 = AvgTV20)]
write_parquet(scores_out, file.path(OUT, "alpha_scores.parquet"))
saveRDS(list(S = S, res = res, ic_raw = ic_raw, ic_resid = ic_resid, sub_resid = sub_resid),
        file.path(OUT, "te_stage2_full.rds"))
cat("[s2] DONE. validation + scores saved.\n")
