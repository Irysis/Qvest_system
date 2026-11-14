## 이음매 D2(수익률 단절 채움 · 사건 종류별 정정) — 차트 3장 + P1R03 15엔진 재측정 표 + 텔레그램 1통(prep_send · qvest-telegram SKILL §0 · 정정 = 푸시)
##   실행: 저장소 루트에서 Rscript 04_Research/01_reports/rawdata_seam_20260330_repair_20261113/tools/d2_report.R [--dry] [--no-send] [--charts-only]
##   수치 출처(AX-008 — 등급 · 판정 값은 다시 계산하지 않는다):
##     · 정정 10행 = 06_Registry/ret_fill_registry.json(정정 값 · 근거) + d2_fill/d2b_changed_rows.csv(17:31 시총 기준 값 — 적용 전후 전 열 대조 산출)
##     · 종가 일치율 = d2_fill/close_match_by_month.csv(퀀티 종가 vs 거래소 원주가 · 12종목 표본 · 기술 통계)
##     · P1R03 = 각 산출물 authoritative_remeasure.json(essence · grade_v3) · 일간 수익 동일성 = 03_period_returns.csv(ret_net) 기술 비교(판정 아님)
##       D2 전 = remeasure_d1_20261114(7엔진) · 없으면 remeasure_seam_20261113 / D2 후 = remeasure_d2_20261114
suppressPackageStartupMessages({ library(data.table); library(jsonlite); library(ggplot2) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
ROOT <- sub("/+$", "", gsub("\\\\", "/", Sys.getenv("QM_ROOT", getwd())))
if (!file.exists(file.path(ROOT, "CLAUDE.md"))) ROOT <- gsub("\\\\", "/", getwd())
REP <- file.path(ROOT, "04_Research/01_reports/rawdata_seam_20260330_repair_20261113")
D2 <- file.path(REP, "d2_fill"); OUT <- file.path(REP, "charts"); dir.create(OUT, showWarnings = FALSE)
RD <- file.path(ROOT, "04_Research/programs/P1_RETURN/P1R03_factor_family_composites")
a <- commandArgs(trailingOnly = TRUE); if ("--dry" %in% a) Sys.setenv(QVEST_TG_DRY_RUN = "1")
TAU_D <- as.Date("2022-12-31")

C_PRE <- "#e34948"; C_POST <- "#2a78d6"; C_ALT <- "#7a5cd6"; INK <- "#0b0b0b"; INK2 <- "#52514e"; MUTED <- "#898781"; GRID <- "#e1e0d9"
FAM <- ""
fdir <- c(file.path(Sys.getenv("LOCALAPPDATA"), "Microsoft", "Windows", "Fonts"), file.path(Sys.getenv("WINDIR", "C:/Windows"), "Fonts"))
fM <- file.path(fdir, "현대하모니+M.ttf"); fM <- fM[file.exists(fM)][1]
if (!is.na(fM)) { try(systemfonts::register_font(name = "HDHM", plain = fM), silent = TRUE); FAM <- "HDHM" }
th <- function(base = 12) theme_minimal(base_family = FAM, base_size = base) +
  theme(plot.title = element_text(size = base + 3, colour = INK), plot.title.position = "plot",
        plot.subtitle = element_text(size = base - 1.5, colour = INK2, lineheight = 1.15),
        plot.caption = element_text(size = base - 4, colour = MUTED, hjust = 0, lineheight = 1.1), plot.caption.position = "plot",
        panel.grid.minor = element_blank(), panel.grid.major = element_line(colour = GRID, linewidth = 0.3),
        axis.text = element_text(colour = INK2), legend.position = "top", legend.justification = "left")

## 1) 정정 10행 — 17:31 시총 기준 vs 정정 값(사건 종류별)
reg <- as.data.table(fromJSON(file.path(ROOT, "06_Registry/ret_fill_registry.json"))$entries)[, .(Date = as.Date(Date), Ticker, Ret_reg = Ret, method)]
chg <- fread(file.path(D2, "d2b_changed_rows.csv"))[, Date := as.Date(Date)]
X <- merge(chg[abs(after - before) > 1e-9, .(Date, Ticker, before, after)], reg, by = c("Date", "Ticker"))
stopifnot(nrow(X) == 10L, all(abs(X$after - X$Ret_reg) < 1e-12))
EV <- c(konex_transfer_holder_ratio = "코넥스 → 코스닥 이전상장 첫날", otc_to_exchange_first_day_holder_ratio = "장외 → 코스닥 상장 첫날",
        second_source_adjusted_ratio = "토요일 행 결손(1998)")
X[, ev := factor(EV[method], levels = EV)]
X[, lab := sprintf("%s  %s", format(Date), Ticker)]
setorder(X, ev, Date); X[, lab := factor(lab, levels = rev(lab))]
L1 <- rbind(X[, .(lab, ev, v = 100 * before, w = "17:31 채움(시가총액 기준)")], X[, .(lab, ev, v = 100 * after, w = "18:22 정정(보유자 수익)")])
L1[, w := factor(w, levels = c("17:31 채움(시가총액 기준)", "18:22 정정(보유자 수익)"))]
p1 <- ggplot(L1, aes(v, lab)) + geom_vline(xintercept = 0, colour = MUTED, linewidth = 0.3) +
  geom_line(aes(group = lab), colour = "#c9c7bf", linewidth = 0.8) + geom_point(aes(colour = w), size = 3) +
  facet_grid(ev ~ ., scales = "free_y", space = "free_y", labeller = label_wrap_gen(14)) +
  scale_colour_manual(values = c(C_PRE, C_POST), name = NULL) +
  labs(title = "수익률 단절 채움 — 사건 종류가 값을 정한다",
       subtitle = paste0("이전상장 · 일반공모: 같은 날 상장된 신주가 시가총액을 부풀린다 → 종가 비율이 보유자 수익\n",
                         "장외 → 상장 첫날: 거래소 첫 종가 ÷ 장외 마지막 종가(상장일 신주 비율 10~25% 로 교차 검증)"),
       x = "그날 수익률(%)", y = NULL,
       caption = "출처: DART 공시 목록(사건 종류) · 거래소 원주가(네이버 모바일 일별 시세) · 확인값 목록 06_Registry/ret_fill_registry.json(행마다 근거)") +
  th(11) + theme(strip.text.y = element_text(angle = 0, hjust = 0, colour = INK2))
f1 <- file.path(OUT, "d2_c1_fill_by_event.png")
ggsave(f1, p1, width = 9, height = 6.4, dpi = 160, bg = "white", device = ragg::agg_png)

## 2) 퀀티 종가 vs 거래소 종가 — 월별 일치율(새 결함 · 이 수리 밖)
CM <- fread(file.path(D2, "close_match_by_month.csv"))
CM[, `:=`(m = as.Date(paste0(month, "-01")), close = 100 * close_same / n, vol = 100 * vol_same / n)]
L2 <- rbind(CM[, .(m, v = close, w = "종가 일치율")], CM[, .(m, v = vol, w = "거래량 일치율")])
p2 <- ggplot(L2, aes(m, v, colour = w)) + geom_line(linewidth = 0.9) + geom_point(size = 1.8) +
  geom_vline(xintercept = as.Date("2026-09-01"), colour = MUTED, linetype = "dashed", linewidth = 0.4) +
  scale_colour_manual(values = c("종가 일치율" = C_PRE, "거래량 일치율" = C_POST), name = NULL) +
  scale_y_continuous(limits = c(0, 100)) + scale_x_date(date_labels = "%y-%m", date_breaks = "2 months") +
  labs(title = "퀀티 종가 vs 거래소 종가 — 월별 일치율(12종목 표본)",
       subtitle = sprintf("2026-08 까지 %.0f%% → 09 %.1f%% · 10 %.1f%% · 11 %.1f%% · 거래량은 계속 일치 — 종가 항목 정의가 바뀐 것으로 보인다(미확인)\n2025-10 전의 80%%대 = 이후 사건으로 수정된 2종목(퀀티 ÷ 원주가 비율이 사건일까지 일정 0.913 · 0.856 → 그 뒤 일치 — 정상)",
                      CM[month == "2026-08", close], CM[month == "2026-09", close], CM[month == "2026-10", close], CM[month == "2026-11", close]),
       x = NULL, y = "일치율(%)", caption = "출처: RAWDATA(퀀티) vs 네이버 모바일 일별 시세(거래소 원주가) · 같은 날 · 0.5원 이내 = 일치") + th(11)
f2 <- file.path(OUT, "d2_c2_close_match_by_month.png")
ggsave(f2, p2, width = 9, height = 5, dpi = 160, bg = "white", device = ragg::agg_png)
cat("[d2_rep] 차트", f1, f2, "\n")
if ("--charts-only" %in% a) quit(save = "no", status = 0L)

## 3) P1R03 15엔진 — D2 전 vs 후
CAT <- c(TOTAL = "토탈", FVALU = "밸류", FRISK = "위험", FCROW = "쏠림", FMOME = "모멘텀", FTECH = "기술적", FDEFE = "방어", FLIQU = "유동성",
         FQUAL = "퀄리티", FGROW = "성장", FINVE = "투자", FLEVE = "레버리지", FACCR = "발생액", FCONS = "컨센서스", FREGI = "국면")
num <- function(x) { v <- suppressWarnings(as.numeric(x)); if (length(v) == 1L) v else NA_real_ }
art_of <- function(dir, code) { p <- file.path(dir, paste0(code, ".json")); if (!file.exists(p)) return(NA_character_)
  j <- fromJSON(p); if (!isTRUE(j$ok)) return(NA_character_); sub("/+$", "", gsub("\\\\", "/", j$artifacts)) }
rd_auth <- function(ad) {
  if (is.na(ad) || !file.exists(file.path(ad, "authoritative_remeasure.json"))) return(NULL)
  j <- fromJSON(file.path(ad, "authoritative_remeasure.json"), simplifyVector = FALSE); e <- j$essence; g <- j$grade_v3
  list(grade = j$essence_grade %||% NA, calmar = num(e$calmar), cagr = num(e$cagr), tw = num(g$oos$calmar_tw), btw = num(g$oos$bench_calmar_tw),
       S = num(g$S), fa = num(g$fa$t_min), rv = g$rules_version %||% NA_character_, SB = num(g$S_B), band = g$band %||% NA_character_)
}
## 등급 규칙 판이 다른 '전' 기록(11-13 = v3.4) — 등급 v3.5 세션의 같은 산출물 재채점 시험(dry-run) 등급으로 같은 규칙끼리 비교한다(규칙 몫과 자료 몫을 가른다)
V35 <- file.path(ROOT, "04_Research/01_reports/grade_v35_cr_beta_selection_20261113/data/dryrun_v35_d1.csv")
V35 <- if (file.exists(V35)) fread(V35, select = c("dir", "grade", "basis"))[, dir := basename(dir)] else data.table(dir = character(0), grade = character(0), basis = character(0))
rd_ret <- function(ad) { if (is.na(ad)) return(NULL); r <- fread(file.path(ad, "03_period_returns.csv"), select = c("date", "ret_net")); r[, date := as.Date(date)][] }
OLD1 <- file.path(RD, "remeasure_d1_20261114/results"); OLD0 <- file.path(RD, "remeasure_seam_20261113/results"); NEW <- file.path(RD, "remeasure_d2_20261114/results")
M <- rbindlist(lapply(names(CAT), function(eng) {
  code <- paste0("P1R03_", eng, "_C0")
  ao <- art_of(OLD1, code); src <- "11-14 D1 뒤"; if (is.na(ao)) { ao <- art_of(OLD0, code); src <- "11-13 수익률 정정 뒤" }
  an <- art_of(NEW, code); o <- rd_auth(ao); n <- rd_auth(an); ro <- rd_ret(ao); rn <- rd_ret(an)
  is_same <- NA; first_diff <- NA_character_; n_diff <- NA_integer_
  if (!is.null(ro) && !is.null(rn)) {
    x <- merge(ro, rn, by = "date", suffixes = c("_o", "_n"))
    same_day <- (is.na(x$ret_net_o) & is.na(x$ret_net_n)) | (!is.na(x$ret_net_o) & !is.na(x$ret_net_n) & abs(x$ret_net_o - x$ret_net_n) <= 1e-9)   # 1e-9 = 등록부 값 반올림(1e-10 급) 허용
    dd <- x[!same_day]
    is_same <- nrow(dd[date <= TAU_D]) == 0L; n_diff <- nrow(dd); first_diff <- if (nrow(dd)) format(min(dd$date)) else "-"
  }
  rv_old <- o$rv %||% NA_character_; rv_new <- n$rv %||% NA_character_
  g_rule <- NA_character_
  if (!is.na(rv_old) && !is.na(rv_new) && rv_old != rv_new && !is.na(ao)) { h <- V35[dir == basename(ao)]; if (nrow(h)) g_rule <- h$grade[1] }
  data.table(code = eng, name = CAT[[eng]], before_src = src, g_old = o$grade %||% NA, rv_old = rv_old, g_old_rule = g_rule, g_new = n$grade %||% NA, rv_new = rv_new,
             calmar_old = o$calmar %||% NA, calmar_new = n$calmar %||% NA, tw_old = o$tw %||% NA, tw_new = n$tw %||% NA,
             btw = (n$btw %||% o$btw) %||% NA, S_old = o$S %||% NA, S_new = n$S %||% NA, fa_old = o$fa %||% NA, fa_new = n$fa %||% NA,
             band_old = o$band %||% NA, band_new = n$band %||% NA, SB_new = n$SB %||% NA,
             is_same = is_same, n_days_changed = n_diff, first_changed = first_diff, art_new = an)
}))
fwrite(M, file.path(REP, "p1r03_d2_before_after.csv"))
f2d <- function(x) ifelse(is.finite(x), sprintf("%.2f", x), "–")
M[, g_base := fifelse(!is.na(g_old_rule), g_old_rule, g_old)]                 # 같은 규칙(v3.5)끼리 비교할 '전' 등급
print(M[, .(name, g_old, rv_old, g_old_rule, g_new, rv_new, calmar_old = f2d(calmar_old), calmar_new = f2d(calmar_new), tw_old = f2d(tw_old), tw_new = f2d(tw_new),
            S_old = f2d(S_old), S_new = f2d(S_new), is_same, n_days_changed, first_changed)])
if (any(is.na(M$g_new))) stop("[d2_rep] D2 후 측정이 빠진 엔진: ", paste(M[is.na(g_new), name], collapse = ", "))
L3 <- rbind(M[, .(name, v = tw_old, w = "D2 전")], M[, .(name, v = tw_new, w = "D2 후")])
L3[, w := factor(w, levels = c("D2 전", "D2 후"))]; L3[, name := factor(name, levels = rev(M$name))]
bt <- M$btw[is.finite(M$btw)][1]
p3 <- ggplot(L3, aes(v, name, colour = w)) + geom_vline(xintercept = bt, colour = MUTED, linetype = "dashed", linewidth = 0.4) +
  geom_line(aes(group = name), colour = "#c9c7bf", linewidth = 0.8) + geom_point(size = 3) +
  scale_colour_manual(values = c("D2 전" = C_PRE, "D2 후" = C_POST), name = NULL) +
  labs(title = "P1R03 15엔진 — 시험 구간(OOS) Calmar, 수익률 단절 채움(D2) 전 vs 후",
       subtitle = sprintf("점선 = 같은 구간 KOSPI200 Calmar %.2f · IS(≤ 2022-12-31) 일간 수익 동일(|차| ≤ 1e-9) %d/%d 엔진", bt, sum(M$is_same, na.rm = TRUE), nrow(M)),
       x = "시험 구간 Calmar", y = NULL, caption = sprintf("출처: 각 측정 산출물 authoritative_remeasure.json(등급 규칙 후 %s · 전 %s) · D2 전 = 11-14 D1 재측정(%d엔진) · 나머지 = 11-13 재측정(%d엔진)",
                         paste(sort(unique(na.omit(M$rv_new))), collapse = "/"), paste(sort(unique(na.omit(M$rv_old))), collapse = "/"),
                         sum(M$before_src == "11-14 D1 뒤"), sum(M$before_src != "11-14 D1 뒤"))) + th(11)
f3 <- file.path(OUT, "d2_c3_p1r03_oos_calmar.png")
ggsave(f3, p3, width = 8.5, height = 6.4, dpi = 160, bg = "white", device = ragg::agg_png)
cat("[d2_rep] 차트", f3, "\n")
if ("--no-send" %in% a) quit(save = "no", status = 0L)

## IS 자격 판정 A/B(같은 코드 · 원 판정 규칙 — tools/p1r03_is_rejudge_ab.R 산출) — 있으면 실는다(판정은 다시 하지 않는다 · 원 판정 11-13 기록은 그대로)
ABF <- file.path(REP, "p1r03_is_rejudge_ab/is_rejudge_ab.csv")
ab_line <- NULL
if (file.exists(ABF)) {
  AB <- fread(ABF)
  abq <- dcast(AB, engine ~ side, value.var = "qualify")                  # 이름 = abq · abt — 전역 q · t 는 base::q · base::t 를 가린다
  abt <- dcast(AB, engine ~ side, value.var = "t_alpha_vis")
  ch <- abq[pre != post]
  ab_line <- sprintf("IS 자격 판정(β 통제 t(α) ≥ 2 ∧ 상승 포착 ≥ 0.55 · 같은 코드로 전 · 후 평가): 자격 %d → %d엔진%s",
                     sum(abq$pre, na.rm = TRUE), sum(abq$post, na.rm = TRUE),
                     if (nrow(ch)) paste0(" · 바뀐 엔진 ", paste(sprintf("%s(t %.2f → %.2f)", CAT[ch$engine], abt[match(ch$engine, abt$engine), pre], abt[match(ch$engine, abt$engine), post]), collapse = " · "))
                     else " · 바뀐 엔진 없음")
}
source(file.path(ROOT, "02_Infrastructure/programs/program_report.R"))
gtxt <- ifelse(!is.na(M$g_old_rule) & M$g_old_rule != M$g_old,
               sprintf("등급 %s(규칙 %s) → 같은 결과 규칙 %s 재채점 %s → %s", M$g_old, M$rv_old, M$rv_new, M$g_old_rule, M$g_new),
        ifelse(!is.na(M$rv_old) & !is.na(M$rv_new) & M$rv_old != M$rv_new & is.na(M$g_old_rule),
               sprintf("등급 %s(규칙 %s · 같은 규칙 재채점 없음 — 규칙 몫 미분리) → %s", M$g_old, M$rv_old, M$g_new),   # 침묵 혼합 방지
               sprintf("등급 %s → %s", M$g_base, M$g_new)))
f3d <- function(x) ifelse(is.finite(x), sprintf("%.3f", x), "–")
btxt <- ifelse(!is.na(M$band_old) & !is.na(M$band_new) & M$band_old != M$band_new,
               sprintf(" · 점수 띠 %s → %s(B 경계 S_B %s)", M$band_old, M$band_new, f3d(M$SB_new)), "")
ln <- sprintf("%s: %s · 전기간 Calmar %s → %s · 시험 구간 Calmar %s → %s · 종합점수 S %s → %s%s",
              M$name, gtxt, f2d(M$calmar_old), f2d(M$calmar_new), f2d(M$tw_old), f2d(M$tw_new), f3d(M$S_old), f3d(M$S_new), btxt)
gch <- M[g_base != g_new]; gl <- if (nrow(gch)) paste(sprintf("%s %s→%s%s", gch$name, gch$g_base, gch$g_new, ifelse(gch$band_old != gch$band_new, "(점수 띠 경계)", "")), collapse = " · ") else "없음(15엔진)"
rch <- M[!is.na(g_old_rule) & g_old_rule != g_old]
rl <- if (nrow(rch)) sprintf(" · 등급 규칙 v3.5 몫 %s", paste(sprintf("%s %s→%s", rch$name, rch$g_old, rch$g_old_rule), collapse = " · ")) else ""
extra <- list(
  list(heading = "무엇이 틀렸고 어떻게 채웠나", type = "bullet", items = c(
    "결함: RAWDATA 에 수정주가 기준이 끊긴 날의 수익률이 종가 비율 그대로(−37 ~ −99%) 남아 있었다. 11-14 17:31 에 시가총액 기준 실수익(그날 시가총액 ÷ 전날 − 1 · 날짜별 가격제한폭 안)으로 159행을 채웠다.",
    "정정(18:22): 시가총액 기준은 현금이 오가지 않는 사건(무상증자 · 분할 · 병합 · 무상감자)에서만 맞다. DART 공시로 사건 종류를 다시 확인해 10행을 고쳤다.",
    "코넥스 → 코스닥 이전상장 첫날 5행: 같은 날 일반공모 신주가 상장돼 시가총액이 부풀었다 → 종가 비율(코넥스 마지막 종가 → 코스닥 첫 종가)이 보유자 수익.",
    "장외(K-OTC) → 코스닥 상장 첫날 4행: 퀀티가 상장 뒤 가격만 이후 사건으로 수정해 종가 비율도 깨져 있었다 → 거래소 첫 종가 ÷ 장외 마지막 종가(예: 카페24 2018-02-08 +0.41% → −9.99%).",
    "확인한 값 14건은 근거와 함께 목록으로 남기고, 데이터 적재 때마다 그 값을 강제한다(다시 적재해도 같은 값).")),
  list(heading = "검증", type = "bullet", items = c(
    "거래소 원주가(체결 종가 · 기준가 · 공식 등락률)와 대조: 이전상장 4건 종가 비율 일치 · 장외 → 상장 첫날의 상장일 신주 비율 10~25%(공모 규모로 타당).",
    "수정주가 1~3원 동전주 75행은 시가총액 값이 표시 가격 반올림 구간 안 75/75 → 그대로.",
    "적용 전후 전 열 대조: 바뀐 것은 수익률 열뿐 · 정정 뒤 독립 감사 통과 · 못 채운 10행은 모두 측정 축 밖(2000 전 8 · 동전주 2).",
    "자체 점검에서 찾아 고친 것: D2 팩터 재계산이 밸류 · 성장 7개 팩터(B/M · E/P · CF/P · P/S · 매출 · 이익 · 자산 성장)의 퀀티 보충값(DART 에 없는 종목)을 빠뜨렸다(약 6.8만 행(442달 67,645 + 202611 340)). 보충 단계를 포함해 다시 계산했고, 두 달(2018-06 · 2026-09)을 전체 재계산과 대조해 7/7 일치를 확인한 뒤 15엔진을 쟀다.",
    sprintf("IS(≤ 2022-12-31) 일간 수익 동일(|차| ≤ 1e-9) %d/%d 엔진 · 달라진 엔진 = %s(D2 가 바꾼 2000~2022 수익률 · 팩터 값 위에서 보유가 조금씩 달라짐)",
            sum(M$is_same, na.rm = TRUE), nrow(M), paste(M[is_same == FALSE, name], collapse = " · ")),
    "등급 비교는 같은 규칙끼리: 11-13 기록(규칙 v3.4)은 등급 v3.5(위기 방어 가점에 시가총액 · β 일치 대조) 재채점 시험 등급과 나란히 적었다 — 규칙 몫과 데이터 몫을 가른다.",
    ab_line,
    "시험 구간 차이는 2026 날짜에 흩어져 있다(03-30 하루 차이는 0) — 03-30 빈칸 71행을 채워 4월 뒤 롤링 창 팩터(모멘텀 · 변동성 · β) 값과 보유가 바뀐 몫이다. 2026-09 뒤는 아래 새 결함 1(종가 정의 변화)도 함께 있다.")),
  list(heading = "엔진별(D2 전 → 후)", type = "bullet", items = ln),
  list(heading = "새로 나온 결함 2건(이 수리 밖 · 결정 필요)", type = "bullet", items = c(
    sprintf("퀀티 종가 vs 거래소 종가: 2026-08 까지 %.0f%% 일치 → 09 %.1f%% · 10 %.1f%% · 11 %.1f%%(거래량은 일치). 종가 항목 정의가 바뀐 것으로 보인다 — 09 이후 모든 수익률 · 벤치 정렬 영향.",
            CM[month == "2026-08", close], CM[month == "2026-09", close], CM[month == "2026-10", close], CM[month == "2026-11", close]),
    "RAWDATA 에 상장 전 장외 · 코넥스 이력이 있고 측정 유니버스에 상장일 거르기가 없다(예: 카페24 2009-05 ~). 나중에 상장한 종목에만 이력이 있다면 생존 편향 위험.")))
prep_send(program = "P1_RETURN", target = "P1R03 정정 3 — 수익률 단절 채움(사건 종류별) 뒤 15엔진 재측정",
          status = list(stage = "데이터 결함 수리 · 재측정(측정 신뢰 훼손)", position = "P1R03 15엔진 재측정 끝(같은 사양 · 정본 측정 계약)",
                        previous = "11-14 18:22 수익률 단절 채움 정정(사건 종류별 10행) · 팩터 DB · IC · 결합용 팩터 뷰 · FF 재계산 · 밸류 · 성장 7개 팩터 보충값 복구"),
          verdict_line = sprintf("%sD2 몫 등급 변화 %s%s · IS 일간 수익 동일 %d/15",
                                 if (!is.null(ab_line)) sprintf("IS 자격 판정 %s(%d/15) · ", if (nrow(ch)) "바뀜" else "그대로", sum(abq$post, na.rm = TRUE)) else "",
                                 gl, rl, sum(M$is_same, na.rm = TRUE)),
          next_step = "결정 필요: 퀀티 종가 정의 변화(리프레시 확인) · 상장 전 이력 유니버스 처리(도훈) · P1R04 재측정(1계층 세션)",
          artifact = REP, charts = c("수익률 단절 채움 — 사건 종류가 값을 정한다" = f1, "P1R03 15엔진 — 시험 구간 Calmar, D2 전 vs 후" = f3,
                                     "퀀티 종가 vs 거래소 종가 — 월별 일치율" = f2), push = TRUE, extra = extra)
