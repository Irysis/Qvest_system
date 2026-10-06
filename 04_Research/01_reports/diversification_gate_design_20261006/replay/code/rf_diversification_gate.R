#==============================================================================
# rf_diversification_gate.R — 기저 분산성 관문 (강화 개시 판정 보조 · v0 2026-10-06)
#
# 설계 정본: 04_Research/01_reports/diversification_gate_design_20261006/README.md (도훈 결정 §8 반영판)
# 묻는 것: 신규 논문 충실구현 기저가 **이미 가진 B 이상 전략**과 같은 것인가(중복) · 겹치지 않는가(독창).
#   잣대 = 정본 벤치(KOSPI200 · .cache/benchmark.parquet) 대비 **월간 초과수익**. 원수익 상관은 롱온리 베타 때문에
#   전부 0.8~0.9 로 판별력이 없다.
#
# ★PIT: 여기 값은 **연구 자원 배분**(무엇을 강화할지)에만 쓴다. 셀 엔진·보유 결정으로 흘러가면 pit.md C1(D-E —
#   "슬리브를 전기간 상관으로 고르면 시점 t 보유를 미래 통계로 정한 것")이다. 출력 = 요청·원장 메타·보고서뿐.
#   분산 재료(diversifier) 판정을 2계층이 소비할 때는 as-of(결정 시점까지의 창)로 다시 재야 한다 — 이 파일의 전기간 값을
#   2계층 배합 입력으로 넘기지 말 것.
#
# 근거(수치·방법):
#   - 초과수익 상관으로 전략의 겹침을 잰다: Grinold & Kahn (2000) Active Portfolio Management, 2nd ed., ch.5(활성수익·IR)
#     https://www.mhprofessional.com/active-portfolio-management-a-quantitative-approach-for-producing-superior-returns-and-controlling-risk-9780070248823-usa
#   - 상관 기반 전략 군집으로 중복 시도를 센다: López de Prado & Lewis (2019) "Detection of false investment strategies using
#     unsupervised learning methods", Quantitative Finance 19(9) https://doi.org/10.1080/14697688.2019.1622311
#   - 생성(spanning) 회귀 — 기존 집합으로 설명되는 몫(R²)과 남는 절편(α): Huberman & Kandel (1987) "Mean-Variance Spanning",
#     Journal of Finance 42(4) https://doi.org/10.1111/j.1540-6261.1987.tb03917.x
#   - 생성 회귀의 설명 변수 선택 = BIC: Schwarz (1978) "Estimating the Dimension of a Model", Annals of Statistics 6(2)
#     https://doi.org/10.1214/aos/1176344136
#   - 공통 구간 ≥ 60개월(월간 회귀 계수 추정의 표준 창): Fama & MacBeth (1973) "Risk, Return, and Equilibrium: Empirical Tests",
#     Journal of Political Economy 81(3) https://doi.org/10.1086/260061
#   - 문턱 = 경험 분포 분위(하드코딩 대신 데이터 보정) — 분위 자체는 도훈 결정(설정 파일 calibration.q_*).
#
# 공개: rfd_cfg · rfd_bench_daily · rfd_read_series · rfd_monthly · rfd_members · rfd_pool · rfd_matrix
#       rfd_metrics · rfd_jaccard · rfd_calibrate · rfd_verdict · rfd_disposition · rfd_papers · rfd_related
# 요구: data.table · jsonlite · arrow(정본 벤치 parquet) · zoo(sim_result.rds)
# 검사: 08_Tests/reinforcement/test_rf_diversification_gate.R
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })

