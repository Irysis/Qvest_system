#==============================================================================
# test_seam_scale_guard.R — 수출본 이음매 레벨 연속성 가드 검사기 (합성 픽스처)
#
# 2026-09-07 신설 (도훈 승인 A안). 운영 상태(.cache/rawdata.parquet · 원장)를 **빌리지
# 않는다** — 픽스처는 전부 합성이고 사이드카는 tempdir 로 나간다
# (feedback-a-test-that-borrows-live-state-flaps-when-you-fix-the-state).
#
# 검사 축:
#   ① 정상 이음매(비율 ~1) → 무처치 + 상한가 1.30 오검거 없음
#   ② x5 분할 주입 → 검거 + 처분 + 사유 기록(사이드카 도달)
#   ③ x0.2 역수 → 검거
#   ④ 한쪽에만 있는 종목 → "정상" 아닌 별도 사유(no_anchor / absent_at_seam)
#   ⑤ 가드 제거 변이 → 빨강 (검출력 실증 — 양성 대조 + 위반 주입)
#   ⑥ 벤치 경로와 어휘 일치 (같은 상수·같은 판정 이름을 **재도출**)
#   ⑦ 배관 도달 — 두 배관이 가드를 **부르는가**(AST 로 재도출, grep 아님)
#   ⑧ 문턱이 설정 경유인가 (설정을 바꾸면 판정이 따라 바뀐다 = 하드코딩 부재 실증)
#   ⑨ 창 스캔 — 이음매 당일이 정지값이라 단절이 하루 뒤에 나타나는 종목을 잡는가
#   ⑩⑪ 배관 블록 실구동 — 두 배관의 가드 구간을 잘라 합성 픽스처 위에서 eval
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })

# ★러너는 self-first (r-portability ④-b) — 자기가 실린 트리를 검사한다
.t_root <- function() {
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", a[grepl("^--file=", a)])
  cands <- character(0)
  if (length(f)) cands <- c(cands, normalizePath(file.path(dirname(f[1]), "..", ".."), mustWork = FALSE))
  cands <- c(cands, Sys.getenv("CLAUDE_PROJECT_DIR", unset = ""), Sys.getenv("QM_ROOT", unset = ""), getwd())
  cands <- gsub("\\\\", "/", cands[nzchar(cands)])
  hit <- cands[file.exists(file.path(cands, "02_Infrastructure/hooks/qvest_hook_router.py"))]
  if (!length(hit)) stop("project root 미발견")
  hit[1]
}
PROJ <- .t_root(); setwd(PROJ)
PASS <- 0L; FAIL <- 0L
ok  <- function(n, m = "") { PASS <<- PASS + 1L; cat(sprintf("  PASS: %s%s\n", n, if (nzchar(m)) paste0(" — ", m) else "")) }
bad <- function(n, m = "") { FAIL <<- FAIL + 1L; cat(sprintf("  FAIL: %s — %s\n", n, m)) }
cat("=== seam scale guard (합성 픽스처) ===\n")

GUARD <- file.path(PROJ, "02_Infrastructure/data/seam_scale_guard.R")
CFGP  <- file.path(PROJ, "02_Infrastructure/data/seam_guard_config.json")
BENCH <- file.path(PROJ, "02_Infrastructure/data/naver_benchmark_update.py")
TMPD  <- file.path(tempdir(), paste0("seamtest_", as.integer(Sys.time())))
dir.create(TMPD, recursive = TRUE, showWarnings = FALSE)

source(GUARD)
cfg <- seam_guard_config(reload = TRUE)

# ── 합성 픽스처 ──────────────────────────────────────────────────────────────
# base 3세션 + update 5세션. update 쪽만 조정기준이 다른 종목을 심는다.
DB <- as.Date(c("2026-03-25", "2026-03-26", "2026-03-27"))          # base
DU <- as.Date(c("2026-03-30", "2026-03-31", "2026-04-01", "2026-04-02", "2026-04-03"))
SEAM <- DU[1]

