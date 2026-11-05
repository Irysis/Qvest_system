## P2R05 evaluate.R 순수 도우미 픽스처(합성 · 결과 무접촉 · 사전등록 고정 대상) — 본 실행 블록은 sys.nframe() > 0 이라 안 돈다
## 실행: Rscript evaluate_fixture.R
##   P2R04 승계 도우미(공통 창 · 위기 짝 · 깊은 위기 · 빠른 급락 · 강세 · β 비대칭 · β 비 Δ · 알파 · 집중 · β 짝 사본 · 사이클 · 회복 · 라운드 판정 · 선택 · 지문 · 핀 ·
##   과반 · β 짝 계획 · 셀 로그 · 방향 경로 · LV ⑩ 3대조 · 혼합 가중 · 보유 대조 · 처치 전달 · ⑭ · 칸 통과(13조건) · 판정 어휘 · 결론 기본 이름 · 기록용 위기 ·
##   크기 분위 · 크기 × β · 시장 기준점 · 국면 월 · 유동성 분위 · RX0 동일성 · A 거리 · R7(등록 · 방어 성분) · 보는 창 가림 · 표식)
##   + P2R05 신설(경로 · 핀 · 기대 엔진 · 사양 구성 키 · 기저 적재 줄 · 워밍 센티널 · 템플릿 대조 · ⑩ 분위 엔진 · LV 구성 · 표적 정의 대조(실제 엔진 · 변조 사본 · 합성 격자) ·
##   라벨 정확값 · 거부 경계 · ⑮(독립 NW 대조) · D^σ · D^perm · R¹ · 적중 · 층화 · 교차율 · 예측표 적재(동일 · 판본 불일치 = 중단 · 시험 창 불일치 · 결손 · 중복) ·
##   상위 n 동점 · 규칙 점수 · 전이 · 재현 · Kelley · Dimson(알려진 lag 구조) · 판정 여유 · 위기 유형(실제 분류 파일 · 경계 · 핀 대조 · 없음 = 미분류) · 시작 시점 분류 기록 ·
##   진단 읽기(중심 · 희석 ① 등록 + 깊은 위기 기록 · 변동성 · 꼬리 고유 · 용량 8조합 · LV 이름 · 빈 전제 · 표 결손) · 결론 이름 · ⑮ 시험 조건 문 · τ_D 경계 · 보는 창 신호일 ·
##   꼬리 블록 끝까지(합성) · 판정 1칸 조기 경로(스텁 루트) · 센티널 · 규칙 문장 · ⑮ 예측표 셀 로그 대조(같음 · 경로 다름 · md5 다름 · 연쇄 · 대조 불가 · 셀 로그 없음 — 격리 점검 v2))
##   + 뮤테이션(소스 텍스트 치환 · 치환 대상 1줄 · 치환 성사 · 사본 단독 적재 · 본 실행 블록 미실행 — deparse 금지)
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat("  OK  ", m, "\n") }
ng <- function(m, d = "") { FAIL <<- FAIL + 1L; cat("  FAIL", m, d, "\n") }
chk <- function(id, cond, msg, d = "") if (isTRUE(cond)) ok(paste(id, msg)) else ng(paste(id, msg), d)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
RD <- file.path(ROOT, "04_Research/programs/P2_DEFENSE/P2R05_distribution_target")
EVF <- file.path(RD, "evaluate.R")
source(file.path(ROOT, "04_Research/programs/_lib/round_kit.R"))
source(EVF)
source(file.path(RD, "round_rules.R"))
source(file.path(ROOT, "02_Infrastructure/contracts/diagnosis_packet.R"))       # dp_scan_dates(가림 교차 대조 — 다른 구현)
chk("01", !exists("CELLS_ONLY") && !exists("EVS"), "source 시 본 실행 블록 미실행(sys.nframe 가드)")
J <- function(dt) fromJSON(toJSON(dt, na = "null"), simplifyVector = FALSE)
TMP <- gsub("\\\\", "/", tempdir())
TAU <- as.Date("2022-12-31")
BCP <- file.path(ROOT, "06_Registry/behavior_card.json")                         # 읽기만(규칙 상수의 행동 카드 키 원천)
FS <- p2r05_final_selection_rule(ROOT, BCP)
TI <- FS$tail_instrument; TOL <- FS$crisis_improve_min
NW <- p5_nw_fun(ROOT)
rho <- function(u, tau) u * (tau - (u < 0))                                      # 픽스처 독립 pinball
nw_ref <- function(x, L) { n <- length(x); e <- x - mean(x); s <- sum(e^2) / n                                   # 픽스처 독립 NW(Bartlett · /n)
  for (l in seq_len(L)) s <- s + 2 * (1 - l / (L + 1)) * sum(e[(l + 1):n] * e[1:(n - l)]) / n; mean(x) / sqrt(s / n) }
RXE <- "04_Research/strategies/RP_AUTO_2002_06975/engine.R"

## 02) 규칙 · 진단 표(DESIGN §3.4 · §4 · Q 10-18 LV)
chk("02", identical(names(P2R05_RULES), c("V1", "V2")) && identical(unname(vapply(P2R05_RULES, `[[`, "", "engine")), c("engine_V1.R", "engine_V2.R")) &&
      identical(names(P2R05_DIAGNOSTICS), c("Q50", "N1", "N2", "S1", "S2", "W2", "LV", "RX0S")) &&
      identical(unname(vapply(P2R05_DIAGNOSTICS, function(d) as.character(d$control), "")), c("center_only", "tail_perm", "tail_perm", "vol_proxy", "vol_proxy", "capacity_pair", "lowvol_screen", "seed_pair")) &&
      identical(P2R05_DIAGNOSTICS$LV$engines, c("E2", "E3")) && identical(P2R05_DIAGNOSTICS$RX0S$engines, c("E2", "E3")) && isTRUE(P2R05_DIAGNOSTICS$RX0S$reseed) &&
      identical(P2R05_DIAGNOSTICS$LV$factor$id, "D03_RealVol") && isTRUE(P2R05_DIAGNOSTICS$W2$blend) &&
      identical(P2R05_DIAGNOSTICS$N1$pair, "V1") && identical(P2R05_DIAGNOSTICS$S2$pair, "V2") && all(vapply(P2R05_DIAGNOSTICS[1:6], function(d) identical(d$engines, "E2"), logical(1))),
    "규칙 V1 · V2(엔진 파일) · 진단 Q50 · N1 · N2 · S1 · S2 · W2(E2) · LV(E2 · E3 · D03) · RX0S(E2 · E3 · 재시드 · control seed_pair) · 짝")

## 03) 공통 창 사본(P2R04 승계)
src <- file.path(TMP, "p2r05_src"); out <- file.path(TMP, "p2r05_out"); unlink(c(src, out), recursive = TRUE); dir.create(src)
d <- seq(as.Date("2005-01-03"), by = "day", length.out = 40); r <- c(rep(0.01, 10), rep(-0.02, 10), rep(0.005, 20)); nav <- cumprod(1 + r)
fwrite(data.table(date = d, ret_net = r), file.path(src, "03_period_returns.csv"))
fwrite(data.table(date = d, benchmark_ret = r / 2, benchmark_nav = cumprod(1 + r / 2)), file.path(src, "05_benchmark_returns.csv"))
fwrite(data.table(date = d, nav_gross = nav * 1.001, nav_net = nav, cum_cost = nav * 0.001, drawdown_net = nav / cummax(nav) - 1), file.path(src, "02_nav.csv"))
fwrite(data.table(date = rep(d[c(1, 15, 30)], each = 2), ticker = rep(c("000660", "005930"), 3), target_weight = 0.5), file.path(src, "04_holdings.csv"))
writeLines('{"y":2}', file.path(src, "authoritative_remeasure.json"))
st <- d[20]; p2_trim_artifacts(src, out, st)
nv2 <- fread(file.path(out, "02_nav.csv")); H2 <- fread(file.path(out, "04_holdings.csv"), colClasses = list(character = "ticker"))
chk("03", min(as.Date(nv2$date)) == st && abs(nv2$nav_net[1] - 1) < 1e-12 && identical(sort(unique(as.character(as.Date(H2$date)))), as.character(d[c(15, 30)])) &&
      identical(H2$ticker[1], "000660") && file.exists(file.path(out, "authoritative_remeasure.json")), "공통 창 — NAV 재기준 · 보유 = 시작에 들던 리밸부터 · 선행 0 보존 · 비 CSV 복사")

## 04) 위기 짝 비율 · 05) 깊은 위기
CR3 <- data.table(peak_date = c("2008-05-16", "2011-05-02", "2020-01-22"), trough_date = c("2008-10-24", "2011-09-26", "2020-03-19"))
crm <- J(copy(CR3)[, `:=`(dd_capture = c(0.60, 0.95, 0.70), bm_dd = c(-0.49, -0.27, -0.35))])
crr <- J(copy(CR3)[, `:=`(dd_capture = c(0.80, 0.90, 0.75), bm_dd = c(-0.49, -0.27, -0.35))])
mj <- p2_crisis_majority(crm, crr, 0.03)
chk("04", mj$n_pair == 3L && mj$n_better == 2L && abs(mj$share - 2/3) < 1e-12 && mj$unpaired == 0L && p2_crisis_majority(crm, crr, 0.06)$n_better == 1L &&
      is.na(p2_crisis_majority(list(), crr, 0.03)$share) && p2_crisis_majority(crm[1:2], crr, 0.03)$unpaired == 1L, "위기 짝 3 · 개선 2 · 문턱 0.06 이면 1 · 위기 없음 NA · 짝 없음 1")
dk <- p2_deep_crisis_keys(crm, crr)
chk("05", identical(sort(dk), sort(c("2008-05-16 2008-10-24", "2020-01-22 2020-03-19"))), "깊은 위기 = 2008 · 2020(중앙값 이상)")

## 06) 빠른 급락 — 21거래일 창 · −20% 경계 · 날짜 불일치 · 월 안 급락
bd <- seq(as.Date("2010-01-04"), by = "day", length.out = 300); rr <- rep(0, 300)
rr[11:20] <- (0.75)^(1/10) - 1; rr[101:200] <- (0.70)^(1/100) - 1; rr[231:252] <- (0.80)^(1/22) - 1; rr[261:281] <- (0.80)^(1/21) - 1
BR <- data.table(date = bd, benchmark_ret = rr)
CRF <- J(data.table(peak_date = format(bd[c(10, 100, 230, 260, 1)]), trough_date = format(c(bd[c(20, 200, 252, 281)], as.Date("2009-12-31")))))
fk <- p2_fast_crash_keys(BR, CRF, 21L, -0.20); TBF <- fk$table
bm25 <- seq(as.Date("2011-01-03"), as.Date("2011-03-31"), by = "day"); r25 <- rep(0, length(bm25)); i1 <- which(bm25 == as.Date("2011-02-03")); i2 <- which(bm25 == as.Date("2011-02-17"))
r25[(i1 + 1):i2] <- (0.75)^(1 / (i2 - i1)) - 1
fk25 <- p2_fast_crash_keys(data.table(date = bm25, benchmark_ret = r25), J(data.table(peak_date = "2011-02-03", trough_date = "2011-02-17")), 21L, -0.20)
chk("06", identical(fk$keys, c(paste(bd[10], bd[20]), paste(bd[260], bd[281]))) && isTRUE(abs(TBF$max_drop[1] + 0.25) < 1e-9) && identical(TBF$fast[2], FALSE) &&
      identical(TBF$fast[3], FALSE) && identical(fk$unclassified, paste(bd[1], "2009-12-31")) && identical(fk25$no_month_end, "2011-02-03 2011-02-17"),
    "빠름 = 10일 −25% · 21일 −20% 경계 · 느림 2 · 분류 못 함 · 월말 0")

## 07) 강세 구간 · 08) β 비대칭 수준 · 09) β 비 Δ · 10) 알파 비열등
BL <- data.table(start_ym = c("2009-03", "2011-10", "2013-07", "2016-02"), end_ym = c("2011-04", "2013-02", "2014-07", "2017-10"))
bm5 <- J(copy(BL)[, up_capture := c(0.85, 0.70, -0.23, -0.25)]); br5 <- J(copy(BL)[, up_capture := c(1.00, 1.00, -0.20, -0.20)])
bs <- p2_bull_segments(bm5, br5, 0.8, 2L)
chk("07", bs$n_pair == 4L && identical(bs$per_phase[order(k)]$ok, c(TRUE, FALSE, TRUE, FALSE)) && abs(bs$share - 0.5) < 1e-12 && is.na(p2_bull_segments(bm5[1], br5[1], 0.8, 2L)$share),
    "강세 — 0.85 ✓ · 0.70 ✗ · 음수 기준 일반화 · 짝 1 = NA")
chk("08", isTRUE(p2_beta_asym(0.8, 1.0)) && identical(p2_beta_asym(1.1, 0.9), FALSE) && identical(p2_beta_asym(1.0, 1.0), FALSE) && is.na(p2_beta_asym(NA, 1)), "하락 β < 상승 β 만 참")
d0 <- p2_beta_ratio_delta(1.31, 0.99, 1.31, 0.99); dk7 <- p2_beta_ratio_delta(0.7 * 1.31, 0.7 * 0.99, 1.31, 0.99); dg <- p2_beta_ratio_delta(0.9, 0.95, 1.31, 0.99)
chk("09", identical(d0$ok, FALSE) && identical(dk7$ok, FALSE) && isTRUE(abs(dk7$delta) < 1e-12) && isTRUE(dg$ok) && is.na(p2_beta_ratio_delta(1, 0, 1, 1)$ok), "β 비 Δ — 정적 축소 Δ 0 · 상승 β 0 = NA")
chk("10", isTRUE(p2_alpha_ok(list(t = -1.5, d_alpha = -0.01), -2, 0.10, 0.2)) && identical(p2_alpha_ok(list(t = -1.5, d_alpha = -0.03), -2, 0.10, 0.2), FALSE) &&
      identical(p2_alpha_ok(list(t = -2.5, d_alpha = 0), -2, 0.10, 0.2), FALSE) && identical(p2_alpha_ok(list(t = 0.5, d_alpha = -0.001), -2, -0.05, 0.2), FALSE) &&
      is.na(p2_alpha_ok(list(t = NA, d_alpha = 0), -2, 0.1, 0.2)), "알파 비열등 — 여유 0.2 × 엔진 α · t 문턱 · 엔진 α ≤ 0 = 감소 0")

## 11) 집중 · 12) β 짝 사본 · 13) 사이클 · 14) 회복
tl <- J(data.table(peak_date = c("2008-05-16", "2008-05-16", "2020-01-22", "2011-05-02"), Ticker = c("A", "B", "C", "D"), contrib = c(-0.18, -0.02, -0.04, -0.12)))
tl2 <- J(data.table(peak_date = c("2020-01-22", "2011-05-02"), Ticker = c("C", "D"), contrib = c(-0.04, -0.12)))
chk("11", identical(p2_conc_status(p2_top_loss(tl, c("2008-05-16", "2020-01-22"), -0.10)), "breach") && identical(p2_conc_status(p2_top_loss(tl2, "2020-01-22", -0.10)), "clear") &&
      identical(p2_conc_status(p2_top_loss(tl2, c("2008-05-16", "2020-01-22"), -0.10)), "unmeasured"), "집중 — breach · clear · 깊은 위기 누락 = 미측정")
bsrc <- file.path(TMP, "p2r05_bsrc"); bout <- file.path(TMP, "p2r05_bout"); unlink(c(bsrc, bout), recursive = TRUE); dir.create(bsrc)
for (f in c("02_nav.csv", "03_period_returns.csv", "04_holdings.csv", "05_benchmark_returns.csv")) file.copy(file.path(src, f), bsrc)
p2_beta_scaled_copy(bsrc, bout, 0.8)
pb <- fread(file.path(bout, "03_period_returns.csv")); hb <- fread(file.path(bout, "04_holdings.csv")); bb <- fread(file.path(bout, "05_benchmark_returns.csv"))
chk("12", isTRUE(all.equal(pb$ret_net, 0.8 * r)) && isTRUE(all.equal(sum(hb[date == min(date)]$target_weight), 0.8)) && isTRUE(all.equal(bb$benchmark_ret, r / 2)) &&
      inherits(try(p2_beta_scaled_copy(bsrc, bout, 1.2), silent = TRUE), "try-error"), "β 짝 사본 — 수익 · 보유 k 배 · 벤치 그대로 · k > 1 거부")
CRISES <- data.table(peak_date = c("2007-10-11", "2008-05-16", "2008-11-05", "2011-05-02", "2017-11-03", "2020-01-22", "2021-06-25"),
                     trough_date = c("2008-03-17", "2008-10-24", "2008-11-20", "2011-09-26", "2019-08-07", "2020-03-19", "2022-09-30"))
BULLS <- data.table(start_ym = c("2009-03", "2011-10", "2013-07", "2016-02", "2020-04"), end_ym = c("2011-04", "2013-02", "2014-07", "2017-10", "2021-06"))
cy <- p2_cycle_compound(J(copy(BULLS)[, st_cum := c(0.80, 0.30, 0.20, 0.40, 0.90)]), J(copy(CRISES)[, st_cum := c(-0.20, -0.40, -0.05, -0.12, -0.15, -0.25, -0.20)]),
                        J(copy(BULLS)[, st_cum := c(0.90, 0.35, 0.25, 0.45, 1.00)]), J(copy(CRISES)[, st_cum := c(-0.25, -0.45, -0.06, -0.20, -0.10, -0.28, -0.30)]))
chk("13", cy$n_pair == 3L && cy$n_ge == 2L && abs(cy$share - 2/3) < 1e-12 && length(cy$unpaired_crises) == 4L, "사이클 짝 3 · 칸 ≥ 기준 2/3 · 짝 없는 위기 4")
rt <- p2_recovery_tag(J(copy(CR3)[, `:=`(st_recovery_obs = c(400, 100, 300), st_recovery_censored = c(FALSE, FALSE, TRUE))]),
                      J(copy(CR3)[, `:=`(st_recovery_obs = c(300, 120, 200), st_recovery_censored = c(FALSE, FALSE, FALSE))]), 0.5)
chk("14", identical(rt$n_longer, 2L) && isTRUE(rt$tag) && identical(p2_recovery_tag(J(CR3), J(CR3), 0.5)$status, "unmeasured"), "회복 — 더 긴 위기 2/3 → 회복 지연 · 관측 없음 = 미측정")

## 15) 라운드 판정(규칙 × 구성) · 16) 선택 · 17) 지문 · 19) 과반 · 20) β 짝 계획
T1 <- data.table(engine = rep(c("E2", "E3"), each = 2), device = rep(c("V1", "V2"), 2), tested = TRUE, pass = c(TRUE, FALSE, TRUE, TRUE), excluded = FALSE)
v1 <- p2_round_verdict(T1); T6 <- copy(T1)[, pass := TRUE][, excluded := c(TRUE, FALSE, FALSE, FALSE)]; v6 <- p2_round_verdict(T6)
chk("15", identical(v1$verdict, "supported") && identical(v1$both, "V1") && identical(v1$one, "V2") && identical(v1$label, "supported(판정 4/4)") &&
      identical(v6$excluded, "V1") && identical(p2_round_verdict(copy(T1)[, tested := FALSE])$verdict, "untested"), "supported(판정 4/4) · 한 구성 · 집중 제외 · untested")
mk <- function(dv, s, s0, b3, b4) list(device = dv, non_inferiority = list(S = s, S_rx0 = s0), rules = list(beta_deep = list(share = b3), fast = list(share = b4)))
sel <- p2_select(list(V2 = list(mk("V2", 0.8, 0.5, 0.6, 0.6), mk("V2", 0.45, 0.5, 0.6, 0.6)), V1 = list(mk("V1", 0.7, 0.5, 0.6, 0.6), mk("V1", 0.6, 0.5, 0.6, 0.6))))
selt <- p2_select(list(V1 = list(mk("V1", 0.7, 0.5, 0.6, 0.6)), V2 = list(mk("V2", 0.7, 0.5, 0.8, 0.8))))
chk("16", identical(sel[[1]]$device, "V1") && identical(selt[[1]]$device, "V2") && identical(selt[[1]]$tie_break, "r34") && !length(p2_select(list())), "선택 — 평균 S 증분 · 동률 ③④ 합 · 검증 0 = 없음")
chk("17", !identical(c(A = "x|y"), "x|y") && isTRUE(p2_fp_same(c(A = "x|y"), "x|y")) && !isTRUE(p2_fp_same("x|y", "x|z")), "지문 — 이름 붙은 벡터도 같음 · 다르면 거짓")
chk("19", identical(p2_maj(0.5, 0.5), FALSE) && isTRUE(p2_maj(0.51, 0.5)) && identical(p2_maj(NA, 0.5), FALSE) && identical(p2_maj(c(0.9, 0.9), 0.5), FALSE), "과반 — 같음 = 거짓 · NA · 길이 2 = 거짓")
b1 <- p2_beta_plan(0.8, 1); b2 <- p2_beta_plan(1.2, 1); b4 <- p2_beta_plan(NA, 1); b6 <- p2_beta_plan(0.5, 1, 0.9)
chk("20", identical(b1$mode, "scaled") && identical(b2$mode, "rx0") && identical(p2_beta_plan(1, 1)$mode, "rx0") && identical(b4$mode, "unmeasured") && isTRUE(b6$forced) && identical(b6$k, 0.9),
    "β 짝 계획 — 사본 · RX0 · 미측정 · 강제")

## 18) 핀 재대조
PRT <- file.path(TMP, "p2r05_pinroot"); unlink(PRT, recursive = TRUE); dir.create(file.path(PRT, "06_Registry"), recursive = TRUE); dir.create(file.path(PRT, ".cache/factor_db"), recursive = TRUE)
writeLines(toJSON(list(entries = list(list(catalog_id = "lean:entropy", status = "active", resolver = list(f = "x")))), auto_unbox = TRUE), file.path(PRT, "06_Registry/weight_catalog.json"))
writeLines(toJSON(list(D03_RealVol = list(name = "Realized Volatility", direction = "lower_better")), auto_unbox = TRUE), file.path(PRT, ".cache/factor_db/factor_registry.json"))
writeLines("a", file.path(PRT, "f.txt"))
pre_ok <- list(cells = list(), operational_pins = list(files = list(list(path = "f.txt", md5 = unname(tools::md5sum(file.path(PRT, "f.txt"))))),
               catalog_entries = list(list(catalog_id = "lean:entropy", status = "active", resolver = list(f = "x"))),
               factor_registry_entries = list(list(id = "D03_RealVol", entry = list(name = "Realized Volatility", direction = "lower_better"))),
               packages = list(), r_version = R.version.string))
pre_fr <- pre_ok; pre_fr$operational_pins$factor_registry_entries[[1]]$entry$direction <- "higher_better"
pre_unk <- pre_ok; pre_unk$operational_pins$factor_db_snapshot <- list(list(path = "x"))
chk("18", !length(p2_pin_mismatches(pre_ok, PRT)) && identical(p2_pin_mismatches(pre_fr, PRT), "팩터 레지스트리 엔트리: D03_RealVol") &&
      length(p2_pin_mismatches(pre_unk, PRT)) == 1L && grepl("대조 함수 없는 운영 핀 종류", p2_pin_mismatches(pre_unk, PRT)), "핀 — 일치 0 · 레지스트리 변경 1 · 대조 함수 없는 종류 1")

## 21) 셀 로그 · 22) 방향 경로 · 23) LV ⑩ 3대조 · 24) 혼합 가중
ln <- function(cell, fac, wt = "ew", months = 322L) sprintf("[rf_cell_engine] cell=%s | univ=all_hyg | factors=%s | wt=%s | months=%d | rows=6525", cell, fac, wt, months)
p1 <- p2_parse_cell_log(paste0(ln("P2R05_E2_LV", "D03_RealVol"), "\r")); pn <- p2_parse_cell_log(c("[rf_cell_engine] catalog lean:entropy | x", "noise"))
chk("21", isTRUE(p1$found) && identical(p1$factors, "D03_RealVol") && identical(p1$months, 322L) && !isTRUE(pn$found) && identical(p2_parse_cell_log(ln("X", "none"))$factors, character(0)),
    "셀 로그 — D03 · CRLF · months · none = 빈 목록 · 줄 없음")
dl <- function(d, ic, reg, def, n) c(sprintf("[align_factor_direction] PIT-safe: sig_date=%s | min_months=36", d),
                                      sprintf("[align_factor_direction] loaded-factor direction: IC-inferred=%d / registry-fallback=%d / default-fallback=%d (n_factors=%d)", ic, reg, def, n))
DD <- p2_parse_direction_lines(c(dl("2005-01-31", 1L, 0L, 0L, 1L), dl("2005-02-28", 0L, 1L, 0L, 1L), dl("2023-01-31", 1L, 0L, 0L, 1L)))
r2d <- p2_direction_record(DD, 1L, "2005-02-02", TAU)
chk("22", nrow(DD) == 3L && identical(r2d$n_sig, 2L) && identical(r2d$registry_fallback, 1L) && !is.na(r2d$tag), "방향 경로 — 평가 창 신호일 2 · 레지스트리 대체 1 → 꼬리표 · τ 뒤 제외")
fe <- function(...) lapply(c(...), function(i) list(kind = "db", id = i))
SR3 <- fe("M01_Mom_12_1", "V10_FCF_Yield", "M08_Residual_Mom"); DEVLV <- P2R05_DIAGNOSTICS$LV$factor
c_e2 <- p2_construction_check(p2_parse_cell_log(ln("P2R05_E2_LV", "D03_RealVol")), p2_parse_cell_log(ln("P2R05_E2_RX0", "none")), DEVLV, fe("D03_RealVol"), list(), "P2R05_E2_LV", "P2R05_E2_RX0")
c_e3 <- p2_construction_check(p2_parse_cell_log(ln("P2R05_E3_LV", "M01_Mom_12_1+V10_FCF_Yield+M08_Residual_Mom+D03_RealVol")),
                              p2_parse_cell_log(ln("P2R05_E3_RX0", "M01_Mom_12_1+V10_FCF_Yield+M08_Residual_Mom")), DEVLV, c(SR3, fe("D03_RealVol")), SR3, "P2R05_E3_LV", "P2R05_E3_RX0")
c_vl <- p2_construction_check(p2_parse_cell_log(ln("P2R05_E2_LV", "none")), p2_parse_cell_log(ln("P2R05_E2_RX0", "none")), DEVLV, fe("D03_RealVol"), list(), "P2R05_E2_LV", "P2R05_E2_RX0")
chk("23", isTRUE(c_e2$ok) && isTRUE(c_e3$ok) && identical(unname(unlist(c_vl$checks)), c(TRUE, FALSE, TRUE)), "LV ⑩ — E2(D03 꼬리 1) · E3(RX0 3팩터 + D03) 통과 · 변형 로그 미적재 = 그 대조만")
chk("24", identical(p2_blend_weight(0.875, 1L)$device_weight, 0.125) && identical(p2_blend_weight(0.5, 4L, 1L)$device_weight, 0.125) && is.na(p2_blend_weight(0.5, 0L)$device_weight),
    "혼합 가중 — E2 LV 0.875 → 0.125 · E3 LV 0.5 · 4팩터 → 0.125 · 팩터 0 = NA")

