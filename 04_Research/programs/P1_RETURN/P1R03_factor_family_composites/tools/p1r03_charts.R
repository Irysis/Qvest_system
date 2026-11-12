## P1R03 결과 보고 차트 묶음 — 팩터 카테고리 합성 엔진 14 + 토탈 1(표준 구성 롱온리 25종 EW · 15bps · 유동성 2e8)
##   실행: 저장소 루트에서 Rscript 04_Research/programs/P1_RETURN/P1R03_factor_family_composites/tools/p1r03_charts.R
##   출력: report/charts/*.png · 마지막 표준 출력 줄 = JSON 배열 [{"file","caption"}] (prep_send charts 인자용)
##
##   수치 출처(AX-008 — 판정 · 등급에 닿는 값은 다시 계산하지 않는다):
##     · 판정 표(β-통제 알파 t · 상승 포착률 · 자격) = results/verdict.json::table (round_core v3 rc_p1_evaluate)
##     · 문턱 = 등록본 stage_artifacts/programs/.../prereg.json::rules_resolved (해석된 값)
##     · 위기별 하락노출(dd_capture) · 강세 국면별 상승 포착률 = results/<칸>/full/behavior_card.json (행동 카드 · LT 20/20)
##     · IS 위기 하락노출 중앙값 = results/<칸>/eval.json::visible.dd_capture_median(보고 정본 지표 '하락노출' = 위기 구간 전략 낙폭 ÷ 시장 낙폭)
##       ★누적수익 비(cum_capture · visible.dc)는 '하락노출'이 아니다 — 이 묶음은 그리지 않는다
##     · IS 시작 · 위기 수 = results/<칸>/eval.json::visible.window · n_crisis · 등급 = results/<칸>.json::grade (authoritative_remeasure)
##     · NAV · 연도별 초과수익 · 수익 상관 = 산출물 02_nav · 03_period_returns · 05_benchmark_returns 로 그린 기술 통계(판정 아님)
##     · 원천 이음매 표식 = 06_Registry/basis_break_registry.json::scope.source_transition_seams 중 그 칸 전기간 최대 |일 순수익| 날
##       (표식만 단다 — 값은 고치거나 다시 계산하지 않는다 · 재측정은 데이터 쪽 과제)
##   쓰는 곳은 report/charts/ 뿐이다(다른 파일 수정 · 발송 · 커밋 없음).
suppressPackageStartupMessages({ library(data.table); library(jsonlite); library(ggplot2) })
for (p in c("ragg", "systemfonts", "ggrepel", "scales")) if (!requireNamespace(p, quietly = TRUE)) stop("[p1r03_charts] 패키지 없음: ", p)

ROOT <- sub("/+$", "", gsub("\\\\", "/", Sys.getenv("QM_ROOT", getwd())))   # 경로 정규화 함수 금지(한글 경로) — 슬래시 치환만
if (!file.exists(file.path(ROOT, "CLAUDE.md"))) ROOT <- gsub("\\\\", "/", getwd())
RID <- "P1R03_factor_family_composites"
RD  <- file.path(ROOT, "04_Research/programs/P1_RETURN", RID)
RES <- Sys.getenv("P1R03_CHARTS_RES", file.path(RD, "results"))   # 시험용 덮어쓰기(기본 = 라운드 results)
OUT <- Sys.getenv("P1R03_CHARTS_OUT", file.path(RD, "report/charts"))
PRE <- file.path(ROOT, "stage_artifacts/programs/P1_RETURN", RID, "prereg.json")
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)

## ---- 표시 이름(카테고리) · 저위험 계열 --------------------------------------------------------------
CAT <- c(FACCR = "발생액", FCONS = "컨센서스", FCROW = "쏠림", FDEFE = "방어", FGROW = "성장",
         FINVE = "수급", FLEVE = "레버리지", FLIQU = "유동성", FMOME = "모멘텀", FQUAL = "퀄리티",
         FREGI = "국면", FRISK = "위험", FTECH = "기술적", FVALU = "밸류", TOTAL = "토탈")
LOWRISK <- c("FDEFE", "FRISK", "FLIQU", "FREGI")

## ---- 색 · 글꼴(현대하모니 M · prep_crisis_chart 와 같은 방식) ----------------------------------------
C_STRAT <- "#2a78d6"; C_BENCH <- "#898781"; C_PASS <- "#2a78d6"; C_FAIL <- "#e34948"; C_NA <- "#b5b3ab"
C_POS <- "#2a78d6"; C_NEG <- "#e34948"; C_MID <- "#f0efec"; C_LOW <- "#eb6834"
INK <- "#0b0b0b"; INK2 <- "#52514e"; MUTED <- "#898781"; GRID <- "#e1e0d9"; TEST_FILL <- "#eceae3"
FAM <- ""
fdir <- c(file.path(Sys.getenv("LOCALAPPDATA"), "Microsoft", "Windows", "Fonts"), file.path(Sys.getenv("WINDIR", "C:/Windows"), "Fonts"))
fM <- file.path(fdir, "현대하모니+M.ttf"); fM <- fM[file.exists(fM)][1]
if (!is.na(fM)) { try(systemfonts::register_font(name = "HDHM", plain = fM), silent = TRUE); FAM <- "HDHM" }

th <- function(base = 12) {
  theme_minimal(base_family = FAM, base_size = base) +
    theme(plot.title = element_text(size = base + 4, colour = INK), plot.title.position = "plot",
          plot.subtitle = element_text(size = base - 1.5, colour = INK2, lineheight = 1.15),
          plot.caption = element_text(size = base - 4, colour = MUTED, hjust = 0, lineheight = 1.1), plot.caption.position = "plot",
          panel.grid.minor = element_blank(), panel.grid.major = element_line(colour = GRID, linewidth = 0.3),
          axis.text = element_text(colour = INK2), legend.position = "top", legend.justification = "left",
          legend.title = element_blank(), plot.background = element_rect(fill = "white", colour = NA),
          plot.margin = margin(10, 14, 8, 10))
}
save_png <- function(g, name, h, w = 7.2) {
  p <- file.path(OUT, name)
  ggsave(p, g, width = w, height = h, dpi = 150, device = ragg::agg_png, bg = "white")
  p
}
pct <- function(x, d = 0) ifelse(is.finite(x), sprintf(paste0("%.", d, "f%%"), 100 * x), "–")
f2 <- function(x, d = 2) ifelse(is.finite(x), sub("^-(0[.]?0*)$", "\\1", formatC(x, format = "f", digits = d)), "–")   # -0.00 → 0.00
num <- function(x) { v <- suppressWarnings(as.numeric(x)); if (length(v) == 1L) v else NA_real_ }
`%||%` <- function(a, b) if (is.null(a)) b else a
rj <- function(p) tryCatch(fromJSON(p, simplifyVector = FALSE), error = function(e) NULL)

## ---- 등록본: τ_D · 문턱 · 칸 목록 -----------------------------------------------------------------
pre <- rj(PRE); if (is.null(pre)) stop("[p1r03_charts] 등록본 없음: ", PRE)
TAU <- as.Date(pre$spec$tau_d)
find_rule <- function(rules, id) {
  for (r in rules) { if (identical(r$id, id)) return(r); if (!is.null(r$of)) { k <- find_rule(r$of, id); if (!is.null(k)) return(k) } }
  NULL
}
r_t  <- find_rule(pre$rules_resolved, "q_t_alpha"); r_uc <- find_rule(pre$rules_resolved, "q_uc")
TH_T <- num(r_t$value); TH_UC <- num(r_uc$value)
if (!is.finite(TH_T) || !is.finite(TH_UC)) stop("[p1r03_charts] 등록본 문턱 해석 실패")
RULE_LINE <- sprintf("자격 규칙(사전등록) = IS β-통제 알파 t ≥ %s ∧ IS 상승 포착률 ≥ %s", f2(TH_T, 1), f2(TH_UC, 2))
CODES <- vapply(pre$spec$cells, function(c) c$code, character(1))
ENG <- sub("^P1R03_(.*)_C0$", "\\1", CODES)
TEST_LAB <- sprintf("OOS(%s~ · 보고 전용)", format(TAU + 1, "%Y"))
VIS_FACET  <- sprintf("IS\n~%s", format(TAU, "%Y-%m"))
TEST_FACET <- sprintf("OOS\n%s~\n보고 전용", format(TAU + 1, "%Y"))
STR_FACET  <- sprintf("경계 걸침\n%s\n보고 전용", format(TAU))
FACET_TAIL <- sprintf("\n아래 면 = %s · IS/OOS 경계 %s", TEST_LAB, format(TAU))
mm <- function(s) gsub("-", "−", s, fixed = TRUE)                                   # 표시용 빼기 기호
s2 <- function(x, d = 2) mm(sub("^(-?)0\\.", "\\1.", f2(x, d)))                     # 앞자리 0 떼기: 0.84 → .84 · -0.04 → −.04

