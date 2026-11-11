#!/usr/bin/env Rscript
#==============================================================================
# test_skew_rp_bkr_2022.R — 왜도(점프) 위험 예산 어댑터(arXiv 2202.10721 · 2026-11-11) 시험 · 합성 자료만
#
# 지키는 것:
#   a. ES 해석식(식 eq:es1) = 손실 밀도 수치 적분 · VaR 근 = 혼합 분포함수 · 논문 예 1 표(점프 有 37.22 · 無 28.46 · RC 4.08/5.46/27.68)
#   b. 오일러 분해 ΣRC = ES · 식 (eq:rc1) = ES 의 중앙 차분 기울기 = 단순형(VaR 항 소거) · 해에서 RC/ES = 1/n ·
#      논문 예 2 표(ERC 점프 44.70/19.87/35.42 · 가우시안 ES 60.85/21.96/17.19) · α⁻(57.4% · 67.11%)
#   c. 점프를 심은 합성 자료 — 점프 종목의 비중이 변동성 ERC(erc_maillard_roncalli_teiletche_2010.R)보다 낮다 · 점프일 검출
#   d. 점프 없는 자료 — 'Gaussian model → traditional ERC'(§4.2): 낙하 nojump 이 진단 줄에 남고 해 = 변동성 ERC
#   e. 결정성 · 비음 · 이름 보존 · 자산 순서 치환 불변 · 운영 래퍼 통과 · ctx 밖 접근 없음 · 진단 줄 형식
#   f. 돌연변이 3종(소스 텍스트 치환 · 정확히 한 곳 · 사본 단독 실행 단정) — 각 사본은 a/b/c 중 해당 묶음을 통과하지 못해야 한다
#==============================================================================
suppressMessages(library(data.table))
.find_root <- function() {
  for (c in c(getwd(), Sys.getenv("CLAUDE_PROJECT_DIR"), Sys.getenv("QM_ROOT"))) {
    if (nzchar(c) && file.exists(file.path(c, "02_Infrastructure/methods/register_method.R"))) return(normalizePath(c, "/", TRUE))
  }
  stop("저장소 루트를 찾지 못했다 — 저장소 루트에서 실행할 것")
}
ROOT <- .find_root(); setwd(ROOT)
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat(sprintf("  OK   %s\n", m)) }
ng <- function(m, d = "") { FAIL <<- FAIL + 1L; cat(sprintf("  FAIL %s%s\n", m, if (nzchar(d)) paste0(" — ", d) else "")) }
quiet <- function(expr) { o <- capture.output(v <- tryCatch(expr, error = function(e) e)); list(v = v, out = o) }

AD <- "02_Infrastructure/methods/adapters/skew_rp_bruder_kostyuchyk_roncalli_2022.R"
load_adapter <- function(text = NULL) {
  E <- new.env(parent = globalenv())
  if (is.null(text)) sys.source(file.path(ROOT, AD), envir = E) else eval(parse(text = text, encoding = "UTF-8"), envir = E)
  E
}
E0 <- load_adapter()
ERC <- new.env(parent = globalenv()); sys.source(file.path(ROOT, "02_Infrastructure/methods/adapters/erc_maillard_roncalli_teiletche_2010.R"), envir = ERC)
suppressMessages(source(file.path(ROOT, "02_Infrastructure/methods/method_registry.R")))         # wrap_adapter(운영 래퍼)
suppressMessages(source(file.path(ROOT, "02_Infrastructure/portfolio/strategy_tilt_weights.R")))  # 래퍼 의존 normalize_long_only

