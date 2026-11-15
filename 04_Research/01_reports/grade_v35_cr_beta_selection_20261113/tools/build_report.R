## build_report.R — 등급 v3.5 재채점 결과 표 · 차트
##   사전등록 PREREG.md §4(T1~T4) + 부록 1 §4(T1′ · T5 · T2 = 쓰기 뒤 전수)
##   읽는 것 = 계약 산출 · 저장 기록 필드만(등급 · 지표를 새로 계산하지 않는다 — AX-008):
##     data/dryrun_v34_<RUN>.csv · data/dryrun_v35_<RUN>.csv — 쓰기 직전, 같은 자료 판에서 v3.4 계약(교체 전 커밋 사본) · v3.5 계약(운영)으로
##       채점한 드라이런(tools/dryrun_contract.R)
##     data/census_<PRE>.csv — 쓰기 직전 저장 기록 전수 · data/census_<POST>.csv — 쓰기 뒤 전수(tools/census_regrade_set.py)
##     P1R03 결과 사본(results/ · remeasure_seam_20261113/results/)의 artifacts — 이음매 수리 전 측정(재측정본으로 대체된 기록) 표시용
##   환경변수: V35_RUN(드라이런 꼬리표 · 기본 post) · V35_CEN_PRE(쓰기 직전 전수 꼬리표 · 필수) · V35_CEN_POST(쓰기 뒤 전수 꼬리표 · 기본 post)
##   실행: 저장소 루트에서 Rscript 04_Research/01_reports/grade_v35_cr_beta_selection_20261113/tools/build_report.R
suppressPackageStartupMessages({ library(data.table); library(jsonlite); library(ggplot2) })
for (p in c("ragg", "systemfonts", "ggrepel", "patchwork", "scales")) if (!requireNamespace(p, quietly = TRUE)) stop("[v35 report] 패키지 없음: ", p)
ROOT <- sub("/+$", "", gsub("\\\\", "/", Sys.getenv("QM_ROOT", getwd())))
if (!file.exists(file.path(ROOT, "CLAUDE.md"))) ROOT <- gsub("\\\\", "/", getwd())
D <- file.path(ROOT, "04_Research/01_reports/grade_v35_cr_beta_selection_20261113")
OD <- sub("/+$", "", gsub("\\\\", "/", Sys.getenv("V35_OUT_DIR", D)))   # 산출 폴더(시험 때 다른 곳 · 기본 = 보고서 폴더)
OUT <- file.path(OD, "charts"); dir.create(OUT, recursive = TRUE, showWarnings = FALSE); dir.create(file.path(OD, "data"), showWarnings = FALSE)
RUN <- Sys.getenv("V35_RUN", "post"); CPRE <- Sys.getenv("V35_CEN_PRE"); CPOST <- Sys.getenv("V35_CEN_POST", "post")
if (!nzchar(CPRE)) stop("[v35 report] V35_CEN_PRE(쓰기 직전 전수 꼬리표)가 필요하다")
rd <- function(f) { p <- file.path(D, "data", f); if (!file.exists(p)) stop("[v35 report] 없음: ", p); fread(p, na.strings = c("", "NA")) }
pre <- fromJSON(file.path(D, "prereg.json"))
NEG <- pre$report$T4_sets$cr_strong_converted_normal; RND <- pre$report$T4_sets$random_non_strong$paths
v4 <- rd(sprintf("dryrun_v34_%s.csv", RUN)); v5 <- rd(sprintf("dryrun_v35_%s.csv", RUN))
c0 <- rd(sprintf("census_%s.csv", CPRE))
POST <- file.exists(file.path(D, "data", sprintf("census_%s.csv", CPOST)))
cP <- if (POST) rd(sprintf("census_%s.csv", CPOST)) else NULL
for (cc in c("factor_md5", "rawdata_vintage", "bench_vintage", "basis", "err", "blocked_by")) {
  if (!cc %in% names(v4)) v4[, (cc) := NA_character_]
  if (!cc %in% names(v5)) v5[, (cc) := NA_character_]
}
if ("vintage_changed_during_run" %in% c(names(v4), names(v5))) stop("[v35 report] 드라이런 중 자료 판이 바뀌었다 — 드라이런부터 다시")
lg <- function(x) tolower(as.character(x)) %in% "true"   # 전수 CSV 의 True/False(파이썬) → 논리
for (x in c("c0", "cP")) { d0 <- get(x); if (is.null(d0)) next
  for (cc in intersect(c("fa_stale", "scope", "scope_snapshot", "t4", "rec_inc", "hard_fail", "judge_eligible", "benefit"), names(d0))) d0[, (cc) := lg(get(cc))]
  assign(x, d0) }

