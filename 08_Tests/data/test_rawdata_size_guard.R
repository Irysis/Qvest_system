#==============================================================================
# test_rawdata_size_guard.R — W-02 (RAWDATA.Size 결측 사고) 수리·경보의 상설 검사
#
# 사고(2026-09-23 감사 W-02 confirmed): Naver 시총 페이지가 SPA(UTF-8)로 바뀌어 스냅샷이
#   09-12 부터 매 실행 "`x` must be a single string, not a character NA" 로 죽었고, 파이프라인은
#   '장중 스냅샷 의심' 으로 원인을 오귀속했다. 복원 경로는 창 안의 가격 일치일만 썼으므로
#   직전일 Size 까지 비면 원리상 복원 불가였다(09-10~22 100% 결측). factor_db_202609 에서
#   V01~V24·S01·S02·L26 27종 0행, emission_report class_R=27 은 reader 0.
#
# 축(각각 양성 대조 + 위반 주입 + 돌연변이 통제):
#   A 디코더      — UTF-8/EUC-KR 양성 · 무효 바이트 = 명시 에러 · 구판 디코드 = 사고 재현
#   B 레거시 구조 — SPA 페이지 = '구조 변경' 명시 에러(NULL/0행 아님)
#   C API 파서    — 정수 주식수 · 구조 변경 명시 에러 · 억원 반올림 변이 = 정수성 탈락
#   D 복원        — 크기 앵커 행을 넘기면 reconstructed(양성) · 안 넘기면 no_matching_day(돌연변이)
#                   · 기준 차단 · 직접 관측 · 불안정 사유 · 앵커일 선택(채움률 문턱 경유)
#   E 채움률 가드 — 순수 판정 · cache_freshness_audit VALUE_FAIL(주입) / 축 제거 시 PASS(돌연변이)
#   F 배출 게이트 — class_R=1 픽스처 → REGRESS · 부재 → UNMEASURED
#   G 배선        — daily_refresh.sh 의 실제 [1z]·[6a-gate] 블록을 잘라 실행 → DR_FAILED 적재,
#                   DR_FAILED 줄을 지운 돌연변이는 적재 0 (검출력 실증)
#   H 원인 귀속   — 스냅샷 실패 시 파이프라인이 '장중 스냅샷 의심' 이 아니라 '스냅샷 부재' 를 찍는다
#
# 네트워크 없음(전부 고정 픽스처·모의 GET). 운영 산출물 무접촉 — 임시물은 .cache/_test_fx_size_guard
#   (gitignore) 아래에만 쓰고 모든 종료 경로에서 지운다.
# 요약 규약: 마지막 줄 {"test":"rawdata_size_guard","pass":N,"fail":N,"total":N}
#==============================================================================
suppressPackageStartupMessages({
  library(data.table); library(jsonlite); library(arrow); library(xml2); library(rvest); library(httr)
})

.MARKER <- "02_Infrastructure/data/naver_data_collector.R"
.script_dir <- function() {
  a <- commandArgs(trailingOnly = FALSE)
  m <- grep("^--file=", a, value = TRUE)
  if (!length(m)) return("")
  dirname(sub("^--file=", "", m[1L]))
}
.sd <- .script_dir()
PROJ <- ""
for (.c in c(Sys.getenv("QM_ROOT", ""), Sys.getenv("CLAUDE_PROJECT_DIR", ""),
             if (nzchar(.sd)) file.path(.sd, "..", "..") else "", getwd())) {
  .c <- gsub("\\\\", "/", .c)
  if (nzchar(.c) && file.exists(file.path(.c, .MARKER))) { PROJ <- normalizePath(.c, winslash = "/"); break }
}
if (!nzchar(PROJ)) stop("[test_rawdata_size_guard] PROJECT_ROOT 해석 실패 — 표지 부재: ", .MARKER)
PROJECT_ROOT <- PROJ          # 가드·감사기가 루트를 이 이름으로 찾는다(env 의존 제거)

PASS <- 0L; FAIL <- 0L
ok  <- function(n, m = "") { PASS <<- PASS + 1L; cat(sprintf("  PASS: %s - %s\n", n, m)) }
bad <- function(n, m = "") { FAIL <<- FAIL + 1L; cat(sprintf("  FAIL: %s - %s\n", n, m)) }
chk <- function(n, cond, m = "") if (isTRUE(cond)) ok(n, m) else bad(n, m)