mkfx <- function() {
  row <- function(tk, dates, cl, src) data.table(Date = dates, Ticker = tk,
                                                 Close = as.numeric(cl), source = src)
  rbindlist(list(
    # ① 정상 — 이음매 비율 1.0098
    row("NORM", DB, c(100, 101, 102), "base"), row("NORM", DU, c(103, 104, 105, 106, 107), "upd"),
    # ① 상한가 +30% — 진짜 등락이므로 오검거되면 안 된다
    row("LIMIT", DB, c(100, 101, 102), "base"), row("LIMIT", DU, c(132.6, 133, 134, 135, 136), "upd"),
    # ② x5 분할 기준 단절 (그날 실수익률 -1.47%)
    row("SPLIT5", DB, c(100, 101, 102), "base"), row("SPLIT5", DU, c(502.5, 505, 508, 510, 512), "upd"),
    # ③ x0.2 역수(액면병합)
    row("REV5", DB, c(1000, 1010, 1020), "base"), row("REV5", DU, c(201, 202, 203, 204, 205), "upd"),
    # ④-a update 에만 존재 (앵커 없음)
    row("NEWLIST", DU, c(50, 51, 52, 53, 54), "upd"),
    # ④-b base 에만 존재 (이음매에서 사라짐)
    row("GONE", DB, c(10, 11, 12), "base"),
    # 정수배 지문 없음 → unattributed
    row("ODD", DB, c(100, 101, 102), "base"), row("ODD", DU, c(245, 246, 247, 248, 249), "upd"),
    # ⑨ 이음매 당일은 정지값(102 그대로) → 단절이 하루 뒤(03-31)에 나타난다
    row("LATE", DB, c(100, 101, 102), "base"), row("LATE", DU, c(102, 510, 512, 514, 516), "upd")
  ))
}

fx <- mkfx()
rep <- seam_scan_report(fx, seam_scan_dates(fx, SEAM, cfg), cfg)
V <- function(r, tk, d = SEAM) r$tbl[Ticker == tk & (is.na(Date) | Date == d)]

# ── ① 정상 이음매 ────────────────────────────────────────────────────────────
n <- V(rep, "NORM"); l <- V(rep, "LIMIT")
if (nrow(n) == 1 && n$verdict == "on_scale" && n$action == "none" &&
    nrow(l) == 1 && l$verdict == "on_scale" && l$action == "none") {
  ok("normal_seam_untouched", "비율 1.0098 + 상한가 1.30 둘 다 on_scale/none")
} else {
  bad("normal_seam_untouched", sprintf("NORM=%s/%s LIMIT=%s/%s",
      paste(n$verdict, collapse = ","), paste(n$action, collapse = ","),
      paste(l$verdict, collapse = ","), paste(l$action, collapse = ",")))
}

# ── ② x5 분할 검거 + 처분 + 사유 기록 ────────────────────────────────────────
s <- V(rep, "SPLIT5")
if (nrow(s) == 1 && s$verdict == "adjustment_basis_break" &&
    isTRUE(all.equal(s$canonical_scale, 5)) && s$action == "rescale_ret" &&
    abs(s$implied_ret - (502.5 / 102 / 5 - 1)) < 1e-12) {
  ok("split_x5_caught", sprintf("scale=5 implied_ret=%.5f action=rescale_ret", s$implied_ret))
} else {
  bad("split_x5_caught", sprintf("verdict=%s scale=%s action=%s",
      paste(s$verdict, collapse = ","), paste(s$canonical_scale, collapse = ","),
      paste(s$action, collapse = ",")))
}

# ── ③ x0.2 역수 검거 ─────────────────────────────────────────────────────────
r5 <- V(rep, "REV5")
if (nrow(r5) == 1 && r5$verdict == "adjustment_basis_break" &&
    isTRUE(all.equal(r5$canonical_scale, 0.2))) {
  ok("reverse_x0.2_caught", sprintf("scale=%.3f", r5$canonical_scale))
} else {
  bad("reverse_x0.2_caught", sprintf("verdict=%s scale=%s",
      paste(r5$verdict, collapse = ","), paste(r5$canonical_scale, collapse = ",")))
}

