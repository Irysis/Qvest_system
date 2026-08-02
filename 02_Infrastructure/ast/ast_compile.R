#==============================================================================
# ast_compile.R — AST v1.1: AST JSON → R 실행 계획 (연산자 라이브러리 𝒪 실행기)
#
# SOT   : 02_Infrastructure/docs/qvest_ast_v1_1_sot.md §2(𝒪) · §4-2(컴파일러-소유 AS_OF)
# 라이브러리: 02_Infrastructure/ast/operator_library.json
#
# 설계 핵심 (SOT §4 3중 구조 예방의 ②):
#   1) 리프 로드는 컴파일러 소유 — factor DB 리프 = load_month_factors /
#      load_daily_factors 경유(C15), RAWDATA 컬럼 리프 = load_rawdata 경유.
#      조인·시점 정렬은 AS_OF 규율로 컴파일러가 생성 (수기 merge 금지 —
#      백테 = 배포 단일 경로).
#   2) 연산자당 R 함수 1 (data.table). 횡단면 = by=Date, 시계열 = by=Ticker
#      (setorder(Ticker, Date) 순서 보장).
#   3) 산출 = (Date, Ticker, value) 표준 신호 패널 + compile manifest
#      (리프 목록 · 연산자 카운트 · ast_features — Phase 2 로깅 소재).
#
# 내부 패널 계약: (Date, Ticker, value, avail_ts)
#   avail_ts = 해당 행이 의사결정에 사용 가능해지는 최초 시각.
#   불변식 INV-AVAIL: avail_ts >= Date — 리프에서 강제(.mk_panel)하고 모든
#   연산자가 보존한다(연산자는 avail_ts 를 감소시키지 않음). 이 불변식 덕에
#   최종 AS_OF 조인(avail_ts <= eval_date)이 미래 Date 행을 절대 선택하지 않는다.
#
#   TS 연산자의 avail_ts = emission-time 의미론: 행 t 의 파생 신호는
#   max(행 자신의 avail_ts, 재료 avail_ts) 에 방출된다. 재료 시각만 쓰면
#   TS_LAG(x,1) 의 t+1 행(값=x_t, 재료가용=t)이 eval=t 에 매칭되어 lag 이
#   소거되는 look-ahead 등가 버그가 생긴다 — 본 컴파일러는 이를 pmax 로 차단.
#
# 경계 (backtest-contract / python-policy 정합):
#   본 컴파일러는 팩터 신호 계산까지만. 포트폴리오 수익 구성은 기존 계약
#   (canonical_screen_bt / build_bt_result / Return.portfolio) 불변 — 자체합성 금지.
#   출력 (Date,Ticker,value) 는 canonical_screen_bt(scores_dt) 의
#   (Date,Ticker,score) 로 직결된다.
#
# 작성: 2026-07-25 (AST v1.1 Step 2 — S2b)
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(jsonlite)
})

.AST_COMPILER_VERSION <- "1.1.0"

`%||%` <- function(a, b) if (is.null(a)) b else a

#------------------------------------------------------------------------------
# 0. 경로/라이브러리 로드
#------------------------------------------------------------------------------

.ast_root <- function() {
  r <- Sys.getenv("QM_ROOT", "")
  if (nzchar(r) && dir.exists(r)) return(gsub("\\\\", "/", r))
  fb <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
  if (dir.exists(fb)) return(fb)
  stop("[ast_compile] project root 미해결 — QM_ROOT env 설정 필요")
}

AST_LIB_PATH_DEFAULT <- file.path(.ast_root(), "02_Infrastructure/ast/operator_library.json")

ast_load_library <- function(path = AST_LIB_PATH_DEFAULT) {
  if (!file.exists(path)) {
    stop("[ast_compile] operator_library.json 부재: ", path)
  }
  lib <- jsonlite::fromJSON(path, simplifyVector = FALSE)
  attr(lib, "md5") <- unname(tools::md5sum(path))
  attr(lib, "path") <- path
  lib
}

#------------------------------------------------------------------------------
# 1. 패널 헬퍼 (내부 계약: Date, Ticker, value, avail_ts)
#------------------------------------------------------------------------------

.assert_panel <- function(dt, label = "panel") {
  if (!is.data.table(dt)) stop(sprintf("[ast_compile] %s: data.table 아님", label))
  need <- c("Date", "Ticker", "value", "avail_ts")
  miss <- setdiff(need, names(dt))
  if (length(miss)) {
    stop(sprintf("[ast_compile] %s: 패널 필수 컬럼 누락 — %s", label, paste(miss, collapse = ", ")))
  }
  invisible(dt)
}

# 리프 원시 로드 → 내부 패널 정규화.
#  - avail_ts 부재 시 Date + avail_offset_days 로 생성 (offset >= 0 강제).
#  - INV-AVAIL(avail_ts >= Date) + (Date,Ticker) 유일성 하드 검증.
.mk_panel <- function(dt, avail_offset_days = 0L, label = "leaf") {
  dt <- as.data.table(copy(dt))
  miss <- setdiff(c("Date", "Ticker", "value"), names(dt))
  if (length(miss)) {
    stop(sprintf("[ast_compile] %s: 리프 패널 필수 컬럼 누락 — %s", label, paste(miss, collapse = ", ")))
  }
  dt[, Date := as.Date(Date)]
  off <- as.integer(avail_offset_days)
  if (is.na(off) || off < 0L) {
    stop(sprintf("[ast_compile] %s: avail_offset_days 는 0 이상 정수 (음수 = lead 등가 거부)", label))
  }
  if (!"avail_ts" %in% names(dt)) dt[, avail_ts := Date + off]
  dt[, avail_ts := as.Date(avail_ts)]
  if (anyNA(dt$avail_ts)) {
    stop(sprintf("[ast_compile] %s: avail_ts NA 존재 — 가용시각 미선언 리프 거부", label))
  }
  if (dt[avail_ts < Date, .N] > 0L) {
    stop(sprintf(
      "[ast_compile] %s: avail_ts < Date 관측 존재 — 관측일보다 이른 가용시각은 라벨 방향 오류(미래참조 방향) 거부",
      label))
  }
  if (anyDuplicated(dt, by = c("Date", "Ticker")) > 0L) {
    stop(sprintf("[ast_compile] %s: (Date,Ticker) 중복 — 패널 불변식 위반", label))
  }
  setorder(dt, Ticker, Date)
  dt[, .(Date, Ticker, value, avail_ts)]
}

