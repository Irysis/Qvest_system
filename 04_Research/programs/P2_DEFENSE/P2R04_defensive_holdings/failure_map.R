## P2R04 실패 지도(사전등록 conclusion_scope 5 '검증 0 일 때 남길 것') — 장치 × 위기 × 원인 · β 짝 여유 · 크기 × β 짝 · 결측 · 희석 · 용량 ·
##   크기 · 유동성 귀속 · 보유 겹침 · 국면별 월 차이. 입력 = 보는 창 평가값만(results/evaluation_visible.json — 칸별 rules.*.per_crisis · size_beta ·
##   record.size_decile · liquidity · concentration · holdings_overlap · regime_months · readings). 수치는 계약 산출 그대로 옮긴다(AX-008) —
##   새로 계산하는 것은 비교(포착 < 비교 대상 − 사전등록 crisis_improve_min)와 집계뿐. 원인 분류는 판정이 아니라 기술(記述)이다 —
##   규칙은 아래 .cause() 에 고정해 적는다(결과를 본 뒤 만든 분류임을 밝힌다 · P2R03 failure_map.R 과 같은 틀).
##   실행: Rscript failure_map.R → stage_artifacts/programs/P2_DEFENSE/P2R04_defensive_holdings/failure_map.{md,csv} · cell_profile.csv
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
RD  <- file.path(ROOT, "04_Research/programs/P2_DEFENSE/P2R04_defensive_holdings")
OUT <- file.path(ROOT, "stage_artifacts/programs/P2_DEFENSE/P2R04_defensive_holdings")
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
num <- function(x) if (is.null(x) || !length(x)) NA_real_ else suppressWarnings(as.numeric(x[[1]]))
ev  <- fromJSON(file.path(RD, "results/evaluation_visible.json"), simplifyVector = FALSE)
TOL <- num(fromJSON(file.path(OUT, "prereg.json"), simplifyVector = FALSE)$final_selection_rule$crisis_improve_min)
DEV <- c(H1 = "하방β(D04)", H2 = "저변동(D03)", H3 = "β 비대칭(D07)", H4 = "퀄리티(Q08)")
pc  <- function(x) if (is.null(x)) data.table(k = character(), m = numeric(), r = numeric()) else
  rbindlist(lapply(x, function(z) data.table(k = z$k, m = num(z$m), r = num(z$r))), fill = TRUE)
by_peak <- function(x, field) if (is.null(x)) data.table(peak = character(), v = numeric()) else
  rbindlist(lapply(x, function(z) data.table(peak = as.character(z$peak_date), v = num(z[[field]]))), fill = TRUE)
