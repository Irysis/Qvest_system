# tilt_attribution.R — 일간 활성수익 성분 분해 계약 (플랜 qvest-1-drifting-eclipse P2-02 · 2026-09-25 신설)
# =============================================================================
# ★라벨: "진단 — 등급 대체 아님". 등급은 essence_score.R 하나다(CLAUDE.md §등급). 이 계약의 어떤 수치도
#   등급·문턱·A 자격을 바꾸지 않는다. 선정 규칙의 입력으로 쓰려면 as-of 로만(pit.md C1 D-E) — 이 계약의 요약
#   통계(전기간 평균·NW-t·구간표)는 사후 평가량이라 선정 입력이 아니다. 일간 성분 계열과 사전 적재는 as-of 다.
#
# 왜 필요한가 (레버 감사 scratchpad/organic/lever_audit_final.md §② · 플랜 진단 2):
#   A 를 막는 구속 축은 OOS retention 이고, 그 벽의 실체는 2017~20·2025~26 에 거의 모든 칸이 같은 부호로 공유하는
#   K200 대비 활성 성분이다(PC1 54.5% · b_ewcw 중앙 0.80). retention 은 **비율**이라 IS 알파를 희석해도 올라간다 —
#   어느 성분이 벽을 만드는지 칸마다 분리해 재지 않으면 레버(PR-L1 cap_core 등)의 판정이 비율 게임이 된다.
#
# 분해 (수익일 t · 모든 노출은 t-1 까지의 정보로만 정한다):
#   a_t = r_net,t − r_K200,t
#       = market_beta_t + ew_cw_t + tilt_nsc_t + selection_t + cost_t + recon_t      (항등식 · 검사 = identity_resid)
#   요인:  f_m = r_K200 (05 CSV 벤치 = .cache/benchmark.parquet BM_Ret)
#          f_e = r_EWU − r_K200  — EW_U = 월말 시그널일 적격(K200∪KQ150 멤버 ∧ LIQ(20행 평균 거래대금, 1행 지연) ≥ 고정 축) 동일가중 ·
#                               close_t1 · 창 안 buy-and-hold(설정 ew_universe — 칸과 같은 재조정 주기). 일간 U_t(결정일 t-1 상태)는 적재 사전에 쓴다
#          f_n = s_N⊥         — 무신호 대조(시총 상위 N · 시총가중 · 월말 시그널 · close_t1)의 특이수익(1차 적재 [f_m,f_e] 제거)을
#                               다시 [f_m,f_e] 에 사전 직교화(창 [t−W,t−1] · 설정 nsc_factor — 직교화 전 corr(s_N,f_e) = −0.84 실측)
#   종목 사전 적재 β_i,t = [t−W, t−1] 창 일간 OLS(절편 포함) → 횡단면 사전으로 축소(설정 참조) · 창은 t 를 포함하지 않는다.
#   포트 노출 = Σ_i w_i,t β_i,t (w = 시작 시점 비중 — 하네스 드리프트 그대로 · 현금 포함 Σw = GL).
#   market_beta = (Σwβ_m − 1)·f_m · ew_cw = Σwβ_e·f_e · tilt_nsc = Σwβ_n·f_n · selection = Σ w·e_i (e_i = r_i − β_i·f)
#   cost = ret_net − ret_gross(03) · recon = ret_gross(03) − Σ w r (보유 재구성 잔차 — 0 이어야 한다)
#   근거 문헌·파라미터 = tilt_attribution_config.json(_source 필드 — 원문 링크).
#
# 입력 = 산출물 03_period_returns.csv · 04_holdings.csv · 05_benchmark_returns.csv (+00_manifest.json ·
#   authoritative_remeasure.json). ★같은 산출물에 remeasure_close_t1_* 형제 디렉터리가 있으면 그것이 우선이다(원장 current_axis).
# 출력 = list(label, …, daily) · ta_write() 가 JSON + 일간 CSV 로 쓴다(쓰기는 명시 out_dir 에만 — 기본 쓰기 없음).
#
# PIT 기계 (양방향 검증 = 08_Tests/contracts/test_tilt_attribution.R):
#   · 설정 가드 — 결정일 지연·유동성 지연 < 1 이면 멈춘다(fail-closed).
#   · ta_pit_probe() — 접두 불변 검사. A층: 수익일 c 이후 모든 입력을 뒤섞어도 c 의 사전 상태가 비트 동일 ·
#     B층: 결정일(c−1) 이후 거래대금 입력(C10) · 시그널일 이후 Size(C2)를 뒤섞어도 해당 상태 불변.
#
# 사용:
#   source("02_Infrastructure/contracts/tilt_attribution.R")
#   cfg <- ta_config(root)
#   mkt <- ta_load_market(root, cfg, from = ta_load_from(first_date, cfg), to = last_date, extra_tickers = held)
#   st  <- ta_build_state(mkt, cfg)
#   res <- ta_attribute(artifact_dir, st, cfg)          # 형제 close_t1 판 자동 우선
#   ta_write(res, out_dir)
# =============================================================================

suppressPackageStartupMessages({ library(data.table); library(jsonlite) })

TA_VERSION <- "tilt_attribution_v1"
TA_LABEL   <- "진단 — 등급 대체 아님"
TA_COMPONENTS <- c("market_beta", "ew_cw", "tilt_nsc", "selection")

.ta_or <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

# ── 자기 위치(같은 체크아웃의 형제 계약을 쓴다 — worktree 에서 main 을 읽지 않게) ─────────────────────
.TA_SELF_DIR <- local({
  hit <- NA_character_
  for (i in rev(seq_len(sys.nframe()))) {
    fr <- tryCatch(sys.frame(i), error = function(e) NULL)
    if (is.null(fr)) next
    for (nm in c("ofile", "file")) {
      v <- tryCatch(get0(nm, envir = fr, inherits = FALSE), error = function(e) NULL)
      if (is.character(v) && length(v) == 1L && grepl("tilt_attribution\\.R$", v)) { hit <- v; break }
    }
    if (!is.na(hit)) break
  }
  if (is.na(hit)) NA_character_ else normalizePath(dirname(hit), winslash = "/", mustWork = FALSE)
})

#' 루트 해석 — 명시 인자 > CLAUDE_PROJECT_DIR > QM_ROOT. 운영 경로 리터럴 폴백 없음(샌드박스 역류 방지).
ta_root <- function(root = NULL) {
  cands <- c(root, Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""))
  for (p in cands) {
    if (!is.character(p) || !nzchar(p)) next
    p <- gsub("\\\\", "/", p)
    if (dir.exists(file.path(p, "06_Registry")) && dir.exists(file.path(p, "02_Infrastructure")))
      return(sub("/+$", "", p))
  }
  stop("[tilt] 루트를 찾지 못했다 — root 인자 또는 CLAUDE_PROJECT_DIR/QM_ROOT 를 지정하라")
}

.ta_contract_dir <- function(root = NULL) {
  if (!is.na(.TA_SELF_DIR) && file.exists(file.path(.TA_SELF_DIR, "essence_score.R"))) return(.TA_SELF_DIR)
  file.path(ta_root(root), "02_Infrastructure", "contracts")
}

# 형제 계약(정본 재사용 — 사본 금지): essence 분할 · β-통제 α
.TA_DEP <- new.env(parent = emptyenv())
.ta_deps <- function(root = NULL) {
  if (!is.null(.TA_DEP$ess) && !is.null(.TA_DEP$bca)) return(invisible(TRUE))
  cd <- .ta_contract_dir(root)
  for (f in c("essence_score.R", "beta_controlled_alpha.R"))
    if (!file.exists(file.path(cd, f))) stop(sprintf("[tilt] 형제 계약 부재: %s/%s", cd, f))
  ess <- new.env(parent = globalenv()); bca <- new.env(parent = globalenv())
  utils::capture.output(sys.source(file.path(cd, "essence_score.R"), envir = ess, keep.source = FALSE))
  utils::capture.output(sys.source(file.path(cd, "beta_controlled_alpha.R"), envir = bca, keep.source = FALSE))
  for (fn in c(".essence_split_components", ".essence_oos_splits"))
    if (!exists(fn, envir = ess, inherits = FALSE)) stop("[tilt] essence_score.R 에 ", fn, " 가 없다 — 분할 정의를 사본으로 만들지 않는다")
  .TA_DEP$ess <- ess; .TA_DEP$bca <- bca; .TA_DEP$dir <- cd
  invisible(TRUE)
}