.join_staleness <- function() getOption("qvest.ast.join_staleness_days", NULL)

# ── 컴파일러-소유 AS_OF 조인 (SOT §4-2 — 회수의 본체) ─────────────────────────
# grid (Ticker, Date=eval_date) 의 각 셀에 대해 avail_ts <= eval_date 인 관측 중
# 가장 늦게 가용해진 것(LOCF)을 취한다. 매칭 없음 → NA (미래 채움 없음).
# staleness_days 지정 시 eval_date − avail_ts > staleness → NA (무한 LOCF 차단).
.as_of_join <- function(p, grid, staleness_days = NULL) {
  .assert_panel(p, "as_of_join input")
  if (p[avail_ts < Date, .N] > 0L) {
    stop("[ast_compile] as_of_join: INV-AVAIL 위반 패널 (avail_ts < Date)")
  }
  g <- unique(as.data.table(grid)[, .(Ticker, eval_date = as.Date(Date))])
  b <- p[, .(Ticker, join_ts = avail_ts, obs_date = Date, obs_avail = avail_ts, obs_value = value)]
  setorder(b, Ticker, join_ts, obs_date)
  hit <- b[g, on = .(Ticker, join_ts <= eval_date),
           .(value = obs_value[.N], avail_src = obs_avail[.N]),
           by = .EACHI]
  # 비등가 조인 출력의 x 조인컬럼(join_ts)은 i(eval_date) 값을 담는다.
  if ("join_ts" %in% names(hit)) {
    setnames(hit, "join_ts", "Date")
  } else if ("eval_date" %in% names(hit)) {
    setnames(hit, "eval_date", "Date")
  } else stop("[ast_compile] as_of_join: 조인 컬럼 해석 실패 (data.table 버전 확인)")
  hit[, Date := as.Date(Date)]
  hit[, avail_src := as.Date(avail_src)]
  # 매칭 0건 셀은 by=.EACHI 에서 드롭될 수 있음 — 전체 grid 로 재병합해 NA 복원
  full <- g[, .(Date = eval_date, Ticker)]
  hit <- merge(full, hit, by = c("Date", "Ticker"), all.x = TRUE)
  if (!is.null(staleness_days)) {
    hit[!is.na(value) & as.numeric(Date - avail_src) > staleness_days, value := NA]
  }
  hit[, .(Date, Ticker, value, avail_src)]
}

# 이항 정렬: 결과 그리드 = a(좌측 피연산자) 그리드. b 는 AS_OF LOCF.
# 반환: Date, Ticker, a_value, b_value, a_avail, b_avail, avail_ts(=보수 max)
.align2 <- function(a, b, staleness_days = .join_staleness()) {
  .assert_panel(a, "align2.a"); .assert_panel(b, "align2.b")
  bj <- .as_of_join(b, a[, .(Date, Ticker)], staleness_days)
  m <- merge(a[, .(Date, Ticker, a_value = value, a_avail = avail_ts)],
             bj[, .(Date, Ticker, b_value = value, b_avail = avail_src)],
             by = c("Date", "Ticker"), all.x = TRUE)
  m[, avail_ts := {
    av <- a_avail
    w <- !is.na(b_avail)
    av[w] <- pmax(a_avail[w], b_avail[w])
    av
  }]
  setorder(m, Ticker, Date)
  m
}

# TS 창 연산의 보수 avail: max(자기 avail, 창 내 rolling max avail)
.roll_avail <- function(av, w) {
  rm_ <- frollapply(as.numeric(av), w, max)
  rm_ <- as.Date(rm_, origin = "1970-01-01")
  fifelse(is.na(rm_), av, pmax(av, rm_))
}

#------------------------------------------------------------------------------
# 2. 연산자 구현 — 연산자당 R 함수 1 (data.table)
#    횡단면: by=Date / 시계열: by=Ticker + setorder(Ticker, Date) 순서 보장
#------------------------------------------------------------------------------

## ── 횡단면 ──────────────────────────────────────────────────────────────────

op_cs_rank <- function(x) {
  x <- copy(x)
  x[, c("value", "avail_ts") := {
    v <- value; ok <- !is.na(v); n <- sum(ok)
    out <- rep(NA_real_, .N)
    if (n == 1L) out[ok] <- 0.5
    if (n >= 2L) out[ok] <- (frank(v[ok], ties.method = "average") - 1) / (n - 1)
    av <- avail_ts
    if (n >= 1L) av[ok] <- max(avail_ts[ok])   # 횡단면 재료 전파: 참여 행 max
    list(out, av)
  }, by = Date]
  x[]
}

op_cs_zscore <- function(x) {
  x <- copy(x)
  x[, c("value", "avail_ts") := {
    v <- value; ok <- !is.na(v); n <- sum(ok)
    out <- rep(NA_real_, .N)
    if (n >= 2L) {
      s <- sd(v[ok])
      if (is.finite(s) && s > 0) out[ok] <- (v[ok] - mean(v[ok])) / s
    }
    av <- avail_ts
    if (n >= 1L) av[ok] <- max(avail_ts[ok])
    list(out, av)
  }, by = Date]
  x[]
}

op_cs_winsorize <- function(x, p) {
  x <- copy(x)
  x[, c("value", "avail_ts") := {
    v <- value; ok <- !is.na(v); n <- sum(ok)
    if (n >= 2L) {
      q <- quantile(v[ok], c(p, 1 - p), names = FALSE, type = 7)
      v[ok] <- pmin(pmax(v[ok], q[1]), q[2])
    }
    av <- avail_ts
    if (n >= 1L) av[ok] <- max(avail_ts[ok])
    list(v, av)
  }, by = Date]
  x[]
}

op_cs_demean <- function(x) {
  x <- copy(x)
  x[, c("value", "avail_ts") := {
    v <- value; ok <- !is.na(v); n <- sum(ok)
    out <- rep(NA_real_, .N)
    if (n >= 1L) out[ok] <- v[ok] - mean(v[ok])
    av <- avail_ts
    if (n >= 1L) av[ok] <- max(avail_ts[ok])
    list(out, av)
  }, by = Date]
  x[]
}