SRC  <- file.path(PROJ, .MARKER)
FIXD <- file.path(PROJ, "08_Tests/fixtures/naver")
FXDIR <- file.path(PROJ, ".cache", "_test_fx_size_guard")
unlink(FXDIR, recursive = TRUE); dir.create(FXDIR, recursive = TRUE, showWarnings = FALSE)
.cleanup <- function() unlink(FXDIR, recursive = TRUE)
fin <- function() {
  .cleanup()
  cat(sprintf("TOTAL: %d pass / %d fail\n", PASS, FAIL))
  cat(toJSON(list(test = "rawdata_size_guard", pass = PASS, fail = FAIL, total = PASS + FAIL),
             auto_unbox = TRUE), "\n")
  quit(save = "no", status = if (FAIL > 0L) 1L else 0L)
}

cat("=== rawdata size guard (W-02) ===\n")

# ── 수집기 함수를 AST 로 꺼내 격리 환경에 심는다(파일 전체 source 금지 — 운영 config/네트워크) ──
SBX <- new.env(parent = globalenv())
NEED <- c("%||%", ".naver_decode_html", ".naver_sise_page", ".naver_last_page",
          ".naver_empty_size_dt", ".naver_parse_size_api", ".naver_resolve_size",
          ".naver_size_anchor_date", "naver_run_pipeline")
{
  ex <- parse(SRC); got <- character(0)
  for (i in seq_along(ex)) {
    e <- ex[[i]]
    if (is.call(e) && length(e) >= 3 && as.character(e[[1]]) %in% c("<-", "=")) {
      nm <- tryCatch(as.character(e[[2]]), error = function(z) "")
      if (length(nm) == 1L && nm %in% NEED) { eval(e, envir = SBX); got <- c(got, nm) }
    }
  }
}
miss <- setdiff(NEED, got)
chk("ast_load", !length(miss), if (length(miss)) paste("부재:", paste(miss, collapse = ",")) else
  sprintf("%d 심볼", length(got)))
if (length(miss)) fin()
F <- function(nm) get(nm, envir = SBX)
CFG <- jsonlite::fromJSON(file.path(PROJ, "02_Infrastructure/data/naver_collector_config.json"))

#──────────────────────────────────────────────────────────────────────────────
# A 디코더
#──────────────────────────────────────────────────────────────────────────────
spa_raw <- readBin(file.path(FIXD, "sise_market_sum_spa_utf8.html.txt"), "raw", 1e7)
a1 <- tryCatch(F(".naver_decode_html")(spa_raw, "text/html; charset=utf-8", "fx"), error = function(e) e)
chk("A1_utf8_declared_decodes", is.character(a1) && !is.na(a1) &&
      grepl("Npay", html_text(html_node(read_html(a1), "title")), fixed = TRUE),
    "SPA(UTF-8) 본문 → 유효 문자열 · title 판독")
a1b <- tryCatch(F(".naver_decode_html")(spa_raw, NULL, "fx"), error = function(e) e)
chk("A1b_utf8_undeclared_retry", is.character(a1b) && !is.na(a1b),
    "charset 미선언이어도 EUC-KR 실패 후 UTF-8 재시도로 복구")
euc <- iconv("<html><body><table class=\"type_2\"><tr><td>삼성전자</td></tr></table></body></html>",
             from = "UTF-8", to = "EUC-KR", toRaw = TRUE)[[1]]
a2 <- tryCatch(F(".naver_decode_html")(euc, "text/html; charset=euc-kr", "fx"), error = function(e) e)
chk("A2_euckr_positive", is.character(a2) && grepl("삼성전자", a2, fixed = TRUE), "EUC-KR 바이트 → 한글 보존")
badb <- as.raw(c(0x3c, 0x62, 0x3e, 0xff, 0xfe, 0x80, 0xc0, 0x3c, 0x2f, 0x62, 0x3e))
a3 <- tryCatch(F(".naver_decode_html")(badb, "text/html", "fx"), error = function(e) e)
chk("A3_invalid_bytes_explicit_error", inherits(a3, "error") && grepl("디코드 실패", conditionMessage(a3)),
    if (inherits(a3, "error")) conditionMessage(a3) else "에러 없이 통과(침묵)")