# ── ④ 한쪽에만 있는 종목 = "정상" 아닌 별도 사유 ─────────────────────────────
nl <- V(rep, "NEWLIST"); gn <- rep$tbl[Ticker == "GONE"]
cond_nl <- nrow(nl) == 1 && nl$verdict == "no_anchor" && nl$action == "block_ret"
cond_gn <- nrow(gn) == 1 && gn$verdict == "absent_at_seam" && gn$action == "no_measure"
if (cond_nl && cond_gn) {
  ok("one_sided_gets_own_reason", "NEWLIST=no_anchor(block) · GONE=absent_at_seam(no_measure)")
} else {
  bad("one_sided_gets_own_reason", sprintf("NEWLIST=%s/%s GONE=%s/%s (둘 다 on_scale 로 흡수되면 안 됨)",
      paste(nl$verdict, collapse = ","), paste(nl$action, collapse = ","),
      paste(gn$verdict, collapse = ","), paste(gn$action, collapse = ",")))
}

# 정수배 지문 없음 → unattributed_jump(차단)
od <- V(rep, "ODD")
if (nrow(od) == 1 && od$verdict == "unattributed_jump" && od$action == "block_ret") {
  ok("unattributed_blocked", "정수배로 안 붙는 단절은 배율을 지어내지 않고 차단")
} else {
bad("unattributed_blocked", sprintf("verdict=%s action=%s",
     paste(od$verdict, collapse = ","), paste(od$action, collapse = ",")))
}

# ── ⑨ 창 스캔 — 단절이 하루 뒤에 나타나는 종목 ───────────────────────────────
lt <- rep$tbl[Ticker == "LATE" & !is.na(Date) & Date == DU[2]]
lt0 <- V(rep, "LATE")
if (nrow(lt) == 1 && lt$verdict == "adjustment_basis_break" &&
    isTRUE(all.equal(lt$canonical_scale, 5)) && nrow(lt0) == 1 && lt0$verdict == "on_scale") {
  ok("late_manifesting_break_caught", "이음매 당일은 정지값(on_scale)이고 단절은 03-31 에서 검거")
} else {
  bad("late_manifesting_break_caught",
      sprintf("D+1=%s (하루만 보면 놓치는 자리)", paste(lt$verdict, collapse = ",")))
}

# ── 처분 적용 (Ret 재계산 → 가드 적용) ───────────────────────────────────────
run_pipe <- function(fx, use_guard = TRUE, cfg_ = cfg) {
  d <- copy(fx)
  rp <- if (use_guard) seam_scan_report(d, seam_scan_dates(d, SEAM, cfg_), cfg_) else NULL
  setorder(d, Ticker, Date)
  d[, Ret := Close / shift(Close) - 1, by = Ticker]
  if (!is.null(rp)) d <- seam_apply_actions(d, rp)
  list(dt = d, rep = rp)
}
g <- run_pipe(fx, TRUE)
getret <- function(d, tk, dd = SEAM) d$dt[Ticker == tk & Date == dd, Ret]

if (is.na(getret(g, "ODD")) && is.na(getret(g, "NEWLIST")) &&
    abs(getret(g, "SPLIT5") - (502.5 / 102 / 5 - 1)) < 1e-12 &&
    abs(getret(g, "NORM") - (103 / 102 - 1)) < 1e-12) {
  ok("actions_applied_to_ret", "block→NA · rescale→조정계수 나눈 값 · 정상행 불변")
} else {
  bad("actions_applied_to_ret", sprintf("ODD=%s NEWLIST=%s SPLIT5=%s",
      getret(g, "ODD"), getret(g, "NEWLIST"), getret(g, "SPLIT5")))
}

# 사고 반경: 이음매 밖 행은 한 값도 안 바뀐다
b <- run_pipe(fx, FALSE)
off <- g$dt[!Date %in% as.Date(rep$dates)]
offb <- b$dt[!Date %in% as.Date(rep$dates)]
setorder(off, Ticker, Date); setorder(offb, Ticker, Date)
if (isTRUE(all.equal(off$Ret, offb$Ret))) {
  ok("blast_radius_confined", "판정 창 밖 Ret 전량 불변")
} else {
bad("blast_radius_confined", "가드가 창 밖 행을 건드렸다")
}

