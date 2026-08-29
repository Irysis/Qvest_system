#!/usr/bin/env Rscript
## ============================================================================
## reinforce_ladder.R — 자동 강화 사다리 드라이버 (v9.2 §8-S2, 2026-08-24)
##
## 요청(도훈): "등급이 낮아도 시그널이 있으면 강화 프로세스를 총동원하는 자동 배선."
##   F/C 등급이라도 **국면별 IR** 이 살아 있으면 → ①팩터 composite → ②비중 방법론 교체
##   → ③리스크 오버레이 순으로 자동으로 태운다.
##
## ★측정 코드는 0줄이다. 3칸 전부 기존 계약 호출이다:
##   ① run_alpha_search(fe_score_composite.R) + sc_incremental_report/sc_axes
##   ② run_alpha_search(weight_method=<카탈로그 arm>)
##   ③ drain_run_candidate() 직접 호출 + overlay_bt_recon() + essence_score()
##
## ── 왜 worker 를 자식 프로세스로 두는가 (이중 모드의 이유) ────────────────────
##   run_alpha_search() 는 ①자체 timeout 이 없고 ②전역(`%||%` 포함)을 재정의하며
##   ③하네스에 10GB peak → Windows segfault 전례가 있다(backtest_harness.R:1085 주석).
##   9회 반복 호출하면 셋이 누적된다. ⇒ 같은 파일이 `--job=<path.json>` 이면 worker,
##   없으면 driver(system2(Rscript, ..., timeout=per_attempt_secs)).
##
## ── 안전장치 (전부 필수) ────────────────────────────────────────────────────
##   · out_root 분리 — ★overlay_candidate_queue.R:34 / standalone_track_queue.R 이
##     `stage_artifacts/alpha_search/*` 를 glob 한다. 분리하지 않으면 사다리 산출물이
##     스크린 큐에 등재돼 **자기입력 루프**가 된다(위험 R3).
##   · QVEST_SCREEN_QUEUE_NORUN=1 (자식이 큐 리프레시를 돌지 않게)
##   · send_telegram=FALSE / per-attempt timeout / .cache/reinforce_ladder.stop
##   · dir.create 뮤텍스 + stale 6h / 칸마다 원장 flush(재개점)
##   · 셀 재개는 out_dir/bt_result.rds 존재로 재실행 회피 / 예산 시계 재개 시 리셋 금지
##
## ★드라이버는 새 큐를 만들지 않는다 — 한 프로세스 트리에서 완주하고 종료 시
##   close_round() 1회 + tg_agent_brief() 1회. 중간에 사람·다른 세션을 기다리는 상태가
##   하나도 없다("소비자 0인 큐"가 이 저장소의 반복 결함 — 위험 R10).
##
## 실행:
##   Rscript 02_Infrastructure/ops/reinforce_ladder.R --dry-run --list-candidates
##   Rscript 02_Infrastructure/ops/reinforce_ladder.R --top=1 --rung1-max=1 --rung2-arms=ivol
##   Rscript 02_Infrastructure/ops/reinforce_ladder.R --job=<jobfile.json>      # (내부) worker
## ============================================================================
suppressPackageStartupMessages({
  library(data.table); library(jsonlite)
})
setDTthreads(1)

`%|N|%` <- function(a, b) if (!is.null(a) && length(a) > 0L && !all(is.na(a))) a else b

## ─── root / 상수 ────────────────────────────────────────────────────────────
.rl_find_root <- function() {
  cands <- c(Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""), getwd(),
             "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
  cands <- cands[nzchar(cands)]
  hit <- cands[file.exists(file.path(cands, "02_Infrastructure/alpha_search/run_alpha_search.R"))]
  if (!length(hit)) stop("[reinforce_ladder] project root 미발견 (QM_ROOT 확인)")
  normalizePath(hit[1], winslash = "/", mustWork = FALSE)
}
RL_ROOT <- .rl_find_root()
setwd(RL_ROOT)
if (!nzchar(Sys.getenv("CLAUDE_PROJECT_DIR", ""))) Sys.setenv(CLAUDE_PROJECT_DIR = RL_ROOT)
if (!nzchar(Sys.getenv("QM_ROOT", "")))            Sys.setenv(QM_ROOT = RL_ROOT)

RL_VERSION     <- "reinforce_ladder_v1"
RL_CONFIG_REL  <- "06_Registry/reinforce_ladder_config.json"
RL_LEDGER_REL  <- "06_Registry/reinforce_ladder_ledger.json"
RL_IP_REL      <- "06_Registry/improvement_potential.json"
RL_PLAN_REL    <- "06_Registry/weight_sweep_plan.json"
RL_STOP_REL    <- ".cache/reinforce_ladder.stop"
RL_LOCK_REL    <- ".cache/reinforce_ladder.lock"
RL_SELF        <- file.path(RL_ROOT, "02_Infrastructure/ops/reinforce_ladder.R")
RL_ALPHA_STAGE <- "stage_artifacts/alpha_search"

## ── 진입 규칙 ladder_entry_v1 — RCMA 문턱 재사용 ─────────────────────────────
##   출처 = 02_Infrastructure/portfolio/regime_module_admission.R:45,56-57.
##   c1(IR floor) · c2(표본) · c4(유의) 를 재사용하고 **c0_sign 을 신설**한다:
##   RCMA 의 `|t| ≥ 2` 는 **방어형 음의 IR 셀**(위기에 벤치를 덜 잃는 specialist)을
##   받기 위한 양측 검정이다. 사다리는 "강화할 신호"를 찾는 것이므로 부호를 강제한다.
##   ★c3_oos 는 재사용 **불가** — ip_per_regime 이 IS/OOS 분할을 내지 않는다.
##     그래서 라벨을 RCMA-admitted 가 아니라 `LADDER_ENTRY` 로 따로 발급하고
##     `rcma_c3_oos = "not_evaluated"` 를 명기한다. RCMA-admitted 로 오인되면
##     자본 층 주장이 되어버린다(등급 인플레의 전형).
RL_IR_FLOOR        <- 0.5
RL_MIN_MONTHS      <- 12L
RL_T_MIN           <- 2.0
RL_RARE_MIN_MONTHS <- 6L
RL_RARE_T_MIN      <- 1.5
RL_STRESS_POOL     <- c("CRISIS", "RISK_OFF", "CAUTION")
RL_ENTRY_RULE      <- "ladder_entry_v1"

## ── ②칸 화이트리스트 ───────────────────────────────────────────────────────
##   왜 stopifnot 인가: backtest_harness.R:1179-1181 의 최종 else 가 미등록 문자열을
##   **에러 없이 EW 로 폴백**한다. 오타 1글자가 "새 방법론을 시험했다"는 거짓 기록을 만든다
##   (같은 사고가 methods/method_registry.R:73-78 에 이미 기록돼 있다 — 위험 R2).
RL_WEIGHT_WHITELIST <- c(
  "equal", "ivol", "hrp", "minvar", "riskparity", "score_tilt", "score_pure",
  "rank_tilt", "softmax_tilt", "winsor_tilt", "nco_score_tilt",
  "cvar", "maxdiv", "nco", "resampled", "robust_mv", "factor_rp",
  "entropy", "kelly", "higher_moment", "omega")
## ★3종 하드 제외 — 이름과 실제가 다른 팔은 사다리에 못 올린다.
##   run_alpha_search.R:280-288 이 run_monthly_simulation 에 `regime_dt`/`ic_history` 를
##   **전달하지 않는다**. 그래서 backtest_harness.R:1112,1148 에서 `mrs_val = 0` 이 되어
##   regime_tilt/regime_softmax 는 **조용히 국면 중립으로 퇴화**하고, ic_tilt 는 IC 이력
##   없이 돈다. 측정은 성공하고 라벨만 거짓이 되는 형태 — 가장 나쁜 실패다.
##   (배선 복구는 별건 태스크. 복구되면 이 목록에서 빼면 된다.)
RL_WEIGHT_EXCLUDED <- c("regime_tilt", "regime_softmax", "ic_tilt")
RL_WEIGHT_FALLBACK <- c("ivol", "hrp", "score_tilt", "rank_tilt")

RL_COMPOSITE_ENGINE <- "02_Infrastructure/alpha_search/fe_score_composite.R"

## ─── 로깅 ───────────────────────────────────────────────────────────────────
.RL_LOGFILE <- NULL
rl_log <- function(fmt, ...) {
  msg <- sprintf("[%s] %s", format(Sys.time(), "%H:%M:%S"), sprintf(fmt, ...))
  cat(msg, "\n", sep = "")
  if (!is.null(.RL_LOGFILE)) try(cat(msg, "\n", sep = "", file = .RL_LOGFILE, append = TRUE), silent = TRUE)
  invisible(NULL)
}

## ─── 설정 ───────────────────────────────────────────────────────────────────
RL_CONFIG_DEFAULTS <- list(
  enabled = TRUE, max_active = 1L, target_grade = "B", redo_completed = FALSE,
  per_attempt_secs = 2100L, budget_secs_per_candidate = 14400L,
  rung1_max_attempts = 3L, rung2_max_arms = 4L,
  strike_limit = 2L, strike_blocks_rung3 = FALSE,
  out_root = "stage_artifacts/reinforce_ladder",
  composite_support_min_dates = 120L, composite_support_min_median_names = 30L)

rl_config <- function(path = NULL) {
  p <- path %|N|% file.path(RL_ROOT, RL_CONFIG_REL)
  cfg <- RL_CONFIG_DEFAULTS
  if (file.exists(p)) {
    j <- tryCatch(fromJSON(p, simplifyVector = TRUE), error = function(e) NULL)
    if (is.null(j)) stop("[reinforce_ladder] 설정 파싱 실패(조용한 기본값 사용 금지): ", p)
    for (k in names(cfg)) if (!is.null(j[[k]])) cfg[[k]] <- j[[k]]
    cfg$`_source` <- p
  } else {
    cfg$`_source` <- "defaults(파일 부재)"
  }
  cfg$max_active                 <- as.integer(cfg$max_active)
  cfg$per_attempt_secs           <- as.integer(cfg$per_attempt_secs)
  cfg$budget_secs_per_candidate  <- as.integer(cfg$budget_secs_per_candidate)
  cfg$rung1_max_attempts         <- as.integer(cfg$rung1_max_attempts)
  cfg$rung2_max_arms             <- as.integer(cfg$rung2_max_arms)
  cfg$strike_limit               <- as.integer(cfg$strike_limit)
  cfg$strike_blocks_rung3        <- isTRUE(as.logical(cfg$strike_blocks_rung3))
  cfg$composite_support_min_dates        <- as.integer(cfg$composite_support_min_dates)
  cfg$composite_support_min_median_names <- as.integer(cfg$composite_support_min_median_names)
  cfg
}

## ─── 원자 JSON 기록 (temp + rename — overlay_candidate_drain.R:.atomic_write_json 전례) ──
rl_write_json_atomic <- function(obj, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  tmp <- paste0(path, ".tmp", Sys.getpid())
  write_json(obj, tmp, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = 8)
  if (file.exists(path)) suppressWarnings(file.remove(path))
  if (!isTRUE(suppressWarnings(file.rename(tmp, path)))) {
    okc <- suppressWarnings(file.copy(tmp, path, overwrite = TRUE)); suppressWarnings(file.remove(tmp))
    if (!isTRUE(okc)) stop("[reinforce_ladder] 원자 기록 실패: ", path)
  }
  invisible(TRUE)
}

## ─── 원장 ───────────────────────────────────────────────────────────────────
RL_LEDGER_DOC <- paste(
  "강화 사다리 원장 (reinforce_ladder_v1). 진입 규칙 = ladder_entry_v1 —",
  "RCMA 문턱(IR>=0.5 / n>=12m / |t|>=2) 재사용 + c0_sign(active_ir>0) 신설.",
  "★rcma_c3_oos = not_evaluated — ip_per_regime 이 IS/OOS 분할을 내지 않으므로 RCMA c3 는 재사용 불가.",
  "이 원장의 LADDER_ENTRY 는 RCMA-admitted 가 **아니다**(자본 층 주장 아님).",
  "★RISK_OFF 는 unified_regime_signal 에서 월 0(공집합)이라 이 규칙이 그 국면에서 한 번도 발화하지 못한다 —",
  "'RISK_OFF 미진입'은 **측정 안 됨**이지 통과가 아니다.",
  "★basis: 모든 셀에 daily_native / monthly_recon 이 붙는다. 두 basis 는 직접 비교 불가",
  "(오버레이 없이 월간 재구성만 해도 MDD −9.07pp — overlay_bt_recon.R 헤더 참조).")

rl_ledger_read <- function(root = RL_ROOT) {
  p <- file.path(root, RL_LEDGER_REL)
  d <- if (file.exists(p)) tryCatch(fromJSON(p, simplifyVector = FALSE), error = function(e) NULL) else NULL
  if (is.null(d)) d <- list(schema_version = "reinforce_ladder_ledger_v1",
                            `_doc` = RL_LEDGER_DOC, runs = list())
  if (is.null(d$runs)) d$runs <- list()
  d$`_doc` <- RL_LEDGER_DOC
  d
}

