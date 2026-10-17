## P2R03 evaluate.R 순수 도우미 픽스처 검사(합성 · 결과 무접촉 · 사전등록 고정 대상) — 본 실행 블록은 sys.nframe() > 0 이라 안 돈다
## 실행: Rscript evaluate_fixture.R
##   1 공통 창 사본 · 2 위기 짝 과반 · 3 깊은 위기 · 4 빠른 급락(문턱 경계 · 21거래일 창 · 날짜 불일치) · 5 강세 구간별(음수 기준 일반화 · 짝 < 2) ·
##   6 β 비대칭(같음 = 거짓) · 7 오버레이 집행 줄(신 · 구 형식 · lag 줄 · 층별 줄 비혼동) · 8 같은 선정 집합(위반 · 결측 · τ 절단) · 9 알파 비열등 ·
##   10 집중 · β 짝 사본 · 11 사이클 짝(실제 보는 창 연대기) · 12 회복 꼬리표 · 13 lag-1 꼬리표 · 14 라운드 판정 · 15 선택(동률) · 16 지문 비교(이름 붙은 벡터) ·
##   17 핀 재대조(오버레이 arm) · 18 판정 1칸 조기 미시험(상태 · 집행 증거) · 19 보는 창 파일에서 시험 창 제외 · 21 β 비 변화량(정적 축소 불변) ·
##   22 HM 타이밍 회귀 · 23 현금 타이밍 · 24 lag-1 조건 (b) · 25 빠른 급락 기록 판 · 장치 7종 · 20 뮤테이션(소스 텍스트 치환 8종)
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat("  OK  ", m, "\n") }
ng <- function(m, d = "") { FAIL <<- FAIL + 1L; cat("  FAIL", m, d, "\n") }
EVF <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/04_Research/programs/P2_DEFENSE/P2R03_conditional_overlay/evaluate.R"
source("C:/Users/99922/OneDrive/Quant_Module_Moltbot/04_Research/programs/_lib/round_kit.R")
source(EVF)
if (exists("EVS")) ng("본 실행 블록이 source 에서 돌았다") else ok("source 시 본 실행 블록 미실행(sys.nframe 가드)")
J <- function(dt) fromJSON(toJSON(dt, na = "null"), simplifyVector = FALSE)
TMP <- gsub("\\\\", "/", tempdir())

## 1) 공통 창 사본
src <- file.path(TMP, "p2r03_src"); out <- file.path(TMP, "p2r03_out"); unlink(c(src, out), recursive = TRUE); dir.create(src)
d <- seq(as.Date("2005-01-03"), by = "day", length.out = 40); r <- c(rep(0.01, 10), rep(-0.02, 10), rep(0.005, 20)); nav <- cumprod(1 + r)
fwrite(data.table(date = d, ret_net = r), file.path(src, "03_period_returns.csv"))
fwrite(data.table(date = d, benchmark_ret = r / 2, benchmark_nav = cumprod(1 + r / 2)), file.path(src, "05_benchmark_returns.csv"))
fwrite(data.table(date = d, nav_gross = nav * 1.001, nav_net = nav, cum_cost = nav * 0.001, drawdown_net = nav / cummax(nav) - 1), file.path(src, "02_nav.csv"))
fwrite(data.table(date = rep(d[c(1, 15, 30)], each = 2), ticker = rep(c("000660", "005930"), 3), target_weight = 0.5), file.path(src, "04_holdings.csv"))
writeLines('{"y":2}', file.path(src, "authoritative_remeasure.json"))
st <- d[20]; p2_trim_artifacts(src, out, st)
nv2 <- fread(file.path(out, "02_nav.csv")); H2 <- fread(file.path(out, "04_holdings.csv"), colClasses = list(character = "ticker"))
if (min(as.Date(nv2$date)) == st && abs(nv2$nav_net[1] - 1) < 1e-12 && identical(sort(unique(as.character(as.Date(H2$date)))), as.character(d[c(15, 30)])) &&
    identical(H2$ticker[1], "000660") && file.exists(file.path(out, "authoritative_remeasure.json"))) ok("1 공통 창 — NAV 재기준 · 보유 = 시작에 들던 리밸부터 · 선행 0 보존 · 비 CSV 복사") else ng("1")

