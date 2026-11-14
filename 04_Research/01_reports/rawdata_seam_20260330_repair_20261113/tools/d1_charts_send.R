## 이음매 D1(가격 수준 팩터 연속 가격 · 11-14) — 차트 2장 + 텔레그램 1통(prep_send · qvest-telegram SKILL §0 · 정정 = 푸시)
##   실행: 저장소 루트에서 Rscript 04_Research/01_reports/rawdata_seam_20260330_repair_20261113/tools/d1_charts_send.R [--dry] [--no-send]
##   입력(수치 출처):
##     · M06 옛/새 = 옛 코드 vs 새 코드 대조 산출(저장 없음 · as-of 2026-04-30) — 스크래치 pxc_compare.rds 를 옮겨 적은 d1_price_continuity/m06_old_new_20260430.csv
##     · UMD(WML) 옛 = FF 요인 판 사본(월간 내용 md5 941e6a63d006) · 새 = 운영 .cache/kr_factor_returns_v2.parquet(654fcff70913)
##     · 칸 유형 분류 · IC 대조 = d1_price_continuity/(stage_report.json · cell_type_by_month.txt) — 판정 수치 아님(기술 통계)
suppressPackageStartupMessages({ library(data.table); library(jsonlite); library(ggplot2); library(arrow) })
ROOT <- sub("/+$", "", gsub("\\\\", "/", Sys.getenv("QM_ROOT", getwd())))
if (!file.exists(file.path(ROOT, "CLAUDE.md"))) ROOT <- gsub("\\\\", "/", getwd())
REP <- file.path(ROOT, "04_Research/01_reports/rawdata_seam_20260330_repair_20261113")
D1 <- file.path(REP, "d1_price_continuity"); OUT <- file.path(REP, "charts"); dir.create(OUT, showWarnings = FALSE)
a <- commandArgs(trailingOnly = TRUE)
if ("--dry" %in% a) Sys.setenv(QVEST_TG_DRY_RUN = "1")

C_PRE <- "#e34948"; C_POST <- "#2a78d6"; INK <- "#0b0b0b"; INK2 <- "#52514e"; MUTED <- "#898781"; GRID <- "#e1e0d9"
FAM <- ""
fdir <- c(file.path(Sys.getenv("LOCALAPPDATA"), "Microsoft", "Windows", "Fonts"), file.path(Sys.getenv("WINDIR", "C:/Windows"), "Fonts"))
fM <- file.path(fdir, "현대하모니+M.ttf"); fM <- fM[file.exists(fM)][1]
if (!is.na(fM)) { try(systemfonts::register_font(name = "HDHM", plain = fM), silent = TRUE); FAM <- "HDHM" }
th <- function(base = 12) theme_minimal(base_family = FAM, base_size = base) +
  theme(plot.title = element_text(size = base + 4, colour = INK), plot.title.position = "plot",
        plot.subtitle = element_text(size = base - 1.5, colour = INK2, lineheight = 1.15),
        plot.caption = element_text(size = base - 4, colour = MUTED, hjust = 0, lineheight = 1.1), plot.caption.position = "plot",
        panel.grid.minor = element_blank(), panel.grid.major = element_line(colour = GRID, linewidth = 0.3),
        axis.text = element_text(colour = INK2), legend.position = "top", legend.justification = "left")

## 1) M06 52주 고점 대비 — 이음매 종목(as-of 2026-04-30)
M <- fread(file.path(D1, "m06_old_new_20260430.csv"))
p1 <- ggplot(M, aes(old, new)) +
  geom_abline(slope = 1, intercept = 0, colour = MUTED, linewidth = 0.4, linetype = "dashed") +
  geom_point(colour = C_POST, alpha = 0.55, size = 1.6) +
  scale_x_continuous(limits = c(0, NA)) + scale_y_continuous(limits = c(0, NA)) +
  labs(title = "52주 고점 대비(M06) — 이음매 종목, 수리 전 vs 후",
       subtitle = sprintf("as-of 2026-04-30 · 값이 바뀐 이음매 종목 %d개 · 점선 = 변화 없음\n수리 전에는 기준 단절(×k) 때문에 값이 1 근처(높은 기준으로 바뀐 종목)나 0.1~0.3(낮은 기준으로 바뀐 종목)에 몰렸다", nrow(M)),
       x = "수리 전(원 종가 수준)", y = "수리 후(연속 가격)",
       caption = "출처: 옛 코드 vs 새 코드 대조(저장 없음) · 이음매 = 저장 수익률이 종가 비율과 다른 자리(2026-03-30 351종 외)") + th()
