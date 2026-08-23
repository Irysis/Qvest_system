#!/usr/bin/env Rscript
#==============================================================================
# weight_catalog.R — 비중 결정 방법론 **통합 색인** (v9.2 S3-①, 2026-08-24 신설)
#
#------------------------------------------------------------------------------
# 왜 있나 — 세 갈래는 계약이 달라서 안 붙은 게 아니라 **다리가 없어서** 안 붙었다
#------------------------------------------------------------------------------
# 저장소에는 비중 규칙이 세 군데 따로 산다:
#   R1 lean 빌트인 23종      backtest_harness.R 의 `weight_method` 문자열 분기
#   R2 QEPM 레지스트리 14종  weight_method_registry.R::dispatch_weight_method
#   R3 논문/생성 어댑터      06_Registry/method_registry.json + methods/adapters/*.R
# 7개월간 R2 의 실호출은 1건이었다. 이유는 계약 충돌이 아니라 **아무도 한 줄을 안 썼기
# 때문**이다:
#     dispatch_weight_method(m, alpha = ctx$mu, cov_matrix = ctx$Sigma,
#                            returns = ctx$R, bounds = c(0, ctx$ub), max_names = 25)
# 어댑터 ctx(Sigma, R, mu, assets, ub, lookback_days, decision_date, eval_date)가
# 나머지 둘의 **상위집합**이다. lean 루프는 리밸일마다 (selected, ret_sub, sc) =
# (assets, R, mu) 를 이미 갖고 있고, QEPM 은 (alpha, cov_matrix, returns) = (mu, Sigma, R)
# 를 받는다. 그래서 이 파일은 **병합하지 않는다 — 색인만 한다.**
#
#------------------------------------------------------------------------------
# 설계 규약
#------------------------------------------------------------------------------
# ① **정규형은 새로 만들지 않는다.** wrap_adapter(method_registry.R:55)의 f(ctx)->w 가
#    정규형이다 — long-only · cap · Σw=1 을 이미 강제하고, 스케일-정규화-우선 결함도
#    이미 수리돼 있다(그 파일 :73-78 의 EW 붕괴 실사고 기록). 여기서 다시 만들면
#    두 번째 정규형이 생기고 둘이 갈린다.
# ② **카탈로그 JSON 은 파생 파일이다** — 06_Registry/weight_catalog.json 은
#    sync_catalog() 이 재생성한다. 손편집 금지. 엔트리는 **리졸버만** 적는다
#    (구현 복사 금지 — 복사하면 원본이 바뀌어도 사본이 안 바뀐다).
# ③ **R2 는 private-env 로 싣는다.** weight_method_registry.R:286/293 의 취약한 `%||%`
#    (`!is.null(a) && !is.na(a)` — 벡터에서 크래시)가 source() 로 **전역을 오염**시켜
#    run_alpha_search.R:346 이 매 런 사후 복구를 하고 있다. 워크어라운드를 하나 더
#    쌓지 말고 원인을 없앤다 — 선례 = method_registry.R:96 load_method_adapters.
# ④ **status 는 숨김이 아니라 표시다.** retired/blocked_inputs/degraded_wiring 도
#    카탈로그에는 **남는다**. arms() 가 기본 집합에서 뺄 뿐이고, include= 로 강제 편입된다.
#    (G-5 철회 — DPL·PPO_RL·Genetic 은 retired 로 박지 않는다. 정상 등재하고,
#     다른 축과 **똑같은 게이트**(verify_adapter · sweep/DSR · book-marginal · PIT)를 건다.
#     철회되는 것은 금지이지 측정 규율이 아니다.)
#
# 진입점:
#   sync_catalog(probe = FALSE)      R1/R2/R3 재색인 → weight_catalog.json
#   as_ctx_adapter(entry)            엔트리 → wrap_adapter 로 감싼 f(ctx)->w
#   weight_catalog_arms(axis=…)      사다리 ②칸 / 캐리어 배터리가 소비하는 arm 표
#   catalog_weight_arms()            Σ-A/B 배터리 주입용 named list(extra_adapters 모양)
#   admit_generated(…)               생성물(generate_weight_variants.R)의 카탈로그 편입
#==============================================================================

suppressWarnings(suppressMessages({
  library(jsonlite)
  library(data.table)
}))

# ── root: marker 로 정체 검사 (r-portability 금칙 ③④, method_registry.R 선례) ──
.wc_root <- function() {
  .marker <- file.path("02_Infrastructure", "portfolio", "weight_catalog.R")
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
  if (file.exists(.marker)) return(getwd())
  cand <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
  if (file.exists(file.path(cand, .marker))) cand else getwd()
}

WEIGHT_CATALOG_PATH   <- file.path("06_Registry", "weight_catalog.json")
WC_GEN_ADAPTER_DIR    <- file.path("02_Infrastructure", "methods", "adapters", "gen")
WC_UB                 <- 0.20

`%|.|%` <- function(a, b) if (!is.null(a) && length(a) > 0 && !all(is.na(a))) a else b

#' 원장(JSON) 리스트에서 **정확 이름**으로만 꺼낸다.
#' ★왜 필요한가 (2026-08-24 실측): R 의 `l$adapter` 는 리스트에서 **부분 일치**를 한다.
#'   method_registry.json 의 blocked 항목은 `adapter` 키가 아예 **없고** `adapter_kind` 만 있는데,
#'   `m$adapter` 가 조용히 `adapter_kind`("weight")를 돌려줬다 — 결손이 그럴듯한 값으로 위장했다.
#'   그 상태로 리졸버에 `adapter="weight"` 가 실려 "어댑터 파일 부재: weight" 라는 **엉뚱한 진단**이
#'   나왔다. 원인 문장이 틀리면 수리도 틀린다. JSON 유래 접근은 전부 이 함수를 경유한다.
.wc_get <- function(l, k, default = NULL) {
  if (!is.list(l) || !(k %in% names(l))) return(default)
  v <- l[[k]]
  if (is.null(v)) default else v
}

#------------------------------------------------------------------------------
# ctx 역변환 — R(obs × assets) 행렬 → long (Date, Ticker, Ret)
#
# ★왜 필요한가: R1 빌트인은 전부 `calc_X(tickers, ret_dt, …)` 시그니처이고 ret_dt 는
#   long data.table 이다. 캐리어 축(ctx 만 있는 세계)에서 그 규칙들을 그대로 쓰려면
#   이 6줄이 다리다. **구현을 복제하지 않는 유일한 길**이기도 하다.
# ★PIT: 이것은 표현 변환이지 시점 변환이 아니다. ctx$R 은 호출자가 이미 PIT trailing 으로
#   잘라 준 창이고(auto_sigma_weighting_ab.R: `raw[Date < start_d]`), 여기서는 행 **순서만**
#   보존한다. 빌트인 규칙이 Date 로 하는 일은 `tail(sort(unique(Date)), n_days)` 정렬·절단
#   뿐이므로, decision_date 에서 역산한 연속 의사(pseudo) 날짜가 의미상 동치다.
#   달력 의미(요일·월경계)를 읽는 규칙은 R1 에 없다 — 생기면 이 함수부터 고칠 것.
#------------------------------------------------------------------------------
.ctx_ret_dt <- function(ctx) {
  R <- ctx$R
  if (is.null(R) || !is.matrix(R) || !nrow(R)) return(data.table(Date = as.Date(character(0)),
                                                                 Ticker = character(0), Ret = numeric(0)))
  anchor <- tryCatch(as.Date(ctx$decision_date), error = function(e) as.Date("2000-01-01"))
  if (is.na(anchor)) anchor <- as.Date("2000-01-01")
  d <- anchor - rev(seq_len(nrow(R)))            # 순서만 보존하는 의사 날짜(오름차순)
  data.table(Date = rep(d, times = ncol(R)),
             Ticker = rep(colnames(R), each = nrow(R)),
             Ret = as.numeric(R))
}

