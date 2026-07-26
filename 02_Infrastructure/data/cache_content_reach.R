#==============================================================================
# cache_content_reach.R — 캐시 "내용 도달" 판정부 (P2-02 / P2-03 수리, 2026-07-26)
#
# 문제 (04_Research/01_reports/completion_check_pattern_scan_20260726.md §3):
#   cache_freshness_audit 는 두 갈래로 "신선하다"를 결론냈는데, 둘 다 내용을 안 본다.
#     P2-02 (B형) 디렉토리형 캐시에 date_col 이 없으면 **파일명 YYYYMM 의 월말**로
#            lag 을 만든다 → max(0, today - m_end) = 그 달 내내 0. 파일이 어느 날짜에
#            얼어붙어 있어도 FRESH. 실사고: factor_db_202607 이 Date=2026-07-03 에서
#            3주 동결된 동안 매일 data_lag=0/FRESH 보고.
#     P2-03 (C형) date_col 미선언 단일파일 캐시는 **mtime 만으로** 판정 → 내용이
#            비었든 잘렸든 구분 못 함. 실사고: fundamental_dart.parquet mtime 26일
#            → FRESH 인데 내용은 FY2025 corps 50 (정상 714).
#   두 장치가 동시에 침묵해서 FY2025 재무제표 결손이 4개월간 무보고로 남았다.
#
# 이 파일이 대는 명제:
#   "며칠 지났나 / 파일을 언제 만졌나" 가 아니라 **"데이터가 그 지점까지 실제로 차 있나"**.
#   두 가지 도달 축을 선언형으로 제공한다 (registry cache_registry.json 이 선언, 본 파일이 판정):
#
#   ① 시간축 (date_col) — 관측 시계열. YYYY-MM 문자열 축도 지원(kind).
#      · date_semantics="period_end": 기간-라벨 스탬프(월말 라벨은 당월 진행 중 today 를
#        앞선다 → 음수 lag 을 0 으로 clamp). 관측축(observation)은 clamp 하지 않는다.
#   ② 라벨-코호트 커버리지 (coverage_check) — 시간축이 아예 없거나(bsns_year),
#      있어도 그것이 **미래 스탬프**인 캐시용. 실측 근거: fundamental_dart.parquet 의
#      Factor_Date 는 PIT usable date 라 max 가 2027-03-31 이다. 이걸 date_col 로
#      선언하면 lag 이 **음수**가 되어 역시 영구 FRESH — date_col 선언은 여기서 가짜 수리다.
#      대신 "제출기한이 지난 최신 라벨이 직전 라벨 대비 충분히 차 있나"를 잰다.
#
# ★설계 원칙: 후보 집합을 **데이터에 있는 것 중 최신**으로 잡지 않는다(그게 B형 결함이다).
#   기대 라벨은 **달력(제출기한 규칙)에서 먼저 정하고**, 그 라벨이 데이터에 없으면
#   COVERAGE_MISSING 이다. 존재하는 것만 보면 통째로 빠진 코호트가 영원히 안 보인다.
#
# 소비처: 02_Infrastructure/data/cache_freshness_audit.R
# 검사  : 08_Tests/data/test_cache_content_reach.R (위반 주입 — 배터리 SUITES 편입)
#==============================================================================
suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
})

if (!exists("%||%")) {
  `%||%` <- function(a, b) if (is.null(a)) b else a
}

# ─── 시간축 정규화 ────────────────────────────────────────────────────────────

#' 그 달의 마지막 날.
ccr_month_end <- function(d) {
  d <- as.Date(d)
  seq(as.Date(format(d, "%Y-%m-01")), by = "month", length.out = 2L)[2L] - 1L
}

#' 문자/숫자/Date/POSIXct → Date, **에러 없이**. 잘못된 값은 NA.
#' ★as.Date(<character>) 는 기본 tryFormats 경로에서 잘못된 값에 warning 이 아니라
#'   **error** 를 던진다(예: as.Date("2026-13-01")). suppressWarnings 로는 못 막는다 —
#'   date_col 문자열 컬럼에 이상값 1건만 있어도 감사 전체가 죽는다(감시기 사망).
#'   format 지정 파싱은 같은 입력에 NA 를 돌려주므로 그쪽을 쓴다. (2026-07-26 C축 적발)
.ccr_as_date_safe <- function(x) {
  if (inherits(x, "Date")) return(x)
  if (inherits(x, "POSIXt")) return(as.Date(x))
  if (is.numeric(x)) return(suppressWarnings(as.Date(x, origin = "1970-01-01")))
  s <- as.character(x)
  out <- suppressWarnings(as.Date(s, format = "%Y-%m-%d"))
  need <- is.na(out) & !is.na(s) & nzchar(s)
  if (any(need)) out[need] <- suppressWarnings(as.Date(s[need], format = "%Y/%m/%d"))
  out
}

