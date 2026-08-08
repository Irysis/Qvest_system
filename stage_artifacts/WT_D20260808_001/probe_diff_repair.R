suppressPackageStartupMessages(library(jsonlite))
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
MBX <- "qepm/mailbox/worktask/WT-D20260808_001"
a <- fromJSON(file.path(MBX, "alpha_package_prerepair_20260808.json"), simplifyVector = FALSE)
b <- fromJSON(file.path(MBX, "alpha_package.json"), simplifyVector = FALSE)
cat("prerepair keys:", paste(names(a), collapse = ", "), "\n\n")
cat("추가 최상위 키:", paste(setdiff(names(b), names(a)), collapse = ", "), "\n")
cat("삭제 최상위 키:", paste(setdiff(names(a), names(b)), collapse = ", "), "\n\n")
cat("--- pit 블록 ---\n"); str(b$pit, max.level = 2)
fa <- unlist(a$challenge_flags); fb <- unlist(b$challenge_flags)
cat("\n--- 추가된 challenge_flags (", length(setdiff(fb, fa)), "건) ---\n", sep = "")
for (s in setdiff(fb, fa)) cat(" + ", s, "\n", sep = "")
cat("\n--- 삭제된 flags (", length(setdiff(fa, fb)), "건) ---\n", sep = "")
for (s in setdiff(fa, fb)) cat(" - ", s, "\n", sep = "")
cat("\ndiagnostics 동일:", identical(a$diagnostics, b$diagnostics), "\n")
cat("hypothesis 동일:", identical(a$hypothesis, b$hypothesis), "\n")
cat("factors 동일:", identical(a$factors, b$factors), "\n")
cat("alpha_vector 동일:", identical(a$alpha_vector, b$alpha_vector), "\n")
cat("verdict 동일:", identical(a$verdict, b$verdict), "\n")

cat("\n=== diagnostics 항목별 대조 ===\n")
ka <- names(a$diagnostics); kb <- names(b$diagnostics)
cat("추가:", paste(setdiff(kb,ka), collapse=", "), "\n")
cat("삭제:", paste(setdiff(ka,kb), collapse=", "), "\n")
for (k in intersect(ka,kb)) {
  va <- a$diagnostics[[k]]; vb <- b$diagnostics[[k]]
  if (!identical(va, vb)) cat(sprintf("  변경 %-40s : %s -> %s\n", k,
     paste(format(unlist(va)), collapse=","), paste(format(unlist(vb)), collapse=",")))
}
cat("\n=== hypothesis 하위 대조 ===\n")
for (k in union(names(a$hypothesis), names(b$hypothesis))) {
  if (!identical(a$hypothesis[[k]], b$hypothesis[[k]]))
    cat(sprintf("  변경 %s (a nchar %s / b nchar %s)\n", k,
        nchar(paste(unlist(a$hypothesis[[k]]),collapse="")),
        nchar(paste(unlist(b$hypothesis[[k]]),collapse=""))))
}
cat("\nfalsification a:", substr(paste(unlist(a$hypothesis$falsification),collapse=" "),1,120), "...\n")
cat("falsification b:", substr(paste(unlist(b$hypothesis$falsification),collapse=" "),1,120), "...\n")
