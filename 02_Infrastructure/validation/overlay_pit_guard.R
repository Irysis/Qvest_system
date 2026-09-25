# =============================================================================
# overlay_pit_guard.R — 오버레이 신호 타이밍 PIT 가드 (2026-07-06, 도훈 지시)
# =============================================================================
# 사건(재발 방지 대상): BearProb 오버레이가 신호를 `Date < anchor_date`로 로드했으나
#   anchor_date = 홀딩월(return_ym)의 *다음달* 첫 거래일(간격 ~31일) → 홀딩월 '말' 정보로
#   그 홀딩월 수익을 스케일 = ~1개월 동월 look-ahead. (faith 오버레이 버그 재발)
#   증상은 placebo/OOS/DSR/subperiod 전부 통과, **lag1 스트레스 + strict-PIT A/B만 판별**.
#
# 원칙(C5 구체화): 오버레이 신호는 **홀딩월이 시작되기 전** 데이터로만 계산·적용한다.
#   - 홀딩월 = 수익(ret)이 실제로 벌리는 캘린더 월.
#   - clean 컷오프 = first-day-of-holding-month. 신호는 Date < 이 값 만 사용.
#   - 패널별 홀딩월 식별:
#       aggregate(period_returns_*): 홀딩월 = return_ym.            컷오프 = ymd(paste0(return_ym,"-01"))
#       holdings(alpha_scores_*):    홀딩월 = month(Date)+1 (β-scan offset+1). 컷오프 = floor_month(Date) %m+% months(1)
#   - anchor_date/realized_ym(라벨)로 컷오프를 잡지 말 것(홀딩월보다 뒤라 look-ahead).
#
# 사용법(오버레이 리서치 의무):
#   source("02_Infrastructure/validation/overlay_pit_guard.R")
#   cutoff <- overlay_signal_cutoff(holding_ym)            # 또는 holdings_cutoff(Date)
#   assert_overlay_pit(my_used_cutoff, cutoff)             # HARD: 컷오프가 홀딩월 시작 전인지
#   ab <- overlay_lookahead_ab(metric_current, metric_strict)   # current≫strict면 look-ahead 의심
#   # + lag1 스트레스: 신호를 shift(1) 적용판이 base 대비 붕괴하는지 확인(유일 판별검정)
#
# ★2026-09-24 C11 확장(파일 하단): 날짜 라벨이 아니라 가용일(avail_date)로 결합·검증하는 층.
#   c11_legacy_gate · c11_window_start · c11_asof_align · assert_overlay_pit_avail · c11_consumption_record.
#   위 C5 함수 4종의 본문은 불변(보존 단정 = 08_Tests/regime/test_c11_consumers.R).
# =============================================================================
suppressWarnings(suppressMessages({ library(data.table); if(!requireNamespace("lubridate", quietly=TRUE)) NULL }))

# 홀딩월(YYYY-MM) 시작일 — 신호는 이 시점 '전' 데이터만 사용 가능
overlay_signal_cutoff <- function(holding_ym) as.Date(paste0(as.character(holding_ym), "-01"))

# holdings 패널: Date(month(D)) → 홀딩월 = month(D)+1 시작일 (β-scan offset+1 실증)
holdings_signal_cutoff <- function(panel_date) {
  d <- as.Date(panel_date)
  fm <- as.Date(format(d, "%Y-%m-01"))
  # +1개월
  y <- as.integer(format(fm, "%Y")); m <- as.integer(format(fm, "%m"))
  m2 <- m + 1L; y2 <- y + (m2 - 1L) %/% 12L; m2 <- ((m2 - 1L) %% 12L) + 1L
  as.Date(sprintf("%04d-%02d-01", y2, m2))
}