## ---- 칸 측정 결과 · 평가 · 행동 카드 ---------------------------------------------------------------
cells <- rbindlist(lapply(seq_along(CODES), function(i) {
  r <- rj(file.path(RES, paste0(CODES[i], ".json")))
  ev <- rj(file.path(RES, CODES[i], "eval.json"))
  data.table(code = CODES[i], engine = ENG[i], cat = CAT[[ENG[i]]],
             ok = isTRUE(r$ok), artifacts = if (isTRUE(r$ok)) gsub("\\\\", "/", r$artifacts) else NA_character_,
             grade = if (isTRUE(r$ok)) as.character(r$grade %||% NA) else NA_character_,
             evaluated = identical(ev$status, "evaluated"),
             dd_vis = num(ev$visible$dd_capture_median), uc_vis_ev = num(ev$visible$uc),
             vis_start = if (length(ev$visible$window)) as.character(ev$visible$window[[1]]) else NA_character_,
             n_crisis_vis = num(ev$visible$n_crisis))
}))
## IS 시작(첫 수익일 달) · 위기 수 — 엔진마다 다르다(사전등록 S-6: 칸 사이 비교는 겹치는 창으로만)
cells[, vis_ym := ifelse(is.na(vis_start), NA_character_, format(as.Date(vis_start), "%Y-%m"))]
win_note <- function() {
  w <- cells[!is.na(vis_ym)]
  if (!nrow(w)) return("")
  w[, key := paste0(vis_ym, "~", ifelse(is.finite(n_crisis_vis), sprintf("(위기 %d)", as.integer(n_crisis_vis)), ""))]
  tb <- w[, .(cats = paste(cat, collapse = " · "), n = .N), by = key][order(-n)]
  if (nrow(tb) == 1L) return(sprintf("IS 시작 = 전 칸 %s", tb$key))
  grp <- c(sprintf("%s = %s", tb$cats[-1], tb$key[-1]), sprintf("그 밖 = %s", tb$key[1]))
  ln <- split(grp, ceiling(seq_along(grp) / 2))
  paste0("엔진마다 실효 시작이 다르다 — 정렬은 엔진별 판정값이지 같은 창 비교가 아니다(사전등록 S-6)\nIS 시작: ",
         paste(vapply(ln, paste, character(1), collapse = " / "), collapse = " /\n"))
}
## 위기 사건명 두 줄 나누기(가운데에 가장 가까운 빈칸에서)
wrap2 <- function(s, min_chars = 10L) {
  if (!nzchar(s) || nchar(s) <= min_chars) return(s)
  sp <- gregexpr(" ", s, fixed = TRUE)[[1]]
  if (sp[1] < 0) return(s)
  cut <- sp[which.min(abs(sp - nchar(s) / 2))]
  paste0(substr(s, 1, cut - 1), "\n", substr(s, cut + 1, nchar(s)))
}
WIN_NOTE <- win_note()
cells[, artifacts := ifelse(ok & !is.na(artifacts) & dir.exists(artifacts), artifacts, NA_character_)]

VER_P <- file.path(RES, "verdict.json")
V <- if (file.exists(VER_P)) tryCatch(fromJSON(VER_P, simplifyVector = TRUE), error = function(e) NULL) else NULL
VT <- if (!is.null(V) && NROW(V$table)) as.data.table(V$table) else NULL
if (!is.null(VT)) {
  keep <- intersect(c("code", "status", "t_alpha_vis", "alpha_ann_vis", "beta_vis", "port_t_vis", "n_vis", "uc_vis", "cagr_vis",
                      "t_alpha_test", "alpha_ann_test", "n_test", "uc_test", "qualify"), names(VT))
  cells <- merge(cells, VT[, ..keep], by = "code", all.x = TRUE, sort = FALSE)
}
for (k in c("t_alpha_vis", "alpha_ann_vis", "beta_vis", "uc_vis", "cagr_vis", "t_alpha_test", "alpha_ann_test", "uc_test"))
  if (!k %in% names(cells)) cells[, (k) := NA_real_]
if (!"qualify" %in% names(cells)) cells[, qualify := NA]
cells[, verdict_lab := fifelse(qualify %in% TRUE, "통과", fifelse(qualify %in% FALSE, "미달", "미시험"))]
## 표시 순서 = IS β-통제 알파 t 내림차순(판정 표가 없으면 칸 순서)
ord <- if (any(is.finite(cells$t_alpha_vis))) cells[order(-t_alpha_vis, na.last = TRUE)]$engine else cells$engine
cells[, cat_f := factor(cat, levels = CAT[ord])]
cells[, low := engine %in% LOWRISK]
N_OK <- sum(cells$ok); N_ALL <- nrow(cells); FULL <- !is.null(VT) && N_OK == N_ALL
cat(sprintf("[p1r03_charts] 측정 %d/%d · 판정 파일 %s\n", N_OK, N_ALL, if (is.null(VT)) "없음" else "있음"), file = stderr())

made <- list(); skipped <- list()
add <- function(file, caption) made[[length(made) + 1L]] <<- list(file = file, caption = caption)
skip <- function(name, why) { skipped[[length(skipped) + 1L]] <<- list(chart = name, reason = why); cat(sprintf("[건너뜀] %s — %s\n", name, why), file = stderr()) }
partial_note <- if (FULL) "" else sprintf(" · 측정 %d/%d칸(중간 판)", N_OK, N_ALL)

## ---- 수익 계열(산출물) -------------------------------------------------------------------------
read_series <- function(dir) {
  nv <- fread(file.path(dir, "02_nav.csv"), select = c("date", "nav_net", "drawdown_net"))
  pr <- fread(file.path(dir, "03_period_returns.csv"), select = c("date", "ret_net"))
  br <- fread(file.path(dir, "05_benchmark_returns.csv"), select = c("date", "benchmark_ret", "benchmark_nav"))
  x <- merge(merge(nv, pr, by = "date"), br, by = "date"); x[, date := as.Date(date)]; x[order(date)]
}
S <- rbindlist(lapply(which(!is.na(cells$artifacts)), function(i) {
  x <- tryCatch(read_series(cells$artifacts[i]), error = function(e) NULL)
  if (is.null(x)) return(NULL)
  x[, `:=`(engine = cells$engine[i], cat = cells$cat[i])]
}))
DATA_END <- if (nrow(S)) max(S$date) else NA

## ---- 원천 이음매(수정주가 기준 단절) 표식 — 값은 고치지 않는다(AX-008) ---------------------------------
##   이음매 = basis_break_registry.json 의 원천 전환 경계 · 영향 칸 = 그 날이 그 칸 전기간 최대 |일 순수익| 날
BBR <- rj(file.path(ROOT, "06_Registry/basis_break_registry.json"))
SEAMS <- if (is.null(BBR)) as.Date(character()) else as.Date(unlist(BBR$scope$source_transition_seams))
SEAM_HIT <- character(); SEAM_DAY <- as.Date(NA)
if (nrow(S) && length(SEAMS)) {
  mx <- S[, .(dmax = date[which.max(abs(ret_net))]), by = engine]
  hit <- mx[dmax %in% SEAMS]
  if (nrow(hit)) { SEAM_HIT <- hit$engine; SEAM_DAY <- min(hit$dmax) }
}
SEAM_ON <- length(SEAM_HIT) > 0
SEAM_CATS <- paste(CAT[SEAM_HIT], collapse = " · ")
SEAM_NOTE <- if (SEAM_ON) sprintf("‡ = %s 원천 이음매(수정주가 기준 단절) 결함이 실린 엔진(%s)\n   → OOS 값 · 전기간 값은 재측정 전 인용 보류 · IS(≤ %s) 자격 판정에는 영향 없음",
                                  format(SEAM_DAY), SEAM_CATS, format(TAU)) else ""
