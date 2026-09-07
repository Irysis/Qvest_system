#==============================================================================
# Incremental Update File — Update_File 증분 파서
#
# 03_Universe/Update_File/*_update.xlsx → RAWDATA/consensus/investor 증분 갱신
# QuantiWise 증분 도착 시 KRX/Naver 임시 데이터 완벽 교체
# Factor DB는 이 함수 완료 후에만 재빌드 (Level 0 규칙)
#
# ★★ OHLCVS 레인 = **퇴역 표기 (RETIRED for forward use) · 2026-09-07 도훈 지시** ★★
#   확정 구성: quantiwise(1990-01-05 ~ 2026-08-28) + naver 수정주가(2026-08-31 ~) **2단**.
#   즉 **가격의 전진(신규 거래일 적재)은 이제 naver_data_collector.R 이 진다.**
#   `incremental_ohlcvs()` 는 앞으로 정상 흐름에서 새 날짜를 만들지 않는다.
#
#   ▸ 남겨 두는 이유(삭제하지 않음):
#       ① **과거 데이터 재빌드** — base/증분 xlsx 에서 rawdata 를 다시 세울 때 필요하다.
#       ② 그 경로의 **이음매 가드**(아래 seam_scale_guard 블록)는 그대로 살아 있어야 한다.
#          두 수출본은 수정주가 조정기준이 달라 이어붙이면 분할 비율이 하루 수익률이 된다.
#       ③ 원장/라벨 축: rawdata 의 `source` 는 지우지 않는다 — 라벨이 **이음매의 지도**다.
#
#   ▸ **원천 우선순위 (도훈 지시 2026-09-07 — 위 열린 위험의 처분)**:
#     "퀀티와이즈가 있으면 최우선, 네이버는 최신 보충. 퀀티가 업데이트되면 네이버 데이터를
#      퀀티 기준으로 바꿔라." + 후속 확인('분할 종목이 5배 달라지는데?')에 "퀀티 그대로 덮기".
#     ⇒ naver 구간을 덮는 것은 **사고가 아니라 정상 경로**다. 판정은 코드가 아니라
#        `06_Registry/rawdata_source_priority.json` 이 낸다(부재 = stop).
#     ⇒ 막을 것은 덮기가 아니라 **"덮은 뒤 새 경계에서 조정기준 단절을 아무도 안 보는 상태"** 다.
#        그래서 교체 직후 `source` 전환점에서 이음매를 **재도출**해(날짜를 박지 않는다)
#        seam_scan_report 를 돌린다 — 퀀티가 부분만 덮으면 경계가 그만큼 이동한다.
#
# 사용법:
#   source("02_Infrastructure/incremental_update_file.R")
#   result <- incremental_update_all()  # 전체 자동
#   result <- incremental_ohlcvs()      # OHLCVS만 (퇴역 표기 — 재빌드 전용)
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(readxl)
})

if (!exists("PROJECT_ROOT")) source(file.path(dirname(dirname(sys.frame(1)$ofile %||% ".")), "config.R"))
if (!exists("is_trading_day")) source(file.path(DATA_DIR, "trading_calendar.R"))
# 원천 우선순위 정본 리졸버 — 병합 지점이 **설정을 경유**한다(부재 = stop, 하드코딩 금지)
if (!exists("rawdata_priority_decide")) source(file.path(DATA_DIR, "rawdata_source_priority.R"))

UPDATE_DIR <- file.path(PROJECT_ROOT, "03_Universe", "Update_File")
LAST_PROCESSED_FILE <- file.path(CACHE_DIR, "update_file_last_processed.rds")

# ─── Internal: 마지막 처리 시각 ──────────────────────────────────────────────
.get_last_processed <- function() {
  if (file.exists(LAST_PROCESSED_FILE)) readRDS(LAST_PROCESSED_FILE)
  else list(time = as.POSIXct("1970-01-01"), files = list())
}

.save_last_processed <- function(file_mtimes) {
  saveRDS(list(time = Sys.time(), files = file_mtimes), LAST_PROCESSED_FILE)
}

# ─── Internal: Update_File 변경 감지 ─────────────────────────────────────────
detect_update_changes <- function() {
  if (!dir.exists(UPDATE_DIR)) return(list(changed = character(0)))

  update_files <- list.files(UPDATE_DIR, pattern = "\\.xlsx$", full.names = TRUE)
  if (length(update_files) == 0) return(list(changed = character(0)))

  last <- .get_last_processed()
  changed <- character(0)
  current_mtimes <- list()

  for (f in update_files) {
    mt <- file.mtime(f)
    current_mtimes[[basename(f)]] <- mt
    prev_mt <- last$files[[basename(f)]]
    if (is.null(prev_mt) || mt > prev_mt) {
      changed <- c(changed, f)
    }
  }

  list(changed = changed, mtimes = current_mtimes)
}

