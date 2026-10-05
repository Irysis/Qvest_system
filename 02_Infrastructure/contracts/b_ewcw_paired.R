# b_ewcw_paired.R — b_ewcw 짝지은 Δ 계약 (PR-L1 1차 기전 지표 · 플랜 qvest-1-drifting-eclipse §P2 PR-L1 · 2026-09-25 밤 신설)
# =============================================================================
# ★라벨: "진단 — 등급 대체 아님". 등급은 essence_score.R 하나다. 이 계약은 두 칸(arm · 바닥)의 [시장, EW_U−K200] 2요인
#   사전 적재 b_ewcw_2f(tilt_attribution.R 일간 산출)의 **같은 날 짝** 차이 Δ_t = b_arm,t − b_floor,t 의 평균과 그 추론 통계만 낸다.
#
# 왜 필요한가 (P2 통합 보고 §3 · 2026-09-25): PR-L1(벤치 인지 코어-위성) 1차 지표 = "b_ewcw 감소(짝지은 NW-t ≤ −3)" 인데
#   이 수치를 내는 계약 함수가 없었다(tilt_attribution 은 칸별 일간 b_ewcw_2f 와 구간 평균만 낸다). 판정 입력은 R 계약 산출물뿐이다(AX-008).
#
# 정의 (일간 · 같은 날 짝):
#   d_t = b_arm,t − b_floor,t  (t ∈ 두 칸 일간 산출의 공통 수익일)   value = mean(d)
#   se·t = Newey-West(Bartlett) — 평균의 장기분산. ★lag = max(W, ⌈b·T⌉) (설정 nw.lag_rule = bandwidth_fraction · b = nw.b_fraction).
#     근거: d_t 의 의존은 ① 겹친 적재 창(W−1 일 공유 · MA(W−1) · Hansen & Hodrick 1980) ② 보유 지속(수개월~수년)에서 온다 —
#     겹침 길이 W 만으로는 ②를 못 덮는다. 대역폭을 표본의 고정 비율 b 로 두고 fixed-b 임계값(Kiefer & Vogelsang 2005)으로
#     판정하면 강한 의존에서도 크기가 명목에 가깝다(Sun, Phillips & Jin 2008). 교정 실측(무작위 쌍 귀무 · T=5400 · b=0.2):
#     fixed-b 위양성률 ≈ 5~6% · 정규 1.96 ≈ 11~12% · 자동 lag(NW 1994 · lag 9) ≈ 54~79%. 수치 = INTEG 교정 보고 · 검사 [Z].
#   ★t 의 귀무 분포는 fixed-b 분포다(꼬리가 정규보다 두껍다) — b=0.2 에서 P(t ≤ −3) ≈ 1.3%(정규 0.135%). 판정 문턱(사전등록 −3)은
#     이 크기로 읽어야 한다(산출물 nw.fixed_b 에 임계값 병기). ci_lo·ci_hi = fixed-b 임계(설정 ci_level) × se — 정규 근사 CI 아님.
#   블록 부트스트랩은 싣지 않는다 — 이 계열에서는 블록 = 대역폭이어도 블록 수가 5 개 안팎이라 CI 가 과신한다(교정 실측 90% CI 의 0 제외율
#     ≈ 19%). 사전등록 SE 원천(null_dilution · block_bootstrap)은 이 계약이 공급하지 않는다 — se_eff_fixed_b 는 검정력 근사용 표기일 뿐.
#
# 입력 = tilt_attribution.R::ta_write 가 쓴 <prefix>.json + <prefix>_daily.csv 두 벌(arm · 바닥). 짝의 조건(어기면 stop — 규약이 다른 칸끼리
#   비교하지 않는다): 라벨·버전 = tilt 계약 · 집행 규약(exec_price) 동일 · tilt 설정 md5 동일(같은 적재 정의) · 시장 상태 데이터 지문 동일(같은
#   빈티지 적재) · 적재 창 동일 · 공통 수익일 비율 ≥ 설정.
# 출력 = 최상위 measurement_regime(exec_price · regime key 들 · tilt 설정 md5 · 데이터 지문) + value·se·t·ci_lo·ci_hi·ci_level(fixed-b)·
#   nw_b_fraction · se_eff_fixed_b · nw{lag, rule, T, b, fixed_b} · 입력 지문. bew_write() = 명시 out_dir 에만 JSON(원자 쓰기).
#   ★소비자(rf_prereg.R 판정 입력 검사)는 최상위 ci_level·nw_b_fraction 을 prereg_config verdict.contracts.b_ewcw_paired_delta.pinned
#     로 대조한다(2026-09-26) — 등록 뒤 계약 설정의 대역폭 비율 b 를 바꿔 t 를 고르는 쇼핑을 소비 쪽에서 막는다(prereg_config 는
#     pin_to_registration_config 로 등록 시점에 동결). 계약 설정과 prereg 고정값의 일치는 검사 [RT2] 가 잰다.
#
# 방향: PR-L1 기전 = 코어(시총 상위 k · 벤치 비중)가 EW_U−K200 노출을 줄인다 → Δ < 0. 값의 부호 해석은 사전등록 지표 direction 이 한다.
# ★Vasicek 축소 감쇠(tilt 설정 shrink_weight_ts = w): 두 포트의 GL 이 같으면 사전(횡단 평균)은 같은 날 상쇄되어 Δ̂ ≈ w·Δ(TS 적재) —
#   '참' 적재 차보다 작다(검사 [K] 실측). 기전-함의 효과를 같은 추정량(tilt b_ewcw_2f)으로 내야 검정력 계산이 맞는다.
#
# 재사용(사본 금지): backtest_result_contract.R::.nw_t_mean(정본 NW 식 · parse 로 정의만 적재 — PORT_t 와 같은 식).
# 설정 = 02_Infrastructure/contracts/b_ewcw_paired_config.json(근거 원문 링크 · 없으면 멈춘다). 쓰기 = bew_write 의 명시 out_dir 뿐.
# 검사 = 08_Tests/contracts/test_b_ewcw_paired.R (양성 대조 = 알려진 Δ 주입 회수 · 구조 주입 · 귀무 보정 = 무작위 쌍 위양성률 · 돌연변이)
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })

BEW_VERSION  <- "b_ewcw_paired_v1"
BEW_CONTRACT <- "b_ewcw_paired_delta"
BEW_LABEL    <- "진단 — 등급 대체 아님"
.bew_or <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

.BEW_SELF_DIR <- local({
  hit <- NA_character_
  for (i in rev(seq_len(sys.nframe()))) {
    fr <- tryCatch(sys.frame(i), error = function(e) NULL)
    if (is.null(fr)) next
    for (nm in c("ofile", "file")) {
      v <- tryCatch(get0(nm, envir = fr, inherits = FALSE), error = function(e) NULL)
      if (is.character(v) && length(v) == 1L && grepl("b_ewcw_paired\\.R$", v)) { hit <- v; break }
    }
    if (!is.na(hit)) break
  }
  if (is.na(hit)) NA_character_ else normalizePath(dirname(hit), winslash = "/", mustWork = FALSE)
})

#' 루트 — 명시 인자 > CLAUDE_PROJECT_DIR > QM_ROOT (운영 경로 리터럴 폴백 없음 · 샌드박스 역류 방지)
bew_root <- function(root = NULL) {
  for (p in c(root, Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""))) {
    if (!is.character(p) || !nzchar(p)) next
    p <- sub("/+$", "", gsub("\\\\", "/", p))
    if (dir.exists(file.path(p, "02_Infrastructure")) && dir.exists(file.path(p, "06_Registry"))) return(p)
  }
  stop("[bew] 루트를 찾지 못했다 — root 인자 또는 CLAUDE_PROJECT_DIR/QM_ROOT")
}
.bew_contract_dir <- function(root = NULL) {
  if (!is.na(.BEW_SELF_DIR) && file.exists(file.path(.BEW_SELF_DIR, "backtest_result_contract.R"))) return(.BEW_SELF_DIR)
  file.path(bew_root(root), "02_Infrastructure", "contracts")
}