# HARD assert: 사용한 신호 컷오프가 홀딩월 시작 이후면 = look-ahead → stop()
assert_overlay_pit <- function(used_cutoff_dates, holding_month_start_dates, label = "overlay") {
  u <- as.Date(used_cutoff_dates); h <- as.Date(holding_month_start_dates)
  bad <- which(is.finite(u) & is.finite(h) & u > h)
  if (length(bad) > 0) {
    stop(sprintf(paste0("[overlay_pit_guard] ★LOOK-AHEAD 차단: %s 신호 컷오프가 홀딩월 시작 이후 %d/%d행. ",
                        "예: cutoff=%s > holding_start=%s. 오버레이 신호는 홀딩월 시작 전 데이터만 사용하라 ",
                        "(anchor_date/realized_ym로 컷오프 잡지 말 것)."),
                 label, length(bad), length(u), as.character(u[bad[1]]), as.character(h[bad[1]])))
  }
  invisible(TRUE)
}

# strict-PIT A/B: 현재 타이밍 성과가 strict보다 rel_tol 이상 좋으면 look-ahead 의심
overlay_lookahead_ab <- function(metric_current, metric_strict, metric_name = "metric",
                                 rel_tol = 0.05, higher_is_better = TRUE) {
  d <- if (higher_is_better) (metric_current - metric_strict) else (metric_strict - metric_current)
  infl <- d / abs(metric_strict)
  flag <- is.finite(infl) && infl > rel_tol
  msg <- sprintf("[overlay_pit_guard] %s: current=%.4f strict=%.4f 인플레=%.1f%% → %s",
                 metric_name, metric_current, metric_strict, 100 * infl,
                 if (flag) "★LOOK-AHEAD 의심 — strict-PIT 값으로 재판정 필수" else "clean")
  list(inflation = infl, lookahead_suspected = flag, message = msg)
}

# =============================================================================
# ★C11 가용시점 인지 확장 (2026-09-24 · PIT C11 수리 1단계 · S4 소비자)
# =============================================================================
# 근거: 04_Research/01_reports/pit_c11_20260924/PIT_C11_verdict_20260924.md
#   ② 원칙 (a)(b)(c) · ⑤-6 소비자 4곳 규약 (b) · 1-5 "overlay_pit_guard 는 시간대·공표 시차를 모른다(확정)"
#   · V-02(pg2 — assert_overlay_pit 가 날짜 라벨만 비교해 통과) · V-06(1행 lag MRS·Category 의 종가→종가 적용).
# 위 assert_overlay_pit 는 **날짜 라벨**만 비교한다. 라벨 d 의 값이 실제로는 한국 d+1 이후에야 알 수 있는
#   정보(미국 d 세션·미공표 주간값)를 담아도 통과한다. 아래 층은 라벨이 아니라 **가용일**로 결합·검증한다.
#   위 C5 함수 4종(overlay_signal_cutoff · holdings_signal_cutoff · assert_overlay_pit · overlay_lookahead_ab)의
#   본문은 바꾸지 않았다(08_Tests/regime/test_c11_consumers.R 가 원판과 본문 동일을 단정한다).
#
# ── 패널 계약(생산자 → 소비자) ────────────────────────────────────────────────
#   가용일 열 = `<값열>_avail_date`(열별) 우선, 없으면 `avail_date`(행 공통) — S0 fred_avail_annotate 와 같은 이름.
#   의미 = 그 행의 값을 '한국 d일 15:30 종가 결정'(판정서 ② 형태 a)에 처음 쓸 수 있는 한국 날짜 d.
#   여러 입력을 합친 행이면 입력별 가용일(02_Infrastructure/data/fred_availability.R)의 최댓값(가장 늦은 날).
#   가용일 열이 없는 패널 = legacy(C11 미해소 · 격리 PITQ-C11-20260924) → c11_legacy_gate() 가 정책대로 처리.
#   가용일 NA 인 행 = 아직 쓸 수 없음(fail-closed) — 결합 대상에서 빠진다.
#   ★r1(2026-09-24 · 통합 검증 BLOCKING — 표식 계약 통일): 생산자 3곳(regime_engine_daily = regime_daily_v2 ·
#     regime_signal = unified 일간·월간 · data_collector_fred = macro_regime)이 같은 계약을 싣는다:
#       행 열 avail_date(Date) + 행 열 c11_regime_key(= S0 fred_avail_rules_meta()$regime_key) + 파일 속성 c11_avail_regime_key.
#     가용일 열은 **Date 형만** 인정한다(POSIXct·문자 = 시간대 변환으로 KST 자정이 하루 앞당겨질 수 있다 → legacy).
#     epoch: 행 열 c11_regime_key 또는 속성 c11_avail_regime_key 가 있으면 현행 규칙 키(c11_rules_key)와 같아야 한다 —
#     다르면 stale_epoch(규칙이 바뀐 뒤의 옛 판) = legacy 와 같이 정책 처리. 키가 없으면(실행 중 S0 fred_avail_annotate 로
#     만든 메모리 패널) 가용일 열만으로 인정한다. 저장 패널은 생산자 검사가 키를 강제한다.
#
# ── 결정일(decision_date): 이 날짜 15:30 까지 가용한 값만 쓴다 ─────────────────
#   형태 (b) 노출 × 한국 종가→종가 수익 r_t: 결정일 = 그 수익 창의 시작 = 같은 수익 계열의 직전 행 날짜
#       (c11_window_start). 일간 계열이면 직전 한국 거래일 = S0 fred_decision_date(…, "exposure_return")
#       (검사가 대조한다), 월간 계열이면 직전 월말 행. ★국면 패널 쪽 '1행 lag' 는 이것을 대신하지 못한다(② b).
#   형태 (a)(c) d 종가 결정 · 월간 보유: 결정일 = 실제 집행일 또는 수익 창 시작일(호출자가 넘긴다).
#       날짜 라벨(anchor·realized_ym)을 결정일로 쓰지 말 것 — pit.md C5 원칙 그대로.
# ── legacy 정책(c11_legacy_policy): 인자 > 환경변수 QVEST_C11_LEGACY_REGIME > "stop"
#   stop  = 중단(기본 · fail-closed)
#   label = 진단 전용 재현 — legacy 정렬로 진행하되 산출물에 pit_c11 = unresolved_legacy_panel 표식
#           (등재·L-code 금지는 호출자 책임 — run_wf_ensemble 은 등재·발행을 끈다)
# =============================================================================

