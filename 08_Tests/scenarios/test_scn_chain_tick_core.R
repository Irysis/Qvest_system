## test_scn_chain_tick_core.R — 무인 틱 계획기 · 컴파일러(02_Infrastructure/programs/chain_tick.R) ↔ 실제 코어 상태 전이 (2026-11-10)
##   격리: 임시 루트(SB · 저장소 밖) — 임시 등록부 · 생성기 등록부(RC_RXG_PATH) · 합성 산출 · 가짜 러너 · 판 표식 · 신선도 주입 · 틱 장부(CT_STATE_DIR)
##   코어 코드 · 정본 설정은 저장소 것을 읽기만 한다. 실제 측정 · LLM · 발송 0(prep_send 대체 · tg_send 함정) · 운영 원장 md5 전후 동일.
##   C1~C11 = 설계 §8.2 · K = 장부 · 물러남 · 설정 · 알림 1회 · M = 돌연변이(소스 텍스트 치환 · 치환 1곳 단정)
## 실행: R_ENVIRON_USER=<빈 파일> QM_ROOT=<저장소> Rscript 08_Tests/scenarios/test_scn_chain_tick_core.R   (대상 = CT_UNDER_TEST 또는 저장소 chain_tick.R)
ROOT <- gsub("\\\\", "/", Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))); setwd(ROOT)
if (!file.exists(file.path(ROOT, "04_Research/programs/_lib/round_core/v1/p4.R"))) stop("저장소 루트가 아니다: ", ROOT)
Sys.setenv(QM_ROOT = ROOT)
CTF <- gsub("\\\\", "/", Sys.getenv("CT_UNDER_TEST", file.path(ROOT, "02_Infrastructure/programs/chain_tick.R")))
PASS <- 0L; FAIL <- 0L
chk <- function(name, ok, detail = "") {
  if (isTRUE(ok)) { PASS <<- PASS + 1L; cat(sprintf("  [ok]   %s\n", name)) } else { FAIL <<- FAIL + 1L; cat(sprintf("  [FAIL] %s %s\n", name, paste(detail, collapse = " "))) }
}
err_of <- function(expr) tryCatch({ force(expr); "" }, error = function(e) conditionMessage(e))
suppressMessages(source("04_Research/programs/_lib/round_core/v1/load.R"))
invisible(capture.output(suppressMessages(source("02_Infrastructure/programs/rx_round.R"))))
suppressPackageStartupMessages({ library(data.table) })
TG_CALLS <- 0L; tg_send <- function(...) { TG_CALLS <<- TG_CALLS + 1L; invisible(NULL) }
NOTI <- new.env(); NOTI$n <- 0L
prep_send <- function(...) { NOTI$n <- NOTI$n + 1L; NOTI$last <- list(...); invisible(list(ok = TRUE)) }   # 알림 대체(발송 0)
CT_SRC <- readLines(CTF, encoding = "UTF-8", warn = FALSE)
sys.source(CTF, envir = globalenv())
restore_ct <- function() sys.source(CTF, envir = globalenv())
SB <- gsub("\\\\", "/", tempfile("scn_ct_")); dir.create(SB, recursive = TRUE)
invisible(reg.finalizer(globalenv(), function(e) unlink(SB, recursive = TRUE), onexit = TRUE))
if (startsWith(tolower(SB), tolower(paste0(ROOT, "/")))) stop("샌드박스가 저장소 안이다")
mut_ct <- function(from, to) { m <- sub(from, to, CT_SRC, fixed = TRUE); n <- sum(m != CT_SRC); f <- file.path(SB, sprintf("ct_mut_%d.R", sample.int(1e6, 1)))
  writeLines(m, f, useBytes = TRUE); sys.source(f, envir = globalenv()); n }
Sys.setenv(CT_STATE_DIR = file.path(SB, "state"), QVEST_TG_DRY_RUN = "1", QVEST_UNATTENDED = "0")
SD <- file.path(SB, "state")
REAL <- vapply(c("06_Registry/round_outcomes.jsonl", "06_Registry/q_judgment_ledger.json", "06_Registry/rx_generator.json", "06_Registry/research_programs.json"),
               function(f) if (file.exists(f)) rc_md5(f) else "absent", "")
TAU <- rc_ref_value("06_Registry/behavior_card.json::tau_d")