# 돌연변이 = 구판 디코드(EUC-KR 고정) → 사고 메시지 그대로 재현(이 테스트가 그 병을 본다는 증거)
legacy <- function(raw) read_html(iconv(rawToChar(raw), from = "EUC-KR", to = "UTF-8"))
a4 <- tryCatch(legacy(spa_raw), error = function(e) e)
chk("A4_mutant_legacy_reproduces_incident",
    inherits(a4, "error") && grepl("single string", conditionMessage(a4), fixed = TRUE),
    if (inherits(a4, "error")) conditionMessage(a4) else "구판이 통과 — 픽스처가 사고를 못 담는다")

#──────────────────────────────────────────────────────────────────────────────
# B 레거시 HTML 경로 — 구조 변경은 NULL 이 아니라 명시 에러 (모의 GET, 네트워크 없음)
#──────────────────────────────────────────────────────────────────────────────
mock_resp <- function(body, ct, url = "https://stock.naver.com/market/stock/kr/stocklist/capitalization")
  structure(list(url = url, status_code = 200L, content = body,
                 headers = structure(list(`content-type` = ct), class = c("insensitive", "list"))),
            class = "response")
SBX$GET <- function(...) mock_resp(spa_raw, "text/html; charset=utf-8")
b1 <- tryCatch(F(".naver_sise_page")(0, 1, CFG), error = function(e) e)
chk("B1_spa_structure_change_is_explicit", inherits(b1, "error") && grepl("구조 변경", conditionMessage(b1)),
    if (inherits(b1, "error")) conditionMessage(b1) else sprintf("에러 없이 반환(class=%s)", class(b1)[1]))
b2 <- tryCatch(F(".naver_last_page")(0, CFG), error = function(e) e)
chk("B2_last_page_not_silent_1", inherits(b2, "error"),
    if (inherits(b2, "error")) "구조 변경 = 에러(구판은 1페이지로 위장)" else paste("반환값", format(b2)))
rm("GET", envir = SBX)

#──────────────────────────────────────────────────────────────────────────────
# C API 파서
#──────────────────────────────────────────────────────────────────────────────
apitxt <- paste(readLines(file.path(FIXD, "marketvalue_api_kospi_p1_size5.json"), encoding = "UTF-8", warn = FALSE),
                collapse = "\n")
c1 <- tryCatch(F(".naver_parse_size_api")(apitxt, "KOSPI"), error = function(e) e)
if (inherits(c1, "error")) bad("C1_api_parse", conditionMessage(c1)) else {
  d <- c1$data
  js <- fromJSON(apitxt)
  chk("C1_api_parse", nrow(d) == 5L && identical(c1$total, as.integer(js$totalCount)),
      sprintf("%d행 · totalCount %s", nrow(d), c1$total))
  chk("C1b_size_is_krw_raw", all(d$Size == as.numeric(js$stocks$marketValueRaw)),
      "Size = marketValueRaw(원) — 배율 곱 없음")
  chk("C1c_shares_exact_integer", all(d$shares_exact) && all(d$snap_shares == round(d$snap_shares)),
      sprintf("A005930 shares=%s", format(d[Ticker == "A005930"]$snap_shares, big.mark = ",")))
}
c2 <- tryCatch(F(".naver_parse_size_api")('{"items":[]}', "KOSPI"), error = function(e) e)
chk("C2_structure_change_explicit", inherits(c2, "error") && grepl("구조 변경", conditionMessage(c2)),
    if (inherits(c2, "error")) conditionMessage(c2) else "무에러")
c2b <- tryCatch(F(".naver_parse_size_api")('{"stocks":[{"itemCode":"005930","closePriceRaw":"1"}],"totalCount":1}', "KOSPI"),
                error = function(e) e)
chk("C2b_missing_field_explicit", inherits(c2b, "error") && grepl("marketValueRaw", conditionMessage(c2b)),
    if (inherits(c2b, "error")) conditionMessage(c2b) else "무에러")
