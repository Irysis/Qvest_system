#==============================================================================
# rf_div_replay.R — 기저 분산성 관문 역사 재생 (2026-10-06 · 설계 §9-3) · 2판
#   "그때 이 관문이 있었다면" — 원장 L1 비승격 entry 기저마다 (가) 그 시각 풀(as-of) (나) 현재 풀 로 판정한다.
#   척도 2종: resid = 잔차수익 r − β·b(기본) · active = 초과수익 r − b(1판 · 대조)
#   풀 2판: all = 표식 무관 · clean = C1 선정 승계 표식(selection_basis_full_sample_ic·_inherited) 칸 제외
#   읽기 전용 — 원장·카탈로그·산출물을 쓰지 않는다. 출력 = 보고서 디렉터리 replay/ 뿐.
#==============================================================================
suppressMessages({ library(data.table); library(jsonlite) })
root <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
stg <- "C:/tmp/qvest_staging_1006_divgate"
Sys.setenv(RF_DIV_CFG = file.path(stg, "rf_diversification_gate.json"))
source(file.path(stg, "rf_diversification_gate.R"))
out_dir <- file.path(root, "04_Research/01_reports/diversification_gate_design_20261006/replay")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
t_start <- Sys.time()
cfg <- rfd_cfg(root)
TAINT <- c("selection_basis_full_sample_ic", "selection_basis_full_sample_ic_inherited")
RUNS <- list(resid2_all = list(measure = "resid2", ex = character(0)),
             resid2_clean = list(measure = "resid2", ex = TAINT),
             resid_all = list(measure = "resid", ex = character(0)),
             resid_clean = list(measure = "resid", ex = TAINT),
             active_all = list(measure = "active", ex = character(0)))
Q_GRID <- c(0.80, 0.85, 0.90, 0.95)

mem <- rfd_members(root, cfg)
bm <- rfd_bench_daily(root, cfg)
fac <- rfd_factor_monthly(root, cfg)
cat("유니버스 동일가중 요인:", if (is.null(fac)) "없음" else sprintf("%s ~ %s (%d개월)", fac$ym[1], fac$ym[nrow(fac)], nrow(fac)), "\n")
L <- jsonlite::fromJSON(file.path(root, "06_Registry/reinforce_ledger_l1.json"), simplifyVector = FALSE)
E <- L$entries