## ── 픽스처(test_scn_l1_chain_e2e.R 와 같은 꼴) ─────────────────────────────────
ME <- seq(as.Date("2000-02-01"), as.Date("2025-01-01"), by = "month") - 1L
mk_art <- function(nm, grade = "C") {
  set.seed(nchar(nm)); n <- length(ME); bm <- rnorm(n, 0.006, 0.05); s <- 0.004 + 0.8 * bm + rnorm(n, 0, 0.02)
  d <- file.path(SB, "art", nm); dir.create(d, recursive = TRUE, showWarnings = FALSE)
  fwrite(data.table(date = ME, ret_net = s, risk_free_ret = 0, leverage = 1, frequency = "monthly"), file.path(d, "03_period_returns.csv"))
  fwrite(data.table(date = ME, benchmark_ret = bm, benchmark_id = "KOSPI200"), file.path(d, "05_benchmark_returns.csv"))
  fwrite(data.table(date = ME, nav_net = cumprod(1 + s)), file.path(d, "02_nav.csv"))
  rc_json_write(list(run_id = "RP_20261111_090000_t", essence_grade = grade, grade_scheme = "test_fixture"), file.path(d, "authoritative_remeasure.json")); d
}
mk_eng <- function(nm) { p <- file.path(SB, "eng", nm, "engine.R"); dir.create(dirname(p), recursive = TRUE, showWarnings = FALSE); writeLines(c("## fixture", "FACTORS <- NULL"), p); p }
A_OK <- mk_art("lane_ok", "B"); E_OK <- mk_eng("ok")
REG <- file.path(SB, "research_programs.json")
rc_json_write(list(schema = "research_programs_v1", programs = list(list(id = "P1_RETURN", queue = list(list(key = "engine:E_ok", kind = "engine", engine_path = E_OK, artifacts = A_OK,
  implementation_suspect = FALSE, has_short = FALSE, audit_verdict = "adapted", paper_key = "9909.ok")), consumed = list())), paper_routing = list(unrouted = list())), REG)
FDVL <- file.path(SB, "factor_db_vintage.json")
rc_json_write(list(schema = "factor_db_vintage_v1", entries = list(list(id = "T-REPAIR", completed_at = "2026-11-10T11:26:00+09:00", scope = "all"))), FDVL)
SA <- file.path(SB, "sa"); dir.create(SA)
SQ <- rc_standing_qualified("P1_RETURN", root = ROOT, sa_root = SA); SQ <- SQ[startsWith(ledger, gsub("\\\\", "/", SA))]
POOL <- rc_p4_base_pool(ROOT, registry_path = REG, standing = SQ, fdv_ledger_path = FDVL)
GEN_REG <- file.path(SB, "rx_generator.json"); Sys.setenv(RC_RXG_PATH = GEN_REG)
GD1 <- file.path(SB, "gen", "g1"); dir.create(GD1, recursive = TRUE); file.copy("04_Research/programs/P4_ASSEMBLY/_generator/g1/step.md", GD1)
rc_json_write(list(schema = "rx_generator_v1", current = "g1", versions = list(list(id = "g1", dir = GD1, files = rxg_files_md5(GD1), created_at = rc_now(), reason = "시험", evidence = list()))), GEN_REG)
OUTC <- file.path(SB, "round_outcomes.jsonl"); invisible(file.create(OUTC))
CS <- file.path(SB, "cells"); dir.create(CS)
BS <- rx_compile_spec(list(code = "B0", label = "기저", base_signal = list(kind = "engine", path = E_OK), base_weight = 0.5, factors = list(), weighting = list(kind = "ew")),
                      list(), "B0", "기저", "", NULL, root = ROOT)
BS$fixed_axes <- c(list(long_only = TRUE, n_max = 25L, commission_bps = 15L, liq_adv20_min = 2e8), BS$fixed_axes)
BASE_CELL <- file.path(CS, "base.json"); rc_json_write(BS, BASE_CELL)
RULES <- list(
  list(id = "improve", type = "threshold", label = "보는 창 S 개선", metric = "dS_vis", op = ">=",
       value_ref = "04_Research/programs/P3_CONSTRUCTION/P3R03_advanced_construction/prereg.json::final_selection_rule.tie_eps", source = "tie_eps 승계(시험)"),
  list(id = "uc_floor", type = "threshold", label = "상승 포착 하한", metric = "uc_vis", op = ">=", value_ref = "06_Registry/behavior_card.json::uc_floor", source = "헌장(시험)"),
  list(id = "crisis_no_worse", type = "threshold", label = "위기 하락 포착 비악화", metric = "d_dd_capture_median_vis", op = "<=", value = 0, basis = "정의", source = "정의"),
  list(id = "bull_segments", type = "threshold", label = "강세 구간별 참여(N1)", metric = "uc_seg_ok_share_vis", op = ">", value_ref = "06_Registry/behavior_card.json::majority_share", source = "헌장"),
  list(id = "deep_crisis", type = "threshold", label = "깊은 위기 과반 비악화(N2)", metric = "deep_crisis_nonworse_share_vis", op = ">", value_ref = "06_Registry/behavior_card.json::majority_share", source = "헌장"))
