#==============================================================================
# selection_reality_check.R — 선택 현실 점검 (등급 v3.4 · 스윕형 선정의 A 관문 · v10.2)
#
# 왜 (도훈 2026-11-10 "DSR은 (나) 적용" · decision_register DSR-GATE-FORM-20261110):
#   종전 DSR 관문은 ① 계보 누적 칸 수를 그대로 독립 시행 수로 세고 ② 시행 간 SR 분산을 가정값으로 두었다.
#   한 엔진의 닮은 변형 260개를 무관한 전략 260개로 센 셈이다. 여기서는 그 보정을 **실제 시행 집합의 수익 계열**에 건다 —
#   칸 사이 상관이 재표집에 그대로 실리므로 독립 시행 수를 따로 정할 필요가 없다.
#
# 무엇:
#   통계량 = 등급의 PORT_t 와 같은 식(backtest_result_contract.R::.nw_t_mean · 순 활성 수익 평균의 Newey-West t · lag = 설정).
#   귀무 = 시행 집합의 어느 전략도 벤치마크를 이기지 못한다(H_k: E[활성 수익_k] <= 0 · 한쪽 꼬리).
#   재표집 = 정상 부트스트랩(Politis & Romano 1994) — 날짜를 묶음째 뽑아 모든 전략에 같은 날짜를 쓴다(횡단면 상관 보존).
#   판정 = 단계적 다중 검정의 조정 p값(Romano & Wolf 2016 알고리즘 4.1 · max-T) — 후보의 조정 p값 <= alpha 면 통과.
#   진단 = PBO(Bailey, Borwein, López de Prado & Zhu 2017 · CSCV) · 요구 t(집합 전체의 1 − alpha 분위) · 환산 독립 시행 수.
#   수치(alpha · 재표집 수 · 블록 규칙 · PBO 분할 수)는 전부 06_Registry/grade_v3.json::selection_bias 에서 읽는다(근거 = 그 파일 *_source).
#
# 쓰는 곳: essence_score(..., selection_check = <이 계약의 결과>) — 스윕형 선정이면 A 의 관문(gates$selection_rc)이 된다.
#   결과를 넘기지 않은 스윕은 종전 DSR 관문 그대로다(경과 규정 · 소급 승격 없음). DSR 수치는 어느 쪽이든 계속 기록된다.
#
# 사용:
#   source("02_Infrastructure/contracts/selection_reality_check.R")
#   chk <- src_check_dirs(dirs = <시행 산출 폴더들>, candidate_dir = <후보 폴더>)   # 03_period_returns.csv · 05_benchmark_returns.csv
#   es  <- essence_score(bt, n_trials_cumulative = length(dirs), selection_type = "sweep", selection_check = chk)
#   Rscript 02_Infrastructure/contracts/selection_reality_check.R <후보 폴더> <시행 폴더 1> <시행 폴더 2> ...   # 요약 출력
#
# PIT: 수익 계열만 읽는다(신호 · 팩터 무접촉). 시험 창을 포함한 전 기간 계열을 쓰므로 **등급 · Judge · 사람 쪽 판정 전용**이다 —
#   처방 에이전트 · 선택 규칙의 입력으로 쓰지 않는다(정보 경계).
#==============================================================================
suppressPackageStartupMessages(library(data.table))

SRC_SCHEMA <- "selection_reality_check_v1"
SRC_METHOD <- "romano_wolf_stepdown_maxT_stationary_bootstrap"

.src_or <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

#' 프로젝트 루트 — 인자 → CLAUDE_PROJECT_DIR → QM_ROOT → 작업 폴더 순(등급 설정 파일이 있는 곳만 인정)
.src_root <- function(root = NULL) {
  for (p in c(root, Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""), getwd())) {
    if (is.null(p) || !nzchar(p)) next
    p <- gsub("\\\\", "/", p)
    if (file.exists(file.path(p, "06_Registry", "grade_v3.json"))) return(p)
  }
  stop("[selection_rc] 프로젝트 루트 해석 실패 — root 인자 또는 path 를 주어라", call. = FALSE)
}

