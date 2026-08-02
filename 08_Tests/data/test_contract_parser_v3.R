#!/usr/bin/env Rscript
#==============================================================================
# test_contract_parser_v3.R — DART 계약공시 파서 v3 위반 주입 테스트 (FQ-002 / FQ-125)
#
# 2026-08-03 신설. v3 는 구서식(2019-05 이전) 커버를 위해 **바이트→텍스트 디코딩**을
#   교체했다. 그 수리가 진짜로 살아 있는지, 그리고 기존(2023-08+) 경로가 안 깨졌는지를
#   합성 픽스처로 잰다 — **API 호출 0**.
#
# ★왜 이 검사기가 필요한가 (실측 근거):
#   구판은 `readLines(encoding="UTF-8")` 로 인코딩을 **하드코딩**했다. 신형 문서가
#   우연히 UTF-8 이라 동작했고, 구형(EUC-KR) 에서는 regex 가 throw → 드라이버가
#   `PARSER_ERROR`(parse_note 공란) 로 삼켰다. 실측 634건. 즉 **"성공"이 우연이었다**.
#   같은 부류의 재발을 막으려면 "구형이 파싱된다"만으로는 부족하다 —
#   **CP949 분기를 죽였을 때 실제로 빨개지는지**(돌연변이 축)까지 봐야 한다.
#   그러지 않으면 UTF-8 분기 하나로도 모든 축이 초록일 수 있다(축 공허화).
#
# ★두 번째 축 계열 = 금액 훼손 검거. 공시는 `매출액대비(%)` 를 동봉하므로 amt/rev 를
#   재계산해 대조할 수 있다. 구판엔 이 대조가 없어 오값이 조용히 `OK` 로 기록됐다
#   (실측 20230809800003: `계약금액(원)` 뒤 첫 숫자가 "2. 계약내역"의 2 → amt=2, status OK).
#   T2x 계열이 훼손을 주입하고, T2x-mut 이 대조를 껐을 때 통과로 뒤집히는지 확인한다.
#
# 실행: Rscript 08_Tests/data/test_contract_parser_v3.R
# 마지막 줄 = 요약 JSON (러너가 이 줄만 읽는다 — 없으면 UNREPORTED=1 fail)
#==============================================================================
# ── 루트 해석: 테스트 러너는 self-first (r-portability ④-b) ────────────────────
.tp_root <- function() {
  self <- ""
  ca <- commandArgs(trailingOnly = FALSE)
  fa <- grep("^--file=", ca, value = TRUE)
  if (length(fa)) self <- normalizePath(file.path(dirname(sub("^--file=", "", fa[1])), "..", ".."),
                                        winslash = "/", mustWork = FALSE)
  # ★앵커 순서 정본 = 이 줄. self 최우선, env 는 그 뒤 (worktree 에서 main 을 재는 사고 방지)
  cands <- c(self, Sys.getenv("CLAUDE_PROJECT_DIR", unset = ""), Sys.getenv("QM_ROOT", unset = ""), getwd())
  cands <- gsub("\\\\", "/", cands[nzchar(cands)])       # 정규화를 검사보다 먼저
  marker <- "02_Infrastructure/data/dart_contract_doc_parser.R"
  hit <- cands[file.exists(file.path(cands, marker))]
  if (!length(hit)) stop("project root 미발견 (marker 없음)")
  if (nzchar(self) && !identical(hit[1], self))
    cat(sprintf("⚠ ANCHOR OVERRIDE: 검사기 위치='%s' 이나 대상='%s'\n", self, hit[1]))
  hit[1]
}
ROOT <- .tp_root()
source(file.path(ROOT, "02_Infrastructure/data/dart_contract_doc_parser.R"), encoding = "UTF-8")

