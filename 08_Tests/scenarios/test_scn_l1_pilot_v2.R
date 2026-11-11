## test_scn_l1_pilot_v2.R — v10.2 사다리 루프 종단 파일럿 + A 경로 소방 훈련(코어 v2 · 도훈 L1-CHAIN-PILOT-FIRST-20261111 · 판단 J-20261111-010)
##   실행 = bash 08_Tests/scenarios/run_l1_pilot_v2.sh — 거울 루트(M = 저장소 HEAD 의 코드 · 등록부 사본 + 등급 계약 데이터 사본)를 만들고
##          R_ENVIRON_USER = 빈 파일 · QM_ROOT = CLAUDE_PROJECT_DIR = RC_SA_ROOT = M 으로 이 파일을 부른다(직접 부르면 첫 줄 단정에서 멈춘다).
##   단계(무엇이 진짜이고 무엇이 대역인가 — 보고에 그대로 싣는다):
##     S 상설 판 — v2 상설 판을 M 의 등록부에 실제 등록(rc_register · 점검 · 철학 P1 영수증 = M 의 판단 원장 사본) → 스캔 → 측정(가짜 측정기 =
##       KOSPI200 실제 월 수익 위 합성 수익) → 판정(등록 규칙 실제 적용 · t(α) = 실제 계약 · 상승 포착 = 실제 행동 카드 · 칸 평가의 RAWDATA 패킷은 대역) → 보고(건식)
##     B 기저 풀 — 알려진 답 2건(처치 칸만 통과 = 맨 엔진 자격 없음 · 등급 경로 기저 = 자격 없음) · v1 코어 = 틀린 답(자식 프로세스 대조)
##     C 사슬 — 판 등록(감독 영수증) → 기준 칸 → 걸음 채택 · 기각(실제 보는 창 지표 · 등록 규칙) → 닫기 = 실제 선택 현실 점검 재채점(selection_regrade.R) +
##       실제 A 자격 관문(round_candidate_gate.R → rf_a_eligibility) → judge_request.eligible.json(건식 — Judge 스폰 없음) · 모듈 풀 등재 = 임시 루트만
##     K 막힘 경로 — 배리어 잠김 · 데이터 낡음 · 판 표식 진행 중 · GPU 대기 · 측정 실패(2회 → 포기) · 핀 변경(상설 R2) — 원장 무기록 · 풀리면 잇는다
##     R 실행기 — round.sh 판 라우팅(v2 판 · v1 판 공존) · p4-pool · p4-status · 사슬 틱 드라이런(chain_tick.sh · 판 라우팅)
##     Z 격리 — 실제 원장 md5 불변 · 실발송 0(QVEST_TG_DRY_RUN=1 · 발송 본문 보관 수 불변)
REPO <- gsub("\\\\", "/", Sys.getenv("PILOT_REPO", "")); M <- gsub("\\\\", "/", Sys.getenv("QM_ROOT", ""))
if (!nzchar(REPO) || !nzchar(M) || identical(tolower(M), tolower(REPO)) || startsWith(tolower(M), tolower(paste0(REPO, "/"))) ||
    !file.exists(file.path(M, ".pilot_mirror")) || !identical(Sys.getenv("QVEST_TG_DRY_RUN"), "1") || !identical(gsub("\\\\", "/", Sys.getenv("RC_SA_ROOT")), M))
  stop("[pilot] 거울 루트 격리 단정 실패 — run_l1_pilot_v2.sh 로만 돈다(QM_ROOT = 거울 · RC_SA_ROOT = 거울 · 텔레그램 건식)")
setwd(M)
suppressMessages(source(file.path(M, "04_Research/programs/_lib/round_core/v2/load.R")))
if (!identical(rc_root(), M) || !identical(RC_VERSION, "v2")) stop("[pilot] 코어 루트 ≠ 거울 또는 판 ≠ v2")
suppressMessages(source(file.path(M, "02_Infrastructure/programs/rx_round.R")))
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
PASS <- 0L; FAIL <- 0L; STEPS <- list()
chk <- function(id, name, ok, detail = "", ev = list()) {
  ok <- isTRUE(ok); if (ok) PASS <<- PASS + 1L else FAIL <<- FAIL + 1L
  cat(sprintf("  [%s] %s %s%s\n", if (ok) "ok" else "FAIL", id, name, if (!ok && length(detail) && nzchar(paste(detail, collapse = ""))) paste0(" — ", paste(detail, collapse = " ")) else ""))
  STEPS[[length(STEPS) + 1L]] <<- list(id = id, name = name, ok = ok, detail = paste(detail, collapse = " "), evidence = ev)
}
err_of <- function(expr) tryCatch({ force(expr); "" }, error = function(e) conditionMessage(e))
md5 <- function(p) unname(as.character(tools::md5sum(p)))
OUT <- file.path(M, "pilot_out"); dir.create(OUT, showWarnings = FALSE)
TAU <- rc_ref_value("06_Registry/behavior_card.json::tau_d")
RUN_TS <- format(Sys.time(), "%Y%m%d_%H%M%S")
E <- rc_deps(M)
BRC <- new.env(parent = globalenv()); invisible(capture.output(suppressMessages(sys.source(file.path(M, "02_Infrastructure/contracts/backtest_result_contract.R"), envir = BRC))))
ESS <- new.env(parent = globalenv()); invisible(capture.output(suppressMessages(sys.source(file.path(M, "02_Infrastructure/contracts/essence_score.R"), envir = ESS))))   # DSR(진단 · .essence_dsr)
AX <- rc_ref_value("02_Infrastructure/worktask/constraint_defaults.json::measurement_axis.active")
EXEC <- rc_ref_value("02_Infrastructure/worktask/constraint_defaults.json::execution.exec_price")   # 현행 집행 규약(A 관문 legacy_regime 대조)
cat(sprintf("[pilot] 거울 루트 %s · 코어 %s · τ_D %s · 측정 축 %s\n", M, RC_VERSION, TAU, AX))