# ── ② 사유 기록 도달 (사이드카) ──────────────────────────────────────────────
sc <- seam_write_sidecar(g$rep, "unittest", dir_ = TMPD)
js <- jsonlite::fromJSON(sc)
tk <- as.data.table(js$tickers)
if (file.exists(sc) && nrow(tk[Ticker == "SPLIT5" & verdict == "adjustment_basis_break"]) == 1 &&
    nrow(tk[Ticker == "NEWLIST" & verdict == "no_anchor"]) == 1 &&
    nrow(tk[Ticker == "GONE" & verdict == "absent_at_seam"]) == 1 &&
    !is.null(js$verdict_counts) && !is.null(js$config)) {
  ok("sidecar_records_reasons", sprintf("%d종 기록 + verdict_counts + config", nrow(tk)))
} else {
  bad("sidecar_records_reasons", "사이드카에 종목·사유·설정이 남지 않음 (조용한 통과)")
}
if (nrow(tk[verdict == "on_scale"]) == 0) {
  ok("sidecar_excludes_on_scale", "정상행은 안 싣는다")
} else {
bad("sidecar_excludes_on_scale", "on_scale 이 실렸다")
}

# ── ⑤ 가드 제거 변이 → 빨강 (검출력 실증) ────────────────────────────────────
# (a) 양성 대조: 가드 없이 돌리면 오염이 그대로 살아남아야 한다
mut_a <- abs(b$dt[Ticker == "SPLIT5" & Date == SEAM, Ret] - (502.5 / 102 - 1)) < 1e-12 &&
         abs(b$dt[Ticker == "ODD" & Date == SEAM, Ret] - (245 / 102 - 1)) < 1e-12
# (b) 처분표 무력화 변이: 전부 "none" 으로 바꾸면 오염이 통과해야 한다
mut_b <- local({
  e <- new.env(parent = globalenv())
  sys.source(GUARD, envir = e)
  assign("seam_action_for", function(verdict, cfg = NULL) rep("none", length(verdict)), envir = e)
  d <- copy(fx)
  rp <- e$seam_scan_report(d, e$seam_scan_dates(d, SEAM, cfg), cfg)
  setorder(d, Ticker, Date); d[, Ret := Close / shift(Close) - 1, by = Ticker]
  d <- e$seam_apply_actions(d, rp)
  abs(d[Ticker == "SPLIT5" & Date == SEAM, Ret] - (502.5 / 102 - 1)) < 1e-12
})
if (mut_a && mut_b) {
  ok("guard_removal_mutation_reddens", "가드 제거·처분표 무력화 둘 다 오염이 살아남음 = 검출력 실증")
} else {
  bad("guard_removal_mutation_reddens",
      sprintf("변이가 무해했다(a=%s b=%s) — 검사가 가드를 재고 있지 않다", mut_a, mut_b))
}

