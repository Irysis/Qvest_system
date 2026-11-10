## test_round_core_v1_p4_chain.R — P4 강화 사슬(round_core v1/p4.R · v10.2 · 2026-11-10) 격리 검사(양성 대조 + 위반 주입)
##   실제 등록부 · 결과 원장 · 생성기 등록부 · stage_artifacts 에 쓰지 않는다 — 임시 등록부 · 임시 원장 · 임시 생성기 등록부(RC_RXG_PATH) ·
##   임시 팩터 DB 수리 원장 · 합성 산출물(월간 수익 CSV)만 쓴다. 코드 · 정본 설정(등급 · 행동 카드 · 문턱)은 저장소 것을 읽기만 한다.
##   A 경로 · 기저 풀(사유 코드 전수 · 팩터 DB 판 양방향 · 상설 경로)  B 격차(보는 창만 — 시험 창 무감 양성 대조 · 계약 동치)
##   C 사슬 판 검사(위반 주입: 시험 창 · 전 기간 지표 · 출처 없음 · 필수 지표 없음 · 예산 출처 · 생성기 md5 · 풀 밖 기저)
##   D 등록 · 걸음 열기(판정 안 된 걸음 위 · 두 블록 · 고정 축 · 같은 칸 · 부모 · 날짜 누출 · 낡은 생성기 · 풀 밖 기저 · 사양 변경 R2)
##   E 걸음 판정(채택 · 기각 · 미측정 · 잡음 예산) · 원장 사슬 변조  F 설계 입력(보는 창 · 누출 fail-closed)  G 닫기(결과 원장 · 마감 훅)
##   H 생성기 판(rxg_pin · rxg_revise 거부 · 추가 전용) · 생성기 검토  I 헌장 격차 절 · CLI
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
       basis = "정의 — 비악화 = 부모 이하(새 숫자 없음)", source = "정의"))
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
mfun <- function(artifacts, root, tau, ...) { k <- basename(artifacts); if (!is.null(stub[[k]])) stub[[k]] else rc_p4_visible_metrics(artifacts, root, tau, bm_hist = NULL) }
chk("D0 풀이 사양 스냅샷과 다르면 등록 거부", grepl("pool_md5", err_of(rc_p4_chain_register(CD, copy(POOL)[key == "engine:T_ok", reason := "x"], ROOT, metrics_fun = mfun))))
chk("D1 등록(원장 첫 줄 — 기저 보는 창 지표 실측 · 규칙 해석본)", identical(err_of(rc_p4_chain_register(CD, POOL, ROOT, metrics_fun = mfun)), ""))
ST <- .rcp4_state(CD, ROOT)
chk("D2 등록 기록 — 기저 S_vis 유한 · 해석 규칙 3 · 두 번 등록 거부", is.finite(.rcp4_num(ST$reg$base_metrics$S_vis)) && length(ST$reg$rules_resolved) == 3L &&
      grepl("이미 등록", err_of(rc_p4_chain_register(CD, POOL, ROOT, metrics_fun = mfun))))
s1 <- base_spec; s1$overlay <- list(kind = "dd_brake", arm_id = "dd_brake_q"); C1 <- wspec("s1", s1)
open1 <- function(...) err_of(rc_p4_step_open(CD, ..., root = ROOT, pool = POOL))
H <- "낙폭 브레이크 층이 깊은 위기의 하락 포착을 낮춘다"; M <- "보유 시작 전 낙폭 신호로 노출을 줄여 위기 구간 손실 경로를 자른다"
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
chk("D13 원장은 거부된 걸음을 쓰지 않았다(등록 1줄)", rc_p4_steps_verify(CD)$n == 1L)
chk("D14 정상 걸음 열기(양성 대조 — 오버레이 1블록 · 부모 기저)", identical(open1(1, H, M, "regime_exposure", C1, 0, "g1"), ""))
s3 <- s1; s3$overlay <- list(kind = "vol_scale", arm_id = "vol_scale_x"); C3 <- wspec("s3", s3)
chk("D15 판정 안 된 걸음 위에 여는 걸음 = 거부", grepl("판정되지 않았다", open1(2, H, M, "tail_overlay", C3, 1, "g1")))
chk("D16 판정 안 된 걸음이 있으면 닫기 거부", grepl("판정 안 된", err_of(rc_p4_close(CD, "n", probes = c("a", "b"), root = ROOT, outcomes_path = OUTC))))
sp_b <- readBin(rc_p4_spec_path(CD), "raw", file.info(rc_p4_spec_path(CD))$size); cat(" ", file = rc_p4_spec_path(CD), append = TRUE)
chk("D17 등록 뒤 사슬 판 변경 = 판정 거부(R2)", grepl("R2", err_of(rc_p4_step_decide(CD, 1, A_S1, ROOT, metrics_fun = mfun))))
writeBin(sp_b, rc_p4_spec_path(CD))

