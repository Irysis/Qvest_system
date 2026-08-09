#==============================================================================
# d6_format_probe.R — registry 재직렬화가 **형식을 바꾸는가** 를 쓰기 전에 잰다.
# 근거: 메모리 reference-shared-registry-reserialize-precision-loss —
#   pretty=TRUE(4칸) 로 쓰면 정본(2칸)과 전면 재직렬화되어 diff 를 못 읽는다.
#   추가 축: 이 파일은 CRLF 다. LF 로 쓰면 전 줄이 바뀐다.
# 쓰지 않는다 — tmp 로만 만들어 비교하고 지운다.
#==============================================================================
suppressPackageStartupMessages({ library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
REG  <- file.path(ROOT, "02_Infrastructure/factor_db/factor_registry.json")

raw <- readBin(REG, "raw", file.size(REG))
n_crlf <- sum(raw[-length(raw)] == as.raw(0x0d) & raw[-1] == as.raw(0x0a))
n_lf   <- sum(raw == as.raw(0x0a))
cat(sprintf("[d6] 원본: bytes=%s  LF=%d  CRLF=%d  → %s\n",
            format(length(raw), big.mark = ","), n_lf, n_crlf,
            if (n_crlf == n_lf) "전부 CRLF" else "혼재(!)"))

orig_lines <- readLines(REG, warn = FALSE)
cat(sprintf("[d6] 원본 줄수=%d\n", length(orig_lines)))
# 들여쓰기 단위 실측: 두 번째 줄의 선행 공백
lead <- function(s) nchar(sub("^( *).*$", "\\1", s))
cat(sprintf("[d6] 원본 들여쓰기: L2=%d L3=%d L11=%d\n",
            lead(orig_lines[2]), lead(orig_lines[3]), lead(orig_lines[11])))

reg <- fromJSON(REG, simplifyVector = FALSE)
tmpdir <- file.path(ROOT, "stage_artifacts/infra/factor_dedup_wiring_20260809")

for (pv in list(TRUE, 2L, 4L)) {
  tf <- file.path(tmpdir, sprintf("_fmt_probe_%s.json", if (isTRUE(pv)) "TRUE" else pv))
  write_json(reg, tf, auto_unbox = TRUE, pretty = pv, null = "null", digits = NA)
  L <- readLines(tf, warn = FALSE)
  rb <- readBin(tf, "raw", file.size(tf))
  c2 <- sum(rb[-length(rb)] == as.raw(0x0d) & rb[-1] == as.raw(0x0a))
  cat(sprintf("[d6] pretty=%-4s → 줄수=%-6d L2들여=%d  CRLF=%d  줄수일치=%s  L2일치=%s\n",
              if (isTRUE(pv)) "TRUE" else pv, length(L), lead(L[2]), c2,
              length(L) == length(orig_lines), identical(L[2], orig_lines[2])))
  # 내용 동일 줄 비율 (형식만 비교)
  if (length(L) == length(orig_lines)) {
    cat(sprintf("        동일 줄 비율 = %.4f\n", mean(L == orig_lines)))
  }
  unlink(tf)
}
cat("[d6] done — 위에서 '줄수일치 TRUE + 동일 줄 비율 1.0000' 인 설정만 안전\n")
