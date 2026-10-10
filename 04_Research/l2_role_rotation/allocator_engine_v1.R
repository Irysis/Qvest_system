#==============================================================================
# allocator_engine_v1.R — 2계층 역할 슬리브 로테이션 v1 배분 엔진 (PR-L2-ROLESLEEVE-V1 · 2026-10-10)
#
# v0 엔진(allocator_engine.R · 동결)과 같은 계약·같은 구성. 바뀐 것은 **방어 슬리브 소속 원천 하나**:
#   방어 = work/l2v1_defensive_labels.parquet(결정일 = 보유월 첫날 · as-of 하방 베타 β− 하위 삼분위 · in_sleeve)
#   공격·반등·α = asof_roles.parquet(ps_confirm phase · is_member) — v0 그대로
# 계약: run_paper_replication(engine_direct) 이 RAWDATA·BM_DT 를 넣은 환경에서 source → PORTFOLIO(Date, Ticker, Weight).
#   Date = 시그널일 s_m · 하네스가 m 첫 거래일 종가(close_t1)로 집행. arm = Sys.getenv("L2V1_ARM") ∈ 설계 arms(T_var·K·S·EW_all).
# PIT(시그널일 s_m 기준 — 쓰는 것 전부 s_m 이하):
#   · 방어 소속 = β− 창 date < m 첫날(= s_m 까지) · 나머지 슬리브 = as-of 역할(자료 < m 첫날)
#   · P(m) = msm_asof_daily Date <= s_m 마지막 Crisis_Prob_asof · 모듈 보유 = exec_date <= 집행일 마지막 스냅샷
#   · 유니버스 = s_m K200∪KQ150 · 유동성 = 20일 평균 거래대금 1일 지연(C10)
#   ★arm K 의 Pbar(창 132개월 P 평균)는 전기간 통계 — 노출 맞춤 대조(실시간 불가 · 후보 아님 · 등급 진단 전용).
# 입력 대조: 매니페스트(기본 work/l2v1_inputs_manifest.json · 검사 전용 L2V1_MANIFEST_PATH)의 files sha256 전부 + L2V1_INPUTS_SHA(있으면).
# 쓰기: L2V1_DIAG_DIR 가 있을 때만 진단 CSV 2개(덮어쓰기 거부). 그 밖 쓰기 0.
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite); library(arrow) })

.l2v1_root <- local({
  cands <- c(Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""), getwd())
  hit <- ""
  for (p in cands) if (nzchar(p) && file.exists(file.path(p, "02_Infrastructure/config.R"))) { hit <- p; break }
  if (!nzchar(hit)) stop("[l2v1_engine] 프로젝트 루트 미발견")
  normalizePath(hit, winslash = "/")
})
.l2v1_dir <- file.path(.l2v1_root, "04_Research/l2_role_rotation")
.l2v1_sha <- function(p) digest::digest(file = p, algo = "sha256")
.l2v1_abs <- function(p) if (grepl("^([A-Za-z]:)?[/\\\\]", p)) p else file.path(.l2v1_root, p)

# ── 0. 설계·입력 지문(동결 대조 — 어긋나면 멈춘다) ───────────────────────────────
.l2v1_man_path <- Sys.getenv("L2V1_MANIFEST_PATH", "")
if (!nzchar(.l2v1_man_path)) .l2v1_man_path <- file.path(.l2v1_dir, "work/l2v1_inputs_manifest.json")
.l2v1_expect <- Sys.getenv("L2V1_INPUTS_SHA", "")
if (nzchar(.l2v1_expect) && !identical(.l2v1_sha(.l2v1_man_path), .l2v1_expect))
  stop("[l2v1_engine] 입력 매니페스트 sha256 ≠ L2V1_INPUTS_SHA — 동결 입력이 바뀌었다")
