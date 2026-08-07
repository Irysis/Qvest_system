#!/usr/bin/env Rscript
# test_method_adapter_contract.R — 논문 유래 method 어댑터 계약 위반 주입 테스트 ((b)안, 2026-08-08).
#
# (b)안의 안전 주장은 하나다:
#   **"어댑터가 아무리 이상해도 Production Constraints 를 깰 수 없다"**
#   — long-only(w≥0) / Σw=1 / w≤UB 를 wrap_adapter 가 강제하기 때문.
# 그 주장이 참인지를 **일부러 위반하는 어댑터를 주입해서** 확인한다. 주장만 문서에 적고
# 검사하지 않으면, 어느 날 조용히 깨져도 아무도 모른다.
#
# ★교훈 반영: 픽스처가 한 제약을 먼저 발화시키면 나머지 제약은 재지도 못한 채 초록이 된다
#   ([[project-injection-fixture-confounding-20260802]] — max_names/long_only/upper_bound/sum_w
#   4종이 전부 돌연변이 생존이었는데 cash 정합이 그늘을 만들어 초록이었다).
#   그래서 여기서는 **주입 1건당 제약 1개**만 건드리고, 각 축을 개별로 단언한다.
#
# ★clean 통과 선확인: 정상 어댑터가 먼저 통과해야 "위반 검거"가 의미를 갖는다
#   (모든 입력을 거부하는 래퍼도 위반 주입은 다 잡는다 — 그건 검사 사망이지 성공이 아니다).

.root <- local({
  .marker <- file.path("02_Infrastructure", "methods", "method_registry.R")
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", a[grep("^--file=", a)])
  if (length(f)) {
    d <- dirname(normalizePath(f[1], winslash = "/", mustWork = FALSE))
    r <- normalizePath(file.path(d, "..", ".."), winslash = "/", mustWork = FALSE)
    if (file.exists(file.path(r, .marker))) return(r)
  }
  for (k in c("CLAUDE_PROJECT_DIR", "QM_ROOT")) {
    v <- Sys.getenv(k, "")
    if (nzchar(v) && file.exists(file.path(v, .marker))) return(v)
  }
  cand <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
  if (file.exists(file.path(cand, .marker))) cand else getwd()
})
setwd(.root)

PASS <- 0; FAIL <- 0
ok  <- function(m) { PASS <<- PASS + 1; cat(sprintf("  [PASS] %s\n", m)) }
bad <- function(m, d) { FAIL <<- FAIL + 1; cat(sprintf("  [FAIL] %s — %s\n", m, d)) }

suppressWarnings(suppressMessages({
  source("02_Infrastructure/portfolio/strategy_tilt_weights.R")   # normalize_long_only
  source("02_Infrastructure/methods/method_registry.R")
}))

# ── 기능 프로브: 의존 심볼이 실제로 있는가. 없으면 이 검사는 아무것도 재지 않는다. ──
for (sym in c("normalize_long_only", "wrap_adapter", "load_method_adapters", "method_triage")) {
  if (!exists(sym)) { cat(sprintf("FATAL: `%s` 부재 — 검사가 성립하지 않는다.\n", sym)); quit(status = 2) }
}

UB <- 0.20
A  <- paste0("A", sprintf("%02d", 1:25))          # 25 종목
ctx <- list(assets = A, ub = UB, lookback_days = 250,
            Sigma = { S <- diag(25); dimnames(S) <- list(A, A); S },
            R = matrix(rnorm(250 * 25, 0, 0.02), nrow = 250, dimnames = list(NULL, A)),
            mu = setNames(seq(1, 0.1, length.out = 25), A),
            decision_date = as.Date("2020-01-02"), eval_date = as.Date("2020-01-31"))

# 제약 축별 검사기 — **개별로** 본다(한 축이 다른 축을 가리지 않도록).
chk <- list(
  long_only   = function(w) all(w >= -1e-9),
  sum_one     = function(w) abs(sum(w) - 1) < 1e-6,
  upper_bound = function(w) all(w <= UB + 1e-9),
  finite      = function(w) all(is.finite(w)),
  named       = function(w) identical(sort(names(w)), sort(A))
)

run <- function(fn, id = "probe") {
  g <- wrap_adapter(fn, id, ub = UB)
  utils::capture.output(res <- g(ctx))
  res
}

cat("== 어댑터 계약 위반 주입 테스트 ==\n\n")

cat("[0] clean 선확인 — 정상 어댑터가 통과해야 위반 검거가 의미를 가진다\n")
w0 <- run(function(ctx) setNames(pmax(as.numeric(ctx$mu[ctx$assets]), 0), ctx$assets), "clean")
for (nm in names(chk)) {
  if (isTRUE(chk[[nm]](w0))) ok(sprintf("clean · %s", nm))
  else bad(sprintf("clean · %s", nm), "정상 어댑터가 계약을 못 지킴 = 하네스 결함")
}
if (max(w0) > 1/25 + 1e-9) ok("clean · 실제로 기울어짐(EW 폴백이 아님)")  else bad("clean · tilt", "EW 와 구별 안 됨 — 래퍼가 입력을 무시할 가능성")

