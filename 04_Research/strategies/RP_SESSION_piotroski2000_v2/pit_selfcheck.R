# pit_selfcheck.R — 편입일 이후 정보 0 독립 재확인(엔진 코드를 쓰지 않고 원천에서 다시 잰다)
#   ① 보유 종목마다: 그 편입에 쓴 회계연도 t · t-1 · t-2 의 v2 행 Factor_Date 최대 ≤ 신호일 ∧ 익년 3/31 ≤ 신호일
#   ② 보유 기록 집행일(date) = 신호일 다음 거래일(5월 첫 거래일) · 신호일 = 4월 마지막 거래일
#   ③ 돌연변이 대조: 가용일을 하루 뒤로 미는 가짜 행을 넣으면 ①이 위반을 잡는지(검사기 생존 확인)
ROOT <- "G:/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
suppressMessages({ library(data.table); library(arrow); library(jsonlite) })
SDIR <- file.path(ROOT, "04_Research/strategies/RP_SESSION_piotroski2000_v2")
RD <- fromJSON(file.path(SDIR, "run_dirs.json"), simplifyVector = FALSE)
cal <- sort(unique(as.Date(arrow::read_parquet(file.path(ROOT, ".cache/RAWDATA.parquet"), col_select = "Date")$Date)))
items <- c("IncomeContOps","NetIncome","OperatingCF","Revenue","GrossProfit","COGS","EquityChangeCF","ExtraGainGAAP","ExtraLossGAAP",
           "TotalAssets","CurrentAssets","CurrentLiab","LongTermBorr","Bonds","CurrentBorr","CurrentBonds","EquityParent","TotalEquity","PreferredCapital")
q <- as.data.table(dplyr::collect(dplyr::select(dplyr::filter(arrow::open_dataset(file.path(ROOT, ".cache/fundamental_v2/fund_v2_quarterly.parquet")),
                                                              Item %in% items), Ticker, Period, Item, Value, Factor_Date)))
q <- q[is.finite(Value)]
q[, yr := as.integer(substr(Period, 1, 4))]
fdy <- q[, .(fd = max(Factor_Date, na.rm = TRUE)), by = .(Ticker, yr)]
check <- function(dir, inject = FALSE) {
  H <- fread(file.path(dir, "04_holdings.csv"), select = c("date", "ticker", "target_weight"))[target_weight != 0]
  H[, date := as.Date(date)]
  H[, sig := cal[findInterval(as.numeric(date) - 1, as.numeric(cal))]]
  H[, fy := as.integer(format(sig, "%Y")) - 1L]
  X <- rbind(H[, .(ticker, sig, yr = fy)], H[, .(ticker, sig, yr = fy - 1L)], H[, .(ticker, sig, yr = fy - 2L)])
  X <- merge(X, fdy, by.x = c("ticker", "yr"), by.y = c("Ticker", "yr"), all.x = TRUE)
  if (inject) X[1L, fd := sig + 1L]                                     # 돌연변이: 신호일 다음 날 가용 행 하나
  M <- X[, .(fd_max = max(fd, na.rm = TRUE)), by = .(ticker, sig)]
  M[, rule := as.Date(sprintf("%d-03-31", as.integer(format(sig, "%Y"))))]
  list(n_hold = nrow(H), n_viol_fd = M[fd_max > sig, .N], n_viol_rule = M[rule > sig, .N],
       sig_months = paste(sort(unique(format(H$sig, "%m"))), collapse = ","), exec_months = paste(sort(unique(format(H$date, "%m"))), collapse = ","),
       slack_days_min = as.numeric(min(M$sig - M$fd_max)))
}
out <- list()
for (id in names(RD)) if (!is.null(RD[[id]]$out_dir)) out[[id]] <- check(RD[[id]]$out_dir)
out$mutation_hl <- check(RD$hl$out_dir, inject = TRUE)
out$mutation_caught <- out$mutation_hl$n_viol_fd > 0L
write_json(out, file.path(SDIR, "pit_selfcheck.json"), auto_unbox = TRUE, pretty = TRUE)
print(str(out))

