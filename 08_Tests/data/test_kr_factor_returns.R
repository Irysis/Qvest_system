#!/usr/bin/env Rscript
#==============================================================================
# test_kr_factor_returns.R — 한국 FF 팩터 빌더(02_Infrastructure/data/build_kr_factor_returns.R) 계약 검사
#   합성 자료(30종목 · 2009-11 ~ 2011-09)로 정답을 따로 계산해(빌더 함수를 쓰지 않는 오라클) 대조하고,
#   위반 주입(돌연변이 — 소스 텍스트 치환 · 치환 성사 단정) 3종으로 검사가 살아 있음을 보인다.
#   ① PIT: 구성일 뒤 공개된 BE 는 그해 정렬에 없다 ② 비멤버는 정렬에 없다 ③ 일간 HML = 오라클
#   ④ 월간 HML = 포트폴리오 월간 복리의 조합 ⑤ 자료 없는 정렬은 NA(지어내지 않는다) ⑥ RF = 전 거래일 금리
#   ⑦ 완결 월만 월간 파일에 ⑧ MKT = MKT_TOTAL − RF ⑨ SMB5 = 세 SMB 평균 ⑩ 같은 입력 → 같은 내용 해시
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
root <- gsub("\\\\", "/", Sys.getenv("QM_ROOT", Sys.getenv("CLAUDE_PROJECT_DIR", "")))
if (!nzchar(root)) stop("QM_ROOT 미설정")
BUILDER <- file.path(root, "02_Infrastructure/data/build_kr_factor_returns.R")
pass <- 0L; fail <- 0L
ok <- function(cond, msg) {
  if (isTRUE(cond)) { pass <<- pass + 1L; cat("  PASS ", msg, "\n", sep = "") }
  else { fail <<- fail + 1L; cat("  FAIL ", msg, "\n", sep = "") }
}

load_builder <- function(text = NULL) {
  e <- new.env(parent = globalenv())
  f <- BUILDER
  if (!is.null(text)) { f <- tempfile(fileext = ".R"); writeLines(text, f, useBytes = TRUE) }
  sys.source(f, envir = e, keep.source = FALSE)
  e
}
mutant <- function(from, to) {
  src <- readLines(BUILDER, encoding = "UTF-8", warn = FALSE)
  txt <- paste(src, collapse = "\n")
  n <- lengths(regmatches(txt, gregexpr(from, txt, fixed = TRUE)))
  if (n != 1L) stop("돌연변이 치환 대상이 정확히 1곳이 아니다(", n, "): ", from)
  load_builder(sub(from, to, txt, fixed = TRUE))
}

## ── 합성 자료 ────────────────────────────────────────────────────────────────
mk_raw <- function() {
  set.seed(20261109)
  d <- seq(as.Date("2009-11-02"), as.Date("2011-09-30"), by = "day")
  d <- d[as.integer(format(d, "%u")) <= 5L]
  tk <- sprintf("T%02d", 1:30)
  R <- CJ(Ticker = tk, Date = d)
  R[, i := as.integer(substr(Ticker, 2, 3))]
  R[, Ret := round(rnorm(.N, 0.0003 * (i %% 5), 0.02), 6)]
  setorder(R, Ticker, Date)
  R[, g := cumprod(1 + Ret), by = Ticker]
  R[, `:=`(Size = (i^2) * 1e9 * g, Close = 1000 * g, member = TRUE)]
  R[Ticker == "T05" & Date == as.Date("2011-06-30"), member := FALSE]      # 구성일 비멤버
  R[, c("i", "g") := NULL]
  R[]
}
mk_fund <- function() {
  i <- 1:30; tk <- sprintf("T%02d", i)
  be09 <- (i^2) * 1e9 * (0.3 + (i %% 7) / 5); be10 <- be09 * 1.05
  ta09 <- be09 * (1.5 + (i %% 3) / 2); ta10 <- ta09 * (1 + ((i * 7) %% 11 - 5) / 50)
  op09 <- be09 * (0.01 + (i %% 4) / 100); op10 <- be10 * (0.012 + ((i * 3) %% 5) / 100); ie10 <- be10 * 0.002
  fd09 <- c("03" = "2009-05-15", "06" = "2009-08-14", "09" = "2009-11-16", "12" = "2010-03-15")
  fd10 <- c("03" = "2010-05-17", "06" = "2010-08-16", "09" = "2010-11-15", "12" = "2011-03-15")
  out <- list()
  add <- function(t, p, it, v, fd) out[[length(out) + 1L]] <<- data.table(Ticker = t, Period = p, Item = it, Value = v, Factor_Date = as.Date(fd))
  for (j in seq_along(tk)) {
    add(tk[j], "200912", "EquityParent", be09[j], "2010-03-15"); add(tk[j], "200912", "TotalAssets", ta09[j], "2010-03-15")
    add(tk[j], "201012", "EquityParent", be10[j], if (tk[j] == "T25") "2011-07-20" else "2011-03-15")   # ★T25 = 구성일 뒤 공개
    add(tk[j], "201012", "TotalAssets", ta10[j], "2011-03-15")
    for (q in names(fd09)) {
      add(tk[j], paste0("2009", q), "OperatingProfit", op09[j], fd09[[q]])
      add(tk[j], paste0("2010", q), "OperatingProfit", op10[j], fd10[[q]])
      add(tk[j], paste0("2010", q), "InterestExp", ie10[j], fd10[[q]])
    }
  }
  rbindlist(out)
}
mk_rf <- function(R) { d <- sort(unique(R$Date)); data.table(Date = d, y = ifelse(d < as.Date("2011-07-15"), 3.00, 4.00)) }