# 돌연변이: 시총을 억원 반올림(레거시 단위)으로 바꾸면 정수성이 깨져 직접 관측에서 빠져야 한다
mut <- fromJSON(apitxt)
mut$stocks$marketValueRaw <- as.character(round(as.numeric(mut$stocks$marketValueRaw) / 1e8) * 1e8 + 12345)
c3 <- F(".naver_parse_size_api")(as.character(toJSON(mut, auto_unbox = TRUE)), "KOSPI")
chk("C3_mutant_rounded_cap_not_exact", !any(c3$data$shares_exact),
    sprintf("정수성 탈락 %d/%d", sum(!c3$data$shares_exact), nrow(c3$data)))

#──────────────────────────────────────────────────────────────────────────────
# D 복원 — 검증자 정정의 양성 대조: '스냅샷 없이 창 이전 Size 만 있는 합성 창'
#──────────────────────────────────────────────────────────────────────────────
RS <- F(".naver_resolve_size")
d_pre <- as.Date("2026-09-01") + 0:4          # 창 이전 5일(Size 있음)
d_win <- as.Date("2026-09-08") + 0:2          # 창(Size 결측)
tk <- c("A000001", "A000002", "A000003")
sh <- c(1e6, 2e6, 3e6)
px <- function(t, d) 1000 * match(t, tk) + as.numeric(d - as.Date("2026-09-01"))
syn <- CJ(Date = c(d_pre, d_win), Ticker = tk)
syn[, Close := px(Ticker, Date)]
syn[, Size := fifelse(Date %in% d_pre, sh[match(Ticker, tk)] * Close, NA_real_)]
anchor <- max(d_pre)
new_win <- syn[Date %in% d_win, .(Date, Ticker, Close)]
# 양성: 크기 앵커일 행을 new 와 pool 양쪽에 넘긴다(naver_backfill_range 의 size_anchor 경로와 같은 모양)
d1 <- RS(rbind(syn[Date == anchor, .(Date, Ticker, Close)], new_win),
         rbind(syn[Date == anchor, .(Date, Ticker, Close, Size)], syn[Date %in% d_win, .(Date, Ticker, Close, Size)]),
         CFG)[Date %in% d_win]
exp_sz <- sh[match(d1$Ticker, tk)] * d1$Close
chk("D1_positive_reconstructed_from_anchor",
    all(d1$size_source == "reconstructed_shares_x_close") && isTRUE(all.equal(d1$Size, exp_sz)),
    sprintf("출처 %s · Size=shares×Close 정확", paste(unique(d1$size_source), collapse = "/")))
# 돌연변이(구판 경로): 창 안 행만 넘기면 짝이 0 → 복원 불가 — 이것이 09-10~22 100% 결측의 기전
d2 <- RS(new_win, syn[Date %in% d_win, .(Date, Ticker, Close, Size)], CFG)
chk("D2_mutant_window_only_cannot_recover", all(d2$size_source == "unavailable_no_matching_day") && all(is.na(d2$Size)),
    "크기 앵커 없이는 no_matching_day (검증자 정정이 하중을 진다)")
# 기준 차단: 차단 종목은 사유 NA, 같은날 스냅샷은 허용
bb <- data.table(Ticker = "A000002", reason = "unavailable_adjustment_basis_break")
pool3 <- rbind(syn[Date == anchor, .(Date, Ticker, Close, Size)],
               data.table(Date = d_win[3], Ticker = "A000002", Close = px("A000002", d_win[3]), Size = 777))
d3 <- RS(rbind(syn[Date == anchor, .(Date, Ticker, Close)], new_win), pool3, CFG, basis_block = bb)[Date %in% d_win]
chk("D3_basis_block_reason",
    all(d3[Ticker == "A000002" & Date != d_win[3]]$size_source == "unavailable_adjustment_basis_break") &&
      all(is.na(d3[Ticker == "A000002" & Date != d_win[3]]$Size)) &&
      identical(d3[Ticker == "A000002" & Date == d_win[3]]$size_source, "snapshot_same_day") &&
      all(d3[Ticker != "A000002"]$size_source == "reconstructed_shares_x_close"),
    "차단 종목 = 사유 NA · 같은날 스냅샷은 허용 · 비차단 종목은 복원")
