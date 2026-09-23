#==============================================================================
# test_rawdata_bm_ret_sync.R — W-09 RAWDATA.BM_Ret 단일 writer 상설 검사
#
# 사고(2026-09-23 W-09): naver 일간 경로가 행을 append 하며 BM_Ret 을 안 채워 2026-09-07~
#   전량 결측(MA06 소실 · C18 332→110행). 2025-01-02 · 2026-09-02 는 벤치와 불일치.
#   BM_Ret writer 가 5곳에 흩어져 서로 다른 정의(자체계산·0 센티널·전열 재조인·NA 행 삭제)를 썼다.
#
# 축 (양성 대조 + 위반 주입 + 돌연변이 통제):
#   A 계획      — 합성 RAWDATA+벤치에서 fill/overwrite/protected/bench_lag/거부 분류
#   B 쓰기      — 결측 채움·정본 일치 · 다른 열·행 순서·형 불변 · 보호 날짜 불변 · 로그는 픽스처 안
#   C 위반 주입 — 독립 오라클이 (벤치 없는 날 채움 / 다른 열 변경 / 토요장·2024-12-30 변경)을 red 로 잡는다
#                 + 쓰기기 돌연변이(지연일 추정 채움 · 다른 열 건드림 · 보호 해제 · 동시 writer)가 실제로 red
#   D 킬스위치  — enabled=true 면 덮어쓰기 거부·채움 허용 · 부재 = 허용 · 광기값·상한·벤치 결손 = 위반
#   E 메모리 API — rawdata_bm_ret_sync_dt (BM_Ret 열 부재 → 생성·채움)
#   F 배선      — daily_refresh.sh 의 실제 [3b] 블록: [1]/[2]/[3] 뒤 · [6a] 앞 · 스텁 rc 별 DR_FAILED 적재 ·
#                 적재 줄 삭제 돌연변이 = 침묵 · 실제 Rscript 로 격리 루트 end-to-end
#   G 경로 정리 — 옛 writer 들이 전열 재조인·자체계산·0 센티널·NA 행 삭제를 더는 하지 않고 단일 writer 를 부른다
#
# 운영 산출물 무접촉 — 전부 tempdir() 아래 픽스처. 자식 Rscript 는 빈 R_ENVIRON_USER 로 격리.
# 요약 규약: 마지막 줄 {"test":"rawdata_bm_ret_sync","pass":N,"fail":N,"total":N}
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite); library(arrow) })

.MARKER <- "02_Infrastructure/data/rawdata_bm_ret_sync.R"
.script_dir <- function() {
  m <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
  if (!length(m)) return("")
  dirname(sub("^--file=", "", m[1L]))
}
.sd <- .script_dir()
PROJ <- ""
for (.c in c(Sys.getenv("QM_ROOT", ""), Sys.getenv("CLAUDE_PROJECT_DIR", ""),
             if (nzchar(.sd)) file.path(.sd, "..", "..") else "", getwd())) {
  .c <- gsub("\\\\", "/", .c)
  if (nzchar(.c) && file.exists(file.path(.c, .MARKER))) { PROJ <- .c; break }
}
if (!nzchar(PROJ)) stop("[test_rawdata_bm_ret_sync] 루트 해석 실패 — 표지 부재: ", .MARKER)

PASS <- 0L; FAIL <- 0L
ok  <- function(n, m = "") { PASS <<- PASS + 1L; cat(sprintf("  PASS: %s - %s\n", n, m)) }
bad <- function(n, m = "") { FAIL <<- FAIL + 1L; cat(sprintf("  FAIL: %s - %s\n", n, m)) }
chk <- function(n, cond, m = "") if (isTRUE(cond)) ok(n, m) else bad(n, m)

FX <- gsub("\\\\", "/", file.path(tempdir(), "bmsync_fx"))
unlink(FX, recursive = TRUE); dir.create(FX, recursive = TRUE)
fin <- function() {
  unlink(FX, recursive = TRUE)
  cat(sprintf("TOTAL: %d pass / %d fail\n", PASS, FAIL))
  cat(toJSON(list(test = "rawdata_bm_ret_sync", pass = PASS, fail = FAIL, total = PASS + FAIL),
             auto_unbox = TRUE), "\n")
  quit(save = "no", status = if (FAIL > 0L) 1L else 0L)
}

