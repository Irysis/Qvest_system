#==============================================================================
# cache_freshness_audit.R — Registry 기반 Freshness Logger (L3)
#
# 도훈 mandate 2026-05-15 영구 보호망 L3:
#   - Registry에 등록된 cache의 mtime + max(Date) vs max_lag_days 비교
#   - Registry에 등록되지 않은 .cache/*.parquet = ORPHAN alert
#   - 양방향 검증으로 silent gap 차단
#
# 2026-07-03 (감사 DATA-P0-1) 값-sanity 섹션 추가:
#   - 신선도(mtime/max Date) 단일축의 맹점 보완 — RAWDATA BM_Ret +581% 손상값이
#     FRESH로 판정되고 7월 factor DB가 이를 소비해 59~60팩터(M08 포함) 결손되던
#     사고 재발 방지. registry 항목의 value_checks 선언 소비:
#       abs_ret_max   : |col| > threshold 건수 (값 폭주 탐지)
#       required_cols : 필수 컬럼 존재 (K200/KQ150 strip 사고 탐지)
#       parity        : 기준 캐시 대비 월수익(log1p 합) 상관 (손상 구간 탐지)
#   - 위반 = VALUE_FAIL / CRITICAL (등록 캐시로 취급 → telegram alert 경로 포함)
#
# Output:
#   .cache/freshness_log.json (daily append)
#   qepm/observability/cache_freshness_latest.json (latest)
#
# Telegram alert: stale > 7 days = WARN, > 14 days = CRITICAL
#==============================================================================
suppressPackageStartupMessages({
  library(jsonlite)
  library(arrow)
  library(data.table)
})

if (!exists("PROJECT_ROOT")) {
  PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
}

source(file.path(PROJECT_ROOT, "02_Infrastructure/data/cache_registry_runner.R"))
# 내용-도달 판정부 (P2-02/P2-03 수리, 2026-07-26) — date_col kind/semantics + 라벨-코호트 커버리지.
source(file.path(PROJECT_ROOT, "02_Infrastructure/data/cache_content_reach.R"))

