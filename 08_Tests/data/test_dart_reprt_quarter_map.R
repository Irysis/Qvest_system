#==============================================================================
# test_dart_reprt_quarter_map.R — DART reprt_code ↔ 분기 매핑 상설 검사 (위반 주입)
#
# 대상: 02_Infrastructure/data/data_collector_dart_quarterly.R :: REPRT_MAP
#       02_Infrastructure/data/dart_submission_window.R :: .dart_season_bounds
#                                                          DART_REPRT_LABEL
#
# 왜 있나 (2026-07-26 R1 수리):
#   REPRT_MAP 이 11014→quarter 1 / 11013→quarter 3 으로 **뒤집혀** 있었다.
#   11014(3분기, 11월 접수)가 quarter 1 로 라벨돼 Factor_Date = bsns_year-05-15 를
#   받았고, 그 결과 Factor_Date − 실접수일 **중앙값 −183일 / look-ahead 99.8%**
#   (5,911/5,923 filing key). PIT C4 축 위반이다.
#
#   ★ 이 결함이 오래 살아남은 기전: 매핑은 **두 파일에 나뉘어** 있었고
#     (제출창은 dart_submission_window.R, 분기 라벨은 REPRT_MAP), 한쪽만 고쳐도
#     각 파일은 자기 안에서 일관돼 보인다. 따라서 이 검사의 핵심은 단일 파일
#     검증이 아니라 **두 파일의 교차 합치**(A2)다 — 한쪽만 뒤집히면 FAIL.
#
# 구조 4축:
#   A. 계약     — 매핑 정본 + 교차 합치 + Factor_Date 규약(C4) 대조. 데이터 불요.
#   B. 차단 실효 — 뒤집힌 맵/부분 뒤집힌 맵을 주입해 A 의 판정부가 실제로 FAIL 을
#                  내는지. 음성 통제(정상 맵 통과)로 오탐 0 도 함께 본다.
#                  ※ 검사가 죽어도 겉보기는 "경고 0" 이므로 이 축이 없으면 무의미.
#   C. 데이터 불변식 — 저장 raw 의 thstrm_nm 라벨·실접수월·Factor_Date 시차.
#                  parquet 부재 시 SKIP(FAIL 아님) — 단 SKIP 은 요약에 명시된다.
#   D. 데이터 차단 실효 — 같은 데이터에 구 매핑을 적용하면 C 가 FAIL 로 뒤집히는지.
#
# ⚠ look-ahead 는 0 이 아니다 (전수 실측 21.2%). C4 고정일 규약(5/15·8/15·11/15·
#   익년 3/31)은 개별사 실제 접수일보다 앞설 수 있기 때문이며, 매핑이 바뀌지 않은
#   11012(25.7%)·11011(24.4%)에도 **동일하게** 존재하는 기존 성질이다. 따라서
#   불변식은 "0 건"이 아니라 **중앙 시차 ≥ 0** + **비율 래칫**으로 건다.
#   (0 을 기대값으로 걸면 매 실행 FAIL → 검사가 꺼지고, 그게 더 위험하다.)
#
# 단독 실행: Rscript 08_Tests/data/test_dart_reprt_quarter_map.R
# 배터리   : 08_Tests/hooks/run_all_hooks.sh (SUITES 배열)
#==============================================================================

suppressPackageStartupMessages({ library(jsonlite); library(data.table) })

