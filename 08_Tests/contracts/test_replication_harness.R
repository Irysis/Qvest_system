# test_replication_harness.R — v10 충실구현 하네스의 양방향 검증 (합성 데이터)
#
# 계약 (v10 2026-08-29):
#   ① 롱숏 부호 정확성 — 숏 레그가 하락하면 LS 수익 양(+)
#   ② 비용 실효 — commission>0 이면 NAV_net < NAV_gross
#   ③ PIT t+1 — Exec_Date = 시그널 익월 첫 거래일 (> Signal_Date)
#   ④ 종목수 무제한 — n=60 롱숏 완주 + diagnostics$n_max 정확
#   ⑤ 계약 왕복 — build_bt_result → audit: constraint_profile="replication" 이면
#      holdings_cap 이 n>25 에도 PASS(보고만), 프로파일 없으면 FAIL (양방향)
#   ⑥ L-code enum — paper_replication/reinforcement + RP/RF prefix
#   ⑦ L-code construction_type 파생
#   ── 2026-09-24 플랜 P0-04(집행 규약 close_t1) · P0-03(회계 무결성) 보강 — ③ 은 Exec_Date **라벨**만 봤다.
#      아래는 **실현 수익 귀속**을 잰다(라벨이 아니라 실현값):
#   ⑧ 위반 주입 — d 종가 정보로 편입한 종목이 집행일에만 +10%: legacy 는 새 보유가 그 수익을 얻고
#      close_t1·open_t1 은 얻지 못한다. 양성 대조: 집행 다음 날 +10% 는 close_t1 새 보유가 얻는다.
#      돌연변이(close_t1 창을 >= 로 되돌린 사본) red.
#   ⑨ 집행일 수익 = 직전 보유의 **드리프트** 비중(목표 비중 아님)
#   ⑩ 비용 기장일 — legacy exec 행 가산 / close_t1 첫 보유일 곱 · exec 행 무비용 · NAV 비 = Π(1−Σ|Δw|c)
#   ⑪ P0-03 첫 행 ret_gross 복원(하네스 Rg 반환) + 폴백 경로 첫 행 = 비용 미상(0) · 구판 NA→0 돌연변이 red
#   ⑫ P0-03 audit cost_sign — 음의 비용 주입 FAIL(high · integrity WARNING) · 청정 PASS
#   ⑬ 설정 기본값 — constraint_defaults.json::execution.exec_price 를 **소비**한다(라벨만이 아니라 산출 동일) ·
#      부재/허용 밖/명시 경로 부재 = 멈춤(fail-closed) · 운영값 close_t1
#   ⑭ open_t1 가드 — 미수정 Open 주입은 플래그 + close_t1 처리 · 가드 한도를 설정에서 읽는다(한도 완화 사본 red)
#   ⑮ strategy_spec(.rp_strategy_spec) — 진술·엔진 경로·비용 라벨이 실현값 · integrity WARNING 상수 해소 ·
#      생존 통제는 러너가 멤버십을 적용할 때만 진술 · Check 13 비발화
#   ⑯ 러너 배선 — 두 sim 호출이 exec_price 인자를 넘긴다 · 돌연변이(sim_grade 인자 삭제) red
#   (패리티 = test_replication_exec_parity.R · 골든 재현 = test_replication_exec_golden.R)
#
# 실행: Rscript 08_Tests/contracts/test_replication_harness.R

# 앵커 = self-first (r-portability 금칙 ④-b: 테스트 러너는 자기 위치 1순위 — env 는 폴백)
.self <- tryCatch({
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", a[grepl("^--file=", a)])
  if (length(f)) dirname(f[1]) else "."
}, error = function(e) ".")
root <- normalizePath(file.path(.self, "..", ".."), winslash = "/", mustWork = FALSE)
if (!file.exists(file.path(root, "02_Infrastructure", "config.R")))
  root <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(root)
suppressPackageStartupMessages({
  library(data.table); library(xts); library(PerformanceAnalytics); library(jsonlite)
})

pass <- 0L; fail <- 0L
ok <- function(m) { cat(sprintf("  [PASS] %s\n", m)); pass <<- pass + 1L }
ng <- function(m) { cat(sprintf("  [FAIL] %s\n", m)); fail <<- fail + 1L }

# 실제 t+1 규약과 동일 (backtest_harness.R:316 — 시그널 익월 첫 거래일)
get_execution_date <- function(signal_date, all_dates) {
  ym <- format(signal_date, "%Y-%m")
  yr <- as.integer(substr(ym, 1, 4)); mo <- as.integer(substr(ym, 6, 7))
  if (mo == 12) { yr <- yr + 1; mo <- 1 } else { mo <- mo + 1 }
  cands <- all_dates[all_dates >= as.Date(sprintf("%04d-%02d-01", yr, mo))]
  if (length(cands) > 0) min(cands) else NA
}

source("02_Infrastructure/replication/replication_harness.R")

# ── 합성 데이터: 2020-01 ~ 2020-06, 평일만. UP 종목 +0.2%/일, DN 종목 −0.2%/일 ──
mk_raw <- function(n_up, n_dn) {
  dates <- seq(as.Date("2020-01-01"), as.Date("2020-06-30"), by = "day")
  dates <- dates[!format(dates, "%u") %in% c("6", "7")]
  tick <- c(sprintf("UP%03d", seq_len(n_up)), sprintf("DN%03d", seq_len(n_dn)))
  g <- CJ(Date = dates, Ticker = tick)
  g[, Ret := ifelse(grepl("^UP", Ticker), 0.002, -0.002)]
  g[, Close := 100 * cumprod(1 + Ret), by = Ticker]
  g
}
RAW <- mk_raw(3, 3)
BM <- unique(RAW[, .(Date)])[, BM_Ret := 0.0001][]
all_d <- sort(unique(RAW$Date))
sig_d <- as.Date(c("2020-01-31", "2020-02-29", "2020-03-31", "2020-04-30"))
sig_d <- as.Date(sapply(sig_d, function(d) max(all_d[format(all_d, "%Y-%m") == format(d, "%Y-%m")])))

