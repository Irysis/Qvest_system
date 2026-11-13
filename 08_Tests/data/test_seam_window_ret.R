#==============================================================================
# test_seam_window_ret.R — 적재기 Ret 재계산 창 한정 + 전 이음매 재판정 (2026-11-13 · 원천 이음매 결함 수리)
#
# 왜 (실측 2026-11-13): incremental_ohlcvs 가 Ret 을 전 이력에 다시 셌고 가드는 이번 창 첫날 · 바뀐 전환점만 고쳤다.
#   신규 상장 보충 창(-FromOverride OHLCVS=20261110)이 증분 창을 11-10~ 로 좁힌 11-11 11:28 적재부터 2026-03-30
#   이음매 처분이 매번 생비율로 되돌아갔다(|Ret|>0.35 351종 · 등가중 +66% · P1R03 엔진 하루 +75%).
#
# 무엇을 재나(전부 합성 픽스처 · 운영 .cache · 06_Registry 쓰기 0 · 사이드카는 가짜 함수로 가린다):
#   W1 단위 — seam_ret_recompute_window: 창 행만 다시 센다 · 창 밖 저장값 불변 · Ret 열 없으면 만든다 · 첫날 없음 = stop
#   W2 적재 3회 시나리오(가드 블록을 의미 앵커로 잘라 실구동 — test_seam_scale_guard ⑩ 과 같은 앵커):
#        1회 = 전체 창(03-30~) → 03-30 전환 이음매 처분(SPLIT5 rescale · ODD block)
#        2회 = 좁은 창(04-06~) · INNER 만 새 기준(×2)으로 재수출 → 창 첫날 이음매 처분 + 03-30 처분 보존
#        3회 = 더 좁은 창(04-09~) → 04-06 창 안(같은 source 라벨) 이음매 처분 보존 + 03-30 보존
#   W3 돌연변이(소스 텍스트 치환 · 정확히 1곳 · 치환 성사 단정):
#        M_old  = 구판 두 줄 복원(전 이력 재계산 + 바뀐 경계만) → 03-30 이 생비율로 되살아나야 한다(= 11-11 사고 재현 · 양성 대조)
#        M_full = 전 이력 재계산만 복원 → 04-06 창 안 이음매가 되살아나야 한다(전환점 재판정만으로는 못 막는 자리)
#        M_seed = 전환점 재판정만 끔 → 창 한정 재계산이 03-30 을 지킨다(층마다 맡는 자리가 다름을 고정)
#   W4 배관 도달 — incremental_ohlcvs 가 seam_ret_recompute_window · rsa_audit · rsa_block_new 를 부르고, 감사가 저장 앞에 있다(AST)
#
# 실행: R_ENVIRON_USER=<빈 파일> Rscript 08_Tests/data/test_seam_window_ret.R
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })

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
chk <- function(cond, n, m = "") if (isTRUE(cond)) ok(n, m) else bad(n, m)
cat("=== seam window Ret (합성 픽스처) ===\n")

DATA <- file.path(PROJ, "02_Infrastructure/data")
INCR <- file.path(DATA, "incremental_update_file.R")
Sys.setenv(CLAUDE_PROJECT_DIR = PROJ, QM_ROOT = PROJ)   # 가드 루트 해석을 검사 대상 트리에 묶는다
source(file.path(DATA, "seam_scale_guard.R"))

# ── W1 단위 ───────────────────────────────────────────────────────────────────
u <- data.table(Date = as.Date("2026-01-01") + c(0:4, 0:4), Ticker = rep(c("A", "B"), each = 5),
                Close = c(10, 11, 12, 13, 14, 20, 20, 40, 41, 42))
u[, Ret := c(NA, 0.1, 0.5, 0.25, -0.75, NA, 0, 9, 9, 9)]          # 창 밖 저장값(일부러 생비율과 다르게)
u2 <- seam_ret_recompute_window(copy(u), as.Date("2026-01-04"))
g <- function(d, tk, dd) d[Ticker == tk & Date == as.Date(dd), Ret]
chk(abs(g(u2, "A", "2026-01-04") - (13 / 12 - 1)) < 1e-15 && abs(g(u2, "A", "2026-01-05") - (14 / 13 - 1)) < 1e-15 &&
    abs(g(u2, "B", "2026-01-04") - (41 / 40 - 1)) < 1e-15, "w1_window_rows_recomputed", "창 첫 행 = 창 밖 직전 행이 앵커")
