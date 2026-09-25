#!/usr/bin/env Rscript
#==============================================================================
# rf_preflight.R — 셀 착수 전 **지식 주입** (도훈 지시 2026-08-30 감사 지적)
#
# 왜 필요한가 (2026-08-30 감사 실측):
#   무인 러너는 LLM 에이전트를 **0개** 스폰한다. 그래서 `axiom_context_inject.sh`
#   (PreToolUse|Agent)가 한 번도 발화하지 않는다.
#   ★공리 쪽은 결함이 아니다 — 공리는 *판단*을 제약하는데 규칙 실행에는 셀 실행 시점의
#     판단이 없다. 설계는 격자 작성 시 한 번 이뤄졌고 PIT·고정축은 엔진·계약이 강제한다.
#   ★그러나 **지식 주입은 진짜 빠져 있었다**: `hypothesis_index`(죽은 구성 380건) 조회 0건,
#     `rf_lessons_digest`(직전 시도 교훈) 0건. SKILL 1단계가 "착수 전 의무" 로 요구하는 것들이다.
#     조회를 안 하면 **이미 죽은 조합을 다시 돌린다**.
#
# 이 파일이 하는 일 (판단하지 않는다 — 사실만 붙인다):
#   ① hypothesis_index 조회 — 셀 구성 키워드로 죽은 선례를 찾아 스펙·로그에 붙인다
#   ② rf_lessons_digest    — 직전 시도들의 등급·교훈 요약을 붙인다
#   ③ 고정 축 사후 검증    — 산출물이 실제로 long-only·<=25종·Sigma w=1 인지 재도출
#      (공리를 "주입" 하는 대신 **결과에서 확인**한다 — 규칙 실행에 맞는 형태)
#      ★2026-09-24 P0-02: 04_holdings 에서 재도출(n_max·w>=0·|Σw-1|·시작일·유니버스 as-of·LIQ t-1).
#        구판은 AR 최상위 n_max/has_short 를 읽어 1099/1099 공허 통과였다(러너는 replication$ 아래에 쓴다).
#   ④ 과거 칸 진단 백필    — rf_essence_diag_backfill(): 형제 essence_diag.json 만 쓴다(원장 무접촉)
#
# ★차단하지 않는다. 죽은 선례가 있어도 실행은 진행하고 **기록**한다 —
#   AX-000("실측 negative 는 사실 기록이지 금지 목록이 아니다")과 정합.
#==============================================================================
suppressMessages({ library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")

#' 셀 구성에서 조회 키워드를 뽑는다 — **이름이 아니라 구성으로** 조회한다
#' (2026-08-29 실증: 이름 조회는 0건인데 구성 조회가 선례를 찾아냈다)
rf_preflight_keywords <- function(spec) {
  kw <- character(0)
  # ★팩터는 두 자리에 담긴다 — 현행 격자는 factors(복수), 구 스펙은 factor2/factor3(단수).
  #   구판은 factor2 만 읽어 현행 셀에서 팩터 키가 0건이었다(선언은 원천을 말하지 산출 축을 말하지 않는다).
  .fl <- c(spec$factors %||% list(),
           if (!is.null(spec$factor2) && !identical(spec$factor2$kind %||% "", "none")) list(spec$factor2),
           if (!is.null(spec$factor3) && !identical(spec$factor3$kind %||% "", "none")) list(spec$factor3))
  .ids <- unique(vapply(.fl, function(x) as.character(x$id %||% x$kind %||% ""), character(1)))
  .ids <- .ids[nzchar(.ids) & .ids != "none"]
  kw <- c(kw, .ids)
  # 계열도 함께 — id 는 저장소마다 다르지만 계열은 문헌 검색어에 가깝다
  .fam <- tryCatch({
    suppressMessages(source(file.path(ROOT, "02_Infrastructure/ops/rf_factor_arms.R"), local = TRUE))
    f <- rf_factor_families(.ids, ROOT); unique(f[!is.na(f) & nzchar(f)])
  }, error = function(e) character(0))
  kw <- c(kw, .fam)
  if (!is.null(spec$overlay$kind) && !identical(spec$overlay$kind, "none"))
    kw <- c(kw, as.character(spec$overlay$kind))
  f2 <- spec$factor2
  if (!is.null(f2$id) && nzchar(f2$id)) kw <- c(kw, f2$id)
  if (identical(f2$kind, "price") && identical(f2$id, "lowvol60")) kw <- c(kw, "volatility", "lowvol")
  if (!is.null(f2$id)) {
    if (grepl("Amihud|Kyle|LIQ", f2$id, ignore.case = TRUE)) kw <- c(kw, "illiquidity", "turnover")
    if (grepl("BM|value", f2$id, ignore.case = TRUE))        kw <- c(kw, "value_momentum")
    if (grepl("GPA|quality|Q0", f2$id, ignore.case = TRUE))  kw <- c(kw, "quality_profitability")
    if (grepl("Revision|SUE|C1", f2$id, ignore.case = TRUE)) kw <- c(kw, "earnings_revision")
  }
  wk <- spec$weighting$kind %||% "ew"
  if (!identical(wk, "ew")) kw <- c(kw, wk)
  uk <- spec$universe$kind %||% "k200_kq150"
  if (!identical(uk, "k200_kq150")) kw <- c(kw, uk)
  unique(kw[nzchar(kw)])
}

#' hypothesis_index 조회 (CLI 정본 경유 — 술어를 재구현하지 않는다)
rf_preflight_dead <- function(kw, max_kw = 4L) {
  idx <- file.path(ROOT, "02_Infrastructure/tools/hypothesis_index.R")
  if (!file.exists(idx) || !length(kw)) return(list())
  out <- list()
  for (k in utils::head(kw, max_kw)) {
    r <- tryCatch(system2("Rscript", c(shQuote(idx), "lookup", shQuote(k)),
                          stdout = TRUE, stderr = FALSE), error = function(e) character(0))
    hits <- grep("FAIL|DISTILLED_NEG|VALIDATED_NEGATIVE|negative", r, value = TRUE, ignore.case = TRUE)
    if (length(hits)) out[[k]] <- substr(utils::head(hits, 3), 1, 140)
  }
  out
}

#' 직전 시도 교훈 요약
rf_preflight_lessons <- function(base_id, n_last = 3L) {
  led <- tryCatch(fromJSON(file.path(ROOT, "06_Registry/reinforce_ledger_l1.json"), simplifyVector = FALSE),
                  error = function(e) NULL)
  if (is.null(led)) return(character(0))
  E <- Filter(function(e) identical(e$base_id, base_id), led$entries)
  if (!length(E)) return(character(0))
  at <- E[[1]]$attempts
  at <- Filter(function(a) !is.null(a$essence) && !is.null(a$essence$port_t), at)
  if (!length(at)) return(character(0))
  at <- utils::tail(at, n_last)
  vapply(at, function(a) sprintf("n=%d %s Grade %s · PORT_t %.3f",
                                 a$n, a$essence$cell_code %||% "?", a$grade %||% "?",
                                 as.numeric(a$essence$port_t)), character(1))
}

#' active 공리(전역 Law) 적재 — 무인 R 레인은 Agent 를 스폰하지 않아 주입 훅을 지나지 않는다.
#'   훅이 못 닿으면 **레인이 직접 읽는다**. 안 읽고 읽었다고 적는 것이 최악이다.
rf_preflight_axioms <- function(root = ROOT, max_chars = 110L) {
  d <- file.path(root, "qepm/memory/axioms/active")
  fs <- tryCatch(list.files(d, pattern = "^AX-", full.names = TRUE), error = function(e) character(0))
  fs <- fs[endsWith(fs, ".json")]          # ★정규식 이스케이프를 피한다 — 이 저장소에서 반복해 접혔다
  if (!length(fs)) return(character(0))
  out <- vapply(sort(fs), function(f) {
    ax <- tryCatch(fromJSON(f, simplifyVector = FALSE), error = function(e) NULL)
    if (is.null(ax)) return(NA_character_)
    id <- as.character(ax$axiom_id %||% ax$id %||% sub(".json", "", basename(f), fixed = TRUE))
    st <- as.character(ax$statement %||% ax$text %||% ax$name %||% "")
    st <- substr(trimws(gsub("[[:space:]]+", " ", st)), 1L, max_chars)
    sprintf("%s: %s", id, st)
  }, character(1))
  unname(out[!is.na(out) & nzchar(out)])
}

#' ★고정 축 사후 검증 — 공리를 주입하는 대신 **산출물에서 재도출**한다
#'
#' (P0-02 · 2026-09-24 재작성) 구판은 `AR$n_max` / `AR$has_short` 를 읽었는데 러너(run_paper_replication.R)는
#'   그 값을 `AR$replication$n_max` 아래에 쓴다 — 최상위 키가 늘 NULL 이라 **1099/1099 칸에서 공허하게 통과**했다
#'   (감사 D8-07 · 메모리 "verify 고정축 게이트는 최상위 키를 읽지만 러너는 replication$ 아래에 쓴다").
#'   게다가 그 값은 선언이지 실현이 아니다(선언은 원천을 말하지 산출 축을 말하지 않는다).
#'   ⇒ 이제 **04_holdings.csv(없으면 bt_result.rds$holdings) 에서 재도출**한다. AR 키는 참고(declared)로만 읽는다.
#'
#' 재도출 항목 (fixed = 격자 06_Registry/reinforce_program.json::fixed_axes):
#'   n_max        날짜별 보유 수(비중 != 0) 최대 > fixed$n_max            → 위반
#'   long_only    최소 비중 < -tol                                        → 위반
#'   Σw           날짜별 Σw > 1 + tol                                     → 위반(레버리지)
#'                날짜별 Σw < 1 - tol                                     → ★라벨 sigma_w_lt_1 (위반 아님 —
#'                도훈 D-D: Σw=1 은 위험자산 정규화, 오버레이 현금과 양립)
#'   시작일       첫 보유일의 fixed$start_date 대비 달력 월 차 > 허용(diagnostics.window_allowance_months = 도훈 D-C 12)
#'                → 위반 window_deviation + holds 에 "window_deviation"(처분 = P0-12 A 보류 · 바닥·carry 제외)
#'   유니버스     보유 (종목, 시그널일 d) 가 K200∪KQ150 멤버(as-of d)가 아니면  → 위반
#'   LIQ          adv20(t-1) = shift(frollmean(Close*Vol, 20), 1) at d < fixed$liq_adv20_min → 위반
#'   ★시그널일 d = max(RAWDATA 거래일 < 보유일). 복제 하네스는 보유를 **집행일**(= get_execution_date(d) =
#'     익월 첫 거래일)로 찍고, 러너 .apply_universe·엔진 PANEL 은 멤버십·유동성을 **시그널일 행**에서 자른다 —
#'     그래서 as-of 는 보유일이 아니라 d 다(보유일 멤버십으로 재면 편출 당일 종목을 오판한다 — 검사 V9).
#'
#' 판독 불가 = NA(통과 아님). ok = 위반 있으면 FALSE · 판정 못 한 항목이 있으면 NA · 전부 판정·무위반이면 TRUE.
#' @param spec     셀 스펙(선택). universe.kind 가 k200_kq150 계열이 아니면(B3 all_listed·size_band 처치)
#'                 유니버스 이탈을 위반이 아니라 라벨 universe_treatment:<kind> 로 둔다(선언된 처치).
#' @param rawdata  주입(검사용) — data.table(Date, Ticker, Close, Vol, K200, KQ150). NULL 이면 .cache/RAWDATA.parquet
#'                 에서 보유 종목만 읽는다(mmap 없음 · 1초 안팎).
#' @param holdings 주입(검사용) — data.frame(date, ticker, weight 계열). NULL 이면 산출물에서 읽는다.
rf_preflight_verify_axes <- function(ar_path, fixed, spec = NULL, rawdata = NULL, holdings = NULL,
                                     root = ROOT) {
  art <- dirname(ar_path)
  out <- list(ok = NA, violations = character(0), codes = character(0), labels = character(0),
              holds = character(0), checks = list(), derived = list(), note = "")
  H <- if (!is.null(holdings)) .rf_pf_norm_holdings(holdings, "injected") else .rf_pf_read_holdings(art)
  if (is.null(H)) {
    out$note <- "보유 산출물 부재/판독 불가 — 고정 축 미검증(NA · 통과 아님)"
    out$derived$source <- NA_character_
    return(out)
  }
  ES <- .rf_pf_es_env(root)
  dp <- ES$.essence_diag_params(root = root)
  tol <- dp$axes_weight_tol
  fx <- if (is.list(fixed)) fixed else list()
  .fxn <- function(k) { v <- suppressWarnings(as.numeric(fx[[k]])[1]); if (length(v) == 1L && is.finite(v)) v else NA_real_ }
  held <- H[is.finite(w) & w != 0]
  bad <- character(0); codes <- character(0); labs <- character(0); holds <- character(0); chk <- list()
  D <- list(source = attr(H, "source"), n_rows = nrow(H), n_dates = data.table::uniqueN(H$date))
  # AR 선언값(참고) — 판정에 쓰지 않는다
  AR <- tryCatch(jsonlite::fromJSON(ar_path, simplifyVector = TRUE), error = function(e) NULL)
  D$n_max_declared <- suppressWarnings(as.integer((AR$replication$n_max %||% AR$n_max %||% NA)[1]))

  # ① n_max
  nfx <- .fxn("n_max")
  per <- if (nrow(held)) held[, .(n = .N), by = date] else data.table::data.table(date = as.Date(character(0)), n = integer(0))
  D$n_max_realized <- if (nrow(per)) max(per$n) else 0L
  D$n_max_fixed <- nfx
  chk$n_max <- if (is.na(nfx)) NA else (D$n_max_realized <= nfx)
  if (isFALSE(chk$n_max)) {
    bad <- c(bad, sprintf("n_max %d > %d (04_holdings realized)", D$n_max_realized, as.integer(nfx)))
    codes <- c(codes, "n_max")
  }
  # ② long-only
  D$w_min <- if (nrow(H)) min(H$w[is.finite(H$w)]) else NA_real_
  lo <- fx[["long_only"]]
  chk$long_only <- if (!isTRUE(lo)) NA else if (!is.finite(D$w_min)) NA else
    (D$w_min >= (if (is.finite(tol)) -tol else 0))
  if (isFALSE(chk$long_only)) {
    bad <- c(bad, sprintf("w<0 (min %.6g, %d rows) - long-only", D$w_min, sum(H$w < 0, na.rm = TRUE)))
    codes <- c(codes, "negative_weight")
  }
  # ③ Σw
  sw <- H[is.finite(w), .(s = sum(w)), by = date]
  D$sigma_w_min <- if (nrow(sw)) min(sw$s) else NA_real_
  D$sigma_w_max <- if (nrow(sw)) max(sw$s) else NA_real_
  D$sigma_w_absdev_max <- if (nrow(sw)) max(abs(sw$s - 1)) else NA_real_
  chk$sigma_w <- if (!is.finite(tol) || !nrow(sw)) NA else (D$sigma_w_max <= 1 + tol)
  if (isFALSE(chk$sigma_w)) {
    bad <- c(bad, sprintf("sigma_w>1 (max %.6f)", D$sigma_w_max)); codes <- c(codes, "sigma_w_gt_1")
  }
  if (is.finite(tol) && nrow(sw) && D$sigma_w_min < 1 - tol) {
    labs <- c(labs, "sigma_w_lt_1")
    D$sigma_w_lt_1_dates <- sum(sw$s < 1 - tol)
  }
  # ④ 시작일 (창 규칙 D-C)
  fsd <- if (nrow(held)) min(held$date) else as.Date(NA)
  anc <- tryCatch(as.Date(as.character(fx[["start_date"]])[1]), error = function(e) as.Date(NA))
  if (length(anc) != 1L) anc <- as.Date(NA)
  if (is.na(anc)) anc <- dp$window_anchor_date
  dev <- ES$.essence_month_diff(anc, fsd)
  allow <- dp$window_allowance_months
  D$first_holding_date <- if (is.na(fsd)) NA_character_ else format(fsd)
  D$window_anchor_date <- if (is.na(anc)) NA_character_ else format(anc)
  D$window_deviation_months <- dev
  D$window_allowance_months <- allow
  chk$start <- if (is.na(dev) || !is.finite(allow)) NA else (dev <= allow)
  if (isFALSE(chk$start)) {
    bad <- c(bad, sprintf("window_deviation %dm > allow %dm (first holding %s vs %s)",
                          dev, as.integer(allow), format(fsd), format(anc)))
    codes <- c(codes, "window_deviation"); holds <- c(holds, "window_deviation")
  }
  # ⑤⑥ 유니버스(as-of) · LIQ(t-1)
  uni <- toupper(as.character(fx[["universe"]] %||% ""))
  liq_min <- .fxn("liq_adv20_min")
  want_u <- identical(uni, "K200_KQ150")
  want_l <- is.finite(liq_min)
  chk$universe <- NA; chk$liq <- NA
  if ((want_u || want_l) && nrow(held)) {
    RD <- tryCatch(if (!is.null(rawdata)) .rf_pf_norm_rawdata(rawdata) else
                     .rf_pf_read_rawdata(root, unique(held$ticker)),
                   error = function(e) { D$rawdata_error <<- conditionMessage(e); NULL })
    if (!is.null(RD)) {
      X <- .rf_pf_asof(held, RD)
      D$decision_date_rule <- "d = max(RAWDATA 거래일 < 보유일) — 러너 .apply_universe · 엔진 PANEL 과 같은 시그널일"
      D$asof_rows <- nrow(X)
      D$asof_missing_rows <- sum(!X$has_row)
      if (want_u) {
        outside <- X$has_row & !X$member
        D$universe_outside_rows <- sum(outside)
        D$universe_outside_tickers <- utils::head(unique(X$ticker[outside]), 10L)
        kind <- tryCatch(as.character(spec$universe$kind %||% ""), error = function(e) "")
        treat <- nzchar(kind) && !kind %in% c("k200_kq150", "sector_neutral", "index")
        chk$universe <- if (any(!X$has_row)) (if (any(outside)) FALSE else NA) else !any(outside)
        if (any(!X$has_row)) labs <- c(labs, "universe_unverifiable")
        if (any(outside)) {
          if (treat) {
            chk$universe <- NA
            labs <- c(labs, paste0("universe_treatment:", kind))
          } else {
            bad <- c(bad, sprintf("universe outside K200+KQ150 as-of d: %d rows (%s)", sum(outside),
                                  paste(utils::head(unique(X$ticker[outside]), 3L), collapse = ",")))
            codes <- c(codes, "universe_outside")
          }
        }
      }
      if (want_l) {
        below <- X$has_row & is.finite(X$adv20_l1) & X$adv20_l1 < liq_min
        unk <- X$has_row & !is.finite(X$adv20_l1)
        D$liq_min <- liq_min
        D$liq_below_rows <- sum(below)
        D$liq_unverifiable_rows <- sum(unk) + sum(!X$has_row)
        D$liq_min_ratio <- if (any(is.finite(X$adv20_l1))) min(X$adv20_l1[is.finite(X$adv20_l1)]) / liq_min else NA_real_
        chk$liq <- if (any(below)) FALSE else if (D$liq_unverifiable_rows > 0) NA else TRUE
        if (D$liq_unverifiable_rows > 0) labs <- c(labs, "liq_unverifiable")
        if (any(below)) {
          bad <- c(bad, sprintf("LIQ adv20(t-1) < %.0f: %d rows (min ratio %.3f)", liq_min, sum(below), D$liq_min_ratio))
          codes <- c(codes, "liq_below")
        }
      }
    } else labs <- c(labs, "rawdata_unavailable")
  }
  out$violations <- bad; out$codes <- codes; out$labels <- unique(labs); out$holds <- unique(holds)
  out$checks <- chk; out$derived <- D
  out$ok <- if (length(bad)) FALSE else if (any(vapply(chk, function(x) is.na(x), logical(1)))) NA else TRUE
  out$note <- if (length(bad)) "고정 축 위반 — 결과 무효 검토" else if (is.na(out$ok))
    "고정 축 일부 미판정(NA) — 위반 없음 · 통과 아님" else
    "고정 축 재도출 확인(04_holdings: n_max·long-only·Σw·시작일·유니버스 as-of·LIQ t-1)"
  out
}

# ── 내부 부품 ────────────────────────────────────────────────────────────────
# essence_score.R 을 사적 환경에 적재 — 진단 설정·월 차를 **같은 코드**로 쓴다(사본 금지)
.rf_pf_es_env <- function(root = ROOT) {
  e <- new.env(parent = globalenv())
  suppressMessages(sys.source(file.path(root, "02_Infrastructure/contracts/essence_score.R"), envir = e,
                              keep.source = FALSE))
  e
}

.rf_pf_norm_holdings <- function(h, source) {
  h <- data.table::as.data.table(h)
  dc <- intersect(c("date", "Date", "Exec_Date"), names(h))
  tc <- intersect(c("ticker", "Ticker"), names(h))
  wc <- intersect(c("actual_weight", "target_weight", "weight", "Weight"), names(h))
  if (!length(dc) || !length(tc) || !length(wc)) return(NULL)
  w <- suppressWarnings(as.numeric(h[[wc[1]]]))
  if (all(is.na(w)) && length(wc) > 1L) w <- suppressWarnings(as.numeric(h[[wc[2]]]))
  d <- h[[dc[1]]]
  d <- if (inherits(d, "Date")) d else tryCatch(as.Date(as.character(d)), error = function(e) as.Date(rep(NA, length(d))))
  out <- data.table::data.table(date = as.Date(d), ticker = as.character(h[[tc[1]]]), w = w)
  out <- out[!is.na(date) & !is.na(ticker)]
  data.table::setattr(out, "source", source)
  out
}

.rf_pf_read_holdings <- function(art) {
  f <- file.path(art, "04_holdings.csv")
  if (file.exists(f)) {
    h <- tryCatch(data.table::fread(f, showProgress = FALSE), error = function(e) NULL)
    if (!is.null(h) && nrow(h)) { r <- .rf_pf_norm_holdings(h, "04_holdings.csv"); if (!is.null(r)) return(r) }
  }
  b <- file.path(art, "bt_result.rds")
  if (file.exists(b)) {
    h <- tryCatch(readRDS(b)$holdings, error = function(e) NULL)
    if (!is.null(h) && NROW(h)) return(.rf_pf_norm_holdings(h, "bt_result.rds$holdings"))
  }
  NULL
}

.rf_pf_norm_rawdata <- function(x) {
  x <- data.table::as.data.table(x)
  need <- c("Date", "Ticker", "Close", "Vol", "K200", "KQ150")
  if (!all(need %in% names(x))) stop("rawdata 열 부재: ", paste(setdiff(need, names(x)), collapse = ","))
  x <- x[, need, with = FALSE]
  if (!inherits(x$Date, "Date")) x[, Date := as.Date(Date)]
  list(panel = x, dates = sort(unique(x$Date)))
}

# 보유 종목만 읽는다 — 거래일 목록은 전 종목에서(시그널일 = 전체 거래일 기준 직전 거래일)
.rf_pf_read_rawdata <- function(root, tickers) {
  f <- file.path(root, ".cache", "RAWDATA.parquet")
  if (!file.exists(f)) stop("RAWDATA.parquet 부재: ", f)
  if (!requireNamespace("arrow", quietly = TRUE) || !requireNamespace("dplyr", quietly = TRUE))
    stop("arrow/dplyr 부재")
  ds <- arrow::open_dataset(f)
  tk <- unique(as.character(tickers))
  p <- data.table::as.data.table(dplyr::collect(dplyr::select(dplyr::filter(ds, Ticker %in% tk),
                                                             Date, Ticker, Close, Vol, K200, KQ150)))
  dts <- data.table::as.data.table(dplyr::collect(dplyr::distinct(dplyr::select(ds, Date))))$Date
  if (!inherits(p$Date, "Date")) p[, Date := as.Date(Date)]
  list(panel = p, dates = sort(unique(as.Date(dts))))
}

# (종목, 보유일) → 시그널일 d 의 멤버십 · adv20(t-1). 엔진(rf_cell_engine.R)과 같은 식:
#   .TV = Close*Vol · adv20_l1 = shift(frollmean(.TV, 20, align="right"), 1) by Ticker (종목 자기 행 순서)
.rf_pf_asof <- function(held, RD) {
  P <- data.table::copy(RD$panel)
  data.table::setorder(P, Ticker, Date)
  P[, tv := as.numeric(Close) * as.numeric(Vol)]
  P[, adv20_l1 := data.table::shift(data.table::frollmean(tv, 20L, align = "right"), 1L), by = Ticker]
  P[, member := (K200 == 1 | KQ150 == 1)]
  P[is.na(member), member := FALSE]
  hd <- sort(unique(held$date))
  idx <- findInterval(as.numeric(hd) - 0.5, as.numeric(RD$dates))
  dmap <- data.table::data.table(date = hd, dsig = as.Date(ifelse(idx > 0, as.numeric(RD$dates)[pmax(idx, 1L)], NA_real_),
                                                          origin = "1970-01-01"))
  X <- merge(held[, .(date, ticker)], dmap, by = "date", all.x = TRUE)
  X <- merge(X, P[, .(ticker = Ticker, dsig = Date, member, adv20_l1)], by = c("ticker", "dsig"), all.x = TRUE)
  X[, has_row := !is.na(member)]
  X[is.na(member), member := FALSE]
  X
}

#' 과거 칸 진단 백필 — 형제 파일 essence_diag.json 만 쓴다 (P0-02 · 원장·authoritative_remeasure.json 무접촉)
#'
#' bt_result.rds 에서 essence_diagnostics()(재채점 없음) + 고정 축 재도출(rf_preflight_verify_axes)을 만들어
#'   artifact_dir 옆에 원자적으로(같은 디렉터리 임시 파일 → rename) 쓴다. 저장 등급은 **읽어서 병기**할 뿐
#'   다시 매기지 않는다. 보호 파일(authoritative_remeasure.json · bt_result.rds · 원장) 경로로는 쓰지 않는다.
#' @return 기록한 list (invisible)
rf_essence_diag_backfill <- function(artifact_dir, out = file.path(artifact_dir, "essence_diag.json"),
                                     fixed = NULL, rawdata = NULL, with_axes = TRUE, root = ROOT) {
  btp <- file.path(artifact_dir, "bt_result.rds")
  if (!file.exists(btp)) stop("[rf_essence_diag_backfill] bt_result.rds 부재: ", btp)
  if (basename(out) %in% c("authoritative_remeasure.json", "bt_result.rds", "reinforce_ledger_l1.json",
                           "reinforce_ledger_l2.json") || !grepl("\\.json$", out))
    stop("[rf_essence_diag_backfill] 보호 파일·비 JSON 경로에는 쓰지 않는다: ", out)
  ES <- .rf_pf_es_env(root)
  bt <- readRDS(btp)
  dg <- ES$essence_diagnostics(bt, root = root)
  arp <- file.path(artifact_dir, "authoritative_remeasure.json")
  AR <- tryCatch(jsonlite::fromJSON(arp, simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(fixed))
    fixed <- tryCatch(jsonlite::fromJSON(file.path(root, "06_Registry/reinforce_program.json"),
                                         simplifyVector = FALSE)$fixed_axes, error = function(e) NULL)
  ax <- if (isTRUE(with_axes) && !is.null(fixed))
    tryCatch(rf_preflight_verify_axes(arp, fixed, rawdata = rawdata, root = root),
             error = function(e) list(ok = NA, note = paste("verify 실패:", conditionMessage(e)))) else NULL
  .md5 <- function(p) tryCatch(unname(as.character(tools::md5sum(p))), error = function(e) NA_character_)
  rec <- list(
    schema = "essence_diag_backfill_v1",
    artifact_dir = normalizePath(artifact_dir, winslash = "/", mustWork = FALSE),
    computed_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    provenance = list(bt_result_md5 = .md5(btp),
                      essence_score_md5 = .md5(file.path(root, "02_Infrastructure/contracts/essence_score.R")),
                      rf_preflight_md5 = .md5(file.path(root, "02_Infrastructure/ops/rf_preflight.R")),
                      config_source = dg$params$source),
    stored = list(essence_grade = AR$essence_grade %||% NA_character_,
                  oos_retention = AR$essence$oos_retention %||% NA_real_,
                  measurement_regime = AR$measurement_regime),
    diagnostics = dg,
    axes = ax,
    note = "형제 파일(P0-02) — 원장·authoritative_remeasure.json 무접촉. 등급은 재채점하지 않는다(stored = 저장값 병기).")
  tmp <- tempfile(pattern = ".essence_diag_", tmpdir = dirname(out), fileext = ".tmp")
  jsonlite::write_json(rec, tmp, auto_unbox = TRUE, pretty = TRUE, digits = NA, na = "null", null = "null")
  # file.rename = 같은 볼륨 원자 교체(Windows 에서도 기존 파일을 덮는다 — 2026-09-24 실측). 선삭제하지 않는다.
  if (!file.rename(tmp, out)) { unlink(tmp); stop("[rf_essence_diag_backfill] 원자 교체 실패: ", out) }
  invisible(rec)
}

#' 종합: 스펙에 지식 블록을 붙이고 요약 문자열을 돌려준다
rf_preflight <- function(spec, base_id) {
  kw <- rf_preflight_keywords(spec)
  dead <- rf_preflight_dead(kw)
  les <- rf_preflight_lessons(base_id)
  axs <- rf_preflight_axioms()
  spec$preflight <- list(
    keywords = kw, dead_precedents = dead, recent_attempts = les,
    axioms = axs, axiom_injected = length(axs) > 0L,
    note = paste("★차단하지 않는다 — 죽은 선례는 사실 기록이지 금지 목록이 아니다(AX-000).",
                 "실행은 진행하고 기록만 남긴다. 같은 구성이 반복되면 이 블록이 그 사실을 드러낸다."),
    axiom_injection = paste("무인 러너는 에이전트를 스폰하지 않아 axiom_context_inject(PreToolUse[Agent])가",
                            "발화하지 않는다. 그래서 ★레인이 직접 active 공리를 읽어 이 블록에 넣는다",
                            sprintf("(적재 %d건).", length(axs)),
                            "고정 축은 엔진·계약이 강제하고, 실행 후 rf_preflight_verify_axes() 가",
                            "산출물에서 재도출해 확인한다."))
  spec
}