# --- 후보: 비승격 entry 의 기저 -------------------------------------------------
hrs <- function(a, b) as.numeric(difftime(b, a, units = "hours"))
att_stats <- function(at) {
  if (!length(at)) return(list(n = 0L, nB = 0L, best_pt = NA_real_, best_calmar = NA_real_, wall_h = 0, cpu_h = 0))
  g <- vapply(at, function(a) .rfd_chr(a$grade), "")
  pt <- vapply(at, function(a) .rfd_num(a$essence$port_t), 0)
  cm <- vapply(at, function(a) .rfd_num(a$essence$calmar), 0)
  o <- do.call(c, lapply(at, function(a) .rfd_time(a$opened_at)))
  cl <- do.call(c, lapply(at, function(a) .rfd_time(a$closed_at)))
  list(n = length(at), nB = sum(g %in% c("A", "B")),
       best_pt = if (all(is.na(pt))) NA_real_ else max(pt, na.rm = TRUE),
       best_calmar = if (all(is.na(cm))) NA_real_ else max(cm, na.rm = TRUE),
       wall_h = if (all(is.na(o)) || all(is.na(cl))) NA_real_ else hrs(min(o, na.rm = TRUE), max(cl, na.rm = TRUE)),
       cpu_h = sum(pmax(0, hrs(o, cl)), na.rm = TRUE))
}
cand <- list()
for (i in seq_along(E)) {
  e <- E[[i]]
  bid <- .rfd_chr(e$base_id)
  if (grepl("_promo", bid, fixed = TRUE)) next
  base <- .rfd_abs(sub(" .*$", "", .rfd_chr(e$base_artifacts)), root)
  s <- .rfd_series_in_dir(base)
  st <- att_stats(.rfd_or(e$attempts, list()))
  desc <- Filter(function(x) startsWith(.rfd_chr(x$base_id), paste0(bid, "_promo")), E)
  ds <- att_stats(do.call(c, lapply(desc, function(x) .rfd_or(x$attempts, list()))))
  g <- if (!is.null(s)) .rfd_auth_grade(s$auth) else list(grade = NA_character_, port_t = NA_real_, rescued = NA)
  cand[[length(cand) + 1L]] <- data.table(
    idx = i, entry_id = bid, paper_key = .rfd_chr(e$paper_key), status = .rfd_chr(e$status),
    opened_at = .rfd_time(e$opened_at), base_dir = base, series = if (is.null(s)) "" else s$path,
    exec = if (is.null(s)) "" else s$exec,
    base_grade = if (nzchar(.rfd_chr(g$grade))) .rfd_chr(g$grade) else .rfd_chr(e$base_grade),
    base_pt = g$port_t, rescued = g$rescued, axis_ok = !identical(e$axis_valid, FALSE),
    n_att = st$n, nB = st$nB, best_pt = st$best_pt, best_calmar = st$best_calmar, wall_h = st$wall_h, cpu_h = st$cpu_h,
    n_desc_entries = length(desc), desc_n_att = ds$n, desc_nB = ds$nB, desc_best_pt = ds$best_pt, desc_wall_h = ds$wall_h,
    desc_ids = paste(vapply(desc, function(x) .rfd_chr(x$base_id), ""), collapse = ";"))
}
cand <- rbindlist(cand, fill = TRUE)
cand[, kind := fifelse(startsWith(paper_key, "combo:"), "combo", "single")]
setorder(cand, opened_at)
cand[, remeasure := vapply(seq_len(.N), function(j) any(vapply(seq_len(j - 1L), function(k) rfd_related(paper_key[k], paper_key[j]), logical(1))), logical(1))]
cand[kind == "single" & remeasure, kind := "single_remeasure"]
cand[, has_series := nzchar(series)]

# --- 월간 계열 적재: B 이상 구성원 + 후보 기저 + 강화 계보의 전 칸(예측 타당도) ---------
lin_entries <- unique(unlist(c(cand$entry_id, strsplit(cand$desc_ids[nzchar(cand$desc_ids)], ";", fixed = TRUE))))
need <- unique(c(mem[grade %in% c("A", "B") & axis_ok == TRUE, series], cand[has_series == TRUE, series],
                 mem[kind == "cell" & entry_id %in% lin_entries, series]))
mon <- list()
for (p in need) mon[[p]] <- rfd_monthly(rfd_read_series(p), bm, fac)
bad <- names(mon)[vapply(mon, is.null, logical(1))]
cat("월간 계열:", length(need), " 실패:", length(bad), "\n")
key_of <- function(p) paste0("S", match(p, need))
ser_mon <- mon[!vapply(mon, is.null, logical(1))]
names(ser_mon) <- key_of(names(ser_mon))
mats <- rfd_matrix(ser_mon)
mem[, mid := key_of(series)]
cand[, mid := fifelse(has_series, key_of(series), "")]

# 같은 기저 계열(잔차 상관 ≥ 0.999 = 같은 측정의 재실행)을 두 entry 가 쓰면 하나로 — 강화가 실제로 돈 쪽
cand[, dup_series := FALSE]
ids <- cand[has_series == TRUE, which = TRUE]
for (a in ids) for (b in ids) if (b > a && !cand$dup_series[b] && !cand$dup_series[a] && rfd_related(cand$paper_key[a], cand$paper_key[b])) {
  r <- .rfd_cor(mats$E[, cand$mid[a]], mats$E[, cand$mid[b]])[["rho"]]
  if (is.finite(r) && r >= 0.999) { drop <- if (cand$n_att[b] > cand$n_att[a]) a else b; set(cand, drop, "dup_series", TRUE) }
}
cat(sprintf("후보 entry %d (계열 有 %d · 같은 계열 재개설 %d) · kind: %s\n", nrow(cand), sum(cand$has_series), sum(cand$dup_series),
            paste(names(table(cand$kind)), table(cand$kind), collapse = " ")))

