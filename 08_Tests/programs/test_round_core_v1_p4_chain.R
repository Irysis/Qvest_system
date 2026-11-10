## test_round_core_v1_p4_chain.R — P4 강화 사슬(round_core v1/p4.R · v10.2 · 2026-11-10) 격리 검사(양성 대조 + 위반 주입)
##   실제 등록부 · 결과 원장 · 생성기 등록부 · stage_artifacts 에 쓰지 않는다 — 임시 등록부 · 임시 원장 · 임시 생성기 등록부(RC_RXG_PATH) ·
##   임시 팩터 DB 수리 원장 · 합성 산출물(월간 수익 CSV)만 쓴다. 코드 · 정본 설정(등급 · 행동 카드 · 문턱)은 저장소 것을 읽기만 한다.
##   A 경로 · 기저 풀(사유 코드 전수 · 팩터 DB 판 양방향 · 상설 경로)  B 격차(보는 창만 — 시험 창 무감 양성 대조 · 계약 동치)
##   C 사슬 판 검사(위반 주입: 시험 창 · 전 기간 지표 · 출처 없음 · 필수 지표 없음 · 예산 출처 · 생성기 md5 · 풀 밖 기저)
##   D 등록 · 걸음 열기(판정 안 된 걸음 위 · 두 블록 · 고정 축 · 같은 칸 · 부모 · 날짜 누출 · 낡은 생성기 · 풀 밖 기저 · 사양 변경 R2)
##   E 걸음 판정(채택 · 기각 · 미측정 · 잡음 예산) · 원장 사슬 변조  F 설계 입력(보는 창 · 누출 fail-closed)  G 닫기(결과 원장 · 마감 훅)
##   H 생성기 판(rxg_pin · rxg_revise 거부 · 추가 전용) · 생성기 검토  I 헌장 격차 절 · CLI
##   J (11-10 실운용 연결) 기저 칸 사양(P1 표준 구성 생성기 동형) · 걸음 측정(가짜 러너 · 배리어 잠김 = 정본 판정기 · R2 · 실패 · 지문 · 스윕 회계) ·
##     기본 러너 배선(가짜 루트 워커) · 감독 영수증(등록 P1 · T1 / 닫기 P2 · T2 / 생성기 개정 — 임시 판단 원장) · 후보 관문(가짜 재채점 · 관문 파일)
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); ROOT <- gsub("\\\\", "/", ROOT); setwd(ROOT)
PASS <- 0L; FAIL <- 0L
chk <- function(name, ok, detail = "") {
  if (isTRUE(ok)) { PASS <<- PASS + 1L; cat(sprintf("  [ok]   %s\n", name)) } else { FAIL <<- FAIL + 1L; cat(sprintf("  [FAIL] %s %s\n", name, detail)) }
}
err_of <- function(expr) tryCatch({ force(expr); "" }, error = function(e) conditionMessage(e))
source("04_Research/programs/_lib/round_core/v1/load.R")
source("02_Infrastructure/programs/rx_round.R")
suppressPackageStartupMessages(library(data.table))

SB <- gsub("\\\\", "/", file.path(tempdir(), "rc_p4")); unlink(SB, recursive = TRUE); dir.create(SB, recursive = TRUE)
invisible(reg.finalizer(globalenv(), function(e) unlink(SB, recursive = TRUE), onexit = TRUE))
TAU <- rc_ref_value("06_Registry/behavior_card.json::tau_d")
OUTC <- file.path(SB, "round_outcomes.jsonl"); FDVL <- file.path(SB, "factor_db_vintage.json"); REG <- file.path(SB, "research_programs.json")
GEN_REG <- file.path(SB, "rx_generator.json"); Sys.setenv(RC_RXG_PATH = GEN_REG)
REAL_OUTC_MD5 <- if (file.exists("06_Registry/round_outcomes.jsonl")) rc_md5("06_Registry/round_outcomes.jsonl") else "absent"
REAL_GEN_MD5 <- rc_md5("06_Registry/rx_generator.json")

## ── 합성 산출물(월간 · 2000-01 ~ 2024-12 · 시험 창 행 포함) ─────────────────────────
ME <- seq(as.Date("2000-02-01"), as.Date("2025-01-01"), by = "month") - 1L
mk_art <- function(nm, alpha = 0.004, beta = 0.8, seed = 1L, post = NULL, grade = NULL, run_id = "RP_20261111_090000_t") {
  set.seed(seed); n <- length(ME)
  bm <- rnorm(n, 0.006, 0.055); bm[ME >= as.Date("2008-06-01") & ME <= as.Date("2008-11-30")] <- -0.09      # 위기 1(보는 창)
  bm[ME >= as.Date("2002-04-01") & ME <= as.Date("2002-09-30")] <- -0.06
  s <- alpha + beta * bm + rnorm(n, 0, 0.02)
  if (!is.null(post)) s[ME > as.Date(TAU)] <- post(s[ME > as.Date(TAU)])
  d <- file.path(SB, "art", nm); dir.create(d, recursive = TRUE, showWarnings = FALSE)
  fwrite(data.table(date = ME, ret_net = s, risk_free_ret = 0, leverage = 1, frequency = "monthly"), file.path(d, "03_period_returns.csv"))
  fwrite(data.table(date = ME, benchmark_ret = bm, benchmark_id = "KOSPI200"), file.path(d, "05_benchmark_returns.csv"))
  fwrite(data.table(date = ME, nav_net = cumprod(1 + s)), file.path(d, "02_nav.csv"))
  fwrite(data.table(run_id = "t", date = ME, ticker = "A1", target_weight = 1), file.path(d, "04_holdings.csv"))
  rc_json_write(list(run_id = run_id, essence_grade = grade %||% "C", grade_scheme = "test_fixture"), file.path(d, "authoritative_remeasure.json"))
  d
}
A_BASE <- mk_art("base", grade = "B")
A_POST <- mk_art("base_post", grade = "B", post = function(x) x - 0.05)                 # τ_D 뒤만 다르다(시험 창 무감 양성 대조)
A_S1 <- mk_art("s1", alpha = 0.006, seed = 1L); A_S2 <- mk_art("s2", seed = 2L); A_S3 <- mk_art("s3", seed = 3L); A_S4 <- mk_art("s4", seed = 4L)
A_STALE <- mk_art("stale", grade = "B", run_id = "RP_20261101_090000_t")
A_A <- mk_art("gradeA", grade = "A"); A_C <- mk_art("gradeC", grade = "C")

## ── 엔진 · 임시 등록부 · 수리 원장 · 생성기 등록부 ───────────────────────────────
ENG <- file.path(SB, "eng"); dir.create(ENG, showWarnings = FALSE)
mk_eng <- function(nm) { p <- file.path(ENG, nm, "engine.R"); dir.create(dirname(p), recursive = TRUE, showWarnings = FALSE)
  writeLines(c("## fixture engine", paste("##", nm), "FACTORS <- data.table::data.table(Date = as.Date(character(0)), Ticker = character(0), Score = numeric(0))"), p); p }
it <- function(nm, art, ...) modifyList(list(key = paste0("engine:T_", nm), kind = "engine", engine_path = mk_eng(nm), artifacts = art, grade = "F",
                                             implementation_suspect = FALSE, has_short = FALSE, audit_verdict = "adapted", paper_key = paste0("9902.", nm)), list(...))
ITEMS <- list(it("ok", A_BASE), it("short", A_A, has_short = TRUE), it("suspect", A_A, implementation_suspect = TRUE), it("suspna", A_A, implementation_suspect = NULL),
              it("misdecl", A_A, audit_verdict = "misdeclared"), it("gradec", A_C), it("stale", A_STALE), it("ok2", A_S2))
ITEMS[[4]]$implementation_suspect <- NULL
noeng <- it("noeng", A_A); unlink(dirname(noeng$engine_path), recursive = TRUE)
rc_json_write(list(schema = "research_programs_v1", target_spec = list(), programs = list(
  list(id = "P1_RETURN", queue = ITEMS[1:6], consumed = list()), list(id = "P3_CONSTRUCTION", queue = ITEMS[7:8]), list(id = "P4_ASSEMBLY", queue = list(), rounds = list())),
  paper_routing = list(unrouted = list(noeng))), REG)
rc_json_write(list(schema = "factor_db_vintage_v1", entries = list(list(id = "T-REPAIR", completed_at = "2026-11-10T11:26:00+09:00", scope = "all"))), FDVL)
GD1 <- file.path(SB, "gen", "g1"); dir.create(GD1, recursive = TRUE); file.copy("04_Research/programs/P4_ASSEMBLY/_generator/g1/step.md", GD1)
rc_json_write(list(schema = "rx_generator_v1", current = "g1", versions = list(list(id = "g1", dir = GD1, files = rxg_files_md5(GD1), created_at = rc_now(), reason = "시험", evidence = list()))), GEN_REG)
## ── 임시 판단 원장(감독 영수증 — 기존 코어와 같은 우회: ledger = 임시 원장 · review_root = 임시 리뷰 뿌리) ─────────────
REAL_LEDGER_MD5 <- rc_md5("06_Registry/q_judgment_ledger.json")
LEDG <- file.path(SB, "q_judgment_ledger.json"); RVR <- file.path(SB, "rv")
rvw <- function(id, role, trigger, round, file = NULL, challenges = list(), mkfile = TRUE) {
  f <- file %||% sprintf("04_Research/programs/_supervision/superfan/%s20261110_1200_%s_%s.md", if (role == "philosophy") "philosophy/" else "",
                         trigger, sub("_.*$", "", round %||% "none"))
  if (mkfile) { dir.create(dirname(file.path(RVR, f)), recursive = TRUE, showWarnings = FALSE); writeLines("리뷰", file.path(RVR, f)) }
  list(id = id, at = "x", role = role, trigger = trigger, scope = list(), file = f, round = round, direction = if (trigger == "P2") "toward" else NULL,
       challenges = challenges)
}
LREV <- list()
for (cid in c("P4C99_selftest", "P4C97_none", "P4C96_measure", "P4C95_nota", "P4C94_vint",
              "P4C93_close", "P4C92_lock", "P4C91_samea", "P4C90_sameb", "P4C89_aband", "P4C88_new", "P4C87_old", "P4C86_other", "P4C85_grade", "P4C84_dup")) {
  tg <- sub("_.*$", "", cid)
  LREV <- c(LREV, list(rvw(paste0("R-P1-", tg), "philosophy", "P1", cid), rvw(paste0("R-T1-", tg), "judgment", "T1", cid),
                       rvw(paste0("R-P2-", tg), "philosophy", "P2", cid, file = sprintf("04_Research/programs/_supervision/superfan/philosophy/20261110_1300_P2_%s.md", tg)),
                       rvw(paste0("R-T2-", tg), "judgment", "T2", cid, file = sprintf("04_Research/programs/_supervision/superfan/20261110_1300_T2_%s.md", tg))))
}
LREV <- c(LREV, list(
  rvw("R-T1OPEN-P4C96", "judgment", "T1", "P4C96_measure", file = "04_Research/programs/_supervision/superfan/20261110_1210_T1_open.md", challenges = list("C-OPEN")),
  rvw("R-T1-NOFILE", "judgment", "T1", "P4C96_measure", file = "04_Research/programs/_supervision/superfan/20261110_1211_T1_nofile.md", mkfile = FALSE),
  rvw("R-T1-NOROUND", "judgment", "T1", NULL, file = "04_Research/programs/_supervision/superfan/20261110_1212_T1_noround.md"),
  rvw("R-T2HOLD-P4C99", "judgment", "T2", "P4C99_selftest", file = "04_Research/programs/_supervision/superfan/20261110_1213_T2_hold.md", challenges = list("C-HOLD")),
  rvw("R-GEN-g2", "philosophy", "P4", "P4_generator_g2", file = "04_Research/programs/_supervision/superfan/philosophy/20261110_1400_P4_gen_g2.md"),
  rvw("R-GEN-g9", "philosophy", "P4", "P4_generator_g9", file = "04_Research/programs/_supervision/superfan/philosophy/20261110_1401_P4_gen_g9.md"),
  rvw("R-GENHOLD-g2", "philosophy", "P4", "P4_generator_g2", file = "04_Research/programs/_supervision/superfan/philosophy/20261110_1402_P4_gen_hold.md", challenges = list("C-GHOLD"))))
rc_json_write(list(schema = "q_judgment_ledger_v1", judgments = list(), reviews = LREV, challenges = list(
  list(id = "C-OPEN", review = "R-T1OPEN-P4C96", grade = "challenge", status = "open", hold_request = FALSE, responses = list()),
  list(id = "C-HOLD", review = "R-T2HOLD-P4C99", grade = "stop", status = "rebutted", hold_request = TRUE, responses = list(list(by = "Q", text = "반론"))),
  list(id = "C-GHOLD", review = "R-GENHOLD-g2", grade = "challenge", status = "countered", hold_request = TRUE, responses = list(list(by = "Q", text = "반론"))))), LEDG)
RCPT <- function(cid) { tg <- sub("_.*$", "", cid); list(p1 = paste0("R-P1-", tg), t1 = paste0("R-T1-", tg), p2 = paste0("R-P2-", tg), t2 = paste0("R-T2-", tg)) }
NO_GATE <- file.path(SB, "no_such_gate.R")
close4 <- function(cd, cid, ...) { r <- RCPT(cid); rc_p4_close(cd, ..., root = ROOT, outcomes_path = OUTC, philosophy_p2 = r$p2, superfan_t2 = r$t2,
                                                             ledger = LEDG, review_root = RVR, gate_file = NO_GATE) }

ST_ENG <- mk_eng("standing_short")
STQ <- data.table(round_id = "P1S99_t", edition = 1L, code = "P1S99_x", engine = "x", engine_path = ST_ENG, engine_md5 = rc_md5(ST_ENG), engine_same = TRUE,
                  artifacts = A_S3, paper_key = "9903.00001", verdict_at = "2026-11-10T12:00:00+0900", ledger = "t")
STQ2 <- copy(STQ)[, `:=`(code = "P1S99_y", engine_path = mk_eng("standing_changed"), engine_same = FALSE)]

cat("A 경로 · 기저 풀\n")
chk("A1 다른 기기 절대 경로(C:\\Users\\99922\\OneDrive\\…) → 저장소 상대", identical(.rcp4_rel("C:\\Users\\99922\\OneDrive\\Quant_Module_Moltbot/04_Research/strategies/X/engine.R"),
                                                                       "04_Research/strategies/X/engine.R") &&
      identical(.rcp4_rel("C:/Users/99922/OneDrive/Quant_Module_Moltbot/stage_artifacts/replication/r1"), "stage_artifacts/replication/r1") &&
      identical(.rcp4_rel(file.path(ROOT, "06_Registry/x.json")), "06_Registry/x.json"))