.l2v1_man <- fromJSON(.l2v1_man_path, simplifyVector = FALSE)
for (.k in names(.l2v1_man$files)) {
  .f <- .l2v1_man$files[[.k]]
  if (!identical(.l2v1_sha(.l2v1_abs(.f$path)), .f$sha256))
    stop(sprintf("[l2v1_engine] 입력 %s(%s) sha256 이 동결값과 다르다 — 측정 중단", .k, .f$path))
}
.l2v1_design <- fromJSON(.l2v1_abs(.l2v1_man$files$design$path), simplifyVector = FALSE)
.l2v1_arm <- Sys.getenv("L2V1_ARM", "")
if (!(.l2v1_arm %in% names(.l2v1_design$arms))) stop(sprintf("[l2v1_engine] L2V1_ARM='%s' — 허용 %s", .l2v1_arm, paste(names(.l2v1_design$arms), collapse = "/")))
.l2v1_fx <- fromJSON(.l2v1_abs(.l2v1_man$files$reinforce_program_fixed_axes$path), simplifyVector = FALSE)$fixed_axes
.l2v1_nmax <- as.integer(.l2v1_fx$n_max)
.l2v1_liq <- as.numeric(.l2v1_fx$liq_adv20_min)
if (!identical(.l2v1_fx$universe, "K200_KQ150") || !isTRUE(.l2v1_fx$long_only) || !is.finite(.l2v1_liq) || is.na(.l2v1_nmax))
  stop("[l2v1_engine] fixed_axes 판독 실패/예상 밖(universe·long_only·n_max·liq_adv20_min)")
.l2v1_roles <- unlist(.l2v1_design$roles)
.l2v1_other <- unlist(.l2v1_design$labels_other_roles$roles)
if (!identical(sort(c("defensive", .l2v1_other)), sort(.l2v1_roles))) stop("[l2v1_engine] 역할 목록 불일치(방어 + 나머지 ≠ roles)")
.l2v1_wvec <- function(key) {
  w <- vapply(.l2v1_roles, function(r) as.numeric(.l2v1_design$sleeve_weights[[key]][[r]]), numeric(1))
  if (any(!is.finite(w)) || any(w < 0) || abs(sum(w) - 1) > 1e-12) stop(sprintf("[l2v1_engine] 슬리브 비중 %s 비정상", key))
  w
}
.l2v1_w_hi <- .l2v1_wvec("w_hi"); .l2v1_w_lo <- .l2v1_wvec("w_lo")

# ── 1. 달력 · 보유월 · 시그널일 · 집행일 ─────────────────────────────────────────
if (!exists("RAWDATA") || !is.data.table(RAWDATA)) stop("[l2v1_engine] RAWDATA(data.table) 가 환경에 없다 — 러너가 넣어야 한다")
.l2v1_cal <- sort(unique(as.Date(RAWDATA$Date)))
.l2v1_hm_first <- as.Date(.l2v1_design$window$first_holding_month)
.l2v1_hm_last  <- as.Date(.l2v1_design$window$last_holding_month)
.l2v1_hm_all <- seq(seq(.l2v1_hm_first, by = "-1 month", length.out = 2L)[2], .l2v1_hm_last, by = "month")  # 한 달 앞(S 의 지연 P 용)
.l2v1_sig_of <- function(m) { x <- .l2v1_cal[.l2v1_cal < m]; if (!length(x)) as.Date(NA) else max(x) }
.l2v1_exe_of <- function(m) { x <- .l2v1_cal[.l2v1_cal >= m]; if (!length(x)) as.Date(NA) else min(x) }
.l2v1_sig_all <- as.Date(vapply(.l2v1_hm_all, function(m) as.numeric(.l2v1_sig_of(m)), numeric(1)), origin = "1970-01-01")
.l2v1_hm  <- .l2v1_hm_all[-1L]
.l2v1_sig <- .l2v1_sig_all[-1L]
.l2v1_exe <- as.Date(vapply(.l2v1_hm, function(m) as.numeric(.l2v1_exe_of(m)), numeric(1)), origin = "1970-01-01")
if (anyNA(.l2v1_sig_all) || anyNA(.l2v1_exe)) stop("[l2v1_engine] 시그널일/집행일 산출 불가(달력 밖)")
if (any(format(.l2v1_exe, "%Y-%m") != format(.l2v1_hm, "%Y-%m")) || any(.l2v1_sig >= .l2v1_hm))
  stop("[l2v1_engine] 시그널일·집행일이 보유월 정의와 어긋난다")

