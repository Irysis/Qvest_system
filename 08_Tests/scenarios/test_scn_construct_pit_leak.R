#!/usr/bin/env Rscript
# test_scn_construct_pit_leak.R — 구성 엔진(E3) 운영 시나리오 시험 (2026-11-10)
#   (a) 정상 흐름: 12개월 월 1회 as-of 호출(Σ 공급자 · CDaR 구성) — 매달 사용 자료 종점 < 결정일
#   (b) 중간 실패: 요인 열 결손 → ts 는 멈춤(시끄럽게) · ctx 경로는 pca 로 내려가며 사유 기록 · LP 실행 불가 → min_cdar 복원 기록
#   (c) 업데이트 누락: 요인 표가 결정일 60일 전에 멈춤 → as-of 진입점은 멈추고 · ctx 끝 맞춤 경로는 '낡음' 기록 후 pca
#   (d) 재실행: 같은 입력 두 번 → 같은 출력(상태 · 파일 쓰기 없음)
#   (e) 누출 주입: 결정일 이후 한 달(21거래일 · 극단값)을 밀어 넣어도 출력 불변 + 돌연변이(컷 제거 사본)가 그 주입을 잡는다(양성 대조)
.root <- local({
  m <- file.path("02_Infrastructure", "reinforcement", "rf_factor_cov.R"); r <- NULL
  for (k in c("QM_ROOT", "CLAUDE_PROJECT_DIR")) { v <- gsub("\\\\", "/", Sys.getenv(k, "")); if (is.null(r) && nzchar(v) && file.exists(file.path(v, m))) r <- v }
  if (is.null(r)) { d <- getwd(); for (i in 1:6) { if (is.null(r) && file.exists(file.path(d, m))) r <- d; d <- dirname(d) } }
  if (is.null(r)) { a <- commandArgs(FALSE); f <- sub("^--file=", "", a[grep("^--file=", a)]); if (length(f)) { d <- dirname(gsub("\\\\", "/", f[1])); for (i in 1:6) { if (is.null(r) && file.exists(file.path(d, m))) r <- d; d <- dirname(d) } } }
  if (is.null(r)) stop("root 미발견"); r
})
Sys.setenv(QM_ROOT = .root)
suppressWarnings(suppressMessages(library(data.table)))
FCOV <- file.path(.root, "02_Infrastructure/reinforcement/rf_factor_cov.R")
CDAR <- file.path(.root, "02_Infrastructure/reinforcement/rf_cdar_construct.R")
E1 <- new.env(); sys.source(FCOV, envir = E1); E2 <- new.env(); sys.source(CDAR, envir = E2)
cfgF <- E1$rfc_config(file.path(.root, "02_Infrastructure/reinforcement/rf_factor_cov.json"))
cfgC <- E2$rcd_config(file.path(.root, "02_Infrastructure/reinforcement/rf_cdar_construct.json"))
P <- 0L; Fl <- 0L
ck <- function(cond, msg) { if (isTRUE(cond)) { P <<- P + 1L; cat("  [PASS]", msg, "\n") } else { Fl <<- Fl + 1L; cat("  [FAIL]", msg, "\n") } }
errs <- function(expr) { m <- tryCatch({ force(expr); NA_character_ }, error = function(e) conditionMessage(e)); m }

# 합성 패널 — 영업일 900일 · 30종목 · FF6 모양 요인
set.seed(20261110)
days <- seq(as.Date("2021-01-04"), by = "day", length.out = 1300); days <- days[!weekdays(days) %in% c("Saturday", "Sunday")][1:900]
K <- 6; fn <- c("MKT_TOTAL", "SMB5", "HML", "RMW", "CMA", "WML")
Fm <- matrix(stats::rnorm(900 * K), 900) %*% diag(c(0.012, 0.006, 0.005, 0.004, 0.004, 0.008)); colnames(Fm) <- fn
Fm[400:440, "MKT_TOTAL"] <- -0.012                                       # 확장 이력 안의 약세 구간(dd_state 표본)
N <- 30; tk <- sprintf("T%03d", 1:N); B <- cbind(stats::runif(N, 0.6, 1.4), matrix(stats::rnorm(N * 5, 0, 0.6), N))
Rm <- Fm %*% t(B) + matrix(stats::rnorm(900 * N, 0, 0.015), 900); colnames(Rm) <- tk
RET <- data.table(Date = rep(days, N), Ticker = rep(tk, each = 900), Ret = as.numeric(Rm))
FAC <- data.table(Date = days, Fm)
LB <- 252L
dec <- days[seq(500, 830, by = 30)][1:12]

