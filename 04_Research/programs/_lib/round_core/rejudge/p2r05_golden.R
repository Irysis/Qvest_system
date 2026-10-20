## P2R05 범용분 황금값 — 원판 = P2R05 evaluate.R(작업 중 판 · main 미커밋 · 2026-10-18 21:44 · md5 0f7402d9…)의 함수 정의만 파싱해(실행 · 사본 없음)
##   결정론 합성 입력(난수 없음 · 고정 문자열 파일)의 출력을 JSON(유효 숫자 15)으로 남긴다. 코어 이관분(v1/p2.R)이 같은 입력에서 같은 출력을 내는지
##   test_round_core_v1_p2.R J 가 이 황금값으로 대조한다(원판 파일이 없어도 · 그 판이 바뀌어도 이 기록이 기준).
##   의도된 차이(대조에서 뺀다): rc_p2_seed_band 의 note — P2R05 고유 근거 문구(DESIGN §0b · C-054)를 범용 문구로 바꿨다. 그 밖은 문자열 동일.
##   대조 밖(계약 함수 · 원자료가 필요한 것): rc_p2_dimson_from · rc_p2_liq_tercile_cell · rc_p2_liq_attr_round — 같은 식의 순수 부품(dimson_beta · ret_state ·
##   liq_tercile_core · liq_improvement · liq_table)이 여기서 대조된다.
## 사용: Rscript p2r05_golden.R <P2R05 evaluate.R> <황금값 json>   ·   라이브러리 = sys.source(이 파일) → rc_golden_cases(tmp) · rc_golden_run(cases, getf)
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
## 사례 id 접두 → (원판 이름 · 코어 이름)
RC_GOLDEN_FNS <- list(md5_or_na = c("p5_md5", "rc_md5_or_na"), find_pin = c("p5_find_pin", "rc_find_pin"), bins = c(".p5_bins", ".rc_p2_bins"),
                      liq_from = c("p5_liq_from", "rc_p2_liq_from"), dimson_beta = c("p5_dimson_beta", "rc_p2_dimson_beta"), margins = c("p5_margins", "rc_p2_margins"),
                      load_crisis_types = c("p5_load_crisis_types", "rc_p2_load_crisis_types"), load_onset = c("p5_load_onset", "rc_p2_load_onset"),
                      crisis_type_record = c("p5_crisis_type_record", "rc_p2_crisis_type_record"), ret_state = c("p5_ret_state", "rc_p2_ret_state"),
                      liq_tercile_core = c("p5_liq_tercile_core", "rc_p2_liq_tercile_core"), liq_improvement = c("p5_liq_improvement", "rc_p2_liq_improvement"),
                      liq_table = c("p5_liq_table", "rc_p2_liq_table"), liq_attr_for = c("p5_liq_attr_for", "rc_p2_liq_attr_for"),
                      seed_band = c("p5_seed_band", "rc_p2_seed_band"), seed_tags = c("p5_seed_tags", "rc_p2_seed_tags"), seed_tag_counts = c("p5_seed_tag_counts", "rc_p2_seed_tag_counts"))