# 계열 위생: 구성원별 cor(r, b) · β
hyg <- rbindlist(lapply(names(ser_mon), function(k) {
  m <- ser_mon[[k]]; b <- m$r - m$a
  data.table(mid = k, n = nrow(m), cor_rb = suppressWarnings(cor(m$r, b)), beta = attr(m, "rfd_beta"), ann_active = mean(m$a) * 12)
}))
hyg <- merge(hyg, unique(mem[, .(mid, member_id, kind, lineage, grade)], by = "mid"), by = "mid", all.x = TRUE)
fwrite(hyg[order(cor_rb)], file.path(out_dir, "series_hygiene.csv"))

as_pool <- function(P) { P <- copy(P); P[, member_id := mid]; P }
flat <- function(m) as.data.table(m[c("status", "n_pool_members", "n_pool_lineages", "rho_max", "neighbor_lineage", "neighbor_member",
                                      "n_overlap", "r2_span", "r2_span_raw", "span_sel", "alpha_span", "alpha_span_t", "n_span",
                                      "rho_down", "capture_down", "n_down")])
C1 <- cand[has_series == TRUE & dup_series == FALSE]
lin_cells <- function(j) {  # 후보 계보(자기 entry + 승격 자손)의 측정 칸 mid
  ents <- c(C1$entry_id[j], if (nzchar(C1$desc_ids[j])) strsplit(C1$desc_ids[j], ";", fixed = TRUE)[[1]] else character(0))
  intersect(mem[kind == "cell" & entry_id %in% ents, mid], colnames(mats$E))
}
res <- list(); pv <- list()
for (rn in names(RUNS)) {
  ms <- RUNS[[rn]]$measure; ex <- RUNS[[rn]]$ex
  pool_now <- as_pool(rfd_pool(mem, cfg, exclude_flags = ex))
  cat(sprintf("현재 풀[%s]: 구성원 %d · 계보 %d\n", rn, nrow(pool_now), uniqueN(pool_now$lineage)))
  for (j in seq_len(nrow(C1))) {
    cm <- ser_mon[[C1$mid[j]]]
    mn <- rfd_metrics(cm, C1$paper_key[j], pool_now, mats, cfg, measure = ms)
    Pa <- as_pool(rfd_pool(mem, cfg, as_of = C1$opened_at[j], exclude_flags = ex))
    ma <- rfd_metrics(cm, C1$paper_key[j], Pa, mats, cfg, measure = ms)
    nb_best <- if (nzchar(ma$neighbor_lineage)) suppressWarnings(max(Pa[lineage == ma$neighbor_lineage, port_t], na.rm = TRUE)) else NA_real_
    # 관련 계보(같은 논문 공유)와의 최대 상관 — 결합의 양성 대조
    rel <- Pa[vapply(lineage, function(l) rfd_related(l, C1$paper_key[j]) && !identical(l, C1$paper_key[j]), logical(1))]
    X <- switch(ms, active = mats$A, resid2 = mats$E2, mats$E)
    ycol <- switch(ms, active = "a", resid2 = "e2", "e")
    y <- rep(NA_real_, nrow(X)); y[match(cm$ym, rownames(X))] <- cm[[ycol]]
    rel_r <- if (nrow(rel)) suppressWarnings(max(vapply(intersect(rel$member_id, colnames(X)), function(id) {
      r <- .rfd_cor(y, X[, id]); if (r[["n"]] >= cfg$series$min_overlap_months) r[["rho"]] else NA_real_ }, 0), na.rm = TRUE)) else NA_real_
    res[[length(res) + 1L]] <- cbind(data.table(run = rn, entry_id = C1$entry_id[j]),
                                     setnames(flat(mn), function(x) paste0("now_", x)),
                                     setnames(flat(ma), function(x) paste0("asof_", x)),
                                     data.table(asof_neighbor_lineage_best_pt = if (is.finite(nb_best)) nb_best else NA_real_,
                                                asof_related_rho_max = if (is.finite(rel_r)) rel_r else NA_real_))
    # 예측 타당도: 강화 칸 각각을 같은 as-of 풀에 댄 rho_max — 기저 rho_max 가 칸 rho_max 를 예측하나
    cells <- lin_cells(j)
    if (length(cells)) {
      cr <- vapply(cells, function(k) rfd_metrics(ser_mon[[k]], C1$paper_key[j], Pa, mats, cfg, measure = ms)$rho_max, 0)
      pv[[length(pv) + 1L]] <- data.table(run = rn, entry_id = C1$entry_id[j], base_rho_max = ma$rho_max, n_cells = length(cells),
                                          cells_rho_med = median(cr, na.rm = TRUE), cells_rho_max = suppressWarnings(max(cr, na.rm = TRUE)),
                                          cells_rho_q25 = unname(quantile(cr, 0.25, na.rm = TRUE)))
    }
  }
}
R <- rbindlist(res, fill = TRUE)
R <- merge(R, C1[, .(entry_id, paper_key, kind, status, opened_at, base_grade, base_pt, rescued, n_att, nB, best_pt, best_calmar,
                     wall_h, cpu_h, n_desc_entries, desc_n_att, desc_nB, desc_best_pt, desc_wall_h, mid)], by = "entry_id")
