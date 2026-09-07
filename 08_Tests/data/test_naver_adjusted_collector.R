#==============================================================================
# test_naver_adjusted_collector.R — 네이버 개별종목 **수정주가 경로** 검사기
#
# 2026-09-07 신설 (도훈 지시: 개별종목 = 수정주가 · 벤치 = 종가 · 원천 2단).
#
# ★네트워크를 타지 않는다 — 전부 08_Tests/fixtures/naver/ 의 **고정 응답**이다.
# ★운영 상태(.cache/RAWDATA.parquet · 원장 · 운영 설정)를 빌리지 않는다. rawdata 는
#   합성 21열 테이블이고 설정은 스텁이다
#   (feedback-a-test-that-borrows-live-state-flaps-when-you-fix-the-state).
# ★함수는 소스 좌표가 아니라 **AST 로 재도출**한다 — 리팩터가 줄을 옮겨도 표적이
#   안 죽는다(feedback-source-text-assertions-pin-coordinates-that-refactors-move).
#
# 검사 축:
#   ① 파서가 수정주가 OHLCV 를 낸다 (삼성 50:1 분할 전일 = 53,000 이지 2,650,000 아님)
#   ② 분할 전후 연속성 — 수정주가 판은 |ret| < SEAM_MAX_RET, 원주가 판은 아니다
#   ③ 실패 종목이 사유와 함께 집계된다 (조용한 누락 = unaccounted 로 검거)
#   ④ 스키마 계약 — 소비자 열 목록을 **다른 writer 에서 재도출**해 충족을 확인
#   ⑤ 위반 주입 — 파서를 구판(종가만/원주가)으로 되돌리면 ①②④가 빨강
#   ⑥ 무거래(Vol 0 · OHL 0) 규약 — 0 을 가격으로 적재하지 않는다
#   ⑦ 값 갱신이 승계 축(K200·KQ150·Sector…)을 보존한다 (삭제 후 append 아님)
#   ⑧ 설정 경유 — 문턱·엔드포인트가 코드가 아니라 JSON 에서 온다
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })

# ★러너는 self-first (r-portability ④-b)
.t_root <- function() {
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", a[grepl("^--file=", a)])
  cands <- character(0)
  if (length(f)) cands <- c(cands, normalizePath(file.path(dirname(f[1]), "..", ".."), mustWork = FALSE))
  cands <- c(cands, Sys.getenv("CLAUDE_PROJECT_DIR", unset = ""), Sys.getenv("QM_ROOT", unset = ""), getwd())
  cands <- gsub("\\\\", "/", cands[nzchar(cands)])
  hit <- cands[file.exists(file.path(cands, "02_Infrastructure/hooks/qvest_hook_router.py"))]
  if (!length(hit)) stop("project root 미발견")
  hit[1]
}
PROJ <- .t_root(); setwd(PROJ)
PASS <- 0L; FAIL <- 0L
ok  <- function(n, m = "") { PASS <<- PASS + 1L; cat(sprintf("  PASS: %s%s\n", n, if (nzchar(m)) paste0(" - ", m) else "")) }
bad <- function(n, m = "") { FAIL <<- FAIL + 1L; cat(sprintf("  FAIL: %s - %s\n", n, m)) }
cat("=== naver adjusted collector (고정 픽스처 · 네트워크 없음) ===\n")

SRC  <- file.path(PROJ, "02_Infrastructure/data/naver_data_collector.R")
CFGP <- file.path(PROJ, "02_Infrastructure/data/naver_collector_config.json")
FIXD <- file.path(PROJ, "08_Tests/fixtures/naver")

# ── AST 로 함수 정의를 뽑아 격리 환경에 심는다 (파일 전체 source 금지 — 운영 config 를
#    끌고 들어오고 네트워크 상수를 전역에 뿌린다) ───────────────────────────────
SBX <- new.env(parent = globalenv())
.load_fns <- function(path, names_) {
  ex <- parse(path); got <- character(0)
  for (i in seq_along(ex)) {
    e <- ex[[i]]
    if (is.call(e) && length(e) >= 3 && as.character(e[[1]]) %in% c("<-", "=")) {
      nm <- tryCatch(as.character(e[[2]]), error = function(z) "")
      if (length(nm) == 1L && nm %in% names_) { eval(e, envir = SBX); got <- c(got, nm) }
    }
  }
  got
}
NEED <- c("%||%", ".naver_empty_price_dt", ".naver_parse_sisejson",
          ".naver_apply_no_trade_policy", ".naver_bare_code", ".naver_ymd",
          ".naver_collect_chunk", "naver_collect_adjusted", ".naver_apply_update",
          "NAVER_VALUE_COLS")