# ① 롱숏: long UP, short DN → 양(+) 수익
W_LS <- rbindlist(lapply(sig_d, function(d) data.table(
  Date = d,
  Ticker = c("UP001", "UP002", "DN001", "DN002"),
  Weight = c(0.5, 0.5, -0.5, -0.5))))
sim <- run_replication_simulation(copy(RAW), copy(BM), W_LS, commission = 0)
tot <- as.numeric(last(sim$DAILY_NAV_DT$NAV)) - 1
if (is.finite(tot) && tot > 0) ok(sprintf("① 롱숏 부호 — LS 총수익 %+.2f%% > 0", tot * 100)) else
  ng(sprintf("① 롱숏 부호 — 총수익 %+.4f (양수 기대)", tot))
if (any(sim$HOLDINGS_LOG$Leg == "short")) ok("① 숏 레그 HOLDINGS_LOG 기록") else ng("① 숏 레그 기록 부재")

# ② 비용 실효
sim_c <- run_replication_simulation(copy(RAW), copy(BM), W_LS, commission = 0.0015)
nav_net <- as.numeric(last(sim_c$DAILY_NAV_DT$NAV))
nav_gross <- as.numeric(last(sim_c$DAILY_NAV_DT$NAV_gross))
if (nav_net < nav_gross) ok(sprintf("② 비용 실효 — net %.4f < gross %.4f", nav_net, nav_gross)) else
  ng("② 비용이 NAV 에 반영되지 않음")

# ③ t+1 실행
if (all(sim$PORTFOLIO_LOG$Exec_Date > sim$PORTFOLIO_LOG$Signal_Date)) ok("③ Exec > Signal (t+1 규약)") else
  ng("③ Exec_Date <= Signal_Date 존재 — PIT 위반")
exp_exec <- get_execution_date(sig_d[1], all_d)
got_exec <- sim$PORTFOLIO_LOG[Signal_Date == sig_d[1], Exec_Date]
if (identical(as.Date(got_exec), as.Date(exp_exec))) ok("③ Exec = 익월 첫 거래일 (하네스 규약 일치)") else
  ng(sprintf("③ Exec 불일치: %s vs 기대 %s", got_exec, exp_exec))

# ④ n=60 롱숏 완주
RAW60 <- mk_raw(30, 30)
BM60 <- unique(RAW60[, .(Date)])[, BM_Ret := 0.0001][]
W60 <- rbindlist(lapply(sig_d, function(d) data.table(
  Date = d,
  Ticker = c(sprintf("UP%03d", 1:30), sprintf("DN%03d", 1:30)),
  Weight = c(rep(1 / 30, 30), rep(-1 / 30, 30)))))
sim60 <- run_replication_simulation(copy(RAW60), copy(BM60), W60, commission = 0)
if (identical(sim60$diagnostics$n_max, 60L) || sim60$diagnostics$n_max == 60) ok("④ n=60 완주 + n_max=60 (상한 없음 실증)") else
  ng(sprintf("④ n_max=%s (60 기대)", sim60$diagnostics$n_max))

# ⑤ 계약 왕복 — audit holdings_cap 프로파일 양방향
suppressMessages({
  source("02_Infrastructure/contracts/backtest_result_contract.R")
  source("02_Infrastructure/contracts/audit_bt_result.R")
})
spec_rp <- list(strategy_name = "RP_TEST", constraint_profile = "replication",
                weight_method = "ew", rebalance = "monthly")
bt_rp <- build_bt_result(sim60, spec_rp, run_id = "TEST_RP", strategy_id = "RP_TEST",
                         transaction_cost_bps = 0, frequency = "daily",
                         created_by_agent = "test")
bt_rp <- audit_bt_result(bt_rp)
cap_rp <- bt_rp$audit[check_name == "holdings_cap"]
if (nrow(cap_rp) == 1L && cap_rp$status == "PASS" && grepl("replication", cap_rp$detail)) {
  ok("⑤ replication profile: n=60 인데 holdings_cap PASS(보고만)")
} else ng(sprintf("⑤ replication profile 판정 이상: %s", paste(cap_rp$status, collapse = ",")))

spec_no <- list(strategy_name = "NO_PROFILE", weight_method = "ew", rebalance = "monthly")
bt_no <- build_bt_result(sim60, spec_no, run_id = "TEST_NO", strategy_id = "NO_PROFILE",
                         transaction_cost_bps = 0, frequency = "daily",
                         created_by_agent = "test")
bt_no <- audit_bt_result(bt_no)
cap_no <- bt_no$audit[check_name == "holdings_cap"]
if (nrow(cap_no) == 1L && cap_no$status == "FAIL") {
  ok("⑤ 프로파일 부재: n=60 → holdings_cap FAIL (실투형 경로 무변경 — 양방향)")
} else ng(sprintf("⑤ 실투형 경로 판정 이상: %s", paste(cap_no$status, collapse = ",")))

# ⑥ L-code enum
source("02_Infrastructure/axiom/lcode_schema.R")
if (all(c("paper_replication", "reinforcement") %in% LCODE_VALID_MODES)) ok("⑥ LCODE_VALID_MODES 신규 2종") else
  ng("⑥ enum 에 paper_replication/reinforcement 부재")
emit_txt <- paste(readLines("02_Infrastructure/axiom/lcode_emit.R", warn = FALSE, encoding = "UTF-8"), collapse = "\n")
if (grepl('paper_replication = "RP"', emit_txt, fixed = TRUE) &&
    grepl('reinforcement = "RF"', emit_txt, fixed = TRUE)) ok("⑥ RP/RF prefix 배선") else
  ng("⑥ RP/RF prefix 부재")

