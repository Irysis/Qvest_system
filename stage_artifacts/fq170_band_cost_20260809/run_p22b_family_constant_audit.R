## P22b — 계열 상수 19 감사: 접두 규칙이 실제 계열을 반영하는가
## 사전등록(측정 전 고정, 이 주석이 정본):
##  `CP_FACTOR_DB_CLUSTERS = 19` 는 내가 `fam_of()` = sub("^([A-Za-z]+)[0-9_].*$", "\\1", x) 로 센 값이다.
##  **틀리면 오늘의 군집 판정 전부(P19b GO / P20a NO_GO)와 '19 vs 20 하나 차이' 서술이 함께 움직인다.**
##  의심 지점(측정 전 나열):
##   S1 폴백 발동: 규칙이 안 맞아 `substr(x,1,3)` 으로 떨어진 이름 — 계열이 이름조각으로 쪼개진다
##   S2 이형 접두: `XF_DU01_NetMargin` 처럼 접두가 두 겹인 것
##   S3 크기 1 계열: 혼자인 계열은 진짜 계열이 아니라 파싱 사고일 수 있다
##   S4 병합 후보: 서로 다른 접두인데 의미상 같은 계열(예: R / RE, IN / INV, C / CR)
##  ★S4 는 **판정이 아니라 목록 제시**다 — 의미 판단은 도훈/후속 라운드 몫이고,
##    여기서는 **경계 사례가 몇 개이고 그것들이 상수를 어디까지 움직이는지**만 낸다.
##  산출: 계열 수의 **하한/상한 범위**와, 그 범위에서 오늘 판정이 뒤집히는지.
##  ★read-only. 새 성과 측정 없음.
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
DATA_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
CODE_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.claude/worktrees/jovial-mcnulty-f7d018"
setwd(DATA_ROOT)
OUT <- file.path(CODE_ROOT, "stage_artifacts/fq170_band_cost_20260809")
source(file.path(CODE_ROOT, "02_Infrastructure/factor_db/factor_db_connector.R"))
source(file.path(CODE_ROOT, "02_Infrastructure/contracts/cluster_power.R"))

B <- as.data.table(readRDS("stage_artifacts/WT_D20260809_003/merged_panel.rds")); B[, Date := as.Date(Date)]
ds <- sort(unique(B$Date))
probe <- as.data.table(load_month_factors(ds[floor(length(ds)/2)]))
ALL <- sort(unique(probe$Factor_Name))
cat(sprintf("[입력 실측] 팩터 %d종\n", length(ALL)))

rule_raw <- function(x) sub("^([A-Za-z]+)[0-9_].*$", "\\1", x)
D <- data.table(base = ALL)
D[, raw := rule_raw(base)]
D[, fallback := raw == base]                       # 규칙 불일치 → 폴백
D[, fam := ifelse(fallback, substr(base, 1, 3), raw)]

cat(sprintf("\n[S1] 폴백 발동: %d / %d\n", sum(D$fallback), nrow(D)))
if (any(D$fallback)) print(head(D[fallback == TRUE, .(base, fam)], 12))

F <- D[, .(n = .N, ex = paste(head(base, 2), collapse = ", ")), by = fam][order(-n)]
cat(sprintf("\n[현행] 계열 %d종 (상수 기록 %d)\n", nrow(F), CP_FACTOR_DB_CLUSTERS))
print(F)

cat(sprintf("\n[S3] 크기 1 계열: %d종 — %s\n", sum(F$n == 1L),
            paste(F[n == 1L, fam], collapse = ", ")))
cat("\n[S2] 접두 두 겹 의심(이름에 '_' 앞 조각이 2글자 이상 + 두 번째 조각도 문자로 시작):\n")
two <- D[grepl("^[A-Za-z]{2,}_[A-Za-z]", base)]
if (nrow(two)) print(head(two[, .(base, fam)], 10)) else cat("  (없음)\n")

cat("\n[S4] 병합 후보 — 한쪽이 다른쪽의 접두인 계열쌍 (판정 아님, 목록):\n")
fams <- sort(F$fam); pairs <- list()
for (a in fams) for (b in fams) if (a != b && startsWith(b, a))
  pairs[[length(pairs)+1L]] <- data.table(shorter = a, longer = b,
                                          n_short = F[fam==a, n], n_long = F[fam==b, n])
PP <- if (length(pairs)) rbindlist(pairs) else data.table()
if (nrow(PP)) print(PP) else cat("  (없음)\n")

## 상수의 하한/상한: 모두 병합(하한) ~ 현행(상한)
n_hi <- nrow(F)
n_lo <- if (nrow(PP)) n_hi - uniqueN(PP$longer) else n_hi
cat(sprintf("\n★계열 수 범위: 하한 %d(병합 후보 전부 합침) ~ 현행/상한 %d · 상수 기록 %d\n",
            n_lo, n_hi, CP_FACTOR_DB_CLUSTERS))

## 오늘 판정이 이 범위에서 뒤집히는가
chk <- function(nc) list(p19b = cp_feasibility(0.500, nc, 52L)$verdict,
                         p20a = cp_feasibility(0.410, 15L, 43L)$verdict,   # P20a 는 자기 표본 계열 15 고정
                         need45 = cp_required_n(0.45), crit = round(cp_critical_rho(nc), 3))
for (nc in unique(c(n_lo, CP_FACTOR_DB_CLUSTERS, n_hi))) {
  r <- chk(nc)
  cat(sprintf("  계열 %2d → 임계 %.3f · P19b(rho .500) %s · rho0.45 필요군집 %s\n",
              nc, r$crit, r$p19b, r$need45))
}
flip <- length(unique(vapply(unique(c(n_lo, n_hi)), function(nc)
  cp_feasibility(0.500, nc, 52L)$verdict, character(1)))) > 1L
cat(sprintf("\n범위 내에서 P19b 판정 뒤집힘: %s\n", flip))
verdict <- if (nrow(F) != CP_FACTOR_DB_CLUSTERS) "M1_CONSTANT_WRONG" else
           if (flip) "M2_FRAGILE" else "M3_ROBUST"
cat(sprintf("판정: %s\n", verdict))
if (verdict == "M1_CONSTANT_WRONG")
  cat(sprintf("⇒ 상수를 %d → %d 로 고치고 오늘 판정 재산출\n", CP_FACTOR_DB_CLUSTERS, nrow(F)))
if (verdict == "M2_FRAGILE")
  cat("⇒ 병합 판단이 결론을 바꾼다 — 계열 정의를 명시적 필드로 못박아야 한다(휴리스틱 금지)\n")
fwrite(F, file.path(OUT, "p22b_families.csv"))
write_json(list(verdict=verdict, n_factors=nrow(D), n_fam_current=nrow(F),
                constant_recorded=CP_FACTOR_DB_CLUSTERS, n_fallback=sum(D$fallback),
                n_singleton=sum(F$n==1L), n_lo=n_lo, n_hi=n_hi, flips=flip,
                merge_pairs=PP, families=F),
           file.path(OUT, "p22b_result.json"), pretty=TRUE, auto_unbox=TRUE, digits=NA)