## ═══ 합성 측정기 — KOSPI200 실제 월 수익(거울 .cache/benchmark.parquet 사본) 위 r = α + β·bm + ε · 계약 함수(build_metrics · build_benchmark_compare) ·
##     실제 등급 계약(gv3_score_dir)으로 측정 시점 등급 ═════════════════════════════════════════════════════════════════
BM <- local({ h <- as.data.table(arrow::read_parquet(file.path(M, ".cache/benchmark.parquet")))[is.finite(BM_Ret)][, .(Date = as.Date(Date), r = BM_Ret)]
  h[, ym := format(Date, "%Y-%m")]; m <- h[, .(date = max(Date), bm = prod(1 + r) - 1, nd = .N), by = ym][order(ym)]
  m[ym >= "2000-01" & nd >= 15L] })
BM <- BM[ym < format(Sys.Date(), "%Y-%m")]                       # 끝난 달만
cat(sprintf("[pilot] 벤치 월 %d개(%s ~ %s)\n", nrow(BM), BM$ym[1], BM$ym[nrow(BM)]))
mk_syn <- function(nm, alpha, beta, sd, seed, n_trials = 1L, grade = TRUE) {
  set.seed(seed); n <- nrow(BM); r <- alpha + beta * BM$bm + rnorm(n, 0, sd)
  d <- file.path(M, "stage_artifacts/replication/pilot", nm); unlink(d, recursive = TRUE); dir.create(d, recursive = TRUE)
  rid <- sprintf("RP_%s_%s", RUN_TS, gsub("[^A-Za-z0-9]", "", nm))
  pr <- data.table(date = BM$date, ret_net = r, risk_free_ret = 0, leverage = 1, frequency = "monthly")
  br <- data.table(date = BM$date, benchmark_ret = BM$bm, benchmark_id = "KOSPI200")
  nv <- data.table(date = BM$date, nav_net = cumprod(1 + r))
  ho <- data.table(run_id = rid, date = rep(BM$date, each = 2L), ticker = rep(c("A005930", "A000660"), n), target_weight = 0.5)
  fwrite(nv, file.path(d, "02_nav.csv")); fwrite(pr, file.path(d, "03_period_returns.csv")); fwrite(ho, file.path(d, "04_holdings.csv")); fwrite(br, file.path(d, "05_benchmark_returns.csv"))
  au <- list(status = "OK", run_id = rid, strategy_id = nm, metric_type = "backtested", grade_scheme = "grade_v3", essence_grade = NA_character_,
             selection_type = "sweep", n_trials_cumulative = as.integer(n_trials),
             measurement_regime = list(selection_type = "sweep", n_trials_cumulative = as.integer(n_trials), n_trials_basis = "round_cells",
                                       exec_price = EXEC, exec_price_basis = "argument", cost_model_version = "pilot_synthetic"),
             measurement_axis = list(epoch = AX), pilot = list(synthetic = TRUE, alpha = alpha, beta = beta, sd = sd, seed = seed))
  a <- r - BM$bm; mu <- mean(a); s <- sd(a)                       # DSR(BLdP) — 계약 함수 그대로(essence_score.R .essence_dsr · 진단 · v3.4 관문 아님)
  au$dsr <- ESS$.essence_dsr(mu / s * sqrt(12), n, as.integer(n_trials), mean(((a - mu) / s)^3), mean(((a - mu) / s)^4), A = 12); au$essence <- list(dsr = au$dsr)
  if (isTRUE(grade)) {
    met <- BRC$build_metrics(nv, pr, ho, rid, nm, frequency = "monthly", annualization_factor = 12)
    cmp <- BRC$build_benchmark_compare(pr, br, rid, nm, annualization_factor = 12)
    fwrite(met, file.path(d, "06_metrics.csv")); fwrite(cmp, file.path(d, "07_benchmark_compare.csv"))
    rc_json_write(au, file.path(d, "authoritative_remeasure.json"))
    g <- E$gv3_score_dir(d, root = M); au$essence_grade <- g$grade; au$grade_v3 <- g
  }
  rc_json_write(au, file.path(d, "authoritative_remeasure.json"))
  saveRDS(list(holdings = ho[, .(date, ticker, weight = target_weight)], period_returns = pr), file.path(d, "bt_result.rds"))
  d
}
## 칸 사양 · 시행 수 → 합성 모수(code 꼬리로 고른다 · 결정론)
SYN <- list(X_E2 = c(0.000, 0.90, 0.030), X_E3 = c(0.010, 0.70, 0.022), Y_E2 = c(0.008, 0.80, 0.022),
            k0 = c(0.004, 0.85, 0.025), k1 = c(0.012, 0.75, 0.020), k2 = c(0.003, 0.90, 0.026), k3 = c(0.004, 0.85, 0.025), k4 = c(0.004, 0.85, 0.025))
RUN <- new.env(); RUN$n <- 0L; RUN$fail_k <- character(0)
runner_syn <- function(spec_path, code, out_json, log_dir, root, role = "variant") {
  RUN$n <- RUN$n + 1L; s <- rc_json_read(spec_path); k <- sub("^.*_(k[0-9]+)$", "\\1", code)
  if (k %in% RUN$fail_k) { rc_json_write(list(n = 1L, code = code, ok = FALSE, err = "pilot 주입 실패"), out_json); return(1L) }
  p <- SYN[[k]]; d <- mk_syn(sprintf("%s_n%d", code, RUN$n), p[1], p[2], p[3], seed = 200L + as.integer(sub("k", "", k)),
                             n_trials = as.integer(s$selection_accounting$n_family_at_registration %||% 1L))
  rc_json_write(list(n = 1L, code = code, ok = TRUE, artifacts = d), out_json); 0L
}
FP <- function() "pilot-fp"; FRESH <- function(root) list(ok = TRUE, state = "fresh", reason = "pilot 주입")
FREE <- function(root) list(state = "free", reason = "", lock = "", blocking = FALSE)
GPUOK <- function(engine_path, holder, purpose = holder, root = rc_root()) list(ok = TRUE, need = FALSE, state = "cpu", reason = "pilot", release = function() invisible(NULL))
VINT <- rc_p4_vintage_default          # 실제 판 표식(거울 루트의 판 표식 원장 사본)

