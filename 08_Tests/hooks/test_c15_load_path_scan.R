#!/usr/bin/env Rscript
#==============================================================================
# test_c15_load_path_scan.R — C15 스캐너 위반 주입 테스트 (양방향)
# 오늘의 규율: "FAIL 이 뜬다"만으로는 검사기 생존 증명이 안 된다.
#   정상에 PASS · 위반에 FAIL · 관용 케이스에 PASS_WITH_NOTES · 전제 부재에 ERROR — 넷 다 확인.
#==============================================================================
suppressPackageStartupMessages({ library(data.table) })
R <- local({
  m <- "02_Infrastructure/hooks/qvest_hook_router.py"
  c1 <- c(Sys.getenv("CLAUDE_PROJECT_DIR",""), Sys.getenv("QM_ROOT",""), "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
  c1 <- c1[nzchar(c1)]; h <- c1[file.exists(file.path(c1, m))]
  if (!length(h)) stop("root 해석 실패"); normalizePath(h[1])
})
setwd(R); source("02_Infrastructure/validation/c15_load_path_scan.R")

## ★2026-08-08 수리 — 초판은 최상위에서 on.exit(unlink(TMP)) 를 썼다. r-portability.md 금칙 ②.
##   초판 주석은 "스크립트 최상위 아님"이라고 **합리화**했으나 사실이 아니었고, 같은 금칙이
##   test_blunt_anchor_failclosed.R 초판에서 **조기 발화로 백업을 선삭제**해 패널을 오염시킨
##   전례가 이미 있다(재생성으로 복구). 수리 = 전체를 함수로 감싸 on.exit 를 함수 프레임에 등록.
main <- function() {
  TMP <- file.path(tempdir(), paste0("c15test_", as.integer(runif(1, 1e6, 9e6))))
  dir.create(TMP, recursive = TRUE, showWarnings = FALSE)
  on.exit(unlink(TMP, recursive = TRUE), add = TRUE)   ## 함수 프레임 등록 = 예외 경로에서도 발화

  pass <- 0L; fail <- 0L
  chk <- function(nm, got, want) {
    ok <- identical(got, want)
    cat(sprintf("  [%s] %-46s got=%-16s want=%s\n", if (ok) "PASS" else "FAIL", nm, got, want))
    if (ok) pass <<- pass + 1L else fail <<- fail + 1L
  }
  w <- function(nm, lines) { p <- file.path(TMP, nm); writeLines(lines, p); invisible(p) }

  ## ① 정상: 커넥터 경유만
  w("ok_connector.R", c('f <- load_month_factors(dd, factor_names="R05_Tail_Risk")', 'x <- f[[1]]'))
  ## ② 관용: 직접 read + align 있음 (현 production 패턴)
  w("tolerated.R", c('f <- read_parquet(".cache/factor_db/factor_db_202608.parquet")',
                     'a <- align_factor_direction(f, reg, sig_date=AS_OF, min_ic_months=12L)'))
  ## ③ 위반 주입: 직접 read + align 없음
  w("violate.R", c('f <- read_parquet(".cache/factor_db/factor_db_202608.parquet")', 'z <- f$Z_Score'))
  ## ④ 주석 위장: 주석 속 직접 read 는 잡히면 안 됨(오탐 방지)
  w("comment_only.R", c('# f <- read_parquet(".cache/factor_db/factor_db_202608.parquet")',
                        'f <- load_month_factors(dd)'))
  ## ★⑤ 변수 경유(초판 사각지대 — 2026-08-08 자체 적발): 경로를 변수에 담고 read_parquet(변수)
  w("via_var.R", c('fdb <- file.path(ROOT, sprintf(".cache/factor_db/factor_db_%s.parquet", ym))',
                   'f <- as.data.table(read_parquet(fdb, col_select=c("Ticker","Z_Score")))',
                   'a <- align_factor_direction(f, reg, sig_date=AS_OF)'))
  ## ⑥ 변수 경유 + align 없음 → FAIL 이어야
  w("via_var_noalign.R", c('fdb <- file.path(ROOT, ".cache/factor_db/factor_db_202608.parquet")',
                           'f <- read_parquet(fdb)', 'z <- f$Z_Score'))
  res <- c15_scan(roots = TMP, quiet = TRUE)
  g <- function(n) res[file == n | basename(file) == n, verdict][1]
  cat("=== 판정 ===\n")
  chk("정상(커넥터만)", g("ok_connector.R"), "PASS")
  chk("관용(직접read+align)", g("tolerated.R"), "PASS_WITH_NOTES")
  chk("★위반 주입(직접read, align 없음)", g("violate.R"), "FAIL")
  chk("주석 위장(오탐 방지)", g("comment_only.R"), "PASS")
  chk("★변수 경유 + align (초판 사각지대)", g("via_var.R"), "PASS_WITH_NOTES")
  chk("★변수 경유 + align 없음", g("via_var_noalign.R"), "FAIL")

  ## ⑤ 전제 부재: 대상 0 → ERROR(합격 아님)
  empty <- file.path(TMP, "empty"); dir.create(empty, showWarnings = FALSE)
  e <- tryCatch({ c15_scan(roots = empty, quiet = TRUE); "NO_ERROR" }, error = function(x) "ERROR")
  chk("대상 0 → ERROR(빈 결과≠합격)", e, "ERROR")

  ## ⑥ 실제 운영 경로 스캔이 살아있는가 (기능 프로브 — 0파일이면 검사 사망)
  real <- c15_scan(quiet = TRUE)
  chk("운영 경로 스캔 파일수 > 0", nrow(real) > 0L, TRUE)
  cat(sprintf("\n[운영 경로 현황] %d파일 | PASS %d · NOTES %d · FAIL %d\n", nrow(real),
              sum(real$verdict=="PASS"), sum(real$verdict=="PASS_WITH_NOTES"), sum(real$verdict=="FAIL")))
  cat(sprintf("\n===== %d PASS / %d FAIL =====\n", pass, fail))
  # 2026-08-20: 배터리는 마지막 유효 JSON 줄만 읽는다. 카운터가 main() 지역변수라
  #   최상위에 두면 'object not found' 로 죽는다 — 스코프 안에서 발행한다.
  cat(sprintf("{\"test\":\"test_c15_load_path_scan\",\"pass\":%d,\"fail\":%d,\"total\":%d}\n",
              pass, fail, pass + fail))
  if (fail == 0L) 0L else 1L
}

.rc <- main()
if (!interactive()) quit(status = .rc)
