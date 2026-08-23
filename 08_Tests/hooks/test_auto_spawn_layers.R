# =============================================================================
# test_auto_spawn_layers.R — Layer 1~3 (L1 자동 스폰, 도훈 승인 2026-08-16) 위반 주입
#
#   L1: ip_per_regime (ip_v1 스코어 — 표본 미달 시 판정 없음)
#   L2: build_auto_spawn_queue (kind 4종 + kill switch + capacity + 상태 이월)
#       + claim 프로토콜 (선점/중복 거부/done 보존) + FR_RCMA 재정의(D2) 소비
#   양방향: 위반 주입이 빨개지는지 + 정상 픽스처가 초록인지.
# =============================================================================
suppressPackageStartupMessages({ library(jsonlite); library(data.table) })

.root <- (function() {
  cands <- c(Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""),
             "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
  cands <- cands[nzchar(cands)]
  hit <- cands[file.exists(file.path(cands, "02_Infrastructure/hooks/qvest_hook_router.py"))]
  if (!length(hit)) stop("project root 미발견")
  hit[1]
})()

n_pass <- 0L; n_fail <- 0L
chk <- function(name, cond) {
  if (isTRUE(cond)) { n_pass <<- n_pass + 1L; cat(sprintf("[PASS] %s\n", name)) }
  else { n_fail <<- n_fail + 1L; cat(sprintf("[FAIL] %s\n", name)) }
}

Sys.setenv(QVEST_IP_NORUN = "1", QVEST_DRAIN_NORUN = "1")
source(file.path(.root, "02_Infrastructure/portfolio/standalone_track_queue.R"))
source(file.path(.root, "02_Infrastructure/ops/auto_spawn_queue.R"))
source(file.path(.root, "02_Infrastructure/regime/improvement_potential.R"))

# =============================================================================
# T1. ip_per_regime — ip_v1 스코어
# =============================================================================
mk_pr <- function(n, act) {
  d <- seq(as.Date("2020-01-01"), by = "month", length.out = n)
  data.table(date = d, ret_net = 0.01 + act, benchmark_ret = 0.01)
}
set.seed(42)
n <- 40L
act <- c(rnorm(30, 0.01, 0.02), rnorm(10, -0.02, 0.02))  # normal 30m 상회 / crisis 10m 하회
pr <- mk_pr(n, act)
cat_dt <- data.table(Date = pr$date,
                     Category = c(rep("EXPANSION", 30), rep("CRISIS", 10)))
r <- ip_per_regime(pr, cat_dt)
chk("T1a 정상 픽스처: score 유효 + 양수 (normal 상회 ∧ crisis 하회)",
    isTRUE(r$score_eligible) && is.finite(r$score) && r$score > 0)
chk("T1b per_regime 셀 스키마 (n_months/active_ir/active_t)",
    r$normal$n_months == 30 && is.finite(r$crisis$active_ir))

cat_dt2 <- data.table(Date = pr$date, Category = c(rep("EXPANSION", 37), rep("CRISIS", 3)))
r2 <- ip_per_regime(pr, cat_dt2)
chk("T1c crisis 3m < 6 → score NA (표본 미달 = 판정 없음, 억지 산출 금지)",
    !isTRUE(r2$score_eligible) && is.na(r2$score))

# =============================================================================
# 픽스처 루트 구성 (L2)
# =============================================================================
troot <- file.path(tempdir(), sprintf("asq_%d", Sys.getpid()))
mkdirp <- function(...) dir.create(file.path(troot, ...), recursive = TRUE, showWarnings = FALSE)
mkdirp("06_Registry"); mkdirp(".cache")
mkdirp("stage_artifacts/alpha_search/RUN1"); mkdirp("stage_artifacts/alpha_search/RUN2")
mkdirp("stage_artifacts/alpha_search/RUN3")

hr <- function(run, route) write_json(
  list(screening = list(screen_pass = TRUE, screen_route = route),
       strategy = paste("Fixture", run), grade = "C", timestamp = "2026-08-16"),
  file.path(troot, "stage_artifacts/alpha_search", run, "hurdle_result.json"), auto_unbox = TRUE)
hr("RUN1", "FR_RCMA")                 # catalog 부재 → register_module_induce
hr("RUN2", "STANDALONE_TRACK")        # catalog 등재 + PORT_t 실측 → standalone_review
hr("RUN3", "FR_RCMA")                 # catalog fr_eligible → fr_disposition_suggest

write_json(list(modules = list(
  STR_AS_RUN2 = list(fr_eligible = FALSE, origin_mode = "alpha_search", registered_at = "2026-08-16",
                     meta = list(authoritative_essence = list(portfolio_alpha_t_nw_lag3 = 1.5,
                                                             oos_retention = 0.4, calmar = 0.5))),
  STR_AS_RUN3 = list(fr_eligible = TRUE, origin_mode = "alpha_search", registered_at = "2026-08-16",
                     meta = list())
)), file.path(troot, "06_Registry/module_catalog.json"), auto_unbox = TRUE)
# ★schema 2.0 (2026-08-23) — 빈 큐여도 정본 형태로 둔다. entries 는 비어 있으므로
#   enum 을 실을 항목이 없지만, `schema_version` 이 빠져 있으면 소비자가 구판 판정
#   경로로 떨어져도 이 픽스처는 초록이 난다(형태 회귀에 눈이 먼다).
write_json(list(schema_version = "2.0", entries = list()),
           file.path(troot, "06_Registry/alpha_frontier_queue.json"), auto_unbox = TRUE)