# ── ⑧ 문턱이 설정 경유인가 (하드코딩 부재 실증) ──────────────────────────────
mut_cfg <- local({
  cf <- jsonlite::fromJSON(CFGP)
  cf$rescale_ret_enabled <- FALSE          # 설정만 바꾼다
  p2 <- file.path(TMPD, "cfg_norescale.json")
  writeLines(jsonlite::toJSON(cf, auto_unbox = TRUE), p2, useBytes = TRUE)
  c2 <- seam_guard_config(p2, reload = TRUE)
  r2 <- seam_scan_report(fx, seam_scan_dates(fx, SEAM, c2), c2)
  r2$tbl[Ticker == "SPLIT5" & Date == SEAM, action]
})
mut_tol <- local({
  cf <- jsonlite::fromJSON(CFGP)
  cf$SEAM_MAX_RET <- 5.0                   # 상한을 올리면 x5 도 '정상 등락' 이 된다
  p3 <- file.path(TMPD, "cfg_looset.json")
  writeLines(jsonlite::toJSON(cf, auto_unbox = TRUE), p3, useBytes = TRUE)
  c3 <- seam_guard_config(p3, reload = TRUE)
  r3 <- seam_scan_report(fx, seam_scan_dates(fx, SEAM, c3), c3)
  r3$tbl[Ticker == "SPLIT5" & Date == SEAM, verdict]
})
if (identical(mut_cfg, "block_ret") && identical(mut_tol, "on_scale")) {
  ok("thresholds_come_from_config", "rescale kill switch·SEAM_MAX_RET 둘 다 판정을 움직인다")
} else {
  bad("thresholds_come_from_config",
      sprintf("설정 변경이 판정을 안 움직임 (action=%s verdict=%s) — 값이 코드에 박혀 있다",
              mut_cfg, mut_tol))
}
invisible(seam_guard_config(CFGP, reload = TRUE))   # 정본 재적재 (최상위 자동출력 억제)

# 설정 부재 = 조용한 기본값이 아니라 stop
miss <- tryCatch({ seam_guard_config(file.path(TMPD, "no_such.json"), reload = TRUE); "no_stop" },
                 error = function(e) conditionMessage(e))
if (grepl("설정 부재", miss, fixed = TRUE)) {
  ok("missing_config_stops", "폴백 기본값으로 내려앉지 않는다")
} else {
bad("missing_config_stops", sprintf("결과: %s", substr(miss, 1, 60)))
}

# ── ⑥ 벤치 경로와 어휘 일치 (재도출) ─────────────────────────────────────────
bench <- readLines(BENCH, warn = FALSE)
py_reads_cfg <- any(grepl("seam_guard_config.json", bench, fixed = TRUE))
# 벤치가 실제로 **같은 값**을 얻는가 — 문자열이 아니라 실행으로 재도출
py <- Sys.getenv("QVEST_PY", unset = "")
pyx <- file.path(PROJ, ".venv_qvest_ml/Scripts/python.exe")
py <- if (file.exists(pyx)) pyx else py
py_vals <- NULL
if (nzchar(py) && file.exists(py)) {
  code <- paste0("import sys;sys.path.insert(0,'02_Infrastructure/data');",
                 "import naver_benchmark_update as m;",
                 "print(m.SEAM_MAX_RET, m.SCALE_TOL, m.SCALE_LOOKBACK_DAYS)")
  o <- suppressWarnings(system2(py, c("-c", shQuote(code)), stdout = TRUE, stderr = TRUE))
  st <- attr(o, "status"); if (is.null(st)) st <- 0L
  if (st == 0L) py_vals <- as.numeric(strsplit(trimws(tail(o, 1)), " +")[[1]])
}
if (py_reads_cfg && !is.null(py_vals) && length(py_vals) == 3 &&
    isTRUE(all.equal(py_vals[1], as.numeric(cfg$SEAM_MAX_RET))) &&
    isTRUE(all.equal(py_vals[2], as.numeric(cfg$SCALE_TOL))) &&
    isTRUE(all.equal(py_vals[3], as.numeric(cfg$SCALE_LOOKBACK_DAYS)))) {
  ok("bench_shares_constants", sprintf("py SEAM_MAX_RET=%.4g == R %.4g (같은 정본 파일)",
                                       py_vals[1], as.numeric(cfg$SEAM_MAX_RET)))
} else {
  bad("bench_shares_constants",
      sprintf("벤치가 정본을 안 읽거나 값이 갈림 (reads_cfg=%s py=%s) — 한쪽만 고쳐지는 자리",
              py_reads_cfg, paste(py_vals, collapse = "/")))
}
# 판정 어휘: 벤치의 이름이 R 쪽에도 살아 있는가
gsrc <- paste(readLines(GUARD, warn = FALSE), collapse = "\n")
vocab <- c("canonical_scale", "anchor_date", "anchor_close", "SEAM_MAX_RET",
           "SCALE_TOL", "SCALE_LOOKBACK_DAYS")
