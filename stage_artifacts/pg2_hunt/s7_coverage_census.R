## s7 — 전략 풀 40계열의 **커버리지 census** + 파킹 적용 가부 사유 분해
## s6 확인: STR_1698 은 2024-04 에 끝나 파킹 겹침 51 < 60 → 계약이 정확히 차단.
## ⇒ 후보들이 왜 막히는지 **사유별로** 센다(조용한 skip 금지 — 오늘 내 코드가 어긴 규약).
suppressPackageStartupMessages({ library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/pg2_hunt")
say  <- function(fmt, ...) { cat(sprintf(paste0("[s7] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R"); source("02_Infrastructure/contracts/book_marginal.R")
mi <- function(d) as.integer(format(d,"%Y"))*12L + as.integer(format(d,"%m"))
lab <- function(m) sprintf("%04d-%02d", (m-1L)%/%12L, (m-1L)%%12L+1L)

inc <- bm_load_incumbent(); inc[, m := mi(date)]
INV <- readRDS(file.path(OUT,"s1_inventory.rds"))
Mru <- fread(file.path(ROOT,"stage_artifacts/FQ191/p1_rule.csv"))[, date := as.Date(date)][date < as.Date("2026-01-01")]
LB <- data.table(m = mi(Mru$date) + 2L, on = as.logical(Mru$regime))
S3 <- fread(file.path(OUT,"s3_strategies_lineage.csv"))
say("=== 라벨 창 === %s ~ %s (%d개월)", lab(min(LB$m)), lab(max(LB$m)), nrow(LB))

rows <- list()
for (j in INV$keep) {
  nm <- INV$names[j]; S <- INV$ser[[j]]
  ovPG <- length(intersect(S$m, inc$m))
  ovLB <- length(intersect(S$m, LB$m))
  rows[[length(rows)+1L]] <- data.table(id = nm, n = nrow(S),
    from = lab(min(S$m)), to = lab(max(S$m)), ov_pg2 = ovPG, ov_park = ovLB,
    park_ok = ovLB >= 60L)
}
C <- rbindlist(rows)
C <- merge(C, S3[, .(id, rho, ir, short, dIR, lineage)], by="id", all.x=TRUE)
setorder(C, short)
say("=== ★커버리지 census (%d계열) ===", nrow(C))
say("  %-32s %9s %9s %7s %7s %7s", "strategy", "from", "to", "PG2", "파킹", "가능")
for (i in seq_len(min(14, nrow(C))))
  say("  %-32s %9s %9s %7d %7d %7s", substr(C$id[i],1,32), C$from[i], C$to[i],
      C$ov_pg2[i], C$ov_park[i], C$park_ok[i])
say("  ...")
say("=== ★파킹 적용 가부 사유 분해 ===")
say("  파킹 가능(겹침>=60): **%d / %d**", sum(C$park_ok), nrow(C))
say("  불가 사유:")
say("    계열이 라벨 창보다 먼저 끝남(to < %s): **%d건**", lab(max(LB$m)), sum(C$ov_park < 60 & C$to < lab(max(LB$m))))
say("    그 외(시작 늦음/결측): %d건", sum(C$ov_park < 60) - sum(C$ov_park < 60 & C$to < lab(max(LB$m))))
say("  종료 시점 분포:"); print(sort(table(substr(C$to, 1, 4)), decreasing = TRUE))
say("=== ★파킹 가능한 계열의 성적 ===")
P <- C[park_ok == TRUE & lineage == FALSE]
if (nrow(P)) {
  say("  %d계열 · 부족분 중앙 %.3f · 최소 **%.3f** (%s)",
      nrow(P), median(P$short, na.rm=TRUE), min(P$short, na.rm=TRUE), P[which.min(short), id])
  for (i in order(P$short)[1:min(5,nrow(P))])
    say("    %-32s rho %+.3f · IR %+.3f · 부족 %+.3f · 파킹겹침 %d",
        substr(P$id[i],1,32), P$rho[i], P$ir[i], P$short[i], P$ov_park[i])
} else say("  ★파킹 가능 + 비계보 계열 **0건** — 레버를 적용할 대상이 없다")
say("=== ★판정 ===")
say("  최고 후보 STR_1698: 부족 %.3f 이나 계열이 %s 종료 → 파킹 겹침 %d < 60",
    C[id=="STR_1698_WT008_M08_Swap", short], C[id=="STR_1698_WT008_M08_Swap", to],
    C[id=="STR_1698_WT008_M08_Swap", ov_park])
say("  ⇒ **데이터 신선도가 레버 적용을 막는다** — 결과가 나빠서가 아니다.")
say("  ⇒ 다음: ①전략 계열을 최신까지 연장(생산 코드 재실행) 또는 ②전략 창에 맞춘 라벨 재구성")
fwrite(C, file.path(OUT,"s7_census.csv"))
say("=== s7 완료 → s7_census.csv ===")