## 25) 보유 대조 · 26) 처치 전달
tick <- sprintf("%06d", 1:30); D3 <- as.Date(c("2010-01-04", "2010-02-01", "2023-03-02"))
H_R <- data.table(date = rep(D3, each = 25), ticker = rep(tick[1:25], 3), w = 0.04)
H_S <- copy(H_R)[date == D3[2] & ticker == tick[25], ticker := tick[26]]
H_W <- copy(H_R)[date == D3[1] & ticker %in% tick[1:2], w := c(0.05, 0.03)]
H_T <- copy(H_R)[date == D3[3] & ticker == tick[25], ticker := tick[27]]
o_i <- p2_holdings_overlap(copy(H_R), H_R, TAU); o_s <- p2_holdings_overlap(H_S, H_R, TAU); o_w <- p2_holdings_overlap(H_W, H_R, TAU); o_t <- p2_holdings_overlap(H_T, H_R, TAU)
chk("25", identical(o_i$n_differ, 0L) && identical(o_s$n_differ, 1L) && identical(o_w$n_differ, 1L) && identical(o_t$n_differ, 0L) && identical(p2_holdings_overlap(H_R[0], H_R, TAU)$status, "unmeasured"),
    "보유 대조 — 같음 0 · 교체 1 · 비중만 1 · τ 뒤 0 · 빈 보유 = 미측정")
chk("26", identical(p2_treatment_delivered(o_i), FALSE) && isTRUE(p2_treatment_delivered(o_s)), "처치 전달 — 같음 = 거짓 · 다름 = 참")

## 27) ⑭ 선택 귀속
s_a <- p2_selection_attr("selection_defense", FS$mc8_label_required); s_e <- p2_selection_attr("insufficient", "selection_defense")
EXV <- J(data.table(peak_date = c("2008-05-16", "2011-05-02", "2020-01-22"), selection_sum = c(-0.02, -0.10, -0.01)))
EXR <- J(data.table(peak_date = c("2008-05-16", "2011-05-02", "2020-01-22"), selection_sum = c(-0.08, -0.05, -0.06)))
sd_ok <- p2_selection_decomp(EXV, EXR, c("2008-05-16", "2020-01-22"), 0.5); sd_na <- p2_selection_decomp(J(data.table(peak_date = "2008-05-16", x = 1)), EXR, "2008-05-16", 0.5)
PK4 <- c("2008-05-16", "2011-05-02", "2020-01-22", "2021-06-25")
ERX <- J(data.table(peak_date = PK4, selection_sum = -0.10))
sd_eq <- p2_selection_decomp(J(data.table(peak_date = PK4, selection_sum = c(-0.10, -0.10, -0.10, -0.099))), ERX, PK4, 0.5)
chk("27", isTRUE(s_a$ok) && identical(s_e$status, "unmeasured") && isTRUE(sd_ok$ok) && identical(sd_na$status, "unmeasured") && identical(sd_eq$n_better, 1L) &&
      isTRUE(p2_selection_rule(s_a, sd_ok)$ok) && identical(p2_selection_rule(s_a, sd_na)$measured, FALSE), "⑭ — 라벨 · insufficient = 미측정 · 분해 엄격 > 0 · 필드 없음 = 미측정")

## 28) 칸 통과 — 13조건(⑮ 포함) · 29) 판정 어휘
FL <- list(crisis = TRUE, deep = TRUE, beta_deep = TRUE, fast = TRUE, beta_ratio = TRUE, bull = TRUE, alpha = TRUE, cycle = TRUE, construction = TRUE, S = TRUE, path = TRUE, selection = TRUE, tail = TRUE)
one_off <- vapply(names(FL), function(k) { f <- FL; f[[k]] <- FALSE; p2_cell_pass(f) }, logical(1)); one_na <- vapply(names(FL), function(k) { f <- FL; f[[k]] <- NA; p2_cell_pass(f) }, logical(1))
chk("28", isTRUE(p2_cell_pass(FL)) && !any(one_off) && !any(one_na) && length(FL) == 13L, "칸 통과 — ①~⑦ · ⑨ · ⑩ · ⑫ · ⑬ · ⑭ · ⑮ 13조건 · 하나 거짓 · NA = 거짓")
vf <- function(...) { f <- list(pass = FALSE, beta_unmeasured = FALSE, beta_deep = FALSE, fast = FALSE, crisis = FALSE, deep = FALSE, selection = FALSE, selection_measured = TRUE,
                                level = TRUE, beta_ratio = TRUE, strength = list(bull = TRUE, alpha = FALSE, cycle = TRUE, S = TRUE, path = TRUE), tail = TRUE)
                      a <- list(...); f[names(a)] <- a; p2_cell_verdict(f) }
VV <- c(vf(pass = TRUE), vf(beta_deep = NA), vf(beta_deep = TRUE, fast = NA), vf(crisis = TRUE, deep = TRUE), vf(beta_deep = TRUE, fast = TRUE, selection_measured = FALSE),
        vf(beta_deep = TRUE, fast = TRUE), vf(crisis = TRUE, deep = TRUE, beta_deep = TRUE, fast = TRUE, selection = TRUE), vf(beta_deep = TRUE))
chk("29", identical(VV, c("pass", "beta_unmeasured", "fast_unmeasured", "exposure_only", "selection_unmeasured", "size_or_exposure_defense", "defense_but_strength_or_path", "not_decisive")) &&
      all(VV %in% P2R05_VERDICTS) && all(c("untested_tail_instrument", "asymmetry_unmet") %in% P2R05_VERDICTS) && setequal(names(P2R05_VERDICT_NAMES), P2R05_VERDICTS) && setequal(names(P2R05_VERDICT_SHORT), P2R05_VERDICTS) &&
      grepl("꼬리 회피 기계", P2R05_VERDICT_NAMES[["defense_but_strength_or_path"]]) && grepl("반증 아님", P2R05_VERDICT_NAMES[["untested_tail_instrument"]]),
    "판정 어휘 — P2R04 8분기 + untested_tail_instrument · asymmetry_unmet · '꼬리 회피 기계(방어만 · 복리 없음)'(⑥ 미달 · ⑤ · ⑮ 통과)")

## 30) 기록용 위기 · 31) 크기 분위 · 38) 크기 × β · 39) 시장 기준점 · 40) 국면 월 · 42) 유동성 분위 · 43) 결론 기본 이름 · 44) A 거리
CRT <- data.table(peak_date = c("2007-10-11", "2008-05-16", "2011-05-02"), trough_date = c("2008-03-17", "2008-10-24", "2011-09-26"))
REC <- p2_crisis_record(J(copy(CRT)[, dd_capture := c(0.50, 0.60, 0.90)]), J(copy(CRT)[, dd_capture := c(0.70, 0.80, 0.85)]), J(copy(CRT)[, dd_capture := c(0.60, 0.70, 0.80)]),
                        FS$state_unturned_max_drop_crises, 0.03, deep = "2011-05-02 2011-09-26")
chk("30", identical(REC$crisis, c("2007-10-11 2008-03-17", "2011-05-02 2011-09-26")) && identical(REC$beats_beta_copy, c(TRUE, FALSE)) && identical(REC$deep, c(FALSE, TRUE)),
    "상태 미전환 최대 하락 위기 — 2007-10 · 2011-05 · β 짝 승패 · 깊음")
SZ <- p2_size_compare(J(data.table(size_decile = c(10, 9, NA, 10), n = c(3, 2, 1, 5), peak_date = c("2008-05-16", "2008-05-16", "2008-05-16", "2011-05-02"))),
                      J(data.table(size_decile = c(5, 6), n = c(4, 4), peak_date = c("2008-05-16", "2011-05-02"))), "2008-05-16")
chk("31", isTRUE(abs(SZ$deep_mean_decile - 9.6) < 1e-12) && identical(SZ$deep_mean_decile_rx0, 5), "크기 분위 — 9.6(결측 제외) vs 5")
CRC <- J(copy(CR3)[, dd_capture := c(0.70, 0.80, 0.85)])
chk("38", identical(p2_size_beta_plan(1.2, 1)$scale, 1) && isTRUE(p2_size_beta_core(crm, CRC, dk, 0.03, 0.5)$ok) && identical(p2_size_beta_core(crm, CRC, dk[1], 0.03, 0.5)$ok, FALSE),
    "크기 × β — 차입 없음 · 깊은 위기 2/2 · 짝 1 = 미측정")
vm <- p2_vs_market(J(copy(CR3)[, `:=`(dd_capture = c(0.60, 0.98, 0.70))]), 0.03)
chk("39", identical(vm$n_better, 2L) && isTRUE(abs(vm$share - 2/3) < 1e-12), "시장 기준점 — 0.60 · 0.70 < 0.97 → 2/3")
YM <- format(seq(as.Date("2008-01-01"), by = "month", length.out = 12), "%Y-%m"); DF <- c(0.01, 0.01, 0.01, -0.02, -0.02, -0.02, 0.03, 0.03, 0, 0, 0, 0.005)
rg <- p2_regime_diff(YM, DF, J(data.table(peak_date = "2008-04-10", trough_date = "2008-06-20")), J(data.table(start_ym = c("2008-06", "2008-07"), end_ym = c("2008-06", "2008-08"))))
chk("40", identical(rg$crisis$n, 3L) && identical(rg$bull$n, 2L) && identical(rg$other$n, 7L), "국면 월 — 위기 우선 3 · 강세 2 · 그 밖 7")
chk("42", identical(p2_liq_deciles(c(1, 50, 100, NA), 1:100), c(1L, 5L, 10L, NA)) && all(is.na(p2_liq_deciles(c(1, 2), 1:9))), "유동성 분위 — 1 · 5 · 10 · NA · 유니버스 9 = NA")
chk("43", grepl("방어 이름 없음", p2_defense_name(FALSE, TRUE, TRUE, TRUE, TRUE, "ok")) && grepl("보류", p2_defense_name(NA, TRUE, TRUE, TRUE, TRUE, "ok")) &&
      grepl("노출\\(β\\) 방어", p2_defense_name(TRUE, TRUE, FALSE, TRUE, TRUE, "ok")) && identical(p2_defense_name(TRUE, TRUE, TRUE, TRUE, TRUE, "ok"), "선택(특성) 방어") &&
      grepl("크기 × β 방어", p2_defense_name(TRUE, TRUE, TRUE, TRUE, FALSE, "ok")), "결론 기본 이름 — 미통과 · 보류 · 노출 · 선택(특성) · 크기 × β")
ad <- p2_a_distance(list(cagr = 0.12, sharpe = 0.9, calmar = 0.3, port_t = 2.5), 0.25, list(cagr_min = 0.16, sharpe_min = 0.8, port_t_b = 2.0), S = 0.7, a_boundary = 1)
chk("44", isTRUE(abs(ad$cagr$distance + 0.04) < 1e-12) && identical(ad$cagr$meets, FALSE) && isTRUE(ad$calmar$meets) && identical(ad$S$meets, FALSE), "A 거리 — 값 − 문턱 · 충족")

## 32) 규칙 키(⑮ 하위 키 포함) · 33) 규칙 승계(P2R04 키 · 값 그대로 + tail_instrument)
FSx <- FS; FSx$tail_instrument$t_min <- NULL; FSy <- FS; FSy$tail_instrument <- NULL
chk("32", !length(p2_fs_missing(FS)) && identical(p2_fs_missing(FSx), "tail_instrument.t_min") && identical(p2_fs_missing(FSy), "tail_instrument") &&
      identical(sort(p2_fs_missing(NULL)), sort(P2R05_FS_KEYS)), "규칙 키 — 결손 0 · tail_instrument.t_min · tail_instrument · 규칙 없음 = 전부")
e4 <- new.env(); sys.source(file.path(ROOT, "04_Research/programs/P2_DEFENSE/P2R04_defensive_holdings/round_rules.R"), envir = e4, keep.source = FALSE)
F4 <- e4$p2r04_final_selection_rule(ROOT, BCP)
P4F <- fromJSON(file.path(ROOT, "stage_artifacts/programs/P2_DEFENSE/P2R04_defensive_holdings/prereg.json"), simplifyVector = FALSE)$final_selection_rule
same4 <- vapply(names(F4), function(k) identical(F4[[k]], FS[[k]]), logical(1))
num4 <- c("calmar_norm", "port_t_norm", "w_calmar", "w_port_t", "tie_eps", "uc_floor", "majority_share", "crisis_improve_min", "alpha_t_floor", "alpha_margin_frac",
          "single_name_loss_floor", "bull_ratio", "fast_window_days", "fast_drop")
samep <- vapply(num4, function(k) isTRUE(all.equal(as.numeric(FS[[k]]), as.numeric(P4F[[k]]))), logical(1))
chk("33", all(same4) && setequal(names(FS), c(names(F4), "tail_instrument")) && all(samep) && identical(unlist(FS$state_unturned_max_drop_crises), unlist(P4F$state_unturned_max_drop_crises)) &&
      identical(FS$tail_instrument, list(tau = 0.1, ref = "constant_tau", nw_lag = 3, t_min = 2, t_min_source = "measurement-graduation §2 t_min_survive")),
    "승계 — P2R04 함수 키 · 값 · 근거 문장 동일 · P2R04 사전등록 값 동일 · tail_instrument 그대로", paste(names(F4)[!same4], names(samep)[!samep]))

## 34) 칸 목록(14칸 · DESIGN §12 + LV)
mkc <- function(en, cp, ctl = P2R05_DIAGNOSTICS[[cp]]$control %||% NA_character_) list(code = paste0("P2R05_", en, "_", cp), engine = en, component = cp,
                                                                                        reference = identical(cp, "RX0"), diagnostic = cp %in% names(P2R05_DIAGNOSTICS), control = ctl)
GOOD <- c(lapply(c("RX0", "V1", "V2", "Q50", "N1", "N2", "S1", "S2", "W2", "LV", "RX0S"), function(cp) mkc("E2", cp)), lapply(c("RX0", "V1", "V2", "LV", "RX0S"), function(cp) mkc("E3", cp)))
NOCTL <- lapply(GOOD, function(z) { z$control <- NULL; z })
B_ctl <- GOOD; B_ctl[[4]]$control <- "vol_proxy"
B_q3 <- c(GOOD, list(mkc("E3", "Q50"))); B_jc <- GOOD; B_jc[[2]]$control <- "center_only"
B_rule <- GOOD[-14]; B_unk <- c(GOOD, list(mkc("E2", "V3", NA))); B_code <- GOOD; B_code[[2]]$code <- "P2R05_E3_V1"
G_rs <- GOOD; G_rs[[11]]$control <- "seed_band"                                     # RX0S control ≠ seed_pair = 불일치(Q 10-18 정렬 1 — 대조한다)
chk("34", length(GOOD) == 16L && !length(p2_cells_check(GOOD)) && !length(p2_cells_check(NOCTL)) && any(grepl("control ≠ 진단 표: P2R05_E2_RX0S", p2_cells_check(G_rs), fixed = TRUE)) &&
      identical(GOOD[[11]]$control, "seed_pair") && any(grepl("control ≠", p2_cells_check(B_ctl))) &&
      any(grepl("engines 밖", p2_cells_check(B_q3))) && any(grepl("판정 칸에 control", p2_cells_check(B_jc))) && any(grepl("규칙 집합", p2_cells_check(B_rule))) &&
      any(grepl("V3", p2_cells_check(B_unk))) && any(grepl("code ≠", p2_cells_check(B_code))) && identical(sort(vapply(GOOD, `[[`, "", "code")), sort(P2R05_CELL_PLAN$code)) &&
      identical(P2R05_CELL_PLAN$control[P2R05_CELL_PLAN$component == "RX0S"], c("seed_pair", "seed_pair")),
    "칸 목록 — 16칸 통과 · control 없어도 · RX0S control = seed_pair(다르면 불일치) · control 불일치 · E3 Q50 · 판정 칸 control · 규칙 결손 · 표 밖 부품 · code · round_rules 계획 16칸")

## 35) 보는 창 가림(P2R04 승계)
XV <- list(alpha_test_window = list(t = 1), tbl = data.table(a = 1), cell_log_full_period = list(variant = list(months = 322L)),
           trim = list(variant = list(start = as.Date("2005-03-02"), n_pr = 4000L)), why = "공통 창 실패: start 2023-05-02 이후", rules = list(ym = c("2022-12", "2023-01")),
           table = data.table(k = c("2008-05-16 2008-10-24", "2023-02-01 2023-03-01"), v = 1:2))
VO <- p2_visible_only(XV, TAU)
chk("35", is.null(VO$alpha_test_window) && is.null(VO$tbl) && is.null(VO$cell_log_full_period) && is.null(VO$trim$variant$n_pr) && !grepl("2023-05-02", VO$why) &&
      identical(VO$rules$ym, c("2022-12", P2R05_REDACT)) && identical(XV$table$k[2], "2023-02-01 2023-03-01") && !length(dp_scan_dates(VO, TAU)) && length(dp_scan_dates(XV, TAU)) > 0L,
    "보는 창 — 시험 창 · 전 구간 항목 제거 · τ 뒤 날짜 가림 · 원본 무변경 · 전수 검사 0")

## 41) RX0 동일성(P2R04 대비 · 이름)
PRa <- data.table(date = seq(as.Date("2010-01-04"), by = "day", length.out = 70), ret_net = 0.001); PRb <- copy(PRa); PRb[10, ret_net := 0.002]
i_s <- p2_rx0_identity_core(H_R, H_R, PRa, PRa, TAU); i_r <- p2_rx0_identity_core(H_R, H_R, PRb, PRa, TAU)
chk("41", isTRUE(i_s$holdings_same) && isTRUE(i_s$returns_same) && identical(i_r$months_differ, 1L) && all(c("holdings_dates_only_p2r05", "holdings_dates_only_p2r04") %in% names(i_s)),
    "RX0 동일성 — 같음 · 하루 다름 = 다른 달 1 · 필드 이름 P2R05 · P2R04")

## 45) R7 판독 — 등록(P2R04 그대로) · 방어 성분(S 무관 · 판정된 규칙 = 두 구성 tested ∧ ③ 측정)
nx <- function(dv, eng, sh, s, s0, tested = TRUE, st = "ok") list(device = dv, engine = eng, tested = tested,
  rules = list(beta_deep = list(share = if (identical(st, "ok")) sh else NA_real_, status = st, n_pair = if (identical(st, "ok")) 2L else 0L)), non_inferiority = list(S = s, S_rx0 = s0))
NO1 <- list(nx("V1", "E2", 0.4, 0.51, 0.5), nx("V1", "E3", 0.6, 0.505, 0.5), nx("V2", "E2", 0.6, 0.49, 0.5), nx("V2", "E3", 0.4, 0.5, 0.5))
NO3 <- list(nx("V1", "E2", 0.4, 0.6, 0.5), nx("V1", "E3", 0.4, 0.6, 0.5), nx("V2", "E2", 0.4, 0.5, 0.5), nx("V2", "E3", 0.4, 0.5, 0.5))
NO2 <- list(nx("V1", "E2", 0.6, 0.51, 0.5), nx("V1", "E3", 0.6, 0.505, 0.5), nx("V2", "E2", 0.4, 0.5, 0.5), nx("V2", "E3", 0.4, 0.5, 0.5))
NOS <- list(nx("V1", "E2", 0.4, NA, 0.5), nx("V1", "E3", 0.4, 0.5, 0.5), nx("V2", "E2", 0.4, 0.5, 0.5), nx("V2", "E3", 0.4, 0.5, 0.5))   # V1 S 비유한
NO8 <- unlist(lapply(c("V1", "V2"), function(h) list(nx(h, "E2", NA, 0.501, 0.5, st = "unmeasured"), nx(h, "E3", NA, 0.5, 0.5, st = "unmeasured(짝 < 2)"))), recursive = FALSE)
nr1 <- p2_noise_reading(NO1, character(0), 0.02, 0.5); nr3 <- p2_noise_reading(NO3, character(0), 0.02, 0.5); nr2 <- p2_noise_reading(NO2, character(0), 0.02, 0.5)
nrs <- p2_noise_reading(NOS, character(0), 0.02, 0.5); nr8 <- p2_noise_reading(NO8, character(0), 0.02, 0.5); nrv <- p2_noise_reading(NO1, "V1", 0.02, 0.5)
chk("45", isTRUE(nr1$result) && isTRUE(nr1$defense_component$result) && isTRUE(nr1$defense_component$paused_and_report) && grepl("P2 정지", nr1$defense_component$label) &&
      identical(nr3$result, FALSE) && isTRUE(nr3$defense_component$result) && identical(nr2$result, FALSE) && identical(nr2$defense_component$result, FALSE) &&
      is.na(nrs$result) && isTRUE(nrs$defense_component$result) && identical(nrs$defense_component$judged_devices, "2/2") && is.na(nr8$result) && is.na(nr8$defense_component$result) &&
      identical(nrv$result, FALSE) && identical(nrv$defense_component$result, FALSE),
    "R7 — 등록 잡음 이내 ∧ 방어 잡음(정지 · 보고) · S 증분 큼 = 등록 밖 · 방어 이내 · ③ 두 구성 과반 = 둘 다 밖 · S 비유한 = 등록 판독 불가 · 방어 판독 · ③ 미측정 = 둘 다 불가 · 검증 1 = 밖")

## 46) 라운드 라벨 판정어별 칸 수(⑮ 포함) · 47) 작업 사본 표식
TB4 <- data.table(engine = rep(c("E2", "E3"), each = 2), device = rep(c("V1", "V2"), 2), tested = FALSE, pass = FALSE, excluded = FALSE, verdict = "untested_tail_instrument")
TBm <- copy(TB4)[1:2, `:=`(tested = TRUE, verdict = c("exposure_only", "beta_unmeasured"))]
chk("46", identical(p2_round_verdict(TB4)$label, "untested(판정 0/4 · 꼬리 계기 미시험 4)") && identical(p2_round_verdict(TBm)$label, "falsified(판정 2/4 · 노출 방어 1 · β 짝 미측정 1 · 꼬리 계기 미시험 2)"),
    "라운드 라벨 — '꼬리 계기 미시험 4' · 혼합 = 어휘 순서", paste(p2_round_verdict(TB4)$label, p2_round_verdict(TBm)$label))
mk_bout <- readLines(file.path(bout, "NO_VISIBLE_REVIEW.txt"), warn = FALSE, encoding = "UTF-8")
PMK <- file.path(TMP, "p2r05_mark_parent"); unlink(PMK, recursive = TRUE); .p2_mark_full(PMK, P2R05_FULL_MARK_PARENT)
chk("47", identical(mk_bout, P2R05_FULL_AUDIENCE) && identical(readLines(file.path(PMK, "NO_VISIBLE_REVIEW.txt"), warn = FALSE, encoding = "UTF-8"), c(P2R05_FULL_AUDIENCE, P2R05_FULL_MARK_PARENT)) &&
      grepl("rx0_dimson_scaled", P2R05_FULL_MARK_PARENT), "표식 — β 짝 사본 · 상위 폴더 문구(Dimson 사본 포함)")

## ═══ P2R05 신설 ═══
## N01) 경로 · 핀 · 설계 입력 핀
pre_pin <- list(operational_pins = list(files = list(list(path = "04_Research/strategies/DT_2002_06975/engine_V1.R", md5 = "aaa"), list(path = "x/y.R", md5 = "b1"), list(path = "x\\y.R", md5 = "b2"))),
                design_inputs = list(note = "x", files = list(list(path = "04_Research/programs/P2_DEFENSE/_design_notes/crisis_type_classify.json", md5 = "m1")), more = list(list(file = "a/b.json", md5 = "m2"))))
chk("N01", identical(p5_rel("C:\\Users\\99922\\OneDrive\\Quant_Module_Moltbot/04_Research/x.R", ROOT), "04_Research/x.R") && identical(p5_rel("c:/users/99922/onedrive/quant_module_moltbot/a.R", ROOT), "a.R") &&
      identical(p5_rel("04_Research/x.R", ROOT), "04_Research/x.R") && identical(p5_pin_md5(pre_pin, "04_research/strategies/DT_2002_06975/engine_V1.R"), "aaa") &&
      is.na(p5_pin_md5(pre_pin, "x/y.R")) && is.na(p5_pin_md5(pre_pin, "z.R")) && identical(p5_find_pin(pre_pin$design_inputs, P2R05_CRISIS_TYPE_NOTE), "m1") &&
      identical(p5_find_pin(pre_pin$design_inputs, "a/b.json"), "m2") && !length(p5_find_pin(list(), "a/b.json")),
    "경로 — 절대 · 역슬래시 · 대소문자 → 저장소 상대 · 핀 md5(대소문자 무시) · 같은 경로 핀 둘이 다르면 NA · 설계 입력 핀 재귀 탐색(path · file)")

## N02~N08 스텁 루트(엔진 파일 · 사양 · 셀 로그 · 보유) — ⑩ · 판정 1칸 조기 경로 공용
STR <- file.path(TMP, "p2r05_stub"); unlink(STR, recursive = TRUE)
for (dd in c("04_Research/strategies/RP_AUTO_2002_06975", "04_Research/strategies/DT_2002_06975", "specs", "results", "art")) dir.create(file.path(STR, dd), recursive = TRUE, showWarnings = FALSE)
ENGF <- c(RX0 = "04_Research/strategies/RP_AUTO_2002_06975/engine.R", V1 = "04_Research/strategies/DT_2002_06975/engine_V1.R", V2 = "04_Research/strategies/DT_2002_06975/engine_V2.R",
          Q50 = "04_Research/strategies/DT_2002_06975/engine_Q50.R")
for (k in names(ENGF)) writeLines(paste("# stub engine", k), file.path(STR, ENGF[[k]]))
MD5 <- vapply(ENGF, function(p) unname(tools::md5sum(file.path(STR, p))), "")
PRE_STUB <- list(operational_pins = list(files = lapply(names(ENGF), function(k) list(path = ENGF[[k]], md5 = MD5[[k]]))))
FX <- list(n_max = 25L, liq_adv20_min = 2e8, start_date = "2000-01-01", universe = "ALL_HYG", measurement_axis = "all_hyg_px1000_2000_v1", base_weight = 0.5)
spec <- function(code, kind = "engine", paths = ENGF[["RX0"]], bw = 0.5, factors = list(), fx = FX)
  list(code = code, block = "RX", base_signal = if (identical(kind, "engine_blend")) list(kind = kind, paths = as.list(file.path(STR, paths))) else list(kind = kind, path = file.path(STR, paths)),
       base_weight = bw, factors = factors, weighting = list(kind = "ew"), fixed_axes = fx, universe = list(kind = "all_hyg"), defense_sleeve = NULL, label = paste("라벨", code), idea = "x")
