## FQ-127 G1 — ΔIR 상신이 **어느 incumbent base 대비**였는지 기록돼 있는가
## 사전등록(측정 전 고정, 이 주석이 정본):
##  F2 가 3층으로 갈랐다: 자본 게이트(HARD 3종)=절대 기준이라 **면역** · 서사 층=게이트 미통과 ·
##  **ΔIR 상신(§4 book-marginal)= 정의상 비교량이라 유일한 잔여 노출**.
##  선례: 08-03 실측 = 같은 필터가 재구성 base **+0.169** vs production **-0.149** (부호 반전) ·
##        08-08 실측 = PG2 정체성이 두 필드로 갈려 **퇴역 PG2 를 7주간 기준선으로** 사용.
##  ⇒ `book_state.json` 이 ΔIR 판정의 base 를 **식별 가능하게** 기록하는지 본다.
##  ★구조 질문이다(필드가 있는가) — 산문 판독 아님. F2 에서 확립한 순서: 인덱스/구조 먼저.
##  판정:
##   V1_IDENTIFIED : incumbent 를 **버전/시점까지** 식별하는 필드 존재(예: pg2_version + ir + asof)
##   V2_VALUE_ONLY : IR 값만 있고 **어느 book 인지** 식별 불가 → 08-08 형 사고 재발 가능
##   V3_ABSENT     : ΔIR base 기록 자체가 없음
##  ★read-only.
suppressPackageStartupMessages({ library(jsonlite) })
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
OUT <- ".claude/worktrees/jovial-mcnulty-f7d018/stage_artifacts/fq127_base_dependency_20260810"

cands <- c("06_Registry/book_state.json", "qepm/registry/book_state.json",
           "02_Infrastructure/portfolio/book_state.json", "qepm/book_state.json")
hit <- cands[file.exists(cands)]
if (!length(hit)) {
  f <- list.files(".", pattern = "book_state", recursive = TRUE, full.names = TRUE)
  f <- f[!grepl("worktrees|\\.git", f)]
  hit <- head(f, 3)
}
cat("book_state 후보:", if (length(hit)) paste(hit, collapse = ", ") else "(없음)", "\n")
if (!length(hit)) {
  cat("=> book_state 부재 — ΔIR base 기록 확인 불가. 이것 자체가 발견.\n")
  write_json(list(verdict = "V3_ABSENT", reason = "book_state 파일 미발견"),
             file.path(OUT, "g1_result.json"), pretty = TRUE, auto_unbox = TRUE, digits = NA)
  quit(save = "no")
}
P <- hit[1]
J <- fromJSON(P, simplifyVector = FALSE)
cat(sprintf("\n[%s] 최상위 키 %d\n", P, length(J)))
for (k in names(J))
  cat(sprintf("  %-30s class=%-9s len=%d\n", k, class(J[[k]])[1], length(J[[k]])))

## IR / base / incumbent 관련 필드 (이름 기반 1차 추림 — 그 다음 값을 눈으로)
pat <- "ir|incumbent|baseline|base|version|asof|as_of|convention|pg2"
rel <- names(J)[grepl(pat, names(J), ignore.case = TRUE)]
cat("\n★IR/base 관련 최상위 필드:", if (length(rel)) paste(rel, collapse = " | ") else "(없음)", "\n")
for (k in rel) {
  v <- paste(as.character(unlist(J[[k]])), collapse = " · ")
  cat(sprintf("  %-30s = %s\n", k, substr(v, 1, 88)))
}

## 판정에 필요한 3요소: IR 값 · 그 book 의 정체(버전/구성) · 시점
has_ir      <- any(grepl("(^|_)ir$|_ir$|incumbent_book_ir", names(J), ignore.case = TRUE))
has_ident   <- any(grepl("version|pg2|composition|members|holdings|config", names(J), ignore.case = TRUE))
has_asof    <- any(grepl("asof|as_of|updated|date|timestamp", names(J), ignore.case = TRUE))
cat(sprintf("\n3요소: IR값 %s · book 정체 %s · 시점 %s\n", has_ir, has_ident, has_asof))
verdict <- if (has_ir && has_ident && has_asof) "V1_IDENTIFIED" else
           if (has_ir) "V2_VALUE_ONLY" else "V3_ABSENT"
cat(sprintf("판정: %s\n", verdict))
if (verdict == "V2_VALUE_ONLY")
  cat("=> IR 값은 있으나 **어느 book 인지** 식별 불가 — 08-08 형(퇴역 PG2 를 기준선으로) 재발 가능\n")
cat("\n[한정] 최상위 필드만 봤다. 중첩 구조에 식별자가 있을 수 있으므로 위 목록을 눈으로 확인할 것\n")
write_json(list(verdict = verdict, path = P, top_keys = names(J),
                related_fields = rel, has_ir = has_ir, has_identity = has_ident, has_asof = has_asof),
           file.path(OUT, "g1_result.json"), pretty = TRUE, auto_unbox = TRUE, digits = NA)
