## P1R04 결과 보고 차트 묶음 — 결합기 T1(시점별 IC 가중) 15 엔진 vs 같은 날 재측정한 등가중 기준 15 엔진
##   (표준 구성 = 롱온리 25종 등가중 · 월말 신호 · 15bps · 20일 평균 거래대금 ≥ 2억 원 · 전 종목 위생 유니버스 — P1R03 과 같다)
##   실행(저장소 루트 · 측정 · 평가 · 짝 읽기 뒤): Rscript 04_Research/programs/P1_RETURN/P1R04_combiner_t1_icw/tools/p1r04_charts.R [라운드 폴더]
##   P1R04_CHARTS_IS_ONLY=1 → OOS 요소(OOS 값 · OOS 음영 · 전기간 등급)를 빼고 그린다. 다음 단계를 설계하는 세션은 이 판으로 배치만 확인한다(τ_D).
##   출력: <라운드>/report/charts/*.png(IS 전용 = report/charts_is/) · 마지막 표준 출력 줄 = JSON 배열 [{"file","caption"}](prep_send charts 인자용)
##   수치 출처(AX-008 — 판정에 닿는 값은 다시 계산하지 않는다):
##     · 엔진 자격 표(β-통제 알파 t · 상승 포착률 · β · 알파 연율 · CAGR · 자격) = results/verdict.json::table(OOS 열 포함) | IS 전용 = results/evaluation_visible.json::table
##     · 짝 증분(IS) · 행동 차 · 제외 표식 · 결합 개선 판정 = results/pair_reading_visible.json(사전등록에 고정한 도구 tools/p1r04_pair_reading.R 의 산출)
##     · OOS 짝 증분 t = round_core 계약 rc_pair_alpha(...)$test(보고 전용 · 판정에 쓰지 않는다)
##     · 위기별 하락노출 = results/<엔진>/visible/diagnosis_packet.json(IS) | OOS 포함 = results/<엔진>/full/behavior_card.json(행동 카드 · LT 20/20)
##     · NAV · 수익 · 보유 = 산출물 02_nav · 03_period_returns · 04_holdings · 05_benchmark_returns(기술 통계 · 판정 아님)
##     · 카테고리 가중 추이 = 엔진과 같은 식(fc_combiner_gen.R fcc_rule_t1_v0 — w = max(s_reg × ICIR(as-of 36~120개월), 0) · W_f = 카테고리 구성원 가중 평균)으로
##       IS 달마다 다시 낸 값(결합용 뷰 · 정본 IC 접근자 · 성과 무참조) → results/weight_trace_visible.json 에 저장(있으면 다시 쓰지 않는다)
##   쓰는 곳 = report/charts(_is)/ · results/weight_trace_visible.json 뿐(발송 · 커밋 없음).
suppressPackageStartupMessages({ library(data.table); library(jsonlite); library(ggplot2) })
for (p in c("ragg", "systemfonts", "ggrepel", "scales")) if (!requireNamespace(p, quietly = TRUE)) stop("[p1r04_charts] 패키지 없음: ", p)
ROOT <- sub("/+$", "", gsub("\\\\", "/", Sys.getenv("QM_ROOT", getwd())))     # 경로 정규화 함수 금지(한글 경로) — 슬래시 치환만
if (!file.exists(file.path(ROOT, "CLAUDE.md"))) ROOT <- gsub("\\\\", "/", getwd())
setwd(ROOT)
invisible(capture.output(suppressMessages(source("04_Research/programs/_lib/round_core/v3/load.R"))))
args <- commandArgs(trailingOnly = TRUE)
RD <- if (length(args) && !is.na(args[1]) && nzchar(args[1])) args[1] else "04_Research/programs/P1_RETURN/P1R04_combiner_t1_icw"
RDA <- if (grepl("^([A-Za-z]:|/)", RD)) RD else file.path(ROOT, RD)
RES <- file.path(RDA, "results")
IS_ONLY <- identical(Sys.getenv("P1R04_CHARTS_IS_ONLY"), "1")
OUT <- Sys.getenv("P1R04_CHARTS_OUT", file.path(RDA, "report", if (IS_ONLY) "charts_is" else "charts"))
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)
SP <- rc_json_read(file.path(RDA, "round_spec.json"))
TAU <- as.Date(SP$tau_d)

## ---- 공통 도우미 ---------------------------------------------------------------------------------
num <- function(x) { v <- suppressWarnings(as.numeric(unlist(x))); if (length(v) == 1L) v else NA_real_ }
rj <- function(p) if (file.exists(p)) tryCatch(fromJSON(p, simplifyVector = FALSE), error = function(e) NULL) else NULL
rows_dt <- function(rows) {                                    # 행 목록(JSON 객체 배열) → data.table · 빈 값 = NA
  if (!length(rows)) return(NULL)
  nm <- unique(unlist(lapply(rows, names)))
  rbindlist(lapply(rows, function(r) as.data.table(lapply(setNames(nm, nm), function(k) { v <- r[[k]]; if (is.null(v) || !length(v)) NA else v[[1]] }))), fill = TRUE)
}
find_rule <- function(rules, id) { for (r in rules) { if (identical(r$id, id)) return(r); if (!is.null(r$of)) { k <- find_rule(r$of, id); if (!is.null(k)) return(k) } }; NULL }
pct <- function(x, d = 0) ifelse(is.finite(x), sprintf(paste0("%.", d, "f%%"), 100 * x), "–")
f2 <- function(x, d = 2) ifelse(is.finite(x), sub("^-(0[.]?0*)$", "\\1", formatC(x, format = "f", digits = d)), "–")
mm <- function(s) gsub("-", "−", s, fixed = TRUE)
s2 <- function(x, d = 2) mm(sub("^(-?)0\\.", "\\1.", f2(x, d)))
sgn <- function(x, d = 2) ifelse(is.finite(x), mm(sprintf(paste0("%+.", d, "f"), x)), "–")

## ---- 색 · 글꼴(현대하모니 M — P1R03 차트와 같은 방식) ------------------------------------------------
C_T1 <- "#2a78d6"; C_T0 <- "#7d9fc8"; C_BENCH <- "#898781"; C_PASS <- "#2a78d6"; C_FAIL <- "#e34948"; C_NA <- "#b5b3ab"
C_POS <- "#2a78d6"; C_NEG <- "#e34948"; C_MID <- "#f0efec"; C_TAG <- "#eb6834"; C_GOOD <- "#2a78d6"; C_BAD <- "#e34948"
INK <- "#0b0b0b"; INK2 <- "#52514e"; MUTED <- "#898781"; GRID <- "#e1e0d9"; TEST_FILL <- "#eceae3"; BLANK <- "#f5f4ef"
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
          legend.title = element_blank(), plot.background = element_rect(fill = "white", colour = NA), plot.margin = margin(10, 14, 8, 10))
}
save_png <- function(g, name, h, w = 7.2) { p <- file.path(OUT, name); ggsave(p, g, width = w, height = h, dpi = 150, device = ragg::agg_png, bg = "white"); p }
made <- list(); skipped <- list()
add <- function(file, caption) made[[length(made) + 1L]] <<- list(file = file, caption = caption)
skip <- function(name, why) { skipped[[length(skipped) + 1L]] <<- list(chart = name, reason = why); cat(sprintf("[건너뜀] %s — %s\n", name, why), file = stderr()) }
## 부제 · 캡션 줄바꿈 — 그림 너비(인치) · 글자 크기(pt)로 한 줄 표시 폭을 정한다(strwrap = 표시 폭 기준 · 한글 2칸). 0.45 = 평균 글자 폭 ÷ 글자 크기(배치 시험 11-13 실측 근사)
wrapw <- function(s, W) if (is.null(s) || !nzchar(s)) s else
  paste(unlist(lapply(strsplit(s, "\n", fixed = TRUE)[[1]], function(l) if (nchar(l, type = "width") <= W) l else strwrap(l, width = W))), collapse = "\n")
LB <- function(w_in, base = 12, title = NULL, subtitle = NULL, caption = NULL, cap_pt = base - 4, ...) {
  wu <- function(pt) floor((w_in - 0.4) * 72 / (pt * 0.45))
  labs(title = title, subtitle = wrapw(subtitle, wu(base - 1.5)), caption = wrapw(caption, wu(cap_pt)), ...)
}

## ---- 등록 규칙 · 표시 이름 -----------------------------------------------------------------------
RR <- rc_rules_resolve(SP$rules, ROOT)
TH_T <- num(find_rule(RR, "q_t_alpha")$value); TH_UC <- num(find_rule(RR, "q_uc")$value)
if (!is.finite(TH_T) || !is.finite(TH_UC)) stop("[p1r04_charts] 자격 문턱을 사양 규칙에서 읽지 못했다")
KEEP <- as.numeric(RC_P4_UC_SEG_KEEP)
CATN <- c(accrual = "발생액", consensus = "컨센서스", crowding = "쏠림", defense = "방어", growth = "성장", investor_flow = "수급", leverage = "레버리지",
          liquidity = "유동성", momentum = "모멘텀", quality = "퀄리티", regime = "국면", risk = "위험", technical = "기술적", value = "밸류", total = "토탈")