wspec <- function(nm, s) writeLines(toJSON(s, auto_unbox = TRUE, null = "null", digits = NA), file.path(STR, "specs", paste0(nm, ".json")))
wspec("R", spec("R")); wspec("V1", spec("V1", paths = ENGF[["V1"]])); wspec("V2", spec("V2", paths = ENGF[["V2"]])); wspec("Q50", spec("Q50", paths = ENGF[["Q50"]]))
wspec("V1x", spec("V1x", paths = ENGF[["V2"]])); wspec("W2", spec("W2", kind = "engine_blend", paths = c(ENGF[["RX0"]], ENGF[["V2"]])))
wspec("LV", spec("LV", bw = 0.875, factors = fe("D03_RealVol"), fx = modifyList(FX, list(base_weight = 0.875))))
wspec("V1n", spec("V1n", paths = ENGF[["V1"]], fx = modifyList(FX, list(n_max = 20L))))                       # 구성 키(fixed_axes.n_max) 다름
HX <- "0123456789abcdef0123456789abcdef"
hitl <- function(k, n = 1234L) sprintf("[rf_cell_engine] 기저 캐시 적중 — base_v2_%s_%s.rds (%d행)", substr(MD5[[k]], 1, 12), HX, n)
runl <- function(k) sprintf("[rf_cell_engine] 기저 캐시 미스 — 엔진 실행: %s [absent · base_v2_%s_%s.rds]", basename(ENGF[[k]]), substr(MD5[[k]], 1, 12), HX)
wlog <- function(nm, lines) writeLines(lines, file.path(STR, "results", paste0(nm, ".log")), useBytes = TRUE)
wlog("R", c(hitl("RX0"), ln("R", "none"))); wlog("V1", c(runl("V1"), ln("V1", "none"))); wlog("V2", c(hitl("V2"), ln("V2", "none"))); wlog("Q50", c(hitl("Q50"), ln("Q50", "none")))
wlog("V1x", c(hitl("V2"), ln("V1x", "none"))); wlog("V1e", ln("V1e", "none")); wlog("V1m", c(hitl("V1"), ln("V1m", "none", months = 321L)))
wlog("W2", c(hitl("RX0"), hitl("V2"), "[rf_cell_engine] engine_blend 2개 — 공통 999행 (engine.R + engine_V2.R)", ln("W2", "none")))
wlog("W2b", c(hitl("RX0"), hitl("V2"), ln("W2b", "none"))); wlog("LV", c(hitl("RX0"), ln("LV", "D03_RealVol"))); wlog("V1n", c(hitl("V1"), ln("V1n", "none")))
for (nm in c("V1i", "V1q", "V1k", "V1l", "V1m3", "V1s", "V1h", "Q50s")) wlog(nm, c(hitl(if (startsWith(nm, "Q50")) "Q50" else "V1"), ln(nm, "none")))
art <- function(nm, H) { p <- file.path(STR, "art", nm); dir.create(p, showWarnings = FALSE); fwrite(H[, .(date, ticker, target_weight = w)], file.path(p, "04_holdings.csv")); p }
A_R <- art("A_R", H_R); A_I <- art("A_I", copy(H_R)); A_D <- art("A_D", H_S); A_Q <- art("A_Q", copy(H_S)); A_Q2 <- art("A_Q2", H_W)
CTX <- list(pre = PRE_STUB, root = STR, warm = list(ok = TRUE, status = "ok"), template = list(ok = TRUE, status = "ok", rc = 0L), tail_d = list(status = "stub"))
rdl <- function(nm) .p2_read_lines(file.path(STR, "results", paste0(nm, ".log")))
rsp <- function(nm) fromJSON(file.path(STR, "specs", paste0(nm, ".json")), simplifyVector = FALSE)
cdt <- function(comp, v, r = "R", lgv = v, lgr = r, ctx = CTX, ec = v, er = r)
  p5_construction_dt(comp, rsp(v), rsp(r), p2_parse_cell_log(rdl(lgv)), p2_parse_cell_log(rdl(lgr)), rdl(lgv), rdl(lgr), ctx, ec, er)

## N02) 기대 엔진 · 사양 엔진 · 엔진 대조
e_v1 <- p5_engine_check(rsp("V1"), rsp("R"), "V1", PRE_STUB, STR); e_x <- p5_engine_check(rsp("V1x"), rsp("R"), "V1", PRE_STUB, STR)
e_np <- p5_engine_check(rsp("V1"), rsp("R"), "V1", list(operational_pins = list(files = PRE_STUB$operational_pins$files[-2])), STR)
e_w2 <- p5_engine_check(rsp("W2"), rsp("R"), "W2", PRE_STUB, STR); e_lv <- p5_engine_check(rsp("LV"), rsp("R"), "LV", PRE_STUB, STR)
chk("N02", identical(p5_expected_engines("V2")$paths, ENGF[["V2"]]) && identical(p5_expected_engines("W2")$kind, "engine_blend") && identical(p5_expected_engines("LV")$paths, ENGF[["RX0"]]) &&
      is.null(p5_expected_engines("ZZ")) && isTRUE(e_v1$ok) && isTRUE(e_v1$uses_dt) && !isTRUE(e_x$ok) && isTRUE(e_x$checks$pins) && !isTRUE(e_x$checks$paths) && !isTRUE(e_np$ok) &&
      grepl("엔진 핀", e_np$why) && isTRUE(e_w2$ok) && isTRUE(e_w2$uses_dt) && isTRUE(e_lv$ok) && !isTRUE(e_lv$uses_dt),
    "엔진 대조 — V1 = engine_V1(핀) · V1 사양에 V2 엔진 = 경로 불일치 · 핀 없음 · W2 결합 · LV = RX0 엔진(분위 엔진 아님)")

## N03) 사양 구성 키
s_same <- p5_spec_same(rsp("V1"), rsp("R")); s_n <- p5_spec_same(rsp("V1n"), rsp("R")); s_lv <- p5_spec_same(rsp("LV"), rsp("R")); s_lv2 <- p5_spec_same(rsp("LV"), rsp("R"), c("factors", "base_weight"), "base_weight")
s_ord <- rsp("V1"); s_ord$fixed_axes <- rev(s_ord$fixed_axes); s_note <- rsp("V1"); s_note$fixed_axes$base_weight_note <- "서술"
chk("N03", isTRUE(s_same$ok) && identical(s_n$differ, "fixed_axes") && setequal(s_lv$differ, c("fixed_axes", "base_weight", "factors")) && isTRUE(s_lv2$ok) &&
      isTRUE(p5_spec_same(s_ord, rsp("R"))$ok) && isTRUE(p5_spec_same(s_note, rsp("R"))$ok), "사양 구성 키 — 같음 · n_max 다름 · LV(D03 · 0.875)는 그 키를 빼면 같음 · 키 순서 · _note 무시")

## N04) 기저 적재 줄
PL <- p5_parse_base_load(c(hitl("RX0"), runl("V1"), "[rf_cell_engine] engine_blend 2개 — 공통 999행 (engine.R + engine_V2.R)", "noise"))
pinv <- function(k) list(list(path = ENGF[[k]], md5 = MD5[[k]]))
bl1 <- p5_base_load_check(PL, pinv("RX0")); bl2 <- p5_base_load_check(PL, pinv("V1")); bl3 <- p5_base_load_check(PL, pinv("V2"))
blw <- p5_base_load_check(p5_parse_base_load(rdl("W2")), c(pinv("RX0"), pinv("V2")), blend = TRUE); blb <- p5_base_load_check(p5_parse_base_load(rdl("W2b")), c(pinv("RX0"), pinv("V2")), blend = TRUE)
wrongname <- p5_base_load_check(p5_parse_base_load(sub("engine_V1.R", "engine_V2.R", runl("V1"), fixed = TRUE)), pinv("V1"))
chk("N04", identical(PL$loads$kind, c("hit", "run")) && identical(PL$loads$engine[2], "engine_V1.R") && identical(PL$blend$n, 2L) && isTRUE(bl1$ok) && isTRUE(bl2$ok) && !isTRUE(bl3$ok) &&
      isTRUE(blw$ok) && isTRUE(blw$blend_line) && !isTRUE(blb$ok) && !isTRUE(wrongname$ok) && !isTRUE(p5_base_load_check(PL, list())$ok),
    "기저 적재 줄 — 적중 · 실행 · 결합 줄 해석 · md5 앞 12자 일치 · 다른 엔진 = 없음 · 결합 줄 없음 = 불일치 · 실행 줄 엔진 이름 다름 = 불일치 · 핀 없음")

## N05) 워밍 센티널
WD <- file.path(TMP, "p2r05_warm"); dir.create(WD, showWarnings = FALSE)
ww <- function(nm, x) { p <- file.path(WD, nm); writeLines(toJSON(x, auto_unbox = TRUE), p); p }
w_ok <- p5_warm_check(ww("a", list(cache_months = "261/261", positive_control = list(pass = TRUE, rho = 0.9), code_version = P2R05_CODE_VERSION)))
w_ok2 <- p5_warm_check(ww("b", list(cache_months = list(done = 262, total = 262), positive_control = "pass", code_version = P2R05_CODE_VERSION)))
w_inc <- p5_warm_check(ww("c", list(cache_months = "260/261", positive_control = TRUE, code_version = P2R05_CODE_VERSION)))
w_pc <- p5_warm_check(ww("d", list(cache_months = "261/261", positive_control = list(pass = FALSE), code_version = P2R05_CODE_VERSION)))
w_cv <- p5_warm_check(ww("e", list(cache_months = "261/261", positive_control = TRUE, code_version = "RP_AUTO_2002_06975/dnn_rolling/rev3")))
writeLines("status=ok", file.path(WD, "f"))
chk("N05", isTRUE(w_ok$ok) && isTRUE(w_ok2$ok) && identical(w_ok2$cache_total, 262) && !isTRUE(w_inc$ok) && !isTRUE(w_pc$ok) && !isTRUE(w_cv$ok) && grepl("code_version", w_cv$why) &&
      identical(p5_warm_check(file.path(WD, "zz"))$status, "absent") && identical(p5_warm_check(file.path(WD, "f"))$status, "unreadable"),
    "워밍 센티널 — 261/261 · {done, total} 262/262 · 미완 · 양성 대조 실패 · 판본 다름 · 없음 · JSON 아님")
## N05b) 워밍 센티널 해석(Q 10-18 정렬 2) — 측정에 묶인 사본 results/warm_sentinel.json 우선 · 없으면 night_state · 둘 다 있고 다르면 '센티널 판본 다름'(판정 = 사본)
WR <- file.path(TMP, "p2r05_warmres"); unlink(WR, recursive = TRUE); dir.create(WR)
okw <- list(cache_months = "261/261", positive_control = list(pass = TRUE), code_version = P2R05_CODE_VERSION)
writeLines(toJSON(okw, auto_unbox = TRUE), file.path(WR, "night.done")); r_n <- p5_warm_resolve(WR, file.path(WR, "night.done"))
invisible(file.copy(file.path(WR, "night.done"), file.path(WR, "warm_sentinel.json"))); r_s <- p5_warm_resolve(WR, file.path(WR, "night.done"))
writeLines(toJSON(modifyList(okw, list(cache_months = "260/261")), auto_unbox = TRUE), file.path(WR, "night.done")); r_d <- p5_warm_resolve(WR, file.path(WR, "night.done"))
r_0 <- p5_warm_resolve(file.path(WR, "nowhere"), file.path(WR, "zz")); cc_vd <- cdt("V1", "V1", ctx = modifyList(CTX, list(warm = r_d)))
chk("N05b", identical(r_n$source, "night_state/p2r05_warm.done") && isTRUE(r_n$ok) && is.na(r_n$version_tag) && identical(r_s$source, "results/warm_sentinel.json") && isTRUE(r_s$ok) &&
      identical(r_s$version_differ, FALSE) && isTRUE(r_d$ok) && identical(r_d$source, "results/warm_sentinel.json") && identical(r_d$version_tag, "센티널 판본 다름") &&
      identical(r_0$status, "absent") && !isTRUE(r_0$ok) && is.na(r_0$version_tag) && isTRUE(cc_vd$ok) && identical(cc_vd$warm$version_tag, "센티널 판본 다름") &&
      identical(cc_vd$warm$source, "results/warm_sentinel.json"),
    "워밍 센티널 해석 — 사본 없음 = night_state · 사본 우선 · 같은 판 = 꼬리표 없음 · night 재워밍(260/261)이어도 사본(261/261)으로 판정 + '센티널 판본 다름' · 둘 다 없음 = absent · ⑩(a) 기록에 꼬리표")

## N06) 템플릿 차분 대조(실행기 주입)
TD <- file.path(TMP, "p2r05_tdc"); dir.create(file.path(TD, dirname(P2R05_TEMPLATE_CHECK)), recursive = TRUE, showWarnings = FALSE); writeLines("q()", file.path(TD, P2R05_TEMPLATE_CHECK))
t0 <- p5_template_check(TD, runner = function(f) c("ok 1", "ok 2")); t1 <- p5_template_check(TD, runner = function(f) structure(c("차분 구역 밖 1줄"), status = 1L))
t2 <- p5_template_check(file.path(TMP, "nowhere")); t3 <- p5_template_check(TD, runner = function(f) stop("boom"))
chk("N06", isTRUE(t0$ok) && identical(t0$rc, 0L) && !isTRUE(t1$ok) && identical(t1$rc, 1L) && identical(t2$status, "absent") && !isTRUE(t2$ok) && !isTRUE(t3$ok),
    "템플릿 차분 대조 — rc 0 통과 · rc 1 실패 · 스크립트 없음 · 실행 오류 = 실패")

## N07) ⑩ 분위 엔진 구성 증거 — 하나씩 깬다
cc_ok <- cdt("V1", "V1"); cc_x <- cdt("V1", "V1x"); cc_e <- cdt("V1", "V1", lgv = "V1e"); cc_m <- cdt("V1", "V1", lgv = "V1m")
cc_w <- cdt("V1", "V1", ctx = modifyList(CTX, list(warm = list(ok = FALSE, status = "mismatch", why = "분위 캐시 260/261"))))
cc_t <- cdt("V1", "V1", ctx = modifyList(CTX, list(template = list(ok = FALSE, status = "fail", why = "rc 1"))))
cc_n <- cdt("V1", "V1n", lgv = "V1n"); cc_c <- cdt("V1", "V1", ec = "OTHER")
cc_rw <- cdt("RX0", "R", ctx = modifyList(CTX, list(warm = list(ok = FALSE), template = list(ok = FALSE))))             # 분위 엔진 아님 → 워밍 · 템플릿 해당 없음
cc_w2 <- cdt("W2", "W2"); cc_w2b <- cdt("W2", "W2", lgv = "W2b")
chk("N07", isTRUE(cc_ok$ok) && !isTRUE(cc_x$ok) && !isTRUE(cc_x$checks$a_engine) && !isTRUE(cc_e$ok) && !isTRUE(cc_e$checks$a_base_load_variant) && !isTRUE(cc_m$ok) &&
      !isTRUE(cc_m$checks$b_months_equal) && !isTRUE(cc_w$ok) && grepl("워밍", cc_w$why) && !isTRUE(cc_t$ok) && grepl("템플릿", cc_t$why) && !isTRUE(cc_n$checks$a_spec_same) &&
      !isTRUE(cc_c$checks$a_variant_log) && isTRUE(cc_rw$ok) && identical(cc_rw$warm$status, "not_applicable") && isTRUE(cc_w2$ok) && identical(cc_w2$blend_share, 0.5) && !isTRUE(cc_w2b$ok) &&
      is.null(cc_ok$variant_log$months),
    "⑩ — 통과 · 엔진 경로 · 기저 적재 줄 · months= · 워밍 · 템플릿 · 구성 키 · 다른 칸 로그 각각 · 분위 엔진 아님 = 워밍 · 템플릿 해당 없음 · W2 결합(몫 0.5) · 결합 줄 없음 · 보는 창 기록에 months 없음")

## N08) LV 구성 증거(P2R04 ⑩ + 엔진 핀 · 기저 적재 · months=) · 기대 몫(E3 RX0 사양 위 1회)
lvc <- function(ew, lgv = "LV") p5_construction_lowvol(rsp("LV"), rsp("R"), p2_parse_cell_log(rdl(lgv)), p2_parse_cell_log(rdl("R")), rdl(lgv), rdl("R"), CTX, "LV", "R", ew)
l_ok <- lvc(0.125); l_w <- lvc(0.5)
WCS <- file.path(TMP, "p2r05_wroot"); dir.create(file.path(WCS, "s"), recursive = TRUE, showWarnings = FALSE)
writeLines(toJSON(list(base_weight = 0.5, factors = SR3), auto_unbox = TRUE), file.path(WCS, "s/E3_RX0.json"))
chk("N08", isTRUE(l_ok$ok) && identical(l_ok$blend$device_weight, 0.125) && !isTRUE(l_w$ok) && grepl("혼합 몫", l_w$why) &&
      identical(p5_lv_expect_weight(list(list(engine = "E3", component = "RX0", path = "s/E3_RX0.json")), WCS), 0.125) && is.na(p5_lv_expect_weight(list(), WCS)),
    "LV ⑩ — 통과(몫 0.125) · 기대 몫 다름 = 불일치 · 기대 몫 = E3 RX0(0.5 · 3팩터) 위 1회 = 0.125 · RX0 없음 = NA")

## N09) 표적 정의 대조 — 실제 엔진(RP_AUTO 3판) · 변조 사본(표적 줄 · 거래일 줄) · 합성 격자(평가 라벨 함수를 엔진 블록과 대조)
yd <- p5_ydef_check(RXE, ROOT)
EX <- file.path(TMP, "p2r05_eng"); dir.create(file.path(EX, "e"), recursive = TRUE, showWarnings = FALSE)
SRC_E <- readLines(file.path(ROOT, RXE), warn = FALSE, encoding = "UTF-8")
writeLines(sub(".G[, lab_end := Close / shift(Open, .HORIZON - 1L) - 1, by = Ticker]", ".G[, lab_end := Close / shift(Open, .HORIZON) - 1, by = Ticker]", SRC_E, fixed = TRUE), file.path(EX, "e/bad1.R"), useBytes = TRUE)
writeLines(sub(".rd <- RAWDATA[Date >= .GRID_FROM & is.finite(Close) & Close > 0, .cols, with = FALSE]", ".rd <- RAWDATA[Date >= .GRID_FROM, .cols, with = FALSE]", SRC_E, fixed = TRUE), file.path(EX, "e/bad2.R"), useBytes = TRUE)
yb1 <- p5_ydef_check("e/bad1.R", EX); yb2 <- p5_ydef_check("e/bad2.R", EX)
bad_lab <- function(RAW, dates, H, has_open = TRUE) { L <- p5_labels(RAW, dates, H, has_open); L[, y_raw := y_raw * 1.0001]; L }
ybo <- p5_ydef_check(RXE, ROOT, label_fun = bad_lab)
chk("N09", isTRUE(yd$ok) && identical(yd$horizon, 5) && identical(yd$quint, 5) && isTRUE(yd$oracle$open$ok) && isTRUE(yd$oracle$no_open$ok) && isTRUE(yd$oracle$rank01_check) &&
      is.function(yd$rank01) && !isTRUE(yb1$ok) && grepl("label", yb1$why) && !isTRUE(yb2$ok) && grepl("close_rows", yb2$why) && !isTRUE(ybo$ok) && grepl("합성 격자", ybo$why) &&
      !isTRUE(p5_ydef_check(character(0), ROOT)$ok),
    "표적 정의 — 실제 엔진 줄 14 · H 5 · 분위 5 · 합성 격자(시가 있음 · 없음) · .rank01 검산 · 표적 줄 변조 · 종가 필터 변조 · 라벨 함수 변조 = 실패 · 파일 없음 = 실패")

## N10) 평가 라벨 정확값 — 거래일 공백 · 시가 0 · 종가 0 · 중복(앞 행) · 시가 없음(종가 대 종가) · H 2
cal8 <- as.Date("2021-03-01") + c(0, 1, 2, 3, 4, 7, 8, 9)
RL8 <- rbind(data.table(Date = cal8, Ticker = "A", Close = 10:17, Open = 10:17 - 0.5), data.table(Date = cal8[-3], Ticker = "B", Close = c(20, 21, 23, 24, 25, 26, 27), Open = c(19.5, 0, 22.5, 23.5, 24.5, 25.5, 26.5)))
RL8[Ticker == "B" & Date == cal8[5], Close := 0]
RL8 <- rbind(RL8, data.table(Date = cal8[3], Ticker = "A", Close = 999, Open = 999))
LB <- p5_labels(RL8, cal8, 2L); LBn <- p5_labels(RL8[, .(Date, Ticker, Close)], cal8, 2L, has_open = FALSE)
gv <- function(L, d, t) L[Date == d & Ticker == t]$y_raw
chk("N10", isTRUE(all.equal(gv(LB, cal8[1], "A"), 12 / 10.5 - 1)) && !length(gv(LB, cal8[1], "B")) && !length(gv(LB, cal8[2], "B")) && isTRUE(all.equal(gv(LB, cal8[2], "A"), 13 / 11.5 - 1)) &&
      !length(gv(LB, cal8[3], "B")) && !length(gv(LB, cal8[4], "B")) && isTRUE(all.equal(gv(LB, cal8[5], "B"), 26 / 24.5 - 1)) && !nrow(LB[Date %in% cal8[7:8]]) && isTRUE(all.equal(gv(LBn, cal8[1], "A"), 12 / 10 - 1)) &&
      isTRUE(all.equal(gv(LBn, cal8[2], "B"), 23 / 21 - 1)) && !length(gv(LBn, cal8[1], "B")) && identical(LB[Date == cal8[1] & Ticker == "A"]$dH, cal8[3]),
    "라벨 — 종가(d+2)/시가(d+1) · 시가 0 · 행 없음 · d+1 종가 0(행 제외) = 없음 · 다음 신호일 26/24.5 · 중복 = 앞 행 · 끝 = 없음 · 시가 없음 = 종가/종가")

## N11) V1 거부(순위/N ≤ 몫 · 동률 평균 · 결측)
chk("N11", identical(p5_veto(1:10, 0.2), c(TRUE, TRUE, rep(FALSE, 8))) && identical(p5_veto(c(NA, 1:10), 0.2), c(NA, TRUE, TRUE, rep(FALSE, 8))) &&
      identical(p5_veto(c(1, 1, 3, 4, 5), 0.2), c(FALSE, FALSE, FALSE, FALSE, FALSE)) && identical(p5_veto(c(1, 1, 3, 4, 5, 6, 7, 8, 9, 10), 0.2), c(TRUE, TRUE, rep(FALSE, 8))),
    "거부 — 10종 중 순위 1 · 2(0.2 경계 포함) · 결측 = NA · 동률 평균(1.5/5 = 0.3 > 0.2)")

## N12) ⑮ 꼬리 계기 — 독립 pinball · 독립 NW 와 정확 대조 · 통과 · 미달 · 설정 해석 불가
set.seed(11); dts <- seq(as.Date("2010-01-31"), by = "month", length.out = 40)
QYp <- rbindlist(lapply(seq_along(dts), function(i) data.table(Date = dts[i], Ticker = c("A", "B"), y = c(0.9, 0.8), q10 = 0.5 + rnorm(2, 0, 0.05))))
QYn <- copy(QYp)[, q10 := pmax(0, 0.02 + rnorm(.N, 0, 0.01))]
Dp <- QYp[, .(D = mean(rho(y - 0.1, 0.1) - rho(y - q10, 0.1))), by = Date]$D; Dn <- QYn[, .(D = mean(rho(y - 0.1, 0.1) - rho(y - q10, 0.1))), by = Date]$D
ip <- p5_tail_instrument(QYp, TI, NW); inn <- p5_tail_instrument(QYn, TI, NW)
ibad <- p5_tail_instrument(QYp, modifyList(TI, list(ref = "other")), NW); ilag <- p5_tail_instrument(QYp, modifyList(TI, list(nw_lag = 0)), NW)
chk("N12", isTRUE(all.equal(ip$per_date$D, Dp, tolerance = 0)) && isTRUE(abs(ip$t - nw_ref(Dp, 3L)) < 1e-10) && isTRUE(ip$pass) && isTRUE(abs(ip$margin - (ip$t - 2)) < 1e-12) &&
      identical(inn$status, "ok") && identical(inn$pass, FALSE) && isTRUE(abs(inn$t - nw_ref(Dn, 3L)) < 1e-10) && identical(ibad$status, "unmeasured") && identical(ilag$status, "unmeasured") &&
      identical(p5_tail_instrument(QYp[0], TI, NW)$status, "unmeasured") && identical(ip$q_col, "q10") && identical(ip$n_dates, 40L) &&
      !anyDuplicated(names(ip)) && !anyDuplicated(names(ibad)) && !anyDuplicated(names(p5_tail_instrument(QYp[0], TI, NW))),
    "⑮ — D_d = 독립 pinball · t = 독립 NW(3) · t > 2 통과 · 음수 = 미달(status ok) · 기준 다름 · lag 0 · 행 없음 = 미측정 · 여유 = t − 2")

## N13) D^σ · D^perm — 같은 주변분포 짝 대비 이득(정확값) · N14) R¹ · 적중 · σ 층화 · 교차율
set.seed(12)
QZ <- rbindlist(lapply(seq_along(dts), function(i) { n <- 20L; q50 <- runif(n, 0.3, 0.7); s <- runif(n, 0.05, 0.3)
  data.table(Date = dts[i], Ticker = sprintf("T%02d", seq_len(n)), y = runif(n, 0.05, 1), q50 = q50, q10 = q50 - s, q90 = pmin(1, q50 + s), s_perm = sample(s), s_sigma = sort(s)[rank(seq_len(n))],
             sigma252 = runif(n, 0.1, 0.6), q10_raw = q50 - s, q50_raw = q50, q90_raw = pmin(1, q50 + s)) }))
QZ[seq(1, .N, by = 7), q10_raw := q50_raw + 0.01]                                # 재배열 전 교차(7행마다 1)
ds <- p5_dalt(QZ, TI, NW, "s_sigma"); dp <- p5_dalt(QZ, TI, NW, "s_perm")
Ds <- QZ[, .(D = mean(rho(y - (q50 - s_sigma), 0.1) - rho(y - q10, 0.1))), by = Date]$D; Dpp <- QZ[, .(D = mean(rho(y - (q50 - s_perm), 0.1) - rho(y - q10, 0.1))), by = Date]$D
chk("N13", isTRUE(all.equal(ds$per_date$D, Ds)) && isTRUE(all.equal(dp$per_date$D, Dpp)) && isTRUE(abs(ds$t - nw_ref(Ds, 3L)) < 1e-10) && !isTRUE(all.equal(ds$mean_D, dp$mean_D)) &&
      identical(ds$s_col, "s_sigma") && identical(p5_dalt(QZ, TI, NW, "nope")$status, "unmeasured"), "D^σ · D^perm — 정확값 · 독립 NW · 둘이 다르다 · 열 없음 = 미측정")
R1 <- p5_r1_monthly(QZ); HT <- p5_hits(QZ); SS <- p5_sigma_strata(QZ, TI); CX <- p5_crossing(QZ)
r1ref <- 1 - QZ[, sum(rho(y - q10, 0.1))] / QZ[, sum(rho(y - 0.1, 0.1))]
chk("N14", isTRUE(abs(R1$q10$pooled - r1ref) < 1e-12) && identical(R1$q50$tau, 0.5) && isTRUE(abs(HT$q10$pooled - QZ[, mean(y <= q10)]) < 1e-12) && identical(nrow(SS$per_decile), 10L) &&
      isTRUE(abs(CX$crossing_pooled - mean(seq_len(nrow(QZ)) %% 7 == 1)) < 1e-12) && identical(CX$rearranged_violation_pooled, 0) && identical(CX$n_dates, 40L),
    "R¹ 합산 = 독립 · τ 0.5 · 적중 · σ 10분위 10층 · 교차율 = 재배열 전 7행마다 1 · 재배열 뒤 위반 0")

## N15) 예측표 적재 — 같음 · 보는 창 q 다름 = 중단 · 시험 창만 다름 = 사람 쪽 판 미사용 · 열 결손 · 중복 · 없음
QD <- file.path(TMP, "p2r05_qp"); unlink(QD, recursive = TRUE); dir.create(QD)
QP0 <- rbind(QZ[, P2R05_QPRED_COLS, with = FALSE], copy(QZ[Date == dts[40]])[, Date := as.Date("2023-01-31")][, P2R05_QPRED_COLS, with = FALSE])
wq <- function(d, nm, x) { dir.create(d, showWarnings = FALSE); arrow::write_parquet(x, file.path(d, nm)) }
wq(file.path(QD, "a"), "f1.parquet", QP0); wq(file.path(QD, "a"), "f2.parquet", QP0)
qv <- copy(QP0); qv[1, q10 := q10 + 1e-9]; wq(file.path(QD, "b"), "f1.parquet", QP0); wq(file.path(QD, "b"), "f2.parquet", qv)
qt <- copy(QP0); qt[Date == as.Date("2023-01-31"), q50 := q50 + 0.1]; wq(file.path(QD, "c"), "f1.parquet", QP0); wq(file.path(QD, "c"), "f2.parquet", qt)
wq(file.path(QD, "d"), "f1.parquet", QP0[, -"s_sigma"]); wq(file.path(QD, "e"), "f1.parquet", rbind(QP0, QP0[1])); dir.create(file.path(QD, "z"))
haltof <- function(expr) tryCatch({ expr; "no_halt" }, p5_halt = function(e) e$reason, error = function(e) paste("error:", conditionMessage(e)))
qa <- p5_qpred_load(file.path(QD, "a"), TAU); qc <- p5_qpred_load(file.path(QD, "c"), TAU)
chk("N15", identical(qa$status, "ok") && identical(qa$n_files, 2L) && identical(qa$full_status, "ok") && identical(qa$visible$n_dates, 40L) && max(qa$Qv$Date) < as.Date("2022-12-01") &&
      identical(haltof(p5_qpred_load(file.path(QD, "b"), TAU)), "예측표 판본 불일치(보는 창 q 열 · (신호일, 종목) 집합)") && identical(qc$status, "ok") && identical(qc$full_status, "test_window_mismatch") &&
      is.null(qc$Qall) && identical(haltof(p5_qpred_load(file.path(QD, "d"), TAU)), "예측표 열 결손") && identical(haltof(p5_qpred_load(file.path(QD, "e"), TAU)), "예측표 (신호일, 종목) 중복") &&
      identical(p5_qpred_load(file.path(QD, "z"), TAU)$status, "absent"),
    "예측표 — 두 파일 같음 · 보는 창 q10 1e-9 다름 = 평가 중단 · 시험 창만 다름 = 사람 쪽 판 미사용 · 열 결손 · 중복 = 중단 · 없음 = absent")

