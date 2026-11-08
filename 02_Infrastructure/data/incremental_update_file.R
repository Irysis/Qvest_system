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
#   ▸ **적재 안전 관문 (2026-09-23 · 적대 검증 [높음])** — `ohlcvs_update_gate()`:
#     qw_refresh.ps1 은 목표일 도달 판정 **전에** $wb.Save() 하고 finally 에서 Close($true) 로 또 저장한다.
#     ⇒ 갱신이 실패·중단돼도 xlsx mtime 이 바뀌고, 다음 [0b] 가 그 파일을 '변경' 으로 적재했다.
#       지평선이 그대로(08-28)여도 아래 Ret 재계산(Close/shift(Close)-1)이 전 이력을 다시 계산해
#       naver 이음매(08-31) Ret 을 조정기준 단절 그대로 되살린다(실측 1,715행 · A001470 +1,577%) —
#       source 전환점이 안 움직이므로 seam 재검사도 그 경계를 훑지 않는다.
#     관문(하나라도 실패 = 적재 거부 · RAWDATA 무접촉 · '처리 완료' 미기록 → 다음 정상 갱신 때 재시도):
#       sheet_order        — 앞 6시트가 Open·High·Low·Close·Vol·Size 순서(적재 루프가 **번호로** 읽는다)
#       sheet_read_error   — 시트 A열 판독 실패
#       date_axis_missing  — 값 시트에 'D A T E' 날짜축이 없거나 날짜 0개
#       horizon_mismatch   — 날짜축 시트(DATA_Key 처럼 날짜축 없는 시트는 제외)의 A열 마지막 날짜가 서로 다름
#       prior_unmeasured   — 직전 적재 지평선(RAWDATA source ∈ quantiwise·quantiwise_update 의 max Date) 미측정
#       not_advanced       — 공통 지평선 ≤ 직전 적재 지평선(전진 없음)
#         ★예외 '새 자료 없음'(2026-11-09 · 도훈 승인): 지평선 = 직전 적재 ∧ 값 6시트의 B6 괄호(질의 종료일 · CPD-1TD) = 지평선이면
#           주말 · 휴일 밤의 정상 재저장이다(OHLCVS 는 '이미 완료' 판정 없이 밤마다 다시 받는다 · qw_refresh.ps1 anchor=qw_base).
#           거부가 아니다 — 적재 0 · RAWDATA 무접촉 · 처리 완료 기록 · rc 0. B6 가 지평선보다 뒤 · B6 미해석 · 지평선이 뒤로 감
#           = 지금처럼 not_advanced 거부(받아야 할 날을 못 받은 저장). B6 는 지평선 = 직전 적재일 때만 탐침으로 읽는다
#           (.uf_probe_book — F4 머리 관문과 같은 판독 · 그 밖의 날엔 추가 비용 0). 구판은 이 경우도 거부해 r2(rc=3)를 냈다
#           (11-09 월 첫 관측 · 주마다 월 · 화 아침 반복 예상) — 같은 단계의 진짜 거부(지표 DB 3개)가 실패 서명(dr_fail_signature.R —
#           rc 를 지운 단계 이름)에 묻힌다.
#       horizon_row_empty  — (파싱 후) 지평선 날짜 행에 값이 0칸인 값 시트
#     거부 시 incremental_update_all() 은 나머지 파일을 처리·기록한 뒤 **stop()** → Rscript rc≠0(2026-11-06 부터 rc 3 —
#     아래 ▸rc 계약) → daily_refresh.sh run_r 이 DR_FAILED 에 싣는다(로그 표지 `[GATE_REFUSED]`). 판정 기록 = .cache/update_file_ohlcvs_gate.json
#     qw_refresh.ps1(단말 드라이버)은 고치지 않는다 — 드라이버가 무엇을 저장하든 적재 쪽에서 막는다.
#
#   ▸ **수급 · 컨센서스 · 유니버스 적재 수리 (2026-11-06 · F3 · F4 · F5)** — 계획서
#     04_Research/01_reports/quantiwise_data_expansion_20261106/PLAN.md §3.0 · §3.5 · 시험 08_Tests/data/test_incremental_update_gates.R
#     F3 받은 창의 날짜 = 교체: 컨센서스는 eps_1y 하나의 max 이후만 12지표에 붙였고(뒤처진 지표의 날은 영구 손실 — 4지표 10-19),
#        수급은 패널 전체 max 이후만 붙였다(한 유형만 빈 10-20~10-30 은 다시 받아도 'Date > max' 에 걸린다). 지금은
#        출력(지표 · 유형 · 시트)마다 '이번 xlsx 가 받은 날짜'의 기존 행을 지우고 새 행을 넣는다(유니버스 적재기와 같은 규약).
#        ★2차(같은 날 · 독립 검증 지적): 수급 1차 판은 4유형 창의 **합집합**으로 지워, 시트 창이 다르면 그 날짜를 받지 않은
#          유형의 행을 대체 없이 잃었다 → 유형 × 그 유형의 받은 창으로 교체. 관문 ②에 window_empty(받은 창 0일인 출력)를 더해
#          머리 판정 date_axis_missing 한 줄이 유일한 방어선이던 상태를 없앴다. 컨센서스 · 유니버스는 이미 출력별이었다(확인).
#     F4 공용 적재 관문(아래 ─── 공용 적재 관문 절): 머리(탐침 — 시트 · 지평선 일치 · B6 괄호 ≥ 목표일) + 채움비
#        (그날 채움 수 / 직전 W 축 날짜 중앙값 ≥ 그 항목 이력에서 산출한 문턱). 거부 = 그 책 적재 0 · 캐시 무접촉 · 처리 미기록.
#     F5 이름 → 적재기 명시 표(완전 일치) 디스패치: 미등록 xlsx = 경고 · 처리 미기록(매 실행 다시 경고) · 이름에 부분 문자열이
#        들었다고 엉뚱한 적재기를 돌리지 않는다(구판 grepl("Consensus") 등).
#   ▸ **rc 계약 (incremental_update_all · daily_refresh.sh run_r 이 그대로 받는다)**: 0 정상(OHLCVS '새 자료 없음' 포함) · 3 관문 거부(적재 0 · 다음 갱신 때 재시도) ·
#     4 미등록 xlsx 만 있음 · 1 그 밖의 오류. run_r 은 0 이 아니면 DR_FAILED 에 'r<N>(rc=…)' 를 싣고 체인을 계속한다(호출부 무변경).
#     거부 · 미등록은 전부 처리 · 기록한 **뒤** 끝에서 R 오류로 알린다 — 잡히면(tryCatch · 시험) 평범한 오류이고,
#     비대화형에서 잡히지 않고 끝나면 options(error=) 가 그 종료 코드로 내보낸다(대화형 세션은 끄지 않는다).
#
# 사용법:
#   source("02_Infrastructure/incremental_update_file.R")
#   result <- incremental_update_all()  # 전체 자동 (거부 · 미등록 = 끝에서 오류 · Rscript 종료 코드 3/4)
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
OHLCVS_GATE_RECORD  <- file.path(CACHE_DIR, "update_file_ohlcvs_gate.json")   # 관문 판정 기록(처리 상태 아님)

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
  # ★엑셀 소유자 잠금 파일(~$Name.xlsx)은 데이터가 아니다 (2026-09-19 실사고):
  #   퀀티 갱신기가 Consensus_update.xlsx 를 연 사이 '~$Consensus_update.xlsx' 가 새 파일로 잡혀
  #   grepl("Consensus") 가 참 → **아직 갱신 중인 옛 파일**로 컨센서스 적재가 돌았다.
  update_files <- update_files[!startsWith(basename(update_files), "~$")]
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

# ─── OHLCVS 적재 안전 관문 (2026-09-23) — 머리 주석 ▸적재 안전 관문 참조 ─────────
#   값 시트 목록 = 아래 적재 루프가 **번호로** 읽는 순서 그대로(루프도 이 상수를 쓴다 — 두 벌 금지).
.OHLCVS_VAR_SHEETS <- c("Open", "High", "Low", "Close", "Vol", "Size")
#   직전 적재 지평선의 출처 라벨 = 퀀티 수출본(base·증분). naver 는 퀀티 지평선이 아니다.
.OHLCVS_QW_SOURCES <- c("quantiwise", "quantiwise_update")

#' 시트별 A열 날짜축 지평선 — 'D A T E' 라벨 행 아래의 Excel serial 만 날짜로 센다.
#'   (위쪽 머리 셀 'Refresh'=0 같은 숫자를 날짜로 세지 않는다: serial 0 = 1899-12-30)
#' @return data.table(pos, sheet, date_axis, n_dates, horizon, last_row_date, err)
ohlcvs_sheet_horizons <- function(xlsx) {
  sh <- readxl::excel_sheets(xlsx)
  rbindlist(lapply(seq_along(sh), function(i) {
    a <- tryCatch(suppressWarnings(readxl::read_xlsx(xlsx, sheet = i, range = readxl::cell_cols("A:A"),
                                                     col_names = FALSE, col_types = "text",
                                                     .name_repair = "minimal")),
                  error = function(e) e)
    if (inherits(a, "error"))
      return(data.table(pos = i, sheet = sh[i], date_axis = NA, n_dates = NA_integer_,
                        horizon = as.Date(NA), last_row_date = as.Date(NA), err = conditionMessage(a)))
    lab <- if (ncol(a)) trimws(as.character(a[[1]])) else character(0)
    r <- which(lab == "D A T E")[1]
    if (is.na(r))
      return(data.table(pos = i, sheet = sh[i], date_axis = FALSE, n_dates = 0L,
                        horizon = as.Date(NA), last_row_date = as.Date(NA), err = NA_character_))
    d <- as.Date(suppressWarnings(as.numeric(lab[-seq_len(r)])), origin = "1899-12-30")
    d <- d[!is.na(d)]
    data.table(pos = i, sheet = sh[i], date_axis = TRUE, n_dates = length(d),
               horizon = if (length(d)) max(d) else as.Date(NA),
               last_row_date = if (length(d)) d[length(d)] else as.Date(NA), err = NA_character_)
  }))
}

#' 직전 적재 지평선 = RAWDATA 에서 퀀티 출처 행의 max(Date). 판독 불가·0행 = NA(미측정 — 통과로 접지 않는다).
.ohlcvs_prior_horizon <- function(rawdata_path, sources = .OHLCVS_QW_SOURCES) {
  if (!file.exists(rawdata_path)) return(as.Date(NA))
  r <- tryCatch(as.data.table(read_parquet(rawdata_path, col_select = c("Date", "source"), mmap = FALSE)),
                error = function(e) NULL)
  if (is.null(r) || !all(c("Date", "source") %in% names(r))) return(as.Date(NA))
  d <- as.Date(r$Date[r$source %in% sources])
  rm(r); gc(verbose = FALSE)
  d <- d[!is.na(d)]
  if (!length(d)) as.Date(NA) else max(d)
}

