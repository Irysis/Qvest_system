## FQ-182 적대검증 P3 — delete-1 최대 영향일(2026-07-30 신호 / 2026-07-31 수익) 정체 검사
## P2 실측: 이 1일 제거만으로 왜도 diff 가 44% 감소. 값 fwd1 = +0.1998 (일간 +20%).
## ★존재 검사가 아니라 정체 검사: 이 값이 실재 사건인가, 원천 데이터 결함인가.
suppressPackageStartupMessages({ library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/FQ182")
say  <- function(fmt, ...) { cat(sprintf(paste0("[p3] ", fmt, "\n"), ...)); flush.console() }

D <- as.data.table(readRDS(file.path(OUT, "p0.rds"))$D)[order(Date)]
say("=== 전체 표본 극단 일간수익 상위/하위 10 ===")
S <- D[order(-abs(BM_Ret))][1:12, .(Date, BM_Ret = round(BM_Ret,5), dd252 = round(dd252,4))]
print(S)
say("|BM_Ret| >= 10%% 인 날: %d일 · >=15%%: %d일 · >=20%%: %d일",
    D[abs(BM_Ret)>=0.10,.N], D[abs(BM_Ret)>=0.15,.N], D[abs(BM_Ret)>=0.20,.N])
say("전체 sd %.5f -> 최대 절대수익은 %.1f 표준편차", sd(D$BM_Ret), max(abs(D$BM_Ret))/sd(D$BM_Ret))

say(""); say("=== 2026-07 ~ 2026-08 구간 원계열 ===")
print(D[Date >= as.Date("2026-07-01"), .(Date, BM_Ret = round(BM_Ret,5),
        dd252 = round(dd252,4), fwd1 = round(fwd1,5))])

say(""); say("=== 연도별 |BM_Ret| >= 10%% 발생 ===")
D[, yr := as.integer(format(Date, "%Y"))]
print(D[abs(BM_Ret)>=0.10, .(n = .N, max_abs = round(max(abs(BM_Ret)),4)), by = yr][order(yr)])

say(""); say("=== 원천 대조: alloc_daily/p0.rds$BD ===")
BDp <- file.path(ROOT, "stage_artifacts/alloc_daily/p0.rds")
if (file.exists(BDp)) {
  BD <- as.data.table(readRDS(BDp)$BD)[order(Date)]
  say("  BD 행수 %d · %s ~ %s · 컬럼 %s", nrow(BD), as.character(min(BD$Date)),
      as.character(max(BD$Date)), paste(names(BD), collapse=","))
  print(BD[Date >= as.Date("2026-07-20"), .SD, .SDcols = intersect(names(BD),
        c("Date","BM_Ret","dd252","BM_Close","Close"))])
} else say("  ★원천 파일 없음: %s", BDp)

say(""); say("=== ★최근 20일 vs 역사 변동성 대비 ===")
D[, yr := NULL]
recent <- D[Date >= as.Date("2026-07-08")]
say("  2026-07-08~ (n=%d) sd %.5f · 역사 sd %.5f · 배율 %.2fx",
    nrow(recent), sd(recent$BM_Ret), sd(D$BM_Ret), sd(recent$BM_Ret)/sd(D$BM_Ret))
say("  이 구간 수익: %s", paste(sprintf("%+.3f", recent$BM_Ret), collapse=" "))