## N16) 상위 n(동점 = 거래대금 높은 순 · 종목코드) · 규칙 점수
tf <- p5_top_flag(c(5, 5, 4, 5, 3), c(TRUE, TRUE, TRUE, FALSE, TRUE), c(1e9, 2e9, 5e9, 9e9, NA), c("B", "A", "C", "D", "E"), 2L)
tf2 <- p5_top_flag(c(5, 5, 4), c(TRUE, TRUE, TRUE), c(1e9, 1e9, 1e9), c("B", "A", "C"), 2L)
rsV1 <- p5_rule_score("V1", c(0.1, 0.2, 0.3, 0.4, 0.5), c(5, 4, 3, 2, 1), rep(0, 5), rep(0, 5), 0.2)
chk("N16", identical(tf, c(TRUE, TRUE, FALSE, FALSE, FALSE)) && identical(tf2, c(TRUE, TRUE, FALSE)) && identical(rsV1, c(NA, 4, 3, 2, 1)) &&
      identical(p5_rule_score("V2", 1:3 / 10, 3:1, 0, 0, 0.2), 1:3 / 10) && identical(p5_rule_score("S2", 0, 0.5, 0.1, 0.2, 0.2), 0.3) && identical(p5_rule_score("N2", 0, 0.5, 0.1, 0.2, 0.2), 0.4) &&
      all(is.na(p5_rule_score("ZZ", 1:2, 1:2, 0, 0, 0.2))),
    "상위 n — 유동성 밖 제외 · 동점 = 거래대금 내림 · 같으면 종목코드 · V1 = 거부 NA 나머지 q50 · V2 = q10 · S2 = q50 − s_σ · N2 = q50 − s_perm · 모르는 규칙 = NA")

## N17) 전이 · 귀속(합성) — 거부 집합 · V2 상위 n 의 다음 보유월 하위 · 상위 5분위 적중 · 깊은 위기 달 · Jaccard · Q50 상위 n 중 거부 몫
QT <- QZ[Date %in% dts[1:2], .(Date, Ticker, q10, q50, s_perm, s_sigma)]
SPT <- QT[, .(Date, Ticker, Size = seq_len(.N) * 1e9, adv20_l1 = 5e8, r_next = -q10)]                       # 수익 = −q10 → 거부(q10 하위) = 수익 상위
PRMT <- list(veto_share = 0.2, n_max = 5L, liq_min = 2e8, n_bins = 5L)
TR <- p5_transfer(QT, SPT, PRMT, deep_ym = .p5_hold_ym(dts[2]))
chk("N17", identical(TR$n_dates, 2L) && identical(TR$veto$top, 1) && identical(TR$veto$bottom, 0) && isTRUE(all.equal(TR$v2_top$bottom, 0.8)) && identical(TR$deep$n_dates, 1L) && identical(TR$base_rate, 0.2) &&
      identical(TR$veto_set$size$mean, 4) && isTRUE(TR$q50_top_vetoed$mean >= 0) && identical(TR$width_v1$mean, 16) && is.finite(TR$veto_set$jaccard_sigma$mean),
    "전이 — 수익 = −q10 이면 거부 집합 = 상위 5분위 적중 1 · V2 상위 5 = 하위 5분위 4/5(5분위 1개 = 4종) · 깊은 위기 달 1 · 기저 0.2 · 거부 4/20 · 폭 16")

## N18) 재현(E2 보유 ↔ 예측표 규칙 상위 n) · N19) Kelley 보유 평균
H_rep <- QT[, .(date = Date + 1L, ticker = Ticker, w = as.numeric(p5_top_flag(q10, rep(TRUE, .N), rep(5e8, .N), Ticker, 5L))), by = Date][w > 0][, w := 0.2]
rp_ok <- p5_reproduce(QT, SPT, H_rep, "V2", PRMT, TAU)
H_bad <- copy(H_rep); H_bad[1, ticker := "ZZZ"]
rp_bad <- p5_reproduce(QT, SPT, H_bad, "V2", PRMT, TAU)
QK <- data.table(Date = dts[1], Ticker = c("A", "B"), q10 = c(0.1, 0.2), q50 = c(0.5, 0.3), q90 = c(0.7, 0.9))
kh <- p5_kelley_hold(QK, data.table(date = dts[1] + 1L, ticker = c("A", "B"), w = c(0.75, 0.25)), TAU)
kref <- 0.75 * (0.7 + 0.1 - 1.0) / 0.6 + 0.25 * (0.9 + 0.2 - 0.6) / 0.7
chk("N18", identical(rp_ok$share_dates_exact, 1) && identical(rp_ok$match_rate$mean, 1) && identical(rp_bad$mismatch$not_in_qpred, 1L) && isTRUE(rp_bad$match_rate$min < 1), "재현 — 일치 1 · 예측표 밖 종목 = 사유 not_in_qpred")
chk("N19", isTRUE(abs(kh$mean - kref) < 1e-12), "Kelley — (q90 + q10 − 2q50)/(q90 − q10) 보유 가중 평균")

## N20) Dimson β — 알려진 lag 구조(0.5·m_{t−1} + 0.3·m_t + 0.2·m_{t+1}) = 합 1.0 · 동시 β 만이면 0.3
set.seed(20); mm <- rnorm(3000, 0, 0.01); rr2 <- 0.5 * c(NA, mm[-3000]) + 0.3 * mm + 0.2 * c(mm[-1], NA) + rnorm(3000, 0, 1e-4)
dmb <- p5_dimson_beta(rr2, mm); ols <- unname(coef(lm(rr2 ~ mm))[2])
chk("N20", isTRUE(abs(dmb$beta - 1.0) < 0.01) && isTRUE(abs(dmb$coef$lag - 0.5) < 0.01) && isTRUE(abs(dmb$coef$lead - 0.2) < 0.01) && isTRUE(abs(ols - 0.3) < 0.02) &&
      is.na(p5_dimson_beta(1:5, 1:5)$beta) && isTRUE(abs(p2_beta_plan(dmb$beta * 0.8, dmb$beta)$k - 0.8) < 1e-12),
    "Dimson — 계수 합 1.0(lag 0.5 · lead 0.2) · 동시 OLS 0.3 · 표본 < 10 = NA · k_D = 비")

## N21) 판정 여유(값 − 문턱 · 양수 = 충족)
RLm <- list(beta_deep = list(per_crisis = data.table(k = c("a", "b"), m = c(0.5, 0.9), r = c(0.6, 0.8)), share = 0.75),
            fast = list(per_crisis = data.table(k = "a", m = 0.5, r = 0.6), share = 1), beta_asym = list(delta = -0.07),
            selection = list(decomposition = list(per_crisis = data.table(peak_date = c("a", "b"), sv = c(-0.02, -0.1), sr = c(-0.05, -0.05)), share = 0.5)))
MG <- p5_margins(RLm, list(t = 2.7, t_min = 2, margin = 0.7), 0.5, 0.03)
chk("N21", isTRUE(all.equal(MG$beta_deep$per_crisis$margin, c(0.6 - 0.03 - 0.5, 0.8 - 0.03 - 0.9))) && isTRUE(all.equal(MG$beta_deep$share_minus_majority, 0.25)) &&
      isTRUE(all.equal(MG$selection_decomp$per_crisis$margin, c(0.03, -0.05))) && isTRUE(all.equal(MG$beta_ratio$margin, 0.07)) && identical(MG$tail$margin, 0.7) &&
      identical(nrow(p5_margins(list(), list(), 0.5, 0.03)$beta_deep$per_crisis), 0L), "여유 — ③ (사본 − tol) − 변형 · 비율 − 과반 · ⑭ 분해 차 · ⑤ −Δ · ⑮ t − 2 · 빈 입력")

## N22) 위기 유형(실제 분류 파일) — 문턱 재계산(판정 창 7위기 중앙값 = 2011-05 rho_W) · 경계 · 핀 대조 · 없음 = 미분류 · 집계 두 판 · 시작 시점 분류 기록(from_top)
md5ct <- unname(tools::md5sum(file.path(ROOT, P2R05_CRISIS_TYPE_NOTE)))
pin_ok <- list(design_inputs = list(files = list(list(path = P2R05_CRISIS_TYPE_NOTE, md5 = md5ct))))
CTa <- p5_load_crisis_types(ROOT, pin_ok); CTb <- p5_load_crisis_types(ROOT, list(design_inputs = list(files = list(list(path = P2R05_CRISIS_TYPE_NOTE, md5 = "x")))))
CTc <- p5_load_crisis_types(ROOT, list()); CTz <- p5_load_crisis_types(file.path(TMP, "nowhere"), pin_ok)
PCV <- data.table(k = CRISES[, paste(peak_date, trough_date)], m = c(0.5, 0.6, 0.9, 0.7, 0.4, 0.8, 0.6), r = c(0.6, 0.7, 0.85, 0.8, 0.5, 0.75, 0.7))
CTR <- p5_crisis_type_record(PCV, CTa, deep_keys = c("2008-05-16 2008-10-24", "2011-05-02 2011-09-26", "2020-01-22 2020-03-19", "2021-06-25 2022-09-30"), tol = 0.03)
CO <- p5_load_onset(ROOT, list()); COR <- p5_crisis_type_record(PCV, CO, character(0), 0.03)
gw <- function(T, ty) { z <- T[type == ty]; if (nrow(z)) c(z$n, z$n_win) else c(0L, 0L) }
chk("N22", identical(CTa$status, "ok") && is.na(CTa$pin_tag) && isTRUE(abs(CTa$threshold - 0.334086) < 1e-12) && isTRUE(CTa$threshold_stated_matches) &&
      identical(CTa$classes[boundary == TRUE, k], "2011-05-02 2011-09-26") && identical(CTb$pin_tag, "분류 판본 다름") && grepl("핀 없음", CTc$pin_tag) && identical(CTz$status, "unclassified") &&
      identical(CTR$status, "ok") && identical(gw(CTR$as_written, "systemic"), c(4L, 2L)) && identical(gw(CTR$boundary_separate, "systemic"), c(3L, 1L)) &&
      identical(gw(CTR$boundary_separate, "boundary"), c(1L, 1L)) && identical(gw(CTR$as_written, "dispersed"), c(3L, 3L)) && identical(gw(CTR$deep_boundary_separate, "systemic"), c(2L, 1L)) &&
      identical(p5_crisis_type_record(PCV, CTz)$status, "unclassified") && identical(CO$status, "ok") && isTRUE(CO$visible_from_top_matches_table) &&
      identical(gw(COR$as_written, "from_top"), c(6L, 5L)) && identical(gw(COR$as_written, "not_from_top"), c(1L, 0L)),
    "위기 유형 — 문턱 0.334086(재계산) · 표기 0.3341 일치 · 경계 = 2011-05 · 핀 일치 · 판본 다름 · 핀 없음 · 파일 없음 = 미분류 · 경계 포함 systemic 4(승 2) · 분리 3(승 1) + 경계 1(승 1) · dispersed 3/3 · 시작 시점 분류 from_top 6(승 5) · 그 밖 1(승 0)",
    paste(format(CTa$threshold), CTa$pin_tag))

## N23) 진단 읽기 — 중심 · 희석(① 등록 + 깊은 위기 기록) · 변동성 · 꼬리 고유(S 이김 = 고유 아님 · 표 결손 = 판독 불가 · D^σ ≤ 2 = 미확인)
pcd <- function(k, m, r) data.table(k = k, m = m, r = r)
cell <- function(eng, dev, b3, crisis = b3, deep = b3, tested = TRUE, cl = paste0(eng, dev), S = 0.5, S0 = 0.5)
  list(engine = eng, device = dev, cell = cl, tested = tested, rules_computed = TRUE, pass = FALSE, verdict = "x",
       rules = list(beta_deep = list(per_crisis = b3), crisis = list(per_crisis = crisis), deep = list(per_crisis = deep)), non_inferiority = list(S = S, S_rx0 = S0))
KK <- c("a", "b", "c", "d")
V1c <- cell("E2", "V1", pcd(KK, c(0.5, 0.5, 0.5, 0.9), c(0.6, 0.6, 0.6, 0.8)), crisis = pcd(c(KK, "e"), c(0.5, 0.5, 0.5, 0.9, 0.5), c(0.6, 0.6, 0.6, 0.8, 0.6)))
Qc <- cell("E2", "Q50", pcd(KK, c(0.5, 0.7, 0.7, 0.7), c(0.6, 0.6, 0.6, 0.6)))            # a 이김
Sc <- cell("E2", "S1", pcd(KK, c(0.7, 0.5, 0.7, 0.7), c(0.6, 0.6, 0.6, 0.6)))             # b 이김
Nc <- cell("E2", "N1", pcd(c("a", "b"), c(0.7, 0.7), c(0.6, 0.6)), crisis = pcd(c("a", "e"), c(0.5, 0.5), c(0.6, 0.6)), deep = pcd("a", 0.7, 0.6))   # c 표 없음 · ① a · e 개선
rc_ <- p5_read_center(V1c, Qc, 0.03); rdl_ <- p5_read_dilution(V1c, Nc, 0.03); rv_ <- p5_read_volleak(V1c, Sc, 0.03)
TI_OK <- list(ok = TRUE); TI_NO <- list(ok = FALSE); TI_NA <- list(ok = NA)
tu_ok <- p5_read_tail_unique(V1c, Sc, Nc, Qc, TI_OK, 2, 0.03)
V1d <- cell("E2", "V1", pcd(c("a", "d"), c(0.5, 0.5), c(0.6, 0.6))); Nd <- cell("E2", "N1", pcd(c("a", "d"), c(0.7, 0.7), c(0.6, 0.6)))
tu_d <- p5_read_tail_unique(V1d, Sc, Nd, Qc, TI_OK, 2, 0.03)
chk("N23", identical(rc_$center_effect, "a") && identical(rc_$n_win, 3L) && identical(rdl_$dilution, c("a", "e")) && identical(rdl_$n_improve, 4L) && identical(rdl_$deep_record$n_improve, 3L) &&
      identical(rdl_$deep_record$dilution, character(0)) && identical(rv_$vol_proxy, "b") && identical(tu_ok$n_tail_unique, 0L) &&
      identical(tu_ok$per_crisis[crisis == "c"]$n, "unknown") && grepl("판독 불가", tu_ok$per_crisis[crisis == "c"]$names) && grepl("변동성 대리", tu_ok$per_crisis[crisis == "b"]$names) &&
      grepl("중심 표적", tu_ok$per_crisis[crisis == "a"]$names) && identical(tu_d$n_tail_unique, 1L) && identical(tu_d$per_crisis[crisis == "d"]$tail_unique, TRUE) &&
      identical(p5_read_tail_unique(V1d, Sc, Nd, Qc, TI_NO, 2, 0.03)$n_tail_unique, 0L) && identical(p5_read_tail_unique(V1d, Sc, Nd, Qc, TI_NA, 2, 0.03)$n_tail_unique, 0L) &&
      grepl("미확인", p5_read_tail_unique(V1d, Sc, Nd, Qc, TI_NO, 2, 0.03)$per_crisis[crisis == "d"]$names) &&
      identical(p5_read_center(V1c, list(rules_computed = FALSE), 0.03)$status, "unmeasured"),
    "읽기 — 중심 a · 희석 ① a · e(등록) · 깊은 위기 겹침 0(기록) · 변동성 b · 꼬리 고유: S · Q50 이긴 위기 아님 · 표 결손 = 판독 불가 · d(셋 다 미승 ∧ 꼬리 증분) = 고유 · 증분 없음 · 미측정 = 미확인")

## N24) 용량 읽기 — 8조합 · 첫 일치 · 표 밖
CB <- expand.grid(e2 = c(TRUE, FALSE), w2 = c(TRUE, FALSE), e3 = c(TRUE, FALSE))
labs <- mapply(p5_capacity_label, CB$e2, CB$w2, CB$e3)
cxp <- function(tested, pass) list(tested = tested, pass = pass, verdict = "x", construction = list(blend_share = 0.5))
chk("N24", identical(p5_capacity_label(TRUE, TRUE, TRUE), P2R05_CAPACITY_TABLE$label[1]) && identical(p5_capacity_label(TRUE, FALSE, TRUE), P2R05_CAPACITY_TABLE$label[1]) &&
      identical(p5_capacity_label(TRUE, FALSE, FALSE), P2R05_CAPACITY_TABLE$label[2]) && identical(p5_capacity_label(TRUE, TRUE, FALSE), P2R05_CAPACITY_TABLE$label[3]) &&
      identical(p5_capacity_label(FALSE, TRUE, FALSE), P2R05_CAPACITY_TABLE$label[3]) && identical(p5_capacity_label(FALSE, FALSE, FALSE), P2R05_CAPACITY_TABLE$label[4]) &&
      grepl("표 밖", p5_capacity_label(FALSE, TRUE, TRUE)) && grepl("표 밖", p5_capacity_label(FALSE, FALSE, TRUE)) && !anyNA(labs) &&
      grepl("미측정", p5_read_capacity(cxp(FALSE, FALSE), cxp(TRUE, TRUE), cxp(TRUE, TRUE))$label) && identical(p5_read_capacity(cxp(TRUE, TRUE), cxp(TRUE, FALSE), cxp(TRUE, FALSE))$label, P2R05_CAPACITY_TABLE$label[2]),
    "용량 — 같은 처치 · 용량 의존 · 구성 의존(W2 통과 ∧ E3 미달) · 이 형태 미달 · 표 밖 2조합 · 미시험 = 미측정")

## N25) LV 읽기(비교 범위 = LV 가 β 짝을 이긴 깊은 위기 · 판단 T1 C-058) — 증분 없음 · 증분 있음(tol 밖) · LV 미승 위기는 비교 밖 · LV 승리 0 = 미결 · 변형 포착 결손 = 미결 · S 증분
NOINC <- "원천 ① 증분 없음(저용량 변동성 스크린과 같음)"
Vlv <- cell("E2", "V1", pcd(c("a", "b"), c(0.50, 0.40), c(0.60, 0.60)), S = 0.62, S0 = 0.60)
LVa <- cell("E2", "LV", pcd(c("a", "b"), c(0.51, 0.42), c(0.60, 0.60)), S = 0.61, S0 = 0.60)      # LV a · b 승 · Vk 가 LV 보다 0.01 · 0.02 낮음(tol 안)
LVb <- cell("E2", "LV", pcd(c("a", "b"), c(0.51, 0.45), c(0.60, 0.60)))                           # b 에서 Vk 가 0.05 낮음(tol 밖)
LVc <- cell("E2", "LV", pcd(c("a", "b"), c(0.51, 0.59), c(0.60, 0.60)))                           # b 에서 LV 미승 → a 만 비교
LVn <- cell("E2", "LV", pcd(c("a", "b"), c(0.70, 0.70), c(0.60, 0.60)))                           # LV 승리 0
lw_a <- p5_read_lowvol(Vlv, LVa, 0.03); lw_b <- p5_read_lowvol(Vlv, LVb, 0.03); lw_c <- p5_read_lowvol(Vlv, LVc, 0.03); lw_n <- p5_read_lowvol(Vlv, LVn, 0.03)
lw_0 <- p5_read_lowvol(cell("E2", "V1", pcd(c("a", "b"), c(0.7, 0.7), c(0.6, 0.6))), LVa, 0.03); lw_u <- p5_read_lowvol(cell("E2", "V1", pcd("a", 0.5, 0.6)), LVa, 0.03)
K2 <- c("2008-05-16 2008-10-24", "2011-05-02 2011-09-26")                                          # 격리 점검 재현 R2 · R2b
lw_r2 <- p5_read_lowvol(cell("E2", "V1", pcd(K2, c(0.50, 0.50), c(0.60, 0.60))), cell("E2", "LV", pcd(K2, c(0.50, 0.65), c(0.60, 0.60))), 0.03)   # Vk 둘 다 승 · LV 2008-05 만 승 · 포착 같음
lw_r2b <- p5_read_lowvol(cell("E2", "V1", pcd(K2, c(0.70, 0.70), c(0.60, 0.60))), cell("E2", "LV", pcd(K2, c(0.51, 0.42), c(0.60, 0.60))), 0.03)  # Vk 승리 0 · LV 보다 나쁨
chk("N25", identical(lw_a$name, NOINC) && identical(lw_a$n_lv_win, 2L) && identical(lw_a$variant_wins, c("a", "b")) && isTRUE(abs(lw_a$dS_variant - 0.02) < 1e-12) && isTRUE(abs(lw_a$dS_lv - 0.01) < 1e-12) &&
      identical(lw_b$name, "LV 대비 증분 있음") && identical(lw_b$n_variant_beats_lv, 1L) && identical(lw_b$increment_kind, "beats_lv_in_lv_wins") &&
      identical(lw_c$name, "LV 대비 증분 있음") && identical(lw_c$n_lv_win, 1L) && identical(lw_c$outside_lv, "b") && identical(lw_c$increment_kind, "wins_outside_lv") &&
      identical(lw_0$name_status, "not_applicable") && grepl("해당 없음", lw_0$name) &&
      grepl("LV 대비 판독 미결\\(LV β 짝 승리 깊은 위기 0\\)", lw_n$name) && grepl("변형 포착 결손", lw_u$name) && identical(lw_u$name_status, "undetermined") &&
      grepl("LV 미시험", p5_read_lowvol(Vlv, list(rules_computed = FALSE), 0.03)$name) &&
      identical(lw_r2$name, "LV 대비 증분 있음") && identical(lw_r2$outside_lv, "2011-05-02 2011-09-26") && identical(lw_r2b$name_status, "not_applicable") && !identical(lw_r2b$name, NOINC),
    "LV 한 정의(필수 2) — Vk 승리 ⊆ LV 승리 ∧ tol 안 = '원천 ① 증분 없음' · tol 밖 이김 = 증분 있음 · LV 가 못 이긴 위기를 Vk 가 이김(재현 R2) = 증분 있음 · Vk 승리 0(재현 R2b · LV 보다 나쁨) = 해당 없음 · LV 승리 0 · 변형 포착 결손 · LV 미시험 = 미결 · S 증분 기록")

## N26) 결론 이름 — 꼬리 학습 방어 · 꼬리 회피 기계 · ⑮ 미시험 꼬리표 · LV 이름 · 희석 몫 · 단일 시드
xg <- list(rules_computed = TRUE, tested = TRUE, tail_gate = list(pass = TRUE), flags = list(r3 = TRUE, r4 = TRUE, crisis = TRUE, deep = TRUE, level = TRUE, beta_ratio = TRUE, tail = TRUE,
           s14 = TRUE, s14_measured = TRUE, sb_ok = TRUE, sb_status = "ok",
           strength = list(bull = TRUE, alpha = TRUE, cycle = TRUE, S = TRUE, path = TRUE)), reference_points = list(engine = list(deep = 0.75), market = list(deep = list(share = 0.5))))
rdg <- list(tail_unique = list(n_tail_unique = 1L, n_win = 3L, per_crisis = data.table(crisis = "d")), dilution = list(tag = "희석 몫 1/4 위기(…)", n_improve = 4L))
cn1 <- p5_conclusion(xg, rdg, list(name = NA_character_)); xm <- xg; xm$flags$strength$alpha <- FALSE; xm$tail_gate$pass <- FALSE; xm$flags$tail <- FALSE
cn2 <- p5_conclusion(xm, NULL, list(name = "원천 ① 증분 없음(저용량 변동성 스크린과 같음)")); xm2 <- xg; xm2$flags$strength$alpha <- FALSE; cn2b <- p5_conclusion(xm2, NULL, NULL)
xl <- xg; xl$flags$level <- FALSE; cn3 <- p5_conclusion(xl, rdg, NULL)
chk("N26", startsWith(cn1$name, "꼬리 학습 방어(꼬리 고유 1/3 위기)") && grepl("선택(특성) 방어", cn1$name, fixed = TRUE) && grepl("희석 몫 1/4", cn1$sentence) && grepl("단일 시드", cn1$sentence) &&
      identical(cn2$name, "선택(특성) 방어") && !("꼬리 회피 기계(방어만 · 복리 없음)" %in% cn2$tags) && any(grepl("미시험\\(꼬리 계기\\)", cn2$tags)) && "원천 ① 증분 없음(저용량 변동성 스크린과 같음)" %in% cn2$tags &&
      "꼬리 회피 기계(방어만 · 복리 없음)" %in% cn2b$tags && isTRUE(cn2b$machine) && identical(cn2$machine, FALSE) &&
      grepl("해당 없음", cn2$sentence) && !grepl("꼬리 학습", cn3$name) && grepl("노출\\(β\\) 방어", cn3$name) && grepl("미시험", p5_conclusion(list(rules_computed = FALSE, why = "x"))$name),
    "결론 — 방어 성립 ∧ 꼬리 고유 1 = '꼬리 학습 방어' · 알파 미달(⑮ 통과) = 꼬리 회피 기계 · 알파 미달 ∧ ⑮ 미달 = 미시험(계기)이 먼저(꼬리 회피 기계 아님) · LV 이름 · E3 희석 해당 없음 · ⑤ 수준 역행이면 꼬리 학습 이름 없음")

## N27) ⑮ 시험 조건 문 — 판정된 변형 칸 + ⑮ 미달 = untested_tail_instrument(판정 계산 유지) · 통과 = 그대로 · 이미 미시험 = 그대로
xt <- list(engine = "E2", device = "V1", tested = TRUE, rules_computed = TRUE, pass = TRUE, verdict = "pass", rules = list(x = 1), tbl = data.table(engine = "E2", device = "V1", tested = TRUE, pass = TRUE, excluded = FALSE, verdict = "pass"))
g1 <- p5_apply_tail_gate(xt, list(status = "ok", t = 1.2, t_min = 2, pass = FALSE)); g2 <- p5_apply_tail_gate(xt, list(status = "ok", t = 3, t_min = 2, pass = TRUE))
g3 <- p5_apply_tail_gate(xt, list(status = "unmeasured", why = "예측표 없음", pass = FALSE)); g4 <- p5_apply_tail_gate(modifyList(xt, list(tested = FALSE, verdict = "untested")), list(status = "ok", t = 1, pass = FALSE))
chk("N27", identical(g1$verdict, "untested_tail_instrument") && identical(g1$tested, FALSE) && identical(g1$pass, FALSE) && isTRUE(g1$rules_computed) && identical(g1$tbl$verdict, "untested_tail_instrument") &&
      grepl("반증 아님", g1$why) && identical(g2$verdict, "pass") && isTRUE(g2$tested) && grepl("예측표 없음", g3$why) && identical(g4$verdict, "untested"),
    "⑮ 문 — 미달 = 꼬리 계기 미시험(판정 계산 유지 · 반증 아님) · 통과 = 그대로 · 미측정 사유 · 이미 미시험 = 그대로")