seam_lab <- function(e, x) ifelse(e %in% SEAM_HIT, paste0(x, " ‡"), x)
cat_lab <- function(e) seam_lab(e, CAT[e])                                      # 축 라벨: 영향 칸에 ‡
cap_add <- function(cap) if (SEAM_ON) paste0(cap, "\n", SEAM_NOTE) else cap
if (SEAM_ON) cat(sprintf("[p1r03_charts] 이음매 %s 영향 칸: %s\n", format(SEAM_DAY), SEAM_CATS), file = stderr())

## =============================================================================================
## 1. 자격 지도 — x = IS 상승 포착률 · y = IS β-통제 알파 t
## =============================================================================================
D1 <- cells[is.finite(t_alpha_vis) & is.finite(uc_vis)]
if (nrow(D1)) {
  D1[, vf := factor(verdict_lab, levels = c("통과", "미달", "미시험"))]
  xr <- range(c(D1$uc_vis, TH_UC)); yr <- range(c(D1$t_alpha_vis, TH_T, 0))
  xp <- diff(xr) * 0.12; yp <- diff(yr) * 0.12
  g <- ggplot(D1, aes(uc_vis, t_alpha_vis)) +
    annotate("rect", xmin = TH_UC, xmax = Inf, ymin = TH_T, ymax = Inf, fill = C_PASS, alpha = 0.07) +
    annotate("text", x = Inf, y = Inf, label = "자격 영역", hjust = 1.1, vjust = 1.6, family = FAM, size = 3.6, colour = C_PASS) +
    geom_hline(yintercept = TH_T, linetype = "dashed", colour = INK2, linewidth = 0.45) +
    geom_vline(xintercept = TH_UC, linetype = "dashed", colour = INK2, linewidth = 0.45) +
    geom_hline(yintercept = 0, colour = "#c3c2b7", linewidth = 0.4) +
    annotate("text", x = xr[1] - xp * 0.9, y = TH_T, label = sprintf("t = %s", f2(TH_T, 1)), vjust = -0.5, hjust = 0, family = FAM, size = 3.2, colour = INK2) +
    annotate("text", x = TH_UC, y = yr[1] - yp * 0.9, label = sprintf("상승 포착률 = %s", f2(TH_UC, 2)), hjust = -0.05, family = FAM, size = 3.2, colour = INK2) +
    geom_point(aes(colour = vf, shape = low), size = 3.6, stroke = 1.1) +
    ggrepel::geom_text_repel(aes(label = cat), family = FAM, size = 3.9, colour = INK, seed = 7, box.padding = 0.45,
                             point.padding = 0.3, min.segment.length = 0.2, segment.colour = MUTED, max.overlaps = 50) +
    scale_colour_manual(values = c("통과" = C_PASS, "미달" = C_FAIL, "미시험" = C_NA), drop = TRUE) +
    scale_shape_manual(values = c(`FALSE` = 16, `TRUE` = 17), labels = c(`FALSE` = "기타 카테고리", `TRUE` = "저위험 계열(방어 · 위험 · 유동성 · 국면)")) +
    scale_x_continuous(limits = c(xr[1] - xp, xr[2] + xp), labels = function(x) f2(x, 2)) +
    scale_y_continuous(limits = c(yr[1] - yp, yr[2] + yp)) +
    guides(colour = guide_legend(order = 1), shape = guide_legend(order = 2, nrow = 1)) +
    labs(title = "P1 자격 지도 — 카테고리 합성 엔진 15",
         subtitle = paste0(RULE_LINE, "\nIS = 실효 시작 ~ ", format(TAU), " · 통과 ", sum(D1$verdict_lab == "통과"), " / ", nrow(D1), partial_note),
         x = "IS 상승 포착률(강세 국면 중앙값 · KOSPI200 대비)", y = "IS β-통제 알파 t(NW)",
         caption = "출처: results/verdict.json(round_core v3 판정 표) · 문턱 = 등록본 prereg.json rules_resolved\n표준 구성 = 롱온리 25종 동일가중 · 월말 신호 · 15bps · 20일 평균 거래대금 ≥ 2억 원 · 전 종목 위생 유니버스") +
    th() + theme(legend.box = "vertical", legend.spacing.y = unit(2, "pt"))
  add(save_png(g, "01_qualification_map.png", 7.0),
      sprintf("자격 지도 — IS 상승 포착률 × β-통제 알파 t · 문턱 t ≥ %s · 상승 포착률 ≥ %s · 통과 %d/%d", f2(TH_T, 1), f2(TH_UC, 2), sum(D1$verdict_lab == "통과"), nrow(D1)))
} else skip("01_qualification_map", "판정 표(results/verdict.json) 없음 — 평가 전")

## =============================================================================================
## 2. 누적 수익 vs KOSPI200 — 15 엔진 작은 그림(로그 축 · OOS 음영)
## =============================================================================================
if (nrow(S)) {
  ## 계약 NAV 를 그대로 쓴다 — nav_net · benchmark_nav 는 둘 다 첫 체결일 종가 = 1 기준(첫 수익일 수익이 첫 행에 이미 들어 있다)
  N <- S[, .(engine, cat, date, st = nav_net, bm = benchmark_nav)]
  ## 선을 1x 에서 시작: 엔진마다 첫 수익일 앞 거래일(전 칸 수익일 달력 · 없으면 하루 전)에 v = 1 행을 앞에 붙인다
  cal <- sort(unique(S$date))
  B0 <- N[, .(d1 = min(date)), by = .(engine, cat)]
  B0[, ix := findInterval(as.numeric(d1) - 1, as.numeric(cal))]
  B0[, date := fifelse(ix >= 1L, cal[pmax(ix, 1L)], d1 - 1L)]
  N <- rbind(B0[, .(engine, cat, date, st = 1, bm = 1)], N)[order(engine, date)]
  ## 단정: 패널 끝값 = 산출물 02_nav.csv 마지막 nav_net · 05_benchmark_returns.csv 마지막 benchmark_nav
  for (i in which(!is.na(cells$artifacts))) {
    e <- cells$engine[i]; if (!e %in% N$engine) next
    nv_last <- tail(fread(file.path(cells$artifacts[i], "02_nav.csv"), select = "nav_net")$nav_net, 1)
    bm_last <- tail(fread(file.path(cells$artifacts[i], "05_benchmark_returns.csv"), select = "benchmark_nav")$benchmark_nav, 1)
    z <- N[engine == e][.N]
    if (!isTRUE(all.equal(z$st, nv_last, tolerance = 1e-12)) || !isTRUE(all.equal(z$bm, bm_last, tolerance = 1e-12)))
      stop(sprintf("[p1r03_charts] 02 끝값 불일치 %s: 엔진 %.6f vs nav_net %.6f · 시장 %.6f vs benchmark_nav %.6f", e, z$st, nv_last, z$bm, bm_last))
  }
  L <- rbind(N[, .(engine, cat, date, who = "엔진(순수익)", v = st)], N[, .(engine, cat, date, who = "KOSPI200", v = bm)])
  lab_of <- cells[, setNames(sprintf("%s%s", seam_lab(engine, cat), fifelse(verdict_lab == "통과", " · 통과", fifelse(verdict_lab == "미달", " · 미달", ""))), engine)]
  lv <- intersect(ord, unique(L$engine))
  L[, panel := factor(lab_of[engine], levels = lab_of[lv])]
  endv <- N[, .SD[.N], by = engine][, .(engine, st, bm)]
  mult <- function(x) ifelse(x < 1, formatC(x, format = "f", digits = 2), formatC(x, format = "f", digits = 1))
  lab_of[endv$engine] <- sprintf("%s\n%sx · 시장 %sx", lab_of[endv$engine], mult(endv$st), mult(endv$bm))
  L[, panel := factor(lab_of[engine], levels = lab_of[lv])]
  tag <- data.table(panel = factor(lab_of[lv[1]], levels = lab_of[lv]), x = TAU + 30, lab = sub("보고 전용", "보고\n전용", TEST_FACET, fixed = TRUE))
  g <- ggplot(L, aes(date, v)) +
    annotate("rect", xmin = TAU, xmax = DATA_END, ymin = 0, ymax = Inf, fill = TEST_FILL) +
    geom_vline(xintercept = TAU, colour = MUTED, linewidth = 0.3, linetype = "dashed") +
    geom_hline(yintercept = 1, colour = "#c3c2b7", linewidth = 0.25) +
    geom_line(aes(colour = who), linewidth = 0.5) +
    geom_text(data = tag, aes(x = x, y = 0, label = lab), inherit.aes = FALSE, hjust = 0, vjust = -0.15, size = 2.4, family = FAM, colour = INK2, lineheight = 0.9) +
    facet_wrap(~panel, ncol = 3) +
    scale_y_log10(breaks = 10^(-3:4), labels = function(x) paste0(trimws(formatC(x, format = "fg", digits = 3, big.mark = ",")), "x")) +
    scale_x_date(breaks = as.Date(c("2000-01-01", "2010-01-01", "2020-01-01")), date_labels = "%Y") +
    scale_colour_manual(values = c("엔진(순수익)" = C_STRAT, "KOSPI200" = C_BENCH), breaks = c("엔진(순수익)", "KOSPI200")) +
    labs(title = "누적 수익 — 엔진(15bps 순) vs KOSPI200",
         subtitle = sprintf("로그 축 · 1x = 각 엔진 첫 체결일 종가(실효 시작 신호 다음 거래일) · 패널 순서 = IS β-통제 알파 t 내림차순\n패널 제목 아래 = 마지막 날 누적 배수(엔진 · 같은 기간 KOSPI200 = 산출물 NAV 끝값)\n음영 = %s · 점선 = IS/OOS 경계 %s · 자료 끝 %s%s",
                            TEST_LAB, format(TAU), format(DATA_END), partial_note),
         x = NULL, y = "누적 가치(로그)",
         caption = cap_add(paste0("출처: 산출물 02_nav.csv(nav_net) · 05_benchmark_returns.csv(benchmark_nav) — 정규화 없이 그대로 · 기술 통계 · 판정 아님",
                                  if (SEAM_ON) sprintf("\n‡ 패널의 %s 계단과 끝 배수에는 이음매 하루가 들어 있다", format(SEAM_DAY, "%Y-%m")) else ""))) +
    th(11) + theme(strip.text = element_text(size = 10, colour = INK, hjust = 0, lineheight = 1.05), panel.spacing = unit(8, "pt"),
                   axis.text = element_text(size = 8))
  add(save_png(g, "02_cumulative_vs_kospi200.png", 10.6),
      paste0(sprintf("누적 수익 vs KOSPI200 — %d칸 작은 그림 · 로그 축 · 1x = 첫 체결일 종가 · 음영 = %s", length(lv), TEST_LAB),
             if (SEAM_ON) sprintf(" · ‡ %s = %s 원천 이음매 결함 — OOS · 끝 배수 재측정 전 인용 보류(IS 판정 영향 없음)", SEAM_CATS, format(SEAM_DAY)) else ""))
} else skip("02_cumulative_vs_kospi200", "측정 끝난 칸이 없다")