# 직접 관측: pool 없이 정수 주식수만으로 복원
so <- data.table(Ticker = tk, shares = sh)
d4 <- RS(new_win, NULL, CFG, shares_obs = so)
chk("D4_direct_shares_obs", all(d4$size_source == "reconstructed_shares_x_close") &&
      isTRUE(all.equal(d4$Size, sh[match(d4$Ticker, tk)] * d4$Close)), "스냅샷 가격 불일치와 무관하게 주식수로 복원")
# 불안정: 앵커 주식수와 직접 관측이 허용오차 밖 → 사유 NA (부재를 값으로 위장하지 않는다)
so5 <- data.table(Ticker = tk, shares = sh * c(1, 1 + 3 * as.numeric(CFG$size_shares_tol), 1))
d5 <- RS(rbind(syn[Date == anchor, .(Date, Ticker, Close)], new_win),
         syn[Date == anchor, .(Date, Ticker, Close, Size)], CFG, shares_obs = so5)[Date %in% d_win]
chk("D5_unstable_shares_na",
    all(d5[Ticker == "A000002"]$size_source == "unavailable_shares_unstable") && all(is.na(d5[Ticker == "A000002"]$Size)) &&
      all(d5[Ticker != "A000002"]$size_source == "reconstructed_shares_x_close"),
    sprintf("spread %.0f%% > tol %.0f%% → NA", 300 * as.numeric(CFG$size_shares_tol), 100 * as.numeric(CFG$size_shares_tol)))
# 앵커일 선택 — 채움률 문턱(registry fill_rate) 경유. 정본 설정 파일은 읽기만 한다.
DATA_DIR <- file.path(PROJ, "02_Infrastructure/data")
assign("DATA_DIR", DATA_DIR, envir = SBX)
sa <- tryCatch(F(".naver_size_anchor_date")(copy(syn), min(d_win)), error = function(e) e)
chk("D6_anchor_date_last_filled_day", inherits(sa, "Date") && identical(sa, anchor),
    if (inherits(sa, "error")) conditionMessage(sa) else paste("앵커", sa))
syn6 <- copy(syn); syn6[Date == anchor & Ticker == "A000001", Size := NA_real_]   # 33% 결측 주입
sa6 <- tryCatch(F(".naver_size_anchor_date")(syn6, min(d_win)), error = function(e) e)
chk("D6b_injected_gap_moves_anchor_back", inherits(sa6, "Date") && identical(sa6, anchor - 1L),
    if (inherits(sa6, "error")) conditionMessage(sa6) else paste("앵커", sa6, "(결측 주입일 회피)"))

#──────────────────────────────────────────────────────────────────────────────
# E 채움률 가드 + cache_freshness_audit 통합
#──────────────────────────────────────────────────────────────────────────────
FG <- new.env(parent = globalenv())
sys.source(file.path(PROJ, "02_Infrastructure/data/rawdata_fill_guard.R"), envir = FG)
spec <- tryCatch(FG$rawdata_fill_spec(file.path(PROJ, "02_Infrastructure/data/cache_registry.json")),
                 error = function(e) e)
chk("E0_registry_declares_fill_rate", is.list(spec) && all(c("Size", "BM_Ret") %in% spec$cols) &&
      is.finite(spec$max_na_rate), if (is.list(spec)) sprintf("cols=%s max_na=%s n_dates=%d",
      paste(spec$cols, collapse = ","), spec$max_na_rate, spec$n_dates) else conditionMessage(spec))
if (!is.list(spec)) fin()
mkpanel <- function(n = 200L) {
  p <- CJ(Date = as.Date("2026-09-17") + 0:2, Ticker = sprintf("A%06d", seq_len(n)))
  p[, `:=`(Close = 1000, Size = 1e11, BM_Ret = 0.001)]
  p
}
p_ok <- mkpanel()
p_ok[Date == max(Date) & Ticker == "A000001", Size := NA_real_]             # 0.5% 결측 = 정상 대역
v1 <- FG$rawdata_fill_verdict(FG$rawdata_fill_rates(p_ok, spec$cols, spec$n_dates), spec$max_na_rate)
chk("E1_pure_positive_ok", identical(v1$status, "OK"), sprintf("status=%s", v1$status))
p_bad <- mkpanel(); p_bad[Date == max(Date), Size := NA_real_]
v2 <- FG$rawdata_fill_verdict(FG$rawdata_fill_rates(p_bad, spec$cols, spec$n_dates), spec$max_na_rate)
chk("E2_pure_injection_fail", identical(v2$status, "FAIL") && "Size" %in% v2$violations$col,
    sprintf("status=%s viol=%s", v2$status, paste(v2$violations$col, collapse = ",")))
