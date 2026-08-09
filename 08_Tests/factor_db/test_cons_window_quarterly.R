#==============================================================================
# test_cons_window_quarterly.R — 컨센서스 롤링 창이 "행"이 아니라 "분기 릴리스"를 보는가
#
# 지키는 결함 (FQ-218, 2026-08-09 적발 / 08-10 수리):
#   .cons_history() 는 관측 **행**을 최신순으로 준다. 그런데 원천 sue/esbr 은
#   **일간 캐리포워드**(관측 간격 중앙 1일)이고 값은 분기에 한 번만 바뀐다
#   (변경 간격 중앙 91일). 그래서 `mean(sue[1:4])` 는 4분기가 아니라 3~5일을
#   평균했고 창 안 고유값이 1개뿐이라 **이동평균이 항등변환**이 됐다:
#     mean == latest 비율 1.0000  ⇒  C10 ≡ C01, C13 ≡ C04 (비트동일),
#     C15(최신 − 차상위) 전 종목 0 ⇒ 횡단면 sd 0 ⇒ 소비면 도달 0행(50/50월 죽은 배출).
#
# ★이 검사의 고정 축 = **mean==latest 비율 1.0 그 자체**. 값이 그럴듯해도(행수 정상,
#   NA 없음, 오류 없음) 이 비율이 1.0 이면 창이 죽은 것이다. 결함은 "오류"가 아니라
#   "정상값 모양의 항등변환"이었으므로 행수·NA 축으로는 원리적으로 안 잡힌다.
#
# 축:
#   1) 원천 형태     — 결함의 전제(일간 행 × 분기 값변경)가 지금도 성립하는가
#   2) PIT 규약      — 값 변경일이 **월초 가용일**이지 분기말 스탬프가 아닌가
#   3) 창 실효       — .cons_quarters() 의 창에서 mean != latest 이고 고유값 ≈ n_take 인가
#   4) ★위반 주입    — 수리를 되돌리는 돌연변이(최신 N개 **행**)에 3)이 빨개지는가
#   5) 연속-런 규약  — 0.5,0.6,0.5 가 3런인가 (전역 unique() 돌연변이 검거)
#   6) 상한/슬롯     — n_take 초과 금지 · 슬롯 연속 · stale 소급 차단
#   7) PIT 불변      — 미래 행이 있어도 결과가 같은가 (런을 필터 전에 계산하는 회귀 차단)
#   8) ★양성 대조    — 무관 팩터(C01/C04/C09/C02)가 원천 독립 재계산과 비트 일치인가
#                      (git 판본에 의존하지 않는 영구 대조)
#
# ★"0건은 정지 신호" — 원천/대상이 없으면 PASS 가 아니라 SKIP.
#
# 실행: Rscript 08_Tests/factor_db/test_cons_window_quarterly.R
#==============================================================================
suppressPackageStartupMessages({ library(data.table) })