# ── 설정 (fail-closed) ─────────────────────────────────────────────────────────
#' @return cfg(list) + cfg$.fa(고정 축 해석값) · cfg$.path · cfg$.md5
ta_config <- function(root = NULL, path = NULL) {
  root <- ta_root(root)
  p <- .ta_or(path, file.path(root, "02_Infrastructure/contracts/tilt_attribution_config.json"))
  if (!file.exists(p)) stop("[tilt] 설정 부재: ", p, " — 기본값을 지어내지 않는다(fail-closed)")
  cfg <- jsonlite::fromJSON(p, simplifyVector = FALSE)
  need <- c("fixed_axes_source", "fixed_axes_keys", "universe", "loadings", "nw", "periods", "episodes",
            "pit_probe", "controls", "history", "no_signal_control", "nsc_factor", "ew_universe")
  miss <- setdiff(need, names(cfg))
  if (length(miss)) stop("[tilt] 설정 키 부재: ", paste(miss, collapse = ","))
  u <- cfg$universe; l <- cfg$loadings
  for (k in c("membership_flags", "liq_window_rows", "liq_lag_rows", "size_lag_rows", "decision_lag_market_days"))
    if (is.null(u[[k]])) stop("[tilt] universe.", k, " 부재")
  for (k in c("window_market_days", "min_obs", "shrink_weight_ts", "min_prior_n", "det_rel_tol"))
    if (is.null(l[[k]])) stop("[tilt] loadings.", k, " 부재")
  # ★PIT 가드 — 결정일 지연·유동성 지연이 1 미만이면 당일 정보 사용이다(C6·C10). 설정으로 끌 수 없다.
  if (as.integer(u$decision_lag_market_days) < 1L)
    stop("[tilt] PIT 가드: universe.decision_lag_market_days < 1 — 수익일 당일 멤버십 사용 금지(C6 · t-1 멤버십)")
  if (as.integer(u$liq_lag_rows) < 1L)
    stop("[tilt] PIT 가드: universe.liq_lag_rows < 1 — 결정일 당일 거래대금 사용 금지(C10)")
  if (as.integer(u$size_lag_rows) < 1L)
    stop("[tilt] PIT 가드: universe.size_lag_rows < 1 — 결정일 당일 Size 사용 금지(엔진 .SizeLag · C2)")
  if (as.integer(l$window_market_days) < as.integer(l$min_obs))
    stop("[tilt] loadings.window_market_days < min_obs — 창이 최소 관측을 담지 못한다")
  src <- as.character(cfg$fixed_axes_source)
  fa_file <- sub("::.*$", "", src); fa_key <- sub("^.*::", "", src)
  fa_path <- file.path(root, fa_file)
  if (!file.exists(fa_path)) stop("[tilt] 고정 축 원천 부재: ", fa_path)
  FA <- jsonlite::fromJSON(fa_path, simplifyVector = FALSE)[[fa_key]]
  if (is.null(FA)) stop("[tilt] 고정 축 블록 부재: ", src)
  k <- cfg$fixed_axes_keys
  for (nm in c("n_max", "liq_min", "weight_cap", "commission_bps", "start_date")) {
    kk <- k[[nm]]
    if (is.null(kk) || !(kk %in% names(FA))) stop(sprintf("[tilt] 고정 축 키 부재: %s(%s) in %s", nm, .ta_or(kk, "?"), src))
  }
  wc <- FA[[k$weight_cap]]
  cfg$.fa <- list(
    n_max = as.integer(FA[[k$n_max]]),
    liq_min = as.numeric(FA[[k$liq_min]]),
    weight_cap = if (is.null(wc)) Inf else as.numeric(wc),
    commission_bps = as.numeric(FA[[k$commission_bps]]),
    start_date = as.Date(as.character(FA[[k$start_date]])),
    source = src)
  if (!is.finite(cfg$.fa$n_max) || cfg$.fa$n_max < 1L || !is.finite(cfg$.fa$liq_min))
    stop("[tilt] 고정 축 값 비정상: n_max/liq")
  cfg$.path <- gsub("\\\\", "/", p)
  cfg$.md5 <- unname(as.character(tools::md5sum(p)))
  cfg$.root <- root
  cfg
}

# 적재 시작일 — 첫 수익일 − 필요 시장일×2 달력일(한국 시장은 달력 2일에 거래일 ≥1 — 이후 ta_build_state 가 실제 개수를 검증)
ta_need_market_days <- function(cfg)
  as.integer(cfg$history$buffer_windows) * as.integer(cfg$loadings$window_market_days) +
  as.integer(cfg$history$buffer_extra_market_days)
ta_load_from <- function(first_date, cfg) as.Date(first_date) - 2L * ta_need_market_days(cfg)

.ta_fp <- function(p) { fi <- file.info(p); list(path = gsub("\\\\", "/", p), size = unname(fi$size),
                                                 mtime = format(fi$mtime, "%Y-%m-%dT%H:%M:%S%z")) }

#' 시장 패널 적재(읽기 전용) — RAWDATA 부분 열 + 벤치. 적재 전후 지문이 다르면 멈춘다(리프레시 경합).
ta_load_market <- function(root = NULL, cfg, from, to = NULL, raw_path = NULL, bm_path = NULL,
                           extra_tickers = character(0)) {
  root <- ta_root(root)
  suppressPackageStartupMessages(library(arrow))
  rp <- .ta_or(raw_path, file.path(root, ".cache/RAWDATA.parquet"))
  bp <- .ta_or(bm_path, file.path(root, ".cache/benchmark.parquet"))
  for (p in c(rp, bp)) if (!file.exists(p)) stop("[tilt] 시장 데이터 부재: ", p)
  flags <- unlist(cfg$universe$membership_flags)
  cols <- unique(c("Date", "Ticker", "Ret", "Size", "Close", "Vol", flags))
  f0 <- list(raw = .ta_fp(rp), bm = .ta_fp(bp))
  RAW <- as.data.table(arrow::read_parquet(rp, col_select = tidyselect::all_of(cols), mmap = FALSE))
  BM  <- as.data.table(arrow::read_parquet(bp, col_select = tidyselect::all_of(c("Date", "BM_Ret")), mmap = FALSE))
  f1 <- list(raw = .ta_fp(rp), bm = .ta_fp(bp))
  if (!identical(f0, f1)) stop("[tilt] 적재 중 시장 데이터 파일이 바뀌었다 — 적재를 버린다")
  if (!inherits(RAW$Date, "Date")) RAW[, Date := as.Date(Date, tz = "Asia/Seoul")]
  if (!inherits(BM$Date, "Date"))  BM[,  Date := as.Date(Date, tz = "Asia/Seoul")]
  from <- as.Date(from); to <- if (is.null(to)) max(RAW$Date) else as.Date(to)
  RAW <- RAW[Date >= from & Date <= to]
  cal <- sort(unique(RAW$Date))
  memx <- Reduce(`|`, lapply(flags, function(f) { v <- RAW[[f]]; !is.na(v) & v == 1 }))
  tick <- sort(unique(c(RAW$Ticker[memx], as.character(extra_tickers))))
  P <- RAW[Ticker %in% tick]
  rm(RAW); invisible(gc(FALSE))
  BM <- BM[Date %in% cal]
  list(P = P, BM = BM, cal = cal, from = from, to = to,
       fp = c(f1, list(n_rows = nrow(P), n_tickers = length(tick), cal_first = format(min(cal)), cal_last = format(max(cal)))))
}

# ── 누적합 창(수익일 t 의 창 = 행 [t−W, t−1] — t 미포함) ────────────────────────────────────────────
.ta_colcumsum0 <- function(M) {
  C <- if (requireNamespace("matrixStats", quietly = TRUE)) matrixStats::colCumsums(M) else apply(M, 2, cumsum)
  if (is.null(dim(C))) C <- matrix(C, ncol = ncol(M))
  rbind(0, C)
}
.ta_window_index <- function(D, W) list(hi = seq_len(D), lo = pmax(1L, seq_len(D) - W))

#' 종목별 사전 OLS (절편 포함) — Y: D×N(NA = 결측) · X: D×K 요인(NA 허용). 반환 list(B = K 개 D×N, n = D×N)
.ta_roll_ols <- function(Y, X, W, min_obs, det_tol) {
  D <- nrow(Y); K <- ncol(X)
  okX <- rowSums(!is.finite(X)) == 0L
  O <- is.finite(Y) & okX
  Of <- O * 1
  Y0 <- Y; Y0[!O] <- 0
  X0 <- X; X0[!okX, ] <- 0
  ix <- .ta_window_index(D, W)
  ws <- function(M) { C <- .ta_colcumsum0(M); C[ix$hi, , drop = FALSE] - C[ix$lo, , drop = FALSE] }
  n  <- ws(Of)
  Sy <- ws(Y0)
  Sx <- lapply(seq_len(K), function(k) ws(Of * X0[, k]))
  Sxy <- lapply(seq_len(K), function(k) ws(Y0 * X0[, k]))
  nn <- ifelse(n > 0, n, NA_real_)
  Cxy <- lapply(seq_len(K), function(k) Sxy[[k]] - Sx[[k]] * Sy / nn)
  Cxx <- function(k, l) ws(Of * (X0[, k] * X0[, l])) - Sx[[k]] * Sx[[l]] / nn
  valid <- n >= min_obs
  if (K == 2L) {
    a <- Cxx(1, 1); b <- Cxx(1, 2); d <- Cxx(2, 2)
    det <- a * d - b^2
    rel <- det / (a * d)
    ok <- valid & is.finite(rel) & a > 0 & d > 0 & rel > det_tol
    B1 <- (d * Cxy[[1]] - b * Cxy[[2]]) / det
    B2 <- (a * Cxy[[2]] - b * Cxy[[1]]) / det
    B <- list(B1, B2)
  } else if (K == 3L) {
    a <- Cxx(1, 1); b <- Cxx(1, 2); c3 <- Cxx(1, 3); d <- Cxx(2, 2); e <- Cxx(2, 3); f <- Cxx(3, 3)
    i11 <- d * f - e^2; i12 <- c3 * e - b * f; i13 <- b * e - c3 * d
    i22 <- a * f - c3^2; i23 <- b * c3 - a * e; i33 <- a * d - b^2
    det <- a * i11 + b * i12 + c3 * i13
    rel <- det / (a * d * f)
    ok <- valid & is.finite(rel) & a > 0 & d > 0 & f > 0 & rel > det_tol
    y1 <- Cxy[[1]]; y2 <- Cxy[[2]]; y3 <- Cxy[[3]]
    B <- list((i11 * y1 + i12 * y2 + i13 * y3) / det,
              (i12 * y1 + i22 * y2 + i23 * y3) / det,
              (i13 * y1 + i23 * y2 + i33 * y3) / det)
  } else stop("[tilt] .ta_roll_ols: K ∈ {2,3} 만 지원")
  B <- lapply(B, function(M) { M[!ok | !is.finite(M)] <- NA_real_; M })
  list(B = B, n = n)
}