.rfd_or <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a
.rfd_chr <- function(x) { x <- as.character(unlist(.rfd_or(x, ""))); if (!length(x) || is.na(x[1])) "" else x[1] }
.rfd_num <- function(x) { x <- suppressWarnings(as.numeric(unlist(.rfd_or(x, NA_real_)))); if (!length(x)) NA_real_ else x[1] }
.rfd_time <- function(x) {
  s <- .rfd_chr(x)
  if (!nzchar(s)) return(as.POSIXct(NA))
  s <- sub("([+-][0-9]{2}):?([0-9]{2})$", "\\1\\2", s)
  t <- suppressWarnings(as.POSIXct(s, format = "%Y-%m-%dT%H:%M:%S%z", tz = "Asia/Seoul"))
  if (is.na(t)) t <- suppressWarnings(as.POSIXct(substr(s, 1, 19), format = "%Y-%m-%dT%H:%M:%S", tz = "Asia/Seoul"))
  t
}
.rfd_abs <- function(p, root) {
  p <- sub("/+$", "", gsub("\\", "/", .rfd_chr(p), fixed = TRUE))
  if (!nzchar(p)) return("")
  if (grepl("^[A-Za-z]:/", p) || startsWith(p, "/")) p else file.path(root, p)
}
.rfd_read_json <- function(p) tryCatch(jsonlite::fromJSON(p, simplifyVector = FALSE), error = function(e) NULL)

rfd_cfg <- function(root) {
  p <- Sys.getenv("RF_DIV_CFG", file.path(root, "06_Registry/rf_diversification_gate.json"))
  cfg <- .rfd_read_json(p)
  if (is.null(cfg)) stop("rf_diversification_gate: 설정 판독 불가 — ", p)
  cfg
}

# --- 계보 키 -------------------------------------------------------------------
# 결합은 논문 집합(setkey). 같은 논문을 하나라도 공유하면 '관련 계보' — 서로의 비교 대상에서 뺀다
# (결합은 구성 논문과 닮는 것이 당연하고, 같은 논문의 재측정은 중복 판정의 대상이 아니라 재측정 결정의 대상이다).
rfd_papers <- function(key) {
  key <- .rfd_chr(key)
  if (!nzchar(key)) return(character(0))
  if (startsWith(key, "combo:")) return(sort(unique(strsplit(sub("^combo:", "", key), "+", fixed = TRUE)[[1]])))
  key
}
rfd_related <- function(k1, k2) identical(.rfd_chr(k1), .rfd_chr(k2)) || length(intersect(rfd_papers(k1), rfd_papers(k2))) > 0L

# --- 계열 판독 -----------------------------------------------------------------
rfd_bench_daily <- function(root, cfg) {
  p <- .rfd_abs(.rfd_or(cfg$benchmark$path, ".cache/benchmark.parquet"), root)
  b <- data.table::as.data.table(arrow::read_parquet(p, col_select = c("Date", "BM_Ret")))
  data.table::setnames(b, c("date", "bm"))
  b[, date := as.Date(date)]
  b <- b[!is.na(bm)]
  data.table::setkey(b, date)
  attr(b, "rfd_path") <- p
  attr(b, "rfd_mtime") <- format(file.info(p)$mtime, "%Y-%m-%dT%H:%M:%S%z")
  b
}

# 유니버스 동일가중 월수익 ew — 동일가중 롱온리 전략이 공유하는 '동일가중 − 시총가중'(사이즈) 성분을 빼기 위한 두 번째 요인.
#   ew = (200·KOSPI200 동일가중 + 150·KOSDAQ150 동일가중)/350 (일간 · 유니버스 K200∪KQ150 구성 종목 수 비례) → 월 복리.
#   원천 = .cache/indices.parquet(kospi200_ew 2009-01~ · kosdaq150_ew 2010-01~) — 두 지수가 다 있는 날만 쓴다(2010-01~).
rfd_factor_monthly <- function(root, cfg) {
  p <- .rfd_abs(.rfd_or(cfg$factors$path, ".cache/indices.parquet"), root)
  if (!file.exists(p)) return(NULL)
  x <- data.table::as.data.table(arrow::read_parquet(p, col_select = c("Date", "kospi200_ew", "kosdaq150_ew")))
  data.table::setorder(x, Date)
  x[, `:=`(r_k = kospi200_ew / data.table::shift(kospi200_ew) - 1, r_q = kosdaq150_ew / data.table::shift(kosdaq150_ew) - 1)]
  x <- x[is.finite(r_k) & is.finite(r_q)]
  x[, ew := (200 * r_k + 150 * r_q) / 350]
  m <- x[, .(ew = prod(1 + ew) - 1), by = .(ym = format(Date, "%Y-%m"))]
  data.table::setorder(m, ym)
  if (nrow(m) > 1L) m <- m[-1L]   # 첫 달 = 부분월
  m
}