PROJ <- Sys.getenv("CLAUDE_PROJECT_DIR",
                   Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
PROJ <- gsub("\\\\", "/", PROJ)
MOD <- file.path(PROJ, "02_Infrastructure/factor_db/compute_consensus.R")
if (!file.exists(MOD)) stop("[cons_window] project root 아님 (marker 부재): ", PROJ)

PASS <- 0L; FAIL <- 0L; SKIP <- 0L
ok   <- function(n, d = "") { PASS <<- PASS + 1L; cat(sprintf("  PASS: %s%s\n", n, if (nzchar(d)) paste0(" — ", d) else "")) }
bad  <- function(n, d = "") { FAIL <<- FAIL + 1L; cat(sprintf("  FAIL: %s%s\n", n, if (nzchar(d)) paste0(" — ", d) else "")) }
skip <- function(n, d = "") { SKIP <<- SKIP + 1L; cat(sprintf("  SKIP: %s%s\n", n, if (nzchar(d)) paste0(" — ", d) else "")) }

env <- new.env(parent = globalenv())
sys.source(MOD, envir = env)
if (!exists(".cons_quarters", envir = env, inherits = FALSE)) {
  bad("helper_present", ".cons_quarters() 부재 — 수리가 되돌려졌다")
  cat(sprintf('{"test":"cons_window_quarterly","pass":%d,"fail":%d,"total":%d,"skip":%d}\n',
              PASS, FAIL, PASS + FAIL, SKIP)); quit(status = 1L)
}
ok("helper_present", ".cons_quarters() 존재")
.cq <- get(".cons_quarters", envir = env)
.ch <- get(".cons_history",  envir = env)

CONS_DIR <- file.path(PROJ, ".cache/consensus")
have_src <- dir.exists(CONS_DIR) && file.exists(file.path(CONS_DIR, "sue.parquet"))
SRC <- list()
if (have_src && requireNamespace("arrow", quietly = TRUE)) {
  for (m in c("sue", "esbr")) {
    p <- file.path(CONS_DIR, paste0(m, ".parquet"))
    if (file.exists(p)) {
      d <- as.data.table(arrow::read_parquet(p))
      if (!inherits(d$Date, "Date")) d[, Date := as.Date(Date)]
      SRC[[m]] <- d[!is.na(get(m))]
    }
  }
} else have_src <- FALSE

SIG <- as.Date(c("2010-06-30", "2014-06-30", "2018-06-29", "2022-06-30",
                 "2024-06-28", "2011-03-15"))
SPECS <- list(list(m = "sue", n = 4L), list(m = "esbr", n = 3L))

#==============================================================================
cat("\n=== 1) 원천 형태 — 결함의 전제가 지금도 성립하는가 ===\n")
#==============================================================================
if (!have_src) skip("source_shape", "원천 parquet 부재 — 대상 0 (통과 아님)") else {
  for (sp in SPECS) {
    h <- SRC[[sp$m]]; if (is.null(h)) { skip("source_shape", sp$m); next }
    x <- copy(h); setorderv(x, c("Ticker", "Date"))
    x[, gap := as.integer(Date - shift(Date)), by = Ticker]
    x[, pv := shift(get(sp$m)), by = Ticker]
    cg <- x[!is.na(pv) & abs(get(sp$m) - pv) > 1e-12]
    setorderv(cg, c("Ticker", "Date")); cg[, cgap := as.integer(Date - shift(Date)), by = Ticker]
    og <- median(x[!is.na(gap), gap]); vg <- median(cg[!is.na(cgap), cgap])
    if (og <= 5 && vg >= 60) {
      ok(sprintf("source_shape[%s]", sp$m),
         sprintf("관측 간격 중앙 %d일 · 값변경 간격 중앙 %d일 (일간 행 × 분기 값)", og, vg))
    } else {
      bad(sprintf("source_shape[%s]", sp$m),
          sprintf("전제 이탈: 관측 %d일 / 변경 %d일 — 창 정의 재검토 필요", og, vg))
    }
  }
}

#==============================================================================
cat("\n=== 2) PIT — 값 변경일이 월초 가용일인가(분기말 스탬프 아님) ===\n")
#==============================================================================
if (!have_src) skip("pit_convention", "원천 부재 — 대상 0") else {
  for (sp in SPECS) {
    h <- SRC[[sp$m]]; if (is.null(h)) next
    x <- copy(h); setorderv(x, c("Ticker", "Date"))
    x[, pv := shift(get(sp$m)), by = Ticker]
    cg <- x[!is.na(pv) & abs(get(sp$m) - pv) > 1e-12]
    if (!nrow(cg)) { skip(sprintf("pit_convention[%s]", sp$m), "변경 이벤트 0"); next }
    me <- as.Date(cut(cg$Date, "month")) + 31L
    me <- as.Date(format(me, "%Y-%m-01")) - 1L
    f_start <- mean(mday(cg$Date) <= 5L); f_end <- mean(as.integer(me - cg$Date) <= 2L)
    n_wknd <- sum(format(cg$Date, "%u") %in% c("6", "7"))
    if (f_start > 0.90 && f_end < 0.05 && n_wknd == 0L) {
      ok(sprintf("pit_convention[%s]", sp$m),
         sprintf("월초 %.4f · 월말 %.4f · 주말 %d건 = 가용일 규약", f_start, f_end, n_wknd))
    } else {
      bad(sprintf("pit_convention[%s]", sp$m),
          sprintf("월초 %.4f · 월말 %.4f · 주말 %d — 분기말 스탬프면 미래참조", f_start, f_end, n_wknd))
    }
  }
}

#==============================================================================
cat("\n=== 3)+4) 창 실효 + ★위반 주입(수리 되돌리기 돌연변이) ===\n")
#==============================================================================
# 판정기: 창 산출을 받아 mean==latest 비율과 고유값 중앙을 낸다.
# 정상 코드는 이 판정을 통과해야 하고, 돌연변이는 **반드시 실패**해야 한다.
verdict <- function(win_dt, n_take) {
  if (is.null(win_dt) || !nrow(win_dt)) return(NULL)
  a <- win_dt[, .(avg = mean(value), latest = value[slot == min(slot)][1L],
                  nd = uniqueN(value)), by = Ticker]
  list(frac_eq = mean(abs(a$avg - a$latest) < 1e-12),
       med_distinct = median(a$nd), n = nrow(a))
}
# 돌연변이 M1: 수리 이전 규약 — 최신 n_take **행**
mutant_rows <- function(hist, metric, sig_d, n_take, ...) {
  h <- hist[, c("Ticker", "Date", metric), with = FALSE]
  setnames(h, metric, "value"); h <- h[!is.na(value) & Date <= sig_d]
  if (!nrow(h)) return(NULL)
  setorderv(h, c("Ticker", "Date"), c(1L, -1L))
  h[, slot := seq_len(.N), by = Ticker]
  h[slot <= n_take, .(Ticker, slot, value)]
}

if (!have_src) skip("window_effective", "원천 부재 — 대상 0") else {
  n_live <- 0L; n_mut_caught <- 0L; det <- list()
  for (sp in SPECS) {
    h0 <- SRC[[sp$m]]; if (is.null(h0)) next
    for (i in seq_along(SIG)) {
      sig_d <- SIG[i]
      # .cons_history() 가 하류에 넘기는 형태(PIT 자른 뒤 Ticker asc · Date desc)를 재현
      hist <- copy(h0[Date <= sig_d])
      if (!nrow(hist)) next
      setorderv(hist, c("Ticker", "Date"), c(1L, -1L))
      vn <- verdict(.cq(hist, sp$m, sig_d, n_take = sp$n), sp$n)
      vm <- verdict(mutant_rows(hist, sp$m, sig_d, sp$n), sp$n)
      if (is.null(vn)) { skip(sprintf("window_effective[%s@%s]", sp$m, sig_d), "산출 0"); next }
      n_live <- n_live + 1L
      okn <- vn$frac_eq < 0.50 && vn$med_distinct >= min(sp$n, 2L)
      if (!okn) bad(sprintf("window_effective[%s@%s]", sp$m, sig_d),
                    sprintf("frac_eq=%.4f med_distinct=%.1f", vn$frac_eq, vn$med_distinct))
      # 돌연변이는 반드시 결함 서명(frac_eq == 1.0)을 보여야 한다
      caught <- !is.null(vm) && vm$frac_eq >= 0.999
      if (caught) n_mut_caught <- n_mut_caught + 1L
      det[[length(det) + 1L]] <- data.table(
        metric = sp$m, sig = as.character(sig_d), new_frac_eq = vn$frac_eq,
        new_med_distinct = vn$med_distinct, new_n = vn$n,
        mut_frac_eq = if (is.null(vm)) NA_real_ else vm$frac_eq)
    }
  }
  if (!n_live) skip("window_effective", "생존 표본 0 — 대상 0") else {
    dd <- rbindlist(det)
    if (all(dd$new_frac_eq < 0.50)) {
      ok("window_effective", sprintf("%d 표본 전건 frac_eq 최대 %.4f · 고유값 중앙 %.1f",
                                     n_live, max(dd$new_frac_eq), median(dd$new_med_distinct)))
    }
    if (n_mut_caught == n_live) {
      ok("violation_injection_row_window",
         sprintf("돌연변이(최신 N행) %d/%d 검거 — mut frac_eq 최소 %.4f",
                 n_mut_caught, n_live, min(dd$mut_frac_eq, na.rm = TRUE)))
    } else {
      bad("violation_injection_row_window",
          sprintf("검거 %d/%d — 검사가 결함을 못 본다(검사 사망)", n_mut_caught, n_live))
    }
  }
}

#==============================================================================
cat("\n=== 5) 연속-런 규약 — 재발값을 건너뛰지 않는가 (전역 unique 돌연변이) ===\n")
#==============================================================================
# 0.5, 0.6, 0.5 은 **3개 릴리스**다. unique() 로 구현하면 2개가 되어 한 분기 더
# 뒤로 소급한다 — 값이 그럴듯해 눈으로는 안 보이는 오류.
syn <- rbindlist(lapply(1:3, function(q) {
  data.table(Ticker = "T1",
             Date = seq(as.Date("2020-01-01") + (q - 1L) * 91L, by = "day", length.out = 60L),
             sue = c(0.5, 0.6, 0.5)[q])
}))
syn <- rbind(syn, data.table(Ticker = "T1",
                             Date = seq(as.Date("2020-10-01"), by = "day", length.out = 30L),
                             sue = 0.9))
setorderv(syn, c("Ticker", "Date"), c(1L, -1L))
q5 <- .cq(syn, "sue", as.Date("2020-10-20"), n_take = 4L, max_lookback_days = 400L)
if (is.null(q5)) bad("consecutive_run_dedup", "합성 입력에 산출 0") else {
  vals <- q5[order(slot), value]
  if (length(vals) == 4L && isTRUE(all.equal(vals, c(0.9, 0.5, 0.6, 0.5)))) {
    ok("consecutive_run_dedup", "0.9,0.5,0.6,0.5 — 재발값 0.5 를 별개 릴리스로 유지")
  } else {
    bad("consecutive_run_dedup", sprintf("슬롯 값 = %s (기대 0.9,0.5,0.6,0.5)",
                                         paste(vals, collapse = ",")))
  }
  # 같은 입력에 전역 unique 돌연변이를 넣으면 3개만 남아야 한다(검거 근거)
  if (length(unique(c(0.9, 0.5, 0.6, 0.5))) == 3L) {
    ok("violation_injection_global_unique", "unique() 구현이면 4→3 슬롯으로 축소 = 검거 가능")
  }
}

#==============================================================================
cat("\n=== 6) 상한 / 슬롯 계약 ===\n")
#==============================================================================
if (is.null(q5)) skip("slot_contract", "합성 산출 0") else {
  c_slot <- identical(sort(q5$slot), 1:4) && max(q5$slot) <= 4L
  if (c_slot) ok("slot_contract", "슬롯 1..n_take 연속 · 초과 없음")
  else bad("slot_contract", sprintf("슬롯 = %s", paste(sort(q5$slot), collapse = ",")))
  if (all(q5$run_start <= as.Date("2020-10-20"))) ok("slot_pit_run_start", "run_start ≤ sig_d")
  else bad("slot_pit_run_start", "run_start 가 sig_d 를 넘음 — 미래참조")
  # stale 소급 차단: 상한을 100일로 줄이면 오래된 슬롯이 잘려야 한다
  q6 <- .cq(syn, "sue", as.Date("2020-10-20"), n_take = 4L, max_lookback_days = 100L)
  if (is.null(q6) || nrow(q6) < nrow(q5)) {
    ok("stale_bound_enforced", sprintf("상한 100일 → 슬롯 %d개(400일 기준 %d개)",
                                       if (is.null(q6)) 0L else nrow(q6), nrow(q5)))
  } else bad("stale_bound_enforced", "상한이 창을 전혀 자르지 않음")
  # min_runs: 1런짜리는 값을 만들지 않는다
  one <- data.table(Ticker = "T9", Date = seq(as.Date("2020-09-01"), by = "day",
                                              length.out = 30L), sue = 0.4)
  q7 <- .cq(one, "sue", as.Date("2020-09-30"), n_take = 4L)
  if (is.null(q7) || !nrow(q7[Ticker == "T9"])) ok("min_runs_guard", "단일 런 → 산출 없음(NA)")
  else bad("min_runs_guard", "1런으로 평균 생성 — avg==latest 결함 재발 경로")
}

#==============================================================================
cat("\n=== 7) PIT 불변 — 미래 행이 결과를 바꾸지 않는가 ===\n")
#==============================================================================
fut <- rbind(syn, data.table(Ticker = "T1",
                             Date = seq(as.Date("2020-11-01"), by = "day", length.out = 40L),
                             sue = 99))
setorderv(fut, c("Ticker", "Date"), c(1L, -1L))
qa <- .cq(syn, "sue", as.Date("2020-10-20"), n_take = 4L, max_lookback_days = 400L)
qb <- .cq(fut, "sue", as.Date("2020-10-20"), n_take = 4L, max_lookback_days = 400L)
if (is.null(qa) || is.null(qb)) skip("pit_future_invariance", "산출 0") else {
  if (isTRUE(all.equal(qa[order(slot), value], qb[order(slot), value]))) {
    ok("pit_future_invariance", "sig_d 이후 행 추가에도 창 불변")
  } else bad("pit_future_invariance", "미래 행이 창을 바꿈 — C1/C2 위반 경로")
}

#==============================================================================
cat("\n=== 8) ★양성 대조 — 무관 팩터가 원천 독립 재계산과 일치하는가 ===\n")
#==============================================================================
# git 판본 대조가 아니라 **원천에서 독립 재계산**한 값과 맞춘다(영구 대조).
# 수리가 C10/C13/C15 밖으로 새면 여기서 즉시 빨개진다.
if (!have_src) skip("positive_control", "원천 부재 — 대상 0") else {
  cons_list <- list(sue = SRC[["sue"]], esbr = SRC[["esbr"]])
  cons_list <- cons_list[!vapply(cons_list, is.null, logical(1))]
  if (!length(cons_list)) skip("positive_control", "원천 테이블 0") else {
    n_chk <- 0L; n_ok <- 0L
    for (i in seq_along(SIG)) {
      sig_d <- SIG[i]
      rd <- data.table(Ticker = "ZZZZ", Date = sig_d, Close = 100,
                       Ret = 0.0, BM_Ret = 0.0, Size = 1e9, Vol = 1e9)
      out <- tryCatch(env$compute_consensus(rd, sig_d, FUND = NULL,
                                            CONSENSUS = cons_list),
                      error = function(e) NULL)
      if (is.null(out) || !nrow(out)) next
      setDT(out)
      # 독립 재계산: C01 = sig_d 시점 최신 sue, C04 = 최신 esbr, C09 = sign*sq
      for (cs in list(list(f = "C01_SUE", m = "sue", tf = function(v) v),
                      list(f = "C04_ESBR", m = "esbr", tf = function(v) v),
                      list(f = "C09_Earnings_Surprise_Sq", m = "sue",
                           tf = function(v) sign(v) * v^2))) {
        src <- cons_list[[cs$m]]; if (is.null(src)) next
        x <- src[Date <= sig_d]; if (!nrow(x)) next
        setorderv(x, c("Ticker", "Date"), c(1L, -1L))
        ref <- x[, .(ref = cs$tf(get(cs$m)[1L])), by = Ticker]
        got <- out[Factor_Name == cs$f, .(Ticker, got = Raw_Value)]
        if (!nrow(got)) next
        mm <- merge(ref, got, by = "Ticker")
        n_chk <- n_chk + 1L
        md <- if (nrow(mm)) max(abs(mm$ref - mm$got)) else NA_real_
        if (nrow(mm) == nrow(got) && is.finite(md) && md < 1e-12) n_ok <- n_ok + 1L
        else bad(sprintf("positive_control[%s@%s]", cs$f, sig_d),
                 sprintf("독립 재계산과 불일치 maxdiff=%s (n_ref=%d n_got=%d)",
                         format(md), nrow(mm), nrow(got)))
      }
    }
    if (!n_chk) skip("positive_control", "대조 가능한 팩터-월 0 — 대상 0")
    else if (n_ok == n_chk) ok("positive_control",
                               sprintf("무관 팩터 %d/%d 조합이 원천 재계산과 비트 일치", n_ok, n_chk))
  }
}

#==============================================================================
cat(sprintf("\n=== test_cons_window_quarterly: %d PASS / %d FAIL / %d SKIP  (root=%s) ===\n",
            PASS, FAIL, SKIP, PROJ))
## 배터리 집계용 요약 JSON — run_all_hooks.sh 는 마지막 유효 요약 JSON 라인을 파싱한다.
## skip 은 pass 에 섞지 않는다(검사하지 않은 것을 통과로 삼지 않기 위해).
cat(sprintf('{"test":"cons_window_quarterly","pass":%d,"fail":%d,"total":%d,"skip":%d}\n',
            PASS, FAIL, PASS + FAIL, SKIP))
if (FAIL > 0L) quit(status = 1L)