#' 횡단면 사전 축소 — prior_t = 그날 U_t 멤버 TS 적재 평균(표본 < min_n 이면 사전 없음 → TS 그대로)
#'   최종 = w·TS + (1−w)·prior · TS 부재(관측 부족) = prior(폴백 — 비율을 진단에 남긴다)
.ta_shrink <- function(B, U, w, min_n) {
  lapply(B, function(M) {
    ok <- U & is.finite(M)
    cnt <- rowSums(ok)
    prior <- rowSums(ifelse(ok, M, 0)) / cnt
    prior[cnt < min_n] <- NA_real_
    has <- is.finite(M); hp <- matrix(is.finite(prior), nrow(M), ncol(M))
    out <- M
    out[has & hp] <- (w * M + (1 - w) * prior)[has & hp]
    out[!has & hp] <- matrix(prior, nrow(M), ncol(M))[!has & hp]
    attr(out, "fallback_frac_U") <- sum(U & !has & hp) / max(1, sum(U & hp))
    attr(out, "prior") <- prior
    out
  })
}

# ── 월 격자(시그널 = 달의 마지막 시장일 · 집행 = 다음 달 첫 시장일 = get_execution_date 규약) ──────────
.ta_month_grid <- function(cal, from_idx = 1L) {
  ym <- format(cal, "%Y-%m")
  sig <- which(!duplicated(ym, fromLast = TRUE))
  ex <- vapply(sig, function(s) {
    y <- as.integer(substr(ym[s], 1, 4)); m <- as.integer(substr(ym[s], 6, 7))
    if (m == 12L) { y <- y + 1L; m <- 1L } else m <- m + 1L
    j <- which(cal >= as.Date(sprintf("%04d-%02d-01", y, m)))
    if (length(j)) j[1] else NA_integer_
  }, integer(1))
  g <- data.table(sig_idx = sig, exec_idx = ex)[!is.na(exec_idx) & sig_idx >= from_idx]
  g
}

.ta_cap_weights <- function(w, cap, iters = 200L) {
  w <- w / sum(w)
  if (!is.finite(cap)) return(w)
  for (i in seq_len(iters)) {
    ov <- w > cap + 1e-12
    if (!any(ov)) break
    ex <- sum(w[ov] - cap); w[ov] <- cap; fr <- !ov
    if (!any(fr) || sum(w[fr]) <= 0) break
    w[fr] <- w[fr] + ex * w[fr] / sum(w[fr])
  }
  w / sum(w)
}

#' 무신호 대조 보유(시그널일 상태만: 멤버십·LIQ(C10 지연)·Size(엔진 .SizeLag) — 신호 미사용)
.ta_nsc_holdings <- function(st_core, cfg, from_idx) {
  g <- .ta_month_grid(st_core$cal, from_idx)
  n <- cfg$.fa$n_max; cap <- cfg$.fa$weight_cap
  out <- vector("list", nrow(g))
  for (k in seq_len(nrow(g))) {
    s <- g$sig_idx[k]
    sz <- st_core$SIZE_L[s, ]
    cand <- which(st_core$ELIG[s, ] & is.finite(sz) & sz > 0)
    if (!length(cand)) next
    o <- cand[order(-sz[cand], st_core$tickers[cand])]
    top <- head(o, n)
    out[[k]] <- data.table(Exec = st_core$cal[g$exec_idx[k]], Ticker = st_core$tickers[top],
                           Weight = .ta_cap_weights(sz[top], cap), sig_idx = s)
  }
  rbindlist(out)
}

#' 보유(집행일 목표 비중) → 시작 시점 일간 비중 (replication_harness.R 규약 그대로)
#'   close_t1 창 (E_k, E_{k+1}] · close_d_legacy 창 [E_k, E_{k+1}) · 레그별 Σ|w| = gross · 창 안 결측 수익 = 0 ·
#'   창 안 유한 수익이 1개도 없는 종목은 빠지고 나머지로 재정규화(Return.portfolio 열 규약) · 드리프트 = buy-and-hold.
#' @param H data.table(Exec<Date>, Ticker<chr>, Weight<num>)
#' @return data.table(di, ti, w) — w 부호 포함 · Σ_i w = GL − GS
.ta_daily_weights <- function(H, st, exec_price = c("close_t1", "close_d_legacy")) {
  exec_price <- match.arg(exec_price)
  H <- as.data.table(H)[is.finite(Weight) & Weight != 0]
  if (!nrow(H)) return(data.table(di = integer(0), ti = integer(0), w = numeric(0)))
  ex <- sort(unique(as.Date(H$Exec)))
  ei <- match(ex, st$cal)
  if (anyNA(ei)) stop("[tilt] 집행일이 시장 달력에 없다: ", paste(format(ex[is.na(ei)]), collapse = ","))
  D <- length(st$cal)
  tmiss <- setdiff(unique(H$Ticker), st$tickers)
  if (length(tmiss)) stop(sprintf("[tilt] 상태에 없는 보유 종목 %d개(예: %s) — ta_load_market(extra_tickers=) 로 실어라",
                                  length(tmiss), paste(head(tmiss, 3), collapse = ",")))
  out <- vector("list", 2L * length(ex)); j <- 0L
  for (k in seq_along(ex)) {
    if (exec_price == "close_t1") {
      lo <- ei[k] + 1L; hi <- if (k < length(ex)) ei[k + 1L] else D
    } else {
      lo <- ei[k]; hi <- if (k < length(ex)) ei[k + 1L] - 1L else D
    }
    if (lo > hi || lo > D) next
    days <- lo:hi
    hk <- H[Exec == ex[k]]
    ti_all <- match(hk$Ticker, st$tickers)
    for (leg in c(1, -1)) {
      sel <- which(sign(hk$Weight) == leg)
      if (!length(sel)) next
      gross <- sum(abs(hk$Weight[sel]))
      tix <- ti_all[sel]
      Rw_na <- st$R[days, tix, drop = FALSE]
      has <- colSums(is.finite(Rw_na)) > 0
      if (!any(has)) next
      wn <- abs(hk$Weight[sel][has]); wn <- wn / sum(wn)
      Rw <- st$R0[days, tix[has], drop = FALSE]
      G <- apply(1 + Rw, 2, cumprod)
      if (is.null(dim(G))) G <- matrix(G, nrow = length(days))
      Gb <- rbind(rep(1, ncol(G)), G[-nrow(G), , drop = FALSE])    # 시작 시점 = 전일까지 누적(당일 수익 미포함)
      V <- sweep(Gb, 2, wn, `*`)
      Wt <- V / rowSums(V)
      j <- j + 1L
      out[[j]] <- data.table(di = rep(days, times = ncol(Wt)), ti = rep(tix[has], each = length(days)),
                             w = leg * gross * as.vector(Wt))
    }
  }
  rbindlist(out[seq_len(j)])
}

#' 비용 포함 순수익(하네스 close_t1 기장 — 새 보유 첫 날 곱셈 차감 · 회전 = 목표 비중 Σ|Δw|)
.ta_net_from_holdings <- function(H, gross_daily, st, bps, exec_price = "close_t1") {
  H <- as.data.table(H)[is.finite(Weight) & Weight != 0]
  ex <- sort(unique(as.Date(H$Exec))); ei <- match(ex, st$cal)
  net <- copy(gross_daily)                    # data.table(di, r)
  prev <- NULL
  for (k in seq_along(ex)) {
    cur <- setNames(H[Exec == ex[k]]$Weight, H[Exec == ex[k]]$Ticker)
    to <- if (is.null(prev)) sum(abs(cur)) else {
      al <- union(names(cur), names(prev)); a <- cur[al]; a[is.na(a)] <- 0; b <- prev[al]; b[is.na(b)] <- 0; sum(abs(a - b)) }
    prev <- cur
    cd <- if (exec_price == "close_t1") ei[k] + 1L else ei[k]
    kk <- to * bps / 1e4
    if (exec_price == "close_t1") net[di == cd, r := (1 - kk) * (1 + r) - 1] else net[di == cd, r := r - kk]
  }
  net
}

#' 포트 성분(요인 노출 × 요인 실현 · 선별) — WL = .ta_daily_weights() 반환
ta_decompose <- function(WL, st) {
  WL <- copy(as.data.table(WL))
  if (nrow(WL)) {
    idx <- cbind(WL$di, WL$ti)
    WL[, `:=`(bm = st$Bm[idx], be = st$Be[idx], bn = st$Bn[idx], b2e = st$B2e[idx], e = st$E0[idx], r = st$R0[idx])]
  }
  A <- WL[, .(GL = sum(w), beta_m = sum(w * bm), beta_e = sum(w * be), beta_n = sum(w * bn),
              b_ewcw_2f = sum(w * b2e), s_p = sum(w * e), r_rec = sum(w * r), n_hold = .N,
              n_na = sum(!is.finite(bm) | !is.finite(be) | !is.finite(bn) | !is.finite(e))), by = di]
  setorder(A, di)
  A[, `:=`(date = st$cal[di], rb = st$rb[di], fe = st$fe[di], fn = st$fn[di])]
  A[, `:=`(market_beta = (beta_m - 1) * rb, ew_cw = beta_e * fe, tilt_nsc = beta_n * fn, selection = s_p)]
  A[]
}

