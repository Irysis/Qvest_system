#==============================================================================
# DART 단일판매·공급계약체결 document.xml 원문 파서 — FQ-002 계약수주 magnitude
#
# 2026-08-02 신설. insider(dart_insider_doc_parser.R) / pledge(dart_pledge_audit_acquire.py)
#   와 같은 document.xml 파이프이나 **서식이 다르다** — 재사용이 아니라 신규 파서다.
#   (게이트 실측: rcept 20260731800547/800210/800216 3건 클린 추출 확인 후 작성)
#
# 실측 서식 (2026-07 표본 3/3 동일):
#   "2. 계약내역  계약금액(원) 241,380,850,670  최근매출액(원) 8,054,627,xxx,xxx"
#   · 계약금액·최근매출액 **둘 다 '(원)' 단위 동일** — 분모 변환 불요
#   · 공시가 최근매출액을 동봉 → 시총 조인 없이 네이티브 분모 사용 가능
#   · 한화오션 주석 "각각 억원 미만에서 반올림" → 대형계약 정밀도 손실 플래그
#   · HD현대마린엔진 주석 "계약일의 최초고시환율 적용" → 외화계약 원화환산 플래그
#   · 신규/변경계약 **구조화 구분자 부재** — 자유텍스트 비고 파싱만 가능(표본 3중 1이 변경계약)
#
# ★설계 원칙 (이 저장소 반복 결함 회피):
#   추출 실패를 NA 로 조용히 흘리지 않는다. parse_status 에 명시 라벨을 싣고,
#   호출자가 "값이 없다"와 "안 재봤다"를 구분할 수 있게 한다.
#   (근거: 2026-08-02 "빈 결과 = 합격" 계통 11지점 수리 — git_dirty / lookahead clean=TRUE)
#
#------------------------------------------------------------------------------
# v3 (2026-08-03) — 구서식 커버 + 상태 라벨 분리. FQ-125 크롤(2019-01~2023-07) 선행조건.
#
# ★특정된 서식 차이 = **바이트 인코딩**이지 태그·라벨이 아니다 (표본 14건 바이트 실측):
#     2023-08+ 문서 : 본문 바이트가 **UTF-8** (meta 태그는 charset=euc-kr 로 *거짓* 선언)
#     2019-05 이전  : 본문 바이트가 **EUC-KR/CP949** (meta 선언과 일치)
#   구판은 `readLines(encoding="UTF-8")` 로 **선언도 탐지도 아닌 하드코딩** 을 썼다.
#   신형에선 우연히 맞아 동작했고, 구형에선 EUC-KR 바이트가 UTF-8 로 오태깅되어
#   `gsub`/`regexpr` 가 "input string is invalid" 로 **throw** → 드라이버 tryCatch 가
#   NULL 을 받아 `PARSER_ERROR`(parse_note 공란) 로 기록했다. 실측 634건이 전부 이것이다.
#   ★즉 구판의 성공은 **선언을 무시하고 하드코딩한 값이 우연히 맞은 것**이었다.
#     선언(meta charset)을 믿었어도 신형에서 틀렸다 — 그래서 v3 는 **바이트를 검사**한다.
#
#   라벨 어휘는 두 시대가 동일하다(디코딩만 하면 구판 정규식이 그대로 맞는다):
#     · 거래소공시 표준형 : "계약금액(원) N  최근매출액(원) N  매출액대비(%) N"
#     · 자율공시형        : "확정 계약금액 N … 계약금액 총액(원) N  최근 매출액(원) N"
#     · 2017 변종        : "계약금액 (원)" / "최근 매출액 (원)" — 괄호 앞 공백.
#                          v2 정규식의 ` ?` 가 이미 커버한다(신규 분기 불요).
#   → **기존 추출 경로(라벨 정규식·필드 산출)는 무변경**. v3 가 바꾼 것은 (a) 바이트→텍스트
#     디코딩, (b) 상태 라벨 분리, (c) 원문 캐시, (d) 무결성 교차검사 뿐이다.
#
# ★상태 라벨 분리 (구판은 전부 UNZIP_FAIL 로 뭉개 성공률을 왜곡했다):
#     NO_SOURCE_CORRECTION : 기재정정 공시인데 DART 가 원문 없음(014) — **정상 동작**.
#                            2019 이전 정정본은 원문이 아예 제공되지 않는다(구조적).
#     NO_SOURCE_014        : 비정정인데 014 (드묾 — 조사 대상)
#     RATE_LIMIT_020       : DART 일한도. ★구판은 이것도 UNZIP_FAIL 로 기록하고
#                            체크포인트를 **정상 기록**했다 = "한도 소진"이 "원문 없음"으로
#                            영구 동결되는 자리(이 저장소 "빈 결과 = 합격" 계통과 동형).
#     DART_ERROR_<code>    : 그 외 DART 상태코드(100/800/900…)
#     DECODE_FAIL          : UTF-8·CP949 어느 쪽으로도 본문 앵커("계약")가 안 나옴
#     UNZIP_FAIL           : 위 어느 것도 아닌데 zip 이 깨짐 (이제 진짜 손상만 남는다)
#
# ★무결성 교차검사 (ratio_check): 공시는 `매출액대비(%)` 를 **동봉**한다.
#   amt/rev 로 재계산한 값과 대조하면 금액 필드 훼손이 조용히 통과하지 못한다.
#   parse_status 는 건드리지 않는다(회귀 위험 0) — 별도 필드로만 노출한다.
#==============================================================================

