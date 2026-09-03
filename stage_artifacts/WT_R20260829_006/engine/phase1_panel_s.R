## WT-R20260829_006 Phase 1 — 월간 패널 구축
##  산출: (1) 팩터별 월간 L/S 수익 (329 팩터) (2) 계열(15) 합성 z 패널 + 계열 L/S 수익
##        (3) forward returns / bench / liq / size
##  PIT: load_month_factors() 경유(C15) · Z_Score_Aligned(C13) · adv20_t1(C10) · forward 수익(C5)
suppressPackageStartupMessages({library(data.table);library(arrow);library(jsonlite)})
setDTthreads(1); try(arrow::set_cpu_count(1),silent=TRUE); try(arrow::set_io_thread_count(2),silent=TRUE)
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/config.R")
source("02_Infrastructure/factor_db/factor_db_connector.R")
source("02_Infrastructure/ramp/factor_validation.R")

OUT <- "C:/Users/99922/AppData/Local/Temp/claude/C--Users-99922-OneDrive-Quant-Module-Moltbot/0c0807c3-c2cd-4903-8044-987993f6f62f/scratchpad/wt006"
LIQ_MIN <- 2e8
PIT_EXCLUDE <- c(
  "C01_SUE","C02_EPS_Chg_1m","C03_EPS_Chg_3m","C04_ESBR","C05_ESCR","C06_TP_Gap",
  "C08_Coverage","C11_Earnings_Streak","C12_Estimate_Dispersion_Proxy","C16_EPS_Acceleration",
  "C18_Earnings_CAR_3d","C19_Composite_Earnings","SE02_Consensus_Revision","V04_fPER",
  "V05_fPBR","V06_fDY","V09_PEG","D32_Beta_VIX","MA01_GDP_Sensitivity","MA03_Rate_Sensitivity",
  "MA04_YieldCurve_Sensitivity",
  ## 2차 순회에서 추가 적발 (as_of 스냅샷이 아니라 소비 팩터 합집합으로 재검증한 결과)
  "C07_TP_Mom", "MA02_CPI_Sensitivity")
