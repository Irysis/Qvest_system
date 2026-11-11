#!/usr/bin/env Rscript
#==============================================================================
# test_topological_rp_nka_2026.R — 뿌리 있는 MST 배분기(TRP-MST · arXiv 2604.16773 변형 I · 2026-11-11)
#
# 합성 자료만 쓴다(실자료 · 성과 파일 없음). 실패가 하나라도 있으면 종료 코드 1.
#   A. 손계산 예(자산 5 · 상관행렬 직접 지정 · 나무 구조 상관 = 간선 상관의 경로곱 → 생성 나무 = MST):
#      거미형(허브 A) · 경로형(허브 동률 → 이름 최소) 나무와 비중이 식 eq:alpha · eq:path-product · eq:normalized-weights 손계산과 일치
#      (ρ = 1 운영값 · ρ = 0.5 · ρ = 0 = EW 극한 §6.1 (a))
#   B. 최소 신장 나무 = 전수 탐색 최소 총 거리(n = 5 · 6 · 여러 시드)
#   C. 자산 순서 치환 공변 · 수익 척도 변화(a_i r_i + c_i · a_i > 0) 불변
#   D. 군집을 심은 합성 자료에서 EW 와 다르고 HRP 선례 어댑터와도 다르다
#   E. 결정성 · 비음 · 이름 보존 · 래퍼 경유 · 진단 줄 형식 · ctx 밖 접근 없음
#   F. 돌연변이(소스 텍스트 치환 · 정확히 한 곳) — α 식 변형 사본은 A 를, 최대 신장 나무 사본은 B 를 통과하지 못한다
#==============================================================================
.find_root <- function() {
  for (c in c(Sys.getenv("QM_ROOT"), getwd())) {
    c <- gsub("\\\\", "/", c)
    if (nzchar(c) && file.exists(file.path(c, "02_Infrastructure/methods/method_registry.R"))) return(c)
  }
  stop("저장소 루트를 못 찾았다 — 루트에서 실행하거나 QM_ROOT 를 지정")
}
ROOT <- .find_root(); setwd(ROOT)
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat(sprintf("  OK   %s\n", m)) }
ng <- function(m, d = "") { FAIL <<- FAIL + 1L; cat(sprintf("  FAIL %s%s\n", m, if (nzchar(d)) paste0(" — ", d) else "")) }
quiet <- function(expr) { o <- capture.output(v <- tryCatch(expr, error = function(e) e)); list(v = v, out = o) }

AD <- "02_Infrastructure/methods/adapters/topological_rp_nayar_kulkarni_ainasse_2026.R"
E <- new.env(parent = globalenv()); sys.source(file.path(ROOT, AD), envir = E)
suppressMessages(source(file.path(ROOT, "02_Infrastructure/methods/method_registry.R")))        # wrap_adapter(운영 래퍼)
suppressMessages(source(file.path(ROOT, "02_Infrastructure/portfolio/strategy_tilt_weights.R"))) # 래퍼 의존 normalize_long_only

## 표본 상관이 정확히 C 인 수익 창 — 중심화 · 백색화한 Z(cov = I) × chol(C)
.exact_R <- function(C, T = 252L, seed = 1L, scale = 0.01) {
  set.seed(seed)
  Z <- matrix(rnorm(T * ncol(C)), T); Z <- scale(Z, scale = FALSE)
  Z <- Z %*% solve(chol(stats::cov(Z)))
  R <- (Z %*% chol(C)) * scale
  colnames(R) <- colnames(C); R
}
## 나무 구조 상관: C_ij = 경로 위 간선 상관의 곱(가우스 나무 모형 — 양정치 · 생성 나무가 유일 MST)
.tree_C <- function(nm, edges, rho) {
  n <- length(nm); A <- matrix(0, n, n, dimnames = list(nm, nm))
  for (k in seq_len(nrow(edges))) A[edges[k, 1], edges[k, 2]] <- A[edges[k, 2], edges[k, 1]] <- rho[k]
  C <- diag(n); dimnames(C) <- list(nm, nm)
  for (s in nm) {                       # 너비 우선으로 s 에서의 경로곱
    val <- setNames(rep(NA_real_, n), nm); val[s] <- 1; q <- s
    while (length(q)) { u <- q[1]; q <- q[-1]; for (v in nm[A[u, ] != 0]) if (is.na(val[v])) { val[v] <- val[u] * A[u, v]; q <- c(q, v) } }
    C[s, ] <- val
  }
  C
}
.edge_set <- function(Em) sort(apply(Em, 1L, function(e) paste(sort(e), collapse = "-")))
nm5 <- c("A", "B", "C", "D", "E")

