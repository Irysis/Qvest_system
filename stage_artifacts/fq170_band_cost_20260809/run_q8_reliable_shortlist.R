## Q8 — 신뢰 가능한 착수 후보만 (Q2 의 미완 부분 마무리)
## 사전등록(측정 전 고정, 이 주석이 정본):
##  Q2 는 '즉시 가능 N건' 을 냈으나 상위 후보가 전부 `next_action` **결측**이라
##  '선행조건 언급 없음' 을 '선행조건 없음' 으로 읽은 것이었다(신뢰 불가). 그때 남긴 규약:
##  **근거를 댈 수 있는 건 `next_action` 이 있으면서 선행조건이 없는 쪽**.
##  ⇒ 그 부분집합을 실제로 산출한다. 이번엔 결측을 **별도 범주**로 분리해 절대 섞지 않는다.
##  필터(전부 명시):
##   ①status **정확일치** `frontier_open` 또는 `config_scoped_negative_frontier_open` (접두/포함 금지)
##   ②`next_action` **존재**(결측은 '판정 불가' 로 따로 센다)
##   ③선행조건 키워드 부재(로그인/export/설치/capacity/타항목 대기)
##   ④owner 미배정
##  ★분류 근거를 **항목별로 출력**해 눈으로 검증 가능하게 한다(오늘 3회 실패의 유일한 방어).
##  ★read-only. 선정이지 측정이 아니다.
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
OUT <- ".claude/worktrees/jovial-mcnulty-f7d018/stage_artifacts/fq170_band_cost_20260809"
E <- fromJSON("06_Registry/alpha_frontier_queue.json", simplifyVector = FALSE)[["entries"]]
g <- function(x, k) if (!is.list(x) || !(k %in% names(x))) NA_character_ else {
  v <- x[[k]]; if (is.null(v) || !length(v)) NA_character_ else paste(as.character(v), collapse = " ") }
D <- rbindlist(lapply(E, function(x) data.table(
  id = g(x,"id"), lane = g(x,"lane"), status = g(x,"status"), owner = g(x,"owner"),
  title = g(x,"title"), nx = g(x,"next_action"), gate = g(x,"data_gate"),
  ev = g(x,"ev_rationale"), wall = g(x,"wall_check"))), fill = TRUE)
cat(sprintf("[전체] %d\n", nrow(D)))

OK <- c("frontier_open", "config_scoped_negative_frontier_open")
C <- D[status %in% OK]
cat(sprintf("①정확일치 status: **%d**\n", nrow(C)))
C[, has_nx := !is.na(nx) & nzchar(nx)]
cat(sprintf("②next_action 보유: %d · **결측 %d (판정 불가로 분리)**\n", sum(C$has_nx), sum(!C$has_nx)))
W <- C[has_nx == TRUE]
blob <- tolower(paste(W$nx, W$gate))
W[, need_login   := grepl("로그인|login|quantiwise|qw |export|도훈 ", blob)]
W[, need_install := grepl("설치|install|venv|kiwipiepy|bs4|패키지|gpu|capacity|hf ", blob)]
W[, need_wait    := grepl("완료 후|선행|대기|blocked|의존|이후에", blob)]
W[, owned := !is.na(owner) & nzchar(owner) & !grepl("^(미배정|unassigned|none|na|-)$", tolower(owner))]
cat(sprintf("③선행조건: 로그인 %d · 설치 %d · 대기 %d\n", sum(W$need_login), sum(W$need_install), sum(W$need_wait)))
cat(sprintf("④owner 배정: %d\n", sum(W$owned)))
R <- W[!need_login & !need_install & !need_wait & !owned]
cat(sprintf("\n★★**신뢰 가능한 착수 후보: %d**\n", nrow(R)))
cat("\n=== 후보 (lane · next_action 근거 포함) ===\n")
for (i in seq_len(min(8L, nrow(R)))) {
  r <- R[i]
  cat(sprintf("\n[%s] lane=%s\n  %s\n  next: %s\n  ev  : %s\n",
              r$id, r$lane, substr(r$title,1,66), substr(r$nx,1,150), substr(r$ev,1,90)))
}
cat("\n=== [검증] 선행조건으로 제외된 것 표본 5 (분류 근거 확인) ===\n")
X <- W[need_login | need_install | need_wait | owned]
for (i in seq_len(min(5L, nrow(X)))) {
  r <- X[i]
  cat(sprintf("  [%s] login=%s install=%s wait=%s owned=%s | %s\n", r$id, r$need_login,
              r$need_install, r$need_wait, r$owned, substr(r$nx, 1, 72)))
}
cat(sprintf("\n[판정 불가] next_action 결측 %d건 — **'선행조건 없음' 과 섞지 않는다**\n", sum(!C$has_nx)))
cat(sprintf("  ID: %s\n", substr(paste(C[has_nx == FALSE, id], collapse = " · "), 1, 130)))
cat("\n=== lane 분포 (후보) ===\n"); print(R[, .N, by = lane][order(-N)])
fwrite(R[, .(id, lane, status, title, nx, ev, wall)], file.path(OUT, "q8_shortlist.csv"))
write_json(list(n_total = nrow(D), n_exact = nrow(C), n_with_nx = sum(C$has_nx),
                n_missing_nx = sum(!C$has_nx), n_candidates = nrow(R),
                undecidable_ids = C[has_nx == FALSE, id],
                candidates = R[, .(id, lane, title, nx)]),
           file.path(OUT, "q8_result.json"), pretty = TRUE, auto_unbox = TRUE, digits = NA)