## 이음매 수리 전 P1R03 측정(재측정본으로 대체 · 인용 대상 아님 — 부록 1 §2)
P13 <- file.path(ROOT, "04_Research/programs/P1_RETURN/P1R03_factor_family_composites")
## 칸마다 가장 늦은 결과 묶음(원 측정 results/ · 재측정 remeasure_*/results/ — 결과 파일 시각 순)의 기록만 현행 · 앞선 묶음의 기록 = 대체됨
rs13 <- rbindlist(lapply(c(file.path(P13, "results"), Sys.glob(file.path(P13, "remeasure_*", "results"))), function(dd)
  rbindlist(lapply(Sys.glob(file.path(dd, "P1R03_*_C0.json")), function(f) {
    x <- tryCatch(fromJSON(f)$artifacts, error = function(e) NULL)
    data.table(code = sub("\\.json$", "", basename(f)), dir = if (is.null(x)) NA_character_ else sub("^.*(stage_artifacts/)", "\\1", gsub("\\\\", "/", as.character(x)[1])),
               t = file.mtime(f), set = basename(dirname(dd)))
  }))), fill = TRUE)
SUPER <- if (nrow(rs13)) { rs13 <- rs13[!is.na(dir)]; setdiff(rs13$dir, rs13[order(-as.numeric(t))][, .SD[1], by = code]$dir) } else character(0)
## 중단된 측정(판정에 쓰지 않음 · 99_Archive/*aborted_measure*) — 예: P1R04 11-13 10:04~10:31(이음매 D1 예고로 멈춤 · DESIGN §10)
ABORT <- unique(unlist(lapply(Sys.glob(file.path(ROOT, "99_Archive", "*aborted_measure*", c("*.json", "results/*.json"))), function(f) {
  x <- tryCatch(fromJSON(f)$artifacts, error = function(e) NULL)
  if (is.null(x)) character(0) else sub("^.*(stage_artifacts/)", "\\1", gsub("\\\\", "/", as.character(x)))
})))

K <- c("dir", "strategy", "remeasured_at", "essence_grade", "rules_version", "fa_stale", "scope", "scope_snapshot", "t4", "judge_eligible")
J <- merge(v4[, .(dir, g4 = grade, basis4 = basis, crn4 = cr_notch, band4 = band, fa4 = fa_notch, err4 = err, fmd5_4 = factor_md5, raw4 = rawdata_vintage)],
           v5[, .(dir, g5 = grade, basis5 = basis, crn5 = cr_notch, band5 = band, notch5 = notch, fa5 = fa_notch, stored_grade, stored_rules, stored_cr_notch,
                  cr, mc8_label, label_size_beta, size_beta_status, share_se, share_sb, share_se_path, share_sb_path, exposure_varies,
                  beta_leg, rho_median, card_beta, blocked5 = blocked_by, err5 = err, fmd5_5 = factor_md5, raw5 = rawdata_vintage)], by = "dir", all = TRUE)
J <- merge(J, c0[, ..K], by = "dir", all.x = TRUE)
J[, superseded := dir %in% SUPER][, aborted := dir %in% ABORT]
errs <- J[!is.na(err4) | !is.na(err5)]
## 두 드라이런이 같은 자료 판이었나(요인 md5 · RAWDATA 크기@시각)
vint <- unique(J[is.na(err4) & is.na(err5), .(fmd5_4, fmd5_5, raw4, raw5)])
vint_ok <- nrow(vint) == 1L && identical(vint$fmd5_4, vint$fmd5_5) && identical(vint$raw4, vint$raw5)

