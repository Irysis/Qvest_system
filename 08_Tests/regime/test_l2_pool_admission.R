#!/usr/bin/env Rscript
#==============================================================================
# test_l2_pool_admission.R — 2계층 풀 자격 술어 (2026-09-07 신설)
#
# 왜: 2026-09-04 에 방어형 경로가 "배선됐다" 고 기록됐는데, 2026-09-07 실측에서
#   module_catalog 275건 중 defensive_score 보유 **0건**이었다 — 생산자(essence_score)와
#   소비자(풀 조립부) 가 둘 다 있는데 그 사이 등재기가 값을 안 실었다. 게다가 풀 조립부는
#   계약 함수 `ds_pool_eligible()` 대신 자체 사본 `.defensive_ok()` 를 들고 있었고,
#   등급 floor 는 essence 가 아니라 **발행 시점 `grade`** 를 읽고 있었다.
#   기존 검사(test_rolling_defensive.R §J)는 소스 문자열만 봤기 때문에 전부 초록이었다.
#   ⇒ 이 검사는 술어를 **합성 카탈로그로 실제 구동**한다.
#
# 지키는 것:
#   ① grade B → grade_floor 편입              ② grade F + 방어형 → defensive_specialist
#   ③ grade F + 비방어형 → 제외                ④ defensive_score **부재** → 제외 + 사유가
#      `dscore_absent` 로 남는다 (부재 ≠ 거짓 — 한 칸에 합치면 배선 결함이 안 보인다)
#   ⑤ QVEST_L2_DEFENSIVE_ROUTE=OFF → 방어형 편입 0
#   ⑥ 술어가 계약 `ds_pool_eligible()` 을 **런타임에 실제로 경유**한다 (sentinel 주입)
#   ⑦ 등급 축 = essence (essence_grade > meta.essence_grade > grade 폴백) — 회귀 지점
#   ⑧ 운영 06_Registry/module_catalog.json 을 건드리지 않는다 (md5 전후 대조)
#==============================================================================
suppressMessages({ library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
ROOT <- gsub("\\\\", "/", ROOT)          # R 문자열 안 Windows 백슬래시(\U)는 즉사
setwd(ROOT); Sys.setenv(QM_ROOT = ROOT)
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat(sprintf("  OK   %s\n", m)) }
ng <- function(m, d = "") { FAIL <<- FAIL + 1L; cat(sprintf("  FAIL %s%s\n", m, if (nzchar(d)) paste0(" — ", d) else "")) }

OPS_CATALOG <- file.path(ROOT, "06_Registry/module_catalog.json")
MD5_BEFORE  <- if (file.exists(OPS_CATALOG)) unname(tools::md5sum(OPS_CATALOG)) else NA_character_

## ── 검사 대상 = 소비자의 함수 그 자체 ────────────────────────────────────────
suppressMessages(source(file.path(ROOT, "02_Infrastructure/regime/l2_pool_admission.R")))

# ── 합성 defensive_score (ds_score 반환 형태) ────────────────────────────────
.ds <- function(defensive, status = "ok", n = 40L, excess = 0.015, t = 3.1, hit = 0.66)
  list(status = status, defensive = defensive, convex = TRUE, n_months = 200L,
       down = list(n = n, excess = excess, hit = hit, t = t, capture = 0.6),
       deep = list(n = 9L, excess = excess, hit = hit, t = 1.6, capture = 0.9),
       reason = "합성 픽스처")

# ── 합성 카탈로그 (운영 파일 미사용 — tempdir 사본으로만) ────────────────────
.contract <- list(contract_pass = TRUE)
.mod <- function(grade = "F", essence = NULL, meta_essence = NULL, ds = NULL,
                 fr = TRUE, metric = "backtested") {
  e <- list(strategy_id = "X", grade = grade, fr_eligible = fr, metric_type = metric,
            contract = .contract, sim_result_path = "x/sim_result.rds")
  if (!is.null(essence))      e$essence_grade <- essence
  if (!is.null(meta_essence)) e$meta <- list(essence_grade = meta_essence,
                                             essence_regrade_ref = "fixture_regrade")
  if (!is.null(ds))           e$defensive_score <- ds
  e
}
MODS <- list(
  m_gradeB          = .mod(grade = "B", essence = "B", ds = .ds(FALSE)),   # ①
  m_F_defensive     = .mod(grade = "F", essence = "F", ds = .ds(TRUE)),    # ②
  m_F_not_defensive = .mod(grade = "F", essence = "F", ds = .ds(FALSE)),   # ③
  m_F_no_dscore     = .mod(grade = "F", essence = "F", ds = NULL),         # ④
  m_F_ds_notok      = .mod(grade = "F", essence = "F",
                           ds = .ds(NA, status = "하락월 10 < 12 — 판정 불가")),
  m_emitF_essB      = .mod(grade = "F", essence = "B", ds = NULL),         # ⑦ 축 회귀
  m_emitF_metaB     = .mod(grade = "F", meta_essence = "B", ds = NULL),    # ⑦ 축 회귀
  m_contract_fail   = .mod(grade = "F", essence = "F", ds = .ds(TRUE), fr = FALSE)
)
TD <- file.path(tempdir(), sprintf("l2pool_%d", Sys.getpid()))
dir.create(TD, recursive = TRUE, showWarnings = FALSE)
FIX <- file.path(TD, "module_catalog.json")
write(toJSON(list(modules = MODS), auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null"), FIX)
MODS <- fromJSON(FIX, simplifyVector = FALSE)$modules   # ★JSON 왕복 — 운영과 같은 형태로 읽는다

cat("=== A. 편입 경로 (방어형 경로 ON) ===\n")
R <- l2_admit_catalog(MODS, floor = "B", defensive_route = TRUE)
.route <- function(id) as.character(R$routes[[id]])
.code  <- function(id) as.character(R$codes[[id]])

if (identical(.route("m_gradeB"), "grade_floor"))
  ok("A1 ① grade B → grade_floor 편입") else ng("A1", .code("m_gradeB"))
if (identical(.route("m_F_defensive"), "defensive_specialist"))
  ok("A2 ② grade F + 방어형 → defensive_specialist 편입") else ng("A2", .code("m_F_defensive"))
if (is.na(R$routes[["m_F_not_defensive"]]) && identical(.code("m_F_not_defensive"), "not_defensive"))
  ok("A3 ③ grade F + 비방어형 → 제외(not_defensive · 위반 주입)") else
  ng("A3", .code("m_F_not_defensive"))
if (is.na(R$routes[["m_F_no_dscore"]]) && identical(.code("m_F_no_dscore"), "dscore_absent"))
  ok("A4 ④ defensive_score 부재 → 제외 + 사유 dscore_absent (부재 ≠ 거짓)") else
  ng("A4 부재가 '아님'으로 뭉개졌다", .code("m_F_no_dscore"))
if (identical(.code("m_F_ds_notok"), "dscore_not_ok"))
  ok("A5 표본 부족은 '아님'이 아니라 판정 불가로 따로 센다") else ng("A5", .code("m_F_ds_notok"))
if (identical(.code("m_contract_fail"), "contract_floor") && is.na(R$routes[["m_contract_fail"]]))
  ok("A6 계약 floor 미달은 방어형이어도 편입 안 됨 — 다른 층의 거절로 따로 센다") else
  ng("A6", .code("m_contract_fail"))

cat("\n=== B. ④ 집계에 사유가 실제로 남는가 ===\n")
tl <- R$tally
## ★기대값을 픽스처에서 못박는다 — "있으면 통과" 로 두면 항상 초록이라 아무것도 안 지킨다.
##   부재로 **제외되는** 것은 m_F_no_dscore 1건뿐이다(emitF_essB/metaB 는 등급으로 먼저 편입).
.n_abs <- if (is.null(tl[["dscore_absent"]])) 0L else as.integer(tl[["dscore_absent"]])
if (.n_abs == 1L) ok("B1 dscore_absent 집계 = 1 (픽스처 기대값과 일치)") else
  ng("B1 dscore_absent 집계 불일치", sprintf("기대 1 · 실측 %d", .n_abs))
if (!is.null(tl[["dscore_absent"]]) && !is.null(tl[["not_defensive"]]))
  ok("B2 부재와 거짓이 **다른 칸**에 있다") else
  ng("B2 부재/거짓이 한 칸으로 뭉개짐",
     paste(names(tl), as.integer(tl), sep = "=", collapse = " "))
if (R$n_excluded >= 1L && R$n_contract_excluded == 1L)
  ok(sprintf("B3 제외 집계 분리: 자격 제외 %d · 계약 제외 %d", R$n_excluded, R$n_contract_excluded)) else
  ng("B3 제외 집계", sprintf("%d/%d", R$n_excluded, R$n_contract_excluded))

cat("\n=== C. ⑦ 등급 축 = essence (발행 시점 grade 아님) ★회귀 지점 ===\n")
if (identical(.route("m_emitF_essB"), "grade_floor") &&
    identical(as.character(R$grade_sources[["m_emitF_essB"]]), "entry"))
  ok("C1 grade=F 이지만 essence_grade=B → grade_floor (구판은 여기서 빠졌다)") else
  ng("C1 emit grade 를 읽고 있다", .code("m_emitF_essB"))
if (identical(.route("m_emitF_metaB"), "grade_floor") &&
    identical(as.character(R$grade_sources[["m_emitF_metaB"]]), "meta_regrade"))
  ok("C2 meta.essence_grade=B(v9.21 재채점) → grade_floor · 출처가 meta_regrade 로 남는다") else
  ng("C2", paste(.code("m_emitF_metaB"), R$grade_sources[["m_emitF_metaB"]]))
## 음성 대조 — essence 가 없으면 emit grade 로 폴백하되 출처를 밝힌다
g <- l2_essence_grade(list(grade = "B"))
if (identical(g$grade, "B") && identical(g$source, "emit_grade"))
  ok("C3 essence 부재 시 emit 폴백 + 출처 표시(조용한 대체 아님)") else ng("C3", g$source)
g0 <- l2_essence_grade(list(grade = "ungraded"))
if (is.na(g0$grade) && identical(g0$source, "none"))
  ok("C4 'ungraded' 를 등급으로 승격하지 않는다") else ng("C4", g0$source)

cat("\n=== D. ⑤ kill switch (QVEST_L2_DEFENSIVE_ROUTE) ===\n")
R_off <- l2_admit_catalog(MODS, floor = "B", defensive_route = FALSE)
if (R_off$n_defensive == 0L) ok("D1 defensive_route=FALSE → 방어형 편입 0") else
  ng("D1 스위치 무력", as.character(R_off$n_defensive))
if (R_off$n_grade_floor == R$n_grade_floor)
  ok(sprintf("D2 등급 경로는 스위치와 무관 (grade_floor %d 유지 — 병렬 경로이지 대체가 아니다)",
             R_off$n_grade_floor)) else ng("D2 등급 경로가 함께 죽었다")
if (!is.null(R_off$tally[["route_off"]]))
  ok("D3 해제 사유가 route_off 로 남는다(비방어형과 구분)") else ng("D3 해제가 침묵")
## env 해석기 양방향
.old_route <- Sys.getenv("QVEST_L2_DEFENSIVE_ROUTE", unset = NA)
Sys.setenv(QVEST_L2_DEFENSIVE_ROUTE = "OFF")
d_off <- l2_env_defensive_route()
Sys.setenv(QVEST_L2_DEFENSIVE_ROUTE = "ON")
d_on <- l2_env_defensive_route()
if (isFALSE(d_off) && isTRUE(d_on)) ok("D4 env 해석기 양방향 (OFF/ON)") else
  ng("D4 env 해석", sprintf("off=%s on=%s", d_off, d_on))
.old_floor <- Sys.getenv("QVEST_L2_GRADE_FLOOR", unset = NA)
Sys.setenv(QVEST_L2_GRADE_FLOOR = "OFF")
if (identical(l2_env_floor(), "OFF")) ok("D5 floor OFF 해석") else ng("D5 floor 해석")
R_fo <- l2_admit_catalog(MODS, floor = "OFF", defensive_route = TRUE)
if (R_fo$n_admitted == 7L && !is.null(R_fo$tally[["floor_off"]]))
  ok(sprintf("D6 floor=OFF 진단판 = 계약 통과분 전량 편입 %d건", R_fo$n_admitted)) else
  ng("D6 floor OFF", as.character(R_fo$n_admitted))
if (is.na(.old_route)) Sys.unsetenv("QVEST_L2_DEFENSIVE_ROUTE") else
  Sys.setenv(QVEST_L2_DEFENSIVE_ROUTE = .old_route)
if (is.na(.old_floor)) Sys.unsetenv("QVEST_L2_GRADE_FLOOR") else
  Sys.setenv(QVEST_L2_GRADE_FLOOR = .old_floor)

cat("\n=== E. ⑥ 술어가 계약을 **런타임에** 경유하는가 (sentinel 주입) ===\n")
## 소스 문자열이 아니라 동작으로 재도출한다 — 사본을 들고 있으면 sentinel 이 안 먹는다.
.real <- ds_pool_eligible
assign("ds_pool_eligible",
       function(grade, dscore, params = NULL, floor = "B", defensive_route = TRUE)
         list(eligible = TRUE, route = "SENTINEL", code = "sentinel", reason = "주입"),
       envir = globalenv())
R_s <- l2_admit_catalog(MODS, floor = "B", defensive_route = TRUE)
assign("ds_pool_eligible", .real, envir = globalenv())
if (identical(as.character(R_s$routes[["m_F_not_defensive"]]), "SENTINEL"))
  ok("E1 l2_admit 이 ds_pool_eligible 을 실제로 호출한다(주입이 판정을 바꾼다)") else
  ng("E1 자체 사본을 들고 있다 — 계약 미경유", as.character(R_s$routes[["m_F_not_defensive"]]))
R_r <- l2_admit_catalog(MODS, floor = "B", defensive_route = TRUE)
if (identical(as.character(R_r$routes[["m_F_not_defensive"]]), "NA") ||
    is.na(R_r$routes[["m_F_not_defensive"]]))
  ok("E2 주입 해제 후 원판정 복귀(양성 대조)") else ng("E2 복귀 실패")
## 소비자 소스 재도출 — 자체 사본이 되살아나지 않았는가
.code_only <- function(p) paste(sub("#.*$", "", readLines(p, warn = FALSE)), collapse = "\n")
bsrc <- .code_only(file.path(ROOT, "02_Infrastructure/regime/build_module_performance.R"))
if (grepl("l2_admit(", bsrc, fixed = TRUE))
  ok("E3 풀 조립부가 l2_admit() 을 소비한다") else ng("E3 소비 없음")
if (!grepl(".defensive_ok", bsrc, fixed = TRUE))
  ok("E4 풀 조립부에 자체 술어 사본(.defensive_ok) 없음") else
  ng("E4 자격 술어가 둘로 갈렸다", "소비자가 자기 사본을 들면 두 판정이 갈린다")
lsrc <- .code_only(file.path(ROOT, "02_Infrastructure/regime/l2_pool_admission.R"))
if (grepl("ds_pool_eligible", lsrc, fixed = TRUE))
  ok("E5 술어 파일이 계약을 참조한다") else ng("E5")

cat("\n=== F. 등재기 이음매 — 카탈로그로 전이되는가 ===\n")
rsrc <- .code_only(file.path(ROOT, "02_Infrastructure/contracts/register_module.R"))
if (grepl("defensive_score", rsrc, fixed = TRUE) && grepl("essence_grade", rsrc, fixed = TRUE))
  ok("F1 register_module 이 두 필드를 다룬다") else
  ng("F1 등재기가 값을 안 싣는다 — 생산자·소비자 사이 전이 없음")
## 실제 entry 에 실리는지 형태로 재도출(가짜 sim_result 로 entry 만 만든다)
.tmp_env <- new.env(parent = globalenv())
okreg <- tryCatch({
  sys.source(file.path(ROOT, "02_Infrastructure/contracts/register_module.R"), envir = .tmp_env)
  fml <- names(formals(get("register_module", envir = .tmp_env)))
  all(c("essence_grade", "defensive_score", "auth_remeasure_path") %in% fml)
}, error = function(e) { cat("   (", conditionMessage(e), ")\n"); FALSE })
if (isTRUE(okreg)) ok("F2 register_module 시그니처에 전이 인자 3종") else
  ng("F2 시그니처 미확장")

cat("\n=== G. ⑧ 운영 카탈로그 불변 ===\n")
MD5_AFTER <- if (file.exists(OPS_CATALOG)) unname(tools::md5sum(OPS_CATALOG)) else NA_character_
if (identical(MD5_BEFORE, MD5_AFTER))
  ok("G1 06_Registry/module_catalog.json md5 불변 (검사는 tempdir 픽스처만 썼다)") else
  ng("G1 ★운영 원장이 검사 중에 바뀌었다", sprintf("%s -> %s", MD5_BEFORE, MD5_AFTER))
unlink(TD, recursive = TRUE)

cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
cat(sprintf('{"test":"l2_pool_admission","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL > 0L) 1L else 0L)
