## test_xf_fill_merge.R — XF(엑셀 · 퀀티) → DART 이름 채우기 병합(factor_db_builder.R::.fdb_xf_fill_merge)의 변환 계약
##   (2026-11-09 · FACTOR-DIRECTION-STORAGE-REPAIR-20261109). 구판은 이름만 바꿔 넣어 DART 가 음수로 저장하는 4개(Q05 · Q15 · GR03 · AC05)의
##   채움 행 부호가 반대였고 V08_PSR 채움 행은 역수였다(2016-06 실측: Q15 249행 · V08 31행 · 달마다 채움 수백 ~ 1,900행).
##   F1 DART 값이 있는 종목은 DART 그대로 · XF 원본 행은 남지 않는다
##   F2 음수 저장 4개 = 채움 행 −x
##   F3 V08 = 채움 행 1/x · x ≤ 0 은 뺀다
##   F4 변환 없는 짝(Q01) = 채움 행 그대로
##   F5 짝 밖 팩터는 건드리지 않는다
##   M1 돌연변이(Q05 변환 제거 · 소스 텍스트 치환 · 치환 성사 단정) → F2 가 걸린다
##   M2 돌연변이(V08 역수 제거) → F3 가 걸린다
suppressPackageStartupMessages({ library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
B <- file.path(ROOT, "02_Infrastructure/factor_db/factor_db_builder.R")
PASS <- 0L; FAIL <- 0L
chk <- function(name, ok, detail = "") {
  if (isTRUE(ok)) { PASS <<- PASS + 1L; cat(sprintf("  [ok]   %s\n", name)) } else { FAIL <<- FAIL + 1L; cat(sprintf("  [FAIL] %s %s\n", name, detail)) }
}
## 함수 정의만 소스 텍스트에서 꺼낸다(빌더 전체를 소스하면 config · 데이터 경로가 딸려 온다)
ex <- parse(B, keep.source = TRUE)
i <- which(vapply(ex, function(z) is.call(z) && identical(as.character(z[[1]]), "<-") && identical(as.character(z[[2]]), ".fdb_xf_fill_merge"), logical(1)))
stopifnot(length(i) == 1L)
SRC <- paste(as.character(attr(ex, "srcref")[[i]]), collapse = "\n")
load_fn <- function(src) { E <- new.env(parent = globalenv()); eval(parse(text = src), envir = E); get(".fdb_xf_fill_merge", envir = E) }
mutant <- function(old, new) {
  n <- lengths(regmatches(SRC, gregexpr(old, SRC, fixed = TRUE)))
  if (n != 1L) return(NULL)
  load_fn(sub(old, new, SRC, fixed = TRUE))
}

COMB <- rbindlist(list(
  data.table(Ticker = c("A", "B"), Factor_Name = "Q05_Accrual", Raw_Value = c(-0.05, -0.07)),     # DART(음수 저장)
  data.table(Ticker = c("A", "C"), Factor_Name = "XF_A01_Accrual", Raw_Value = c(0.04, 0.20)),    # XF(원래 양) — A 는 DART 있음
  data.table(Ticker = "A", Factor_Name = "V08_PSR", Raw_Value = 3.0),                              # DART 시총/매출
  data.table(Ticker = c("B", "C"), Factor_Name = "XF_V04_SP", Raw_Value = c(0.5, -1.0)),          # XF 매출/시총
  data.table(Ticker = "A", Factor_Name = "Q01_GPA", Raw_Value = 0.3),
  data.table(Ticker = "D", Factor_Name = "XF_Q01_GPA", Raw_Value = 0.25),
  data.table(Ticker = c("A", "B"), Factor_Name = "M01_Mom_12_1", Raw_Value = c(0.1, -0.2))         # 짝 밖
))
val <- function(d, f, t) d[Factor_Name == f & Ticker == t, Raw_Value]

run <- function(fn) {
  r <- list(); d <- fn(copy(COMB), verbose = FALSE)
  r$f1 <- identical(val(d, "Q05_Accrual", "A"), -0.05) && identical(val(d, "Q05_Accrual", "B"), -0.07) &&
    !any(grepl("^XF_(A01|V04|Q01)_", d$Factor_Name)) && d[Factor_Name == "Q05_Accrual" & Ticker == "A", .N] == 1L
  r$f2 <- isTRUE(all.equal(val(d, "Q05_Accrual", "C"), -0.20))
  r$f3 <- isTRUE(all.equal(val(d, "V08_PSR", "B"), 2.0)) && !length(val(d, "V08_PSR", "C")) && identical(val(d, "V08_PSR", "A"), 3.0)
  r$f4 <- isTRUE(all.equal(val(d, "Q01_GPA", "D"), 0.25))
  r$f5 <- isTRUE(all.equal(d[Factor_Name == "M01_Mom_12_1"][order(Ticker), Raw_Value], c(0.1, -0.2)))
  r
}
LIVE <- run(load_fn(SRC))
chk("F1 DART 값이 있는 종목은 DART 그대로 · XF 원본 행 없음", LIVE$f1)
chk("F2 음수 저장 짝(Q05) 채움 행 = −x", LIVE$f2)
chk("F3 V08 채움 행 = 1/x · x ≤ 0 제외", LIVE$f3)
chk("F4 변환 없는 짝(Q01) 채움 행 그대로", LIVE$f4)
chk("F5 짝 밖 팩터 그대로", LIVE$f5)
M1 <- mutant("XF_A01_Accrual        = function(x) -x,", "XF_A01_Accrual        = function(x) x,")
M2 <- mutant("XF_V04_SP             = function(x) fifelse(is.finite(x) & x > 0, 1 / x, NA_real_)", "XF_V04_SP             = function(x) x")
chk("M0 돌연변이 2개 치환 성사", is.function(M1) && is.function(M2))
if (is.function(M1)) chk("M1 Q05 변환 제거 → F2 가 걸린다", !isTRUE(run(M1)$f2))
if (is.function(M2)) chk("M2 V08 역수 제거 → F3 가 걸린다", !isTRUE(run(M2)$f3))
cat(sprintf("\n[test_xf_fill_merge] %d passed, %d failed\n", PASS, FAIL))
cat(sprintf('{"test":"xf_fill_merge","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))  # 배터리 요약 줄(run_all_hooks.sh)
if (FAIL > 0L) quit(save = "no", status = 1L)