chk(identical(g(u2, "A", "2026-01-03"), 0.5) && identical(g(u2, "B", "2026-01-03"), 9),
    "w1_outside_window_kept", "창 밖 저장값(지난 처분 자리) 불변")
chk(identical(attr(u2, "ret_recompute")$n_rows, 4L), "w1_attr_rows", "창 행 수 기록")
u3 <- seam_ret_recompute_window(copy(u)[, Ret := NULL], as.Date("2026-01-03"))
chk("Ret" %in% names(u3) && is.na(g(u3, "A", "2026-01-02")) && abs(g(u3, "A", "2026-01-03") - (12 / 11 - 1)) < 1e-15,
    "w1_creates_ret_column", "Ret 열 없으면 만들고 창 밖은 NA")
e1 <- tryCatch({ seam_ret_recompute_window(copy(u), as.Date(NA)); "no_error" }, error = function(e) "stopped")
chk(identical(e1, "stopped"), "w1_missing_from_stops", "첫날 없음 = 전 이력 재계산으로 떨어지지 않고 stop")

# ── W2 적재 3회 시나리오 ──────────────────────────────────────────────────────
cut_block <- function(path, start_pat, end_pat) {
  ln <- readLines(path, warn = FALSE, encoding = "UTF-8")
  i <- which(vapply(ln, function(x) grepl(start_pat, x, fixed = TRUE), logical(1)))
  j <- which(vapply(ln, function(x) grepl(end_pat, x, fixed = TRUE), logical(1)))
  if (!length(i) || !length(j)) return(NULL)
  j <- j[j > i[1]]
  if (!length(j)) return(NULL)
  paste(ln[i[1]:(j[1] - 1L)], collapse = "\n")
}
BLK <- cut_block(INCR, "[guard 2026-09-07", "# BM_Ret 매핑")
if (is.null(BLK)) { bad("w2_block_found", "가드 블록 앵커 소실"); BLK <- "" } else ok("w2_block_found", sprintf("%d자", nchar(BLK)))

DB <- as.Date(c("2026-03-25", "2026-03-26", "2026-03-27"))
DU <- as.Date(c("2026-03-30", "2026-03-31", "2026-04-01", "2026-04-02", "2026-04-03",
                "2026-04-06", "2026-04-07", "2026-04-08", "2026-04-09", "2026-04-10"))
SEAM <- DU[1]; W2 <- as.Date("2026-04-06"); W3 <- as.Date("2026-04-09")
row <- function(tk, dates, cl, src) data.table(Date = dates, Ticker = tk, Close = as.numeric(cl), source = src)
base <- rbindlist(list(
  row("NORM", DB, c(100, 101, 102), "quantiwise"),
  row("SPLIT5", DB, c(100, 101, 102), "quantiwise"),       # 증분 수출본은 ×5 기준(그날 실수익 −1.47%)
  row("ODD", DB, c(100, 101, 102), "quantiwise"),          # 정수배 지문 없음 → 차단
  row("INNER", DB, c(50, 51, 52), "quantiwise")))
upd_cl <- function(tk) switch(tk, NORM = 103:112, SPLIT5 = 502.5 + 0:9, ODD = 245 + 0:9, INNER = 52.5 + (0:9) * 0.5)
export <- function(dates, inner_scale = 1) rbindlist(lapply(c("NORM", "SPLIT5", "ODD", "INNER"), function(tk) {
  cl <- upd_cl(tk)[match(dates, DU)]
  if (tk == "INNER") cl <- cl * inner_scale
  row(tk, dates, cl, "quantiwise_update") }))