## 2) 위기 짝 과반(dd_capture · tol)
CR3 <- data.table(peak_date = c("2008-05-16", "2011-05-02", "2020-01-22"), trough_date = c("2008-10-24", "2011-09-26", "2020-03-19"))
crm <- J(copy(CR3)[, `:=`(dd_capture = c(0.60, 0.95, 0.70), bm_dd = c(-0.49, -0.27, -0.35))])
crr <- J(copy(CR3)[, `:=`(dd_capture = c(0.80, 0.90, 0.75), bm_dd = c(-0.49, -0.27, -0.35))])
mj <- p2_crisis_majority(crm, crr, 0.03)
if (mj$n_pair == 3L && mj$n_better == 2L && abs(mj$share - 2/3) < 1e-12 && mj$unpaired == 0L) ok("2a 짝 3 · 개선 2(0.20 · 0.05 > 0.03) · 비율 2/3") else ng("2a", paste(mj$n_pair, mj$n_better))
if (p2_crisis_majority(crm, crr, 0.06)$n_better == 1L && is.na(p2_crisis_majority(list(), crr, 0.03)$share) && p2_crisis_majority(crm[1:2], crr, 0.03)$unpaired == 1L)
  ok("2b 문턱 0.06 이면 0.05 개선은 개선 아님 · 위기 없음 NA · 한 칸에만 있는 위기 = 짝 없음 1") else ng("2b")

## 3) 깊은 위기 = 벤치 낙폭 크기 ≥ 중앙값
dk <- p2_deep_crisis_keys(crm, crr)
if (identical(sort(dk), sort(c("2008-05-16 2008-10-24", "2020-01-22 2020-03-19")))) ok("3 깊은 위기 = 2008 · 2020(중앙값 0.35 이상)") else ng("3", paste(dk))

## 4) 빠른 급락 — 21거래일 창 · 문턱 −20% 경계 · 날짜 불일치 = 분류 못 함
bd <- seq(as.Date("2010-01-04"), by = "day", length.out = 300); rr <- rep(0, 300)
rr[11:20] <- (0.75)^(1/10) - 1                                                  # 위기 A: 10일에 −25%(빠름)
rr[101:200] <- (0.70)^(1/100) - 1                                               # 위기 B: 100일에 −30%(21일 창 최대 ≈ −7.2% · 느림)
rr[231:252] <- (0.80)^(1/22) - 1                                                # 위기 C: 22일에 −20% — 21일 창으로는 −19.x%(느림)
rr[261:281] <- (0.80)^(1/21) - 1                                                # 위기 D: 21일에 정확히 −20%(경계 = 빠름)
BR <- data.table(date = bd, benchmark_ret = rr)
CRF <- J(data.table(peak_date = format(bd[c(10, 100, 230, 260, 1)]), trough_date = format(c(bd[c(20, 200, 252, 281)], as.Date("2009-12-31")))))
fk <- p2_fast_crash_keys(BR, CRF, 21L, -0.20)
TBF <- fk$table
if (identical(fk$keys, c(paste(bd[10], bd[20]), paste(bd[260], bd[281]))) && isTRUE(abs(TBF$max_drop[1] + 0.25) < 1e-9) && identical(TBF$fast[2], FALSE) &&
    identical(TBF$fast[3], FALSE) && identical(fk$unclassified, paste(bd[1], "2009-12-31")))
  ok(sprintf("4 빠름 = A(10일 −25%%) · D(21일 −20%% 경계) · 느림 = B(창 최대 %.1f%%) · C(22일 −20%% → 21일 창 %.2f%%) · 날짜 불일치 = 분류 못 함", 100 * TBF$max_drop[2], 100 * TBF$max_drop[3])) else
  ng("4", paste(fk$keys, collapse = "|"))

## 5) 강세 구간별 — 양수 기준 80% · 음수 기준 일반화(기준 − 0.2|기준|) · 짝 < 2 = NA
BL <- data.table(start_ym = c("2009-03", "2011-10", "2013-07", "2016-02"), end_ym = c("2011-04", "2013-02", "2014-07", "2017-10"))
bm5 <- J(copy(BL)[, up_capture := c(0.85, 0.70, -0.23, -0.25)]); br5 <- J(copy(BL)[, up_capture := c(1.00, 1.00, -0.20, -0.20)])
bs <- p2_bull_segments(bm5, br5, 0.8, 2L)
if (bs$n_pair == 4L && identical(bs$per_phase[order(k)]$ok, c(TRUE, FALSE, TRUE, FALSE)) && abs(bs$share - 0.5) < 1e-12)
  ok("5a 0.85 ≥ 0.80 ✓ · 0.70 < 0.80 ✗ · 음수 기준 −0.20 → 문턱 −0.24: −0.23 ✓ · −0.25 ✗ → 비율 0.5(과반 아님)") else ng("5a", paste(bs$per_phase$ok))
if (is.na(p2_bull_segments(bm5[1], br5[1], 0.8, 2L)$share) && is.na(p2_bull_segments(list(), br5, 0.8, 2L)$share)) ok("5b 짝 1 < 2 · 국면 없음 → NA(미시험)") else ng("5b")

## 6) β 비대칭
if (isTRUE(p2_beta_asym(0.8, 1.0)) && identical(p2_beta_asym(1.1, 0.9), FALSE) && identical(p2_beta_asym(1.0, 1.0), FALSE) && is.na(p2_beta_asym(NA, 1)))
  ok("6 하락장 β < 상승장 β 만 참 · 같음 = 거짓 · NA = NA") else ng("6")

