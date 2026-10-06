#!/usr/bin/env Rscript
#==============================================================================
# register_measured_module.R — 측정 산출물 → module_catalog **등재 이음매** (2026-09-07)
#
# 무엇이 없었나: v10 생산 레인(run_paper_replication → 충실구현·결합·강화 셀)은
#   `authoritative_remeasure.json` 과 `bt_result.rds` 를 남기고 끝난다. `register_module()`
#   을 **한 번도 부르지 않는다**. 그래서 631 런(essence B 54 · defensive TRUE 407)이
#   module_catalog 에 들어갈 경로가 없었고, 카탈로그는 2026-08-24 이후 정지 상태였다.
#   ⇒ "1계층이 B 이상을 못 만든다" 가 아니라 **만든 것이 풀로 못 갔다**.
#
# 이 파일의 경계 — 재측정하지 않는다.
#   입력은 이미 계약을 통과해 디스크에 있는 산출물뿐이고(auth JSON · 계약 CSV ·
#   메모리 안 sim), 하는 일은 그것을 카탈로그 스키마로 옮기는 것뿐이다.
#   새 백테스트를 띄우는 코드 경로가 이 파일에 없다.
#
# ── 등재 자격 = **소비자의 술어 그 자체** ────────────────────────────────────
#   무엇을 등재할지는 `ds_pool_eligible()`(계약) 이 정한다 — `l2_admit()`/
#   `build_module_performance.R` 이 풀을 조립할 때 쓰는 바로 그 함수다.
#   여기서 사본을 들면 "등재된 것"과 "풀이 받아들이는 것"이 갈린다(2026-09-04~07 에
#   풀 조립부가 `.defensive_ok()` 사본을 들고 계약 함수를 아무도 안 부르던 상태의 재발).
#   ⇒ 자격 = essence 등급 ∈ {A,B}(route=grade_floor) **또는** 방어형(route=
#      defensive_specialist). 그 외는 등재하지 않는다(카탈로그 폭주 방지).
#   ★floor 는 여기서 **고정 "B"** 다 — env(QVEST_L2_GRADE_FLOOR)로 풀을 좁히는 것은
#     소비 시점 판단이고, 기록(카탈로그)까지 좁히면 env 를 되돌려도 그 사이 산출물이
#     영영 없다. 기록은 넓게, 소비는 좁게.
#
# ── 조용한 실패 금지 ─────────────────────────────────────────────────────────
#   계약 floor(contract_pass ∧ metric_type=backtested ∧ frozen ∧ provenance 4종)를
#   **우회하지 않는다**. 못 넣으면 사유를 저널에 남기고 넘어간다. 사유 코드는 부재와
#   거짓과 판정불가를 가른다(dscore_absent ≠ not_defensive ≠ dscore_not_ok).
#
# 사용:
#   source(".../contracts/register_measured_module.R")
#   rmm_register_measured(out_dir, sim_result = sim_grade, origin_mode = "replication")
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })

.RMM_ENV <- new.env(parent = globalenv())   # 계약 3종을 **격리 적재** — 호출자의 `%||%` 를 덮지 않는다

.rmm_root <- function() {
  for (p in c(Sys.getenv("CLAUDE_PROJECT_DIR", unset = ""),
              Sys.getenv("QM_ROOT", unset = ""), getwd())) {
    if (!nzchar(p)) next
    p <- gsub("\\\\", "/", p)      # R 문자열 안 Windows 백슬래시는 \U 로 즉사한다
    if (dir.exists(file.path(p, "02_Infrastructure")) &&
        dir.exists(file.path(p, "06_Registry"))) return(sub("/+$", "", p))
  }
  stop("[rmm] project root not found — CLAUDE_PROJECT_DIR/QM_ROOT 확인")
}

local({
  root <- .rmm_root()
  for (rel in c("02_Infrastructure/regime/l2_pool_admission.R",
                "02_Infrastructure/contracts/register_module.R",
                "02_Infrastructure/ops/shared_registry_io.R")) {
    p <- file.path(root, rel)
    if (!file.exists(p)) stop("[rmm] 계약 파일 부재: ", p)
    suppressMessages(sys.source(p, envir = .RMM_ENV))
  }
  for (f in c("ds_pool_eligible", "ds_params", "l2_essence_grade",
              "register_module", "sr_with_lock"))
    if (!exists(f, envir = .RMM_ENV, inherits = FALSE))
      stop("[rmm] 계약 함수 부재: ", f)
})