missing_vocab <- vocab[!vapply(vocab, function(v)
  grepl(v, gsrc, fixed = TRUE) && any(grepl(v, bench, fixed = TRUE)), logical(1))]
if (!length(missing_vocab)) {
  ok("shared_vocabulary", paste(vocab, collapse = " "))
} else {
bad("shared_vocabulary", sprintf("두 배관에 공통으로 없는 이름: %s",
                                      paste(missing_vocab, collapse = ", ")))
}

# ── ⑦ 배관 도달 — **부르는가** (AST 재도출, 소스 좌표·grep 아님) ─────────────
calls_in_fn <- function(path, fn_name) {
  ex <- parse(path)
  found <- character(0)
  walk <- function(e) {
    if (is.call(e)) { h <- e[[1]]; if (is.name(h)) found <<- c(found, as.character(h)) }
    if (is.recursive(e)) for (i in seq_along(e)) if (!is.null(e[[i]])) try(walk(e[[i]]), silent = TRUE)
  }
  for (i in seq_along(ex)) {
    e <- ex[[i]]
    if (is.call(e) && length(e) >= 3 && as.character(e[[1]]) %in% c("<-", "=") &&
        identical(as.character(e[[2]]), fn_name)) walk(e[[3]])
  }
  unique(found)
}
# ★2026-09-07 표적 이설: naver 배관의 가드 소비자가 naver_merge_rawdata →
#   .naver_seam_verify 로 바뀌었다(수집 경로가 수정주가 siseJson 으로 교체되며 구
#   병합기가 사라짐). 이름을 적어 둔 검사는 리팩터가 옮기는 좌표를 못박는다 —
#   그래서 **진입점에서 사슬을 재도출**한다: backfill → seam_verify → 가드 원어.
NAVSRC <- file.path(PROJ, "02_Infrastructure/data/naver_data_collector.R")
c_incr <- calls_in_fn(file.path(PROJ, "02_Infrastructure/data/incremental_update_file.R"), "incremental_ohlcvs")
c_entry <- calls_in_fn(NAVSRC, "naver_backfill_range")
c_nav  <- calls_in_fn(NAVSRC, ".naver_seam_verify")
need_i <- c("seam_scan_report", "seam_apply_actions", "seam_write_sidecar")
need_n <- c("seam_classify_pair", "seam_action_for")
mi <- setdiff(need_i, c_incr); mn <- setdiff(need_n, c_nav)
reached <- ".naver_seam_verify" %in% c_entry
if (!length(mi) && !length(mn) && reached) {
  ok("both_pipes_call_guard", "incremental_ohlcvs · naver_backfill_range→.naver_seam_verify 둘 다 가드 도달")
} else {
  bad("both_pipes_call_guard", sprintf("미호출 — incremental:{%s} naver:{%s} entry_reaches=%s",
      paste(mi, collapse = ","), paste(mn, collapse = ","), reached))
}

# ── ⑩⑪ 배관 블록 **실구동** — "붙였다" 가 아니라 "돈다" 를 잰다 ────────────────
#   AST(축 ⑦)는 호출이 적혀 있음을 보이지만, 그 블록 안의 색인·처분 코드가 실제로
#   Ret 을 옳게 바꾸는지는 못 본다(실제로 naver 쪽에서 부분집합 문맥 색인 결함을 한 번
#   냈다). 의미 앵커로 블록을 잘라 합성 픽스처 위에서 eval 한다 — 앵커가 사라지면
#   추출이 실패하고 그 자체가 빨강이다(가드를 걷어내면 이 축이 죽는 방향이 옳다).
cut_block <- function(path, start_pat, end_pat) {
  ln <- readLines(path, warn = FALSE)
  i <- which(vapply(ln, function(x) grepl(start_pat, x, fixed = TRUE), logical(1)))
  j <- which(vapply(ln, function(x) grepl(end_pat, x, fixed = TRUE), logical(1)))
  if (!length(i) || !length(j)) return(NULL)
  j <- j[j > i[1]]
  if (!length(j)) return(NULL)
  paste(ln[i[1]:(j[1] - 1L)], collapse = "\n")
}