## ★`cells`/`rungs`/`final` 은 **통째로 교체**한다 — modifyList 는 리스트를 재귀 병합하므로
##   구 라벨의 셀이 원장에 영구히 남는다(라벨 규약을 바꾸면 죽은 셀이 계속 표에 실린다).
## ★v9.21: registration 추가 — 재개 시 이전 회차의 등재 결과가 재귀 병합으로 잔존하면
##   "이번 회차에 등재했다"로 오독된다(위 주석과 같은 사유).
RL_LEDGER_REPLACE_KEYS <- c("cells", "rungs", "final", "registration")

rl_ledger_upsert <- function(cand_id, rec, root = RL_ROOT) {
  d <- rl_ledger_read(root)
  prev <- d$runs[[cand_id]]
  merged <- if (is.null(prev)) rec else modifyList(prev, rec)
  for (k in RL_LEDGER_REPLACE_KEYS) if (!is.null(rec[[k]])) merged[[k]] <- rec[[k]]
  d$runs[[cand_id]] <- merged
  d$generated_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  rl_write_json_atomic(d, file.path(root, RL_LEDGER_REL))
  invisible(d$runs[[cand_id]])
}

## ─── stop 파일 · 뮤텍스 ─────────────────────────────────────────────────────
rl_stop_requested <- function(root = RL_ROOT) file.exists(file.path(root, RL_STOP_REL))

rl_lock_acquire <- function(root = RL_ROOT, stale_secs = 6 * 3600) {
  lk <- file.path(root, RL_LOCK_REL)
  dir.create(dirname(lk), recursive = TRUE, showWarnings = FALSE)
  if (dir.create(lk, showWarnings = FALSE)) {
    writeLines(sprintf("pid=%s started=%s", Sys.getpid(), format(Sys.time())), file.path(lk, "owner.txt"))
    return(TRUE)
  }
  age <- as.numeric(difftime(Sys.time(), file.mtime(lk), units = "secs"))
  if (is.finite(age) && age > stale_secs) {
    rl_log("WARN 뮤텍스 stale %.0f분 — 회수하고 재취득 (%s)", age / 60, lk)
    unlink(lk, recursive = TRUE, force = TRUE)
    if (dir.create(lk, showWarnings = FALSE)) {
      writeLines(sprintf("pid=%s started=%s (stale reclaim)", Sys.getpid(), format(Sys.time())),
                 file.path(lk, "owner.txt"))
      return(TRUE)
    }
  }
  FALSE
}
rl_lock_release <- function(root = RL_ROOT) unlink(file.path(root, RL_LOCK_REL), recursive = TRUE, force = TRUE)

## ─── 진입 게이트 ────────────────────────────────────────────────────────────
#' ip 블록 1건 → 국면 셀별 자격 + 진입 요약
#' @return list(cells=data.table, eligible=logical, entry_regime, entry_strength, dup_sig, reason)
rl_entry_gate <- function(blk) {
  base <- list(eligible = FALSE, entry_regime = NA_character_, entry_strength = NA_real_,
               entry_ir = NA_real_, entry_n_months = NA_integer_, dup_sig = NA_character_,
               rule = RL_ENTRY_RULE, rcma_c3_oos = "not_evaluated",
               cells = data.table(), reason = "")
  if (!isTRUE(blk$available)) { base$reason <- paste("ip available=FALSE —", blk$reason %|N|% "사유 미기재"); return(base) }
  per <- blk$per_regime
  if (is.null(per) || !length(per)) { base$reason <- "per_regime 비어있음 — 판정 불가(미측정)"; return(base) }

  rows <- rbindlist(lapply(names(per), function(L) {
    s <- per[[L]]
    n  <- suppressWarnings(as.integer((s$n_months  %|N|% NA)[1]))
    ir <- suppressWarnings(as.numeric((s$active_ir %|N|% NA)[1]))
    tt <- suppressWarnings(as.numeric((s$active_t  %|N|% NA)[1]))
    data.table(regime = L, n_months = n, active_ir = ir, active_t = tt,
               mean_ann = suppressWarnings(as.numeric((s$mean_ann %|N|% NA)[1])))
  }), fill = TRUE)

  rows[, c0_sign := is.finite(active_ir) & active_ir > 0]                       # 신설(부호 강제)
  rows[, c1_perf := is.finite(active_ir) & active_ir >= RL_IR_FLOOR]            # RCMA c1 (top_tercile 항은 풀 없음)
  rows[, c2_n    := is.finite(n_months)  & n_months  >= RL_MIN_MONTHS]          # RCMA c2
  rows[, c4_sig  := is.finite(active_t)  & abs(active_t) >= RL_T_MIN]           # RCMA c4
  rows[, rare_cell_diagnostic := regime %in% RL_STRESS_POOL & is.finite(n_months) & n_months < RL_MIN_MONTHS]
  rows[, eligible := c0_sign & c1_perf & c2_n & c4_sig]

  E <- rows[eligible == TRUE]
  if (!nrow(E)) {
    base$cells <- rows
    base$reason <- sprintf("자격 셀 0 — 최대 t=%.3f / 최대 IR=%.3f (문턱 IR>=%.1f n>=%d |t|>=%.1f, 부호 강제)",
                           suppressWarnings(max(rows$active_t, na.rm = TRUE)),
                           suppressWarnings(max(rows$active_ir, na.rm = TRUE)),
                           RL_IR_FLOOR, RL_MIN_MONTHS, RL_T_MIN)
    return(base)
  }
  i <- which.max(E$active_t)
  base$cells          <- rows
  base$eligible       <- TRUE
  base$entry_regime   <- as.character(E$regime[i])
  base$entry_strength <- as.numeric(E$active_t[i])
  base$entry_ir       <- as.numeric(E$active_ir[i])
  base$entry_n_months <- as.integer(E$n_months[i])
  base$dup_sig        <- sprintf("%s|%d|%.3f|%.3f", base$entry_regime, base$entry_n_months,
                                 base$entry_ir, base$entry_strength)
  base$reason         <- sprintf("자격 셀 %d — 진입 %s (IR %.3f, t %.3f, n %dm)", nrow(E),
                                 base$entry_regime, base$entry_ir, base$entry_strength, base$entry_n_months)
  base
}

## ─── manifest 해석 ──────────────────────────────────────────────────────────
.RL_MF_CACHE <- new.env(parent = emptyenv())     # 전수 스캔 1회 메모이즈 (id → manifest 경로)

.rl_manifest_for <- function(strategy_id, root = RL_ROOT, out_root = NULL) {
  rid <- sub("^STR_AS_", "", strategy_id)
  ## ★사다리 자기 산출물은 후보가 아니다 — ip 게이트를 연 뒤로 사다리 런도 ip 블록을 갖는다.
  ##   여기서 즉시 걸러야 (a) 자기입력 루프가 원천 차단되고 (b) 전수 스캔이 발생하지 않는다.
  if (!is.null(out_root) && length(Sys.glob(file.path(root, out_root, "*", "*", rid)))) return(NULL)
  p <- file.path(root, RL_ALPHA_STAGE, rid, "strategy_manifest.json")
  if (!file.exists(p)) {
    ## 접두 규약을 벗어난 id → 전수 스캔. **프로세스당 1회만** 돈다(783 dir 파싱 비용).
    if (!exists("map", envir = .RL_MF_CACHE, inherits = FALSE)) {
      mp <- list()
      for (f in Sys.glob(file.path(root, RL_ALPHA_STAGE, "*", "strategy_manifest.json"))) {
        m <- tryCatch(fromJSON(f, simplifyVector = TRUE), error = function(e) NULL)
        sid <- if (is.null(m)) NULL else as.character(m$strategy_id)[1]
        if (!is.null(sid) && nzchar(sid) && !is.na(sid)) mp[[sid]] <- f
      }
      assign("map", mp, envir = .RL_MF_CACHE)
    }
    hit <- get("map", envir = .RL_MF_CACHE)[[strategy_id]]
    if (!is.null(hit)) p <- hit
  }
  if (!file.exists(p)) return(NULL)
  m <- tryCatch(fromJSON(p, simplifyVector = TRUE), error = function(e) NULL)
  if (is.null(m)) return(NULL)
  run_dir <- dirname(p)
  btp <- (m$execution$bt_result_path %|N|% file.path(RL_ALPHA_STAGE, basename(run_dir), "bt_result.rds"))[1]
  if (!file.exists(file.path(root, btp)) && file.exists(file.path(run_dir, "bt_result.rds")))
    btp <- file.path(RL_ALPHA_STAGE, basename(run_dir), "bt_result.rds")
  list(strategy_id = as.character(m$strategy_id),
       strategy_name = as.character(m$strategy_name %|N|% NA),
       strategy_idea = as.character(m$strategy_idea %|N|% NA),
       manifest_path = sub(paste0("^", RL_ROOT, "/"), "", gsub("\\\\", "/", p)),
       run_dir = sub(paste0("^", RL_ROOT, "/"), "", gsub("\\\\", "/", run_dir)),
       engine = as.character(m$factor_engine_path %|N|% NA),
       weight_method = as.character(m$execution$weight_method %|N|% "equal"),
       n_holdings = as.integer(m$execution$n_holdings %|N|% 25L),
       universe = as.character(m$execution$universe %|N|% "K200_KQ150"),
       commission = as.numeric(m$execution$commission %|N|% 0.0015),
       grade = as.character(m$verdict$grade %|N|% NA),
       bt_status = as.character(m$backtest_contract$status %|N|% NA),
       bt_result_path = as.character(btp))
}

.rl_grade_rank <- function(g) {
  g <- toupper(as.character(g %|N|% "NA"))
  vapply(g, function(x) switch(sub("_.*$", "", x), "A" = 0L, "B" = 1L, "C" = 2L, "F" = 3L, 4L), integer(1))
}
.rl_family <- function(engine) {
  b <- sub("\\.R$", "", basename(as.character(engine)))
  b <- sub("^(factor_engine|fe)_", "", b)
  sub("_.*$", "", b)
}

## ─── 셀 라벨은 **내용 주소**여야 한다 (재개 정확성) ─────────────────────────
##   실측 사고(3차 스모크): 라벨이 위치 기반(`c_base_p1` / `rung2_ivol`)이라
##   ①칸이 실패한 런에서 만든 `rung2_ivol`(base 엔진 + ivol)을, ①칸이 성공한 다음 런이
##   **다른 base(composite) 기준의 셀로 오인해 재사용**했다 → ②칸이 ref 를 갈아탄 채
##   낡은 셀과 비교해 gain=TRUE 를 냈다(거짓 이득).
##   ⇒ 라벨(=산출 디렉터리)에 구성을 인코딩해 원장/글롭 두 재개 경로 모두를 안전하게 만든다.
.rl_tag <- function(engine) {
  b <- sub("\\.R$", "", basename(as.character(engine)))
  gsub("[^A-Za-z0-9]", "", sub("^(factor_engine|fe)_", "", b))
}
.rl_cfg_tag <- function(cfg) {
  if (identical(as.character(cfg$engine), RL_COMPOSITE_ENGINE)) {
    m <- trimws(strsplit(as.character(cfg$env$COMPOSITE_MEMBERS %|N|% ""), ",", fixed = TRUE)[[1]])
    m <- m[nzchar(m)]
    paste0("comp", paste(vapply(m, .rl_tag, ""), collapse = ""))
  } else .rl_tag(cfg$engine)
}