cat("E 걸음 판정 · 예산 · 원장\n")
bmv <- ST$reg$base_metrics; mkm <- function(dS, uc, ddd) list(S_vis = .rcp4_num(bmv$S_vis) + dS, uc_vis = uc, dd_capture_median_vis = .rcp4_num(bmv$dd_capture_median_vis) + ddd,
                                                              calmar_vis = 1, port_t_vis = 1, cagr_vis = 0.1, sharpe_vis = 1, mdd_vis = 0.2, window = c("2000-01-31", TAU))
stub$s1 <- mkm(0.05, 0.60, -0.01)
r1 <- tryCatch(rc_p4_step_decide(CD, 1, A_S1, ROOT, metrics_fun = mfun), error = function(e) e)
chk("E1 채택(개선 ≥ 여유 · 상승 포착 ≥ 하한 · 위기 비악화) · r7 signal", !inherits(r1, "error") && identical(r1$decision, "accept") && identical(r1$r7, "signal"),
    if (inherits(r1, "error")) conditionMessage(r1) else paste(unlist(r1$reasons)))
chk("E2 같은 걸음 다시 판정 = 거부", grepl("이미 판정", err_of(rc_p4_step_decide(CD, 1, A_S1, ROOT, metrics_fun = mfun))))
chk("E3 머리 = 걸음 1 · 부모 0 으로 여는 걸음 = 거부", identical(.rcp4_state(CD, ROOT)$head_k, 1L) && grepl("머리", open1(2, H, M, "tail_overlay", C3, 0, "g1")))
chk("E4 걸음 2 열기(부모 1 · 꼬리 오버레이)", identical(open1(2, H, M, "tail_overlay", C3, 1, "g1"), ""))
stub$s2 <- mkm(0.05 + 0.005, 0.60, -0.01)           # 부모(걸음 1) 대비 +0.005 = 여유 이내
r2 <- rc_p4_step_decide(CD, 2, A_S2, ROOT, metrics_fun = mfun)
chk("E5 부모 대비 개선이 여유 이내 = 기각 · 사유 improve · r7 noise", identical(r2$decision, "reject") && any(grepl("^improve", unlist(r2$reasons))) && identical(r2$r7, "noise"))
s4 <- s1; s4$rebalance <- list(kind = "interval", k = 2L, phase = 0L); C4 <- wspec("s4", s4)
chk("E6 머리는 그대로 걸음 1(기각은 머리를 옮기지 않는다)", identical(.rcp4_state(CD, ROOT)$head_k, 1L) && identical(open1(3, H, M, "rebalance", C4, 1, "g1"), ""))
stub$s3 <- list(S_vis = NA_real_, uc_vis = 0.6, dd_capture_median_vis = 0.1)
r3 <- rc_p4_step_decide(CD, 3, A_S3, ROOT, metrics_fun = mfun)
chk("E7 미측정 = 기각(통과로 접지 않는다) · r7 NA(연속을 끊지도 잇지도 않는다)", identical(r3$decision, "reject") && any(grepl("미측정", unlist(r3$reasons))) && is.na(r3$r7))
s5 <- s1; s5$universe <- list(kind = "k200_kq150"); C5 <- wspec("s5", s5)
invisible(open1(4, H, M, "universe", C5, 1, "g1")); stub$s4 <- mkm(0.05 - 0.001, 0.60, -0.01); r4 <- rc_p4_step_decide(CD, 4, A_S4, ROOT, metrics_fun = mfun)
s6 <- s1; s6$cap_core <- list(k = 5L, satellite = "floor"); C6 <- wspec("s6", s6)
chk("E8 연속 '잡음 이내' K(2) = 예산 소진 — 걸음 열기 거부", identical(r4$r7, "noise") && grepl("예산 소진", open1(5, H, M, "construction", C6, 1, "g1")))
stub$uc <- mkm(0.10, 0.40, -0.01)
chk("E9 상승 포착 하한 미달 · 위기 악화는 각각 기각 사유(판정 표 단위 검사)", {
  T1 <- data.table(dS_vis = 0.1, uc_vis = 0.40, d_dd_capture_median_vis = -0.01); A1 <- rc_rules_apply(ST$reg$rules_resolved, T1)
  T2 <- data.table(dS_vis = 0.1, uc_vis = 0.60, d_dd_capture_median_vis = 0.02); A2 <- rc_rules_apply(ST$reg$rules_resolved, T2)
  isFALSE(A1$uc_floor) && isTRUE(A1$improve) && isFALSE(A2$crisis_no_worse) })