EPS <- rc_ref_value(RULES[[1]]$value_ref)
FB <- function(up = 1) data.table(start_ym = c("2003-04", "2005-01", "2009-03", "2016-02"), end_ym = c("2004-03", "2007-10", "2010-12", "2017-10"), up_capture = up)
FC <- function(dd = 1) data.table(peak_date = c("2002-04-18", "2008-05-16", "2011-05-02", "2020-01-22"), trough_date = c("2002-09-30", "2008-10-24", "2011-09-26", "2020-03-19"),
                                  bm_dd = c(0.25, 0.50, 0.20, 0.35), dd_capture = dd, st_recovery_obs = 100, st_recovery_censored = FALSE)
mkm <- function(S) list(S_vis = S, uc_vis = 0.60, dd_capture_median_vis = 0.50, calmar_vis = 1, port_t_vis = 1, cagr_vis = 0.1, sharpe_vis = 1, mdd_vis = 0.2,
                        window = c("2000-01-31", TAU), cdar_vis = 0.3, beta_up_vis = 1, beta_down_vis = 0.8, worst_name_contrib_deep_vis = -0.02, bull_vis = FB(), crises_vis = FC())
STUB <- list(lane_ok = mkm(1), m_base = mkm(1), m_up = mkm(1 + 2 * EPS), m_dn = mkm(0.5))
mfun <- function(artifacts, root, tau, ...) STUB[[basename(artifacts)]] %||% stop("지표 대체 없음: ", basename(artifacts))
runner_to <- function(nm) function(spec_path, code, out_json, log_dir, root, role) { d <- mk_art(nm); rc_json_write(list(ok = TRUE, artifacts = d), out_json); 0L }
runner_crash <- function(spec_path, code, out_json, log_dir, root, role) stop("워커 크래시(주입)")
free <- function(root) list(state = "free", reason = "", lock = "", blocking = FALSE)
FRESH <- function(root) list(ok = TRUE, state = "fresh", reason = "시험 주입")
FP <- function() "fp"; VINT <- function(root) list(id = "v1", n_repairs = 1L); VINT2 <- function(root) list(id = "v2", n_repairs = 2L)
VIP <- function(root) list(id = "v1", n_repairs = 1L, n_in_progress = 1L)
VF <- function(v) function(root) .rcp4_vint(v, root)
bm_ <- function(cd) rc_p4_base_measure(cd, ROOT, runner = runner_to("m_base"), barrier = free, fingerprint = FP, vintage = VINT, metrics_fun = mfun, freshness = FRESH)
sm_ <- function(cd, k, run) rc_p4_step_measure(cd, k, ROOT, runner = run, barrier = free, fingerprint = FP, vintage = VINT, freshness = FRESH)
dec <- function(cd, k) rc_p4_step_decide(cd, k, root = ROOT, metrics_fun = mfun)
pl <- function(cd, v = VINT) ct_plan(cd, ROOT, SD, vintage_fun = VF(v))
nled <- function(cd) rc_p4_steps_verify(cd)$n
mk_chain <- function(cid, bud = list(max_steps = 6L, max_steps_source = "시험", noise_k = 2L, noise_k_source = "시험")) {
  cd <- file.path(SB, "P4_ASSEMBLY", cid); invisible(rc_p4_chain_new(cd, cid, "engine:E_ok", POOL, BASE_CELL, RULES, bud))
  invisible(.rcp4_append(cd, list(event = "chain_registered", chain_id = cid, spec_md5 = rc_md5(rc_p4_spec_path(cd)), rules_resolved = rc_rules_resolve(RULES, ROOT)))); cd
}
H <- "가중을 역변동성으로 바꾸면 위기 경로에서 고변동 종목 비중이 줄어 하락 포착이 낮아진다"
M <- "변동성이 높은 종목이 깊은 하락에서 손실을 키우므로 그 비중을 줄이면 위기 손실이 잘린다"
WN <- new.env(); WN$i <- 0L
gen_out <- function(cd, J, extra = "", rc = 0L) {   # 코어가 만든 작업 폴더 + 가짜 생성기 산출
  WN$i <- WN$i + 1L; wd <- file.path(SB, "lanes", sprintf("w%03d", WN$i))
  rc_p4_generator_workdir(cd, wd, ROOT, pool = POOL, outcomes_path = OUTC, toolbox_md = "도구 상자(시험)")
  js <- as.character(jsonlite::toJSON(J, auto_unbox = TRUE, pretty = TRUE))
  writeLines(enc2utf8(c("설계 메모", extra, "", "```json", js, "```")), file.path(wd, "out.md"), useBytes = TRUE)
  writeLines(sprintf('{"rc":%d,"reason":"ok","model":"fake"}', rc), file.path(wd, "gen_result.json")); wd
}
J0 <- function(delta = list(weighting = list(kind = "inv_vol", window = 60L)), block = "weighting", h = H)
  list(hypothesis = h, mechanism = M, block_type = block, delta = delta, expected_direction = "위기 하락 포착 비악화", falsification = "보는 창 S 개선이 여유 이내면 기각", philosophy_alignment = "위기 방어")