# ── 상태 구축 ──────────────────────────────────────────────────────────────────
#' @param upto 이 날짜까지만(접두) — 탐침용. tickers = 열 집합 고정(탐침 비교용)
ta_build_state <- function(mkt, cfg, tickers = NULL, upto = NULL) {
  u <- cfg$universe; l <- cfg$loadings
  cal <- mkt$cal; P <- mkt$P
  if (!is.null(upto)) { cal <- cal[cal <= as.Date(upto)]; P <- P[Date <= as.Date(upto)] }
  if (is.null(tickers)) tickers <- sort(unique(P$Ticker))
  P <- P[Ticker %in% tickers]
  P <- copy(P); setorder(P, Ticker, Date)
  flags <- unlist(u$membership_flags)
  L <- as.integer(u$liq_window_rows); llag <- as.integer(u$liq_lag_rows)
  slag <- as.integer(u$size_lag_rows); dlag <- as.integer(u$decision_lag_market_days)
  if (dlag < 1L || llag < 1L || slag < 1L) stop("[tilt] PIT 가드: 지연 < 1")
  liq <- cfg$.fa$liq_min
  P[, .mem := Reduce(`|`, lapply(flags, function(f) { v <- get(f); !is.na(v) & v == 1 }))]
  P[, .tv := as.numeric(Close) * as.numeric(Vol)]
  P[, .adv := shift(frollmean(.tv, L, align = "right"), llag), by = Ticker]     # C10 — 결정일 당일 거래대금 제외
  P[, .size_l := shift(Size, slag), by = Ticker]                               # C2 — 엔진 .SizeLag
  P[, .elig := .mem & !is.na(.adv) & .adv >= liq]
  D <- length(cal); N <- length(tickers)
  if (D < 2L) stop("[tilt] 시장일 < 2")
  pos <- cbind(match(P$Date, cal), match(P$Ticker, tickers))
  R <- matrix(NA_real_, D, N); R[pos] <- P$Ret; R[!is.finite(R)] <- NA_real_
  ELIG <- matrix(FALSE, D, N); ELIG[pos] <- P$.elig
  SIZE_L <- matrix(NA_real_, D, N); SIZE_L[pos] <- P$.size_l
  rm(P); invisible(gc(FALSE))
  # U_t = 결정일(t − dlag) 상태 — 수익일 당일 플래그는 쓰지 않는다(C6 · t-1 멤버십)
  U <- matrix(FALSE, D, N)
  if (D > dlag) U[(dlag + 1L):D, ] <- ELIG[1:(D - dlag), , drop = FALSE]
  rb <- mkt$BM$BM_Ret[match(cal, mkt$BM$Date)]
  R0 <- R; R0[is.na(R0)] <- 0
  core <- list(cal = cal, tickers = tickers, R = R, R0 = R0, ELIG = ELIG, SIZE_L = SIZE_L)
  ew_mode <- .ta_or(cfg$ew_universe$rebalance, NA_character_)
  WU <- NULL
  if (identical(ew_mode, "daily")) {                 # 감사 대조용 — U_t 일간 동일가중
    UR <- U & is.finite(R)
    nU <- rowSums(UR)
    rU <- rowSums(ifelse(UR, R, 0)) / nU
    rU[nU == 0L] <- NA_real_
  } else if (identical(ew_mode, "monthly_bh")) {     # 기본 — 시그널일 적격 동일가중 · close_t1 · 창 안 buy-and-hold
    HU <- .ta_grid_holdings(core, cfg, cal[1], function(cand, s) cand)
    WU <- .ta_daily_weights(HU, core, "close_t1")
    rU <- rep(NA_real_, D); nU <- integer(D)
    if (nrow(WU)) {
      WU[, r := R0[cbind(di, ti)]]
      a <- WU[, .(r = sum(w * r), n = .N), by = di]
      rU[a$di] <- a$r; nU[a$di] <- a$n
      WU[, r := NULL]
    }
  } else stop("[tilt] ew_universe.rebalance 미지원/부재: ", ew_mode, " (monthly_bh | daily)")
  fe <- rU - rb
  W <- as.integer(l$window_market_days); mo <- as.integer(l$min_obs)
  wts <- as.numeric(l$shrink_weight_ts); mpn <- as.integer(l$min_prior_n); dt <- as.numeric(l$det_rel_tol)
  # 1차 적재 [f_m, f_e]
  L1 <- .ta_roll_ols(R, cbind(rb, fe), W, mo, dt)
  B1 <- .ta_shrink(L1$B, U, wts, mpn)
  E1 <- R0 - B1[[1]] * rb - B1[[2]] * fe
  # 무신호 대조: 1차 사전(prior)이 선 뒤부터
  pr_ok <- which(is.finite(attr(B1[[1]], "prior")) & is.finite(attr(B1[[2]], "prior")))
  if (!length(pr_ok)) stop("[tilt] 1차 적재 사전이 한 번도 서지 않는다 — 적재 창/표본 확인")
  NSC_H <- .ta_nsc_holdings(core, cfg, from_idx = pr_ok[1])
  if (!nrow(NSC_H)) stop("[tilt] 무신호 대조 보유 0")
  WN <- .ta_daily_weights(NSC_H[, .(Exec, Ticker, Weight)], core, "close_t1")
  sN <- rep(NA_real_, D); rN <- rep(NA_real_, D)
  if (nrow(WN)) {
    WN[, `:=`(e1 = E1[cbind(di, ti)], r0 = R0[cbind(di, ti)])]
    agg <- WN[, .(s = sum(w * e1), r = sum(w * r0)), by = di]
    sN[agg$di] <- agg$s; rN[agg$di] <- agg$r
    WN[, c("e1", "r0") := NULL]
  }
  rm(E1); invisible(gc(FALSE))
  # 무신호 대조 요인의 사전 직교화 — f_n = s_N − ĥ·f_m − ĝ·f_e (계수 = [t−W, t−1] 창 · 절편 미차감) · 설정 nsc_factor
  if (!identical(.ta_or(cfg$nsc_factor$orthogonalize, NA_character_), "exante_rolling_on_fm_fe"))
    stop("[tilt] nsc_factor.orthogonalize 미지원/부재: ", .ta_or(cfg$nsc_factor$orthogonalize, "NULL"))
  Lo <- .ta_roll_ols(matrix(sN, ncol = 1L), cbind(rb, fe), W, mo, dt)
  fn <- sN - Lo$B[[1]][, 1] * rb - Lo$B[[2]][, 1] * fe
  # 2차 적재 [f_m, f_e, f_n]
  L2 <- .ta_roll_ols(R, cbind(rb, fe, fn), W, mo, dt)
  B2 <- .ta_shrink(L2$B, U, wts, mpn)
  fnz <- ifelse(is.finite(fn), fn, NA_real_)
  E0 <- R0 - B2[[1]] * rb - B2[[2]] * fe - B2[[3]] * fnz
  st <- list(version = TA_VERSION, cal = cal, tickers = tickers, D = D, N = N,
             R = R, R0 = R0, U = U, ELIG = ELIG, SIZE_L = SIZE_L,
             rb = rb, rU = rU, nU = nU, fe = fe, fn = fn, sN_raw = sN, rN_gross = rN,
             Bm = B2[[1]], Be = B2[[2]], Bn = B2[[3]], B2e = B1[[2]], B2m = B1[[1]], E0 = E0,
             NSC_H = NSC_H, WN = WN, WU = WU, ew_mode = ew_mode,
             diag = list(fallback_frac = c(m = attr(B2[[1]], "fallback_frac_U"), e = attr(B2[[2]], "fallback_frac_U"),
                                          n = attr(B2[[3]], "fallback_frac_U")),
                         first_fn = if (any(is.finite(fn))) format(cal[which(is.finite(fn))[1]]) else NA_character_,
                         nU_median = stats::median(nU[nU > 0]),
                         cfg_md5 = cfg$.md5, fp = mkt$fp))
  st
}

# ── 통계 부품 ─────────────────────────────────────────────────────────────────
#' NW t (평균) — backtest_result_contract.R::.nw_t_mean 과 같은 식(Bartlett · /n). lag=3 이면 PORT_t 와 같다(패리티 검사).
.ta_nw_t <- function(x, lag) {
  x <- x[!is.na(x)]; n <- length(x); lag <- as.integer(lag)
  if (n < (lag + 2L)) return(NA_real_)
  mu <- mean(x); e <- x - mu
  s <- sum(e^2) / n
  if (lag >= 1L) for (l in seq_len(lag)) { w <- 1 - l / (lag + 1); s <- s + 2 * w * sum(e[(l + 1):n] * e[1:(n - l)]) / n }
  if (s <= 0) return(NA_real_)
  mu / sqrt(s / n)
}
.ta_nw_lag <- function(n, rule) {
  if (!identical(rule, "nw1994_bartlett")) stop("[tilt] 미지 nw.lag_rule: ", rule)
  max(1L, as.integer(floor(4 * (n / 100)^(2 / 9))))
}
.ta_stats <- function(x, a, lag, house_lag, af = 252) {
  ok <- is.finite(x) & is.finite(a); x <- x[ok]; a <- a[ok]
  va <- stats::var(a)
  list(n = length(x), ann_mean = mean(x) * af, sum = sum(x),
       ir = if (stats::sd(x) > 0) mean(x) / stats::sd(x) * sqrt(af) else NA_real_,
       nw_t = .ta_nw_t(x, lag), nw_t_house = .ta_nw_t(x, house_lag),
       share_of_active_sum = if (abs(sum(a)) > 0) sum(x) / sum(a) else NA_real_,
       var_share = if (is.finite(va) && va > 0) stats::cov(x, a) / va else NA_real_)
}

# 낙폭 구간(고점 → 저점) — nav 계열에서 깊이 상위 k
.ta_dd_episodes <- function(r, dates, k) {
  nav <- cumprod(1 + ifelse(is.finite(r), r, 0))
  pk <- cummax(c(1, nav))[-1]
  dd <- nav / pk - 1
  eps <- list(); i <- 1L; n <- length(dd)
  while (i <= n) {
    if (dd[i] < 0) {
      j <- i; while (j <= n && dd[j] < 0) j <- j + 1L
      seg <- i:(j - 1L); tr <- seg[which.min(dd[seg])]
      eps[[length(eps) + 1L]] <- list(start = i, trough = tr, end = j - 1L, depth = dd[tr])
      i <- j
    } else i <- i + 1L
  }
  if (!length(eps)) return(list())
  o <- order(vapply(eps, function(e) e$depth, numeric(1)))
  eps <- eps[head(o, k)]
  lapply(eps, function(e) c(e, list(from = format(dates[e$start]), to = format(dates[e$trough]))))
}