LOWRISK <- c("defense", "risk", "liquidity", "regime")
MISDIR <- c(value = "V23_RAFI_Weight", consensus = "C08_Coverage", crowding = "CR05_Short_Pressure_Proxy")   # 방향 격리 재판정 불일치 3(11-13 · DESIGN §10)
OOS_LAB <- sprintf("OOS(%s~ · 보고 전용)", format(TAU + 1, "%Y"))
IS_LAB <- sprintf("IS(첫 체결일 ~ %s)", format(TAU))
STD_CAP <- "표준 구성 = 롱온리 25종 등가중 · 월말 신호 · 15bps · 20일 평균 거래대금 ≥ 2억 원 · 전 종목 위생 유니버스"
lin_lab <- function(ln) ifelse(ln %in% LOWRISK, paste0(CATN[ln], " *"), CATN[ln])

## ---- 엔진 30 · 결과 · 판정 표 ------------------------------------------------------------------
CE <- rbindlist(lapply(SP$cells, function(c) data.table(code = as.character(c$code), engine = as.character(c$engine), role = as.character(c$role),
                                                        lineage = as.character(c$lineage %||% NA_character_))))
if (anyNA(CE$lineage) || !all(CE$lineage %in% names(CATN))) stop("[p1r04_charts] 사양 칸의 lineage 가 표시 이름표 밖이다")
cres <- function(code) {
  r <- rj(file.path(RES, paste0(code, ".json"))); ev <- rj(file.path(RES, code, "eval.json"))
  art <- if (isTRUE(r$ok) && !is.null(r$artifacts)) r$artifacts else ev$artifacts
  art <- if (is.null(art)) NA_character_ else gsub("\\\\", "/", as.character(art)[1])
  list(artifacts = if (!is.na(art) && dir.exists(art)) art else NA_character_,
       grade = if (!IS_ONLY && isTRUE(r$ok) && !is.null(r$grade)) as.character(r$grade)[1] else NA_character_,
       evaluated = identical(ev$status, "evaluated"))
}
cr <- lapply(CE$code, cres)
CE[, `:=`(artifacts = vapply(cr, `[[`, character(1), "artifacts"), grade = vapply(cr, `[[`, character(1), "grade"),
          evaluated = vapply(cr, `[[`, logical(1), "evaluated"))]
VT <- rows_dt((rj(file.path(RES, if (IS_ONLY) "evaluation_visible.json" else "verdict.json")) %||% list())$table)
if (!is.null(VT) && IS_ONLY) { tc <- grep("_test$", names(VT), value = TRUE); if (length(tc)) VT[, (tc) := NULL] }
NUMC <- c("t_alpha_vis", "alpha_ann_vis", "beta_vis", "uc_vis", "cagr_vis", "t_alpha_test", "alpha_ann_test")
if (!is.null(VT)) CE <- merge(CE, VT[, intersect(c("code", NUMC, "qualify"), names(VT)), with = FALSE], by = "code", all.x = TRUE, sort = FALSE)
for (k in NUMC) CE[, (k) := if (k %in% names(CE)) suppressWarnings(as.numeric(get(k))) else NA_real_]
CE[, qualify := if ("qualify" %in% names(CE)) as.logical(qualify) else NA]
V1 <- CE[role == "variant"]; V0 <- CE[role == "reference"]
L <- merge(V1[, .(lineage, code1 = code, art1 = artifacts, grade1 = grade, t1 = t_alpha_vis, a1 = alpha_ann_vis, b1 = beta_vis, uc1 = uc_vis,
                  cg1 = cagr_vis, tt1 = t_alpha_test, q1 = qualify)],
           V0[, .(lineage, code0 = code, art0 = artifacts, t0 = t_alpha_vis, a0 = alpha_ann_vis, b0 = beta_vis, uc0 = uc_vis, cg0 = cagr_vis,
                  tt0 = t_alpha_test, q0 = qualify)], by = "lineage", all = TRUE)
L[, cat := unname(CATN[lineage])]
## 짝 읽기(사전등록 도구 산출) — 없으면 짝 그림은 건너뛴다
PR <- rj(file.path(RES, "pair_reading_visible.json")); PT <- rows_dt(PR$table)
PNUM <- c("d_t_vis", "d_alpha_ann_vis", "n_vis", "uc_t1", "uc_t0", "dd_med_t1", "dd_med_t0", "beta_t1", "beta_t0", "ew_cw_t1", "ew_cw_t0",
          "selection_t1", "selection_t0", "cdar_t1", "cdar_t0", "bull_seg_keep_share", "deep_crisis_nonworse_share")
PLOG <- c("strength_loss", "crisis_worse", "size_tilt", "pass_t", "counted", "lowrisk_tilt_tag")
if (!is.null(PT)) L <- merge(L, PT[, intersect(c("lineage", "status", PNUM, PLOG), names(PT)), with = FALSE], by = "lineage", all.x = TRUE)
for (k in PNUM) L[, (k) := if (k %in% names(L)) suppressWarnings(as.numeric(get(k))) else NA_real_]
for (k in PLOG) L[, (k) := if (k %in% names(L)) as.logical(get(k)) else NA]
if (!"status" %in% names(L)) L[, status := NA_character_]
ORD <- L[order(-d_t_vis, -t1, na.last = TRUE)]$lineage                    # 표시 순서 = IS 짝 증분 t 내림차순
N_MEAS <- sum(!is.na(CE$artifacts)); N_ALL <- nrow(CE)
partial_note <- if (N_MEAS == N_ALL) "" else sprintf(" · 측정 %d/%d(중간 판독)", N_MEAS, N_ALL)
cat(sprintf("[p1r04_charts] %s · 측정 %d/%d · 판정 표 %s · 짝 읽기 %s\n", if (IS_ONLY) "IS 전용" else "IS + OOS", N_MEAS, N_ALL,
            if (is.null(VT)) "없음" else "있음", if (is.null(PT)) "없음" else "있음"), file = stderr())

## ---- 수익 · NAV 계열(산출물) --------------------------------------------------------------------
read_series <- function(dir) {
  nv <- fread(file.path(dir, "02_nav.csv"), select = c("date", "nav_net"))
  pr <- fread(file.path(dir, "03_period_returns.csv"), select = c("date", "ret_net"))
  br <- fread(file.path(dir, "05_benchmark_returns.csv"), select = c("date", "benchmark_ret", "benchmark_nav"))
  x <- merge(merge(nv, pr, by = "date"), br, by = "date"); x[, date := as.Date(date)]; x <- x[order(date)]
  if (IS_ONLY) x <- x[date <= TAU]
  x
}
SR <- rbindlist(lapply(which(!is.na(CE$artifacts)), function(i) {
  x <- tryCatch(read_series(CE$artifacts[i]), error = function(e) NULL); if (is.null(x) || !nrow(x)) return(NULL)
  x[, `:=`(code = CE$code[i], role = CE$role[i], lineage = CE$lineage[i])]
}))
DATA_END <- if (nrow(SR)) max(SR$date) else as.Date(NA)
## 같은 산출 짝(사전등록 정정 기록 R-2 예외): IS 일별 순수익이 모두 같으면 증분 0 = 개선 아님(측정됨)
same_out <- function(ln) {
  a <- SR[lineage == ln & role == "variant" & date <= TAU, .(date, r1 = ret_net)]; b <- SR[lineage == ln & role == "reference" & date <= TAU, .(date, r0 = ret_net)]
  x <- merge(a, b, by = "date"); nrow(x) > 0 && isTRUE(all.equal(x$r1, x$r0, tolerance = 1e-12))
}
L[, same := vapply(lineage, same_out, logical(1))]
L[, gap := status %in% "evaluated" & !same & !(is.finite(d_t_vis) & is.finite(uc_t1) & is.finite(uc_t0))]
VV <- switch(as.character(PR$verdict %||% "?"), support = "지지 — 결합 개선", falsified = "반증 — 개선 없음", untested = "미시험 — 측정 안 된 짝 있음", "판독 불가(짝 읽기 없음)")
if (any(L$gap) && !identical(PR$verdict, "support")) VV <- "미시험 — 값이 빈 짝(사전등록 정정 기록)"
## OOS 짝 증분(보고 전용 · 계약 rc_pair_alpha 의 test)
L[, `:=`(dt_test = NA_real_, da_test = NA_real_)]
if (!IS_ONLY) {
  E <- rc_deps(ROOT)
  for (i in seq_len(nrow(L))) if (!is.na(L$art1[i]) && !is.na(L$art0[i])) {
    pa <- tryCatch(rc_pair_alpha(E, L$art1[i], L$art0[i], TAU)$test, error = function(e) NULL)
    if (!is.null(pa)) set(L, i, c("dt_test", "da_test"), list(num(pa$t), num(pa$d_alpha)))
  }
}
RULE_LINE <- sprintf("엔진 자격(사전등록) = IS β-통제 알파 t ≥ %s ∧ IS 상승 포착률 ≥ %s", f2(TH_T, 1), f2(TH_UC, 2))
PAIR_RULE <- sprintf("결합 개선(사전등록) = IC 가중 − 등가중 월 수익 차의 IS β-통제 알파 t ≥ %s 인 짝이 2개 이상 또는 토탈 짝 — 상승 포착률 손실(기준의 %s%% 아래) · 위기 하락노출 악화 · 소형주 쪽 이동인 짝은 세지 않는다",
                     f2(TH_T, 1), formatC(100 * KEEP, format = "d"))