f1 <- file.path(OUT, "d1_c1_m06_old_new.png")
ggsave(f1, p1, width = 8, height = 6.2, dpi = 160, bg = "white", device = ragg::agg_png)

## 2) UMD 월수익 — 수리 전 vs 후
cfg <- fromJSON(file.path(ROOT, "06_Registry/kr_factor_returns.json"), simplifyVector = TRUE)
vd <- file.path(ROOT, ".cache", cfg$outputs$vintage_dir)
old_f <- list.files(vd, pattern = "^941e6a63d006.*\\.parquet$", full.names = TRUE)[1]
if (is.na(old_f)) stop("[d1_charts] 옛 FF 판 사본(941e6a63d006)이 없다: ", vd)
O <- as.data.table(read_parquet(old_f))[, .(Date = as.Date(Date), WML)]
N <- as.data.table(read_parquet(file.path(ROOT, ".cache", cfg$outputs$monthly)))[, .(Date = as.Date(Date), WML)]
W <- merge(O, N, by = "Date", suffixes = c("_old", "_new"))[Date >= as.Date("2026-03-01")]
WL <- melt(W, id.vars = "Date", variable.name = "v", value.name = "r")
WL[, v := factor(fifelse(v == "WML_old", "수리 전", "수리 후"), levels = c("수리 전", "수리 후"))]
p2 <- ggplot(WL, aes(format(Date, "%Y-%m"), 100 * r, fill = v)) + geom_col(position = position_dodge(width = 0.75), width = 0.7) +
  geom_hline(yintercept = 0, colour = INK2, linewidth = 0.3) +
  scale_fill_manual(values = c("수리 전" = C_PRE, "수리 후" = C_POST), name = NULL) +
  labs(title = "모멘텀 요인(UMD) 월수익 — 수리 전 vs 후",
       subtitle = "바뀐 달 = 2026-05 ~ 10(6개월 · 최대 1.58%p)\n2026-04 이전 UMD 와 다른 FF 요인(MKT · SMB · HML · RMW · CMA)은 322개월 동일",
       x = NULL, y = "월수익(%)", caption = "출처: FF 요인 빌더(build_kr_factor_returns.R) 수리 전(월간 md5 941e6a63d006) vs 수리 후(654fcff70913)") + th()
f2 <- file.path(OUT, "d1_c2_umd_old_new.png")
ggsave(f2, p2, width = 8.6, height = 5.4, dpi = 160, bg = "white", device = ragg::agg_png)
cat("[d1_charts] ", f1, " · ", f2, "\n")
if ("--no-send" %in% a) quit(save = "no", status = 0L)

source(file.path(ROOT, "02_Infrastructure/programs/program_report.R"))
ch <- c("52주 고점 대비(M06) — 이음매 종목, 수리 전 vs 후(as-of 2026-04-30)" = f1,
        "모멘텀 요인(UMD) 월수익 — 수리 전 vs 후(2026-03 ~ 10)" = f2)