PASS <- 0L; FAIL <- 0L; SKIP <- 0L; FAILED <- character(0); SKIPS <- list()
ok <- function(axis, cond, detail = "") {
  if (isTRUE(cond)) { PASS <<- PASS + 1L; cat(sprintf("  ✅ %s\n", axis)) }
  else { FAIL <<- FAIL + 1L; FAILED <<- c(FAILED, axis)
         cat(sprintf("  ❌ %s %s\n", axis, detail)) }
}
skip <- function(axis, reason, missing = "") {
  SKIP <<- SKIP + 1L
  SKIPS[[length(SKIPS) + 1L]] <- list(axis = axis, reason = reason, missing = missing)
  cat(sprintf("  ⏭ %s — %s (%s)\n", axis, reason, missing))
}

#──────────────────────────────────────────────────────────────────────────────
# 픽스처: 실측 문서 구조 그대로의 최소 HTML (2026-08-03 실크롤 표본에서 발췌·축약)
#──────────────────────────────────────────────────────────────────────────────
HEAD <- '<html><head><meta content="text/html; charset=euc-kr" http-equiv="Content-Type"></head><body>'
TAIL <- '</body></html>'

# 거래소공시 표준형 (2018-06 삼성중공업 실측 서식). amt/rev/pct 를 인자로 받는다.
fx_standard <- function(amt = "266,100,000,000", rev = "7,901,200,000,000", pct = "3.4") {
  paste0(HEAD, '<table><tr><td>1. 판매ㆍ공급계약 구분</td><td>공사수주</td></tr>',
         '<tr><td>2. 계약내역</td><td>계약금액(원)</td><td>', amt, '</td>',
         '<td>최근매출액(원)</td><td>', rev, '</td>',
         '<td>매출액대비(%)</td><td>', pct, '</td></tr>',
         '<tr><td>3. 계약상대</td><td>유럽지역 선주</td></tr>',
         '<tr><td>5. 계약기간</td><td>2018-06-28</td></tr></table>', TAIL)
}
# 자율공시형 (2023-08 테크윈 실측). 계약상대방 절에 **상대방 매출액**이 실리는 함정 포함.
fx_autonomous <- function(amt = "8,852,690,840", rev = "267,491,091,324", pct = "3.31",
                          cp_rev = "40,680,531,000,000") {
  paste0(HEAD, '<table><tr><td>2. 계약내역</td><td>조건부 계약여부</td><td>미해당</td></tr>',
         '<tr><td>확정 계약금액</td><td>', amt, '</td>',
         '<td>계약금액 총액(원)</td><td>', amt, '</td>',
         '<td>최근 매출액(원)</td><td>', rev, '</td>',
         '<td>매출액 대비(%)</td><td>', pct, '</td></tr>',
         '<tr><td>3. 계약상대방</td><td>Micron</td>',
         '<td>-최근 매출액(원)</td><td>', cp_rev, '</td></tr></table>', TAIL)
}
# 2017 변종: 괄호 앞 공백 "계약금액 (원)"
fx_2017 <- function(amt = "1,623,647,591", rev = "141,979,321,639", pct = "1.14") {
  paste0(HEAD, '<table><tr><td>2. 계약내역</td><td>계약금액 (원)</td><td>', amt, '</td>',
         '<td>최근 매출액 (원)</td><td>', rev, '</td>',
         '<td>매출액 대비 (%)</td><td>', pct, '</td></tr></table>', TAIL)
}

as_utf8  <- function(s) { Encoding(s) <- "UTF-8"; charToRaw(enc2utf8(s)) }
as_cp949 <- function(s) {
  r <- iconv(enc2utf8(s), from = "UTF-8", to = "CP949", toRaw = TRUE)[[1]]
  if (is.null(r)) {   # 자기진단: 어느 글자가 CP949 에 없는지 지목한다(무언의 halt 금지)
    bad <- Filter(function(ch) is.null(iconv(ch, "UTF-8", "CP949", toRaw = TRUE)[[1]]),
                  strsplit(enc2utf8(s), "")[[1]])
    stop(sprintf("픽스처에 CP949 미대응 문자: %s", paste(unique(bad), collapse = " ")))
  }
  r
}

