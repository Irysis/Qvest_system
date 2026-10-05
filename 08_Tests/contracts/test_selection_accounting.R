# test_selection_accounting.R — selection_accounting.R(P1-03 · 이 판 = sa_subwindow 만) 양방향 검증 (합성 · tempdir 만 씀 · 운영 무접촉)
#
# 재는 것
#   C  설정 fail-closed — 부재 · 절단일 비날짜 · 근거(source) 부재 · 미지 cut id · cut 과 end 동시
#   S1 항등 — end ≥ 산출 마지막 날이면 절단 없음 · 재구성 essence·grade = 저장 authoritative_remeasure.json(JSON 왕복 identical)
#   S2 절단 = 절단된 시뮬레이션 — 표를 date ≤ end 로 자른 sa 값이 '데이터 끝이 end 인 시뮬레이션'(sim 을 잘라 정본 build_bt_result →
#      audit → essence)과 identical (월말 거래일 · 월중 거래일 · 비거래일 end 3가지 · 독립 경로)
#   S3 미래 둔감 · 이빨 — end 뒤 수익을 크게 바꿔도 절단판 불변(verify_identity=FALSE) / end 앞을 바꾸면 달라진다 /
#      저장 bt 를 바꾸면(항등 깨짐) 항등 자기검사가 멈춘다
#   S4 산출 형식 — 최상위 measurement_regime(exec_price·key = 권위 산출) · window(cut_id·end_source) · 라벨 · 설정 절단일 = config
#   S5 입력 판 해석 — remeasure_<prefer>_* 형제 우선 · 형제 둘이면 멈춤 · 파일 부재 멈춤
#   W  쓰기 — out_dir 없으면 멈춤 · 명시 경로 JSON
#   RT 소비자 왕복(2026-09-26) — 판정 입력 검사 정본 rf_prereg.R::.rfp_check_measurement 가 sa_write 산출을 합성 루트(tempdir)에서
#      받는가: 등재·고정값(end_from_config = 1) · 양성(설정 cut id 절단판 → source.fields essence/calmar·oos_retention 재도출 = 계약 값) ·
#      거부(end 인자 산출 = 같은 수치라도 · 규약 불일치). ★소비자 부재 = FAIL(P2-01 배포 뒤 INTEG — 조용한 생략 없음)
#   M  돌연변이 — (M1) date < end(하루 누락) → S2 red · (M2) nav 미절단 → S2 red · (M3) 채점 인자 n_trials 누락 → S1 항등 멈춤 ·
#      (M4) 항등 자기검사 제거 → S3c red(변조를 못 잡는다) · (M5) end_from_config 를 늘 1 로 → RT4 red(end 인자 산출 통과) ·
#      (M6) 소비자 설정에서 end_from_config 고정 제거 → RT4 red(고정이 일을 한다)
#   R  루트 읽기 전용 — contracts·06_Registry 최상위 지문 불변
# 실행: Rscript 08_Tests/contracts/test_selection_accounting.R (빈 Renviron 권장)
suppressPackageStartupMessages({ library(data.table); library(jsonlite); library(xts); library(PerformanceAnalytics) })

.self <- tryCatch({
  a <- commandArgs(trailingOnly = FALSE); f <- sub("^--file=", "", a[grepl("^--file=", a)])
  if (length(f)) dirname(f[1]) else "."
}, error = function(e) ".")
ROOT <- normalizePath(file.path(.self, "..", ".."), winslash = "/", mustWork = FALSE)
CONTRACT <- file.path(ROOT, "02_Infrastructure/contracts/selection_accounting.R")
CFG_SRC  <- file.path(ROOT, "02_Infrastructure/contracts/selection_accounting_config.json")
if (!file.exists(CONTRACT)) stop("검사 앵커 실패 — 계약 부재: ", CONTRACT)