cat("(a) 정상 흐름 — 12개월\n")
okm <- vapply(dec, function(d) {
  s <- E1$rfc_sigma_asof(RET, FAC, d, tk, LB, cfgF, model = "ts")
  c1 <- E2$rcd_construct_asof(RET, d, tk, LB, cfgC, mu = stats::setNames(stats::rnorm(N), tk))
  s$diag$max_used_date < d && c1$max_used_date < d && min(eigen(s$Sigma, TRUE, TRUE)$values) > 0 &&
    c1$n_active <= 25 && abs(sum(c1$w) - 1) < 1e-9
}, logical(1))
ck(all(okm), sprintf("12/12 달: 사용 자료 종점 < 결정일 · Σ PD · ≤25종 · Σw = 1 (%d/12)", sum(okm)))

d <- dec[6]
cat("(b) 중간 실패\n")
m1 <- errs(E1$rfc_sigma_asof(RET, FAC[, .(Date, foo = MKT_TOTAL)], d, tk, LB, cfgF, model = "ts"))
ck(!is.na(m1) && grepl("요인 열", m1), sprintf("요인 열 결손 → ts 멈춤: %s", m1))
lg <- utils::capture.output(sc <- E1$rfc_sigma_ctx(list(assets = tk, R = Rm[1:LB, ], decision_date = d,
                                                     factor_returns = function() FAC[, .(Date, foo = MKT_TOTAL)]), cfgF))
ck(identical(sc$model, "pca") && grepl("부족", sc$diag$fallback), sprintf("ctx 경로 → pca · 사유 '%s'", sc$diag$fallback))
cz <- cfgC; cz$nu_kappa <- 1e-6
oz <- E2$rcd_construct(Rm[1:LB, ], cz, mu = stats::setNames(stats::rnorm(N), tk), budget = "eq")
ck(!is.na(oz$fallback) && identical(oz$mode, "max_mu_cdar_cap") && abs(sum(oz$w) - 1) < 1e-9, sprintf("ν 실행 불가 → 복원 기록: %s", oz$fallback))

cat("(c) 업데이트 누락 — 요인 표가 60일 전에 멈춤\n")
FST <- FAC[Date < d - 60]
m2 <- errs(E1$rfc_sigma_asof(RET, FST, d, tk, LB, cfgF, model = "ts"))
ck(!is.na(m2) && grepl("덮지 못한다", m2), sprintf("as-of 진입점 멈춤: %s", m2))
Rw <- as.matrix(dcast(RET[Date < d], Date ~ Ticker, value.var = "Ret")[, -1L]); Rw <- utils::tail(Rw, LB)
sc2 <- E1$rfc_sigma_ctx(list(assets = tk, R = Rw, decision_date = d, factor_returns = function() FST), cfgF)
ck(identical(sc2$model, "pca") && grepl("낡음", sc2$diag$fallback), sprintf("ctx 끝 맞춤 → pca · '%s'", sc2$diag$fallback))

cat("(d) 재실행 멱등\n")
s1 <- E1$rfc_sigma_asof(RET, FAC, d, tk, LB, cfgF, model = "ts", variant = "dd_state")
s2 <- E1$rfc_sigma_asof(RET, FAC, d, tk, LB, cfgF, model = "ts", variant = "dd_state")
mu6 <- stats::setNames(seq(1, -1, length.out = N), tk)
c1 <- E2$rcd_construct_asof(RET, d, tk, LB, cfgC, mu = mu6); c2 <- E2$rcd_construct_asof(RET, d, tk, LB, cfgC, mu = mu6)
ck(identical(s1$Sigma, s2$Sigma) && identical(c1$w, c2$w), "같은 입력 두 번 → 비트 동일")

cat("(e) 누출 주입(결정일 이후 21거래일 · 극단값) + 돌연변이 양성 대조\n")
fut <- days[days >= d][1:21]
# 주입 = 결정일 이후 한 달 행의 값을 극단값으로 덮어쓴다(행 추가가 아니라 — 추가하면 (Date, Ticker) 겹침이 된다)
RETx <- copy(RET)[Date %in% fut, Ret := 0.5]
FACx <- copy(FAC)[Date %in% fut, `:=`(MKT_TOTAL = -0.3, SMB5 = 0.2, HML = -0.2, RMW = 0.2, CMA = -0.2, WML = 0.2)]
m0 <- errs(E1$rfc_sigma_asof(rbind(RET, RET[Date == days[10]]), FAC, d, tk, LB, cfgF, model = "ts"))
ck(!is.na(m0) && grepl("겹침", m0), sprintf("(Date, Ticker) 겹침 → 멈춤(dcast 개수 집계 차단): %s", m0))
base_s <- E1$rfc_sigma_asof(RET, FAC, d, tk, LB, cfgF, model = "ts", variant = "dd_state")
inj_s  <- E1$rfc_sigma_asof(RETx, FACx, d, tk, LB, cfgF, model = "ts", variant = "dd_state")
ck(identical(base_s$Sigma, inj_s$Sigma), "Σ(dd_state) 주입 전후 비트 동일")
base_c <- E2$rcd_construct_asof(RET, d, tk, LB, cfgC, mu = mu6); inj_c <- E2$rcd_construct_asof(RETx, d, tk, LB, cfgC, mu = mu6)
ck(identical(base_c$w, inj_c$w), "CDaR 구성 비중 주입 전후 비트 동일")