PV <- rbindlist(pv, fill = TRUE)

# --- 문턱 보정(현재 풀 · 단일 논문 후보) + 분위 민감도 --------------------------------
thr_of <- function(rn, q_dup, q_div = .rfd_num(cfg$calibration$q_div)) {
  ns <- R[run == rn & kind != "combo", .(status = now_status, rho_max = now_rho_max, r2_span = now_r2_span, rho_down = now_rho_down)]
  c2 <- cfg; c2$calibration$q_dup <- q_dup; c2$calibration$q_div <- q_div
  rfd_calibrate(ns, c2)
}
thr <- lapply(setNames(names(RUNS), names(RUNS)), function(rn) thr_of(rn, .rfd_num(cfg$calibration$q_dup)))
for (rn in names(thr)) cat(sprintf("문턱[%s] n=%d · τ_dup ρ=%.3f R²=%.3f · τ_div ρ=%.3f R²=%.3f · τ_div_down=%.3f\n", rn, thr[[rn]]$n_null,
                                   thr[[rn]]$tau_dup_rho, thr[[rn]]$tau_dup_r2, thr[[rn]]$tau_div_rho, thr[[rn]]$tau_div_r2, thr[[rn]]$tau_div_down))
R[, `:=`(base_ok = NA, asof_verdict = NA_character_, now_verdict = NA_character_, asof_disposition = NA_character_)]
mk <- function(k, pre) list(status = R[[paste0(pre, "status")]][k], rho_max = R[[paste0(pre, "rho_max")]][k],
                            r2_span = R[[paste0(pre, "r2_span")]][k], rho_down = R[[paste0(pre, "rho_down")]][k],
                            alpha_span_t = R[[paste0(pre, "alpha_span_t")]][k])