# ── 2. 후보 · 슬리브 소속(방어 = v1 라벨 · 나머지 = as-of 역할) ───────────────────
.l2v1_cand <- fread(.l2v1_abs(.l2v1_man$files$candidates$path))
.l2v1_ar <- as.data.table(read_parquet(.l2v1_abs(.l2v1_man$files$asof_roles$path)))
.l2v1_ar <- .l2v1_ar[ps_confirm == .l2v1_design$labels_other_roles$ps_confirm & role %in% .l2v1_other]
.l2v1_ar[, decision_date := as.Date(decision_date)]
.l2v1_dl <- as.data.table(read_parquet(.l2v1_abs(.l2v1_man$files$defensive_labels$path)))
.l2v1_dl[, decision_date := as.Date(decision_date)]
if (!all(.l2v1_hm %in% .l2v1_ar$decision_date)) stop("[l2v1_engine] 보유월 일부에 as-of 역할 결정월이 없다")
if (!all(.l2v1_hm %in% .l2v1_dl$decision_date)) stop("[l2v1_engine] 보유월 일부에 방어 v1 라벨 결정월이 없다")
if (any(.l2v1_dl[decision_date %in% .l2v1_hm]$window_last >= .l2v1_dl[decision_date %in% .l2v1_hm]$decision_date))
  stop("[l2v1_engine] PIT: 방어 라벨 창 끝이 결정일 이후")
.l2v1_mem <- rbind(
  .l2v1_ar[decision_date %in% .l2v1_hm & is_member == TRUE & member_id %in% .l2v1_cand$member_id, .(decision_date, member_id, role)],
  .l2v1_dl[decision_date %in% .l2v1_hm & in_sleeve == TRUE & member_id %in% .l2v1_cand$member_id, .(decision_date, member_id, role = "defensive")])
.l2v1_mem <- merge(.l2v1_mem, .l2v1_cand[, .(member_id, module_key)], by = "member_id")

# ── 3. 예측기 P(m) — Date <= s_m 마지막 값 ───────────────────────────────────────
.l2v1_ms <- as.data.table(read_parquet(.l2v1_abs(.l2v1_man$files$msm_asof_daily$path)))
.l2v1_ms <- .l2v1_ms[, .(Date = as.Date(Date), P = as.numeric(get(.l2v1_design$predictor$column)))][order(Date)]
.l2v1_p_at <- function(s) { x <- .l2v1_ms[Date <= s]; if (!nrow(x)) NA_real_ else x$P[nrow(x)] }
.l2v1_P_all <- vapply(.l2v1_sig_all, .l2v1_p_at, numeric(1))
if (anyNA(.l2v1_P_all) || any(.l2v1_P_all < -1e-9 | .l2v1_P_all > 1 + 1e-9)) stop("[l2v1_engine] 예측기 P 결측/범위 밖")
.l2v1_P_all <- pmin(pmax(.l2v1_P_all, 0), 1)       # 부동소수 끝자리만(v0 와 같음)
.l2v1_P_T <- .l2v1_P_all[-1L]                      # 보유월 m 의 P(s_m)
.l2v1_P_S <- .l2v1_P_all[-length(.l2v1_P_all)]     # 한 달 지연 P(s_{m-1})
.l2v1_Pbar <- mean(.l2v1_P_T)                      # arm K 전용(노출 맞춤 대조 · 전기간 P 평균 — 후보 아님)

# ── 4. 슬리브 비중 w_r(m) (arm 별) ───────────────────────────────────────────────
.l2v1_sleeve_w <- function(i) {
  switch(.l2v1_arm,
    T_var = .l2v1_P_T[i] * .l2v1_w_hi + (1 - .l2v1_P_T[i]) * .l2v1_w_lo,
    S     = .l2v1_P_S[i] * .l2v1_w_hi + (1 - .l2v1_P_S[i]) * .l2v1_w_lo,
    K     = .l2v1_Pbar * .l2v1_w_hi + (1 - .l2v1_Pbar) * .l2v1_w_lo,
    EW_all = setNames(rep(NA_real_, length(.l2v1_roles)), .l2v1_roles))
}

