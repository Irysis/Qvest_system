## n6 — insider_sell_panel 의 두 결함 규명 (측정 착수 가부 판정)
##  결함A: cnv_off_* ≡ cnv_all_* 상관 1.000 → 임원/전체 필터 미작동 (신호 6종이 아니라 3종)
##  결함B: 값 크기 물리 불가 (min -5.0e25 / max +8.8e28 / sd 5.1e26) — 6변수 전부 동일 극단
## ★목표: ①결함이 몇 건인지 ②소수 이상치인지 전면 오염인지 ③랭킹으로 우회 가능한지
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/pg2_hunt")
say  <- function(fmt, ...) { cat(sprintf(paste0("[n6] ", fmt, "\n"), ...)); flush.console() }

f <- "stage_artifacts/WT_D20260718_002/insider_sell_panel.parquet"
I <- as.data.table(read_parquet(f))
SIG <- grep("^cnv_", names(I), value=TRUE)
for (s in SIG) I[[s]] <- suppressWarnings(as.numeric(I[[s]]))

say("=== A. off ≡ all 동일성 실측 ===")
for (w in c(3,6,12)) {
  a <- I[[sprintf("cnv_off_%d", w)]]; b <- I[[sprintf("cnv_all_%d", w)]]
  say("  창 %2d: 완전 동일 %s · 다른 행 %d/%d · 최대 절대차 %.3e",
      w, identical(a, b), sum(a != b, na.rm=TRUE), length(a), max(abs(a-b), na.rm=TRUE))
}
say("  ⇒ %s", if (all(vapply(c(3,6,12), function(w)
      identical(I[[sprintf("cnv_off_%d",w)]], I[[sprintf("cnv_all_%d",w)]]), TRUE)))
  "★off/all 이 **바이트 수준 동일** — 임원 필터가 적용되지 않았다(생산 코드 결함)" else "일부만 동일")

say("=== B. 극단값의 정체 ===")
v <- I$cnv_all_12
q <- quantile(v[is.finite(v)], c(0, .001, .01, .25, .5, .75, .99, .999, 1))
say("  분위: %s", paste(sprintf("%s=%.3e", names(q), q), collapse=" "))
say("  |v| > 1e12 인 행: **%d / %d (%.4f%%)**", sum(abs(v) > 1e12, na.rm=TRUE), length(v),
    100*mean(abs(v) > 1e12, na.rm=TRUE))
say("  |v| > 1e6  인 행: %d (%.3f%%)", sum(abs(v) > 1e6, na.rm=TRUE), 100*mean(abs(v) > 1e6, na.rm=TRUE))
ext <- I[abs(cnv_all_12) > 1e12]
say("  극단 행의 종목 %d개 · 월 %d개", uniqueN(ext$Ticker), uniqueN(ext$ym))
if (nrow(ext)) {
  say("  극단 상위 5:")
  print(head(ext[order(-abs(cnv_all_12)), .(Ticker, ym, cnv_all_3, cnv_all_12)], 5))
  say("  극단 종목 빈도 상위:"); print(head(sort(table(ext$Ticker), decreasing=TRUE), 5))
}
say("=== 극단 제외 시 분포 (정상 성분이 존재하는가) ===")
vc <- v[is.finite(v) & abs(v) <= 1e6]
say("  |v|<=1e6 인 %d행: 중앙 %.4f · sd %.4f · [%.3f, %.3f] · 0비율 %.1f%%",
    length(vc), median(vc), sd(vc), min(vc), max(vc), 100*mean(vc==0))
say("  ⇒ %s", if (sd(vc) > 0 && length(vc) > 0.9*length(v))
   "★정상 성분이 대다수 — 극단은 소수 오염" else "★전면 오염 의심")

say("=== C. 랭킹으로 우회 가능한가 ===")
say("  ★랭킹은 스케일에 불변이지만 **극단값의 순위 자체가 틀렸다면** 우회가 아니다.")
I[, r12 := frank(cnv_all_12, ties.method="average", na.last="keep"), by = ym]
I[, r12w := frank(pmin(pmax(cnv_all_12, -1e6), 1e6), ties.method="average", na.last="keep"), by = ym]
say("  월내 랭킹 vs winsorize(±1e6) 후 랭킹 상관 %.6f",
    cor(I$r12, I$r12w, use="complete.obs"))
say("  순위가 바뀐 행 %d (%.3f%%)", sum(I$r12 != I$r12w, na.rm=TRUE),
    100*mean(I$r12 != I$r12w, na.rm=TRUE))
say("  ⇒ %s", if (cor(I$r12, I$r12w, use="complete.obs") > 0.999)
   "★랭킹은 극단에 거의 불변 — 랭킹 기반 슬리브는 결함을 우회한다" else
   "★랭킹도 영향받음 — 우회 불가")

say("=== D. ★0 비율이 랭킹을 무너뜨리는가 (더 큰 문제일 수 있다) ===")
z <- I[, .(zero_pct = mean(cnv_all_12 == 0, na.rm=TRUE), n = .N), by = ym]
say("  월별 0 비율: 중앙 %.1f%% · [%.1f%%, %.1f%%]",
    100*median(z$zero_pct), 100*min(z$zero_pct), 100*max(z$zero_pct))
say("  ★0 이 절반이면 top-25 선별 시 **동점이 25를 넘어** 사실상 무작위 선택이 된다")
say("  월별 비영(非零) 종목수: 중앙 %.0f · 25 미만인 달 %d/%d",
    median(I[, sum(cnv_all_12 != 0, na.rm=TRUE), by=ym]$V1),
    sum(I[, sum(cnv_all_12 != 0, na.rm=TRUE), by=ym]$V1 < 25),
    uniqueN(I$ym))

say("=== ★착수 판정 ===")
nz_ok <- median(I[, sum(cnv_all_12 != 0, na.rm=TRUE), by=ym]$V1) >= 25
rk_ok <- cor(I$r12, I$r12w, use="complete.obs") > 0.999
say("  랭킹 우회 %s · 비영 종목수 충분 %s", if (rk_ok) "가능" else "불가", if (nz_ok) "예" else "★아니오")
say("  %s", if (rk_ok && nz_ok)
  "★랭킹 기반으로 착수 가능 — 단 ①off/all 중복이라 신호 3종 ②스케일 결함은 별도 수리 대상(칩)" else
  "★착수 불가 — 데이터 수리가 선행")
say("=== n6 완료 ===")
