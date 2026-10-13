#==============================================================================
# diagnosis_packet.R — 처방 루프 진단 패킷 (S1 최소판 · v10.01 · 2026-10-13)
#
# 왜: 처방 루프의 에이전트(분석가 · 처방 담당 · 리뷰어)는 수치를 만들지 않는다(AX-008) — 진단 수치는 이 계약이 R 로 낸다.
#   그리고 그 에이전트는 τ_D(2022-12-31) 이후 성과를 보면 안 된다(설계 §3.4 R4 · §3.5 D6 — 절대).
#   그래서 패킷은 τ_D 이후 데이터를 **읽지 않고** 만든다 — 사후 가림이 아니라 적재 단계 절단이다
#   (수익 · 벤치 · 보유 · 시장 패널 · 벤치 이력을 전부 τ_D 에서 자른 뒤 계산한다). 산출 전 날짜 전수 검사가 한 번 더 막는다.
#   설계 = 04_Research/01_reports/l1_prescription_redesign_20261013/README.md §3.3(진단 계약 R) · §5 S1
#
# 무엇을 담나 (모두 보는 창 = 측정 시작 ~ τ_D):
#   ① 정체 — 전략 구성(기저 신호 · 결합 팩터 · 비중 · 리밸 · 유니버스 · 오버레이 · 방어 슬리브 · 집행 규약) · 논문
#   ② 성과 — CAGR · MDD · Calmar · Sharpe · PORT_t(등급 v3 와 같은 계약 함수 gv3_window) + 같은 창 벤치 · 연도별 수익
#   ③ 행동 카드 — 보는 창만으로 만든 카드(위기별 하락 포착 · 상승 포착 · CR 판정 · 베타 · CDaR · 롤링 36M)
#   ④ MC8 귀속 — 선택 / 크기 / 노출 방어 + 위기별 플라시보 분위(matched_controls.R)
#   ⑤ 노출 분해 — tilt_attribution 사전 적재 기계(모든 노출 = t-1 까지): 시장 베타 · 동일가중−시총가중 · 무신호 틸트 · 선택 · 비용
#      창 요약 + 위기별 합
#   ⑥ 위기 귀속 — 위기마다 손실 기여 상위 종목(업종 · 크기 분위 · 성분) · 업종별 합 · 크기 분위별 합
#   ⑦ 구성 프로필 — 종목 수 · 유효 종목 수 · 회전 · 비용 부담 · 크기 분위 비중 · 업종 비중
#
# PIT · τ_D: 적재 = τ_D 까지(ta_load_market to · mc_load_raw to · 벤치 이력 · 보유 집행일 · 수익일). 위기 · 국면 연대기도
#   τ_D 까지의 벤치로만 정한다. 검사 = τ_D 이후 데이터를 흔들어도 패킷 불변(08_Tests/contracts/test_diagnosis_packet.R).
# 경계: 등급을 내지 않는다(진단 — 등급 정본 = essence_score.R). 처방 에이전트 입력 전용이다 —
#   이 패킷의 수치는 보는 창 사후 평가량이라 자동 선정 규칙 입력이 아니다(pit.md C1 D-E).
#
# 공개: dp_build · dp_scan_dates · dp_markdown · dp_write
# 검사: 08_Tests/contracts/test_diagnosis_packet.R
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })

.dp_or <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

.dp_root <- function(root = NULL) {
  for (p in c(root, Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""), getwd())) {
    if (is.null(p) || !nzchar(p)) next
    p <- gsub("\\\\", "/", p)
    if (file.exists(file.path(p, "CLAUDE.md")) && dir.exists(file.path(p, "06_Registry"))) return(sub("/+$", "", p))
  }
  stop("[diagnosis_packet] 프로젝트 루트 해석 실패")
}

# 의존 계약을 사적 환경 하나에 싣는다(같은 루트면 재사용)
.DP <- new.env(parent = emptyenv())
.dp_deps <- function(root) {
  if (isTRUE(.DP$loaded) && identical(.DP$root, root)) return(invisible(.DP$e))
  e <- new.env(parent = globalenv())
  for (f in c("behavior_card.R", "matched_controls.R", "grade_v3.R", "tilt_attribution.R")) {
    p <- file.path(root, "02_Infrastructure/contracts", f)
    if (!file.exists(p)) stop("[diagnosis_packet] 의존 계약 없음: ", p)
    invisible(utils::capture.output(suppressMessages(sys.source(p, envir = e, keep.source = FALSE))))
  }
  .DP$e <- e; .DP$root <- root; .DP$loaded <- TRUE
  invisible(e)
}

