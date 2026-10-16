## test_msm_asof.R — 02_Infrastructure/regime/msm_asof.R 검사(결정 PIT-C1-MSM-PARAMS 안 A · 2026-10-16)
##   1 PC1 고속 커널 = 운영 조밀 커널 · 2 완료 연도 · 3 식별 가드 · 4 원장 append-only · 5 적용 구간 (r_k, r_{k+1}] · 6 접두 불변(PIT) ·
##   7 벤치 해시 · 8 생산자 흐름(적합 대역 · 순서 · 승계 · 빈 해 거부 · 재실행 0) · 9 운영 원장 · 캐시(있을 때 — PC2 저장 = 재계산)
## 실행: Rscript 08_Tests/regime/test_msm_asof.R
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; Sys.setenv(QM_ROOT = ROOT); setwd(ROOT)
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat("  OK  ", m, "\n") }
ng <- function(m, d = "") { FAIL <<- FAIL + 1L; cat("  FAIL", m, d, "\n") }
source(file.path(ROOT, "02_Infrastructure/regime/msm_asof.R"))
bm <- msma_load_bm(ROOT); RT <- msma_returns(bm)
pin <- unlist(fromJSON(file.path(ROOT, "02_Infrastructure/ops/msm_param_pin.json"))$params)[c("m0", "sigma", "b", "gamma_1")]

## 1) PC1 — 고속 커널 = 운영 조밀 커널(핀 모수 · 전기간 실제 수익)
fk <- msma_kernel(ROOT); pk <- msma_prod_kernel(ROOT)
pd <- pk$extract_msm_path(RT$r, MSMA_K_BAR, pin[["m0"]], pin[["sigma"]], pin[["b"]], pin[["gamma_1"]])
fd <- fk$msm_fast_filter(RT$r, MSMA_K_BAR, pin[["m0"]], pin[["sigma"]], pin[["b"]], pin[["gamma_1"]], TRUE)
pc1 <- max(abs(pd$CrisisProb - fd$crisis_prob))
if (pc1 < 1e-10) ok(sprintf("1 PC1 고속 커널 = 운영 조밀 커널(최대 차 %.1e · %d일)", pc1, nrow(RT))) else ng("1 PC1", pc1)

## 2) 완료 연도 — 다음 해 자료가 있어야 완료 · 해의 마지막 거래일
dd <- as.Date(c("2002-12-30", "2003-06-02", "2003-12-30", "2004-12-29", "2004-12-30", "2005-03-02"))
ye <- msma_year_ends(dd)
if (identical(ye$y, c(2003L, 2004L)) && identical(format(ye$rf), c("2003-12-30", "2004-12-30")) && !nrow(msma_year_ends(dd[1:5], 2005L)))
  ok("2 완료 연도 = 2003 · 2004(2005 는 진행 중) · 해의 마지막 거래일") else ng("2", paste(ye$y, format(ye$rf)))

## 3) 식별 가드(사전 고정 — γ1 < 1e-5 또는 σ/sd ∉ [0.8, 1.25] = 퇴화)
mk <- function(...) { v <- list(...); list(inits = lapply(v, function(z) list(par = list(m0 = z[1], sigma = z[2], b = z[3], gamma_1 = z[4]), negloglik = z[5]))) }
g1 <- msma_guard(mk(c(1.4, 0.010, 3, 1e-7, -100), c(1.3, 0.010, 2, 0.01, -99)), 0.010)
g2 <- msma_guard(mk(c(1.4, 0.010, 3, 0.02, -100), c(1.3, 0.010, 2, 0.01, -99)), 0.010)
g3 <- msma_guard(mk(c(1.4, 0.020, 3, 0.02, -100), c(1.3, 0.010, 2, 1e-8, -99)), 0.010, prev_theta = list(m0 = 1.1, sigma = 0.01, b = 2, gamma_1 = 0.03))
g4 <- tryCatch(msma_guard(mk(c(1.4, 0.020, 3, 0.02, -100)), 0.010), error = function(e) "err")
g5 <- msma_guard(mk(c(1.4, 0.0125, 3, 0.02, -100), c(1.3, 0.010, 2, 0.01, -99)), 0.010)
if (identical(g1$guard_action, "best_nondegenerate") && identical(g1$theta$gamma_1, 0.01) && identical(g1$raw_mle$par$gamma_1, 1e-7) &&
    identical(g2$guard_action, "mle") && identical(g3$guard_action, "carry_forward_previous") && identical(g3$theta$m0, 1.1) && is.na(g3$negloglik) &&
    identical(g4, "err") && identical(g5$guard_action, "mle"))
  ok("3 식별 가드 — 최적점 퇴화면 비퇴화 최고 · 비퇴화면 MLE · 전부 퇴화면 직전 유효 승계 · 첫 적합 전부 퇴화는 중단 · 경계 1.25 포함") else ng("3")