# group 패널(범주형 value)을 x 그리드에 AS_OF 정렬 후 (Date, group) demean.
op_cs_neutralize <- function(x, g) {
  m <- .align2(x, g)
  m[is.na(b_value), a_value := NA]
  m[, c("a_value", "avail_ts") := {
    v <- a_value; ok <- !is.na(v)
    out <- v
    if (any(ok)) out[ok] <- v[ok] - mean(v[ok])
    av <- avail_ts
    if (any(ok)) av[ok] <- max(avail_ts[ok])
    list(out, av)
  }, by = .(Date, b_value)]
  out <- m[, .(Date, Ticker, value = a_value, avail_ts)]
  setorder(out, Ticker, Date)
  out[]
}

## ── 시계열 ──────────────────────────────────────────────────────────────────

op_ts_lag <- function(x, k) {
  x <- copy(x); setorder(x, Ticker, Date)
  x[, c("value", "avail_ts") := {
    sv <- shift(value, k, type = "lag")
    sa <- shift(avail_ts, k, type = "lag")
    # emission-time: 재료 avail 만 쓰면 t+k 행이 eval=t 에 조기 매칭되어 lag 소거.
    av <- fifelse(is.na(sa), avail_ts, pmax(avail_ts, sa))
    list(sv, av)
  }, by = Ticker]
  x[]
}

op_ts_delta <- function(x, k) {
  x <- copy(x); setorder(x, Ticker, Date)
  x[, c("value", "avail_ts") := {
    sv <- shift(value, k, type = "lag")
    sa <- shift(avail_ts, k, type = "lag")
    av <- fifelse(is.na(sa), avail_ts, pmax(avail_ts, sa))
    list(value - sv, av)
  }, by = Ticker]
  x[]
}

op_ts_mean <- function(x, w) {
  x <- copy(x); setorder(x, Ticker, Date)
  x[, `:=`(value = frollmean(value, w),
           avail_ts = .roll_avail(avail_ts, w)), by = Ticker]
  x[]
}

op_ts_std <- function(x, w) {
  x <- copy(x); setorder(x, Ticker, Date)
  x[, `:=`(value = frollapply(value, w, sd),
           avail_ts = .roll_avail(avail_ts, w)), by = Ticker]
  x[]
}

op_ts_rank <- function(x, w) {
  x <- copy(x); setorder(x, Ticker, Date)
  fr <- function(vw) {
    if (anyNA(vw)) return(NA_real_)
    n <- length(vw)
    if (n == 1L) return(0.5)
    (sum(vw < vw[n]) + 0.5 * (sum(vw == vw[n]) - 1)) / (n - 1)
  }
  x[, `:=`(value = frollapply(value, w, fr),
           avail_ts = .roll_avail(avail_ts, w)), by = Ticker]
  x[]
}

op_ts_min <- function(x, w) {
  x <- copy(x); setorder(x, Ticker, Date)
  x[, `:=`(value = frollapply(value, w, min),
           avail_ts = .roll_avail(avail_ts, w)), by = Ticker]
  x[]
}

op_ts_max <- function(x, w) {
  x <- copy(x); setorder(x, Ticker, Date)
  x[, `:=`(value = frollapply(value, w, max),
           avail_ts = .roll_avail(avail_ts, w)), by = Ticker]
  x[]
}

op_ts_sum <- function(x, w) {
  x <- copy(x); setorder(x, Ticker, Date)
  x[, `:=`(value = frollsum(value, w),
           avail_ts = .roll_avail(avail_ts, w)), by = Ticker]
  x[]
}

# y 를 x 그리드에 AS_OF 정렬 후 롤링 cor/beta. (성능 백로그: frollapply-급 순수 R 루프)
.ts_pairroll <- function(x, y, w, f2) {
  m <- .align2(x, y)
  setorder(m, Ticker, Date)
  m[, value := {
    va <- a_value; vb <- b_value; n <- .N
    out <- rep(NA_real_, n)
    if (n >= w) {
      for (i in w:n) {
        sa <- va[(i - w + 1L):i]; sb <- vb[(i - w + 1L):i]
        if (!anyNA(sa) && !anyNA(sb)) out[i] <- f2(sa, sb)
      }
    }
    out
  }, by = Ticker]
  m[, avail_ts := .roll_avail(avail_ts, w), by = Ticker]
  out <- m[, .(Date, Ticker, value, avail_ts)]
  setorder(out, Ticker, Date)
  out[]
}

op_ts_corr <- function(x, y, w) {
  .ts_pairroll(x, y, w, function(sa, sb) {
    da <- sd(sa); db <- sd(sb)
    if (is.finite(da) && da > 0 && is.finite(db) && db > 0) cor(sa, sb) else NA_real_
  })
}

# TS_BETA(x, y, w) = 회귀 x ~ y 기울기 = cov(x,y)/var(y)
op_ts_beta <- function(x, y, w) {
  .ts_pairroll(x, y, w, function(sa, sb) {
    vy <- var(sb)
    if (is.finite(vy) && vy > 0) cov(sa, sb) / vy else NA_real_
  })
}

## ── 산술 ────────────────────────────────────────────────────────────────────

# e1/e2: list(kind = "panel"|"const", value = ...)
.arith2 <- function(e1, e2, f) {
  if (e1$kind == "panel" && e2$kind == "panel") {
    m <- .align2(e1$value, e2$value)
    m[, value := f(a_value, b_value)]
    out <- m[, .(Date, Ticker, value, avail_ts)]
    setorder(out, Ticker, Date)
    return(out[])
  }
  if (e1$kind == "panel") {
    p <- copy(e1$value); p[, value := f(value, e2$value)]; return(p[])
  }
  if (e2$kind == "panel") {
    p <- copy(e2$value); p[, value := f(e1$value, value)]; return(p[])
  }
  stop("[ast_compile] 이항 연산 인자 전부 상수 — 검증 단계 누락")
}

op_div_fn <- function(eps) {
  force(eps)
  function(a, b) fifelse(is.na(a) | is.na(b) | abs(b) < eps, NA_real_, a / b)
}

.unary_math <- function(x, f) {
  p <- copy(x); p[, value := f(value)]; p[]
}

op_log  <- function(x) .unary_math(x, function(v) {
  out <- rep(NA_real_, length(v)); ok <- !is.na(v) & v > 0
  out[ok] <- log(v[ok]); out
})
op_abs  <- function(x) .unary_math(x, abs)
op_sign <- function(x) .unary_math(x, function(v) as.numeric(sign(v)))
op_sqrt <- function(x) .unary_math(x, function(v) {
  out <- rep(NA_real_, length(v)); ok <- !is.na(v) & v >= 0
  out[ok] <- sqrt(v[ok]); out
})