#' 설정 판독 + 검증 — 06_Registry/grade_v3.json::selection_bias (어휘 밖 · 범위 밖이면 멈춘다)
src_cfg <- function(root = NULL, path = NULL) {
  p <- if (is.null(path)) file.path(.src_root(root), "06_Registry", "grade_v3.json") else path
  sb <- jsonlite::fromJSON(p, simplifyVector = FALSE)[["selection_bias"]]
  if (is.null(sb)) stop("[selection_rc] 설정에 selection_bias 절이 없다: ", p, call. = FALSE)
  bad <- function(m) stop("[selection_rc] selection_bias 설정 오류 — ", m, call. = FALSE)
  num1 <- function(k) { v <- suppressWarnings(as.numeric(sb[[k]])); if (length(v) != 1L || !is.finite(v)) bad(paste0(k, " 숫자 1개")); v }
  alpha <- num1("alpha"); if (!(alpha > 0 && alpha < 1)) bad("alpha 는 (0, 1)")
  B <- as.integer(num1("resamples")); if (B < 1000L) bad("resamples 는 1000 이상(Romano & Wolf 2016)")
  lag <- as.integer(num1("nw_lag")); if (lag < 0L) bad("nw_lag 는 0 이상")
  seed <- as.integer(num1("seed"))
  if (!identical(sb[["method"]], "romano_wolf_stepdown_maxT")) bad("method 어휘 밖(romano_wolf_stepdown_maxT)")
  if (!identical(sb[["bootstrap"]], "stationary")) bad("bootstrap 어휘 밖(stationary)")
  if (!identical(sb[["block_rule"]], "n_cuberoot")) bad("block_rule 어휘 밖(n_cuberoot)")
  if (!identical(sb[["missing_dates"]], "zero_active")) bad("missing_dates 어휘 밖(zero_active)")
  pb <- sb[["pbo"]]; if (!is.list(pb)) bad("pbo 절 없음")
  S <- suppressWarnings(as.integer(pb[["partitions"]])); if (length(S) != 1L || is.na(S) || S < 2L || S %% 2L != 0L) bad("pbo.partitions 는 짝수")
  role <- as.character(.src_or(pb[["role"]], "")); if (!(role %in% c("diagnostic", "gate"))) bad("pbo.role 어휘 밖(diagnostic | gate)")
  fl <- suppressWarnings(as.numeric(pb[["flag_above"]])); if (length(fl) != 1L || !is.finite(fl) || !(fl > 0 && fl < 1)) bad("pbo.flag_above 는 (0, 1)")
  list(version = as.character(.src_or(sb[["version"]], "sb?")), alpha = alpha, resamples = B, nw_lag = lag, seed = seed,
       pbo_partitions = S, pbo_role = role, pbo_flag_above = fl, path = p)
}

#' 열마다 평균 · Newey-West 표준오차 · t — backtest_result_contract.R::.nw_t_mean 과 같은 식(Bartlett 가중 · 1/n 정규화)
#' @param A 관측 x 전략 행렬(결측 없음)
src_nw <- function(A, lag = 3L) {
  A <- as.matrix(A); n <- nrow(A)
  if (n < (lag + 2L)) stop("[selection_rc] 관측이 너무 적다(n = ", n, ")", call. = FALSE)
  mu <- colMeans(A); E <- sweep(A, 2L, mu)
  s <- colSums(E^2) / n
  if (lag > 0L) for (l in seq_len(lag)) {
    w <- 1 - l / (lag + 1)
    s <- s + 2 * w * colSums(E[(l + 1L):n, , drop = FALSE] * E[1L:(n - l), , drop = FALSE]) / n
  }
  se <- sqrt(s / n); se[!(is.finite(s) & s > 0)] <- NA_real_
  list(mean = mu, se = se, t = mu / se)
}

#' 정상 부트스트랩 날짜 색인 1벌(Politis & Romano 1994) — 묶음 길이 ~ 기하분포(평균 1/p) · 끝에서 처음으로 이어 붙인다
src_sb_index <- function(n, p) {
  newb <- c(TRUE, stats::runif(n - 1L) < p)
  starts <- sample.int(n, sum(newb), replace = TRUE)
  bid <- cumsum(newb)
  off <- seq_len(n) - which(newb)[bid]
  ((starts[bid] - 1L + off) %% n) + 1L
}