L <- readLines(rc_p4_steps_path(CD), encoding = "UTF-8"); lb <- readBin(rc_p4_steps_path(CD), "raw", file.info(rc_p4_steps_path(CD))$size)
L2 <- L; L2[2] <- sub("낙폭", "낙X", L2[2], fixed = TRUE); writeLines(L2, rc_p4_steps_path(CD), useBytes = TRUE)
chk("E10 걸음 원장 중간 줄 변조 = 사슬 끊김 · 판독 거부", !rc_p4_steps_verify(CD)$ok && grepl("끊", rc_p4_status(CD, ROOT)[1]))
writeBin(lb, rc_p4_steps_path(CD))
chk("E11 복원 뒤 사슬 정상 · 상태 줄(걸음 4 · 채택 1 · 기각 3 · 머리 걸음 1)", rc_p4_steps_verify(CD)$ok && grepl("걸음 4\\(판정 4 · 채택 1 · 기각 3\\)", rc_p4_status(CD, ROOT)[1]) &&
      grepl("머리 = 걸음 1", rc_p4_status(CD, ROOT)[1]), rc_p4_status(CD, ROOT)[1])
chk("E12 원장 지표 · 판정 기록에 τ_D 뒤 날짜 없음(보는 창만 · 기록 시각 at 은 메타)", !length(rc_after_tau_leaks(lapply(rc_p4_steps_read(CD), function(r) r[setdiff(names(r), c("at", "prev"))]), TAU)))

cat("F 설계 입력\n")
DI <- tryCatch(rc_p4_design_input(ROOT, CD, pool = POOL, outcomes_path = OUTC), error = function(e) e)
chk("F1 설계 입력 생성 — 병목 · 걸음 이력 · 채택 규칙 · 도구 상자 안내", !inherits(DI, "error") && grepl("병목", DI) && grepl("걸음 2 \\[tail_overlay", DI) &&
      grepl("보는 창 S 개선", DI) && grepl("blend = base_signal", DI), if (inherits(DI, "error")) conditionMessage(DI) else "")
chk("F2 보는 창만 — τ_D 뒤 날짜 · 등급 표기 · 등급 열 없음", !inherits(DI, "error") && !length(rc_after_tau_leaks(DI, TAU)) &&
      !grepl("(등급|Grade|grade)\\s*[ABCF](?![A-Za-z])", DI, perl = TRUE) && !grepl("| grade |", DI, fixed = TRUE))
bad_out <- file.path(SB, "outcomes_leak.jsonl")
writeLines(as.character(jsonlite::toJSON(list(schema = RC_OUTCOME_SCHEMA, kind = "round", program = "P2_DEFENSE", round_id = "P2R99_x", verdict_label = "x", note = "n",
                                              probes = list("2024-08-05 급락을 다시 본다", "b"), lessons = list()), auto_unbox = TRUE)), bad_out)