## ── 논문 예(§3.2 예 1 · §3.3.2 예 2) ─────────────────────────────────────────
cor3 <- matrix(c(1, .5, .2, .5, 1, .4, .2, .4, 1), 3)
.ex1 <- function() {
  s <- c(.2, .25, .3); rj <- matrix(.5, 3, 3); diag(rj) <- 1; sj <- rep(.2, 3)
  list(mu = c(.1, .15, .2), Sig = diag(s) %*% cor3 %*% diag(s), muJ = rep(-.1, 3), SigJ = diag(sj) %*% rj %*% diag(sj), lam = .25, alpha = .95)
}
.ex2 <- function() {
  s <- c(.08, .2, .3); sj <- c(.15, .2, .1); rj <- diag(3); rj[1, 2] <- rj[2, 1] <- .5
  list(mu = c(.03, .08, .12), Sig = diag(s) %*% cor3 %*% diag(s), muJ = c(-.15, -.4, 0), SigJ = diag(sj) %*% rj %*% diag(sj), lam = .25, alpha = .95)
}

## ── 합성 패널 ──────────────────────────────────────────────────────────────
## 점프 패널: 20종 · 252일 · 시장 1요인(β 1 · sd 1%) · A = 5종(정상 잡음 1% + 공통 점프일 4일에 −30%) · B = 15종(잡음 3.9% —
##   표본 총분산이 A 와 비슷해 변동성 ERC 는 둘을 거의 같게 본다). 점프일의 균등가중 수익 ≈ −7.5% ≈ 정상 σ 의 6배.
jump_panel <- function(seed = 20261111L) {
  set.seed(seed); Tn <- 252L
  m <- rnorm(Tn, 0, 0.01)
  A <- sapply(1:5, function(j) m + rnorm(Tn, 0, 0.010))
  B <- sapply(1:15, function(j) m + rnorm(Tn, 0, 0.039))
  jd <- c(40L, 101L, 160L, 222L); A[jd, ] <- A[jd, ] - 0.30
  X <- cbind(A, B); colnames(X) <- c(sprintf("J%02d", 1:5), sprintf("N%02d", 1:15)); X
}
## 점프 없는 패널: 12종 · 252일 · 시장 1요인(β 0.7~1.3) + 가우시안 잡음(변동성 이질)
nojump_panel <- function(seed = 7L) {
  set.seed(seed); Tn <- 252L; n <- 12L
  m <- rnorm(Tn, 0, 0.01); be <- seq(0.7, 1.3, length.out = n); sv <- seq(0.006, 0.03, length.out = n)
  X <- sapply(seq_len(n), function(j) be[j] * m + rnorm(Tn, 0, sv[j])); colnames(X) <- sprintf("G%02d", seq_len(n)); X
}
mkctx <- function(X, d = "2015-06-30") list(R = X, assets = colnames(X), mu = setNames(rep(0, ncol(X)), colnames(X)), Sigma = stats::cov(X),
                                          ub = 1, lookback_days = nrow(X), decision_date = as.Date(d), eval_date = as.Date(d) + 30)
XJ <- jump_panel(); XG <- nojump_panel()

