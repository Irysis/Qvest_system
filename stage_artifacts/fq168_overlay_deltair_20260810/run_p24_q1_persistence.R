## P24 — **내가 오늘 만든 계약을 같은 칼로 재기**: q1 은 지속적 base 성질인가
## 사전등록(측정 전 고정, 이 주석이 정본):
##  P23b 가 rel14 를 죽인 근거는 유의성이 아니라 **비지속성**이었다 — 홀수달로 정의한 군과
##    짝수달로 정의한 군의 **Jaccard 0.182**. ⇒ 같은 시험을 **q1 에도** 걸어야 공정하다.
##    q1 이 같은 성질이면 오늘 발행한 `overlay_precheck` 문턱은 **실현-표본 서술**로 강등되고
##    계약에 그 한정을 박아야 한다. **자기 명제를 반증하는 경로**를 여는 것이 이 라운드다.
##  ★사전 예상(기록해 둔다): q1 은 **평균 비중**이고 rel14 는 4구간 중 **argmax 위치**다.
##    argmax 는 구조적으로 불안정하므로 q1 이 더 안정할 것으로 예상 — 그러나 **예상은 판정이 아니다**.
##  측정(전부 p16_q1_vs_effect.csv 재분석, 새 측정 0):
##   ①연속량 지속성 = spearman(q1_odd, q1_evn) + pearson
##   ②군 지속성 = 계약 문턱(>=0.25)으로 정의한 '높음' 군의 홀/짝 **Jaccard**
##   ③rel14 대조 = P23b 의 0.182 와 나란히 (같은 척도로 비교하는 것이 요점)
##   ④문턱 근방 흔들림 = 판정(GO/CAUTION/NO_GO)이 홀/짝에서 **바뀌는 base 수**
##  판정:
##   J1_PERSISTENT     : rho >= 0.7 ∧ Jaccard >= 0.6 → 계약 근거 유지
##   J2_WEAK           : 하나만 충족 → 계약에 한정 문구 추가
##   J3_NOT_PERSISTENT : 둘 다 미달 → **q1 도 실현-표본 서술**. 문턱 강등 + 계약 개정 의무
##  ★자본 주장 없음. ★결과가 어느 쪽이든 계약에 반영한다(J1 이어도 근거를 기록).
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
CODE_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.claude/worktrees/jovial-mcnulty-f7d018"
OUT <- file.path(CODE_ROOT, "stage_artifacts/fq168_overlay_deltair_20260810")
D <- fread(file.path(OUT, "p16_q1_vs_effect.csv"))
cat(sprintf("[입력 실측] base %d · 열 %s\n", nrow(D), paste(names(D), collapse=",")))
stopifnot(all(c("q1_odd","q1_evn","q1_all") %in% names(D)))
D <- D[is.finite(q1_odd) & is.finite(q1_evn)]
cat(sprintf("[입력 실측] q1_all %.3f~%.3f · q1_odd %.3f~%.3f · q1_evn %.3f~%.3f (n=%d)\n",
            min(D$q1_all), max(D$q1_all), min(D$q1_odd), max(D$q1_odd),
            min(D$q1_evn), max(D$q1_evn), nrow(D)))

cat("\n=== ① 연속량 지속성 ===\n")
rho <- suppressWarnings(cor(D$q1_odd, D$q1_evn, method="spearman"))
pea <- suppressWarnings(cor(D$q1_odd, D$q1_evn, method="pearson"))
cat(sprintf("  spearman(q1_odd, q1_evn) = **%+.3f**   pearson = %+.3f   (n=%d)\n", rho, pea, nrow(D)))

cat("\n=== ② 군 지속성 — 계약 문턱(>=0.25)으로 정의한 '높음' 군 ===\n")
hi_o <- D[q1_odd >= 0.25, base]; hi_e <- D[q1_evn >= 0.25, base]
inter <- intersect(hi_o, hi_e); uni <- union(hi_o, hi_e)
jac <- if (length(uni)) length(inter)/length(uni) else NA_real_
cat(sprintf("  홀 %d건 · 짝 %d건 · 교집합 %d · 합집합 %d → **Jaccard %.3f**\n",
            length(hi_o), length(hi_e), length(inter), length(uni), jac))
if (length(uni)) cat(sprintf("  홀에만: %s\n  짝에만: %s\n",
    paste(setdiff(hi_o,hi_e), collapse=", "), paste(setdiff(hi_e,hi_o), collapse=", ")))

cat("\n=== ③ rel14 와 같은 척도로 대조 (P23b) ===\n")
cat(sprintf("  rel14 군 Jaccard **0.182**  vs  q1 군 Jaccard **%.3f**\n", jac))

cat("\n=== ④ 계약 판정이 홀/짝에서 바뀌는가 ===\n")
vd <- function(q) ifelse(q >= 0.28, "NO_GO", ifelse(q >= 0.25, "CAUTION", "GO"))
D[, `:=`(v_odd = vd(q1_odd), v_evn = vd(q1_evn), v_all = vd(q1_all))]
flip <- D[v_odd != v_evn]
cat(sprintf("  판정 불일치 **%d / %d** (%.0f%%)\n", nrow(flip), nrow(D), 100*nrow(flip)/nrow(D)))
if (nrow(flip)) print(flip[, .(base, q1_odd, v_odd, q1_evn, v_evn, q1_all, v_all)])
## 부호가 갈린 4점(근거)이 흔들리는가 — 계약의 실증 기반
key <- c("FAM_L","FAM_CR","FAM_S","PG2")
cat("\n  [근거 4점] 계약이 선 실측점들의 홀/짝 판정\n")
print(D[base %in% key, .(base, q1_all, v_all, q1_odd, v_odd, q1_evn, v_evn)])

verdict <- if (isTRUE(rho >= 0.7) && isTRUE(jac >= 0.6)) "J1_PERSISTENT" else
           if (isTRUE(rho >= 0.7) || isTRUE(jac >= 0.6)) "J2_WEAK" else "J3_NOT_PERSISTENT"
cat(sprintf("\n판정: **%s**  (rho %.3f vs 0.7 · Jaccard %.3f vs 0.6)\n", verdict, rho, jac))
write_json(list(verdict=verdict, n=nrow(D), rho_spearman=rho, pearson=pea, jaccard=jac,
                rel14_jaccard_reference=0.182, n_verdict_flip=nrow(flip),
                flips=flip[, .(base,q1_odd,v_odd,q1_evn,v_evn)],
                key4=D[base %in% key, .(base,q1_all,v_all,v_odd,v_evn)],
                source="p16_q1_vs_effect.csv 재분석 · 새 측정 없음"),
           file.path(OUT,"p24_result.json"), pretty=TRUE, auto_unbox=TRUE, digits=NA)
