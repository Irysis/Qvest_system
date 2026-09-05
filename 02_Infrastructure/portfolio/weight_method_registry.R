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
  ),
  # v8.x 부록 — Direct Portfolio Learning (You-Zhang 2025). feasibility pilot 단계.
  # 실제 weight 산출은 Python(02_Infrastructure/ml_pipeline/dpl_portfolio.py) cvxpylayers
  # differentiable QP layer가 담당 — R fn은 venv subprocess bridge(미구현 시 infeasible 반환).
  "DPL" = list(
    fn = "dpl_weights_cvxpylayers",
    family = "deep_learning",
    requires = c("alpha", "cov", "returns"),
    description = "Direct Portfolio Learning — features→μ̂→differentiable convex QP layer→weights, realized net Sharpe end-to-end (cvxpylayers, Python venv qvest_ml). long-only/Σw=1/[0,0.20]/≤25 active.",
    hyperparams = c("lambda_risk", "gamma_turnover", "lr", "n_epochs", "lookback")
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

# ─── 하네스 규약 표적 번역 (2026-09-05) ──────────────────────────────────────
# 왜 있나: 이 레지스트리의 표준 조립은 (alpha, cov_matrix, returns, bounds, max_names) 인데
#   advanced_weights.R 의 tail-aware 3종 — calc_cdar_weights(CDaR_LP) · calc_cvar_weights(CVaR_LP)
#   · calc_maxdiv_weights(MaxDiv) — 은 backtest_harness 규약 (tickers, ret_dt, n_days, max_w, …)
#   이고 `...` 도 없다. do.call 이 "unused arguments (returns = …)" 로 죽고, 카탈로그 wrapper 가
#   EW 로 폴백해 probe.ok=FALSE → weight_catalog_arms 가 unverified 로 실효 강등 →
#   rf_cell_engine "카탈로그 arm 부재" (실측 2026-09-05: RP_20260904_163647_18444_rescued_rulefast_promo2
#   B2_6 n=11 미측정 — "낙폭 경로를 직접 목적함수로 쓰면 MDD 가 내려가는가" 가 미결로 남았다).
#   표적 시그니처는 바꾸지 않는다 — 같은 함수를 lean 축(backtest_harness.R)이 (tickers, ret_dt)
#   로 부른다. 조립층(이 파일)이 번역한다.
# ★인식 조건 = formals 에 tickers ∧ ret_dt **둘 다**. 그 외 시그니처는 번역하지 않는다 —
#   모르는 인자를 조용히 떨어뜨리면 "기본값으로 돌았다" 가 "돌았다" 로 위장한다. 실패는 소리나게
#   (unused arguments 그대로 → infeasible → wrapper 가 호명하고 EW 폴백 → probe 가 강등).
#   08_Tests/contracts/test_weight_catalog.R (h) 가 양방향(3종 통과 · 틀린 이름 강등)으로 잰다.
# ★PIT: 표현 변환이지 시점 변환이 아니다(weight_catalog.R::.ctx_ret_dt 와 같은 규약).
#   returns 는 호출자가 이미 t-1 로 잘라 준 창(rf_cell_engine: `Date < d`)이고, 표적이 Date 로
#   하는 일은 `tail(sort(unique(Date)), n_days)` 절단뿐이다. rownames 가 실제 날짜면 그대로 쓰고,
#   없으면 행 순서를 보존하는 의사 날짜(오름차순 라벨)를 붙인다. n_days 는 호출자가 준 창 전체
#   (nrow) — 표적 기본값 120 으로 창을 다시 자르지 않는다(호출자의 lookback 이 축이다).
.wmr_is_harness_convention <- function(fn_formals) all(c("tickers", "ret_dt") %in% fn_formals)

.wmr_returns_to_ret_dt <- function(returns) {
  R <- as.matrix(returns)
  if (!nrow(R) || !ncol(R)) stop("harness_convention: returns 행렬이 비어 있다")
  tk <- colnames(R)
  if (is.null(tk) || any(is.na(tk) | !nzchar(tk)))
    stop("harness_convention: returns 에 colnames(티커) 가 없다 — 번역 불가")
  d <- NULL
  rn <- rownames(R)
  if (!is.null(rn)) {
    d <- suppressWarnings(tryCatch(as.Date(rn), error = function(e) NULL))
    if (!is.null(d) && (anyNA(d) || anyDuplicated(d) > 0L)) d <- NULL
  }
  if (is.null(d)) d <- as.Date("2000-01-01") + (seq_len(nrow(R)) - 1L)   # 순서만 보존하는 라벨
  data.table(Date   = rep(d, times = ncol(R)),
             Ticker = rep(tk, each = nrow(R)),
             Ret    = as.numeric(R))
}

.wmr_dispatch_harness <- function(fn, fn_name, fn_formals, method_name,
                                  returns, bounds, max_names, extra = list()) {
  infeasible <- function(reason) list(weights = NULL, method = method_name, infeasible = TRUE,
                                      reason = reason, interface = "harness_convention", fn = fn_name)
  if (is.null(returns))
    return(infeasible("harness_convention: returns 부재 — (tickers, ret_dt) 표적은 수익률 창이 필요하다"))
  rd <- tryCatch(.wmr_returns_to_ret_dt(returns), error = function(e) conditionMessage(e))
  if (is.character(rd)) return(infeasible(rd))
  Rm <- as.matrix(returns)
  tk <- colnames(Rm)
  if (length(tk) > max_names)
    return(infeasible(sprintf("harness_convention: universe %d > max_names %d — 표적에 breadth 인자가 없다(선별은 호출자 축)",
                              length(tk), as.integer(max_names))))
  if (length(bounds) < 2L || !is.finite(bounds[2]) || bounds[2] <= 0)
    return(infeasible("harness_convention: bounds[2](max_w) 가 유효하지 않다"))
  if (is.finite(bounds[1]) && bounds[1] > 0)
    return(infeasible(sprintf("harness_convention: 하한 %.3f > 0 은 표적이 지원하지 않는다(long-only lb=0 만)", bounds[1])))

  h <- list(tickers = tk, ret_dt = rd)
  if ("n_days" %in% fn_formals)
    h$n_days <- if (!is.null(extra$n_days)) as.integer(extra$n_days) else nrow(Rm)
  if ("max_w" %in% fn_formals) h$max_w <- as.numeric(bounds[2])
  # 레지스트리 hyperparam 이름 `alpha_level` → 표적 `alpha`. 호출자가 명시했을 때만 전달한다 —
  #   기본값은 표적이 갖는다(CDaR/CVaR_LP 는 신뢰수준 0.95, calc_cvar_weights 는 꼬리확률 0.05 로
  #   **의미가 다르다**. 여기서 수치를 정하지 않는다).
  if ("alpha" %in% fn_formals && !is.null(extra$alpha_level)) h$alpha <- as.numeric(extra$alpha_level)
  extra <- extra[setdiff(names(extra), c("n_days", "alpha_level"))]
  passthru <- intersect(names(extra), setdiff(fn_formals, names(h)))
  for (k in passthru) h[[k]] <- extra[[k]]
  dropped <- setdiff(names(extra), passthru)
  if (length(dropped) && !("..." %in% fn_formals))
    return(infeasible(sprintf("harness_convention: 표적 %s 가 받지 않는 인자 %s — 조용히 떨어뜨리지 않는다",
                              fn_name, paste(dropped, collapse = ","))))

  w <- tryCatch(do.call(fn, h), error = function(e) e)
  if (inherits(w, "error")) {
    warning(sprintf("[dispatch] %s failed: %s", method_name, conditionMessage(w)))
    return(infeasible(conditionMessage(w)))
  }
  v  <- suppressWarnings(as.numeric(w))
  if (length(v) != length(tk) || !all(is.finite(v)))
    return(infeasible(sprintf("harness_convention: 산출 길이/유한성 불일치 — %d vs tickers %d", length(v), length(tk))))
  # 이름: 표적이 이름을 주면 그 이름으로 정렬, 없으면 **위치**(하네스 계약 — backtest_harness.R 은
  #   `names(w) <- selected` 를 무조건 수행한다. weight_catalog.R::.wc_lean_carrier_fn 주석과 동일).
  nm <- names(w)
  if (!is.null(nm) && all(tk %in% nm)) v <- v[match(tk, nm)]
  names(v) <- tk
  list(weights = v, method = method_name, infeasible = FALSE, interface = "harness_convention",
       fn = fn_name, n_days = h$n_days, max_w = h$max_w, alpha = h$alpha, passthru = passthru)
}

# ─── Dispatch (단일 방법론 실행) ─────────────────────────
# v6.1 Task#26 (L-192 Remediation, 2026-04-24):
#   - bounds default 0.20 → 0.10 (per-name 상한 축소)
#   - min_names = 15 (Grinold breadth 하한)
#   - hhi_cap = 0.10 (집중 방지)
#   - alpha_winsor = 2.0 (outlier ±2σ clip)
dispatch_weight_method <- function(method_name,
                                     alpha = NULL,
                                     cov_matrix = NULL,
                                     returns = NULL,
                                     confidence = NULL,
                                     bounds = c(0, 0.10),
                                     max_names = 25,
                                     min_names = 15L,
                                     hhi_cap = 0.10,
                                     alpha_winsor = 2.0,
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
  fn_formals <- names(formals(fn))

  # 인자 조립 (method별 상이)
  args <- list(...)

  # ★하네스 규약 표적 (tickers, ret_dt, …) 은 표준 조립이 닿지 않는다 — 번역층으로 보낸다.
  #   (2026-09-05 — CDaR_LP·CVaR_LP·MaxDiv 가 "unused arguments" 로 죽어 EW 폴백되던 결함)
  if (.wmr_is_harness_convention(fn_formals))
    return(.wmr_dispatch_harness(fn, fn_name, fn_formals, method_name,
                                 returns = returns, bounds = bounds, max_names = max_names,
                                 extra = args))

  if ("alpha" %in% spec$requires) args$alpha <- alpha
  if ("cov" %in% spec$requires) args$cov_matrix <- cov_matrix
  if ("returns" %in% spec$requires) args$returns <- returns
  args$bounds <- bounds
  args$max_names <- max_names

  # v6.1 Task#26 breadth 제약 — MVO만 native 지원. 기타 method는 호환 시도
  # (method fn이 해당 인자 formals에 있으면 전달, 없으면 drop)
  if ("min_names" %in% fn_formals) args$min_names <- min_names
  if ("hhi_cap" %in% fn_formals) args$hhi_cap <- hhi_cap
  if ("alpha_winsor" %in% fn_formals) args$alpha_winsor <- alpha_winsor

  # v6.1 R4: confidence propagation — MVO가 native 지원
  # Non-MVO 메소드에는 alpha × confidence 로 pre-scale (best-effort)
  if (!is.null(confidence)) {
    if (method_name == "MVO" && "alpha" %in% spec$requires) {
      args$confidence <- confidence
    } else if ("alpha" %in% spec$requires && !is.null(alpha)) {
      common <- intersect(names(alpha), names(confidence))
      if (length(common) > 0) {
        c_scaled <- confidence[names(alpha)]
        c_scaled[is.na(c_scaled)] <- 0.5
        args$alpha <- alpha * c_scaled
      }
    }
  }

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
                                  confidence = NULL,
                                  bounds = c(0, 0.10), max_names = 25,
                                  min_names = 15L, hhi_cap = 0.10,
                                  alpha_winsor = 2.0,
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
                                 confidence = confidence,
                                 bounds = bounds,
                                 max_names = max_names,
                                 min_names = min_names,
                                 hhi_cap = hhi_cap,
                                 alpha_winsor = alpha_winsor)
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