## ── A 판정 함수(돌연변이 F 가 같은 함수를 쓴다) ─────────────────────────────
test_A <- function(env, verbose = TRUE) {
  rep_ <- if (verbose) list(ok = ok, ng = ng) else list(ok = function(m) NULL, ng = function(m, d = "") NULL)
  allok <- TRUE
  chk <- function(cond, m, d = "") { if (isTRUE(cond)) rep_$ok(m) else { rep_$ng(m, d); allok <<- FALSE } }
  ## A1 거미형: A-B .8 · A-C .7 · A-D .6 · D-E .75 → 뿌리 A(차수 3) · b(A)=3 · b(D)=1
  sp_e <- rbind(c("A", "B"), c("A", "C"), c("A", "D"), c("D", "E"))
  Csp <- .tree_C(nm5, sp_e, c(0.8, 0.7, 0.6, 0.75))
  Xsp <- .exact_R(Csp, seed = 3L)
  chk(max(abs(stats::cor(Xsp) - Csp)) < 1e-12, "A0 합성 창의 표본 상관 = 지정 상관(1e-12)")
  r1 <- env$trp_mst_weights(Xsp)
  chk(identical(.edge_set(r1$edges), .edge_set(sp_e)), "A1 거미형 MST = 생성 나무 {A-B, A-C, A-D, D-E}", paste(.edge_set(r1$edges), collapse = ","))
  chk(identical(r1$root, "A") && r1$b[["A"]] == 3L && r1$b[["D"]] == 1L, "A2 hub 뿌리 = A · b(A) = 3 · b(D) = 1", r1$root)
  ## ρ = 1: g = A 1 · B C D 1/3 · E (1/3)(1/1) = 1/3 → Σ = 7/3 → w = A 3/7 · 나머지 1/7
  e1 <- c(A = 3, B = 1, C = 1, D = 1, E = 1) / 7
  chk(max(abs(r1$w - e1)) < 1e-12, "A3 ρ = 1 손계산 w = (3/7, 1/7, 1/7, 1/7, 1/7)", paste(round(r1$w, 6), collapse = ","))
  ## ρ = 0.5: α_A = 0.5 + 0.5/3 = 2/3 · α_D = 0.5 + 0.5/1 = 1 → g = 1 · 2/3 · 2/3 · 2/3 · 2/3 → Σ = 11/3 → w = 3/11 · 2/11 ×4
  r05 <- env$trp_mst_weights(Xsp, rho = 0.5)
  e05 <- c(A = 3, B = 2, C = 2, D = 2, E = 2) / 11
  chk(max(abs(r05$w - e05)) < 1e-12, "A4 ρ = 0.5 손계산 w = (3/11, 2/11 ×4)", paste(round(r05$w, 6), collapse = ","))
  ## ρ = 0 → 정규화된 원 신호 = EW(s ≡ 1 · §6.1 Limit cases (a))
  r0 <- env$trp_mst_weights(Xsp, rho = 0)
  chk(max(abs(r0$w - 0.2)) < 1e-12, "A5 ρ = 0 → EW(§6.1 (a))")
  ## A6 경로형: A-B .8 · B-C .7 · C-D .75 · D-E .65 → 차수 2 동률(B · C · D) → 이름 최소 B
  ##    B 의 자식 A · C(b = 2) · C→D(b = 1) · D→E(b = 1) · ρ = 1: g = B 1 · A ½ · C ½ · D ½ · E ½ → Σ = 3 → B 1/3 · 나머지 1/6
  pa_e <- rbind(c("A", "B"), c("B", "C"), c("C", "D"), c("D", "E"))
  Xpa <- .exact_R(.tree_C(nm5, pa_e, c(0.8, 0.7, 0.75, 0.65)), seed = 4L)
  rp <- env$trp_mst_weights(Xpa)
  chk(identical(.edge_set(rp$edges), .edge_set(pa_e)) && identical(rp$root, "B"), "A6 경로형 MST = 생성 나무 · hub 동률 → 이름 최소 B", rp$root)
  ep <- c(A = 1, B = 2, C = 1, D = 1, E = 1) / 6
  chk(max(abs(rp$w - ep)) < 1e-12, "A7 경로형 ρ = 1 손계산 w = (1/6, 1/3, 1/6, 1/6, 1/6)", paste(round(rp$w, 6), collapse = ","))
  ## A8 깊이: ρ = 0.5 경로형 — α_B = 0.75 · α_C = α_D = 1 → g = B 1 · A C D E 0.75 → w = 1/4 · 3/16 ×4
  rp5 <- env$trp_mst_weights(Xpa, rho = 0.5)
  chk(max(abs(rp5$w - c(A = 3, B = 4, C = 3, D = 3, E = 3) / 16)) < 1e-12, "A8 경로형 ρ = 0.5 손계산 w = (3/16, 1/4, 3/16 ×3)")
  allok
}