#' 호출자의 난수 상태를 건드리지 않고 고정 씨앗으로 식을 돌린다
.src_with_seed <- function(seed, fn) {
  ge <- globalenv()
  old <- if (exists(".Random.seed", envir = ge, inherits = FALSE)) get(".Random.seed", envir = ge) else NULL
  on.exit(if (is.null(old)) { if (exists(".Random.seed", envir = ge, inherits = FALSE)) rm(".Random.seed", envir = ge) }
          else assign(".Random.seed", old, envir = ge), add = TRUE)
  set.seed(seed, kind = "Mersenne-Twister", normal.kind = "Inversion", sample.kind = "Rejection")
  fn()
}

#' 귀무 통계량 행렬(재표집 x 전략) — (재표집 평균 − 표본 평균) / 표본 NW 표준오차
#'   날짜 가중(각 날짜가 뽑힌 횟수)으로 평균을 한 번에 낸다: 재표집 평균 = t(W) %*% A / n
src_null_stats <- function(A, nw, B, mean_block, seed, chunk = 200L) {
  n <- nrow(A); K <- ncol(A); p <- 1 / mean_block
  Tn <- matrix(NA_real_, B, K)
  .src_with_seed(seed, function() {
    b0 <- 0L
    while (b0 < B) {
      m <- min(chunk, B - b0)
      W <- matrix(0, n, m)
      for (j in seq_len(m)) W[, j] <- tabulate(src_sb_index(n, p), nbins = n)
      Mb <- crossprod(W, A) / n
      Tn[b0 + seq_len(m), ] <<- sweep(sweep(Mb, 2L, nw$mean), 2L, nw$se, "/")
      b0 <- b0 + m
    }
    invisible(NULL)
  })
  Tn
}

#' 단계적 다중 검정의 조정 p값 — Romano & Wolf (2016) 알고리즘 4.1
#'   t 를 큰 순서로 세우고(r1..rS), max*_{t,j} = 재표집마다 (t*_{rj}, ..., t*_{rS}) 의 최댓값,
#'   p_initial_{rs} = (#{max*_{t,s} >= t_{rs}} + 1) / (M + 1), p_adj_{rs} = max(p_initial_{rs}, p_adj_{r(s−1)}).
src_stepdown_p <- function(t, Tn) {
  K <- length(t); M <- nrow(Tn)
  ord <- order(t, decreasing = TRUE)
  mx <- Tn[, ord, drop = FALSE]
  if (K > 1L) for (j in (K - 1L):1L) mx[, j] <- pmax(mx[, j], mx[, j + 1L])
  p_init <- (colSums(sweep(mx, 2L, t[ord], ">=")) + 1) / (M + 1)
  out <- numeric(K); out[ord] <- cummax(p_init); names(out) <- names(t)
  list(p_adj = out, max_all = mx[, 1L])
}

#' PBO — Bailey, Borwein, López de Prado & Zhu (2017) 의 CSCV
#'   기간을 S 개 연속 구간으로 나누고, S/2 개를 고르는 모든 조합마다 고른 쪽(IS)에서 최고인 전략의 나머지 쪽(OOS) 상대 순위
#'   w = 순위 / (N + 1), 로짓 = log(w / (1 − w)) 를 모은다. PBO = 로짓 <= 0 인 조합의 비율. 성과 통계 = 활성 수익의 평균/표준편차.
src_pbo <- function(A, S = 16L) {
  A <- as.matrix(A); n <- nrow(A); K <- ncol(A)
  if (K < 2L) return(list(status = "not_applicable", reason = "전략 1개"))
  if (n < 4L * S) return(list(status = "not_applicable", reason = "관측 부족"))
  blk <- as.integer(cut(seq_len(n), breaks = S, labels = FALSE))
  s1 <- rowsum(A, blk); s2 <- rowsum(A^2, blk); nb <- as.numeric(tabulate(blk, nbins = S))
  cmb <- utils::combn(S, S %/% 2L); C <- ncol(cmb)
  IS <- matrix(0, C, S); IS[cbind(rep(seq_len(C), each = S %/% 2L), as.vector(cmb))] <- 1
  perf <- function(sel) {
    nn <- as.vector(sel %*% nb); m <- (sel %*% s1) / nn
    v <- ((sel %*% s2) / nn - m^2) * (nn / (nn - 1))
    r <- m / sqrt(v); r[!is.finite(r)] <- -Inf; r
  }
  R_is <- perf(IS); R_oos <- perf(1 - IS)
  best <- max.col(R_is, ties.method = "first")
  rk <- vapply(seq_len(C), function(i) rank(R_oos[i, ], ties.method = "average")[best[i]], numeric(1))
  w <- rk / (K + 1); lam <- log(w / (1 - w))
  list(status = "ok", pbo = mean(lam <= 0), partitions = S, combinations = C, logit_median = stats::median(lam),
       statistic = "active_sharpe")
}

