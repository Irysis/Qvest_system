#!/usr/bin/env Rscript
#==============================================================================
# test_rf_b5_design_lib.R — B5 오버레이 자체 설계 레인 **라이브러리** 양방향 검사 (2026-09-17)
#
# 대상: 02_Infrastructure/ops/rf_b5_design_lib.R · rf_overlay_ledger_count.py(b5_design 몫 집계)
# 도훈 지시 2026-09-17: "매 강화 사이클마다 LLM 이 … 오버레이를 자체 설계" + "한 칸에 여러 오버레이 중첩"
#   + "오버레이층만 무한대로 탐색하는 버그 방지" + "오버레이 적대적 검증부".
# 지키는 것 (정상 경로 + 위반 주입):
#   A 설정 — b5_design.enabled 는 명시적 true 만 · 수치 비정상 = 기본값
#   B 발화 — 다음 블록 B5 판정: 기록 순서 · 미기록 시 러너 규칙 예측 · 앞 블록 미완·미결·B5 착수·비활성 = 불발
#   C arm 성과 이력 — B5 칸만(승계 층 오귀속 금지) · 상주 제외 · carry 제외 · Δ 중앙값 · G2 pass/fail
#   D 가드 — H1(자동 1회·재설계 상한·비활성) · H2(일간 상한 · 구판 기록 비산입) · H3(arm 을 낸 라운드 창 · 교대 우회 차단) · H4(상주 제외)
#   E 재료 — 날짜·위기 이름 제거 · 식별자 보존 · 앞선 교훈 상한 · 총량 상한 · 상주/퇴역 arm 비노출 · 낙폭 해부
#   F 낙폭 에피소드 — 깊이·기간·회복·벤치 비
#   G 검증·쓰기 — 칸 무결성 · 폴백 · 재설계 덧붙임 코드 · 자리 보존 채움 · 총 15칸 · 백업 위치 · CLI '-' 인자
#   H claim — 신규·점유·사망 pid·해제 표식
# 격리: 샌드박스 루트(.cache/_test_rf_b5_design_lib_<pid>) — 운영 원장·카탈로그·arm 디렉터리·jlog 에 쓰지 않는다(끝에 해시 대조).
#==============================================================================
suppressMessages({ library(jsonlite); library(data.table) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
CODE <- sub("/+$", "", gsub("\\\\", "/", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")))
setwd(CODE)
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat(sprintf("  OK   %s\n", m)) }
ng <- function(m, d = "") { FAIL <<- FAIL + 1L; cat(sprintf("  FAIL %s%s\n", m, if (nzchar(d)) paste0(" — ", d) else "")) }
chk <- function(cond, m, d = "") if (isTRUE(cond)) ok(m) else ng(m, d)

REAL <- c(file.path(CODE, "06_Registry/reinforce_ledger_l1.json"), file.path(CODE, "06_Registry/overlay_catalog.json"),
          file.path(CODE, "06_Registry/overlay_arm_ledger.jsonl"))
REAL_MD5 <- tools::md5sum(REAL[file.exists(REAL)])
REAL_JL <- file.path(CODE, ".cache/reinforce_auto_log.jsonl")
REAL_JL_N <- if (file.exists(REAL_JL)) length(readLines(REAL_JL, warn = FALSE)) else 0L   # 운영 jlog 는 다른 프로세스도 쓴다 — 이 검사의 픽스처 id 만 대조
REAL_ARMS <- sort(list.files(file.path(CODE, "02_Infrastructure/reinforcement/overlay_arms")))

SB <- file.path(CODE, ".cache", sprintf("_test_rf_b5_design_lib_%d", Sys.getpid()))
unlink(SB, recursive = TRUE)
for (d in c("06_Registry", "specs", "art", "stage_artifacts/l_code/reinforcement", ".cache/rf_block_design", ".cache/rf_b1_design",
            "02_Infrastructure/reinforcement/overlay_arms"))
  dir.create(file.path(SB, d), recursive = TRUE, showWarnings = FALSE)
stopifnot(file.copy(file.path(CODE, "06_Registry/reinforce_program.json"), file.path(SB, "06_Registry/reinforce_program.json")))
CFGP <- file.path(SB, "06_Registry/reinforce_auto_config.json")
JL   <- file.path(SB, "jlog.jsonl")
wjson <- function(x, p) write(toJSON(x, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = NA), p)
base_cfg <- list(enabled = TRUE, b5_design = list(enabled = TRUE, max_cells = 8, min_cells = 3, max_new_arms = 3, max_layers = 3, prior_entries = 12,
                 guards = list(max_redesign_rounds = 1, daily_arm_cap = 6, stagnation_window = 2, max_active_generated = 40)))
wjson(base_cfg, CFGP)
Sys.setenv(QVEST_RF_ROOT = SB, QVEST_RP_JLOG = JL, QVEST_RF_CONFIG = CFGP, QVEST_B5_CODE_ROOT = CODE)

# ── 카탈로그 픽스처 ───────────────────────────────────────────────────────────
arm <- function(id, kind, status = "active", action = "scalar_exposure", state = "vol", source = NULL, family = "vol_target") {
  a <- list(id = id, kind = kind, family = family, basis = paste("fixture", id), status = status, est_cost_min = 1, action = action, state = state)
  if (!is.null(source)) a$source <- source
  a }
CAT0 <- list(schema = "overlay_catalog_v1", note = "fixture", families = list(vol_target = "x"), arms = list(
  arm("arm_a", "kind_a"), arm("arm_b", "kind_b", action = "cross_sectional", state = "drawdown"), arm("arm_c", "kind_c", action = "cross_sectional", state = "trend"),
  arm("arm_d", "kind_d", state = "multivar"), arm("arm_e", "kind_e"), arm("arm_same_kind", "kind_a"),
  arm("arm_old", "kind_old", status = "retired"),
  arm("pg2_risk_overlay_v1", "pg2_risk_overlay", source = "overlay_propose", state = "multivar"),
  arm("gen1", "gen_20260101_000000", source = "overlay_propose"), arm("gen2", "b5gen_fx_1", source = "b5_design"),
  arm("gen3", "gen_20260102_000000")))
wjson(CAT0, file.path(SB, "06_Registry/overlay_catalog.json"))
writeLines(character(0), file.path(SB, "06_Registry/overlay_arm_ledger.jsonl"))

LIBP <- Sys.getenv("QVEST_B5_TEST_LIB", file.path(CODE, "02_Infrastructure/ops/rf_b5_design_lib.R"))   # 돌연변이 검사용 재지정
invisible(capture.output(suppressMessages(source(LIBP))))
chk(identical(ROOT, SB) && identical(.CODE_ROOT, CODE), "S0 lib 이 샌드박스를 데이터 루트로 · 코드 루트는 저장소로 읽는다", sprintf("ROOT=%s CODE=%s", ROOT, .CODE_ROOT))

# ── 원장 픽스처 도구 ──────────────────────────────────────────────────────────
L2 <- function(id, kind) list(kind = kind, arm_id = id)
spec <- function(name, overlay = NULL, overlay_cell = NULL, label = name) {
  p <- file.path(SB, "specs", paste0(name, ".json")); s <- list(label = label)
  if (!is.null(overlay)) s$overlay <- overlay
  if (!is.null(overlay_cell)) s$overlay_cell <- overlay_cell
  wjson(s, p); p }
att <- function(n, code, pt = 1, cagr = 0.2, mdd = 0.5, calmar = 0.4, sp = "", adv = NULL, art = NULL, measured = TRUE, terminal = FALSE) {
  a <- list(n = n, cell_code = code, idea = sprintf("[%s] fixture", code))
  if (measured) a$essence <- list(cell_code = code, block = sub("_.*$", "", code), port_t = pt, cagr = cagr, mdd = mdd, calmar = calmar, oos_retention = 0.5, spec = sp)
  if (!is.null(adv)) a$adversary <- if (is.list(adv)) adv else list(verdict = adv)   # 문자열=판정만 · 리스트=전체 기록
  if (!is.null(art)) a$artifacts <- art
  if (terminal) { a$terminal <- TRUE; a$terminal_reason <- "fixture" }
  a }
entry <- function(id, atts, status = "active", order = list("B1", "B5", "B2", "B3", "B4"), extra = list()) {
  e <- list(base_id = id, status = status, base_grade = "C", base_artifacts = "", attempts_used = length(atts), attempts = atts)
  if (!is.null(order)) e$block_order <- order
  c(e, extra) }
LEDP <- file.path(SB, "06_Registry/reinforce_ledger_l1.json")
write_ledger <- function(entries) wjson(list(schema_version = "reinforce_ledger_v2", layer = 1L, max_attempts = 25L, note = "fixture",
                                             entries = entries, combination_review = list(papers_since_last_review = 0L, last_review_date = "", history = list()),
                                             last_updated = ""), LEDP)
b1_five <- function(pfx = "", best_art = NULL, cagr = 0.22, calmar = 0.38) lapply(1:5, function(i)
  att(i, sprintf("B1_%d", i), pt = i, cagr = cagr, mdd = 0.55, calmar = calmar, art = if (i == 5L) best_art else NULL))
jlog_events <- function() { if (!file.exists(JL)) return(character(0))
  vapply(readLines(JL, warn = FALSE, encoding = "UTF-8"), function(l) tryCatch(fromJSON(l)$event, error = function(e) ""), character(1), USE.NAMES = FALSE) }

cat("=== A. 설정 ===\n")
c1 <- b5_cfg(SB)
chk(isTRUE(c1$enabled) && identical(c1$max_cells, 8L) && identical(c1$guards$stagnation_window, 2L), "A1 설정 읽기 — enabled·수치·guards")
wjson(list(enabled = TRUE), CFGP)
c2 <- b5_cfg(SB)
chk(!isTRUE(c2$enabled) && identical(c2$max_new_arms, 3L) && identical(c2$guards$daily_arm_cap, 6L), "A2 [위반] b5_design 블록 부재 = 꺼짐 · 수치는 기본값")
wjson(list(b5_design = list(enabled = "yes", max_cells = -4, guards = list(daily_arm_cap = "x"))), CFGP)
c3 <- b5_cfg(SB)
chk(!isTRUE(c3$enabled) && identical(c3$max_cells, 8L) && identical(c3$guards$daily_arm_cap, 6L), "A3 [위반] enabled='yes'(비불리언) = 꺼짐 · 음수·문자 수치 = 기본값")
wjson(base_cfg, CFGP)

cat("\n=== B. 발화 조건 — 다음 블록이 B5 인가 ===\n")
write_ledger(list(
  entry("T_DUE", b1_five()),
  entry("T_PEND", c(b1_five()[1:4], list(att(5, "B1_5", measured = FALSE)))),
  entry("T_TERM", c(b1_five()[1:4], list(att(5, "B1_5", measured = FALSE, terminal = TRUE)))),
  entry("T_B5", c(b1_five(), list(att(6, "B5_16")))),
  entry("T_ORDER_B2", b1_five(), order = list("B1", "B2", "B3", "B5", "B4")),
  entry("T_PRED", b1_five(), order = NULL),
  entry("T_PRED_LOW", b1_five(cagr = 0.10), order = NULL),
  entry("T_B1D7", b1_five()),
  entry("T_EXH", b1_five(), status = "exhausted")))
wjson(list(schema = "rf_b1_design_v1", cells = lapply(1:7, function(i) list(label = paste("c", i), factors = list("F1")))),
      file.path(SB, ".cache/rf_b1_design/T_B1D7.json"))
nb <- function(id) b5_next_block_is_b5(.b5_entry(SB, id), SB)
r <- nb("T_DUE");      chk(isTRUE(r) && grepl("recorded", attr(r, "why")), "B1 기록 순서 B1>B5 · B1 5칸 측정 → 발화", attr(r, "why"))
r <- nb("T_PEND");     chk(!isTRUE(r) && grepl("미결", attr(r, "why")), "B2 [위반] B1 미결 1칸 → 불발", attr(r, "why"))
r <- nb("T_TERM");     chk(isTRUE(r), "B3 terminal 로 닫힌 칸은 완료로 센다 → 발화", attr(r, "why"))
r <- nb("T_B5");       chk(!isTRUE(r) && grepl("B5 시도", attr(r, "why")), "B4 [위반] B5 시도 있음 → 불발(자동 설계는 착수 전 1회)", attr(r, "why"))
r <- nb("T_ORDER_B2"); chk(!isTRUE(r) && grepl("B2 미완", attr(r, "why")), "B5 순서 B1>B2>… → B2 미측정이라 불발", attr(r, "why"))
r <- nb("T_PRED");     chk(isTRUE(r) && grepl("predicted", attr(r, "why")), "B6 ★순서 미기록 · CAGR≥0.16 ∧ Calmar<0.64 → 러너 규칙으로 B5 2번째 예측 → 발화(러너가 같은 호출에서 순서를 적고 B5 를 여는 창을 잡는다)", attr(r, "why"))
r <- nb("T_PRED_LOW"); chk(!isTRUE(r) && grepl("predicted", attr(r, "why")), "B7 순서 미기록 · CAGR 미달 → 기본 순서 예측(B2 다음) → 불발", attr(r, "why"))
r <- nb("T_B1D7");     chk(!isTRUE(r) && grepl("5/7", attr(r, "why")), "B8 B1 설계 7칸인데 5칸만 닫힘 → 불발(칸 수는 설계에서 센다)", attr(r, "why"))
r <- nb("T_EXH");      chk(!isTRUE(r), "B9 [위반] 비활성 entry → 불발")
e_small <- entry("T_SMALL", b1_five()[1:4], order = NULL)
r <- b5_next_block_is_b5(e_small, SB); chk(!isTRUE(r) && grepl("program", attr(r, "why")), "B10 used<5 · 미기록 → 러너는 순서를 안 적고 격자 순서로 돈다 → program 순서로 판정", attr(r, "why"))

cat("\n=== C. arm 성과 이력 (B5 칸만) ===\n")
write_ledger(list(
  entry("T_OUT1", list(
    att(1, "B1_1", pt = 1, cagr = 0.1, mdd = 0.5, calmar = 0.2), att(2, "B1_2", pt = 2, cagr = 0.2, mdd = 0.6, calmar = 0.3),
    att(3, "B1_3", pt = 3, cagr = 0.3, mdd = 0.7, calmar = 0.4),
    att(4, "B5_16", pt = 2.5, cagr = 0.25, mdd = 0.5, calmar = 0.5, adv = "pass", sp = spec("o1_b5_16", overlay = L2("arm_a", "kind_a"), overlay_cell = L2("arm_a", "kind_a"))),
    att(5, "B5_17", pt = 1.5, cagr = 0.15, mdd = 0.4, calmar = 0.375, adv = "fail",
        sp = spec("o1_b5_17", overlay = list(L2("arm_a", "kind_a"), L2("arm_b", "kind_b")), overlay_cell = list(L2("arm_a", "kind_a"), L2("arm_b", "kind_b")))),
    att(6, "B2_6", pt = 9, cagr = 0.9, mdd = 0.1, calmar = 9, sp = spec("o1_b2_6", overlay = L2("arm_a", "kind_a"))),
    att(7, "B4_21", pt = 9, cagr = 0.9, mdd = 0.1, calmar = 9, sp = spec("o1_b4_21", overlay = L2("arm_b", "kind_b"))),
    att(8, "B5_31", pt = 9, cagr = 0.9, mdd = 0.1, calmar = 9, adv = "pass", sp = spec("o1_b5_31", overlay = L2("pg2_risk_overlay_v1", "pg2_risk_overlay"), overlay_cell = L2("pg2_risk_overlay_v1", "pg2_risk_overlay")))),
    status = "exhausted"),
  entry("T_OUT2", list(
    att(1, "B1_1", pt = 1, cagr = 0.2, mdd = 0.6, calmar = 0.3), att(2, "B1_2", pt = 3, cagr = 0.2, mdd = 0.6, calmar = 0.3),
    att(3, "B5_16", pt = 3, cagr = 0.3, mdd = 0.45, calmar = 0.6, adv = "pass", sp = spec("o2_b5_16", overlay = list(L2("arm_c", "kind_c"), L2("arm_a", "kind_a"))))),
    status = "exhausted", extra = list(carry = list(overlay = L2("arm_c", "kind_c"))))))
O <- rf_overlay_outcomes(SB)
oa <- O[arm_id == "arm_a"]; ob <- O[arm_id == "arm_b"]
near <- function(x, y) isTRUE(all.equal(as.numeric(x), y, tolerance = 1e-9))
chk(nrow(oa) == 1L && oa$uses == 3L && oa$stacked_uses == 1L && oa$n_entries == 2L, "C1 arm_a 사용 3(단층 2·스택 1) · entry 2 — B2/B4 승계 층은 안 센다 ★핵심",
    sprintf("uses=%s stacked=%s n=%s", oa$uses, oa$stacked_uses, oa$n_entries))
chk(nrow(oa) == 1L && near(oa$med_d_port_t, 0.5) && near(oa$med_d_mdd, -0.15) && near(oa$med_d_cagr, 0.05) && near(oa$med_d_calmar, 0.2),
    "C2 Δ = 칸 − 같은 entry B1 중앙값 · arm 별 중앙값(PORT_t +0.5 · MDD −0.15 · CAGR +0.05 · Calmar +0.2)",
    sprintf("%s %s %s %s", oa$med_d_port_t, oa$med_d_mdd, oa$med_d_cagr, oa$med_d_calmar))
chk(nrow(oa) == 1L && oa$adv_pass == 2L && oa$adv_fail == 1L && nrow(ob) == 1L && ob$uses == 1L && ob$stacked_uses == 1L && ob$adv_fail == 1L,
    "C3 G2 verdict 집계 — arm_a pass 2/fail 1 · arm_b(스택만) fail 1")
chk(!("arm_c" %in% O$arm_id), "C4 carry 층(arm_c)은 그 칸의 처치가 아니다 — 안 센다")
chk(!("pg2_risk_overlay_v1" %in% O$arm_id), "C5 상주 arm·상주 칸(B5_31)은 안 센다")
chk(identical(sort(b5_pass_arm_ids(SB)), "arm_a"), "C6 G2 pass arm = arm_a")

cat("\n=== D. 가드 H1~H4 ===\n")
today <- format(Sys.Date(), "%Y-%m-%d")
rounds <- function(...) list(rounds = list(...))
rd <- function(round, at, n, ids) list(round = round, at = at, source = "b5_design_lane", n_cells = 3L, new_arms_admitted = n, new_arms_rejected = 0L,
                                       compose_only = FALSE, fallback = FALSE, new_arm_ids = as.list(ids))
base_led <- list(
  entry("T_OUT1", list(att(1, "B1_1"), att(2, "B5_16", adv = "pass", sp = spec("g_pass", overlay_cell = L2("arm_a", "kind_a")))), status = "exhausted",
        extra = list(b5_design = rounds(rd(1L, "2026-09-10T10:00:00+0900", 1L, "gen_x")))),
  entry("T_OUT2", list(att(1, "B1_1")), status = "exhausted",
        extra = list(b5_design = rounds(rd(1L, "2026-09-11T10:00:00+0900", 1L, "gen_y"), rd(2L, "2026-09-12T10:00:00+0900", 0L, character(0))))),
  entry("T_G", b1_five()),
  entry("T_G1", b1_five(), extra = list(b5_design = rounds(rd(1L, "2026-09-13T10:00:00+0900", 0L, character(0))))),
  entry("T_G2", b1_five(), extra = list(b5_design = rounds(rd(1L, "2026-09-13T11:00:00+0900", 0L, character(0)), rd(2L, "2026-09-13T12:00:00+0900", 0L, character(0))))),
  entry("T_GX", b1_five(), status = "exhausted"))
write_ledger(base_led)
cfg <- b5_cfg(SB)
unlink(JL)
g <- b5_guards(.b5_entry(SB, "T_G"), SB, cfg, "auto")
chk(isTRUE(g$ok) && identical(g$round, 1L), "D1 H1 자동 — 라운드 기록 없음 → 통과 · round 1")
g <- b5_guards(.b5_entry(SB, "T_G1"), SB, cfg, "auto")
chk(!isTRUE(g$ok) && identical(g$refuse_reason, "h1_already_designed"), "D2 [위반] H1 round 1 기록 뒤 자동 재발화 → 거부", g$refuse_reason)
g <- b5_guards(.b5_entry(SB, "T_G1"), SB, cfg, "redesign")
chk(isTRUE(g$ok) && identical(g$round, 2L), "D3 H1 수동 재설계 첫 회 → 통과 · round 2")
g <- b5_guards(.b5_entry(SB, "T_G2"), SB, cfg, "redesign")
chk(!isTRUE(g$ok) && identical(g$refuse_reason, "h1_max_redesign_rounds"), "D4 [위반] H1 재설계 2회째(상한 1) → 거부 ★핵심", g$refuse_reason)
g <- b5_guards(.b5_entry(SB, "T_GX"), SB, cfg, "redesign")
chk(!isTRUE(g$ok) && identical(g$refuse_reason, "h1_entry_not_active"), "D5 [위반] 비활성 entry 재설계 → 거부", g$refuse_reason)
# H3 — 최근 arm 라운드 [gen_x, gen_y] · 마지막 라운드는 배합(0) — 교대 우회
g <- b5_guards(.b5_entry(SB, "T_G"), SB, cfg, "auto")
chk(isTRUE(g$compose_only) && "h3_stagnation" %in% g$compose_reasons && identical(g$arm_quota, 0L),
    "D6 ★H3 arm 을 낸 최근 2라운드(gen_x·gen_y) 가 G2 pass 에 한 번도 못 들었다 → compose_only · 사이의 배합 라운드는 창을 비우지 못한다", paste(g$compose_reasons, collapse = ","))
# 돌연변이 대조 — 구판 창(전 라운드 마지막 2개가 모두 arm 을 냈을 때만)이었다면 발화하지 않는다
allr <- .b5_all_rounds(rf_load(1L, SB)); setorderv(allr, "at"); last_old <- utils::tail(allr, 2L)
chk(!all(last_old$n_new > 0L), "D7 [돌연변이 대조] 구판 창(전 라운드 기준)은 같은 원장에서 H3 를 못 세운다 — D6 과 판정이 갈린다")
led_unlock <- base_led; led_unlock[[2]]$b5_design$rounds[[1]]$new_arm_ids <- list("gen_y", "arm_a")
write_ledger(led_unlock)
g <- b5_guards(.b5_entry(SB, "T_G"), SB, cfg, "auto")
chk(!("h3_stagnation" %in% g$compose_reasons), "D8 H3 해제 — 최근 arm 중 하나(arm_a)가 G2 pass B5 칸의 자기 층 → 새 arm 허용")
write_ledger(base_led)
# H2 — 오늘 b5_design 방출 5건 + 구판(출처 없음) 3건 + overlay_propose 2건 → 할당 1
LG <- file.path(SB, "06_Registry/overlay_arm_ledger.jsonl")
emis <- function(src, n) vapply(seq_len(n), function(i) as.character(toJSON(c(list(record_type = "arm_emission", kind = paste0("k", i), emitted_at = paste0(today, "T09:00:00+0900")),
                                                                            if (is.null(src)) list() else list(source = src)), auto_unbox = TRUE)), character(1))
writeLines(c(emis("b5_design", 5), emis(NULL, 3), emis("overlay_propose", 2)), LG)
led_h2 <- base_led; led_h2[[1]]$b5_design <- NULL; led_h2[[2]]$b5_design <- NULL; write_ledger(led_h2)
g <- b5_guards(.b5_entry(SB, "T_G"), SB, cfg, "auto")
chk(identical(g$n_today, 5L) && identical(g$arm_quota, 1L) && !isTRUE(g$compose_only),
    "D9 H2 오늘 b5_design 5건 → 할당 min(3, 6−5)=1 · 구판·다른 레인 기록은 안 센다", sprintf("n_today=%s quota=%s", g$n_today, g$arm_quota))
writeLines(c(emis("b5_design", 6), emis(NULL, 3)), LG)
g <- b5_guards(.b5_entry(SB, "T_G"), SB, cfg, "auto")
chk(identical(g$arm_quota, 0L) && isTRUE(g$compose_only) && "h2_quota" %in% g$compose_reasons, "D10 [위반] H2 일간 상한 도달 → 할당 0 · compose_only")
cnt_legacy <- system2(.b5_py(), c(shQuote(file.path(CODE, "02_Infrastructure/ops/rf_overlay_ledger_count.py")), shQuote(LG), today), stdout = TRUE)
chk(identical(trimws(tail(cnt_legacy, 1)), "3"), "D11 집계기 기본 호출(overlay_propose)은 구판 기록을 계속 센다(거동 불변)", paste(cnt_legacy, collapse = " "))
writeLines(character(0), LG)
# H4 — 생성 arm gen1(overlay_propose)·gen2(b5gen_)·gen3(gen_) = 3 · 상주 pg2(source=overlay_propose) 는 제외
cfg4 <- cfg; cfg4$guards$max_active_generated <- 2L
g <- b5_guards(.b5_entry(SB, "T_G"), SB, cfg4, "auto")
chk(identical(g$n_active_generated, 3L) && isTRUE(g$compose_only) && "h4_active_generated" %in% g$compose_reasons,
    "D12 H4 활성 생성 arm 3 > 상한 2 → compose_only · 상주 arm 은 생성 arm 수에 안 든다", sprintf("n=%s", g$n_active_generated))
ev <- jlog_events()
chk(all(c("overlay_guard_h1_once", "overlay_guard_h2_quota", "overlay_guard_h3_stagnation", "overlay_guard_h4_active_generated") %in% ev),
    "D13 가드 판정마다 jlog overlay_guard_<name> 이벤트(침묵 없음)")

cat("\n=== E. 재료 — 날짜 제거 · 상한 · 비노출 ===\n")
ds <- b5_strip_dates(c("2008-10 급락", "2020/03 충격", "2019.12 고점", "2008년 10월", "3월 15일 공시", "GFC 이후", "코로나 국면", "금융위기 때", "2022 에선",
                       "RP_20260917_105807_22632 · L-RF-20260905_120000 · arXiv 2002.06975 · v10.4 · 0.2008 · B5_16 · 25종"))
chk(!b5_has_dates(ds[1:9]) && all(grepl("<date>|<yr>|<episode>", ds[1:9])), "E1 날짜·연도·연월·한글 월일·이름 붙은 위기 → 전부 마스킹", paste(ds[1:9], collapse = " | "))
chk(identical(ds[10], "RP_20260917_105807_22632 · L-RF-20260905_120000 · arXiv 2002.06975 · v10.4 · 0.2008 · B5_16 · 25종"),
    "E2 식별자(RP_·L-RF-·arXiv id·버전·소수·셀 코드)는 보존", ds[10])
# 픽스처: T_MAT — 최고 칸 B1_5 에 산출물(nav·벤치) · 이 entry L-code 에 날짜 · 앞선 논문 B5 L-code 14건(긴 기전)
art <- file.path(SB, "art/T_MAT"); dir.create(art, recursive = TRUE, showWarnings = FALSE)
dts <- seq(as.Date("2005-01-31"), by = "month", length.out = 9)
fwrite(data.table(date = dts, nav_net = c(1, 1.1, 0.88, 0.99, 1.2, 1.0, 0.9, 1.3, 1.35)), file.path(art, "02_nav.csv"))
fwrite(data.table(date = dts, benchmark_nav = c(1, 1, 1, 1, 1, 0.9, 0.8, 1, 1)), file.path(art, "05_benchmark_returns.csv"))
mat_atts <- c(b1_five(best_art = art), list(att(6, "B2_6", sp = spec("m_b2", overlay = L2("arm_d", "kind_d")))))
write_ledger(list(entry("T_MAT", mat_atts, extra = list(carry = list(overlay = L2("arm_e", "kind_e"))))))
LCD <- file.path(SB, "stage_artifacts/l_code/reinforcement")
wr_l <- function(bid, blk, mech, avoid = character(0)) { f <- file.path(LCD, sprintf("l_code_%s_%s.json", bid, blk))
  write(toJSON(list(l_code = sprintf("L-RF-%s-%s", bid, blk), strategy_id = paste0(bid, "_", blk), mechanism = mech, avoid = as.list(avoid)), auto_unbox = TRUE), f); f }
wr_l("T_MAT", "B1", "판정: 2008-10 급락과 2020년 3월 코로나 충격, GFC 이후 낙폭이 컸다 · 근거 L-RF-20260905_120000 · RP_20260917_105807 · 2002.06975 · v10.4 · 0.2008",
     c("2022 에선 스칼라 축소가 실패", "금융위기 구간 한정 필터 금지"))
long_mech <- paste(rep("기전 서술 2011 과 2015 사이의 침식형 낙폭이 구속 축이다.", 60), collapse = " ")
for (k in 1:14) { f <- wr_l(sprintf("T_PRIOR%02d", k), "B5", long_mech, rep("회피 서술 2018 이후 반복", 5))
  Sys.setFileTime(f, Sys.time() - (100 - k) * 60) }
res <- b5_materials("T_MAT", SB, cfg, compose_only = FALSE, arm_quota = 2L, round = 1L, out_p = file.path(SB, "mat.txt"))
txt <- res$text; flat <- paste(txt, collapse = "\n")
chk(!b5_has_dates(txt), "E3 ★재료 전체에 달력 날짜·연도·위기 이름 0 (마스킹 후)")
chk(grepl("<date>", flat, fixed = TRUE) && grepl("<yr>", flat, fixed = TRUE) && grepl("<episode>", flat, fixed = TRUE), "E4 원천에 있던 날짜는 지워진 자리로 남는다(<date>/<yr>/<episode>)")
chk(grepl("L-RF-20260905_120000", flat, fixed = TRUE) && grepl("RP_20260917_105807", flat, fixed = TRUE) && grepl("2002.06975", flat, fixed = TRUE),
    "E5 재료 안 식별자 보존")
n_prior <- sum(grepl("^### T_PRIOR", txt))
chk(identical(n_prior, 12L) && grepl("T_PRIOR14_B5", flat, fixed = TRUE) && !grepl("T_PRIOR02_B5", flat, fixed = TRUE),
    "E6 앞선 논문 B5 교훈 = 최근 12건(prior_entries) · 오래된 것부터 빠진다", sprintf("n=%d", n_prior))
mech_lines <- txt[grepl("^- 기전: ", txt)]
chk(length(mech_lines) > 0L && all(nchar(sub("^- 기전: ", "", mech_lines)) <= 701L), "E7 기전 서술 700자 상한(+…)")
chk(!any(grepl("^- pg2_risk_overlay_v1 ", txt)) && !any(grepl("^- arm_old ", txt)) && any(grepl("^- arm_a ", txt)),
    "E8 활성 카탈로그 목록에 상주 arm·퇴역 arm 없음(활성만)")
chk(any(grepl("에피소드 1: 깊이 25.0%", txt, fixed = TRUE)) && any(grepl("비\\(전략/벤치\\) 1.25", txt)),
    "E9 바닥 낙폭 해부 — 최고 칸 산출물에서 깊이 25% · 같은 창 벤치 20% · 비 1.25", paste(txt[grepl("에피소드", txt)], collapse = " / "))
chk(any(grepl("| B2_6 | B2 |", txt, fixed = TRUE) & grepl("(승계) arm_d", txt, fixed = TRUE)),
    "E10 측정표 — 비 B5 칸의 오버레이는 '(승계)' 로 표시(그 칸의 처치로 오귀속 금지)")
chk(identical(names(res$sizes), c("axioms", "entry", "floor", "outcomes", "prior", "adv", "distilled", "catalog", "contract", "guard")) && all(res$sizes > 0L) &&
    file.exists(file.path(SB, "mat.txt.sizes.json")), "E11 절별 크기 산출 + sizes.json")
chk(any(grepl("B5_31(pg2_risk_overlay_v1)", txt, fixed = TRUE)), "E12 상주 칸 서술은 격자 standing_cells 에서 재도출(코드·arm)")
old_cap <- B5_MAT_CAP_CHARS; total0 <- sum(nchar(txt)); B5_MAT_CAP_CHARS <- total0 - 3000L
res2 <- b5_materials("T_MAT", SB, cfg, round = 1L)
chk(res2$prior_dropped > 0L && sum(nchar(res2$text)) <= B5_MAT_CAP_CHARS && sum(grepl("^### T_PRIOR", res2$text)) < 12L,
    "E13 총량 상한 — 넘으면 앞선 교훈을 오래된 것부터 덜어 상한 안으로", sprintf("dropped=%s total=%d cap=%d", res2$prior_dropped, sum(nchar(res2$text)), B5_MAT_CAP_CHARS))
B5_MAT_CAP_CHARS <- old_cap
res3 <- b5_materials("T_MAT", SB, cfg, compose_only = TRUE, arm_quota = 0L, round = 2L)
chk(any(grepl("compose_only = TRUE", res3$text, fixed = TRUE)) && any(grepl("새 arm 을 내지 마라", res3$text, fixed = TRUE)), "E14 가드 상태 절 — compose_only 면 새 arm 금지 문구")

# ── E15~E17: (4b) G2 반증 상세 — 앞선 칸이 '어떤 검사에서' 죽었는지가 재료에 실리는가
#   왜: verdict 만 주면 설계가 같은 죽음을 반복한다(실측 2026-09-19 — 22칸 연속 소비 보류, 사인 거의 전부 T3).
adv_rec <- function(code, cell, floor, verdict, t3s = "fail", reason = "", layers = list(L2("arm_a", "kind_a"))) list(
  schema = "rf_overlay_adversary_v1", recorded_at = "2026-09-19T22:56:15+0900", code = code, verdict = verdict, reason = reason,
  own_layers = layers, cell = list(calmar = cell), floor = list(calmar = floor),
  tests = list(T1 = list(status = "pass", calmar_shift = 0.48), T4 = list(status = "pass", const_calmar = 0.432),
               T3 = list(status = t3s, obs_calmar = 0.505, placebo_q = 0.523, p_value = 0.0796),
               T3b = list(status = "not_computed")))
adv_atts <- c(b1_five(best_art = art), list(
  att(6, "B5_18", pt = 2.7, calmar = 0.516, sp = spec("m_adv1", overlay = L2("arm_a", "kind_a")),
      adv = adv_rec("B5_18", 0.516, 0.457, "fail")),
  att(7, "B5_31", pt = 2.1, calmar = 0.458, sp = spec("m_adv2", overlay = L2("arm_b", "kind_b")),
      adv = adv_rec("B5_31", 0.458, 0.457, "not_candidate", t3s = "not_computed", reason = "calmar_not_above_floor"))))
write_ledger(list(entry("T_MAT", adv_atts, extra = list(carry = list(overlay = L2("arm_e", "kind_e"))))))
res_adv <- b5_materials("T_MAT", SB, cfg, round = 1L)
fa <- paste(res_adv$text, collapse = "\n")
chk(grepl("## (4b)", fa, fixed = TRUE) && grepl("| B5_18 |", fa, fixed = TRUE) &&
    grepl("fail obs 0.505 vs q 0.523 p 0.080", fa, fixed = TRUE) && grepl("pass const 0.432", fa, fixed = TRUE),
    "E15 (4b) 반증 상세 — 칸·검사별 수치(T3 obs/q/p · T4 상수)가 재료에 실린다",
    paste(res_adv$text[grepl("B5_18", res_adv$text)], collapse = " / "))
chk(grepl("arm_a", fa, fixed = TRUE) && grepl("집계: 2칸 · pass 0 · fail 1 · not_candidate 1 · 실패 사인 T3 1건", fa, fixed = TRUE),
    "E16 스택(arm_id)·집계 줄 — 사인 빈도까지 센다",
    paste(res_adv$text[grepl("집계:", res_adv$text)], collapse = " / "))
# 돌연변이: 절을 붙이는 줄을 지운 사본 → (4b) 가 사라져야 한다(= E15 가 결함을 잡는다)
mut_src <- readLines(file.path(CODE, "02_Infrastructure/ops/rf_b5_design_lib.R"), warn = FALSE, encoding = "UTF-8")
# ★fixed=TRUE — `sec$adv` 의 $ 는 정규식에서 행 끝이라 패턴이 영원히 안 맞는다(초판 실패)
drop_i <- grepl("sec$adv <- .b5_adv_sec(root)", mut_src, fixed = TRUE)
stopifnot(sum(drop_i) == 1L)
mut_src <- mut_src[!drop_i]
mp <- file.path(SB, "rf_b5_design_lib_mut.R"); writeLines(mut_src, mp, useBytes = TRUE)
menv <- new.env(parent = globalenv())
invisible(capture.output(suppressMessages(source(mp, local = menv, encoding = "UTF-8"))))
res_mut <- menv$b5_materials("T_MAT", SB, cfg, round = 1L)
chk(!any(grepl("## (4b)", res_mut$text, fixed = TRUE)) && identical(as.integer(res_mut$sizes[["adv"]]), 0L),
    "E17 [돌연변이] 절 조립 줄 제거 → (4b) 부재·크기 0(= E15·E16 이 결함을 잡는다)",
    sprintf("adv 크기=%s", res_mut$sizes[["adv"]]))
write_ledger(list(entry("T_MAT", mat_atts, extra = list(carry = list(overlay = L2("arm_e", "kind_e"))))))

cat("\n=== F. 낙폭 에피소드 ===\n")
ep <- b5_drawdown_episodes(c(1, 1.1, 0.88, 0.99, 1.2, 1.0, 0.9, 1.3), seq(as.Date("2005-01-31"), by = "month", length.out = 8), bnav = c(1, 1, 1, 1, 1, 0.9, 0.8, 1))
chk(length(ep) == 2L && near(ep[[1]]$depth, 0.25) && isTRUE(ep[[1]]$recovered) && near(ep[[1]]$bench_depth, 0.2) && near(ep[[1]]$ratio, 1.25) &&
    near(ep[[2]]$depth, 0.2) && ep[[1]]$m_peak_trough > 1.5 && ep[[1]]$m_peak_trough < 2.5,
    "F1 두 에피소드 깊이 25%·20% 정렬 · 회복 · 벤치 깊이·비 · 고점→저점 ≈2개월")
ep2 <- b5_drawdown_episodes(c(1, 1.2, 0.9, 0.8), seq(as.Date("2005-01-31"), by = "month", length.out = 4))
chk(length(ep2) == 1L && !isTRUE(ep2[[1]]$recovered) && is.na(ep2[[1]]$m_recover), "F2 미회복 에피소드 = recovered FALSE · 회복 개월 NA")

cat("\n=== G. 검증·최종 쓰기 ===\n")
mech_design <- function(id, cells) { p <- rfbd_path(SB, id, "B5"); wjson(list(block = "B5", cells = cells), p); p }
lane_design <- function(id, round, cells) { p <- b5_lane_design(SB, id, round); dir.create(dirname(p), recursive = TRUE, showWarnings = FALSE)
  wjson(list(schema = "rf_b5_design_v1", base_id = id, round = round, rationale = "fixture", cells = cells), p); p }
pk <- function(..., label = "c") list(picks = list(...), label = label, why = "fixture")
v3_atts <- c(b1_five(), list(att(6, "B5_16", sp = spec("v3_16", overlay_cell = L2("arm_a", "kind_a"))),
                          att(7, "B5_17", sp = spec("v3_17", overlay_cell = L2("arm_b", "kind_b"))),
                          att(8, "B5_18", sp = spec("v3_18", overlay_cell = list(L2("arm_c", "kind_c"), L2("arm_d", "kind_d"))))))
v4_atts <- c(b1_five(), lapply(1:5, function(i) att(5 + i, sprintf("B5_%d", 15 + i), sp = spec(sprintf("v4_%d", i), overlay_cell = L2(c("arm_a", "arm_b", "arm_c", "arm_d", "arm_e")[i], paste0("kind_", letters[i]))))),
             list(att(11, "B5_31", sp = spec("v4_31", overlay_cell = L2("pg2_risk_overlay_v1", "pg2_risk_overlay")))))
write_ledger(list(entry("T_V1", b1_five()), entry("T_V2", b1_five()),
                  entry("T_V3", v3_atts, extra = list(b5_design = rounds(rd(1L, "2026-09-14T10:00:00+0900", 0L, character(0))))),
                  entry("T_V4", v4_atts), entry("T_V5", b1_five()), entry("T_V6", b1_five())))
# G1 — 라운드 1: 10칸 제안 중 4칸 유효
mech1 <- mech_design("T_V1", list(list(pick = "arm_e", label = "기전 칸")))
mech1_txt <- readLines(mech1, warn = FALSE)
lp <- lane_design("T_V1", 1L, list(pk("arm_a"), pk("arm_b", "arm_c"), pk("arm_c", "arm_b"), pk("arm_old"), pk("pg2_risk_overlay_v1"),
                                   pk("arm_a", "arm_b", "arm_c", "arm_d"), pk("arm_a", "arm_same_kind"), pk("new_rej"), pk("arm_d"), pk("arm_e", "arm_a")))
unlink(JL)
vr <- b5_verify_and_write("T_V1", SB, cfg, lane_out = lp, admitted_ids = "gen2", rejected_ids = "new_rej", round = 1L)
FD <- fromJSON(rfbd_path(SB, "T_V1", "B5"), simplifyVector = FALSE)
cells_rt <- rfbd_cells(SB, "T_V1", "B5")
chk(isTRUE(vr$ok) && identical(vr$n_new, 4L) && identical(FD$source, "b5_design_lane") && identical(as.integer(FD$round), 1L) && nzchar(FD$written_at %||% "") &&
    length(FD$cells) == 4L, "G1 ★라운드 1 — 역순 중복·퇴역·상주·4층·같은 kind·거부 arm 6칸 제외 → 4칸 · source/round/written_at", vr$why)
chk(length(cells_rt) == 4L && identical(vapply(cells_rt, function(c) c$code, character(1)), c("B5_16", "B5_17", "B5_18", "B5_19")) &&
    is.null(cells_rt[[2]]$overlay$kind) && length(cells_rt[[2]]$overlay) == 2L, "G2 러너 소비(rfbd_cells) — 코드 B5_16..19 · 스택 칸은 층 리스트 2개")
bk <- b5_mech_backup(SB, "T_V1")
chk(file.exists(bk) && identical(readLines(bk, warn = FALSE), mech1_txt) && !any(grepl("mech", list.files(file.path(SB, ".cache/rf_block_design")))),
    "G3 기전 설계 백업 = 레인 디렉터리(.cache/rf_block_design 밖 — 그 디렉터리 최신 파일명이 순서 규칙 입력)")
EV1 <- rf_load(1L, SB)$entries[[1]]
rr <- EV1$b5_design$rounds
chk(length(rr) == 1L && identical(as.integer(rr[[1]]$round), 1L) && identical(as.integer(rr[[1]]$n_cells), 4L) && !isTRUE(rr[[1]]$fallback) &&
    identical(rr[[1]]$source, "b5_design_lane") && identical(unlist(rr[[1]]$new_arm_ids), "gen2") && is.null(EV1$b5_redesign),
    "G4 원장 b5_design.rounds 기록(round·n_cells·source·new_arm_ids) · 라운드 1 은 b5_redesign 을 안 연다")
ev <- jlog_events()
chk(sum(ev == "design_cell_dropped") == 6L && all(c("overlay_guard_h5_design_size", "overlay_guard_h6_cell_integrity", "design_verified", "design_backed_up") %in% ev),
    "G5 칸 제외 6건 · H5/H6 판정 · design_verified 이벤트", paste(table(ev), collapse = ","))
# G6 — 폴백: 유효 2칸
mech2 <- mech_design("T_V2", list(list(pick = "arm_e", label = "기전 칸")))
m2_before <- readLines(mech2, warn = FALSE)
lp2 <- lane_design("T_V2", 1L, list(pk("arm_a"), pk("arm_b"), pk("arm_old"), pk("zzz_missing")))
vr2 <- b5_verify_and_write("T_V2", SB, cfg, lane_out = lp2, round = 1L)
rr2 <- rf_load(1L, SB)$entries[[2]]$b5_design$rounds
chk(!isTRUE(vr2$ok) && isTRUE(vr2$fallback) && identical(readLines(mech2, warn = FALSE), m2_before) && length(rr2) == 1L && isTRUE(rr2[[1]]$fallback) &&
    grepl("유효 칸 2", rr2[[1]]$fallback_reason) && !file.exists(b5_mech_backup(SB, "T_V2")),
    "G6 ★유효 칸 2 < 최소 3 → 폴백 · 기전 설계 불변 · 라운드는 fallback=true 로 기록 · 백업 없음", vr2$why)
vr2b <- b5_verify_and_write("T_V2", SB, cfg, lane_out = file.path(SB, "nope.json"), round = 1L)
chk(isTRUE(vr2b$fallback) && grepl("설계 파일 부재", vr2b$why), "G7 [위반] 설계 파일 부재도 폴백 라운드로 기록(H8 — 미기록이면 매 tick 반복)")
# G8 — 재설계: 측정 3칸 뒤에 덧붙임
wjson(list(block = "B5", source = "b5_design_lane", round = 1L, cells = list(pk("arm_a"), pk("arm_b"), pk("arm_c", "arm_d"))), rfbd_path(SB, "T_V3", "B5"))
lp3 <- lane_design("T_V3", 2L, list(pk("arm_d"), pk("arm_d", "arm_c"), pk("arm_e"), pk("arm_a", "arm_e"), pk("arm_b")))
vr3 <- b5_verify_and_write("T_V3", SB, cfg, lane_out = lp3, round = 2L)
c3 <- rfbd_cells(SB, "T_V3", "B5"); E3 <- rf_load(1L, SB)$entries[[3]]
chk(isTRUE(vr3$ok) && identical(vr3$n_new, 3L) && identical(vapply(c3, function(c) c$code, character(1)), sprintf("B5_%d", 16:21)) &&
    isTRUE(E3$b5_redesign$active) && identical(as.integer(E3$b5_redesign$cells_added), 3L) && identical(as.integer(E3$b5_redesign$base_design_cells), 3L) &&
    identical(as.integer(E3$b5_redesign$round), 2L),
    "G8 ★재설계 — 측정된 3칸 자리 보존 + 새 3칸 B5_19..21 · 이미 잰 스택([C,D]·[B]) 제외 · b5_redesign{active,round 2,cells_added 3,base 3}", vr3$why)
# G9 — 자리 보존 채움: 측정 코드 B5_16..20 인데 설계 파일은 3칸(구 entry 의 사후 기전 설계)
wjson(list(block = "B5", cells = list(pk("arm_a"), pk("arm_b"), pk("arm_c"))), rfbd_path(SB, "T_V4", "B5"))
lp4 <- lane_design("T_V4", 2L, list(pk("arm_a", "arm_b"), pk("arm_c", "arm_e"), pk("arm_d", "arm_e")))
vr4 <- b5_verify_and_write("T_V4", SB, cfg, lane_out = lp4, round = 2L)
c4 <- rfbd_cells(SB, "T_V4", "B5"); E4 <- rf_load(1L, SB)$entries[[4]]
chk(isTRUE(vr4$ok) && identical(tail(vapply(c4, function(c) c$code, character(1)), 3), c("B5_21", "B5_22", "B5_23")) &&
    identical(as.integer(E4$b5_redesign$base_design_cells), 5L),
    "G9 ★측정 코드(B5_16..20)보다 짧은 바닥은 자리표시로 채운다 → 새 칸 B5_21 부터(상주 B5_31 은 코드 공간 밖) — 겹치면 러너가 '자리 있음' 으로 조용히 건너뛴다",
    paste(vapply(c4, function(c) c$code, character(1)), collapse = ","))
# G10 — 총 15칸: 바닥 13 + 제안 4 → 2칸만 자리 → 최소 3 미달 폴백
pairs <- utils::combn(c("arm_a", "arm_b", "arm_c", "arm_d", "arm_e"), 2, simplify = FALSE)
base13 <- c(lapply(c("arm_a", "arm_b", "arm_c", "arm_d", "arm_e"), function(x) pk(x)), lapply(pairs[1:8], function(p) do.call(pk, as.list(p))))
wjson(list(block = "B5", cells = base13), rfbd_path(SB, "T_V5", "B5"))
lp5 <- lane_design("T_V5", 2L, c(lapply(pairs[9:10], function(p) do.call(pk, as.list(p))), list(pk("arm_a", "arm_b", "arm_c"), pk("arm_b", "arm_c", "arm_d"))))
vr5 <- b5_verify_and_write("T_V5", SB, cfg, lane_out = lp5, round = 2L)
chk(isTRUE(vr5$fallback) && grepl("유효 칸 2", vr5$why) && length(fromJSON(rfbd_path(SB, "T_V5", "B5"), simplifyVector = FALSE)$cells) == 13L,
    "G10 [위반] entry 총 15칸(B5_16..30) 초과분 제외 → 유효 2 → 폴백 · 기존 13칸 불변", vr5$why)
# G11 — CLI: '-' 자리표시 인자(빈 인자가 Windows 에서 사라져 거부 목록이 승인 자리로 밀리던 위험) — 자식 Rscript 샌드박스 격리 확인 후
REN <- file.path(SB, ".Renviron.empty"); writeLines(character(0), REN)
old_re <- Sys.getenv("R_ENVIRON_USER", unset = NA); old_qm <- Sys.getenv("QM_ROOT")
Sys.setenv(R_ENVIRON_USER = REN, QM_ROOT = SB)
child_root <- trimws(paste(tryCatch(system2("Rscript", c("-e", shQuote("cat(Sys.getenv('QM_ROOT'))")), stdout = TRUE, stderr = FALSE), error = function(e) ""), collapse = ""))
if (identical(child_root, SB)) {
  ok("G11a 자식 Rscript 가 샌드박스를 QM_ROOT 로 읽는다(~/.Renviron 우회) — CLI 절 실행")
  lp6 <- lane_design("T_V6", 1L, list(pk("arm_a"), pk("arm_b"), pk("arm_c"), pk("arm_d")))
  out6 <- suppressWarnings(system2("Rscript", c(shQuote(LIBP), "verify", "T_V6", shQuote(lp6), "1", "0", "-", "arm_d"),
                                   stdout = TRUE, stderr = FALSE))
  D6 <- tryCatch(fromJSON(rfbd_path(SB, "T_V6", "B5"), simplifyVector = FALSE), error = function(e) NULL)
  chk(is.null(attr(out6, "status")) && length(D6$cells) == 3L && grepl("written", tail(out6, 1)),
      "G11b CLI verify '-' = 빈 승인 목록 · 거부 arm_d 칸 제외 → 3칸 기록 · rc 0", paste(tail(out6, 2), collapse = " / "))
  due <- suppressWarnings(system2("Rscript", c(shQuote(LIBP), "due"), stdout = TRUE, stderr = FALSE))
  chk(grepl("^T_V1\t1\t", tail(due, 1)), "G11c CLI due — 첫 활성 entry · 발화 1 · 사유 (탭 구분 마지막 줄)", tail(due, 1))
} else ng("G11a 자식 루트가 샌드박스가 아니다 — CLI 절 건너뜀(운영 오염 방지)", child_root)
if (is.na(old_re)) Sys.unsetenv("R_ENVIRON_USER") else Sys.setenv(R_ENVIRON_USER = old_re)
Sys.setenv(QM_ROOT = old_qm)

cat("\n=== H. claim ===\n")
CL <- file.path(SB, ".cache/claim_t")
r1 <- b5_claim_acquire(CL, Sys.getpid(), 6)
chk(isTRUE(r1$ok) && identical(r1$reason, "acquired") && file.exists(file.path(CL, "owner.json")), "H1 신규 claim 획득 · owner.json")
r2 <- b5_claim_acquire(CL, Sys.getpid(), 6)
chk(!isTRUE(r2$ok) && identical(r2$reason, "claimed"), "H2 [위반] 살아 있는 소유자 → 점유(claimed)", r2$note)
writeLines(toJSON(list(pid = 3999997L), auto_unbox = TRUE), file.path(CL, "owner.json"))
r3 <- b5_claim_acquire(CL, Sys.getpid(), 6)
chk(isTRUE(r3$ok) && grepl("사망", r3$note), "H3 소유자 pid 사망 → 나이 무관 인수", r3$note)
invisible(rf_claim_release(CL)); dir.create(CL, showWarnings = FALSE)
writeLines(toJSON(list(pid = Sys.getpid()), auto_unbox = TRUE), file.path(CL, "owner.json"))
writeLines("{}", file.path(CL, "released.json"))
r4 <- b5_claim_acquire(CL, Sys.getpid(), 6)
chk(isTRUE(r4$ok) && grepl("해제 표식", r4$note), "H4 해제 표식(released.json) → 제자리 인수", r4$note)

cat("\n=== Z. 격리 ===\n")
now_md5 <- tools::md5sum(REAL[file.exists(REAL)])
chk(identical(unname(now_md5), unname(REAL_MD5)), "Z1 운영 원장·카탈로그·방출 원장 해시 불변")
new_jl <- if (file.exists(REAL_JL)) { l <- readLines(REAL_JL, warn = FALSE); if (length(l) > REAL_JL_N) l[(REAL_JL_N + 1L):length(l)] else character(0) } else character(0)
chk(!any(grepl('"base_id":"T_(V[0-9]|MAT|G|DUE|PRED|OUT)', new_jl)), "Z1b 운영 jlog 에 이 검사의 픽스처 이벤트 0")
chk(identical(sort(list.files(file.path(CODE, "02_Infrastructure/reinforcement/overlay_arms"))), REAL_ARMS), "Z2 운영 arm 디렉터리 불변")
unlink(SB, recursive = TRUE)
chk(!dir.exists(SB), "Z3 샌드박스 삭제")

cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
cat(sprintf('{"test":"rf_b5_design_lib","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL > 0L) 1L else 0L)