.c11_root <- function(root = NULL) {
  if (!is.null(root) && length(root) == 1L && !is.na(root) && nzchar(root)) return(gsub("\\\\", "/", root))
  for (k in c("QM_ROOT", "CLAUDE_PROJECT_DIR")) {
    v <- Sys.getenv(k, "")
    if (nzchar(v)) return(gsub("\\\\", "/", v))
  }
  getwd()
}
.c11_date <- function(x) as.Date(x, origin = "1970-01-01")

# 값 열에 쓰일 가용일 열 이름(열별 > 행 공통). 없으면 NA = legacy.
#   ★r1(V4 B2): Date 형만 인정. POSIXct 가용일은 as.Date(UTC) 변환에서 KST 자정이 전날이 되어(03-17 00:00 KST →
#   03-16) 결정일 03-16 에 03-17 가용 행이 쓰이고 HARD 검사도 통과했다(실측 probe). 첫 후보가 Date 가 아니면 NA(legacy).
c11_panel_avail_col <- function(panel, value_col) {
  nm <- names(panel)
  for (cand in c(paste0(value_col, "_avail_date"), "avail_date")) {
    if (cand %in% nm) return(if (inherits(panel[[cand]], "Date")) cand else NA_character_)
  }
  NA_character_
}

# 패널 epoch 키(행 열 c11_regime_key 의 고유값 또는 속성 c11_avail_regime_key). 없으면 character(0).
c11_panel_keys <- function(panel) {
  k <- character(0)
  if ("c11_regime_key" %in% names(panel)) k <- unique(as.character(panel[["c11_regime_key"]]))
  a <- attr(panel, "c11_avail_regime_key", exact = TRUE)
  if (!is.null(a)) k <- c(k, as.character(a))
  unique(k)
}

# epoch 판정: 키가 없으면 "no_key"(메모리 패널) · 전부 현행 키면 "current" · 아니면 "stale"(NA 키·규칙 키 미해석 포함).
c11_panel_epoch <- function(panel, root = NULL) {
  k <- c11_panel_keys(panel)
  if (!length(k)) return("no_key")
  cur <- c11_rules_key(root)
  if (is.na(cur) || anyNA(k) || !all(k == cur)) "stale" else "current"
}