## =============================================================================================
## 1. 짝 증분 — IC 가중 − 등가중 월 수익 차의 IS β-통제 알파 t
## =============================================================================================
D1 <- L[is.finite(d_t_vis) | gap | same | !(status %in% "evaluated")]
if (!is.null(PT) && nrow(D1)) {
  D1[, st := fcase(gap | !(status %in% "evaluated"), "미시험",
                   counted %in% TRUE, "셈 대상(문턱 ∧ 제외 표식 없음)",
                   pass_t %in% TRUE, "문턱 넘음 · 제외 표식",
                   default = "문턱 미달")]
  D1[, stf := factor(st, levels = c("셈 대상(문턱 ∧ 제외 표식 없음)", "문턱 넘음 · 제외 표식", "문턱 미달", "미시험"))]
  D1[, tags := fifelse(st == "미시험", "", trimws(paste0(ifelse(strength_loss %in% TRUE, "참여↓ ", ""), ifelse(crisis_worse %in% TRUE, "위기↑ ", ""), ifelse(size_tilt %in% TRUE, "소형주", ""))))]
  D1[, catr := factor(lineage, levels = rev(ORD))]
  D1[, xv := fifelse(is.finite(d_t_vis), d_t_vis, 0)]
  D1[, lab_x := pmax(xv, 0, dt_test, na.rm = TRUE) + 0.15]                    # 값 라벨은 늘 막대 끝 · 0 · OOS 점 중 오른쪽 바깥(음수 막대가 축 라벨과 겹치지 않게)
  D1[, lab := paste0(fifelse(same, "0(같은 산출)", mm(f2(d_t_vis, 2))), fifelse(st == "미시험", " 미시험", ""), ifelse(nzchar(tags), paste0("  ", tags), ""))]
  lo <- min(0, D1$xv, D1$dt_test, na.rm = TRUE); hi <- max(TH_T, D1$xv, D1$dt_test, 0, na.rm = TRUE)
  W1 <- 7.6
  g <- ggplot(D1, aes(y = catr)) +
    geom_col(aes(x = xv, fill = stf), width = 0.62, show.legend = TRUE) +
    geom_vline(xintercept = 0, colour = "#c3c2b7", linewidth = 0.4) +
    geom_vline(xintercept = TH_T, linetype = "dashed", colour = INK2, linewidth = 0.5) +
    annotate("text", x = TH_T, y = Inf, label = sprintf("문턱 t = %s", f2(TH_T, 1)), vjust = -0.4, hjust = -0.05, family = FAM, size = 3.2, colour = INK2) +
    geom_text(aes(x = lab_x, label = lab), hjust = 0, family = FAM, size = 3.2, colour = INK) +
    scale_y_discrete(labels = function(x) lin_lab(x)) +
    scale_fill_manual(values = c("셈 대상(문턱 ∧ 제외 표식 없음)" = C_PASS, "문턱 넘음 · 제외 표식" = C_TAG, "문턱 미달" = "#c9c7bf", "미시험" = "#e6e4dc"), drop = FALSE, name = NULL) +
    scale_x_continuous(limits = c(lo - 0.3, hi + 2.6)) + coord_cartesian(clip = "off") +
    guides(fill = guide_legend(nrow = 2)) +
    LB(W1, 12, title = "결합 개선 — IC 가중 − 등가중 짝 증분 알파 t(IS)", cap_pt = 7.6,
         subtitle = paste0("판정: ", VV, " · 셈 대상 ", sum(D1$st == "셈 대상(문턱 ∧ 제외 표식 없음)"), " / 짝 ", nrow(D1),
                           " · 토탈 짝 ", if (isTRUE(L[lineage == "total"]$counted)) "셈 대상" else "셈 밖", partial_note, "\n",
                           "막대 = 같은 날 측정한 두 엔진의 월 수익 차(IC 가중 − 등가중)를 KOSPI200 에 회귀한 β-통제 알파 t(NW lag 3) · ", IS_LAB, "\n",
                           "제외 표식: 참여↓ = 상승 포착률 손실 · 위기↑ = 위기 하락노출 악화 · 소형주 = 크기 성분↑ ∧ 선택 성분↓ · * = 저위험 카테고리",
                           if (!IS_ONLY) paste0("\n속 빈 점 = ", OOS_LAB, " 짝 증분 t — 판정에 쓰지 않는다") else ""),
         x = "짝 증분 β-통제 알파 t", y = NULL,
         caption = paste0(PAIR_RULE, "\n출처: results/pair_reading_visible.json(사전등록 고정 도구 tools/p1r04_pair_reading.R)",
                          if (!IS_ONLY) " · OOS = round_core 계약 rc_pair_alpha(test)" else "", "\n", STD_CAP)) +
    th() + theme(panel.grid.major.y = element_blank(), axis.text.y = element_text(size = 11.5, colour = INK), plot.margin = margin(14, 14, 8, 10),
                 plot.caption = element_text(size = 7.6, colour = MUTED, hjust = 0, lineheight = 1.1))
  if (!IS_ONLY && any(is.finite(D1$dt_test)))
    g <- g + geom_point(data = D1[is.finite(dt_test)], aes(x = dt_test, shape = "OOS 짝 증분 t(보고 전용)"), size = 3, stroke = 1, colour = INK, fill = "white") +
      scale_shape_manual(values = c("OOS 짝 증분 t(보고 전용)" = 21), name = NULL)
  add(save_png(g, "01_pair_increment.png", 3.4 + 0.36 * nrow(D1), w = 7.6),
      sprintf("결합 개선 판정 — IC 가중 − 등가중 짝 증분 알파 t(IS · 문턱 %s) · %s · 셈 대상 %d / 짝 %d%s", f2(TH_T, 1), VV,
              sum(D1$st == "셈 대상(문턱 ∧ 제외 표식 없음)"), nrow(D1), if (!IS_ONLY) paste0(" · 속 빈 점 = ", OOS_LAB) else ""))
} else skip("01_pair_increment", "짝 읽기(results/pair_reading_visible.json) 없음")

## =============================================================================================
## 2. 자격 이동 — 등가중(같은 날) → IC 가중 · x = IS 상승 포착률 · y = IS β-통제 알파 t
## =============================================================================================
D2 <- L[is.finite(t1) & is.finite(uc1) & is.finite(t0) & is.finite(uc0)]
if (nrow(D2)) {
  D2[, vf := factor(fifelse(q1 %in% TRUE, "IC 가중 자격 통과", fifelse(q1 %in% FALSE, "IC 가중 자격 미달", "미시험")), levels = c("IC 가중 자격 통과", "IC 가중 자격 미달", "미시험"))]
  xr <- range(c(D2$uc0, D2$uc1, TH_UC)); yr <- range(c(D2$t0, D2$t1, TH_T, 0)); xp <- diff(xr) * 0.12; yp <- diff(yr) * 0.12
  n1 <- sum(D2$q1 %in% TRUE); n0 <- sum(D2$q0 %in% TRUE)
  g <- ggplot(D2) +
    annotate("rect", xmin = TH_UC, xmax = Inf, ymin = TH_T, ymax = Inf, fill = C_PASS, alpha = 0.07) +
    annotate("text", x = Inf, y = Inf, label = "자격 영역", hjust = 1.1, vjust = 1.6, family = FAM, size = 3.6, colour = C_PASS) +
    geom_hline(yintercept = TH_T, linetype = "dashed", colour = INK2, linewidth = 0.45) +
    geom_vline(xintercept = TH_UC, linetype = "dashed", colour = INK2, linewidth = 0.45) +
    geom_hline(yintercept = 0, colour = "#c3c2b7", linewidth = 0.4) +
    geom_segment(aes(x = uc0, y = t0, xend = uc1, yend = t1), colour = MUTED, linewidth = 0.5, arrow = arrow(length = unit(5, "pt"), type = "closed")) +
    geom_point(aes(uc0, t0, shape = "등가중(같은 날 재측정)"), size = 2.6, colour = C_T0, stroke = 1) +
    geom_point(aes(uc1, t1, colour = vf), size = 3.6) +
    ggrepel::geom_text_repel(aes(uc1, t1, label = lin_lab(lineage)), family = FAM, size = 3.7, colour = INK, seed = 7, box.padding = 0.45,
                             point.padding = 0.3, min.segment.length = 0.2, segment.colour = MUTED, max.overlaps = 50) +
    scale_colour_manual(values = c("IC 가중 자격 통과" = C_PASS, "IC 가중 자격 미달" = C_FAIL, "미시험" = C_NA), drop = TRUE) +
    scale_shape_manual(values = c("등가중(같은 날 재측정)" = 1)) +
    scale_x_continuous(limits = c(xr[1] - xp, xr[2] + xp), labels = function(x) f2(x, 2)) + scale_y_continuous(limits = c(yr[1] - yp, yr[2] + yp)) +
    guides(colour = guide_legend(order = 1), shape = guide_legend(order = 2)) +
    LB(7.2, 12, title = "자격 이동 — 등가중 → IC 가중(같은 카테고리 · 같은 날)",
         subtitle = paste0(RULE_LINE, "\n화살표 = 같은 카테고리의 등가중 엔진(속 빈 점) → IC 가중 엔진(색 점) · ", IS_LAB,
                           "\n자격 통과: IC 가중 ", n1, " / ", nrow(D2), " · 등가중(같은 날) ", n0, " / ", nrow(D2), " · * = 저위험 카테고리", partial_note),
         x = "IS 상승 포착률(강세 국면 중앙값 · KOSPI200 대비)", y = "IS β-통제 알파 t(NW)",
         caption = paste0("출처: results/", if (IS_ONLY) "evaluation_visible" else "verdict", ".json(round_core v3 판정 표 · IC 가중 = 변형 엔진 · 등가중 = 짝 기준 엔진)\n", STD_CAP)) +
    th() + theme(legend.box = "horizontal")
  add(save_png(g, "02_qualification_shift.png", 7.2),
      sprintf("자격 이동 지도 — 등가중 → IC 가중(같은 날 측정) · IS 상승 포착률 × β-통제 알파 t · 자격 통과 IC 가중 %d · 등가중 %d / %d", n1, n0, nrow(D2)))
} else skip("02_qualification_shift", "판정 표의 알파 t · 상승 포착률 없음 — 평가 전")