SRC <- file.path(PROJ, .MARKER)
CFG_PATH <- file.path(PROJ, "02_Infrastructure/data/rawdata_bm_ret_sync_config.json")
E <- new.env()
sys.source(SRC, envir = E)   # 운영 전역 오염 없이 로드
# sys.source 는 ofile 을 안 남긴다 — 설정·유틸 경로를 명시로 준다
E$.BMS_SELF_DIR <- file.path(PROJ, "02_Infrastructure/data")
CFG <- E$rawdata_bm_ret_sync_config(CFG_PATH)

#──────────────────────────────────────────────────────────────────────────────
# 픽스처 — 합성 RAWDATA + 벤치
#──────────────────────────────────────────────────────────────────────────────
D <- function(x) as.Date(x)
bench_fx <- data.table(
  Date   = D(c("1998-12-04", "1998-12-07", "2024-12-27", "2024-12-30", "2025-01-02",
               "2026-09-01", "2026-09-02", "2026-09-03", "2026-09-04")),
  BM_Close = c(100, 101, 319.03, 317.82, 317.77, 1075.30, 1031.53, 1032.82, 1051.52),
  BM_Ret = c(0.001, 0.002, -0.0075283870, -0.0037927468, -0.0039494718,
             0.0032187340, -0.0407049196, 0.0012505695, 0.0181057687))
raw_dates <- D(c("1998-12-04", "1998-12-07", "2024-12-27", "2024-12-30", "2025-01-02",
                 "2026-09-01", "2026-09-02", "2026-09-03", "2026-09-04", "2026-09-07"))
raw_bm <- c(NA, 0.0055, -0.0075283870, NA, -0.0001573218,
            0.0032187340, -0.0382032921, NA, NA, NA)
mk_raw <- function() {
  set.seed(7)
  tk <- c("A000010", "A000020", "A000030")
  r <- CJ(Date = raw_dates, Ticker = tk)
  r[, BM_Ret := raw_bm[match(Date, raw_dates)]]
  r[, `:=`(Name = paste0("nm_", Ticker), source = "naver", K200 = 1,
           Close = round(runif(.N, 1000, 5000)), Ret = rnorm(.N, 0, 0.02), Size = runif(.N, 1e9, 1e10))]
  setcolorder(r, c("Date", "Ticker", "Name", "K200", "Close", "Size", "Ret", "source", "BM_Ret"))
  r[sample(.N)]            # 행 순서 섞기 — writer 가 재정렬하지 않음을 검사
}
RAW0 <- mk_raw()
fresh <- function(tag) {
  d <- file.path(FX, tag); unlink(d, recursive = TRUE); dir.create(d, recursive = TRUE)
  write_parquet(RAW0, file.path(d, "RAWDATA.parquet"))
  write_parquet(bench_fx, file.path(d, "benchmark.parquet"))
  list(dir = d, raw = file.path(d, "RAWDATA.parquet"), bench = file.path(d, "benchmark.parquet"))
}
ks <- function(dir, enabled) {
  p <- file.path(dir, "ks.json"); writeLines(toJSON(list(enabled = enabled), auto_unbox = TRUE), p); p
}
rd <- function(p) as.data.table(read_parquet(p, mmap = FALSE))
md5 <- function(p) unname(tools::md5sum(p))

# 독립 오라클 — writer 코드와 무관하게 전후 표를 비교해 위반 목록을 낸다
oracle <- function(before, after, bench, cfg) {
  v <- character(0)
  if (nrow(before) != nrow(after)) return("nrow_changed")
  if (!identical(names(before), names(after))) v <- c(v, "cols_changed")
  if (!identical(before$Date, after$Date) || !identical(before$Ticker, after$Ticker)) v <- c(v, "row_order_or_keys_changed")
  for (cc in setdiff(names(before), "BM_Ret"))
    if (!identical(before[[cc]], after[[cc]])) v <- c(v, paste0("other_col_changed:", cc))
  chg <- which(xor(is.na(before$BM_Ret), is.na(after$BM_Ret)) |
               (!is.na(before$BM_Ret) & !is.na(after$BM_Ret) & before$BM_Ret != after$BM_Ret))
  if (length(chg)) {
    cd <- unique(after$Date[chg])
    bv <- bench$BM_Ret[match(cd, bench$Date)]
    if (any(!is.finite(bv))) v <- c(v, paste0("filled_without_bench:", paste(cd[!is.finite(bv)], collapse = ",")))
    nv <- after$BM_Ret[chg]; ev <- bench$BM_Ret[match(after$Date[chg], bench$Date)]
    if (any(is.finite(ev) & (is.na(nv) | nv != ev))) v <- c(v, "written_value_not_bench")
    pd <- cd[E$bm_ret_protected(cd, cfg)]
    if (length(pd)) v <- c(v, paste0("protected_touched:", paste(pd, collapse = ",")))
  }
  v
}

