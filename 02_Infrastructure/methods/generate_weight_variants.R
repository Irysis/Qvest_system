#!/usr/bin/env Rscript
#==============================================================================
# generate_weight_variants.R — 비중 규칙 **내부 생성기** (v9.2 S3-④, 2026-08-24)
#
#------------------------------------------------------------------------------
# 왜 — 실패 진단을 뒤집는다
#------------------------------------------------------------------------------
# 2026-08 실측이 실패 통로 ①의 **코드 줄을 특정했다**: `.ledoit_wolf_shrink`
# (backtest_harness.R:706)를 쓰는 곳은 :471(hrp) · :651(minvar) · :744(riskparity)
# **셋뿐**이고, advanced_weights.R Tier1~3 은 전부 **생 표본공분산**을 쓴다
# (:87 maxdiv · :119 nco · :187 resampled · :327 kelly …). 예외는 calc_robust_mv_weights
# 의 하드코딩 shrinkage=0.5(:223,:237) 하나다.
# 그리고 `compute_robust_cov`(OGK/MCD/SDE, advanced_weights.R:1321)가 **구현돼 있는데
# 호출자가 0** 이다.
# 271개월 실측: minvar_lw 1.1753 vs MVO_lw 1.4113 ⇒ **축소는 알파를 쓰는 규칙에서 크게
# 먹었다**. 그래서 G1 의 1순위 표적은 score_tilt · MVO · nco_score_tilt 계열이다.
#
#------------------------------------------------------------------------------
# ★sweep 판별을 **코드가 강제한다**
#------------------------------------------------------------------------------
# `generate_siblings()` 의 인자에 `ir` 도 `measured` 도 **없다**. 방출은 선언 축
# (부모 · 규칙 · 고정 레시피)의 **결정적 함수**이고, 그것이 chain 주장의 근거다.
#   · 방출은 **측정 전에** 원장(06_Registry/weight_variant_ledger.jsonl)에 기록된다.
#   · 한 런의 모든 형제가 같은 `trial_family_id` 를 받는다 → **패자를 숨길 수 없다.**
#   · k>1 에서 argmax 를 고르면 그건 `selection_type="sweep"` 이고 `n_trials` 가 가족
#     단위로 누적돼 DSR 게이트에 걸린다.
# 생성물의 **자격은 전부 재사용**한다 — register_method.R:218 `verify_adapter`
# (결정성 · 비-EW · 제약 · `.nearest_arm` 중복). 새 게이트를 만들지 않는다.
#
# ★실파일로 낸다(메모리 클로저 아님): 02_Infrastructure/methods/adapters/gen/<parent>__<rule>.R
#   그래야 verify_adapter 가 production 경로 그대로 검사하고, 재현·감사가 가능하다.
# ★부모 파일을 **편집하지 않는다**. 형제가 자기 Σ 를 만들고 부모 규칙을 그 위에서
#   호출한다 ⇒ 기존 23종에 대한 회귀 위험 0.
#
# 사용:
#   source("02_Infrastructure/methods/generate_weight_variants.R")
#   generate_siblings("lean:score_tilt", "shrinkage_lift")
#   generate_siblings("qepm:MVO", "shrinkage_lift")
#   generate_siblings("lean:softmax_tilt", "param_probe")
#==============================================================================

suppressWarnings(suppressMessages({ library(jsonlite) }))

.gv_root <- function() {
  for (k in c("CLAUDE_PROJECT_DIR", "QM_ROOT")) {
    v <- Sys.getenv(k, "")
    if (nzchar(v) && dir.exists(file.path(v, "06_Registry"))) return(v)
  }
  if (dir.exists("06_Registry")) return(getwd())
  "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
}