suppressPackageStartupMessages({ library(httr) })

CTR_PARSER_VERSION <- "v3"

# 태그 제거 + 공백 정규화
.ctr_plain <- function(x) gsub("\\s+", " ", gsub("<[^>]+>", " ", x))

# "241,380,850,670" → 241380850670 (numeric). 실패 시 NA_real_.
.ctr_num <- function(s) {
  if (is.null(s) || is.na(s) || !nzchar(s)) return(NA_real_)
  suppressWarnings(as.numeric(gsub("[^0-9.]", "", s)))
}

# 라벨 뒤 첫 숫자열 추출. 라벨 자체가 없으면 NA + 사유는 호출자가 판단.
.ctr_after <- function(txt, label) {
  m <- regexpr(paste0(label, "\\s*([0-9][0-9,]*)"), txt, perl = TRUE)
  if (m < 0) return(NA_character_)
  seg <- regmatches(txt, m)
  sub(paste0("^", label, "\\s*"), "", seg)
}

# 소수 허용판 (매출액대비(%) 처럼 "3.31" 형태). 정수판과 분리한 이유: 금액 필드에
# 소수를 허용하면 "1,623,647,591" 뒤에 오는 무관한 소수를 삼킬 여지가 생긴다.
.ctr_after_dec <- function(txt, label) {
  m <- regexpr(paste0(label, "\\s*([0-9][0-9,]*(?:[.][0-9]+)?)"), txt, perl = TRUE)
  if (m < 0) return(NA_character_)
  seg <- regmatches(txt, m)
  sub(paste0("^", label, "\\s*"), "", seg)
}

# 본문 앵커 "계약" — **바이트로 못박는다**. 소스 리터럴로 두면 source(encoding=) 와
# 로케일 조합에 따라 native 로 재인코딩될 수 있어, 인코딩 판별기 자신이 인코딩에
# 의존하는 순환이 된다(이 저장소 "검사가 결함과 같은 좌표계" 계통).
.CTR_ANCHOR <- local({ s <- rawToChar(as.raw(c(0xEA,0xB3,0x84,0xEC,0x95,0xBD)))
                       Encoding(s) <- "UTF-8"; s })