## ── 묶음 a · b · c (돌연변이 사본에도 같은 함수를 돌린다) ─────────────────────
group_a <- function(E) {
  r <- list()
  p <- .ex1(); x <- c(.2, .2, .6)
  e <- E$.skrp_es(x, p)
  m1 <- sum(x * p$mu); s1 <- sqrt(drop(x %*% p$Sig %*% x)); m2 <- sum(x * (p$mu + p$muJ)); s2 <- sqrt(drop(x %*% (p$Sig + p$SigJ) %*% x))
  g <- function(l) (1 - p$lam) * dnorm(l, -m1, s1) + p$lam * dnorm(l, -m2, s2)       # 손실 L = −R 의 혼합 밀도
  cdf <- integrate(g, -Inf, e$var, rel.tol = 1e-12)$value
  esn <- integrate(function(l) l * g(l), e$var, Inf, rel.tol = 1e-12)$value / (1 - p$alpha)
  r$a1 <- c(abs(cdf - p$alpha) < 1e-9, sprintf("a1 VaR 근: 밀도 적분 F(VaR) = %.10f(α = %.2f)", cdf, p$alpha))
  r$a2 <- c(abs(esn - e$es) < 1e-9, sprintf("a2 ES 해석식 %.10f = 수치 적분 %.10f(차 %.1e)", e$es, esn, abs(esn - e$es)))
  r$a3 <- c(abs(100 * e$es - 37.22) < 0.005 && all(abs(100 * e$rc - c(4.08, 5.46, 27.68)) < 0.005),
            sprintf("a3 논문 예 1 표(점프 有): ES %.2f · RC %s(표 37.22 · 4.08/5.46/27.68)", 100 * e$es, paste(sprintf("%.2f", 100 * e$rc), collapse = "/")))
  e0 <- E$.skrp_es(x, modifyList(p, list(lam = 0)))
  r$a4 <- c(abs(100 * e0$es - 28.46) < 0.005 && all(abs(100 * e0$rc - c(1.78, 3.64, 23.04)) < 0.005),
            sprintf("a4 논문 예 1 표(점프 無): ES %.2f · RC %s(표 28.46 · 1.78/3.64/23.04)", 100 * e0$es, paste(sprintf("%.2f", 100 * e0$rc), collapse = "/")))
  ## a5 — 일별 축 척도: 점프 패널에서 추정한 모형 · 무작위 아닌 비중에서 해석식 = 고정 시드 몬테카를로(표본 2e6 · 허용 3%)
  est <- E$.skrp_estimate(XJ); n <- ncol(XJ)
  if (identical(est$status, "none")) {
    pj <- list(mu = rep(0, n), Sig = est$Sig, muJ = est$muJ, SigJ = est$SigJ, lam = est$lam, alpha = .99)
    w <- seq(1, 2, length.out = n); w <- w / sum(w)
    ej <- E$.skrp_es(w, pj)
    set.seed(99L); N <- 2e6L
    m1 <- 0; s1 <- sqrt(drop(w %*% pj$Sig %*% w)); m2 <- sum(w * pj$muJ); s2 <- sqrt(drop(w %*% (pj$Sig + pj$SigJ) %*% w))
    jmp <- runif(N) < pj$lam; R <- ifelse(jmp, rnorm(N, m2, s2), rnorm(N, m1, s1)); L <- sort(-R, decreasing = TRUE)
    esmc <- mean(L[seq_len(ceiling((1 - pj$alpha) * N))])
    r$a5 <- c(abs(esmc / ej$es - 1) < 0.03, sprintf("a5 일별 추정 모형 ES 해석식 %.5f ≈ 몬테카를로 %.5f(상대차 %.2f%% · 시드 99)", ej$es, esmc, 100 * abs(esmc / ej$es - 1)))
  } else r$a5 <- c(FALSE, sprintf("a5 전제 불성립 — 점프 패널 추정 상태 %s", est$status))
  r
}