## =============================================================================================
## 3. 누적 상대 성과 — IC 가중 ÷ 등가중(같은 카테고리)
## =============================================================================================
RW <- rbindlist(lapply(unique(L$lineage), function(ln) {
  a <- SR[lineage == ln & role == "variant", .(date, r1 = ret_net)]; b <- SR[lineage == ln & role == "reference", .(date, r0 = ret_net)]
  x <- merge(a, b, by = "date")[order(date)]; if (!nrow(x)) return(NULL)
  x[, rel := cumprod(1 + r1) / cumprod(1 + r0)]
  rbind(data.table(date = x$date[1] - 1L, rel = 1), x[, .(date, rel)])[, lineage := ln]
}))
if (nrow(RW)) {
  endv <- RW[, .(is_end = rel[max(which(date <= TAU), 1L)], last = rel[.N]), by = lineage]
  mult <- function(x) ifelse(is.finite(x), sprintf("×%.2f", x), "–")
  plab <- setNames(sprintf("%s · IS 끝 %s%s", lin_lab(endv$lineage), mult(endv$is_end), if (IS_ONLY) "" else paste0(" · 자료 끝 ", mult(endv$last))), endv$lineage)
  lv <- intersect(ORD, endv$lineage)
  RW[, panel := factor(plab[lineage], levels = plab[lv])]
  g <- ggplot(RW, aes(date, rel)) +
    geom_hline(yintercept = 1, colour = "#c3c2b7", linewidth = 0.3) +
    geom_line(colour = C_T1, linewidth = 0.55) +
    facet_wrap(~panel, ncol = 3) +
    scale_y_log10(labels = function(x) sprintf("×%.2f", x)) +
    scale_x_date(breaks = as.Date(c("2000-01-01", "2010-01-01", "2020-01-01")), date_labels = "%Y") +
    LB(7.6, 11, title = "누적 상대 성과 — IC 가중 ÷ 등가중(같은 카테고리)",
         subtitle = paste0("값 = IC 가중 엔진 누적 순가치 ÷ 같은 카테고리 등가중 엔진 누적 순가치(겹치는 거래일 · 로그 축) · ×1 = 같은 성과\n",
                           "위로 갈수록 시점별 IC 가중이 등가중을 이긴 것 · 패널 순서 = IS 짝 증분 t 내림차순",
                           if (!IS_ONLY) paste0("\n음영 = ", OOS_LAB, " · 점선 = IS/OOS 경계 ", format(TAU)) else "", partial_note),
         x = NULL, y = "상대 누적 가치(로그)",
         caption = paste0("출처: 산출물 03_period_returns.csv(ret_net · 15bps 순) — 일별 복리 · 기술 통계 · 판정 아님(판정 = 짝 증분 알파 t · 1번 그림)\n", STD_CAP)) +
    th(11) + theme(strip.text = element_text(size = 9.5, colour = INK, hjust = 0), panel.spacing = unit(8, "pt"), axis.text = element_text(size = 8))
  if (!IS_ONLY && is.finite(DATA_END) && DATA_END > TAU)
    g <- g + annotate("rect", xmin = TAU, xmax = DATA_END, ymin = 0, ymax = Inf, fill = TEST_FILL, alpha = 0.7) +
      geom_vline(xintercept = TAU, colour = MUTED, linewidth = 0.3, linetype = "dashed")
  add(save_png(g, "03_relative_wealth.png", 10.2, w = 7.6),
      sprintf("누적 상대 성과 — IC 가중 ÷ 등가중 %d 짝(로그 축 · ×1 = 같은 성과)%s", length(lv), if (!IS_ONLY) paste0(" · 음영 = ", OOS_LAB) else ""))
} else skip("03_relative_wealth", "두 엔진이 모두 측정된 짝이 없다")

## =============================================================================================
## 4. 누적 수익 — IC 가중 · 등가중 · KOSPI200
## =============================================================================================
if (nrow(SR)) {
  N4 <- rbindlist(lapply(unique(L$lineage), function(ln) {
    a <- SR[lineage == ln & role == "variant"]; b <- SR[lineage == ln & role == "reference"]
    out <- list()
    if (nrow(a)) out[[1]] <- rbind(data.table(date = a$date[1] - 1L, v = 1), a[, .(date, v = nav_net)])[, who := "IC 가중"]
    if (nrow(b)) out[[2]] <- rbind(data.table(date = b$date[1] - 1L, v = 1), b[, .(date, v = nav_net)])[, who := "등가중(같은 날)"]
    k <- if (nrow(a)) a else b
    if (nrow(k)) out[[3]] <- rbind(data.table(date = k$date[1] - 1L, v = 1), k[, .(date, v = benchmark_nav)])[, who := "KOSPI200"]
    if (!length(out)) return(NULL)
    rbindlist(out)[, lineage := ln]
  }))
  e4 <- N4[, .(v = v[.N]), by = .(lineage, who)]
  e4w <- dcast(e4, lineage ~ who, value.var = "v")
  gx <- function(col) if (col %in% names(e4w)) e4w[[col]] else rep(NA_real_, nrow(e4w))
  mul <- function(x) ifelse(!is.finite(x), "–", paste0(ifelse(x < 1, formatC(x, format = "f", digits = 2), formatC(x, format = "f", digits = 1)), "x"))
  plab4 <- setNames(sprintf("%s\nIC %s · 등가중 %s · 시장 %s", lin_lab(e4w$lineage), mul(gx("IC 가중")), mul(gx("등가중(같은 날)")), mul(gx("KOSPI200"))), e4w$lineage)
  lv4 <- intersect(ORD, e4w$lineage)
  N4[, panel := factor(plab4[lineage], levels = plab4[lv4])]
  N4[, who := factor(who, levels = c("IC 가중", "등가중(같은 날)", "KOSPI200"))]
  g <- ggplot(N4, aes(date, v, colour = who, linetype = who)) +
    geom_hline(yintercept = 1, colour = "#c3c2b7", linewidth = 0.25) +
    geom_line(linewidth = 0.5) +
    facet_wrap(~panel, ncol = 3) +
    scale_y_log10(breaks = 10^(-3:4), labels = function(x) paste0(trimws(formatC(x, format = "fg", digits = 3, big.mark = ",")), "x")) +
    scale_x_date(breaks = as.Date(c("2000-01-01", "2010-01-01", "2020-01-01")), date_labels = "%Y") +
    scale_colour_manual(values = c("IC 가중" = C_T1, "등가중(같은 날)" = C_T0, "KOSPI200" = C_BENCH)) +
    scale_linetype_manual(values = c("IC 가중" = "solid", "등가중(같은 날)" = "22", "KOSPI200" = "solid")) +
    LB(7.6, 11, title = "누적 수익 — IC 가중 · 등가중 · KOSPI200(15bps 순)",
         subtitle = paste0("로그 축 · 1x = 각 엔진 첫 체결일 직전 · 패널 제목 아래 = ", if (IS_ONLY) "IS 끝" else "자료 끝", " 누적 배수 · 패널 순서 = IS 짝 증분 t 내림차순",
                           if (!IS_ONLY) paste0("\n음영 = ", OOS_LAB, " · 점선 = IS/OOS 경계 ", format(TAU), " · 자료 끝 ", format(DATA_END)) else "", partial_note),
         x = NULL, y = "누적 가치(로그)",
         caption = paste0("출처: 산출물 02_nav.csv(nav_net) · 05_benchmark_returns.csv(benchmark_nav) — 정규화 없이 그대로 · 기술 통계 · 판정 아님\n", STD_CAP)) +
    th(11) + theme(strip.text = element_text(size = 9.2, colour = INK, hjust = 0, lineheight = 1.05), panel.spacing = unit(8, "pt"), axis.text = element_text(size = 8))
  if (!IS_ONLY && is.finite(DATA_END) && DATA_END > TAU)
    g <- g + annotate("rect", xmin = TAU, xmax = DATA_END, ymin = 0, ymax = Inf, fill = TEST_FILL, alpha = 0.7) +
      geom_vline(xintercept = TAU, colour = MUTED, linewidth = 0.3, linetype = "dashed")
  add(save_png(g, "04_cumulative_vs_kospi200.png", 11.0, w = 7.6),
      sprintf("누적 수익 — IC 가중(실선) · 등가중(점선) · KOSPI200(회색) %d 카테고리 · 로그 축%s", length(lv4), if (!IS_ONLY) paste0(" · 음영 = ", OOS_LAB) else ""))
} else skip("04_cumulative_vs_kospi200", "측정 끝난 엔진이 없다")