.ta_episode_table <- function(Dt, ep, kind) {
  cols <- c(TA_COMPONENTS, "cost", "recon")
  rbindlist(lapply(ep, function(e) {
    s <- Dt[e$start:e$trough]
    act <- sum(s$active)
    row <- data.table(kind = kind, from = e$from, to = e$to, depth = e$depth, n_days = nrow(s),
                      bench_sum = sum(s$benchmark_ret), strat_sum = sum(s$ret_net), active_sum = act)
    for (cc in cols) { row[[paste0(cc, "_sum")]] <- sum(s[[cc]]); row[[paste0(cc, "_share")]] <- if (abs(act) > 0) sum(s[[cc]]) / act else NA_real_ }
    row
  }), fill = TRUE)
}

# ── 산출물 해석 ───────────────────────────────────────────────────────────────
#' 산출물 디렉터리 → 입력 판(remeasure_close_t1_* 형제 우선). 반환 list(dir, exec_price, regime_key, basis)
ta_resolve_artifact <- function(artifact_dir, prefer = "close_t1", regime_key = NULL) {
  ad <- sub("/+$", "", gsub("\\\\", "/", artifact_dir))
  if (!dir.exists(ad)) stop("[tilt] 산출물 디렉터리 부재: ", ad)
  sib <- list.dirs(ad, recursive = FALSE, full.names = TRUE)
  sib <- sib[grepl(paste0("^remeasure_", prefer, "_"), basename(sib))]
  if (!is.null(regime_key)) sib <- sib[basename(sib) == paste0("remeasure_", regime_key)]
  use <- ad; basis <- "artifact_dir"
  if (length(sib) > 1L) stop("[tilt] 형제 판이 여럿이다 — regime_key 로 지정하라: ", paste(basename(sib), collapse = ","))
  if (length(sib) == 1L) { use <- gsub("\\\\", "/", sib); basis <- paste0("sibling:", basename(sib)) }
  need <- file.path(use, c("03_period_returns.csv", "04_holdings.csv", "05_benchmark_returns.csv"))
  if (!all(file.exists(need))) stop("[tilt] 입력 CSV 부재: ", paste(basename(need[!file.exists(need)]), collapse = ","))
  ep <- NA_character_; rk <- NA_character_
  ap <- file.path(use, "authoritative_remeasure.json")
  if (file.exists(ap)) {
    au <- tryCatch(jsonlite::fromJSON(ap, simplifyVector = TRUE), error = function(e) NULL)
    ep <- .ta_or(au$measurement_regime$exec_price, NA_character_); rk <- .ta_or(au$measurement_regime$key, NA_character_)
  }
  if (is.na(ep)) {
    mp <- file.path(use, "00_manifest.json")
    cmv <- if (file.exists(mp)) .ta_or(jsonlite::fromJSON(mp)$cost_model_version, "") else ""
    ep <- if (grepl("first_hold_day_multiplicative$", cmv)) "close_t1" else if (grepl("exec_day_additive$", cmv)) "close_d_legacy" else NA_character_
  }
  if (is.na(ep) || !(ep %in% c("close_t1", "close_d_legacy")))
    stop("[tilt] 집행 규약 판독 불가/미지원(", ep, ") — close_t1 · close_d_legacy 만 재구성한다: ", use)
  list(dir = use, exec_price = ep, regime_key = rk, basis = basis, of_artifact = ad)
}

ta_read_holdings <- function(dir) {
  h <- fread(file.path(dir, "04_holdings.csv"), colClasses = list(character = c("ticker")))
  wc <- if ("actual_weight" %in% names(h)) "actual_weight" else "target_weight"
  h[, .(Exec = as.Date(date), Ticker = as.character(ticker), Weight = as.numeric(get(wc)))]
}