group_b <- function(E) {
  r <- list()
  p <- .ex2(); x <- c(.5, .3, .2)
  e <- E$.skrp_es(x, p)
  r$b1 <- c(abs(sum(e$rc) - e$es) < 1e-12, sprintf("b1 오일러 분해 ΣRC = ES(차 %.1e)", abs(sum(e$rc) - e$es)))
  fd <- sapply(1:3, function(i) { h <- 1e-6; xp <- x; xm <- x; xp[i] <- x[i] + h; xm[i] <- x[i] - h; (E$.skrp_es(xp, p)$es - E$.skrp_es(xm, p)$es) / (2 * h) })
  r$b2 <- c(max(abs(fd - e$mr)) < 1e-7, sprintf("b2 식 (eq:rc1) 한계 위험 = ES 중앙 차분(최대차 %.1e)", max(abs(fd - e$mr))))
  ## 단순형: ∂ES = Σ π_i[ϕ(h_i)∂σ_i − Φ(−h_i)∂μ_i]/(1 − α) — δ 의 VaR 항 소거 확인
  S2 <- p$Sig + p$SigJ; m1 <- sum(x * p$mu); m2 <- sum(x * (p$mu + p$muJ)); s1 <- sqrt(drop(x %*% p$Sig %*% x)); s2 <- sqrt(drop(x %*% S2 %*% x))
  h1 <- (e$var + m1) / s1; h2 <- (e$var + m2) / s2
  ms <- ((1 - p$lam) * (dnorm(h1) * drop(p$Sig %*% x) / s1 - pnorm(-h1) * p$mu) + p$lam * (dnorm(h2) * drop(S2 %*% x) / s2 - pnorm(-h2) * (p$mu + p$muJ))) / (1 - p$alpha)
  r$b3 <- c(max(abs(ms - e$mr)) < 1e-12, sprintf("b3 원문 식 (eq:rc1) = 단순형(VaR 항 소거 · 차 %.1e)", max(abs(ms - e$mr))))
  sol <- E$.skrp_rb(p, rep(1 / 3, 3)); xs <- sol$y / sum(sol$y); es <- E$.skrp_es(xs, p)
  r$b4 <- c(isTRUE(sol$converged) && max(abs(es$rc / es$es - 1 / 3)) < 1e-8, sprintf("b4 해에서 RC/ES = 1/3(최대차 %.1e · 반복 %d)", max(abs(es$rc / es$es - 1 / 3)), sol$iters))
  r$b5 <- c(all(abs(100 * xs - c(44.70, 19.87, 35.42)) < 0.005) && abs(100 * es$es - 33.12) < 0.005,
            sprintf("b5 논문 예 2 표(ERC · 점프 ES 95%%): %s · ES %.2f(표 44.70/19.87/35.42 · 33.12)", paste(sprintf("%.2f", 100 * xs), collapse = "/"), 100 * es$es))
  sg <- E$.skrp_rb(modifyList(p, list(lam = 0)), rep(1 / 3, 3)); xg <- sg$y / sum(sg$y)
  r$b6 <- c(all(abs(100 * xg - c(60.85, 21.96, 17.19)) < 0.005), sprintf("b6 논문 예 2 표(ERC · 가우시안 ES 95%%): %s(표 60.85/21.96/17.19)", paste(sprintf("%.2f", 100 * xg), collapse = "/")))
  am1 <- E$.skrp_alpha_minus(.25, .52); am2 <- E$.skrp_alpha_minus(.25, .75)
  r$b7 <- c(abs(am1 - .574) < 5e-4 && abs(am2 - .6711) < 5e-5, sprintf("b7 존재 하한 α⁻: λ .25 · SR .52 → %.4f(논문 57.4%%) · SR .75 → %.4f(논문 67.11%%)", am1, am2))
  r$b8 <- c(isTRUE(E$.skrp_exists(.99, .02, 0)) && !isTRUE(E$.skrp_exists(.99, .995, 0)) && !isTRUE(E$.skrp_exists(.60, .25, .75)),
            "b8 존재 조건 α ≥ max(α⁻, λ): (.99, λ .02, SR 0) 성립 · (λ .995 > α) 실패 · (.60 < α⁻ .6711) 실패")
  r
}

group_c <- function(E) {
  r <- list()
  ctx <- mkctx(XJ)
  q <- quiet(E$method_weights(ctx)); v <- q$v
  if (inherits(v, "error")) return(list(c1 = c(FALSE, paste("c1 실행 오류:", conditionMessage(v)))))
  w <- v / sum(v); we <- ERC$erc_weights_mrt2010(stats::cov(XJ))$w
  jA <- grepl("^J", names(w))
  ln <- grep("^\\[skrp\\] ", q$out, value = TRUE)
  r$c1 <- c(length(ln) == 1L && grepl(" n_jump=4 ", ln) && grepl("fallback=none$", ln), sprintf("c1 심은 점프일 4개 검출 · 낙하 없음('%s')", paste(ln, collapse = "|")))
  r$c2 <- c(sum(w[jA]) < sum(we[jA]) - 0.02, sprintf("c2 점프 종목 합계 비중 왜도 RP %.3f < 변동성 ERC %.3f", sum(w[jA]), sum(we[jA])))
  r$c3 <- c(all(w[jA] < we[jA]), sprintf("c3 점프 종목 각각 왜도 RP < 변동성 ERC(최대 %.4f vs 최소 ERC %.4f)", max(w[jA]), min(we[jA])))
  r
}

