#==============================================================================
# DART Insider Disclosure — document.xml Parser (Production Module)
#
# 목적: elestock.json 이 역사(≈최근2년 cap) 데이터에서 rows=0 을 반환하는 블로커를
#   우회하여, DART 공시 원문(document.xml)을 직접 파싱해 2005~ 인사이더 거래를 추출.
#
# 진입 함수:
#   parse_insider_doc(rcept_no, KEY)  ->  data.table
#     columns: rcept_no, corp_name, corp_code, reporter_name,
#              reporter_class {임원|주요주주|임원겸주요주주|불명},
#              is_officer(logical), is_major_holder(logical),
#              officer_title, major_holder_type, relation,
#              변동일(Date), report_reason, security_type,
#              qty_before, qty_change(signed numeric), qty_after, price,
#              note, filing_date, parse_status, parse_note
#
# 설계 요점 (실측 리버스엔지니어링 기반, 2026-07-05):
#   1. document.xml = ZIP(application/x-msdownload). unzip → <rcept_no>.xml.
#   2. 인코딩: XML 선언부 encoding="..." 은 신뢰불가(2010/2007 파일이 utf-8 선언인데
#      실제 EUC-KR). => 양쪽 readLines() 시도 후 한글이 살아있고 내용이 긴 쪽 채택.
#   3. 데이터 셀 = <TU>/<TE> 태그(DART 추출태그) + <TD>/<TH>. 4종 전부 파싱.
#   4. 헤더에 &cr; 개행엔티티 삽입 => 키워드검색 전 gsub("&cr;","").
#   5. 거래상세 표: 헤더에 '보고사유'+'변동일' 키워드로 앵커(표 인덱스는 연도별 가변).
#   6. 증감 방향: 구포맷(2005-2010)은 증감이 부호없는 절대값 + 보고사유 '(+)/(-)' 로 방향.
#      신포맷(2024)은 증감 자체가 signed. => 보고사유 부호 우선, 없으면 증감 부호 사용.
#   7. 보고자 구분: '발행회사와의 관계' 행의 임원(등기여부) / 주요주주 필드로 officer vs
#      major-holder 분리 (Cohen-Malloy-Pomorski 2012 신호품질 관건).
#
# fail-soft: 파싱 불가 필링은 NULL 아닌 1행(또는 0행) data.table + parse_note.
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(httr)
})

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0 || (length(a) == 1 && is.na(a))) b else a
# Hangul syllable range via unicode escapes (locale/encoding-independent — a raw
# "[가-힣]" literal in source can compile to a broken byte range under non-UTF-8 locales)
.HANGUL <- "[가-힣]"

#------------------------------------------------------------------------------
# .dart_fetch_doc: fetch document.xml (ZIP) and return path to extracted .xml
#------------------------------------------------------------------------------
.dart_fetch_doc <- function(rcept_no, KEY, tmpdir = tempdir()) {
  url <- "https://opendart.fss.or.kr/api/document.xml"
  d <- tryCatch(GET(url, query = list(crtfc_key = KEY, rcept_no = rcept_no)),
                error = function(e) NULL)
  if (is.null(d) || status_code(d) != 200) {
    return(list(ok = FALSE, note = paste0("http_fail_", if (is.null(d)) "NULL" else status_code(d))))
  }
  ctype <- headers(d)[["content-type"]] %||% ""
  raw <- content(d, "raw")
  # DART returns JSON error (not ZIP) when rcept_no invalid / no doc
  if (length(raw) < 100 || grepl("application/json", ctype, ignore.case = TRUE)) {
    msg <- tryCatch(rawToChar(raw), error = function(e) "")
    return(list(ok = FALSE, note = paste0("no_zip:", substr(msg, 1, 80))))
  }
  z <- file.path(tmpdir, paste0("dart_", rcept_no, ".zip"))
  writeBin(raw, z)
  exdir <- file.path(tmpdir, paste0("dart_ex_", rcept_no))
  files <- tryCatch(unzip(z, exdir = exdir), error = function(e) NULL)
  if (is.null(files) || length(files) == 0) {
    return(list(ok = FALSE, note = "unzip_fail"))
  }
  xf <- files[grepl("\\.xml$", files, ignore.case = TRUE)]
  # main filing = the xml named after rcept_no (fallback: largest xml)
  main <- xf[grepl(rcept_no, xf, fixed = TRUE)]
  if (length(main) == 0) {
    if (length(xf) == 0) return(list(ok = FALSE, note = "no_xml_in_zip"))
    sizes <- file.info(xf)$size
    main <- xf[which.max(sizes)]
  } else {
    main <- main[1]
  }
  list(ok = TRUE, xml = main, zip = z, exdir = exdir)
}

