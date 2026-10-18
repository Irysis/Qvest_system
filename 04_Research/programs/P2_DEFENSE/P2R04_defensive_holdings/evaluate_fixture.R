## P2R04 evaluate.R 순수 도우미 픽스처 검사(합성 · 결과 무접촉 · 사전등록 고정 대상) — 본 실행 블록은 sys.nframe() > 0 이라 안 돈다
## 실행: Rscript evaluate_fixture.R
##   P2R03 승계 도우미(공통 창 · 위기 짝 · 깊은 위기 · 빠른 급락 · 강세 구간 · β 비대칭 · β 비 Δ · 알파 · 집중 · β 짝 사본 · 사이클 · 회복 · 라운드 판정 ·
##   선택 · 지문 · 핀) + P2R04 신설(과반 · β 짝 계획 · 셀 로그 적재 줄 · 방향 경로 줄 · ⑩ 구성 증거 3대조(장치 꼬리 반복) · 혼합 가중 · 보유 대조 ·
##   처치 전달 · ⑭ 선택 귀속(라벨 ∧ 위기 분해) · 칸 통과 · 판정 어휘 · 결론 이름 · 기록용 위기 · 크기 분위 · 크기 × β 짝 · 시장 기준점 · 국면 월 ·
##   유동성 분위 · RX0 동일성 · 진단 표 · 진단 기대 가중 · 진단 읽기(결측 · 용량 표 · 희석) · A 거리 · R7 판독(판독 불가 포함) · 규칙 키 · 규칙 승계 · 칸 목록(23칸) ·
##   보는 창 가림 · 판정 1칸 조기 미시험 경로(판정 · 진단 역할) · 격리 교차 점검 v1 반영(⑭ 분해 엄격 > 0 · ⑭ 미측정 = selection_unmeasured · 보류 이름 ·
##   판정어별 칸 수 라벨 · 작업 사본 표식 · 구성 비 주석)) + 뮤테이션(소스 텍스트 치환 · 치환 성사 단정 · 사본 단독 적재 — deparse 금지)
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat("  OK  ", m, "\n") }
ng <- function(m, d = "") { FAIL <<- FAIL + 1L; cat("  FAIL", m, d, "\n") }
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
RD <- file.path(ROOT, "04_Research/programs/P2_DEFENSE/P2R04_defensive_holdings")
EVF <- file.path(RD, "evaluate.R")
source(file.path(ROOT, "04_Research/programs/_lib/round_kit.R"))
source(EVF)
source(file.path(RD, "round_rules.R"))
source(file.path(ROOT, "02_Infrastructure/contracts/diagnosis_packet.R"))       # dp_scan_dates(가림 교차 대조 — 다른 구현)
if (exists("EVS")) ng("본 실행 블록이 source 에서 돌았다") else ok("01 source 시 본 실행 블록 미실행(sys.nframe 가드)")
J <- function(dt) fromJSON(toJSON(dt, na = "null"), simplifyVector = FALSE)
TMP <- gsub("\\\\", "/", tempdir())
TAU <- as.Date("2022-12-31")
BCP <- file.path(ROOT, "06_Registry/behavior_card.json")                         # 읽기만(규칙 상수의 행동 카드 키 원천)
FS <- p2r04_final_selection_rule(ROOT, BCP)

## 02) 장치 표 — DESIGN §3(H1 하방β D04 · H2 저변동 D03 · H3 β 비대칭 D07 · H4 퀄리티 Q08 · kind db) · 진단 표(C1~C4 E2 · W1~W4 E2 · E3 · N0 E2)
if (identical(names(P2R04_DEVICES), paste0("H", 1:4)) &&
    identical(unname(vapply(P2R04_DEVICES, `[[`, "", "id")), c("D04_Downside_Beta", "D03_RealVol", "D07_Beta_Asymmetry", "Q08_Composite_Quality")) &&
    identical(unname(vapply(P2R04_DEVICES, `[[`, "", "name")), c("하방β", "저변동", "β 비대칭", "퀄리티")) &&
    all(vapply(P2R04_DEVICES, function(d) identical(d$kind, "db") && nzchar(d$basis), logical(1))) &&
    identical(names(P2R04_DIAGNOSTICS), c(paste0("C", 1:4), paste0("W", 1:4), "N0")) &&
    identical(unname(vapply(P2R04_DIAGNOSTICS[paste0("W", 1:4)], function(d) paste(d$engines, collapse = "+"), "")), rep("E2+E3", 4)) &&
    identical(P2R04_DIAGNOSTICS$C3$pair, "H3") && identical(P2R04_DIAGNOSTICS$N0$kind, "null_perm") && identical(P2R04_DIAGNOSTICS$C1$weight, 0))
  ok("02 장치 표 H1~H4(D04 · D03 · D07 · Q08 · db) · 진단 표 C(E2 · 가중 0) · W(E2 · E3) · N0(E2 · null_perm)") else ng("02")

## 03) 공통 창 사본(P2R03 승계)
src <- file.path(TMP, "p2r04_src"); out <- file.path(TMP, "p2r04_out"); unlink(c(src, out), recursive = TRUE); dir.create(src)
d <- seq(as.Date("2005-01-03"), by = "day", length.out = 40); r <- c(rep(0.01, 10), rep(-0.02, 10), rep(0.005, 20)); nav <- cumprod(1 + r)
fwrite(data.table(date = d, ret_net = r), file.path(src, "03_period_returns.csv"))
fwrite(data.table(date = d, benchmark_ret = r / 2, benchmark_nav = cumprod(1 + r / 2)), file.path(src, "05_benchmark_returns.csv"))
fwrite(data.table(date = d, nav_gross = nav * 1.001, nav_net = nav, cum_cost = nav * 0.001, drawdown_net = nav / cummax(nav) - 1), file.path(src, "02_nav.csv"))
fwrite(data.table(date = rep(d[c(1, 15, 30)], each = 2), ticker = rep(c("000660", "005930"), 3), target_weight = 0.5), file.path(src, "04_holdings.csv"))
writeLines('{"y":2}', file.path(src, "authoritative_remeasure.json"))
st <- d[20]; p2_trim_artifacts(src, out, st)
nv2 <- fread(file.path(out, "02_nav.csv")); H2 <- fread(file.path(out, "04_holdings.csv"), colClasses = list(character = "ticker"))
if (min(as.Date(nv2$date)) == st && abs(nv2$nav_net[1] - 1) < 1e-12 && identical(sort(unique(as.character(as.Date(H2$date)))), as.character(d[c(15, 30)])) &&
    identical(H2$ticker[1], "000660") && file.exists(file.path(out, "authoritative_remeasure.json"))) ok("03 공통 창 — NAV 재기준 · 보유 = 시작에 들던 리밸부터 · 선행 0 보존 · 비 CSV 복사") else ng("03")

## 04) 위기 짝 비율(dd_capture · tol)
CR3 <- data.table(peak_date = c("2008-05-16", "2011-05-02", "2020-01-22"), trough_date = c("2008-10-24", "2011-09-26", "2020-03-19"))
crm <- J(copy(CR3)[, `:=`(dd_capture = c(0.60, 0.95, 0.70), bm_dd = c(-0.49, -0.27, -0.35))])
crr <- J(copy(CR3)[, `:=`(dd_capture = c(0.80, 0.90, 0.75), bm_dd = c(-0.49, -0.27, -0.35))])
mj <- p2_crisis_majority(crm, crr, 0.03)
if (mj$n_pair == 3L && mj$n_better == 2L && abs(mj$share - 2/3) < 1e-12 && mj$unpaired == 0L &&
    p2_crisis_majority(crm, crr, 0.06)$n_better == 1L && is.na(p2_crisis_majority(list(), crr, 0.03)$share) && p2_crisis_majority(crm[1:2], crr, 0.03)$unpaired == 1L)
  ok("04 위기 짝 3 · 개선 2(0.20 · 0.05 > 0.03) · 문턱 0.06 이면 1 · 위기 없음 NA · 한 칸에만 있는 위기 = 짝 없음 1") else ng("04", paste(mj$n_pair, mj$n_better))

## 05) 깊은 위기 = 벤치 낙폭 크기 ≥ 중앙값
dk <- p2_deep_crisis_keys(crm, crr)
if (identical(sort(dk), sort(c("2008-05-16 2008-10-24", "2020-01-22 2020-03-19")))) ok("05 깊은 위기 = 2008 · 2020(중앙값 0.35 이상)") else ng("05", paste(dk))

## 06) 빠른 급락 — 21거래일 창 · 문턱 −20% 경계 · 날짜 불일치 = 분류 못 함 · 위기 안 월말 0 = 일화 판 제외 목록
bd <- seq(as.Date("2010-01-04"), by = "day", length.out = 300); rr <- rep(0, 300)
rr[11:20] <- (0.75)^(1/10) - 1; rr[101:200] <- (0.70)^(1/100) - 1; rr[231:252] <- (0.80)^(1/22) - 1; rr[261:281] <- (0.80)^(1/21) - 1
BR <- data.table(date = bd, benchmark_ret = rr)
CRF <- J(data.table(peak_date = format(bd[c(10, 100, 230, 260, 1)]), trough_date = format(c(bd[c(20, 200, 252, 281)], as.Date("2009-12-31")))))
fk <- p2_fast_crash_keys(BR, CRF, 21L, -0.20); TBF <- fk$table
bm25 <- seq(as.Date("2011-01-03"), as.Date("2011-03-31"), by = "day"); r25 <- rep(0, length(bm25)); i1 <- which(bm25 == as.Date("2011-02-03")); i2 <- which(bm25 == as.Date("2011-02-17"))
r25[(i1 + 1):i2] <- (0.75)^(1 / (i2 - i1)) - 1
fk25 <- p2_fast_crash_keys(data.table(date = bm25, benchmark_ret = r25), J(data.table(peak_date = "2011-02-03", trough_date = "2011-02-17")), 21L, -0.20)
if (identical(fk$keys, c(paste(bd[10], bd[20]), paste(bd[260], bd[281]))) && isTRUE(abs(TBF$max_drop[1] + 0.25) < 1e-9) && identical(TBF$fast[2], FALSE) &&
    identical(TBF$fast[3], FALSE) && identical(fk$unclassified, paste(bd[1], "2009-12-31")) &&
    identical(fk25$no_month_end, "2011-02-03 2011-02-17") && identical(fk25$table$month_ends_inside, 0L))
  ok("06 빠름 = 10일 −25% · 21일 −20% 경계 · 느림 = 100일 −30% · 22일 −20% · 날짜 불일치 = 분류 못 함 · 월 안 급락 = 월말 0 목록") else ng("06", paste(fk$keys, collapse = "|"))

## 07) 강세 구간별 — 양수 기준 80% · 음수 기준 일반화(기준 − 0.2|기준|) · 짝 < 2 = NA
BL <- data.table(start_ym = c("2009-03", "2011-10", "2013-07", "2016-02"), end_ym = c("2011-04", "2013-02", "2014-07", "2017-10"))
bm5 <- J(copy(BL)[, up_capture := c(0.85, 0.70, -0.23, -0.25)]); br5 <- J(copy(BL)[, up_capture := c(1.00, 1.00, -0.20, -0.20)])
bs <- p2_bull_segments(bm5, br5, 0.8, 2L)
if (bs$n_pair == 4L && identical(bs$per_phase[order(k)]$ok, c(TRUE, FALSE, TRUE, FALSE)) && abs(bs$share - 0.5) < 1e-12 &&
    is.na(p2_bull_segments(bm5[1], br5[1], 0.8, 2L)$share) && is.na(p2_bull_segments(list(), br5, 0.8, 2L)$share))
  ok("07 강세 — 0.85 ✓ · 0.70 ✗ · 음수 기준 −0.20 → 문턱 −0.24: −0.23 ✓ · −0.25 ✗ → 0.5 · 짝 1 · 국면 없음 = NA") else ng("07")

## 08) β 비대칭 수준 · 09) β 비 Δ(정적 축소 불변)
if (isTRUE(p2_beta_asym(0.8, 1.0)) && identical(p2_beta_asym(1.1, 0.9), FALSE) && identical(p2_beta_asym(1.0, 1.0), FALSE) && is.na(p2_beta_asym(NA, 1)))
  ok("08 하락장 β < 상승장 β 만 참 · 같음 = 거짓 · NA = NA") else ng("08")
d0 <- p2_beta_ratio_delta(1.31, 0.99, 1.31, 0.99); dk7 <- p2_beta_ratio_delta(0.7 * 1.31, 0.7 * 0.99, 1.31, 0.99); dg <- p2_beta_ratio_delta(0.9, 0.95, 1.31, 0.99)
if (identical(d0$ok, FALSE) && identical(dk7$ok, FALSE) && isTRUE(abs(dk7$delta) < 1e-12) && isTRUE(dg$ok) && is.na(p2_beta_ratio_delta(1, 0, 1, 1)$ok) && is.na(p2_beta_ratio_delta(NA, 1, 1, 1)$ok))
  ok("09 β 비 Δ — 같은 비 = 거짓 · 정적 0.7 배 축소 = Δ 0 · 비 1.32 → 0.95 = 참 · 상승 β 0 · NA = NA") else ng("09")

## 10) 알파 비열등
a1 <- p2_alpha_ok(list(t = -1.5, d_alpha = -0.01), -2, 0.10, 0.2); a2 <- p2_alpha_ok(list(t = -1.5, d_alpha = -0.03), -2, 0.10, 0.2)
a3 <- p2_alpha_ok(list(t = -2.5, d_alpha = 0), -2, 0.10, 0.2); a4 <- p2_alpha_ok(list(t = 0.5, d_alpha = -0.001), -2, -0.05, 0.2); a5 <- p2_alpha_ok(list(t = NA, d_alpha = 0), -2, 0.1, 0.2)
if (isTRUE(a1) && identical(a2, FALSE) && identical(a3, FALSE) && identical(a4, FALSE) && is.na(a5)) ok("10 여유 = 0.2 × 엔진 α · t 문턱 · 엔진 α ≤ 0 이면 감소 허용 0 · NA = NA") else ng("10")

