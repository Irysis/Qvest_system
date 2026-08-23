# _gen_sigma.R — 생성 형제가 공유하는 Σ 추정기 (generate_weight_variants.R 가 생성).
#   ★어댑터가 아니다(`_` 접두 = weight_catalog 글롭 제외).
#   ★추정기가 조용히 표본공분산으로 낙하하는 것을 **금지**한다 — 그러면 "추정기를 갈아끼웠다"가
#     거짓이 되고 형제가 부모와 같은 것을 재게 된다(A/B 통제 붕괴).
.gen_root <- function() {
  for (k in c("CLAUDE_PROJECT_DIR", "QM_ROOT")) {
    v <- Sys.getenv(k, "")
    if (nzchar(v) && dir.exists(file.path(v, "06_Registry"))) return(v)
  }
  if (dir.exists("06_Registry")) return(getwd())
  "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
}

# 부모 규칙(calc_*) 해석기. production 은 하네스가 이미 로드한 상태로 돌지만, verify_adapter 는
#   `new.env(parent = globalenv())` 로 검사하므로 전역에 없을 수 있다. 그때 **조용히 실패하는 대신**
#   의존을 스스로 갖춘다(선례 = register_method.R 이 wrapper 의존을 갖추는 이유와 동일 —
#   의존 결손을 어댑터 결함으로 오탐하면 정상 어댑터가 거부된다).
.GEN_LEAN_ENV <- NULL
gen_lean_fn <- function(nm) {
  if (exists(nm, mode = "function")) return(get(nm, mode = "function"))
  if (is.null(.GEN_LEAN_ENV)) {
    e <- new.env(parent = globalenv())
    for (f in c("02_Infrastructure/portfolio/strategy_tilt_weights.R",
                "02_Infrastructure/portfolio/hrp_core.R",
                "02_Infrastructure/portfolio/advanced_weights.R")) {
      fp <- file.path(.gen_root(), f)
      if (file.exists(fp)) suppressWarnings(suppressMessages(try(sys.source(fp, envir = e), silent = TRUE)))
    }
    if (!exists(nm, envir = e, inherits = FALSE)) {
      # ★config.R 을 **먼저** e 에 싣는다. backtest_harness.R:18-20 은
      #     if (!exists("PROJECT_ROOT")) source(file.path(dirname(sys.frame(1)$ofile %||% "."), "config.R"))
      #   인데, 함수 안에서 부르면 `ofile` 이 없어 `./config.R` 로 낙하해 깨진다
      #   ("cannot open the connection" → 하네스 전체가 조용히 안 실림).
      #   PROJECT_ROOT 를 미리 정의해 두면 그 줄 자체가 실행되지 않는다.
      cf <- file.path(.gen_root(), "02_Infrastructure/config.R")
      if (file.exists(cf)) suppressWarnings(suppressMessages(try(sys.source(cf, envir = e), silent = TRUE)))
      fp <- file.path(.gen_root(), "02_Infrastructure/backtest_harness.R")
      if (file.exists(fp)) suppressWarnings(suppressMessages(try(sys.source(fp, envir = e), silent = TRUE)))
    }
    .GEN_LEAN_ENV <<- e
  }
  if (!exists(nm, envir = .GEN_LEAN_ENV, inherits = FALSE))
    stop(sprintf("gen_lean_fn: 부모 규칙 부재 %s (하네스/portfolio 로드 실패)", nm))
  get(nm, envir = .GEN_LEAN_ENV)
}

gen_sigma <- function(R, est = "sample") {
  a <- colnames(R)
  if (identical(est, "sample")) { S <- stats::cov(R); dimnames(S) <- list(a, a); return(S) }
  if (identical(est, "OGK")) {
    if (!exists("compute_robust_cov", mode = "function")) {
      fp <- file.path(.gen_root(), "02_Infrastructure/portfolio/advanced_weights.R")
      if (file.exists(fp)) suppressWarnings(suppressMessages(source(fp)))
    }
    if (!exists("compute_robust_cov", mode = "function"))
      stop("gen_sigma: compute_robust_cov 부재 — OGK 형제를 만들 수 없다")
    if (!isTRUE(get0(".HAS_RRCOV", ifnotfound = FALSE)))
      stop(paste0("gen_sigma: rrcov 패키지 부재 — compute_robust_cov 가 **표본공분산으로 조용히 ",
                   "낙하**한다. 그러면 OGK 형제가 sample 형제와 동일해지고 결과표엔 두 arm 으로 보인다."))
    S <- compute_robust_cov(R, method = "OGK"); dimnames(S) <- list(a, a); return(S)
  }
  if (!exists(".get_cor_cov", mode = "function")) {
    fp <- file.path(.gen_root(), "02_Infrastructure/portfolio/hrp_core.R")
    if (file.exists(fp)) suppressWarnings(suppressMessages(source(fp)))
  }
  if (!exists(".get_cor_cov", mode = "function"))
    stop("gen_sigma: .get_cor_cov 부재 (hrp_core.R 미로드)")
  cc <- .get_cor_cov(R, est)
  S <- cc$cov; dimnames(S) <- list(a, a)
  Ssamp <- stats::cov(R)
  # 비-퇴화: 표본공분산과 구별되지 않으면 추정기가 폴백했다는 뜻이다 — 이름을 부른다.
  if (max(abs(S - Ssamp)) / max(abs(Ssamp)) < 1e-10)
    stop(sprintf("gen_sigma: est=%s 산출이 표본공분산과 구별되지 않음(폴백 의심)", est))
  S
}