#------------------------------------------------------------------------------
# .dart_read_xml: encoding-robust read. Try EUC-KR + UTF-8, pick hangul-valid.
#------------------------------------------------------------------------------
.dart_read_xml <- function(xf) {
  rd <- function(enc) tryCatch({
    x <- paste(readLines(file(xf, encoding = enc), warn = FALSE), collapse = "\n")
    Encoding(x) <- "UTF-8"
    x
  }, error = function(e) "")
  t_euc <- rd("EUC-KR")
  t_utf <- rd("UTF-8")
  h_euc <- grepl(.HANGUL, t_euc)
  h_utf <- grepl(.HANGUL, t_utf)
  # Prefer the encoding that yields hangul; among those, prefer longer content.
  if (h_euc && !h_utf) return(list(txt = t_euc, enc = "EUC-KR"))
  if (h_utf && !h_euc) return(list(txt = t_utf, enc = "UTF-8"))
  if (h_euc && h_utf) {
    if (nchar(t_euc) >= nchar(t_utf)) return(list(txt = t_euc, enc = "EUC-KR"))
    return(list(txt = t_utf, enc = "UTF-8"))
  }
  # neither has hangul — return the longer (best effort)
  if (nchar(t_euc) >= nchar(t_utf)) return(list(txt = t_euc, enc = "EUC-KR?"))
  list(txt = t_utf, enc = "UTF-8?")
}

#------------------------------------------------------------------------------
# helpers: table / row / cell extraction
#------------------------------------------------------------------------------
.strip_cell <- function(x) {
  x <- gsub("&cr;", "", x, fixed = TRUE)
  x <- gsub("<[^>]+>", " ", x)          # strip inner tags
  x <- gsub("&#[0-9]+;", " ", x)        # numeric entities
  x <- gsub("&[a-zA-Z]+;", " ", x)      # named entities
  x <- gsub("[\r\n\t]+", " ", x)
  x <- gsub("\\s+", " ", x)
  trimws(x)
}

.extract_tables <- function(txt) {
  regmatches(txt, gregexpr("<TABLE.*?</TABLE>", txt, ignore.case = TRUE))[[1]]
}
.extract_rows <- function(tb) {
  regmatches(tb, gregexpr("<TR.*?</TR>", tb, ignore.case = TRUE))[[1]]
}
.extract_cells <- function(row) {
  # TD / TH / TU / TE  (DART data values live in TU / TE)
  cells <- regmatches(row, gregexpr("<T[DHUE][ >].*?</T[DHUE]>", row, ignore.case = TRUE))[[1]]
  vapply(cells, .strip_cell, character(1), USE.NAMES = FALSE)
}

# numeric parse: strip commas / spaces / non [-0-9.]; return signed numeric
.num <- function(x) {
  if (is.null(x) || length(x) == 0) return(NA_real_)
  x <- gsub("[^0-9.-]", "", x)              # dash last in class = literal, no range op
  x <- gsub("(?<=.)-", "", x, perl = TRUE)  # keep only a leading minus
  suppressWarnings(as.numeric(x))
}

