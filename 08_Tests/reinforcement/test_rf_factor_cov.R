#!/usr/bin/env Rscript
# test_rf_factor_cov.R — 요인 위험모형 Σ 공급자(rf_factor_cov.R) 합성 자료 시험 (2026-11-10 · 레인 E3)
#   ① 알려진 요인 구조 복원(B 상관 · Σ 상대오차가 표본 공분산보다 작다)
#   ② 표본 밖 분산 예측(합성) — GMV 포트폴리오의 '참' 분산 · 무작위 롱온리 포트폴리오 예측 오차
#   ③ 양의 정부호(N > T 포함) · 조건수 가드 발화
#   ④ 변형(downside · dd_state) 표본 · 대체 경로 · ⑤ pca(Bai-Ng 가 참 K) · ⑥ cs(특성) · ⑦ LW2004
#   ⑧ 시그마 어댑터(운영 래퍼 wrap_sigma_estimator 경유) — 공급자 유무 · 낡은 요인 표
#   (PIT 누출 주입 · 돌연변이는 08_Tests/scenarios/test_scn_construct_pit_leak.R)
.root <- local({
  m <- file.path("02_Infrastructure", "reinforcement", "rf_factor_cov.R"); r <- NULL
  for (k in c("QM_ROOT", "CLAUDE_PROJECT_DIR")) { v <- gsub("\\\\", "/", Sys.getenv(k, "")); if (is.null(r) && nzchar(v) && file.exists(file.path(v, m))) r <- v }
  if (is.null(r)) { d <- getwd(); for (i in 1:6) { if (is.null(r) && file.exists(file.path(d, m))) r <- d; d <- dirname(d) } }
  if (is.null(r)) { a <- commandArgs(FALSE); f <- sub("^--file=", "", a[grep("^--file=", a)]); if (length(f)) { d <- dirname(gsub("\\\\", "/", f[1])); for (i in 1:6) { if (is.null(r) && file.exists(file.path(d, m))) r <- d; d <- dirname(d) } } }
  if (is.null(r)) stop("root 미발견"); r
})
Sys.setenv(QM_ROOT = .root)
suppressWarnings(suppressMessages(source(file.path(.root, "02_Infrastructure/reinforcement/rf_factor_cov.R"))))
cfg <- rfc_config(file.path(.root, "02_Infrastructure/reinforcement/rf_factor_cov.json"))
P <- 0L; Fl <- 0L
ck <- function(cond, msg) { if (isTRUE(cond)) { P <<- P + 1L; cat("  [PASS]", msg, "\n") } else { Fl <<- Fl + 1L; cat("  [FAIL]", msg, "\n") } }

# 합성 세계 — 참 Σ = BΩBᵀ + D 를 알고 있다
mk_world <- function(N, Tn, K = 3L, seed = 7L, fsd = c(0.012, 0.006, 0.005)) {
  set.seed(seed)
  Om <- diag(fsd[seq_len(K)]^2, K)
  B <- cbind(stats::runif(N, 0.5, 1.5), matrix(stats::rnorm(N * (K - 1L), 0, 0.8), N))[, seq_len(K), drop = FALSE]
  D <- stats::runif(N, 0.01, 0.025)^2
  F <- matrix(stats::rnorm(Tn * K), Tn) %*% chol(Om)
  E <- matrix(stats::rnorm(Tn * N), Tn) %*% diag(sqrt(D))
  R <- F %*% t(B) + E
  a <- sprintf("A%03d", seq_len(N)); colnames(R) <- a; colnames(F) <- c("MKT_TOTAL", "SMB5", "HML")[seq_len(K)]
  S <- B %*% Om %*% t(B) + diag(D); dimnames(S) <- list(a, a)
  list(R = R, F = F, B = B, S = S, D = D, a = a)
}
relF <- function(A, B) sqrt(sum((A - B)^2)) / sqrt(sum(B^2))
gmv <- function(S) { o <- solve(S, rep(1, ncol(S))); o / sum(o) }

