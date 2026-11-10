#!/usr/bin/env Rscript
#==============================================================================
# test_kr_factor_returns.R — 한국 FF 팩터 빌더(02_Infrastructure/data/build_kr_factor_returns.R) 계약 검사
#   합성 자료(30종목 · 2009-11 ~ 2011-09)로 정답을 따로 계산해(빌더 함수를 쓰지 않는 오라클) 대조하고,
#   위반 주입(돌연변이 — 소스 텍스트 치환 · 치환 성사 단정) 3종으로 검사가 살아 있음을 보인다.
#   ① PIT: 구성일 뒤 공개된 BE 는 그해 정렬에 없다 ② 비멤버는 정렬에 없다 ③ 일간 HML = 오라클
#   ④ 월간 HML = 포트폴리오 월간 복리의 조합 ⑤ 자료 없는 정렬은 NA(지어내지 않는다) ⑥ RF = 전 거래일 금리
#   ⑦ 완결 월만 월간 파일에 ⑧ MKT = MKT_TOTAL − RF ⑨ SMB5 = 세 SMB 평균 ⑩ 같은 입력 → 같은 내용 해시
#   v1.1(11-10): (a) 정정 의심 연도 = DART 당시 기록으로 정렬 편입 (b) 기록 날짜 > 구성일이면 결측 (c) 퀀티 값이 공개된 해는 v1.0 과 같다
#   (e) RS 없으면 멈춤 (f) krf_restated_record 계산 · (d) 돌연변이 M5~M7(v1.0 규칙 복귀 · 우선순위 뒤집기 · 날짜 검사 삭제)
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
RS0 <- data.table(Ticker = character(0), fy = integer(0), BE_r = numeric(0), TA_r = numeric(0), OPN_r = numeric(0), R_d = as.Date(character(0)))
run <- function(env, to = NULL, F = FUND, RS = RS0) env$krf_build(copy(RAW0), F, RFY, cfg, to = to, RS = RS)
res <- run(E)
labs_of <- function(env, F, RS, yr = 2011L)
  env$krf_annual_labels(env$krf_snap(copy(RAW0)[, ME_l1 := NA_real_], env$krf_calendar(RAW0, 1L)$me), env$krf_annual_fund(F, RS), yr, cfg)$labels

cat("[test_kr_factor_returns] 합성 30종목 · ", format(min(RAW0$Date)), "~", format(max(RAW0$Date)), "\n", sep = "")
LA <- res$diag$annual
lab <- labs_of(E, FUND, RS0)
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

## ── v1.1 정정 의심 연도 DART 기록(GRADE-V33-NOTCH-ASOF-AND-RULE-CHANGE-PROCEDURE-20261110) ──────────────
#   T12 · T18 = 정정 의심 FY2010: 퀀티 값은 다음 해 보고서 뒤(2012-03-15)로 미뤄져 있다(v2 1단계 표의 규칙)
#   T12 의 DART 당시 기록 = 2011-03-16 부터(구성일 앞) · T18 = 2011-07-20 부터(구성일 뒤 — 나중 기재정정본)
cat("[test_kr_factor_returns] v1.1 정정 의심 연도\n")
RST <- c("T12", "T18")
FUND2 <- copy(FUND)[Ticker %in% RST & substr(Period, 1, 4) == "2010", Factor_Date := as.Date("2012-03-15")]
q12 <- FUND[Ticker == "T12" & substr(Period, 1, 4) == "2010"]
be12 <- q12[Item == "EquityParent", Value]; ta12 <- q12[Item == "TotalAssets", Value]
opn12 <- q12[Item == "OperatingProfit", sum(Value)] - q12[Item == "InterestExp", sum(Value)]
RS2 <- data.table(Ticker = RST, fy = 2010L, BE_r = c(be12 * 0.9, 1e12), TA_r = c(ta12 * 0.95, 1e12), OPN_r = c(opn12 * 0.9, 1e10),
                  R_d = as.Date(c("2011-03-16", "2011-07-20")))
la <- labs_of(E, FUND2, RS2)
ch <- E$krf_build(copy(RAW0), FUND2, RFY, cfg, RS = RS2)$chars
me12 <- RAW0[Ticker == "T12" & Date == as.Date("2011-06-30"), Size]
ok(all(c("BM", "OP", "INV") %in% la[Ticker == "T12", sort]) &&
     isTRUE(abs(ch[Ticker == "T12" & ym == 201106L, bm] - be12 * 0.9 / me12) < 1e-12 * be12 / me12),
   "(a) 정정 의심 T12 는 DART 당시 기록(구성일 앞 공개)으로 2011 B/M · OP · INV 정렬에 들어가고 값 = DART 기록(특성 bm = BE_r / ME)")