open_from <- function(cd, wd) { o <- function(f) readLines(file.path(wd, "open", f), encoding = "UTF-8", warn = FALSE)[1]
  rc_p4_step_open(cd, o("k.txt"), o("hypothesis.txt"), o("mechanism.txt"), o("block.txt"), o("cell.txt"), o("parent.txt"), o("generator.txt"), root = ROOT, pool = POOL) }

cat("C 계획기 · 컴파일러 ↔ 코어\n")
CD <- mk_chain("P4C70_tick")
p <- pl(CD); chk("C1 등록 직후 plan = measure_base(k 0)", identical(p$action, "measure_base") && identical(p$k, 0L), unlist(p))
pv <- pl(CD, VIP); pu <- ct_plan(CD, ROOT, SD, vintage_fun = function(root) NULL)
chk("C1c 기준 칸 전에도 판 표식(재수리) — 수리 진행 중 → wait vintage_in_progress · 판독 불가 → wait vintage_unknown(measure_base 아님 · 코어가 rc 1 로 거부할 측정)",
    identical(pv$action, "wait") && identical(pv$reason, "vintage_in_progress") && identical(pu$action, "wait") && identical(pu$reason, "vintage_unknown"), c(unlist(pv), unlist(pu)))
invisible(bm_(CD)); p <- pl(CD); chk("C1b 기준 칸 측정 뒤 plan = open(k 1)", identical(p$action, "open") && identical(p$k, 1L), unlist(p))
W1 <- gen_out(CD, J0()); n0 <- nled(CD); l0 <- rc_md5(rc_p4_steps_path(CD))
r1 <- ct_compile(CD, W1, 1L, ROOT)
cell1 <- if (isTRUE(r1$ok)) rc_json_read(r1$cell) else NULL
chk("C2 정상 산출 → compile ok · 칸 사양이 부모와 한 블록만 다름(spec_diff) · 원장 무변경",
    isTRUE(r1$ok) && isTRUE(rc_p4_spec_diff(rc_json_read(file.path(W1, "parent_cell_spec.json")), cell1, "weighting", ROOT)$ok) && identical(l0, rc_md5(rc_p4_steps_path(CD))), r1$msg)
chk("C2b open/*.txt 로 코어 p4-step-open 성공 → plan = measure_step(k 1)", identical(err_of(open_from(CD, W1)), "") && identical(pl(CD)$action, "measure_step"))
invisible(sm_(CD, 1, runner_to("m_up"))); p <- pl(CD)
chk("C3 측정 → plan = decide(k 1)", identical(p$action, "decide") && identical(p$k, 1L), unlist(p))
d1 <- dec(CD, 1); p <- pl(CD)
chk("C3b 판정(채택) → plan = open(k 2) · 부모 = 1", identical(d1$decision, "accept") && identical(p$action, "open") && identical(p$k, 2L) && grepl("부모 1", p$detail), unlist(p))
## 걸음 2 — 세션이 손으로 열면서 칸 파일 이름을 cells/k3.json 으로 썼다(R2 보호 시험용) · 측정 실패 2회 → 포기
s2 <- rc_json_read(file.path(gen_out(CD, J0()), "parent_cell_spec.json")); s2$rebalance <- list(freq = "monthly"); s2$code <- "k2man"
dir.create(file.path(CD, "cells"), showWarnings = FALSE); C3P <- file.path(CD, "cells", "k3.json"); rc_json_write(s2, C3P)
invisible(rc_p4_step_open(CD, 2, H, M, "rebalance", C3P, 1, "g1", root = ROOT, pool = POOL))
invisible(sm_(CD, 2, runner_crash)); p1 <- pl(CD); invisible(sm_(CD, 2, runner_crash)); p2 <- pl(CD)
chk("C4 측정 실패 1회 = measure_step 유지 · 2회(RC_STANDING_MAX_FAILS) = abandon", identical(p1$action, "measure_step") && identical(p2$action, "abandon") && identical(p2$k, 2L), paste(p1$action, p2$action))
ar <- ct_abandon_reason(CD, 2, ROOT)
chk("C4b 포기 사유 = 숫자 · 날짜 없음 · 코어 포기 성공 → plan = open(k 3)", !grepl("[0-9]", ar) && identical(err_of(rc_p4_step_abandon(CD, 2, ar, ROOT)), "") && identical(pl(CD)$action, "open"))
W3 <- gen_out(CD, J0(delta = list(rebalance = list(freq = "monthly")), block = "rebalance")); lr <- nled(CD)
r3 <- ct_compile(CD, W3, 3L, ROOT)
chk("C9 원장이 이미 참조하는 칸 파일(cells/k3.json)은 덮지 않는다(R2) · 파일 그대로", !isTRUE(r3$ok) && identical(r3$code, "r2") && identical(rc_json_read(C3P)$code, "k2man") && nled(CD) == lr, r3$code)
## C8 컴파일 거부 — 원장 줄 수 불변
rej <- function(J = J0(), extra = "", raw = NULL) { wd <- gen_out(CD, J, extra); if (!is.null(raw)) writeLines(raw, file.path(wd, "out.md")); n <- nled(CD); r <- ct_compile(CD, wd, length(.rcp4_state(CD, ROOT)$open_ks) + 1L, ROOT)
  list(code = if (isTRUE(r$ok)) "ok" else r$code, same = nled(CD) == n) }
