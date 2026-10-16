## P3R03 evaluate.R 순수 도우미 픽스처 검사(합성 · 결과 무접촉 · 사전등록 고정 대상) — 본 실행 블록은 sys.nframe() > 0 이라 안 돈다
## 실행: Rscript evaluate_fixture.R
##   1 공통 창 사본 · 2 위기 짝 과반 · 3 방법별 진단 줄 파싱(5 태그 · 키 접두 혼동 없음) · 4 이력 탈락 · 5 처치 전달률 · 6 위기 보유 집행일 ·
##   7 β 대조 · 8 알파 비열등(t 문턱 · NA) · 9 깊은 위기 · 집중 손실 · β 짝 사본 · 10 라운드 판정(판정 칸 수 표기)
##   v2(격리 교차 점검 반영): 11 사이클 짝 — 실제 보는 창 벤치 연대기(위기 7 · 강세 5)로 '짝 3(2011 · 2017-11 · 2021-06) · 코로나 짝 없음 · 강세 1회 사용' ·
##   12 미측정은 통과로 접지 않는다(집중 손실 · β 대조) · 13 같은 선정 집합 · 14 후보 꼬리표 · 15 핀 재대조 · 16 판정 1칸 조기 미시험 경로
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat("  OK  ", m, "\n") }
ng <- function(m, d = "") { FAIL <<- FAIL + 1L; cat("  FAIL", m, d, "\n") }
source("C:/Users/99922/OneDrive/Quant_Module_Moltbot/04_Research/programs/_lib/round_kit.R")
source("C:/Users/99922/OneDrive/Quant_Module_Moltbot/04_Research/programs/P3_CONSTRUCTION/P3R03_advanced_construction/evaluate.R")
if (exists("EVS")) ng("본 실행 블록이 source 에서 돌았다") else ok("source 시 본 실행 블록 미실행(sys.nframe 가드)")
J <- function(dt) fromJSON(toJSON(dt, na = "null"), simplifyVector = FALSE)

## 1) 공통 창 사본
src <- file.path(tempdir(), "p3r03_src"); out <- file.path(tempdir(), "p3r03_out"); unlink(c(src, out), recursive = TRUE); dir.create(src)
d <- seq(as.Date("2005-01-03"), by = "day", length.out = 40); r <- c(rep(0.01, 10), rep(-0.02, 10), rep(0.005, 20)); nav <- cumprod(1 + r)
fwrite(data.table(date = d, ret_net = r), file.path(src, "03_period_returns.csv"))
fwrite(data.table(date = d, benchmark_ret = r / 2, benchmark_nav = cumprod(1 + r / 2)), file.path(src, "05_benchmark_returns.csv"))
fwrite(data.table(date = d, nav_gross = nav * 1.001, nav_net = nav, cum_cost = nav * 0.001, drawdown_net = nav / cummax(nav) - 1), file.path(src, "02_nav.csv"))
fwrite(data.table(date = rep(d[c(1, 15, 30)], each = 2), ticker = rep(c("000660", "005930"), 3), target_weight = 0.5), file.path(src, "04_holdings.csv"))
writeLines('{"y":2}', file.path(src, "authoritative_remeasure.json"))
st <- d[20]; p3_trim_artifacts(src, out, st)
nv2 <- fread(file.path(out, "02_nav.csv")); H2 <- fread(file.path(out, "04_holdings.csv"), colClasses = list(character = "ticker"))
if (min(as.Date(nv2$date)) == st && abs(nv2$nav_net[1] - 1) < 1e-12 && abs(nv2$drawdown_net[1]) < 1e-12) ok("1a NAV 재기준 · 낙폭 재계산") else ng("1a")
if (identical(sort(unique(as.character(as.Date(H2$date)))), as.character(d[c(15, 30)])) && identical(H2$ticker[1], "000660") &&
    file.exists(file.path(out, "authoritative_remeasure.json"))) ok("1b 보유 = 시작에 들고 있던 리밸부터 · 선행 0 보존 · 비 CSV 복사") else ng("1b")

## 2) 위기 짝 과반
crm <- J(data.table(peak_date = c("2008-05-16", "2011-07-29", "2020-01-17"), trough_date = c("2008-10-24", "2011-09-26", "2020-03-19"), cum_capture = c(0.60, 0.95, 0.70)))
crr <- J(data.table(peak_date = c("2008-05-16", "2011-07-29", "2020-01-17"), trough_date = c("2008-10-24", "2011-09-26", "2020-03-19"), cum_capture = c(0.80, 0.90, 0.75)))
mj <- p3_crisis_majority(crm, crr, 1e-9)
if (mj$n_pair == 3L && mj$n_better == 2L && abs(mj$share - 2/3) < 1e-12 && mj$unpaired == 0L) ok("2a 짝 3 · 개선 2 · 비율 2/3 · 짝 없음 0") else ng("2a")
if (p3_crisis_majority(crm, crr, 0.5)$n_better == 0L && is.na(p3_crisis_majority(list(), crr, 1e-9)$share)) ok("2b tol 반영 · 위기 없음 → NA") else ng("2b")
if (p3_crisis_majority(crm[1:2], crr, 1e-9)$unpaired == 1L) ok("2c 한 칸에만 있는 위기 = 짝 없음 1(평가는 이것이 0 이 아니면 미시험)") else ng("2c")