# ── 본체 ──────────────────────────────────────────────────────────────────────
#' 칸 1개 분해 + 요약. pit = ta_pit_probe() 결과(선택 — 부착만 한다).
ta_attribute <- function(artifact_dir, st, cfg, regime_key = NULL, pit = NULL, keep_daily = TRUE,
                         inject_alpha_ann = NULL) {
  .ta_deps(cfg$.root)
  src <- ta_resolve_artifact(artifact_dir, regime_key = regime_key)
  PR <- fread(file.path(src$dir, "03_period_returns.csv"))
  BR <- fread(file.path(src$dir, "05_benchmark_returns.csv"))
  H  <- ta_read_holdings(src$dir)
  man <- tryCatch(jsonlite::fromJSON(file.path(src$dir, "00_manifest.json")), error = function(e) list())
  auth <- tryCatch(jsonlite::fromJSON(file.path(src$dir, "authoritative_remeasure.json"), simplifyVector = TRUE), error = function(e) NULL)
  bps <- suppressWarnings(as.numeric(.ta_or(man$transaction_cost_bps, NA)))
  if (!is.finite(bps)) bps <- cfg$.fa$commission_bps
  WL <- .ta_daily_weights(H, st, src$exec_price)
  CMP <- ta_decompose(WL, st)
  PR[, date := as.Date(date)]; BR[, date := as.Date(date)]
  Dt <- merge(PR[, .(date, ret_gross, ret_net)], BR[, .(date, benchmark_ret)], by = "date")
  setorder(Dt, date)
  Dt <- Dt[is.finite(ret_net) & is.finite(benchmark_ret)]
  if (!is.null(inject_alpha_ann)) {
    # 양성 대조(b) 회계판 — 보유 종목 수익에 알려진 초과수익 δ 를 더한 세계: 포트 수익 += δ·Σw(보유 가중) ·
    #   노출·요인은 그대로다(주입은 종목 특이수익). 기대 = 선별 성분만 δ·Σw 만큼 움직인다.
    dlt <- as.numeric(inject_alpha_ann) / 252
    add <- WL[, .(dS = dlt * sum(w)), by = di][, date := st$cal[di]]
    CMP[add, on = "di", `:=`(selection = selection + i.dS, r_rec = r_rec + i.dS)]
    Dt[add, on = "date", `:=`(ret_gross = ret_gross + i.dS, ret_net = ret_net + i.dS)]
  }
  miss_days <- Dt[!CMP, on = "date"]
  Dt <- merge(Dt, CMP[, .(date, GL, beta_m, beta_e, beta_n, b_ewcw_2f, r_rec, rb, fe, fn, n_hold, n_na,
                          market_beta, ew_cw, tilt_nsc, selection)], by = "date", all.x = TRUE)
  # 보유 행이 없는 날 = 하네스 수익 0(Lr NA→0) — 노출 0 · 현금
  Dt[is.na(GL), `:=`(GL = 0, beta_m = 0, beta_e = 0, beta_n = 0, b_ewcw_2f = 0, r_rec = 0, n_hold = 0L, n_na = 0L,
                     rb = st$rb[match(date, st$cal)], fe = st$fe[match(date, st$cal)], fn = st$fn[match(date, st$cal)])]
  Dt[is.na(market_beta), `:=`(market_beta = (beta_m - 1) * rb, ew_cw = 0, tilt_nsc = 0, selection = 0)]
  bench_gap <- max(abs(Dt$benchmark_ret - Dt$rb), na.rm = TRUE)
  if (!is.finite(bench_gap) || bench_gap > 1e-10)
    stop(sprintf("[tilt] 벤치 불일치 max|05 − 상태 rb| = %.3g — 같은 벤치로 분해하지 않으면 성분이 섞인다", bench_gap))
  n_na_days <- sum(Dt$n_na > 0 | !is.finite(Dt$ew_cw) | !is.finite(Dt$tilt_nsc) | !is.finite(Dt$selection))
  if (n_na_days > 0L)
    stop(sprintf("[tilt] 적재 결측 %d일 — 적재 창이 칸 시작 전에 서지 않았다(ta_load_from 확인)", n_na_days))
  Dt[, `:=`(active = ret_net - benchmark_ret, cost = ret_net - ret_gross, recon = ret_gross - r_rec)]
  Dt[, identity_resid := active - (market_beta + ew_cw + tilt_nsc + selection + cost + recon)]
  ## 요약
  n <- nrow(Dt); lag <- .ta_nw_lag(n, cfg$nw$lag_rule); hl <- as.integer(cfg$nw$house_lag)
  cols <- c(TA_COMPONENTS, "cost", "recon")
  full <- c(list(active = .ta_stats(Dt$active, Dt$active, lag, hl)),
            setNames(lapply(cols, function(cc) .ta_stats(Dt[[cc]], Dt$active, lag, hl)), cols),
            list(signal_part = .ta_stats(Dt$tilt_nsc + Dt$selection, Dt$active, lag, hl)))
  per <- rbindlist(lapply(cfg$periods, function(p) {
    s <- Dt[date >= as.Date(p$from) & date <= as.Date(p$to)]
    if (nrow(s) < 20L) return(NULL)
    lp <- .ta_nw_lag(nrow(s), cfg$nw$lag_rule)
    rbindlist(lapply(c("active", cols), function(cc) {
      z <- .ta_stats(s[[cc]], s$active, lp, hl)
      data.table(period = p$id, from = p$from, to = p$to, component = cc, n = z$n, ann_mean = z$ann_mean,
                 ir = z$ir, nw_t = z$nw_t, share_of_active_sum = z$share_of_active_sum, var_share = z$var_share)
    }))[, `:=`(beta_m_mean = mean(s$beta_m), beta_e_mean = mean(s$beta_e), beta_n_mean = mean(s$beta_n),
               b_ewcw_2f_mean = mean(s$b_ewcw_2f), GL_mean = mean(s$GL))]
  }))
  # retention — essence 분할 그대로(사본 없음)
  ess <- .TA_DEP$ess
  spl <- ess$.essence_oos_splits("v2")
  ret_of <- function(x) {
    cc <- ess$.essence_split_components(x, spl, 252)
    rr <- vapply(cc, function(z) as.numeric(z$retention), numeric(1))
    list(retention = if (any(is.finite(rr))) stats::median(rr[is.finite(rr)]) else NA_real_,
         splits = lapply(cc, function(z) list(split = z$split, is_ir = z$is_ir, oos_ir = z$oos_ir, retention = z$retention)))
  }
  retn <- c(list(active = ret_of(Dt$active)),
            setNames(lapply(cols, function(cc) ret_of(Dt[[cc]])), cols),
            setNames(lapply(TA_COMPONENTS, function(cc) ret_of(Dt$active - Dt[[cc]])), paste0("active_ex_", TA_COMPONENTS)),
            list(active_ex_common = ret_of(Dt$active - Dt$market_beta - Dt$ew_cw),
                 signal_part = ret_of(Dt$tilt_nsc + Dt$selection)))
  # β-통제 α (정본 계약 — 일간 · NW lag = 규칙)
  bca <- tryCatch(.TA_DEP$bca$beta_controlled_alpha(Dt$ret_net, Dt$benchmark_ret, periods_per_year = 252, nw_lag = lag),
                  error = function(e) list(error = conditionMessage(e)))
  # 무신호 대조 대비(같은 창 · 대조 순수익 = 같은 비용 규약)
  gN <- data.table(di = which(is.finite(st$rN_gross)), r = st$rN_gross[is.finite(st$rN_gross)])
  nN <- .ta_net_from_holdings(st$NSC_H[, .(Exec, Ticker, Weight)], gN, st, bps, "close_t1")
  Dt[, rN_net := nN$r[match(match(date, st$cal), nN$di)]]
  dd <- Dt[is.finite(rN_net), ret_net - rN_net]
  nsc <- list(n = length(dd), diff_ann = mean(dd) * 252, diff_nw_t = .ta_nw_t(dd, .ta_nw_lag(length(dd), cfg$nw$lag_rule)),
              corr = if (length(dd) > 2) stats::cor(Dt[is.finite(rN_net)]$ret_net, Dt[is.finite(rN_net)]$rN_net) else NA_real_,
              control_active_ann = Dt[is.finite(rN_net), mean(rN_net - benchmark_ret)] * 252,
              spec = list(n = cfg$.fa$n_max, weight_cap = if (is.finite(cfg$.fa$weight_cap)) cfg$.fa$weight_cap else "none",
                          weighting = cfg$no_signal_control$weighting, grid = cfg$no_signal_control$grid, cost_bps = bps))
  # 에피소드
  epb <- .ta_dd_episodes(Dt$benchmark_ret, Dt$date, as.integer(cfg$episodes$benchmark_top_k))
  eps <- .ta_episode_table(Dt, epb, "benchmark_drawdown")
  if (isTRUE(cfg$episodes$include_strategy_mdd)) {
    eps_s <- .ta_dd_episodes(Dt$ret_net, Dt$date, 1L)
    eps <- rbind(eps, .ta_episode_table(Dt, eps_s, "strategy_mdd"), fill = TRUE)
  }
  # 패리티(권위 산출과의 대조 — 같은 CSV 를 같은 식으로 읽었는가)
  par <- list(
    port_t_lag3 = full$active$nw_t_house,
    port_t_auth = .ta_or(auth$essence$portfolio_alpha_t_nw_lag3, NA_real_),
    retention = retn$active$retention,
    retention_auth = .ta_or(auth$essence$oos_retention, NA_real_),
    identity_resid_max = max(abs(Dt$identity_resid)),
    recon_abs_max = max(abs(Dt$recon)), recon_abs_mean = mean(abs(Dt$recon)),
    bench_gap_max = bench_gap, days_without_holding_rows = nrow(miss_days))
  par$port_t_match <- is.finite(par$port_t_auth) && abs(round(par$port_t_lag3, 3) - par$port_t_auth) <= 0.0015
  par$retention_match <- (!is.finite(par$retention_auth) && !is.finite(par$retention)) ||   # 둘 다 미정의(IS IR ≤ 0.05 — essence 규칙)
    (is.finite(par$retention_auth) && is.finite(par$retention) && abs(round(par$retention, 3) - par$retention_auth) <= 0.0015)
  vint <- NULL
  if (!is.null(auth$measurement_regime$data_vintage$raw)) {
    dv <- auth$measurement_regime$data_vintage$raw
    vint <- list(cell_raw_size = dv$size, cell_raw_mtime = dv$mtime, state_raw_size = st$diag$fp$raw$size,
                 state_raw_mtime = st$diag$fp$raw$mtime,
                 same_vintage = identical(as.numeric(dv$size), as.numeric(st$diag$fp$raw$size)) &&
                   identical(as.character(dv$mtime), as.character(st$diag$fp$raw$mtime)))
  }
  md5 <- function(f) unname(as.character(tools::md5sum(file.path(src$dir, f))))
  res <- list(
    label = TA_LABEL, version = TA_VERSION, created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    note = paste0("진단 — 등급 대체 아님. 등급 = essence_score.R(authoritative_remeasure.json::essence_grade). ",
                  "성분 = 보유 기반 사전 노출×요인 실현(모든 노출은 t-1 까지). 전기간 요약·구간표는 사후 평가량 — 선정 규칙 입력 금지(C1 D-E). ",
                  "구간 경계는 레버 감사가 본 경계다(설정 periods_source)."),
    input = list(artifact = src$of_artifact, dir = src$dir, basis = src$basis, exec_price = src$exec_price,
                 regime_key = src$regime_key, strategy_id = .ta_or(man$strategy_id, NA_character_),
                 md5 = list(r03 = md5("03_period_returns.csv"), h04 = md5("04_holdings.csv"), b05 = md5("05_benchmark_returns.csv")),
                 essence_grade_auth = .ta_or(auth$essence_grade, NA_character_),
                 first = format(min(Dt$date)), last = format(max(Dt$date)), n_days = n, cost_bps = bps,
                 inject_alpha_ann = inject_alpha_ann),
    config = list(path = cfg$.path, md5 = cfg$.md5, fixed_axes = cfg$.fa[c("n_max", "liq_min", "commission_bps", "source")],
                  window = cfg$loadings$window_market_days, min_obs = cfg$loadings$min_obs,
                  shrink_weight_ts = cfg$loadings$shrink_weight_ts, nw_lag = lag, nw_lag_rule = cfg$nw$lag_rule, house_lag = hl),
    state = list(version = st$version, cal_first = format(st$cal[1]), cal_last = format(st$cal[st$D]), n_tickers = st$N,
                 nU_median = st$diag$nU_median, fallback_frac = st$diag$fallback_frac, first_fn = st$diag$first_fn,
                 data_fp = st$diag$fp, vintage = vint),
    parity = par,
    loadings = list(beta_m_mean = mean(Dt$beta_m), beta_e_mean = mean(Dt$beta_e), beta_n_mean = mean(Dt$beta_n),
                    b_ewcw_2f_asof_mean = mean(Dt$b_ewcw_2f), GL_mean = mean(Dt$GL),
                    note = "b_ewcw_2f = [시장, EW_U−K200] 2요인 사전 적재의 보유 가중(플랜 δ1 정의의 as-of 판) · beta_e = 3요인(분해에 쓴 값)"),
    full = full, periods = per, retention = retn, beta_controlled_alpha = bca, no_signal = nsc,
    loading_calibration = ta_loading_calibration(Dt, cfg),
    episodes = eps, pit_probe = pit)
  if (keep_daily) res$daily <- Dt[, .(date, ret_net, ret_gross, benchmark_ret, active, market_beta, ew_cw, tilt_nsc, selection,
                                      cost, recon, identity_resid, GL, beta_m, beta_e, beta_n, b_ewcw_2f, fe, fn, rN_net)]
  res
}

#' 쓰기(명시 out_dir 에만) — <prefix>.json(일간 제외) + <prefix>_daily.csv
ta_write <- function(res, out_dir, prefix = "tilt_attribution") {
  if (missing(out_dir) || !nzchar(out_dir)) stop("[tilt] out_dir 필수 — 기본 쓰기 경로 없음")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  js <- res; js$daily <- NULL
  tmp <- file.path(out_dir, paste0(".", prefix, ".json.tmp"))
  writeLines(jsonlite::toJSON(js, auto_unbox = TRUE, pretty = TRUE, digits = 10, na = "null", null = "null"), tmp, useBytes = TRUE)
  file.rename(tmp, file.path(out_dir, paste0(prefix, ".json")))
  if (!is.null(res$daily)) fwrite(res$daily, file.path(out_dir, paste0(prefix, "_daily.csv")))
  invisible(file.path(out_dir, paste0(prefix, ".json")))
}

# ── PIT 탐침 (접두 불변) ───────────────────────────────────────────────────────
.ta_with_seed <- function(seed, expr) {
  old <- if (exists(".Random.seed", envir = globalenv(), inherits = FALSE)) get(".Random.seed", envir = globalenv()) else NULL
  on.exit({ if (is.null(old)) { if (exists(".Random.seed", envir = globalenv(), inherits = FALSE)) rm(".Random.seed", envir = globalenv()) }
            else assign(".Random.seed", old, envir = globalenv()) }, add = TRUE)
  set.seed(seed); force(expr)
}

