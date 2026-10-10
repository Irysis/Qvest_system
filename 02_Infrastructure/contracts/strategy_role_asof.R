#==============================================================================
# strategy_role_asof.R — 전략 역할 라벨 as-of 판 (2계층 소비용 · v0 · 2026-10-10)
#
# 왜: 06_Registry/strategy_roles.json 의 역할 등급은 **전기간** 통계이고, 방어·공격은 사후 Pagan-Sossounov(PS) 연대기
#   (전환점 판정에 ±t_window 미래 창)를 쓴다 — strategy_role.json 이 "2계층 as-of 소비 금지" 라 적는다.
#   2계층이 결정 시점 t 의 슬리브 소속을 정할 때는 t 이전 자료만으로 같은 통계를 다시 재야 한다(pit.md C1 D-E · C14).
# 설계 정본: 04_Research/01_reports/l2_role_rotation_redesign_20261010/README.md §2.1
#
# 원칙 (통계 동일성 · 구조적 PIT):
#   - 역할 통계는 **재구현하지 않는다** — 정본 sr_card()(strategy_role.R) · rfd_monthly()(rf_diversification_gate.R)를 그대로 부른다.
#     as-of 판이 바꾸는 것은 입력 두 가지뿐이다: ① 모든 원자료를 **date < t 로 자른 뒤** 정본 함수에 넣는다
#     ② PS 국면은 잘린 벤치로 다시 판정하고 **확정된 구간만** 라벨을 단다(미확정 = NA → sr_card 가 두 국면 어디에도 안 넣는다).
#   - 결정 시점 t = 달 T 의 첫날. 쓰는 자료 = date < t 인 일간 수익·벤치·사이즈 지수(= Usable_Date ≤ t−1).
#     ★자른 계열에 정본 rfd_monthly 를 그대로 쓰므로 계열의 마지막 캘린더 달(T−1)은 '부분월 가능'으로 버려진다
#       → 일간 계열은 T−2 까지, 월간 계열(행 일자 = 다음 리밸일)은 T−3 까지 쓴다. 보수적 1개월 지연이지만
#       ★t 의 라벨이 t 이후 자료의 '값'뿐 아니라 '존재'에도 의존하지 않는다(삭제 대조 통과 — build_asof_roles.R 대조 i).
#   - 베타·2요인 회귀·NW t·OOS 분할은 전부 sr_card 안에서 잘린 표본(확장 창)으로 계산된다.
#
# PS as-of 확정 규칙 (bbdetection 1.0 소스 src/filter.cpp 판독 — CRAN 미러 github.com/cran/bbdetection):
#   - 극값 후보 루프 = i ∈ [t_window, n − t_window) (0-기준) → 마지막 t_window 관측에는 전환점이 생길 수 없다.
#     검열(t_censor) = 양 끝 t_censor 관측의 극값 제거 — 월간 기본값(8 > 6)에서는 창 조건이 구속한다.
#   - 상태 벡터: 고점 달 = 강세(TRUE) · 저점 달 = 약세(FALSE) · 마지막 극값 뒤 구간은 그 상태를 연장(get_bull).
#   - 실측(2005-01~2026-10 결정월 262개): 모든 전환점이 정확히 9개월 뒤(= t_window+1) 처음 확정되며,
#     확정 뒤 사라진 전환점 0건 · 일시 소멸 3건(고점 2004-03·2013-02·2024-06 — 다음 저점 확정 전 지수가 고점을 넘어
#     끝단 검열 eliminate_max 가 제거했다가 저점 확정과 함께 복귀).
#   confirm = "phase"(기본 · 주판): 두 확정 전환점 사이의 **완결 국면**만 라벨 — 진행 중 국면(마지막 전환점 이후)과
#             첫 전환점 이전 구간은 NA. 근거: 설계 §2.1 "시점 t 에 확정된 국면만(검열 창 지난 고·저점)".
#   confirm = "state"(민감도): 확정 전환점이 상태를 결정하는 달까지 라벨 — 진행 중 국면도 마지막
#             max(t_window, t_censor) − 1 개월(= 미검출 전환점이 상태를 바꿀 수 있는 꼬리)만 빼고 쓴다.
#   두 판 모두 PIT 다(잘린 벤치만 본다). 차이는 '라벨 개정 위험을 얼마나 받아들이나'뿐이다.
#
# 근거(국면 정의·수치는 정본 설정에서 온다 — 여기서 새 수치를 만들지 않는다):
#   - Pagan & Sossounov (2003) JAE 18(1) https://doi.org/10.1002/jae.664 · Bry & Boschan (1971) NBER — 모수 = setpar_dating_alg()
#     기본값(정본 sr_regimes 와 같은 호출) · strategy_role.json regimes.ps_bear.impl 과 기동 시 대조(불일치 = 중단)
#   - Cooper, Gutierrez & Hameed (2004) JF 59(3) https://doi.org/10.1111/j.1540-6261.2004.00665.x — cgh36 은 월초 기지(그대로)
#   - 등급 문턱·OOS 분할·NW 시차·최소 개월 = strategy_role.json grading(sr_card 가 읽는다)
#
# 하지 않는 것:
#   - diversifier: 비교 풀 = **현재** essence B+(전기간 권위 등급) — as-of 판 비교 풀이 존재하지 않는다. 2요인 잔차·계보 대표·BIC 선택도
#     전기간이다. → as-of 라벨을 내지 않는다(대체 정의는 도훈/Q 결정 사항 — build_asof_roles README 미결 항목).
#   - lt_bear(Lunde-Timmermann 강건성 기록): 등급 입력이 아니므로 NA(as-of 판 미산출).
#   - 계보 중복 제거·상관 군집 대표 선정(rf_role_classify_all.R ②)은 다시 하지 않는다 — 소속 판정만.
#
# 공개: sra_ps_params · sra_ps_asof · sra_phases · sra_regimes_asof · sra_factor_monthly · sra_inputs
#       sra_month_inputs · sra_card_asof · sra_flatten · sra_labels_at · sra_build · sra_decision_dates
# 요구: data.table · jsonlite · arrow · bbdetection · strategy_role.R(→ rf_diversification_gate.R)
# 사용: 04_Research/l2_role_rotation/build_asof_roles.R
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })

.sra_find_root <- function(root = NULL) {
  for (p in c(root, Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""), getwd())) {
    if (is.null(p) || !nzchar(p)) next
    p <- gsub("\\\\", "/", p)
    if (dir.exists(file.path(p, "02_Infrastructure"))) return(p)
  }
  stop("[strategy_role_asof] 프로젝트 루트 해석 실패")
}
# 정본 역할 통계(sr_card · .sr_t · .sr_nw_alpha · .sr_grade · .sr_oos)와 계열 판독(rfd_*)을 그대로 쓴다 — 재구현 금지(통계 동일성)
if (!exists("sr_card", mode = "function") || !exists(".sr_env"))
  source(file.path(.sra_find_root(), "02_Infrastructure/contracts/strategy_role.R"))
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

#' PS 모수 = bbdetection::setpar_dating_alg() 기본값(정본 sr_regimes 와 같은 호출) · 정본 설정 서술과 대조
sra_ps_params <- function(cfg) {
  f <- formals(bbdetection::setpar_dating_alg)
  p <- lapply(f[c("t_window", "t_censor", "t_phase", "t_cycle", "max_chng")], eval)
  impl <- as.character(cfg$regimes$ps_bear$impl %||% "")
  for (k in names(p)) {
    hit <- regmatches(impl, regexpr(paste0(k, " [0-9.]+"), impl))
    if (length(hit) && !isTRUE(all.equal(as.numeric(sub(".* ", "", hit)), as.numeric(p[[k]]))))
      stop(sprintf("[strategy_role_asof] PS 모수 드리프트: 패키지 기본 %s=%s · strategy_role.json '%s'", k, p[[k]], hit))
  }
  p$tail_unconfirmed <- as.integer(max(p$t_window, p$t_censor)) - 1L   # 'state' 판에서 빼는 꼬리(위 머리말 유도)
  p
}