# ⑩ incremental_ohlcvs 의 가드 구간 (판정 → Ret 재계산 → 처분)
blk_i <- cut_block(file.path(PROJ, "02_Infrastructure/data/incremental_update_file.R"),
                   "[guard 2026-09-07", "# BM_Ret 매핑")
if (is.null(blk_i)) {
  bad("incremental_block_runs", "가드 블록을 의미 앵커로 못 찾음 (제거됐거나 앵커 소실)")
} else {
  e <- new.env(parent = globalenv())
  assign("raw", copy(fx), envir = e)
  assign("update_dates", DU, envir = e)
  # ★2026-09-07 저녁: 블록이 경계를 `source` 전환점 차집합에서 **재도출**하게 바뀌었다.
  #   교체 전 source 지도(.src_before)는 이 블록 앞에서 만들어지므로 픽스처가 공급한다.
  #   안 주면 블록은 fail-safe 로 min(update_dates) 에 후퇴하고 그 후퇴가 초록으로 보인다.
  assign(".src_before", copy(fx)[, .(Date, source)], envir = e)
  assign("DATA_DIR", file.path(PROJ, "02_Infrastructure/data"), envir = e)
  sc_calls <- 0L
  assign("seam_write_sidecar", function(rep, label, ...) {
    sc_calls <<- sc_calls + 1L; file.path(TMPD, "stub.json") }, envir = e)
  r <- tryCatch({ eval(parse(text = blk_i), envir = e); "ok" },
                error = function(z) conditionMessage(z))
  d <- get("raw", envir = e)
  gr <- function(tk) d[Ticker == tk & Date == SEAM, Ret]
  if (identical(r, "ok") && sc_calls == 1L && is.na(gr("ODD")) &&
      abs(gr("SPLIT5") - (502.5 / 102 / 5 - 1)) < 1e-12 &&
      abs(gr("NORM") - (103 / 102 - 1)) < 1e-12) {
    # ★같은 블록에서 처분 호출만 지운 변이는 오염이 살아남아야 한다 — 이 축이
    #   "블록이 돈다" 를 재고 있는지(아니면 그냥 초록인지) 자기 실증한다.
    mut <- local({
      # ★변이는 **이름을 적어 지우지 않는다** — 처분 함수 자체를 무력화한다.
      #   구판은 소스 문자열 `raw <- seam_apply_actions(raw, seam_rep)` 를 치환했는데,
      #   러너가 다중 이음매 루프로 바뀌자 그 문자열이 사라져 변이가 조용히 no-op 이 됐다
      #   (소스 텍스트 단정은 리팩터가 옮기는 좌표를 못박는다 — 2026-09-05 카드).
      #   소비 지점(함수 이름)을 가리면 러너가 어떻게 바뀌어도 변이가 성립한다.
      em <- new.env(parent = globalenv())
      assign("raw", copy(fx), envir = em); assign("update_dates", DU, envir = em)
      assign(".src_before", copy(fx)[, .(Date, source)], envir = em)
      assign("DATA_DIR", file.path(PROJ, "02_Infrastructure/data"), envir = em)
      assign("seam_write_sidecar", function(...) "", envir = em)
      assign("seam_apply_actions", function(dt, rep) dt, envir = em)
      tryCatch({ eval(parse(text = blk_i), envir = em)
        dm <- get("raw", envir = em)
        abs(dm[Ticker == "SPLIT5" & Date == SEAM, Ret] - (502.5 / 102 - 1)) < 1e-12
      }, error = function(z) FALSE)
    })
    if (mut) ok("incremental_block_runs", "블록 실행 → 오염 차단/재정렬 + 사이드카 1회 + 처분 제거 변이는 오염 생존")
    else bad("incremental_block_runs", "처분 호출을 지워도 오염이 사라짐 — 이 축이 블록을 재고 있지 않다")
  } else {
    bad("incremental_block_runs",
        sprintf("err=%s sidecar=%d ODD=%s SPLIT5=%s", substr(r, 1, 60), sc_calls,
                gr("ODD"), gr("SPLIT5")))
  }
}