## 원인 기술 규칙(고정): β 짝 승 = 선택 몫 · RX0 대비만 승 = 노출(β) 몫(같은 β 현금 사본도 같은 만큼 덜 빠짐) · 그 밖 = 방어 없음
##   덧붙임: 희석 몫(E2 · 무작위 순열 팩터 N0 도 그 위기에서 RX0 대비 개선 — 평가 readings.dilution) · 크기 × β 짝 승 · 엔진 > 시장(RX0 포착 > 1)
.cause <- function(b_beta, b_rx0, dil, b_sb, cap_rx0) {
  base <- if (isTRUE(b_beta)) "선택 몫(β 짝 승)" else if (isTRUE(b_rx0)) "노출(β) 몫(β 사본도 덜 빠짐)" else "방어 없음(RX0 대비 개선 없음)"
  add <- c(if (isTRUE(dil)) "희석 몫(N0 도 개선)" else NULL, if (isTRUE(b_sb)) "크기 × β 짝 승" else NULL,
           if (is.finite(cap_rx0) && cap_rx0 > 1) "엔진 > 시장" else NULL)
  paste(c(base, add), collapse = " · ")
}
DIL <- ev$readings$dilution$by_device; DIAG_E <- ev$readings$diag_engine %||% "E2"
rows <- list(); prof <- list()
for (cell in Filter(function(z) identical(z$role, "judge"), ev$cells)) {
  e <- cell$engine; d <- cell$device; R <- cell$rules
  CR <- pc(R$crisis$per_crisis)                                                   # m = 변형 · r = RX0
  BC <- unique(rbind(pc(R$beta_deep$per_crisis), pc(R$fast$per_crisis), pc(R$slow$per_crisis))[, .(k, cap_beta = r)], by = "k")
  SB <- pc(cell$size_beta$per_crisis)[, .(k, cap_sb = r)]
  deep <- unlist(cell$crisis_pairs$deep_keys %||% list()); fast <- unlist(R$fast$keys %||% list()); slow <- unlist(R$slow$keys %||% list())
  dil <- if (identical(e, DIAG_E)) unlist(DIL[[d]]$dilution_share %||% list()) else character()
  SZ <- by_peak(cell$record$size_decile$per_crisis, "mean_decile"); SZ0 <- by_peak(cell$record$size_decile$per_crisis, "mean_decile_rx0")
  LQ <- by_peak(cell$liquidity$variant$per_crisis, "mean_decile"); LQ0 <- by_peak(cell$liquidity$rx0$per_crisis, "mean_decile")
  T1 <- by_peak(cell$concentration$per_crisis, "top1")
  M <- merge(merge(CR, BC, by = "k", all.x = TRUE), SB, by = "k", all.x = TRUE)
  M[, peak := sub(" .*$", "", k)]
  for (X in list(list(SZ, "size_dec"), list(SZ0, "size_dec_rx0"), list(LQ, "liq_dec"), list(LQ0, "liq_dec_rx0"), list(T1, "top1")))
    M <- merge(M, setnames(copy(X[[1]]), "v", X[[2]]), by = "peak", all.x = TRUE)
  M[, `:=`(engine = e, device = d, name = DEV[[d]],
           type = vapply(k, function(z) paste(c(if (z %in% deep) "깊은" else NULL, if (z %in% fast) "빠른" else if (z %in% slow) "느린" else "미분류"), collapse = " · "), ""),
           beats_rx0 = is.finite(m) & is.finite(r) & m < r - TOL, beats_beta = is.finite(m) & is.finite(cap_beta) & m < cap_beta - TOL,
           beats_sb = is.finite(m) & is.finite(cap_sb) & m < cap_sb - TOL, beats_mkt = is.finite(m) & m < 1 - TOL,
           beta_margin = round(cap_beta - m, 3), diluted = if (identical(e, DIAG_E)) k %in% dil else NA)]
  M[, cause := mapply(.cause, beats_beta, beats_rx0, diluted, beats_sb, r)]
  rows[[length(rows) + 1L]] <- M
  BA <- R$beta_asym %||% list(); HO <- cell$holdings_overlap %||% list(); RM <- cell$regime_months %||% list(); P <- R$path %||% list()
  prof[[length(prof) + 1L]] <- data.table(engine = e, device = d, name = DEV[[d]], verdict = cell$verdict, attr = cell$attribution$label %||% NA_character_,
    beta = round(num(BA$beta[[1]]), 2), beta_rx0 = round(num(BA$beta[[2]]), 2), down_up = round(num(BA$ratio), 2), down_up_rx0 = round(num(BA$ratio_rx0), 2),
    k_beta_copy = round(num(R$beta_deep$k), 2), name_overlap = round(num(HO$name_overlap_mean), 2),
    d_crisis_m = round(100 * num(RM$crisis$mean), 2), d_bull_m = round(100 * num(RM$bull$mean), 2), d_other_m = round(100 * num(RM$other$mean), 2),
    recov_longer = round(num(cell$recovery$share), 2), mdd_vs_bench = round(num(P$mdd_vs_bench[[1]]), 2), cdar = round(num(P$cdar[[1]]), 3), cdar_rx0 = round(num(P$cdar[[2]]), 3),
    turnover = round(num(cell$record$turnover_annual[[1]]), 1), turnover_rx0 = round(num(cell$record$turnover_annual[[2]]), 1))
}
FM <- rbindlist(rows, fill = TRUE); PF <- rbindlist(prof)
setorder(FM, engine, device, k); setorder(PF, engine, device)
keep <- c("engine", "device", "name", "k", "type", "m", "r", "cap_beta", "cap_sb", "beta_margin", "beats_rx0", "beats_beta", "beats_sb", "beats_mkt", "diluted",
          "size_dec", "size_dec_rx0", "liq_dec", "liq_dec_rx0", "top1", "cause")
FM <- FM[, ..keep]; setnames(FM, c("k", "m", "r"), c("crisis", "cap", "cap_rx0"))
for (j in c("cap", "cap_rx0", "cap_beta", "cap_sb", "top1")) set(FM, j = j, value = round(FM[[j]], 3))
for (j in c("size_dec", "size_dec_rx0", "liq_dec", "liq_dec_rx0")) set(FM, j = j, value = round(FM[[j]], 1))
fwrite(FM, file.path(OUT, "failure_map.csv")); fwrite(PF, file.path(OUT, "cell_profile.csv"))
md <- function(D) c(paste0("| ", paste(names(D), collapse = " | "), " |"), paste0("|", strrep("---|", ncol(D))),
                    apply(D, 1, function(r) paste0("| ", paste(ifelse(is.na(r), "NA", trimws(r)), collapse = " | "), " |")))
tally <- FM[, .N, by = .(engine, device, cause = sub(" · .*$", "", cause))]
dil_t <- FM[engine == DIAG_E & beats_rx0 == TRUE, .(rx0_wins = .N, diluted = sum(diluted %in% TRUE)), by = device]
sz_t  <- FM[, .(size_dec = round(mean(size_dec, na.rm = TRUE), 1), size_dec_rx0 = round(mean(size_dec_rx0, na.rm = TRUE), 1),
                liq_dec = round(mean(liq_dec, na.rm = TRUE), 1), liq_dec_rx0 = round(mean(liq_dec_rx0, na.rm = TRUE), 1)), by = .(engine, device)]