rank_g <- c(F = 0L, C = 1L, B = 2L, A = 3L)
mv <- function(a, b) fifelse(is.na(a) | is.na(b), "판정 불가", fifelse(a == b, "그대로", fifelse(rank_g[b] < rank_g[a], "내림", "오름")))
## 규칙 효과 = 같은 입력 v3.4 → v3.5 · 자료 판 효과 = 저장 → 같은 규칙 판(지금)
## (11-15 정밀화) 교체 뒤 현행 판(v3.5)으로 측정된 기록은 저장 등급이 이미 v3.5 다 — v3.4 → v3.5 는 반사실이라 범위 밖 규칙 효과 검사에서 빼고
##   따로 적는다(리허설 11-14 16:25 때는 대상에 없었다 · 요인 낡음으로 대상에 든다). 자료 판 효과는 같은 규칙 판끼리 = 저장 → v3.5(지금).
RV_NOW <- fromJSON(file.path(ROOT, "06_Registry/grade_v3.json"))$rules_version
J[, post_release := stored_rules %in% RV_NOW][, g_data := fifelse(post_release, g5, g4)]
J[, rule_move := mv(g4, g5)][, data_move := mv(stored_grade, g_data)]
RULE <- J[scope %in% TRUE]; n_snap <- RULE[scope_snapshot %in% TRUE, .N]; n_new <- RULE[!scope_snapshot %in% TRUE, .N]
RULE[, sub := fifelse(scope_snapshot %in% TRUE, sprintf("등록 시점 %d", n_snap), sprintf("등록 뒤 %d", n_new))]
FA <- J[fa_stale %in% TRUE & !scope %in% TRUE]
T4 <- J[t4 %in% TRUE]; t4_same <- T4[!is.na(g4) & !is.na(g5) & g4 == g5, .N]
rule_outside <- J[rule_move %in% c("내림", "오름") & !scope %in% TRUE & !post_release]   # 교체 전 저장분(v3.3 · v3.4)만
post_diff <- J[post_release & rule_move %in% c("내림", "오름")]                         # 교체 뒤 측정분 — v3.4 였다면 달랐을 기록(참고)
n_post <- J[post_release == TRUE, .N]; n_post_same <- J[post_release == TRUE & !is.na(g5) & stored_grade == g5, .N]
rule_up <- J[rule_move == "오름"]                                                        # 단조성 = 전 기록

## T2 — 전체 권위 기록 분포(쓰기 직전 전수 → 쓰기 뒤 전수 · 없으면 쓰기 직전 전수에 드라이런 v3.5 를 얹은 예측)
G <- c("A", "B", "C", "F")
cnt <- function(x) x[scheme == "grade_v3" & essence_grade %in% G, .N, by = .(g = essence_grade)]
before <- cnt(c0)
## 같은 기록 집합끼리 비교한다 — 쓰기 직전 전수 뒤에 새로 측정된 기록은 분포에서 빼고 건수만 적는다(11-15 · 두 전수 사이 측정이 섞이면 변화 합이 0 이 아니게 된다)
n_new_post <- if (POST) cP[!dir %in% c0$dir & scheme == "grade_v3" & essence_grade %in% G, .N] else 0L
after <- if (POST) cnt(cP[dir %in% c0$dir]) else { tmp <- copy(c0); tmp[J[is.na(err5)], on = "dir", essence_grade := i.g5]; cnt(tmp) }
dist <- merge(data.table(g = G), before[, .(g, before = N)], by = "g", all.x = TRUE)
dist <- merge(dist, after[, .(g, after = N)], by = "g", all.x = TRUE)
dist[is.na(before), before := 0L][is.na(after), after := 0L][, delta := after - before]
dist[, g := factor(g, levels = G)]; setorder(dist, g)
## 쓰기 전후 바뀐 기록(원인별) · 수혜 표식 · Judge 트리거
chg <- if (POST) {
  m <- merge(c0[, .(dir, strategy, g0 = essence_grade)], cP[, .(dir, g1 = essence_grade, causes, benefit, judge_eligible, rules_version)], by = "dir")
  m[!is.na(g0) & !is.na(g1) & g0 != g1][, move := mv(g0, g1)]
} else NULL
ben_new <- if (POST) merge(c0[, .(dir, b0 = benefit)], cP[, .(dir, strategy, b1 = benefit, causes)], by = "dir")[b1 %in% TRUE & !b0 %in% TRUE] else NULL
judge_off <- if (POST) cP[judge_eligible %in% TRUE & essence_grade != "A"] else J[judge_eligible %in% TRUE & g5 != "A"]
BOOKF <- file.path(ROOT, "06_Registry/book/book_registry.json")
book_txt <- if (file.exists(BOOKF)) paste(readLines(BOOKF, warn = FALSE, encoding = "UTF-8"), collapse = "\n") else ""
a_down <- if (POST) chg[g0 == "A"] else J[g4 == "A" & g5 != "A"]
a_down_book <- if (nrow(a_down)) a_down[vapply(dir, function(d) grepl(basename(d), book_txt, fixed = TRUE), logical(1))] else a_down