## =============================================================================================
## 3. 알파 t 정렬 — IS β-통제 알파 t(막대) · OOS 알파 t(속 빈 점 · 보고 전용)
## =============================================================================================
D3 <- cells[is.finite(t_alpha_vis)]
if (nrow(D3)) {
  D3[, catr := factor(cat, levels = rev(CAT[ord]))]
  D3[, vf := factor(verdict_lab, levels = c("통과", "미달", "미시험"))]
  ## 값 라벨은 막대 끝과 OOS 점 중 바깥쪽에 둔다(점이 숫자를 덮지 않게)
  ## 점이 막대 끝 바깥이면 점 반지름만큼 더 띄운다
  D3[, beyond := is.finite(t_alpha_test) & ifelse(t_alpha_vis >= 0, t_alpha_test > t_alpha_vis, t_alpha_test < t_alpha_vis)]
  D3[, lab_x := ifelse(t_alpha_vis >= 0, pmax(t_alpha_vis, t_alpha_test, na.rm = TRUE) + ifelse(beyond, 0.3, 0.15),
                                         pmin(t_alpha_vis, t_alpha_test, na.rm = TRUE) - ifelse(beyond, 0.3, 0.15))]
  lo <- min(0, D3$t_alpha_vis, D3$t_alpha_test, na.rm = TRUE); hi <- max(TH_T, D3$t_alpha_vis, D3$t_alpha_test, na.rm = TRUE)
  g <- ggplot(D3, aes(y = catr)) +
    geom_col(aes(x = t_alpha_vis, fill = vf), width = 0.62) +
    geom_point(data = D3[is.finite(t_alpha_test)], aes(x = t_alpha_test, shape = "OOS 알파 t(보고 전용)"), size = 3, stroke = 1, colour = INK, fill = "white") +
    geom_text(aes(x = lab_x, label = mm(f2(t_alpha_vis, 2)), hjust = ifelse(t_alpha_vis >= 0, 0, 1)), family = FAM, size = 3.3, colour = INK) +
    scale_y_discrete(labels = function(x) { e <- names(CAT)[match(x, CAT)]; cat_lab(e) }) +
    geom_vline(xintercept = 0, colour = "#c3c2b7", linewidth = 0.4) +
    geom_vline(xintercept = TH_T, linetype = "dashed", colour = INK2, linewidth = 0.5) +
    annotate("text", x = TH_T, y = Inf, label = sprintf("문턱 t = %s", f2(TH_T, 1)), vjust = -0.4, hjust = -0.05, family = FAM, size = 3.2, colour = INK2) +
    scale_fill_manual(values = c("통과" = C_PASS, "미달" = C_FAIL, "미시험" = C_NA), drop = TRUE, name = NULL) +
    scale_shape_manual(values = c("OOS 알파 t(보고 전용)" = 21), name = NULL) +
    scale_x_continuous(limits = c(lo - 0.6, hi + 0.8)) +
    coord_cartesian(clip = "off") +
    labs(title = "β-통제 알파 t 정렬 — IS",
         subtitle = paste0("막대 = IS(실효 시작 ~ ", format(TAU), ") β-통제 알파 t · 색 = 자격 판정(알파 t ∧ 상승 포착률)\n",
                           "속 빈 점 = ", TEST_LAB, " 알파 t — 판정에 쓰지 않는다", partial_note,
                           if (nzchar(WIN_NOTE)) paste0("\n", WIN_NOTE) else ""),
         x = "β-통제 알파 t(NW)", y = NULL,
         caption = cap_add("출처: results/verdict.json(t_alpha_vis · t_alpha_test · qualify) · 문턱 = 등록본 prereg.json\nIS 시작 · 위기 수 = results/<칸>/eval.json::visible(window · n_crisis)")) +
    th() + theme(panel.grid.major.y = element_blank(), axis.text.y = element_text(size = 11.5, colour = INK),
                 legend.box = "horizontal", plot.margin = margin(14, 14, 8, 10))
  add(save_png(g, "03_alpha_t_rank.png", 3.0 + 0.36 * nrow(D3)),
      paste0(sprintf("β-통제 알파 t 정렬 — IS 막대(문턱 %s) · 속 빈 점 = %s · 엔진마다 실효 시작이 달라 같은 창 비교 아님(S-6)", f2(TH_T, 1), TEST_LAB),
             if (SEAM_ON) sprintf(" · ‡ %s OOS 알파 t = 이음매 결함 · 인용 보류", SEAM_CATS) else ""))
} else skip("03_alpha_t_rank", "판정 표(results/verdict.json) 없음 — 평가 전")