## ── 조건 (complexity_weight 2) ───────────────────────────────────────────────

op_clip <- function(x, lo, hi) {
  p <- copy(x); p[, value := pmin(pmax(value, lo), hi)]; p[]
}

# cond>0 = TRUE. 그리드 = cond 그리드, a/b 는 AS_OF 정렬. avail = 3자 보수 max.
op_if_else <- function(ec, ea, eb, staleness_days = .join_staleness()) {
  cp <- ec$value
  res <- cp[, .(Date, Ticker, c_value = value, c_avail = avail_ts)]
  bind_branch <- function(res, e, vnm, anm) {
    if (e$kind == "const") {
      res[, (vnm) := as.numeric(e$value)]
      res[, (anm) := as.Date(NA)]
    } else {
      j <- .as_of_join(e$value, res[, .(Date, Ticker)], staleness_days)
      setnames(j, c("value", "avail_src"), c(vnm, anm))
      res <- merge(res, j, by = c("Date", "Ticker"), all.x = TRUE)
    }
    res
  }
  res <- bind_branch(res, ea, "a_value", "a_avail")
  res <- bind_branch(res, eb, "b_value", "b_avail")
  res[, value := fifelse(is.na(c_value), NA_real_,
                         fifelse(c_value > 0, a_value, b_value))]
  res[, avail_ts := {
    av <- c_avail
    w <- !is.na(a_avail); av[w] <- pmax(av[w], a_avail[w])
    w <- !is.na(b_avail); av[w] <- pmax(av[w], b_avail[w])
    av
  }]
  out <- res[, .(Date, Ticker, value, avail_ts)]
  setorder(out, Ticker, Date)
  out[]
}

# 그리드 = x 그리드. cond>0 인 곳만 x, 나머지 NA.
op_where <- function(x, cond) {
  m <- .align2(x, cond)
  m[, value := fifelse(!is.na(b_value) & b_value > 0, a_value, NA_real_)]
  out <- m[, .(Date, Ticker, value, avail_ts)]
  setorder(out, Ticker, Date)
  out[]
}

#------------------------------------------------------------------------------
# 3. AST 분석 — 검증 + ast_features + 리프 목록 + 소요 히스토리 (단일 워크)
#------------------------------------------------------------------------------

.ESCAPE_CLASSES <- c("MODEL_SCORE", "STORED_SCORE", "LLM_SCORE", "SPECIAL_OP")
.CANONICAL_CLASSES <- c("FIELD", "FIELD_REGISTRY_PTR")

.leaf_id <- function(leaf) {
  paste(leaf$class %||% "FIELD", leaf$source %||% "", leaf$field %||% "",
        leaf$vintage %||% "", sep = "|")
}

.check_param <- function(opname, spec_p, params, path) {
  nm <- spec_p$name
  v <- params[[nm]]
  if (is.null(v)) {
    if (isTRUE(spec_p$required)) {
      stop(sprintf("[ast_validate] %s: %s 필수 파라미터 '%s' 누락", path, opname, nm))
    }
    return(invisible(NULL))
  }
  ty <- spec_p$type %||% "num"
  if (ty == "str") {
    if (!is.character(v) || length(v) != 1L || !nzchar(v)) {
      stop(sprintf("[ast_validate] %s: %s 파라미터 '%s' 는 비어있지 않은 문자열", path, opname, nm))
    }
    return(invisible(NULL))
  }
  if (!is.numeric(v) || length(v) != 1L || !is.finite(v)) {
    stop(sprintf("[ast_validate] %s: %s 파라미터 '%s' 는 단일 유한 수치", path, opname, nm))
  }
  if (ty == "int" && v != as.integer(v)) {
    stop(sprintf("[ast_validate] %s: %s 파라미터 '%s' 는 정수 (got %s)", path, opname, nm, v))
  }
  excl <- isTRUE(spec_p$exclusive)
  if (!is.null(spec_p$min)) {
    bad <- if (excl) v <= spec_p$min else v < spec_p$min
    if (bad) stop(sprintf("[ast_validate] %s: %s 파라미터 '%s'=%s < 허용 하한 %s%s (음수 lag/lead 등가 거부 포함)",
                          path, opname, nm, v, spec_p$min, if (excl) " (exclusive)" else ""))
  }
  if (!is.null(spec_p$max)) {
    bad <- if (excl) v >= spec_p$max else v > spec_p$max
    if (bad) stop(sprintf("[ast_validate] %s: %s 파라미터 '%s'=%s > 허용 상한 %s", path, opname, nm, v, spec_p$max))
  }
  invisible(NULL)
}