cat("[PIT-strict] ast_verify FAIL_LOOKAHEAD 리프", length(PIT_EXCLUDE), "종 제외
")

## ── 1. rawdata → 월말 앵커 · forward 수익 · adv20 ─────────────────────────────
.need <- c("Date","Ticker","Close","K200","KQ150","Vol","Size","Ret","BM_Ret")
RAW <- as.data.table(read_parquet(".cache/rawdata.parquet", col_select = all_of(.need)))
RAW[, Date := as.Date(Date)]
raw_max <- max(RAW$Date); cat("[raw] max date =", as.character(raw_max), " rows =", nrow(RAW), "\n")

## 월말 앵커: 2003-12 ~ (형성창 12m + 여유). 팩터 수익 시작 = 2004-01 홀딩월
firsts <- seq(as.Date("2003-12-01"), as.Date(format(raw_max, "%Y-%m-01")), by = "month")
me_cal <- c(firsts[-1] - 1L, as.Date(format(raw_max,"%Y-%m-01")) + 31L)  # 캘린더 월말 후보
udates <- sort(unique(RAW$Date))
ME <- unique(as.Date(vapply(me_cal, function(d){ v <- udates[udates <= d]
        if (length(v)) as.character(max(v)) else NA_character_ }, character(1))))
ME <- ME[!is.na(ME)]; ME <- ME[ME >= as.Date("2003-12-01")]
cat("[anchors] n =", length(ME), " first =", as.character(min(ME)), " last =", as.character(max(ME)), "\n")

ADV20 <- build_adv20_t1(RAW[, .(Date, Ticker, Vol, Close)], at_dates = ME)
RAWME <- RAW[Date %in% ME]; rm(RAW); invisible(gc())
fwd <- build_monthly_forward_returns(RAWME, ME, liq_daily = ADV20)
RET_DT   <- as.data.table(fwd$returns_dt)[, .(Date = as.Date(Date), Ticker, Ret_1m)]
BENCH_DT <- as.data.table(fwd$bench_dt)[, .(Date = as.Date(Date), BM_Ret)]
LIQ_DT   <- as.data.table(fwd$liq_dt)[, .(Date = as.Date(Date), Ticker, adv)]
liq_ruler <- attr(fwd$liq_dt, "liq_ruler", exact = TRUE)
cat("[fwd] liq_ruler =", liq_ruler, " ret rows =", nrow(RET_DT), " bench =", nrow(BENCH_DT), "\n")

SIZE_DT <- RAWME[, .(Date, Ticker, Size)]
UNIV_DT <- RAWME[(K200 == 1 | KQ150 == 1), .(Date, Ticker, K200 = as.integer(K200), KQ150 = as.integer(KQ150))]
cat("[univ] rows =", nrow(UNIV_DT), " per-month median =",
    median(UNIV_DT[, .N, by = Date]$N), "\n")

saveRDS(list(RET_DT=RET_DT, BENCH_DT=BENCH_DT, LIQ_DT=LIQ_DT, SIZE_DT=SIZE_DT,
             UNIV_DT=UNIV_DT, ME=ME, liq_ruler=liq_ruler, raw_max=raw_max),
        file.path(OUT, "p1s_market.rds"))

## ── 2. 계열 지도 (registry 15 계열) ───────────────────────────────────────────
reg <- fromJSON("02_Infrastructure/factor_db/factor_registry.json", simplifyVector = FALSE)
FAM <- data.table(Factor_Name = names(reg),
                  family = vapply(reg, function(x){ v <- x$labels$economic_family
                    if (is.null(v)) NA_character_ else as.character(v)[1] }, character(1)))
FAM <- FAM[!is.na(family) & !(Factor_Name %in% PIT_EXCLUDE)]
cat("[fam] declared families =", uniqueN(FAM$family), "\n"); print(table(FAM$family))
fwrite(FAM, file.path(OUT, "p1s_family_map.csv"))

## ── 3. 월별 루프 — 팩터 L/S 수익 + 계열 합성 z ────────────────────────────────
sig_dates <- ME[ME >= as.Date("2003-12-01") & ME <= max(RET_DT$Date)]
cat("[loop] n sig_dates =", length(sig_dates), "\n")

fac_ret_l <- vector("list", length(sig_dates))
fam_ret_l <- vector("list", length(sig_dates))
famz_l    <- vector("list", length(sig_dates))
cov_l     <- vector("list", length(sig_dates))

t0 <- Sys.time()
for (i in seq_along(sig_dates)) {
  d <- sig_dates[i]
  z <- tryCatch(load_month_factors(d, dedup = TRUE), error = function(e) NULL)
  if (is.null(z) || nrow(z) == 0) next
  setDT(z)
  z <- z[!Factor_Name %in% PIT_EXCLUDE]   # PIT-strict: 정적검증기 FAIL_LOOKAHEAD 리프 제외
  ## 유니버스 ∩ 유동성 (t 시점 관측 — adv20_t1 = 당일 미포함)
  u <- UNIV_DT[Date == d, .(Ticker)]
  lq <- LIQ_DT[Date == d, .(Ticker, adv)]
  keep <- merge(u, lq, by = "Ticker", all.x = TRUE)[is.na(adv) | adv >= LIQ_MIN, .(Ticker)]
  r <- RET_DT[Date == d, .(Ticker, Ret_1m)]
  keep <- merge(keep, r, by = "Ticker")                      # forward 수익 실현분만
  if (nrow(keep) < 50) next
  z <- z[Ticker %in% keep$Ticker]
  z <- merge(z, keep, by = "Ticker")
  z <- z[is.finite(Z_Score_Aligned) & is.finite(Ret_1m)]
  if (nrow(z) == 0) next

  ## (a) 팩터별 decile L/S — 팩터 정의(롱숏 스프레드)
  z[, rk := frank(Z_Score_Aligned, ties.method = "average") / .N, by = Factor_Name]
  z[, nf := .N, by = Factor_Name]
  fr <- z[nf >= 50, .(
      n = .N,
      ls = mean(Ret_1m[rk > 0.9]) - mean(Ret_1m[rk <= 0.1])
    ), by = Factor_Name]
  fr[, Date := d]
  fac_ret_l[[i]] <- fr

  ## (b) 계열 합성 z (계열 내 EW · 결정론적 · 선택 없음)
  zz <- merge(z[, .(Ticker, Factor_Name, Z_Score_Aligned, Ret_1m)], FAM, by = "Factor_Name")
  fz <- zz[, .(z_fam = mean(Z_Score_Aligned), k = uniqueN(Factor_Name)),
           by = .(Ticker, family)]
  fz <- merge(fz, keep, by = "Ticker")
  fz[, Date := d]
  famz_l[[i]] <- fz[, .(Date, Ticker, family, z_fam, k)]

  fz[, rk := frank(z_fam, ties.method = "average") / .N, by = family]
  fz[, nf := .N, by = family]
  famret <- fz[nf >= 50, .(n = .N,
      ls = mean(Ret_1m[rk > 0.9]) - mean(Ret_1m[rk <= 0.1])), by = family]
  famret[, Date := d]
  fam_ret_l[[i]] <- famret

  cov_l[[i]] <- data.table(Date = d, n_univ = nrow(u), n_keep = nrow(keep),
                           n_factor = uniqueN(z$Factor_Name), n_family = uniqueN(fz$family))
  if (i %% 24 == 0) cat(sprintf("  [%d/%d] %s  elapsed %.1f min\n", i, length(sig_dates),
      as.character(d), as.numeric(difftime(Sys.time(), t0, units = "mins"))))
}

FAC_RET <- rbindlist(fac_ret_l, use.names = TRUE)
FAM_RET <- rbindlist(fam_ret_l, use.names = TRUE)
FAMZ    <- rbindlist(famz_l, use.names = TRUE)
COV     <- rbindlist(cov_l, use.names = TRUE)
cat("[out] FAC_RET rows", nrow(FAC_RET), " FAM_RET rows", nrow(FAM_RET),
    " FAMZ rows", nrow(FAMZ), "\n")
cat("[out] date range", as.character(min(FAM_RET$Date)), "~", as.character(max(FAM_RET$Date)), "\n")

write_parquet(FAC_RET, file.path(OUT, "p1s_factor_ls_returns.parquet"))
write_parquet(FAM_RET, file.path(OUT, "p1s_family_ls_returns.parquet"))
write_parquet(FAMZ,    file.path(OUT, "p1s_family_z_panel.parquet"))
fwrite(COV, file.path(OUT, "p1s_coverage.csv"))
cat("[done] total", round(as.numeric(difftime(Sys.time(), t0, units="mins")),1), "min\n")
