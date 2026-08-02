#!/usr/bin/env Rscript
#==============================================================================
# dart_contract_parser_regression.R — 파서 v3 회귀 검증 (FQ-002 / FQ-125 선행)
#
# 2026-08-03 신설. v3 는 구서식(EUC-KR 바이트) 커버를 위해 **바이트→텍스트 디코딩**을
#   교체했다. 신형(UTF-8) 경로가 그대로인지는 주장이 아니라 실측으로 증명해야 한다.
#
# 방법: 체크포인트 CSV 에 저장된 값이 곧 **v2 의 산출물**이다(2026-08-02 실크롤).
#   같은 rcept_no 의 원문을 다시 받아 v3 로 파싱하고 저장값과 전 필드 대조한다.
#   → "v3 로 재파싱해도 값이 안 변한다"의 직접 증거. 별도 v2 재구현이 필요 없다
#     (재구현 대조는 전사 오류가 끼어들 여지를 만든다).
#
# ★원문 캐시: 응답 바이트를 .cache/dart/contract_docs/<rcept_no>.bin 에 보존한다.
#   1회 지불 후 재실행은 **API 호출 0**. 앞으로의 재파싱·서식 조사도 무료가 된다.
#
# ★해석 주의: 저장값과 다르면 두 가능성이다 — (a) v3 회귀 (b) DART 원문 재발행.
#   그래서 불일치는 요약이 아니라 **행 단위로 CSV 에 남긴다**(집계로 뭉개면 진단 불가).
#
# Usage:
#   [REG_START=202308 REG_END=202607 DART_DAILY_BUDGET=7000 REG_CACHE_ONLY=1] \
#     Rscript 02_Infrastructure/data/dart_contract_parser_regression.R
#   REG_CACHE_ONLY=1 → 캐시에 있는 문서만 검증(네트워크 미사용).
# 산출: .cache/dart/contract_regression_<START>_<END>.csv (불일치 행) + stdout 요약
#==============================================================================
suppressPackageStartupMessages({ library(data.table) })

