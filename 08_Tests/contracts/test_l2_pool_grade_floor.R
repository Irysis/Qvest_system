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
#   ★2026-11-10 재조준(시험 정비): 2026-10-06 도훈 결정 "2계층 풀 구성 전환"(커밋 f0930f5532 ·
#     06_Registry/strategy_role.json pool.mode = "role") 이후 풀은 **역할 대표** 경로(admission_route = role_rep)로
#     들어온다. 그 경로의 자격 축은 essence 등급이 아니라 **역할 등급 B+**(strategy_roles.json card.roles.<역할>.grade)다
#     (strategy_role.json pool.basis "역할 B+ 하나 이상 = 2계층 풀 편입 경로 · essence 등급 floor 경로와 병렬").
#     구판 단언은 role_rep 모듈의 essence 등급(C · F)을 essence floor 에 대조해 10-07 부터 빨강이었다 — 낡은 축.
#     ⇒ 경로별로 **각자의 축에서** 재도출한다(느슨하게 하지 않는다: role_rep 은 역할 등급 B+ 를 등록부에서 다시 찾아
#        대조하고, 찾지 못하거나 B 미만이면 빨강 · 그 밖 경로는 종전 그대로 essence floor).
if (fl %in% c("A", "B")) {
  allowed <- if (identical(fl, "A")) "A" else c("A", "B")
  routes <- vapply(mp$modules, function(m) as.character(m$admission_route %||% ""), character(1))
  is_role <- routes == "role_rep"
  # 역할 대표 경로 — 빌더 .ROLE_REPS/.role_of 와 같은 조회(빈 pool_rep_roles 행 제외 → id 우선 → run id)
  if (any(is_role)) {
    sr_cfg <- tryCatch(fromJSON("06_Registry/strategy_role.json", simplifyVector = FALSE), error = function(e) NULL)
    pmode <- tolower(as.character(sr_cfg$pool$mode %||% "legacy"))
    if (!identical(pmode, "role"))
      ng(sprintf("② role_rep 경로 모듈 %d건인데 풀 모드 = %s — role 모드가 아니면 이 경로는 없어야 한다", sum(is_role), pmode))
    rr <- tryCatch(fromJSON("06_Registry/strategy_roles.json", simplifyVector = FALSE)$entries, error = function(e) NULL)
    rr <- Filter(function(e) length(unlist(e$pool_rep_roles)) > 0L, rr %||% list())
    cat_mods <- tryCatch(fromJSON("06_Registry/module_catalog.json", simplifyVector = FALSE)$modules, error = function(e) list())
    .runid <- function(x) { m <- regmatches(x, regexpr("[0-9]{8}_[0-9]{6}_[0-9]+", x, perl = TRUE)); if (length(m)) m else NA_character_ }
    role_bad <- character(0)
    for (id in names(mp$modules)[is_role]) {
      e <- rr[[id]]
      if (is.null(e)) {
        rec <- cat_mods[[id]]
        k <- .runid(paste(id, rec$meta$artifacts_dir %||% "", rec$bt_result_path %||% ""))
        if (!is.na(k)) e <- rr[[k]]
      }
      if (is.null(e)) { role_bad <- c(role_bad, sprintf("%s(역할 등록 없음)", id)); next }
      reps <- unlist(e$pool_rep_roles)
      claimed <- strsplit(as.character(mp$modules[[id]]$role %||% ""), ";", fixed = TRUE)[[1]]
      if (!setequal(claimed, reps)) role_bad <- c(role_bad, sprintf("%s(역할 %s ≠ 등록 %s)", id,
                                                                   paste(claimed, collapse = ";"), paste(reps, collapse = ";")))
      g <- vapply(reps, function(r) toupper(as.character(e$card$roles[[r]]$grade %||% "")), character(1))
      if (!all(g %in% c("A", "B"))) role_bad <- c(role_bad, sprintf("%s(역할 등급 %s)", id, paste(g, collapse = ",")))
    }
    if (!length(role_bad)) ok(sprintf("② role_rep %d건 전건 역할 등급 B+ (strategy_roles.json 재도출 일치)", sum(is_role))) else
      ng(sprintf("② role_rep 역할 B+ 재도출 불일치 %d건: %s", length(role_bad), paste(head(role_bad, 8), collapse = " · ")))
  }
  grades <- vapply(mp$modules[!is_role], function(m) toupper(as.character(m$grade %||% "")), character(1))
  bad <- grades[!grades %in% allowed]
  if (!length(bad)) ok(sprintf("② 비역할 경로 %d건 전건 essence grade ∈ {%s} (재도출 일치)",
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
