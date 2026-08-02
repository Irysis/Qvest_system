#!/usr/bin/env Rscript
#==============================================================================
# dart_contract_reparse_failures.R — 파서 v3 로 parse 실패분 재파싱 (FQ-002)
#
# 2026-08-02 신설 (WT-D20260802_018). 크롤 중 실측 진단: 자율공시 서식
#   ("계약금액 총액(원)" + "최근 매출액(원)" 공백)이 구판 정규식에 전량 NO_AMOUNT
#   → 원본 실패 22.9% = 커버리지 편향 위험. 파서 v2 수리 후, 체크포인트의
#   parse_status != "OK" 행만 재fetch·재파싱해 CSV 를 제자리 갱신한다.
#
# 2026-08-03 v3 갱신:
#   · 재대상 판정에서 **원문 부재(정정공시)를 제외**한다 — DART 가 014 를 주는 건은
#     몇 번 재시도해도 원문이 없다. 구판은 이것도 매 실행 재fetch 해 예산을 태웠고,
#     성공률 분모에도 섞여 "파싱 실패"로 읽혔다.
#   · 원문 캐시(.cache/dart/contract_docs) 경유 — 이미 받은 문서는 **API 호출 0**.
#   · is_correction 전달 → 014 를 NO_SOURCE_CORRECTION 으로 라벨.
#   · 회귀 검증은 별도 정본으로 분리(dart_contract_parser_regression.R, 36개월 전량).
#     여기 인라인 stopifnot 2건은 **빠른 차단 실효 확인**이지 회귀 검증이 아니다.
#
# 예산: 재대상 행 수 − 캐시 적중분 만큼만 document.xml 호출.
# Usage: [REPARSE_START=201901 REPARSE_END=202607 DART_DAILY_BUDGET=6900] \
#          Rscript 02_Infrastructure/data/dart_contract_reparse_failures.R
#==============================================================================
suppressPackageStartupMessages({ library(data.table) })