# ── ④ 고 BM 5분위 경계 as-of 독립 재계산 (2026-11-09 Q 검토 누출 수리 뒤 추가) ─────────────────────────────
#   원천(v2 1단계 표 Factor_Date · RAWDATA Size · 러너와 같은 측정 축 주입 멤버십)에서 엔진 코드를 쓰지 않고 경계를 다시 계산해
#   (a) 엔진 진단 cut80_prior · n_cut · n_cut_late 와 같은지 (b) 경계 표본에 편입일 d 이후 가용 행이 0 인지 확인한다.
#   돌연변이 대조 ①: 늦은 행 1개(그해 늦은 행 중 BM 최대)를 경계 표본에 다시 넣으면 엔진 값과 어긋나는지(검사기 생존)
#   돌연변이 대조 ②: 가용일 필터를 끈 재계산이 수리 전 엔진 진단(engine_diag_hl_superseded_pitcut.csv)을 재현하는지(누출 실재 확인)
suppressMessages({ source(file.path(ROOT, "02_Infrastructure/config.R")); source(file.path(ROOT, "02_Infrastructure/backtest_harness.R"))
                   source(file.path(ROOT, "02_Infrastructure/contracts/measurement_axis.R")) })
res <- load_rawdata(use_cache = TRUE); RAW <- res$RAWDATA; rm(res); invisible(gc())
if (!inherits(RAW$Date, "Date")) RAW[, Date := as.Date(Date)]
RAW <- ma_inject_universe(RAW, ma_epoch(root = ROOT))$RAWDATA
RAW <- RAW[, .(Date, Ticker, Size, mem = (fcoalesce(as.numeric(K200), 0) > 0) | (fcoalesce(as.numeric(KQ150), 0) > 0))]
q2 <- as.data.table(dplyr::collect(dplyr::select(dplyr::filter(arrow::open_dataset(file.path(ROOT, ".cache/fundamental_v2/fund_v2_quarterly.parquet")),
                                                               Item %in% items), Ticker, Period, Item, Value, Factor_Date, Check)))