## ── 오라클(빌더 함수를 쓰지 않는다) ──────────────────────────────────────────
or_bm_ports <- function(R, F, fdate = as.Date("2011-06-30"), dec = as.Date("2010-12-31")) {
  U <- R[Date == fdate & member == TRUE & Size > 0, .(Ticker, ME_f = Size)]
  U <- merge(U, R[Date == dec, .(Ticker, ME_dec = Size)], by = "Ticker", all.x = TRUE)
  U <- merge(U, F[Period == "201012" & Item == "EquityParent" & Factor_Date <= fdate, .(Ticker, BE = Value)], by = "Ticker", all.x = TRUE)
  o <- order(-U$ME_f); before <- cumsum(U$ME_f[o]) - U$ME_f[o]
  big <- logical(nrow(U)); big[o] <- before / sum(U$ME_f) < 0.90
  U$big <- big
  S <- U[is.finite(BE) & BE > 0 & is.finite(ME_dec)]
  S$x <- S$BE / S$ME_dec
  q <- quantile(S$x[S$big], c(0.3, 0.7), names = FALSE, type = 7)
  S$port <- paste0(ifelse(S$big, "B", "S"), ifelse(S$x <= q[1], "L", ifelse(S$x >= q[2], "H", "N")))
  S
}
# 가중 상한(JKP 2023 · 설정 weighting) — 직전 월말 멤버 중 Big(시총 상위 90%)의 시총 80 분위
or_cap <- function(R, me_date = as.Date("2011-06-30")) {
  U <- R[Date == me_date & member == TRUE & Size > 0]
  o <- order(-U$Size); before <- cumsum(U$Size[o]) - U$Size[o]
  big <- logical(nrow(U)); big[o] <- before / sum(U$Size) < 0.90
  quantile(U$Size[big], 0.80, names = FALSE, type = 7)
}
or_vw <- function(R, P, d, cap = Inf) {
  dd <- sort(unique(R$Date)); dp <- dd[match(d, dd) - 1L]
  x <- merge(merge(R[Date == d, .(Ticker, Ret)], R[Date == dp, .(Ticker, ME = Size)], by = "Ticker"), P[, .(Ticker, port)], by = "Ticker")
  x[, W := pmin(ME, cap)]
  r <- x[, .(r = sum(W * Ret) / sum(W)), by = port]
  setNames(r$r, r$port)
}
or_hml <- function(v) (v[["SH"]] + v[["BH"]]) / 2 - (v[["SL"]] + v[["BL"]]) / 2

## ── 실행 ────────────────────────────────────────────────────────────────────
E <- load_builder()
cfg <- E$krf_config(root)
cfg$start_date <- "2010-01-01"
cfg$guards$min_big_for_breakpoints <- 3L
cfg$guards$trading_day_min_rows <- 1L                 # 합성 30종목 — 실자료 문턱(100)은 거래일 판정용
RAW0 <- mk_raw(); FUND <- mk_fund(); RFY <- mk_rf(RAW0)
run <- function(env, to = NULL) env$krf_build(copy(RAW0), FUND, RFY, cfg, to = to)
res <- run(E)

