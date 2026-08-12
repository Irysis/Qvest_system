## P22b-2 — 선언된 계열 분류를 읽는다 (내 문자열 휴리스틱 대체)
## 사전등록(측정 전 고정, 이 주석이 정본):
##  P22b 에서 계열 수 19 는 **내 접두 문자열 규칙** 산물임이 드러났고, 병합 판단에 취약(M2_FRAGILE)했다.
##  ★그런데 커넥터에 `group_factors_by_family()` 가 이미 있고 `factor_registry.json` 의
##    **선언 필드**(`category` / `labels$economic_family`)를 읽는다 ⇒ **정답 배관이 있었는데 안 썼다**.
##  ⇒ 선언 분류의 **실제 고유값 수**를 세고, 그 수로 오늘 판정을 재산출한다.
##  ★이건 상수 하나가 아니라 **오늘의 모든 군집 판정(P19b/P20a)과 '19 vs 20' 서술**을 좌우한다.
##  판정:
##   N1_MATCHES  : 선언 계열 수 ≈ 19 → 내 휴리스틱이 우연히 맞았다(상수 유지)
##   N2_COARSER  : 선언 계열 수 < 19 → 임계가 **올라가고** 오늘 판정이 더 강하게 미달
##   N3_FINER    : 선언 계열 수 > 19 → 임계가 내려가 질문이 다시 열릴 수 있다
##  ★read-only.
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
DATA_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
CODE_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.claude/worktrees/jovial-mcnulty-f7d018"
setwd(DATA_ROOT)
OUT <- file.path(CODE_ROOT, "stage_artifacts/fq170_band_cost_20260809")
source(file.path(CODE_ROOT, "02_Infrastructure/contracts/cluster_power.R"))

## registry 위치 탐색 (정체 검사: 파일을 실제로 열어 필드를 확인한다)
cands <- c("02_Infrastructure/factor_db/factor_registry.json",
           "06_Registry/factor_registry.json",
           ".cache/factor_registry.json")
hit <- cands[file.exists(cands)]
cat(sprintf("[registry 탐색] 후보 %d · 존재 %s\n", length(cands),
            if (length(hit)) paste(hit, collapse=", ") else "(없음)"))
if (!length(hit)) {
  f <- list.files("02_Infrastructure", pattern="factor_registry.*\\.json$", recursive=TRUE, full.names=TRUE)
  cat(sprintf("  재귀 탐색: %s\n", if (length(f)) paste(head(f,3), collapse=", ") else "(없음)"))
  hit <- head(f, 1)
}
if (!length(hit)) { cat("⇒ registry 부재 — 선언 분류 확인 불가. 이것 자체가 발견.\n")
  write_json(list(verdict="REGISTRY_ABSENT"), file.path(OUT,"p22b2_result.json"),
             pretty=TRUE, auto_unbox=TRUE, digits=NA); quit(save="no") }
REG <- fromJSON(hit[1], simplifyVector = FALSE)
cat(sprintf("[registry] %s · 항목 %d\n", hit[1], length(REG)))

getf <- function(x, path) { v <- x; for (k in path) { v <- if (is.list(v)) v[[k]] else NULL; if (is.null(v)) return(NA_character_) }
                            if (length(v) && is.character(v)) v[1] else NA_character_ }
D <- rbindlist(lapply(names(REG), function(nm) data.table(
  base = nm,
  category = getf(REG[[nm]], "category"),
  econ_fam = getf(REG[[nm]], c("labels","economic_family")))), fill = TRUE)
cat(sprintf("\n필드 보유: category %d/%d · economic_family %d/%d\n",
            sum(!is.na(D$category)), nrow(D), sum(!is.na(D$econ_fam)), nrow(D)))
cat("\n=== category 고유값 ===\n"); print(D[!is.na(category), .N, by=category][order(-N)])
cat("\n=== economic_family 고유값 ===\n"); print(D[!is.na(econ_fam), .N, by=econ_fam][order(-N)])

n_cat <- uniqueN(D[!is.na(category), category]); n_ef <- uniqueN(D[!is.na(econ_fam), econ_fam])
n_decl <- max(n_cat, n_ef, na.rm = TRUE)
cat(sprintf("\n★선언 계열 수: category %d · economic_family %d → 채택 %d (내 휴리스틱 19)\n",
            n_cat, n_ef, n_decl))
cat("\n=== 오늘 판정 재산출 ===\n")
for (nc in sort(unique(c(n_cat, n_ef, 19L)))) {
  if (!is.finite(nc) || nc < 3L) next
  cat(sprintf("  계열 %2d → 임계 %.3f · P19b(rho .500) %-22s · P20a(rho .410) %s\n", nc,
              cp_critical_rho(nc), cp_feasibility(0.500, nc, 52L)$verdict,
              cp_feasibility(0.410, nc, 43L)$verdict))
}
verdict <- if (!is.finite(n_decl)) "REGISTRY_NO_FIELD" else
           if (abs(n_decl - 19L) <= 1L) "N1_MATCHES" else
           if (n_decl < 19L) "N2_COARSER" else "N3_FINER"
cat(sprintf("\n판정: %s\n", verdict))
if (verdict == "N2_COARSER")
  cat(sprintf("⇒ 임계가 %.3f → %.3f 로 **올라간다**. 오늘 판정은 더 강하게 미달이고 '19 vs 20 하나 차이' 서술은 폐기.\n",
              cp_critical_rho(19L), cp_critical_rho(n_decl)))
write_json(list(verdict=verdict, registry=hit[1], n_items=nrow(D),
                n_category=n_cat, n_econ_family=n_ef, n_declared=n_decl,
                heuristic_count=19L, crit_declared=cp_critical_rho(n_decl),
                crit_heuristic=cp_critical_rho(19L),
                categories=D[!is.na(category), .N, by=category],
                econ_families=D[!is.na(econ_fam), .N, by=econ_fam]),
           file.path(OUT,"p22b2_result.json"), pretty=TRUE, auto_unbox=TRUE, digits=NA)
