## s3 — s2 결함 2건 수리 + 근접 재료 정확 식별
##  ①자기유사 가드 `rho>0.95` 가 **0건 제외** — STR_1715_WT016(rho 0.945)이 문턱 바로 아래로 통과.
##    PG2 = STR_1715_on_M4_R05_noLayer4 이므로 **명백한 자기 파생**인데 분포 통계에 들어갔다.
##    ⇒ 상관 문턱(모양 휴리스틱) 대신 **계보 식별**(이름)로 바꾼다 — 오늘 반복한 정체 검사 규약.
##  ②부족분 최소 0.002 가 어느 계열인지 표에서 정확히 짚는다(s2 는 값만 출력했다).
suppressPackageStartupMessages({ library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/pg2_hunt")
say  <- function(fmt, ...) { cat(sprintf(paste0("[s3] ", fmt, "\n"), ...)); flush.console() }
R <- fread(file.path(OUT, "s2_strategies.csv"))
say("=== 입력 실측 === %d계열", nrow(R))

## ── ① 계보 식별 (PG2 = STR_1715_on_M4_R05_noLayer4) ─────────────────────────
LIN <- "STR_1715|STR_1716|pg2|AR_M4|M4_R05|noLayer4"
R[, lineage := grepl(LIN, id, ignore.case = TRUE)]
say("=== ① 계보 식별 (이름 기반) ===")
say("  PG2 계보 패턴: %s", LIN)
say("  계보 판정 **%d / %d**:", sum(R$lineage), nrow(R))
for (i in which(R$lineage)) say("    %-34s rho %+.3f · IR %+.3f", substr(R$id[i],1,34), R$rho[i], R$ir[i])
say("  ★구 가드(rho>0.95) 제외 수 = %d — **0건이라 계보가 통계에 섞였다**", sum(R$rho > 0.95))
say("  ★rho 0.7 이상인데 계보 아닌 계열 %d건 — 이들은 별도 확인 필요:",
    sum(R$rho > 0.7 & !R$lineage))
for (i in which(R$rho > 0.7 & !R$lineage)) say("    %-34s rho %+.3f · IR %+.3f", substr(R$id[i],1,34), R$rho[i], R$ir[i])

V <- R[lineage == FALSE]
say("=== ② 계보 제외 후 분포 (%d계열) ===", nrow(V))
say("  rho  중앙 %+.3f · [%.3f, %.3f]", median(V$rho), min(V$rho), max(V$rho))
say("  IR   중앙 %+.3f · [%.3f, %.3f] · **>=0.7 %d건**", median(V$ir), min(V$ir), max(V$ir), sum(V$ir>=0.7))
say("  부족분 중앙 %.3f · **최소 %.3f**", median(V$short, na.rm=TRUE), min(V$short, na.rm=TRUE))
say("  ΔIR  중앙 %+.4f · 최고 %+.4f", median(V$dIR), max(V$dIR))

say("=== ③ ★근접 8건 정확 식별 (부족분 오름차순) ===")
say("  %-34s %8s %8s %9s %9s %10s %-16s", "strategy","rho","IR","필요IR","부족","ΔIR","verdict_ci")
for (i in order(V$short)[1:min(8,nrow(V))])
  say("  %-34s %+8.3f %+8.3f %9.3f %+9.3f %+10.4f %-16s", substr(V$id[i],1,34),
      V$rho[i], V$ir[i], V$need[i], V$short[i], V$dIR[i], V$verdict[i])

say("=== ④ ★s2 의 '부족분 최소 0.002' 정체 ===")
i0 <- which.min(R$short)
say("  전체(계보 포함) 최소: **%s** — rho %+.3f · IR %+.3f · 필요 %.3f · 부족 %+.3f · 계보 %s",
    R$id[i0], R$rho[i0], R$ir[i0], R$need[i0], R$short[i0], R$lineage[i0])
i1 <- which.min(V$short)
say("  계보 제외 최소   : **%s** — rho %+.3f · IR %+.3f · 필요 %.3f · **부족 %+.3f** · ΔIR %+.4f",
    V$id[i1], V$rho[i1], V$ir[i1], V$need[i1], V$short[i1], V$dIR[i1])
say("  ⇒ 팩터DB 최소 0.142 대비 %s",
    if (V$short[i1] < 0.142) sprintf("★개선 (%.3f)", V$short[i1]) else sprintf("미달 (%.3f)", V$short[i1]))

say("=== ⑤ ★핵심 구조: IR 과 rho 가 함께 간다 ===")
say("  cor(rho, IR) 전체 %+.3f · 계보 제외 %+.3f",
    cor(R$rho, R$ir, use="complete.obs"), cor(V$rho, V$ir, use="complete.obs"))
say("  rho<0.4 계열(%d): IR 중앙 %+.3f · rho>=0.4 계열(%d): IR 중앙 %+.3f",
    sum(V$rho<0.4), median(V[rho<0.4, ir]), sum(V$rho>=0.4), median(V[rho>=0.4, ir]))
say("  ⇒ ★**높은 IR 은 높은 상관과 함께 온다** — 오늘 331 라운드에서 본 것과 같은 구조가")
say("     완성 전략 풀에서도 재현된다. 이것이 book-marginal 의 근본 벽이다.")
say("=== ⑥ 최종 판정 ===")
say("  1급(IR>=필요) 계보 제외 **%d / %d** · CI 하단>=0.05 **%d**",
    sum(V$ir >= V$need, na.rm=TRUE), nrow(V), sum(V$lo >= 0.05, na.rm=TRUE))
fwrite(R, file.path(OUT,"s3_strategies_lineage.csv"))
say("=== s3 완료 ===")