run_group <- function(gr, label) {
  cat(sprintf("\n=== %s ===\n", label))
  for (z in gr) if (identical(z[1], "TRUE")) ok(z[2]) else ng(z[2])
}

run_group(group_a(E0), "a. ES 해석식 대조")
run_group(group_b(E0), "b. 위험 기여 · 오일러 · 위험 예산 해")
run_group(group_c(E0), "c. 점프 심은 자료 — 점프 종목 비중 < 변동성 ERC")

cat("\n=== d. 점프 없는 자료 — 가우시안 모형 = 변동성 ERC(§4.2) ===\n")
qd <- quiet(E0$method_weights(mkctx(XG))); vd <- qd$v
lnd <- grep("^\\[skrp\\] ", qd$out, value = TRUE)
if (!inherits(vd, "error") && length(lnd) == 1L && grepl(" n_jump=0 ", lnd) && grepl("fallback=nojump$", lnd)) ok(sprintf("d1 점프일 0 → 낙하가 진단 줄에 남는다('%s')", lnd)) else ng("d1 낙하 기록", paste(c(if (inherits(vd, "error")) conditionMessage(vd), qd$out), collapse = " | "))
if (!inherits(vd, "error")) {
  wd <- vd / sum(vd); wed <- ERC$erc_weights_mrt2010(stats::cov(XG))$w
  if (max(abs(wd - wed[names(wd)])) < 1e-6) ok(sprintf("d2 해 = 변동성 ERC(최대차 %.1e)", max(abs(wd - wed[names(wd)])))) else ng("d2 변동성 ERC 와 다르다", sprintf("%.2e", max(abs(wd - wed[names(wd)]))))
  if (max(abs(wd - 1 / length(wd))) > 0.01) ok(sprintf("d3 EW 와 구별(최대 편차 %.3f)", max(abs(wd - 1 / length(wd))))) else ng("d3 EW 퇴화")
}
p2 <- .ex2(); S2g <- E0$.skrp_rb(modifyList(p2, list(mu = rep(0, 3), lam = 0)), rep(1 / 3, 3))
eg <- ERC$erc_weights_mrt2010(p2$Sig)$w
if (max(abs(S2g$y / sum(S2g$y) - eg)) < 1e-8) ok(sprintf("d4 λ = 0 · μ = 0 → 변동성 ERC(논문 예 2 Σ · 차 %.1e · 표 60.94/22.20/16.87 = %s)", max(abs(S2g$y / sum(S2g$y) - eg)), paste(sprintf("%.2f", 100 * eg), collapse = "/"))) else
  ng("d4 가우시안 μ = 0 해가 변동성 ERC 와 다르다")
if (all(abs(100 * eg - c(60.94, 22.20, 16.87)) < 0.006)) ok("d5 ERC 선례 어댑터 = 논문 표 tab:example2-1(60.94/22.20/16.87)") else ng("d5 ERC 선례가 논문 표와 다르다", paste(round(100 * eg, 2), collapse = "/"))
## d6 — 같은 점프 자료라도 점프 성분을 끄면(λ = 0) 점프 종목 비중이 다시 오른다(점프 성분이 c2 의 원인)
estJ <- E0$.skrp_estimate(XJ); nJ <- ncol(XJ)
xJ1 <- E0$.skrp_rb(list(mu = rep(0, nJ), Sig = estJ$Sig, muJ = estJ$muJ, SigJ = estJ$SigJ, lam = estJ$lam, alpha = .99), rep(1 / nJ, nJ)); xJ0 <- E0$.skrp_rb(list(mu = rep(0, nJ), Sig = estJ$Sig, muJ = rep(0, nJ), SigJ = matrix(0, nJ, nJ), lam = 0, alpha = .99), rep(1 / nJ, nJ))
aJ <- grepl("^J", colnames(XJ))
if (sum((xJ0$y / sum(xJ0$y))[aJ]) > sum((xJ1$y / sum(xJ1$y))[aJ])) ok(sprintf("d6 점프 성분 끔(정상 국면 Σ 만) → 점프 종목 합 %.3f > 켬 %.3f", sum((xJ0$y / sum(xJ0$y))[aJ]), sum((xJ1$y / sum(xJ1$y))[aJ]))) else ng("d6 점프 성분 효과 방향")