# 반환: list(leaves, op_counts, features, history)
.ast_analyze <- function(node, lib) {
  acc <- new.env(parent = emptyenv())
  acc$node_count <- 0L
  acc$max_depth <- 0L
  acc$free_param_count <- 0L
  acc$conditional_op_count <- 0L
  acc$windows <- numeric(0)
  acc$op_counts <- list()
  acc$leaves <- list()           # leaf_id -> leaf 메타
  acc$history <- list()          # leaf_id -> 소요 히스토리(주기 단위)
  acc$escape_types <- character(0)

  numeric_param_names <- c("window", "k", "p", "lo", "hi", "eps", "extra_lag_days")

  walk <- function(node, depth, hist_acc, path) {
    if (!is.list(node)) stop(sprintf("[ast_validate] %s: 노드는 list 여야 함", path))
    acc$node_count <- acc$node_count + 1L
    acc$max_depth <- max(acc$max_depth, depth)
    type <- node$type %||% stop(sprintf("[ast_validate] %s: type 필드 누락", path))

    if (identical(type, "const")) {
      v <- node$value
      if (!is.numeric(v) || length(v) != 1L || !is.finite(v)) {
        stop(sprintf("[ast_validate] %s: const value 는 단일 유한 수치", path))
      }
      acc$free_param_count <- acc$free_param_count + 1L
      return(invisible("const"))
    }

    if (identical(type, "leaf")) {
      cls <- node$class %||% "FIELD"
      if (!cls %in% c(.CANONICAL_CLASSES, .ESCAPE_CLASSES)) {
        stop(sprintf("[ast_validate] %s: 미지의 리프 class '%s'", path, cls))
      }
      fld <- node$field
      if (is.null(fld) || !is.character(fld) || !nzchar(fld)) {
        stop(sprintf("[ast_validate] %s: 리프 field 필수", path))
      }
      if (cls %in% .CANONICAL_CLASSES) {
        src <- node$source
        if (is.null(src) || is.null(lib$leaf_sources[[src]])) {
          stop(sprintf("[ast_validate] %s: canonical 리프 source 미등재 ('%s') — leaf_sources: %s",
                       path, src %||% "<NULL>", paste(names(lib$leaf_sources), collapse = ", ")))
        }
      } else {
        # escape 리프: 계약 필드 검증 (SOT §2 — 누락 = 컴파일 거부)
        esc <- lib$escape_leaves[[cls]]
        req <- vapply(esc$contract_fields_required, identity, character(1))
        ct <- node$contract %||% list()
        miss <- setdiff(req, names(ct))
        if (length(miss)) {
          stop(sprintf("[ast_validate] %s: escape 리프 %s 계약 필드 누락 — {%s}",
                       path, cls, paste(miss, collapse = ", ")))
        }
        acc$escape_types <- unique(c(acc$escape_types, cls))
      }
      id <- .leaf_id(node)
      if (is.null(acc$leaves[[id]])) {
        src_meta <- if (!is.null(node$source)) lib$leaf_sources[[node$source]] else NULL
        rp <- node$restatement_prone %||% (src_meta$restatement_prone_default %||% NA)
        acc$leaves[[id]] <- list(
          id = id, class = cls, source = node$source %||% NA_character_,
          field = fld, vintage = node$vintage %||% NA_character_,
          restatement_prone = rp
        )
      }
      acc$history[[id]] <- max(acc$history[[id]] %||% 0L, hist_acc)
      return(invisible("panel"))
    }

    if (!identical(type, "op")) {
      stop(sprintf("[ast_validate] %s: 미지의 노드 type '%s'", path, type))
    }

    opname <- toupper(node$op %||% stop(sprintf("[ast_validate] %s: op 필드 누락", path)))
    if (grepl("^(LEAD|FUTURE)", opname)) {
      stop(sprintf("[ast_validate] %s: '%s' — LEAD/FUTURE_* 부재 원칙 (SOT §2) 컴파일 거부", path, opname))
    }
    spec <- lib$operators[[opname]]
    if (is.null(spec)) {
      stop(sprintf("[ast_validate] %s: 연산자 '%s' 는 𝒪 밖 — 허용: %s",
                   path, opname, paste(names(lib$operators), collapse = ", ")))
    }
    acc$op_counts[[opname]] <- (acc$op_counts[[opname]] %||% 0L) + 1L
    if (identical(spec$class, "conditional")) {
      acc$conditional_op_count <- acc$conditional_op_count + 1L
    }

    args <- node$args %||% list()
    if (length(args) != spec$arity) {
      stop(sprintf("[ast_validate] %s: %s arity %d 요구, %d 공급", path, opname, spec$arity, length(args)))
    }

    params <- node$params %||% list()
    spec_pnames <- vapply(spec$params %||% list(), function(p) p$name, character(1))
    extra <- setdiff(names(params), spec_pnames)
    if (length(extra)) {
      stop(sprintf("[ast_validate] %s: %s 미선언 파라미터 {%s} — 오타 가드", path, opname, paste(extra, collapse = ", ")))
    }
    for (sp in spec$params %||% list()) .check_param(opname, sp, params, path)

    # free_param_count / window_variety
    for (nm in intersect(names(params), numeric_param_names)) {
      if (is.numeric(params[[nm]])) {
        acc$free_param_count <- acc$free_param_count + 1L
        if (nm == "window") acc$windows <- c(acc$windows, as.numeric(params[[nm]]))
      }
    }

    # 히스토리 전파 (주기 단위): TS_LAG/TS_DELTA += k, TS 창 += window − 1
    child_hist <- rep(hist_acc, length(args))
    if (opname %in% c("TS_LAG", "TS_DELTA")) {
      child_hist <- child_hist + as.integer(params$k)
    } else if (identical(spec$class, "time_series") && !is.null(params$window)) {
      child_hist <- child_hist + as.integer(params$window) - 1L
    }

    # VINTAGE: 직접 리프만
    if (opname == "VINTAGE") {
      ch <- args[[1]]
      if (!identical(ch$type %||% "", "leaf")) {
        stop(sprintf("[ast_validate] %s: VINTAGE 는 직접 리프만 감쌀 수 있음", path))
      }
    }

    kinds <- character(length(args))
    for (i in seq_along(args)) {
      kinds[i] <- walk(args[[i]], depth + 1L, child_hist[i], sprintf("%s/%s[%d]", path, opname, i))
    }

    # 인자 타입 검증: "panel"/"leaf_only" 자리에는 const 불가
    for (i in seq_along(args)) {
      aty <- spec$args[[i]]$type %||% "panel"
      if (aty %in% c("panel", "leaf_only") && kinds[i] == "const") {
        stop(sprintf("[ast_validate] %s: %s 인자 %d('%s')는 패널이어야 함 — const 불가",
                     path, opname, i, spec$args[[i]]$name %||% i))
      }
    }
    if (all(kinds == "const")) {
      stop(sprintf("[ast_validate] %s: %s 전 인자 상수 — AST 무의미 (상수 접기 금지)", path, opname))
    }
    invisible("panel")
  }

  root_kind <- walk(node, 1L, 0L, "root")
  if (identical(root_kind, "const")) {
    stop("[ast_validate] AST 루트가 상수 — 신호 패널을 산출하지 않음")
  }

  leaves <- unname(acc$leaves)
  rp_flags <- vapply(leaves, function(l) isTRUE(l$restatement_prone), logical(1))
  esc_cnt <- sum(vapply(leaves, function(l) l$class %in% .ESCAPE_CLASSES, logical(1)))
  canon <- Filter(function(l) l$class %in% .CANONICAL_CLASSES, leaves)
  distinct_fields <- unique(vapply(canon, function(l) paste(l$source, l$field, sep = "::"), character(1)))

  list(
    leaves = leaves,
    op_counts = acc$op_counts,
    history = acc$history,
    features = list(
      node_count = acc$node_count,
      max_depth = acc$max_depth,
      free_param_count = acc$free_param_count,
      distinct_field_count = length(distinct_fields),
      conditional_op_count = acc$conditional_op_count,
      window_variety = length(unique(acc$windows)),
      restatement_exposure = sum(rp_flags),
      escape_leaf_count = esc_cnt,
      escape_leaf_types = as.list(acc$escape_types)
    )
  )
}