#' 원문 바이트 → UTF-8 텍스트 (인코딩 **탐지**, 선언·하드코딩 불신)
#' @return list(text, encoding ∈ {UTF-8, CP949, CP949_LOSSY}, ok, note)
.ctr_decode <- function(rawb) {
  rawb <- rawb[rawb != as.raw(0L)]              # rawToChar 는 embedded NUL 에서 죽는다
  if (!length(rawb)) return(list(text = "", encoding = "NONE", ok = FALSE, note = "empty body"))
  s_raw <- rawToChar(rawb)

  has_anchor <- function(s) isTRUE(grepl(.CTR_ANCHOR, s, fixed = TRUE, useBytes = FALSE))

  # ① UTF-8 로 유효한가 (바이트 검사 — 선언이 아니라)
  if (isTRUE(validUTF8(s_raw))) {
    s1 <- s_raw; Encoding(s1) <- "UTF-8"
    if (has_anchor(s1)) return(list(text = s1, encoding = "UTF-8", ok = TRUE, note = ""))
  }
  # ② CP949(EUC-KR 상위집합) 엄격 변환
  s2 <- suppressWarnings(iconv(s_raw, from = "CP949", to = "UTF-8"))
  if (!is.na(s2) && has_anchor(s2)) return(list(text = s2, encoding = "CP949", ok = TRUE, note = ""))
  # ③ CP949 손실 허용 (일부 바이트 파손) — 라벨이 살아 있으면 쓰되 라벨을 남긴다
  s3 <- suppressWarnings(iconv(s_raw, from = "CP949", to = "UTF-8", sub = "?"))
  if (!is.na(s3) && has_anchor(s3))
    return(list(text = s3, encoding = "CP949_LOSSY", ok = TRUE, note = "lossy CP949 decode"))
  # ④ ASCII-only 등 앵커가 없는 유효 UTF-8 — "못 읽었다"와 "값이 없다"를 섞지 않는다
  list(text = "", encoding = "UNKNOWN", ok = FALSE,
       note = sprintf("no anchor in UTF-8/CP949 (%d bytes)", length(rawb)))
}

#' 응답 바디가 DART 상태 XML 인지 판정 (zip 이 아니라 에러 응답인 경우)
#' @return 상태코드 문자열("014"/"020"/…) 또는 NA_character_
.ctr_dart_status <- function(rawb) {
  if (!length(rawb) || length(rawb) > 4096L) return(NA_character_)   # 정상 zip 은 이보다 크다
  s <- suppressWarnings(rawToChar(rawb[rawb != as.raw(0L)]))
  if (!isTRUE(validUTF8(s))) s <- suppressWarnings(iconv(s, "CP949", "UTF-8", sub = "?"))
  if (is.na(s) || !nzchar(s)) return(NA_character_)
  m <- regexpr("<status>\\s*([0-9]{2,3})\\s*</status>", s, perl = TRUE)
  if (m < 0) return(NA_character_)
  gsub("[^0-9]", "", regmatches(s, m))
}