POOL <- rc_p4_base_pool(ROOT, registry_path = REG, standing = rbind(STQ, STQ2), fdv_ledger_path = FDVL)
rs <- function(k) strsplit(POOL[key == k]$reason, ";", fixed = TRUE)[[1]]
chk("A2 자격 = 권위 등급 B · 롱온리 · 감사 통과 · 꼬리표 없음 · 수리 뒤 측정", isTRUE(POOL[key == "engine:T_ok"]$eligible), POOL[key == "engine:T_ok"]$reason)
want <- list(short = "needs_long_leg", suspect = "implementation_suspect", suspna = "implementation_suspect", misdecl = "audit_not_passed",
             gradec = "not_qualified", stale = "factor_db_stale", noeng = "no_engine")
for (k in names(want)) chk(sprintf("A3 %s → %s", k, want[[k]]), want[[k]] %in% rs(paste0("engine:T_", k)) && !isTRUE(POOL[key == paste0("engine:T_", k)]$eligible),
                           POOL[key == paste0("engine:T_", k)]$reason)
chk("A4 팩터 DB 판 양방향 — 같은 등급 B · 수리 앞 측정 = 제외 · 수리 뒤 = 통과(같은 임시 원장)",
    isTRUE(POOL[key == "engine:T_stale"]$fdv_stale) && isFALSE(POOL[key == "engine:T_ok"]$fdv_stale) && identical(rs("engine:T_stale"), "factor_db_stale"))
POOL_nofdv <- rc_p4_base_pool(ROOT, registry_path = REG, standing = STQ, fdv_ledger_path = file.path(SB, "no_such_ledger.json"))
chk("A5 수리 원장 판독 불가 = 판정 불가(NA) — 제외하지 않고 사유만 기록", is.na(POOL_nofdv[key == "engine:T_stale"]$fdv_stale) &&
      !("factor_db_stale" %in% strsplit(POOL_nofdv[key == "engine:T_stale"]$reason, ";")[[1]]) && grepl("판정 불가", POOL_nofdv[key == "engine:T_stale"]$reason_detail))
sk <- POOL[standing_code == "P1S99_x"]
chk("A6 상설 자격 경로 — 등록부 항목 없는 엔진도 standing:<판>:<code> 행 · 롱숏 여부와 무관하게 자격(표준 구성 롱온리 측정 통과)",
    nrow(sk) == 1L && isTRUE(sk$eligible) && isTRUE(sk$standing_qualified) && grepl("^standing:P1S99_t:", sk$key) && identical(sk$artifacts, A_S3))
chk("A7 상설 판정 뒤 엔진 변경 = standing_engine_changed(자격 인정 없음)", "standing_engine_changed" %in% strsplit(POOL[standing_code == "P1S99_y"]$reason, ";")[[1]] &&
      !isTRUE(POOL[standing_code == "P1S99_y"]$eligible))
chk("A8 풀 md5 결정론 · 자격 열에 반응", identical(rc_p4_pool_md5(POOL), rc_p4_pool_md5(copy(POOL)[sample(.N)])) &&
      !identical(rc_p4_pool_md5(POOL), rc_p4_pool_md5(copy(POOL)[key == "engine:T_ok", eligible := FALSE])))
POOL_real <- tryCatch(rc_p4_base_pool(ROOT), error = function(e) e)
chk("A9 운영 등록부 판독(읽기만) — 행마다 사유 코드 어휘 안", !inherits(POOL_real, "error") &&
      all(unlist(strsplit(POOL_real$reason[nzchar(POOL_real$reason)], ";")) %in% names(RC_P4_REASONS)), if (inherits(POOL_real, "error")) conditionMessage(POOL_real) else "")

cat("B 격차(보는 창)\n")
G <- rc_p4_gap(A_BASE, ROOT); G2 <- rc_p4_gap(A_POST, ROOT)
chk("B1 보는 창만 — 창 끝 ≤ τ_D · 기록에 τ_D 뒤 날짜 없음 · 하한 5종", G$window[2] <= TAU && !length(rc_after_tau_leaks(G, TAU)) &&
      identical(G$floors$floor, c("S", "port_t", "calmar", "cagr", "sharpe")))
chk("B2 시험 창 무감(양성 대조) — τ_D 뒤만 다른 두 산출 = 같은 격차", isTRUE(all.equal(G$floors$value, G2$floors$value)) && identical(G$bottleneck, G2$bottleneck))
E <- rc_deps(ROOT); X <- .rcp4_read_art(A_BASE, E); w <- E$gv3_window(X$pr, X$br, X$nv, to = as.Date(TAU), root = ROOT)
chk("B3 계약 동치 — 값 = gv3_window(to = τ_D) · S = gv3_S(정본 문턱 · 가중)", isTRUE(all.equal(G$metrics$calmar_vis, w$calmar)) &&
      isTRUE(all.equal(G$metrics$S_vis, E$gv3_S(w$calmar, w$port_t, E$gv3_thresholds(ROOT), E$gv3_cfg(ROOT)$weights))))
fl <- G$floors[is.finite(margin_rel)]
chk("B4 병목 = 상대 여유 최소 하한 · 통과 = 값 ≥ 문턱", identical(G$bottleneck, fl$floor[which.min(fl$margin_rel)]) && all(G$floors$pass == (G$floors$value >= G$floors$threshold)))
VM <- rc_p4_visible_metrics(A_BASE, ROOT, bm_hist = NULL); VM2 <- rc_p4_visible_metrics(A_POST, ROOT, bm_hist = NULL)
chk("B5 보는 창 행동 카드(상승 포착 · 위기 하락 포착) — 유한 · 시험 창 무감", is.finite(VM$uc_vis) && is.finite(VM$dd_capture_median_vis) &&
      isTRUE(all.equal(VM$uc_vis, VM2$uc_vis)) && isTRUE(all.equal(VM$dd_capture_median_vis, VM2$dd_capture_median_vis)), VM$card_error)

cat("C 사슬 판 검사\n")
CS <- file.path(SB, "cells"); dir.create(CS, showWarnings = FALSE)
base_spec <- list(code = "B0", label = "기저", block = "RX", fixed_axes = list(long_only = TRUE, n_max = 25L, commission_bps = 15L, measurement_axis = "x"),
                  base_signal = list(kind = "engine", path = ITEMS[[1]]$engine_path), base_weight = 0.5, factors = list(), weighting = list(kind = "ew"),
                  defense_sleeve = NULL, universe = list(kind = "all_hyg"), selection_accounting = list(selection_type = "chain"))
wspec <- function(nm, s) { p <- file.path(CS, paste0(nm, ".json")); rc_json_write(s, p); p }
BASE_CELL <- wspec("base", base_spec)
RULES <- list(
  list(id = "improve", type = "threshold", label = "보는 창 S 개선", metric = "dS_vis", op = ">=",
       value_ref = "04_Research/programs/P3_CONSTRUCTION/P3R03_advanced_construction/prereg.json::final_selection_rule.tie_eps",
       source = "S 비열등 여유 tie_eps(P0R01 → P3R01 · P3R02 · P3R03 사전등록 승계)"),
  list(id = "uc_floor", type = "threshold", label = "상승 포착 하한", metric = "uc_vis", op = ">=", value_ref = "06_Registry/behavior_card.json::uc_floor",
       source = "투자철학 헌장 강세 참여 ≥ 55%(behavior_card.json::uc_floor_source)"),
  list(id = "crisis_no_worse", type = "threshold", label = "위기 하락 포착 비악화", metric = "d_dd_capture_median_vis", op = "<=", value = 0,
       basis = "정의 — 비악화 = 부모 이하(새 숫자 없음)", source = "정의"),
  list(id = "bull_segments", type = "threshold", label = "강세 구간별 참여(N1)", metric = "uc_seg_ok_share_vis", op = ">", value_ref = "06_Registry/behavior_card.json::majority_share",
       source = "헌장 §5 빈칸 4 · 7 · 24(시험)"),
  list(id = "deep_crisis", type = "threshold", label = "깊은 위기 과반 비악화(N2)", metric = "deep_crisis_nonworse_share_vis", op = ">", value_ref = "06_Registry/behavior_card.json::majority_share",
       source = "헌장 §5 빈칸 2 · 23(시험)"))
BUD <- list(max_steps = 5L, max_steps_source = "시험 사양 작성자 지정(시험)", noise_k = 2L, noise_k_source = "시험 사양 작성자 지정(시험)")
CD <- file.path(SB, "chain", "P4C99_selftest")
chk("C0 풀 밖 기저 = 거부 · 자격 미달 기저 = 거부", grepl("풀 밖", err_of(rc_p4_chain_new(file.path(SB, "x1"), "P4C98_x", "engine:NOPE", POOL, BASE_CELL, RULES, BUD))) &&
      grepl("자격 미달", err_of(rc_p4_chain_new(file.path(SB, "x2"), "P4C98_x", "engine:T_short", POOL, BASE_CELL, RULES, BUD))))
chk("C1 사슬 판 생성 · 검사 통과(양성 대조)", identical(err_of(rc_p4_chain_new(CD, "P4C99_selftest", "engine:T_ok", POOL, BASE_CELL, RULES, BUD, purpose = "자체 시험")), ""))
S0 <- rc_json_read(rc_p4_spec_path(CD)); RR <- rc_p4_chain_check(S0, ROOT)
chk("C2 규칙 해석 — 개선 여유 = 정본 참조값 · 상승 포착 = behavior_card uc_floor", identical(RR[[1]]$value, rc_ref_value(RULES[[1]]$value_ref)) &&
      identical(RR[[2]]$value, rc_ref_value("06_Registry/behavior_card.json::uc_floor")))
inj <- function(f) { s <- S0; s <- f(s); err_of(rc_p4_chain_check(s, ROOT)) }
chk("C3 시험 창 지표 규칙 = 거부(S_test)", grepl("시험 창", inj(function(s) { s$adoption$rules[[1]]$metric <- "S_test"; s })))
chk("C4 전 기간 지표 규칙 = 거부(calmar_full · cr_overall · oos)", grepl("시험 창", inj(function(s) { s$adoption$rules[[1]]$metric <- "calmar_full"; s })) &&
      grepl("시험 창", inj(function(s) { s$adoption$rules[[1]]$metric <- "cr_overall"; s })) && grepl("시험 창", inj(function(s) { s$adoption$rules[[1]]$metric <- "S_oos"; s })))
chk("C5 판정 표 밖 지표 = 거부", grepl("판정 표 열 밖", inj(function(s) { s$adoption$rules[[1]]$metric <- "grade"; s })))
chk("C6 출처 문구 없는 규칙 = 거부", grepl("출처", inj(function(s) { s$adoption$rules[[2]]$source <- NULL; s })))
chk("C7 필수 지표(위기 비악화) 빠짐 = 거부", grepl("필수 지표", inj(function(s) { s$adoption$rules[[3]] <- NULL; s })))
chk("C8 예산 출처 없음 · 정수 아님 = 거부", grepl("noise_k_source", inj(function(s) { s$budget$noise_k_source <- NULL; s })) &&
      grepl("정수", inj(function(s) { s$budget$max_steps <- 2.5; s })))
chk("C9 생성기 md5 ≠ 등록부 = 거부", grepl("등록부", inj(function(s) { s$generator$files[[1]] <- "00000000000000000000000000000000"; s })))
chk("C10 수치 문턱 근거 없음(value · basis 없음) = 거부(하드코딩 금지)", grepl("근거", inj(function(s) { s$adoption$rules[[3]]$basis <- NULL; s })))
chk("C11 사양 글에 τ_D 뒤 날짜 = 거부", grepl("τ_D", inj(function(s) { s$purpose <- "2024-08-05 급락 대응"; s })))

cat("D 등록 · 걸음 열기\n")
stub <- list()
## 헌장 빈칸 지표(N1 · N2)의 재료 = 고정 합성 표(강세 3 · 위기 4 · 전부 보는 창) — 실지표 칸은 상승 포착 1 · 하락 포착 1 로 둔다(판정 결과는 S · 중앙값 규칙이 가른다)
FIX_BULL <- function(up = 1) data.table(start_ym = c("2003-04", "2009-03", "2016-02"), end_ym = c("2004-03", "2010-12", "2017-10"), up_capture = up)
FIX_CR <- function(dd = 1) data.table(peak_date = c("2002-04-18", "2008-05-16", "2011-05-02", "2020-01-22"), trough_date = c("2002-09-30", "2008-10-24", "2011-09-26", "2020-03-19"),
                                      bm_dd = c(0.30, 0.50, 0.25, 0.35), dd_capture = dd, st_recovery_obs = 100, st_recovery_censored = FALSE)
mfun <- function(artifacts, root, tau, ...) { k <- basename(artifacts); if (!is.null(stub[[k]])) stub[[k]] else
  { m <- rc_p4_visible_metrics(artifacts, root, tau, bm_hist = NULL); m[c("bull_vis", "crises_vis")] <- list(FIX_BULL(), FIX_CR()); m } }   # 얕은 교체(modifyList 는 표 열을 재귀로 섞는다)
RUN <- new.env(); RUN$n <- 0L; RUN$spec <- NULL; RUN$roles <- character(0)
runner_to <- function(art) function(spec_path, code, out_json, log_dir, root, role) {
  RUN$n <- RUN$n + 1L; RUN$spec <- rc_json_read(spec_path); RUN$code <- code; RUN$role <- role; RUN$roles <- c(RUN$roles, role)
  rc_json_write(list(n = 1L, code = code, ok = TRUE, grade = "C", artifacts = art), out_json); 0L }
held <- function(root) list(state = "held", reason = "alive", lock = "refresh", blocking = TRUE)
free <- function(root) list(state = "free", reason = "", lock = "", blocking = FALSE)
FP <- function() "fp-same"
FRESH <- function(root) list(ok = TRUE, state = "fresh", reason = "시험 주입")   # 신선도 판정(v1/freshness.R) 주입 — 실데이터 날짜와 무관하게
VINT <- function(root) list(id = "vint-1", n_repairs = 1L); VINT2 <- function(root) list(id = "vint-2", n_repairs = 2L)
bmeas <- function(cd, art, mf = mfun) rc_p4_base_measure(cd, ROOT, runner = runner_to(art), barrier = free, fingerprint = FP, vintage = VINT, freshness = FRESH, metrics_fun = mf)
smeas <- function(cd, k, art) rc_p4_step_measure(cd, k, ROOT, runner = runner_to(art), barrier = free, fingerprint = FP, vintage = VINT, freshness = FRESH)
md <- function(cd, k, art) { invisible(smeas(cd, k, art)); rc_p4_step_decide(cd, k, root = ROOT, metrics_fun = mfun) }
reg4 <- function(cd, cid, pool = POOL, mf = mfun, p1 = RCPT(cid)$p1, t1 = RCPT(cid)$t1)
  rc_p4_chain_register(cd, pool, ROOT, metrics_fun = mf, p1 = p1, t1 = t1, ledger = LEDG, review_root = RVR)