# 게이트 훅(§7 ④)용 단독 검증 진입점 — 위반 시 stop, 통과 시 분석 결과 반환(invisible)
ast_validate <- function(ast, lib = ast_load_library()) {
  invisible(.ast_analyze(ast, lib))
}

ast_features <- function(ast, lib = ast_load_library()) {
  .ast_analyze(ast, lib)$features
}

#------------------------------------------------------------------------------
# 4. 평가기 (dispatcher)
#------------------------------------------------------------------------------

ast_eval <- function(node, lib, provider, ctx) {
  type <- node$type
  if (identical(type, "const")) {
    return(list(kind = "const", value = as.numeric(node$value)))
  }
  if (identical(type, "leaf")) {
    raw <- provider(node, ctx)
    cls <- node$class %||% "FIELD"
    src_meta <- if (!is.null(node$source)) lib$leaf_sources[[node$source]] else NULL
    off_default <- src_meta$avail_offset_days_default %||% 0L
    # STORED_SCORE: 가용시각 명시 의무 (암묵 0 금지 — 저장 패널 동월 look-ahead 재발 방지)
    if (identical(cls, "STORED_SCORE") && !"avail_ts" %in% names(as.data.table(raw))) {
      off_ct <- node$contract$avail_offset_days
      if (is.null(off_ct)) {
        stop(sprintf("[ast_compile] STORED_SCORE '%s': avail_ts 컬럼 또는 contract.avail_offset_days 명시 의무",
                     node$field))
      }
      off_default <- off_ct
    }
    off <- node$avail_offset_days %||% off_default
    p <- .mk_panel(raw, avail_offset_days = off, label = .leaf_id(node))
    if (nrow(p) == 0L) warning(sprintf("[ast_compile] 리프 %s: 0행 로드", .leaf_id(node)))
    if (!is.null(ctx$.rec)) ctx$.rec$rows[[.leaf_id(node)]] <- nrow(p)
    return(list(kind = "panel", value = p))
  }
  if (!identical(type, "op")) stop("[ast_compile] 미지의 노드 type: ", type %||% "<NULL>")

  op <- toupper(node$op)
  ps <- node$params %||% list()

  if (op == "VINTAGE") {
    child <- node$args[[1]]
    child$vintage <- ps$tag
    return(ast_eval(child, lib, provider, ctx))
  }
  if (op == "AS_OF") {
    r <- ast_eval(node$args[[1]], lib, provider, ctx)
    k <- as.integer(ps$extra_lag_days)
    p <- copy(r$value)
    p[, avail_ts := avail_ts + k]
    return(list(kind = "panel", value = p))
  }

  ev <- lapply(node$args, ast_eval, lib = lib, provider = provider, ctx = ctx)
  P <- function(i) ev[[i]]$value

  out <- switch(op,
    "CS_RANK"      = op_cs_rank(P(1)),
    "CS_ZSCORE"    = op_cs_zscore(P(1)),
    "CS_WINSORIZE" = op_cs_winsorize(P(1), as.numeric(ps$p)),
    "CS_NEUTRALIZE"= op_cs_neutralize(P(1), P(2)),
    "CS_DEMEAN"    = op_cs_demean(P(1)),
    "TS_LAG"       = op_ts_lag(P(1), as.integer(ps$k)),
    "TS_DELTA"     = op_ts_delta(P(1), as.integer(ps$k)),
    "TS_MEAN"      = op_ts_mean(P(1), as.integer(ps$window)),
    "TS_STD"       = op_ts_std(P(1), as.integer(ps$window)),
    "TS_RANK"      = op_ts_rank(P(1), as.integer(ps$window)),
    "TS_MIN"       = op_ts_min(P(1), as.integer(ps$window)),
    "TS_MAX"       = op_ts_max(P(1), as.integer(ps$window)),
    "TS_SUM"       = op_ts_sum(P(1), as.integer(ps$window)),
    "TS_CORR"      = op_ts_corr(P(1), P(2), as.integer(ps$window)),
    "TS_BETA"      = op_ts_beta(P(1), P(2), as.integer(ps$window)),
    "ADD"          = .arith2(ev[[1]], ev[[2]], `+`),
    "SUB"          = .arith2(ev[[1]], ev[[2]], `-`),
    "MUL"          = .arith2(ev[[1]], ev[[2]], `*`),
    "DIV"          = .arith2(ev[[1]], ev[[2]], op_div_fn(as.numeric(ps$eps %||% 1e-12))),
    "LOG"          = op_log(P(1)),
    "ABS"          = op_abs(P(1)),
    "SIGN"         = op_sign(P(1)),
    "SQRT"         = op_sqrt(P(1)),
    "CLIP"         = op_clip(P(1), as.numeric(ps$lo), as.numeric(ps$hi)),
    "IF_ELSE"      = op_if_else(ev[[1]], ev[[2]], ev[[3]]),
    "WHERE"        = op_where(P(1), P(2)),
    stop("[ast_compile] dispatcher 미구현 연산자: ", op)
  )
  list(kind = "panel", value = out)
}

#------------------------------------------------------------------------------
# 5. canonical 리프 provider — 리프 로드는 컴파일러 소유 (C15 / §7b)
#------------------------------------------------------------------------------

.ensure_infra <- local({
  done <- FALSE
  function() {
    if (done) return(invisible(TRUE))
    root <- .ast_root()
    if (!exists("PROJECT_ROOT", envir = globalenv())) {
      source(file.path(root, "02_Infrastructure/config.R"))
    }
    if (!exists("load_month_factors", mode = "function")) {
      source(file.path(root, "02_Infrastructure/factor_db/factor_db_connector.R"))
    }
    done <<- TRUE
    invisible(TRUE)
  }
})