## 4) 원장 append-only
tl <- file.path(tempdir(), "msm_ledger_t4.json"); unlink(tl)
row <- function(d) list(fit_date = d, data_end = d, theta = list(m0 = 1.3, sigma = 0.01, b = 2, gamma_1 = 0.01), guard_action = "mle")
msma_ledger_append(tl, row("2003-12-30")); msma_ledger_append(tl, row("2004-12-30"))
e1 <- tryCatch(msma_ledger_append(tl, row("2004-12-30")), error = function(e) "dup")
e2 <- tryCatch(msma_ledger_append(tl, row("2002-12-30")), error = function(e) "back")
L4 <- msma_ledger_read(tl); L4$estimator <- "x"; writeLines(toJSON(L4, auto_unbox = TRUE, null = "null"), tl)
e3 <- tryCatch(msma_ledger_append(tl, row("2005-12-29")), error = function(e) "est")
if (identical(e1, "dup") && identical(e2, "back") && identical(e3, "est") && length(msma_ledger_read(tl)$rows) == 2L)
  ok("4 원장 append-only — 같은 적합일 재기록 · 날짜 역행 · 추정기 불일치 거부") else ng("4")

## 5) 적용 구간 (r_k, r_{k+1}] — r_k 당일은 직전 θ · 다음 날부터 새 θ
r1 <- max(RT$Date[format(RT$Date, "%Y") == "2005"]); r2 <- max(RT$Date[format(RT$Date, "%Y") == "2010"])
S5 <- data.table(fit_date = c(r1, r2), m0 = c(1.30, 1.45), sigma = c(0.012, 0.015), b = c(2.0, 3.0), gamma_1 = c(0.02, 0.05), guard_action = "mle")
nx <- function(d) min(RT$Date[RT$Date > d])
P5 <- tryCatch(msma_path(RT, S5, root = ROOT), error = function(e) { ng("5", paste("오류:", conditionMessage(e))); NULL })
if (!is.null(P5)) {
  ref_r2 <- fk$msm_fast_filter(RT$r[RT$Date <= r2], MSMA_K_BAR, 1.30, 0.012, 2.0, 0.02, TRUE)$crisis_prob
  ref_n2 <- fk$msm_fast_filter(RT$r[RT$Date <= nx(r2)], MSMA_K_BAR, 1.45, 0.015, 3.0, 0.05, TRUE)$crisis_prob
  if (isTRUE(!(r1 %in% P5$Date) && identical(P5[Date == nx(r1)]$msm_fit_date, r1) && identical(P5[Date == r2]$msm_fit_date, r1) &&
      identical(P5[Date == nx(r2)]$msm_fit_date, r2) && abs(P5[Date == r2]$Crisis_Prob - tail(ref_r2, 1)) < 1e-14 &&
      abs(P5[Date == nx(r2)]$Crisis_Prob - tail(ref_n2, 1)) < 1e-14 && all(P5$msm_fit_date < P5$Date) && min(P5$Date) == nx(r1)))
    ok("5 적용 구간 (r_k, r_{k+1}] — 첫 적합일 당일 값 없음 · r_2 당일 = θ_1 · 다음 거래일부터 θ_2 · 값 = 처음부터 전방 필터") else ng("5")
}

## 6) 접두 불변(PIT) — 자료를 t 에서 잘라 다시 계산해도 t 이하 값이 같다(필터 · 디민 · 블록 적용 인과)
cuts <- as.Date(c("2008-09-30", "2011-08-31", "2015-12-30"))
d6 <- tryCatch(vapply(cuts, function(tc) { bt <- bm[Date <= tc]; Pt <- msma_path(msma_returns(bt), S5[fit_date < tc], root = ROOT)
  J <- merge(Pt[, .(Date, a = Crisis_Prob)], P5[Date <= tc, .(Date, b = Crisis_Prob)], by = "Date")
  if (nrow(J) != nrow(P5[Date <= tc])) return(Inf); max(abs(J$a - J$b)) }, numeric(1)), error = function(e) Inf)
if (isTRUE(all(d6 < 1e-13))) ok(sprintf("6 접두 불변 — 절단 3곳(2008-09 · 2011-08 · 2015-12) 최대 차 %.1e", max(d6))) else ng("6", paste(d6))

## 7) 벤치 해시 — 적합 자료 범위 안 수정만 잡는다
h0 <- msma_bench_sha(bm, "2010-12-30"); b2 <- copy(bm); b2[Date == as.Date("2009-03-02"), BM_Close := BM_Close * 1.001]
b3 <- copy(bm); b3[Date == max(Date), BM_Close := BM_Close * 1.001]
if (identical(h0, msma_bench_sha(bm, "2010-12-30")) && !identical(h0, msma_bench_sha(b2, "2010-12-30")) && identical(h0, msma_bench_sha(b3, "2010-12-30")))
  ok("7 벤치 해시 — 같은 자료 같음 · 범위 안 수정 다름 · 범위 밖 수정 같음") else ng("7")