## =============================================================================================
## 5. 행동 변화 — IC 가중 − 등가중(IS): 상승 포착률 · 위기 하락노출 · β · 크기 성분 · 선택 성분
## =============================================================================================
if (!is.null(PT)) {
  M5 <- c(uc = "Δ 상승 포착률\n(강세 국면 중앙값)", dd = "Δ 위기 하락노출\n(위기 중앙값)", beta = "Δ β", ew = "Δ 크기 성분\n(연율 · 동일가중 − 시총가중)", sel = "Δ 선택 성분\n(연율)")
  B5 <- rbind(L[, .(lineage, m = "uc", v = uc_t1 - uc_t0, tag = strength_loss %in% TRUE)],
              L[, .(lineage, m = "dd", v = dd_med_t1 - dd_med_t0, tag = crisis_worse %in% TRUE)],
              L[, .(lineage, m = "beta", v = beta_t1 - beta_t0, tag = FALSE)],
              L[, .(lineage, m = "ew", v = ew_cw_t1 - ew_cw_t0, tag = size_tilt %in% TRUE)],
              L[, .(lineage, m = "sel", v = selection_t1 - selection_t0, tag = size_tilt %in% TRUE)])
  B5 <- B5[is.finite(v)]
  if (nrow(B5)) {
    good <- function(m, v) fcase(m %in% c("uc", "sel"), v >= 0, m == "dd", v <= 0, m == "ew", v <= 0, default = NA)
    B5[, col := fifelse(tag, "제외 표식", fifelse(m == "beta", "참고", fifelse(good(m, v), "개선 쪽", "악화 쪽")))]
    B5[, mf := factor(M5[m], levels = M5)]
    B5[, catr := factor(lineage, levels = rev(ORD))]
    B5[, txt := ifelse(m %in% c("ew", "sel"), mm(sprintf("%+.1f%%", round(100 * v, 1) + 0)), sgn(round(v, 2) + 0, 2))]   # + 0 = −0.0 표기 막기
    g <- ggplot(B5, aes(v, catr)) +
      geom_vline(xintercept = 0, colour = "#c3c2b7", linewidth = 0.4) +
      geom_segment(aes(x = 0, xend = v, yend = catr, colour = col), linewidth = 0.8) +
      geom_point(aes(colour = col), size = 2.6) +
      geom_text(aes(label = txt, hjust = ifelse(v >= 0, -0.25, 1.25)), family = FAM, size = 2.6, colour = INK2) +
      facet_wrap(~mf, nrow = 1, scales = "free_x") +
      scale_colour_manual(values = c("개선 쪽" = C_GOOD, "악화 쪽" = C_BAD, "제외 표식" = C_TAG, "참고" = MUTED)) +
      scale_y_discrete(labels = function(x) lin_lab(x)) +
      scale_x_continuous(expand = expansion(mult = 0.45)) +
      LB(10.4, 10.5, title = "행동 변화 — IC 가중 − 등가중(IS · 같은 카테고리)",
           subtitle = paste0("상승 포착률 ↑ · 위기 하락노출 ↓ · 선택 성분 ↑ = 개선 쪽(파랑) · 크기 성분 ↑ = 소형주 쪽 이동 · β = 참고(회색)\n",
                             "주황 = 결합 개선 판정에서 그 짝을 빼는 제외 표식(상승 포착률 손실 · 위기 하락노출 악화 · 소형주 쪽 이동) · ", IS_LAB, partial_note),
           x = NULL, y = NULL,
           caption = paste0("출처: results/pair_reading_visible.json(IS 진단 패킷 — 행동 카드 · 노출 분해 · 계약 산출 · 손계산 없음)\n",
                            "위기 하락노출 = 위기 구간 전략 낙폭 ÷ 시장 낙폭(LT 20/20 위기 중앙값) · 크기 성분 = 동일가중 − 시총가중 수익 차 · 선택 성분 = 노출 분해의 종목 선택 몫")) +
      th(10.5) + theme(panel.grid.major.y = element_blank(), axis.text.y = element_text(size = 10, colour = INK), strip.text = element_text(size = 9, colour = INK, lineheight = 1.05),
                       axis.text.x = element_text(size = 7.5), panel.spacing = unit(10, "pt"))
    add(save_png(g, "05_behavior_delta.png", 5.6, w = 10.4),
        "행동 변화(IC 가중 − 등가중 · IS) — 상승 포착률 · 위기 하락노출 · β · 크기 성분 · 선택 성분 · 주황 = 결합 개선 판정의 제외 표식")
  } else skip("05_behavior_delta", "짝 행동 값이 비었다")
} else skip("05_behavior_delta", "짝 읽기 없음")

## =============================================================================================
## 6. 위기별 하락노출 변화 — 위기(행) × 카테고리(열) · IC 가중 − 등가중
## =============================================================================================
ev_names <- function(peaks) {
  reg <- rj(file.path(ROOT, "06_Registry/crisis_event_names.json")); out <- rep("", length(peaks))
  if (is.null(reg) || !length(reg$events)) return(out)
  tol <- as.integer(reg$match$tolerance_months %||% 2L)
  mon <- function(d) { d <- as.Date(d); as.integer(format(d, "%Y")) * 12L + as.integer(format(d, "%m")) }
  em <- vapply(reg$events, function(e) mon(paste0(e$peak, "-01")), integer(1)); en <- vapply(reg$events, function(e) as.character(e$name), character(1))
  for (i in seq_along(peaks)) { gp <- abs(em - mon(peaks[i])); if (length(gp) && min(gp) <= tol) out[i] <- en[which.min(gp)] }
  out
}
crises_of <- function(code) {
  b <- if (IS_ONLY) rj(file.path(RES, code, "visible", "diagnosis_packet.json"))$behavior else rj(file.path(RES, code, "full", "behavior_card.json"))
  if (is.null(b) || !length(b$crises)) return(NULL)
  rbindlist(lapply(b$crises, function(z) data.table(peak = as.character(z$peak_date), trough = as.character(z$trough_date %||% NA_character_),
                                                    win = as.character(z$window %||% "visible"), dd = num(z$dd_capture))))
}
C6 <- rbindlist(lapply(seq_len(nrow(L)), function(i) {
  a <- if (!is.na(L$code1[i])) crises_of(L$code1[i]) else NULL; b <- if (!is.na(L$code0[i])) crises_of(L$code0[i]) else NULL
  if (is.null(a) || is.null(b)) return(NULL)
  x <- merge(a[, .(peak, trough, win, d1 = dd)], b[, .(peak, d0 = dd)], by = "peak"); if (!nrow(x)) return(NULL)
  x[, `:=`(lineage = L$lineage[i], dlt = d1 - d0)]
}), fill = TRUE)
if (nrow(C6)) {
  if (IS_ONLY) C6 <- C6[is.na(trough) | as.Date(trough) <= TAU | win == "visible"]
  key <- unique(C6[, .(peak, trough, win)])[order(as.Date(peak))][!duplicated(peak)]
  key[, nm := ev_names(peak)]
  key[, lab := paste0(format(as.Date(peak), "%y.%m"), ifelse(is.na(trough), "", paste0("~", format(as.Date(trough), "%y.%m"))), ifelse(nzchar(nm), paste0(" ", nm), ""))]
  key[, wf := factor(fifelse(win == "visible", "IS", fifelse(win == "straddle", "경계 걸침", "OOS")), levels = c("IS", "경계 걸침", "OOS"))]
  C6 <- merge(C6, key[, .(peak, lab, wf)], by = "peak")
  C6[, `:=`(catf = factor(lineage, levels = ORD), labf = factor(lab, levels = rev(key$lab)), txt = s2(dlt, 2))]
  B6 <- CJ(lineage = intersect(ORD, unique(C6$lineage)), peak = key$peak)[!C6, on = c("lineage", "peak")]      # 빈칸(그 위기 앞 신호 개시 · 행동 카드 제외)
  B6 <- merge(B6, key[, .(peak, lab, wf)], by = "peak")
  B6[, `:=`(catf = factor(lineage, levels = ORD), labf = factor(lab, levels = rev(key$lab)))]
  g <- ggplot(C6, aes(catf, labf)) +
    geom_tile(aes(fill = dlt), colour = "white", linewidth = 0.8) +
    geom_tile(data = B6, fill = BLANK, colour = "white", linewidth = 0.8) +
    geom_text(data = B6, label = "–", family = FAM, size = 2.7, colour = MUTED) +
    geom_text(aes(label = txt), family = FAM, size = 2.7, colour = INK) +
    scale_fill_gradient2(low = C_POS, mid = C_MID, high = C_NEG, midpoint = 0, limits = c(-0.5, 0.5), oob = scales::squish,
                         name = "Δ 하락노출(IC 가중 − 등가중)", breaks = c(-0.5, -0.25, 0, 0.25, 0.5), labels = c("≤−.50", "−.25", "0", "+.25", "≥+.50")) +
    scale_x_discrete(labels = function(x) lin_lab(x)) +
    facet_grid(wf ~ ., scales = "free_y", space = "free_y", switch = "y") +
    LB(7.8, 11, title = "위기별 하락노출 변화 — IC 가중 − 등가중",
         subtitle = paste0("값 = 위기 구간 낙폭 ÷ KOSPI200 낙폭(하락노출)의 차이 · 파랑(음수) = IC 가중이 그 위기에서 덜 잃었다 · 빨강 = 더 잃었다\n",
                           "위기 = KOSPI200 Lunde-Timmermann 20/20 첫 통과 구간 · 귀속 전 원값(β · 크기 미통제) — 방어 근거 아님\n열 순서 = IS 짝 증분 t 내림차순",
                           if (!IS_ONLY) paste0(" · 아래 면 = ", OOS_LAB) else paste0(" · ", IS_LAB), partial_note),
         x = NULL, y = NULL,
         caption = paste0("출처: results/<엔진>/", if (IS_ONLY) "visible/diagnosis_packet.json(IS 행동 카드)" else "full/behavior_card.json(행동 카드 · 계약 산출)",
                          "::crises[].dd_capture · 사건명 = 06_Registry/crisis_event_names.json", if (nrow(B6)) " · – = 그 위기 전 신호 개시 또는 행동 카드 제외" else "")) +
    th(11) + theme(panel.grid = element_blank(), panel.grid.major = element_blank(), axis.text.x = element_text(angle = 50, hjust = 1, vjust = 1, size = 10, colour = INK),
                   axis.text.y = element_text(size = 9, colour = INK), strip.text.y.left = element_text(angle = 0, size = 9.5, colour = INK2), strip.placement = "outside",
                   legend.key.width = unit(26, "pt"), legend.key.height = unit(8, "pt"))
  add(save_png(g, "06_crisis_delta_heatmap.png", 3.4 + 0.42 * nrow(key), w = 7.8),
      sprintf("위기별 하락노출 변화(IC 가중 − 등가중) — 위기 %d개 × 카테고리 · 파랑 = IC 가중이 덜 잃음 · 귀속 전 원값 · 방어 근거 아님", nrow(key)))
} else skip("06_crisis_delta_heatmap", "행동 카드 위기 표 없음 — 평가 전")