#──────────────────────────────────────────────────────────────────────────────
# 최소 ZIP(store) 빌더 — 실 파이프(parse_contract_bytes)를 관통시키기 위함.
#   utils::zip() 은 외부 바이너리 의존이라 환경에 따라 조용히 없다. 그러면 통합 축이
#   skip 으로 사라지고 "핵심 경로 무검사"가 초록에 숨는다 — 그래서 직접 만든다.
#──────────────────────────────────────────────────────────────────────────────
.CRC_TBL <- local({
  tb <- integer(256); POLY <- -306674912L   # 0xEDB88320 의 32bit signed 표현
  for (n in 0:255) { c <- n
    for (k in 1:8) c <- if (bitwAnd(c, 1L) == 1L) bitwXor(POLY, bitwShiftR(c, 1)) else bitwShiftR(c, 1)
    tb[n + 1L] <- c }
  tb
})
.crc32 <- function(rb) {
  c <- -1L
  for (b in as.integer(rb)) c <- bitwXor(.CRC_TBL[bitwAnd(bitwXor(c, b), 255L) + 1L], bitwShiftR(c, 8))
  bitwXor(c, -1L)
}
.u16 <- function(x) { x <- as.integer(x); as.raw(c(bitwAnd(x, 255L), bitwAnd(bitwShiftR(x, 8), 255L))) }
.u32 <- function(x) { x <- as.integer(x); as.raw(c(bitwAnd(x, 255L), bitwAnd(bitwShiftR(x, 8), 255L),
                                                  bitwAnd(bitwShiftR(x, 16), 255L), bitwAnd(bitwShiftR(x, 24), 255L))) }
make_zip <- function(docbytes, fname = "doc.xml") {
  fn <- charToRaw(fname); crc <- .crc32(docbytes); n <- length(docbytes)
  lfh <- c(.u32(0x04034b50), .u16(20), .u16(0), .u16(0), .u16(0), .u16(0x21),
           .u32(crc), .u32(n), .u32(n), .u16(length(fn)), .u16(0), fn)
  cd  <- c(.u32(0x02014b50), .u16(20), .u16(20), .u16(0), .u16(0), .u16(0), .u16(0x21),
           .u32(crc), .u32(n), .u32(n), .u16(length(fn)), .u16(0), .u16(0),
           .u16(0), .u16(0), .u32(0), .u32(0), fn)
  body <- c(lfh, docbytes)
  c(body, cd, .u32(0x06054b50), .u16(0), .u16(0), .u16(1), .u16(1),
    .u32(length(cd)), .u32(length(body)), .u16(0))
}
dart_err <- function(code, msg = "test") as_utf8(sprintf(
  '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><result><status>%s</status><message>%s</message></result>',
  code, msg))

cat("=== test_contract_parser_v3 ===\n\n[A] 서식·인코딩 커버리지\n")

#──────────────────────────────────────────────────────────────────────────────
# A. 두 시대 × 세 서식 = 6 축. 같은 논리 문서가 인코딩과 무관하게 같은 값을 내야 한다.
#    이것이 v3 수리의 본체다(라벨이 아니라 인코딩이 원인이었다).
#──────────────────────────────────────────────────────────────────────────────
EXP <- list(standard   = list(f = fx_standard,   amt = 266100000000, rev = 7901200000000),
            autonomous = list(f = fx_autonomous, amt = 8852690840,   rev = 267491091324),
            v2017      = list(f = fx_2017,       amt = 1623647591,   rev = 141979321639))
for (nm in names(EXP)) {
  e <- EXP[[nm]]
  for (enc in c("UTF-8", "CP949")) {
    rb <- if (enc == "UTF-8") as_utf8(e$f()) else as_cp949(e$f())
    r  <- parse_contract_bytes(make_zip(rb))
    ok(sprintf("A_%s_%s", nm, enc),
       identical(r$parse_status, "OK") && isTRUE(r$contract_amount == e$amt) &&
         isTRUE(r$recent_revenue == e$rev) && identical(r$doc_encoding, enc),
       sprintf("(status=%s amt=%s rev=%s enc=%s)", r$parse_status, r$contract_amount,
               r$recent_revenue, r$doc_encoding))
  }
}
# A7: 상대방 매출 오염 함정 — 자율공시형 분모는 발행사 매출이어야 한다
r <- parse_contract_bytes(make_zip(as_cp949(fx_autonomous())))
ok("A7_counterparty_revenue_not_used",
   isTRUE(r$recent_revenue == 267491091324) && !isTRUE(r$recent_revenue == 40680531000000),
   sprintf("(rev=%s)", r$recent_revenue))