## ── B 판정 함수: MST 총 거리 = 전수 탐색 최소 ────────────────────────────────
.brute_min <- function(D) {
  n <- ncol(D); ij <- which(upper.tri(D), arr.ind = TRUE); best <- Inf
  for (cmb in utils::combn(nrow(ij), n - 1L, simplify = FALSE)) {
    par <- seq_len(n); f <- function(x) { while (par[x] != x) x <- par[x]; x }; okc <- TRUE
    for (k in cmb) { a <- f(ij[k, 1]); b <- f(ij[k, 2]); if (a == b) { okc <- FALSE; break }; par[b] <- a }
    if (okc) best <- min(best, sum(D[ij[cmb, , drop = FALSE]]))
  }
  best
}
test_B <- function(env, verbose = TRUE) {
  allok <- TRUE
  for (cfg in list(c(5, 11), c(5, 12), c(6, 13), c(6, 14), c(6, 15))) {
    n <- cfg[1]; set.seed(cfg[2])
    f <- rnorm(252); X <- sapply(seq_len(n), function(j) runif(1, 0.2, 1.5) * f + rnorm(252)); colnames(X) <- sprintf("Z%02d", seq_len(n))
    D <- env$.trp_distance(X); Em <- env$.trp_mst(D)
    tot <- sum(apply(Em, 1L, function(e) D[e[1], e[2]])); bm <- .brute_min(D)
    good <- nrow(Em) == n - 1L && abs(tot - bm) < 1e-12
    if (verbose) { if (good) ok(sprintf("B n=%d seed=%d MST 총 거리 %.6f = 전수 최소 %.6f", n, cfg[2], tot, bm)) else ng(sprintf("B n=%d seed=%d", n, cfg[2]), sprintf("%.6f vs %.6f", tot, bm)) }
    if (!good) allok <- FALSE
  }
  allok
}

## 군집 패널 — 시장 + 군집 3개(크기 6 · 4 · 2) + 종목 잡음(변동성 이질)
.cluster_panel <- function(T = 252L, seed = 21L) {
  set.seed(seed); m <- rnorm(T, 0, 0.010); g <- lapply(1:3, function(i) rnorm(T, 0, 0.010))
  grp <- c(rep(1, 6), rep(2, 4), rep(3, 2)); n <- length(grp)
  X <- sapply(seq_len(n), function(j) m + g[[grp[j]]] * c(1.2, 1.0, 0.8)[grp[j]] + rnorm(T, 0, runif(1, 0.006, 0.02)))
  colnames(X) <- sprintf("K%02d", seq_len(n)); X
}

cat("=== A. 손계산 예 ===\n");   invisible(test_A(E))
cat("\n=== B. MST = 전수 탐색 ===\n"); invisible(test_B(E))

cat("\n=== C. 치환 공변 · 척도 불변 ===\n")
Xc <- .cluster_panel()
wc <- E$trp_mst_weights(Xc)$w
set.seed(99L); pm <- sample(ncol(Xc))
wp <- E$trp_mst_weights(Xc[, pm])$w
if (identical(names(wp), colnames(Xc)[pm]) && max(abs(wp - wc[names(wp)])) < 1e-12) ok("C1 자산 순서 치환 → 비중이 치환을 따라 움직인다(차 < 1e-12)") else
  ng("C1 치환 공변", sprintf("%.3e", max(abs(wp - wc[names(wp)]))))
rv <- rev(seq_len(ncol(Xc))); wr <- E$trp_mst_weights(Xc[, rv])$w
if (max(abs(wr - wc[names(wr)])) < 1e-12) ok("C2 역순 치환 공변") else ng("C2 역순 치환")
set.seed(7L); av <- runif(ncol(Xc), 0.1, 10); cv <- rnorm(ncol(Xc), 0, 0.01)
Xs <- sweep(sweep(Xc, 2, av, "*"), 2, cv, "+")
ws <- E$trp_mst_weights(Xs)$w
if (max(abs(ws - wc)) < 1e-12) ok("C3 수익 척도 · 위치 변화(a_i r_i + c_i · a_i > 0) 불변 — 상관만 쓰는 식의 함의") else ng("C3 척도 불변", sprintf("%.3e", max(abs(ws - wc))))
ws2 <- E$trp_mst_weights(Xc * 37)$w
if (max(abs(ws2 - wc)) < 1e-12) ok("C4 공통 척도(×37) 불변") else ng("C4 공통 척도")

