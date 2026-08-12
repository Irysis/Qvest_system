## FQ-127 C1 — 범위 정의: 과거 '개선' 주장 중 **base 를 명시하지 않은 것**이 몇 건인가
## 사전등록(측정 전 고정, 이 주석이 정본):
##  FQ-127 = "지금까지의 개선 중 몇 건이 약한 base 아티팩트인가". next_action 결측이라 범위를 내가 정의한다.
##  ★전면 재측정 전에 **규모를 센다**(착수 전 사전 확인 규약). 재측정은 비싸고 census 는 싸다.
##  근거: 오늘 FQ-170 이 **Δ 부호가 base 에 조건부**임을 순열 통제 4/4 로 확립했다.
##        ⇒ base 를 명시하지 않은 개선 주장은 **해석 불가**이며, 그 비율이 FQ-127 의 작업량이다.
##  코퍼스: `.cache/round_closures.jsonl`(라이브) — 과거 라운드 판정문 전량.
##  ★★이건 **자유 텍스트 substring 탐지**다. 오늘 그걸로 여러 번 틀렸으므로:
##   ①탐지 결과를 **양방향 표본 출력**해 눈으로 검증 가능하게 하고
##   ②판정이 아니라 **범위 추정**으로만 쓴다(개별 확인은 다음 라운드)
##   ③결측/무탐지를 '해당 없음' 과 합치지 않는다(오늘 Q2 에서 그걸로 틀렸다).
##  판정:
##   S1_LARGE  : base 미명시 개선 주장 >= 30% → FQ-127 은 큰 라운드, 우선순위 분할 필요
##   S2_MEDIUM : 10~30%
##   S3_SMALL  : < 10% → 개별 처리로 충분
##  ★read-only.
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
DATA_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
CODE_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.claude/worktrees/jovial-mcnulty-f7d018"
setwd(DATA_ROOT)
OUT <- file.path(CODE_ROOT, "stage_artifacts/fq127_base_dependency_20260810")
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)

SRC <- ".cache/round_closures.jsonl"
stopifnot(file.exists(SRC))
ln <- readLines(SRC, warn = FALSE)
cat(sprintf("[코퍼스] %s · %d 레코드\n", SRC, length(ln)))
P <- lapply(ln, function(l) tryCatch(fromJSON(l, simplifyVector = TRUE), error = function(e) NULL))
ok <- !vapply(P, is.null, logical(1))
cat(sprintf("  파싱 %d / %d\n", sum(ok), length(ln)))
fl <- function(e, k) { v <- e[[k]]; if (is.null(v)) "" else paste(as.character(unlist(v)), collapse = " ") }
D <- rbindlist(lapply(P[ok], function(e) data.table(
  round_id = fl(e, "round_id"), layer = fl(e, "layer"), verdict = fl(e, "verdict_type"),
  body = paste(fl(e,"mechanism_diagnosis"), fl(e,"frontier_update"), fl(e,"consumer_surfaces")))), fill = TRUE)
D <- D[nzchar(body)]
cat(sprintf("  본문 보유 %d\n", nrow(D)))

## 개선 주장 탐지 (넓게)
IMPROVE <- "\\+0\\.[0-9]|ΔIR|Δ *\\+|개선|향상|우위|상승|올랐|증가분|기여.*\\+"
## base 명시 탐지 (넓게)
BASENAME <- "base|기준선|baseline|incumbent|PG2|core4|FAM_|vs |대비|무밴드|no.?band|standalone"
D[, has_improve := grepl(IMPROVE, body, perl = TRUE)]
D[, has_base    := grepl(BASENAME, body, perl = TRUE, ignore.case = TRUE)]
n_imp <- sum(D$has_improve)
n_bad <- sum(D$has_improve & !D$has_base)
cat(sprintf("\n★개선 주장 포함 라운드: **%d / %d (%.1f%%)**\n", n_imp, nrow(D), 100*n_imp/nrow(D)))
cat(sprintf("  그중 base 미명시: **%d (%.1f%% of 개선주장)**\n", n_bad, 100*n_bad/max(n_imp,1)))

cat("\n=== [검증·양성] 개선 ∧ base 명시 — 표본 3 ===\n")
for (i in head(which(D$has_improve & D$has_base), 3))
  cat(sprintf("  [%s] %s\n", substr(D$round_id[i],1,44), substr(gsub("\\s+"," ",D$body[i]), 1, 130)))
cat("\n=== [검증·문제] 개선 ∧ base **미명시** — 표본 5 ===\n")
for (i in head(which(D$has_improve & !D$has_base), 5))
  cat(sprintf("  [%s] %s\n", substr(D$round_id[i],1,44), substr(gsub("\\s+"," ",D$body[i]), 1, 130)))
cat("\n=== [검증·음성] 개선 주장 없음 — 표본 3 (오탐 확인) ===\n")
for (i in head(which(!D$has_improve), 3))
  cat(sprintf("  [%s] %s\n", substr(D$round_id[i],1,44), substr(gsub("\\s+"," ",D$body[i]), 1, 110)))

cat("\n=== layer 별 base-미명시 개선 주장 ===\n")
L <- D[has_improve == TRUE, .(n_imp = .N, n_no_base = sum(!has_base)), by = layer][order(-n_no_base)]
print(head(L, 10))
frac <- n_bad / max(n_imp, 1)
verdict <- if (frac >= 0.30) "S1_LARGE" else if (frac >= 0.10) "S2_MEDIUM" else "S3_SMALL"
cat(sprintf("\n판정: %s (base 미명시 비율 %.1f%%)\n", verdict, 100*frac))
cat("⚠자유 텍스트 substring 탐지다 — **범위 추정**이지 개별 판정이 아니다. 표본으로 눈 검증할 것\n")
fwrite(D[, .(round_id, layer, verdict, has_improve, has_base)], file.path(OUT, "c1_claims.csv"))
write_json(list(verdict = verdict, n_rounds = nrow(D), n_improve = n_imp,
                n_no_base = n_bad, frac_no_base = frac, by_layer = L),
           file.path(OUT, "c1_result.json"), pretty = TRUE, auto_unbox = TRUE, digits = NA)
