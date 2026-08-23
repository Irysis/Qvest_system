#==============================================================================
# improvement_potential.R — 개선-여지 평가 어댑터 (Layer 1, L1 자동 스폰 — 도훈 승인 2026-08-16)
#
# 목적: QEPM/alpha-search 미승격 전략(screen_route 라벨 보유분)에 대해
#   "이 신호가 국면조건부로 개선 여지가 있는가"를 실측으로 첨부한다.
#   SOT: 04_Research/01_reports/auto_spawn_orchestration_design_20260816.md Layer 1.
#
# 설계 원칙:
#   - 신규 측정기가 아니라 어댑터 — per-regime 스키마는 build_module_performance.R:163-166,
#     데이터 로더는 overlay_candidate_drain.R 의 adapter 를 재사용한다.
#   - ★vintage pinning 의무(measurement-graduation §7): 국면 라벨 parquet 은
#     pin_cache 경유(read_pinned)로만 읽고 pin_tag 를 블록에 기록한다.
#     (배경: 두 평가기 코드에 pin 강제가 없어 호출자 책임으로 방치돼 있었다 — 어댑터 층에서 봉합)
#   - tier=screen_diagnostic — 자본게이트/graduation 판정 아님. 스폰 우선순위 근거일 뿐.
#   - 미지원 입력(adapter A weights 등)은 available=FALSE + 사유 — 억지 산출 금지
#     (canonical_screen_bt diag_cap_tier 의 available=FALSE 패턴 승계).
#   - ip_v1 score 는 잠정 공식 — 판별력 검증 루프(설계안 §5, 분기별 SURVIVOR율 대조) 전까지
#     스코어 개정 대상임을 score_version 으로 명시.
#
# ip_v1 score 공식 (문서화 — 변경 시 score_version 올릴 것):
#   crisis 측 = Category ∈ {CRISIS, CAUTION} / normal 측 = 그 외 (홀딩월 국면 = 직전월 신호, PIT).
#   score = active_ir_normal + max(0, -active_ir_crisis)
#   해석: "평시/상승에 벤치 상회 ∧ 위기에 하회"일수록 overlay/국면 결합의 개선 여지가 크다
#   (overlay 는 위기 노출을 줄이는 레버이므로, 위기에서 잃는 신호가 결합 이득이 큼).
#   유효 조건: n_months_normal ≥ 24 ∧ n_months_crisis ≥ 6 — 미달 시 score=NA(판정 없음).
#
# Usage:
#   Rscript 02_Infrastructure/regime/improvement_potential.R --backlog      # overlay 큐 전수
#   Rscript 02_Infrastructure/regime/improvement_potential.R --id=<cand_id>
#   Rscript 02_Infrastructure/regime/improvement_potential.R --runs-since=2026-08-23   # alpha-search 런 소급 (v9.2)
#   Rscript 02_Infrastructure/regime/improvement_potential.R --run-dir=<dir>[,<dir>...]
#   (run_alpha_search.R 6d 직후 improvement_potential_for_run(OUT_DIR) 자동 호출 — 비치명)
# ★소급 경로는 pin 1회 공유 + 레지스트리 1회 배치 기록이다(read-modify-write N회 회피).
# ★entries 는 **id-keyed 객체**다(배열 아님) — 소비측 파이썬은 `d['entries'].values()` 로 순회할 것.
#==============================================================================
Sys.setenv(QVEST_DRAIN_NORUN = "1")

.ip_root <- function() {
  cands <- c(Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""),
             "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
  cands <- cands[nzchar(cands)]
  hit <- cands[file.exists(file.path(cands, "02_Infrastructure/hooks/qvest_hook_router.py"))]
  if (!length(hit)) stop("[improvement_potential] project root 미발견")
  hit[1]
}
IP_ROOT <- .ip_root()

# 드레인 어댑터 재사용 (QVEST_DRAIN_NORUN=1 로 CLI 미발화). data.table/jsonlite/arrow 동반 로드.
source(file.path(IP_ROOT, "02_Infrastructure/regime/overlay_candidate_drain.R"))
source(file.path(IP_ROOT, "02_Infrastructure/data/pin_cache.R"))

IP_REGISTRY_REL <- "06_Registry/improvement_potential.json"
IP_UNI_CACHE <- file.path(IP_ROOT, ".cache/unified_regime_signal.parquet")
IP_CRISIS_CATS <- c("CRISIS", "CAUTION")
IP_MIN_NORMAL_M <- 24L
IP_MIN_CRISIS_M <- 6L