## ── 그림(현대하모니 M · P1R03 차트와 같은 방식) ──
C_OLD <- "#898781"; C_NEW <- "#2a78d6"; C_LOSE <- "#e34948"; C_KEEP <- "#2a78d6"; C_NONE <- "#b5b3ab"; C_UP <- "#2a78d6"
INK <- "#0b0b0b"; INK2 <- "#52514e"; MUTED <- "#898781"; GRID <- "#e1e0d9"
FAM <- ""
fdir <- c(file.path(Sys.getenv("LOCALAPPDATA"), "Microsoft", "Windows", "Fonts"), file.path(Sys.getenv("WINDIR", "C:/Windows"), "Fonts"))
fM <- file.path(fdir, "현대하모니+M.ttf"); fM <- fM[file.exists(fM)][1]
if (!is.na(fM)) { try(systemfonts::register_font(name = "HDHM", plain = fM), silent = TRUE); FAM <- "HDHM" }
th <- function(base = 12) theme_minimal(base_family = FAM, base_size = base) +
  theme(plot.title = element_text(size = base + 3, colour = INK), plot.title.position = "plot",
        plot.subtitle = element_text(size = base - 1.5, colour = INK2, lineheight = 1.15),
        plot.caption = element_text(size = base - 4, colour = MUTED, hjust = 0, lineheight = 1.1), plot.caption.position = "plot",
        panel.grid.minor = element_blank(), panel.grid.major = element_line(colour = GRID, linewidth = 0.3),
        axis.text = element_text(colour = INK2), legend.position = "top", legend.justification = "left", legend.title = element_blank(),
        plot.background = element_rect(fill = "white", colour = NA), plot.margin = margin(10, 14, 8, 10))
pct <- function(x) ifelse(is.finite(x), sprintf("%.0f%%", 100 * x), "–")
n_rule_down <- J[rule_move == "내림" & !post_release, .N]; n_data_mv <- J[data_move %in% c("내림", "오름"), .N]   # 교체 뒤 측정분의 반사실 차이는 규칙 효과로 세지 않는다

## 그림 1 — 전체 권위 기록 등급 분포(쓰기 직전 → 쓰기 뒤)
L <- melt(dist, id.vars = c("g", "delta"), measure.vars = c("before", "after"), variable.name = "when", value.name = "n")
lv <- c("재채점 전(v3.4 · 저장)", if (POST) "재채점 뒤(v3.5)" else "재채점 뒤(v3.5 · 예측)")
L[, when := factor(fifelse(when == "before", lv[1], lv[2]), levels = lv)]
lab <- dist[, .(g, y = pmax(before, after), txt = fifelse(delta == 0, "변화 없음", sprintf("%+d", delta)))]
g1 <- ggplot(L, aes(g, n, fill = when)) + geom_col(position = position_dodge(width = 0.75), width = 0.7) +
  geom_text(aes(label = format(n, big.mark = ",")), position = position_dodge(width = 0.75), vjust = -0.4, family = FAM, size = 3.3, colour = INK2) +
  geom_text(data = lab, aes(g, y, label = txt), inherit.aes = FALSE, vjust = -2.2, family = FAM, size = 3.6,
            colour = ifelse(lab$txt == "변화 없음", MUTED, C_LOSE)) +
  scale_fill_manual(values = c(C_OLD, C_NEW)) + scale_y_continuous(expand = expansion(mult = c(0, 0.18)), labels = scales::comma) +
  labs(title = "① 권위 등급 분포 — 재채점 전 vs 뒤", x = NULL, y = "기록 수",
       subtitle = sprintf("저장 권위 기록 %s건 · 같은 입력 드라이런 %d건\n= 위기 방어 가점 범위 %d + 팩터 수익률 갱신 %d + 실데이터 음성 대조(겹침 제외)\n규칙 효과(v3.4 → v3.5) 내림 %d건 · 데이터 갱신 효과(저장 → 같은 규칙 버전으로 재계산) 이동 %d건",
                          format(sum(dist$before), big.mark = ","), nrow(J), nrow(RULE), nrow(FA), n_rule_down, n_data_mv),
       caption = "등급 = 권위 등급 v3(essence) · 데이터 갱신 효과 = 팩터 조정 알파 노치를 현행 팩터 수익률로 다시 계산\n원천 수익률 정정(03-30 · 가격 연속성 · 내부 단절 채움) 반영") + th()

## 그림 2 — 위기 방어 '강함' 기록의 귀속: 시가총액 · 노출 일치 대조 통과율 vs 시가총액 · β 일치 대조 통과율
P <- J[(scope %in% TRUE | dir %in% NEG) & is.finite(share_se)]
had <- function(b) b %in% c("selection", "timing_evidence")             # 가점이 유지됐나(노치 근거)
P[, kind := fifelse(!mc8_label %in% "selection_defense", "선택 방어 아님(기존 판정부터)",
             fifelse(!had(basis4), "가점 없음(v3.4 부터 · 타이밍 증거 없음)",
             fifelse(had(basis5), "가점 유지(β 일치 대조도 통과)", "가점 해제(β 로 설명되는 방어)")))]