## ---- 행동 카드(위기 · 강세 국면) ----------------------------------------------------------------
ev_names <- function(peaks) {
  reg <- rj(file.path(ROOT, "06_Registry/crisis_event_names.json")); out <- rep("", length(peaks))
  if (is.null(reg) || !length(reg$events)) return(out)
  tol <- as.integer(reg$match$tolerance_months %||% 2L)
  mon <- function(d) { d <- as.Date(d); as.integer(format(d, "%Y")) * 12L + as.integer(format(d, "%m")) }
  em <- vapply(reg$events, function(e) mon(paste0(e$peak, "-01")), integer(1)); en <- vapply(reg$events, function(e) as.character(e$name), character(1))
  for (i in seq_along(peaks)) { gp <- abs(em - mon(peaks[i])); if (length(gp) && min(gp) <= tol) out[i] <- en[which.min(gp)] }
  out
}
cards <- lapply(setNames(cells$code, cells$engine), function(k) rj(file.path(RES, k, "full", "behavior_card.json")))
CR <- rbindlist(lapply(names(cards), function(e) {
  b <- cards[[e]]; if (is.null(b) || !length(b$crises)) return(NULL)
  rbindlist(lapply(b$crises, function(c) data.table(engine = e, peak = as.character(c$peak_date), trough = as.character(c$trough_date),
                                                    win = as.character(c$window), ongoing = isTRUE(c$ongoing),
                                                    cum_capture = num(c$cum_capture), dd_capture = num(c$dd_capture), bm_dd = num(c$bm_dd))))
}), fill = TRUE)
EXCL <- rbindlist(lapply(names(cards), function(e) {
  b <- cards[[e]]; if (is.null(b) || !length(b$excluded)) return(NULL)
  rbindlist(lapply(b$excluded, function(x) data.table(engine = e, peak = as.character(x$peak), reason = as.character(x$reason %||% NA))))
}), fill = TRUE)
BU <- rbindlist(lapply(names(cards), function(e) {
  b <- cards[[e]]; if (is.null(b) || !length(b$bull_phases)) return(NULL)
  rbindlist(lapply(b$bull_phases, function(p) data.table(engine = e, start = as.character(p$start_ym), end = as.character(p$end_ym),
                                                         win = as.character(p$window), up_capture = num(p$up_capture), bm_cum = num(p$bm_cum))))
}), fill = TRUE)

heat_theme <- function() th(11) + theme(panel.grid = element_blank(), panel.grid.major = element_blank(), axis.text.x = element_text(angle = 50, hjust = 1, vjust = 1, size = 10, colour = INK),
                                        axis.text.y = element_text(size = 9.5, colour = INK, lineheight = 0.95), legend.position = "top",
                                        strip.text.y = element_text(angle = 0, size = 9.5, colour = INK, hjust = 0), strip.placement = "outside",
                                        legend.key.width = unit(26, "pt"), legend.key.height = unit(8, "pt"))
cap_fill <- function(lo_good, lab) scale_fill_gradient2(low = if (lo_good) C_POS else C_NEG, mid = C_MID, high = if (lo_good) C_NEG else C_POS,
                                                         midpoint = 1, limits = c(0, 2), oob = scales::squish, name = lab,
                                                         breaks = c(0, 0.5, 1, 1.5, 2), labels = c("≤0", "0.5", "1", "1.5", "≥2"))
BLANK <- "#f5f4ef"
## 엔진 × 행 격자의 빈칸(실효 시작 전 등) — 연회색 타일 + '–'
blank_cells <- function(D, rowkey) {
  full <- CJ(engine = unique(D$engine), r = unique(D[[rowkey]]))
  setnames(full, "r", rowkey)
  b <- full[!D, on = c("engine", rowkey)]
  b
}

## =============================================================================================
## 4. 위기 구간 하락노출 — 위기(행) × 엔진(열) · 행동 카드 crises[].dd_capture(보고 정본 지표 '하락노출')
## =============================================================================================
if (nrow(CR)) {
  D4 <- copy(CR)
  key <- unique(D4[, .(peak, trough, win, ongoing)])[order(as.Date(peak))][!duplicated(peak)]
  key[, nm := ev_names(peak)]
  key[, nm2 := vapply(nm, wrap2, character(1))]
  key[, lab := paste0(format(as.Date(peak), "%y.%m"), "~", format(as.Date(trough), "%y.%m"), ifelse(ongoing, " 진행 중", ""), ifelse(nzchar(nm2), paste0("\n", nm2), ""))]
  key[, wf := factor(fcase(win == "visible", VIS_FACET, win == "straddle", STR_FACET, default = TEST_FACET), levels = c(VIS_FACET, STR_FACET, TEST_FACET))]
  key[, seam := SEAM_ON & as.Date(peak) < SEAM_DAY & SEAM_DAY <= as.Date(trough)]
  lev_r <- rev(key$lab); lev_c <- CAT[ord]
  D4 <- merge(D4, key[, .(peak, lab, wf, seam)], by = "peak")
  D4[, `:=`(catf = factor(CAT[engine], levels = lev_c), labf = factor(lab, levels = lev_r), txt = s2(dd_capture, 2),
            seam_cell = seam & engine %in% SEAM_HIT)]
  B4 <- merge(blank_cells(D4, "peak"), key[, .(peak, lab, wf)], by = "peak")
  B4[, `:=`(catf = factor(CAT[engine], levels = lev_c), labf = factor(lab, levels = lev_r))]
  neg4 <- any(D4$dd_capture < 0, na.rm = TRUE)
  g <- ggplot(D4, aes(catf, labf)) +
    geom_tile(aes(fill = dd_capture), colour = "white", linewidth = 0.8) +
    geom_tile(data = B4, fill = BLANK, colour = "white", linewidth = 0.8) +
    geom_text(data = B4, label = "–", family = FAM, size = 2.8, colour = MUTED) +
    geom_tile(data = D4[seam_cell == TRUE], fill = NA, colour = INK, linewidth = 0.55, linetype = "22") +
    geom_text(aes(label = txt), family = FAM, size = 2.8, colour = INK) +
    cap_fill(TRUE, "하락노출(위기 구간 전략 낙폭 ÷ 시장 낙폭)") +
    scale_x_discrete(labels = function(x) { e <- names(CAT)[match(x, CAT)]; cat_lab(e) }) +
    facet_grid(wf ~ ., scales = "free_y", space = "free_y", switch = "y") +
    labs(title = "위기 구간 하락노출 — 엔진 × KOSPI200 위기",
         subtitle = paste0("값 = 위기 구간 엔진 낙폭 ÷ KOSPI200 낙폭 · 1.00 = 시장만큼 · 1 미만(파랑) = 시장보다 얕은 낙폭",
                           if (neg4) " · 음수 = 시장 하락 구간에 엔진 상승" else "", "\n",
                           "귀속 전 원값 — 방어 근거 아님(사전등록 결론 범위 · β · 크기 · 숨은 현금 미통제)\n",
                           "위기 = KOSPI200 Lunde-Timmermann 20/20 첫 통과 구간\n열 순서 = IS 알파 t 내림차순(엔진마다 실효 시작 다름 — 같은 창 비교 아님)",
                           FACET_TAIL, partial_note),
         x = NULL, y = NULL,
         caption = cap_add(paste0("출처: results/<칸>/full/behavior_card.json::crises[].dd_capture(행동 카드 · 계약 산출) · 사건명 = 06_Registry/crisis_event_names.json",
                                  if (nrow(B4)) "\n– = 실효 시작 전 · 시작이 위기 안이라 행동 카드에서 제외(behavior_card.json::excluded)" else "",
                                  if (any(D4$seam_cell)) " · 점선 테두리 = 이음매 하루가 든 위기 구간" else ""))) +
    heat_theme() + theme(strip.text.y.left = element_text(angle = 0, size = 9.5, colour = INK2), axis.text.y = element_text(size = 9, colour = INK, lineheight = 0.92))
  add(save_png(g, "04_crisis_capture_heatmap.png", 3.2 + 0.5 * nrow(key)),
      paste0(sprintf("위기 구간 하락노출 열지도(위기 구간 전략 낙폭 ÷ 시장 낙폭) — 엔진 × LT 20/20 위기 %d개(IS %d · %s %d) · 귀속 전 원값 · 방어 근거 아님",
                     nrow(key), sum(key$win == "visible"), TEST_LAB, sum(key$win != "visible")),
             if (any(D4$seam_cell)) sprintf(" · ‡ %s 의 %s 위기 칸 = 이음매 결함 · 인용 보류", SEAM_CATS, key[seam == TRUE]$lab[1] |> sub(pattern = "\n.*", replacement = "")) else ""))
} else skip("04_crisis_capture_heatmap", "행동 카드(results/<칸>/full/behavior_card.json) 없음 — 평가 전")

