#==============================================================================
# QEPM Weight Method Registry — v1.0
# 2026-04-23 Session 69 Day 1 — Optimizer Research Agent dispatch
#
# 목적:
#   Optimizer Agent가 호출할 weight 방법론 registry.
#   각 방법론은 (alpha, cov, constraints) → (weights, metrics) 표준 인터페이스.
#
# 새 방법론 추가 시 이 파일에 method 추가 + source() 경로 등록.
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
})

# ─── 기존 infra 로드 ─────────────────────────────────────
WEIGHT_METHODS_BASE <- list(
  mvo_registry = "02_Infrastructure/portfolio/mean_variance_optimizer.R",
  hrp_core = "02_Infrastructure/portfolio/hrp_core.R",
  advanced_weights = "02_Infrastructure/portfolio/advanced_weights.R",
  protection_strategy = "02_Infrastructure/portfolio/protection_strategy.R"
)

load_weight_infra <- function() {
  for (nm in names(WEIGHT_METHODS_BASE)) {
    path <- WEIGHT_METHODS_BASE[[nm]]
    if (file.exists(path)) {
      source(path, local = FALSE)
    }
  }
}

# ─── Method Registry ────────────────────────────────────
# 각 entry: list(fn=..., family=..., requires=c("alpha","cov","returns"), description=...)
WEIGHT_METHOD_REGISTRY <- list(
  "MVO" = list(
    fn = "mvo_weights",
    family = "classical",
    requires = c("alpha", "cov"),
    description = "Mean-Variance Optimization: max x'α - λ/2 x'Σx. μ + Σ + λ 정통.",
    hyperparams = c("lambda", "phi")
  ),
  "MVO_grid" = list(
    fn = "mvo_grid_search",
    family = "classical",
    requires = c("alpha", "cov"),
    description = "MVO with λ/φ grid search",
    hyperparams = c("lambda_grid", "phi_grid")
  ),
  "HRP" = list(
    fn = "hrp_weights",
    family = "risk_parity",
    requires = c("cov"),
    description = "Hierarchical Risk Parity (López de Prado 2016)",
    hyperparams = c("linkage_method", "cov_method")
  ),
  "ERC" = list(
    fn = "erc_weights",
    family = "risk_parity",
    requires = c("cov"),
    description = "Equal Risk Contribution",
    hyperparams = c()
  ),
  "CVaR_LP" = list(
    fn = "calc_cvar_weights",
    family = "tail_aware",
    requires = c("returns"),
    description = "CVaR LP (Rockafellar-Uryasev)",
    hyperparams = c("alpha_level")
  ),
  "CDaR_LP" = list(
    fn = "calc_cdar_weights",
    family = "tail_aware",
    requires = c("returns"),
    description = "CDaR LP (drawdown-at-risk)",
    hyperparams = c("alpha_level")
  ),
  "MaxDiv" = list(
    fn = "calc_maxdiv_weights",
    family = "entropy",
    requires = c("cov"),
    description = "Max Diversification",
    hyperparams = c()
  ),
  "EntropyPooling" = list(
    fn = "calc_entropy_pooling_weights",
    family = "entropy",
    requires = c("returns", "views"),
    description = "Entropy Pooling (Meucci)",
    hyperparams = c("confidence")
  ),
  "BlackLitterman" = list(
    fn = "bl_weights",
    family = "classical",
    requires = c("prior_alpha", "views", "cov"),
    description = "Black-Litterman (prior + views)",
    hyperparams = c("tau", "lambda")
  ),
  "Protection_ES" = list(
    fn = "calc_protection_es_weights",
    family = "tail_aware",
    requires = c("returns"),
    description = "Floor + ES LP (Pfaff Ch.13)",
    hyperparams = c("floor", "es_budget")
  ),
  "PPO_RL" = list(
    fn = "ppo_rl_weights",
    family = "reinforcement_learning",
    requires = c("returns", "alpha", "cov"),
    description = "PPO policy gradient on portfolio returns",
    hyperparams = c("n_episodes", "lr")
  ),
  "Genetic" = list(
    fn = "genetic_weights",
    family = "evolutionary",
    requires = c("alpha", "cov", "returns"),
    description = "Genetic algorithm weight search",
    hyperparams = c("pop_size", "n_generations")
  ),
  "Ensemble" = list(
    fn = "ensemble_weights",
    family = "ensemble",
    requires = c("method_list"),
    description = "Meta-weight SR 최대화",
    hyperparams = c("method_list", "meta_lambda")
  )
)