# path = 03_period_returns.csv(daily|monthly · ret_net) 또는 sim_result.rds(strategy_xts · 일간 순수익)
rfd_read_series <- function(path) {
  if (!nzchar(path) || !file.exists(path)) return(NULL)
  if (grepl("\\.rds$", path, ignore.case = TRUE)) {
    # xts 이름공간을 올려야 index.xts 가 등록된다 — 안 올리면 zoo::index 가 초 단위 원시값을 내 as.Date 가 서기 289만 년을 만든다(실측)
    if (!requireNamespace("xts", quietly = TRUE)) return(NULL)
    s <- tryCatch(readRDS(path)$strategy_xts, error = function(e) NULL)
    if (is.null(s) || !NROW(s)) return(NULL)
    idx <- zoo::index(s)
    d <- if (inherits(idx, "POSIXct")) as.Date(format(idx, "%Y-%m-%d", tz = .rfd_or(attr(idx, "tzone"), "Asia/Seoul")))
         else as.Date(idx)
    dt <- data.table::data.table(date = d, ret = as.numeric(s[, 1]))
    return(list(freq = "daily", dt = dt[!is.na(ret) & !is.na(date)]))
  }
  x <- tryCatch(data.table::fread(path, select = c("date", "frequency", "ret_net"), showProgress = FALSE),
                error = function(e) NULL)
  if (is.null(x) || !nrow(x)) return(NULL)
  x[, date := as.Date(date)]
  list(freq = .rfd_chr(x$frequency[1]), dt = x[!is.na(ret_net), .(date, ret = ret_net)])
}

# 월간 원수익 r · 벤치 b · 초과 a = r − b. 월 = 수익이 실현된 캘린더 월.
#   일간 행: 수익일의 월.
#   월간 행: 행 일자 = 다음 리밸 일(보유월 다음 달 첫 거래일)에 **직전 보유월** 수익을 적는다 → 행 월의 앞 달.
#     실측(2026-10-06 BOOK_0001 output/03_period_returns.csv 272행): 앞 달로 붙이면 cor(r, 벤치) 0.699 · 같은 달이면 0.078.
# 가장자리 월(계열의 첫·마지막 캘린더 월)은 부분월이라 버린다 — 문턱 숫자 없이 정의로 자른다.
.rfd_prev_ym <- function(d) {
  y <- as.integer(format(d, "%Y")); m <- as.integer(format(d, "%m")) - 1L
  y[m == 0L] <- y[m == 0L] - 1L; m[m == 0L] <- 12L
  sprintf("%04d-%02d", y, m)
}
rfd_monthly <- function(ser, bm, fac = NULL) {
  if (is.null(ser) || !nrow(ser$dt)) return(NULL)
  bmm <- bm[, .(b = prod(1 + bm) - 1), by = .(ym = format(date, "%Y-%m"))]
  if (identical(ser$freq, "monthly")) {
    m <- ser$dt[, .(r = prod(1 + ret) - 1), by = .(ym = .rfd_prev_ym(date))]
    m <- merge(m, bmm, by = "ym")
  } else {
    d <- merge(ser$dt, bm, by = "date")
    if (!nrow(d)) return(NULL)
    m <- d[, .(r = prod(1 + ret) - 1, b = prod(1 + bm) - 1), by = .(ym = format(date, "%Y-%m"))]
  }
  data.table::setorder(m, ym)
  if (nrow(m) <= 2L) return(NULL)
  m <- m[-c(1L, nrow(m))]
  m[, a := r - b]
  # 잔차수익 e = r - beta*b (Grinold & Kahn 의 residual return). 초과수익 a = e + (beta - 1)*b 라서 베타가 다른 전략끼리는
  # (beta - 1)*b 항이 상관을 만든다 — 시장중립 롱숏 기저(beta~0)의 a ~ -b 가 beta<1 롱온리 칸과 '닮아' 보인다(재생 1판 실측).
  vb <- stats::var(m$b)
  beta <- if (is.finite(vb) && vb > 0) stats::cov(m$r, m$b) / vb else NA_real_
  m[, e := if (is.finite(beta)) r - beta * b else NA_real_]
  # 2요인 잔차 e2 = r − β1·b − β2·(ew − b) — 시장 + 사이즈(동일가중 − 시총가중) 성분 제거. ew 없는 달은 NA.
  m[, e2 := NA_real_]
  if (!is.null(fac)) {
    m <- merge(m, fac, by = "ym", all.x = TRUE, sort = TRUE)
    ok <- is.finite(m$ew)
    if (sum(ok) > 3L) {
      sz <- m$ew - m$b
      f <- tryCatch(stats::lm.fit(cbind(1, m$b[ok], sz[ok]), m$r[ok]), error = function(e) NULL)
      if (!is.null(f) && all(is.finite(f$coefficients[2:3]))) m[ok, e2 := r - f$coefficients[2] * b - f$coefficients[3] * (ew - b)]
    }
    m[, ew := NULL]
  }
  out <- m[, .(ym, r, a, e, e2)]
  attr(out, "rfd_beta") <- beta
  out
}