# 소요 히스토리(주기) → 달력 버퍼 변환은 보수적으로: monthly = 주기*32일, daily = 주기*2+40일
ast_leaf_provider_canonical <- function() {
  raw_env <- new.env(parent = emptyenv())
  function(leaf, ctx) {
    cls <- leaf$class %||% "FIELD"
    src <- leaf$source %||% ""
    hist_p <- ctx$history_periods[[.leaf_id(leaf)]] %||%
              ctx$history_periods[[paste(cls, src, leaf$field, "", sep = "|")]] %||% 0L
    ed <- as.Date(ctx$eval_dates)

    if (cls %in% .ESCAPE_CLASSES && !identical(cls, "STORED_SCORE")) {
      stop(sprintf(
        "[ast_compile] canonical provider: escape 리프 %s 로드 미구현 — Phase 2 통합 에이전트 소관 (test provider 로 공급 가능)",
        cls))
    }

    if (identical(cls, "STORED_SCORE")) {
      path <- leaf$contract$path
      if (is.null(path)) stop("[ast_compile] STORED_SCORE: contract.path 필요 (canonical provider)")
      if (!file.exists(path)) path2 <- file.path(.ast_root(), path) else path2 <- path
      if (!file.exists(path2)) stop("[ast_compile] STORED_SCORE: 패널 파일 부재 — ", path)
      if (!requireNamespace("arrow", quietly = TRUE)) stop("[ast_compile] arrow 패키지 필요")
      dt <- as.data.table(arrow::read_parquet(path2))
      vc <- leaf$contract$value_col %||% leaf$field
      if (!vc %in% names(dt) && !"value" %in% names(dt)) {
        stop(sprintf("[ast_compile] STORED_SCORE '%s': 값 컬럼('%s' 또는 'value') 부재", leaf$field, vc))
      }
      if (!"value" %in% names(dt)) setnames(dt, vc, "value")
      return(dt)
    }

    if (identical(src, "factor_db_monthly")) {
      .ensure_infra()
      if (!is.null(leaf$vintage)) {
        stop("[ast_compile] factor_db_monthly: vintage 태그는 canonical provider 미지원 — pin_cache 스냅샷 경유 필요 (measurement-graduation §7). 침묵 무시 금지.")
      }
      first_m <- as.Date(cut(min(ed), "month"))
      first_need <- seq(first_m, by = "-1 month", length.out = hist_p + 1L)[hist_p + 1L]
      last_m <- as.Date(cut(max(ed), "month"))
      mseq <- seq(first_need, last_m, by = "month")
      # 요청 sig_date = 각 월 캘린더 말일. 파일 해석은 YYYYMM 만 쓰므로 월 선택에는
      # 영향 없고, 방향정렬(Usable_Date <= sig_date) 창만 정한다.
      req_dates <- seq(min(mseq), by = "month", length.out = length(mseq) + 1L)[-1] - 1L
      # ★ 행 라벨은 요청일이 아니라 커넥터가 보고한 **패널 as-of**(월 파일 Date =
      #   거래일 월말)를 쓴다. 캘린더 월말로 합성하면 eval 그리드(거래일 월말)보다
      #   늦은 라벨이 되어 AS_OF 조인이 전월 값을 당긴다 = 1개월 stale
      #   (실측 2026-08-02: 2004-12~2026-06 중 94/259 월 = 36.3% 가 거래말<캘린더말.
      #    WT_D20260802_009 probe_parity2.R 로 stale 방향 실증 — max|diff|=0 vs 전월값).
      #   lag 방향이라 look-ahead 는 아니나 신호가 한 달 낡아 측정이 감쇠한다.
      out <- vector("list", length(req_dates))
      asof_v <- rep(as.Date(NA), length(req_dates))
      dup_months <- character(0)
      for (i in seq_along(req_dates)) {
        lm <- tryCatch(
          load_month_factors(req_dates[i], factor_names = leaf$field),
          error = function(e) NULL)
        if (is.null(lm) || !nrow(lm)) next
        asof <- attr(lm, "factor_db_asof_date")
        # fail-closed: as-of 미보고 시 요청일로 되돌리지 않는다 (그 되돌림이 본 결함)
        if (is.null(asof) || length(asof) != 1L || is.na(asof)) {
          stop(sprintf(paste0("[ast_compile] factor_db_monthly '%s' @%s: 커넥터가 패널 as-of ",
                              "(attr factor_db_asof_date) 를 보고하지 않음 — 캘린더 월말 라벨 ",
                              "합성 금지(1개월 stale 재발). factor_db_connector.R v2.4+ 필요."),
                      leaf$field, format(req_dates[i])))
        }
        asof <- as.Date(asof)
        if (asof > req_dates[i]) {
          stop(sprintf(paste0("[ast_compile] factor_db_monthly '%s': 패널 as-of %s 가 요청 ",
                              "sig_date %s 보다 미래 — 미래 vintage 로드(look-ahead) 거부"),
                      leaf$field, format(asof), format(req_dates[i])))
        }
        # 월 파일 결손 시 커넥터가 closest-earlier 파일로 대체 → 같은 as-of 중복.
        # 중복 라벨은 (Date,Ticker) 불변식 위반이므로 최초 1건만 쓰고 결손을 알린다
        # (LOCF 는 AS_OF 조인이 담당 — 여기서 값을 복제해 신선한 척 하지 않는다).
        if (any(!is.na(asof_v) & asof_v == asof)) {
          dup_months <- c(dup_months, format(req_dates[i], "%Y-%m"))
          next
        }
        asof_v[i] <- asof
        out[[i]] <- data.table(Date = asof, Ticker = lm$Ticker,
                               value = lm$Z_Score_Aligned)
      }
      if (length(dup_months)) {
        warning(sprintf(paste0("[ast_compile] factor_db_monthly '%s': 월 DB 결손으로 ",
                               "이전 월 패널이 대체 반환된 월 %d건 (%s%s) — 해당 월은 AS_OF ",
                               "LOCF 로 이월됨. final_max_staleness_days 설정 권장."),
                        leaf$field, length(dup_months),
                        paste(head(dup_months, 6), collapse = ", "),
                        if (length(dup_months) > 6) " ..." else ""))
      }
      if (!is.null(ctx$.rec)) {
        ok <- !is.na(asof_v)
        ctx$.rec$asof[[.leaf_id(leaf)]] <- list(
          label_source = "connector_asof (factor_db Date column, 거래일 월말)",
          n_months = sum(ok),
          asof_first = if (any(ok)) format(min(asof_v[ok])) else NA_character_,
          asof_last  = if (any(ok)) format(max(asof_v[ok])) else NA_character_,
          n_asof_before_request = sum(ok & asof_v < req_dates),
          n_month_gap_fallback = length(dup_months)
        )
      }
      return(rbindlist(out[!vapply(out, is.null, logical(1))]))
    }

    if (identical(src, "factor_db_daily")) {
      .ensure_infra()
      if (!is.null(leaf$vintage)) {
        stop("[ast_compile] factor_db_daily: vintage 태그 canonical provider 미지원 — pin_cache 경유 필요.")
      }
      lo <- min(ed) - (hist_p * 2L + 40L)
      dt <- load_daily_factors(date_range = c(lo, max(ed)), factors = leaf$field,
                               align_direction = TRUE)
      setnames(dt, leaf$field, "value")
      return(dt[, .(Date, Ticker, value)])
    }

    if (identical(src, "rawdata")) {
      .ensure_infra()
      if (!exists("load_rawdata", mode = "function")) {
        source(file.path(.ast_root(), "02_Infrastructure/backtest_harness.R"))
      }
      if (is.null(raw_env$RAWDATA)) {
        rl <- load_rawdata(use_cache = TRUE)
        raw_env$RAWDATA <- rl$RAWDATA
      }
      RD <- raw_env$RAWDATA
      if (!leaf$field %in% names(RD)) {
        stop(sprintf("[ast_compile] rawdata 리프: 컬럼 '%s' 부재 (A1 스키마 확인)", leaf$field))
      }
      lo <- min(ed) - (hist_p * 2L + 40L)
      return(RD[Date >= lo & Date <= max(ed),
                .(Date, Ticker, value = get(leaf$field))])
    }

    stop(sprintf("[ast_compile] canonical provider: 미지의 리프 source '%s'", src))
  }
}