#' 잘린 월말 지수 nav(달 < T) 하나에 PS 판정 + 확정 마스크
#' @return list(bull, tp(전환점 위치 = 상태가 바뀌기 직전 달), confirmed(논리), ps_bear(확정 밖 NA))
sra_ps_asof <- function(nav, pars, confirm = c("phase", "state")) {
  confirm <- match.arg(confirm)
  n <- length(nav)
  bbdetection::setpar_dating_alg()                      # 정본 sr_regimes 와 같은 호출(기본값) — 전역 상태를 매번 다시 건다
  bull <- as.logical(bbdetection::run_dating_alg(nav))
  tp <- which(diff(as.integer(bull)) != 0L)             # 고점(강세 마지막 달) · 저점(약세 마지막 달)
  ok <- rep(FALSE, n)
  if (length(tp)) {
    first <- tp[1L]
    hi <- if (identical(confirm, "phase")) tp[length(tp)] else n - pars$tail_unconfirmed
    if (hi > first) ok[(first + 1L):hi] <- TRUE         # 첫 전환점 이전(시작점이 전환점이 아닌 구간)은 미확정
  }
  list(bull = bull, tp = tp, confirmed = ok, ps_bear = ifelse(ok, !bull, NA))
}

#' 국면 표(확정 여부 포함) — 상태 run 단위
sra_phases <- function(ym, ps) {
  r <- rle(ps$bull); e <- cumsum(r$lengths); s <- e - r$lengths + 1L
  data.table(state = ifelse(r$values, "bull", "bear"), start_ym = ym[s], end_ym = ym[e], n = r$lengths,
             closed = e %in% ps$tp,                                          # 끝이 확정 전환점
             n_confirmed = vapply(seq_along(s), function(i) sum(ps$confirmed[s[i]:e[i]]), 0L))
}

#' as-of 국면 3종 — 입력 bm_daily 는 이미 date < t 로 잘린 일간 벤치(정본 rfd_bench_daily 형식: date · bm)
#' @return data.table(ym, ps_bear, lt_bear(NA), cgh36) · attr phases · attr ps
sra_regimes_asof <- function(bm_daily, pars, confirm = c("phase", "state")) {
  confirm <- match.arg(confirm)
  x <- bm_daily[order(date)][, .(date, bm)]
  x[, nav := cumprod(1 + bm)]                                               # 정본 sr_regimes 와 같은 구성
  me <- x[, .(nav = nav[.N]), by = .(ym = format(date, "%Y-%m"))][order(ym)]
  ps <- sra_ps_asof(me$nav, pars, confirm)
  me[, ps_bear := ps$ps_bear]
  me[, lt_bear := NA]                                                       # 강건성 기록 필드 — as-of 판 미산출(등급 무관)
  me[, cgh36 := data.table::shift(nav / data.table::shift(nav, 36L) - 1) < 0]   # 월초 기지(정본 그대로)
  out <- me[, .(ym, ps_bear, lt_bear, cgh36)]
  attr(out, "phases") <- sra_phases(me$ym, ps)
  attr(out, "ps") <- ps
  out
}