#------------------------------------------------------------------------------
# R1 — lean 빌트인 23종. 이 표가 backtest_harness.R:1084-1181 분기와 1:1 대응이다.
#   carrier_call : ctx 축에서 그 규칙을 부르는 방법(needs_score → ctx$mu 를 scores 로)
#   cov_hook     : cov_method= 인자를 받는가 (G1 shrinkage_lift 의 pass-through 경로)
#   status       : degraded_wiring = 이름과 실제가 다른 팔 (아래 주석)
#------------------------------------------------------------------------------
# ★degraded_wiring 3종(regime_tilt · regime_softmax · ic_tilt): run_alpha_search 가
#   regime_dt / ic_history 를 하네스에 **전달하지 않아** mrs_val=0 · ic_hist=NULL 로
#   조용히 국면-중립 퇴화한다(backtest_harness.R:1112, 1148). "국면 조건부를 쟀다"가
#   거짓이 되므로 기본 arm 집합에서 뺀다. 카탈로그에는 남는다 — 배선이 복구되면
#   status 만 바뀐다(별건 태스크).
WC_LEAN_BUILTIN <- list(
  list(name = "ivol",           family = "risk_based",    needs_score = FALSE, cov_hook = FALSE, cost = 6,  status = "active"),
  list(name = "hrp",            family = "risk_based",    needs_score = FALSE, cov_hook = TRUE,  cost = 8,  status = "active"),
  list(name = "minvar",         family = "risk_based",    needs_score = FALSE, cov_hook = FALSE, cost = 8,  status = "active"),
  list(name = "riskparity",     family = "risk_parity",   needs_score = FALSE, cov_hook = FALSE, cost = 8,  status = "active"),
  list(name = "score_tilt",     family = "score_blend",   needs_score = TRUE,  cov_hook = TRUE,  cost = 8,  status = "active"),
  list(name = "score_pure",     family = "score_blend",   needs_score = TRUE,  cov_hook = TRUE,  cost = 8,  status = "active"),
  list(name = "rank_tilt",      family = "score_blend",   needs_score = TRUE,  cov_hook = TRUE,  cost = 8,  status = "active"),
  list(name = "softmax_tilt",   family = "score_blend",   needs_score = TRUE,  cov_hook = TRUE,  cost = 8,  status = "active"),
  list(name = "winsor_tilt",    family = "score_blend",   needs_score = TRUE,  cov_hook = TRUE,  cost = 8,  status = "active"),
  list(name = "nco_score_tilt", family = "score_blend",   needs_score = TRUE,  cov_hook = FALSE, cost = 10, status = "active"),
  list(name = "entropy",        family = "entropy",       needs_score = TRUE,  cov_hook = FALSE, cost = 8,  status = "active"),
  list(name = "cvar",           family = "tail_aware",    needs_score = FALSE, cov_hook = FALSE, cost = 10, status = "active"),
  list(name = "omega",          family = "tail_aware",    needs_score = FALSE, cov_hook = FALSE, cost = 10, status = "active"),
  list(name = "maxdiv",         family = "entropy",       needs_score = FALSE, cov_hook = FALSE, cost = 8,  status = "active"),
  list(name = "nco",            family = "risk_based",    needs_score = FALSE, cov_hook = FALSE, cost = 10, status = "active"),
  list(name = "resampled",      family = "classical",     needs_score = FALSE, cov_hook = FALSE, cost = 15, status = "active"),
  list(name = "robust_mv",      family = "classical",     needs_score = FALSE, cov_hook = FALSE, cost = 10, status = "active"),
  list(name = "factor_rp",      family = "risk_parity",   needs_score = FALSE, cov_hook = FALSE, cost = 8,  status = "active"),
  list(name = "kelly",          family = "growth",        needs_score = FALSE, cov_hook = FALSE, cost = 8,  status = "active"),
  list(name = "higher_moment",  family = "higher_moment", needs_score = FALSE, cov_hook = FALSE, cost = 10, status = "active"),
  list(name = "regime_tilt",    family = "score_blend",   needs_score = TRUE,  cov_hook = TRUE,  cost = 8,  status = "degraded_wiring"),
  list(name = "regime_softmax", family = "score_blend",   needs_score = TRUE,  cov_hook = TRUE,  cost = 8,  status = "degraded_wiring"),
  list(name = "ic_tilt",        family = "score_blend",   needs_score = TRUE,  cov_hook = TRUE,  cost = 8,  status = "degraded_wiring")
)
.WC_DEGRADED_NOTE <- paste0(
  "run_alpha_search 가 regime_dt/ic_history 를 전달하지 않아 국면-중립으로 조용히 퇴화",
  "(backtest_harness.R:1112,1148 mrs_val=0). 배선 복구 전에는 이름과 실제가 다르다.")

# lean 빌트인 → ctx 축 호출 (carrier 리졸버). needs_score 면 ctx$mu 를 scores 로 쓴다.
.wc_lean_carrier_fn <- function(spec) {
  force(spec)
  fname <- paste0("calc_", spec$name, "_weights")
  # 하네스 분기와 이름이 다른 두 건 — score_pure 는 score_tilt 를 alpha=1.0/max_w=1.0 로 부르고,
  # riskparity/minvar 등은 이름 규칙 그대로다.
  function(ctx) {
    a  <- ctx$assets
    rd <- .ctx_ret_dt(ctx)
    sc <- if (isTRUE(spec$needs_score)) {
      m <- ctx$mu
      if (is.null(m)) stop(sprintf("[wcat] %s 는 score 를 요구하는데 ctx$mu 가 없다", spec$name))
      v <- suppressWarnings(as.numeric(m[a])); v[!is.finite(v)] <- 0; stats::setNames(v, a)
    } else NULL
    res <- if (identical(spec$name, "score_pure")) {
      calc_score_tilt_weights(a, sc, rd, alpha = 1.0, max_w = 1.0)
    } else {
      if (!exists(fname, mode = "function"))
        stop(sprintf("[wcat] 빌트인 함수 부재: %s (backtest_harness.R 미로드?)", fname))
      fn <- get(fname, mode = "function")
      if (is.null(sc)) fn(a, rd) else fn(a, sc, rd)
    }
    # ★위치 기반 이름 부여 — 하네스 계약과 **자구 동일**하게 맞춘다.
    #   backtest_harness.R:1186 이 `names(w) <- selected` 를 무조건 수행한다. 즉 production
    #   에서 빌트인 산출의 정체성은 **순서**다. 여기서 다르게 해석하면 같은 규칙이 lean 축과
    #   캐리어 축에서 다른 것을 계산하게 된다(축이 갈리면 A/B 가 성립하지 않는다).
    #   ★실측 계기(2026-08-24 probe): 11종이 **이름 없는** 벡터를 반환하는데 wrap_adapter 는
    #     `v[a]` 로 이름 색인한다 → 전부 NA → 0 → "전량 0/음수 선호 → EW 폴백".
    #     즉 이름을 안 붙이면 score 계열 arm 전체가 조용히 EW 가 된다.
    res <- as.numeric(res)
    if (length(res) != length(a))
      stop(sprintf("[wcat] %s 산출 길이 불일치: %d vs assets %d", spec$name, length(res), length(a)))
    stats::setNames(res, a)
  }
}