## 3) 방법별 진단 줄 파싱 — 5 태그 · 키 접두 혼동 없음(rc_dev · mp_var · nfacts)
COV <- "[rf_cell_engine] catalog paper:X | 차별화 250 · EW폴백 3 · 커버리지 98.4% (선정일 254/258) · 유니버스 지지 100.0% (빈 시그널일 0 — 비중 무관)"
LN <- list(
  hrp = "[hrp] d=2005-01-31 n=23 maxw=0.1200 effn=14.20",
  nco = "[nco] d=2005-01-31 n=23 q=10.96 nfacts=2 mp_var=0.8123 k=4 maxw=0.3100 effn=5.10",
  michaud = "[michaud] d=2005-01-31 n=23 B=500 T=252 mcse=0.00370 maxw=0.2900 effn=6.30",
  cvar = "[cvar] d=2005-01-31 n=23 T=252 beta=0.95 cvar=0.016525 var=0.013696 active=7 maxw=0.5780 effn=3.10",
  erc = "[erc] d=2005-01-31 n=23 iter=15 rc_dev=2.43e-13 maxw=0.0750 effn=18.63")
for (tg in names(LN)) {
  L <- c(COV, LN[[tg]], sub("2005-01-31", "2005-02-28", LN[[tg]]), "[method:paper:X] 어댑터 실패 → EW 폴백: 자산 3종 미만 — 하네스가 먼저 EW 로 처리한다")
  pl <- p3_parse_cell_log(L, tg)
  okk <- nrow(pl$diag) == 2L && identical(pl$diag$n[1], 23L) && identical(as.character(pl$diag$d), c("2005-01-31", "2005-02-28")) &&
    is.finite(pl$diag$maxw[1]) && is.finite(pl$diag$effn[1]) && identical(pl$coverage$n_try, 258) && pl$n_method_fallback == 1L &&
    identical(pl$fallback_by_reason$under_3_assets, 1L)
  if (okk) ok(sprintf("3 %s 진단 줄 → d · n · maxw · effn · 커버리지 · 폴백 사유", tg)) else ng(sprintf("3 %s", tg), paste(capture.output(print(pl$diag)), collapse = " "))
}
pl_x <- p3_parse_cell_log(c(COV, LN$hrp), "nco")
if (nrow(pl_x$diag) == 0L) ok("3f 다른 방법 태그 줄은 세지 않는다(hrp 줄을 nco 로 안 읽음)") else ng("3f")
pl_e <- p3_parse_cell_log(c(COV, LN$erc), "erc")
if (identical(as.character(pl_e$diag$d), "2005-01-31")) ok("3g 'rc_dev=' 의 'd=' 를 날짜로 읽지 않는다(키 앞 공백)") else ng("3g", as.character(pl_e$diag$d))

## 4) 이력 탈락
Dd <- data.table(d = as.Date(c("2005-01-31", "2005-02-28", "2005-03-31")), n = c(23L, 4L, 25L), maxw = 0.1, effn = 10)
Hr <- data.table(date = as.Date(c(rep("2005-02-01", 25), rep("2005-03-02", 25), rep("2005-04-01", 25))), ticker = sprintf("%06d", 1:75), w = 0.04)
hd <- p3_history_drops(Dd, Hr)
if (identical(hd$drops, c(2L, 21L, 0L)) && identical(as.character(hd$exec), c("2005-02-01", "2005-03-02", "2005-04-01"))) ok("4 탈락 = 선정 25 − n · 다음 첫 집행일 짝") else ng("4", paste(hd$drops))

## 5) 처치 전달률 = 진단 줄 고유 신호일 / n_try
pl5 <- p3_parse_cell_log(c(COV, LN$hrp, LN$hrp, sub("2005-01-31", "2005-02-28", LN$hrp)), "hrp")
if (isTRUE(all.equal(p3_delivery(pl5), 2 / 258))) ok("5a 전달률 = 고유 신호일 2(중복 줄 1 제외) / 258") else ng("5a", p3_delivery(pl5))
if (is.na(p3_delivery(p3_parse_cell_log(LN$hrp, "hrp")))) ok("5b 커버리지 줄 없음 → NA(미시험)") else ng("5b")