## 7) 오버레이 집행 줄
L_NEW <- c("[rf_cell_engine] overlay 층별 | a(자기) n_min 24 평균노출 0.9 최소 0.1 횡단면sd 0.0",
           "[rf_cell_engine] overlay turbulence | 축 스칼라 | 평균노출 0.912 · 최소 0.000 · 완전현금 14/270개월 · 현금 집행(표현 하한) 14신호일")
L_OLD <- "[rf_cell_engine] overlay vol_scale | 축 스칼라 | 평균노출 0.937 · 최소 0.208 · 완전현금 0/322개월"
L_VEC <- c("[rf_cell_engine] overlay_shift=1 적용 — 노출 경로 1개월 지연(앞선 달 없는 1개월은 1 · lag 스트레스판)",
           "[rf_cell_engine] overlay dbeta_tilt | 축 종목별 | 평균노출 0.870 · 최소 0.500 · 완전현금 0/270개월 · 횡단면 sd 최대 0.231 · 현금 집행(표현 하한) 0신호일")
o1 <- p2_parse_overlay_log(L_NEW); o2 <- p2_parse_overlay_log(L_OLD); o3 <- p2_parse_overlay_log(L_VEC); o4 <- p2_parse_overlay_log(L_NEW[1])
if (isTRUE(o1$found) && identical(o1$kind, "turbulence") && identical(o1$axis, "스칼라") && identical(o1$full_cash_months, 14) && identical(o1$cash_exec, 14) && !isTRUE(o1$shift1) &&
    isTRUE(o2$found) && is.na(o2$cash_exec) && identical(o2$expo_min, 0.208) &&
    isTRUE(o3$shift1) && identical(o3$axis, "종목별") && identical(o3$xs_sd_max, 0.231) && identical(o3$cash_exec, 0) && !isTRUE(o4$found))
  ok("7 신 형식(현금 집행 수) · 구 형식(NA) · 종목별 · lag 줄 · '층별' 요약 줄은 집행 줄로 안 읽음") else ng("7")

## 8) 같은 선정 집합(오버레이판)
mkH <- function(x) { x <- as.data.table(x); x[, date := as.Date(date)]; x[] }
Hr <- mkH(data.frame(date = rep(c("2010-01-29", "2010-02-26", "2023-03-31"), each = 3), ticker = rep(c("A", "B", "C"), 3), w = 1/3))
Hv <- mkH(data.frame(date = rep(c("2010-01-29", "2010-02-26"), each = 2), ticker = c("A", "B", "A", "C"), w = 0.2))
s1 <- p2_subset_check(Hv, Hr, as.Date("2022-12-31"))
Hv2 <- rbind(Hv, mkH(data.frame(date = "2010-02-26", ticker = "Z", w = 0.1))); s2 <- p2_subset_check(Hv2, Hr, as.Date("2022-12-31"))
s3 <- p2_subset_check(Hv[date == as.Date("2010-01-29")], Hr, as.Date("2022-12-31"))
if (identical(s1$n_checked, 2L) && identical(s1$n_violate, 0L) && identical(s1$n_missing, 0L) && identical(s2$n_violate, 1L) && identical(s3$n_missing, 1L))
  ok("8 보는 창 RX0 보유일 2(τ 뒤 제외) · 부분 집합 위반 0 · RX0 밖 종목 = 위반 1 · 변형 보유 없는 날 = 결측 1") else ng("8", paste(s1$n_checked, s2$n_violate, s3$n_missing))

## 9) 알파 비열등
a1 <- p2_alpha_ok(list(t = -1.5, d_alpha = -0.01), -2, 0.10, 0.2); a2 <- p2_alpha_ok(list(t = -1.5, d_alpha = -0.03), -2, 0.10, 0.2)
a3 <- p2_alpha_ok(list(t = -2.5, d_alpha = 0), -2, 0.10, 0.2); a4 <- p2_alpha_ok(list(t = 0.5, d_alpha = -0.001), -2, -0.05, 0.2); a5 <- p2_alpha_ok(list(t = NA, d_alpha = 0), -2, 0.1, 0.2)
if (isTRUE(a1) && identical(a2, FALSE) && identical(a3, FALSE) && identical(a4, FALSE) && is.na(a5)) ok("9 여유 = 0.2 × 엔진 α · t 문턱 · 엔진 α ≤ 0 이면 감소 허용 0 · NA = NA") else ng("9")

