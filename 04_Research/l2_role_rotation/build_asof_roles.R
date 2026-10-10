#==============================================================================
# build_asof_roles.R — 2계층 역할 슬리브용 as-of 역할 라벨 생성 + 대조 3종 (v0 · 2026-10-10)
#   사용: cd 04_Research/l2_role_rotation && Rscript --no-save -e 'source("build_asof_roles.R")'
#         env SRA_SKIP_BUILD=1 = 기존 parquet 재사용(대조만 다시)
#   설계: 04_Research/01_reports/l2_role_rotation_redesign_20261010/README.md §2.1 · 계약 02_Infrastructure/contracts/strategy_role_asof.R
#   유니버스 = 06_Registry/strategy_roles.json 에서 pool_rep_roles 가 비지 않은 항목(문자열/목록 정규화).
#   ★유니버스 자체는 전기간 역할 등급으로 뽑힌 집합이다 — 라벨은 as-of 지만 후보 집합 선정은 사후다(README 미결 1).
#   산출(이 디렉터리):
#     asof_roles.parquet               주판(PS 확정 = 완결 국면만 · confirm="phase")
#     asof_roles_sens_state.parquet    민감도(PS 확정 = 상태 결정 달까지 · confirm="state")
#     member_meta.csv                  구성원 메타(전기간 pool_rep_roles 는 **참고용** — 2계층 선택 입력 금지)
#     asof_controls/                   대조 (i) 누출 음성·양성 · (ii) 수렴 · (iii) 개시 시점 · 소속 안정성 · 빠른 판≡정본 대조
#     asof_roles_summary.json          핵심 수치
#   (같은 디렉터리를 쓰는 국면 예측기 작업(work/·predictor_*.json·pit_audit.json)과 파일명이 겹치지 않게 asof_ 접두)
#==============================================================================
suppressMessages({ library(data.table); library(jsonlite); library(arrow) })
.root <- gsub("\\\\", "/", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
setwd(.root)
source("02_Infrastructure/contracts/strategy_role_asof.R")
OUT <- Sys.getenv("SRA_OUT", file.path(.root, "04_Research/l2_role_rotation")); CTRL <- file.path(OUT, "asof_controls")   # SRA_OUT = 시험 출력 경로
dir.create(CTRL, recursive = TRUE, showWarnings = FALSE)
T0 <- Sys.time()
ROLES <- c("defensive", "offensive", "rebound", "alpha")
say <- function(...) cat(sprintf(...), "\n", sep = "")

# --- 1. 유니버스 ------------------------------------------------------------------
reg <- sr_registry_load(.root)
norm_roles <- function(x) { v <- as.character(unlist(x)); v <- v[!is.na(v) & nzchar(v)]; unique(unlist(strsplit(v, ";", fixed = TRUE))) }
U <- Filter(function(e) length(norm_roles(e$pool_rep_roles)) > 0L, reg$entries)
n_str <- sum(vapply(U, function(e) is.character(e$pool_rep_roles), logical(1)))
inp <- sra_inputs(.root)
series <- setNames(lapply(names(U), function(id) .sr_env$rfd_read_series(U[[id]]$series)), names(U))
bad <- names(series)[vapply(series, is.null, logical(1))]
if (length(bad)) stop("계열 판독 불가: ", paste(bad, collapse = ", "))
SP <- lapply(series, sra_prep_series, bm = inp$bm)                          # 벤치 거래일 결합·ym 부착(한 번)
exec_of <- function(e) if (identical(e$kind, "book")) "book_output" else if (grepl("\\.rds$", e$series)) "sim_result" else
  if (grepl("remeasure_close_t1_", e$series)) "close_t1_remeasure" else "native"
meta <- rbindlist(lapply(names(U), function(id) {
  e <- U[[id]]; s <- series[[id]]
  # 달력 진단(날짜만 — 수익값 미사용): 정본 벤치 거래일에 없는 날짜 비율 · 주말 날짜 비율
  data.table(member_id = id, kind = e$kind, lineage = e$lineage, cell = e$cell %||% "", essence_grade = e$essence_grade %||% NA_character_,
             exec = exec_of(e), freq = s$freq, series = e$series,
             pool_rep_roles_fullsample = paste(norm_roles(e$pool_rep_roles), collapse = ";"),
             pool_rep_roles_was_string = is.character(e$pool_rep_roles),
             calendar_join_loss = if (identical(s$freq, "monthly")) NA_real_ else round(mean(!s$dt$date %in% inp$bm$date), 4),
             weekend_dates = if (identical(s$freq, "monthly")) NA_integer_ else sum(format(s$dt$date, "%u") %in% c("6", "7")))
}))
fwrite(meta, file.path(OUT, "member_meta.csv"))
say("[유니버스] %d 구성원 (pool_rep_roles 문자열 저장 %d 건 정규화) · exec: %s", nrow(meta), n_str,
    paste(meta[, .N, by = exec][, sprintf("%s=%d", exec, N)], collapse = " "))
dates <- sra_decision_dates(inp$bm)
if (identical(Sys.getenv("SRA_TEST"), "1")) dates <- dates[sort(unique(c(seq(1, length(dates), by = 6), length(dates))))]   # 시험용 축소
say("[결정 시점] %s ~ %s (%d) · 벤치 %s (mtime %s) · PS 모수 %s", format(min(dates)), format(max(dates)), length(dates),
    format(max(inp$bm$date)), inp$bench_mtime, paste(sprintf("%s=%s", names(inp$pars), unlist(inp$pars)), collapse = " "))

# --- 2a. 빠른 판 ≡ 정본 판 대조(월간 수익·카드 전체 · 표본 시점 × 전 구성원) — 불일치 = 중단 -------------------
same_vals <- function(a, b) {   # 값 비트 동일성(열 이름·행 수·각 열 identical) — data.table 키 속성 차이는 무시
  if (is.null(a) || is.null(b)) return(is.null(a) && is.null(b))
  identical(names(a), names(b)) && nrow(a) == nrow(b) && all(mapply(identical, as.list(a), as.list(b)))
}
EQ_DATES <- unique(as.Date(c("2006-06-01", "2009-11-01", "2012-06-01", "2015-01-01", "2018-07-01", "2021-03-01", "2025-07-01", format(max(dates)))))
EQ <- rbindlist(lapply(as.list(EQ_DATES), function(t) {
  M <- sra_month_inputs(t, inp, "phase")
  mon_same <- vapply(names(SP), function(id) same_vals(sra_monthly_asof(SP[[id]], M$t, M$bmm), sra_monthly_canonical(series[[id]], M)), logical(1))
  Lf <- sra_labels_at(t, SP, inp, "phase", M = M, path = "fast"); Lc <- sra_labels_at(t, series, inp, "phase", M = M, path = "canonical")
  data.table(decision_date = t, n_members = length(SP), monthly_identical = sum(mon_same), cards_identical = identical(as.data.frame(Lf), as.data.frame(Lc)))
}))
fwrite(EQ, file.path(CTRL, "fast_vs_canonical.csv")); print(EQ)
if (!all(EQ$monthly_identical == EQ$n_members) || !all(EQ$cards_identical)) stop("빠른 판 ≠ 정본 판 — 생성 중단")

# --- 2. 생성 ----------------------------------------------------------------------
P_MAIN <- file.path(OUT, "asof_roles.parquet"); P_SENS <- file.path(OUT, "asof_roles_sens_state.parquet")
if (identical(Sys.getenv("SRA_SKIP_BUILD"), "1") && file.exists(P_MAIN) && file.exists(P_SENS)) {
  A <- as.data.table(read_parquet(P_MAIN)); S <- as.data.table(read_parquet(P_SENS))
} else {
  A <- sra_build(SP, inp, dates, "phase"); write_parquet(A, P_MAIN)
  S <- sra_build(SP, inp, dates, "state"); write_parquet(S, P_SENS)
}
say("[생성] 주판 %d 행 · 민감도 %d 행 · %.0f 초", nrow(A), nrow(S), as.numeric(difftime(Sys.time(), T0, units = "secs")))

# as-of PS 연대기 기록(결정 시점별 국면 표) + 사후 전기간 연대기(대조용)
ph_rows <- list()
for (k in seq_along(dates)) for (cf in c("phase", "state")) {
  M <- sra_month_inputs(dates[k], inp, cf); ph <- copy(attr(M$R, "phases"))
  ph_rows[[length(ph_rows) + 1L]] <- ph[, `:=`(decision_date = dates[k], ps_confirm = cf)]
}
PH <- rbindlist(ph_rows); setcolorder(PH, c("decision_date", "ps_confirm"))
fwrite(PH, file.path(CTRL, "ps_phases_asof.csv"))
Rfull <- sr_regimes(inp$bm)
rr <- rle(Rfull$ps_bear); ee <- cumsum(rr$lengths); ss <- ee - rr$lengths + 1L
PHF <- data.table(state = ifelse(rr$values, "bear", "bull"), start_ym = Rfull$ym[ss], end_ym = Rfull$ym[ee], n = rr$lengths)
fwrite(PHF, file.path(CTRL, "ps_phases_fullsample_expost.csv"))

# --- 3. 대조 (i) 누출 음성 대조 + 양성 대조 ----------------------------------------------
# t 이후(date >= t) 원자료 전부 교란: 전략 수익(일간 행·월간 행) · 벤치 일간 수익 · 사이즈 지수 수준
perturb <- function(t, type, seed) {
  set.seed(seed); t <- as.Date(t)
  S2 <- lapply(series, function(s) {
    d <- copy(s$dt); k <- which(d$date >= t)
    if (length(k)) {
      if (type == "shuffle") d$ret[k] <- d$ret[k][sample.int(length(k))]
      if (type == "flip_noise") d$ret[k] <- -d$ret[k] + stats::rnorm(length(k), 0, 0.05)
      if (type == "delete") d <- d[-k]
    }
    list(freq = s$freq, dt = d)
  })
  I2 <- inp
  b <- copy(inp$bm); k <- which(b$date >= t)
  if (length(k)) {
    if (type == "shuffle") b$bm[k] <- b$bm[k][sample.int(length(k))]
    if (type == "flip_noise") b$bm[k] <- -b$bm[k] + stats::rnorm(length(k), 0, 0.05)
    if (type == "delete") b <- b[-k]
  }
  setkey(b, date); I2$bm <- b
  x <- copy(inp$ix); k <- which(x$Date >= t)
  if (length(k)) {
    if (type == "shuffle") { o <- sample.int(length(k)); x$kospi200_ew[k] <- x$kospi200_ew[k][o]; x$kosdaq150_ew[k] <- x$kosdaq150_ew[k][o] }
    if (type == "flip_noise") { x$kospi200_ew[k] <- x$kospi200_ew[k] * exp(stats::rnorm(length(k), 0, 0.2)); x$kosdaq150_ew[k] <- x$kosdaq150_ew[k] * exp(stats::rnorm(length(k), 0, 0.2)) }
    if (type == "delete") x <- x[-k]
  }
  I2$ix <- x
  list(series = S2, inp = I2)
}
# 파이프라인 4종: as-of 주판·민감도(검사 대상) + 일부러 새는 판 2종(양성 대조 — 계기가 누출을 잡을 수 있음을 보인다)
#   leaky_expost_ps     : 전략 자료는 자르되 PS 국면 = 전기간 사후 연대기(sr_regimes · 정본 1계층 판)를 달 < T 로만 자른 것
#   leaky_fullseries    : PS 는 as-of 지만 월간 계열을 **자르지 않은** 전 계열에서 만든 뒤 달 < T 로 거른 것(값은 t 이전, '존재'는 t 이후 의존)
labels_pipeline <- function(t, SER, INP, pipe) {
  SPx <- lapply(SER, sra_prep_series, bm = INP$bm)                         # 교란된 원자료에서 처음부터 다시(종단 대조)
  if (pipe %in% c("asof_phase", "asof_state")) return(sra_labels_at(t, SPx, INP, sub("asof_", "", pipe)))
  M <- sra_month_inputs(t, INP, "phase")
  if (pipe == "leaky_expost_ps") {
    Rx <- sr_regimes(INP$bm); T_ym <- format(as.Date(t), "%Y-%m")
    M$R <- Rx[ym < T_ym]; attr(M$R, "phases") <- NULL
    return(rbindlist(lapply(names(SPx), function(id) sra_flatten(sra_card_asof(SPx[[id]], M, INP$cfg), M, id, INP$cfg))))
  }
  if (pipe == "leaky_fullseries") {
    T_ym <- format(as.Date(t), "%Y-%m")
    fac_full <- sra_factor_monthly(INP$ix)
    return(rbindlist(lapply(names(SER), function(id) {
      mm <- .sr_env$rfd_monthly(SER[[id]], INP$bm, fac_full)             # ★자르지 않음
      cd <- if (is.null(mm)) list(status = "no_data") else {
        m <- merge(merge(mm[ym < T_ym, .(ym, r)], M$bmm, by = "ym"), M$fac, by = "ym", all.x = TRUE)
        z <- sr_card(m, M$R, INP$cfg); z$ym_used <- intersect(m[is.finite(r) & is.finite(b), ym], M$R$ym); z
      }
      sra_flatten(cd, M, id, INP$cfg)
    })))
  }
  stop("unknown pipe ", pipe)
}
rowkey <- function(D) do.call(paste, c(lapply(D, function(x) if (is.numeric(x)) sprintf("%.17g", x) else as.character(x)), sep = "|"))
CT <- as.Date(c("2009-01-01", "2013-04-01", "2016-07-01", "2020-04-01", "2024-10-01"))
PIPES <- c("asof_phase", "asof_state", "leaky_expost_ps", "leaky_fullseries")
LK <- list(); seed <- 20261010L
for (t in as.list(CT)) for (pipe in PIPES) {
  L0 <- labels_pipeline(t, series, inp, pipe)
  for (type in c("shuffle", "flip_noise", "delete")) {
    seed <- seed + 1L; P <- perturb(t, type, seed)
    L1 <- labels_pipeline(t, P$series, P$inp, pipe)
    k0 <- rowkey(L0); k1 <- rowkey(L1)
    LK[[length(LK) + 1L]] <- data.table(decision_date = t, pipeline = pipe, perturbation = type, n_rows = nrow(L0),
      n_rows_diff = sum(k0 != k1), n_grade_diff = sum(!mapply(identical, L0$grade_asof, L1$grade_asof)),
      n_member_diff = sum(L0$is_member != L1$is_member),
      bit_identical = identical(as.data.frame(L0), as.data.frame(L1)))
  }
}
LK <- rbindlist(LK)
fwrite(LK, file.path(CTRL, "leakage_control.csv"))
print(LK[, .(cells = .N, bit_identical = sum(bit_identical), rows_diff = sum(n_rows_diff), grade_diff = sum(n_grade_diff), member_diff = sum(n_member_diff)), by = .(pipeline, perturbation)])

# --- 4. 대조 (ii) 수렴 — 마지막 결정 시점 as-of 등급 vs 레지스트리 전기간 등급 ----------------------
t_last <- max(dates)
reg_rows <- rbindlist(lapply(names(U), function(id) {
  cd <- U[[id]]$card
  rbindlist(lapply(ROLES, function(r) { z <- cd$roles[[r]]
    data.table(member_id = id, role = r, grade_full = as.character(z$grade %||% NA), t_full = as.numeric(z$t %||% NA),
               n_full = as.integer(z$n %||% NA), mean_full = as.numeric(z$mean %||% NA), n_months_full = as.integer(cd$n_months %||% NA),
               last_ym_full = as.character(cd$last_ym %||% NA)) }))
}))
# 진단(귀속용 · 라벨 아님): as-of 월 집합 + 사후 전기간 PS 연대기 → 차이를 'PS 확정 지연'과 '월 집합(t 절단)'으로 나눈다
Mx <- sra_month_inputs(t_last, inp, "phase"); Mx$R <- Rfull[ym < format(t_last, "%Y-%m")]; attr(Mx$R, "phases") <- NULL
DX <- rbindlist(lapply(names(SP), function(id) sra_flatten(sra_card_asof(SP[[id]], Mx, inp$cfg), Mx, id, inp$cfg)))[, .(member_id, role, grade_diag = grade_asof, n_diag = n_regime_obs)]
conv <- function(X, tag) {
  C <- merge(X[decision_date == t_last, .(member_id, role, grade_asof, t_asof = t, n_asof = n_regime_obs, mean_asof = mean, n_months_asof = n_months, last_ym_asof = last_ym, both_nonneg)],
             reg_rows, by = c("member_id", "role"))
  C <- merge(C, DX, by = c("member_id", "role"))
  C[, agree := grade_asof == grade_full]
  C[, member_agree := (grade_asof %in% c("A", "B")) == (grade_full %in% c("A", "B"))]
  C[, cause := fifelse(agree, "",
      fifelse(grade_diag == grade_full & grade_asof != grade_diag, "ps_confirmation_lag",
      fifelse(grade_diag != grade_full & grade_asof == grade_diag, "month_set_t_cut",
              "both")))]
  C[, ps_confirm := tag]
  C[]
}
CV <- rbind(conv(A, "phase"), conv(S, "state"))
fwrite(CV, file.path(CTRL, "convergence_final.csv"))
print(CV[, .(n = .N, grade_agree = round(mean(agree), 4), member_agree = round(mean(member_agree), 4)), by = .(ps_confirm, role)])
print(CV[, .(n = .N, grade_agree = round(mean(agree), 4), member_agree = round(mean(member_agree), 4)), by = ps_confirm])
print(CV[agree == FALSE, .N, by = .(ps_confirm, role, cause)])

# --- 5. 대조 (iii) 개시 시점 — 확정 약세 국면 2회 -----------------------------------------
ph_main <- PH[ps_confirm == "phase" & state == "bear" & closed == TRUE & n_confirmed > 0L]
mk <- ph_main[, .(n_bear_closed_all = .N, n_bear_closed_2005 = sum(start_ym >= "2005-01")), by = decision_date]
mk <- merge(data.table(decision_date = dates), mk, by = "decision_date", all.x = TRUE)
mk[is.na(n_bear_closed_all), `:=`(n_bear_closed_all = 0L, n_bear_closed_2005 = 0L)]
first_ge <- function(d, v, k) { i <- which(v >= k); if (length(i)) format(d[i[1]]) else NA_character_ }
sm <- A[role == "defensive", .(first_2bear = first_ge(decision_date, fifelse(is.na(n_phases), 0L, n_phases), 2L),
                               first_def_gradeable = first_ge(decision_date, fifelse(is.na(n_regime_obs), 0L, n_regime_obs), 24L),
                               first_ok = first_ge(decision_date, as.integer(status == "ok"), 1L)), by = member_id]
cover <- A[role == "defensive", .(share_2bear = mean(fifelse(is.na(n_phases), 0L, n_phases) >= 2L)), by = decision_date]
first_cover <- function(q) { i <- which(cover$share_2bear >= q); if (length(i)) format(cover$decision_date[i[1]]) else NA_character_ }
role_first <- A[, .(n_mem = sum(is_member)), by = .(role, decision_date)][n_mem > 0, .(first_member_date = format(min(decision_date))), by = role]
START <- list(
  market_2bear_since_1990 = first_ge(mk$decision_date, mk$n_bear_closed_all, 2L),
  market_2bear_since_2005 = first_ge(mk$decision_date, mk$n_bear_closed_2005, 2L),
  universe_share_2bear_50 = first_cover(0.5), universe_share_2bear_80 = first_cover(0.8), universe_share_2bear_100 = first_cover(1.0),
  member_first_2bear_min = min(sm$first_2bear, na.rm = TRUE), member_first_2bear_median = sort(sm$first_2bear)[ceiling(nrow(sm) / 2)],
  member_first_2bear_max = max(sm$first_2bear, na.rm = TRUE),
  defensive_gradeable_median = sort(sm$first_def_gradeable)[ceiling(nrow(sm) / 2)],
  role_first_member = setNames(as.list(role_first$first_member_date), role_first$role),
  confirmed_bear_phases_2005plus_at_last = PH[ps_confirm == "phase" & decision_date == t_last & state == "bear" & closed & start_ym >= "2005-01",
                                              sprintf("%s~%s(%d)", start_ym, end_ym, n)])
fwrite(sm, file.path(CTRL, "start_by_member.csv")); fwrite(mk, file.path(CTRL, "confirmed_bear_count_by_date.csv"))
write_json(START, file.path(CTRL, "start_date.json"), auto_unbox = TRUE, pretty = TRUE)
str(START)

# --- 6. 소속 안정성 ------------------------------------------------------------------
LIN <- setNames(meta$lineage, meta$member_id)                               # 계보(논문 키) — 정적 메타(통계 아님)
memb <- function(X, tag) {
  W <- X[, {
    ds <- sort(unique(decision_date))
    sets <- lapply(ds, function(d) sort(member_id[decision_date == d & is_member]))
    n <- lengths(sets); k <- length(sets)
    ent <- c(NA_integer_, vapply(2:k, function(i) length(setdiff(sets[[i]], sets[[i - 1L]])), 0L))
    ext <- c(NA_integer_, vapply(2:k, function(i) length(setdiff(sets[[i - 1L]], sets[[i]])), 0L))
    den <- c(NA_integer_, n[-1] + n[-k])
    list(decision_date = ds, n_members = n, n_lineages = vapply(sets, function(z) length(unique(LIN[z])), 0L), entries = ent, exits = ext,
         turnover = ifelse(!is.na(den) & den > 0, (ent + ext) / den, NA_real_))   # 대칭차 / (전월+당월) — 0 = 불변 · 1 = 전면 교체
  }, by = role]
  W[, ps_confirm := tag]
  W[, .(ps_confirm, role, decision_date, n_members, n_lineages, entries, exits, turnover)]
}
MB <- rbind(memb(A, "phase"), memb(S, "state"))
fwrite(MB, file.path(CTRL, "membership_by_date.csv"))
spells <- function(X) X[order(member_id, role, decision_date)][, { r <- rle(is_member); list(spell = r$lengths[r$values]) }, by = .(member_id, role)]
start_d <- as.Date(START$market_2bear_since_2005)
summ <- function(X, tag) {
  W <- MB[ps_confirm == tag]
  sp <- spells(X[decision_date >= start_d])
  W2 <- W[decision_date >= start_d]
  out <- W2[, .(median_members_from_start = as.numeric(median(n_members)), median_lineages_from_start = as.numeric(median(n_lineages)),
                min_members = min(n_members), max_members = max(n_members),
                median_members_all_dates = as.numeric(median(W[role == .BY$role, n_members])),
                mean_entries = round(mean(entries[-1], na.rm = TRUE), 2), mean_exits = round(mean(exits[-1], na.rm = TRUE), 2),
                mean_turnover = round(mean(turnover[-1], na.rm = TRUE), 4), median_turnover = round(median(turnover[-1], na.rm = TRUE), 4),
                months_with_change = sum((entries[-1] + exits[-1]) > 0, na.rm = TRUE), n_months = .N - 1L,
                members_at_last = n_members[.N]), by = role]
  out <- merge(out, sp[, .(median_spell_months = as.numeric(median(spell)), n_spells = .N), by = role], by = "role", all.x = TRUE)
  out[, ps_confirm := tag]; out[]
}
MS <- rbind(summ(A, "phase"), summ(S, "state"))
fwrite(MS, file.path(CTRL, "membership_summary.csv"))
print(MS)
# 전기간 대표 역할(사후) vs as-of 소속 — 마지막 시점·개시 이후 소속 개월 비율(참고)
rep_long <- meta[, .(role = unlist(strsplit(pool_rep_roles_fullsample, ";"))), by = member_id][role %in% ROLES]
RV <- merge(rep_long, A[decision_date >= start_d, .(share_member_from_start = round(mean(is_member), 3),
                                                    member_at_last = is_member[decision_date == t_last]), by = .(member_id, role)], by = c("member_id", "role"))
fwrite(RV, file.path(CTRL, "fullsample_rep_vs_asof.csv"))
print(RV[, .(reps = .N, member_at_last = sum(member_at_last), median_share_from_start = median(share_member_from_start)), by = role])

# --- 6b. 진단 — 계열 날짜 정렬(달력만으로 표식: 주말 날짜가 있는 일간 계열) · 라벨 아님 ------------------------------
#   레거시 sim_result 계열은 날짜가 정본 벤치보다 하루 이르다(일요일 = 월요일 수익) → 정본 rfd_monthly 의 날짜 내부 결합이
#   월요일 수익을 통째로 버린다. 레지스트리(전기간)와 as-of 라벨이 같은 결함을 공유하므로 크기를 기록만 한다(+1일 재정렬 대비).
SHIFT <- meta[!is.na(weekend_dates) & weekend_dates > 0, member_id]
LD <- rbindlist(lapply(SHIFT, function(id) {
  s0 <- series[[id]]; s1 <- list(freq = s0$freq, dt = copy(s0$dt)[, date := date + 1L])
  card_full <- function(s) { mm <- .sr_env$rfd_monthly(s, inp$bm[, .(date, bm)], sra_factor_monthly(inp$ix))
    m <- merge(merge(mm[, .(ym, r)], inp$bm[, .(b = prod(1 + bm) - 1), by = ym], by = "ym"), sra_factor_monthly(inp$ix), by = "ym", all.x = TRUE)
    sr_card(m, Rfull, inp$cfg) }
  c0 <- card_full(s0); c1 <- card_full(s1)
  d0 <- merge(s0$dt, inp$bm, by = "date"); d1 <- merge(s1$dt, inp$bm, by = "date")
  rbindlist(lapply(ROLES, function(r) data.table(member_id = id, role = r, join_rows = nrow(d0), join_rows_shift1 = nrow(d1), rows = nrow(s0$dt),
    daily_cor_bm = round(cor(d0$ret, d0$bm), 3), daily_cor_bm_shift1 = round(cor(d1$ret, d1$bm), 3), beta = round(c0$beta, 3), beta_shift1 = round(c1$beta, 3),
    grade_registry_rule = c0$roles[[r]]$grade, t_registry_rule = round(c0$roles[[r]]$t, 3), grade_shift1 = c1$roles[[r]]$grade, t_shift1 = round(c1$roles[[r]]$t, 3))))
}))
fwrite(LD, file.path(CTRL, "diag_calendar_shift_fullsample.csv"))
if (nrow(LD)) print(LD[role == "defensive", .(member_id, join_rows, rows, daily_cor_bm, daily_cor_bm_shift1, beta, beta_shift1, grade_registry_rule, grade_shift1)])

# --- 7. 요약 ------------------------------------------------------------------------
SUM <- list(
  built_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), n_members = nrow(meta), n_pool_rep_roles_string = n_str,
  decision_dates = c(format(min(dates)), format(max(dates)), length(dates)), bench = inp$bench_path, bench_mtime = inp$bench_mtime,
  ps_params = inp$pars,
  leakage = list(asof_bit_identical = LK[pipeline %like% "^asof", sprintf("%d/%d", sum(bit_identical), .N)],
                 leaky_expost_ps_detected = LK[pipeline == "leaky_expost_ps", sprintf("%d/%d", sum(!bit_identical), .N)],
                 leaky_fullseries_detected = LK[pipeline == "leaky_fullseries", sprintf("%d/%d (delete %d/%d)", sum(!bit_identical), .N,
                                                sum(!bit_identical[perturbation == "delete"]), sum(perturbation == "delete"))]),
  convergence = CV[, .(grade_agree = round(mean(agree), 4), member_agree = round(mean(member_agree), 4), n = .N,
                       n_ps_lag = sum(cause == "ps_confirmation_lag"), n_month_set = sum(cause == "month_set_t_cut"), n_both = sum(cause == "both")), by = ps_confirm],
  start = START, membership = MS, seconds = round(as.numeric(difftime(Sys.time(), T0, units = "secs"))))
write_json(SUM, file.path(OUT, "asof_roles_summary.json"), auto_unbox = TRUE, pretty = TRUE, digits = 6)
say("[완료] %.0f 초 · %s", SUM$seconds, OUT)