pass <- 0L; fail <- 0L
chk <- function(name, ok, detail = "") {
  if (isTRUE(ok)) { pass <<- pass + 1L; cat(sprintf("  [PASS] %s %s\n", name, detail)) }
  else { fail <<- fail + 1L; cat(sprintf("  [FAIL] %s %s\n", name, detail)) }
}
expect_stop <- function(name, expr, pat = NULL) {
  e <- tryCatch({ force(expr); NULL }, error = function(e) conditionMessage(e))
  chk(name, !is.null(e) && (is.null(pat) || grepl(pat, e)), if (is.null(e)) "(멈추지 않음)" else sprintf("(%s)", substr(e, 1, 100)))
}
TMP <- normalizePath(file.path(tempdir(), paste0("sa_test_", Sys.getpid())), winslash = "/", mustWork = FALSE)
dir.create(TMP, recursive = TRUE, showWarnings = FALSE)
inside <- function(p, q) startsWith(tolower(normalizePath(p, winslash = "/", mustWork = FALSE)), tolower(paste0(normalizePath(q, winslash = "/", mustWork = FALSE), "/")))
if (inside(TMP, ROOT)) stop("tempdir 가 루트 안이다 — 쓰기 위험(중단): ", TMP)
ROOT_FP <- function() { fs <- c(list.files(file.path(ROOT, "02_Infrastructure/contracts"), full.names = TRUE), list.files(file.path(ROOT, "06_Registry"), full.names = TRUE))
  fs <- fs[file.exists(fs) & !dir.exists(fs)]; setNames(unname(tools::md5sum(fs)), fs) }
FP0 <- ROOT_FP()

invisible(capture.output(source(CONTRACT, encoding = "UTF-8")))
CFG <- sa_config(ROOT, CFG_SRC)