q2[, `:=`(yr = as.integer(substr(Period, 1, 4)), mm = substr(Period, 5, 6))]
q2 <- unique(q2[mm %in% c("03", "06", "09", "12") & is.finite(Value)], by = c("Ticker", "Period", "Item"))
dec_tk <- as.data.table(arrow::read_parquet(file.path(ROOT, ".cache/qw_fund_v2/fiscal_month.parquet")))[FiscalMonth == "12", unique(Ticker)]
nd <- unique(q2[Check == "non_dec_fy", .(Ticker, yr)])
b <- q2[Ticker %in% dec_tk & mm == "12" & Item %in% c("EquityParent", "TotalEquity", "PreferredCapital")]
b <- b[!nd, on = c("Ticker", "yr")]
bw <- dcast(b, Ticker + yr ~ Item, value.var = "Value"); bf <- dcast(b, Ticker + yr ~ Item, value.var = "Factor_Date")
for (cc in c("EquityParent", "TotalEquity", "PreferredCapital")) { if (!cc %in% names(bw)) bw[, (cc) := NA_real_]; if (!cc %in% names(bf)) bf[, (cc) := NA_real_] }
for (cc in c("EquityParent", "TotalEquity", "PreferredCapital")) set(bf, j = cc, value = as.Date(as.numeric(bf[[cc]]), origin = "1970-01-01"))
setnames(bf, c("EquityParent", "TotalEquity", "PreferredCapital"), c("fEP", "fTE", "fPC"))
B <- merge(bw, bf, by = c("Ticker", "yr"))
B[, BE := fifelse(is.finite(EquityParent), EquityParent, TotalEquity) - fcoalesce(PreferredCapital, 0)]
B[, fcap := fifelse(is.finite(EquityParent), fEP, fTE)]
B[, fbe := fifelse(is.na(fcap), as.Date(NA), pmax(fcap, fPC, na.rm = TRUE))]
RAW[, `:=`(y = as.integer(format(Date, "%Y")), m = as.integer(format(Date, "%m")))]
ME <- RAW[m == 12L & is.finite(Size) & Size > 0, .SD[which.max(Date)], by = .(Ticker, y), .SDcols = c("Size", "mem")]
B <- merge(B, ME, by.x = c("Ticker", "yr"), by.y = c("Ticker", "y"))
B <- B[is.finite(BE) & BE > 0 & mem %in% TRUE, .(Ticker, yr, BM = BE / Size, av = pmax(fbe, as.Date(sprintf("%d-03-31", yr + 1L))))]
FORM <- data.table(Date = cal)[as.integer(format(Date, "%m")) == 4L, .(d = max(Date)), by = .(fy = as.integer(format(Date, "%Y")) - 1L)]
FORM <- FORM[d >= as.Date(ma_epoch(root = ROOT)$start_date)]   # 측정 축 시작(활성 epoch) — 엔진 진단과 같은 편입일 집합
q80 <- function(x) if (length(x)) as.numeric(stats::quantile(x, 0.8, type = 7)) else NA_real_
CUT <- FORM[, {
  s <- B[yr == fy - 1L]; ok <- !is.na(s$av) & s$av <= d
  late <- s[!ok]; mut <- if (nrow(late)) c(s$BM[ok], late$BM[which.max(late$BM)]) else s$BM[ok]
  .(cut_asof = q80(s$BM[ok]), n_cut = sum(ok), n_cut_late = sum(!ok), n_after_d_in_sample = sum(s$av[ok] > d, na.rm = TRUE),
    cut_mut1 = q80(mut), cut_nofilter = q80(s$BM))
}, by = .(fy, d)]
E  <- fread(file.path(SDIR, "engine_diag_hl.csv"))[, .(d = as.Date(form_date), e_cut = cut80_prior, e_n_cut = n_cut, e_n_late = n_cut_late)]
E0 <- fread(file.path(SDIR, "engine_diag_hl_superseded_pitcut.csv"))[, .(d = as.Date(form_date), e0_cut = cut80_prior)]
CUT <- merge(merge(CUT, E, by = "d"), E0, by = "d")
tol <- 1e-10
CUT[, `:=`(match_asof = (is.na(cut_asof) & is.na(e_cut)) | abs(cut_asof - e_cut) < tol,
           match_n = n_cut == e_n_cut & n_cut_late == e_n_late,
           mut1_caught = n_cut_late == 0L | abs(cut_mut1 - e_cut) > tol,
           nofilter_reproduces_old = (is.na(cut_nofilter) & is.na(e0_cut)) | abs(cut_nofilter - e0_cut) < tol)]
fwrite(CUT, file.path(SDIR, "pit_selfcheck_cut.csv"))
out$cut_check <- list(n_dates = nrow(CUT), all_match_asof = all(CUT$match_asof), all_match_counts = all(CUT$match_n),
                      after_d_in_sample_total = sum(CUT$n_after_d_in_sample), n_dates_with_late = sum(CUT$n_cut_late > 0L),
                      late_rows_total = sum(CUT$n_cut_late), mutation1_caught_all = all(CUT$mut1_caught),
                      mutation1_dates_tested = sum(CUT$n_cut_late > 0L),
                      nofilter_reproduces_old_engine = all(CUT$nofilter_reproduces_old))
write_json(out, file.path(SDIR, "pit_selfcheck.json"), auto_unbox = TRUE, pretty = TRUE)
print(CUT[, .(d, n_cut, n_cut_late, cut_asof, e_cut, e0_cut, match_asof, mut1_caught, nofilter_reproduces_old)])
str(out$cut_check)
