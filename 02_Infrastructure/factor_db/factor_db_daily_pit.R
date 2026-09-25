# =============================================================================
# factor_db_daily_pit.R — 일간 Factor DB PIT 수리 도우미 (C11 V-09·V-12 · C1 D08·RE10·RE13·RE04)
# =============================================================================
# 2026-09-24 신설 · PIT C11 수리 1단계(코드만) · 서브시스템 S2_daily_fdb.
# 근거: 04_Research/01_reports/pit_c11_20260924/PIT_C11_verdict_20260924.md
#   V-09  phase6 D32: FRED VIX 를 관측일(미국 거래일) 그대로 한국 날짜에 같은 날짜 roll 결합
#   V-12  phase7 RE10·RE13: 전표본 frank/.N(C1) + 같은 날짜 · RE11 같은 날짜 · RE14 M-01 라벨 CPI(최대 약 45일 미공표)
#   1-4   phase6 D08_Tail_Beta: 전 이력 1계수 복제(C1) · phase9b RE04: 전표본 frank(C1 — 2026-09-24 절단 불변성 검사로 확정)
#   ⑤-4·⑤-8 · decision_register PIT-C11-CONVENTIONS ③(CPI 2025-10 결측 → 날짜 기준 12개월 변화) ⑤(C1 동시 수리)
#
# 규약: 일간 fdb 의 한국 날짜 d 행 = 'd 15:30 KST 결정'(판정서 ② 소비 형태 a). 해외 계열은 전부
#   S0 가용시점 층(02_Infrastructure/data/fred_availability.R)의 fred_asof_join(mode = "decision_close")을 경유한다.
#   ★이 파일에는 오프셋·공표 시차 수치가 없다 — 정본은 06_Registry/fred_availability_rules.json.
#   관측 시계열 위의 통계(누적 백분위·EWMA·12개월 변화)는 '그 관측까지'만 쓰고, 가용일이 관측일 순서로
#   단조(비감소)임을 확인한 뒤 결합한다 — 단조가 깨지면 앞 관측이 뒤 관측보다 늦게 풀려 통계에 새므로 거부(stop).
#
# 호출자: factor_db_daily_phase6.R · factor_db_daily_phase7.R · factor_db_daily_phase9b.R
#   (fred_availability.R 을 먼저 source 해야 FRED 결합 함수가 돈다 — 없으면 stop, 같은 날짜 판으로 되돌아가지 않는다)
# 쓰기: 없음(순수 함수). 검사: 08_Tests/factor_db/test_daily_fdb_pit_c11.R
# =============================================================================

suppressWarnings(suppressMessages({ library(data.table) }))

# regime_daily_v2 수리판 표식(스탬프). 판정서 V-10(VIX_z 같은 날짜)·V-11(주간·월간 축 미공표 값)의 생산자 수리
# (regime_engine_daily.R · 별도 서브시스템 S3)가 끝난 파일만 일간 fdb 로 싣는다. 값 = S0 fred_avail_rules_meta()$regime_key
# 형식('c11_avail:<version>:<md5>'). 받는 자리 3곳(어느 하나면 된다):
#   ① data.table R 속성 — setattr(result, "c11_avail_regime_key", key) 후 write_parquet(arrow 'r' 메타데이터 attributes)
#      (2026-09-24 S3 수리판 regime_engine_daily.R 초안의 형식)  ② parquet 최상위 메타데이터 키  ③ 같은 이름의 열.
FDB_REGIME_C11_STAMP_KEY    <- "c11_avail_regime_key"
FDB_REGIME_C11_STAMP_PREFIX <- "c11_avail:"

.fdb_need_avail <- function() {
  if (!exists("fred_asof_join", mode = "function") || !exists("fred_avail_date", mode = "function"))
    stop("[fdb_pit] fred_availability.R 가 로드되지 않았다 — 해외 계열 결합 거부(fail-closed). ",
         "source(file.path(INFRA_DIR, 'data', 'fred_availability.R')) 를 먼저 하라")
  invisible(TRUE)
}

# 관측 시계열 1개 추출: Series_ID == series_id 우선, 없으면 Series 열에서 규칙 파일의 name·aliases 로.
#   같은 관측일 중복은 구판과 같은 last(Value) 로 접는다. 반환 = data.table(Date, Value) 관측일 오름차순 · 없으면 NULL.
fdb_fred_obs <- function(macro_dt, series_id, rules = NULL) {
  .fdb_need_avail()
  s <- fred_series_rule(series_id, rules)                    # 미등록·금지 계열 = stop (fail-closed)
  m <- as.data.table(macro_dt)
  sel <- NULL
  if ("Series_ID" %in% names(m)) sel <- m[as.character(Series_ID) == s$id]
  if ((is.null(sel) || !nrow(sel)) && "Series" %in% names(m))
    sel <- m[as.character(Series) %in% unique(c(s$id, s$name, unlist(s$aliases)))]
  if (is.null(sel) || !nrow(sel)) return(NULL)
  sel <- sel[!is.na(Value), .(Date = as.Date(Date), Value = as.double(Value))]
  sel <- sel[!is.na(Date)]
  if (!nrow(sel)) return(NULL)
  setorder(sel, Date)
  sel[, .(Value = last(Value)), by = Date]
}