## =============================================================================================
## 5. 엔진 수익 상관 — IS 월간 순수익(왼쪽) · KOSPI200 초과수익(오른쪽 파일) · 계층 군집 순서
## =============================================================================================
if (nrow(S) && length(unique(S$engine)) >= 3) {
  M <- S[date <= TAU, .(r = prod(1 + ret_net) - 1, b = prod(1 + benchmark_ret) - 1), by = .(engine, ym = format(date, "%Y-%m"))]
  corr_chart <- function(val, name, title, sub_head, cap_what) {
    W <- dcast(M, ym ~ engine, value.var = val)
    X <- as.matrix(W[, -1]); colnames(X) <- names(W)[-1]
    C <- cor(X, use = "pairwise.complete.obs")
    hc <- hclust(as.dist(1 - C), method = "average"); oe <- colnames(C)[hc$order]
    D <- as.data.table(as.table(C)); setnames(D, c("a", "b", "rho"))
    D[, `:=`(af = factor(CAT[as.character(a)], levels = CAT[oe]), bf = factor(CAT[as.character(b)], levels = rev(CAT[oe])))]
    D[, both_low := as.character(a) %in% LOWRISK & as.character(b) %in% LOWRISK]
    D[as.character(a) == as.character(b), rho := NA_real_]
    off <- C[upper.tri(C)]
    lo_lab <- function(e) ifelse(e %in% LOWRISK, paste0(CAT[e], " *"), CAT[e])
    g <- ggplot(D, aes(af, bf, fill = rho)) +
      geom_tile(colour = "white", linewidth = 0.6) +
      geom_tile(data = D[both_low == TRUE], colour = C_LOW, linewidth = 0.9, fill = NA) +
      geom_text(aes(label = s2(rho, 2)), data = D[is.finite(rho)], family = FAM, size = 3.0, colour = INK) +
      scale_fill_gradient2(low = C_POS, mid = C_MID, high = C_NEG, midpoint = 0, limits = c(-1, 1), name = "상관계수", na.value = BLANK) +
      scale_x_discrete(labels = function(x) { e <- names(CAT)[match(x, CAT)]; lo_lab(e) }) +
      scale_y_discrete(labels = function(x) { e <- names(CAT)[match(x, CAT)]; lo_lab(e) }) +
      coord_fixed() +
      labs(title = title,
           subtitle = sprintf("%s · %s ~ %s 월간 · 계층 군집 순서(거리 = 1 − 상관 · 평균 연결)\n비대각 상관 중앙값 %s · 범위 %s ~ %s%s\n* · 주황 테두리 = 저위험 계열(방어 · 위험 · 유동성 · 국면 — 결론에서 한 원천으로 센다)",
                              sub_head, min(M$ym), format(TAU, "%Y-%m"), f2(median(off), 2), mm(f2(min(off), 2)), mm(f2(max(off), 2)), partial_note),
           x = NULL, y = NULL, caption = paste0("출처: 산출물 03_period_returns.csv(ret_net)", cap_what, " — 일별 → 월간 복리 · 기술 통계 · 판정 아님\n엔진마다 실효 시작이 달라 쌍마다 겹치는 달로만 잰다(pairwise)")) +
      th(11) + theme(panel.grid = element_blank(), panel.grid.major = element_blank(), axis.text.x = element_text(angle = 50, hjust = 1, vjust = 1, size = 10, colour = INK),
                     axis.text.y = element_text(size = 10, colour = INK), legend.key.width = unit(26, "pt"), legend.key.height = unit(8, "pt"),
                     plot.subtitle = element_text(size = 9.5, colour = INK2, lineheight = 1.15))
    list(g = g, med = median(off))
  }
  a <- corr_chart("r", "05", "엔진 수익 상관 — IS 월간 순수익", "15bps 순수익", "")
  add(save_png(a$g, "05_return_correlation.png", 8.0),
      sprintf("엔진 수익 상관 — IS 월간 순수익 · 계층 군집 순서 · 비대각 중앙값 %s · 저위험 계열 4 표시", f2(a$med, 2)))
  M[, x := r - b]
  b2 <- corr_chart("x", "05b", "엔진 초과수익 상관 — IS 월간(KOSPI200 차감)", "엔진 순수익 − KOSPI200", " · 05_benchmark_returns.csv(benchmark_ret)")
  add(save_png(b2$g, "05b_excess_return_correlation.png", 8.0),
      sprintf("엔진 초과수익 상관 — IS 월간(순수익 − KOSPI200) · 시장 공통 성분을 뺀 분산 원천 지도 · 비대각 중앙값 %s", f2(b2$med, 2)))
} else skip("05_return_correlation", "측정 끝난 칸이 3개 미만")

## =============================================================================================
## 6. 강세 국면 상승 포착률 — 강세 국면(행) × 엔진(열) · 행동 카드 up_capture
## =============================================================================================
if (nrow(BU)) {
  D6 <- copy(BU)
  key <- unique(D6[, .(start, end, win)])[order(start)][!duplicated(start)]
  key[, lab := paste0(sub("^20", "", sub("-", ".", start)), "~", sub("^20", "", sub("-", ".", end)))]
  key[, wf := factor(fcase(win == "visible", VIS_FACET, win == "straddle", STR_FACET, default = TEST_FACET), levels = c(VIS_FACET, STR_FACET, TEST_FACET))]
  key[, seam := SEAM_ON & start <= format(SEAM_DAY, "%Y-%m") & format(SEAM_DAY, "%Y-%m") <= end]
  lev_r <- rev(key$lab); lev_c <- CAT[ord]
  D6 <- merge(D6, key[, .(start, lab, wf, seam)], by = "start")
  D6[, `:=`(catf = factor(CAT[engine], levels = lev_c), labf = factor(lab, levels = lev_r), seam_cell = seam & engine %in% SEAM_HIT)]
  B6 <- merge(blank_cells(D6, "start"), key[, .(start, lab, wf)], by = "start")
  B6[, `:=`(catf = factor(CAT[engine], levels = lev_c), labf = factor(lab, levels = lev_r))]
  neg6 <- any(D6$up_capture < 0, na.rm = TRUE)
  g <- ggplot(D6, aes(catf, labf)) +
    geom_tile(aes(fill = up_capture), colour = "white", linewidth = 0.8) +
    geom_tile(data = B6, fill = BLANK, colour = "white", linewidth = 0.8) +
    geom_text(data = B6, label = "–", family = FAM, size = 2.8, colour = MUTED) +
    geom_tile(data = D6[seam_cell == TRUE], fill = NA, colour = INK, linewidth = 0.55, linetype = "22") +
    geom_text(aes(label = s2(up_capture, 2)), family = FAM, size = 2.8, colour = INK) +
    cap_fill(FALSE, "상승 포착률") +
    scale_x_discrete(labels = function(x) { e <- names(CAT)[match(x, CAT)]; cat_lab(e) }) +
    facet_grid(wf ~ ., scales = "free_y", space = "free_y", switch = "y") +
    labs(title = "강세 국면 상승 포착률 — 엔진 × KOSPI200 강세 국면",
         subtitle = paste0("값 = 강세 국면 엔진 누적수익 ÷ KOSPI200 누적수익 · 1.00 = 시장만큼 · 높을수록 참여(파랑)",
                           if (neg6) "\n음수 = 시장 상승 구간에 엔진 하락" else "", "\n",
                           sprintf("자격 문턱 = IS 강세 국면 중앙값 ≥ %s(등록본) · 열 순서 = IS 알파 t 내림차순", f2(TH_UC, 2)),
                           sprintf("\n경계 걸침 = IS/OOS 경계 %s 를 가로지르는 국면(보고 전용)", format(TAU)), FACET_TAIL, partial_note),
         x = NULL, y = NULL,
         caption = cap_add(paste0("출처: results/<칸>/full/behavior_card.json::bull_phases[].up_capture(행동 카드 · 계약 산출)",
                                  if (nrow(B6)) "\n– = 실효 시작 전(행동 카드에 국면 없음)" else "",
                                  if (any(D6$seam_cell)) " · 점선 테두리 = 이음매 하루가 든 국면 구간" else ""))) +
    heat_theme() + theme(strip.text.y.left = element_text(angle = 0, size = 9.5, colour = INK2))
  add(save_png(g, "06_bull_capture_heatmap.png", 3.2 + 0.36 * nrow(key)),
      paste0(sprintf("강세 국면 상승 포착률 열지도 — 엔진 × 강세 국면 %d개 · 높을수록 참여 · %s · 경계 걸침(%s) = 보고 전용", nrow(key), TEST_LAB, format(TAU)),
             if (any(D6$seam_cell)) sprintf(" · ‡ %s 의 %s 국면 칸 = 이음매 결함 · 인용 보류", SEAM_CATS, key[seam == TRUE]$lab[1]) else ""))
} else skip("06_bull_capture_heatmap", "행동 카드 없음 — 평가 전")