## 11) 집중 손실 — 깊은 위기 −18% = breach · 깊은 위기가 −4% 뿐이면 clear · 깊지 않은 위기(−12%)는 안 셈 · 누락 · 표 없음 = 미측정
tl <- J(data.table(peak_date = c("2008-05-16", "2008-05-16", "2020-01-22", "2011-05-02"), Ticker = c("A", "B", "C", "D"), contrib = c(-0.18, -0.02, -0.04, -0.12)))
tl2 <- J(data.table(peak_date = c("2020-01-22", "2011-05-02"), Ticker = c("C", "D"), contrib = c(-0.04, -0.12)))
t1 <- p2_top_loss(tl, c("2008-05-16", "2020-01-22"), -0.10)
if (identical(p2_conc_status(t1), "breach") && identical(t1$n_breach, 1L) && identical(p2_conc_status(p2_top_loss(tl2, "2020-01-22", -0.10)), "clear") &&
    identical(p2_conc_status(p2_top_loss(tl2, c("2008-05-16", "2020-01-22"), -0.10)), "unmeasured") && identical(p2_conc_status(p2_top_loss(list(), "2008-05-16", -0.10)), "unmeasured"))
  ok("11 집중 — 깊은 위기 −18% breach · 깊은 위기 −4% 뿐 = clear(2011 −12% 는 깊지 않아 안 셈) · 깊은 위기 누락 · 표 없음 = 미측정") else ng("11")

## 12) β 짝 사본 — 수익 · 보유 k 배 · 벤치 그대로 · k > 1 거부
bsrc <- file.path(TMP, "p2r04_bsrc"); bout <- file.path(TMP, "p2r04_bout"); unlink(c(bsrc, bout), recursive = TRUE); dir.create(bsrc)
for (f in c("02_nav.csv", "03_period_returns.csv", "04_holdings.csv", "05_benchmark_returns.csv")) file.copy(file.path(src, f), bsrc)
p2_beta_scaled_copy(bsrc, bout, 0.8)
pb <- fread(file.path(bout, "03_period_returns.csv")); hb <- fread(file.path(bout, "04_holdings.csv")); bb <- fread(file.path(bout, "05_benchmark_returns.csv"))
if (isTRUE(all.equal(pb$ret_net, 0.8 * r)) && isTRUE(all.equal(sum(hb[date == min(date)]$target_weight), 0.8)) && isTRUE(all.equal(bb$benchmark_ret, r / 2)) &&
    inherits(try(p2_beta_scaled_copy(bsrc, bout, 1.2), silent = TRUE), "try-error")) ok("12 β 짝 사본 — 수익 · 보유 k 배 · 벤치 그대로 · k > 1 거부") else ng("12")

## 13) 사이클 짝 — 실제 보는 창 벤치 연대기(날짜) · 성과는 합성
CRISES <- data.table(peak_date = c("2007-10-11", "2008-05-16", "2008-11-05", "2011-05-02", "2017-11-03", "2020-01-22", "2021-06-25"),
                     trough_date = c("2008-03-17", "2008-10-24", "2008-11-20", "2011-09-26", "2019-08-07", "2020-03-19", "2022-09-30"))
BULLS <- data.table(start_ym = c("2009-03", "2011-10", "2013-07", "2016-02", "2020-04"), end_ym = c("2011-04", "2013-02", "2014-07", "2017-10", "2021-06"))
bu_m <- J(copy(BULLS)[, st_cum := c(0.80, 0.30, 0.20, 0.40, 0.90)]); bu_r <- J(copy(BULLS)[, st_cum := c(0.90, 0.35, 0.25, 0.45, 1.00)])
cr_m <- J(copy(CRISES)[, st_cum := c(-0.20, -0.40, -0.05, -0.12, -0.15, -0.25, -0.20)]); cr_r <- J(copy(CRISES)[, st_cum := c(-0.25, -0.45, -0.06, -0.20, -0.10, -0.28, -0.30)])
cy <- p2_cycle_compound(bu_m, cr_m, bu_r, cr_r)
if (cy$n_pair == 3L && cy$n_ge == 2L && abs(cy$share - 2/3) < 1e-12 && length(cy$unpaired_crises) == 4L && cy$pair_mismatch == 0L &&
    is.na(p2_cycle_compound(J(BULLS[1][, st_cum := 0.8]), J(CRISES[1:4][, st_cum := -0.1]), J(BULLS[1][, st_cum := 0.9]), J(CRISES[1:4][, st_cum := -0.2]))$share))
  ok("13 사이클 짝 3(2011 · 2017-11 · 2021-06) · 칸 ≥ 기준 2/3 · 짝 없는 위기 4 · 짝 1 → NA") else ng("13", paste(cy$n_pair, cy$n_ge))

## 14) 회복 꼬리표 — 더 긴 위기 과반 · 관측 열 없음 = 미측정 · 미회복(검열) = 관측 하한 무한대 · 둘 다 미회복 = 제외
rc_m <- J(copy(CR3)[, `:=`(st_recovery_obs = c(400, 100, 300), st_recovery_censored = c(FALSE, FALSE, TRUE))])
rc_r <- J(copy(CR3)[, `:=`(st_recovery_obs = c(300, 120, 200), st_recovery_censored = c(FALSE, FALSE, FALSE))])
rt <- p2_recovery_tag(rc_m, rc_r, 0.5); rt0 <- p2_recovery_tag(J(CR3), rc_r, 0.5)
rc_m2 <- J(copy(CR3)[, `:=`(st_recovery_obs = c(NA, 100, NA), st_recovery_censored = c(TRUE, FALSE, TRUE))])
rc_r2 <- J(copy(CR3)[, `:=`(st_recovery_obs = c(300, 120, NA), st_recovery_censored = c(FALSE, FALSE, TRUE))])
rt2 <- p2_recovery_tag(rc_m2, rc_r2, 0.5)
if (identical(rt$n_longer, 2L) && isTRUE(rt$tag) && identical(rt0$status, "unmeasured") && identical(rt2$n_pair, 2L) && identical(rt2$n_longer, 1L) &&
    identical(rt2$n_censored_variant, 1L) && identical(rt2$tag, FALSE))
  ok("14 회복 — 더 긴 위기 2/3 → '회복 지연' · 관측 열 없음 = 미측정 · 변형만 미회복 = 더 김 · 둘 다 미회복 = 제외 · 1/2 = 과반 아님") else ng("14")

## 15) 라운드 판정 — 장치 × 엔진 · 두 엔진 통과만 검증 · 집중 제외 · 판정 칸 수 표기
T1 <- data.table(engine = rep(c("E2", "E3"), each = 2), device = rep(c("H1", "H2"), 2), tested = TRUE, pass = c(TRUE, FALSE, TRUE, TRUE), excluded = FALSE)
v1 <- p2_round_verdict(T1)
T6 <- copy(T1)[, pass := TRUE][, excluded := c(TRUE, FALSE, FALSE, FALSE)]; v6 <- p2_round_verdict(T6)
T3 <- copy(T1)[, pass := FALSE][1:2, tested := FALSE]
if (identical(v1$verdict, "supported") && identical(v1$both, "H1") && identical(v1$one, "H2") && identical(v1$label, "supported(판정 4/4)") &&
    identical(v6$excluded, "H1") && identical(v6$both, "H2") && identical(p2_round_verdict(T3)$label, "falsified(판정 2/4)") &&
    identical(p2_round_verdict(copy(T1)[, tested := FALSE])$verdict, "untested"))
  ok("15 supported(판정 4/4) · 한 엔진 = partial 재료 · 집중 제외 = 검증 아님 · falsified(판정 2/4) · untested") else ng("15", v1$label)

## 16) 선택 — S 증분(두 엔진 평균) · 동률이면 ③ · ④ 비율 합 · 검증 0 = 선택 없음
mk <- function(dv, s, s0, b3, b4) list(device = dv, non_inferiority = list(S = s, S_rx0 = s0), rules = list(beta_deep = list(share = b3), fast = list(share = b4)))
sel <- p2_select(list(H2 = list(mk("H2", 0.8, 0.5, 0.6, 0.6), mk("H2", 0.45, 0.5, 0.6, 0.6)), H1 = list(mk("H1", 0.7, 0.5, 0.6, 0.6), mk("H1", 0.6, 0.5, 0.6, 0.6))))
selt <- p2_select(list(H1 = list(mk("H1", 0.7, 0.5, 0.6, 0.6)), H3 = list(mk("H3", 0.7, 0.5, 0.8, 0.8))))
if (identical(sel[[1]]$device, "H1") && isTRUE(abs(sel[[1]]$dS - 0.15) < 1e-12) && identical(selt[[1]]$device, "H3") && identical(selt[[1]]$tie_break, "r34") && !length(p2_select(list())))
  ok("16 선택 — 평균 S 증분 H1 0.15 > H2 0.125 · 동률이면 ③ · ④ 비율 합(H3) · 검증 0 = 선택 없음") else ng("16")

## 17) 지문 비교 — 이름 붙은 벡터
fa <- c(HRP1 = "x|y"); fb <- "x|y"
if (!identical(fa, fb) && isTRUE(p2_fp_same(fa, fb)) && !isTRUE(p2_fp_same("x|y", "x|z"))) ok("17 identical(이름 붙은, 이름 없는) = 거짓 · p2_fp_same = 참 · 다르면 거짓") else ng("17")

## 18) 핀 재대조 — 일치 0 · 팩터 레지스트리 엔트리 변경 · 대조 함수 없는 핀 종류 = 불일치(침묵 통과 금지)
PRT <- file.path(TMP, "p2r04_pinroot"); unlink(PRT, recursive = TRUE); dir.create(file.path(PRT, "06_Registry"), recursive = TRUE); dir.create(file.path(PRT, ".cache/factor_db"), recursive = TRUE)
writeLines(toJSON(list(entries = list(list(catalog_id = "lean:entropy", status = "active", resolver = list(f = "x")))), auto_unbox = TRUE), file.path(PRT, "06_Registry/weight_catalog.json"))
writeLines(toJSON(list(D03_RealVol = list(name = "Realized Volatility", direction = "lower_better")), auto_unbox = TRUE), file.path(PRT, ".cache/factor_db/factor_registry.json"))
writeLines("a", file.path(PRT, "f.txt"))
pre_ok <- list(cells = list(), operational_pins = list(files = list(list(path = "f.txt", md5 = unname(tools::md5sum(file.path(PRT, "f.txt"))))),
               catalog_entries = list(list(catalog_id = "lean:entropy", status = "active", resolver = list(f = "x"))),
               factor_registry_entries = list(list(id = "D03_RealVol", entry = list(name = "Realized Volatility", direction = "lower_better"))),
               packages = list(), r_version = R.version.string))
pre_fr <- pre_ok; pre_fr$operational_pins$factor_registry_entries[[1]]$entry$direction <- "higher_better"
pre_unk <- pre_ok; pre_unk$operational_pins$factor_db_snapshot <- list(list(path = "x"))
if (!length(p2_pin_mismatches(pre_ok, PRT)) && identical(p2_pin_mismatches(pre_fr, PRT), "팩터 레지스트리 엔트리: D03_RealVol") &&
    length(p2_pin_mismatches(pre_unk, PRT)) == 1L && grepl("대조 함수 없는 운영 핀 종류", p2_pin_mismatches(pre_unk, PRT)) && grepl("factor_db_snapshot", p2_pin_mismatches(pre_unk, PRT)))
  ok("18 핀 — 일치 = 0 · 팩터 레지스트리 엔트리 변경 = 불일치 1 · 대조 함수 없는 핀 종류 = 불일치 1(침묵 통과 금지)") else ng("18", paste(p2_pin_mismatches(pre_unk, PRT)))

## 19) 과반 — 비율이 문턱을 '넘어야'(같음 = 거짓) · 비유한 = 거짓
if (identical(p2_maj(0.5, 0.5), FALSE) && isTRUE(p2_maj(0.51, 0.5)) && identical(p2_maj(NA, 0.5), FALSE) && identical(p2_maj(c(0.9, 0.9), 0.5), FALSE) && identical(p2_maj(0.9, NULL), FALSE))
  ok("19 과반 — 0.5 vs 0.5 = 거짓 · 0.51 = 참 · NA · 길이 2 · 문턱 없음 = 거짓") else ng("19")

## 20) β 짝 계획 — k < 1 사본 · k ≥ 1(1 포함) = RX0 · 비유한 · RX0 β ≤ 0 · k ≤ 0 = 미측정 · 강제 k(리허설)
b1 <- p2_beta_plan(0.8, 1); b2 <- p2_beta_plan(1.2, 1); b3 <- p2_beta_plan(1, 1); b4 <- p2_beta_plan(NA, 1); b5 <- p2_beta_plan(1, 0); b6 <- p2_beta_plan(0.5, 1, 0.9); b7 <- p2_beta_plan(0.5, 1, -1)
if (identical(b1$mode, "scaled") && isTRUE(abs(b1$k - 0.8) < 1e-12) && identical(b1$comparator, "RX0 × k") && identical(b2$mode, "rx0") && identical(b3$mode, "rx0") &&
    identical(b4$mode, "unmeasured") && identical(b5$mode, "unmeasured") && identical(b6$mode, "scaled") && isTRUE(b6$forced) && identical(b6$k, 0.9) && identical(b7$mode, "unmeasured"))
  ok("20 β 짝 계획 — 0.8 사본 · 1.2 · 1.0 = RX0 · NA · RX0 β 0 · 강제 −1 = 미측정 · 강제 0.9 = 사본(forced)") else ng("20")