## ── 스칼라 안전 접근자 ────────────────────────────────────────────────────────
##   ① 이름 있는 **원자 벡터**의 [[ 는 없는 키에 throw 한다(list 만 NULL 을 준다).
##   ② sprintf 는 인자 하나가 길이 0이면 문자열 **전체**를 없앤다 — 스칼라화를 강제한다.
.rmm_get <- function(x, k) {
  if (is.null(x) || !is.list(x) || !(k %in% names(x))) return(NULL)
  x[[k]]
}
.rmm_c1 <- function(x, alt = NA_character_) {
  v <- suppressWarnings(as.character(x)[1])
  if (length(v) != 1L || is.na(v) || !nzchar(v)) alt else v
}
.rmm_n1 <- function(x) { v <- suppressWarnings(as.numeric(x)[1]); if (length(v) == 1L) v else NA_real_ }
.rmm_fmt <- function(x, fmt = "%.2f", alt = "NA") {
  v <- .rmm_n1(x); if (is.finite(v)) sprintf(fmt, v) else alt
}
.rmm_rel <- function(path, root = .rmm_root()) {
  p <- gsub("\\\\", "/", as.character(path)[1])
  r <- gsub("\\\\", "/", root)
  if (startsWith(p, paste0(r, "/"))) substring(p, nchar(r) + 2L) else p
}

#' 저널 1줄 (JSONL). 싱크는 QVEST_RP_JLOG 로 돌린다 — 검사가 운영 로그를 오염시키지 않게.
rmm_journal <- function(event, ...) {
  p <- Sys.getenv("QVEST_RP_JLOG", file.path(.rmm_root(), ".cache/reinforce_auto_log.jsonl"))
  rec <- c(list(ts = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), event = event,
                src = "register_measured_module"), list(...))
  tryCatch({
    dir.create(dirname(p), recursive = TRUE, showWarnings = FALSE)
    cat(toJSON(rec, auto_unbox = TRUE, null = "null"), "\n", sep = "", file = p, append = TRUE)
  }, error = function(e) NULL)
  cat(sprintf("[rmm] %s\n", event))
  invisible(TRUE)
}

#' out_dir 의 authoritative_remeasure.json 을 읽는다 (simplifyVector=FALSE — 구조 고정).
rmm_read_auth <- function(out_dir) {
  p <- file.path(out_dir, "authoritative_remeasure.json")
  if (!file.exists(p)) return(NULL)
  tryCatch(fromJSON(p, simplifyVector = FALSE), error = function(e) NULL)
}

#' 권위 산출물 1건의 **풀 자격 판정** — 판정 자체는 계약 ds_pool_eligible() 이 낸다.
#' @return list(eligible, route, code, reason, grade, has_dscore,
#'              n_down, down_t, down_excess, deep_excess, ds_status)   ★convex 폐기 2026-09-07
rmm_admission <- function(auth, floor = "B", defensive_route = TRUE, params = NULL) {
  eg <- .rmm_c1(.rmm_get(auth, "essence_grade"))
  if (is.na(eg)) {   # 카탈로그 레코드 형태로 들어온 경우도 같은 축으로 읽는다
    g <- .RMM_ENV$l2_essence_grade(auth); eg <- .rmm_c1(g$grade)
  }
  ds <- .rmm_get(auth, "defensive_score")
  if (!is.null(ds) && !is.list(ds)) ds <- NULL          # 스칼라/NA 잔재 = 미산출
  r <- .RMM_ENV$ds_pool_eligible(eg, ds,
         params = if (is.null(params)) .RMM_ENV$ds_params(.rmm_root()) else params,
         floor = floor, defensive_route = defensive_route)
  dn <- .rmm_get(ds, "down"); dp <- .rmm_get(ds, "deep")
  r$grade       <- eg
  r$has_dscore  <- !is.null(ds)
  r$ds_status   <- .rmm_c1(.rmm_get(ds, "status"))
  r$n_down      <- .rmm_n1(.rmm_get(dn, "n"))
  r$down_t      <- .rmm_n1(.rmm_get(dn, "t"))
  r$down_excess <- .rmm_n1(.rmm_get(dn, "excess"))
  r$deep_excess <- .rmm_n1(.rmm_get(dp, "excess"))
  r
}