run_load <- function(raw_prev, upd, blk = BLK) {
  # 적재기 순서 그대로: 교체 전 source 지도 → 창 행 교체(Ret 없음) → 가드 블록
  src_before <- raw_prev[, .(Date, source)]
  ud <- sort(unique(upd$Date))
  r <- rbind(raw_prev[!(Date %in% ud)], upd[, Ret := NA_real_], fill = TRUE)
  e <- new.env(parent = globalenv())
  assign("raw", r, envir = e); assign("update_dates", ud, envir = e); assign(".src_before", src_before, envir = e)
  assign("DATA_DIR", DATA, envir = e)
  assign("seam_write_sidecar", function(rep, label, ...) "stub", envir = e)
  msg <- tryCatch({ eval(parse(text = blk), envir = e); "ok" }, error = function(z) conditionMessage(z))
  if (!identical(msg, "ok")) stop("블록 실행 실패: ", msg)
  out <- get("raw", envir = e); setorder(out, Ticker, Date); out
}
gv <- function(d, tk, dd) d[Ticker == tk & Date == as.Date(dd), Ret]

scenario <- function(blk) {
  r0 <- copy(base)[, Ret := c(NA, 0.01, 1 / 101, NA, 0.01, 1 / 101, NA, 0.01, 1 / 101, NA, 0.02, 1 / 51)]
  r1 <- invisible(capture.output(x1 <- run_load(r0, export(DU), blk))); r1 <- x1
  x2 <- NULL; invisible(capture.output(x2 <- run_load(r1, export(DU[DU >= W2], inner_scale = 2), blk)))
  x3 <- NULL; invisible(capture.output(x3 <- run_load(x2, export(DU[DU >= W3], inner_scale = 2), blk)))
  list(r1 = r1, r2 = x2, r3 = x3)
}
S <- tryCatch(scenario(BLK), error = function(e) { bad("w2_scenario_runs", conditionMessage(e)); NULL })
if (!is.null(S)) {
  imp5 <- 502.5 / 102 / 5 - 1
  chk(abs(gv(S$r1, "SPLIT5", SEAM) - imp5) < 1e-12 && is.na(gv(S$r1, "ODD", SEAM)) &&
      abs(gv(S$r1, "NORM", SEAM) - (103 / 102 - 1)) < 1e-12, "w2_load1_transition_seam_repaired",
      sprintf("SPLIT5 %.5f(rescale) · ODD NA(block) · NORM 정상", imp5))
  chk(abs(gv(S$r2, "SPLIT5", SEAM) - imp5) < 1e-12 && is.na(gv(S$r2, "ODD", SEAM)),
      "w2_load2_old_seam_kept", "좁은 창(04-06~) 뒤에도 03-30 처분 그대로")
  inner_imp <- (upd_cl("INNER")[6] * 2) / upd_cl("INNER")[5] / 2 - 1
  chk(abs(gv(S$r2, "INNER", W2) - inner_imp) < 1e-12, "w2_load2_window_start_seam_repaired",
      sprintf("창 첫날 같은 라벨 안 ×2 이음매 rescale → %.5f", inner_imp))
  mid <- S$r1[Date > SEAM & Date < W2]; mid2 <- S$r2[Date > SEAM & Date < W2]
  chk(isTRUE(all.equal(mid[order(Ticker, Date)]$Ret, mid2[order(Ticker, Date)]$Ret)), "w2_load2_blast_radius",
      "창 밖 사이 구간(03-31~04-03) Ret 전량 불변")
  chk(abs(gv(S$r3, "INNER", W2) - inner_imp) < 1e-12 && abs(gv(S$r3, "SPLIT5", SEAM) - imp5) < 1e-12,
      "w2_load3_inner_and_old_seams_kept", "더 좁은 창(04-09~) 뒤에도 04-06 · 03-30 처분 보존")
}