## 10) 집중 · β 짝 사본
tl <- J(data.table(peak_date = c("2008-05-16", "2008-05-16", "2020-01-22", "2011-05-02"), Ticker = c("A", "B", "C", "D"), contrib = c(-0.18, -0.02, -0.04, -0.12)))
t1 <- p2_top_loss(tl, c("2008-05-16", "2020-01-22"), -0.10)
if (identical(p2_conc_status(t1), "breach") && identical(t1$n_breach, 1L) && identical(p2_conc_status(p2_top_loss(tl, c("2008-05-16", "2008-11-05"), -0.10)), "breach") &&
    identical(p2_conc_status(p2_top_loss(J(data.table(peak_date = "2020-01-22", Ticker = "C", contrib = -0.04)), c("2008-05-16", "2020-01-22"), -0.10)), "unmeasured") &&
    identical(p2_conc_status(p2_top_loss(list(), "2008-05-16", -0.10)), "unmeasured")) ok("10a 집중 — 깊은 위기 −18% = breach · 깊지 않은 위기(2011 −12%)는 안 셈 · 누락 · 표 없음 = 미측정") else ng("10a")
bsrc <- file.path(TMP, "p2r03_bsrc"); bout <- file.path(TMP, "p2r03_bout"); unlink(c(bsrc, bout), recursive = TRUE); dir.create(bsrc)
for (f in c("02_nav.csv", "03_period_returns.csv", "04_holdings.csv", "05_benchmark_returns.csv")) file.copy(file.path(src, f), bsrc)
p2_beta_scaled_copy(bsrc, bout, 0.8)
pb <- fread(file.path(bout, "03_period_returns.csv")); hb <- fread(file.path(bout, "04_holdings.csv")); bb <- fread(file.path(bout, "05_benchmark_returns.csv"))
if (isTRUE(all.equal(pb$ret_net, 0.8 * r)) && isTRUE(all.equal(sum(hb[date == min(date)]$target_weight), 0.8)) && isTRUE(all.equal(bb$benchmark_ret, r / 2)) &&
    inherits(try(p2_beta_scaled_copy(bsrc, bout, 1.2), silent = TRUE), "try-error")) ok("10b β 짝 사본 — 수익 · 보유 k 배 · 벤치 그대로 · k > 1 거부") else ng("10b")

## 11) 사이클 짝 — 실제 보는 창 벤치 연대기(P3R03 픽스처 11 과 같은 날짜 · 성과는 합성)
CRISES <- data.table(peak_date = c("2007-10-11", "2008-05-16", "2008-11-05", "2011-05-02", "2017-11-03", "2020-01-22", "2021-06-25"),
                     trough_date = c("2008-03-17", "2008-10-24", "2008-11-20", "2011-09-26", "2019-08-07", "2020-03-19", "2022-09-30"))
BULLS <- data.table(start_ym = c("2009-03", "2011-10", "2013-07", "2016-02", "2020-04"), end_ym = c("2011-04", "2013-02", "2014-07", "2017-10", "2021-06"))
bu_m <- J(copy(BULLS)[, st_cum := c(0.80, 0.30, 0.20, 0.40, 0.90)]); bu_r <- J(copy(BULLS)[, st_cum := c(0.90, 0.35, 0.25, 0.45, 1.00)])
cr_m <- J(copy(CRISES)[, st_cum := c(-0.20, -0.40, -0.05, -0.12, -0.15, -0.25, -0.20)]); cr_r <- J(copy(CRISES)[, st_cum := c(-0.25, -0.45, -0.06, -0.20, -0.10, -0.28, -0.30)])
cy <- p2_cycle_compound(bu_m, cr_m, bu_r, cr_r)
if (cy$n_pair == 3L && cy$n_ge == 2L && abs(cy$share - 2/3) < 1e-12 && length(cy$unpaired_crises) == 4L && cy$pair_mismatch == 0L &&
    is.na(p2_cycle_compound(J(BULLS[1][, st_cum := 0.8]), J(CRISES[1:4][, st_cum := -0.1]), J(BULLS[1][, st_cum := 0.9]), J(CRISES[1:4][, st_cum := -0.2]))$share))
  ok("11 사이클 짝 3(2011 · 2017-11 · 2021-06) · 칸 ≥ 기준 2/3 · 짝 없는 위기 4 · 짝 1 → NA") else ng("11", paste(cy$n_pair, cy$n_ge))

## 12) 회복 꼬리표
rc_m <- J(copy(CR3)[, `:=`(st_recovery_obs = c(400, 100, 300), st_recovery_censored = c(FALSE, FALSE, TRUE))])
rc_r <- J(copy(CR3)[, `:=`(st_recovery_obs = c(300, 120, 200), st_recovery_censored = c(FALSE, FALSE, FALSE))])
rt <- p2_recovery_tag(rc_m, rc_r, 0.5); rt0 <- p2_recovery_tag(J(CR3), rc_r, 0.5)
rt1 <- p2_recovery_tag(J(copy(CR3)[, st_recovery_obs := c(1, 2, 3)]), J(copy(CR3)[, st_recovery_obs := c(1, 2, 3)]), 0.5)
if (identical(rt$n_longer, 2L) && isTRUE(rt$tag) && identical(rt0$status, "unmeasured") && identical(rt1$status, "ok") && identical(rt1$tag, FALSE))
  ok("12 회복 — 더 긴 위기 2/3 > 0.5 → '회복 지연' · 관측 열 없음 = 미측정 · 미회복 열 없어도 동작") else ng("12")