## 21) 셀 로그 적재 줄 — E2 none · E2 1팩터 · E3 4팩터 · 마지막 줄 · CRLF · 적재 줄 없음 · 형식 어긋남
ln <- function(cell, fac, wt = "ew") sprintf("[rf_cell_engine] cell=%s | univ=all_hyg | factors=%s | wt=%s | months=322 | rows=6525", cell, fac, wt)
E3F <- "M01_Mom_12_1+V10_FCF_Yield+M08_Residual_Mom"
LG_E2_0 <- c("[rf_cell_engine] 기저 캐시 적중 — base_v2_x.rds (375198행)", ln("P2R04_E2_RX0", "none"))
LG_E2_H2 <- ln("P2R04_E2_H2", "D03_RealVol"); LG_E3_0 <- ln("P2R04_E3_RX0", E3F, "catalog")
LG_E3_H1 <- ln("P2R04_E3_H1", paste0(E3F, "+", paste(rep("D04_Downside_Beta", 6), collapse = "+")), "catalog")
p0 <- p2_parse_cell_log(LG_E2_0); p1 <- p2_parse_cell_log(paste0(LG_E2_H2, "\r")); p3 <- p2_parse_cell_log(LG_E3_H1)
p2l <- p2_parse_cell_log(c(ln("OLD", "none"), LG_E2_H2)); pn <- p2_parse_cell_log(c("[rf_cell_engine] catalog lean:entropy | x", "noise"))
pb <- p2_parse_cell_log(sub(" \\| rows=6525$", "", LG_E2_H2))
if (isTRUE(p0$found) && identical(p0$factors, character(0)) && identical(p0$cell, "P2R04_E2_RX0") && identical(p1$factors, "D03_RealVol") && identical(p1$months, 322L) &&
    identical(p3$factors, c("M01_Mom_12_1", "V10_FCF_Yield", "M08_Residual_Mom", rep("D04_Downside_Beta", 6))) && identical(p3$wt, "catalog") &&
    identical(p2l$cell, "P2R04_E2_H2") && identical(p2l$n_lines, 2L) && !isTRUE(pn$found) && !isTRUE(pb$found))
  ok("21 적재 줄 — none = 빈 목록 · D03 · E3 3팩터 + 장치 6회 순서 · CRLF · 마지막 줄 · 적재 줄 없음 · rows 없는 줄 = 못 찾음") else ng("21")

## 22) 팩터 방향 경로 줄 — 블록(팩터) 경계 · 평가 창(창 시작에 유효한 신호일 ~ τ) · 레지스트리 대체 꼬리표 · 블록 불일치 · 없음
dl <- function(d, ic, reg, def, n) c(sprintf("[align_factor_direction] PIT-safe: sig_date=%s | min_months=36", d),
                                      sprintf("[align_factor_direction] loaded-factor direction: IC-inferred=%d / registry-fallback=%d / default-fallback=%d (n_factors=%d)", ic, reg, def, n))
SD <- c("2004-12-31", "2005-01-31", "2005-02-28", "2023-01-31")
LD <- c("[factor_db_connector] Loaded.", dl(SD[1], 1L, 0L, 0L, 1L), dl(SD[2], 1L, 0L, 0L, 1L), dl(SD[3], 1L, 0L, 0L, 1L), dl(SD[4], 1L, 0L, 0L, 1L),
        "[align_factor_direction] PIT-safe: sig_date=2005-01-31 | min_months=36", "noise",
        dl(SD[1], 0L, 1L, 0L, 1L), dl(SD[2], 0L, 1L, 0L, 1L), dl(SD[3], 1L, 0L, 0L, 1L), dl(SD[4], 1L, 0L, 0L, 1L))
DD <- p2_parse_direction_lines(LD)
r2 <- p2_direction_record(DD, 2L, "2005-02-02", TAU); r1 <- p2_direction_record(DD, 1L, "2005-02-02", TAU)
if (nrow(DD) == 8L && max(DD$block) == 2L && identical(DD[block == 2L]$reg, c(1L, 1L, 0L, 0L)) && identical(r2$n_sig, 2L) && identical(r2$registry_fallback, 1L) &&
    identical(r2$ic_inferred, 1L) && identical(r2$first, "2005-01-31") && !is.na(r2$tag) && identical(r1$registry_fallback, 0L) && is.na(r1$tag) &&
    identical(p2_direction_record(DD, 3L, "2005-02-02", TAU)$status, "block_mismatch") && identical(p2_direction_record(data.table(), 1L, NA, TAU)$status, "absent"))
  ok("22 방향 경로 — 2블록 · 블록 2 평가 창(2005-01-31 ~ τ) 신호일 2 · 레지스트리 대체 1 → 꼬리표 · τ 뒤 제외 · 블록 3 = 불일치 · 줄 없음 = absent") else ng("22", paste(nrow(DD), r2$n_sig, r2$registry_fallback))

## 23) ⑩ 구성 증거 3대조(사양 · 변형 로그 · RX0 로그) — 장치 꼬리 반복(E3 50% = 6회) 허용 · 겹치지 않게 하나씩 깨진다
fe <- function(...) lapply(c(...), function(i) list(kind = "db", id = i))
SR3 <- fe("M01_Mom_12_1", "V10_FCF_Yield", "M08_Residual_Mom")
cc <- function(lv, lr, dev, sv, sr, ec = "P2R04_E2_H2", er = "P2R04_E2_RX0") p2_construction_check(p2_parse_cell_log(lv), p2_parse_cell_log(lr), dev, sv, sr, ec, er)
c_e2 <- cc(LG_E2_H2, LG_E2_0, P2R04_DEVICES$H2, fe("D03_RealVol"), list())
c_e3 <- cc(LG_E3_H1, LG_E3_0, P2R04_DEVICES$H1, c(SR3, fe(rep("D04_Downside_Beta", 6))), SR3, "P2R04_E3_H1", "P2R04_E3_RX0")
c_sp <- cc(LG_E2_H2, LG_E2_0, P2R04_DEVICES$H1, fe("D03_RealVol"), list())                                   # 사양 끝 D03 ≠ 장치 H1(D04)
c_vl <- cc(ln("P2R04_E2_H2", "none"), LG_E2_0, P2R04_DEVICES$H2, fe("D03_RealVol"), list())                  # 변형 로그에 장치 팩터 미적재
c_rl <- cc(LG_E2_H2, ln("P2R04_E2_RX0", "D03_RealVol"), P2R04_DEVICES$H2, fe("D03_RealVol"), list())         # RX0 로그에 장치 팩터
c_cl <- cc(ln("P2R04_E2_H1", "D03_RealVol"), LG_E2_0, P2R04_DEVICES$H2, fe("D03_RealVol"), list())           # 변형 로그가 다른 칸
c_mid <- cc(ln("P2R04_E2_H2", "D03_RealVol+M01_Mom_12_1+D03_RealVol"), ln("P2R04_E2_RX0", "D03_RealVol+M01_Mom_12_1"), P2R04_DEVICES$H2,
            fe("D03_RealVol", "M01_Mom_12_1", "D03_RealVol"), fe("D03_RealVol", "M01_Mom_12_1"))               # 장치 팩터가 바탕에도(꼬리 밖)
c_rs <- cc(LG_E2_H2, LG_E2_0, P2R04_DEVICES$H2, fe("D03_RealVol"), fe("M01_Mom_12_1"))                        # RX0 사양 ≠ 바탕
c_kd <- cc(LG_E2_H2, LG_E2_0, P2R04_DEVICES$H2, list(list(kind = "price", id = "D03_RealVol")), list())       # kind 불일치
chk <- function(x) unname(unlist(x$checks))
if (isTRUE(c_e2$ok) && identical(c_e2$device_count, 1L) && isTRUE(c_e3$ok) && identical(c_e3$device_count, 6L) && identical(chk(c_sp), c(FALSE, TRUE, TRUE)) &&
    identical(chk(c_vl), c(TRUE, FALSE, TRUE)) && identical(chk(c_rl), c(TRUE, TRUE, FALSE)) && identical(chk(c_cl), c(TRUE, FALSE, TRUE)) &&
    !isTRUE(c_mid$checks$spec) && !isTRUE(c_rs$checks$spec) && !isTRUE(c_kd$checks$spec) && grepl("변형 로그", c_vl$why) && is.na(c_e2$why))
  ok("23 ⑩ 구성 — E2(꼬리 1) · E3(꼬리 6) 통과 · 사양≠장치 · 변형 로그 미적재 · RX0 로그 장치 · 다른 칸 로그 · 바탕에 장치 · RX0 사양 불일치 · kind 불일치가 각각 한 대조만 깬다") else
  ng("23", paste(chk(c_sp), chk(c_vl), chk(c_rl), collapse = "|"))

## 24) 혼합 가중 — E2 0.5 · E3 6회 0.25 → 0.5 · 도구 상자 기본 4팩터 0.125 · 결측 짝 w0 1 → 0 · w0 없음 m/(1+n) · 팩터 0 · m > n = NA
if (identical(p2_blend_weight(0.5, 1L)$device_weight, 0.5) && isTRUE(abs(p2_blend_weight(0.25, 9L, 6L)$device_weight - 0.5) < 1e-12) &&
    identical(p2_blend_weight(0.5, 4L, 1L)$device_weight, 0.125) && identical(p2_blend_weight(1, 1L, 1L)$device_weight, 0) &&
    isTRUE(abs(p2_blend_weight(NULL, 2L)$device_weight - 1/3) < 1e-12) && is.na(p2_blend_weight(0.5, 0L)$device_weight) && is.na(p2_blend_weight(0.5, 2L, 3L)$device_weight))
  ok("24 혼합 가중 — E2 0.5 · E3(0.25 · 6/9) 0.5 · 도구 상자 0.125 · 결측 짝 0 · w0 없음 1/3 · 팩터 0 · m > n = NA") else ng("24")

## 25) 보유 대조 — 같음 = 다름 0 · 한 종목 교체 · 비중만 다름 · τ 뒤 변화는 안 셈 · 한쪽에만 있는 보유일 = 다름 아님(따로 셈)
tick <- sprintf("%06d", 1:30); D3 <- as.Date(c("2010-01-04", "2010-02-01", "2023-03-02"))
H_R <- data.table(date = rep(D3, each = 25), ticker = rep(tick[1:25], 3), w = 0.04)
H_S <- copy(H_R)[date == D3[2] & ticker == tick[25], ticker := tick[26]]
H_W <- copy(H_R)[date == D3[1] & ticker %in% tick[1:2], w := c(0.05, 0.03)]
H_T <- copy(H_R)[date == D3[3] & ticker == tick[25], ticker := tick[27]]
H_O <- rbind(H_R, data.table(date = as.Date("2010-03-02"), ticker = tick[1:25], w = 0.04))
o_i <- p2_holdings_overlap(copy(H_R), H_R, TAU); o_s <- p2_holdings_overlap(H_S, H_R, TAU); o_w <- p2_holdings_overlap(H_W, H_R, TAU)
o_t <- p2_holdings_overlap(H_T, H_R, TAU); o_o <- p2_holdings_overlap(H_O, H_R, TAU)
if (identical(o_i$n_dates, 2L) && identical(o_i$n_differ, 0L) && identical(o_i$name_overlap_min, 1) && identical(o_s$n_differ, 1L) &&
    isTRUE(abs(o_s$name_overlap_min - 24/25) < 1e-12) && isTRUE(abs(o_s$weight_overlap_min - 0.96) < 1e-12) && identical(o_w$n_differ, 1L) &&
    identical(o_w$name_overlap_min, 1) && isTRUE(abs(o_w$weight_overlap_min - 0.99) < 1e-12) && identical(o_t$n_differ, 0L) &&
    identical(o_o$n_only_variant, 1L) && identical(o_o$n_differ, 0L) && identical(p2_holdings_overlap(H_R[0], H_R, TAU)$status, "unmeasured"))
  ok("25 보유 대조 — 같음 0 · 교체 1(이름 24/25 · 비중 0.96) · 비중만 1(이름 1 · 비중 0.99) · τ 뒤 0 · 변형만 있는 날 = 따로 1 · 빈 보유 = 미측정") else
  ng("25", paste(o_s$n_differ, o_w$n_differ, o_t$n_differ, o_o$n_only_variant))

## 26) 처치 전달 — 같음 = 거짓(무처치 = 미시험) · 다름 = 참 · 미측정 = 거짓
if (identical(p2_treatment_delivered(o_i), FALSE) && isTRUE(p2_treatment_delivered(o_s)) && identical(p2_treatment_delivered(list(status = "unmeasured", n_differ = NA_integer_)), FALSE))
  ok("26 처치 전달 — 보유 같음 = 거짓 · 다름 = 참 · 미측정 = 거짓") else ng("26")