chk("D0 풀이 사양 스냅샷과 다르면 등록 거부", grepl("pool_md5", err_of(reg4(CD, "P4C99_selftest", pool = copy(POOL)[key == "engine:T_ok", reason := "x"]))))
chk("D0b 감독 영수증 없는 등록 = 거부(철학 P1 · 판단 T1 각각) · 원장 무기록", grepl("영수증", err_of(reg4(CD, "P4C99_selftest", p1 = NULL))) &&
      grepl("영수증", err_of(reg4(CD, "P4C99_selftest", t1 = NULL))) && rc_p4_steps_verify(CD)$n == 0L)
chk("D1 등록(원장 첫 줄 — 기저 보는 창 지표 실측 · 규칙 해석본)", identical(err_of(reg4(CD, "P4C99_selftest")), ""))
ST <- .rcp4_state(CD, ROOT)
chk("D2 등록 기록 — 기저 S_vis 유한 · 해석 규칙 3 · 영수증 id · 두 번 등록 거부", is.finite(.rcp4_num(ST$reg$base_metrics$S_vis)) && length(ST$reg$rules_resolved) == 5L &&
      identical(ST$reg$superfan$philosophy_p1$id, "R-P1-P4C99") && identical(ST$reg$superfan$superfan_t1$id, "R-T1-P4C99") &&
      grepl("이미 등록", err_of(reg4(CD, "P4C99_selftest"))))
s1 <- base_spec; s1$overlay <- list(kind = "dd_brake", arm_id = "dd_brake_q"); C1 <- wspec("s1", s1)
H <- "낙폭 브레이크 층이 깊은 위기의 하락 포착을 낮춘다"; M <- "보유 시작 전 낙폭 신호로 노출을 줄여 위기 구간 손실 경로를 자른다"
chk("D2b 기준 칸 미측정 = 걸음 열기 · 측정 · 판정 · 설계 입력 거부('기준 칸 측정 먼저') · 원장 무기록",
    grepl("기준 칸 측정 먼저", err_of(rc_p4_step_open(CD, 1, H, M, "regime_exposure", C1, 0, "g1", root = ROOT, pool = POOL))) &&
      grepl("기준 칸 측정 먼저", err_of(smeas(CD, 1, A_S1))) && grepl("기준 칸 측정 먼저", err_of(rc_p4_step_decide(CD, 1, root = ROOT, metrics_fun = mfun))) &&
      grepl("기준 칸 측정 먼저", err_of(rc_p4_design_input(ROOT, CD, pool = POOL, outcomes_path = OUTC))) && rc_p4_steps_verify(CD)$n == 1L &&
      grepl("기준 칸 미측정", rc_p4_status(CD, ROOT)[1]))
RUN$roles <- character(0); bm0 <- bmeas(CD, A_BASE); BMR <- Filter(function(r) identical(r$event, "base_measured"), rc_p4_steps_read(CD))
chk("D2c 기준 칸 측정 — base_measured{artifacts · measured_spec_md5 · 보는 창 metrics · vintage · measured_at} · 시행 1 · sweep · role base · 다시 = already",
    identical(bm0$status, "measured") && length(BMR) == 1L && identical(BMR[[1]]$artifacts, .rcp4_rel(A_BASE)) && is.finite(.rcp4_num(BMR[[1]]$metrics$S_vis)) &&
      identical(BMR[[1]]$vintage$id, "vint-1") && !is.null(BMR[[1]]$measured_at) && identical(RUN$roles, "base") &&
      identical(RUN$spec$selection_accounting$selection_type, "sweep") && identical(as.integer(RUN$spec$selection_accounting$n_family_at_registration), 1L) &&
      identical(RUN$spec$selection_accounting$family_root, "P4C99_selftest") && identical(bmeas(CD, A_BASE)$status, "already") &&
      grepl("기준 칸 측정", rc_p4_status(CD, ROOT)[1]))
open1 <- function(...) err_of(rc_p4_step_open(CD, ..., root = ROOT, pool = POOL))
s2 <- s1; s2$weighting <- list(kind = "inv_vol", window = 60L); C_TWO <- wspec("two", s2)
chk("D3 두 블록(오버레이 + 비중)을 한 걸음에 = 거부", grepl("블록", open1(1, H, M, "regime_exposure", C_TWO, 0, "g1")))
sf <- base_spec; sf$fixed_axes$n_max <- 30L; C_FIX <- wspec("fix", sf)
chk("D4 고정 축 변경 = 거부", grepl("고정 축", open1(1, H, M, "construction", C_FIX, 0, "g1")))
chk("D5 부모와 같은 칸(바뀐 축 없음) · 기저 칸 재사용 = 거부", grepl("같은 칸|이미 쓴", open1(1, H, M, "weighting", BASE_CELL, 0, "g1")))
chk("D6 칸 2개 = 거부(한 걸음 = 칸 하나)", grepl("정확히 1개", open1(1, H, M, "regime_exposure", c(C1, C_TWO), 0, "g1")))
chk("D7 가설 · 기전 글에 τ_D 뒤 날짜 = 거부", grepl("τ_D", open1(1, "2024-08-05 급락을 막는다", M, "regime_exposure", C1, 0, "g1")) &&
      grepl("τ_D", open1(1, H, "2023-03 위기 경로", "regime_exposure", C1, 0, "g1")))
chk("D8 기전 문장 없음 = 거부", grepl("mechanism", open1(1, H, "  ", "regime_exposure", C1, 0, "g1")))
chk("D9 블록 어휘 밖 = 거부 · 부모 ≠ 머리 = 거부", grepl("어휘 밖", open1(1, H, M, "magic", C1, 0, "g1")) && grepl("머리", open1(1, H, M, "regime_exposure", C1, 3, "g1")))
sb <- base_spec; sb$base_signal <- list(kind = "engine", path = ITEMS[[2]]$engine_path); C_OUT <- wspec("outpool", sb)
chk("D10 풀(자격) 밖 기저로 바꾸는 걸음 = 거부", grepl("풀\\(자격\\) 밖", open1(1, H, M, "base", C_OUT, 0, "g1")))
chk("D11 생성기 판 id ≠ 사슬 판 = 거부", grepl("생성기 판", open1(1, H, M, "regime_exposure", C1, 0, "g2")))
gm <- file.path(GD1, "step.md"); gb <- readBin(gm, "raw", file.info(gm)$size); cat("\n<!-- 무등록 수정 -->\n", file = gm, append = TRUE)
chk("D12 낡은 생성기(디스크 md5 ≠ 사슬 판) = 거부 · 사슬 판 검사도 거부", grepl("md5", open1(1, H, M, "regime_exposure", C1, 0, "g1")) && grepl("디스크", err_of(rc_p4_chain_check(S0, ROOT))))
writeBin(gb, gm)
chk("D13 원장은 거부된 걸음을 쓰지 않았다(등록 1줄 + 기준 칸 1줄)", rc_p4_steps_verify(CD)$n == 2L)
chk("D14 정상 걸음 열기(양성 대조 — 오버레이 1블록 · 부모 기저)", identical(open1(1, H, M, "regime_exposure", C1, 0, "g1"), ""))
s3 <- s1; s3$overlay <- list(kind = "vol_scale", arm_id = "vol_scale_x"); C3 <- wspec("s3", s3)
chk("D15 판정 안 된 걸음 위에 여는 걸음 = 거부", grepl("판정되지 않았다", open1(2, H, M, "tail_overlay", C3, 1, "g1")))
chk("D16 판정 안 된 걸음이 있으면 닫기 거부", grepl("판정 안 된", err_of(close4(CD, "P4C99_selftest", "n", probes = c("a", "b")))))
sp_b <- readBin(rc_p4_spec_path(CD), "raw", file.info(rc_p4_spec_path(CD))$size); cat(" ", file = rc_p4_spec_path(CD), append = TRUE)
chk("D17 등록 뒤 사슬 판 변경 = 판정 거부(R2)", grepl("R2", err_of(rc_p4_step_decide(CD, 1, A_S1, ROOT, metrics_fun = mfun))))
writeBin(sp_b, rc_p4_spec_path(CD))

cat("E 걸음 판정 · 예산 · 원장\n")
bmv <- ST$reg$base_metrics; mkm <- function(dS, uc, ddd) list(S_vis = .rcp4_num(bmv$S_vis) + dS, uc_vis = uc, dd_capture_median_vis = .rcp4_num(bmv$dd_capture_median_vis) + ddd,
                                                              calmar_vis = 1, port_t_vis = 1, cagr_vis = 0.1, sharpe_vis = 1, mdd_vis = 0.2, window = c("2000-01-31", TAU),
                                                              bull_vis = FIX_BULL(), crises_vis = FIX_CR(1 + ddd))
stub$s1 <- mkm(0.05, 0.60, -0.01)
r1 <- tryCatch(md(CD, 1, A_S1), error = function(e) e)
chk("E1 채택(개선 ≥ 여유 · 상승 포착 ≥ 하한 · 위기 비악화) · r7 signal", !inherits(r1, "error") && identical(r1$decision, "accept") && identical(r1$r7, "signal"),
    if (inherits(r1, "error")) conditionMessage(r1) else paste(unlist(r1$reasons)))
chk("E2 같은 걸음 다시 판정 = 거부", grepl("이미 판정", err_of(rc_p4_step_decide(CD, 1, A_S1, ROOT, metrics_fun = mfun))))
chk("E3 머리 = 걸음 1 · 부모 0 으로 여는 걸음 = 거부", identical(.rcp4_state(CD, ROOT)$head_k, 1L) && grepl("머리", open1(2, H, M, "tail_overlay", C3, 0, "g1")))
chk("E4 걸음 2 열기(부모 1 · 꼬리 오버레이)", identical(open1(2, H, M, "tail_overlay", C3, 1, "g1"), ""))
stub$s2 <- mkm(0.05 + 0.005, 0.60, -0.01)           # 부모(걸음 1) 대비 +0.005 = 여유 이내
r2 <- md(CD, 2, A_S2)
chk("E5 부모 대비 개선이 여유 이내 = 기각 · 사유 improve · r7 noise", identical(r2$decision, "reject") && any(grepl("^improve", unlist(r2$reasons))) && identical(r2$r7, "noise"))
s4 <- s1; s4$rebalance <- list(kind = "interval", k = 2L, phase = 0L); C4 <- wspec("s4", s4)
chk("E6 머리는 그대로 걸음 1(기각은 머리를 옮기지 않는다)", identical(.rcp4_state(CD, ROOT)$head_k, 1L) && identical(open1(3, H, M, "rebalance", C4, 1, "g1"), ""))
stub$s3 <- list(S_vis = NA_real_, uc_vis = 0.6, dd_capture_median_vis = 0.1)
r3 <- md(CD, 3, A_S3)
chk("E7 미측정 = 기각(통과로 접지 않는다) · r7 NA(연속을 끊지도 잇지도 않는다)", identical(r3$decision, "reject") && any(grepl("미측정", unlist(r3$reasons))) && is.na(r3$r7))
s5 <- s1; s5$universe <- list(kind = "k200_kq150"); C5 <- wspec("s5", s5)
invisible(open1(4, H, M, "universe", C5, 1, "g1")); stub$s4 <- mkm(0.05 - 0.001, 0.60, -0.01); r4 <- md(CD, 4, A_S4)
s6 <- s1; s6$cap_core <- list(k = 5L, satellite = "floor"); C6 <- wspec("s6", s6)
chk("E8 연속 '잡음 이내' K(2) = 예산 소진 — 걸음 열기 거부", identical(r4$r7, "noise") && grepl("예산 소진", open1(5, H, M, "construction", C6, 1, "g1")))
stub$uc <- mkm(0.10, 0.40, -0.01)
chk("E9 상승 포착 하한 미달 · 위기 악화는 각각 기각 사유(판정 표 단위 검사)", {
  T1 <- data.table(dS_vis = 0.1, uc_vis = 0.40, d_dd_capture_median_vis = -0.01); A1 <- rc_rules_apply(ST$reg$rules_resolved, T1)
  T2 <- data.table(dS_vis = 0.1, uc_vis = 0.60, d_dd_capture_median_vis = 0.02); A2 <- rc_rules_apply(ST$reg$rules_resolved, T2)
  isFALSE(A1$uc_floor) && isTRUE(A1$improve) && isFALSE(A2$crisis_no_worse) })
L <- readLines(rc_p4_steps_path(CD), encoding = "UTF-8"); lb <- readBin(rc_p4_steps_path(CD), "raw", file.info(rc_p4_steps_path(CD))$size)
L2 <- L; iL <- grep("낙폭", L2, fixed = TRUE)[1]; L2[iL] <- sub("낙폭", "낙X", L2[iL], fixed = TRUE); writeLines(L2, rc_p4_steps_path(CD), useBytes = TRUE)   # 첫 걸음 열기 줄(등록 · 기준 칸 줄 다음)
chk("E10 걸음 원장 중간 줄 변조 = 사슬 끊김 · 판독 거부", !rc_p4_steps_verify(CD)$ok && grepl("끊", rc_p4_status(CD, ROOT)[1]))
writeBin(lb, rc_p4_steps_path(CD))
chk("E11 복원 뒤 사슬 정상 · 상태 줄(걸음 4 · 채택 1 · 기각 3 · 머리 걸음 1)", rc_p4_steps_verify(CD)$ok && grepl("걸음 4\\(판정 4 · 채택 1 · 기각 3\\)", rc_p4_status(CD, ROOT)[1]) &&
      grepl("머리 = 걸음 1", rc_p4_status(CD, ROOT)[1]), rc_p4_status(CD, ROOT)[1])
chk("E12 원장 지표 · 판정 기록에 τ_D 뒤 날짜 없음(보는 창만 · 기록 시각 at 은 메타)", !length(rc_after_tau_leaks(lapply(rc_p4_steps_read(CD), function(r) r[setdiff(names(r), c("at", "prev", "measured_at"))]), TAU)))
chk("E13 판정 산출 = 측정 기록(artifacts_source step_measured) · 첫 걸음 부모 기준 = base_measured", all(vapply(Filter(function(r) identical(r$event, "step_result"), rc_p4_steps_read(CD)),
                                                                          function(r) identical(r$artifacts_source, "step_measured"), TRUE)) &&
      identical(Filter(function(r) identical(r$event, "step_result"), rc_p4_steps_read(CD))[[1]]$parent_basis, "base_measured"))

cat("F 설계 입력\n")
DI <- tryCatch(rc_p4_design_input(ROOT, CD, pool = POOL, outcomes_path = OUTC), error = function(e) e)
chk("F1 설계 입력 생성 — 병목 · 걸음 이력 · 채택 규칙 · 도구 상자 안내", !inherits(DI, "error") && grepl("병목", DI) && grepl("걸음 2 \\[tail_overlay", DI) &&
      grepl("보는 창 S 개선", DI) && grepl("blend = base_signal", DI), if (inherits(DI, "error")) conditionMessage(DI) else "")
chk("F2 보는 창만 — τ_D 뒤 날짜 · 등급 표기 · 등급 열 없음", !inherits(DI, "error") && !length(rc_after_tau_leaks(DI, TAU)) &&
      !grepl("(등급|Grade|grade)\\s*[ABCF](?![A-Za-z])", DI, perl = TRUE) && !grepl("| grade |", DI, fixed = TRUE))