# ─── OHLCVS 증분 ── ★퇴역 표기(전진 용도) 2026-09-07 ─────────────────────────
#   가격 전진 = naver_data_collector.R::naver_run_pipeline (수정주가 siseJson).
#   이 함수는 **과거 재빌드 전용**으로 남는다. 아래 seam_scale_guard 블록은 그 재빌드가
#   base/증분 두 수출본을 이어붙일 때 여전히 필요하므로 **건드리지 않는다**.
incremental_ohlcvs <- function() {
  ohlcvs_update <- file.path(UPDATE_DIR, "OHLCVS_update.xlsx")
  if (!file.exists(ohlcvs_update)) {
    cat("[incr_ohlcvs] OHLCVS_update.xlsx 없음. 스킵.\n")
    return(invisible(NULL))
  }

  cat("[incr_ohlcvs] OHLCVS_update.xlsx 증분 처리...\n")

  RAWDATA_CACHE <- file.path(CACHE_DIR, "rawdata.parquet")
  raw <- as.data.table(read_parquet(RAWDATA_CACHE))

  # base max date = OHLCVS.xlsx (base 파일)의 max date
  # Update_File은 항상 base 이후 전부 추출하여 교체
  base_ohlcvs <- file.path(PROJECT_ROOT, "03_Universe", "OHLCVS.xlsx")
  base_dates <- .extract_qw_dates(base_ohlcvs)
  base_max <- max(base_dates)
  cat(sprintf("  base max date (OHLCVS.xlsx): %s\n", base_max))

  # Update xlsx 파싱 (6 시트) — QT_to_xts 우회, 직접 파싱
  # (QT_to_xts는 xts의 TZ 변환에서 1일 밀림 버그 발생)
  var_names <- c("Open", "High", "Low", "Close", "Vol", "Size")
  all_long <- NULL

  for (i in seq_along(var_names)) {
    cat(sprintf("  Sheet %d/6: %s...\n", i, var_names[i]))
    raw_df <- as.data.frame(read_xlsx(ohlcvs_update, sheet = i, skip = 7,
                                       col_names = TRUE, na = c("", "NA")))
    # 첫 5행 스킵 (Name, Item Code, Unit, Base Date, D A T E)
    raw_df <- raw_df[-1:-5, ]

    # 첫 열 = Date serial, 나머지 = Ticker 값
    serials <- suppressWarnings(as.numeric(raw_df[[1]]))
    dates <- as.Date(serials, origin = "1899-12-30")

    ticker_cols <- names(raw_df)[-1]
    vals <- as.data.table(raw_df[, -1])
    vals <- vals[, lapply(.SD, as.numeric)]
    vals[, Date := dates]

    long <- melt(vals, id.vars = "Date", variable.name = "Ticker",
                 value.name = var_names[i], variable.factor = FALSE)
    long <- long[!is.na(Date) & Date > base_max]
    rm(raw_df, vals); gc()

    if (is.null(all_long)) {
      all_long <- long
    } else {
      all_long <- merge(all_long, long, by = c("Date", "Ticker"), all = TRUE)
    }
    rm(long); gc()
  }

  if (is.null(all_long) || nrow(all_long) == 0) {
    cat("  증분 데이터 없음.\n")
    return(invisible(NULL))
  }

  # 거래일 필터
  cal <- .load_calendar()
  before_n <- nrow(all_long)
  all_long <- all_long[Date %in% cal$Date]
  cat(sprintf("  거래일 필터: %d → %d rows\n", before_n, nrow(all_long)))

  # [guard 2026-07-11] 수출 이음매 검증 — update 최소일이 base 직후 거래일보다 뒤면
  # base/update 커버리지 사이에 구멍(실사고: base ~03-27 + update 04-30~ → 03-30~04-29
  # 소실, rawdata_april_gap_incident_20260711). rawdata가 그 구간을 보유하면 WARN만
  # (본 함수는 update 날짜만 교체하므로 데이터 안전), 미보유면 강한 경고.
  if (nrow(all_long) > 0) {
    upd_min <- min(all_long$Date)
    seam_days <- as.Date(cal[Date > base_max & Date < upd_min]$Date)
    if (length(seam_days) > 0) {
      seam_missing <- seam_days[!seam_days %in% unique(raw$Date)]
      cat(sprintf("  ⚠️ [이음매] base(~%s)와 update(%s~) 사이 거래일 %d일 — QuantiWise 수출 커버리지 구멍.\n",
                  base_max, upd_min, length(seam_days)))
      if (length(seam_missing) > 0) {
        cat(sprintf("  ⛔ [이음매] 그중 %d일은 rawdata에도 부재 (%s ~ %s) — KRX 백필 또는 QuantiWise 재수출(B5=%s) 필요!\n",
                    length(seam_missing), min(seam_missing), max(seam_missing),
                    format(base_max + 1, "%Y%m%d")))
      } else {
        cat("     rawdata는 해당 구간 보유 (KRX/Naver 수집분) — 데이터 안전. 근본 해소는 QuantiWise 재수출.\n")
      }
    }
  }

  # 유효 행만 (Close > 0)
  all_long <- all_long[!is.na(Close) & Close > 0]

  # source 태그
  all_long[, source := "quantiwise_update"]

  # 기존 RAWDATA에서 증분 구간의 임시 데이터 제거
  update_dates <- unique(all_long$Date)

  ## ★원천 우선순위 경유 (2026-09-07 도훈 지시 — **가드 방향 전환**) ─────────────
  ##  구판(같은 날 아침): "xlsx 가 naver 구간을 덮으면 stop, QVEST_ALLOW_BASIS_REGRESSION=1
  ##    로만 통과". 그 차단은 도훈 설계와 **반대**였다 — 퀀티가 정본이고, 퀀티가 덮는 것이
  ##    정상 경로다("퀀티 그대로 덮기").
  ##  신판: 누가 이기는지는 코드가 아니라 06_Registry/rawdata_source_priority.json 이 정한다.
  ##    ⇒ 이 경로의 incoming 은 항상 "quantiwise_update". 그보다 rank 가 낮은(=우선순위가
  ##       높은) 원천의 행은 **덮지 않고 보존**한다. 현행 표에서는 그런 원천이 없으므로
  ##       전량 교체가 정상 동작이고, 표를 바꾸면 판정이 따라 움직인다(설정 경유 실증).
  ##    ⇒ 막을 것은 덮기가 아니라 덮은 **뒤** 새 경계를 아무도 안 보는 상태다 —
  ##       Ret 재계산 다음 블록에서 이음매를 재도출해 재검사한다.
  .rsp_cfg <- rawdata_priority_config()
  if (!"source" %in% names(raw))
    stop("[incr_ohlcvs] rawdata 에 source 열이 없다 — 우선순위를 판정할 축이 없다(라벨이 이음매의 지도다)")
  .in_win <- raw$Date %in% update_dates
  .dec <- rawdata_priority_decide(raw$source[.in_win], "quantiwise_update",
                                  cfg = .rsp_cfg, context = "incr_ohlcvs",
                                  has_incumbent = TRUE)
  rawdata_priority_print(.dec, "incr_ohlcvs")
  .replace <- logical(nrow(raw)); .replace[which(.in_win)] <- .dec$allow %in% TRUE
  n_replaced  <- sum(.replace)
  n_preserved <- sum(.in_win) - n_replaced

  ## ★경계 재도출용 스냅샷 — 교체 **전** 의 source 지도. 날짜를 박지 않고 차집합으로 잡는다.
  .src_before <- raw[, .(Date, source)]

  raw <- raw[!.replace]
  cat(sprintf("  기존 데이터 교체: %s rows (날짜 %d일) · 우선순위로 보존 %s rows\n",
              format(n_replaced, big.mark = ","), length(update_dates),
              format(n_preserved, big.mark = ",")))
  .pri_side <- tryCatch(rawdata_priority_sidecar(list(
      merge_point = "incremental_update_file.R::incremental_ohlcvs",
      incoming_source = "quantiwise_update",
      update_dates = as.character(sort(update_dates)),
      n_rows_in_window = sum(.in_win), n_replaced = n_replaced, n_preserved = n_preserved,
      decisions = .dec[, .N, by = .(decision, incumbent_source, incoming_source)]),
      label = "incr_ohlcvs", cfg = .rsp_cfg),
    error = function(e) { cat(sprintf("  ⚠ [rawdata_priority] 사이드카 실패: %s\n",
                                      conditionMessage(e))); NA_character_ })
  if (!is.na(.pri_side)) cat(sprintf("  [rawdata_priority] 사이드카: %s\n", .pri_side))

  # Append
  # 컬럼 맞추기
  for (col in setdiff(names(raw), names(all_long))) {
    all_long[, (col) := NA]
  }
  for (col in setdiff(names(all_long), names(raw))) {
    raw[, (col) := NA]
  }
  common_cols <- intersect(names(raw), names(all_long))
  raw <- rbind(raw[, ..common_cols], all_long[, ..common_cols], fill = TRUE)

  # ── 우선순위 중복 해소 (교체 창 안) ─────────────────────────────────────────
  #   위 판정에서 **보존된** 행이 있으면 all_long 의 같은 (Date,Ticker) 와 중복이 된다.
  #   승자는 rank 가 정한다 — `unique()` 가 첫 행을 남긴다는 구현 사실에 얹지 않는다
  #   (그건 규칙이 아니라 우연이고, 행 순서가 바뀌면 판정이 뒤집힌다).
  .win_idx <- raw$Date %in% update_dates
  if (any(.win_idx)) {
    .ded <- rawdata_priority_dedup(raw[.win_idx], .rsp_cfg, context = "incr_ohlcvs/window")
    if (.ded$n_dropped > 0L) {
      cat(sprintf("  [rawdata_priority] 창 내 중복 %s행 해소 — 승자 rank 우선\n",
                  format(.ded$n_dropped, big.mark = ",")))
      print(.ded$dropped_by)
      raw <- rbind(raw[!.win_idx], .ded$dt, fill = TRUE)
    }
  }

  # ── [guard 2026-09-07 도훈 승인 A안 · 같은 날 방향 전환] 레벨 연속성 ────────
  # 위 커버리지 가드는 **날짜 구멍만** 본다. base 수출본(quantiwise)과 증분 수출본
  # (quantiwise_update), 그리고 naver 수정주가는 **조정기준이 서로 다르고**, 그 이음매를
  # 아래 `Close / shift(Close)` 로 가로지르면 분할·액면 비율이 그대로 하루 수익률이 된다.
  #   실측 2026-03-30: 2,548종 중 275종(10.8pct)이 |Ret| > 0.35, 최대 +7,863pct.
  #   배율이 5x·2x·10x·0.2x 로 군집(분할 지문)하고 인접일(03-27/03-31)은 0건.
  # ★판정은 Ret 재계산 **앞**에서, Close 만 보고 낸다(오염된 Ret 을 근거로 삼지 않는다).
  #
  # ★★경계를 날짜로 박지 않는다 (2026-09-07 방향 전환의 핵심).
  #   퀀티가 naver 구간을 **부분만** 덮으면 경계가 그만큼 이동한다:
  #     before  qw ~08-28 | naver 08-31~09-04           → 전환점 08-31
  #     after   qw ~09-02(08-31~09-02 덮음) | naver 09-03~09-04 → 전환점 **09-03**
  #   `min(update_dates)`(=08-31) 만 재면 이동한 경계 09-03 을 통째로 놓친다.
  #   그래서 교체 전/후 `source` 지도의 **차집합**으로 재도출하고, 예전 커버리지를 잃지
  #   않도록 min(update_dates) 를 항상 함께 훑는다(바닥은 유지, 이동분은 추가).
  seam_seeds <- tryCatch({
    source(file.path(DATA_DIR, "seam_scale_guard.R"))
    .chg <- seam_detect_changed(.src_before, raw)
    if (nrow(.chg)) {
      for (i in seq_len(nrow(.chg)))
        cat(sprintf("  [seam_guard] 경계 신설/이동: %s (%s -> %s)\n",
                    as.character(.chg$seam_date[i]), .chg$from[i], .chg$to[i]))
    } else cat("  [seam_guard] source 전환점 변화 없음 — min(update_dates) 만 훑는다\n")
    sort(unique(c(as.Date(min(update_dates)), as.Date(.chg$seam_date))))
  }, error = function(e) {
    cat(sprintf("  ⛔ [seam_guard] 경계 재도출 실패 (%s) — min(update_dates) 로 후퇴\n",
                conditionMessage(e)))
    as.Date(min(update_dates))
  })

  # ★for 는 Date 벡터를 numeric 으로 떨어뜨린다 — 인덱스로 돈다.
  seam_reps <- list(); seam_failed <- as.Date(character(0))
  for (k in seq_along(seam_seeds)) {
    sd_ <- seam_seeds[k]
    r <- tryCatch(seam_scan_report(raw, seam_scan_dates(raw, sd_)),
                  error = function(e) {
                    cat(sprintf("  ⛔ [seam_guard] 이음매 %s 판정 실패 (%s) — fail-closed\n",
                                as.character(sd_), conditionMessage(e)))
                    NULL })
    if (is.null(r)) {
      w <- tryCatch(seam_scan_dates(raw, sd_), error = function(e) sd_)
      seam_failed <- c(seam_failed, as.Date(w))
    } else seam_reps[[as.character(sd_)]] <- r
  }

  # Ret 재계산
  setorder(raw, Ticker, Date)
  raw[, Ret := Close / shift(Close) - 1, by = Ticker]

  for (nm in names(seam_reps)) {
    rp <- seam_reps[[nm]]
    raw <- seam_apply_actions(raw, rp)
    lbl <- sprintf("qwupdate_seam_%s", gsub("-", "", nm))
    seam_report_print(rp, lbl)
    cat(sprintf("  [seam_guard] 사이드카: %s\n", seam_write_sidecar(rp, lbl)))
  }
  if (length(seam_failed)) {
    # ★fail-closed 는 배관이 아니라 **측정**에 건다: 못 잰 경계의 창 전체 Ret NA.
    #   가드가 못 돌았는데 조용히 통과시키면 그것이 이 계통의 재발 기전이다.
    seam_failed <- sort(unique(seam_failed))
    raw[Date %in% seam_failed, Ret := NA_real_]
    cat(sprintf("  [seam_guard] 미측정 경계 %d일 Ret 전량 NA (%s) — 조용한 통과 금지\n",
                length(seam_failed), paste(as.character(head(seam_failed, 6)), collapse = ", ")))
  }
  if (!length(seam_reps) && !length(seam_failed))
    cat("  ⚠ [seam_guard] 판정도 실패도 없다 — 재검사가 실제로 돌았는지 확인 필요\n")

  # BM_Ret 매핑
  bm <- as.data.table(read_parquet(file.path(CACHE_DIR, "benchmark.parquet")))
  # [guard 2026-07-18] benchmark.parquet Date가 writer(naver_benchmark_update.py)에 따라
  # POSIXct(timestamp)일 수 있음 → Date-class인 raw$Date와 by="Date" 조인 시 silent all-NA →
  # RAWDATA.BM_Ret 14M행 전멸 후 write-back 위험. 양측 Date를 Date-class로 강제(build_cache/phase7 동일).
  bm[, Date := as.Date(Date)]
  raw[, Date := as.Date(Date)]
  raw[, BM_Ret := NULL]
  raw <- merge(raw, bm[, .(Date, BM_Ret)], by = "Date", all.x = TRUE)

  # 저장
  setorder(raw, Date, Ticker)
  write_parquet(raw, RAWDATA_CACHE)

  cat(sprintf("[incr_ohlcvs] 완료: %s rows | %s ~ %s\n",
              format(nrow(raw), big.mark = ","),
              min(raw$Date), max(raw$Date)))

  invisible(list(dates_updated = update_dates, rows = nrow(all_long)))
}