RDG <- ev$readings
mis <- rbindlist(lapply(names(RDG$missing), function(h) { z <- RDG$missing[[h]]
  data.table(device = h, diag_cell = z$diag_cell %||% NA, beta_wins = num(z$n_win), missing_pattern = num(z$n_missing_pattern), status = z$status %||% NA) }))
cap <- rbindlist(lapply(names(RDG$capacity), function(h) { z <- RDG$capacity[[h]]
  data.table(device = h, label = z$label %||% NA, verdicts = paste(unlist(z$verdicts), collapse = " · "), e3_composition = paste(unlist(z$e3_composition), collapse = " → ")) }))
dg <- rbindlist(lapply(ev$diagnostics, function(z) data.table(cell = z$cell, verdict = z$verdict %||% z$status,
  holdings_differ = num(z$holdings_overlap$n_differ), name_overlap = round(num(z$holdings_overlap$name_overlap_mean), 3))))
txt <- c("# P2R04 실패 지도 — 장치 × 위기 × 원인(보는 창 · 2026-10-18)", "",
  sprintf("- 입력 = evaluation_visible.json 만(칸별 per_crisis · 크기 × β 짝 · 크기/유동성 십분위 · 집중 · 보유 겹침 · 국면 월 차이 · 진단 판독). 포착 = 위기 낙폭 포착(dd_capture · 낮을수록 방어) · 이김 = 비교 대상보다 %.2f 이상 낮음(사전등록 crisis_improve_min).", TOL),
  "- 원인 기술 규칙(결과를 본 뒤 만든 기술 분류 · 판정 아님): β 짝 승 = 선택 몫 · RX0 대비만 승 = 노출(β) 몫 · 그 밖 = 방어 없음 / 덧붙임: 희석 몫(E2 — 무작위 순열 팩터 N0 도 그 위기에서 RX0 대비 개선) · 크기 × β 짝 승 · 엔진 > 시장(RX0 포착 > 1).",
  "- 비교 대상: cap_rx0 = 같은 배치 RX0 · cap_beta = RX0 × k(변형과 같은 β · 나머지 현금 — 깊은 · 빠른 · 느린 위기) · cap_sb = 크기 × β 짝(크기 분포 바스켓을 변형 β 로 낮춘 현금 사본 — 깊은 위기만 · 기록) · 시장 = 1.",
  "- 크기 · 유동성 십분위 = 위기 고점 시점 보유 종목의 평균 십분위(10 = 가장 큼 · 가장 유동적 · 평가 record.size_decile · liquidity).", "",
  "## 원인 집계(장치 × 엔진 · 위기 7)", md(dcast(tally, engine + device ~ cause, value.var = "N", fill = 0)), "",
  sprintf("## 희석 몫(%s · RX0 대비 개선 위기 중 N0 도 개선한 위기)", DIAG_E), md(dil_t), "",
  "## 크기 · 유동성 귀속(위기 고점 보유 평균 십분위 · 7위기 평균)", md(sz_t), "",
  "## 칸 프로필(β · 하락/상승 β 비 · 보유 겹침 · 국면 월 차이 %/월 · 회복 · 경로 · 회전)", md(PF), "",
  "## 결측 짝(Ck · DNN 100% + 장치 팩터 내부 결합 — 팩터 결측 종목 제외 효과만)",
  "- beta_wins = 변형 Hk 의 깊은 위기 β 짝 승리 수 · missing_pattern = 그 승리 위기에서 Ck 도 β 짝을 이긴 수(= '결측 패턴 방어'). 평가 로그의 '결측 짝 NA' 는 꼬리표 없음(결측 패턴 방어 0)이다.",
  md(mis), "",
  "## 용량 짝(방어 몫 50% · 12.5% × 두 엔진 — 네 칸 모두 통과해야 '세기 의존 없음')", md(cap), "",
  "## 진단 칸(보유 차이 · 이름 겹침 vs RX0)", md(dg), "",
  "## 장치 × 위기 상세", md(FM[, .(engine, device, crisis, type, cap, cap_rx0, cap_beta, cap_sb, beats_beta, beats_sb, beats_mkt, diluted, size_dec, liq_dec, top1, cause)]))
writeLines(txt, file.path(OUT, "failure_map.md"), useBytes = TRUE)
cat("failure_map ok:", nrow(FM), "행 ·", nrow(PF), "칸 →", OUT, "\n")
print(dcast(tally, engine + device ~ cause, value.var = "N", fill = 0)); print(dil_t); print(sz_t); print(PF[, .(engine, device, beta, down_up, down_up_rx0, name_overlap, d_crisis_m, d_bull_m, d_other_m, recov_longer)])
