# test_replication_ls_combination.R — 충실구현 하네스 다리 결합 선택지(ls_combination) 계약 (2026-11-09)
#
# 결정: decision_register REPLICATION-LS-PAPER-BHR-20261109(도훈 '논문식으로 진행').
#   daily(기본 · 구판) = 매일 Rg = GL·L − GS·S / bhr(논문식) = 보유창 안 달러 매수 후 보유 장부 N = 1 + GL(ΠL−1) − GS(ΠS−1).
# 계약:
#   ① 알려진 사례(1롱 · 1숏 · 비용 0): bhr 창 끝 누적 = BHR_L − BHR_S(0.21) · daily 누적 = Π(1+L−S)−1(−0.84) — 둘이 다르다
#   ② 롱만 · GL = 1: bhr 경로 = daily 경로(항등)
#   ③ 다리 여러 종목: bhr 창 끝 = 롱 종목 BHR 평균 − 숏 종목 BHR 평균(동일가중 편입)
#   ④ 창 두 개: 창마다 장부를 1 로 새로 열고 NAV 가 창 끝 값을 곱으로 잇는다
#   ⑤ 자본 소진(숏 +300%): N ≤ 0 → n_ruin_windows = 1 · 그 뒤 수익 0 · NAV 0
#   ⑥ 허용 밖 값 = 멈춤 · 미지정 = daily(명시 daily 와 같은 산출)
#   ⑦ 돌연변이: bhr 가지를 끈 하네스 사본 → ① 의 bhr 기대가 깨진다(검사 생존 확인 · 치환 성사 단정)
#   ⑧ 러너 배선: run_paper_replication 의 두 시뮬레이션 호출이 ls_combination = ls_comb 를 넘긴다(정적) · 한쪽 삭제 사본 red
# 실행: Rscript 08_Tests/contracts/test_replication_ls_combination.R

.self <- tryCatch({
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", a[grepl("^--file=", a)])
  if (length(f)) dirname(f[1]) else "."
}, error = function(e) ".")
root <- normalizePath(file.path(.self, "..", ".."), winslash = "/", mustWork = FALSE)
if (!file.exists(file.path(root, "02_Infrastructure", "config.R")))
  root <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(root)
suppressPackageStartupMessages({ library(data.table); library(xts); library(PerformanceAnalytics) })

pass <- 0L; fail <- 0L
ok <- function(m) { cat(sprintf("  [PASS] %s\n", m)); pass <<- pass + 1L }
ng <- function(m) { cat(sprintf("  [FAIL] %s\n", m)); fail <<- fail + 1L }
chk <- function(cond, m) if (isTRUE(cond)) ok(m) else ng(m)

# 실제 t+1 규약과 같은 집행일(시그널 익월 첫 거래일 — test_replication_harness.R 와 동일)
get_execution_date <- function(signal_date, all_dates) {
  ym <- format(signal_date, "%Y-%m")
  yr <- as.integer(substr(ym, 1, 4)); mo <- as.integer(substr(ym, 6, 7))
  if (mo == 12) { yr <- yr + 1; mo <- 1 } else { mo <- mo + 1 }
  cands <- all_dates[all_dates >= as.Date(sprintf("%04d-%02d-01", yr, mo))]
  if (length(cands) > 0) min(cands) else NA
}
HARNESS <- file.path(root, "02_Infrastructure/replication/replication_harness.R")
H <- new.env(parent = globalenv()); sys.source(HARNESS, envir = H)

# ── 합성 데이터: 2020-01-27 ~ 2020-03-06 평일. 수익은 사례마다 덮어쓴다 ──
dates <- seq(as.Date("2020-01-27"), as.Date("2020-03-06"), by = "day")
dates <- dates[!format(dates, "%u") %in% c("6", "7")]
mk <- function(tickers) { g <- CJ(Date = dates, Ticker = tickers); g[, Ret := 0][] }
setret <- function(g, tk, d, r) g[Ticker == tk & Date == as.Date(d), Ret := r][]
close_px <- function(g) { g[, Close := 100 * cumprod(1 + Ret), by = Ticker][] }
BM <- data.table(Date = dates, BM_Ret = 0)
sig1 <- as.Date("2020-01-31")                      # 집행 2020-02-03 → 보유창 (02-03, 끝] (close_t1)
nav_end <- function(sim) tail(sim$DAILY_NAV_DT$NAV_gross, 1)
run <- function(env, raw, W, comb = NULL) {
  args <- list(raw, BM, W, commission = 0, start_date = "2020-01-01", exec_price = "close_t1")
  if (!is.null(comb)) args$ls_combination <- comb
  do.call(env$run_replication_simulation, args)
}