#------------------------------------------------------------------------------
# R2 — QEPM 레지스트리 14종. private env 로딩(설계 규약 ③).
#------------------------------------------------------------------------------
.WC_ENV <- new.env(parent = emptyenv())   # 모듈-로컬 캐시(전역 오염 0)

.wc_qepm_env <- function(root = .wc_root()) {
  if (!is.null(.WC_ENV$qepm)) return(.WC_ENV$qepm)
  p <- file.path(root, "02_Infrastructure", "portfolio", "weight_method_registry.R")
  if (!file.exists(p)) { .WC_ENV$qepm <- FALSE; return(FALSE) }
  e <- new.env(parent = globalenv())
  ok <- tryCatch({ suppressWarnings(suppressMessages(sys.source(p, envir = e))); TRUE },
                 error = function(z) { cat(sprintf("[wcat] weight_method_registry source 실패: %s\n",
                                                   conditionMessage(z))); FALSE })
  if (!ok) { .WC_ENV$qepm <- FALSE; return(FALSE) }
  # ★infra 를 priv 로 먼저 싣고 load_weight_infra 를 no-op 으로 가린다.
  #   원본은 `source(path, local = FALSE)` 라 호출될 때마다 **globalenv 를 오염**시킨다
  #   (그 파일 :26-30). dispatch_weight_method 안의 get()/exists() 는 렉시컬 체인을
  #   타므로 priv 에 있으면 그대로 찾는다 — 동작은 같고 오염만 사라진다.
  for (nm in c("02_Infrastructure/portfolio/mean_variance_optimizer.R",
               "02_Infrastructure/portfolio/hrp_core.R",
               "02_Infrastructure/portfolio/advanced_weights.R",
               "02_Infrastructure/portfolio/protection_strategy.R")) {
    fp <- file.path(root, nm)
    if (file.exists(fp)) suppressWarnings(suppressMessages(
      try(sys.source(fp, envir = e), silent = TRUE)))
  }
  assign("load_weight_infra", function() invisible(NULL), envir = e)
  .WC_ENV$qepm <- e
  e
}

# ctx 에서 유도 불가한 입력을 요구하는 method 는 blocked_inputs — 카탈로그에는 남고
# 기본 arm 집합에서만 빠진다(views/prior_alpha/method_list 는 ctx 계약에 없다).
.WC_CTX_DERIVABLE <- c("alpha", "cov", "returns", "confidence")

.wc_qepm_specs <- function(root = .wc_root()) {
  e <- .wc_qepm_env(root)
  if (isFALSE(e) || is.null(e)) return(list())
  reg <- tryCatch(get("WEIGHT_METHOD_REGISTRY", envir = e), error = function(z) NULL)
  if (!is.list(reg) || !length(reg)) return(list())
  lapply(names(reg), function(nm) {
    m <- reg[[nm]]
    req <- as.character(m$requires %|.|% character(0))
    need <- setdiff(req, .WC_CTX_DERIVABLE)
    list(name = nm, family = as.character(m$family %|.|% "unknown"),
         requires = req, missing_inputs = need,
         status = if (length(need)) "blocked_inputs" else "active",
         hyperparams = as.character(m$hyperparams %|.|% character(0)),
         description = as.character(m$description %|.|% ""))
  })
}

#' ★설계 전체를 성립시키는 한 줄. QEPM 14종을 ctx 어댑터로 만든다.
.wc_qepm_carrier_fn <- function(name, root = .wc_root()) {
  force(name); force(root)
  function(ctx) {
    e <- .wc_qepm_env(root)
    if (isFALSE(e)) stop("[wcat] weight_method_registry 로드 실패")
    disp <- get("dispatch_weight_method", envir = e)
    a <- ctx$assets
    S <- ctx$Sigma
    if (is.null(S)) { S <- stats::cov(ctx$R); dimnames(S) <- list(a, a) }
    r <- disp(name,
              alpha      = ctx$mu,
              cov_matrix = S,
              returns    = ctx$R,
              bounds     = c(0, ctx$ub %|.|% WC_UB),
              max_names  = 25L)
    # ★infeasible 을 조용히 넘기지 않는다 — stop 하면 wrap_adapter 가 method_id 를
    #   **호명**하고 EW 폴백을 로그로 남긴다(method_registry.R:59). 그게 계약이다.
    if (is.list(r) && isTRUE(r$infeasible))
      stop(sprintf("dispatch infeasible: %s", as.character(r$reason %|.|% "unknown")))
    w <- if (is.list(r)) r$weights else r
    if (is.null(w)) stop("dispatch 가 weights 를 내지 않음")
    w <- suppressWarnings(as.numeric(w[a] %|.|% w))
    stats::setNames(w, a)
  }
}

#------------------------------------------------------------------------------
# R3 — 논문 어댑터(method_registry.json) + 생성물(adapters/gen/*.R)
#   load_method_adapters 패턴 재사용: private env + 진입점 고정 + 파일 부재 호명.
#------------------------------------------------------------------------------
.wc_adapter_file_fn <- function(rel_path, entrypoint = "method_weights", root = .wc_root()) {
  force(rel_path); force(entrypoint); force(root)
  function(ctx) {
    key <- paste0("af::", rel_path)
    fn <- .WC_ENV[[key]]
    if (is.null(fn)) {
      ap <- if (file.exists(rel_path)) rel_path else file.path(root, rel_path)
      if (!file.exists(ap)) stop(sprintf("어댑터 파일 부재: %s", rel_path))
      e <- new.env(parent = globalenv())
      sys.source(ap, envir = e)
      if (!exists(entrypoint, envir = e, inherits = FALSE))
        stop(sprintf("진입점 `%s` 부재: %s", entrypoint, rel_path))
      fn <- get(entrypoint, envir = e)
      assign(key, fn, envir = .WC_ENV)
    }
    fn(ctx)
  }
}