# ─── Registry 조회 ───────────────────────────────────────
list_methods <- function(family = NULL) {
  if (is.null(family)) {
    return(names(WEIGHT_METHOD_REGISTRY))
  }
  names(WEIGHT_METHOD_REGISTRY)[
    sapply(WEIGHT_METHOD_REGISTRY, function(m) m$family == family)
  ]
}

describe_method <- function(method_name) {
  if (!method_name %in% names(WEIGHT_METHOD_REGISTRY)) {
    stop(sprintf("[weight_method_registry] Unknown method: %s", method_name))
  }
  WEIGHT_METHOD_REGISTRY[[method_name]]
}

# ─── Dispatch (단일 방법론 실행) ─────────────────────────
dispatch_weight_method <- function(method_name,
                                     alpha = NULL,
                                     cov_matrix = NULL,
                                     returns = NULL,
                                     bounds = c(0, 0.10),
                                     max_names = 20,
                                     ...) {
  spec <- describe_method(method_name)
  fn_name <- spec$fn

  # Infra 로드
  load_weight_infra()

  if (!exists(fn_name, mode = "function")) {
    warning(sprintf("[dispatch] Function '%s' not found (method=%s)", fn_name, method_name))
    return(list(weights = NULL, method = method_name, infeasible = TRUE,
                reason = sprintf("function_missing: %s", fn_name)))
  }

  fn <- get(fn_name)

  # 인자 조립 (method별 상이)
  args <- list(...)
  if ("alpha" %in% spec$requires) args$alpha <- alpha
  if ("cov" %in% spec$requires) args$cov_matrix <- cov_matrix
  if ("returns" %in% spec$requires) args$returns <- returns
  args$bounds <- bounds
  args$max_names <- max_names

  tryCatch(
    do.call(fn, args),
    error = function(e) {
      warning(sprintf("[dispatch] %s failed: %s", method_name, conditionMessage(e)))
      list(weights = NULL, method = method_name, infeasible = TRUE,
           reason = conditionMessage(e))
    }
  )
}

# ─── 전체 방법론 비교 (Optimizer Agent 자율 탐색 보조) ───
compare_all_methods <- function(alpha, cov_matrix, returns = NULL,
                                  bounds = c(0, 0.10), max_names = 20,
                                  methods = NULL) {
  if (is.null(methods)) {
    # returns 없으면 tail-aware는 제외
    methods <- if (is.null(returns)) {
      c("MVO", "HRP", "ERC", "MaxDiv")
    } else {
      c("MVO", "HRP", "ERC", "MaxDiv", "CVaR_LP", "CDaR_LP")
    }
  }

  cat(sprintf("[compare_all_methods] testing %d methods\n", length(methods)))

  results <- list()
  for (m in methods) {
    cat(sprintf("  %s ... ", m))
    r <- dispatch_weight_method(m,
                                 alpha = alpha,
                                 cov_matrix = cov_matrix,
                                 returns = returns,
                                 bounds = bounds,
                                 max_names = max_names)
    if (is.null(r$infeasible) || !r$infeasible) {
      ir <- r$expected_information_ratio %||% NA
      cat(sprintf("IR=%.3f\n", ir %||% NA))
    } else {
      cat(sprintf("INFEASIBLE (%s)\n", r$reason %||% "unknown"))
    }
    results[[m]] <- r
  }

  # IR 기준 정렬
  irs <- sapply(results, function(r) r$expected_information_ratio %||% NA)
  ordered <- order(irs, decreasing = TRUE, na.last = TRUE)

  cat("\n=== Method Comparison (by IR) ===\n")
  for (i in ordered) {
    m <- names(results)[i]
    ir <- irs[i]
    cat(sprintf("  %s: IR=%s\n", m, if (is.na(ir)) "N/A" else sprintf("%.3f", ir)))
  }

  list(
    results = results,
    best_method = names(results)[ordered[1]],
    best_weights = results[[ordered[1]]]$weights,
    ranking = names(results)[ordered]
  )
}

`%||%` <- function(a, b) if (!is.null(a) && !is.na(a)) a else b

cat("[weight_method_registry.R] Loaded.\n")
cat(sprintf("  %d methods registered: %s\n",
            length(WEIGHT_METHOD_REGISTRY),
            paste(names(WEIGHT_METHOD_REGISTRY), collapse = ", ")))
cat("Functions: list_methods(family=NULL), describe_method(name),\n")
cat("           dispatch_weight_method(method_name, ...), compare_all_methods(...)\n")