#' 패킷 안 날짜 전수 검사 — Date 값과 'YYYY-MM-DD' · 'YYYY-MM' 문자열을 재귀로 훑어 τ_D 초과를 찾는다
#' @return 초과 날짜 문자열(없으면 길이 0)
dp_scan_dates <- function(x, tau) {
  tau <- as.Date(tau); tau_ym <- format(tau, "%Y-%m"); bad <- character(0)
  walk <- function(v) {
    if (is.null(v)) return(invisible())
    if (inherits(v, "Date")) { b <- v[!is.na(v) & v > tau]; if (length(b)) bad <<- c(bad, format(b)); return(invisible()) }
    if (is.data.frame(v)) { for (cc in names(v)) walk(v[[cc]]); return(invisible()) }
    if (is.list(v)) { for (z in v) walk(z); return(invisible()) }
    if (is.character(v)) {
      for (s in v[!is.na(v)]) {
        d <- regmatches(s, gregexpr("(19|20)\\d{2}-(0[1-9]|1[0-2])-(0[1-9]|[12]\\d|3[01])", s))[[1]]
        if (length(d)) { dd <- suppressWarnings(as.Date(d)); b <- d[!is.na(dd) & dd > tau]; bad <<- c(bad, b) }
        m <- regmatches(s, gregexpr("(?<![0-9-])(19|20)\\d{2}-(0[1-9]|1[0-2])(?![0-9-])", s, perl = TRUE))[[1]]
        if (length(m)) bad <<- c(bad, m[m > tau_ym])
      }
    }
    invisible()
  }
  walk(x)
  unique(bad)
}

# 산출물 해석 — remeasure_close_t1_* 형제 판 우선(tilt_attribution 과 같은 규칙) · 보유 · 명세 · 매니페스트
.dp_read <- function(E, dir) {
  src <- E$ta_resolve_artifact(dir)
  f <- function(n) { p <- file.path(src$dir, n); if (!file.exists(p)) stop("[diagnosis_packet] 산출물 없음: ", p); p }
  pr <- fread(f("03_period_returns.csv")); br <- fread(f("05_benchmark_returns.csv")); nv <- fread(f("02_nav.csv"))
  H <- fread(f("04_holdings.csv"), colClasses = list(character = "ticker"))
  for (nm in c("pr", "br", "nv", "H")) { d <- get(nm); d[, date := as.Date(date)] }
  rj <- function(n) { p <- file.path(src$dir, n); if (!file.exists(p)) p <- file.path(dir, n)
                      if (file.exists(p)) tryCatch(fromJSON(p, simplifyVector = TRUE), error = function(e) list()) else list() }
  list(src = src, pr = pr, br = br, nv = nv, H = H, spec = rj("01_strategy_spec.json"), man = rj("00_manifest.json"))
}

# 전략 구성 서술 — 명세에서 그대로(수치 성과 없음). 셀 사양(spec_*.json)이 있으면 그 축을 쓴다.
.dp_identity <- function(rd, cell_spec = NULL) {
  s <- rd$spec
  ax <- if (is.list(cell_spec)) list(
    base_signal = cell_spec$base_signal, base_weight = cell_spec$base_weight,
    factors = vapply(.dp_or(cell_spec$factors, list()), function(z) as.character(.dp_or(z$id, z$kind)), character(1)),
    weighting = .dp_or(cell_spec$weighting$label, cell_spec$weighting$kind), rebalance = .dp_or(cell_spec$rebalance$label, cell_spec$rebalance$kind),
    universe = .dp_or(cell_spec$universe$kind, NA), overlay = .dp_or(cell_spec$overlay$arm_id, "none"),
    defense_sleeve = if (is.null(cell_spec$defense_sleeve)) "none" else cell_spec$defense_sleeve$kind) else NULL
  list(strategy_name = .dp_or(s$strategy_name, NA_character_), paper_url = .dp_or(s$source_paper_url, NA_character_),
       construction = .dp_or(s$construction, NA_character_), weight_method = .dp_or(s$weight_method, NA_character_),
       rebalance = .dp_or(s$rebalance, NA_character_), universe = .dp_or(s$universe, NA_character_),
       n_max = .dp_or(s$n_max, NA), has_short = .dp_or(s$has_short, NA), exec_price = rd$src$exec_price,
       idea = .dp_or(s$strategy_idea, NA_character_), cell_axes = ax)
}

# 연도별 수익(보는 창) — 전략 · 벤치 · 차
.dp_annual <- function(pr, br) {
  P <- pr[, .(y = format(date, "%Y"), r = ret_net)][, .(strategy = prod(1 + r) - 1, n = .N), by = y]
  B <- br[, .(y = format(date, "%Y"), r = benchmark_ret)][, .(bench = prod(1 + r) - 1), by = y]
  A <- merge(P, B, by = "y")[order(y)]
  A[, active := strategy - bench][, .(year = y, strategy, bench, active, n_days = n)]
}