## 27) ⑭ 선택 귀속 — 라벨(selection_defense 만 통과 · 확정 라벨 밖 · 대조 상태 오류 = 미측정) ∧ 위기 분해(선택 항 깊은 위기 과반 · 변형 − RX0 > 0 엄격 · 문턱 없음)
##     · 필드 없음 · 깊은 짝 < 2 = 미측정 · 둘 다 기록(격리 교차 점검 v1 필수 1 · 3)
s_a <- p2_selection_attr("selection_defense", FS$mc8_label_required); s_b <- p2_selection_attr("size_defense", FS$mc8_label_required)
s_c <- p2_selection_attr(NULL, FS$mc8_label_required); s_d <- p2_selection_attr("selection_defense", NULL); s_e <- p2_selection_attr("insufficient", list("selection_defense"))
s_f <- p2_selection_attr("selection_defense", FS$mc8_label_required, "no_holdings"); s_g <- p2_selection_attr("weird_label", FS$mc8_label_required)
EXV <- J(data.table(peak_date = c("2008-05-16", "2011-05-02", "2020-01-22"), trough_date = CR3$trough_date, selection_sum = c(-0.02, -0.10, -0.01)))
EXR <- J(data.table(peak_date = c("2008-05-16", "2011-05-02", "2020-01-22"), trough_date = CR3$trough_date, selection_sum = c(-0.08, -0.05, -0.06)))
DPK <- c("2008-05-16", "2020-01-22")
sd_ok <- p2_selection_decomp(EXV, EXR, DPK, 0.5); sd_no <- p2_selection_decomp(EXV, EXR, c("2008-05-16", "2011-05-02"), 0.5)
sd_na <- p2_selection_decomp(J(data.table(peak_date = "2008-05-16", strategy_sum = -0.1)), EXR, DPK, 0.5); sd_1 <- p2_selection_decomp(EXV, EXR, "2008-05-16", 0.5)
## 경계: 격리 교차 점검 재현 R1(차 +0.015 · +0.020 · +0.060 · −0.010 → 문턱 없는 엄격 판정 3/4 통과) · 차 = 0 은 개선 아님(엄격) · 작은 양수 +0.001 = 개선(문턱 없음)
PK4 <- c("2008-05-16", "2011-05-02", "2020-01-22", "2021-06-25"); TR4 <- c("2008-10-24", "2011-09-26", "2020-03-19", "2022-09-30")
ERX <- J(data.table(peak_date = PK4, trough_date = TR4, selection_sum = c(-0.10, -0.10, -0.10, -0.10)))
sd_r1 <- p2_selection_decomp(J(data.table(peak_date = PK4, trough_date = TR4, selection_sum = -0.10 + c(0.015, 0.020, 0.060, -0.010))), ERX, PK4, 0.5)
sd_eq <- p2_selection_decomp(J(data.table(peak_date = PK4, trough_date = TR4, selection_sum = c(-0.10, -0.10, -0.10, -0.099))), ERX, PK4, 0.5)
sd_sm <- p2_selection_decomp(J(data.table(peak_date = PK4, trough_date = TR4, selection_sum = -0.10 + c(0.001, 0.001, 0.001, -0.02))), ERX, PK4, 0.5)
ru_ok <- p2_selection_rule(s_a, sd_ok); ru_lb <- p2_selection_rule(s_b, sd_ok); ru_dc <- p2_selection_rule(s_a, sd_na); ru_in <- p2_selection_rule(s_e, sd_ok)
if (isTRUE(s_a$ok) && identical(s_a$status, "ok") && identical(s_b$ok, FALSE) && identical(s_b$status, "ok") && identical(s_c$status, "unmeasured") &&
    identical(s_d$status, "no_rule") && identical(s_e$status, "unmeasured") && identical(s_e$ok, FALSE) && identical(s_f$status, "unmeasured") && identical(s_g$status, "unmeasured") &&
    isTRUE(sd_ok$ok) && identical(sd_ok$n_better, 2L) && identical(sd_no$ok, FALSE) && identical(sd_na$status, "unmeasured") && identical(sd_na$ok, FALSE) &&
    identical(sd_1$status, "unmeasured") && isTRUE(sd_r1$ok) && identical(sd_r1$n_better, 3L) && identical(sd_eq$n_better, 1L) && identical(sd_eq$ok, FALSE) &&
    isTRUE(sd_sm$ok) && identical(sd_sm$n_better, 3L) && isTRUE(ru_ok$ok) && isTRUE(ru_ok$measured) && identical(ru_lb$ok, FALSE) && isTRUE(ru_lb$measured) &&
    identical(ru_lb$label, "size_defense") && isTRUE(ru_lb$decomposition$ok) && identical(ru_dc$ok, FALSE) && identical(ru_dc$status, "unmeasured(선택 항 분해)") &&
    identical(ru_dc$measured, FALSE) && isTRUE(ru_dc$label_ok) && identical(ru_in$measured, FALSE) && identical(ru_in$status, "unmeasured"))
  ok("27 ⑭ — 라벨 통과 · size_defense 측정됨 미통과 · insufficient · 라벨 없음 · 모르는 라벨 · 대조 상태 오류 = 미측정 · 분해 엄격 > 0(R1 3/4 통과 · 차 0 = 개선 아님 · +0.001 = 개선) · 필드 없음 · 짝 1 = 미측정") else ng("27")

## 28) 칸 통과 — 12 조건 모두 참일 때만(어느 하나만 거짓이어도 거짓 · NA = 거짓)
FL <- list(crisis = TRUE, deep = TRUE, beta_deep = TRUE, fast = TRUE, beta_ratio = TRUE, bull = TRUE, alpha = TRUE, cycle = TRUE, construction = TRUE, S = TRUE, path = TRUE, selection = TRUE)
one_off <- vapply(names(FL), function(k) { f <- FL; f[[k]] <- FALSE; p2_cell_pass(f) }, logical(1))
one_na <- vapply(names(FL), function(k) { f <- FL; f[[k]] <- NA; p2_cell_pass(f) }, logical(1))
if (isTRUE(p2_cell_pass(FL)) && !any(one_off) && !any(one_na) && length(FL) == 12L) ok("28 칸 통과 — ①~⑦ · ⑨ · ⑩ · ⑫ · ⑬ · ⑭ 12조건 · 하나 거짓 · NA = 거짓") else ng("28", paste(names(FL)[one_off], collapse = ","))

## 29) 판정 어휘 — 분기마다 하나 · 모두 사전 고정 어휘 안 · 이 라운드 이름('방어만 · 복리 없음' = '저변동 기계')
vf <- function(...) { f <- list(pass = FALSE, beta_unmeasured = FALSE, beta_deep = FALSE, fast = FALSE, crisis = FALSE, deep = FALSE, selection = FALSE,
                                 selection_measured = TRUE); a <- list(...); f[names(a)] <- a; p2_cell_verdict(f) }
VV <- c(pass = vf(pass = TRUE), bu1 = vf(beta_unmeasured = TRUE, beta_deep = TRUE), bu2 = vf(beta_deep = NA), fu = vf(beta_deep = TRUE, fast = NA),
        eo = vf(crisis = TRUE, deep = TRUE, beta_deep = FALSE), su = vf(beta_deep = TRUE, fast = TRUE, selection = FALSE, selection_measured = FALSE),
        se = vf(beta_deep = TRUE, fast = TRUE, selection = FALSE),
        ds = vf(crisis = TRUE, deep = TRUE, beta_deep = TRUE, fast = TRUE, selection = TRUE), nd1 = vf(beta_deep = TRUE, fast = FALSE),
        nd2 = vf(beta_deep = TRUE, fast = TRUE, selection = TRUE, crisis = FALSE, deep = TRUE),
        bu3 = vf(beta_deep = NA, selection_measured = FALSE), eo2 = vf(crisis = TRUE, deep = TRUE, beta_deep = FALSE, selection_measured = FALSE))
if (identical(unname(VV), c("pass", "beta_unmeasured", "beta_unmeasured", "fast_unmeasured", "exposure_only", "selection_unmeasured", "size_or_exposure_defense",
                            "defense_but_strength_or_path", "not_decisive", "not_decisive", "beta_unmeasured", "exposure_only")) && all(VV %in% P2R04_VERDICTS) &&
    "untested" %in% P2R04_VERDICTS && setequal(names(P2R04_VERDICT_NAMES), P2R04_VERDICTS) && setequal(names(P2R04_VERDICT_SHORT), P2R04_VERDICTS) &&
    grepl("저변동 기계", P2R04_VERDICT_NAMES[["defense_but_strength_or_path"]]) && identical(P2R04_VERDICT_NAMES[["selection_unmeasured"]], "선택 귀속 미측정 — 방어 이름 보류"))
  ok("29 어휘 — pass · beta_unmeasured · fast_unmeasured · exposure_only · selection_unmeasured(③④ 통과 ∧ ⑭ 미측정 · 이름 보류) · size_or_exposure_defense · 저변동 기계 · not_decisive") else
  ng("29", paste(VV, collapse = ","))

## 30) 기록용 위기(상태 미전환 최대 하락 위기 · C-019) — 사전등록 목록 · 짝 없는 위기 · RX0 · β 짝 승패 · 사본 없음 = NA
CRT <- data.table(peak_date = c("2007-10-11", "2008-05-16", "2011-05-02"), trough_date = c("2008-03-17", "2008-10-24", "2011-09-26"))
rcm <- J(copy(CRT)[, dd_capture := c(0.50, 0.60, 0.90)]); rcr <- J(copy(CRT)[, dd_capture := c(0.70, 0.80, 0.85)]); rcb <- J(copy(CRT)[, dd_capture := c(0.60, 0.70, 0.80)])
REC <- p2_crisis_record(rcm, rcr, rcb, FS$state_unturned_max_drop_crises, 0.03, deep = "2011-05-02 2011-09-26", fast = "2011-05-02 2011-09-26")
REC0 <- p2_crisis_record(rcm[c(1, 2)], rcr[c(1, 2)], list(), FS$state_unturned_max_drop_crises, 0.03)
if (identical(REC$crisis, c("2007-10-11 2008-03-17", "2011-05-02 2011-09-26")) && identical(REC$beats_rx0, c(TRUE, FALSE)) && identical(REC$beats_beta_copy, c(TRUE, FALSE)) &&
    identical(REC$deep, c(FALSE, TRUE)) && identical(REC0$in_pairs, c(TRUE, FALSE)) && all(is.na(REC0$beats_beta_copy)))
  ok("30 상태 미전환 최대 하락 위기 — 2007-10 · 2011-05 · RX0 · β 짝 승패 · 깊음 표기 · 짝 없는 위기 · 사본 없음 = NA") else ng("30")

## 31) 위기 중 크기 분위 — 종목 가중 평균 분위 · 분위 결측은 셈에서 빼고 따로 · 깊은 위기 평균
BSD_V <- J(data.table(size_decile = c(10, 9, NA, 10), contrib = c(-0.1, -0.05, -0.01, -0.2), n = c(3, 2, 1, 5), peak_date = c("2008-05-16", "2008-05-16", "2008-05-16", "2011-05-02")))
BSD_R <- J(data.table(size_decile = c(5, 6), contrib = c(-0.1, -0.1), n = c(4, 4), peak_date = c("2008-05-16", "2011-05-02")))
SZ <- p2_size_compare(BSD_V, BSD_R, "2008-05-16"); sp8 <- SZ$per_crisis[peak_date == "2008-05-16"]
if (identical(SZ$status, "ok") && isTRUE(abs(sp8$mean_decile - 9.6) < 1e-12) && identical(sp8$n_unknown, 1) && identical(sp8$mean_decile_rx0, 5) &&
    isTRUE(abs(SZ$deep_mean_decile - 9.6) < 1e-12) && identical(SZ$deep_mean_decile_rx0, 5) && identical(p2_size_compare(list(), BSD_R)$status, "absent"))
  ok("31 크기 분위 — 2008 변형 9.6(결측 1 제외) vs RX0 5 · 깊은 위기 평균 · 패킷에 없으면 absent") else ng("31")

## 32) 규칙 키 — round_rules 산출이 평가가 요구하는 키를 다 갖는다 · 하나 빠지면 그 키를 짚는다 · 구 이름(from_top_crises) 없음
FSx <- FS; FSx$mc8_label_required <- NULL
if (!length(p2_fs_missing(FS)) && identical(p2_fs_missing(FSx), "mc8_label_required") && identical(p2_fs_missing(NULL), P2R04_FS_KEYS) &&
    !("from_top_crises" %in% names(FS)) && "state_unturned_max_drop_crises" %in% P2R04_FS_KEYS)
  ok("32 규칙 키 — 결손 0 · mc8_label_required 결손 검출 · 규칙 없음 = 전부 결손 · 구 키 이름 없음(C-019)") else ng("32", paste(p2_fs_missing(FS), collapse = ","))

## 33) 규칙 승계 — P2R03 final_selection_rule 의 키 · 값 · 근거 문장 그대로(같은 행동 카드 설정) + mc8 라벨 = 계약 enum + 기록용 위기 = 설계 노트 두 위기
e3 <- new.env(); sys.source(file.path(ROOT, "04_Research/programs/P2_DEFENSE/P2R03_conditional_overlay/round_rules.R"), envir = e3, keep.source = FALSE)
F3 <- e3$p2r03_final_selection_rule(ROOT, BCP)
same3 <- vapply(names(F3), function(k) identical(F3[[k]], FS[[k]]), logical(1))
MCS <- readLines(file.path(ROOT, "02_Infrastructure/contracts/matched_controls.R"), warn = FALSE, encoding = "UTF-8")
if (all(same3) && length(F3) == 23L && identical(FS$mc8_label_required, "selection_defense") && any(grepl('"selection_defense"', MCS, fixed = TRUE)) &&
    identical(FS$state_unturned_max_drop_crises, c("2007-10-11 2008-03-17", "2011-05-02 2011-09-26")) &&
    grepl("state_turn_classify.md", FS$state_unturned_max_drop_crises_evidence, fixed = TRUE))
  ok("33 승계 — P2R03 23키 값 · 근거 동일 · mc8 라벨 = matched_controls.R enum · 상태 미전환 최대 하락 위기 2건 = state_turn_classify.md") else
  ng("33", paste(names(F3)[!same3], collapse = ","))