cat("\n=== e. 결정성 · 비음 · 이름 · 치환 불변 · 래퍼 · PIT ===\n")
ctxJ <- mkctx(XJ)
r1 <- quiet(E0$method_weights(ctxJ))$v; r2 <- quiet(E0$method_weights(ctxJ))$v
if (identical(r1, r2)) ok("e1 결정성(같은 입력 → 비트 동일 출력)") else ng("e1 비결정")
if (all(is.finite(r1)) && all(r1 > 0)) ok(sprintf("e2 비음(최소 %.3g · 양수 선호)", min(r1))) else ng("e2 음수 · 비유한")
if (identical(names(r1), ctxJ$assets)) ok("e3 이름 = ctx$assets(순서 그대로)") else ng("e3 이름 보존", paste(names(r1), collapse = ","))
set.seed(3L); perm <- sample(ncol(XJ)); XP <- XJ[, perm]
rp <- quiet(E0$method_weights(mkctx(XP)))$v
if (!inherits(rp, "error") && max(abs(rp[names(r1)] / sum(rp) - r1 / sum(r1))) < 1e-8) ok(sprintf("e4 자산 순서 치환 불변(차 %.1e)", max(abs(rp[names(r1)] / sum(rp) - r1 / sum(r1))))) else ng("e4 치환 불변")
rg1 <- quiet(E0$method_weights(mkctx(XG)))$v; XGp <- XG[, rev(seq_len(ncol(XG)))]; rg2 <- quiet(E0$method_weights(mkctx(XGp)))$v
if (max(abs(rg2[names(rg1)] / sum(rg2) - rg1 / sum(rg1))) < 1e-8) ok("e5 치환 불변(점프 없는 자료 · 역순)") else ng("e5 치환 불변(가우시안)")
W <- wrap_adapter(E0$method_weights, "SkewRPBKR2022")
qw <- quiet(W(ctxJ)); ww <- qw$v
if (!inherits(ww, "error") && abs(sum(ww) - 1) < 1e-9 && all(ww >= 0) && !any(grepl("어댑터 실패", qw$out, fixed = TRUE)) && max(abs(ww - r1 / sum(r1))) < 1e-12)
  ok("e6 운영 래퍼(wrap_adapter) 통과 — Σw = 1 · 롱온리 · 폴백 없음 · 해 그대로") else ng("e6 래퍼", paste(qw$out, collapse = " | "))