# 업종 as-of 지도 — 보유 종목만, τ_D 까지만 읽는다.
#   종목명은 싣지 않는다: RAWDATA Name 은 2026년부터만 채워져 τ_D 이전엔 비어 있고, 회사명은 에이전트의 사전학습 서사 지식
#   (시험 창 사건)을 불러오는 통로다(설계 §3.5 — Glasserman & Lin 2023). 처방에는 업종 · 크기 분위 · 성분이면 된다.
.dp_names <- function(root, tickers, tau, raw_path = NULL) {
  p <- .dp_or(raw_path, file.path(root, ".cache/RAWDATA.parquet"))
  if (!file.exists(p) || !requireNamespace("arrow", quietly = TRUE)) return(NULL)
  sch <- names(arrow::open_dataset(p)$schema)
  if (!all(c("Date", "Ticker", "Sector") %in% sch)) return(NULL)
  M <- as.data.table(arrow::read_parquet(p, col_select = tidyselect::all_of(c("Date", "Ticker", "Sector"))))
  if (!inherits(M$Date, "Date")) M[, Date := as.Date(Date)]
  M[Ticker %in% tickers & Date <= tau, .(Date, Ticker, Sector = as.character(Sector))]
}
.dp_asof_label <- function(NM, tickers, d) {
  if (is.null(NM) || !nrow(NM)) return(data.table(Ticker = tickers, Sector = NA_character_))
  x <- NM[Ticker %in% tickers & Date <= d]
  x <- x[order(Ticker, Date)][, .(Sector = utils::tail(Sector[!is.na(Sector)], 1)[1]), by = Ticker]
  merge(data.table(Ticker = tickers), x, by = "Ticker", all.x = TRUE)
}