## C8 은 k3 칸 파일 이름 충돌을 피하려고 다른 사슬(같은 상태)에서 본다
CD8 <- mk_chain("P4C71_rej"); invisible(bm_(CD8)); CD_save <- CD; CD <- CD8
cases <- list(parse = rej(raw = "설명만 있고 json 블록이 없다"), schema = rej(J = J0()[c("hypothesis", "block_type", "delta")]), block = rej(J = J0(block = "magic")),
              contaminated = rej(J = J0(h = "2023년 3월 급락 같은 위기에서 손실을 줄인다")), contaminated2 = rej(extra = "참고: 2024-08-05 급락"),
              invalid = rej(J = J0(delta = list(weighting = list(kind = "ivol")))), diff = rej(J = J0(delta = list(weighting = list(kind = "inv_vol", window = 60L), rebalance = list(freq = "monthly")))))
want <- c(parse = "parse", schema = "schema", block = "block", contaminated = "contaminated", contaminated2 = "contaminated", invalid = "invalid", diff = "diff")
got <- vapply(cases, function(x) x$code, ""); sm <- vapply(cases, function(x) x$same, TRUE)
for (nm in names(want)) chk(sprintf("C8 거부 %-13s → %s · 원장 불변", nm, want[[nm]]), identical(got[[nm]], want[[nm]]) && sm[[nm]], got[[nm]])
CD <- CD_save
## C5 예산
CD5 <- mk_chain("P4C72_bud", list(max_steps = 1L, max_steps_source = "시험", noise_k = 5L, noise_k_source = "시험")); invisible(bm_(CD5))
W5 <- gen_out(CD5, J0()); invisible(ct_compile(CD5, W5, 1L, ROOT)); invisible(open_from(CD5, W5)); invisible(sm_(CD5, 1, runner_to("m_up"))); invisible(dec(CD5, 1))
p5 <- pl(CD5); chk("C5 최대 걸음 소진 → close_wait budget_steps", identical(p5$action, "close_wait") && identical(p5$reason, "budget_steps"), unlist(p5))
CD6 <- mk_chain("P4C73_noise", list(max_steps = 6L, max_steps_source = "시험", noise_k = 1L, noise_k_source = "시험")); invisible(bm_(CD6))
W6 <- gen_out(CD6, J0()); invisible(ct_compile(CD6, W6, 1L, ROOT)); invisible(open_from(CD6, W6)); invisible(sm_(CD6, 1, runner_to("m_dn"))); d6 <- dec(CD6, 1)
p6 <- pl(CD6); chk("C5b 연속 잡음 K → close_wait budget_noise(코어도 열기 거부)", identical(p6$action, "close_wait") && identical(p6$reason, "budget_noise") &&
                     grepl("예산 소진", err_of(rc_p4_step_open(CD6, 2, H, M, "weighting", file.path(W6, "parent_cell_spec.json"), 0, "g1", root = ROOT, pool = POOL))), paste(unlist(p6), d6$r7))
## C6 판 표식
p7 <- pl(CD, VINT2); p8 <- pl(CD, VIP); p9 <- ct_plan(CD, ROOT, SD, vintage_fun = function(root) NULL)
chk("C6 판 표식 바뀜 → close_wait vintage_changed · 진행 중 수리 → wait · 판독 불가 → wait vintage_unknown",
    identical(p7$reason, "vintage_changed") && identical(p7$action, "close_wait") && identical(p8$reason, "vintage_in_progress") && identical(p9$reason, "vintage_unknown"))