.wc_paper_specs <- function(root = .wc_root()) {
  rp <- file.path(root, "06_Registry", "method_registry.json")
  if (!file.exists(rp)) return(list())
  reg <- tryCatch(fromJSON(rp, simplifyVector = FALSE), error = function(z) NULL)
  ms <- reg$methods %|.|% list()
  out <- list()
  for (m in ms) {
    # ★전부 .wc_get — `$` 부분 일치가 결손을 값으로 위장한다(위 주석 참조).
    if (!identical(.wc_get(m, "adapter_kind"), "weight")) next   # sigma/exposure 는 다른 축이다
    mid <- as.character(.wc_get(m, "method_id", ""))
    if (!nzchar(mid)) next
    ap  <- as.character(.wc_get(m, "adapter", ""))
    vd  <- as.character(.wc_get(m, "verdict", "unknown"))
    st  <- if (!identical(vd, "implemented")) "blocked_inputs"
           else if (!nzchar(ap) || !file.exists(file.path(root, ap))) "unverified" else "active"
    out[[length(out) + 1L]] <- list(
      name = mid, adapter = ap,
      entrypoint = as.character(.wc_get(m, "entrypoint", "method_weights")),
      family = as.character(.wc_get(m, "route", "paper")),
      status = st, verdict = vd,
      selection_type = as.character(.wc_get(m, "selection_type", "chain")),
      screen_axes = .wc_get(m, "screen_axes"),
      paper_id = as.character(.wc_get(m, "paper_id", NA_character_)),
      measurement_status = as.character(.wc_get(m, "measurement_status", NA_character_)))
  }
  out
}

.wc_generated_specs <- function(root = .wc_root()) {
  gd <- file.path(root, WC_GEN_ADAPTER_DIR)
  if (!dir.exists(gd)) return(list())
  # `_` 로 시작하는 파일은 공용 헬퍼다(어댑터 아님) — 색인에서 제외.
  fs <- list.files(gd, pattern = "\\.R$", full.names = FALSE)
  fs <- fs[!grepl("^_", fs)]
  led <- .wc_variant_ledger(root)
  lapply(fs, function(f) {
    id <- sub("\\.R$", "", f)
    rec <- led[[id]]
    list(name = id, adapter = file.path(WC_GEN_ADAPTER_DIR, f),
         entrypoint = "method_weights",
         family = as.character(rec$family %|.|% "generated"),
         parent = as.character(rec$parent %|.|% NA_character_),
         rule = as.character(rec$rule %|.|% NA_character_),
         status = as.character(rec$status %|.|% "unverified"),
         selection_type = as.character(rec$selection_type %|.|% "chain"),
         trial_family_id = as.character(rec$trial_family_id %|.|% NA_character_),
         n_trials_family = as.integer(rec$n_trials_family %|.|% 1L),
         emitted_at = as.character(rec$emitted_at %|.|% NA_character_))
  })
}

#' 형제 방출 원장(generate_weight_variants.R 가 **측정 전에** append 한다) → id 색인.
.wc_variant_ledger <- function(root = .wc_root()) {
  p <- file.path(root, "06_Registry", "weight_variant_ledger.jsonl")
  if (!file.exists(p)) return(list())
  ln <- tryCatch(readLines(p, warn = FALSE), error = function(z) character(0))
  out <- list()
  for (l in ln) {
    if (!nzchar(trimws(l))) next
    o <- tryCatch(fromJSON(l, simplifyVector = FALSE), error = function(z) NULL)
    if (is.null(o)) next
    for (s in (o$siblings %|.|% list())) {
      sid <- as.character(s$adapter_id %|.|% "")
      if (!nzchar(sid)) next
      out[[sid]] <- c(s, list(trial_family_id = o$trial_family_id,
                              n_trials_family = o$n_siblings,
                              selection_type  = o$selection_type,
                              emitted_at      = o$emitted_at,
                              parent          = o$parent_catalog_id,
                              rule            = o$rule))
    }
  }
  out
}

#------------------------------------------------------------------------------
# sync_catalog — 병합하지 않고 색인한다.
#   probe=TRUE 면 합성 fixture 로 한 번 돌려 **EW 퇴화 여부**를 기록한다(비싼 축이라 기본 FALSE).
#   ★probe 결과는 기존 파일에서 **보존 병합**된다 — probe 없이 다시 sync 해도 지워지지 않는다.
#------------------------------------------------------------------------------
.WC_STATUS_RANK <- c(retired = 0L, blocked_inputs = 1L, degraded_wiring = 1L,
                     unverified = 1L, active = 2L)
# ★안전 조회 — `v[[k]]` 는 미지 키에서 **에러**를 낸다. 미지 status/우선순위가 들어왔을 때
#   arms() 전체가 죽으면 "카탈로그가 비었다"로 보인다(결손이 정상값 0 으로 위장하는 계통).
.wc_rank <- function(st) {
  i <- match(as.character(st)[1], names(.WC_STATUS_RANK))
  if (is.na(i)) 0L else as.integer(.WC_STATUS_RANK[[i]])
}
.WC_PRIO_RANK <- c("⭐⭐⭐" = 0L, "⭐⭐" = 1L, "⭐" = 2L, "후순위" = 4L)
.WC_PRIO_DEFAULT <- 3L    # 미표기는 ⭐와 후순위 사이 — 모르는 것을 버리지 않는다
.wc_prio <- function(x) {
  k <- trimws(as.character(x)[1])
  if (is.na(k) || !nzchar(k)) return(.WC_PRIO_DEFAULT)
  i <- match(k, names(.WC_PRIO_RANK))
  if (is.na(i)) .WC_PRIO_DEFAULT else as.integer(.WC_PRIO_RANK[[i]])
}

.wc_screen_axes <- function(x) {
  if (is.null(x)) return(list(shrinkage_builtin = NA_character_,
                              statistic_order = NA_character_, screen_priority = NA_character_))
  list(shrinkage_builtin = as.character(x$shrinkage_builtin %|.|% NA_character_),
       statistic_order   = as.character(x$statistic_order   %|.|% NA_character_),
       screen_priority   = as.character(x$screen_priority   %|.|% NA_character_))
}