#' 정규화된 본문 텍스트 → 필드 (순수 함수 — I/O 없음, 테스트가 직접 부른다)
#' @param txt .ctr_plain 을 통과한 UTF-8 텍스트
parse_contract_text <- function(txt) {
  out <- list(contract_amount = NA_real_, recent_revenue = NA_real_, ratio_to_revenue = NA_real_,
              disclosed_ratio_pct = NA_real_, ratio_check = "UNAVAILABLE",
              is_amendment = NA, amendment_evidence = "",
              rounding_flag = FALSE, fx_flag = FALSE,
              parse_status = "NO_AMOUNT", parse_note = "")
  if (is.null(txt) || is.na(txt) || !nzchar(txt)) {
    out$parse_status <- "NO_AMOUNT"; out$parse_note <- "empty text"; return(out)
  }

  # ── v2 (2026-08-02, WT-D20260802_018 실측 진단): 자율공시 서식 커버 ──────────
  #  · 거래소공시 표준형: "계약금액(원) N ... 최근매출액(원) N"
  #  · 자율공시형(원본 실패 22.9%의 기전, rcept 20230830900288 실측):
  #      "확정 계약금액 N ... 계약금액 총액(원) N ... 최근 매출액(원) N"
  #      → 라벨 "계약금액 총액(원)" 우선, "최근 ?매출액(원)" 공백 허용.
  #  · 함정: "3. 계약상대방" 절에 상대방의 "-최근 매출액(원)"이 실린다 (동일 실측 문서
  #      에서 상대방 매출 40.68조가 발행사 매출 2,675억 뒤에 등장). 발행사 필드가 결측일
  #      때 lenient 매칭이 상대방 매출을 집으면 분모 오염 → 매출 추출은 계약상대방 절
  #      이전 텍스트로 한정한다.
  #  ★v3: 이 블록은 **무변경**이다. 구서식 실패의 원인은 라벨이 아니라 인코딩이었다.
  #
  #  ⚠ 알려진 결함(v3 에서 **고치지 않음** — 범위 밖, 별도 검증 필요):
  #    아래 절-경계 판정은 "계약상대방"의 **아무 출현**에서 자른다. 기재정정 공시는 본표
  #    **앞에** 정정 사유가 자유텍스트로 실리고 거기에 그 단어가 흔히 등장한다 —
  #      "3. 정정사유 계약상대방(태국 공군)과 합의하에 납기 9개월 연장"
  #    그러면 아직 오지도 않은 발행사 매출액이 통째로 잘려 `NO_REVENUE` 가 된다.
  #    36개월 회귀 검증이 실측 적발: **16건**(한국항공우주·한화오션·SK바이오사이언스·
  #    대웅·현대건설·삼성전자 등, 2023-11~2026-07). 예: 20231130800362 는 본표에
  #    최근매출액 2,825,136,012,824 가 멀쩡히 있는데 그 앞에서 절단된다.
  #    ★전부 is_correction=TRUE 라 build_contract_panel 의 신호 경로에는 들어가지 않는다
  #      (누출검증 A/B 용 보존분만 영향) — 그래서 FQ-125 크롤의 차단 사유가 아니다.
  #    ★수리 후보 = 절 머리표(`[0-9]\\s*\\.\\s*계약상대방`)로 좁히기. 시험 적용 시
  #      16건은 복구되나 **stored NO_REVENUE 81건 중 33건이 OK 로 뒤집혔다** — 그 33건이
  #      발행사 매출인지 상대방 매출(원래 막으려던 오염)인지 건별 확인 전에는 채택 불가.
  #      "고치니 더 많이 바뀐다"가 곧 개선의 증거는 아니다. 별도 태스크로 분리.
  txt_pre_cp <- { cp <- regexpr("계약상대방", txt, perl = TRUE)
                  if (cp > 0) substr(txt, 1, cp - 1) else txt }
  amt <- .ctr_num(.ctr_after(txt, "계약금액 ?총액 ?\\(원\\)"))
  if (is.na(amt)) amt <- .ctr_num(.ctr_after(txt, "계약금액 ?\\(원\\)"))
  rev <- .ctr_num(.ctr_after(txt_pre_cp, "최근 ?매출액 ?\\(원\\)"))
  out$contract_amount <- amt
  out$recent_revenue  <- rev
  if (!is.na(amt) && !is.na(rev) && rev > 0) out$ratio_to_revenue <- amt / rev

  # 신규 vs 변경계약 — 구조화 필드가 없어 자유텍스트 단서만 (실측 확인)
  amd_pat <- "변경계약|계약금액 변경|기존 계약|최초 계약"
  hit <- regexpr(amd_pat, txt, perl = TRUE)
  out$is_amendment <- hit > 0
  if (hit > 0) out$amendment_evidence <- substr(.ctr_plain(substr(txt, max(1, hit - 40), hit + 120)), 1, 160)

  out$rounding_flag <- grepl("억원 미만에서 반올림|백만원 미만", txt)
  out$fx_flag       <- grepl("환율|USD|외화", txt)

  # ── v3 무결성 교차검사 ──────────────────────────────────────────────────────
  # 공시가 동봉한 `매출액대비(%)` 와 amt/rev 재계산치를 대조한다. 금액 필드가 훼손되면
  # 여기서 **불일치가 드러난다** — 훼손이 그럴듯한 숫자로 조용히 통과하는 경로를 막는 축.
  # ★parse_status 는 절대 건드리지 않는다: 36개월 기존 산출과의 회귀 위험을 0 으로 둔다.
  disc <- .ctr_num(.ctr_after_dec(txt_pre_cp, "매출액 ?대비 ?\\(%\\)"))
  out$disclosed_ratio_pct <- disc
  if (!is.na(disc) && !is.na(out$ratio_to_revenue)) {
    comp <- out$ratio_to_revenue * 100
    # 허용오차: 공시 반올림(1~2 자리) + 비고의 "억원 미만 반올림" 을 흡수하는 폭.
    # 실측 14문서 최대 편차 0.036%p → 0.05 절대 + 0.5% 비례.
    tol <- 0.05 + 0.005 * abs(disc)
    out$ratio_check <- if (abs(comp - disc) <= tol) "OK" else "MISMATCH"
    if (identical(out$ratio_check, "MISMATCH"))
      out$parse_note <- sprintf("ratio_mismatch computed=%.4f disclosed=%.4f", comp, disc)
  }

  out$parse_status <- if (is.na(amt)) "NO_AMOUNT" else if (is.na(rev)) "NO_REVENUE" else "OK"
  out
}