P[, tag := fifelse(scope %in% TRUE & !superseded & !aborted, sprintf("%s→%s", g4, g5), "")]
set.seed(20261113)
g2 <- ggplot(P, aes(share_se, share_sb, colour = kind)) +
  annotate("rect", xmin = 0.5, xmax = Inf, ymin = -Inf, ymax = 0.5, fill = "#fbe9e8", alpha = 0.6) +
  geom_hline(yintercept = 0.5, colour = MUTED, linetype = "dashed", linewidth = 0.4) +
  geom_vline(xintercept = 0.5, colour = MUTED, linetype = "dashed", linewidth = 0.4) +
  geom_jitter(width = 0.012, height = 0.012, size = 3, alpha = 0.9) +
  ggrepel::geom_text_repel(aes(label = tag), family = FAM, size = 3.3, colour = INK, seed = 7, min.segment.length = 0, box.padding = 0.4) +
  scale_colour_manual(values = c("가점 유지(β 일치 대조도 통과)" = C_KEEP, "가점 해제(β 로 설명되는 방어)" = C_LOSE,
                                 "가점 없음(v3.4 부터 · 타이밍 증거 없음)" = "#eb6834", "선택 방어 아님(기존 판정부터)" = C_NONE)) +
  guides(colour = guide_legend(nrow = 2)) +
  scale_x_continuous(labels = scales::percent, limits = c(-0.03, 1.03)) + scale_y_continuous(labels = scales::percent, limits = c(-0.03, 1.03)) +
  annotate("text", x = 1.02, y = 0.02, label = "β 로 산 방어 영역", hjust = 1, vjust = 0, family = FAM, size = 3.3, colour = C_LOSE) +
  labs(title = "② 위기 방어 '강함' 기록의 귀속 — 무작위 대조 포트폴리오를 이긴 위기 비율",
       x = "시가총액 · 노출 일치 대조를 이긴 위기(v3.4 판정)", y = "시가총액 · β 일치 대조를 이긴 위기(v3.5 추가)",
       subtitle = "점선 = 과반(50%) · 둘 다 과반이어야 선택 방어 가점 · 라벨 = 가점 범위 기록의 등급(v3.4→v3.5 · 같은 입력)",
       caption = paste0("대조 = 같은 시가총액 분위에서 무작위로 고른 포트폴리오(characteristic-matched random portfolios) 200개의 위기 낙폭 5% 분위\n",
                        "β 일치 = 각 대조를 현금 혼합으로 전략 β 까지 낮춤(월간 OLS β · 차입 없음) · 위기 = Lunde-Timmermann 20/20 · 전기간\n",
                        "라벨 없는 점 = 원천 수익률 정정 전 P1R03 측정(재측정본으로 대체) · 중단된 P1R04 측정 · 실데이터 음성 대조(가점이 이미 없던 강함 기록)")) + th()

## 그림 3 — 전이 행렬: 규칙 효과(범위 · v3.4 → v3.5) | 자료 판 효과(팩터 판 갱신 · 저장 → v3.4 재계산)
tm <- function(x, a, b, ttl) {
  x <- x[!is.na(get(a)) & !is.na(get(b))]
  m <- CJ(from = G, to = G)[x[, .N, by = .(from = get(a), to = get(b))], on = c("from", "to"), N := i.N]
  m[is.na(N), N := 0L][, `:=`(from = factor(from, levels = rev(G)), to = factor(to, levels = G))]
  m[, kind := fifelse(N == 0L, "없음", fifelse(as.character(from) == as.character(to), "그대로",
                fifelse(rank_g[as.character(to)] < rank_g[as.character(from)], "내림", "오름")))]
  ggplot(m, aes(to, from, fill = kind)) + geom_tile(colour = "white", linewidth = 1.2) +
    geom_text(aes(label = fifelse(N > 0L, format(N, big.mark = ","), "")), family = FAM, size = 4.2, colour = INK) +
    scale_fill_manual(values = c("없음" = "#f6f5f1", "그대로" = "#dedcd4", "내림" = "#f3b6b5", "오름" = "#b7d3f2"), drop = FALSE) +
    labs(title = ttl, x = "재채점 뒤 등급", y = "재채점 앞 등급") + th(11) +
    theme(panel.grid.major = element_blank(), legend.position = "none", axis.title.y = element_text(angle = 90, vjust = 1))
}
g3 <- patchwork::wrap_plots(
  tm(RULE, "g4", "g5", sprintf("규칙 효과 — 위기 방어 가점 범위 %d건\n(같은 입력 · v3.4 → v3.5)", nrow(RULE))),
  tm(FA, "stored_grade", "g_data", sprintf("데이터 갱신 효과 — 팩터 수익률 갱신 %d건\n(저장 → 같은 규칙 버전으로 재계산 · 규칙 무관)", nrow(FA))), nrow = 1) +
  patchwork::plot_annotation(title = "③ 재채점 등급 이동 — 원인별",
                             subtitle = sprintf("규칙 효과는 내림만 가능(조건만 추가) · 범위 밖(교체 전 저장분) 규칙 효과 %d건 · 실데이터 음성 대조 %d/%d 동일",
                                                nrow(rule_outside), t4_same, nrow(T4)),
                             theme = th())
