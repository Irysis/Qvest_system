#!/usr/bin/env Rscript
#==============================================================================
# test_p3r03_adapters.R — P3R03 원문 충실 구성 어댑터 5종(2026-10-16) — 원문 대조 검사(등록 검증만으로는 충실도를 못 가린다 · Superfan C-20261016-006)
#
#   H. HRP(López de Prado 2016): 논문 예제 1·2 의 d · d̃ 수치 재현 · 예제 3 첫 병합 (1,2) · 대각 공분산 → IVP(해석해) · 준대각화 = 원문 getQuasiDiag
#      직역(판다스 색인 두 배 루프)과 일치 · 연결법 뮤테이션(single → ward.D2 사본은 결과가 바뀐다 = 연결법이 실제로 쓰인다)
#   N. NCO(López de Prado 2019): KDE 정의식 · 순수 잡음 → MP σ² ≈ 1 · nFacts 소수 · 요인 심은 자료 → nFacts ≥ 1 · 잡음 제거 상관 = 단위 대각 · 양정치 ·
#      대각합 n · 블록 3개 → 군집이 블록을 되찾음 · 같은 블록 3개 → 블록 비중 1/3 · 결정성 · 전역 난수 무접촉
#   M. Michaud: 2자산 롱온리 최소분산 해석해 · 비중 = 모의 최소분산 평균(합 1 · 비음) · 결정성 · 전역 난수 무접촉 · mcse 기록 · 등분산 독립 → EW 근처
#   C. CVaR LP(Rockafellar-Uryasev 2000): LP 목적값 = 해의 CVaR_β(정의식 직접 계산) · 2자산 격자 최적 이하 · β 0.95
#   E. ERC(Maillard-Roncalli-Teïletche 2010): 위험 기여 균등 · 기존 erc_weights(같은 순환 좌표 하강)와 일치 · 대각 → 역변동성 · 2자산 = 역변동성
#   W. 운영 래퍼(wrap_adapter) 경유 — 롱온리 · Σw = 1 · EW 와 구별 · 진단 줄 · 어댑터가 ctx 밖(파일 · 날짜 · 전역 데이터)을 읽지 않는다
#==============================================================================
suppressMessages({ library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat(sprintf("  OK   %s\n", m)) }
ng <- function(m, d = "") { FAIL <<- FAIL + 1L; cat(sprintf("  FAIL %s%s\n", m, if (nzchar(d)) paste0(" — ", d) else "")) }
chk <- function(cond, m, d = "") if (isTRUE(cond)) ok(m) else ng(m, d)
ADIR <- file.path(ROOT, "02_Infrastructure/methods/adapters")
load_ad <- function(f) { e <- new.env(parent = globalenv()); sys.source(file.path(ADIR, f), envir = e); e }
H <- load_ad("hrp_lopez_de_prado_2016.R"); N <- load_ad("nco_lopez_de_prado_2019.R"); M <- load_ad("michaud_resampled_minvar.R")
C <- load_ad("cvar_lp_rockafellar_uryasev_2000.R"); E <- load_ad("erc_maillard_roncalli_teiletche_2010.R")
suppressMessages(source(file.path(ROOT, "02_Infrastructure/methods/method_registry.R")))
suppressMessages(source(file.path(ROOT, "02_Infrastructure/portfolio/strategy_tilt_weights.R")))

.panel <- function(n = 20L, T = 252L, seed = 7L) {
  set.seed(seed)
  m <- rnorm(T, 0, 0.012); g1 <- rnorm(T, 0, 0.008); g2 <- rnorm(T, 0, 0.008); sv <- seq(0.006, 0.030, length.out = n)
  b <- runif(n, 0.6, 1.4); grp <- rep(1:2, length.out = n)
  X <- sapply(seq_len(n), function(j) b[j] * m + (if (grp[j] == 1L) g1 else g2) + rnorm(T, 0, sv[j]))
  colnames(X) <- sprintf("T%02d", seq_len(n)); X
}
X <- .panel()
ctx <- list(R = X, assets = colnames(X), mu = setNames(rep(0, ncol(X)), colnames(X)), Sigma = stats::cov(X), ub = 1,
            lookback_days = 252L, decision_date = as.Date("2010-01-29"))

cat("=== H. HRP ===\n")
rho <- matrix(c(1, .7, .2, .7, 1, -.2, .2, -.2, 1), 3)
Lx <- H$.hrp_linkage(rho)
d_paper <- matrix(c(0, .3873, .6325, .3873, 0, .7746, .6325, .7746, 0), 3)
dt_paper <- matrix(c(0, .5659, .9747, .5659, 0, 1.1225, .9747, 1.1225, 0), 3)
chk(max(abs(sqrt(pmax((1 - rho) / 2, 0)) - d_paper)) < 1e-4, "H1 예제 1 — 상관 거리 d 재현(.3873 · .6325 · .7746)")
chk(max(abs(Lx$dtilde - dt_paper)) < 1e-4, "H2 예제 2 — 거리의 거리 d̃ 재현(.5659 · .9747 · 1.1225)", paste(round(Lx$dtilde, 4), collapse = ","))
chk(identical(as.integer(Lx$Z[1, ]), c(0L, 1L)) && abs(Lx$height[1] - .5659) < 1e-4, "H3 예제 3 — 첫 병합 u[1] = (1,2) · 거리 .5659")
set.seed(11); sv <- runif(9, 0.01, 0.04); Sd <- diag(sv^2); ordr <- sample(9)
w_hrp_d <- H$.hrp_rec_bipart(Sd, ordr); w_d <- numeric(9); w_d[as.integer(names(w_hrp_d))] <- w_hrp_d
ivp <- (1 / sv^2) / sum(1 / sv^2)
chk(max(abs(w_d - ivp)) < 1e-12, "H4 대각 공분산 → HRP = 역분산(IVP) — 해석해(정렬 순서와 무관)")
## 원문 getQuasiDiag 직역(판다스: 색인 0,2,4… 로 벌리고 군집 자리에 item1 · i+1 자리에 item2 를 넣은 뒤 색인 정렬)
quasi_ref <- function(Z, n) {
  s <- data.frame(idx = c(0, 1), v = c(Z[nrow(Z), 1], Z[nrow(Z), 2]))
  while (max(s$v) >= n) {
    s$idx <- seq(0, 2 * nrow(s) - 1, by = 2)
    cl <- which(s$v >= n); j <- s$v[cl] - n + 1
    add <- data.frame(idx = s$idx[cl] + 1, v = Z[j, 2])
    s$v[cl] <- Z[j, 1]
    s <- rbind(s, add); s <- s[order(s$idx), ]
  }
  s$v + 1L
}
Lp <- H$.hrp_linkage(stats::cor(X))
chk(identical(as.integer(H$.hrp_quasi_diag(Lp)), as.integer(quasi_ref(Lp$Z, Lp$n))), "H5 준대각화 = 원문 getQuasiDiag 직역과 일치(20종 패널)")
w_h <- H$hrp_weights_ldp2016(X)
chk(all(w_h > 0) && abs(sum(w_h) - 1) < 1e-12 && identical(H$hrp_weights_ldp2016(X), w_h), "H6 비중 양수 · 합 1 · 결정성")
src <- readLines(file.path(ADIR, "hrp_lopez_de_prado_2016.R"), warn = FALSE, encoding = "UTF-8")
hit <- which(src == 'HRP_LINKAGE <- "single"   # 원문 부록 A.3 `link=sch.linkage(dist,\'single\')` (SSRN 2708678 p.15-16) — 스윕 아님')
mut <- src; if (length(hit) == 1L) mut[hit] <- 'HRP_LINKAGE <- "ward.D2"'
MT <- tempfile(fileext = ".R"); writeLines(mut, MT, useBytes = TRUE)
Hm <- new.env(parent = globalenv()); sys.source(MT, envir = Hm)
chk(length(hit) == 1L && max(abs(Hm$hrp_weights_ldp2016(X) - w_h)) > 1e-6, "H7 뮤테이션 — 연결법을 ward.D2 로 바꾼 사본은 비중이 달라진다(연결법이 실제로 쓰인다 · 치환 성사)",
    sprintf("hit=%d", length(hit)))

cat("=== N. NCO ===\n")
chk(abs(N$.nco_kde(0, 1, 0) - stats::dnorm(0)) < 1e-12 && abs(N$.nco_kde(c(0, 2), 0.5, 1) - mean(stats::dnorm(c(2, -2))) / 0.5) < 1e-12,
    "N1 가우스 KDE 정의식(밀도 = 평균 φ((x−x_i)/h)/h)")
set.seed(3); Zn <- matrix(rnorm(1000 * 40), 1000, 40)
dn0 <- N$nco_denoise_cov(stats::cov(Zn), q = 1000 / 40)
chk(dn0$var > 0.6 && dn0$nFacts <= 2L, "N2 순수 잡음 → MP σ² 가 1 근처 · 신호 고유값 거의 없음", sprintf("var=%.3f nFacts=%d", dn0$var, dn0$nFacts))
set.seed(4); f <- rnorm(1000); Zf <- sapply(1:40, function(j) 0.8 * f + rnorm(1000))
dn1 <- N$nco_denoise_cov(stats::cov(Zf), q = 1000 / 40)
C1 <- N$.nco_cov2corr(dn1$S)
chk(dn1$nFacts >= 1L && max(abs(diag(C1) - 1)) < 1e-10 && abs(sum(diag(C1)) - 40) < 1e-8 &&
      min(eigen(dn1$S, symmetric = TRUE, only.values = TRUE)$values) > 0, "N3 요인 심은 자료 → nFacts ≥ 1 · 잡음 제거 상관 단위 대각 · 대각합 n · 양정치",
    sprintf("nFacts=%d", dn1$nFacts))
set.seed(5); T5 <- 252; blk <- rep(1:3, each = 4)
g <- matrix(rnorm(T5 * 3), T5, 3); Xb <- sapply(1:12, function(j) g[, blk[j]] + rnorm(T5, 0, 0.35)); colnames(Xb) <- paste0("B", 1:12)
cl <- N$.nco_with_seed(1L, N$nco_cluster_kmeans_base(stats::cor(Xb), max_k = 6L))
part_ok <- all(vapply(1:3, function(b) length(unique(cl$labels[blk == b])) == 1L, logical(1))) && length(unique(cl$labels)) == 3L
chk(part_ok, "N4 블록 3개(종목 12) → 군집이 블록을 되찾는다(실루엣 t 선택 · 상한 n/2 = 6)", paste(cl$labels, collapse = ""))
Sb <- kronecker(diag(3), matrix(0.6, 4, 4) + diag(0.4, 4)) * 1e-4; colnames(Sb) <- rownames(Sb) <- paste0("B", 1:12)
set.seed(6); Xs <- matrix(rnorm(252 * 12), 252, 12) %*% chol(Sb); colnames(Xs) <- paste0("B", 1:12)
rn <- N$nco_weights_ldp2019(Xs, seed = 42L)
bw <- tapply(rn$w, blk, sum)
chk(all(rn$w >= 0) && abs(sum(rn$w) - 1) < 1e-10 && max(abs(bw - 1 / 3)) < 0.15, "N5 같은 모양 블록 3개 → 블록 비중이 고르게(각 ≈ 1/3) · 롱온리 · 합 1",
    paste(round(bw, 3), collapse = ","))
set.seed(99); g0 <- runif(1); set.seed(99); r1 <- N$nco_weights_ldp2019(X, seed = 7L); g1 <- runif(1); r2 <- N$nco_weights_ldp2019(X, seed = 7L)
chk(identical(r1$w, r2$w) && identical(g0, g1), "N6 결정성(같은 시드 같은 비중) · 전역 난수 상태 무접촉")

cat("=== M. Michaud ===\n")
S2 <- matrix(c(0.04, 0.006, 0.006, 0.01), 2)
w2 <- M$.mi_lo_minvar(S2); w1_ana <- (S2[2, 2] - S2[1, 2]) / (S2[1, 1] + S2[2, 2] - 2 * S2[1, 2])
chk(abs(w2[1] - min(max(w1_ana, 0), 1)) < 1e-8, "M1 2자산 롱온리 최소분산 = 해석해", sprintf("%.6f vs %.6f", w2[1], w1_ana))
set.seed(99); g0 <- runif(1); set.seed(99); rm1 <- M$michaud_resampled_minvar(X[, 1:10], seed = 5L, B = 200L); g1 <- runif(1)
rm2 <- M$michaud_resampled_minvar(X[, 1:10], seed = 5L, B = 200L)
chk(identical(rm1$w, rm2$w) && identical(g0, g1) && all(rm1$w >= 0) && abs(sum(rm1$w) - 1) < 1e-10,
    "M2 결정성 · 전역 난수 무접촉 · 비음 · 합 1")
chk(is.finite(rm1$mcse) && rm1$mcse < 0.02, "M3 몬테카를로 표준오차 기록(B = 200 에서 < 0.02)", sprintf("mcse=%.4f", rm1$mcse))
set.seed(8); Xi <- matrix(rnorm(252 * 8, 0, 0.01), 252, 8); colnames(Xi) <- paste0("I", 1:8)
ri <- M$michaud_resampled_minvar(Xi, seed = 1L, B = 300L)
chk(max(abs(ri$w - 1 / 8)) < 0.05, "M4 등분산 독립 자산 → 재표집 평균은 EW 근처(점추정 최소분산보다 덜 쏠림)", paste(round(ri$w, 3), collapse = ","))
w_pt <- M$.mi_lo_minvar(stats::cov(Xi))
chk(1 / sum(ri$w^2) >= 1 / sum(w_pt^2) - 1e-9, "M5 재표집 평균의 유효 종목 수 ≥ 점추정 최소분산(원문 기전 — 추정 오차로 인한 쏠림 완화)",
    sprintf("effn %.2f vs %.2f", 1 / sum(ri$w^2), 1 / sum(w_pt^2)))

cat("=== C. CVaR LP ===\n")
cvar_def <- function(L, beta) { a <- stats::quantile(L, beta, type = 1); grid <- sort(unique(L)); min(vapply(grid, function(al) al + mean(pmax(L - al, 0)) / (1 - beta), numeric(1))) }
rc <- C$cvar_lp_ru2000(X[, 1:8])
Lsol <- -as.numeric(X[, 1:8] %*% rc$w)
chk(abs(rc$cvar - cvar_def(Lsol, 0.95)) < 1e-9, "C1 LP 목적값 = 해의 CVaR_0.95(정리 2 정의식 직접 계산)", sprintf("%.8f vs %.8f", rc$cvar, cvar_def(Lsol, 0.95)))
X2 <- X[, c(1, 20)]; r2c <- C$cvar_lp_ru2000(X2)
grid_best <- min(vapply(seq(0, 1, by = 0.005), function(a) cvar_def(-as.numeric(X2 %*% c(a, 1 - a)), 0.95), numeric(1)))
chk(r2c$cvar <= grid_best + 1e-9, "C2 2자산 — LP 해의 CVaR ≤ 격자(0.5% 간격) 최소", sprintf("%.8f vs %.8f", r2c$cvar, grid_best))
chk(all(rc$w >= 0) && abs(sum(rc$w) - 1) < 1e-10 && identical(C$CVAR_BETA, 0.95) && identical(C$cvar_lp_ru2000(X[, 1:8])$w, rc$w),
    "C3 비음 · 합 1 · β 0.95 · 결정성")

cat("=== E. ERC ===\n")
re <- E$erc_weights_mrt2010(stats::cov(X))
chk(re$rc_dev < 1e-8, "E1 위험 기여 균등(최대 편차 < 1e-8)", sprintf("%.2e", re$rc_dev))
src_env <- new.env(); sys.source(file.path(ROOT, "02_Infrastructure/portfolio/frontier_hrp/dynamic_regime_rp.R"), envir = src_env)
chk(max(abs(re$w - src_env$erc_weights(stats::cov(X))[names(re$w)])) < 1e-7, "E2 기존 erc_weights(같은 순환 좌표 하강)와 일치")
chk(max(abs(E$erc_weights_mrt2010(Sd)$w - (1 / sv) / sum(1 / sv))) < 1e-9, "E3 대각 공분산 → ERC = 역변동성(해석해)")
S2e <- matrix(c(0.04, 0.012, 0.012, 0.01), 2); we2 <- E$erc_weights_mrt2010(S2e)$w
chk(abs(we2[1] - 0.1 / (0.2 + 0.1)) < 1e-9, "E4 2자산 ERC = 역변동성(상관 무관 — 해석해)", sprintf("%.6f", we2[1]))

cat("=== W. 운영 래퍼 경유 · PIT 정적 검사 ===\n")
for (nm in c("hrp_lopez_de_prado_2016.R", "nco_lopez_de_prado_2019.R", "michaud_resampled_minvar.R", "cvar_lp_rockafellar_uryasev_2000.R",
             "erc_maillard_roncalli_teiletche_2010.R")) {
  e <- load_ad(nm); f <- wrap_adapter(get("method_weights", envir = e), nm, ub = 1)
  out <- capture.output(w <- f(ctx))
  diag_ok <- any(grepl("^\\[(hrp|nco|michaud|cvar|erc)\\] d=2010-01-29 n=20", out))
  chk(all(w >= -1e-12) && abs(sum(w) - 1) < 1e-8 && max(abs(w - 1 / 20)) > 1e-3 && diag_ok && !any(grepl("EW 폴백", out)),
      sprintf("W %s — 롱온리 · 합 1 · EW 와 구별 · 진단 줄 · 폴백 없음", nm), paste(head(out, 2), collapse = " / "))
  s <- paste(readLines(file.path(ADIR, nm), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  code <- gsub("#[^\n]*", "", s)
  chk(!grepl("fread|readRDS|read_parquet|open_dataset|load_month_factors|Sys\\.Date|Sys\\.time|file\\.exists|load_rawdata", code),
      sprintf("W %s — ctx 밖을 읽지 않는다(파일 · 시계 · 전역 데이터 접근 없음 · PIT)", nm))
}

cat(sprintf("\n== p3r03_adapters: PASS %d · FAIL %d ==\n", PASS, FAIL))
cat(sprintf('{"test":"p3r03_adapters","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
if (FAIL > 0L) quit(status = 1L)