# ── 5. 모듈 보유 스냅샷(집행일 이하 마지막) ──────────────────────────────────────
.l2v1_pan <- as.data.table(read_parquet(.l2v1_abs(.l2v1_man$files$holdings_panel$path)))
.l2v1_pan[, exec_date := as.Date(exec_date)]
.l2v1_snapdates <- unique(.l2v1_pan[, .(module_key, snap = exec_date)])
setkey(.l2v1_snapdates, module_key, snap)

# ── 6. 유니버스 · 유동성(시그널일 기준 · 1일 지연 거래대금) ──────────────────────
.l2v1_need <- c("Date", "Ticker", "K200", "KQ150", "Close", "Vol")
if (!all(.l2v1_need %in% names(RAWDATA))) stop("[l2v1_engine] RAWDATA 에 필요한 열이 없다: ", paste(setdiff(.l2v1_need, names(RAWDATA)), collapse = ","))
.l2v1_D <- RAWDATA[as.Date(Date) >= (min(.l2v1_sig) - 90) & as.Date(Date) <= max(.l2v1_sig), .(Date = as.Date(Date), Ticker, K200, KQ150, Close, Vol)]
setorder(.l2v1_D, Ticker, Date)
.l2v1_D[, TV := as.numeric(Close) * as.numeric(Vol)]
.l2v1_D[, adv20_l1 := shift(frollmean(TV, 20L, align = "right"), 1L), by = Ticker]   # C10 — 시그널일 당일 거래대금 미사용
.l2v1_U <- .l2v1_D[Date %in% .l2v1_sig & (K200 == TRUE | KQ150 == TRUE) & is.finite(adv20_l1) & adv20_l1 >= .l2v1_liq, .(Date, Ticker)]
.l2v1_Umem <- .l2v1_D[Date %in% .l2v1_sig & (K200 == TRUE | KQ150 == TRUE), .(Date, Ticker)]
rm(.l2v1_D); invisible(gc(verbose = FALSE))

# ── 7. 월별 배분 → 종목 비중 ─────────────────────────────────────────────────────
.l2v1_rows <- vector("list", length(.l2v1_hm)); .l2v1_diag <- vector("list", length(.l2v1_hm)); .l2v1_sw <- vector("list", length(.l2v1_hm))
for (i in seq_along(.l2v1_hm)) {
  m <- .l2v1_hm[i]; s <- .l2v1_sig[i]; ex <- .l2v1_exe[i]
  q <- data.table(module_key = .l2v1_cand$module_key, snap = ex); setkey(q, module_key, snap)
  sn_last <- .l2v1_snapdates[q, .(module_key, snap = x.snap), roll = TRUE]   # 집행일 이하 마지막 스냅샷
  sn_last <- sn_last[!is.na(snap)]
  avail <- sn_last$module_key
  sizes <- setNames(integer(length(.l2v1_roles)), .l2v1_roles)
  if (identical(.l2v1_arm, "EW_all")) {
    mw <- data.table(module_key = avail, mw = 1 / length(avail))
    wr <- setNames(rep(NA_real_, length(.l2v1_roles)), .l2v1_roles)
  } else {
    wr <- .l2v1_sleeve_w(i)
    mem <- unique(.l2v1_mem[decision_date == m & module_key %in% avail], by = c("module_key", "role"))
    sizes <- vapply(.l2v1_roles, function(r) uniqueN(mem[role == r]$module_key), integer(1))
    if (sum(sizes) == 0L) stop(sprintf("[l2v1_engine] %s: 모든 슬리브가 비었다", format(m)))
    if (any(sizes == 0L)) { wr[sizes == 0L] <- 0; wr <- wr / sum(wr) }     # 빈 슬리브 재정규화(설계 empty_sleeve_rule)
    mem[, mw := wr[role] / sizes[role]]                                       # 슬리브 안 동일가중
    mw <- mem[, .(mw = sum(mw)), by = module_key]                             # 여러 슬리브 소속 = 몫 합산
  }
  mw <- mw[mw > 0]
  h <- merge(.l2v1_pan[module_key %in% mw$module_key], sn_last, by.x = c("module_key", "exec_date"), by.y = c("module_key", "snap"))
  h <- merge(h, mw, by = "module_key")
  agg <- h[, .(w = sum(mw * weight)), by = .(Ticker = ticker)]
  n_pos <- sum(agg$w > 0)
  el <- agg[w > 0 & Ticker %in% .l2v1_U[Date == s]$Ticker]
  setorder(el, -w, Ticker)
  keep <- head(el, .l2v1_nmax)
  keep[, Weight := w / sum(w)]
  .l2v1_rows[[i]] <- keep[, .(Date = s, Ticker, Weight)]
  .l2v1_sw[[i]] <- data.table(holding_month = m, signal_date = s, exec_date = ex, P_T = .l2v1_P_T[i], P_S = .l2v1_P_S[i],
                              role = .l2v1_roles, w_role = as.numeric(wr), n_members = as.integer(sizes))
  .l2v1_diag[[i]] <- data.table(holding_month = m, signal_date = s, exec_date = ex, arm = .l2v1_arm,
                                n_modules_avail = length(avail), n_modules_weighted = nrow(mw), sum_module_w = sum(mw$mw),
                                n_agg_positive = n_pos, n_not_member = sum(agg$w > 0 & !(agg$Ticker %in% .l2v1_Umem[Date == s]$Ticker)),
                                n_eligible = nrow(el), n_kept = nrow(keep),
                                kept_share_of_positive_mass = if (n_pos) sum(keep$w) / sum(agg[w > 0]$w) else NA_real_,
                                net_mass = sum(agg$w), any_empty_sleeve = any(sizes == 0L) && !identical(.l2v1_arm, "EW_all"))
}
PORTFOLIO <- rbindlist(.l2v1_rows)
setorder(PORTFOLIO, Date, -Weight, Ticker)