ggsave(file.path(OUT, "01_grade_distribution.png"), g1, width = 7.4, height = 5.2, dpi = 150, device = ragg::agg_png, bg = "white")
ggsave(file.path(OUT, "02_cr_strong_attribution.png"), g2, width = 7.6, height = 6.0, dpi = 150, device = ragg::agg_png, bg = "white")
ggsave(file.path(OUT, "03_transition_by_cause.png"), g3, width = 8.6, height = 4.6, dpi = 150, device = ragg::agg_png, bg = "white")

## ── 표 ──
fwrite(J, file.path(OD, sprintf("data/regrade_table_%s.csv", RUN)))
row1 <- function(x) x[, sprintf("| `%s` | %s | %s | %s | %s | %s | %s → %s | %s | %s | %s | %s | %s |%s", dir, paste0(fifelse(is.na(strategy), "", strategy), fifelse(superseded, " ※", ""), fifelse(aborted, " †", "")), stored_grade, g4, g5, band5, basis4, basis5,
                               pct(share_se), pct(share_sb), fifelse(exposure_varies %in% TRUE, "변함", "고정"),
                               ifelse(is.finite(beta_leg), sprintf("%.2f", beta_leg), "–"), ifelse(is.finite(rho_median), sprintf("%.2f", rho_median), "–"), "")]
hdr <- c("| 기록 | 전략 | 저장 | v3.4 | v3.5 | 띠 | 근거 v3.4 → v3.5 | 시가총액·노출 일치 | 시가총액·β 일치 | 노출 | 보유 β | ρ 중앙 |", "|---|---|---|---|---|---|---|---|---|---|---|---|")
tab <- function(x, a, b) { if (!nrow(x)) return("- (없음)"); y <- x[!is.na(get(a)) & !is.na(get(b)), .N, by = .(from = get(a), to = get(b))]; setorder(y, from, to)
  c("| 앞 | 뒤 | 건수 |", "|---|---|---|", y[, sprintf("| %s | %s | %d |", from, to, N)]) }
