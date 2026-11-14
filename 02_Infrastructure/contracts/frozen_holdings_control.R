# frozen_holdings_control.R — 위기 전 보유 동결 대조 (진단 기록 · 2026-11-14 · 도훈 CHARTER-GAP14-FOLLOWUPS-20261113 (나) '기록부터')
#
# 질문: 위기 방어가 위기 전에 담고 있던 종목에서 왔나(선택), 위기 무렵 보유를 바꾼 데서 왔나(보유 회전 = 헌장 빈칸 9 A′ 의 타이밍)?
#   등급 v3.5 는 노출(현금) 경로가 고정이면 무작위 대조 포트폴리오(시가총액 · β 일치)를 넘은 방어를 '선택'으로 센다. 노출 1 을 유지한 채
#   보유를 위기 무렵 저β 로 돌린 전략도 그 대조를 넘을 수 있다(철학 C-20261113-063 · 합성 기록 검사). 같은 β 낮춤을 현금으로 하면
#   타이밍(증거 필요)인데 보유로 하면 선택이 되는 비대칭 — 결정 카드 (나) 는 이것을 A′ 의 타이밍으로 보고, 먼저 진단으로 기록한다.
#
# 대조(위기마다 · 위기 = 행동 카드의 LT 20/20 위기):
#   ① 동결 보유 = 첫 위기 거래일에 유효한 보유(= 고점 이전 마지막 리밸 보유). MC8 과 같은 시가총액 분위 매핑 · 합 1 · 노출 GL0 = 그 리밸의 Σ목표비중.
#   ② 동결 플라시보 = 같은 리밸에서 분위마다 전략 보유 수만큼 분위 멤버를 무작위로 뽑아 같은 비중을 얹은 포트폴리오 n 개
#      (matched_controls.R .mc_placebo_paths 와 같은 추출 규칙 · 시드 = MC8 시드 + 고점 날짜 번호).
#   ③ β 맞춤 = 고점 이전 완결 달 창(최대 beta_window_months · 최소 beta_min_months)에서 고정 비중 수익의 월간 OLS β(행동 카드 .bc_beta).
#      ρ_j = min(β_F / β_j, 1) — 플라시보를 현금 혼합으로 동결 보유의 '위기 전' β 까지 낮춘다(차입 없음). 고점 이전 자료만(PIT).
#      v3.5 의 짝은 전략의 전기간 β 에 맞춘다. 여기서는 동결 보유 자신의 위기 전 β 에 맞춘다 — 고점 직전에 저β 로 옮겨 둔 보유도
#      '분위 안 저β' 로 드러나게(보유 회전이 고점 앞이든 뒤든 같은 판정).
#   ④ 동결 보유와 플라시보 모두 그 리밸 창 시작부터 저점까지 매수후보유(리밸 없음 · 결측 수익 = 0 · MC8 레그 규약).
#      하락 포착 = (고점, 저점] 최대낙폭 ÷ 같은 창 벤치 낙폭(× GL0 · 플라시보는 × ρ_j).
#   ⑤ 넘음 = 동결 포착 < 플라시보 포착의 alpha 분위 − tol(MC8 과 같은 규칙) · 넘은 위기 비율 > majority_share → frozen_separated.
#      시가총액만 맞춘 참고 비율(ρ = 1)도 함께 적는다(분위 안 저β 만으로 넘는지 가른다).
#   ⑥ 기록 판(오케스트레이터 11-14 보완 ①② · 판정 아님 · v3.6 결정 재료): ρ 대상 2 × β 창 2 의 넘음 · 비율 · 라벨을 함께 적는다.
#      own_prepeak(= 주 판정) · own_prepeak_normal(같은 창의 평상 달만) · leg_full(v3.5 짝처럼 전략 레그 β · 전략 전기간 · PIT 아님)
#      · leg_normal(전략 레그 β · 평상 달). 평상 달 = 긴 벤치 이력의 LT 위기(고점 달 ~ 저점 달)에 걸리지 않은 달.
# 가상 판정(등급 아님): v3.5 노치 근거가 selection 인 기록에서
#   frozen_separated → selection_survives_freeze · frozen_not_separated → rotation_timing(v3.6 를 정하면 A′ 타이밍 증거가 있어야 가점)
#   · 판정 가능한 위기 2개 미만 → freeze_unresolved · 근거가 selection 이 아니면 not_selection_v35 · 근거를 모르면 v35_basis_unknown.
# 경계: 기록만 — 등급 · 노치 · MC8 · 행동 카드 · 권위 기록 필드를 바꾸지 않는다(핀 6파일 밖 · matched_controls.R · behavior_card.R 은 읽기만).
#   기록은 전기간이다(보는 창 · 시험 창을 나눠 적는다 — 감독관에게는 보는 창 몫만 건넨다 · 규약 §13-2).
# 수치 = 06_Registry/frozen_holdings_control.json(β 창 · 근거) + matched_controls.json(n · alpha · seed · 분위 수) + behavior_card.json(majority_share).
# 검사: 08_Tests/contracts/test_frozen_holdings_control.R · 도구: 02_Infrastructure/programs/frozen_holdings_diag.R
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })

.fhc_or <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
.FHC_SCHEMA <- "frozen_holdings_control_v1"
.FHC_LABELS <- c("frozen_separated", "frozen_not_separated", "insufficient")
.FHC_HYP <- c("selection_survives_freeze", "rotation_timing", "freeze_unresolved", "not_selection_v35", "v35_basis_unknown")

# 루트 = 호출자 명시 → CLAUDE_PROJECT_DIR → QM_ROOT → getwd (matched_controls.R 와 같은 표식)
.fhc_root <- function(root = NULL) {
  for (p in c(root, Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""), getwd())) {
    if (is.null(p) || !nzchar(p)) next
    p <- gsub("\\\\", "/", p)
    if (file.exists(file.path(p, "CLAUDE.md")) && dir.exists(file.path(p, "06_Registry"))) return(p)
  }
  stop("[frozen_holdings] 프로젝트 루트 해석 실패")
}

# MC8 · 행동 카드 계약을 사적 환경에 싣는다(전역 무접촉 · 같은 루트면 재사용)
.FHC <- new.env(parent = emptyenv())
.fhc_deps <- function(root) {
  if (isTRUE(.FHC$loaded) && identical(.FHC$root, root)) return(invisible(.FHC$d))
  m <- new.env(parent = globalenv())
  p <- file.path(root, "02_Infrastructure/contracts/matched_controls.R")
  if (!file.exists(p)) stop("[frozen_holdings] 의존 계약 없음: ", p)
  invisible(utils::capture.output(suppressMessages(sys.source(p, envir = m, keep.source = FALSE))))
  d <- list(mc = m, bc = m$.mc_deps(root))
  .FHC$d <- d; .FHC$root <- root; .FHC$loaded <- TRUE
  invisible(d)
}

#' 설정 정본 — 필수 키 · 범위가 어긋나면 멈춘다(기본값을 지어내지 않는다)
fhc_cfg <- function(root = NULL, path = NULL) {
  p <- .fhc_or(path, file.path(.fhc_root(root), "06_Registry/frozen_holdings_control.json"))
  if (!file.exists(p)) stop("[frozen_holdings] 설정 없음: ", p)
  x <- fromJSON(p, simplifyVector = TRUE)
  need <- c("contract", "beta_window_months", "beta_min_months", "beta_window_source", "ledger")
  miss <- setdiff(need, names(x))
  if (length(miss)) stop("[frozen_holdings] 설정 키 없음: ", paste(miss, collapse = ", "))
  if (!identical(x$contract, .FHC_SCHEMA)) stop("[frozen_holdings] 계약 판 불일치: ", x$contract, " ≠ ", .FHC_SCHEMA)
  w <- x$beta_window_months; m <- x$beta_min_months
  if (!is.numeric(w) || !is.numeric(m) || length(w) != 1L || length(m) != 1L || !is.finite(w) || !is.finite(m) || m < 6 || w < m)
    stop("[frozen_holdings] β 창 범위 오류(최소 ≥ 6 · 최대 ≥ 최소): ", w, " / ", m)
  if (!nzchar(x$beta_window_source)) stop("[frozen_holdings] β 창 근거 없음")
  x
}