v3 <- FG$rawdata_fill_verdict(FG$rawdata_fill_rates(mkpanel()[, !"BM_Ret"], spec$cols, spec$n_dates), spec$max_na_rate)
chk("E3_missing_column_fail", identical(v3$status, "FAIL") && any(!v3$violations$present),
    "열 부재 = 위반(미측정을 정상으로 접지 않는다)")
# 통합: caches_override 로 사본 패널을 넣는다(정본 산출물 무접촉 persist=FALSE)
PROJECT_ROOT <- PROJ
source(file.path(PROJ, "02_Infrastructure/data/cache_freshness_audit.R"))
wr <- function(dt, nm) { p <- file.path(FXDIR, nm); write_parquet(dt, p); file.path(".cache", "_test_fx_size_guard", nm) }
rel_ok  <- wr(mkpanel(), "rawdata_ok.parquet")
rel_bad <- wr(p_bad, "rawdata_size_na.parquet")
ent <- function(rel, with_axis = TRUE) {
  vc <- list(required_cols = list("Date", "Ticker", "Size"))
  if (with_axis) vc$fill_rate <- list(cols = as.list(spec$cols), max_na_rate = spec$max_na_rate, n_dates = spec$n_dates)
  list(path = rel, tier = "test", schedule = "weekly", max_lag_days = 30, date_col = "Date",
       date_col_kind = "date", date_semantics = "observation", value_checks = vc)
}
aud <- function(e) {
  r <- suppressWarnings(cache_freshness_audit(telegram_alert = FALSE, caches_override = list(e),
                                              today = as.Date("2026-09-20"), persist = FALSE))
  rr <- if (!is.null(r$results)) r$results else r
  hit <- Filter(function(x) is.list(x) && identical(x$path, paste0(e$path, "::value")), rr)
  if (length(hit)) hit[[1]] else NULL
}
e_pos <- aud(ent(rel_ok))
chk("E4_audit_positive_value_pass", !is.null(e_pos) && identical(e_pos$status, "VALUE_PASS"),
    sprintf("status=%s", e_pos$status %||% "없음"))
e_inj <- aud(ent(rel_bad))
chk("E5_audit_injection_value_fail", !is.null(e_inj) && identical(e_inj$status, "VALUE_FAIL") &&
      grepl("fill_rate", e_inj$note %||% "") && grepl("Size", e_inj$note %||% ""),
    sprintf("status=%s note=%s", e_inj$status %||% "없음", substr(e_inj$note %||% "", 1, 90)))
e_mut <- aud(ent(rel_bad, with_axis = FALSE))
chk("E6_mutant_axis_removed_passes", !is.null(e_mut) && identical(e_mut$status, "VALUE_PASS"),
    "축을 제거하면 100% 결측도 VALUE_PASS — 이 축이 유일한 검출기다(돌연변이 통제)")

#──────────────────────────────────────────────────────────────────────────────
# F 배출 게이트 (순수 판독)
#──────────────────────────────────────────────────────────────────────────────
EG <- new.env(parent = globalenv())
sys.source(file.path(PROJ, "02_Infrastructure/factor_db/emission_report_gate.R"), envir = EG)
ymc <- format(Sys.Date(), "%Y%m")
fdir <- file.path(FXDIR, "fdb"); dir.create(fdir, showWarnings = FALSE)
write_json(list(ym = ymc, class_R_regression = list("V01_BM"), verdict = "WARN"),
           file.path(fdir, sprintf("emission_report_%s.json", ymc)), auto_unbox = TRUE)
