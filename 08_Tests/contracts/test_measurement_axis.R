## test_measurement_axis.R — 측정 축 epoch 계약(MC1 · MC3) 검사기 (양방향 · 합성 데이터)
## 대상: 02_Infrastructure/contracts/measurement_axis.R · factor_db/factor_z_standard.R::corp_action_member(리팩터 동치)
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
.self <- tryCatch({ a <- commandArgs(trailingOnly = FALSE); f <- sub("^--file=", "", a[grepl("^--file=", a)])
                    if (length(f)) dirname(f[1]) else "." }, error = function(e) ".")
root <- normalizePath(file.path(.self, "..", ".."), winslash = "/", mustWork = FALSE)
if (!file.exists(file.path(root, "02_Infrastructure", "config.R"))) root <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(root)
invisible(capture.output(suppressMessages(source("02_Infrastructure/factor_db/factor_z_standard.R"))))
source("02_Infrastructure/contracts/measurement_axis.R")
pass <- 0L; fail <- 0L
chk <- function(name, ok, detail = "") {
  if (isTRUE(ok)) { pass <<- pass + 1L; cat(sprintf("  [PASS] %s\n", name)) } else { fail <<- fail + 1L; cat(sprintf("  [FAIL] %s %s\n", name, detail)) }
}
err <- function(expr) inherits(tryCatch({ force(expr); NULL }, error = function(e) e), "error")

cat("=== M1 · M2 설정 ===\n")
e0 <- ma_epoch(root = root); e1 <- ma_epoch("all_hyg_2000_v1", root = root)
cd <- fromJSON("02_Infrastructure/worktask/constraint_defaults.json", simplifyVector = FALSE)
e0 <- ma_epoch("k200kq150_2005_v1", root = root)                    # 구 축(전환 뒤 = 비활성)
chk("M1a active = 새 축(10-13 전환 · MEASUREMENT-AXIS-SWITCH) · 구 축 = K200_KQ150 · 2005-01-01 · 위생 없음 · 비활성",
    identical(ma_epoch(root = root)$id, "all_hyg_2000_v1") && identical(e0$universe, "K200_KQ150") &&
      identical(e0$start_date, as.Date("2005-01-01")) && !e0$hygiene && !e0$active)
chk("M1b 새 축 = ALL_HYG · 2000-01-01 · 하한 = tier_soft_deployment 정본 · 표식 3 · 활성", identical(e1$universe, "ALL_HYG") &&
      identical(e1$start_date, as.Date("2000-01-01")) && identical(e1$liq_min, as.numeric(cd$tier_soft_deployment$liquidity_min_won_20d_avg)) &&
      setequal(e1$excluded_flags, c("AdminStock", "TradingHalt", "UnfaithfulDisc")) && e1$active)
chk("M2 유니버스 → epoch(ALL_HYG = 활성 all_hyg_2000_v1 · K200_KQ150 = 유일한 구 축)",
    identical(ma_epoch_by_universe("ALL_HYG", root)$id, "all_hyg_2000_v1") && identical(ma_epoch_by_universe("K200_KQ150", root)$id, e0$id))

cat("\n=== 합성 세계 ===\n")
days <- seq(as.Date("2020-01-01"), by = "day", length.out = 60); days <- days[!format(days, "%u") %in% c("6", "7")]
mk <- function() {
  D <- CJ(Ticker = c("BIG", "SMALL", "FLAG", "NAFLG"), Date = days)
  D[, Close := 10000]; D[, Vol := fifelse(Ticker == "SMALL", 100, 1e5)]   # 거래대금: 1e9 · 1e6(하한 2e8 미만)
  D[, `:=`(AdminStock = 0, TradingHalt = 0, UnfaithfulDisc = 0)]
  D[Ticker == "NAFLG", `:=`(AdminStock = NA, TradingHalt = NA, UnfaithfulDisc = NA)]
  D[Ticker == "FLAG" & Date >= days[30] & Date <= days[33], AdminStock := 1]
  D[, `:=`(K200 = fifelse(Ticker == "BIG", 1, 0), KQ150 = 0)]
  setorder(D, Date, Ticker); D
}
D <- mk()