## 34) 칸 목록(23칸) — §10 + 진단(E2 C1~C4 · W1~W4 · N0 · E3 W1~W4) · code · 엔진 · RX0 · 장치 표 · 진단 표 engines · reference · diagnostic · 장치 집합
mkc <- function(en, cp, ref = identical(cp, "RX0"), dg = cp %in% names(P2R04_DIAGNOSTICS)) list(code = paste0("P2R04_", en, "_", cp), engine = en, component = cp, reference = ref, diagnostic = dg)
GOOD <- c(lapply(c("RX0", paste0("H", 1:4), paste0("C", 1:4), paste0("W", 1:4), "N0"), function(cp) mkc("E2", cp)),
          lapply(c("RX0", paste0("H", 1:4), paste0("W", 1:4)), function(cp) mkc("E3", cp)))
B_code <- GOOD; B_code[[2]]$code <- "P2R04_E3_H1"
B_unk <- c(GOOD, list(mkc("E2", "H5")))
B_ref <- GOOD; B_ref[[1]]$reference <- FALSE
B_set <- GOOD[-5]
B_eng <- c(GOOD, list(mkc("E4", "RX0"), mkc("E4", "H1")))
B_rx <- c(GOOD, list(list(code = "P2R04_E2_RX0b", engine = "E2", component = "RX0", reference = TRUE)))
B_c3 <- c(GOOD, list(mkc("E3", "C1")))
B_dg <- GOOD; B_dg[[7]]$diagnostic <- FALSE
if (length(GOOD) == 23L && !length(p2_cells_check(GOOD)) && any(grepl("code ≠", p2_cells_check(B_code))) && any(grepl("H5", p2_cells_check(B_unk))) &&
    any(grepl("reference", p2_cells_check(B_ref))) && any(grepl("장치 집합", p2_cells_check(B_set))) && any(grepl("판정 엔진 3개", p2_cells_check(B_eng))) &&
    any(grepl("E2 RX0 2칸", p2_cells_check(B_rx))) && any(grepl("진단 표 engines 밖", p2_cells_check(B_c3))) && any(grepl("diagnostic", p2_cells_check(B_dg))))
  ok("34 칸 목록 — 23칸 통과 · code · 표 밖 부품 · reference · 장치 집합 · 엔진 수 · RX0 2칸 · E3 결측 짝(engines 밖) · diagnostic 표식 각각 검출") else ng("34")

## 35) 보는 창 가림 — 시험 창 · 전 구간 항목 제거 · τ_D 이후 날짜(YYYY-MM-DD · YYYY-MM) 가림 · τ 이전 그대로 · 원본 무변경 · dp_scan_dates(다른 구현) 0
XV <- list(alpha_test_window = list(t = 1), tbl = data.table(a = 1), cell_log_full_period = list(variant = list(months = 322L)),
           trim = list(variant = list(start = as.Date("2005-03-02"), n_pr = 4000L), rx0 = list(start = as.Date("2005-03-02"), n_pr = 4000L)),
           why = "공통 창 실패: start 2023-05-02 이후", window = "common_from_2005-03-02", rules = list(x = 1, ym = c("2022-12", "2023-01")),
           table = data.table(k = c("2008-05-16 2008-10-24", "2023-02-01 2023-03-01"), v = 1:2))
VO <- p2_visible_only(XV, TAU)
if (is.null(VO$alpha_test_window) && is.null(VO$tbl) && is.null(VO$cell_log_full_period) && is.null(VO$trim$variant$n_pr) && identical(VO$trim$variant$start, as.Date("2005-03-02")) &&
    !grepl("2023-05-02", VO$why) && grepl(P2R04_REDACT, VO$why, fixed = TRUE) && identical(VO$window, "common_from_2005-03-02") &&
    identical(VO$rules$ym, c("2022-12", P2R04_REDACT)) && identical(VO$table$k[1], "2008-05-16 2008-10-24") && grepl(P2R04_REDACT, VO$table$k[2], fixed = TRUE) &&
    identical(XV$table$k[2], "2023-02-01 2023-03-01") && !length(dp_scan_dates(VO, TAU)) && length(dp_scan_dates(XV, TAU)) > 0L)
  ok("35 보는 창 — 시험 창 알파 · 표 행 · 셀 로그 셈 · 사본 행 수 제거 · τ 뒤 날짜 가림(문자열 · 연월 · 표 열) · τ 이전 그대로 · 원본 무변경 · 전수 검사 0") else ng("35")

## 36) 판정 1칸 조기 미시험 경로(합성 산출물 · 계약 호출 없음) — 판정: 상태 · 장치 표 · 사양 · 변형 로그 · 실효 시작 · 무처치 · ⑩ 통과 후 패킷 없음 ·
##     예기치 않은 오류 / 진단: 보유 같음이어도 계속(무처치 아님) · 혼합 가중 불일치 · 희석 짝 null_perm 해석
STR <- file.path(TMP, "p2r04_stub"); unlink(STR, recursive = TRUE); dir.create(file.path(STR, "specs"), recursive = TRUE); RS2 <- file.path(STR, "results"); dir.create(RS2)
writeLines(toJSON(list(code = "R", factors = list(), base_weight = 0.5), auto_unbox = TRUE), file.path(STR, "specs/R.json"))
writeLines(toJSON(list(code = "V", factors = list(list(kind = "db", id = "D03_RealVol")), base_weight = 0.5), auto_unbox = TRUE), file.path(STR, "specs/V.json"))
writeLines(toJSON(list(code = "VW", factors = list(list(kind = "db", id = "D03_RealVol")), base_weight = 0.875), auto_unbox = TRUE), file.path(STR, "specs/VW.json"))
writeLines(toJSON(list(code = "VN", factors = list(list(kind = "null_perm", id = "null_perm_s7", seed = 7L)), base_weight = 0.5), auto_unbox = TRUE), file.path(STR, "specs/VN.json"))
writeLines(ln("R", "none"), file.path(RS2, "R.log")); writeLines(ln("VX", "none"), file.path(RS2, "VX.log"))
for (cd in c("V", "VI", "VD", "VS", "DI", "DW", "DM")) writeLines(ln(cd, "D03_RealVol"), file.path(RS2, paste0(cd, ".log")))
writeLines(ln("DN", "null_perm_s7"), file.path(RS2, "DN.log"))
art <- function(nm, H) { p <- file.path(STR, nm); dir.create(p, showWarnings = FALSE); fwrite(H[, .(date, ticker, target_weight = w)], file.path(p, "04_holdings.csv")); p }
A_R <- art("A_R", H_R); A_I <- art("A_I", copy(H_R)); A_D <- art("A_D", H_S)
ES <- list(status = "ok", date = "2005-01-31")
evd <- function(a, es = ES) list(status = "evaluated", artifacts = a, effective_start = es)
X0 <- list(root = STR, res = RS2, out = RS2, env = list(E = list(ta_resolve_artifact = function(d) list(dir = d))), fs = FS, tau = TAU, ea = new.env())
cR <- list(code = "R", path = "specs/R.json"); cv <- function(code, sp = "specs/V.json") list(code = code, path = sp)
u_a <- p2_eval_pair_safe(X0, "E2", "H2", cv("V"), cR, list(status = "measure_failed"), evd(A_R))
u_b <- p2_eval_pair_safe(X0, "E2", "H9", cv("V"), cR, evd(A_D), evd(A_R))
u_c <- p2_eval_pair_safe(X0, "E2", "H1", cv("V"), cR, evd(A_D), evd(A_R))
u_d <- p2_eval_pair_safe(X0, "E2", "H2", cv("VX"), cR, evd(A_D), evd(A_R))
u_e <- p2_eval_pair_safe(X0, "E2", "H2", cv("VI"), cR, evd(A_I), evd(A_R))
u_f <- p2_eval_pair_safe(X0, "E2", "H2", cv("VD"), cR, evd(A_D), evd(A_R))
u_g <- p2_eval_pair_safe(X0, "E2", "H2", cv("VS"), cR, evd(A_D, list(status = "insufficient", date = NA)), evd(A_R))
XB <- X0; XB$env <- list(E = list())                                            # ta_resolve_artifact 없음 → 예기치 않은 오류(modifyList 는 빈 목록으로 지우지 못한다)
u_h <- p2_eval_pair_safe(XB, "E2", "H2", cv("VD"), cR, evd(A_D), evd(A_R))
d_i <- p2_eval_pair_safe(X0, "E2", "W2", cv("DI", "specs/VW.json"), cR, evd(A_I), evd(A_R), opts = list(role = "diagnostic", expect_weight = 0.125))
d_w <- p2_eval_pair_safe(X0, "E2", "W2", cv("DW"), cR, evd(A_D), evd(A_R), opts = list(role = "diagnostic", expect_weight = 0.125))
d_n <- p2_eval_pair_safe(X0, "E2", "N0", cv("DN", "specs/VN.json"), cR, evd(A_D), evd(A_R), opts = list(role = "diagnostic", expect_weight = 0.5))
d_m <- p2_eval_pair_safe(X0, "E2", "C2", cv("DM"), cR, evd(A_D), evd(A_R), opts = list(role = "diagnostic", expect_weight = 0))
u_p <- p2_eval_pair_safe(X0, "E2", "H2", cv("VD"), cR, evd(A_D), evd(A_R), opts = list(expect_cell_rx0 = "R"))   # expect_cell 만 빠짐(부분 일치 회귀)
U <- list(u_a, u_b, u_c, u_d, u_e, u_f, u_g, u_h, d_i, d_w, d_n, d_m, u_p)
if (all(vapply(U, function(u) !isTRUE(u$tested) && identical(u$verdict, "untested") && identical(u$tbl$tested, FALSE) && identical(u$pass, FALSE), logical(1))) &&
    grepl("평가 상태", u_a$why) && grepl("장치 표에 없는 부품", u_b$why) && grepl("구성 증거", u_c$why) && grepl("사양", u_c$why) &&
    grepl("변형 로그", u_d$why) && grepl("무처치", u_e$why) && identical(u_e$holdings_overlap$n_differ, 0L) &&
    grepl("보는 창 패킷 없음", u_f$why) && identical(u_f$holdings_overlap$n_differ, 1L) && isTRUE(u_f$construction$ok) && identical(u_f$construction$blend$device_weight, 0.5) &&
    grepl("실효 시작", u_g$why) && grepl("평가 오류", u_h$why) &&
    grepl("보는 창 패킷 없음", d_i$why) && identical(d_i$treatment_delivered, FALSE) && isTRUE(d_i$construction$blend$ok) &&
    grepl("혼합 가중 불일치", d_w$why) && grepl("보는 창 패킷 없음", d_n$why) && identical(d_n$device_factor$kind, "null_perm") &&
    grepl("혼합 가중 불일치", d_m$why) && identical(d_m$role, "diagnostic") && grepl("보는 창 패킷 없음", u_p$why) && isTRUE(u_p$construction$ok))
  ok("36 조기 미시험 — 판정 8경로(상태 · 표 밖 · 사양 · 로그 · 무처치 · 패킷 없음 · 실효 시작 · 오류) · 진단: 보유 같아도 계속 · 가중 불일치 2 · null_perm 해석 · opts 부분 일치 없음") else
  ng("36", paste(vapply(U, function(u) u$why %||% "-", ""), collapse = " / "))

## 38) 크기 × β 짝 계획 · 판정 부분(C-017) — k < 1 축소 · k ≥ 1 바스켓 그대로(차입 없음) · 비유한 · 바스켓 β ≤ 0 = 미측정 · 깊은 위기 과반
z1 <- p2_size_beta_plan(0.8, 1); z2 <- p2_size_beta_plan(1.2, 1); z3 <- p2_size_beta_plan(NA, 1); z4 <- p2_size_beta_plan(1, 0)
CRC <- J(copy(CR3)[, dd_capture := c(0.70, 0.80, 0.85)])
sbc <- p2_size_beta_core(crm, CRC, dk, 0.03, 0.5); sbc1 <- p2_size_beta_core(crm, CRC, dk[1], 0.03, 0.5)
if (identical(z1$mode, "scaled") && isTRUE(abs(z1$scale - 0.8) < 1e-12) && identical(z2$mode, "basket") && identical(z2$scale, 1) && identical(z3$mode, "unmeasured") &&
    is.na(z3$scale) && identical(z4$mode, "unmeasured") && isTRUE(sbc$ok) && identical(sbc$n_pair, 2L) && identical(sbc1$ok, FALSE) && identical(sbc1$status_pairs, "unmeasured(짝 < 2)"))
  ok("38 크기 × β — k 0.8 축소 · 1.2 = 바스켓 그대로(차입 없음) · NA · β 0 = 미측정 · 깊은 위기 2/2(0.60 < 0.67 · 0.70 < 0.82) 통과 · 짝 1 = 미측정") else ng("38")

## 39) 시장 대비 기준점(C-024) — dd_capture < 1 − tol 비율 · 깊은 위기 부분 · 열 없음 = 0
crm_m <- J(copy(CR3)[, `:=`(dd_capture = c(0.60, 0.98, 0.70), bm_dd = c(-0.49, -0.27, -0.35))])
vm <- p2_vs_market(crm_m, 0.03); vmd <- p2_vs_market(crm_m, 0.03, dk); vm0 <- p2_vs_market(J(data.table(peak_date = "2008-05-16", trough_date = "2008-10-24")), 0.03)
if (identical(vm$n, 3L) && identical(vm$n_better, 2L) && isTRUE(abs(vm$share - 2/3) < 1e-12) && identical(vmd$n, 2L) && identical(vmd$share, 1) && identical(vm0$n, 0L) && is.na(vm0$share))
  ok("39 시장 기준점 — 0.60 · 0.70 < 0.97 · 0.98 아님 → 2/3 · 깊은 위기 2/2 · 열 없음 = 0") else ng("39", paste(vm$n_better, vm$share))