bad_out <- file.path(SB, "outcomes_leak.jsonl")
writeLines(as.character(jsonlite::toJSON(list(schema = RC_OUTCOME_SCHEMA, kind = "round", program = "P2_DEFENSE", round_id = "P2R99_x", verdict_label = "x", note = "n",
                                              probes = list("2024-08-05 급락을 다시 본다", "b"), lessons = list()), auto_unbox = TRUE)), bad_out)
DI3 <- tryCatch(suppressWarnings(rc_p4_design_input(ROOT, CD, pool = POOL, outcomes_path = bad_out)), error = function(e) conditionMessage(e))
chk("F3 결과 원장에 τ_D 뒤 날짜가 섞인 줄 = 설계 입력에서 그 줄만 빠진다(11-10 감사 K P1 — 멈추지 않고 · 누출 없음)", is.character(DI3) && !grepl("2024-08-05", DI3, fixed = TRUE) && grepl("P4 강화 사슬 설계 입력", DI3, fixed = TRUE))

cat("G 닫기\n")
chk("G1 다음 탐침 2개 미만 = 닫기 거부", grepl("탐침", err_of(close4(CD, "P4C99_selftest", "해석", probes = "하나"))))
cx <- function(p2, t2) err_of(rc_p4_close(CD, "n", probes = c("a", "b"), root = ROOT, outcomes_path = OUTC, philosophy_p2 = p2, superfan_t2 = t2,
                                         ledger = LEDG, review_root = RVR, gate_file = NO_GATE))
chk("G0 감독 영수증 없는 닫기 = 거부(P2 없음 · T2 없음 · 남의 사슬 P2 · T2 자리에 철학 리뷰 · 열린 보류 요청) · 결과 원장 무기록",
    grepl("영수증", cx(NA, "R-T2-P4C99")) && grepl("영수증", cx("R-P2-P4C99", NA)) && grepl("대상", cx("R-P2-P4C97", "R-T2-P4C99")) &&
      grepl("요구", cx("R-P2-P4C99", "R-P2-P4C99")) && grepl("보류", cx("R-P2-P4C99", "R-T2HOLD-P4C99")) && !length(rc_outcomes_read(OUTC, program = "P4_ASSEMBLY")))
CL <- tryCatch(close4(CD, "P4C99_selftest", "오버레이 낙폭 브레이크가 보는 창 S 를 올렸다", probes = c("꼬리 오버레이를 다른 기저에서", "비중 블록"),
                      lessons = "기각 3 은 잡음 이내"), error = function(e) e)
O <- rc_outcomes_read(OUTC, program = "P4_ASSEMBLY")
chk("G2 결과 원장 — 사슬 1줄 · 최종 후보 = 마지막 채택(걸음 1) · extra(생성기 판 · 걸음 수 · 블록 유형별)", !inherits(CL, "error") && length(O) == 1L &&
      identical(O[[1]]$round_id, "P4C99_selftest") && identical(as.integer(O[[1]]$extra$final_candidate$k), 1L) && identical(O[[1]]$extra$generator_version, "g1") &&
      identical(as.integer(O[[1]]$extra$n_steps), 4L) && identical(as.integer(O[[1]]$extra$by_block$regime_exposure$accept), 1L) &&
      identical(as.integer(O[[1]]$extra$by_block$tail_overlay$reject), 1L) && identical(O[[1]]$r7, "signal"),
    if (inherits(CL, "error")) conditionMessage(CL) else "")
chk("G3 마감 훅 — selection_regrade.R 호출 · 결과는 finalize.json(사람 쪽)에만 · 원장엔 상태 · md5", !inherits(CL, "error") && identical(CL$finalize$status, "done") &&
      file.exists(file.path(CD, "finalize.json")) && identical(O[[1]]$extra$finalize$md5, rc_md5(file.path(CD, "finalize.json"))) &&
      is.null(O[[1]]$extra$finalize$grade_after) && !is.na(O[[1]]$extra$finalize$regrade_status))
chk("G3b 후보 관문 파일 없음 = candidate_gate pending(원장 · 결과 원장 = 상태 문자열만) · 영수증 id 기록", !inherits(CL, "error") &&
      identical(O[[1]]$extra$finalize$candidate_gate, "pending") && identical(O[[1]]$extra$philosophy_p2, "R-P2-P4C99") &&
      identical(O[[1]]$extra$superfan_t2, "R-T2-P4C99") && identical(rc_json_read(file.path(CD, "finalize.json"))$candidate_gate$status, "pending"))
chk("G4 두 번 닫기 = 거부 · 닫힌 사슬에 걸음 열기 = 거부", grepl("이미 닫힌", err_of(close4(CD, "P4C99_selftest", "n", probes = c("a", "b")))) &&
      grepl("닫힌 사슬", open1(5, H, M, "construction", C6, 1, "g1")))
CD2 <- file.path(SB, "chain", "P4C97_none"); invisible(rc_p4_chain_new(CD2, "P4C97_none", "engine:T_ok", POOL, BASE_CELL, RULES, BUD))
invisible(reg4(CD2, "P4C97_none", mf = function(a, root, tau, ...) bmv))
c2 <- close4(CD2, "P4C97_none", "걸음 없음", no_probes_reason = "시험 — 걸음을 열지 않았다")
chk("G5 채택 없는 사슬 = '개선 없음' · 마감 no_candidate · Judge 요청 파일 없음", identical(c2$finalize$status, "no_candidate") && grepl("개선 없음", c2$label) &&
      !length(list.files(c(CD, CD2), pattern = "judge_request", recursive = TRUE)))

cat("H 생성기 판 · 검토\n")
chk("H1 rxg_pin(등록부 = 디스크) · 현재 판 g1", identical(rxg_pin(root = ROOT)$id, "g1") && identical(rxg_current(ROOT)$id, "g1"))
GD2 <- file.path(SB, "gen", "g2"); dir.create(GD2); writeLines(c(readLines(file.path(GD1, "step.md"), encoding = "UTF-8"), "", "## g2 — 기각 사유 우선 읽기"), file.path(GD2, "step.md"), useBytes = TRUE)
chk("H2 근거 round_id 가 결과 원장에 없으면 개정 거부", grepl("결과 원장에 없는", err_of(rxg_revise(GD2, "기각 사유 우선", "P4C00_nope", ROOT, outcomes_path = OUTC))))
writeLines("x", file.path(GD2, "rules.json"))
chk("H3 판정 규칙 · 설정 파일이 든 판 = 개정 거부(생성기는 프롬프트만)", grepl("프롬프트\\(md\\)만", err_of(rxg_revise(GD2, "r", "P4C99_selftest", ROOT, outcomes_path = OUTC))))
unlink(file.path(GD2, "rules.json"))
chk("H4 개정 사유에 τ_D 뒤 날짜 = 거부", grepl("τ_D", err_of(rxg_revise(GD2, "2024-08 사건 반영", "P4C99_selftest", ROOT, outcomes_path = OUTC))))
g1_before <- rxg_get("g1", ROOT)
gx <- function(pr) err_of(rxg_revise(GD2, "블록별 기각 사유를 먼저 읽게 한다", c("P4C99_selftest"), ROOT, outcomes_path = OUTC, philosophy_review = pr, ledger = LEDG, review_root = RVR))
gen_md5_0 <- rc_md5(GEN_REG)
chk("H4b 철학 의견 없는 생성기 개정 = 거부(없음 · 다른 판 대상 · 판단 리뷰 · 열린 보류 요청) · 등록부 무변경",
    grepl("영수증", gx(NULL)) && grepl("대상", gx("R-GEN-g9")) && grepl("요구", gx("R-T1-P4C99")) && grepl("보류", gx("R-GENHOLD-g2")) && identical(rc_md5(GEN_REG), gen_md5_0))
rv <- tryCatch(rxg_revise(GD2, "블록별 기각 사유를 먼저 읽게 한다", c("P4C99_selftest"), ROOT, outcomes_path = OUTC, philosophy_review = "R-GEN-g2", ledger = LEDG, review_root = RVR),
               error = function(e) e)
chk("H5 개정(추가 전용) — g2 추가 · 현재 = g2 · g1 기록 불변 · 철학 의견 id 기록", !inherits(rv, "error") && identical(rxg_current(ROOT)$id, "g2") && identical(rxg_get("g1", ROOT), g1_before) &&
      identical(rxg_get("g2", ROOT)$philosophy_review, "R-GEN-g2"), if (inherits(rv, "error")) conditionMessage(rv) else "")
GD3 <- file.path(SB, "gen", "g3"); dir.create(GD3); invisible(file.copy(file.path(GD2, "step.md"), GD3))
chk("H6 기존 판과 같은 파일 = 개정 거부 · 이름 형식 g<n>", grepl("같다", err_of(rxg_revise(GD3, "r", "P4C99_selftest", ROOT, outcomes_path = OUTC))) &&
      grepl("g<번호>", err_of(rxg_revise(file.path(SB, "gen"), "r", "P4C99_selftest", ROOT, outcomes_path = OUTC))))
RV <- tryCatch(rc_p4_generator_review(ROOT, chain_dirs = c(CD, CD2), outcomes_path = OUTC), error = function(e) e)
chk("H7 생성기 검토 — 블록 유형별 채택 · 기각 · 주된 기각 사유 · 보는 창만", !inherits(RV, "error") && nrow(RV$table) == 4L &&
      grepl("| regime_exposure | 1 | 1 | 0 | 1/1 |", RV$md, fixed = TRUE) && grepl("improve", RV$md) && !length(rc_after_tau_leaks(RV$md, TAU)),
    if (inherits(RV, "error")) conditionMessage(RV) else "")

cat("I 블록 판별 · 헌장 격차 · rx_validate 기저 · CLI\n")
sfd <- base_spec; sfd$factors <- list(list(kind = "db", id = "D01_IdioVol")); sfd2 <- sfd; sfd2$factors[[1]]$direction <- "defensive"
chk("I1 팩터 방향만 바꾼 변경 = 그 팩터 블록(blend)의 변경 · 다른 블록 선언은 거부", isTRUE(rc_p4_spec_diff(sfd, sfd2, "blend", ROOT)$ok) &&
      !isTRUE(rc_p4_spec_diff(sfd, sfd2, "weighting", ROOT)$ok))
sbl <- base_spec; sbl$base_signal <- list(kind = "engine_blend", paths = list(ITEMS[[1]]$engine_path, ST_ENG))
chk("I2 기저 결합(engine_blend · 풀 자격 2개) = blend 블록 · base 선언 거부 · 풀 없이 거부",
    isTRUE(rc_p4_spec_diff(base_spec, sbl, "blend", ROOT, POOL)$ok) && !isTRUE(rc_p4_spec_diff(base_spec, sbl, "base", ROOT, POOL)$ok) &&
      !isTRUE(rc_p4_spec_diff(base_spec, sbl, "blend", ROOT, NULL)$ok))
sbo <- base_spec; sbo$base_signal <- list(kind = "engine", path = gsub("/", "\\\\", ST_ENG))
chk("I3 기저 교체(풀 자격 엔진 · 경로 표기 달라도 같은 엔진) = base 블록 통과", isTRUE(rc_p4_spec_diff(base_spec, sbo, "base", ROOT, POOL)$ok))
cg <- tryCatch(rx_charter_gap_md(G, ROOT), error = function(e) e)
chk("I4 헌장 격차 절(rx_charter_gap_md) — 하한 표 · 병목 · 처방 입력 검사 통과 · rc_p4_gap 산출만 받는다", !inherits(cg, "error") && grepl("병목", cg) &&
      grepl(G$bottleneck, cg, fixed = TRUE) && inherits(tryCatch(rx_charter_gap_md(list(a = 1), ROOT), error = function(e) e), "error"))
v_ok <- rx_validate(list(base_signal = list(kind = "engine", key = "engine:T_ok")), ROOT, pool = POOL)
chk("I5 rx_validate — 풀 자격 key = 통과 · 셀 엔진 형식(path · pool_key)으로 정규화", isTRUE(v_ok$ok) && identical(v_ok$delta$base_signal$pool_key, "engine:T_ok") &&
      identical(v_ok$delta$base_signal$path, ITEMS[[1]]$engine_path))
o <- suppressWarnings(system2("Rscript", c(shQuote(file.path(RC_DIR, "driver.R")), shQuote(CD), "p4-status"), stdout = TRUE, stderr = TRUE))
chk("I6 CLI p4-status", any(grepl("^\\[P4 사슬\\] P4C99_selftest", o)), paste(tail(o, 2), collapse = " | "))
chk("I7 운영 결과 원장 · 운영 생성기 등록부 무접촉", identical(if (file.exists("06_Registry/round_outcomes.jsonl")) rc_md5("06_Registry/round_outcomes.jsonl") else "absent", REAL_OUTC_MD5) &&
      identical(rc_md5("06_Registry/rx_generator.json"), REAL_GEN_MD5))
reg_real <- rxg_load(ROOT, file.path(ROOT, "06_Registry/rx_generator.json"))
chk("I8 운영 생성기 등록부 g1 = 저장소 프롬프트 md5(핀 일치)", identical(rxg_files_md5(reg_real$versions[[1]]$dir, ROOT), reg_real$versions[[1]]$files))

cat("J 기저 칸 사양 · 걸음 측정(가짜 러너 · 실제 측정 없음) · 후보 관문\n")
fid <- function(eng, key, title) rc_json_write(list(source_paper = list(url = paste0("https://example.org/paper/", key), title = title, paper_key = key)),
                                               file.path(dirname(eng), "FIDELITY.json"))
fid(ITEMS[[1]]$engine_path, "9902.ok", "시험 논문 ok"); fid(ST_ENG, "9903.00001", "시험 논문 상설")
BCS <- file.path(SB, "bcs", "base.json"); jb <- tryCatch(rc_p4_base_cell_spec("engine:T_ok", POOL, ROOT, BCS), error = function(e) e)
bs <- if (inherits(jb, "error")) list() else rc_json_read(BCS)
dref <- rc_p1_cell_spec(bs$code %||% "x", ITEMS[[1]]$engine_path, list(url = "https://example.org/paper/9902.ok", title = "시험 논문 ok", paper_key = "9902.ok"),
                        "9902.ok", 1L, bs$selection_accounting$n_trials_basis %||% "x", root = ROOT)
DREF <- file.path(SB, "bcs", "direct.json"); rc_json_write(dref, DREF); dj <- rc_json_read(DREF)
chk("J1 기저 칸 사양 = P1 표준 구성 생성기(rc_p1_cell_spec) 산출과 같은 모양 — 메타(p4 · 계보 표식)만 다르다 · 엔진 신호 그대로 · 시행 1",
    !inherits(jb, "error") && identical(.rcp4_js(bs[setdiff(names(bs), c("p4", "selection_accounting"))]), .rcp4_js(dj[setdiff(names(dj), "selection_accounting")])) &&
      identical(.rcp4_js(bs$selection_accounting[setdiff(names(bs$selection_accounting), "lineage")]), .rcp4_js(dj$selection_accounting[setdiff(names(dj$selection_accounting), "lineage")])) &&
      identical(bs$selection_accounting$lineage, "P4_chain_base") && identical(as.integer(bs$selection_accounting$n_family_at_registration), 1L) &&
      identical(bs$base_signal$kind, "engine") && identical(.rcp4_rel(bs$base_signal$path), .rcp4_rel(ITEMS[[1]]$engine_path)) && isFALSE(bs$p4$same_construction) &&
      identical(bs$p4$pool_key, "engine:T_ok"), if (inherits(jb, "error")) conditionMessage(jb) else "")
