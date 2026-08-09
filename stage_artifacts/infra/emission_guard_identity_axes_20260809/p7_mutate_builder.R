## P7 — 빌더 Coverage 계약 돌연변이 (축 C 검출력 실증)
##   2026-06-10 이전의 구 정의(`Coverage = !is.na(Raw_Value)` 단독)로 되돌린다.
##   그 상태에서 축 D 는 실데이터에서 침묵하는데 Coverage=FALSE 직접 주입 테스트는
##   계속 통과한다 — 축 C 가 없으면 검사가 살아 있는 채로 눈이 먼다.
##   ★Rscript -e 경유 금지(프로젝트 규약) + `!` 는 셸 확장에 걸린다 → .R 파일로 수행.
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
ROOT <- gsub("\\\\", "/", ROOT)
P <- file.path(ROOT, "02_Infrastructure/factor_db/factor_db_builder.R")
t <- readLines(P, warn = FALSE)
FROM <- "dt[, Coverage := !is.na(Raw_Value) & !is.na(Z_Score)]"
TO   <- "dt[, Coverage := !is.na(Raw_Value)]"
i <- grep(FROM, t, fixed = TRUE)
if (length(i) != 1L) stop(sprintf("돌연변이 지점 %d건 (1건이어야 함)", length(i)))
t[i] <- sub(FROM, TO, t[i], fixed = TRUE)
writeLines(t, P)
cat(sprintf("[p7] %d행 돌연변이 적용: Coverage 를 구 정의(!is.na(Raw_Value) 단독)로 되돌림\n", i))