#------------------------------------------------------------------------------
# .parse_reporter: officer vs major-holder classification (TABLE ~5)
#------------------------------------------------------------------------------
.parse_reporter <- function(tables) {
  out <- list(reporter_name = NA_character_, officer_title = NA_character_,
              major_holder_type = NA_character_, relation = NA_character_,
              is_officer = FALSE, is_major_holder = FALSE)
  # find the table containing '발행회사와의 관계'
  rel_tbl <- NULL
  for (tb in tables) {
    if (grepl("발행회사와의\\s*관계", tb)) { rel_tbl <- tb; break }
  }
  if (is.null(rel_tbl)) return(out)

  rows <- .extract_rows(rel_tbl)
  for (r in rows) {
    cells <- .extract_cells(r)
    cells <- cells[nzchar(cells)]
    if (length(cells) == 0) next
    # reporter name: row with '성명(명칭)' or '한 글'/'한글'
    if (any(grepl("성명|명칭", cells)) && is.na(out$reporter_name)) {
      # value after '한 글'/'한글' token, else last non-label cell
      hi <- which(grepl("한\\s*글", cells))
      if (length(hi) && hi[1] < length(cells)) {
        out$reporter_name <- cells[hi[1] + 1]
      } else {
        cand <- cells[!grepl("성명|명칭|한\\s*글|한자|영문", cells)]
        if (length(cand)) out$reporter_name <- cand[1]
      }
    }
    # 발행회사와의 관계 row: 임원(등기여부)/임원(직위) + 직위명
    if (any(grepl("발행회사와의\\s*관계", cells))) {
      # locate 임원 label then its value
      oi <- which(grepl("임원", cells))
      if (length(oi) && oi[1] < length(cells)) {
        val <- cells[oi[1] + 1]
        if (nzchar(val) && val != "-") { out$is_officer <- TRUE; }
      }
      ti <- which(grepl("직위명", cells))
      if (length(ti) && ti[1] < length(cells)) {
        tv <- cells[ti[1] + 1]
        if (nzchar(tv) && tv != "-") out$officer_title <- tv
      }
    }
    # 주요주주 row
    if (any(grepl("주요주주", cells)) && !any(grepl("발행회사", cells))) {
      mi <- which(grepl("주요주주", cells))
      if (length(mi) && mi[1] < length(cells)) {
        mv <- cells[mi[1] + 1]
        if (nzchar(mv) && mv != "-") { out$is_major_holder <- TRUE; out$major_holder_type <- mv }
      }
    }
  }
  # officer_title present but is_officer not flagged (2024 has 등기임원 value) -> keep as is
  # If officer title exists, ensure officer flag
  if (!is.na(out$officer_title)) out$is_officer <- TRUE
  out
}

#------------------------------------------------------------------------------
# .parse_corp: company name / code (TABLE ~4)  회사명 / 회사코드
#------------------------------------------------------------------------------
.parse_corp <- function(tables) {
  out <- list(corp_name = NA_character_, corp_code = NA_character_)
  for (tb in tables) {
    if (!grepl("회\\s*사\\s*명", tb)) next
    rows <- .extract_rows(tb)
    for (r in rows) {
      cells <- .extract_cells(r); cells <- cells[nzchar(cells)]
      if (length(cells) == 0) next
      ci <- which(grepl("회\\s*사\\s*명", cells))
      if (length(ci) && ci[1] < length(cells) && is.na(out$corp_name)) {
        out$corp_name <- cells[ci[1] + 1]
      }
      cc <- which(grepl("회사코드", cells))
      if (length(cc) && cc[1] < length(cells) && is.na(out$corp_code)) {
        v <- gsub("[^0-9A-Za-z]", "", cells[cc[1] + 1])
        if (nzchar(v)) out$corp_code <- v
      }
    }
    if (!is.na(out$corp_name)) break
  }
  out
}

#------------------------------------------------------------------------------
# .parse_date_kr: '2010년 06월 24일' / '2024.01.25' -> Date
#------------------------------------------------------------------------------
.parse_date_kr <- function(x) {
  if (is.na(x) || !nzchar(x)) return(as.Date(NA))
  x <- trimws(x)
  # yyyy년 mm월 dd일
  m <- regmatches(x, regexec("([0-9]{4})\\s*년\\s*([0-9]{1,2})\\s*월\\s*([0-9]{1,2})\\s*일", x))[[1]]
  if (length(m) == 4) return(as.Date(sprintf("%s-%02d-%02d", m[2], as.integer(m[3]), as.integer(m[4]))))
  # yyyy.mm.dd or yyyy-mm-dd or yyyy/mm/dd  (dash placed last in class to avoid range op)
  m2 <- regmatches(x, regexec("([0-9]{4})[./-]\\s*([0-9]{1,2})[./-]\\s*([0-9]{1,2})", x))[[1]]
  if (length(m2) == 4) return(as.Date(sprintf("%s-%02d-%02d", m2[2], as.integer(m2[3]), as.integer(m2[4]))))
  as.Date(NA)
}