# 노출 분해 · 위기 귀속 — tilt_attribution 기계를 τ_D 까지의 시장 패널로 다시 세운다
.dp_exposure <- function(E, root, rd, prv, brv, Hv, crises, tau, raw_path = NULL, bm_path = NULL, top_k = 5L) {
  tcfg <- E$ta_config(root)
  held <- unique(Hv$ticker)
  mkt <- E$ta_load_market(root, tcfg, from = E$ta_load_from(min(prv$date), tcfg), to = tau, raw_path = raw_path,
                          bm_path = bm_path, extra_tickers = held)
  if (max(mkt$cal) > tau) stop("[diagnosis_packet] PIT — 시장 패널이 τ_D 를 넘었다")
  st <- E$ta_build_state(mkt, tcfg)
  wc <- if ("actual_weight" %in% names(Hv) && any(is.finite(Hv$actual_weight))) "actual_weight" else "target_weight"
  Hta <- Hv[, .(Exec = date, Ticker = as.character(ticker), Weight = as.numeric(get(wc)))]
  WL <- E$.ta_daily_weights(Hta, st, rd$src$exec_price)
  CMP <- E$ta_decompose(WL, st)
  Dt <- merge(prv[, .(date, ret_gross, ret_net)], brv[, .(date, benchmark_ret)], by = "date")[order(date)]
  Dt <- merge(Dt, CMP[, .(date, GL, beta_m, beta_e, beta_n, r_rec, rb, market_beta, ew_cw, tilt_nsc, selection)],
              by = "date", all.x = TRUE)
  Dt[is.na(GL), `:=`(GL = 0, beta_m = 0, beta_e = 0, beta_n = 0, r_rec = 0, rb = st$rb[match(date, st$cal)],
                     market_beta = -st$rb[match(date, st$cal)], ew_cw = 0, tilt_nsc = 0, selection = 0)]
  gap <- max(abs(Dt$benchmark_ret - Dt$rb), na.rm = TRUE)
  if (!is.finite(gap) || gap > 1e-10) stop(sprintf("[diagnosis_packet] 벤치 불일치 max|05 − 상태| = %.3g", gap))
  nna <- sum(!is.finite(Dt$market_beta) | !is.finite(Dt$ew_cw) | !is.finite(Dt$tilt_nsc) | !is.finite(Dt$selection))
  if (nna > 0L) stop(sprintf("[diagnosis_packet] 노출 결측 %d일 — 적재 창이 칸 시작 전에 서지 않았다(tilt_attribution ta_load_from)", nna))
  Dt[, `:=`(active = ret_net - benchmark_ret, cost = ret_net - ret_gross, recon = ret_gross - r_rec)]
  comp <- c("market_beta", "ew_cw", "tilt_nsc", "selection", "cost")
  yrs <- nrow(Dt) / 252
  summ <- rbindlist(lapply(c("active", comp, "recon"), function(cc)
    data.table(component = cc, ann_mean = mean(Dt[[cc]]) * 252,
               share_of_active = if (abs(sum(Dt$active)) > 1e-12) sum(Dt[[cc]]) / sum(Dt$active) else NA_real_)))
  load <- list(beta_m_mean = mean(Dt$beta_m[Dt$GL > 0]), beta_e_mean = mean(Dt$beta_e[Dt$GL > 0]),
               beta_n_mean = mean(Dt$beta_n[Dt$GL > 0]), GL_mean = mean(Dt$GL))
  # 위기별 성분 합 + 종목 귀속
  WL[, `:=`(date = st$cal[di], Ticker = st$tickers[ti], r = st$R0[cbind(di, ti)],
            c_m = w * st$Bm[cbind(di, ti)] * st$rb[di], c_e = w * st$Be[cbind(di, ti)] * st$fe[di],
            c_n = w * st$Bn[cbind(di, ti)] * ifelse(is.finite(st$fn[di]), st$fn[di], 0), c_s = w * st$E0[cbind(di, ti)])]
  WL[, contrib := w * r]
  # 크기 분위(as-of = 그날 사전 Size(엔진 .SizeLag) · 유니버스 U_t 의 분위 경계) — 위기 시작일 기준
  size_decile <- function(di0, tix) {
    u <- which(st$U[di0, ] & is.finite(st$SIZE_L[di0, ]))
    if (length(u) < 10L) return(rep(NA_integer_, length(tix)))
    bp <- stats::quantile(st$SIZE_L[di0, u], probs = seq_len(9) / 10, names = FALSE, type = 7)
    s <- st$SIZE_L[di0, tix]
    ifelse(is.finite(s), findInterval(s, bp) + 1L, NA_integer_)
  }
  NM <- .dp_names(root, unique(WL$Ticker), tau, raw_path)
  per <- list(); hold <- list(); sect <- list(); sizeb <- list()
  for (i in seq_len(nrow(crises))) {
    p0 <- as.Date(crises$peak_date[i]); t0 <- as.Date(crises$trough_date[i])
    W <- Dt[date > p0 & date <= t0]
    if (!nrow(W)) next
    per[[length(per) + 1L]] <- data.table(peak_date = p0, trough_date = t0, n_days = nrow(W),
      strategy_sum = sum(W$ret_net), bench_sum = sum(W$benchmark_ret), active_sum = sum(W$active),
      market_beta_sum = sum(W$market_beta), ew_cw_sum = sum(W$ew_cw), tilt_nsc_sum = sum(W$tilt_nsc),
      selection_sum = sum(W$selection), cost_sum = sum(W$cost), GL_mean = mean(W$GL))
    X <- WL[date > p0 & date <= t0]
    if (!nrow(X)) next
    A <- X[, .(contrib = sum(contrib), market = sum(c_m), size_ew = sum(c_e), nsc = sum(c_n), selection = sum(c_s),
               days_held = .N, w_mean = mean(w)), by = .(Ticker, ti)]
    di0 <- match(min(X$date), st$cal)
    A[, size_decile := size_decile(di0, ti)]
    lab <- .dp_asof_label(NM, A$Ticker, p0)
    A <- merge(A, lab, by = "Ticker", all.x = TRUE)
    setorder(A, contrib)
    hold[[length(hold) + 1L]] <- A[seq_len(min(top_k, .N)), .(peak_date = p0, Ticker, Sector, size_decile,
                                                               contrib, market, size_ew, nsc, selection, days_held, w_mean)]
    sect[[length(sect) + 1L]] <- A[, .(contrib = sum(contrib), n = .N), by = Sector][order(contrib)][, peak_date := p0][]
    sizeb[[length(sizeb) + 1L]] <- A[, .(contrib = sum(contrib), n = .N), by = size_decile][order(size_decile)][, peak_date := p0][]
  }
  list(label = "진단 — 등급 대체 아님 · 노출 = t-1 까지 사전 적재(tilt_attribution 기계) · 위기 합 = 일간 기여의 산술합",
       window = c(format(min(Dt$date)), format(max(Dt$date))), n_days = nrow(Dt), years = yrs,
       loadings = load, summary = summ, crises = rbindlist(per), top_losers = rbindlist(hold),
       by_sector = rbindlist(sect, fill = TRUE), by_size_decile = rbindlist(sizeb, fill = TRUE),
       state = list(cal_first = format(st$cal[1]), cal_last = format(st$cal[st$D]), n_tickers = st$N,
                    nU_median = st$diag$nU_median))
}