## 6) 위기 보유 집행일
ex <- as.Date(c("2008-04-01", "2008-05-02", "2008-06-02", "2008-07-01", "2008-11-03", "2011-07-01", "2011-08-01"))
crj <- J(data.table(peak_date = c("2008-05-16", "2011-07-29"), trough_date = c("2008-10-24", "2011-09-26")))
if (identical(as.character(p3_crisis_execs(ex, crj)), c("2008-05-02", "2008-06-02", "2008-07-01", "2011-07-01", "2011-08-01"))) ok("6 위기 보유 집행일") else ng("6")

## 7) β 대조(선택 기여 짝)
exm <- J(data.table(peak_date = c("2008-05-16", "2011-07-29", "2020-01-17"), trough_date = c("2008-10-24", "2011-09-26", "2020-03-19"), selection_sum = c(0.02, -0.01, 0.03)))
exr <- J(data.table(peak_date = c("2008-05-16", "2011-07-29", "2020-01-17"), trough_date = c("2008-10-24", "2011-09-26", "2020-03-19"), selection_sum = c(0.01, 0.00, 0.04)))
sv <- p3_selection_vs_ref(exm, exr)
if (sv$n_pair == 3L && sv$n_better == 1L && is.na(p3_selection_vs_ref(list(), exr)$share)) ok("7 선택 기여 개선 1/3 · 노출 분해 없음 NA") else ng("7")

## 8) 알파 비열등 — t > 문턱(−2) ∧ 증분 ≥ −여유 × max(엔진 알파, 0) · NA 는 NA(미시험 — FALSE 로 접지 않음)
if (isTRUE(p3_alpha_ok(list(t = -1.5, d_alpha = -0.01), -2, 0.10, 0.2)) &&                       # −1% ≥ −2%(엔진 10% 의 20%)
    identical(p3_alpha_ok(list(t = -1.5, d_alpha = -0.03), -2, 0.10, 0.2), FALSE) &&              # −3% < −2% — 여유 초과
    identical(p3_alpha_ok(list(t = -2.4, d_alpha = 0.00), -2, 0.10, 0.2), FALSE) &&               # t 문턱
    identical(p3_alpha_ok(list(t = -2, d_alpha = 0.00), -2, 0.10, 0.2), FALSE) &&                 # 경계 = 탈락
    identical(p3_alpha_ok(list(t = -0.5, d_alpha = -0.001), -2, -0.05, 0.2), FALSE) &&            # 엔진 알파 ≤ 0 → 여유 0
    is.na(p3_alpha_ok(list(t = NA, d_alpha = 0), -2, 0.1, 0.2)) && is.na(p3_alpha_ok(list(t = 1, d_alpha = 0), -2, NA, 0.2)))
  ok("8 알파 비열등 — t 문턱 · 엔진 알파 비례 여유 · 엔진 알파 ≤ 0 이면 여유 0 · NA 는 NA") else ng("8")

## 9) 깊은 위기 · 지정 위기 과반(dd_capture) · 집중 손실 · β 짝 사본
crm9 <- J(data.table(peak_date = c("2008-05-16", "2011-07-29", "2015-08-10", "2020-01-17"), trough_date = c("2008-10-24", "2011-09-26", "2015-08-24", "2020-03-19"),
                     bm_dd = c(-0.50, -0.20, -0.10, -0.35), dd_capture = c(0.90, 0.60, 0.50, 0.70), st_cum = c(-0.40, -0.10, -0.05, -0.25)))
crr9 <- J(data.table(peak_date = c("2008-05-16", "2011-07-29", "2015-08-10", "2020-01-17"), trough_date = c("2008-10-24", "2011-09-26", "2015-08-24", "2020-03-19"),
                     bm_dd = c(-0.50, -0.20, -0.10, -0.35), dd_capture = c(0.95, 0.90, 0.80, 0.75), st_cum = c(-0.45, -0.18, -0.08, -0.28)))
dk <- p3_deep_crisis_keys(crm9, crr9)
if (identical(sort(dk), sort(c("2008-05-16 2008-10-24", "2020-01-17 2020-03-19")))) ok("9a 깊은 위기 = 벤치 낙폭 크기 ≥ 중앙값(2008 · 2020)") else ng("9a", paste(dk))
dm9 <- p3_crisis_majority(crm9, crr9, 0.03, metric = "dd_capture", subset = dk)
if (dm9$n_pair == 2L && dm9$n_better == 2L && abs(dm9$share - 1) < 1e-12) ok("9b 깊은 위기 과반 — 2008 0.90 vs 0.95 · 2020 0.70 vs 0.75(둘 다 0.05 > 0.03 개선) → 비율 1") else
  ng("9b", paste(dm9$n_pair, dm9$n_better))