.resolve_proj <- function() {
  cands <- c(Sys.getenv("CLAUDE_PROJECT_DIR", unset = ""),
             Sys.getenv("QM_ROOT", unset = ""),
             "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
  cands <- cands[nzchar(cands)]
  marker <- "02_Infrastructure/data/data_collector_dart_quarterly.R"
  hit <- cands[file.exists(file.path(cands, marker))]
  if (length(hit) == 0L) stop("project root 미발견 — CLAUDE_PROJECT_DIR 설정 필요")
  hit[1]
}
PROJ <- .resolve_proj()
setwd(PROJ)

source("02_Infrastructure/data/dart_submission_window.R")

PASS <- 0L; FAIL <- 0L; SKIP <- 0L
ok   <- function(n, m = "") { PASS <<- PASS + 1L; cat(sprintf("  PASS: %s%s\n", n, if (nzchar(m)) paste0(" — ", m) else "")) }
bad  <- function(n, m = "") { FAIL <<- FAIL + 1L; cat(sprintf("  FAIL: %s — %s\n", n, m)) }
skip <- function(n, m = "") { SKIP <<- SKIP + 1L; cat(sprintf("  SKIP: %s — %s\n", n, m)) }

# 정본 기대값 (OpenDART 공식 + 저장데이터 thstrm_nm 실측, 2026-07-26 확정)
CANON <- c("11013" = 1L, "11012" = 2L, "11014" = 3L, "11011" = 4L)
# quarter → 제출창 개시월 (dart_submission_window.R 규약: q4=사업보고서는 익년 1월)
CANON_START_MONTH <- c("1" = 4L, "2" = 7L, "3" = 10L, "4" = 1L)
# quarter → Factor_Date 고정일 (PIT C4: 분기 5/15·8/15·11/15, 연간 익년 3/31)
CANON_FDATE <- c("1" = "05-15", "2" = "08-15", "3" = "11-15", "4" = "03-31")

#==============================================================================
# 판정부 (순수 함수 — 맵을 인자로 받아야 위반 주입이 가능하다)
#==============================================================================

#' 매핑이 정본과 일치하는가
judge_map_canonical <- function(map_dt) {
  m <- setNames(as.integer(map_dt$quarter), as.character(map_dt$reprt_code))
  if (!setequal(names(m), names(CANON))) return(list(ok = FALSE, why = "reprt_code 집합 불일치"))
  bad_codes <- names(CANON)[m[names(CANON)] != CANON]
  if (length(bad_codes)) {
    return(list(ok = FALSE, why = sprintf("%s → q%s (기대 q%s)", paste(bad_codes, collapse = ","),
                paste(m[bad_codes], collapse = ","), paste(CANON[bad_codes], collapse = ","))))
  }
  list(ok = TRUE, why = "")
}

#' 매핑 ↔ 제출창(다른 파일) 교차 합치. 한쪽만 뒤집혀도 FAIL.
judge_cross_window <- function(map_dt, year = 2025L) {
  probs <- character(0)
  for (i in seq_len(nrow(map_dt))) {
    rcode <- as.character(map_dt$reprt_code[i]); q <- as.integer(map_dt$quarter[i])
    st <- .dart_season_bounds(year, rcode)$start
    if (is.na(st)) { probs <- c(probs, sprintf("%s 창 미상", rcode)); next }
    got <- as.integer(format(st, "%m")); want <- CANON_START_MONTH[[as.character(q)]]
    if (!identical(got, want))
      probs <- c(probs, sprintf("%s(q%d) 창개시 %d월 (기대 %d월)", rcode, q, got, want))
  }
  list(ok = length(probs) == 0L, why = paste(probs, collapse = " / "))
}

#' 매핑 ↔ 보고서 한글 라벨 합치 ("1분기보고서" ↔ q1)
judge_label_agreement <- function(map_dt) {
  want <- c("1" = "1분기", "2" = "반기", "3" = "3분기", "4" = "사업보고서")
  probs <- character(0)
  for (i in seq_len(nrow(map_dt))) {
    rcode <- as.character(map_dt$reprt_code[i]); q <- as.integer(map_dt$quarter[i])
    lab <- unname(DART_REPRT_LABEL[rcode])
    if (is.na(lab)) { probs <- c(probs, sprintf("%s 라벨 부재", rcode)); next }
    if (!grepl(want[[as.character(q)]], lab, fixed = TRUE))
      probs <- c(probs, sprintf("%s(q%d) 라벨='%s' (기대 '%s' 포함)", rcode, q, lab, want[[as.character(q)]]))
  }
  list(ok = length(probs) == 0L, why = paste(probs, collapse = " / "))
}

#' 저장 raw 의 thstrm_nm 최빈 라벨 ↔ 매핑 분기 (데이터 기반)
judge_thstrm_label <- function(dat, map_dt) {
  want <- c("1" = "1분기", "2" = "반기", "3" = "3분기")
  m <- setNames(as.integer(map_dt$quarter), as.character(map_dt$reprt_code))
  probs <- character(0); detail <- character(0)
  for (rcode in names(m)) {
    q <- m[[rcode]]
    if (as.character(q) %in% names(want) == FALSE) next   # 11011(연간) 라벨은 "제N기"
    sub <- dat[reprt_code == rcode & !is.na(thstrm_nm) & nzchar(thstrm_nm)]
    if (!nrow(sub)) { probs <- c(probs, sprintf("%s 데이터 없음", rcode)); next }
    top <- sub[, .N, by = thstrm_nm][order(-N)][1]
    detail <- c(detail, sprintf("%s→q%d '%s'", rcode, q, top$thstrm_nm))
    if (!grepl(want[[as.character(q)]], top$thstrm_nm, fixed = TRUE))
      probs <- c(probs, sprintf("%s(q%d) 최빈라벨='%s' (기대 '%s' 포함)",
                                rcode, q, top$thstrm_nm, want[[as.character(q)]]))
  }
  list(ok = length(probs) == 0L, why = paste(probs, collapse = " / "),
       detail = paste(detail, collapse = " | "))
}

#' Factor_Date − 실접수일 중앙 시차 ≥ 0 (코드별). 뒤집힘의 직격 지표.
judge_factor_date_lag <- function(fil, map_dt) {
  m <- setNames(as.integer(map_dt$quarter), as.character(map_dt$reprt_code))
  x <- copy(fil)
  x[, q := m[reprt_code]]
  x[, fd := as.Date(fifelse(q == 1L, sprintf("%d-05-15", bsns_year),
                    fifelse(q == 2L, sprintf("%d-08-15", bsns_year),
                    fifelse(q == 3L, sprintf("%d-11-15", bsns_year),
                            sprintf("%d-03-31", bsns_year + 1L)))))]
  x[, la := as.numeric(fd - rcept_date)]
  agg <- x[, .(n = .N, med = as.numeric(median(la)), pct_neg = round(100 * mean(la < 0), 1)),
           by = reprt_code][order(reprt_code)]
  bad_rows <- agg[med < 0]
  list(ok = nrow(bad_rows) == 0L,
       why = if (nrow(bad_rows)) paste(sprintf("%s 중앙시차 %.0f일(<0)", bad_rows$reprt_code, bad_rows$med),
                                       collapse = " / ") else "",
       agg = agg)
}

#==============================================================================
# A. 계약 (데이터 불요)
#==============================================================================
cat("=== A. 매핑 계약 + 교차 합치 ===\n")

# 소스에서 REPRT_MAP 을 실제로 읽어온다 (하드코딩 재기술이 아니라 정본 파싱)
SRC_Q <- "02_Infrastructure/data/data_collector_dart_quarterly.R"
src_lines <- readLines(SRC_Q, warn = FALSE, encoding = "UTF-8")
i0 <- grep("^REPRT_MAP\\s*<-\\s*data\\.table\\(", src_lines)
if (length(i0) != 1L) {
  bad("A0_reprt_map_locatable", sprintf("REPRT_MAP 정의 %d곳 (기대 1)", length(i0)))
  REPRT_MAP <- NULL
} else {
  i1 <- i0 + which(grepl("^\\)", src_lines[(i0 + 1):min(length(src_lines), i0 + 12)]))[1]
  eval(parse(text = paste(src_lines[i0:i1], collapse = "\n")))
  ok("A0_reprt_map_locatable", sprintf("line %d", i0))
}

if (!is.null(REPRT_MAP)) {
  r <- judge_map_canonical(REPRT_MAP)
  if (r$ok) ok("A1_map_canonical", "11013→1 / 11012→2 / 11014→3 / 11011→4") else
    bad("A1_map_canonical", r$why)

  r <- judge_cross_window(REPRT_MAP)
  if (r$ok) ok("A2_cross_file_window_agreement", "REPRT_MAP ↔ .dart_season_bounds 합치") else
    bad("A2_cross_file_window_agreement", r$why)

  r <- judge_label_agreement(REPRT_MAP)
  if (r$ok) ok("A3_label_agreement", "REPRT_MAP ↔ DART_REPRT_LABEL 합치") else
    bad("A3_label_agreement", r$why)

  # A4: Factor_Date 고정일 규약(C4)이 소스에 그대로 있는가
  fd_src <- paste(src_lines, collapse = "\n")
  miss <- names(CANON_FDATE)[!vapply(CANON_FDATE, function(d) grepl(d, fd_src, fixed = TRUE), logical(1))]
  if (length(miss) == 0L)
    ok("A4_factor_date_c4_constants", "5/15·8/15·11/15·익년3/31 전부 존재") else
    bad("A4_factor_date_c4_constants", sprintf("결측 고정일: q%s", paste(miss, collapse = ",")))
}

#==============================================================================
# B. 차단 실효 (위반 주입) — 판정부가 실제로 이빨이 있는가
#==============================================================================
cat("\n=== B. 차단 실효 (위반 주입) ===\n")

MAP_GOOD <- data.table(reprt_code = c("11013","11012","11014","11011"), quarter = c(1L,2L,3L,4L))
MAP_FLIP <- data.table(reprt_code = c("11014","11012","11013","11011"), quarter = c(1L,2L,3L,4L))  # 원 결함
MAP_PART <- data.table(reprt_code = c("11013","11012","11014","11011"), quarter = c(1L,2L,4L,3L))  # 부분 뒤집기

if (judge_map_canonical(MAP_FLIP)$ok) bad("B1_flip_detected_by_canonical", "뒤집힌 맵이 통과함 — 검사 무력") else
  ok("B1_flip_detected_by_canonical", judge_map_canonical(MAP_FLIP)$why)

if (judge_cross_window(MAP_FLIP)$ok) bad("B2_flip_detected_by_cross_window", "교차 합치가 뒤집힘을 못 잡음") else
  ok("B2_flip_detected_by_cross_window", judge_cross_window(MAP_FLIP)$why)

if (judge_label_agreement(MAP_FLIP)$ok) bad("B3_flip_detected_by_label", "라벨 합치가 뒤집힘을 못 잡음") else
  ok("B3_flip_detected_by_label", "구 매핑 라벨 불일치 검출")

if (judge_map_canonical(MAP_PART)$ok) bad("B4_partial_flip_detected", "부분 뒤집기가 통과함") else
  ok("B4_partial_flip_detected", "11014/11011 교환 검출")

# 음성 통제 — 정상 맵이 오탐되지 않는가 (오탐은 검사를 꺼지게 만든다)
neg <- c(judge_map_canonical(MAP_GOOD)$ok, judge_cross_window(MAP_GOOD)$ok,
         judge_label_agreement(MAP_GOOD)$ok)
if (all(neg)) ok("B5_negative_control_no_false_alarm", "정상 맵 3판정 전부 통과") else
  bad("B5_negative_control_no_false_alarm", sprintf("정상 맵 오탐: %s", paste(which(!neg), collapse = ",")))

#==============================================================================
# C/D. 데이터 불변식 + 데이터 차단 실효
#==============================================================================
cat("\n=== C. 데이터 불변식 (저장 raw) ===\n")

RAWP <- file.path(get0("CACHE_DIR", ifnotfound = file.path(PROJ, ".cache")),
                  "dart", "dart_raw_quarterly.parquet")
if (!file.exists(RAWP)) RAWP <- file.path(PROJ, ".cache", "dart", "dart_raw_quarterly.parquet")

if (!file.exists(RAWP)) {
  skip("C_data_invariants", sprintf("raw parquet 부재: %s", RAWP))
  skip("D_data_injection", "raw parquet 부재")
} else {
  dat <- tryCatch(as.data.table(arrow::read_parquet(
           RAWP, col_select = c("rcept_no","reprt_code","bsns_year","Ticker","thstrm_nm"),
           mmap = FALSE)), error = function(e) NULL)
  if (is.null(dat) || !nrow(dat)) {
    skip("C_data_invariants", "raw parquet 로드 실패")
    skip("D_data_injection", "raw parquet 로드 실패")
  } else {
    # C1: thstrm_nm 최빈 라벨 ↔ 매핑
    r <- judge_thstrm_label(dat, MAP_GOOD)
    if (r$ok) ok("C1_thstrm_label_matches_map", r$detail) else
      bad("C1_thstrm_label_matches_map", r$why)

    # filing key 단위 실접수일
    fil <- dat[!is.na(rcept_no) & nzchar(rcept_no),
               .(rcept_date = min(as.Date(substr(rcept_no, 1, 8), "%Y%m%d"), na.rm = TRUE)),
               by = .(Ticker, bsns_year, reprt_code)]
    fil <- fil[!is.na(rcept_date)]

    # C2: 실접수 최빈월 ↔ 제출창 개시월 (같은 달 또는 창 안)
    want_mo <- c("11013" = 5L, "11012" = 8L, "11014" = 11L, "11011" = 3L)
    probs <- character(0); det <- character(0)
    for (rcode in names(want_mo)) {
      s <- fil[reprt_code == rcode]
      if (!nrow(s)) next
      mo <- s[, .N, by = .(m = as.integer(format(rcept_date, "%m")))][order(-N)][1]$m
      det <- c(det, sprintf("%s→%d월", rcode, mo))
      if (!identical(mo, want_mo[[rcode]]))
        probs <- c(probs, sprintf("%s 최빈접수월 %d월 (기대 %d월)", rcode, mo, want_mo[[rcode]]))
    }
    if (length(probs) == 0L) ok("C2_receipt_month_matches_window", paste(det, collapse = " | ")) else
      bad("C2_receipt_month_matches_window", paste(probs, collapse = " / "))

    # C3: Factor_Date − 실접수일 중앙 시차 ≥ 0 (전 코드)
    r_good <- judge_factor_date_lag(fil, MAP_GOOD)
    if (r_good$ok)
      ok("C3_factor_date_median_lag_nonneg",
         paste(sprintf("%s med=%+.0f d(%.1f%% neg)", r_good$agg$reprt_code,
                       r_good$agg$med, r_good$agg$pct_neg), collapse = " | ")) else
      bad("C3_factor_date_median_lag_nonneg", r_good$why)

    # C4: look-ahead 비율 래칫 (2026-07-26 실측 baseline + 3pp 여유)
    #     0 을 기대하지 않는다 — C4 고정일 규약의 성질(매핑 불변 코드에도 동일 존재).
    BASE <- c("11011" = 24.4, "11012" = 25.7, "11013" = 22.2, "11014" = 11.3)
    probs <- character(0)
    for (i in seq_len(nrow(r_good$agg))) {
      rcode <- r_good$agg$reprt_code[i]; p <- r_good$agg$pct_neg[i]
      if (!rcode %in% names(BASE)) next
      if (p > BASE[[rcode]] + 3.0)
        probs <- c(probs, sprintf("%s %.1f%% > baseline %.1f%%+3pp", rcode, p, BASE[[rcode]]))
    }
    if (length(probs) == 0L)
      ok("C4_lookahead_rate_ratchet", "전 코드 baseline+3pp 이내") else
      bad("C4_lookahead_rate_ratchet", paste(probs, collapse = " / "))

    cat("\n=== D. 데이터 차단 실효 (구 매핑 주입) ===\n")
    # D1: 같은 데이터에 구 매핑을 적용하면 C1 이 FAIL 로 뒤집히는가
    if (judge_thstrm_label(dat, MAP_FLIP)$ok)
      bad("D1_flip_breaks_thstrm_label", "구 매핑인데도 라벨 검사가 통과 — 케이스 공허") else
      ok("D1_flip_breaks_thstrm_label", "구 매핑에서 라벨 불일치 검출")

    # D2: 구 매핑이면 C3 중앙시차가 음수로 뒤집히는가 (원 결함 −183일 재현)
    r_flip <- judge_factor_date_lag(fil, MAP_FLIP)
    if (r_flip$ok)
      bad("D2_flip_breaks_median_lag", "구 매핑인데 중앙시차 전부 ≥0 — 지표 무력") else
      ok("D2_flip_breaks_median_lag", r_flip$why)

    # D3: 구 매핑의 11014 look-ahead 가 래칫을 실제로 넘는가 (99.8% 재현)
    p14 <- r_flip$agg[reprt_code == "11014"]$pct_neg
    if (length(p14) && p14 > BASE[["11014"]] + 3.0)
      ok("D3_flip_breaks_ratchet", sprintf("구 매핑 11014 look-ahead %.1f%%", p14)) else
      bad("D3_flip_breaks_ratchet", sprintf("구 매핑 11014 %.1f%% — 래칫을 못 넘음", p14))
  }
}

cat(sprintf("\nTOTAL: %d pass / %d fail / %d skip\n", PASS, FAIL, SKIP))
cat(toJSON(list(test = "dart_reprt_quarter_map", pass = PASS, fail = FAIL,
                skip = SKIP, total = PASS + FAIL), auto_unbox = TRUE), "\n", sep = "")
if (FAIL > 0) quit(status = 1)