#' 원문 응답 바이트 → 파싱 결과 (순수 — 네트워크 없음)
#' @param rawb          document.xml 응답 바디 원본 바이트 (zip 또는 DART 상태 XML)
#' @param is_correction 기재정정 여부(원장 메타). NA 면 014 를 NO_SOURCE_014 로 라벨.
parse_contract_bytes <- function(rawb, is_correction = NA) {
  out <- list(contract_amount = NA_real_, recent_revenue = NA_real_, ratio_to_revenue = NA_real_,
              disclosed_ratio_pct = NA_real_, ratio_check = "UNAVAILABLE",
              is_amendment = NA, amendment_evidence = "",
              rounding_flag = FALSE, fx_flag = FALSE,
              doc_encoding = NA_character_, parser_version = CTR_PARSER_VERSION,
              parse_status = "UNZIP_FAIL", parse_note = "")

  # ① DART 상태 XML 먼저 — unzip 실패로 뭉개면 "한도 소진"과 "원문 없음"이 같은 라벨이 된다
  st <- .ctr_dart_status(rawb)
  if (!is.na(st)) {
    out$parse_status <- if (identical(st, "014")) {
                          if (isTRUE(is_correction)) "NO_SOURCE_CORRECTION" else "NO_SOURCE_014"
                        } else if (identical(st, "020")) "RATE_LIMIT_020"
                        else sprintf("DART_ERROR_%s", st)
    out$parse_note <- sprintf("dart status %s (%d bytes)", st, length(rawb))
    return(out)
  }

  # ② 실제 zip 해제
  tf <- tempfile(fileext = ".zip"); ex <- tempfile()
  # 최상위 on.exit 은 미발화(금칙 ②)이나 여기는 **함수 프레임**이라 정상 발화한다.
  on.exit({ unlink(tf, force = TRUE); unlink(ex, recursive = TRUE, force = TRUE) }, add = TRUE)
  dir.create(ex, showWarnings = FALSE)
  writeBin(rawb, tf)
  ok <- tryCatch({ unzip(tf, exdir = ex); TRUE }, error = function(e) FALSE, warning = function(w) FALSE)
  if (!ok) { out$parse_status <- "UNZIP_FAIL"
             out$parse_note <- sprintf("unzip fail (%d bytes)", length(rawb)); return(out) }
  fs <- list.files(ex, full.names = TRUE, recursive = TRUE)
  if (!length(fs)) { out$parse_status <- "UNZIP_FAIL"; out$parse_note <- "empty archive"; return(out) }

  docb <- readBin(fs[1], "raw", n = file.info(fs[1])$size)
  dec <- .ctr_decode(docb)
  out$doc_encoding <- dec$encoding
  if (!dec$ok) { out$parse_status <- "DECODE_FAIL"; out$parse_note <- dec$note; return(out) }

  fld <- parse_contract_text(.ctr_plain(dec$text))
  for (k in names(fld)) out[[k]] <- fld[[k]]
  if (nzchar(dec$note))
    out$parse_note <- paste(c(dec$note, out$parse_note)[nzchar(c(dec$note, out$parse_note))], collapse = "; ")
  out
}