# ─── Consensus 증분 ──────────────────────────────────────────────────────────
incremental_consensus <- function() {
  cons_update <- file.path(UPDATE_DIR, "Consensus_update.xlsx")
  if (!file.exists(cons_update)) {
    cat("[incr_consensus] Consensus_update.xlsx 없음. 스킵.\n")
    return(invisible(NULL))
  }

  cat("[incr_consensus] Consensus_update.xlsx 증분 처리...\n")
  cons_cache_dir <- file.path(CACHE_DIR, "consensus")

  # 기존 캐시의 max date
  ref_file <- file.path(cons_cache_dir, "eps_1y.parquet")
  if (!file.exists(ref_file)) {
    cat("  기존 캐시 없음. base Consensus.xlsx부터 빌드 필요.\n")
    return(invisible(NULL))
  }
  ref <- as.data.table(read_parquet(ref_file))
  base_max <- max(ref$Date, na.rm = TRUE)
  cat(sprintf("  기존 캐시 max: %s\n", base_max))

  # Update_File을 임시 파싱 → base_max 이후만 추출 → 기존 캐시에 append
  source(file.path(DATA_DIR, "consensus_parser.R"))

  # 임시 디렉토리에 Update_File 파싱
  tmp_dir <- file.path(CACHE_DIR, "consensus_tmp")
  dir.create(tmp_dir, showWarnings = FALSE)

  old_cache <- CONSENSUS_CACHE
  CONSENSUS_CACHE <<- tmp_dir
  old_xlsx <- CONSENSUS_XLSX
  CONSENSUS_XLSX <<- cons_update

  tryCatch({
    consensus_build_cache(force = TRUE)

    # 각 metric의 증분만 기존 캐시에 append
    tmp_files <- list.files(tmp_dir, pattern = "\\.parquet$", full.names = TRUE)
    for (tf in tmp_files) {
      metric <- basename(tf)
      orig_file <- file.path(cons_cache_dir, metric)

      tmp_dt <- as.data.table(read_parquet(tf))
      new_rows <- tmp_dt[Date > base_max]

      if (nrow(new_rows) > 0 && file.exists(orig_file)) {
        orig_dt <- as.data.table(read_parquet(orig_file))
        # 겹치는 날짜 제거 후 append
        orig_dt <- orig_dt[!Date %in% unique(new_rows$Date)]
        combined <- rbind(orig_dt, new_rows, fill = TRUE)
        setorder(combined, Date)
        # [2026-06-17 fix] Windows arrow mmap-on-write 잠금(error 1224) 회피:
        #   read_parquet(orig)의 mmap을 rm+gc로 해제 후, temp 파일에 쓰고 rename으로 원자 교체.
        rm(orig_dt); gc()
        .tmp_out <- paste0(orig_file, ".tmp")
        write_parquet(combined, .tmp_out)
        if (file.exists(orig_file)) file.remove(orig_file)
        file.rename(.tmp_out, orig_file)
        cat(sprintf("  %s: +%d rows (max: %s)\n", metric, nrow(new_rows), max(combined$Date)))
      }
    }

    # 임시 디렉토리 정리
    unlink(tmp_dir, recursive = TRUE)
    cat("[incr_consensus] 증분 완료.\n")
  }, error = function(e) {
    cat(sprintf("[incr_consensus] 오류: %s\n", e$message))
    unlink(tmp_dir, recursive = TRUE)
  }, finally = {
    CONSENSUS_CACHE <<- old_cache
    CONSENSUS_XLSX <<- old_xlsx
  })
}