# 산출물 디렉터리 → 계열 경로: close_t1 재측정판(측정 체제 정본)이 있으면 그것, 없으면 최상위(신판 = 원래 close_t1).
.rfd_series_in_dir <- function(dir, remeasure_json = "") {
  if (nzchar(remeasure_json) && file.exists(remeasure_json)) {
    p <- file.path(dirname(remeasure_json), "03_period_returns.csv")
    if (file.exists(p)) return(list(path = p, exec = "close_t1_remeasure", auth = remeasure_json))
  }
  if (!nzchar(dir) || !dir.exists(dir)) return(NULL)
  rm <- list.files(dir, pattern = "^remeasure_close_t1_", full.names = TRUE)
  rm <- rm[file.exists(file.path(rm, "03_period_returns.csv"))]
  if (length(rm)) {
    rm <- rm[order(file.info(rm)$mtime, decreasing = TRUE)][1]
    return(list(path = file.path(rm, "03_period_returns.csv"), exec = "close_t1_remeasure",
                auth = file.path(rm, "authoritative_remeasure.json")))
  }
  p <- file.path(dir, "03_period_returns.csv")
  if (file.exists(p)) return(list(path = p, exec = "native", auth = file.path(dir, "authoritative_remeasure.json")))
  NULL
}
.rfd_auth_grade <- function(auth) {
  A <- if (nzchar(auth) && file.exists(auth)) .rfd_read_json(auth) else NULL
  if (is.null(A)) return(list(grade = NA_character_, port_t = NA_real_, rescued = NA))
  list(grade = .rfd_chr(A$essence_grade), port_t = .rfd_num(A$essence$portfolio_alpha_t_nw_lag3),
       rescued = isTRUE(A$recent_regime_rescued))
}
.rfd_flags <- function(fl) {
  fl <- .rfd_or(fl, list())
  v <- vapply(fl, function(z) if (identical(.rfd_chr(z$verdict), "consumed")) .rfd_chr(z$flag) else "", "")
  paste(sort(unique(v[nzchar(v)])), collapse = ";")
}