cat("[1] 알려진 요인 구조 복원 (N 60 · T 252 · K 3)\n")
W <- mk_world(60, 252)
o <- rfc_ts_cov(W$R, W$F, cfg)
ck(min(diag(stats::cor(o$B, W$B))) > 0.95, sprintf("B 열별 상관 최소 %.3f > 0.95", min(diag(stats::cor(o$B, W$B)))))
eF <- relF(o$Sigma, W$S); eS <- relF(stats::cov(W$R), W$S)
ck(eF < eS, sprintf("Σ 상대오차 요인 %.4f < 표본 %.4f", eF, eS))
ck(o$K == 3L && identical(o$model, "ts"), "K = 3 · model ts")

cat("[2] 표본 밖 분산 예측(합성)\n")
vF <- drop(t(gmv(o$Sigma)) %*% W$S %*% gmv(o$Sigma)); vS <- drop(t(gmv(stats::cov(W$R))) %*% W$S %*% gmv(stats::cov(W$R)))
ck(vF < vS, sprintf("GMV 참 분산 요인판 %.3e < 표본판 %.3e", vF, vS))
set.seed(11); Wp <- matrix(stats::rexp(200 * 60), 200); Wp <- Wp / rowSums(Wp)
pe <- function(S) mean((log(rowSums((Wp %*% S) * Wp)) - log(rowSums((Wp %*% W$S) * Wp)))^2)
ck(pe(o$Sigma) <= pe(stats::cov(W$R)) * 1.05, sprintf("롱온리 200개 로그 분산 예측 MSE 요인 %.4f ≤ 표본 %.4f × 1.05", pe(o$Sigma), pe(stats::cov(W$R))))
Wn <- mk_world(60, 252, seed = 99)          # 같은 참 구조 · 새 경로(표본 밖) — 실현 분산 대비
Wn$R <- { set.seed(123); Fn <- matrix(stats::rnorm(252 * 3), 252) %*% chol(diag(c(0.012, 0.006, 0.005)^2)); Fn %*% t(W$B) + matrix(stats::rnorm(252 * 60), 252) %*% diag(sqrt(W$D)) }
rv <- function(w) stats::var(drop(Wn$R %*% w))
ck(rv(gmv(o$Sigma)) < rv(gmv(stats::cov(W$R))), sprintf("새 경로 실현 분산 GMV 요인 %.3e < 표본 %.3e", rv(gmv(o$Sigma)), rv(gmv(stats::cov(W$R)))))

cat("[3] 양의 정부호 · N > T · 조건수 가드\n")
W2 <- mk_world(300, 120, seed = 3)
o2 <- rfc_ts_cov(W2$R, W2$F, cfg)
ck(min(eigen(o2$Sigma, TRUE, TRUE)$values) > 0, "N 300 > T 120 에서 요인 Σ 최소 고유값 > 0")
ck(min(eigen(stats::cov(W2$R), TRUE, TRUE)$values) < 1e-12, "같은 자료의 표본 Σ 는 특이(대조)")
Ssing <- diag(c(1, 1e-12, 1)); g <- rfc_guard(Ssing, cfg$kappa_max)
ck(g$clipped && g$kappa_after <= cfg$kappa_max * (1 + 1e-6), sprintf("가드 발화 κ %.3g → %.3g", g$kappa_before, g$kappa_after))
g0 <- rfc_guard(o$Sigma, cfg$kappa_max); ck(!g0$clipped && max(abs(g0$S - o$Sigma)) < 1e-15, "정상 Σ 는 가드가 건드리지 않음")