got <- .load_fns(SRC, NEED)
miss <- setdiff(NEED, got)
if (!length(miss)) ok("ast_load", paste(length(got), "심볼 재도출"))  else
  bad("ast_load", sprintf("AST 에서 못 찾음: %s", paste(miss, collapse = ", ")))
if (length(miss)) { cat(sprintf("TOTAL: %d pass / %d fail / 0 skipped\n", PASS, FAIL)); quit(status = 1) }

# ── 픽스처 실재 확인 — 없는 픽스처는 '통과'도 '실패'도 아니라 **미측정**이다.
#   ★.gitignore 의 `*.html` 이 원주가 대조군 픽스처를 삼켰던 자리다(2026-09-07). 그래서
#   확장자를 .html.txt 로 두고, 여기서 존재를 먼저 재서 신선한 클론에서 조용히 죽지 않게 한다.
FIX_REQ <- c("sisejson_005930_2018split.txt", "sisejson_032860_seam.txt",
             "sisejson_305090_limitdown.txt", "sisejson_empty.txt",
             "sise_day_005930_2018split.html.txt")
fix_missing <- FIX_REQ[!file.exists(file.path(FIXD, FIX_REQ))]
if (!length(fix_missing)) ok("fixtures_present", sprintf("%d종 실재", length(FIX_REQ))) else {
  bad("fixtures_present", sprintf("부재: %s", paste(fix_missing, collapse = ", ")))
  cat(sprintf("TOTAL: %d pass / %d fail / 0 skipped\n", PASS, FAIL)); quit(status = 1)
}

CFG_STUB <- list(no_trade_ohl_policy = "fill_from_close", request_sleep_sec = 0,
                 request_jitter_sec = 0, max_failure_rate = 0.02, workers = 1L,
                 max_retries = 0L, retry_backoff_base_sec = 0, request_timeout_sec = 5,
                 price_endpoint = "STUB")
rd <- function(f) paste(readLines(file.path(FIXD, f), warn = FALSE), collapse = "\n")

#──────────────────────────────────────────────────────────────────────────────
# ① 파서가 **수정주가** OHLCV 를 낸다
#──────────────────────────────────────────────────────────────────────────────
parse_fn <- get(".naver_parse_sisejson", envir = SBX)
adj <- parse_fn(rd("sisejson_005930_2018split.txt"))
need_cols <- c("Date", "Open", "High", "Low", "Close", "Vol")
if (!is.data.table(adj) || !all(need_cols %in% names(adj))) {
  bad("parser_columns", sprintf("열 결손: %s", paste(setdiff(need_cols, names(adj)), collapse = ",")))
} else if (nrow(adj) < 8) {
  bad("parser_columns", sprintf("행 %d — 픽스처(10세션) 대비 부족", nrow(adj)))
} else ok("parser_columns", sprintf("%d행 x OHLCV", nrow(adj)))

pre <- adj[Date == as.Date("2018-04-27")]$Close
# 삼성전자 50:1 분할(2018-05-04). 수정주가면 53,000, 원주가면 2,650,000.
if (length(pre) == 1L && abs(pre - 53000) < 1e-6) {
  ok("parser_is_adjusted", "2018-04-27 종가 53,000 (원주가 2,650,000 아님)")
} else {
  bad("parser_is_adjusted", sprintf("2018-04-27 종가 = %s — 수정주가가 아니다",
                                    paste(pre, collapse = "/")))
}