cat("=== M3 · M4 · M5 거래대금 · 멤버십 · PIT ===\n")
a <- ma_adv20_l1(D)
man <- D[Ticker == "BIG"][order(Date)]; man_a <- shift(frollmean(man$Close * man$Vol, 20L), 1L)
chk("M3a adv20(t−1) = 20일 평균을 하루 늦춤(수동 계산과 동일 · 첫 20일 NA)", isTRUE(all.equal(a[D$Ticker == "BIG"], man_a)) && sum(!is.na(a[D$Ticker == "BIG"])) == length(days) - 20L)
Ds <- D[sample(.N)]; as <- ma_adv20_l1(Ds)
chk("M3b 행 순서 무관(섞인 입력도 같은 값 · 입력 불변)", isTRUE(all.equal(as[match(paste(D$Ticker, D$Date), paste(Ds$Ticker, Ds$Date))], a)) &&
      identical(names(Ds), names(D)))
m <- ma_membership(D, e1)
chk("M4a 거래대금 하한 이상(BIG) = 멤버 · 미만(SMALL) = 아님 · 표식 NA(NAFLG) = 멤버", all(m[D$Ticker == "BIG" & !is.na(a)]) &&
      !any(m[D$Ticker == "SMALL"]) && all(m[D$Ticker == "NAFLG" & !is.na(a)]))
chk("M4b 관리종목 표식 기간(FLAG)만 탈락 · 나머지 날은 멤버", !any(m[D$Ticker == "FLAG" & D$Date >= days[30] & D$Date <= days[33]]) &&
      all(m[D$Ticker == "FLAG" & D$Date > days[33]]))
D2 <- mk(); D2[Ticker == "BIG" & Date == days[40], Vol := 0]
m2 <- ma_membership(D2, e1)
i40 <- which(D$Ticker == "BIG" & D$Date == days[40])
chk("M5a [PIT] 당일 거래량 0 은 그날 멤버십을 바꾸지 않는다(t−1 기준) · 다음 날 평균에만 반영", m2[i40] == m[i40] &&
      ma_adv20_l1(D2)[which(D$Ticker == "BIG" & D$Date == days[41])] < a[which(D$Ticker == "BIG" & D$Date == days[41])])
nD <- length(days); D3 <- mk(); D3[Ticker == "FLAG" & Date == days[nD - 1L], TradingHalt := 1]   # 평일만 남겨 약 43일 — 끝에서 센다
m3 <- ma_membership(D3, e1)
chk("M5b [PIT] 다음 날 표식은 오늘 멤버십을 바꾸지 않고 그날만 바꾼다", isTRUE(m3[which(D$Ticker == "FLAG" & D$Date == days[nD - 2L])]) &&
      isFALSE(m3[which(D$Ticker == "FLAG" & D$Date == days[nD - 1L])]) && isTRUE(m3[which(D$Ticker == "FLAG" & D$Date == days[nD])]))

cat("\n=== M6 · M7 주입 · 멈춤 ===\n")
DI <- mk(); orig_k <- DI$K200
inj <- ma_inject_universe(DI, e1); R <- inj$RAWDATA
chk("M6a 주입 — K200 := 위생 멤버십 · KQ150 := 0 · 원 플래그 = K200_IDX", identical(R$K200, as.numeric(m)) && all(R$KQ150 == 0) &&
      identical(R$K200_IDX, orig_k) && identical(inj$diag$mode, "injected"))