#──────────────────────────────────────────────────────────────────────────────
cat("\n[A] 계획 분류\n")
#──────────────────────────────────────────────────────────────────────────────
cur <- E$bm_ret_date_summary(RAW0[, .(Date, BM_Ret)])
pl0 <- E$bm_ret_sync_plan(cur, bench_fx, CFG, allow_overwrite = FALSE)
act <- function(pl, d) pl[Date == D(d)]$action
chk("A1_fill_missing_with_bench", identical(act(pl0, "2026-09-03"), "fill") && identical(act(pl0, "2026-09-04"), "fill"))
chk("A2_bench_lag_left_na", identical(act(pl0, "2026-09-07"), "bench_lag"))
chk("A3_mismatch_refused_under_killswitch",
    identical(act(pl0, "2025-01-02"), "refused_killswitch") && identical(act(pl0, "2026-09-02"), "refused_killswitch"))
chk("A4_protected_saturday_and_ghost",
    all(c(act(pl0, "1998-12-04"), act(pl0, "1998-12-07"), act(pl0, "2024-12-30")) == "protected"))
chk("A5_equal_is_ok", identical(act(pl0, "2026-09-01"), "ok") && identical(act(pl0, "2024-12-27"), "ok"))
chk("A6_rc_violation_when_refused", E$bm_ret_plan_rc(pl0) == 3L)
pl1 <- E$bm_ret_sync_plan(cur, bench_fx, CFG, allow_overwrite = TRUE)
chk("A7_overwrite_when_released",
    identical(act(pl1, "2025-01-02"), "overwrite") && identical(act(pl1, "2026-09-02"), "overwrite") &&
      E$bm_ret_plan_rc(pl1) == 4L, "킬스위치 해제 → 덮어쓰기, 남은 것은 지연(rc=4)")
pl2 <- E$bm_ret_sync_plan(cur, bench_fx, CFG, dates = D(c("2026-09-03", "2030-01-01")), allow_overwrite = TRUE)
chk("A8_dates_subset_and_absent_flagged",
    nrow(pl2) == 2L && identical(act(pl2, "2026-09-03"), "fill") && identical(act(pl2, "2030-01-01"), "absent_in_rawdata"))

#──────────────────────────────────────────────────────────────────────────────
cat("\n[B] 쓰기 — 양성 대조\n")
#──────────────────────────────────────────────────────────────────────────────
f <- fresh("b_dry")
h0 <- md5(f$raw)
r <- E$rawdata_sync_bm_ret(dry_run = TRUE, raw_path = f$raw, bench_path = f$bench, cfg = CFG,
                           killswitch_path = ks(f$dir, FALSE))
chk("B1_dry_run_writes_nothing", identical(md5(f$raw), h0) &&
      !file.exists(file.path(f$dir, "rawdata_bm_ret_sync_last.json")) && !isTRUE(r$written))

f <- fresh("b_apply")
bk <- file.path(f$dir, "backup.parquet")
r <- E$rawdata_sync_bm_ret(dry_run = FALSE, raw_path = f$raw, bench_path = f$bench, cfg = CFG,
                           killswitch_path = ks(f$dir, FALSE), backup_path = bk)
A <- rd(f$raw); B <- rd(bk)
chk("B2_backup_is_original", identical(md5(bk), h0))
chk("B3_filled_equal_bench",
    all(A[Date %in% D(c("2026-09-03", "2026-09-04"))]$BM_Ret == bench_fx$BM_Ret[match(A[Date %in% D(c("2026-09-03", "2026-09-04"))]$Date, bench_fx$Date)]))
