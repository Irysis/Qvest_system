## FQ-127 G1b — 정본 book_state 에서 ΔIR base 식별 가능성 확인
## ★G1 초판이 파일명을 추측해 **스키마 파일**을 잡았다. 정본 경로는 계약이 안다:
##   `portfolio_governor.R:80` .PG_BOOK_STATE_PATH = qepm/mailbox/governor/book_state.json
##   ⇒ **계약의 경로 상수를 읽고 그걸 쓴다**(오늘 반복 규약: 파일명 추측 금지).
## 사전등록(측정 전 고정):
##  질문 = ΔIR 판정의 **기준선(incumbent)** 이 나중에 재현 가능하게 기록됐는가.
##  3요소: ①incumbent IR 값 ②그 book 의 **정체**(구성원/버전 — 값만으론 어느 book 인지 모른다)
##         ③**시점**(언제의 book 인가). 08-08 사고 = 정체가 두 필드로 갈려 퇴역 PG2 를 7주간 기준선으로.
##  판정: V1_IDENTIFIED(3요소 다) / V2_VALUE_ONLY(IR 값만) / V3_ABSENT
##  ★read-only. 05_Production 은 읽기만.
suppressPackageStartupMessages({ library(jsonlite) })
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
OUT <- ".claude/worktrees/jovial-mcnulty-f7d018/stage_artifacts/fq127_base_dependency_20260810"
P <- "qepm/mailbox/governor/book_state.json"
cat(sprintf("[정본 경로] %s · 존재 %s\n", P, file.exists(P)))
if (!file.exists(P)) {
  d <- dirname(P)
  cat(sprintf("  디렉터리 존재 %s · 내용: %s\n", dir.exists(d),
              paste(head(list.files(d), 8), collapse = ", ")))
  cat("=> 정본 book_state 부재 — ΔIR 상신 이력의 base 기록이 **파일로 존재하지 않는다**\n")
  write_json(list(verdict = "V3_ABSENT", path = P, dir_exists = dir.exists(d),
                  dir_files = list.files(dirname(P))),
             file.path(OUT, "g1b_result.json"), pretty = TRUE, auto_unbox = TRUE, digits = NA)
  quit(save = "no")
}
J <- fromJSON(P, simplifyVector = FALSE)
cat(sprintf("\n최상위 키 %d:\n", length(J)))
for (k in names(J)) {
  v <- tryCatch(paste(as.character(unlist(J[[k]])), collapse = " · "), error = function(e) "")
  cat(sprintf("  %-30s %-9s len=%-4d %s\n", k, class(J[[k]])[1], length(J[[k]]), substr(v, 1, 52)))
}
nm <- names(J)
has_ir    <- any(grepl("incumbent_book_ir|book_ir|(^|_)ir$", nm, ignore.case = TRUE))
has_ident <- any(grepl("admitted_ids|members|holdings|composition|version|pg2|book_weights", nm, ignore.case = TRUE))
has_asof  <- any(grepl("asof|as_of|updated|date|timestamp|generated", nm, ignore.case = TRUE))
has_conv  <- any(grepl("ir_convention|convention|basis", nm, ignore.case = TRUE))
cat(sprintf("\n3요소: IR값 %s · book 정체 %s · 시점 %s   (+ ir_convention %s)\n",
            has_ir, has_ident, has_asof, has_conv))
verdict <- if (has_ir && has_ident && has_asof) "V1_IDENTIFIED" else
           if (has_ir) "V2_VALUE_ONLY" else "V3_ABSENT"
cat(sprintf("판정: %s\n", verdict))
if (verdict == "V1_IDENTIFIED")
  cat("=> ΔIR 판정의 기준선이 **재현 가능하게** 기록된다 — F2 의 잔여 노출이 닫힌다\n")
if (verdict == "V2_VALUE_ONLY")
  cat("=> IR 값만 있고 **어느 book 인지** 식별 불가 — 08-08 형 재발 가능(자본 판정 직접 노출)\n")
write_json(list(verdict = verdict, path = P, top_keys = nm,
                has_ir = has_ir, has_identity = has_ident, has_asof = has_asof,
                has_convention = has_conv),
           file.path(OUT, "g1b_result.json"), pretty = TRUE, auto_unbox = TRUE, digits = NA)
