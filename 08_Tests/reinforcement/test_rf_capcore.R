#!/usr/bin/env Rscript
#==============================================================================
# test_rf_capcore.R — PR-L1 cap_core(벤치 인지 코어-위성) + B7 후보 제외 엔진 배선 (2026-10-03 CAPCORE-IMPL · B7-EXCL-IMPL)
#
# 지키는 불변식(양방향 — 양성 대조 + 위반 주입):
#   K  k=0 / 키 없음 = 기존 칸과 **비트 동일**(EW → FACTORS identical · 비EW → PORTFOLIO identical · 진단 파일 0)
#   U  코어 = 시그널일 K200 멤버 중 t-1 시총 상위 k(유동성 t-1 통과) · 비중 = t-1 시총 / K200 t-1 시총 합 · 위성 = 바닥 비중 × (1−Σc)
#      합집합 ≤ n_max 절단 = 코어 밖 위성을 바닥 점수 낮은 순으로(동률 Ticker) · 겹침 = 코어 한 자리 + 위성 몫 가산
#   F  고정 축 — Σw=1 · w≥0 · ≤ n_max · 유니버스 K200∪KQ150 칸에서만 · FACTORS 제거(러너가 PORTFOLIO 를 쓰게) ·
#      (E9) 사전등록 draft3 형식(최상위 weight_stage)은 엔진이 멈춘다(조용한 무처치 차단)
#   P  PIT 섭동 — 시그널일 당일 Size 교란 → 불변 · t-1 Size 교란 → 코어가 바뀐다(양성) · 미래 행(Size·K200) 교란 → 과거 보유 불변
#   R  C1 무작위 위성 — seed 결정론 · 베타 구간 · 접두 안정 · 전역 난수 상태 복원
#   S  서명 — cap_core(k>0)는 바닥과 다른 칸 · k=0·키 없음은 구판 서명 그대로
#   X  B7 exclude=base_factors 엔진 배선 — 셀 스펙 factors 의 id 가 후보에서 빠진다(빠지지 않으면 엔진이 멈추는 픽스처로 양방향) ·
#      전달량 진단 → 계약(contracts/sleeve_delivery.R) 재도출 왕복
# 돌연변이 판별력은 키트 tools/mutants.sh 가 잰다(각 방어를 끈 사본에서 이 검사가 red).
# 부작용 없음: 픽스처·스펙·진단·임시 루트 전부 tempdir. 원장·산출물·설정 무접촉. 실행: cd <ROOT> && Rscript 08_Tests/reinforcement/test_rf_capcore.R
#==============================================================================
suppressMessages({ library(data.table); library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
ENGINE <- file.path(ROOT, "02_Infrastructure/reinforcement/rf_cell_engine.R")
suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_capcore.R")))
.pass <- 0L; .fail <- 0L
ok <- function(m) { .pass <<- .pass + 1L; cat(sprintf("  [OK] %s\n", m)) }
ng <- function(m, d = "") { .fail <<- .fail + 1L; cat(sprintf("  [NG] %s%s\n", m, if (nzchar(d)) paste0(" — ", d) else "")) }
# chk 는 조건 평가 오류도 NG 로 센다(돌연변이가 객체를 깨면 최상위에서 죽지 않고 이름 붙은 red 가 남게)
chk <- function(cond, m_ok, m_ng = m_ok, detail = "") {
  v <- tryCatch(isTRUE(cond), error = function(e) structure(FALSE, msg = conditionMessage(e)))
  d <- tryCatch(paste(detail, collapse = " "), error = function(e) "")
  if (isTRUE(v)) ok(m_ok) else ng(m_ng, paste(d, attr(v, "msg") %||% ""))
}
# 절 단위 보호 — 절 안 계산이 죽으면 그 절을 NG 1건으로 남기고 다음 절로 간다(요약 JSON 은 항상 나온다)
sect <- function(name, expr) tryCatch(expr, error = function(e) ng(paste0(name, " 절 중단(계산 오류)"), conditionMessage(e)))
.err <- function(expr) tryCatch({ force(expr); NA_character_ }, error = function(e) conditionMessage(e))
TMPD <- file.path(tempdir(), paste0("capcore_", Sys.getpid())); dir.create(TMPD, recursive = TRUE, showWarnings = FALSE)
# 비트 동일 판정 — data.table 은 .internal.selfref(외부 포인터)가 표마다 달라 identical() 이 항상 FALSE 다. 열 이름·행 수·열별 identical 로 잰다.
bit_same <- function(a, b) !is.null(a) && !is.null(b) && identical(names(a), names(b)) && nrow(a) == nrow(b) &&
  all(vapply(names(a), function(n) identical(a[[n]], b[[n]]), logical(1)))

cat("== A. 파싱 ==\n")
chk(is.null(rf_cc_parse(NULL)) && is.null(rf_cc_parse(list())), "A1 키 없음 → NULL")
chk(grepl("k 필수", .err(rf_cc_parse(list(satellite = "floor"))) %||% ""), "A2 k 없음 → stop")
chk(all(vapply(list(-1, 1.5, "a", c(1, 2)), function(v) grepl("k 는", .err(rf_cc_parse(list(k = v))) %||% ""), logical(1))),
    "A3 k 음수·소수·문자·복수 → stop")
chk(grepl("알 수 없는 인자", .err(rf_cc_parse(list(k = 2, cap = 0.3))) %||% ""), "A4 알 수 없는 인자(비중 상한 등) → stop")
chk(grepl("미지원 satellite", .err(rf_cc_parse(list(k = 2, satellite = "random"))) %||% ""), "A5 미지원 satellite → stop")
chk(grepl("seed 필수", .err(rf_cc_parse(list(k = 2, satellite = "random_beta_matched", beta_factor = "D02_Beta"))) %||% "") &&
      grepl("beta_factor 필수", .err(rf_cc_parse(list(k = 2, satellite = "random_beta_matched", seed = 3))) %||% ""),
    "A6 C1 무작위 위성은 seed·beta_factor 필수(코드 기본값 없음 — 사전등록 스펙 값)")
chk(grepl("k=0", .err(rf_cc_parse(list(k = 0, satellite = "random_beta_matched", beta_factor = "B", seed = 1))) %||% ""),
    "A7 k=0 + 무작위 위성 → stop(무처치 칸에 무작위만 남는 칸 금지)")
chk(grepl("쓰이지 않는다", .err(rf_cc_parse(list(k = 2, seed = 5))) %||% ""), "A8 floor 위성에 seed → stop(서명만 다른 같은 처치 금지)")
p2 <- rf_cc_parse(list(k = 2)); p0 <- rf_cc_parse(list(k = 0L))
chk(identical(p2$k, 2L) && identical(p2$satellite, "floor") && identical(p0$k, 0L), "A9 정상 파싱 — k=2 floor · k=0")

cat("== B. 코어(rf_cc_core) 단위 ==\n")
sect("B", {
d1 <- as.Date("2020-01-31"); d2 <- as.Date("2020-02-28")
XB <- rbind(
  data.table(Date = d1, Ticker = c("A", "B", "C", "D", "E", "N"), K200 = c(TRUE, TRUE, TRUE, TRUE, TRUE, FALSE),
             .SizeLag = c(500, 300, 200, NA, 100, 9999), .adv20_l1 = c(1e9, 1e9, 1e9, 1e9, 1e9, 1e9)),
  data.table(Date = d2, Ticker = c("A", "B", "C", "D", "E", "N"), K200 = c(TRUE, TRUE, TRUE, TRUE, TRUE, FALSE),
             .SizeLag = c(500, 300, 200, 50, 100, 9999), .adv20_l1 = c(1e7, 1e9, 1e9, 1e9, 1e9, 1e9)))
CB <- rf_cc_core(XB, 2L, 2e8)
c1 <- CB$core[Date == d1]; c2 <- CB$core[Date == d2]
chk(identical(c1$Ticker, c("A", "B")) && isTRUE(all.equal(c1$cw, c(500, 300) / 1100)),
    "B1 코어 = K200 t-1 시총 상위 2(A·B) · 비중 = t-1 시총 / K200 유한 합(1100 — 비K200 N 9999 제외 · 결측 D 제외)")
chk(identical(c2$Ticker, c("B", "C")) && isTRUE(all.equal(c2$cw, c(300, 200) / 1150)) && CB$diag[Date == d2]$n_illiquid_above == 1L,
    "B2 유동성 미달 A(t-1 adv20 1e7) 는 코어에서 빠지고 분모에는 남는다(벤치 비중 근사) · 밀린 수 1 기록")
chk(isTRUE(all.equal(CB$diag[Date == d1]$size_cov, 4 / 5)), "B3 K200 t-1 시총 커버리지(4/5) 기록")
chk(grepl("후보 .* < k", .err(rf_cc_core(XB, 5L, 2e8)) %||% ""), "B4 유동성 통과 후보 < k → stop")
chk(grepl("≥ 1", .err(rf_cc_core(data.table(Date = d1, Ticker = c("A", "B"), K200 = TRUE, .SizeLag = c(1, 1), .adv20_l1 = 1e9), 2L, 2e8)) %||% ""),
    "B5 코어 비중 합 ≥ 1(위성 소멸) → stop")
chk(grepl("열 부재", .err(rf_cc_core(XB[, !"K200"], 2L, 2e8)) %||% ""), "B6 입력 열 부재 → stop")

})
cat("== C. 합성(rf_cc_compose) 단위 ==\n")
sect("C", {
mk_core <- function(d, tk, cw) data.table(Date = d, Ticker = tk, cw = cw)
S10 <- data.table(Date = d1, Ticker = sprintf("S%02d", 1:10), Weight = 0.1, Score = 10:1)
C1x <- rf_cc_compose(S10, mk_core(d1, c("A", "B"), c(0.2, 0.1)), 25L)$portfolio
chk(nrow(C1x) == 12L && isTRUE(all.equal(sum(C1x$Weight), 1)) && isTRUE(all.equal(C1x[Ticker == "A"]$Weight, 0.2)) &&
      isTRUE(all.equal(C1x[Ticker == "S01"]$Weight, 0.7 / 10)),
    "C1 절단 없음 — 코어 A 0.2·B 0.1 그대로 · 위성 = 0.1 × (1−0.3)")
S25 <- data.table(Date = d1, Ticker = sprintf("S%02d", 1:25), Weight = 1 / 25, Score = c(25:3, 2, 2))
R25 <- rf_cc_compose(S25, mk_core(d1, c("A", "B"), c(0.2, 0.1)), 25L)
P25 <- R25$portfolio
chk(nrow(P25) == 25L && !any(c("S24", "S25") %in% P25$Ticker) && R25$diag$n_truncated == 2L &&
      isTRUE(all.equal(P25[Ticker == "S01"]$Weight, 0.7 / 23)),
    "C2 |C∪S|=27 → 점수 낮은 위성 2(S24·S25 · 동률 2 는 Ticker 순으로 뒤가 먼저) 절단 · 남은 23 위성 = 0.7/23")
S25b <- copy(S25)[, Score := c(25:2, 2)]; S25b[Ticker == "S24", Score := 2]   # S24·S25 동률(2) · S23 = 3
P25b <- rf_cc_compose(S25b, mk_core(d1, c("A", "B"), c(0.2, 0.1)), 25L)$portfolio
chk(!("S25" %in% P25b$Ticker) && !("S24" %in% P25b$Ticker) && ("S23" %in% P25b$Ticker), "C2b 동률 tie-break 결정론(Ticker 사전순 뒤가 먼저 빠짐)")
S25o <- copy(S25)[Ticker == "S01", Ticker := "A"]                                  # 위성 1위가 코어 A 와 겹친다
R25o <- rf_cc_compose(S25o, mk_core(d1, c("A", "B"), c(0.2, 0.1)), 25L)
P25o <- R25o$portfolio
chk(nrow(P25o) == 25L && R25o$diag$n_overlap == 1L && R25o$diag$n_truncated == 1L &&
      isTRUE(all.equal(P25o[Ticker == "A"]$Weight, 0.2 + 0.7 / 24)) && identical(P25o[Ticker == "A"]$role, "core+satellite"),
    "C3 겹침 = 코어 한 자리 · 위성 몫(0.7/24) 가산 · 절단 1(|C∪S|=26)")
Snw <- data.table(Date = d1, Ticker = sprintf("S%02d", 1:4), Weight = c(0.4, 0.3, 0.2, 0.1), Score = 4:1)
Pnw <- rf_cc_compose(Snw, mk_core(d1, "A", 0.25), 25L)$portfolio
chk(isTRUE(all.equal(Pnw[Ticker == "S01"]$Weight / Pnw[Ticker == "S04"]$Weight, 4)) && isTRUE(all.equal(sum(Pnw[Ticker != "A"]$Weight), 0.75)),
    "C4 비EW 바닥 비중의 비율 보존(0.4:0.1 = 4) · 위성 합 = 1 − Σc")
chk(grepl("≥ n_max", .err(rf_cc_compose(S10, mk_core(d1, LETTERS[1:3], c(.1, .1, .1)), 3L)) %||% ""), "C5 코어 ≥ n_max → stop")
chk(grepl("코어가 없는", .err(rf_cc_compose(rbind(S10, copy(S10)[, Date := d2]), mk_core(d1, "A", 0.2), 25L)) %||% ""),
    "C6 코어가 없는 위성 시그널일 → stop(코어 없는 달을 처치 받은 달로 기록 금지)")
chk(grepl("점수 결측", .err(rf_cc_compose(copy(S25)[, Score := NA_real_], mk_core(d1, c("A", "B"), c(.2, .1)), 25L)) %||% ""),
    "C7 절단이 필요한데 위성 점수 결측 → stop")
chk(grepl("음수", .err(rf_cc_compose(copy(S10)[1, Weight := -0.1], mk_core(d1, "A", 0.2), 25L)) %||% ""), "C8 음수 위성 비중 → stop(long-only)")
Sns <- S10[, .(Date, Ticker, Weight)]
Pns <- rf_cc_compose(Sns, mk_core(d1, "A", 0.2), 25L, SCORE = S10[, .(Date, Ticker, Score)])$portfolio
chk(nrow(Pns) == 11L && isTRUE(all.equal(sum(Pns$Weight), 1)), "C9 위성에 Score 가 없으면 바닥 점수표(SCORE)에서 붙인다")

})
cat("== R. C1 무작위 위성 단위 ==\n")
sect("R", {
set.seed(99); RD <- as.Date(sprintf("2005-%02d-28", 1:6))
PR <- CJ(Date = RD, Ticker = sprintf("T%02d", 1:60))[, Score := rnorm(.N)]
BR <- copy(PR)[, .(Date, Ticker, .zbeta = as.integer(sub("T", "", Ticker)) / 60)]
SR <- PR[, .SD[order(-Score)][1:25], by = Date][, .(Date, Ticker)]
.rs0 <- if (exists(".Random.seed", envir = globalenv())) get(".Random.seed", envir = globalenv()) else NULL
r1 <- rf_cc_random_satellite(PR, SR, BR, ".zbeta", 7L, as.Date("2005-01-01"))
.rs1 <- if (exists(".Random.seed", envir = globalenv())) get(".Random.seed", envir = globalenv()) else NULL
r2 <- rf_cc_random_satellite(PR, SR, BR, ".zbeta", 7L, as.Date("2005-01-01"))
r3 <- rf_cc_random_satellite(PR, SR, BR, ".zbeta", 8L, as.Date("2005-01-01"))
r4 <- rf_cc_random_satellite(PR[Date < RD[6]], SR[Date < RD[6]], BR, ".zbeta", 7L, as.Date("2005-01-01"))
chk(bit_same(r1, r2) && bit_same(attr(r1, "rf_cc_rand"), attr(r2, "rf_cc_rand")) && !identical(r1$Ticker, r3$Ticker), "R1 같은 seed → 비트 동일 · 다른 seed → 다른 추출")
chk(identical(.rs0, .rs1), "R2 전역 난수 상태 복원(호출 전후 .Random.seed 동일)")
chk(bit_same(r1[Date < RD[6]], r4), "R3 접두 안정 — 마지막 달을 빼도 앞 달 추출 불변")
bandok <- all(vapply(RD, function(d) { b <- BR[Date == d & Ticker %in% SR[Date == d]$Ticker]$.zbeta; x <- BR[Date == d & Ticker %in% r1[Date == d]$Ticker]$.zbeta
  all(x >= min(b) & x <= max(b)) }, logical(1)))
chk(bandok && all(r1[, .N, by = Date]$N == 25L) && isTRUE(all.equal(r1[, sum(Weight), by = Date]$V1, rep(1, 6))),
    "R4 바닥 위성 베타 구간 안에서 |SEL| 개 · EW")
chk(grepl("베타가 전부 결측", .err(rf_cc_random_satellite(PR, SR, copy(BR)[, .zbeta := NA_real_], ".zbeta", 7L, as.Date("2005-01-01"))) %||% ""),
    "R5 바닥 위성 베타 전부 결측 → stop(대조 측정 무효)")

})
cat("== S. 서명 ==\n")
suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_spec_sig.R")))
sb <- list(factors = list(list(kind = "db", id = "X1")), weighting = list(kind = "ew"), base_signal = list(kind = "engine", path = "e.R"))
sa <- sb; sa$cap_core <- list(k = 2); sa1 <- sb; sa1$cap_core <- list(k = 1); s0 <- sb; s0$cap_core <- list(k = 0)
sc <- sb; sc$cap_core <- list(k = 2, satellite = "random_beta_matched", beta_factor = "D02_Beta", seed = 11)
chk(!identical(.spec_sig(sa), .spec_sig(sb)) && !identical(.spec_sig(sa), .spec_sig(sa1)) && !identical(.spec_sig(sa), .spec_sig(sc)),
    "S1 cap_core k=2 · k=1 · C1 무작위 = 바닥과도 서로도 다른 칸(접히지 않는다)")
chk(identical(.spec_sig(s0), .spec_sig(sb)) && !grepl("cap_core|\"k\"", .spec_sig(sb)),
    "S2 k=0·키 없음 = 구판 서명 비트 동일(같은 포트폴리오는 같은 칸)")

# ── 엔진 픽스처(스모크 검사와 같은 생성식 · 기간만 2010 까지) ──────────────────
AXES <- list(long_only = TRUE, n_max = 25L, universe = "K200_KQ150", start_date = "2005-01-01", commission_bps = 15L, liq_adv20_min = 2e8)
make_fixture <- function(idx_n = 40L, n_tk = 50L) {
  set.seed(20260830L)
  d <- seq(as.Date("2003-06-02"), as.Date("2010-12-31"), by = "day"); d <- d[as.integer(format(d, "%w")) %in% 1:5]
  x <- CJ(Ticker = sprintf("T%03d", seq_len(n_tk)), Date = d); setorder(x, Ticker, Date)
  x[, .r := rnorm(.N, 0.0002, 0.012)]; x[, Close := 10000 * cumprod(1 + .r), by = Ticker]; x[, .r := NULL]
  x[, Vol := 200000]; x[, Size := Close * 1e6 * (1 + as.integer(sub("T", "", Ticker)) %% 7L)]
  x[, K200 := as.integer(sub("T", "", Ticker)) <= idx_n]; x[, KQ150 := FALSE]
  x[, Sector_Lv2 := paste0("S", (as.integer(sub("T", "", Ticker)) %% 5L) + 1L)]
  x[]
}
FIX <- make_fixture()
PX <- list(kind = "price", id = "lowvol60")
# ★얕은 치환 — modifyList 는 이름 없는 리스트(factors)를 재귀 병합하다가 **안 바꾼다**(초판 X1 이 그래서 lowvol60 을 기저로 돌았다).
base_spec <- function(...) { b <- list(code = "CC_T", label = "capcore test", block = "T", fixed_axes = AXES,
                                       base_signal = list(kind = "mom_12_1"), factors = list(PX),
                                       weighting = list(kind = "ew"), universe = list(kind = "k200_kq150"))
  a <- list(...); b[names(a)] <- a; b }
run_cell <- function(spec, fixture = FIX, out_dir = NULL, diag_env = "") {
  p <- file.path(TMPD, "spec.json"); writeLines(toJSON(spec, auto_unbox = TRUE, pretty = TRUE, null = "null"), p)
  Sys.setenv(RF_CELL_SPEC = p, RF_ENGINE_DIAG_DIR = diag_env)
  par <- if (is.null(out_dir)) globalenv() else { e <- new.env(parent = globalenv()); assign("OUT_DIR", out_dir, envir = e); e }
  env <- new.env(parent = par)   # 러너 모사: fe_env <- new.env(parent = 러너 함수 환경(OUT_DIR 보유))
  assign("RAWDATA", copy(fixture), envir = env); assign("BM_DT", NULL, envir = env)
  err <- NULL; logs <- character(0)
  logs <- utils::capture.output(suppressWarnings(suppressMessages(
    tryCatch(source(ENGINE, local = env), error = function(e) err <<- conditionMessage(e)))))
  Sys.unsetenv("RF_ENGINE_DIAG_DIR")
  list(err = err, env = env, logs = logs,
       pf = if (exists("PORTFOLIO", envir = env, inherits = FALSE)) get("PORTFOLIO", envir = env) else NULL,
       fx = if (exists("FACTORS", envir = env, inherits = FALSE)) get("FACTORS", envir = env) else NULL)
}
# 독립 재계산 — 코어 기대값(엔진 코드 미사용): 티커 안 직전 행 Size · 시그널일 K200 · t-1 adv20 ≥ 2e8
indep_core <- function(fx, k, sig) {
  x <- copy(fx); setorder(x, Ticker, Date)
  x[, sl := shift(Size, 1L), by = Ticker]
  x[, adv := shift(frollmean(as.numeric(Close) * as.numeric(Vol), 20L, align = "right"), 1L), by = Ticker]
  y <- x[Date %in% sig & K200 == TRUE]
  y[, den := sum(sl[is.finite(sl) & sl > 0]), by = Date]
  y[is.finite(sl) & sl > 0 & !is.na(adv) & adv >= 2e8][order(Date, -sl, Ticker)][, head(.SD, k), by = Date][, .(Date, Ticker, cw = sl / den)]
}

cat("== K. k=0 비트 동일 (무처치 양성 대조) ==\n")
DGD <- file.path(TMPD, "diag_k0"); dir.create(DGD, showWarnings = FALSE)
e0 <- run_cell(base_spec(), diag_env = DGD)
e0k <- run_cell(base_spec(cap_core = list(k = 0)), diag_env = DGD)
chk(is.null(e0$err) && is.null(e0k$err) && !is.null(e0$fx) && is.null(e0$pf) && bit_same(e0$fx, e0k$fx) && is.null(e0k$pf),
    sprintf("K1 EW 칸 — cap_core k=0 의 FACTORS 가 키 없는 칸과 identical(%d행) · PORTFOLIO 없음", NROW(e0$fx)),
    "K1 k=0 이 기존 EW 칸을 바꿨다", c(e0$err, e0k$err))
w0 <- run_cell(base_spec(weighting = list(kind = "inv_vol", window = 60L)))
w0k <- run_cell(base_spec(weighting = list(kind = "inv_vol", window = 60L), cap_core = list(k = 0L)))
chk(is.null(w0$err) && !is.null(w0$pf) && bit_same(w0$pf, w0k$pf), "K2 비EW(inv_vol) 칸 — k=0 PORTFOLIO identical", "K2", c(w0$err, w0k$err))
chk(!file.exists(file.path(DGD, "rf_engine_diag.json")), "K3 k=0·B7 없음 → 엔진 진단 파일 0(기존 칸 산출 디렉터리 무변화)")
chk(!any(grepl("cap_core", e0k$logs)), "K4 k=0 → cap_core 로그 줄 0(단계 미실행)")

cat("== E. 엔진 통합 k=2 · k=1 ==\n")
OD <- file.path(TMPD, "outdir_a1"); dir.create(OD, showWarnings = FALSE)
a1 <- run_cell(base_spec(cap_core = list(k = 2)), out_dir = OD)
chk(is.null(a1$err) && !is.null(a1$pf) && is.null(a1$fx), "E1 k=2 → PORTFOLIO 산출 · FACTORS 제거(러너 top_n_long 이 cap_core 를 버리지 않게)", "E1", a1$err)
if (!is.null(a1$pf)) {
  P <- a1$pf; sig <- sort(unique(P$Date))
  agg <- P[, .(s = sum(Weight), n = .N, mn = min(Weight)), by = Date]
  chk(max(abs(agg$s - 1)) < 1e-10 && min(agg$mn) >= 0 && max(agg$n) <= 25L && all(P$Leg == "LONG"),
      sprintf("F1 고정 축 — Σw=1(최대 오차 %.1e) · w≥0 · 보유 ≤25(최대 %d) · LONG", max(abs(agg$s - 1)), max(agg$n)))
  IC2 <- indep_core(FIX, 2L, sig)
  hit <- merge(IC2, P, by = c("Date", "Ticker"), all.x = TRUE)
  chk(nrow(IC2) == 2L * length(sig) && all(!is.na(hit$Weight)) && all(hit$Weight >= hit$cw - 1e-12),
      sprintf("U1 코어 = 독립 재계산 K200 t-1 시총 상위 2(%d 시그널일 전부 보유 · 비중 ≥ t-1 벤치 비중)", length(sig)))
  FX0 <- e0$fx; SC <- FX0[, .(Date, Ticker, Score)]
  sat <- P[!IC2, on = c("Date", "Ticker")]
  chk(all(sat[!FX0, on = c("Date", "Ticker")][, .N] == 0L), "U2 위성 ⊆ 바닥(키 없는 칸 FACTORS) 보유 — 위성이 바닥 밖 이름을 들이지 않는다")
  # 절단 = 코어 밖 바닥 이름 중 점수 하위부터
  tr_ok <- all(vapply(sig, function(d) {
    fl <- FX0[Date == d][order(-Score, Ticker)]; core <- IC2[Date == d]$Ticker; held <- P[Date == d]$Ticker
    want <- head(fl[!(Ticker %in% core)]$Ticker, 25L - length(core))
    setequal(setdiff(held, core), want)
  }, logical(1)))
  n_trunc <- sum(vapply(sig, function(d) max(0L, sum(!(FX0[Date == d]$Ticker %in% IC2[Date == d]$Ticker)) - (25L - 2L)), integer(1)))
  chk(tr_ok && n_trunc > 0L, sprintf("U3 절단 — 코어 밖 바닥 이름 중 점수 상위 (25−k)개만 남는다(낮은 점수부터 빠짐 · 절단 발생 %d건)", n_trunc), "U3", n_trunc)
  cw_ok <- all(vapply(sig, function(d) {
    core <- IC2[Date == d]; held <- P[Date == d]; nsat <- held[!(Ticker %in% core$Ticker)]
    fl <- FX0[Date == d]$Ticker; ov <- intersect(core$Ticker, fl)
    nk <- nrow(nsat) + length(ov); ws <- (1 - sum(core$cw)) / nk
    all(abs(nsat$Weight - ws) < 1e-12) && all(abs(held[match(core$Ticker, Ticker)]$Weight - (core$cw + ifelse(core$Ticker %in% ov, ws, 0))) < 1e-12)
  }, logical(1)))
  chk(cw_ok, "U4 비중 — 위성 = (1−Σc)/|S'| (EW 바닥) · 코어 = t-1 벤치 비중(+겹치면 위성 몫)")
  dg <- file.path(OD, "rf_engine_diag.json")
  chk(file.exists(dg) && !is.null(fromJSON(dg)$cap_core) && is.null(fromJSON(dg)$sleeve_delivery),
      "E2 러너 모사(상위 환경 OUT_DIR) → 진단 파일에 cap_core 절 기록")
}
a2 <- run_cell(base_spec(cap_core = list(k = 1)))
chk(is.null(a2$err) && !is.null(a2$pf) && !bit_same(a2$pf, a1$pf) &&
      all(merge(indep_core(FIX, 1L, sort(unique(a2$pf$Date))), a2$pf, by = c("Date", "Ticker"), all.x = TRUE)[, !is.na(Weight)]),
    "E3 k=1 → 코어 1종(독립 재계산 일치) · k=2 와 다른 포트폴리오", "E3", a2$err)
wa <- run_cell(base_spec(weighting = list(kind = "inv_vol", window = 60L), cap_core = list(k = 2)))
if (is.null(wa$err) && !is.null(wa$pf)) {
  d <- sort(unique(wa$pf$Date))[30]; core <- indep_core(FIX, 2L, d)$Ticker
  sw <- wa$pf[Date == d & !(Ticker %in% core)]; bw <- w0$pf[Date == d & Ticker %in% sw$Ticker]
  m <- merge(sw, bw, by = "Ticker")
  chk(nrow(m) >= 2L && max(abs(m$Weight.x / m$Weight.y - m$Weight.x[1] / m$Weight.y[1])) < 1e-9,
      "E4 비EW(inv_vol) 바닥 위성 — 바닥 비중 비율 보존(공통 배율 = (1−Σc)/남은 합)")
} else ng("E4 비EW cap_core", wa$err %||% "")
chk(grepl("k200_kq150 칸에서만", run_cell(base_spec(universe = list(kind = "size_band", q_lo = 0, q_hi = 0.9), cap_core = list(k = 2)))$err %||% ""),
    "E5 유니버스 축이 K200∪KQ150 가 아닌 칸 → stop(코어 메가캡이 유니버스 축을 깬다)")
chk(grepl("≥ n_max", run_cell(base_spec(cap_core = list(k = 25)))$err %||% ""), "E6 k ≥ n_max → stop")
c1r <- run_cell(base_spec(cap_core = list(k = 2, satellite = "random_beta_matched", beta_factor = "lowvol60", beta_kind = "price", seed = 7L)))
c1s <- run_cell(base_spec(cap_core = list(k = 2, satellite = "random_beta_matched", beta_factor = "lowvol60", beta_kind = "price", seed = 7L)))
chk(is.null(c1r$err) && !is.null(c1r$pf) && bit_same(c1r$pf, c1s$pf) && !bit_same(c1r$pf, a1$pf) &&
      max(c1r$pf[, .N, by = Date]$N) <= 25L && max(abs(c1r$pf[, sum(Weight), by = Date]$V1 - 1)) < 1e-10,
    "E8 C1(코어 k=2 + 베타매칭 무작위 위성) — 결정론 · A1 과 다름 · 고정 축 유지", "E8", c1r$err)
# E9 — 사전등록 draft3 형식(최상위 weight_stage·k)이 셀 스펙에 그대로 실리면 엔진이 멈춘다(조용한 무처치 = 바닥 비트 동일 포트폴리오 차단)
e9 <- run_cell(base_spec(weight_stage = "cap_core", k = 2L))
e9b <- run_cell(base_spec(weight_stage = "cap_core", cap_core = list(k = 2)))
chk(grepl("weight_stage", e9$err %||% "") && grepl("weight_stage", e9b$err %||% ""),
    "E9 최상위 weight_stage(draft3 형식 · cap_core 키 유무 무관) → stop(엔진이 읽지 않는 처치 키 = 조용한 무처치 차단)", "E9",
    c(e9$err %||% "멈추지 않음", e9b$err %||% "멈추지 않음"))

cat("== P. PIT 섭동 ==\n")
sig_all <- sort(unique(a1$pf$Date))
FP1 <- copy(FIX); FP1[Date %in% sig_all, Size := Size * runif(.N, 0.01, 100)]               # 시그널일 당일 시총 교란
p1 <- run_cell(base_spec(cap_core = list(k = 2)), fixture = FP1)
chk(is.null(p1$err) && bit_same(p1$pf, a1$pf), "P1 시그널일 당일 Size 교란 → 보유·비중 비트 동일(t-1 만 쓴다 · C2)", "P1 당일 시총이 새어 들었다", p1$err)
setorder(FIX, Ticker, Date)
prev_day <- FIX[Ticker == "T040", .(Date, prv = shift(Date))][Date %in% sig_all]$prv
FP2 <- copy(FIX); FP2[Ticker == "T040" & Date %in% prev_day, Size := 1e20]                     # t-1 시총만 거대하게
p2 <- run_cell(base_spec(cap_core = list(k = 2)), fixture = FP2)
chk(is.null(p2$err) && all(vapply(sig_all, function(d) "T040" %in% p2$pf[Date == d]$Ticker, logical(1))) &&
      all(p2$pf[Ticker == "T040"]$Weight > 0.99 * (1e20 / (1e20 + 1))) ,
    "P2 [양성] t-1 Size 만 교란 → 그 종목이 전 시그널일 코어 · 비중 ≈ 벤치 비중(t-1 값을 실제로 쓴다)", "P2", p2$err)
cut <- sig_all[30]
FP3 <- copy(FIX); FP3[Date > cut, `:=`(Size = Size * runif(.N, 0.01, 100),                     # 미래 시총·멤버십 교란(멤버 5종 교체 —
                                       K200 = as.integer(sub("T", "", Ticker)) %in% 6:45)]       #   멤버 수 40 유지: 후보 가드 회피)
p3 <- run_cell(base_spec(cap_core = list(k = 2)), fixture = FP3)
chk(is.null(p3$err) && bit_same(p3$pf[Date <= cut], a1$pf[Date <= cut]) && !bit_same(p3$pf, a1$pf), sprintf("P3 미래(> %s) Size·K200 교란 → 그 이전 보유 비트 동일", format(cut)),
    "P3 미래 행이 과거 보유를 바꿨다", p3$err)

cat("== X. B7 exclude=base_factors 엔진 배선 · 전달량 진단 → 계약 왕복 ==\n")
# 임시 루트: 등록부 = 방어 후보 XDEF(as-of 1위) · lowvol60(2위). 기저 팩터에 XDEF(null_perm — 값 무관 · id 만)를 둔다.
#   제외가 걸리면 슬리브 = lowvol60(price 원천으로 적재 가능) → 엔진 완주. 제외가 무시되면 XDEF 를 price 로 적재하려다 멈춘다(양방향).
XR <- file.path(TMPD, "xroot"); for (dd in c("02_Infrastructure/reinforcement", "06_Registry", "02_Infrastructure/contracts")) dir.create(file.path(XR, dd), recursive = TRUE, showWarnings = FALSE)
for (f in c("rf_rebalance.R", "rf_sleeve.R", "rf_capcore.R", "rf_cell_engine.R"))
  file.copy(file.path(ROOT, "02_Infrastructure/reinforcement", f), file.path(XR, "02_Infrastructure/reinforcement", f), overwrite = TRUE)
write(toJSON(list(factors = list(XDEF = list(category = "defense", lifecycle_status = "active"),
                                 lowvol60 = list(category = "risk", lifecycle_status = "active"))), auto_unbox = TRUE),
      file.path(XR, "06_Registry/factor_evidence.json"))
write(toJSON(list(fixed_axes = list(start_date = "2005-01-01"),
                  blocks = list(list(id = "B7", selection_asof = list(bear_quantile = 0.3, min_bear_months = 4L, candidate_categories = c("defense", "risk"),
                                                                     rank_key = "ic_bad", ic_path = "ic.parquet", bench_path = "bm.parquet",
                                                                     bench_price_col = "BM_Close")))), auto_unbox = TRUE),
      file.path(XR, "06_Registry/reinforce_program.json"))
.me <- seq(as.Date("2000-02-01"), by = "month", length.out = 59L) - 1L; .ue <- seq(as.Date("2000-03-01"), by = "month", length.out = 59L) - 1L
.bm <- data.table(hm = format(.ue, "%Y-%m"), ret = ifelse(seq_along(.ue) %% 3L == 0L, -0.08, 0.02), hend = .ue)
.ic <- rbindlist(lapply(c("XDEF", "lowvol60"), function(f) data.table(Factor_Name = f, Date = .me, Usable_Date = .ue,
                                                                        IC = ifelse(.bm$ret < 0, if (f == "XDEF") 0.30 else 0.10, 0))))
suppressMessages(library(arrow)); arrow::write_parquet(.ic, file.path(XR, "ic.parquet")); arrow::write_parquet(.bm, file.path(XR, "bm.parquet"))
run_x <- function(sleeve, out_dir = NULL) {
  old <- Sys.getenv("QM_ROOT"); Sys.setenv(QM_ROOT = XR); on.exit(Sys.setenv(QM_ROOT = old))
  ENGINE <<- file.path(XR, "02_Infrastructure/reinforcement/rf_cell_engine.R"); on.exit(ENGINE <<- file.path(ROOT, "02_Infrastructure/reinforcement/rf_cell_engine.R"), add = TRUE)
  run_cell(base_spec(factors = list(list(kind = "null_perm", id = "XDEF", seed = 1L)), defense_sleeve = sleeve), out_dir = out_dir)
}
XO <- file.path(TMPD, "outdir_x"); dir.create(XO, showWarnings = FALSE)
xe <- run_x(list(kind = "factor_topk", k = 5, factor_kind = "price", exclude = "base_factors"), out_dir = XO)
xn <- run_x(list(kind = "factor_topk", k = 5, factor_kind = "price"))
chk(is.null(xe$err) && any(grepl("팩터 lowvol60", xe$logs)) && any(grepl("기저 팩터 제외 1종(풀 안 1: XDEF)", xe$logs, fixed = TRUE)),
    "X1 [양성] exclude=base_factors → 셀 스펙 factors 의 XDEF 가 후보에서 빠지고 lowvol60 이 슬리브(엔진 완주)", "X1", xe$err)
chk(!is.null(xn$err) && grepl("XDEF", xn$err), "X2 [대조] 제외 없음 → as-of 1위 XDEF 선택(제외가 실제로 선택을 바꾼다)", "X2", xn$err %||% "멈추지 않았다")
dgx <- file.path(XO, "rf_engine_diag.json")
DX <- if (file.exists(dgx)) fromJSON(dgx) else NULL
chk(!is.null(DX$sleeve_delivery) && identical(DX$sleeve_delivery$resolved_id, "lowvol60") && identical(as.character(DX$sleeve_delivery$excluded_ids), "XDEF") &&
      nrow(as.data.frame(DX$sleeve_delivery$rows)) > 0L, "X3 진단 파일 — 전달량 행 · 제외 id(XDEF) · 해석 id(lowvol60)")
# 계약 왕복: 같은 디렉터리에 authoritative_remeasure.json(실현 규약) → sd_measure 재도출 = 엔진 요약
write(toJSON(list(measurement_regime = list(exec_price = "close_t1")), auto_unbox = TRUE), file.path(XO, "authoritative_remeasure.json"))
suppressMessages(source(file.path(ROOT, "02_Infrastructure/contracts/sleeve_delivery.R")))
sm <- tryCatch(sd_measure(XO, "sleeve_delivery"), error = function(e) conditionMessage(e))
chk(is.list(sm) && isTRUE(all.equal(sm$value, DX$sleeve_delivery$summary$pooled)) && isTRUE(all.equal(sm$mean_by_date, DX$sleeve_delivery$summary$mean_by_date)) &&
      identical(sm$measurement_regime$exec_price, "close_t1") && sm$value > 0 && sm$value <= 1,
    sprintf("X4 계약 sd_measure 재도출 = 엔진 요약(δ 풀링 %.3f · 등가중 %.3f) · 실현 규약 close_t1", if (is.list(sm)) sm$value else NA, if (is.list(sm)) sm$mean_by_date else NA),
    "X4", if (is.character(sm)) sm else "")
ca <- tryCatch(sd_measure(OD, "cap_core"), error = function(e) conditionMessage(e))
chk(is.character(ca) && grepl("authoritative_remeasure", ca), "X5 cap_core 진단만 있고 실현 규약 파일이 없으면 계약이 멈춘다(fail-closed)")
write(toJSON(list(measurement_regime = list(exec_price = "close_t1")), auto_unbox = TRUE), file.path(OD, "authoritative_remeasure.json"))
ca2 <- tryCatch(sd_measure(OD, "cap_core"), error = function(e) conditionMessage(e))
chk(is.list(ca2) && ca2$value > 0 && ca2$value < 1 && ca2$k == 2L, sprintf("X6 cap_core 계약 — Σ코어 평균 %.4f 재도출", if (is.list(ca2)) ca2$value else NA), "X6",
    if (is.character(ca2)) ca2 else "")

unlink(TMPD, recursive = TRUE)
cat(sprintf("\n== 결과: %d PASS / %d FAIL ==\n", .pass, .fail))
cat(sprintf('{"test":"rf_capcore","pass":%d,"fail":%d,"total":%d}\n', .pass, .fail, .pass + .fail))
if (.fail > 0L) quit(status = 1L)