# 구성 프로필 — 보유 기록(집행일 ≤ τ_D)과 MC8 분위 배정
.dp_profile <- function(Hv, prv, ctl) {
  wc <- if ("actual_weight" %in% names(Hv) && any(is.finite(Hv$actual_weight))) "actual_weight" else "target_weight"
  H <- Hv[is.finite(get(wc)) & get(wc) > 0, .(date, ticker, w = get(wc))]
  per <- H[, .(N = .N, GL = sum(w), eff_n = sum(w)^2 / sum(w^2)), by = date][order(date)]
  ex <- sort(unique(H$date)); to <- numeric(0)
  for (k in seq_along(ex)[-1L]) {
    a <- H[date == ex[k]]; b <- H[date == ex[k - 1L]]
    al <- union(a$ticker, b$ticker)
    wa <- setNames(a$w, a$ticker)[al]; wa[is.na(wa)] <- 0; wb <- setNames(b$w, b$ticker)[al]; wb[is.na(wb)] <- 0
    to <- c(to, sum(abs(wa - wb)))
  }
  yrs <- nrow(prv) / 252
  cost <- if (all(c("ret_gross", "ret_net") %in% names(prv))) sum(prv$ret_gross - prv$ret_net, na.rm = TRUE) / yrs else NA_real_
  list(n_rebalances = length(ex), n_mean = mean(per$N), eff_n_mean = mean(per$eff_n), gl_mean = mean(per$GL),
       turnover_per_rebalance_mean = if (length(to)) mean(to) else NA_real_,
       turnover_annual = if (length(to) && yrs > 0) sum(to) / yrs else NA_real_,
       cost_drag_annual = cost)
}

#' 진단 패킷 — 측정 산출물 디렉터리 → 보는 창(≤ τ_D)만으로 계산한 진단
#' @param cell_spec 셀 사양(spec_*.json) 경로 또는 목록 — 있으면 구성 서술에 축을 싣는다
#' @param raw / raw_path / bm_path / bm_hist — 시장 데이터(없으면 .cache 정본). 어떤 경우든 τ_D 에서 자른다.
dp_build <- function(dir, root = NULL, tau_d = NULL, cell_spec = NULL, raw = NULL, raw_path = NULL, bm_path = NULL,
                     bm_hist = NULL, with_exposure = TRUE) {
  root <- .dp_root(root); E <- .dp_deps(root)
  bcfg <- E$bc_cfg(root); tau <- as.Date(.dp_or(tau_d, bcfg$tau_d)); bcfg$tau_d <- format(tau)
  rd <- .dp_read(E, dir)
  prv <- rd$pr[date <= tau][order(date)]; brv <- rd$br[date <= tau][order(date)]; nvv <- rd$nv[date <= tau][order(date)]
  Hv <- rd$H[date <= tau]
  if (nrow(prv) < 2L || !nrow(Hv)) stop("[diagnosis_packet] τ_D 이전 수익 · 보유가 없다")
  if (any(Hv$target_weight < 0, na.rm = TRUE)) stop("[diagnosis_packet] 음수 비중(숏) — 처방 루프는 롱온리(고정 축)")
  if (is.character(cell_spec) && length(cell_spec) == 1L && file.exists(cell_spec))
    cell_spec <- fromJSON(cell_spec, simplifyVector = FALSE)
  ## ② 성과 — 등급 v3 와 같은 계약 함수(gv3_window)를 보는 창 표에 건다
  emptyM <- data.table(metric_name = character(0), metric_value = numeric(0))
  emptyC <- data.table(metric_name = character(0), active_value = numeric(0))
  X <- E$.gv3_prep(prv, brv, nvv, emptyM, emptyC)
  perf <- E$gv3_window(X$pr, X$br, X$nv, root = root)
  bs <- E$.gv3_bench_as_strategy(X$br, as.character(X$pr$frequency[1]))
  bperf <- E$gv3_window(bs$pr, X$br, bs$nv, root = root)
  bperf$port_t <- NULL
  ## ③ 행동 카드 — 보는 창 표 · τ_D 까지의 벤치 이력
  if (is.null(bm_hist)) {
    bp <- .dp_or(bm_path, file.path(root, ".cache/benchmark.parquet"))
    bm_hist <- if (file.exists(bp) && requireNamespace("arrow", quietly = TRUE)) {
      h <- as.data.table(arrow::read_parquet(bp, col_select = tidyselect::all_of(c("Date", "BM_Ret"))))
      h[is.finite(BM_Ret), .(date = as.Date(Date), benchmark_ret = BM_Ret)][order(date)]
    } else NULL
  }
  bmh <- if (is.null(bm_hist)) NULL else as.data.table(bm_hist)[date <= tau]
  sid <- tryCatch(as.character(prv$strategy_id[1]), error = function(e) NA_character_)
  card <- E$bc_card(prv[, .(date, ret_net)], brv[, .(date, benchmark_ret)], cfg = bcfg, bm_hist = bmh,
                    strategy_id = sid, root = root)
  ## ④ MC8 — τ_D 까지의 RAWDATA
  mcfg <- E$mc_cfg(root)
  if (is.null(raw)) raw <- E$mc_load_raw(root, from = min(Hv$date) - 31L, to = tau, path = raw_path)
  raw <- as.data.table(raw)[Date <= tau]
  uni <- as.character(.dp_or(rd$spec$universe, .dp_or(rd$man$universe_id, NA_character_)))[1]
  if (is.na(uni) || !nzchar(uni)) stop("[diagnosis_packet] 유니버스 미상")
  ctl <- E$mc_controls(Hv, prv, brv, raw, mcfg, rd$src$exec_price, uni)
  card <- E$mc_attribution(card, ctl, brv[, .(date, benchmark_ret)], bcfg, E)
  ## ⑤⑥ 노출 분해 · 위기 귀속
  crises <- if (!is.null(card$crises) && NROW(card$crises)) as.data.table(card$crises) else data.table()
  expo <- if (isTRUE(with_exposure) && nrow(crises))
    .dp_exposure(E, root, rd, prv, brv, Hv, crises, tau, raw_path = raw_path, bm_path = bm_path) else NULL
  ## ⑦ 구성 프로필
  prof <- .dp_profile(Hv, prv, ctl)
  hd <- ctl$basket_diag
  ctrl <- card$controls
  pk <- list(
    schema = "diagnosis_packet_v1",
    label = "진단 — 등급 대체 아님 · 보는 창(≤ τ_D)만으로 계산 · 처방 에이전트 입력 전용",
    tau_d = format(tau), window = c(format(min(prv$date)), format(max(prv$date))),
    created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    identity = .dp_identity(rd, cell_spec),
    performance = list(strategy = perf, benchmark = bperf, annual = .dp_annual(prv, brv)),
    behavior = list(verdict = card$overall$verdict, summary = card$overall, crises = card$crises,
                    bull_phases = card$bull_phases, stats = card$stats, rolling = card$rolling,
                    dc_strong_max = card$dc_strong_max),
    controls = list(status = ctrl$status, attribution = ctrl$attribution$overall,
                    placebo_alpha = ctrl$attribution$placebo_alpha, exposure_profile = ctrl$exposure_profile[c("mean", "varies", "min", "max")],
                    per_crisis = ctrl$placebo$per_crisis, basket_capture = ctrl$size_exposure_matched$per_crisis,
                    exposure_capture = ctrl$exposure_matched$per_crisis),
    exposure = expo,
    profile = prof,
    provenance = list(source_dir = rd$src$dir, artifact = dir, exec_price = rd$src$exec_price, universe = uni,
                      contracts = c("behavior_card.R", "matched_controls.R", "grade_v3.R(gv3_window)", "tilt_attribution.R"),
                      data_cut = "적재 단계 절단 — 수익 · 벤치 · 보유 · 시장 패널 · 벤치 이력 모두 ≤ τ_D"))
  bad <- dp_scan_dates(pk[setdiff(names(pk), c("created_at", "tau_d"))], tau)
  if (length(bad)) stop("[diagnosis_packet] τ_D 초과 날짜가 패킷에 있다(", length(bad), "): ", paste(utils::head(bad, 5), collapse = ","))
  pk
}