#' 판정 1줄 — 텔레그램/저널 공용. 길이 0 인자로 문장이 통째로 사라지지 않게 전부 스칼라화.
rmm_gate_note <- function(adm) {
  if (!isTRUE(adm$eligible))
    return(sprintf("풀 미편입(%s) — %s", .rmm_c1(adm$code, "unknown"), .rmm_c1(adm$reason, "사유 미기록")))
  if (identical(.rmm_c1(adm$route), "defensive_specialist"))
    ## ★"볼록" 문구 제거 (도훈 결정 2026-09-07) — 그 플래그는 무신호에서 더 잘 켜졌고(52% vs 32%)
    ##   실제 한계반응은 전부 오목이었다. 심층 초과는 표본(심도월 10개)이 얇아 참고값으로만 적는다.
    return(sprintf("방어형 등재 — 하락월 %s개 초과 %s%%/월 (t %s) · 심층 %s%%/월(n 얇음)",
                   .rmm_fmt(adm$n_down, "%.0f"),
                   .rmm_fmt(100 * .rmm_n1(adm$down_excess), "%+.2f"),
                   .rmm_fmt(adm$down_t, "%.2f"),
                   .rmm_fmt(100 * .rmm_n1(adm$deep_excess), "%+.2f")))
  sprintf("등급 %s — 등급 floor 통과 등재", .rmm_c1(adm$grade, "NA"))
}

#' sim_result 정규화 — DAILY_NAV_DT 에 Strategy_Ret 이 없으면 strategy_xts 에서 붙인다.
#'   ★replication_harness 는 DAILY_NAV_DT 를 (Date, NAV, NAV_gross) 로 낸다. 소비자
#'     (build_module_performance:225)와 계약 검증(.validate_module_sim)은 Strategy_Ret 을
#'     요구한다 — 같은 수치의 **모양 어댑터**이지 재측정이 아니다.
rmm_normalize_sim <- function(sim) {
  if (is.null(sim) || is.null(sim$DAILY_NAV_DT)) return(sim)
  d <- as.data.table(sim$DAILY_NAV_DT)
  if ("Strategy_Ret" %in% names(d)) return(sim)
  if (!is.null(sim$strategy_xts) && requireNamespace("xts", quietly = TRUE) &&
      requireNamespace("zoo", quietly = TRUE)) {
    sx <- data.table(Date = as.Date(zoo::index(sim$strategy_xts)),
                     Strategy_Ret = as.numeric(sim$strategy_xts[, 1]))
    d[, Date := as.Date(Date)]
    d <- merge(d, sx, by = "Date", all.x = TRUE)
  } else if ("NAV" %in% names(d)) {
    d[, Date := as.Date(Date)]
    setorder(d, Date)
    d[, Strategy_Ret := c(NAV[1] - 1, diff(NAV) / head(NAV, -1))]
  } else return(sim)
  sim$DAILY_NAV_DT <- d
  sim
}

