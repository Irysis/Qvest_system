# qepm_MVO__shr_lw_nls.R — **생성된 형제** (generate_weight_variants.R · 손편집 금지)
#
# 부모   : qepm:MVO
# 규칙   : shrinkage_lift
# 축     : estimator = lw_nls
#
# ★이 파일은 부모를 **편집하지 않는다** — 자기 Σ 를 만들고 부모 규칙을 그 위에서 부른다.
#   기존 23종에 대한 회귀 위험 0. 제약(long-only · Σw=1 · w≤ub)은 wrap_adapter 가 강제한다.
# ★성과를 읽지 않는다 — 이 파일 어디에도 측정 필드가 없다(admit_generated 가 정적 스캔한다).

.gen_root_a <- function() {
  for (k in c("CLAUDE_PROJECT_DIR", "QM_ROOT")) {
    v <- Sys.getenv(k, "")
    if (nzchar(v) && dir.exists(file.path(v, "06_Registry"))) return(v)
  }
  if (dir.exists("06_Registry")) return(getwd())
  "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
}
if (!exists("gen_sigma", mode = "function"))
  source(file.path(.gen_root_a(), "02_Infrastructure/methods/adapters/gen", "_gen_sigma.R"))

# ctx$R -> long (Date, Ticker, Ret). 순서만 보존하는 의사 날짜(weight_catalog.R::.ctx_ret_dt 동형).
.ctx_ret_dt_local <- function(ctx) {
  R <- ctx$R; anchor <- tryCatch(as.Date(ctx$decision_date), error = function(e) as.Date("2000-01-01"))
  if (is.na(anchor)) anchor <- as.Date("2000-01-01")
  d <- anchor - rev(seq_len(nrow(R)))
  data.table::data.table(Date = rep(d, times = ncol(R)),
                         Ticker = rep(colnames(R), each = nrow(R)), Ret = as.numeric(R))
}

.qepm_dispatch <- function(nm, ...) {
  e <- get0(".GEN_QEPM_ENV", ifnotfound = NULL)
  if (is.null(e)) {
    e <- new.env(parent = globalenv())
    suppressWarnings(suppressMessages(sys.source(
      file.path(.gen_root_a(), "02_Infrastructure/portfolio/weight_method_registry.R"), envir = e)))
    for (f in c("mean_variance_optimizer", "hrp_core", "advanced_weights", "protection_strategy")) {
      fp <- file.path(.gen_root_a(), "02_Infrastructure/portfolio", paste0(f, ".R"))
      if (file.exists(fp)) suppressWarnings(suppressMessages(try(sys.source(fp, envir = e), silent = TRUE)))
    }
    assign("load_weight_infra", function() invisible(NULL), envir = e)
    assign(".GEN_QEPM_ENV", e, envir = globalenv())
  }
  r <- get("dispatch_weight_method", envir = e)(nm, ...)
  if (is.list(r) && isTRUE(r$infeasible)) stop(sprintf("dispatch infeasible: %s", r$reason))
  w <- if (is.list(r)) r$weights else r
  if (is.null(w)) stop("dispatch 가 weights 를 내지 않음")
  w
}

.parent_adapter <- function(rel) {
  e <- new.env(parent = globalenv())
  sys.source(file.path(.gen_root_a(), rel), envir = e)
  get("method_weights", envir = e)
}

method_weights <- function(ctx) {
  a <- ctx$assets
  S <- gen_sigma(ctx$R[, a, drop = FALSE], "lw_nls")
  w <- .qepm_dispatch("MVO", alpha = ctx$mu, cov_matrix = S, returns = ctx$R,
                 bounds = c(0, if (is.null(ctx$ub)) 0.20 else ctx$ub),
                 max_names = 25L, min_names = min(15L, length(a)),
                 hhi_cap = max(0.10, 1.05 / length(a)))
  # 이름이 있으면 **이름으로** 정렬한다 — max_names 로 support 를 제한하는 부모(MVO 계열)는
  #   선택된 종목만 돌려주므로 미선택분은 0 이 맞다(길이 불일치로 죽이면 정상 동작을 거부한다).
  #   이름이 없으면 하네스 계약(backtest_harness.R:1186)대로 **위치 기반**이다.
  if (!is.null(names(w))) {
    v <- suppressWarnings(as.numeric(w[a])); v[!is.finite(v)] <- 0; w <- v
  } else w <- as.numeric(w)
  if (length(w) != length(a)) stop(sprintf("산출 길이 불일치: %d vs %d", length(w), length(a)))
  stats::setNames(w, a)
}