ok(!("T12" %in% labs_of(E, FUND2, RS0)[sort == "BM", Ticker]), "(a) 대조 — 기록이 없으면(0행) T12 는 정렬에 없다(미룬 날짜 2012-03-15)")
ok(!any(c("BM", "OP", "INV") %in% la[Ticker == "T18", sort]), "(b) DART 기록 날짜(2011-07-20)가 구성일 뒤인 T18 은 정렬에 없다(앞당기지 않는다)")
RS3 <- copy(RS2)[Ticker == "T12", `:=`(BE_r = be12 * 0.02, OPN_r = opn12 * 5)]   # 값을 크게 바꾼 기록(T12 = SH · SW → 우선순위가 뒤집히면 SL · SR 로 바뀐다)
rc <- run(E, RS = RS3)                                                    # 퀀티 값이 이미 공개된 해에 기록이 있어도
ok(identical(E$.krf_content_md5(rc$monthly, cols), E$.krf_content_md5(res$monthly, cols)) &&
     identical(labs_of(E, FUND, RS3)[order(sort, Ticker)], lab[order(sort, Ticker)]),
   "(c) 퀀티 값이 구성일 앞에 공개된 해는 기록이 있어도 v1.0 과 같다(정렬 · 월간 내용 해시) — 퀀티 우선")
e_null <- tryCatch({ E$krf_build(copy(RAW0), FUND, RFY, cfg); "no_error" }, error = function(e) conditionMessage(e))
e_fund <- tryCatch({ E$krf_annual_fund(FUND); "no_error" }, error = function(e) conditionMessage(e))
ok(grepl("RS", e_null) && grepl("RS", e_fund), "(e) RS 를 주지 않으면 krf_build · krf_annual_fund 가 멈춘다(v1.0 규칙으로 조용히 돌아가지 않는다)")
# krf_restated_record — 보유 판 · CFS 우선 · 다른 해 응답 배제 · 우선주 차감 · 날짜 겹침 중단
REST <- data.table(Ticker = c("A1", "A2", "A3"), fy = 2019L)
CK <- data.table(Ticker = c("A1", "A2", "A3"), FY = 2019L, DART_Date = as.Date(c("2020-03-30", "2020-03-31", "2020-03-30")),
                 DART_Factor_Date = as.Date(c("2020-03-31", "2020-04-01", "2020-03-31")))
FD <- data.table(Ticker = c("A1", "A2", "A3"), bsns_year = 2019L, TotalAssets = c(100, 200, 300), TotalEquity = c(50, 80, 90),
                 OperatingProfit = c(10, 20, 30), InterestExp = c(1, NA, 3))
RAWB <- data.table(Ticker = c("A1", "A1", "A1", "A1", "A2", "A2", "A2"), bsns_year = 2019L,
                   rcept_no = c("20200330000001", "20200330000001", "20200330000001", "20190601000009", "20200331000002", "20200331000002", "20200331000002"),
                   fs_div = c("CFS", "OFS", "CFS", "CFS", "OFS", "OFS", "OFS"),
                   account_id = c("ifrs-full_EquityAttributableToOwnersOfParent", "ifrs-full_Equity", "dart_IssuedCapitalOfPreferredStock",
                                  "ifrs-full_EquityAttributableToOwnersOfParent", "ifrs_Equity", "ifrs_NoncontrollingInterests", "ifrs_Equity"),
                   thstrm_amount = c("45", "60", "2", "999", "70", "5", "71"))
RR <- E$krf_restated_record(REST, CK, FD, RAWB)$RS
ok(isTRUE(all.equal(RR[order(Ticker), BE_r], c(43, 65, 90))) && isTRUE(all.equal(RR[order(Ticker), OPN_r], c(9, 20, 27))) &&
     identical(RR[order(Ticker), R_d], CK$DART_Factor_Date),
   "(f) 기록 = CFS 지배주주지분 − 우선주(A1 45 − 2 · 다른 해 응답 999 배제) · 자본총계 − 비지배(A2 70 − 5) · 원장 없음 → fundamental_dart 자본총계(A3) · OPN = 영업이익 − 이자비용(없음 = 0) · 날짜 = 접수 다음 거래일")
e_dup <- tryCatch({ E$krf_restated_record(REST, rbind(CK, CK[1][, DART_Factor_Date := as.Date("2020-04-02")]), FD, RAWB); "no_error" },
                  error = function(e) conditionMessage(e))
ok(grepl("하나가 아니다", e_dup), "(f) DART 접수 날짜가 기업-연도마다 둘이면 멈춘다")