# ⑪ naver 배관의 가드 소비자 **실구동** — 함수를 AST 로 뽑아 합성 픽스처 위에서 돌린다.
#   ★2026-09-07 재작성: 소스 텍스트 앵커(cut_block) 대신 **정의 자체를 재도출**한다.
#   새 경로는 첫 naver 일의 직전 종가도 naver 에서 받으므로 Ret 이 **측정값**이다 —
#   가드는 그 값을 덮지 않고 대조한다(seam_mode=verify). 그래서 이 축이 재는 명제는
#   "가드가 Ret 을 고쳤나" 가 아니라 "가드가 판정을 내고 측정값과의 일치를 남기나" 다.
extract_fn <- function(path, fn_name) {
  ex <- parse(path)
  for (i in seq_along(ex)) {
    e <- ex[[i]]
    if (is.call(e) && length(e) >= 3 && as.character(e[[1]]) %in% c("<-", "=") &&
        identical(as.character(e[[2]]), fn_name)) return(e)
  }
  NULL
}
fdef <- extract_fn(NAVSRC, ".naver_seam_verify")
if (is.null(fdef)) {
  bad("naver_block_runs", ".naver_seam_verify 정의를 AST 에서 못 찾음 (제거됐거나 개명)")
} else {
  e2 <- new.env(parent = globalenv())
  assign("DATA_DIR", file.path(PROJ, "02_Infrastructure/data"), envir = e2)
  # 설정 의존을 격리 — 운영 설정을 빌리지 않는다
  assign("naver_collector_config", function(...) list(seam_verify_tol = 1e-6), envir = e2)
  eval(fdef, envir = e2)
  fn <- get(".naver_seam_verify", envir = e2)
  # 픽스처: 정상 · x5 분할(측정 Ret 이 implied 와 일치) · 정수배 아닌 급등 · 앵커 부재
  first <- data.table(
    Ticker = c("NORM", "SPLIT5", "ODD", "NEWLIST"),
    Close  = c(103, 502.5, 245, 50),
    Ret    = c(103 / 102 - 1, 502.5 / 102 / 5 - 1, 245 / 102 - 1, NA_real_))
  r2 <- tryCatch(fn(c(102, 102, 102, NA_real_), first$Ticker, first),
                 error = function(z) conditionMessage(z))
  if (!is.data.table(r2)) {
    bad("naver_block_runs", sprintf("실행 실패: %s", substr(paste(r2, collapse = " "), 1, 80)))
  } else {
    gv <- function(tk, col) r2[Ticker == tk][[col]][1]
    cond <- identical(gv("NORM", "verdict"), "on_scale") &&
      identical(gv("SPLIT5", "verdict"), "adjustment_basis_break") &&
      isTRUE(gv("SPLIT5", "agrees")) &&                       # 가드 추정 == 내부 측정
      identical(gv("SPLIT5", "action"), "rescale_ret") &&
      identical(gv("ODD", "verdict"), "unattributed_jump") &&
      identical(gv("NEWLIST", "verdict"), "no_anchor")
    if (cond) ok("naver_block_runs",
                 "판정 4종 + 분할 칸에서 가드 implied_ret == naver 내부 측정 Ret (양성 대조)")
    else bad("naver_block_runs", sprintf("NORM=%s SPLIT5=%s/%s ODD=%s NEWLIST=%s",
             gv("NORM", "verdict"), gv("SPLIT5", "verdict"), gv("SPLIT5", "agrees"),
             gv("ODD", "verdict"), gv("NEWLIST", "verdict")))
  }
}

unlink(TMPD, recursive = TRUE)
cat(sprintf("TOTAL: %d pass / %d fail / 0 skipped\n", PASS, FAIL))
cat(jsonlite::toJSON(list(test = "seam_scale_guard", pass = PASS, fail = FAIL,
                          skipped = 0L, total = PASS + FAIL, skips = list()),
                     auto_unbox = TRUE), "\n", sep = "")
if (FAIL > 0) quit(status = 1)