# 일간 수익 행렬(행 = 날짜 · 열 = 종목) — 결측 = 0(MC8 레그 규약) · fin = 수익이 있었던 칸(가중 적용률 진단용)
.fhc_ret_matrix <- function(R, tickers, dates) {
  di <- as.integer(dates)
  sub <- R[as.integer(Date) >= min(di) & as.integer(Date) <= max(di)]
  sub <- sub[as.integer(Date) %in% di & Ticker %in% tickers]
  Rm <- matrix(0, length(dates), length(tickers)); Fn <- matrix(FALSE, length(dates), length(tickers))
  if (nrow(sub)) {
    ij <- cbind(match(as.integer(sub$Date), di), match(sub$Ticker, tickers))
    ok <- is.finite(sub$Ret)
    Rm[ij[ok, , drop = FALSE]] <- sub$Ret[ok]; Fn[ij[ok, , drop = FALSE]] <- TRUE
  }
  list(R = Rm, F = Fn)
}

# 분위별 무작위 추출 — .mc_placebo_paths 와 같은 규칙(분위 멤버 ≥ 보유면 비복원 · 아니면 복원 + 비중 누적)
.fhc_draw <- function(hk, uk, tickers, n) {
  Wm <- matrix(0, length(tickers), n)
  for (bb in sort(unique(hk$b))) {
    ws <- hk[b == bb]$w; m <- length(ws)
    mi <- match(uk[b == bb]$Ticker, tickers); nb <- length(mi)
    if (!nb) next
    if (m <= nb) {
      idx <- matrix(vapply(seq_len(n), function(j) mi[sample.int(nb, m)], integer(m)), nrow = m)
      Wm[cbind(as.vector(idx), rep(seq_len(n), each = m))] <- rep(ws, n)
    } else for (j in seq_len(n)) {
      pk <- mi[sample.int(nb, m, replace = TRUE)]
      for (q in seq_len(m)) Wm[pk[q], j] <- Wm[pk[q], j] + ws[q]
    }
  }
  Wm
}