# 숫자 서식(마크다운)
.dp_pct <- function(x, d = 1L) if (is.null(x) || length(x) == 0L || !is.finite(x)) "—" else sprintf(paste0("%.", d, "f%%"), 100 * x)
.dp_num <- function(x, d = 2L) if (is.null(x) || length(x) == 0L || !is.finite(x)) "—" else formatC(x, format = "f", digits = d)

#' 사람(과 에이전트)이 읽는 요약 — 숫자는 패킷 값 그대로(계산하지 않는다)
dp_markdown <- function(pk) {
  L <- character(0); a <- function(...) L <<- c(L, paste0(...))
  id <- pk$identity; P <- pk$performance; Bv <- pk$behavior; C <- pk$controls; X <- pk$exposure; Pf <- pk$profile
  a("# 진단 패킷 — ", .dp_or(id$strategy_name, "?"))
  a(""); a("> ", pk$label, " · 보는 창 ", pk$window[1], " ~ ", pk$window[2], " (τ_D = ", pk$tau_d, ")")
  a(""); a("## 1. 전략 구성")
  a("- 논문: ", .dp_or(id$paper_url, "—"), " · 구성 ", .dp_or(id$construction, "—"), " · 비중 ", .dp_or(id$weight_method, "—"),
    " · 리밸 ", .dp_or(id$rebalance, "—"), " · 유니버스 ", .dp_or(id$universe, "—"), " · 최대 ", .dp_or(id$n_max, "—"), "종 · 집행 ", id$exec_price)
  if (!is.null(id$cell_axes)) {
    ax <- id$cell_axes
    a("- 축: 기저 신호 가중 ", .dp_or(ax$base_weight, "—"), " · 결합 팩터 ", if (length(ax$factors)) paste(ax$factors, collapse = ", ") else "없음",
      " · 비중 ", .dp_or(ax$weighting, "—"), " · 리밸 ", .dp_or(ax$rebalance, "—"), " · 오버레이 ", .dp_or(ax$overlay, "none"),
      " · 방어 슬리브 ", .dp_or(ax$defense_sleeve, "none"))
  }
  a(""); a("## 2. 성과 (보는 창)")
  s <- P$strategy; b <- P$benchmark
  a("| 지표 | 전략 | KOSPI200 |"); a("|---|---|---|")
  a("| CAGR | ", .dp_pct(s$cagr), " | ", .dp_pct(b$cagr), " |")
  a("| 최대낙폭 | ", .dp_pct(-s$mdd), " | ", .dp_pct(-b$mdd), " |")
  a("| Calmar | ", .dp_num(s$calmar), " | ", .dp_num(b$calmar), " |")
  a("| Sharpe | ", .dp_num(s$sharpe), " | ", .dp_num(b$sharpe), " |")
  a("| PORT_t | ", .dp_num(s$port_t), " | — |")
  an <- as.data.table(P$annual)
  if (nrow(an)) { a(""); a("연도별(전략 / 벤치 / 차): ", paste(sprintf("%s %s/%s/%s", an$year, vapply(an$strategy, .dp_pct, ""),
                                                             vapply(an$bench, .dp_pct, ""), vapply(an$active, .dp_pct, "")), collapse = " · ")) }
  a(""); a("## 3. 행동 카드 (보는 창만으로 만든 카드)")
  sm <- Bv$summary
  a("- 위기 방어 판정: **", .dp_or(Bv$verdict, "—"), "** · 위기 ", .dp_or(sm$n_crisis, 0), "번 · 하락 포착 중앙 ", .dp_num(sm$crisis_dd_capture_median),
    " (최악 ", .dp_num(sm$crisis_dd_capture_worst), ") · 강세 상승 포착 중앙 ", .dp_num(sm$bull_up_capture_median),
    " · 자기 낙폭/벤치 ", .dp_num(sm$mdd_vs_bench))
  st <- Bv$stats
  ro <- Bv$rolling
  a("- 베타 ", .dp_num(st$beta), " (하락장 ", .dp_num(st$beta_down), " · 상승장 ", .dp_num(st$beta_up), ") · CDaR ", .dp_pct(-st$cdar),
    " · 롤링 ", .dp_or(ro$window_months, "36"), "M 통과율 전체 ", .dp_pct(ro$pass_life, 0L), " · 최근 ", .dp_pct(ro$pass_recent, 0L),
    " (판정 ", .dp_or(ro$status, "—"), " · 정의 = rolling_grade.R)")
  cr <- as.data.table(Bv$crises)
  if (nrow(cr)) {
    a(""); a("| 위기(고점→바닥) | 벤치 낙폭 | 전략 낙폭 | 하락 포착 | 크기·노출 짝 | 무작위 5% 분위 | p |"); a("|---|---|---|---|---|---|---|")
    pc <- as.data.table(C$per_crisis); bc <- as.data.table(C$basket_capture)
    for (i in seq_len(nrow(cr))) {
      j <- if (nrow(pc)) match(cr$peak_date[i], pc$peak_date) else NA; k <- if (nrow(bc)) match(cr$peak_date[i], bc$peak_date) else NA
      a("| ", format(as.Date(cr$peak_date[i])), "→", format(as.Date(cr$trough_date[i])), " | ", .dp_pct(-cr$bm_dd[i]), " | ", .dp_pct(-cr$st_dd[i]),
        " | ", .dp_num(cr$dd_capture[i]), " | ", if (is.na(k)) "—" else .dp_num(bc$control_dd_capture[k]),
        " | ", if (is.na(j)) "—" else .dp_num(pc$placebo_q[j]), " | ", if (is.na(j)) "—" else .dp_num(pc$placebo_p[j], 3L), " |")
    }
  }
  at <- C$attribution
  a(""); a("- 크기·노출 짝 귀속(MC8): **", .dp_or(at$label, "—"), "** — 무작위 크기 짝을 넘은 위기 비율 ", .dp_pct(at$share_beats_size_exposure, 0L),
    " · 노출 짝(벤치 × 평균 노출)을 넘은 위기 비율 ", .dp_pct(at$share_beats_exposure, 0L), " · 평균 노출 ", .dp_num(C$exposure_profile$mean))
  if (!is.null(X)) {
    a(""); a("## 4. 노출 분해 (보는 창 · 연율 평균 · 노출은 t-1 까지)")
    sx <- as.data.table(X$summary)
    nm <- c(active = "초과수익(전체)", market_beta = "시장 베타", ew_cw = "동일가중−시총가중(크기)", tilt_nsc = "무신호 대조 틸트",
            selection = "선택(특이)", cost = "비용", recon = "재구성 잔차")
    a("| 성분 | 연율 평균 | 초과수익 중 몫 |"); a("|---|---|---|")
    for (i in seq_len(nrow(sx))) a("| ", .dp_or(unname(nm[sx$component[i]]), sx$component[i]), " | ", .dp_pct(sx$ann_mean[i], 2L), " | ", .dp_num(sx$share_of_active[i]), " |")
    a("- 평균 적재: 시장 ", .dp_num(X$loadings$beta_m_mean), " · 크기(EW−CW) ", .dp_num(X$loadings$beta_e_mean), " · 무신호 ", .dp_num(X$loadings$beta_n_mean),
      " · 노출 ", .dp_num(X$loadings$GL_mean))
    xc <- as.data.table(X$crises)
    if (nrow(xc)) {
      a(""); a("위기별 성분 합(일간 합): "); a("| 위기 시작 | 전략 | 벤치 | 초과 | 시장 베타 | 크기 | 무신호 | 선택 | 비용 |"); a("|---|---|---|---|---|---|---|---|---|")
      for (i in seq_len(nrow(xc))) a("| ", format(as.Date(xc$peak_date[i])), " | ", .dp_pct(xc$strategy_sum[i]), " | ", .dp_pct(xc$bench_sum[i]), " | ",
                                     .dp_pct(xc$active_sum[i]), " | ", .dp_pct(xc$market_beta_sum[i]), " | ", .dp_pct(xc$ew_cw_sum[i]), " | ",
                                     .dp_pct(xc$tilt_nsc_sum[i]), " | ", .dp_pct(xc$selection_sum[i]), " | ", .dp_pct(xc$cost_sum[i]), " |")
    }
    tl <- as.data.table(X$top_losers)
    if (nrow(tl)) {
      a(""); a("위기별 손실 기여 상위 종목(기여 = 일간 비중×수익의 합 · 크기 분위 1=최소 10=최대):")
      for (p0 in unique(format(as.Date(tl$peak_date)))) {
        z <- tl[format(as.Date(peak_date)) == p0]
        a("- ", p0, ": ", paste(sprintf("%s(%s · 분위 %s) %s [시장 %s · 크기 %s · 선택 %s]", z$Ticker,
                                        ifelse(is.na(z$Sector), "업종 미상", z$Sector), ifelse(is.na(z$size_decile), "?", z$size_decile),
                                        vapply(z$contrib, .dp_pct, "", d = 2L), vapply(z$market, .dp_pct, "", d = 2L),
                                        vapply(z$size_ew, .dp_pct, "", d = 2L), vapply(z$selection, .dp_pct, "", d = 2L)), collapse = " · "))
      }
    }
    bs <- as.data.table(X$by_sector)
    if (nrow(bs)) {
      a(""); a("위기별 업종 손실(하위 3):")
      for (p0 in unique(format(as.Date(bs$peak_date)))) {
        z <- bs[format(as.Date(peak_date)) == p0][order(contrib)][1:min(3L, .N)]
        a("- ", p0, ": ", paste(sprintf("%s %s(%d종)", ifelse(is.na(z$Sector), "업종 미상", z$Sector), vapply(z$contrib, .dp_pct, "", d = 2L), z$n), collapse = " · "))
      }
    }
    bz <- as.data.table(X$by_size_decile)
    if (nrow(bz)) {
      a(""); a("위기별 크기 분위 기여 합(위기 시작일 as-of 분위 · 1=최소 10=최대 · 기여 = 일간 비중×수익의 합 · 괄호 = 보유 종목 수):")
      for (p0 in unique(format(as.Date(bz$peak_date)))) {
        z <- bz[format(as.Date(peak_date)) == p0][order(size_decile)]
        a("- ", p0, ": ", paste(sprintf("분위 %s %s(%d)", ifelse(is.na(z$size_decile), "?", z$size_decile),
                                        vapply(z$contrib, .dp_pct, "", d = 2L), z$n), collapse = " · "))
      }
    }
  }
  a(""); a("## 5. 구성 프로필 (보는 창)")
  a("- 리밸 ", .dp_or(Pf$n_rebalances, "—"), "회 · 평균 종목 수 ", .dp_num(Pf$n_mean, 1L), " · 유효 종목 수 ", .dp_num(Pf$eff_n_mean, 1L),
    " · 평균 노출 ", .dp_num(Pf$gl_mean), " · 회전(리밸당 Σ|Δw|) ", .dp_num(Pf$turnover_per_rebalance_mean), " · 연 회전 ", .dp_num(Pf$turnover_annual),
    " · 연 비용 부담 ", .dp_pct(Pf$cost_drag_annual, 2L))
  paste(L, collapse = "\n")
}

#' 저장 — diagnosis_packet.json + diagnosis_packet.md (원자적 쓰기)
dp_write <- function(pk, out_dir, prefix = "diagnosis_packet") {
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  w <- function(txt, name) { p <- file.path(out_dir, name); tmp <- paste0(p, ".tmp"); writeLines(txt, tmp, useBytes = TRUE); file.rename(tmp, p); p }
  pj <- w(toJSON(pk, auto_unbox = TRUE, digits = NA, null = "null", na = "null", pretty = TRUE, Date = "ISO8601"), paste0(prefix, ".json"))
  pm <- w(enc2utf8(dp_markdown(pk)), paste0(prefix, ".md"))
  invisible(c(json = pj, md = pm))
}