## N28) τ_D 경계 — 보는 창 RAW = τ 당일 포함 · τ 뒤 가격으로 라벨 안 만듦 · 보는 창 신호일 = τ 달 첫날 전
RAWS <- local({ set.seed(31); d <- seq(as.Date("2021-01-04"), as.Date("2021-09-30"), by = "day"); d <- d[!(as.POSIXlt(d)$wday %in% c(0L, 6L))]
  R <- CJ(Ticker = sprintf("A%06d", 1:30), Date = d); R[, ret := rnorm(.N, 0, 0.02)]; R[, Close := 100 * cumprod(1 + ret), by = Ticker]
  R[, Open := Close * (1 + rnorm(.N, 0, 0.005))][, Vol := round(runif(.N, 1e4, 1e5))][, Size := Close * 1e6][, ret := NULL]; R[] })
tauT <- as.Date("2021-07-30")
cutT <- p5_visible_cut(RAWS, tauT); QVS <- p5_visible_signals(data.table(Date = as.Date(c("2021-06-30", "2021-07-01", "2021-07-30")), x = 1), tauT)
chk("N28", isTRUE(max(cutT$Date) == tauT) && identical(nrow(cutT[Date == tauT]), 30L) && !nrow(p5_labels(cutT, tauT, 5L)) && identical(nrow(p5_labels(RAWS, tauT, 5L)), 30L) &&
      identical(QVS$Date, as.Date("2021-06-30")) && identical(nrow(p5_visible_signals(data.table(Date = as.Date("2022-11-30")), TAU)), 1L) &&
      identical(nrow(p5_visible_signals(data.table(Date = as.Date("2022-12-29")), TAU)), 0L),
    "τ_D — 보는 창 RAW 에 τ 당일 포함 · τ 뒤 가격 없는 라벨 = 없음(전 구간이면 30) · 보는 창 신호일 = τ 달 첫날 전(2022-11-30 포함 · 2022-12-29 제외)")

## N32) 꼬리 블록 끝까지(합성 RAW · 예측표 · 실제 엔진 표적 정의) — ⑮ · 기록 · D^σ 열 · 교차율 · 전이
sig <- RAWS[, .(Date = max(Date)), by = .(ym = format(Date, "%Y-%m"))]$Date
QS <- rbindlist(lapply(sig, function(dd) { set.seed(as.integer(dd)); n <- 30L; q50 <- runif(n, 0.3, 0.7); s <- runif(n, 0.05, 0.25)
  data.table(Date = dd, Ticker = sprintf("A%06d", 1:30), q10 = q50 - s, q50 = q50, q90 = pmin(1, q50 + s), q10_raw = q50 - s, q50_raw = q50, q90_raw = pmin(1, q50 + s),
             s_perm = sample(s), s_sigma = sort(s)[rank(runif(n))], sigma252 = runif(n, 0.1, 0.5)) }))
QS[seq(1, .N, by = 9), q10_raw := q50_raw + 0.02]
YDS <- yd; YDS$veto_share <- 0.2
PRMS <- list(veto_share = 0.2, n_max = 5L, liq_min = 0, n_bins = 5L, liq = p5_liq_from(RAWS))
TB_ <- p5_tail_block(QS, RAWS, YDS, TI, NW, PRMS, deep_ym = "2021-04", "visible")
labS <- p5_labels(RAWS, unique(QS$Date), 5L); QYS <- p5_attach_y(QS, labS, yd$rank01)
chk("N32", identical(TB_$instrument$status, "ok") && identical(TB_$instrument$n_dates, uniqueN(labS$Date)) && identical(TB_$records$d_sigma$s_col, "s_sigma") &&
      isTRUE(abs(TB_$records$d_sigma$mean_D - p5_dalt(QYS, TI, NW, "s_sigma")$mean_D) < 1e-12) && identical(TB_$records$d_perm$s_col, "s_perm") &&
      isTRUE(abs(TB_$records$crossing$crossing_pooled - mean(seq_len(nrow(QS)) %% 9 == 1)) < 1e-12) && identical(TB_$records$transfer$status, "ok") && !is.null(TB_$SP) &&
      identical(TB_$records$labels$horizon, 5) && all(QYS$y > 0 & QYS$y <= 1) && identical(p5_tail_block(QS, RAWS, list(ok = FALSE, why = "x"), TI, NW, PRMS)$instrument$status, "unmeasured") &&
      identical(TB_$records$d_width$status, "ok") && identical(TB_$records$d_hist$status, "unmeasured"),
    "꼬리 블록 — ⑮ 신호일 = 라벨 있는 신호일 · D^σ = s_sigma · D^perm = s_perm · 교차율 · 전이 · 신호일 패널 · y ∈ (0, 1] · 표적 정의 실패 = 미측정 · D^w 기록 · s_hist 없음 = D^H 미측정")

## N29) 판정 1칸 조기 경로(스텁 루트 · 계약 호출 없음)
RS2 <- file.path(STR, "results")
ES <- list(status = "ok", date = "2005-01-31")
evd <- function(a, es = ES) list(status = "evaluated", artifacts = a, effective_start = es)
X0 <- list(root = STR, res = RS2, out = RS2, env = list(E = list(ta_resolve_artifact = function(d) list(dir = d))), fs = FS, tau = TAU, ea = new.env())
cR <- list(code = "R", path = "specs/R.json"); cv <- function(code, sp) list(code = code, path = paste0("specs/", sp, ".json"))
JO <- function(...) modifyList(list(role = "judge", ctx = CTX, tail_ok = TRUE), list(...))
DO <- function(...) modifyList(list(role = "diagnostic", ctx = CTX, tail_ok = TRUE), list(...))
qok <- list(status = "ok", dir = A_Q2, cell = "Q50"); qsame <- list(status = "ok", dir = A_Q, cell = "Q50")
U <- list(
  a = p5_eval_pair_safe(X0, "E2", "V1", cv("V1", "V1"), cR, list(status = "measure_failed"), evd(A_R), JO()),
  b = p5_eval_pair_safe(X0, "E2", "V9", cv("V1", "V1"), cR, evd(A_D), evd(A_R), JO()),
  c = p5_eval_pair_safe(X0, "E2", "V1", cv("V1", "V1"), cR, evd(A_D), evd(A_R), DO()),
  d = p5_eval_pair_safe(X0, "E2", "V1", cv("V1x", "V1x"), cR, evd(A_D), evd(A_R), JO()),
  e = p5_eval_pair_safe(X0, "E2", "V1", cv("V1e", "V1"), cR, evd(A_D), evd(A_R), JO()),
  f = p5_eval_pair_safe(X0, "E2", "V1", cv("V1i", "V1"), cR, evd(A_D), evd(A_R), JO(ctx = modifyList(CTX, list(warm = list(ok = FALSE, status = "absent", why = "워밍 센티널 없음")))) ),
  g = p5_eval_pair_safe(X0, "E2", "V1", cv("V1i", "V1"), cR, evd(A_D), evd(A_R), JO(ctx = modifyList(CTX, list(template = list(ok = FALSE, status = "fail", why = "rc 1"))))),
  h = p5_eval_pair_safe(X0, "E2", "V1", cv("V1m", "V1"), cR, evd(A_D), evd(A_R), JO()),
  i = p5_eval_pair_safe(X0, "E2", "V1", cv("V1i", "V1"), cR, evd(A_I), evd(A_R), JO(q50 = qok)),
  j = p5_eval_pair_safe(X0, "E2", "V1", cv("V1q", "V1"), cR, evd(A_D), evd(A_R), JO(q50 = qsame)),
  k = p5_eval_pair_safe(X0, "E2", "V1", cv("V1k", "V1"), cR, evd(A_D), evd(A_R), JO(q50 = list(status = "unmeasured", why = "Q50 지문 ≠ 구성 판정 칸 지문"))),
  l = p5_eval_pair_safe(X0, "E2", "V1", cv("V1l", "V1"), cR, evd(A_D), evd(A_R), JO(q50 = qok)),
  m = p5_eval_pair_safe(X0, "E3", "V1", cv("V1m3", "V1"), cR, evd(A_D), evd(A_R), JO(q50 = list(status = "not_applicable", why = "같은 구성 Q50 칸 없음"))),
  n = p5_eval_pair_safe(X0, "E2", "Q50", cv("Q50s", "Q50"), cR, evd(A_I), evd(A_R), DO()),
  o = p5_eval_pair_safe(X0, "E2", "LV", cv("LV", "LV"), cR, evd(A_D), evd(A_R), DO(expect_weight = 0.125)),
  o2 = p5_eval_pair_safe(X0, "E2", "LV", cv("LV", "LV"), cR, evd(A_D), evd(A_R), DO(expect_weight = 0.5)),
  p = p5_eval_pair_safe(X0, "E2", "V1", cv("V1s", "V1"), cR, evd(A_D, list(status = "insufficient", date = NA)), evd(A_R), JO()),
  q = p5_eval_pair_safe(local({ x <- X0; x$env <- list(E = list()); x }), "E2", "V1", cv("V1h", "V1"), cR, evd(A_D), evd(A_R), JO()),
  r = p5_eval_pair_safe(X0, "E2", "W2", cv("W2", "W2"), cR, evd(A_D), evd(A_R), DO()),
  r2 = p5_eval_pair_safe(X0, "E2", "W2", cv("W2b", "W2"), cR, evd(A_D), evd(A_R), DO()),
  s = p5_eval_pair_safe(X0, "E2", "V1", cv("V1l", "V1"), cR, evd(A_D), evd(A_R), JO(q50 = qok, expect_cell_rx0 = "R")))
wy <- function(z) U[[z]]$why %||% ""
chk("N29", all(vapply(U, function(u) !isTRUE(u$tested) && identical(u$verdict, "untested") && identical(u$pass, FALSE), logical(1))) &&
      grepl("평가 상태", wy("a")) && grepl("표에 없는 부품", wy("b")) && grepl("역할 불일치", wy("c")) && grepl("엔진 경로", wy("d")) && grepl("기저 적재 줄", wy("e")) &&
      grepl("워밍", wy("f")) && grepl("템플릿", wy("g")) && grepl("months=", wy("h")) && grepl("무처치\\(⑩\\)", wy("i")) && grepl("V1 = Q50", wy("j")) && grepl("V1 전달량", wy("k")) &&
      grepl("보는 창 패킷 없음", wy("l")) && identical(U$l$delivery_q50$status, "ok") && grepl("보는 창 패킷 없음", wy("m")) && identical(U$m$delivery_q50$status, "not_applicable") &&
      grepl("보는 창 패킷 없음", wy("n")) && identical(U$n$treatment_delivered, FALSE) && grepl("보는 창 패킷 없음", wy("o")) && identical(U$o$construction$flavor, "lowvol_screen") &&
      grepl("혼합 몫", wy("o2")) && grepl("실효 시작", wy("p")) && grepl("평가 오류", wy("q")) && grepl("보는 창 패킷 없음", wy("r")) && grepl("기저 적재 줄", wy("r2")) &&
      grepl("보는 창 패킷 없음", wy("s")) && isTRUE(U$s$construction$ok),
    "판정 1칸 — 상태 · 표 밖 · 역할 · 엔진 경로 · 적재 줄 · 워밍 · 템플릿 · months= · 무처치 · V1 = Q50 · Q50 미측정 · Q50 다름 → 패킷 · E3 해당 없음 · 진단 무처치 계속 · LV · LV 몫 · 실효 시작 · 오류 · W2 · W2 결합 줄 · opts 부분 일치 없음",
    paste(vapply(names(U), function(z) sprintf("%s:%s", z, substr(wy(z), 1, 40)), ""), collapse = " | "))

## N30) 센티널 형식(P2R04 형식) · 측정 ok 셈
SEN <- file.path(TMP, "p2r05_sent", "x.done"); p5_sentinel_write(SEN, "evaluated", 0L, "ok=12/14")
MOK <- file.path(TMP, "p2r05_mok"); dir.create(MOK, showWarnings = FALSE); writeLines('{"ok": true}', file.path(MOK, "A.json")); writeLines('{"ok": false}', file.path(MOK, "B.json"))
chk("N30", grepl("^status=evaluated rc=0 at=[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2} ok=12/14$", readLines(SEN)) &&
      identical(p5_measured_ok(MOK, list(list(code = "A"), list(code = "B"), list(code = "C"))), "ok=1/3"), "센티널 — 'status=… rc=… at=YYYY-MM-DD HH:MM:SS ok=…/…' · 측정 ok 1/3")

## N31) 규칙 문장(round_rules.R) — 승계 키 = P2R04 사전등록 문장 그대로 · ⑮ · 결합 금지 · 희석 분리 · LV · R7 두 성분 · 칸 수
RR <- p2r05_rules(ROOT, BCP); P4R <- fromJSON(file.path(ROOT, P2R05_P2R04_PREREG), simplifyVector = FALSE)$rules
chk("N31", all(vapply(P2R05_RULES_INHERITED, function(k) identical(RR[[k]], P4R[[k]]), logical(1))) && grepl("NW\\(3\\) t > 2", RR$tail_instrument) &&
      grepl("결합 금지: P2R03 D5 · D7 · P2R04 H2 · W2 와의 위기별 승패 합집합으로 결합 · 선택 규칙을 짜지 않는다", RR$conclusion_scope, fixed = TRUE) &&
      grepl("① 위기 수 겹침(등록 판독) · 깊은 위기 겹침은 따로 기록", RR$diagnostics_reading, fixed = TRUE) && grepl("원천 ① 증분 없음(저용량 변동성 스크린과 같음)", RR$conclusion_names, fixed = TRUE) &&
      grepl("방어 성분 잡음이면 P2 정지(paused) · 도훈 보고 대상(P2R03 · P2R04 방어 성분 연속 2 — 체계 §4)", RR$r7_reading, fixed = TRUE) &&
      grepl("E2 묶음 11칸 → E3 묶음 5칸", RR$vintage_group, fixed = TRUE) && grepl("변형 칸 4", RR$round_verdict, fixed = TRUE) && grepl("10칸은 분모 밖", RR$round_verdict, fixed = TRUE) &&
      grepl("Dimson", RR$record) && grepl("판정 여유", RR$record) && grepl("crisis_type_classify.json", RR$record, fixed = TRUE) && startsWith(RR$record, P4R$record) &&
      startsWith(RR$failure_semantics, P4R$failure_semantics) && grepl("연속 3 이면 P2 정지", RR$r7_reading, fixed = TRUE) && grepl("D^σ ∧ D^w ∧ D^H", RR$instrument_action, fixed = TRUE) &&
      grepl("V2 상승 β > S2 상승 β", RR$expectations_appendix_a, fixed = TRUE) && grepl("P2 정지 보고 4요소", RR$pause_report, fixed = TRUE) &&
      grepl("V1 = Q50(같은 추첨 중앙값) 순위 보존형", RR$vocabulary, fixed = TRUE) && grepl("RX0S", RR$diagnostics, fixed = TRUE) && grepl("같은 추첨 미확인", RR$selection, fixed = TRUE) &&
      grepl("판정어(defense_but_strength_or_path) · 결론 꼬리표가 함께 쓰는 한 정의", RR$conclusion_names, fixed = TRUE) && grepl("β 비대칭 미달", RR$conclusion_names, fixed = TRUE) &&
      grepl("⊆ LV 승리 위기", RR$conclusion_names, fixed = TRUE) && grepl("Vk 승리 위기 ⊆ LV 승리 위기", RR$diagnostics_reading, fixed = TRUE) &&
      !grepl("단일 시드라 시드 잡음 띠가 없다", RR$conclusion_scope, fixed = TRUE) && !grepl("사전 분류된 위기 유형 기전", RR$conclusion_scope, fixed = TRUE) &&
      grepl("위기 유형은 사후로만 보인다(crisis_type_classify · crisis_type_asof — 시작 시점 · 진행 중 as-of 모두 못 가름) → 결합 기전 없음", RR$conclusion_scope, fixed = TRUE) &&
      grepl("P4/A/BOOK 전 도훈 확인", RR$conclusion_scope, fixed = TRUE) && grepl("재시드 칸 2", RR$conclusion_scope, fixed = TRUE) &&
      grepl("측정에 묶인 판 1개", RR$tail_instrument, fixed = TRUE) && grepl("예측표 미묶임", RR$failure_semantics, fixed = TRUE) &&
      !grepl("꼭대기 시작 위기", RR$record, fixed = TRUE) && grepl("state_turn_classify.md", RR$record, fixed = TRUE) && grepl("E3 = 해당 없음", RR$selection, fixed = TRUE) &&
      grepl("수평 불일치", RR$conclusion_names, fixed = TRUE) && grepl("유동성 십분위는 Q50 · S1 · S2 만", RR$diagnostics, fixed = TRUE) &&
      grepl("이 학습 설정은 종목 왼꼬리를 배우지 못함(계기 실패 · 원천 ① 반증 아님)", RR$instrument_action, fixed = TRUE) && !grepl("원천 ① 이 학습 설정 반증", RR$instrument_action, fixed = TRUE),
    "규칙 문장 — 승계 11키 동일 · ⑮ · 결합 금지 · 희석 분리 · LV · R7 방어 성분(기계형 · 연속 3) · 계기 → 다음 행동(D^σ ∧ D^w ∧ D^H) · 부록 A · 정지 보고 4요소 · V1 정정 · RX0S · 같은 추첨 · 묶음 11 · 5 · 분모 밖 10 · 격리 점검 v1(꼬리 회피 기계 한 정의 · LV ⊆ · 옛 문장 둘 정정 · 예측표 묶음 · 이름 정리 · E2 같은 추첨 · 수평 · 유동성 범위 · A 문구)")

## N31b) 규칙 문장 v2(격리 점검 v2) — ⑮ 셀 로그 대조 · 실패 의미 · ⑤ 괄호(방어 이름 = ⑤ 수준 · Δ 만 미달 = 이름 유지) · ⑤ 수준만 미달 = 통과 · 첫 일치 · 사유 문자열
chk("N31b", grepl("셀 로그 대조(격리 교차 점검 v2 필수 1", RR$tail_instrument, fixed = TRUE) && grepl("'[DT qpred] path='", RR$tail_instrument, fixed = TRUE) &&
      grepl("셀 로그 없는 칸 = 미측정", RR$tail_instrument, fixed = TRUE) && grepl("셀 로그 '[DT qpred] path=' 줄의 경로 · md5 ≠ 묶인 판", RR$failure_semantics, fixed = TRUE) &&
      grepl("⑮ 예측표 셀 로그 대조 불가", RR$failure_semantics, fixed = TRUE) && grepl("Δ 만 미달인 칸은 방어 이름이 남는다", RR$conclusion_names, fixed = TRUE) &&
      !grepl("'방어' 이름 조건", RR$conclusion_names, fixed = TRUE) && grepl("⑤ 수준만 미달이고 나머지가 모두 통과면 그 칸은 통과다", RR$conclusion_names, fixed = TRUE) &&
      grepl("⑥ 등이 함께 미달이어도", RR$conclusion_names, fixed = TRUE) && grepl("첫 일치(격리 교차 점검 v2 권고 3 · 코드 순서)", RR$conclusion_names, fixed = TRUE) &&
      grepl("⑮ 예측표 셀 로그 대조 불가", RR$conclusion_names, fixed = TRUE) && grepl("이름은 첫 일치로 붙는다", RR$diagnostics_reading, fixed = TRUE) &&
      identical(p5_load_onset(file.path(TMP, "nowhere"), list())$why, "시작 시점 분류 파일 없음") && !any(grepl("꼭대기 시작", readLines(EVF, warn = FALSE, encoding = "UTF-8"), fixed = TRUE)),
    "규칙 문장 v2 — ⑮ 셀 로그 대조 · 셀 로그 없음 = 미측정 · 실패 의미(중단 · 대조 불가 꼬리표) · ⑤ 괄호 = 코드(방어 이름 ⑤ 수준 · Δ 만 미달 = 이름 유지) · ⑤ 수준만 미달 = 통과 · 첫 일치 · LV 첫 일치 · 사유 '시작 시점 분류'")

## N33) 시드 띠 · 시드 미결 꼬리표 · R7 꼬리표 수(판단 T1 C-054) — 재시드 칸 없음 = '시드 띠 미측정'
RS1 <- list(engine = "E2", device = "RX0S", cell = "P2R05_E2_RX0S", rules_computed = TRUE, tested = TRUE,
            rules = list(crisis = list(per_crisis = pcd(c("a", "b", "c"), c(0.62, 0.55, 0.80), c(0.60, 0.60, 0.80)))), non_inferiority = list(S = 0.55, S_rx0 = 0.60))
BD <- p5_seed_band(RS1)
Vsd <- list(engine = "E2", device = "V1", cell = "P2R05_E2_V1", rules_computed = TRUE, tested = TRUE,
            rules = list(beta_deep = list(per_crisis = pcd(c("a", "b"), c(0.50, 0.40), c(0.51, 0.50))), fast = list(per_crisis = pcd(c("a", "c"), c(0.50, 0.70), c(0.51, 0.75)))),
            non_inferiority = list(S = 0.63, S_rx0 = 0.60))
ST <- p5_seed_tags(Vsd, BD); ST0 <- p5_seed_tags(Vsd, p5_seed_band(list(rules_computed = FALSE, why = "재시드 칸 없음")))
STC <- p5_seed_tag_counts(list(c(Vsd, list(seed_tags = ST)), list(device = "V2", seed_tags = ST0)), c("V1", "V2"))
chk("N33", isTRUE(all.equal(BD$per_crisis$band, c(0.02, 0.05, 0))) && isTRUE(abs(BD$S_band - 0.05) < 1e-12) && identical(ST$deep[crisis == "a"]$undetermined, TRUE) &&
      identical(ST$deep[crisis == "b"]$undetermined, FALSE) && identical(ST$n_fast_undetermined, 1L) && isTRUE(ST$S$undetermined) && "S 시드 미결" %in% ST$tags &&
      any(grepl("시드 미결 1/2 깊은 위기", ST$tags)) && identical(ST0$tags, "시드 띠 미측정") && identical(STC$n_cells_with_band, 1L) && identical(STC$n_deep_undetermined, 1L) &&
      identical(STC$n_S_undetermined, 1L) && grepl("일부 칸", STC$tag) && identical(p5_seed_band(list(rules_computed = FALSE))$tag, "시드 띠 미측정"),
    "시드 띠 — 위기별 |RX0S − RX0| · S 띠 · 간격 0.01 < 띠 0.02 = 시드 미결 · 0.10 > 0.05 = 결정 · 빠른 급락 · |S 증분| 0.03 < 0.05 = S 시드 미결 · 재시드 없음 = 미측정 · R7 꼬리표 수")

## N34) D^w(대칭 폭 짝 q̂50 − (q̂90 − q̂50) · 정확값 · 독립 NW) — 비대칭 합성(q90 폭 ≠ q10 폭)
set.seed(34); QW <- copy(QZ)[, q90 := pmin(1, q50 + runif(.N, 0.02, 0.4))]
dw <- p5_dwidth(QW, TI, NW); Dw <- QW[, .(D = mean(rho(y - (q50 - (q90 - q50)), 0.1) - rho(y - q10, 0.1))), by = Date]$D
chk("N34", isTRUE(all.equal(dw$per_date$D, Dw)) && isTRUE(abs(dw$t - nw_ref(Dw, 3L)) < 1e-10) && identical(dw$ref, "q50 - (q90 - q50)") && isTRUE(abs(dw$t_minus_t_min - (dw$t - 2)) < 1e-12) &&
      identical(p5_dwidth(QW[, -"q90"], TI, NW)$status, "unmeasured"), "D^w — 정확값 · 독립 NW · 여유 t − 2 · q90 없음 = 미측정")

## N35) D^H(s_hist · 선택 열) · 꼬리 증분(D^σ ∧ D^w ∧ D^H 모두 t > 2 · 하나라도 미측정 = NA)
set.seed(35); QH <- copy(QZ)[, s_hist := sample(q50 - q10), by = Date]
dh <- p5_dalt(QH, TI, NW, "s_hist"); Dh <- QH[, .(D = mean(rho(y - (q50 - s_hist), 0.1) - rho(y - q10, 0.1))), by = Date]$D
okt <- function(t) list(status = "ok", t = t)
inc1 <- p5_tail_increment(okt(2.5), okt(3), okt(2.1), 2); inc2 <- p5_tail_increment(okt(2.5), okt(1.9), okt(2.1), 2); inc3 <- p5_tail_increment(okt(2.5), okt(3), list(status = "unmeasured"), 2)
chk("N35", isTRUE(all.equal(dh$per_date$D, Dh)) && identical(dh$s_col, "s_hist") && isTRUE(inc1$ok) && identical(inc2$ok, FALSE) && is.na(inc3$ok) &&
      identical(p5_dalt(QZ, TI, NW, "s_hist")$status, "unmeasured") && identical(p5_tail_increment(okt(2), okt(3), okt(3), 2)$ok, FALSE),
    "D^H — 정확값(q̂50 − s_hist) · 꼬리 증분 = 셋 다 > 2 · 하나 ≤ 2 = 거짓 · 하나 미측정 = NA · s_hist 없음 = 미측정 · t = 2 = 거짓(엄격)")

## N36) 계기 → 다음 행동 표(A · B · C · D · 첫 일치 · 맞는 줄 모두 · 미측정)
vcell <- function(dev, ok3, st = "ok") list(device = dev, cell = paste0("E2", dev), rules_computed = TRUE, rules = list(beta_deep = list(status = st, ok = ok3)))
OA <- list(vcell("V1", FALSE), vcell("V2", FALSE)); OD <- list(vcell("V1", TRUE), vcell("V2", FALSE))
t_p <- list(status = "ok", pass = TRUE); t_f <- list(status = "ok", pass = FALSE); t_u <- list(status = "unmeasured", pass = FALSE)
a1 <- p5_action_row(t_f, list(ok = TRUE), OA, 2); a2 <- p5_action_row(t_p, list(ok = FALSE), OA, 2); a3 <- p5_action_row(t_p, list(ok = TRUE), OA, 2)
a4 <- p5_action_row(t_p, list(ok = TRUE), OD, 2); a5 <- p5_action_row(t_p, list(ok = FALSE), OD, 2); a6 <- p5_action_row(t_u, list(ok = TRUE), OD, 2); a7 <- p5_action_row(t_p, list(ok = NA), OA, 2)
chk("N36", identical(a1$row, "A") && identical(a2$row, "B") && identical(a3$row, "C") && identical(a4$row, "D") && identical(a5$row, "B") && identical(a5$matches, c("B", "D")) &&
      is.na(a6$row) && grepl("계기 미측정", a6$note) && is.na(a7$row) && grepl("미측정", a7$note) && identical(a4$r3_pass_cells, "E2V1") && identical(a1$action, P2R05_ACTION_TABLE$action[1]) &&
      grepl("V3", a3$action), "다음 행동 — ⑮ 미달 = A · 증분 없음 = B · 증분 ∧ ③ 미달 = C · ③ 통과 = D · B 와 D 동시 = 첫 일치 B(둘 다 기록) · 계기 미측정 · 증분 미측정 = 줄 없음")

## N37) 같은 추첨 판독(철학 P1 C-063) — k' = β(V)/β(Q50) · Q50 × k' 사본 승패 · ⑤ Δ(V − Q50) · ⑥ 강세
pk <- function(beta, bd, bu, crises, bulls = list(), ucm = 0.9) list(behavior = list(stats = list(beta = beta, beta_down = bd, beta_up = bu), crises = crises, bull_phases = bulls,
                                                                             summary = list(bull_up_capture_median = ucm)))
