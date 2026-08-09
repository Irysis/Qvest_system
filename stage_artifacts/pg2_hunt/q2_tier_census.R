## q2 — 새 tier 로 40계열 재census: "계약 준수 ∧ 직교 교집합이 비어 있다" 가 여전히 맞는가
## r4 는 **10-component 파일명만** 보고 6/40 을 셌다. 그런데 harness_compliance 가
## 대체 검증 기록(walkforward_integrity·lockbox·prelb·subperiods)을 인식하도록 수리되면서
## STR_1698 이 "하네스 밖" → **validated_needs_retrofit** 으로 바뀌었다.
## ⇒ 직교 계열들도 검증 기록을 갖고 있다면 내 "구조적 공백" 결론이 약해진다. 다시 센다.
suppressPackageStartupMessages({ library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/pg2_hunt")
say  <- function(fmt, ...) { cat(sprintf(paste0("[q2] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R"); source("02_Infrastructure/contracts/harness_compliance.R")
INV <- readRDS(file.path(OUT,"s1_inventory.rds")); IDX <- INV$idx
C7  <- fread(file.path(OUT,"s7_census.csv"))

rows <- list(); t0 <- Sys.time()
for (j in INV$keep) {
  nm <- INV$names[j]; f <- gsub("\\\\","/", IDX$file[j])
  r <- tryCatch(harness_compliance(f), error=function(e) NULL)
  if (is.null(r)) next
  rows[[length(rows)+1L]] <- data.table(id=nm, ten=r$ten_component, c15=r$c15 %||% "미상",
    tier=r$tier, alt=length(r$alt_validation), metric_type=r$metric_type)
}
`%||%` <- function(a,b) if (is.null(a)||is.na(a)) b else a
R <- rbindlist(rows, fill=TRUE)
R <- merge(R, C7[, .(id, rho, ir, short, park_ok, lineage)], by="id", all.x=TRUE)
say("=== tier 분포 (%d계열, %.1f분) ===", nrow(R), as.numeric(difftime(Sys.time(),t0,units="mins")))
print(sort(table(R$tier), decreasing=TRUE))
say("=== ★핵심 질문: 직교(rho<0.3) 계열의 tier ===")
O <- R[rho < 0.3 & lineage == FALSE]
say("  직교 비계보 계열 **%d건**", nrow(O))
print(sort(table(O$tier), decreasing=TRUE))
say("  대체 검증 보유(alt>=2) **%d / %d**", sum(O$alt >= 2), nrow(O))
say("=== ★직교 ∧ 검증기록 보유 계열 (retrofit 후보) ===")
V <- O[tier %in% c("contract_compliant","contract_c15_undetected","validated_needs_retrofit")]
setorder(V, short)
if (nrow(V)) {
  say("  **%d건**:", nrow(V))
  say("  %-32s %-26s %5s %8s %8s %8s %6s", "strategy","tier","10-c","rho","IR","부족","파킹")
  for (i in seq_len(nrow(V)))
    say("  %-32s %-26s %5d %+8.3f %+8.3f %+8.3f %6s", substr(V$id[i],1,32), V$tier[i],
        V$ten[i], V$rho[i], V$ir[i], V$short[i], V$park_ok[i])
} else say("  ★0건")
say("=== ★결론 재판정 ===")
say("  r4 서술: '계약 준수 ∧ 직교 교집합이 구조적으로 비어 있다'")
if (nrow(V)) {
  say("  ⇒ ★**정정 필요** — 직교 ∧ 검증기록 계열이 **%d건** 있다. 공백은 '검증' 이 아니라", nrow(V))
  say("     **10-component 형식**의 공백이었다. 이들은 retrofit 대상이지 하네스 밖이 아니다.")
  say("     최선: %s (rho %+.3f · IR %+.3f · 부족 %+.3f · tier %s)",
      V$id[1], V$rho[1], V$ir[1], V$short[1], V$tier[1])
} else {
  say("  ⇒ 결론 유지 — 직교 계열 중 검증기록 보유 0건")
}
say("  ★어느 쪽이든 파킹 적용 가능 여부가 별도 관문이다(계열 종료 시점).")
fwrite(R, file.path(OUT,"q2_tier_census.csv"))
say("=== q2 완료 ===")