# --- 구성원 열거 ----------------------------------------------------------------
# 원장 L1 (기저 + 칸) · 모듈 카탈로그(원장 밖 B 이상 — 구 QEPM A 이관 · 6월 alpha_search) · BOOK.
# 등급 = 현재 권위 등급(칸 = 원장 attempt$grade — 09-25 close_t1 rebase 반영 · 기저·카탈로그 = essence_grade).
# 한 계열 파일은 한 번만(승격 자식의 기저 = 부모 승자 칸과 같은 디렉터리) — 칸 기록을 우선한다(등급이 원장에 있다).
rfd_members <- function(root, cfg) {
  rows <- list()
  add <- function(...) rows[[length(rows) + 1L]] <<- data.table::data.table(...)
  L <- .rfd_read_json(file.path(root, "06_Registry/reinforce_ledger_l1.json"))
  for (e in .rfd_or(L$entries, list())) {
    pk <- .rfd_chr(e$paper_key)
    axis_ok <- !identical(e$axis_valid, FALSE)
    for (a in .rfd_or(e$attempts, list())) {
      art <- .rfd_abs(a$artifacts, root)
      if (!nzchar(art)) next
      s <- .rfd_series_in_dir(art, .rfd_abs(a$measurement_regime$remeasure_path, root))
      if (is.null(s)) next
      add(member_id = basename(sub("/$", "", art)), kind = "cell", lineage = pk, entry_id = .rfd_chr(e$base_id),
          cell = .rfd_chr(.rfd_or(a$cell_code, a$essence$cell_code)), grade = .rfd_chr(a$grade),
          port_t = .rfd_num(a$essence$port_t), calmar = .rfd_num(a$essence$calmar),
          available_at = .rfd_time(.rfd_or(a$closed_at, a$opened_at)), series = s$path, exec = s$exec,
          holdings = file.path(dirname(s$path), "04_holdings.csv"), flags = .rfd_flags(a$vintage_flags),
          axis_ok = axis_ok, rescued = NA)
    }
    base <- .rfd_abs(sub(" .*$", "", .rfd_chr(e$base_artifacts)), root)
    s <- .rfd_series_in_dir(base)
    if (!is.null(s)) {
      g <- .rfd_auth_grade(s$auth)
      add(member_id = basename(sub("/$", "", base)), kind = "base", lineage = pk, entry_id = .rfd_chr(e$base_id),
          cell = "", grade = .rfd_or(g$grade, .rfd_chr(e$base_grade)), port_t = g$port_t, calmar = NA_real_,
          available_at = .rfd_time(e$opened_at), series = s$path, exec = s$exec,
          holdings = file.path(dirname(s$path), "04_holdings.csv"), flags = .rfd_flags(e$base_vintage_flags),
          axis_ok = axis_ok, rescued = g$rescued)
    }
  }
  M <- .rfd_read_json(file.path(root, "06_Registry/module_performance.json"))$modules
  C <- .rfd_read_json(file.path(root, "06_Registry/module_catalog.json"))$modules
  ledger_dirs <- if (length(rows)) unique(vapply(rows, function(r) r$member_id, "")) else character(0)
  for (sid in names(.rfd_or(M, list()))) {
    m <- M[[sid]]
    g <- .rfd_chr(m$grade)
    if (!g %in% c("A", "B")) next
    cm <- .rfd_or(C[[sid]], list())
    art <- .rfd_chr(cm$meta$artifacts_dir)
    if (nzchar(art) && basename(sub("/$", "", art)) %in% ledger_dirs) next
    if (isTRUE(cm$grade_contaminated)) next
    p <- .rfd_abs(m$sim_result_path, root)
    pk <- .rfd_chr(cm$meta$paper_key)
    kind <- if (identical(.rfd_chr(m$trust_status), "legacy_qepm_grade_a")) "legacy_qepm" else "catalog"
    add(member_id = sid, kind = kind, lineage = if (nzchar(pk)) pk else paste0("module:", sid), entry_id = "",
        cell = "", grade = g, port_t = NA_real_, calmar = NA_real_,
        available_at = .rfd_time(cm$registered_at), series = p, exec = "sim_result",
        holdings = "", flags = "", axis_ok = TRUE, rescued = NA)
  }
  B <- .rfd_read_json(file.path(root, "06_Registry/book/book_registry.json"))
  for (b in .rfd_or(B$entries, list())) {
    cp <- .rfd_abs(b$code_path, root)
    p <- file.path(cp, "output/03_period_returns.csv")
    if (!file.exists(p)) next
    add(member_id = .rfd_chr(b$book_id), kind = "book", lineage = paste0("book:", .rfd_chr(b$book_id)), entry_id = "",
        cell = "", grade = .rfd_chr(b$grade), port_t = NA_real_, calmar = NA_real_,
        available_at = .rfd_time(b$registered_at), series = p, exec = "book_output",
        holdings = "", flags = "", axis_ok = TRUE, rescued = NA)
  }
  D <- data.table::rbindlist(rows, fill = TRUE)
  D[, kind_rank := match(kind, c("cell", "base", "catalog", "legacy_qepm", "book"))]
  data.table::setorder(D, series, kind_rank)
  D <- D[!duplicated(series)]
  D[, kind_rank := NULL]
  D[]
}

