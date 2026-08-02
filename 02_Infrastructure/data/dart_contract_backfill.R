#!/usr/bin/env Rscript
#==============================================================================
# DART 계약수주 Backfill Driver — FQ-002 (계약수주 magnitude)
#   resumable · universe-bounded · daily-budget-aware
#
# 2026-08-02 신설. dart_insider_backfill.R 정본 패턴 복제 + 그 파일이 기록한 실사고 회피:
#   · pblntf_ty 오지정 → 0건 (insider 는 "E" 로 0건 받고서야 "D" 로 수리)
#     → 착수 전 실측으로 **"I"(거래소공시) 확정**. A/B/C/D/E/F/J 7종 전부 0건 확인.
#   · 단발 429/503 즉시 halt → partial 무한루프 (201912 정체)
#     → 백오프 재시도 2회, 진짜 일한도(020)만 halt.
#   · '020' 부분매칭 오탐 (공시 비고의 "2020년") → parse_status/parse_note 에서만 판정.
#
# 실측 규모 (2026-07 전수): 유니버스 348사 교집합 87건/월(체결·정정제외 40건/월).
#   전구간 2005-01~2026-07 259개월 → document.xml ≈22,533 호출(3.2일 @ 일 7,000).
#   파일럿(최근 36개월) ≈3,100 호출 → 반나절.
#
# Usage:
#   QM_ROOT=... [BF_START=2023-08 BF_END=2026-07 DART_DAILY_BUDGET=7000 DRY_RUN=1] \
#     Rscript 02_Infrastructure/data/dart_contract_backfill.R
#   DRY_RUN=1 → list.json 만 조회(document.xml 미호출). 예산 소모 최소로 배선 검증.
# 산출: .cache/dart/contract_backfill/<YYYYMM>.csv
#==============================================================================
suppressPackageStartupMessages({ library(httr); library(jsonlite); library(data.table) })

