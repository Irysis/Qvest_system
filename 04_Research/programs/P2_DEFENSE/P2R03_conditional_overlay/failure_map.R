## P2R03 실패 지도(사전등록 leave_behind '검증 0 일 때 남길 것' · 철학 P2 C-20261018-011 ②) — 장치 × 위기 × 원인 · 현금 타이밍 · 대조 읽기
##   입력 = 보는 창 산출만: results/evaluation_visible.json(칸별 rules · record.expo_m · cash_timing · contrast) ·
##          results/<칸>/visible/diagnosis_packet.json(위기별 포착) · results/<칸>/original/visible_rx0_beta/diagnosis_packet.json(β 사본 · 보는 창)
##   수치는 계약 산출 그대로 옮긴다(AX-008) — 새로 계산하는 것은 위기 구간 안 · 바닥 뒤 3개월의 월 노출 평균(평가 기록 expo_m 의 구간 평균)뿐.
##   원인 분류는 판정이 아니라 기술(記述)이다 — 규칙은 아래 .cause() 에 고정해 적는다(결과를 본 뒤 만든 분류임을 밝힌다).
##   실행: Rscript failure_map.R → stage_artifacts/programs/P2_DEFENSE/P2R03_conditional_overlay/failure_map.{md,csv}
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
RD  <- file.path(ROOT, "04_Research/programs/P2_DEFENSE/P2R03_conditional_overlay")
OUT <- file.path(ROOT, "stage_artifacts/programs/P2_DEFENSE/P2R03_conditional_overlay")
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
ev  <- fromJSON(file.path(RD, "results/evaluation_visible.json"), simplifyVector = FALSE)
TOL <- as.numeric(fromJSON(file.path(ROOT, "stage_artifacts/programs/P2_DEFENSE/P2R03_conditional_overlay/prereg.json"), simplifyVector = FALSE)$final_selection_rule$crisis_improve_min)
DEV <- c(D1 = "하방β 축소", D2 = "특이변동 축소", D3 = "상태 거리 게이트", D4 = "꼬리 확률 게이트", D5 = "추세 현금", D6 = "낙폭 브레이크", D7 = "낙폭 재진입")
pk  <- function(path) if (file.exists(path)) fromJSON(path, simplifyVector = FALSE) else NULL
crises_of <- function(p) if (is.null(p)) data.table() else rbindlist(lapply(p$behavior$crises %||% list(), function(z)
  data.table(k = paste(z$peak_date, z$trough_date), peak = as.Date(z$peak_date), trough = as.Date(z$trough_date), cap = as.numeric(z$dd_capture %||% NA))), fill = TRUE)
ym_seq <- function(a, b) format(seq(as.Date(format(a, "%Y-%m-01")), as.Date(format(b, "%Y-%m-01")), by = "month"), "%Y-%m")
## 원인 기술 규칙(고정) — β 짝 승 = 방어 · 위기 중 평균 노출 ≥ 0.95 = 신호 지연(노출 유지) · 그 밖 = 현금 비용(현금이 손실 구간과 어긋남)
##   덧붙임: 바닥 뒤 3개월 평균 노출 < 위기 중 평균 노출 − 0.05 = 재진입 지연 · RX0 포착 > 1 = 엔진이 시장보다 더 빠짐(엔진 비대칭)
.cause <- function(beats_beta, e_cr, e_rb, cap_rx0) {
  base <- if (isTRUE(beats_beta)) "방어(β 짝 승)" else if (is.finite(e_cr) && e_cr >= 0.95) "신호 지연(위기 내내 노출 유지)" else "현금 비용(현금이 손실 구간과 어긋남)"
  add <- c(if (is.finite(e_rb) && is.finite(e_cr) && e_rb < e_cr - 0.05) "재진입 지연" else NULL,
           if (is.finite(cap_rx0) && cap_rx0 > 1) "엔진 > 시장" else NULL)
  paste(c(base, add), collapse = " · ")
}
rows <- list(); cash <- list()
for (cell in ev$cells) {
  if (isTRUE(cell$lag) || !isTRUE(cell$tested)) next
  e <- cell$engine; d <- cell$device; code <- cell$cell
  R <- cell$rules
  deep <- unlist(R$deep$deep_keys %||% list())
  ft <- rbindlist(lapply(R$fast$table %||% list(), function(z) data.table(k = z$k, fast = isTRUE(z$fast))), fill = TRUE)
  V  <- crises_of(pk(file.path(RD, "results", code, "visible/diagnosis_packet.json")))
  X0 <- crises_of(pk(file.path(RD, "results", cell$rx0, "visible/diagnosis_packet.json")))
  bp <- file.path(RD, "results", code, "original/visible_rx0_beta/diagnosis_packet.json")
  BC <- if (file.exists(bp)) crises_of(pk(bp)) else copy(X0)          # k ≥ 1 이면 β 사본 = RX0(평가 규칙)
  if (!nrow(V)) next
  M <- merge(merge(V, X0[, .(k, cap_rx0 = cap)], by = "k", all.x = TRUE), BC[, .(k, cap_beta = cap)], by = "k", all.x = TRUE)
  EX <- rbindlist(lapply(cell$record$expo_m %||% list(), function(z) data.table(ym = z$ym, e = as.numeric(z$e))))
  for (i in seq_len(nrow(M))) {
    r <- M[i]
    cr_m <- ym_seq(r$peak, r$trough); rb_m <- ym_seq(r$trough + 31, r$trough + 92)
    e_cr <- if (nrow(EX)) mean(EX[ym %in% cr_m, e]) else NA_real_
    e_rb <- if (nrow(EX)) mean(EX[ym %in% rb_m, e]) else NA_real_
    typ <- paste(c(if (r$k %in% deep) "깊은" else NULL, if (r$k %in% ft[fast %in% TRUE, k]) "빠른" else if (r$k %in% ft[fast %in% FALSE, k]) "느린" else "미분류"), collapse = " · ")
    bb <- is.finite(r$cap_beta) && r$cap < r$cap_beta - TOL
    rows[[length(rows) + 1L]] <- data.table(engine = e, device = d, name = DEV[[d]], crisis = r$k, type = typ,
      cap = round(r$cap, 3), cap_rx0 = round(r$cap_rx0, 3), cap_beta = round(r$cap_beta, 3),
      beats_rx0 = is.finite(r$cap_rx0) && r$cap < r$cap_rx0 - TOL, beats_beta = bb,
      expo_crisis = round(e_cr, 2), expo_rebound3 = round(e_rb, 2), cause = .cause(bb, e_cr, e_rb, r$cap_rx0))
  }
  ct <- cell$record$cash_timing %||% list()
  cash[[length(cash) + 1L]] <- data.table(engine = e, device = d, name = DEV[[d]], cash_share = round(as.numeric(ct$cash_share %||% NA), 3),
    precision = round(as.numeric(ct$precision %||% NA), 3), recall = round(as.numeric(ct$recall %||% NA), 3),
    expo_crisis = round(as.numeric(ct$expo_crisis %||% NA), 3), expo_noncrisis = round(as.numeric(ct$expo_noncrisis %||% NA), 3),
    rebound_3m = round(as.numeric(ct$rebound_3m %||% NA), 3), rebound_6m = round(as.numeric(ct$rebound_6m %||% NA), 3),
    hm_gamma = round(as.numeric(cell$record$hm_timing$gamma %||% NA), 3), hm_t = round(as.numeric(cell$record$hm_timing$t_gamma %||% NA), 2))
}
FM <- rbindlist(rows); CT <- rbindlist(cash)
setorder(FM, engine, device, crisis); setorder(CT, engine, device)
fwrite(FM, file.path(OUT, "failure_map.csv")); fwrite(CT, file.path(OUT, "cash_timing.csv"))
md <- function(D) c(paste0("| ", paste(names(D), collapse = " | "), " |"), paste0("|", strrep("---|", ncol(D))),
                    apply(D, 1, function(r) paste0("| ", paste(ifelse(is.na(r), "NA", trimws(r)), collapse = " | "), " |")))