cat("\n=== D. 군집 자료에서 EW · HRP 와 다르다 ===\n")
W <- wrap_adapter(E$method_weights, "TopoRPNKA2026")
ctx <- list(R = Xc, assets = colnames(Xc), mu = setNames(rep(0, ncol(Xc)), colnames(Xc)), Sigma = stats::cov(Xc),
            ub = 1, lookback_days = 252L, decision_date = as.Date("2010-01-29"))
rw <- quiet(W(ctx)); wt <- rw$v
dev_ew <- max(abs(wt - 1 / length(wt)))
if (dev_ew > 0.01) ok(sprintf("D1 EW 와 구별(최대 편차 %.3f)", dev_ew)) else ng("D1 EW 퇴화", sprintf("%.4f", dev_ew))
EH <- new.env(parent = globalenv()); sys.source(file.path(ROOT, "02_Infrastructure/methods/adapters/hrp_lopez_de_prado_2016.R"), envir = EH)
wh <- quiet(wrap_adapter(EH$method_weights, "HRP_LdP2016")(ctx))$v
dev_h <- max(abs(wt - wh[names(wt)]))
if (dev_h > 0.01) ok(sprintf("D2 HRP(López de Prado 2016) 선례와 구별(최대 편차 %.3f)", dev_h)) else ng("D2 HRP 와 같다", sprintf("%.4f", dev_h))
rt <- E$trp_mst_weights(Xc)
if (rt$w[[rt$root]] == max(rt$w)) ok(sprintf("D3 뿌리(%s) 비중이 최대 — ρ = 1 에서 g_r = 1 ≥ g_v(§13.1 eq:g-bounds)", rt$root)) else ng("D3 뿌리 비중")
dep <- rt$depth[names(rt$w)]
if (all(diff(tapply(rt$w, dep, max)) <= 1e-15)) ok("D4 깊이가 깊을수록 비중 상한이 줄어든다(경로를 따라 감쇠 — [숨은 절] §8.3 ③)") else ng("D4 깊이 감쇠")

cat("\n=== E. 결정성 · 비음 · 이름 · 진단 줄 · ctx 밖 접근 ===\n")
r1 <- quiet(E$method_weights(ctx)); r2 <- quiet(E$method_weights(ctx))
if (identical(r1$v, r2$v) && identical(wt, quiet(W(ctx))$v)) ok("E1 결정성(원 출력 · 래퍼 출력 모두 identical)") else ng("E1 비결정")
if (all(r1$v >= 0) && all(is.finite(r1$v))) ok("E2 비음 · 유한") else ng("E2 음수/비유한")
if (identical(names(r1$v), ctx$assets) && identical(names(wt), ctx$assets)) ok("E3 이름 보존(= ctx$assets 순서)") else ng("E3 이름")
if (abs(sum(wt) - 1) < 1e-12 && max(abs(wt - r1$v / sum(r1$v))) < 1e-12 && !any(grepl("어댑터 실패", rw$out, fixed = TRUE)))
  ok("E4 래퍼 경유 Σw = 1 · 해 불변 · 폴백 없음") else ng("E4 래퍼", paste(rw$out, collapse = " | "))
ln <- grep("^\\[trp\\] ", r1$out, value = TRUE)
pat <- sprintf("^\\[trp\\] d=2010-01-29 n=12 root=%s depth=[0-9]+ leaves=[0-9]+ active=12$", rt$root)
if (length(ln) == 1L && grepl(pat, ln)) ok(sprintf("E5 진단 줄 '%s'", ln)) else ng("E5 진단 줄", paste(r1$out, collapse = " | "))
lv <- as.integer(sub(".*leaves=([0-9]+).*", "\\1", ln)); dp <- as.integer(sub(".*depth=([0-9]+).*", "\\1", ln))
if (length(lv) == 1L && lv == sum(rt$b == 0L) && dp == max(rt$depth)) ok("E6 진단 줄 값 = 나무(잎 수 · 최대 깊이)") else ng("E6 진단 줄 값")
## 활동 필터: 수익 전부 0 인 종목 → 비중 0 · active 하나 줄어든다 · 나머지는 정상
Xz <- Xc; Xz[, "K03"] <- 0
rz <- quiet(E$method_weights(modifyList(ctx, list(R = Xz))))
if (!inherits(rz$v, "error") && rz$v[["K03"]] == 0 && sum(rz$v > 0) == 11L && any(grepl("active=11$", rz$out)))
  ok("E7 활동 필터(m_i > ε) — 수익 0 종목 비중 0 · active=11") else ng("E7 활동 필터", paste(rz$out, collapse = " | "))
