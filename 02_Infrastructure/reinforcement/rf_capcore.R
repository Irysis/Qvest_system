#==============================================================================
# rf_capcore.R — PR-L1 벤치 인지 코어-위성 (cap_core) · 비중 단계 뒤 구성 단계 (2026-10-03 CAPCORE-IMPL)
#
# 무엇: 셀 스펙 `cap_core = {k, satellite, ...}` 가 있고 k > 0 이면, 엔진(rf_cell_engine.R)이 비중 단계(§5) 직후
#   ① 코어 C = 그 시그널일 **K200 멤버** 중 t-1 시총(.SizeLag) 상위 k 종(유동성 t-1 하한 통과) — 비중 = t-1 벤치 비중 근사
#      c_i = Size_{t-1,i} / Σ_{K200 멤버 · .SizeLag 유한 양수} Size_{t-1}  (유동비율·지수 편입 상한 미반영 — 사전등록 Q-L1-4 · 치료 정의의 일부)
#   ② 위성 S = 바닥 보유(그 칸의 비중 단계 산출 그대로 · EW 칸이면 1/|SEL|) 또는 C1 대조용 베타매칭 무작위 위성
#   ③ 합집합 ≤ n_max 절단(union_truncation · 결정 PREREG-DRAFT2-Q-INTERPRETATIONS ③): 코어에 없는 위성을 바닥 시그널일 점수(Score)
#      **낮은 순**(동률 = Ticker 사전순)으로 빼서 |C ∪ S'| = n_max · 코어와 겹치는 위성은 한 자리(코어)로 세고 그 위성 몫은 코어 비중에 더한다 ·
#      남은 위성 몫은 합이 (1 − Σc) 가 되게 바닥 비중에 비례 재조정 — w_i = c_i·1[i∈C] + (1 − Σc)·f_i / Σ_{j∈S'} f_j ·1[i∈S'].
#   를 만들어 PORTFOLIO 로 낸다. 불변식(stopifnot): Σw = 1 · w ≥ 0 · |보유| ≤ n_max · 비중 상한 없음(v10 폐지).
#   ★k = 0 이면 엔진이 이 파일의 어떤 함수도 부르지 않는다 — 기존 칸과 비트 동일(무처치 양성 대조 · 검사 test_rf_capcore.R K0).
#
# 왜 엔진 국소 단계인가(비중 카탈로그·rf_sleeve.R 가 아니라):
#   · 비중 카탈로그 arm(weight_catalog.R · 엔진 catalog 분기)은 **선정된 이름(SEL) 위의 비중**만 낸다(ctx$assets = SEL) — 코어는 선정 밖
#     이름(메가캡)을 들이므로 멤버십을 바꾼다. 카탈로그 계약(EW 폴백 가드 · 커버리지 분모 = 선정일)과도 맞지 않는다.
#   · rf_sleeve.R(B7)은 **선정 단계**(|SEL| = n_max 보존 · 25종 안에서의 교체)다. cap_core 는 비중 단계 **뒤**(위성 비중을 받아 코어와 합성)라
#     자리가 다르다 — 한 파일에 섞으면 B7 서명·검사와 결합된다. 그래서 순수 함수 파일 하나 + 엔진 국소 삽입 1곳.
#   · 러너 본체(reinforce_auto_parallel.R)는 건드리지 않는다. 격자(reinforce_program.json)에도 넣지 않는다 — 플랜 PR-L1 "성공 확인 전
#     cap_core 를 전 계보 상주 칸으로 배포 금지". 사전등록 arm 의 셀 스펙에만 실린다.
#
# PIT: 코어 순위·비중 = .SizeLag(엔진 DT[, shift(Size,1), by=Ticker] — 시그널일 전 거래 행 · C2) · 멤버십 = 시그널일 행 K200 플래그(C6 · PIT 시변) ·
#   유동성 = .adv20_l1(t-1 · C10) · 절단 순위 = 바닥 시그널일 점수(엔진 PANEL Score — t-1 정보) · 베타 = 팩터 DB D02_Beta 시그널일 값(C15 경유) ·
#   성과 통계 소비 0(selection_basis none). 같은 날 가격·시총 사용 금지 — 검사 P1(시그널일 Size 섭동 → 불변) · P2(t-1 Size 섭동 → 변함).
#
# 공개: rf_cc_parse / rf_cc_core / rf_cc_random_satellite / rf_cc_compose / rf_cc_report
# 계약: 순수 함수 · 파일 읽기/쓰기 없음 · 결함 = stop()(조용한 폴백 금지 — 폴백은 '처치를 안 받은 칸'을 '받은 칸'으로 기록한다).
#==============================================================================
suppressMessages({ library(data.table) })
if (!exists("%||%")) `%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

.RF_CC_SATELLITES <- c("floor", "random_beta_matched")

#' cap_core 규칙 파싱 — 미지원 인자·값은 멈춘다.
#'   k(정수 ≥ 0 · 필수) · satellite(floor | random_beta_matched · 기본 floor) · random 이면 beta_factor·seed 필수(기본값을 코드에 두지 않는다 —
#'   C1 의 seed 는 사전등록 스펙에 기록된 값이어야 한다) · beta_kind(기본 db = 팩터 DB C15 경유) · label.
#' @return NULL(키 없음) 또는 list(k, satellite, beta_factor, beta_kind, seed, label)
rf_cc_parse <- function(x) {
  if (is.null(x) || !length(x)) return(NULL)
  if (!is.list(x)) stop("[rf_capcore] cap_core 는 list 여야 한다")
  ok_args <- c("k", "satellite", "beta_factor", "beta_kind", "seed", "label")
  extra <- setdiff(names(x), ok_args)
  if (length(extra)) stop(sprintf("[rf_capcore] 알 수 없는 인자: %s", paste(extra, collapse = ", ")))
  if (is.null(x$k)) stop("[rf_capcore] k 필수(0 = 무처치)")
  k <- suppressWarnings(as.integer(x$k))
  if (length(k) != 1L || is.na(k) || k < 0L || !isTRUE(all.equal(as.numeric(x$k), as.numeric(k))))
    stop(sprintf("[rf_capcore] k 는 0 이상 정수 하나여야 한다: %s", paste(format(x$k), collapse = ",")))
  sat <- as.character(x$satellite %||% "floor")
  if (length(sat) != 1L || !(sat %in% .RF_CC_SATELLITES))
    stop(sprintf("[rf_capcore] 미지원 satellite '%s' (지원: %s)", paste(sat, collapse = ","), paste(.RF_CC_SATELLITES, collapse = ", ")))
  bf <- as.character(x$beta_factor %||% ""); bk <- as.character(x$beta_kind %||% "db")
  sd <- suppressWarnings(as.integer(x$seed %||% NA_integer_))
  if (identical(sat, "random_beta_matched")) {
    if (k == 0L) stop("[rf_capcore] k=0 에서 random_beta_matched 위성은 정의되지 않는다(k=0 = 무처치 · 무작위 위성만 남는 칸은 C1 이 아니다)")
    if (length(bf) != 1L || !nzchar(bf)) stop("[rf_capcore] random_beta_matched 는 beta_factor 필수(사전등록 스펙 값)")
    if (length(sd) != 1L || is.na(sd)) stop("[rf_capcore] random_beta_matched 는 seed 필수(사전등록 스펙 값 — 코드 기본값 없음)")
  } else if (nzchar(paste(bf, collapse = "")) || !is.na(sd[1])) {
    stop("[rf_capcore] satellite=floor 에 beta_factor/seed 는 쓰이지 않는다 — 스펙 결함(같은 처치가 다른 서명이 된다)")
  }
  list(k = k, satellite = sat, beta_factor = bf, beta_kind = bk, seed = sd,
       label = as.character(x$label %||% sprintf("cap_core k=%d %s", k, sat)))
}

#' 코어 — 시그널일별 K200 멤버 중 t-1 시총 상위 k (유동성 t-1 통과) · 비중 = t-1 벤치 비중 근사.
#' @param X data.table(Date, Ticker, K200, .SizeLag, .adv20_l1) — 시그널일 행(엔진 DT 의 그날 행 그대로 · 패널 필터 전)
#' @param k 코어 종목 수(≥1) · liq_min 유동성 하한(격자 fixed_axes.liq_adv20_min — 엔진 .LIQ_MIN)
#' @return list(core = data.table(Date, Ticker, cw, size_lag, rank), diag = data.table(Date, n_k200, n_size, size_cov, denom,
#'              sum_core, n_illiquid_above))  — n_illiquid_above = 시총 순위로는 코어였을 유동성 미달 수(진단)
#'   ★분모 = K200 멤버 전원의 유한 양수 .SizeLag 합(유동성 무관 — 벤치 비중 근사). 코어 후보만 유동성을 통과해야 한다(고정 축 LIQ).
#'   ★k 종을 못 채운 시그널일 · Σc ≥ 1 · 분모 ≤ 0 = stop(코어 없는 달을 '처치 받은 달'로 기록하지 않는다).
rf_cc_core <- function(X, k, liq_min) {
  X <- as.data.table(X)
  need <- c("Date", "Ticker", "K200", ".SizeLag", ".adv20_l1")
  if (!all(need %in% names(X))) stop(sprintf("[rf_capcore] 코어 입력 열 부재: %s", paste(setdiff(need, names(X)), collapse = ",")))
  k <- as.integer(k); liq_min <- as.numeric(liq_min)
  if (length(k) != 1L || is.na(k) || k < 1L) stop("[rf_capcore] rf_cc_core k 는 1 이상")
  if (length(liq_min) != 1L || !is.finite(liq_min)) stop("[rf_capcore] liq_min 이 유한 수 하나가 아니다")
  M <- X[K200 %in% TRUE, .(Date = as.Date(Date), Ticker = as.character(Ticker), s = as.numeric(.SizeLag), a = as.numeric(.adv20_l1))]
  if (anyDuplicated(M[, .(Date, Ticker)])) stop("[rf_capcore] 시그널일 K200 행에 (Date,Ticker) 중복")
  dts <- sort(unique(as.Date(X$Date)))
  if (!length(dts)) stop("[rf_capcore] 시그널일 0개")
  out <- vector("list", length(dts)); dg <- vector("list", length(dts))
  for (i in seq_along(dts)) {
    d <- dts[i]; m <- M[Date == d]
    ok_s <- is.finite(m$s) & m$s > 0
    den <- sum(m$s[ok_s])
    if (!nrow(m)) stop(sprintf("[rf_capcore] %s — K200 멤버 0종(멤버십 결손 · 코어 정의 불가)", format(d)))
    if (!is.finite(den) || den <= 0) stop(sprintf("[rf_capcore] %s — K200 t-1 시총 합 ≤ 0(분모 정의 불가)", format(d)))
    e <- m[ok_s]
    setorderv(e, c("s", "Ticker"), c(-1L, 1L))
    liq <- !is.na(e$a) & e$a >= liq_min
    cand <- e[liq]
    if (nrow(cand) < k) stop(sprintf("[rf_capcore] %s — 유동성 통과 K200 후보 %d < k %d", format(d), nrow(cand), k))
    top <- cand[seq_len(k)]
    # 순수 시총 순위로는 코어였는데 유동성 미달로 빠진 수(진단 · 실데이터 2005~2026 k=2 에서 0 — SIZE-T1 점검 report/size_t1_check.json)
    n_ill <- sum(!liq[seq_len(min(nrow(e), match(top$Ticker[k], e$Ticker)))])
    cw <- top$s / den
    if (sum(cw) >= 1) stop(sprintf("[rf_capcore] %s — 코어 비중 합 %.6f ≥ 1(위성 소멸)", format(d), sum(cw)))
    out[[i]] <- data.table(Date = d, Ticker = top$Ticker, cw = cw, size_lag = top$s, rank = seq_len(k))
    dg[[i]] <- data.table(Date = d, n_k200 = nrow(m), n_size = sum(ok_s), size_cov = sum(ok_s) / nrow(m), denom = den,
                          sum_core = sum(cw), n_illiquid_above = n_ill)
  }
  list(core = rbindlist(out), diag = rbindlist(dg))
}

#' C1 대조 위성 — 바닥 위성과 같은 베타 구간에서 seed 고정 무작위(EW).
#'   시그널일 t: 구간 = 바닥 선정(SEL_t) 중 베타 유한인 이름의 [min, max] · 모집단 = 그날 후보 패널(PANEL_t · 유니버스·유동성·기저 신호 통과)
#'   중 베타 ∈ 구간 · 비복원 min(|SEL_t|, |모집단|) 개. 바닥 이름을 모집단에서 빼지 않는다(무신호 추출 — 같은 베타 분포의 무작위 보유).
#'   ★Score = 그 이름의 바닥 시그널일 점수 — 절단 규칙(바닥 점수 낮은 순)이 대조에도 같은 문언으로 걸린다(결정 ③ 문언 · 보고서 참조).
#'   ★seed: 주 seed 의 runif 흐름에서 달 순번(start 대비)으로 그 달 seed 를 뽑는다 — 접두 안정(뒤에 달이 붙어도 과거 달 추출 불변 ·
#'     null_perm 과 같은 규약). 전역 난수 상태는 되돌린다.
#' @param PANEL data.table(Date, Ticker, Score) · SEL data.table(Date, Ticker) · BETA data.table(Date, Ticker, <bcol>)
#' @return data.table(Date, Ticker, Weight, Score) + attr("rf_cc_rand") = data.table(Date, n_sel, n_beta_sel, n_pool, n_draw, b_lo, b_hi)
rf_cc_random_satellite <- function(PANEL, SEL, BETA, bcol, seed, start) {
  P <- as.data.table(PANEL); S <- as.data.table(SEL); B <- as.data.table(BETA)
  if (!(bcol %in% names(B))) stop("[rf_capcore] 베타 열 부재: ", bcol)
  seed <- suppressWarnings(as.integer(seed)); start <- as.Date(start)
  if (length(seed) != 1L || is.na(seed)) stop("[rf_capcore] seed 부재")
  if (length(start) != 1L || is.na(start)) stop("[rf_capcore] start 부재")
  B <- B[, .(Date = as.Date(Date), Ticker = as.character(Ticker), b = as.numeric(get(bcol)))][is.finite(b)]
  P <- merge(P[, .(Date = as.Date(Date), Ticker = as.character(Ticker), Score)], B, by = c("Date", "Ticker"), all.x = TRUE)
  S <- unique(S[, .(Date = as.Date(Date), Ticker = as.character(Ticker))])
  nd <- sort(unique(S$Date))
  if (!length(nd)) stop("[rf_capcore] 바닥 선정 0일")
  nmi <- (as.integer(format(nd, "%Y")) - as.integer(format(start, "%Y"))) * 12L +
         (as.integer(format(nd, "%m")) - as.integer(format(start, "%m")))
  if (any(nmi < 0L) || anyDuplicated(nmi))
    stop("[rf_capcore] 시그널일이 시작 달 앞이거나 한 달에 둘이다 — 달별 seed 정의 불가(측정 무효)")
  rs_old <- if (exists(".Random.seed", envir = globalenv(), inherits = FALSE)) get(".Random.seed", envir = globalenv()) else NULL
  rk_old <- RNGkind()
  on.exit({ if (is.null(rs_old)) { RNGkind(rk_old[1], rk_old[2], rk_old[3])
              if (exists(".Random.seed", envir = globalenv(), inherits = FALSE)) rm(".Random.seed", envir = globalenv()) }
            else assign(".Random.seed", rs_old, envir = globalenv()) }, add = TRUE)
  set.seed(seed, kind = "Mersenne-Twister", normal.kind = "Inversion", sample.kind = "Rejection")
  ms <- as.integer(floor(stats::runif(max(nmi) + 1L) * 2147483646)) + 1L
  out <- vector("list", length(nd)); dg <- vector("list", length(nd))
  for (i in seq_along(nd)) {
    d <- nd[i]
    sel <- S[Date == d]$Ticker
    pd <- P[Date == d]
    bs <- pd[Ticker %in% sel & is.finite(b)]$b
    if (!length(bs)) stop(sprintf("[rf_capcore] %s — 바닥 위성의 베타가 전부 결측(구간 정의 불가 · 대조 칸 측정 무효)", format(d)))
    lo <- min(bs); hi <- max(bs)
    pool <- pd[is.finite(b) & b >= lo & b <= hi]
    setorder(pool, Ticker)                               # 추출 전 정렬 — 행 순서가 추출을 바꾸지 않게(결정론)
    n <- min(length(sel), nrow(pool))
    if (n < 1L) stop(sprintf("[rf_capcore] %s — 베타 구간 모집단 0", format(d)))
    set.seed(ms[nmi[i] + 1L], kind = "Mersenne-Twister", normal.kind = "Inversion", sample.kind = "Rejection")
    pick <- pool[sort(sample.int(nrow(pool), n))]
    out[[i]] <- data.table(Date = d, Ticker = pick$Ticker, Weight = 1 / n, Score = pick$Score)
    dg[[i]] <- data.table(Date = d, n_sel = length(sel), n_beta_sel = length(bs), n_pool = nrow(pool), n_draw = n, b_lo = lo, b_hi = hi)
  }
  R <- rbindlist(out)
  setattr(R, "rf_cc_rand", rbindlist(dg))
  R
}

#' 코어 + 위성 합성 — union_truncation · 비중 재조정 · 불변식.
#' @param SAT   data.table(Date, Ticker, Weight[, Score]) — 위성 비중(시그널일별 합 > 0 · 음수 금지). Score 열이 없으면 SCORE 에서 붙인다.
#' @param CORE  rf_cc_core()$core
#' @param n_max 고정 축 보유 상한(격자 fixed_axes.n_max)
#' @param SCORE data.table(Date, Ticker, Score) — 절단 순위(바닥 시그널일 점수). 위성 이름의 점수가 없으면 stop.
#' @return list(portfolio = data.table(Date, Ticker, Weight, role ∈ core|satellite|core+satellite), diag = data.table(Date, n_core, n_sat_in,
#'              n_overlap, n_truncated, n_hold, sum_core, sum_sat, w_max))
rf_cc_compose <- function(SAT, CORE, n_max, SCORE = NULL) {
  SAT <- as.data.table(SAT); CORE <- as.data.table(CORE)
  n_max <- as.integer(n_max)
  if (length(n_max) != 1L || is.na(n_max) || n_max < 1L) stop("[rf_capcore] n_max 결함")
  if (!all(c("Date", "Ticker", "Weight") %in% names(SAT))) stop("[rf_capcore] 위성 열(Date,Ticker,Weight) 부재")
  if (!all(c("Date", "Ticker", "cw") %in% names(CORE))) stop("[rf_capcore] 코어 열(Date,Ticker,cw) 부재")
  has_sc <- "Score" %in% names(SAT)
  SAT <- if (has_sc) SAT[, .(Date = as.Date(Date), Ticker = as.character(Ticker), f = as.numeric(Weight), Score = as.numeric(Score))]
         else SAT[, .(Date = as.Date(Date), Ticker = as.character(Ticker), f = as.numeric(Weight))]
  if (!has_sc) {                                            # 위성에 점수가 없으면 바닥 점수표에서 붙인다(없는 이름 = NA → 절단 때 stop)
    if (is.null(SCORE)) stop("[rf_capcore] 절단 순위 점수(SCORE) 부재")
    SC <- unique(as.data.table(SCORE)[, .(Date = as.Date(Date), Ticker = as.character(Ticker), Score = as.numeric(Score))])
    if (anyDuplicated(SC[, .(Date, Ticker)])) stop("[rf_capcore] 점수표 (Date,Ticker) 중복")
    SAT <- merge(SAT, SC, by = c("Date", "Ticker"), all.x = TRUE)
  }
  if (anyDuplicated(SAT[, .(Date, Ticker)])) stop("[rf_capcore] 위성 (Date,Ticker) 중복")
  if (any(!is.finite(SAT$f)) || any(SAT$f < 0)) stop("[rf_capcore] 위성 비중에 음수·비유한")
  CORE <- CORE[, .(Date = as.Date(Date), Ticker = as.character(Ticker), cw = as.numeric(cw))]
  dts <- sort(unique(SAT$Date))
  miss <- setdiff(as.character(dts), as.character(unique(CORE$Date)))
  if (length(miss)) stop(sprintf("[rf_capcore] 코어가 없는 위성 시그널일 %d개(예: %s)", length(miss), miss[1]))
  out <- vector("list", length(dts)); dg <- vector("list", length(dts))
  for (i in seq_along(dts)) {
    d <- dts[i]
    s <- SAT[Date == d & f > 0]
    cc <- CORE[Date == d]
    kc <- nrow(cc)
    if (kc >= n_max) stop(sprintf("[rf_capcore] 코어 %d종 ≥ n_max %d — 위성이 사라진다", kc, n_max))
    if (!nrow(s)) stop(sprintf("[rf_capcore] %s — 위성 0종(바닥 보유 없음)", format(d)))
    sc <- sum(cc$cw)
    if (!is.finite(sc) || sc <= 0 || sc >= 1) stop(sprintf("[rf_capcore] %s — 코어 비중 합 %.6f ∉ (0,1)", format(d), sc))
    ov <- s[Ticker %in% cc$Ticker]
    nc <- s[!(Ticker %in% cc$Ticker)]
    room <- n_max - kc
    n_tr <- 0L
    if (nrow(nc) > room) {
      if (any(!is.finite(nc$Score))) stop(sprintf("[rf_capcore] %s — 절단 대상 위성의 점수 결측(순위 정의 불가)", format(d)))
      setorderv(nc, c("Score", "Ticker"), c(-1L, 1L))       # 점수 높은 순 · 동률 Ticker 사전순 → 뒤(낮은 점수)부터 뺀다
      n_tr <- nrow(nc) - room
      nc <- nc[seq_len(room)]
    }
    keep <- rbind(ov, nc)
    fs <- sum(keep$f)
    if (!is.finite(fs) || fs <= 0) stop(sprintf("[rf_capcore] %s — 남은 위성 비중 합 ≤ 0", format(d)))
    keep[, ws := (1 - sc) * f / fs]
    W <- merge(cc[, .(Ticker, cw)], keep[, .(Ticker, ws)], by = "Ticker", all = TRUE)
    W[is.na(cw), cw := 0][is.na(ws), ws := 0]
    W[, `:=`(Date = d, Weight = cw + ws,
             role = fifelse(cw > 0 & ws > 0, "core+satellite", fifelse(cw > 0, "core", "satellite")))]
    # ── 불변식 (고정 축) ──
    stopifnot(all(is.finite(W$Weight)), all(W$Weight >= 0), abs(sum(W$Weight) - 1) < 1e-10, nrow(W) <= n_max,
              !anyDuplicated(W$Ticker))
    out[[i]] <- W[, .(Date, Ticker, Weight, role)]
    dg[[i]] <- data.table(Date = d, n_core = kc, n_sat_in = nrow(s), n_overlap = nrow(ov), n_truncated = n_tr,
                          n_hold = nrow(W), sum_core = sc, sum_sat = sum(W$ws), w_max = max(W$Weight))
  }
  list(portfolio = rbindlist(out), diag = rbindlist(dg))
}

#' 로그 한 줄(진단) — 서술은 칸 사이에서 갈리는 값(Σc 범위 · 겹침 · 절단 · 보유 수)을 적는다.
rf_cc_report <- function(cc, diag, core_diag) {
  sprintf(paste0("cap_core=%s | k=%d · 위성=%s · Σ코어 평균 %.4f(%.4f~%.4f) · 겹침 평균 %.2f · 절단 평균 %.2f · 보유 %d~%d종 · ",
                 "K200 t-1 시총 커버리지 최소 %.4f · 유동성 미달로 밀린 시총 상위 %d건 · 시그널일 %d"),
          cc$label, cc$k, cc$satellite, mean(diag$sum_core), min(diag$sum_core), max(diag$sum_core),
          mean(diag$n_overlap), mean(diag$n_truncated), min(diag$n_hold), max(diag$n_hold),
          min(core_diag$size_cov), sum(core_diag$n_illiquid_above), nrow(diag))
}

cat("[rf_capcore.R] Loaded — rf_cc_parse / rf_cc_core / rf_cc_random_satellite / rf_cc_compose / rf_cc_report\n")