#' date_col 값 → Date 벡터. 파싱 불가는 NA (에러 아님 — 감시기는 죽으면 안 된다).
#'
#' @param kind "date" (기본, Date/POSIXct/표준 문자열) |
#'             "ym" ("YYYY-MM" 문자열 → 그 달 말일) |
#'             "ym_compact" ("YYYYMM" → 그 달 말일)
ccr_to_date <- function(x, kind = "date") {
  kind <- kind %||% "date"
  if (is.null(x) || length(x) == 0L) return(as.Date(character(0)))
  if (identical(kind, "ym") || identical(kind, "ym_compact")) {
    s <- as.character(x)
    pat <- if (identical(kind, "ym")) "^([0-9]{4})-([0-9]{2})$" else "^([0-9]{4})([0-9]{2})$"
    okm <- grepl(pat, s)
    out <- rep(as.Date(NA), length(s))
    if (any(okm)) {
      yy <- sub(pat, "\\1", s[okm]); mm <- sub(pat, "\\2", s[okm])
      # format 지정 — "2026-13" 처럼 패턴은 맞지만 월이 불가능한 값은 NA (에러 아님)
      first <- suppressWarnings(as.Date(paste0(yy, "-", mm, "-01"), format = "%Y-%m-%d"))
      good <- !is.na(first)
      # 월말 = 다음달 1일 − 1일.
      # ★고유값에만 적용한 뒤 match 로 되돌린다 (2026-07-26 성능 수리): 종전엔 행마다
      #   seq() 를 불러, data_ym 이 6,470,000행/고유 124개월인 nps 패널에서 감사 자체가
      #   사실상 끝나지 않았다. 감시기가 감시 대상보다 느려서 안 도는 것도 침묵의 한 형태다.
      nxt <- rep(as.Date(NA), length(first))
      if (any(good)) {
        u <- unique(first[good])
        u_end <- as.Date(vapply(u, function(f)
          as.character(seq(f, by = "month", length.out = 2L)[2L] - 1L), character(1)))
        nxt[good] <- u_end[match(first[good], u)]
      }
      out[okm] <- nxt
    }
    return(out)
  }
  .ccr_as_date_safe(x)
}

#' 내용 lag (일). semantics="period_end" 면 음수 clamp (기간 라벨이 today 를 앞서는 것은 정상).
ccr_lag_days <- function(last_date, today, semantics = "observation") {
  last_date <- .ccr_as_date_safe(last_date)
  if (length(last_date) != 1L || is.na(last_date)) return(NA_integer_)
  lag <- as.integer(as.Date(today) - last_date)
  if (identical(semantics %||% "observation", "period_end")) lag <- max(0L, lag)
  lag
}

#' 파일에서 컬럼 몇 개만 읽는다 (대용량 full-load 회피). 실패는 NULL.
ccr_read_cols <- function(path, cols) {
  if (!file.exists(path)) return(NULL)
  dt <- tryCatch({
    if (grepl("\\.parquet$", path)) {
      as.data.table(read_parquet(path, col_select = tidyselect::all_of(cols)))
    } else if (grepl("\\.csv$", path)) {
      fread(path, select = cols)
    } else if (grepl("\\.rds$", path)) {
      as.data.table(readRDS(path))
    } else NULL
  }, error = function(e) NULL)
  # col_select 실패 시 전량 read 로 1회 재시도 (스키마 상이 대비)
  if (is.null(dt) && grepl("\\.parquet$", path)) {
    dt <- tryCatch(as.data.table(read_parquet(path)), error = function(e) NULL)
  }
  if (is.null(dt) || !all(cols %in% names(dt))) return(NULL)
  dt
}

# ─── 라벨-코호트 커버리지 ─────────────────────────────────────────────────────

