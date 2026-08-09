## h2 — 중복의 정밀 규정: "완전 중복" 인가 "겹치는 곳에서만 동일 + 커버리지 상이" 인가
## h1 이 겹침 66,543행에서 완전동일을 봤는데 내 331 측정 성과는 달랐다(C01 rho 0.423 vs C10 0.306).
## 동일 벡터인데 성과가 다르면 **커버리지가 다르다**. 처분(배출 차단)이 달라지므로 정밀화한다.
suppressPackageStartupMessages({ library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/pg2_hunt")
say  <- function(fmt, ...) { cat(sprintf(paste0("[h2] ", fmt, "\n"), ...)); flush.console() }

A <- readRDS(file.path(OUT, "factor_long.rds"))
pairs <- list(c("C01_SUE","C10_SUE_Persistence"), c("C04_ESBR","C13_Revision_Breadth_3m"))
for (p in pairs) {
  a <- A[Factor_Name == p[1], .(Date, Ticker, za = z)]
  b <- A[Factor_Name == p[2], .(Date, Ticker, zb = z)]
  say("=== %s vs %s ===", p[1], p[2])
  say("  단독 행수: %s **%d행/%d개월** · %s **%d행/%d개월**",
      p[1], nrow(a), uniqueN(a$Date), p[2], nrow(b), uniqueN(b$Date))
  J <- merge(a, b, by = c("Date","Ticker"), all = TRUE)
  say("  합집합 %d행 · 교집합 %d · %s 단독 %d · %s 단독 %d",
      nrow(J), sum(!is.na(J$za) & !is.na(J$zb)),
      p[1], sum(!is.na(J$za) & is.na(J$zb)), p[2], sum(is.na(J$za) & !is.na(J$zb)))
  ov <- J[!is.na(za) & !is.na(zb)]
  say("  ★교집합에서 완전동일: %s (최대절대차 %.3e)", identical(ov$za, ov$zb), max(abs(ov$za-ov$zb)))
  ## 커버리지 차이가 어디서 오는가 — 월별
  ma <- a[, .(na = .N), by = Date]; mb <- b[, .(nb = .N), by = Date]
  MM <- merge(ma, mb, by = "Date", all = TRUE)
  MM[is.na(na), na := 0L][is.na(nb), nb := 0L]
  say("  월별 종목수: %s 중앙 %.0f · %s 중앙 %.0f · 같은 달 %d/%d",
      p[1], median(MM$na), p[2], median(MM$nb), sum(MM$na == MM$nb), nrow(MM))
  say("  %s 만 있는 달 %d · %s 만 있는 달 %d",
      p[1], sum(MM$nb == 0), p[2], sum(MM$na == 0))
  d <- MM[na != nb][order(Date)]
  if (nrow(d)) {
    say("  ★차이 나는 달 %d개 · 예시:", nrow(d))
    print(head(d, 5)); print(tail(d, 3))
  }
  say("  ⇒ %s", if (identical(ov$za, ov$zb) && nrow(MM[na != nb]) == 0)
      "**완전 중복** — 배출 차단 안전" else
      "**교집합 동일 + 커버리지 상이** — 한쪽만 있는 구간이 있으므로 단순 차단 시 정보 손실 가능")
}

say("=== ★처분 권고 (도훈/후속 태스크용) ===")
say("  1) 두 쌍 모두 교집합에서 **바이트 동일** = 같은 계산의 중복 배출이 맞다.")
say("  2) 단 커버리지가 다르면 차단 대상은 '중복 이름' 이 아니라 **중복 구간**이다.")
say("     처분 전 확인: 커버리지가 넓은 쪽을 남기고 좁은 쪽을 deprecated 로.")
say("  3) ★내 331 측정에서 두 쌍이 각각 다른 성과를 낸 것은 **커버리지 차이의 결과**이며,")
say("     이는 '유효 독립 재료 수' 계산에 영향을 준다(종합이 295~307 로 추정한 값).")
say("  4) 실제 코드 수정(compute_consensus.R 배출 차단)은 factor_db 생산 변경이므로")
say("     이 라운드에서 하지 않는다 — 칩으로 분리하고 도훈 판단에 올린다.")
say("=== h2 완료 ===")