## 40) 국면별 월 차이 — 위기 월 우선 → 강세 월 → 그 밖 · 평균
YM <- format(seq(as.Date("2008-01-01"), by = "month", length.out = 12), "%Y-%m"); DF <- c(0.01, 0.01, 0.01, -0.02, -0.02, -0.02, 0.03, 0.03, 0, 0, 0, 0.005)
rg <- p2_regime_diff(YM, DF, J(data.table(peak_date = "2008-04-10", trough_date = "2008-06-20")), J(data.table(start_ym = c("2008-06", "2008-07"), end_ym = c("2008-06", "2008-08"))))
if (identical(rg$n_months, 12L) && identical(rg$crisis$n, 3L) && isTRUE(abs(rg$crisis$mean + 0.02) < 1e-12) && identical(rg$bull$n, 2L) && isTRUE(abs(rg$bull$mean - 0.03) < 1e-12) &&
    identical(rg$other$n, 7L) && isTRUE(abs(rg$other$mean - 0.035 / 7) < 1e-12))
  ok("40 국면 월 — 위기 4~6월 3개(6월 강세와 겹치면 위기 우선) −0.02 · 강세 7 · 8월 +0.03 · 그 밖 7개") else ng("40", paste(rg$crisis$n, rg$bull$n, rg$other$n))

## 41) RX0 동일성(C-025) — 같음 · 하루 수익 다름 = 다른 달 1 · 보유 다름 · τ 뒤 차이 안 셈
PRa <- data.table(date = seq(as.Date("2010-01-04"), by = "day", length.out = 70), ret_net = 0.001); PRb <- copy(PRa); PRb[10, ret_net := 0.002]
PRc <- rbind(PRa, data.table(date = as.Date("2023-01-03"), ret_net = 0.1)); PRd <- rbind(PRa, data.table(date = as.Date("2023-01-03"), ret_net = 0.2))
i_s <- p2_rx0_identity_core(H_R, H_R, PRa, PRa, TAU); i_r <- p2_rx0_identity_core(H_R, H_R, PRb, PRa, TAU); i_h <- p2_rx0_identity_core(H_S, H_R, PRa, PRa, TAU)
i_t <- p2_rx0_identity_core(H_T, H_R, PRc, PRd, TAU)
if (isTRUE(i_s$holdings_same) && isTRUE(i_s$returns_same) && identical(i_s$months_differ, 0L) && identical(i_r$returns_same, FALSE) && identical(i_r$months_differ, 1L) &&
    identical(i_h$holdings_same, FALSE) && identical(i_h$holdings_dates_differ, 1L) && isTRUE(i_h$returns_same) && isTRUE(i_t$holdings_same) && isTRUE(i_t$returns_same))
  ok("41 RX0 동일성 — 같음 · 하루 수익 다름 = 다른 달 1 · 보유 교체 1 · τ 뒤 보유 · 수익 차이는 안 셈") else ng("41")

## 42) 유동성 분위(C-020) — 10분위(진단 패킷 크기 분위와 같은 경계 규약) · 유니버스 10 미만 = NA · 비유한 = NA
uv <- 1:100; lq <- p2_liq_deciles(c(1, 50, 100, NA), uv)
if (identical(lq, c(1L, 5L, 10L, NA)) && all(is.na(p2_liq_deciles(c(1, 2), 1:9)))) ok("42 유동성 분위 — 1 → 1 · 50 → 5 · 100 → 10 · NA · 유니버스 9 = NA") else ng("42", paste(lq))

## 43) 결론 이름(DESIGN §8.2 + C-017) — ③④ 미통과 · ③④ NA = 보류 · ⑤ 역행 · ⑤ NA = 보류 · ⑭ 미측정 = 보류 · ⑭ 미통과 · 크기 × β 미측정 · 미통과 · 통과
if (grepl("방어 이름 없음", p2_defense_name(FALSE, TRUE, TRUE, TRUE, TRUE, "ok")) && identical(p2_defense_name(NA, TRUE, TRUE, TRUE, TRUE, "ok"), "방어 이름 보류(③ · ④ β 짝 미측정)") &&
    identical(p2_defense_name(TRUE, NA, TRUE, TRUE, TRUE, "ok"), "방어 이름 보류(③ · ④ β 짝 미측정)") && grepl("⑤ 수준 미측정", p2_defense_name(TRUE, TRUE, NA, TRUE, TRUE, "ok")) &&
    grepl("노출\\(β\\) 방어", p2_defense_name(TRUE, TRUE, FALSE, TRUE, TRUE, "ok")) &&
    identical(p2_defense_name(TRUE, TRUE, TRUE, FALSE, TRUE, "ok", s14_measured = FALSE), "방어 이름 보류(⑭ 선택 귀속 미측정)") &&
    grepl("크기 방어 또는 노출 방어", p2_defense_name(TRUE, TRUE, TRUE, FALSE, TRUE, "ok")) && grepl("미측정", p2_defense_name(TRUE, TRUE, TRUE, TRUE, NA, "unmeasured")) &&
    grepl("크기 × β 방어", p2_defense_name(TRUE, TRUE, TRUE, TRUE, FALSE, "ok")) && identical(p2_defense_name(TRUE, TRUE, TRUE, TRUE, TRUE, "ok"), "선택(특성) 방어"))
  ok("43 결론 이름 — 미통과 · ③④ NA 보류 · ⑤ NA 보류 · β 역행 · ⑭ 미측정 보류 · ⑭ 미통과 · 크기 × β 미측정 · 미통과 · 모두 통과 = '선택(특성) 방어'") else ng("43")

## 44) 진단 읽기 (a) 결측 짝 · (c) 희석 짝 — 위기별 승리 겹침(둘 다 · H 만 · 표에 없음)
pcH <- data.table(k = c("A", "B", "C", "D"), m = c(0.5, 0.5, 0.5, 0.9), r = c(0.6, 0.6, 0.6, 0.8))   # H 승리 A · B · C
pcC <- data.table(k = c("A", "B"), m = c(0.5, 0.7), r = c(0.6, 0.6))                                 # C 승리 A · B 패 · C 표 없음
ow <- p2_read_overlap_wins(pcH, pcC, 0.03)
hX <- list(tested = TRUE, device = "H1", rules = list(beta_deep = list(per_crisis = pcH), crisis = list(per_crisis = pcH)))
cX <- list(tested = TRUE, cell = "P2R04_E2_C1", rules = list(beta_deep = list(per_crisis = pcC), crisis = list(per_crisis = pcC)))
rm1 <- p2_read_missing(hX, cX, 0.03); rd1 <- p2_read_dilution(hX, cX, 0.03); rm0 <- p2_read_missing(hX, list(tested = FALSE, why = "x"), 0.03)
if (identical(ow$n_a, 3L) && identical(ow$both, "A") && identical(ow$a_only, "B") && identical(ow$unknown, "C") && identical(rm1$n_missing_pattern, 1L) &&
    identical(rm1$n_not_missing, 1L) && grepl("결측 패턴 방어 1/3", rm1$tag) && grepl("희석 몫 1/3", rd1$tag) && identical(rm0$status, "unmeasured") &&
    identical(p2_read_overlap_wins(NULL, pcC, 0.03)$status, "unmeasured"))
  ok("44 진단 읽기 — H 승리 3 중 결측 짝도 이김 1(결측 패턴 방어) · H 만 1 · 표에 없음 1 · 희석 몫 1/3 · 짝 미시험 = 미측정") else ng("44")

## 45) 용량 읽기 표(C-018 · R-20261018-004) — 16조합 전부 한 행 · 대표 조합 라벨 · 가중 불일치 · 미시험 = 미측정
lab16 <- unlist(lapply(c(TRUE, FALSE), function(a) lapply(c(TRUE, FALSE), function(b) lapply(c(TRUE, FALSE), function(c0) lapply(c(TRUE, FALSE), function(d0) p2_capacity_label(a, b, c0, d0))))))
cx <- function(tested, pass, w) list(tested = tested, pass = pass, verdict = if (tested) "x" else "untested", construction = list(blend = list(device_weight = w)))
rc_a <- p2_read_capacity(cx(TRUE, TRUE, 0.5), cx(TRUE, FALSE, 0.5), cx(TRUE, FALSE, 0.125), cx(TRUE, FALSE, 0.125))
rc_b <- p2_read_capacity(cx(TRUE, FALSE, 0.5), cx(TRUE, FALSE, 0.5), cx(TRUE, TRUE, 0.125), cx(TRUE, FALSE, 0.125))
rc_c <- p2_read_capacity(cx(TRUE, TRUE, 0.5), cx(TRUE, TRUE, 0.125), cx(TRUE, FALSE, 0.125), cx(TRUE, FALSE, 0.125))
rc_d <- p2_read_capacity(cx(TRUE, TRUE, 0.5), cx(FALSE, FALSE, 0.5), cx(TRUE, FALSE, 0.125), cx(TRUE, FALSE, 0.125))
if (length(lab16) == 16L && !anyNA(lab16) && identical(p2_capacity_label(TRUE, TRUE, FALSE, FALSE), P2R04_CAPACITY_TABLE$label[2]) &&
    grepl("구성 의존\\(E2", rc_a$label) && grepl("과용량 의심", rc_b$label) && grepl("가중 불일치", rc_c$label) && grepl("미시험", rc_d$label) &&
    identical(p2_capacity_label(FALSE, FALSE, FALSE, FALSE), P2R04_CAPACITY_TABLE$label[6]) && grepl("같은 처치 두 구성 통과", p2_capacity_label(TRUE, TRUE, TRUE, FALSE)))
  ok("45 용량 표 — 16조합 각 한 라벨 · 용량 의존(12.5% 들만 미달) · 구성 의존 · 과용량 의심 · 이 형태 미달 · 가중 불일치 · 미시험 = 미측정") else ng("45")

## 46) 진단 칸 장치 · 기대 가중 — C/W = 짝 장치 · N0 = null_perm(seed) · seed 없음 · 표 밖 = NULL · 기대 가중(사양에서 재도출)
dvn <- p2_diag_device("N0", list(list(kind = "null_perm", id = "null_perm_s3", seed = 3L))); dvs <- p2_diag_device("N0", list(list(kind = "null_perm", id = "null_perm_s3")))
SPR <- file.path(TMP, "p2r04_wroot"); unlink(SPR, recursive = TRUE); dir.create(file.path(SPR, "s"), recursive = TRUE)
writeLines(toJSON(list(base_weight = 0.5, factors = SR3), auto_unbox = TRUE), file.path(SPR, "s/E3_RX0.json"))
writeLines(toJSON(list(base_weight = 0.5, factors = fe("D04_Downside_Beta")), auto_unbox = TRUE), file.path(SPR, "s/E2_H1.json"))
WC <- list(list(engine = "E3", component = "RX0", path = "s/E3_RX0.json"), list(engine = "E2", component = "H1", path = "s/E2_H1.json"))
if (identical(p2_diag_device("C3", list())$id, "D07_Beta_Asymmetry") && identical(p2_diag_device("W1", list())$id, "D04_Downside_Beta") && identical(dvn$id, "null_perm_s3") &&
    is.null(dvs) && is.null(p2_diag_device("Z9", list())) && identical(p2_diag_expect_weight("C1", WC, SPR), 0) &&
    identical(p2_diag_expect_weight("W2", WC, SPR), 0.125) && identical(p2_diag_expect_weight("N0", WC, SPR), 0.5) && is.na(p2_diag_expect_weight("W2", WC[2], SPR)))
  ok("46 진단 장치 · 기대 가중 — C3 = D07 · W1 = D04 · N0 = null_perm(seed) · seed 없음 · 표 밖 = NULL · C 0 · W 0.125(E3 RX0 + 1) · N0 0.5(E2 H1) · RX0 없음 = NA") else ng("46")

## 47) A 거리(C-031) — 값 − 문턱 · 충족 · 벤치 Calmar 문턱 · S 경계 · 결측 = 충족 아님
TH <- list(cagr_min = 0.16, sharpe_min = 0.8, port_t_b = 2.0)
ad <- p2_a_distance(list(cagr = 0.12, sharpe = 0.9, calmar = 0.3, port_t = 2.5), 0.25, TH, S = 0.7, a_boundary = 1)
if (isTRUE(abs(ad$cagr$distance + 0.04) < 1e-12) && identical(ad$cagr$meets, FALSE) && isTRUE(ad$sharpe$meets) && isTRUE(ad$calmar$meets) &&
    isTRUE(abs(ad$calmar$distance - 0.05) < 1e-12) && isTRUE(ad$port_t$meets) && identical(ad$S$meets, FALSE) && identical(p2_a_distance(list(), NA, TH)$cagr$meets, FALSE))
  ok("47 A 거리 — CAGR −0.04 미충족 · Sharpe · Calmar(벤치 0.25 대비 +0.05) · PORT_t 충족 · S 0.7 < 1 · 값 없음 = 미충족") else ng("47")

## 48) R7 판독(C-029) — 판정된 장치 = 두 구성 tested ∧ ③ 측정(status ok · 짝 ≥ 2 · 비율 유한) ∧ S 증분 유한 · 판정된 장치 < 2 = 판독 불가(NA) ·
##     아니면 검증 0 ∧ ③ 두 구성 과반 장치 0 ∧ S 증분 최대 < tie_eps(판정된 장치만) — 격리 교차 점검 v1 권고 3 · v2 권고 1 (a)
nx <- function(dv, eng, sh, s, s0, tested = TRUE, st = "ok") list(device = dv, engine = eng, tested = tested,
  rules = list(beta_deep = list(share = if (identical(st, "ok")) sh else NA_real_, status = st, n_pair = if (identical(st, "ok")) 2L else 0L)),
  non_inferiority = list(S = s, S_rx0 = s0))