#------------------------------------------------------------------------------
# 6. 컴파일 진입점
#------------------------------------------------------------------------------

#' AST → (Date, Ticker, value) 표준 신호 패널 + compile manifest
#'
#' @param ast AST (R 리스트) 또는 JSON 파일 경로 또는 JSON 문자열
#' @param eval_dates 신호 평가일 그리드 (Date 벡터 — 예: 월말 sig_date 열)
#' @param universe 선택. (Date, Ticker) data.table — 지정 시 그 그리드로 산출.
#'                 NULL 이면 eval_dates x (표현식 패널 관측 Ticker 전체) CJ 그리드
#' @param provider 선택. 리프 provider 함수(leaf, ctx) — NULL 이면 canonical
#'                 (load_month_factors/load_daily_factors/load_rawdata 경유).
#'                 테스트용 합성 provider 주입 지점 (AS_OF 규율은 provider 무관 동일 적용)
#' @param join_max_staleness_days 이항/분기 AS_OF LOCF 신선도 상한 (NULL = 무제한)
#' @param final_max_staleness_days 최종 그리드 AS_OF LOCF 신선도 상한 (NULL = 무제한)
#' @param manifest_out 선택. manifest JSON 저장 경로
#' @return list(panel = data.table(Date, Ticker, value), manifest = list)
ast_compile <- function(ast, eval_dates, universe = NULL, provider = NULL,
                        lib_path = AST_LIB_PATH_DEFAULT,
                        join_max_staleness_days = NULL,
                        final_max_staleness_days = NULL,
                        manifest_out = NULL) {
  lib <- ast_load_library(lib_path)

  if (is.character(ast) && length(ast) == 1L) {
    ast <- if (file.exists(ast)) jsonlite::fromJSON(ast, simplifyVector = FALSE)
           else jsonlite::fromJSON(ast, simplifyVector = FALSE)
  }

  ana <- .ast_analyze(ast, lib)   # 검증 + features + 리프/히스토리 (위반 시 stop)

  if (is.null(provider)) provider <- ast_leaf_provider_canonical()
  rec <- new.env(parent = emptyenv()); rec$rows <- list(); rec$asof <- list()
  ctx <- list(eval_dates = as.Date(eval_dates),
              history_periods = ana$history,
              .rec = rec)

  old_opt <- options(qvest.ast.join_staleness_days = join_max_staleness_days)
  on.exit(options(old_opt), add = TRUE)

  res <- ast_eval(ast, lib, provider, ctx)
  if (!identical(res$kind, "panel")) stop("[ast_compile] AST 루트 평가 결과가 패널이 아님")
  p <- res$value

  grid <- if (!is.null(universe)) {
    u <- as.data.table(universe)
    stopifnot(all(c("Date", "Ticker") %in% names(u)))
    unique(u[, .(Date = as.Date(Date), Ticker)])
  } else {
    CJ(Date = as.Date(ctx$eval_dates), Ticker = unique(p$Ticker))
  }

  fin <- .as_of_join(p, grid, staleness_days = final_max_staleness_days)
  panel <- fin[, .(Date, Ticker, value)]
  setorder(panel, Date, Ticker)

  leaves_manifest <- lapply(ana$leaves, function(l) {
    c(l, list(required_history_periods = ana$history[[l$id]] %||% 0L,
              n_rows_loaded = rec$rows[[l$id]] %||% NA_integer_,
              # 라벨 출처 감사면 — 월간 팩터 리프의 Date 라벨이 커넥터 as-of 인지 확인용
              # (합성 캘린더 월말 = 1개월 stale 결함의 지문)
              asof_label = rec$asof[[l$id]] %||% NULL))
  })

  manifest <- list(
    compiler = list(
      name = "ast_compile.R", version = .AST_COMPILER_VERSION,
      compiled_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
      library_version = lib$`_meta`$version, library_md5 = attr(lib, "md5")
    ),
    leaves = leaves_manifest,
    operator_counts = ana$op_counts,
    ast_features = ana$features,
    as_of = list(
      condition = "avail_ts <= eval_date (컴파일러-소유 조인 — 수기 merge 없음)",
      join_max_staleness_days = join_max_staleness_days,
      final_max_staleness_days = final_max_staleness_days,
      n_eval_dates = length(unique(grid$Date)),
      n_tickers_grid = length(unique(grid$Ticker)),
      n_cells = nrow(panel),
      n_nonna = sum(!is.na(panel$value))
    ),
    boundary = "signal-only: 포트 수익 구성은 canonical_screen_bt/build_bt_result 경유 (자체합성 금지)"
  )

  if (!is.null(manifest_out)) {
    jsonlite::write_json(manifest, manifest_out, auto_unbox = TRUE, pretty = TRUE, null = "null")
  }

  list(panel = panel, manifest = manifest)
}