chk("B4_overwritten_equal_bench",
    all(A[Date == D("2025-01-02")]$BM_Ret == -0.0039494718) && all(A[Date == D("2026-09-02")]$BM_Ret == -0.0407049196))
chk("B5_lag_day_still_na", all(is.na(A[Date == D("2026-09-07")]$BM_Ret)) && r$rc == 4L)
chk("B6_protected_unchanged",
    all(is.na(A[Date == D("1998-12-04")]$BM_Ret)) && all(A[Date == D("1998-12-07")]$BM_Ret == 0.0055) &&
      all(is.na(A[Date == D("2024-12-30")]$BM_Ret)))
ov <- oracle(B, A, bench_fx, CFG)
chk("B7_oracle_clean_other_cols_order_types", length(ov) == 0L &&
      identical(sapply(A, function(x) class(x)[1]), sapply(B, function(x) class(x)[1])), paste(ov, collapse = ";"))
lj <- tryCatch(fromJSON(file.path(f$dir, "rawdata_bm_ret_sync_last.json")), error = function(e) NULL)
chk("B8_log_in_fixture_with_old_values",
    !is.null(lj) && lj$rc == 4L && any(lj$changes$date == "2025-01-02" & abs(lj$changes$old - (-0.0001573218)) < 1e-15) &&
      file.exists(file.path(f$dir, "rawdata_bm_ret_sync_log.jsonl")))
h1 <- md5(f$raw)
r2 <- E$rawdata_sync_bm_ret(dry_run = FALSE, raw_path = f$raw, bench_path = f$bench, cfg = CFG,
                            killswitch_path = ks(f$dir, TRUE))
chk("B9_idempotent_second_run_writes_nothing", !isTRUE(r2$written) && r2$rc == 4L &&
      identical(md5(f$raw), h1))

#──────────────────────────────────────────────────────────────────────────────
cat("\n[C] 위반 주입 — 오라클 검출력 + 쓰기기 돌연변이\n")
#──────────────────────────────────────────────────────────────────────────────
# C1~C3: 오라클 자체의 검출력(정상 후표 A 에 위반을 주입)
X <- copy(A); X[Date == D("2026-09-07"), BM_Ret := 0.0201]
chk("C1_oracle_red_fill_without_bench", any(grepl("^filled_without_bench", oracle(B, X, bench_fx, CFG))))
X <- copy(A); X[Ticker == "A000010" & Date == D("2026-09-03"), Close := Close + 1]
chk("C2_oracle_red_other_column", any(grepl("^other_col_changed:Close", oracle(B, X, bench_fx, CFG))))
X <- copy(A); X[Date == D("1998-12-07"), BM_Ret := 0.002]
X2 <- copy(A); X2[Date == D("2024-12-30"), BM_Ret := -0.0037927468]
chk("C3_oracle_red_protected_touched",
    any(grepl("^protected_touched:1998-12-07", oracle(B, X, bench_fx, CFG))) &&
      any(grepl("^protected_touched:2024-12-30", oracle(B, X2, bench_fx, CFG))))

# C4: 쓰기기 돌연변이 — 지연일을 직전값으로 '추정' 채움 → 오라클 red
M <- new.env(); for (nm in ls(E, all.names = TRUE)) assign(nm, get(nm, E), M)
orig_plan <- E$bm_ret_sync_plan
M$bm_ret_sync_plan <- function(...) {
  p <- orig_plan(...)
  p[action == "bench_lag", `:=`(action = "fill", bench = 0.0181057687)]   # 추정 금지 위반
  p
}
environment(M$rawdata_sync_bm_ret) <- M
f <- fresh("c4"); Bc <- rd(f$raw)
invisible(M$rawdata_sync_bm_ret(dry_run = FALSE, raw_path = f$raw, bench_path = f$bench, cfg = CFG,
                                killswitch_path = ks(f$dir, FALSE)))
chk("C4_mutant_guess_fill_caught", any(grepl("^filled_without_bench:2026-09-07", oracle(Bc, rd(f$raw), bench_fx, CFG))),
    "지연일 추정 채움 돌연변이를 오라클이 잡는다")