g1 <- EG$emission_gate_read(file.path(fdir, sprintf("emission_report_%s.json", ymc)))
chk("F1_class_R_1_regress", identical(g1$status, "REGRESS") && g1$n == 1L && identical(g1$names, "V01_BM"),
    sprintf("status=%s n=%s", g1$status, g1$n))
write_json(list(ym = "000000", class_R_regression = list(), verdict = "OK"),
           file.path(fdir, "emission_report_000000.json"), auto_unbox = TRUE)
g2 <- EG$emission_gate_read(file.path(fdir, "emission_report_000000.json"))
chk("F2_class_R_0_ok", identical(g2$status, "OK"), sprintf("status=%s", g2$status))
g3 <- EG$emission_gate_read(file.path(fdir, "emission_report_999999.json"))
chk("F3_absent_unmeasured", identical(g3$status, "UNMEASURED"), "보고서 부재 = 미측정(OK 로 접지 않는다)")

#──────────────────────────────────────────────────────────────────────────────
# G 배선 — daily_refresh.sh 의 **실제 블록**을 잘라 bash 로 실행
#──────────────────────────────────────────────────────────────────────────────
DR <- readLines(file.path(PROJ, "02_Infrastructure/data/daily_refresh.sh"), encoding = "UTF-8", warn = FALSE)
DR <- sub("\r$", "", DR)
cut_block <- function(start_pat, end_pat) {
  i <- grep(start_pat, DR); j <- grep(end_pat, DR)
  if (length(i) != 1L || !length(j)) return(NULL)
  j <- j[j > i][1]; if (is.na(j)) return(NULL)
  DR[i:(j - 1L)]
}
blk_sz <- cut_block("^# ── \\[1z\\]", '^echo "\\[2/7\\]')
blk_eg <- cut_block("^# ── \\[6a-gate\\]", '^echo "\\[6b/7\\]')
i1 <- grep('^echo "\\[1/7\\]', DR); i2 <- grep('^echo "\\[2/7\\]', DR); iz <- grep("^# ── \\[1z\\]", DR)
i6 <- grep('^echo "\\[6a/7\\]', DR); i6b <- grep('^echo "\\[6b/7\\]', DR); ig <- grep("^# ── \\[6a-gate\\]", DR)
chk("G0_blocks_in_place", !is.null(blk_sz) && !is.null(blk_eg) && length(iz) == 1L && iz > i1 && iz < i2 &&
      length(ig) == 1L && ig > i6 && ig < i6b, "[1z] = [1] 과 [2] 사이 · [6a-gate] = [6a] 와 [6b] 사이")
RSCRIPT <- file.path(R.home("bin"), "Rscript.exe"); if (!file.exists(RSCRIPT)) RSCRIPT <- file.path(R.home("bin"), "Rscript")
# ★Git bash 우선 — PATH 의 bash 가 WSL 이면 Windows 경로를 못 읽는다(미측정을 실패로 오판)
BASH <- ""
for (.b in c("C:/Program Files/Git/bin/bash.exe", "C:/Program Files/Git/usr/bin/bash.exe", Sys.which("bash")))
  if (nzchar(.b) && file.exists(.b)) { BASH <- .b; break }