#' 위기 전 보유 동결 대조 — 메모리 입력(측정 산출물을 읽는 쪽은 fhc_dir)
#' @param H 보유(date = 집행일, ticker, target_weight) · @param pr 전략 수익(date, ret_net) · @param br 벤치(date, benchmark_ret)
#' @param R RAWDATA 판(Date, Ticker, Ret, Size, 멤버 열) · @param cfg mc_cfg() · @param exec_price 집행 규약 · @param universe 대조 유니버스
#' @param bcfg bc_cfg() · @param crises 행동 카드 crises(peak_date, trough_date, window, dd_capture) · @param bm_hist 긴 벤치 이력(β 창)
#' @param fcfg fhc_cfg() · @param v35_basis 저장 기록의 v3.5 노치 근거(grade_v3.notch_basis) — 가상 판정에만 쓴다
fhc_frozen <- function(H, pr, br, R, cfg, exec_price, universe, bcfg, crises, bm_hist, fcfg,
                       v35_basis = NA_character_, root = NULL, tol = NULL) {
  root <- .fhc_root(root); d <- .fhc_deps(root); M <- d$mc; e <- d$bc
  tol <- .fhc_or(tol, M$.MC_TOL)
  maj <- bcfg$majority_share
  if (!is.numeric(maj) || !is.finite(maj)) stop("[frozen_holdings] majority_share 설정 없음(behavior_card.json)")
  n <- as.integer(cfg$placebo_n); alpha <- as.numeric(cfg$placebo_alpha); seed0 <- as.integer(cfg$placebo_seed)
  out0 <- list(schema = .FHC_SCHEMA, majority_share = maj, placebo_n = n, placebo_alpha = alpha, tol = tol,
               beta_window_months = fcfg$beta_window_months, beta_min_months = fcfg$beta_min_months, v35_basis = v35_basis)
  ## 모든 반환을 한 곳에서 마무리한다 — 일찍 끝나도(보유 없음 · 위기 없음 · 창 없음) 같은 모양(상태 · 위기별 표 · 창별 요약 · 라벨 · 가상 판정)
  ## 판별 비율(기록 판) — 그 판의 넘음이 잴 수 있었던 위기만 센다 · 라벨 규칙은 주 판정과 같다
  vsum <- function(x, col) {
    v <- if (nrow(x) && col %in% names(x)) x[[col]] else logical(0)
    v <- v[!is.na(v)]; k <- length(v); s <- if (k) mean(v) else NA_real_
    list(n_crisis = k, share = s, label = if (k < 2L || !is.finite(s)) "insufficient" else if (s > maj) "frozen_separated" else "frozen_not_separated")
  }
  legb <- list(full = NA_real_, normal = NA_real_, status = "not_run"); crisis_ym <- character(0)
  fin <- function(status, P = data.table(), varies = NA) {
    okP <- if (nrow(P) && "status" %in% names(P)) P[status == "ok"] else data.table()
    summ <- function(w) {
      x <- if (nrow(okP) && w != "overall") okP[window == w] else okP
      nn <- nrow(x)
      shr <- if (nn) mean(x$beats) else NA_real_
      list(n_crisis = nn, share_frozen_beats_size_beta = shr, share_frozen_beats_size = if (nn) mean(x$beats_size) else NA_real_,
           median_rotation_gap = if (nn) stats::median(x$rotation_gap, na.rm = TRUE) else NA_real_,
           median_beta_frozen = if (nn) stats::median(x$beta_frozen) else NA_real_,
           label = if (nn < 2L || !is.finite(shr)) "insufficient" else if (shr > maj) "frozen_separated" else "frozen_not_separated",
           variants = lapply(c(own_prepeak = "beats", own_prepeak_normal = "beats_own_normal", leg_full = "beats_leg_full",
                               leg_normal = "beats_leg_normal"), function(col) vsum(x, col)))
    }
    S <- list(overall = summ("overall"), visible = summ("visible"), test = summ("test"))
    lab <- S$overall$label
    hyp <- if (is.na(v35_basis) || !nzchar(v35_basis)) "v35_basis_unknown"
           else if (!identical(v35_basis, "selection")) "not_selection_v35"
           else if (identical(lab, "frozen_separated")) "selection_survives_freeze"
           else if (identical(lab, "frozen_not_separated")) "rotation_timing" else "freeze_unresolved"
    c(out0, list(status = status, per_crisis = P, summary = S, label = lab, hypothetical_v36 = hyp, exposure_varies = varies,
                 leg_beta = legb[c("full", "normal", "status")], crisis_months_n = length(crisis_ym),
                 status_counts = if (nrow(P) && "status" %in% names(P)) as.list(table(P$status)) else list()))
  }
  H <- as.data.table(H)[, date := as.Date(date)][is.finite(target_weight) & target_weight != 0]
  if (!nrow(H)) return(fin("no_holdings"))
  if (any(H$target_weight < 0)) return(fin("not_applicable_long_short"))
  pr <- as.data.table(pr)[, date := as.Date(date)]
  bmd <- as.data.table(br)[, .(date = as.Date(date), benchmark_ret)][is.finite(benchmark_ret)]
  bmh <- as.data.table(bm_hist)[, .(date = as.Date(date), benchmark_ret)][is.finite(benchmark_ret)][order(date)]
  ## (기록 판 · 오케스트레이터 11-14 보완 ②) 평상 달 = 긴 벤치 이력의 LT 위기(고점 달 ~ 저점 달)에 걸리지 않은 달
  hcr <- tryCatch(e$.bc_crises_by_cfg(e$.bc_series(bmh, "benchmark_ret"), bcfg), error = function(err) NULL)
  crisis_ym <- if (is.null(hcr) || !nrow(hcr)) character(0) else unique(unlist(lapply(seq_len(nrow(hcr)), function(k)
    format(seq(as.Date(format(hcr$peak_date[k], "%Y-%m-01")), as.Date(format(hcr$trough_date[k], "%Y-%m-01")), by = "month"), "%Y-%m"))))
  CR <- as.data.table(crises)
  if (!nrow(CR)) return(fin("no_crises"))
  win <- M$.mc_windows(pr$date, H$date, exec_price)
  if (!nrow(win)) return(fin("no_windows"))
  ex <- M$mc_exposure(H, win)
  ## (기록 판 · 보완 ①) 전략 레그 β — v3.5 짝의 β 분자와 같은 정의(분위 매핑 보유를 바스켓 엔진으로 재현 · 월간 OLS) · 전기간 · 평상 달
  legb <- tryCatch({
    sbA <- M$mc_size_basket(H, R, cfg, universe)
    lg <- M$.mc_basket_returns(sbA$hold, win, R)
    Kl <- bmh$benchmark_ret[match(lg$date, bmh$date)]
    okl <- is.finite(Kl) & is.finite(lg$ret)
    mol <- M$.mc_monthly_cols(lg$date[okl], cbind(k = Kl[okl], l = lg$ret[okl]))
    nml <- !(mol$ym %in% crisis_ym)
    list(full = e$.bc_beta(mol$M[, "l"], mol$M[, "k"]), normal = if (sum(nml) >= 6L) e$.bc_beta(mol$M[nml, "l"], mol$M[nml, "k"]) else NA_real_,
         status = "ok", dates = sort(unique(lg$date[okl])))
  }, error = function(err) list(full = NA_real_, normal = NA_real_, status = paste("error:", conditionMessage(err)), dates = as.Date(character(0))))
  rows <- vector("list", nrow(CR))
  for (i in seq_len(nrow(CR))) {
    p0 <- as.Date(CR$peak_date[i]); t0 <- as.Date(CR$trough_date[i])
    base <- data.table(peak_date = p0, trough_date = t0, window = as.character(CR$window[i]), cap_strategy = as.numeric(CR$dd_capture[i]))
    st <- function(s, ...) cbind(base, data.table(status = s, ...))
    dd <- win[date > p0 & date <= t0]
    if (!nrow(dd)) { rows[[i]] <- st("not_held"); next }
    e0 <- dd$exec_date[which.min(dd$date)]                                   # 첫 위기 거래일에 유효한 보유의 집행일(≤ 고점)
    if (e0 > p0) { rows[[i]] <- st("held_after_peak"); next }               # 창 규약상 생기지 않는다 — 생기면 판정에서 뺀다
    sb <- M$mc_size_basket(H[date == e0], R, cfg, universe)
    hk <- sb$hold; uk <- sb$univ
    if (!nrow(hk)) { rows[[i]] <- st("unmapped", exec_frozen = e0); next }
    gl0 <- ex$path[exec_date == e0]$GL[1]
    tk <- unique(c(hk$Ticker, uk$Ticker))
    ## β 창 — 고점 달 이전 완결 달(최대 W · 최소 m) · 긴 벤치 이력의 거래일
    pm <- as.Date(format(p0, "%Y-%m-01"))
    a0 <- seq(pm, by = "-1 month", length.out = fcfg$beta_window_months + 1L)[fcfg$beta_window_months + 1L]
    dpre <- bmh[date >= a0 & date < pm]$date
    nmon <- length(unique(format(dpre, "%Y-%m")))
    if (nmon < fcfg$beta_min_months) { rows[[i]] <- st("beta_window_short", exec_frozen = e0, n_hold = nrow(hk), gl0 = gl0, beta_months = nmon); next }
    ## 매수후보유 창 — 그 리밸 창 시작 → 저점(전략 수익일)
    dbh <- sort(unique(win[date >= min(win[exec_date == e0]$date) & date <= t0]$date))   # 그 뒤 리밸이 있어도 동결 보유를 그대로 든다
    W <- matrix(as.numeric(hk$w[match(tk, hk$Ticker)]), ncol = 1L)
    W[!is.finite(W)] <- 0
    Wp <- M$.mc_with_seed(seed0 + as.integer(p0), .fhc_draw(hk, uk, tk, n))
    WW <- cbind(W, Wp)                                                       # 열 1 = 동결 보유 · 2.. = 동결 플라시보
    ## β(고정 비중 수익 · 월간 OLS)
    Xp <- .fhc_ret_matrix(R, tk, dpre)
    rp <- Xp$R %*% WW
    cov_pre <- mean(as.numeric(Xp$F %*% W[, 1]))                             # 동결 보유 가중 수익 적용률(진단)
    moL <- M$.mc_monthly_cols(dpre, cbind(k = bmh$benchmark_ret[match(dpre, bmh$date)], rp)); mo <- moL$M
    bk <- mo[, 1]
    betas <- vapply(seq_len(ncol(WW)), function(j) e$.bc_beta(mo[, j + 1L], bk), numeric(1))
    bF <- betas[1]; bj <- betas[-1]
    if (!is.finite(bF) || bF <= 0) { rows[[i]] <- st("beta_unmeasured", exec_frozen = e0, n_hold = nrow(hk), gl0 = gl0, beta_months = nmon, beta_frozen = bF); next }
    rho <- ifelse(is.finite(bj) & bj > 0, pmin(bF / bj, 1), NA_real_)
    nv <- sum(is.finite(rho))
    if (nv * alpha < 1) { rows[[i]] <- st("placebo_beta_unmeasured", exec_frozen = e0, n_hold = nrow(hk), gl0 = gl0, beta_months = nmon, beta_frozen = bF); next }
    ## 위기 하락 포착(매수후보유 · (고점, 저점])
    Xb <- .fhc_ret_matrix(R, tk, dbh)
    cum <- apply(1 + Xb$R, 2, cumprod); if (!is.matrix(cum)) cum <- matrix(cum, nrow = length(dbh))
    V <- cum %*% WW
    Vp <- rbind(colSums(WW), V[-nrow(V), , drop = FALSE])
    RB <- V / Vp - 1
    K <- bmd$benchmark_ret[match(dbh, bmd$date)]
    ix <- which(dbh > p0 & dbh <= t0 & is.finite(K))
    if (!length(ix)) { rows[[i]] <- st("no_crisis_days", exec_frozen = e0); next }
    nav <- c(1, cumprod(1 + K[ix])); bdd <- max(1 - nav / cummax(nav))
    if (!(bdd > 0)) { rows[[i]] <- st("bench_no_drawdown", exec_frozen = e0); next }
    capF <- M$.mc_dd_cols(gl0 * RB[ix, 1, drop = FALSE]) / bdd
    ## 플라시보 포착의 alpha 분위 — ρ 를 곱한 경로만(비유한 ρ 경로는 뺀다 · 남은 경로 × alpha < 1 이면 NA)
    qv <- function(rh) {
      vj <- which(is.finite(rh))
      if (length(vj) * alpha < 1) return(NA_real_)
      cb <- M$.mc_dd_cols(sweep(gl0 * RB[ix, 1L + vj, drop = FALSE], 2L, rh[vj], `*`)) / bdd
      cb <- cb[is.finite(cb)]
      if (!length(cb)) NA_real_ else as.numeric(stats::quantile(cb, alpha, names = FALSE, type = 7))
    }
    qB <- qv(rho)                                                            # 주 판정 — 시가총액 · β 일치(동결 보유 자신의 위기 전 β)
    qS <- qv(rep(1, length(bj)))                                             # 시가총액만(참고)
    ## 기록 판(보완 ①②) — ρ 대상 2(자기 위기 전 β · 전략 레그 β) × β 창 2(전기간 · 평상 달). 판정은 v3.6 때 정한다.
    bt <- function(Mm, cols) vapply(cols, function(j) e$.bc_beta(Mm[, j], Mm[, 1]), numeric(1))
    npre <- !(moL$ym %in% crisis_ym)
    bFn <- NA_real_; rho_on <- rep(NA_real_, length(bj))
    if (sum(npre) >= fcfg$beta_min_months) {
      bn <- bt(mo[npre, , drop = FALSE], 2:ncol(mo)); bFn <- bn[1]
      if (is.finite(bFn) && bFn > 0) rho_on <- ifelse(is.finite(bn[-1]) & bn[-1] > 0, pmin(bFn / bn[-1], 1), NA_real_)
    }
    rho_lf <- rho_ln <- rep(NA_real_, length(bj))
    if (identical(legb$status, "ok") && length(legb$dates) >= 2L) {
      Xf <- .fhc_ret_matrix(R, tk, legb$dates)
      mof <- M$.mc_monthly_cols(legb$dates, cbind(k = bmh$benchmark_ret[match(legb$dates, bmh$date)], Xf$R %*% Wp))
      okm <- is.finite(mof$M[, 1])
      Mf <- mof$M[okm, , drop = FALSE]; nmf <- !(mof$ym[okm] %in% crisis_ym)
      bjf <- bt(Mf, 2:ncol(Mf))
      if (is.finite(legb$full) && legb$full > 0) rho_lf <- ifelse(is.finite(bjf) & bjf > 0, pmin(legb$full / bjf, 1), NA_real_)
      if (is.finite(legb$normal) && legb$normal > 0 && sum(nmf) >= 6L) {
        bjn <- bt(Mf[nmf, , drop = FALSE], 2:ncol(Mf))
        rho_ln <- ifelse(is.finite(bjn) & bjn > 0, pmin(legb$normal / bjn, 1), NA_real_)
      }
    }
    q_on <- qv(rho_on); q_lf <- qv(rho_lf); q_ln <- qv(rho_ln)
    bx <- function(q) if (is.finite(q)) as.numeric(capF) < q - tol else NA
    rows[[i]] <- st("ok", exec_frozen = e0, n_hold = nrow(hk), gl0 = gl0, beta_months = nmon, beta_frozen = bF,
                    beta_placebo_median = stats::median(bj, na.rm = TRUE), rho_median = stats::median(rho, na.rm = TRUE),
                    n_placebo_valid = nv, coverage_pre = cov_pre, cap_frozen = as.numeric(capF),
                    q_size_beta = qB, q_size = qS, beats = as.numeric(capF) < qB - tol, beats_size = as.numeric(capF) < qS - tol,
                    rotation_gap = as.numeric(capF) - as.numeric(CR$dd_capture[i]),
                    beta_frozen_normal = bFn, beta_months_normal = sum(npre), beta_leg_full = legb$full, beta_leg_normal = legb$normal,
                    rho_median_own_normal = stats::median(rho_on, na.rm = TRUE), rho_median_leg_full = stats::median(rho_lf, na.rm = TRUE),
                    rho_median_leg_normal = stats::median(rho_ln, na.rm = TRUE),
                    q_own_normal = q_on, q_leg_full = q_lf, q_leg_normal = q_ln,
                    beats_own_normal = bx(q_on), beats_leg_full = bx(q_lf), beats_leg_normal = bx(q_ln))
  }
  fin("ok", rbindlist(rows, fill = TRUE), isTRUE(ex$varies))
}