# ⑦ L-code construction_type 파생 (2026-09-02 — emit 키워드 추론 폴백이 롱숏 5분위를
#    'single_factor_long_only' 로 적던 결함. 양방향: 롱숏/롱온리/명시/미상 + vocab + 배선)
#    러너 전체를 source 하면 config·텔레그램까지 끌려오므로 helper 정의 1개만 parse→eval 한다.
rp_src <- "02_Infrastructure/alpha_search/run_paper_replication.R"
rp_exprs <- parse(rp_src, encoding = "UTF-8", keep.source = FALSE)
.is_def <- function(e, nm) is.call(e) && identical(as.character(e[[1]]), "<-") &&
                           identical(as.character(e[[2]]), nm)
ct_def <- Filter(function(e) .is_def(e, ".rp_construction_type"), rp_exprs)
.nz <- function(x) if (is.null(x)) "NULL" else as.character(x)
if (length(ct_def) == 1L) {
  ct_env <- new.env(parent = globalenv())
  ct_env$`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a
  eval(ct_def[[1]], envir = ct_env)
  f <- ct_env$.rp_construction_type
  ls_spec <- list(construction = "quantile_long_short", weighting = "vw")
  tn_spec <- list(construction = "top_n_long", weighting = "ew")
  cases <- list(
    list("롱숏 관측(has_short=TRUE) → long_short",
         f(ls_spec, list(has_short = TRUE, n_max = 138L)), "long_short"),
    list("top_n_long 롱온리 관측 → single_sleeve_long_only_topN",
         f(tn_spec, list(has_short = FALSE, n_max = 25L)), "single_sleeve_long_only_topN"),
    list("engine_direct 롱온리 관측 → single_factor_long_only",
         f(list(construction = "engine_direct"), list(has_short = FALSE), engine_direct = TRUE), "single_factor_long_only"),
    list("선언 top_n_long 이어도 실행 분기 engine_direct + 숏 관측 → long_short",
         f(tn_spec, list(has_short = TRUE), engine_direct = TRUE), "long_short"),
    list("미관측(diagnostics 부재) + 선언 롱숏 → long_short (선언 폴백)",
         f(ls_spec, NULL), "long_short"),
    list("호출자 명시 construction_type 우선",
         f(c(tn_spec, construction_type = "overlay_regime"), list(has_short = FALSE)), "overlay_regime"))
  for (cs in cases) if (identical(cs[[2]], cs[[3]])) ok(paste("⑦", cs[[1]])) else
    ng(sprintf("⑦ %s: got %s", cs[[1]], .nz(cs[[2]])))
  # 미상(engine_direct + 미관측)은 NULL — 라벨을 지어내지 않는다
  if (is.null(f(list(construction = "engine_direct"), NULL, engine_direct = TRUE)))
    ok("⑦ 미상 = NULL (라벨 날조 없음 — emit 측 정직 결측)") else ng("⑦ 미상에 라벨을 지어냈다")
  labs <- unique(unlist(lapply(cases, `[[`, 2)))
  if (all(labs %in% LCODE_VALID_CONSTRUCTION_TYPES)) ok("⑦ 파생 라벨 전부 controlled vocab 안") else
    ng(sprintf("⑦ vocab 밖 라벨: %s", paste(setdiff(labs, LCODE_VALID_CONSTRUCTION_TYPES), collapse = ",")))
} else ng(sprintf("⑦ .rp_construction_type 정의 %d건 — 파생 helper 가 러너에 없거나 중복", length(ct_def)))
# 배선 — helper 가 있어도 emit 호출이 안 넘기면 키워드 추론이 다시 산다
rp_txt <- paste(readLines(rp_src, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
emit_blk <- regmatches(rp_txt, regexpr("emit_lcode\\(mode = \"paper_replication\"[^}]*", rp_txt))
if (length(emit_blk) == 1L && grepl("construction_type\\s*=", emit_blk) && grepl("mechanism_hypothesis\\s*=", emit_blk))
  ok("⑦ emit_lcode 호출에 construction_type·mechanism_hypothesis 명시 전달") else
  ng("⑦ emit_lcode 호출이 두 축을 안 넘긴다 — 키워드 추론 폴백 부활")

# ═════════════════════════════════════════════════════════════════════════════
# P0-04 · P0-03 보강 (2026-09-24)
# ═════════════════════════════════════════════════════════════════════════════
HARNESS <- "02_Infrastructure/replication/replication_harness.R"
.near <- function(a, b, tol = 1e-12) length(a) == 1L && length(b) == 1L && is.finite(a) && is.finite(b) && abs(a - b) <= tol
rg_at <- function(sim, d) { x <- sim$strategy_gross_xts; v <- as.numeric(x[index(x) == d]); if (length(v)) v else NA_real_ }
rn_at <- function(sim, d) { x <- sim$strategy_xts;       v <- as.numeric(x[index(x) == d]); if (length(v)) v else NA_real_ }
wdays <- function(from, to) { d <- seq(as.Date(from), as.Date(to), by = "day"); d[!format(d, "%u") %in% c("6", "7")] }
month_ends <- function(dd, n) as.Date(sapply(unique(format(dd, "%Y-%m"))[seq_len(n)],
                                            function(m) as.numeric(max(dd[format(dd, "%Y-%m") == m]))))
# Close/Open 을 Ret 에서 합성 (open_t1 용) — 기본은 겹밤 0(Open = Close_prev), 필요 시 개별 덮어쓰기
add_px <- function(R) {
  setorder(R, Ticker, Date)
  R[, Close := 100 * cumprod(1 + Ret), by = Ticker]
  R[, Open := Close / (1 + Ret)]
  R
}

# ── ⑧ 위반 주입: 집행일 +10% ────────────────────────────────────────────────
D8 <- wdays("2021-01-01", "2021-05-31")
S8 <- month_ends(D8, 4)                                  # 1~4월 말
E8 <- as.Date(sapply(S8, function(s) as.numeric(get_execution_date(s, D8))))
ex2 <- E8[2]; ex2p1 <- min(D8[D8 > ex2])
R8 <- CJ(Date = D8, Ticker = c("FLAT", "JUMP", "NXT"))[, Ret := 0]
R8[Ticker == "JUMP" & Date == ex2,   Ret := 0.10]        # d(2월 말) 종가 정보로 편입한 종목이 집행일에만 +10%
R8[Ticker == "NXT"  & Date == ex2p1, Ret := 0.10]        # 양성 대조: 집행 다음 날 +10%
R8 <- add_px(R8)
R8[Ticker == "JUMP" & Date == ex2, Open := Close]        # 갭 상승(겹밤) — 장중 0
BM8 <- unique(R8[, .(Date)])[, BM_Ret := 0][]
W8 <- rbind(data.table(Date = S8[1], Ticker = "FLAT", Weight = 1),
            data.table(Date = S8[2], Ticker = c("JUMP", "NXT"), Weight = c(0.5, 0.5)),
            data.table(Date = S8[3], Ticker = "FLAT", Weight = 1))
run8 <- function(ep, env = globalenv()) env$run_replication_simulation(copy(R8), copy(BM8), W8, commission = 0, exec_price = ep)
s8L <- run8("close_d_legacy"); s8T <- run8("close_t1"); s8O <- run8("open_t1")
tot <- function(s) prod(1 + as.numeric(s$strategy_gross_xts)) - 1
inj_ok <- function(sT) .near(rg_at(sT, ex2), 0) && .near(rg_at(sT, ex2p1), 0.05) && .near(tot(sT), 0.05)
if (.near(rg_at(s8L, ex2), 0.05) && .near(tot(s8L), 0.10, 1e-12))
  ok("⑧ legacy 재현: 새 보유가 집행일 +10% 를 얻는다(Rg[exec]=0.05 · 총 +10%) — 결함 D4-01 실증") else
  ng(sprintf("⑧ legacy 가 집행일 수익을 새 보유에 안 붙인다 — Rg[exec]=%s 총=%s", rg_at(s8L, ex2), tot(s8L)))
if (inj_ok(s8T)) ok("⑧ close_t1: 집행일 수익 = 직전 보유(FLAT 0) · 새 보유는 다음 날부터(+5%) · 총 +5% — 주입 수익 미획득") else
  ng(sprintf("⑧ close_t1 귀속 이상 — Rg[exec]=%s Rg[exec+1]=%s 총=%s", rg_at(s8T, ex2), rg_at(s8T, ex2p1), tot(s8T)))
if (.near(rg_at(s8O, ex2), 0) && .near(tot(s8O), 0.05))
  ok("⑧ open_t1: 겹밤 갭 +10% 는 직전 보유 몫(FLAT 0) · 새 보유 장중 0 · 총 +5%") else
  ng(sprintf("⑧ open_t1 귀속 이상 — Rg[exec]=%s 총=%s", rg_at(s8O, ex2), tot(s8O)))
# 돌연변이: close_t1 창을 legacy 창(>=)으로 되돌린 사본 → 주입 판정이 red 여야 판별력이 있다
h_txt <- readLines(HARNESS, warn = FALSE, encoding = "UTF-8")
mut8 <- sub("hold_pool <- hold_pool[hold_pool > exec_date]", "hold_pool <- hold_pool[hold_pool >= exec_date]", h_txt, fixed = TRUE)
if (!identical(mut8, h_txt)) {
  tf <- tempfile(fileext = ".R"); writeLines(mut8, tf, useBytes = TRUE)
  menv <- new.env(parent = globalenv()); suppressMessages(capture.output(sys.source(tf, envir = menv))); unlink(tf)
  sm <- tryCatch(run8("close_t1", menv), error = function(e) NULL)
  if (!is.null(sm) && !inj_ok(sm)) ok("⑧ 돌연변이(close_t1 창 >=) 사본은 주입 판정에서 red — 판별력 확인") else
    ng("⑧ 돌연변이 사본이 주입 판정을 통과 — 검사 판별력 없음")
} else ng("⑧ 돌연변이 대상 줄(close_t1 창)을 못 찾음 — 하네스 구조가 바뀌었나")

# ── ⑨ 집행일 수익 = 직전 보유의 드리프트 비중 ─────────────────────────────────
R9 <- CJ(Date = D8, Ticker = c("A", "B", "C"))[, Ret := 0]
mid <- D8[D8 > E8[1] & D8 < ex2][5]
R9[Ticker == "A" & Date == mid, Ret := 1.00]             # 창 중간 A 2배 → 드리프트 비중 A 2/3 · B 1/3
R9[Ticker == "A" & Date == ex2, Ret := 0.10]             # 집행일 A +10%
BM9 <- unique(R9[, .(Date)])[, BM_Ret := 0][]
W9 <- rbind(data.table(Date = S8[1], Ticker = c("A", "B"), Weight = c(0.5, 0.5)),
            data.table(Date = S8[2], Ticker = "C", Weight = 1))
s9T <- run_replication_simulation(copy(R9), copy(BM9), W9, commission = 0, exec_price = "close_t1")
s9L <- run_replication_simulation(copy(R9), copy(BM9), W9, commission = 0, exec_price = "close_d_legacy")
if (.near(rg_at(s9T, ex2), 0.2 / 3)) ok(sprintf("⑨ close_t1 집행일 수익 %.6f = 드리프트 비중 2/3×10%% (목표 비중이면 0.05)", rg_at(s9T, ex2))) else
  ng(sprintf("⑨ 집행일 수익 %.6f ≠ 드리프트 2/3×10%%", rg_at(s9T, ex2)))
if (.near(rg_at(s9L, ex2), 0)) ok("⑨ legacy 는 집행일을 새 보유(C 0)에 붙인다 — 규약 차이가 실현값에 나타난다") else
  ng(sprintf("⑨ legacy 집행일 수익 %s (0 기대)", rg_at(s9L, ex2)))

# ── ⑩ 비용 기장일 ─────────────────────────────────────────────────────────────
cm <- 0.0015
s10T <- run_replication_simulation(copy(R8), copy(BM8), W8, commission = cm, exec_price = "close_t1")
s10L <- run_replication_simulation(copy(R8), copy(BM8), W8, commission = cm, exec_price = "close_d_legacy")
pl <- s10T$PORTFOLIO_LOG
nxt_day <- function(d) min(D8[D8 > d])
book_ok <- all(pl$Cost_Date == as.Date(sapply(pl$Exec_Date, function(d) as.numeric(nxt_day(d)))))
mult_ok <- all(vapply(seq_len(nrow(pl)), function(i) {
  d <- pl$Cost_Date[i]; k <- pl$Turnover[i] * cm
  .near(rn_at(s10T, d), (1 - k) * (1 + rg_at(s10T, d)) - 1, 1e-14) }, logical(1)))
exec_free <- all(vapply(pl$Exec_Date[-1], function(d) identical(rn_at(s10T, d), rg_at(s10T, d)), logical(1)))
nav_ratio <- as.numeric(last(s10T$DAILY_NAV_DT$NAV)) / as.numeric(last(s10T$DAILY_NAV_DT$NAV_gross))
if (book_ok && mult_ok && exec_free && .near(nav_ratio, prod(1 - pl$Turnover * cm), 1e-12) && .near(pl$Turnover[1], 1))
  ok(sprintf("⑩ close_t1 비용: 첫 보유일(exec+1) 곱 기장 · exec 행 무비용 · NAV 비 %.8f = Π(1−Σ|Δw|c) · 초기 Σ|w|=1", nav_ratio)) else
  ng(sprintf("⑩ close_t1 비용 기장 이상 — 기장일 %s 곱 %s exec무비용 %s NAV비 %.10f vs %.10f",
             book_ok, mult_ok, exec_free, nav_ratio, prod(1 - pl$Turnover * cm)))
plL <- s10L$PORTFOLIO_LOG
if (all(plL$Cost_Date == plL$Exec_Date) &&
    all(vapply(seq_len(nrow(plL)), function(i) .near(rn_at(s10L, plL$Exec_Date[i]),
          rg_at(s10L, plL$Exec_Date[i]) - plL$Turnover[i] * cm, 1e-15), logical(1))))
  ok("⑩ legacy 비용: exec 행 가산 차감(Rn = Rg − Σ|Δw|c) — 초판 그대로") else ng("⑩ legacy 비용 기장 이상")
if (identical(s10T$cost_model_version, "replication_weight_delta_v1/first_hold_day_multiplicative") &&
    identical(s10L$cost_model_version, "replication_weight_delta_v1/exec_day_additive") &&
    identical(s10T$diagnostics$exec_price, "close_t1"))
  ok("⑩ cost_model_version·diagnostics$exec_price 가 규약별 실현값") else ng("⑩ 규약 라벨 이상")

# ── ⑪ P0-03 첫 행 ret_gross ──────────────────────────────────────────────────
R11 <- CJ(Date = D8, Ticker = c("P", "Q"))[, Ret := 0]
R11[Date == E8[1], Ret := 0.05]                           # legacy 첫 행(=exec1) +5%
R11[Date == nxt_day(E8[1]), Ret := 0.05]                  # close_t1 첫 행(=exec1+1) +5%
set.seed(20260924)
BM11 <- unique(R11[, .(Date)])[, BM_Ret := rnorm(.N, 0, 0.01)][]   # 벤치 비퇴화(Check 17 — 상수 벤치는 critical FAIL)
W11 <- rbindlist(lapply(S8[1:3], function(d) data.table(Date = d, Ticker = c("P", "Q"), Weight = c(0.5, 0.5))))
spec11 <- list(strategy_name = "P003", constraint_profile = "replication", weight_method = "ew", rebalance = "monthly")
pr_of <- function(sim, env = globalenv()) env$build_period_returns(sim, "T", "T", "daily", 0)
s11L <- run_replication_simulation(copy(R11), copy(BM11), W11, commission = cm, exec_price = "close_d_legacy")
s11T <- run_replication_simulation(copy(R11), copy(BM11), W11, commission = cm, exec_price = "close_t1")
p11L <- pr_of(s11L); p11T <- pr_of(s11T)
first_ok <- function(p, g, c) .near(p$ret_gross[1], g, 1e-15) && .near(p$cost_ret[1], c, 1e-15)
if (first_ok(p11L, 0.05, cm)) ok(sprintf("⑪ legacy 첫 행 ret_gross %.4f · cost_ret %.4f = Σ|w|×15bps (구판은 0 · −ret_net)", p11L$ret_gross[1], p11L$cost_ret[1])) else
  ng(sprintf("⑪ legacy 첫 행 ret_gross=%s cost_ret=%s", p11L$ret_gross[1], p11L$cost_ret[1]))
if (first_ok(p11T, 0.05, 1.05 * cm)) ok(sprintf("⑪ close_t1 첫 행(exec+1) ret_gross %.4f · cost_ret %.6f = (1+Rg)·Σ|w|c", p11T$ret_gross[1], p11T$cost_ret[1])) else
  ng(sprintf("⑪ close_t1 첫 행 ret_gross=%s cost_ret=%s", p11T$ret_gross[1], p11T$cost_ret[1]))
# 폴백(생산자가 Rg 를 안 줄 때): 첫 행은 되짚을 수 없다 → ret_net(비용 미상 0) — 0 으로 짓지 않는다
s11F <- s11L; s11F$strategy_gross_xts <- NULL
p11F <- pr_of(s11F)
if (.near(p11F$ret_gross[1], p11F$ret_net[1], 0) && .near(p11F$cost_ret[1], 0, 0))
  ok("⑪ 폴백 경로(NAV_gross 되짚기) 첫 행 = ret_net · cost 0(미상) — 지은 0/음의 비용 없음") else
  ng(sprintf("⑪ 폴백 첫 행 ret_gross=%s ret_net=%s", p11F$ret_gross[1], p11F$ret_net[1]))
# 돌연변이: 구판(Rg 무시 + NA→0 채움) 사본은 첫 행 판정에서 red
c_txt <- readLines("02_Infrastructure/contracts/backtest_result_contract.R", warn = FALSE, encoding = "UTF-8")
mut11 <- sub("g_xts <- sim_result$strategy_gross_xts", "g_xts <- NULL", c_txt, fixed = TRUE)
mut11 <- sub("    ret_g <- diff(log(nav_g_xts))", "    ret_g <- diff(log(nav_g_xts)); ret_g[is.na(ret_g)] <- 0", mut11, fixed = TRUE)
if (sum(mut11 != c_txt) == 2L) {
  tf <- tempfile(fileext = ".R"); writeLines(mut11, tf, useBytes = TRUE)
  cenv <- new.env(parent = globalenv()); suppressMessages(capture.output(sys.source(tf, envir = cenv))); unlink(tf)
  pm <- pr_of(s11L, cenv)
  if (!first_ok(pm, 0.05, cm) && .near(pm$ret_gross[1], 0, 0))
    ok(sprintf("⑪ 구판 돌연변이 사본: 첫 행 ret_gross 0 · cost_ret %.4f(=−ret_net) → red — 판별력 확인", pm$cost_ret[1])) else
    ng("⑪ 구판 돌연변이 사본이 첫 행 판정을 통과 — 판별력 없음")
} else ng("⑪ 돌연변이 대상 줄 2개를 못 찾음 — 계약 구조가 바뀌었나")

# ── (⑫·⑮ 공용) 러너의 strategy_spec 조립 함수를 parse→eval 로 꺼낸다 (러너 전체 source 없이) ──
sp_env <- new.env(parent = globalenv())
sp_env$`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a
for (nm in c(".rp_abs_path", ".rp_strategy_spec")) {
  hit <- Filter(function(e) .is_def(e, nm), rp_exprs)
  if (length(hit) == 1L) eval(hit[[1]], envir = sp_env) else ng(sprintf("⑮ %s 정의 %d건", nm, length(hit)))
}
eng <- file.path(tempdir(), "p004_engine.R")
writeLines(c("# 합성 엔진 (검사용) — 상수 패널",
             "FACTORS <- data.table::data.table(Date = as.Date('2021-01-29'), Ticker = 'FLAT', Score = 1)"), eng)
pspec <- list(construction = "top_n_long", weighting = "ew", rebalance = "monthly")
full_spec <- function(sim, universe = "K200_KQ150")
  sp_env$.rp_strategy_spec("P004", "idea", pspec, universe, sim, "https://example.org/paper", eng)
mk_bt <- function(sim, spec, id, universe_id = "K200_KQ150")
  build_bt_result(sim, spec, run_id = id, strategy_id = id, transaction_cost_bps = 15, slippage_bps = 0,
                  frequency = "daily", universe_id = universe_id, created_by_agent = "test")

# ── ⑫ P0-03 audit cost_sign ─────────────────────────────────────────────────
#   청정 산출은 integrity PASS 여야 주입 뒤 WARNING 이 cost_sign 때문임을 가를 수 있다(다른 WARN 이 섞이면 판별 불가).
bt12 <- suppressMessages(audit_bt_result(mk_bt(s11T, full_spec(s11T), "T12")))
c12 <- bt12$audit[check_name == "cost_sign_nonnegative"]
if (nrow(c12) == 1L && c12$status == "PASS" && identical(bt12$manifest$integrity_status, "PASS"))
  ok("⑫ 청정 산출: cost_sign_nonnegative PASS · integrity PASS") else
  ng(sprintf("⑫ 청정 산출 cost_sign %s · integrity %s — 비PASS: %s", paste(c12$status, collapse = ","),
             bt12$manifest$integrity_status, paste(bt12$audit[status != "PASS", check_name], collapse = ",")))
bt12b <- mk_bt(s11T, full_spec(s11T), "T12b")
bt12b$period_returns[2, `:=`(cost_ret = -0.01, ret_gross = ret_net - 0.01)]   # 음의 비용 주입 (Check 12 정합 유지)
bt12b <- suppressMessages(audit_bt_result(bt12b))
c12b <- bt12b$audit[check_name == "cost_sign_nonnegative"]
c12d <- bt12b$audit[check_name == "cost_decomposition_consistency"]
if (nrow(c12b) == 1L && c12b$status == "FAIL" && c12b$severity == "high" &&
    c12d$status == "PASS" && bt12b$manifest$integrity_status == "WARNING")
  ok("⑫ 음의 비용 주입: cost_sign FAIL(high) · Check 12(동어반복)는 PASS · integrity WARNING(official 유지)") else
  ng(sprintf("⑫ 주입 판정 이상 — sign %s/%s decomposition %s integrity %s",
             paste(c12b$status, collapse = ","), paste(c12b$severity, collapse = ","),
             paste(c12d$status, collapse = ","), bt12b$manifest$integrity_status))

# ── ⑬ 설정 기본값 소비 · fail-closed ─────────────────────────────────────────
.ov <- Sys.getenv("QVEST_CONSTRAINT_DEFAULTS", NA)
Sys.unsetenv("QVEST_CONSTRAINT_DEFAULTS")
live_ep <- tryCatch(rep_exec_price_default(), error = function(e) paste("ERR", conditionMessage(e)))
s13d <- run_replication_simulation(copy(R8), copy(BM8), W8, commission = cm)          # exec_price 미지정
if (identical(live_ep, "close_t1") && identical(s13d$diagnostics$exec_price, "close_t1"))
  ok("⑬ 운영 설정 execution.exec_price = close_t1 · 미지정 호출이 그 값으로 측정") else
  ng(sprintf("⑬ 운영 기본값 %s / 실현 %s", live_ep, s13d$diagnostics$exec_price))
cfg0 <- jsonlite::fromJSON("02_Infrastructure/worktask/constraint_defaults.json", simplifyVector = FALSE)
wcfg <- function(mod) { x <- cfg0; x <- mod(x); f <- tempfile(fileext = ".json")
  writeLines(jsonlite::toJSON(x, auto_unbox = TRUE, pretty = TRUE, null = "null"), f, useBytes = TRUE); f }
f_leg <- wcfg(function(x) { x$execution$exec_price <- "close_d_legacy"; x })
f_none <- wcfg(function(x) { x$execution <- NULL; x })
f_bad <- wcfg(function(x) { x$execution$exec_price <- "close_t2"; x })
Sys.setenv(QVEST_CONSTRAINT_DEFAULTS = f_leg)
s13l <- run_replication_simulation(copy(R8), copy(BM8), W8, commission = cm)
if (identical(s13l$diagnostics$exec_price, "close_d_legacy") &&
    identical(s13l$strategy_xts, s10L$strategy_xts) && identical(s13l$DAILY_NAV_DT, s10L$DAILY_NAV_DT))
  ok("⑬ 설정 사본을 legacy 로 바꾸면 미지정 호출의 **산출**이 명시 legacy 와 비트 동일(라벨만이 아니다)") else
  ng("⑬ 설정 기본값이 산출에 전달되지 않는다")
err_of <- function(expr) tryCatch({ force(expr); "NO_ERROR" }, error = function(e) "ERROR")
Sys.setenv(QVEST_CONSTRAINT_DEFAULTS = f_none)
e1 <- err_of(run_replication_simulation(copy(R8), copy(BM8), W8, commission = cm))
Sys.setenv(QVEST_CONSTRAINT_DEFAULTS = f_bad)
e2 <- err_of(run_replication_simulation(copy(R8), copy(BM8), W8, commission = cm))
Sys.setenv(QVEST_CONSTRAINT_DEFAULTS = file.path(tempdir(), "no_such_cfg.json"))
e3 <- err_of(run_replication_simulation(copy(R8), copy(BM8), W8, commission = cm))
Sys.unsetenv("QVEST_CONSTRAINT_DEFAULTS")
e4 <- err_of(run_replication_simulation(copy(R8), copy(BM8), W8, commission = cm, exec_price = "close_t2"))
if (all(c(e1, e2, e3, e4) == "ERROR"))
  ok("⑬ fail-closed: execution 블록 부재 · 허용 밖 값 · 명시 경로 부재(폴백 안 함) · 허용 밖 인자 — 전부 멈춤") else
  ng(sprintf("⑬ fail-closed 위반 — 블록부재 %s 값 %s 경로 %s 인자 %s", e1, e2, e3, e4))

# ── ⑭ open_t1 가드 ───────────────────────────────────────────────────────────
R14 <- copy(R8)[, Ret := 0]; R14 <- add_px(R14)
R14[Ticker == "JUMP" & Date == ex2, Open := Close * 2]    # 미수정 Open 이음매: 겹밤 +100% · 장중 −50%
s14 <- run_replication_simulation(copy(R14), copy(BM8), W8, commission = 0, exec_price = "open_t1")
g14 <- s14$diagnostics$open_guard
if (!is.null(g14) && g14$n_flagged >= 1L && .near(rg_at(s14, ex2), 0))
  ok(sprintf("⑭ 미수정 Open 주입: 가드 플래그 %d/%d · 그 종목·날은 close_t1 처리(새 보유 장중 −50%% 미반영)",
             g14$n_flagged, g14$n_checked)) else
  ng(sprintf("⑭ 가드 미발화 — flagged %s Rg[exec]=%s", g14$n_flagged, rg_at(s14, ex2)))
f_loose <- wcfg(function(x) { x$execution$open_t1_overnight_limit <- list(list(from = "1900-01-01", limit = 10)); x })
Sys.setenv(QVEST_CONSTRAINT_DEFAULTS = f_loose)
s14m <- run_replication_simulation(copy(R14), copy(BM8), W8, commission = 0, exec_price = "open_t1")
Sys.unsetenv("QVEST_CONSTRAINT_DEFAULTS")
if (s14m$diagnostics$open_guard$n_flagged == 0L && .near(rg_at(s14m, ex2), -0.25))
  ok("⑭ 한도 완화 설정 사본: 플래그 0 · 새 보유가 이음매 −50%×0.5 를 먹는다 → 가드가 설정 한도를 쓴다(판별력)") else
  ng(sprintf("⑭ 한도 완화 사본 판정 이상 — flagged %s Rg[exec]=%s", s14m$diagnostics$open_guard$n_flagged, rg_at(s14m, ex2)))
if (!is.na(.ov)) Sys.setenv(QVEST_CONSTRAINT_DEFAULTS = .ov)

# ── ⑮ strategy_spec 진술 · integrity ────────────────────────────────────────
if (exists(".rp_strategy_spec", envir = sp_env)) {
  spT <- full_spec(s11T)
  s11Lc <- run_replication_simulation(copy(R11), copy(BM11), W11, commission = cm, exec_price = "close_d_legacy")
  spL <- full_spec(s11Lc)
  if (grepl("집행 close_t1", spT$lookahead_prevention, fixed = TRUE) && !grepl("close_d_legacy", spT$lookahead_prevention) &&
      grepl("집행 close_d_legacy", spL$lookahead_prevention, fixed = TRUE) &&
      identical(spT$exec_price, "close_t1") && identical(spT$cost_model_version, s11T$cost_model_version) &&
      identical(spT$factor_engine_path, eng) && is.character(spT$survivorship_bias_control) && !is.na(spT$survivorship_bias_control))
    ok("⑮ 진술(lookahead_prevention)·exec_price·cost_model_version·엔진 경로가 sim 실현값에서 생성") else
    ng("⑮ strategy_spec 진술이 실현값과 어긋난다")
  bt15 <- suppressMessages(audit_bt_result(mk_bt(s11T, spT, "T15")))
  st <- function(b, n) b$audit[check_name == n, status]
  want <- c("lookahead_bias_checked", "survivorship_bias_checked", "c15_factor_db_load_path",
            "lookahead_detector_self_scan", "t_plus_1_cadence_consistency", "cost_sign_nonnegative")
  got <- vapply(want, function(n) paste(st(bt15, n), collapse = ","), character(1))
  if (all(got == "PASS") && identical(bt15$manifest$integrity_status, "PASS") &&
      identical(bt15$manifest$cost_model_version, s11T$cost_model_version))
    ok("⑮ integrity PASS — Check 8·9·14·15 WARN 상수 해소 · Check 13 비발화 · manifest cost_model_version 실현값") else
    ng(sprintf("⑮ integrity %s — %s · cmv %s", bt15$manifest$integrity_status,
               paste(names(got), got, sep = "=", collapse = " "), bt15$manifest$cost_model_version))
  # 음성 대조: 구판 spec(엔진 경로·생존 통제·C 참조 없음)은 WARN 상수 4종이 그대로 — 해소가 필드 전파 덕임을 가른다
  sp_old <- spT[setdiff(names(spT), c("factor_engine_path", "survivorship_bias_control", "exec_price", "cost_model_version"))]
  sp_old$lookahead_prevention <- "detect_lookahead(engine) CLEAN + t+1 실행(get_execution_date 익월 첫 거래일) + 시그널일>RAWDATA 범위 검사"
  bt15o <- suppressMessages(audit_bt_result(mk_bt(s11T, sp_old, "T15o")))
  wo <- sort(bt15o$audit[status == "WARN", check_name])
  if (identical(bt15o$manifest$integrity_status, "WARNING") &&
      identical(wo, sort(c("lookahead_bias_checked", "survivorship_bias_checked", "c15_factor_db_load_path", "lookahead_detector_self_scan"))))
    ok("⑮ 음성 대조: 구판 spec 은 골든 10_audit 와 같은 WARN 4종(Check 8·9·14·15) · integrity WARNING") else
    ng(sprintf("⑮ 구판 spec WARN = %s (%s)", paste(wo, collapse = ","), bt15o$manifest$integrity_status))
  # 음성 대조: 러너가 멤버십을 적용하지 않는 유니버스는 생존 통제를 진술하지 않는다 → Check 9 WARN(정직)
  spX <- full_spec(s11T, "KR_TOP342")
  bt15x <- suppressMessages(audit_bt_result(mk_bt(s11T, spX, "T15x", "KR_TOP342")))
  if (is.na(spX$survivorship_bias_control) && st(bt15x, "survivorship_bias_checked") == "WARN")
    ok("⑮ 멤버십 미적용 유니버스 → 생존 통제 진술 없음(NA) · Check 9 WARN — 진술로 채우지 않는다") else
    ng("⑮ 멤버십 미적용 유니버스에 생존 통제를 진술했다")
  # 음성 대조: 하네스가 exec_price 를 싣지 않은 sim(구판 모양)이면 진술을 지어내지 않고 멈춘다
  s_old <- s11T; s_old$diagnostics$exec_price <- NULL
  if (err_of(full_spec(s_old)) == "ERROR")
    ok("⑮ exec_price 없는 sim → 멈춤(진술 날조 없음)") else ng("⑮ exec_price 없는 sim 에 진술을 지어냈다")
}

# ── ⑯ 러너 배선 (정적 — 두 sim 호출이 exec_price 를 넘기는가) ────────────────────
.find_calls <- function(e, fname) {
  out <- list()
  walk <- function(x) {
    if (is.call(x)) {
      if (identical(as.character(x[[1]])[1], fname)) out[[length(out) + 1L]] <<- x
      for (a in as.list(x)[-1]) if (!missing(a)) walk(a)
    }
  }
  walk(e); out
}
.wiring_ok <- function(exprs) {
  fx <- Filter(function(e) .is_def(e, "run_paper_replication"), exprs)
  if (length(fx) != 1L) return(FALSE)
  cs <- .find_calls(fx[[1]][[3]], "run_replication_simulation")
  args <- lapply(cs, function(cl) as.list(cl)$exec_price)
  length(cs) == 2L && all(vapply(args, is.name, logical(1))) &&
    setequal(vapply(args, as.character, character(1)), c("exec_price_paper", "exec_price")) &&
    length(.find_calls(fx[[1]][[3]], ".rp_strategy_spec")) == 1L &&
    length(.find_calls(fx[[1]][[3]], "rep_resolve_exec_price")) == 2L
}
if (.wiring_ok(rp_exprs)) ok("⑯ 러너: sim_paper·sim_grade 가 exec_price 심볼 전달 · 규약 해석 2회 · .rp_strategy_spec 경유") else
  ng("⑯ 러너 배선 이상 — sim 호출이 exec_price 를 안 넘기거나 spec 을 직접 조립")
rp_lines <- readLines(rp_src, warn = FALSE, encoding = "UTF-8")
mut16 <- sub("commission = 0.0015, start_date = start_date,", "commission = 0.0015, start_date = start_date)", rp_lines, fixed = TRUE)
mut16 <- mut16[!grepl("^\\s*exec_price = exec_price\\)\\s*$", mut16)]
if (!identical(mut16, rp_lines)) {
  tf <- tempfile(fileext = ".R"); writeLines(mut16, tf, useBytes = TRUE)
  mex <- tryCatch(parse(tf, encoding = "UTF-8", keep.source = FALSE), error = function(e) NULL); unlink(tf)
  if (!is.null(mex) && !.wiring_ok(mex)) ok("⑯ 돌연변이(sim_grade 의 exec_price 인자 삭제) 사본은 red — 판별력 확인") else
    ng("⑯ 돌연변이 사본이 배선 판정을 통과(또는 parse 실패)")
} else ng("⑯ 돌연변이 대상 줄을 못 찾음")

cat(sprintf("결과: PASS=%d FAIL=%d\n", pass, fail))
## ★러너 요약 계약 (v10 2026-09-03) — 없으면 run_all_hooks.sh 가 UNMEASURED 로 계상해 이 스위트의 단언이 총계에 0 으로 들어간다.
cat(sprintf('{"test":"replication_harness","pass":%d,"fail":%d,"total":%d,"skipped":0}\n', pass, fail, pass + fail))
if (fail > 0L) quit(status = 1L)
