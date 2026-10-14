#!/usr/bin/env Rscript
#==============================================================================
# test_eigen_clean_markowitz.R — 고유모드 정제 공분산 마코위츠 어댑터(arXiv 1810.08384 · 2026-10-15)
#
# 지키는 것(양방향):
#   A. 정제 공분산 — 대각합 보존(식 4 'Tr C = Σσ²') · 양정치 · k 상한(n−1) · 결정성 · 위반 주입(상관 대각합 판)이 A1 에 걸린다
#   B. 비중(래퍼 직접) — 롱온리 · Σw = 1 · EW 와 구별 · 고변동 종목 비중이 낮다(위험 처리 방향)
#      · 상한 · 롱온리 제약이 묶이지 않을 때 무제약 해 Σ̃⁻¹1 과 비례(논문 x ∝ C⁻¹p 의 롱온리 판)
#   C. 실패는 이름을 부르고 EW 로 — 조용한 통과 없음(표준편차 0 종목)
#   D. 어댑터가 ctx 밖을 읽지 않는다(PIT — 파일 · 날짜 · 전역 데이터 접근 없음)
#   E. ★운영 경로(셀 엔진 catalog 분기와 같은 weight_catalog_arms()$adapter_fn — 래퍼 상한 = WC_UB) — 2026-10-15 P3R02 교차 점검 R1:
#      구판 검사는 ub 1.0 래퍼로만 재서, 운영 상한 0.20 의 사후 재분배(휴리스틱)와 양수 4종 이하 해의 단언 실패 → 신호일 무기록 탈락을
#      보지 못했다. 상한이 2차 계획 안에 있으면 래퍼가 해를 바꾸지 않는다(참 최적해) — 구판(상한 밖) 사본은 같은 입력에서 바뀌거나 죽는다.
#==============================================================================
suppressMessages({ library(jsonlite); library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat(sprintf("  OK   %s\n", m)) }
ng <- function(m, d = "") { FAIL <<- FAIL + 1L; cat(sprintf("  FAIL %s%s\n", m, if (nzchar(d)) paste0(" — ", d) else "")) }
quiet <- function(expr) { o <- capture.output(v <- tryCatch(expr, error = function(e) e)); list(v = v, out = o) }

AD <- "02_Infrastructure/methods/adapters/eigen_clean_markowitz.R"
E <- new.env(parent = globalenv()); sys.source(file.path(ROOT, AD), envir = E)
suppressMessages(source(file.path(ROOT, "02_Infrastructure/methods/method_registry.R")))        # wrap_adapter(운영 래퍼)
suppressMessages(source(file.path(ROOT, "02_Infrastructure/portfolio/strategy_tilt_weights.R"))) # 래퍼 의존 normalize_long_only(register_method.R 와 같은 적재)

## 합성 패널 — 시장 1요인 + 업종 2요인 + 종목 잡음(변동성 이질) · 252일
.panel <- function(n = 20L, T = 252L, seed = 7L, sv = seq(0.006, 0.030, length.out = n)) {
  set.seed(seed)
  m <- rnorm(T, 0, 0.012); g1 <- rnorm(T, 0, 0.008); g2 <- rnorm(T, 0, 0.008)
  b <- runif(n, 0.6, 1.4); grp <- rep(1:2, length.out = n)
  X <- sapply(seq_len(n), function(j) b[j] * m + (if (grp[j] == 1L) g1 else g2) + rnorm(T, 0, sv[j]))
  colnames(X) <- sprintf("T%02d", seq_len(n)); X
}
X <- .panel()
ctx <- list(R = X, assets = colnames(X), mu = setNames(rep(0, ncol(X)), colnames(X)),
            Sigma = stats::cov(X), ub = 1, lookback_days = 252L, decision_date = as.Date("2010-01-29"))

cat("=== A. 정제 공분산 ===\n")
cc <- E$.ecm_clean_cov(X)
s <- apply(X, 2L, stats::sd)
if (abs(sum(diag(cc$Sigma)) - sum(s^2)) < 1e-10) ok("A1 대각합 보존 — Tr Σ̃ = Σσ²(논문 식 4)") else
  ng("A1 대각합", sprintf("%.3e vs %.3e", sum(diag(cc$Sigma)), sum(s^2)))
if (min(eigen(cc$Sigma, symmetric = TRUE, only.values = TRUE)$values) > 0) ok("A2 양정치(ε² > 0)") else ng("A2 양정치 아님")
if (identical(cc$k, 5L) && cc$eps2 > 0) ok(sprintf("A3 k = 5 · ε² = %.4f", cc$eps2)) else ng("A3", paste(cc$k, cc$eps2))
cc4 <- E$.ecm_clean_cov(X[, 1:4])
if (identical(cc4$k, 3L) && cc4$eps2 > 0) ok("A4 종목 4 → k = n−1 = 3(평평한 잔여 모드가 남는다)") else ng("A4", paste(cc4$k, cc4$eps2))
## 정제가 실제로 표본 공분산과 다르다(아무것도 안 한 정제가 아님). 보존되는 것은 총분산뿐 — 종목별 분산은 논문대로 바뀔 수 있다
S0 <- stats::cov(X)
if (max(abs(cc$Sigma - S0)) > 1e-8 && abs(sum(diag(cc$Sigma)) - sum(diag(S0))) < 1e-10)
  ok("A5 공분산은 정제되고(표본과 다름) 총분산은 보존된다") else ng("A5 정제 무효 또는 총분산 변형")
## A6 위반 주입(양성 대조): 정제 함수 사본의 ε² 를 구판 오류(상관 대각합 보존 — (n − Σλ)/n)로 바꾸면 A1 의 단정이 붉어진다
src_cc <- deparse(E$.ecm_clean_cov)
i_eps <- grep("eps2 <- max(", src_cc, fixed = TRUE)
if (length(i_eps) == 1L) {
  mut_cc <- src_cc; mut_cc[i_eps] <- "  eps2 <- max((n - sum(lam))/n, 1e-08)"
  Em <- new.env(parent = E); fm <- eval(parse(text = mut_cc), envir = Em)
  ccm <- fm(X)
  if (abs(sum(diag(ccm$Sigma)) - sum(s^2)) > 1e-6) ok(sprintf("A6 위반 주입 — 상관 대각합 판 사본은 총분산을 못 지킨다(차 %.2e) → A1 이 붉어진다", abs(sum(diag(ccm$Sigma)) - sum(s^2)))) else
    ng("A6 돌연변이 사본이 A1 을 통과한다 — A1 에 검출력이 없다")
} else ng("A6 주입 실패 — ε² 줄이 바뀌었으면 재조준", sprintf("일치 %d", length(i_eps)))

cat("\n=== B. 비중(래퍼 직접 · ub 1.0) ===\n")
W <- wrap_adapter(E$method_weights, "EigenCleanMarkowitz")
r1 <- quiet(W(ctx)); r2 <- quiet(W(ctx)); w1 <- r1$v; w2 <- r2$v
if (all(w1 >= -1e-12) && abs(sum(w1) - 1) < 1e-9) ok("B1 롱온리 · Σw = 1") else ng("B1 제약")
if (identical(w1, w2)) ok("B2 결정성(같은 입력 → 같은 출력)") else ng("B2 비결정")
if (max(abs(w1 - 1 / length(w1))) > 0.01) ok(sprintf("B3 EW 와 구별(최대 편차 %.3f)", max(abs(w1 - 1 / length(w1))))) else ng("B3 EW 퇴화")
## 같은 요인 노출 · 잡음만 다른 두 종목: 잡음 큰 쪽 비중이 작다(정제 공분산의 위험 처리 방향)
lo <- "T01"; hi <- "T19"   # 같은 업종(홀수 번호 = 업종 1) · 잡음 sd 0.006 vs 0.029
if (w1[[lo]] > w1[[hi]]) ok(sprintf("B4 저잡음 %s(%.3f) > 고잡음 %s(%.3f)", lo, w1[[lo]], hi, w1[[hi]])) else ng("B4 위험 처리 방향", paste(w1[[lo]], w1[[hi]]))
## 상한 · 롱온리 제약이 묶이지 않으면 무제약 해(Σ̃⁻¹1)와 비례 — 논문 x ∝ C⁻¹p 의 롱온리 판
##   (교환 가능 패널 = 같은 시장 베타 1 · 같은 잡음 · 업종 요인 없음 → 해가 EW 근처 양수 · 상한 0.20 아래 = 제약 비구속)
##   표본 3000일 — 252일이면 표본 잡음 모드(k = 5 중 4개)가 해를 흩어 음수 · 상한 초과가 생긴다(전제 불성립 실측 2026-10-15)
set.seed(11L); mb <- rnorm(3000L, 0, 0.012)
Xb <- sapply(1:10, function(j) mb + rnorm(3000L, 0, 0.012)); colnames(Xb) <- sprintf("B%02d", 1:10)
xb <- quiet(E$method_weights(list(R = Xb, assets = colnames(Xb), ub = 1)))$v
ubs <- solve(E$.ecm_clean_cov(Xb)$Sigma, rep(1, 10))
nb <- ubs / sum(ubs)
if (all(nb > 0) && max(nb) < E$ECM_WEIGHT_CAP - 1e-6) {
  if (max(abs(xb / sum(xb) - nb)) < 1e-6) ok("B5 제약 비구속 → 무제약 마코위츠 해와 비례(롱온리 · 상한 계획의 정합)") else ng("B5 비례 아님", sprintf("%.2e", max(abs(xb / sum(xb) - nb))))
} else ng("B5 전제(제약 비구속 패널) 불성립 — 픽스처 재조준", sprintf("min %.3f max %.3f", min(nb), max(nb)))

cat("\n=== C. 실패는 이름을 부르고 EW 로 ===\n")
Xz <- X; Xz[, 3] <- 0                                     # 표준편차 0 종목
rz <- quiet(W(list(R = Xz, assets = colnames(Xz), ub = 1)))
if (!inherits(rz$v, "error") && max(abs(rz$v - 1 / length(rz$v))) < 1e-12 && any(grepl("어댑터 실패", rz$out, fixed = TRUE)))
  ok("C1 정제 불가 → 래퍼가 이름을 부르고 EW 폴백(조용한 통과 아님)") else ng("C1 폴백 호명", paste(rz$out, collapse = "|"))

cat("\n=== D. ctx 밖을 읽지 않는다(PIT) ===\n")
src <- paste(sub("#.*$", "", readLines(file.path(ROOT, AD), warn = FALSE)), collapse = "\n")
bad <- c("read", "fread", "load", "Sys.Date", "Sys.time", "file.path", "get(", "<<-")
hit <- bad[vapply(bad, function(b) grepl(b, src, fixed = TRUE), logical(1))]
if (!length(hit)) ok("D1 어댑터 코드에 파일 · 시각 · 전역 접근 없음") else ng("D1 ctx 밖 접근 의심", paste(hit, collapse = ","))

cat("\n=== E. 운영 경로(셀 엔진 catalog 분기 = weight_catalog_arms()$adapter_fn · 래퍼 상한 WC_UB) ===\n")
suppressMessages(source(file.path(ROOT, "02_Infrastructure/portfolio/weight_catalog.R")))
if (isTRUE(all.equal(E$ECM_WEIGHT_CAP, WC_UB))) ok(sprintf("E1 어댑터 상한 = 카탈로그 하네스 상한(%.2f) — 드리프트 대조", WC_UB)) else
  ng("E1 어댑터 상한 ≠ WC_UB — 계획 안 상한과 래퍼 상한이 어긋난다(재분배 휴리스틱 · 단언 실패가 되살아난다)", paste(E$ECM_WEIGHT_CAP, WC_UB))
AR <- weight_catalog_arms(quiet = TRUE)
row <- AR[catalog_id == "paper:EigenCleanMarkowitz"]
if (nrow(row) != 1L) { ng("E0 카탈로그에 paper:EigenCleanMarkowitz 가 없다"); OP <- NULL } else OP <- row$adapter_fn[[1]]
## 구판(상한 밖) 사본 — **소스 파일 텍스트**를 치환해 만든다(deparse 는 긴 호출을 줄바꿈해 치환이 조용히 빗나갔다 —
##   그 사본은 계획 오류로 EW 폴백을 냈고 E3 가 엉뚱한 이유로 통과했다 · 실측 2026-10-15). 치환 성사 · 사본 단독 실행을 단정한다.
src_ad <- paste(readLines(file.path(ROOT, AD), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
k_am <- "Am <- cbind(diag(n), cap * matrix(1, n, n) - diag(n))"; k_bv <- "bvec = rep(0, 2L * n)"
mut_ad <- sub(k_bv, "bvec = rep(0, n)", sub(k_am, "Am <- diag(n)", src_ad, fixed = TRUE), fixed = TRUE)
OLD <- NULL
if (grepl(k_am, src_ad, fixed = TRUE) && grepl(k_bv, src_ad, fixed = TRUE) && !grepl(k_am, mut_ad, fixed = TRUE) && !grepl(k_bv, mut_ad, fixed = TRUE)) {
  Eo <- new.env(parent = globalenv()); eval(parse(text = mut_ad), envir = Eo)
  ro0 <- quiet(Eo$method_weights(ctx))$v
  if (inherits(ro0, "error") || !is.numeric(ro0)) ng("E-사본이 단독으로 안 돈다 — 대조 무효", if (inherits(ro0, "error")) conditionMessage(ro0) else class(ro0)) else
    OLD <- wrap_adapter(Eo$method_weights, "EigenCleanMarkowitz_old", ub = WC_UB)
} else ng("E-주입 실패 — 제약 행렬 · 계획 호출 텍스트가 바뀌었으면 재조준")
rawn <- function(cx) { r <- quiet(E$method_weights(cx))$v; r / sum(r) }
if (!is.null(OP) && !is.null(OLD)) {
  ## E2 — 계획 안 상한: 운영 래퍼가 해를 바꾸지 않는다(= 참 최적해 · 재분배 없음) · 상한 준수
  ro <- quiet(OP(ctx)); wo <- ro$v; rn <- rawn(ctx)
  unc <- solve(cc$Sigma, rep(1, ncol(X))); unc_max <- max(pmax(unc, 0) / sum(pmax(unc, 0)))
  if (!inherits(wo, "error") && max(wo) <= WC_UB + 1e-9 && abs(sum(wo) - 1) < 1e-9 && max(abs(wo - rn[names(wo)])) < 1e-6)
    ok(sprintf("E2 운영 경로 = 계획 해 그대로(최대 비중 %.3f ≤ %.2f · 래퍼 재분배 0 — 차 %.1e)", max(wo), WC_UB, max(abs(wo - rn[names(wo)])))) else
    ng("E2 운영 경로가 해를 바꿨거나 상한 위반", if (inherits(wo, "error")) conditionMessage(wo) else sprintf("max %.3f · 차 %.2e", max(wo), max(abs(wo - rn[names(wo)]))))
  ## E3 — 양성 대조: 같은 패널에서 구판은 상한 밖이라(무제약 최대 비중 > 상한) 래퍼가 재분배 → 계획 해와 다르다
  rold <- quiet(OLD(ctx)); wold <- rold$v
  if (unc_max > WC_UB && !inherits(wold, "error") && max(abs(wold - wo[names(wold)])) > 1e-4)
    ok(sprintf("E3 구판 사본(상한 밖) → 래퍼 휴리스틱 재분배로 해가 달라진다(차 %.3f · 무제약 최대 %.3f > %.2f) — E2 가 구판을 가른다", max(abs(wold - wo[names(wold)])), unc_max, WC_UB)) else
    ng("E3 전제 또는 검출력 부족", sprintf("무제약 최대 %.3f · 구판 %s", unc_max, if (inherits(wold, "error")) conditionMessage(wold) else "동일"))
  ## E4 — 양수 4종 이하 해: 저베타 · 저잡음 3종(β 1.0 · 잡음 0.004) + 고베타 · 고잡음 3종(β 1.4 · 잡음 0.03) — 1요인 최소분산에서
  ##      β_i > 1/K(Sherman–Morrison) 인 고베타 종목은 무제약 비중이 음수 → 롱온리 해 = 저베타 3종만 양수. 구판(상한 밖)은 래퍼 단언이
  ##      깨져 오류(엔진이 삼키면 신호일 무기록 탈락) · 신판은 상한 계획 해(양수 ≥ ⌈1/c⌉ = 5종)를 낸다
  set.seed(5L); m6 <- rnorm(252L, 0, 0.012)
  X6 <- cbind(sapply(1:3, function(j) 1.0 * m6 + rnorm(252L, 0, 0.004)), sapply(1:3, function(j) 1.4 * m6 + rnorm(252L, 0, 0.03)))
  colnames(X6) <- sprintf("S%02d", 1:6)
  u6 <- quiet(E$.ecm_clean_cov(X6))$v; u6 <- solve(u6$Sigma, rep(1, 6))
  if (sum(u6 > 0) > 4L) ng("E4 전제(무제약 해에 음수 ≥2 → 롱온리 양수 ≤4) 불성립 — 픽스처 재조준", paste(round(u6 / sum(abs(u6)), 3), collapse = ","))
  c6 <- list(R = X6, assets = colnames(X6), ub = 1, decision_date = as.Date("2010-02-26"))
  w6o <- quiet(OLD(c6))$v; w6n <- quiet(OP(c6))
  oldbad <- inherits(w6o, "error")
  newok <- !inherits(w6n$v, "error") && max(w6n$v) <= WC_UB + 1e-9 && sum(w6n$v > 1e-8) >= 5L && abs(sum(w6n$v) - 1) < 1e-9
  if (oldbad && newok) ok(sprintf("E4 양수 ≤4종 해 — 구판 = 래퍼 단언 오류(무기록 탈락의 원인) · 신판 = 양수 %d종 · 최대 %.3f", sum(w6n$v > 1e-8), max(w6n$v))) else
    ng("E4 ≤4종 사례", sprintf("구판 오류 %s · 신판 %s", oldbad, if (inherits(w6n$v, "error")) conditionMessage(w6n$v) else sprintf("양수 %d 최대 %.3f", sum(w6n$v > 1e-8), max(w6n$v))))
  ## E5 — 종목 4개(n·c < 1): 신판은 이름을 부르고 멈춘다 → 래퍼가 EW 폴백을 로그에 남긴다(오류가 엔진까지 가지 않는다 = 무기록 탈락 없음)
  X4 <- X[, 1:4]; c4 <- list(R = X4, assets = colnames(X4), ub = 1, decision_date = as.Date("2010-03-31"))
  r4 <- quiet(OP(c4))
  if (!inherits(r4$v, "error") && max(abs(r4$v - 0.25)) < 1e-12 && any(grepl("상한 불능", r4$out, fixed = TRUE)) &&
      any(grepl("어댑터 실패", r4$out, fixed = TRUE)) && any(grepl("infeasible=1", r4$out, fixed = TRUE)))
    ok("E5 n·c < 1 → '상한 불능' 호명 · 래퍼 EW 폴백 로그 · 진단 줄 infeasible=1(엔진은 EW 폴백으로 센다 · 오류 전파 없음)") else
    ng("E5 n·c < 1 처리", paste(c(if (inherits(r4$v, "error")) conditionMessage(r4$v), r4$out), collapse = " | "))
  ## E6 — 진단 줄: 셀 로그에서 기록 항목(활성 · 상한 구속 · n)을 셀 수 있다(형식 고정)
  ln <- grep("^\\[ecm\\] ", ro$out, value = TRUE)
  pat <- "^\\[ecm\\] d=2010-01-29 n=20 k=5 cap=0\\.20 active=[0-9]+ capbind=[0-9]+ eps2=[0-9.]+ infeasible=0$"
  if (length(ln) == 1L && grepl(pat, ln)) ok(sprintf("E6 진단 줄 형식 '%s'", ln)) else ng("E6 진단 줄", paste(ro$out, collapse = " | "))
  capb <- as.integer(sub(".*capbind=([0-9]+).*", "\\1", ln)); act <- as.integer(sub(".*active=([0-9]+).*", "\\1", ln))
  if (length(capb) == 1L && capb == sum(wo >= WC_UB - 1e-6) && act == sum(wo > 1e-8))
    ok(sprintf("E7 진단 줄 값 = 운영 산출(활성 %d · 상한 구속 %d)", act, capb)) else ng("E7 진단 줄 값 불일치", paste(capb, act, sum(wo >= WC_UB - 1e-6), sum(wo > 1e-8)))
  ## E8 — n·c = 1(5종 × 0.20): 가능해 = EW 하나 → 계획을 풀지 않고 EW · 진단 줄 · 폴백 호명 없음(재점검 권고 10-15 — 일차종속 상한 제약의 quadprog 반올림 오류 회피)
  X5 <- X[, 1:5]; r5 <- quiet(OP(list(R = X5, assets = colnames(X5), ub = 1, decision_date = as.Date("2010-04-30"))))
  if (!inherits(r5$v, "error") && max(abs(r5$v - 0.2)) < 1e-12 && any(grepl("^\\[ecm\\] .* n=5 .*active=5 capbind=5 .*infeasible=0$", r5$out)) &&
      !any(grepl("어댑터 실패", r5$out, fixed = TRUE)))
    ok("E8 n·c = 1 → EW(유일 가능해) · 진단 줄 active=5 capbind=5 · 폴백 호명 없음") else ng("E8 n·c = 1", paste(c(if (inherits(r5$v, "error")) conditionMessage(r5$v), r5$out), collapse = " | "))
  ## E9 — 미세 양수 잔차 없음: 양수로 세는 수 = 진단 줄 문턱(1e-8)으로 세는 수(하네스 Weight != 0 이 보유로 세는 수와 같게)
  if (sum(wo > 0) == sum(wo > 1e-8) && sum(w6n$v > 0) == sum(w6n$v > 1e-8)) ok(sprintf("E9 미세 양수 잔차 0(양수 %d = 문턱 위 %d)", sum(wo > 0), sum(wo > 1e-8))) else
    ng("E9 미세 양수 잔차", paste(sum(wo > 0), sum(wo > 1e-8), sum(w6n$v > 0), sum(w6n$v > 1e-8)))
  ## E10 — 5종 상한 꼭짓점(n > 5): 저베타 · 저잡음 5종이 지배 → 5종 상한 0.20 · 나머지 0 이 해(양의 승수 — 계획이 오류 없이 꼭짓점을 낸다)
  set.seed(9L); m7 <- rnorm(252L, 0, 0.012)
  X7 <- cbind(sapply(1:5, function(j) 1.0 * m7 + rnorm(252L, 0, 0.004)), sapply(1:2, function(j) 1.4 * m7 + rnorm(252L, 0, 0.03)))
  colnames(X7) <- sprintf("V%02d", 1:7)
  r7 <- quiet(OP(list(R = X7, assets = colnames(X7), ub = 1, decision_date = as.Date("2010-05-31"))))
  if (!inherits(r7$v, "error") && sum(abs(r7$v - 0.2) < 1e-8) == 5L && sum(r7$v > 1e-8) == 5L && !any(grepl("어댑터 실패", r7$out, fixed = TRUE)))
    ok("E10 꼭짓점 — 5종 상한 0.20 · 2종 0(오류 · 폴백 없음)") else ng("E10 꼭짓점", paste(c(if (inherits(r7$v, "error")) conditionMessage(r7$v) else round(r7$v, 4), r7$out), collapse = " | "))
  ## E11 — 척도 정규화 불변: 같은 계획을 Σ̃ 원척도로 풀어 정규화한 해 = 어댑터 해(Σ̃/s0 로 풀어도 해는 비례만 바뀐다)
  n20 <- ncol(X); Am20 <- cbind(diag(n20), WC_UB * matrix(1, n20, n20) - diag(n20))
  raw20 <- pmax(quadprog::solve.QP(cc$Sigma, rep(1, n20), Am20, rep(0, 2L * n20))$solution, 0)
  if (max(abs(raw20 / sum(raw20) - rn)) < 1e-6) ok(sprintf("E11 척도 정규화 불변(원척도 해와 차 %.1e)", max(abs(raw20 / sum(raw20) - rn)))) else
    ng("E11 척도 정규화가 해를 바꿨다", sprintf("%.2e", max(abs(raw20 / sum(raw20) - rn))))
}

cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
cat(sprintf('{"test":"eigen_clean_markowitz","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL > 0L) 1L else 0L)