# 관측값을 한국 날짜에 가용일 기준으로 싣는다(판정서 ② 형태 a). 반환 = kr_dates 순서 그대로 1:1
#   data.table(Date = 한국 날짜, value, obs_date, avail_date). 가용 관측이 없으면 value = NA.
fdb_fred_on_kr_dates <- function(kr_dates, obs_dt, series_id, value_col = "Value", kr_calendar = NULL, rules = NULL) {
  .fdb_need_avail()
  od <- as.data.table(obs_dt)
  if (!all(c("Date", value_col) %in% names(od))) stop("[fdb_pit] obs_dt 에 Date/", value_col, " 열 없음")
  j <- fred_asof_join(as.Date(kr_dates), od[, c("Date", value_col), with = FALSE], series_id,
                      mode = "decision_close", kr_calendar = kr_calendar, rules = rules, value_col = value_col)
  data.table(Date = j$kr_date, value = as.double(j$value), obs_date = j$obs_date, avail_date = j$avail_date)
}

# 관측 순서로 가용일이 비감소인지 확인(NA = 아직 불가 — 끝부분에만 허용). 깨지면 stop.
fdb_assert_avail_monotone <- function(obs_dates, series_id, kr_calendar = NULL, rules = NULL) {
  .fdb_need_avail()
  o <- sort(as.Date(obs_dates))
  a <- as.integer(fred_avail_date(series_id, o, kr_calendar = kr_calendar, rules = rules))
  ok <- !is.na(a)
  if (any(ok)) {
    last_ok <- max(which(ok))
    if (any(!ok[seq_len(last_ok)]))
      stop(sprintf("[fdb_pit] %s: 가용일 NA 가 가용 관측 사이에 있음 — 누적 통계 결합 거부", series_id))
    av <- a[seq_len(last_ok)]
    if (any(diff(av) < 0L))
      stop(sprintf("[fdb_pit] %s: 가용일이 관측 순서로 단조가 아님(%d곳) — 앞 관측이 뒤 관측보다 늦게 풀려 누적 통계에 샌다. 결합 거부",
                   series_id, sum(diff(av) < 0L)))
  }
  invisible(TRUE)
}

# 관측 시계열 위의 통계(stat_fun(value, date) — 반드시 그 관측까지만 쓰는 함수)를 가용일 기준으로 한국 날짜에 싣는다.
fdb_fred_stat_on_kr_dates <- function(kr_dates, obs_dt, series_id, stat_fun, kr_calendar = NULL, rules = NULL) {
  od <- as.data.table(obs_dt)[order(Date)]
  if (anyDuplicated(od$Date)) stop("[fdb_pit] ", series_id, ": 관측일 중복 — fdb_fred_obs() 로 접은 뒤 넘겨라")
  fdb_assert_avail_monotone(od$Date, series_id, kr_calendar = kr_calendar, rules = rules)
  st <- as.double(stat_fun(od$Value, od$Date))
  if (length(st) != nrow(od)) stop("[fdb_pit] stat_fun 길이 불일치: ", series_id)
  fdb_fred_on_kr_dates(kr_dates, data.table(Date = od$Date, stat = st), series_id, value_col = "stat",
                       kr_calendar = kr_calendar, rules = rules)
}

# 누적(expanding) 백분위 = 구판 frank(x, ties = "average") / N 의 '그 시점까지' 판.
#   i 번째 값의 평균 순위를 x[1..i](NA 제외) 안에서 매기고 그 개수로 나눈다. 마지막 원소는 전표본 값과 같다.
fdb_expanding_pct <- function(x) {
  x <- as.double(x); out <- rep(NA_real_, length(x))
  ok <- which(!is.na(x))
  if (!length(ok)) return(out)
  v <- x[ok]
  out[ok] <- vapply(seq_along(v), function(i) {
    h <- v[seq_len(i)]
    (sum(h < v[i]) + (sum(h == v[i]) + 1) / 2) / i
  }, 0)
  out
}

# 날짜 기준 k개월 변화율(행 기준 shift 금지 — 결측 달이 있으면 행 shift 는 k+1개월 변화가 된다.
#   decision PIT-C11-CONVENTIONS ③: CPIAUCSL 2025-10 부재). 기준 달 관측이 없으면 NA.
fdb_change_by_date <- function(values, dates, months) {
  months <- as.integer(months)
  if (length(months) != 1L || is.na(months) || months < 1L) stop("[fdb_pit] months 는 양의 정수 1개")
  d <- as.Date(dates); v <- as.double(values)
  lt <- as.POSIXlt(d)
  y <- lt$year + 1900L; mo <- lt$mon + 1L - months
  y <- y + (mo - 1L) %/% 12L; mo <- ((mo - 1L) %% 12L) + 1L
  base <- as.Date(sprintf("%04d-%02d-%02d", y, mo, lt$mday), optional = TRUE)
  bv <- v[match(base, d)]
  ifelse(!is.na(v) & !is.na(bv) & bv != 0, v / bv - 1, NA_real_)
}

