#!/usr/bin/env Rscript
#==============================================================================
# test_rf_b5_materials_labels.R — B5 설계 재료의 교차 entry 결과 **라벨** 가림
#   (도훈 결정 D-E-B5-LABELS 2026-09-25 · pit.md C1 D-E · 짝 = test_rf_b5_materials_redact.R(수치 · D-E-B5-MATERIALS))
#
# 배경: 수치를 가린 뒤에도 재료가 다른 entry 의 결과 라벨을 실었다 — (4b) "fail(failed: T1,T3)" · "실패 사인 T3 4건" ·
#   (6) 기전 지도 "포화/미포화"(+ 포화 순 정렬) · (2b) "오버레이 반증 pass 0/114 (dead)" · (5) "[negative]".
#   무인 설계자가 "죽은 적 없는 arm · 미포화 칸" 을 고르면 평가 창 결과를 소비하는 자동 선정이다.
#   수리 = rf_b5_design_lib.R 가 B5M 가림 체계(.b5_capx · 조립부 교차 절 기본 가림 · 발송 전 재검증)에 라벨 규칙을 더한다.
#   라벨 어휘는 나열하지 않고 코드가 실제로 낸 문자열(원장 G2 기록 · RFM_VCLASSES · ADV_DEFERRED_VERDICT · rf_target_brief 리터럴 ·
#   디렉터 overlay$status)에서 재료마다 재도출한다. 자기 entry 절 (1)(2)(7)(8) 은 라벨 유지(바이트 불변).
#
# 양방향:
#   A. 가림기(.b5_labeler) — 어휘 ⊇ 이 검사가 원장에 쓴 G2 문자열 · 생산자 상수(소스 텍스트에서 독립 판독) · rf_target_brief 가 실제로 낸 포화 라벨 ·
#      디렉터 상태 · 라벨 뒤 목록/개수 흡수 · 경계 밖 낱말 보존(bypass · dead-end · 포화한다 · b5gen_pass_1 · Calmar · 단독 검사 이름)
#      [위반 주입] 포화 리터럴 부재 / 판정 등급 상수 부재 / 연기 상수 부재 / 무력 가림(gsub no-op) / 무력 검증기 / 과잉 경계 → NULL(fail-closed)
#   B. b5_materials 합성 루트 — ★검사 자체 판별기(피검 가림기를 빌리지 않는다): 교차 절 라벨 0 · 표식 뒤 개수 0 ·
#      (2b) 디렉터 값·개수 0 · (4b) 4열·검사 이름 0·'-' 칸 0 · (5) [극성] 0 · (6) (action,state) 순·판정 개수 0 ·
#      자기 절 (1)(2)(7)(8) = 라벨 처리를 끈 판과 바이트 동일 · (1) 자기 G2 판정·자기 L-code 라벨 유지 · jlog 가린 개수
#   C. 돌연변이 — ① 조립부 라벨 가림 끔(게이트 유지) → materials_rejected(vocab)
#                 ② 라벨 가림 전부 끔 + 게이트 끔 → 라벨 잔존 → 판별기 red
#                 ③ (6) 정렬 줄 제거(포화 순 복원) → 순서 판별 red
#                 ④ (6) 행에 "판정 k" 복원 → 게이트 map_counts
#                 ⑤ (4b) 집계에 "실패 사인 T3 k건" 복원 → 게이트 adv_tests
#                 ⑥ (2b) 원천 표식 끔(구판 호출) → 게이트 director
#                 ⑦ (5) 극성 복원 → 게이트 polarity
#                 ⑧ 가림기 적재 실패(NULL 주입) → labeler_unavailable · 파일 없음
#   (수리 전 판 red 실증 = QVEST_B5_LIB 를 기준판으로 바꿔 돌리면 A 는 가림기 부재 · B 는 라벨 잔존으로 실패한다)
# 격리: QVEST_RF_ROOT = tempdir 합성 루트 · QVEST_RP_JLOG = tempdir · 코드 루트(QVEST_B5_CODE_ROOT) = QM_ROOT — 운영 원장·카탈로그·jlog 무접촉.
# 대상 교체: QVEST_B5_LIB (기본 = QM_ROOT/02_Infrastructure/ops/rf_b5_design_lib.R)
#==============================================================================
suppressMessages({ library(jsonlite); library(data.table) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
CODE <- sub("/+$", "", gsub("\\", "/", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"), fixed = TRUE))
LIB  <- Sys.getenv("QVEST_B5_LIB", file.path(CODE, "02_Infrastructure/ops/rf_b5_design_lib.R"))
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat(sprintf("  OK   %s\n", m)) }
ng <- function(m, d = "") { FAIL <<- FAIL + 1L; cat(sprintf("  FAIL %s%s\n", m, if (nzchar(d)) paste0(" — ", d) else "")) }
chk <- function(cond, m, d = "") if (isTRUE(cond)) ok(m) else ng(m, d)
finish <- function() {
  cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
  cat(sprintf('{"test":"rf_b5_materials_labels","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
  quit(status = if (FAIL > 0L) 1L else 0L)
}

# ── 검사 자체 판별기(피검 코드와 독립) ─────────────────────────────────────────────
HG <- "\uAC00-\uD7A3"; PART <- "\uC740\uB294\uC774\uAC00\uC744\uB97C\uB85C\uC640\uACFC\uC758\uB3C4\uB9CC\uC5D0"
esc <- function(s) gsub("([][{}()*+?.\\\\^$|])", "\\\\\\1", s, perl = TRUE)
my_tok <- function(t, ci = TRUE) {       # 경계: ASCII 단어(영숫자_-) / 한글(뒤 조사 1자 허용)
  a1 <- grepl("^[A-Za-z0-9_]", t, perl = TRUE); h1 <- grepl(sprintf("^[%s]", HG), t, perl = TRUE)
  a2 <- grepl("[A-Za-z0-9_]$", t, perl = TRUE); h2 <- grepl(sprintf("[%s]$", HG), t, perl = TRUE)
  paste0(if (a1) "(?<![A-Za-z0-9_\\-])" else if (h1) sprintf("(?<![%s])", HG) else "",
         if (ci && grepl("[A-Za-z]", t)) sprintf("(?i:%s)", esc(t)) else esc(t),
         if (a2) "(?![A-Za-z0-9_\\-])" else if (h2) sprintf("(?:(?![%s])|(?=[%s](?![%s])))", HG, PART, HG) else "")
}
hits_of <- function(lines, vocab, ci = TRUE) {
  out <- character(0)
  for (v in vocab) { h <- lines[grepl(my_tok(v, ci), lines, perl = TRUE)]; if (length(h)) out <- c(out, paste0(v, " :: ", substr(h, 1, 100))) }
  out
}
CROSS_H <- c("## 공리", "## (2b)", "## (3)", "## (4)", "## (4b)", "## (5)", "## (6)"); OWN_H <- c("## (1)", "## (2)", "## (7)", "## (8)")
sec_of <- function(txt) {
  key <- rep(NA_character_, length(txt)); cur <- NA_character_
  for (i in seq_along(txt)) {
    if (startsWith(txt[i], "## ")) { cur <- NA_character_
      for (h in c(CROSS_H, OWN_H)) if (startsWith(txt[i], paste0(h, " "))) cur <- h
      if (is.na(cur)) cur <- paste0("?", substr(txt[i], 1, 12)) }
    key[i] <- cur
  }
  key
}
lines_in <- function(txt, h) { k <- sec_of(txt); txt[!is.na(k) & k %in% h] }
map_rows <- function(txt) { s <- lines_in(txt, "## (6)")[-1]; i <- which(startsWith(s, "### ") | !nzchar(s)); if (length(i)) s[seq_len(i[1] - 1L)] else s }

# ── 합성 루트 ────────────────────────────────────────────────────────────────
SB <- gsub("\\", "/", file.path(tempdir(), sprintf("b5lab_%d", Sys.getpid())), fixed = TRUE)
unlink(SB, recursive = TRUE, force = TRUE)
for (d in c("06_Registry", "specs", "art/T_SELF", "art/T_SELF_B1_5", "stage_artifacts/l_code/reinforcement", ".cache/rf_block_design",
            "qepm/memory/axioms/active"))
  dir.create(file.path(SB, d), recursive = TRUE, showWarnings = FALSE)
JL <- file.path(SB, "jlog.jsonl"); CFGP <- file.path(SB, "06_Registry/reinforce_auto_config.json")
wjson <- function(x, p) write(toJSON(x, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = NA), p)
REAL <- c(file.path(CODE, "06_Registry/reinforce_ledger_l1.json"), file.path(CODE, "06_Registry/overlay_catalog.json"))
REAL_MD5 <- tools::md5sum(REAL[file.exists(REAL)])
REAL_JL <- file.path(CODE, ".cache/reinforce_auto_log.jsonl")
REAL_JL_N <- if (file.exists(REAL_JL)) length(readLines(REAL_JL, warn = FALSE)) else 0L
stopifnot(file.copy(file.path(CODE, "06_Registry/reinforce_program.json"), file.path(SB, "06_Registry/reinforce_program.json")))
wjson(list(enabled = TRUE, b5_design = list(enabled = TRUE, max_cells = 8, min_cells = 3, max_new_arms = 3, max_layers = 3, prior_entries = 12,
           guards = list(max_redesign_rounds = 1, daily_arm_cap = 6, stagnation_window = 2, max_active_generated = 40))), CFGP)
Sys.setenv(QVEST_RF_ROOT = SB, QVEST_RP_JLOG = JL, QVEST_RF_CONFIG = CFGP, QVEST_B5_CODE_ROOT = CODE)
arm <- function(id, kind, basis, action = "scalar_exposure", state = "vol") list(id = id, kind = kind, family = "vol_target", basis = basis,
                                                                               status = "active", est_cost_min = 1, action = action, state = state)
BASIS_Z <- "깊이 기반 계열(둘 다 포화)은 · G2 fail(failed: T1,T3) 이력 · pass 3/10 · bypass 경로 · b5gen_pass_1 참조 · dead-end 아님 · 포화한다"
wjson(list(schema = "overlay_catalog_v1", note = "fixture", families = list(vol_target = "x"), arms = list(
  arm("arm_zeta", "kind_z", BASIS_Z, action = "scalar_exposure", state = "vol"),
  arm("arm_alpha", "kind_a", "확장창 분위 게이트", action = "cross_sectional", state = "drawdown"),
  arm("arm_mid", "kind_m", "다변량 제동", state = "multivar"))), file.path(SB, "06_Registry/overlay_catalog.json"))
writeLines(character(0), file.path(SB, "06_Registry/overlay_arm_ledger.jsonl"))
L2 <- function(id, kind) list(kind = kind, arm_id = id)
spec <- function(name, overlay_cell) { p <- file.path(SB, "specs", paste0(name, ".json")); wjson(list(label = name, overlay_cell = overlay_cell), p); p }
att <- function(n, code, pt, calmar, sp = "", adv = NULL, art = NULL) {
  a <- list(n = n, cell_code = code, idea = sprintf("[%s] fixture", code),
            essence = list(cell_code = code, block = sub("_.*$", "", code), port_t = pt, cagr = 0.2, mdd = 0.5, calmar = calmar, oos_retention = 0.5, spec = sp))
  if (!is.null(adv)) a$adversary <- adv
  if (!is.null(art)) a$artifacts <- art
  a }
tst <- function(t1, t3, t3b, t4) list(T1 = list(status = t1, calmar_shift = 0.48), T3 = list(status = t3, obs_calmar = 0.505, placebo_q = 0.523, p_value = 0.0796),
                                      T3b = list(status = t3b), T4 = list(status = t4, const_calmar = 0.432))
adv <- function(code, verdict, reason, tests = list(), arm_id, kind, history = list(), analytic = NULL)
  list(schema = "rf_overlay_adversary_v1", recorded_at = "2026-09-19T22:56:15+0900", code = code, verdict = verdict, reason = reason,
       analytic_verdict = analytic, own_layers = list(L2(arm_id, kind)), cell = list(calmar = 0.6), floor = list(calmar = 0.4), tests = tests, history = history)
# 자기 entry — 자기 B5 칸 1개(판정 not_candidate = 자기 라벨 · (1) 에 남아야 한다)
dts <- seq(as.Date("2005-01-31"), by = "month", length.out = 9)
fwrite(data.table(date = dts, nav_net = c(1, 1.1, 0.88, 0.99, 1.2, 1.0, 0.9, 1.3, 1.35)), file.path(SB, "art/T_SELF_B1_5/02_nav.csv"))
fwrite(data.table(date = dts, benchmark_nav = c(1, 1, 1, 1, 1, 0.9, 0.8, 1, 1)), file.path(SB, "art/T_SELF_B1_5/05_benchmark_returns.csv"))
wjson(list(replication = list(source_paper = list(title = "Fixture paper", url = "https://arxiv.org/abs/2002.06975")),
           essence = list(portfolio_alpha_t_nw_lag3 = 2.345, cagr = 0.211, mdd = 0.502, calmar = 0.456, oos_retention = 0.61)),
      file.path(SB, "art/T_SELF/authoritative_remeasure.json"))
self_atts <- c(lapply(1:5, function(i) att(i, sprintf("B1_%d", i), pt = i + 0.125, calmar = 0.381, art = if (i == 5L) file.path(SB, "art/T_SELF_B1_5") else NULL)),
               list(att(6, "B5_16", pt = 1.5, calmar = 0.3, sp = spec("self_b5", L2("arm_mid", "kind_m")),
                        adv = adv("B5_16", "not_candidate", "calmar_not_above_floor", arm_id = "arm_mid", kind = "kind_m"))))
# 교차 entry — fail / pass / not_candidate(beyond) / 연기(이력 error) / 미검증
oth1 <- list(att(1, "B1_1", pt = 1, calmar = 0.2),
  att(2, "B5_16", pt = 2.5, calmar = 0.9, sp = spec("o1_16", L2("arm_zeta", "kind_z")),
      adv = adv("B5_16", "fail", "failed: T1,T3", tst("fail", "fail", "not_computed", "pass"), "arm_zeta", "kind_z", analytic = "fail")),
  att(3, "B5_17", pt = 2.0, calmar = 0.7, sp = spec("o1_17", L2("arm_alpha", "kind_a")),
      adv = adv("B5_17", "pass", "all required passed: T1,T3,T4", tst("pass", "pass", "not_computed", "pass"), "arm_alpha", "kind_a", analytic = "pass")),
  att(4, "B5_18", pt = 1.0, calmar = 0.5, sp = spec("o1_18", L2("arm_mid", "kind_m")),
      adv = adv("B5_18", "not_candidate", "beyond_max_candidates", arm_id = "arm_mid", kind = "kind_m")),
  att(5, "B5_19", pt = 1.1, calmar = 0.45, sp = spec("o1_19", L2("arm_zeta", "kind_z")),
      adv = adv("B5_19", "deferred_refresh_lock", "refresh_barrier: lock", arm_id = "arm_zeta", kind = "kind_z",
                history = list(list(at = "2026-09-18T00:00:00+0900", verdict = "error")))))
oth2 <- list(att(1, "B1_1", pt = 1, calmar = 0.2), att(2, "B5_16", pt = 1.5, calmar = 0.4, sp = spec("o2_16", L2("arm_alpha", "kind_a"))))
entry <- function(id, atts, status, extra = list()) c(list(base_id = id, status = status, base_grade = "C", attempts_used = length(atts), attempts = atts,
                                                         block_order = list("B1", "B5", "B2", "B3", "B4")), extra)
wjson(list(schema_version = "reinforce_ledger_v2", layer = 1L, max_attempts = 25L, note = "fixture",
           entries = list(entry("T_SELF", self_atts, "active", list(base_artifacts = file.path(SB, "art/T_SELF"))),
                          entry("T_OTH1", oth1, "exhausted", list(base_artifacts = "")), entry("T_OTH2", oth2, "exhausted", list(base_artifacts = ""))),
           combination_review = list(papers_since_last_review = 0L, last_review_date = "", history = list()), last_updated = ""),
      file.path(SB, "06_Registry/reinforce_ledger_l1.json"))
LCD <- file.path(SB, "stage_artifacts/l_code/reinforcement")
wr_l <- function(bid, blk, mech, avoid = character(0)) write(toJSON(list(l_code = sprintf("L-RF-%s-%s", bid, blk), strategy_id = paste0(bid, "_", blk),
  mechanism = mech, avoid = as.list(avoid)), auto_unbox = TRUE), file.path(LCD, sprintf("l_code_%s_%s.json", bid, blk)))
MECH <- paste("판정: B5_16 G2 fail(failed: T1,T3) · not_candidate 2칸 · 기전 지도 포화로 판정 · 미포화 칸은 남았다 · pass 3/10 · Pass 한 칸 ·",
              "deferred_refresh_lock 1칸 · bypass · dead-end · 포화한다 · T3 = 플라시보 · b5gen_pass_1 · Calmar 0.5")
wr_l("T_OTH1", "B5", MECH, c("below_floor 스택 재탕", "unverified 칸 fail 반복"))
wr_l("T_SELF", "B1", "자기 entry — B5_16 not_candidate · 기전 지도 포화 · G2 fail 이력 (자기 라벨 — 가리지 않는다)")
wjson(list(as_of = "2026-09-24T11:16:05+0900", binding = "calmar", co_binding = list("oos_retention"),
           program_best = list(port_t = 4.349, calmar = 0.501, mdd = 0.551, cagr = 0.276), thresholds = list(calmar_min = 0.64, port_t_min = 2.95),
           recurring_class = list(shape = "erosion", shape_rule = "고점→저점 중앙 ≤ 12개월 = spike", depth_median = 0.551, m_peak_trough_median = 25.7,
                                  ratio_median = 1.337, n_lineages_sharing = 5),
           pool_inventory = list(defensive_n = 361, defensive_deep_dd_excess_median = 2.57, defensive_deep_dd_negative_share = 0.169),
           overlay = list(status = "dead", adv_pass = 0, n_verdict = 114)), file.path(SB, ".cache/rf_director_context.json"))
wjson(list(n_entries = 2L, entries = list(
  list(dist_id = "DIST-T-001", status = "distilled", polarity = "negative", research_mode = "overlay",
       statement_refined = "오버레이 낙폭 축소는 G2 pass 0/9 에서 멈췄다", retry_condition = "새 기전일 때", n_supporting = 3L),
  list(dist_id = "DIST-T-002", status = "distilled", polarity = "conditional", research_mode = "overlay",
       statement_refined = "오버레이 국면 게이트는 조건부로만 쓴다", n_supporting = 2L))), file.path(SB, "06_Registry/distilled_knowledge.json"))
wjson(list(axiom_id = "AX-901", name = "fixture", statement = "오버레이는 'dead-end' 가 아니다 · T3 fail 이 반복됐다"),
      file.path(SB, "qepm/memory/axioms/active/AX-901.json"))

load_lib <- function(path) {
  e <- new.env(parent = globalenv())
  invisible(capture.output(suppressWarnings(suppressMessages(sys.source(path, envir = e, keep.source = FALSE)))))
  e
}
jl <- function() if (file.exists(JL)) readLines(JL, warn = FALSE, encoding = "UTF-8") else character(0)
mat <- function(E, tag) {
  p <- file.path(SB, sprintf("mat_%s.txt", tag)); unlink(p)
  r <- tryCatch(E$b5_materials("T_SELF", SB, E$b5_cfg(SB), compose_only = FALSE, arm_quota = 2L, round = 1L, out_p = p),
                error = function(e) structure(conditionMessage(e), class = "err"))
  list(r = r, p = p, txt = if (file.exists(p)) readLines(p, warn = FALSE, encoding = "UTF-8") else NULL)
}
mutate <- function(tag, pairs, src = LIB) {
  t <- paste(readLines(src, warn = FALSE, encoding = "UTF-8"), collapse = "\n"); n_hit <- 0L
  for (pr in pairs) { if (lengths(regmatches(t, gregexpr(pr[1], t, fixed = TRUE))) >= 1L) n_hit <- n_hit + 1L
                      t <- gsub(pr[1], pr[2], t, fixed = TRUE) }
  p <- file.path(SB, sprintf("mut_%s.R", tag)); writeLines(t, p, useBytes = TRUE)
  list(path = p, applied = identical(n_hit, length(pairs)))
}

cat("=== test_rf_b5_materials_labels ===\n")
E <- tryCatch(load_lib(LIB), error = function(e) { ng("라이브러리 적재", conditionMessage(e)); NULL })
if (is.null(E)) finish()

# ── 독립 어휘(이 검사가 쓴 것 + 생산자 소스 텍스트 + 생산자 함수가 실제로 낸 문자열) ────────────────────────
MM <- paste(readLines(file.path(CODE, "02_Infrastructure/reinforcement/rf_mechanism_map.R"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
AV <- paste(readLines(file.path(CODE, "02_Infrastructure/reinforcement/rf_overlay_adversary.R"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
vc <- regmatches(MM, regexec("(?m)^RFM_VCLASSES\\s*<-\\s*c\\(([^)]*)\\)", MM, perl = TRUE))[[1]]
CONST <- c(if (length(vc) == 2L) gsub('"', "", trimws(strsplit(vc[2], ",", fixed = TRUE)[[1]])) else character(0),
           { m <- regmatches(AV, regexec('(?m)^ADV_DEFERRED_VERDICT\\s*<-\\s*"([^"]+)"', AV, perl = TRUE))[[1]]; if (length(m) == 2L) m[2] else character(0) })
BRIEF <- tryCatch(strsplit(get("rf_target_brief", envir = E, mode = "function")(SB, k_saturate = 1L), "\n", fixed = TRUE)[[1]], error = function(e) character(0))   # 생산자가 실제로 낸 줄(k=1 → 포화·미포화 둘 다)
SAT <- unique(trimws(sub(".*\u00B7\\s*", "", BRIEF)))
G2W <- c("fail", "pass", "not_candidate", "calmar_not_above_floor", "beyond_max_candidates", "failed: T1,T3", "failed", "all required passed: T1,T3,T4",
         "all required passed", "not_computed", "deferred_refresh_lock", "refresh_barrier: lock", "refresh_barrier", "error")
MYV <- unique(c(G2W, CONST, SAT, "dead"))
TESTS <- c("T1", "T3", "T3b", "T4")
chk(length(CONST) >= 5L && length(SAT) == 2L && all(c("deferred_refresh_lock", "below_floor") %in% CONST),
    "S0 독립 어휘 원천 — 생산자 소스 텍스트(RFM_VCLASSES·ADV_DEFERRED_VERDICT) · rf_target_brief 가 실제로 낸 포화 라벨 2종",
    sprintf("const=%s sat=%s", paste(CONST, collapse = ","), paste(SAT, collapse = ",")))

cat("--- A. 가림기 — 재도출 어휘 · 흡수 · 경계 · fail-closed ---\n")
if (exists(".b5_labeler", envir = E)) {
  LB <- E$.b5_labeler(SB)
  chk(is.list(LB) && is.function(LB$redact) && is.function(LB$has) && identical(LB$mask, "<label>"), "A1 가림기 적재 · 표식 <label>")
  if (is.list(LB)) {
    miss <- setdiff(MYV, LB$vocab)
    chk(!length(miss), "A2 ★어휘 ⊇ 원장 G2 기록(verdict·reason·머리·검사 상태·이력) ∪ 생산자 상수 ∪ 포화 라벨 ∪ 디렉터 상태 — 나열 아닌 재도출",
        paste(miss, collapse = ","))
    chk(all(LB$n_src > 0L) && setequal(names(LB$n_src), c("g2", "const", "sat", "director")), "A3 원천 4종 전부 실림", paste(names(LB$n_src), LB$n_src, collapse = " "))
    x <- "G2 fail(failed: T1,T3) · pass 3/10 · Fail 7 · 포화로 판정 · 미포화 칸 · not_candidate 2칸 · (dead) · 실패 사인 fail: T3,T3b · G2 fail T4 에서 멈춤"
    y <- LB$redact(x)
    chk(!length(hits_of(y, MYV)) && !grepl("3/10|T1,T3|T3b|T4| 7|<label>\\s*\\d", y) && isTRUE(LB$has(x)) && !isTRUE(LB$has(y)),
        "A4 라벨·라벨 뒤 목록(failed: T1,T3 · fail T4)·개수(pass 3/10 · Fail 7)·한글 조사(포화로) 흡수 — 검증기 TRUE→FALSE", y)
    keep <- "bypass · dead-end · 포화한다 · b5gen_pass_1 · Calmar 0.5 · T3 = 플라시보 · B5_22 xs_vol_gap_corr_brake"
    chk(identical(LB$redact(keep), keep) && !isTRUE(LB$has(keep)), "A5 경계 밖 낱말 보존(bypass·dead-end·포화한다·arm kind·지표 이름·단독 검사 이름)", LB$redact(keep))
    chk(identical(LB$redact(y), y), "A6 멱등 — 가린 텍스트를 다시 가려도 같다")
  }
  inj <- function(nm, val) { old <- get(nm, envir = E); assign(nm, val, envir = E); r <- E$.b5_labeler(SB); assign(nm, old, envir = E); r }
  chk(is.null(inj("rf_target_brief", function(root = NULL, k_saturate = NULL) "no labels")), "A7 [위반] 포화 리터럴 부재(rf_target_brief 에 ifelse 라벨 없음) → NULL")
  fe <- new.env(parent = globalenv()); assign("SAT_ON", "포화", envir = fe); assign("SAT_OFF", "미포화", envir = fe)
  fk <- function(root = NULL, k_saturate = NULL) { mp <- list(saturated = TRUE); paste(ifelse(mp$saturated, SAT_ON, SAT_OFF)) }
  environment(fk) <- fe
  LK <- inj("rf_target_brief", fk)
  chk(is.list(LK) && all(c("포화", "미포화") %in% LK$vocab),
      "A7b 생산자가 라벨을 상수로 옮겨도(ifelse(saturated, SAT_ON, SAT_OFF)) 그 함수 환경에서 풀어 어휘를 잇는다")
  chk(identical(E$.b5_vocab_clean(c("label", "Stat", "pass", "x", "3")), "pass"), "A7c 표식 안에 든 낱말(label·stat)·한 글자·숫자는 어휘에서 뺀다(멱등 보호)")
  chk(is.null(inj("RFM_VCLASSES", character(0))), "A8 [위반] 판정 등급 상수(RFM_VCLASSES) 부재 → NULL")
  chk(is.null(inj(".b5_const_str", function(path, name) NULL)), "A9 [위반] 연기 상수(ADV_DEFERRED_VERDICT) 판독 실패 → NULL")
  cs <- E$.b5_const_str
  f1 <- file.path(SB, "c1.R"); writeLines(c('ADV_DEFERRED_VERDICT <- "x_lock"', 'ADV_DEFERRED_VERDICT <- "y_lock"'), f1)
  f2 <- file.path(SB, "c2.R"); writeLines(c('ADV_DEFERRED_VERDICT <- "x_lock"', 'z <- stop("평가되면 안 된다")'), f2)
  chk(is.null(cs(f1, "ADV_DEFERRED_VERDICT")) && identical(cs(f2, "ADV_DEFERRED_VERDICT"), "x_lock") && is.null(cs(file.path(SB, "nope.R"), "ADV_DEFERRED_VERDICT")),
      "A10 상수 판독 = parse 만(평가 없음) · 두 번 정의 = NULL · 파일 부재 = NULL")
  mA <- mutate("noop", list(c("x[ok] <- gsub(mask_rx, B5_LABEL_MASK, x[ok], perl = TRUE); x", "x")))
  chk(mA$applied && is.null(load_lib(mA$path)$.b5_labeler(SB)), "A11 [돌연변이] 무력 가림(gsub no-op) → 적재 양성 대조가 잡는다 → NULL")
  mB <- mutate("blind", list(c("any(vapply(has_rx, function(rx) any(grepl(rx, x, perl = TRUE)), logical(1)))", "FALSE")))
  chk(mB$applied && is.null(load_lib(mB$path)$.b5_labeler(SB)), "A12 [돌연변이] 무력 검증기(항상 FALSE) → NULL")
  mC <- mutate("wide", list(c('pre  <- if (isa(f1)) sprintf("(?<![%s])", a)', 'pre  <- if (isa(f1)) ""'),
                            c('post <- if (isa(fn)) sprintf("(?![%s])", a)', 'post <- if (isa(fn)) ""')))
  chk(mC$applied && is.null(load_lib(mC$path)$.b5_labeler(SB)), "A13 [돌연변이] 과잉 가림(ASCII 경계 제거 → bypass 를 가린다) → 보존 대조가 잡는다 → NULL")
} else ng("A 가림기 부재(.b5_labeler)", "수리 전 판이면 기대된 red")

cat("--- B. b5_materials — 교차 절 라벨 0 · 자기 절 불변 ---\n")
unlink(JL)
M <- mat(E, "main")
M_OFF <- NULL
if (!inherits(M$r, "err") && !is.null(M$txt)) {
  txt <- M$txt; xl <- lines_in(txt, CROSS_H)
  h <- hits_of(xl, MYV)
  chk(length(xl) > 20L && !length(h), "B1 ★교차 절(공리·(2b)·(3)·(4)·(4b)·(5)·(6)) 라벨 0 — 검사 자체 판별기 · 원장 G2·상수·포화·디렉터 상태", paste(head(h, 6), collapse = " | "))
  chk(!any(grepl("<label>\\s*[:=]?\\s*\\d|3/10|0/9|0/114", xl)) && !any(grepl(sprintf("<label>\\s*[:,]\\s*(%s)", paste(TESTS, collapse = "|")), xl)),
      "B2 표식 뒤 개수·검사 목록 0(pass 3/10 · 0/9 · 0/114 · failed: T1,T3)")
  s2 <- lines_in(txt, "## (2b)")[-1]; s2 <- s2[nzchar(s2)]
  chk(length(s2) >= 3L && !length(hits_of(s2, c("calmar", "oos_retention", "erosion", "dead"), ci = FALSE)) &&
      !any(grepl("[0-9]", gsub("<stat>", "", s2, fixed = TRUE))) && !any(grepl("spike", s2, fixed = TRUE)),
      "B3 (2b) 구속·공동 구속·형태·상태 값 0 · 본문 정수(공유 계보 5 · 방어형 361 · 0/114) 0 · 라벨 규칙 문장 없음", paste(s2, collapse = " / "))
  s4 <- lines_in(txt, "## (4b)"); r4 <- s4[startsWith(s4, "| ") & !startsWith(s4, "| entry") & !startsWith(s4, "|---")]
  chk(length(r4) >= 5L && all(lengths(regmatches(r4, gregexpr("|", r4, fixed = TRUE))) == 5L) && all(endsWith(r4, "| <stat> \u00B7 <label> |")) &&
      !length(hits_of(s4, TESTS, ci = FALSE)) && !any(grepl("\\|\\s*-\\s*\\|", r4)) && any(grepl("집계: \\d+칸 \\(판정별 개수", s4)),
      "B4 (4b) 4열(entry·코드·스택·결과) · 결과 = 표식 · 검사 이름 0 · '-' 검사 칸 0(후보 여부 누출 차단) · 집계 = 칸 수만", paste(head(r4, 2), collapse = " / "))
  s5 <- lines_in(txt, "## (5)")
  chk(any(grepl("[<label>]", s5, fixed = TRUE)) && !any(grepl("\\[(negative|conditional|positive)\\]", s5)) && any(grepl("DIST-T-001", s5, fixed = TRUE)),
      "B5 (5) 극성 = [<label>] · [negative]/[conditional] 0 · 항목 id 보존", paste(s5[grepl("DIST-T", s5)], collapse = " / "))
  m6 <- map_rows(txt); k6 <- do.call(rbind, lapply(strsplit(trimws(m6), "\\s+"), function(z) z[1:2]))
  srt <- if (is.null(k6)) FALSE else identical(order(k6[, 1], k6[, 2], method = "radix"), seq_len(nrow(k6)))
  chk(length(m6) == 14L && srt && !any(grepl("(판정|미검증)\\s*\\d", m6)) && !length(hits_of(m6, SAT)),
      "B6 ★(6) 지도 14행 = (action,state) 순(포화 순 아님) · 판정/미검증 개수 0 · 포화 라벨 0", paste(head(m6, 3), collapse = " / "))
  s6 <- lines_in(txt, "## (6)"); zb <- s6[grepl("^- arm_zeta ", s6)]
  chk(length(zb) == 1L && grepl("둘 다 <label>)", zb, fixed = TRUE) && all(vapply(c("bypass", "dead-end", "포화한다", "b5gen_pass_1"), grepl, logical(1), x = zb, fixed = TRUE)),
      "B7 arm basis 서술 속 라벨(둘 다 포화 · fail(failed: T1,T3) · pass 3/10)만 가리고 경계 밖 낱말은 보존", zb)
  s4p <- lines_in(txt, "## (4)")
  chk(any(grepl("<label>로 판정", s4p, fixed = TRUE)) && any(grepl("T3 = 플라시보", s4p, fixed = TRUE)) && any(grepl("포화한다", s4p, fixed = TRUE)),
      "B8 교훈 서술 — '포화로'(조사) 는 가리고 '포화한다'(동사)·단독 검사 이름은 남긴다", paste(s4p[grepl("^- 기전", s4p)], collapse = " / "))
  s1 <- lines_in(txt, "## (1)")
  chk(any(grepl("| B5_16 |", s1, fixed = TRUE) & grepl("| not_candidate |", s1, fixed = TRUE)) &&
      any(grepl("자기 entry — B5_16 not_candidate · 기전 지도 포화 · G2 fail 이력", s1, fixed = TRUE)),
      "B9 ★자기 entry (1) — 자기 칸 G2 판정(not_candidate)·자기 L-code 라벨(포화·fail)은 그대로")
  ev <- jl(); w <- ev[grepl('"event":"materials_written"', ev)]
  chk(length(w) == 1L && grepl('"cross_entry_labels_masked":[1-9]', w) && grepl('"label_vocab":[1-9]', w) && grepl("label_vocab_src", w),
      "B10 jlog materials_written 에 가린 라벨 수·어휘 크기·원천별 수")
  # 자기 절 바이트 불변 — 라벨 처리를 전부 끈 판(원천 표식 제외 · 조립부·절단·게이트 끔)과 (1)(2)(7)(8) 이 같다
  mOff <- mutate("off", list(c(".label_x <- function(S) { for (k in xsecs) if (length(S[[k]])) S[[k]] <- LB$redact(S[[k]]); S }", ".label_x <- function(S) S"),
                             c("if (length(lab_bad)) {", "if (FALSE) {"), c("sx <- function(s) rx$redact(lb$redact(s))", "sx <- function(s) rx$redact(s)")))
  if (mOff$applied) {
    M_OFF <- mat(load_lib(mOff$path), "off")
    same <- !is.null(M_OFF$txt) && all(vapply(OWN_H, function(hh) identical(lines_in(txt, hh), lines_in(M_OFF$txt, hh)), logical(1)))
    chk(same, "B11 ★자기·정적 절 (1)(2)(7)(8) = 라벨 처리를 끈 판과 바이트 동일(라벨 규칙은 교차 절만 건드린다)")
  } else ng("B11 돌연변이 좌표 미발견(off)")
} else ng("B 재료 생성 실패", if (inherits(M$r, "err")) as.character(M$r) else "파일 없음")

cat("--- C. 돌연변이 ---\n")
LBX <- ".label_x <- function(S) { for (k in xsecs) if (length(S[[k]])) S[[k]] <- LB$redact(S[[k]]); S }"
rej <- function(r, why) inherits(r$r, "err") && is.null(r$txt) && any(grepl('"event":"materials_rejected"', jl()) & grepl(why, jl(), fixed = TRUE))
m1 <- mutate("nolabel", list(c(LBX, ".label_x <- function(S) S")))
if (m1$applied) { unlink(JL); r <- mat(load_lib(m1$path), "m1")
  chk(rej(r, "cross_entry_labels_residual") && any(grepl("vocab:", jl(), fixed = TRUE)), "C1 [돌연변이] 조립부 라벨 가림 끔(게이트 유지) → materials_rejected(vocab) · 파일 없음")
} else ng("C1 돌연변이 미적용(좌표 변경)")
if (!is.null(M_OFF) && !is.null(M_OFF$txt)) {
  chk(length(hits_of(lines_in(M_OFF$txt, CROSS_H), MYV)) > 5L, "C2 [돌연변이] 라벨 가림 전부 끔 + 게이트 끔 → 교차 절 라벨 잔존 → 이 검사의 판별기가 잡는다(B1 red)",
      sprintf("잔존 %d", length(hits_of(lines_in(M_OFF$txt, CROSS_H), MYV))))
} else ng("C2 라벨 처리 끈 판 재료 없음")
m3 <- mutate("satorder", list(c('mp6 <- mp6[order(as.character(mp6$action), as.character(mp6$state), method = "radix")]', "")))
if (m3$applied) { r <- mat(load_lib(m3$path), "m3"); m6 <- if (is.null(r$txt)) character(0) else map_rows(r$txt)
  k6 <- if (length(m6)) do.call(rbind, lapply(strsplit(trimws(m6), "\\s+"), function(z) z[1:2])) else NULL
  chk(!is.null(k6) && !identical(order(k6[, 1], k6[, 2], method = "radix"), seq_len(nrow(k6))),
      "C3 [돌연변이] (6) 정렬 줄 제거 → 포화·측정 순이 되살아난다 → (action,state) 순 판별이 잡는다(B6 red)")
} else ng("C3 돌연변이 미적용(좌표 변경)")
m4 <- mutate("mapcount", list(c("as.integer(mp6$n_arms_catalog), LB$mask)", "as.integer(mp6$n_arms_catalog), paste(\"\uD310\uC815\", mp6$n_verdict))")))
if (m4$applied) { unlink(JL); r <- mat(load_lib(m4$path), "m4")
  chk(rej(r, "cross_entry_labels_residual") && any(grepl("map_counts", jl(), fixed = TRUE)), "C4 [돌연변이] (6) 행에 '판정 k' 복원 → 게이트 map_counts · 파일 없음")
} else ng("C4 돌연변이 미적용(좌표 변경)")
m5 <- mutate("advtests", list(c('sprintf("- 집계: %d칸 (판정별 개수·실패 사인은 가렸다 %s)", length(rows), mk)', 'sprintf("- 집계: %d칸 · 실패 사인 T3 %d건", length(rows), 1L)')))
if (m5$applied) { unlink(JL); r <- mat(load_lib(m5$path), "m5")
  chk(rej(r, "cross_entry_labels_residual") && any(grepl("adv_tests", jl(), fixed = TRUE)), "C5 [돌연변이] (4b) 집계에 '실패 사인 T3 k건' 복원 → 게이트 adv_tests(기본 가림이 못 잡는 자리)")
} else ng("C5 돌연변이 미적용(좌표 변경)")
m6m <- mutate("dir", list(c("b5_director_context(root, label_mask = LB$mask)", "b5_director_context(root)")))
if (m6m$applied) { unlink(JL); r <- mat(load_lib(m6m$path), "m6")
  chk(rej(r, "cross_entry_labels_residual") && any(grepl("director", jl(), fixed = TRUE)), "C6 [돌연변이] (2b) 원천 표식 끔(구판 호출) → 구속·형태·개수 잔존 → 게이트 director")
} else ng("C6 돌연변이 미적용(좌표 변경)")
m7 <- mutate("pol", list(c("rows5$dist_id[i], LB$mask,", "rows5$dist_id[i], rows5$polarity[i],")))
if (m7$applied) { unlink(JL); r <- mat(load_lib(m7$path), "m7")
  chk(rej(r, "cross_entry_labels_residual") && any(grepl("polarity", jl(), fixed = TRUE)), "C7 [돌연변이] (5) 극성 복원 → 게이트 polarity")
} else ng("C7 돌연변이 미적용(좌표 변경)")
E8 <- load_lib(LIB)
if (exists(".b5_labeler", envir = E8)) {
  assign(".b5_labeler", function(root = NULL) NULL, envir = E8); unlink(JL)
  r <- mat(E8, "m8")
  chk(rej(r, "labeler_unavailable"), "C8 [위반 주입] 가림기 적재 실패(NULL) → labeler_unavailable 중단 · 파일 없음(라벨을 가리지 않은 재료가 나가는 길 없음)")
} else ng("C8 가림기 부재", "수리 전 판이면 기대된 red")

cat("--- Z. 격리 ---\n")
now_md5 <- tools::md5sum(REAL[file.exists(REAL)])
chk(identical(unname(now_md5), unname(REAL_MD5)), "Z1 운영(QM_ROOT) 원장·카탈로그 해시 불변")
new_jl <- if (file.exists(REAL_JL)) { l <- readLines(REAL_JL, warn = FALSE); if (length(l) > REAL_JL_N) l[(REAL_JL_N + 1L):length(l)] else character(0) } else character(0)
chk(!any(grepl('"base_id":"T_(SELF|OTH[0-9])"', new_jl)), "Z2 운영 jlog 에 이 검사의 픽스처 이벤트 0")
unlink(SB, recursive = TRUE, force = TRUE)
finish()
