## Q2 — 정확일치 후보 중 **설치·로그인 없이 즉시 되는 것** 선별
## 사전등록(측정 전 고정, 이 주석이 정본):
##  착수 전 확인 결과: status 는 자유 문자열(226항목/117종)이라 안전한 술어는 **정확일치 둘뿐**:
##    `frontier_open`(59) + `config_scoped_negative_frontier_open`(11) = 70건.
##  ★그중 다수가 **선행 조건**을 갖는다: 도훈 QW 로그인(FQ-003/005) · 패키지 설치(FQ-074 kiwipiepy+bs4) ·
##    타 항목 완료 대기 · GPU/capacity. 이건 status 가 아니라 **next_action/data_gate 본문**에 있다.
##  ⇒ 본문을 읽어 **선행조건 유형**을 분류하고, 조건 없는 것만 남긴다.
##  ★분류는 substring 이지만 이번엔 **판별 대상이 자유 서술문**이라 불가피하다 —
##    대신 ①키워드를 넓게 잡고 ②**분류 결과를 항목별로 출력**해 눈으로 검증 가능하게 한다
##    (오늘 접두 필터로 실패했으므로 '조용한 분류' 를 만들지 않는다).
##  ★read-only. 선정이지 측정이 아니다.
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
E <- fromJSON("06_Registry/alpha_frontier_queue.json", simplifyVector = FALSE)[["entries"]]
g <- function(x,k) if (!is.list(x) || !(k %in% names(x))) NA_character_ else {
  v <- x[[k]]; if (is.null(v) || !length(v)) NA_character_ else paste(as.character(v), collapse=" ") }
D <- rbindlist(lapply(E, function(x) data.table(
  id=g(x,"id"), lane=g(x,"lane"), status=g(x,"status"), owner=g(x,"owner"),
  gate=g(x,"data_gate"), title=g(x,"title"), nx=g(x,"next_action"),
  ev=g(x,"ev_rationale"), wall=g(x,"wall_check"))), fill=TRUE)

## ★정확일치만 (접두/포함 금지 — 오늘 그걸로 틀렸다)
OK_STATUS <- c("frontier_open", "config_scoped_negative_frontier_open")
C <- D[status %in% OK_STATUS]
cat(sprintf("[정확일치] %d / %d 항목\n", nrow(C), nrow(D)))
print(C[, .N, by=status])

## 선행조건 유형 — 넓게 잡고 **항목별로 보여준다**
blob <- tolower(paste(C$nx, C$gate, C$wall))
C[, need_login  := grepl("로그인|login|quantiwise|qw |export|도훈", blob)]
C[, need_install:= grepl("설치|install|venv|kiwipiepy|bs4|패키지|gpu|capacity", blob)]
C[, need_other  := grepl("완료 후|선행|대기|blocked|의존", blob)]
C[, ready_now   := !need_login & !need_install & !need_other]
cat(sprintf("\n선행조건: 로그인/export %d · 설치/capacity %d · 타항목 대기 %d\n",
            sum(C$need_login), sum(C$need_install), sum(C$need_other)))
cat(sprintf("★**즉시 가능 후보: %d / %d**\n", sum(C$ready_now), nrow(C)))

## owner 배정된 것 제외
C[, owned := !is.na(owner) & nzchar(owner) & !grepl("^(미배정|unassigned|none|na|-)$", tolower(owner))]
R <- C[ready_now == TRUE & owned == FALSE]
cat(sprintf("  owner 배정 제외 후: **%d**\n", nrow(R)))
cat("\n=== lane 분포 ===\n"); print(R[, .N, by=lane][order(-N)])

cat("\n=== 즉시 가능 후보 (상위 10 · ev/wall 함께) ===\n")
for (i in seq_len(min(10L, nrow(R)))) {
  r <- R[i]
  cat(sprintf("\n[%s] lane=%s\n  %s\n  next: %s\n  ev  : %s\n  wall: %s\n",
              r$id, r$lane, substr(r$title,1,70), substr(r$nx,1,120),
              substr(r$ev,1,100), substr(r$wall,1,100)))
}
## 제외된 것도 표본 출력 — 분류가 맞는지 눈으로 확인 (조용한 분류 금지)
cat("\n=== [검증용] 선행조건으로 제외된 것 표본 5 ===\n")
X <- C[ready_now == FALSE]
for (i in seq_len(min(5L, nrow(X)))) {
  r <- X[i]
  cat(sprintf("  [%s] login=%s install=%s other=%s | %s\n", r$id, r$need_login,
              r$need_install, r$need_other, substr(r$nx, 1, 80)))
}
fwrite(R[, .(id, lane, status, title, nx, ev, wall)],
       file.path("C:/Users/99922/OneDrive/Quant_Module_Moltbot/.claude/worktrees/jovial-mcnulty-f7d018",
                 "stage_artifacts/fq170_band_cost_20260809/q2_ready_now.csv"))
write_json(list(n_total=nrow(D), n_exact=nrow(C), n_ready=nrow(R),
                by_lane=R[, .N, by=lane], candidates=R[, .(id, lane, title, nx)]),
           file.path("C:/Users/99922/OneDrive/Quant_Module_Moltbot/.claude/worktrees/jovial-mcnulty-f7d018",
                     "stage_artifacts/fq170_band_cost_20260809/q2_result.json"),
           pretty=TRUE, auto_unbox=TRUE, digits=NA)