# ─── Investor_Act 증분 ───────────────────────────────────────────────────────
incremental_investor <- function() {
  inv_update <- file.path(UPDATE_DIR, "Investor_Act_update.xlsx")
  if (!file.exists(inv_update)) {
    cat("[incr_investor] Investor_Act_update.xlsx 없음. 스킵.\n")
    return(invisible(NULL))
  }

  cat("[incr_investor] Investor_Act_update.xlsx 증분 처리...\n")

  inv_cache_dir <- file.path(CACHE_DIR, "investor_stock")
  if (!dir.exists(inv_cache_dir)) dir.create(inv_cache_dir, recursive = TRUE)

  # 기존 캐시 max date
  all_file <- file.path(inv_cache_dir, "investor_all.parquet")
  if (file.exists(all_file)) {
    existing <- as.data.table(read_parquet(all_file))
    base_max <- max(existing$Date, na.rm = TRUE)
    cat(sprintf("  기존 캐시 max: %s (%s rows)\n", base_max, format(nrow(existing), big.mark = ",")))
  } else {
    existing <- NULL
    base_max <- as.Date("2026-03-27")
    cat(sprintf("  기존 캐시 없음. base_max: %s\n", base_max))
  }

  # 4시트 직접 파싱 (QT_to_xts 우회, 5행 스킵)
  sheet_map <- list("외인" = "Foreign", "기관" = "Institutional",
                    "개인" = "Individual", "기타법인" = "OtherCorp")
  all_new <- list()

  for (sheet_name in names(sheet_map)) {
    cat(sprintf("  시트 '%s'...\n", sheet_name))
    raw_df <- as.data.frame(read_xlsx(inv_update, sheet = sheet_name, skip = 7,
                                       col_names = TRUE, na = c("", "NA")))
    raw_df <- raw_df[-1:-5, ]  # 5행 스킵 (Update_File 공통 형태)

    serials <- suppressWarnings(as.numeric(raw_df[[1]]))
    dates <- as.Date(serials, origin = "1899-12-30")

    vals <- as.data.table(raw_df[, -1])
    vals <- vals[, lapply(.SD, as.numeric)]
    vals[, Date := dates]

    long <- melt(vals, id.vars = "Date", variable.name = "Ticker",
                 value.name = "NetBuy", variable.factor = FALSE)
    long <- long[!is.na(Date) & Date > base_max & !is.na(NetBuy) & NetBuy != 0]
    long[, InvestorType := sheet_map[[sheet_name]]]

    if (nrow(long) > 0) all_new[[length(all_new) + 1]] <- long
    cat(sprintf("    %d rows (> %s)\n", nrow(long), base_max))
    rm(raw_df, vals, long); gc()
  }

  if (length(all_new) == 0) {
    cat("  증분 데이터 없음.\n")
    return(invisible(NULL))
  }

  new_dt <- rbindlist(all_new)

  # 기존 캐시에 append (겹치는 날짜 교체)
  if (!is.null(existing)) {
    existing <- existing[!Date %in% unique(new_dt$Date)]
    combined <- rbind(existing, new_dt, fill = TRUE)
  } else {
    combined <- new_dt
  }
  setorder(combined, Date, Ticker, InvestorType)
  write_parquet(combined, all_file)

  # [2026-07-17 배관수리] 파생 파일 동반 재생성 — 기존엔 investor_all만 갱신되고
  # per-type 분리 파일(investor_foreign/institutional/individual/othercorp.parquet)과
  # investor_wide.parquet는 full 파서(parse_investor_act)에서만 쓰여 영구 stale
  # (실측: all=2026-07-01 vs 분리=2026-03-26 → flow_features_daily 113d stale의 원인).
  for (itype in unique(combined$InvestorType)) {
    split_path <- file.path(inv_cache_dir, sprintf("investor_%s.parquet", tolower(itype)))
    write_parquet(combined[InvestorType == itype], split_path)
  }
  wide <- dcast(combined, Date + Ticker ~ InvestorType, value.var = "NetBuy", fill = 0)
  write_parquet(wide, file.path(inv_cache_dir, "investor_wide.parquet"))
  cat(sprintf("  파생 재생성: 분리 %d종 + wide (max: %s)\n",
              uniqueN(combined$InvestorType), max(combined$Date)))

  cat(sprintf("[incr_investor] 완료: +%s rows → 총 %s rows (max: %s)\n",
              format(nrow(new_dt), big.mark = ","),
              format(nrow(combined), big.mark = ","),
              max(combined$Date)))
}

