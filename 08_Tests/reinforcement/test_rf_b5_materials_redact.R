#!/usr/bin/env Rscript
#==============================================================================
# test_rf_b5_materials_redact.R — B5 설계 재료의 교차 entry 전기간 수치 가림
#   (도훈 결정 D-E-B5-MATERIALS 2026-09-25 · pit.md C1 D-E · 짝 = test_rf_b1_materials_redact.R(R2))
#
# 배경: B5 설계 레인은 오버레이 arm 을 고르는 무인 자동 선정기다. 재료가 다른 entry 의 전기간 측정값을 실었다
#   (09-25 실측: 최신 B5 entry 발송 재료의 교차 절 잔존 수치 543 — (3) ΔCalmar 순 상위 8/하위 8 · (4) 교훈 속 Calmar/MDD 366 ·
#   (4b) G2 obs/q/p 87 · (5) 증류 수치 · (2b) 프로그램 최고치 · (6) arm basis 의 "MDD -10 · CAGR -23").
#   수리 = rf_b5_design_lib.R 가 자기·정적 절((1)·(2)·(7)·(8)) 밖 전부를 B1 정본 가림 함수로 가리고(식별자 보존 · 절단 앞뒤 2회) ·
#   (3) 은 arm_id 순 · 발송 전 재도출 검증 — 잔존이면 재료를 쓰지 않는다(materials_rejected → 레인 materials_failed → 기존 설계).
#
# 양방향:
#   A. 적재기(.b5_redactor) — 정본(rf_b1_design_lib.R) 이름 적재 · 부수효과 0(작업 디렉터리·B1 재료 쓰기) · 6 이름만 ·
#      [위반] 이름 결손 / 같은 이름 두 번 / 무력 가림(규칙 no-op) / 무력 검증기(항상 FALSE) / 파일 부재 → NULL(fail-closed)
#   B. b5_materials 합성 루트 — 교차 절 잔존 수치 0(★검사 자체 판별기 — 피검 코드의 검증기를 빌리지 않는다) · <stat> 존재 ·
#      자기 절 수치 보존((1) 측정표·자기 L-code · (2) 바닥 해부) · (3) arm_id 순·성과 칸 가림(픽스처는 ΔCalmar 순 ≠ id 순) ·
#      (4b) 검사 상태·판정 보존 · 식별자 보존 · 700자 절단이 식별자를 잘라도 오탐 폴백 없음 · (8) A 문턱 · jlog 가린 개수
#   C. 돌연변이 — ① 절 가림 끔(게이트 유지) → 중단·파일 없음·materials_rejected(게이트가 잡는다)
#                 ② 절 가림 + 게이트 끔 → 재료에 수치 잔존 → 이 검사의 판별기가 잡는다(red)
#                 ③ (3) 순위 복원(ΔCalmar 내림차순) → arm_id 순 판별이 잡는다(red)
#                 ④ 가림 함수 적재 실패(캐시 NULL 주입) → redactor_unavailable 중단·파일 없음
#   (수리 전 판 red 실증 = QVEST_B5_LIB 를 기준판으로 바꿔 돌리면 A 는 함수 부재 · B 는 잔존 수치·순위로 실패한다)
# 격리: QVEST_RF_ROOT = tempdir 합성 루트 · QVEST_RP_JLOG = tempdir · 코드 루트(QVEST_B5_CODE_ROOT) = QM_ROOT(가림 함수 정본) —
#   운영 원장·카탈로그·jlog 무접촉(끝에 해시 대조).
# 대상 교체: QVEST_B5_LIB (기본 = QM_ROOT/02_Infrastructure/ops/rf_b5_design_lib.R)
#==============================================================================
suppressMessages({ library(jsonlite); library(data.table) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
CODE <- sub("/+$", "", gsub("\\", "/", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"), fixed = TRUE))
LIB  <- Sys.getenv("QVEST_B5_LIB", file.path(CODE, "02_Infrastructure/ops/rf_b5_design_lib.R"))
B1LIB <- file.path(CODE, "02_Infrastructure/ops/rf_b1_design_lib.R")
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat(sprintf("  OK   %s\n", m)) }
ng <- function(m, d = "") { FAIL <<- FAIL + 1L; cat(sprintf("  FAIL %s%s\n", m, if (nzchar(d)) paste0(" — ", d) else "")) }
chk <- function(cond, m, d = "") if (isTRUE(cond)) ok(m) else ng(m, d)
finish <- function() {
  cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
  cat(sprintf('{"test":"rf_b5_materials_redact","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
  quit(status = if (FAIL > 0L) 1L else 0L)
}

# ── 검사 자체 판별기(피검 코드와 독립) — 식별자를 지운 뒤 소수·백분율·%p·pp · 지표 뒤 정수가 남았나 ──────────────
ID_RX <- c("(?<![A-Za-z0-9_.])\\d{4}\\.\\d{4,5}(v\\d+)?(?![A-Za-z0-9_])", "(?<![A-Za-z0-9_.])[vV]\\d+(\\.\\d+)+(?![A-Za-z0-9_])",
           "(?<![A-Za-z0-9_.])(19[89]\\d|20[0-3]\\d)\\.(0[1-9]|1[0-2])(?![0-9])")
residual <- function(x) {
  x <- as.character(x); for (rx in ID_RX) x <- gsub(rx, " ", x, perl = TRUE)
  m1 <- regmatches(x, gregexpr("[-+\u2212]?\\d*\\.\\d+|\\d+(\\.\\d+)?\\s?(%|pp(?![A-Za-z]))", x, perl = TRUE))
  m2 <- regmatches(x, gregexpr("(?i)(?<![A-Za-z0-9_])(port_t|calmar|cagr|mdd|sharpe|icir|ic|dsr|sortino)\\s*[=:]?\\s*[-+\u2212]?\\d+(?![A-Za-z0-9_.])", x, perl = TRUE))
  unique(c(unlist(m1), unlist(m2)))
}
# 절 분할 — '## ' 머리 기준 · 교차 = 공리·(2b)·(3)·(4)·(4b)·(5)·(6) · 자기 = (1)·(2)·(7)·(8)
CROSS_H <- c("## 공리", "## (2b)", "## (3)", "## (4)", "## (4b)", "## (5)", "## (6)")
sec_of <- function(txt) {
  key <- rep(NA_character_, length(txt)); cur <- NA_character_
  for (i in seq_along(txt)) {
    if (startsWith(txt[i], "## ")) {
      cur <- NA_character_
      for (h in c(CROSS_H, "## (1)", "## (2)", "## (7)", "## (8)")) if (startsWith(txt[i], paste0(h, " "))) cur <- h
      if (is.na(cur)) cur <- paste0("?", substr(txt[i], 1, 12))
    }
    key[i] <- cur
  }
  key
}
cross_lines <- function(txt) { k <- sec_of(txt); txt[!is.na(k) & k %in% CROSS_H] }
own_lines <- function(txt, h) { k <- sec_of(txt); txt[!is.na(k) & k == h] }
s3_ids <- function(txt) {
  s <- own_lines(txt, "## (3)"); r <- s[startsWith(s, "| ") & !startsWith(s, "| arm_id") & !startsWith(s, "|---") & !startsWith(s, "| (") & !startsWith(s, "| …")]
  trimws(vapply(strsplit(r, "|", fixed = TRUE), function(z) z[2], character(1)))
}

# ── 합성 루트 ────────────────────────────────────────────────────────────────
SB <- gsub("\\", "/", file.path(tempdir(), sprintf("b5m_redact_%d", Sys.getpid())), fixed = TRUE)
unlink(SB, recursive = TRUE, force = TRUE)
for (d in c("06_Registry", "specs", "art/T_SELF", "art/T_SELF_B1_5", "stage_artifacts/l_code/reinforcement", ".cache/rf_block_design",
            "qepm/memory/axioms/active"))
  dir.create(file.path(SB, d), recursive = TRUE, showWarnings = FALSE)
JL <- file.path(SB, "jlog.jsonl"); CFGP <- file.path(SB, "06_Registry/reinforce_auto_config.json")
wjson <- function(x, p) write(toJSON(x, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = NA), p)
REAL <- c(file.path(CODE, "06_Registry/reinforce_ledger_l1.json"), file.path(CODE, "06_Registry/overlay_catalog.json"))
REAL_MD5 <- tools::md5sum(REAL[file.exists(REAL)])
REAL_JL <- file.path(CODE, ".cache/reinforce_auto_log.jsonl")   # 운영 jlog 는 다른 프로세스도 쓴다 — 이 검사의 픽스처 id 만 대조
REAL_JL_N <- if (file.exists(REAL_JL)) length(readLines(REAL_JL, warn = FALSE)) else 0L
stopifnot(file.copy(file.path(CODE, "06_Registry/reinforce_program.json"), file.path(SB, "06_Registry/reinforce_program.json")))
wjson(list(enabled = TRUE, b5_design = list(enabled = TRUE, max_cells = 8, min_cells = 3, max_new_arms = 3, max_layers = 3, prior_entries = 12,
           guards = list(max_redesign_rounds = 1, daily_arm_cap = 6, stagnation_window = 2, max_active_generated = 40))), CFGP)
Sys.setenv(QVEST_RF_ROOT = SB, QVEST_RP_JLOG = JL, QVEST_RF_CONFIG = CFGP, QVEST_B5_CODE_ROOT = CODE)
arm <- function(id, kind, basis, action = "scalar_exposure", state = "vol") list(id = id, kind = kind, family = "vol_target", basis = basis,
                                                                               status = "active", est_cost_min = 1, action = action, state = state)
wjson(list(schema = "overlay_catalog_v1", note = "fixture", families = list(vol_target = "x"), arms = list(
  arm("arm_zeta", "kind_z", "노출 축소 — 과거 칸에서 MDD -10 · CAGR -23 · 하위 10% 분위 · λ 0.94 · 1.5배"),
  arm("arm_alpha", "kind_a", "확장창 분위 게이트 — 문턱은 데이터에서 추정", action = "cross_sectional", state = "drawdown"),
  arm("arm_mid", "kind_m", "다변량 제동 · 층 3 까지", state = "multivar"))), file.path(SB, "06_Registry/overlay_catalog.json"))
writeLines(character(0), file.path(SB, "06_Registry/overlay_arm_ledger.jsonl"))
L2 <- function(id, kind) list(kind = kind, arm_id = id)
spec <- function(name, overlay = NULL, overlay_cell = NULL) {
  p <- file.path(SB, "specs", paste0(name, ".json")); s <- list(label = name)
  if (!is.null(overlay)) s$overlay <- overlay
  if (!is.null(overlay_cell)) s$overlay_cell <- overlay_cell
  wjson(s, p); p }
att <- function(n, code, pt, cagr, mdd, calmar, sp = "", adv = NULL, art = NULL) {
  a <- list(n = n, cell_code = code, idea = sprintf("[%s] fixture", code),
            essence = list(cell_code = code, block = sub("_.*$", "", code), port_t = pt, cagr = cagr, mdd = mdd, calmar = calmar, oos_retention = 0.5, spec = sp))
  if (!is.null(adv)) a$adversary <- adv
  if (!is.null(art)) a$artifacts <- art
  a }
adv_rec <- function(code, cell, floor, verdict, t3s, arm_id, kind) list(schema = "rf_overlay_adversary_v1", recorded_at = "2026-09-19T22:56:15+0900",
  code = code, verdict = verdict, reason = if (verdict == "fail") "failed: T3" else "", own_layers = list(L2(arm_id, kind)),
  cell = list(calmar = cell), floor = list(calmar = floor),
  tests = list(T1 = list(status = "pass", calmar_shift = 0.48), T4 = list(status = "pass", const_calmar = 0.432),
               T3 = list(status = t3s, obs_calmar = 0.505, placebo_q = 0.523, p_value = 0.0796), T3b = list(status = "not_computed")))
# 자기 entry — 바닥 칸(B1_5) 산출물 · 기저 산출물 · 자기 L-code(수치 포함 = 보존 대상)
dts <- seq(as.Date("2005-01-31"), by = "month", length.out = 9)
fwrite(data.table(date = dts, nav_net = c(1, 1.1, 0.88, 0.99, 1.2, 1.0, 0.9, 1.3, 1.35)), file.path(SB, "art/T_SELF_B1_5/02_nav.csv"))
fwrite(data.table(date = dts, benchmark_nav = c(1, 1, 1, 1, 1, 0.9, 0.8, 1, 1)), file.path(SB, "art/T_SELF_B1_5/05_benchmark_returns.csv"))
wjson(list(replication = list(source_paper = list(title = "Fixture paper", url = "https://arxiv.org/abs/2002.06975")),
           essence = list(portfolio_alpha_t_nw_lag3 = 2.345, cagr = 0.211, mdd = 0.502, calmar = 0.456, oos_retention = 0.61)),
      file.path(SB, "art/T_SELF/authoritative_remeasure.json"))
self_atts <- c(lapply(1:5, function(i) att(i, sprintf("B1_%d", i), pt = i + 0.125, cagr = 0.22, mdd = 0.55, calmar = 0.381,
                                           art = if (i == 5L) file.path(SB, "art/T_SELF_B1_5") else NULL)),
               list(att(6, "B2_6", pt = 1.777, cagr = 0.2, mdd = 0.5, calmar = 0.4, sp = spec("self_b2", overlay = L2("arm_mid", "kind_m")))))
# 교차 entry — ΔCalmar 순은 zeta > mid > alpha (id 순 alpha < mid < zeta 와 반대)
oth1 <- list(att(1, "B1_1", pt = 1, cagr = 0.1, mdd = 0.5, calmar = 0.2),
             att(2, "B5_16", pt = 2.5, cagr = 0.25, mdd = 0.4, calmar = 0.9, sp = spec("o1_16", overlay_cell = L2("arm_zeta", "kind_z")),
                 adv = adv_rec("B5_16", 0.9, 0.2, "fail", "fail", "arm_zeta", "kind_z")),
             att(3, "B5_17", pt = 0.5, cagr = 0.05, mdd = 0.6, calmar = 0.05, sp = spec("o1_17", overlay_cell = L2("arm_alpha", "kind_a")),
                 adv = adv_rec("B5_17", 0.05, 0.2, "pass", "pass", "arm_alpha", "kind_a")))
oth2 <- list(att(1, "B1_1", pt = 1, cagr = 0.1, mdd = 0.5, calmar = 0.2),
             att(2, "B5_16", pt = 1.5, cagr = 0.15, mdd = 0.45, calmar = 0.4, sp = spec("o2_16", overlay_cell = L2("arm_mid", "kind_m"))))
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
MECH <- paste("판정: B5_22(xs_vol_gap_corr_brake × multivar_marginal_risk_share_tilt) Calmar 0.763 · MDD 0.287~0.615(폭 0.328) · 폭 5.5%p · 4pp 차 ·",
              "PORT_t 3 · −0.280 과 +1.25 · 0.338이 가장 높고 · 근거 arXiv 2002.06975 · v10.4 · RP_20260917_105807_22632 · L-RF-20260905_120000 · b5gen_fx_1 · 25종")
wr_l("T_OTH2", "B5", MECH, c("MDD 0.543~0.615 인 스칼라 축 재탕", "Calmar 0.332 인 dd_recovery 스택"))
# 700자 절단이 식별자(arXiv 2002.06975) 한가운데("2002.069")를 자르는 기전 — 절단 뒤 가림이 없으면 소수 모양 조각이 게이트를 멈춘다
wr_l("T_OTH1", "B5", paste0(strrep("가", 692), "2002.06975 뒤 서술 Calmar 0.9"))
wr_l("T_SELF", "B1", "자기 entry 기전 — B1_5 PORT_t 5.125 · Calmar 0.381 (자기 측정 — 가리지 않는다)")
wjson(list(as_of = "2026-09-24T11:16:05+0900", binding = "calmar", co_binding = list("oos_retention"),
           program_best = list(port_t = 4.349, calmar = 0.501, mdd = 0.551, cagr = 0.276), thresholds = list(calmar_min = 0.64, port_t_min = 2.95),
           recurring_class = list(shape = "erosion", shape_rule = "rule", depth_median = 0.551, m_peak_trough_median = 25.7, ratio_median = 1.337, n_lineages_sharing = 5),
           pool_inventory = list(defensive_n = 361, defensive_deep_dd_excess_median = 2.57, defensive_deep_dd_negative_share = 0.169),
           overlay = list(status = "dead", adv_pass = 0, n_verdict = 114)), file.path(SB, ".cache/rf_director_context.json"))
wjson(list(n_entries = 1L, entries = list(list(dist_id = "DIST-T-001", status = "distilled", polarity = "negative", research_mode = "overlay",
      statement_refined = "오버레이 낙폭 축소는 Calmar 0.504 에서 멈췄다 · CAGR -1.71% · IC 0.22 · ICIR 1.88",
      retry_condition = "Calmar 0.64 넘는 칸 재현 시", n_supporting = 3L))), file.path(SB, "06_Registry/distilled_knowledge.json"))
wjson(list(axiom_id = "AX-900", name = "fixture", statement = "오버레이 반증 통과율 0.12 · 낙폭 57% 에서 멈춘다"),
      file.path(SB, "qepm/memory/axioms/active/AX-900.json"))

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

cat("=== test_rf_b5_materials_redact ===\n")
E <- tryCatch(load_lib(LIB), error = function(e) { ng("라이브러리 적재", conditionMessage(e)); NULL })
if (is.null(E)) finish()

cat("--- A. 적재기 — 정본 이름 적재 · 부수효과 0 · fail-closed ---\n")
if (exists(".b5_redactor", envir = E) && exists("B5_OWN_SECTIONS", envir = E)) {
  wd0 <- getwd()
  RX <- E$.b5_redactor(B1LIB)
  chk(is.list(RX) && is.function(RX$redact) && is.function(RX$has) && identical(RX$mask, "<stat>"), "A1 정본(rf_b1_design_lib.R) 가림 함수 적재 · 표식 <stat>")
  chk(identical(getwd(), wd0), "A2 부수효과 0 — 작업 디렉터리 불변(그 파일을 source 했다면 최상위 setwd(QVEST_RF_ROOT) 로 바뀐다)", getwd())
  if (is.list(RX)) {
    fe <- environment(RX$redact)
    chk(setequal(ls(fe, all.names = TRUE), E$B5_REDACT_NAMES) && !exists("b1_materials", envir = fe, inherits = FALSE),
        "A3 적재 환경엔 가림 규칙·함수 6 이름뿐(b1_materials·setwd 등 나머지 최상위 식은 평가하지 않는다)", paste(ls(fe, all.names = TRUE), collapse = ","))
    x <- "B5_22 arm_x Calmar 0.763 · MDD 0.287~0.615 · 5.5%p · PORT_t 3 · arXiv 2002.06975 · v10.4 · RP_20260917_105807_22632"
    y <- RX$redact(x)
    chk(!length(residual(y)) && grepl("2002.06975", y, fixed = TRUE) && grepl("RP_20260917_105807_22632", y, fixed = TRUE) && grepl("B5_22 arm_x", y, fixed = TRUE),
        "A4 적재한 가림 = 수치 0 · 식별자 보존", y)
  }
  b1 <- readLines(B1LIB, warn = FALSE, encoding = "UTF-8")
  mk <- function(tag, lines) { p <- file.path(SB, sprintf("b1_%s.R", tag)); writeLines(lines, p, useBytes = TRUE); p }
  i_has <- grep("^rf_b1_has_stats <- function", b1)
  i_red_rule <- grep("for (rx in RF_B1_STAT_RULES) s <- gsub(rx, RF_B1_STAT_MASK, s, perl = TRUE)", b1, fixed = TRUE)
  i_has_body <- grep("any(vapply(c(RF_B1_STAT_RULES, RF_B1_STAT_METRIC), function(rx) any(grepl(rx, x, perl = TRUE)), logical(1)))", b1, fixed = TRUE)
  if (length(i_has) == 1L && length(i_red_rule) == 1L && length(i_has_body) == 1L) {
    b_miss <- b1; b_miss[i_has] <- sub("^rf_b1_has_stats", "rf_b1_has_stats_renamed", b_miss[i_has])
    chk(is.null(E$.b5_redactor(mk("miss", b_miss))), "A5 [위반] 이름 결손(rf_b1_has_stats 없음) → NULL")
    chk(is.null(E$.b5_redactor(mk("dup", c(b1, "rf_b1_redact_stats <- function(x) x")))), "A6 [위반] 같은 이름 두 번(뒤에 무력판 덧정의) → NULL")
    b_noop <- b1; b_noop[i_red_rule] <- sub("s <- gsub(rx, RF_B1_STAT_MASK, s, perl = TRUE)", "s <- s", b_noop[i_red_rule], fixed = TRUE)
    b_noop <- sub('s <- gsub(RF_B1_STAT_METRIC, paste0("\\\\1\\\\2", RF_B1_STAT_MASK), s, perl = TRUE)', "s <- s", b_noop, fixed = TRUE)
    chk(is.null(E$.b5_redactor(mk("noop", b_noop))), "A7 [위반] 무력 가림(규칙 no-op) → 적재 양성 대조가 잡는다 → NULL")
    b_blind <- b1; b_blind[i_has_body] <- sub("any(vapply(c(RF_B1_STAT_RULES, RF_B1_STAT_METRIC), function(rx) any(grepl(rx, x, perl = TRUE)), logical(1)))",
                                               "FALSE", b_blind[i_has_body], fixed = TRUE)
    chk(is.null(E$.b5_redactor(mk("blind", b_blind))), "A8 [위반] 무력 검증기(항상 FALSE) → 적재 양성 대조가 잡는다 → NULL")
  } else ng("A5~A8 돌연변이 좌표 미발견 — 정본 판이 바뀌었다(검사 갱신 필요)", sprintf("%d/%d/%d", length(i_has), length(i_red_rule), length(i_has_body)))
  chk(is.null(E$.b5_redactor(file.path(SB, "nope.R"))), "A9 [위반] 정본 파일 부재 → NULL")
} else ng("A 적재기 부재(.b5_redactor · B5_OWN_SECTIONS)", "수리 전 판이면 기대된 red")

cat("--- B. b5_materials — 교차 절 수치 0 · 자기 절 보존 · arm_id 순 ---\n")
unlink(JL)
M <- mat(E, "main")
if (!inherits(M$r, "err") && !is.null(M$txt)) {
  txt <- M$txt; xl <- cross_lines(txt); rs <- residual(xl)
  chk(length(xl) > 20L && !length(rs), "B1 ★교차 절(공리·(2b)·(3)·(4)·(4b)·(5)·(6)) 잔존 수치 0 — 검사 자체 판별기", paste(head(rs, 12), collapse = ","))
  chk(sum(lengths(regmatches(xl, gregexpr("<stat>", xl, fixed = TRUE)))) >= 20L, "B2 가린 자리는 <stat> 로 남는다(수치가 있었다는 사실은 보존)")
  s1 <- own_lines(txt, "## (1)"); s2 <- own_lines(txt, "## (2)")
  chk(any(grepl("5.125", s1, fixed = TRUE)) && any(grepl("0.381", s1, fixed = TRUE)) && any(grepl("2.345", s1, fixed = TRUE)) && any(grepl("1.777", s1, fixed = TRUE)),
      "B3 자기 entry 측정표·기저 수치는 그대로((1) PORT_t 5.125 · Calmar 0.381 · 기저 t 2.345 · B2_6 1.777)")
  chk(any(grepl("자기 entry 기전 — B1_5 PORT_t 5.125", s1, fixed = TRUE)), "B4 자기 entry L-code 기전은 가리지 않는다")
  chk(any(grepl("깊이 25.0%", s2, fixed = TRUE)) && any(grepl("1.25", s2, fixed = TRUE)), "B5 (2) 바닥 낙폭 해부(자기 산출물) 수치 보존 — 깊이 25.0% · 비 1.25")
  ids <- s3_ids(txt)
  chk(identical(ids, c("arm_alpha", "arm_mid", "arm_zeta")), "B6 ★(3) arm 목록 = arm_id 순(ΔCalmar 순 zeta>mid>alpha 가 아니다)", paste(ids, collapse = ","))
  s3 <- own_lines(txt, "## (3)"); rows3 <- s3[startsWith(s3, "| arm_") & !startsWith(s3, "| arm_id")]
  chk(length(rows3) == 3L && all(endsWith(rows3, "| <stat> |")) && !any(grepl("상위|하위", s3[1])), "B7 (3) 성과 칸 = <stat> 뿐 · '상위/하위' 순위 머리 없음", paste(rows3, collapse = " / "))
  s4b <- own_lines(txt, "## (4b)")
  chk(any(grepl("fail obs <stat> vs q <stat> p <stat>", s4b, fixed = TRUE)) && any(grepl("pass const <stat>", s4b, fixed = TRUE)) &&
      any(grepl("| B5_16 |", s4b, fixed = TRUE)) && any(grepl("arm_zeta", s4b, fixed = TRUE)),
      "B8 (4b) 검사 상태·판정·코드·스택은 남고 수치만 가린다", paste(s4b[grepl("B5_16", s4b)], collapse = " / "))
  flat <- paste(txt, collapse = "\n")
  chk(grepl("2002.06975", flat, fixed = TRUE) && grepl("v10.4", flat, fixed = TRUE) && grepl("RP_20260917_105807_22632", flat, fixed = TRUE) &&
      grepl("L-RF-20260905_120000", flat, fixed = TRUE) && grepl("b5gen_fx_1", flat, fixed = TRUE) && grepl("DIST-T-001", flat, fixed = TRUE) &&
      grepl("AX-900", flat, fixed = TRUE), "B9 식별자 보존 — arXiv id · 버전 · RP_/L-RF- id · arm id · DIST/AX id")
  s4 <- own_lines(txt, "## (4)"); m1 <- s4[grepl("^- 기전: 가+", s4)]
  chk(length(m1) == 1L && nchar(sub("^- 기전: ", "", m1)) <= 710L && !length(residual(m1)),
      "B10 700자 절단이 식별자 한가운데를 잘라도 조각까지 가린다 — 오탐 폴백 없이 재료가 나온다", substr(m1, nchar(m1) - 20L, nchar(m1)))
  s8 <- own_lines(txt, "## (8)")
  chk(any(grepl("A 등급 문턱", s8, fixed = TRUE) & grepl("0.640", s8, fixed = TRUE)) && !any(grepl("4.349", flat, fixed = TRUE)),
      "B11 (2b) 프로그램 최고치는 가리고 A 문턱(고정 축 상수)만 (8) 로 옮겨 싣는다")
  ev <- jl(); w <- ev[grepl('"event":"materials_written"', ev)]
  chk(length(w) == 1L && grepl('"cross_entry_stats_masked":[1-9]', w) && grepl('redacted_sections', w), "B12 jlog materials_written 에 가린 개수·가린 절")
  chk(identical(sort(M$r$redacted_sections), sort(c("axioms", "director", "outcomes", "prior", "adv", "distilled", "catalog"))),
      "B13 가림 절 = 자기·정적 절((1)·(2)·(7)·(8)) 밖 전부", paste(M$r$redacted_sections, collapse = ","))
} else ng("B 재료 생성 실패", if (inherits(M$r, "err")) as.character(M$r) else "파일 없음")

cat("--- C. 돌연변이 ---\n")
RED_DEF <- ".redact_x <- function(S) { for (k in xsecs) if (length(S[[k]])) S[[k]] <- RX$redact(S[[k]]); S }"
GATE    <- "|| isTRUE(RX$has(xl))) {"
ORDER   <- "O <- O[order(as.character(O$arm_id), method = \"radix\")]"
m1 <- mutate("noredact", list(c(RED_DEF, ".redact_x <- function(S) S")))
if (m1$applied) {
  unlink(JL); r <- mat(load_lib(m1$path), "m1")
  chk(inherits(r$r, "err") && is.null(r$txt) && any(grepl('"event":"materials_rejected"', jl()) & grepl("cross_entry_stats_residual", jl())),
      "C1 [돌연변이] 절 가림 끔(게이트 유지) → 재료 생성 중단 · 파일 없음 · materials_rejected(게이트가 잡는다)")
} else ng("C1 돌연변이 미적용(좌표 변경)")
m2 <- mutate("noredact_nogate", list(c(RED_DEF, ".redact_x <- function(S) S"), c(GATE, "|| FALSE) {")))
if (m2$applied) {
  r <- mat(load_lib(m2$path), "m2")
  chk(!inherits(r$r, "err") && length(residual(cross_lines(r$txt))) > 10L,
      "C2 [돌연변이] 가림+게이트 끔 → 재료에 교차 수치 잔존 → 이 검사의 판별기가 잡는다(B1 이 red)", sprintf("잔존 %d", length(residual(cross_lines(r$txt)))))
} else ng("C2 돌연변이 미적용(좌표 변경)")
m3 <- mutate("rank", list(c(ORDER, "O <- O[order(-O$med_d_calmar)]")))
if (m3$applied) {
  r <- mat(load_lib(m3$path), "m3")
  chk(!inherits(r$r, "err") && !identical(s3_ids(r$txt), sort(s3_ids(r$txt))),
      "C3 [돌연변이] (3) ΔCalmar 순위 복원 → arm_id 순 판별이 잡는다(B6 이 red)", paste(s3_ids(r$txt), collapse = ","))
} else ng("C3 돌연변이 미적용(좌표 변경)")
E4 <- load_lib(LIB)
if (exists(".B5_RX", envir = E4)) {
  assign("rx", NULL, envir = E4$.B5_RX); unlink(JL)
  r <- mat(E4, "m4")
  chk(inherits(r$r, "err") && is.null(r$txt) && any(grepl("redactor_unavailable", jl())),
      "C4 [위반 주입] 가림 함수 적재 실패(NULL) → redactor_unavailable 중단 · 파일 없음(가리지 않은 재료가 나가는 길 없음)")
} else ng("C4 캐시 환경(.B5_RX) 부재", "수리 전 판이면 기대된 red")

cat("--- Z. 격리 ---\n")
now_md5 <- tools::md5sum(REAL[file.exists(REAL)])
chk(identical(unname(now_md5), unname(REAL_MD5)), "Z1 운영(QM_ROOT) 원장·카탈로그 해시 불변")
new_jl <- if (file.exists(REAL_JL)) { l <- readLines(REAL_JL, warn = FALSE); if (length(l) > REAL_JL_N) l[(REAL_JL_N + 1L):length(l)] else character(0) } else character(0)
chk(!any(grepl('"base_id":"T_(SELF|OTH[0-9])"', new_jl)), "Z2 운영 jlog 에 이 검사의 픽스처 이벤트 0")
unlink(SB, recursive = TRUE, force = TRUE)
finish()