#' label_col 값 → 정수 라벨(연도).
#'
#' @param pattern NULL 이면 그대로 as.integer. 지정 시 **앵커된** 정규식이어야 하고
#'   capture group 1 이 정수 라벨이다 (예: Period="YYYYMM" 에서 연간 코호트만 뽑을 때
#'   "^([0-9]{4})12$"). 매칭 안 되는 행은 NA → 코호트 집계에서 제외된다.
#'   ★이것이 "존재하는 것 중 최신"으로 후보를 잡는 것과 다른 점: 기대 라벨은 달력에서
#'   따로 정하므로, 패턴이 걸러낸 뒤에도 통째로 빠진 코호트는 COVERAGE_MISSING 으로 남는다.
.ccr_parse_label <- function(x, pattern = NULL) {
  if (is.null(pattern)) return(suppressWarnings(as.integer(x)))
  s <- as.character(x)
  m <- grepl(pattern, s)
  out <- rep(NA_integer_, length(s))
  if (any(m)) out[m] <- suppressWarnings(as.integer(sub(pattern, "\\1", s[m])))
  out
}

#' 라벨(연도 정수) → 제출기한 Date.
#' @param rule list(years=<offset>, md="MM-DD")
ccr_due_date <- function(label, rule) {
  suppressWarnings(as.Date(sprintf("%d-%s", as.integer(label) + as.integer(rule$years %||% 0L),
                                   rule$md)))
}

#' 그룹 g 의 제출기한 규칙을 고른다.
.ccr_rule_for <- function(due_rule, g) {
  if (is.null(due_rule$by)) return(due_rule)
  m <- due_rule$map[[as.character(g)]]
  m
}

#' 달력에서 먼저 정하는 "기대 최신 라벨" — due(L) <= today - grace 인 최대 L.
#' due 가 L 에 대해 단조증가이므로 today 에서 역산한 뒤 ±2 만 확인한다.
ccr_expected_label <- function(rule, today, grace_days) {
  cutoff <- as.Date(today) - as.integer(grace_days)
  y0 <- as.integer(format(cutoff, "%Y")) - as.integer(rule$years %||% 0L)
  cand <- (y0 + 2L):(y0 - 2L)          # 내림차순
  for (L in cand) {
    d <- ccr_due_date(L, rule)
    if (!is.na(d) && d <= cutoff) return(L)
  }
  NA_integer_
}