inj2 <- ma_inject_universe(R, e1)
chk("M6b 이중 주입이 원 플래그를 덮지 않는다(K200_IDX 유지 · 멤버십 재계산 동일)", identical(inj2$RAWDATA$K200_IDX, orig_k) && identical(inj2$RAWDATA$K200, as.numeric(m)))
DK <- mk(); before <- copy(DK); n0 <- ma_inject_universe(DK, e0)
chk("M6c 구 축(K200_KQ150) = 아무것도 안 한다(열 추가 0 · 값 동일 = 비트 동일 측정)", identical(n0$diag$mode, "noop") && identical(DK, before))
DM <- mk()[, UnfaithfulDisc := NULL]
chk("M7a 위생 표식 열이 없으면 멈춘다(멤버십을 지어내지 않는다)", err(ma_membership(DM, e1)))
chk("M7b 종가 · 거래량이 없으면 멈춘다", err(ma_adv20_l1(mk()[, Vol := NULL])))
chk("M7c 위생 epoch 가 아닌데 멤버십 요청 = 멈춤", err(ma_membership(mk(), e0)))

cat("\n=== M8 표준 필터 리팩터 동치 ===\n")
set.seed(7)
snap <- data.table(Date = rep(as.Date("2020-03-31"), 200), Ticker = sprintf("T%03d", 1:200),
                   LIQ_20d = c(NA, runif(199, 0, 5e8)), AdminStock = sample(c(0, 1, NA), 200, TRUE),
                   TradingHalt = sample(c(0, 1, NA), 200, TRUE), UnfaithfulDisc = sample(c(0, 1, NA), 200, TRUE))
old_filter <- function(sig_snap, sig_date, liq_threshold = 2e8)
  sig_snap[Date == sig_date & !is.na(LIQ_20d) & LIQ_20d >= liq_threshold & (is.na(AdminStock) | AdminStock == 0) &
             (is.na(TradingHalt) | TradingHalt == 0) & (is.na(UnfaithfulDisc) | UnfaithfulDisc == 0)]
chk("M8 universe_corp_action_filter(리팩터) = 구판 인라인 식(NA · 표식 · 하한 경계 포함)",
    identical(universe_corp_action_filter(snap, as.Date("2020-03-31")), old_filter(snap, as.Date("2020-03-31"))) &&
      identical(universe_corp_action_filter(snap, as.Date("2020-03-31"), 3e8), old_filter(snap, as.Date("2020-03-31"), 3e8)))

cat("\n=== M9 · M10 문구 · 커버리지 기록 ===\n")
chk("M9 FIDELITY 유니버스 문구 — 구 축은 구판 문구 그대로 · 새 축은 위생 명시",
    identical(ma_fidelity_universe("K200_KQ150"), "universe 치환(K200∪KQ150)") && grepl("전 종목 + 위생", ma_fidelity_universe("ALL_HYG"), fixed = TRUE))
sc <- ma_signal_coverage(R[K200 == 1, list(Date, Ticker)], R)
chk("M10 신호 커버리지 기록(자르지 않음) — 첫 신호일 · 연도별 폭/멤버 중앙값", identical(sc$status, "ok") && nrow(sc$by_year) >= 1L &&
      identical(sc$first_signal_date, format(min(R[K200 == 1]$Date))))

cat("\n=== M11~M18 실효 시작(MC3 B안 · 도훈 10-13 · MC3-EFFECTIVE-START-B) ===\n")
rl <- e1$effective_start
chk("M11a 새 축 규칙 판독 = breadth_multiple · 배수 = 설정 정본(2) · 창 기준 = effective_start · 구 축 = 규칙 없음(NULL)",
    identical(rl$rule, "breadth_multiple") &&
      identical(rl$breadth_mult, as.numeric(cd$measurement_axis$epochs$all_hyg_2000_v1$effective_start$breadth_mult)) &&
      identical(rl$window_anchor, "effective_start") && is.null(e0$effective_start))