#' @param caches_override 위반 주입 테스트용 — registry 대신 쓸 cache 엔트리 리스트.
#'   지정 시 orphan 스캔과 IC 프론티어 절은 건너뛴다(주입 registry 에선 무의미).
#' @param today 기준일 주입 (테스트 결정성). 기본 Sys.Date().
#' @param persist FALSE 면 observability/로그/알림상태 파일을 쓰지 않는다 — 테스트가
#'   정본 산출물을 오염시키지 않도록. ★검사가 감시 대상을 건드리면 그 검사는 증거가 아니다.
cache_freshness_audit <- function(telegram_alert = TRUE,
                                    warn_lag_multiplier = 1.0,
                                    critical_lag_multiplier = 2.0,
                                    caches_override = NULL,
                                    today = Sys.Date(),
                                    persist = TRUE) {
  caches <- if (!is.null(caches_override)) caches_override else cache_registry_load()
  today <- as.Date(today)
  today_ts <- Sys.time()

  # ─── 거래일 캘린더 (2026-07-17 주말/휴일 오탐 제거) ─────────────────────────
  # tight-SLA daily 캐시(max_lag ≤ 7)의 data_lag를 "완결 거래일 수"로 측정.
  # 근거: 토/일·휴장일(예: 2026-07-17)마다 RAWDATA/benchmark/MSM lag=2 false-WARN
  # 재발(07-12 일요일 실증) — 캘린더-일 기준이라 비거래일을 지연으로 오인.
  # (last_d, today) 개구간의 거래일 수 = 실제로 놓친 완결 세션 수. 캘린더 커버리지
  # 밖(스테일)이면 기존 캘린더-일 계산으로 fallback (lag를 늘리는 일은 없음).
  .tcal <- tryCatch({
    p <- file.path(PROJECT_ROOT, ".cache", "trading_calendar.parquet")
    if (file.exists(p)) sort(unique(as.Date(as.data.table(read_parquet(p))$Date))) else NULL
  }, error = function(e) NULL)
  .trading_lag <- function(last_d, cal_lag) {
    if (is.null(.tcal) || is.na(last_d) || max(.tcal) < today - 3L) return(cal_lag)
    sum(.tcal > last_d & .tcal < today)
  }

  results <- list()
  registered_paths <- sapply(caches, function(c) c$path)

  # ─── (1) Registered caches: stale check ─────────────────────────────────────
  for (c in caches) {
    cache_path <- file.path(PROJECT_ROOT, c$path)
    res <- list(
      path = c$path,
      tier = c$tier,
      schedule = c$schedule,
      max_lag_days = c$max_lag_days,
      registered = TRUE
    )

    if (!is.null(c$file_pattern)) {
      # ── 디렉토리형 cache (월별 parquet 묶음 — 예: .cache/factor_db/) ─────────
      #    2026-06-10 P1: factor_db / factor_db_daily 디렉토리 freshness 지원.
      #    최신 파일 = file_pattern 매칭 사전순 max (YYYYMM zero-pad → 시간순 일치).
      #    date_col 있으면 최신 파일의 해당 컬럼 max(Date) (col_select — 대용량 wide 대비),
      #    없으면 파일명 YYYYMM의 월말 기준 lag (당월 진행 중 음수 → 0 clamp).
      if (!dir.exists(cache_path)) {
        res$status <- "MISSING"
        res$severity <- "CRITICAL"
        results[[c$path]] <- res
        next
      }
      fs <- sort(list.files(cache_path, pattern = c$file_pattern))
      if (length(fs) == 0) {
        res$status <- "MISSING"
        res$severity <- "CRITICAL"
        res$note <- sprintf("file_pattern '%s' 매칭 파일 0건", c$file_pattern)
        results[[c$path]] <- res
        next
      }
      latest_file <- fs[length(fs)]
      latest_path <- file.path(cache_path, latest_file)
      res$latest_file <- latest_file
      res$n_files <- length(fs)

      mtime <- file.info(latest_path)$mtime
      mtime_lag <- as.integer(today - as.Date(mtime))

      data_lag <- NA_integer_
      if (!is.null(c$date_col)) {
        # ── 내용 기준 (정본 경로) ─────────────────────────────────────────────
        #   집계 규약(2026-07-26 P2-02 명문화): 디렉토리형 캐시의 내용 도달 =
        #   **file_pattern 매칭 사전순 max 파일 1개**의 max(date_col).
        #   (YYYYMM zero-pad 라 사전순 = 시간순. 파일당 1개월이고 완료월 파일은 그 달
        #    최종 거래일에서 멈추므로, 전 파일 스캔 없이 최신 파일만으로 프론티어가 잡힌다 —
        #    실측 2026-07-26: factor_db 439파일 전부 파일명 YYYYMM == 내용 max Date 월,
        #    직전 12개월 전부 내용 max == 그 달 최종 거래일.)
        #   ★내부 월의 구멍(D형)은 이 축의 대상이 아니다 — 별도 gap 검사 소관.
        dt <- tryCatch(as.data.table(read_parquet(latest_path, col_select = c$date_col)),
                       error = function(e)
                         tryCatch(as.data.table(read_parquet(latest_path)),
                                  error = function(e2) NULL))
        if (!is.null(dt) && c$date_col %in% names(dt)) {
          last_d <- suppressWarnings(max(ccr_to_date(dt[[c$date_col]], c$date_col_kind),
                                         na.rm = TRUE))
          if (length(last_d) == 1L && !is.na(last_d) && is.finite(as.numeric(last_d))) {
            data_lag <- ccr_lag_days(last_d, today, c$date_semantics)
            res$content_max_date <- format(last_d)
            res$lag_basis <- "content"
          }
        }
      } else {
        # ── fallback: 파일명 YYYYMM 월말 추정 (P2-02 — 내용을 열지 않는다) ─────
        #   이 경로는 date_col 미선언 시에만 남는 **추정**이다. max(0, today - 월말)
        #   이므로 당월 내내 0 → 파일이 어느 날짜에 얼어붙어도 FRESH 가 된다
        #   (실사고: factor_db_202607 이 Date=2026-07-03 에 3주 동결, 그동안 매일 FRESH).
        #   조용한 추정 금지 — lag_basis 로 표기하고 아래에서 severity 를 WARN 으로 올린다.
        ym <- regmatches(latest_file, regexpr("[0-9]{6}", latest_file))
        if (length(ym) == 1) {
          m_start <- as.Date(paste0(ym, "01"), format = "%Y%m%d")
          m_end <- seq(m_start, by = "month", length.out = 2)[2] - 1
          data_lag <- max(0L, as.integer(today - m_end))
          res$lag_basis <- "filename_month_end_estimate"
        }
      }
    } else {
    # ── 단일 파일 cache (기존 경로) ──────────────────────────────────────────
    if (!file.exists(cache_path)) {
      res$status <- "MISSING"
      res$severity <- "CRITICAL"
      results[[c$path]] <- res
      next
    }

    mtime <- file.info(cache_path)$mtime
    mtime_lag <- as.integer(today - as.Date(mtime))

    # data freshness via date_col
    data_lag <- NA_integer_
    if (!is.null(c$date_col)) {
      # date_col 1개만 읽는다 (ccr_read_cols = col_select + 실패 시 전량 read 폴백).
      # 2026-07-26: 종전엔 parquet 전량 read 라, date_col 을 새로 선언한 대용량 패널
      # (nps_headcount_raw 6.47M행 × 11열 등)이 그대로 감사 비용이 됐다.
      dt <- ccr_read_cols(cache_path, c$date_col)
      if (!is.null(dt) && c$date_col %in% names(dt)) {
        # date_col_kind: "date"(기본) | "ym"("YYYY-MM") | "ym_compact"("YYYYMM")
        # date_semantics: "observation"(기본) | "period_end"(기간 라벨 — 음수 lag clamp)
        last_d <- suppressWarnings(max(ccr_to_date(dt[[c$date_col]], c$date_col_kind),
                                       na.rm = TRUE))
        if (length(last_d) == 1L && !is.na(last_d) && is.finite(as.numeric(last_d))) {
          data_lag <- ccr_lag_days(last_d, today, c$date_semantics)
          res$content_max_date <- format(last_d)
          res$lag_basis <- "content"
        }
      }
    }
    }

    #──────────────────────────────────────────────────────────────────────────
    # (2026-07-26 CFA-02 수리, probe② 감사 확정) 주석은 "Pick worse of" 인데 구현은
    #   data_lag 가 있으면 mtime_lag 를 **무조건 버렸다**. mtime > data 인 병리 케이스가
    #   실재한다(2026-07-26 실측 3건):
    #     .cache/macro_regime.parquet        data_lag=-5  mtime_lag=0
    #     .cache/unified_regime_signal.parquet data_lag=-5 mtime_lag=0
    #     .cache/factor_db/                  data_lag=0   mtime_lag=1
    #   forward-dated 캐시(예측 지평이 미래 날짜)는 생성기가 죽어도 지평 소진 + max_lag
    #   까지 음수/저 lag 로 FRESH 를 유지하고, 동결을 보여주는 유일한 축(mtime)이 폐기된다.
    #   → 주석대로 worse-of 구현. 음수 data_lag 는 0-clamp 후 비교(미래 날짜가 신선도를
    #   깎아주는 일 없게). 정상 monthly 캐시는 data_lag ≥ mtime_lag 라 판정 불변 —
    #   max() 는 병리 케이스에서만 엄격해진다(실측: 위 3건 전부 여전히 OK, 사각만 소거).
    #──────────────────────────────────────────────────────────────────────────
    data_lag_eval <- if (!is.na(data_lag)) max(0L, as.integer(data_lag)) else NA_integer_
    lag <- if (!is.na(data_lag_eval)) max(mtime_lag, data_lag_eval) else mtime_lag
    if (!is.na(data_lag) && !is.na(mtime_lag) && mtime_lag > data_lag_eval) {
      res$lag_note_worse_of <- sprintf(
        "mtime_lag(%d) > data_lag(%s) — mtime 축 채택(동결 감지). 구판은 data_lag 를 써서 이 상태를 신선으로 보고했다",
        mtime_lag, format(data_lag))
    }
    # tight-SLA daily 캐시(max_lag ≤ 7)는 거래일-기준 lag — 주말/휴장일 false-WARN 제거
    #   ★기준일은 채택된 lag 에 대응하는 날짜여야 한다(worse-of 로 mtime 이 채택됐는데
    #     today-data_lag 를 기준일로 쓰면 다시 data 축으로 되돌아간다).
    if (!is.na(data_lag) && isTRUE(c$schedule == "daily") &&
        !is.null(c$max_lag_days) && c$max_lag_days <= 7) {
      lag <- .trading_lag(today - lag, lag)
      # 합성 표기 — 내용 기준인지(content) 를 지우지 않는다
      res$lag_basis <- paste0(res$lag_basis %||% "mtime", "+trading_days")
    }
    res$mtime_lag <- mtime_lag
    res$data_lag <- data_lag
    res$lag_used <- lag
    if (is.null(res$lag_basis)) res$lag_basis <- "mtime"

    if (isTRUE(c$schedule == "on_demand")) {
      # [2026-07-14 Q] on_demand 캐시 = '요청 시 생성' 의미론 — stale 개념 부적용.
      #   신선도는 정보(lag 기록)로만 보고하고 severity는 최대 WARN(CRITICAL 승격 금지).
      #   근거: on_demand는 스케줄 갱신 대상이 아니라 소비 시점 생성물(예: legacy STR 전용
      #   ic_matrix). CRITICAL로 올리면 미가동이 상시 오탐 → 진짜 daily/monthly 신선도 신호를 가림.
      if (!is.null(c$max_lag_days) && !is.na(lag) && lag > c$max_lag_days) {
        res$status <- "ON_DEMAND_STALE"; res$severity <- "WARN"
      } else {
        res$status <- "ON_DEMAND"; res$severity <- "OK"
      }
    } else if (!is.null(c$max_lag_days) && !is.na(lag)) {
      warn_thresh <- c$max_lag_days * warn_lag_multiplier
      crit_thresh <- c$max_lag_days * critical_lag_multiplier
      if (lag <= c$max_lag_days) {
        res$status <- "FRESH"; res$severity <- "OK"
      } else if (lag <= crit_thresh) {
        res$status <- "STALE_WARN"; res$severity <- "WARN"
      } else {
        res$status <- "STALE_CRITICAL"; res$severity <- "CRITICAL"
      }
    } else {
      res$status <- "NO_THRESHOLD"; res$severity <- "OK"
    }

    # ─── 도달 축 선언 감사 (2026-07-26 P2-02/P2-03) ────────────────────────────
    #   "검사됐고 정상"과 "애초에 검사가 없어서 조용함"은 겉보기가 같다. 이 절이
    #   그 둘을 상태값으로 갈라놓는다. 스케줄 갱신 대상(on_demand 아님 + SLA 있음)만
    #   대상 — on_demand/SLA-null 은 stale 개념 자체가 부적용이라 소음이 된다.
    res$reach_declared <- ccr_reach_declaration(c)
    scheduled <- !isTRUE(c$schedule == "on_demand") && !is.null(c$max_lag_days)

    if (identical(res$lag_basis, "filename_month_end_estimate") && scheduled) {
      # 조용한 추정 금지 (P2-02). 내용을 한 번도 안 읽은 lag 은 OK 로 통과시키지 않는다.
      res$note <- paste0("파일명 YYYYMM 월말 추정 lag — 내용 미열람 (당월 파일이 어느 날짜에 ",
                         "얼어붙어도 lag=0). registry 에 date_col 선언 필요")
      if (identical(res$severity, "OK")) {
        res$status <- "FILENAME_ESTIMATE_ONLY"; res$severity <- "WARN"
      }
    } else if (is.na(data_lag) && scheduled) {
      # date_col 로 내용을 못 읽은 경우 = mtime 만 남았다 (P2-03).
      if (identical(res$reach_declared, "coverage_check")) {
        res$lag_basis <- "mtime(+coverage_check)"
        res$note <- "신선도는 mtime 축, 내용 도달은 <path>::coverage 항목이 판정"
      } else if (identical(res$reach_declared, "mtime_only_declared")) {
        res$lag_basis <- "mtime(declared)"
        res$note <- sprintf("내용 도달 축 미선언(명시) — %s",
                            c$no_content_check$reason %||% "(사유 미기재)")
        if (identical(res$status, "FRESH")) res$status <- "MTIME_ONLY"
      } else {
        res$lag_basis <- "mtime(undeclared)"
        res$note <- paste0("date_col / coverage_check / no_content_check 중 어느 것도 선언되지 ",
                           "않음 — mtime 만으로 판정 중이라 내용 결손(빈 파일·잘린 파일·과거만 ",
                           "담긴 파일)을 구조적으로 감지 못 함. registry 선언 필요")
        if (identical(res$severity, "OK")) {
          res$status <- "NO_COVERAGE_CHECK"; res$severity <- "WARN"
        }
      }
    }
    results[[c$path]] <- res
  }

  # ─── (1b) Value-sanity checks — registry value_checks 소비 (2026-07-03) ─────
  #   신선도와 독립인 별도 result 항목("<path>::value")으로 기록. 파일 자체가 없으면
  #   (1)의 MISSING/CRITICAL이 이미 커버하므로 스킵. parquet 전용 (col_select로
  #   필요 컬럼만 read — RAWDATA 417MB full-load 회피). 위반 시 CRITICAL.
  for (c in caches) {
    if (is.null(c$value_checks)) next
    cache_path <- file.path(PROJECT_ROOT, c$path)
    vres <- list(
      path = paste0(c$path, "::value"),
      tier = c$tier, schedule = c$schedule,
      registered = TRUE, check = "value_sanity"
    )
    if (!file.exists(cache_path) || !grepl("\\.parquet$", cache_path)) {
      vres$status <- "VALUE_SKIP"; vres$severity <- "OK"
      vres$note <- "파일 없음 또는 비-parquet — (1) freshness 결과 참조"
      results[[vres$path]] <- vres
      next
    }
    vc <- c$value_checks
    viol <- character(0)

    # 스키마 (lazy scan — full read 없이 컬럼명·물리타입만)
    sch <- tryCatch(arrow::open_dataset(cache_path)$schema, error = function(e) NULL)
    sch_names <- if (!is.null(sch)) sch$names else NULL

    # (a) required_cols — K200/KQ150 등 Layer2 컬럼 strip 사고 탐지
    if (!is.null(vc$required_cols)) {
      req <- unlist(vc$required_cols)
      if (is.null(sch_names)) {
        viol <- c(viol, "required_cols: 스키마 read 실패")
      } else {
        miss <- setdiff(req, sch_names)
        if (length(miss) > 0)
          viol <- c(viol, sprintf("required_cols 누락: %s", paste(miss, collapse = ",")))
        vres$required_cols_missing <- if (length(miss) > 0) miss else NULL
      }
    }

    # (a2) dtype_checks — on-disk 물리 타입 불변식 (2026-07-25)
    #   benchmark.parquet Date가 writer에 따라 date32[day] ↔ timestamp로 흔들려, Date-class를
    #   전제한 R 소비자의 by="Date" 조인이 경고 없이 전부 NA가 된 사고 재발 감지
    #   (fdb_daily phase7 β-파생 팩터 ~54개 전멸, 2026-07-18). 값·신선도는 정상이라
    #   기존 두 축(1)(1b a/b/c)이 구조적으로 못 잡는 실패 모드 — 물리 스키마만이 판별.
    #   실측 표기(2026-07-25): R Date-class·pa.date32() → "date32[day]" /
    #   R POSIXct → "timestamp[us, tz=UTC]" / pandas to_parquet → "timestamp[ns]".
    #   오염 표기가 writer마다 다르므로 blacklist가 아닌 기대값 일치로 판정한다.
    if (!is.null(vc$dtype_checks)) {
      if (is.null(sch)) {
        viol <- c(viol, "dtype_checks: 스키마 read 실패")
      } else {
        dmis <- character(0); obs <- character(0)
        for (cn in names(vc$dtype_checks)) {
          want <- vc$dtype_checks[[cn]]
          fld  <- tryCatch(sch$GetFieldByName(cn), error = function(e) NULL)
          got  <- if (is.null(fld)) NA_character_ else fld$type$ToString()
          obs[[cn]] <- got
          if (is.na(got)) {
            dmis <- c(dmis, sprintf("%s: 컬럼 부재", cn))
          } else if (!identical(got, want)) {
            dmis <- c(dmis, sprintf("%s: %s (기대 %s)", cn, got, want))
          }
        }
        vres$dtype_observed <- as.list(obs)
        if (length(dmis) > 0)
          viol <- c(viol, sprintf("dtype 불일치: %s", paste(dmis, collapse = "; ")))
      }
    }

    # 대상 컬럼 read helper — Date + 지정 컬럼만, 날짜별 unique (RAWDATA는
    # BM_Ret가 종목 행마다 반복이므로 날짜 단위로 축약)
    .read_date_col <- function(path, col) {
      if (is.null(sch_names) && path == cache_path) return(NULL)
      dt <- tryCatch(
        as.data.table(read_parquet(path, col_select = tidyselect::all_of(c("Date", col)))),
        error = function(e) NULL)
      if (is.null(dt) || !all(c("Date", col) %in% names(dt))) return(NULL)
      dt <- dt[!is.na(get(col))]
      dt[, Date := as.Date(Date)]
      unique(dt, by = "Date")[, .(Date, v = get(col))]
    }

    # (b) abs_ret_max — 값 폭주 (예: BM_Ret +581% 손상)
    if (!is.null(vc$abs_ret_max)) {
      arm <- vc$abs_ret_max
      d <- .read_date_col(cache_path, arm$col)
      if (is.null(d)) {
        viol <- c(viol, sprintf("abs_ret_max: 컬럼 %s read 실패", arm$col))
      } else {
        thr <- arm$threshold %||% 0.15
        max_v <- arm$max_violations %||% 0L
        n_bad <- d[abs(v) > thr, .N]
        vres$abs_ret_n_violations <- n_bad
        vres$abs_ret_max_abs <- round(max(abs(d$v), na.rm = TRUE), 4)
        if (n_bad > max_v) {
          bad_dates <- d[abs(v) > thr][order(-abs(v))][seq_len(min(5L, n_bad))]
          viol <- c(viol, sprintf("|%s|>%.2f %d건 (max=%.4f, 예: %s)",
                                  arm$col, thr, n_bad, vres$abs_ret_max_abs,
                                  paste(format(bad_dates$Date), collapse = ",")))
        }
      }
    }

    # (c) parity — 기준 캐시(benchmark.parquet) 대비 월수익 상관
    if (!is.null(vc$parity)) {
      pr <- vc$parity
      against_path <- file.path(PROJECT_ROOT, pr$against)
      d_self <- .read_date_col(cache_path, pr$col)
      d_ref  <- if (file.exists(against_path))
                  .read_date_col(against_path, pr$against_col %||% pr$col)
                else NULL
      if (is.null(d_self) || is.null(d_ref)) {
        viol <- c(viol, sprintf("parity: %s 또는 %s read 실패", c$path, pr$against))
      } else {
        m <- merge(d_self, d_ref, by = "Date", suffixes = c("_a", "_b"))
        # 대조 창 시작(선택). 2026-10-08 도훈 결정 DATA-SAT-CLOSE: 1990~98 토요장 구간은
        #   복원하지 않기로 종결 — 그 구간의 월요일 BM_Ret 정의 차이(토→월 vs 금→월)가
        #   전 구간 상관을 0.98 로 끌어내려 매일 CRITICAL 을 냈다(1999~ 상관 1.000000).
        if (!is.null(pr$from)) {
          m <- m[Date >= as.Date(pr$from)]
          vres$parity_from <- pr$from
        }
        if (nrow(m) < 60L) {
          viol <- c(viol, sprintf("parity: 공통 날짜 %d건 (<60) — 대조 불가", nrow(m)))
        } else {
          # 월수익 parity: log1p 합 기준 (데이터 무결성 대조용 — 백테스트 수익 합성 아님)
          m[, ym := format(Date, "%Y-%m")]
          mm <- m[, .(a = sum(log1p(pmax(v_a, -0.9999))),
                      b = sum(log1p(pmax(v_b, -0.9999)))), by = ym]
          mcor <- suppressWarnings(cor(mm$a, mm$b))
          vres$parity_monthly_cor <- round(mcor, 6)
          vres$parity_n_months <- nrow(mm)
          min_cor <- pr$min_monthly_cor %||% 0.99
          if (is.na(mcor) || mcor < min_cor)
            viol <- c(viol, sprintf("parity: 월수익 상관 %.4f < %.2f (vs %s)",
                                    mcor, min_cor, pr$against))
        }
      }
    }

    # (d) fill_rate — 값 열 채움률 (2026-09-23 W-02). ★위 (b)(c) 는 .read_date_col 이
    #   결측을 **먼저 지우고** 재므로 열이 100% 비어도 '위반 0' 이다 — Size 09-10~22 ·
    #   BM_Ret 09-07~ 전량 결측이 VALUE_PASS 였던 자리. 여기서는 최근 n_dates 거래일의
    #   열별 결측률(!is.finite)을 재고 max_na_rate 를 넘으면 위반. 판정 로직은
    #   rawdata_fill_guard.R 순수 함수 하나 — daily_refresh [1] 경보와 같은 코드다.
    if (!is.null(vc$fill_rate)) {
      fr_res <- tryCatch({
        if (!exists("rawdata_fill_rates"))
          source(file.path(PROJECT_ROOT, "02_Infrastructure/data/rawdata_fill_guard.R"))
        fspec <- rawdata_fill_spec_from(vc$fill_rate)
        have <- intersect(fspec$cols, sch_names %||% character(0))
        fdt <- as.data.table(read_parquet(cache_path,
                                          col_select = tidyselect::all_of(c("Date", have))))
        rawdata_fill_verdict(rawdata_fill_rates(fdt, fspec$cols, fspec$n_dates),
                             fspec$max_na_rate)
      }, error = function(e) list(status = "ERROR", error = conditionMessage(e)))
      if (identical(fr_res$status, "ERROR")) {
        viol <- c(viol, sprintf("fill_rate: 판독 실패 (%s)", fr_res$error))
      } else {
        vres$fill_rates <- fr_res$rates[, .(Date = as.character(Date), col, n, n_na,
                                            na_rate = round(na_rate, 6), present)]
        if (!identical(fr_res$status, "OK")) {
          fv <- fr_res$violations
          viol <- c(viol, sprintf("fill_rate: %s (max_na_rate=%s)",
                                  paste(sprintf("%s@%s=%s", fv$col, as.character(fv$Date),
                                                ifelse(fv$present, sprintf("%.4f", fv$na_rate), "열부재")),
                                        collapse = ","),
                                  format(fr_res$max_na_rate)))
        }
      }
    }

    if (length(viol) > 0) {
      vres$status <- "VALUE_FAIL"; vres$severity <- "CRITICAL"
      vres$note <- paste(viol, collapse = " | ")
    } else {
      vres$status <- "VALUE_PASS"; vres$severity <- "OK"
    }
    results[[vres$path]] <- vres
  }

  # ─── (1b2) 라벨-코호트 커버리지 — registry coverage_check 소비 (2026-07-26 P2-03) ──
  #   신선도(mtime/max Date)가 구조적으로 못 잡는 축: **회계 라벨로 색인된 캐시**.
  #   DART 재무제표는 Date 시계열이 없고(bsns_year), 파생 캐시의 Factor_Date 는 PIT
  #   usable date 라 max 가 미래(2027-03-31)다 — 어느 쪽도 "차 있나"를 답하지 못한다.
  #   실사고: fundamental_dart.parquet mtime 26일 → FRESH 인데 FY2025 corps 50 (정상 714),
  #   4개월간 무보고. 여기서는 "제출기한이 지난 최신 라벨이 직전 라벨 대비 차 있나"를 잰다.
  #   신선도와 독립인 별도 항목("<path>::coverage")으로 기록. 위반 = CRITICAL.
  for (c in caches) {
    if (is.null(c$coverage_check)) next
    cache_path <- file.path(PROJECT_ROOT, c$path)
    cres <- list(
      path = paste0(c$path, "::coverage"),
      tier = c$tier, schedule = c$schedule,
      registered = TRUE, check = "label_cohort_coverage"
    )
    if (!file.exists(cache_path)) {
      cres$status <- "COVERAGE_SKIP"; cres$severity <- "OK"
      cres$note <- "파일 없음 — (1) freshness 결과 참조"
      results[[cres$path]] <- cres
      next
    }
    cc <- tryCatch(ccr_coverage_check(c$coverage_check, path = cache_path, today = today),
                   error = function(e)
                     list(status = "COVERAGE_UNKNOWN", severity = "WARN",
                          note = sprintf("커버리지 판정 실행 실패: %s", conditionMessage(e)),
                          groups = list()))
    cres$status <- cc$status; cres$severity <- cc$severity
    cres$note <- cc$note; cres$groups <- cc$groups
    results[[cres$path]] <- cres
  }

  # ─── (1c) IC 월-프론티어 감시 (P3, 2026-07-26) ──────────────────────────────
  #   registry 엔트리 .cache/factor_db/factor_ic_monthly.parquet 의 신선도 축(Usable_Date
  #   캘린더 lag ≤ 40일)은 "며칠 지났나"만 잰다. 월말 재빌드 체인(cron → factor_db 월말
  #   스냅샷 → compute_all_factor_ic_monthly)이 통째로 실패해도 최대 ~5주간 FRESH 로
  #   통과한다 — 실측(2026-07-26): Usable_Date max 2026-06-30, lag 26 → FRESH.
  #   여기서는 같은 registry 엔트리에 "산출 가능한 월을 다 산출했나"(월-프론티어) 축을
  #   덧붙인다. 판정 규약 = compute_all_factor_ic_monthly() 의 incomplete-terminal-pair
  #   guard 와 동일 operand (달력 종료 · 그달 RAWDATA 최종 거래일) — 상세 및 유예 규칙은
  #   02_Infrastructure/data/ic_frontier_check.R 헤더 참조.
  #   당월 진행 중 전월 IC 가 최신인 상태는 정상(OK)으로 판정한다.
  if (is.null(caches_override)) tryCatch({
    source(file.path(PROJECT_ROOT, "02_Infrastructure/data/ic_frontier_check.R"))
    fr <- ic_frontier_check(today = today)
    results[[fr$path]] <- fr
  }, error = function(e) {
    results[[".cache/factor_db/factor_ic_monthly.parquet::frontier"]] <<- list(
      path = ".cache/factor_db/factor_ic_monthly.parquet::frontier",
      tier = 2L, schedule = "monthly", registered = TRUE,
      check = "ic_month_frontier",
      status = "IC_FRONTIER_UNKNOWN", severity = "WARN",
      note = sprintf("frontier check 실행 실패: %s", conditionMessage(e))
    )
  })

  # ─── (2) Orphan detection: .cache files NOT in registry ─────────────────────
  cache_dir <- file.path(PROJECT_ROOT, ".cache")
  # 주입 registry 에서는 orphan 개념이 성립하지 않는다(등록집합이 부분집합) → 스킵.
  if (is.null(caches_override) && dir.exists(cache_dir)) {
    all_files <- list.files(cache_dir, pattern = "\\.(parquet|csv|rds)$",
                             recursive = FALSE, full.names = FALSE)
    all_paths <- paste0(".cache/", all_files)
    orphans <- setdiff(all_paths, registered_paths)
    # Filter out known research/temp file patterns
    # 2026-06-26: 스크래치/임시 제외 강화 — 리서치 세션이 만드는 `_`-접두 임시 .rds/.csv,
    #   timestamp 백업(_YYYYMMDD_HHMMSS), *_corrupt_*, backfill audit 등은 데이터 소스가 아니라
    #   ephemeral → orphan 노이즈(WARN 118 중 ~110이 이것). `_`-접두 = ephemeral 컨벤션으로 제외.
    orphans <- orphans[!grepl("^\\.cache/(_|scout_|wt_|hr_v2|crisis_defense|stress_|factor_correlation|factor_overlap|factor_ic_|conditional_ic_|update_file_)",
                                orphans)]
    orphans <- orphans[!grepl("(_corrupt|_backup_|_[0-9]{8}_[0-9]{6}|backfill_v8_audit)", orphans)]
    # 2026-07-17 확장: vintage pin/백업 스냅샷(_pinYYYYMMDD/_bak_YYYYMMDD — 불변 스냅샷,
    #   신선도 개념 부적용, project-cache-vintage-pinning 보존 대상) + WT/렌즈/진단 리서치
    #   잔재(wtNNN_/lensN_/promote_diag_)를 orphan 노이즈에서 제외. 데이터 소스 아님.
    orphans <- orphans[!grepl("(_pin[0-9]{8}|_bak_[0-9]{8})", orphans)]
    orphans <- orphans[!grepl("^\\.cache/(wt[0-9]+_|lens[0-9]+_|promote_diag_)", orphans)]
    for (o in orphans) {
      results[[o]] <- list(
        path = o, tier = NA, schedule = NA,
        registered = FALSE,
        status = "ORPHAN",
        severity = "WARN",
        note = "registry에 등록되지 않은 cache — registry entry 추가 필요"
      )
    }
  }

  # ─── (3) Summary + persist ──────────────────────────────────────────────────
  by_sev <- list(
    OK       = sum(sapply(results, function(r) r$severity == "OK")),
    WARN     = sum(sapply(results, function(r) r$severity == "WARN")),
    CRITICAL = sum(sapply(results, function(r) r$severity == "CRITICAL"))
  )

  audit <- list(
    ran_at = format(today_ts, "%Y-%m-%dT%H:%M:%S%z"),
    n_total = length(results),
    summary = by_sev,
    results = unname(results)
  )

  if (isTRUE(persist)) {
    obs_dir <- file.path(PROJECT_ROOT, "qepm", "observability")
    dir.create(obs_dir, showWarnings = FALSE, recursive = TRUE)
    latest_path <- file.path(obs_dir, "cache_freshness_latest.json")
    write_json(audit, latest_path, pretty = TRUE, auto_unbox = TRUE, na = "null")

    # Append to daily log
    log_path <- file.path(PROJECT_ROOT, ".cache", "freshness_log.json")
    existing <- if (file.exists(log_path)) {
      tryCatch(jsonlite::fromJSON(log_path, simplifyVector = FALSE), error = function(e) list())
    } else list()
    existing[[length(existing) + 1L]] <- list(
      ran_at = audit$ran_at,
      summary = by_sev,
      crit_paths = sapply(Filter(function(r) r$severity == "CRITICAL", results), function(r) r$path),
      warn_paths = sapply(Filter(function(r) r$severity == "WARN", results), function(r) r$path)
    )
    if (length(existing) > 365) existing <- tail(existing, 365)  # 1 year cap
    write_json(existing, log_path, pretty = TRUE, auto_unbox = TRUE, na = "null")
  }

  # ─── (4) Telegram alert if WARN/CRITICAL ───────────────────────────────────
  cat(sprintf("\n=== Cache Freshness Audit (%s) ===\n", audit$ran_at))
  cat(sprintf("OK=%d WARN=%d CRITICAL=%d\n", by_sev$OK, by_sev$WARN, by_sev$CRITICAL))
  for (r in results) {
    if (r$severity %in% c("WARN", "CRITICAL")) {
      cat(sprintf("  [%s] %s (lag=%s, max=%s) %s\n",
                  r$severity, r$path,
                  r$lag_used %||% "n/a", r$max_lag_days %||% "n/a",
                  r$note %||% r$status))
    }
  }

  # ─── 알림 트리거 = 등록 캐시의 실제 stale/missing 만 (2026-06-26) ───────────
  # orphan(registry 미등재)은 데이터 노후가 아니라 registry 위생 이슈 → JSON 로그·콘솔엔 남기되
  #   "Cache Freshness Alert"(데이터 신선도 경보) 트리거에서는 제외. orphan 노이즈로 실질
  #   stale(예: factor_db_daily)이 묻히던 문제 해소. orphan 건수는 footnote 로만 통지.
  is_orphan <- function(r) isTRUE(r$status == "ORPHAN") || !isTRUE(r$registered)
  alert_items <- Filter(function(r) r$severity %in% c("WARN", "CRITICAL") && !is_orphan(r), results)
  n_orphan    <- sum(vapply(results, function(r) isTRUE(r$status == "ORPHAN"), logical(1)))
  alert_crit  <- sum(vapply(alert_items, function(r) r$severity == "CRITICAL", logical(1)))
  alert_warn  <- sum(vapply(alert_items, function(r) r$severity == "WARN", logical(1)))

  # ─── 반복알림 dedup (2026-07-17 도훈 지시 "왜 매번 같은 알림") ───────────────
  # 알림 집합(path:status) 서명이 직전 발송과 동일한 WARN-only 상태면 발송 억제.
  # 규칙: CRITICAL 존재 = 항상 발송 / 서명 변화 = 발송 / 동일 서명 = 7일마다 리마인더만.
  # 상태 파일: .cache/freshness_alert_state.json {signature, last_sent_at}
  alert_state_path <- file.path(PROJECT_ROOT, ".cache", "freshness_alert_state.json")
  alert_sig <- paste(sort(vapply(alert_items, function(r) paste0(r$path, ":", r$status),
                                  character(1))), collapse = "|")
  prev_state <- if (file.exists(alert_state_path)) {
    tryCatch(jsonlite::fromJSON(alert_state_path), error = function(e) NULL)
  } else NULL
  days_since_sent <- if (!is.null(prev_state$last_sent_at)) {
    as.numeric(difftime(today_ts, as.POSIXct(prev_state$last_sent_at), units = "days"))
  } else Inf
  send_reason <- if (alert_crit > 0) "critical"
    else if (is.null(prev_state) || !identical(prev_state$signature, alert_sig)) "changed"
    else if (days_since_sent >= 7) "weekly_reminder"
    else NA_character_

  if (telegram_alert && length(alert_items) > 0 && is.na(send_reason)) {
    cat(sprintf("[cache_freshness] 알림 집합 불변 (직전 발송 %.1f일 전) — 발송 억제 (7일 리마인더 대기)\n",
                days_since_sent))
  }

  # persist=FALSE (위반 주입 테스트)에서는 발송·상태쓰기 둘 다 금지 — 검사가 실제
  # 텔레그램을 쏘거나 dedup 서명을 오염시키면 그 검사는 부작용이지 증거가 아니다.
  telegram_alert <- isTRUE(telegram_alert) && isTRUE(persist)

  if (telegram_alert && length(alert_items) > 0 && !is.na(send_reason)) {
    tryCatch({
      source(file.path(PROJECT_ROOT, "02_Infrastructure/telegram/telegram_notify.R"))
      # note 동반 (2026-07-26): lag/max 만으로는 사유가 안 보이는 항목이 있다 —
      #   value_sanity(VALUE_FAIL)·ic_month_frontier 는 lag 축이 없어 "lag=n/a, max=n/a"
      #   로만 나가 무슨 일인지 알 수 없었다(조용한 실패). note 가 있으면 붙인다.
      #────────────────────────────────────────────────────────────────────────
      # (2026-08-16 CFA-05) Markdown 이스케이프 — 이 알림은 07-03~08-15 최소 20건이
      #   전부 HTTP 400 "can't parse entities" 로 거부됐다. 원인은 본문에 보간되는
      #   **파일 경로의 언더스코어**(stage_artifacts / method_frontier /
      #   firm_level_scaffold / nps_headcount_raw / BM_Ret …)가 legacy Markdown 의
      #   이탤릭 시작으로 읽혀, 아래 orphan_note 의 의도된 _..._ 짝과 어긋나는 것.
      #   실측 재구성: 언더스코어 17개(홀수) → 마지막 _ 가 byte offset 584 에서 미종결
      #   = API 가 지목한 오프셋과 정확히 일치.
      #   ⇒ 정적 서식(*bold*, _italic_)은 유지하고 **동적 값만** 이스케이프한다.
      #────────────────────────────────────────────────────────────────────────
      .md_esc <- function(x) gsub("([_*\\[`])", "\\\\\\1", as.character(x))
      .fmt_alert <- function(r) sprintf("- %s (lag=%s, max=%s)%s",
                                        .md_esc(r$path), r$lag_used %||% "n/a", r$max_lag_days %||% "n/a",
                                        if (!is.null(r$note)) paste0("\n  ", .md_esc(r$note)) else "")
      crit_list <- sapply(Filter(function(r) r$severity == "CRITICAL", alert_items), .fmt_alert)
      warn_list <- sapply(Filter(function(r) r$severity == "WARN", alert_items), .fmt_alert)
      orphan_note <- if (n_orphan > 0)
        sprintf("\n\n_(orphan %d건은 registry 미등재 — 로그만, 알림 제외)_", n_orphan) else ""
      reminder_tag <- if (identical(send_reason, "weekly_reminder"))
        "\n_(동일 상태 지속 — 주간 리마인더)_" else ""
      msg <- sprintf("🚨 *Cache Freshness Alert*\n\nCRITICAL %d / WARN %d (등록 캐시 stale 기준)\n\n*Critical:*\n%s\n\n*Warn:*\n%s%s%s",
                      alert_crit, alert_warn,
                      if (length(crit_list) > 0) paste(head(crit_list, 10), collapse = "\n") else "(none)",
                      if (length(warn_list) > 0) paste(head(warn_list, 10), collapse = "\n") else "(none)",
                      reminder_tag, orphan_note)
      #────────────────────────────────────────────────────────────────────────
      # (2026-08-16 CFA-06) 발송 결과를 **검사한다**. 구판은 tg_send 반환을 버리고
      #   무조건 alert_state 를 스탬프했다 — HTTP 400 은 R 에러가 아니므로 아래
      #   tryCatch(error=) 의 CFA-04 기록도 도달하지 못했다(실측: 400 거부된 런의
      #   latest JSON 에 alert_delivery 필드 자체가 부재). 결과는 "경보 채널이 죽었는데
      #   last_sent_at 은 배달된 것처럼 갱신" — 감시망 전체가 정상을 보고했다.
      #   ⇒ ①성패를 alert_delivery 에 남기고 ②실패면 서명 스탬프를 **보류**해서
      #     다음 런이 같은 상태를 '변화 없음'으로 삼키지 않게 한다.
      #────────────────────────────────────────────────────────────────────────
      .send <- tg_send(msg, parse_mode = "Markdown")
      .ok <- isTRUE(.send$ok)
      audit$alert_delivery <- if (.ok) "SENT" else
        sprintf("FAILED: status=%s %s", .send$status %||% "NA", substr(.send$error %||% "unknown", 1, 300))
      write_json(audit, latest_path, pretty = TRUE, auto_unbox = TRUE, na = "null")
      if (.ok) {
        write_json(list(signature = alert_sig,
                        last_sent_at = format(today_ts, "%Y-%m-%dT%H:%M:%S%z"),
                        reason = send_reason),
                   alert_state_path, auto_unbox = TRUE)
      } else {
        cat(sprintf("[cache_freshness][★] 경보 발송 실패 — alert_state 스탬프 보류(다음 런 재시도 대상): %s\n",
                    audit$alert_delivery))
      }
    }, error = function(e) {
      #────────────────────────────────────────────────────────────────────────
      # (2026-07-26 CFA-04 수리, probe② 감사 확정) 발송 실패를 cat 으로만 흘리면,
      #   stale 경보가 실재하는데 경보 채널이 죽은 상태가 **어느 표면에도** 남지 않는다
      #   (무인 백그라운드 잡의 stdout 은 아무도 안 본다 → 산출 JSON·exit 전부 정상으로 보임).
      #   경보 시스템 자신의 실패는 감시 대상이어야 한다 → latest JSON 에 기록하고
      #   부팅 DataFresh 리더가 읽어 노출한다(그 JSON 은 부팅이 이미 읽는다).
      #────────────────────────────────────────────────────────────────────────
      cat(sprintf("Telegram alert failed: %s\n", e$message))
      .adf <- sprintf("FAILED: %s", e$message)
      audit$alert_delivery <<- .adf
      tryCatch(write_json(audit, latest_path, pretty = TRUE,
                          auto_unbox = TRUE, na = "null"),
               error = function(e2)
                 cat(sprintf("alert_delivery 기록마저 실패: %s\n", e2$message)))
    })
  } else if (telegram_alert && length(alert_items) == 0) {
    cat(sprintf("[cache_freshness] 등록 캐시 전부 fresh — 알림 생략 (orphan %d건은 로그만)\n", n_orphan))
    # 상태 초기화: 다음 stale 재발 시 '변화'로 즉시 발송되도록 서명 리셋
    if (file.exists(alert_state_path) && !is.null(prev_state) &&
        !identical(prev_state$signature, "")) {
      write_json(list(signature = "", last_sent_at = prev_state$last_sent_at %||% NULL),
                 alert_state_path, auto_unbox = TRUE)
    }
  }

  invisible(audit)
}

`%||%` <- function(a, b) if (is.null(a)) b else a

cat("[cache_freshness_audit] Loaded.\n")