## C7 닫는 중 · 닫힘 · 변조 · 사양 변경
cp_chain <- function(src, nm) { d <- file.path(SB, "cp", nm); dir.create(d, recursive = TRUE); file.copy(c(rc_p4_spec_path(src), rc_p4_steps_path(src)), d); d }
X1 <- cp_chain(CD5, "closing"); invisible(.rcp4_append(X1, list(event = "chain_closing", final_k = 1L)))
X2 <- cp_chain(CD5, "closed"); invisible(.rcp4_append(X2, list(event = "chain_closed", final_k = 1L)))
X3 <- cp_chain(CD5, "tamper"); L <- readLines(rc_p4_steps_path(X3), encoding = "UTF-8"); L[2] <- sub("measured", "measureX", L[2]); writeBin(charToRaw(paste0(paste(L, collapse = "\n"), "\n")), rc_p4_steps_path(X3))
X4 <- cp_chain(CD5, "spec"); cat(" ", file = rc_p4_spec_path(X4), append = TRUE)
X5 <- cp_chain(CD5, "hold"); file.create(file.path(X5, "tick_hold"))
a7 <- vapply(list(X1, X2, X3, X4, X5), function(x) paste(pl(x)[c("action", "reason")], collapse = ":"), "")
chk("C7 chain_closing → close_stuck · closed → skip · 원장 변조 → broken ledger_broken · 사양 변경(R2) → broken spec_changed · tick_hold → skip",
    identical(a7, c("close_stuck:closing", "skip:closed", "broken:ledger_broken", "broken:spec_changed", "skip:held_by_session")), a7)
## C10 생성기 파일 변경(사슬 판이 핀을 건 뒤)
CD5 <- mk_chain("P4C74_gen"); invisible(bm_(CD5))
sf <-file.path(GD1, "step.md"); sb <- readBin(sf, "raw", file.info(sf)$size); cat("\n추가", file = sf, append = TRUE)
p10 <- pl(CD5); writeBin(sb, sf)
chk("C10 생성기 판 파일 md5 변경 → close_wait generator_changed · 되돌리면 open", identical(p10$reason, "generator_changed") && identical(pl(CD5)$action, "open"), unlist(p10))
pr <- ct_prompt(CD5, gen_out(CD5, J0()), ROOT); pt <- readLines(pr$path, encoding = "UTF-8", warn = FALSE)
chk("C10b 프롬프트 = 머리말(작업 폴더 · 네 파일만 · 판 표식) + step.md 바이트 그대로", isTRUE(pr$ok) && grepl("작업 디렉터리", pt[1]) && any(grepl(CT_PREAMBLE_ID, pt, fixed = TRUE)) &&
      identical(tail(readBin(pr$path, "raw", file.info(pr$path)$size), length(sb)), sb))
## C11 읽기 전용
lm <- vapply(list(CD, CD5, CD6, CD8), function(d) rc_md5(rc_p4_steps_path(d)), ""); for (d in list(CD, CD5, CD6, CD8)) invisible(pl(d))
chk("C11 계획기 실행 전후 원장 md5 동일(읽기 전용) · 운영 원장 · 등록부 md5 동일", identical(lm, vapply(list(CD, CD5, CD6, CD8), function(d) rc_md5(rc_p4_steps_path(d)), "")) &&
      identical(REAL, vapply(names(REAL), function(f) if (file.exists(f)) rc_md5(f) else "absent", "")))

cat("K 장부 · 물러남 · 설정 · 알림\n")
r_a <- ct_record(SD, "P4C99_k", "gen_fail", "parse"); r_b <- ct_record(SD, "P4C99_k", "gen_fail", "invalid")
chk("K1 생성 실패 RC_STANDING_MAX_FAILS 번째 → blocked · 계획 = blocked gen_failures", identical(RC_STANDING_MAX_FAILS, 2L) && identical(r_a, "count=1") && identical(r_b, "blocked") &&
      isTRUE(ct_state_read(SD, "P4C99_k")$gen_blocked))