# 정본 NW 식(.nw_t_mean) — 파일을 parse 해서 그 정의만 평가한다(라이브러리 적재·부작용 없음 · 사본 금지)
.BEW_DEP <- new.env(parent = emptyenv())
.bew_nw_fun <- function(root = NULL) {
  if (is.function(.BEW_DEP$nw)) return(.BEW_DEP$nw)
  p <- file.path(.bew_contract_dir(root), "backtest_result_contract.R")
  if (!file.exists(p)) stop("[bew] 정본 계약 부재: ", p)
  ex <- parse(file = p, encoding = "UTF-8", keep.source = FALSE); env <- new.env(parent = globalenv())
  for (e in as.list(ex)) if (is.call(e) && identical(as.character(e[[1]]), "<-") && is.name(e[[2]]) &&
                              identical(as.character(e[[2]]), ".nw_t_mean")) eval(e, envir = env)
  if (!exists(".nw_t_mean", envir = env, inherits = FALSE)) stop("[bew] backtest_result_contract.R 에 .nw_t_mean 이 없다 — NW 식을 사본으로 만들지 않는다")
  .BEW_DEP$nw <- env$.nw_t_mean; .BEW_DEP$nw_src <- p
  .BEW_DEP$nw
}

# ── 설정 (fail-closed) ─────────────────────────────────────────────────────────
bew_config <- function(root = NULL, path = NULL) {
  root <- bew_root(root)
  p <- .bew_or(path, file.path(root, "02_Infrastructure/contracts/b_ewcw_paired_config.json"))
  if (!file.exists(p)) stop("[bew] 설정 부재: ", p, " — 기본값을 지어내지 않는다(fail-closed)")
  cfg <- fromJSON(p, simplifyVector = FALSE)
  need <- list(c("input", "series"), c("input", "tilt_label"), c("input", "tilt_version"), c("input", "min_common_frac"),
               c("input", "window_field"), c("nw", "kernel"), c("nw", "lag_rule"), c("nw", "b_fraction"),
               c("nw", "fixed_b", "alpha_two_sided"), c("nw", "fixed_b", "coef_975"), c("nw", "fixed_b", "ci_level"), c("nw", "fixed_b", "coef_ci"))
  for (k in need) {
    v <- cfg; for (kk in k) v <- if (is.list(v)) v[[kk]] else NULL
    if (is.null(v) || !length(v)) stop("[bew] 설정 키 부재(fail-closed): ", paste(k, collapse = "."))
  }
  if (!identical(cfg$nw$kernel, "bartlett")) stop("[bew] nw.kernel 은 bartlett 만(정본 .nw_t_mean 식)")
  if (!(cfg$nw$lag_rule %in% c("bandwidth_fraction"))) stop("[bew] 미지 nw.lag_rule: ", cfg$nw$lag_rule)
  bf <- suppressWarnings(as.numeric(cfg$nw$b_fraction))
  if (!(length(bf) == 1L && is.finite(bf) && bf > 0 && bf <= 1)) stop("[bew] nw.b_fraction ∈ (0,1] (fixed-b 대역폭 비율)")
  if (length(cfg$nw$fixed_b$coef_975) != 4L || length(cfg$nw$fixed_b$coef_ci) != 4L) stop("[bew] nw.fixed_b.coef_975·coef_ci 는 3차 다항 4계수")
  if (!isTRUE(all.equal(as.numeric(cfg$nw$fixed_b$alpha_two_sided), 0.05))) stop("[bew] coef_975 는 양측 5% 임계 다항식 — alpha_two_sided 는 0.05 여야 한다")
  cl <- as.numeric(cfg$nw$fixed_b$ci_level); if (!(cl > 0 && cl < 1)) stop("[bew] nw.fixed_b.ci_level ∈ (0,1)")
  if (!(as.numeric(cfg$input$min_common_frac) > 0 && as.numeric(cfg$input$min_common_frac) <= 1)) stop("[bew] input.min_common_frac ∈ (0,1]")
  cfg$.path <- gsub("\\\\", "/", p); cfg$.md5 <- unname(as.character(tools::md5sum(p)))
  cfg
}

# ── 통계 부품 (순수) ────────────────────────────────────────────────────────────
#' NW lag — max(적재 창 W, ⌈b·T⌉) (겹친 창 의존 이상 · 표본의 고정 비율 = fixed-b 대역폭)
bew_nw_lag <- function(window, n, cfg) {
  W <- suppressWarnings(as.integer(window))
  if (!is.finite(W) || W < 1L) stop("[bew] 적재 창 W 판독 불가 — lag 를 정할 수 없다")
  n <- as.integer(n); if (!is.finite(n) || n < 2L) stop("[bew] 표본 길이 판독 불가")
  as.integer(max(W, ceiling(as.numeric(cfg$nw$b_fraction) * n)))
}