#' 라벨-코호트 커버리지 판정.
#'
#' @param spec  registry 의 coverage_check 선언:
#'   list(label_col, entity_col, group_col = NULL, label_pattern = NULL,
#'        due_rule = list(years=, md=)  또는  list(by="<col>", map=list("<g>"=list(years=,md=), ...)),
#'        grace_days = 45, min_ratio_vs_prior = 0.8)
#' @param data  data.table (label_col/entity_col/[group_col] 보유). NULL 이면 path 에서 읽는다.
#' @param path  data=NULL 일 때 읽을 파일 경로
#' @param today 기준일 (테스트 주입용)
#' @return list(status, severity, note, groups) — cache_freshness_audit 결과에 부착 가능
ccr_coverage_check <- function(spec, data = NULL, path = NULL, today = Sys.Date()) {
  today <- as.Date(today)
  grace <- as.integer(spec$grace_days %||% 45L)
  min_ratio <- as.numeric(spec$min_ratio_vs_prior %||% 0.8)
  label_col <- spec$label_col
  entity_col <- spec$entity_col
  group_col <- spec$group_col

  need <- c(label_col, entity_col, group_col)
  if (is.null(data)) data <- ccr_read_cols(path, need)
  if (is.null(data)) {
    return(list(status = "COVERAGE_UNKNOWN", severity = "WARN",
                note = sprintf("커버리지 판정 불가 — 컬럼 read 실패 (%s)",
                               paste(need, collapse = ",")),
                groups = list()))
  }
  data <- as.data.table(data)
  if (!all(need %in% names(data))) {
    return(list(status = "COVERAGE_UNKNOWN", severity = "WARN",
                note = sprintf("커버리지 판정 불가 — 컬럼 부재: %s",
                               paste(setdiff(need, names(data)), collapse = ",")),
                groups = list()))
  }

  gvals <- if (is.null(group_col)) list(NULL) else as.list(sort(unique(as.character(data[[group_col]]))))
  groups <- list(); viol <- character(0)

  for (g in gvals) {
    sub <- if (is.null(g)) data else data[as.character(get(group_col)) == g]
    gname <- if (is.null(g)) "(all)" else g
    rule <- .ccr_rule_for(spec$due_rule, g)
    if (is.null(rule)) {
      groups[[gname]] <- list(group = gname, status = "NO_RULE",
                              note = "due_rule map 에 이 그룹 없음 — 판정 제외")
      next
    }

    # 라벨별 고유 엔티티 수 (label_pattern 이 있으면 그것으로 정수 라벨 추출)
    .cnt_dt <- data.table(label = .ccr_parse_label(sub[[label_col]], spec$label_pattern),
                          .ent  = as.character(sub[[entity_col]]))
    cnt <- .cnt_dt[!is.na(label), .(n = uniqueN(.ent)), by = label][order(label)]
    if (nrow(cnt) == 0L) {
      groups[[gname]] <- list(group = gname, status = "NO_DATA", note = "라벨 0건")
      next
    }

    L_exp <- ccr_expected_label(rule, today, grace)
    due_exp <- if (is.na(L_exp)) as.Date(NA) else ccr_due_date(L_exp, rule)
    # 데이터 시작 이전을 요구하지 않는다 (백필 범위 밖은 기대치 아님)
    if (is.na(L_exp) || L_exp < min(cnt$label)) {
      groups[[gname]] <- list(group = gname, status = "NO_EXPECTATION",
                              expected_label = if (is.na(L_exp)) NULL else L_exp,
                              note = "기대 라벨이 데이터 범위 이전 — 판정 제외")
      next
    }

    n_exp <- if (L_exp %in% cnt$label) cnt[label == L_exp, n] else 0L
    prior <- cnt[label < L_exp]
    if (nrow(prior) == 0L) {
      groups[[gname]] <- list(group = gname, status = "INSUFFICIENT_HISTORY",
                              expected_label = L_exp, n_expected = n_exp,
                              note = "직전 라벨 부재 — 비율 판정 불가")
      next
    }
    L_ref <- max(prior$label); n_ref <- prior[label == L_ref, n]
    ratio <- if (n_ref > 0L) n_exp / n_ref else NA_real_

    gres <- list(group = gname, expected_label = L_exp,
                 due_date = format(due_exp), reference_label = L_ref,
                 n_expected = as.integer(n_exp), n_reference = as.integer(n_ref),
                 ratio = if (is.na(ratio)) NULL else round(ratio, 4),
                 min_ratio = min_ratio)

    if (n_exp == 0L) {
      gres$status <- "COVERAGE_MISSING"
      viol <- c(viol, sprintf("%s: 라벨 %s(기한 %s) 코호트 자체가 없음 (직전 %s=%d)",
                              gname, L_exp, format(due_exp), L_ref, n_ref))
    } else if (!is.na(ratio) && ratio < min_ratio) {
      gres$status <- "COVERAGE_LOW"
      viol <- c(viol, sprintf("%s: 라벨 %s(기한 %s) %d건 = 직전 %s(%d건) 대비 %.1f%% < %.0f%%",
                              gname, L_exp, format(due_exp), n_exp, L_ref, n_ref,
                              100 * ratio, 100 * min_ratio))
    } else {
      gres$status <- "COVERAGE_OK"
    }
    groups[[gname]] <- gres
  }

  if (length(viol) > 0L) {
    list(status = "COVERAGE_FAIL", severity = "CRITICAL",
         note = paste(viol, collapse = " | "), groups = unname(groups))
  } else {
    list(status = "COVERAGE_PASS", severity = "OK",
         note = sprintf("도달 코호트 %d그룹 전부 기준 충족 (grace %dd, min_ratio %.2f)",
                        length(groups), grace, min_ratio),
         groups = unname(groups))
  }
}

# ─── 도달 축 선언 감사 ────────────────────────────────────────────────────────

#' registry 엔트리가 "내용 도달"을 무엇으로 선언했는가.
#' @return "date_col" | "coverage_check" | "mtime_only_declared" | "undeclared"
#' ★ "undeclared" 는 조용한 OK 가 아니라 WARN 이어야 한다 — 선언이 없다는 것은
#'   그 캐시가 내용 결손에 대해 **무방비**라는 뜻이고, 그 상태가 P2-03 을 만들었다.
ccr_reach_declaration <- function(entry) {
  if (!is.null(entry$date_col)) return("date_col")
  if (!is.null(entry$coverage_check)) return("coverage_check")
  if (!is.null(entry$no_content_check)) return("mtime_only_declared")
  "undeclared"
}

cat("[cache_content_reach] Loaded.\n")