## 13) lag-1 꼬리표
D34 <- list(tested = TRUE, rules = list(beta_deep = list(ok = TRUE), fast = list(ok = TRUE)))
L34 <- D34; L3 <- list(tested = TRUE, rules = list(beta_deep = list(ok = TRUE), fast = list(ok = FALSE))); D0 <- list(tested = TRUE, rules = list(beta_deep = list(ok = FALSE), fast = list(ok = FALSE)))
if (identical(p2_lag_tag(D34, L34), "lag-1 유지") && identical(p2_lag_tag(D34, L3), "지연 민감(lag-1 에서 ④ 붕괴)") &&
    identical(p2_lag_tag(list(tested = FALSE), L34), "lag-1 미시험") && grepl("비교 대상 없음", p2_lag_tag(D0, L34)))
  ok("13 lag-1 — 유지 · 지연 민감(④) · 미시험 · 장치가 ③④ 못 넘으면 비교 대상 없음") else ng("13")

## 14) 라운드 판정 — 장치 칸만 · 판정 칸 수 표기
T1 <- data.table(engine = rep(c("E2", "E3"), each = 2), device = rep(c("D1", "D5"), 2), lag = FALSE, tested = TRUE, pass = c(TRUE, FALSE, TRUE, TRUE), excluded = FALSE)
v1 <- p2_round_verdict(T1)
T6 <- copy(T1)[, pass := TRUE][, excluded := c(TRUE, FALSE, FALSE, FALSE)]; v6 <- p2_round_verdict(T6)
T3 <- copy(T1)[, pass := FALSE][1:2, tested := FALSE]
if (identical(v1$verdict, "supported") && identical(v1$both, "D1") && identical(v1$one, "D5") && identical(v1$label, "supported(판정 4/4)") &&
    identical(v6$excluded, "D1") && identical(v6$both, "D5") && identical(p2_round_verdict(T3)$label, "falsified(판정 2/4)") &&
    identical(p2_round_verdict(copy(T1)[, tested := FALSE])$verdict, "untested"))
  ok("14 supported(판정 4/4) · 집중 제외 = 검증 아님 · falsified(판정 2/4) · untested") else ng("14", v1$label)

## 15) 선택 — S 증분(두 엔진 평균) · 동률이면 ③ · ④ 비율 합
mk <- function(dv, s, s0, b3, b4) list(device = dv, non_inferiority = list(S = s, S_rx0 = s0), rules = list(beta_deep = list(share = b3), fast = list(share = b4)))
sel <- p2_select(list(D5 = list(mk("D5", 0.8, 0.5, 0.6, 0.6), mk("D5", 0.45, 0.5, 0.6, 0.6)), D1 = list(mk("D1", 0.7, 0.5, 0.6, 0.6), mk("D1", 0.6, 0.5, 0.6, 0.6))))
selt <- p2_select(list(D1 = list(mk("D1", 0.7, 0.5, 0.6, 0.6)), D2 = list(mk("D2", 0.7, 0.5, 0.8, 0.8))))
if (identical(sel[[1]]$device, "D1") && isTRUE(abs(sel[[1]]$dS - 0.15) < 1e-12) && identical(selt[[1]]$device, "D2") && identical(selt[[1]]$tie_break, "r34") && !length(p2_select(list())))
  ok("15 선택 — 평균 S 증분 D1 0.15 > D5 0.125(입력 순서 무관) · 동률이면 ③ · ④ 비율 합(D2) · 검증 0 = 선택 없음") else ng("15", paste(sel[[1]]$device, sel[[1]]$dS, selt[[1]]$device))

## 16) 지문 비교 — 이름 붙은 벡터(P3R03 오표시 재현)
fa <- c(HRP1 = "x|y"); fb <- "x|y"
if (!identical(fa, fb) && isTRUE(p2_fp_same(fa, fb)) && !isTRUE(p2_fp_same("x|y", "x|z"))) ok("16 identical(이름 붙은, 이름 없는) = 거짓(P3R03 결함) · p2_fp_same = 참 · 다르면 거짓") else ng("16")