ovq <- function(ids_status) write_json(
  list(candidates = lapply(names(ids_status), function(id)
    list(id = id, status = ids_status[[id]], strategy_name = paste("OV", id)))),
  file.path(troot, "06_Registry/overlay_candidate_queue.json"), auto_unbox = TRUE)
ovq(list(OV_NEW = "queued", OV_OLD = "measured"))

# =============================================================================
# T2. kill switch
# =============================================================================
write_json(list(schema_version = "auto_spawn_config_v1", enabled = FALSE,
                capacity_pending_per_kind = 5L),
           file.path(troot, "06_Registry/auto_spawn_config.json"), auto_unbox = TRUE)
q0 <- build_auto_spawn_queue(troot, write = TRUE)
chk("T2a kill switch OFF → 적재 정지 (NULL 반환)", is.null(q0))
chk("T2b kill switch OFF → 큐 파일 미생성",
    !file.exists(file.path(troot, ASQ_QUEUE_REL)))

# =============================================================================
# T3. build — kind 4종 (D2 FR_RCMA 재정의 소비 포함)
# =============================================================================
write_json(list(schema_version = "auto_spawn_config_v1", enabled = TRUE,
                capacity_pending_per_kind = 5L),
           file.path(troot, "06_Registry/auto_spawn_config.json"), auto_unbox = TRUE)
q1 <- build_auto_spawn_queue(troot, write = TRUE)
ids <- names(q1$entries)
chk("T3a overlay_drain — queued 만 적재 (measured 제외)",
    ("overlay_drain:OV_NEW" %in% ids) && !("overlay_drain:OV_OLD" %in% ids))
chk("T3b D2 재정의: FR_RCMA ∧ catalog 부재 → register_module_induce",
    "register_module_induce:STR_AS_RUN1" %in% ids)
chk("T3c D2 재정의: FR_RCMA ∧ fr_eligible → fr_disposition_suggest",
    "fr_disposition_suggest:STR_AS_RUN3" %in% ids)
chk("T3d STANDALONE_TRACK ∧ PORT_t 실측 → standalone_review",
    "standalone_review:STR_AS_RUN2" %in% ids)
chk("T3e 큐 파일 실재 + 스키마", file.exists(file.path(troot, ASQ_QUEUE_REL)) &&
    identical(q1$schema_version, "auto_spawn_queue_v1"))

# =============================================================================
# T4. claim 프로토콜
# =============================================================================
e1 <- auto_spawn_claim("overlay_drain:OV_NEW", "sessionA", root = troot)
chk("T4a claim → in_progress + owner 기록",
    identical(e1$status, "in_progress") && identical(e1$owner, "sessionA"))
err <- tryCatch({ auto_spawn_claim("overlay_drain:OV_NEW", "sessionB", root = troot); FALSE },
                error = function(e) grepl("이미 claim", conditionMessage(e)))
chk("T4b 중복 claim → 거부 (stale 전 재점유 불가)", isTRUE(err))
auto_spawn_done("overlay_drain:OV_NEW", note = "테스트 완료", root = troot)
q2 <- build_auto_spawn_queue(troot, write = TRUE)
chk("T4c done 후 재빌드 → 상태 보존 (pending 리셋 금지)",
    identical(q2$entries[["overlay_drain:OV_NEW"]]$status, "done"))
err <- tryCatch({ auto_spawn_claim("overlay_drain:OV_NEW", "sessionC", root = troot); FALSE },
                error = function(e) grepl("이미 done", conditionMessage(e)))
chk("T4d done entry claim → 거부", isTRUE(err))

# =============================================================================
# T5. capacity — kind 별 pending 상한
# =============================================================================
many <- setNames(as.list(rep("queued", 8L)), paste0("OVX_", 1:8))
ovq(c(many, list(OV_NEW = "queued")))
write_json(list(schema_version = "auto_spawn_config_v1", enabled = TRUE,
                capacity_pending_per_kind = 3L),
           file.path(troot, "06_Registry/auto_spawn_config.json"), auto_unbox = TRUE)
q3 <- build_auto_spawn_queue(troot, write = TRUE)
n_od_pending <- sum(vapply(q3$entries, function(e)
  identical(e$kind, "overlay_drain") && identical(e$status, "pending"), logical(1)))
chk("T5a capacity 3 → overlay_drain pending ≤ 3", n_od_pending <= 3L)
chk("T5b done 이월은 capacity 와 무관하게 보존",
    identical(q3$entries[["overlay_drain:OV_NEW"]]$status, "done"))

# =============================================================================
# T6. 내구 로그 + 상태라인
# =============================================================================
chk("T6a auto_spawn_log.jsonl append (build/claim/done 사건 내구 기록)",
    file.exists(file.path(troot, ASQ_LOG_REL)) &&
    length(readLines(file.path(troot, ASQ_LOG_REL), warn = FALSE)) >= 4L)
sl <- auto_spawn_status_line(troot)
chk("T6b 상태라인 pending 노출", grepl("AutoSpawn: pending", sl))
write_json(list(schema_version = "auto_spawn_config_v1", enabled = FALSE),
           file.path(troot, "06_Registry/auto_spawn_config.json"), auto_unbox = TRUE)
chk("T6c 상태라인 kill switch 노출", grepl("OFF", auto_spawn_status_line(troot)))

unlink(troot, recursive = TRUE, force = TRUE)

cat(sprintf("\n=== test_auto_spawn_layers: %d PASS / %d FAIL ===\n", n_pass, n_fail))
cat(sprintf('{"test":"auto_spawn_layers","pass":%d,"fail":%d,"total":%d}\n',
            n_pass, n_fail, n_pass + n_fail))
if (n_fail > 0) quit(save = "no", status = 1L)
