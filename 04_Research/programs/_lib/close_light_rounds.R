## P2R02 · P1R01 · P3R01 종료 — 보고서(md) · 등록부 기록 · 보고 1통(라운드마다)
## 실행: Rscript close_light_rounds.R <P2R02|P1R01|P3R01> [record] [send]   (인자 없으면 미리보기)
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT, QM_ROOT = ROOT); setwd(ROOT)
source("02_Infrastructure/programs/program_registry.R")
source("02_Infrastructure/programs/program_report.R")
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
A <- commandArgs(trailingOnly = TRUE); WHICH <- A[1]; RECORD <- "record" %in% A; SEND <- "send" %in% A
pct <- function(x) prep_fmt_pct(x, 1L); rt <- function(x) prep_fmt_ratio(x, 2L)
ENGN <- c(E1 = "모멘텀 12-1", E2 = "2002.06975 DNN 원형", E3 = "B6_36(2002.06975 계보)")
DEVN <- c(C1 = "추세 현금", C2 = "변동성 타기팅", C3 = "낙폭 제어", C4 = "저변동 틸트", C5 = "퀄리티 틸트", C6 = "추세 현금+저변동")
KN <- c(K0 = "EW(기준)", K1 = "역변동성", K2 = "최소분산", K3 = "낙폭 제약(CDaR)", K4 = "켈리", K5 = "순위 버퍼 2배")
CFG <- list(
  P2R02 = list(program = "P2_DEFENSE", pname = "방어 엔진", target = "방어 장치 교차 엔진 검증(장치 6 × 엔진 3)", round = "P2R02_device_cross_engine", dir = "04_Research/programs/P2_DEFENSE/P2R02_device_cross_engine"),
  P1R01 = list(program = "P1_RETURN", pname = "수익 엔진", target = "수익 엔진 자격(엔진 3)", round = "P1R01_engine_qualification", dir = "04_Research/programs/P1_RETURN/P1R01_engine_qualification"),
  P3R01 = list(program = "P3_CONSTRUCTION", pname = "구성", target = "구성 지도(구성 5 × 엔진 2)", round = "P3R01_construction_map", dir = "04_Research/programs/P3_CONSTRUCTION/P3R01_construction_map"))