all9 <- p3_crisis_majority(crm9, crr9, 0.03, metric = "dd_capture")
if (all9$n_pair == 4L && all9$n_better == 4L) ok("9c 전체 위기 과반(dd_capture · 실질 문턱 0.03)") else ng("9c", paste(all9$n_pair, all9$n_better))
if (p3_crisis_majority(crm9, crr9, 0.06, metric = "dd_capture")$n_better == 2L) ok("9d 문턱 0.06 이면 0.05 개선은 개선 아님(잡음 배제)") else ng("9d")
tl <- J(data.table(peak_date = c(rep("2008-05-16", 4), rep("2011-07-29", 2)), Ticker = c("A", "B", "C", "D", "E", "F"), contrib = c(-0.18, -0.03, -0.02, -0.01, -0.12, -0.01)))
t9 <- p3_top_loss(tl, c("2008-05-16", "2020-01-17"), -0.10)
if (identical(t9$status, "partial") && identical(t9$missing_deep, "2020-01-17") && t9$n_breach == 1L && abs(t9$deep_top1_min + 0.18) < 1e-12 &&
    abs(t9$per_crisis[peak_date == "2008-05-16"]$top3 + 0.23) < 1e-12 && identical(p3_conc_status(t9), "breach"))
  ok("9f 집중 손실 — 깊은 위기(2008) 한 종목 −18% < −10% → breach(2020 누락이어도 위반은 위반) · 2011(깊지 않음) −12% 는 세지 않음 · 상위 3 합") else ng("9f")
if (identical(p3_top_loss(list(), "2008-05-16", -0.1)$status, "unmeasured")) ok("9g 종목 손실 표 없음 → 미측정(0 으로 접지 않음)") else ng("9g")
bsrc <- file.path(tempdir(), "p3r03_bsrc"); bout <- file.path(tempdir(), "p3r03_bout"); unlink(c(bsrc, bout), recursive = TRUE); dir.create(bsrc)
for (f in c("03_period_returns.csv", "05_benchmark_returns.csv", "02_nav.csv", "04_holdings.csv", "authoritative_remeasure.json")) file.copy(file.path(src, f), bsrc)
p3_beta_scaled_copy(bsrc, bout, 0.8)
pr_s <- fread(file.path(bout, "03_period_returns.csv")); nv_s <- fread(file.path(bout, "02_nav.csv")); H_s <- fread(file.path(bout, "04_holdings.csv"), colClasses = list(character = "ticker"))
br_s <- fread(file.path(bout, "05_benchmark_returns.csv")); br_0 <- fread(file.path(bsrc, "05_benchmark_returns.csv"))
if (isTRUE(all.equal(pr_s$ret_net, 0.8 * r)) && isTRUE(all.equal(nv_s$nav_net, nav[1] * cumprod(1 + 0.8 * r))) && isTRUE(all.equal(H_s$target_weight, rep(0.4, 6))) &&
    identical(H_s$ticker[1], "000660") && isTRUE(all.equal(br_s$benchmark_ret, br_0$benchmark_ret)) && file.exists(file.path(bout, "authoritative_remeasure.json")) &&
    isTRUE(all.equal(nv_s$drawdown_net, nv_s$nav_net / cummax(nv_s$nav_net) - 1)))
  ok("9h β 짝 사본 — 수익 k 배 · NAV 재누적 · 보유 k 배(Σw = k) · 벤치 그대로 · 낙폭 재계산") else ng("9h")
if (inherits(try(p3_beta_scaled_copy(bsrc, bout, 1.2), silent = TRUE), "try-error")) ok("9i β 짝 k > 1 거부") else ng("9i")

## 10) 라운드 판정 — 판정 칸 수 표기
T1 <- data.table(engine = rep(c("E2", "E3"), each = 2), method = rep(c("HRP", "ERC"), 2), tested = TRUE, pass = c(TRUE, FALSE, TRUE, TRUE))
v1 <- p3_round_verdict(T1)
if (identical(v1$verdict, "supported") && identical(sort(v1$both), "HRP") && identical(v1$one, "ERC") && identical(v1$label, "supported(판정 4/4)"))
  ok("10a 두 엔진 통과 HRP → supported(판정 4/4) · ERC 한 엔진") else ng("10a", v1$label)