## ─── 후보 목록 ──────────────────────────────────────────────────────────────
rl_candidates <- function(config, root = RL_ROOT) {
  ipp <- file.path(root, RL_IP_REL)
  if (!file.exists(ipp)) stop("[reinforce_ladder] ip 레지스트리 부재: ", ipp,
                              " — `improvement_potential.R --runs-since=` 로 먼저 채울 것")
  d <- fromJSON(ipp, simplifyVector = FALSE)
  ents <- d$entries %|N|% list()
  if (!length(ents)) stop("[reinforce_ladder] ip 엔트리 0건 — 빈 결과 = 합격 아님")

  rows <- list(); n_avail <- 0L; cellrows <- list()
  for (nm in names(ents)) {
    blk <- ents[[nm]]
    if (isTRUE(blk$available)) n_avail <- n_avail + 1L
    g <- rl_entry_gate(blk)
    ## ★셀 수와 후보 수는 다른 분모다 — 한 후보가 여러 국면에서 자격을 가질 수 있다.
    ##   플랜의 "13셀 자격(12 RISK_ON + 1 CRISIS)"은 셀 기준이므로 둘 다 낸다.
    if (nrow(g$cells)) {
      cc <- copy(g$cells)[eligible == TRUE]
      if (nrow(cc)) { cc[, candidate_id := as.character(blk$id %|N|% nm)]; cellrows[[length(cellrows) + 1L]] <- cc }
    }
    if (!isTRUE(g$eligible)) next
    mf <- .rl_manifest_for(blk$id %|N|% nm, root, out_root = config$out_root)
    if (is.null(mf)) next
    if (!file.exists(file.path(root, mf$bt_result_path))) next
    rows[[length(rows) + 1L]] <- data.table(
      candidate_id = as.character(blk$id %|N|% nm),
      entry_regime = g$entry_regime, entry_strength = g$entry_strength,
      entry_ir = g$entry_ir, entry_n_months = g$entry_n_months,
      dup_sig = g$dup_sig, ip_score = suppressWarnings(as.numeric(blk$score %|N|% NA)),
      pin_tag = as.character(blk$pin_tag %|N|% NA),
      grade = mf$grade, engine = mf$engine, weight_method = mf$weight_method,
      n_holdings = mf$n_holdings, universe = mf$universe, commission = mf$commission,
      bt_result_path = mf$bt_result_path, manifest_path = mf$manifest_path,
      run_dir = mf$run_dir, strategy_name = mf$strategy_name, strategy_idea = mf$strategy_idea)
  }
  CELLS <- if (length(cellrows)) rbindlist(cellrows, fill = TRUE) else data.table()
  if (!length(rows))
    return(list(table = data.table(), n_available = n_avail, n_eligible = 0L, n_taken = 0L,
                n_dup_dropped = 0L, dropped = data.table(), cells = CELLS))

  T0 <- rbindlist(rows, fill = TRUE)
  setorder(T0, -entry_strength)
  T0[, dup_rank := seq_len(.N), by = dup_sig]
  dropped <- T0[dup_rank > 1L]
  T1 <- T0[dup_rank == 1L]
  T1[, dup_rank := NULL]

  ## ── ★루프 폐쇄 (v9.21 §2-f, 2026-08-24) ─────────────────────────────────
  ##   구판은 원장을 **전혀 보지 않았다**. `entry_strength` 내림차순 + `max_active=1` 이므로
  ##   **매 실행이 같은 1위 후보를 다시 집는다.** 셀 재개 로직(out_dir/bt_result.rds 존재 시
  ##   재실행 회피)이 있어 두 번째 실행은 빠르게 끝나지만, 같은 결과로 close_round 와
  ##   등재를 되풀이하고 **다음 후보로는 영원히 넘어가지 않는다.**
  ##   ⇒ 무인 기동(§2-d)을 붙이는 순간 이 결함이 binding 이 된다 — 매일 아침 같은 전략만 태운다.
  ##
  ##   ★플랜 §2-f 정정: 플랜은 "close_round 에 `frontier_update` 인자 한 줄만 채우면 큐
  ##     되먹임이 발화한다"고 적었으나 **전제가 틀렸다**. `close_round.R:169` 는 그 서술에서
  ##     `FQ-[0-9]+` 를 정규식 추출해 큐를 갱신하는데, 사다리 입력은 frontier 가설이 아니라
  ##     전략 모듈이다 — `improvement_potential.json` 42 항목 전부 전략 id 키이고 **FQ-id 참조 0**
  ##     (2026-08-24 실측). 인자를 채워도 `fq_ids` 는 빈 벡터라 아무것도 안 바뀐다.
  ##     사다리의 실제 소비면은 frontier 큐가 아니라 **자기 원장**이고, 폐쇄 지점이 여기다.
  ##
  ##   ★배제 기준은 `stage == "done"` 하나다 — 중단(`stopped`)·진행 중은 재개해야 하므로 남긴다.
  ##   ★`--redo` 로 명시 해제 가능(재측정 의도가 있을 때. 조용한 봉인 금지).
  n_done_excluded <- 0L; done_ids <- character(0)
  if (!isTRUE(config$redo_completed)) {
    led <- tryCatch(rl_ledger_read(root), error = function(e) NULL)
    if (!is.null(led) && length(led$runs)) {
      done_ids <- names(led$runs)[vapply(led$runs, function(r)
        identical(as.character(r$stage %|N|% ""), "done"), logical(1))]
      if (length(done_ids)) {
        keep <- !(T1$candidate_id %in% done_ids)
        n_done_excluded <- sum(!keep)
        T1 <- T1[keep]
      }
    }
  }

  list(table = T1, n_available = n_avail, n_eligible = nrow(T0), n_taken = nrow(T1),
       n_dup_dropped = nrow(dropped), dropped = dropped, cells = CELLS,
       n_done_excluded = n_done_excluded, done_ids = done_ids)
}

## ─── ②칸 arm 목록 (생산은 위임 — 드라이버는 검증만 한다) ────────────────────
rl_weight_arms <- function(config, override = NULL, root = RL_ROOT) {
  src <- "override"
  arms <- override
  if (is.null(arms)) {
    pp <- file.path(root, RL_PLAN_REL)
    if (file.exists(pp)) {
      j <- tryCatch(fromJSON(pp, simplifyVector = TRUE), error = function(e) NULL)
      a <- NULL
      if (!is.null(j)) {
        if (!is.null(j$arms)) {
          a <- if (is.character(j$arms)) j$arms
               else if (is.data.frame(j$arms)) as.character(j$arms$weight_method %|N|% j$arms$id)
               else as.character(unlist(lapply(j$arms, function(x) x$weight_method %|N|% x$id %|N|% x)))
        } else if (!is.null(j$weight_methods)) a <- as.character(j$weight_methods)
      }
      if (length(a)) { arms <- a; src <- RL_PLAN_REL }
    }
  }
  ## 2순위 = weight_catalog.json (S3 레인 파생 색인). ★여기서는 stop 이 아니라 **교집합**이다 —
  ##   카탈로그는 lean 하네스 밖 방법론(QEPM/논문 어댑터)도 담으므로 미등재가 정상이다.
  ##   반대로 `--rung2-arms` 로 **직접 호명**한 것은 오타 가능성이 있으므로 아래에서 stop 한다.
  if (is.null(arms)) {
    cp <- file.path(root, "06_Registry/weight_catalog.json")
    if (file.exists(cp)) {
      j <- tryCatch(fromJSON(cp, simplifyVector = TRUE), error = function(e) NULL)
      E <- if (is.null(j)) NULL else j$entries
      if (is.data.frame(E) && "origin" %in% names(E)) {
        lean <- as.character(E$resolver$lean_name %|N|% rep(NA_character_, nrow(E)))
        okrow <- E$origin == "lean_builtin" & (E$status %in% c("active", "unverified"))
        a <- unique(lean[okrow & !is.na(lean)])
        a <- setdiff(intersect(a, RL_WEIGHT_WHITELIST), RL_WEIGHT_EXCLUDED)
        if (length(a)) { arms <- a; src <- "06_Registry/weight_catalog.json(lean_builtin ∩ whitelist)" }
      }
    }
  }
  if (is.null(arms)) { arms <- RL_WEIGHT_FALLBACK; src <- "fallback(RL_WEIGHT_FALLBACK)" }
  arms <- unique(trimws(as.character(arms)))
  arms <- arms[nzchar(arms)]

  bad_excluded <- intersect(arms, RL_WEIGHT_EXCLUDED)
  if (length(bad_excluded))
    stop(sprintf(paste0("[reinforce_ladder] ②칸 하드 제외 방법론 요청됨: %s — ",
                        "run_alpha_search 가 regime_dt/ic_history 를 전달하지 않아 조용히 국면 중립으로 ",
                        "퇴화한다(backtest_harness.R:1112,1148 mrs_val=0). 이름과 실제가 다른 팔은 못 올린다."),
                 paste(bad_excluded, collapse = ", ")))
  ## ★조용한 EW 폴백 차단 — 미등록 문자열은 에러다.
  stopifnot(`②칸 weight_method 화이트리스트 위반 (미등록 문자열은 harness 가 조용히 EW 로 폴백한다)` =
              all(arms %in% RL_WEIGHT_WHITELIST))
  n <- min(length(arms), config$rung2_max_arms)
  list(arms = head(arms, n), source = src, n_available = length(arms))
}

## ─── ①칸 멤버 선정 composite_member_v1 ──────────────────────────────────────
## ★후보 arm 은 백테 arm 상한보다 넉넉히 만든다 — pre-flight 가 **엔진 단위로** 탈락시키기
##   때문이다(파라미터 엔진은 env 없이 재현 불가: 실측 fe_factor_combo.R 은 FACTOR_NAMES
##   환경변수를 요구하는데 manifest 는 그 값을 기록하지 않는다). 상위 2개만 만들면 1번이
##   재현 불가일 때 ①칸이 통째로 죽는다. 백테는 여전히 rung1_max_attempts 개만 돈다.
RL_PARTNER_POOL_MAX <- 4L

rl_composite_arms <- function(cand, pool, config) {
  P <- copy(pool)[candidate_id != cand$candidate_id & engine != cand$engine]
  if (!nrow(P)) return(list(arms = list(), engines = character(0),
                            reason = "partner 후보 0 — 같은 엔진뿐(결합 불가)"))
  P[, grade_rank  := .rl_grade_rank(grade)]
  P[, diff_regime := as.integer(entry_regime != cand$entry_regime)]
  P[, diff_family := as.integer(.rl_family(engine) != .rl_family(cand$engine))]
  ## 정렬 = ip 자격(이미 필터) → essence/hurdle 등급 → base 와 다른 국면에서 강한 것 → 다른 엔진 계열
  setorder(P, grade_rank, -diff_regime, -diff_family, -entry_strength)
  P <- P[!duplicated(engine)]
  P <- P[seq_len(min(RL_PARTNER_POOL_MAX, nrow(P)))]

  arms <- list()
  for (i in seq_len(nrow(P)))                         # ★라벨 = 내용 주소(파트너 엔진명)
    arms[[length(arms) + 1L]] <- list(label = sprintf("c_%s", .rl_tag(P$engine[i])),
                                      members = c(cand$engine, P$engine[i]))
  if (nrow(P) >= 2L)                                  # 3-멤버 arm (2·2·3 규약)
    arms[[length(arms) + 1L]] <- list(
      label = sprintf("c_%s_%s", .rl_tag(P$engine[1]), .rl_tag(P$engine[2])),
      members = c(cand$engine, P$engine[1], P$engine[2]))
  list(arms = arms, engines = unique(unlist(lapply(arms, `[[`, "members"))), partners = P,
       reason = sprintf("partner %d후보 (등급→다른국면→다른계열→강도) — 후보 arm %d, 백테 상한 %d",
                        nrow(P), length(arms), config$rung1_max_attempts))
}

## ─── 셀 측정 (계약 호출만) ──────────────────────────────────────────────────
.rl_source_once <- function(rel, probe) {
  if (exists(probe, mode = "function")) return(invisible(TRUE))
  f <- file.path(RL_ROOT, rel)
  if (file.exists(f)) suppressMessages(source(f))
  invisible(exists(probe, mode = "function"))
}

#' @param bt bt_result 또는 .rds 경로
#' @param basis "daily_native" | "monthly_recon" — ★두 basis 는 직접 비교 불가
rl_cell <- function(bt, basis, label, n_trials_cumulative = 1L, selection_type = "chain",
                    out_dir = NA_character_, secs = NA_real_, extra = list()) {
  stopifnot(basis %in% c("daily_native", "monthly_recon"))
  .rl_source_once("02_Infrastructure/contracts/essence_score.R", "essence_score")
  B <- if (is.character(bt)) readRDS(bt) else bt
  es <- tryCatch(essence_score(B, n_trials_cumulative = n_trials_cumulative,
                               selection_type = selection_type, sidecar_log = FALSE),
                 error = function(e) NULL)
  if (is.null(es)) stop("[reinforce_ladder] essence_score 실패 — 셀 ", label)
  e <- es$essence
  c(list(label = label, basis = basis, grade = es$grade,
         SR = as.numeric(e$net_sharpe %|N|% NA), IR = as.numeric(e$net_ir %|N|% NA),
         MDD = as.numeric(e$mdd %|N|% NA), Calmar = as.numeric(e$calmar %|N|% NA),
         CAGR = as.numeric(e$cagr %|N|% NA), PORT_t = as.numeric(e$portfolio_alpha_t_nw_lag3 %|N|% NA),
         oos_retention = as.numeric(e$oos_retention %|N|% NA), dsr = as.numeric(e$dsr %|N|% NA),
         n_months = as.integer(nrow(as.data.table(B$period_returns))),
         integrity = as.character(B$manifest$integrity_status[1]),
         selection_type = selection_type, n_trials_cumulative = n_trials_cumulative,
         out_dir = out_dir, secs = secs,
         hard_fail = isTRUE(es$hard_fail), essence_reasons = paste(es$reasons, collapse = "; ")),
    extra)
}

#' 증분 — ★basis 불일치 시 stop. 이것이 basis 방화벽의 강제 지점이다.
rl_delta <- function(new, ref) {
  if (!identical(new$basis, ref$basis))
    stop(sprintf(paste0("[reinforce_ladder] basis 불일치 비교 차단: %s(%s) vs %s(%s). ",
                        "월간 재구성은 오버레이 없이도 MDD −9.07pp 를 만든다 — ",
                        "basis 를 섞으면 아무 일도 안 한 팔이 ΔMDD 문턱을 통과한다."),
                 new$label, new$basis, ref$label, ref$basis))
  d <- list(ref_label = ref$label, basis = new$basis,
            dSR = new$SR - ref$SR, dIR = new$IR - ref$IR, dMDD = new$MDD - ref$MDD,
            dCalmar = new$Calmar - ref$Calmar, dPORT_t = new$PORT_t - ref$PORT_t,
            dCAGR = new$CAGR - ref$CAGR)
  ## HARD 3축 = sc_incremental_report(score_composite.R:296) 자구동일 문턱
  d$gate_dSR  <- isTRUE(d$dSR  >= 0.05)
  d$gate_dMDD <- isTRUE(d$dMDD <= -0.03)
  d$gate_dIR  <- isTRUE(d$dIR  >= 0.05)
  d$gain <- isTRUE(d$gate_dSR || d$gate_dMDD || d$gate_dIR)
  d$rule <- "sc_incremental_report HARD: dSR>=+0.05 OR dMDD<=-0.03 OR dIR>=+0.05 (같은 basis 안에서만)"
  d
}