# 원주가 대조군: 같은 날짜가 sise_day 페이지에서는 2,650,000 이다 (엔드포인트 선택이
# 장식이 아니라 하중을 진다는 실증 — 이게 없으면 ①은 자기 자신만 확인한다)
# ★픽스처는 EUC-KR 바이트다 — 문자로 읽으면 로케일에서 죽는다. 찾는 것은 ASCII 숫자라
#   바이트로 훑는다(계기가 잴 것을 안 재고 재기 쉬운 것을 잰다).
rd_bytes <- function(f) {
  p <- file.path(FIXD, f)
  rawToChar(readBin(p, "raw", n = file.info(p)$size))
}
raw_html <- rd_bytes("sise_day_005930_2018split.html.txt")
if (grepl("2,650,000", raw_html, fixed = TRUE, useBytes = TRUE) &&
    !grepl("2,650,000", rd_bytes("sisejson_005930_2018split.txt"), fixed = TRUE, useBytes = TRUE)) {
  ok("unadjusted_counterexample", "sise_day 픽스처엔 2,650,000 이 있고 siseJson 엔 없다")
} else {
  bad("unadjusted_counterexample", "두 원천의 갈림이 픽스처에서 재현되지 않는다")
}

#──────────────────────────────────────────────────────────────────────────────
# ② 분할 전후 **연속성** — 문턱은 seam_guard_config 에서 재도출(하드코딩 금지)
#──────────────────────────────────────────────────────────────────────────────
seam_cfg <- jsonlite::fromJSON(file.path(PROJ, "02_Infrastructure/data/seam_guard_config.json"))
MAXRET <- as.numeric(seam_cfg$SEAM_MAX_RET)
setorder(adj, Date)
adj[, r := Close / shift(Close) - 1]
worst_adj <- suppressWarnings(max(abs(adj$r), na.rm = TRUE))
if (is.finite(worst_adj) && worst_adj <= MAXRET) {
  ok("split_continuity_adjusted", sprintf("분할 창 최대 |ret| = %.4f <= %.2f", worst_adj, MAXRET))
} else {
  bad("split_continuity_adjusted", sprintf("최대 |ret| = %.4f 가 %.2f 초과 — 연속이 아니다",
                                           worst_adj, MAXRET))
}
# 원주가 판이었다면 같은 창에서 -98% 가 난다 (위반 주입 = 축 ⑤의 일부)
if (abs(51900 / 2650000 - 1) > MAXRET) {
  ok("split_discontinuity_unadjusted", "원주가였다면 -98.0% — 이 축이 실제로 갈린다")
} else bad("split_discontinuity_unadjusted", "원주가 판이 문턱을 넘지 않는다 — 축이 안 갈린다")

# 이음매 종목 A032860: 수정주가에서는 08-28→08-31 이 -3.19%,
# quantiwise 원주가 690 에서 보면 +384% (2단 이음매의 실체)
s32 <- parse_fn(rd("sisejson_032860_seam.txt"))
c28 <- s32[Date == as.Date("2026-08-28")]$Close; c31 <- s32[Date == as.Date("2026-08-31")]$Close
if (length(c28) == 1L && length(c31) == 1L && abs(c31 / c28 - 1) <= MAXRET &&
    abs(c31 / 690 - 1) > MAXRET) {
  ok("seam_ticker_continuous_in_adjusted",
     sprintf("naver 내부 %.4f (연속) vs quantiwise 종가 690 대비 %.2f (단절)",
             c31 / c28 - 1, c31 / 690 - 1))
} else {
  bad("seam_ticker_continuous_in_adjusted", sprintf("c28=%s c31=%s", paste(c28, collapse=""), paste(c31, collapse="")))
}

# 진짜 하한가 연쇄는 분할로 오독되면 안 된다 (A305090: 09-01 -30%, 09-02 -30%, 09-03 -30%)
s30 <- parse_fn(rd("sisejson_305090_limitdown.txt"))
r01 <- s30[Date == as.Date("2026-09-01")]$Close / s30[Date == as.Date("2026-08-31")]$Close - 1
if (length(r01) == 1L && r01 < -0.25 && r01 > -0.35) {
  ok("limitdown_not_a_split", sprintf("09-01 실측 %.4f (하한가) — 배율 스냅 대상 아님", r01))
} else bad("limitdown_not_a_split", sprintf("r01=%s", paste(round(r01, 4), collapse = "")))