NO1 <- list(nx("H1", "E2", 0.4, 0.51, 0.5), nx("H1", "E3", 0.6, 0.505, 0.5), nx("H2", "E2", 0.6, 0.49, 0.5), nx("H2", "E3", 0.4, 0.5, 0.5))
NO2 <- list(nx("H1", "E2", 0.6, 0.51, 0.5), nx("H1", "E3", 0.6, 0.505, 0.5), nx("H2", "E2", 0.4, 0.5, 0.5), nx("H2", "E3", 0.4, 0.5, 0.5))
NO3 <- list(nx("H1", "E2", 0.4, 0.6, 0.5), nx("H1", "E3", 0.4, 0.6, 0.5), nx("H2", "E2", 0.4, 0.5, 0.5), nx("H2", "E3", 0.4, 0.5, 0.5))
NO6 <- list(nx("H1", "E2", 0.4, 0.5, 0.5), nx("H1", "E3", 0.4, 0.5, 0.5), nx("H2", "E2", 0.4, 0.5, 0.5, FALSE), nx("H2", "E3", 0.4, 0.5, 0.5))
## 위반(리뷰 재현): 8칸 모두 β 대조 미측정(③ NA) · S 증분 작음 → 예전엔 '잡음 이내(판정 4/4)'로 샜다 → 판독 불가 · 빠진 장치 4(③ 미측정)
NO8 <- unlist(lapply(paste0("H", 1:4), function(h) list(nx(h, "E2", NA, 0.501, 0.5, st = "unmeasured"), nx(h, "E3", NA, 0.5, 0.5, st = "unmeasured(짝 < 2)"))), recursive = FALSE)
## 섞임: H1~H3 측정(작은 S 증분) · H4 는 E3 ③ 미측정에 큰 S 증분 → H4 빠짐(그 증분은 셈에 안 듦) → 판정된 장치 3/4 · 잡음 이내
NO7 <- c(NO1, list(nx("H3", "E2", 0.3, 0.5, 0.5), nx("H3", "E3", 0.3, 0.505, 0.5), nx("H4", "E2", 0.4, 1.0, 0.5), nx("H4", "E3", NA, 1.0, 0.5, st = "unmeasured(짝 < 2)")))
nr1 <- p2_noise_reading(NO1, character(0), 0.02, 0.5, c("H1", "H2")); nr2 <- p2_noise_reading(NO2, character(0), 0.02, 0.5, c("H1", "H2"))
nr3 <- p2_noise_reading(NO3, character(0), 0.02, 0.5, c("H1", "H2")); nr4 <- p2_noise_reading(NO1, "H1", 0.02, 0.5, c("H1", "H2"))
nr5 <- p2_noise_reading(list(nx("H1", "E2", 0.4, 0.5, 0.5, FALSE)), character(0), 0.02, 0.5, "H1")
nr6 <- p2_noise_reading(NO6, character(0), 0.02, 0.5, c("H1", "H2", "H3", "H4"))
nr8 <- p2_noise_reading(NO8, character(0), 0.02, 0.5, paste0("H", 1:4)); nr7 <- p2_noise_reading(NO7, character(0), 0.02, 0.5, paste0("H", 1:4))
drop_why <- function(nr, h) { z <- Filter(function(d) identical(d$device, h), nr$dropped); if (length(z)) z[[1]]$why else NA_character_ }
if (isTRUE(nr1$result) && identical(nr1$label, "잡음 이내") && identical(nr1$judged_devices, "2/2") && isTRUE(abs(nr1$max_dS - 0.0075) < 1e-12) && !length(nr1$dropped) &&
    identical(nr2$result, FALSE) && identical(nr2$n_device_r3_both, 1L) && identical(nr2$label, "잡음 밖") && identical(nr3$result, FALSE) &&
    identical(nr3$components$max_dS_below_tie, FALSE) && identical(nr4$result, FALSE) && is.na(nr5$result) && is.na(nr6$result) &&
    identical(nr6$judged_devices, "1/4") && grepl("판독 불가", nr6$label) && identical(drop_why(nr6, "H2"), "미시험 구성 있음"))
  ok("48 R7 — 잡음 이내(2/2 · 최대 S 증분 0.0075) · ③ 두 구성 과반 장치 1 · S 증분 0.1 · 검증 1 = 잡음 밖 · 판정된 장치 1/4 = 판독 불가(H2 미시험 · 이유 기록) · 없음 = NA") else ng("48")

## 53) R7 ③ 측정 조건(격리 교차 점검 v2 권고 1 (a)) — 위반: 8칸 모두 β 대조 미측정 = 판독 불가 0/4(리뷰 재현 — 예전엔 '잡음 이내') ·
##     양성: ③ 측정 장치 3개 ≥ 2 → 판독 · ③ 미측정 구성이 있는 H4 는 빠지고 그 큰 S 증분은 셈에 안 든다
if (is.na(nr8$result) && identical(nr8$judged_devices, "0/4") && grepl("판독 불가", nr8$label) && length(nr8$dropped) == 4L &&
    all(vapply(nr8$dropped, function(d) grepl("③ 미측정", d$why), logical(1))) &&
    isTRUE(nr7$result) && identical(nr7$label, "잡음 이내") && identical(nr7$judged_devices, "3/4") && identical(nr7$judged, c("H1", "H2", "H3")) &&
    grepl("③ 미측정", drop_why(nr7, "H4")) && isTRUE(abs(nr7$max_dS - 0.0075) < 1e-12))
  ok("53 R7 ③ 측정 — 8칸 β 대조 미측정 = 판독 불가(0/4 · 빠진 장치 4 · ③ 미측정) · 섞임 = 판정된 장치 3/4(H4 ③ 미측정 빠짐 · 큰 S 증분 불산입) · 잡음 이내") else
  ng("53", paste(format(nr8$result), nr8$judged_devices, format(nr7$result), nr7$judged_devices))

## 49) 진단 읽기 묶음 — OUT · DOUT 에서 장치마다 결측 · 용량(E2 · E3 장치 · 용량 짝) · 희석(N0) 을 찾는다
pc_ <- function(k, m, r) data.table(k = k, m = m, r = r)
oc <- function(eng, dev, pass, w, pc) list(engine = eng, device = dev, tested = TRUE, pass = pass, verdict = "v", cell = paste0(eng, dev),
                                         construction = list(blend = list(device_weight = w)), rules = list(beta_deep = list(per_crisis = pc), crisis = list(per_crisis = pc)))
OUTr <- list(oc("E2", "H1", TRUE, 0.5, pcH), oc("E3", "H1", FALSE, 0.5, pcH))
DOUTr <- list(oc("E2", "C1", FALSE, 0, pcC), oc("E2", "W1", FALSE, 0.125, pcC), oc("E3", "W1", FALSE, 0.125, pcC), oc("E2", "N0", FALSE, 0.5, pcC))
RR <- p2_readings(OUTr, DOUTr, 0.03, "H1")
if (identical(RR$other_engine, "E3") && identical(RR$missing$H1$n_missing_pattern, 1L) && grepl("구성 의존\\(E2", RR$capacity$H1$label) &&
    identical(RR$dilution$by_device$H1$n_dilution, 1L) && isTRUE(RR$dilution$n0$tested))
  ok("49 읽기 묶음 — 다른 엔진 E3 · 결측 패턴 1 · 용량 '구성 의존(E2 …)' · 희석 몫 1 · N0 요약") else ng("49", RR$capacity$H1$label)

## 50) 라운드 판정 라벨의 판정어별 칸 수(격리 교차 점검 v1 권고 2) — 8칸 모두 β 짝 미측정 = 'falsified(판정 8/8 · β 짝 미측정 8)' · 섞이면 어휘 순서대로 · verdict 열 없으면 예전 라벨
TB8 <- data.table(engine = rep(c("E2", "E3"), each = 4), device = rep(paste0("H", 1:4), 2), tested = TRUE, pass = FALSE, excluded = FALSE, verdict = "beta_unmeasured")
TBm <- copy(TB8)[1:3, verdict := c("exposure_only", "selection_unmeasured", "exposure_only")][8, `:=`(tested = FALSE, verdict = "untested")]
v8 <- p2_round_verdict(TB8); vm <- p2_round_verdict(TBm)
if (identical(v8$label, "falsified(판정 8/8 · β 짝 미측정 8)") && identical(vm$label, "falsified(판정 7/8 · 노출 방어 2 · ⑭ 미측정 1 · β 짝 미측정 4 · 미시험 1)") &&
    identical(p2_round_verdict(T1)$label, "supported(판정 4/4)") && identical(v8$verdict_counts, "β 짝 미측정 8"))
  ok("50 라운드 라벨 — 'falsified(판정 8/8 · β 짝 미측정 8)' · 혼합 = 어휘 순서 칸 수(노출 방어 2 · ⑭ 미측정 1 · β 짝 미측정 4 · 미시험 1) · verdict 열 없음 = 예전 라벨") else
  ng("50", paste(v8$label, vm$label, sep = " / "))

## 51) 보는 창 밖 작업 사본 표식(격리 교차 점검 v1 권고 7) — 공통 창 사본 · β 짝 사본 폴더에 NO_VISIBLE_REVIEW.txt(칸 평가 full/ 와 같은 첫 줄 문구) · 상위 폴더 표식 줄
mk_out <- readLines(file.path(out, "NO_VISIBLE_REVIEW.txt"), warn = FALSE, encoding = "UTF-8"); mk_bout <- readLines(file.path(bout, "NO_VISIBLE_REVIEW.txt"), warn = FALSE, encoding = "UTF-8")
PMK <- file.path(TMP, "p2r04_mark_parent"); unlink(PMK, recursive = TRUE); .p2_mark_full(PMK, P2R04_FULL_MARK_PARENT)
mk_p <- readLines(file.path(PMK, "NO_VISIBLE_REVIEW.txt"), warn = FALSE, encoding = "UTF-8")
if (identical(mk_out, P2R04_FULL_AUDIENCE) && identical(mk_bout, P2R04_FULL_AUDIENCE) && identical(mk_p, c(P2R04_FULL_AUDIENCE, P2R04_FULL_MARK_PARENT)) &&
    grepl("visible\\*", P2R04_FULL_MARK_PARENT))
  ok("51 표식 — 공통 창 사본 · β 짝 사본 = 칸 평가 full/ 문구 · 상위 폴더 = 문구 + 'visible* 만 보는 창' 줄") else ng("51")

## 52) 구성 몫 · 비(격리 교차 점검 v1 권고 6) — E3 장치 칸(0.25 · 9 · 6) DNN : 기존 = 1:1 · E3 용량 짝(0.5 · 4 · 1) = 4:3 · E2 = 기존 팩터 없음 · 용량 읽기 주석
bh <- p2_blend_weight(0.25, 9L, 6L); bw <- p2_blend_weight(0.5, 4L, 1L); be <- p2_blend_weight(0.875, 1L, 1L)
cb <- function(b, pass = FALSE) list(tested = TRUE, pass = pass, verdict = "x", construction = list(blend = b))
rcn <- p2_read_capacity(cb(p2_blend_weight(0.5, 1L, 1L)), cb(bh), cb(be), cb(bw))
if (isTRUE(abs(bh$dnn_share - 0.25) < 1e-12) && isTRUE(abs(bh$other_share - 0.25) < 1e-12) && isTRUE(abs(bh$dnn_share + bh$other_share + bh$device_weight - 1) < 1e-12) &&
    identical(p2_ratio_str(bh$dnn_share, bh$other_share), "1:1") && identical(p2_ratio_str(bw$dnn_share, bw$other_share), "4:3") &&
    identical(p2_ratio_str(be$dnn_share, be$other_share), "기존 팩터 없음") && is.na(p2_ratio_str(NA, 1)) &&
    identical(rcn$composition_note, "E3 용량 짝 W 는 방어 몫 외에 DNN : 기존 팩터 비율도 1:1 → 4:3 로 바뀐다(구성 차이 혼재 — 용량 읽기는 이 차이를 함께 읽는다)"))
  ok("52 구성 — E3 장치 칸 1:1(DNN 0.25 · 기존 0.25 · 방어 0.5) · E3 용량 짝 4:3 · E2 = 기존 팩터 없음 · 용량 읽기 주석 '1:1 → 4:3'") else ng("52", rcn$composition_note %||% "NA")