X0 <- Xc * 0; r0 <- quiet(W(modifyList(ctx, list(R = X0))))
if (!inherits(r0$v, "error") && any(grepl("어댑터 실패", r0$out, fixed = TRUE)) && max(abs(r0$v - 1 / 12)) < 1e-12)
  ok("E8 활성 0 → 이름 부르고 래퍼 EW 폴백") else ng("E8 활성 0", paste(r0$out, collapse = " | "))
src <- paste(sub("#.*$", "", readLines(file.path(ROOT, AD), warn = FALSE, encoding = "UTF-8")), collapse = "\n")
bad <- c("read", "fread", "load", "Sys.Date", "Sys.time", "file.path", "get(", "<<-", "set.seed", "runif", "rnorm", "sample(", "ctx$mu", "ctx$Sigma")
hit <- bad[vapply(bad, function(b) grepl(b, src, fixed = TRUE), logical(1))]
if (!length(hit)) ok("E9 어댑터 코드에 파일 · 시각 · 전역 · 난수 · mu/Sigma 접근 없음") else ng("E9 ctx 밖 접근 의심", paste(hit, collapse = ","))

cat("\n=== F. 돌연변이(소스 텍스트 치환) ===\n")
src_ad <- paste(readLines(file.path(ROOT, AD), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
mutate <- function(from, to) {
  n_hit <- lengths(regmatches(src_ad, gregexpr(from, src_ad, fixed = TRUE)))
  if (n_hit != 1L) return(list(ok = FALSE, n = n_hit))
  mt <- sub(from, to, src_ad, fixed = TRUE)
  Em <- new.env(parent = globalenv()); eval(parse(text = mt, encoding = "UTF-8"), envir = Em)
  list(ok = !identical(mt, src_ad), n = n_hit, env = Em)
}
## F1 α 식 ρ/b → ρ·b
m1 <- mutate("(1 - rho) + rho / pmax(b, 1L)", "(1 - rho) + rho * pmax(b, 1L)")
if (!isTRUE(m1$ok)) ng("F1 주입 실패 — α 줄이 바뀌었으면 재조준", sprintf("일치 %d", m1$n)) else {
  okrun <- !inherits(tryCatch(m1$env$trp_mst_weights(.cluster_panel()), error = function(e) e), "error")
  if (!okrun) ng("F1 사본이 단독으로 안 돈다 — 대조 무효") else if (!test_A(m1$env, verbose = FALSE)) ok("F1 α 식 돌연변이(ρ·b · 치환 1곳) 사본 → A 불통과") else ng("F1 A 가 α 돌연변이를 못 잡는다")
}
## F2 MST → 최대 신장 나무(거리 내림차순)
m2 <- mutate("o <- order(dv, lo_r, hi_r, method = \"radix\")", "o <- order(-dv, lo_r, hi_r, method = \"radix\")")
if (!isTRUE(m2$ok)) ng("F2 주입 실패 — 간선 정렬 줄이 바뀌었으면 재조준", sprintf("일치 %d", m2$n)) else {
  okrun <- !inherits(tryCatch(m2$env$trp_mst_weights(.cluster_panel()), error = function(e) e), "error")
  if (!okrun) ng("F2 사본이 단독으로 안 돈다 — 대조 무효") else if (!test_B(m2$env, verbose = FALSE) && !test_A(m2$env, verbose = FALSE)) ok("F2 최대 신장 나무 돌연변이(치환 1곳) 사본 → B · A 불통과") else ng("F2 B/A 가 정렬 돌연변이를 못 잡는다")
}
## F3 hub 동률 처리 → 이름 최대(뿌리 규칙 돌연변이)
m3 <- mutate("root <- cand[order(cand, method = \"radix\")][1]", "root <- cand[order(cand, method = \"radix\", decreasing = TRUE)][1]")
if (!isTRUE(m3$ok)) ng("F3 주입 실패 — 뿌리 줄이 바뀌었으면 재조준", sprintf("일치 %d", m3$n)) else {
  if (!test_A(m3$env, verbose = FALSE)) ok("F3 동률 뿌리 규칙 돌연변이(이름 최대 · 치환 1곳) 사본 → A(경로형) 불통과") else ng("F3 A 가 뿌리 동률 돌연변이를 못 잡는다")
}

cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
cat(sprintf('{"test":"topological_rp_nka_2026","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL > 0L) 1L else 0L)