# ── 독립 경로(검사 쪽 정본 적재 — 계약의 .SA_DEP 와 별개 환경) ──
IND <- new.env(parent = globalenv())
with_root <- function(expr) {
  old <- c(QM_ROOT = Sys.getenv("QM_ROOT", NA), CLAUDE_PROJECT_DIR = Sys.getenv("CLAUDE_PROJECT_DIR", NA)); owd <- getwd()
  on.exit({ for (k in names(old)) if (is.na(old[[k]])) Sys.unsetenv(k) else do.call(Sys.setenv, setNames(list(old[[k]]), k)); setwd(owd) }, add = TRUE)
  Sys.setenv(QM_ROOT = ROOT, CLAUDE_PROJECT_DIR = ROOT); setwd(ROOT); force(expr)
}
with_root(capture.output(suppressMessages({
  source(file.path(ROOT, "02_Infrastructure/contracts/backtest_result_contract.R"), local = IND, encoding = "UTF-8")
  source(file.path(ROOT, "02_Infrastructure/contracts/audit_bt_result.R"), local = IND, encoding = "UTF-8")
  source(file.path(ROOT, "02_Infrastructure/contracts/essence_score.R"), local = IND, encoding = "UTF-8")
})))
NT <- 50L; ST <- "sweep"
score_sim <- function(sim) with_root({
  bt <- NULL; es <- NULL
  capture.output(bt <- suppressMessages(IND$build_bt_result(sim, list(strategy_name = "SYN", rebalance_frequency = "monthly"), run_id = "SYN_RUN", strategy_id = "SYN",
                                                              transaction_cost_bps = 15, slippage_bps = 0, frequency = "daily", annualization_factor = 252)))
  capture.output(bt <- suppressMessages(IND$audit_bt_result(bt)))
  capture.output(es <- suppressWarnings(suppressMessages(IND$essence_score(bt, n_trials_cumulative = NT, selection_type = ST, sidecar_log = FALSE))))
  list(bt = bt, es = es)
})
# 합성 시뮬레이션(하네스 반환 모양) — 영업일 · 월 첫 영업일 집행 · 보유 5종 · 집행 첫날 비용
mk_sim <- function(seed, from = "2008-01-01", to = "2016-12-31") {
  set.seed(seed)
  d <- seq(as.Date(from), as.Date(to), by = "day"); d <- d[!(format(d, "%u") %in% c("6", "7"))]
  n <- length(d); bm <- rnorm(n, 3e-4, 0.012); g <- 0.9 * bm + rnorm(n, 2.5e-4, 0.006)
  ym <- format(d, "%Y-%m"); ex <- d[!duplicated(ym)]
  net <- g; net[d %in% ex] <- (1 - 0.0015) * (1 + g[d %in% ex]) - 1
  H <- rbindlist(lapply(ex, function(e) data.table(Exec_Date = e, Ticker = sprintf("A%03d", sample.int(30, 5)), Weight = 0.2)))
  list(DAILY_NAV_DT = data.table(Date = d, NAV = cumprod(1 + net), NAV_gross = cumprod(1 + g)),
       strategy_xts = xts(net, d), strategy_gross_xts = xts(g, d), bm_xts = xts(bm, d),
       HOLDINGS_LOG = H, PORTFOLIO_LOG = data.table(Exec_Date = ex), cost_model_version = "synthetic_v1")
}
cut_sim <- function(sim, end) {
  end <- as.Date(end); k <- sim$DAILY_NAV_DT$Date <= end
  list(DAILY_NAV_DT = sim$DAILY_NAV_DT[k], strategy_xts = sim$strategy_xts[index(sim$strategy_xts) <= end],
       strategy_gross_xts = sim$strategy_gross_xts[index(sim$strategy_gross_xts) <= end], bm_xts = sim$bm_xts[index(sim$bm_xts) <= end],
       HOLDINGS_LOG = sim$HOLDINGS_LOG[Exec_Date <= end], PORTFOLIO_LOG = sim$PORTFOLIO_LOG[Exec_Date <= end], cost_model_version = sim$cost_model_version)
}
write_art <- function(dir, sc, key = "close_t1_syn") invisible({
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  saveRDS(sc$bt, file.path(dir, "bt_result.rds"))
  auth <- list(status = "OK", kind = "synthetic_for_test", essence_grade = sc$es$grade, essence = sc$es$essence,
               selection_type = ST, n_trials_cumulative = NT,
               measurement_regime = list(key = key, regime = key, exec_price = "close_t1", cost_model_version = "synthetic_v1",
                                         harness_md5 = "syn", selection_type = ST, n_trials_cumulative = NT))
  jsonlite::write_json(auth, file.path(dir, "authoritative_remeasure.json"), auto_unbox = TRUE, pretty = TRUE, digits = NA, na = "null", null = "null")
  dir
})
rt <- function(x) fromJSON(toJSON(x, auto_unbox = TRUE, digits = NA, na = "null", null = "null"), simplifyVector = TRUE)

SIM <- mk_sim(7); SC <- score_sim(SIM)
ART <- write_art(file.path(TMP, "art1"), SC)
LAST <- max(SIM$DAILY_NAV_DT$Date)

# ═══ C 설정 fail-closed ═══
cat("\n[C] 설정 fail-closed\n")
c0 <- fromJSON(CFG_SRC, simplifyVector = FALSE)
wcfg <- function(x, nm) { p <- file.path(TMP, nm); writeLines(toJSON(x, auto_unbox = TRUE, pretty = TRUE, digits = NA), p); p }
expect_stop("C1 설정 부재 → stop", sa_config(ROOT, file.path(TMP, "none.json")), "설정 부재")
x <- c0; x$subwindow$cuts[[1]]$end <- "not-a-date"; expect_stop("C2 절단일 비날짜 → stop", sa_config(ROOT, wcfg(x, "c2.json")), "날짜")
x <- c0; x$subwindow$cuts[[1]]$source <- ""; expect_stop("C3 절단 근거 부재 → stop", sa_config(ROOT, wcfg(x, "c3.json")), "근거")
expect_stop("C4 미지 cut id → stop", sa_subwindow(ART, cut = "nope", root = ROOT, cfg = CFG), "절단 id")
expect_stop("C5 cut 과 end 동시 → stop", sa_subwindow(ART, cut = names(CFG$subwindow$cuts)[1], end = "2012-01-31", root = ROOT, cfg = CFG), "함께")
chk("C6 설정 기본 절단일 = 2024-12-31(플랜 PR-L1 ③ · D-H)", identical(CFG$subwindow$cuts[[CFG$subwindow$default_cut]]$end, "2024-12-31"))