# ── 위반 주입: 1건당 제약 1개 ────────────────────────────────────────────────
INJ <- list(
  list(n = "T1 음수 비중(롱숏 시도)", f = function(ctx) { v <- rep(1, 25); v[1:5] <- -3; setNames(v, ctx$assets) }),
  list(n = "T2 상한 초과(1종목 몰빵)",  f = function(ctx) { v <- rep(1e-6, 25); v[1] <- 1e6; setNames(v, ctx$assets) }),
  list(n = "T3 합≠1 (스케일 100배)",    f = function(ctx) setNames(rep(4, 25), ctx$assets)),
  list(n = "T4 NA/Inf 산출",            f = function(ctx) { v <- rep(1, 25); v[3] <- NA; v[7] <- Inf; setNames(v, ctx$assets) }),
  list(n = "T5 이름 없는 벡터",          f = function(ctx) rep(1, 25)),
  list(n = "T6 길이 불일치(10개만)",     f = function(ctx) setNames(rep(1, 10), ctx$assets[1:10])),
  list(n = "T7 전량 0",                  f = function(ctx) setNames(rep(0, 25), ctx$assets)),
  list(n = "T8 전량 음수",               f = function(ctx) setNames(rep(-1, 25), ctx$assets)),
  list(n = "T9 예외 throw",              f = function(ctx) stop("의도적 실패")),
  list(n = "T10 NULL 반환",              f = function(ctx) NULL)
)
cat("\n[1] 위반 주입 10종 — 전부 유효 비중으로 교정돼야 한다\n")
for (t in INJ) {
  w <- tryCatch(run(t$f, "inj"), error = function(e) e)
  if (inherits(w, "error")) { bad(t$n, sprintf("래퍼가 예외를 흘림: %s", conditionMessage(w))); next }
  viol <- names(chk)[!vapply(names(chk), function(nm) isTRUE(chk[[nm]](w)), logical(1))]
  if (!length(viol)) ok(sprintf("%s → 교정됨 (max=%.3f, sum=%.6f)", t$n, max(w), sum(w)))
  else bad(t$n, sprintf("제약 위반 잔존: %s", paste(viol, collapse = ", ")))
}

# ── 돌연변이: 래퍼에서 제약 강제를 빼면 위반이 **통과해야** 한다 ──
#   ★치환으로 무력화한다(구간 삭제는 NameError 를 내고 그게 '검거'로 오독된다).
cat("\n[2] 돌연변이 — 강제를 빼면 T1/T2/T3 가 살아남아야 검사가 유효\n")
naive <- function(fn) function(ctx) { v <- fn(ctx); w <- suppressWarnings(as.numeric(v[ctx$assets])); names(w) <- ctx$assets; w }
survived <- 0
for (t in INJ[1:3]) {
  w <- tryCatch(naive(t$f)(ctx), error = function(e) NULL)
  if (is.null(w)) next
  viol <- names(chk)[!vapply(names(chk), function(nm) isTRUE(chk[[nm]](w)), logical(1))]
  if (length(viol)) { survived <- survived + 1; ok(sprintf("돌연변이 %s → 위반 잔존(%s) = 검사 판별력 있음", t$n, paste(viol, collapse=","))) }
  else bad(sprintf("돌연변이 %s", t$n), "강제를 뺐는데도 위반이 안 생김 — 픽스처가 제약을 못 건드림(교락)")
}
if (survived >= 3) ok(sprintf("돌연변이 판별력 %d/3", survived)) else bad("돌연변이 판별력", sprintf("%d/3 (<3)", survived))

# ── 실물 어댑터: 레지스트리에 등재된 것이 실제로 로드·동작하는가 ──
cat("\n[3] 실물 레지스트리 — implemented 어댑터가 로드되고 계약을 지키는가\n")
utils::capture.output(ads <- load_method_adapters(route = "optimizer", ub = UB))
if (!length(ads)) {
  bad("레지스트리 로드", "implemented 어댑터 0건 — (b)안이 배선되지 않은 상태")
} else {
  ok(sprintf("로드 %d건: %s", length(ads), paste(names(ads), collapse = ", ")))
  for (id in names(ads)) {
    utils::capture.output(w <- ads[[id]](ctx))
    viol <- names(chk)[!vapply(names(chk), function(nm) isTRUE(chk[[nm]](w)), logical(1))]
    if (length(viol)) bad(sprintf("실물 %s", id), paste(viol, collapse = ", "))
    else ok(sprintf("실물 %s → 유효 (max=%.3f, sum=%.6f, n>0=%d)", id, max(w), sum(w), sum(w > 1e-8)))
    # ★EW 와 구별되는가 — 폴백만 타고 있으면 "돌았다"가 아니라 "아무것도 안 했다"이다.
    if (max(abs(w - 1/25)) < 1e-8) bad(sprintf("실물 %s 판별", id), "EW 와 동일 — 폴백만 탄 것으로 의심")
    else ok(sprintf("실물 %s → EW 와 구별됨", id))
  }
}

cat("\n[4] triage 보고 — 등재가 아니라 처분이 실리는가\n")
tri <- method_triage("optimizer")
if (!length(tri)) bad("triage", "optimizer route 0건")  else {
  vs <- vapply(tri, function(x) as.character(x$verdict), character(1))
  if (all(nzchar(vs))) ok(sprintf("optimizer %d건 전부 verdict 보유: %s", length(tri), paste(unique(vs), collapse=", ")))
  else bad("triage", "verdict 결측 항목 존재")
  blocked <- Filter(function(x) !identical(x$verdict, "implemented"), tri)
  if (!length(blocked)) ok("blocked 항목 없음")
  else if (all(vapply(blocked, function(x) !is.na(x$blocker) && nzchar(x$blocker), logical(1))))
    ok(sprintf("blocked %d건 전부 blocker 명시", length(blocked)))
  else bad("triage", "blocked 인데 사유가 빈 항목 존재 — 침묵 기각")
}

cat(sprintf("\nFINAL: passed=%d failed=%d\n", PASS, FAIL))
quit(status = if (FAIL > 0) 1 else 0)