.rr_root <- function() {
  cands <- c(Sys.getenv("CLAUDE_PROJECT_DIR", unset = ""), Sys.getenv("QM_ROOT", unset = ""),
             "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
  cands <- gsub("\\\\", "/", cands[nzchar(cands)])       # 정규화를 검사보다 먼저(금칙 ③)
  hit <- cands[file.exists(file.path(cands, "02_Infrastructure/hooks/qvest_hook_router.py"))]
  if (!length(hit)) stop("project root 미발견"); hit[1]
}
ROOT <- .rr_root()
env <- readLines(file.path(ROOT, ".env"), warn = FALSE)
KEY <- sub("^DART_API_KEY=", "", env[grepl("^DART_API_KEY=", env)][1])
source(file.path(ROOT, "02_Infrastructure/data/dart_contract_doc_parser.R"), encoding = "UTF-8")
CKDIR  <- file.path(ROOT, ".cache/dart/contract_backfill")
DOCDIR <- file.path(ROOT, ".cache/dart/contract_docs")
dir.create(DOCDIR, recursive = TRUE, showWarnings = FALSE)
BUDGET <- as.integer(Sys.getenv("DART_DAILY_BUDGET", "6900"))
START  <- Sys.getenv("REPARSE_START", "000000")
END    <- Sys.getenv("REPARSE_END",   "999999")

# ── 차단 실효 확인 2건 (수리가 살아있나 — 신형이 잡히고 구형이 안 깨졌는지) ──
chk <- parse_contract_doc("20230830900288", KEY, cache_dir = DOCDIR)   # 자율공시형
stopifnot(identical(chk$parse_status, "OK"),
          isTRUE(abs(chk$contract_amount - 8852690840) < 1),
          isTRUE(abs(chk$recent_revenue - 267491091324) < 1))
cat("[reparse] 확인 1/3 PASS: 자율공시형 추출 (테크윙 88.5억 / 매출 2,675억 — 상대방 40.68조 아님)\n")
chk2 <- parse_contract_doc("20260731800547", KEY, cache_dir = DOCDIR)  # 표준형
stopifnot(identical(chk2$parse_status, "OK"))
cat("[reparse] 확인 2/3 PASS: 표준형 유지\n")
chk3 <- parse_contract_doc("20190131800465", KEY, cache_dir = DOCDIR)  # 구서식(EUC-KR)
stopifnot(identical(chk3$parse_status, "OK"), identical(chk3$doc_encoding, "CP949"),
          isTRUE(abs(chk3$contract_amount - 9166581312) < 1))
cat("[reparse] 확인 3/3 PASS: 구서식 EUC-KR 디코딩 (씨에스윈드 91.7억, enc=CP949)\n")
calls <- sum(!c(chk$from_cache, chk2$from_cache, chk3$from_cache))

# ★재대상 = 파싱을 다시 해볼 여지가 있는 상태만.
#   NO_SOURCE_CORRECTION / NO_SOURCE_014 는 DART 에 원문이 없다 — 재시도가 무의미하고,
#   섞어 두면 "재파싱 실패 잔존"으로 계상돼 성공률이 왜곡된다(구판의 결함).
RETRYABLE_EXCL <- c("OK", "NO_SOURCE_CORRECTION", "NO_SOURCE_014")

fs <- list.files(CKDIR, pattern = "^[0-9]{6}[.]csv$", full.names = TRUE)
fs <- fs[basename(fs) >= paste0(START, ".csv") & basename(fs) <= paste0(END, ".csv")]
cat(sprintf("[reparse] 대상 체크포인트 %d개월 (%s..%s)\n", length(fs), START, END))

n_fix <- 0L; n_still <- 0L; n_nosrc <- 0L; still_status <- character(0)
for (f in fs) {
  D <- fread(f, colClasses = list(character = c("corp_code", "rcept_no")))
  if (!"rcept_no" %in% names(D)) next
  idx <- which(!is.na(D$rcept_no) & !(D$parse_status %in% RETRYABLE_EXCL) & nzchar(D$parse_status))
  if (!length(idx)) next
  # v3 신규 컬럼 자리 확보 (구 스키마 CSV 를 제자리 갱신하므로 없으면 만든다)
  for (cl in c("disclosed_ratio_pct", "ratio_check", "doc_encoding", "parser_version"))
    if (!cl %in% names(D)) D[, (cl) := if (cl == "disclosed_ratio_pct") NA_real_ else NA_character_]
  changed <- FALSE
  for (i in idx) {
    if (calls >= BUDGET) break
    cached <- file.exists(file.path(DOCDIR, paste0(as.character(D$rcept_no[i]), ".bin")))
    if (!cached) { calls <- calls + 1L; Sys.sleep(0.4) }
    pr <- tryCatch(parse_contract_doc(as.character(D$rcept_no[i]), KEY,
                                      is_correction = D$is_correction[i], cache_dir = DOCDIR),
                   error = function(e) NULL)
    if (is.null(pr)) next
    if (identical(pr$parse_status, "RATE_LIMIT_020")) {
      cat("[reparse] DART status 020 (일한도) — halt (미기록 없음: 이 행은 갱신 안 함)\n")
      calls <- BUDGET; break
    }
    D[i, `:=`(contract_amount = pr$contract_amount, recent_revenue = pr$recent_revenue,
              ratio_to_revenue = pr$ratio_to_revenue, disclosed_ratio_pct = pr$disclosed_ratio_pct,
              ratio_check = pr$ratio_check, is_amendment = pr$is_amendment,
              rounding_flag = pr$rounding_flag, fx_flag = pr$fx_flag,
              doc_encoding = pr$doc_encoding, parser_version = pr$parser_version,
              parse_status = pr$parse_status, parse_note = pr$parse_note)]
    changed <- TRUE
    if (identical(pr$parse_status, "OK")) n_fix <- n_fix + 1L
    else if (pr$parse_status %in% c("NO_SOURCE_CORRECTION", "NO_SOURCE_014")) n_nosrc <- n_nosrc + 1L
    else { n_still <- n_still + 1L; still_status <- c(still_status, pr$parse_status) }
  }
  if (changed) fwrite(D, f)
  if (calls >= BUDGET) { cat("[reparse] 예산 도달 — 잔여는 다음 실행\n"); break }
}
cat(sprintf("[reparse] done. calls=%d | 복구 %d | 원문부재 확정 %d | 잔존실패 %d\n",
            calls, n_fix, n_nosrc, n_still))
if (length(still_status)) { cat("[reparse] 잔존실패 사유 분포:\n"); print(table(still_status)) }
