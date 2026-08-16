# =============================================================================
# test_p0_loop_closure.R — P0 루프 닫기 수리 4건 위반 주입 테스트 (2026-08-16, L1 승인)
#
# 대상:
#   P0#1 hypothesis_index 원천 (g) overlay_ab_results — 파서/스테일 감시
#   P0#2 drain_verdict dv_v1 — 판정 코드화 + 양성 대조(07-10 실측 16건 = INFERIOR 전건,
#        세션 수기 판정 L-OVL-20260710_153559 과 일치해야 함)
#   P0#3 close_round frontier 선언↔실기록 대조 — 부재 id 경고 + 구조 필드
#   P0#4 st_record_disposition — 기록/재읽기/supersede/거부
#
# 규약: 위반을 주입해 빨간불이 실제로 켜지는지 + 양성 대조가 초록인지 양방향 확인.
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

# ── SUT 로드 (CLI 가드: sys.nframe/QVEST_DRAIN_NORUN/--file 검사로 부수 실행 없음) ──
Sys.setenv(QVEST_DRAIN_NORUN = "1")
source(file.path(.root, "02_Infrastructure/regime/overlay_candidate_drain.R"))
source(file.path(.root, "02_Infrastructure/contracts/close_round.R"))
source(file.path(.root, "02_Infrastructure/portfolio/standalone_track_queue.R"))
source(file.path(.root, "02_Infrastructure/tools/hypothesis_index.R"))

# =============================================================================
# T1. drain_verdict dv_v1 — 주입 5종
# =============================================================================
mkP <- function(scen, t) data.table(scenario = scen, paired_nw_t_lag3 = t)

v <- drain_verdict(mkP(c("uni_cat", "uni_cat_lag1", "voltgt"), c(-1.2, -0.5, -2.0)))
chk("T1a 전부 음수 → INFERIOR", identical(v$verdict, "INFERIOR"))

v <- drain_verdict(mkP(c("uni_cat", "uni_cat_lag1"), c(5.0, 1.5)), n_selection = 8)
chk("T1b 고t + lag1 양수 → SURVIVOR", identical(v$verdict, "SURVIVOR"))

v <- drain_verdict(mkP("uni_cat", 5.0), n_selection = 8)
chk("T1c 고t + lag1 짝 부재 → INDETERMINATE (동월 누출 방어)",
    identical(v$verdict, "INDETERMINATE"))

v <- drain_verdict(data.table())
chk("T1d 빈 입력 → INDETERMINATE (억지 판정 금지)", identical(v$verdict, "INDETERMINATE"))

v <- drain_verdict(mkP(c("uni_cat", "uni_cat_lag1"), c(0.8, 0.5)), n_selection = 16)
chk("T1e 양수이나 null_max_t 미만 → INDETERMINATE", identical(v$verdict, "INDETERMINATE"))

v <- drain_verdict(mkP(c("uni_cat_cost", "uni_cat_lag1_cost"), c(4.0, 0.9)), n_selection = 4)
chk("T1f _cost 시나리오의 lag1 짝 매핑(_lag1_cost) 작동", identical(v$verdict, "SURVIVOR") &&
    identical(v$lag1_scenario, "uni_cat_lag1_cost"))

# =============================================================================
# T2. 양성 대조 — 07-10 실측 16건 재판정 = 세션 수기 판정(INFERIOR 전건)과 일치
# =============================================================================
od_dir <- file.path(.root, "06_Registry/overlay_ab_results")
if (dir.exists(od_dir)) {
  vb <- drain_verdict_batch(result_dir = od_dir, write = FALSE)
  vs <- vb[startsWith(candidate_id, "STR_AS_")]
  chk("T2a 07-10 배치 STR_AS_* = 16건", nrow(vs) == 16L)
  chk("T2b 전건 INFERIOR (세션 수기 판정 재현)", nrow(vs) > 0 && all(vs$verdict == "INFERIOR"))
  chk("T2c 최대 best_t가 음수 (L-code '최대 관측 paired NW-t = -1.199' 정합)",
      nrow(vs) > 0 && max(vs$best_t, na.rm = TRUE) < 0)
} else {
  chk("T2 결과 디렉토리 부재 — UNREPORTED (PASS 아님)", FALSE)
}

