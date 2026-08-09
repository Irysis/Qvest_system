## n7 — n6 의 두 오진 정정 + 올바른 문턱으로 재판정
## ★내 오진 2건 (자가 검거):
##  ①"off ≡ all, 임원 필터 미작동" — 틀렸다. 10,318~15,852행(11.5~17.7%)이 실제로 다르다.
##    n5 의 상관 1.000 은 **8.77e28 이상치 하나가 Pearson 을 지배**한 아티팩트다.
##    ⇒ 규약: 극단 꼬리가 있는 변수의 중복 판정에 **Pearson 을 쓰지 말 것**(rank/Spearman 로).
##  ②"랭킹 우회 불가" — 틀렸다. winsorize 문턱을 ±1e6 으로 잡았는데 **정상값의 50.8%가 1e6 초과**다
##    (값 단위가 금액(원)으로 보인다). 정상 데이터를 잘라놓고 순위가 바뀐다고 판정했다.
##    ⇒ 문턱은 **오염 구간**(|v|>1e12, 0.55%)에서 잡아야 한다.
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/pg2_hunt")
say  <- function(fmt, ...) { cat(sprintf(paste0("[n7] ", fmt, "\n"), ...)); flush.console() }

I <- as.data.table(read_parquet("stage_artifacts/WT_D20260718_002/insider_sell_panel.parquet"))
SIG <- grep("^cnv_", names(I), value=TRUE)
for (s in SIG) I[[s]] <- suppressWarnings(as.numeric(I[[s]]))

say("=== 1. ★중복 판정을 Spearman 으로 (Pearson 은 이상치가 지배) ===")
M <- as.matrix(I[, ..SIG])
say("  %-12s %-12s %10s %10s", "A", "B", "Pearson", "Spearman")
for (w in c(3,6,12)) {
  a <- I[[sprintf("cnv_off_%d",w)]]; b <- I[[sprintf("cnv_all_%d",w)]]
  say("  cnv_off_%-4d cnv_all_%-4d %10.4f %10.4f", w, w,
      cor(a, b, use="complete.obs"), cor(a, b, method="spearman", use="complete.obs"))
}
say("  ⇒ Spearman 이 1 보다 뚜렷이 낮으면 **두 계열은 다른 정보** — n5 의 1.000 은 이상치 산물")
CS <- suppressWarnings(cor(M, method="spearman", use="pairwise.complete.obs"))
say("  6변수 Spearman 최대 비대각 %.4f (Pearson 은 %.4f)",
    max(abs(CS[upper.tri(CS)])), max(abs(suppressWarnings(cor(M, use="pairwise.complete.obs"))[upper.tri(CS)])))

say("=== 2. ★올바른 문턱으로 랭킹 안정성 재측정 ===")
say("  오염 구간 정의: |v| > 1e12 (0.55%% · 24종목) — 물리 불가 크기")
say("  %-10s %12s %12s %12s", "문턱", "자르는 비율", "랭킹 상관", "순위변경%")
for (th in c(1e6, 1e9, 1e11, 1e12, 1e13)) {
  I[, rr := frank(cnv_all_12, ties.method="average", na.last="keep"), by = ym]
  I[, rw := frank(pmin(pmax(cnv_all_12, -th), th), ties.method="average", na.last="keep"), by = ym]
  say("  %10.0e %11.2f%% %12.6f %11.2f%%", th, 100*mean(abs(I$cnv_all_12) > th, na.rm=TRUE),
      cor(I$rr, I$rw, use="complete.obs"), 100*mean(I$rr != I$rw, na.rm=TRUE))
}
say("  ⇒ ★오염 구간(1e12)에서 자를 때 랭킹이 보존되면 **랭킹 기반 슬리브는 결함을 우회**한다")

say("=== 3. 값의 정체 — 금액인가 ===")
vc <- I$cnv_all_12[is.finite(I$cnv_all_12) & I$cnv_all_12 != 0 & abs(I$cnv_all_12) < 1e12]
say("  비영·비오염 %d행: 중앙 |v| %.3e · 1사분위 %.3e · 3사분위 %.3e",
    length(vc), median(abs(vc)), quantile(abs(vc),.25), quantile(abs(vc),.75))
say("  ⇒ 중앙 %.1f억원 규모 — **거래금액(원)으로 정합**. 0(47%%) = 그 달 내부자 매매 없음",
    median(abs(vc))/1e8)
say("  ★따라서 '0 비율 47%%' 는 결함이 아니라 **사건 희소성**이다(내 n6 서술 정정).")
say("     단 top-25 선별 시 동점 0 이 많으면 선별이 무의미해지므로, **비영 종목 안에서만** 랭킹해야 한다.")
nz <- I[, .(n_nz = sum(cnv_all_12 != 0, na.rm=TRUE)), by = ym]
say("  월별 비영 종목수 중앙 %.0f · 25 미만 %d/%d 개월 · 50 미만 %d",
    median(nz$n_nz), sum(nz$n_nz < 25), nrow(nz), sum(nz$n_nz < 50))

say("=== 4. ★오염의 정체 (수리 가능한가) ===")
ext <- I[abs(cnv_all_12) > 1e12]
say("  오염 %d행 · %d종목 · %d개월", nrow(ext), uniqueN(ext$Ticker), uniqueN(ext$ym))
say("  오염 종목: %s", paste(head(sort(unique(ext$Ticker)), 12), collapse=", "))
say("  ★A011070 2019-01 = 8.77e28 원 = 한국 GDP 의 10^13 배 — 파싱/오버플로우 결함 확정")
say("  12개월 창이 그 값을 끌고 가 2019-02~12 까지 오염(cnv_all_12 동일값 유지 관측)")
say("  ⇒ 수리는 **원천 파서** 문제이므로 이 라운드 밖(칩 분리). 측정은 랭킹+오염 절단으로 우회.")

say("=== ★최종 착수 판정 ===")
th <- 1e12
I[, rr := frank(cnv_all_12, ties.method="average", na.last="keep"), by = ym]
I[, rw := frank(pmin(pmax(cnv_all_12, -th), th), ties.method="average", na.last="keep"), by = ym]
rk_ok <- cor(I$rr, I$rw, use="complete.obs") > 0.999
nz_ok <- median(nz$n_nz) >= 50
say("  랭킹 안정(1e12 절단) %s · 비영 종목수 충분 %s", rk_ok, nz_ok)
say("  %s", if (rk_ok && nz_ok)
  "★★착수 가능 — 신호 = 비영 종목 내 월별 랭킹(오염 1e12 winsorize) · 방향 = 매도 강도 낮을수록 long" else
  "★착수 불가")
say("=== n7 완료 ===")