#------------------------------------------------------------------------------
# .parse_trades: the 거래상세 table (anchor: header has 보고사유 + 변동일)
#------------------------------------------------------------------------------
.parse_trades <- function(tables) {
  trade_tbl <- NULL
  for (tb in tables) {
    clean <- gsub("&cr;", "", tb, fixed = TRUE)
    if (grepl("보고사유", clean) && grepl("변동일", clean)) { trade_tbl <- clean; break }
  }
  if (is.null(trade_tbl)) {
    return(list(rows = data.table(), note = "no_trade_table"))
  }
  rows <- .extract_rows(trade_tbl)
  parsed <- list()
  for (r in rows) {
    cells <- .extract_cells(r)
    cells <- cells[nzchar(cells)]
    if (length(cells) == 0) next
    joined <- paste(cells, collapse = " ")
    # skip header rows / total rows
    if (grepl("보고사유", joined) || grepl("변동전|증감|변동후|소\\s*유\\s*주\\s*식", joined) && !grepl("매수|매도|취득|처분|증여|상속|신규|전환|행사|무상|배정|출자", joined)) next
    if (grepl("^합\\s*계", cells[1]) || grepl("합\\s*계", cells[1])) next

    # first cell = 보고사유 ; must look like a reason (매수/매도/신규/...)
    reason <- cells[1]
    if (!grepl("매수|매도|취득|처분|증여|상속|신규|전환|행사|무상|배정|출자|합병|장내|장외|기타|수증|증권|주식", reason)) {
      # some old formats put 변동일 in different position; try to locate a date cell
      if (!any(vapply(cells, function(c) !is.na(.parse_date_kr(c)), logical(1)))) next
    }

    # locate date cell (first cell parseable as date)
    dt_idx <- which(vapply(cells, function(c) !is.na(.parse_date_kr(c)), logical(1)))[1]
    if (is.na(dt_idx)) next
    trade_date <- .parse_date_kr(cells[dt_idx])

    # After date: 종류, 변동전, 증감, 변동후, 단가, 비고 (positional)
    tail_cells <- cells[(dt_idx + 1):length(cells)]
    security_type <- if (length(tail_cells) >= 1) tail_cells[1] else NA_character_

    # numeric cells among remaining (변동전 / 증감 / 변동후 / 단가)
    remain <- if (length(tail_cells) >= 2) tail_cells[2:length(tail_cells)] else character(0)
    nums <- suppressWarnings(vapply(remain, .num, numeric(1), USE.NAMES = FALSE))
    # keep positions; qty_before, qty_change, qty_after, price are first 4 numerics
    num_vals <- nums[!is.na(nums)]
    qty_before <- if (length(num_vals) >= 1) num_vals[1] else NA_real_
    qty_change <- if (length(num_vals) >= 2) num_vals[2] else NA_real_
    qty_after  <- if (length(num_vals) >= 3) num_vals[3] else NA_real_
    price      <- if (length(num_vals) >= 4) num_vals[4] else NA_real_

    # note = last non-numeric cell (비고), if distinct
    note_cell <- NA_character_
    nonnum_tail <- remain[is.na(suppressWarnings(vapply(remain, .num, numeric(1), USE.NAMES = FALSE)))]
    if (length(nonnum_tail)) note_cell <- tail(nonnum_tail, 1)

    # SIGN: 보고사유 (+)/(-) authoritative; else keep 증감's own sign
    sign_from_reason <- NA_integer_
    if (grepl("\\(\\+\\)", reason) || grepl("매수|취득|신규|증여|수증|무상|배정|행사|전환", reason)) sign_from_reason <- 1L
    if (grepl("\\(\\-\\)|\\(－\\)", reason) || grepl("매도|처분", reason)) sign_from_reason <- -1L
    signed_change <- qty_change
    if (!is.na(qty_change)) {
      if (!is.na(sign_from_reason)) {
        signed_change <- abs(qty_change) * sign_from_reason
      }
      # else: leave qty_change as-is (already signed in new format)
    }

    parsed[[length(parsed) + 1L]] <- data.table(
      report_reason = reason,
      `변동일` = trade_date,
      security_type = security_type,
      qty_before = qty_before,
      qty_change = signed_change,
      qty_after = qty_after,
      price = price,
      note = note_cell
    )
  }
  if (length(parsed) == 0) return(list(rows = data.table(), note = "trade_table_no_rows"))
  list(rows = rbindlist(parsed, fill = TRUE), note = "ok")
}