# =============================================================================
# T3. close_round frontier 선언↔실기록 대조
# =============================================================================
co <- capture.output({
  msgs <- character(0)
  rec_bad <- withCallingHandlers(
    close_round("P0TEST_R1", "config_scoped_negative",
                "P0 테스트 — frontier 대조 위반 주입용 기전 진단 문장.",
                next_probes = c("probe A", "probe B"),
                frontier_update = "FQ-999999 신규 등재 (존재하지 않는 id)",
                live_trigger = "테스트 트리거", write_marker = FALSE),
    message = function(m) { msgs <<- c(msgs, conditionMessage(m)); invokeRestart("muffleMessage") })
})
chk("T3a 부재 FQ-id → frontier_update_verified=FALSE", identical(rec_bad$frontier_update_verified, FALSE))
chk("T3b 부재 id가 frontier_ids_missing에 기록", "FQ-999999" %in% (rec_bad$frontier_ids_missing %||% ""))
chk("T3c 불일치 경고 메시지 발화", any(grepl("선언↔실기록 불일치", msgs)))

# 실재 id 추출 (큐 텍스트에서 "FQ-nnn" 첫 건)
qp <- file.path(.root, "06_Registry/alpha_frontier_queue.json")
qtxt <- paste(readLines(qp, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
mm <- regmatches(qtxt, gregexpr('"FQ-[0-9]{1,4}"', qtxt, perl = TRUE))[[1]]
real_id <- gsub('"', "", mm[1])
co <- capture.output(suppressMessages(
  rec_ok <- close_round("P0TEST_R2", "config_scoped_negative",
                        "P0 테스트 — frontier 실재 id 양성 대조용 기전 진단 문장.",
                        next_probes = c("probe A", "probe B"),
                        frontier_update = paste(real_id, "status 갱신"),
                        live_trigger = "테스트 트리거", write_marker = FALSE)))
chk(sprintf("T3d 실재 id(%s) → verified=TRUE", real_id),
    isTRUE(rec_ok$frontier_update_verified))

co <- capture.output(suppressMessages(
  rec_na <- close_round("P0TEST_R3", "config_scoped_negative",
                        "P0 테스트 — id 미언급 서술 대조불가 확인용 기전 진단.",
                        next_probes = c("probe A", "probe B"),
                        frontier_update = "프론티어 항목 서술만 갱신 (id 없음)",
                        live_trigger = "테스트 트리거", write_marker = FALSE)))
chk("T3e FQ-id 미언급 → verified=NA (억지 판정 금지)",
    length(rec_na$frontier_update_verified) == 1 && is.na(rec_na$frontier_update_verified))

# =============================================================================
# T4. st_record_disposition — 픽스처 루트 (실원장 불변)
# =============================================================================
troot <- file.path(tempdir(), sprintf("p0t_%d", Sys.getpid()))
dir.create(file.path(troot, "06_Registry"), recursive = TRUE, showWarnings = FALSE)

r1 <- st_record_disposition("STR_TEST_P0", "overlay_routed", note = "주입 테스트", root = troot)
dj <- fromJSON(file.path(troot, DISPO_REL), simplifyVector = FALSE)
chk("T4a 기록 후 원장 실재 + verdict 일치",
    identical(dj$dispositions$STR_TEST_P0$verdict, "overlay_routed"))

r2 <- st_record_disposition("STR_TEST_P0", "fr_routed", root = troot)
dj <- fromJSON(file.path(troot, DISPO_REL), simplifyVector = FALSE)
chk("T4b 재기록 → supersede 체인 기록",
    identical(dj$dispositions$STR_TEST_P0$verdict, "fr_routed") &&
    !is.null(dj$dispositions$STR_TEST_P0$supersedes))

err <- tryCatch({ st_record_disposition("STR_TEST_P0", "", root = troot); FALSE },
                error = function(e) TRUE)
chk("T4c verdict 결측 → stop (거부)", isTRUE(err))
err <- tryCatch({ st_record_disposition("", "overlay_routed", root = troot); FALSE },
                error = function(e) TRUE)
chk("T4d strategy_id 결측 → stop (거부)", isTRUE(err))

# 실원장 스키마 정합: 실제 dispositions 파일이 있으면 스캔 소비 형태 그대로인지
real_dp <- file.path(.root, DISPO_REL)
if (file.exists(real_dp)) {
  rd <- fromJSON(real_dp, simplifyVector = FALSE)
  chk("T4e 실원장 dispositions 맵 존재 (스캔 소비 스키마)", !is.null(rd$dispositions))
}

# =============================================================================
# T5. hypothesis_index 원천 (g) — 파서 + 스테일 감시
# =============================================================================
fx_dir <- file.path(troot, "06_Registry/overlay_ab_results")
dir.create(fx_dir, recursive = TRUE, showWarnings = FALSE)
fx <- list(candidate_id = "STR_AS_FIXTURE_1", measured_at = "2026-08-16T00:00:00+0900",
           tier = "screen_diagnostic", adapter = "weights_parquet",
           paired_nw = list(list(scenario = "uni_cat", paired_nw_t_lag3 = -1.2),
                            list(scenario = "voltgt", paired_nw_t_lag3 = -0.4)),
           verdict = list(verdict = "INFERIOR", rule_version = "dv_v1", null_max_t = 2.35))
write_json(fx, file.path(fx_dir, "STR_AS_FIXTURE_1.json"), auto_unbox = TRUE)

pe <- .hi_parse_overlay_drain(file.path(fx_dir, "STR_AS_FIXTURE_1.json"), troot, list())
chk("T5a 파서: OVL_ id 공간 + OVERLAY_INFERIOR",
    identical(pe$strategy_id, "OVL_STR_AS_FIXTURE_1") &&
    identical(pe$verdict, "OVERLAY_INFERIOR"))
chk("T5b 파서: best paired t 추출(-0.4) + source_types",
    isTRUE(abs(pe$key_metrics$best_paired_nw_t_lag3 - (-0.4)) < 1e-9) &&
    identical(pe$source_types, "overlay_drain"))

fx2 <- fx; fx2$verdict <- NULL; fx2$candidate_id <- "STR_AS_FIXTURE_2"
write_json(fx2, file.path(fx_dir, "STR_AS_FIXTURE_2.json"), auto_unbox = TRUE)
pe2 <- .hi_parse_overlay_drain(file.path(fx_dir, "STR_AS_FIXTURE_2.json"), troot, list())
chk("T5c 판정 미기록 구판 → OVERLAY_MEASURED (억지 판정 금지)",
    identical(pe2$verdict, "OVERLAY_MEASURED"))

writeLines("{ 깨진 json", file.path(fx_dir, "BROKEN.json"))
err <- tryCatch({ .hi_parse_overlay_drain(file.path(fx_dir, "BROKEN.json"), troot, list()); FALSE },
                error = function(e) TRUE)
chk("T5d 손상 JSON → 파서 error (콜렉터 tryCatch가 skip+카운트)", isTRUE(err))

# 스테일 감시: 인덱스를 과거 mtime으로 두면 fixture 결과가 stale 로 잡혀야 함
idx_p <- file.path(troot, "06_Registry/hypothesis_index.json")
write_json(list(schema_version = "hypothesis_index_v1", entries = list()), idx_p, auto_unbox = TRUE)
Sys.setFileTime(idx_p, Sys.time() - 3600)
st <- .hi_stale_check(idx_p, root = troot, warn = FALSE)
chk("T5e 스테일 감시: overlay_ab_results 원천 감지",
    any(grepl("overlay_ab_results", st %||% character(0))))

# 실인덱스 커버리지: build 후 OVL_ 엔트리 실재 (build는 별도 실행분 — 여기선 실측 파일만 확인)
real_idx <- file.path(.root, "06_Registry/hypothesis_index.json")
if (file.exists(real_idx)) {
  itxt <- paste(readLines(real_idx, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  chk("T5f 실인덱스에 OVL_ 엔트리 존재 (build 배선 확인 — build 미실행 시 FAIL이 정상)",
      grepl('"OVL_STR_AS_', itxt, fixed = TRUE))
}

unlink(troot, recursive = TRUE, force = TRUE)

cat(sprintf("\n=== test_p0_loop_closure: %d PASS / %d FAIL ===\n", n_pass, n_fail))
if (n_fail > 0) quit(save = "no", status = 1L)