cat("[4] 위기 조건부 변형\n")
od <- rfc_ts_cov(W$R, W$F, cfg, variant = "downside")
ck(od$diag$n_obs == sum(W$F[, "MKT_TOTAL"] < 0) && is.na(od$diag$fallback), sprintf("downside 표본 = 시장 음수일 %d", od$diag$n_obs))
ck(relF(od$Sigma, o$Sigma) > 1e-3, "downside Σ ≠ base Σ")
H <- rbind(W$F, W$F)                          # 확장 창 이력 — 앞 절반에 25% 급락 구간 주입
H[100:130, "MKT_TOTAL"] <- -0.012
st <- rfc_state_mask(H[, "MKT_TOTAL"], "dd_state", cfg$dd_state_threshold)
os <- rfc_ts_cov(W$R, W$F, cfg, variant = "dd_state", F_hist = H)
ck(os$diag$n_omega == sum(st) && sum(st) >= 40 && is.na(os$diag$fallback), sprintf("dd_state Ω 표본 = 상태일 %d (이력 %d)", os$diag$n_omega, nrow(H)))
ck(max(abs(os$B - o$B)) < 1e-12, "dd_state 는 노출 B 를 유지(Ω 만 위기판)")
of <- rfc_ts_cov(W$R, W$F, cfg, variant = "dd_state", F_hist = W$F)
ck(!is.na(of$diag$fallback) && max(abs(of$Sigma - o$Sigma)) < 1e-12, sprintf("상태 표본 부족 → base 로 돌아가며 사유 기록: %s", of$diag$fallback))
mm <- c(-0.1, -0.1, 0.3, -0.05); ck(identical(rfc_state_mask(mm, "dd_state", 0.18), c(FALSE, TRUE, FALSE, FALSE)), "dd_state 판정은 그 날까지 경로만(as-of) — 손계산 대조")
Fna <- cbind(W$F, RMW = c(rep(NA, 10), stats::rnorm(242, 0, 0.004)))
ona <- rfc_ts_cov(W$R, Fna, cfg); ck(identical(ona$diag$dropped_factors, "RMW") && ona$K == 3L, "창 안 결측 요인은 빼고 기록(dropped_factors)")

cat("[5] pca — Bai-Ng IC_p2\n")
W3 <- mk_world(80, 252, seed = 5, fsd = c(0.015, 0.012, 0.010))   # 퍼진(pervasive) 요인 — Bai-Ng 의 전제
op <- rfc_pca_cov(W3$R, cfg)
ck(op$K == 3L, sprintf("퍼진 요인 참 K 3 → 선택 K %d", op$K))
opw <- rfc_pca_cov(mk_world(80, 252, seed = 5)$R, cfg)
ck(opw$K <= 3L, sprintf("약한 요인(분산 신호 < 잡음)은 덜 고른다 — 선택 K %d ≤ 3 (과대 선택 없음)", opw$K))
ck(relF(op$Sigma, W3$S) < relF(stats::cov(W3$R), W3$S), sprintf("pca Σ 오차 %.4f < 표본 %.4f", relF(op$Sigma, W3$S), relF(stats::cov(W3$R), W3$S)))

cat("[6] cs — 알려진 특성 노출\n")
set.seed(8); N <- 120; Tn <- 252
X <- matrix(stats::rnorm(N * 2), N, dimnames = list(sprintf("A%03d", 1:N), c("size", "value")))
X1 <- cbind(1, X); Om <- diag(c(0.012, 0.005, 0.004)^2); D <- stats::runif(N, 0.01, 0.02)^2
Fc <- matrix(stats::rnorm(Tn * 3), Tn) %*% chol(Om); Rc <- Fc %*% t(X1) + matrix(stats::rnorm(Tn * N), Tn) %*% diag(sqrt(D)); colnames(Rc) <- rownames(X)
Sc <- X1 %*% Om %*% t(X1) + diag(D)
oc <- rfc_cs_cov(Rc, X, cfg)
ck(relF(oc$Sigma, Sc) < relF(stats::cov(Rc), Sc), sprintf("cs Σ 오차 %.4f < 표본 %.4f", relF(oc$Sigma, Sc), relF(stats::cov(Rc), Sc)))
oc2 <- rfc_cs_cov(Rc, -X, cfg); ck(max(abs(oc2$Sigma - oc$Sigma)) < 1e-14, "노출 부호 반전에 Σ 불변(방향 무관)")
ck(inherits(try(rfc_cs_cov(Rc, X[-1, ], cfg), silent = TRUE), "try-error"), "노출 행이 종목과 안 맞으면 멈춤")