#------------------------------------------------------------------------------
# parse_insider_doc: MAIN entry point
#------------------------------------------------------------------------------
parse_insider_doc <- function(rcept_no, KEY, tmpdir = tempdir(), keep_files = FALSE) {
  rcept_no <- as.character(rcept_no)
  empty_row <- function(status, note, corp_name = NA_character_, corp_code = NA_character_) {
    data.table(
      rcept_no = rcept_no, corp_name = corp_name, corp_code = corp_code,
      reporter_name = NA_character_, reporter_class = NA_character_,
      is_officer = NA, is_major_holder = NA,
      officer_title = NA_character_, major_holder_type = NA_character_, relation = NA_character_,
      `변동일` = as.Date(NA), report_reason = NA_character_, security_type = NA_character_,
      qty_before = NA_real_, qty_change = NA_real_, qty_after = NA_real_, price = NA_real_,
      note = NA_character_, filing_date = NA_character_,
      parse_status = status, parse_note = note
    )
  }

  fetched <- .dart_fetch_doc(rcept_no, KEY, tmpdir = tmpdir)
  if (!isTRUE(fetched$ok)) {
    return(empty_row("FETCH_FAIL", fetched$note))
  }
  on.exit({
    if (!keep_files) {
      try(unlink(fetched$zip), silent = TRUE)
      try(unlink(fetched$exdir, recursive = TRUE), silent = TRUE)
    }
  }, add = TRUE)

  rd <- .dart_read_xml(fetched$xml)
  txt <- gsub("&cr;", "", rd$txt, fixed = TRUE)
  if (!grepl(.HANGUL, txt) || !grepl("<TABLE", txt, ignore.case = TRUE)) {
    return(empty_row("READ_FAIL", paste0("no_hangul_or_table_enc=", rd$enc)))
  }

  tables <- .extract_tables(txt)
  if (length(tables) == 0) return(empty_row("PARSE_FAIL", "no_tables"))

  corp <- .parse_corp(tables)
  reporter <- .parse_reporter(tables)
  trades <- .parse_trades(tables)

  # reporter_class
  rc <- if (isTRUE(reporter$is_officer) && isTRUE(reporter$is_major_holder)) "임원겸주요주주"
        else if (isTRUE(reporter$is_officer)) "임원"
        else if (isTRUE(reporter$is_major_holder)) "주요주주"
        else "불명"

  if (nrow(trades$rows) == 0) {
    # valid filing but no trade detail (holdings-only) — return 1 metadata row, 0 trades
    r <- empty_row("NO_TRADES", trades$note, corp$corp_name, corp$corp_code)
    r[, `:=`(reporter_name = reporter$reporter_name, reporter_class = rc,
             is_officer = reporter$is_officer, is_major_holder = reporter$is_major_holder,
             officer_title = reporter$officer_title, major_holder_type = reporter$major_holder_type)]
    return(r)
  }

  out <- trades$rows
  out[, `:=`(
    rcept_no = rcept_no,
    corp_name = corp$corp_name,
    corp_code = corp$corp_code,
    reporter_name = reporter$reporter_name,
    reporter_class = rc,
    is_officer = reporter$is_officer,
    is_major_holder = reporter$is_major_holder,
    officer_title = reporter$officer_title,
    major_holder_type = reporter$major_holder_type,
    relation = NA_character_,
    filing_date = substr(rcept_no, 1, 8),
    parse_status = "OK",
    parse_note = paste0("enc=", rd$enc, ";ntbl=", length(tables))
  )]
  setcolorder(out, c("rcept_no","corp_name","corp_code","reporter_name","reporter_class",
                     "is_officer","is_major_holder","officer_title","major_holder_type","relation",
                     "변동일","report_reason","security_type","qty_before","qty_change","qty_after",
                     "price","note","filing_date","parse_status","parse_note"))
  out[]
}

cat("[dart_insider_doc_parser] Loaded. entry: parse_insider_doc(rcept_no, KEY)\n")