.ta_scramble <- function(mkt, from_date, fields, seed, flags) {
  m2 <- mkt; P <- copy(mkt$P); BM <- copy(mkt$BM)
  idx <- which(P$Date >= as.Date(from_date))
  .ta_with_seed(seed, {
    for (f in intersect(fields, names(P))) {
      if (!length(idx)) break
      if (f %in% flags) set(P, i = idx, j = f, value = as.numeric(sample(c(0, 1), length(idx), replace = TRUE)))
      else {
        v <- as.numeric(P[[f]][idx])
        set(P, i = idx, j = f, value = v[sample.int(length(v))] * stats::runif(length(v), 0.2, 3))
      }
    }
    if ("BM_Ret" %in% fields) {
      jb <- which(BM$Date >= as.Date(from_date))
      if (length(jb)) set(BM, i = jb, j = "BM_Ret", value = stats::rnorm(length(jb), 0, 0.03))
    }
  })
  m2$P <- P; m2$BM <- BM; m2
}

.ta_state_row <- function(st, c_idx, H_list) {
  tk <- st$tickers
  WN <- st$WN[di == c_idx]
  WU <- if (is.null(st$WU)) data.table(di = integer(0), ti = integer(0), w = numeric(0)) else st$WU[di == c_idx]
  last <- st$cal[st$D]
  hw <- lapply(H_list, function(h) { W <- .ta_daily_weights(as.data.table(h$H)[Exec <= last], st, h$exec_price)[di == c_idx]
                                     setNames(W$w, tk[W$ti]) })
  list(U = sort(tk[st$U[c_idx, ]]),
       Bm = setNames(st$Bm[c_idx, ], tk), Be = setNames(st$Be[c_idx, ], tk), Bn = setNames(st$Bn[c_idx, ], tk),
       B2e = setNames(st$B2e[c_idx, ], tk),
       nsc_w = setNames(WN$w, tk[WN$ti]), ewu_w = setNames(WU$w, tk[WU$ti]), hold_w = hw)
}

.ta_cmp_num <- function(a, b, tol) {
  k <- union(names(a), names(b)); x <- a[k]; y <- b[k]
  bothna <- is.na(x) & is.na(y)
  d <- abs(x - y); d[bothna] <- 0; d[xor(is.na(x), is.na(y))] <- Inf
  if (!length(d)) 0 else max(d)
}

#' 접두 불변 탐침. H_list = list(list(H = holdings, exec_price = "close_t1"), …)
#' @return list(status = "PASS"/"FAIL", rows = data.table(층·탐침일·항목·최대차))
ta_pit_probe <- function(mkt, cfg, st = NULL, H_list = list(), probe_days = NULL, seed = 1L) {
  if (is.null(st)) st <- ta_build_state(mkt, cfg)
  tol <- as.numeric(cfg$pit_probe$tol); flags <- unlist(cfg$universe$membership_flags)
  if (is.null(probe_days)) {
    k <- as.integer(cfg$pit_probe$n_probe_days)
    ok <- which(is.finite(st$fn) & rowSums(is.finite(st$Bm)) > 0)
    rng <- if (length(ok)) range(ok) else c(2L, st$D)
    probe_days <- unique(as.integer(round(rng[1] + (rng[2] - rng[1]) * seq_len(k) / (k + 1))))
  }
  all_fields <- c("Ret", "Size", "Close", "Vol", flags, "BM_Ret")
  rows <- list()
  add <- function(tier, c_idx, item, gap) rows[[length(rows) + 1L]] <<-
    data.table(tier = tier, day = format(st$cal[c_idx]), item = item, max_gap = gap, pass = is.finite(gap) && gap <= tol)
  for (c_idx in probe_days) {
    ref <- .ta_state_row(st, c_idx, H_list)
    upto <- st$cal[c_idx]
    # A층 — 수익일 c 이후 전 입력 교란
    mA <- .ta_scramble(mkt, st$cal[c_idx], all_fields, seed + c_idx, flags)
    sA <- ta_build_state(mA, cfg, tickers = st$tickers, upto = upto)
    rA <- .ta_state_row(sA, c_idx, H_list)
    add("A_lookahead", c_idx, "U", if (identical(ref$U, rA$U)) 0 else Inf)
    for (b in c("Bm", "Be", "Bn", "B2e")) add("A_lookahead", c_idx, paste0("loading_", b), .ta_cmp_num(ref[[b]], rA[[b]], tol))
    add("A_lookahead", c_idx, "nsc_weight", .ta_cmp_num(ref$nsc_w, rA$nsc_w, tol))
    add("A_lookahead", c_idx, "ewu_weight", .ta_cmp_num(ref$ewu_w, rA$ewu_w, tol))
    add("A_lookahead", c_idx, "factor_hist_fe", .ta_cmp_num(setNames(st$fe[seq_len(c_idx - 1L)], seq_len(c_idx - 1L)),
                                                           setNames(sA$fe[seq_len(c_idx - 1L)], seq_len(c_idx - 1L)), tol))
    add("A_lookahead", c_idx, "factor_hist_fn", .ta_cmp_num(setNames(st$fn[seq_len(c_idx - 1L)], seq_len(c_idx - 1L)),
                                                           setNames(sA$fn[seq_len(c_idx - 1L)], seq_len(c_idx - 1L)), tol))
    for (h in seq_along(H_list)) add("A_lookahead", c_idx, paste0("hold_weight_", h), .ta_cmp_num(ref$hold_w[[h]], rA$hold_w[[h]], tol))
    # B층(C10) — 결정일(c−1) 이후 거래대금 입력 교란 → U_c 불변
    if (c_idx >= 2L) {
      mB <- .ta_scramble(mkt, st$cal[c_idx - 1L], c("Close", "Vol"), seed + 7L * c_idx, flags)
      sB <- ta_build_state(mB, cfg, tickers = st$tickers, upto = upto)
      add("B_c10_liquidity", c_idx, "U", if (identical(ref$U, sort(sB$tickers[sB$U[c_idx, ]]))) 0 else Inf)
    }
    # B층(C2) — c 를 담은 무신호 대조 창의 시그널일 이후 Size 교란 → 그 창 비중 불변
    ex_i <- match(unique(st$NSC_H$Exec), st$cal); sg_i <- unique(st$NSC_H$sig_idx)
    kk <- which(ex_i < c_idx)
    if (length(kk)) {
      s_idx <- sg_i[max(kk)]
      mC <- .ta_scramble(mkt, st$cal[s_idx], c("Size"), seed + 13L * c_idx, flags)
      sC <- ta_build_state(mC, cfg, tickers = st$tickers, upto = upto)
      WN <- sC$WN[di == c_idx]
      add("B_c2_size", c_idx, "nsc_weight", .ta_cmp_num(ref$nsc_w, setNames(WN$w, sC$tickers[WN$ti]), tol))
    }
    # B층(격자 결정일) — 2026-09-25 적대 검증 추가. A층은 c 이후만 교란해 (시그널일, c) 사이의 결정 입력 누출을 못 본다
    #   (실증: EW_U·무신호 대조 적격을 집행일 상태로 바꾼 돌연변이 M9·M11 이 A·B_c10·B_c2 를 전부 통과했다).
    #   c 를 담은 월 격자 창의 시그널일 s_k 기준 — 거래대금(Close·Vol)·Size 는 s_k 부터(엔진 지연 1행이면 s_k 값은 안 쓴다),
    #   멤버십 플래그는 s_k 다음 날부터 교란 → EW_U·무신호 대조의 c 시작 비중이 비트 동일해야 한다(수익은 교란하지 않는다 — 드리프트는 정당).
    gq <- .ta_month_grid(st$cal, 1L); kq <- which(gq$exec_idx < c_idx)
    if (length(kq)) {
      s_k <- gq$sig_idx[max(kq)]
      mG <- .ta_scramble(mkt, st$cal[s_k], c("Close", "Vol", "Size"), seed + 17L * c_idx, flags)
      if (s_k < st$D) mG <- .ta_scramble(mG, st$cal[s_k + 1L], flags, seed + 19L * c_idx, flags)
      sG <- ta_build_state(mG, cfg, tickers = st$tickers, upto = upto)
      rG <- .ta_state_row(sG, c_idx, list())
      add("B_grid_decision", c_idx, "ewu_weight", .ta_cmp_num(ref$ewu_w, rG$ewu_w, tol))
      add("B_grid_decision", c_idx, "nsc_weight", .ta_cmp_num(ref$nsc_w, rG$nsc_w, tol))
    }
  }
  R <- rbindlist(rows)
  list(status = if (nrow(R) && all(R$pass)) "PASS" else "FAIL", n_checks = nrow(R), n_fail = sum(!R$pass),
       probe_days = format(st$cal[probe_days]), rows = R,
       note = paste0("A층 = 미래참조(수익일 c 이후 전 입력 교란) · B층 = 결정일 규약(C10 거래대금 · C2 Size · 격자 결정일 = 시그널일 이후 ",
                     "멤버십·거래대금·Size 교란 → EW_U·무신호 대조 비중 불변). 전부 비트 동일(tol)이어야 PASS"))
}