# 비교 풀: 현재 등급 B 이상 · (as_of 가 있으면) 그 시각 전에 측정된 것 · 무효 축 제외 · (선택) 표식 제외.
rfd_pool <- function(members, cfg, as_of = NULL, exclude_flags = NULL) {
  grades <- unlist(.rfd_or(cfg$pool$grades, list("A", "B")))
  ex <- if (is.null(exclude_flags)) unlist(.rfd_or(cfg$pool$exclude_vintage_flags, list())) else exclude_flags
  P <- members[grade %in% grades & axis_ok == TRUE]
  if (length(ex)) P <- P[!vapply(strsplit(flags, ";", fixed = TRUE), function(f) any(f %in% ex), logical(1))]
  if (!is.null(as_of)) P <- P[is.na(available_at) | available_at < as_of]
  P[]
}

# 월간 초과(a)·원(r) 행렬 — 행 = ym(합집합) · 열 = member_id
rfd_matrix <- function(monthly) {
  ids <- names(monthly)
  yms <- sort(unique(unlist(lapply(monthly, function(m) m$ym))))
  A <- matrix(NA_real_, length(yms), length(ids), dimnames = list(yms, ids))
  R <- A
  E <- A
  E2 <- A
  for (id in ids) {
    m <- monthly[[id]]
    i <- match(m$ym, yms)
    A[i, id] <- m$a
    R[i, id] <- m$r
    E[i, id] <- m$e
    if (!is.null(m$e2)) E2[i, id] <- m$e2
  }
  list(A = A, R = R, E = E, E2 = E2)
}

# --- 지표 ------------------------------------------------------------------------
.rfd_cor <- function(x, y) {
  ok <- !is.na(x) & !is.na(y)
  n <- sum(ok)
  if (n < 3L) return(c(rho = NA_real_, n = n))
  sx <- stats::sd(x[ok]); sy <- stats::sd(y[ok])
  if (!is.finite(sx) || !is.finite(sy) || sx == 0 || sy == 0) return(c(rho = NA_real_, n = n))
  c(rho = stats::cor(x[ok], y[ok]), n = n)
}

# 생성 회귀 — y(후보 초과) ~ X(계보별 최근접 구성원 초과) · 설명 변수 = BIC 전진 선택(Schwarz 1978)
.rfd_span <- function(y, X) {
  n <- length(y)
  bic <- function(cols) {
    rss <- if (!length(cols)) sum((y - mean(y))^2) else sum(stats::lm.fit(cbind(1, X[, cols, drop = FALSE]), y)$residuals^2)
    n * log(rss / n) + (length(cols) + 1) * log(n)
  }
  sel <- integer(0)
  cur <- bic(sel)
  repeat {
    rest <- setdiff(seq_len(ncol(X)), sel)
    if (!length(rest)) break
    b <- vapply(rest, function(j) bic(c(sel, j)), 0)
    if (min(b) >= cur) break
    sel <- c(sel, rest[which.min(b)])
    cur <- min(b)
  }
  if (!length(sel)) {
    t0 <- mean(y) / (stats::sd(y) / sqrt(n))
    return(list(r2 = 0, adj_r2 = 0, sel = character(0), alpha = mean(y), alpha_t = t0, n = n))
  }
  Z <- X[, sel, drop = FALSE]
  f <- stats::lm(y ~ Z)
  s <- summary(f)
  list(r2 = s$r.squared, adj_r2 = s$adj.r.squared, sel = colnames(X)[sel],
       alpha = unname(stats::coef(f)[1]), alpha_t = unname(stats::coef(s)[1, 3]), n = n)
}