#' 유니버스 동일가중 월수익 — 정본 rfd_factor_monthly 와 같은 식을 **메모리 표**에 적용(자를 수 있게)
#'   (정본: 02_Infrastructure/reinforcement/rf_diversification_gate.R rfd_factor_monthly — 기동 시 전기간 비트 동일성 대조)
sra_factor_monthly <- function(ix) {
  if (is.null(ix) || !nrow(ix)) return(NULL)
  x <- data.table::copy(ix)
  data.table::setorder(x, Date)
  x[, `:=`(r_k = kospi200_ew / data.table::shift(kospi200_ew) - 1, r_q = kosdaq150_ew / data.table::shift(kosdaq150_ew) - 1)]
  x <- x[is.finite(r_k) & is.finite(r_q)]
  x[, ew := (200 * r_k + 150 * r_q) / 350]
  m <- x[, .(ew = prod(1 + ew) - 1), by = .(ym = format(Date, "%Y-%m"))]
  data.table::setorder(m, ym)
  if (nrow(m) > 1L) m <- m[-1L]
  m
}

#' 원자료 적재(전부 메모리 — 대조 실험에서 t 이후를 교란할 수 있게) + 정본 대조
sra_inputs <- function(root = NULL) {
  root <- .sra_find_root(root)
  cfg <- sr_cfg(root); dcfg <- .sr_env$rfd_cfg(root)
  bm <- .sr_env$rfd_bench_daily(root, dcfg)
  ixp <- .sr_env$.rfd_abs(.sr_env$.rfd_or(dcfg$factors$path, ".cache/indices.parquet"), root)
  ix <- data.table::as.data.table(arrow::read_parquet(ixp, col_select = c("Date", "kospi200_ew", "kosdaq150_ew")))
  ref <- .sr_env$rfd_factor_monthly(root, dcfg)
  if (!isTRUE(all.equal(as.data.frame(sra_factor_monthly(ix)), as.data.frame(ref), tolerance = 0)))
    stop("[strategy_role_asof] sra_factor_monthly ≠ 정본 rfd_factor_monthly — 정본 변경 추적 필요")
  list(root = root, cfg = cfg, dcfg = dcfg, bm = bm, ix = ix, pars = sra_ps_params(cfg),
       bench_path = attr(bm, "rfd_path"), bench_mtime = attr(bm, "rfd_mtime"), ix_path = ixp)
}

#' 결정 시점 목록 — 월초 · from ~ (벤치 마지막 날이 속한 달의 첫날 = 직전 달이 완결된 마지막 결정월)
sra_decision_dates <- function(bm, from = "2005-01-01") {
  last <- as.Date(format(max(bm$date), "%Y-%m-01"))
  seq(as.Date(from), last, by = "month")
}

#' 결정 시점 t 의 공통 입력(전 구성원 공유) — 전부 date < t 로 자른다
sra_month_inputs <- function(t, inp, confirm = c("phase", "state")) {
  confirm <- match.arg(confirm)
  t <- as.Date(t)
  bm_t <- inp$bm[date < t]
  data.table::setkey(bm_t, date)
  list(t = t, confirm = confirm, bm = bm_t,
       bmm = bm_t[, .(b = prod(1 + bm) - 1), by = .(ym = format(date, "%Y-%m"))],
       fac = sra_factor_monthly(inp$ix[Date < t]),
       R = sra_regimes_asof(bm_t, inp$pars, confirm))
}

#' 구성원 1개 · 결정 시점 1개 → 역할 카드(diversifier 제외) — 정본 sr_card_for_series 와 같은 조립, 입력만 잘린 판
#' @param ser rfd_read_series() 결과(list(freq, dt(date, ret)))
sra_card_asof <- function(ser, M, cfg) {
  if (is.null(ser) || is.null(ser$dt)) return(list(status = "series_unreadable"))
  st <- list(freq = ser$freq, dt = ser$dt[date < M$t])                      # ★date < t — 값·존재 모두 t 이전만
  if (!nrow(st$dt)) return(list(status = "no_data", n_months = 0L))
  mm <- .sr_env$rfd_monthly(st, M$bm, M$fac)
  if (is.null(mm)) return(list(status = "no_data", n_months = 0L))
  m <- merge(merge(mm[, .(ym, r)], M$bmm, by = "ym"), M$fac, by = "ym", all.x = TRUE)
  cd <- sr_card(m, M$R, cfg)
  cd$ym_used <- intersect(m[is.finite(r) & is.finite(b), ym], M$R$ym)      # sr_card 가 실제로 쓴 달(같은 필터·병합)
  cd
}