# C5: 쓰기기 돌연변이 — 적용이 다른 열도 건드림 → writer 자체 해시 가드가 쓰기 전에 멈춘다
M5 <- new.env(); for (nm in ls(E, all.names = TRUE)) assign(nm, get(nm, E), M5)
orig_apply <- E$bm_ret_apply_dt
M5$bm_ret_apply_dt <- function(raw, plan) { out <- orig_apply(raw, plan); set(raw, i = 1L, j = "Close", value = -1); out }
environment(M5$rawdata_sync_bm_ret) <- M5
f <- fresh("c5"); h5 <- md5(f$raw)
e5 <- tryCatch({ M5$rawdata_sync_bm_ret(dry_run = FALSE, raw_path = f$raw, bench_path = f$bench, cfg = CFG,
                                        killswitch_path = ks(f$dir, FALSE)); "no_error" },
               error = function(e) conditionMessage(e))
chk("C5_mutant_other_column_stopped_before_write", grepl("BM_Ret 외 열이 바뀌었다", e5) && identical(md5(f$raw), h5), e5)

# C6: 보호 해제 돌연변이(설정 protect 비움) → 토요장·2024-12-30 을 쓴다 → 오라클 red (보호가 설정에서 온다는 통제)
CFGm <- CFG; CFGm$protect <- CFG$protect[0]
f <- fresh("c6"); Bc <- rd(f$raw)
invisible(E$rawdata_sync_bm_ret(dry_run = FALSE, raw_path = f$raw, bench_path = f$bench, cfg = CFGm,
                                killswitch_path = ks(f$dir, FALSE)))
o6 <- oracle(Bc, rd(f$raw), bench_fx, CFG)
chk("C6_mutant_protect_removed_caught",
    any(grepl("protected_touched:.*1998-12-0", o6)) && any(grepl("2024-12-30", o6)), paste(o6, collapse = ";"))

# C7: 동시 writer — 계획 후 파일이 바뀌면 쓰지 않는다
M7 <- new.env(); for (nm in ls(E, all.names = TRUE)) assign(nm, get(nm, E), M7)
M7$bm_ret_apply_dt <- function(raw, plan) {
  out <- orig_apply(raw, plan)
  write_parquet(RAW0[1:3], M7$.victim)       # 다른 writer 가 그 사이에 파일을 바꿨다
  out
}
environment(M7$rawdata_sync_bm_ret) <- M7
f <- fresh("c7"); M7$.victim <- f$raw
e7 <- tryCatch({ M7$rawdata_sync_bm_ret(dry_run = FALSE, raw_path = f$raw, bench_path = f$bench, cfg = CFG,
                                        killswitch_path = ks(f$dir, FALSE)); "no_error" },
               error = function(e) conditionMessage(e))
chk("C7_concurrent_writer_detected", grepl("다른 writer", e7) && nrow(rd(f$raw)) == 3L, e7)

#──────────────────────────────────────────────────────────────────────────────
cat("\n[D] 킬스위치 · 광기값 · 상한 · 벤치 결손\n")
#──────────────────────────────────────────────────────────────────────────────
f <- fresh("d1")
r <- E$rawdata_sync_bm_ret(dry_run = FALSE, raw_path = f$raw, bench_path = f$bench, cfg = CFG,
                           killswitch_path = ks(f$dir, TRUE))
Ad <- rd(f$raw)
chk("D1_killswitch_on_fills_but_no_overwrite",
    r$rc == 3L && all(Ad[Date == D("2026-09-03")]$BM_Ret == 0.0012505695) &&
      all(Ad[Date == D("2025-01-02")]$BM_Ret == -0.0001573218))