CRk <- data.table(peak_date = c("2008-05-16", "2011-05-02", "2020-01-22"), trough_date = c("2008-10-24", "2011-09-26", "2020-03-19"))
PMs <- pk(0.8, 0.7, 0.9, J(copy(CRk)[, dd_capture := c(0.50, 0.70, 0.60)]), bm5, 0.9)
PQs <- pk(1.0, 1.0, 0.95, J(copy(CRk)[, dd_capture := c(0.80, 0.75, 0.85)]), br5, 0.95)
PRs <- pk(0.9, 1.1, 0.9, J(copy(CRk)[, dd_capture := c(0.9, 0.9, 0.9)]))
PQBs <- pk(0.8, 0.8, 0.76, J(copy(CRk)[, dd_capture := c(0.64, 0.60, 0.68)]))
sdp <- p5_same_draw_plan(PMs, PQs, PRs)
sdc <- p5_same_draw_core(PMs, PQs, PQBs, deep = c("2008-05-16 2008-10-24", "2020-01-22 2020-03-19"), fast_keys = c("2008-05-16 2008-10-24", "2011-05-02 2011-09-26"),
                         tol = 0.03, maj = 0.5, ratio = 0.8, uc_floor = 0.55)
chk("N37", isTRUE(abs(sdp$k - 0.8) < 1e-12) && identical(sdp$mode, "scaled") && identical(sdp$comparator, "Q50 × k'") && isTRUE(abs(sdp$k_rx0 - 0.8 / 0.9) < 1e-12) &&
      identical(p5_same_draw_plan(pk(1.2, 1, 1, list()), PQs, PRs)$comparator, "Q50(k' ≥ 1)") && identical(sdc$deep$share, 1) && isTRUE(sdc$deep$majority) && identical(sdc$fast$share, 0.5) &&
      identical(sdc$fast$majority, FALSE) && isTRUE(sdc$beta_ratio$ok) && isTRUE(abs(sdc$beta_ratio$delta - (0.7 / 0.9 - 1 / 0.95)) < 1e-12) && identical(sdc$bull$share, 0.5) && identical(sdc$bull$ok, FALSE) &&
      identical(p5_same_draw_core(PMs, PQs, NULL, "2008-05-16 2008-10-24", character(0), 0.03, 0.5, 0.8, 0.55)$deep$n_pair, 0L),
    "같은 추첨 — k' 0.8(β_V/β_Q50 · k 0.889 아님) · k' ≥ 1 = Q50 · 깊은 위기 2/2 과반 · 빠른 급락 1/2 = 과반 아님 · ⑤ Δ = V − Q50 · ⑥ 0.5 · 사본 없음 = 짝 0")

## N38) 선택 꼬리표(같은 추첨) — 과반 = 꼬리표 없음 · 과반 미만 = '같은 추첨 미확인' · 측정 칸 없음 = '같은 추첨 미측정' · 선택 없음
OS1 <- list(list(device = "V1", cell = "E2V1", same_draw = list(status = "ok", deep = list(majority = TRUE))), list(device = "V1", cell = "E3V1", same_draw = list(status = "not_applicable")))
OS2 <- list(list(device = "V1", cell = "E2V1", same_draw = list(status = "ok", deep = list(majority = FALSE))))
OS3 <- list(list(device = "V1", cell = "E3V1", same_draw = list(status = "not_applicable")))
sg1 <- p5_same_draw_tag(list(list(device = "V1")), OS1); sg2 <- p5_same_draw_tag(list(list(device = "V1")), OS2); sg3 <- p5_same_draw_tag(list(list(device = "V1")), OS3)
chk("N38", is.na(sg1$tag) && identical(sg2$tag, "같은 추첨 미확인 — P4 · A 후보 전 도훈 확인") && grepl("같은 추첨 미측정", sg3$tag) && identical(p5_same_draw_tag(list(), OS1)$status, "no_selection"),
    "선택 꼬리표 — 같은 추첨 과반 = 없음 · 과반 미만 = 미확인 · 측정 칸 없음 = 미측정 · 선택 없음")

## N39) P2 정지 보고 재료(철학 P1 C-064 · 4요소) + 유형 기록에 ⑤ · ⑭ 같은 줄(C-067) · 보유 겹침(C-068) · 유동성 나란히(C-069) · Sharpe 표기(C-070)
DCX <- data.table(peak_date = c("2008-05-16", "2020-01-22"), sv = c(-0.01, -0.2), sr = c(-0.05, -0.05))
CTR2 <- p5_crisis_type_record(PCV, CTa, deep_keys = c("2008-05-16 2008-10-24", "2011-05-02 2011-09-26", "2020-01-22 2020-03-19", "2021-06-25 2022-09-30"), tol = 0.03, decomp = DCX, beta_delta = -0.1)
xv <- list(engine = "E2", device = "V1", cell = "P2R05_E2_V1", role = "judge", tested = TRUE, rules_computed = TRUE,
           rules = list(beta_deep = list(share = 0.75), beta_asym = list(delta = -0.1), selection = list(status = "ok", ok = FALSE), bull = list(uc_median = 0.6, uc_median_rx0 = 0.9)),
           record = list(crisis_type = CTR2, state_unturned_max_drop = data.table(crisis = c("x", "y"), beats_beta_copy = c(TRUE, NA)), crisis_dd_capture_median = c(variant = 0.7, rx0 = 0.8),
                         rolling = list(pass_life = 0.6, pass_recent = 0.5)),
           flags = list(r3 = FALSE, sharpe_up = TRUE), holdings_overlap = list(status = "ok", n_dates = 10L, n_differ = 9L, name_overlap_mean = 0.4),
           same_draw = list(status = "ok", holdings_overlap_vs_q50 = list(status = "ok", n_dates = 10L, n_differ = 5L)),
           liquidity = list(variant = list(deep_mean_decile = 6.5), rx0 = list(deep_mean_decile = 7.2)))
xq <- list(engine = "E2", device = "Q50", cell = "P2R05_E2_Q50", role = "diagnostic", tested = TRUE, rules_computed = TRUE, holdings_overlap = list(status = "ok", n_dates = 10L, n_differ = 3L),
           liquidity = list(variant = list(deep_mean_decile = 7.0), rx0 = list(deep_mean_decile = 7.2)))
xr <- list(engine = "E2", device = "RX0S", cell = "P2R05_E2_RX0S", role = "diagnostic", tested = TRUE, rules_computed = TRUE, holdings_overlap = list(status = "ok", n_dates = 10L, n_differ = 1L))
PR_ <- p5_pause_report(list(xv), list(xq, xr), 0.55); LM <- PR_$lever_map
chk("N39", identical(PR_$elements, c("lever_map", "philosophy_scorecard", "p4_implication", "philosophy_p4")) && identical(nrow(LM), 3L) && identical(LM[cell == "P2R05_E2_V1"]$systemic, "1/3") &&
      identical(LM[cell == "P2R05_E2_V1"]$boundary, "1/1") && identical(LM[cell == "P2R05_E2_V1"]$state_unturned, "1/1") && isTRUE(LM[cell == "P2R05_E2_V1"]$sharpe_up_without_r3) &&
      identical(LM[cell == "P2R05_E2_V1"]$beta_ratio_delta, -0.1) && identical(nrow(PR_$philosophy_scorecard$table), 1L) && isTRUE(PR_$philosophy_scorecard$table$bull_participation_meets_floor) &&
      identical(length(PR_$philosophy_scorecard$unmeasured_forms), 3L) && is.na(PR_$p4_implication) && is.na(PR_$philosophy_p4) &&
      identical(PR_$holdings_overlap$variant_q50$P2R05_E2_V1$n_differ, 5L) && identical(PR_$holdings_overlap$rx0_rx0s$P2R05_E2_RX0S$n_differ, 1L) &&
      identical(PR_$holdings_overlap$q50_rx0$P2R05_E2_Q50$n_differ, 3L) && identical(nrow(PR_$liquidity_deciles), 2L) &&
      identical(CTR2$per_crisis[crisis == "2008-05-16 2008-10-24"]$selection_better, TRUE) && identical(CTR2$per_crisis[crisis == "2020-01-22 2020-03-19"]$selection_better, FALSE) &&
      identical(CTR2$beta_ratio_delta, -0.1) && identical(CTR2$boundary_separate[type == "systemic"]$n_selection_better, 1L),
    "정지 보고 — 4요소 · 레버 지도(systemic 1/3 · 경계 1/1 · 상태 미전환 1/1 · ⑤ Δ · ⑭ · ③ 미통과 Sharpe 상승) · 성적표(강세 ≥ 0.55) · 미측정 형태 3 · P4 자리 · 보유 겹침 4종 · 유동성 V · Q50 · 유형 기록 ⑭ 위기별 · ⑤ Δ")

## N40) 부록 A 예측 기록(V2 상승 β > S2 상승 β ∧ ⑥ V2 ≥ S2)
v2a <- list(engine = "E2", device = "V2", rules_computed = TRUE, rules = list(beta_asym = list(up = 1.05), bull = list(share = 0.6)))
s2a <- list(engine = "E2", device = "S2", rules_computed = TRUE, rules = list(beta_asym = list(up = 0.95), bull = list(share = 0.5)))
apx <- p5_appendix_a(list(v2a), list(s2a)); apx2 <- p5_appendix_a(list(v2a), list(modifyList(s2a, list(rules = list(beta_asym = list(up = 1.2), bull = list(share = 0.5))))))
chk("N40", isTRUE(apx$holds) && isTRUE(apx$up_beta_holds) && isTRUE(apx$bull_holds) && identical(apx2$holds, FALSE) && identical(apx2$bull_holds, TRUE) &&
      identical(p5_appendix_a(list(), list())$status, "unmeasured"), "부록 A — 상승 β · ⑥ 둘 다 = 성립 · 상승 β 역전 = 불성립 · 칸 없음 = 미측정")

## N41) 재시드 짝 ⑩(RX0S) — RX0 엔진과 다른 파일 · 다른 md5 · 핀 · 기저 적재 · 워밍 · 템플릿 해당 없음 · .SEED_BASE 기록
SR2 <- file.path(TMP, "p2r05_stub2"); unlink(SR2, recursive = TRUE); dir.create(file.path(SR2, "e"), recursive = TRUE); dir.create(file.path(SR2, "04_Research/strategies/RP_AUTO_2002_06975"), recursive = TRUE)
dir.create(file.path(SR2, "04_Research/strategies/DT_2002_06975"), recursive = TRUE)
writeLines(c("# rx0", ".SEED_BASE <- 20020697L                              # 시드"), file.path(SR2, ENGF[["RX0"]]))
RSE <- "04_Research/strategies/DT_2002_06975/engine_RX0S.R"; writeLines(c("# rx0s", ".SEED_BASE <- 30000001L   # 재시드"), file.path(SR2, RSE))
M2 <- c(RX0 = unname(tools::md5sum(file.path(SR2, ENGF[["RX0"]]))), RX0S = unname(tools::md5sum(file.path(SR2, RSE))))
PRE2 <- list(operational_pins = list(files = list(list(path = ENGF[["RX0"]], md5 = M2[["RX0"]]), list(path = RSE, md5 = M2[["RX0S"]]))))
sp2 <- function(p) list(code = "x", block = "RX", base_signal = list(kind = "engine", path = file.path(SR2, p)), base_weight = 0.5, factors = list(), weighting = list(kind = "ew"), fixed_axes = FX, universe = list(kind = "all_hyg"))
hl2 <- function(k) sprintf("[rf_cell_engine] 기저 캐시 적중 — base_v2_%s_%s.rds (10행)", substr(M2[[k]], 1, 12), HX)
LS <- c(hl2("RX0S"), ln("RS", "none")); LR2 <- c(hl2("RX0"), ln("R2", "none"))
CX2 <- list(pre = PRE2, root = SR2, warm = list(ok = FALSE, status = "absent"), template = list(ok = FALSE, status = "absent"))
crs <- p5_construction_dt("RX0S", sp2(RSE), sp2(ENGF[["RX0"]]), p2_parse_cell_log(LS), p2_parse_cell_log(LR2), LS, LR2, CX2, "RS", "R2")
crs_bad <- p5_construction_dt("RX0S", sp2(ENGF[["RX0"]]), sp2(ENGF[["RX0"]]), p2_parse_cell_log(LR2), p2_parse_cell_log(LR2), LR2, LR2, CX2, "R2", "R2")
chk("N41", isTRUE(crs$ok) && identical(crs$flavor, "reseed") && identical(crs$warm$status, "not_applicable") && isTRUE(crs$seed$differ) && identical(crs$seed$seed_base, 30000001) &&
      !isTRUE(crs_bad$ok) && grepl("RX0 엔진과 다른 파일", crs_bad$why), "재시드 ⑩ — 다른 엔진 파일(핀 · 적재 줄) 통과 · 워밍 · 템플릿 해당 없음 · .SEED_BASE 다름 기록 · RX0 엔진 그대로 = 불일치")

## N42) 유동성 구간별 위기 손익 귀속(철학 P4 C-20261018-076) — 분위 기여 합 = 구간 손익 = 계약 03 ret_gross 구간 합(계약 수익 = 하네스 원시 Return.portfolio 로 만든 독립 판) ·
##   종목별 기여 = 독립 buy-and-hold 구현과 일치 · 분위 = 고점일 t−1 20일 평균 거래대금(고점일 당일 급증 미반영 — C10) · 결측 수익 = 0 · 고점일 행 없는 종목 = unknown ·
##   개선의 저 분위 몫(과반 = '저유동 귀속') · 재구성 불일치 = 미측정 · 라운드 묶음(스텁 루트 · 깊은 위기만 · 칸 미평가 = 그 칸만 미측정) · 정지 보고 나란히 표 · 결론 꼬리표
suppressPackageStartupMessages({ library(xts); library(PerformanceAnalytics) })
E_TA <- .dp_deps(ROOT)                                                             # tilt_attribution(ta_resolve_artifact · ta_read_holdings · .ta_daily_weights) 포함
cal42 <- local({ d <- seq(as.Date("2010-01-04"), by = "day", length.out = 100); d[!(as.POSIXlt(d)$wday %in% c(0L, 6L))][1:60] })
p42 <- cal42[25]; t42 <- cal42[45]; U9 <- sprintf("U%d", 1:9)
R42 <- local({ set.seed(42); R <- CJ(Ticker = c(U9, "U10"), Date = cal42)
  R[, Ret := rnorm(.N, 0, 0.01)]
  R[Date > p42 & Date <= t42, Ret := fifelse(Ticker == "U1", -0.010, fifelse(Ticker == "U2", -0.001, fifelse(Ticker == "U10", 0.002, -0.005)))]
  R[Ticker == "U2" & Date == cal42[30], Ret := NA_real_]                            # 창 안 결측 수익 = 0(계약 규약)
  R <- R[!(Ticker == "U10" & Date < cal42[30])]                                      # U10 = 고점일 행 없음 → 분위 unknown(유니버스 밖)
  R[, Close := 100 * cumprod(1 + fifelse(is.finite(Ret), Ret, 0)), by = Ticker]
  R[, Vol := 2^as.numeric(match(Ticker, c(U9, "U10"))) * 1e4]                        # 거래대금 순위 = 번호(2배 간격) → 저 U1–3 · 중 U4–6 · 고 U7–9
  R[Ticker == "U2" & Date == p42, Vol := 1e9]                                        # 고점일 당일 급증 — t−1 이면 저 분위 · 당일 포함(C10 위반)이면 고 분위
  R[] })
H42v <- data.table(date = rep(cal42[c(3, 35)], each = 3), ticker = c("U2", "U5", "U8", "U2", "U6", "U10"), actual_weight = c(0.4, 0.3, 0.3, 0.5, 0.25, 0.25))
H42r <- data.table(date = rep(cal42[c(3, 35)], each = 3), ticker = c("U1", "U4", "U7", "U1", "U4", "U7"), actual_weight = c(0.4, 0.3, 0.3, 0.5, 0.25, 0.25))
win42 <- function(ex, k, cal) cal[cal > ex[k] & (k == length(ex) | cal <= ex[min(k + 1L, length(ex))])]   # close_t1 창 (E_k, E_{k+1}]
rg_oracle <- function(H, RAW, cal) { ex <- sort(unique(as.Date(H$date))); out <- list()          # 하네스 .leg_daily 원시(Return.portfolio buy-and-hold · 유한 수익 행 · 결측 0 · 재정규화)
  for (k in seq_along(ex)) { hp <- win42(ex, k, cal); md <- H[as.Date(date) == ex[k]]
    sub <- RAW[Ticker %in% md$ticker & Date %in% hp & is.finite(Ret), .(Date, Ticker, Ret)]
    wide <- dcast(sub, Date ~ Ticker, value.var = "Ret"); setorder(wide, Date)
    rmx <- as.matrix(wide[, -1, with = FALSE]); rmx[!is.finite(rmx)] <- 0
    wn <- setNames(md$actual_weight, md$ticker)[colnames(rmx)]; wn <- wn / sum(wn)
    pr <- PerformanceAnalytics::Return.portfolio(xts::xts(rmx, order.by = wide$Date), weights = wn, rebalance_on = NA)
    dd <- merge(data.table(date = hp), data.table(date = as.Date(zoo::index(pr)), ret_gross = as.numeric(pr[, 1])), by = "date", all.x = TRUE)
    dd[!is.finite(ret_gross), ret_gross := 0]; out[[k]] <- dd }
  rbindlist(out) }
bh_contrib <- function(H, RAW, cal, p0, t0) { ex <- sort(unique(as.Date(H$date))); out <- list()   # 독립 buy-and-hold 시작 비중 × 일수익(종목별 · 구간 합)
  for (k in seq_along(ex)) { hp <- win42(ex, k, cal); md <- H[as.Date(date) == ex[k]]; w0 <- md$actual_weight / sum(md$actual_weight)
    M <- vapply(md$ticker, function(t) { z <- RAW[Ticker == t]; r <- z$Ret[match(hp, z$Date)]; r[!is.finite(r)] <- 0; r }, numeric(length(hp)))
    V <- rbind(w0, sweep(apply(1 + M, 2, cumprod), 2, w0, `*`)); Wb <- V[-nrow(V), , drop = FALSE] / rowSums(V[-nrow(V), , drop = FALSE])
    out[[k]] <- data.table(date = rep(hp, ncol(M)), Ticker = rep(md$ticker, each = length(hp)), c = as.vector(Wb * M)) }
  rbindlist(out)[date > p0 & date <= t0, .(c = sum(c)), by = Ticker][order(Ticker)] }
art42 <- function(nm, H, RG) { p <- file.path(TMP, "p2r05_liq", nm); unlink(p, recursive = TRUE); dir.create(p, recursive = TRUE)
  fwrite(RG[, .(date, ret_gross, ret_net = ret_gross)], file.path(p, "03_period_returns.csv")); fwrite(H, file.path(p, "04_holdings.csv"))
  fwrite(data.table(date = RG$date, benchmark_ret = -0.004), file.path(p, "05_benchmark_returns.csv"))
  writeLines(toJSON(list(measurement_regime = list(exec_price = "close_t1", key = "close_t1_fixture")), auto_unbox = TRUE), file.path(p, "authoritative_remeasure.json")); p }
RGv <- rg_oracle(H42v, R42, cal42); RGr <- rg_oracle(H42r, R42, cal42)
A42v <- art42("v", H42v, RGv); A42r <- art42("r", H42r, RGr); A42m <- art42("m", H42v, copy(RGv)[date == cal42[40], ret_gross := ret_gross + 1e-6])
CRK42 <- data.table(k = paste(p42, t42), peak = p42, trough = t42, deep = TRUE, fast = FALSE)
LIQ42 <- p5_liq_from(R42); hy42 <- function(d) U9
LV42 <- p5_liq_tercile_cell(E_TA, A42v, CRK42, R42, LIQ42, hy42, TAU); LR42 <- p5_liq_tercile_cell(E_TA, A42r, CRK42, R42, LIQ42, hy42, TAU)
LM42 <- p5_liq_tercile_cell(E_TA, A42m, CRK42, R42, LIQ42, hy42, TAU)
av <- LV42$per_crisis[[1]]; avr <- LR42$per_crisis[[1]]; ORV <- bh_contrib(H42v, R42, cal42, p42, t42); ORR <- bh_contrib(H42r, R42, cal42, p42, t42)
tc <- function(a, t) { z <- a$by_tercile[tercile == t]$contrib; if (length(z)) z else 0 }; trc <- function(a, tk) a$names[Ticker == tk]$tercile
IM42 <- p5_liq_improvement(LV42$per_crisis, LR42$per_crisis, FS$majority_share); IMm <- p5_liq_improvement(LM42$per_crisis, LR42$per_crisis, FS$majority_share)
imp42 <- av$total - avr$total; li42 <- tc(av, "low") - tc(avr, "low")
chk("N42a", identical(av$status, "ok") && isTRUE(av$recon_ok) && isTRUE(abs(av$recon_gap) < 1e-12) && isTRUE(abs(av$sum_terciles - av$total) < 1e-14) &&
      isTRUE(abs(av$contract_sum - sum(RGv[date > p42 & date <= t42]$ret_gross)) < 1e-12) && isTRUE(avr$recon_ok) && identical(av$n_days, 20L) &&
      isTRUE(all.equal(av$names[order(Ticker)]$contrib, ORV$c, tolerance = 1e-12)) && isTRUE(all.equal(avr$names[order(Ticker)]$contrib, ORR$c, tolerance = 1e-12)) &&
      isTRUE(abs(tc(av, "low") - ORV[Ticker == "U2"]$c) < 1e-14) && isTRUE(abs(tc(av, "mid") - sum(ORV[Ticker %in% c("U5", "U6")]$c)) < 1e-14) &&
      isTRUE(abs(tc(av, "unknown") - ORV[Ticker == "U10"]$c) < 1e-14) && identical(LV42$exec_price, "close_t1"),
    "귀속 항등 — 분위 합 = 구간 손익 · 재구성 = 하네스 원시 Return.portfolio 계약 수익(차 < 1e-12) · 종목별 기여 = 독립 buy-and-hold · 저 = U2 · 중 = U5 + U6 · unknown = U10 · 20일 창 · 창 안 리밸",
    paste(format(av$recon_gap), format(av$total), format(av$contract_sum)))
chk("N42b", identical(trc(av, "U2"), "low") && identical(trc(av, "U5"), "mid") && identical(trc(av, "U6"), "mid") && identical(trc(av, "U8"), "high") && identical(trc(av, "U10"), "unknown") &&
      identical(trc(avr, "U1"), "low") && identical(trc(avr, "U4"), "mid") && identical(trc(avr, "U7"), "high") && identical(av$n_universe, 9L) && identical(av$asof, format(p42)) &&
      isTRUE(av$names[Ticker == "U2"]$adv20_l1 < 1e8) && isTRUE(all.equal(av$names[Ticker == "U2"]$adv20_l1, LIQ42[Date == p42 & Ticker == "U2"]$adv20_l1)),
    "분위 — 고점일 t−1 거래대금(당일 1e9 급증 미반영 → U2 저) · 2배 간격 순위 · 고점일 행 없는 U10 = unknown · 유니버스 9 · as-of = 고점일")
chk("N42c", identical(IM42$status, "ok") && isTRUE(abs(IM42$per_crisis$improvement - imp42) < 1e-14) && isTRUE(imp42 > 0) && isTRUE(abs(IM42$per_crisis$low_share - li42 / imp42) < 1e-12) &&
      isTRUE(IM42$per_crisis$low_share > 0.5) && isTRUE(IM42$per_crisis$low_attributed) && identical(IM42$n_low_attributed, 1L) && any(grepl("^저유동 귀속\\(.*1/1 개선 위기\\)$", IM42$tags)) &&
      identical(LM42$per_crisis[[1]]$recon_ok, FALSE) && identical(IMm$per_crisis$status, "recon_mismatch") && is.na(IMm$per_crisis$low_attributed) && identical(IMm$n_low_attributed, 0L) &&
      any(grepl("유동성 귀속 미측정\\(일부 위기 1/1", IMm$tags)) && !any(grepl("저유동 귀속", IMm$tags)) &&
      identical(p5_liq_improvement(NULL, LR42$per_crisis, 0.5)$tags, "유동성 귀속 미측정") && identical(p5_liq_tercile_core(data.table(), data.table(), c(a = 1), 1:9)$status, "unmeasured"),
    "개선 — 칸 − RX0 > 0 · 저 분위 몫 = Δ저 / 개선 > 과반 = '저유동 귀속 1/1' · 03 한 날 1e-6 어긋남 = 재구성 불일치 → 몫 안 읽음 · '유동성 귀속 미측정(일부 위기)' · 칸 귀속 없음 = 미측정 · 구간 보유 없음 = 미측정")
## 라운드 묶음(스텁 루트) — 위기 = RX0 보는 창 패킷(깊은 위기 = 깊이 ≥ 중앙값 → 1개 · 빠른 급락 0) · S1 미평가 = 그 칸만 미측정 · E3 없음 = 미측정 꼬리표
RS42 <- file.path(TMP, "p2r05_liq_res"); unlink(RS42, recursive = TRUE); dir.create(file.path(RS42, "R42c", "visible"), recursive = TRUE)
writeLines(toJSON(list(behavior = list(crises = list(list(peak_date = format(p42), trough_date = format(t42), bm_dd = -0.2), list(peak_date = format(cal42[5]), trough_date = format(cal42[10]), bm_dd = -0.05)))),
                  auto_unbox = TRUE), file.path(RS42, "R42c", "visible", "diagnosis_packet.json"))
X42 <- list(root = TMP, res = RS42, env = list(E = E_TA, liq = LIQ42, raw = data.table(Date = rep(cal42, each = 9), Ticker = rep(U9, 60), HYG = TRUE)))
C42 <- list(list(code = "R42c", engine = "E2", component = "RX0"), list(code = "V42c", engine = "E2", component = "V1"), list(code = "S42c", engine = "E2", component = "S1"),
            list(code = "N42c", engine = "E2", component = "N1"))
EV42 <- list(R42c = list(status = "evaluated", artifacts = A42r), V42c = list(status = "evaluated", artifacts = A42v), S42c = list(status = "not_measured"), N42c = list(status = "evaluated", artifacts = A42v))
LQ42 <- p5_liq_attr_round(X42, EV42, C42, c("E2", "E3"), R42, FS, TAU)
PZ42 <- p5_pause_report(list(), list(), 0.55, LQ42)
chk("N42d", identical(LQ42$E2$status, "ok") && identical(nrow(LQ42$E2$crises), 1L) && isTRUE(LQ42$E2$crises$deep) && identical(LQ42$E2$crises$crisis, paste(p42, t42)) &&
      identical(names(LQ42$E2$per_cell), c("V1", "S1", "RX0")) && identical(LQ42$E2$improvement$V1$n_low_attributed, 1L) && identical(LQ42$E2$per_cell$S1$status, "unmeasured") &&
      grepl("not_measured", LQ42$E2$per_cell$S1$why) && identical(LQ42$E2$improvement$S1$tags, "유동성 귀속 미측정") && identical(LQ42$E3$status, "unmeasured") &&
      identical(p5_liq_attr_for(LQ42, "E3", "V1")$tags, "유동성 귀속 미측정") && identical(p5_liq_attr_for(LQ42, "E2", "V1")$status, "ok") &&
      identical(p5_liq_attr_for(LQ42, "E2", "RX0")$tags, "유동성 귀속 미측정") && identical(sort(LQ42$E2$table[status == "ok"]$device), c("RX0", "V1")) &&
      isTRUE(all.equal(LQ42$E2$table[device == "V1"]$low, tc(av, "low"))) && identical(PZ42$liquidity_terciles$E2$status, "ok") &&
      identical(PZ42$liquidity_terciles$E2$improvement[device == "V1"]$n_low_attributed, 1L) && identical(PZ42$liquidity_terciles$E3$tag, "유동성 귀속 미측정") &&
      grepl("Ret 열 없음", tryCatch(p5_liq_attr_round(X42, EV42, C42, "E2", R42[, -"Ret"], FS, TAU), error = function(e) conditionMessage(e))),
    "라운드 묶음 — 깊은 위기 1(얕은 위기 제외 · 빠른 급락 0) · 나란히 칸 V1 · S1 · RX0(N1 = 나란히 칸 밖) · S1 미평가 = 그 칸만 · E3 없음 = 미측정 · RX0 자신 = 귀속 없음 · 표 · 정지 보고 · Ret 없음 = 오류")