# ═══ S1 항등 ═══
cat("\n[S1] 항등(절단 없음)\n")
r1 <- sa_subwindow(ART, end = format(LAST + 30), root = ROOT, cfg = CFG)
chk("S1a 절단 없음 판정(end ≥ 마지막 날)", identical(r1$window$truncated, FALSE))
chk("S1b 재구성 essence = 저장 권위 산출(JSON 왕복 identical)", identical(rt(r1$essence), rt(fromJSON(file.path(ART, "authoritative_remeasure.json"), simplifyVector = FALSE)$essence)))
chk("S1c 항등 자기검사 기록 TRUE", isTRUE(r1$identity$essence_identical) && isTRUE(r1$identity$grade_identical))
chk("S1d 계약 경로 = 검사 쪽 독립 채점(sim 전체)", identical(rt(r1$essence), rt(SC$es$essence)))

# ═══ S2 절단 = 절단된 시뮬레이션 ═══
cat("\n[S2] 절단 = 데이터 끝이 end 인 시뮬레이션(독립 경로)\n")
dts <- SIM$DAILY_NAV_DT$Date
e_me <- max(dts[format(dts, "%Y-%m") == "2013-06"])                 # 월말 거래일
e_mid <- dts[format(dts, "%Y-%m") == "2014-03"][10]                  # 월중 거래일
e_nt <- as.Date("2012-09-15"); stopifnot(!(e_nt %in% dts))            # 비거래일(토)
for (e in list(e_me, e_mid, e_nt)) {
  rs <- sa_subwindow(ART, end = format(e), root = ROOT, cfg = CFG, verify_identity = FALSE)
  ind <- score_sim(cut_sim(SIM, e))
  chk(sprintf("S2 end=%s → sa 절단판 = 절단 시뮬레이션 채점(identical)", format(e)), identical(rt(rs$essence), rt(ind$es$essence)) && identical(rs$grade_diagnostic, ind$es$grade),
      sprintf("(calmar %s vs %s · n %d)", format(rs$essence$calmar), format(ind$es$essence$calmar), rs$window$n_days_used))
}
chk("S2d 절단판은 전 구간과 다르다(절단이 실제로 일어남)", !identical(rt(rs$essence), rt(r1$essence)))