#' 계약 CSV 산출물 → 소비 가능한 최소 sim_result (새 백테 없음).
#'   03_period_returns.csv(date, ret_net) + 05_benchmark_returns.csv(date, benchmark_ret)
#'   = save_bt_result 가 이미 얼려 둔 계약 산출물. 재시뮬레이션·리밸런싱 없음.
#' @return list(sim, code) — sim NULL 이면 code 가 사유
rmm_sim_from_artifacts <- function(out_dir) {
  fr <- file.path(out_dir, "03_period_returns.csv")
  fb <- file.path(out_dir, "05_benchmark_returns.csv")
  if (!file.exists(fr)) return(list(sim = NULL, code = "no_period_returns"))
  if (!file.exists(fb)) return(list(sim = NULL, code = "no_benchmark_returns"))
  if (!requireNamespace("xts", quietly = TRUE)) return(list(sim = NULL, code = "no_xts_pkg"))
  pr <- tryCatch(fread(fr, showProgress = FALSE), error = function(e) NULL)
  br <- tryCatch(fread(fb, showProgress = FALSE), error = function(e) NULL)
  if (is.null(pr) || is.null(br) || !nrow(pr) || !nrow(br))
    return(list(sim = NULL, code = "series_unreadable"))
  if (!all(c("date", "ret_net") %in% names(pr)) ||
      !all(c("date", "benchmark_ret") %in% names(br)))
    return(list(sim = NULL, code = "series_schema"))
  d <- pr[is.finite(ret_net), .(Date = as.Date(date), Strategy_Ret = as.numeric(ret_net))]
  setorder(d, Date)
  if (nrow(d) < 60L) return(list(sim = NULL, code = "series_too_short"))
  d[, NAV := cumprod(1 + Strategy_Ret)]
  b <- br[is.finite(benchmark_ret), .(Date = as.Date(date), r = as.numeric(benchmark_ret))]
  setorder(b, Date)
  if (!nrow(b)) return(list(sim = NULL, code = "benchmark_empty"))
  list(sim = list(DAILY_NAV_DT = d[, .(Date, NAV, Strategy_Ret)],
                  strategy_xts = xts::xts(d$Strategy_Ret, order.by = d$Date),
                  bm_xts = xts::xts(b$r, order.by = b$Date),
                  provenance = list(built_from = "contract_csv", out_dir = .rmm_rel(out_dir),
                                    note = "계약 CSV 재조립 — 새 측정 없음")),
       code = "ok")
}

#' 산출물 디렉터리의 00_manifest.json 에서 provenance 를 **재도출**한다(진술 아님).
.rmm_manifest <- function(out_dir) {
  p <- file.path(out_dir, "00_manifest.json")
  if (!file.exists(p)) return(list())
  tryCatch(fromJSON(p, simplifyVector = FALSE), error = function(e) list())
}