extra <- list(
  list(heading = "무엇이 틀렸나", type = "bullet", items = c(
    "11-13 수리로 수익률은 고쳤지만, 종가 수준은 2026-03-30(351종) · 10-15(1종) · 11-10(3종) 처분 자리에서 그대로 끊겨 있었다.",
    "그래서 여러 날의 가격 비율을 쓰는 팩터가 2026-03 이후 값에서 틀렸다. 10:1 분할 종목의 52주 고점 대비가 0.1 근처였고, 거래정지 종목(347원 → 5,820원 단절)에는 가짜 변동성과 ADX 100 이 찍혔다. 모멘텀 요인(UMD)의 종목 정렬도 같은 이유로 틀렸다.")),
  list(heading = "어떻게 고쳤나", type = "bullet", items = c(
    "연속 가격 배율: 저장 수익률이 종가 비율과 다른 자리에서만 1이 아닌 배율을 종목 안에서 누적한다. 날짜를 넘는 가격 비율이 수익률 연쇄와 같아지고, 그날까지의 값만 쓰므로 미래 정보가 들어가지 않는다.",
    "대상 23팩터: 모멘텀 6(+ 합성 1) · 기술적 12 · 방어(Yang-Zhang 변동성) · 유동성(야간 스프레드) · 밸류(복합 지분발행) · 쏠림(ADX). FF 요인 빌더의 모멘텀 정렬(UMD)도 같은 방식으로 고쳤다.",
    "가격 수준 자체(동전주 바닥 · 로그 가격 · 목표가 괴리)는 이 수리에서 바꾸지 않았다. 따로 정할 문제다.")),
  list(heading = "검증", type = "bullet", items = c(
    "2026-02 이전 as-of 값은 비트 단위로 같다(정정 자리 이전 배율 = 1 · 실자료로 2022-12 · 2026-02 확인). IS 판정은 바뀌지 않는다.",
    "202603 ~ 202611: 이음매가 아닌 종목은 값 변화 0 · 값 소실 0. 이음매 종목은 달마다 3,800 ~ 6,800개 값이 정정됐다.",
    "IC 월간 원장: 대상 밖 팩터 112,906행 동일 · 대상 23팩터의 2026-03 ~ 09 값 161행만 바뀌었다. FF 요인: UMD 6개월만 바뀌었다(최대 1.58%p).",
    "시험 3종 통과(단위 · 모듈 실구동 대조 · 돌연변이 · 배선 · FF 모멘텀).")),
  list(heading = "영향", type = "bullet", items = c(
    "이 23팩터를 쓰는 측정은 재측정 전까지 A 자격 · 기저 풀 자격이 자동 보류된다(데이터 버전 기록 PRICE-CONTINUITY-FACTORS-20261113).",
    "UMD 가 바뀌어 팩터 조정 알파(Carhart4 · FF6)의 시험 구간 마지막 6개월이 움직인다. 등급 재채점은 v3.5 교체 때 한 번에 반영한다.",
    "P1R03 에서 수익률이 바뀌는 엔진 7개(모멘텀 · 기술적 · 밸류 · 방어 · 유동성 · 쏠림 · 토탈)는 오늘 P1R04 측정 뒤에 재측정한다.")))
prep_send(program = "P1_RETURN",
          target = "데이터 정정 — 가격 수준 팩터 연속 가격(이음매 D1)",
          status = list(stage = "데이터 결함 수리(측정 신뢰 훼손 — 도훈 11-13 '1번은 다시 계산해주고')",
                        position = "팩터 DB 23팩터(2026-03 ~ 11) · IC 원장 · 결합용 팩터 뷰 · FF 요인 UMD 재계산 끝(11-14 16:23)",
                        previous = "11-13 수익률 이음매 수리 · P1R03 15엔진 재측정(IS 판정 불변 · OOS 정정)"),
          verdict_line = "IS 값 비트 동일 · 2026-03 이후 가격 수준 팩터 정정 — 이음매 아닌 종목의 값 변화 0 · UMD 6개월만 변화(최대 1.58%p)",
          next_step = "P1R04 재측정(1계층 세션) → P1R03 영향 7엔진 재측정 → 결과 보고 · 결정 대기: 원천 내부 단절(D2) 처리 방식",
          artifact = REP, charts = ch, push = TRUE, extra = extra)