#' 적재 보정 진단(사후 평가량 — 선정·판정 입력 금지 · 2026-09-25 적대 검증 추가)
#'   선별 성분을 같은 날 요인 실현 [f_m, f_e, f_n] 에 OLS 회귀한 기울기. 사전 적재가 맞으면 선별에 요인 노출이 남지 않는다(기울기 ≈ 0).
#'   기울기 c_k ≠ 0 이면 c_k·f_k 만큼이 요인 성분과 선별 사이에서 잘못 나뉜 것이다 — 요인 실현이 큰 구간(2025~26: f_m 연 +87% ·
#'   f_e 연 −50%)에서는 작은 적재 오차가 선별 수치를 지배하므로 선별을 읽기 전에 이 표를 본다.
#'   intercept_ann = 요인 중립 선별(사후) · misattributed_ann = 선별 평균 − 절편 = Σ c_k·평균(f_k) (연율).
#'   근거: 특성 기반 측정의 잔여(선별)는 벤치·특성 포트폴리오 노출을 담지 않아야 한다 — Daniel, Grinblatt, Titman & Wermers (1997),
#'   JF 52(3):1035-1058, https://doi.org/10.1111/j.1540-6261.1997.tb02724.x (계약 attribution._source 와 같은 뿌리).
#'   최소 관측 = loadings.min_obs(회귀 최소 관측 규칙 재사용 — 새 파라미터 없음). SE 는 OLS(참고용 — 판정 없음).
ta_loading_calibration <- function(Dt, cfg) {
  mo <- as.integer(cfg$loadings$min_obs)
  one <- function(s, id) {
    X <- cbind(1, s$rb, s$fe, s$fn); y <- s$selection
    ok <- stats::complete.cases(X) & is.finite(y); X <- X[ok, , drop = FALSE]; y <- y[ok]
    n <- length(y); k <- ncol(X)
    if (n < max(mo, k + 2L)) return(NULL)
    fit <- stats::lm.fit(X, y); b <- unname(fit$coefficients)
    if (anyNA(b)) return(NULL)
    V <- tryCatch(solve(crossprod(X)) * sum(fit$residuals^2) / (n - k), error = function(e) NULL)
    se <- if (is.null(V)) rep(NA_real_, k) else sqrt(diag(V))
    data.table(period = id, n = n, slope_m = b[2], slope_e = b[3], slope_n = b[4],
               t_m = b[2] / se[2], t_e = b[3] / se[3], t_n = b[4] / se[4],
               selection_ann = mean(y) * 252, intercept_ann = b[1] * 252, misattributed_ann = (mean(y) - b[1]) * 252)
  }
  rbindlist(c(list(one(Dt, "full")),
              lapply(cfg$periods, function(p) one(Dt[date >= as.Date(p$from) & date <= as.Date(p$to)], p$id))))
}

#' 요인 실현의 구간 요약(서술 전용) — f_m(K200) · f_e(EW_U−K200) · f_n⊥(무신호 대조 직교 잔여) 연율 평균·IR·NW-t
ta_factor_periods <- function(st, cfg) {
  rbindlist(lapply(cfg$periods, function(p) {
    k <- st$cal >= as.Date(p$from) & st$cal <= as.Date(p$to)
    z <- rbindlist(lapply(c(f_m = "rb", f_e = "fe", f_n = "fn"), function(v) {
      x <- st[[v]][k]; x <- x[is.finite(x)]
      if (length(x) < 20L) return(NULL)
      data.table(period = p$id, n = length(x), ann_mean = mean(x) * 252, ann_sd = stats::sd(x) * sqrt(252),
                 ir = mean(x) / stats::sd(x) * sqrt(252), nw_t = .ta_nw_t(x, .ta_nw_lag(length(x), cfg$nw$lag_rule)))
    }), idcol = "factor")
    if (!nrow(z)) return(NULL)
    z[, nU_median := stats::median(st$nU[k][st$nU[k] > 0])]
  }))
}

#' (b) 시장 수준 주입 — 보유 종목·보유일(시작 비중 ≠ 0)의 원천 수익에 δ 를 더한 시장 패널을 돌려준다(상태 재구축용).
#'   EW_U 에 보유 종목이 섞이는 누출까지 포함한 '현실' 주입이다 — 회수율은 1 − 누출(설정 controls 참조).
ta_inject_market <- function(mkt, st, H, exec_price, alpha_ann) {
  WL <- .ta_daily_weights(H, st, exec_price)[w != 0]
  key <- unique(data.table(Date = st$cal[WL$di], Ticker = st$tickers[WL$ti]))
  m2 <- mkt; P <- copy(mkt$P)
  P[key, on = c("Date", "Ticker"), Ret := Ret + as.numeric(alpha_ann) / 252]
  m2$P <- P
  attr(m2, "injected") <- list(n_stock_days = nrow(key), alpha_ann = alpha_ann)
  m2
}

# ── 양성 대조 (실데이터·합성 공용) ─────────────────────────────────────────────
.ta_grid_holdings <- function(st, cfg, from_date, pick) {
  g <- .ta_month_grid(st$cal, 1L)
  g <- g[st$cal[sig_idx] >= as.Date(from_date)]
  rbindlist(lapply(seq_len(nrow(g)), function(k) {
    s <- g$sig_idx[k]; cand <- which(st$ELIG[s, ])
    sel <- pick(cand, s)
    if (!length(sel)) return(NULL)
    data.table(Exec = st$cal[g$exec_idx[k]], Ticker = st$tickers[sel], Weight = 1 / length(sel))
  }))
}

.ta_quick_stats <- function(C, cfg) {
  C <- C[is.finite(market_beta) & is.finite(selection)]
  C[, active := r_rec - rb]
  lag <- .ta_nw_lag(nrow(C), cfg$nw$lag_rule)
  list(n = nrow(C), sel_ann = mean(C$selection) * 252, sel_nw_t = .ta_nw_t(C$selection, lag),
       ewcw_var_share = stats::cov(C$ew_cw, C$active) / stats::var(C$active),
       beta_m_mean = mean(C$beta_m), beta_e_mean = mean(C$beta_e), beta_n_mean = mean(C$beta_n),
       identity_max = max(abs(C$active - (C$market_beta + C$ew_cw + C$tilt_nsc + C$selection))))
}

#' (a) EW 유니버스 복제 — 시그널일 적격 전 종목 동일가중(월 격자 · close_t1)
ta_control_ew_replica <- function(st, cfg, from_date = cfg$.fa$start_date) {
  H <- .ta_grid_holdings(st, cfg, from_date, function(cand, s) cand)
  C <- ta_decompose(.ta_daily_weights(H, st, "close_t1"), st)
  q <- .ta_quick_stats(C, cfg); cc <- cfg$controls
  q$pass <- is.finite(q$ewcw_var_share) && q$ewcw_var_share >= cc$ew_replica_ew_share_min &&
    q$beta_e_mean >= cc$ew_replica_beta_band[[1]] && q$beta_e_mean <= cc$ew_replica_beta_band[[2]] &&
    q$beta_m_mean >= cc$ew_replica_beta_band[[1]] && q$beta_m_mean <= cc$ew_replica_beta_band[[2]] &&
    is.finite(q$sel_nw_t) && abs(q$sel_nw_t) < stats::qnorm(1 - cc$fpr_alpha / 2)
  q
}

#' (c) 무작위 n 종 — 선별 NW-t 분포(위양성률)
#'   size_rank = c(lo, hi) 를 주면 시그널일 적격 종목을 SIZE_L(엔진 .SizeLag) 내림차순으로 세운 lo~hi 위 풀에서만 뽑는다(사이즈 버킷 무신호 대조).
#'   ★2026-09-25 적대 검증: U 전체 무작위(기본)는 평균 특성이 EW_U 와 같아 OLS 선형성상 선별 ≈ 0 이 보장되는 퇴화 대조다 —
#'   칸들처럼 사이즈가 기운 포트의 선별 보정은 이 버킷판으로만 보인다(실측 2026-09-25 샌드박스 R 100: 평균 t 상위 1~60 −0.85 ·
#'   61~150 −0.53 · 151~400 +0.51 — 설정 기준 |평균 t| ≤ mean_t_abs_max 를 셋 다 넘는다 = 사이즈 기운 포트의 선별 t 는 위치가 밀린 영가설 위에 있다).
ta_control_random <- function(st, cfg, from_date = cfg$.fa$start_date, R = NULL, seed = NULL, n = NULL, size_rank = NULL) {
  cc <- cfg$controls
  R <- .ta_or(R, as.integer(cc$random_n_portfolios)); seed <- .ta_or(seed, as.integer(cc$random_seed)); n <- .ta_or(n, cfg$.fa$n_max)
  if (!is.null(size_rank) && (length(size_rank) != 2L || any(!is.finite(size_rank)) || size_rank[1] < 1 || size_rank[2] < size_rank[1]))
    stop("[tilt] size_rank = c(lo, hi) (1 ≤ lo ≤ hi) 이어야 한다")
  pool_of <- function(cand, s) {
    if (is.null(size_rank)) return(cand)
    sz <- st$SIZE_L[s, cand]; o <- cand[is.finite(sz)][order(-sz[is.finite(sz)])]
    if (length(o) < size_rank[1]) return(integer(0))
    o[size_rank[1]:min(size_rank[2], length(o))]
  }
  one <- .ta_with_seed(seed, lapply(seq_len(R), function(r) {
    H <- .ta_grid_holdings(st, cfg, from_date, function(cand, s) { p <- pool_of(cand, s); if (length(p) >= n) p[sample.int(length(p), n)] else p })
    C <- ta_decompose(.ta_daily_weights(H, st, "close_t1"), st)
    q <- .ta_quick_stats(C, cfg); c(t = q$sel_nw_t, sel_ann = q$sel_ann, beta_e = q$beta_e_mean)
  }))
  M <- do.call(rbind, one); tt <- unname(M[, "t"])
  crit <- stats::qnorm(1 - cc$fpr_alpha / 2)
  fpr <- mean(abs(tt) > crit, na.rm = TRUE)
  list(R = R, n_stocks = n, seed = seed, size_rank = size_rank, t = tt, fpr = fpr, mean_t = mean(tt, na.rm = TRUE), sd_t = stats::sd(tt, na.rm = TRUE),
       sel_ann_median = stats::median(M[, "sel_ann"], na.rm = TRUE), beta_e_median = stats::median(M[, "beta_e"], na.rm = TRUE),
       pass = is.finite(fpr) && fpr <= cc$fpr_max && abs(mean(tt, na.rm = TRUE)) <= cc$mean_t_abs_max)
}

cat("[tilt_attribution.R] Loaded (", TA_VERSION, ") — ta_config · ta_load_market · ta_build_state · ta_attribute · ta_pit_probe · ta_write · 대조 ta_control_*\n", sep = "")
cat("  라벨: ", TA_LABEL, " — 성분 분해는 판정이 아니다(등급 = essence 하나)\n", sep = "")
