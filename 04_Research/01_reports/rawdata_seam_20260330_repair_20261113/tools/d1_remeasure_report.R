## 이음매 D1 — P1R03 영향 7엔진 재측정 수리 전(11-13 · Ret 정정 뒤 · D1 전) vs 후(11-14 · D1 뒤) 표 · 차트 · 텔레그램 1통
##   실행: 저장소 루트에서 Rscript 04_Research/01_reports/rawdata_seam_20260330_repair_20261113/tools/d1_remeasure_report.R [--dry] [--no-send]
##   수치 출처(AX-008 — 등급 · 판정 값은 다시 계산하지 않는다): 각 산출물 authoritative_remeasure.json(essence · grade_v3) ·
##     일간 수익 동일성 = 03_period_returns.csv(ret_net) 기술 비교(판정 아님)
##   수리 전 = P1R03 remeasure_seam_20261113/results/<칸>.json::artifacts · 수리 후 = remeasure_d1_20261114/results/<칸>.json::artifacts
suppressPackageStartupMessages({ library(data.table); library(jsonlite); library(ggplot2) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
ROOT <- sub("/+$", "", gsub("\\\\", "/", Sys.getenv("QM_ROOT", getwd())))
if (!file.exists(file.path(ROOT, "CLAUDE.md"))) ROOT <- gsub("\\\\", "/", getwd())
REP <- file.path(ROOT, "04_Research/01_reports/rawdata_seam_20260330_repair_20261113")
OUT <- file.path(REP, "charts"); dir.create(OUT, showWarnings = FALSE)
RD <- file.path(ROOT, "04_Research/programs/P1_RETURN/P1R03_factor_family_composites")
OLD <- file.path(RD, "remeasure_seam_20261113/results"); NEW <- file.path(RD, "remeasure_d1_20261114/results")
a <- commandArgs(trailingOnly = TRUE); if ("--dry" %in% a) Sys.setenv(QVEST_TG_DRY_RUN = "1")
CAT <- c(FMOME = "모멘텀", FTECH = "기술적", FVALU = "밸류", FDEFE = "방어", FLIQU = "유동성", FCROW = "쏠림", TOTAL = "토탈")
D1_FIRST <- as.Date("2026-04-01")   # 바뀐 첫 신호 = 2026-03 월말 → 그 보유가 버는 첫 날 이후만 바뀔 수 있다
num <- function(x) { v <- suppressWarnings(as.numeric(x)); if (length(v) == 1L) v else NA_real_ }
art_of <- function(dir, code) { p <- file.path(dir, paste0(code, ".json")); if (!file.exists(p)) return(NA_character_)
  j <- fromJSON(p); if (!isTRUE(j$ok)) return(NA_character_); sub("/+$", "", gsub("\\\\", "/", j$artifacts)) }
rd_auth <- function(ad) {
  if (is.na(ad) || !file.exists(file.path(ad, "authoritative_remeasure.json"))) return(NULL)
  j <- fromJSON(file.path(ad, "authoritative_remeasure.json"), simplifyVector = FALSE); e <- j$essence; g <- j$grade_v3
  list(grade = j$essence_grade %||% NA, calmar = num(e$calmar), cagr = num(e$cagr), sharpe = num(e$net_sharpe), mdd = num(e$mdd),
       tw = num(g$oos$calmar_tw), btw = num(g$oos$bench_calmar_tw), S = num(g$S), fa = num(g$fa$t_min),
       blocked = paste(unlist(g$blocked_by), collapse = " · "))
}
rd_ret <- function(ad) { if (is.na(ad)) return(NULL); r <- fread(file.path(ad, "03_period_returns.csv"), select = c("date", "ret_net")); r[, date := as.Date(date)][] }
M <- rbindlist(lapply(names(CAT), function(c) {
  code <- paste0("P1R03_", c, "_C0"); ao <- art_of(OLD, code); an <- art_of(NEW, code); o <- rd_auth(ao); n <- rd_auth(an)
  ro <- rd_ret(ao); rn <- rd_ret(an); same_pre <- NA; first_diff <- NA_character_; n_diff <- NA_integer_
  if (!is.null(ro) && !is.null(rn)) {
    x <- merge(ro, rn, by = "date", suffixes = c("_o", "_n"))
    dd <- x[!(ret_net_o == ret_net_n | (is.na(ret_net_o) & is.na(ret_net_n)))]
    same_pre <- nrow(dd[date < D1_FIRST]) == 0L; n_diff <- nrow(dd); first_diff <- if (nrow(dd)) format(min(dd$date)) else "-"
  }
  data.table(code = c, name = CAT[[c]], g_old = o$grade %||% NA, g_new = n$grade %||% NA,
             calmar_old = o$calmar %||% NA, calmar_new = n$calmar %||% NA, cagr_old = o$cagr %||% NA, cagr_new = n$cagr %||% NA,
             tw_old = o$tw %||% NA, tw_new = n$tw %||% NA, btw = (n$btw %||% o$btw) %||% NA,
             S_old = o$S %||% NA, S_new = n$S %||% NA, fa_old = o$fa %||% NA, fa_new = n$fa %||% NA, blk_new = n$blocked %||% NA,
             same_before_0401 = same_pre, n_days_changed = n_diff, first_changed = first_diff, art_new = an)
}))
fwrite(M, file.path(REP, "p1r03_d1_before_after.csv"))
f2 <- function(x) ifelse(is.finite(x), sprintf("%.2f", x), "–"); pc <- function(x) ifelse(is.finite(x), sprintf("%+.1f%%", 100 * x), "–")
print(M[, .(name, g_old, g_new, calmar_old = f2(calmar_old), calmar_new = f2(calmar_new), tw_old = f2(tw_old), tw_new = f2(tw_new), btw = f2(btw),
            S_old = f2(S_old), S_new = f2(S_new), fa_old = f2(fa_old), fa_new = f2(fa_new), same_before_0401, n_days_changed, first_changed)])

## 차트 — OOS(시험 구간) Calmar 수리 전 → 후 · 같은 구간 KOSPI200
L <- rbind(M[, .(name, v = tw_old, w = "D1 전(11-13)")], M[, .(name, v = tw_new, w = "D1 후(11-14)")])
L[, w := factor(w, levels = c("D1 전(11-13)", "D1 후(11-14)"))]; L[, name := factor(name, levels = rev(M$name))]
FAM <- ""; fdir <- c(file.path(Sys.getenv("LOCALAPPDATA"), "Microsoft", "Windows", "Fonts"), file.path(Sys.getenv("WINDIR", "C:/Windows"), "Fonts"))
fM <- file.path(fdir, "현대하모니+M.ttf"); fM <- fM[file.exists(fM)][1]
if (!is.na(fM)) { try(systemfonts::register_font(name = "HDHM", plain = fM), silent = TRUE); FAM <- "HDHM" }
bt <- M$btw[is.finite(M$btw)][1]
g <- ggplot(L, aes(v, name, colour = w)) + geom_vline(xintercept = bt, colour = "#898781", linetype = "dashed", linewidth = 0.4) +
  geom_line(aes(group = name), colour = "#c9c7bf", linewidth = 0.8) + geom_point(size = 3) +
  scale_colour_manual(values = c("D1 전(11-13)" = "#e34948", "D1 후(11-14)" = "#2a78d6"), name = NULL) +
  labs(title = "P1R03 영향 7엔진 — 시험 구간(OOS) Calmar, D1 전 vs 후",
       subtitle = sprintf("점선 = 같은 구간 KOSPI200 Calmar %.2f · 2026-03-31 이전 일간 수익은 7엔진 모두 같다", bt),
       x = "시험 구간 Calmar", y = NULL, caption = "출처: 각 측정 산출물 authoritative_remeasure.json(등급 v3.4) · D1 전 = 11-13 재측정(수익률 정정 뒤)") +
  theme_minimal(base_family = FAM, base_size = 12) +
  theme(plot.title.position = "plot", plot.caption.position = "plot", plot.caption = element_text(size = 8, colour = "#898781", hjust = 0),
        plot.subtitle = element_text(size = 10, colour = "#52514e"), legend.position = "top", legend.justification = "left",
        panel.grid.minor = element_blank(), panel.grid.major = element_line(colour = "#e1e0d9", linewidth = 0.3))
fc <- file.path(OUT, "d1_c3_p1r03_oos_calmar.png"); ggsave(fc, g, width = 8, height = 5, dpi = 160, bg = "white", device = ragg::agg_png)
cat("[d1_rm] 차트", fc, "\n")
if ("--no-send" %in% a) quit(save = "no", status = 0L)

source(file.path(ROOT, "02_Infrastructure/programs/program_report.R"))
ln <- sprintf("%s: 등급 %s → %s · 전기간 Calmar %s → %s · 시험 구간 Calmar %s → %s · 종합점수 S %s → %s",
              M$name, M$g_old, M$g_new, f2(M$calmar_old), f2(M$calmar_new), f2(M$tw_old), f2(M$tw_new), f2(M$S_old), f2(M$S_new))
chg <- M[g_old != g_new]; gl <- if (nrow(chg)) paste(sprintf("%s %s→%s", chg$name, chg$g_old, chg$g_new), collapse = " · ") else "등급 변화 없음(7엔진)"
extra <- list(
  list(heading = "엔진별(D1 전 → 후)", type = "bullet", items = ln),
  list(heading = "검증", type = "bullet", items = c(
    sprintf("2026-03-31 이전 일간 수익: %d/%d 엔진 비트 동일 — 바뀐 첫 날 = 바뀐 첫 신호(2026-03 월말) 뒤 보유일", sum(M$same_before_0401, na.rm = TRUE), nrow(M)),
    "IS(≤ 2022-12-31) 자격 판정은 바뀌지 않는다. 바뀐 값은 시험 구간 끝 7개월(2026-04 ~ 10)뿐이다.",
    "나머지 8엔진은 수익률이 그대로이고, 팩터 조정 알파(UMD 6개월 변화)는 등급 v3.5 교체 때 일괄 재채점한다.")))
prep_send(program = "P1_RETURN", target = "P1R03 정정 2 — 가격 수준 팩터 연속 가격(D1) 뒤 영향 7엔진 재측정",
          status = list(stage = "데이터 결함 수리 · 재측정(측정 신뢰 훼손)", position = "P1R03 영향 7엔진 재측정 끝(같은 사양 · 정본 측정 계약)",
                        previous = "11-14 16:23 D1 데이터 정정(팩터 DB 23팩터 · IC · 결합용 팩터 뷰 · FF UMD)"),
          verdict_line = sprintf("IS 판정 불변 · 시험 구간 끝 7개월 값 정정 — %s", gl),
          next_step = "결정 대기: 원천 내부 단절(D2) 처리 방식 · P1R04 재측정(1계층 세션)",
          artifact = REP, charts = c("P1R03 영향 7엔진 — 시험 구간 Calmar, D1 전 vs 후" = fc), push = TRUE, extra = extra)