sync_catalog <- function(root = .wc_root(), probe = FALSE, write = TRUE, quiet = FALSE) {
  prev <- tryCatch({
    p <- file.path(root, WEIGHT_CATALOG_PATH)
    if (file.exists(p)) fromJSON(p, simplifyVector = FALSE) else NULL
  }, error = function(z) NULL)
  prev_probe <- list()
  for (e in (prev$entries %|.|% list()))
    if (!is.null(e$probe)) prev_probe[[as.character(e$catalog_id)]] <- e$probe

  entries <- list()
  mk <- function(...) entries[[length(entries) + 1L]] <<- list(...)

  # R1 -------------------------------------------------------------------------
  for (s in WC_LEAN_BUILTIN) {
    mk(catalog_id = paste0("lean:", s$name), label = s$name, origin = "lean_builtin",
       family = s$family, status = s$status,
       notes = if (identical(s$status, "degraded_wiring")) .WC_DEGRADED_NOTE else NULL,
       resolver = list(kind = "lean_builtin", lean_name = s$name,
                       carrier_fn = paste0("calc_", s$name, "_weights"),
                       needs_score = s$needs_score, cov_hook = s$cov_hook),
       screen_axes = .wc_screen_axes(NULL), selection_type = "chain",
       trial_family_id = NULL, n_trials_family = 1L,
       prior_measured = NULL, est_cost_min = s$cost)
  }
  # R2 -------------------------------------------------------------------------
  for (s in .wc_qepm_specs(root)) {
    mk(catalog_id = paste0("qepm:", s$name), label = s$name, origin = "qepm_registry",
       family = s$family, status = s$status,
       notes = if (length(s$missing_inputs))
         sprintf("ctx 로 유도 불가한 입력 요구: %s", paste(s$missing_inputs, collapse = ", ")) else NULL,
       resolver = list(kind = "qepm_registry", dispatch_name = s$name,
                       requires = s$requires, hyperparams = s$hyperparams),
       screen_axes = .wc_screen_axes(NULL), selection_type = "chain",
       trial_family_id = NULL, n_trials_family = 1L,
       prior_measured = NULL, est_cost_min = 10)
  }
  # R3a 논문 -------------------------------------------------------------------
  for (s in .wc_paper_specs(root)) {
    mk(catalog_id = paste0("paper:", s$name), label = s$name, origin = "paper_adapter",
       family = s$family, status = s$status,
       notes = if (identical(s$status, "blocked_inputs"))
         sprintf("verdict=%s (등재됐으나 implemented 아님)", s$verdict) else NULL,
       resolver = list(kind = "adapter_file", adapter = s$adapter, entrypoint = s$entrypoint,
                       paper_id = s$paper_id),
       screen_axes = .wc_screen_axes(s$screen_axes), selection_type = s$selection_type,
       trial_family_id = NULL, n_trials_family = 1L,
       prior_measured = if (!is.na(s$measurement_status)) list(measurement_status = s$measurement_status) else NULL,
       est_cost_min = 10)
  }
  # R3b 생성물 -----------------------------------------------------------------
  for (s in .wc_generated_specs(root)) {
    mk(catalog_id = paste0("gen:", s$name), label = s$name, origin = "generated",
       family = s$family, status = s$status,
       notes = sprintf("parent=%s rule=%s emitted=%s", s$parent, s$rule, s$emitted_at),
       resolver = list(kind = "adapter_file", adapter = s$adapter, entrypoint = s$entrypoint,
                       parent = s$parent, rule = s$rule),
       screen_axes = .wc_screen_axes(NULL), selection_type = s$selection_type,
       trial_family_id = s$trial_family_id, n_trials_family = s$n_trials_family,
       prior_measured = NULL, est_cost_min = 6)
  }

  # probe (선택) — EW 퇴화 검거. 보존 병합.
  for (i in seq_along(entries)) {
    cid <- entries[[i]]$catalog_id
    if (isTRUE(probe) && .wc_rank(entries[[i]]$status) >= 1L) {
      entries[[i]]$probe <- .wc_probe_entry(entries[[i]], root)
    } else if (!is.null(prev_probe[[cid]])) {
      entries[[i]]$probe <- prev_probe[[cid]]
    }
  }

  cnt <- table(vapply(entries, function(e) e$origin, character(1)))
  out <- list(
    `_doc` = paste0("비중 결정 방법론 통합 색인 — **파생 파일**(손편집 금지). ",
                    "재생성 = source('02_Infrastructure/portfolio/weight_catalog.R'); sync_catalog(). ",
                    "엔트리는 리졸버만 적는다(구현 복사 금지). 정규형 = wrap_adapter(method_registry.R:55)."),
    generator = "02_Infrastructure/portfolio/weight_catalog.R::sync_catalog",
    generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    status_vocab = as.list(.WC_STATUS_RANK),
    retraction_note = paste0("G-5(2026-08-23 도훈): settled-negative 선언 철회. ",
                             "DPL·PPO_RL·Genetic 은 retired 로 박지 않는다 — 정상 등재하고 ",
                             "같은 게이트(verify_adapter · sweep/DSR · book-marginal ΔIR≥0.05 · PIT)를 건다."),
    counts = as.list(cnt), n_entries = length(entries), entries = entries)

  if (isTRUE(write)) {
    p <- file.path(root, WEIGHT_CATALOG_PATH)
    dir.create(dirname(p), showWarnings = FALSE, recursive = TRUE)
    tmp <- paste0(p, ".tmp", Sys.getpid())
    writeLines(as.character(toJSON(out, auto_unbox = TRUE, pretty = TRUE, null = "null", digits = NA)), tmp)
    file.rename(tmp, p)                                  # 원자 교체(부분 기록 방지)
  }
  if (!quiet) {
    cat(sprintf("[wcat] sync — entries=%d (%s)\n", length(entries),
                paste(sprintf("%s %d", names(cnt), as.integer(cnt)), collapse = " · ")))
    st <- table(vapply(entries, function(e) e$status, character(1)))
    cat(sprintf("[wcat] status: %s\n", paste(sprintf("%s %d", names(st), as.integer(st)), collapse = " · ")))
  }
  invisible(out)
}

#' 합성 fixture 1회 실행 — **EW 와 구별되는가**만 본다(성과 아님).
.wc_probe_entry <- function(entry, root = .wc_root()) {
  fx <- tryCatch(.wc_fixture(), error = function(z) NULL)
  if (is.null(fx)) return(list(ok = FALSE, reason = "fixture 생성 실패"))
  f <- tryCatch(as_ctx_adapter(entry, root = root), error = function(z) NULL)
  if (is.null(f)) return(list(ok = FALSE, reason = "리졸브 실패"))
  o <- NULL
  msg <- utils::capture.output(o <- tryCatch(f(fx), error = function(z) conditionMessage(z)))
  if (is.character(o)) return(list(ok = FALSE, reason = paste("예외:", o[1])))
  ew <- rep(1 / length(fx$assets), length(fx$assets))
  d  <- max(abs(as.numeric(o) - ew))
  lg <- paste(utils::head(msg, 3), collapse = " | ")
  # ★퇴화를 두 부류로 가른다 — 사유가 다르면 처분도 다르다.
  #   (a) wrapper 가 폴백을 **호명**했다(로그 있음) → 어댑터/디스패치 결함. 로그가 사유다.
  #   (b) 예외도 폴백도 없는데 출력이 정확히 EW → **스케일-캡-정규화 순서 결함** 의심.
  #       advanced_weights.R:30-35 `.normalize` 는 `pmin(w, max_w)` 를 합-정규화 **전에**
  #       적용한다. 원 선호 스케일이 max_w(0.15)를 넘으면 전 원소가 캡에 걸려 동일해지고,
  #       그 뒤 합-정규화되어 **정확히 EW** 가 된다. 2026-08-08 `.minvar_w` 실사고와 동형이고,
  #       wrap_adapter :73-78 이 기록한 바로 그 병이다. 다른 점은 이건 **아직 안 고쳐졌다**는 것.
  rsn <- if (is.finite(d) && d >= 1e-6) NA_character_
         else if (nzchar(lg)) "EW 퇴화 — wrapper 폴백(로그 참조)"
         else paste0("EW 퇴화 — 예외·폴백 없이 정확히 EW. 스케일-캡-정규화 순서 결함 의심",
                     "(advanced_weights.R:30-35 .normalize 가 합-정규화 전에 pmin(w,max_w) 적용).")
  list(ok = is.finite(d) && d >= 1e-6, max_abs_dev_from_ew = round(d, 8),
       reason = rsn, log = lg)
}