BCS2 <- file.path(SB, "bcs", "standing.json"); jb2 <- tryCatch(rc_p4_base_cell_spec(sk$key, POOL, ROOT, BCS2), error = function(e) e)
chk("J2 상설 자격 행 기저 = 같은 생성기 · same_construction TRUE(풀 산출이 이 표준 구성 측정)", !inherits(jb2, "error") && isTRUE(rc_json_read(BCS2)$p4$same_construction),
    if (inherits(jb2, "error")) conditionMessage(jb2) else "")
POOL_nometa <- copy(POOL)[key == "engine:T_ok", engine_path := .rcp4_rel(ITEMS[[8]]$engine_path)]
chk("J3 기저 칸 거부 — 풀 밖 · 자격 미달 · 덮어쓰기 · 논문 메타 없음",
    grepl("풀 밖", err_of(rc_p4_base_cell_spec("engine:NOPE", POOL, ROOT, file.path(SB, "bcs", "n1.json")))) &&
      grepl("자격 미달", err_of(rc_p4_base_cell_spec("engine:T_short", POOL, ROOT, file.path(SB, "bcs", "n2.json")))) &&
      grepl("덮어쓰지", err_of(rc_p4_base_cell_spec("engine:T_ok", POOL, ROOT, BCS))) &&
      grepl("논문 메타", err_of(rc_p4_base_cell_spec("engine:T_ok", POOL_nometa, ROOT, file.path(SB, "bcs", "n3.json")))))
CD3 <- file.path(SB, "chain", "P4C96_measure")
j4 <- tryCatch(rc_p4_chain_new(CD3, "P4C96_measure", "engine:T_ok", POOL, adoption_rules = RULES, budget = BUD), error = function(e) e)
S3 <- if (inherits(j4, "error")) list() else rc_json_read(rc_p4_spec_path(CD3))
chk("J4 사슬 판 — base_cell_spec 생략 = 사슬 디렉터리에 기저 칸 생성(md5 = 사양) · 검사 통과", !inherits(j4, "error") &&
      file.exists(file.path(CD3, "base_cell_spec.json")) && identical(S3$base$cell_spec_md5, rc_md5(file.path(CD3, "base_cell_spec.json"))),
    if (inherits(j4, "error")) conditionMessage(j4) else "")
r3x <- function(p1 = "R-P1-P4C96", t1 = "R-T1-P4C96") err_of(reg4(CD3, "P4C96_measure", p1 = p1, t1 = t1))
chk("J5 등록 영수증 위반 주입 — P1 없음 · 남의 사슬 P1 · T1 자리에 철학 리뷰 · 응답 없는 도전 · 리뷰 파일 없음 · 대상 없는 T1 = 거부 · 원장 무기록",
    grepl("영수증", r3x(p1 = NULL)) && grepl("수령 목록", r3x(p1 = "R-P1-P4C97")) && grepl("요구", r3x(t1 = "R-P1-P4C96")) &&
      grepl("응답 없는 도전", r3x(t1 = "R-T1OPEN-P4C96")) && grepl("파일", r3x(t1 = "R-T1-NOFILE")) && grepl("대상", r3x(t1 = "R-T1-NOROUND")) &&
      rc_p4_steps_verify(CD3)$n == 0L)
chk("J5b 등록(양성 대조 — 영수증 일치)", identical(r3x(), ""))
A_BSTD <- mk_art("base_std", alpha = 0.005, seed = 7L); stub$base_std <- mkm(0.10, 0.60, -0.02)
n_b <- rc_p4_steps_verify(CD3)$n
jv0 <- rc_p4_base_measure(CD3, ROOT, runner = runner_to(A_BSTD), barrier = held, fingerprint = FP, vintage = VINT, freshness = FRESH, metrics_fun = mfun)
jv1 <- rc_p4_base_measure(CD3, ROOT, runner = runner_to(A_BSTD), barrier = free, fingerprint = FP, vintage = function(root) NULL, freshness = FRESH, metrics_fun = mfun)
chk("J5c 기준 칸 측정 거부 — 배리어 잠김 · 판 표식 판독 불가(fail-closed) = 재지 않고 사유 · 원장 무기록", identical(jv0$status, "barrier_held") &&
      identical(jv1$status, "vintage_unknown") && rc_p4_steps_verify(CD3)$n == n_b)
mb0 <- readBin(file.path(CD3, "base_cell_spec.json"), "raw", file.info(file.path(CD3, "base_cell_spec.json"))$size); cat(" ", file = file.path(CD3, "base_cell_spec.json"), append = TRUE)
chk("J5d 기저 칸 사양이 바뀌면 기준 칸 측정 거부(R2)", grepl("R2", err_of(bmeas(CD3, A_BSTD))))
writeBin(mb0, file.path(CD3, "base_cell_spec.json"))
chk("J5e 기준 칸 측정(풀 산출과 다른 산출 — base_std)", identical(bmeas(CD3, A_BSTD)$status, "measured"))
m1 <- rc_json_read(file.path(CD3, "base_cell_spec.json")); m1$overlay <- list(kind = "dd_brake", arm_id = "dd_brake_q"); CM1 <- wspec("m1", m1)
chk("J6 걸음 1 열기(기저 칸 + 오버레이 1블록)", identical(err_of(rc_p4_step_open(CD3, 1, H, M, "regime_exposure", CM1, 0, S3$generator$id, root = ROOT, pool = POOL)), ""))
chk("J7 측정 안 된 걸음 판정(산출 생략) = 거부", grepl("측정 안 된", err_of(rc_p4_step_decide(CD3, 1, root = ROOT, metrics_fun = mfun))))
RUN$n <- 0L; RUN$spec <- NULL
fake_ok <- function(spec_path, code, out_json, log_dir, root, role) {
  RUN$n <- RUN$n + 1L; RUN$spec <- rc_json_read(spec_path); RUN$code <- code; RUN$role <- role
  d <- mk_art("m1", alpha = 0.006, seed = 5L); rc_json_write(list(n = 1L, code = code, ok = TRUE, grade = "C", artifacts = d), out_json); 0L }
fake_fail <- function(spec_path, code, out_json, log_dir, root, role) { RUN$n <- RUN$n + 1L; rc_json_write(list(ok = FALSE, deferred = "refresh_lock"), out_json); 0L }
n_led <- function() rc_p4_steps_verify(CD3)$n
n0 <- n_led(); jb8 <- rc_p4_step_measure(CD3, 1, ROOT, runner = fake_ok, barrier = held, fingerprint = FP, vintage = VINT, freshness = FRESH)
chk("J8 배리어 잠김 = 측정하지 않고 사유 반환 · 러너 미호출 · 원장 무기록", identical(jb8$status, "barrier_held") && grepl("held", jb8$reason) && RUN$n == 0L && n_led() == n0)
LKD <- gsub("\\\\", "/", file.path(SB, "rb_lock")); invisible(dir.create(LKD)); invisible(file.create(file.path(LKD, "pid")))
Sys.setenv(QM_REFRESH_LOCKDIR = LKD, QM_RAWDATA_WRITER_LOCKDIR = gsub("\\\\", "/", file.path(SB, "rb_writer_none")))
rbh <- rc_p4_barrier_default(ROOT); jb9 <- rc_p4_step_measure(CD3, 1, ROOT, runner = fake_ok, fingerprint = FP, vintage = VINT, freshness = FRESH)
Sys.setenv(QM_REFRESH_LOCKDIR = gsub("\\\\", "/", file.path(SB, "rb_lock_none"))); rbf <- rc_p4_barrier_default(ROOT)
Sys.unsetenv(c("QM_REFRESH_LOCKDIR", "QM_RAWDATA_WRITER_LOCKDIR"))
chk("J9 정본 배리어(refresh_barrier.R → .sh) — 갓 만든 잠금(빈 pid) = held → 측정 거부 · 잠금 없음 = free(양성 대조)",
    identical(rbh$state, "held") && isTRUE(rbh$blocking) && identical(jb9$status, "barrier_held") && RUN$n == 0L && identical(rbf$state, "free") && isFALSE(rbf$blocking),
    sprintf("held=%s/%s free=%s", rbh$state, rbh$reason, rbf$state))
mb <- readBin(CM1, "raw", file.info(CM1)$size); cat(" ", file = CM1, append = TRUE)
chk("J10 열린 뒤 칸 사양이 바뀐 걸음 = 측정 거부(R2) · 러너 미호출", grepl("R2", err_of(rc_p4_step_measure(CD3, 1, ROOT, runner = fake_ok, barrier = free, fingerprint = FP, vintage = VINT, freshness = FRESH))) && RUN$n == 0L)
writeBin(mb, CM1)
jf <- rc_p4_step_measure(CD3, 1, ROOT, runner = fake_fail, barrier = free, fingerprint = FP, vintage = VINT, freshness = FRESH)
fpn <- local({ i <- 0L; function() { i <<- i + 1L; paste0("fp", i) } })
jf2 <- rc_p4_step_measure(CD3, 1, ROOT, runner = fake_ok, barrier = free, fingerprint = fpn, vintage = VINT, freshness = FRESH)
recs3 <- rc_p4_steps_read(CD3)
chk("J11 워커 ok ≠ true · 측정 중 지문 변화 = step_measure_failed(측정 기록 없음 · 판정 거부 유지)", identical(jf$status, "failed") && identical(jf2$status, "failed") &&
      any(grepl("지문", jf2$why)) && sum(vapply(recs3, function(r) identical(r$event, "step_measure_failed"), TRUE)) == 2L &&
      !any(vapply(recs3, function(r) identical(r$event, "step_measured"), TRUE)) && grepl("측정 안 된", err_of(rc_p4_step_decide(CD3, 1, root = ROOT, metrics_fun = mfun))))
n_v <- n_led(); jvc <- rc_p4_step_measure(CD3, 1, ROOT, runner = fake_ok, barrier = free, fingerprint = FP, vintage = VINT2, freshness = FRESH)
chk("J11b 팩터 DB 판 표식 ≠ 기준 칸 = 걸음 측정 거부(사유 · 러너 미호출 · 원장 무기록)", identical(jvc$status, "vintage_changed") && grepl("새 사슬에서 기준 칸부터", jvc$reason) &&
      n_led() == n_v)
RUN$n <- 0L; md5_open <- rc_md5(CM1)
jm <- rc_p4_step_measure(CD3, 1, ROOT, runner = fake_ok, barrier = free, fingerprint = FP, vintage = VINT, freshness = FRESH)
sa <- RUN$spec$selection_accounting; MS <- Filter(function(r) identical(r$event, "step_measured"), rc_p4_steps_read(CD3))
chk("J12 측정(가짜 러너) — step_measured{k · artifacts · measured_at} · 러너 1회 · 열린 사양 불변",
    identical(jm$status, "measured") && RUN$n == 1L && length(MS) == 1L && identical(as.integer(MS[[1]]$k), 1L) && !is.null(MS[[1]]$measured_at) &&
      identical(MS[[1]]$artifacts, .rcp4_rel(file.path(SB, "art", "m1"))) && identical(rc_md5(CM1), md5_open) && identical(MS[[1]]$cell_spec_md5, md5_open))
chk("J13 시행 회계 = 스윕 그대로(sweep · family_root = 사슬 id · 기저 1 + 연 걸음 1 = 2 · 근거 문구) · 'chain' 표시 없음 · 칸은 열린 사양과 같다(메타만 다름)",
    identical(sa$selection_type, "sweep") && identical(sa$family_root, "P4C96_measure") && identical(as.integer(sa$n_family_at_registration), 2L) &&
      grepl("기저 1", sa$n_trials_basis) && !grepl("chain", .rcp4_js(sa$selection_type)) && identical(RUN$code, "P4C96_measure_k1") && identical(RUN$role, "variant") &&
      identical(.rcp4_js(RUN$spec[setdiff(names(RUN$spec), "selection_accounting")]), .rcp4_js(m1[setdiff(names(m1), "selection_accounting")])))
RUN$n <- 0L; ja <- rc_p4_step_measure(CD3, 1, ROOT, runner = fake_ok, barrier = free, fingerprint = FP, vintage = VINT, freshness = FRESH)
chk("J14 이미 측정한 걸음 = already(다시 재지 않는다)", identical(ja$status, "already") && RUN$n == 0L)
chk("J15 측정 기록과 다른 산출을 넘긴 판정 = 거부", grepl("다른 산출", err_of(rc_p4_step_decide(CD3, 1, A_S2, ROOT, metrics_fun = mfun))))
stub$m1 <- mkm(0.05, 0.60, -0.01)          # 풀 산출(A_BASE) 기준이면 +0.05 채택 · 기준 칸(base_std = +0.10) 기준이면 −0.05 기각
jd <- tryCatch(rc_p4_step_decide(CD3, 1, root = ROOT, metrics_fun = mfun), error = function(e) e)
chk("J16 첫 걸음 비교 기준 = base_measured$metrics(풀 산출 지표 아님) — dS_vis = −0.05 · 기각 · 산출 = 측정 기록", !inherits(jd, "error") &&
      identical(jd$artifacts_source, "step_measured") && identical(jd$parent_basis, "base_measured") && isTRUE(all.equal(.rcp4_num(jd$table$dS_vis), -0.05)) &&
      identical(jd$decision, "reject") && identical(jd$artifacts, MS[[1]]$artifacts), if (inherits(jd, "error")) conditionMessage(jd) else "")
chk("J17 판정한 걸음 · 열지 않은 걸음 측정 = 거부", grepl("이미 판정", err_of(rc_p4_step_measure(CD3, 1, ROOT, runner = fake_ok, barrier = free, fingerprint = FP, vintage = VINT, freshness = FRESH))) &&
      grepl("열지 않은", err_of(rc_p4_step_measure(CD3, 5, ROOT, runner = fake_ok, barrier = free, fingerprint = FP, vintage = VINT, freshness = FRESH))))
## 기본 러너 배선(정본 호출 모양) — 가짜 루트의 rf_cell_worker.R 가 받은 인자 · 환경을 결과 json 에 적는다(실제 워커 · 측정 없음)
FR <- file.path(SB, "fakeroot"); dir.create(file.path(FR, "02_Infrastructure/ops"), recursive = TRUE)
writeLines(c("a <- commandArgs(trailingOnly = TRUE)",
             "jsonlite::write_json(list(args = a, nofa = Sys.getenv('QVEST_RP_NO_FACTOR_ANALYSIS'), reg = Sys.getenv('QVEST_RP_REGISTER', 'unset'), ok = TRUE), a[4], auto_unbox = TRUE)"),
           file.path(FR, "02_Infrastructure/ops/rf_cell_worker.R"))