cat("① 알려진 사례 — 1롱 1숏\n")
R1 <- mk(c("L1", "S1"))
R1 <- setret(R1, "L1", "2020-02-04", 0.10); R1 <- setret(R1, "L1", "2020-02-05", 0.10)
R1 <- setret(R1, "S1", "2020-02-04", -0.50); R1 <- setret(R1, "S1", "2020-02-05", 1.00)
R1 <- close_px(R1)
W1 <- data.table(Date = sig1, Ticker = c("L1", "S1"), Weight = c(1, -1))
sd <- run(H, copy(R1), W1, "daily"); sb <- run(H, copy(R1), W1, "bhr")
chk(abs(nav_end(sb) - 1.21) < 1e-12, sprintf("bhr NAV 끝 = 1 + BHR_L − BHR_S = 1.21 (실측 %.6f)", nav_end(sb)))
chk(abs(nav_end(sd) - 0.16) < 1e-12, sprintf("daily NAV 끝 = Π(1+L−S) = 1.6 × 0.1 = 0.16 (실측 %.6f)", nav_end(sd)))
chk(identical(sb$diagnostics$ls_combination, "bhr") && identical(sd$diagnostics$ls_combination, "daily"), "diagnostics$ls_combination 실현값 기록")
chk(identical(sb$diagnostics$n_ruin_windows, 0L), "자본 소진 없음 = n_ruin_windows 0")

cat("② 롱만 · GL = 1 → bhr = daily\n")
W2 <- data.table(Date = sig1, Ticker = "L1", Weight = 1)
s2d <- run(H, copy(R1), W2, "daily"); s2b <- run(H, copy(R1), W2, "bhr")
chk(isTRUE(all.equal(s2d$DAILY_NAV_DT$NAV_gross, s2b$DAILY_NAV_DT$NAV_gross, tolerance = 1e-12)), "롱만 경로 항등")

cat("③ 다리 여러 종목 — 동일가중 편입 · 다리 안 매수 후 보유\n")
R3 <- mk(c("LA", "LB", "SA", "SB"))
for (x in list(c("LA", "2020-02-04", 0.20), c("LA", "2020-02-05", -0.10), c("LB", "2020-02-04", -0.05), c("LB", "2020-02-06", 0.30),
               c("SA", "2020-02-04", 0.40), c("SA", "2020-02-07", -0.60), c("SB", "2020-02-05", -0.20), c("SB", "2020-02-06", 0.10)))
  R3 <- setret(R3, x[1], x[2], as.numeric(x[3]))
R3 <- close_px(R3)
W3 <- data.table(Date = sig1, Ticker = c("LA", "LB", "SA", "SB"), Weight = c(0.5, 0.5, -0.5, -0.5))
s3 <- run(H, copy(R3), W3, "bhr")
bh <- function(tk) R3[Ticker == tk & Date > as.Date("2020-02-03"), prod(1 + Ret) - 1]
exp3 <- 1 + mean(c(bh("LA"), bh("LB"))) - mean(c(bh("SA"), bh("SB")))
chk(abs(nav_end(s3) - exp3) < 1e-12, sprintf("NAV 끝 = 1 + 평균 BHR_L − 평균 BHR_S = %.6f (실측 %.6f)", exp3, nav_end(s3)))

cat("④ 창 두 개 — 창마다 장부를 새로 연다\n")
R4 <- copy(R1)[, Ret := 0][]
R4 <- setret(R4, "L1", "2020-02-04", 0.10); R4 <- setret(R4, "S1", "2020-02-05", -0.50)     # 창 1: N 끝 = 1 + 0.1 + 0.5 = 1.6
R4 <- setret(R4, "L1", "2020-03-03", -0.20); R4 <- setret(R4, "S1", "2020-03-04", 0.25)     # 창 2: N 끝 = 1 − 0.2 − 0.25 = 0.55
R4 <- close_px(R4)
sig2 <- as.Date("2020-02-28")                      # 집행 2020-03-02 → 창 2 = (03-02, 끝]
W4 <- rbind(data.table(Date = sig1, Ticker = c("L1", "S1"), Weight = c(1, -1)), data.table(Date = sig2, Ticker = c("L1", "S1"), Weight = c(1, -1)))
s4 <- run(H, copy(R4), W4, "bhr")
chk(abs(nav_end(s4) - 1.6 * 0.55) < 1e-12, sprintf("NAV 끝 = 1.6 × 0.55 = 0.88 (실측 %.6f)", nav_end(s4)))