# ─── Universe_Support 증분 ───────────────────────────────────────────────────
# [2026-07-25 D1 수리] 구 구현은 parse_universe_support(us_update)를 force=FALSE로 호출 —
# 기존 캐시 존재 시 전 시트 "Cache hit" 스킵 = 증분 no-op이었고, force=TRUE로 바꾸면 merge
# 없이 update-기간만으로 통째 덮어쓰기 = 1990~ 역사 패널 소실. D1 우회(openpyxl 스트리밍 +
# 겹침날짜 교체 merge, 검증 PASS)를 표준 경로로 승격:
#   ① 파싱 = us_update_stream_parse.py (openpyxl read_only 스트리밍 조기종료 — update xlsx
#      시트 XML이 스타일 잔재로 420~560MB bloat라 openxlsx/readxl 통짜 로드는 메모리 리스크)
#   ② merge = incremental_investor()와 동형: existing[!Date %in% new_dates] + new rbind
#      (update 첫 스냅샷이 기존 종점과 겹쳐도 최신 export가 이김 — idempotent 재실행 안전)
#   ③ 스키마 = 디스크 시맨틱 컬럼명(Date/Ticker/K200 등) 기준 통일. legacy 'Value' 파일은
#      merge 시 시맨틱명으로 승격 저장
#   ④ 쓰기 = temp-rename (Windows arrow mmap 잠금 1224 회피 — incremental_consensus 06-17 패턴)
# 실패는 stop() 전파(fail-closed) — 구현 전처럼 삼켜서 no-op을 "완료"로 위장하지 않는다.
incremental_universe_support <- function(
    update_path = file.path(UPDATE_DIR, "Universe_Support_update.xlsx"),
    cache_dir   = UNIVERSE_SUPPORT_CACHE,
    parser_py   = file.path(DATA_DIR, "us_update_stream_parse.py"),
    py_exec     = NULL
) {
  if (!file.exists(update_path)) {
    cat("[incr_universe_support] Universe_Support_update.xlsx 없음. 스킵.\n")
    return(invisible(NULL))
  }
  cat("[incr_universe_support] Universe_Support_update.xlsx 증분 처리...\n")

  # 시트 메타(UNIVERSE_SUPPORT_SHEET_META)만 필요 — 전체 파서는 호출하지 않는다
  if (!exists("UNIVERSE_SUPPORT_SHEET_META")) source(file.path(DATA_DIR, "parse_universe_support.R"))
  if (!file.exists(parser_py)) stop("[incr_universe_support] 파서 부재: ", parser_py)

  # ① Python 스트리밍 파싱 → stage CSV (QVEST_PY = openpyxl 보유 확인됨. pyarrow 불요)
  if (is.null(py_exec)) {
    py_candidates <- c(Sys.getenv("QVEST_PY", ""),
                       file.path(PROJECT_ROOT, ".venv_qvest_ml/Scripts/python.exe"))
    py_candidates <- py_candidates[nzchar(py_candidates) & file.exists(py_candidates)]
    if (length(py_candidates) == 0)
      stop("[incr_universe_support] python 실행경로 미발견 (QVEST_PY / .venv_qvest_ml)")
    py_exec <- py_candidates[1]
  }
  stage_dir <- file.path(tempdir(), paste0("us_incr_", format(Sys.time(), "%Y%m%d_%H%M%S")))
  dir.create(stage_dir, recursive = TRUE, showWarnings = FALSE)
  on.exit(unlink(stage_dir, recursive = TRUE), add = TRUE)

  # env= 미사용 (Windows system2 env는 인자 주입 트랩) — 경로는 argv로 전달
  py_out <- suppressWarnings(system2(py_exec,
              args = c(shQuote(parser_py), shQuote(update_path), shQuote(stage_dir)),
              stdout = TRUE, stderr = TRUE))
  py_status <- attr(py_out, "status"); if (is.null(py_status)) py_status <- 0L
  cat(paste0("  py| ", py_out, collapse = "\n"), "\n")
  if (py_status != 0 || !any(grepl("PARSE_OK", py_out)))
    stop("[incr_universe_support] 스트리밍 파싱 실패 (exit=", py_status,
         ", PARSE_OK 센티널 부재) — 증분 중단")

  # ② 시트별 merge (겹침 날짜 교체 후 rbind) + ④ temp-rename 쓰기
  n_merged <- 0L
  for (s in names(UNIVERSE_SUPPORT_SHEET_META)) {
    meta    <- UNIVERSE_SUPPORT_SHEET_META[[s]]
    vcol    <- meta$value_col
    new_csv <- file.path(stage_dir, sprintf("us_new_%s.csv", meta$cache_name))
    pq_path <- file.path(cache_dir, sprintf("us_%s.parquet", meta$cache_name))

    if (!file.exists(new_csv)) {
      cat(sprintf("  ⚠ %s: 파서 산출물 부재 — 스킵\n", meta$cache_name)); next
    }
    if (!file.exists(pq_path)) {
      cat(sprintf(paste0("  ⚠ %s: 기존 패널 부재 — update xlsx(증분 기간만)로는 역사 패널을 만들 수 없음. ",
                         "base Universe_Support.xlsx로 parse_universe_support() 선행 필요. 스킵.\n"),
                  meta$cache_name)); next
    }

    new_dt <- fread(new_csv, encoding = "UTF-8", colClasses = "character")
    if (nrow(new_dt) == 0) { cat(sprintf("  ⚠ %s: 신규 0행 — 스킵\n", meta$cache_name)); next }
    if (!identical(names(new_dt), c("Date", "Ticker", vcol)))
      stop(sprintf("[incr_universe_support] %s: 파서 CSV 헤더 불일치: %s",
                   meta$cache_name, paste(names(new_dt), collapse = ",")))
    new_dt[, Date := as.Date(Date)]
    if (meta$value_type == "numeric") new_dt[, (vcol) := as.numeric(get(vcol))]

    existing <- as.data.table(read_parquet(pq_path))
    setnames(existing, "Value", vcol, skip_absent = TRUE)   # legacy 'Value' 스키마 → 시맨틱명 승격
    existing[, Date := as.Date(Date)]                        # timestamp 혼입 방어 (date32 통일)
    if (!identical(sort(names(existing)), sort(names(new_dt))))
      stop(sprintf("[incr_universe_support] %s: 스키마 불일치 existing={%s} vs new={%s}",
                   meta$cache_name, paste(names(existing), collapse = ","),
                   paste(names(new_dt), collapse = ",")))

    upd_dates  <- unique(new_dt$Date)
    n_prev     <- nrow(existing)
    max_prev   <- max(existing$Date)
    n_replaced <- existing[Date %in% upd_dates, .N]
    combined   <- rbind(existing[!Date %in% upd_dates], new_dt, use.names = TRUE)
    setorder(combined, Date, Ticker)

    rm(existing); gc()                       # mmap 해제 후 temp-rename
    tmp_out <- paste0(pq_path, ".tmp")
    write_parquet(combined, tmp_out)
    if (file.exists(pq_path)) file.remove(pq_path)
    file.rename(tmp_out, pq_path)

    cat(sprintf("  %s: %s → %s rows (겹침교체 %s | 신규날짜 %d개 %s~%s | 기존 max %s)\n",
                meta$cache_name, format(n_prev, big.mark = ","),
                format(nrow(combined), big.mark = ","), format(n_replaced, big.mark = ","),
                length(upd_dates), min(upd_dates), max(upd_dates), max_prev))

    # 멤버십 sanity (K200 ~200 / KQ150 ~150) — warn-only, 원본 export 이상 조기 가시화
    if (vcol %in% c("K200", "KQ150")) {
      exp_n <- if (vcol == "K200") 200 else 150
      chk <- new_dt[, .(msum = sum(get(vcol), na.rm = TRUE)), by = Date]
      for (j in seq_len(nrow(chk)))
        cat(sprintf("    %s %s: sum=%g\n", vcol, chk$Date[j], chk$msum[j]))
      bad <- chk[abs(msum - exp_n) > exp_n * 0.25]
      if (nrow(bad) > 0)
        cat(sprintf("  ⚠ %s: 멤버십 합 이상(기대 ~%d): %s — 원본 export 확인 필요\n",
                    vcol, exp_n, paste(sprintf("%s=%g", bad$Date, bad$msum), collapse = ", ")))
    }
    n_merged <- n_merged + 1L
    rm(combined, new_dt); gc()
  }

  if (n_merged == 0L) {
    cat("[incr_universe_support] ⚠ merge된 시트 0개 — 증분 미반영. 위 스킵 사유 확인 필요.\n")
  } else {
    cat(sprintf("[incr_universe_support] 완료: %d/%d 시트 merge.\n",
                n_merged, length(UNIVERSE_SUPPORT_SHEET_META)))
  }
  invisible(list(n_merged = n_merged))
}