# ── 국면 라벨: pin 경유 로드 (§7) ────────────────────────────────────────────
#   같은 날짜 안에서는 동일 pin 재사용 (pin_cache 는 동일 tag 재-pin 거부 — tryCatch 로
#   "이미 pin됨"을 재사용으로 해석). pin_tag 는 블록에 기록.
.ip_pin_uni <- function() {
  tag <- format(Sys.Date(), "ip_%Y%m%d")
  tryCatch(pin_cache(IP_UNI_CACHE, tag), error = function(e) {
    if (!grepl("재-pin|이미|exists", conditionMessage(e))) {
      # 재-pin 거부 외 오류는 실패 — 단 pin 사본이 실재하면 재사용 가능
      pinned <- tryCatch(read_pinned(IP_UNI_CACHE, tag), error = function(e2) NULL)
      if (is.null(pinned)) stop(e)
    }
    invisible(NULL)
  })
  list(tag = tag, path = read_pinned(IP_UNI_CACHE, tag))
}

.ip_load_uni_pinned <- function(pin) {
  as.data.table(read_parquet(pin$path))[
    , .(ym_sig = as.character(YM), Category = as.character(Category))]
}

# ── per-regime 핵심 (pure — 검사기가 이 함수를 때린다) ───────────────────────
#   pr_monthly: data.table(date, ret_net, benchmark_ret) / cat_dt: data.table(Date, Category)
#   홀딩월 국면 = 직전월 신호 (호출측이 drain_build_uni 규약으로 만든 cat_dt 전달).
ip_per_regime <- function(pr_monthly, cat_dt) {
  pr <- as.data.table(copy(pr_monthly))
  pr[, active := ret_net - benchmark_ret]
  pr[as.data.table(cat_dt), on = c(date = "Date"), Category := i.Category]
  pr[is.na(Category), Category := "UNLABELED"]
  pr[, side := fifelse(Category %in% IP_CRISIS_CATS, "crisis", "normal")]
  stat <- function(x) {
    n <- sum(is.finite(x))
    if (n < 2L || stats::sd(x, na.rm = TRUE) == 0)
      return(list(n_months = n, active_ir = NA_real_, active_t = NA_real_, mean_ann = NA_real_))
    ir <- mean(x, na.rm = TRUE) / stats::sd(x, na.rm = TRUE) * sqrt(12)
    list(n_months = n, active_ir = ir, active_t = ir * sqrt(n / 12),
         mean_ann = mean(x, na.rm = TRUE) * 12)
  }
  per_cat <- lapply(split(pr$active, pr$Category), stat)
  s_nor <- stat(pr[side == "normal", active])
  s_cri <- stat(pr[side == "crisis", active])
  eligible <- s_nor$n_months >= IP_MIN_NORMAL_M && s_cri$n_months >= IP_MIN_CRISIS_M &&
              is.finite(s_nor$active_ir) && is.finite(s_cri$active_ir)
  score <- if (eligible) s_nor$active_ir + max(0, -s_cri$active_ir) else NA_real_
  list(per_regime = per_cat,
       normal = s_nor, crisis = s_cri,
       score = score, score_version = "ip_v1",
       score_eligible = eligible,
       score_reason = if (eligible) "ip_v1 = ir_normal + max(0, -ir_crisis)"
                      else sprintf("표본 미달/무정보 (normal %dm < %d 또는 crisis %dm < %d) — 판정 없음",
                                   s_nor$n_months, IP_MIN_NORMAL_M, s_cri$n_months, IP_MIN_CRISIS_M))
}

