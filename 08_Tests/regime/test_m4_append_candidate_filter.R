# test_m4_append_candidate_filter.R — m4 append-only 게이트 후보 필터의 양방향 검증
#
# 배경 (2026-08-29 실사고): AS_OF=2026-09-01 월중(08-29) 실행에서 재생성본이 발행 후보가
#   아닌 행 2류를 만들었다 — ①기발행 월 중복 결정행(08-03 vs 발행 08-01) ②데이터 꼬리
#   행(08-28). ②가 자기 달 말(08-31) 라벨 매크로를 물어 PIT 게이트(rc=4)가 **전체를**
#   차단했고, 진짜 새 달(09-01) 발행까지 막혔다. 수리 = "미발행 월의 첫 행만 후보"
#   (독트린 "새 달만 잇는다"의 구현 정합 — m4_append_only.R:137~).
#
# 계약 (양방향 — 필터가 PIT 이빨을 뽑으면 안 된다):
#   ① 기발행 월의 중복/꼬리 행은 후보에서 제외되고 **제외 사실이 로그에 남는다**
#   ② 미발행 월의 첫 행은 후보로 남는다
#   ③ [이빨 보존] 남은 후보의 PIT 검사 코드는 불변 — 위반 시 quit(status=4) 경로 실재
#
# 방식: 필터 로직을 소스에서 그대로 추출 실행(모의 데이터) + 텍스트 재도출.
# 실행: Rscript 08_Tests/regime/test_m4_append_candidate_filter.R

.self <- tryCatch({
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", a[grepl("^--file=", a)])
  if (length(f)) dirname(f[1]) else "."
}, error = function(e) ".")
root <- normalizePath(file.path(.self, "..", ".."), winslash = "/", mustWork = FALSE)
if (!file.exists(file.path(root, "02_Infrastructure", "config.R")))
  root <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(root)
suppressPackageStartupMessages(library(data.table))

pass <- 0L; fail <- 0L
ok <- function(m) { cat(sprintf("  [PASS] %s\n", m)); pass <<- pass + 1L }
ng <- function(m) { cat(sprintf("  [FAIL] %s\n", m)); fail <<- fail + 1L }

SRC <- "02_Infrastructure/regime/m4_append_only.R"
txt <- paste(readLines(SRC, warn = FALSE, encoding = "UTF-8"), collapse = "\n")

# ①② 필터 의미 재현 (소스와 동일 연산 — 모의: 발행 …~08-01 / add = 08-03, 08-28, 09-01)
pub_dates <- as.Date(c("2026-07-01", "2026-08-01"))
add <- data.table(Date = as.Date(c("2026-08-03", "2026-08-28", "2026-09-01")), v = 1:3)
.add_ym <- format(add$Date, "%Y-%m")
.pub_ym <- unique(format(pub_dates, "%Y-%m"))
.keep <- !duplicated(.add_ym) & !(.add_ym %in% .pub_ym)
if (identical(as.character(add$Date[.keep]), "2026-09-01"))
  ok("①② 모의 재현: {08-03, 08-28} 제외 · {09-01} 유지 (실사고 셋 그대로)") else
  ng(sprintf("①② 필터 결과 오류: %s", paste(add$Date[.keep], collapse = ",")))
# 같은 새 달에 결정행+꼬리가 둘 다 오면 첫 행만
add2 <- data.table(Date = as.Date(c("2026-09-01", "2026-09-26")), v = 1:2)
.a2 <- format(add2$Date, "%Y-%m")
.k2 <- !duplicated(.a2) & !(.a2 %in% .pub_ym)
if (identical(as.character(add2$Date[.k2]), "2026-09-01"))
  ok("② 새 달 내 복수 행 → 첫 행(결정행)만 후보") else ng("② 새 달 첫 행 선별 실패")

# ① 소스에 필터+로그가 실재하는가 (부활 방지 — 텍스트 재도출)
if (grepl("!duplicated(.add_ym) & !(.add_ym %in% .pub_ym)", txt, fixed = TRUE))
  ok("① 소스에 후보 필터 실재") else ng("① 후보 필터가 소스에서 사라짐")
if (grepl("발행 후보 제외", txt, fixed = TRUE))
  ok("① 제외가 침묵하지 않음 (로그 문구 실재)") else ng("① 제외 로그 부재 — 침묵 절단")

# ③ PIT 이빨 보존 — 필터 뒤에도 pit_check_rows(add) + quit(status = 4) 경로 실재
if (grepl("pit_check_rows(add)", txt, fixed = TRUE) && grepl("quit(status = 4)", txt, fixed = TRUE))
  ok("③ PIT 검사·차단(rc=4) 경로 불변 — 필터가 이빨을 뽑지 않음") else
  ng("③ PIT 차단 경로 소실 — 필터가 검사를 우회시켰다")
# 필터가 pit_check 이전에 위치하는가 (후보 정제 → 검사 순서)
p_f <- regexpr("발행 후보 제외", txt, fixed = TRUE)
p_p <- regexpr("pit_check_rows(add)", txt, fixed = TRUE)
if (p_f > 0 && p_p > 0 && p_f < p_p)
  ok("③ 순서 = 후보 정제 → PIT 검사 (검사 대상이 정확)") else ng("③ 필터/검사 순서 이상")

cat(sprintf("결과: PASS=%d FAIL=%d\n", pass, fail))
## ★러너 요약 계약 (v10 2026-09-03) — 없으면 run_all_hooks.sh 가 UNMEASURED 로 계상해 이 스위트의 단언이 총계에 0 으로 들어간다.
cat(sprintf('{"test":"m4_append_candidate_filter","pass":%d,"fail":%d,"total":%d,"skipped":0}\n', pass, fail, pass + fail))
if (fail > 0L) quit(status = 1L)