# ═══ S3 미래 둔감 · 이빨 · 항등 자기검사 ═══
cat("\n[S3] 미래 둔감 · 이빨 · 항등 자기검사\n")
tamper <- function(dir_src, dir_dst, after = NULL, before = NULL) {
  dir.create(dir_dst, recursive = TRUE, showWarnings = FALSE)
  file.copy(file.path(dir_src, "authoritative_remeasure.json"), dir_dst, overwrite = TRUE)
  b <- readRDS(file.path(dir_src, "bt_result.rds")); pr <- as.data.table(b$period_returns); nv <- as.data.table(b$nav)
  sel <- if (!is.null(after)) pr$date > as.Date(after) else pr$date <= as.Date(before)
  pr[sel, `:=`(ret_net = ret_net - 0.03, ret_gross = ret_gross - 0.03)]
  nv[, nav_net := cumprod(1 + pr$ret_net)]; nv[, drawdown_net := nav_net / cummax(nav_net) - 1]
  b$period_returns <- pr; b$nav <- nv; saveRDS(b, file.path(dir_dst, "bt_result.rds")); dir_dst
}
TA <- tamper(ART, file.path(TMP, "art_after"), after = e_me)
ra <- sa_subwindow(TA, end = format(e_me), root = ROOT, cfg = CFG, verify_identity = FALSE)
r_me <- sa_subwindow(ART, end = format(e_me), root = ROOT, cfg = CFG, verify_identity = FALSE)
chk("S3a end 뒤 수익 변조 → 절단판 불변(미래 둔감)", identical(rt(ra$essence), rt(r_me$essence)))
TB <- tamper(ART, file.path(TMP, "art_before"), before = e_me)
rb <- sa_subwindow(TB, end = format(e_me), root = ROOT, cfg = CFG, verify_identity = FALSE)
chk("S3b end 앞 수익 변조 → 절단판이 달라진다(이빨)", !identical(rt(rb$essence), rt(r_me$essence)))
expect_stop("S3c 저장 bt 변조(권위 산출과 불일치) → 항등 자기검사가 멈춘다", sa_subwindow(TA, end = format(e_me), root = ROOT, cfg = CFG), "항등 자기검사 실패")

# ═══ S4 산출 형식 ═══
cat("\n[S4] 산출 형식\n")
chk("S4a 최상위 measurement_regime.exec_price·key = 권위 산출", identical(r1$measurement_regime$exec_price, "close_t1") && identical(r1$measurement_regime$key, "close_t1_syn"))
chk("S4b 채점 인자 = 권위 산출(n_trials·selection_type)", identical(r1$measurement_regime$n_trials_cumulative, NT) && identical(r1$measurement_regime$selection_type, ST))
chk("S4c end 인자 = end_source 'argument' · cut_id NA", identical(r1$window$end_source, "argument") && is.na(r1$window$cut_id))
chk("S4d 라벨 = 진단 — 등급 대체 아님", identical(r1$label, "진단 — 등급 대체 아님") && identical(r1$contract, "sa_subwindow"))
cz <- sa_subwindow(ART, root = ROOT, cfg = CFG)     # 기본 cut(2024-12-31) — 합성 끝(2016) 뒤라 절단 없음 = 항등
chk("S4e 기본 cut = 설정 id · end_source config", identical(cz$window$cut_id, CFG$subwindow$default_cut) && startsWith(cz$window$end_source, "config:") &&
      identical(cz$window$end, CFG$subwindow$cuts[[CFG$subwindow$default_cut]]$end) && identical(cz$window$truncated, FALSE))

# ═══ S5 입력 판 해석 ═══
cat("\n[S5] 입력 판 해석\n")
P5 <- file.path(TMP, "art_parent"); dir.create(P5, showWarnings = FALSE)
write_art(P5, score_sim(cut_sim(SIM, e_mid)), key = "close_d_legacy_old")      # 부모 = 다른 판
write_art(file.path(P5, "remeasure_close_t1_abc12345"), SC)                    # 형제 = 권위 재측정 판
r5 <- sa_subwindow(P5, end = format(LAST + 1), root = ROOT, cfg = CFG)
chk("S5a remeasure_close_t1_* 형제 우선", grepl("^sibling:remeasure_close_t1_", r5$input$basis) && identical(rt(r5$essence), rt(SC$es$essence)))
write_art(file.path(P5, "remeasure_close_t1_def67890"), SC)
expect_stop("S5b 형제 둘 → 멈춤(regime_key 로 지정)", sa_subwindow(P5, end = format(LAST + 1), root = ROOT, cfg = CFG), "여럿")
r5c <- sa_subwindow(P5, end = format(LAST + 1), root = ROOT, cfg = CFG, regime_key = "close_t1_def67890")
chk("S5c regime_key 로 지정하면 그 판", identical(r5c$input$basis, "sibling:remeasure_close_t1_def67890"))
E5 <- file.path(TMP, "art_empty"); dir.create(E5, showWarnings = FALSE)
expect_stop("S5d 입력 파일 부재 → 멈춤", sa_subwindow(E5, end = "2012-01-31", root = ROOT, cfg = CFG), "입력 부재")