cat("[7] Ledoit-Wolf 2004\n")
lw <- rfc_lw2004(W2$R[, 1:100])
ck(lw$delta > 0 && lw$delta <= 1 && min(eigen(lw$S, TRUE, TRUE)$values) > 0, sprintf("δ %.3f ∈ (0,1] · PD (N 100 · T 120)", lw$delta))
lw2 <- rfc_lw2004(mk_world(10, 2000, seed = 4)$R); ck(lw2$delta < lw$delta, sprintf("T 많으면 수축 약함 δ %.3f < %.3f", lw2$delta, lw$delta))

cat("[8] 시그마 어댑터 — 운영 래퍼 wrap_sigma_estimator 경유\n")
suppressWarnings(suppressMessages({ library(data.table); source(file.path(.root, "02_Infrastructure/methods/method_registry.R")) }))
ae <- new.env(); sys.source(file.path(.root, "02_Infrastructure/methods/adapters/factor_cov_fan_fan_lv_2008.R"), envir = ae)
wf <- wrap_sigma_estimator(get("sigma_estimate", ae), "FactorCovFFL2008")
d0 <- as.Date("2024-01-02"); a <- W$a
ctx0 <- list(assets = a, R = W$R, decision_date = d0)
log0 <- utils::capture.output(S0 <- wf(ctx0))
ck(any(grepl("model=pca", log0)) && any(grepl("요인 공급자 없음", log0)), "공급자 없음 → pca 로 내려가고 진단 줄에 사유")
ck(relF(S0, stats::cov(W$R)) > 1e-3 && !any(grepl("폴백", log0)), "표본 공분산과 구별 · 래퍼 폴백 없음")
fdt <- data.table(Date = d0 - rev(seq_len(252)), W$F)
ctx1 <- c(ctx0, list(factor_returns = function() fdt))
log1 <- utils::capture.output(S1 <- wf(ctx1))
ck(any(grepl("model=ts", log1)) && any(grepl("align=tail", log1)) && max(abs(S1 - o$Sigma)) < 1e-12, "공급자 있음 → ts · 끝 맞춤 · 순수 함수와 같은 Σ")
ctx2 <- c(ctx0, list(factor_returns = function() { x <- copy(fdt); x[, Date := Date - 60L]; x }))
log2 <- utils::capture.output(S2 <- wf(ctx2))
ck(any(grepl("model=pca", log2)) && any(grepl("요인 표 낡음", log2)), "낡은 요인 표(60일) → 관측 요인을 버리고 pca · 사유 기록")
ctx3 <- c(ctx0, list(factor_returns = function() fdt, R_dates = fdt$Date))
log3 <- utils::capture.output(S3 <- wf(ctx3))
ck(any(grepl("align=dates", log3)) && max(abs(S3 - o$Sigma)) < 1e-12, "R_dates 전달 → 날짜 맞춤(정공법) · 같은 Σ")
ck(isTRUE(all.equal(wf(ctx1), wf(ctx1))), "결정론(같은 ctx 두 번 같은 Σ)")

cat("[9] dd_state 상태 경로는 요인 열 가용 시작과 무관(시장 열 전체 이력 · 2026-11-10 G8 수리)\n")
## 실데이터 결함 모사: 시장 열은 처음부터 · 다른 요인 열(SMB5)은 늦게 시작(앞 250행 NA). 앞부분에 고점 → 35% 하락 → 고점 아래 정체.
##   종전(complete.cases 로 거른 뒤 경로) = 경로가 251행에서 1 로 다시 시작해 고점이 재설정 → 상태일 0 → base 로 떨어졌다.
set.seed(21); nH <- 600L
mH <- c(rep(0.002, 100), rep(log(0.65) / 100, 100), stats::rnorm(400, 0, 0.003))
mH[101:200] <- exp(mH[101:200]) - 1
HH <- cbind(MKT_TOTAL = mH, SMB5 = c(rep(NA, 250), stats::rnorm(350, 0, 0.006)), HML = stats::rnorm(nH, 0, 0.005))
st_full <- rfc_state_mask(HH[, "MKT_TOTAL"], "dd_state", cfg$dd_state_threshold)       # 시장 열 하나의 as-of 경로(독립 기대값)
sel_exp <- st_full & stats::complete.cases(HH)
oh <- rfc_ts_cov(W$R, W$F, cfg, variant = "dd_state", F_hist = HH)
ck(sum(sel_exp) >= 200L && oh$diag$n_omega == sum(sel_exp) && is.na(oh$diag$fallback),
   sprintf("Ω 표본 = 시장 전 경로 상태일 ∩ 요인 완전 행 %d (얻음 %d · fb %s)", sum(sel_exp), oh$diag$n_omega, oh$diag$fallback))