# ── 후보 1건 평가 (드레인 어댑터 재사용) ─────────────────────────────────────
improvement_potential_entry <- function(entry, pin = NULL) {
  blk_base <- list(id = entry$id %||% NA_character_,
                   tier = "screen_diagnostic", metric_type = "canonical_screen_diag",
                   basis = "스폰 우선순위 근거 — 자본게이트/graduation 판정 아님",
                   computed_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"))
  ad <- drain_resolve_adapter(entry)
  if (!identical(ad$adapter, "bt_result_rds") || is.na(ad$bt_result_path %||% NA)) {
    return(c(blk_base, list(available = FALSE,
      reason = sprintf("adapter=%s — ip_v1 은 bt_result_rds 만 지원 (억지 산출 금지)", ad$adapter))))
  }
  dat <- drain_load_bt_result(ad)
  if (is.null(pin)) pin <- .ip_pin_uni()
  u <- .ip_load_uni_pinned(pin)
  cat_dt <- drain_build_uni(u, dat$dates, extra_lag = 0L)[, .(Date, Category)]
  pr <- dat$pr_monthly
  c(blk_base, list(available = TRUE, adapter = "bt_result_rds",
                   n_months_total = nrow(pr),
                   pin_tag = pin$tag),
    ip_per_regime(pr, cat_dt))
}

# ── 레지스트리 적재 (id-keyed, 원자적 병합 — 기존 항목 보존) ─────────────────
improvement_potential_write <- function(blocks, root = IP_ROOT) {
  rp <- file.path(root, IP_REGISTRY_REL)
  d <- if (file.exists(rp)) tryCatch(fromJSON(rp, simplifyVector = FALSE), error = function(e) NULL) else NULL
  if (is.null(d)) d <- list(schema_version = "improvement_potential_v1",
                            `_doc` = paste("Layer 1 개선-여지 평가 레지스트리 (ip_v1).",
                                           "소비자 = auto_spawn_queue.R (Layer 2).",
                                           "screen_diagnostic — 자본게이트 아님."),
                            entries = list())
  if (is.null(d$entries)) d$entries <- list()
  for (b in blocks) if (nzchar(b$id %||% "")) d$entries[[b$id]] <- b
  d$generated_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  tmp <- paste0(rp, ".tmp", Sys.getpid())
  write_json(d, tmp, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = 6)
  if (file.exists(rp)) suppressWarnings(file.remove(rp))
  if (!isTRUE(suppressWarnings(file.rename(tmp, rp)))) {
    ok <- suppressWarnings(file.copy(tmp, rp, overwrite = TRUE)); suppressWarnings(file.remove(tmp))
    if (!isTRUE(ok)) stop("[improvement_potential] 원자 기록 실패: ", rp)
  }
  invisible(d)
}

# overlay 큐 전수(backlog) 평가
improvement_potential_backlog <- function(root = IP_ROOT) {
  qp <- file.path(root, "06_Registry/overlay_candidate_queue.json")
  if (!file.exists(qp)) stop("[improvement_potential] overlay 큐 부재: ", qp)
  q <- fromJSON(qp, simplifyVector = FALSE)
  cands <- q$candidates %||% list()
  if (!length(cands)) stop("[improvement_potential] 큐 후보 0건 — 빈 결과 = 합격 아님")
  pin <- .ip_pin_uni()
  blocks <- list(); n_ok <- 0L; n_na <- 0L
  for (e in cands) {
    b <- tryCatch(improvement_potential_entry(e, pin = pin), error = function(err) {
      list(id = e$id %||% "?", available = FALSE, tier = "screen_diagnostic",
           reason = paste("평가 실패:", conditionMessage(err)),
           computed_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"))
    })
    blocks[[length(blocks) + 1L]] <- b
    if (isTRUE(b$available)) n_ok <- n_ok + 1L else n_na <- n_na + 1L
  }
  improvement_potential_write(blocks, root)
  cat(sprintf("[improvement_potential] backlog %d건 — 평가 %d / 미지원·실패 %d → %s (pin_tag=%s)\n",
              length(blocks), n_ok, n_na, IP_REGISTRY_REL, pin$tag))
  invisible(blocks)
}

# alpha-search 런 1건 (run_alpha_search.R 6d 직후 호출 — 비치명 tryCatch 는 호출측)
improvement_potential_for_run <- function(out_dir, root = IP_ROOT) {
  mfp <- file.path(out_dir, "strategy_manifest.json")
  if (!file.exists(mfp)) stop("[improvement_potential] manifest 부재: ", mfp)
  m <- fromJSON(mfp, simplifyVector = FALSE)
  entry <- list(id = m$strategy_id %||% paste0("STR_AS_", basename(out_dir)),
                source = "alpha_search_manifest", source_path = mfp,
                bt_result_path = (m$execution %||% list())$bt_result_path %||%
                                 file.path(out_dir, "bt_result.rds"))
  b <- improvement_potential_entry(entry)
  improvement_potential_write(list(b), root)
  cat(sprintf("[improvement_potential] %s — available=%s score=%s\n", entry$id,
              isTRUE(b$available), if (is.null(b$score) || is.na(b$score %||% NA)) "NA"
                                   else sprintf("%.3f", b$score)))
  invisible(b)
}

# ── alpha-search 런 소급 평가 (v9.2 §8-S2 [7], 2026-08-24) ───────────────────
#   왜: run_alpha_search 6d+ 의 구 게이트(deep && screen_pass)가 lean 라운드의 ip 산출을
#   0건으로 봉했다. 게이트를 연 뒤에도 **이미 끝난 런**은 재평가 경로가 없으면 영원히 빈칸이다.
#   ★비용 규율 2가지 — 이 함수의 존재 이유:
#     ① pin 을 1회만 잡아 전 런이 공유한다(.ip_pin_uni 는 호출당 pin_cache 접근).
#     ② 레지스트리 기록을 **1회 배치**로 한다. improvement_potential_write 는 read-modify-write
#        전량 재작성이므로 런마다 부르면 N회 전체 재직렬화가 된다(16런 = 16회).
#   run_dirs: stage_artifacts/alpha_search/<run_id> 디렉터리 벡터.
improvement_potential_run_dirs <- function(run_dirs, root = IP_ROOT) {
  run_dirs <- unique(run_dirs[nzchar(run_dirs)])
  run_dirs <- run_dirs[file.exists(file.path(run_dirs, "strategy_manifest.json"))]
  if (!length(run_dirs))
    stop("[improvement_potential] 대상 런 0건 — strategy_manifest.json 을 가진 디렉터리 없음 (빈 결과 = 합격 아님)")
  pin <- .ip_pin_uni()
  blocks <- list(); n_ok <- 0L; n_na <- 0L
  for (d in run_dirs) {
    b <- tryCatch({
      m <- fromJSON(file.path(d, "strategy_manifest.json"), simplifyVector = FALSE)
      entry <- list(id = m$strategy_id %||% paste0("STR_AS_", basename(d)),
                    source = "alpha_search_manifest",
                    source_path = file.path(d, "strategy_manifest.json"),
                    bt_result_path = (m$execution %||% list())$bt_result_path %||%
                                     file.path(d, "bt_result.rds"))
      improvement_potential_entry(entry, pin = pin)
    }, error = function(err) {
      list(id = paste0("STR_AS_", basename(d)), available = FALSE, tier = "screen_diagnostic",
           reason = paste("평가 실패:", conditionMessage(err)),
           computed_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"))
    })
    blocks[[length(blocks) + 1L]] <- b
    if (isTRUE(b$available)) n_ok <- n_ok + 1L else n_na <- n_na + 1L
  }
  improvement_potential_write(blocks, root)          # ★1회 배치 기록
  cat(sprintf("[improvement_potential] run-dirs %d건 — 평가 %d / 미지원·실패 %d → %s (pin_tag=%s)\n",
              length(blocks), n_ok, n_na, IP_REGISTRY_REL, pin$tag))
  invisible(blocks)
}

# run_id 접두(YYYYMMDD_HHMMSS_PID)로 날짜 필터. since = "YYYY-MM-DD" 또는 "YYYYMMDD".
improvement_potential_runs_since <- function(since, root = IP_ROOT,
                                             stage_root = file.path(root, "stage_artifacts/alpha_search")) {
  since_key <- gsub("-", "", as.character(since)[1])
  if (!grepl("^[0-9]{8}$", since_key)) stop("[improvement_potential] --runs-since 는 YYYY-MM-DD 형식")
  dirs <- Sys.glob(file.path(stage_root, "*"))
  dirs <- dirs[dir.exists(dirs)]
  key <- substr(basename(dirs), 1L, 8L)
  keep <- grepl("^[0-9]{8}$", key) & key >= since_key
  improvement_potential_run_dirs(dirs[keep], root = root)
}

# ── CLI ──────────────────────────────────────────────────────────────────────
if (sys.nframe() == 0L && Sys.getenv("QVEST_IP_NORUN") != "1") {
  args <- commandArgs(trailingOnly = TRUE)
  if ("--backlog" %in% args) {
    improvement_potential_backlog()
  } else if (any(grepl("^--runs-since=", args))) {
    since <- sub("^--runs-since=", "", grep("^--runs-since=", args, value = TRUE)[1])
    improvement_potential_runs_since(since)
  } else if (any(grepl("^--run-dir=", args))) {
    dirs <- sub("^--run-dir=", "", grep("^--run-dir=", args, value = TRUE))
    dirs <- unlist(strsplit(dirs, ",", fixed = TRUE))
    dirs <- ifelse(grepl("^([A-Za-z]:)?[/\\\\]", dirs), dirs, file.path(IP_ROOT, dirs))
    improvement_potential_run_dirs(dirs)
  } else if (any(grepl("^--id=", args))) {
    cid <- sub("^--id=", "", grep("^--id=", args, value = TRUE)[1])
    qp <- file.path(IP_ROOT, "06_Registry/overlay_candidate_queue.json")
    q <- fromJSON(qp, simplifyVector = FALSE)
    hit <- Filter(function(x) identical(x$id, cid), q$candidates %||% list())
    if (!length(hit)) stop("[improvement_potential] 큐에서 id 미발견: ", cid)
    b <- improvement_potential_entry(hit[[1]])
    improvement_potential_write(list(b))
    cat(toJSON(b, auto_unbox = TRUE, pretty = TRUE, na = "null"), "\n")
  } else if (length(args)) {
    cat(paste0("usage: Rscript improvement_potential.R --backlog | --id=<candidate_id>\n",
               "                                       | --runs-since=YYYY-MM-DD | --run-dir=<dir>[,<dir>...]\n"))
  }
}