#' 계약 공시 1건 파싱
#' @param rcept_no      접수번호
#' @param api_key       DART key
#' @param is_correction 기재정정 여부(원장 메타). 014 응답의 라벨 분기에만 쓴다.
#' @param cache_dir     원문 응답 캐시 디렉토리. 지정 시 <rcept_no>.bin 재사용 →
#'                      재파싱이 API 호출 0 이 된다(회귀 검증·재처리 비용의 핵심).
#' @return list(rcept_no, contract_amount, recent_revenue, ratio_to_revenue,
#'              disclosed_ratio_pct, ratio_check, is_amendment, amendment_evidence,
#'              rounding_flag, fx_flag, doc_encoding, parser_version,
#'              parse_status, parse_note, from_cache)
#'   parse_status ∈ {OK, NO_AMOUNT, NO_REVENUE, DECODE_FAIL, UNZIP_FAIL,
#'                   NO_SOURCE_CORRECTION, NO_SOURCE_014, RATE_LIMIT_020,
#'                   DART_ERROR_<code>, FETCH_FAIL, http_fail_<code>}
#'   ★NA 값이 있으면 parse_status 가 반드시 OK 가 아니다 — 호출자는 status 로 판정할 것.
parse_contract_doc <- function(rcept_no, api_key, is_correction = NA, cache_dir = NULL) {
  cf <- if (!is.null(cache_dir) && nzchar(cache_dir))
          file.path(cache_dir, paste0(as.character(rcept_no), ".bin")) else NA_character_
  if (!is.na(cf) && file.exists(cf) && file.info(cf)$size > 0) {
    rawb <- readBin(cf, "raw", n = file.info(cf)$size)
    res <- parse_contract_bytes(rawb, is_correction = is_correction)
    return(c(list(rcept_no = rcept_no), res, list(from_cache = TRUE)))
  }

  tf <- tempfile(fileext = ".zip")
  on.exit(unlink(tf, force = TRUE), add = TRUE)
  r <- tryCatch(GET("https://opendart.fss.or.kr/api/document.xml",
                    query = list(crtfc_key = api_key, rcept_no = rcept_no),
                    write_disk(tf, overwrite = TRUE), timeout(60)),
                error = function(e) NULL)
  if (is.null(r)) {
    res <- parse_contract_bytes(raw(0), is_correction = is_correction)
    res$parse_status <- "FETCH_FAIL"; res$parse_note <- "GET error"
    return(c(list(rcept_no = rcept_no), res, list(from_cache = FALSE)))
  }
  sc <- status_code(r)
  if (sc != 200) {
    res <- parse_contract_bytes(raw(0), is_correction = is_correction)
    res$parse_status <- sprintf("http_fail_%d", sc)
    res$parse_note   <- sprintf("http_fail_%d", sc)
    return(c(list(rcept_no = rcept_no), res, list(from_cache = FALSE)))
  }

  sz <- file.info(tf)$size
  rawb <- if (is.na(sz) || sz <= 0) raw(0) else readBin(tf, "raw", n = sz)
  if (!is.na(cf) && length(rawb)) {
    dir.create(dirname(cf), recursive = TRUE, showWarnings = FALSE)
    tryCatch(writeBin(rawb, cf), error = function(e) invisible(NULL))
  }
  res <- parse_contract_bytes(rawb, is_correction = is_correction)
  c(list(rcept_no = rcept_no), res, list(from_cache = FALSE))
}

cat("[dart_contract_doc_parser] Loaded (", CTR_PARSER_VERSION,
    ") — parse_contract_doc(rcept_no, api_key, is_correction, cache_dir)\n", sep = "")