cat("⑤ 자본 소진 — 숏 +300%\n")
R5 <- copy(R1)[, Ret := 0][]
R5 <- setret(R5, "S1", "2020-02-05", 3.00); R5 <- setret(R5, "L1", "2020-02-06", 0.50)
R5 <- close_px(R5)
s5 <- run(H, copy(R5), W1, "bhr")
chk(identical(s5$diagnostics$n_ruin_windows, 1L), "n_ruin_windows = 1")
chk(abs(nav_end(s5)) < 1e-12, sprintf("소진 뒤 NAV 0 유지(실측 %.6f)", nav_end(s5)))

cat("⑥ 허용 밖 값 · 미지정\n")
e6 <- tryCatch({ run(H, copy(R1), W1, "monthly"); FALSE }, error = function(e) grepl("daily \\| bhr", conditionMessage(e)))
chk(isTRUE(e6), "허용 밖 값 = 멈춤")
s6 <- run(H, copy(R1), W1, NULL)
chk(isTRUE(all.equal(s6$DAILY_NAV_DT, sd$DAILY_NAV_DT, tolerance = 0)) && identical(s6$diagnostics$ls_combination, "daily"), "미지정 = daily(같은 산출)")

cat("⑦ 돌연변이 — bhr 가지를 끈 사본\n")
src <- readLines(HARNESS, encoding = "UTF-8", warn = FALSE)
needle <- 'if (identical(ls_combination, "bhr")) {'
hit <- grep(needle, src, fixed = TRUE)
chk(length(hit) == 1L, "치환 대상 1곳")
mut <- src; mut[hit] <- sub(needle, 'if (FALSE) {', mut[hit], fixed = TRUE)
chk(!identical(mut, src), "치환 성사")
tf <- tempfile(fileext = ".R"); writeLines(mut, tf, useBytes = TRUE)
M <- new.env(parent = globalenv()); sys.source(tf, envir = M)
sm <- run(M, copy(R1), W1, "bhr")
chk(abs(nav_end(sm) - 1.21) > 1e-6, sprintf("돌연변이 red — 끈 사본의 bhr NAV 끝 %.6f ≠ 1.21", nav_end(sm)))

cat("⑧ 러너 배선\n")
RUN <- file.path(root, "02_Infrastructure/alpha_search/run_paper_replication.R")
rs <- readLines(RUN, encoding = "UTF-8", warn = FALSE)
wire <- function(lines) {
  i <- grep("run_replication_simulation(RAWDATA, BM_DT, WEIGHTS,", lines, fixed = TRUE)
  all(vapply(i, function(k) any(grepl("ls_combination = ls_comb", lines[k:min(length(lines), k + 3L)], fixed = TRUE)), logical(1))) && length(i) == 2L
}
chk(wire(rs), "두 시뮬레이션 호출이 ls_combination = ls_comb 를 넘긴다")
k <- grep("exec_price = exec_price, ls_combination = ls_comb)", rs, fixed = TRUE)
rs2 <- rs; if (length(k)) rs2[k[1]] <- sub(", ls_combination = ls_comb)", ")", rs2[k[1]], fixed = TRUE)
chk(length(k) == 1L && !identical(rs2, rs) && !wire(rs2), "돌연변이 red — 한 호출에서 인자 삭제 사본")
chk(any(grepl('if (!identical(ls_comb, "daily")) list(ls_combination', rs, fixed = TRUE)), "기본 daily 는 auth 키 추가 0 · bhr 만 measurement_regime 에 기록")

cat(sprintf("\n결과: PASS=%d FAIL=%d\n", pass, fail))
## 러너 요약 계약(run_all_hooks.sh — 없으면 UNMEASURED 로 계상)
cat(sprintf('{"test":"replication_ls_combination","pass":%d,"fail":%d,"total":%d,"skipped":0}\n', pass, fail, pass + fail))
if (fail > 0L) quit(status = 1L)