## 8) 생산자 흐름 — 적합 대역(stub)으로 빠른 검사: 빠진 해만 순서대로 적합 · 가드 승계 · 재실행 0 · 빈 해 끼워 넣기 거부
real_fit <- msma_fit
msma_fit <- function(ret, k_bar = MSMA_K_BAR, root = NULL) {
  n <- length(ret); dg <- n %% 2L == 0L                                    # 자료 길이 짝수인 해는 '전부 퇴화'로 꾸민다(승계 경로)
  s <- sd(ret); p <- function(g) list(m0 = 1.3, sigma = if (dg) 3 * s else s, b = 2, gamma_1 = g)
  list(inits = list(list(par = p(0.02), negloglik = -n), list(par = p(0.03), negloglik = -n + 1), list(par = p(0.04), negloglik = -n + 2)), secs = 0, evals = 0L)
}
tl8 <- file.path(tempdir(), "msm_ledger_t8.json"); unlink(tl8); to8 <- file.path(tempdir(), "msm_asof_t8.parquet"); unlink(to8)
bm8 <- bm[Date <= as.Date("2007-03-30")]
YE8 <- msma_year_ends(msma_returns(bm8)$Date)
u1 <- tryCatch(msma_update(ROOT, ledger = tl8, out = to8, bm = bm8, verbose = FALSE), error = function(e) conditionMessage(e))
L8 <- msma_ledger_read(tl8)
acts <- vapply(L8$rows, function(z) z$guard_action, ""); dates8 <- vapply(L8$rows, function(z) z$fit_date, "")
u2 <- if (is.list(u1)) msma_update(ROOT, ledger = tl8, out = to8, bm = bm8, verbose = FALSE) else NULL
P8 <- if (file.exists(to8)) arrow::read_parquet(to8, as_data_frame = FALSE) else NULL
cond8 <- is.list(u1) && identical(dates8, format(YE8$rf)) && u1$new_fits == nrow(YE8) && identical(u2$new_fits, 0L) &&
  all(acts %in% c("mle", "carry_forward_previous")) && !is.null(P8) && identical(P8$metadata$msm_estimator, "asof_yearly:v1")
## 승계 행은 직전 유효 θ 를 그대로 싣는다
cf <- which(acts == "carry_forward_previous")
cond8b <- !length(cf) || all(vapply(cf, function(i) i > 1L && identical(L8$rows[[i]]$theta, L8$rows[[i - 1L]]$theta), logical(1)))
## 빈 해 끼워 넣기 거부 — 원장 2003 · 2005 만 있고 2004 가 빠졌으면 중단
tl8g <- file.path(tempdir(), "msm_ledger_t8g.json"); unlink(tl8g)
msma_ledger_append(tl8g, L8$rows[[1]]); msma_ledger_append(tl8g, L8$rows[[3]])
u3 <- tryCatch(msma_update(ROOT, ledger = tl8g, out = NULL, bm = bm8, verbose = FALSE), error = function(e) "gap")
msma_fit <- real_fit
if (cond8 && cond8b && identical(u3, "gap"))
  ok(sprintf("8 생산자 흐름 — 완료 연도 %d개 순서대로 적합 · 승계 %d행 = 직전 θ · 재실행 새 적합 0 · 캐시 추정기 표식 · 빈 해 거부", nrow(YE8), length(cf))) else
  ng("8", paste(if (is.character(u1)) u1 else "", paste(acts, collapse = ","), identical(u3, "gap")))

## 9) 운영 원장 · 캐시(있을 때) — PC2 저장 캐시 = 원장으로 재계산 · 적합일 = 2003~ 완료 연도 연속 · 가드 어휘
LP <- msma_ledger_path(ROOT); CP <- file.path(ROOT, ".cache/msm_asof_daily.parquet")
if (file.exists(LP) && file.exists(CP)) {
  L9 <- msma_ledger_read(LP); S9 <- msma_schedule(L9)
  st <- as.data.table(arrow::read_parquet(CP)); st[, Date := as.Date(Date)]
  P9 <- msma_path(RT, S9, root = ROOT)
  J9 <- merge(st[, .(Date, a = Crisis_Prob)], P9[, .(Date, b = Crisis_Prob)], by = "Date")
  ye9 <- msma_year_ends(RT$Date)
  meta <- arrow::read_parquet(CP, as_data_frame = FALSE)$metadata
  if (nrow(J9) == nrow(st) && max(abs(J9$a - J9$b)) < 1e-12 && identical(format(S9$fit_date), format(ye9$rf)) &&
      all(S9$guard_action %in% c("mle", "best_nondegenerate", "carry_forward_previous")) && identical(meta$msm_estimator, "asof_yearly:v1"))
    ok(sprintf("9 운영 원장 %d행(%s~%s) · 캐시 %d일 = 재계산(PC2 최대 차 %.1e) · 추정기 표식", nrow(S9), format(min(S9$fit_date)), format(max(S9$fit_date)),
               nrow(st), max(abs(J9$a - J9$b)))) else ng("9", sprintf("n %d/%d · fit dates %s", nrow(J9), nrow(st), paste(format(S9$fit_date), collapse = ",")))
} else cat("  SKIP 9 운영 원장 · 캐시 없음(초기 적합 전)\n")

cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
cat(sprintf('{"test":"msm_asof","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL > 0L) 1L else 0L)