## ── 위반 주입(검사가 살아 있나) ─────────────────────────────────────────────
cat("[test_kr_factor_returns] 위반 주입\n")
M1 <- mutant("    J[, BE  := .krf_pick(BE,  BE_d,  BE_r,  R1_d, fdate)]\n", "")
l1 <- labs_of(M1, FUND, RS0)
ok("T25" %in% l1[sort == "BM"]$Ticker, "M1 BE 의 PIT 고르기를 지우면 T25 가 정렬에 들어온다(① 이 잡는다)")
M2 <- mutant("prev = c(as.Date(NA), head(dates, -1L))", "prev = dates")
rf2 <- M2$krf_build(copy(RAW0), FUND, RFY, cfg, RS = RS0)$daily[Date == as.Date("2011-07-15")]$rf_yield_pct
ok(identical(rf2, 4), "M2 RF 를 그날 금리로 바꾸면 07-15 이 4% 가 된다(⑥ 이 잡는다)")
M3 <- mutant("RAW[, ME_l1 := shift(Size, 1L), by = Ticker]", "RAW[, ME_l1 := Size]")
h3 <- M3$krf_build(copy(RAW0), FUND, RFY, cfg, RS = RS0)$daily[Date == d1]$HML
ok(isTRUE(abs(h3 - or_hml(v)) > 1e-9), "M3 가중을 그날 시총으로 바꾸면 일간 HML 이 오라클과 달라진다(③ 이 잡는다)")
M4 <- mutant("RD[, W := fifelse(is.finite(cap), pmin(ME_l1, cap), NA_real_)]", "RD[, W := ME_l1]")
h4 <- M4$krf_build(copy(RAW0), FUND, RFY, cfg, RS = RS0)$daily[Date == d1]$HML
ok(isTRUE(abs(h4 - or_hml(v)) > 1e-9), "M4 가중 상한을 지우면 일간 HML 이 오라클(상한 가치가중)과 달라진다(③ 이 잡는다)")
mk_mkt <- function(r) r$daily[Date == d1]$MKT_TOTAL
x_mkt <- merge(RAW0[Date == d1, .(Ticker, Ret)], RAW0[Date == as.Date("2011-07-04"), .(Ticker, ME = Size)], by = "Ticker")
x_mkt <- x_mkt[Ticker %in% RAW0[Date == as.Date("2011-06-30") & member == TRUE]$Ticker]
ok(isTRUE(abs(mk_mkt(res) - x_mkt[, sum(ME * Ret) / sum(ME)]) < 1e-12), "⑧ 대조 — 시장(MKT_TOTAL)은 상한 없는 가치가중(직전 월말 멤버)")
PICK <- "fifelse(!is.na(d) & d <= at, v, fifelse(!is.na(dr) & dr <= at & is.finite(vr), vr, NA_real_))"
M5 <- mutant(PICK, "fifelse(!is.na(d) & d <= at, v, NA_real_)")              # (d) v1.0 규칙(정정 의심 기업을 뺀다)으로 되돌림
ok(!("T12" %in% labs_of(M5, FUND2, RS2)[sort == "BM", Ticker]), "M5(d) 고르기를 v1.0 규칙으로 되돌리면 T12 가 정렬에서 빠진다((a) 가 잡는다)")
M6 <- mutant(PICK, "fifelse(!is.na(dr) & dr <= at & is.finite(vr), vr, fifelse(!is.na(d) & d <= at, v, NA_real_))")   # DART 기록을 먼저
ok(!identical(labs_of(M6, FUND, RS3)[order(sort, Ticker)], lab[order(sort, Ticker)]) ||
     !identical(M6$.krf_content_md5(M6$krf_build(copy(RAW0), FUND, RFY, cfg, RS = RS3)$monthly, cols), E$.krf_content_md5(res$monthly, cols)),
   "M6 퀀티 우선을 DART 기록 우선으로 바꾸면 (c) 가 잡는다(정렬 또는 월간 해시가 달라진다)")
M7 <- mutant("dr <= at & is.finite(vr)", "is.finite(vr)")                    # 기록 날짜 검사를 지움
ok("T18" %in% labs_of(M7, FUND2, RS2)[sort == "BM", Ticker], "M7 기록 날짜 검사를 지우면 T18(구성일 뒤 기록)이 들어온다((b) 가 잡는다)")

cat(sprintf("[test_kr_factor_returns] %d PASS / %d FAIL\n", pass, fail))
cat(toJSON(list(test = "kr_factor_returns", pass = pass, fail = fail, total = pass + fail), auto_unbox = TRUE), "\n")  # 배터리 요약 줄 — 키 test 필수(run_all_hooks.sh)
if (fail > 0L) quit(save = "no", status = 1L)