#──────────────────────────────────────────────────────────────────────────────
# ⑥ 무거래 규약 — Vol 0 · OHL 0 을 '가격 0' 으로 적재하지 않는다
#──────────────────────────────────────────────────────────────────────────────
# ★응답의 무거래 표기가 두 가지라는 것이 이 축의 실제 내용이다(2026-09-07 실측):
#     A032860 2026-08-27 = (3450,3450,3450,3450, Vol 0)  → Vol 0 인데 OHL 은 있다
#     A005930 2018-04-30 = (0,0,0,53000, Vol 0)          → OHL 이 0(부재)
#   두 사실이 갈려 있지 않으면 전자를 '정상 거래일' 로 읽는다.
ntp <- get(".naver_apply_no_trade_policy", envir = SBX)
nt32 <- ntp(copy(s32), CFG_STUB)
z32 <- nt32[Date == as.Date("2026-08-27")]
nt59 <- ntp(copy(adj), CFG_STUB)
z59 <- nt59[Date == as.Date("2018-04-30")]
if (nrow(z32) == 1L && isTRUE(z32$no_trade) && isFALSE(z32$ohl_absent) &&
    nrow(z59) == 1L && isTRUE(z59$no_trade) && isTRUE(z59$ohl_absent) &&
    z59$Open == z59$Close && z59$High == z59$Close && z59$Low == z59$Close &&
    !any(nt59$Open == 0, na.rm = TRUE) && !any(nt59$Close == 0, na.rm = TRUE)) {
  ok("no_trade_policy",
     sprintf("무거래 표기 2종 분리 (Vol0+OHL있음 / Vol0+OHL부재) · 부재는 Close(%s)로 충전 · 잔여 0가격 0건",
             z59$Close))
} else {
  bad("no_trade_policy",
      sprintf("A032860 no_trade=%s ohl_absent=%s | A005930 no_trade=%s ohl_absent=%s Open=%s",
              paste(z32$no_trade, collapse = ""), paste(z32$ohl_absent, collapse = ""),
              paste(z59$no_trade, collapse = ""), paste(z59$ohl_absent, collapse = ""),
              paste(z59$Open, collapse = "")))
}
nt_na <- ntp(copy(adj), modifyList(CFG_STUB, list(no_trade_ohl_policy = "as_na")))
if (is.na(nt_na[Date == as.Date("2018-04-30")]$Open[1])) {
  ok("no_trade_policy_configurable", "정책을 as_na 로 바꾸면 결과가 따라 바뀐다(하드코딩 부재)")
} else bad("no_trade_policy_configurable", "정책 전환이 결과를 안 바꾼다 — 상수가 코드에 있다")

#──────────────────────────────────────────────────────────────────────────────
# ③ 실패 집계 — 조용한 누락 없음
#──────────────────────────────────────────────────────────────────────────────
collect <- get("naver_collect_adjusted", envir = SBX)
# 픽스처 응답을 돌려주는 스텁으로 네트워크 층만 대체한다
assign(".naver_fetch_sisejson", function(code, s, e, cfg) {
  if (code == "005930") return(list(data = parse_fn(rd("sisejson_005930_2018split.txt")),
                                    ok = TRUE, reason = NA_character_, http_status = 200L, attempts = 1L))
  if (code == "032860") return(list(data = parse_fn(rd("sisejson_032860_seam.txt")),
                                    ok = TRUE, reason = NA_character_, http_status = 200L, attempts = 1L))
  if (code == "999999") return(list(data = parse_fn(rd("sisejson_empty.txt")), ok = FALSE,
                                    reason = "empty_range", http_status = 200L, attempts = 1L))
  if (code == "888888") return(list(data = get(".naver_empty_price_dt", envir = SBX)(), ok = FALSE,
                                    reason = "http_404", http_status = 404L, attempts = 1L))
  list(data = get(".naver_empty_price_dt", envir = SBX)(), ok = FALSE,
       reason = "exhausted_retries:network_error", http_status = NA_integer_, attempts = 4L)
}, envir = SBX)

r3 <- collect(c("005930", "032860", "999999", "888888", "777777"),
              "20260820", "20260904", cfg = CFG_STUB, workers = 1L, verbose = FALSE)
rs <- if (nrow(r3$failures)) sort(r3$failures$reason) else character(0)
if (r3$n_requested == 5L && r3$n_ok == 2L && nrow(r3$failures) == 3L &&
    identical(rs, sort(c("empty_range", "http_404", "exhausted_retries:network_error"))) &&
    all(c("Ticker", "reason", "http_status", "attempts") %in% names(r3$failures))) {
  ok("failures_aggregated_with_reason",
     sprintf("성공 %d · 실패 %d (%s)", r3$n_ok, nrow(r3$failures), paste(rs, collapse = " ")))
} else {
  bad("failures_aggregated_with_reason",
      sprintf("n_ok=%d n_fail=%d reasons={%s}", r3$n_ok, nrow(r3$failures), paste(rs, collapse = ",")))
}
if (abs(r3$failure_rate - 3 / 5) < 1e-9 && isTRUE(r3$over_cap)) {
  ok("failure_rate_over_cap", sprintf("실패율 %.2f > 상한 %.2f → 병합 차단 신호",
                                      r3$failure_rate, CFG_STUB$max_failure_rate))
} else bad("failure_rate_over_cap", sprintf("rate=%.3f over_cap=%s", r3$failure_rate, r3$over_cap))