md <- c("# 등급 v3.5 재채점 결과 — 사전등록 §4 · 부록 1 §4 표",
        sprintf("- 생성 %s · 드라이런 `%s`(v3.4 계약 = 교체 전 커밋 사본 · v3.5 = 운영) · 쓰기 직전 전수 `%s` · %s", format(Sys.time(), "%Y-%m-%d %H:%M"), RUN, CPRE,
                if (POST) sprintf("쓰기 뒤 전수 `%s`", CPOST) else "쓰기 뒤 전수 없음(예측)"),
        sprintf("- 데이터 시점: %s", if (vint_ok) sprintf("두 드라이런 같은 데이터 시점 — 요인 md5 %s · RAWDATA %s", substr(vint$fmd5_5, 1, 12), vint$raw5) else "⚠ 두 드라이런의 데이터 시점이 다르다(아래 오류 · 원자료 확인)"),
        if (nrow(errs)) sprintf("- ⚠ 채점 오류 %d건: %s", nrow(errs), paste(errs$dir, collapse = ", ")) else "- 채점 오류 0건",
        sprintf("- 드라이런 대상 %d건 = 위기 방어 가점 범위 %d(등록 시점 %d · 등록 뒤 %d) ∪ 팩터 수익률 갱신 %d(범위와 겹침 %d) ∪ 실데이터 음성 대조 %d",
                nrow(J), nrow(RULE), n_snap, n_new, J[fa_stale %in% TRUE, .N], J[fa_stale %in% TRUE & scope %in% TRUE, .N], nrow(T4)),
        "", "## T4 실데이터 음성 대조 — 같은 입력에서 v3.4 = v3.5(기준 = 같은 데이터 시점 v3.4 · 부록 1 §2)",
        sprintf("- %d/%d 동일(강함인데 이미 보통 %d · 무작위 %d)", t4_same, nrow(T4), length(NEG), length(RND)),
        sprintf("- 범위 밖 기록의 규칙 효과(v3.4 ≠ v3.5 · 교체 전 저장분 v3.3 · v3.4): %d건%s", nrow(rule_outside), if (nrow(rule_outside)) paste0(" — ", paste(rule_outside$dir, collapse = ", ")) else ""),
        sprintf("- 교체 뒤 %s 로 측정된 기록 %d건(요인 낡음으로 대상에 듦 · 저장 등급이 이미 %s — 재채점 규칙 효과 없음 · 저장 = %s 지금 %d/%d): v3.4 계약이었다면 달랐을 기록 %d건%s",
                RV_NOW, n_post, RV_NOW, RV_NOW, n_post_same, n_post,
                nrow(post_diff), if (nrow(post_diff)) paste0(" — ", paste(post_diff$dir, collapse = ", ")) else ""),
        sprintf("- 규칙 효과 오름: %d건(기대 0 — 조건만 추가)", nrow(rule_up)),
        "", sprintf("## T1′ 위기 방어 가점 범위 %d건 — 저장 → v3.4(지금) → v3.5(지금)", nrow(RULE)), "",
        sprintf("### 등록 시점 %d", n_snap), "", hdr, row1(RULE[scope_snapshot %in% TRUE]),
        "", sprintf("### 등록 뒤 %d(사전등록 뒤 측정)", n_new), "", hdr, row1(RULE[!scope_snapshot %in% TRUE]),
        "", "- ※ = 같은 칸의 더 늦은 재측정으로 대체된 P1R03 측정 — 인용 대상 아님",
        "- † = 중단된 측정(판정에 쓰지 않음 · 99_Archive 의 aborted_measure 기록 · 예: P1R04 11-13 10:04~10:31)",
        sprintf("- 규칙 효과(v3.4 → v3.5): %s", paste(RULE[, .N, by = rule_move][, sprintf("%s %d", rule_move, N)], collapse = " · ")),
        sprintf("- 데이터 갱신 효과(저장 → v3.4): %s", paste(RULE[, .N, by = data_move][, sprintf("%s %d", data_move, N)], collapse = " · ")),
        "", sprintf("## T5 팩터 수익률 갱신 재채점(규칙 무관) %d건 — 저장 → 같은 규칙 버전(지금)", nrow(FA)), "",
        sprintf("- 교체 전 저장분 %d건 = v3.4 계약(지금) · 교체 뒤 %s 측정분 %d건 = %s 계약(지금)", FA[post_release != TRUE, .N], RV_NOW, FA[post_release == TRUE, .N], RV_NOW), "",
        tab(FA, "stored_grade", "g_data"),
        "", sprintf("- 교체 전 저장분 v3.4(지금) = v3.5(지금): %d/%d", FA[post_release != TRUE & !is.na(g4) & !is.na(g5) & g4 == g5, .N], FA[post_release != TRUE & !is.na(g4) & !is.na(g5), .N]),
        "", "## T2 전체 권위 기록 분포", "", sprintf("| 등급 | 재채점 전 | 재채점 뒤%s | 변화 |", if (POST) "" else "(예측)"), "|---|---|---|---|",
        dist[, sprintf("| %s | %s | %s | %+d |", g, format(before, big.mark = ","), format(after, big.mark = ","), delta)],
        if (POST) c("", sprintf("- 같은 기록 집합(쓰기 직전 전수 %s건)끼리 비교 · 그 뒤 새로 측정된 기록 %d건은 빼고 셌다(현행 판으로 측정 · 재채점 대상 아님)",
                                format(sum(dist$before), big.mark = ","), n_new_post)) else character(0),
        if (POST) c("", sprintf("- 쓰기 전후 등급이 바뀐 기록 %d건 — 원인별:", nrow(chg)),
                    if (nrow(chg)) chg[, .N, by = .(cause = fifelse(is.na(causes), "(기록 없음)", causes), move)][, sprintf("  - %s · %s %d", cause, move, N)] else "  - (없음)",
                    sprintf("- 새 수혜 표식(등급이 측정 때보다 오른 기록): %d건%s", nrow(ben_new),
                            if (nrow(ben_new)) paste0(" — 원인 ", paste(ben_new[, .N, by = causes][, sprintf("%s %d", causes, N)], collapse = " · ")) else "")) else character(0),
        "", "## A 등급 · Judge · BOOK 영향",
        sprintf("- A 에서 내려간 기록: %d건%s", nrow(a_down), if (nrow(a_down)) paste0(" — ", paste(a_down$dir, collapse = ", ")) else ""),
        sprintf("- 그중 BOOK 등록부에 이름이 있는 기록: %d건", nrow(a_down_book)),
        sprintf("- Judge 트리거(judge_request.eligible.json)가 있는데 새 등급이 A 가 아닌 기록: %d건%s", nrow(judge_off),
                if (nrow(judge_off)) paste0(" — ", paste(judge_off$dir, collapse = ", "), "(rcg_withdraw 대상)") else ""),
        "", "## 그림", "- `charts/01_grade_distribution.png` · `charts/02_cr_strong_attribution.png` · `charts/03_transition_by_cause.png`",
        sprintf("- 원자료: `data/regrade_table_%s.csv` · `data/dryrun_v34_%s.csv` · `data/dryrun_v35_%s.csv` · `data/census_%s.csv`%s", RUN, RUN, RUN, CPRE,
                if (POST) sprintf(" · `data/census_%s.csv`", CPOST) else ""))
