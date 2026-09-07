#!/usr/bin/env Rscript
# =============================================================================
# l2_pool_admission.R — 2계층 로테이션 **풀 자격 술어** (2026-09-07)
#
# 왜 별도 파일인가: 자격 술어가 `build_module_performance.R` 안에 인라인으로 있으면
#   검사가 그것을 구동하려고 국면 parquet + sim_result.rds 전량을 세워야 한다. 그래서
#   검사는 술어를 **재구현**하게 되고(= 자기 사본을 검사하는 무의미한 초록), 소비자와
#   갈린다. 실제로 2026-09-04~09-07 사이 풀 조립부는 `.defensive_ok()` 라는 자체 사본을
#   들고 있었고 `ds_pool_eligible()` 은 아무도 부르지 않았다(호출자 = 검사 1개뿐).
#   ⇒ 술어를 소비자가 실제로 부르는 한 함수로 모으고, 검사는 **그 함수**를 합성
#      카탈로그로 구동한다.
#
# 판정 축 (SKILL strategy-rotation §3):
#   ① 등급 floor — **essence 등급** ∈ {A,B} (env QVEST_L2_GRADE_FLOOR: B(기본)/A/OFF)
#   ② 방어형 병렬 경로 — 등급 미달이어도 defensive_score$defensive 면 편입
#      (env QVEST_L2_DEFENSIVE_ROUTE=OFF 로 해제)
#   판정 자체는 `02_Infrastructure/contracts/defensive_score.R::ds_pool_eligible()` 이 낸다.
#
# ★등급 축 (2026-09-07 정정): 소비자는 오랫동안 `rec$grade` 를 읽었는데 그 값은
#   **발행 시점 기록**이다(essence_regrade_apply.R 이 명시: "top-level grade 는 불변").
#   v9.21 권위 재채점 결과는 `meta$essence_grade` 에 병기됐고, 신규 등재는
#   `essence_grade` 를 싣는다. 세 자리가 갈린 채로 floor 를 걸면 SKILL 이 말하는
#   "essence grade" 와 코드가 읽는 값이 다른 축이 된다(실측: 그 때문에 essence B 인
#   fr_eligible 모듈 3건이 풀에서 빠져 있었다).
#   ⇒ 우선순위 = essence_grade > meta.essence_grade > grade(폴백, source 로 표시).
#
# env 는 **호출자가 읽어 넘긴다** — 이 파일의 함수는 env 를 읽지 않는다(검사가 운영
#   env 를 빌리면 그 env 를 고칠 때 검사가 깨진다). env 해석은 l2_env_floor()/
#   l2_env_defensive_route() 두 헬퍼로만.
# =============================================================================

.l2_root <- function() {
  for (p in c(Sys.getenv("CLAUDE_PROJECT_DIR", unset = ""),
              Sys.getenv("QM_ROOT", unset = ""), getwd())) {
    if (!nzchar(p)) next
    p <- gsub("\\\\", "/", p)          # R 문자열 안 Windows 백슬래시는 \U 로 즉사한다
    if (dir.exists(file.path(p, "02_Infrastructure"))) return(p)
  }
  stop("[l2_pool_admission] project root not found — CLAUDE_PROJECT_DIR/QM_ROOT 확인")
}

## ── 계약 본체는 **격리 환경**에 적재한다 ──────────────────────────────────────
##   defensive_score.R 은 자기 `%||%` 를 정의한다(NA 를 NULL 로 보지 않는 판본).
##   전역에 풀면 소비자의 `%||%` 를 덮어써 `grade %||% "ungraded"` 같은 표현의 의미가
##   조용히 바뀐다. regime_label_gate 어댑터가 같은 이유로 격리돼 있다.
.l2_ds_env <- new.env(parent = globalenv())
local({
  root <- .l2_root()
  p <- file.path(root, "02_Infrastructure/contracts/defensive_score.R")
  if (!file.exists(p)) stop("[l2_pool_admission] defensive_score.R 부재: ", p)
  sys.source(p, envir = .l2_ds_env)
  for (f in c("ds_pool_eligible", "ds_params", "ds_score"))
    if (!exists(f, envir = .l2_ds_env, inherits = FALSE))
      stop("[l2_pool_admission] defensive_score.R 에 ", f, " 없음 — 계약 파손")
})
ds_pool_eligible <- get("ds_pool_eligible", envir = .l2_ds_env)
ds_params        <- get("ds_params",        envir = .l2_ds_env)

`%|l|%` <- function(a, b) if (is.null(a) || length(a) == 0L ||
                             (length(a) == 1L && is.na(a))) b else a
.l2_get <- function(x, k) {
  ## 이름 있는 **원자 벡터**의 [[ 는 없는 키에 대해 throw 한다(list 만 NULL).
  if (is.null(x) || !is.list(x)) return(NULL)
  if (!(k %in% names(x))) return(NULL)
  x[[k]]
}
.l2_chr1 <- function(x) {
  v <- suppressWarnings(as.character(x)[1])
  if (length(v) != 1L || is.na(v) || !nzchar(v)) NA_character_ else v
}