xgl <- xg; xgl$liq_attr <- IM42; xgn <- xg; xgn$liq_attr <- modifyList(IM42, list(tags = NULL))
cl1 <- p5_conclusion(xgl, rdg, NULL); cl0 <- p5_conclusion(xg, rdg, NULL); cln <- p5_conclusion(xgn, rdg, NULL); clu <- p5_conclusion(list(rules_computed = FALSE, why = "x"))
chk("N42e", any(grepl("^저유동 귀속", cl1$tags)) && grepl("저유동 귀속", cl1$sentence) && "유동성 귀속 미측정" %in% cl0$tags && !any(grepl("유동성 귀속|저유동", cln$tags)) &&
      "유동성 귀속 미측정" %in% clu$tags && identical(xgl$liq_attr$status, "ok"),
    "결론 — 저 분위 과반 = '저유동 귀속' · 귀속 없음 = '유동성 귀속 미측정'(의무) · 측정 · 꼬리표 없음 = 없음 · 미시험 칸에도 의무 꼬리표")

## N43) 표적 정의 대조 대상 = 분위 엔진 파일만(재시드 짝 제외 — 건식 실행 10-18 발견: RX0S 엔진이 DT 폴더 rx0s/ 에 있어 섞이면 상수 대조가 깨져 ⑮ 가 미측정으로 접힌다) ·
##   실제 DT 엔진 7개 표적 정의 통과 · 재시드 엔진을 섞으면 실패 · 미시험 칸도 정확 이름 rules($ 부분 일치 rules_computed 방지)
RS43 <- "04_Research/strategies/DT_2002_06975/rx0s/engine_RX0S.R"; wspec("RS43", spec("RS43", paths = RS43))
cells43 <- list(list(code = "a", component = "V1", path = "specs/V1.json"), list(code = "b", component = "RX0S", path = "specs/RS43.json"),
                list(code = "c", component = "W2", path = "specs/W2.json"), list(code = "d", component = "LV", path = "specs/LV.json"))
DTF43 <- p5_dt_engine_files(cells43, STR)
DT7 <- file.path("04_Research/strategies/DT_2002_06975", paste0("engine_", c("V1", "V2", "Q50", "N1", "N2", "S1", "S2"), ".R"))
y7 <- if (all(file.exists(file.path(ROOT, DT7)))) p5_ydef_check(DT7, ROOT) else list(ok = NA, why = "DT 엔진 파일 없음(픽스처 대조 생략)")
y8 <- if (isTRUE(y7$ok) && file.exists(file.path(ROOT, RS43))) p5_ydef_check(c(DT7, RS43), ROOT) else list(ok = FALSE)
u43 <- .p2_untested(list(engine = "E2", device = "Q50", cell = "c", rules_computed = FALSE), "x")
chk("N43", setequal(DTF43, c(ENGF[["V1"]], ENGF[["V2"]])) && !any(grepl("rx0s/", DTF43, fixed = TRUE)) && isTRUE(y7$ok) && !isTRUE(y8$ok) &&
      isTRUE(list(rules_computed = TRUE)$rules) && is.list(u43[["rules"]]) && !isTRUE(u43$rules) && all(vapply(U, function(u) is.list(u[["rules"]]), logical(1))) &&
      identical(p5_pause_report(list(), list(u43), 0.55)$status, "ok"),
    "표적 정의 대상 — V1 · W2 의 DT 엔진만(재시드 rx0s/ · LV 제외) · 실제 DT 엔진 7개 통과 · 재시드 엔진 섞으면 실패 · R 의 $ 부분 일치(rules → rules_computed) 방지 = 미시험 칸 rules 정확 이름",
    paste(y7$why %||% "", paste(DTF43, collapse = ",")))

## N44) ⑮ 예측표 = 측정에 묶인 판 1개(격리 점검 v1 필수 4) — 워밍 센티널 qpred{path, md5} 파일만 읽는다(폴더에 판본 다른 파일이 있어도 중단 없음 · 기록) ·
##   md5 불일치 = 평가 중단 · 묶인 파일 없음 = 평가 중단 · 필드 없음 = '예측표 미묶임'(⑮ 미측정) · 상대 경로(warm_engine.R .rel) · 절대 경로 둘 다
QB <- file.path(TMP, "p2r05_qbound"); unlink(QB, recursive = TRUE); dir.create(file.path(QB, "q"), recursive = TRUE)
QPa <- QP0; QPb <- copy(QP0); QPb[1, q10 := q10 + 1e-6]                                         # b = 보는 창 q 가 다른 옛 판(폴더 전체를 읽으면 중단될 조합)
arrow::write_parquet(QPa, file.path(QB, "q", "aaaa1111_bbbb2222.parquet")); arrow::write_parquet(QPb, file.path(QB, "q", "aaaa1111_cccc3333.parquet"))
wsen <- function(nm, qp) { f <- file.path(QB, nm); writeLines(toJSON(list(cache_months = "261/261", positive_control = list(pass = TRUE), code_version = P2R05_CODE_VERSION, qpred = qp),
                                                                    auto_unbox = TRUE, null = "null"), f); list(path = f, source = "results/warm_sentinel.json") }
QBa <- file.path(QB, "q", "aaaa1111_bbbb2222.parquet")
qb_ok <- p5_qpred_bound(QB, wsen("w_ok.json", list(path = "q/aaaa1111_bbbb2222.parquet", md5 = unname(tools::md5sum(QBa)))), TAU, qdir = file.path(QB, "q"))
qb_abs <- p5_qpred_bound(QB, wsen("w_abs.json", list(path = gsub("\\\\", "/", QBa), md5 = unname(tools::md5sum(QBa)))), TAU, qdir = file.path(QB, "q"))
qb_un <- p5_qpred_bound(QB, wsen("w_un.json", NULL), TAU, qdir = file.path(QB, "q"))
qb_md5 <- haltof(p5_qpred_bound(QB, wsen("w_md5.json", list(path = "q/aaaa1111_bbbb2222.parquet", md5 = strrep("0", 32))), TAU, qdir = file.path(QB, "q")))
qb_nof <- haltof(p5_qpred_bound(QB, wsen("w_nof.json", list(path = "q/zzzz.parquet", md5 = strrep("0", 32))), TAU, qdir = file.path(QB, "q")))
chk("N44", identical(qb_ok$status, "ok") && identical(qb_ok$n_files, 1L) && identical(qb_ok$n_other, 1L) && identical(qb_ok$other, "aaaa1111_cccc3333.parquet") &&
      identical(qb_ok$bound$path, "q/aaaa1111_bbbb2222.parquet") && isTRUE(all.equal(qb_ok$Qv$q10, p5_visible_signals(QPa, TAU)[order(Date, Ticker)]$q10)) && identical(qb_abs$status, "ok") &&
      identical(qb_un$status, "unbound") && grepl("예측표 미묶임", qb_un$why) && identical(qb_md5, "예측표 md5 ≠ 측정 묶음(워밍 센티널 qpred.md5)") &&
      identical(qb_nof, "묶인 예측표 없음(워밍 센티널 qpred.path)") && grepl("판본 다른 예측표 1개", qb_ok$other_note),
    "예측표 묶음 — 센티널 판 1개만(옛 판 있어도 중단 없음 · 기록 1) · 상대 · 절대 경로 · 필드 없음 = 미묶임(⑮ 미측정) · md5 다름 = 중단 · 파일 없음 = 중단")

## N45) 판정어 = 결론 꼬리표(필수 1) — ⑤ 만 실패 · ⑮ 만 실패 · ① ⑥ 실패 · ⑥ 만 실패(⑤ ⑮ 통과) 네 경우에 판정어와 결론 '꼬리 회피 기계'가 같은 정의
fl45 <- function(...) { f <- list(r3 = TRUE, r4 = TRUE, crisis = TRUE, deep = TRUE, level = TRUE, beta_ratio = TRUE, tail = TRUE, s14 = TRUE, s14_measured = TRUE, sb_ok = TRUE, sb_status = "ok",
                                  strength = list(bull = TRUE, alpha = TRUE, cycle = TRUE, S = TRUE, path = TRUE)); a <- list(...); f[names(a)] <- a; f }
vd45 <- function(f) p2_cell_verdict(list(pass = FALSE, beta_unmeasured = FALSE, beta_deep = f$r3, fast = f$r4, crisis = f$crisis, deep = f$deep, selection = f$s14, selection_measured = f$s14_measured,
                                         level = f$level, beta_ratio = f$beta_ratio, strength = f$strength, tail = f$tail))
cn45 <- function(f) p5_conclusion(list(rules_computed = TRUE, tested = TRUE, tail_gate = list(pass = isTRUE(f$tail)), flags = f, reference_points = list()), NULL, NULL)
F5 <- fl45(beta_ratio = FALSE); F5L <- fl45(level = FALSE); F15 <- fl45(tail = FALSE, strength = list(bull = TRUE, alpha = TRUE, cycle = TRUE, S = TRUE, path = TRUE))
F16 <- fl45(crisis = FALSE, strength = list(bull = FALSE, alpha = TRUE, cycle = TRUE, S = TRUE, path = TRUE)); F6 <- fl45(strength = list(bull = FALSE, alpha = TRUE, cycle = TRUE, S = TRUE, path = TRUE))
F6t <- fl45(tail = FALSE, strength = list(bull = FALSE, alpha = TRUE, cycle = TRUE, S = TRUE, path = TRUE))
mt <- function(f) "꼬리 회피 기계(방어만 · 복리 없음)" %in% cn45(f)$tags
chk("N45", identical(vd45(F5), "asymmetry_unmet") && !mt(F5) && identical(vd45(F5L), "asymmetry_unmet") && !mt(F5L) &&
      identical(vd45(F15), "untested_tail_instrument") && !mt(F15) && identical(vd45(F6t), "untested_tail_instrument") && !mt(F6t) &&
      identical(vd45(F16), "not_decisive") && !mt(F16) && identical(vd45(F6), "defense_but_strength_or_path") && mt(F6) &&
      all(vapply(list(F5, F5L, F15, F16, F6, F6t), function(f) identical(identical(vd45(f), "defense_but_strength_or_path"), mt(f)), logical(1))) &&
      grepl("β 비대칭 미달", P2R05_VERDICT_NAMES[["asymmetry_unmet"]]) && identical(P2R05_VERDICT_SHORT[["asymmetry_unmet"]], "β 비대칭 미달"),
    "판정어 = 결론 꼬리표 — ⑤ Δ 만 · ⑤ 수준 만 실패 = β 비대칭 미달(기계 아님) · ⑮ 만 실패 = 미시험(계기) · ① ⑥ 실패 = 결정 미달(꼬리표 없음) · ⑥ 만 실패 = 꼬리 회피 기계(둘 다) · ⑥ ∧ ⑮ 실패 = 미시험 먼저")

## N46) 수평 판독(결론 범위 5 · 권고 5) — 거부 집합 다음 보유월 하위 분위 적중 ≤ 기저 = '수평 불일치' · 기록 없음 = 미측정 · 결론 문장 나란히(결론 범위 11 · 14)
hz1 <- p5_horizon_reading(list(status = "ok", veto = list(bottom = 0.2), base_rate = 0.2)); hz2 <- p5_horizon_reading(list(status = "ok", veto = list(bottom = 0.35), base_rate = 0.2))
hz3 <- p5_horizon_reading(NULL); sd46 <- list(liq = list(V = 6.5, S = 7, Q50 = 7.1, RX0 = 7.4), overlap = list(rx0 = 0.4, q50 = 0.7))
cz <- p5_conclusion(xg, rdg, NULL, side = sd46, hz = hz1); cz2 <- p5_conclusion(xg, rdg, NULL, hz = hz2)
chk("N46", isTRUE(hz1$mismatch) && grepl("^수평 불일치", hz1$tag) && identical(hz2$mismatch, FALSE) && is.na(hz2$tag) && identical(hz3$status, "unmeasured") && grepl("미측정", hz3$tag) &&
      any(grepl("^수평 불일치", cz$tags)) && !any(grepl("수평", cz2$tags)) && grepl("나란히 V 6.5 · S 7 · Q50 7.1 · RX0 7.4", cz$sentence, fixed = TRUE) &&
      grepl("보유 이름 겹침 RX0 대비 0.4 · Q50 대비 0.7", cz$sentence, fixed = TRUE) && !grepl("나란히", cz2$sentence, fixed = TRUE),
    "수평 — 적중 ≤ 기저(같음 포함) = 수평 불일치 꼬리표 · 기저 초과 = 없음 · 기록 없음 = 미측정 · 결론 문장 유동성 십분위 V · S · Q50 · RX0 나란히 · 보유 겹침 RX0 · Q50 대비")

## N47) ⑮ 예측표 셀 로그 대조(격리 점검 v2 필수 1) — 분위 엔진 칸 셀 로그 '[DT qpred] path=' = 묶인 판(저장소 상대 · 슬래시 · 대소문자 정규화 · md5) · 경로 다름 · md5 다름 = 평가 중단 ·
##   줄 없음 = 같은 기저 캐시 연쇄(이번 측정에서 그 캐시를 '실행'한 칸의 예측표 = 묶인 판) 또는 '대조 불가' · 셀 로그 없음 = 미측정(대상 아님) · 평균 엔진 칸 · 재시드 짝 = 대상 밖 · 묶인 판 없음 = 해당 없음
Q47D <- file.path(STR, "04_Research/strategies/DT_2002_06975/_work/qpred"); dir.create(Q47D, recursive = TRUE, showWarnings = FALSE)
Q47 <- file.path(Q47D, "cv47aaaa_11112222.parquet"); writeLines("bound qpred stub", Q47)
Q47o <- file.path(Q47D, "cv47bbbb_33334444.parquet"); writeLines("other qpred stub", Q47o)
B47 <- list(path = p5_rel(Q47, STR), abs = Q47, md5 = unname(tools::md5sum(Q47)), sentinel = "results/warm_sentinel.json"); B47m <- modifyList(B47, list(md5 = strrep("0", 32)))
dir.create(file.path(STR, "04_Research/strategies/DT_2002_06975/rx0s"), showWarnings = FALSE)
writeLines("# stub reseed engine", file.path(STR, "04_Research/strategies/DT_2002_06975/rx0s/engine.R"))          # 재시드 엔진도 DT 폴더 안(N43 · 실제 배치)
wspec("RS47", spec("RS47", paths = "04_Research/strategies/DT_2002_06975/rx0s/engine.R"))
c47 <- function(cd, eng, comp, sp) list(code = cd, engine = eng, component = comp, path = file.path("specs", paste0(sp, ".json")))
C47 <- list(c47("E2_RX0", "E2", "RX0", "R"), c47("E2_RX0S", "E2", "RX0S", "RS47"), c47("E2_V1", "E2", "V1", "V1"), c47("E2_V2", "E2", "V2", "V2"), c47("E2_Q50", "E2", "Q50", "Q50"),
            c47("E2_W2", "E2", "W2", "W2"), c47("E2_LV", "E2", "LV", "LV"), c47("E3_V1", "E3", "V1", "V1"), c47("E3_V2", "E3", "V2", "V2"))
ql47 <- function(p) sprintf("[DT qpred] path=%s rows=123 months=261", p)
sc47 <- function(nm, logs) { d <- file.path(STR, nm); unlink(d, recursive = TRUE); dir.create(d)
  for (cd in names(logs)) writeLines(logs[[cd]], file.path(d, paste0(cd, ".log")), useBytes = TRUE); d }
Q47v <- gsub("/", "\\", toupper(Q47), fixed = TRUE)                                                      # 역슬래시 · 대문자 판(같은 파일)
LA47 <- list(E2_RX0 = hitl("RX0"), E2_RX0S = ql47(Q47o), E2_V1 = c(runl("V1"), ql47(Q47v)), E2_V2 = c(runl("V2"), ql47(Q47)), E2_Q50 = hitl("Q50"),
             E2_W2 = c(hitl("RX0"), hitl("V2"), "[rf_cell_engine] engine_blend 2개 — 공통 999행 (engine.R + engine_V2.R)"), E2_LV = hitl("RX0"), E3_V1 = hitl("V1"))   # E3_V2 = 셀 로그 없음
R47a <- sc47("res47a", LA47)
R47b <- sc47("res47b", modifyList(LA47, list(E2_V1 = c(runl("V1"), ql47(Q47o)))))                          # 경로 다름(다른 판본 파일)
R47c <- sc47("res47c", modifyList(LA47, list(E2_V1 = runl("V1"))))                                         # 실행 줄만(예측표 줄 없음) → 연쇄 출처 아님
st47 <- function(z, cd) { p <- z$per_cell; if (is.null(p) || !nrow(p) || !(cd %in% p$code)) NA_character_ else p$status[p$code == cd][1] }
QA47 <- p5_qpred_log_check(C47, R47a, STR, B47); QC47 <- p5_qpred_log_check(C47, R47c, STR, B47)
h47b <- haltof(p5_qpred_log_check(C47, R47b, STR, B47)); h47m <- haltof(p5_qpred_log_check(C47, R47a, STR, B47m))
na47 <- p5_qpred_log_check(C47, R47a, STR, NULL); na47b <- p5_qpred_log_check(C47, R47a, STR, list(md5 = "x"))
x47u <- modifyList(xg, list(qpred_log = list(status = "unverifiable"))); x47c <- modifyList(xg, list(qpred_log = list(status = "chained")))
QLT <- "⑮ 예측표 셀 로그 대조 불가(셀 로그 예측표 줄 없음 · 기저 캐시 출처 미확인)"
chk("N47", identical(QA47$status, "ok") && setequal(QA47$per_cell$code, c("E2_V1", "E2_V2", "E2_Q50", "E2_W2", "E3_V1", "E3_V2")) &&
      identical(st47(QA47, "E2_V1"), "match") && identical(st47(QA47, "E2_V2"), "match") && identical(st47(QA47, "E3_V1"), "chained") && identical(st47(QA47, "E2_W2"), "chained") &&
      identical(QA47$per_cell$chained_from[QA47$per_cell$code == "E3_V1"], "E2_V1") && identical(QA47$per_cell$chained_from[QA47$per_cell$code == "E2_W2"], "E2_V2") &&
      identical(st47(QA47, "E2_Q50"), "unverifiable") && identical(st47(QA47, "E3_V2"), "no_log") &&
      identical(c(QA47$n_match, QA47$n_chained, QA47$n_unverifiable, QA47$n_no_log), c(2L, 2L, 1L, 1L)) && grepl("대조 불가 1칸", QA47$tag, fixed = TRUE) &&
      identical(h47b, "셀 로그 예측표 ≠ 측정 묶음(워밍 센티널 qpred)") && identical(h47m, "셀 로그 예측표 md5 ≠ 측정 묶음(워밍 센티널 qpred)") &&
      identical(st47(QC47, "E2_V1"), "unverifiable") && identical(st47(QC47, "E3_V1"), "unverifiable") && identical(QC47$n_unverifiable, 3L) &&
      identical(na47$status, "not_applicable") && identical(na47b$status, "not_applicable") &&
      QLT %in% p5_conclusion(x47u, rdg, NULL)$tags && !any(grepl("셀 로그 대조 불가", p5_conclusion(x47c, rdg, NULL)$tags, fixed = TRUE)) &&
      !any(grepl("셀 로그 대조 불가", p5_conclusion(xg, rdg, NULL)$tags, fixed = TRUE)),
    "셀 로그 예측표 대조 — 같음(역슬래시 · 대문자 판 포함) · 줄 없음 = 연쇄(E3 V1 ← E2 V1 · W2 ← E2 V2) · 출처 없음 = 대조 불가(꼬리표 1칸) · 셀 로그 없음 = 미측정 · 평균 엔진 · 재시드 짝 대상 밖 · 경로 다름 · md5 다름 = 중단 · 실행 줄만 = 연쇄 출처 아님 · 묶인 판 없음 = 해당 없음 · 결론 꼬리표",
    paste(QA47$status, paste(QA47$per_cell$code, QA47$per_cell$status, collapse = ","), h47b, h47m))