c11_panel_status <- function(panel, value_col) {
  if (is.na(c11_panel_avail_col(panel, value_col))) return("legacy_unannotated")
  if (identical(c11_panel_epoch(panel), "stale")) "stale_epoch" else "avail_annotated"
}

c11_legacy_policy <- function(policy = NULL) {
  p <- if (length(policy) && !is.na(policy[1]) && nzchar(policy[1])) policy[1] else Sys.getenv("QVEST_C11_LEGACY_REGIME", "")
  if (!nzchar(p)) p <- "stop"
  p <- tolower(as.character(p))
  if (!p %in% c("stop", "label"))
    stop(sprintf("[overlay_pit_guard/C11] 알 수 없는 legacy 정책 '%s' — stop|label 만 허용(조용한 통과 금지)", p), call. = FALSE)
  p
}

.C11_WARNED <- new.env(parent = emptyenv())

# 소비 직전 관문: 가용일 열이 있으면 통과, 없으면 정책(stop = 중단 · label = 표식 후 legacy 정렬).
c11_legacy_gate <- function(panel, value_col, site, source_desc = "", policy = NULL) {
  if (!is.data.frame(panel)) stop("[overlay_pit_guard/C11] ", site, ": 국면 패널이 data.frame 이 아니다", call. = FALSE)
  if (!(value_col %in% names(panel)))
    stop(sprintf("[overlay_pit_guard/C11] %s: 값 열 '%s' 없음", site, value_col), call. = FALSE)
  ac <- c11_panel_avail_col(panel, value_col)
  ep <- if (is.na(ac)) NA_character_ else c11_panel_epoch(panel)
  if (!is.na(ac) && !identical(ep, "stale"))
    return(invisible(list(status = "avail_annotated", policy = NA_character_, legacy = FALSE, avail_col = ac)))
  pol <- c11_legacy_policy(policy)
  msg <- if (identical(ep, "stale"))
    sprintf(paste0("[overlay_pit_guard/C11] %s: 국면 패널(%s)의 epoch 키(%s)가 현행 규칙 키(%s)와 다르다",
                   " = 규칙이 바뀐 뒤의 옛 판(stale_epoch) — 가용일이 현행 규칙으로 계산되지 않았다."),
            site, if (nzchar(source_desc)) source_desc else "?", paste(c11_panel_keys(panel), collapse = ","),
            as.character(c11_rules_key()))
  else sprintf(paste0("[overlay_pit_guard/C11] %s: 국면 패널(%s)에 가용일 열(%s_avail_date / avail_date · Date 형)이 없다",
                        " = C11 미해소 legacy 패널(판정서 V-05·V-06·V-11 · 격리 PITQ-C11-20260924).",
                        " 날짜 라벨·1행 lag 로는 규약 (b)/(c)를 충족할 수 없다."),
                 site, if (nzchar(source_desc)) source_desc else "?", value_col)
  if (identical(pol, "stop"))
    stop(paste0(msg, " -> 중단(fail-closed). 2단계 재빌드(가용일 부착) 뒤 재실행하라.",
                " 진단 전용 재현 = QVEST_C11_LEGACY_REGIME=label (산출물에 pit_c11 미해소 표식 · 등재 금지)."),
         call. = FALSE)
  key <- paste(site, value_col)
  if (is.null(.C11_WARNED[[key]])) {
    assign(key, TRUE, envir = .C11_WARNED)
    warning(paste0(msg, " -> label 정책: legacy 정렬로 진행하되 산출물에 pit_c11 = unresolved_legacy_panel 표식."),
            call. = FALSE)
  }
  invisible(list(status = if (identical(ep, "stale")) "unresolved_stale_epoch" else "unresolved_legacy_panel",
                 policy = pol, legacy = TRUE, avail_col = NA_character_))
}