#' 측정 산출물 디렉터리 → 위기 전 보유 동결 대조(읽기만 · 쓰기 없음)
#'   입력 규약은 matched_controls.R::mc_card 와 같다(보유 · 수익 · 벤치 · 명세 · 벤치 이력은 측정 마지막 날까지).
#'   v3.5 노치 근거 = 저장 권위 기록 grade_v3.notch_basis(없으면 NA → v35_basis_unknown).
fhc_dir <- function(dir, root = NULL, raw = NULL, bm_hist = NULL, fcfg = NULL, cfg = NULL, bcfg = NULL) {
  root <- .fhc_root(root); d <- .fhc_deps(root); M <- d$mc; e <- d$bc
  fcfg <- .fhc_or(fcfg, fhc_cfg(root)); cfg <- .fhc_or(cfg, M$mc_cfg(root)); bcfg <- .fhc_or(bcfg, e$bc_cfg(root))
  f <- function(nm) { p <- file.path(dir, nm); if (!file.exists(p)) stop("[frozen_holdings] 산출물 없음: ", p); p }
  pr <- fread(f("03_period_returns.csv")); br <- fread(f("05_benchmark_returns.csv")); H <- fread(f("04_holdings.csv"))
  pr[, date := as.Date(date)]; br[, date := as.Date(date)]; H[, date := as.Date(date)]
  rj <- function(nm) { p <- file.path(dir, nm); if (file.exists(p)) tryCatch(fromJSON(p, simplifyVector = TRUE), error = function(err) list()) else list() }
  spec <- rj("01_strategy_spec.json"); man <- rj("00_manifest.json")
  uni <- .fhc_or(spec[["universe"]], man[["universe_id"]])
  if (is.null(uni) || !length(uni) || is.na(uni[1]) || !nzchar(uni[1])) stop("[frozen_holdings] 유니버스 미상 — 대조 유니버스를 정할 수 없다")
  uni <- as.character(uni[1])
  ep <- M$.mc_exec_price(spec, pr$date, H$date)
  last_d <- max(pr$date)
  if (is.null(bm_hist)) bm_hist <- M$.mc_bench_history(root)
  if (is.null(bm_hist)) stop("[frozen_holdings] 긴 벤치 이력 없음(.cache/benchmark.parquet) — β 창을 잴 수 없다")
  bmh <- as.data.table(bm_hist)[date <= last_d]
  card <- e$bc_card(pr[, .(date, ret_net)], br[, .(date, benchmark_ret)], cfg = bcfg, bm_hist = bmh,
                    strategy_id = tryCatch(as.character(pr$strategy_id[1]), error = function(err) NA_character_), root = root)
  if (is.null(raw)) raw <- M$mc_load_raw(root, from = min(H$date) - 31L - 31L * fcfg$beta_window_months, to = last_d, hygiene = identical(uni, "ALL_HYG"))
  ar <- rj("authoritative_remeasure.json")
  v35 <- as.character(.fhc_or(ar[["grade_v3"]][["notch_basis"]], NA_character_))[1]
  res <- fhc_frozen(H, pr[, .(date, ret_net)], br[, .(date, benchmark_ret)], raw, cfg, ep$value, uni, bcfg, card$crises, bmh, fcfg,
                    v35_basis = v35, root = root)
  res$source <- list(dir = dir, universe = uni, exec_price = ep$value, strategy_name = .fhc_or(ar[["strategy_name"]], NA_character_),
                     cr_overall = .fhc_or(ar[["grade_v3"]][["cr"]][["overall"]], NA_character_),
                     cr_notch_basis = .fhc_or(ar[["grade_v3"]][["cr_notch_basis"]], NA_character_),
                     essence_grade = .fhc_or(ar[["essence_grade"]], NA_character_), rules_version = .fhc_or(ar[["grade_v3"]][["rules_version"]], NA_character_))
  res
}