## =============================================================================================
## 7. 위기 하락노출 × 상승 포착률 — IS · 귀속 전 원값(기술형 산점도 · 방어 · 철학 판정 아님)
## =============================================================================================
D7 <- cells[is.finite(dd_vis) & is.finite(uc_vis_ev)]
if (nrow(D7)) {
  D7[, vf := factor(verdict_lab, levels = c("통과", "미달", "미시험"))]
  D7[, lab := ifelse(is.finite(beta_vis), sprintf("%s · β %s", cat, f2(beta_vis, 2)), cat)]
  xr <- range(c(D7$uc_vis_ev, TH_UC)); yr <- range(c(D7$dd_vis, 1)); xp <- diff(xr) * 0.12; yp <- diff(yr) * 0.15
  g <- ggplot(D7, aes(uc_vis_ev, dd_vis)) +
    geom_hline(yintercept = 1, linetype = "dashed", colour = INK2, linewidth = 0.45) +
    geom_vline(xintercept = TH_UC, linetype = "dashed", colour = INK2, linewidth = 0.45) +
    annotate("text", x = xr[1] - xp * 0.9, y = 1, label = "하락노출 1.00 = 시장만큼", vjust = -0.5, hjust = 0, family = FAM, size = 3.1, colour = INK2) +
    annotate("text", x = TH_UC, y = yr[2] + yp * 0.9, label = sprintf("상승 포착률 문턱 %s(등록본)", f2(TH_UC, 2)), hjust = -0.05, family = FAM, size = 3.1, colour = INK2) +
    geom_point(aes(colour = vf, shape = low), size = 3.6, stroke = 1.1) +
    ggrepel::geom_text_repel(aes(label = lab), family = FAM, size = 3.5, colour = INK, seed = 11, box.padding = 0.45,
                             min.segment.length = 0.2, segment.colour = MUTED, max.overlaps = 50) +
    scale_colour_manual(values = c("통과" = C_PASS, "미달" = C_FAIL, "미시험" = C_NA), drop = TRUE, labels = c("통과" = "P1 자격 통과", "미달" = "P1 자격 미달", "미시험" = "미시험")) +
    scale_shape_manual(values = c(`FALSE` = 16, `TRUE` = 17), labels = c(`FALSE` = "기타 카테고리", `TRUE` = "저위험 계열(방어 · 위험 · 유동성 · 국면)")) +
    scale_x_continuous(limits = c(xr[1] - xp, xr[2] + xp), labels = function(x) f2(x, 2)) +
    scale_y_continuous(limits = c(yr[1] - yp, yr[2] + yp), labels = function(x) f2(x, 2)) +
    labs(title = "위기 하락노출 × 상승 포착률 — IS · 귀속 전 원값",
         subtitle = paste0("x = IS 상승 포착률(강세 국면 중앙값) · y = IS 위기 하락노출 중앙값(위기 구간 전략 낙폭 ÷ 시장 낙폭)\n",
                           "귀속 전 원값 — β · 크기 · 숨은 현금 미통제 · 방어 근거 아님 · 자격 ≠ 철학 적합(사전등록 결론 범위)\n",
                           "점 라벨 = 카테고리 · IS β — 낮은 하락노출과 낮은 β 가 겹치는지 함께 읽는다\n색 = P1 자격(하락노출은 판정에 안 쓰는 보고 열)",
                           partial_note, if (nzchar(WIN_NOTE)) paste0("\n", WIN_NOTE) else ""),
         x = "IS 상승 포착률(강세 국면 중앙값)", y = "IS 위기 하락노출(중앙값)",
         caption = "출처: results/<칸>/eval.json::visible(uc · dd_capture_median · window · n_crisis — 행동 카드 IS 패킷)\nβ · 판정 색 =results/verdict.json(beta_vis · qualify)") +
    th() + theme(legend.box = "vertical", legend.spacing.y = unit(2, "pt"), plot.subtitle = element_text(size = 9.3, colour = INK2, lineheight = 1.15))
  add(save_png(g, "07_asymmetry_map.png", 7.6),
      "위기 하락노출 × 상승 포착률(IS · 귀속 전 원값) — 점 라벨에 IS β 병기 · β · 크기 · 숨은 현금 미통제 · 방어 근거 아님 · 자격 ≠ 철학 적합(사전등록 결론 범위)")
} else skip("07_asymmetry_map", "eval.json(visible uc · dd_capture_median) 없음 — 평가 전")

## =============================================================================================
## 8. 연도별 초과수익 — 엔진 × 연도(순수익 − KOSPI200)
## =============================================================================================
if (nrow(S)) {
  Y <- S[, .(r = prod(1 + ret_net) - 1, b = prod(1 + benchmark_ret) - 1, d0 = min(date), d1 = max(date)), by = .(engine, yr = as.integer(format(date, "%Y")))]
  Y[, x := r - b]
  ## 엔진별 부분 첫해: 그 칸 첫 수익일이 연초(첫 10일) 뒤인 해
  Y[, partial := yr == min(yr) & as.integer(format(d0, "%j")) > 10L, by = engine]
  yl <- Y[, .(d0 = min(d0), d1 = max(d1), anyp = any(partial)), by = yr][order(yr)]
  yl[, lab := as.character(yr)]
  yl[yr == min(yr) & anyp, lab := paste0(yr, "(부분)")]
  yl[d1 == max(d1) & format(d1, "%m") != "12", lab := paste0(yr, "(~", as.integer(format(d1, "%m")), "월)")]
  vis_y <- as.integer(format(TAU, "%Y"))
  yl[, wf := factor(ifelse(yr <= vis_y, VIS_FACET, TEST_FACET), levels = c(VIS_FACET, TEST_FACET))]
  lev_r <- rev(yl$lab); lev_c <- CAT[ord]
  Y <- merge(Y, yl[, .(yr, lab, wf)], by = "yr")
  Y[, `:=`(labf = factor(lab, levels = lev_r), catf = factor(CAT[engine], levels = lev_c),
           seam_cell = SEAM_ON & engine %in% SEAM_HIT & yr == as.integer(format(SEAM_DAY, "%Y")))]
  Y[, txt := paste0(mm(ifelse(round(100 * x) == 0, "0", sprintf("%+.0f", round(100 * x)))), ifelse(partial, "†", ""))]
  B8 <- merge(blank_cells(Y, "yr"), yl[, .(yr, lab, wf)], by = "yr")
  B8[, `:=`(labf = factor(lab, levels = lev_r), catf = factor(CAT[engine], levels = lev_c))]
  ## 엔진별 실효 시작(첫 수익일 달) 묶음 — 캡션용
  st8 <- Y[, .(m = format(min(d0), "%Y-%m")), by = engine][, .(cats = paste(CAT[engine], collapse = " · "), n = .N), by = m][order(-n)]
  st_line <- paste(c(if (nrow(st8) > 1) sprintf("%s %s", st8$cats[-1], st8$m[-1]), sprintf("%s %s", if (nrow(st8) > 1) "그 밖" else "전 칸", st8$m[1])), collapse = " · ")
  lim <- 0.4
  g <- ggplot(Y, aes(catf, labf)) +
    geom_tile(aes(fill = x, alpha = partial), colour = "white", linewidth = 0.6) +
    geom_tile(data = B8, fill = BLANK, colour = "white", linewidth = 0.6) +
    geom_text(data = B8, label = "–", family = FAM, size = 2.8, colour = MUTED) +
    geom_tile(data = Y[seam_cell == TRUE], fill = NA, colour = INK, linewidth = 0.55, linetype = "22") +
    geom_text(aes(label = txt), family = FAM, size = 2.8, colour = INK) +
    scale_alpha_manual(values = c(`FALSE` = 1, `TRUE` = 0.5), guide = "none") +
    scale_fill_gradient2(low = C_NEG, mid = C_MID, high = C_POS, midpoint = 0, limits = c(-lim, lim), oob = scales::squish, name = "연 초과수익",
                         breaks = c(-0.4, -0.2, 0, 0.2, 0.4), labels = c("≤−40%", "−20%", "0", "+20%", "≥+40%")) +
    scale_x_discrete(labels = function(x) { e <- names(CAT)[match(x, CAT)]; cat_lab(e) }) +
    facet_grid(wf ~ ., scales = "free_y", space = "free_y", switch = "y") +
    labs(title = "연도별 초과수익 — 엔진 × 연도",
         subtitle = paste0("값 = 그해 엔진 순수익(15bps) − KOSPI200 수익, %p · 파랑 = 시장 상회 · 빨강 = 하회\n",
                           "열 순서 = IS 알파 t 내림차순 · † · 옅은 칸 = 그 엔진의 첫해가 부분 연도(실효 시작이 그해 중간) · 마지막 행 = 부분 연도",
                           FACET_TAIL, partial_note),
         x = NULL, y = NULL,
         caption = cap_add(paste0("출처: 산출물 03_period_returns.csv(ret_net) · 05_benchmark_returns.csv(benchmark_ret) — 일별 복리 · 기술 통계 · 판정 아님\n",
                                  "† 부분 연도 · 실효 시작(첫 수익일 달) = ", st_line, if (nrow(B8)) "\n– = 실효 시작 전" else "",
                                  if (any(Y$seam_cell)) " · 점선 테두리 = 이음매 하루가 든 해" else ""))) +
    heat_theme() + theme(axis.text.y = element_text(size = 8.8, colour = INK), strip.text.y.left = element_text(angle = 0, size = 9.5, colour = INK2))
  add(save_png(g, "08_annual_excess_heatmap.png", 2.9 + 0.27 * nrow(yl)),
      paste0(sprintf("연도별 초과수익 열지도 — 엔진 × 연도(순수익 − KOSPI200 · %%p) · 2023~ = %s · † = 엔진별 부분 첫해(%s)", TEST_LAB, st_line),
             if (any(Y$seam_cell)) sprintf(" · ‡ %s 의 %s 칸 = 이음매 결함 · 인용 보류", SEAM_CATS, format(SEAM_DAY, "%Y")) else ""))
} else skip("08_annual_excess_heatmap", "측정 끝난 칸이 없다")