C <- CFG[[WHICH]]; if (is.null(C)) stop("usage: close_light_rounds.R <P2R02|P1R01|P3R01> [record] [send]")
ev <- fromJSON(file.path(ROOT, C$dir, "results/evaluation.json"), simplifyVector = TRUE)
SA <- file.path(ROOT, "stage_artifacts/programs", C$program, C$round); dir.create(SA, recursive = TRUE, showWarnings = FALSE)
L <- character(0); a <- function(...) L <<- c(L, paste0(...))
items <- character(0); verdict_line <- ""; next_step <- ""; results <- list(); status_after <- "ready"; reason <- ""
if (WHICH == "P2R02") {
  V <- as.data.table(ev$devices)
  a("# P2R02 방어 장치 교차 엔진 검증 — 라운드 보고서"); a("")
  a("> 사전등록 md5 ", ev$prereg_md5, " · 측정 = P0R01 21칸 공유 · 보는 창 위기 ", ev$n_crises_visible, "개 · 급락/완만 경계 ", ev$crisis_type_median_tdays, "거래일")
  a(""); a("| 장치 | (엔진×위기) 쌍 | V1 엔진 단독보다 덜 빠짐 | V2 크기+노출 짝 플라시보 넘음 | V3 상승 포착 ≥ ", rt(ev$uc_floor), " 엔진 | 급락형 V1 | 완만형 V1 | 판정 |")
  a("|---|---|---|---|---|---|---|---|")
  for (i in seq_len(nrow(V))) with(V[i], a("| ", DEVN[device], " | ", n_pairs, " | ", pct(v1_share), " | ", pct(v2_share), " | ", n_uc_ok, "/", n_eng, " | ",
    pct(v1_crash), " | ", pct(v1_grind), " | ", if (verdict == "validated") "**검증**" else paste0("기각(", fail_codes, ")"), " |"))
  val <- V[verdict == "validated"]$device
  a(""); a("- 과반 = ", rt(ev$majority_share), " · V2 = 같은 크기 분포 · 같은 평균 노출의 무작위 포트폴리오 200개 분위(MC8) — 노출을 줄였을 뿐인 방어는 V2 를 못 넘는다.")
  a("- 검증 장치: ", if (length(val)) paste(DEVN[val], collapse = " · ") else "없음", " — P4 조립의 방어 후보(P4 에서 고를 때 이 6장치를 시행 수로 센다).")
  items <- vapply(seq_len(nrow(V)), function(i) with(V[i], sprintf("%s — 단독보다 덜 빠짐 %s · 플라시보 넘음 %s · 상승 유지 엔진 %d/%d → %s", DEVN[device], pct(v1_share), pct(v2_share),
    n_uc_ok, n_eng, if (verdict == "validated") "검증" else "기각")), character(1))
  verdict_line <- sprintf("검증 장치 %d/6 — %s", length(val), if (length(val)) paste(DEVN[val], collapse = " · ") else "크기·노출 짝 대조를 넘는 장치 없음")
  next_step <- "검증 장치는 P4 조립 후보 · 기각 장치는 기전 교훈으로"
  results <- list(validated = as.list(val), devices = V[, .(device, v1_share, v2_share, n_uc_ok, verdict, fail_codes)])
  reason <- sprintf("P2R02 완료 — 검증 장치 %d/6", length(val))
} else if (WHICH == "P1R01") {
  T <- as.data.table(ev$table)
  a("# P1R01 수익 엔진 자격 — 라운드 보고서"); a("")
  a("> 사전등록 md5 ", ev$prereg_md5, " · 측정 = P0R01 C0 칸 공유 · 자격 = 보는 창 β-통제 t(α) ≥ ", rt(ev$t_alpha_min), " ∧ 상승 포착 ≥ ", rt(ev$uc_floor))
  a(""); a("| 엔진 | 보는 창 t(α) | 보는 창 α(연) | 베타 | 상승 포착 | 자격 | 시험 창 α(연) | 유지 |"); a("|---|---|---|---|---|---|---|---|")
  for (i in seq_len(nrow(T))) with(T[i], a("| ", ENGN[engine], " | ", rt(t_alpha_vis), " | ", pct(alpha_ann_vis), " | ", rt(beta_vis), " | ", rt(uc_vis), " | ",
    if (isTRUE(qualify)) "**자격**" else "미달", " | ", pct(alpha_ann_test), " | ", if (isTRUE(test_hold)) "✓" else if (isFALSE(test_hold)) "✗" else "—", " |"))
  q <- T[qualify %in% TRUE]$engine
  a(""); a("- 재료 규칙(B 이상)에 맞는 새 엔진이 없어 기존 3종만 판정했다(사전등록 material_note) — 새 재료는 충실구현 레인으로.")
  items <- vapply(seq_len(nrow(T)), function(i) with(T[i], sprintf("%s — t(α) %s · 베타 %s · 상승 포착 %s → %s", ENGN[engine], rt(t_alpha_vis), rt(beta_vis), rt(uc_vis),
    if (isTRUE(qualify)) "자격" else "미달")), character(1))
  verdict_line <- sprintf("수익 엔진 자격 %d/3 — %s", length(q), if (length(q)) paste(ENGN[q], collapse = " · ") else "자격 엔진 없음(새 재료 필요)")
  next_step <- if (length(q)) "자격 엔진은 P4 수익 엔진 후보 · 새 재료 확보는 충실구현 레인" else "새 재료 확보(충실구현 레인) — P1 은 재료 대기"
  results <- list(qualified = as.list(q), table = T[, .(engine, t_alpha_vis, beta_vis, uc_vis, qualify, alpha_ann_test, test_hold)])
  status_after <- if (length(q)) "ready" else "idle"; reason <- sprintf("P1R01 완료 — 자격 %d/3", length(q))
} else {
  T <- as.data.table(ev$table)
  a("# P3R01 구성 지도 — 라운드 보고서"); a("")
  a("> 사전등록 md5 ", ev$prereg_md5, " · 기준 = P0R01 EW 칸 · improve = 보는 창 CDaR < 기준 ∧ S_vis ≥ 기준")
  a(""); a("| 엔진 | 구성 | CDaR(보는 창) | S_vis | 기준 CDaR | 기준 S_vis | 개선 | 연 회전 | 시험 창 Calmar |"); a("|---|---|---|---|---|---|---|---|---|")
  setorder(T, engine, variant)
  for (i in seq_len(nrow(T))) with(T[i], a("| ", ENGN[engine], " | ", KN[variant], " | ", pct(cdar), " | ", sprintf("%.3f", S_vis), " | ", pct(cdar0), " | ", sprintf("%.3f", S0), " | ",
    if (variant == "K0") "—" else if (isTRUE(improve)) "**개선**" else "—", " | ", rt(turnover), " | ", rt(test_calmar), " |"))
  sel <- ev$selected
  a(""); a("- 판정: ", if (identical(ev$verdict, "construction_lever")) "구성 레버 있음(두 엔진 모두 개선한 변형)" else "이 엔진들에선 EW 를 넘는 구성 없음",
    if (!is.null(sel)) paste0(" · 선택 = ", KN[sel$variant]) else "")
  items <- vapply(seq_len(nrow(T[variant != "K0"])), function(i) with(T[variant != "K0"][i], sprintf("%s · %s — CDaR %s(기준 %s) · S %s(기준 %s)%s", ENGN[engine], KN[variant],
    pct(cdar), pct(cdar0), sprintf("%.2f", S_vis), sprintf("%.2f", S0), if (isTRUE(improve)) " · 개선" else "")), character(1))
  verdict_line <- if (!is.null(sel)) sprintf("구성 레버 있음 — %s 가 두 엔진 모두에서 CDaR 를 낮추며 종합점수 유지", KN[sel$variant]) else "구성만 바꿔서는 두 엔진 모두에서 낙폭과 종합점수를 함께 개선하지 못했다(EW 유지)"
  next_step <- if (!is.null(sel)) "선택 구성은 P4 조립 후보" else "P4 는 EW 구성으로"
  results <- list(verdict = ev$verdict, selected = sel$variant %||% NULL)
  reason <- sprintf("P3R01 완료 — %s", ev$verdict)
}
REP <- file.path(SA, "ROUND_REPORT.md"); writeLines(enc2utf8(L), REP, useBytes = TRUE); cat("보고서:", REP, "\n")
if (RECORD) {
  rr <- Filter(function(r) identical(r$round_id, C$round), pr_get(pr_load(ROOT), C$program)$rounds)[[1]]
  pr_record_round(C$program, list(round_id = C$round, prereg = rr$prereg, prereg_md5 = rr$prereg_md5, status = "complete",
                                  results = results, report = sub(paste0("^", ROOT, "/"), "", REP)), root = ROOT)
  pr_set_status(C$program, status_after, reason = reason, root = ROOT)
}
if (SEND || !RECORD) {
  if (!SEND) Sys.setenv(QVEST_TG_DRY_RUN = "1")
  res <- prep_send(program = C$pname, target = C$target,
                   status = list(stage = sprintf("%s — %s", C$pname, C$round), position = "라운드 종료 · 보고",
                                 previous = "P0 실현 가능성 지도 측정 공유(새 측정 축 · 보는 창 판정)"),
                   verdict_line = verdict_line, next_step = next_step, artifact = REP, push = TRUE,
                   extra = list(list(heading = "판정 표(보는 창)", type = "bullet", items = items)), root = ROOT)
  cat("prep_send ok =", isTRUE(res$ok), "\n")
}