ck(isTRUE(all.equal(oh$Omega, stats::cov(HH[sel_exp, colnames(W$F), drop = FALSE]), tolerance = 1e-12)), "Ω_state = cov(상태일 ∩ 완전 행) — 표식과 표본 선택 분리")
ck(identical(oh$variant_used, "dd_state") && oh$diag$state_path_n == nH && oh$diag$n_state_days == sum(st_full), "variant_used = dd_state · 진단에 상태 경로 길이 · 상태일")
## 모든 열이 처음부터 있으면 종전과 같은 표본(기본 이력 모양에서 결과 불변)
ck(os$diag$n_omega == sum(st) && identical(os$variant_used, "dd_state"), "열 결측 없는 이력 → 종전과 같은 상태 표본")
ck(identical(of$variant_used, "base") && identical(od$variant_used, "downside") && identical(o$variant_used, "base"), "표본 부족으로 떨어진 변형은 variant_used = base(소비자가 셀 수 있게)")
odf <- rfc_ts_cov(W$R[1:60, ], W$F[1:60, ], cfg, variant = "downside")
ck(!is.na(odf$diag$fallback) && identical(odf$variant_used, "base"), sprintf("downside 표본 부족 → variant_used = base (%s)", odf$diag$fallback))
## rfc_sigma_ctx 경로 — 날짜가 있는 이력에서 상태 경로 시작일을 진단에 남긴다
dH <- d0 - rev(seq_len(nH)); FH <- data.table(Date = dH, HH)
oc9 <- rfc_sigma_ctx(list(assets = a, R = W$R, R_dates = tail(dH, 252L), decision_date = d0, factor_returns = function() { x <- copy(FH); x[tail(seq_len(nH), 252L), (colnames(W$F)) := as.data.table(W$F)]; x }), cfg, "dd_state")
ck(identical(oc9$model, "ts") && identical(oc9$diag$state_path_start, format(dH[1])) && is.na(oc9$diag$fallback),
   sprintf("rfc_sigma_ctx dd_state — 상태 경로 시작 %s(= 시장 열 첫날 · 요인 열 SMB5 시작 %s 아님)", oc9$diag$state_path_start %||% "없음", format(dH[251])))

cat("[10] 돌연변이 — 상태 경로를 요인 완전 행으로 되돌리면 [9] 가 잡는다(소스 텍스트 치환 · 치환 수 단언)\n")
src <- readLines(file.path(.root, "02_Infrastructure/reinforcement/rf_factor_cov.R"), warn = FALSE, encoding = "UTF-8")
mut_load <- function(from, to) {
  hit <- grepl(from, src, fixed = TRUE); s2 <- src; s2[hit] <- gsub(from, to, s2[hit], fixed = TRUE)
  f <- tempfile(fileext = ".R"); writeLines(s2, f, useBytes = TRUE); e <- new.env(parent = globalenv())
  suppressWarnings(suppressMessages(sys.source(f, envir = e))); list(e = e, n = sum(hit))
}
M1 <- mut_load("mrow <- is.finite(H[, mkt])", "mrow <- stats::complete.cases(H[, colnames(F), drop = FALSE])")
om1 <- tryCatch(M1$e$rfc_ts_cov(W$R, W$F, cfg, variant = "dd_state", F_hist = HH), error = function(e) NULL)
ck(M1$n == 1L && !is.null(om1) && om1$diag$n_omega != sum(sel_exp), sprintf("치환 %d · 돌연변이 n_omega %s ≠ %d(검출)", M1$n, if (is.null(om1)) "오류" else om1$diag$n_omega, sum(sel_exp)))
M2 <- mut_load('vu <- if (is.na(fb)) variant else "base"', "vu <- variant")
om2 <- M2$e$rfc_ts_cov(W$R, W$F, cfg, variant = "dd_state", F_hist = W$F)
ck(M2$n == 1L && !identical(om2$variant_used, "base"), sprintf("치환 %d · variant_used 고정 돌연변이 → 폴백이 base 로 안 보인다(검출)", M2$n))