tally <- FM[, .N, by = .(engine, device, cause = sub(" · .*$", "", cause))]
CON <- ev$contrast
txt <- c("# P2R03 실패 지도 — 장치 × 위기 × 원인(보는 창 · 2026-10-18)", "",
  sprintf("- 입력 = evaluation_visible.json · 보는 창 진단 패킷(변형 · RX0 · β 사본) · 평가 기록 월 노출(expo_m). 포착 = 위기 낙폭 포착(dd_capture · 낮을수록 방어) · 이김 = 비교 대상보다 %.2f 이상 낮음(사전등록 crisis_improve_min).", TOL),
  "- 원인 기술 규칙(결과를 본 뒤 만든 기술 분류 · 판정 아님): β 짝 승 = 방어 · 위기 중 평균 노출 ≥ 0.95 = 신호 지연 · 그 밖 = 현금 비용 / 덧붙임: 바닥 뒤 3개월 노출 < 위기 중 노출 − 0.05 = 재진입 지연 · RX0 포착 > 1 = 엔진 > 시장.",
  "- 두 엔진은 D3~D7 의 월 노출 경로가 같다(시장 수준 스칼라 게이트 · 철학 P2 C-012) — 엔진 쌍은 타이밍 사건 수를 늘리지 않는다.", "",
  "## 원인 집계(장치 × 엔진 · 위기 7)", md(dcast(tally, engine + device ~ cause, value.var = "N", fill = 0)), "",
  "## 현금 타이밍(평가 기록 · 현금 = 월 노출 < 0.5)", md(CT), "",
  "## 장치 × 위기 상세", md(FM[, .(engine, device, crisis, type, cap, cap_rx0, cap_beta, beats_beta, expo_crisis, expo_rebound3, cause)]), "",
  "## 대조 읽기(평가 contrast · 판정 아님)")
for (eng in names(CON)) {
  txt <- c(txt, sprintf("### %s", eng))
  if (!is.null(CON[[eng]]$exposure_cor)) {
    C <- CON[[eng]]$exposure_cor
    M <- if (is.list(C) && !is.null(names(C))) as.data.table(lapply(C, function(v) unlist(v))) else as.data.table(do.call(rbind, lapply(C, unlist)))
    txt <- c(txt, "- 월 노출 경로 상관(장치 간):", md(cbind(device = names(DEV)[seq_len(nrow(M))], M)))
  }
  txt <- c(txt, paste0("- 읽기 쌍: ", paste(unlist(CON[[eng]]$readings), collapse = " / ")), "")
}
writeLines(txt, file.path(OUT, "failure_map.md"), useBytes = TRUE)
cat("failure_map ok:", nrow(FM), "행 ·", nrow(CT), "칸 →", OUT, "\n")
print(dcast(tally, engine + device ~ cause, value.var = "N", fill = 0))