## 17) 핀 재대조 — 오버레이 카탈로그 arm 엔트리
PRT <- file.path(TMP, "p2r03_pinroot"); unlink(PRT, recursive = TRUE); dir.create(file.path(PRT, "06_Registry"), recursive = TRUE)
writeLines(toJSON(list(entries = list(list(catalog_id = "lean:entropy", status = "active", resolver = list(f = "x")))), auto_unbox = TRUE), file.path(PRT, "06_Registry/weight_catalog.json"))
writeLines(toJSON(list(arms = list(list(id = "ts_mom_sign", kind = "ts_mom_gate", status = "active"))), auto_unbox = TRUE), file.path(PRT, "06_Registry/overlay_catalog.json"))
writeLines("a", file.path(PRT, "f.txt"))
pre_ok <- list(cells = list(), operational_pins = list(files = list(list(path = "f.txt", md5 = unname(tools::md5sum(file.path(PRT, "f.txt"))))),
               catalog_entries = list(list(catalog_id = "lean:entropy", status = "active", resolver = list(f = "x"))),
               overlay_arms = list(list(id = "ts_mom_sign", entry = list(id = "ts_mom_sign", kind = "ts_mom_gate", status = "active"))),
               packages = list(), r_version = R.version.string))
pre_bad <- pre_ok; pre_bad$operational_pins$overlay_arms[[1]]$entry$status <- "retired"
if (!length(p2_pin_mismatches(pre_ok, PRT)) && identical(p2_pin_mismatches(pre_bad, PRT), "오버레이 카탈로그 arm: ts_mom_sign")) ok("17 핀 — 일치 = 0 · arm 엔트리 변경 = 불일치 1") else ng("17", paste(p2_pin_mismatches(pre_bad, PRT)))

## 18) 판정 1칸 조기 미시험 — 평가 상태 · 오버레이 집행 증거(장치 칸에 lag 줄 · lag 칸에 lag 줄 없음 · 집행 줄 없음)
RS <- file.path(TMP, "p2r03_res"); unlink(RS, recursive = TRUE); dir.create(RS)
writeLines(L_NEW, file.path(RS, "C_D.log")); writeLines(L_VEC, file.path(RS, "C_L.log")); writeLines("nothing", file.path(RS, "C_X.log"))
X0 <- list(root = TMP, res = RS, out = RS, env = new.env(), fs = list(majority_share = 0.5, crisis_improve_min = 0.03), tau = as.Date("2022-12-31"), ea = new.env())
ev <- list(status = "evaluated"); cr0 <- list(code = "R0")
u1 <- p2_eval_pair_safe(X0, "E2", "D3", list(code = "C_D"), cr0, list(status = "measure_failed"), ev)
u2 <- p2_eval_pair_safe(X0, "E2", "D3", list(code = "C_L"), cr0, ev, ev)                       # 장치 칸인데 lag 줄 있음
u3 <- p2_eval_pair_safe(X0, "E2", "D3", list(code = "C_D", lag = TRUE), cr0, ev, ev)           # lag 칸인데 lag 줄 없음
u4 <- p2_eval_pair_safe(X0, "E2", "D3", list(code = "C_X"), cr0, ev, ev)                       # 집행 줄 없음
if (!isTRUE(u1$tested) && grepl("평가 상태", u1$why) && !isTRUE(u2$tested) && grepl("집행 증거", u2$why) && !isTRUE(u3$tested) && grepl("기대 TRUE", u3$why) &&
    !isTRUE(u4$tested) && grepl("집행 줄 FALSE", u4$why) && identical(u4$tbl$tested, FALSE)) ok("18 조기 미시험 — 상태 · 장치 칸 lag 줄 · lag 칸 줄 없음 · 집행 줄 없음 → 미시험(반증 아님)") else
  ng("18", paste(u1$why, u2$why, u3$why, u4$why, sep = " / "))

## 19) 보는 창 파일에서 시험 창 제외
vx <- p2_visible_only(list(alpha_test_window = list(t = 1), tbl = data.table(a = 1), rules = list(x = 1)))
if (is.null(vx$alpha_test_window) && is.null(vx$tbl) && identical(vx$rules$x, 1)) ok("19 p2_visible_only — 시험 창 증분 알파 · 표 행 제거 · 판정 유지") else ng("19")

## 21) β 비 변화량(⑤ 장치 검증 · 철학 P1 C-044) — 정적 축소(k 배)는 비를 바꾸지 않는다 · 비가 낮아질 때만 참 · 상승 β ≤ 0 = NA
d0 <- p2_beta_ratio_delta(1.31, 0.99, 1.31, 0.99); dk <- p2_beta_ratio_delta(0.7 * 1.31, 0.7 * 0.99, 1.31, 0.99); dg <- p2_beta_ratio_delta(0.9, 0.95, 1.31, 0.99)
if (identical(d0$ok, FALSE) && identical(dk$ok, FALSE) && isTRUE(abs(dk$delta) < 1e-12) && isTRUE(dg$ok) && is.na(p2_beta_ratio_delta(1, 0, 1, 1)$ok) && is.na(p2_beta_ratio_delta(NA, 1, 1, 1)$ok))
  ok("21 β 비 Δ — 같은 비 = 거짓 · 정적 0.7 배 축소 = Δ 0(거짓) · 비 1.32 → 0.95 = 참 · 상승 β 0 · NA = NA") else ng("21")