cat("[test_kr_factor_returns] 합성 30종목 · ", format(min(RAW0$Date)), "~", format(max(RAW0$Date)), "\n", sep = "")
LA <- res$diag$annual
lab <- E$krf_annual_labels(E$krf_snap(copy(RAW0)[, ME_l1 := NA_real_], E$krf_calendar(RAW0, 1L)$me), E$krf_annual_fund(FUND), 2011L, cfg)$labels
ok(!("T25" %in% lab[sort == "BM"]$Ticker) && !("T25" %in% lab[sort == "OP"]$Ticker), "① PIT — 구성일(2011-06-30) 뒤 공개(2011-07-20) BE 의 T25 는 2011 B/M · OP 정렬에 없다")
ok("T25" %in% lab[sort == "INV"]$Ticker, "① 대조 — T25 는 TA 가 공개돼 있어 INV 정렬에는 있다")
ok(!("T05" %in% lab$Ticker), "② 구성일 비멤버 T05 는 2011 정렬 어디에도 없다")

P <- or_bm_ports(RAW0, FUND)
ok(setequal(P$Ticker, lab[sort == "BM"]$Ticker) && all(merge(P, lab[sort == "BM"], by = "Ticker")[, port.x == port.y]),
   "③ 2011 B/M 정렬 포트폴리오 배정 = 오라클")
d1 <- as.Date("2011-07-05")
cap6 <- or_cap(RAW0)
ok(identical(cfg$weighting$rule, "capped_vw") && isTRUE(abs(res$caps[fym == 201106L]$cap - cap6) < 1e-6 * cap6) &&
     sum(RAW0[Date == as.Date("2011-07-04") & Ticker %in% P$Ticker]$Size > cap6) >= 2L,
   sprintf("③ 가중 상한(2011-06 말 Big 시총 80 분위 %.4g) = 오라클 · 상한이 실제로 걸리는 종목이 있다", cap6))
v <- or_vw(RAW0, P, d1, cap6)
ok(isTRUE(abs(res$daily[Date == d1]$HML - or_hml(v)) < 1e-12), sprintf("③ 일간 HML(%s) = 오라클(상한 가치가중) (%.10f)", d1, or_hml(v)))
v_unc <- or_vw(RAW0, P, d1)
ok(isTRUE(abs(or_hml(v_unc) - or_hml(v)) > 1e-9), "③ 대조 — 상한 없는 가치가중 HML 은 다른 값이다(상한이 결과를 바꾼다)")
jd <- sort(unique(RAW0$Date)); jd <- jd[format(jd, "%Y%m") == "201107"]
pm <- sapply(c("SH", "SN", "SL", "BH", "BN", "BL"), function(p) prod(1 + sapply(jd, function(d) or_vw(RAW0, P, d, cap6)[[p]])) - 1)
ok(isTRUE(abs(res$monthly[ym == 201107L]$HML - or_hml(pm)) < 1e-12), sprintf("④ 월간 HML(2011-07) = 포트폴리오 월간 복리의 조합 (%.10f)", or_hml(pm)))
cm <- res$monthly[ym >= 201007L & ym <= 201106L]
ok(nrow(cm) == 12L && all(is.na(cm$CMA)) && all(is.finite(cm$RMW)) && all(is.finite(cm$HML)),
   "⑤ FY2008 TA 가 없으면 2010-07 ~ 2011-06 CMA = NA(지어내지 않는다) · RMW · HML 는 값")
rf <- res$daily[Date %in% as.Date(c("2011-07-15", "2011-07-18")), .(Date, rf_yield_pct)]
ok(identical(rf$rf_yield_pct, c(3, 4)), "⑥ RF = 전 거래일 금리(07-15 은 07-14 의 3% · 07-18 은 07-15 의 4%)")
r2 <- run(E, to = "2011-09-28")
ok(!(201109L %in% r2$monthly$ym) && (201109L %in% res$monthly$ym) && any(format(r2$daily$Date, "%Y%m") == "201109"),
   "⑦ 남은 평일이 있는 마지막 달(2011-09 · 28일까지)은 월간 파일에 없고 일간에는 있다 · 월말까지 오면 싣는다")
