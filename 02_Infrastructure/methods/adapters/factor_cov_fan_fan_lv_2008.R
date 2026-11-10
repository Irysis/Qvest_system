# factor_cov_fan_fan_lv_2008.R — 요인 모형 공분산 Σ = BΩBᵀ + D (시그마 어댑터 · 2026-11-10 레인 E3)
#
# 원문: Fan, Fan & Lv (2008) 'High dimensional covariance matrix estimation using a factor model', J. Econometrics 147(1):186-197
#   https://doi.org/10.1016/j.jeconom.2008.09.017 — 관측 요인 시계열 회귀로 B · D, Ω = cov(f). 역행렬(포트폴리오 구성에 쓰이는 양)의
#   추정 오차가 표본 공분산보다 작다(정리 3 계열).
# 구현 = 02_Infrastructure/reinforcement/rf_factor_cov.R::rfc_sigma_ctx — ctx$factor_returns()(ctx 공급자 · rfc_register_ctx_provider)가
#   있으면 관측 FF6 요인(ts), 없으면 주성분 요인 + Bai-Ng IC_p2(pca)로 떨어지고 진단 줄에 mode 를 적는다(조용히 바꾸지 않는다).
# 변형 = 설정 adapter_variant(base · downside · dd_state) — 이 파일은 base 고정. 위기 조건부 판은 별도 method_id 로 등재할 것(시행 집합 회계).
# PIT: ctx$R = 호출자가 Date < 결정일로 자른 창 · 요인 수익도 Date < decision_date 로 자른다(rfc_sigma_ctx).
# 진단 줄 '[fcov] d=… n=… T=… model=… K=… variant=… align=… kappa=… fb=…'.

.fcov_root <- local({
  m <- file.path("02_Infrastructure", "reinforcement", "rf_factor_cov.R")
  r <- NULL
  for (k in c("QM_ROOT", "CLAUDE_PROJECT_DIR")) { v <- gsub("\\\\", "/", Sys.getenv(k, "")); if (is.null(r) && nzchar(v) && file.exists(file.path(v, m))) r <- v }
  if (is.null(r)) { d <- getwd(); for (i in 1:6) { if (is.null(r) && file.exists(file.path(d, m))) r <- d; d <- dirname(d) } }
  if (is.null(r)) stop("[fcov] 루트를 찾지 못했다")
  r
})
source(file.path(.fcov_root, "02_Infrastructure", "reinforcement", "rf_factor_cov.R"), local = TRUE)
.FCOV_CFG <- rfc_config(file.path(.fcov_root, "02_Infrastructure", "reinforcement", "rf_factor_cov.json"))
FCOV_VARIANT <- "base"

sigma_estimate <- function(ctx) {
  o <- rfc_sigma_ctx(ctx, .FCOV_CFG, variant = FCOV_VARIANT)
  dd <- if (is.null(ctx$decision_date)) "NA" else format(ctx$decision_date)
  cat(sprintf("[fcov] d=%s n=%d T=%d model=%s K=%d variant=%s align=%s kappa=%.3g fb=%s\n", dd, length(ctx$assets), nrow(ctx$R),
              o$model, o$K, o$variant, o$diag$align %||% "?", o$diag$kappa_after, ifelse(is.na(o$diag$fallback %||% NA), "none", o$diag$fallback)))
  S <- o$Sigma[ctx$assets, ctx$assets]
  S
}