mutate <- function(path, pairs) {
  src <- readLines(path, warn = FALSE, encoding = "UTF-8"); n <- 0L
  for (p in pairs) { hit <- grepl(p[1], src, fixed = TRUE); n <- n + sum(hit); src[hit] <- gsub(p[1], p[2], src[hit], fixed = TRUE) }
  f <- tempfile(fileext = ".R"); writeLines(src, f, useBytes = TRUE); e <- new.env(); sys.source(f, envir = e)
  list(env = e, n = n)
}
# 돌연변이 1 — 종목 수익 컷 제거(단언은 남김) → 2선 단언이 멈춰야 한다
M1 <- mutate(FCOV, list(c("as.data.table(ret)[Date < d & Ticker %in% assets]", "as.data.table(ret)[Ticker %in% assets]")))
mm1 <- errs(M1$env$rfc_sigma_asof(RETx, FACx, d, tk, LB, cfgF, model = "pca"))
ck(M1$n == 1L && !is.na(mm1) && grepl("PIT 단언", mm1), sprintf("돌연변이 1(치환 %d) · pca → 2선 단언 발화: %s", M1$n, mm1))
mm1t <- errs(M1$env$rfc_sigma_asof(RETx, FACx, d, tk, LB, cfgF, model = "ts"))
ck(!is.na(mm1t) && grepl("덮지 못한다", mm1t), sprintf("돌연변이 1 · ts → 요인 표 컷과 어긋나 먼저 멈춤(3선): %s", mm1t))
# 돌연변이 2 — 컷 + 단언 제거 → 출력이 달라져야 한다(1선 시험의 이빨)
M2 <- mutate(FCOV, list(c("as.data.table(ret)[Date < d & Ticker %in% assets]", "as.data.table(ret)[Ticker %in% assets]"),
                        c("if (out$diag$max_used_date >= d) stop", "if (FALSE) stop"),
                        c("fh <- as.data.table(fac)[Date < d]", "fh <- as.data.table(fac)")))
ms2 <- tryCatch(M2$env$rfc_sigma_asof(RETx, FACx, d, tk, LB, cfgF, model = "ts", variant = "dd_state")$Sigma, error = function(e) NULL)
ck(M2$n == 3L && !is.null(ms2) && !identical(ms2, base_s$Sigma), sprintf("돌연변이 2(치환 %d) → 주입이 Σ 를 바꾼다(검출)", M2$n))
# 돌연변이 3 — 요인 이력 컷만 제거 → dd_state Ω 가 미래 급락을 먹는다(종목 창은 그대로)
M3 <- mutate(FCOV, list(c("fh <- as.data.table(fac)[Date < d]", "fh <- as.data.table(fac)")))
ms3 <- M3$env$rfc_sigma_asof(RET, FACx, d, tk, LB, cfgF, model = "ts", variant = "dd_state")
ck(M3$n == 1L && !identical(ms3$Sigma, base_s$Sigma) && ms3$diag$n_omega > base_s$diag$n_omega,
   sprintf("돌연변이 3(치환 %d) → 미래 급락 %d일이 위기 Ω 표본에 섞임(%d → %d)", M3$n, 21L, base_s$diag$n_omega, ms3$diag$n_omega))
# 돌연변이 4 — CDaR 시나리오 컷 + 단언 제거
M4 <- mutate(CDAR, list(c("as.data.table(ret)[Date < d & Ticker %in% assets]", "as.data.table(ret)[Ticker %in% assets]"),
                        c("if (o$max_used_date >= d) stop", "if (FALSE) stop")))
mc4 <- tryCatch(M4$env$rcd_construct_asof(RETx, d, tk, LB, cfgC, mu = mu6)$w, error = function(e) NULL)
ck(M4$n == 2L && !is.null(mc4) && !identical(mc4, base_c$w), sprintf("돌연변이 4(치환 %d) → 주입이 비중을 바꾼다(검출)", M4$n))

cat(sprintf('{"test":"test_scn_construct_pit_leak","pass":%d,"fail":%d,"total":%d}\n', P, Fl, P + Fl))
if (Fl > 0L) quit(status = 1L)