# 금칙 ④: CLAUDE_PROJECT_DIR 먼저. marker 로 정체성 검증(존재 검사로 대체 금지 — 금칙 ③).
.ctr_root <- function() {
  cands <- c(Sys.getenv("CLAUDE_PROJECT_DIR", unset = ""), Sys.getenv("QM_ROOT", unset = ""),
             "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
  cands <- cands[nzchar(cands)]
  marker <- "02_Infrastructure/hooks/qvest_hook_router.py"
  hit <- cands[file.exists(file.path(cands, marker))]
  if (!length(hit)) stop("project root 미발견 — CLAUDE_PROJECT_DIR 설정 필요")
  hit[1]
}
ROOT <- .ctr_root()

env <- readLines(file.path(ROOT, ".env"), warn = FALSE)
KEY <- sub("^DART_API_KEY=", "", env[grepl("^DART_API_KEY=", env)][1])
if (!nzchar(KEY)) stop("DART_API_KEY 미발견 (.env)")

CKDIR <- file.path(ROOT, ".cache/dart/contract_backfill")
dir.create(CKDIR, recursive = TRUE, showWarnings = FALSE)
# v3(2026-08-03): 원문 응답 캐시. 파서를 다시 고쳐야 할 때 재크롤이 아니라 재파싱으로
#   끝난다 — 08-02 에 구서식 실패 1,139건을 재fetch 해야 했던 비용의 재발 방지.
DOCDIR <- file.path(ROOT, ".cache/dart/contract_docs")
dir.create(DOCDIR, recursive = TRUE, showWarnings = FALSE)
UNI_CC <- unique(fread(file.path(ROOT, ".cache/dart/universe_corpcodes.csv"),
                       colClasses = "character")$corp_code)
source(file.path(ROOT, "02_Infrastructure/data/dart_contract_doc_parser.R"), encoding = "UTF-8")

DELAY        <- 0.75
DAILY_BUDGET <- as.integer(Sys.getenv("DART_DAILY_BUDGET", "7000"))
DRY_RUN      <- nzchar(Sys.getenv("DRY_RUN", ""))
START <- Sys.getenv("BF_START", "2023-08"); END <- Sys.getenv("BF_END", "2026-07")

calls <- 0L; halted <- FALSE
api_get <- function(url, q) {
  calls <<- calls + 1L
  r <- tryCatch(GET(url, query = q, timeout(60)), error = function(e) NULL)
  Sys.sleep(DELAY); r
}
parse_resp <- function(r) if (is.null(r)) NULL else
  tryCatch(fromJSON(content(r, "text", encoding = "UTF-8"), flatten = TRUE), error = function(e) NULL)

months <- format(seq(as.Date(paste0(START, "-01")), as.Date(paste0(END, "-01")), by = "month"), "%Y%m")
cat(sprintf("[ctr] universe=%d | months=%s..%s (%d) | budget=%d/run | DRY_RUN=%s\n",
            length(UNI_CC), START, END, length(months), DAILY_BUDGET, DRY_RUN))

for (ym in months) {
  ck <- file.path(CKDIR, paste0(ym, ".csv"))
  if (file.exists(ck)) next
  if (calls >= DAILY_BUDGET) { cat(sprintf("[ctr] budget reached before %s — resume next run\n", ym)); break }

  yr <- substr(ym, 1, 4); mo <- substr(ym, 5, 6)
  bgn <- paste0(ym, "01")
  last <- format(seq(as.Date(paste0(yr, "-", mo, "-01")), by = "month", length.out = 2)[2] - 1, "%d")
  end <- paste0(ym, last)

  page <- 1L; disc <- list(); list_ok <- TRUE
  repeat {
    pp <- parse_resp(api_get("https://opendart.fss.or.kr/api/list.json",
            list(crtfc_key = KEY, bgn_de = bgn, end_de = end,
                 pblntf_ty = "I", page_no = page, page_count = 100)))
    if (is.null(pp)) { list_ok <- FALSE; break }
    if (!is.null(pp$status) && pp$status == "020") {
      cat("[ctr] DART status 020 (일한도) — halt\n"); halted <- TRUE; break
    }
    # status 013 = 조회 데이터 없음(정상). 그 외 비-000 은 불완전으로 취급.
    if (!is.null(pp$status) && pp$status == "013") break
    if (is.null(pp$status) || pp$status != "000" || is.null(pp$list) || !length(pp$list)) {
      list_ok <- FALSE; break
    }
    disc[[length(disc) + 1L]] <- as.data.table(pp$list)
    tp <- if (!is.null(pp$total_page)) as.integer(pp$total_page) else page
    if (page >= tp) break
    page <- page + 1L
    if (calls >= DAILY_BUDGET) { list_ok <- FALSE; break }
  }
  if (halted) break
  # ★불완전한 목록으로 체크포인트를 쓰지 않는다 — "빈 결과 = 합격"의 재발 형태다.
  #  (2026-08-02 계통 수리: 미측정을 정상값으로 내려앉히면 다음 실행이 재시도하지 않는다)
  if (!list_ok) { cat(sprintf("[ctr] list incomplete for %s — 체크포인트 미기록(다음 실행 재시도)\n", ym)); break }

  # ★DRY_RUN 은 어떤 경로에서도 체크포인트를 쓰지 않는다.
  #  '공시 없음' 체크포인트를 dry run 이 남기면 이후 실제 실행이 그 달을 skip 한다 —
  #  검증용 실행이 수집 대상을 조용히 없애는 형태(이번 세션 "빈 결과 = 합격" 계통과 동형).
  .ck_write <- function(dt) if (!DRY_RUN) fwrite(dt, ck)

  if (!length(disc)) { .ck_write(data.table(ym = ym, note = "no_disclosures"))
                       cat(sprintf("[ctr] %s: 공시 0건\n", ym)); next }
  dd <- rbindlist(disc, fill = TRUE)
  # 신호 이벤트 = 최초 체결 공시. 기재정정은 사후 수정본이라 역사 패널에 넣으면 look-ahead.
  #   정정본은 누출검증용으로 별도 수집(is_correction 플래그로 표시, 기본 신호에서 제외).
  sel <- dd[grepl("단일판매", report_nm) & grepl("체결", report_nm) & corp_code %in% UNI_CC]
  if (!nrow(sel)) { .ck_write(data.table(ym = ym, note = "no_universe_contract"))
                    cat(sprintf("[ctr] %s: 0 universe contract (calls=%d)\n", ym, calls)); next }
  sel[, is_correction := grepl("기재정정", report_nm)]

  if (DRY_RUN) {
    cat(sprintf("[ctr] %s: %d건 (정정 %d) — DRY_RUN, document.xml 미호출 (calls=%d)\n",
                ym, nrow(sel), sum(sel$is_correction), calls))
    next
  }

  .is_rate  <- function(pr) !is.null(pr) && grepl("http_fail_(429|503)", pr$parse_note %||% "")
  rows <- list(); partial <- FALSE; fail_n <- 0L; nosrc_n <- 0L
  for (i in seq_len(nrow(sel))) {
    if (calls >= DAILY_BUDGET) { partial <- TRUE; break }
    calls <- calls + 1L
    # v3: is_correction 을 넘겨야 014 를 NO_SOURCE_CORRECTION 으로 라벨할 수 있고,
    #     cache_dir 로 원문을 보존해 재파싱이 API 호출 0 이 된다.
    pr <- tryCatch(parse_contract_doc(sel$rcept_no[i], KEY,
                                      is_correction = sel$is_correction[i], cache_dir = DOCDIR),
                   error = function(e) NULL)
    retry <- 0L
    while (.is_rate(pr) && retry < 2L && calls < DAILY_BUDGET) {
      retry <- retry + 1L; Sys.sleep(5 * retry); calls <- calls + 1L
      pr <- tryCatch(parse_contract_doc(sel$rcept_no[i], KEY,
                                        is_correction = sel$is_correction[i], cache_dir = DOCDIR),
                     error = function(e) NULL)
    }
    # ★일한도 소진을 데이터로 기록하지 않는다. 구판은 020 응답이 unzip 실패로 떨어져
    #   UNZIP_FAIL 행이 되고 그 달이 **정상 체크포인트**로 굳었다 — 한도가 '원문 없음'으로
    #   영구 동결되는 자리(이 저장소 "빈 결과 = 합격" 계통). 즉시 halt 하고 미기록.
    if (!is.null(pr) && identical(pr$parse_status, "RATE_LIMIT_020")) {
      cat(sprintf("[ctr] DART status 020 (일한도) at %s — halt, %s 미기록\n", sel$rcept_no[i], ym))
      halted <- TRUE; partial <- TRUE; break
    }
    if (is.null(pr)) { fail_n <- fail_n + 1L
      rows[[length(rows) + 1L]] <- data.table(ym = ym, rcept_no = sel$rcept_no[i],
        corp_code = sel$corp_code[i], corp_name = sel$corp_name[i], rcept_dt = sel$rcept_dt[i],
        report_nm = sel$report_nm[i], is_correction = sel$is_correction[i],
        contract_amount = NA_real_, recent_revenue = NA_real_, ratio_to_revenue = NA_real_,
        disclosed_ratio_pct = NA_real_, ratio_check = "UNAVAILABLE",
        is_amendment = NA, rounding_flag = NA, fx_flag = NA, doc_encoding = NA_character_,
        parser_version = CTR_PARSER_VERSION, parse_status = "PARSER_ERROR",
        parse_note = "parse_contract_doc threw (사유 미상 — 조사 대상)")
      next
    }
    # 원문 부재(정정공시)는 파싱 실패가 아니다 — 성공률 계산에서 분리한다.
    if (identical(pr$parse_status, "NO_SOURCE_CORRECTION")) nosrc_n <- nosrc_n + 1L
    else if (!identical(pr$parse_status, "OK")) fail_n <- fail_n + 1L
    rows[[length(rows) + 1L]] <- data.table(ym = ym, rcept_no = sel$rcept_no[i],
      corp_code = sel$corp_code[i], corp_name = sel$corp_name[i], rcept_dt = sel$rcept_dt[i],
      report_nm = sel$report_nm[i], is_correction = sel$is_correction[i],
      contract_amount = pr$contract_amount, recent_revenue = pr$recent_revenue,
      ratio_to_revenue = pr$ratio_to_revenue, disclosed_ratio_pct = pr$disclosed_ratio_pct,
      ratio_check = pr$ratio_check, is_amendment = pr$is_amendment,
      rounding_flag = pr$rounding_flag, fx_flag = pr$fx_flag,
      doc_encoding = pr$doc_encoding, parser_version = pr$parser_version,
      parse_status = pr$parse_status, parse_note = pr$parse_note)
  }
  R <- if (length(rows)) rbindlist(rows, fill = TRUE) else data.table()
  if (partial) {
    cat(sprintf("[ctr] %s partial (%d/%d, calls=%d) — 체크포인트 미기록\n",
                ym, nrow(R), nrow(sel), calls)); break
  }
  .ck_write(R)
  # 분모 = 원문이 실제로 제공된 건. 정정 원문부재를 실패로 세면 성공률이 왜곡된다.
  n_src <- nrow(R) - nosrc_n
  cat(sprintf("[ctr] %s: %d건 기록 (원문제공 %d 중 OK %d = %.1f%% / 실패 %d / 원문부재(정정) %d) calls=%d\n",
              ym, nrow(R), n_src, sum(R$parse_status == "OK", na.rm = TRUE),
              if (n_src > 0) 100 * sum(R$parse_status == "OK", na.rm = TRUE) / n_src else NA_real_,
              fail_n, nosrc_n, calls))
}
cat(sprintf("[ctr] done. calls=%d halted=%s\n", calls, halted))