# ─── 전체 증분 실행 ──────────────────────────────────────────────────────────
incremental_update_all <- function() {
  cat("=== Incremental Update_File 처리 시작 ===\n\n")

  changes <- detect_update_changes()
  if (length(changes$changed) == 0) {
    cat("Update_File 변경 없음.\n")
    return(invisible(list(updated = FALSE)))
  }

  cat(sprintf("변경 감지: %d 파일\n", length(changes$changed)))
  for (f in changes$changed) cat(sprintf("  → %s\n", basename(f)))
  cat("\n")

  ohlcvs_result <- NULL
  qw_updated <- FALSE

  # OHLCVS
  if (any(grepl("OHLCVS", changes$changed))) {
    ohlcvs_result <- incremental_ohlcvs()
    qw_updated <- TRUE
  }

  # Consensus
  if (any(grepl("Consensus", changes$changed))) {
    incremental_consensus()
    qw_updated <- TRUE
  }

  # Investor_Act
  if (any(grepl("Investor", changes$changed))) {
    incremental_investor()
  }

  # Universe_Support
  if (any(grepl("Universe_Support", changes$changed))) {
    incremental_universe_support()
  }

  # 처리 완료 기록
  .save_last_processed(changes$mtimes)

  cat("\n=== Incremental Update 완료 ===\n")
  invisible(list(updated = TRUE, qw_updated = qw_updated, ohlcvs = ohlcvs_result))
}

cat("[incremental_update_file] Loaded. Functions: incremental_update_all(), incremental_ohlcvs(), detect_update_changes()\n")