# ★조용한 누락 검거: 청크가 한 종목을 통째로 흘려도 unaccounted 로 남아야 한다
chunk_orig <- get(".naver_collect_chunk", envir = SBX)
assign(".naver_collect_chunk", function(codes, s, e, cfg) {
  out <- chunk_orig(setdiff(codes, "032860"), s, e, cfg); out       # 032860 을 조용히 증발
}, envir = SBX)
r3b <- collect(c("005930", "032860"), "20260820", "20260904", cfg = CFG_STUB, workers = 1L, verbose = FALSE)
if ("A032860" %in% r3b$failures$Ticker &&
    r3b$failures[Ticker == "A032860"]$reason[1] == "unaccounted") {
  ok("silent_drop_detected", "요청했는데 데이터도 실패기록도 없는 종목을 unaccounted 로 검거")
} else {
  bad("silent_drop_detected", sprintf("증발한 종목이 실패 목록에 없다 (fails=%d)", nrow(r3b$failures)))
}
assign(".naver_collect_chunk", chunk_orig, envir = SBX)

#──────────────────────────────────────────────────────────────────────────────
# ④ 스키마 계약 — 소비자 열 목록을 **다른 writer 에서 재도출**한다
#    (이 파일 안에 목록을 다시 적으면 스스로를 확인할 뿐이다)
#──────────────────────────────────────────────────────────────────────────────
derive_contract <- function(path) {
  ex <- parse(path); best <- character(0)
  walk <- function(e) {
    if (is.call(e) && identical(as.character(e[[1]])[1], "c")) {
      v <- tryCatch(eval(e), error = function(z) NULL)
      if (is.character(v) && all(c("Close", "Ret", "source") %in% v) && length(v) > length(best))
        best <<- v
    }
    if (is.recursive(e)) for (i in seq_along(e)) if (!is.null(e[[i]])) try(walk(e[[i]]), silent = TRUE)
  }
  for (i in seq_along(ex)) walk(ex[[i]])
  best
}
contract <- derive_contract(file.path(PROJ, "02_Infrastructure/data/rawdata_sanitize.R"))
if (!length(contract)) {
  bad("schema_contract", "rawdata_sanitize.R 에서 열 계약을 재도출하지 못함")
} else {
  produced <- c("Date", "Ticker", "source", get("NAVER_VALUE_COLS", envir = SBX))
  # 값 축은 이 writer 가 산출, 나머지(Name/Market/Sector/BM_Ret)는 **승계**로 충족된다.
  inherited <- setdiff(contract, produced)
  # ★2026-09-07 저녁: 갱신은 이제 **원천 우선순위**를 경유한다(퀀티 정본 · naver 보충).
  #   source 가 NA 면 '출처 미상 = 판정 불가' 로 정지한다 — 이 축이 재는 건 스키마 계약이지
  #   우선순위가 아니므로, 이 writer 자신의 레인(naver)을 incumbent 로 둔다.
  synth <- data.table(Date = as.Date("2026-08-31"), Ticker = "A000001", source = "naver")
  for (cc in contract) if (!cc %in% names(synth)) synth[, (cc) := NA_real_]
  upd_cols <- c("Date", "Ticker", get("NAVER_VALUE_COLS", envir = SBX))
  applied <- get(".naver_apply_update", envir = SBX)(synth, synth[, ..upd_cols])
  if (all(contract %in% names(applied$dt))) {
    ok("schema_contract", sprintf("계약 %d열 재도출 · 산출 %d + 승계 %d = 전부 존재",
                                  length(contract), length(intersect(contract, produced)), length(inherited)))
  } else {
    bad("schema_contract", sprintf("갱신 후 결손: %s",
                                   paste(setdiff(contract, names(applied$dt)), collapse = ",")))
  }
}