# ═══ W 쓰기 ═══
cat("\n[W] 쓰기\n")
expect_stop("W1 out_dir 없으면 멈춤", sa_write(r1), "out_dir")
wp <- sa_write(rs, file.path(TMP, "out"))
wj <- fromJSON(wp, simplifyVector = FALSE)
chk("W2 JSON 최상위 measurement_regime.exec_price · essence.calmar · window.end", identical(wj$measurement_regime$exec_price, "close_t1") &&
      is.numeric(wj$essence$calmar) && identical(wj$window$end, format(e_nt)))

# ═══ RT 소비자 왕복 — rf_prereg.R 판정 입력 검사(.rfp_check_measurement)가 이 계약 산출을 받는가 ═══
cat("\n[RT] 소비자 왕복(rf_prereg 판정 입력 검사 정본)\n")
PRL <- file.path(ROOT, "02_Infrastructure/reinforcement/rf_prereg.R"); PRC <- file.path(ROOT, "06_Registry/prereg/prereg_config.json")
rt_ok <- file.exists(PRL) && file.exists(PRC)
chk("RT0 소비자(rf_prereg.R · prereg_config.json) 존재 — INTEG 는 P2-01 뒤", rt_ok, if (rt_ok) "" else "(부재 — 소비 계약을 잴 수 없다)")
RTX <- NULL
if (rt_ok) {
  RR <- file.path(TMP, "rt_root")
  for (d in c("02_Infrastructure/contracts", "06_Registry/prereg", "stage_artifacts/prereg/PR-RT")) dir.create(file.path(RR, d), recursive = TRUE, showWarnings = FALSE)
  file.create(file.path(RR, "02_Infrastructure/config.R"))                                  # rf_prereg 루트 표지(.rfp_is_root)
  file.copy(PRC, file.path(RR, "06_Registry/prereg/prereg_config.json"))
  file.copy(CONTRACT, file.path(RR, "02_Infrastructure/contracts/selection_accounting.R"))   # 계약 파일 존재 검사용 사본
  PE <- new.env(parent = globalenv()); invisible(capture.output(sys.source(PRL, envir = PE, keep.source = FALSE)))
  pcfg <- PE$rf_prereg_config(RR); cdef <- pcfg$verdict$contracts[["sa_subwindow"]]
  chk("RT1 소비자 설정에 이 계약 등재(파일 = 이 계약 · artifact_regime_required)", is.list(cdef) && identical(cdef$file, "02_Infrastructure/contracts/selection_accounting.R") &&
        isTRUE(cdef$artifact_regime_required))
  pinw <- if (is.list(cdef$pinned) && !is.null(cdef$pinned$end_from_config)) {
    w <- pcfg; for (kk in strsplit(as.character(cdef$pinned$end_from_config), ".", fixed = TRUE)[[1]]) w <- if (is.list(w)) w[[kk]] else NULL; w } else NULL
  chk("RT2 소비자 고정 end_from_config = 1(설정 cut id 산출만 판정 입력)", isTRUE(all.equal(as.numeric(pinw), 1)), sprintf("(%s)", format(pinw)))
  ADIR <- file.path(RR, "stage_artifacts/prereg/PR-RT")
  PRX <- list(metrics = list(list(id = "calmar_trunc", contract = "sa_subwindow"), list(id = "oos_retention_trunc", contract = "sa_subwindow")),
              floors = list(list(id = "F")), arms = list(list(id = "A1")), contrasts = list(), se_cells = list(), measurement_regime = list(exec_price = "close_t1"))
  rel <- function(p) substring(normalizePath(p, winslash = "/"), nchar(normalizePath(RR, winslash = "/")) + 2L)
  mkm <- function(p, metric, path, ..., regime = "close_t1") c(list(metric = metric, target = "A1"), list(...),
    list(source = list(contract = "sa_subwindow", artifact = rel(p), artifact_sha256 = PE$.rfp_sha_file(p), measurement_regime = list(exec_price = regime),
                       fields = list(value = path))))
  RTX <- function(m, pr = PRX, cf = pcfg) tryCatch(PE$.rfp_check_measurement(m, pr, RR, cf, TRUE), error = function(e) conditionMessage(e))
  # 설정 cut id 절단판(합성 범위 안 cut 을 둔 설정 사본) — 같은 end 의 end 인자 판과 수치는 같고 출처만 다르다
  xc <- c0; xc$subwindow$cuts$trunc_rt <- list(end = format(e_me), source = "검사 전용 — 합성 범위 안 절단(소비자 왕복)")
  CFGT <- sa_config(ROOT, wcfg(xc, "rt_cfg.json"))
  rct <- sa_subwindow(ART, cut = "trunc_rt", root = ROOT, cfg = CFGT, verify_identity = FALSE)
  chk("RT3a 설정 cut 절단판 = 같은 end 의 end 인자 판(수치 동일 · 출처만 다름 · end_from_config 1/0)",
      identical(rt(rct$essence), rt(r_me$essence)) && identical(rct$end_from_config, 1L) && identical(r_me$end_from_config, 0L) && isTRUE(rct$window$truncated))
  pc <- sa_write(rct, ADIR, prefix = "rt_cut")
  m1 <- RTX(mkm(pc, "calmar_trunc", "essence/calmar")); m2 <- RTX(mkm(pc, "oos_retention_trunc", "essence/oos_retention"))
  chk("RT3 양성 — 소비자가 설정 cut 산출을 받고 source.fields 경로로 수치를 재도출(essence/calmar · essence/oos_retention = 계약 값)",
      is.list(m1) && is.list(m2) && isTRUE(all.equal(m1$value, rct$essence$calmar)) && isTRUE(all.equal(m2$value, rct$essence$oos_retention)),
      if (is.character(m1)) sprintf("(거부: %s)", substr(m1, 1, 100)) else if (is.character(m2)) sprintf("(거부: %s)", substr(m2, 1, 100)) else sprintf("(calmar %.4f)", m1$value))
  pa <- sa_write(r_me, ADIR, prefix = "rt_arg")
  e4 <- RTX(mkm(pa, "calmar_trunc", "essence/calmar"))
  chk("RT4 end 인자 산출(같은 수치) → 거부(pinned end_from_config — 절단일 쇼핑 차단)", is.character(e4) && grepl("end_from_config", e4), substr(as.character(e4)[1], 1, 90))
  e5 <- RTX(mkm(pc, "calmar_trunc", "essence/calmar"), pr = modifyList(PRX, list(measurement_regime = list(exec_price = "close_d_legacy"))))
  chk("RT5 사전등록 규약 ≠ 산출 규약 → 거부(실현값 대조)", is.character(e5) && grepl("규약", e5), substr(as.character(e5)[1], 1, 90))
}