ok(isTRUE(max(abs(res$daily$MKT - (res$daily$MKT_TOTAL - res$daily$RF)), na.rm = TRUE) < 1e-15) &&
     isTRUE(max(abs(res$monthly$MKT - (res$monthly$MKT_TOTAL - res$monthly$RF)), na.rm = TRUE) < 1e-15), "⑧ MKT = MKT_TOTAL − RF(일간 · 월간)")
s5 <- res$monthly[is.finite(SMB5)]
ok(nrow(s5) > 0L && isTRUE(max(abs(s5$SMB5 - (s5$SMB_BM + s5$SMB_OP + s5$SMB_INV) / 3)) < 1e-15) && identical(res$monthly$SMB, res$monthly$SMB_BM),
   "⑨ SMB5 = 세 정렬 SMB 평균 · SMB = 3요인판(B/M 정렬)")
cols <- c("Date", "MKT", "SMB", "HML", "WML", "RMW", "CMA", "RF", "SMB5")
ok(identical(E$.krf_content_md5(res$monthly, cols), E$.krf_content_md5(run(E)$monthly, cols)), "⑩ 같은 입력 → 같은 월간 내용 해시")

## ── 위반 주입(검사가 살아 있나) ─────────────────────────────────────────────
cat("[test_kr_factor_returns] 위반 주입\n")
M1 <- mutant("    J[is.na(BE_d) | BE_d > fdate, BE := NA_real_]\n", "")
l1 <- M1$krf_annual_labels(M1$krf_snap(copy(RAW0)[, ME_l1 := NA_real_], M1$krf_calendar(RAW0, 1L)$me), M1$krf_annual_fund(FUND), 2011L, cfg)$labels
ok("T25" %in% l1[sort == "BM"]$Ticker, "M1 BE 의 PIT 거름을 지우면 T25 가 정렬에 들어온다(① 이 잡는다)")
M2 <- mutant("prev = c(as.Date(NA), head(dates, -1L))", "prev = dates")
rf2 <- M2$krf_build(copy(RAW0), FUND, RFY, cfg)$daily[Date == as.Date("2011-07-15")]$rf_yield_pct
ok(identical(rf2, 4), "M2 RF 를 그날 금리로 바꾸면 07-15 이 4% 가 된다(⑥ 이 잡는다)")
M3 <- mutant("RAW[, ME_l1 := shift(Size, 1L), by = Ticker]", "RAW[, ME_l1 := Size]")
h3 <- M3$krf_build(copy(RAW0), FUND, RFY, cfg)$daily[Date == d1]$HML
ok(isTRUE(abs(h3 - or_hml(v)) > 1e-9), "M3 가중을 그날 시총으로 바꾸면 일간 HML 이 오라클과 달라진다(③ 이 잡는다)")
M4 <- mutant("RD[, W := fifelse(is.finite(cap), pmin(ME_l1, cap), NA_real_)]", "RD[, W := ME_l1]")
h4 <- M4$krf_build(copy(RAW0), FUND, RFY, cfg)$daily[Date == d1]$HML
ok(isTRUE(abs(h4 - or_hml(v)) > 1e-9), "M4 가중 상한을 지우면 일간 HML 이 오라클(상한 가치가중)과 달라진다(③ 이 잡는다)")
mk_mkt <- function(r) r$daily[Date == d1]$MKT_TOTAL
x_mkt <- merge(RAW0[Date == d1, .(Ticker, Ret)], RAW0[Date == as.Date("2011-07-04"), .(Ticker, ME = Size)], by = "Ticker")
x_mkt <- x_mkt[Ticker %in% RAW0[Date == as.Date("2011-06-30") & member == TRUE]$Ticker]
ok(isTRUE(abs(mk_mkt(res) - x_mkt[, sum(ME * Ret) / sum(ME)]) < 1e-12), "⑧ 대조 — 시장(MKT_TOTAL)은 상한 없는 가치가중(직전 월말 멤버)")

cat(sprintf("[test_kr_factor_returns] %d PASS / %d FAIL\n", pass, fail))
cat(toJSON(list(suite = "test_kr_factor_returns", pass = pass, fail = fail), auto_unbox = TRUE), "\n")
if (fail > 0L) quit(save = "no", status = 1L)
