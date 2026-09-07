# test_l2_pool_grade_floor.R — v10 2계층 풀 grade floor 의 재도출 검증
#
# 계약 (v10 2026-08-29 도훈 "1계층에서 생산된 B등급 이상의 전략들을 활용"):
#   ① 산출물 module_performance.json 이 자기에게 쓰인 floor 를 기록한다(grade_floor)
#   ② floor ∈ {A,B} 산출물이면 수록 모듈 전건의 grade 가 floor 를 충족한다 (재도출 —
#      진술이 아니라 실제 수록분 대조. 감사 항목은 재도출이어야 한다)
#   ③ 빌더에 env 배선(QVEST_L2_GRADE_FLOOR)·제외 카운터가 실재한다 (부활 방지)
#   ④ register_module 에 grade_basis 파라미터·기록이 실재한다
#
# 실행: Rscript 08_Tests/contracts/test_l2_pool_grade_floor.R

# 앵커 = self-first (r-portability 금칙 ④-b: 테스트 러너는 자기 위치 1순위 — env 는 폴백)
.self <- tryCatch({
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", a[grepl("^--file=", a)])
  if (length(f)) dirname(f[1]) else "."
}, error = function(e) ".")
root <- normalizePath(file.path(.self, "..", ".."), winslash = "/", mustWork = FALSE)
if (!file.exists(file.path(root, "02_Infrastructure", "config.R")))
  root <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(root)
suppressPackageStartupMessages(library(jsonlite))
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a

pass <- 0L; fail <- 0L
ok <- function(m) { cat(sprintf("  [PASS] %s\n", m)); pass <<- pass + 1L }
ng <- function(m) { cat(sprintf("  [FAIL] %s\n", m)); fail <<- fail + 1L }

mp_path <- "06_Registry/module_performance.json"
mp <- tryCatch(fromJSON(mp_path, simplifyVector = FALSE), error = function(e) NULL)
if (is.null(mp)) { ng("module_performance.json 파싱 실패"); quit(status = 1L) }

# ① floor 메타 기록
fl <- as.character(mp$grade_floor %||% "")
if (nzchar(fl)) ok(sprintf("① grade_floor 메타 기록 = %s", fl)) else
  ng("① grade_floor 메타 부재 — 구판 산출물(재생성 필요) 또는 기록 누락")

# ② 재도출: floor ∈ {A,B} 이면 수록 전건 대조
if (fl %in% c("A", "B")) {
  allowed <- if (identical(fl, "A")) "A" else c("A", "B")
  grades <- vapply(mp$modules, function(m) toupper(as.character(m$grade %||% "")), character(1))
  bad <- grades[!grades %in% allowed]
  if (!length(bad)) ok(sprintf("② 수록 %d건 전건 grade ∈ {%s} (재도출 일치)",
                               length(grades), paste(allowed, collapse = ","))) else
    ng(sprintf("② floor=%s 인데 위반 등급 수록: %s", fl, paste(unique(bad), collapse = ",")))
  if (as.integer(mp$n_floor_excluded %||% -1L) >= 0L)
    ok(sprintf("② 제외 카운터 기록 = %s (침묵 절단 아님)", mp$n_floor_excluded)) else
    ng("② n_floor_excluded 부재 — 절단이 침묵한다")
} else if (identical(fl, "OFF")) {
  ok("② floor=OFF (진단 산출물) — 등급 대조 생략(정직 라벨)")
}

# ③ 빌더 배선 (부활 방지 — 텍스트)
bd <- paste(readLines("02_Infrastructure/regime/build_module_performance.R",
                      warn = FALSE, encoding = "UTF-8"), collapse = "\n")
## ★2026-09-07 재조준: 구 토큰 `.floor_ok`(빌더 사설 술어)는 계약 함수 `l2_admit()`
##   경유로 대체됐다(l2_pool_admission.R — 술어를 소비자의 함수 하나로 모은 수리).
##   이름이 옮겨졌을 뿐 의도는 그대로이므로 **현행 소비 지점**을 겨눈다. 죽은 표적에
##   빨강을 남기면 그 자리는 검사되지 않는 커버리지 구멍이 된다.
for (tok in c("QVEST_L2_GRADE_FLOOR", "l2_admit", ".floor_excluded")) {
  if (grepl(tok, bd, fixed = TRUE)) ok(sprintf("③ 빌더에 %s 실재", tok)) else
    ng(sprintf("③ 빌더에 %s 부재 — floor 가 걷힘", tok))
}
if (!grepl("등급은 정보용 attach만", bd, fixed = TRUE)) ok("③ 구 '등급 정보용' 서술 제거") else
  ng("③ 구 '등급 정보용' 서술 잔존 — v10 과 모순")

# ④ register_module grade_basis
rm_txt <- paste(readLines("02_Infrastructure/contracts/register_module.R",
                          warn = FALSE, encoding = "UTF-8"), collapse = "\n")
if (grepl("grade_basis = NA_character_", rm_txt, fixed = TRUE) &&
    grepl("grade_basis     = grade_basis", rm_txt, fixed = TRUE)) {
  ok("④ register_module grade_basis 파라미터+기록 실재")
} else ng("④ register_module grade_basis 배선 부재")

cat(sprintf("결과: PASS=%d FAIL=%d\n", pass, fail))
## ★러너 요약 계약 (v10 2026-09-03) — 없으면 run_all_hooks.sh 가 UNMEASURED 로 계상해 이 스위트의 단언이 총계에 0 으로 들어간다.
cat(sprintf('{"test":"l2_pool_grade_floor","pass":%d,"fail":%d,"total":%d,"skipped":0}\n', pass, fail, pass + fail))
if (fail > 0L) quit(status = 1L)