# ── W3 돌연변이 ───────────────────────────────────────────────────────────────
NEW_RET <- "raw <- seam_ret_recompute_window(raw, min(update_dates))"
OLD_RET <- "raw[, Ret := Close / shift(Close) - 1, by = Ticker]"
NEW_SEED <- "sort(unique(c(as.Date(min(update_dates)), as.Date(.chg$seam_date), as.Date(.all$seam_date))))"
OLD_SEED <- "sort(unique(c(as.Date(min(update_dates)), as.Date(.chg$seam_date))))"
mutate <- function(blk, pairs) {
  for (p in pairs) {
    n <- lengths(regmatches(blk, gregexpr(p[1], blk, fixed = TRUE)))
    if (n != 1L) stop(sprintf("치환 대상 %d곳(1 이어야 함): %s", n, substr(p[1], 1, 50)))
    blk <- sub(p[1], p[2], blk, fixed = TRUE)
  }
  blk
}
run_mut <- function(pairs) tryCatch(scenario(mutate(BLK, pairs)), error = function(e) conditionMessage(e))
Mo <- run_mut(list(c(NEW_RET, OLD_RET), c(NEW_SEED, OLD_SEED)))
if (is.list(Mo)) {
  v <- gv(Mo$r2, "SPLIT5", SEAM)
  chk(abs(v - (502.5 / 102 - 1)) < 1e-12, "w3_M_old_reproduces_incident",
      sprintf("구판 복원 = 좁은 창 뒤 03-30 SPLIT5 %.3f(생비율 +393%%) — 11-11 사고 재현(양성 대조)", v))
} else bad("w3_M_old_reproduces_incident", paste("변이 실행 실패:", Mo))
Mf <- run_mut(list(c(NEW_RET, OLD_RET)))
if (is.list(Mf)) {
  v <- gv(Mf$r3, "INNER", W2); raw_inner <- (upd_cl("INNER")[6] * 2) / upd_cl("INNER")[5] - 1
  chk(abs(v - raw_inner) < 1e-12 && abs(gv(Mf$r3, "SPLIT5", SEAM) - (502.5 / 102 / 5 - 1)) < 1e-12, "w3_M_full_inner_seam_revives",
      sprintf("전 이력 재계산만 복원 = 04-06 창 안 이음매 %.3f 로 되살아남 · 03-30 은 전환점 재판정이 지킴", v))
} else bad("w3_M_full_inner_seam_revives", paste("변이 실행 실패:", Mf))
Ms <- run_mut(list(c(NEW_SEED, OLD_SEED)))
if (is.list(Ms)) {
  chk(abs(gv(Ms$r3, "SPLIT5", SEAM) - (502.5 / 102 / 5 - 1)) < 1e-12 && abs(gv(Ms$r3, "INNER", W2) - inner_imp) < 1e-12,
      "w3_M_seed_window_recompute_guards", "전환점 재판정만 꺼도 창 한정 재계산이 03-30 · 04-06 을 지킨다(층 분담 고정)")
} else bad("w3_M_seed_window_recompute_guards", paste("변이 실행 실패:", Ms))

# ── W4 배관 도달 (AST) ─────────────────────────────────────────────────────────
fn_calls <- function(path, fn_name) {
  ex <- parse(path, encoding = "UTF-8"); found <- character(0)
  walk <- function(e) {
    if (is.call(e)) { h <- e[[1]]; if (is.name(h)) found <<- c(found, as.character(h)) }
    if (is.recursive(e)) for (i in seq_along(e)) if (!is.null(e[[i]])) try(walk(e[[i]]), silent = TRUE)
  }
  for (x in ex) if (is.call(x) && length(x) >= 3 && as.character(x[[1]]) %in% c("<-", "=") &&
                    identical(as.character(x[[2]]), fn_name)) walk(x[[3]])
  found
}
cs <- fn_calls(INCR, "incremental_ohlcvs")
need <- c("seam_ret_recompute_window", "seam_detect", "rsa_audit", "rsa_block_new", "write_parquet")
chk(all(need %in% cs), "w4_pipeline_calls", paste("incremental_ohlcvs 호출:", paste(intersect(need, cs), collapse = " · ")))
pos <- function(nm) match(nm, cs)
chk(isTRUE(pos("rsa_block_new") < max(which(cs == "write_parquet"))), "w4_audit_before_write", "감사 차단이 저장 앞")
chk(!grepl(OLD_RET, paste(readLines(INCR, warn = FALSE, encoding = "UTF-8"), collapse = "\n"), fixed = TRUE),
    "w4_no_full_history_recompute", "적재기에 전 이력 Ret 재계산 줄이 남지 않았다")

cat(sprintf("TOTAL: %d pass / %d fail / 0 skipped\n", PASS, FAIL))
cat(jsonlite::toJSON(list(test = "seam_window_ret", pass = PASS, fail = FAIL, skipped = 0L, total = PASS + FAIL, skips = list()),
                     auto_unbox = TRUE), "\n", sep = "")
if (FAIL > 0) quit(status = 1)