## e7 — 실패는 이름을 부르고 EW(표준편차 0 종목)
Xz <- XG; Xz[, 2] <- 0; qz <- quiet(W(mkctx(Xz)))
if (!inherits(qz$v, "error") && max(abs(qz$v - 1 / ncol(Xz))) < 1e-12 && any(grepl("어댑터 실패", qz$out, fixed = TRUE))) ok("e7 분산 0 종목 → 래퍼가 이름을 부르고 EW 폴백") else ng("e7 폴백 호명", paste(qz$out, collapse = "|"))
src <- paste(sub("#.*$", "", readLines(file.path(ROOT, AD), warn = FALSE, encoding = "UTF-8")), collapse = "\n")
bad <- c("read", "fread", "load", "Sys.Date", "Sys.time", "file.path", "get(", "<<-", "set.seed", "runif", "rnorm", "sample(")
hit <- bad[vapply(bad, function(b) grepl(b, src, fixed = TRUE), logical(1))]
if (!length(hit)) ok("e8 어댑터 코드에 파일 · 시각 · 전역 · 난수 접근 없음") else ng("e8 ctx 밖 접근 · 난수 의심", paste(hit, collapse = ","))
lnJ <- grep("^\\[skrp\\] ", quiet(E0$method_weights(ctxJ))$out, value = TRUE)
pat <- "^\\[skrp\\] d=2015-06-30 n=20 n_jump=[0-9]+ pi=[0-9.]+ es=[0-9.]+ iters=[0-9]+ fallback=(none|nojump|estfail|noexist|solver)$"
if (length(lnJ) == 1L && grepl(pat, lnJ)) ok(sprintf("e9 진단 줄 형식 '%s'", lnJ)) else ng("e9 진단 줄", paste(lnJ, collapse = " | "))

cat("\n=== f. 돌연변이(소스 텍스트 치환 · 정확히 한 곳) ===\n")
src_ad <- paste(readLines(file.path(ROOT, AD), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
count_fixed <- function(pat, s) { g <- gregexpr(pat, s, fixed = TRUE)[[1]]; if (g[1] == -1L) 0L else length(g) }
MUT <- list(
  list(id = "M1 ES φ 의 기대수익 항 부호(− → +)", from = "- b / (1 - alpha) * stats::pnorm(-(a + b) / c)", to = "+ b / (1 - alpha) * stats::pnorm(-(a + b) / c)", grp = "a", fn = group_a),
  list(id = "M2 δ₁ 의 점프 평균 부호(− μ̃ → + μ̃)", from = "w2 * (h2 / s2 * S2x - par$muJ)", to = "w2 * (h2 / s2 * S2x + par$muJ)", grp = "b", fn = group_b),
  list(id = "M3 점프 강도 λ = 0(점프 성분 끔)", from = "out$lam <- nj / Tn", to = "out$lam <- 0 * nj / Tn", grp = "c", fn = group_c)
)
for (m in MUT) {
  k <- count_fixed(m$from, src_ad)
  if (k != 1L) { ng(sprintf("%s 주입 실패 — 대상 텍스트 %d곳(정확히 1곳이어야)", m$id, k)); next }
  mut <- sub(m$from, m$to, src_ad, fixed = TRUE)
  if (count_fixed(m$from, mut) != 0L || count_fixed(m$to, mut) != 1L) { ng(sprintf("%s 치환 미성사", m$id)); next }
  Em <- tryCatch(load_adapter(mut), error = function(e) e)
  if (inherits(Em, "error")) { ng(sprintf("%s 사본이 적재되지 않는다 — 대조 무효", m$id), conditionMessage(Em)); next }
  rm0 <- quiet(Em$method_weights(mkctx(XJ)))$v
  if (inherits(rm0, "error") || !is.numeric(rm0) || length(rm0) != ncol(XJ)) { ng(sprintf("%s 사본이 단독으로 안 돈다 — 대조 무효", m$id), if (inherits(rm0, "error")) conditionMessage(rm0) else class(rm0)); next }
  res <- quiet(m$fn(Em))$v
  nf <- if (inherits(res, "error")) NA_integer_ else sum(vapply(res, function(z) !identical(z[1], "TRUE"), logical(1)))
  if (!is.na(nf) && nf >= 1L) ok(sprintf("%s → 사본이 묶음 %s 에서 %d/%d 항목 실패(검출)", m$id, m$grp, nf, length(res))) else
    ng(sprintf("%s 를 묶음 %s 가 못 잡는다", m$id, m$grp), if (inherits(res, "error")) conditionMessage(res) else "전 항목 통과")
}

cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
cat(sprintf('{"test":"skew_rp_bkr_2022","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL > 0L) 1L else 0L)
