#!/usr/bin/env Rscript
#==============================================================================
# rf_factor_backfill_tick.R — 이력 미달 팩터 **무인 점진 백필** (2026-09-01 도훈 지시)
#
# 왜: 생산자가 새로 생긴 팩터(technical 12종)와 무인 등록된 논문 신호는 **당월만** 채워진다.
#   daily_refresh [6a] 는 당월 1파일만 빌드하기 때문이다. 이력이 없으면 IC 가 안 서고,
#   IC 가 없으면 B1 후보 풀에 못 들어간다 — 등재만 되고 아무도 못 쓰는 상태가 그대로 재현된다.
#
# ★전 구간 재빌드(build_factor_db_monthly(force=TRUE), 수시간)를 스케줄에 넣는 것이 아니다.
#   빌더에 이미 있는 **팩터 단위 scoped backfill**(backfill_custom_factor)을 쓴다.
#   예산제라 하룻밤에 안 끝나면 **다음 밤이 이어받는다** — 진행 상태가 "이력 개월수" 라는
#   실물에서 파생되므로 별도 커서가 필요 없고, 중단돼도 다음 실행이 자연히 재개한다.
#
# 호출: daily_refresh.sh [6c] (매일 밤). 수동 호출도 무해(멱등).
# 스위치: QVEST_FDB_NO_BACKFILL=1 (정지) · QVEST_FDB_BACKFILL_BUDGET_MIN (기본 60분)
#
# ⚠fdb_daily 자동 재빌드 게이트(QVEST_FDB_DAILY_AUTOREBUILD=0)와 혼동 금지 —
#   그건 **전 파일 삭제 후 1990~ 전체 재구축**이고 여기는 팩터 단위 증분이다.
#==============================================================================
suppressMessages({ library(data.table); library(jsonlite); library(arrow) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT); Sys.setenv(QM_ROOT = ROOT)
FDB   <- file.path(ROOT, ".cache/factor_db")
LOG_P <- file.path(ROOT, ".cache/reinforce_auto_log.jsonl")

jlog <- function(event, ...) {
  rec <- c(list(ts = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), event = event, src = "fdb_backfill"), list(...))
  cat(toJSON(rec, auto_unbox = TRUE, null = "null"), "\n", sep = "", file = LOG_P, append = TRUE)
  cat(sprintf("[fdb_bf] %s %s\n", event,
              paste(names(rec)[-(1:3)], unlist(lapply(rec[-(1:3)], function(z) substr(paste(z, collapse=","), 1, 80))),
                    sep = "=", collapse = " ")))
}