`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0 && !all(is.na(a))) a else b
.gv_get <- function(l, k, d = NULL) { if (!is.list(l) || !(k %in% names(l))) return(d)
                                      v <- l[[k]]; if (is.null(v)) d else v }

GV_GEN_DIR    <- "02_Infrastructure/methods/adapters/gen"
GV_LEDGER     <- "06_Registry/weight_variant_ledger.jsonl"
GV_HELPER     <- "_gen_sigma.R"     # `_` 접두 = 어댑터 아님(카탈로그 글롭에서 제외된다)

#------------------------------------------------------------------------------
# 고정 레시피 — **선언 축**. 여기 없는 것은 방출되지 않는다.
#   ★값 집합은 사전고정이다. "성과를 보고 고른" 값이 아니라 "선언한" 값이다.
#     G1 의 5종은 전부 저장소에 이미 구현돼 있다:
#       sample / ledoit_wolf / lw_nls / gerber_rmt  → hrp_core.R::.get_cor_cov
#       OGK                                          → advanced_weights.R:1321 compute_robust_cov
#------------------------------------------------------------------------------
GV_FIXED_RECIPE <- list(
  shrinkage_lift = list(
    # cov_method= 인자를 받는 부모에 통하는 4종(pass-through 경로 — 추정기가 부모 안으로 들어간다)
    est_cov_method = c("sample", "ledoit_wolf", "lw_nls", "gerber_rmt"),
    # ctx$Sigma 를 통째로 받는 부모(QEPM dispatch)에 통하는 5종 — OGK 는 이 경로로만 닿는다
    est_sigma      = c("sample", "ledoit_wolf", "lw_nls", "gerber_rmt", "OGK"),
    note = "부모가 생 표본공분산이면 추정기만 바꾼 형제. 목적함수·선별 불변."
  ),
  moment_truncation = list(
    # 고차·꼬리 목적함수의 1·2차 **짝**. 목적은 승리가 아니라 대조다.
    #   PRD 가 δ=1(완전 축소)에서도 minvar_lw 에 0.181 미달했다 — 잔여가 '목적함수' 탓인지
    #   '구조' 탓인지 미결이다. 짝을 만들면 갈린다.
    trunc = c("mv_mu_sigma", "minvar_only"),
    note = "고차/꼬리 부모의 1·2차 대조쌍. 승리가 아니라 판별이 목적."
  ),
  param_probe = list(
    # 기존 23종의 파라미터 공간. 단일 값 = chain, 값 집합을 성과로 고르면 = sweep.
    spaces = list(
      score_tilt     = list(alpha = c(0.2, 0.4, 0.6, 0.8), max_w = c(0.10, 0.15, 0.20)),
      score_pure     = list(max_w = c(0.10, 0.15, 0.20)),
      softmax_tilt   = list(tau = c(0.5, 1.0, 2.0)),
      winsor_tilt    = list(winsor_sd = c(1.0, 2.0, 3.0)),
      rank_tilt      = list(max_w = c(0.10, 0.15, 0.20)),
      hrp            = list(cov_method = c("sample", "ledoit_wolf", "gerber_rmt"),
                            n_days = c(60L, 120L, 250L)),
      ivol           = list(n_days = c(30L, 60L, 120L))
    ),
    # ★hrp linkage 는 **노출돼 있지 않다** — calc_hrp_weights 시그니처에 linkage 인자가 없다
    #   (계획서 초안이 가정한 축). 없는 인자를 만들려면 부모 편집이 필요하고 그건 회귀 위험이라
    #   여기서는 하지 않는다. 대신 cov_method × n_days 로 선언한다(사실대로 적는다).
    note = "기존 규칙의 파라미터 공간. linkage 는 부모가 노출하지 않아 제외."
  )
)

#------------------------------------------------------------------------------
# 형제 어댑터가 공유하는 Σ 추정 헬퍼(파일 1개). 생성물마다 복제하지 않는다.
#------------------------------------------------------------------------------
.gv_write_helper <- function(root = .gv_root()) {
  p <- file.path(root, GV_GEN_DIR, GV_HELPER)
  dir.create(dirname(p), recursive = TRUE, showWarnings = FALSE)
  txt <- c(
'# _gen_sigma.R — 생성 형제가 공유하는 Σ 추정기 (generate_weight_variants.R 가 생성).',
'#   ★어댑터가 아니다(`_` 접두 = weight_catalog 글롭 제외).',
'#   ★추정기가 조용히 표본공분산으로 낙하하는 것을 **금지**한다 — 그러면 "추정기를 갈아끼웠다"가',
'#     거짓이 되고 형제가 부모와 같은 것을 재게 된다(A/B 통제 붕괴).',
'.gen_root <- function() {',
'  for (k in c("CLAUDE_PROJECT_DIR", "QM_ROOT")) {',
'    v <- Sys.getenv(k, "")',
'    if (nzchar(v) && dir.exists(file.path(v, "06_Registry"))) return(v)',
'  }',
'  if (dir.exists("06_Registry")) return(getwd())',
'  "C:/Users/99922/OneDrive/Quant_Module_Moltbot"',
'}',
'',
'# 부모 규칙(calc_*) 해석기. production 은 하네스가 이미 로드한 상태로 돌지만, verify_adapter 는',
'#   `new.env(parent = globalenv())` 로 검사하므로 전역에 없을 수 있다. 그때 **조용히 실패하는 대신**',
'#   의존을 스스로 갖춘다(선례 = register_method.R 이 wrapper 의존을 갖추는 이유와 동일 —',
'#   의존 결손을 어댑터 결함으로 오탐하면 정상 어댑터가 거부된다).',
'.GEN_LEAN_ENV <- NULL',
'gen_lean_fn <- function(nm) {',
'  if (exists(nm, mode = "function")) return(get(nm, mode = "function"))',
'  if (is.null(.GEN_LEAN_ENV)) {',
'    e <- new.env(parent = globalenv())',
'    for (f in c("02_Infrastructure/portfolio/strategy_tilt_weights.R",',
'                "02_Infrastructure/portfolio/hrp_core.R",',
'                "02_Infrastructure/portfolio/advanced_weights.R")) {',
'      fp <- file.path(.gen_root(), f)',
'      if (file.exists(fp)) suppressWarnings(suppressMessages(try(sys.source(fp, envir = e), silent = TRUE)))',
'    }',
'    if (!exists(nm, envir = e, inherits = FALSE)) {',
'      # ★config.R 을 **먼저** e 에 싣는다. backtest_harness.R:18-20 은',
'      #     if (!exists("PROJECT_ROOT")) source(file.path(dirname(sys.frame(1)$ofile %||% "."), "config.R"))',
'      #   인데, 함수 안에서 부르면 `ofile` 이 없어 `./config.R` 로 낙하해 깨진다',
'      #   ("cannot open the connection" → 하네스 전체가 조용히 안 실림).',
'      #   PROJECT_ROOT 를 미리 정의해 두면 그 줄 자체가 실행되지 않는다.',
'      cf <- file.path(.gen_root(), "02_Infrastructure/config.R")',
'      if (file.exists(cf)) suppressWarnings(suppressMessages(try(sys.source(cf, envir = e), silent = TRUE)))',
'      fp <- file.path(.gen_root(), "02_Infrastructure/backtest_harness.R")',
'      if (file.exists(fp)) suppressWarnings(suppressMessages(try(sys.source(fp, envir = e), silent = TRUE)))',
'    }',
'    .GEN_LEAN_ENV <<- e',
'  }',
'  if (!exists(nm, envir = .GEN_LEAN_ENV, inherits = FALSE))',
'    stop(sprintf("gen_lean_fn: 부모 규칙 부재 %s (하네스/portfolio 로드 실패)", nm))',
'  get(nm, envir = .GEN_LEAN_ENV)',
'}',
'',
'gen_sigma <- function(R, est = "sample") {',
'  a <- colnames(R)',
'  if (identical(est, "sample")) { S <- stats::cov(R); dimnames(S) <- list(a, a); return(S) }',
'  if (identical(est, "OGK")) {',
'    if (!exists("compute_robust_cov", mode = "function")) {',
'      fp <- file.path(.gen_root(), "02_Infrastructure/portfolio/advanced_weights.R")',
'      if (file.exists(fp)) suppressWarnings(suppressMessages(source(fp)))',
'    }',
'    if (!exists("compute_robust_cov", mode = "function"))',
'      stop("gen_sigma: compute_robust_cov 부재 — OGK 형제를 만들 수 없다")',
'    if (!isTRUE(get0(".HAS_RRCOV", ifnotfound = FALSE)))',
'      stop(paste0("gen_sigma: rrcov 패키지 부재 — compute_robust_cov 가 **표본공분산으로 조용히 ",
                   "낙하**한다. 그러면 OGK 형제가 sample 형제와 동일해지고 결과표엔 두 arm 으로 보인다."))',
'    S <- compute_robust_cov(R, method = "OGK"); dimnames(S) <- list(a, a); return(S)',
'  }',
'  if (!exists(".get_cor_cov", mode = "function")) {',
'    fp <- file.path(.gen_root(), "02_Infrastructure/portfolio/hrp_core.R")',
'    if (file.exists(fp)) suppressWarnings(suppressMessages(source(fp)))',
'  }',
'  if (!exists(".get_cor_cov", mode = "function"))',
'    stop("gen_sigma: .get_cor_cov 부재 (hrp_core.R 미로드)")',
'  cc <- .get_cor_cov(R, est)',
'  S <- cc$cov; dimnames(S) <- list(a, a)',
'  Ssamp <- stats::cov(R)',
'  # 비-퇴화: 표본공분산과 구별되지 않으면 추정기가 폴백했다는 뜻이다 — 이름을 부른다.',
'  if (max(abs(S - Ssamp)) / max(abs(Ssamp)) < 1e-10)',
'    stop(sprintf("gen_sigma: est=%s 산출이 표본공분산과 구별되지 않음(폴백 의심)", est))',
'  S',
'}')
  writeLines(txt, p)
  invisible(p)
}

#------------------------------------------------------------------------------
# 부모 해석 — 카탈로그 엔트리에서 호출 형태를 읽는다.
#------------------------------------------------------------------------------
.gv_catalog <- function(root = .gv_root()) {
  p <- file.path(root, "06_Registry", "weight_catalog.json")
  if (!file.exists(p)) stop("[gv] weight_catalog.json 부재 — sync_catalog() 선행")
  fromJSON(p, simplifyVector = FALSE)
}

.gv_parent <- function(catalog_id, root = .gv_root()) {
  cg <- .gv_catalog(root)
  ids <- vapply(cg$entries, function(e) as.character(.gv_get(e, "catalog_id", "")), character(1))
  i <- match(catalog_id, ids)
  if (is.na(i)) stop(sprintf("[gv] 미지 부모 catalog_id: %s (등재 %d건)", catalog_id, length(ids)))
  cg$entries[[i]]
}

# 부모 호출 코드 조각 — Σ 를 어디로 넣는가가 형제의 전부다.
.gv_call_snippet <- function(entry, est = NULL, args = NULL) {
  r <- .gv_get(entry, "resolver", list())
  kind <- as.character(.gv_get(r, "kind", ""))
  extra <- if (length(args)) paste0(", ", paste(sprintf("%s = %s", names(args),
              vapply(args, function(v) if (is.character(v)) sprintf('"%s"', v) else
                                       format(v, scientific = FALSE), character(1))),
              collapse = ", ")) else ""
  if (identical(kind, "lean_builtin")) {
    nm <- as.character(.gv_get(r, "lean_name", ""))
    needs <- isTRUE(.gv_get(r, "needs_score", FALSE))
    cm <- if (!is.null(est)) sprintf(', cov_method = "%s"', est) else ""
    fname <- if (identical(nm, "score_pure")) "calc_score_tilt_weights" else paste0("calc_", nm, "_weights")
    fix <- if (identical(nm, "score_pure")) ", alpha = 1.0, max_w = 1.0" else ""
    if (needs) sprintf('gen_lean_fn("%s")(a, sc, rd%s%s%s)', fname, fix, cm, extra)
    else       sprintf('gen_lean_fn("%s")(a, rd%s%s)', fname, cm, extra)
  } else if (identical(kind, "qepm_registry")) {
    # ★bounds/min_names 를 ctx 에서 안전하게 뽑는다. register_method 의 합성 fixture 는
    #   `ub` 를 안 주고(→ c(0, NULL) = 길이1 = "bounds invalid") 자산이 8개다(→ min_names 15 미달).
    #   hhi_cap 도 같은 부류다 — 8종이면 달성 가능한 최소 HHI 가 1/8 = 0.125 로 기본 0.10 을
    #   **원리적으로** 못 넘는다(infeasible). 셋 다 자산 수에 맞춰 완화하되,
    #   production(25종)에서는 min(15,25)=15 · max(0.10, 1.05/25=0.042)=0.10 으로 **동일**하다.
    #   즉 완화는 fixture 구간에서만 발화한다(게이트를 낮추는 것이 아니다).
    sprintf(paste0('.qepm_dispatch("%s", alpha = ctx$mu, cov_matrix = S, returns = ctx$R,\n',
                   '                 bounds = c(0, if (is.null(ctx$ub)) 0.20 else ctx$ub),\n',
                   '                 max_names = 25L, min_names = min(15L, length(a)),\n',
                   '                 hhi_cap = max(0.10, 1.05 / length(a))%s)'),
            as.character(.gv_get(r, "dispatch_name", "")), extra)
  } else if (identical(kind, "adapter_file")) {
    sprintf('.parent_adapter("%s")(ctx2)', as.character(.gv_get(r, "adapter", "")))
  } else stop(sprintf("[gv] 형제를 만들 수 없는 resolver kind: %s", kind))
}

#------------------------------------------------------------------------------
# 어댑터 파일 본문 생성
#------------------------------------------------------------------------------
.gv_emit_file <- function(adapter_id, entry, rule, est, args, root = .gv_root()) {
  r <- .gv_get(entry, "resolver", list())
  kind <- as.character(.gv_get(r, "kind", ""))
  needs <- isTRUE(.gv_get(r, "needs_score", FALSE))
  pid <- as.character(.gv_get(entry, "catalog_id", "?"))

  pre <- c()
  if (kind == "lean_builtin") {
    pre <- c(pre,
      '  a  <- ctx$assets',
      '  rd <- .ctx_ret_dt_local(ctx)')
    if (needs) pre <- c(pre,
      '  sc <- { v <- suppressWarnings(as.numeric(ctx$mu[a])); v[!is.finite(v)] <- 0; stats::setNames(v, a) }')
  } else if (kind == "qepm_registry") {
    pre <- c(pre,
      '  a <- ctx$assets',
      sprintf('  S <- gen_sigma(ctx$R[, a, drop = FALSE], "%s")', est %||% "sample"))
  } else {
    pre <- c(pre,
      '  a <- ctx$assets',
      sprintf('  S <- gen_sigma(ctx$R[, a, drop = FALSE], "%s")', est %||% "sample"),
      '  ctx2 <- ctx; ctx2$Sigma <- S')
  }
  call <- .gv_call_snippet(entry, est = if (kind == "lean_builtin") est else NULL, args = args)

  txt <- c(
sprintf('# %s.R — **생성된 형제** (generate_weight_variants.R · 손편집 금지)', adapter_id),
'#',
sprintf('# 부모   : %s', pid),
sprintf('# 규칙   : %s', rule),
sprintf('# 축     : %s', if (!is.null(est)) sprintf('estimator = %s', est) else
                          if (length(args)) paste(sprintf("%s=%s", names(args), unlist(args)), collapse = " · ") else "-"),
'#',
'# ★이 파일은 부모를 **편집하지 않는다** — 자기 Σ 를 만들고 부모 규칙을 그 위에서 부른다.',
'#   기존 23종에 대한 회귀 위험 0. 제약(long-only · Σw=1 · w≤ub)은 wrap_adapter 가 강제한다.',
'# ★성과를 읽지 않는다 — 이 파일 어디에도 측정 필드가 없다(admit_generated 가 정적 스캔한다).',
'',
'.gen_root_a <- function() {',
'  for (k in c("CLAUDE_PROJECT_DIR", "QM_ROOT")) {',
'    v <- Sys.getenv(k, "")',
'    if (nzchar(v) && dir.exists(file.path(v, "06_Registry"))) return(v)',
'  }',
'  if (dir.exists("06_Registry")) return(getwd())',
'  "C:/Users/99922/OneDrive/Quant_Module_Moltbot"',
'}',
'if (!exists("gen_sigma", mode = "function"))',
sprintf('  source(file.path(.gen_root_a(), "%s", "%s"))', GV_GEN_DIR, GV_HELPER),
'',
'# ctx$R -> long (Date, Ticker, Ret). 순서만 보존하는 의사 날짜(weight_catalog.R::.ctx_ret_dt 동형).',
'.ctx_ret_dt_local <- function(ctx) {',
'  R <- ctx$R; anchor <- tryCatch(as.Date(ctx$decision_date), error = function(e) as.Date("2000-01-01"))',
'  if (is.na(anchor)) anchor <- as.Date("2000-01-01")',
'  d <- anchor - rev(seq_len(nrow(R)))',
'  data.table::data.table(Date = rep(d, times = ncol(R)),',
'                         Ticker = rep(colnames(R), each = nrow(R)), Ret = as.numeric(R))',
'}',
'',
'.qepm_dispatch <- function(nm, ...) {',
'  e <- get0(".GEN_QEPM_ENV", ifnotfound = NULL)',
'  if (is.null(e)) {',
'    e <- new.env(parent = globalenv())',
'    suppressWarnings(suppressMessages(sys.source(',
'      file.path(.gen_root_a(), "02_Infrastructure/portfolio/weight_method_registry.R"), envir = e)))',
'    for (f in c("mean_variance_optimizer", "hrp_core", "advanced_weights", "protection_strategy")) {',
'      fp <- file.path(.gen_root_a(), "02_Infrastructure/portfolio", paste0(f, ".R"))',
'      if (file.exists(fp)) suppressWarnings(suppressMessages(try(sys.source(fp, envir = e), silent = TRUE)))',
'    }',
'    assign("load_weight_infra", function() invisible(NULL), envir = e)',
'    assign(".GEN_QEPM_ENV", e, envir = globalenv())',
'  }',
'  r <- get("dispatch_weight_method", envir = e)(nm, ...)',
'  if (is.list(r) && isTRUE(r$infeasible)) stop(sprintf("dispatch infeasible: %s", r$reason))',
'  w <- if (is.list(r)) r$weights else r',
'  if (is.null(w)) stop("dispatch 가 weights 를 내지 않음")',
'  w',
'}',
'',
'.parent_adapter <- function(rel) {',
'  e <- new.env(parent = globalenv())',
'  sys.source(file.path(.gen_root_a(), rel), envir = e)',
'  get("method_weights", envir = e)',
'}',
'',
'method_weights <- function(ctx) {',
pre,
sprintf('  w <- %s', call),
'  # 이름이 있으면 **이름으로** 정렬한다 — max_names 로 support 를 제한하는 부모(MVO 계열)는',
'  #   선택된 종목만 돌려주므로 미선택분은 0 이 맞다(길이 불일치로 죽이면 정상 동작을 거부한다).',
'  #   이름이 없으면 하네스 계약(backtest_harness.R:1186)대로 **위치 기반**이다.',
'  if (!is.null(names(w))) {',
'    v <- suppressWarnings(as.numeric(w[a])); v[!is.finite(v)] <- 0; w <- v',
'  } else w <- as.numeric(w)',
'  if (length(w) != length(a)) stop(sprintf("산출 길이 불일치: %d vs %d", length(w), length(a)))',
'  stats::setNames(w, a)',
'}')
  p <- file.path(root, GV_GEN_DIR, paste0(adapter_id, ".R"))
  dir.create(dirname(p), recursive = TRUE, showWarnings = FALSE)
  writeLines(unlist(txt), p)
  p
}

#------------------------------------------------------------------------------
# generate_siblings — ★시그니처에 `ir`·`measured` 가 **없다**
#
#   방출은 (catalog_entry, fixed_recipe)의 결정적 함수다. 성과를 인자로 받지 않으므로
#   "성과를 보고 골라 방출했다"가 **구조적으로 불가능**하고, 그것이 chain 주장의 근거다.
#   방출 즉시(=측정 **전에**) 원장에 전 형제가 기록된다 — 패자를 숨길 수 없다.
#------------------------------------------------------------------------------
#' @param catalog_id 부모 (예: "lean:score_tilt" · "qepm:MVO")
#' @param rule "shrinkage_lift" | "moment_truncation" | "param_probe"
#' @param fixed_recipe 선언 레시피(기본 = GV_FIXED_RECIPE[[rule]]). 성과 무관.
#' @param max_emit 방출 상한 — arm 팽창을 구조적으로 막는다(R4).
#' @param dry_run TRUE 면 파일·원장 미기록(무엇이 나올지만 본다)
generate_siblings <- function(catalog_id, rule, fixed_recipe = NULL, max_emit = 5L,
                              root = .gv_root(), dry_run = FALSE, quiet = FALSE) {
  if (!(rule %in% names(GV_FIXED_RECIPE)))
    stop(sprintf("[gv] 미지 규칙: %s (가능: %s)", rule, paste(names(GV_FIXED_RECIPE), collapse = ", ")))
  rec <- fixed_recipe %||% GV_FIXED_RECIPE[[rule]]
  entry <- .gv_parent(catalog_id, root)
  r <- .gv_get(entry, "resolver", list())
  kind <- as.character(.gv_get(r, "kind", ""))
  parent_label <- gsub("[^A-Za-z0-9]", "_", catalog_id)

  plan <- list()   # list(suffix, est, args)
  if (identical(rule, "shrinkage_lift")) {
    ests <- if (identical(kind, "lean_builtin")) {
      if (!isTRUE(.gv_get(r, "cov_hook", FALSE)))
        stop(sprintf(paste0("[gv] %s 는 cov_method= 인자를 노출하지 않는다 — 추정기를 부모 안으로 ",
                            "넣을 경로가 없다. 부모를 편집하지 않는다는 규약상 이 부모에는 ",
                            "shrinkage_lift 형제를 만들지 않는다(사실대로 기각)."), catalog_id))
      rec$est_cov_method
    } else rec$est_sigma
    for (e in ests) plan[[length(plan) + 1L]] <- list(suffix = paste0("shr_", e), est = e, args = NULL)
  } else if (identical(rule, "moment_truncation")) {
    for (t in rec$trunc) plan[[length(plan) + 1L]] <- list(suffix = paste0("trunc_", t), est = NULL,
                                                           args = NULL, trunc = t)
  } else {  # param_probe
    lbl <- as.character(.gv_get(entry, "label", ""))
    sp <- rec$spaces[[lbl]]
    if (is.null(sp))
      stop(sprintf("[gv] param_probe 공간 미선언: %s (선언된 부모: %s)", lbl,
                   paste(names(rec$spaces), collapse = ", ")))
    grid <- expand.grid(sp, stringsAsFactors = FALSE)
    for (i in seq_len(nrow(grid))) {
      ar <- as.list(grid[i, , drop = FALSE]); names(ar) <- names(sp)
      sfx <- paste0("p_", paste(sprintf("%s%s", substr(names(ar), 1, 3),
                    gsub("[^A-Za-z0-9]", "", as.character(unlist(ar)))), collapse = "_"))
      plan[[length(plan) + 1L]] <- list(suffix = sfx, est = NULL, args = ar)
    }
  }

  # ★방출 상한 — 결정적 절단(앞에서부터). 성과로 자르지 않는다.
  n_planned <- length(plan)
  if (length(plan) > max_emit) plan <- plan[seq_len(max_emit)]

  # moment_truncation 은 부모를 대체하는 **대조쌍**이라 부모 호출이 아니라 고정 목적함수를 쓴다.
  tfid <- sprintf("WVF_%s_%s_%s", format(Sys.time(), "%Y%m%d%H%M%S"), parent_label, rule)
  sibs <- list(); files <- character(0)
  for (p in plan) {
    aid <- sprintf("%s__%s", parent_label, p$suffix)
    if (identical(rule, "moment_truncation")) {
      ent2 <- entry
      ent2$resolver <- list(kind = "qepm_registry",
                            dispatch_name = if (identical(p$trunc, "mv_mu_sigma")) "MVO" else "MVO")
      # minvar_only = 알파를 끄고 Σ 만 — dispatch 에 알파 0 벡터를 준다(별도 규칙 신설 없음).
      fp <- if (isTRUE(dry_run)) NA_character_ else
        .gv_emit_trunc(aid, entry, p$trunc, root)
    } else {
      fp <- if (isTRUE(dry_run)) NA_character_ else
        .gv_emit_file(aid, entry, rule, p$est, p$args, root)
    }
    files <- c(files, fp)
    sibs[[length(sibs) + 1L]] <- list(
      adapter_id = aid, adapter = file.path(GV_GEN_DIR, paste0(aid, ".R")),
      axis = p$suffix, estimator = p$est %||% NA_character_,
      params = p$args %||% list(), status = "unverified",
      family = sprintf("generated_%s", rule))
  }

  # k>1 이면 argmax 를 고르는 순간 sweep 이다 — 미리 라벨을 박고 n_trials 를 가족에 누적시킨다.
  sel <- if (length(sibs) > 1L) "sweep_candidate_family" else "chain"
  ledger <- list(
    record_type = "sibling_emission",
    trial_family_id = tfid,
    emitted_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    parent_catalog_id = catalog_id, rule = rule,
    fixed_recipe_note = as.character(rec$note %||% ""),
    n_planned = n_planned, n_siblings = length(sibs), max_emit = max_emit,
    selection_type = sel,
    emission_is_pre_measurement = TRUE,
    generator = "02_Infrastructure/methods/generate_weight_variants.R::generate_siblings",
    generator_formals = names(formals(generate_siblings)),
    sweep_note = paste0("방출은 선언 축의 결정적 함수다(생성기 인자에 ir/measured 없음). ",
                        "k>1 에서 argmax 를 고르면 selection_type='sweep' 이고 n_trials 는 ",
                        "가족 단위(n_siblings)로 누적돼 DSR 게이트에 걸린다. 패자도 여기 남는다."),
    siblings = sibs)

  if (!isTRUE(dry_run)) {
    .gv_write_helper(root)
    lp <- file.path(root, GV_LEDGER)
    dir.create(dirname(lp), recursive = TRUE, showWarnings = FALSE)
    cat(as.character(toJSON(ledger, auto_unbox = TRUE, null = "null", digits = NA)), "\n",
        file = lp, sep = "", append = TRUE)
  }
  if (!quiet) {
    cat(sprintf("[gv] %s · %s → 형제 %d/%d (family=%s · selection=%s%s)\n",
                catalog_id, rule, length(sibs), n_planned, tfid, sel,
                if (isTRUE(dry_run)) " · DRY" else ""))
    for (s in sibs) cat(sprintf("     - %s\n", s$adapter_id))
    if (!isTRUE(dry_run))
      cat("     ★다음: admit_generated(<파일>) — verify_adapter 통과분만 카탈로그에 오른다\n")
  }
  invisible(list(trial_family_id = tfid, siblings = sibs, files = files, ledger = ledger))
}

#' moment_truncation 짝 — 부모의 고차/꼬리 목적함수를 1·2차로 제한한 대조.
.gv_emit_trunc <- function(adapter_id, entry, trunc, root = .gv_root()) {
  pid <- as.character(.gv_get(entry, "catalog_id", "?"))
  body <- if (identical(trunc, "mv_mu_sigma"))
'  # 1·2차만: w ∝ Σ⁻¹ μ̂ (long-only). 부모의 고차/꼬리 항을 제거한 대조.
  mu <- suppressWarnings(as.numeric(ctx$mu[a])); mu[!is.finite(mu)] <- 0
  w <- tryCatch(solve(S + diag(1e-8, ncol(S)), mu), error = function(e) mu)
  w <- pmax(w, 0); if (sum(w) <= 0) w <- rep(1 / length(a), length(a))'
  else
'  # 2차만(알파 무시): w ∝ Σ⁻¹1 (min-var). 목적함수 차수를 더 낮춘 두 번째 대조.
  w <- tryCatch(solve(S + diag(1e-8, ncol(S)), rep(1, ncol(S))), error = function(e) rep(1, ncol(S)))
  w <- pmax(w, 0); if (sum(w) <= 0) w <- rep(1 / length(a), length(a))'
  txt <- c(
sprintf('# %s.R — **생성된 대조쌍** (generate_weight_variants.R · 손편집 금지)', adapter_id),
sprintf('# 부모   : %s  (moment_truncation / %s)', pid, trunc),
'#',
'# ★목적은 승리가 아니라 **판별**이다. 부모의 열세가 "목적함수 차수" 탓인지 "구조" 탓인지',
'#   미결이므로, 같은 Σ·같은 선별 위에서 1·2차로만 푼 짝을 만들어 갈라 본다.',
'# ★성과를 읽지 않는다.',
'',
'method_weights <- function(ctx) {',
'  a <- ctx$assets',
'  S <- ctx$Sigma',
'  if (is.null(S)) { S <- stats::cov(ctx$R[, a, drop = FALSE]); dimnames(S) <- list(a, a) }',
body,
'  w <- w / sum(w)   # ★합-정규화를 캡보다 **먼저** (wrap_adapter :73-78 실사고 규약)',
'  stats::setNames(as.numeric(w), a)',
'}')
  p <- file.path(root, GV_GEN_DIR, paste0(adapter_id, ".R"))
  dir.create(dirname(p), recursive = TRUE, showWarnings = FALSE)
  writeLines(txt, p)
  p
}

#' 주간 트리거용 — 런당 방출 상한을 지키며 1순위 표적부터 돈다.
#'   실측 사전분포(271개월: minvar_lw 1.1753 vs MVO_lw 1.4113)가 "축소는 알파를 쓰는
#'   규칙에서 크게 먹었다"를 가리키므로 score_tilt · MVO · nco_score_tilt 계열이 먼저다.
GV_PRIORITY_TARGETS <- list(
  list(catalog_id = "lean:score_tilt",   rule = "shrinkage_lift"),
  list(catalog_id = "qepm:MVO",          rule = "shrinkage_lift"),
  list(catalog_id = "lean:softmax_tilt", rule = "shrinkage_lift"),
  list(catalog_id = "lean:winsor_tilt",  rule = "shrinkage_lift"),
  list(catalog_id = "lean:score_tilt",   rule = "param_probe")
)

generate_weekly_batch <- function(max_families = 1L, max_emit = 5L, root = .gv_root(),
                                  dry_run = FALSE) {
  out <- list()
  for (t in utils::head(GV_PRIORITY_TARGETS, max_families)) {
    r <- tryCatch(generate_siblings(t$catalog_id, t$rule, max_emit = max_emit,
                                    root = root, dry_run = dry_run),
                  error = function(e) { cat(sprintf("[gv] %s/%s 생략: %s\n",
                                                    t$catalog_id, t$rule, conditionMessage(e))); NULL })
    if (!is.null(r)) out[[length(out) + 1L]] <- r
  }
  invisible(out)
}

if (!exists(".GV_QUIET_LOAD") || !isTRUE(.GV_QUIET_LOAD))
  cat("[generate_weight_variants.R] loaded — generate_siblings(catalog_id, rule) · generate_weekly_batch()\n")