# D08 꼬리베타 누적판(C++ roll_expanding_tail_beta_cpp — factor_db_daily_rcpp.cpp).
fdb_d08_expanding_tail_beta <- function(ret, bm, k_sd, min_tail) {
  if (!exists("roll_expanding_tail_beta_cpp", mode = "function"))
    stop("[fdb_pit] roll_expanding_tail_beta_cpp 없음 — factor_db_daily_rcpp.cpp 를 sourceCpp 하라")
  roll_expanding_tail_beta_cpp(as.double(ret), as.double(bm), as.double(k_sd), as.integer(min_tail))
}

# 시장 MRS 누적 백분위(phase9b RE04 의 '해당 시점까지' 상위 판정용). rw 는 Date·MRS 열을 가진 종목×일 표.
#   모집단 = 한국 거래일(rw 의 날짜) 위 MRS 일자열 — 구판의 종목별 전표본 frank(상장기간 의존) 대신.
#   rw(data.table)에 MRS_Pct_Exp 열을 참조로 붙여 그대로 돌려준다(행 순서·키 불변 · 큰 표를 복사하지 않는다).
fdb_attach_mrs_expanding_pct <- function(rw) {
  if (!is.data.table(rw)) rw <- as.data.table(rw)
  if (!all(c("Date", "MRS") %in% names(rw))) stop("[fdb_pit] rw 에 Date·MRS 열 없음")
  mk <- unique(rw[!is.na(MRS), .(Date, MRS)])
  if (anyDuplicated(mk$Date)) stop("[fdb_pit] 같은 날짜에 MRS 값이 둘 이상 — 시장 수준 계열이 아님")
  setorder(mk, Date)
  mk[, MRS_Pct_Exp := fdb_expanding_pct(MRS)]
  rw <- setalloccol(rw)
  set(rw, j = "MRS_Pct_Exp", value = mk$MRS_Pct_Exp[match(rw[["Date"]], mk$Date)])
  rw[]
}

# 현행 규칙 epoch 키(S0 fred_avail_rules_meta()$regime_key). 도우미 미적재·판독 실패 = NA(→ 스탬프 판정 FALSE).
.fdb_current_regime_key <- function() {
  if (!exists("fred_avail_rules_meta", mode = "function")) return(NA_character_)
  tryCatch(as.character(fred_avail_rules_meta()$regime_key), error = function(e) NA_character_)
}

# regime_daily_v2 스탬프 판독: R 속성·parquet 메타데이터 키·같은 이름 열 중 하나의 값이 **현행 규칙 키와 같으면** TRUE.
#   ★r1(V2 소견 5 · 통합 검증 '표식 계약 불일치'): 구판은 'c11_avail:' 접두만 봐서 규칙이 바뀐 뒤의 옛 epoch 파일도
#   통과했다. 이제 epoch 가 현행과 달라도 FALSE(stale). 파일 없음·판독 실패·스탬프 없음·형식 불일치 = FALSE(fail-closed).
fdb_regime_c11_ok <- function(regime_path, current_key = .fdb_current_regime_key()) {
  if (!file.exists(regime_path)) return(FALSE)
  if (length(current_key) != 1L || is.na(current_key) || !startsWith(current_key, FDB_REGIME_C11_STAMP_PREFIX)) return(FALSE)
  tb <- tryCatch(arrow::read_parquet(regime_path, as_data_frame = FALSE, mmap = FALSE), error = function(e) NULL)
  if (is.null(tb)) return(FALSE)
  .ok1 <- function(v) is.character(v) && length(v) == 1L && !is.na(v) && identical(v, current_key)
  if (.ok1(tryCatch(tb$metadata$r$attributes[[FDB_REGIME_C11_STAMP_KEY]], error = function(e) NULL))) return(TRUE)
  if (.ok1(tryCatch(tb$metadata[[FDB_REGIME_C11_STAMP_KEY]], error = function(e) NULL))) return(TRUE)
  if (FDB_REGIME_C11_STAMP_KEY %in% names(tb)) {
    v <- as.character(as.vector(tb[[FDB_REGIME_C11_STAMP_KEY]]))
    v <- v[!is.na(v)]
    return(length(v) > 0L && all(v == current_key))
  }
  FALSE
}

# 스탬프가 없으면 regime 값 열을 NA 로(fail-closed). 반환 = 스탬프 판정(논리값). dt 는 참조로 수정된다.
fdb_regime_c11_mask <- function(dt, cols, regime_path, label = "") {
  ok <- fdb_regime_c11_ok(regime_path)
  cols <- intersect(cols, names(dt))
  if (!ok && length(cols)) {
    for (cc in cols) set(dt, j = cc, value = NA_real_)
    msg <- sprintf("[C11] %s regime_daily_v2 미수리판 또는 옛 epoch(스탬프 %s ≠ 현행 %s) → %s = NA (fail-closed · 판정서 V-10·V-11)",
                   label, FDB_REGIME_C11_STAMP_KEY, .fdb_current_regime_key(), paste(cols, collapse = ","))
    cat("  !!", msg, "\n")
    warning(msg, call. = FALSE)
  }
  invisible(ok)
}