T2 <- copy(T1)[, pass := c(TRUE, FALSE, FALSE, FALSE)]
if (identical(p3_round_verdict(T2)$verdict, "partial")) ok("10b 한 엔진만 통과 → partial") else ng("10b")
T3 <- copy(T1)[, pass := FALSE][1:2, tested := FALSE]
v3 <- p3_round_verdict(T3)
if (identical(v3$verdict, "falsified") && identical(v3$label, "falsified(판정 2/4)")) ok("10c 통과 없음 → falsified(판정 2/4 — 판정된 칸 수를 함께 적는다)") else ng("10c", v3$label)
T4 <- copy(T1)[, tested := FALSE]
if (identical(p3_round_verdict(T4)$label, "untested(판정 0/4)") && identical(p3_round_verdict(data.table())$verdict, "untested")) ok("10d 미시험 → untested(판정 0/4 · 반증 아님)") else ng("10d")
T5 <- data.table(engine = c("E2", "E3"), method = "NCO", tested = c(TRUE, FALSE), pass = c(TRUE, FALSE))
if (identical(p3_round_verdict(T5)$verdict, "partial")) ok("10e 한 엔진 미시험 · 한 엔진 통과 → partial(두 엔진 통과 아님)") else ng("10e")
T6 <- data.table(engine = c("E2", "E3"), method = "CVR", tested = TRUE, pass = TRUE, excluded = c(TRUE, FALSE))
v6 <- p3_round_verdict(T6)
if (identical(v6$verdict, "partial") && identical(v6$excluded, "CVR") && !length(v6$both)) ok("10f 두 엔진 통과여도 집중 손실(또는 미측정)이면 후보 제외 → partial · 제외 목록") else ng("10f", v6$verdict)

## 11) 사이클 짝 — 실제 보는 창 벤치 연대기(위기 7 · 강세 5 — 날짜만 · 성과는 합성)
CRISES <- data.table(peak_date = c("2007-10-11", "2008-05-16", "2008-11-05", "2011-05-02", "2017-11-03", "2020-01-22", "2021-06-25"),
                     trough_date = c("2008-03-17", "2008-10-24", "2008-11-20", "2011-09-26", "2019-08-07", "2020-03-19", "2022-09-30"))
BULLS <- data.table(start_ym = c("2009-03", "2011-10", "2013-07", "2016-02", "2020-04"), end_ym = c("2011-04", "2013-02", "2014-07", "2017-10", "2021-06"))
bu_m <- J(copy(BULLS)[, st_cum := c(0.80, 0.30, 0.20, 0.40, 0.90)]); bu_r <- J(copy(BULLS)[, st_cum := c(0.90, 0.35, 0.25, 0.45, 1.00)])
cr_m <- J(copy(CRISES)[, st_cum := c(-0.20, -0.40, -0.05, -0.12, -0.15, -0.25, -0.20)]); cr_r <- J(copy(CRISES)[, st_cum := c(-0.25, -0.45, -0.06, -0.20, -0.10, -0.28, -0.30)])
cp <- p3_cycle_pairs(bu_m, cr_m)
want <- data.table(k = c("2011-05-02 2011-09-26", "2017-11-03 2019-08-07", "2021-06-25 2022-09-30"), bull = c("2009-03 2011-04", "2016-02 2017-10", "2020-04 2021-06"))
if (identical(cp$pairs$k, want$k) && identical(cp$pairs$bull, want$bull)) ok("11a 짝 3 = 2011-05↔2009-03~2011-04 · 2017-11↔2016-02~2017-10 · 2021-06↔2020-04~2021-06") else
  ng("11a", paste(cp$pairs$k, cp$pairs$bull, collapse = " | "))
if (identical(cp$unpaired, c("2007-10-11 2008-03-17", "2008-05-16 2008-10-24", "2008-11-05 2008-11-20", "2020-01-22 2020-03-19")))
  ok("11b 짝 없는 위기 = GFC 3구간 · 코로나(2020-01) — 직전 위기 바닥 이후 · 고점 이전 강세가 없다") else ng("11b", paste(cp$unpaired, collapse = " | "))
if (!anyDuplicated(cp$pairs$bull) && !("2016-02 2017-10" %in% cp$pairs[k == "2020-01-22 2020-03-19", bull]))
  ok("11c 강세 1회 사용 — 2016-02~2017-10 강세가 코로나 위기에 다시 쓰이지 않는다(구 구현 결함)") else ng("11c")
cy <- p3_cycle_compound(bu_m, cr_m, bu_r, cr_r)
## 2011: 1.8·0.88=1.584 vs 1.9·0.80=1.52 → ≥ · 2017-11: 1.4·0.85=1.19 vs 1.45·0.90=1.305 → < · 2021-06: 1.9·0.80=1.52 vs 2.0·0.70=1.40 → ≥
if (cy$n_pair == 3L && cy$n_ge == 2L && abs(cy$share - 2/3) < 1e-12 && length(cy$unpaired_crises) == 4L && cy$pair_mismatch == 0L)
  ok("11d 사이클 복리 — 짝 3 · 칸 ≥ 기준 2/3 · 짝 없는 위기 4 기록") else ng("11d", paste(cy$n_pair, cy$n_ge, cy$share))