## =============================================================================================
## 7. 카테고리 가중 추이 — 토탈 엔진이 시점마다 어느 카테고리에 무게를 실었나(IS · 엔진과 같은 식)
## =============================================================================================
WT_P <- file.path(RES, "weight_trace_visible.json")
WT <- rj(WT_P)
if (is.null(WT)) WT <- tryCatch({
  t0 <- Sys.time()
  spT <- rc_json_read(file.path(ROOT, "04_Research/strategies/FC_TOTAL_ICW/own_spec.json"))
  M <- rbindlist(lapply(spT$core$members, function(m) data.table(id = as.character(m$id), family = as.character(m$family), s_reg = as.numeric(m$s_reg))))
  FC <- new.env(parent = globalenv()); sys.source(file.path(ROOT, "02_Infrastructure/factor_db/factor_combinable.R"), envir = FC, keep.source = FALSE)
  IC <- new.env(parent = globalenv())
  local({ owd <- setwd(file.path(ROOT, "02_Infrastructure")); on.exit(setwd(owd), add = TRUE)
    invisible(utils::capture.output(suppressMessages({ sys.source(file.path(ROOT, "02_Infrastructure", "config.R"), envir = IC, keep.source = FALSE)
      sys.source(file.path(ROOT, "02_Infrastructure", "factor_db", "factor_db_connector.R"), envir = IC, keep.source = FALSE) }))) })
  cfg <- FC$fc_config(ROOT)
  meta <- jsonlite::fromJSON(file.path(ROOT, cfg$storage$dir, cfg$storage$meta_file), simplifyVector = TRUE)
  START <- as.Date(local({ e <- new.env(parent = globalenv()); sys.source(file.path(ROOT, "02_Infrastructure/contracts/measurement_axis.R"), envir = e, keep.source = FALSE); e$ma_epoch(root = ROOT)$start_date }))
  MM <- as.data.table(meta$months)[, asof := as.Date(asof)][asof >= START & asof <= TAU]
  fam_rows <- list(); mem_rows <- list()
  for (i in seq_len(nrow(MM))) {
    d <- MM$asof[i]
    r <- NULL; invisible(utils::capture.output(r <- FC$fc_load_month(d, direction = "registry", factors = M$id, missing = "na", dedup = FALSE, family = FALSE)))
    m <- as.data.table(r$meta)[, .(id = Factor_Name, s_reg_v = s_reg)]
    icr <- NULL; invisible(utils::capture.output(icr <- IC$compute_rolling_ic_all(d, 36L, 120L)))
    X <- merge(M, m, by = "id")
    X[, a := s_reg * icr$ICIR[match(id, icr$Factor_Name)]][, w := fifelse(is.finite(a) & a > 0, a, 0)]
    F <- X[, .(W = mean(w), n = .N, n_pos = sum(w > 0), effn = if (sum(w) > 0) sum(w)^2 / sum(w^2) else NA_real_, sw = sum(w)), by = family]
    tot <- sum(F$W)
    fam_rows[[i]] <- F[, .(asof = format(d), family, share = if (tot > 0) W / tot else NA_real_, n, n_pos, effn)]
    Y <- X[id %in% MISDIR]
    if (nrow(Y)) mem_rows[[i]] <- merge(Y[, .(id, family, w)], F[, .(family, sw, n)], by = "family")[, .(asof = format(d), id, family, w, share = fifelse(sw > 0, w / sw, NA_real_), base = 1 / n)]
  }
  out <- list(schema = "p1r04_weight_trace_visible_v1", audience = "IS(τ_D 이전 as-of) 만 · 성과 아님 — 엔진과 같은 식으로 다시 낸 카테고리 가중(토탈 엔진)",
              rule = "w = max(s_reg × ICIR(as-of 36~120개월), 0) · W_f = 그 달 결합용 뷰에 있는 카테고리 구성원 가중 평균 · 몫 = W_f / Σ W_f(Σ = 0 이면 그 달 등가중 점수 · 몫 없음)",
              window = c(format(min(MM$asof)), format(max(MM$asof))), months = rbindlist(fam_rows), misdirected_members = rbindlist(mem_rows),
              elapsed_sec = round(as.numeric(difftime(Sys.time(), t0, units = "secs")), 1))
  lk <- rc_after_tau_leaks(out, TAU); if (length(lk)) stop("가중 추적 출력에 τ_D 뒤 날짜: ", paste(head(lk, 3), collapse = ","))
  rc_json_write(out, WT_P); rj(WT_P)
}, error = function(e) { cat("[p1r04_charts] 가중 추적 실패: ", conditionMessage(e), "\n", file = stderr()); NULL })
FW <- rows_dt(WT$months)
if (!is.null(FW) && nrow(FW)) {
  FW[, `:=`(asof = as.Date(asof), share = suppressWarnings(as.numeric(share)))]
  nf <- length(unique(FW$family)); eq <- 1 / nf
  Y7 <- FW[is.finite(share), .(ratio = mean(share) / eq), by = .(family, yr = format(asof, "%Y"))]
  A7 <- FW[is.finite(share), .(ratio = mean(share) / eq), by = family][, yr := "IS 평균"]
  D7 <- rbind(Y7, A7)
  ford <- A7[order(-ratio)]$family
  D7[, `:=`(ff = factor(family, levels = rev(ford)), yf = factor(yr, levels = c(sort(unique(Y7$yr)), "IS 평균")))]
  D7[, txt := ifelse(yr == "IS 평균", sprintf("×%.1f", ratio), "")]
  MW <- rows_dt(WT$misdirected_members)
  mis_line <- if (!is.null(MW) && nrow(MW)) {
    MW[, `:=`(w = as.numeric(w), share = as.numeric(share), base = as.numeric(base))]
    s <- MW[, .(zero = mean(w <= 0), med = stats::median(share, na.rm = TRUE), base = stats::median(base, na.rm = TRUE)), by = .(id, family)]
    paste0("방향 재판정 불일치 구성원의 IS 가중: ", paste(sprintf("%s(%s) 가중 0 인 달 %s · 카테고리 안 몫 중앙값 %s(등가중 %s)", s$id, CATN[s$family], pct(s$zero),
                                                       pct(s$med, 1), pct(s$base, 1)), collapse = " · "))
  } else ""
  g <- ggplot(D7, aes(yf, ff)) +
    geom_tile(aes(fill = ratio), colour = "white", linewidth = 0.5) +
    geom_text(aes(label = txt), family = FAM, size = 3, colour = INK) +
    geom_vline(xintercept = length(unique(Y7$yr)) + 0.5, colour = INK2, linewidth = 0.4) +
    scale_fill_gradient2(low = C_NEG, mid = C_MID, high = C_POS, midpoint = 1, limits = c(0, 3), oob = scales::squish, name = "몫 ÷ 등가중 몫",
                         breaks = c(0, 1, 2, 3), labels = c("0", "×1", "×2", "≥×3")) +
    scale_y_discrete(labels = function(x) lin_lab(x)) +
    LB(9.6, 10.5, cap_pt = 7.4, title = "카테고리 가중 추이 — 토탈 IC 가중 엔진(IS)",
         subtitle = paste0("값 = 그해 달마다 카테고리가 받은 결합 가중 몫의 평균 ÷ 등가중 몫(1/", nf, ") · 파랑 = 등가중보다 무겁게 · 빨강 = 가볍게(0 = 가중 0)\n",
                           "가중 = 카테고리 구성원의 as-of ICIR 양의 부분 평균(이력 36개월 미만 · 등록 방향과 반대로 움직인 팩터 = 0) · 엔진과 같은 식으로 다시 냈다 · ",
                           sprintf("%s ~ %s", WT$window[[1]], WT$window[[2]])),
         x = NULL, y = NULL,
         caption = paste0("출처: results/weight_trace_visible.json(결합용 뷰 · 정본 IC 접근자 compute_rolling_ic_all · 성과 무참조 · IS 달만)",
                          if (nzchar(mis_line)) paste0("\n", mis_line) else "")) +
    th(10.5) + theme(panel.grid = element_blank(), panel.grid.major = element_blank(), axis.text.x = element_text(angle = 60, hjust = 1, vjust = 1, size = 8),
                     axis.text.y = element_text(size = 10, colour = INK), legend.key.width = unit(26, "pt"), legend.key.height = unit(8, "pt"),
                     plot.caption = element_text(size = 7.4, colour = MUTED, hjust = 0, lineheight = 1.1))
  add(save_png(g, "07_category_weight_trace.png", 5.8, w = 9.6),
      paste0("카테고리 가중 추이 — 토탈 IC 가중 엔진이 해마다 각 카테고리에 실은 무게(등가중 대비 배수 · IS)", if (nzchar(mis_line)) " · 방향 재판정 불일치 구성원 가중 병기" else ""))
} else skip("07_category_weight_trace", "가중 추적 없음")