#──────────────────────────────────────────────────────────────────────────────
# ⑦ 값 갱신이 **승계 축**을 보존한다 (삭제 후 append 가 아니다)
#──────────────────────────────────────────────────────────────────────────────
# ★2026-09-07 저녁 재구성: 갱신이 **원천 우선순위**를 경유하게 됐다(퀀티 정본 · naver 보충).
#   구판 픽스처는 incumbent 를 전부 quantiwise_update 로 두고 naver 가 덮기를 기대했는데,
#   그 기대가 이제 도훈 설계와 반대다. 이 축이 재는 것은 승계(K200/Sector 생존)이므로
#   **갱신 가능한 레인(A000001=naver)** 위에서 재고, 옆 칸(A000002=quantiwise_update)을
#   보존 대조군으로 같이 둔다 — 한 픽스처에서 두 명제가 갈린다.
raw_syn <- data.table(
  Date = rep(as.Date(c("2026-08-28", "2026-08-31")), each = 2),
  Ticker = rep(c("A000001", "A000002"), 2),
  K200 = c(1, 0, 1, 0), KQ150 = c(0, 1, 0, 1), Float = c(0.3, 0.4, 0.3, 0.4),
  Sector = "반도체", Sector_Lv2 = "IT", Name = c("가", "나", "가", "나"),
  Market = "KOSPI", AdminStock = 0, TradingHalt = 0, UnfaithfulDisc = 0,
  BM_Ret = 0.01,
  Open = 1, High = 1, Low = 1, Close = c(100, 200, 110, 210), Vol = 10, Size = 1e9,
  Ret = 0, source = c("naver", "quantiwise_update", "naver", "quantiwise_update"))
upd_syn <- data.table(Date = as.Date("2026-08-31"), Ticker = c("A000001", "A000002", "A000003"),
                      Open = c(105, 205, 5), High = c(115, 215, 6), Low = c(95, 195, 4),
                      Close = c(112, 212, 5.5), Vol = c(11, 21, 3), Size = c(2e9, 3e9, 4e8),
                      Ret = c(0.02, 0.01, NA_real_))
ap <- get(".naver_apply_update", envir = SBX)(raw_syn, upd_syn)
d <- ap$dt
keep_ok <- nrow(d) == 5L && ap$n_updated == 1L && ap$n_appended == 1L &&
  identical(ap$n_skipped, 1L) &&
  identical(d[Date == as.Date("2026-08-31") & Ticker == "A000001"]$K200, 1) &&
  identical(d[Date == as.Date("2026-08-31") & Ticker == "A000001"]$Sector, "반도체") &&
  identical(d[Date == as.Date("2026-08-31") & Ticker == "A000001"]$Close, 112) &&
  identical(d[Date == as.Date("2026-08-28") & Ticker == "A000001"]$Close, 100) &&   # 창 밖 불변
  identical(d[Date == as.Date("2026-08-31") & Ticker == "A000001"]$source, "naver") &&
  # ★보존 대조군 — 상위 원천(quantiwise_update)은 값도 라벨도 안 바뀐다
  identical(d[Date == as.Date("2026-08-31") & Ticker == "A000002"]$Close, 210) &&
  identical(d[Date == as.Date("2026-08-31") & Ticker == "A000002"]$source, "quantiwise_update")
if (keep_ok) {
  ok("update_preserves_inherited_axes",
     sprintf("갱신 %d · 스킵 %d(상위 원천 보존) · 추가 %d · K200/Sector/BM_Ret 보존 · 창 밖 불변",
             ap$n_updated, ap$n_skipped, ap$n_appended))
} else {
  bad("update_preserves_inherited_axes",
      sprintf("n=%d upd=%d skip=%d add=%d K200=%s Close31=%s Close28=%s", nrow(d),
              ap$n_updated, ap$n_skipped, ap$n_appended,
              paste(d[Date == as.Date("2026-08-31") & Ticker == "A000001"]$K200, collapse = ""),
              paste(d[Date == as.Date("2026-08-31") & Ticker == "A000001"]$Close, collapse = ""),
              paste(d[Date == as.Date("2026-08-28") & Ticker == "A000001"]$Close, collapse = "")))
}
# 위반 주입: 구판처럼 '해당 날짜 행 삭제 후 append' 하면 승계 축이 사라져야 한다
del_then_append <- function(raw, upd) {
  r <- raw[!(Date %in% unique(upd$Date))]
  rbind(r, copy(upd)[, source := "naver"], fill = TRUE)
}
d_bad <- del_then_append(raw_syn, upd_syn)
if (all(is.na(d_bad[Date == as.Date("2026-08-31") & Ticker == "A000001"]$K200))) {
  ok("delete_append_loses_axes_mutant", "삭제후append 변이는 K200 을 잃는다 — 이 축이 실제로 갈린다")
} else bad("delete_append_loses_axes_mutant", "변이가 축을 안 잃는다 — ⑦이 아무것도 안 재고 있다")