## ═══ S. 상설 판(v2) — 등록 → 스캔 → 측정 → 판정 → 보고 ═══════════════════════════════════════════════
cat("\nS 상설 판(v2)\n")
mk_engine <- function(nm) { d <- file.path(M, "04_Research/strategies", nm); dir.create(d, recursive = TRUE, showWarnings = FALSE)
  writeLines(c(sprintf("## 파일럿 합성 엔진 %s — 실행하지 않는다(측정은 파일럿 가짜 측정기)", nm), "PORTFOLIO <- NULL", strrep("## 채움 — 검증기 하한(200바이트)\n", 8)), file.path(d, "engine.R"))
  rc_json_write(list(paper_key = paste0("9990.", sub("RP_AUTO_PILOT_", "", nm)), paper_url = paste0("https://arxiv.org/abs/9990.0000", nchar(nm) %% 9)), file.path(d, "lane_provenance.json"))
  file.path(d, "engine.R") }
ENG_X <- mk_engine("RP_AUTO_PILOT_X"); ENG_Y <- mk_engine("RP_AUTO_PILOT_Y"); ENG_Z <- mk_engine("RP_AUTO_PILOT_Z")
pp <- function(k) list(url = paste0("https://arxiv.org/abs/", k), title = paste("Pilot paper", k), paper_key = k)
## 레인 인계(등록부 — 거울 사본 · writer pr_save) — 등급 Z = B(등급 경로 사례) · X · Y = C
lane_art <- function(nm, g) { d <- file.path(M, "stage_artifacts/replication/pilot_lane", nm); dir.create(d, recursive = TRUE, showWarnings = FALSE)
  rc_json_write(list(run_id = sprintf("RP_%s_lane", RUN_TS), essence_grade = g, grade_scheme = "grade_v3"), file.path(d, "authoritative_remeasure.json")); d }