# ═══ M 돌연변이 ═══
cat("\n[M] 돌연변이\n")
src <- readLines(CONTRACT, encoding = "UTF-8", warn = FALSE)
mutant <- function(from, to) {
  hit <- which(grepl(from, src, fixed = TRUE)); if (length(hit) != 1L) return(NULL)
  s2 <- src; s2[hit] <- sub(from, to, s2[hit], fixed = TRUE)
  p <- file.path(TMP, sprintf("mut_%d.R", sample.int(1e6, 1))); writeLines(s2, p, useBytes = TRUE)
  e <- new.env(parent = globalenv()); invisible(capture.output(sys.source(p, envir = e, keep.source = FALSE))); e
}
mchk <- function(name, m, fn) if (is.null(m)) chk(paste(name, "— 대상 줄 1곳"), FALSE) else fn(m)
ind_me <- score_sim(cut_sim(SIM, e_me))
mchk("M1", mutant("keep <- function(x) x[date <= end_d]", "keep <- function(x) x[date < end_d]"), function(m) {
  x <- m$sa_subwindow(ART, end = format(e_me), root = ROOT, cfg = CFG, verify_identity = FALSE)
  chk("M1 date < end(하루 누락) 돌연변이는 S2 를 red 로", !identical(rt(x$essence), rt(ind_me$es$essence))) })