## ═══ 뮤테이션 — 소스 텍스트 치환(치환 대상이 정확히 1줄 · 사본 단독 적재 · 사본이 본 실행 블록을 돌리지 않음)이 각각 위 검사 하나를 깨는가 ═══
##   + 검출 함수 원본 대조(같은 검출 함수가 원본 사본에서는 거짓 · 오류 없음이어야 한다 — 오류를 '검출'로 세는 가짜 양성 대조 방지)
SRC <- readLines(EVF, warn = FALSE, encoding = "UTF-8")
mutant <- function(from, to) {
  hit <- sum(grepl(from, SRC, fixed = TRUE)); if (hit != 1L) return(list(err = sprintf("치환 대상 %d줄(1줄이어야 함): %s", hit, from)))
  MS <- sub(from, to, SRC, fixed = TRUE)
  if (identical(MS, SRC) || sum(MS != SRC) != 1L) return(list(err = paste("치환 불성사:", from)))
  p <- gsub("\\\\", "/", tempfile("p2r05_mut_", tmpdir = TMP, fileext = ".R")); writeLines(MS, p, useBytes = TRUE)
  e <- new.env(); r0 <- tryCatch({ sys.source(p, envir = e, keep.source = FALSE); NULL }, error = function(z) conditionMessage(z))
  if (!is.null(r0)) return(list(err = paste("사본 적재 실패:", r0))); if (exists("CELLS_ONLY", envir = e, inherits = FALSE)) return(list(err = "사본이 본 실행 블록을 돌렸다"))
  list(env = e)
}
FL_NOTAIL <- FL; FL_NOTAIL$tail <- FALSE
MU <- list(
  ## 지정 뮤테이션(구현 계약 · Q 10-18 추가 2종)
  list(nm = "⑮ 부등호 뒤집기", from = "pass = identical(st, \"ok\") && t > tmin, margin", to = "pass = identical(st, \"ok\") && t < tmin, margin",
       kill = function(e) !isTRUE(e$p5_tail_instrument(QYp, TI, NW)$pass)),
  list(nm = "⑮ NW lag 0", from = "t <- if (nrow(Dd)) nw(Dd$D, lag = lag) else NA_real_", to = "t <- if (nrow(Dd)) nw(Dd$D, lag = 0L) else NA_real_",
       kill = function(e) !isTRUE(abs(e$p5_tail_instrument(QYp, TI, NW)$t - nw_ref(Dp, 3L)) < 1e-10)),
  list(nm = "라벨 시가 → 종가(y 정의)", from = "E <- R[Date %in% M$d1, .(d1 = Date, Ticker, en = Open)]", to = "E <- R[Date %in% M$d1, .(d1 = Date, Ticker, en = as.numeric(Close))]",
       kill = function(e) !isTRUE(e$p5_ydef_check(RXE, ROOT)$ok) || !isTRUE(all.equal(e$p5_labels(RL8, cal8, 2L)[Date == cal8[1] & Ticker == "A"]$y_raw, 12 / 10.5 - 1))),
  list(nm = "꼬리 고유에서 Sk 빠뜨림", from = "tu <- all(c(ss, ns, qs) == \"no_win\") && dt_ok", to = "tu <- all(c(ns, qs) == \"no_win\") && dt_ok",
       kill = function(e) { Sx <- cell("E2", "S1", pcd(c("a", "d"), c(0.7, 0.5), c(0.6, 0.6))); !identical(e$p5_read_tail_unique(V1d, Sx, Nd, Qc, TI_OK, 2, 0.03)$n_tail_unique, 0L) }),
  list(nm = "V1 전달량(≠ Q50) 검사 빠뜨림", from = "if (!p2_treatment_delivered(ovq)) return(.p2_untested(out, sprintf(\"무처치(⑩ V1 = Q50)", to = "if (FALSE) return(.p2_untested(out, sprintf(\"무처치(⑩ V1 = Q50)",
       kill = function(e) !grepl("V1 = Q50", e$p5_eval_pair_safe(X0, "E2", "V1", cv("V1q", "V1"), cR, evd(A_D), evd(A_R), JO(q50 = qsame))$why)),
  list(nm = "τ_D 경계 ≤ → <(보는 창 RAW)", from = "p5_visible_cut <- function(RAW, tau) RAW[Date <= as.Date(tau)]", to = "p5_visible_cut <- function(RAW, tau) RAW[Date < as.Date(tau)]",
       kill = function(e) !identical(nrow(e$p5_visible_cut(RAWS, tauT)[Date == tauT]), 30L)),
  list(nm = "보는 창 신호일 < → <=", from = "p5_visible_signals <- function(Q, tau) Q[Date < .p5_month_floor(tau)]", to = "p5_visible_signals <- function(Q, tau) Q[Date <= .p5_month_floor(tau)]",
       kill = function(e) !identical(e$p5_visible_signals(data.table(Date = as.Date(c("2021-06-30", "2021-07-01", "2021-07-30")), x = 1), tauT)$Date, as.Date("2021-06-30"))),
  list(nm = "LV 읽기에서 tol 빠뜨림", from = "variant_beats_lv = if (is.finite(mv) && is.finite(ml)) mv < ml - tol else NA", to = "variant_beats_lv = if (is.finite(mv) && is.finite(ml)) mv < ml else NA",
       kill = function(e) !identical(e$p5_read_lowvol(Vlv, LVa, 0.03)$name, "원천 ① 증분 없음(저용량 변동성 스크린과 같음)")),
  list(nm = "Dimson lag 계수 빠뜨림", from = "list(beta = unname(sum(b[2:4])),", to = "list(beta = unname(sum(b[3:4])),",
       kill = function(e) !isTRUE(abs(e$p5_dimson_beta(rr2, mm)$beta - 1.0) < 0.01)),
  ## ⑩ · ⑮ · 기록 · 읽기 · 판정 문
  list(nm = "템플릿 대조 rc 검사 제거", from = "list(ok = identical(rc, 0L), rc = rc, status = if (identical(rc, 0L)) \"ok\" else \"fail\"", to = "list(ok = TRUE, rc = rc, status = if (identical(rc, 0L)) \"ok\" else \"fail\"",
       kill = function(e) isTRUE(e$p5_template_check(TD, runner = function(f) structure("x", status = 1L))$ok)),
  list(nm = "워밍 캐시 완료 검사 제거", from = "okC <- is.finite(cm$done) && is.finite(cm$total) && cm$total >= 1 && cm$done == cm$total", to = "okC <- TRUE",
       kill = function(e) isTRUE(e$p5_warm_check(file.path(WD, "c"))$ok)),
  list(nm = "기저 적재 md5 앞 12자 대조 제거", from = "hit <- P$loads[md5_12 == m12]", to = "hit <- P$loads",
       kill = function(e) isTRUE(e$p5_base_load_check(p5_parse_base_load(hitl("RX0")), pinv("V2"))$ok)),   # 적중 줄만(다른 엔진 md5) — 대조가 없으면 아무 적중 줄이나 통과
  list(nm = "예측표 판본 단정 제거", from = "if (length(bad_v)) p5_halt(", to = "if (FALSE) p5_halt(",
       kill = function(e) !identical(tryCatch({ e$p5_qpred_load(file.path(QD, "b"), TAU); "no_halt" }, p5_halt = function(z) "halt"), "halt")),
  list(nm = "⑮ 문 제거", from = "if (!isTRUE(x$tested) || isTRUE(tail$pass)) return(x)", to = "return(x)",
       kill = function(e) !identical(e$p5_apply_tail_gate(xt, list(status = "ok", t = 1.2, t_min = 2, pass = FALSE))$verdict, "untested_tail_instrument")),
  list(nm = "칸 통과에서 ⑮ 제거", from = "isTRUE(f$selection) && isTRUE(f$tail)", to = "isTRUE(f$selection)",
       kill = function(e) isTRUE(e$p2_cell_pass(FL_NOTAIL))),
  list(nm = "희석 등록 판독을 깊은 위기로", from = "reg <- p2_read_overlap_wins(v$rules$crisis$per_crisis, n$rules$crisis$per_crisis, tol)", to = "reg <- p2_read_overlap_wins(v$rules$deep$per_crisis, n$rules$deep$per_crisis, tol)",
       kill = function(e) !identical(e$p5_read_dilution(V1c, Nc, 0.03)$dilution, c("a", "e"))),
  list(nm = "교차율을 재배열 뒤 열로", from = "crossing_pooled = if (any(ok3)) mean((Q$q10_raw > Q$q50_raw | Q$q50_raw > Q$q90_raw)[ok3])", to = "crossing_pooled = if (any(ok3)) mean((Q$q10 > Q$q50 | Q$q50 > Q$q90)[ok3])",
       kill = function(e) !isTRUE(abs(e$p5_crossing(QZ)$crossing_pooled - mean(seq_len(nrow(QZ)) %% 7 == 1)) < 1e-12)),
  list(nm = "D^σ 를 s_perm 으로", from = "d_sigma = .sf(p5_dalt(QY, TI, nw, \"s_sigma\"))", to = "d_sigma = .sf(p5_dalt(QY, TI, nw, \"s_perm\"))",
       kill = function(e) !identical(e$p5_tail_block(QS, RAWS, YDS, TI, NW, PRMS, deep_ym = "2021-04", "visible")$records$d_sigma$s_col, "s_sigma")),
  list(nm = "거부 경계 ≤ → <", from = "out[is.finite(q)] <- (r[is.finite(q)] / n) <= share", to = "out[is.finite(q)] <- (r[is.finite(q)] / n) < share",
       kill = function(e) !identical(e$p5_veto(1:10, 0.2), c(TRUE, TRUE, rep(FALSE, 8)))),
  list(nm = "위기 유형 경계 eps 무력화", from = "C[, boundary := is.finite(th) & is.finite(rho_W) & abs(rho_W - th) < eps]", to = "C[, boundary := is.finite(th) & is.finite(rho_W) & abs(rho_W - th) < 0]",
       kill = function(e) !identical(e$p5_load_crisis_types(ROOT, pin_ok)$classes[boundary == TRUE, k], "2011-05-02 2011-09-26")),
  list(nm = "분류 판본 대조 제거", from = "else if (!identical(pin, md5)) \"분류 판본 다름\" else NA_character_", to = "else NA_character_",
       kill = function(e) !identical(e$p5_load_crisis_types(ROOT, list(design_inputs = list(files = list(list(path = P2R05_CRISIS_TYPE_NOTE, md5 = "x")))))$pin_tag, "분류 판본 다름")),
  list(nm = "R7 방어 성분이 ③ 무시", from = "res_d <- if (!readable_d) NA else c1 && (n3d == 0L)", to = "res_d <- if (!readable_d) NA else c1",
       kill = function(e) !identical(e$p2_noise_reading(NO2, character(0), 0.02, 0.5)$defense_component$result, FALSE)),
  list(nm = "LV 빈 전제 가드 제거(LV 승리 0 = 미결)", from = "if (!length(lw)) return(c(base, list(status = \"ok\", n_lv_win = 0L", to = "if (FALSE) return(c(base, list(status = \"ok\", n_lv_win = 0L",
       kill = function(e) !identical(e$p5_read_lowvol(Vlv, LVn, 0.03)$name_status, "undetermined")),
  list(nm = "용량 표 일치를 any 로", from = "if (all(is.na(pat) | pat == x)) return(table$label[i]) }", to = "if (any(is.na(pat) | pat == x)) return(table$label[i]) }",
       kill = function(e) !identical(e$p5_capacity_label(FALSE, FALSE, FALSE), P2R05_CAPACITY_TABLE$label[4])),
  list(nm = "Kelley 부호", from = "kel = ifelse(q90 - q10 > 0, (q90 + q10 - 2 * q50) / (q90 - q10), NA_real_)", to = "kel = ifelse(q90 - q10 > 0, (q90 - q10 - 2 * q50) / (q90 - q10), NA_real_)",
       kill = function(e) !isTRUE(abs(e$p5_kelley_hold(QK, data.table(date = dts[1] + 1L, ticker = c("A", "B"), w = c(0.75, 0.25)), TAU)$mean - kref) < 1e-12)),
  list(nm = "상위 n 동점을 거래대금 오름으로", from = "o <- idx[order(-score[idx], -ifelse(is.finite(adv[idx]), adv[idx], -Inf), tk[idx])]", to = "o <- idx[order(-score[idx], ifelse(is.finite(adv[idx]), adv[idx], -Inf), tk[idx])]",
       kill = function(e) !identical(e$p5_top_flag(c(5, 5, 4, 5, 3), c(TRUE, TRUE, TRUE, FALSE, TRUE), c(1e9, 2e9, 5e9, 9e9, NA), c("B", "A", "C", "D", "E"), 2L), c(TRUE, TRUE, FALSE, FALSE, FALSE)) ||
                            !identical(e$p5_top_flag(c(5, 5, 5), c(TRUE, TRUE, TRUE), c(1e9, 3e9, 2e9), c("A", "B", "C"), 1L), c(FALSE, TRUE, FALSE))),
  list(nm = "엔진 핀 대조 제거", from = "okN <- length(vp) > 0L && length(rp) > 0L && all(vapply(c(vp, rp), function(z) isTRUE(z$ok), logical(1)))", to = "okN <- TRUE",
       kill = function(e) isTRUE(e$p5_engine_check(rsp("V1"), rsp("R"), "V1", list(operational_pins = list(files = PRE_STUB$operational_pins$files[-2])), STR)$ok)),
  list(nm = "⑩ months= 대조 제거", from = "okM <- isTRUE(lv$found) && isTRUE(lr$found) && identical(lv$months, lr$months)", to = "okM <- TRUE",
       kill = function(e) isTRUE(e$p5_construction_dt("V1", rsp("V1"), rsp("R"), p2_parse_cell_log(rdl("V1m")), p2_parse_cell_log(rdl("R")), rdl("V1m"), rdl("R"), CTX, "V1m", "R")$ok)),
  list(nm = "결론 꼬리 학습 방어 조건에서 방어 성립 빠뜨림", from = "name <- if (granted && ntu > 0L) sprintf(", to = "name <- if (ntu > 0L) sprintf(",
       kill = function(e) grepl("꼬리 학습", e$p5_conclusion(xl, rdg, NULL)$name)),
  list(nm = "표적 블록 합성 대조 무력화", from = "ok <- all(okf) && okc && isTRUE(orc$ok)", to = "ok <- all(okf) && okc",
       kill = function(e) isTRUE(e$p5_ydef_check(RXE, ROOT, label_fun = bad_lab)$ok)),
  ## 판단 T1 R-007 · 철학 P1 R-008 · 철학 P4 C-076 · Q 10-18 정렬 2
  list(nm = "시드 띠 부등호 < → >", from = "undetermined = ifelse(is.finite(band), gap < band, NA)", to = "undetermined = ifelse(is.finite(band), gap > band, NA)",
       kill = function(e) !identical(e$p5_seed_tags(Vsd, BD)$deep[crisis == "a"]$undetermined, TRUE)),
  list(nm = "D^w 거울 부호(q̂50 + 폭)", from = "D = mean(p5_rho(y - (q50 - (q90 - q50)), tau)", to = "D = mean(p5_rho(y - (q50 + (q90 - q50)), tau)",
       kill = function(e) !isTRUE(all.equal(e$p5_dwidth(QW, TI, NW)$per_date$D, Dw))),
  list(nm = "같은 추첨 k' 대신 k(β_V/β_RX0)", from = "p <- p2_beta_plan(bv, bq)", to = "p <- p2_beta_plan(bv, br)",
       kill = function(e) !isTRUE(abs(e$p5_same_draw_plan(PMs, PQs, PRs)$k - 0.8) < 1e-12)),
  list(nm = "유동성 3분위 t−1 → 당일 거래대금(C10)", from = "L[, adv20_l1 := shift(frollmean(Close * Vol, 20L, align = \"right\"), 1L), by = Ticker]",
       to = "L[, adv20_l1 := frollmean(Close * Vol, 20L, align = \"right\"), by = Ticker]",
       kill = function(e) !identical(e$p5_liq_tercile_cell(E_TA, A42v, CRK42, R42, e$p5_liq_from(R42), hy42, TAU)$per_crisis[[1]]$names[Ticker == "U2"]$tercile, "low")),
  list(nm = "유동성 재구성 대조 단정 제거", from = "recon_ok = is.finite(gap) && abs(gap) < tol, recon_tol = tol,", to = "recon_ok = TRUE, recon_tol = tol,",
       kill = function(e) !identical(e$p5_liq_tercile_cell(E_TA, A42m, CRK42, R42, LIQ42, hy42, TAU)$per_crisis[[1]]$recon_ok, FALSE)),
  list(nm = "저 분위 과반 부등호 > → <", from = "low_attributed = if (is.finite(sh)) sh > as.numeric(maj) else NA", to = "low_attributed = if (is.finite(sh)) sh < as.numeric(maj) else NA",
       kill = function(e) !isTRUE(e$p5_liq_improvement(LV42$per_crisis, LR42$per_crisis, 0.5)$per_crisis$low_attributed)),
  list(nm = "유동성 귀속 미측정 의무 꼬리표 제거", from = "liqtag <- if (is.null(x$liq_attr) || !identical(x$liq_attr$status, \"ok\")) \"유동성 귀속 미측정\" else x$liq_attr$tags",
       to = "liqtag <- x$liq_attr$tags", kill = function(e) !("유동성 귀속 미측정" %in% e$p5_conclusion(xg, rdg, NULL)$tags)),
  list(nm = "워밍 센티널 사본 우선 제거", from = "w <- p5_warm_check(if (hb) bound else night_path, code_version)", to = "w <- p5_warm_check(night_path, code_version)",
       kill = function(e) !isTRUE(e$p5_warm_resolve(WR, file.path(WR, "night.done"))$ok)),
  list(nm = "표적 정의 대상에서 재시드 제외 제거", from = "p5_dt_engine_files <- function(cells, root) unique(unlist(lapply(Filter(function(cl) !isTRUE(p5_expected_engines(cl$component)$reseed), cells), function(cl) {",
       to = "p5_dt_engine_files <- function(cells, root) unique(unlist(lapply(cells, function(cl) {", kill = function(e) any(grepl("rx0s/", e$p5_dt_engine_files(cells43, STR), fixed = TRUE))),
  list(nm = "미시험 칸 rules 정확 이름 제거($ 부분 일치)", from = "  if (is.null(out[[\"rules\"]])) out[[\"rules\"]] <- list()", to = "  invisible(NULL)",
       kill = function(e) !is.list(e$.p2_untested(list(engine = "E2", device = "V1", rules_computed = FALSE), "x")[["rules"]])),
  ## 격리 교차 점검 v1(필수 1 · 2 · 4 · 권고 5)
  list(nm = "판정어 ⑮ 먼저 제거", from = "  if (identical(f$tail, FALSE)) \"untested_tail_instrument\" else", to = "  if (FALSE) \"untested_tail_instrument\" else",
       kill = function(e) !identical(e$p2_cell_verdict(list(pass = FALSE, beta_unmeasured = FALSE, beta_deep = TRUE, fast = TRUE, crisis = TRUE, deep = TRUE, selection = TRUE, selection_measured = TRUE,
                                                           level = TRUE, beta_ratio = TRUE, strength = F15$strength, tail = FALSE)), "untested_tail_instrument")),
  list(nm = "판정어 ⑤ 단계 제거", from = "  if (!isTRUE(f$level) || !isTRUE(f$beta_ratio)) \"asymmetry_unmet\" else", to = "  if (FALSE) \"asymmetry_unmet\" else",
       kill = function(e) !identical(e$p2_cell_verdict(list(pass = FALSE, beta_unmeasured = FALSE, beta_deep = TRUE, fast = TRUE, crisis = TRUE, deep = TRUE, selection = TRUE, selection_measured = TRUE,
                                                           level = TRUE, beta_ratio = FALSE, strength = F6$strength, tail = TRUE)), "asymmetry_unmet")),
  list(nm = "꼬리 회피 기계 정의에서 ① ② 빠뜨림", from = "  isTRUE(tail) && isTRUE(crisis) && isTRUE(deep) && isTRUE(r3) && isTRUE(r4) && isTRUE(s14m) && isTRUE(s14) && isTRUE(level) && isTRUE(ratio) &&",
       to = "  isTRUE(tail) && isTRUE(r3) && isTRUE(r4) && isTRUE(s14m) && isTRUE(s14) && isTRUE(level) && isTRUE(ratio) &&",
       kill = function(e) "꼬리 회피 기계(방어만 · 복리 없음)" %in% e$p5_conclusion(list(rules_computed = TRUE, tested = TRUE, tail_gate = list(pass = TRUE), flags = F16, reference_points = list()), NULL, NULL)$tags),
  list(nm = "LV ⊆ 조건 제거", from = "  outv <- setdiff(base$variant_wins, lw)", to = "  outv <- character(0)",
       kill = function(e) !identical(e$p5_read_lowvol(Vlv, LVc, 0.03)$name, "LV 대비 증분 있음")),
  list(nm = "LV Vk 승리 0 가드 제거", from = "  if (!length(base$variant_wins)) return(c(base, list(status = \"ok\", n_lv_win = nrow(P), n_variant_beats_lv = sum(P$variant_beats_lv), per_crisis = P,",
       to = "  if (FALSE) return(c(base, list(status = \"ok\", n_lv_win = nrow(P), n_variant_beats_lv = sum(P$variant_beats_lv), per_crisis = P,",
       kill = function(e) !identical(e$p5_read_lowvol(cell("E2", "V1", pcd(c("a", "b"), c(0.7, 0.7), c(0.6, 0.6))), LVa, 0.03)$name_status, "not_applicable")),
  list(nm = "예측표 md5 대조 제거", from = "  if (!identical(m, mv)) p5_halt(", to = "  if (FALSE) p5_halt(",
       kill = function(e) !identical(haltof(e$p5_qpred_bound(QB, wsen("w_md5k.json", list(path = "q/aaaa1111_bbbb2222.parquet", md5 = strrep("0", 32))), TAU, qdir = file.path(QB, "q"))),
                                     "예측표 md5 ≠ 측정 묶음(워밍 센티널 qpred.md5)")),
  list(nm = "예측표 폴더 전체 읽기 회귀", from = "  QP <- p5_qpred_load(dirname(f), tau, files = f)", to = "  QP <- p5_qpred_load(dirname(f), tau)",
       kill = function(e) !identical(tryCatch(e$p5_qpred_bound(QB, wsen("w_okk.json", list(path = "q/aaaa1111_bbbb2222.parquet", md5 = unname(tools::md5sum(QBa)))), TAU, qdir = file.path(QB, "q"))$status,
                                              p5_halt = function(z) "halt"), "ok")),
  list(nm = "수평 판독 부등호 ≤ → >", from = "  mm <- vb <= br", to = "  mm <- vb > br",
       kill = function(e) !isTRUE(e$p5_horizon_reading(list(status = "ok", veto = list(bottom = 0.2), base_rate = 0.2))$mismatch)),
  ## 격리 점검 v2 필수 1 — ⑮ 예측표 셀 로그 대조
  list(nm = "셀 로그 경로 다름 중단 제거", from = 'if (!identical(.p5_npath(q, root), B)) p5_halt("셀 로그 예측표 ≠ 측정 묶음(워밍 센티널 qpred)"', to = 'if (FALSE) p5_halt("셀 로그 예측표 ≠ 측정 묶음(워밍 센티널 qpred)"',
       kill = function(e) !identical(haltof(e$p5_qpred_log_check(C47, R47b, STR, B47)), "셀 로그 예측표 ≠ 측정 묶음(워밍 센티널 qpred)")),
  list(nm = "셀 로그 경로 정규화 제거(원문 비교)", from = 'if (!identical(.p5_npath(q, root), B)) p5_halt(', to = 'if (!identical(q, B)) p5_halt(',
       kill = function(e) !identical(haltof(e$p5_qpred_log_check(C47, R47a, STR, B47)), "no_halt")),
  list(nm = "셀 로그 md5 중단 제거", from = 'mq <- p5_md5(qf); if (!is.na(mq) && !identical(mq, bound$md5)) p5_halt(', to = 'mq <- p5_md5(qf); if (FALSE) p5_halt(',
       kill = function(e) !identical(haltof(e$p5_qpred_log_check(C47, R47a, STR, B47m)), "셀 로그 예측표 md5 ≠ 측정 묶음(워밍 센티널 qpred)")),
  list(nm = "연쇄 대조 끊기", from = "if (length(ch) && !length(run))", to = "if (FALSE && length(ch) && !length(run))",
       kill = function(e) !identical(st47(e$p5_qpred_log_check(C47, R47a, STR, B47), "E3_V1"), "chained")),
  list(nm = "연쇄 출처를 예측표 일치 칸으로 한정 안 함", from = "for (r in rows) if (length(r$q)) {", to = "for (r in rows) if (TRUE) {",
       kill = function(e) !identical(st47(e$p5_qpred_log_check(C47, R47c, STR, B47), "E3_V1"), "unverifiable")),
  list(nm = "셀 로그 대조 재시드 짝 제외 제거", from = "    if (isTRUE(p5_expected_engines(cl$component)$reseed)) next", to = "    if (FALSE) next",
       kill = function(e) !identical(haltof(e$p5_qpred_log_check(C47, R47a, STR, B47)), "no_halt")),
  list(nm = "셀 로그 없음을 대조 불가로", from = "if (!isTRUE(r$has_log)) return(", to = "if (FALSE) return(",
       kill = function(e) !identical(st47(e$p5_qpred_log_check(C47, R47a, STR, B47), "E3_V2"), "no_log")),
  list(nm = "결론 셀 로그 꼬리표 제거", from = 'qltag <- if (identical(x$qpred_log$status, "unverifiable"))', to = 'qltag <- if (FALSE)',
       kill = function(e) !(QLT %in% e$p5_conclusion(x47u, rdg, NULL)$tags)),
  ## P2R04 승계 뮤테이션(판정 ①~⑭ 코드 경로 그대로임을 같은 뮤턴트로 다시 확인)
  list(nm = "과반 > → >=", from = "is.finite(s) && is.finite(m) && s > m }", to = "is.finite(s) && is.finite(m) && s >= m }", kill = function(e) isTRUE(e$p2_maj(0.5, 0.5))),
  list(nm = "β 짝 k ≥ 1 분기 제거", from = 'else if (k >= 1) "rx0" else "scaled"', to = 'else "scaled"', kill = function(e) !identical(e$p2_beta_plan(1.2, 1)$mode, "rx0")),
  list(nm = "크기 × β 바스켓 차입", from = 'scale = if (identical(mode, "unmeasured")) NA_real_ else min(k, 1)', to = 'scale = if (identical(mode, "unmeasured")) NA_real_ else k',
       kill = function(e) !identical(e$p2_size_beta_plan(1.2, 1)$scale, 1)),
  list(nm = "⑩ 무처치 검사 제거", from = 'identical(ov$status, "ok") && isTRUE(ov$n_differ > 0L)', to = 'identical(ov$status, "ok")', kill = function(e) isTRUE(e$p2_treatment_delivered(o_i))),
  list(nm = "판정 칸도 무처치 통과", from = '(!diag || !identical(ov$status, "ok"))', to = '(!identical(ov$status, "ok"))',
       kill = function(e) !grepl("무처치", e$p5_eval_pair_safe(X0, "E2", "V1", cv("V1i", "V1"), cR, evd(A_I), evd(A_R), JO(q50 = qok))$why)),
  list(nm = "opts 부분 일치 회귀($expect_cell)", from = 'ec <- opts[["expect_cell"]] %||% cm$code', to = 'ec <- opts$expect_cell %||% cm$code',
       kill = function(e) !isTRUE(e$p5_eval_pair_safe(X0, "E2", "V1", cv("V1l", "V1"), cR, evd(A_D), evd(A_R), JO(q50 = qok, expect_cell_rx0 = "R"))$construction$ok)),
  list(nm = "두 구성 조건 제거", from = "both <- agg[n_pass == 2L & !ex, device]", to = "both <- agg[n_pass >= 1L & !ex, device]", kill = function(e) !identical(e$p2_round_verdict(T1)$both, "V1")),
  list(nm = "집중 문턱 부호", from = "n_breach = sum(deep$top1 < floor)", to = "n_breach = sum(deep$top1 > floor)", kill = function(e) !identical(e$p2_conc_status(e$p2_top_loss(tl2, "2020-01-22", -0.10)), "clear")),
  list(nm = "보유 다름을 이름 집합만으로", from = "differ = !setequal(a$ticker, b$ticker) || any(wa != wb))", to = "differ = !setequal(a$ticker, b$ticker))",
       kill = function(e) identical(e$p2_holdings_overlap(H_W, H_R, TAU)$n_differ, 0L)),
  list(nm = "selection_unmeasured 분기 제거", from = 'if (isTRUE(r3) && isTRUE(r4) && !m14) "selection_unmeasured" else', to = 'if (FALSE) "selection_unmeasured" else',
       kill = function(e) !identical(e$p2_cell_verdict(list(pass = FALSE, beta_unmeasured = FALSE, beta_deep = TRUE, fast = TRUE, selection_measured = FALSE)), "selection_unmeasured")),
  list(nm = "⑭ 분해 부등호 > → >=", from = "J[, better := sv - sr > 0]", to = "J[, better := sv - sr >= 0]",
       kill = function(e) !identical(e$p2_selection_decomp(J(data.table(peak_date = PK4, selection_sum = -0.10)), ERX, PK4, 0.5)$ok, FALSE)),
  list(nm = "MC8 insufficient 를 측정으로", from = 'else if (is.na(lb) || !(lb %in% P2R05_MC8_LABELS)) "unmeasured" else "ok"', to = 'else if (is.na(lb)) "unmeasured" else "ok"',
       kill = function(e) !identical(e$p2_selection_attr("insufficient", "selection_defense")$status, "unmeasured")),
  list(nm = "결론 ③ · ④ NA 보류 제거", from = 'if (is.na(r3 %||% NA) || is.na(r4 %||% NA)) return("방어 이름 보류(③ · ④ β 짝 미측정)")', to = 'if (FALSE) return("방어 이름 보류(③ · ④ β 짝 미측정)")',
       kill = function(e) !grepl("보류", e$p2_defense_name(NA, TRUE, TRUE, TRUE, TRUE, "ok"))),
  list(nm = "R7 ③ 측정 조건 제거", from = 'r3m <- tst & st3 %in% "ok" & !is.na(np3) & np3 >= 2L & is.finite(sh3)', to = "r3m <- tst",
       kill = function(e) !is.na(e$p2_noise_reading(NO8, character(0), 0.02, 0.5)$result)),
  list(nm = "R7 판독 불가 규칙 제거", from = "readable <- nb >= 2L; readable_d <- nbd >= 2L", to = "readable <- TRUE; readable_d <- nbd >= 2L",
       kill = function(e) !is.na(e$p2_noise_reading(NOS, character(0), 0.02, 0.5)$result)),
  list(nm = "R7 S 증분 문턱 제거", from = "c3 <- is.finite(dmax) && dmax < as.numeric(tie_eps)", to = "c3 <- is.finite(dmax)",
       kill = function(e) isTRUE(e$p2_noise_reading(NO3, character(0), 0.02, 0.5)$result)),
  list(nm = "보는 창 시험 창 알파 제거 누락", from = 'P2R05_VISIBLE_DROP <- c("alpha_test_window", "tbl", "cell_log_full_period")', to = 'P2R05_VISIBLE_DROP <- c("tbl", "cell_log_full_period")',
       kill = function(e) !is.null(e$p2_visible_only(XV, TAU)$alpha_test_window)),
  list(nm = "τ_D 이후 날짜 가림 제거", from = "if (is.character(x)) return(.p2_redact_chr(x, tau))", to = "if (is.character(x)) return(x)",
       kill = function(e) grepl("2023-05-02", e$p2_visible_only(XV, TAU)$why)),
  list(nm = "대조 함수 없는 핀 종류 묵인", from = 'if (length(unk)) bad <- c(bad, paste("대조 함수 없는 운영 핀 종류', to = 'if (FALSE) bad <- c(bad, paste("대조 함수 없는 운영 핀 종류',
       kill = function(e) !length(e$p2_pin_mismatches(pre_unk, PRT))),
  list(nm = "빠름 창 한 칸 넓힘", from = "e <- min(i1, a + as.integer(win))", to = "e <- min(i1, a + as.integer(win) + 1L)", kill = function(e) !identical(e$p2_fast_crash_keys(BR, CRF, 21L, -0.20)$keys, fk$keys)),
  list(nm = "음수 기준 일반화 제거", from = "thr := r - (1 - ratio) * abs(r)", to = "thr := ratio * r",
       kill = function(e) !identical(e$p2_bull_segments(bm5, br5, 0.8, 2L)$per_phase[order(k)]$ok, c(TRUE, FALSE, TRUE, FALSE))),
  list(nm = "β 비 Δ → 차이", from = "rv <- x[1] / x[2]; rr <- x[3] / x[4]", to = "rv <- x[1] - x[2]; rr <- x[3] - x[4]",
       kill = function(e) isTRUE(e$p2_beta_ratio_delta(0.7 * 1.31, 0.7 * 0.99, 1.31, 0.99)$ok)),
  list(nm = "β 짝 사본 표식 제거", from = ".p2_mark_full(dir = out_dir)", to = "invisible(NULL)",
       kill = function(e) { od <- file.path(TMP, "p2r05_mut_bout"); unlink(od, recursive = TRUE); e$p2_beta_scaled_copy(bsrc, od, 0.8); !file.exists(file.path(od, "NO_VISIBLE_REVIEW.txt")) }))
nk <- 0L; mres <- character(0)
E_ORIG <- local({ e <- new.env(); sys.source(EVF, envir = e, keep.source = FALSE); e })   # 원본 사본(같은 적재 경로) — 검출 함수가 원본에서 거짓 · 오류 없음이어야 한다
for (m in MU) {
  k0 <- tryCatch(isTRUE(m$kill(E_ORIG)), error = function(z) NA)
  if (!identical(k0, FALSE)) { ng(paste("뮤테이션 검출 함수 원본 대조", m$nm), if (is.na(k0)) "원본에서 오류" else "원본에서도 참"); mres <- c(mres, sprintf("%s: 검출 함수 무효", m$nm)); next }
  mt <- mutant(m$from, m$to)
  if (!is.null(mt$err)) { ng(paste("뮤테이션", m$nm), mt$err); mres <- c(mres, sprintf("%s: 오류", m$nm)); next }
  kd <- tryCatch(isTRUE(m$kill(mt$env)), error = function(z) TRUE)                # 뮤턴트가 픽스처 경로에서 멈추면 그것도 검출(실패)
  if (kd) { nk <- nk + 1L; mres <- c(mres, sprintf("%s: 검출", m$nm)) } else { ng(paste("뮤테이션 생존", m$nm)); mres <- c(mres, sprintf("%s: 생존", m$nm)) }
}
if (nk == length(MU)) ok(sprintf("M 뮤테이션 %d/%d 검출(치환 대상 1줄 · 치환 성사 · 사본 단독 적재)", nk, length(MU)))
cat(sprintf("합계 PASS %d FAIL %d · 뮤테이션 검출 %d/%d\n", PASS, FAIL, nk, length(MU)))
cat(sprintf('{"test":"p2r05_evaluate_fixture","pass":%d,"fail":%d,"total":%d,"mutants_killed":%d,"mutants_total":%d}\n', PASS, FAIL, PASS + FAIL, nk, length(MU)))
if (FAIL > 0L) quit(status = 1L)