## =============================================================================================
## 8. 포트폴리오 차이 — 보유 겹침 · 월 수익 상관(IC 가중 vs 등가중)
## =============================================================================================
hold <- function(dir) { h <- tryCatch(fread(file.path(dir, "04_holdings.csv"), select = c("date", "ticker")), error = function(e) NULL); if (is.null(h)) return(NULL)
  h[, date := as.Date(date)]; if (IS_ONLY) h <- h[date <= TAU]; unique(h) }
win_of <- function(d) fifelse(d <= TAU, "IS", "OOS")
P8 <- rbindlist(lapply(seq_len(nrow(L)), function(i) {
  if (is.na(L$art1[i]) || is.na(L$art0[i])) return(NULL)
  h1 <- hold(L$art1[i]); h0 <- hold(L$art0[i]); if (is.null(h1) || is.null(h0)) return(NULL)
  ov <- merge(h1[, .(n1 = .N), by = date], merge(h1, h0, by = c("date", "ticker"))[, .(both = .N), by = date], by = "date", all.x = TRUE)
  ov[is.na(both), both := 0L]; ov[, w := win_of(date)]
  a <- SR[lineage == L$lineage[i] & role == "variant", .(r1 = prod(1 + ret_net) - 1), by = .(ym = format(date, "%Y-%m"), w = win_of(date))]
  b <- SR[lineage == L$lineage[i] & role == "reference", .(r0 = prod(1 + ret_net) - 1), by = .(ym = format(date, "%Y-%m"), w = win_of(date))]
  cc <- merge(a, b, by = c("ym", "w"))[, .(rho = if (.N >= 12) stats::cor(r1, r0) else NA_real_), by = w]
  merge(ov[, .(overlap = mean(both / n1)), by = w], cc, by = "w", all = TRUE)[, lineage := L$lineage[i]]
}), fill = TRUE)
if (nrow(P8)) {
  D8 <- melt(P8, id.vars = c("lineage", "w"), measure.vars = c("overlap", "rho"), variable.name = "m", value.name = "v")[is.finite(v)]
  D8[, mf := factor(fifelse(m == "overlap", "보유 겹침(리밸일 평균 · IC 가중 종목 중 등가중에도 있는 몫)", "월 수익 상관"),
                    levels = c("보유 겹침(리밸일 평균 · IC 가중 종목 중 등가중에도 있는 몫)", "월 수익 상관"))]
  D8[, catr := factor(lineage, levels = rev(ORD))]
  D8[, wf := factor(fifelse(w == "IS", IS_LAB, OOS_LAB), levels = c(IS_LAB, OOS_LAB))]
  g <- ggplot(D8, aes(v, catr, fill = wf)) +
    geom_col(position = position_dodge2(width = 0.75, reverse = TRUE), width = 0.7) +
    geom_text(aes(label = s2(v, 2)), position = position_dodge2(width = 0.75, reverse = TRUE), hjust = -0.15, family = FAM, size = 2.7, colour = INK) +
    facet_wrap(~mf, nrow = 1) +
    scale_fill_manual(values = setNames(c(C_T1, "#b9b7ae"), c(IS_LAB, OOS_LAB)), drop = TRUE) +
    scale_x_continuous(limits = c(0, 1.15), breaks = c(0, 0.25, 0.5, 0.75, 1), labels = function(x) f2(x, 2)) +
    scale_y_discrete(labels = function(x) lin_lab(x)) +
    LB(9.0, 10.5, title = "포트폴리오 차이 — IC 가중 vs 등가중(같은 카테고리)",
         subtitle = paste0("보유 겹침 = 리밸일마다 IC 가중 25종 중 등가중 25종에도 든 비율의 평균 · 1.00 = 같은 포트폴리오\n",
                           "겹침이 낮고 상관이 낮을수록 시점별 IC 가중이 실제로 다른 종목을 골랐다 · 패널 순서 = IS 짝 증분 t 내림차순", partial_note),
         x = NULL, y = NULL,
         caption = paste0("출처: 산출물 04_holdings.csv(date · ticker) · 03_period_returns.csv(ret_net → 월 복리) — 기술 통계 · 판정 아님\n", STD_CAP)) +
    th(10.5) + theme(panel.grid.major.y = element_blank(), axis.text.y = element_text(size = 10, colour = INK), strip.text = element_text(size = 9.5, colour = INK))
  add(save_png(g, "08_portfolio_difference.png", 5.4, w = 9.0),
      "포트폴리오 차이 — 보유 겹침 · 월 수익 상관(IC 가중 vs 등가중) · 낮을수록 IC 가중이 다른 종목을 골랐다")
} else skip("08_portfolio_difference", "보유 · 수익 산출물이 짝으로 없다")