RC_GOLDEN_SUPPORT <- c("P2R05_BOUNDARY_EPS", "P2R05_LIQ_TERCILES", "P2R05_LIQ_RECON_TOL", "P2R05_CRISIS_TYPE_NOTE", "P2R05_ONSET_NOTE", ".p5_readable")
RC_GOLDEN_DROP <- list(seed_band = "note")
rc_golden_json <- function(x, drop = character(0)) {
  if (is.list(x) && !is.data.frame(x)) for (k in drop) x[[k]] <- NULL
  as.character(toJSON(x, auto_unbox = TRUE, null = "null", na = "null", digits = NA, Date = "ISO8601", force = TRUE))
}
## 결정론 합성 입력 — 분류 파일은 고정 문자열(직렬화 판본에 기대지 않는다 · md5 고정). 사례 = list(id, fn(접두), args)
rc_golden_cases <- function(tmp) {
  dir.create(file.path(tmp, "notes"), recursive = TRUE, showWarnings = FALSE)
  put <- function(rel, s) { writeLines(enc2utf8(s), file.path(tmp, rel), useBytes = TRUE); rel }
  ct <- put("notes/crisis_type.json", paste0('{"rule":"문턱 = peak >= 2008-01-01 위기 rho_W 중앙값 = 0.35","crises":[',
    '{"crisis":"2002-04-18 2002-09-30","type":"dispersed","rho_W":0.25,"window":"판정 창"},{"crisis":"2008-05-16 2008-10-24","type":"systemic","rho_W":0.5,"window":"판정 창"},',
    '{"crisis":"2011-08-01 2011-09-26","type":"dispersed","rho_W":0.3,"window":"판정 창"},{"crisis":"2015-07-01 2015-08-24","type":"systemic","rho_W":0.35,"window":"판정 창"},',
    '{"crisis":"bad key","type":"systemic","rho_W":0.2},{"crisis":"2018-10-01 2018-10-29","type":"other","rho_W":0.35,"window":"판정 창"}],"falsification":"합성 반증 문장"}'))   # 문턱(2008~ 중앙값) = 0.35 = 경계 2건
  ct2 <- put("notes/crisis_type_norule.json", '{"rule":"문턱 없음","crises":[{"crisis":"2008-05-16 2008-10-24","type":"systemic","rho_W":0.5}]}')
  ct3 <- put("notes/crisis_type_bad.json", '{"rule":"x","crises":[]}')
  on <- put("notes/onset.json", paste0('{"table":[{"crisis":"2008-05-16 → 2008-10-24","from_top":true,"window":"판정 창"},',
    '{"crisis":"2011-08-01 → 2011-09-26","from_top":false,"window":"판정 창"},{"crisis":"2020-02-17 → 2020-03-19","from_top":true,"window":"시험 창"},',
    '{"crisis":"2015-07-01 → 2015-08-24","window":"판정 창"}],"visible_from_top":["2008-05-16 → 2008-10-24"]}'))
  on2 <- put("notes/onset_mismatch.json", '{"table":[{"crisis":"2008-05-16 → 2008-10-24","from_top":false,"window":"판정 창"}],"visible_from_top":["2008-05-16 → 2008-10-24"]}')
  m5 <- function(rel) unname(as.character(tools::md5sum(file.path(tmp, rel))))
  pin <- function(...) list(design_inputs = list(notes = lapply(list(...), function(z) list(path = z[[1]], md5 = z[[2]]))))
  ## 합성 원자료(난수 없음) — 3종목 × 30일 · C 3일 결측 · B 1일 Ret NA
  d <- seq(as.Date("2020-01-01"), by = "day", length.out = 30); i <- seq_len(90)
  RAW <- data.table(Date = rep(d, 3), Ticker = rep(c("A", "B", "C"), each = 30), Close = 1000 + (i * 37) %% 400, Vol = 1e4 + (i * 53) %% 900, Ret = ((i * 29) %% 41 - 20) / 1000)
  RAW <- RAW[!(Ticker == "C" & Date %in% d[5:7])]; RAW[Ticker == "B" & Date == d[10], Ret := NA_real_]
  j <- seq_len(60); m <- sin(j / 3) / 50 + ((j * 13) %% 7 - 3) / 1000; r <-0.2 * c(0, m[-60]) + 0.9 * m + 0.1 * c(m[-1], 0) + cos(j) / 400
  K <- c("2008-05-16 2008-10-24", "2011-08-01 2011-09-26", "2015-07-01 2015-08-24", "2018-10-01 2018-10-29")
  RL <- list(beta_deep = list(per_crisis = data.table(k = K[1:2], m = c(0.8, 0.6), r = c(0.9, 0.55)), share = 0.5),
             fast = list(per_crisis = data.table(k = K[3:4], m = c(0.7, 0.95), r = c(0.85, 0.9)), share = 1),
             selection = list(decomposition = list(per_crisis = data.table(peak_date = c("2008-05-16", "2011-08-01"), sv = c(0.1, -0.02), sr = c(0.05, 0.01)), share = 0.5)),
             beta_asym = list(delta = -0.03))
  CL <- list(status = "ok", pin_tag = NA_character_, classes = data.table(k = K[1:3], type = c("systemic", "dispersed", "systemic"), boundary = c(FALSE, FALSE, TRUE), rho_W = c(0.5, 0.3, 0.35)))
  PC <- data.table(k = K, m = c(0.7, 0.9, 0.8, NA), r = c(0.85, 0.88, 0.95, 0.9))
  DC <- data.table(peak_date = c("2008-05-16", "2015-07-01"), sv = c(0.1, -0.05), sr = c(0.02, 0.01))
  ## 유동성 3분위 — 구간 기여 · 계약 구간 수익 · 고점일 adv · 유니버스 adv
  C5 <- data.table(date = rep(d[1:4], 5), Ticker = rep(c("T1", "T2", "T3", "T4", "T5"), each = 4), contrib = ((seq_len(20) * 7) %% 11 - 5) / 1e4)
  RG <- C5[, .(ret_gross = sum(contrib)), by = date]
  RGx <- copy(RG)[1, ret_gross := ret_gross + 1e-6]
  ADV <- c(T1 = 1e8, T2 = 5e8, T3 = 2e9, T4 = 8e9, T5 = NA); U <- c(seq(5e7, 1e10, length.out = 29), NA)
  BYT <- function(lo, mid, hi) data.table(tercile = c("low", "mid", "high"), contrib = c(lo, mid, hi), n_names = c(2L, 2L, 1L))
  RV <- list(k1 = list(status = "ok", total = 0.02, recon_ok = TRUE, by_tercile = BYT(0.015, 0.004, 0.001), deep = TRUE, fast = FALSE),
             k2 = list(status = "ok", total = -0.01, recon_ok = TRUE, by_tercile = BYT(-0.005, -0.004, -0.001), deep = FALSE, fast = TRUE),
             k3 = list(status = "ok", total = 0.03, recon_ok = FALSE, by_tercile = BYT(0.02, 0.005, 0.005), deep = TRUE, fast = TRUE),
             k4 = list(status = "unmeasured", why = "구간 보유 기여 없음"))
  RR <- list(k1 = list(status = "ok", total = 0.005, recon_ok = TRUE, by_tercile = BYT(0.001, 0.003, 0.001), deep = TRUE, fast = FALSE),
             k2 = list(status = "ok", total = -0.02, recon_ok = TRUE, by_tercile = BYT(-0.01, -0.008, -0.002)),
             k3 = list(status = "ok", total = 0.01, recon_ok = TRUE, by_tercile = BYT(0.005, 0.003, 0.002)),
             k4 = list(status = "ok", total = 0, recon_ok = TRUE, by_tercile = BYT(0, 0, 0)), k5 = list(status = "ok", total = 1))
  PER <- list(V1 = list(status = "ok", cell = "E2_V1", per_crisis = list(k1 = c(RV$k1, list(contract_sum = 0.02, recon_gap = 0, contract_cum = 0.0201)), k4 = RV$k4)),
              RX0 = list(status = "unmeasured", cell = "E2_RX0", why = "RX0 칸 평가 상태 not_measured"))
  BAND <- list(status = "ok", per_crisis = data.table(k = K[1:3], band = c(0.05, 0.2, 0.01)), S_band = 0.03)
  V <- list(rules_computed = TRUE, cell = "E2_V1", rules = list(beta_deep = list(per_crisis = data.table(k = K[1:2], m = c(0.8, 0.6), r = c(0.9, 0.5))),
                                                               fast = list(per_crisis = data.table(k = K[3:4], m = c(0.7, 0.9), r = c(0.72, 0.95)))),
            non_inferiority = list(S = 0.81, S_rx0 = 0.80))
  RS <- list(rules_computed = TRUE, cell = "E2_RX0S", rules = list(crisis = list(per_crisis = data.table(k = K, m = c(0.7, 0.9, 0.8, NA), r = c(0.75, 0.88, 0.95, 0.9)))),
             non_inferiority = list(S = 0.81, S_rx0 = 0.78))
  OUTS <- list(list(device = "V1", seed_tags = list(status = "ok", n_deep_undetermined = 1L, n_fast_undetermined = 0L, S = list(undetermined = TRUE))),
               list(device = "V1", seed_tags = list(status = "unmeasured")), list(device = "V2", seed_tags = list(status = "ok", n_deep_undetermined = 2L, n_fast_undetermined = 1L, S = list(undetermined = FALSE))),
               list(device = "V3"))
  LQA <- list(E2 = list(status = "ok", improvement = list(V1 = list(status = "ok", n_crisis = 2L))), E3 = list(status = "unmeasured", why = "위기 없음"))
  NEST <- list(a = list(path = "x/notes/crisis_type.json", md5 = "aa"), b = list(list(file = "y\\notes\\CRISIS_TYPE.json", md5 = "bb")), c = list(path = "z/other.json", md5 = "cc"),
               d = list(path = c("p", "q"), md5 = "dd"))
  list(
    list(id = "md5_or_na.file", fn = "md5_or_na", args = list(file.path(tmp, ct))), list(id = "md5_or_na.absent", fn = "md5_or_na", args = list(file.path(tmp, "nope.json"))),
    list(id = "md5_or_na.na", fn = "md5_or_na", args = list(NA_character_)),
    list(id = "find_pin.nested", fn = "find_pin", args = list(NEST, "notes/crisis_type.json")), list(id = "find_pin.none", fn = "find_pin", args = list(NEST, "absent.json")),
    list(id = "bins.k3", fn = "bins", args = list(c(1, 5, 10, NA, 20, 31), 1:30, 3)), list(id = "bins.k1", fn = "bins", args = list(c(1, 2), 1:30, 1)),
    list(id = "bins.short", fn = "bins", args = list(c(1, 2), c(1, NA, 3), 3)),
    list(id = "liq_from", fn = "liq_from", args = list(RAW)),
    list(id = "ret_state.default_cal", fn = "ret_state", args = list(RAW, c("B", "A", "Z", "A"), d[3])),
    list(id = "ret_state.given_cal", fn = "ret_state", args = list(RAW, c("C"), d[2], d[seq(1, 30, by = 2)])),
    list(id = "dimson_beta.ok", fn = "dimson_beta", args = list(r, m)), list(id = "dimson_beta.short", fn = "dimson_beta", args = list(r[1:8], m[1:8])),
    list(id = "dimson_beta.mismatch", fn = "dimson_beta", args = list(r, m[-1])), list(id = "dimson_beta.na", fn = "dimson_beta", args = list(replace(r, c(3, 7, 30), NA), m)),
    list(id = "margins.full", fn = "margins", args = list(RL, list(margin = 0.4, t = 2.4, t_min = 2.0), 0.5, 0.02)),
    list(id = "margins.empty", fn = "margins", args = list(list(), list(), 0.5, 0.02)),
    list(id = "load_crisis_types.pinned", fn = "load_crisis_types", args = list(tmp, pin(list(ct, m5(ct))), ct)),
    list(id = "load_crisis_types.nopin", fn = "load_crisis_types", args = list(tmp, list(design_inputs = list()), ct)),
    list(id = "load_crisis_types.otherpin", fn = "load_crisis_types", args = list(tmp, pin(list(ct, "0123")), ct)),
    list(id = "load_crisis_types.twopins", fn = "load_crisis_types", args = list(tmp, pin(list(ct, "0123"), list(paste0("x/", ct), "4567")), ct)),
    list(id = "load_crisis_types.norule", fn = "load_crisis_types", args = list(tmp, pin(list(ct2, m5(ct2))), ct2)),
    list(id = "load_crisis_types.bad", fn = "load_crisis_types", args = list(tmp, pin(list(ct3, m5(ct3))), ct3)),
    list(id = "load_crisis_types.absent", fn = "load_crisis_types", args = list(tmp, pin(list("notes/absent.json", "00")), "notes/absent.json")),
    list(id = "load_crisis_types.eps", fn = "load_crisis_types", args = list(tmp, pin(list(ct, m5(ct))), ct, 0.06)),
    list(id = "load_onset.pinned", fn = "load_onset", args = list(tmp, pin(list(on, m5(on))), on)),
    list(id = "load_onset.mismatch", fn = "load_onset", args = list(tmp, list(design_inputs = list()), on2)),
    list(id = "load_onset.absent", fn = "load_onset", args = list(tmp, list(), "notes/absent.json")),
    list(id = "crisis_type_record.ok", fn = "crisis_type_record", args = list(PC, CL, K[1:2], 0.02, DC, -0.04)),
    list(id = "crisis_type_record.unclassified", fn = "crisis_type_record", args = list(PC, list(status = "unclassified", why = "분류 파일 없음"), K, 0, NULL, NA_real_)),
    list(id = "crisis_type_record.no_pc", fn = "crisis_type_record", args = list(data.table(), CL, K, 0.02, NULL, 0.01)),
    list(id = "crisis_type_record.no_decomp", fn = "crisis_type_record", args = list(PC, CL, character(0), 0)),
    list(id = "liq_tercile_core.ok", fn = "liq_tercile_core", args = list(C5, RG, ADV, U)),
    list(id = "liq_tercile_core.gap", fn = "liq_tercile_core", args = list(C5, RGx, ADV, U)),
    list(id = "liq_tercile_core.no_retg", fn = "liq_tercile_core", args = list(C5, data.table(), ADV, U)),
    list(id = "liq_tercile_core.small_univ", fn = "liq_tercile_core", args = list(C5, RG, ADV, c(1e8, 2e8))),
    list(id = "liq_tercile_core.empty", fn = "liq_tercile_core", args = list(data.table(), RG, ADV, U)),
    list(id = "liq_improvement.mixed", fn = "liq_improvement", args = list(RV, RR, 0.5)), list(id = "liq_improvement.none", fn = "liq_improvement", args = list(list(), RR, 0.5)),
    list(id = "liq_table", fn = "liq_table", args = list(PER, "E2")),
    list(id = "liq_attr_for.hit", fn = "liq_attr_for", args = list(LQA, "E2", "V1")), list(id = "liq_attr_for.cell_missing", fn = "liq_attr_for", args = list(LQA, "E2", "V2")),
    list(id = "liq_attr_for.engine_unmeasured", fn = "liq_attr_for", args = list(LQA, "E3", "V1")), list(id = "liq_attr_for.engine_absent", fn = "liq_attr_for", args = list(LQA, "E4", "V1")),
    list(id = "seed_band.ok", fn = "seed_band", args = list(RS)), list(id = "seed_band.unreadable", fn = "seed_band", args = list(list(rules_computed = FALSE, why = "재시드 칸 측정 실패"))),
    list(id = "seed_band.no_table", fn = "seed_band", args = list(list(rules_computed = TRUE, rules = list(crisis = list())))),
    list(id = "seed_tags.ok", fn = "seed_tags", args = list(V, BAND)),
    list(id = "seed_tags.band_missing_crisis", fn = "seed_tags", args = list(V, list(status = "ok", per_crisis = data.table(k = K[1], band = 0.5), S_band = NA_real_))),
    list(id = "seed_tags.band_unmeasured", fn = "seed_tags", args = list(V, list(status = "unmeasured", why = "재시드 칸 없음"))),
    list(id = "seed_tags.unreadable", fn = "seed_tags", args = list(list(rules_computed = FALSE), BAND)),
    list(id = "seed_tag_counts", fn = "seed_tag_counts", args = list(OUTS, c("V1", "V2"))), list(id = "seed_tag_counts.none", fn = "seed_tag_counts", args = list(OUTS, "V9")))
}
## 사례 실행 → id = JSON 문자열(오류 = "ERROR: <메시지>") · getf(fn 접두) = 실행할 함수
rc_golden_run <- function(cases, getf) setNames(vapply(cases, function(cs) tryCatch(rc_golden_json(do.call(getf(cs$fn), cs$args), RC_GOLDEN_DROP[[cs$fn]] %||% character(0)),
                                                                                   error = function(e) paste("ERROR:", conditionMessage(e))), character(1)),
                                                vapply(cases, `[[`, "", "id"))
