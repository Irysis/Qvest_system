#!/usr/bin/env Rscript
#==============================================================================
# test_rf_adversary_exec_regime.R — 적대검증(G2) 해석 경로의 집행 규약 **양방향 검사** (P0-04 후속 · 2026-09-24)
#
# 왜: 하네스가 close_t1(보유창 (exec, next_exec] · 집행일 수익은 직전 보유 · 비용 = 새 보유 첫 날 곱)으로 바뀌었는데
#   적대검증 해석 경로(.adv_period_index · .adv_holding_period_returns · 노출 경로 비용 기장)는 legacy 창
#   [exec, next_exec) 를 가정했다. close_t1 칸에 legacy 창을 쓰면 집행일 수익이 새 노출 E_{p+1} 로 곱해진다.
#
# 재는 것:
#   A 규약 판독 — 선언(authoritative_remeasure > strategy_spec) × 산출 창(첫 수익일 vs 첫 집행일) · 모순 주입 · essence 표식 대조 · 쌍 판정
#   B 창 해석 — ★위반 주입: 집행일에만 +10% 가 나는 합성에서 close_t1 은 그 수익을 **직전 보유 노출**로 곱한다
#       (독립 재도출한 진실 경로와 비트 일치) · 돌연변이(구판 legacy 창)는 새 노출로 곱해 red ·
#       T3b 보유기간 종목수익도 같은 주입(집행일 +50% 종목)으로 양방향 · legacy 는 구판 참조 구현과 identical
#   C 파이프라인(격리 root) — close_t1 칸 해석 경로 · 규약 혼합(셀 close_t1 × 바닥 legacy) 거부 · 선언 모순 · open_t1 미지원 ·
#       판독 불가는 검정 단계에서 멈춤(pass 로 새지 않음) · legacy 칸 경로 불변 · 돌연변이 2종(규약 무시 · 쌍 판정 제거) red ·
#       거부 verdict 는 소비 술어(rf_runner_gates.R::rf_adversary_ok)에서 보류
#   D T1 재실행 규약 고정 — 스텁 워커 종단: legacy 칸은 legacy 로 재실행(QVEST_CONSTRAINT_DEFAULTS 사본) · 사본은 exec_price 만 바뀜 ·
#       돌연변이(고정을 무시하는 워커) → 실현 규약 불일치 → T1 error(비교 거부) · 설정 부재 → 재실행 없이 error · env 복원
#   E ★2026-09-24 수리 — G-F1 바닥 출처(floor_source carry/none → 바닥 없음 · PORT_t 폴백 금지 · 돌연변이 구판 식별 red) ·
#       I2 rebase 칸 산출물 = 원장 표식 형제 판(돌연변이 구판 판독 = regime_conflict red) · 규약 거부 error 재검정 술어
#       rf_adversary_rerun_blocks(rebase 뒤만 · 돌연변이 구 술어 red) · 러너 배선 블록 추출 실행(돌연변이 구 술어 red)
# 부작용 없음: 픽스처 전부 tempdir. 운영 원장·설정·산출물 무접촉. 자식 Rscript 는 R_ENVIRON_USER=빈 파일.
#==============================================================================
suppressMessages({ library(data.table); library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat("  OK  ", m, "\n") }
ng <- function(m, why = "") { FAIL <<- FAIL + 1L; why <- paste(as.character(why), collapse = " ")   # 길이 0 사유도 죽지 않게(돌연변이 보고 보존)
  cat("  FAIL", m, if (nzchar(why)) paste0(" — ", why) else "", "\n") }
chk <- function(cond, m, why = "") if (isTRUE(cond)) ok(m) else ng(m, why)

ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
ADV <- file.path(ROOT, "02_Infrastructure/reinforcement/rf_overlay_adversary.R")
invisible(capture.output(suppressMessages(source(ADV))))
.adv_load_deps(ROOT)
invisible(capture.output(suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_runner_gates.R")))))
TD <- file.path(tempdir(), sprintf("ax%d", Sys.getpid())); dir.create(TD, recursive = TRUE, showWarnings = FALSE)   # 짧게 — 재실행 산출 경로가 깊다(Windows 260자)
EMPTY_RENV <- file.path(TD, "empty.Renviron"); writeLines("", EMPTY_RENV)
.old_renv <- Sys.getenv("R_ENVIRON_USER", unset = NA); Sys.setenv(R_ENVIRON_USER = EMPTY_RENV)
.old_cdef <- Sys.getenv("QVEST_CONSTRAINT_DEFAULTS", unset = NA); Sys.unsetenv("QVEST_CONSTRAINT_DEFAULTS")

# ── 합성 달력·시장 ────────────────────────────────────────────────────────────
set.seed(20260924L)
days <- seq(as.Date("2005-01-03"), by = "day", length.out = 60L * 31L)
days <- days[as.integer(format(days, "%w")) %in% 1:5]
days <- days[format(days, "%Y-%m") %in% unique(format(days, "%Y-%m"))[1:60]]
exec <- days[!duplicated(format(days, "%Y-%m"))]           # 월 첫 거래일 = 집행일
P <- length(exec); INJ <- 0.10
r_all <- rnorm(length(days), 0.0004, 0.01)
r_all[days %in% exec[-1]] <- INJ                            # ★주입: 집행일(둘째부터)에만 +10%
E <- ifelse(seq_len(P) %% 2L == 1L, 1, 0.2)                  # 홀수 기간 전액 · 짝수 기간 20%
CR <- 0.0015
d_t1 <- days[days > exec[1]]; r_t1 <- r_all[days > exec[1]]  # close_t1 산출: 첫 집행일 수익 행 없음
d_lg <- days[days >= exec[1]]; r_lg <- r_all[days >= exec[1]] # legacy 산출: 첫 집행일부터

# 독립 재도출 진실 경로 (함수 밖 규칙 — 적대검증 코드를 부르지 않는다)
truth_path <- function(dd, rr, regime) {
  p <- vapply(dd, function(t) if (regime == "close_t1") sum(exec < t) else sum(exec <= t), integer(1))
  out <- rr * E[p]
  dE <- c(0, abs(diff(E)))
  for (k in seq_len(P)) {
    pos <- if (regime == "close_t1") which(p == k)[1] else which(dd == exec[k])[1]
    if (is.na(pos)) next
    out[pos] <- if (regime == "close_t1") (1 - dE[k] * CR) * (1 + out[pos]) - 1 else out[pos] - dE[k] * CR
  }
  list(ret = out, p = p)
}
TR_T1 <- truth_path(d_t1, r_t1, "close_t1"); TR_LG <- truth_path(d_lg, r_lg, "close_d_legacy")

# 구판 참조 구현(2026-09-17 판 그대로 — legacy 비트 동일 대조용)
old_period_index <- function(ret_dates, exec_dates) {
  pid <- findInterval(ret_dates, exec_dates)
  keep <- pid >= 1L
  exec_pos <- match(exec_dates, ret_dates)
  for (k in which(is.na(exec_pos))) { cand <- which(pid == k); exec_pos[k] <- if (length(cand)) cand[1] else NA_integer_ }
  list(pid = pid, keep = keep, exec_pos = exec_pos)
}
old_exposure_path <- function(r, period_of, E, exec_pos, cost_rate) {
  E <- as.numeric(E); E[!is.finite(E)] <- 0
  out <- as.numeric(r) * E[period_of]
  dE <- c(0, abs(diff(E)))
  cost <- numeric(length(r)); cost[exec_pos] <- cost[exec_pos] + dE * cost_rate
  out - cost
}
old_hpr <- function(HF, ret_dates, loader) {
  ex <- sort(unique(HF$date)); last_day <- max(ret_dates)
  RAW <- loader(unique(HF$ticker), min(ex), last_day)
  RAW[!is.finite(Ret), Ret := 0]; RAW <- RAW[Date %in% ret_dates]
  RAW[, pid := findInterval(Date, ex)]; RAW <- RAW[pid >= 1L]
  HP <- RAW[, .(R = prod(1 + Ret) - 1), by = .(pid, ticker = Ticker)]
  HF2 <- copy(HF)[, pid := match(date, ex)]
  merge(HF2[, .(pid, ticker, w)], HP, by = c("pid", "ticker"), all.x = TRUE)
}

# 산출물 픽스처 — 03(날짜·수익) · 04(집행일 보유) · 선언(선택)
tk <- sprintf("T%02d", 1:10)
mk_art <- function(name, dd, rr, Evec = rep(1, P), auth = NULL, spec = NULL, write03 = TRUE) {
  d <- file.path(TD, "arts", name); dir.create(d, recursive = TRUE, showWarnings = FALSE)
  if (write03) fwrite(data.table(date = dd, frequency = "daily", ret_gross = rr, ret_net = rr), file.path(d, "03_period_returns.csv"))
  H <- CJ(date = exec, ticker = tk); H[, target_weight := (1 / length(tk)) * Evec[match(date, exec)]]
  fwrite(H, file.path(d, "04_holdings.csv"))
  if (!is.null(auth)) write(toJSON(list(measurement_regime = list(exec_price = auth)), auto_unbox = TRUE), file.path(d, "authoritative_remeasure.json"))
  if (!is.null(spec)) write(toJSON(list(exec_price = spec), auto_unbox = TRUE), file.path(d, "01_strategy_spec.json"))
  d
}

cat("=== A. 규약 판독 (선언 × 산출 창) ===\n")
a_t1  <- mk_art("a_t1", d_t1, r_t1, auth = "close_t1")
a_lg0 <- mk_art("a_lg0", d_lg, r_lg)                         # 선언 없음(P0-01 이전 형태)
a_t10 <- mk_art("a_t10", d_t1, r_t1)                         # 선언 없음 · exclusive 창
a_lie <- mk_art("a_lie", d_lg, r_lg, auth = "close_t1")      # ★주입: close_t1 이라 선언했는데 창은 legacy
a_dis <- mk_art("a_dis", d_t1, r_t1, auth = "close_t1", spec = "close_d_legacy")
a_opn <- mk_art("a_opn", d_lg, r_lg, auth = "open_t1")
a_late <- mk_art("a_late", d_lg[d_lg >= exec[3]], r_lg[d_lg >= exec[3]])   # 보유가 수익보다 먼저 시작해 창이 안 맞음
x <- .adv_resolve_exec(a_t1);  chk(identical(x$exec_price, "close_t1") && identical(x$status, "declared_verified") && identical(x$window, "exec_exclusive"), "A1 선언 close_t1 + 산출 창 (exec,…] → declared_verified", paste(x$status, x$window))
x <- .adv_resolve_exec(a_lg0); chk(identical(x$exec_price, "close_d_legacy") && identical(x$status, "derived"), "A2 선언 부재 + 첫 수익일 = 첫 집행일 → legacy(재도출)", paste(x$status, x$exec_price))
x <- .adv_resolve_exec(a_t10); chk(identical(x$exec_price, "close_t1") && identical(x$status, "derived"), "A3 선언 부재 + 첫 수익일 > 첫 집행일 → close_t1(재도출)", paste(x$status, x$exec_price))
x <- .adv_resolve_exec(a_lie); chk(is.na(x$exec_price) && identical(x$status, "conflict"), "A4 [주입] 선언 close_t1 ≠ 산출 창 legacy → conflict(선언을 믿지 않는다)", paste(x$status, x$exec_price))
x <- .adv_resolve_exec(a_dis); chk(is.na(x$exec_price) && identical(x$status, "conflict") && grepl("선언 모순", x$source), "A5 [주입] authoritative_remeasure ≠ strategy_spec → conflict", x$source)
x <- .adv_resolve_exec(a_late); chk(is.na(x$exec_price) && identical(x$status, "unknown"), "A6 산출 창 판독 불가 + 선언 없음 → unknown(추정 안 함)", paste(x$status, x$window))
att <- function(art, tag = NULL) { a <- list(n = 1L, artifacts = art, essence = list(port_t = 1, calmar = 0.5)); if (!is.null(tag)) a$essence$exec_price <- tag; a }
x <- .adv_attempt_exec(att(a_lg0, "close_t1"), a_lg0); chk(identical(x$status, "conflict"), "A7 [주입] 원장 essence 규약(close_t1) ≠ 산출물(legacy) → conflict(등급 수치와 경로가 다른 규약)", x$status)
x <- .adv_attempt_exec(att("", "close_t1"), ""); chk(identical(x$status, "essence_only") && identical(x$exec_price, "close_t1"), "A8 산출물 부재 + essence 표식 → essence_only", x$status)
R <- function(ep, st = "derived") list(exec_price = ep, status = st, source = "t", window = "w")
chk(identical(.adv_regime_pair(R("close_t1"), R("close_t1"))$status, "same"), "A9 쌍 same")
chk(identical(.adv_regime_pair(R("close_t1"), R("close_d_legacy"))$status, "mismatch"), "A10 쌍 mismatch")
chk(identical(.adv_regime_pair(R("open_t1"), R("open_t1"))$status, "unsupported"), "A11 open_t1 → unsupported(해석 경로 없음)")
chk(identical(.adv_regime_pair(R(NA_character_, "unknown"), R("close_t1"))$status, "undetermined"), "A12 한쪽 판독 불가 → undetermined")
chk(identical(.adv_regime_pair(R(NA_character_, "conflict"), R(NA_character_, "unknown"))$status, "conflict"), "A13 conflict 가 undetermined 보다 앞선다")
x <- .adv_resolve_exec(a_opn); chk(identical(x$exec_price, "open_t1") && identical(x$status, "declared_verified"), "A14 open_t1 선언 + 집행일 포함 창 → 판독은 되고(쌍 단계에서 거부)", x$status)
# 원장 essence Calmar ↔ 산출물 Calmar 대조 — 재측정(rebase)이 essence 만 바꾸고 산출물 경로가 옛 판을 가리키는 경우
a_val <- mk_art("a_val", d_t1, r_t1)
write(toJSON(list(measurement_regime = list(exec_price = "close_t1"), essence = list(calmar = 0.5)), auto_unbox = TRUE, digits = NA), file.path(a_val, "authoritative_remeasure.json"))
av <- function(cal) list(n = 1L, artifacts = a_val, essence = list(port_t = 1, calmar = cal))
x <- .adv_attempt_exec(av(0.5000004), a_val); chk(identical(x$status, "declared_verified") && identical(x$exec_price, "close_t1"), "A15 essence Calmar ≈ 산출물(직렬화 오차 안 · 4e-7) → 대조 통과", x$status)
x <- .adv_attempt_exec(av(0.62), a_val); chk(identical(x$status, "conflict") && is.na(x$exec_price) && grepl("Calmar", x$source, fixed = TRUE),
    "A16 [주입] essence Calmar 0.62 ≠ 산출물 0.5(규약 표식 없음) → conflict — 등급 수치와 해석 경로가 다른 측정", x$source)

cat("=== B. 창 해석 — ★위반 주입: 집행일 수익은 누구의 것인가 ===\n")
px <- .adv_period_index(d_t1, exec, "close_t1")
chk(identical(as.integer(px$pid), TR_T1$p), "B1 close_t1 기간 색인 = 독립 재도출 sum(exec < t) (집행일 exec_k 는 기간 k−1)")
chk(identical(px$exec_pos, vapply(seq_len(P), function(k) which(TR_T1$p == k)[1], integer(1))), "B2 close_t1 비용 기장 위치 = 각 기간 첫 수익일(새 보유 첫 날)")
kp <- which(px$keep); ep1 <- match(px$exec_pos, kp)
obs <- adv_exposure_path(r_t1[kp], px$pid[kp], E, ep1, CR, "multiplicative")
chk(isTRUE(all.equal(obs, TR_T1$ret[kp], tolerance = 1e-14)), "B3 close_t1 노출 경로 = 진실 경로(비트 수준 · 곱 기장)", sprintf("max|Δ| %.3g", max(abs(obs - TR_T1$ret[kp]))))
ex_i <- match(exec[-1], d_t1[kp])
chk(isTRUE(all.equal(obs[ex_i], INJ * E[seq_len(P - 1L)], tolerance = 1e-14)), "B4 [주입] 집행일 +10% 는 **직전 보유**의 노출 E_{k−1} 로 번다(새 보유 E_k 아님)")
pxm <- .adv_period_index(d_t1, exec)                          # 돌연변이 = 구판(legacy 창 가정)
kpm <- which(pxm$keep); obm <- adv_exposure_path(r_t1[kpm], pxm$pid[kpm], E, match(pxm$exec_pos, kpm), CR)
bad <- max(abs(obm[match(exec[-1], d_t1[kpm])] - INJ * E[seq_len(P - 1L)]))
chk(bad > 0.05, sprintf("B5 [돌연변이] legacy 창을 close_t1 산출에 쓰면 집행일 수익을 새 노출로 곱한다(최대 오차 %.3f) — 검사가 가른다", bad))
set.seed(7L); ok_lg <- TRUE
for (s in 1:25) {
  rd <- sort(sample(days, 400L)); ed <- sort(sample(days, 12L))
  if (!identical(.adv_period_index(rd, ed, "close_d_legacy"), old_period_index(rd, ed)) || !identical(.adv_period_index(rd, ed), old_period_index(rd, ed))) ok_lg <- FALSE }
chk(ok_lg, "B6 legacy 색인 = 구판 참조 구현 identical (무작위 25판 · 집행일이 수익일에 없는 경우 포함)")
pxl <- .adv_period_index(d_lg, exec, "close_d_legacy"); kl <- which(pxl$keep); el <- match(pxl$exec_pos, kl)
chk(identical(adv_exposure_path(r_lg[kl], pxl$pid[kl], E, el, CR), old_exposure_path(r_lg[kl], pxl$pid[kl], E, el, CR)) &&
    identical(adv_exposure_path(r_lg[kl], pxl$pid[kl], E, el, CR, "additive"), old_exposure_path(r_lg[kl], pxl$pid[kl], E, el, CR)),
    "B7 legacy 노출 경로(가산 기장) = 구판 identical")
chk(isTRUE(all.equal(adv_exposure_path(r_lg[kl], pxl$pid[kl], E, el, CR), TR_LG$ret[kl], tolerance = 1e-14)), "B8 legacy 노출 경로 = legacy 진실 경로(집행일 수익은 새 보유 · 집행일 가산 기장)")
e_bad <- tryCatch({ .adv_period_index(d_t1, exec, "open_t1"); "no" }, error = function(e) "stop")
chk(identical(e_bad, "stop"), "B9 해석 경로가 없는 규약(open_t1)은 색인 단계에서 멈춘다")
# T3b 보유기간 종목수익 — 종목 T01 이 exec_2 에만 +50%
RAW <- CJ(Date = days, Ticker = tk)[, Ret := 0.001]; RAW[Ticker == "T01" & Date == exec[2], Ret := 0.5]
loader <- function(tickers, from, to) RAW[Ticker %in% tickers & Date >= as.Date(from) & Date <= as.Date(to)]
HF <- CJ(date = exec, ticker = tk)[, w := 1 / length(tk)]
hp_t1 <- .adv_holding_period_returns(HF, d_t1, loader, "close_t1")
tr_hp <- function(k, t, regime) { win <- if (regime == "close_t1") days[days > exec[k] & (k == P | days <= exec[min(k + 1L, P)])] else
                                              days[days >= exec[k] & (k == P | days < exec[min(k + 1L, P)])]
  win <- win[win %in% (if (regime == "close_t1") d_t1 else d_lg)]; x <- RAW[Ticker == t & Date %in% win]$Ret; if (length(x)) prod(1 + x) - 1 else NA_real_ }
hp_t1[, truth := mapply(tr_hp, pid, ticker, MoreArgs = list(regime = "close_t1"))]
chk(isTRUE(all.equal(hp_t1$R, hp_t1$truth, tolerance = 1e-14)), "B10 close_t1 보유기간 종목수익 = 진실 (exec_k, exec_{k+1}] 복리")
chk(hp_t1[pid == 1L & ticker == "T01"]$R > 0.4 && hp_t1[pid == 2L & ticker == "T01"]$R < 0.1, "B11 [주입] T01 의 집행일(exec_2) +50% 는 기간 1(직전 보유)의 몫")
hp_m <- old_hpr(HF, d_t1, loader)
chk(hp_m[pid == 2L & ticker == "T01"]$R > 0.4, "B12 [돌연변이] 구판 창은 그 +50% 를 기간 2(새 보유)에 준다 — 검사가 가른다")
chk(identical(.adv_holding_period_returns(HF, d_lg, loader, "close_d_legacy"), old_hpr(HF, d_lg, loader)) &&
    identical(.adv_holding_period_returns(HF, d_lg, loader), old_hpr(HF, d_lg, loader)), "B13 legacy 보유기간 종목수익 = 구판 identical")

cat("=== C. 파이프라인 (격리 root · 합성 산출물) ===\n")
mk_root <- function(name, engine_lines = c("# stub engine — overlay 옵션 없음", "x <- 1"), rp_lines = c("# stub runner", "y <- 1")) {
  FR <- file.path(TD, name)
  for (d in c("06_Registry", ".cache/rf_parallel", "02_Infrastructure/reinforcement/overlay_arms", "02_Infrastructure/alpha_search",
              "02_Infrastructure/ops", "02_Infrastructure/worktask"))
    dir.create(file.path(FR, d), recursive = TRUE, showWarnings = FALSE)
  writeLines("# stub", file.path(FR, "02_Infrastructure/config.R"))
  writeLines(engine_lines, file.path(FR, "02_Infrastructure/reinforcement/rf_cell_engine.R"))
  writeLines(rp_lines, file.path(FR, "02_Infrastructure/alpha_search/run_paper_replication.R"))
  write(toJSON(list(id = "brake_s", family = "drawdown", basis = "b"), auto_unbox = TRUE), file.path(FR, "02_Infrastructure/reinforcement/overlay_arms/brake_s.arm.json"))
  write(toJSON(list(fixed_axes = list(commission_bps = 15)), auto_unbox = TRUE), file.path(FR, "06_Registry/reinforce_program.json"))
  write(toJSON(list(overlay_adversary = list(enabled = TRUE, alpha = 0.05, n_placebo = 40, max_candidates = 3), worker_timeout_sec = 120), auto_unbox = TRUE),
        file.path(FR, "06_Registry/reinforce_auto_config.json"))
  FR
}
mk_spec <- function(FR, bid, code, block, overlay = NULL, floor_code = NULL) {
  s <- list(code = code, label = code, idea = sprintf("[fixt %s]", code), block = block, base_weight = 0.5,
            factors = list(list(kind = "db", id = "F1")), weighting = list(kind = "ew"), universe = list(kind = "k200_kq150"))
  if (!is.null(overlay)) { s$overlay <- overlay; s$overlay_basis <- "fixture" }
  if (!is.null(floor_code)) s$floor_code <- floor_code
  p <- file.path(FR, ".cache/rf_parallel", sprintf("spec_%s__%s.json", code, bid)); write(toJSON(s, auto_unbox = TRUE, pretty = TRUE, null = "null"), p); p
}
OV <- list(kind = "brake_s", arm_id = "brake_s")
entry <- function(FR, bid, art_floor, art_cell, cal_f = 0.30, cal_c = 0.50) {
  list(base_id = bid, paper_key = "fixture", status = "active", base_grade = "C", attempts_used = 2L,
       attempts = list(
         list(n = 1L, cell_code = "B1_1", grade = "B", artifacts = art_floor,
              essence = list(cell_code = "B1_1", port_t = 2.5, calmar = cal_f, spec = mk_spec(FR, bid, "B1_1", "B1"))),
         list(n = 2L, cell_code = "B5_16", grade = "B", artifacts = art_cell,
              essence = list(cell_code = "B5_16", port_t = 2.4, calmar = cal_c, spec = mk_spec(FR, bid, "B5_16", "B5", OV, "B1_1")))))
}
FR <- mk_root("C")
f_t1 <- mk_art("f_t1", d_t1, r_t1, auth = "close_t1");  c_t1 <- mk_art("c_t1", d_t1, r_t1, E, auth = "close_t1")
f_lg <- mk_art("f_lg", d_lg, r_lg);                     c_lg <- mk_art("c_lg", d_lg, r_lg, E)
c_lie <- mk_art("c_lie", d_lg, r_lg, E, auth = "close_t1")
f_op <- mk_art("f_op", d_lg, r_lg, auth = "open_t1");   c_op <- mk_art("c_op", d_lg, r_lg, E, auth = "open_t1")
c_und <- mk_art("c_und", d_t1, r_t1, E, write03 = FALSE)   # 03 부재 + 선언 부재 → 판독 불가
led <- list(schema_version = "reinforce_ledger_v2", layer = 1L, max_attempts = 25L, entries = list(
  entry(FR, "E_T1", f_t1, c_t1), entry(FR, "E_MIX", f_lg, c_t1), entry(FR, "E_LIE", f_t1, c_lie),
  entry(FR, "E_OPN", f_op, c_op), entry(FR, "E_LG", f_lg, c_lg), entry(FR, "E_UND", f_t1, c_und)))
LPF <- file.path(FR, "06_Registry/reinforce_ledger_l1.json"); write(toJSON(led, auto_unbox = TRUE, pretty = TRUE, null = "null", digits = NA), LPF)
md0 <- tools::md5sum(LPF)
run <- function(bid, env = globalenv(), root = FR, reruns = "skip") {
  f <- get("rf_overlay_adversary_run", envir = env)
  S <- NULL; invisible(capture.output(S <- f(bid, "B5", 1L, root = root, dry_run = TRUE, reruns = reruns, rawdata_loader = loader)))
  list(S = S, J = fromJSON(S[code == "B5_16"]$json, simplifyVector = FALSE))
}
cal <- function(x) adv_calmar_from_ret(x, 252)$calmar
rel <- function(a, b) abs(a - b) / max(1, abs(b))
# 진실 경로는 **파일에서 다시 읽은** 수익으로 만든다(fwrite 15자리 직렬화 — 적대검증이 보는 입력과 같은 값)
rf_t1 <- fread(file.path(f_t1, "03_period_returns.csv"))$ret_net; rf_lg <- fread(file.path(f_lg, "03_period_returns.csv"))$ret_net
TRF_T1 <- truth_path(d_t1, rf_t1, "close_t1"); TRF_LG <- truth_path(d_lg, rf_lg, "close_d_legacy")
z <- run("E_T1"); J <- z$J
chk(identical(J$exec_regime$status, "same") && identical(J$exec_regime$exec_price, "close_t1") && isTRUE(J$candidate), "C1 close_t1 × close_t1 → 같은 규약 · 후보 진행", paste(J$exec_regime$status, J$reason))
chk(identical(J$approximation$exec_price, "close_t1") && identical(J$approximation$holding_window, "(exec, next_exec]") && identical(J$approximation$cost_booking, "multiplicative"),
    "C2 근사 경로 기록 = close_t1 · (exec, next_exec] · 곱 기장")
chk(isTRUE(abs(J$approximation$floor_approx_gap - (cal(rf_t1) - 0.30)) < 1e-9), "C3 바닥 근사 = 바닥 ret_net 그대로(E≡1)", sprintf("%.3g", J$approximation$floor_approx_gap - (cal(rf_t1) - 0.30)))
chk(isTRUE(rel(J$tests$T3$obs_calmar, cal(TRF_T1$ret)) < 1e-9), sprintf("C4 T3 관측 Calmar = close_t1 진실 경로 Calmar (%.6f · 상대오차 < 1e-9)", cal(TRF_T1$ret)),
    sprintf("%.10f vs %.10f", J$tests$T3$obs_calmar %||% NA, cal(TRF_T1$ret)))
EM <- new.env(); invisible(capture.output(sys.source(ADV, envir = EM)))
EM$.adv_attempt_exec <- function(a, art, ...) list(exec_price = "close_d_legacy", status = "derived", source = "mutant: 구판 legacy 가정", window = "exec_inclusive")
zm <- run("E_T1", EM)
chk(is.finite(zm$J$tests$T3$obs_calmar %||% NA) && rel(zm$J$tests$T3$obs_calmar, cal(TRF_T1$ret)) > 1e-3,
    sprintf("C5 [돌연변이] 규약을 무시(legacy 가정)하면 close_t1 칸의 T3 관측이 진실과 갈린다(%.4f vs %.4f)", zm$J$tests$T3$obs_calmar %||% NA, cal(TRF_T1$ret)))
z <- run("E_MIX"); J <- z$J
chk(identical(J$verdict, "error") && startsWith(J$reason, "regime_mismatch") && !isTRUE(J$candidate) && !length(J$tests),
    "C6 [주입] 셀 close_t1 × 바닥 legacy → verdict error(regime_mismatch) · 후보 아님 · 검정 0 (Calmar 비교 거부)", paste(J$verdict, substr(J$reason, 1, 40)))
chk(identical(z$S[code == "B5_16"]$exec_regime, "regime_mismatch"), "C7 요약 표 exec_regime 열 = regime_mismatch")
EM2 <- new.env(); invisible(capture.output(sys.source(ADV, envir = EM2)))
EM2$.adv_regime_pair <- function(cell, floor) list(status = "undetermined", exec_price = NA_character_, cell = cell, floor = floor)
J2 <- run("E_MIX", EM2)$J
chk(!startsWith(J2$reason, "regime_mismatch") && isTRUE(J2$candidate), "C8 [돌연변이] 쌍 판정을 무력화하면 규약 혼합 칸이 후보로 통과해 교차 규약 Calmar 비교가 일어난다 — 가드가 막고 있다", J2$reason)
J <- run("E_LIE")$J; chk(identical(J$verdict, "error") && startsWith(J$reason, "regime_conflict"), "C9 [주입] 셀 선언 모순(close_t1 선언 · legacy 창) → error(regime_conflict)", substr(J$reason, 1, 40))
J <- run("E_OPN")$J; chk(identical(J$verdict, "error") && startsWith(J$reason, "regime_unsupported"), "C10 open_t1 칸 → error(regime_unsupported)", substr(J$reason, 1, 40))
J <- run("E_LG")$J
chk(identical(J$exec_regime$exec_price, "close_d_legacy") && identical(J$exec_regime$cell$status, "derived") && identical(J$approximation$cost_booking, "additive") &&
    identical(J$approximation$cost, sprintf("|ΔE_p| × %.4f at exec (first ΔE = 0)", CR)), "C11 legacy 칸(선언 없음) → 재도출 legacy · 가산 기장 · 구판 문자열")
chk(isTRUE(rel(J$tests$T3$obs_calmar, cal(TRF_LG$ret)) < 1e-9), "C12 legacy 칸 T3 관측 = legacy 진실 경로(집행일 수익은 새 보유)",
    sprintf("%.10f vs %.10f", J$tests$T3$obs_calmar %||% NA, cal(TRF_LG$ret)))
J <- run("E_UND")$J
chk(identical(J$verdict, "error") && grepl("regime_undetermined", J$reason, fixed = TRUE) && isTRUE(J$candidate),
    "C13 행 단계 판독 불가 → 검정 단계가 다시 판독해 멈춘다(verdict error · pass 로 새지 않음)", substr(J$reason, 1, 60))
chk(identical(md0, tools::md5sum(LPF)), "C14 dry_run — 격리 원장 무변")
advs <- list(pass = list(verdict = "pass"), mix = list(verdict = "error", reason = "regime_mismatch: x"))
chk(isTRUE(rf_adversary_ok(list(adversary = advs$pass))) && !isTRUE(rf_adversary_ok(list(adversary = advs$mix))),
    "C15 규약 거부 verdict(error) 는 소비 술어에서 보류(rf_runner_gates.R::rf_adversary_ok)")

cat("=== D. T1 재실행 규약 고정 (스텁 워커 종단) ===\n")
FD <- mk_root("D", engine_lines = c(".shift <- as.integer(SPEC$overlay_shift %||% 0L)", ".strict <- isTRUE(SPEC$overlay_strict)"),
              rp_lines = c('if (!identical(Sys.getenv("QVEST_RP_NO_LCODE", "0"), "1")) z <- 1'))
CDEF <- list(schema = "constraint_defaults", tier_graduation = list(port_t = 2.95),
             execution = list(exec_price = "close_t1", open_t1_overnight_limit = list(list(from = "1998-12-07", limit = 0.15), list(from = "2015-06-15", limit = 0.30)),
                              note = "fixture"))
CDP <- file.path(FD, "02_Infrastructure/worktask/constraint_defaults.json"); write(toJSON(CDEF, auto_unbox = TRUE, pretty = TRUE, digits = NA), CDP)
writeLines(c(
  'suppressMessages(library(jsonlite)); a <- commandArgs(trailingOnly = TRUE); `%||%` <- function(x, y) if (is.null(x) || length(x) == 0L) y else x',
  '# 하네스 rep_execution_config 흉내 — 레버(QVEST_CONSTRAINT_DEFAULTS)가 있으면 그 파일, 없으면 root 설정. ignore = 레버를 무시하는 돌연변이',
  'cp <- Sys.getenv("QVEST_CONSTRAINT_DEFAULTS", "")',
  'if (identical(Sys.getenv("STUB_MODE"), "ignore") || !nzchar(cp)) cp <- Sys.getenv("STUB_ROOT_CFG")',
  'ep <- fromJSON(cp, simplifyVector = TRUE)$execution$exec_price',
  'art <- file.path(dirname(a[4]), "art"); dir.create(art, recursive = TRUE, showWarnings = FALSE)',
  'write(toJSON(list(measurement_regime = list(exec_price = ep)), auto_unbox = TRUE), file.path(art, "authoritative_remeasure.json"))',
  'writeLines(cp, file.path(dirname(a[4]), "stub_cfg_used.txt"))',
  'write(toJSON(list(n = as.integer(a[2]), ok = TRUE, grade = "B", artifacts = art, essence = list(calmar = 9, port_t = 1)), auto_unbox = TRUE), a[4])'),
  file.path(FD, "02_Infrastructure/ops/rf_cell_worker.R"))
Sys.setenv(STUB_ROOT_CFG = CDP)
ledD <- list(schema_version = "reinforce_ledger_v2", layer = 1L, max_attempts = 25L, entries = list(entry(FD, "D_LG", f_lg, c_lg), entry(FD, "D_T1", f_t1, c_t1)))
write(toJSON(ledD, auto_unbox = TRUE, pretty = TRUE, null = "null", digits = NA), file.path(FD, "06_Registry/reinforce_ledger_l1.json"))
pre_env <- Sys.getenv("QVEST_CONSTRAINT_DEFAULTS", unset = NA)
J <- run("D_LG", root = FD, reruns = "auto")$J; T1 <- J$tests$T1
chk(identical(T1$status, "pass") && identical(T1$exec_price, "close_d_legacy") && identical(T1$exec_price_realized, "close_d_legacy"),
    "D1 legacy 칸 T1 → legacy 로 재실행(설정 기본 close_t1 을 덮어 고정) · 실현 규약 대조 통과", paste(T1$status, T1$exec_price_realized %||% "", T1$detail %||% ""))
pin <- if (!is.null(T1$exec_pin$path) && file.exists(T1$exec_pin$path)) fromJSON(T1$exec_pin$path, simplifyVector = FALSE) else NULL
src <- fromJSON(CDP, simplifyVector = FALSE)
pin_ex <- pin$execution; pin_ex$exec_price <- NULL; src_ex <- src$execution; src_ex$exec_price <- NULL
chk(!is.null(pin) && identical(pin$execution$exec_price, "close_d_legacy") && identical(pin_ex, src_ex) && identical(src$execution$exec_price, "close_t1"),
    "D2 고정 사본 = execution.exec_price 만 바뀜(다른 키 동일) · 원본 설정 무변")
uf <- file.path(dirname(T1$spec %||% TD), "stub_cfg_used.txt")
used <- if (file.exists(uf)) readLines(uf, warn = FALSE) else character(0)
.np <- function(x) tolower(gsub("\\\\", "/", x))   # 경로 비교(구분자·대소문자) — 존재 확인은 file.exists 가 한다
chk(length(used) == 1L && file.exists(used) && identical(.np(used), .np(T1$exec_pin$path)), "D3 워커(자식)는 QVEST_CONSTRAINT_DEFAULTS 로 고정 사본을 읽었다")
chk(identical(Sys.getenv("QVEST_CONSTRAINT_DEFAULTS", unset = NA), pre_env), "D4 재실행 뒤 부모 env 복원(QVEST_CONSTRAINT_DEFAULTS)")
J <- run("D_T1", root = FD, reruns = "auto")$J
chk(identical(J$tests$T1$status, "pass") && identical(J$tests$T1$exec_price_realized, "close_t1"), "D5 close_t1 칸 T1 → close_t1 로 재실행 · 실현 대조 통과")
Sys.setenv(STUB_MODE = "ignore")
J <- run("D_LG", root = FD, reruns = "auto")$J; T1 <- J$tests$T1
chk(identical(T1$status, "error") && startsWith(T1$detail %||% "", "regime_mismatch_rerun") && !identical(J$verdict, "pass"),
    "D6 [돌연변이] 고정을 무시하는 워커(설정 기본 close_t1 로 재실행) → 실현 규약 불일치 → T1 error · 바닥 Calmar 비교 거부", paste(T1$status, substr(T1$detail %||% "", 1, 50)))
Sys.unsetenv("STUB_MODE")
invisible(file.rename(CDP, paste0(CDP, ".off"))); Sys.setenv(STUB_ROOT_CFG = "")
unlink(file.path(FD, ".cache/rf_overlay_adversary/D_LG/B5_16/T1/stub_cfg_used.txt"))
J <- run("D_LG", root = FD, reruns = "auto")$J; T1 <- J$tests$T1
chk(identical(T1$status, "error") && grepl("exec_price 고정 실패", T1$detail %||% "", fixed = TRUE) &&
    !file.exists(file.path(FD, ".cache/rf_overlay_adversary/D_LG/B5_16/T1/stub_cfg_used.txt")),
    "D7 설정 부재 → 고정 실패 → 워커를 띄우지 않고 T1 error(고정 없는 재실행 금지)", substr(T1$detail %||% "", 1, 60))
e1 <- tryCatch({ .adv_pin_exec_config(FD, "open_t1", TD); "no" }, error = function(e) "stop")
chk(identical(e1, "stop"), "D8 해석 경로가 없는 규약(open_t1)으로는 고정하지 않는다")

cat("=== E. ★2026-09-24 수리 — 바닥 출처(G-F1) · rebase 칸 산출물(I2) · 규약 거부 재검정(I2) ===\n")
FE <- mk_root("E")
spec_at <- function(bid, code, block, extra = list(), factors = list(list(kind = "db", id = "F1")), overlay = NULL) {
  s <- c(list(code = code, label = code, idea = sprintf("[fixt %s]", code), block = block, base_weight = 0.5, factors = factors,
              weighting = list(kind = "ew"), universe = list(kind = "k200_kq150")), extra)
  if (!is.null(overlay)) { s$overlay <- overlay; s$overlay_cell <- overlay; s$overlay_basis <- "fixture" }
  p <- file.path(FE, ".cache/rf_parallel", sprintf("spec_%s__%s.json", code, bid)); write(toJSON(s, auto_unbox = TRUE, pretty = TRUE, null = "null"), p); p
}
entry_e <- function(bid, art_f, art_c, b5_extra = list(), b5_factors = list(list(kind = "db", id = "F1")), mr_f = NULL, mr_c = NULL,
                    cal_f = 0.30, cal_c = 0.50) {
  a1 <- list(n = 1L, cell_code = "B1_1", grade = "B", artifacts = art_f,
             essence = list(cell_code = "B1_1", port_t = 3.1, calmar = cal_f, spec = spec_at(bid, "B1_1", "B1")))
  a2 <- list(n = 2L, cell_code = "B5_16", grade = "B", artifacts = art_c,
             essence = list(cell_code = "B5_16", port_t = 2.4, calmar = cal_c, spec = spec_at(bid, "B5_16", "B5", b5_extra, b5_factors, OV)))
  if (!is.null(mr_f)) a1$measurement_regime <- mr_f
  if (!is.null(mr_c)) a2$measurement_regime <- mr_c
  list(base_id = bid, paper_key = "fixture", status = "active", base_grade = "C", attempts_used = 2L, attempts = list(a1, a2))
}
# I2 픽스처: 원장 artifacts = 옛(legacy) 산출물 · 원장 표식 remeasure_path = close_t1 형제 판(03/04 포함) — P0-06 rebase 뒤 모양
mr_rb <- function(dir) list(regime = "close_t1_ab12cd34", key = "close_t1_ab12cd34", exec_price = "close_t1", basis = "rebase",
                            remeasure_path = file.path(dir, "authoritative_remeasure.json"), rebased_at = "2026-09-24T21:00:00+0900")
ledE <- list(schema_version = "reinforce_ledger_v2", layer = 1L, max_attempts = 25L, entries = list(
  entry_e("E_CARRY", f_t1, c_t1, b5_extra = list(floor_source = "carry", floor_carry_cell = "B1_2")),   # ★G-F1: 바닥 = carry(측정 칸 아님)
  entry_e("E_NONE", f_t1, c_t1, b5_extra = list(floor_source = "none")),
  entry_e("E_FB", f_t1, c_t1, b5_factors = list(list(kind = "db", id = "F9"))),                        # floor_code·floor_source 없음 · 서명 불일치
  entry_e("E_ATT", f_t1, c_t1, b5_extra = list(floor_source = "attempt", floor_code = "B1_1")),          # 양성 대조
  entry_e("E_RB", f_lg, c_lg, b5_extra = list(floor_source = "attempt", floor_code = "B1_1"), mr_f = mr_rb(f_t1), mr_c = mr_rb(c_t1))))
write(toJSON(ledE, auto_unbox = TRUE, pretty = TRUE, null = "null", digits = NA), file.path(FE, "06_Registry/reinforce_ledger_l1.json"))
runE <- function(bid, env = globalenv()) run(bid, env, root = FE)
J <- runE("E_CARRY")$J
chk(identical(J$verdict, "not_candidate") && identical(J$reason, "floor_carry") && is.null(J$floor) && !length(J$tests) &&
      identical(J$floor_resolution$floor_source, "carry"),
    "E1 ★G-F1 floor_source=carry → 바닥 없음(not_candidate · floor_carry) · 검정 0 · entry 칸(B1_1)과 비교하지 않는다", paste(J$verdict, J$reason))
J <- runE("E_NONE")$J
chk(identical(J$verdict, "not_candidate") && identical(J$reason, "floor_missing"), "E2 floor_source=none → floor_missing", paste(J$verdict, J$reason))
J <- runE("E_FB")$J
chk(identical(J$verdict, "not_candidate") && identical(J$reason, "floor_unidentified") && identical(J$floor_resolution$match, "port_t_fallback_refused"),
    "E3 floor_code·출처 없음 + 서명 불일치 → PORT_t 폴백 금지(floor_unidentified — 짐작한 바닥 위의 pass 금지)", paste(J$verdict, J$reason))
J <- runE("E_ATT")$J
chk(isTRUE(J$candidate) && identical(J$floor$code, "B1_1") && identical(J$floor$match, "floor_code") && length(J$tests) > 0L,
    "E4 [양성 대조] floor_source=attempt · floor_code → 그 칸이 바닥 · 검정 진행", paste(J$verdict, J$reason))
# 돌연변이 — 구판 .adv_floor_of(floor_source 무시 · PORT_t 폴백)면 carry 바닥 칸이 entry 칸 B1_1 과 비교돼 후보가 된다
EF <- new.env(); invisible(capture.output(sys.source(ADV, envir = EF)))
EF$.adv_floor_of <- function(a, spec, own, attempts, block, root, base_id) {
  meas <- Filter(function(x) is.list(x$essence) && !is.null(x$essence$port_t) && suppressWarnings(as.integer(x$n)) < suppressWarnings(as.integer(a$n)), attempts)
  fc <- as.character(spec$floor_code %||% "")
  if (nzchar(fc)) { hit <- Filter(function(x) identical(.rf_attempt_code(x), fc), meas); if (length(hit)) return(list(attempt = hit[[1]], match = "floor_code")) }
  other <- Filter(function(x) !startsWith(as.character(.rf_attempt_code(x) %||% ""), paste0(block, "_")), meas)
  if (!length(other)) return(list(attempt = NULL, match = NULL))
  v <- vapply(other, function(x) suppressWarnings(as.numeric(x$essence$port_t)), numeric(1))
  list(attempt = other[[which.max(replace(v, !is.finite(v), -Inf))]], match = "port_t_fallback") }
Jm <- runE("E_CARRY", EF)$J
chk(isTRUE(Jm$candidate) && identical(Jm$floor$match, "port_t_fallback"),
    "E5 [돌연변이] 구판 바닥 식별 → carry 바닥 칸이 PORT_t 폴백(B1_1)과 비교돼 후보·검정 진행 — E1 이 이 결함을 잡는다", paste(Jm$reason, Jm$floor$match %||% ""))
# I2 — rebase 칸: 산출물 = 원장 표식 형제 판(close_t1) · 옛 legacy 산출물을 읽지 않는다
J <- runE("E_RB")$J
chk(identical(J$exec_regime$status, "same") && identical(J$exec_regime$exec_price, "close_t1") && isTRUE(J$candidate) &&
      isTRUE(rel(J$tests$T3$obs_calmar, cal(TRF_T1$ret)) < 1e-9) && identical(.np(J$cell$artifacts), .np(c_t1)),
    "E6 ★I2 rebase 칸(원장 artifacts = legacy · 표식 remeasure_path = close_t1 판) → 형제 판으로 해석 · 같은 규약 · T3 = close_t1 진실 경로",
    paste(J$exec_regime$status, J$verdict, substr(J$reason, 1, 60)))
EA <- new.env(); invisible(capture.output(sys.source(ADV, envir = EA)))
EA$.adv_art_dir <- function(a, root) { ar <- as.character(a$artifacts %||% ""); ar }   # 구판: 원장 artifacts 만
Jm <- runE("E_RB", EA)$J
chk(identical(Jm$verdict, "error") && grepl("regime_conflict", Jm$reason, fixed = TRUE),
    "E7 [돌연변이] 구판 산출물 판독(표식 무시) → 원장 close_t1 표식 × legacy 산출물 = regime_conflict error(통합 검증 I2 재현) — E6 이 잡는다",
    paste(Jm$verdict, substr(Jm$reason, 1, 60)))
# I2 — 규약 거부 error 의 재검정 술어(러너 tick 시작)
at0 <- "2026-09-24T20:00:00+0900"; at1 <- "2026-09-24T22:00:00+0900"
eR <- function(v_at, rb_at, verdict = "error", reason = "regime_mismatch: cell=close_t1 floor=close_d_legacy") {
  a1 <- list(n = 1L, cell_code = "B1_1", essence = list(port_t = 3))
  if (!is.null(rb_at)) a1$measurement_regime <- list(regime = "close_t1_ab12cd34", rebased_at = rb_at)
  a2 <- list(n = 2L, cell_code = "B5_16", essence = list(port_t = 2), adversary = list(verdict = verdict, reason = reason, block = "B5", at = v_at))
  list(base_id = "X", attempts = list(a1, a2)) }
r1 <- rf_adversary_rerun_blocks(eR(at0, at1)); r2 <- rf_adversary_rerun_blocks(eR(at1, at0)); r3 <- rf_adversary_rerun_blocks(eR(at0, NULL))
r4 <- rf_adversary_rerun_blocks(eR(at0, NULL, "deferred_refresh_lock", "refresh_barrier: x"))
r5 <- rf_adversary_rerun_blocks(eR(at0, at1, "fail", "failed: T3"))
r6 <- rf_adversary_rerun_blocks(eR(at0, at1, "error", "tests_failed: regime_conflict: cell=…"))
chk(identical(r1$blocks, "B5") && grepl("regime_rebased:B5_16", r1$why$B5) && !length(r2$blocks) && !length(r3$blocks) &&
      identical(r4$blocks, "B5") && grepl("deferred:", r4$why$B5) && !length(r5$blocks) && identical(r6$blocks, "B5"),
    "E8 ★I2 재검정 술어 — 규약 거부 error 가 그 뒤 rebase 로 풀릴 수 있을 때만 재실행(판정 뒤 rebase ○ · 앞 rebase × · rebase 없음 × · 연기분 ○ · fail × · 검정 단계 규약 거부 ○)")
old_pred <- function(E) unique(unlist(lapply(E$attempts, function(a) if (identical(as.character((a$adversary %||% list())$verdict %||% "")[1], "deferred_refresh_lock")) "B5" else NULL)))
chk(!length(old_pred(eR(at0, at1))), "E9 [돌연변이] 구판 술어(연기분만)는 rebase 뒤 규약 거부 칸을 다시 검정하지 않는다 — E8 이 잡는다")
# 러너 배선 — 재실행 블록을 러너 소스에서 떼어 실행(스텁 적대검증 · 스텁 원장)
RSRC <- readLines(file.path(ROOT, "02_Infrastructure/ops/reinforce_auto_parallel.R"), warn = FALSE, encoding = "UTF-8")
i0 <- grep("^\\.adv_def_blk <- unique\\(", RSRC)
i1 <- if (length(i0) == 1L) i0 + which(grepl("^\\}$", RSRC[(i0 + 1L):length(RSRC)]))[1] else NA
if (length(i0) != 1L || is.na(i1)) ng("E10 러너 재실행 블록 추출 실패") else {
  RR <- file.path(TD, "rr"); dir.create(file.path(RR, "02_Infrastructure/reinforcement"), recursive = TRUE, showWarnings = FALSE)
  writeLines(c("rf_overlay_adversary_run <- function(bid, block, layer, root) { .CALLS <<- c(.CALLS, paste(bid, block))",
               "  data.table::data.table(code = 'B5_16', verdict = 'pass') }"), file.path(RR, "02_Infrastructure/reinforcement/rf_overlay_adversary.R"))
  run_blk <- function(E0) { env <- new.env(parent = globalenv()); env$E <- E0; env$BID <- "X"; env$ROOT <- RR; env$EV <- character(0)
    assign(".CALLS", character(0), envir = globalenv())
    env$jlog <- function(event, ...) env$EV <- c(env$EV, event)
    env$rf_load <- function(layer, root) list(entries = list(E0))
    eval(parse(text = RSRC[i0:i1]), envir = env); list(calls = get(".CALLS", envir = globalenv()), ev = env$EV) }
  w1 <- run_blk(eR(at0, at1)); w2 <- run_blk(eR(at1, at0))
  chk(identical(w1$calls, "X B5") && "adversary_rerun_regime" %in% w1$ev && !length(w2$calls),
      "E10 러너 배선 — rebase 뒤 규약 거부 칸이 있으면 tick 시작에 적대검증을 다시 부른다(없으면 안 부른다)", paste(w1$ev, collapse = ","))
  # 돌연변이 — 러너가 구판 술어(연기분만)를 쓰면 같은 칸을 다시 부르지 않는다
  blk_m <- RSRC[i0:i1]
  im <- grep("^\\.adv_rr <- rf_adversary_rerun_blocks\\(E", blk_m)
  blk_m[im] <- ".adv_rr <- list(blocks = character(0), why = list())"   # 구판 러너 = 연기분 술어만(규약 거부 재검정 없음)
  wm <- tryCatch({ env <- new.env(parent = globalenv()); E0 <- eR(at0, at1); env$E <- E0; env$BID <- "X"; env$ROOT <- RR
    assign(".CALLS", character(0), envir = globalenv()); env$jlog <- function(event, ...) invisible(NULL)
    env$rf_load <- function(layer, root) list(entries = list(E0)); eval(parse(text = blk_m), envir = env); get(".CALLS", envir = globalenv()) },
    error = function(e) paste("ERR", conditionMessage(e)))
  chk(length(im) == 1L && !length(wm), "E11 [돌연변이] 러너가 구판 술어(연기분만)로 돌면 rebase 뒤 규약 거부 칸을 다시 부르지 않는다 — E10 이 잡는다", paste(wm, collapse = ","))
}

unlink(TD, recursive = TRUE, force = TRUE)
if (is.na(.old_renv)) Sys.unsetenv("R_ENVIRON_USER") else Sys.setenv(R_ENVIRON_USER = .old_renv)
if (!is.na(.old_cdef)) Sys.setenv(QVEST_CONSTRAINT_DEFAULTS = .old_cdef)
cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
cat(sprintf('{"test":"rf_adversary_exec_regime","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL == 0L) 0L else 1L)