for (k in seq_len(nrow(R))) {
  rn <- R$run[k]
  base_ok <- (!is.na(R$base_pt[k]) && R$base_pt[k] >= 0) || isTRUE(R$rescued[k])
  set(R, k, "base_ok", base_ok)
  set(R, k, "asof_verdict", rfd_verdict(mk(k, "asof_"), thr[[rn]]))
  set(R, k, "now_verdict", rfd_verdict(mk(k, "now_"), thr[[rn]]))
  set(R, k, "asof_disposition", rfd_disposition(R$asof_verdict[k], base_ok, mk(k, "asof_"), thr[[rn]]))
}
R[, actual := fifelse(n_att > 0, "reinforced", "not_reinforced")]
R[, lineage_best_pt := pmax(best_pt, desc_best_pt, na.rm = TRUE)]
R[, lineage_nB := nB + desc_nB]
R[, lineage_wall_h := rowSums(cbind(wall_h, desc_wall_h), na.rm = TRUE)]
R[, lineage_cpu_h := cpu_h]
sens <- list()
for (rn in names(RUNS)) for (q in Q_GRID) {
  th <- thr_of(rn, q)
  X <- R[run == rn]
  v <- vapply(seq_len(nrow(X)), function(k) rfd_verdict(list(status = X$asof_status[k], rho_max = X$asof_rho_max[k], r2_span = X$asof_r2_span[k]), th), "")
  skip <- v == "duplicate" & X$actual == "reinforced"
  sens[[length(sens) + 1L]] <- data.table(run = rn, q_dup = q, tau_dup_rho = th$tau_dup_rho, tau_dup_r2 = th$tau_dup_r2,
                                          n_dup = sum(v == "duplicate"), n_dup_reinforced = sum(skip),
                                          saved_wall_h = sum(X$lineage_wall_h[skip]), lost_B_cells = sum(X$lineage_nB[skip]),
                                          lost_best_pt = if (any(skip)) max(X$lineage_best_pt[skip], na.rm = TRUE) else NA_real_,
                                          dup_entries = paste(sub("^RP_2026", "", X$entry_id[v == "duplicate"]), collapse = " "),
                                          flags_22632 = any(v == "duplicate" & grepl("22632", X$entry_id)))
}
SENS <- rbindlist(sens)

# 보유 겹침(as-of 이웃 · resid_all 판만)
R[, asof_jaccard := NA_real_]
for (k in which(R$run == "resid_all" & nzchar(R$asof_neighbor_member))) {
  h1 <- file.path(dirname(C1[mid == R$mid[k], series][1]), "04_holdings.csv")
  h2 <- mem[mid == R$asof_neighbor_member[k], holdings][1]
  set(R, k, "asof_jaccard", rfd_jaccard(h1, .rfd_or(h2, "")))
}
setorder(R, run, opened_at)
fwrite(R, file.path(out_dir, "replay_entries.csv"))
fwrite(PV, file.path(out_dir, "predictive_validity.csv"))
fwrite(SENS, file.path(out_dir, "quantile_sensitivity.csv"))
jsonlite::write_json(thr, file.path(out_dir, "thresholds_provisional.json"), auto_unbox = TRUE, pretty = TRUE, digits = 6)

# --- 음성 대조: 순수 잡음(후보 잔차의 중앙 변동성 · 평균 0) ------------------------------
set.seed(20261006)
bmm <- bm[, .(b = prod(1 + bm) - 1), by = .(ym = format(date, "%Y-%m"))]
sd_med <- median(vapply(C1$mid, function(k) sd(ser_mon[[k]]$e, na.rm = TRUE), 0))
yms_c <- rownames(mats$E)[rownames(mats$E) >= "2005-03" & rownames(mats$E) <= "2026-08"]
noise <- list()
for (rn in names(RUNS)) {
  pool_now <- as_pool(rfd_pool(mem, cfg, exclude_flags = RUNS[[rn]]$ex))
  for (b in seq_len(200)) {
    nm <- merge(data.table(ym = yms_c, z = rnorm(length(yms_c), 0, sd_med)), bmm, by = "ym")
    nm[, `:=`(r = b + z, a = z, e = z, e2 = z)]   # 원수익 = 벤치 + 잡음(β=1) → 초과 = 잔차 = 잡음
    m <- rfd_metrics(nm[, .(ym, r, a, e, e2)], "noise:none", pool_now, mats, cfg, measure = RUNS[[rn]]$measure)
    v <- rfd_verdict(m, thr[[rn]])
    noise[[length(noise) + 1L]] <- data.table(run = rn, b = b, rho_max = m$rho_max, r2_span = m$r2_span, rho_down = m$rho_down,
                                              alpha_span_t = m$alpha_span_t, verdict = v,
                                              disposition_if_neg_alpha = rfd_disposition(v, FALSE, m, thr[[rn]]))
  }
}
NZ <- rbindlist(noise)
fwrite(NZ, file.path(out_dir, "negative_control_noise.csv"))