# ── 8. 계약 자체 점검(어기면 멈춘다) ─────────────────────────────────────────────
.l2v1_chk <- PORTFOLIO[, .(n = .N, s = sum(Weight), mn = min(Weight)), by = Date]
if (nrow(.l2v1_chk) != length(.l2v1_hm)) stop("[l2v1_engine] 시그널일 수가 보유월 수와 다르다(빈 달 발생)")
if (any(abs(.l2v1_chk$s - 1) > 1e-9) || any(.l2v1_chk$mn <= 0) || any(.l2v1_chk$n > .l2v1_nmax))
  stop("[l2v1_engine] Σw=1 · w>0 · ≤n_max 위반")
if (max(PORTFOLIO$Date) >= as.Date(.l2v1_design$window$data_cutoff)) stop("[l2v1_engine] 시그널일이 데이터 컷오프 이후")

# ── 9. 진단(선택) ───────────────────────────────────────────────────────────────
.l2v1_dd <- Sys.getenv("L2V1_DIAG_DIR", "")
if (nzchar(.l2v1_dd)) {
  dir.create(.l2v1_dd, recursive = TRUE, showWarnings = FALSE)
  .p1 <- file.path(.l2v1_dd, sprintf("engine_diag_%s.csv", .l2v1_arm)); .p2 <- file.path(.l2v1_dd, sprintf("engine_sleeve_weights_%s.csv", .l2v1_arm))
  if (file.exists(.p1) || file.exists(.p2)) stop("[l2v1_engine] 진단 덮어쓰기 거부: ", .l2v1_dd)
  fwrite(rbindlist(.l2v1_diag), .p1); fwrite(rbindlist(.l2v1_sw), .p2)
}
cat(sprintf("[l2v1_engine] arm=%s · 보유월 %d (%s~%s) · 종목 행 %d · 월 보유 %d~%d · Pbar %.4f · 매니페스트 %s\n", .l2v1_arm, length(.l2v1_hm),
            format(min(.l2v1_hm)), format(max(.l2v1_hm)), nrow(PORTFOLIO), min(.l2v1_chk$n), max(.l2v1_chk$n), .l2v1_Pbar, basename(.l2v1_man_path)))