if (identical(p2_beta_asym(0.7 * 1.31, 0.7 * 0.99), FALSE)) ok("21b 수준 판정(방어 주장)은 역비대칭 엔진의 정적 축소를 거짓으로 둔다(칸 꼬리표)") else ng("21b")

## 22) HM 타이밍 회귀 — 합성 차이 = 0.4 × max(0, −벤치) + 잡음 → γ ≈ 0.4 · t > 2 · 관측 < 24 = 미측정
source("C:/Users/99922/OneDrive/Quant_Module_Moltbot/02_Infrastructure/contracts/beta_controlled_alpha.R")
set.seed(20261017L); kk <- rnorm(120, 0.005, 0.06); dd <- 0.4 * pmax(0, -kk) + rnorm(120, 0, 0.003)
hm <- p2_hm_fit(dd, kk); hm0 <- p2_hm_fit(dd[1:20], kk[1:20])
if (identical(hm$status, "ok") && isTRUE(abs(hm$gamma - 0.4) < 0.05) && isTRUE(hm$t_gamma > 2) && identical(hm0$status, "n<24")) ok(sprintf("22 HM γ %.3f(참값 0.4) · t %.1f · n<24 = 미측정", hm$gamma, hm$t_gamma)) else ng("22", paste(hm$status, hm$gamma))

## 23) 현금 타이밍 — 위기 달 3 중 2 현금 · 현금 달 3 중 2 위기 · 반등 3개월 평균 노출
EXM <- data.table(ym = format(seq(as.Date("2008-01-01"), by = "month", length.out = 12), "%Y-%m"), e = c(1, 1, 1, 1, 0.2, 0.3, 1, 0.4, 1, 1, 1, 1))
CRT <- J(data.table(peak_date = "2008-05-16", trough_date = "2008-07-24"))
ctm <- p2_cash_timing(EXM, CRT, 0.5)
if (identical(ctm$status, "ok") && isTRUE(abs(ctm$recall - 2/3) < 1e-12) && isTRUE(abs(ctm$precision - 2/3) < 1e-12) && isTRUE(abs(ctm$rebound_3m - (0.4 + 1 + 1) / 3) < 1e-12) &&
    identical(p2_cash_timing(data.table(), CRT)$status, "unmeasured")) ok("23 현금 정밀도 2/3 · 재현율 2/3 · 반등 3개월 노출 0.8 · 빈 표 = 미측정") else ng("23", paste(ctm$precision, ctm$recall, ctm$rebound_3m))

## 24) lag-1 조건 (b) — 장치 느린 약세 과반 ∧ lag-1 미달 = 보류 · lag-1 NA(짝 < 2) 는 보류 아님 · 꼬리표에 보류 문구
DS <- list(tested = TRUE, rules = list(beta_deep = list(ok = TRUE), fast = list(ok = TRUE), slow = list(ok = TRUE)))
LS0 <- list(tested = TRUE, rules = list(beta_deep = list(ok = TRUE), fast = list(ok = TRUE), slow = list(ok = FALSE)))
LSN <- list(tested = TRUE, rules = list(beta_deep = list(ok = TRUE), fast = list(ok = TRUE), slow = list(ok = NA)))
if (isTRUE(p2_lag_hold(DS, LS0)) && !isTRUE(p2_lag_hold(DS, LSN)) && !isTRUE(p2_lag_hold(DS, DS)) && grepl("선택 보류", p2_lag_tag(DS, LS0)) && identical(p2_lag_tag(DS, DS), "lag-1 유지"))
  ok("24 lag-1 (b) — 느린 약세 붕괴 = 보류 · lag-1 NA 는 보류 아님 · 유지 = 'lag-1 유지'") else ng("24")

## 25) 빠른 급락 기록 판 — 위기 안 월말 0 인 급락 목록 · 빠른 구간 시작/끝
bm25 <- seq(as.Date("2011-01-03"), as.Date("2011-03-31"), by = "day"); r25 <- rep(0, length(bm25)); i1 <- which(bm25 == as.Date("2011-02-03")); i2 <- which(bm25 == as.Date("2011-02-17"))
r25[(i1 + 1):i2] <- (0.75)^(1 / (i2 - i1)) - 1
fk25 <- p2_fast_crash_keys(data.table(date = bm25, benchmark_ret = r25), J(data.table(peak_date = "2011-02-03", trough_date = "2011-02-17")), 21L, -0.20)
if (identical(fk25$keys, "2011-02-03 2011-02-17") && identical(fk25$no_month_end, "2011-02-03 2011-02-17") && identical(fk25$table$month_ends_inside, 0L) &&
    identical(format(fk25$table$seg_start), "2011-02-03") && identical(format(fk25$table$seg_end), "2011-02-17")) ok("25 월 안 급락(2/3~2/17) — 빠름 · 위기 안 월말 0 → 기록 판 제외 목록 · 구간 시작/끝") else ng("25", paste(fk25$table$month_ends_inside))