# 후보(cand: rfd_monthly 결과) vs 풀 — cand_key 와 관련된 계보는 비교에서 뺀다.
# 반환: rho_max · 이웃(계보·구성원) · n_overlap · r2_span(adj) · alpha_span(t) · rho_down · capture_down · 풀 크기
rfd_metrics <- function(cand, cand_key, pool, mats, cfg, measure = NULL) {
  min_ov <- as.integer(.rfd_num(.rfd_or(cfg$series$min_overlap_months, 60)))
  measure <- .rfd_chr(.rfd_or(measure, .rfd_or(cfg$series$measure, "resid")))
  X <- switch(measure, active = mats$A, resid2 = mats$E2, mats$E)
  ycol <- switch(measure, active = "a", resid2 = "e2", "e")
  out <- list(n_pool_members = 0L, n_pool_lineages = 0L, rho_max = NA_real_, neighbor_lineage = "", neighbor_member = "",
              n_overlap = 0L, r2_span = NA_real_, r2_span_raw = NA_real_, span_sel = "", alpha_span = NA_real_,
              alpha_span_t = NA_real_, n_span = 0L, rho_down = NA_real_, capture_down = NA_real_, n_down = 0L,
              status = "insufficient")
  if (is.null(cand) || !nrow(cand)) { out$status <- "candidate_series_missing"; return(out) }
  P <- pool[!vapply(lineage, function(l) rfd_related(l, cand_key), logical(1))]
  P <- P[member_id %in% colnames(X)]
  out$n_pool_members <- nrow(P)
  out$n_pool_lineages <- data.table::uniqueN(P$lineage)
  if (!nrow(P)) { out$status <- "pool_empty"; return(out) }
  yms <- rownames(X)
  y <- rep(NA_real_, length(yms)); y[match(cand$ym, yms)] <- cand[[ycol]]
  yr <- rep(NA_real_, length(yms)); yr[match(cand$ym, yms)] <- cand$r
  cr <- t(vapply(P$member_id, function(id) .rfd_cor(y, X[, id]), c(rho = 0, n = 0)))
  P[, `:=`(rho = cr[, "rho"], n_ov = as.integer(cr[, "n"]))]
  Q <- P[n_ov >= min_ov & !is.na(rho)]
  if (!nrow(Q)) { out$status <- "overlap_short"; return(out) }
  data.table::setorder(Q, -rho)
  best <- Q[!duplicated(lineage)]                       # 계보별 최근접 구성원
  out$rho_max <- best$rho[1]
  out$neighbor_lineage <- best$lineage[1]
  out$neighbor_member <- best$member_id[1]
  out$n_overlap <- best$n_ov[1]
  # 생성 회귀 창: 후보 ∩ (공통 구간이 min_ov 이상인 계보 대표들) — 창이 min_ov 미만이면 가장 짧은 대표부터 뺀다
  reps <- best$member_id
  win <- function(ids) { ok <- !is.na(y); for (id in ids) ok <- ok & !is.na(X[, id]); ok }
  w <- win(reps)
  while (sum(w) < min_ov && length(reps) > 1L) {
    cov <- vapply(reps, function(id) sum(!is.na(y) & !is.na(X[, id])), 0)
    reps <- reps[-which.min(cov)]
    w <- win(reps)
  }
  if (sum(w) >= min_ov) {
    sp <- .rfd_span(y[w], X[w, reps, drop = FALSE])
    out$r2_span <- sp$adj_r2
    out$r2_span_raw <- sp$r2
    out$span_sel <- paste(sp$sel, collapse = ";")
    out$alpha_span <- sp$alpha
    out$alpha_span_t <- sp$alpha_t
    out$n_span <- sp$n
  }
  # 하락 국면 동조: 풀(계보 대표 동일가중) 원수익이 음수인 달만의 (같은 척도) 상관 · 하락 포착률
  pr <- rowMeans(mats$R[, best$member_id, drop = FALSE], na.rm = TRUE)
  pa <- rowMeans(X[, best$member_id, drop = FALSE], na.rm = TRUE)
  D <- !is.na(y) & is.finite(pr) & pr < 0
  out$n_down <- sum(D)
  if (sum(D) >= min_ov) {
    out$rho_down <- unname(.rfd_cor(y[D], pa[D])["rho"])
    out$capture_down <- mean(yr[D]) / mean(pr[D])
  }
  out$measure <- measure
  out$status <- "ok"
  out
}

