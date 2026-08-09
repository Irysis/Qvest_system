## r2 — STR_1675 계열 ①계보 규명 ②PIT 무결성 확인
## FQ-213 최우선 probe. 계보가 같으면 독립 후보 2 → 1. PIT 가 깨졌으면 전부 무효.
suppressPackageStartupMessages({ library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/pg2_hunt")
say  <- function(fmt, ...) { cat(sprintf(paste0("[r2] ", fmt, "\n"), ...)); flush.console() }
INV <- readRDS(file.path(OUT,"s1_inventory.rds"))
IDX <- INV$idx

say("=== ① 계열 원천 파일 ===")
for (nm in c("STR_1675_QRebal_Hybrid","STR_1675_B_monthly","WT_D20260424_009_pilot11")) {
  j <- which(INV$names == nm)[1]; if (is.na(j)) { say("  %s 미발견", nm); next }
  p <- gsub("\\\\","/", IDX$file[j])
  say("  %-26s → %s", substr(nm,1,26), sub(paste0("^", gsub("\\\\","/",ROOT), "/?"), "", p))
  say("  %-26s   %d행 · PG2 겹침 %d", "", IDX$n[j], IDX$ov[j])
}

say("=== ② 전략 디렉토리 내용 (계보 단서) ===")
for (nm in c("STR_1675_QRebal_Hybrid","STR_1675_B_monthly")) {
  j <- which(INV$names == nm)[1]; if (is.na(j)) next
  d <- dirname(dirname(IDX$file[j]))
  say("  --- %s ---", substr(nm,1,30))
  say("      경로: %s", sub(paste0("^", gsub("\\\\","/",ROOT), "/?"), "", gsub("\\\\","/", d)))
  ff <- list.files(d, recursive = FALSE)
  say("      항목 %d: %s", length(ff), paste(head(ff, 12), collapse=", "))
  ## manifest/spec 가 있으면 전략 정의 확인
  ms <- list.files(d, pattern="(manifest|strategy_spec|README)", recursive=TRUE, full.names=TRUE)
  for (m in head(ms, 3)) {
    say("      [%s]", basename(m))
    if (grepl("\\.json$", m)) {
      x <- tryCatch(jsonlite::fromJSON(m, simplifyVector = TRUE), error=function(e) NULL)
      if (!is.null(x)) {
        kk <- intersect(c("strategy_id","name","description","factors","signal","universe",
                          "rebalance","parent","lineage","note"), names(x))
        for (k in kk) say("        %-14s %s", k, substr(paste(unlist(x[[k]]), collapse=" | "), 1, 110))
      }
    } else if (grepl("\\.csv$", m)) {
      say("        %s", paste(head(readLines(m, warn=FALSE), 2), collapse=" / "))
    } else {
      say("        %s", paste(head(readLines(m, warn=FALSE, n=3), 3), collapse=" / "))
    }
  }
}

say("=== ③ ★PIT 단서: 산출물 계보 체인 ===")
for (nm in c("STR_1675_QRebal_Hybrid","STR_1675_B_monthly")) {
  j <- which(INV$names == nm)[1]; if (is.na(j)) next
  d <- dirname(dirname(IDX$file[j]))
  au <- list.files(d, pattern="(audit|lineage|forge_package|judge)", recursive=TRUE, full.names=TRUE)
  say("  %-26s 감사/계보 산출물 %d건: %s", substr(nm,1,26), length(au),
      paste(head(basename(au), 5), collapse=", "))
  ## audit 이 있으면 PIT 판정 확인
  a1 <- au[grepl("audit", basename(au))][1]
  if (!is.na(a1)) {
    if (grepl("\\.csv$", a1)) {
      A <- tryCatch(fread(a1), error=function(e) NULL)
      if (!is.null(A) && nrow(A)) {
        cn <- names(A)[grepl("check|status|result|pass", names(A), ignore.case=TRUE)]
        say("      audit 컬럼: %s · 행 %d", paste(head(names(A),8), collapse=","), nrow(A))
        if (length(cn)) { say("      상태 분포:"); print(table(A[[cn[1]]])) }
      }
    }
  }
}
say("=== ④ 판정 재료 ===")
say("  ★계보 동일 여부는 위 ②의 경로·manifest 로 판단한다.")
say("  ★PIT 는 audit 산출물이 있으면 1차, 없으면 **생산 코드 재산출 parity** 가 유일한 확인이다.")
say("     (오늘 확립: 저장 패널 재사용은 동월 look-ahead 전례가 있어 base 로 못 쓴다)")
say("=== r2 완료 ===")