#' NW 평균 추론 — 정본 .nw_t_mean 으로 t 를 내고, se 는 같은 잔차(평균 제거)로 낸다: y = x − mean(x) + 1 이면 t(y) = 1/se
bew_nw_stats <- function(x, lag, root = NULL) {
  nw <- .bew_nw_fun(root)
  x <- x[is.finite(x)]; n <- length(x)
  if (n < lag + 2L) return(list(n = n, value = if (n) mean(x) else NA_real_, se = NA_real_, t = NA_real_))
  mu <- mean(x); y <- x - mu + 1; t1 <- nw(y, lag = lag)
  se <- if (is.finite(t1) && t1 > 0) mean(y) / t1 else NA_real_      # = sqrt(장기분산/n) — 정본 식의 분모 그대로
  list(n = n, value = mu, se = se, t = if (is.finite(se) && se > 0) mu / se else NA_real_)
}

#' fixed-b 임계값(Bartlett · Kiefer & Vogelsang 2005 3차 다항) — which = "975"(양측 5%) | "ci"(설정 ci_level 의 양측 분위)
bew_fixed_b_crit <- function(b, cfg, which = c("975", "ci")) {
  which <- match.arg(which)
  cf <- as.numeric(unlist(if (which == "975") cfg$nw$fixed_b$coef_975 else cfg$nw$fixed_b$coef_ci))
  sum(cf * c(1, b, b^2, b^3))
}

#' 핵심(순수) — 같은 날 짝 계열 두 개 → Δ 통계. dates 는 정렬·유일 · b_arm/b_floor 는 같은 길이
bew_paired_delta_series <- function(dates, b_arm, b_floor, window, cfg, root = NULL) {
  if (length(b_arm) != length(b_floor) || length(b_arm) != length(dates)) stop("[bew] 짝 계열 길이 불일치")
  if (anyDuplicated(dates)) stop("[bew] 날짜 중복 — 같은 날 짝이 아니다")
  if (is.unsorted(dates)) stop("[bew] 날짜 비정렬")
  d <- as.numeric(b_arm) - as.numeric(b_floor)
  if (any(!is.finite(d))) stop(sprintf("[bew] 비유한 Δ %d일 — 적재 결측은 계약 입력 전에 막혀야 한다(tilt 가 멈춘다)", sum(!is.finite(d))))
  n <- length(d); L <- bew_nw_lag(window, n, cfg)
  s <- bew_nw_stats(d, L, root)
  bb <- L / n; crit <- bew_fixed_b_crit(bb, cfg, "975"); ccrit <- bew_fixed_b_crit(bb, cfg, "ci")
  cl <- as.numeric(cfg$nw$fixed_b$ci_level)
  list(value = s$value, se = s$se, t = s$t, n = n,
       ci_lo = s$value - ccrit * s$se, ci_hi = s$value + ccrit * s$se, ci_level = cl,
       nw_b_fraction = as.numeric(cfg$nw$b_fraction),      # 최상위 — 소비자 pinned 대조 키(등록 동결 · 쇼핑 차단)
       se_eff_fixed_b = s$se * crit / stats::qnorm(0.975),
       se_eff_note = "검정력 근사 표기 — 정규 공식(MDE = (z_power + z_0.975)·se)에 넣으면 fixed-b 임계를 반영한다. 사전등록 SE 원천(null_dilution·block_bootstrap) 아님",
       nw = list(kernel = cfg$nw$kernel, lag = L, lag_rule = sprintf("%s: max(W=%s, ceil(%s x T=%d))", cfg$nw$lag_rule, format(window), format(cfg$nw$b_fraction), n),
                 T = n, b = bb, fixed_b = list(alpha_two_sided = as.numeric(cfg$nw$fixed_b$alpha_two_sided), crit = crit,
                                               reject = is.finite(s$t) && abs(s$t) > crit, ci_level = cl, ci_crit = ccrit,
                                               source = "Kiefer & Vogelsang (2005) Bartlett 3차 다항(설정 coef_975·coef_ci)"),
                 source = "backtest_result_contract.R::.nw_t_mean(정본 · Bartlett · /n)"),
       d_summary = list(first = format(dates[1]), last = format(dates[n]), sd = stats::sd(d), min = min(d), max = max(d)))
}