chk("D2_killswitch_absent_means_allowed", isTRUE(E$bm_ret_overwrite_allowed(CFG, killswitch_path = file.path(FX, "nope.json"))))
bp <- file.path(FX, "badks.json"); writeLines("{not json", bp)
chk("D3_killswitch_unreadable_means_refuse", !isTRUE(E$bm_ret_overwrite_allowed(CFG, killswitch_path = bp)))
bi <- copy(bench_fx); bi[Date == D("2026-09-03"), BM_Ret := 0.5]
pli <- E$bm_ret_sync_plan(cur, bi, CFG, allow_overwrite = TRUE)
chk("D4_insane_bench_refused", identical(act(pli, "2026-09-03"), "refused_insane") && E$bm_ret_plan_rc(pli) == 3L)
CFGc <- CFG; CFGc$max_overwrite_per_run <- 1L
plc <- E$bm_ret_sync_plan(cur, bench_fx, CFGc, allow_overwrite = TRUE)
chk("D5_cap_refuses_all_overwrites", all(plc[Date %in% D(c("2025-01-02", "2026-09-02"))]$action == "refused_cap"))
bm2 <- bench_fx[Date != D("2026-09-03")]
plm <- E$bm_ret_sync_plan(cur, bm2, CFG, allow_overwrite = TRUE)
chk("D6_bench_missing_inside_span_is_violation", identical(act(plm, "2026-09-03"), "bench_missing") && E$bm_ret_plan_rc(plm) == 3L)

#──────────────────────────────────────────────────────────────────────────────
cat("\n[E] 메모리 API\n")
#──────────────────────────────────────────────────────────────────────────────
dm <- copy(RAW0)[, BM_Ret := NULL]
res <- E$rawdata_bm_ret_sync_dt(dm, bench = bench_fx, cfg = CFG, allow_overwrite = FALSE)
chk("E1_creates_column_and_fills_non_protected",
    "BM_Ret" %in% names(res$dt) && all(res$dt[Date == D("2026-09-02")]$BM_Ret == -0.0407049196) &&
      all(is.na(res$dt[Date == D("1998-12-07")]$BM_Ret)) && all(is.na(res$dt[Date == D("2026-09-07")]$BM_Ret)) &&
      res$rc == 4L)
dm2 <- copy(RAW0)
res2 <- E$rawdata_bm_ret_sync_dt(dm2, bench = bench_fx, cfg = CFG, allow_overwrite = FALSE)
chk("E2_in_memory_respects_killswitch", all(res2$dt[Date == D("2026-09-02")]$BM_Ret == -0.0382032921) && res2$rc == 3L)

#──────────────────────────────────────────────────────────────────────────────
cat("\n[F] 배선 — daily_refresh.sh [3b]\n")
#──────────────────────────────────────────────────────────────────────────────
DRS <- readLines(file.path(PROJ, "02_Infrastructure/data/daily_refresh.sh"), encoding = "UTF-8", warn = FALSE)
i3b <- grep("^# ── \\[3b\\] RAWDATA BM_Ret 동기화", DRS)
iend <- if (length(i3b)) i3b[1] - 1L + grep("^esac$", DRS[i3b[1]:length(DRS)])[1] else NA
pos <- function(pat) grep(pat, DRS, fixed = TRUE)[1]
chk("F1_block_present_once", length(i3b) == 1L && is.finite(iend))
chk("F2_block_after_rawdata_writers_before_6a",
    length(i3b) == 1L && all(c(pos('echo "[1/7]'), pos('echo "[2/7]'), pos('echo "[3/7]')) < i3b) &&
      i3b < pos('echo "[6a/7]'))