if (identical(names(P2R03_DEVICES), paste0("D", 1:7)) && identical(P2R03_DEVICES$D7$kind, "dd_recovery")) ok("25b 장치 7종(D7 = dd_recovery 재진입 · 철학 P1 C-045)") else ng("25b")

## 20) 뮤테이션 — 소스 텍스트 치환(치환 성사 단정 · 사본 단독 적재) 6종이 각각 위 검사 하나를 깨는가
SRC <- readLines(EVF, warn = FALSE, encoding = "UTF-8")
mutant <- function(from, to) {
  hit <- sum(grepl(from, SRC, fixed = TRUE)); if (hit != 1L) return(list(err = sprintf("치환 대상 %d줄(1줄이어야 함): %s", hit, from)))
  p <- file.path(TMP, sprintf("p2r03_mut_%d.R", sample.int(1e6, 1))); writeLines(sub(from, to, SRC, fixed = TRUE), p, useBytes = TRUE)
  e <- new.env(); r0 <- tryCatch({ sys.source(p, envir = e, keep.source = FALSE); NULL }, error = function(z) conditionMessage(z))
  if (!is.null(r0)) return(list(err = paste("사본 적재 실패:", r0))); if (exists("EVS", envir = e, inherits = FALSE)) return(list(err = "사본이 본 실행 블록을 돌렸다"))
  list(env = e)
}
MU <- list(
  list(nm = "빠름 창 한 칸 넓힘", from = "e <- min(i1, a + as.integer(win))", to = "e <- min(i1, a + as.integer(win) + 1L)",
       kill = function(e) !identical(e$p2_fast_crash_keys(BR, CRF, 21L, -0.20)$keys, fk$keys)),
  list(nm = "음수 기준 일반화 제거", from = "thr := r - (1 - ratio) * abs(r)", to = "thr := ratio * r",
       kill = function(e) !identical(e$p2_bull_segments(bm5, br5, 0.8, 2L)$per_phase[order(k)]$ok, c(TRUE, FALSE, TRUE, FALSE))),
  list(nm = "β 비대칭 < → <=", from = "  bd < bu", to = "  bd <= bu",
       kill = function(e) isTRUE(e$p2_beta_asym(1.0, 1.0))),
  list(nm = "지문 비교 unname 제거", from = "identical(unname(as.character(a)), unname(as.character(b)))", to = "identical(a, b)",
       kill = function(e) !isTRUE(e$p2_fp_same(fa, fb))),
  list(nm = "결측 날짜를 세지 않음", from = "if (!length(tv)) { miss <- c(miss, format(d)); next }", to = "if (!length(tv)) next",
       kill = function(e) !identical(e$p2_subset_check(Hv[date == as.Date("2010-01-29")], Hr, as.Date("2022-12-31"))$n_missing, 1L)),
  list(nm = "lag 꼬리표 ④ 무시", from = "lost <- c(if (d3 && !l3) \"③\", if (d4 && !l4) \"④\")", to = "lost <- c(if (d3 && !l3) \"③\")",
       kill = function(e) identical(e$p2_lag_tag(D34, L3), "lag-1 유지")),
  list(nm = "β 비 Δ → 차이(정적 축소에 속는다)", from = "rv <- x[1] / x[2]; rr <- x[3] / x[4]", to = "rv <- x[1] - x[2]; rr <- x[3] - x[4]",
       kill = function(e) isTRUE(e$p2_beta_ratio_delta(0.7 * 1.31, 0.7 * 0.99, 1.31, 0.99)$ok)),
  list(nm = "lag-1 (b) NA 를 미달로", from = "identical(l_out$rules$slow$ok, FALSE)", to = "!isTRUE(l_out$rules$slow$ok)",
       kill = function(e) isTRUE(e$p2_lag_hold(DS, LSN))))
nk <- 0L
for (m in MU) {
  mt <- mutant(m$from, m$to)
  if (!is.null(mt$err)) { ng(paste("20 뮤테이션", m$nm), mt$err); next }
  if (isTRUE(m$kill(mt$env))) nk <- nk + 1L else ng(paste("20 뮤테이션 생존", m$nm))
}
if (nk == length(MU)) ok(sprintf("20 뮤테이션 %d/%d 검출(치환 성사 · 사본 단독 적재)", nk, length(MU)))
cat(sprintf("합계 PASS %d FAIL %d\n", PASS, FAIL))
cat(sprintf('{"test":"p2r03_evaluate_fixture","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
if (FAIL > 0L) quit(status = 1L)