cy1 <- p3_cycle_compound(J(BULLS[1][, st_cum := 0.8]), J(CRISES[1:4][, st_cum := -0.1]), J(BULLS[1][, st_cum := 0.9]), J(CRISES[1:4][, st_cum := -0.2]))
if (cy1$n_pair == 1L && is.na(cy1$share)) ok("11e 짝 1 < 2 → 비율 NA(미시험 — 판정 입력 NA)") else ng("11e", paste(cy1$n_pair, cy1$share))
cpm <- p3_cycle_pairs(J(copy(BULLS)[, st_cum := 0.1]), J(copy(CRISES)[c(7, 1, 4, 5, 2, 6, 3)][, st_cum := -0.1]))
if (identical(cpm$pairs$k, want$k)) ok("11f 위기 입력 순서와 무관(고점 순 정렬)") else ng("11f")

## 12) 미측정은 통과로 접지 않는다 — 집중 상태 · β 짝 판정
tl_ok <- J(data.table(peak_date = c("2008-05-16", "2020-01-17"), Ticker = c("A", "B"), contrib = c(-0.05, -0.04)))
tl_miss <- J(data.table(peak_date = "2008-05-16", Ticker = "A", contrib = -0.05))
if (identical(p3_conc_status(p3_top_loss(tl_ok, c("2008-05-16", "2020-01-17"), -0.10)), "clear") &&
    identical(p3_conc_status(p3_top_loss(tl_miss, c("2008-05-16", "2020-01-17"), -0.10)), "unmeasured") &&
    identical(p3_conc_status(p3_top_loss(list(), c("2008-05-16"), -0.10)), "unmeasured"))
  ok("12a 집중 상태 — 깊은 위기 전부 · 위반 없음 = clear · 깊은 위기 누락 · 표 없음 = unmeasured(후보 제외)") else ng("12a")
b1 <- p3_beta_verdict(NA_real_, 0.5, 0.6, 0.75, 0.5); b2 <- p3_beta_verdict(1.05, 0.5, NA, NA, 0.5); b3 <- p3_beta_verdict(0.9, 0.5, NA, NA, 0.5, err = "x")
b4 <- p3_beta_verdict(0.9, 0.5, NA, 0.75, 0.5); b5 <- p3_beta_verdict(0.9, 0.5, 0.6, 0.75, 0.5); b6 <- p3_beta_verdict(0.9, 0.7, 0.6, 0.75, 0.5)
b7 <- p3_beta_verdict(0.9, 0.5, 0.6, 0.5, 0.5)
if (identical(b1$status, "unmeasured") && is.na(b1$beats) && identical(b2$status, "not_needed") && isTRUE(b2$beats) &&
    identical(b3$status, "unmeasured") && is.na(b3$beats) && identical(b4$status, "unmeasured") && is.na(b4$beats) &&
    identical(b5$status, "ok") && isTRUE(b5$beats) && identical(b6$beats, FALSE) && identical(b7$beats, FALSE))
  ok("12b β 짝 — k 비유한 · 사본 실패 · 사본 입력 NA = 미측정(NA · 통과 아님) · k ≥ 1 = 불필요 · 중앙값 · 깊은 위기 과반(경계 0.5 는 과반 아님)") else ng("12b")

## 13) 같은 선정 집합(변형 보유 ⊆ RX0 보유 · 방법 해를 낸 신호일)
D13 <- data.table(d = as.Date(c("2005-01-31", "2005-02-28")), n = 2L, maxw = 0.5, effn = 2)
HR <- data.table(date = as.Date(c(rep("2005-02-01", 3), rep("2005-03-02", 3))), ticker = c("A", "B", "C", "A", "B", "D"), w = 1/3)
HV <- data.table(date = as.Date(c(rep("2005-02-01", 2), rep("2005-03-02", 2))), ticker = c("A", "B", "A", "D"), w = 0.5)
s1 <- p3_subset_check(D13, HV, HR)
s2 <- p3_subset_check(D13, copy(HV)[4, ticker := "E"], HR)
s3 <- p3_subset_check(D13, HV[1:2], HR)
s4 <- p3_subset_check(D13[0], HV, HR)
s5 <- p3_subset_check(D13, copy(HV)[2, w := 0][4, ticker := "E"][4, w := 0], HR)
if (identical(s1$status, "ok") && s1$n_checked == 2L && s1$n_violate == 0L && s2$n_violate == 1L && identical(s2$violate_dates, "2005-03-02") &&
    s3$n_missing == 1L && identical(s4$status, "unmeasured") && s5$n_violate == 0L)
  ok("13 같은 선정 집합 — ⊆ 통과 · 밖 종목 = 위반 · 집행일 결측 = 결측 · 신호일 없음 = 미측정 · 비중 0 은 보유 아님") else ng("13")

