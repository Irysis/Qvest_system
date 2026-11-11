#!/usr/bin/env Rscript
#==============================================================================
# test_isotropic_corr_cov.R — 등방 상관 공분산 추정기(arXiv 2411.08864 Giller 2024 · 2026-11-11)
#
# 합성 자료만 쓴다(실자료 · 성과 파일 없음). 실패가 하나라도 있으면 종료 코드 1.
#   (a)  참 등방 모형(등분산 · 고정 시드)에서 ρ̂ 가 참값 ±0.012 안
#   (a2) 이분산 등방 모형에서 ρ̂(표준화 수익 판 = 평균 상관)는 참 ρ 에 · 진단 rho_nstar_raw(원자료 §2.3 식)는
#        편의 목표 ρ·((Σσ)²−Σσ²)/((N−1)Σσ²)(< ρ) 에 맞는다
#   (a3) 항등 검산 — 표준화 수익 행렬에 §2.3 식을 직접 계산한 값 = ρ̂(1e-12 이내)
#   (b)  고유값 구조: 1 + (N−1)ρ̂ 한 개(고유벡터 ∝ 1) · 1 − ρ̂ 가 N−1 개(§1.7 · 부록 Theorem eigen) · G⁻¹ 닫힌 식(§3.1)
#   (c)  대칭 · 양정치 · dimnames · 대각 = 표본분산
#   (d)  일반 자료에서 표본공분산과 구별(상대 편차 > 1e-8)
#   (e)  평균-분산 닫힌 해 식 (mvoiso) = solve(Σ, μ)(λ = 1/2 이면 상수까지 같다 · 비례로 단정)
#   (f)  허용 범위 밖(ρ̂ = 1 · ρ̂ = −1/(N−1)) · 결측 · 분산 0 · N < 2 · 열 이름 없음 → 표본공분산을 돌려주지 않고 stop(이름을 부른다)
#   (g)  결정성 · 자산 순서 치환 불변
#   (h)  돌연변이(소스 텍스트 치환 · 정확히 한 곳) — 사본은 위 묶음을 통과하지 못한다
#   (i)  독립성 · PIT: source · 파일 읽기 · 시각 · 난수 호출 없음
#==============================================================================
.find_root <- function() {
  fa <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
  cand <- c(if (length(fa)) normalizePath(file.path(dirname(fa[1]), "..", ".."), winslash = "/", mustWork = FALSE),
            Sys.getenv("QM_ROOT", ""), getwd())
  for (r in cand) if (nzchar(r) && file.exists(file.path(r, "02_Infrastructure/portfolio/isotropic_corr_cov.R"))) return(r)
  stop("루트를 찾지 못했다 — 저장소 루트에서 실행할 것")
}
ROOT <- .find_root()
SRC_PATH <- file.path(ROOT, "02_Infrastructure/portfolio/isotropic_corr_cov.R")
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat(sprintf("  OK   %s\n", m)) }
ng <- function(m, d = "") { FAIL <<- FAIL + 1L; cat(sprintf("  FAIL %s%s\n", m, if (nzchar(d)) paste0(" — ", d) else "")) }