reg <- pr_load(M)
pi <- which(vapply(reg$programs, function(p) identical(p$id, "P1_RETURN"), TRUE))
hand <- function(nm, eng, art, k) list(key = paste0("engine:PILOT_", nm), kind = "engine", engine_path = eng, artifacts = art, has_short = FALSE,
                                       implementation_suspect = FALSE, holdings_claim_mismatch = FALSE, audit_verdict = "faithful", paper_key = k,
                                       title = paste("Pilot paper", k), enqueued_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"))
reg$programs[[pi]]$consumed <- c(reg$programs[[pi]]$consumed %||% list(), list(hand("X", ENG_X, lane_art("X", "C"), "9990.X"),
                                 hand("Y", ENG_Y, lane_art("Y", "C"), "9990.Y"), hand("Z", ENG_Z, lane_art("Z", "B"), "9990.Z")))
e_reg <- err_of(pr_save(reg, M))
chk("S0", "거울 등록부에 파일럿 레인 인계 3건(writer pr_save · 검사 통과)", !nzchar(e_reg), e_reg)
RD <- file.path(M, "04_Research/programs/P1_RETURN/P1S90_pilot"); RID <- "P1S90_pilot"
dir.create(file.path(RD, "specs"), recursive = TRUE, showWarnings = FALSE)
sp_std <- function(code, eng, k) { s <- rc_p1_cell_spec(code, eng, pp(k), k, 1L, "파일럿 시드(시행 무가산)", root = M); p <- file.path(RD, "specs", paste0(code, ".json")); rc_json_write(s, p); p }
S_XE2 <- sp_std("P1S90_X_E2", ENG_X, "9990.X"); S_YE2 <- sp_std("P1S90_Y_E2", ENG_Y, "9990.Y")
s3 <- rc_json_read(S_XE2); s3$code <- "P1S90_X_E3"; s3$factors <- list(list(kind = "db", id = "M01_Mom_12_1"))
s3$weighting <- list(kind = "catalog", catalog_id = "lean:entropy", label = "entropy"); s3$rebalance <- list(kind = "rank_buffer", mult = 2, label = "buffer_2x")
S_XE3 <- file.path(RD, "specs", "P1S90_X_E3.json"); rc_json_write(s3, S_XE3)
seeds <- list(list(code = "P1S90_X_E2", engine = "X_E2", role = "reference", spec = rc_rel(S_XE2, M)),
              list(code = "P1S90_X_E3", engine = "X_E3", role = "reference", spec = rc_rel(S_XE3, M)),
              list(code = "P1S90_Y_E2", engine = "Y_E2", role = "reference", spec = rc_rel(S_YE2, M)))
LANE0 <- file.path(M, "pilot_lane_empty"); dir.create(LANE0, showWarnings = FALSE)
e_init <- err_of(rc_init_standing_p1(RD, RID, seeds, purpose = "파일럿(v2 · 임시 원장)", hypothesis = "P1 규칙 · 표준 구성 재현",
                                     scan = list(lane_root = rc_rel(LANE0, M)), exposures = list("파일럿 — 합성 자료"), conclusion_scope = list("파일럿"), root = M))
spec0 <- tryCatch(rc_json_read(file.path(RD, "round_spec.json")), error = function(e) list())
chk("S1", "상설 판 골격(v2 · core_version v2 · 시드 3 = 맨 엔진 X · 처치 X · 맨 엔진 Y)", !nzchar(e_init) && identical(spec0$core_version, "v2") && length(spec0$cells) == 3L, e_init)
LED <- file.path(M, "06_Registry/q_judgment_ledger.json"); RVR <- M
add_review <- function(id, role, trigger, round, file) {
  dir.create(dirname(file.path(RVR, file)), recursive = TRUE, showWarnings = FALSE); writeLines(sprintf("파일럿 리뷰 %s(합성 — 거울 루트)", id), file.path(RVR, file))
  L <- rc_json_read(LED); L$reviews <- c(L$reviews, list(list(id = id, at = rc_now(), role = role, trigger = trigger, round = round, file = file, challenges = list())))
  rc_json_write(L, LED) }
SFP <- "04_Research/programs/_supervision/superfan/"
add_review("R-PILOT-P1S90", "philosophy", "P1", RID, sprintf("%sphilosophy/20261111_1900_P1_%s.md", SFP, rc_round_tag(RID)))
e_reg2 <- err_of({ rc_draft(RD, M); rv <- file.path(OUT, "review_v1.md"); writeLines("파일럿 점검 ok", rv); rc_mark_reviewed(RD, 1L, rv, "ok", M)
                   rc_register(RD, M, ledger = LED, check_git = FALSE, run_tests = FALSE, review_root = RVR) })
pre <- tryCatch(rc_json_read(file.path(M, "stage_artifacts/programs/P1_RETURN", RID, "prereg.json")), error = function(e) list())
chk("S2", "상설 판 등록(rc_register — 점검 · 철학 P1 영수증 · 핀 · 거울 등록부) · 사전등록 코어 판 v2", !nzchar(e_reg2) && identical(pre$core$version, "v2"), e_reg2)
sc <- tryCatch(rc_standing_scan(RD, M), error = function(e) e)
chk("S3", "스캔 — 시드 3 넣음(레인 비움 · 입구 규칙)", !inherits(sc, "error") && length(sc$enqueued) == 3L, if (inherits(sc, "error")) conditionMessage(sc) else paste(sc$enqueued))
STUBW <- file.path(OUT, "pilot_worker.R")
writeLines(c("## 파일럿 상설 측정 대역 워커(rf_cell_worker.R 와 같은 인자) — 합성 산출 폴더를 쓴다",
             "a <- commandArgs(trailingOnly = TRUE); spec <- a[1]; code <- a[3]; out <- a[4]",
             sprintf("M <- '%s'; suppressMessages(source(file.path(M, '04_Research/programs/_lib/round_core/v2/load.R')))", M),
             "suppressPackageStartupMessages(library(data.table))",
             "BM <- as.data.table(arrow::read_parquet(file.path(M, '.cache/benchmark.parquet')))[is.finite(BM_Ret)][, .(Date = as.Date(Date), r = BM_Ret)]",
             "BM[, ym := format(Date, '%Y-%m')]; BM <- BM[, .(date = max(Date), bm = prod(1 + r) - 1, nd = .N), by = ym][order(ym)][ym >= '2000-01' & nd >= 15L & ym < format(Sys.Date(), '%Y-%m')]",
             "P <- list(X_E2 = c(0.000, 0.90, 0.030), X_E3 = c(0.010, 0.70, 0.022), Y_E2 = c(0.008, 0.80, 0.022)); k <- sub('^P1S90_', '', code); p <- P[[k]]",
             "set.seed(100L + match(k, names(P))); r <- p[1] + p[2] * BM$bm + rnorm(nrow(BM), 0, p[3])",
             "d <- file.path(M, 'stage_artifacts/replication/pilot_standing', code); dir.create(d, recursive = TRUE, showWarnings = FALSE)",
             "fwrite(data.table(date = BM$date, ret_net = r, risk_free_ret = 0, leverage = 1, frequency = 'monthly'), file.path(d, '03_period_returns.csv'))",
             "fwrite(data.table(date = BM$date, benchmark_ret = BM$bm, benchmark_id = 'KOSPI200'), file.path(d, '05_benchmark_returns.csv'))",
             "fwrite(data.table(date = BM$date, nav_net = cumprod(1 + r)), file.path(d, '02_nav.csv'))",
             "fwrite(data.table(run_id = 't', date = BM$date, ticker = 'A005930', target_weight = 1), file.path(d, '04_holdings.csv'))",
             "ep <- rc_ref_value('02_Infrastructure/worktask/constraint_defaults.json::execution.exec_price', M)",
             "rc_json_write(list(run_id = format(Sys.time(), 'RP_%Y%m%d_%H%M%S_pilot'), essence_grade = 'C', grade_scheme = 'pilot_standing',",
             "                   measurement_regime = list(exec_price = ep, exec_price_basis = 'argument', cost_model_version = 'pilot_synthetic')), file.path(d, 'authoritative_remeasure.json'))",
             "rc_json_write(list(n = 1L, code = code, ok = TRUE, artifacts = d), out)"), STUBW)
pend <- rc_standing_pending(RD, M)
ms <- lapply(pend, function(cd) tryCatch(rc_standing_measure_item(RD, cd, M, worker = STUBW, fingerprint = FP, freshness = FRESH, gpu = rc_gpu_guard), error = function(e) list(status = conditionMessage(e))))
chk("S4", "측정 — 대기 3칸 모두 원장 measure ok · 지문 동일(GPU 관문 = 실제 판별 · cpu 엔진)", length(ms) == 3L && all(vapply(ms, function(m) isTRUE(m$ok) && isTRUE(m$fp_same), TRUE)),
    vapply(ms, function(m) paste(m$status %||% m$ok), ""))
eval_syn <- function(root, round_dir, cell, env, tau) {   # 칸 평가 대역 — RAWDATA 패킷(dp_build · mc_card · 7GB 급 적재) 대신 실제 보는 창 행동 카드(rc_p4_visible_metrics)
  r <- rc_json_read(file.path(round_dir, "results", paste0(cell$code, ".json"))); vm <- rc_p4_visible_metrics(r$artifacts, root = root, tau = tau)
  ev <- list(code = cell$code, engine = cell$engine %||% NA, status = "evaluated", artifacts = r$artifacts, axis = list(ok = TRUE, note = "pilot 대역"),
             visible = list(window = vm$window, uc = vm$uc_vis, cagr = vm$cagr_vis, calmar = vm$calmar_vis, port_t = vm$port_t_vis, dd_capture_median = vm$dd_capture_median_vis,
                            n_crisis = vm$n_crisis_vis), test = list(uc = NA), full = list(grade = NA), pilot_eval = "rc_p4_visible_metrics 대역")
  od <- file.path(round_dir, "results", cell$code); dir.create(od, recursive = TRUE, showWarnings = FALSE); rc_json_write(ev, file.path(od, "eval.json")); ev }
J <- tryCatch(rc_standing_judge(RD, M, eval_fun = eval_syn), error = function(e) e)
Q <- tryCatch(rc_standing_qualified("P1_RETURN", root = M, sa_root = M)[round_id == RID], error = function(e) data.table())
chk("S5", "판정(등록 규칙 실제 적용 · t(α) = 계약) — 통과 = X_E3(처치) · Y_E2(표준) · 미달 = X_E2(맨 엔진)",
    !inherits(J, "error") && setequal(Q$code, c("P1S90_X_E3", "P1S90_Y_E2")), if (inherits(J, "error")) conditionMessage(J) else paste(Q$code, Q$construction))
chk("S6", "구성 판독 — X_E3 = treatment(factors · weighting · rebalance) · Y_E2 = standard",
    identical(Q[code == "P1S90_X_E3"]$construction, "treatment") && identical(Q[code == "P1S90_Y_E2"]$construction, "standard"), paste(Q$code, Q$construction, Q$treatment_axes))
rp <- tryCatch(rc_standing_report(RD, send = FALSE, root = M), error = function(e) e)
chk("S7", "보고(건식) — 통과 push 2 · 일 요약 1(미달) · 발송 안 함", !inherits(rp, "error") && length(rp$pass) == 2L && !isTRUE(rp$sent),
    if (inherits(rp, "error")) conditionMessage(rp) else sprintf("pass %d · fail %d · sent %s", length(rp$pass), length(rp$fail), rp$sent))

## ═══ B. 기저 풀 — 알려진 답 2건 · v1 = 틀린 답(자식 프로세스 · 같은 거울 루트) ══════════════════════════════
cat("\nB 기저 풀\n")
POOL <- rc_p4_base_pool(M)
r_ <- function(P, k) P[key == k]
kXT <- paste0("standing:", RID, ":P1S90_X_E3")
chk("B1", "사례 1(처치 칸만 통과) — 맨 엔진 행 engine:PILOT_X 자격 없음 · 처치 칸 행(standing:…:X_E3 · treatment)은 따로 자격",
    identical(r_(POOL, "engine:PILOT_X")$eligible, FALSE) && grepl("not_qualified", r_(POOL, "engine:PILOT_X")$reason) && isTRUE(r_(POOL, kXT)$eligible) &&
      identical(r_(POOL, kXT)$construction, "treatment"), paste(POOL[grepl("PILOT|P1S90", key)]$key, POOL[grepl("PILOT|P1S90", key)]$eligible))
chk("B2", "사례 2(등급 경로) — engine:PILOT_Z(권위 등급 B · 상설 통과 없음) 자격 없음 · 등급은 참고 열", identical(r_(POOL, "engine:PILOT_Z")$eligible, FALSE) &&
      identical(r_(POOL, "engine:PILOT_Z")$grade, "B") && grepl("not_qualified", r_(POOL, "engine:PILOT_Z")$reason))
chk("B3", "대조 — engine:PILOT_Y(표준 칸 Y_E2 통과) = 같은 엔진 행에 합쳐 자격", isTRUE(r_(POOL, "engine:PILOT_Y")$eligible) && identical(r_(POOL, "engine:PILOT_Y")$standing_code, "P1S90_Y_E2"))
cf <- file.path(OUT, "pool_v1.R"); of <- file.path(OUT, "pool_v1.rds")
writeLines(c(sprintf("setwd('%s'); suppressMessages(source('04_Research/programs/_lib/round_core/v1/load.R')); stopifnot(identical(rc_root(), '%s'), identical(RC_VERSION, 'v1'))", M, M),
             sprintf("saveRDS(rc_p4_base_pool('%s'), '%s')", M, of)), cf)
invisible(suppressWarnings(system2("Rscript", shQuote(cf), stdout = TRUE, stderr = TRUE))); P1 <- tryCatch(readRDS(of), error = function(e) data.table(key = character(0)))
chk("B4", "v1 = 틀린 답(정답 대조) — 같은 거울 원장에서 engine:PILOT_X(처치 칸 합침) · engine:PILOT_Z(등급 경로)가 자격 TRUE",
    isTRUE(r_(P1, "engine:PILOT_X")$eligible) && identical(r_(P1, "engine:PILOT_X")$standing_code, "P1S90_X_E3") && isTRUE(r_(P1, "engine:PILOT_Z")$eligible),
    paste(P1[grepl("PILOT", key)]$key, P1[grepl("PILOT", key)]$eligible, P1[grepl("PILOT", key)]$standing_code))
BX <- file.path(OUT, "base_XE3.json"); e_bx <- err_of(rc_p4_base_cell_spec(kXT, POOL, M, BX))
chk("B5", "처치 칸 행의 기저 칸 사양 = 통과 칸 사양 그대로(처치 축 3 · same_construction TRUE)", !nzchar(e_bx) && length(rc_json_read(BX)$factors) == 1L &&
      isTRUE(rc_json_read(BX)$p4$same_construction), e_bx)
fwrite(POOL[, .(key, construction, standing_code, grade, eligible, reason)], file.path(OUT, "pool_v2.csv"))

## ═══ C. 사슬(v2) — 등록 → 기준 칸 → 걸음 → 닫기(실제 재채점 · 실제 A 자격 관문) ═══════════════════════════════
cat("\nC 사슬\n")
CID <- "P4C90_pilot"; CD <- file.path(M, "04_Research/programs/P4_ASSEMBLY", CID)
RULES <- list(
  list(id = "improve", type = "threshold", label = "보는 창 S 개선", metric = "dS_vis", op = ">=",
       value_ref = "04_Research/programs/P3_CONSTRUCTION/P3R03_advanced_construction/prereg.json::final_selection_rule.tie_eps", source = "P3R03 tie_eps 승계(파일럿)"),
  list(id = "uc_floor", type = "threshold", label = "상승 포착 하한", metric = "uc_vis", op = ">=", value_ref = "06_Registry/behavior_card.json::uc_floor", source = "헌장 §2"),
  list(id = "crisis_no_worse", type = "threshold", label = "위기 하락 포착 비악화", metric = "d_dd_capture_median_vis", op = "<=", value = 0, basis = "정의 — 비악화 = 부모 이하", source = "정의"),
  list(id = "bull_segments", type = "threshold", label = "강세 구간별 참여(N1)", metric = "uc_seg_ok_share_vis", op = ">", value_ref = "06_Registry/behavior_card.json::majority_share",
       source = "헌장 §5 빈칸 4 · 7 · 24"),
  list(id = "deep_crisis", type = "threshold", label = "깊은 위기 과반 비악화(N2)", metric = "deep_crisis_nonworse_share_vis", op = ">", value_ref = "06_Registry/behavior_card.json::majority_share",
       source = "헌장 §5 빈칸 2 · 23"))
BUD <- list(max_steps = 4L, max_steps_source = "파일럿(걸음 4 · 시험 규모)", noise_k = 2L, noise_k_source = "체계 §4 R7(연속 2)")
for (tr in list(c("P1", "philosophy"), c("T1", "judgment"), c("P2", "philosophy"), c("T2", "judgment")))
  add_review(sprintf("R-PILOT-%s-%s", tr[1], CID), tr[2], tr[1], CID, sprintf("%s%s20261111_1900_%s_%s.md", SFP, if (tr[2] == "philosophy") "philosophy/" else "", tr[1], rc_round_tag(CID)))
e_new <- err_of(rc_p4_chain_new(CD, CID, "engine:PILOT_Y", POOL, adoption_rules = RULES, budget = BUD, purpose = "파일럿 — 사다리 루프 종단(v2)", root = M))
csp <- tryCatch(rc_json_read(rc_p4_spec_path(CD)), error = function(e) list())
chk("C1", "사슬 판 만들기(기저 = 상설 표준 칸 Y · 채택 규칙 판 v2 · core_version v2)", !nzchar(e_new) && identical(csp$core_version, "v2") && identical(csp$rules_version, "p4_rules_v2"), e_new)
e_reg3 <- err_of(rc_p4_chain_register(CD, POOL, M, p1 = paste0("R-PILOT-P1-", CID), t1 = paste0("R-PILOT-T1-", CID), ledger = LED, review_root = RVR))
chk("C2", "사슬 판 등록(감독 영수증 P1 · T1 · 원장 첫 줄)", !nzchar(e_reg3) && identical(rc_p4_steps_read(CD)[[1]]$event, "chain_registered"), e_reg3)
e_nr <- err_of(rc_p4_chain_register(file.path(M, "nochain"), POOL, M))
bm0 <- rc_p4_base_measure(CD, M, runner = runner_syn, barrier = FREE, fingerprint = FP, vintage = VINT, freshness = FRESH, gpu = GPUOK)
chk("C3", "기준 칸 측정(k = 0 · 가짜 측정기 · 실제 판 표식 · 보는 창 지표 = 실제 행동 카드)", identical(bm0$status, "measured"), paste(bm0$status, bm0$reason %||% "", bm0$why %||% ""))
cells <- file.path(CD, "cells"); dir.create(cells, showWarnings = FALSE)
mk_cell <- function(k, f) { s <- rc_json_read(file.path(CD, "base_cell_spec.json")); s$code <- sprintf("%s_k%d", CID, k); s <- f(s); p <- file.path(cells, sprintf("k%d.json", k)); rc_json_write(s, p); p }
H1 <- "엔트로피 비중이 상위 신호 집중을 풀어 깊은 위기의 한 종목 손실을 줄인다"; M1 <- "등가중 대신 신호 분포의 엔트로피 비중으로 신호 강도를 비중에 반영한다"
o1 <- err_of(rc_p4_step_open(CD, 1L, H1, M1, "weighting", mk_cell(1L, function(s) { s$weighting <- list(kind = "catalog", catalog_id = "lean:entropy", label = "entropy"); s }),
                             0L, "g1", root = M, pool = POOL))
m1 <- rc_p4_step_measure(CD, 1L, M, runner = runner_syn, barrier = FREE, fingerprint = FP, vintage = VINT, freshness = FRESH, gpu = GPUOK)
d1 <- tryCatch(rc_p4_step_decide(CD, 1L, root = M), error = function(e) e)
chk("C4", "걸음 1(비중 블록) — 열기 · 측정 · 판정 = 채택(실제 보는 창 지표 · 등록 규칙)", !nzchar(o1) && identical(m1$status, "measured") && !inherits(d1, "error") && identical(d1$decision, "accept"),
    c(o1, m1$status, if (inherits(d1, "error")) conditionMessage(d1) else paste(d1$decision, paste(d1$failed %||% "", collapse = ","))))
H2 <- "순위 완충이 회전을 줄여 비용을 아낀다"; M2 <- "보유 종목은 순위 2배 안이면 유지해 교체 거래를 줄인다"
o2 <- err_of(rc_p4_step_open(CD, 2L, H2, M2, "rebalance", mk_cell(2L, function(s) { s$weighting <- list(kind = "catalog", catalog_id = "lean:entropy", label = "entropy")
                                                                                       s$rebalance <- list(kind = "rank_buffer", mult = 2, label = "buffer_2x"); s }), 1L, "g1", root = M, pool = POOL))
## K 막힘 경로(걸음 2 측정 전) — 원장 무기록 · 상태만 돌려준다
n0 <- rc_p4_steps_verify(CD)$n
kb <- rc_p4_step_measure(CD, 2L, M, runner = runner_syn, barrier = function(root) list(state = "held", reason = "pilot 주입(writer 잠금)", lock = "writer", blocking = TRUE),
                         fingerprint = FP, vintage = VINT, freshness = FRESH, gpu = GPUOK)
ks <- rc_p4_step_measure(CD, 2L, M, runner = runner_syn, barrier = FREE, fingerprint = FP, vintage = VINT, gpu = GPUOK,
                         freshness = function(root) list(ok = FALSE, state = "stale", reason = "pilot 주입(rawdata 낡음)"))
kv <- rc_p4_step_measure(CD, 2L, M, runner = runner_syn, barrier = FREE, fingerprint = FP, freshness = FRESH, gpu = GPUOK,
                         vintage = function(root) { v <- VINT(root); v$n_in_progress <- 1L; v })
kg <- rc_p4_step_measure(CD, 2L, M, runner = runner_syn, barrier = FREE, fingerprint = FP, vintage = VINT, freshness = FRESH,
                         gpu = function(engine_path, holder, purpose = holder, root = rc_root()) list(ok = FALSE, state = "lane_busy", reason = "pilot 주입(레인 측정 1)", release = function() NULL))
chk("K1", "막힘 4종(배리어 잠김 · 데이터 낡음 · 판 표식 진행 중 · GPU 대기) = 재지 않는다 · 원장 무기록 · 러너 호출 0",
    !nzchar(o2) && identical(kb$status, "barrier_held") && identical(ks$status, "data_stale") && identical(kv$status, "vintage_in_progress") && identical(kg$status, "gpu_wait") &&
      identical(rc_p4_steps_verify(CD)$n, n0), paste(o2, kb$status, ks$status, kv$status, kg$status, rc_p4_steps_verify(CD)$n, n0))
m2 <- rc_p4_step_measure(CD, 2L, M, runner = runner_syn, barrier = FREE, fingerprint = FP, vintage = VINT, freshness = FRESH, gpu = GPUOK)
d2 <- tryCatch(rc_p4_step_decide(CD, 2L, root = M), error = function(e) e)
chk("C5", "막힘이 풀리면 잇는다 — 걸음 2(리밸 블록) 측정 · 판정 = 기각(개선 없음)", identical(m2$status, "measured") && !inherits(d2, "error") && identical(d2$decision, "reject"),
    c(m2$status, if (inherits(d2, "error")) conditionMessage(d2) else paste(d2$decision, paste(d2$failed %||% "", collapse = ","))))
## K 측정 실패 2회 → 포기 → 사슬은 멈추지 않는다
o3 <- err_of(rc_p4_step_open(CD, 3L, "규모 상한이 집중을 줄인다", "핵심 위성 상한으로 종목 수를 고정한다", "construction",
                             mk_cell(3L, function(s) { s$weighting <- list(kind = "catalog", catalog_id = "lean:entropy", label = "entropy"); s$cap_core <- list(k = 5L, satellite = "floor"); s }),
                             1L, "g1", root = M, pool = POOL))
RUN$fail_k <- "k3"
f1 <- rc_p4_step_measure(CD, 3L, M, runner = runner_syn, barrier = FREE, fingerprint = FP, vintage = VINT, freshness = FRESH, gpu = GPUOK)
f2 <- rc_p4_step_measure(CD, 3L, M, runner = runner_syn, barrier = FREE, fingerprint = FP, vintage = VINT, freshness = FRESH, gpu = GPUOK)
ab <- err_of(rc_p4_step_abandon(CD, 3L, "측정 실패 2회(파일럿 주입) — 사슬이 멈추지 않게 기각으로 닫는다", root = M)); RUN$fail_k <- character(0)
chk("K2", "측정 실패 2회 → step_measure_failed 2줄 → 포기(기각 · 산출 없음) — 사슬 계속", !nzchar(o3) && identical(f1$status, "failed") && identical(f2$status, "failed") && !nzchar(ab) &&
      length(Filter(function(r) identical(r$event, "step_measure_failed"), rc_p4_steps_read(CD))) == 2L, c(o3, f1$status, f2$status, ab))
st <- rc_p4_status(CD, M)
## 닫기 — 실제 선택 현실 점검 재채점(시행 집합 = 기준 칸 + 판정 걸음) + 실제 A 자격 관문(round_candidate_gate.R → rf_a_eligibility)
MOD0 <- if (file.exists(file.path(M, "06_Registry/module_catalog.json"))) md5(file.path(M, "06_Registry/module_catalog.json")) else "absent"
cl <- tryCatch(rc_p4_close(CD, note = "파일럿 — 합성 양성 1건(걸음 1)의 A 경로 소방 훈련", probes = c("파일럿 탐침 1(합성)", "파일럿 탐침 2(합성)"),
                           lessons = "파일럿 교훈(합성)", root = M, regrade = TRUE, regrade_write = TRUE,
                           philosophy_p2 = paste0("R-PILOT-P2-", CID), superfan_t2 = paste0("R-PILOT-T2-", CID), ledger = LED, review_root = RVR), error = function(e) e)
fin <- tryCatch(rc_json_read(file.path(CD, "finalize.json")), error = function(e) list())   # 사람 쪽 마감 기록(사슬 폴더 · 원장엔 상태 · md5 만)
cand <- .rcs_str(fin$candidate)
saveRDS(list(close = if (inherits(cl, "error")) conditionMessage(cl) else cl, fin = fin), file.path(OUT, "close.rds"))
recs <- rc_p4_steps_read(CD)
chk("C6", "닫기 — chain_closed · 최종 후보 = 걸음 1(마지막 채택) 산출 · 시행 3(기준 칸 + 판정 걸음 2 · 포기 1 제외)",
    !inherits(cl, "error") && identical(recs[[length(recs)]]$event, "chain_closed") && identical(cl$final$k, 1L) && identical(cand, cl$final$artifacts) &&
      identical(as.integer(cl$finalize$n_trials), 3L), if (inherits(cl, "error")) conditionMessage(cl) else paste(cl$finalize$status, cand, cl$finalize$n_trials))
CA <- if (is.na(cand)) NA_character_ else rc_abs(cand, M)
au1 <- tryCatch(rc_json_read(file.path(CA, "authoritative_remeasure.json")), error = function(e) list())
au0 <- tryCatch(rc_json_read(file.path(CA, "authoritative_remeasure.pre_selection_regrade.json")), error = function(e) list())
src <- tryCatch(rc_json_read(file.path(CA, "selection_reality_check.json")), error = function(e) list())
chk("C7", "실제 선택 현실 점검 재채점(selection_regrade.R · 시행 집합 3) — 측정 시점 A → 재채점 A · 관문 = reality_check · 조정 p ≤ alpha · 원본 사본 남김",
    identical(au0$essence_grade, "A") && identical(au1$essence_grade, "A") && identical(au1$selection_gate$mode, "reality_check") && isTRUE(au1$selection_gate$ok) &&
      isTRUE(src$pass) && identical(as.integer(src$n_trials), 3L) && isTRUE(as.numeric(src$p_adj[[basename(CA)]]) <= as.numeric(src$alpha)),
    paste(au0$essence_grade, "→", au1$essence_grade, au1$selection_gate$reason %||% ""), ev = list(selection_gate = au1$selection_gate, p_adj = src$p_adj, S = au1$grade_v3$S))
jr <- tryCatch(rc_json_read(file.path(CA, "judge_request.eligible.json")), error = function(e) list())
chk("C8", "실제 A 자격 관문(round_candidate_gate.R → rf_a_eligibility) = 발행 · judge_request.eligible.json(judge_request_v2 · pending · 보류 코드 0) · 보류 파일 없음 · Judge 스폰 없음(건식)",
    identical(fin$candidate_gate$action, "publish") && isTRUE(fin$candidate_gate$eligible) && !length(fin$candidate_gate$codes) &&
      identical(jr$schema, "judge_request_v2") && identical(jr$status, "pending") && isTRUE(jr$a_eligibility$eligible) && !length(jr$a_eligibility$codes) &&
      identical(jr$a_eligibility$adapter, "round_candidate_gate.R::rcg_route") && !file.exists(file.path(CA, "judge_request.held.json")),
    paste(fin$candidate_gate$action, paste(unlist(fin$candidate_gate$codes), collapse = ",")), ev = list(judge_request = file.path(cand, "judge_request.eligible.json")))
MOD1 <- if (file.exists(file.path(M, "06_Registry/module_catalog.json"))) md5(file.path(M, "06_Registry/module_catalog.json")) else "absent"
chk("C9", "최종 후보 1개만 모듈 풀 등재(정본 등재기 · 거울 루트 사본 module_catalog 만 바뀜 — 실제 원장은 실행기가 md5 대조)",
    identical(fin$module_pool$status, "registered") && !identical(MOD0, MOD1), paste(fin$module_pool$status, fin$module_pool$why %||% ""))
OC <- tryCatch(rc_outcomes_md(rc_outcomes_path(M), "P4_ASSEMBLY"), error = function(e) paste("오류:", conditionMessage(e)))
chk("C10", "결과 원장(거울 06_Registry/round_outcomes.jsonl) — 사슬 닫기 1줄 · 다음 탐침 2 · 설계 입력 표에 보인다",
    file.exists(rc_outcomes_path(M)) && any(grepl(CID, OC, fixed = TRUE)), substr(paste(OC, collapse = " "), 1, 200))
## K 핀 변경 — 등록된 상설 판의 판정 경로 핀 파일이 바뀌면 그 판은 측정 · 판정을 멈춘다(R2 — 새 판 필요) · 되돌리면 잇는다
PINF <- file.path(M, "06_Registry/grade_v3.json"); pin0 <- readBin(PINF, "raw", file.info(PINF)$size)
writeBin(c(pin0, charToRaw("\n")), PINF)
kp <- err_of(rc_standing_judge(RD, M, eval_fun = eval_syn)); kp_m <- err_of(rc_standing_context(RD, M))
writeBin(pin0, PINF); kp2 <- err_of(rc_standing_context(RD, M))
chk("K3", "핀 변경(상설 판 판정 경로 파일 1바이트) = 판정 · 측정 맥락 거부(판정 경로 핀 불일치 — 새 판) · 되돌리면 정상",
    grepl("핀 불일치", kp) && grepl("핀 불일치", kp_m) && !nzchar(kp2), c(substr(kp, 1, 80), substr(kp2, 1, 80)))
## 무인 틱이 이을 열린 사슬 1개(기준 칸 측정 전) — 실행기 R6 드라이런이 계획 줄(measure_base)을 내야 한다
CID2 <- "P4C91_pilot_open"; CD2 <- file.path(M, "04_Research/programs/P4_ASSEMBLY", CID2)
for (tr in list(c("P1", "philosophy"), c("T1", "judgment")))
  add_review(sprintf("R-PILOT-%s-%s", tr[1], CID2), tr[2], tr[1], CID2, sprintf("%s%s20261111_1901_%s_%s.md", SFP, if (tr[2] == "philosophy") "philosophy/" else "", tr[1], rc_round_tag(CID2)))
POOL2 <- rc_p4_base_pool(M)
e_c2 <- err_of({ rc_p4_chain_new(CD2, CID2, kXT, POOL2, adoption_rules = RULES, budget = BUD, purpose = "파일럿 — 무인 틱이 이을 열린 사슬(처치 칸 기저)", root = M)
                 rc_p4_chain_register(CD2, POOL2, M, p1 = paste0("R-PILOT-P1-", CID2), t1 = paste0("R-PILOT-T1-", CID2), ledger = LED, review_root = RVR) })
bc2 <- tryCatch(rc_json_read(file.path(CD2, "base_cell_spec.json")), error = function(e) list())
chk("C11", "처치 칸 기저 사슬(standing:…:X_E3) 등록 — 기저 칸 사양 = 통과 칸 처치 그대로 · 열린 채 둔다(실행기 R6 사슬 틱 드라이런 대상)",
    !nzchar(e_c2) && identical(rc_p4_steps_read(CD2)[[1]]$event, "chain_registered") && length(bc2$factors) == 1L && identical(bc2$p4$construction, "treatment"), e_c2)

## ═══ 끝 — 단계 기록(pilot_out/pilot_steps.json · 보고 근거) ═══════════════════════════════════════════
rc_json_write(STEPS, file.path(OUT, "pilot_steps.json"))
cat(sprintf("\n== pilot_v2: %d ok · %d FAIL ==\n", PASS, FAIL))
quit(status = if (FAIL) 1L else 0L)