# ── tilt 산출 입력 ─────────────────────────────────────────────────────────────
.bew_md5 <- function(p) unname(as.character(tools::md5sum(p)))
#' tilt 산출 1벌 판독 — json 경로(또는 <dir>/<prefix>.json) → list(json, daily, paths)
bew_read_tilt <- function(x, prefix = "tilt_attribution") {
  jp <- gsub("\\\\", "/", if (dir.exists(x)) file.path(x, paste0(prefix, ".json")) else x)
  if (!file.exists(jp)) stop("[bew] tilt 산출 JSON 부재: ", jp)
  dp <- sub("\\.json$", "_daily.csv", jp)
  if (!file.exists(dp)) stop("[bew] tilt 일간 CSV 부재: ", dp)
  js <- fromJSON(jp, simplifyVector = TRUE)
  dl <- fread(dp)
  dl[, date := as.Date(date)]
  list(json = js, daily = dl, json_path = jp, daily_path = dp, json_md5 = .bew_md5(jp), daily_md5 = .bew_md5(dp))
}

.bew_fp_same <- function(a, b) identical(jsonlite::toJSON(a, auto_unbox = TRUE, digits = NA), jsonlite::toJSON(b, auto_unbox = TRUE, digits = NA))

#' 짝지은 Δ — arm·바닥의 tilt 산출 → 계약 산출(list). 짝의 조건 위반 = stop.
#' @param arm,floor tilt 산출 JSON 경로(또는 디렉터리 + prefix)
bew_paired_delta <- function(arm, floor, cfg = NULL, root = NULL, prefix = "tilt_attribution") {
  root <- bew_root(root); cfg <- .bew_or(cfg, bew_config(root))
  A <- bew_read_tilt(arm, prefix); Fl <- bew_read_tilt(floor, prefix)
  inp <- cfg$input
  for (z in list(A, Fl)) {
    if (!identical(as.character(z$json$label), as.character(inp$tilt_label)) || !identical(as.character(z$json$version), as.character(inp$tilt_version)))
      stop(sprintf("[bew] %s 는 tilt 계약 산출이 아니다(label/version = %s/%s)", z$json_path, .bew_or(z$json$label, "?"), .bew_or(z$json$version, "?")))
    if (!(inp$series %in% names(z$daily))) stop(sprintf("[bew] %s 에 %s 열이 없다", z$daily_path, inp$series))
    if (!is.null(z$json$input$inject_alpha_ann)) stop(sprintf("[bew] %s 는 주입(양성 대조) 산출이다 — 판정 입력 아님", z$json_path))
  }
  epA <- as.character(A$json$input$exec_price); epF <- as.character(Fl$json$input$exec_price)
  if (!identical(epA, epF)) stop(sprintf("[bew] 집행 규약 불일치 arm=%s floor=%s — 규약이 다른 칸끼리 비교하지 않는다", epA, epF))
  rkA <- as.character(.bew_or(A$json$input$regime_key, NA)); rkF <- as.character(.bew_or(Fl$json$input$regime_key, NA))
  if (!is.na(rkA) && !is.na(rkF) && !identical(rkA, rkF)) stop(sprintf("[bew] regime key 불일치 %s ≠ %s", rkA, rkF))
  if (!identical(as.character(A$json$config$md5), as.character(Fl$json$config$md5)))
    stop("[bew] tilt 설정 md5 불일치 — 적재 정의(창·축소·유니버스)가 다른 두 산출은 짝이 아니다")
  wf <- as.character(inp$window_field)
  WA <- A$json$config[[wf]]; WF <- Fl$json$config[[wf]]
  if (is.null(WA) || !identical(as.integer(WA), as.integer(WF))) stop(sprintf("[bew] 적재 창(config.%s) 불일치/부재", wf))
  if (!.bew_fp_same(A$json$state$data_fp, Fl$json$state$data_fp))
    stop("[bew] 시장 상태 데이터 지문 불일치 — 다른 빈티지 적재끼리 짝짓지 않는다(같은 ta_build_state 로 두 칸을 분해할 것)")
  s <- as.character(inp$series)
  a <- A$daily[, .(date, xa = get(s))]; f <- Fl$daily[, .(date, xf = get(s))]
  m <- merge(a, f, by = "date"); setorder(m, date)
  fr <- c(arm = nrow(m) / nrow(a), floor = nrow(m) / nrow(f))
  if (any(fr < as.numeric(inp$min_common_frac)))
    stop(sprintf("[bew] 공통 수익일 비율 arm %.3f · floor %.3f < %s — 표본(시작일·데이터 끝)이 다른 두 칸", fr[1], fr[2], format(inp$min_common_frac)))
  core <- bew_paired_delta_series(m$date, m$xa, m$xf, WA, cfg, root)
  mr <- list(exec_price = epA, regime_key_arm = rkA, regime_key_floor = rkF, tilt_config_md5 = as.character(A$json$config$md5),
             data_fp = A$json$state$data_fp, window = as.integer(WA))
  side <- function(z) list(json = z$json_path, json_md5 = z$json_md5, daily_md5 = z$daily_md5, artifact = z$json$input$artifact,
                           dir = z$json$input$dir, strategy_id = z$json$input$strategy_id, n_days = nrow(z$daily),
                           first = format(min(z$daily$date)), last = format(max(z$daily$date)),
                           essence_grade_auth = z$json$input$essence_grade_auth,
                           GL_zero_days = if ("GL" %in% names(z$daily)) sum(z$daily$GL == 0) else NA_integer_)
  c(list(contract = BEW_CONTRACT, label = BEW_LABEL, version = BEW_VERSION, created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
         note = paste0("진단 — 등급 대체 아님. d_t = b_arm − b_floor(", s, " · 같은 날 짝). value = mean(d) · se·t = NW Bartlett(lag = max(W, b·T)) · ",
                       "ci = fixed-b 임계 × se · t 의 귀무 분포 = fixed-b(nw.fixed_b.crit 병기). 부호 해석은 사전등록 지표 direction."),
         measurement_regime = mr,
         input = list(arm = side(A), floor = side(Fl)),
         pairing = list(n_common = nrow(m), common_frac = as.list(fr), first = format(m$date[1]), last = format(m$date[nrow(m)])),
         config = list(path = cfg$.path, md5 = cfg$.md5, nw_source = .BEW_DEP$nw_src)),
    core)
}