mchk("M2", mutant("nav_t <- keep(nav)", "nav_t <- nav"), function(m) {
  x <- m$sa_subwindow(ART, end = format(e_me), root = ROOT, cfg = CFG, verify_identity = FALSE)
  chk("M2 nav 미절단 돌연변이는 S2 를 red 로", !identical(rt(x$essence), rt(ind_me$es$essence))) })
mchk("M3", mutant("n_trials_cumulative = nt, selection_type = st, sidecar_log = FALSE", "n_trials_cumulative = NULL, selection_type = st, sidecar_log = FALSE"), function(m) {
  e <- tryCatch({ m$sa_subwindow(ART, end = format(LAST + 1), root = ROOT, cfg = CFG); "no_error" }, error = function(e) conditionMessage(e))
  chk("M3 채점 인자 n_trials 누락 돌연변이는 S1 항등 자기검사에서 멈춘다", grepl("항등 자기검사 실패", e), substr(e, 1, 70)) })
mchk("M4", mutant("if (!ess_same || !grd_same)", "if (FALSE)"), function(m) {
  e <- tryCatch({ m$sa_subwindow(TA, end = format(e_me), root = ROOT, cfg = CFG); "no_error" }, error = function(e) conditionMessage(e))
  chk("M4 항등 자기검사 제거 돌연변이는 S3c 를 red 로(변조를 못 잡는다)", identical(e, "no_error"), substr(e, 1, 60)) })
if (is.function(RTX)) {
  mchk("M5", mutant('end_from_config = as.integer(startsWith(end_src, "config:")),', "end_from_config = 1L,"), function(m) {
    x <- m$sa_subwindow(ART, end = format(e_me), root = ROOT, cfg = CFG, verify_identity = FALSE); p5 <- sa_write(x, ADIR, prefix = "rt_mut5")
    r <- RTX(mkm(p5, "calmar_trunc", "essence/calmar"))
    chk("M5 end_from_config 를 늘 1 로 낸 돌연변이는 RT4 를 red 로(end 인자 산출이 판정 입력으로 통과)", is.list(r), if (is.character(r)) substr(r, 1, 70) else "") })
  pc6 <- pcfg; pc6$verdict$contracts$sa_subwindow$pinned <- NULL
  x6 <- RTX(mkm(pa, "calmar_trunc", "essence/calmar"), cf = pc6)
  chk("M6 소비자 설정에서 end_from_config 고정을 끈 돌연변이는 RT4 를 red 로(고정이 일을 한다)", is.list(x6), if (is.character(x6)) substr(x6, 1, 70) else "")
} else chk("M5·M6 소비자 왕복 돌연변이 — 소비자 부재로 잴 수 없다", FALSE)

# ═══ R 읽기 전용 ═══
cat("\n[R] 루트 읽기 전용\n")
chk("R1 루트 contracts·06_Registry 최상위 지문 불변", identical(FP0, ROOT_FP()), sprintf("(%d 파일)", length(FP0)))

cat(sprintf("\n결과: PASS %d · FAIL %d\n", pass, fail))
cat(sprintf('{"test":"selection_accounting","pass":%d,"fail":%d,"total":%d,"skipped":0}\n', pass, fail, pass + fail))
unlink(TMP, recursive = TRUE)
quit(status = if (fail > 0L) 1L else 0L)