chk("F3 결과 원장에 τ_D 뒤 날짜가 섞이면 설계 입력 생성 거부(fail-closed)", grepl("τ_D", err_of(rc_p4_design_input(ROOT, CD, pool = POOL, outcomes_path = bad_out))))

cat("G 닫기\n")
chk("G1 다음 탐침 2개 미만 = 닫기 거부", grepl("탐침", err_of(rc_p4_close(CD, "해석", probes = "하나", root = ROOT, outcomes_path = OUTC))))
CL <- tryCatch(rc_p4_close(CD, "오버레이 낙폭 브레이크가 보는 창 S 를 올렸다", probes = c("꼬리 오버레이를 다른 기저에서", "비중 블록"), lessons = "기각 3 은 잡음 이내",
                           root = ROOT, outcomes_path = OUTC), error = function(e) e)
O <- rc_outcomes_read(OUTC, program = "P4_ASSEMBLY")
chk("G2 결과 원장 — 사슬 1줄 · 최종 후보 = 마지막 채택(걸음 1) · extra(생성기 판 · 걸음 수 · 블록 유형별)", !inherits(CL, "error") && length(O) == 1L &&
      identical(O[[1]]$round_id, "P4C99_selftest") && identical(as.integer(O[[1]]$extra$final_candidate$k), 1L) && identical(O[[1]]$extra$generator_version, "g1") &&
      identical(as.integer(O[[1]]$extra$n_steps), 4L) && identical(as.integer(O[[1]]$extra$by_block$regime_exposure$accept), 1L) &&
      identical(as.integer(O[[1]]$extra$by_block$tail_overlay$reject), 1L) && identical(O[[1]]$r7, "signal"),
    if (inherits(CL, "error")) conditionMessage(CL) else "")
chk("G3 마감 훅 — selection_regrade.R 호출 · 결과는 finalize.json(사람 쪽)에만 · 원장엔 상태 · md5", !inherits(CL, "error") && identical(CL$finalize$status, "done") &&
      file.exists(file.path(CD, "finalize.json")) && identical(O[[1]]$extra$finalize$md5, rc_md5(file.path(CD, "finalize.json"))) &&
      is.null(O[[1]]$extra$finalize$grade_after) && !is.na(O[[1]]$extra$finalize$regrade_status))
chk("G4 두 번 닫기 = 거부 · 닫힌 사슬에 걸음 열기 = 거부", grepl("이미 닫힌", err_of(rc_p4_close(CD, "n", probes = c("a", "b"), root = ROOT, outcomes_path = OUTC))) &&
      grepl("닫힌 사슬", open1(5, H, M, "construction", C6, 1, "g1")))
CD2 <- file.path(SB, "chain", "P4C97_none"); invisible(rc_p4_chain_new(CD2, "P4C97_none", "engine:T_ok", POOL, BASE_CELL, RULES, BUD))
invisible(rc_p4_chain_register(CD2, POOL, ROOT, metrics_fun = function(a, root, tau, ...) bmv))
c2 <- rc_p4_close(CD2, "걸음 없음", no_probes_reason = "시험 — 걸음을 열지 않았다", root = ROOT, outcomes_path = OUTC)
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
rv <- tryCatch(rxg_revise(GD2, "블록별 기각 사유를 먼저 읽게 한다", c("P4C99_selftest"), ROOT, outcomes_path = OUTC), error = function(e) e)
chk("H5 개정(추가 전용) — g2 추가 · 현재 = g2 · g1 기록 불변", !inherits(rv, "error") && identical(rxg_current(ROOT)$id, "g2") && identical(rxg_get("g1", ROOT), g1_before),
    if (inherits(rv, "error")) conditionMessage(rv) else "")
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

Sys.unsetenv("RC_RXG_PATH")
cat(sprintf("\n== round_core_v1_p4_chain: PASS %d · FAIL %d ==\n", PASS, FAIL))
cat(sprintf('{"test":"round_core_v1_p4_chain","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
if (FAIL > 0L) quit(status = 1L)