## =============================================================================================
## 9. 성적표 — 카테고리별 IC 가중 · 등가중 · 짝 증분
## =============================================================================================
if (nrow(L) && (any(is.finite(L$t1)) || any(is.finite(L$d_t_vis)))) {
  T9 <- L[match(ORD, lineage)]
  vlab <- function(q) fifelse(q %in% TRUE, "통과", fifelse(q %in% FALSE, "미달", "–"))
  meas9 <- T9$status %in% "evaluated" & !T9$gap
  tg <- ifelse(!meas9, ifelse(T9$gap %in% TRUE, "값 없음", "미측정"),
               trimws(paste0(ifelse(T9$strength_loss %in% TRUE, "참여↓ ", ""), ifelse(T9$crisis_worse %in% TRUE, "위기↑ ", ""), ifelse(T9$size_tilt %in% TRUE, "소형주", ""))))
  dtv <- ifelse(T9$same %in% TRUE, "0(같은 산출)", mm(f2(T9$d_t_vis, 2)))
  cols <- list(list(h = "카테고리", v = lin_lab(T9$lineage), w = 1.15),
               list(h = "IC 가중\n자격", v = vlab(T9$q1), w = 0.7), list(h = "등가중\n자격", v = vlab(T9$q0), w = 0.7),
               list(h = "알파 t\nIC 가중", v = mm(f2(T9$t1, 2)), w = 0.75), list(h = "알파 t\n등가중", v = mm(f2(T9$t0, 2)), w = 0.75),
               list(h = "짝 증분\n알파 t", v = dtv, w = 0.85), list(h = "짝 증분\n알파 연율", v = mm(pct(T9$d_alpha_ann_vis, 1)), w = 0.8),
               list(h = "상승 포착률\nIC / 등가중", v = paste0(f2(T9$uc_t1, 2), " / ", f2(T9$uc_t0, 2)), w = 1.05),
               list(h = "위기 하락노출\nIC / 등가중", v = paste0(f2(T9$dd_med_t1, 2), " / ", f2(T9$dd_med_t0, 2)), w = 1.05),
               list(h = "β\nIC 가중", v = f2(T9$b1, 2), w = 0.55), list(h = "제외\n표식", v = ifelse(nzchar(tg), tg, "–"), w = 1.35))
  if (!IS_ONLY) cols <- c(cols, list(list(h = "등급\nIC 가중*", v = ifelse(is.na(T9$grade1), "–", T9$grade1), w = 0.6),
                                     list(h = "OOS 알파 t\nIC 가중*", v = mm(f2(T9$tt1, 2)), w = 0.8),
                                     list(h = "OOS 짝\n증분 t*", v = mm(f2(T9$dt_test, 2)), w = 0.7)))
  xw <- vapply(cols, `[[`, numeric(1), "w"); xs <- cumsum(xw) - xw / 2; nr <- nrow(T9); nc <- length(cols)
  G <- rbindlist(lapply(seq_len(nc), function(j) data.table(x = xs[j], y = rev(seq_len(nr)), lab = cols[[j]]$v, j = j)))
  G[, col := INK]
  G[j %in% c(2, 3) & lab == "통과", col := C_PASS]; G[j %in% c(2, 3) & lab == "미달", col := C_FAIL]
  dv <- T9$d_t_vis; G[j == 6, col := ifelse(is.finite(dv[nr + 1 - y]) & dv[nr + 1 - y] >= TH_T, C_PASS, INK)]
  G[j == 11 & lab != "–", col := C_TAG]; G[j == 11 & lab %in% c("미측정", "값 없음"), col := MUTED]
  if (!IS_ONLY) G[j > 11, col := MUTED]
  H <- data.table(x = xs, y = nr + 1.05, lab = vapply(cols, `[[`, character(1), "h"))
  band <- data.table(y = seq_len(nr))[y %% 2 == 0]
  g <- ggplot() +
    geom_rect(data = band, aes(xmin = 0, xmax = sum(xw), ymin = y - 0.5, ymax = y + 0.5), fill = BLANK) +
    geom_text(data = G, aes(x, y, label = lab, colour = I(col)), family = FAM, size = 3.0) +
    geom_text(data = H, aes(x, y, label = lab), family = FAM, size = 2.8, colour = INK2, lineheight = 0.9, vjust = 0) +
    geom_hline(yintercept = nr + 0.55, colour = "#c3c2b7", linewidth = 0.4) +
    scale_x_continuous(limits = c(0, sum(xw)), expand = c(0, 0)) + scale_y_continuous(limits = c(0.4, nr + 1.9), expand = c(0, 0)) +
    LB(if (IS_ONLY) 10.4 else 12.4, 10.5, cap_pt = 7.2, title = "P1R04 성적표 — 시점별 IC 가중 결합 vs 등가중 결합(카테고리 14 + 토탈)",
         subtitle = paste0(RULE_LINE, "\n판정: ", VV, " · 행 순서 = IS 짝 증분 t 내림차순 · 파랑 = 문턱 충족 · * 카테고리 = 저위험 · 값은 모두 IS",
                           if (!IS_ONLY) paste0(" · * 열 = 전기간 등급 · ", OOS_LAB) else "", partial_note),
         caption = paste0("출처: results/", if (IS_ONLY) "evaluation_visible" else "verdict", ".json(자격 · 알파 t · β) · results/pair_reading_visible.json(짝 증분 · 행동 · 제외 표식)",
                          if (!IS_ONLY) " · results/<엔진>.json(authoritative_remeasure essence_grade · 등급 v3.4 · 전기간 — 참고) · OOS 짝 증분 = rc_pair_alpha(test)" else "",
                          "\n제외 표식: 참여↓ = 상승 포착률 손실 · 위기↑ = 위기 하락노출 악화 · 소형주 = 크기 성분↑ ∧ 선택 성분↓")) +
    th(10.5) + theme(axis.text = element_blank(), panel.grid = element_blank(), panel.grid.major = element_blank(), axis.title = element_blank(),
                     plot.subtitle = element_text(size = 9, colour = INK2, lineheight = 1.15), plot.caption = element_text(size = 7.2, colour = MUTED, hjust = 0, lineheight = 1.1))
  add(save_png(g, "09_scorecard.png", 2.8 + 0.33 * nr, w = if (IS_ONLY) 10.4 else 12.4),
      paste0("성적표 — 카테고리별 IC 가중 · 등가중 자격 · 알파 t · 짝 증분 · 상승 포착률 · 위기 하락노출 · β · 제외 표식", if (!IS_ONLY) paste0(" · 전기간 등급 · ", OOS_LAB, " 알파 t(보고 전용)") else ""))
} else skip("09_scorecard", "판정 표 · 짝 읽기 없음")

## =============================================================================================
## 10. IC 가중 엔진 초과수익 상관 — IS 월간(KOSPI200 차감) · 결합 재료 지도
## =============================================================================================
S10 <- SR[role == "variant" & date <= TAU]
if (nrow(S10) && length(unique(S10$lineage)) >= 3) {
  M10 <- S10[, .(x = prod(1 + ret_net) - prod(1 + benchmark_ret)), by = .(lineage, ym = format(date, "%Y-%m"))]
  W <- dcast(M10, ym ~ lineage, value.var = "x"); X <- as.matrix(W[, -1]); colnames(X) <- names(W)[-1]
  C <- stats::cor(X, use = "pairwise.complete.obs")
  hc <- stats::hclust(stats::as.dist(1 - C), method = "average"); oe <- colnames(C)[hc$order]
  D <- as.data.table(as.table(C)); setnames(D, c("a", "b", "rho"))
  D[, `:=`(af = factor(as.character(a), levels = oe), bf = factor(as.character(b), levels = rev(oe)))]
  D[as.character(a) == as.character(b), rho := NA_real_]
  off <- C[upper.tri(C)]
  g <- ggplot(D, aes(af, bf, fill = rho)) +
    geom_tile(colour = "white", linewidth = 0.6) +
    geom_text(aes(label = s2(rho, 2)), data = D[is.finite(rho)], family = FAM, size = 2.9, colour = INK) +
    scale_fill_gradient2(low = C_POS, mid = C_MID, high = C_NEG, midpoint = 0, limits = c(-1, 1), name = "상관계수", na.value = BLANK) +
    scale_x_discrete(labels = function(x) lin_lab(x)) + scale_y_discrete(labels = function(x) lin_lab(x)) + coord_fixed() +
    LB(7.2, 11, title = "IC 가중 엔진 초과수익 상관 — IS 월간(KOSPI200 차감)",
         subtitle = sprintf("결합(블렌딩) 재료 지도 — 낮은 상관 = 서로 다른 수익 원천 · %s ~ %s · 계층 군집 순서(거리 = 1 − 상관)\n비대각 중앙값 %s · 범위 %s ~ %s · * = 저위험 카테고리%s",
                            min(M10$ym), format(TAU, "%Y-%m"), f2(stats::median(off), 2), mm(f2(min(off), 2)), mm(f2(max(off), 2)), partial_note),
         x = NULL, y = NULL, caption = "출처: 산출물 03_period_returns.csv(ret_net) · 05_benchmark_returns.csv(benchmark_ret) — 일별 → 월간 복리 · 쌍마다 겹치는 달 · 기술 통계 · 판정 아님") +
    th(11) + theme(panel.grid = element_blank(), panel.grid.major = element_blank(), axis.text.x = element_text(angle = 50, hjust = 1, vjust = 1, size = 10, colour = INK),
                   axis.text.y = element_text(size = 10, colour = INK), legend.key.width = unit(26, "pt"), legend.key.height = unit(8, "pt"))
  add(save_png(g, "10_t1_excess_correlation.png", 8.0),
      sprintf("IC 가중 엔진 초과수익 상관(IS 월간 · KOSPI200 차감) — 블렌딩 재료 지도 · 비대각 중앙값 %s", f2(stats::median(off), 2)))
} else skip("10_t1_excess_correlation", "측정 끝난 IC 가중 엔진이 3개 미만")

## ---- 기록 · 출력 -------------------------------------------------------------------------------
if (length(skipped)) cat(toJSON(list(skipped = skipped), auto_unbox = TRUE), "\n", file = stderr())
rel <- function(p) sub(paste0("^", ROOT, "/"), "", gsub("\\\\", "/", p))
cat(toJSON(lapply(made, function(m) list(file = rel(m$file), caption = m$caption)), auto_unbox = TRUE), "\n")
