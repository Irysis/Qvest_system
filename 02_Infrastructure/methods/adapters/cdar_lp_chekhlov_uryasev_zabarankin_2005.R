# cdar_lp_chekhlov_uryasev_zabarankin_2005.R — 기대수익 최대화 s.t. CDaR ≤ ν (낙폭 예산 구성 · 2026-11-10 레인 E3)
#
# 원문: Chekhlov, Uryasev & Zabarankin (2005) 'Drawdown Measure in Portfolio Optimization', IJTAF 8(1):13-58
#   https://doi.org/10.1142/S0219024905002767 — §3 CDaR 선형화 · 주 문제 = 기대수익 최대화 s.t. CDaR ≤ ν·자본.
# 구현 = 02_Infrastructure/reinforcement/rf_cdar_construct.R::rcd_construct (희소 LP · lpSolve 단체법 · 결정론). 이 파일은 ctx 다리다.
# KR 사상: μ = ctx$mu(엔진 점수 · 척도 무관) · 시나리오 = ctx$R(엔진이 Date < 신호일로 자른 창) · ν = 같은 후보 EW 의 CDaR × κ(1.0)
#   · 롱온리 · Σw = 1(카탈로그 계약 — wrap_adapter) · 종목별 상한 없음(고정 축) · ≤ 25종(가지치기).
#   ★현행 qepm:CDaR_LP 와 다르다: 그쪽은 최소 CDaR 끝점(μ 무시), 여기는 점수를 낙폭 예산 안에서 최대로 산다.
# PIT: ctx 밖을 보지 않는다. 진단 줄 '[cdar_cuz] d=… n=… T=… mode=… nu=… cdar=… active=… maxw=… effn=… sec=… fb=…'.

.cuz_root <- local({
  m <- file.path("02_Infrastructure", "reinforcement", "rf_cdar_construct.R")
  r <- NULL
  for (k in c("QM_ROOT", "CLAUDE_PROJECT_DIR")) { v <- gsub("\\\\", "/", Sys.getenv(k, "")); if (is.null(r) && nzchar(v) && file.exists(file.path(v, m))) r <- v }
  if (is.null(r)) { d <- getwd(); for (i in 1:6) { if (is.null(r) && file.exists(file.path(d, m))) r <- d; d <- dirname(d) } }
  if (is.null(r)) stop("[cdar_cuz] 루트를 찾지 못했다")
  r
})
source(file.path(.cuz_root, "02_Infrastructure", "reinforcement", "rf_cdar_construct.R"), local = TRUE)
.CUZ_CFG <- rcd_config(file.path(.cuz_root, "02_Infrastructure", "reinforcement", "rf_cdar_construct.json"))
# 판 표식(P-2b · 2026-11-10): 이 arm 은 합 ≤ 1 정규형을 쓸 수 있다. 현금은 칸이 weighting.allow_cash = true 일 때(셀 엔진이
#   ctx$allow_cash 를 싣는다)만 통과하고 그때 LP 예산도 Σw ≤ 1. opt-in 이 없으면 Σw = 1(종전과 같은 해). 근거 = 측정 축 MC5(축 완화 아님).
METHOD_BUDGET <- "le"

method_weights <- function(ctx) {
  a <- ctx$assets
  if (length(a) < 3L) stop("자산 3종 미만 — 하네스가 먼저 EW 로 처리한다")
  R <- as.matrix(ctx$R)[, a, drop = FALSE]
  mu <- if (is.null(ctx$mu)) NULL else { v <- suppressWarnings(as.numeric(ctx$mu[a])); v[!is.finite(v)] <- 0; stats::setNames(v, a) }
  # μ 없음 = 최소 CDaR 끝점 — Σw ≤ 1 이면 w = 0 으로 퇴화하므로 그 경우는 항상 eq
  bud <- if (isTRUE(ctx$allow_cash) && !is.null(mu)) "le" else "eq"
  # ν 규칙(2026-11-10) — 칸이 ctx$cdar_nu_rule 를 싣지 않으면 설정값(ew_candidates · 종전과 비트 동일).
  #   "bench" = 같은 창 공표 KOSPI200 일별 수익(ctx$bench_ret · Date < 결정일)의 CDaR × κ(1) — 등급 CR '강함'(전략 MDD ≤ 같은 창 벤치 MDD)과 같은 기준.
  #   벤치 부재 · 날짜 교집합 부족 = 멈춤(ew 로 조용히 내려가지 않는다).
  nr <- if (is.null(ctx$cdar_nu_rule)) NULL else rcd_nu_rule(ctx$cdar_nu_rule)
  if (identical(nr, "bench")) {
    al <- rcd_bench_align(R, ctx$R_dates, ctx$bench_ret, ctx$decision_date, .CUZ_CFG$alpha)
    o <- rcd_construct(al$R, .CUZ_CFG, mu = mu, budget = bud, bench = al$b, nu_rule = "bench")
  } else {
    o <- if (is.null(nr)) rcd_construct(R, .CUZ_CFG, mu = mu, budget = bud)
         else rcd_construct(R, .CUZ_CFG, mu = mu, budget = bud, nu_rule = nr)
  }
  dd <- if (is.null(ctx$decision_date)) "NA" else format(ctx$decision_date)
  cat(sprintf("[cdar_cuz] d=%s n=%d T=%d nu_rule=%s mode=%s budget=%s cash=%.4f nu=%.6f cdar=%.6f active=%d maxw=%.4f effn=%.2f sec=%.3f fb=%s\n",
              dd, length(a), nrow(R), nr %||% .CUZ_CFG$nu_rule, o$mode, o$budget, o$cash, o$nu %||% NA_real_, o$cdar, o$n_active, max(o$w), o$effn, o$sec,
              ifelse(is.na(o$fallback), "none", o$fallback)))
  o$w
}