# ★n_assets = 25 는 **고정 축**이다 — 종목수 상한이 25 이고 dispatch_weight_method 의
#   min_names 기본값이 15 다. 12종 fixture 로 재면 MVO 계열이 "min_names(15) > universe(12)"
#   로 infeasible 을 내고, 그게 어댑터 결함처럼 보인다(검사기 오탐 = 대상 결함과 겉보기가 같다).
.wc_fixture <- function(n_assets = 25L, n_obs = 260L, seed = 20260824L) {
  set.seed(seed)
  a <- sprintf("A%05d", seq_len(n_assets))
  R <- matrix(stats::rnorm(n_obs * n_assets, 0, 0.02), nrow = n_obs, dimnames = list(NULL, a))
  R <- sweep(R, 2, seq(0.6, 1.8, length.out = n_assets), "*")
  mu <- stats::setNames(seq(0.004, -0.001, length.out = n_assets), a)
  S <- stats::cov(R); dimnames(S) <- list(a, a)
  list(assets = a, R = R, mu = mu, Sigma = S, ub = WC_UB, lookback_days = n_obs,
       decision_date = as.Date("2026-06-01"), eval_date = as.Date("2026-07-01"))
}

#------------------------------------------------------------------------------
# as_ctx_adapter — 엔트리 → **정규형** f(ctx)->w (wrap_adapter 가 제약을 강제한다)
#------------------------------------------------------------------------------
.wc_wrap_env <- function(root = .wc_root()) {
  if (!is.null(.WC_ENV$wrap)) return(.WC_ENV$wrap)
  e <- new.env(parent = globalenv())
  for (nm in c("02_Infrastructure/portfolio/strategy_tilt_weights.R",
               "02_Infrastructure/methods/method_registry.R")) {
    fp <- file.path(root, nm)
    if (file.exists(fp)) suppressWarnings(suppressMessages(try(sys.source(fp, envir = e), silent = TRUE)))
  }
  if (!exists("wrap_adapter", envir = e, inherits = FALSE))
    stop("[wcat] wrap_adapter 부재 — method_registry.R 로드 실패. 정규형 없이 arm 을 내지 않는다.")
  .WC_ENV$wrap <- e
  e
}

as_ctx_adapter <- function(entry, root = .wc_root(), ub = WC_UB) {
  r <- entry$resolver
  if (is.null(r)) stop("[wcat] resolver 부재: ", entry$catalog_id %|.|% "?")
  raw <- switch(as.character(r$kind),
    lean_builtin  = .wc_lean_carrier_fn(list(name = r$lean_name, needs_score = isTRUE(r$needs_score))),
    qepm_registry = .wc_qepm_carrier_fn(as.character(r$dispatch_name), root = root),
    adapter_file  = .wc_adapter_file_fn(as.character(r$adapter),
                                        as.character(r$entrypoint %|.|% "method_weights"), root = root),
    stop(sprintf("[wcat] 미지 resolver kind: %s", r$kind)))
  # lean 빌트인은 harness/advanced_weights 의 calc_* 를 전역에서 찾는다 — 없으면 이름을 부른다.
  we <- .wc_wrap_env(root)
  get("wrap_adapter", envir = we)(raw, as.character(entry$catalog_id), ub = ub)
}

.wc_load_catalog <- function(root = .wc_root(), sync_if_missing = TRUE) {
  p <- file.path(root, WEIGHT_CATALOG_PATH)
  if (!file.exists(p)) {
    if (!sync_if_missing) stop("[wcat] 카탈로그 부재: ", p)
    return(sync_catalog(root = root, quiet = TRUE))
  }
  fromJSON(p, simplifyVector = FALSE)
}

#------------------------------------------------------------------------------
# 하네스가 `catalog:` 를 아는가 — **능력 검사**(선언이 아니라 파일을 본다).
#   ★없는 동안 axis="lean" 은 lean_builtin 행만 낸다. 그러지 않으면 미등록 문자열이
#     backtest_harness.R:1179 else 로 떨어져 **조용히 EW** 가 되고, 결과표에는
#     "새 방법론을 완주했다"고 찍힌다(method_registry.R:73-78 에 같은 형태의 실사고 기록).
#------------------------------------------------------------------------------
.WC_HARNESS_MARK <- "QVEST_CATALOG_BRANCH_V1"
.wc_harness_supports_catalog <- function(root = .wc_root()) {
  p <- file.path(root, "02_Infrastructure", "backtest_harness.R")
  if (!file.exists(p)) return(FALSE)
  any(grepl(.WC_HARNESS_MARK, readLines(p, warn = FALSE), fixed = TRUE))
}