ct_record(SD, basename(CD5), "gen_fail", "a"); ct_record(SD, basename(CD5), "gen_fail", "b"); pb <- pl(CD5); ct_reset(SD, basename(CD5))
chk("K2 차단 사슬 plan = blocked gen_failures · reset 뒤 open · 원장 무접촉", identical(pb$reason, "gen_failures") && identical(pl(CD5)$action, "open"))
chk("K3 mark = 처음 new · 다음 seen", identical(ct_record(SD, "P4C99_k", "mark", "x"), "new") && identical(ct_record(SD, "P4C99_k", "mark", "x"), "seen"))
Sys.setenv(CT_NOW = "2026-11-10 09:00:00"); d1 <- ct_record(SD, "P4C97_d", "mark_daily", "blocked:x"); d2 <- ct_record(SD, "P4C97_d", "mark_daily", "blocked:x")
Sys.setenv(CT_NOW = "2026-11-11 09:00:00"); d3 <- ct_record(SD, "P4C97_d", "mark_daily", "blocked:x"); mkn <- names(ct_state_read(SD, "P4C97_d")$marks); Sys.unsetenv("CT_NOW")
chk("K3b mark_daily(재수리) = 같은 날 new → seen · 다음 날 다시 new · 지난 날 키는 지운다", identical(c(d1, d2, d3), c("new", "seen", "new")) && identical(mkn, "blocked:x@20261111"), c(d1, d2, d3, mkn))
Sys.setenv(CT_NOW = "2026-11-10 12:00:00"); ct_backoff_set(SD, "usage_limit"); b1 <- ct_backoff_active(SD)
Sys.setenv(CT_NOW = "2026-11-10 23:59:59"); b2 <- ct_backoff_active(SD); Sys.setenv(CT_NOW = "2026-11-11 00:00:01"); b3 <- ct_backoff_active(SD); Sys.unsetenv("CT_NOW")
chk("K4 한도 물러남 = 그날 끝까지 · 다음 날 00:00 뒤 풀림", b1 && b2 && !b3)
CFG <- file.path(SB, "cfg.json"); cfg0 <- jsonlite::fromJSON(file.path(dirname(dirname(dirname(CTF))), "06_Registry/chain_tick.json"), simplifyVector = FALSE)
c_ok <- err_of(ct_config(ROOT, file.path(dirname(dirname(dirname(CTF))), "06_Registry/chain_tick.json")))
cb <- cfg0; cb$gen_timeout_sec_source <- NULL; rc_json_write(cb, CFG); c_ns <- err_of(ct_config(ROOT, CFG))
cb <- cfg0; cb$enabled <- "yes"; rc_json_write(cb, CFG); c_en <- err_of(ct_config(ROOT, CFG))
chk("K5 설정 정본 판독 ok · 숫자 근거(_source) 없음 = 거부 · enabled 문자열 = 거부(fail-closed)", identical(c_ok, "") && grepl("근거", c_ns) && grepl("enabled", c_en), c(c_ok, c_ns, c_en))
NOTI$n <- 0L; k6a <- ct_notify_close_wait(CD6, "budget_noise", ROOT, SD); k6b <- ct_notify_close_wait(CD6, "budget_noise", ROOT, SD)
chk("K6 수동 실행(발송 아님) = push FALSE · 'dry' · 표식 없음(무인 실행의 1통을 막지 않는다 · 재수리) · 다음 단계 = 세션 p4-close",
    NOTI$n == 2L && identical(c(k6a, k6b), c("dry", "dry")) && isFALSE(NOTI$last$push) && grepl("p4-close", NOTI$last$next_step) &&
      is.null(.ct_or(ct_state_read(SD, basename(CD6))$marks, list())[["close_wait:budget_noise"]]) && TG_CALLS == 0L, c(NOTI$n, k6a, k6b))
Sys.setenv(QVEST_UNATTENDED = "1"); NOTI$n <- 0L
k6c <- ct_notify_close_wait(CD6, "budget_noise", ROOT, SD); k6d <- ct_notify_close_wait(CD6, "budget_noise", ROOT, SD)
chk("K6b 무인 실행 = push TRUE · 사슬 · 사유당 1회(sent → seen)", NOTI$n == 1L && identical(c(k6c, k6d), c("sent", "seen")) && isTRUE(NOTI$last$push), c(NOTI$n, k6c, k6d))
PREP_OK <- prep_send; prep_send <- function(...) { NOTI$n <- NOTI$n + 1L; invisible(list(ok = FALSE)) }      # tg_agent_brief 실패 꼴(예외 아닌 ok FALSE)
NOTI$n <- 0L; k6e <- ct_notify_close_wait(CD6, "budget_steps", ROOT, SD); k6f <- ct_notify_close_wait(CD6, "budget_steps", ROOT, SD); prep_send <- PREP_OK
k6g <- ct_notify_close_wait(CD6, "budget_steps", ROOT, SD); k6h <- ct_notify_close_wait(CD6, "budget_steps", ROOT, SD)
chk("K6c 발송 실패(ok FALSE) → failed · 표식 없음 → 다음 시도에 다시 보낸다 · 성공 뒤 seen(재수리 — 원 결함: 첫 실패 뒤 영구 seen)",
    identical(c(k6e, k6f, k6g, k6h), c("failed", "failed", "sent", "seen")) && NOTI$n == 3L, c(k6e, k6f, k6g, k6h, NOTI$n))
