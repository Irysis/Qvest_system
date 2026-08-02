#!/usr/bin/env Rscript
#==============================================================================
# dart_contract_reparse_failures.R — 파서 v2 로 parse 실패분 재파싱 (FQ-002)
#
# 2026-08-02 신설 (WT-D20260802_018). 크롤 중 실측 진단: 자율공시 서식
#   ("계약금액 총액(원)" + "최근 매출액(원)" 공백)이 구판 정규식에 전량 NO_AMOUNT
#   → 원본 실패 22.9% = 커버리지 편향 위험. 파서 v2 수리 후, 체크포인트의
#   parse_status != "OK" 행만 재fetch·재파싱해 CSV 를 제자리 갱신한다.
#
# 예산: 실패 행 수만큼 document.xml 호출 (파일럿 19개월 기준 ~350건, 36개월 ~700건).
# Usage: Rscript 02_Infrastructure/data/dart_contract_reparse_failures.R
#==============================================================================
suppressPackageStartupMessages({ library(data.table) })

.rr_root <- function() {
  cands <- c(Sys.getenv("CLAUDE_PROJECT_DIR", unset = ""), Sys.getenv("QM_ROOT", unset = ""),
             "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
  cands <- cands[nzchar(cands)]
  hit <- cands[file.exists(file.path(cands, "02_Infrastructure/hooks/qvest_hook_router.py"))]
  if (!length(hit)) stop("project root 미발견"); hit[1]
}
ROOT <- .rr_root()
env <- readLines(file.path(ROOT, ".env"), warn = FALSE)
KEY <- sub("^DART_API_KEY=", "", env[grepl("^DART_API_KEY=", env)][1])
source(file.path(ROOT, "02_Infrastructure/data/dart_contract_doc_parser.R"), encoding = "UTF-8")
CKDIR <- file.path(ROOT, ".cache/dart/contract_backfill")
BUDGET <- as.integer(Sys.getenv("DART_DAILY_BUDGET", "6900"))

# ── 회귀 검증 2건 (수리 후 위반 주입과 짝: 신형이 잡히고 구형이 안 깨졌는지) ──
chk <- parse_contract_doc("20230830900288", KEY)   # 자율공시형 (구판 NO_AMOUNT였던 실측 문서)
stopifnot(identical(chk$parse_status, "OK"),
          isTRUE(abs(chk$contract_amount - 8852690840) < 1),
          isTRUE(abs(chk$recent_revenue - 267491091324) < 1))
cat("[reparse] 회귀검증 1/2 PASS: 자율공시형 v2 추출 (테크윙 88.5억 / 매출 2,675억 — 상대방 40.68조 아님)\n")
chk2 <- parse_contract_doc("20260731800547", KEY)  # 표준형 (게이트 실측 3/3 중 1)
stopifnot(identical(chk2$parse_status, "OK"))
cat("[reparse] 회귀검증 2/2 PASS: 표준형 유지\n")
calls <- 2L

fs <- list.files(CKDIR, pattern = "^[0-9]{6}[.]csv$", full.names = TRUE)
n_fix <- 0L; n_still <- 0L
for (f in fs) {
  D <- fread(f, colClasses = list(character = "corp_code"))
  if (!"rcept_no" %in% names(D)) next
  idx <- which(!is.na(D$rcept_no) & D$parse_status != "OK" & D$parse_status != "")
  if (!length(idx)) next
  changed <- FALSE
  for (i in idx) {
    if (calls >= BUDGET) break
    calls <- calls + 1L
    pr <- tryCatch(parse_contract_doc(as.character(D$rcept_no[i]), KEY), error = function(e) NULL)
    Sys.sleep(0.6)
    if (is.null(pr)) next
    D[i, `:=`(contract_amount = pr$contract_amount, recent_revenue = pr$recent_revenue,
              ratio_to_revenue = pr$ratio_to_revenue, is_amendment = pr$is_amendment,
              rounding_flag = pr$rounding_flag, fx_flag = pr$fx_flag,
              parse_status = pr$parse_status, parse_note = pr$parse_note)]
    changed <- TRUE
    if (identical(pr$parse_status, "OK")) n_fix <- n_fix + 1L else n_still <- n_still + 1L
  }
  if (changed) fwrite(D, f)
  if (calls >= BUDGET) { cat("[reparse] 예산 도달 — 잔여는 다음 실행\n"); break }
}
cat(sprintf("[reparse] done. calls=%d | 복구 %d | 잔존실패 %d\n", calls, n_fix, n_still))