#' 관문 판정(순수 함수) — 전부 계산하고(조기 종료 없음) 사유를 이름 붙여 남긴다.
#' @param hz  ohlcvs_sheet_horizons() 결과 · @param prior_horizon Date(NA 가능)
#' @param b6  (선택) .uf_probe_book()$sheets — 시트별 B6 괄호 날짜(b6_date = 질의 종료일). '새 자료 없음' 판정에만 쓴다.
#' @return list(ok, skip, reasons = named character, horizon, prior_horizon, sheets = hz, note)
#'   skip = '새 자료 없음'(머리 주석 ▸적재 안전 관문 not_advanced ★예외) — 그때 ok = FALSE · reasons 빈 값 · note = 사유.
ohlcvs_update_gate <- function(hz, prior_horizon, required = .OHLCVS_VAR_SHEETS, b6 = NULL) {
  rs <- character(0)
  add <- function(k, msg) rs[[k]] <<- msg
  hz <- as.data.table(hz)
  head_names <- hz$sheet[seq_len(min(nrow(hz), length(required)))]
  if (!identical(head_names, required))
    add("sheet_order", sprintf("앞 %d시트 = %s (요구 %s — 적재 루프가 번호로 읽는다)", length(required),
                               paste(head_names, collapse = ","), paste(required, collapse = ",")))
  if (any(!is.na(hz$err)))
    add("sheet_read_error", paste(sprintf("%s: %s", hz$sheet[!is.na(hz$err)], hz$err[!is.na(hz$err)]), collapse = " | "))
  req <- hz[sheet %in% required]
  bad_axis <- req[!(date_axis %in% TRUE) | !(n_dates > 0L)]$sheet
  bad_axis <- c(bad_axis, setdiff(required, hz$sheet))
  if (length(bad_axis))
    add("date_axis_missing", sprintf("값 시트 날짜축 없음/0일: %s", paste(unique(bad_axis), collapse = ",")))
  ax <- hz[date_axis %in% TRUE & n_dates > 0L]
  hzs <- unique(ax$horizon)
  common <- if (length(hzs) == 1L) hzs else as.Date(NA)
  if (length(hzs) != 1L)
    add("horizon_mismatch", if (!length(hzs)) "날짜축 시트 0개" else
      sprintf("시트별 지평선 불일치: %s", paste(sprintf("%s=%s", ax$sheet, format(ax$horizon)), collapse = ",")))
  prior_horizon <- as.Date(prior_horizon)
  no_new <- FALSE; note <- NA_character_
  if (length(prior_horizon) != 1L || is.na(prior_horizon)) {
    add("prior_unmeasured", "직전 적재 지평선(RAWDATA 퀀티 출처 max Date) 미측정 — 전진 여부 판정 불가")
  } else if (!is.na(common) && common <= prior_horizon) {
    ## '새 자료 없음' = 다른 사유 0 ∧ 지평선 = 직전 적재 ∧ 값 시트 전부 B6 = 지평선. 하나라도 아니면 지금처럼 거부한다.
    b6d <- as.Date(if (is.null(b6)) rep(NA, length(required)) else b6$b6_date[match(required, b6$sheet)])
    no_new <- !length(rs) && common == prior_horizon && !anyNA(b6d) && all(b6d == common)
    if (no_new) {
      note <- sprintf("새 자료 없음 — 공통 지평선 %s = 직전 적재 = 값 시트 B6(질의 종료일) · 적재 생략(실패 아님)", format(common))
    } else {
      add("not_advanced", sprintf("공통 지평선 %s ≤ 직전 적재 %s — 갱신이 전진하지 않았다(실패·중단 저장 의심) · B6 %s",
                                  format(common), format(prior_horizon),
                                  if (all(is.na(b6d))) "미확인" else paste(sprintf("%s=%s", required, format(b6d, "%Y%m%d")), collapse = ",")))
    }
  }
  list(ok = !length(rs) && !no_new, skip = no_new, reasons = rs, horizon = common,
       prior_horizon = if (length(prior_horizon) == 1L) prior_horizon else as.Date(NA), sheets = hz, note = note)
}

#' 파싱 후 보강 판정 — 지평선 날짜 행에 값이 0칸인 값 시트(날짜만 늘고 값이 빈 저장).
.ohlcvs_horizon_fill_problems <- function(n_at_hz, horizon) {
  z <- names(n_at_hz)[!(unlist(n_at_hz) > 0L)]
  if (!length(z)) return(character(0))
  c(horizon_row_empty = sprintf("지평선 %s 행이 비어 있는 시트: %s", format(horizon), paste(z, collapse = ",")))
}

.ohlcvs_gate_print <- function(g) {
  sh <- g$sheets
  cat(sprintf("  [gate] 시트 지평선: %s\n", paste(sprintf("%s=%s", sh$sheet,
      ifelse(sh$date_axis %in% TRUE, format(sh$horizon), "날짜축없음")), collapse = " ")))
  cat(sprintf("  [gate] 공통 지평선 %s · 직전 적재 %s → %s\n", format(g$horizon), format(g$prior_horizon),
              if (isTRUE(g$ok)) "통과" else if (isTRUE(g$skip)) "새 자료 없음(적재 생략 · 실패 아님)" else "거부"))
}

#' 판정 기록(처리 상태가 아니다 — 실패해도 적재 판정을 바꾸지 않는다).
.ohlcvs_gate_record <- function(g, status, xlsx, path = OHLCVS_GATE_RECORD) {
  tryCatch({
    rec <- list(schema = "update_file_ohlcvs_gate_v1", at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
                status = status, xlsx = xlsx,
                xlsx_mtime = format(file.mtime(xlsx), "%Y-%m-%d %H:%M:%S"),
                horizon = format(g$horizon), prior_horizon = format(g$prior_horizon),
                reasons = as.list(g$reasons), note = g$note %||% NA_character_,
                sheets = lapply(seq_len(nrow(g$sheets)), function(k) list(
                  sheet = g$sheets$sheet[k], date_axis = g$sheets$date_axis[k],
                  horizon = format(g$sheets$horizon[k]), n_dates = g$sheets$n_dates[k])))
    tmp <- paste0(path, ".tmp", Sys.getpid())
    writeLines(jsonlite::toJSON(rec, auto_unbox = TRUE, pretty = TRUE, na = "null", null = "null"), tmp, useBytes = TRUE)
    if (!isTRUE(file.rename(tmp, path))) { suppressWarnings(file.remove(tmp)); stop("rename 실패") }
    path
  }, error = function(e) { cat(sprintf("  ⚠ [gate] 판정 기록 실패(판정 불변): %s\n", conditionMessage(e))); NA_character_ })
}

.ohlcvs_refuse <- function(g, xlsx) {
  for (k in names(g$reasons)) cat(sprintf("  ⛔ [GATE_REFUSED] %s — %s\n", k, g$reasons[[k]]))
  cat("[incr_ohlcvs] ⛔ [GATE_REFUSED] OHLCVS_update.xlsx 적재 거부 — RAWDATA 무접촉 · '처리 완료' 미기록(다음 정상 갱신 때 재시도)\n")
  .ohlcvs_gate_record(g, "refused", xlsx)
  invisible(list(refused = TRUE, reasons = g$reasons, horizon = g$horizon, prior_horizon = g$prior_horizon))
}

#' 새 자료 없음(2026-11-09) — 거부가 아니다: 적재 0 · RAWDATA 무접촉 · 처리 완료로 기록된다(같은 파일을 다시 묻지 않는다).
.ohlcvs_no_new <- function(g, xlsx) {
  cat(sprintf("[incr_ohlcvs] %s\n", g$note))
  .ohlcvs_gate_record(g, "no_new_data", xlsx)
  invisible(list(no_new_data = TRUE, horizon = g$horizon, prior_horizon = g$prior_horizon))
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

  ## ★적재 안전 관문 (2026-09-23) — RAWDATA 를 읽기·쓰기 **전에** 판정한다. 거부 = 무접촉 반환.
  .hz <- ohlcvs_sheet_horizons(ohlcvs_update)
  .prior <- .ohlcvs_prior_horizon(RAWDATA_CACHE)
  .gate <- ohlcvs_update_gate(.hz, .prior)
  ## (2026-11-09) 지평선 = 직전 적재일 때만 B6(질의 종료일)를 읽어 '새 자료 없음'(주말 · 휴일 재저장)과 실패 저장을 가른다.
  ##   탐침 실패 = b6 없음 → 지금처럼 not_advanced 거부(미측정을 통과로 접지 않는다).
  if (identical(names(.gate$reasons), "not_advanced") && isTRUE(.gate$horizon == .gate$prior_horizon)) {
    .pb <- .uf_probe_book(ohlcvs_update)
    .gate <- ohlcvs_update_gate(.hz, .prior, b6 = if (isTRUE(.pb$ok)) .pb$sheets else NULL)
  }
  .ohlcvs_gate_print(.gate)
  if (isTRUE(.gate$skip)) return(.ohlcvs_no_new(.gate, ohlcvs_update))
  if (!isTRUE(.gate$ok)) return(.ohlcvs_refuse(.gate, ohlcvs_update))

  raw <- as.data.table(read_parquet(RAWDATA_CACHE))

  # base max date = OHLCVS.xlsx (base 파일)의 max date
  # Update_File은 항상 base 이후 전부 추출하여 교체
  base_ohlcvs <- file.path(PROJECT_ROOT, "03_Universe", "OHLCVS.xlsx")
  base_dates <- .extract_qw_dates(base_ohlcvs)
  base_max <- max(base_dates)
  cat(sprintf("  base max date (OHLCVS.xlsx): %s\n", base_max))

  # Update xlsx 파싱 (6 시트) — QT_to_xts 우회, 직접 파싱
  # (QT_to_xts는 xts의 TZ 변환에서 1일 밀림 버그 발생)
  var_names <- .OHLCVS_VAR_SHEETS          # 관문이 순서를 확인한 목록과 같은 상수
  all_long <- NULL
  n_at_hz <- setNames(integer(length(var_names)), var_names)   # 지평선 행 값 칸 수(관문 보강)

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
    n_at_hz[[var_names[i]]] <- sum(long$Date == .gate$horizon & !is.na(long[[var_names[i]]]), na.rm = TRUE)
    long <- long[!is.na(Date) & Date > base_max]
    rm(raw_df, vals); gc()

    if (is.null(all_long)) {
      all_long <- long
    } else {
      all_long <- merge(all_long, long, by = c("Date", "Ticker"), all = TRUE)
    }
    rm(long); gc()
  }

  ## 관문 보강 — 지평선 날짜 행이 빈 값 시트가 있으면 거부(날짜만 늘고 값이 빈 저장 · 아직 RAWDATA 무수정)
  .fp <- .ohlcvs_horizon_fill_problems(n_at_hz, .gate$horizon)
  cat(sprintf("  [gate] 지평선 %s 행 값 칸: %s\n", format(.gate$horizon),
              paste(sprintf("%s=%d", names(n_at_hz), as.integer(n_at_hz)), collapse = " ")))
  if (length(.fp)) {
    .gate$ok <- FALSE; .gate$reasons <- c(.gate$reasons, .fp)
    return(.ohlcvs_refuse(.gate, ohlcvs_update))
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
  # ★W-09(2026-09-23): 전열 재조인(`BM_Ret := NULL` + merge) 폐기 — 단일 writer 경유.
  #   구판은 매 실행 BM_Ret 열 전체를 벤치로 갈아엎어 보호 구간(1990~98 토요장 계열 431일 ·
  #   2024-12-30)까지 덮었다. 지금은 결측 채움 + (킬스위치 해제 시) 불일치 정정만 한다.
  if (!exists("rawdata_bm_ret_sync_dt")) source(file.path(DATA_DIR, "rawdata_bm_ret_sync.R"))
  raw <- rawdata_bm_ret_sync_dt(raw, bench = bm[, .(Date, BM_Ret)], tag = "incr_ohlcvs/bm_ret")$dt

  # 저장
  setorder(raw, Date, Ticker)
  write_parquet(raw, RAWDATA_CACHE)

  cat(sprintf("[incr_ohlcvs] 완료: %s rows | %s ~ %s\n",
              format(nrow(raw), big.mark = ","),
              min(raw$Date), max(raw$Date)))
  .ohlcvs_gate_record(.gate, "loaded", ohlcvs_update)

  invisible(list(dates_updated = update_dates, rows = nrow(all_long)))
}