#' 시행 집합의 활성 수익 행렬로 점검한다
#' @param A          관측 x 전략 행렬(순 활성 수익 = 전략 순수익 − 벤치마크 · 결측 없음 · 열 이름 = 시행 id)
#' @param candidate  후보 시행 id(열 이름)
#' @param cfg        src_cfg() 결과
#' @param sensitivity TRUE 면 블록 길이 절반 · 두 배에서의 후보 조정 p값을 함께 낸다(진단)
src_check <- function(A, candidate, cfg, dates = NULL, fill_frac = NULL, sensitivity = FALSE) {
  A <- as.matrix(A)
  if (is.null(colnames(A)) || anyDuplicated(colnames(A))) stop("[selection_rc] 열 이름(시행 id)이 없거나 겹친다", call. = FALSE)
  if (anyNA(A)) stop("[selection_rc] 활성 수익 행렬에 결측이 있다 — src_load_trials 로 맞춰라", call. = FALSE)
  candidate <- as.character(candidate)[1]
  if (!(candidate %in% colnames(A))) stop("[selection_rc] 후보가 시행 집합에 없다: ", candidate, call. = FALSE)
  n <- nrow(A)
  nw <- src_nw(A, cfg$nw_lag)
  dropped <- colnames(A)[!is.finite(nw$t)]
  if (candidate %in% dropped) stop("[selection_rc] 후보의 통계량을 못 낸다(분산 0)", call. = FALSE)
  keep <- is.finite(nw$t)
  A2 <- A[, keep, drop = FALSE]; nw2 <- lapply(nw, function(v) v[keep])
  mean_block <- max(ceiling(n^(1 / 3)), cfg$nw_lag + 1L)
  run <- function(mb) {
    Tn <- src_null_stats(A2, nw2, cfg$resamples, mb, cfg$seed)
    src_stepdown_p(nw2$t, Tn)
  }
  sd0 <- run(mean_block)
  p_c <- unname(sd0$p_adj[candidate])
  crit <- unname(stats::quantile(sd0$max_all, 1 - cfg$alpha))
  n_eff <- if (is.finite(crit) && stats::pnorm(crit) < 1 && stats::pnorm(crit) > 0) log(1 - cfg$alpha) / log(stats::pnorm(crit)) else NA_real_
  pbo <- src_pbo(A2, cfg$pbo_partitions)
  pbo_flag <- identical(pbo$status, "ok") && is.finite(pbo$pbo) && pbo$pbo > cfg$pbo_flag_above
  pass_rc <- is.finite(p_c) && p_c <= cfg$alpha
  pass <- pass_rc && (!identical(cfg$pbo_role, "gate") || (identical(pbo$status, "ok") && !pbo_flag))
  ids <- sort(colnames(A))
  out <- list(
    schema = SRC_SCHEMA, version = cfg$version, method = SRC_METHOD,
    n_obs = n, n_trials = ncol(A2), trial_ids = as.list(colnames(A2)), dropped_zero_variance = as.list(dropped),
    candidate = candidate, candidate_t = unname(nw2$t[candidate]),
    p_adj_candidate = p_c, alpha = cfg$alpha, pass_reality_check = pass_rc, pass = pass,
    required_t = crit, effective_independent_trials = n_eff,
    p_adj = as.list(round(sd0$p_adj, 6)), t = as.list(round(nw2$t, 6)),
    resamples = cfg$resamples, mean_block = mean_block, nw_lag = cfg$nw_lag, seed = cfg$seed,
    pbo = c(pbo, list(role = cfg$pbo_role, flag_above = cfg$pbo_flag_above, flagged = pbo_flag)),
    date_from = if (is.null(dates)) NA_character_ else as.character(min(dates)),
    date_to = if (is.null(dates)) NA_character_ else as.character(max(dates)),
    fill = if (is.null(fill_frac)) NULL else list(trials_filled = sum(fill_frac > 0), max_fill_frac = max(fill_frac)),
    set_hash = .src_set_hash(ids, n, if (is.null(dates)) NULL else as.character(range(dates))),
    computed_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"))
  if (isTRUE(sensitivity)) {
    hb <- max(cfg$nw_lag + 1L, ceiling(mean_block / 2)); db <- 2L * mean_block
    out$block_sensitivity <- list(half = list(mean_block = hb, p_adj_candidate = unname(run(hb)$p_adj[candidate])),
                                  double = list(mean_block = db, p_adj_candidate = unname(run(db)$p_adj[candidate])))
  }
  out
}

#' 시행 집합 지문 — 정렬한 시행 id(분산 0 으로 빠진 칸 포함) · 관측 수 · 표본 첫날 · 끝날. src_check 와 src_gate(재계산)의 단일 출처.
.src_set_hash <- function(ids, n, date_range = NULL) {
  d <- if (is.null(date_range) || !length(date_range) || anyNA(date_range)) "" else as.character(date_range)
  digest_md5(paste(c(sort(as.character(ids)), as.character(as.integer(n)), d), collapse = "|"))
}

#' 문자열 md5(임시 파일 없이) — 시행 집합 지문용
digest_md5 <- function(s) {
  tf <- tempfile("src_md5_"); on.exit(unlink(tf), add = TRUE)
  writeBin(charToRaw(enc2utf8(s)), tf)
  unname(as.character(tools::md5sum(tf)))
}

#' 산출 폴더들에서 활성 수익 행렬을 만든다 — 표본 = 후보의 날짜 · 다른 시행에 없는 날은 활성 수익 0(벤치 보유로 간주)
#' @return list(A, dates, fill_frac, candidate)
src_load_trials <- function(dirs, candidate_dir, ids = NULL) {
  dirs <- gsub("\\\\", "/", as.character(dirs)); candidate_dir <- gsub("\\\\", "/", as.character(candidate_dir)[1])
  if (!(candidate_dir %in% dirs)) dirs <- c(candidate_dir, dirs)
  dirs <- unique(dirs)
  if (is.null(ids)) ids <- basename(dirs)
  if (anyDuplicated(ids)) ids <- make.unique(ids, sep = "#")
  one <- function(d) {
    pr <- data.table::fread(file.path(d, "03_period_returns.csv"), select = c("date", "ret_net"), showProgress = FALSE)
    br <- data.table::fread(file.path(d, "05_benchmark_returns.csv"), select = c("date", "benchmark_ret"), showProgress = FALSE)
    pr[, date := as.character(date)]; br[, date := as.character(date)]
    m <- merge(pr, br, by = "date")
    m[, active := ret_net - benchmark_ret]
    m[is.finite(active), .(date, active)]
  }
  L <- lapply(dirs, one); names(L) <- ids
  cid <- ids[match(candidate_dir, dirs)]
  base <- L[[cid]]
  if (nrow(base) == 0L) stop("[selection_rc] 후보의 수익 계열이 비었다: ", candidate_dir, call. = FALSE)
  A <- matrix(0, nrow(base), length(ids), dimnames = list(NULL, ids))
  fill <- numeric(length(ids)); names(fill) <- ids
  for (k in seq_along(ids)) {
    ix <- match(base$date, L[[k]]$date)
    v <- L[[k]]$active[ix]; miss <- is.na(v)
    fill[k] <- mean(miss); v[miss] <- 0
    A[, k] <- v
  }
  list(A = A, dates = as.Date(base$date), fill_frac = fill, candidate = cid)
}

#' 폴더 묶음으로 바로 점검한다(설정은 정본에서)
src_check_dirs <- function(dirs, candidate_dir, root = NULL, cfg = NULL, ids = NULL, sensitivity = FALSE) {
  if (is.null(cfg)) cfg <- src_cfg(root)
  X <- src_load_trials(dirs, candidate_dir, ids)
  src_check(X$A, X$candidate, cfg, dates = X$dates, fill_frac = X$fill_frac, sensitivity = sensitivity)
}

#' 관문 판독 — essence_score 가 부른다. 결과물의 형식 · 판 · 후보 일치(후보 t = 이 전략의 PORT_t)를 확인하고 통과 여부를 낸다.
#'   확인에 실패하면 통과가 아니다(fail-closed) — 사유를 함께 돌려준다.
#'   ★시행 집합 확인(G1 · 2026-11-10): 점검은 '그 선택에 영향을 줄 수 있었던 모든 칸'으로 했을 때만 의미가 있다 — 집합을 줄이면 보정이 통째로 사라진다
#'   (후보 1칸 점검 = 보정 없음). 그래서 호출자가 기대 시행 집합(expected)을 넘겨야 하고, 모르면 통과가 아니다(fail-closed):
#'     · 점검 시행 수(분산 0 으로 빠진 칸 포함) ≥ expected$n_trials(등록 시행 수 · essence 의 n_trials_cumulative)
#'     · expected$ids ⊆ 점검 시행 id · 지문(set_hash) 재계산 일치(id 목록 · 관측 수 · 표본 창을 손댄 결과물 거부)
#'     · 분산 0 으로 빠진 칸 · 후보와 날짜가 하나도 안 겹치는 칸(채움 100% = 활성 수익 전부 0)이 있으면 거부 — 그런 칸은 보정에 들어가지 않았다
#' @param port_t   이 전략의 계약 PORT_t(benchmark_compare 의 Portfolio_Alpha_t_NW_lag3)
#' @param expected list(n_trials = 등록 시행 수, ids = 등록 시행 id) — 둘 중 하나 이상. NULL · 빈 것 = 기대 집합 미지정 = 통과 아님
src_gate <- function(check, port_t, cfg, tol = 1e-6, expected = NULL) {
  no <- function(why) list(ok = FALSE, reason = why)
  if (!is.list(check) || !identical(check$schema, SRC_SCHEMA)) return(no("형식 불일치"))
  if (!identical(check$method, SRC_METHOD)) return(no("방법 불일치"))
  if (!identical(as.character(check$version), cfg$version)) return(no(paste0("설정 판 불일치(", check$version, " ≠ ", cfg$version, ")")))
  num <- function(x) suppressWarnings(as.numeric(.src_or(x, NA_real_))[1])
  ## 시행 집합(G1) — 기대 집합 미지정 · 빠진 칸 · 겹침 없는 칸 · 수 · id · 지문
  ex_n <- if (is.list(expected)) num(expected$n_trials) else NA_real_
  ex_ids <- if (is.list(expected)) unique(as.character(unlist(expected$ids))) else character(0)
  ex_ids <- ex_ids[!is.na(ex_ids) & nzchar(ex_ids)]
  if (!is.finite(ex_n) && !length(ex_ids)) return(no("기대 시행 집합 미지정(등록 시행 수 · 시행 id) — 집합 크기를 모르는 점검은 통과시키지 않는다"))
  ids <- as.character(unlist(check$trial_ids)); drp <- as.character(unlist(check$dropped_zero_variance))
  if (length(drp)) return(no(paste0("분산 0 으로 빠진 칸이 있다(", paste(drp, collapse = ","), ") — 보정에 들어가지 않은 시행")))
  if (is.list(check$fill) && is.finite(num(check$fill$max_fill_frac)) && num(check$fill$max_fill_frac) >= 1)
    return(no("후보와 날짜가 하나도 안 겹치는 칸이 있다(채움 100%)"))
  nt <- num(check$n_trials)
  if (!is.finite(nt) || !length(ids) || anyDuplicated(ids) || nt != length(ids) || !(as.character(.src_or(check$candidate, "")) %in% ids))
    return(no("시행 수 · 시행 id 목록이 서로 맞지 않는다"))
  if (is.finite(ex_n) && nt < ex_n) return(no(sprintf("점검 시행 %d < 등록 시행 %d — 선택에 영향을 준 칸을 다 담지 않았다", as.integer(nt), as.integer(ex_n))))
  if (length(ex_ids) && !all(ex_ids %in% ids)) return(no(paste0("등록 시행 id 누락: ", paste(utils::head(setdiff(ex_ids, ids), 5L), collapse = ","))))
  dr <- c(as.character(.src_or(check$date_from, NA_character_))[1], as.character(.src_or(check$date_to, NA_character_))[1])
  if (!identical(as.character(.src_or(check$set_hash, ""))[1], .src_set_hash(c(ids, drp), num(check$n_obs), dr)))
    return(no("시행 집합 지문(set_hash) 재계산 불일치 — id 목록 · 관측 수 · 표본 창이 점검 뒤 바뀌었다"))
  if (!isTRUE(all.equal(num(check$alpha), cfg$alpha, tolerance = 1e-12))) return(no("alpha 가 설정과 다르다"))
  if (!is.finite(num(check$resamples)) || num(check$resamples) < cfg$resamples) return(no("재표집 수 부족"))
  if (!identical(as.integer(num(check$nw_lag)), cfg$nw_lag)) return(no("NW lag 불일치"))
  ct <- num(check$candidate_t); pt <- num(port_t)
  if (!is.finite(ct) || !is.finite(pt) || abs(ct - pt) > tol * max(1, abs(pt))) return(no("후보 통계량이 이 전략의 PORT_t 와 다르다"))
  p <- num(check$p_adj_candidate)
  if (!is.finite(p)) return(no("조정 p값 없음"))
  ok <- p <= cfg$alpha
  why <- sprintf("조정 p %.4f %s alpha %.2f · 시행 %d · 요구 t %.2f", p, if (ok) "<=" else ">", cfg$alpha,
                 as.integer(num(check$n_trials)), num(check$required_t))
  if (identical(cfg$pbo_role, "gate")) {
    pb <- check$pbo; pv <- num(pb$pbo)
    if (!identical(pb$status, "ok") || !is.finite(pv)) return(no(paste0(why, " · PBO 미산출(관문)")))
    if (pv > cfg$pbo_flag_above) { ok <- FALSE; why <- paste0(why, sprintf(" · PBO %.3f > %.2f(관문)", pv, cfg$pbo_flag_above)) }
  }
  list(ok = ok, reason = why)
}

#' 결과 저장 · 읽기(JSON) — 후보 산출 폴더에 selection_reality_check.json 으로 둔다
src_write <- function(check, path) {
  tmp <- paste0(path, ".tmp")
  writeLines(jsonlite::toJSON(check, auto_unbox = TRUE, pretty = TRUE, digits = NA, null = "null", na = "null"), tmp, useBytes = TRUE)
  if (!file.rename(tmp, path)) { file.copy(tmp, path, overwrite = TRUE); unlink(tmp) }
  invisible(path)
}
src_read <- function(path) jsonlite::fromJSON(path, simplifyVector = FALSE)

if (sys.nframe() == 0L) {
  a <- commandArgs(trailingOnly = TRUE)
  if (length(a) >= 2L) {
    chk <- src_check_dirs(a[-1L], a[1L], sensitivity = TRUE)
    cat(sprintf("[selection_rc] 후보 %s · t %.3f · 조정 p %.4f (alpha %.2f) → %s · 시행 %d · 요구 t %.2f · 환산 독립 시행 %.1f · PBO %s\n",
                chk$candidate, chk$candidate_t, chk$p_adj_candidate, chk$alpha, if (chk$pass) "통과" else "미달",
                chk$n_trials, chk$required_t, chk$effective_independent_trials,
                if (identical(chk$pbo$status, "ok")) sprintf("%.3f", chk$pbo$pbo) else chk$pbo$status))
  } else cat("[selection_rc] Loaded — src_check_dirs(dirs, candidate_dir) · src_check(A, candidate, cfg) · src_gate(check, port_t, cfg, expected = list(n_trials, ids)).\n")
}