#' 이력 미달 팩터 목록 — (id, module, have_months) · 커버리지 적은 순
#' ★커버리지 대리 = factor_ic_monthly 의 팩터별 개월 수. 443개 parquet 를 전수 스캔하지 않는다
#'   (같은 체인이 매일 갱신하므로 이 파일이 곧 그 달들의 그림자다).
rf_backfill_candidates <- function(root = ROOT, min_ratio = 0.5) {
  reg <- fromJSON(file.path(FDB, "factor_registry.json"), simplifyVector = FALSE)
  n_months <- length(list.files(FDB, pattern = "^factor_db_\\d{6}\\.parquet$"))
  if (!n_months) return(NULL)
  ic_p <- file.path(FDB, "factor_ic_monthly.parquet")
  have <- if (file.exists(ic_p)) {
    IC <- as.data.table(arrow::read_parquet(ic_p, col_select = "Factor_Name"))
    IC[, .N, by = Factor_Name]
  } else data.table(Factor_Name = character(0), N = integer(0))
  setnames(have, c("id", "have"))

  # ── 계열 → compute 모듈. scoped backfill 은 모듈만 갈아끼우면 되므로 계열 전반에 쓴다.
  #   ★technical 만이 아니다: 2026-09-01 실측에서 C15(구 생산자로 만든 낡은 parquet)와
  #   M12(빌더 슬라이스 창이 팩터 정의보다 좁아 영구 0행)도 같은 경로로 채워야 했다.
  CAT2MOD <- c(value="value", momentum="momentum", quality="quality", defense="defense",
               size="size", consensus="consensus", liquidity="liquidity", accrual="accrual",
               risk="risk", regime="regime", crowding="crowding", growth="growth",
               investor_flow="investor", technical="technical")
  cust <- tryCatch(fromJSON(file.path(ROOT, "02_Infrastructure/factor_db/custom_factors.json"),
                            simplifyVector = FALSE), error = function(e) list())
  cust_ids <- vapply(cust %||% list(), function(x) as.character(x$id %||% ""), character(1))

  # ── 빼야 하는 세 부류 (백필해도 소용없거나 나오면 안 되는 것) ────────────────
  #   ① time_series — 시장수준이라 횡단면 Coverage 가 FALSE 인 게 정상(빌더 규칙과 정합).
  #      안 빼면 매일 밤 443개월을 헛돌린다.
  #   ② deprecated — 승계돼서 안 나오는 게 맞다(C14→M26 · C17→M28).
  #   ③ expected_absent 선언분 — 사유·근거와 함께 "결측이 정상" 으로 선언된 것.
  ax <- tryCatch(fromJSON(file.path(ROOT, "06_Registry/factor_panel_axis.json"),
                          simplifyVector = FALSE)$factors, error = function(e) list())
  ts_ids <- names(Filter(function(v) identical(v$panel_axis, "time_series"), ax %||% list()))
  dep_ids <- names(Filter(function(e) identical(as.character((e$lifecycle %||% list())$status %||% ""),
                                                "deprecated"), reg))
  ea <- tryCatch(fromJSON(file.path(ROOT, "02_Infrastructure/factor_db/emission_expected_absent.json"),
                          simplifyVector = FALSE)$expected_absent, error = function(e) list())
  dec_ids <- vapply(ea %||% list(), function(e) as.character(e$factor %||% ""), character(1))

  ids <- setdiff(names(reg), c(ts_ids, dep_ids, dec_ids))
  mod <- vapply(ids, function(f) {
    if (f %in% cust_ids) return("custom")
    m <- CAT2MOD[as.character(reg[[f]]$category %||% "")]
    if (is.na(m)) NA_character_ else unname(m) }, character(1))
  D <- data.table(id = ids, module = mod)[!is.na(module)]
  if (!nrow(D)) return(NULL)
  D <- merge(D, have, by = "id", all.x = TRUE)
  D[is.na(have), have := 0L]
  D <- D[have < as.integer(min_ratio * n_months)]

  # ── ★이득 없는 재시도의 출구 (무상태 — 로그에서 파생한다) ────────────────────
  #   커버리지가 원래 짧은 팩터(원천 이력이 늦게 시작하는 펀더멘털 등)는 몇 번을 돌려도
  #   개월 수가 안 는다. 출구가 없으면 매일 밤 443개월을 헛돌면서 로그는 "정상"으로 보인다 —
  #   무한 재시도는 침묵과 같다(저장소 반복 교훈: 재개 장치에는 출구가 있어야 한다).
  #   ★별도 커서 파일을 만들지 않는다: 직전 backfill_done 의 have_before 와 **지금 have** 가
  #     같으면 그 시도가 아무것도 못 늘린 것이다. 상태는 로그와 실물에서 나온다.
  lg <- file.path(root, ".cache/reinforce_auto_log.jsonl")
  if (file.exists(lg) && nrow(D)) {
    prev <- new.env(parent = emptyenv())
    for (ln in tail(readLines(lg, warn = FALSE), 20000L)) {
      o <- tryCatch(fromJSON(ln, simplifyVector = TRUE), error = function(e) NULL)
      if (!is.null(o) && identical(o$event, "backfill_done") && !is.null(o$id))
        assign(as.character(o$id), suppressWarnings(as.integer(o$have_before %||% NA)), envir = prev)
    }
    D[, .prev := vapply(id, function(k) if (exists(k, envir = prev, inherits = FALSE))
        get(k, envir = prev) else NA_integer_, integer(1))]
    .stuck <- D[is.finite(.prev) & .prev == have, id]
    if (length(.stuck)) {
      cat(sprintf("[fdb_bf] 이득 없는 재시도 제외 %d종: %s
",
                  length(.stuck), paste(head(.stuck, 8), collapse = ",")))
      D <- D[!(id %in% .stuck)]
    }
    if (nrow(D)) D[, .prev := NULL]
  }

  if (!nrow(D)) return(NULL)
  setorderv(D, "have", 1L)
  D[, n_months_total := n_months][]
}