#──────────────────────────────────────────────────────────────────────────────
# B. 돌연변이 — CP949 분기를 죽이면 구서식 축이 실제로 뒤집히는가.
#    안 뒤집히면 A_*_CP949 는 UTF-8 분기가 대신 통과시킨 **공허한 초록**이다.
#──────────────────────────────────────────────────────────────────────────────
cat("\n[B] 돌연변이(검출력 실증)\n")
mut_decode_utf8_only <- function(rawb) {           # 구판과 동형: 인코딩 하드코딩
  s <- rawToChar(rawb[rawb != as.raw(0L)]); Encoding(s) <- "UTF-8"
  tryCatch({ t <- .ctr_plain(s); parse_contract_text(t) }, error = function(e) list(parse_status = "THROW"))
}
mb <- mut_decode_utf8_only(as_cp949(fx_standard()))
ok("B1_mutation_utf8_hardcode_breaks_cp949",
   !identical(mb$parse_status, "OK"),
   sprintf("(구판 경로가 CP949 를 통과시켰다 — status=%s. A_*_CP949 축이 공허하다)", mb$parse_status))
mu <- mut_decode_utf8_only(as_utf8(fx_standard()))
ok("B2_mutation_control_utf8_still_ok", identical(mu$parse_status, "OK"),
   sprintf("(양성 통제 실패: 돌연변이 경로가 UTF-8 도 못 읽음 → B1 이 무의미 — status=%s)", mu$parse_status))

#──────────────────────────────────────────────────────────────────────────────
# C. 위반 주입 — 금액 필드 훼손. 파서가 오값을 조용히 OK 로 반환하면 안 된다.
#──────────────────────────────────────────────────────────────────────────────
cat("\n[C] 위반 주입: 금액 훼손\n")
inj <- list(
  C1_amount_x10   = fx_standard(amt = "2,661,000,000,000"),           # 10배 부풀림
  C2_amount_div10 = fx_standard(amt = "26,610,000,000"),              # 1/10 축소
  C3_amount_tiny  = fx_standard(amt = "2"),                           # 실사고 형태(amt=2)
  C4_rev_swapped  = fx_standard(rev = "790,120,000,000"),             # 분모 훼손
  C5_auto_x100    = fx_autonomous(amt = "885,269,084,000"))
for (nm in names(inj)) {
  r <- parse_contract_bytes(make_zip(as_cp949(inj[[nm]])))
  ok(nm, identical(r$ratio_check, "MISMATCH"),
     sprintf("(훼손이 조용히 통과 — ratio_check=%s amt=%s note='%s')",
             r$ratio_check, r$contract_amount, r$parse_note))
}
# C6 음성 통제: 무손상 문서는 MISMATCH 를 내면 안 된다 (상시-MISMATCH 면 C1~C5 가 공허)
for (nm in names(EXP)) {
  r <- parse_contract_bytes(make_zip(as_cp949(EXP[[nm]]$f())))
  ok(sprintf("C6_clean_%s_no_false_alarm", nm), identical(r$ratio_check, "OK"),
     sprintf("(무손상인데 ratio_check=%s)", r$ratio_check))
}
# C7 돌연변이: 대조를 끄면(구판 = 대조 없음) C3 가 OK 로 통과함을 실증 —
#    "구판은 이 훼손을 못 잡았다"가 주장이 아니라 실측이 된다.
r3 <- parse_contract_bytes(make_zip(as_cp949(fx_standard(amt = "2"))))
ok("C7_mutation_without_crosscheck_silently_ok",
   identical(r3$parse_status, "OK") && isTRUE(r3$contract_amount == 2),
   sprintf("(status=%s amt=%s — 구판 동형 경로가 오값을 OK 로 내지 않음)",
           r3$parse_status, r3$contract_amount))