## 14) 후보 꼬리표
xg <- list(beta_matched = list(status = "ok", beats = TRUE), attribution = list(mechanism = TRUE), history_drop_tag = FALSE, history_drop_status = "ok")
xb <- modifyList(xg, list(beta_matched = list(status = "unmeasured", beats = NA)))
xe <- modifyList(xg, list(beta_matched = list(status = "ok", beats = FALSE), attribution = list(mechanism = FALSE), history_drop_status = "unmeasured"))
if (!length(p3_candidate_tags(list(xg, xg))) && identical(p3_candidate_tags(list(xg, xb)), "β 대조 미측정") &&
    identical(p3_candidate_tags(list(xg, xe)), c("노출(β) 방어", "기전(선택) 방어 미확인", "선택 교락 미측정")))
  ok("14 후보 꼬리표 — 깨끗하면 없음 · β 미측정 · 노출(β) 방어 · 기전 미확인 · 선택 교락 미측정") else ng("14", paste(p3_candidate_tags(list(xg, xe)), collapse = "|"))

## 15) 핀 재대조(precheck · 평가 시작 공용) — 임시 루트
tr <- file.path(tempdir(), "p3r03_pinroot"); unlink(tr, recursive = TRUE); dir.create(file.path(tr, "06_Registry"), recursive = TRUE)
writeLines("a", file.path(tr, "a.txt")); writeLines("b", file.path(tr, "b.txt")); writeLines("e", file.path(tr, "e.R"))
cat('{"entries":[{"catalog_id":"x:1","status":"active","resolver":{"kind":"k","notes":null,"n":2}}]}', file = file.path(tr, "06_Registry/weight_catalog.json"))
m5 <- function(f) unname(as.character(tools::md5sum(file.path(tr, f))))
wc0 <- fromJSON(file.path(tr, "06_Registry/weight_catalog.json"), simplifyVector = FALSE)$entries[[1]]
pre15 <- fromJSON(toJSON(list(cells = list(list(code = "C1", path = "a.txt", md5 = m5("a.txt"))),
                              operational_pins = list(files = list(list(path = "b.txt", md5 = m5("b.txt"))),
                                                      catalog_entries = list(list(catalog_id = "x:1", status = wc0$status, resolver = wc0$resolver)),
                                                      packages = list(jsonlite = as.character(utils::packageVersion("jsonlite"))), r_version = R.version.string),
                              evaluation = list(files = list(list(path = "e.R", md5 = m5("e.R"))))), auto_unbox = TRUE, null = "null", digits = NA), simplifyVector = FALSE)
p0 <- p3_pin_mismatches(pre15, tr)
writeLines("b2", file.path(tr, "b.txt")); p1 <- p3_pin_mismatches(pre15, tr); writeLines("b", file.path(tr, "b.txt"))
cat('{"entries":[{"catalog_id":"x:1","status":"active","resolver":{"kind":"k","notes":null,"n":3}}]}', file = file.path(tr, "06_Registry/weight_catalog.json"))
p2 <- p3_pin_mismatches(pre15, tr)
pre15b <- pre15; pre15b$operational_pins$packages$jsonlite <- "0.0.1"; p3 <- p3_pin_mismatches(pre15b, tr)
unlink(file.path(tr, "e.R")); p4 <- p3_pin_mismatches(pre15, tr)
if (!length(p0) && identical(p1, "운영 경로 md5: b.txt") && identical(p2, "카탈로그 엔트리: x:1") && "jsonlite 판" %in% p3 && "평가 경로 md5: e.R" %in% p4)
  ok("15 핀 재대조 — 일치 0 · 운영 파일 변경 · 카탈로그 resolver 변경 · 패키지 판 · 평가 파일 삭제를 각각 잡는다") else
  ng("15", paste(c(p0, "/", p1, "/", p2, "/", p3, "/", p4), collapse = " "))

