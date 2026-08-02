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
#==============================================================================

suppressPackageStartupMessages({ library(httr) })

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

#' 계약 공시 1건 파싱
#' @param rcept_no 접수번호
#' @param api_key  DART key
#' @return list(rcept_no, contract_amount, recent_revenue, ratio_to_revenue,
#'              is_amendment, amendment_evidence, rounding_flag, fx_flag,
#'              parse_status, parse_note)
#'   parse_status ∈ {OK, NO_AMOUNT, NO_REVENUE, FETCH_FAIL, UNZIP_FAIL, http_fail_<code>}
#'   ★NA 값이 있으면 parse_status 가 반드시 OK 가 아니다 — 호출자는 status 로 판정할 것.
parse_contract_doc <- function(rcept_no, api_key) {
  out <- list(rcept_no = rcept_no, contract_amount = NA_real_, recent_revenue = NA_real_,
              ratio_to_revenue = NA_real_, is_amendment = NA, amendment_evidence = "",
              rounding_flag = FALSE, fx_flag = FALSE,
              parse_status = "FETCH_FAIL", parse_note = "")

  tf <- tempfile(fileext = ".zip"); ex <- tempfile()
  # 최상위 on.exit 은 미발화(금칙 ②)이나 여기는 **함수 프레임**이라 정상 발화한다.
  on.exit({ unlink(tf, force = TRUE); unlink(ex, recursive = TRUE, force = TRUE) }, add = TRUE)
  dir.create(ex, showWarnings = FALSE)

  r <- tryCatch(GET("https://opendart.fss.or.kr/api/document.xml",
                    query = list(crtfc_key = api_key, rcept_no = rcept_no),
                    write_disk(tf, overwrite = TRUE), timeout(60)),
                error = function(e) NULL)
  if (is.null(r)) { out$parse_note <- "GET error"; return(out) }
  sc <- status_code(r)
  if (sc != 200) { out$parse_status <- sprintf("http_fail_%d", sc)
                   out$parse_note <- sprintf("http_fail_%d", sc); return(out) }

  ok <- tryCatch({ unzip(tf, exdir = ex); TRUE },
                 error = function(e) FALSE, warning = function(w) FALSE)
  if (!ok) { out$parse_status <- "UNZIP_FAIL"
             out$parse_note <- sprintf("unzip fail (%s bytes)", file.info(tf)$size); return(out) }
  fs <- list.files(ex, full.names = TRUE, recursive = TRUE)
  if (!length(fs)) { out$parse_status <- "UNZIP_FAIL"; out$parse_note <- "empty archive"; return(out) }

  raw <- tryCatch(paste(readLines(fs[1], warn = FALSE, encoding = "UTF-8"), collapse = "\n"),
                  error = function(e) "")
  txt <- .ctr_plain(raw)

  amt <- .ctr_num(.ctr_after(txt, "계약금액\\(원\\)"))
  rev <- .ctr_num(.ctr_after(txt, "최근매출액\\(원\\)"))
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

  out$parse_status <- if (is.na(amt)) "NO_AMOUNT" else if (is.na(rev)) "NO_REVENUE" else "OK"
  out
}

cat("[dart_contract_doc_parser] Loaded — parse_contract_doc(rcept_no, api_key)\n")