#──────────────────────────────────────────────────────────────────────────────
# D. 라벨 결측 — "값이 없다"와 "안 재봤다"를 섞지 않는다
#──────────────────────────────────────────────────────────────────────────────
cat("\n[D] 라벨 결측 / 디코딩 실패\n")
no_amt <- paste0(HEAD, '<table><tr><td>2. 계약내역</td>',
                 '<td>최근매출액(원)</td><td>7,901,200,000,000</td></tr></table>', TAIL)
r <- parse_contract_bytes(make_zip(as_cp949(no_amt)))
ok("D1_missing_amount_label", identical(r$parse_status, "NO_AMOUNT") && is.na(r$contract_amount),
   sprintf("(status=%s)", r$parse_status))
no_rev <- paste0(HEAD, '<table><tr><td>2. 계약내역</td>',
                 '<td>계약금액(원)</td><td>266,100,000,000</td></tr></table>', TAIL)
r <- parse_contract_bytes(make_zip(as_cp949(no_rev)))
ok("D2_missing_revenue_label", identical(r$parse_status, "NO_REVENUE") && is.na(r$recent_revenue),
   sprintf("(status=%s)", r$parse_status))
# D3: 어느 인코딩으로도 앵커가 안 나오는 바이트 → DECODE_FAIL (NO_AMOUNT 로 내려앉히면
#     "읽지 못했다"가 "금액이 없다"로 위장된다 — 이 저장소 '빈 결과 = 합격' 계통)
garb <- as.raw(c(0xFF, 0xFE, 0x81, 0x40, 0xFF, 0xFF, 0xFE, 0xFE, 0xFF, 0xFF))
r <- parse_contract_bytes(make_zip(garb))
ok("D3_undecodable_is_DECODE_FAIL", identical(r$parse_status, "DECODE_FAIL"),
   sprintf("(status=%s — 미해독이 '금액 없음'으로 내려앉음)", r$parse_status))

#──────────────────────────────────────────────────────────────────────────────
# E. 상태 라벨 분리 — 정정 원문부재 / 한도소진 / 진짜 손상이 같은 라벨이면 안 된다
#──────────────────────────────────────────────────────────────────────────────
cat("\n[E] DART 상태 라벨 분리\n")
r <- parse_contract_bytes(dart_err("014"), is_correction = TRUE)
ok("E1_correction_014_labeled", identical(r$parse_status, "NO_SOURCE_CORRECTION"),
   sprintf("(status=%s)", r$parse_status))
r <- parse_contract_bytes(dart_err("014"), is_correction = FALSE)
ok("E2_noncorrection_014_distinct", identical(r$parse_status, "NO_SOURCE_014"),
   sprintf("(status=%s — 비정정 014 가 정정과 같은 라벨)", r$parse_status))
r <- parse_contract_bytes(dart_err("020", "조회한도를 초과"))
ok("E3_rate_limit_not_no_source", identical(r$parse_status, "RATE_LIMIT_020"),
   sprintf("(status=%s — 한도 소진이 '원문 없음'으로 영구 동결되는 자리)", r$parse_status))
r <- parse_contract_bytes(dart_err("800"))
ok("E4_other_dart_error_surfaced", identical(r$parse_status, "DART_ERROR_800"),
   sprintf("(status=%s)", r$parse_status))
# E5: 진짜 손상 zip → UNZIP_FAIL 이어야 하고 NO_SOURCE_* 로 오라벨되면 안 된다
bad <- as.raw(c(0x50, 0x4b, 0x03, 0x04, rep(0x00, 40)))
r <- parse_contract_bytes(bad)
ok("E5_corrupt_zip_still_UNZIP_FAIL", identical(r$parse_status, "UNZIP_FAIL"),
   sprintf("(status=%s)", r$parse_status))