WO <- file.path(SB, "fakeroot_out"); invisible(dir.create(WO))
old_fa <- Sys.getenv("RC_FACTOR_ANALYSIS", unset = NA); Sys.unsetenv("RC_FACTOR_ANALYSIS")
wrc <- rc_p4_runner_default(file.path(CD3, "measure", "k1.spec.json"), "P4C96_measure_k1", file.path(WO, "r.json"), WO, root = FR)
if (!is.na(old_fa)) Sys.setenv(RC_FACTOR_ANALYSIS = old_fa)
wj <- tryCatch(rc_json_read(file.path(WO, "r.json")), error = function(e) list())
chk("J18 기본 러너 = Rscript rf_cell_worker.R <사양> 1 <code> <결과 json>(measure_cell.R 와 같은 모양) · 요인 분석 끔 · 모듈 풀 등재 끔(QVEST_RP_REGISTER = 0) · 로그 파일 · 호출 뒤 환경 복원",
    identical(as.integer(wrc), 0L) && identical(unlist(wj$args)[2:3], c("1", "P4C96_measure_k1")) && grepl("k1.spec.json$", unlist(wj$args)[1]) &&
      identical(wj$nofa, "1") && identical(wj$reg, "0") && file.exists(file.path(WO, "P4C96_measure_k1.log")) && !nzchar(Sys.getenv("QVEST_RP_NO_FACTOR_ANALYSIS")),
    paste(unlist(wj), collapse = " | "))
## 닫기 · 후보 관문(가짜 재채점 · 가짜 관문 파일 — 다른 담당이 만드는 round_candidate_gate.R 대신)
FSR <- file.path(SB, "fake_sr.R"); FGT <- file.path(SB, "fake_gate.R"); GLOG <- file.path(SB, "gate_log.txt")
writeLines("sr_regrade <- function(candidate_dir, trial_dirs, root = NULL, write = FALSE, ...) list(status = 'ok', grade_before = 'B', grade_after = Sys.getenv('T_SR_GRADE', 'A'), gate_ok = TRUE, reason = 'fake', check = NULL, written = FALSE)", FSR)
writeLines(c("rcg_route <- function(candidate_dir, strategy_id, spec_path, root, write) {",
             sprintf("  writeLines(c(candidate_dir, strategy_id, spec_path, as.character(write)), '%s')", GLOG),
             "  list(action = 'hold', eligible = FALSE, codes = c('OOS_WINDOW', 'FAKE'), path = NA) }"), FGT)
r96 <- RCPT("P4C96_measure")
FRG <- file.path(SB, "fake_register.R"); RLOG <- file.path(SB, "register_log.txt")
writeLines(c("rmm_register_measured <- function(out_dir, sim_result = NULL, origin_mode = 'replication', meta = list(), ...) {",
             sprintf("  writeLines(c(out_dir, origin_mode, meta$chain_id, as.character(meta$chain_k)), '%s')", RLOG),
             "  list(registered = TRUE, code = 'ok', reason = '') }"), FRG)
cl3 <- tryCatch(rc_p4_close(CD3, "오버레이가 기준 칸을 넘지 못했다", probes = c("a", "b"), root = ROOT, outcomes_path = OUTC, philosophy_p2 = r96$p2, superfan_t2 = r96$t2,
                            ledger = LEDG, review_root = RVR, regrade_file = FSR, gate_file = FGT, register_file = FRG, regrade_write = TRUE), error = function(e) e)
fz3 <- if (file.exists(file.path(CD3, "finalize.json"))) rc_json_read(file.path(CD3, "finalize.json")) else list()
O3 <- Filter(function(o) identical(o$round_id, "P4C96_measure"), rc_outcomes_read(OUTC, program = "P4_ASSEMBLY")); gl <- if (file.exists(GLOG)) readLines(GLOG) else character(0)
chk("J19 새 등급 A = 후보 관문 호출(후보 산출 · strategy_id · 측정 사본 사양) · 요약은 finalize.json 에만 · 결과 원장 = 상태 문자열(evaluated)",
    !inherits(cl3, "error") && identical(fz3$candidate_gate$action, "hold") && identical(unlist(fz3$candidate_gate$codes), c("OOS_WINDOW", "FAKE")) &&
      length(gl) == 4L && identical(gl[2], "P4C96_measure_k0") && grepl("measure/k0.spec.json$", gl[3]) && identical(gl[4], "TRUE") &&
      identical(fz3$candidate, .rcp4_rel(A_BSTD)) && .rcp4_rel(A_BSTD) %in% unlist(fz3$trials) && !(.rcp4_rel(A_BASE) %in% unlist(fz3$trials)) &&
      length(O3) == 1L && identical(O3[[1]]$extra$finalize$candidate_gate, "evaluated") && !grepl("\"hold\"|OOS_WINDOW", .rcp4_js(O3[[1]])) &&
      !grepl("\"hold\"|OOS_WINDOW", .rcp4_js(Filter(function(r) identical(r$event, "chain_closed"), rc_p4_steps_read(CD3)))),
    if (inherits(cl3, "error")) conditionMessage(cl3) else .rcp4_js(fz3$candidate_gate))
rl <- if (file.exists(RLOG)) readLines(RLOG) else character(0)
chk("J19b 최종 후보 1개만 모듈 풀 등재(재채점 쓰기 ∧ 재채점 뒤 A) — 정본 등재기 사후 호출(산출 폴더 · origin replication · 사슬 메타) · 실제 상태는 finalize.json 에만",
    length(rl) == 4L && identical(rl[1], A_BSTD) && identical(rl[3], "P4C96_measure") && identical(rl[4], "0") &&
      identical(fz3$module_pool$status, "registered"), paste(rl, collapse = " | "))
chk("J19b2 결과 원장 · 사슬 원장에는 등재 여부가 새지 않는다(evaluated 로만 — 등재 = 전기간 등급 B 이상이라는 사실이 설계 입력으로 가지 않게)",
    identical(O3[[1]]$extra$finalize$module_pool, "evaluated") && !grepl("registered", .rcp4_js(O3[[1]]), fixed = TRUE) &&
      !grepl("registered\"", .rcp4_js(Filter(function(r) identical(r$event, "chain_closed"), rc_p4_steps_read(CD3))), fixed = TRUE),
    .rcp4_js(O3[[1]]$extra$finalize))
mp <- function(g, w) .rcp4_module_pool(list(grade_after = g), list(k = 1L, artifacts = A_S1), .rcp4_state(CD3, ROOT), w, FRG, ROOT)$status
unlink(RLOG)
chk("J19c 등재 조건 — 쓰기 없음 = not_attempted · 등급 C = not_registered(등재기 미호출) · 등재기 파일 없음 = pending_manual",
    identical(mp("A", FALSE), "not_attempted") && identical(mp("C", TRUE), "not_registered") && !file.exists(RLOG) &&
      identical(.rcp4_module_pool(list(grade_after = "B"), list(k = 1L, artifacts = A_S1), .rcp4_state(CD3, ROOT), TRUE, file.path(SB, "none.R"), ROOT)$status, "pending_manual"))
chk("J20 사슬 원장(측정 · 판정 · 닫기 기록)에 τ_D 뒤 날짜 없음(기록 시각 at · measured_at 은 메타)",
    !length(rc_after_tau_leaks(lapply(rc_p4_steps_read(CD3), function(r) r[setdiff(names(r), c("at", "prev", "measured_at"))]), TAU)))
CD4 <- file.path(SB, "chain", "P4C95_nota"); invisible(rc_p4_chain_new(CD4, "P4C95_nota", "engine:T_ok", POOL, BASE_CELL, RULES, BUD))
invisible(reg4(CD4, "P4C95_nota", mf = function(a, root, tau, ...) bmv)); invisible(bmeas(CD4, A_BASE))
invisible(rc_p4_step_open(CD4, 1, H, M, "regime_exposure", C1, 0, rc_json_read(rc_p4_spec_path(CD4))$generator$id, root = ROOT, pool = POOL))
invisible(md(CD4, 1, A_S1)); unlink(GLOG); r95 <- RCPT("P4C95_nota")
Sys.setenv(T_SR_GRADE = "B")
cl4 <- tryCatch(rc_p4_close(CD4, "n", probes = c("a", "b"), root = ROOT, outcomes_path = OUTC, philosophy_p2 = r95$p2, superfan_t2 = r95$t2,
                            ledger = LEDG, review_root = RVR, regrade_file = FSR, gate_file = FGT), error = function(e) e)
Sys.unsetenv("T_SR_GRADE")
O4 <- Filter(function(o) identical(o$round_id, "P4C95_nota"), rc_outcomes_read(OUTC, program = "P4_ASSEMBLY"))
chk("J21 새 등급 A 아님 = 관문 미호출 · 상태는 같은 'evaluated'(등급이 상태로 새지 않는다)", !inherits(cl4, "error") && !file.exists(GLOG) &&
      identical(rc_json_read(file.path(CD4, "finalize.json"))$candidate_gate$action, "not_called") && identical(O4[[1]]$extra$finalize$candidate_gate, "evaluated"),
    if (inherits(cl4, "error")) conditionMessage(cl4) else "")
CD5 <- file.path(SB, "chain", "P4C94_vint"); invisible(rc_p4_chain_new(CD5, "P4C94_vint", "engine:T_ok", POOL, BASE_CELL, RULES, BUD))
invisible(reg4(CD5, "P4C94_vint", mf = function(a, root, tau, ...) bmv)); invisible(bmeas(CD5, A_BASE))
invisible(rc_p4_step_open(CD5, 1, H, M, "regime_exposure", C1, 0, rc_json_read(rc_p4_spec_path(CD5))$generator$id, root = ROOT, pool = POOL))
invisible(.rcp4_append(CD5, list(event = "step_measured", k = 1L, cell_spec_md5 = rc_md5(C1), artifacts = .rcp4_rel(A_S1), vintage = list(id = "vint-OTHER", n_repairs = 3L))))
chk("J21b 걸음 측정의 판 표식 ≠ 기준 칸 = 판정 거부", grepl("판 표식", err_of(rc_p4_step_decide(CD5, 1, root = ROOT, metrics_fun = mfun))))
chk("J22 운영 판단 원장 무접촉", identical(rc_md5("06_Registry/q_judgment_ledger.json"), REAL_LEDGER_MD5))

cat("K 닫기 순서 · 점유 · 시행 집합 · 판 검사 · 판 표식 · 포기 · 글 검사 · 기각 기억 · 중복 칸 · 상태 문자열(11-10 적대적 검토 2차 R1)\n")
isna0 <- function(x) is.null(x) || (length(x) == 1L && is.na(x))
mkchain <- function(cid, base_key = "engine:T_ok", base_art = A_BASE) {
  cd <- file.path(SB, "chain", cid); invisible(rc_p4_chain_new(cd, cid, base_key, POOL, BASE_CELL, RULES, BUD))
  invisible(reg4(cd, cid, mf = function(a, root, tau, ...) bmv)); invisible(bmeas(cd, base_art)); cd }
gid <- function(cd) rc_json_read(rc_p4_spec_path(cd))$generator$id
open_k <- function(cd, k, cell, parent = 0L, block = "regime_exposure", hyp = H) rc_p4_step_open(cd, k, hyp, M, block, cell, parent, gid(cd), root = ROOT, pool = POOL)
evs <- function(cd) vapply(rc_p4_steps_read(cd), function(r) as.character(r$event), "")
SRLOG <- file.path(SB, "sr_log.txt"); FSR2 <- file.path(SB, "fake_sr2.R")
writeLines(c("sr_regrade <- function(candidate_dir, trial_dirs, root = NULL, write = FALSE, expected = NULL, ...) {",
             sprintf("  cat(paste0(as.character(jsonlite::toJSON(list(cand = candidate_dir, trials = as.list(trial_dirs), n = expected$n_trials, ids = as.list(unlist(expected$ids))), auto_unbox = TRUE)), '\\n'), file = '%s', append = TRUE)", SRLOG),
             "  list(status = 'ok', grade_before = 'B', grade_after = Sys.getenv('T_SR_GRADE', 'A'), gate_ok = TRUE, reason = 'fake', check = NULL, written = FALSE) }"), FSR2)
srlines <- function() if (file.exists(SRLOG)) { x <- readLines(SRLOG, warn = FALSE); x[nzchar(x)] } else character(0)
A_RJ <- mk_art("rj2", seed = 12L); stub$rj2 <- list(S_vis = NA_real_, uc_vis = 0.6, dd_capture_median_vis = 0.1)
## K1~K3 닫기 순서 · 재개 멱등
CD93 <- mkchain("P4C93_close"); invisible(open_k(CD93, 1, C1)); invisible(md(CD93, 1, A_S1)); r93 <- RCPT("P4C93_close")
OUT93 <- file.path(SB, "outcomes_93.jsonl"); writeLines(character(0), OUT93); RLOG2 <- file.path(SB, "register_log2.txt")
FRG_BAD <- file.path(SB, "fake_register_bad.R")
writeLines(c("rmm_register_measured <- function(out_dir, sim_result = NULL, origin_mode = 'replication', meta = list(), ...) {",
             sprintf("  cat(paste0(out_dir, '\\n'), file = '%s', append = TRUE)", RLOG2),
             sprintf("  cat('{broken\\n', file = '%s', append = TRUE)", OUT93),
             "  list(registered = TRUE, code = 'ok', reason = '') }"), FRG_BAD)
cl93 <- function(op, reg = FRG_BAD) err_of(rc_p4_close(CD93, "n", probes = c("a", "b"), root = ROOT, outcomes_path = op, philosophy_p2 = r93$p2, superfan_t2 = r93$t2,
                                                       ledger = LEDG, review_root = RVR, regrade_file = FSR2, gate_file = FGT, register_file = reg, regrade_write = TRUE,
                                                       other_chain_dirs = character(0)))
BADO <- file.path(SB, "outcomes_bad.jsonl"); writeLines("{not json", BADO); unlink(c(SRLOG, RLOG2))
e93a <- cl93(BADO)
chk("K1 결과 원장 판독 불가 = 부작용 전에 닫기 거부(재채점 · 등재 미호출 · finalize 없음 · 닫는 중 기록 없음)",
    nzchar(e93a) && !length(srlines()) && !file.exists(RLOG2) && !file.exists(file.path(CD93, "finalize.json")) && !("chain_closing" %in% evs(CD93)), e93a)
e93b <- cl93(OUT93)
chk("K2 부작용 뒤 실패(결과 원장 쓰기 실패) = 사슬은 '닫는 중' — 새 걸음 열기 거부 · 재채점 · 등재 1회 · finalize.json 남음",
    nzchar(e93b) && "chain_closing" %in% evs(CD93) && !("chain_closed" %in% evs(CD93)) && file.exists(file.path(CD93, "finalize.json")) &&
      grepl("닫는 중", err_of(open_k(CD93, 2, C3, parent = 1L, block = "tail_overlay"))) && length(srlines()) == 1L && length(readLines(RLOG2)) == 1L,
    paste(e93b, "|", paste(evs(CD93), collapse = ",")))