#' 원장 한 줄(JSON) — 키 = 기록 · 권위 기록 md5 · 계약 판 · 데이터 시점(RAWDATA · 벤치 크기@수정 시각)
fhc_ledger_line <- function(res, dir, root = NULL, at = Sys.time()) {
  root <- .fhc_root(root)
  rel <- sub(paste0("^", root, "/"), "", gsub("\\\\", "/", dir))
  arp <- file.path(dir, "authoritative_remeasure.json")
  amd5 <- if (file.exists(arp)) unname(as.character(tools::md5sum(arp))) else NA_character_
  vint <- function(f) { fi <- file.info(file.path(root, ".cache", f)); if (is.na(fi$size)) NA_character_ else sprintf("%.0f@%s", fi$size, format(fi$mtime, "%Y-%m-%dT%H:%M:%S")) }
  vin <- list(rawdata = vint("RAWDATA.parquet"), benchmark = vint("benchmark.parquet"))
  key <- paste(rel, amd5, .FHC_SCHEMA, vin$rawdata, vin$benchmark, sep = "|")
  pc <- res$per_crisis
  if (is.data.frame(pc) && nrow(pc)) pc <- as.data.table(pc)[, lapply(.SD, function(v) if (inherits(v, "Date")) format(v) else v)]
  list(key = key, dir = rel, computed_at = format(at, "%Y-%m-%dT%H:%M:%S%z"), contract = .FHC_SCHEMA, status = res$status,
       authoritative_md5 = amd5, data_vintage = vin, source = res$source, v35_basis = res$v35_basis, label = res$label,
       hypothetical_v36 = res$hypothetical_v36, summary = res$summary, exposure_varies = res$exposure_varies,
       leg_beta = res$leg_beta, crisis_months_n = res$crisis_months_n,
       cfg = list(beta_window_months = res$beta_window_months, beta_min_months = res$beta_min_months, placebo_n = res$placebo_n,
                  placebo_alpha = res$placebo_alpha, majority_share = res$majority_share),
       status_counts = res$status_counts, per_crisis = pc)
}

#' 원장 추가(같은 키는 다시 쓰지 않는다 · 줄 단위 추가 · 읽기 실패 줄은 키 없음으로 둔다)
fhc_ledger_append <- function(lines, path) {
  have <- character(0)
  if (file.exists(path)) {
    for (ln in readLines(path, warn = FALSE, encoding = "UTF-8")) {
      k <- tryCatch(fromJSON(ln, simplifyVector = FALSE)$key, error = function(err) NULL)
      if (!is.null(k)) have <- c(have, k)
    }
  }
  new <- Filter(function(z) !z$key %in% have, lines)
  if (length(new)) {
    txt <- vapply(new, function(z) as.character(toJSON(z, auto_unbox = TRUE, null = "null", na = "null", digits = 6)), "")
    con <- file(path, open = "a", encoding = "UTF-8"); on.exit(close(con))
    writeLines(txt, con, useBytes = TRUE)
  }
  list(written = length(new), skipped = length(lines) - length(new))
}