## 16) 판정 1칸 조기 미시험 경로(계약 호출 전 — 평가 상태 · 전달률)
X16 <- list(res = file.path(tempdir(), "p3r03_res16"), fs = list(delivery_min = 0.9, majority_share = 0.5, crisis_improve_min = 0.03), tau = as.Date("2022-12-31"))
dir.create(X16$res, showWarnings = FALSE); writeLines(c(COV, LN$hrp, sub("2005-01-31", "2005-02-28", LN$hrp)), file.path(X16$res, "Z_HRP.log"))
o1 <- p3_eval_pair(X16, "E2", "HRP", list(code = "Z_HRP"), list(code = "Z_RX0"), list(status = "measure_failed"), list(status = "evaluated"))
o2 <- p3_eval_pair(X16, "E2", "HRP", list(code = "Z_HRP"), list(code = "Z_RX0"), list(status = "evaluated"), list(status = "evaluated"))
if (identical(o1$verdict, "untested") && grepl("평가 상태 measure_failed", o1$why) && identical(o1$tbl$tested, FALSE) &&
    identical(o2$verdict, "untested") && grepl("처치 전달률", o2$why) && isTRUE(all.equal(o2$delivery, 2 / 258)) && identical(o2$tbl$excluded, FALSE))
  ok("16 판정 1칸 — 평가 상태 실패 · 전달률 2/258 < 0.9 → 미시험(표 행 tested = FALSE)") else ng("16", paste(o1$why, "/", o2$why))

## 17) 판정 1칸 안전 호출(v3) — 이름 붙은 분기 밖 오류(계약 환경 없음 → 실효 시작 판독에서 오류)도 그 칸만 미시험 · 표 행 · 오류 문구
esc <- function(expr) tryCatch(expr, error = function(e) list(verdict = "error_escaped", why = conditionMessage(e), tbl = NULL))
o17 <- esc(p3_eval_pair_safe(X16, "E3", "HRP", list(code = "Z_HRP"), list(code = "Z_RX0"), list(status = "evaluated", artifacts = "x"), list(status = "evaluated", artifacts = "y"),
                             opts = list(log = file.path(X16$res, "Z_HRP.log"))))
X17 <- modifyList(X16, list(fs = modifyList(X16$fs, list(delivery_min = 0.001))))
o17b <- esc(p3_eval_pair_safe(X17, "E3", "HRP", list(code = "Z_HRP"), list(code = "Z_RX0"), list(status = "evaluated", artifacts = "x"), list(status = "evaluated", artifacts = "y")))
if (identical(o17$verdict, "untested") && identical(o17b$verdict, "untested") && grepl("^평가 오류:", o17b$why) && identical(o17b$tbl$tested, FALSE) &&
    identical(o17b$engine, "E3") && identical(o17b$cell, "Z_HRP") && identical(nrow(rbindlist(list(o17$tbl, o17b$tbl))), 2L))
  ok("17 안전 호출 — 전달률 통과 뒤 계약 오류도 그 칸 미시험(‘평가 오류: …’) · 표 행 tested = FALSE · 라운드 표 결합 가능") else ng("17", paste(o17b$why))

## 18) 이력 탈락 꼬리표(v3) — 판독 불가 = 미측정(통과로 접지 않음)
h1 <- p3_history_drop_eval(data.table(drop_share = c(0.2, 0.15)), 0.10); h2 <- p3_history_drop_eval(data.table(drop_share = c(0.02, 0.05)), 0.10)
h3 <- p3_history_drop_eval(data.table(drop_share = numeric(0)), 0.10); h4 <- p3_history_drop_eval(data.table(drop_share = c(NA_real_, NaN)), 0.10)
h5 <- p3_history_drop_eval(data.table(drop_share = 0.5), 0.10, has_holdings = FALSE)
if (identical(h1, list(status = "ok", tag = TRUE)) && identical(h2, list(status = "ok", tag = FALSE)) && identical(h3$status, "unmeasured") &&
    identical(h4$status, "unmeasured") && identical(h5$status, "unmeasured") && !h3$tag && !h4$tag)
  ok("18 이력 탈락 — 몫 평균 > 0.10 꼬리표 · 이하 없음 · 위기 집행 행 없음 · 몫 비유한 · 보유 판독 실패 = 미측정") else ng("18")

## 19) 핀 재대조(v3) — 행동 카드 설정 사본 md5
writeLines("cfg", file.path(tr, "bc.json")); unlink(file.path(tr, "e.R")); writeLines("e", file.path(tr, "e.R"))
pre19 <- pre15; pre19$behavior_card_cfg <- list(path = "bc.json", md5 = m5("bc.json"))
cat('{"entries":[{"catalog_id":"x:1","status":"active","resolver":{"kind":"k","notes":null,"n":2}}]}', file = file.path(tr, "06_Registry/weight_catalog.json"))
q0 <- p3_pin_mismatches(pre19, tr); writeLines("cfg2", file.path(tr, "bc.json")); q1 <- p3_pin_mismatches(pre19, tr)
if (!length(q0) && identical(q1, "행동 카드 설정 사본 md5")) ok("19 핀 재대조 — 행동 카드 설정 사본이 바뀌면 잡는다") else ng("19", paste(c(q0, "/", q1), collapse = " "))

cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
cat(sprintf('{"test":"p3r03_evaluate_fixture","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL > 0L) 1L else 0L)