blk <- if (length(i3b) == 1L) DRS[i3b:iend] else character(0)
chk("F3_block_calls_single_writer_apply", any(grepl("data/rawdata_bm_ret_sync.R\" --apply", blk, fixed = TRUE)))
BASH <- Sys.which("bash")
if (!nzchar(BASH) && file.exists("C:/Program Files/Git/bin/bash.exe")) BASH <- "C:/Program Files/Git/bin/bash.exe"
RSCRIPT <- gsub("\\\\", "/", file.path(R.home("bin"), "Rscript.exe"))
if (!file.exists(RSCRIPT)) RSCRIPT <- gsub("\\\\", "/", Sys.which("Rscript"))
run_blk <- function(b, rscript, base, env = character(0)) {
  sh <- file.path(FX, "harness.sh")
  renv <- file.path(FX, "empty.Renviron"); writeLines("# isolated", renv)
  writeLines(c("set -u", "DR_FAILED=()", sprintf('export R_ENVIRON_USER="%s"', renv), env,
               sprintf('BASE="%s"', base), sprintf('INFRA="%s"', file.path(PROJ, "02_Infrastructure")),
               sprintf('RSCRIPT="%s"', rscript), b, 'printf "DRF:%s\\n" "${DR_FAILED[@]:-}"'), sh, useBytes = TRUE)
  out <- suppressWarnings(system2(BASH, shQuote(sh), stdout = TRUE, stderr = TRUE))
  list(drf = sub("^DRF:", "", grep("^DRF:", out, value = TRUE)), out = out)
}
if (!nzchar(BASH) || !length(blk)) { bad("F_bash_or_block", "bash 또는 [3b] 블록 부재 — 배선 미측정") } else {
  stub <- file.path(FX, "stub_rscript.sh")
  writeLines(c("#!/usr/bin/env bash",
               'echo "BM_RET_SYNC rc=${STUB_RC} filled=0 overwritten=0 lag=1 violations=0 lag_dates=2026-09-22 viol=${STUB_VIOL:--} "',
               'exit "${STUB_RC}"'), stub)
  cases <- list(c("0", "-"), c("4", "-"), c("3", "2026-09-02:refused_killswitch"), c("1", "-"))
  got <- lapply(cases, function(cs) run_blk(blk, stub, FX, c(sprintf('export STUB_RC=%s', cs[1]),
                                                                sprintf('export STUB_VIOL="%s"', cs[2])))$drf)
  chk("F4_rc0_no_failure", !any(nzchar(got[[1]])), paste(got[[1]], collapse = " "))
  chk("F5_rc4_bench_lag_loaded", any(got[[2]] == "rawdata_bm_ret:bench_lag(2026-09-22)"), paste(got[[2]], collapse = " "))
  chk("F6_rc3_violation_loaded", any(got[[3]] == "rawdata_bm_ret:violation(2026-09-02:refused_killswitch)"), paste(got[[3]], collapse = " "))
  chk("F7_rc1_unmeasured_loaded", any(got[[4]] == "rawdata_bm_ret:unmeasured(rc=1)"), paste(got[[4]], collapse = " "))
  mut <- blk[!grepl("DR_FAILED\\+=", blk)]
  gm <- lapply(cases[2:4], function(cs) run_blk(mut, stub, FX, c(sprintf('export STUB_RC=%s', cs[1]),
                                                                  sprintf('export STUB_VIOL="%s"', cs[2])))$drf)
  chk("F8_mutant_load_lines_removed_goes_silent",
      length(mut) < length(blk) && all(vapply(gm, function(g) !any(nzchar(g)), logical(1))),
      "적재 줄을 지우면 같은 rc 가 침묵 — F5~F7 이 배선 자체를 잰다는 증거")
  # 실제 Rscript end-to-end — 격리 루트(표지 + .cache 픽스처 + 킬스위치 가동)
  root <- file.path(FX, "root"); dir.create(file.path(root, ".cache"), recursive = TRUE)
  dir.create(file.path(root, "06_Registry")); writeLines("fixture", file.path(root, "CLAUDE.md"))
  writeLines(toJSON(list(enabled = TRUE), auto_unbox = TRUE), file.path(root, "06_Registry", "reinforce_auto_config.json"))
  write_parquet(RAW0[!Date %in% D(c("2025-01-02", "2026-09-02"))], file.path(root, ".cache", "RAWDATA.parquet"))
  write_parquet(bench_fx, file.path(root, ".cache", "benchmark.parquet"))
  e2e <- run_blk(blk, RSCRIPT, root)
  Ae <- rd(file.path(root, ".cache", "RAWDATA.parquet"))
  chk("F9_e2e_real_writer_fills_and_reports_lag",
      any(e2e$drf == "rawdata_bm_ret:bench_lag(2026-09-07)") && all(Ae[Date == D("2026-09-04")]$BM_Ret == 0.0181057687) &&
        file.exists(file.path(root, ".cache", "rawdata_bm_ret_sync_last.json")),
      paste(c(e2e$drf, tail(e2e$out, 3)), collapse = " | "))
  # F10/F11 — '루프 정지 = 과거 정정 승인' 결합 차단(2026-09-23 적대 검증 발견 3).
  #   킬스위치가 내려간 밤에도 무인 [3b](--apply 만)는 과거 유한값을 덮지 않는다.
  #   F11 = 같은 조건에서 --allow-overwrite 를 주면 덮는다 → F10 이 구별력을 가진다는 양성 대조.
  root2 <- file.path(FX, "root_ks_down"); dir.create(file.path(root2, ".cache"), recursive = TRUE)
  dir.create(file.path(root2, "06_Registry")); writeLines("fixture", file.path(root2, "CLAUDE.md"))
  writeLines(toJSON(list(enabled = FALSE), auto_unbox = TRUE), file.path(root2, "06_Registry", "reinforce_auto_config.json"))
  write_parquet(RAW0, file.path(root2, ".cache", "RAWDATA.parquet"))
  write_parquet(bench_fx, file.path(root2, ".cache", "benchmark.parquet"))
  e10 <- run_blk(blk, RSCRIPT, root2)
  A10 <- rd(file.path(root2, ".cache", "RAWDATA.parquet"))
  chk("F10_unattended_block_never_overwrites_even_with_killswitch_down",
      all(A10[Date == D("2026-09-02")]$BM_Ret == -0.0382032921) &&
        any(grepl("^rawdata_bm_ret:violation\\(.*2026-09-02:refused_killswitch", e10$drf)),
      paste(c(e10$drf, tail(e10$out, 3)), collapse = " | "))
  # ★system2(env=) 는 Windows 에서 무시된다 — 격리는 F10 과 같은 bash 하네스(QM_ROOT="$BASE")로.
  o11 <- run_blk('QM_ROOT="$BASE" "$RSCRIPT" --no-save "$INFRA/data/rawdata_bm_ret_sync.R" --apply --allow-overwrite',
                 RSCRIPT, root2)$out
  A11 <- rd(file.path(root2, ".cache", "RAWDATA.parquet"))
  chk("F11_explicit_flag_with_killswitch_down_overwrites",
      all(A11[Date == D("2026-09-02")]$BM_Ret == -0.0407049196), paste(tail(o11, 3), collapse = " | "))
}

