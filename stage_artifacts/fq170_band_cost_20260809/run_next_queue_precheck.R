## 다음 알파 라운드 선정 — 착수 전 확인 (FQ-170 종결 후)
## 사전등록(측정 전 고정, 이 주석이 정본):
##  헌법: 발굴 착수 전 큐 확인 + owner 표기 의무 · `dohoon_decision` 항목 세션 임의 착수 금지.
##  ★08-08 교훈 적용:
##   ①**status 는 enum 이 아니다** — 부분 일치 술어가 양방향으로 틀린다(과다제외 25%·과소포함 29%).
##     ⇒ **고유값을 전부 나열**하고 분류를 눈으로 확인한 뒤 거른다.
##   ②`ev_rationale`(rank-IC 동기)와 `wall_check`(PORT_t 실측)를 **함께** 읽는다 — 하나만 보면 오독.
##   ③in-flight 확인은 **제목이 아니라 `next_action` 본문**까지 검색(FQ-166 은 제목으로 안 걸렸다).
##   ④큐의 `owner=미배정` 을 믿지 말고 **오늘자 WT `request.json`** 을 실측.
##  ★read-only. 이 라운드는 **선정**이지 측정이 아니다.
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
Q <- "06_Registry/alpha_frontier_queue.json"
stopifnot(file.exists(Q))
J <- fromJSON(Q, simplifyVector = FALSE)
## ★입력 실측 후 확정(가정 금지 — 초판은 J 자체를 순회해 '항목 5'(최상위 키 수)를 셌다):
##   최상위 = schema_version|sot|updated|consume_rule|**entries** · 원소 필드 = id|lane|title|
##   hypothesis|ev_rationale|wall_check|data_gate|owner|status|next_action|source_refs
items <- J[["entries"]]
stopifnot(!is.null(items), length(items) > 0L)
cat(sprintf("[큐] %s · schema %s · updated %s · **entries %d**\n",
            Q, J[["schema_version"]], J[["updated"]], length(items)))

## ★R 의 `[[` 는 **없는 이름에 오류**를 낸다(NULL 아님) — 안전 접근자 필수
g <- function(x, k) { if (!is.list(x) || !(k %in% names(x))) return(NA_character_)
  v <- x[[k]]; if (is.null(v) || !length(v)) NA_character_ else paste(as.character(v), collapse=" ") }
D <- rbindlist(lapply(items, function(x) data.table(
  id      = g(x, "id"),
  lane    = g(x, "lane"),
  gate    = substr(g(x, "data_gate"), 1, 34),
  title   = substr(g(x, "title"), 1, 54),
  status  = g(x, "status"),
  owner   = g(x, "owner"),
  next_a  = g(x, "next_action"),
  ev      = substr(g(x, "ev_rationale"), 1, 70),
  wall    = substr(g(x, "wall_check"), 1, 70),
  blocked = g(x, "blocked_by"))), fill = TRUE)

cat("\n=== status 고유값 (부분 일치 금지 — 눈으로 분류) ===\n")
print(D[, .N, by = status][order(-N)])
cat("\n=== owner 고유값 ===\n")
print(D[, .N, by = owner][order(-N)])

## 분류는 고유값을 보고 **명시 집합**으로 (접미 포함 여부를 substring 으로 추측하지 않는다)
st <- unique(D$status)
open_set <- st[!grepl("^(closed|done|settled|superseded|merged|withdrawn)", st, ignore.case = TRUE)]
cat(sprintf("\nopen 으로 분류한 status: %s\n", paste(open_set, collapse = " | ")))
OPEN <- D[status %in% open_set]
cat(sprintf("open 항목 %d / %d\n", nrow(OPEN), nrow(D)))

## 도훈 결정 대기 · 차단 · 배정됨 제외
is_dohoon <- grepl("dohoon", OPEN$status, ignore.case=TRUE) | grepl("dohoon", OPEN$owner, ignore.case=TRUE)
is_blocked <- !is.na(OPEN$blocked) & nzchar(OPEN$blocked) & OPEN$blocked != "NA"
is_owned <- !is.na(OPEN$owner) & nzchar(OPEN$owner) & !grepl("^(미배정|unassigned|none|NA)$", OPEN$owner, ignore.case=TRUE)
cat(sprintf("  제외: dohoon_decision %d · blocked %d · owner 배정됨 %d\n",
            sum(is_dohoon), sum(is_blocked), sum(is_owned)))
CAND <- OPEN[!is_dohoon & !is_blocked & !is_owned]
cat(sprintf("★즉시 착수 가능 후보: %d\n", nrow(CAND)))

## in-flight 실측 — 제목이 아니라 오늘자 WT request.json 본문
wts <- list.files("qepm/mailbox/worktask", pattern="^request\\.json$", recursive=TRUE, full.names=TRUE)
recent <- wts[file.mtime(wts) > (max(file.mtime(wts), na.rm=TRUE) - 3*86400)]
inflight <- unlist(lapply(recent, function(p) {
  s <- tryCatch(paste(readLines(p, warn=FALSE), collapse=" "), error=function(e) "")
  unlist(regmatches(s, gregexpr("FQ-[0-9]{3}", s)))
}))
cat(sprintf("\n[in-flight] 최근 3일 WT request %d개 · 언급된 FQ: %s\n", length(recent),
            if (length(inflight)) paste(sort(unique(inflight)), collapse=", ") else "(없음)"))
CAND[, inflight_hit := id %in% inflight]
cat(sprintf("  후보 중 in-flight 중복: %d\n", sum(CAND$inflight_hit)))

FINAL <- CAND[inflight_hit == FALSE]
cat(sprintf("\n★★최종 후보 %d건 (상위 8 — ev/wall 함께 표기)\n", nrow(FINAL)))
if (nrow(FINAL)) for (i in seq_len(min(8L, nrow(FINAL)))) {
  r <- FINAL[i]
  cat(sprintf("\n[%s] %s\n  status=%s\n  next: %s\n  ev  : %s\n  wall: %s\n",
              r$id, r$title, r$status, substr(r$next_a, 1, 110), r$ev, r$wall))
}
write_json(list(n_total=nrow(D), n_open=nrow(OPEN), n_candidate=nrow(CAND),
                n_final=nrow(FINAL), status_values=st, inflight_fq=unique(inflight),
                candidates=FINAL),
           file.path("C:/Users/99922/OneDrive/Quant_Module_Moltbot/.claude/worktrees/jovial-mcnulty-f7d018",
                     "stage_artifacts/fq170_band_cost_20260809/next_queue_precheck.json"),
           pretty=TRUE, auto_unbox=TRUE, digits=NA)