Sys.setenv(QVEST_UNATTENDED = "0")

cat("M 돌연변이\n")
n <- mut_ct("  if (length(st$open_ks) >= mx) return(", "  if (FALSE) return("); pm <- pl(CD5 <- file.path(SB, "P4_ASSEMBLY", "P4C72_bud")); restore_ct()
chk("M1 계획기 예산 조건 제거 → C5 빨강(open 이 나온다 — 코어가 거부할 걸음)", n == 1L && identical(pm$action, "open"), pm$action)
n <- mut_ct("  lk <- rc_after_tau_leaks(paste(txt, collapse = \"\\n\"), tau)", "  lk <- character(0)"); CD <- CD8; rm_ <- rej(extra = "참고: 2024-08-05 급락"); restore_ct()
chk("M2 산출 전문 τ_D 검사 제거 → C8 contaminated2 빨강", n == 1L && !identical(rm_$code, "contaminated"), rm_$code)
n <- mut_ct("  V <- tryCatch(rx_validate(J$delta, root, pool = pool)", "  V <- tryCatch(list(ok = TRUE, delta = J$delta)"); rm2 <- rej(J = J0(delta = list(weighting = list(kind = "ivol")))); restore_ct()
chk("M3 rx_validate 호출 제거 → C8 invalid 빨강", n == 1L && !identical(rm2$code, "invalid"), rm2$code)
n <- mut_ct("  if (!identical(v0$id, st$base_meas$vintage$id)) return(", "  if (FALSE) return("); pm2 <- pl(CD_save, VINT2); restore_ct()
chk("M4 판 표식 비교 제거 → C6 빨강", n == 1L && !identical(pm2$reason, "vintage_changed"), pm2$reason)
n <- mut_ct("if (n >= max_fails) S$gen_blocked <- TRUE", "if (FALSE) S$gen_blocked <- TRUE"); ct_record(SD, "P4C98_m", "gen_fail", "a"); rm5 <- ct_record(SD, "P4C98_m", "gen_fail", "b"); restore_ct()
chk("M5 실패 상한 비교 제거 → K1 빨강(차단되지 않는다)", n == 1L && !identical(rm5, "blocked"), rm5)
n <- mut_ct("  if (!is.null(.ct_or(ct_state_read(sd, cid)$marks, list())[[mkey]])) return(\"seen\")", "  NULL"); Sys.setenv(QVEST_UNATTENDED = "1")
NOTI$n <- 0L; ct_notify_close_wait(CD6, "budget_steps", ROOT, SD); ct_notify_close_wait(CD6, "budget_steps", ROOT, SD); restore_ct(); Sys.setenv(QVEST_UNATTENDED = "0")
chk("M6 닫기 대기 1회 표식 제거 → K6 빨강(두 통)", n == 1L && NOTI$n == 2L, NOTI$n)
n <- mut_ct("  if (is.null(v0)) return(.ct_out(\"wait\", reason = \"vintage_unknown\"", "  if (is.null(v0) && !is.null(st$base_meas)) return(.ct_out(\"wait\", reason = \"vintage_unknown\"")
XV <- mk_chain("P4C75_vu"); pm7 <- ct_plan(XV, ROOT, SD, vintage_fun = function(root) NULL); restore_ct()
chk("M7 기준 칸 앞 판 표식 검사 제거 → C1c 빨강(measure_base 가 나온다)", n == 1L && identical(pm7$action, "measure_base"), pm7$action)
n <- mut_ct("  if (!(is.list(r) && isTRUE(r$ok))) {", "  if (FALSE) {"); Sys.setenv(QVEST_UNATTENDED = "1")
prep_send <- function(...) { NOTI$n <- NOTI$n + 1L; invisible(list(ok = FALSE)) }; r8 <- ct_notify_close_wait(CD6, "vintage_changed", ROOT, SD); prep_send <- PREP_OK
restore_ct(); Sys.setenv(QVEST_UNATTENDED = "0")
chk("M8 발송 결과(ok) 검사 제거 → K6c 빨강(실패를 sent 로 표식)", n == 1L && identical(r8, "sent"), r8)
chk("Z 발송 0 · 운영 원장 · 등록부 무접촉", TG_CALLS == 0L && identical(REAL, vapply(names(REAL), function(f) if (file.exists(f)) rc_md5(f) else "absent", "")))
cat(sprintf("== t_summary: PASS=%d FAIL=%d ==\n", PASS, FAIL))
cat(sprintf('{"test":"scn_chain_tick_core","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
if (FAIL > 0L) quit(save = "no", status = 1L)