#' 축 사이드카가 소비면과 어긋났는가 — ★술어는 **소비자의 상태**여야 한다.
#'   구판은 "이번 tick 이 백필을 했는가"(length(done))로 갱신을 걸었다. 그런데 자동등록 레인은
#'   자기가 직접 backfill+IC 를 돌리므로 이 tick 의 done 에 절대 들어오지 않는다. 그래서
#'   2026-09-17 등록분이 사이드카에 20일간 빠져 있었다(registry 370 vs 사이드카 369).
#'   판정 축을 "registry 에 있는데 사이드카에 없는 id" 로 옮긴다 — 누가 채웠든 걸린다.
#'   ★mtime 비교를 쓰지 않는 이유: 내용이 안 변해도 재생성이 mtime 을 밀어 상시 초록이 된다.
rf_panel_axis_stale <- function(root = ROOT) {
  reg_p <- file.path(root, ".cache/factor_db/factor_registry.json")
  ax_p  <- file.path(root, "06_Registry/factor_panel_axis.json")
  if (!file.exists(reg_p)) return(list(stale = FALSE, missing = character(0), reason = "registry 부재"))
  if (!file.exists(ax_p))  return(list(stale = TRUE,  missing = character(0), reason = "사이드카 부재"))
  reg <- tryCatch(fromJSON(reg_p, simplifyVector = FALSE), error = function(e) NULL)
  ax  <- tryCatch(fromJSON(ax_p,  simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(reg) || is.null(ax)) return(list(stale = TRUE, missing = character(0), reason = "판독 불가"))
  reg_ids <- names(reg[["factors"]] %||% reg)
  ax_ids  <- names(ax[["factors"]]  %||% ax)
  miss <- setdiff(reg_ids, ax_ids)
  list(stale = length(miss) > 0L, missing = miss,
       reason = sprintf("registry %d종 · 사이드카 %d종 · 미등재 %d",
                        length(reg_ids), length(ax_ids), length(miss)))
}

#' 축 사이드카 재생성 (멱등)
#' ★인터프리터 순서가 저장소 관례(QVEST_PY 우선)와 **반대**다 — 의도적이다.
#'   classify_panel_axis.py 는 pandas 를 쓰는데 QVEST_PY(시스템 Python 3.12)에는 pandas 가 없다
#'   (openpyxl 은 있어서 다른 호출부는 멀쩡하다). 그래서 venv 를 먼저 본다.
#' ★system2 는 종료코드로 **예외를 던지지 않는다**. tryCatch(error=) 만 걸어두면 스크립트가
#'   status 1 로 죽어도 조용히 지나간다 — 실제로 2026-09-01 이후 이 갱신은 낡은 게 아니라
#'   줄곧 죽어 있었고 아무도 몰랐다. attr(out,"status") 를 반드시 본다.
rf_panel_axis_py <- function(root = ROOT) {
  cands <- c(file.path(root, ".venv_qvest_ml/Scripts/python.exe"), Sys.getenv("QVEST_PY", ""))
  cands <- cands[nzchar(cands) & file.exists(cands)]
  if (!length(cands)) "" else cands[1]
}
rf_panel_axis_refresh <- function(why, root = ROOT) {
  py <- rf_panel_axis_py(root)
  if (!nzchar(py)) { jlog("panel_axis_failed", why = why, err = "python 실행경로 미발견(venv/QVEST_PY)"); return(invisible(FALSE)) }
  res <- tryCatch({
    out <- system2(py, c(shQuote(file.path(root, "02_Infrastructure/factor_db/classify_panel_axis.py")), "--quiet"),
                   wait = TRUE, stdout = TRUE, stderr = TRUE)
    list(status = as.integer(attr(out, "status") %||% 0L), tail = paste(utils::tail(out, 2), collapse = " | "))
  }, error = function(e) list(status = -1L, tail = conditionMessage(e)))
  st <- rf_panel_axis_stale(root)
  if (!identical(res$status, 0L) || length(st$missing)) {
    jlog("panel_axis_failed", why = why, status = res$status, err = substr(res$tail, 1, 200),
         still_missing = length(st$missing), after = st$reason)
    return(invisible(FALSE))
  }
  jlog("panel_axis_refreshed", why = why, after = st$reason, py = basename(dirname(dirname(py))))
  invisible(TRUE)
}

main <- function() {
  if (nzchar(Sys.getenv("QVEST_FDB_NO_BACKFILL", ""))) { jlog("halt_kill_switch"); return(0L) }
  budget <- suppressWarnings(as.numeric(Sys.getenv("QVEST_FDB_BACKFILL_BUDGET_MIN", "60")))
  if (!is.finite(budget) || budget <= 0) budget <- 60

  CAND <- tryCatch(rf_backfill_candidates(), error = function(e) {
    jlog("candidates_failed", err = conditionMessage(e)); NULL })
  # ★사이드카 신선도는 백필 유무와 **독립**이다 — 조기 반환 앞에서 본다.
  #   (구판은 이 return 뒤에 있어서, 백필할 게 없는 밤에는 영영 갱신되지 않았다)
  .ax <- rf_panel_axis_stale()
  if (isTRUE(.ax$stale)) {
    jlog("panel_axis_stale", reason = .ax$reason, ids = paste(head(.ax$missing, 5), collapse = ","))
    rf_panel_axis_refresh("stale_vs_registry")
  }
  if (is.null(CAND) || !nrow(CAND)) { jlog("nothing_to_backfill"); return(0L) }
  jlog("candidates", n = nrow(CAND), total_months = CAND$n_months_total[1],
       ids = paste(head(CAND$id, 8), collapse = ","), budget_min = budget)

  suppressMessages(source(file.path(ROOT, "02_Infrastructure/factor_db/factor_db_builder.R")))
  t0 <- Sys.time(); done <- character(0)
  for (i in seq_len(nrow(CAND))) {
    el <- as.numeric(difftime(Sys.time(), t0, units = "mins"))
    if (el >= budget) { jlog("budget_exhausted", elapsed_min = round(el, 1), done = length(done),
                             remaining = nrow(CAND) - length(done),
                             note = "다음 밤이 이어받는다 — 진행 상태는 이력 개월수에서 파생된다"); break }
    id <- CAND$id[i]; md <- CAND$module[i]
    r <- tryCatch({ backfill_custom_factor(id = id, module = md); TRUE },
                  error = function(e) { jlog("backfill_failed", id = id, module = md,
                                             err = conditionMessage(e)); FALSE })
    if (isTRUE(r)) { done <- c(done, id)
      jlog("backfill_done", id = id, module = md, have_before = CAND$have[i],
           elapsed_min = round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 1)) }
  }

  # ★IC 재계산은 필수 후속 — 없으면 커넥터의 Z_Score_Aligned(C13 방향 정렬)가 안 서서
  #   채워 넣은 이력이 있어도 B1 후보 풀에 들어가지 못한다(등재만 되고 못 쓰는 상태 재현).
  if (length(done)) {
    tryCatch({ compute_all_factor_ic_monthly()
               jlog("ic_refreshed", n = length(done), ids = paste(done, collapse = ",")) },
             error = function(e) jlog("ic_refresh_failed", err = conditionMessage(e)))
    # 축 판정 사이드카도 새 배출을 반영해 다시 낸다(멱등 · 위 신선도 경로와 같은 함수)
    rf_panel_axis_refresh("backfilled")
  }
  jlog("tick_done", filled = length(done), elapsed_min = round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 1))
  0L
}

rc <- tryCatch(main(), error = function(e) { jlog("fatal", err = conditionMessage(e)); 1L })
quit(status = if (is.numeric(rc)) as.integer(rc) else 0L)