#' 쓰기(명시 out_dir 에만 · 원자) — <prefix>.json
bew_write <- function(res, out_dir, prefix = "b_ewcw_paired_delta") {
  if (missing(out_dir) || !nzchar(out_dir)) stop("[bew] out_dir 필수 — 기본 쓰기 경로 없음")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  out <- file.path(out_dir, paste0(prefix, ".json")); tmp <- file.path(out_dir, paste0(".", prefix, ".json.tmp", Sys.getpid()))
  writeLines(toJSON(res, auto_unbox = TRUE, pretty = TRUE, digits = NA, na = "null", null = "null"), tmp, useBytes = TRUE)
  if (!file.rename(tmp, out)) { unlink(tmp); stop("[bew] 원자 쓰기 실패: ", out) }
  invisible(out)
}

#' 귀무 교정 요약 — Δ 계열 목록(참 평균 0 인 짝들) → 위양성률(정규 1.96 · fixed-b 5% · t ≤ thr) · fixed-b CI 가 0 을 뺀 비율
bew_calibrate <- function(d_list, window, cfg, thr = -3, root = NULL) {
  z <- stats::qnorm(0.975)
  M <- do.call(rbind, lapply(d_list, function(d) {
    n <- length(d); L <- bew_nw_lag(window, n, cfg); s <- bew_nw_stats(d, L, root)
    cb <- bew_fixed_b_crit(L / n, cfg, "975"); cc <- bew_fixed_b_crit(L / n, cfg, "ci")
    c(t = s$t, crit_b = cb, ci_excl0 = as.numeric(abs(s$t) > cc), lag = L)
  }))
  list(R = nrow(M), lag = unname(stats::median(M[, "lag"])), fpr_normal = mean(abs(M[, "t"]) > z, na.rm = TRUE),
       fpr_fixed_b = mean(abs(M[, "t"]) > M[, "crit_b"], na.rm = TRUE), fpr_thr = mean(M[, "t"] <= thr, na.rm = TRUE), thr = thr,
       sd_t = stats::sd(M[, "t"], na.rm = TRUE), mean_t = mean(M[, "t"], na.rm = TRUE),
       ci_excl0 = mean(M[, "ci_excl0"], na.rm = TRUE), ci_nominal = 1 - as.numeric(cfg$nw$fixed_b$ci_level), t = unname(M[, "t"]))
}

cat("[b_ewcw_paired.R] Loaded (", BEW_VERSION, ") — bew_config · bew_paired_delta · bew_paired_delta_series · bew_write · bew_calibrate\n", sep = "")