# 형태 (b): 수익 행 i 의 결정일 = 같은 계열의 (i-1-extra_lag) 행 날짜. extra_lag = C5 lag 스트레스(0 = 규약 기본).
#   ★r1: kr_calendar(한국 거래일 Date 벡터)를 주면 창 시작을 그 날 이하 마지막 한국 거래일로 내린다 — 수익 계열에
#   주말 행이 있으면(STR_944 일요일 1,174행) 직전 행이 일요일이라 토요일 가용 행(미국 금 세션)이 월요일 수익 창에
#   들어갈 수 있다(통합 검증 (2)-3). 달력 시작 이전 = NA(결정일 미해석 → 결합 안 됨). NULL = 구판 동작.
c11_window_start <- function(dates, extra_lag = 0L, kr_calendar = NULL) {
  d <- as.Date(dates)
  k <- suppressWarnings(as.integer(extra_lag))
  if (length(k) != 1L || is.na(k) || k < 0L) stop("[overlay_pit_guard/C11] extra_lag 는 0 이상 정수", call. = FALSE)
  if (anyNA(d)) stop("[overlay_pit_guard/C11] 수익 계열 날짜에 NA — 창 시작을 정할 수 없다", call. = FALSE)
  if (length(d) > 1L && any(diff(as.integer(d)) <= 0L))
    stop("[overlay_pit_guard/C11] 수익 계열 날짜가 엄격 오름차순이 아니다(중복·역순) — 창 시작을 정할 수 없다", call. = FALSE)
  n <- length(d)
  out <- rep(as.Date(NA), n)
  s <- 1L + k
  if (n > s) out[(s + 1L):n] <- d[seq_len(n - s)]
  if (!is.null(kr_calendar)) {
    cal <- sort(unique(as.integer(as.Date(kr_calendar))))
    if (!length(cal) || anyNA(cal)) stop("[overlay_pit_guard/C11] kr_calendar 가 비었거나 NA", call. = FALSE)
    oi <- as.integer(out)
    ix <- findInterval(oi, cal)
    snap <- rep(NA_integer_, n)
    ok <- !is.na(oi) & ix > 0L
    snap[ok] <- cal[ix[ok]]
    out <- .c11_date(snap)
  }
  out
}

# 결정일마다 '그 날 15:30 까지 가용한 최신 행' 의 값. 반환 = data.table(decision_date, value, src_date, avail_date)
#   (입력 순서 1:1). 결합 규칙은 S0 fred_availability.R 의 as-of 결합과 같다: (가용일, 날짜) 오름차순에서
#   날짜 누적최대와 같은 행만 남긴다 — 늦게 가용해진 옛 행이 이미 가용한 새 행을 덮지 않게.
c11_asof_align <- function(decision_dates, panel, value_col, date_col = "Date", avail_col = NULL) {
  ac <- if (is.null(avail_col)) c11_panel_avail_col(panel, value_col) else avail_col
  if (!is.na(ac) && ac %in% names(panel) && !inherits(panel[[ac]], "Date"))
    stop(sprintf("[overlay_pit_guard/C11] 가용일 열 '%s' 가 Date 형이 아니다(%s) — 시간대 변환으로 하루 앞당겨질 수 있어 거부(fail-closed)",
                 ac, paste(class(panel[[ac]]), collapse = "/")), call. = FALSE)
  if (is.na(ac) || !(ac %in% names(panel)))
    stop(sprintf(paste0("[overlay_pit_guard/C11] '%s' 의 가용일 열 없음 — c11_legacy_gate() 를 먼저 거쳐라",
                        " (legacy 패널을 가용일 결합에 넣지 말 것)"), value_col), call. = FALSE)
  for (col in c(date_col, value_col))
    if (!(col %in% names(panel))) stop("[overlay_pit_guard/C11] 패널에 열 없음: ", col, call. = FALSE)
  dd <- as.integer(as.Date(panel[[date_col]]))
  aa <- as.integer(as.Date(panel[[ac]]))
  vv <- panel[[value_col]]
  keep <- !is.na(dd) & !is.na(aa) & !is.na(vv)
  dd <- dd[keep]; aa <- aa[keep]; vv <- vv[keep]
  if (anyDuplicated(dd))
    stop(sprintf("[overlay_pit_guard/C11] 패널 %s 에 같은 날짜 2행 이상 — 결합 모호(fail-closed)", date_col), call. = FALSE)
  dec <- as.integer(as.Date(decision_dates))
  j <- rep(NA_integer_, length(dec))
  if (length(dd)) {
    o <- order(aa, dd)
    A <- aa[o]; D <- dd[o]
    kp <- D == cummax(D)
    A <- A[kp]; src <- o[kp]
    ii <- findInterval(dec, A)
    ok <- !is.na(dec) & !is.na(ii) & ii > 0L
    j[ok] <- src[ii[ok]]
  }
  data.table(decision_date = .c11_date(dec), value = vv[j],
             src_date = .c11_date(dd[j]), avail_date = .c11_date(aa[j]))
}