#' env → 등급 floor ("B" 기본 / "A" / "OFF")
l2_env_floor <- function(default = "B")
  toupper(.l2_chr1(Sys.getenv("QVEST_L2_GRADE_FLOOR", default)) %|l|% default)

#' env → 방어형 병렬 경로 on/off (OFF 만 해제)
l2_env_defensive_route <- function()
  !identical(toupper(.l2_chr1(Sys.getenv("QVEST_L2_DEFENSIVE_ROUTE", "ON")) %|l|% "ON"), "OFF")

#' 카탈로그 레코드 → essence 등급 + 그 값이 어디서 왔는지
#' @return list(grade, source) — source ∈ {entry, meta_regrade, emit_grade, none}
l2_essence_grade <- function(rec) {
  eg <- .l2_chr1(.l2_get(rec, "essence_grade"))
  if (!is.na(eg)) return(list(grade = eg, source = "entry"))
  meta <- .l2_get(rec, "meta")
  mg <- .l2_chr1(.l2_get(meta, "essence_grade"))
  if (!is.na(mg)) return(list(grade = mg, source = "meta_regrade"))
  g <- .l2_chr1(.l2_get(rec, "grade"))
  if (!is.na(g) && !identical(g, "ungraded")) return(list(grade = g, source = "emit_grade"))
  list(grade = NA_character_, source = "none")
}

#' 카탈로그 레코드 1건의 풀 자격 판정.
#' @return list(eligible, route, code, reason, grade_used, grade_source, has_dscore)
l2_admit <- function(rec, floor = "B", defensive_route = TRUE, params = NULL) {
  eg <- l2_essence_grade(rec)
  ds <- .l2_get(rec, "defensive_score")
  if (!is.null(ds) && !is.list(ds)) ds <- NULL          # 스칼라/NA 잔재는 미산출로 본다
  r <- ds_pool_eligible(eg$grade, ds,
                        params = if (is.null(params)) ds_params() else params,
                        floor = floor, defensive_route = defensive_route)
  r$grade_used   <- eg$grade
  r$grade_source <- eg$source
  r$has_dscore   <- !is.null(ds)
  r
}

#' 카탈로그 modules 전체 → 편입 경로 + 제외 사유 집계.
#' @param mods named list — module_catalog.json$modules (simplifyVector=FALSE)
#' @param contract_ok 계약 floor 술어(기본 = fr_eligible ∧ backtested ∧ contract_pass).
#'   계약 floor 를 통과하지 못한 레코드는 `contract_floor` 사유로 따로 센다 — 등급/방어형
#'   판정과 섞지 않는다(다른 층의 거절이다).
#' @return list(routes, codes, grades, tally, n_admitted, n_defensive, n_excluded)
l2_admit_catalog <- function(mods, floor = "B", defensive_route = TRUE,
                             contract_ok = NULL, params = NULL) {
  if (is.null(contract_ok)) contract_ok <- function(e)
    isTRUE(.l2_get(e, "fr_eligible")) &&
    identical(.l2_chr1(.l2_get(e, "metric_type")), "backtested") &&
    isTRUE(.l2_get(.l2_get(e, "contract"), "contract_pass"))
  ids <- names(mods) %|l|% character(0)
  P <- if (is.null(params)) ds_params() else params
  routes <- setNames(rep(NA_character_, length(ids)), ids)
  codes  <- setNames(rep(NA_character_, length(ids)), ids)
  grades <- setNames(rep(NA_character_, length(ids)), ids)
  gsrc   <- setNames(rep(NA_character_, length(ids)), ids)
  for (id in ids) {
    rec <- mods[[id]]
    if (!isTRUE(contract_ok(rec))) { codes[[id]] <- "contract_floor"; next }
    a <- l2_admit(rec, floor = floor, defensive_route = defensive_route, params = P)
    codes[[id]]  <- a$code
    grades[[id]] <- a$grade_used
    gsrc[[id]]   <- a$grade_source
    if (isTRUE(a$eligible)) routes[[id]] <- a$route
  }
  adm <- !is.na(routes)
  list(routes = routes, codes = codes, grades = grades, grade_sources = gsrc,
       tally = table(codes, useNA = "ifany"),
       n_admitted  = sum(adm),
       n_grade_floor = sum(routes[adm] == "grade_floor"),
       n_defensive = sum(routes[adm] == "defensive_specialist"),
       n_excluded  = sum(!adm & codes != "contract_floor"),
       n_contract_excluded = sum(codes == "contract_floor", na.rm = TRUE))
}

if (identical(environment(), globalenv()))
  cat("[l2_pool_admission] Loaded — l2_admit() / l2_admit_catalog() (ds_pool_eligible 경유)\n")