#──────────────────────────────────────────────────────────────────────────────
cat("\n[G] 경로 정리 — 옛 writer 가 단일 writer 를 부른다\n")
#──────────────────────────────────────────────────────────────────────────────
rl <- function(p) paste(readLines(file.path(PROJ, p), encoding = "UTF-8", warn = FALSE), collapse = "\n")
code_only <- function(p) {
  x <- readLines(file.path(PROJ, p), encoding = "UTF-8", warn = FALSE)
  paste(sub("#.*$", "", x), collapse = "\n")
}
iuf <- code_only("02_Infrastructure/data/incremental_update_file.R")
chk("G1_incremental_update_file_routes",
    grepl("rawdata_bm_ret_sync_dt(", iuf, fixed = TRUE) && !grepl("raw[, BM_Ret := NULL]", iuf, fixed = TRUE))
krx <- code_only("02_Infrastructure/data/krx_build_rawdata.R")
chk("G2_krx_no_self_computed_bm_ret_or_zero_sentinel",
    grepl("rawdata_bm_ret_sync_dt(", krx, fixed = TRUE) && !grepl("BM_Ret := 0]", krx, fixed = TRUE) &&
      !grepl("merge(new_rows, bm_new[, .(Date, BM_Ret)]", krx, fixed = TRUE))
san <- code_only("02_Infrastructure/data/rawdata_sanitize.R")
chk("G3_sanitize_routes", grepl("rawdata_bm_ret_sync_dt(", san, fixed = TRUE) && !grepl("raw[, BM_Ret := NULL]", san, fixed = TRUE))
rep <- code_only("02_Infrastructure/data/repair_rawdata_bmret_from_benchmark.R")
chk("G4_repair_script_delegates", grepl("rawdata_sync_bm_ret(", rep, fixed = TRUE) && !grepl("write_parquet(r, tmp)", rep, fixed = TRUE))
py <- rl("02_Infrastructure/data/build_index_cache.py")
chk("G5_python_update_rawdata_delegates",
    grepl("rawdata_bm_ret_sync.R", py, fixed = TRUE) && !grepl('raw = raw[raw["BM_Ret"].notna()', py, fixed = TRUE))

fin()