# --- 양성 대조 ----------------------------------------------------------------------
pc <- list()
S1 <- C1[kind != "combo"]
for (pk in unique(cand[has_series == TRUE & kind != "combo", paper_key])) {
  ids <- cand[has_series == TRUE & paper_key == pk, mid]
  if (length(ids) < 2L) next
  cb <- utils::combn(ids, 2)
  for (c in seq_len(ncol(cb))) {
    r <- .rfd_cor(mats$E[, cb[1, c]], mats$E[, cb[2, c]])
    r2 <- .rfd_cor(mats$E2[, cb[1, c]], mats$E2[, cb[2, c]])
    pc[[length(pc) + 1L]] <- data.table(type = "same_paper_bases(resid|resid2)", paper_key = pk,
                                        a = cand[mid == cb[1, c], entry_id][1], b = cand[mid == cb[2, c], entry_id][1],
                                        rho = r[["rho"]], rho2 = r2[["rho"]], n = r[["n"]])
  }
}
for (j in seq_len(nrow(S1))) {
  own <- intersect(mem[grade %in% c("A", "B") & lineage == S1$paper_key[j] & kind == "cell", mid], colnames(mats$E))
  if (!length(own)) next
  rr <- vapply(own, function(o) .rfd_cor(mats$E[, S1$mid[j]], mats$E[, o])[["rho"]], 0)
  rr2 <- vapply(own, function(o) .rfd_cor(mats$E2[, S1$mid[j]], mats$E2[, o])[["rho"]], 0)
  pc[[length(pc) + 1L]] <- data.table(type = "base_vs_own_B_cells(resid|resid2)", paper_key = S1$paper_key[j], a = S1$entry_id[j],
                                      b = sprintf("%d칸 · 중앙 %.3f | %.3f", length(own), median(rr, na.rm = TRUE), median(rr2, na.rm = TRUE)),
                                      rho = max(rr, na.rm = TRUE), rho2 = max(rr2, na.rm = TRUE), n = length(own))
}
PC <- rbindlist(pc, fill = TRUE)
fwrite(PC, file.path(out_dir, "positive_controls.csv"))

# --- 요약 -------------------------------------------------------------------------
cat("\n==== 재생 요약 ====\n")
for (rn in names(RUNS)) {
  X <- R[run == rn]
  cat(sprintf("\n[%s] 후보 %d\n", rn, nrow(X)))
  print(dcast(X[, .N, by = .(kind, asof_verdict)], kind ~ asof_verdict, value.var = "N", fill = 0))
  print(dcast(X[, .N, by = .(actual, asof_disposition)], actual ~ asof_disposition, value.var = "N", fill = 0))
  cat("잡음 판정:", paste(names(table(NZ[run == rn, verdict])), table(NZ[run == rn, verdict]), collapse = " "),
      "· 잡음 rho_max 중앙", round(median(NZ[run == rn, rho_max], na.rm = TRUE), 3),
      "· 음수 알파 가정 diversifier 비율", round(mean(NZ[run == rn, disposition_if_neg_alpha] == "diversifier"), 3), "\n")
  P1 <- PV[run == rn]
  if (nrow(P1) > 2) cat(sprintf("예측 타당도: cor(기저 rho_max, 칸 중앙 rho_max)=%.3f (n=%d) · 칸 중앙 − 기저 중앙 = %.3f\n",
                                cor(P1$base_rho_max, P1$cells_rho_med, use = "complete.obs"), nrow(P1),
                                median(P1$cells_rho_med - P1$base_rho_max, na.rm = TRUE)))
}
cat("\n분위 민감도:\n"); print(SENS[, !"dup_entries"])
cat("\n양성 대조(같은 논문 기저 쌍 · 잔차):\n"); print(PC[startsWith(type, "same_paper")])
cat("\n소요:", round(as.numeric(difftime(Sys.time(), t_start, units = "secs")), 1), "초\n")