# 보유 겹침(설명용): 두 04_holdings.csv 의 월별 보유 종목 집합 Jaccard 평균
rfd_jaccard <- function(h1, h2) {
  rd <- function(p) {
    if (!nzchar(p) || !file.exists(p)) return(NULL)
    x <- tryCatch(data.table::fread(p, select = c("date", "ticker", "target_weight"), showProgress = FALSE),
                  error = function(e) NULL)
    if (is.null(x) || !nrow(x)) return(NULL)
    x <- x[!is.na(target_weight) & target_weight > 0]
    x[, ym := substr(as.character(date), 1, 7)]
    unique(x[, .(ym, ticker)])
  }
  a <- rd(h1); b <- rd(h2)
  if (is.null(a) || is.null(b)) return(NA_real_)
  yms <- intersect(unique(a$ym), unique(b$ym))
  if (!length(yms)) return(NA_real_)
  j <- vapply(yms, function(m) {
    s1 <- a[ym == m, ticker]; s2 <- b[ym == m, ticker]
    length(intersect(s1, s2)) / length(union(s1, s2))
  }, 0)
  mean(j)
}

# --- 문턱 보정 · 판정 -------------------------------------------------------------
# null = 관련 없는 계보끼리의 최근접 통계 분포(역사 기저 후보 vs 현재 풀) · 분위 = 설정 calibration.q_dup / q_div (도훈 결정)
rfd_calibrate <- function(null_stats, cfg) {
  q_dup <- .rfd_num(cfg$calibration$q_dup)
  q_div <- .rfd_num(cfg$calibration$q_div)
  ok <- null_stats[status == "ok"]
  qf <- function(x, q) if (sum(!is.na(x)) && is.finite(q)) unname(stats::quantile(x, q, na.rm = TRUE, type = 7)) else NA_real_
  list(tau_dup_rho = qf(ok$rho_max, q_dup), tau_dup_r2 = qf(ok$r2_span, q_dup),
       tau_div_rho = qf(ok$rho_max, q_div), tau_div_r2 = qf(ok$r2_span, q_div),
       tau_div_down = qf(ok$rho_down, q_div), q_dup = q_dup, q_div = q_div, n_null = nrow(ok))
}

rfd_verdict <- function(m, thr) {
  if (!identical(m$status, "ok") || is.na(m$rho_max)) return("insufficient")
  r2 <- .rfd_or(m$r2_span, NA_real_)
  dup <- m$rho_max >= thr$tau_dup_rho || (!is.na(r2) && !is.na(thr$tau_dup_r2) && r2 >= thr$tau_dup_r2)
  if (isTRUE(dup)) return("duplicate")
  orig <- m$rho_max < thr$tau_div_rho && (is.na(r2) || is.na(thr$tau_div_r2) || r2 < thr$tau_div_r2)
  if (isTRUE(orig)) "original" else "ordinary"
}

# 처분 행렬(설계 §8.1): 기저 알파 통과(또는 롤링 구제) ∧ 중복 → 강화 미실행 · 그 밖 통과 → 개시
#   미통과 ∧ 독창 ∧ 하락 국면도 독자적 ∧ 생성 α > 0 → diversifier(2계층 풀 후보 · 강화 미개시) · 그 밖 → 현행
rfd_disposition <- function(verdict, base_ok, m, thr) {
  if (identical(verdict, "insufficient")) return(if (isTRUE(base_ok)) "open(current_rule)" else "no_open(current_rule)")
  if (isTRUE(base_ok)) return(if (identical(verdict, "duplicate")) "skip_duplicate" else "open")
  div <- identical(verdict, "original") && !is.na(m$rho_down) && !is.na(thr$tau_div_down) && m$rho_down < thr$tau_div_down &&
    !is.na(m$alpha_span_t) && m$alpha_span_t > 0
  if (isTRUE(div)) "diversifier" else "no_open(current_rule)"
}