## 원판 함수 정의만 꺼낸다(최상위 '이름 <- …' 중 원판 이름 · 보조 상수) — 실행 문장 · source() 는 평가하지 않는다
rc_golden_original <- function(src) {
  ex <- parse(file = src, keep.source = FALSE, encoding = "UTF-8")
  want <- c(vapply(RC_GOLDEN_FNS, `[[`, "", 1L), RC_GOLDEN_SUPPORT)
  O <- new.env(parent = globalenv())
  for (e in ex) if (is.call(e) && identical(e[[1]], as.name("<-")) && is.name(e[[2]]) && as.character(e[[2]]) %in% want) eval(e, O)
  miss <- setdiff(want, ls(O, all.names = TRUE)); if (length(miss)) stop("원판에 없는 정의: ", paste(miss, collapse = ","))
  O
}
if (sys.nframe() == 0L) {
  a <- commandArgs(trailingOnly = TRUE); src <- gsub("\\\\", "/", a[1]); out <- a[2]
  O <- rc_golden_original(src)
  tmp <- file.path(tempdir(), "rc_p2r05_golden"); unlink(tmp, recursive = TRUE)
  cases <- rc_golden_cases(tmp)
  got <- rc_golden_run(cases, function(fn) get(RC_GOLDEN_FNS[[fn]][1], envir = O))
  err <- names(got)[startsWith(got, "ERROR:")]
  G <- list(schema = "round_core_p2r05_golden_v1", source = "04_Research/programs/P2_DEFENSE/P2R05_distribution_target/evaluate.R",
            source_md5 = unname(as.character(tools::md5sum(src))), source_mtime = format(file.info(src)$mtime, "%Y-%m-%dT%H:%M:%S%z"),
            generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), r_version = R.version$version.string,
            packages = list(data.table = as.character(packageVersion("data.table")), jsonlite = as.character(packageVersion("jsonlite"))),
            dropped = RC_GOLDEN_DROP, n_cases = length(got), n_error_cases = length(err), cases = as.list(got))
  writeLines(toJSON(G, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = NA), out, useBytes = TRUE)
  cat(sprintf("[황금값] %d 사례(오류 사례 %d — 원판도 멈추는 입력이면 그 문구가 기준) → %s\n", length(got), length(err), out))
}