## =============================================================================================
## 9. 성적표 — 판정 표 + 행동 카드 + 권위 등급
## =============================================================================================
if (!is.null(VT)) {
  T9 <- cells[order(match(engine, ord))]
  sh <- T9$engine %in% SEAM_HIT
  ws <- ifelse(is.na(T9$vis_ym), "–", paste0(substr(T9$vis_ym, 3, 7), ifelse(is.finite(T9$n_crisis_vis), sprintf(" · %d", as.integer(T9$n_crisis_vis)), "")))
  cols <- list(
    list(h = "카테고리",                 v = paste0(T9$cat, ifelse(T9$low, " *", ""))),
    list(h = "판정",                    v = T9$verdict_lab),
    list(h = "알파 t\nIS",           v = mm(f2(T9$t_alpha_vis, 2))),
    list(h = "상승 포착률\nIS",         v = f2(T9$uc_vis, 2)),
    list(h = "알파 연율\nIS",         v = mm(pct(T9$alpha_ann_vis, 1))),
    list(h = "β\nIS",               v = f2(T9$beta_vis, 2)),
    list(h = "CAGR\nIS",            v = mm(pct(T9$cagr_vis, 1))),
    list(h = "위기 하락노출\nIS 중앙값", v = f2(T9$dd_vis, 2)),
    list(h = "IS 시작\n· 위기 수",     v = ws),
    list(h = "등급\n전기간",              v = paste0(ifelse(is.na(T9$grade), "–", T9$grade), ifelse(sh, " ‡", ""))),
    list(h = "알파 t\nOOS*",          v = paste0(mm(f2(T9$t_alpha_test, 2)), ifelse(sh, " ‡", ""))))
  nr <- nrow(T9); nc <- length(cols)
  xw <- c(1.25, 0.7, 0.8, 0.85, 0.9, 0.65, 0.85, 1.15, 1.0, 0.75, 0.9); xs <- cumsum(xw) - xw / 2
  G <- rbindlist(lapply(seq_len(nc), function(j) data.table(x = xs[j], y = rev(seq_len(nr)), lab = cols[[j]]$v, j = j)))
  G[, col := INK]
  G[j == 2 & lab == "통과", col := C_PASS]; G[j == 2 & lab == "미달", col := C_FAIL]
  tv <- T9$t_alpha_vis; uv <- T9$uc_vis
  G[j == 3, col := ifelse(is.finite(tv[nr + 1 - y]) & tv[nr + 1 - y] >= TH_T, C_PASS, INK)]
  G[j == 4, col := ifelse(is.finite(uv[nr + 1 - y]) & uv[nr + 1 - y] >= TH_UC, C_PASS, INK)]
  G[j %in% c(9, nc), col := MUTED]
  G[j == nc - 1 & grepl("‡", lab, fixed = TRUE), col := MUTED]
  H <- data.table(x = xs, y = nr + 1.05, lab = vapply(cols, `[[`, character(1), "h"))
  band <- data.table(y = seq_len(nr))[y %% 2 == 0]
  g <- ggplot() +
    geom_rect(data = band, aes(xmin = 0, xmax = sum(xw), ymin = y - 0.5, ymax = y + 0.5), fill = BLANK) +
    geom_text(data = G, aes(x, y, label = lab, colour = I(col)), family = FAM, size = 3.2) +
    geom_text(data = H, aes(x, y, label = lab), family = FAM, size = 2.9, colour = INK2, lineheight = 0.9, vjust = 0) +
    geom_hline(yintercept = nr + 0.55, colour = "#c3c2b7", linewidth = 0.4) +
    scale_x_continuous(limits = c(0, sum(xw)), expand = c(0, 0)) +
    scale_y_continuous(limits = c(0.4, nr + 1.9), expand = c(0, 0)) +
    labs(title = "P1R03 성적표 — 카테고리 합성 엔진 15",
         subtitle = paste0(RULE_LINE, " · 파랑 = 문턱 충족\n행 순서 = IS 알파 t 내림차순 · * 카테고리 = 저위험 계열 · * 열 = ", TEST_LAB, partial_note,
                           if (nzchar(WIN_NOTE)) paste0("\n", WIN_NOTE) else "",
                           "\n위기 하락노출 = 위기 구간 전략 낙폭 ÷ 시장 낙폭 · 귀속 전 원값 — 판정에 안 쓰는 보고 열 · 방어 근거 아님"),
         caption = cap_add(paste0("출처: results/verdict.json(알파 t · 상승 포착률 · 알파 연율 · β · CAGR · 판정) · results/<칸>/eval.json::visible(dd_capture_median · window · n_crisis)\n",
                                  "등급 = results/<칸>.json(authoritative_remeasure essence_grade · 등급 v3.4 · 전기간 — 사람 쪽 참고) · IS 시작 = 첫 수익일 연-월(yy-mm)"))) +
    th(11) + theme(axis.text = element_blank(), panel.grid = element_blank(), panel.grid.major = element_blank(), axis.title = element_blank(),
                   plot.subtitle = element_text(size = 9.3, colour = INK2, lineheight = 1.15))
  add(save_png(g, "09_scorecard.png", 2.6 + 0.33 * nr, w = 8.4),
      paste0(sprintf("성적표 — 판정 · 알파 t · 상승 포착률 · 알파 연율 · β · CAGR · 위기 하락노출 · IS 시작 · 위기 수 · 전기간 등급 · OOS 알파 t(보고 전용) · 통과 %d/%d",
                     sum(T9$verdict_lab == "통과"), nr),
             if (SEAM_ON) sprintf(" · ‡ %s 전기간 등급 · OOS 알파 t = 이음매 결함 · 인용 보류(IS 판정 영향 없음)", SEAM_CATS) else ""))
} else skip("09_scorecard", "판정 표(results/verdict.json) 없음 — 평가 전")

## ---- 기록 · 출력 -------------------------------------------------------------------------------
if (length(skipped)) cat(toJSON(list(skipped = skipped), auto_unbox = TRUE), "\n", file = stderr())
rel <- function(p) sub(paste0("^", ROOT, "/"), "", gsub("\\\\", "/", p), fixed = FALSE)
cat(toJSON(lapply(made, function(m) list(file = rel(m$file), caption = m$caption)), auto_unbox = TRUE), "\n")