# E6: 빈 바디 → OK 아님 (0바이트를 정상으로 읽지 않는다)
r <- parse_contract_bytes(raw(0))
ok("E6_empty_body_not_ok", !identical(r$parse_status, "OK"), sprintf("(status=%s)", r$parse_status))

#──────────────────────────────────────────────────────────────────────────────
# F. 캐시 경로 충실도 — 캐시에서 읽은 결과가 바이트 직접 파싱과 같아야 한다.
#    (회귀 검증 전체가 이 캐시 위에 서므로, 캐시가 다른 답을 내면 그 검증이 무의미해진다)
#──────────────────────────────────────────────────────────────────────────────
cat("\n[F] 캐시 경로\n")
tmpc <- file.path(tempdir(), paste0("ctr_cache_", as.integer(Sys.time())))
dir.create(tmpc, recursive = TRUE, showWarnings = FALSE)
zb <- make_zip(as_cp949(fx_standard()))
writeBin(zb, file.path(tmpc, "TESTRCEPT.bin"))
direct <- parse_contract_bytes(zb)
cached <- parse_contract_doc("TESTRCEPT", "NOKEY", cache_dir = tmpc)
ok("F1_cache_matches_direct",
   identical(cached$parse_status, direct$parse_status) &&
     isTRUE(cached$contract_amount == direct$contract_amount) &&
     isTRUE(cached$recent_revenue == direct$recent_revenue) && isTRUE(cached$from_cache),
   sprintf("(from_cache=%s status=%s)", cached$from_cache, cached$parse_status))
unlink(tmpc, recursive = TRUE, force = TRUE)

#──────────────────────────────────────────────────────────────────────────────
# G. 실문서 축 — .cache 의 실크롤 원문이 있을 때만. 없으면 **제3상태 skipped**.
#    (전제 부재를 fail 로 세면 오진단, pass 로 세면 '빈 결과 = 합격' 재발)
#──────────────────────────────────────────────────────────────────────────────
cat("\n[G] 실문서 회귀(캐시 전제)\n")
DOCDIR <- file.path(ROOT, ".cache/dart/contract_docs")
CKDIR  <- file.path(ROOT, ".cache/dart/contract_backfill")
real <- if (dir.exists(DOCDIR)) list.files(DOCDIR, pattern = "[.]bin$", full.names = TRUE) else character(0)
if (!length(real)) {
  skip("G1_real_docs_parse", "실크롤 원문 캐시 부재(gitignore 산출물)", DOCDIR)
  skip("G2_real_docs_encoding_split", "실크롤 원문 캐시 부재", DOCDIR)
} else {
  set.seed(20260803); sel <- real[sort(sample(seq_along(real), min(40L, length(real))))]
  st <- character(0); en <- character(0)
  for (f in sel) {
    rb <- readBin(f, "raw", n = file.info(f)$size)
    rr <- parse_contract_bytes(rb)
    st <- c(st, rr$parse_status); en <- c(en, if (is.na(rr$doc_encoding)) "NA" else rr$doc_encoding)
  }
  ok("G1_real_docs_parse", mean(st == "OK") >= 0.85,
     sprintf("(OK 비율 %.3f / %d건 — 분포: %s)", mean(st == "OK"), length(st),
             paste(names(table(st)), table(st), sep = "=", collapse = " ")))
  ok("G2_real_docs_encoding_split", all(en %in% c("UTF-8", "CP949", "CP949_LOSSY")),
     sprintf("(인코딩 분포: %s)", paste(names(table(en)), table(en), sep = "=", collapse = " ")))
}

#──────────────────────────────────────────────────────────────────────────────
cat(sprintf("\n=== %d pass / %d fail / %d skipped ===\n", PASS, FAIL, SKIP))
if (FAIL) cat("실패 축:", paste(FAILED, collapse = ", "), "\n")
esc <- function(s) gsub('"', '\\\\"', s)
skj <- if (length(SKIPS)) paste0(',"skips":[', paste(vapply(SKIPS, function(s)
  sprintf('{"axis":"%s","reason":"%s","missing":"%s"}', esc(s$ax