# ─── 공용 적재 관문 (F4 · 2026-11-06) — 수급 · 컨센서스 · 유니버스 책 ──────────────────
#   계획서 04_Research/01_reports/quantiwise_data_expansion_20261106/PLAN.md §3.0 F4 · §3.5.
#   왜: 시트별 지평선 · 채움 관문이 OHLCVS 에만 있었다(위 ohlcvs_update_gate). 나머지 책은 받은 것을 그대로 붙였고
#     부분 갱신본이 적재됐다 — 실측(2026-11-06 · 운영 .cache 이력 판독):
#       수급   2026-10-20~10-30 외국인 835~841행(평시 ≈2,353) · 개인 · 기타법인 0행(9거래일)
#       컨센서스 op_profit_fy1 2026-09-21~10-02 평시의 18%(8거래일) · 4지표(coverage · esbr · escr · op_profit_fy1) 10-19 0행 ·
#                9지표(esbr · escr · sue 제외) 2026-03-30~04-29 0행(23거래일 — 관측 최장 0행 구간 · 2026-11-06 2차 재측정).
#                ★1차 주석의 '2026-03-30~04-13 전 지표 0행'은 오독이었다 — 거부 목록(fill_low)만 읽었는데, 04-14~04-29 는
#                판정이 ref_zero 로 바뀌어 그 목록에 없었다(아래 W 근거) · esbr · escr · sue 는 그 구간에 행이 있다.
#       유니버스 Sector_Lv2 10-30 · 11-05 0행(그 시트만 갱신 안 됨 · 나머지 7시트는 전진)
#   관문(하나라도 실패 = 그 책 적재 0 · 캐시 무접촉 · '처리 완료' 미기록 → 다음 갱신 때 재시도 · incremental_update_all rc 3):
#     ① 머리(탐침 — 파싱 전): probe_failed · sheet_missing · sheet_read_error · not_query_sheet · date_axis_missing ·
#        horizon_mismatch(질의 시트 A열 마지막 날짜 불일치) · target_unmeasured · b6_unresolved · b6_behind(B6 괄호 < 목표일).
#        목표일 = 벤치 최신일(qw_refresh.ps1 Get-Target 과 같은 정의) · B6 괄호 규약 = qw_refresh.ps1 완료 판정과 같은 '[YYYYMMDD]'.
#        ★드라이버는 갱신이 실패한 시트의 B6 를 'CPD-1TD'(괄호 없음)로 남긴 채 저장한다 — 실측 11-06 Universe_Support 09:20
#          저장본: 7시트는 이전 라운드 값으로 전진, Sector_Lv2 는 10-19 정체, 8시트 모두 B6 미해석. 값만 보고는 못 가른다.
#     ② 채움(파싱 후): 출력(수급 유형 · 컨센서스 지표 · 유니버스 시트)별 받은 창의 날짜마다
#        채움비 = 그날 채움 수 / 직전 W 축 날짜 채움 수의 중앙값 ≥ 문턱 — fill_low · history_short · ref_zero · outputs_missing ·
#        window_empty(받은 창 0일인 출력 — 교체할 날짜가 없는데 '적재'로 기록하지 않는다 · 2026-11-06 2차).
#        채움 수 = 그 적재기가 실제로 저장하는 행 수(수급 = 0 아닌 순매수 · 컨센서스 = 값 있는 칸 · 유니버스 = 빈칸 아닌 값) —
#        적재분 이력과 같은 잣대로 센다. 축 = 그 책 적재분의 날짜 합집합(거래 달력을 따로 읽지 않는다).
#   ★not_advanced(직전 적재 지평선 대비 전진 없음)는 쓰지 않는다 — 받은 창 교체 규약(F3)에서는 지평선이 그대로인
#     복구 수급(qw_refresh.ps1 -FromOverride)이 정상 경로다. 실패 · 중단 저장본은 ①의 B6 판정이 거른다.

#   W = 직전 비교 창(축 날짜 수 — 일별 책 = 거래일 · 월간 스냅샷 책 = 스냅샷 수). 근거: 저장소 표준 한 달 창(20 거래일 —
#     유동성 20일 평균 거래대금 · .claude/rules/pit.md)이고, 중앙값의 붕괴점(50%) 덕에 비교 창 안 이상일이
#     ⌊(W−1)/2⌋ = 9일까지는 기준이 흔들리지 않는다 — 관측된 최장 부분 갱신 연속 = 9거래일(수급 외국인 2026-10-20~10-30).
#     ★관측된 최장 0행 구간은 23거래일이다(컨센서스 9지표 2026-03-30~04-29 · 2026-11-06 2차 재측정) — W 를 넘는다.
#       그런 구간이 받은 창에 통째로 들면 구간 안 이상일이 비교 창에 쌓인다: 첫 11일(비교 창 20일 중 0 이 10개 이하 →
#       중앙값 > 0)은 fill_low, 12번째 날부터(0 이 11개 이상 → 중앙값 0 · 그날도 0)는 ref_zero — 둘 다 거부 사유라 판정
#       결과는 같다(실측 재현: 03-30~04-13 fill_low · 04-14~04-29 ref_zero). 그 구간을 다시 받는 복구 수급은 받은 창을 새 값으로
#       이은 계열을 재므로 기준이 0 으로 무너지지 않고, 메우지 않은 긴 구멍 바로 뒤의 정상일은 기준 0 · 그날 > 0 = Inf 로 통과한다
#       (영구 거부 없음). ⇒ W 는 '최장 구간을 덮는 길이'일 필요가 없다 — 그래서 23거래일 실측에도 W 는 바꾸지 않았다.
.UF_FILL_W <- 20L
#   과반 결손 상한 — '그날 채움이 평소(직전 W 중앙값)의 절반 미만'. 문턱 = min(이 값, 그 항목 채움비 이력의 연 1회 수준 분위).
#     분위 = 1 / (그 항목 축의 연간 날짜 수 중앙값) — 이력에서 연 1회 이상 절반 밑으로 내려간 항목이면 문턱이 그 분위로
#     내려가, 정상 변동을 영구 거부해 적재가 멈추는 일을 막는다. 실측 근거(2026-11-06 · W=20 · 운영 .cache 이력):
#     2010 이후 정상일 채움비 최저 = 0.669(수급 기타법인) · 0.707(기관) · 0.805(컨센서스 escr · sue) ·
#     사고일 = 0.355(외국인 10-20~10-30) · 0.18(op_profit_fy1 09-21~10-02) · 0(개인 · 기타법인 10-20~10-30 · 컨센서스 4지표 10-19 ·
#     9지표 03-30~04-29 — 그중 04-14~04-29 는 ref_zero · 유니버스 Sector_Lv2 10-30 · 11-05) — 0.5 는 두 군 사이 간극에 있다.
#     같은 실측에서 이 규칙이 2010 이후 거부했을 날 = 위 사고일뿐(정상일 0 · 독립 검증 재측정에서 재현).
.UF_FILL_MAJORITY <- 0.5
#   B6 괄호 = 애드인이 CPD-1TD 를 푼 날짜 — qw_refresh.ps1 완료 판정(\[(\d{8})\])과 같은 규약.
.UF_B6_RE <- "\\[(\\d{8})\\]"

#   머리 탐침(Python · openpyxl read_only 스트리밍) — 시트마다 A5/B5/A6/B6 와 'D A T E' 라벨 아래 A열 날짜축만 읽고
#   첫 비날짜 행에서 멈춘다(수백 MB 책의 서식 잔재 행을 읽지 않는다 — us_update_stream_parse.py 와 같은 조기 종료).
#   readxl 은 시트 XML 전체를 올리므로 B6 한 칸에도 시트당 GB 급 파싱이 된다. 파일 하나만 쓴다는 담당 범위 때문에 여기 싣는다.
#   ★read_only 는 시트가 선언한 <dimension> 까지만 읽는다 — 선언이 틀린 파일(실측: openxlsx 저장본은 'A1')이면 1행에서 멈춰
#     날짜축 0 으로 보인다 → reset_dimensions() 로 선언을 무시한다(실물 퀀티 저장본은 'A1:NTP164' 처럼 맞게 선언).
#   'D A T E' 라벨 탐색 상한 MAX_HEAD = 60행(실물 = 14행 · 라벨이 없으면 날짜축 0 → date_axis_missing).
.UF_PROBE_PY <- r"--(
import sys, io, json, datetime
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="ascii", errors="replace")
from openpyxl import load_workbook

MAX_HEAD = 60

def txt(v):
    if v is None:
        return None
    if isinstance(v, (datetime.datetime, datetime.date)):
        return v.isoformat()
    return str(v)

def as_date(v):
    if isinstance(v, datetime.datetime):
        return v.date()
    if isinstance(v, datetime.date):
        return v
    if v is None or isinstance(v, bool):
        return None
    if isinstance(v, str):
        try:
            v = float(v.strip())
        except ValueError:
            return None
    if isinstance(v, (int, float)) and 20000 < v < 80000:
        return datetime.date(1899, 12, 30) + datetime.timedelta(days=int(v))
    return None

def probe(ws):
    r = {"a5": None, "b5": None, "a6": None, "b6": None, "date_row": None, "dates": [], "err": None}
    if hasattr(ws, "reset_dimensions"):
        ws.reset_dimensions()
    started = False
    for i, row in enumerate(ws.iter_rows(min_row=1, max_col=2, values_only=True), start=1):
        a = row[0] if len(row) > 0 else None
        b = row[1] if len(row) > 1 else None
        if i == 5:
            r["a5"], r["b5"] = txt(a), txt(b)
        elif i == 6:
            r["a6"], r["b6"] = txt(a), txt(b)
        if not started:
            if isinstance(a, str) and a.strip() == "D A T E":
                started = True
                r["date_row"] = i
            elif i >= MAX_HEAD:
                break
            continue
        d = as_date(a)
        if d is None:
            break
        r["dates"].append(d.isoformat())
    return r