OUT93b <- file.path(SB, "outcomes_93b.jsonl"); unlink(GLOG)
e93c <- cl93(OUT93b)
chk("K3 다시 닫기 = 이어서 마무리 — 재채점 · 관문 · 등재 다시 안 함 · 결과 원장 1줄 · chain_closing · chain_closed 각 1줄",
    identical(e93c, "") && length(srlines()) == 1L && length(readLines(RLOG2)) == 1L && !file.exists(GLOG) &&
      length(rc_outcomes_read(OUT93b, program = "P4_ASSEMBLY")) == 1L && sum(evs(CD93) == "chain_closed") == 1L && sum(evs(CD93) == "chain_closing") == 1L, e93c)
## K4 닫기 점유
CD92 <- mkchain("P4C92_lock"); invisible(open_k(CD92, 1, C1)); invisible(md(CD92, 1, A_S1)); r92 <- RCPT("P4C92_lock")
LK92 <- file.path(CD92, "measure", "close.claim"); dir.create(LK92, recursive = TRUE); writeLines(c(as.character(Sys.getpid()), "t"), file.path(LK92, "pid"))
unlink(SRLOG)
e92 <- err_of(rc_p4_close(CD92, "n", probes = c("a", "b"), root = ROOT, outcomes_path = OUTC, philosophy_p2 = r92$p2, superfan_t2 = r92$t2, ledger = LEDG, review_root = RVR,
                          regrade_file = FSR2, gate_file = NO_GATE, other_chain_dirs = character(0)))
chk("K4 다른 닫기가 점유 중 = 닫기 거부 · 재채점 미호출 · 원장 무기록", grepl("다른 프로세스", e92) && !length(srlines()) &&
      !any(c("chain_closing", "chain_closed") %in% evs(CD92)), e92)
unlink(LK92, recursive = TRUE)
## K5 같은 기저 사슬의 시행 집합
A_BB <- mk_art("base_b", seed = 11L)
CD91 <- mkchain("P4C91_samea", base_art = A_BB); invisible(open_k(CD91, 1, C1)); invisible(md(CD91, 1, A_S3))
invisible(open_k(CD91, 2, C3, parent = 0L, block = "tail_overlay")); invisible(md(CD91, 2, A_RJ))
CD86 <- mkchain("P4C86_other", base_key = sk$key, base_art = mk_art("base_o", seed = 13L)); invisible(open_k(CD86, 1, C1)); invisible(md(CD86, 1, A_S3))
CD90 <- mkchain("P4C90_sameb"); invisible(open_k(CD90, 1, C1)); invisible(md(CD90, 1, A_S1)); r90 <- RCPT("P4C90_sameb"); unlink(SRLOG)
e90 <- err_of(rc_p4_close(CD90, "n", probes = c("a", "b"), root = ROOT, outcomes_path = OUTC, philosophy_p2 = r90$p2, superfan_t2 = r90$t2, ledger = LEDG, review_root = RVR,
                          regrade_file = FSR2, gate_file = NO_GATE, other_chain_dirs = c(CD91, CD86, CD90)))
SL <- if (length(srlines())) jsonlite::fromJSON(srlines()[1], simplifyVector = FALSE) else list(); trb <- basename(as.character(unlist(SL$trials)))
chk("K5 같은 기저의 앞 사슬 시행 = 선택 현실 점검 시행 집합 · 기대 시행 수에 들어간다(다른 기저 사슬은 빠진다 · 기대 = 2 + 3)",
    identical(e90, "") && identical(as.integer(SL$n), 5L) && all(c("base", "s1", "base_b", "s3", "rj2") %in% trb) && !("base_o" %in% trb) &&
      all(c("base_b", "rj2") %in% unlist(SL$ids)) && "P4C91_samea" %in% unlist(rc_json_read(file.path(CD90, "finalize.json"))$same_base_chains),
    paste(e90, "|", srlines()[1]))
## K6 사슬 판 — 필수 채택 규칙 방향 · 문턱
loose <- function(i, f) { s <- S0; s$adoption$rules[[i]] <- f(s$adoption$rules[[i]]); err_of(rc_p4_chain_check(s, ROOT)) }
chk("K6 필수 채택 규칙의 방향 · 문턱이 느슨하면 사슬 판 거부(dS ≥ −1 · 상승 포착 ≥ 0 · 위기 ≤ +1 · N1 동률 통과(≥ 과반값) · N2 방향 반대) · 정본 판은 통과",
    grepl("방향", loose(1, function(r) { r$value_ref <- NULL; r$value <- -1; r$basis <- "느슨"; r })) &&
      grepl("방향", loose(2, function(r) { r$value_ref <- NULL; r$value <- 0; r$basis <- "느슨"; r })) &&
      grepl("방향", loose(3, function(r) { r$value <- 1; r })) && grepl("방향", loose(4, function(r) { r$op <- ">="; r })) &&
      grepl("방향", loose(5, function(r) { r$op <- "<"; r })) && grepl("방향", loose(1, function(r) { r$op <- "<="; r })) &&
      identical(err_of(rc_p4_chain_check(S0, ROOT)), ""))
## K7 판 표식 — 진행 중 수리 · 데이터 지문
CD84 <- mkchain("P4C84_dup"); invisible(open_k(CD84, 1, C1))
VINT_IP <- function(root) list(id = "vint-1", n_repairs = 1L, n_in_progress = 1L)
RUN$n <- 0L; n84 <- rc_p4_steps_verify(CD84)$n
jip <- rc_p4_step_measure(CD84, 1, ROOT, runner = fake_ok, barrier = free, fingerprint = FP, vintage = VINT_IP, freshness = FRESH)
chk("K7 팩터 DB 수리 진행 중(완료 시각 없는 항목) = 측정 거부 · 러너 미호출 · 원장 무기록", identical(jip$status, "vintage_in_progress") && RUN$n == 0L &&
      rc_p4_steps_verify(CD84)$n == n84, jip$status)
FR2 <- file.path(SB, "fakeroot2"); dir.create(file.path(FR2, "02_Infrastructure/contracts"), recursive = TRUE)
writeLines("fdv_stamp <- function(root = NULL) list(schema = 'x', valid_from = NA, repairs = list(list(id = 'R1', completed_at = NULL)), in_progress = list('R1'))",
           file.path(FR2, "02_Infrastructure/contracts/factor_db_vintage.R"))
vd <- rc_p4_vintage_default(FR2)
chk("K7b 기본 판 표식 = 진행 중 수리 수(n_in_progress)를 싣는다", identical(as.integer(vd$n_in_progress), 1L))
invisible(rc_p4_step_measure(CD84, 1, ROOT, runner = runner_to(A_S1), barrier = free, fingerprint = FP, vintage = VINT, freshness = FRESH))
d84 <- tryCatch(rc_p4_step_decide(CD84, 1, root = ROOT, metrics_fun = mfun), error = function(e) e)
chk("K7c 기준 칸 · 걸음 측정의 데이터 지문(md5) 기록 · 판정 기록에 대조 결과", !inherits(d84, "error") && identical(d84$data_fp_vs_base, "same") &&
      .rcp4_txt(.rcp4_state(CD84, ROOT)$base_meas$data_fp_md5), if (inherits(d84, "error")) conditionMessage(d84) else "")
## K8 중복 칸(정규화 사양)
invisible(open_k(CD84, 2, C3, parent = 1L, block = "tail_overlay")); invisible(md(CD84, 2, A_RJ))
s3b <- s3[rev(names(s3))]; s3b$label <- "다른 이름"; s3b$idea <- "같은 처치"; C3B <- wspec("s3b", s3b)
chk("K8 기각된 칸과 의미가 같은 칸(키 순서 · 라벨 · 메모만 다름) = 걸음 열기 거부(정규화 사양 서명)", grepl("이미 쓴", err_of(open_k(CD84, 3, C3B, parent = 1L, block = "tail_overlay"))))
## K9 · K10 등급 표기 글
n84 <- rc_p4_steps_verify(CD84)$n
eg1 <- err_of(open_k(CD84, 3, C4, parent = 1L, block = "rebalance", hyp = "기저가 등급 C 에 머문 원인인 노출 경로를 끊는다"))
invisible(open_k(CD84, 3, C4, parent = 1L, block = "rebalance"))
for (i in 1:2) invisible(rc_p4_step_measure(CD84, 3, ROOT, runner = fake_fail, barrier = free, fingerprint = FP, vintage = VINT, freshness = FRESH))
n84b <- rc_p4_steps_verify(CD84)$n; eg2 <- err_of(rc_p4_step_abandon(CD84, 3, "등급 B 라서 더 재지 않는다", ROOT))
chk("K9 가설 · 포기 사유의 등급 표기 = 거부 · 원장 무기록(열기 · 포기 각각)", grepl("등급", eg1) && grepl("등급", eg2) && rc_p4_steps_verify(CD84)$n == n84b &&
      !any(vapply(rc_p4_steps_read(CD84), function(r) grepl("등급 C", paste(unlist(r), collapse = " "), fixed = TRUE), TRUE)), paste(eg1, "|", eg2))
invisible(rc_p4_step_abandon(CD84, 3, "워커가 두 번 실패했다", ROOT))
invisible(.rcp4_append(CD84, list(event = "step_open", k = 4L, hypothesis = "기저가 등급 C 에 머문 원인", mechanism = M, block_type = "universe",
                                  cell_spec_path = .rcp4_rel(C5), cell_spec_md5 = rc_md5(C5), parent = 1L, generator_version = gid(CD84), changed_axes = list("universe"))))
di84 <- tryCatch(rc_p4_design_input(ROOT, CD84, pool = POOL, outcomes_path = OUTC, other_chain_dirs = character(0)), error = function(e) conditionMessage(e))
chk("K10 원장에 이미 들어간 오염 글(등급 표기) = 설계 입력이 그 글만 생략하고 만든다(영구 정지 없음 · 누출 없음) · 포기 걸음은 '포기'로",
    grepl("P4 강화 사슬 설계 입력", di84, fixed = TRUE) && grepl("글 생략", di84, fixed = TRUE) && !grepl("등급 C", di84, fixed = TRUE) && grepl("포기", di84, fixed = TRUE),
    substr(di84, 1, 300))
## K11 포기뿐인 사슬의 닫기 r7
CD89 <- mkchain("P4C89_aband"); invisible(open_k(CD89, 1, C1))
for (i in 1:2) invisible(rc_p4_step_measure(CD89, 1, ROOT, runner = fake_fail, barrier = free, fingerprint = FP, vintage = VINT, freshness = FRESH))
invisible(rc_p4_step_abandon(CD89, 1, "워커가 두 번 실패했다", ROOT))
OUT89 <- file.path(SB, "outcomes_89.jsonl"); r89 <- RCPT("P4C89_aband")
c89 <- tryCatch(rc_p4_close(CD89, "n", probes = c("a", "b"), root = ROOT, outcomes_path = OUT89, philosophy_p2 = r89$p2, superfan_t2 = r89$t2, ledger = LEDG, review_root = RVR,
                            regrade_file = FSR2, gate_file = NO_GATE, other_chain_dirs = character(0)), error = function(e) e)
o89 <- rc_outcomes_read(OUT89, program = "P4_ASSEMBLY")
chk("K11 측정 실패로 포기한 걸음뿐인 사슬 = 닫기 r7 판독 없음(잡음 아님) · 블록 집계 기각 0 · 포기 1",
    !inherits(c89, "error") && length(o89) == 1L && isna0(o89[[1]]$r7) && identical(as.integer(o89[[1]]$extra$by_block$regime_exposure$reject), 0L) &&
      identical(as.integer(o89[[1]]$extra$by_block$regime_exposure$abandoned), 1L), if (inherits(c89, "error")) conditionMessage(c89) else .rcp4_js(o89[[1]]$r7))
## K12 · K13 사슬 사이 기각 기억
oc <- .rcp4_other_chain_rejects(.rcp4_state(CD90, ROOT), ROOT, dirs = c(CD89, CD86, CD91), n_max = 1L)
chk("K12 다른 사슬 기각 기억 — 포기 걸음 빠짐 · 같은 기저 우선 · 줄마다 기저 표기", !nrow(oc[chain == "P4C89_aband"]) && "base" %in% names(oc) &&
      identical(oc[block == "regime_exposure"]$chain, "P4C91_samea") && identical(oc[chain == "P4C91_samea"]$base[1], "engine:T_ok"), .rcp4_js(oc))
CD87 <- mkchain("P4C87_old"); invisible(open_k(CD87, 1, C1)); invisible(md(CD87, 1, A_S3)); Sys.sleep(1.2)
CD88 <- mkchain("P4C88_new"); invisible(open_k(CD88, 1, C1)); invisible(md(CD88, 1, A_S3))
oc2 <- .rcp4_other_chain_rejects(.rcp4_state(CD90, ROOT), ROOT, dirs = c(CD87, CD88), n_max = 1L)
chk("K13 블록마다 최근 기각 우선(사슬 id 알파벳 순 아님)", identical(oc2[block == "regime_exposure"]$chain, "P4C88_new"), .rcp4_js(oc2))
## K14 생성기 검토 · 성적표
RV89 <- tryCatch(rc_p4_generator_review(ROOT, chain_dirs = CD89, outcomes_path = OUT89), error = function(e) e)
sc89 <- if (inherits(RV89, "error")) list() else RV89$scorecard$by_generator[[1]]
chk("K14 생성기 검토 · 성적표 — 포기 걸음은 판정 · 기각 분모 밖(따로 셈)", !inherits(RV89, "error") && identical(RV89$table$decision, "abandoned") &&
      identical(as.integer(sc89$n_decided), 0L) && identical(as.integer(sc89$n_abandoned), 1L), if (inherits(RV89, "error")) conditionMessage(RV89) else "")
## K15 상태 문자열
FGT_ERR <- file.path(SB, "fake_gate_err.R"); writeLines("rcg_route <- function(...) stop('관문 파일 손상')", FGT_ERR)
CD85 <- mkchain("P4C85_grade"); invisible(open_k(CD85, 1, C1)); invisible(md(CD85, 1, A_S1)); r85 <- RCPT("P4C85_grade"); OUT85 <- file.path(SB, "outcomes_85.jsonl")
c85 <- tryCatch(rc_p4_close(CD85, "n", probes = c("a", "b"), root = ROOT, outcomes_path = OUT85, philosophy_p2 = r85$p2, superfan_t2 = r85$t2, ledger = LEDG, review_root = RVR,
                            regrade_file = FSR2, gate_file = FGT_ERR, register_file = file.path(SB, "none.R"), regrade_write = TRUE, other_chain_dirs = character(0)), error = function(e) e)