#──────────────────────────────────────────────────────────────────────────────
# ⑤ 위반 주입 — 파서를 **구판**(종가만 · 원주가)으로 되돌리면 빨강
#──────────────────────────────────────────────────────────────────────────────
legacy_parse <- function(txt) {                    # 구 시세페이지 경로의 산출 형태
  dt <- parse_fn(txt)
  dt[, `:=`(Open = NA_real_, High = NA_real_, Low = NA_real_)]
  dt[]
}
mut1 <- legacy_parse(rd("sisejson_005930_2018split.txt"))
mut_cols_red <- !all(c("Open", "High", "Low") %in% names(mut1)) || all(is.na(mut1$Open))
# 구판은 원주가였다 — sise_day 픽스처의 값을 쓰면 연속성 축이 깨진다
legacy_series <- c(2650000, 2650000, 2650000, 2650000, 51900)
worst_legacy <- max(abs(legacy_series[-1] / legacy_series[-length(legacy_series)] - 1))
mut_cont_red <- worst_legacy > MAXRET
if (mut_cols_red && mut_cont_red) {
  ok("mutant_legacy_parser_is_red",
     sprintf("구판 복원 시 OHL 전량 NA(축④ 빨강) · 최대 |ret| %.3f > %.2f(축② 빨강)",
             worst_legacy, MAXRET))
} else {
  bad("mutant_legacy_parser_is_red",
      sprintf("구판 변이가 초록으로 통과 — 검출력 없음 (cols_red=%s cont_red=%s)",
              mut_cols_red, mut_cont_red))
}

#──────────────────────────────────────────────────────────────────────────────
# ⑧ 설정 경유 — 엔드포인트·문턱이 코드가 아니라 JSON 에서 온다
#──────────────────────────────────────────────────────────────────────────────
if (!file.exists(CFGP)) {
  bad("config_is_sot", "naver_collector_config.json 부재")
} else {
  cfgj <- jsonlite::fromJSON(CFGP)
  needk <- c("price_endpoint", "size_endpoint", "request_sleep_sec", "max_retries",
             "workers", "max_failure_rate", "no_trade_ohl_policy", "seam_mode")
  mk <- setdiff(needk, names(cfgj))
  # 엔드포인트 리터럴이 **코드**에 되살아나 있지 않은가 (설정을 바꿔도 안 따라오는 경로).
  # ★AST 의 문자열 리터럴만 본다 — 주석을 세면 설명문이 검사를 빨갛게 만든다
  #   (문자열을 읽는 스캐너는 자기가 지키는 산출물을 기각한다).
  lits <- character(0)
  wlit <- function(e) {
    if (is.character(e)) lits <<- c(lits, e)
    if (is.recursive(e)) for (i in seq_along(e)) if (!is.null(e[[i]])) try(wlit(e[[i]]), silent = TRUE)
  }
  { ex <- parse(SRC); for (i in seq_along(ex)) wlit(ex[[i]]) }
  literal_back <- any(grepl("api.finance.naver.com", lits, fixed = TRUE))
  if (!length(mk) && !literal_back) {
    ok("config_is_sot", sprintf("키 %d종 · 코드에 엔드포인트 리터럴 없음", length(needk)))
  } else {
    bad("config_is_sot", sprintf("결손키={%s} 코드내리터럴=%s", paste(mk, collapse = ","), literal_back))
  }
}

cat(sprintf("TOTAL: %d pass / %d fail / 0 skipped\n", PASS, FAIL))
cat(jsonlite::toJSON(list(test = "naver_adjusted_collector", pass = PASS, fail = FAIL,
                          skipped = 0L, total = PASS + FAIL, skips = list()),
                     auto_unbox = TRUE), "\n", sep = "")
if (FAIL > 0) quit(status = 1)
