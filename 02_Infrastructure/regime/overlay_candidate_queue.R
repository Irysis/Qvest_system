#!/usr/bin/env Rscript
# overlay_candidate_queue.R — screen_route=OVERLAY_CANDIDATE 소비 배관 (감사 CAP-P1-1, SC-03/04)
#
# 문제: 게이트 2계층(measurement-graduation §3)의 screening tier가 OVERLAY_CANDIDATE 라벨을
#       *생산*만 하고(hurdle_gate.R verdict$screening$screen_route → strategy_manifest.json)
#       소비자가 0 — "MDD 구조 사유로 죽었으나 신호 실재" 후보의 재활용 경로가 라벨에서 끊김.
# 역할: 라벨 보유 후보를 전수 수집해 단일 큐(06_Registry/overlay_candidate_queue.json)에 적재.
#       소비자 = overlay A/B 하네스(02_Infrastructure/ops/auto_regime_overlay_ab.R 계열 —
#       첫 케이스 러너는 02_Infrastructure/regime/overlay_candidate_ab_lh.R).
#
# 스캔 소스:
#   ① stage_artifacts/alpha_search/*/strategy_manifest.json (hurdle_gate 라벨 원산지)
#   ② 06_Registry/module_catalog.json + module_quarantine.json meta (register_module 경유분 — 현재 0건, 배관 선설치)
#   ③ manual_entries — 레지스트리 밖 산출물 수동 등재 (첫 케이스: LH/D2 loser-augment, 07-03 메모리 최우선 큐.
#       수치는 D2_forge_result.rds 실측값을 런타임에 읽음 — 손기입 금지)
#   ④ standalone_track_dispositions.json 의 verdict=overlay_routed 처분 (2026-08-17 신설 —
#       /improve-drain R1. 처분 원장을 큐 적재로 잇는 기계 소비자: 이게 없으면 overlay_routed
#       처분이 죽은 주소 선언이 된다 — FR_RCMA "소비자 0" 전례의 재발 방지)
# A/B 실측 결과(06_Registry/overlay_ab_results/<id>.json 존재 시) → 후보에 ab_result 첨부 + status="measured".
#
# 쓰기: 06_Registry/overlay_candidate_queue.json 은 **원자적**으로 기록한다
#   (02_Infrastructure/utils/atomic_json.R::qvest_atomic_write_json — tmp→rename, 선삭제 없음).
#   2026-08-23 v9.1 후속 수리 이전에는 비원자적 write_json 이라, refresh_screen_queues.R 의
#   뮤텍스가 막지 못하는 **수동 동시 실행**에서 소비자가 절단 JSON 을 읽을 수 있었다
#   (같은 계통의 실사고: axiom_context_inject.sh 변동부 통째 소실, 08-23 21:44).
#   ★뮤텍스는 여전히 필요하다 — 원자적 쓰기는 "절단을 안 읽는다"를 보장할 뿐,
#     두 빌더의 lost update(나중 쓴 쪽이 이김)는 막지 않는다. 두 층은 다른 문제를 푼다.
#
# 실행: Rscript 02_Infrastructure/regime/overlay_candidate_queue.R  (재실행 idempotent — 전량 재생성)
suppressMessages({ library(data.table); library(jsonlite) })
`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0 && !all(is.na(a))) a else b
# ── 원자적 JSON 쓰기 정본 부트스트랩 ─────────────────────────────────────────
#   ★코드 루트는 **자기 파일이 실린 트리**다. env(QM_ROOT/CLAUDE_PROJECT_DIR)는 *데이터*
#     루트라 worktree 에서 갈린다 — 실측(2026-08-23): worktree 사본을 source 했는데
#     라이브러리를 main 에서 찾아 "cannot open the connection" 으로 halt
#     (08_Tests/portfolio/test_standalone_track_queue.R 가 적발). r-portability ④-b 의
#     "자기가 실린 트리" 규율이 러너뿐 아니라 **자기 라이브러리를 부르는 스크립트**에도 걸린다.
#   ★ofile 을 --file= 보다 먼저 본다 — 검사기가 SUT 를 source 하면 --file= 은 검사기를 가리킨다.
#   ★상대경로 self 는 **현재 cwd 기준으로 즉시 절대화**한다. 그래서 이 블록은 스크립트가
#     setwd() 하기 **전에** 놓여야 한다(2차 실측: setwd 뒤에 두었더니 self='.' 가 main 으로
#     해석돼 같은 halt 가 재발했다).
#   ★깊이를 가정하지 않고 marker 를 찾을 때까지 상위로 올라간다.
#   ★이 블록은 정본 안에 넣을 수 없다(그 정본을 찾는 코드다). 3소비자 동일 복제가 불가피하다.
.qvest_atomic_json_src <- function() {
  rel <- "02_Infrastructure/utils/atomic_json.R"
  self <- ""
  for (i in rev(seq_len(sys.nframe()))) {
    o <- sys.frame(i)$ofile
    if (!is.null(o) && nzchar(o)) { self <- o; break }
  }
  if (!nzchar(self)) {
    a <- commandArgs(trailingOnly = FALSE)
    f <- sub("^--file=", "", a[grepl("^--file=", a)])
    if (length(f)) self <- f[1]
  }
  cands <- character(0)
  if (nzchar(self)) {
    self <- chartr("\\", "/", self)
    # 절대경로 판정은 drive-letter·UNC·~ 를 인식할 것 (r-portability ③).
    if (!grepl("^([A-Za-z]:)?[/\\]", self) && !grepl("^~", self))
      self <- file.path(chartr("\\", "/", getwd()), self)
    d <- dirname(self)
    for (k in seq_len(6L)) {
      cands <- c(cands, d)
      nd <- dirname(d)
      if (identical(nd, d)) break
      d <- nd
    }
  }
  cands <- c(cands, chartr("\\", "/", c(Sys.getenv("CLAUDE_PROJECT_DIR", ""),
                                        Sys.getenv("QM_ROOT", ""), getwd())))
  cands <- cands[nzchar(cands)]
  hit <- cands[file.exists(file.path(cands, rel))]
  if (!length(hit)) stop("[atomic_json] 정본 미발견 — 코드 루트 해석 실패 (후보: ",
                         paste(cands, collapse = " | "), ")")
  file.path(hit[1], rel)
}
source(.qvest_atomic_json_src())

root <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); if (dir.exists(root)) setwd(root)


QUEUE_PATH   <- "06_Registry/overlay_candidate_queue.json"
AB_RESULT_DIR <- "06_Registry/overlay_ab_results"

.num <- function(x) if (is.null(x) || length(x) == 0) NA_real_ else suppressWarnings(as.numeric(x[1]))
.chr <- function(x) if (is.null(x) || length(x) == 0) NA_character_ else as.character(x[1])

# ── ① alpha-search strategy_manifest 스캔 ────────────────────────────────────
collect_manifests <- function() {
  files <- Sys.glob("stage_artifacts/alpha_search/*/strategy_manifest.json")
  out <- list()
  for (f in files) {
    m <- tryCatch(fromJSON(f, simplifyVector = TRUE), error = function(e) NULL)
    if (is.null(m)) next
    route <- .chr(m$verdict$screening$screen_route)
    if (is.na(route) || !grepl("OVERLAY_CANDIDATE", route, fixed = TRUE)) next
    mt <- m$metrics %||% list()
    out[[length(out) + 1]] <- list(
      id            = .chr(m$strategy_id),
      source        = "alpha_search_manifest",
      source_path   = f,
      strategy_name = .chr(m$strategy_name),
      screen_route  = route,
      label_time    = .chr(m$created_at),
      grade         = .chr(m$verdict$grade),
      essence_grade = .chr(m$authoritative$essence_grade),
      metric_type   = .chr(m$backtest_contract$metric_type) %||% "backtested",
      bt_result_path = .chr(m$execution$bt_result_path),
      signal_summary = list(
        sharpe = .num(mt$Sharpe), cagr_pct = .num(mt$CAGR), mdd_pct = .num(mt$MDD),
        ir = .num(mt$IR), calmar = .num(mt$Calmar), turnover_ann_pct = .num(mt$Turnover_Ann),
        bm_corr = .num(mt$BM_Corr),
        fmt_codes = paste(vapply(m$fmt$code %||% character(0), as.character, ""), collapse = "|")
      )
    )
  }
  out
}

# ── ② register_module 경유분 (module_catalog + module_quarantine) — 배관 선설치 ──
collect_module_registries <- function() {
  out <- list()
  for (reg in c("06_Registry/module_catalog.json", "06_Registry/module_quarantine.json")) {
    if (!file.exists(reg)) next
    d <- tryCatch(fromJSON(reg, simplifyVector = FALSE), error = function(e) NULL)
    if (is.null(d) || is.null(d$modules)) next
    for (nm in names(d$modules)) {
      mod <- d$modules[[nm]]
      route <- .chr(mod$meta$screen_route %||% mod$screen_route)
      if (is.na(route) || !grepl("OVERLAY_CANDIDATE", route, fixed = TRUE)) next
      out[[length(out) + 1]] <- list(
        id = nm, source = basename(reg), source_path = reg,
        strategy_name = .chr(mod$meta$strategy_name %||% nm),
        screen_route = route, label_time = .chr(mod$registered_at),
        grade = .chr(mod$grade), essence_grade = NA_character_,
        metric_type = .chr(mod$metric_type) %||% NA_character_,
        bt_result_path = .chr(mod$bt_result_path),
        signal_summary = list()
      )
    }
  }
  out
}

# ── ③ manual entries — 레지스트리 밖 산출물 (첫 케이스: LH/D2 loser-augment) ──
# 근거: 메모리 project-smartbeta-allstock-rotation 07-03 "다음 = ① LH → register_module screen-tier
#   (OVERLAY_CANDIDATE) 라벨 적재 ② factor-rotation overlay 소비 실측". register_module 미이행이라 수동 등재.
# config: loser-harvest qm/D0.30/lam0.85 rank3 mf4 tmb18 lv2 lvb20 buf2.5 + iskew5%+amihud5%+gov 배제 @2e8 topn25.
collect_manual <- function() {
  out <- list()
  d2_rds <- "04_Research/factor_rotation/smartbeta_allstock/D2_forge_result.rds"
  if (file.exists(d2_rds)) {
    res <- tryCatch(readRDS(d2_rds), error = function(e) NULL)
    if (!is.null(res)) {
      # forge-authoritative 수치 실독 (D2_forge_bridge.R 산출, weighted_screen_bt/NW lag-3)
      pr <- as.data.table(res$period_returns)
      a  <- pr$ret_net - pr$benchmark_ret
      oos_split <- function(a, frac) {
        n <- length(a); k <- floor(n * frac)
        is_sr <- mean(a[1:k]) / sd(a[1:k]) * sqrt(12)
        oos_sr <- mean(a[(k + 1):n]) / sd(a[(k + 1):n]) * sqrt(12)
        if (!is.finite(is_sr) || is_sr <= 0) return(NA_real_)
        oos_sr / is_sr
      }
      oos_v <- median(sapply(c(.55, .65, .75), function(f) oos_split(a, f)), na.rm = TRUE)
      cagr <- prod(1 + pr$ret_net)^(12 / nrow(pr)) - 1
      mdd  <- { cum <- cumprod(1 + pr$ret_net); abs(min(cum / cummax(cum) - 1)) }
      out[[length(out) + 1]] <- list(
        id            = "LH_D2_loser_augment",
        source        = "manual_memory_20260703",
        source_path   = d2_rds,
        strategy_name = "smartbeta allstock loser-harvest D2 (qm/D0.30/lam0.85 + iskew/amihud/gov 배제, 2e8 topn25)",
        screen_route  = "OVERLAY_CANDIDATE",
        label_time    = format(file.mtime(d2_rds), "%Y-%m-%dT%H:%M:%S%z"),
        grade         = "screen_tier",
        essence_grade = NA_character_,
        metric_type   = "weighted_screen",  # contract-grade(build_benchmark_compare NW lag-3), forge build_bt_result 아님
        bt_result_path = d2_rds,
        signal_summary = list(
          n_months = res$n_months,
          portfolio_alpha_t_nw_lag3 = .num(res$portfolio_alpha_t_nw_lag3),
          information_ratio = .num(res$information_ratio),
          net_sr_active = .num(res$net_sr),
          cagr_pct = round(cagr * 100, 2), mdd_pct = round(mdd * 100, 2),
          calmar = round(cagr / mdd, 3), oos_retention_v2 = round(oos_v, 3),
          turnover_ann_pct = round(.num(res$turnover_annual) * 100, 0),
          note = "graduation 3/3(screen-tier 실측) — 자본게이트 아님. weights=D2_winner_weights.parquet"
        )
      )
    } else cat(sprintf("[queue] WARN: %s 읽기 실패 — LH 수동 등재 생략\n", d2_rds))
  } else cat(sprintf("[queue] WARN: %s 없음 — LH 수동 등재 생략\n", d2_rds))
  out
}

# ── ④ 처분 원장 재라우팅 (2026-08-17 — /improve-drain R1, 도훈 "재개") ────────
#   standalone HARD 심사가 "신호 실재·구조 사유 기각"을 overlay_routed 로 처분하면
#   여기가 그 처분을 큐 후보로 승격한다. source="alpha_search_manifest" + bt_result_path
#   → drain adapter B (bt_result_rds) 경로 그대로 소비 가능.
collect_dispo_routed <- function() {
  out <- list()
  dp <- "06_Registry/standalone_track_dispositions.json"
  d <- if (file.exists(dp)) tryCatch(fromJSON(dp, simplifyVector = FALSE), error = function(e) NULL) else NULL
  for (sid in names(d$dispositions %||% list())) {
    rec <- d$dispositions[[sid]]
    if (!identical(.chr(rec$verdict), "overlay_routed")) next
    rd <- sub("^STR_AS_", "", sid)
    run_dir <- file.path("stage_artifacts/alpha_search", rd)
    bt <- file.path(run_dir, "bt_result.rds")
    mf <- file.path(run_dir, "strategy_manifest.json")
    if (!identical(rd, sid) && file.exists(bt)) {
      m <- if (file.exists(mf)) tryCatch(fromJSON(mf, simplifyVector = FALSE), error = function(e) NULL) else NULL
      out[[length(out) + 1]] <- list(
        id = sid, source = "alpha_search_manifest",
        source_path = mf,
        strategy_name = .chr(m$strategy_name) %||% sid,
        screen_route = "OVERLAY_CANDIDATE(dispo:overlay_routed)",
        label_time = .chr(rec$recorded_at),
        grade = "screen_tier", essence_grade = NA_character_,
        metric_type = "registry_record",
        bt_result_path = bt,
        disposition_note = .chr(rec$note)
      )
    } else {
      # 죽은 처분 가시화 — 조용히 건너뛰지 않는다 (부재를 정상으로 내려앉힘 금지)
      cat(sprintf("[queue] WARN: overlay_routed 처분 %s — bt_result.rds 부재/비표준 id, 적재 생략\n", sid))
    }
  }
  out
}

# ── A/B 실측 결과 첨부 ────────────────────────────────────────────────────────
attach_ab_results <- function(cands) {
  for (i in seq_along(cands)) {
    rf <- file.path(AB_RESULT_DIR, paste0(cands[[i]]$id, ".json"))
    if (file.exists(rf)) {
      cands[[i]]$ab_result <- tryCatch(fromJSON(rf, simplifyVector = TRUE), error = function(e) NULL)
      cands[[i]]$status <- "measured"
    } else cands[[i]]$status <- "queued"
  }
  cands
}

# ── 무신호 대조 감사 결과 부착 (2026-08-22 신설, measurement-graduation §3) ────
#   ★배선 이유: 감사 산출(CSV)만 있고 **읽는 쪽이 없으면** 라벨이 그대로 소비된다.
#   이 저장소가 반복해 당한 계통("기록은 되는데 소비자가 0")을 예방하려고 큐 빌더에 붙인다 —
#   큐에 붙으면 drain / improvement_potential / auto_spawn 등 **모든 소비자가 함께 본다**.
#   ★미감사를 '통과'로 취급하지 않는다: 감사 기록이 없으면 NOT_AUDITED 를 명시한다
#   (확인 불가를 확인 완료로 접지 않는다).
NOSIG_AUDIT_GLOB <- "06_Registry/no_signal_queue_audit_r*_*.csv"
attach_no_signal_audit <- function(cands, root = ".") {
  fs <- Sys.glob(file.path(root, NOSIG_AUDIT_GLOB))
  fs <- fs[!grepl("_clusters_", fs)]
  if (!length(fs)) {
    for (i in seq_along(cands)) cands[[i]]$no_signal <- list(verdict = "NOT_AUDITED",
      note = "무신호 대조 감사 산출 부재 — measurement-graduation §3 미확인 상태")
    return(cands)
  }
  f <- fs[which.max(file.mtime(fs))]
  A <- tryCatch(data.table::fread(f, encoding = "UTF-8"), error = function(e) NULL)
  if (is.null(A) || !nrow(A) || !("id" %in% names(A))) {
    for (i in seq_along(cands)) cands[[i]]$no_signal <- list(verdict = "NOT_AUDITED",
      note = paste0("감사 파일 파싱 실패: ", basename(f)))
    return(cands)
  }
  for (i in seq_along(cands)) {
    r <- A[id == cands[[i]]$id]
    if (nrow(r) >= 1) {
      cands[[i]]$no_signal <- list(
        verdict     = as.character(r$verdict[1]),
        diff_ann    = as.numeric(r$diff_ann[1]),
        diff_nw_t   = as.numeric(r$diff_nw_t[1]),
        t_alpha     = as.numeric(r$t_alpha[1]),
        beta        = as.numeric(r$beta[1]),
        audited_by  = basename(f),
        rule_ref    = "measurement-graduation.md §3 무신호 대조 통과 의무 (2026-08-22)")
    } else {
      cands[[i]]$no_signal <- list(verdict = "NOT_AUDITED",
        note = paste0("감사 산출에 id 부재(", basename(f), ") — 계열 추출 실패 등"))
    }
  }
  cands
}

# ── main ─────────────────────────────────────────────────────────────────────
build_overlay_candidate_queue <- function(write = TRUE) {
  cands <- c(collect_manifests(), collect_module_registries(), collect_manual(),
             collect_dispo_routed())
  # dedupe by id (manifest 우선순위 유지 — 최초 발견분)
  ids <- vapply(cands, function(x) x$id, "")
  cands <- cands[!duplicated(ids)]
  cands <- attach_ab_results(cands)
  cands <- attach_no_signal_audit(cands)   # ★2026-08-22 §3 배선
  queue <- list(
    schema_version = "overlay_candidate_queue_v1",
    generated_at   = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    producer_ref   = "hurdle_gate.R verdict$screening$screen_route (measurement-graduation §3 screening tier)",
    consumer_ref   = paste0("02_Infrastructure/ops/auto_regime_overlay_ab.R + ",
                            "02_Infrastructure/regime/overlay_candidate_ab_lh.R + ",
                            "02_Infrastructure/portfolio/module_dispatcher.R(FR Track2 풀 구성 시 no_signal 확인)"),
    note           = paste0("screening tier 라벨 — 자본/졸업 게이트 아님. ",
                            "overlay A/B 실측(clean-timing +1 lag 스트레스 의무) 후 status=measured. ",
                            "★2026-08-22 추가: 각 후보에 no_signal 필드(measurement-graduation §3 무신호 대조 게이트) 부착. ",
                            "verdict=INDISTINGUISHABLE_FROM_NO_SIGNAL 이면 그 성과는 신호가 아니라 대형주 노출일 수 있으므로 ",
                            "소비자(FR Track2 등)는 직교 재료로 쓰기 전에 확인할 것. NOT_AUDITED 는 미확인이지 통과가 아니다."),
    n_candidates   = length(cands),
    candidates     = cands
  )
  if (write) {
    qvest_atomic_write_json(queue, QUEUE_PATH, auto_unbox = TRUE, pretty = TRUE,
                            digits = NA, null = "null", na = "null", tag = "overlay_queue")
    cat(sprintf("[queue] wrote %s — n_candidates=%d (measured=%d)\n", QUEUE_PATH, length(cands),
                sum(vapply(cands, function(x) identical(x$status, "measured"), FALSE))))
  }
  invisible(queue)
}

if (sys.nframe() == 0L && Sys.getenv("QVEST_OVERLAY_QUEUE_NORUN") != "1") {
  q <- build_overlay_candidate_queue(write = TRUE)
  by_src <- table(vapply(q$candidates, function(x) x$source, ""))
  cat("[queue] by source:\n"); print(by_src)
}