o85 <- rc_outcomes_read(OUT85, program = "P4_ASSEMBLY"); f85 <- if (file.exists(file.path(CD85, "finalize.json"))) rc_json_read(file.path(CD85, "finalize.json")) else list()
cc85 <- .rcp4_js(Filter(function(r) identical(r$event, "chain_closed"), rc_p4_steps_read(CD85)))
chk("K15 관문 오류 · 등재 대기(등급 A · B 가지에서만 생기는 상태) = 결과 원장 · 사슬 원장에는 evaluated 로만(실제 상태는 finalize.json)",
    !inherits(c85, "error") && length(o85) == 1L && identical(o85[[1]]$extra$finalize$candidate_gate, "evaluated") && identical(o85[[1]]$extra$finalize$module_pool, "evaluated") &&
      identical(f85$candidate_gate$status, "error") && identical(f85$module_pool$status, "pending_manual") &&
      !grepl("pending_manual|\"error\"", .rcp4_js(o85[[1]])) && !grepl("pending_manual|\"error\"", cc85),
    if (inherits(c85, "error")) conditionMessage(c85) else .rcp4_js(o85[[1]]$extra$finalize))

cat("KM 수리 되돌림 돌연변이(소스 텍스트 치환 · 치환 성사 단정 · 원본 대조 = 같은 탐침이 원본에서 참)\n")
P4SRC <- file.path(RC_DIR, "p4.R"); P4TXT <- paste(readLines(P4SRC, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
mut <- function(from, to, probe) {
  n <- lengths(regmatches(P4TXT, gregexpr(from, P4TXT, fixed = TRUE))); if (n != 1L) return(sprintf("치환 %d곳", n))
  f <- tempfile(fileext = ".R"); writeLines(enc2utf8(sub(from, to, P4TXT, fixed = TRUE)), f, useBytes = TRUE)
  sys.source(f, envir = globalenv(), keep.source = FALSE); on.exit({ sys.source(P4SRC, envir = globalenv(), keep.source = FALSE); unlink(f) }, add = TRUE)
  isTRUE(tryCatch(probe(), error = function(e) FALSE))
}
MC <- new.env(); MC$i <- 0L
mkc <- function(cid, base_key = "engine:T_ok", base_art = A_BASE, measure = TRUE) {
  MC$i <- MC$i + 1L; cd <- file.path(SB, "mchain", sprintf("%s_%02d", cid, MC$i))
  invisible(rc_p4_chain_new(cd, cid, base_key, POOL, BASE_CELL, RULES, BUD)); invisible(reg4(cd, cid, mf = function(a, root, tau, ...) bmv))
  if (measure) invisible(bmeas(cd, base_art)); cd }
fo <- function() tempfile(pattern = "outc_", tmpdir = SB, fileext = ".jsonl")
cls <- function(cd, cid, op, ...) err_of(rc_p4_close(cd, "n", probes = c("a", "b"), root = ROOT, outcomes_path = op, philosophy_p2 = RCPT(cid)$p2, superfan_t2 = RCPT(cid)$t2,
                                                    ledger = LEDG, review_root = RVR, regrade_file = FSR2, ...))
acc1 <- function(cid) { cd <- mkc(cid); invisible(open_k(cd, 1, C1)); invisible(md(cd, 1, A_S1)); cd }
## K16 닫기 ↔ 걸음 열기 경합(11-10 재수리 R1) — 닫기의 잠금 밖 미판정 검사를 지난 뒤 다른 프로세스가 걸음을 열면 chain_closing 은 거부되고 사슬은 진행 가능하다
race_close <- function(cid) {
  cd <- mkc(cid); invisible(open_k(cd, 1, C1)); invisible(md(cd, 1, A_S1))
  orig <- get(".rcp4_receipt_need", envir = globalenv()); fired <- FALSE
  assign(".rcp4_receipt_need", function(...) { if (!fired) { fired <<- TRUE; invisible(open_k(cd, 2, C3, parent = 1L, block = "tail_overlay")) }; orig(...) }, envir = globalenv())
  on.exit(assign(".rcp4_receipt_need", orig, envir = globalenv()), add = TRUE)
  e <- cls(cd, cid, fo(), gate_file = NO_GATE, other_chain_dirs = character(0))
  list(cd = cd, e = e, fired = fired)
}
RC86 <- race_close("P4C86_other")
d86 <- err_of(md(RC86$cd, 2, A_RJ)); e86b <- cls(RC86$cd, "P4C86_other", fo(), gate_file = NO_GATE, other_chain_dirs = character(0))
chk("K16 닫기 검사 뒤 끼어든 걸음 = chain_closing 거부(잠금 안 미판정 재확인) · 그 걸음 판정 가능 · 다시 닫기 = 성공 · 닫힌 사슬에 미판정 걸음 없음",
    RC86$fired && grepl("판정 안 된 걸음", RC86$e) && identical(d86, "") && identical(e86b, "") &&
      sum(evs(RC86$cd) == "chain_closing") == 1L && sum(evs(RC86$cd) == "chain_closed") == 1L &&
      !length(setdiff(.rcp4_state(RC86$cd, ROOT)$open_ks, .rcp4_state(RC86$cd, ROOT)$decided_ks)), paste(RC86$e, "|", d86, "|", e86b))
## K17 중복 칸 서명 = 열 때 기록한 서명(11-10 재수리 R1) — 기각 칸 파일을 덮어쓴 뒤 라벨만 바꾼 같은 처치 = 거부 · 기록 서명 없는 옛 줄 + 파일 변경 = 대조 불가 거부
dup_over <- function(cid) {
  cd <- mkc(cid); X <- wspec(paste0("x_", cid), s3); invisible(open_k(cd, 1, X, block = "tail_overlay")); invisible(md(cd, 1, A_RJ))
  s4o <- base_spec; s4o$overlay <- list(kind = "dd_brake", arm_id = "dd_brake_other"); rc_json_write(s4o, X)
  s3c <- s3; s3c$label <- paste("라벨만 다름", cid); Y <- wspec(paste0("y_", cid), s3c)
  list(cd = cd, e = err_of(open_k(cd, 2, Y, block = "tail_overlay")))
}
DO87 <- dup_over("P4C87_old")
spk <- Filter(function(r) identical(r$event, "step_open"), rc_p4_steps_read(DO87$cd))[[1]]$spec_key
old_rec <- function(cid) {
  cd <- mkc(cid); X <- wspec(paste0("o_", basename(cd)), s3)
  invisible(.rcp4_append(cd, list(event = "step_open", k = 1L, hypothesis = H, mechanism = M, block_type = "tail_overlay", cell_spec_path = .rcp4_rel(X),
                                  cell_spec_md5 = rc_md5(X), parent = 0L, generator_version = gid(cd), changed_axes = list("overlay"))))
  invisible(md(cd, 1, A_RJ)); rc_json_write(s1, X)
  err_of(open_k(cd, 2, C3B, block = "tail_overlay"))
}
e83 <- old_rec("P4C88_new")
chk("K17 기각 칸 파일 덮어쓰기 뒤 같은 처치(라벨만 다름) = 거부(기록 spec_key) · 열기 기록에 spec_key · 옛 줄(서명 없음) + 파일 변경 = 대조 불가 거부",
    grepl("이미 쓴", DO87$e) && .rcp4_txt(spk) && grepl("대조할 수 없다", e83), paste(DO87$e, "|", e83))

PRB <- list(
  resume = function() { cd <- acc1("P4C93_close"); unlink(c(SRLOG, RLOG2)); writeLines(character(0), OUT93)
    invisible(cls(cd, "P4C93_close", OUT93, gate_file = FGT, register_file = FRG_BAD, regrade_write = TRUE, other_chain_dirs = character(0)))
    e <- cls(cd, "P4C93_close", fo(), gate_file = FGT, register_file = FRG_BAD, regrade_write = TRUE, other_chain_dirs = character(0))
    identical(e, "") && length(srlines()) == 1L },
  preread = function() { cd <- acc1("P4C93_close"); unlink(SRLOG)
    e <- cls(cd, "P4C93_close", BADO, gate_file = NO_GATE, other_chain_dirs = character(0)); nzchar(e) && !length(srlines()) && !("chain_closing" %in% evs(cd)) },
  claim = function() { cd <- acc1("P4C92_lock"); unlink(SRLOG); lk <- file.path(cd, "measure", "close.claim"); dir.create(lk, recursive = TRUE)
    writeLines(c(as.character(Sys.getpid()), "t"), file.path(lk, "pid")); e <- cls(cd, "P4C92_lock", fo(), gate_file = NO_GATE, other_chain_dirs = character(0))
    unlink(lk, recursive = TRUE); grepl("다른 프로세스", e) && !length(srlines()) },
  samebase = function() { cd <- acc1("P4C90_sameb"); unlink(SRLOG); e <- cls(cd, "P4C90_sameb", fo(), gate_file = NO_GATE, other_chain_dirs = c(CD91, CD86))
    identical(e, "") && identical(as.integer(jsonlite::fromJSON(srlines()[1], simplifyVector = FALSE)$n), 5L) },
  bounds = function() grepl("방향", loose(4, function(r) { r$op <- ">="; r })),
  vint = function() { cd <- mkc("P4C84_dup", measure = FALSE)
    identical(rc_p4_base_measure(cd, ROOT, runner = runner_to(A_BASE), barrier = free, fingerprint = FP, vintage = VINT_IP, freshness = FRESH, metrics_fun = mfun)$status, "vintage_in_progress") },
  r7 = function() { cd <- mkc("P4C89_aband"); invisible(open_k(cd, 1, C1))
    for (i in 1:2) invisible(rc_p4_step_measure(cd, 1, ROOT, runner = fake_fail, barrier = free, fingerprint = FP, vintage = VINT, freshness = FRESH))
    invisible(rc_p4_step_abandon(cd, 1, "워커가 두 번 실패했다", ROOT)); o <- fo(); invisible(cls(cd, "P4C89_aband", o, gate_file = NO_GATE, other_chain_dirs = character(0)))
    isna0(rc_outcomes_read(o, program = "P4_ASSEMBLY")[[1]]$r7) },
  opentext = function() { cd <- mkc("P4C85_grade"); grepl("등급", err_of(open_k(cd, 1, C1, hyp = "기저가 등급 C 에 머문 원인"))) },
  abandontext = function() { cd <- mkc("P4C85_grade"); invisible(open_k(cd, 1, C1))
    for (i in 1:2) invisible(rc_p4_step_measure(cd, 1, ROOT, runner = fake_fail, barrier = free, fingerprint = FP, vintage = VINT, freshness = FRESH))
    grepl("등급", err_of(rc_p4_step_abandon(cd, 1, "등급 B 라서", ROOT))) },
  design = function() is.character(tryCatch(rc_p4_design_input(ROOT, CD84, pool = POOL, outcomes_path = OUTC, other_chain_dirs = character(0)), error = function(e) NULL)),
  rejects = function() !nrow(.rcp4_other_chain_rejects(.rcp4_state(CD90, ROOT), ROOT, dirs = CD89, n_max = 1L)),
  order = function() identical(.rcp4_other_chain_rejects(.rcp4_state(CD90, ROOT), ROOT, dirs = c(CD87, CD88), n_max = 1L)[block == "regime_exposure"]$chain, "P4C88_new"),
  dup = function() grepl("이미 쓴", err_of(open_k(CD84, 5, C3B, parent = 1L, block = "tail_overlay"))),
  race = function() grepl("판정 안 된 걸음", race_close("P4C86_other")$e),
  dupkey = function() grepl("이미 쓴", dup_over("P4C87_old")$e),
  dupna = function() grepl("대조할 수 없다", old_rec("P4C88_new")),
  status = function() { cd <- acc1("P4C85_grade"); o <- fo()
    invisible(cls(cd, "P4C85_grade", o, gate_file = FGT_ERR, register_file = file.path(SB, "none.R"), regrade_write = TRUE, other_chain_dirs = character(0)))
    identical(rc_outcomes_read(o, program = "P4_ASSEMBLY")[[1]]$extra$finalize$candidate_gate, "evaluated") })
MU <- list(
  resume = c("reuse <- is.list(prev) && identical(prev$closing_id, closing_id)", "reuse <- FALSE && identical(prev$closing_id, closing_id)"),
  preread = c("invisible(rc_outcomes_read(ap, kind = \"round\"))   #", "invisible(NULL)   #"),
  claim = c("cl <- .rcp4_claim(chain_dir, \"close\")", "cl <- list(ok = TRUE, path = tempfile())"),
  samebase = c("sb <- .rcp4_same_base_trials(st, root, other_chain_dirs)", "sb <- .rcp4_same_base_trials(st, root, character(0))"),
  bounds = c("  .rcp4_required_bounds(rr, rv, root)\n", "\n"),
  vint = c("if (isTRUE(.rcp4_num(v0$n_in_progress) > 0)) {", "if (FALSE) {"),
  r7 = c("else if (nj) \"noise\"", "else if (ns) \"noise\""),
  opentext = c("ci <- rc_input_issues(list(hypothesis, mechanism), st$tau)", "ci <- list(ok = TRUE)"),
  abandontext = c("ci <- rc_input_issues(list(reason), st$tau)", "ci <- list(ok = TRUE)"),
  design = c("if (isTRUE(rc_input_issues(list(x), tau)$ok)) x else", "if (TRUE) x else"),
  rejects = c("identical(r$decision, \"reject\") && !.rcp4_abandoned(r)) {", "identical(r$decision, \"reject\")) {"),
  order = c("D[order(block, -same_base, -xtfrm(at_), -k)]", "D[order(block, chain, -k)]"),
  dup = c("else if (nk %in% usedk)", "else if (FALSE)"),
  race = c("if (length(und)) sprintf(\"판정 안 된 걸음이 있다(다른 프로세스가 걸음을 열었다)", "if (FALSE) sprintf(\"판정 안 된 걸음이 있다(다른 프로세스가 걸음을 열었다)"),
  dupkey = c("if (.rcp4_txt(rec_key)) return(as.character(rec_key))", "if (FALSE) return(as.character(rec_key))"),
  dupna = c("else if (anyNA(usedk))", "else if (FALSE)"),
  status = c("candidate_gate = if (cg$status %in% c(\"evaluated\", \"error\")) \"evaluated\" else cg$status,", "candidate_gate = cg$status,"))
for (nm in names(MU)) {
  base_ok <- isTRUE(tryCatch(PRB[[nm]](), error = function(e) FALSE)); m <- mut(MU[[nm]][1], MU[[nm]][2], PRB[[nm]])
  chk(sprintf("KM-%s 원본 = 탐침 참 · 수리 되돌림 돌연변이 = 탐침 거짓(치환 1곳 성사)", nm), base_ok && identical(m, FALSE), sprintf("원본 %s · 돌연변이 %s", base_ok, m))
}

Sys.unsetenv("RC_RXG_PATH")
cat(sprintf("\n== round_core_v1_p4_chain: PASS %d · FAIL %d ==\n", PASS, FAIL))
cat(sprintf('{"test":"round_core_v1_p4_chain","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
if (FAIL > 0L) quit(status = 1L)