# 격리 루트: 레지스트리 사본 + 패널/보고서 픽스처
FR <- file.path(FXDIR, "root"); dir.create(file.path(FR, ".cache", "factor_db"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(FR, "02_Infrastructure/data"), recursive = TRUE, showWarnings = FALSE)
invisible(file.copy(file.path(PROJ, "02_Infrastructure/data/cache_registry.json"),
                    file.path(FR, "02_Infrastructure/data/cache_registry.json")))
run_blocks <- function(blk, panel, report_classR) {
  write_parquet(panel, file.path(FR, ".cache", "RAWDATA.parquet"))
  write_json(list(ym = ymc, class_R_regression = as.list(report_classR), verdict = "WARN"),
             file.path(FR, ".cache", "factor_db", sprintf("emission_report_%s.json", ymc)), auto_unbox = TRUE)
  sh <- file.path(FXDIR, "harness.sh")
  # ★~/.Renviron 이 QM_ROOT 를 운영 루트로 **덮어쓴다**(R 기동 규약) — 그대로 두면 이 하네스가
  #   격리 루트가 아니라 운영 RAWDATA·보고서를 읽어 '양성 대조' 가 운영 상태를 빌린다.
  #   빈 사용자 Renviron 으로 격리한다(운영 배선은 QM_ROOT="$BASE" = 같은 운영 루트라 무관).
  renv <- file.path(FXDIR, "empty.Renviron"); writeLines("# isolated", renv)
  writeLines(c("set -u", "DR_FAILED=()", sprintf('export R_ENVIRON_USER="%s"', renv),
               sprintf('BASE="%s"', FR),
               sprintf('INFRA="%s"', file.path(PROJ, "02_Infrastructure")),
               sprintf('RSCRIPT="%s"', RSCRIPT), blk,
               'printf "DRF:%s\\n" "${DR_FAILED[@]:-}"'), sh, useBytes = TRUE)
  out <- suppressWarnings(system2(BASH, sh, stdout = TRUE, stderr = TRUE))
  sub("^DRF:", "", grep("^DRF:", out, value = TRUE))
}
if (!nzchar(BASH)) { bad("G_bash_available", "bash 부재 — 배선 실행 검사 미측정") } else {
  okpanel <- mkpanel(); badpanel <- p_bad
  gz1 <- run_blocks(c(blk_sz, blk_eg), okpanel, character(0))
  chk("G1_positive_no_failures", !any(nzchar(gz1)), sprintf("DR_FAILED={%s}", paste(gz1, collapse = " ")))
  gz2 <- run_blocks(c(blk_sz, blk_eg), badpanel, c("V01_BM"))
  chk("G2_injection_both_loaded", "rawdata_size_na" %in% gz2 && any(grepl("^factor_emission_regress:[0-9]{6}:1\\(V01_BM\\)$", gz2)),
      sprintf("DR_FAILED={%s}", paste(gz2, collapse = " ")))
  mut_sz <- blk_sz[!grepl('DR_FAILED\\+=\\("rawdata_size_na"\\)', blk_sz)]
  # W-05: 적재 문자열에 판독 달이 들어갔다(factor_emission_regress:<ym>:N(top))
  mut_eg <- blk_eg[!grepl('DR_FAILED\\+=\\("factor_emission_regress:\\$_eg_ym:\\$\\{', blk_eg)]
  gz3 <- run_blocks(c(mut_sz, mut_eg), badpanel, c("V01_BM"))
  chk("G3_mutant_wiring_removed_goes_silent", !("rawdata_size_na" %in% gz3) && !any(grepl("^factor_emission_regress:[0-9]{6}:1", gz3)) &&
        length(mut_sz) < length(blk_sz) && length(mut_eg) < length(blk_eg),
      "적재 줄을 지우면 같은 주입이 침묵 — G2 가 배선 자체를 잰다는 증거")
}

#──────────────────────────────────────────────────────────────────────────────
# H 원인 귀속 — 스냅샷 실패 시 '장중 스냅샷 의심' 이 아니라 '스냅샷 부재 — 수집 실패' 를 찍는다
#──────────────────────────────────────────────────────────────────────────────
rp <- file.path(FXDIR, "raw_h.parquet")
write_parquet(data.table(Date = as.Date("2026-09-21"), Ticker = "A000001", Close = 1, Size = 1), rp)
SBX$RAWDATA_CACHE <- rp
SBX$last_confirmed_trading_day <- function() as.Date("2026-09-22")
SBX$is_trading_day <- function(d) TRUE
SBX$naver_collector_config <- function(...) CFG
SBX$naver_collect_size_snapshot <- function(cfg) stop("[naver_decode] fx: 응답 디코드 실패 — 모의")
SBX$naver_backfill_range <- function(...) list(report = list(size_source_counts = list(unavailable_no_matching_day = 10),
                                                               size_shares_obs_n = 0L))
h <- capture.output(tryCatch(F("naver_run_pipeline")(cfg = CFG), error = function(e) cat("ERR", conditionMessage(e), "\n")))
chk("H1_failure_attributed_to_snapshot_absence",
    any(grepl("스냅샷 부재 — 수집 실패", h, fixed = TRUE)) && !any(grepl("장중 스냅샷 의심", h, fixed = TRUE)),
    paste(grep("pipeline", h, value = TRUE), collapse = " | "))

fin()