## 37) 뮤테이션 — 소스 텍스트 치환(치환 대상이 정확히 1줄 · 사본 단독 적재 · 사본이 본 실행 블록을 돌리지 않음)이 각각 위 검사 하나를 깨는가
SRC <- readLines(EVF, warn = FALSE, encoding = "UTF-8")
mutant <- function(from, to) {
  hit <- sum(grepl(from, SRC, fixed = TRUE)); if (hit != 1L) return(list(err = sprintf("치환 대상 %d줄(1줄이어야 함): %s", hit, from)))
  MS <- sub(from, to, SRC, fixed = TRUE)
  if (identical(MS, SRC) || sum(MS != SRC) != 1L) return(list(err = paste("치환 불성사:", from)))
  p <- gsub("\\\\", "/", tempfile("p2r04_mut_", tmpdir = TMP, fileext = ".R")); writeLines(MS, p, useBytes = TRUE)
  e <- new.env(); r0 <- tryCatch({ sys.source(p, envir = e, keep.source = FALSE); NULL }, error = function(z) conditionMessage(z))
  if (!is.null(r0)) return(list(err = paste("사본 적재 실패:", r0))); if (exists("EVS", envir = e, inherits = FALSE)) return(list(err = "사본이 본 실행 블록을 돌렸다"))
  list(env = e)
}
FL_NOSEL <- FL; FL_NOSEL$selection <- FALSE
MU <- list(
  list(nm = "과반 > → >=", from = "is.finite(s) && is.finite(m) && s > m }", to = "is.finite(s) && is.finite(m) && s >= m }",
       kill = function(e) isTRUE(e$p2_maj(0.5, 0.5))),
  list(nm = "⑭ 요구 제거(칸 통과)", from = "isTRUE(f$path) && isTRUE(f$selection)", to = "isTRUE(f$path)",
       kill = function(e) isTRUE(e$p2_cell_pass(FL_NOSEL))),
  list(nm = "⑭ 위기 분해 요구 제거", from = "ok = isTRUE(attr$ok) && isTRUE(decomp$ok)))", to = "ok = isTRUE(attr$ok)))",
       kill = function(e) isTRUE(e$p2_selection_rule(s_a, sd_na)$ok)),
  list(nm = "β 짝 k ≥ 1 분기 제거", from = 'else if (k >= 1) "rx0" else "scaled"', to = 'else "scaled"',
       kill = function(e) !identical(e$p2_beta_plan(1.2, 1)$mode, "rx0")),
  list(nm = "크기 × β 바스켓 차입", from = 'scale = if (identical(mode, "unmeasured")) NA_real_ else min(k, 1)', to = 'scale = if (identical(mode, "unmeasured")) NA_real_ else k',
       kill = function(e) !identical(e$p2_size_beta_plan(1.2, 1)$scale, 1)),
  list(nm = "⑩ 무처치 검사 제거", from = 'identical(ov$status, "ok") && isTRUE(ov$n_differ > 0L)', to = 'identical(ov$status, "ok")',
       kill = function(e) isTRUE(e$p2_treatment_delivered(o_i))),
  list(nm = "판정 칸도 무처치 통과(역할 무시)", from = '(!diag || !identical(ov$status, "ok"))', to = '(!identical(ov$status, "ok"))',
       kill = function(e) !grepl("무처치", e$p2_eval_pair_safe(X0, "E2", "H2", cv("VI"), cR, evd(A_I), evd(A_R))$why)),
  list(nm = "opts 부분 일치 회귀($expect_cell)", from = 'opts[["expect_cell"]] %||% cm$code', to = 'opts$expect_cell %||% cm$code',
       kill = function(e) !isTRUE(e$p2_eval_pair_safe(X0, "E2", "H2", cv("VD"), cR, evd(A_D), evd(A_R), opts = list(expect_cell_rx0 = "R"))$construction$ok)),
  list(nm = "진단 표 부분 일치 회귀($weight)", from = 'if (!is.null(dg[["weight"]])) return(as.numeric(dg[["weight"]]))', to = 'if (!is.null(dg$weight)) return(as.numeric(dg$weight))',
       kill = function(e) !identical(suppressWarnings(e$p2_diag_expect_weight("W2", WC, SPR)), 0.125)),
  list(nm = "진단 칸 혼합 가중 대조 제거", from = "if (diag && !isTRUE(cs$blend$ok))", to = "if (FALSE)",
       kill = function(e) !grepl("혼합 가중 불일치", e$p2_eval_pair_safe(X0, "E2", "W2", cv("DW"), cR, evd(A_D), evd(A_R), opts = list(role = "diagnostic", expect_weight = 0.125))$why)),
  list(nm = "장치 꼬리 반복을 1회로", from = "if (isTRUE(r$values[1])) r$lengths[1] else 0L", to = "if (isTRUE(r$values[1])) 1L else 0L",
       kill = function(e) !isTRUE(e$p2_construction_check(p2_parse_cell_log(LG_E3_H1), p2_parse_cell_log(LG_E3_0), P2R04_DEVICES$H1,
                                                          c(SR3, fe(rep("D04_Downside_Beta", 6))), SR3, "P2R04_E3_H1", "P2R04_E3_RX0")$ok)),
  list(nm = "두 엔진 조건 제거", from = "both <- agg[n_pass == 2L & !ex, device]", to = "both <- agg[n_pass >= 1L & !ex, device]",
       kill = function(e) !identical(e$p2_round_verdict(T1)$both, "H1")),
  list(nm = "집중 문턱 부호", from = "n_breach = sum(deep$top1 < floor)", to = "n_breach = sum(deep$top1 > floor)",
       kill = function(e) !identical(e$p2_conc_status(e$p2_top_loss(tl2, "2020-01-22", -0.10)), "clear")),
  list(nm = "⑩ 변형 로그 대조 제거", from = "okV <- isTRUE(lv$found) && identical(lv$cell, expect_cell) && identical(lv$factors, sid_v)", to = "okV <- TRUE",
       kill = function(e) isTRUE(e$p2_construction_check(p2_parse_cell_log(ln("P2R04_E2_H2", "none")), p2_parse_cell_log(LG_E2_0), P2R04_DEVICES$H2,
                                                         fe("D03_RealVol"), list(), "P2R04_E2_H2", "P2R04_E2_RX0")$ok)),
  list(nm = "⑩ RX0 로그 대조 제거", from = "okR <- isTRUE(lr$found) && identical(lr$cell, expect_cell_rx0) && identical(lr$factors, base_v)", to = "okR <- TRUE",
       kill = function(e) isTRUE(e$p2_construction_check(p2_parse_cell_log(LG_E2_H2), p2_parse_cell_log(ln("P2R04_E2_RX0", "D03_RealVol")), P2R04_DEVICES$H2,
                                                         fe("D03_RealVol"), list(), "P2R04_E2_H2", "P2R04_E2_RX0")$ok)),
  list(nm = "보유 다름을 이름 집합만으로", from = "differ = !setequal(a$ticker, b$ticker) || any(wa != wb))", to = "differ = !setequal(a$ticker, b$ticker))",
       kill = function(e) identical(e$p2_holdings_overlap(H_W, H_R, TAU)$n_differ, 0L)),
  list(nm = "size_or_exposure_defense 분기 제거", from = 'if (isTRUE(r3) && isTRUE(r4) && !s14) "size_or_exposure_defense" else', to = 'if (FALSE) "size_or_exposure_defense" else',
       kill = function(e) !identical(e$p2_cell_verdict(list(pass = FALSE, beta_unmeasured = FALSE, beta_deep = TRUE, fast = TRUE, crisis = FALSE, deep = FALSE, selection = FALSE,
                                                            selection_measured = TRUE)), "size_or_exposure_defense")),
  list(nm = "selection_unmeasured 분기 제거", from = 'if (isTRUE(r3) && isTRUE(r4) && !m14) "selection_unmeasured" else', to = 'if (FALSE) "selection_unmeasured" else',
       kill = function(e) !identical(e$p2_cell_verdict(list(pass = FALSE, beta_unmeasured = FALSE, beta_deep = TRUE, fast = TRUE, crisis = FALSE, deep = FALSE, selection = FALSE,
                                                            selection_measured = FALSE)), "selection_unmeasured")),
  list(nm = "⑭ 분해 부등호 > → >=", from = "J[, better := sv - sr > 0]", to = "J[, better := sv - sr >= 0]",
       kill = function(e) !identical(e$p2_selection_decomp(J(data.table(peak_date = PK4, trough_date = TR4, selection_sum = -0.10)), ERX, PK4, 0.5)$ok, FALSE)),
  list(nm = "⑭ 분해에 문턱 0.03 재도입", from = "J[, better := sv - sr > 0]", to = "J[, better := sv - sr > 0.03]",
       kill = function(e) !isTRUE(e$p2_selection_decomp(J(data.table(peak_date = PK4, trough_date = TR4, selection_sum = -0.10 + c(0.015, 0.020, 0.060, -0.010))), ERX, PK4, 0.5)$ok)),
  list(nm = "MC8 insufficient 를 측정으로", from = 'else if (is.na(lb) || !(lb %in% P2R04_MC8_LABELS)) "unmeasured" else "ok"', to = 'else if (is.na(lb)) "unmeasured" else "ok"',
       kill = function(e) !identical(e$p2_selection_attr("insufficient", "selection_defense")$status, "unmeasured")),
  list(nm = "결론 이름 ③ · ④ NA 보류 제거", from = 'if (is.na(r3 %||% NA) || is.na(r4 %||% NA)) return("방어 이름 보류(③ · ④ β 짝 미측정)")',
       to = 'if (FALSE) return("방어 이름 보류(③ · ④ β 짝 미측정)")', kill = function(e) !grepl("보류", e$p2_defense_name(NA, TRUE, TRUE, TRUE, TRUE, "ok"))),
  list(nm = "R7 ③ 측정 조건 제거(잡음 이내로 샌다)", from = 'r3m <- tst & st3 %in% "ok" & !is.na(np3) & np3 >= 2L & is.finite(sh3)', to = "r3m <- tst",
       kill = function(e) isTRUE(e$p2_noise_reading(NO8, character(0), 0.02, 0.5, paste0("H", 1:4))$result)),
  list(nm = "R7 판독 불가 규칙 제거", from = "readable <- nb >= 2L", to = "readable <- TRUE",
       kill = function(e) !is.na(e$p2_noise_reading(NO6, character(0), 0.02, 0.5, c("H1", "H2", "H3", "H4"))$result)),
  list(nm = "β 짝 사본 표식 제거", from = ".p2_mark_full(dir = out_dir)", to = "invisible(NULL)",
       kill = function(e) { od <- file.path(TMP, "p2r04_mut_bout"); unlink(od, recursive = TRUE); e$p2_beta_scaled_copy(bsrc, od, 0.8); !file.exists(file.path(od, "NO_VISIBLE_REVIEW.txt")) }),
  list(nm = "결론 이름 크기 × β 무시", from = "if (!isTRUE(sb_ok)) return(", to = "if (FALSE) return(",
       kill = function(e) identical(e$p2_defense_name(TRUE, TRUE, TRUE, TRUE, FALSE, "ok"), "선택(특성) 방어")),
  list(nm = "결측 짝 승리 비교 부등호", from = "D[is.finite(m) & is.finite(r) & m < r - tol, k] }", to = "D[is.finite(m) & is.finite(r) & m > r - tol, k] }",
       kill = function(e) !identical(e$p2_read_missing(hX, cX, 0.03)$n_missing_pattern, 1L)),
  list(nm = "용량 표 일치를 any 로", from = "if (all(is.na(pat) | pat == x)) return(table$label[i])", to = "if (any(is.na(pat) | pat == x)) return(table$label[i])",
       kill = function(e) !identical(e$p2_capacity_label(FALSE, FALSE, FALSE, FALSE), P2R04_CAPACITY_TABLE$label[6])),
  list(nm = "R7 S 증분 문턱 제거", from = "c3 <- is.finite(dmax) && dmax < as.numeric(tie_eps)", to = "c3 <- is.finite(dmax)",
       kill = function(e) isTRUE(e$p2_noise_reading(NO3, character(0), 0.02, 0.5, c("H1", "H2"))$result)),
  list(nm = "보는 창 파일 시험 창 알파 제거 누락", from = 'P2R04_VISIBLE_DROP <- c("alpha_test_window", "tbl", "cell_log_full_period")',
       to = 'P2R04_VISIBLE_DROP <- c("tbl", "cell_log_full_period")', kill = function(e) !is.null(e$p2_visible_only(XV, TAU)$alpha_test_window)),
  list(nm = "τ_D 이후 날짜 가림 제거", from = "if (is.character(x)) return(.p2_redact_chr(x, tau))", to = "if (is.character(x)) return(x)",
       kill = function(e) grepl("2023-05-02", e$p2_visible_only(XV, TAU)$why)),
  list(nm = "대조 함수 없는 핀 종류 묵인", from = 'if (length(unk)) bad <- c(bad, paste("대조 함수 없는 운영 핀 종류', to = 'if (FALSE) bad <- c(bad, paste("대조 함수 없는 운영 핀 종류',
       kill = function(e) !length(e$p2_pin_mismatches(pre_unk, PRT))),
  list(nm = "빠름 창 한 칸 넓힘", from = "e <- min(i1, a + as.integer(win))", to = "e <- min(i1, a + as.integer(win) + 1L)",
       kill = function(e) !identical(e$p2_fast_crash_keys(BR, CRF, 21L, -0.20)$keys, fk$keys)),
  list(nm = "음수 기준 일반화 제거", from = "thr := r - (1 - ratio) * abs(r)", to = "thr := ratio * r",
       kill = function(e) !identical(e$p2_bull_segments(bm5, br5, 0.8, 2L)$per_phase[order(k)]$ok, c(TRUE, FALSE, TRUE, FALSE))),
  list(nm = "β 비 Δ → 차이(정적 축소에 속는다)", from = "rv <- x[1] / x[2]; rr <- x[3] / x[4]", to = "rv <- x[1] - x[2]; rr <- x[3] - x[4]",
       kill = function(e) isTRUE(e$p2_beta_ratio_delta(0.7 * 1.31, 0.7 * 0.99, 1.31, 0.99)$ok)))
nk <- 0L
for (m in MU) {
  mt <- mutant(m$from, m$to)
  if (!is.null(mt$err)) { ng(paste("37 뮤테이션", m$nm), mt$err); next }
  if (isTRUE(m$kill(mt$env))) nk <- nk + 1L else ng(paste("37 뮤테이션 생존", m$nm))
}
if (nk == length(MU)) ok(sprintf("37 뮤테이션 %d/%d 검출(치환 대상 1줄 · 치환 성사 · 사본 단독 적재)", nk, length(MU)))
cat(sprintf("합계 PASS %d FAIL %d · 뮤테이션 검출 %d/%d\n", PASS, FAIL, nk, length(MU)))
cat(sprintf('{"test":"p2r04_evaluate_fixture","pass":%d,"fail":%d,"total":%d,"mutants_killed":%d,"mutants_total":%d}\n', PASS, FAIL, PASS + FAIL, nk, length(MU)))
if (FAIL > 0L) quit(status = 1L)