SRC <- paste(readLines(SRC_PATH, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
load_env <- function(txt) { e <- new.env(parent = baseenv()); eval(parse(text = txt, encoding = "UTF-8"), envir = e); e }
E <- load_env(SRC)

## 합성 등방 패널: r_it = σ_i (√ρ m_t + √(1−ρ) e_it) — 상관 = ρ(모든 쌍) · 분산 = σ_i²
iso_panel <- function(N, TT, rho, sig, seed) {
  set.seed(seed)
  m <- rnorm(TT); Z <- matrix(rnorm(TT * N), TT, N)
  X <- (sqrt(rho) * m + sqrt(1 - rho) * Z) %*% diag(sig, N)
  colnames(X) <- sprintf("A%02d", seq_len(N)); X
}
## 일반 패널: 2요인 + 이질 잡음(등방 아님)
gen_panel <- function(N = 12L, TT = 252L, seed = 3L) {
  set.seed(seed)
  f <- matrix(rnorm(TT * 2, 0, 0.01), TT, 2); B <- matrix(runif(N * 2, -0.5, 1.5), N, 2)
  X <- f %*% t(B) + matrix(rnorm(TT * N), TT, N) %*% diag(seq(0.005, 0.03, length.out = N))
  colnames(X) <- sprintf("G%02d", seq_len(N)); X
}

RHO0 <- 0.30; N0 <- 10L
X_hom <- iso_panel(N0, 20000L, RHO0, rep(0.015, N0), seed = 11L)
SIG_HET <- seq(0.005, 0.040, length.out = N0)
X_het <- iso_panel(N0, 20000L, RHO0, SIG_HET, seed = 12L)
X_gen <- gen_panel()

err_of <- function(expr) tryCatch({ v <- expr; if (is.matrix(v)) "RETURNED_MATRIX" else "RETURNED_OTHER" },
                                  error = function(e) conditionMessage(e))

## 시험 묶음 — 함수 f 를 받아 이름 붙은 논리 벡터와 서술을 낸다(돌연변이 사본에도 같은 묶음을 돌린다)
suite <- function(f) {
  res <- list()
  put <- function(id, pass, msg) res[[id]] <<- list(pass = isTRUE(pass), msg = msg)
  safe <- function(expr) tryCatch(expr, error = function(e) e)

  ## (a)
  Sa <- safe(f(X_hom))
  ra <- if (is.matrix(Sa)) attr(Sa, "iso_diag")$rho else NA_real_
  put("a", is.finite(ra) && abs(ra - RHO0) < 0.012, sprintf("(a) 등분산 등방 ρ = %.2f → ρ̂ = %.4f(허용 ±0.012 · N = %d · T = 20000)", RHO0, ra, N0))

  ## (a2) 이분산: 본 추정 ρ̂ 는 참 ρ 에 · 원자료 판 rho_nstar_raw 는 편의 목표에
  tgt <- RHO0 * (sum(SIG_HET)^2 - sum(SIG_HET^2)) / ((N0 - 1) * sum(SIG_HET^2))
  Sh <- safe(f(X_het))
  rh <- if (is.matrix(Sh)) attr(Sh, "iso_diag")$rho else NA_real_
  rr <- if (is.matrix(Sh)) attr(Sh, "iso_diag")$rho_nstar_raw else NA_real_
  put("a2", is.finite(rh) && abs(rh - RHO0) < 0.012 && isTRUE(is.finite(rr)) && abs(rr - tgt) < 0.012 && (RHO0 - tgt) > 0.03,
      sprintf("(a2) 이분산 등방 ρ = %.2f → ρ̂ = %.4f(허용 ±0.012) · 진단 rho_nstar_raw = %.4f ≈ 편의 목표 %.4f(편의 %.4f)",
              RHO0, rh, rr, tgt, RHO0 - tgt))

  ## (a3) 항등 검산: 표준화 수익 u = r/σ̂ 에 §2.3 식을 직접 계산한 값 = ρ̂(1e-12)
  id_one <- function(X) {
    U <- sweep(sweep(X, 2L, colMeans(X)), 2L, apply(X, 2L, stats::sd), "/")
    SU <- stats::cov(U); n <- ncol(X)
    Ns <- n * (sum(diag(SU)) / n^2) / (sum(SU) / n^2)
    (n - Ns) / ((n - 1) * Ns)
  }
  ids <- vapply(list(X_gen, X_het, X_hom), function(X) {
    S <- safe(f(X)); if (is.matrix(S)) abs(attr(S, "iso_diag")$rho - id_one(X)) else Inf }, numeric(1))
  put("a3", all(ids < 1e-12), sprintf("(a3) 표준화 수익 §2.3 식 = ρ̂ 항등(최대 차 %.2e · 3 패널)", max(ids)))

  ## (b) 고유값 구조 · G⁻¹ 닫힌 식
  Sg <- safe(f(X_gen))
  if (is.matrix(Sg)) {
    rg <- attr(Sg, "iso_diag")$rho; n <- ncol(Sg)
    Cg <- stats::cov2cor(Sg); eg <- eigen(Cg, symmetric = TRUE)
    top_ok <- abs(eg$values[1] - (1 + (n - 1) * rg)) < 1e-10
    res_ok <- max(abs(eg$values[-1] - (1 - rg))) < 1e-10
    v1 <- eg$vectors[, 1] * sign(eg$vectors[1, 1]); vec_ok <- max(abs(v1 - 1 / sqrt(n))) < 1e-8
    Ginv <- diag(n) / (1 - rg) - rg * matrix(1, n, n) / ((1 - rg) * (1 + (n - 1) * rg))
    inv_ok <- max(abs(Ginv - solve(Cg))) / max(abs(Ginv)) < 1e-10
    dg_ok <- isTRUE(all.equal(unname(attr(Sg, "iso_diag")$eig_corr), c(1 + (n - 1) * rg, 1 - rg), tolerance = 1e-12))
    put("b", top_ok && res_ok && vec_ok && inv_ok && dg_ok,
        sprintf("(b) 고유값 %.4f = 1+(N−1)ρ̂ · 나머지 %d개 = 1−ρ̂ = %.4f · 고유벡터 ∝ 1 · G⁻¹ 닫힌 식(top %s res %s vec %s inv %s diag %s)",
                eg$values[1], n - 1, 1 - rg, top_ok, res_ok, vec_ok, inv_ok, dg_ok))
  } else put("b", FALSE, paste("(b) 추정 실패:", conditionMessage(Sg)))

  ## (c)
  if (is.matrix(Sg)) {
    S0 <- stats::cov(X_gen)
    sym <- identical(Sg, t(Sg)) || isTRUE(all.equal(Sg, t(Sg), tolerance = 0))
    pd <- min(eigen(Sg, symmetric = TRUE, only.values = TRUE)$values) > 0
    dn <- identical(dimnames(Sg), list(colnames(X_gen), colnames(X_gen)))
    dv <- identical(unname(diag(Sg)), unname(diag(S0)))
    put("c", sym && pd && dn && dv, sprintf("(c) 대칭 %s · 양정치 %s · dimnames %s · 대각 = 표본분산(비트 동일) %s", sym, pd, dn, dv))
  } else put("c", FALSE, "(c) 추정 실패")

  ## (d)
  if (is.matrix(Sg)) {
    S0 <- stats::cov(X_gen); dev <- max(abs(Sg - S0)) / max(abs(S0))
    put("d", dev > 1e-8, sprintf("(d) 일반 자료에서 표본공분산과 상대 편차 %.3e(> 1e-8)", dev))
  } else put("d", FALSE, "(d) 추정 실패")

  ## (e) 식 (mvoiso) — ĥ = S⁻¹/(2λ(1−ρ)) {z − Nρ z̄ 1/(1+(N−1)ρ)} · λ = 1/2
  if (is.matrix(Sg)) {
    set.seed(21L); n <- ncol(Sg); mu <- rnorm(n, 0.0005, 0.001)
    rg <- attr(Sg, "iso_diag")$rho; sg <- sqrt(diag(Sg)); z <- mu / sg
    h_cf <- (1 / sg) / (1 - rg) * (z - n * rg * mean(z) / (1 + (n - 1) * rg))
    h_num <- solve(Sg, mu)
    cst <- sum(h_num * h_cf) / sum(h_cf^2)
    prop <- max(abs(h_num - cst * h_cf)) / max(abs(h_num))
    put("e", prop < 1e-8 && abs(cst - 1) < 1e-8,
        sprintf("(e) 닫힌 해 (mvoiso) ∝ solve(Σ, μ)(비례 잔차 %.2e · 상수 %.10f)", prop, cst))
  } else put("e", FALSE, "(e) 추정 실패")

  ## (f) 멈춤 — 표본공분산을 돌려주지 않는다
  Xid <- X_gen[, 1:4]; Xid[, 2:4] <- Xid[, 1] %o% c(2, 0.5, 3)                 # 척도만 다른 같은 열 → ρ̂ = 1(상한 끝점)
  m1 <- err_of(f(Xid))
  Xsz <- X_gen[, 1:2]; Xsz[, 2] <- -2 * Xsz[, 1]                               # 완전 역상관 → ρ̂ = −1 = −1/(N−1)(하한 끝점)
  m2 <- err_of(f(Xsz))
  Xna <- X_gen; Xna[5, "G07"] <- NA
  m3 <- err_of(f(Xna))
  Xzv <- X_gen; Xzv[, "G03"] <- 0.001
  m4 <- err_of(f(Xzv))
  m5 <- err_of(f(X_gen[, 1, drop = FALSE]))
  Xnn <- X_gen; colnames(Xnn) <- NULL
  m6 <- err_of(f(Xnn))
  f_ok <- grepl("허용 범위", m1, fixed = TRUE) && grepl("허용 범위", m2, fixed = TRUE) &&
          grepl("G07", m3, fixed = TRUE) && grepl("결측", m3, fixed = TRUE) &&
          grepl("G03", m4, fixed = TRUE) && grepl("분산 0", m4, fixed = TRUE) &&
          grepl("2종 이상", m5, fixed = TRUE) && grepl("열 이름", m6, fixed = TRUE)
  put("f", f_ok, sprintf("(f) 멈춤 호명 — ρ̂=1: [%s] · 하한: [%s] · 결측: [%s] · 분산0: [%s] · N<2: [%s] · 이름없음: [%s]",
                         substr(m1, 1, 60), substr(m2, 1, 60), substr(m3, 1, 60), substr(m4, 1, 60), substr(m5, 1, 50), substr(m6, 1, 50)))

  ## (g) 결정성 · 치환 불변
  if (is.matrix(Sg)) {
    det_ok <- identical(Sg, f(X_gen))
    p <- c(7L, 2L, 12L, 1L, 5L, 9L, 3L, 11L, 4L, 10L, 6L, 8L)
    Sp <- safe(f(X_gen[, p]))
    perm_ok <- is.matrix(Sp) && identical(dimnames(Sp), dimnames(Sg[p, p])) &&
               max(abs(Sp - Sg[p, p])) / max(abs(Sg)) < 1e-12 &&
               abs(attr(Sp, "iso_diag")$rho - attr(Sg, "iso_diag")$rho) < 1e-12
    put("g", det_ok && perm_ok, sprintf("(g) 결정성 %s · 자산 순서 치환 불변 %s", det_ok, perm_ok))
  } else put("g", FALSE, "(g) 추정 실패")
  res
}

report <- function(res) for (r in res) if (r$pass) ok(r$msg) else ng(r$msg)
all_pass <- function(res) all(vapply(res, function(r) r$pass, logical(1)))

cat("=== (a)~(g) 본 구현 ===\n")
R0 <- suite(E$isotropic_corr_cov)
report(R0)

cat("\n=== (h) 돌연변이(소스 텍스트 치환 · 정확히 한 곳) ===\n")
mutate <- function(id, from, to, expect) {
  hits <- gregexpr(from, SRC, fixed = TRUE)[[1]]
  nh <- if (hits[1] == -1L) 0L else length(hits)
  if (nh != 1L) { ng(sprintf("(h-%s) 치환 대상이 정확히 한 곳이 아니다(%d곳) — 재조준", id, nh)); return(invisible()) }
  mut <- sub(from, to, SRC, fixed = TRUE)
  if (grepl(from, mut, fixed = TRUE) || !grepl(to, mut, fixed = TRUE)) { ng(sprintf("(h-%s) 치환이 일어나지 않았다", id)); return(invisible()) }
  Em <- tryCatch(load_env(mut), error = function(e) e)
  if (inherits(Em, "error")) { ng(sprintf("(h-%s) 사본이 해석되지 않는다 — 대조 무효", id), conditionMessage(Em)); return(invisible()) }
  Rm <- suite(Em$isotropic_corr_cov)
  failed <- names(Rm)[!vapply(Rm, function(r) r$pass, logical(1))]
  if (length(failed) && all(expect %in% failed))
    ok(sprintf("(h-%s) 돌연변이 사본이 묶음을 통과하지 못한다 — 붉어진 항목 %s", id, paste(failed, collapse = ",")))
  else ng(sprintf("(h-%s) 돌연변이를 못 잡는다", id), sprintf("붉어진 항목 [%s] · 기대 [%s]", paste(failed, collapse = ","), paste(expect, collapse = ",")))
}
## h1 — 본 추정을 원자료 §2.3 식(구판 · 이분산 편의)으로 되돌림
mutate("1", "rho <- mean(Cs[upper.tri(Cs)])", "rho <- rho_nstar_raw", expect = c("a2", "a3"))
## h4 — 쌍 평균에 대각(1)을 섞음(평균 상관의 오기)
mutate("4", "upper.tri(Cs)", "upper.tri(Cs, diag = TRUE)", expect = c("a", "a3"))
## h2 — 허용 범위 판정 무력화(경계 stop 제거)
mutate("2", "!(lam_mkt > ISO_EIG_TOL && lam_res > ISO_EIG_TOL)", "FALSE", expect = "f")
## h3 — 조용한 낙하: 반환을 표본공분산으로 바꿔치기
mutate("3", "  diag(S) <- v                              # [구현 ⑤]", "  S <- S0                                   # [구현 ⑤]", expect = c("b", "d"))

cat("\n=== (i) 독립성 · PIT(소스 정적 검사 · 주석 제외) ===\n")
code <- paste(sub("#.*$", "", strsplit(SRC, "\n", fixed = TRUE)[[1]]), collapse = "\n")
bad <- c("source(", "sys.source", "read", "load(", "file", "Sys.time", "Sys.Date", "set.seed", "rnorm", "runif", "sample(", "<<-", "library(", "require(")
hit <- bad[vapply(bad, function(b) grepl(b, code, fixed = TRUE), logical(1))]
if (!length(hit)) ok("(i) source · 파일 · 시각 · 난수 · 전역 쓰기 · 패키지 적재 없음") else ng("(i) 금지 호출", paste(hit, collapse = ","))

cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
cat(sprintf('{"test":"isotropic_corr_cov","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL > 0L) 1L else 0L)