#' 국면 run 수(확정 라벨이 붙은 달 중 이 구성원 표본에 들어간 달 기준)
.sra_runs <- function(ym_all, flag, ym_used) {
  f <- flag; f[is.na(f)] <- FALSE
  f[!ym_all %in% ym_used] <- FALSE
  r <- rle(f); sum(r$values)
}

#' 카드 → 역할별 행(defensive · offensive · rebound · alpha)
sra_flatten <- function(card, M, member_id, cfg, roles = c("defensive", "offensive", "rebound", "alpha")) {
  route <- unlist(cfg$pool$route_grades %||% list("A", "B"))
  st <- as.character(card$status %||% "unknown")
  base <- data.table(decision_date = M$t, member_id = member_id, role = roles, status = st,
                     n_months = as.integer(card$n_months %||% 0L), first_ym = as.character(card$first_ym %||% NA_character_),
                     last_ym = as.character(card$last_ym %||% NA_character_), beta = as.numeric(card$beta %||% NA_real_),
                     n_regime_obs = NA_integer_, n_phases = NA_integer_, mean = NA_real_, t = NA_real_, oos = NA_integer_,
                     grade_asof = NA_character_, is_member = FALSE, alpha_basis = NA_character_, both_nonneg = NA,
                     ps_confirm = M$confirm)
  if (!identical(st, "ok")) return(base)
  R <- M$R
  used <- as.character(card$ym_used %||% character(0))                      # sr_card 가 쓴 달(연속 가정 없음)
  for (i in seq_along(roles)) {
    z <- card$roles[[roles[i]]]
    if (is.null(z)) next
    base[i, `:=`(n_regime_obs = as.integer(z$n), mean = as.numeric(z$mean %||% NA_real_), t = as.numeric(z$t %||% NA_real_),
                 oos = as.integer(z$oos %||% NA_integer_), grade_asof = as.character(z$grade),
                 is_member = as.character(z$grade) %in% route)]
  }
  ia <- which(roles == "alpha")
  if (length(ia)) base[ia, `:=`(alpha_basis = as.character(card$roles$alpha$basis), both_nonneg = isTRUE(card$roles$alpha$both_regimes_nonneg))]
  if (length(used)) {
    id <- which(roles == "defensive"); if (length(id)) base[id, n_phases := .sra_runs(R$ym, R$ps_bear, used)]
    io <- which(roles == "offensive"); if (length(io)) base[io, n_phases := .sra_runs(R$ym, !R$ps_bear, used)]
    ir <- which(roles == "rebound");   if (length(ir)) base[ir, n_phases := .sra_runs(R$ym, R$cgh36, used)]
  }
  base
}

#' 결정 시점 1개 · 전 구성원
#' @param series named list: member_id → rfd_read_series() 결과
sra_labels_at <- function(t, series, inp, confirm = c("phase", "state"), M = NULL) {
  confirm <- match.arg(confirm)
  M <- M %||% sra_month_inputs(t, inp, confirm)
  data.table::rbindlist(lapply(names(series), function(id) sra_flatten(sra_card_asof(series[[id]], M, inp$cfg), M, id, inp$cfg)))
}

#' 전 결정 시점
sra_build <- function(series, inp, dates, confirm = c("phase", "state"), verbose = TRUE) {
  confirm <- match.arg(confirm)
  out <- vector("list", length(dates))
  for (k in seq_along(dates)) {
    out[[k]] <- sra_labels_at(dates[k], series, inp, confirm)
    if (verbose && (k %% 24L == 0L || k == length(dates))) message(sprintf("[sra_build:%s] %d/%d %s", confirm, k, length(dates), format(dates[k])))
  }
  data.table::rbindlist(out)
}