def main():
    if len(sys.argv) != 3:
        print("PROBE_FAIL usage")
        return 2
    xlsx, out = sys.argv[1], sys.argv[2]
    try:
        wb = load_workbook(xlsx, read_only=True, data_only=True)
    except Exception as e:
        print("PROBE_FAIL open " + repr(e)[:300])
        return 2
    sheets = []
    try:
        for name in wb.sheetnames:
            rec = {"sheet": name}
            try:
                rec.update(probe(wb[name]))
            except Exception as e:
                rec.update({"a5": None, "b5": None, "a6": None, "b6": None, "date_row": None,
                            "dates": [], "err": repr(e)[:300]})
            sheets.append(rec)
    finally:
        wb.close()
    with open(out, "w", encoding="utf-8") as fh:
        json.dump({"schema": "uf_probe_v1", "sheets": sheets}, fh, ensure_ascii=True)
    print("PROBE_OK n_sheets=%d" % len(sheets))
    return 0

if __name__ == "__main__":
    sys.exit(main())
)--"

#' 파이썬 실행 경로 — QVEST_PY → .venv_qvest_ml (incremental_universe_support 구판과 같은 순서 · openpyxl 만 필요)
.uf_python <- function(root = PROJECT_ROOT) {
  cands <- c(Sys.getenv("QVEST_PY", ""), file.path(root, ".venv_qvest_ml/Scripts/python.exe"))
  cands <- cands[nzchar(cands) & file.exists(cands)]
  if (length(cands)) cands[1] else NA_character_
}