#------------------------------------------------------------------------------
# weight_catalog_arms — 사다리 ②칸 / 캐리어 배터리가 소비하는 arm 표
#------------------------------------------------------------------------------
#' @param axis "lean"(엔진 런: 선별이 같이 움직임) / "carrier"(선별 고정, 초~분)
#' @param top_k NULL 이면 전부. 정렬 = 우선순위 → 비용 → id (결정적)
#' @param include 강제 편입 catalog_id (status 무관). exclude_retired 보다 강하다.
#' @param min_status "active"(기본) / "unverified" / "any"
weight_catalog_arms <- function(axis = c("lean", "carrier"), top_k = NULL, include = NULL,
                                exclude_retired = TRUE, min_status = "active",
                                root = .wc_root(), catalog = NULL, quiet = FALSE) {
  axis <- match.arg(axis)
  cg <- catalog %|.|% .wc_load_catalog(root)
  es <- cg$entries %|.|% list()
  if (!length(es)) return(data.table())

  floor_rank <- if (identical(min_status, "any")) 0L else .wc_rank(min_status)
  inc <- as.character(include %|.|% character(0))

  # ★probe 실패 = **실효 강등**. 등재는 active 인데 합성 fixture 에서 EW 와 구별되지 않는
  #   arm 을 기본 집합에 넣으면, 결과표에 "새 비중 규칙" 이라는 이름으로 EW 수치가 찍힌다
  #   (method_registry.R:73-78 실사고 계통). 카탈로그에는 남고 include= 로만 강제 편입된다.
  .eff_status <- function(e) {
    st <- as.character(.wc_get(e, "status", "unverified"))
    pr <- .wc_get(e, "probe")
    if (!is.null(pr) && !isTRUE(.wc_get(pr, "ok", FALSE)) && .wc_rank(st) >= 2L) return("unverified")
    st
  }
  keep <- vapply(es, function(e) {
    cid <- as.character(.wc_get(e, "catalog_id", ""))
    if (cid %in% inc) return(TRUE)
    st <- .eff_status(e)
    if (isTRUE(exclude_retired) && identical(as.character(.wc_get(e, "status", "")), "retired")) return(FALSE)
    .wc_rank(st) >= floor_rank
  }, logical(1))
  es <- es[keep]
  if (!length(es)) return(data.table())

  # ── lean 축 능력 게이트 ────────────────────────────────────────────────────
  dropped <- list()
  if (identical(axis, "lean") && !.wc_harness_supports_catalog(root)) {
    is_bi <- vapply(es, function(e) identical(e$origin, "lean_builtin"), logical(1))
    dropped <- es[!is_bi]
    es <- es[is_bi]
    if (!quiet && length(dropped)) {
      cat(sprintf(paste0("[wcat] ★lean 축 축소 %d행 — backtest_harness.R 에 `catalog:` 분기(%s)가 없다.\n",
                         "       미등록 문자열은 :1179 else 로 떨어져 **조용히 EW** 가 된다 ",
                         "(= 'arm 을 완주했다'는 거짓 기록). 빠진 행:\n"),
                  length(dropped), .WC_HARNESS_MARK))
      for (d in utils::head(dropped, 40))
        cat(sprintf("       - %-34s origin=%-14s status=%s\n",
                    d$catalog_id, d$origin, d$status))
      if (length(dropped) > 40) cat(sprintf("       … 외 %d행\n", length(dropped) - 40))
    }
  }

  rows <- lapply(es, function(e) {
    sa <- e$screen_axes %|.|% list()
    origin <- as.character(e$origin)
    ac <- if (identical(axis, "carrier")) NA_character_
          else if (identical(origin, "lean_builtin")) as.character(e$resolver$lean_name)
          else paste0("catalog:", e$catalog_id)
    data.table(
      catalog_id      = as.character(e$catalog_id),
      label           = as.character(e$label),
      axis            = axis,
      axis_call       = ac,
      axis_args       = list(e$resolver$args %|.|% list()),
      adapter_fn      = list(NULL),
      origin          = origin,
      family          = as.character(e$family %|.|% "unknown"),
      status          = .eff_status(e),
      status_declared = as.character(.wc_get(e, "status", "unverified")),
      probe_ok        = { pr <- .wc_get(e, "probe"); if (is.null(pr)) NA else isTRUE(.wc_get(pr, "ok", FALSE)) },
      probe_reason    = { pr <- .wc_get(e, "probe"); as.character(.wc_get(pr, "reason", NA_character_))[1] },
      screen_axes     = list(sa),
      shrinkage_builtin = as.character(sa$shrinkage_builtin %|.|% NA_character_),
      statistic_order   = as.character(sa$statistic_order   %|.|% NA_character_),
      screen_priority   = as.character(sa$screen_priority   %|.|% NA_character_),
      selection_type  = as.character(e$selection_type %|.|% "chain"),
      trial_family_id = as.character(e$trial_family_id %|.|% NA_character_),
      n_trials_family = as.integer(e$n_trials_family %|.|% 1L),
      prior_measured  = list(e$prior_measured %|.|% list()),
      est_cost_min    = as.numeric(e$est_cost_min %|.|% 10))
  })
  DT <- rbindlist(rows, fill = TRUE)

  # adapter_fn 은 **지연 리졸브** — arms() 호출만으로 14+17개 파일을 열지 않는다.
  ee <- setNames(es, vapply(es, function(e) as.character(e$catalog_id), character(1)))
  DT[, adapter_fn := lapply(catalog_id, function(cid) {
    force(cid)
    function(ctx) as_ctx_adapter(ee[[cid]], root = root)(ctx)
  })]

  DT[, .prio := vapply(screen_priority, .wc_prio, integer(1))]
  DT[, .pin := as.integer(!(catalog_id %in% inc))]
  setorderv(DT, c(".pin", ".prio", "est_cost_min", "catalog_id"))
  DT[, c(".prio", ".pin") := NULL]
  if (!is.null(top_k) && is.finite(top_k) && top_k > 0 && nrow(DT) > top_k) DT <- DT[seq_len(top_k)]
  DT[]
}

#------------------------------------------------------------------------------
# catalog_weight_arms — Σ-A/B 배터리 주입용 named list (extra_adapters 모양)
#
# ★paper_research_dispatch.R 이 `run_sigma_ab(extra_adapters = …)` 로 이 목록을 받는다.
#   이름 규약 `wcat_<label>`:
#     · "@" 금지 — sigma_weights_month 가 `rule@est` 로 오해해 미지 추정기로 stop 한다.
#     · 빌트인 이름(EW/strategy/IV/HRP_*/minvar_*/MVO_*)과 충돌 금지 — 충돌하면
#       run_sigma_ab 가 등록분을 **제외**하고 조용히 빌트인을 쓴다(:198-203).
# ★score_tilt 는 항상 들어간다(pin). 구 캐리어 bare 축에서 incumbent 를 IR
#   1.6489 → 1.7905(+0.142)로 이겼는데 현 invested 축 배터리(h1b_sigma_ab_overlay.csv)에
#   그 팔이 **아예 없다**. 사전등록 = 06_Registry/prereg/prereg_score_tilt_invested_axis.json
#------------------------------------------------------------------------------
WC_BATTERY_PIN <- c("lean:score_tilt")

catalog_weight_arms <- function(top_k = 8L, include = WC_BATTERY_PIN, min_status = "active",
                                root = .wc_root(), quiet = FALSE) {
  A <- tryCatch(weight_catalog_arms(axis = "carrier", top_k = top_k, include = include,
                                    min_status = min_status, root = root, quiet = TRUE),
                error = function(z) { cat(sprintf("[wcat] arms 실패: %s\n", conditionMessage(z))); NULL })
  if (is.null(A) || !nrow(A)) return(list())
  nm <- paste0("wcat_", gsub("[^A-Za-z0-9_]", "_", A$label))
  bad <- grepl("@", nm, fixed = TRUE) | grepl("_lw$", nm)
  if (any(bad)) { cat(sprintf("[wcat] ★arm 이름 규약 위반 제외: %s\n", paste(nm[bad], collapse = ", ")))
                  A <- A[!bad]; nm <- nm[!bad] }
  out <- setNames(A$adapter_fn, nm)
  if (!quiet)
    cat(sprintf("[wcat] Σ-배터리 합류 %d arm: %s\n", length(out), paste(nm, collapse = ", ")))
  out
}