# 금칙 ④: CLAUDE_PROJECT_DIR 먼저 + marker 로 정체성 검증(금칙 ③ — 존재 검사 금지)
.rg_root <- function() {
  cands <- c(Sys.getenv("CLAUDE_PROJECT_DIR", unset = ""), Sys.getenv("QM_ROOT", unset = ""),
             "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
  cands <- cands[nzchar(cands)]
  cands <- gsub("\\\\", "/", cands)                 # 정규화를 검사보다 **먼저**
  marker <- "02_Infrastructure/hooks/qvest_hook_router.py"
  hit <- cands[file.exists(file.path(cands, marker))]
  if (!length(hit)) stop("project root 미발견 — CLAUDE_PROJECT_DIR 설정 필요")
  hit[1]
}
ROOT <- .rg_root()
source(file.path(ROOT, "02_Infrastructure/data/dart_contract_doc_parser.R"), encoding = "UTF-8")

CKDIR    <- file.path(ROOT, ".cache/dart/contract_backfill")
DOCDIR   <- file.path(ROOT, ".cache/dart/contract_docs")
dir.create(DOCDIR, recursive = TRUE, showWarnings = FALSE)
CACHE_ONLY <- nzchar(Sys.getenv("REG_CACHE_ONLY", ""))
BUDGET     <- as.integer(Sys.getenv("DART_DAILY_BUDGET", "7000"))
START      <- Sys.getenv("REG_START", "202308")
END        <- Sys.getenv("REG_END",   "202607")

KEY <- ""
if (!CACHE_ONLY) {
  env <- readLines(file.path(ROOT, ".env"), warn = FALSE)
  KEY <- sub("^DART_API_KEY=", "", env[grepl("^DART_API_KEY=", env)][1])
  if (!nzchar(KEY)) stop("DART_API_KEY 미발견 (.env)")
}

fs <- list.files(CKDIR, pattern = "^[0-9]{6}[.]csv$", full.names = TRUE)
fs <- fs[basename(fs) >= paste0(START, ".csv") & basename(fs) <= paste0(END, ".csv")]
if (!length(fs)) stop(sprintf("대상 체크포인트 0개 (%s..%s)", START, END))

D <- rbindlist(lapply(fs, function(f)
        fread(f, colClasses = list(character = c("corp_code", "rcept_no")))), fill = TRUE)
D <- D[!is.na(rcept_no) & nzchar(rcept_no)]
cat(sprintf("[reg] 대상 %s..%s | %d개월 | %d행 | cache_only=%s\n",
            START, END, length(fs), nrow(D), CACHE_ONLY))
cat("[reg] 저장(v2) parse_status 분포:\n"); print(D[, .N, by = parse_status][order(-N)])

num_eq <- function(a, b, tol = 1e-9) {
  if (is.na(a) && is.na(b)) return(TRUE)
  if (is.na(a) || is.na(b)) return(FALSE)
  if (a == b) return(TRUE)
  d <- abs(a - b); s <- max(abs(a), abs(b), 1)
  d / s <= tol
}
lgl_eq <- function(a, b) (is.na(a) && is.na(b)) || (!is.na(a) && !is.na(b) && a == b)

calls <- 0L; halted <- FALSE
n_done <- 0L; n_uncached <- 0L
diffs <- list(); encs <- character(0); chks <- character(0); news <- character(0)
audit <- list()   # ratio_check × is_correction 교차표 + 의심 행 원장

for (i in seq_len(nrow(D))) {
  rc <- as.character(D$rcept_no[i])
  cf <- file.path(DOCDIR, paste0(rc, ".bin"))
  if (!file.exists(cf)) {
    if (CACHE_ONLY) { n_uncached <- n_uncached + 1L; next }
    if (calls >= BUDGET) { cat(sprintf("[reg] 예산 도달 (%d) — 재실행 시 캐시분은 무료\n", calls)); halted <- TRUE; break }
    calls <- calls + 1L
    Sys.sleep(0.35)
  }
  pr <- tryCatch(parse_contract_doc(rc, KEY, is_correction = D$is_correction[i], cache_dir = DOCDIR),
                 error = function(e) NULL)
  if (is.null(pr)) {
    diffs[[length(diffs) + 1L]] <- data.table(rcept_no = rc, ym = D$ym[i], field = "EXCEPTION",
                                              stored = NA_character_, v3 = NA_character_)
    next
  }
  # ★한도 소진을 '원문 없음'으로 기록하지 않는다 — 즉시 halt (구 파서의 급소였다)
  if (identical(pr$parse_status, "RATE_LIMIT_020")) {
    cat(sprintf("[reg] DART status 020 (일한도) at %s — halt (calls=%d)\n", rc, calls))
    halted <- TRUE; break
  }
  n_done <- n_done + 1L
  e1 <- pr$doc_encoding; encs <- c(encs, if (is.null(e1) || is.na(e1)) "NA" else e1)
  chks <- c(chks, pr$ratio_check)
  news <- c(news, pr$parse_status)
  audit[[length(audit) + 1L]] <- data.table(
    rcept_no = rc, ym = D$ym[i], corp_name = D$corp_name[i],
    is_correction = isTRUE(D$is_correction[i]), parse_status = pr$parse_status,
    ratio_check = pr$ratio_check, contract_amount = pr$contract_amount,
    recent_revenue = pr$recent_revenue, disclosed_ratio_pct = pr$disclosed_ratio_pct)

  cmp <- list(
    contract_amount  = num_eq(D$contract_amount[i],  pr$contract_amount),
    recent_revenue   = num_eq(D$recent_revenue[i],   pr$recent_revenue),
    ratio_to_revenue = num_eq(D$ratio_to_revenue[i], pr$ratio_to_revenue),
    parse_status     = identical(as.character(D$parse_status[i]), pr$parse_status),
    is_amendment     = lgl_eq(as.logical(D$is_amendment[i]), pr$is_amendment),
    rounding_flag    = lgl_eq(as.logical(D$rounding_flag[i]), pr$rounding_flag),
    fx_flag          = lgl_eq(as.logical(D$fx_flag[i]),       pr$fx_flag))
  for (f in names(cmp)) if (!isTRUE(cmp[[f]]))
    diffs[[length(diffs) + 1L]] <- data.table(rcept_no = rc, ym = D$ym[i], field = f,
      stored = as.character(D[[f]][i]), v3 = as.character(pr[[f]]))
  if (n_done %% 250L == 0L)
    cat(sprintf("[reg] %d/%d 검증 (calls=%d, 불일치 %d)\n", n_done, nrow(D), calls, length(diffs)))
}

cat(sprintf("\n[reg] 검증 %d행 / API 호출 %d / 미캐시 스킵 %d / halted=%s\n",
            n_done, calls, n_uncached, halted))
if (length(encs)) { cat("[reg] doc_encoding 분포: "); print(table(encs, useNA = "ifany")) }
if (length(chks)) { cat("[reg] ratio_check 분포: "); print(table(chks, useNA = "ifany")) }
if (length(news)) { cat("[reg] v3 parse_status 분포: "); print(table(news, useNA = "ifany")) }

OUTF <- file.path(ROOT, sprintf(".cache/dart/contract_regression_%s_%s.csv", START, END))
if (length(diffs)) {
  DF <- rbindlist(diffs, fill = TRUE)
  fwrite(DF, OUTF)
  cat(sprintf("\n[reg] ❌ 불일치 %d건 (행 %d) → %s\n", nrow(DF), uniqueN(DF$rcept_no), OUTF))
  print(DF[, .N, by = field][order(-N)])
  print(head(DF, 20))
} else {
  if (file.exists(OUTF)) unlink(OUTF)
  cat("\n[reg] ✅ 회귀 없음 — 검증 전 행에서 7개 필드 전량 일치\n")
}
# ★검증 0행을 성공으로 읽지 않는다 ("빈 결과 = 합격" 계통).
if (n_done == 0L) { cat("[reg] ⚠ 검증 0행 — 판정 불가(미측정)\n"); quit(status = 3) }
quit(status = if (length(diffs)) 1L else 0L)