#' 머리 탐침 — 실패는 오류가 아니라 판정(probe_failed)으로 돌려준다(미측정을 통과로 접지 않는다).
#' @return list(ok, err, sheets = data.table(sheet, a5, b5, a6, b6, n_dates, horizon, dates(list), err, query, b6_date))
.uf_probe_book <- function(xlsx, py = .uf_python()) {
  fail <- function(msg) list(ok = FALSE, err = msg, sheets = NULL)
  if (!file.exists(xlsx)) return(fail(paste("xlsx 부재:", xlsx)))
  if (length(py) != 1L || is.na(py) || !nzchar(py)) return(fail("python 실행 경로 미발견(QVEST_PY · .venv_qvest_ml)"))
  td <- tempfile("uf_probe_"); dir.create(td, recursive = TRUE, showWarnings = FALSE)
  on.exit(unlink(td, recursive = TRUE), add = TRUE)
  pyf <- file.path(td, "uf_probe.py"); js <- file.path(td, "probe.json")
  writeLines(.UF_PROBE_PY, pyf)
  # env= 미사용(Windows system2 env 는 인자 주입 트랩 — 유니버스 적재기 주석) · 경로는 argv 로
  out <- tryCatch(suppressWarnings(system2(py, c(shQuote(pyf), shQuote(xlsx), shQuote(js)), stdout = TRUE, stderr = TRUE)),
                  error = function(e) structure(conditionMessage(e), status = 127L))
  st <- attr(out, "status"); if (is.null(st)) st <- 0L
  sentinel <- any(grepl("^PROBE_OK", out))
  if (st != 0L || !sentinel || !file.exists(js))
    return(fail(sprintf("탐침 실패(exit=%s · PROBE_OK %s) %s", st, if (sentinel) "있음" else "없음",
                        paste(tail(out, 2L), collapse = " | "))))
  j <- tryCatch(jsonlite::fromJSON(js, simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(j) || !length(j$sheets)) return(fail("탐침 JSON 판독 불가 또는 시트 0"))
  s1 <- function(x) if (is.null(x)) NA_character_ else as.character(x)
  sh <- rbindlist(lapply(j$sheets, function(s) {
    d <- sort(unique(as.Date(vapply(s$dates, as.character, character(1)))))
    data.table(sheet = s1(s$sheet), a5 = s1(s$a5), b5 = s1(s$b5), a6 = s1(s$a6), b6 = s1(s$b6),
               n_dates = length(d), horizon = if (length(d)) max(d) else as.Date(NA),
               dates = list(d), err = s1(s$err))
  }))
  sh[, query := !is.na(a6) & grepl("^Period.*To", a6)]        # 드라이버의 질의 시트 정의(A6 -like "Period*To*")
  # 금칙 ⑥(02_Infrastructure/docs/rules/r-portability.md): regmatches 의 색인은 perl = TRUE 로 만든다 — Windows TRE 는
  #   매치 위치를 UTF-16 코드유닛으로 내 non-BMP 문자가 앞에 있으면 추출 창이 밀린다(정상값 모양의 오답).
  b6s <- ifelse(is.na(sh$b6), "", sh$b6)
  m <- regmatches(b6s, regexec(.UF_B6_RE, b6s, perl = TRUE))
  sh[, b6_date := as.Date(vapply(m, function(x) if (length(x) == 2L) x[2] else NA_character_, character(1)), "%Y%m%d")]
  list(ok = TRUE, err = NA_character_, sheets = sh)
}

#' 목표일 = 벤치 최신일(qw_refresh.ps1 Get-Target 과 같은 정의). 판독 불가 = NA(미측정 — 관문이 거부한다).
.uf_target_date <- function(bench = file.path(CACHE_DIR, "benchmark.parquet")) {
  if (!file.exists(bench)) return(as.Date(NA))
  d <- tryCatch(read_parquet(bench, col_select = "Date", mmap = FALSE)$Date, error = function(e) NULL)
  d <- if (is.null(d)) as.Date(character(0)) else as.Date(d)
  d <- d[!is.na(d)]
  if (length(d)) max(d) else as.Date(NA)
}

#' 직전 W 개(자기 자신 제외)의 중앙값 — 앞 W 개는 NA
.uf_trailing_median <- function(n, W) {
  m <- rep(NA_real_, length(n))
  if (length(n) > W) for (i in (W + 1L):length(n)) m[i] <- stats::median(n[(i - W):(i - 1L)])
  m
}

#' 채움비 판정(순수 함수).
#' @param hist    data.table(output, Date, n) — 적재분(기존 패널)의 날짜별 채움 수. 행이 없는 날 = 0.
#' @param new     data.table(output, Date, n) — 이번 xlsx 파싱분의 날짜별 채움 수.
#' @param windows named list(output → Date) — 받은 창(교체될 날짜). 창의 날짜는 새 값, 나머지는 적재분으로 이은 계열에서
#'                그날 채움 수 / 직전 W 축 날짜 중앙값을 잰다(창이 길어도 앞쪽 날의 기준은 적재분 — 부분 갱신의 첫날이 걸린다).
#' @return data.table(output, Date, n, ref, ratio, thr, q, q_val, why ∈ ok · fill_low · history_short · ref_zero)
.uf_fill_check <- function(hist, new, windows, W = .UF_FILL_W, majority = .UF_FILL_MAJORITY) {
  empty <- function() data.table(output = character(0), Date = as.Date(character(0)), n = numeric(0))
  hist <- if (is.null(hist) || !nrow(hist)) empty() else as.data.table(hist)[, .(output, Date = as.Date(Date), n)]
  new  <- if (is.null(new)  || !nrow(new))  empty() else as.data.table(new)[, .(output, Date = as.Date(Date), n)]
  ax <- sort(unique(hist$Date))
  per_year <- if (length(ax)) as.numeric(stats::median(table(format(ax, "%Y")))) else NA_real_
  q <- if (is.na(per_year) || per_year <= 0) NA_real_ else 1 / per_year
  res <- list()
  for (o in names(windows)) {
    win <- sort(unique(as.Date(windows[[o]])))
    if (!length(win)) next
    h  <- hist[output == o, .(n = sum(n)), by = Date]
    nh <- numeric(length(ax)); if (nrow(h)) nh[match(h$Date, ax)] <- h$n
    ## 문턱 — 그 항목 적재분의 채움비 분포(0 = 빈 날은 사고일 후보라 분위 계산에서 뺀다)
    rh <- nh / .uf_trailing_median(nh, W)
    rp <- rh[is.finite(rh) & rh > 0]
    qv <- if (!is.na(q) && length(rp) >= per_year) as.numeric(stats::quantile(rp, q, type = 1, names = FALSE)) else NA_real_
    thr <- if (is.na(qv)) NA_real_ else min(majority, qv)
    ## 받은 창 — 병합 후보 계열(창 날짜 = 새 값 · 나머지 = 적재분)
    axm <- sort(unique(c(ax, win)))
    nm  <- numeric(length(axm)); nm[match(ax, axm)] <- nh
    nw  <- new[output == o & Date %in% win, .(n = sum(n)), by = Date]
    vw  <- numeric(length(win)); if (nrow(nw)) vw[match(nw$Date, win)] <- nw$n
    nm[match(win, axm)] <- vw
    for (k in seq_along(win)) {
      i   <- match(win[k], axm)
      ref <- if (i > W) stats::median(nm[(i - W):(i - 1L)]) else NA_real_
      ratio <- if (is.na(ref)) NA_real_ else if (ref > 0) nm[i] / ref else if (nm[i] > 0) Inf else NA_real_
      why <- if (is.na(thr) || is.na(ref)) "history_short" else if (is.na(ratio)) "ref_zero" else
        if (ratio < thr) "fill_low" else "ok"
      res[[length(res) + 1L]] <- data.table(output = o, Date = win[k], n = nm[i], ref = ref, ratio = ratio,
                                            thr = thr, q = q, q_val = qv, why = why)
    }
  }
  if (!length(res)) return(cbind(empty(), data.table(ref = numeric(0), ratio = numeric(0), thr = numeric(0),
                                                    q = numeric(0), q_val = numeric(0), why = character(0))))
  rbindlist(res)
}

#' 관문 사유 추가(같은 키는 이어 붙인다)
.uf_gate_add <- function(g, k, msg) {
  # reasons = 이름 붙은 character — 없는 이름에 [[ ]] 를 쓰면 오류라(리스트와 다르다) 이름으로 먼저 묻는다
  g$reasons[[k]] <- if (k %in% names(g$reasons)) paste(g$reasons[[k]], msg, sep = " ; ") else msg
  g$ok <- FALSE
  g
}

#' 관문 ① 머리 판정 — 전부 계산하고(조기 종료 없음) 사유를 이름 붙여 남긴다.
#' @param expected 이 책에서 읽을 질의 시트 이름(적재기 매핑 그대로) · @param target 목표일(벤치 최신일)
.uf_gate_header <- function(book, probe, expected, target) {
  g <- list(book = book, ok = TRUE, reasons = character(0), target = as.Date(target)[1], horizon = as.Date(NA),
            sheets = NULL, fill = NULL)
  lst <- function(x) paste(x, collapse = ",")
  if (!isTRUE(probe$ok)) return(.uf_gate_add(g, "probe_failed", probe$err %||% "탐침 실패"))
  sh <- probe$sheets
  ex <- sh[sheet %in% expected]
  g$sheets <- ex
  miss <- setdiff(expected, sh$sheet)
  if (length(miss)) g <- .uf_gate_add(g, "sheet_missing", sprintf("질의 시트 없음: %s", lst(miss)))
  bad <- ex[!is.na(err)]
  if (nrow(bad)) g <- .uf_gate_add(g, "sheet_read_error", paste(sprintf("%s: %s", bad$sheet, bad$err), collapse = " | "))
  nq <- ex[!(query %in% TRUE)]$sheet
  if (length(nq)) g <- .uf_gate_add(g, "not_query_sheet", sprintf("A6 가 Period(To) 가 아님: %s", lst(nq)))
  noax <- ex[!(n_dates > 0L)]$sheet
  if (length(noax)) g <- .uf_gate_add(g, "date_axis_missing", sprintf("'D A T E' 아래 날짜축 없음/0일: %s", lst(noax)))
  ends <- sort(unique(ex[n_dates > 0L]$horizon))
  if (length(ends) == 1L) g$horizon <- ends
  if (length(ends) > 1L)
    g <- .uf_gate_add(g, "horizon_mismatch", sprintf("시트별 지평선 불일치: %s",
                      lst(sprintf("%s=%s", ex[n_dates > 0L]$sheet, format(ex[n_dates > 0L]$horizon)))))
  if (is.na(g$target)) {
    g <- .uf_gate_add(g, "target_unmeasured", "목표일(벤치 최신일) 미측정 — B6 괄호 판정 불가")
  } else {
    un <- ex[is.na(b6_date)]
    if (nrow(un)) g <- .uf_gate_add(g, "b6_unresolved", sprintf("B6 괄호 날짜 없음(갱신 미완 저장 의심): %s",
                                    lst(sprintf("%s='%s'", un$sheet, un$b6))))
    bh <- ex[!is.na(b6_date) & b6_date < g$target]
    if (nrow(bh)) g <- .uf_gate_add(g, "b6_behind", sprintf("B6 괄호 < 목표일 %s: %s", format(g$target),
                                    lst(sprintf("%s=%s", bh$sheet, format(bh$b6_date, "%Y%m%d")))))
  }
  g
}

#' 관문 ② 채움 판정 결과를 덧붙인다
#' @param windows (선택) named list(출력 → 받은 창). 받은 창이 0일인 출력 = window_empty 거부(2026-11-06 2차).
#'   ★왜 두 번 묻나: 머리 판정의 date_axis_missing 한 줄이 이 결함의 유일한 방어선이었다(독립 검증 — 그 줄을 지운 사본이
#'     기존 시험 46/46 을 통과하고, 날짜축 없는 개인 시트의 책을 받아 1차 판의 합집합 교체로 그 유형 창 행을 지웠다 60→0).
#'     유형별 교체에서도 그 출력은 갱신 없이 책 전체가 '처리 완료'로 기록된다. 창 0일인 출력은 .uf_fill_check 가 판정할 날이
#'     없어 건너뛰므로(판정 0건) 채움 판정도 못 본다 — 교체 바로 앞에서 출력마다 창이 있는지 다시 묻는다.
.uf_gate_fill <- function(g, fc, outputs_missing = character(0), windows = NULL) {
  g$fill <- fc
  lst <- function(x, k = 6L) paste(c(head(x, k), if (length(x) > k) sprintf("… 외 %d", length(x) - k)), collapse = ", ")
  if (length(outputs_missing))
    g <- .uf_gate_add(g, "outputs_missing", sprintf("파싱 산출 없는 출력(파서가 시트를 조용히 건너뛴 경우 포함): %s",
                                                     lst(outputs_missing, 20L)))
  we <- if (is.null(windows)) character(0) else names(windows)[lengths(windows) == 0L]
  if (length(we))
    g <- .uf_gate_add(g, "window_empty", sprintf("받은 창 0일인 출력(그 시트 날짜축 없음 — 교체할 날짜가 없는 책을 '적재'로 기록하지 않는다): %s",
                                                  lst(we, 20L)))
  if (!is.null(fc) && nrow(fc)) {
    lo <- fc[why == "fill_low"]; hs <- fc[why == "history_short"]; rz <- fc[why == "ref_zero"]
    if (nrow(lo)) g <- .uf_gate_add(g, "fill_low", sprintf("채움비 < 문턱 %d건: %s", nrow(lo),
                     lst(sprintf("%s %s %d/%.0f=%.3f<%.3f", lo$output, format(lo$Date), as.integer(lo$n), lo$ref, lo$ratio, lo$thr))))
    if (nrow(hs)) g <- .uf_gate_add(g, "history_short", sprintf("비교 이력 부족(직전 비교 창 · 문턱 산출 1년치) %d건: %s",
                     nrow(hs), lst(sprintf("%s %s", hs$output, format(hs$Date)))))
    if (nrow(rz)) g <- .uf_gate_add(g, "ref_zero", sprintf("직전 비교 창 중앙값 0 · 그날도 0 %d건: %s",
                     nrow(rz), lst(sprintf("%s %s", rz$output, format(rz$Date)))))
  }
  g
}

.uf_gate_print <- function(g) {
  sh <- g$sheets
  if (!is.null(sh) && nrow(sh)) {
    hz <- ifelse(sh$n_dates > 0L, format(sh$horizon), "축없음")
    b6 <- ifelse(is.na(sh$b6_date), "미해석", format(sh$b6_date, "%Y%m%d"))
    cat(sprintf("  [gate:%s] 시트 지평선/B6: %s\n", g$book, paste(sprintf("%s=%s/%s", sh$sheet, hz, b6), collapse = " ")))
  }
  cat(sprintf("  [gate:%s] 공통 지평선 %s · 목표일 %s\n", g$book, format(g$horizon), format(g$target)))
  f <- g$fill
  if (!is.null(f) && nrow(f)) {
    fr <- f[is.finite(ratio)]
    th <- suppressWarnings(range(f$thr, na.rm = TRUE))
    if (nrow(fr)) {
      w <- fr[which.min(ratio)]
      cat(sprintf("  [gate:%s] 받은 창 %d일 · 채움비 최저 %.3f (%s %s · %d/%.0f) · 문턱 %s\n", g$book, uniqueN(f$Date),
                  w$ratio, w$output, format(w$Date), as.integer(w$n), w$ref,
                  if (all(is.finite(th))) sprintf("%.3f~%.3f", th[1], th[2]) else "미산출"))
    }
  }
  cat(sprintf("  [gate:%s] → %s\n", g$book, if (isTRUE(g$ok)) "통과" else "거부"))
}

#' 판정 기록(처리 상태가 아니다 — 실패해도 적재 판정을 바꾸지 않는다). .cache/update_file_gate_<책>.json
.uf_gate_record <- function(g, status, xlsx,
                            path = file.path(CACHE_DIR, sprintf("update_file_gate_%s.json", tolower(g$book)))) {
  tryCatch({
    fin <- function(x) if (length(x) && is.finite(x)) x else NA
    sh <- g$sheets; f <- g$fill
    rec <- list(schema = "update_file_gate_v1", book = g$book, at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
                status = status, xlsx = xlsx, xlsx_mtime = format(file.mtime(xlsx), "%Y-%m-%d %H:%M:%S"),
                target = format(g$target), horizon = format(g$horizon), reasons = as.list(g$reasons),
                sheets = if (is.null(sh)) list() else lapply(seq_len(nrow(sh)), function(k) list(
                  sheet = sh$sheet[k], query = sh$query[k], b6 = sh$b6[k], horizon = format(sh$horizon[k]),
                  n_dates = sh$n_dates[k])),
                fill = if (is.null(f) || !nrow(f)) list() else lapply(split(f, f$output), function(x) list(
                  thr = fin(x$thr[1]), q = fin(x$q[1]), q_val = fin(x$q_val[1]),
                  min_ratio = fin(suppressWarnings(min(x$ratio[is.finite(x$ratio)]))), n_window = nrow(x),
                  not_ok = sprintf("%s:%s", format(x$Date[x$why != "ok"]), x$why[x$why != "ok"]))))
    tmp <- paste0(path, ".tmp", Sys.getpid())
    writeLines(jsonlite::toJSON(rec, auto_unbox = TRUE, pretty = TRUE, na = "null", null = "null", digits = 6),
               tmp, useBytes = TRUE)
    if (!isTRUE(file.rename(tmp, path))) { suppressWarnings(file.remove(tmp)); stop("rename 실패") }
    path
  }, error = function(e) { cat(sprintf("  ⚠ [gate:%s] 판정 기록 실패(판정 불변): %s\n", g$book, conditionMessage(e)))
                           NA_character_ })
}

#' 거부 — 사유 출력 · 기록 · 거부 표지 반환(캐시는 이미 무접촉). incremental_update_all 이 rc 3 으로 바꾼다.
.uf_refuse <- function(g, xlsx, tag) {
  for (k in names(g$reasons)) cat(sprintf("  ⛔ [GATE_REFUSED] %s — %s\n", k, g$reasons[[k]]))
  cat(sprintf("[%s] ⛔ [GATE_REFUSED] %s 적재 거부 — 캐시 무접촉 · '처리 완료' 미기록(다음 정상 갱신 때 재시도)\n",
              tag, basename(xlsx)))
  .uf_gate_record(g, "refused", xlsx)
  invisible(list(refused = TRUE, book = g$book, reasons = g$reasons, horizon = g$horizon, target = g$target))
}

# ─── Consensus 증분 ──────────────────────────────────────────────────────────
#   (2026-11-06 F3 · F4) 지표별 '받은 창의 날짜 = 교체' + 공용 관문. 구판은 eps_1y 하나의 max 이후만 12지표에 붙여
#   뒤처진 지표의 날을 영구 손실했다(coverage · esbr · escr · op_profit_fy1 의 10-19 — 그 4지표 캐시 max 10-16).
#   파싱을 관문보다 먼저 하는 이유: 지표별 채움 수가 파싱 산출에서 나오고, 파서(consensus_build_cache)가 시트 오류를
#   삼켜 산출을 조용히 빠뜨리는 것(outputs_missing)도 파싱 뒤에야 보인다. 파서 오류는 지금처럼 오류로 전파한다.
incremental_consensus <- function(target = .uf_target_date()) {
  cons_update <- file.path(UPDATE_DIR, "Consensus_update.xlsx")
  if (!file.exists(cons_update)) {
    cat("[incr_consensus] Consensus_update.xlsx 없음. 스킵.\n")
    return(invisible(NULL))
  }

  cat("[incr_consensus] Consensus_update.xlsx 증분 처리...\n")
  cons_cache_dir <- file.path(CACHE_DIR, "consensus")

  # 기존 캐시 존재 확인 — ★구판은 이 파일의 max 하나를 12지표 공통 앵커로 썼다(F3 결함). 지금은 존재 확인만 한다.
  ref_file <- file.path(cons_cache_dir, "eps_1y.parquet")
  if (!file.exists(ref_file)) {
    cat("  기존 캐시 없음. base Consensus.xlsx부터 빌드 필요.\n")
    return(invisible(NULL))
  }

  # Update_File을 임시 파싱 → 관문 → 지표별 받은 창 교체
  source(file.path(DATA_DIR, "consensus_parser.R"))

  # 임시 디렉토리에 Update_File 파싱
  tmp_dir <- file.path(CACHE_DIR, "consensus_tmp")
  dir.create(tmp_dir, showWarnings = FALSE)

  old_cache <- CONSENSUS_CACHE
  CONSENSUS_CACHE <<- tmp_dir
  old_xlsx <- CONSENSUS_XLSX
  CONSENSUS_XLSX <<- cons_update

  refused <- NULL
  tryCatch({
    consensus_build_cache(force = TRUE)

    ## (F4) 관문 — ① 머리 탐침(시트 · 지평선 · B6) → ② 지표별 채움비. 시트 → 지표 = 파서 정본(CONSENSUS_METRICS)
    metrics <- CONSENSUS_METRICS
    g <- .uf_gate_header("Consensus", .uf_probe_book(cons_update), names(metrics), target)
    windows <- NULL
    if (isTRUE(g$ok)) {
      windows <- setNames(lapply(names(metrics), function(s) g$sheets[sheet == s]$dates[[1]]), unname(metrics))
      hist <- list(); newc <- list(); missing <- character(0); mx <- character(0)
      for (m in unname(metrics)) {
        tp <- file.path(tmp_dir, paste0(m, ".parquet")); cp <- file.path(cons_cache_dir, paste0(m, ".parquet"))
        if (!file.exists(tp)) { missing <- c(missing, m); next }
        newc[[m]] <- as.data.table(read_parquet(tp, col_select = "Date", mmap = FALSE))[, .(output = m, n = .N), by = Date]
        if (file.exists(cp)) {
          hd <- as.data.table(read_parquet(cp, col_select = "Date", mmap = FALSE))
          hist[[m]] <- hd[, .(output = m, n = .N), by = Date]
          mx[m] <- format(max(hd$Date, na.rm = TRUE))
        } else mx[m] <- "부재"
      }
      if (length(mx)) {
        grp <- split(names(mx), unname(mx))
        cat(sprintf("  기존 캐시 지표별 max: %s\n",
                    paste(sprintf("%s=%s", names(grp), vapply(grp, paste, "", collapse = ",")), collapse = " · ")))
      }
      g <- .uf_gate_fill(g, .uf_fill_check(rbindlist(hist), rbindlist(newc), windows), missing,
                     windows = windows)
    }
    .uf_gate_print(g)
    if (!isTRUE(g$ok)) {
      refused <- .uf_refuse(g, cons_update, "incr_consensus")
    } else {
      .consensus_append_increment(tmp_dir, cons_cache_dir, windows)
      .uf_gate_record(g, "loaded", cons_update)
      cat("[incr_consensus] 증분 완료.\n")
    }

    # 임시 디렉토리 정리
    unlink(tmp_dir, recursive = TRUE)
  }, error = function(e) {
    unlink(tmp_dir, recursive = TRUE)
    # ★fail-closed (2026-09-19): 구판은 여기서 cat 만 하고 삼켰다 — 그러면 incremental_update_all 이
    #   이 파일의 mtime 을 '처리됨' 으로 기록해 **다시는 재시도하지 않는다**(수급·유니버스 적재기는
    #   이미 stop 전파다 — 컨센서스만 달랐다).
    stop(sprintf("[incr_consensus] 오류: %s", conditionMessage(e)), call. = FALSE)
  }, finally = {
    CONSENSUS_CACHE <<- old_cache
    CONSENSUS_XLSX <<- old_xlsx
  })
  if (!is.null(refused)) return(refused)
  invisible(TRUE)
}

# ─── 컨센서스 증분 붙이기 (파싱 산출 → 기존 캐시) ─────────────────────────────
#' 파서가 tmp_dir 에 쓴 parquet 중 **Date 가 있는 메트릭**을 지표별 **받은 창의 날짜 = 교체**로 붙인다(F3 · 2026-11-06).
#'   그 지표의 받은 창 날짜에 있던 기존 행을 지우고 새 행을 넣는다 — 수급 · 유니버스 적재기와 같은 규약.
#'   ★구판은 `Date > base_max`(eps_1y 하나의 max) 였다 → 다른 지표가 뒤처진 날(10-19)은 다시 받아도 붙지 않았다.
#' ★2026-09-19 수리: 파서는 `ticker_map.parquet`(Ticker·Name, Date 없음)도 쓴다. 구판 루프는 그 파일에서
#'   `tmp_dt[Date > base_max]` 로 죽었고, 그 뒤 알파벳 순서의 메트릭은 **붙지 못했다** — 지금까지 12종이
#'   전부 'ti' 보다 앞(… target_price < ticker_map)이라 운 좋게 피했을 뿐, 매 적재마다 '오류' 가 찍혔다.
#'   ticker_map 은 증분이 아니라 **합집합**(새 상장 종목 이름을 잃지 않게)으로 갱신한다.
#' @param windows named list(지표 → Date) — 받은 창(관문 탐침의 시트 날짜축). NULL = 파싱 산출의 날짜.
#'   구 3번째 인자(base_max · 날짜 1개)는 폐지 — 들어오면 경고하고 NULL 로 본다.
#' @return 붙인 메트릭별 행 수(named integer)
.consensus_append_increment <- function(tmp_dir, cons_cache_dir, windows = NULL) {
  if (!is.null(windows) && !is.list(windows)) {
    cat("  ⚠ [incr_consensus] 3번째 인자는 지표별 받은 창(named list) — 구 base_max(날짜 1개) 규약은 폐지(F3) · 파싱 산출의 날짜로 교체한다\n")
    windows <- NULL
  }
  tmp_files <- list.files(tmp_dir, pattern = "\\.parquet$", full.names = TRUE)
  added <- integer(0)
  .atomic_write <- function(dt, dest) {
    # [2026-06-17 fix] Windows arrow mmap-on-write 잠금(error 1224) 회피: temp 에 쓰고 rename.
    .tmp_out <- paste0(dest, ".tmp")
    write_parquet(dt, .tmp_out)
    if (file.exists(dest)) file.remove(dest)
    file.rename(.tmp_out, dest)
  }
  for (tf in tmp_files) {
    metric <- basename(tf)
    orig_file <- file.path(cons_cache_dir, metric)
    tmp_dt <- as.data.table(read_parquet(tf))

    if (identical(metric, "ticker_map.parquet")) {
      if (all(c("Ticker", "Name") %in% names(tmp_dt))) {
        old_map <- if (file.exists(orig_file)) as.data.table(read_parquet(orig_file)) else tmp_dt[0]
        merged <- unique(rbind(tmp_dt, old_map[!Ticker %in% tmp_dt$Ticker], fill = TRUE), by = "Ticker")
        rm(old_map); gc()
        .atomic_write(merged, orig_file)
        cat(sprintf("  %s: 종목명 합집합 %d종\n", metric, nrow(merged)))
      }
      next
    }
    if (!"Date" %in% names(tmp_dt)) {
      cat(sprintf("  %s: Date 열 없음 — 증분 대상 아님(건너뜀)\n", metric))
      next
    }
    mkey <- sub("\\.parquet$", "", metric)
    if (!is.null(windows) && !length(windows[[mkey]])) {
      cat(sprintf("  ⚠ %s: 받은 창 정보 없음(관문 대상 밖 산출) — 건너뜀\n", metric))
      next
    }
    # 받은 창 = 관문 탐침의 시트 날짜축(또는 파싱 산출의 날짜). ★tmp_dt[, Date] 는 Date 없는 파일에서 오류로 죽는다 —
    #   조용히 '창 0일'로 건너뛰지 않게 일부러 $ 대신 쓴다(위 ticker_map · Date 가드가 그 파일을 먼저 걸러야 한다).
    win <- sort(unique(as.Date(if (is.null(windows)) tmp_dt[, Date] else windows[[mkey]])))
    if (!length(win)) {
      cat(sprintf("  %s: 받은 창 0일 — 건너뜀\n", metric))
      next
    }
    if (!file.exists(orig_file)) {
      cat(sprintf("  ⚠ %s: 기존 패널 부재 — 증분 창만으로 역사 패널을 만들지 않는다(건너뜀)\n", metric))
      next
    }
    new_rows <- tmp_dt[as.Date(Date) %in% win]
    orig_dt <- as.data.table(read_parquet(orig_file))
    in_win <- as.Date(orig_dt$Date) %in% win
    # 진단(판정 아님) — 다시 받은 날의 값이 바뀐 칸 수: 퀀티에는 빈티지가 없어 이 수가 사후 정정의 유일한 흔적이다
    n_chg <- tryCatch({
      vc <- setdiff(intersect(names(new_rows), names(orig_dt)), c("Date", "Ticker"))[1]
      mm <- merge(orig_dt[in_win, c("Date", "Ticker", vc), with = FALSE],
                  new_rows[, c("Date", "Ticker", vc), with = FALSE], by = c("Date", "Ticker"))
      x <- mm[[paste0(vc, ".x")]]; y <- mm[[paste0(vc, ".y")]]
      sum(!((is.na(x) & is.na(y)) | (!is.na(x) & !is.na(y) & x == y)))
    }, error = function(e) NA_integer_)
    n_old <- sum(in_win)
    combined <- rbind(orig_dt[!in_win], new_rows, fill = TRUE)
    setorder(combined, Date)
    rm(orig_dt); gc()
    .atomic_write(combined, orig_file)
    added[[metric]] <- nrow(new_rows)
    cat(sprintf("  %s: 받은 창 %d일(%s~%s) 교체 · 기존 %d행 → 새 %d행 · 값 바뀐 칸 %s (max: %s)\n", metric,
                length(win), min(win), max(win), n_old, nrow(new_rows),
                if (is.na(n_chg)) "?" else format(n_chg), max(combined$Date)))
  }
  invisible(added)
}

# ─── Investor_Act 증분 ───────────────────────────────────────────────────────
#   (2026-11-06 F3 · F4) 받은 창의 날짜 = 교체 + 공용 관문. 구판은 패널 전체 max 이후만 붙였다(`Date > base_max`) →
#   한 유형만 빈 날(10-20~10-30 개인 · 기타법인 0행 · 외국인 35%)은 다시 받아도(-FromOverride) 영영 메워지지 않았고,
#   (2차 · 같은 날) 교체 단위 = 유형 × 그 유형 시트의 받은 창(④) — 1차 판의 4유형 합집합 교체는 시트 창이 다르면 행을 잃었다.
#   그 부분 갱신본 자체도 관문 없이 붙었다(11-06 [0b] '개인 0 rows · 기타법인 0 rows' 그대로 적재).
#   기존 패널 부재 시 증분 창만으로 패널을 만들던 경로(구 base_max 리터럴)는 없앴다 — 관문 history_short 로 거부한다.
incremental_investor <- function(update_path = file.path(UPDATE_DIR, "Investor_Act_update.xlsx"),
                                 cache_dir   = file.path(CACHE_DIR, "investor_stock"),
                                 target      = .uf_target_date()) {
  if (!file.exists(update_path)) {
    cat("[incr_investor] Investor_Act_update.xlsx 없음. 스킵.\n")
    return(invisible(NULL))
  }

  cat("[incr_investor] Investor_Act_update.xlsx 증분 처리...\n")

  if (!dir.exists(cache_dir)) dir.create(cache_dir, recursive = TRUE)
  all_file  <- file.path(cache_dir, "investor_all.parquet")
  sheet_map <- c("외인" = "Foreign", "기관" = "Institutional", "개인" = "Individual", "기타법인" = "OtherCorp")

  ## ① 관문 앞단(머리 탐침 — 시트 · 날짜축 · 지평선 일치 · B6 괄호 ≥ 목표일) + 기존 패널. 거부면 파싱도 하지 않는다.
  g <- .uf_gate_header("Investor_Act", .uf_probe_book(update_path), names(sheet_map), target)
  if (!file.exists(all_file))
    g <- .uf_gate_add(g, "history_short", "기존 패널(investor_all.parquet) 부재 — 증분 창만으로 역사 패널을 만들지 않는다(base 파서 선행)")
  if (!isTRUE(g$ok)) {
    .uf_gate_print(g)
    return(.uf_refuse(g, update_path, "incr_investor"))
  }
  windows <- setNames(lapply(names(sheet_map), function(s) g$sheets[sheet == s]$dates[[1]]), unname(sheet_map))

  existing <- as.data.table(read_parquet(all_file))
  cat(sprintf("  기존 캐시 max: %s (%s rows)\n", max(existing$Date, na.rm = TRUE), format(nrow(existing), big.mark = ",")))

  ## ② 4시트 직접 파싱 (QT_to_xts 우회, 5행 스킵) — 받은 창 전체(구 'Date > 기존 max' 거르기 폐지)
  all_new <- list()

  for (sheet_name in names(sheet_map)) {
    itype <- sheet_map[[sheet_name]]
    cat(sprintf("  시트 '%s'...\n", sheet_name))
    raw_df <- as.data.frame(read_xlsx(update_path, sheet = sheet_name, skip = 7,
                                       col_names = TRUE, na = c("", "NA")))
    raw_df <- raw_df[-1:-5, ]  # 5행 스킵 (Update_File 공통 형태)

    serials <- suppressWarnings(as.numeric(raw_df[[1]]))
    dates <- as.Date(serials, origin = "1899-12-30")

    vals <- as.data.table(raw_df[, -1])
    vals <- vals[, lapply(.SD, as.numeric)]
    vals[, Date := dates]

    long <- melt(vals, id.vars = "Date", variable.name = "Ticker",
                 value.name = "NetBuy", variable.factor = FALSE)
    long <- long[!is.na(Date) & Date %in% windows[[itype]] & !is.na(NetBuy) & NetBuy != 0]
    long[, InvestorType := itype]

    all_new[[length(all_new) + 1L]] <- long
    cat(sprintf("    %d rows (받은 창 %d일 %s~%s)\n", nrow(long), length(windows[[itype]]),
                min(windows[[itype]]), max(windows[[itype]])))
    rm(raw_df, vals, long); gc()
  }
  new_dt <- rbindlist(all_new)

  ## ③ 채움 관문 — 유형별 날짜 채움 수(0 아닌 순매수 행) vs 적재분 이력 · 받은 창 0일인 유형 = window_empty
  g <- .uf_gate_fill(g, .uf_fill_check(existing[, .(n = .N), by = .(output = InvestorType, Date)],
                                       new_dt[, .(n = .N), by = .(output = InvestorType, Date)], windows),
                     windows = windows)
  .uf_gate_print(g)
  if (!isTRUE(g$ok)) return(.uf_refuse(g, update_path, "incr_investor"))

  ## ④ 받은 창의 날짜 = 교체 — 유형마다 **그 유형 시트가 받은 날짜**의 기존 행만 지우고 새 행을 넣는다(2026-11-06 2차).
  ##   ★1차 판은 네 시트 창의 합집합(win_all)으로 4유형을 함께 지웠다 — 시트 창이 다르면(복구 수급에서 시트별 B5 를 손으로
  ##     고친 책 · PLAN §3.3 시트별 B5) 그 날짜를 받지 않은 유형의 기존 행이 지워지고 대체되지 않았다(독립 검증 모래상자: 개인 12일 ·
  ##     나머지 5일 · 같은 끝일 → LOADED · 외국인 · 기관 · 기타법인 앞 7일 84→0행). 관문은 끝일만 대조하고 채움 판정은 그 유형
  ##     창만 재므로 거르지 못한다 — 교체 단위를 판정 단위(유형 × 그 유형의 받은 창)와 같게 둔다. 새 행은 ②에서 이미 유형별 창으로 걸렀다.
  win_key <- unique(rbindlist(lapply(names(windows), function(ty)
    if (length(windows[[ty]])) data.table(InvestorType = ty, Date = as.Date(windows[[ty]])))))
  n_old_by <- if (nrow(win_key)) existing[win_key, on = c("InvestorType", "Date"), nomatch = NULL, .N, by = .EACHI][
    , .(n = sum(N)), by = InvestorType] else data.table(InvestorType = character(0), n = integer(0))
  combined <- rbind(if (nrow(win_key)) existing[!win_key, on = c("InvestorType", "Date")] else existing, new_dt, fill = TRUE)
  rm(existing); gc()
  setorder(combined, Date, Ticker, InvestorType)
  write_parquet(combined, all_file)

  # [2026-07-17 배관수리] 파생 파일 동반 재생성 — 기존엔 investor_all만 갱신되고
  # per-type 분리 파일(investor_foreign/institutional/individual/othercorp.parquet)과
  # investor_wide.parquet는 full 파서(parse_investor_act)에서만 쓰여 영구 stale
  # (실측: all=2026-07-01 vs 분리=2026-03-26 → flow_features_daily 113d stale의 원인).
  for (itype in unique(combined$InvestorType)) {
    split_path <- file.path(cache_dir, sprintf("investor_%s.parquet", tolower(itype)))
    write_parquet(combined[InvestorType == itype], split_path)
  }
  wide <- dcast(combined, Date + Ticker ~ InvestorType, value.var = "NetBuy", fill = 0)
  write_parquet(wide, file.path(cache_dir, "investor_wide.parquet"))
  cat(sprintf("  파생 재생성: 분리 %d종 + wide (max: %s)\n",
              uniqueN(combined$InvestorType), max(combined$Date)))

  n_new_by <- new_dt[, .(n = .N), by = InvestorType]
  for (ty in names(windows)) {
    w <- windows[[ty]]
    cat(sprintf("  %s: 받은 창 %d일(%s~%s) 교체 · 기존 %s행 → 새 %s행\n", ty, length(w),
                if (length(w)) format(min(w)) else "-", if (length(w)) format(max(w)) else "-",
                format(sum(n_old_by[InvestorType == ty]$n), big.mark = ","),
                format(sum(n_new_by[InvestorType == ty]$n), big.mark = ",")))
  }
  win_all <- if (nrow(win_key)) sort(unique(win_key$Date)) else as.Date(character(0))   # 보고용 합집합 — 교체 단위가 아니다(위 ④)
  cat(sprintf("[incr_investor] 완료: 유형별 받은 창 교체(합집합 %d일 %s~%s) · 기존 %s행 → 새 %s행 → 총 %s rows (max: %s)\n",
              length(win_all), min(win_all), max(win_all), format(sum(n_old_by$n), big.mark = ","),
              format(nrow(new_dt), big.mark = ","), format(nrow(combined), big.mark = ","),
              max(combined$Date)))
  .uf_gate_record(g, "loaded", update_path)
  invisible(list(refused = FALSE, rows = nrow(new_dt), window = win_all, windows = windows,
                 n_old = setNames(n_old_by$n, n_old_by$InvestorType)))
}

# ─── Universe_Support 증분 ───────────────────────────────────────────────────
# [2026-07-25 D1 수리] 구 구현은 parse_universe_support(us_update)를 force=FALSE로 호출 —
# 기존 캐시 존재 시 전 시트 "Cache hit" 스킵 = 증분 no-op이었고, force=TRUE로 바꾸면 merge
# 없이 update-기간만으로 통째 덮어쓰기 = 1990~ 역사 패널 소실. D1 우회(openpyxl 스트리밍 +
# 겹침날짜 교체 merge, 검증 PASS)를 표준 경로로 승격:
#   ① 파싱 = us_update_stream_parse.py (openpyxl read_only 스트리밍 조기종료 — update xlsx
#      시트 XML이 스타일 잔재로 420~560MB bloat라 openxlsx/readxl 통짜 로드는 메모리 리스크)
#   ② merge = 시트(출력) 파일마다 그 시트가 받은 날짜 교체: existing[!Date %in% 받은 창] + new rbind
#      (2026-11-06 — 받은 창 = 관문 탐침의 그 시트 날짜축. 수급은 유형 × 그 유형 창 교체 · 둘 다 '출력별 받은 창' 규약)
#      (update 첫 스냅샷이 기존 종점과 겹쳐도 최신 export가 이김 — idempotent 재실행 안전)
#   ③ 스키마 = 디스크 시맨틱 컬럼명(Date/Ticker/K200 등) 기준 통일. legacy 'Value' 파일은
#      merge 시 시맨틱명으로 승격 저장
#   ④ 쓰기 = temp-rename (Windows arrow mmap 잠금 1224 회피 — incremental_consensus 06-17 패턴)
# 실패는 stop() 전파(fail-closed) — 구현 전처럼 삼켜서 no-op을 "완료"로 위장하지 않는다.
# [2026-11-06 F4] 공용 관문 — 8시트 지평선 일치 · B6 괄호 ≥ 목표일 · 시트별 채움비. 거부 = 8시트 모두 적재 0(책 단위).
#   실측: 11-06 09:20 저장본은 Sector_Lv2 만 10-19 에 멈춘 채(나머지 7시트 10-30 · 11-05) '8/8 시트 merge' 로 적재돼
#   us_sector_lv2 의 10-30 월말 행이 빠졌다. 구판의 '시트 파서 산출 부재 · 신규 0행 → 그 시트만 스킵'도 같은 부분 적재라
#   이제는 관문 사유(outputs_missing · fill_low)로 책 전체를 거부한다. 병합 날짜 = 받은 창(탐침 날짜축).
incremental_universe_support <- function(
    update_path = file.path(UPDATE_DIR, "Universe_Support_update.xlsx"),
    cache_dir   = UNIVERSE_SUPPORT_CACHE,
    parser_py   = file.path(DATA_DIR, "us_update_stream_parse.py"),
    py_exec     = NULL,
    target      = .uf_target_date()
) {
  if (!file.exists(update_path)) {
    cat("[incr_universe_support] Universe_Support_update.xlsx 없음. 스킵.\n")
    return(invisible(NULL))
  }
  cat("[incr_universe_support] Universe_Support_update.xlsx 증분 처리...\n")

  # 시트 메타(UNIVERSE_SUPPORT_SHEET_META)만 필요 — 전체 파서는 호출하지 않는다
  if (!exists("UNIVERSE_SUPPORT_SHEET_META")) source(file.path(DATA_DIR, "parse_universe_support.R"))
  if (!file.exists(parser_py)) stop("[incr_universe_support] 파서 부재: ", parser_py)

  # Python 실행 경로 (QVEST_PY = openpyxl 보유 확인됨. pyarrow 불요) — 관문 탐침과 같은 해석
  if (is.null(py_exec)) {
    py_exec <- .uf_python()
    if (is.na(py_exec)) stop("[incr_universe_support] python 실행경로 미발견 (QVEST_PY / .venv_qvest_ml)")
  }
  metas <- UNIVERSE_SUPPORT_SHEET_META
  cnames <- vapply(metas, function(m) m$cache_name, character(1))

  ## (F4) 관문 앞단 — 머리 탐침 + 기존 패널 존재. 거부면 파싱도 하지 않는다.
  g <- .uf_gate_header("Universe_Support", .uf_probe_book(update_path, py_exec), names(metas), target)
  no_panel <- cnames[!file.exists(file.path(cache_dir, sprintf("us_%s.parquet", cnames)))]
  if (length(no_panel))
    g <- .uf_gate_add(g, "history_short", sprintf(paste0("기존 패널 부재: %s — update xlsx(증분 기간만)로는 역사 패널을 ",
                      "만들 수 없음(base Universe_Support.xlsx 로 parse_universe_support() 선행)"), paste(no_panel, collapse = ",")))
  if (!isTRUE(g$ok)) {
    .uf_gate_print(g)
    return(.uf_refuse(g, update_path, "incr_universe_support"))
  }
  windows <- setNames(lapply(names(metas), function(s) g$sheets[sheet == s]$dates[[1]]), unname(cnames))

  # ① Python 스트리밍 파싱 → stage CSV
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

  # ② (F4) 시트별 새 값 · 적재분 채움 수 → 채움 관문. 쓰기 전에 8시트 전부 판정한다(책 단위 거부).
  news <- list(); hist <- list(); newc <- list(); missing <- character(0)
  for (s in names(metas)) {
    meta    <- metas[[s]]
    vcol    <- meta$value_col
    new_csv <- file.path(stage_dir, sprintf("us_new_%s.csv", meta$cache_name))
    pq_path <- file.path(cache_dir, sprintf("us_%s.parquet", meta$cache_name))
    if (!file.exists(new_csv)) { missing <- c(missing, meta$cache_name); next }

    new_dt <- fread(new_csv, encoding = "UTF-8", colClasses = "character")
    if (!identical(names(new_dt), c("Date", "Ticker", vcol)))
      stop(sprintf("[incr_universe_support] %s: 파서 CSV 헤더 불일치: %s",
                   meta$cache_name, paste(names(new_dt), collapse = ",")))
    new_dt[, Date := as.Date(Date)]
    if (meta$value_type == "numeric") new_dt[, (vcol) := as.numeric(get(vcol))]
    news[[meta$cache_name]] <- new_dt
    newc[[meta$cache_name]] <- new_dt[, .(output = meta$cache_name, n = .N), by = Date]

    ex <- as.data.table(read_parquet(pq_path, mmap = FALSE))
    setnames(ex, "Value", vcol, skip_absent = TRUE)
    if (vcol %in% names(ex))
      hist[[meta$cache_name]] <- ex[!is.na(get(vcol)), .(output = meta$cache_name, n = .N), by = .(Date = as.Date(Date))]
    rm(ex); gc()
  }
  g <- .uf_gate_fill(g, .uf_fill_check(rbindlist(hist), rbindlist(newc), windows), missing,
                     windows = windows)
  .uf_gate_print(g)
  if (!isTRUE(g$ok)) return(.uf_refuse(g, update_path, "incr_universe_support"))

  # ③ 시트별 merge (받은 창의 날짜 교체 후 rbind) + ④ temp-rename 쓰기
  n_merged <- 0L
  for (s in names(metas)) {
    meta    <- metas[[s]]
    vcol    <- meta$value_col
    pq_path <- file.path(cache_dir, sprintf("us_%s.parquet", meta$cache_name))
    new_dt  <- news[[meta$cache_name]]

    existing <- as.data.table(read_parquet(pq_path))
    setnames(existing, "Value", vcol, skip_absent = TRUE)   # legacy 'Value' 스키마 → 시맨틱명 승격
    existing[, Date := as.Date(Date)]                        # timestamp 혼입 방어 (date32 통일)
    if (!identical(sort(names(existing)), sort(names(new_dt))))
      stop(sprintf("[incr_universe_support] %s: 스키마 불일치 existing={%s} vs new={%s}",
                   meta$cache_name, paste(names(existing), collapse = ","),
                   paste(names(new_dt), collapse = ",")))

    upd_dates  <- windows[[meta$cache_name]]                 # 받은 창(관문이 날짜마다 채움을 확인한 날짜축)
    new_dt     <- new_dt[Date %in% upd_dates]
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

  cat(sprintf("[incr_universe_support] 완료: %d/%d 시트 merge.\n", n_merged, length(metas)))
  .uf_gate_record(g, "loaded", update_path)
  invisible(list(refused = FALSE, n_merged = n_merged))
}

# ─── 전체 증분 실행 ──────────────────────────────────────────────────────────
#' (2026-11-06 F5) 이름 → 적재기 **명시 표**(완전 일치) 디스패치. 표 순서 = 처리 순서(구판과 같다).
#'   구판은 `grepl("OHLCVS"|"Consensus"|"Investor"|"Universe_Support", 변경 경로)` 였다 → ① 표에 없는 xlsx 는 아무도 안 읽는데
#'   mtime 은 '처리됨'으로 기록돼 영영 버려졌고 ② 이름에 그 부분 문자열만 들어도(예 'Consensus_update_old.xlsx')
#'   **정본 파일**을 다시 읽는 엉뚱한 적재가 돌며 그 파일도 '처리됨'이 됐다.
#'   미등록 xlsx = 폴더에 있는 동안 매 실행 경고 · 처리 기록에서 뺀다 · 끝에서 rc 4(거부가 같이 있으면 rc 3)로 알린다 —
#'   stop 을 즉시 하면 같은 실행의 나머지 책이 멈추므로 전부 처리 · 기록한 뒤에 알린다.
#' @param loaders 이름(파일명) → 적재기 함수명. 새 책은 여기 등록한다(이름 부분 문자열 금지 · PLAN §3.1).
incremental_update_all <- function(loaders = c(OHLCVS_update.xlsx           = "incremental_ohlcvs",
                                               Consensus_update.xlsx        = "incremental_consensus",
                                               Investor_Act_update.xlsx     = "incremental_investor",
                                               Universe_Support_update.xlsx = "incremental_universe_support")) {
  cat("=== Incremental Update_File 처리 시작 ===\n\n")

  changes <- detect_update_changes()
  # 미등록 = 폴더에 **있는** 표 밖 xlsx(변경 여부 무관 — 구판이 '처리됨'으로 기록해 둔 파일도 다시 드러난다)
  unregistered <- sort(setdiff(names(changes$mtimes), names(loaders)))
  if (length(changes$changed) == 0 && !length(unregistered)) {
    cat("Update_File 변경 없음.\n")
    return(invisible(list(updated = FALSE)))
  }

  cat(sprintf("변경 감지: %d 파일\n", length(changes$changed)))
  for (f in changes$changed) cat(sprintf("  → %s\n", basename(f)))
  for (nm in unregistered)
    cat(sprintf("  ⚠ [UNREGISTERED] %s — 적재기 표에 없는 xlsx: 적재 안 함 · '처리 완료' 미기록(있는 동안 매 실행 경고) · 이름 → 적재기 등록 필요\n", nm))
  cat("\n")

  ohlcvs_result <- NULL
  qw_updated <- FALSE
  ohlcvs_refused <- NULL
  refused <- list()
  changed_names <- basename(changes$changed)

  # 표 순서대로 — OHLCVS 관문 거부면 '처리 완료' 로 기록하지 않고(아래) 끝에서 stop → run_r rc 3 → DR_FAILED
  for (nm in names(loaders)) {
    if (!nm %in% changed_names) next
    fn  <- loaders[[nm]]
    res <- get(fn, envir = environment(), mode = "function")()
    is_refused <- is.list(res) && isTRUE(res$refused)
    if (identical(fn, "incremental_ohlcvs")) {
      ohlcvs_result <- res
      if (is_refused) ohlcvs_refused <- res else if (!(is.list(res) && isTRUE(res$no_new_data))) qw_updated <- TRUE
    } else if (is_refused) {
      refused[[nm]] <- res
    } else if (identical(fn, "incremental_consensus")) {
      qw_updated <- TRUE
    }
  }

  # 처리 완료 기록 — 관문이 거부한 책은 직전 기록을 그대로 둔다(없었으면 없는 채로) → 다음 실행이 재시도.
  #   미등록 xlsx 는 기록에서 뺀다(F5 — '처리됨'으로 묻지 않는다).
  mt_save <- changes$mtimes
  keep_prev <- c(if (!is.null(ohlcvs_refused)) names(loaders)[loaders == "incremental_ohlcvs"], names(refused))
  if (length(keep_prev)) {
    prev_files <- .get_last_processed()$files
    for (nm in keep_prev) mt_save[[nm]] <- prev_files[[nm]]
  }
  for (nm in unregistered) mt_save[[nm]] <- NULL
  .save_last_processed(mt_save)

  # 끝에서 알린다 — 다른 책은 이미 처리 · 기록됐다
  others <- c(if (length(refused)) sprintf("관문 거부 %s",
                paste(sprintf("%s(%s)", names(refused), vapply(refused, function(r) paste(names(r$reasons), collapse = ","), "")),
                      collapse = " · ")),
              if (length(unregistered)) sprintf("미등록 xlsx %s", paste(unregistered, collapse = ",")))
  if (!is.null(ohlcvs_refused) || length(others)) {
    ## ★rc 계약(머리 주석 ▸rc 계약): 비대화형(Rscript — daily_refresh.sh run_r)에서 이 오류가 잡히지 않고 끝나면
    ##   종료 코드 3(관문 거부) · 4(미등록만)로 나간다. options(error=) 는 잡히지 않은 오류에서만 · 스택이 풀리기 전에 불린다.
    ##   잡히면(tryCatch · 시험) 평범한 R 오류이고 on.exit 가 옵션을 되돌린다. 대화형 세션은 끄지 않는다.
    .rc <- if (!is.null(ohlcvs_refused) || length(refused)) 3L else 4L
    if (!interactive()) {
      .old_err <- options(error = function() quit(save = "no", status = .rc, runLast = FALSE))
      on.exit(options(.old_err), add = TRUE)
    }
  }
  if (!is.null(ohlcvs_refused))
    stop(structure(class = c("update_file_gate_refused", "error", "condition"), list(call = NULL, message = sprintf(paste0(
      "[incr_ohlcvs][GATE_REFUSED] OHLCVS_update.xlsx 적재 거부 — %s ",
      "(지평선 %s · 직전 적재 %s · 다른 파일은 처리됨 · OHLCVS 는 처리 완료 미기록)%s"),
      paste(names(ohlcvs_refused$reasons), collapse = ","),
      format(ohlcvs_refused$horizon), format(ohlcvs_refused$prior_horizon),
      if (length(others)) paste0(" · 그 밖에 ", paste(others, collapse = " · ")) else ""))))
  if (length(others))
    stop(structure(class = c(if (length(refused)) "update_file_gate_refused" else "update_file_unregistered", "error", "condition"),
                   list(call = NULL, message = sprintf("[incremental_update_all][%s] %s — 다른 파일은 처리됨 · 해당 책은 처리 완료 미기록",
                                                       if (length(refused)) "GATE_REFUSED" else "UNREGISTERED",
                                                       paste(others, collapse = " · ")))))

  cat("\n=== Incremental Update 완료 ===\n")
  invisible(list(updated = TRUE, qw_updated = qw_updated, ohlcvs = ohlcvs_result))
}

cat("[incremental_update_file] Loaded. Functions: incremental_update_all(), incremental_ohlcvs(), detect_update_changes()\n")