#' 측정이 끝난 산출물 1건을 module_catalog 에 등재한다.
#' @param out_dir authoritative_remeasure.json 이 있는 산출물 디렉터리
#' @param sim_result 메모리 안 sim(있으면 그대로). NULL 이면 계약 CSV 로 재조립.
#' @param dry_run TRUE 면 판정·재료 확인까지만 하고 쓰지 않는다(소급 스크립트 기본값).
#' @return list(registered, code, reason, strategy_id, route, grade, fr_eligible)
rmm_register_measured <- function(out_dir, sim_result = NULL, auth = NULL,
                                  origin_mode = "replication", role = NA_character_,
                                  meta = list(), dry_run = FALSE, floor = "B",
                                  catalog_path = NULL, quarantine_path = NULL,
                                  journal = TRUE, lock_wait_s = 60, role_rep_id = NULL) {
  .out <- function(registered, code, reason, adm = NULL, sid = NA_character_, fr = NA) {
    if (isTRUE(journal))
      ## 사건 이름이 셋인 이유: 자격 미달(skipped)·재료/계약 결손(blocked)·모의(dry_run)는
      ## 서로 다른 사실이다. 한 이름으로 합치면 "배선이 안 됐다"와 "자격이 없다"가 같은 줄이 된다.
      rmm_journal(if (isTRUE(registered)) "module_registered" else
                  if (identical(.rmm_c1(code, ""), "dry_run")) "module_register_dry_run" else
                  if (.rmm_c1(code, "") %in%
                      c("not_defensive", "dscore_absent", "dscore_not_ok", "route_off"))
                    "module_register_skipped" else "module_register_blocked",
                  code = .rmm_c1(code, "unknown"), reason = substr(.rmm_c1(reason, ""), 1, 300),
                  out_dir = .rmm_rel(out_dir), strategy_id = .rmm_c1(sid, ""),
                  route = if (is.null(adm)) "" else .rmm_c1(adm$route, ""),
                  grade = if (is.null(adm)) "" else .rmm_c1(adm$grade, ""),
                  fr_eligible = if (is.na(fr)) NULL else isTRUE(fr),
                  dry_run = isTRUE(dry_run), origin_mode = .rmm_c1(origin_mode, ""))
    invisible(list(registered = isTRUE(registered), code = .rmm_c1(code, "unknown"),
                   reason = .rmm_c1(reason, ""), strategy_id = .rmm_c1(sid, ""),
                   route = if (is.null(adm)) NA_character_ else .rmm_c1(adm$route),
                   grade = if (is.null(adm)) NA_character_ else .rmm_c1(adm$grade),
                   admission = adm, fr_eligible = fr, dry_run = isTRUE(dry_run)))
  }
  out_dir <- gsub("\\\\", "/", as.character(out_dir)[1])
  if (is.null(auth)) auth <- rmm_read_auth(out_dir)
  if (is.null(auth))
    return(.out(FALSE, "auth_absent", "authoritative_remeasure.json 부재 — 계약 미경유 = 미측정"))

  ## ① 풀 자격 (등재할 값어치가 있는가) — 계약 술어 경유
  adm <- rmm_admission(auth, floor = floor, defensive_route = TRUE)
  ## ①' 역할 대표 경로(도훈 2026-10-06 — 2계층 풀 = 역할별 대표). 호출자 진술이 아니라 **레지스트리를 다시 읽어** 확인한다:
  ##    06_Registry/strategy_roles.json entries[role_rep_id]$pool_rep_roles 가 비어 있지 않을 때만. 계약 floor ②③ 는 그대로 거친다.
  if (!isTRUE(adm$eligible) && !is.null(role_rep_id)) {
    rr <- tryCatch(fromJSON(file.path(.rmm_root(), "06_Registry/strategy_roles.json"), simplifyVector = FALSE)$entries[[as.character(role_rep_id)[1]]],
                   error = function(e) NULL)
    roles <- unlist(.rmm_get(rr, "pool_rep_roles"))
    if (length(roles)) {
      adm$eligible <- TRUE; adm$route <- "role_rep"; adm$code <- "role_rep"
      adm$reason <- sprintf("역할 대표(%s) — strategy_roles.json · essence %s", paste(roles, collapse = ","), .rmm_c1(adm$grade, "NA"))
      meta$role_pool_rep <- as.list(roles)
    }
  }
  if (!isTRUE(adm$eligible))
    return(.out(FALSE, adm$code, adm$reason, adm))

  ## ② 계약 floor — 우회하지 않는다. 못 넣으면 사유를 남긴다.
  st  <- .rmm_c1(.rmm_get(auth, "status"))
  mt  <- .rmm_c1(.rmm_get(auth, "metric_type"))
  if (!identical(mt, "backtested"))
    return(.out(FALSE, "contract_floor:metric_type",
                sprintf("metric_type=%s (backtested 아님) — 계약 floor 미충족", .rmm_c1(mt, "NA")), adm))
  if (!identical(st, "OK"))
    return(.out(FALSE, "contract_floor:status",
                sprintf("auth status=%s — 무결성 FAIL 판을 승격하지 않는다", .rmm_c1(st, "NA")), adm))

  sid <- .rmm_c1(.rmm_get(auth, "strategy_id"))
  if (is.na(sid)) return(.out(FALSE, "no_strategy_id", "auth 에 strategy_id 없음", adm))
  rid <- .rmm_c1(.rmm_get(auth, "run_id"), sid)
  mf  <- .rmm_manifest(out_dir)
  bv  <- .rmm_c1(.rmm_get(mf, "code_version"), "replication_lane_unlabeled")
  cmv <- .rmm_c1(.rmm_get(mf, "cost_model_version"), "replication_15bps_weight_delta")
  btp <- .rmm_c1(.rmm_get(auth, "bt_result_path"), file.path(out_dir, "bt_result.rds"))

  ## ③ 재료 — 메모리 sim 우선, 없으면 계약 CSV 재조립(**새 백테 금지**)
  sim <- rmm_normalize_sim(sim_result)
  if (is.null(sim)) {
    fb <- rmm_sim_from_artifacts(out_dir)
    if (is.null(fb$sim))
      return(.out(FALSE, paste0("sim_unavailable:", fb$code),
                  "메모리 sim 도 계약 CSV 도 없어 등재 재료를 만들 수 없다(새 백테는 금지)", adm))
    sim <- fb$sim
  }
  d <- tryCatch(as.data.table(sim$DAILY_NAV_DT), error = function(e) NULL)
  if (is.null(d) || !all(c("Date", "Strategy_Ret") %in% names(d)) || is.null(sim$bm_xts))
    return(.out(FALSE, "sim_schema", "DAILY_NAV_DT(Date,Strategy_Ret) + bm_xts 스키마 미충족", adm))

  if (isTRUE(dry_run))
    return(.out(FALSE, "dry_run", rmm_gate_note(adm), adm, sid, NA))

  ## ④ 등재 — 병렬 셀이 동시에 read-modify-write 하지 않도록 원장 뮤텍스로 직렬화한다.
  ##    (rf_cell_worker 가 원장을 안 만지는 이유와 같은 사유 — 여기는 만져야 하므로 잠근다.)
  ## 원장 경로: 인자 > env > 정본. env 레버가 있어야 검사가 **운영 카탈로그를 빌리지 않고**
  ## 실제 등재 경로를 끝까지 구동할 수 있다(QVEST_RP_JLOG 와 같은 이유·같은 형태).
  cp <- if (!is.null(catalog_path)) catalog_path else
        .rmm_c1(Sys.getenv("QVEST_MODULE_CATALOG", ""), .RMM_ENV$MODULE_CATALOG_PATH)
  qp <- if (!is.null(quarantine_path)) quarantine_path else
        .rmm_c1(Sys.getenv("QVEST_MODULE_QUARANTINE", ""),
                if (identical(cp, .RMM_ENV$MODULE_CATALOG_PATH)) .RMM_ENV$MODULE_QUARANTINE_PATH
                else file.path(dirname(cp), "module_quarantine.json"))
  meta$registered_by <- "register_measured_module"
  meta$admission_route <- .rmm_c1(adm$route, "")
  meta$admission_reason <- substr(.rmm_c1(adm$reason, ""), 1, 400)
  meta$artifacts_dir <- .rmm_rel(out_dir)
  meta$essence_grade <- .rmm_c1(adm$grade)     # 구세대 소비자(meta 축)도 같은 값을 본다
  r <- tryCatch(
    .RMM_ENV$sr_with_lock(cp, {
      .RMM_ENV$register_module(
        sim, sid,
        grade = .rmm_c1(adm$grade, "ungraded"),
        grade_basis = "essence_score(authoritative_remeasure.json)",
        essence_grade = .rmm_c1(adm$grade),
        ## 산출물이 디스크에 있으면 **등재기가 직접 읽게** 둔다 — 그래야 카탈로그의
        ## defensive_score$source 가 "authoritative_remeasure"(출처)로 남는다.
        ## 넘겨 주면 source="caller" 가 되어 값의 출처가 한 겹 흐려진다.
        defensive_score = if (file.exists(file.path(out_dir, "authoritative_remeasure.json")))
                            NULL else .rmm_get(auth, "defensive_score"),
        auth_remeasure_path = file.path(out_dir, "authoritative_remeasure.json"),
        origin_mode = origin_mode, role = role, meta = meta,
        catalog_path = cp, quarantine_path = qp,
        metric_type = "backtested", contract_pass = TRUE, frozen = TRUE,
        source_contract_id = rid, build_version = bv, cost_model_version = cmv,
        bt_result_path = .rmm_rel(btp))
    }, wait_s = lock_wait_s),
    error = function(e) e)
  if (inherits(r, "error"))
    return(.out(FALSE, "register_error", conditionMessage(r), adm, sid, NA))
  .out(isTRUE(r$fr_eligible), if (isTRUE(r$fr_eligible)) "registered" else "quarantined",
       if (isTRUE(r$fr_eligible)) rmm_gate_note(adm) else .rmm_c1(r$reason, "계약 floor 미충족"),
       adm, sid, isTRUE(r$fr_eligible))
}

## ★이 파일은 `%||%` 를 **정의하지 않는다** — 호출자(run_paper_replication 등)의 판본을
##   덮으면 `grade %||% "ungraded"` 류 표현의 의미가 조용히 바뀐다(이 저장소의 반복 결함).
if (identical(environment(), globalenv()))
  cat("[register_measured_module.R] Loaded — rmm_register_measured(out_dir, sim_result, ...)\n")