cat("[11] 설정 요인 열 축소 보고 · 날짜 덮음 직접 판정 (2026-11-10 감사 U13)\n")
## 구판: 창 안 일부 날짜에 결측인 비시장 열(또는 표에 없는 설정 열)을 빼고도 model = ts · variant_used = 요청 그대로 → 셀 엔진이 못 셌다.
set.seed(31); dU <- seq(as.Date("2015-01-01"), by = "day", length.out = 400L); dU0 <- dU[301]
FU <- data.table(Date = dU); for (cn in cfg$factor_columns) FU[, (cn) := stats::rnorm(.N, 0, 0.01)]
BU <- matrix(stats::rnorm(8 * length(cfg$factor_columns), 1, 0.3), 8)
RU <- as.matrix(FU[Date < dU0, cfg$factor_columns, with = FALSE]) %*% t(BU) + matrix(stats::rnorm(300 * 8, 0, 0.01), 300); colnames(RU) <- sprintf("A%d", 1:8)
mkU <- function(F, e = environment(rfc_sigma_ctx)) e$rfc_sigma_ctx(list(assets = colnames(RU), R = RU, R_dates = dU[1:300], decision_date = dU0,
                                                                       factor_returns = function() F[Date < dU0]), cfg, "base")
nm_nonmkt <- setdiff(cfg$factor_columns, cfg$market_column)[length(setdiff(cfg$factor_columns, cfg$market_column))]
u0 <- mkU(FU)
ck(identical(u0$model, "ts") && length(u0$diag$requested_missing) == 0L, "완전한 요인 표 → requested_missing 없음(기본 경로)")
FU2 <- copy(FU); FU2[250:260, (nm_nonmkt) := NA_real_]
u1 <- mkU(FU2)
ck(identical(u1$model, "ts") && identical(u1$diag$requested_missing, nm_nonmkt), sprintf("창 안 결측 비시장 열(%s) → ts 로 진행하되 requested_missing 에 그 열(%s)",
   nm_nonmkt, paste(u1$diag$requested_missing, collapse = ",")))
FU3 <- copy(FU)[, (nm_nonmkt) := NULL]; u2 <- mkU(FU3)
ck(identical(u2$diag$requested_missing, nm_nonmkt), "표에 없는 설정 열 → requested_missing")
FU4 <- FU[!(Date %in% dU[100:105])]; u3 <- mkU(FU4)
ck(identical(u3$model, "pca") && grepl("덮지 못함", u3$diag$fallback, fixed = TRUE), "R 날짜 일부를 요인 표가 못 덮음 → pca · 사유(날짜 덮음 직접 판정)")
M3 <- mut_load("o$diag$requested_missing <- unique(", "o$diag$zz_mutated_off <- unique(")   # 접두어가 같은 이름은 `$` 부분 일치로 다시 잡힌다 — 다른 이름으로
u1m <- mkU(FU2, M3$e)
ck(M3$n == 1L && length(u1m$diag$requested_missing) == 0L, sprintf("[돌연변이] 보고 줄 비활성(치환 %d) → 열 축소가 안 보인다(검출 · 엔진 집계의 유일한 입력)", M3$n))

cat(sprintf('{"test":"test_rf_factor_cov","pass":%d,"fail":%d,"total":%d}\n', P, Fl, P + Fl))
if (Fl > 0L) quit(status = 1L)