chk("M11b 형식 오류는 멈춘다(배수 ≤ 1 · 배수 없음 · 모르는 규칙 · 모르는 창 기준) · 정상 형식은 통과",
    err(.ma_eff_rule(list(rule = "breadth_multiple", breadth_mult = 1, window_anchor = "effective_start"), "t")) &&
      err(.ma_eff_rule(list(rule = "breadth_multiple", window_anchor = "effective_start"), "t")) &&
      err(.ma_eff_rule(list(rule = "relative_coverage", breadth_mult = 2, window_anchor = "effective_start"), "t")) &&
      err(.ma_eff_rule(list(rule = "breadth_multiple", breadth_mult = 2, window_anchor = "axis"), "t")) &&
      !err(.ma_eff_rule(list(rule = "breadth_multiple", breadth_mult = 2, window_anchor = "diagnostics"), "t")))
# 합성: 신호일 6개 · 보유 25종 고정 · 신호 폭 30 · 40 · 60 · 45 · 80 · 90 (배수 2 → 문턱 50)
sd6 <- as.Date(c("2001-01-31", "2001-02-28", "2001-03-30", "2001-04-30", "2001-05-31", "2001-06-29"))
bw6 <- c(30L, 40L, 60L, 45L, 80L, 90L)
mkF <- function(bw) rbindlist(lapply(seq_along(sd6), function(i) data.table(Date = sd6[i], Ticker = sprintf("T%03d", seq_len(bw[i])), Score = rnorm(bw[i]))))
mkW <- function(n = 25L) rbindlist(lapply(sd6, function(d) data.table(Date = d, Ticker = sprintf("T%03d", seq_len(n)), Weight = 1 / n)))
set.seed(11); F6 <- mkF(bw6); W6 <- mkW()
es6 <- ma_effective_start(F6, W6, rl)
chk("M12 실효 시작 = 폭 ≥ 보유 × 2 를 처음 만족한 신호일(60 ≥ 50 → 3번째) · 앞 2개 제외 · 시작 뒤 문턱 아래(45) 1개는 자르지 않고 기록",
    identical(es6$status, "ok") && identical(es6$date, "2001-03-30") && identical(es6$n_dates_cut, 2L) &&
      identical(es6$n_dates_below_after, 1L) && identical(as.integer(es6$breadth_at_start), 60L) && identical(as.integer(es6$holdings_at_start), 25L),
    paste(unlist(es6[c("status", "date", "n_dates_cut", "n_dates_below_after")]), collapse = ","))
F6f <- copy(F6)[Date > as.Date("2001-03-30")]; F6f <- rbind(F6[Date <= as.Date("2001-03-30")], F6f[, .SD[1:5], by = Date])   # 뒷날 폭을 5로
chk("M13 [PIT] 뒷날 폭을 바꿔도 실효 시작은 그대로(첫 통과 — 그날까지 값만) · 대조: 그날(3번째) 폭을 49로 낮추면 5번째로 밀린다",
    identical(ma_effective_start(F6f, W6, rl)$date, "2001-03-30") &&
      identical(ma_effective_start(mkF(replace(bw6, 3L, 49L)), W6, rl)$date, "2001-05-31"))
W6z <- copy(W6); W6z <- rbind(W6z, data.table(Date = sd6[1], Ticker = sprintf("Z%03d", 1:30), Weight = 0))   # 비중 0 행 30개
chk("M14 보유 수 = 비중 ≠ 0 종목만(비중 0 행은 세지 않는다 — 넣어도 실효 시작 동일)", identical(ma_effective_start(F6, W6z, rl)$date, es6$date))
F6n <- copy(F6); F6n[Date == sd6[3], Score := NA_real_]
chk("M15 점수 결측 행은 폭에 넣지 않는다(3번째 날 점수 전부 결측 → 폭 0 → 5번째로)", identical(ma_effective_start(F6n, W6, rl)$date, "2001-05-31"))
pu <- ma_effective_start(NULL, W6, rl)
chk("M16 PORTFOLIO 만 내는 엔진(FACTORS 없음) → 폭 미측정 표식 · 자르지 않음(실효 시작 = 첫 신호일)",
    identical(pu$status, "breadth_unmeasurable") && identical(pu$date, "2001-01-31") && identical(pu$n_dates_cut, 0L))