# HARD: 사용한 값의 가용일이 결정일 이후면 = C11 미래참조 → stop(). 결정일 없이 쓰인 값도 위반.
assert_overlay_pit_avail <- function(used_avail_dates, decision_dates, label = "overlay") {
  u <- as.Date(used_avail_dates); h <- as.Date(decision_dates)
  if (length(u) != length(h))
    stop(sprintf("[overlay_pit_guard/C11] %s: 가용일(%d)·결정일(%d) 길이 불일치", label, length(u), length(h)), call. = FALSE)
  bad <- which(!is.na(u) & (is.na(h) | u > h))
  if (length(bad) > 0L)
    stop(sprintf(paste0("[overlay_pit_guard/C11] ★가용시점 위반(C11): %s 사용 값의 가용일이 결정일 이후 %d/%d행. ",
                        "예: avail=%s > decision=%s. 관측일·날짜 라벨이 아니라 가용일로 결합하라(판정서 ② a/b/c)."),
                 label, length(bad), length(u), as.character(u[bad[1]]), as.character(h[bad[1]])), call. = FALSE)
  invisible(TRUE)
}

# 측정 epoch 키(판정서 ⑤ P0-05·06 공유 · 결정 PIT-C11-CONVENTIONS ⑧) — S0 규칙 파일 버전. 실패 = NA.
c11_rules_key <- function(root = NULL) {
  r <- .c11_root(root)
  f <- file.path(r, "02_Infrastructure/data/fred_availability.R")
  rp <- file.path(r, "06_Registry/fred_availability_rules.json")
  if (!file.exists(f) || !file.exists(rp)) return(NA_character_)
  fi <- file.info(rp)
  ck <- paste(rp, fi$size, as.numeric(fi$mtime))        # 규칙 파일 경로·크기·mtime 캐시(소비자 루프에서 반복 적재 방지)
  hit <- .C11_KEYCACHE[[ck]]
  if (!is.null(hit)) return(hit)
  k <- tryCatch({
    e <- new.env(parent = globalenv())
    suppressMessages(suppressWarnings(sys.source(f, envir = e)))
    as.character(e$fred_avail_rules_meta(rp)$regime_key)
  }, error = function(err) NA_character_)
  assign(ck, k, envir = .C11_KEYCACHE)
  k
}
.C11_KEYCACHE <- new.env(parent = emptyenv())

# 산출물 기록용 — 소비자가 어떤 정렬로 국면 값을 썼는지(legacy 면 미해소 표식).
c11_consumption_record <- function(gate, site, mode, extra_lag = 0L, n_rows = NA_integer_,
                                   n_aligned = NA_integer_, root = NULL) {
  leg <- isTRUE(gate$legacy)
  list(status = as.character(gate$status), legacy = leg,
       policy = if (is.null(gate$policy)) NA_character_ else as.character(gate$policy),
       avail_col = if (is.null(gate$avail_col)) NA_character_ else as.character(gate$avail_col),
       site = site, mode = mode, extra_lag = as.integer(extra_lag),
       n_rows = as.integer(n_rows), n_aligned = as.integer(n_aligned),
       quarantine = "PITQ-C11-20260924",
       verdict = "04_Research/01_reports/pit_c11_20260924/PIT_C11_verdict_20260924.md",
       rules_key_at_consumption = if (leg) NA_character_ else c11_rules_key(root))
}

if (sys.nframe() == 0L) cat("[overlay_pit_guard] Loaded — overlay_signal_cutoff / holdings_signal_cutoff / assert_overlay_pit / overlay_lookahead_ab · C11: c11_legacy_gate / c11_window_start / c11_asof_align / assert_overlay_pit_avail\n")