#------------------------------------------------------------------------------
# admit_generated — 생성물의 카탈로그 편입 (자격은 전부 재사용, 새로 만들지 않는다)
#
# 관문 4개:
#   ①정적 스캔 — **측정 필드를 읽는 생성물은 거부**. 어댑터가 성과를 보고 비중을 정하면
#     그건 어댑터가 아니라 사후선택기다(방출이 선언 축의 결정적 함수라는 chain 주장이 깨진다).
#   ②원장 대조 — 방출이 **측정보다 먼저** 기록됐는가(emitted_at 존재 · 측정 키 부재).
#   ③verify_adapter — 결정성 · 비-EW · 제약 · .nearest_arm 중복 (register_method.R:218)
#   ④status 승격 후 sync_catalog 재생성
#------------------------------------------------------------------------------
# 측정 필드 토큰 — 어댑터/생성기 소스에 이게 있으면 거부한다.
.WC_MEASURE_TOKENS <- c("hurdle_result", "bt_result", "essence_score", "module_performance",
                        "information_ratio", "portfolio_alpha_t", "abs_net_sr", "net_sr",
                        "h1b_sigma_ab", "ladder_table", "period_returns", "measured",
                        "sharpe", "calmar")

wc_scan_measurement_leak <- function(path) {
  if (!file.exists(path)) return(list(ok = FALSE, reason = sprintf("파일 부재: %s", path)))
  txt <- tolower(paste(readLines(path, warn = FALSE), collapse = "\n"))
  hit <- .WC_MEASURE_TOKENS[vapply(.WC_MEASURE_TOKENS,
                                   function(t) grepl(t, txt, fixed = TRUE), logical(1))]
  if (length(hit))
    return(list(ok = FALSE, reason = sprintf("측정 필드 참조 검출: %s", paste(hit, collapse = ", "))))
  list(ok = TRUE, reason = NA_character_)
}

admit_generated <- function(adapter_path, root = .wc_root(), method_id = NULL, resync = TRUE) {
  ap <- if (file.exists(adapter_path)) adapter_path else file.path(root, adapter_path)
  id <- method_id %|.|% sub("\\.R$", "", basename(ap))
  fail <- function(r) { cat(sprintf("[wcat:admit] %s REJECT — %s\n", id, r))
                        invisible(list(ok = FALSE, id = id, reason = r)) }

  s <- wc_scan_measurement_leak(ap)
  if (!isTRUE(s$ok)) return(fail(s$reason))

  led <- .wc_variant_ledger(root)
  rec <- led[[id]]
  if (is.null(rec)) return(fail("방출 원장 기록 부재 — 측정 전 방출 기록이 없으면 chain 주장 불가"))
  if (!nzchar(as.character(rec$emitted_at %|.|% ""))) return(fail("원장에 emitted_at 부재"))
  leak <- intersect(names(rec), c("ir", "IR", "measured", "score", "grade", "sr", "SR"))
  if (length(leak)) return(fail(sprintf("원장 기록에 측정 필드: %s", paste(leak, collapse = ", "))))

  rmp <- file.path(root, "02_Infrastructure", "methods", "register_method.R")
  if (!file.exists(rmp)) return(fail("register_method.R 부재 — verify_adapter 없이 편입하지 않는다"))
  re <- new.env(parent = globalenv())
  ok <- tryCatch({ suppressWarnings(suppressMessages(sys.source(rmp, envir = re))); TRUE },
                 error = function(z) conditionMessage(z))
  if (!isTRUE(ok)) return(fail(sprintf("register_method.R source 실패: %s", ok)))
  # ★fixture 를 **고정 축 크기(25종)** 로 맞춘다 — 게이트를 낮추는 것이 아니라 오탐을 없애는 것이다.
  #   register_method.R::rm_fixture 기본값은 8종인데, production 고정 축은 25종이고
  #   dispatch_weight_method 는 min_names=15 · hhi_cap=0.10 을 건다. 8종에서는
  #   ①min_names 15 > 8 이 원리적으로 불가 ②달성 가능한 최소 HHI 가 1/8=0.125 > 0.10 이라
  #   MVO 계열의 실현가능 집합이 **EW 한 점으로 수축**한다 → 정상 어댑터가 "EW 퇴화"로 거부된다.
  #   rm_fixture 는 이미 n_assets 를 인자로 받으므로 **같은 생성기를 크기만 바꿔** 쓴다
  #   (검사용 사본 금지 규약 유지 — fixture 를 새로 쓰지 않는다).
  if (exists("rm_fixture", envir = re, inherits = FALSE)) {
    .orig_fx <- get("rm_fixture", envir = re)
    assign("rm_fixture", function(n_assets = 25L, n_obs = 260L, seed = 20260813L)
                           .orig_fx(n_assets = 25L, n_obs = n_obs, seed = seed), envir = re)
  }
  v <- tryCatch(get("verify_adapter", envir = re)(ap, "weight", id, root = root),
                error = function(z) list(ok = FALSE, reason = conditionMessage(z)))
  if (!isTRUE(v$ok)) return(fail(sprintf("verify_adapter FAIL — %s", v$reason)))
  for (k in names(v$checks %|.|% list()))
    cat(sprintf("    %-16s %s\n", k, as.character(v$checks[[k]])))

  .wc_ledger_set_status(id, "active", root)
  if (isTRUE(resync)) sync_catalog(root = root, quiet = TRUE)
  cat(sprintf("[wcat:admit] %s ADMIT — catalog_id=gen:%s\n", id, id))
  invisible(list(ok = TRUE, id = id, catalog_id = paste0("gen:", id), checks = v$checks))
}

#' 원장에 status 승격 1줄 append (원장은 append-only — 방출 기록을 고치지 않는다).
.wc_ledger_set_status <- function(adapter_id, status, root = .wc_root()) {
  p <- file.path(root, "06_Registry", "weight_variant_ledger.jsonl")
  dir.create(dirname(p), showWarnings = FALSE, recursive = TRUE)
  rec <- .wc_variant_ledger(root)[[adapter_id]]
  o <- list(record_type = "status_update", adapter_id = adapter_id, status = status,
            trial_family_id = rec$trial_family_id %|.|% NA_character_,
            at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"))
  # 상태 갱신은 siblings[] 모양으로 적어 .wc_variant_ledger 가 그대로 흡수하게 한다.
  line <- toJSON(list(record_type = "status_update", emitted_at = rec$emitted_at %|.|% NA_character_,
                      trial_family_id = rec$trial_family_id %|.|% NA_character_,
                      n_siblings = rec$n_trials_family %|.|% 1L,
                      selection_type = rec$selection_type %|.|% "chain",
                      parent_catalog_id = rec$parent %|.|% NA_character_,
                      rule = rec$rule %|.|% NA_character_,
                      siblings = list(list(adapter_id = adapter_id, status = status,
                                           family = rec$family %|.|% "generated"))),
                 auto_unbox = TRUE, null = "null", digits = NA)
  cat(as.character(line), "\n", file = p, sep = "", append = TRUE)
  invisible(o)
}

if (!exists(".WC_QUIET_LOAD") || !isTRUE(.WC_QUIET_LOAD))
  cat("[weight_catalog.R] loaded — sync_catalog() · weight_catalog_arms() · catalog_weight_arms() · admit_generated()\n")