nm <- ma_effective_start(mkF(rep(40L, 6)), W6, rl)
chk("M17 한 번도 못 미치면 never_met(선정이 성립한 신호일 없음) · 규칙 없는 epoch = no_rule",
    identical(nm$status, "never_met") && is.na(nm$date) && identical(ma_effective_start(F6, W6, NULL)$status, "no_rule"))
rec <- c(ma_record(e1), list(effective_start = es6))
rec_d <- rec; rec_d$effective_start_rule$window_anchor <- "diagnostics"
chk("M18a 창 기준일 = 기록된 실효 시작(규칙 window_anchor = effective_start) · 규칙이 diagnostics 거나 기록이 없으면 NA(전역 기준으로)",
    identical(ma_window_anchor(rec), as.Date("2001-03-30")) && is.na(ma_window_anchor(rec_d)) &&
      is.na(ma_window_anchor(ma_record(e1))) && is.na(ma_window_anchor(NULL)))
## M19~M21 — 상위 N 만 FACTORS 로 내는 엔진(셀 엔진) · 10-13 P0 측정 직전 발견: FACTORS 폭 = 25 라 규칙이 영영 안 선다(never_met → 측정 중단)
F25 <- rbindlist(lapply(sd6, function(d) data.table(Date = d, Ticker = sprintf("T%03d", 1:25), Score = rnorm(25))))   # 미리 잘린 패널
BR6 <- data.table(Date = sd6, breadth = bw6)                                                                       # 엔진 보고 선정 전 폭
er <- ma_effective_start(F25, W6, rl, breadth = BR6)
chk("M19 엔진 보고 폭이 있으면 그것으로 판정(미리 잘린 FACTORS 를 무시) — 결과 = M12 와 같음 · basis engine_reported",
    identical(er$status, "ok") && identical(er$date, es6$date) && identical(er$basis, "engine_reported") && identical(er$n_dates_cut, 2L))
pt <- ma_effective_start(F25, W6, rl)
chk("M20 보고 없이 미리 잘린 FACTORS(모든 날 폭 ≤ 보유) → 폭 미측정(factors_pretruncated) · 자르지 않음 · 멈추지 않음 · 대조: 폭이 보유를 넘는 날이 있는데 2배 미달이면 never_met",
    identical(pt$status, "breadth_unmeasurable") && identical(pt$basis, "factors_pretruncated") && identical(pt$n_dates_cut, 0L) &&
      identical(ma_effective_start(mkF(rep(40L, 6)), W6, rl)$status, "never_met"))
scb <- ma_signal_coverage(NULL, NULL, breadth = BR6)
chk("M21 커버리지 기록도 엔진 보고 폭을 쓴다(basis engine_reported · 중앙 > 25)", identical(scb$basis, "engine_reported") && scb$by_year$breadth_median > 25)
scf <- ma_signal_coverage(F6, NULL, basis = "factors"); sch <- ma_signal_coverage(W6, NULL, basis = "holdings")
chk("M18b 커버리지 폭은 선정 전 패널(FACTORS)에서 — 보유 패널로 재면 25로 눌린다(10-13 첫 기록의 결함 · 대조)",
    identical(scf$basis, "factors") && scf$by_year$breadth_median > 25 && identical(sch$by_year$breadth_median, 25))

cat(sprintf("\n== measurement_axis: PASS %d · FAIL %d ==\n", pass, fail))
cat(sprintf('{"test":"measurement_axis","pass":%d,"fail":%d,"total":%d}\n', pass, fail, pass + fail))
if (fail > 0L) quit(status = 1L)