## ─── worker 기동 ────────────────────────────────────────────────────────────
.rl_rscript <- function() {
  p <- file.path(R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")
  if (file.exists(p)) return(p)
  w <- Sys.which("Rscript"); if (nzchar(w)) return(unname(w))
  stop("[reinforce_ladder] Rscript 실행파일 미발견")
}

rl_run_worker <- function(job, jobs_dir, timeout_secs) {
  dir.create(jobs_dir, recursive = TRUE, showWarnings = FALSE)
  tag <- sprintf("%s_%s", job$kind, gsub("[^A-Za-z0-9]", "", job$label))
  jp  <- file.path(jobs_dir, sprintf("job_%s_%s.json", format(Sys.time(), "%H%M%S"), tag))
  rp  <- sub("\\.json$", ".result.json", jp)
  lg  <- sub("\\.json$", ".log", jp)
  rl_write_json_atomic(job, jp)
  t0 <- Sys.time()
  rc <- suppressWarnings(system2(.rl_rscript(),
                                 c("--no-save", "--no-restore", shQuote(RL_SELF), paste0("--job=", shQuote(jp))),
                                 stdout = lg, stderr = lg, wait = TRUE, timeout = timeout_secs))
  secs <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  res <- if (file.exists(rp)) tryCatch(fromJSON(rp, simplifyVector = TRUE), error = function(e) NULL) else NULL
  if (is.null(res)) {
    tail_txt <- if (file.exists(lg)) paste(utils::tail(readLines(lg, warn = FALSE), 6L), collapse = " / ") else "(로그 없음)"
    return(list(ok = FALSE, rc = rc, secs = secs, log = lg,
                error = sprintf("worker 결과 부재 (rc=%s, %.0fs)%s | %s", rc, secs,
                                if (identical(as.integer(rc), 124L)) " TIMEOUT" else "", tail_txt)))
  }
  res$rc <- rc; res$secs <- secs; res$log <- lg
  res
}

## ─── worker 본체 ────────────────────────────────────────────────────────────
rl_worker <- function(job_path) {
  job <- fromJSON(job_path, simplifyVector = TRUE)
  rp  <- sub("\\.json$", ".result.json", job_path)
  out <- tryCatch({
    if (!is.null(job$env) && length(job$env))
      do.call(Sys.setenv, as.list(setNames(as.character(unlist(job$env)), names(job$env))))
    switch(as.character(job$kind),
           alpha_search = .rl_worker_alpha(job),
           support      = .rl_worker_support(job),
           overlay      = .rl_worker_overlay(job),
           stop("worker: 알 수 없는 kind = ", job$kind))
  }, error = function(e) list(ok = FALSE, error = conditionMessage(e)))
  out$kind <- as.character(job$kind); out$label <- as.character(job$label)
  out$finished_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  rl_write_json_atomic(out, rp)
  invisible(out)
}

.rl_worker_alpha <- function(job) {
  suppressMessages(source(file.path(RL_ROOT, "02_Infrastructure/alpha_search/run_alpha_search.R")))
  r <- run_alpha_search(
    strategy_name   = as.character(job$strategy_name),
    strategy_idea   = as.character(job$strategy_idea),
    factor_engine_path = file.path(RL_ROOT, as.character(job$engine)),
    n_holdings      = as.integer(job$n_holdings),
    weight_method   = as.character(job$weight_method),
    commission      = as.numeric(job$commission),
    universe        = as.character(job$universe),
    out_root        = file.path(RL_ROOT, as.character(job$out_root)),
    send_telegram   = FALSE,
    deep            = FALSE)
  od <- gsub("\\\\", "/", r$out_dir)
  list(ok = TRUE, out_dir = sub(paste0("^", RL_ROOT, "/"), "", od),
       strategy_id = r$strategy_id, hurdle_grade = r$grade, hurdle_score = r$score,
       bt_result_path = sub(paste0("^", RL_ROOT, "/"), "", file.path(od, "bt_result.rds")))
}

## ①칸 support pre-flight — ★백테 전에 sc_combine_scores 의 stop 조건을 미리 잰다.
##   sc_combine_scores(score_composite.R:130-132)는 min_members 미달 시 **stop** 한다.
##   백테를 돌린 뒤 죽으면 arm 하나가 통째로 낭비된다.
.rl_worker_support <- function(job) {
  ## ★config.R 를 **먼저** 절대경로로 소싱한다 — backtest_harness.R:18-20 은 PROJECT_ROOT 가
  ##   없으면 `dirname(sys.frame(1)$ofile %||% ".")/config.R` 로 낙하하고, 중첩 source 에서는
  ##   ofile 이 NULL 이라 "./config.R" 을 찾다 죽는다(실측: worker 가 1초 만에
  ##   "cannot open the connection" 으로 종료). run_alpha_search.R:52 와 같은 순서를 쓴다.
  suppressMessages({
    source(file.path(RL_ROOT, "02_Infrastructure/config.R"))
    source(file.path(RL_ROOT, "02_Infrastructure/backtest_harness.R"))
    source(file.path(RL_ROOT, "02_Infrastructure/contracts/score_composite.R"))
  })
  res <- load_rawdata(use_cache = TRUE)
  RAW <- res$RAWDATA; BM <- res$BM_DT
  if (!inherits(RAW$Date, "Date")) RAW[, Date := as.Date(Date)]
  ## run_alpha_search.R:159-162 자구동일 전처리 — 일부 엔진이 LiqPass/AvgTV20 을 읽는다.
  ## 이걸 빼면 pre-flight 가 러너와 **다른 입력**에서 support 를 재게 된다(대용품 검사).
  RAW[, TradingValue := Close * Vol]
  RAW[, AvgTV20 := frollmean(TradingValue, 20L, align = "right"), by = Ticker]
  RAW[, LiqPass := !is.na(AvgTV20) & AvgTV20 >= 2e8]
  ## ★엔진 단위 tryCatch — 한 멤버가 재현 불가라고 ①칸 전체를 죽이지 않는다.
  ##   실측 사례: fe_factor_combo.R 은 `FACTOR_NAMES` 환경변수를 요구하는 **파라미터 엔진**인데
  ##   strategy_manifest 는 그 값을 기록하지 않는다 ⇒ manifest 만으로는 재현 불가.
  ##   이건 사다리의 결함이 아니라 **manifest 스키마의 공백**이고, 여기서는 정직하게
  ##   UNHARVESTABLE 로 표시하고 그 엔진이 든 arm 만 뺀다(침묵 skip 금지).
  engines <- as.character(job$engines)
  H <- list(); hstat <- list()
  for (e in engines) {
    ep <- file.path(RL_ROOT, e)
    r <- tryCatch(sc_harvest_member(ep, RAW, extra_globals = list(BM_DT = BM)),
                  error = function(err) structure(conditionMessage(err), class = "rl_harvest_err"))
    if (inherits(r, "rl_harvest_err")) {
      hstat[[e]] <- list(engine = e, ok = FALSE, reason = as.character(r))
      cat(sprintf("[support] UNHARVESTABLE %s — %s\n", e, as.character(r)))
    } else {
      H[[e]] <- r
      hstat[[e]] <- list(engine = e, ok = TRUE, reason = NA_character_,
                         n_dates = uniqueN(r$Date), n_tickers = uniqueN(r$Ticker), n_rows = nrow(r))
    }
  }
  ## run_alpha_search 는 엔진 실행 **후에** start_date + 유니버스 멤버십을 FACTORS 에 건다
  ## (run_alpha_search.R:181-203). 유효 support 는 그 필터를 통과한 뒤의 것이다.
  memb <- unique(RAW[(K200 == TRUE | KQ150 == TRUE), .(Date, Ticker)])
  sd0 <- as.Date(job$start_date %|N|% "2005-01-01")
  min_m <- as.integer(job$min_members %|N|% 2L)

  ## arm_members 는 arm 당 콤마-조인 문자열 1개로 받는다 — jsonlite 가 길이 같은
  ## 문자벡터 리스트를 **행렬로 단순화**해 인덱싱 규약이 갈리는 것을 원천 차단한다.
  arms_out <- list()
  arm_members <- as.character(job$arm_members)
  for (i in seq_along(job$arm_labels)) {
    lbl <- as.character(job$arm_labels[i])
    mem <- trimws(strsplit(arm_members[i], ",", fixed = TRUE)[[1]])
    mem <- mem[nzchar(mem)]
    miss <- mem[!mem %in% names(H)]
    if (length(miss)) {
      arms_out[[length(arms_out) + 1L]] <- list(
        label = lbl, members = paste(mem, collapse = ","), status = "UNHARVESTABLE",
        reason = sprintf("멤버 재현 불가: %s", paste(miss, collapse = ", ")),
        raw_dates = 0L, raw_rows = 0L, eff_dates = 0L, eff_median_names = 0, eff_min_names = 0L)
      next
    }
    Z <- rbindlist(lapply(mem, function(e) {
      d <- sc_zscore_by_date(H[[e]]); d[, .(Date, Ticker, member = e)]
    }), use.names = TRUE)
    U <- Z[, .(n_members = .N), by = .(Date, Ticker)][n_members >= min_m]
    raw_dates <- uniqueN(U$Date); raw_rows <- nrow(U)
    Ueff <- merge(U[Date >= sd0], memb, by = c("Date", "Ticker"))
    by_d <- Ueff[, .N, by = Date]
    arms_out[[length(arms_out) + 1L]] <- list(
      label = lbl, members = paste(mem, collapse = ","), status = "MEASURED", reason = NA_character_,
      raw_dates = raw_dates, raw_rows = raw_rows,
      eff_dates = as.integer(nrow(by_d)),
      eff_median_names = as.numeric(if (nrow(by_d)) stats::median(by_d$N) else 0),
      eff_min_names = as.integer(if (nrow(by_d)) min(by_d$N) else 0L))
  }
  list(ok = TRUE, min_members = min_m,
       n_harvest_ok = sum(vapply(hstat, function(x) isTRUE(x$ok), logical(1))),
       n_harvest_fail = sum(vapply(hstat, function(x) !isTRUE(x$ok), logical(1))),
       member_support = lapply(names(hstat), function(e) {
         s <- hstat[[e]]
         list(engine = e, ok = isTRUE(s$ok), reason = as.character(s$reason %|N|% NA),
              n_dates = as.integer(s$n_dates %|N|% NA), n_tickers = as.integer(s$n_tickers %|N|% NA),
              n_rows = as.integer(s$n_rows %|N|% NA))
       }),
       arms = arms_out)
}

## ③칸 — 큐 우회 직접 호출 + 재구성 + essence
##   drain_main 을 쓰지 않는 이유: 큐에서 id 를 찾고 없으면 stop 하며 큐 status 를 바꾼다.
##   선례 = improvement_potential.R:45 (QVEST_DRAIN_NORUN=1 소싱 후 함수 직접 호출).
.rl_worker_overlay <- function(job) {
  Sys.setenv(QVEST_DRAIN_NORUN = "1")
  suppressMessages({
    source(file.path(RL_ROOT, "02_Infrastructure/regime/overlay_candidate_drain.R"))
    source(file.path(RL_ROOT, "02_Infrastructure/contracts/overlay_bt_recon.R"))
    source(file.path(RL_ROOT, "02_Infrastructure/contracts/essence_score.R"))
  })
  btp <- file.path(RL_ROOT, as.character(job$bt_result_path))
  entry <- list(id = as.character(job$candidate_id), source = "alpha_search_manifest",
                source_path = file.path(RL_ROOT, as.character(job$manifest_path)),
                bt_result_path = btp)
  out <- drain_run_candidate(entry, cost_bps = as.numeric(job$cost_bps %|N|% 15))
  if (is.null(out$prs))
    stop("drain_run_candidate 반환에 prs 없음 — overlay_candidate_drain.R 의 `prs = prs` 패치 확인")
  verdict <- drain_verdict(out$paired)

  odir <- file.path(RL_ROOT, as.character(job$out_root))
  scen <- names(out$prs)
  cells <- list()
  for (nm in scen) {
    cd <- file.path(odir, nm)
    r <- tryCatch(overlay_bt_recon(out$prs[[nm]], btp, scenario = nm,
                                   strategy_id = sprintf("LADDER_RECON_%s_%s", job$candidate_id, nm),
                                   out_dir = cd, cost_bps = as.numeric(job$cost_bps %|N|% 15),
                                   pin_tag = as.character(job$pin_tag %|N|% NA),
                                   exposure_source = "overlay_candidate_drain: unified_regime_signal CAT_EXPOSURE(prev-month) / voltarget trailing-12m",
                                   carry_holdings = TRUE),
                  error = function(e) list(status = "FAIL", reason = conditionMessage(e)))
    ## ★셀 스키마를 동일하게 유지한다 — jsonlite 왕복에서 키가 갈리면 소비측이
    ##   조용히 NA 를 읽는다(스칼라만, 중첩 없음).
    mk <- function(...) modifyList(
      list(scenario = nm, status = "OK", basis = "monthly_recon", reason = NA_character_,
           out_dir = NA_character_, bt_result_path = NA_character_, grade = NA_character_,
           SR = NA_real_, IR = NA_real_, MDD = NA_real_, Calmar = NA_real_, CAGR = NA_real_,
           PORT_t = NA_real_, audit_pass = NA_integer_, audit_fail = NA_integer_,
           audit_warn = NA_integer_, audit_integrity = NA_character_, audit_critical = NA_integer_),
      list(...))
    if (!identical(r$status, "OK")) {
      cells[[length(cells) + 1L]] <- mk(status = as.character(r$status),
                                        reason = as.character(r$reason %|N|% NA))
      next
    }
    es <- tryCatch(essence_score(r$bt, selection_type = "sweep",
                                 n_trials_cumulative = as.integer(job$n_trials %|N|% length(scen)),
                                 sidecar_log = FALSE), error = function(e) NULL)
    e <- if (is.null(es)) list() else es$essence
    a <- r$audit_summary
    cells[[length(cells) + 1L]] <- mk(
      out_dir = sub(paste0("^", RL_ROOT, "/"), "", gsub("\\\\", "/", cd)),
      bt_result_path = sub(paste0("^", RL_ROOT, "/"), "", gsub("\\\\", "/", file.path(cd, "bt_result.rds"))),
      grade = if (is.null(es)) NA_character_ else as.character(es$grade),
      SR = as.numeric(e$net_sharpe %|N|% NA), IR = as.numeric(e$net_ir %|N|% NA),
      MDD = as.numeric(e$mdd %|N|% NA), Calmar = as.numeric(e$calmar %|N|% NA),
      CAGR = as.numeric(e$cagr %|N|% NA), PORT_t = as.numeric(e$portfolio_alpha_t_nw_lag3 %|N|% NA),
      audit_pass = as.integer(a$pass), audit_fail = as.integer(a$fail), audit_warn = as.integer(a$warn),
      audit_integrity = as.character(a$integrity), audit_critical = as.integer(a$critical_fail_n))
  }
  dir.create(odir, recursive = TRUE, showWarnings = FALSE)
  data.table::fwrite(as.data.table(out$tab), file.path(odir, "drain_scenarios.csv"))
  data.table::fwrite(as.data.table(out$paired), file.path(odir, "drain_paired_nw.csv"))
  list(ok = TRUE, adapter = out$adapter, drain_verdict = verdict,
       pit = list(strict_exposure_identical = out$pit$strict_exposure_identical,
                  strict_ab_inflation = out$pit$strict_ab$inflation,
                  strict_ab_lookahead_suspected = out$pit$strict_ab$lookahead_suspected),
       scenarios = as.data.table(out$tab), cells = cells,
       out_root = sub(paste0("^", RL_ROOT, "/"), "", gsub("\\\\", "/", odir)))
}

## ─── 3칸 ────────────────────────────────────────────────────────────────────
.rl_rel <- function(p) sub(paste0("^", RL_ROOT, "/"), "", gsub("\\\\", "/", p))

rl_rung1_composite <- function(cand, pool, config, st) {
  ca <- rl_composite_arms(cand, pool, config)
  if (!length(ca$arms))
    return(list(rung = "rung1_composite", status = "SKIPPED", reason = ca$reason, cells = list()))

  pre <- rl_run_worker(list(
    kind = "support", label = paste0(cand$candidate_id, "_support"),
    engines = ca$engines, arm_labels = vapply(ca$arms, `[[`, "", "label"),
    arm_members = vapply(ca$arms, function(a) paste(a$members, collapse = ","), ""),
    start_date = "2005-01-01", min_members = 2L), st$jobs_dir, config$per_attempt_secs)
  if (!isTRUE(pre$ok))
    return(list(rung = "rung1_composite", status = "SUPPORT_PREFLIGHT_FAILED",
                reason = as.character(pre$error %|N|% "사유 미기재"), cells = list()))

  sup <- pre$arms
  if (is.data.frame(sup)) sup <- split(sup, seq_len(nrow(sup)))
  keep <- list(); rejected <- list()
  for (i in seq_along(ca$arms)) {
    s <- sup[[i]]
    unharv <- identical(as.character(s$status %|N|% "MEASURED"), "UNHARVESTABLE")
    okd <- as.integer(s$eff_dates %|N|% 0L) >= config$composite_support_min_dates
    okn <- as.numeric(s$eff_median_names %|N|% 0) >= config$composite_support_min_median_names
    rec <- list(label = ca$arms[[i]]$label, members = ca$arms[[i]]$members,
                eff_dates = as.integer(s$eff_dates %|N|% 0L),
                eff_median_names = as.numeric(s$eff_median_names %|N|% 0),
                verdict = if (unharv) "UNHARVESTABLE" else "SUPPORT_INSUFFICIENT",
                reason = as.character(s$reason %|N|% NA))
    if (!unharv && okd && okn) keep[[length(keep) + 1L]] <- c(ca$arms[[i]], rec["eff_dates"], rec["eff_median_names"])
    else rejected[[length(rejected) + 1L]] <- rec
  }
  for (r in rejected)
    if (identical(r$verdict, "UNHARVESTABLE"))
      rl_log("  ① arm %s 기각 UNHARVESTABLE — %s · 백테 미실행", r$label, r$reason)
    else
      rl_log("  ① arm %s 기각 SUPPORT_INSUFFICIENT — dates %d(>=%d) median_names %.0f(>=%d) · 백테 미실행",
             r$label, r$eff_dates, config$composite_support_min_dates,
             r$eff_median_names, config$composite_support_min_median_names)
  ## 백테는 상한만큼만 — pre-flight 후보는 넉넉히, 실측은 예산 안에서.
  keep <- head(keep, max(1L, config$rung1_max_attempts))
  if (!length(keep))
    return(list(rung = "rung1_composite",
                status = if (all(vapply(rejected, function(r) identical(r$verdict, "UNHARVESTABLE"), logical(1))))
                           "ALL_MEMBERS_UNHARVESTABLE" else "SUPPORT_INSUFFICIENT",
                reason = paste("합격 arm 0 — 백테 미실행 |",
                               paste(vapply(rejected, function(r) sprintf("%s:%s", r$label, r$verdict), ""),
                                     collapse = " ")),
                member_support = pre$member_support, rejected = rejected, cells = list()))

  cells <- list()
  sel <- if (length(keep) >= 2L) "sweep" else "chain"
  for (a in keep) {
    if (rl_stop_requested()) break
    if (.rl_budget_left(st) <= 0) { rl_log("  ① 예산 소진 — 남은 arm 중단"); break }
    lbl <- paste0("rung1_", a$label)
    reuse <- .rl_reuse_cell(st, cand, lbl, selection_type = sel,
                            extra_add = list(members = a$members))
    if (!is.null(reuse)) {
      rl_log("  resume: cell %s reused (%s)", lbl, reuse$out_dir); cells[[lbl]] <- reuse; next
    }
    st$n_trials <- st$n_trials + 1L
    w <- rl_run_worker(list(
      kind = "alpha_search", label = paste0(cand$candidate_id, "_", lbl),
      strategy_name = sprintf("LADDER_INTERNAL/%s/%s", cand$candidate_id, lbl),
      strategy_idea = sprintf("강화 사다리 ①칸 score-level composite (members: %s). base=%s 국면 %s (IR %.3f, t %.3f).",
                              paste(basename(a$members), collapse = "+"), basename(cand$engine),
                              cand$entry_regime, cand$entry_ir, cand$entry_strength),
      engine = RL_COMPOSITE_ENGINE, n_holdings = cand$n_holdings,
      weight_method = cand$weight_method, commission = cand$commission, universe = cand$universe,
      out_root = file.path(config$out_root, cand$candidate_id, lbl),
      env = list(COMPOSITE_MEMBERS = paste(a$members, collapse = ","),
                 COMPOSITE_MIN_MEMBERS = "2", COMPOSITE_TOP_N = as.character(cand$n_holdings),
                 QVEST_SCREEN_QUEUE_NORUN = "1",
                 ## ★v9.21 누수 차단 — 중간 arm 은 module_quarantine 에 등재하지 않는다.
                 ##   out_root 분리는 스크린 큐의 `stage_artifacts/alpha_search/*` 글롭만 막는다.
                 ##   register_module 은 out_root 와 무관하게 06_Registry 에 쓰므로 그쪽으로 샜다
                 ##   (실적재 4건: module_quarantine.json 의 LADDER_INTERNAL/*). 그리고
                 ##   overlay_candidate_queue.R::collect_module_registries 는 quarantine 을
                 ##   **경로 필터 없이** 읽는다 ⇒ 다음 refresh 1회면 사다리 내부 arm 이 오버레이
                 ##   큐에 등재되고 ③칸이 그걸 소비한다 = 자기입력 루프(헤더 위험 R3).
                 ##   ★킬스위치는 신설이 아니라 기존 것이다(run_alpha_search.R:433).
                 ##   ★전역(Sys.setenv)이 아니라 **job 단위**로 거는 이유: 드라이버가 완주 후
                 ##     최종 승자를 정식 등재(rl_register_winner)해야 하는데, 전역에 걸면
                 ##     자기 env 가 그 등재를 막는다.
                 QVEST_LEAN_REGISTER = "0")), st$jobs_dir, config$per_attempt_secs)
    if (!isTRUE(w$ok)) { rl_log("  ① arm %s 실패: %s", a$label, w$error %|N|% "?"); next }
    cells[[lbl]] <- rl_cell(file.path(RL_ROOT, w$bt_result_path), "daily_native", lbl,
                            n_trials_cumulative = st$n_trials, selection_type = sel,
                            out_dir = w$out_dir, secs = w$secs,
                            extra = list(members = a$members, hurdle_grade = w$hurdle_grade,
                                         hurdle_score = w$hurdle_score,
                                         support_eff_dates = a$eff_dates,
                                         support_eff_median_names = a$eff_median_names,
                                         n_members_diagnostic = length(a$members)))
    st$spent <- st$spent + (w$secs %|N|% 0)
  }
  list(rung = "rung1_composite", status = if (length(cells)) "MEASURED" else "NO_CELL",
       selection_type = sel, rejected = rejected, member_support = pre$member_support, cells = cells)
}

rl_rung2_weights <- function(cand, config, st, arms_spec) {
  cells <- list()
  base_cfg <- st$best_config
  for (a in arms_spec$arms) {
    if (rl_stop_requested()) break
    if (.rl_budget_left(st) <= 0) { rl_log("  ② 예산 소진 — 남은 arm 중단"); break }
    if (identical(a, base_cfg$weight_method)) { rl_log("  ② arm %s == 현행 비중 — 생략", a); next }
    ## ★라벨에 현재 base 구성을 인코딩한다 — ①칸 결과에 따라 base 가 바뀌므로
    ##   `rung2_ivol` 만으로는 "무엇 위의 ivol 인지"가 사라진다(거짓 재개의 원인).
    lbl <- sprintf("rung2_%s_on_%s", a, .rl_cfg_tag(base_cfg))
    reuse <- .rl_reuse_cell(st, cand, lbl, selection_type = "sweep",
                            extra_add = list(weight_method = a))
    if (!is.null(reuse)) { rl_log("  resume: cell %s reused (%s)", lbl, reuse$out_dir); cells[[lbl]] <- reuse; next }
    st$n_trials <- st$n_trials + 1L
    w <- rl_run_worker(list(
      kind = "alpha_search", label = paste0(cand$candidate_id, "_", lbl),
      strategy_name = sprintf("LADDER_INTERNAL/%s/%s", cand$candidate_id, lbl),
      strategy_idea = sprintf("강화 사다리 ②칸 비중 방법론 교체 (%s -> %s). 신호 축 고정, 비중 축만 변경.",
                              base_cfg$weight_method, a),
      engine = base_cfg$engine, n_holdings = cand$n_holdings, weight_method = a,
      commission = cand$commission, universe = cand$universe,
      out_root = file.path(config$out_root, cand$candidate_id, lbl),
      ## ★v9.21: QVEST_LEAN_REGISTER=0 — ①칸과 같은 사유(누수 차단, 위 주석 참조).
      env = c(base_cfg$env, list(QVEST_SCREEN_QUEUE_NORUN = "1",
                                 QVEST_LEAN_REGISTER = "0"))), st$jobs_dir, config$per_attempt_secs)
    if (!isTRUE(w$ok)) { rl_log("  ② arm %s 실패: %s", a, w$error %|N|% "?"); next }
    ## ★argmax 로 고르므로 sweep — DSR 게이트가 걸리고 n_trials 가 누적된다.
    cells[[lbl]] <- rl_cell(file.path(RL_ROOT, w$bt_result_path), "daily_native", lbl,
                            n_trials_cumulative = st$n_trials, selection_type = "sweep",
                            out_dir = w$out_dir, secs = w$secs,
                            extra = list(weight_method = a, hurdle_grade = w$hurdle_grade,
                                         hurdle_score = w$hurdle_score))
    st$spent <- st$spent + (w$secs %|N|% 0)
  }
  list(rung = "rung2_weights", status = if (length(cells)) "MEASURED" else "NO_CELL",
       selection_type = "sweep", arms = arms_spec$arms, arms_source = arms_spec$source, cells = cells)
}

rl_rung3_overlay <- function(cand, config, st) {
  lbl <- "rung3_overlay"
  w <- rl_run_worker(list(
    kind = "overlay", label = paste0(cand$candidate_id, "_", lbl),
    candidate_id = cand$candidate_id,
    ## ★캐리어는 **현재 최선 구성**이다 — ①/②에서 이겼으면 그 산출물이 base 가 된다.
    ##   manifest_path 는 drain_resolve_adapter 의 폴백 경로에만 쓰이므로 같이 옮긴다
    ##   (안 옮기면 폴백이 조용히 원 base 로 되돌아가 "무엇을 쟀는지"가 갈린다).
    manifest_path = st$best_config$manifest_path %|N|% cand$manifest_path,
    bt_result_path = st$best_config$bt_result_path, pin_tag = cand$pin_tag, cost_bps = 15,
    n_trials = st$n_trials,
    out_root = file.path(config$out_root, cand$candidate_id, lbl),
    ## ★v9.21: ③칸은 drain_run_candidate 만 타므로 register_module 경로가 없다(누수 4건이
    ##   ①②칸뿐인 것과 일치). 그래도 방어적으로 건다 — 이 칸은 오버레이 큐를 **소비**하므로
    ##   같은 회차에 큐를 건드리면 자기입력이 된다.
    env = list(QVEST_SCREEN_QUEUE_NORUN = "1", QVEST_LEAN_REGISTER = "0")),
    st$jobs_dir, config$per_attempt_secs)
  if (!isTRUE(w$ok))
    return(list(rung = "rung3_overlay", status = "FAILED", reason = as.character(w$error %|N|% "?"), cells = list()))
  st$spent <- st$spent + (w$secs %|N|% 0)

  cl <- w$cells
  if (is.data.frame(cl)) cl <- split(cl, seq_len(nrow(cl)))
  cells <- list(); bare <- NULL
  for (c0 in cl) {
    if (!identical(as.character(c0$status), "OK")) {
      rl_log("  ③ 시나리오 %s 재구성 실패: %s", c0$scenario, as.character(c0$reason %|N|% "?")); next
    }
    cell <- list(label = paste0("rung3_", c0$scenario), basis = "monthly_recon",
                 grade = as.character(c0$grade), SR = as.numeric(c0$SR), IR = as.numeric(c0$IR),
                 MDD = as.numeric(c0$MDD), Calmar = as.numeric(c0$Calmar), CAGR = as.numeric(c0$CAGR),
                 PORT_t = as.numeric(c0$PORT_t), out_dir = as.character(c0$out_dir),
                 scenario = as.character(c0$scenario), secs = NA_real_,
                 selection_type = "sweep", n_trials_cumulative = st$n_trials)
    cells[[cell$label]] <- cell
    if (identical(as.character(c0$scenario), "bare")) bare <- cell
  }
  ## ★bare monthly_recon 대조 의무 — 같은 basis 안에서만 증분을 주장한다.
  if (is.null(bare))
    return(list(rung = "rung3_overlay", status = "NO_BARE_RECON",
                reason = "bare monthly_recon 대조군 부재 — basis 방화벽상 판정 불가", cells = cells,
                drain_verdict = w$drain_verdict))
  best <- NULL; best_d <- NULL
  for (nm in names(cells)) {
    if (identical(cells[[nm]]$scenario, "bare")) next
    d <- rl_delta(cells[[nm]], bare)
    cells[[nm]]$delta_vs_bare_recon <- d
    if (is.null(best) || isTRUE(d$dSR > best_d$dSR)) { best <- cells[[nm]]; best_d <- d }
  }
  dv <- w$drain_verdict
  dv_ok <- identical(as.character(dv$verdict %|N|% ""), "SURVIVOR")
  ess_ok <- isTRUE(best_d$gain)
  list(rung = "rung3_overlay", status = "MEASURED", cells = cells,
       bare_label = bare$label, best_label = if (is.null(best)) NA_character_ else best$label,
       best_delta = best_d, drain_verdict = dv, pit = w$pit,
       ## 판정 = drain_verdict AND essence-on-recon 3축 중 1개 이상.
       ## ★drain_verdict 는 paired_nw_t_lag3 하나만 읽고 dMDD 를 판정에 쓰지 않는다(기록만) —
       ##   오버레이의 존재 이유가 MDD 레버이므로 그 축을 essence-on-recon 이 공급한다.
       gain = isTRUE(dv_ok && ess_ok),
       gain_rule = "drain_verdict==SURVIVOR AND essence(best_recon) vs essence(bare_recon) 3축 중 1개 이상",
       gain_detail = sprintf("drain=%s / essence_gain=%s", dv$verdict %|N|% "?", ess_ok),
       out_root = w$out_root)
}

## ─── 예산 · 재개 ────────────────────────────────────────────────────────────
.rl_budget_left <- function(st) st$budget - (st$spent + as.numeric(difftime(Sys.time(), st$t0, units = "secs")))

## 셀 재개: 완료 셀의 out_dir/bt_result.rds 가 실재하면 **백테를 재실행하지 않는다**.
##   원장은 out_dir 과 secs 를 찾는 데만 쓰고, 지표는 저장된 bt_result 에서 다시 읽는다
##   (원장 JSON 왕복이 스칼라를 length-1 리스트로 만들어 rl_delta 의 산술을 깨뜨린다 —
##    "값을 원장에서 되읽는다"는 타입 계약을 코드로 강제할 수 없으므로 계약 파일에서 잰다).
##   secs 는 원장 값을 그대로 보존한다 — 재개 검증이 "완료 칸 secs 불변"을 본다.
.rl_reuse_cell <- function(st, cand, label, selection_type = "chain", extra_add = list()) {
  prev <- st$prev_cells[[label]]
  od <- if (is.null(prev)) "" else as.character(prev$out_dir %|N|% "")[1]
  btp <- if (nzchar(od)) file.path(RL_ROOT, od, "bt_result.rds") else ""
  if (!nzchar(btp) || !file.exists(btp)) {
    ## 라벨이 내용 주소이므로 디렉터리 글롭 재개가 안전하다(.rl_tag / .rl_cfg_tag 참조).
    g <- Sys.glob(file.path(RL_ROOT, st$cfg_out_root, cand$candidate_id, label, "*", "bt_result.rds"))
    if (!length(g)) return(NULL)
    btp <- g[1]; od <- .rl_rel(dirname(g[1]))
  }
  extra <- c(list(resumed = TRUE), extra_add)
  if (!is.null(prev$hurdle_grade)) extra$hurdle_grade <- as.character(prev$hurdle_grade)[1]
  rl_cell(btp, "daily_native", label,
          n_trials_cumulative = st$n_trials, selection_type = selection_type,
          out_dir = od, secs = as.numeric(prev$secs %|N|% NA), extra = extra)
}

## ─── 후보 1건 완주 ──────────────────────────────────────────────────────────
rl_run_candidate <- function(cand, pool, config, arms_spec, dry_run = FALSE) {
  cid <- cand$candidate_id
  led <- rl_ledger_read()
  prev <- led$runs[[cid]]
  prev_cells <- list()
  if (!is.null(prev$cells)) for (nm in names(prev$cells)) prev_cells[[nm]] <- prev$cells[[nm]]

  st <- new.env(parent = emptyenv())
  st$t0 <- Sys.time()
  st$spent <- as.numeric(prev$spent_secs %|N|% 0)          # ★재개 시 리셋 금지 — 누적 지속
  st$budget <- config$budget_secs_per_candidate
  st$n_trials <- as.integer(prev$n_trials %|N|% 1L)        # base 자신이 1
  st$prev_cells <- prev_cells
  st$cfg_out_root <- config$out_root
  st$jobs_dir <- file.path(RL_ROOT, config$out_root, cid, "_jobs")
  st$best_config <- list(engine = cand$engine, weight_method = cand$weight_method,
                         env = list(), bt_result_path = cand$bt_result_path,
                         manifest_path = cand$manifest_path)

  base_cell <- rl_cell(file.path(RL_ROOT, cand$bt_result_path), "daily_native", "base",
                       n_trials_cumulative = 1L, selection_type = "chain",
                       out_dir = cand$run_dir,
                       extra = list(hurdle_grade = cand$grade, engine = cand$engine,
                                    weight_method = cand$weight_method))
  cells <- list(base = base_cell)
  st$best <- base_cell
  rl_log("후보 %s | base essence=%s (hurdle=%s) SR %.3f MDD %.3f IR %.3f | 진입 %s IR %.3f t %.3f",
         cid, base_cell$grade, cand$grade, base_cell$SR, base_cell$MDD, base_cell$IR,
         cand$entry_regime, cand$entry_ir, cand$entry_strength)

  rec <- list(candidate_id = cid, rule = RL_ENTRY_RULE, rcma_c3_oos = "not_evaluated",
              entry = list(regime = cand$entry_regime, active_ir = cand$entry_ir,
                           active_t = cand$entry_strength, n_months = cand$entry_n_months,
                           dup_sig = cand$dup_sig, ip_score = cand$ip_score, pin_tag = cand$pin_tag),
              base = list(engine = cand$engine, weight_method = cand$weight_method,
                          hurdle_grade = cand$grade, bt_result_path = cand$bt_result_path),
              started_at = as.character(prev$started_at %|N|% format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")),
              stage = "base_measured", cells = cells, rungs = list(),
              spent_secs = st$spent, n_trials = st$n_trials, target_grade = config$target_grade)
  if (!dry_run) rl_ledger_upsert(cid, rec)

  strikes <- 0L; rungs <- list()
  .flush <- function(stage) {
    rec$stage <<- stage; rec$cells <<- cells; rec$rungs <<- rungs
    rec$spent_secs <<- st$spent + as.numeric(difftime(Sys.time(), st$t0, units = "secs"))
    rec$n_trials <<- st$n_trials
    rec$best <<- list(label = st$best$label, grade = st$best$grade, basis = st$best$basis)
    rec$updated_at <<- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
    if (!dry_run) rl_ledger_upsert(cid, rec)        # ★칸마다 flush = 재개점
  }
  .target_hit <- function() .rl_grade_rank(st$best$grade) <= .rl_grade_rank(config$target_grade)

  ## ── ①칸 ────────────────────────────────────────────────────────────────
  if (!rl_stop_requested() && !.target_hit() && .rl_budget_left(st) > 0) {
    r1 <- rl_rung1_composite(cand, pool, config, st)
    for (nm in names(r1$cells)) {
      cells[[nm]] <- r1$cells[[nm]]
      cells[[nm]]$delta_vs_base <- rl_delta(r1$cells[[nm]], base_cell)
    }
    win <- .rl_pick_best(r1$cells, base_cell)
    r1$best_label <- if (is.null(win)) NA_character_ else win$label
    r1$gain <- !is.null(win) && isTRUE(cells[[win$label]]$delta_vs_base$gain)
    if (!is.null(win) && .rl_grade_rank(win$grade) < .rl_grade_rank(st$best$grade)) st$best <- win
    if (isTRUE(r1$gain) && !is.null(win)) {
      st$best <- win
      st$best_config <- list(engine = RL_COMPOSITE_ENGINE, weight_method = cand$weight_method,
                             env = list(COMPOSITE_MEMBERS = paste(win$members, collapse = ","),
                                        COMPOSITE_MIN_MEMBERS = "2",
                                        COMPOSITE_TOP_N = as.character(cand$n_holdings)),
                             bt_result_path = file.path(win$out_dir, "bt_result.rds"),
                             manifest_path = file.path(win$out_dir, "strategy_manifest.json"))
    } else if (.rl_measured(r1)) strikes <- strikes + 1L
    rungs[["rung1"]] <- r1
    rl_log("① composite: %s · gain=%s · strikes=%d%s", r1$status, isTRUE(r1$gain), strikes,
           if (!.rl_measured(r1)) " (미측정 — strike 미계상)" else "")
    .flush("rung1_done")
  } else rl_log("① composite 생략 (stop=%s target_hit=%s budget_left=%.0fs)",
                rl_stop_requested(), .target_hit(), .rl_budget_left(st))

  ## ── ②칸 ────────────────────────────────────────────────────────────────
  if (!rl_stop_requested() && !.target_hit() && strikes < config$strike_limit && .rl_budget_left(st) > 0) {
    r2 <- rl_rung2_weights(cand, config, st, arms_spec)
    ref <- st$best
    for (nm in names(r2$cells)) {
      cells[[nm]] <- r2$cells[[nm]]
      cells[[nm]]$delta_vs_ref <- rl_delta(r2$cells[[nm]], ref)
    }
    win <- .rl_pick_best(r2$cells, ref)
    r2$best_label <- if (is.null(win)) NA_character_ else win$label
    r2$gain <- !is.null(win) && isTRUE(cells[[win$label]]$delta_vs_ref$gain)
    if (isTRUE(r2$gain) && !is.null(win)) {
      st$best <- win
      st$best_config$weight_method <- win$weight_method
      st$best_config$bt_result_path <- file.path(win$out_dir, "bt_result.rds")
      st$best_config$manifest_path  <- file.path(win$out_dir, "strategy_manifest.json")
      strikes <- 0L
    } else if (.rl_measured(r2)) strikes <- strikes + 1L
    rungs[["rung2"]] <- r2
    rl_log("② weights: %s · arms=[%s] (%s) · gain=%s · strikes=%d%s", r2$status,
           paste(arms_spec$arms, collapse = ","), arms_spec$source, isTRUE(r2$gain), strikes,
           if (!.rl_measured(r2)) " (미측정 — strike 미계상)" else "")
    .flush("rung2_done")
  } else rl_log("② weights 생략 (stop=%s target_hit=%s strikes=%d budget_left=%.0fs)",
                rl_stop_requested(), .target_hit(), strikes, .rl_budget_left(st))

  ## ── ③칸 — ★strike 로 막지 않는다(기본) ────────────────────────────────
  ##   ①(신호)·②(비중)·③(노출)은 다른 축이고 ③은 이 저장소가 유일하게 실증한
  ##   롱온리 β 레버다. config 한 줄(strike_blocks_rung3)로 뒤집을 수 있다.
  blocked3 <- isTRUE(config$strike_blocks_rung3) && strikes >= config$strike_limit
  if (!rl_stop_requested() && !blocked3 && !.target_hit() && .rl_budget_left(st) > 0) {
    r3 <- rl_rung3_overlay(cand, config, st)
    for (nm in names(r3$cells)) cells[[nm]] <- r3$cells[[nm]]
    rungs[["rung3"]] <- r3
    rl_log("③ overlay: %s · gain=%s (%s)", r3$status, isTRUE(r3$gain),
           as.character(r3$gain_detail %|N|% r3$reason %|N|% ""))
    .flush("rung3_done")
  } else {
    rl_log("③ overlay 생략 (stop=%s blocked=%s target_hit=%s budget_left=%.0fs)", rl_stop_requested(),
           blocked3, .target_hit(), .rl_budget_left(st))
    .flush(if (rl_stop_requested()) "stopped" else "rung3_skipped")
  }

  rec$final <- list(best_label = st$best$label, best_grade = st$best$grade, best_basis = st$best$basis,
                    target_grade = config$target_grade, target_hit = .target_hit(),
                    strikes = strikes, stopped_by_file = rl_stop_requested(),
                    budget_left_secs = round(.rl_budget_left(st)))
  rec$stage <- if (rl_stop_requested()) "stopped" else "done"
  rec$cells <- cells; rec$rungs <- rungs

  ## ★v9.21 §2-e — 승자를 전략 로테이션 풀에 정식 등재한다.
  ##   중간 arm 은 QVEST_LEAN_REGISTER=0 으로 막았으므로, 여기서 열지 않으면 강화 산출물이
  ##   풀에 영원히 못 들어간다. target_hit 여부와 **무관**하게 등재한다 —
  ##   RCMA(regime_module_admission)는 등급이 아니라 국면조건부 성과로 판정하므로
  ##   목표 미달이어도 국면 specialist 로는 쓸모가 있다(AX-001 과 같은 논리).
  ##   특혜는 없다: 1단계와 같은 floor 를 타고, 미달이면 register_module 이 quarantine 으로 보낸다.
  if (!dry_run) {
    reg <- tryCatch(rl_register_winner(cand, st, cells, config),
                    error = function(e) list(status = "FAILED", error = conditionMessage(e)))
    rec$registration <- reg
    rl_log("승자 등재: %s | %s → %s%s", reg$status %|N|% "?", reg$label %|N|% "-",
           reg$registry %|N|% "-",
           if (!is.null(reg$reason) && !is.na(reg$reason)) sprintf(" (%s)", reg$reason) else "")
  }
  rec$spent_secs <- st$spent + as.numeric(difftime(Sys.time(), st$t0, units = "secs"))
  rec$n_trials <- st$n_trials
  if (!dry_run) {
    rl_ledger_upsert(cid, rec)
    .rl_write_table(cid, cells, config)
  }
  rec
}

## 등급 우선, 동률이면 SR — 판정 등급은 essence(자본 층과 같은 잣대)
.rl_pick_best <- function(cellset, ref) {
  best <- NULL
  for (nm in names(cellset)) {
    c0 <- cellset[[nm]]
    if (is.null(best)) { best <- c0; next }
    gr <- .rl_grade_rank(c0$grade); gb <- .rl_grade_rank(best$grade)
    if (gr < gb || (gr == gb && isTRUE(c0$SR > best$SR))) best <- c0
  }
  best
}

.rl_write_table <- function(cid, cells, config) {
  .pick_delta <- function(c0) {
    for (k in c("delta_vs_base", "delta_vs_ref", "delta_vs_bare_recon"))
      if (!is.null(c0[[k]])) return(c0[[k]])
    NULL
  }
  rows <- rbindlist(lapply(names(cells), function(nm) {
    c0 <- cells[[nm]]
    d <- .pick_delta(c0)
    data.table(
      candidate_id = cid,
      basis = as.character(c0$basis),           # ★첫 지표 열이 basis다 (위험 R1)
      cell = as.character(c0$label), grade = as.character(c0$grade %|N|% NA),
      SR = as.numeric(c0$SR %|N|% NA), MDD = as.numeric(c0$MDD %|N|% NA),
      Calmar = as.numeric(c0$Calmar %|N|% NA), IR = as.numeric(c0$IR %|N|% NA),
      CAGR = as.numeric(c0$CAGR %|N|% NA), PORT_t = as.numeric(c0$PORT_t %|N|% NA),
      selection_type = as.character(c0$selection_type %|N|% NA),
      n_trials = as.integer(c0$n_trials_cumulative %|N|% NA),
      ref = if (is.null(d)) NA_character_ else as.character(d$ref_label),
      dSR = if (is.null(d)) NA_real_ else as.numeric(d$dSR),
      dMDD = if (is.null(d)) NA_real_ else as.numeric(d$dMDD),
      dIR = if (is.null(d)) NA_real_ else as.numeric(d$dIR),
      gain = if (is.null(d)) NA else isTRUE(d$gain),
      hurdle_proxy = as.character(c0$hurdle_grade %|N|% NA),   # 참고만 — 판정은 essence
      secs = as.numeric(c0$secs %|N|% NA), out_dir = as.character(c0$out_dir %|N|% NA))
  }), fill = TRUE)
  p1 <- file.path(RL_ROOT, config$out_root, cid, "ladder_table.csv")
  dir.create(dirname(p1), recursive = TRUE, showWarnings = FALSE)
  fwrite(rows, p1)
  p2 <- file.path(RL_ROOT, config$out_root, "ladder_table.csv")
  # ★재개 멱등 (2026-08-24): 롤업은 후보별 블록을 누적하되 **같은 후보의 구 블록은 교체**한다.
  #   구판은 무조건 append 라 재개 1회마다 같은 후보가 한 벌 더 쌓였다 — 실측 12행 → 24행이고
  #   측정치 18/20 컬럼이 동일했다(다른 건 n_trials 2→3 과 secs 부동소수 왕복뿐). 표를 읽는
  #   쪽에서는 "arm 이 두 배"로 보이므로 보고가 조용히 틀린다. 후보 간 누적은 그대로 유지한다.
  prev <- if (file.exists(p2)) tryCatch(fread(p2, showProgress = FALSE), error = function(e) NULL) else NULL
  if (!is.null(prev) && nrow(prev) && "candidate_id" %in% names(prev))
    prev <- prev[as.character(candidate_id) != as.character(cid)]
  out2 <- if (is.null(prev) || !nrow(prev)) rows else rbindlist(list(prev, rows), fill = TRUE)
  fwrite(out2, p2)
  invisible(rows)
}

## ─── 강화 승자의 정식 풀 진입 (v9.21 §2-e) ──────────────────────────────────
##
## 왜 있나: 사다리 중간 arm 은 module_quarantine 으로 새고 있었고(QVEST_LEAN_REGISTER=0 으로
##   차단), 그렇다고 막기만 하면 **강화 산출물이 전략 로테이션 풀에 영원히 못 들어간다.**
##   Track2 소비원은 둘뿐이다(build_module_performance.R:8-9):
##     ① module_catalog fr_eligible=true + metric_type=backtested + contract_pass  ← 1단계 272건
##     ② legacy QEPM grade_a_catalog (catalog 에 **없는** 구세대만)                  ← QEPM 12건
##   2단계(강화) 자리가 없다. 이 함수가 그 자리다 — **막는 것은 중간 arm, 여는 것은 최종 승자.**
##
## 계약: 특혜 없음. 1단계와 **같은 floor**(register_module.R::.eligibility_reason)를 그대로 탄다.
##   floor 미달이면 register_module 이 알아서 quarantine 으로 보낸다(allow_quarantine 기본 TRUE).
##   ★contract_pass 를 **선언하지 않는다** — bt_contract_status.json 의 실측
##     (status=="OK" ∧ audit_fail==0 ∧ metric_type=="backtested")으로만 TRUE 가 된다.
##   ★base 가 승자면 등재하지 않는다 — 개선이 없었고, base 는 자기 lean 라운드로 이미 풀에 있다.
##   ★등급 NA(계약 미경유)면 등재하지 않는다 — 하네스 밖 성과는 유효하지 않다(AX-002).
rl_register_winner <- function(cand, st, cells, config, dry_run = FALSE) {
  lbl <- as.character(st$best$label %|N|% "")
  if (!nzchar(lbl) || identical(lbl, "base"))
    return(list(status = "SKIPPED_BASE", label = lbl,
                note = "승자가 base — 개선 없음. base 는 자기 lean 라운드로 이미 등재됨"))
  cell <- cells[[lbl]]
  if (is.null(cell)) return(list(status = "SKIPPED_NO_CELL", label = lbl))
  if (is.na(cell$grade) || !nzchar(as.character(cell$grade)))
    return(list(status = "SKIPPED_NO_GRADE", label = lbl,
                note = "권위 등급 미산출(계약 미경유) — AX-002"))

  run_dir <- file.path(RL_ROOT, as.character(cell$out_dir))
  btp <- file.path(run_dir, "bt_result.rds")
  bcs <- file.path(run_dir, "bt_contract_status.json")
  if (!file.exists(btp)) return(list(status = "SKIPPED_NO_BT", label = lbl, dir = cell$out_dir))

  ct <- if (file.exists(bcs)) tryCatch(fromJSON(bcs, simplifyVector = TRUE), error = function(e) NULL) else NULL
  contract_ok <- isTRUE(identical(as.character(ct$status %|N|% ""), "OK")) &&
                 isTRUE(identical(as.character(ct$metric_type %|N|% ""), "backtested")) &&
                 isTRUE(as.integer(ct$audit_fail %|N|% 1L) == 0L)
  sid <- as.character(ct$strategy_id %|N|% basename(run_dir))

  ## bt_result → register_module 최소 sim (DAILY_NAV_DT + bm_xts). 재구성기는 이미 있다 —
  ## backfill_lean_modules.R::bl_sim_from_bt (lean 런에 sim_result.rds 가 없어서 만든 것).
  ## 그 파일은 `.bl_invoked_directly()` 가드가 있어 source 해도 CLI 가 안 돈다.
  out <- tryCatch({
    .rl_source_once("02_Infrastructure/ops/backfill_lean_modules.R", "bl_sim_from_bt")
    .rl_source_once("02_Infrastructure/contracts/register_module.R", "register_module")
    sim <- bl_sim_from_bt(readRDS(btp))

    base_cell <- cells[["base"]]
    dl <- if (!is.null(base_cell)) tryCatch(rl_delta(cell, base_cell), error = function(e) NULL) else NULL

    register_module(
      sim, sid,
      grade       = as.character(cell$grade),
      origin_mode = "reinforce_ladder",          # ★1·2단계 산출을 풀에서 구분 가능하게
      role        = NA_character_,
      meta = list(
        strategy_name = sprintf("LADDER/%s/%s", cand$candidate_id, lbl),
        ladder_ref = list(base_candidate = cand$candidate_id, rung = lbl,
                          entry_regime = cand$entry_regime, entry_ir = cand$entry_ir,
                          dSR = dl$dSR %|N|% NA, dMDD = dl$dMDD %|N|% NA, dIR = dl$dIR %|N|% NA,
                          target_grade = config$target_grade,
                          target_hit = .rl_grade_rank(cell$grade) <= .rl_grade_rank(config$target_grade)),
        essence_grade = as.character(cell$grade),
        selection_type = as.character(cell$selection_type %|N|% NA),
        n_trials_cumulative = as.integer(cell$n_trials_cumulative %|N|% NA),
        basis = as.character(cell$basis %|N|% NA),
        bt_contract_status = as.character(ct$status %|N|% "UNKNOWN")),
      metric_type        = "backtested",
      contract_pass      = contract_ok,          # ★선언 아님 — 위에서 실측
      frozen             = TRUE,
      source_contract_id = as.character(ct$run_id %|N|% sid),
      build_version      = "reinforce_ladder_v9.21",
      cost_model_version = "v2.4_delta_15bps",
      bt_result_path     = .rl_rel(btp))
  }, error = function(e) e)

  if (inherits(out, "error"))
    return(list(status = "FAILED", label = lbl, strategy_id = sid, error = conditionMessage(out)))
  list(status = "REGISTERED", label = lbl, strategy_id = sid,
       fr_eligible = isTRUE(out$fr_eligible), contract_pass = contract_ok,
       registry = if (isTRUE(out$fr_eligible)) "module_catalog" else "module_quarantine",
       reason = as.character(out$eligibility_reason %|N|% out$reason %|N|% NA))
}

## ─── 종료 보고 (close_round 1회 + tg_agent_brief 1회) ───────────────────────
.rl_finalize <- function(results, cand_tbl, config, send_tg = TRUE, write_marker = TRUE) {
  if (!length(results)) return(invisible(NULL))
  ids <- vapply(results, function(r) r$candidate_id, "")
  gains <- vapply(results, function(r) isTRUE(r$final$target_hit), logical(1))
  best_lbl <- vapply(results, function(r) as.character(r$final$best_label %|N|% "?"), "")
  best_gr  <- vapply(results, function(r) as.character(r$final$best_grade %|N|% "?"), "")

  mech <- sprintf(paste0("사다리 %d후보: %s. 진입은 국면별 IR(ladder_entry_v1: IR>=0.5 · n>=12m · |t|>=2 · 부호 강제)이고 ",
                         "RCMA c3_oos 는 미평가다(ip 가 IS/OOS 를 분할하지 않음 — RCMA-admitted 아님). ",
                         "판정은 essence 등급이며 basis(daily_native/monthly_recon)가 다른 셀은 비교하지 않았다 — ",
                         "월간 재구성만으로 MDD 가 9.07pp 개선되기 때문이다."),
                  length(results), paste(sprintf("%s→%s(%s)", ids, best_gr, best_lbl), collapse = ", "))
  probes <- c(
    "②칸 화이트리스트 20종 중 미측정 arm 을 다음 라운드에서 태운다(같은 base, 비중 축만 이동 — sweep 누적 n_trials 상속).",
    "regime_tilt·regime_softmax·ic_tilt 의 regime_dt/ic_history 배선을 복구해 하드 제외 3종을 화이트리스트로 되돌린다(현재는 조용한 국면 중립 퇴화).",
    "③칸 SURVIVOR 시나리오를 daily_native basis 로 재현해 basis 착시가 아닌 실이득분을 분리한다.")
  cs <- c("06_Registry/reinforce_ladder_ledger.json",
          file.path(config$out_root, "ladder_table.csv"),
          "06_Registry/improvement_potential.json")
  lt <- c("weight_sweep_plan.json 에 신규 arm 이 등재되면 ②칸 재기동",
          "regime_dt 배선 복구 시 하드 제외 3종 재측정",
          "ip 신규 available 항목이 진입 문턱을 넘으면 자동 재진입")
  vt <- if (any(gains)) "capability_established" else "screen_tier_routed"

  tryCatch({
    .rl_source_once("02_Infrastructure/contracts/close_round.R", "close_round")
    if (exists("close_round", mode = "function"))
      close_round(round_id = sprintf("RL_%s", format(Sys.time(), "%Y%m%d_%H%M%S")),
                  verdict_type = vt, mechanism_diagnosis = mech, next_probes = probes,
                  consumer_surfaces = cs, live_trigger = lt, layer = "research",
                  evidence_refs = c(RL_LEDGER_REL, file.path(config$out_root, "ladder_table.csv")),
                  write_marker = isTRUE(write_marker))
  }, error = function(e) rl_log("close_round 실패(비치명): %s", conditionMessage(e)))

  if (!isTRUE(send_tg)) return(invisible(NULL))
  tryCatch({
    .rl_source_once("02_Infrastructure/telegram/telegram_notify.R", "tg_agent_brief")
    if (!exists("tg_agent_brief", mode = "function")) return(invisible(NULL))
    kv <- as.list(setNames(sprintf("%s · %s", best_gr, best_lbl), ids))
    kv[["진입규칙"]] <- sprintf("%s (국면별 IR · RCMA c3 미평가)", RL_ENTRY_RULE)
    kv[["자격/진입"]] <- sprintf("%d / %d (중복 %d 제거)", attr(cand_tbl, "n_eligible") %|N|% nrow(cand_tbl),
                                 length(results), attr(cand_tbl, "n_dup") %|N|% 0L)
    tg_agent_brief(
      agent = "ReinforceLadder",
      title = sprintf("강화 사다리 %d후보 완주", length(results)),
      sections = list(
        list(type = "summary", emoji = "\U0001FA9C",
             body = paste0("낮은 등급이라도 국면별 신호가 남아 있는 전략을 골라 팩터 결합·비중 방법론·",
                           "리스크 오버레이 순서로 자동으로 강화해 보았습니다. 각 칸의 결과는 원장과 표에 남았습니다.")),
        list(type = "kv", emoji = "\U0001F4CA", heading = "결과", kv = kv),
        list(type = "text", emoji = "\U26A0\UFE0F", heading = "해석 주의",
             body = paste0("오버레이 칸의 수치는 월간 재구성(monthly_recon) 기준입니다. 월간 계열은 월중 저점을 ",
                           "보지 못해 낙폭이 실제보다 작게 나오므로, 원판(일간) 수치와 직접 비교하면 안 됩니다. ",
                           "이 판정은 연구 층이며 자본 편입 판단이 아닙니다."))),
      lock_scope = sprintf("reinforce_ladder_%s", format(Sys.Date(), "%Y%m%d")))
  }, error = function(e) rl_log("tg_agent_brief 실패(비치명): %s", conditionMessage(e)))
  invisible(NULL)
}

## ─── main ───────────────────────────────────────────────────────────────────
rl_main <- function(args = character(0)) {
  getopt <- function(k, d = NULL) {
    h <- grep(paste0("^--", k, "="), args, value = TRUE)
    if (!length(h)) d else sub(paste0("^--", k, "="), "", h[1])
  }
  dry_run <- "--dry-run" %in% args
  list_only <- "--list-candidates" %in% args
  send_tg <- !("--no-telegram" %in% args) && !dry_run

  config <- rl_config(getopt("config"))
  ## --redo: 원장 완주(stage=done) 후보도 다시 태운다(명시 재측정).
  ##   ★반드시 rl_candidates() **앞**에 있어야 한다 — 뒤에 두면 플래그가 죽는다
  ##     (2026-08-24 돌연변이 통제가 실제로 그 죽은 판을 잡았다: --redo 를 줘도 배제가 안 풀렸다).
  if ("--redo" %in% args) config$redo_completed <- TRUE
  if (!is.null(getopt("per-attempt-secs"))) config$per_attempt_secs <- as.integer(getopt("per-attempt-secs"))
  if (!is.null(getopt("rung1-max")))        config$rung1_max_attempts <- as.integer(getopt("rung1-max"))
  if (!is.null(getopt("budget-secs")))      config$budget_secs_per_candidate <- as.integer(getopt("budget-secs"))
  if (!is.null(getopt("out-root")))         config$out_root <- getopt("out-root")

  if (!dry_run) {
    .RL_LOGFILE <<- file.path(RL_ROOT, config$out_root, "reinforce_ladder.log")
    dir.create(dirname(.RL_LOGFILE), recursive = TRUE, showWarnings = FALSE)
  }
  rl_log("%s | config=%s | out_root=%s | dry_run=%s", RL_VERSION, config$`_source`, config$out_root, dry_run)

  if (!isTRUE(config$enabled)) { rl_log("enabled=false (kill switch) — 종료"); return(invisible(NULL)) }
  if (rl_stop_requested()) { rl_log("stop 파일 존재(%s) — 종료", RL_STOP_REL); return(invisible(NULL)) }

  cs <- rl_candidates(config)
  CT <- cs$table
  rl_log("ip available=%d | 자격 셀 후보=%d | dup_sig 중복 제거 %d → 진입 가능 %d",
         cs$n_available, cs$n_eligible, cs$n_dup_dropped, cs$n_taken)
  if (!nrow(CT)) { rl_log("진입 후보 0건 — 종료(빈 결과 = 합격 아님, 문턱 미달일 뿐)"); return(invisible(NULL)) }

  if (list_only) {
    show <- CT[, .(candidate_id, entry_regime, entry_ir = round(entry_ir, 3),
                   entry_t = round(entry_strength, 3), n_m = entry_n_months,
                   hurdle = grade, engine = basename(engine), wm = weight_method, dup_sig)]
    print(show, nrows = 200L)
    if (cs$n_dup_dropped > 0L) {
      cat(sprintf("\n-- dup_sig 중복 제거 %d건 (동일 국면·표본·IR·t = 같은 셀의 중복 계상) --\n", cs$n_dup_dropped))
      print(cs$dropped[, .(candidate_id, dup_sig)], nrows = 50L)
    }
    if (nrow(cs$cells)) {
      byL <- cs$cells[, .N, by = regime][order(-N)]
      cat(sprintf("\n[자격 셀] %d (%s) — ★셀과 후보는 다른 분모다(한 후보가 여러 국면에서 자격 가능)\n",
                  nrow(cs$cells), paste(sprintf("%s %d", byL$regime, byL$N), collapse = " / ")))
    }
    cat(sprintf("
[요약] available=%d eligible_candidates=%d dup_dropped=%d done_excluded=%d taken=%d (max_active=%d)
",
                cs$n_available, cs$n_eligible, cs$n_dup_dropped,
                as.integer(cs$n_done_excluded %|N|% 0L), cs$n_taken, config$max_active))
    ## ★배제를 침묵시키지 않는다 — "후보가 없다"와 "이미 다 태웠다"는 다른 상태다.
    if (as.integer(cs$n_done_excluded %|N|% 0L) > 0L)
      cat(sprintf("        (원장 완주 %d건 배제: %s%s — 재측정하려면 --redo)
",
                  length(cs$done_ids), paste(head(cs$done_ids, 3), collapse = ", "),
                  if (length(cs$done_ids) > 3L) ", ..." else ""))
    cat("[규칙] ladder_entry_v1 — RCMA c1/c2/c4 재사용 + c0_sign 신설 · rcma_c3_oos=not_evaluated (RCMA-admitted 아님)\n")
    cat("[주의] RISK_OFF 는 unified_regime_signal 에서 월 0(공집합) — 이 국면 미진입은 '측정 안 됨'이지 통과가 아니다\n")
    return(invisible(CT))
  }

  top <- as.integer(getopt("top", config$max_active))
  top <- max(1L, min(top, config$max_active, nrow(CT)))
  only <- getopt("candidate")
  if (!is.null(only)) CT <- CT[candidate_id == only]
  if (!nrow(CT)) { rl_log("--candidate=%s 미해당 — 종료", only); return(invisible(NULL)) }
  CT <- CT[seq_len(min(top, nrow(CT)))]

  arms_spec <- rl_weight_arms(config, override = {
    a <- getopt("rung2-arms")
    if (is.null(a)) NULL else trimws(strsplit(a, ",", fixed = TRUE)[[1]])
  })
  rl_log("②칸 arms=[%s] (source=%s, 가용 %d)", paste(arms_spec$arms, collapse = ","),
         arms_spec$source, arms_spec$n_available)

  if (!dry_run && !rl_lock_acquire()) {
    rl_log("다른 사다리 인스턴스가 실행 중(뮤텍스 %s) — 종료", RL_LOCK_REL); return(invisible(NULL))
  }
  on.exit(if (!dry_run) rl_lock_release(), add = TRUE)

  results <- list()
  for (i in seq_len(nrow(CT))) {
    if (rl_stop_requested()) { rl_log("stop 파일 감지 — 남은 후보 중단"); break }
    r <- tryCatch(rl_run_candidate(as.list(CT[i]), cs$table, config, arms_spec, dry_run = dry_run),
                  error = function(e) { rl_log("후보 %s 실패: %s", CT$candidate_id[i], conditionMessage(e)); NULL })
    if (!is.null(r)) results[[length(results) + 1L]] <- r
  }
  attr(cs$table, "n_eligible") <- cs$n_eligible
  attr(cs$table, "n_dup") <- cs$n_dup_dropped
  if (!dry_run) .rl_finalize(results, cs$table, config, send_tg = send_tg,
                             write_marker = !("--no-marker" %in% args))
  rl_log("완주 %d/%d 후보 — 원장 %s", length(results), nrow(CT), RL_LEDGER_REL)
  invisible(results)
}

## ─── 진입점 (CLI + worker 이중 모드) ────────────────────────────────────────
if (sys.nframe() == 0L && !identical(Sys.getenv("QVEST_RL_NORUN"), "1")) {
  .args <- commandArgs(trailingOnly = TRUE)
  .jobf <- grep("^--job=", .args, value = TRUE)
  if (length(.jobf)) {
    rl_worker(sub("^--job=", "", .jobf[1]))              # worker 모드
  } else if ("--help" %in% .args) {
    cat(paste0("usage: Rscript 02_Infrastructure/ops/reinforce_ladder.R [옵션]\n",
               "  --dry-run --list-candidates    진입 후보만 출력 (쓰기 0)\n",
               "  --top=N                        후보 수 (max_active 상한)\n",
               "  --candidate=<id>               특정 후보만\n",
               "  --rung1-max=N                  ①칸 arm 상한\n",
               "  --rung2-arms=a,b,c             ②칸 arm 직접 지정 (화이트리스트 강제)\n",
               "  --per-attempt-secs=N           worker timeout\n",
               "  --budget-secs=N                후보당 예산\n",
               "  --out-root=<path>              산출 루트 (★alpha_search 와 분리 유지)\n",
               "  --no-telegram                  종료 브리프 미발송\n",
               "  --no-marker                    close_round 마커 미발행(검증 실행용 — 정본 큐 불변)\n",
               "  --redo                         원장 완주(stage=done) 후보도 다시 태운다(기본: 배제 = 다음 후보로 전진)
",
               "  --config=<path>                설정 파일\n"))
  } else {
    Sys.setenv(QVEST_SCREEN_QUEUE_NORUN = "1")            # 자식이 스크린 큐를 건드리지 않게 상속
    rl_main(.args)
  }
}