writeLines(md, file.path(OD, "REPORT_tables.md"), useBytes = TRUE)
## 텔레그램 · README 가 읽을 요약(숫자만)
sm <- list(run = RUN, census_pre = CPRE, census_post = if (POST) CPOST else NA, n_records = sum(dist$before), n_regraded = nrow(J), n_rule = nrow(RULE),
           n_rule_snap = n_snap, n_rule_new = n_new, n_fa = nrow(FA), n_fa_overlap = J[fa_stale %in% TRUE & scope %in% TRUE, .N], n_t4 = nrow(T4), t4_same = t4_same,
           rule_moves = as.list(setNames(RULE[, .N, by = rule_move]$N, RULE[, .N, by = rule_move]$rule_move)),
           rule_down_by = RULE[rule_move == "내림", .N, by = .(from = g4, to = g5)], rule_outside = nrow(rule_outside), rule_up = nrow(rule_up),
           fa_moves = FA[!is.na(g_data) & stored_grade != g_data, .N, by = .(from = stored_grade, to = g_data)],
           fa_rule_same = FA[post_release != TRUE & !is.na(g4) & !is.na(g5) & g4 == g5, .N], fa_rule_n = FA[post_release != TRUE & !is.na(g4) & !is.na(g5), .N],
           n_post_release = n_post, post_release_rule_diff = nrow(post_diff), n_new_post = n_new_post,
           post_release_same = n_post_same, rules_version_now = RV_NOW,
           dist = dist[, .(g = as.character(g), before, after, delta)], changed = if (POST) nrow(chg) else NA, benefit_new = if (POST) nrow(ben_new) else NA,
           a_down = nrow(a_down), a_down_book = nrow(a_down_book), judge_withdraw = nrow(judge_off), errors = nrow(errs), vintage_ok = vint_ok,
           superseded_in_rule = RULE[superseded == TRUE, .N], aborted_in_rule = RULE[aborted == TRUE, .N],
           keep_notch = J[basis5 %in% c("selection", "timing_evidence") & crn5 %in% "strong", .N],
           ## 텔레그램 · README 서술용(숫자 · 식별자만) — 규칙 효과 내림 기록 · 범위 기록의 시가총액 · β 일치 대조 통과율 · 보유 β 범위
           rule_down_list = RULE[rule_move == "내림", .(strategy, from = g4, to = g5, beta_leg = round(beta_leg, 2), share_sb = round(share_sb, 2), superseded, aborted)],
           rule_sb_range = if (RULE[is.finite(share_sb), .N]) round(range(RULE[is.finite(share_sb)]$share_sb), 2) else NULL,
           rule_beta_range = if (RULE[is.finite(beta_leg), .N]) round(range(RULE[is.finite(beta_leg)]$beta_leg), 2) else NULL,
           rule_basis5 = as.list(table(RULE$basis5, useNA = "ifany")),
           fa_total_moved = FA[!is.na(g_data) & stored_grade != g_data, .N],
           n_rec_inc = if ("rec_inc" %in% names(c0)) J[dir %in% c0[rec_inc %in% TRUE]$dir, .N] else 0L)
writeLines(toJSON(sm, auto_unbox = TRUE, pretty = TRUE, digits = NA, na = "null"), file.path(OD, "data", sprintf("report_summary_%s.json", RUN)), useBytes = TRUE)
cat(md, sep = "\n")
