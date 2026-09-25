# test_qepm_advisor_contract.R — QEPM 어드바이저 모드(도훈 결정 QEPM-ADVISOR-MODE · 2026-09-25) 문서 계약의 양방향 검사
#
# 대상: .claude/commands/advisor.md · .claude/skills/qvest-advisor/SKILL.md(절차 정본) · 04_Research/advisor/README.md ·
#       .claude/agents/{alpha-hypothesis,alpha-research,risk-research,optimizer-research,forge}.md · .claude/commands/qvest.md
#   A. 존재 · 명령 → 스킬 배선(Skill(qvest-advisor) · frontmatter name) · 스킬 description 트리거 문장
#   B. 금지 절 — 스킬 '## 금지' 절 · 명령 '**금지**' 줄 · 에이전트 어드바이저 블록(맨 위 3~6줄)의 허용/금지/측정/산출 줄
#   C. 측정 경로 — 스킬의 R 예시를 parse 해 run_paper_replication 호출 인자 ⊆ 러너 형식인자(러너 파일 parse 재도출) ∧
#      필수(근거 논문·스펙·시행 회계) 전부 · require_source_paper=FALSE 없음 · selection_type ∈ 러너 match.arg 집합 ·
#      n_trials_basis 가 unknown* 아님 · 인용 필드(authoritative_remeasure.json·essence_grade) = 러너가 쓰는 이름 ·
#      문서가 쓰는 QVEST_* 스위치 = 러너가 실제로 읽는 env · 원장 auto-open 억제가 예시에 실림
#   D. 우회 봉쇄 — 금지 절 밖에 Judge/forge 스폰·dossier·WT·원장/BOOK writer 호출 문구 0 · 스폰 대상 ⊆ 자문 에이전트(파일 실재) ·
#      '도훈 승인 뒤에만' 게이트 · Judge 트리거 = judge.md 스폰 조건(산출물 judge_request.json 은 트리거 아님)
#   E. 동결 검사(test_qepm_freeze_entrypoints.R)와 정합 — 그 파일의 has·adv_ok·STALE_QEPM·STALE_GRID 를 parse 로 빌려 대조
#      (사본을 두지 않는다 — 동결 검사가 바뀌면 여기가 따라간다) · 자문 에이전트가 Read 하는 init 프롬프트 3종도 adv_ok ·
#      forge.md 동결 유지 + '어드바이저는 forge 를 쓰지 않는다' ·
#      qvest.md ④ 선택지 · /worktask 동결 행 보존 · 결정 레지스터 QEPM-ADVISOR-MODE·QEPM-R0-FREEZE 실재
#   F. 산출 위치 — 에이전트별 산출 파일 = 스킬 표 = README 표
#   G. 보강(2026-09-25 · /advisor 구현 워크플로 잔여) — ① 리프레시 배리어 선확인(판정기 refresh_barrier.sh 의 status·free·state= 를 재도출 →
#      스킬 ④ 맨 앞 · /advisor 절차 4 · alpha-search SKILL·명령·에이전트 실행 단계에서 호출보다 앞) ② /advisor frontmatter
#      disable-model-invocation: true ③ 승인 주체(채팅 발화 ∨ 도훈이 직접 친 --measure · 넘겨받은 --measure 무효 · 타 스킬 안내 =
#      메모까지만) ④ PIT 점검표 C11 = 외부·지연 공표 전반(FRED·ECOS·컨센서스·투자자 수급·DART — DART 가용일은 pit.md C4 행에서
#      재도출한 토큰으로 대조 · 가리키는 함수·규칙 id 실재) + 절차 ① frontier·data_pipeline 큐 조회 ⑤ 운영 쓰기 투명화(러너 §7-c
#      module_catalog 등재 · lookup 인라인 재빌드 — 코드 사실과 문서 서술 양방향) ⑥ Judge 전칭 문언 0 · description 3종 =
#      충실구현 관문 여부(러너 §11 재도출)에 맞는 현행 트리거 · reinforce SKILL(description·§8 Grade A 줄)·judge.md ② = 계층별
#      트리거(2계층 = rf_l2_auto.R 재도출 — l2_judge_request.json · 관문 없음 · 1계층 관문 규칙의 강화 전체 전칭 금지)
#   M. 돌연변이(위반 주입 사본 — 메모리 안) — 각 검사기가 red 를 내는지(검사기 양방향) · MG = G 절 돌연변이
#
# 쓰기: 없음(돌연변이는 문자열 사본). 운영 파일은 읽기만 한다(결정 레지스터 포함).
# 실행: Rscript 08_Tests/worktask/test_qepm_advisor_contract.R

.self <- tryCatch({
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", a[grepl("^--file=", a)])
  if (length(f)) dirname(f[1]) else "."
}, error = function(e) ".")
ROOT <- normalizePath(file.path(.self, "..", ".."), winslash = "/", mustWork = FALSE)
if (!file.exists(file.path(ROOT, "02_Infrastructure", "config.R")))
  ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
ROOT <- Sys.getenv("QVEST_QA_ROOT", ROOT)   # 수리 전 트리 대조용(선택)
suppressPackageStartupMessages(library(jsonlite))
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a

P <- 0L; F <- 0L
ok  <- function(m) { P <<- P + 1L; cat(sprintf("  ok   %s\n", m)) }
ng  <- function(m, d = "") { d <- paste(as.character(d), collapse = " "); F <<- F + 1L
  cat(sprintf("  NG   %s%s\n", m, if (length(d) && nzchar(d)) paste0(" — ", d) else "")) }
chk <- function(m, cond, d = "") if (isTRUE(cond)) ok(m) else ng(m, d)
fx  <- function(rel) file.path(ROOT, rel)
rd  <- function(rel) if (file.exists(fx(rel))) paste(readLines(fx(rel), warn = FALSE, encoding = "UTF-8"), collapse = "\n") else ""
lines_of <- function(txt) strsplit(txt, "\n", fixed = TRUE)[[1]]
has <- function(txt, s) grepl(s, txt, fixed = TRUE)
miss_of <- function(txt, toks) toks[!vapply(toks, function(k) has(txt, k), logical(1))]
has_all <- function(txt, toks) length(miss_of(txt, toks)) == 0L

CMD <- ".claude/commands/advisor.md"; SKL <- ".claude/skills/qvest-advisor/SKILL.md"; RDM <- "04_Research/advisor/README.md"
QV  <- ".claude/commands/qvest.md"; FRZ_T <- "08_Tests/worktask/test_qepm_freeze_entrypoints.R"
RPR_F <- "02_Infrastructure/alpha_search/run_paper_replication.R"
ADV_AGENTS <- c("alpha-hypothesis", "alpha-research", "risk-research", "optimizer-research")
INITS <- sprintf("02_Infrastructure/prompts/%s_research_init.md", c("alpha", "risk", "optimizer"))   # 자문 에이전트가 Read 하는 init
AG <- function(n) sprintf(".claude/agents/%s.md", n)

# ═════════════════════════════ 검사기 (문자열 → 판정 — 돌연변이에도 같은 함수를 쓴다) ═════════════════════════════
# 절 추출: 머리(정규식) 줄부터 다음 '## ' 머리 직전까지. rest = 그 절을 뺀 나머지.
sec_split <- function(txt, head_re) {
  L <- lines_of(txt); s <- grep(head_re, L, perl = TRUE)[1]
  if (is.na(s)) return(list(sec = "", rest = txt))
  e <- which(seq_along(L) > s & grepl("^## ", L, perl = TRUE))[1]
  e <- if (is.na(e)) length(L) else e - 1L
  list(sec = paste(L[s:e], collapse = "\n"), rest = paste(L[-(s:e)], collapse = "\n"))
}
line_split <- function(txt, head_re) {
  L <- lines_of(txt); i <- grep(head_re, L, perl = TRUE)
  list(sec = paste(L[i], collapse = "\n"), rest = paste(L[setdiff(seq_along(L), i)], collapse = "\n"))
}
# 에이전트 어드바이저 블록 = '★**어드바이저 모드**' 줄부터 이어지는 '>' 줄들(첫 '## ' 머리보다 위)
adv_block <- function(txt) {
  L <- lines_of(txt); s <- grep("★**어드바이저 모드**", L, fixed = TRUE)[1]
  if (is.na(s)) return(character(0))
  h1 <- grep("^## ", L, perl = TRUE)[1]
  if (!is.na(h1) && h1 < s) return(character(0))            # 맨 위 요약이어야 한다
  e <- s; while (e < length(L) && grepl("^>", L[e + 1L], perl = TRUE)) e <- e + 1L
  L[s:e]
}

FORBID_SKILL <- c("자체 등급", "Judge 스폰", "원장 쓰기", "BOOK", "forge", "qvest-dossier-pipeline", "/worktask promote",
                  "QEPM-R0-FREEZE", "require_source_paper = FALSE", "승인 전 성과")
FORBID_CMD   <- c("자체 등급", "Judge 스폰", "원장 쓰기", "BOOK", "forge", "/worktask promote")
FORBID_AGENT <- c("자체 등급", "forge", "Judge 스폰", "BOOK", "원장 쓰기")
chk_skill_forbid <- function(txt) { s <- sec_split(txt, "^## 금지")$sec; nzchar(s) && has_all(s, FORBID_SKILL) }
chk_cmd_forbid   <- function(txt) { s <- line_split(txt, "^\\*\\*금지\\*\\*")$sec; nzchar(s) && has_all(s, FORBID_CMD) }
chk_agent_block  <- function(txt, out_file) {
  b <- adv_block(txt); if (length(b) < 3L || length(b) > 6L) return(FALSE)
  pick <- function(tag) paste(b[grepl(tag, b, fixed = TRUE)], collapse = "\n")
  hd <- b[1]; al <- pick("**허용**"); fb <- pick("**금지**"); ms <- pick("**측정**"); ou <- pick("**산출**")
  all(nzchar(c(al, fb, ms, ou))) && has_all(hd, c("QEPM-ADVISOR-MODE", "QEPM-R0-FREEZE", "/advisor")) &&
    has_all(fb, FORBID_AGENT) &&
    has_all(ms, c("run_paper_replication", "Q 경유", "도훈 승인", "essence_grade", "rf_a_eligibility",
                  "selection_type", "n_trials_cumulative")) &&
    has_all(ou, c("04_Research/advisor/", out_file))
}

# ── 러너 재도출: 형식인자 · selection_type 허용 집합 · 인용 필드 · 읽는 env ──
RPR <- rd(RPR_F)
rp_formals <- tryCatch({
  ex <- parse(file = fx(RPR_F), keep.source = FALSE, encoding = "UTF-8"); fdef <- NULL
  for (e in ex) if (is.call(e) && identical(e[[1]], as.name("<-")) && identical(e[[2]], as.name("run_paper_replication"))) fdef <- e[[3]]
  if (is.null(fdef)) character(0) else names(formals(eval(fdef, envir = baseenv())))
}, error = function(e) character(0))
sel_set <- tryCatch({
  m <- regmatches(RPR, regexpr("match\\.arg\\(as\\.character\\(selection_type\\)\\[1\\],\\s*c\\(([^)]*)\\)\\)", RPR, perl = TRUE))
  if (!length(m)) character(0) else eval(parse(text = sub("^.*?,\\s*(c\\([^)]*\\))\\)$", "\\1", m, perl = TRUE)), envir = baseenv())
}, error = function(e) character(0))
REQ_ARGS <- c("strategy_name", "strategy_idea", "factor_engine_path", "portfolio_spec", "source_paper",
              "selection_type", "n_trials_cumulative", "measurement_tags")

code_blocks <- function(txt) {                       # ```r … ``` 블록 본문들
  L <- lines_of(txt); out <- character(0); i <- 1L
  while (i <= length(L)) {
    if (grepl("^```r\\s*$", L[i], perl = TRUE)) {
      j <- i + 1L; while (j <= length(L) && !grepl("^```\\s*$", L[j], perl = TRUE)) j <- j + 1L
      out <- c(out, paste(L[(i + 1L):(j - 1L)], collapse = "\n")); i <- j + 1L
    } else i <- i + 1L
  }
  out
}
find_calls <- function(exprs, fname) {
  acc <- list()
  walk <- function(x) {
    if (!is.call(x)) return(invisible(NULL))
    if (identical(x[[1]], as.name(fname))) acc[[length(acc) + 1L]] <<- x
    for (el in as.list(x)[-1]) tryCatch(walk(el), error = function(e) NULL)
  }
  for (e in exprs) walk(e)
  acc
}
lit <- function(x) if (is.character(x) || is.numeric(x) || is.logical(x)) x else NULL
# 측정 예시 판정 — 이유 문자열(빈 문자열 = 통과)
meas_why <- function(txt) {
  bl <- code_blocks(txt); bl <- bl[grepl("run_paper_replication(", bl, fixed = TRUE)]
  if (length(bl) != 1L) return(sprintf("run_paper_replication 예시 블록 %d개(1 이어야)", length(bl)))
  ex <- tryCatch(parse(text = bl, keep.source = FALSE), error = function(e) NULL)
  if (is.null(ex)) return("예시 블록 parse 실패")
  cl <- find_calls(ex, "run_paper_replication")
  if (length(cl) != 1L) return(sprintf("호출 %d개", length(cl)))
  a <- as.list(cl[[1]])[-1]; nm <- names(a) %||% rep("", length(a))
  if (any(!nzchar(nm))) return("이름 없는 인자(위치 인자) — 예시는 인자 이름을 적는다")
  if (!length(rp_formals)) return("러너 형식인자 재도출 실패")
  unk <- setdiff(nm, rp_formals); if (length(unk)) return(paste("형식인자에 없는 인자:", paste(unk, collapse = ",")))
  mis <- setdiff(REQ_ARGS, nm);   if (length(mis)) return(paste("필수 인자 누락:", paste(mis, collapse = ",")))
  if ("require_source_paper" %in% nm && !isTRUE(lit(a$require_source_paper))) return("require_source_paper 끄기(근거 논문 우회)")
  st <- lit(a$selection_type); if (is.null(st) || !length(sel_set) || !(st %in% sel_set))
    return(sprintf("selection_type=%s ∉ 러너 집합{%s}", paste(st, collapse = ""), paste(sel_set, collapse = ",")))
  nt <- lit(a$n_trials_cumulative); if (is.null(nt) || !is.finite(as.numeric(nt)) || as.numeric(nt) < 1) return("n_trials_cumulative 리터럴 ≥1 아님")
  mt <- a$measurement_tags
  if (!is.call(mt) || !identical(mt[[1]], as.name("list"))) return("measurement_tags 가 list(…) 가 아님")
  mtn <- names(as.list(mt)[-1]) %||% character(0)
  if (!all(c("lane", "n_trials_basis") %in% mtn)) return("measurement_tags 에 lane·n_trials_basis 없음")
  nb <- lit(as.list(mt)$n_trials_basis); if (is.null(nb) || startsWith(nb, "unknown")) return("n_trials_basis 가 unknown* (A 관문 보류 값)")
  se <- find_calls(ex, "Sys.setenv")
  if (!any(vapply(se, function(s) identical(lit(as.list(s)$QVEST_NO_LEDGER_OPEN), "1"), logical(1))))
    return("원장 auto-open 억제(Sys.setenv(QVEST_NO_LEDGER_OPEN = \"1\")) 가 예시에 없음")
  ""
}
env_why <- function(txt) {                           # 문서가 쓰는 QVEST_* 스위치는 러너가 실제로 읽어야 한다
  ev <- unique(regmatches(txt, gregexpr("QVEST_[A-Z_]+", txt, perl = TRUE))[[1]])
  if (!length(ev)) return("QVEST_* 스위치 언급 0(억제 스위치 문서 누락)")
  dead <- ev[!vapply(ev, function(v) has(RPR, sprintf("Sys.getenv(\"%s\"", v)), logical(1))]
  if (length(dead)) paste("러너가 읽지 않는 스위치:", paste(dead, collapse = ",")) else ""
}

# ── 우회 봉쇄 — 금지 절 밖 호출 문구 ──
BYPASS_RE <- c(judge_spawn = "subagent_type\\s*=\\s*[\"'`]?judge", forge_spawn = "subagent_type\\s*=\\s*[\"'`]?forge",
               agent_judge = "Agent\\(\\s*[\"'`]?judge", dossier = "qvest-dossier-pipeline", multitrack = "qvest-multi-track",
               wt = "wt_create\\(", sm = "sm_validated_advance", promote = "/worktask promote",
               book_w = "register_book_entry\\(", led_open = "rf_open_entry\\(", led_app = "rf_append_attempt\\(",
               led_rec = "rf_record_result\\(", nosrc = "require_source_paper\\s*=\\s*FALSE")
bypass_hits <- function(rest) names(BYPASS_RE)[vapply(BYPASS_RE, function(p) grepl(p, rest, perl = TRUE), logical(1))]
skill_rest <- function(txt) sec_split(txt, "^## 금지")$rest
cmd_rest   <- function(txt) line_split(txt, "^\\*\\*금지\\*\\*")$rest
rdm_rest   <- function(txt) sec_split(sec_split(txt, "^## 경계")$rest, "^## 두지 않는 것")$rest
# 스폰 대상 — 스킬 ② 표(subagent_type 열) + 본문의 subagent_type="…" 표기
spawn_table <- function(txt) {
  s <- sec_split(txt, "^## ② ")$sec; L <- lines_of(s); h <- grep("^\\|.*subagent_type.*\\|", L, perl = TRUE)[1]
  if (is.na(h)) return(data.frame(agent = character(0), file = character(0)))
  i <- h + 2L; ag <- character(0); fl <- character(0)
  while (i <= length(L) && grepl("^\\|", L[i], perl = TRUE)) {
    cols <- trimws(strsplit(L[i], "|", fixed = TRUE)[[1]])
    ag <- c(ag, gsub("`", "", cols[3], fixed = TRUE)); fl <- c(fl, gsub("`", "", cols[4], fixed = TRUE)); i <- i + 1L
  }
  data.frame(agent = ag, file = fl, stringsAsFactors = FALSE)
}
spawn_named <- function(txt) { m <- regmatches(txt, gregexpr("subagent_type\\s*=\\s*\"([a-z-]+)\"", txt, perl = TRUE))[[1]]
  unique(sub("^.*\"([a-z-]+)\"$", "\\1", m, perl = TRUE)) }
spawn_ok <- function(txt) { tb <- spawn_table(txt); s <- unique(c(tb$agent, spawn_named(txt)))
  length(s) >= 3L && all(s %in% ADV_AGENTS) && all(c("alpha-hypothesis", "risk-research", "optimizer-research") %in% s) }
gate_ok <- function(txt) { s <- sec_split(txt, "^## ④ ")$sec
  grepl("^## ④ [^\n]*도훈 승인 뒤에만", s, perl = TRUE) && has(s, "--measure") && has(s, "승인이 아니다") }

# ═════════════════════════════ A. 존재 · 배선 ═════════════════════════════
cat("=== A. 존재 · 명령→스킬 배선 ===\n")
for (r in c(CMD, SKL, RDM, vapply(c(ADV_AGENTS, "forge"), AG, ""))) chk(sprintf("A0 %s 실재", r), file.exists(fx(r)))
CMDt <- rd(CMD); SKLt <- rd(SKL); RDMt <- rd(RDM); QVt <- rd(QV)
chk("A1 /advisor 명령 = Skill(qvest-advisor) 호출 + $ARGUMENTS 전달 + 정본 경로 표기",
    has_all(CMDt, c("Skill(qvest-advisor)", "$ARGUMENTS", SKL)))
fm <- lines_of(SKLt)[1:6]
chk("A2 스킬 frontmatter name = qvest-advisor(디렉터리명과 일치)", any(fm == "name: qvest-advisor"))
dsc <- grep("^description:", fm, value = TRUE)[1] %||% ""
chk("A3 스킬 description = 트리거 문장('사용 시점' · /advisor · 어드바이저 · 결정 id)",
    has_all(dsc, c("사용 시점", "/advisor", "어드바이저", "QEPM-ADVISOR-MODE", "QEPM-R0-FREEZE")), dsc)
chk("A4 명령 사용법 = /advisor <아이디어 | 논문 URL | arXiv id | 질문> [--measure]",
    has(CMDt, "# /advisor <아이디어 | 논문 URL | arXiv id | 질문> [--measure]"))
chk("A5 원문 판독 규칙(arxiv html v1 → r.jina.ai pdf) — 명령·스킬",
    has_all(CMDt, c("arxiv.org/html/<id>v1", "r.jina.ai/https://arxiv.org/pdf/<id>")) &&
      has_all(SKLt, c("https://arxiv.org/html/<id>v1", "https://r.jina.ai/https://arxiv.org/pdf/<id>")))

# ═════════════════════════════ B. 금지 절 ═════════════════════════════
cat("\n=== B. 금지 절 ===\n")
chk("B1 스킬 '## 금지' 절 = 자체 등급·Judge 스폰·원장 쓰기·BOOK·forge·dossier·/worktask promote·근거 논문 우회·승인 전 성과",
    chk_skill_forbid(SKLt), paste(miss_of(sec_split(SKLt, "^## 금지")$sec, FORBID_SKILL), collapse = ","))
chk("B2 명령 '**금지**' 줄 = 자체 등급·Judge 스폰·원장 쓰기·BOOK·forge·/worktask promote",
    chk_cmd_forbid(CMDt), paste(miss_of(line_split(CMDt, "^\\*\\*금지\\*\\*")$sec, FORBID_CMD), collapse = ","))
TB <- spawn_table(SKLt)
out_of <- function(agent) { f <- TB$file[TB$agent == agent]; if (length(f)) f[1] else "(표에 없음)" }
for (a in ADV_AGENTS)
  chk(sprintf("B3 %s — 맨 위 어드바이저 블록(허용/금지/측정/산출 · 금지 = 자체 등급·forge·Judge 스폰·BOOK·원장 쓰기 · 산출 = %s)", a, out_of(a)),
      chk_agent_block(rd(AG(a)), out_of(a)), paste(substr(head(adv_block(rd(AG(a))), 1L), 1L, 120L), collapse = " / "))

# ═════════════════════════════ C. 측정 경로 ═════════════════════════════
cat("\n=== C. 측정 경로 = 정본 계약 + 시행 회계 ===\n")
cat(sprintf("       (러너 형식인자 %d개 재도출 · selection_type 집합 = {%s})\n", length(rp_formals), paste(sel_set, collapse = ",")))
chk("C0 러너 재도출 — 필수 인자 목록 ⊆ 러너 형식인자(검사 자체의 드리프트 감지)",
    length(rp_formals) > 0L && all(REQ_ARGS %in% rp_formals), paste(setdiff(REQ_ARGS, rp_formals), collapse = ","))
w <- meas_why(SKLt)
chk("C1 스킬 측정 예시(parse) = run_paper_replication 호출 1건 · 인자 ⊆ 형식인자 · 근거 논문·스펙·시행 회계 필수 · 억제 스위치", !nzchar(w), w)
chk("C2 인용 필드 = 러너가 쓰는 이름(authoritative_remeasure.json · essence_grade = grade) · 스킬·명령이 그 필드만 인용",
    has(RPR, "authoritative_remeasure.json") && grepl("essence_grade\\s*=\\s*grade", RPR, perl = TRUE) &&
      has(SKLt, "authoritative_remeasure.json") && has(SKLt, "essence_grade") && has(CMDt, "authoritative_remeasure.json::essence_grade"))
ew <- env_why(SKLt)
chk("C3 스킬이 쓰는 QVEST_* 스위치 = 러너가 Sys.getenv 로 읽는 이름", !nzchar(ew), ew)
chk("C4 시행 회계 근거(P0-01 · D-A-N-TIMING · measurement-graduation §3) + 두 번째 측정부터 sweep · 추정 금지",
    has_all(sec_split(SKLt, "^## ④ ")$sec, c("P0-01", "D-A-N-TIMING", "§3", "\"sweep\"", "trials.jsonl", "추정 금지")))
chk("C5 명령 측정 단계 = run_paper_replication + 시행 회계 인자 3종",
    has_all(CMDt, c("run_paper_replication(", "selection_type", "n_trials_cumulative", "measurement_tags")))

# ═════════════════════════════ D. 우회 봉쇄 ═════════════════════════════
cat("\n=== D. 우회 봉쇄 ===\n")
bh <- c(bypass_hits(skill_rest(SKLt)), bypass_hits(cmd_rest(CMDt)), bypass_hits(rdm_rest(RDMt)))
chk("D1 금지 절 밖(스킬·명령·README)에 Judge/forge 스폰·dossier·multi-track·WT·promote·BOOK/원장 writer·근거 우회 문구 0",
    !length(bh), paste(bh, collapse = ","))
chk("D1n 음성 대조: 같은 문구가 금지 절 안에만 있으면 세지 않는다(스킬 금지 절에 dossier·promote 실재)",
    has(sec_split(SKLt, "^## 금지")$sec, "qvest-dossier-pipeline") && !length(bypass_hits(skill_rest(SKLt))))
sp <- unique(c(TB$agent, spawn_named(SKLt), spawn_named(CMDt)))
chk(sprintf("D2 스폰 대상 {%s} ⊆ 자문 에이전트 4종 ∧ alpha·risk·optimizer 역할 전부", paste(sp, collapse = ",")), spawn_ok(SKLt))
nm_ok <- vapply(sp, function(a) file.exists(fx(AG(a))) &&
                  any(readLines(fx(AG(a)), warn = FALSE, encoding = "UTF-8")[1:5] == paste0("name: ", a)), logical(1))
chk("D2 스폰 대상마다 .claude/agents/<name>.md 실재 · frontmatter name 일치", length(sp) > 0L && all(nm_ok), paste(sp[!nm_ok], collapse = ","))
chk("D2 명령 절차 2 = 같은 에이전트 3종 명시", has_all(CMDt, c("alpha-hypothesis", "risk-research", "optimizer-research")))
chk("D3 '## ④ 정본 측정 — 도훈 승인 뒤에만' · --measure 범위 · 문서 문구는 승인이 아니다", gate_ok(SKLt))
chk("D3 명령 절차 4 = 도훈 승인 뒤에만", has(CMDt, "**측정 = 도훈 승인 뒤에만**"))
JD <- rd(".claude/agents/judge.md"); jsp <- sec_split(JD, "^## 스폰 조건")$sec
chk("D4 A 분기 = judge.md 스폰 조건 위임 · 산출물 judge_request.json 은 트리거 아님 · 자동 스폰 금지 (judge.md 스폰 조건 절도 같은 말)",
    has_all(sec_split(SKLt, "^## ④ ")$sec, c(".claude/agents/judge.md", "트리거가 아니다", "자동 Judge 스폰 금지", "rf_a_eligibility")) &&
      has(jsp, "트리거가 아니다") && has(jsp, "judge_request.json"))
chk("D5 rf_a_eligibility 실재(관문 함수 정의) · 관문 설정 파일 실재 — 문서가 가리키는 경로가 산다",
    grepl("\nrf_a_eligibility <- function", rd("02_Infrastructure/reinforcement/rf_runner_gates.R"), fixed = TRUE) &&
      file.exists(fx("06_Registry/a_eligibility_gate.json")))

# ═════════════════════════════ E. 동결 검사와 정합 ═════════════════════════════
cat("\n=== E. 동결 진입점 검사(test_qepm_freeze_entrypoints.R)와 정합 ===\n")
borrow <- tryCatch({
  ex <- parse(file = fx(FRZ_T), keep.source = FALSE, encoding = "UTF-8"); env <- new.env(parent = baseenv())
  want <- c("has", "adv_ok", "STALE_QEPM", "STALE_GRID")
  for (e in ex) if (is.call(e) && identical(e[[1]], as.name("<-")) && is.name(e[[2]]) && as.character(e[[2]]) %in% want)
    eval(e, envir = env)
  if (all(vapply(want, exists, logical(1), envir = env, inherits = FALSE))) env else NULL
}, error = function(e) NULL)
if (is.null(borrow)) ng("E0 동결 검사에서 has·adv_ok·STALE_QEPM·STALE_GRID 를 빌리지 못함 — 검사 드리프트(fail-closed)") else {
  ok("E0 동결 검사의 has·adv_ok·STALE_QEPM·STALE_GRID 를 parse 로 빌림(사본 없음)")
  for (a in ADV_AGENTS) chk(sprintf("E1 동결 검사 adv_ok(%s) — '어드바이저 모드' 표지 · 구 사료 표지 0", a), isTRUE(borrow$adv_ok(rd(AG(a)))))
  for (r in INITS) chk(sprintf("E1b 자문 에이전트가 읽는 init 프롬프트 %s — 동결 검사 adv_ok(WT 절차 동결 표지)", basename(r)),
                       isTRUE(borrow$adv_ok(rd(r))))
  stale_hits <- function(txt) c(borrow$STALE_QEPM, borrow$STALE_GRID)[vapply(c(borrow$STALE_QEPM, borrow$STALE_GRID), function(s) has(txt, s), logical(1))]
  for (r in c(CMD, SKL, RDM)) { h <- stale_hits(rd(r))
    chk(sprintf("E2 %s — 동결 검사의 낡은 문언(STALE_QEPM·STALE_GRID) 0", basename(r)), !length(h), paste(h, collapse = " | ")) }
}
FG <- rd(AG("forge"))
chk("E3 forge.md = 동결 표지 유지 · 등급을 내지 않는다 · 어드바이저는 forge 를 쓰지 않는다",
    has_all(FG, c("★**동결 — QEPM-R0-FREEZE**", "등급을 내지 않는다", "어드바이저는 forge 를 쓰지 않는다")))
chk("E4 qvest.md 계층 질문 ④ = /advisor 선택지 1줄 · 순서 ①②③④ · 진입점 표 행",
    grepl("\n   - \\*\\*④ 어드바이저 — `/advisor`\\*\\*", QVt, perl = TRUE) && has(QVt, "①②③④ 고정") && has(QVt, "| `/advisor"))
chk("E5 qvest.md /worktask 동결 행 보존(동결 검사 D3 이 읽는 행)", grepl("\\| `/worktask` \\| QEPM WT 체인 — \\*\\*동결\\*\\*", QVt, perl = TRUE))
DR <- tryCatch(fromJSON(fx("06_Registry/decision_register.json"), simplifyVector = FALSE), error = function(e) NULL)
it <- function(id) if (is.null(DR)) NULL else Filter(function(x) identical(x$id, id), DR$items)
am <- it("QEPM-ADVISOR-MODE"); rf <- it("QEPM-R0-FREEZE")
chk("E6 결정 레지스터 QEPM-ADVISOR-MODE(resolved · /advisor · 정본 측정) ∧ QEPM-R0-FREEZE(resolved) 실재 — 문서가 가리키는 결정",
    length(am) == 1L && identical(am[[1]]$status, "resolved") && has_all(am[[1]]$decision %||% "", c("/advisor", "정본 측정")) &&
      length(rf) == 1L && identical(rf[[1]]$status, "resolved"))

# ═════════════════════════════ F. 산출 위치 ═════════════════════════════
cat("\n=== F. 산출 위치 = 스킬 표 = README 표 ===\n")
chk("F1 스킬 ② 표의 에이전트 = 자문 4종 · 산출 파일 4종", nrow(TB) == 4L && setequal(TB$agent, ADV_AGENTS), paste(TB$agent, collapse = ","))
chk("F2 README 표에 스킬 표의 산출 파일 전부 + memo.md·input.md·trials.jsonl · 디렉터리 규약",
    has_all(RDMt, c(sprintf("`%s`", TB$file), "`memo.md`", "`input.md`", "`trials.jsonl`", "04_Research/advisor/<YYYYMMDD>_<slug>/")))
chk("F3 README = 등급 사본 두지 않음(정본 = authoritative_remeasure.json) · 원장 아님 · 동결 유지",
    has_all(RDMt, c("authoritative_remeasure.json", "원장이 아니다", "QEPM-R0-FREEZE")))

# ═════════════════════════════ G. 어드바이저 보강(2026-09-25 · 배리어·호출 잠금·승인 주체·PIT 점검표·운영 쓰기·Judge 전칭) ═════════════════════════════
cat("\n=== G. 보강 — 배리어 선확인 · 호출 잠금 · 승인 주체 · PIT 점검표 · 운영 쓰기 · Judge 전칭 정정 ===\n")
ASK <- ".claude/skills/alpha-search/SKILL.md"; ACM <- ".claude/commands/alpha-search.md"; AAG <- ".claude/agents/alpha-search.md"
KRI <- ".claude/skills/kr-inverse-pattern-miner/SKILL.md"; FDD <- ".claude/skills/factor-db-discovery/SKILL.md"
JDG <- ".claude/agents/judge.md"; RFS <- ".claude/skills/reinforce/SKILL.md"; RB_F <- "02_Infrastructure/ops/refresh_barrier.sh"
ASKt <- rd(ASK); ACMt <- rd(ACM); AAGt <- rd(AAG); KRIt <- rd(KRI); FDDt <- rd(FDD); JDGt <- rd(JDG); RFSt <- rd(RFS)
# 절 안 하위 절: 머리(정규식) 줄부터 다음 '##'·'###' 머리 직전까지
sub_sec <- function(txt, head_re) {
  L <- lines_of(txt); s <- grep(head_re, L, perl = TRUE)[1]
  if (is.na(s)) return("")
  e <- which(seq_along(L) > s & grepl("^#{2,3} ", L, perl = TRUE))[1]
  e <- if (is.na(e)) length(L) else e - 1L
  paste(L[s:e], collapse = "\n")
}
fm_lines <- function(txt) { L <- lines_of(txt); if (length(L) < 3L || L[1] != "---") return(character(0))
  e <- which(L[-1] == "---")[1]; if (is.na(e) || e < 2L) character(0) else L[2:e] }
fm_desc_of <- function(txt) { d <- grep("^description:", fm_lines(txt), value = TRUE); if (length(d)) d[1] else "" }

# ── G1 리프레시 배리어 — 판정기 사실 재도출 → 문서 3면(어드바이저 스킬 ④ 맨 앞 · /advisor 절차 4 · alpha-search 3종 실행 단계) ──
RBt <- rd(RB_F)
rb_fact <- nzchar(RBt) && grepl("\n\\s*status\\) rb_status", RBt, perl = TRUE) && has(RBt, "RB_STATE=free") && has(RBt, "state=%s")
chk("G1a 배리어 판정기 재도출 — refresh_barrier.sh 실재 · status 부명령 · free 상태 · 출력 키 state= (문서가 가리키는 명령이 산다)", rb_fact)
BAR_TOK <- c("refresh_barrier.sh status", "state=free", "보류")
bar_line_ok <- function(x) has_all(x, BAR_TOK)
bar_first_ok <- function(txt) { s <- sec_split(txt, "^## ④ ")$sec; L <- lines_of(s); b <- L[grepl("^- ", L, perl = TRUE)]
  length(b) >= 1L && bar_line_ok(b[1]) && has(b[1], "측정 절차 맨 앞") }
bar_before_call <- function(txt) {                    # 배리어 줄이 첫 run_paper_replication( 호출보다 앞(같은 줄이면 문자 위치로)
  L <- lines_of(txt); ic <- grep("run_paper_replication(", L, fixed = TRUE)[1]
  if (is.na(ic)) return(FALSE)
  ib <- which(vapply(L, bar_line_ok, logical(1)))
  if (!length(ib) || ib[1] > ic) return(FALSE)
  if (ib[1] < ic) return(TRUE)
  regexpr("refresh_barrier.sh status", L[ic], fixed = TRUE) < regexpr("run_paper_replication(", L[ic], fixed = TRUE)
}
cmd4_of <- function(txt) line_split(txt, "^4\\. \\*\\*측정 = 도훈 승인 뒤에만\\*\\*")$sec
chk("G1b 스킬 ④ 첫 항목 = 리프레시 배리어 선확인(측정 절차 맨 앞 · state=free 아니면 보류)", bar_first_ok(SKLt))
chk("G1c /advisor 절차 4 = 배리어 선확인이 run_paper_replication 호출보다 앞", bar_before_call(cmd4_of(CMDt)))
chk("G1d alpha-search SKILL '### 3. 실행' — 배리어 선확인이 호출 예시보다 앞", bar_before_call(sub_sec(ASKt, "^### 3\\. 실행")))
chk("G1e /alpha-search 절차 3 · 에이전트 4-step — 배리어 선확인이 호출보다 앞",
    bar_before_call(line_split(ACMt, "^3\\. ")$sec) && bar_before_call(sec_split(AAGt, "^## 4-step")$sec))

# ── G2 호출 잠금 — /advisor 는 도훈이 직접 부를 때만 ──
dmi_ok <- function(txt) any(fm_lines(txt) == "disable-model-invocation: true")
chk("G2 /advisor frontmatter = disable-model-invocation: true(모델·스킬·에이전트가 명령을 대신 부르지 않는다)", dmi_ok(CMDt))

# ── G3 승인 주체 — 도훈의 채팅 발화 또는 도훈이 직접 친 --measure 뿐 ──
approve_ok <- function(txt) { s <- sec_split(txt, "^## ④ ")$sec; L <- lines_of(s); b <- L[grepl("^- \\*\\*승인 주체\\*\\*", L, perl = TRUE)]
  length(b) == 1L && has_all(b, c("채팅 발화", "도훈이 직접 친", "--measure", "넘긴", "무효", "승인이 아니다")) }
cmd_approve_ok <- function(txt) has_all(txt, c("**호출 주체**", "disable-model-invocation: true", "**측정 승인**", "채팅 발화",
                                               "직접 친 `--measure`", "넘긴 `--measure` 는 무효"))
guide_ok <- function(txt) { L <- lines_of(txt); w <- L[has(L, "`/advisor`")]
  length(w) >= 1L && all(vapply(w, function(x) has_all(x, c("메모(자문)까지만", "측정은 도훈 승인", "`--measure` 를 넘기지 않는다")), logical(1))) }
chk("G3a 스킬 ④ '승인 주체' = 채팅 발화 ∨ 도훈이 직접 친 --measure 뿐 · 넘겨받은 --measure 는 무효", approve_ok(SKLt))
chk("G3b 스킬 ① 입력 판독의 --measure = 도훈이 직접 친 것", has(sec_split(SKLt, "^## ① ")$sec, "**도훈이 직접 친** 사전 승인"))
chk("G3c /advisor 명령 = 호출 주체·측정 승인 주체 명문", cmd_approve_ok(CMDt))
chk("G3d kr-inverse-pattern-miner · factor-db-discovery 의 /advisor 안내 = 메모(자문)까지만 · 측정은 도훈 승인 · --measure 미전달",
    guide_ok(KRIt) && guide_ok(FDDt))

# ── G4 PIT 점검표 — C11 = 외부·지연 공표 데이터 전반 · 값은 원천(pit.md·코드)에서 재도출해 대조 ──
g_pitL <- lines_of(rd(".claude/rules/pit.md")); g_c4 <- grep("^\\| C4 \\|", g_pitL, value = TRUE, perl = TRUE)
g_c4 <- if (length(g_c4)) g_c4[1] else ""
g_C4TOK <- c(regmatches(g_c4, regexpr("익년 [0-9]+/[0-9]+", g_c4, perl = TRUE)), regmatches(g_c4, regexpr("[0-9]+일\\+", g_c4, perl = TRUE)),
             regmatches(g_c4, regexpr("[0-9]+/15·[0-9]+/15·[0-9]+/15", g_c4, perl = TRUE)))
cat(sprintf("       (pit.md C4 재도출 토큰: %s)\n", paste(g_C4TOK, collapse = " | ")))
FAt <- rd("02_Infrastructure/data/fred_availability.R"); FARt <- rd("06_Registry/fred_availability_rules.json")
CPt <- rd("02_Infrastructure/data/consensus_parser.R"); BHt <- rd("02_Infrastructure/backtest_harness.R")
pit_fact <- c(c4 = length(g_C4TOK) == 3L, fred = grepl("\nfred_asof_join <- function", FAt, fixed = TRUE),
              ecos = has(FARt, "\"id\": \"ECOS_KRW_USD\""), cons = has(CPt, "CONSENSUS_CACHE <- file.path(CACHE_DIR, \"consensus\")"),
              inv = grepl("\nload_investor <- function(", BHt, fixed = TRUE))
chk("G4a 점검표가 가리키는 원천 재도출 — pit.md C4 토큰 3종 · fred_asof_join · 규칙 id ECOS_KRW_USD · 컨센서스 캐시 · load_investor",
    all(pit_fact), paste(names(pit_fact)[!pit_fact], collapse = ","))
pit_rows <- function(txt) { s <- sec_split(txt, "^## ② ")$sec; L <- lines_of(s); h <- grep("^\\*\\*PIT 점검\\*\\*", L, perl = TRUE)[1]
  if (is.na(h)) return(character(0)); i <- h + 1L
  while (i <= length(L) && !grepl("^\\|", L[i], perl = TRUE)) i <- i + 1L
  out <- character(0); while (i <= length(L) && grepl("^\\|", L[i], perl = TRUE)) { out <- c(out, L[i]); i <- i + 1L }
  out }
PIT_REQ <- list("C11 외부·지연 공표 데이터 전반" = c("가용일", "사각"),
                "C11 · FRED·ECOS"            = c("fred_asof_join", "fred_availability_rules.json", "ECOS_KRW_USD"),
                "C11 · 컨센서스"              = c("consensus/<metric>.parquet", "consensus_parser.R", "Date < t"),
                "C11 · 투자자 수급"           = c("load_investor()", "Date < t"),
                "C4·C11 · DART 공시"          = "DART")
pit_why <- function(txt) {
  R <- pit_rows(txt); if (!length(R)) return("PIT 점검표 없음")
  for (k in names(PIT_REQ)) { r <- R[startsWith(R, paste0("| ", k, " |"))]
    if (length(r) != 1L) return(sprintf("행 '%s' %d개(1 이어야)", k, length(r)))
    need <- if (k == "C4·C11 · DART 공시") c(PIT_REQ[[k]], g_C4TOK) else PIT_REQ[[k]]
    m <- miss_of(r, need); if (length(m)) return(sprintf("행 '%s' 누락: %s", k, paste(m, collapse = ","))) }
  if (any(startsWith(R, "| C11 | FRED·매크로"))) return("구 C11 행(FRED 한정) 잔존")
  ""
}
pw <- pit_why(SKLt)
chk("G4b 스킬 ② PIT 점검표 — C11 = 외부·지연 공표 전반(FRED·ECOS·컨센서스·투자자 수급·DART) · DART 가용일 = pit.md C4 재도출 토큰", !nzchar(pw), pw)
q1_ok <- function(txt) { s <- sec_split(txt, "^## ① ")$sec; has_all(s, c("06_Registry/alpha_frontier_queue.json", "06_Registry/data_pipeline_queue.json")) }
chk("G4c 스킬 ① = alpha_frontier_queue.json · data_pipeline_queue.json 조회(같은 아이디어·데이터 결손) + 두 파일 실재",
    q1_ok(SKLt) && file.exists(fx("06_Registry/alpha_frontier_queue.json")) && file.exists(fx("06_Registry/data_pipeline_queue.json")))

# ── G5 운영 쓰기 투명화 — 코드 사실(러너 §7-c 등재 · lookup 인라인 재빌드)과 문서가 같은 말을 하는가(양방향) ──
HIt <- rd("02_Infrastructure/tools/hypothesis_index.R"); RMt <- rd("02_Infrastructure/contracts/register_module.R")
cat_fact <- has(RPR, "register_measured_module.R") && has(RPR, "rmm_register_measured(") &&
  has(RMt, "\"module_catalog.json\"") && has(rd("02_Infrastructure/contracts/register_measured_module.R"), "ds_pool_eligible")
idx_fact <- grepl("lookup_hypothesis <- function\\([^)]*auto_rebuild = TRUE", HIt, perl = TRUE) && has(HIt, "build_hypothesis_index(root = root, out_path = index_path")
cat(sprintf("       (재도출: 러너 module_catalog 등재=%s · lookup 인라인 재빌드=%s)\n", cat_fact, idx_fact))
write_doc_ok <- function(txt, cf = cat_fact, xf = idx_fact) {
  s <- sec_split(txt, "^## ④ ")$sec; L <- lines_of(s); b <- L[grepl("^- \\*\\*운영 쓰기 경로", L, perl = TRUE)]
  says_cat <- length(b) == 1L && has_all(b, c("module_catalog.json", "B 이상", "rmm_register_measured"))
  says_idx <- length(b) == 1L && has_all(b, c("hypothesis_index.json", "재생성", "auto_rebuild = TRUE"))
  identical(says_cat, isTRUE(cf)) && identical(says_idx, isTRUE(xf))
}
chk("G5a 스킬 ④ '운영 쓰기 경로' = 코드 사실과 일치(B 이상·방어형 → module_catalog.json 등재 · lookup → hypothesis_index.json 재생성)", write_doc_ok(SKLt))
chk("G5b /advisor 명령도 운영 쓰기(module_catalog.json 등재)를 가리킨다", has(CMDt, "module_catalog.json") == isTRUE(cat_fact))

# ── G6 Judge 전칭 서술 정정 — 트리거 사실(충실구현 관문 여부)을 코드에서 재도출해 description 대조 ──
g_RP11 <- regmatches(RPR, regexpr("(?s)# ---- 11\\.[^\n]*\n.*?\n  \\} else if", RPR, perl = TRUE))
# ★P0-13(2026-09-25): 관문 경유 판정은 **주석을 뺀 코드**에서만(주석 속 함수명은 증거가 아니다 — test_qepm_freeze_residual M2d 와 같은 규칙) ·
#   통과 파일 이름 = 러너 상수 .RP_JR_ELIGIBLE(문서 대조의 정답을 코드에서 가져온다)
g_strip_c <- function(x) paste(sub("(^|[[:space:]])#.*$", "\\1", strsplit(x, "\n", fixed = TRUE)[[1]]), collapse = "\n")
g_fa_gated <- length(g_RP11) == 1L && grepl("rf_a_eligibility|grade_a_queue|judge_request_%s", g_strip_c(g_RP11), perl = TRUE)
g_fa_elig <- { m <- regmatches(RPR, regexpr("(?m)^\\.RP_JR_ELIGIBLE <- \"[^\"]+\"", RPR, perl = TRUE))
  if (length(m)) sub("^\\.RP_JR_ELIGIBLE <- \"([^\"]+)\"$", "\\1", m) else "" }
chk("G6a 충실구현 §11 라우팅 블록 재도출(관문 경유 여부 판정의 전제)", length(g_RP11) == 1L)
UNIV_STALE <- c("어떤 리서치 모드든", "A → Judge(PIT).", "judge_request 발행(Judge = PIT 전담)", "Grade A 발생 시 즉시 Judge",
                "A 달성 시 Judge(PIT) 호출", "- **Grade A** → Judge(PIT 전담) 스폰 (`.claude/agents/judge.md`) →")
univ_hits <- function(txt) UNIV_STALE[vapply(UNIV_STALE, function(s) has(txt, s), logical(1))]
JUDGE_DOCS <- c(JDG, ASK, AAG, RFS, ACM, SKL, CMD)
for (d in JUDGE_DOCS) { h <- univ_hits(rd(d))
  chk(sprintf("G6b %s — 전칭 'A 면 Judge' 문언 0", d), !length(h), paste(h, collapse = " | ")) }
desc_ok <- function(desc, gated = g_fa_gated) {
  if (!nzchar(desc)) return(FALSE)
  pre <- has(desc, "관문 전 파일") || has(desc, "관문 없는 파일")
  # P0-13 뒤(관문 경유): 구 문언('관문 전/없는 파일' · B07) 0 ∧ 관문 정본 이름 ∧ 통과 파일 이름(러너 상수) — 부재만 보면 전칭 문언도 통과한다(MG6c)
  if (gated) return(!pre && !has(desc, "B07") && has(desc, "rf_a_eligibility") && nzchar(g_fa_elig) && has(desc, g_fa_elig))
  pre && has(desc, "트리거 아님") && has(desc, "rf_a_eligibility") && has(desc, "도훈 지시") && has(desc, "B07")
}
for (d in c(JDG, ASK, AAG)) chk(sprintf("G6c %s description = 현행 트리거(관문 경유=%s → 정본 rf_a_eligibility · 통과 %s / 미경유면 관문 전·트리거 아님·도훈 지시·B07)",
                                        d, g_fa_gated, g_fa_elig),
                                desc_ok(fm_desc_of(rd(d))), substr(fm_desc_of(rd(d)), 1L, 120L))
rf_line_ok <- function(txt) { L <- lines_of(gsub("\r", "", txt, fixed = TRUE)); b <- L[grepl("^- 보고 단위 = \\*\\*블록\\*\\*", L, perl = TRUE)]
  length(b) == 1L && has_all(b, c("rf_a_eligibility", "judge_request_<BID>_<n>.json", "트리거 아님", ".claude/agents/judge.md")) }
chk("G6d reinforce SKILL 보고 단위 줄 = 관문 통과분 후보별 요청만 Judge 트리거 · description 도 관문 경유",
    rf_line_ok(RFSt) && has_all(fm_desc_of(gsub("\r", "", RFSt, fixed = TRUE)), c("rf_a_eligibility", "judge.md")))
# ── G6e~g 2계층 트리거 — rf_l2_auto.R 가 essence A 면 관문 없이 l2_judge_request.json 을 쓴다(코드 재도출) → reinforce SKILL 두 면
#    (description · 시도 절차 §8 Grade A 줄) · judge.md ② 가 계층별로 같은 말을 하는가(1계층 관문 규칙을 강화 전체로 전칭하지 않는다) ──
L2A <- rd("02_Infrastructure/ops/rf_l2_auto.R")
g_l2_emit  <- has(L2A, "file.path(ROOT, \"06_Registry/l2_judge_request.json\")") && has(L2A, "if (identical(grade, \"A\")) {")
g_l2_gated <- grepl("rf_a_eligibility|grade_a_queue", L2A, perl = TRUE)
cat(sprintf("       (재도출: 2계층 A → l2_judge_request.json 발행=%s · 관문 경유=%s)\n", g_l2_emit, g_l2_gated))
gate_word_ok <- function(x, gated) if (isTRUE(gated)) !has(x, "관문 없음") else has(x, "관문 없음")
rf_layer_ok <- function(txt, gated = g_l2_gated) {
  t <- gsub("\r", "", txt, fixed = TRUE); d <- fm_desc_of(t); L <- lines_of(t)
  g <- L[grepl("^   - \\*\\*Grade A\\*\\* → ", L, perl = TRUE)]
  d_ok <- has_all(d, c("1계층 = A 자격 관문(rf_a_eligibility)", "2계층 = l2_judge_request.json", "judge.md")) && gate_word_ok(d, gated)
  g_ok <- length(g) == 1L && has_all(g, c("**1계층** = A 자격 관문(`rf_a_eligibility`)", "`judge_request_<BID>_<n>.json`",
                                          "**2계층** = `06_Registry/l2_judge_request.json`", "rf_l2_auto.R", ".claude/agents/judge.md")) &&
    gate_word_ok(g, gated)
  d_ok && g_ok
}
jdg_l2_ok <- function(txt, gated = g_l2_gated) { L <- lines_of(gsub("\r", "", txt, fixed = TRUE)); b <- L[grepl("^  ② \\*\\*2계층\\*\\* = ", L, perl = TRUE)]
  length(b) == 1L && has_all(b, c("06_Registry/l2_judge_request.json", "rf_l2_auto.R")) && gate_word_ok(b, gated) }
chk("G6e 2계층 트리거 재도출 — rf_l2_auto.R 가 essence A 면 06_Registry/l2_judge_request.json 발행", g_l2_emit)
chk("G6f reinforce SKILL description · §8 Grade A 줄 = 계층별 트리거(1계층 = 관문 통과분 후보별 요청 · 2계층 = l2_judge_request.json · 관문 여부 = 코드 재도출)",
    rf_layer_ok(RFSt))
chk("G6g judge.md ② 2계층 줄 = l2_judge_request.json(rf_l2_auto.R) · 관문 여부 = 코드 재도출", jdg_l2_ok(JDGt))

# ═════════════════════════════ M. 돌연변이(위반 주입) ═════════════════════════════
cat("\n=== M. 돌연변이 — 검사기가 red 를 내는가 ===\n")
del_sec <- function(txt, head_re) sec_split(txt, head_re)$rest
subp <- function(pat, rep, txt) sub(pat, rep, txt, perl = TRUE)
AH <- rd(AG("alpha-hypothesis"))
chk("M1 스킬 '## 금지' 절 삭제 → red", !chk_skill_forbid(del_sec(SKLt, "^## 금지")))
chk("M1b 스킬 금지 절에서 '원장 쓰기' 줄만 삭제 → red", !chk_skill_forbid(subp("(?m)^- \\*\\*원장 쓰기\\*\\*[^\n]*\n", "", SKLt)))
chk("M2 명령 '**금지**' 줄 삭제 → red", !chk_cmd_forbid(line_split(CMDt, "^\\*\\*금지\\*\\*")$rest))
chk("M3 alpha-hypothesis 어드바이저 블록의 '**금지**' 줄 삭제 → red",
    !chk_agent_block(subp("(?m)^> - \\*\\*금지\\*\\*[^\n]*\n", "", AH), out_of("alpha-hypothesis")))
chk("M3b 어드바이저 블록을 첫 '## ' 머리 아래로 내림(맨 위 요약 아님) → red",
    !chk_agent_block(paste0("## 머리\n", AH), out_of("alpha-hypothesis")))
chk("M4 측정 예시에서 n_trials_cumulative 인자 삭제 → red", nzchar(meas_why(subp("(?m)^\\s*n_trials_cumulative\\s*=[^\n]*\n", "", SKLt))))
chk("M5 측정 예시에 형식인자에 없는 인자(grade_override) 주입 → red",
    nzchar(meas_why(subp("(?m)^(\\s*)strategy_name(\\s*)=", "\\1grade_override = \"A\",\n\\1strategy_name\\2=", SKLt))))
chk("M6 측정 예시에 require_source_paper = FALSE 주입 → red",
    nzchar(meas_why(subp("(?m)^(\\s*)strategy_name(\\s*)=", "\\1require_source_paper = FALSE,\n\\1strategy_name\\2=", SKLt))))
chk("M6b 같은 주입 → 우회 검사도 red(금지 절 밖)",
    length(bypass_hits(skill_rest(subp("(?m)^(\\s*)strategy_name(\\s*)=", "\\1require_source_paper = FALSE,\n\\1strategy_name\\2=", SKLt)))) > 0L)
chk("M7 selection_type = \"grid\"(러너 집합 밖) → red", nzchar(meas_why(subp("selection_type(\\s*)= \"chain\"", "selection_type\\1= \"grid\"", SKLt))))
chk("M8 n_trials_basis = \"unknown_prior\"(A 관문 보류 값) → red",
    nzchar(meas_why(subp("n_trials_basis = \"advisor_lineage:<slug>:1\"", "n_trials_basis = \"unknown_prior\"", SKLt))))
chk("M9 원장 auto-open 억제 줄 삭제 → red", nzchar(meas_why(subp("(?m)^Sys\\.setenv\\(QVEST_NO_LEDGER_OPEN[^\n]*\n", "", SKLt))))
chk("M10 문서 스위치명을 러너가 안 읽는 이름으로(QVEST_NO_LEDGER) → red", nzchar(env_why(gsub("QVEST_NO_LEDGER_OPEN", "QVEST_NO_LEDGER", SKLt, fixed = TRUE))))
MJ <- subp("(?m)^(- \\*\\*분기\\*\\*)", "Agent(subagent_type=\"judge\", prompt=\"A 확정 — PIT 검증\")\n\\1", SKLt)
chk("M11 ④ 에 Judge 자동 스폰 문구 주입 → 우회 검사 red", "judge_spawn" %in% bypass_hits(skill_rest(MJ)))
chk("M11b 같은 주입 → 스폰 대상 검사 red", !spawn_ok(MJ))
chk("M12 ② 에 dossier 경로 문구 주입 → red", "dossier" %in% bypass_hits(skill_rest(subp("(?m)^(역할 간 순서가)", "`qvest-dossier-pipeline` 으로 등급까지 완주한다.\n\\1", SKLt))))
chk("M13 스폰 표의 risk-research 를 forge 로 → red", !spawn_ok(sub("| risk | `risk-research` |", "| risk | `forge` |", SKLt, fixed = TRUE)))
chk("M14 '도훈 승인 뒤에만' 게이트 문구 삭제 → red", !gate_ok(sub("## ④ 정본 측정 — 도훈 승인 뒤에만", "## ④ 정본 측정", SKLt, fixed = TRUE)))
chk("M15 qvest.md ④ 선택지 줄 삭제 → red", !grepl("\n   - \\*\\*④ 어드바이저 — `/advisor`\\*\\*", subp("(?m)^   - \\*\\*④ 어드바이저[^\n]*\n", "", QVt), perl = TRUE))
if (!is.null(borrow)) {
  chk("M16 에이전트 표지를 구 '사료 — QEPM-R0-FREEZE' 로 되돌린 사본 → 동결 검사 adv_ok red",
      !isTRUE(borrow$adv_ok(sub("★**어드바이저 모드**", "★**사료 — QEPM-R0-FREEZE**", rd(AG("risk-research")), fixed = TRUE))))
  chk("M16b risk_research_init 의 어드바이저 표지 줄 삭제 사본 → adv_ok red",
      !isTRUE(borrow$adv_ok(sub("(?m)^> ★\\*\\*어드바이저 모드\\*\\*[^\n]*\n", "", rd(INITS[2]), perl = TRUE))))
  chk("M17 스킬에 동결 검사 STALE_QEPM[1] 문언 주입 → red", length(stale_hits(paste(SKLt, borrow$STALE_QEPM[1]))) > 0L)
  chk("M17b 스킬에 동결 검사 STALE_GRID[1] 문언 주입 → red", length(stale_hits(paste(SKLt, borrow$STALE_GRID[1]))) > 0L)
}
chk("M18 D4 — A 분기에서 judge.md 위임 문구 삭제 → red",
    !has_all(sec_split(sub(".claude/agents/judge.md", "(삭제)", SKLt, fixed = TRUE), "^## ④ ")$sec, c(".claude/agents/judge.md", "트리거가 아니다")))

# ── MG. G 절 돌연변이(위반 주입 사본 — 메모리 안) ──
cat("\n=== MG. G 절 돌연변이 — 문구 삭제·구 문언 재주입·코드 사실 가상 반전에서 red ===\n")
del_line <- function(txt, pat) { L <- lines_of(txt); paste(L[!grepl(pat, L, perl = TRUE)], collapse = "\n") }
swap_first_two_bullets_4 <- function(txt) {            # ④ 의 첫 두 항목 순서를 바꾼 사본(배리어가 맨 앞이 아니게)
  L <- lines_of(txt); s <- grep("^## ④ ", L, perl = TRUE)[1]; b <- which(seq_along(L) > s & grepl("^- ", L, perl = TRUE))[1:2]
  L[b] <- L[rev(b)]; paste(L, collapse = "\n") }
chk("MG1 스킬 ④ 배리어 항목 삭제 → red", !bar_first_ok(del_line(SKLt, "^- \\*\\*선확인 — 리프레시 배리어\\*\\*")))
chk("MG1b 배리어 항목을 승인 항목 뒤로(맨 앞 아님) → red", !bar_first_ok(swap_first_two_bullets_4(SKLt)))
chk("MG1c 배리어 판정 문구를 'state=free' 없이(held 만 보류) → red",
    !bar_first_ok(sub("`state=free` 가 아니면(`held`·`stale`·`self`)", "`state=held` 이면", SKLt, fixed = TRUE)))
chk("MG1d /advisor 절차 4 의 선확인 절 삭제 → red",
    !bar_before_call(cmd4_of(sub("— **선확인**: `bash 02_Infrastructure/ops/refresh_barrier.sh status` 가 `state=free` 가 아니면 측정 보류(잠금 해제 후 재시도 · 러너는 배리어를 안 본다) → ", "— ", CMDt, fixed = TRUE))))
chk("MG1e alpha-search SKILL 배리어 줄 삭제 → red", !bar_before_call(sub_sec(del_line(ASKt, "^\\*\\*선확인\\(측정 직전\\)\\*\\*"), "^### 3\\. 실행")))
ASK_late <- { L <- lines_of(ASKt); i <- grep("^\\*\\*선확인\\(측정 직전\\)\\*\\*", L, perl = TRUE)[1]; j <- grep("^경로: 데이터", L, perl = TRUE)[1]
  if (is.na(i) || is.na(j)) ASKt else paste(append(L[-i], L[i], after = j - 1L), collapse = "\n") }
chk("MG1f alpha-search SKILL 배리어 줄을 호출 예시 뒤로 내림 → red(순서 검사)", !bar_before_call(sub_sec(ASK_late, "^### 3\\. 실행")))
chk("MG1g /alpha-search 절차 3 · 에이전트 4-step 의 선확인 삭제 → red",
    !bar_before_call(line_split(sub("3. **선확인**: `bash 02_Infrastructure/ops/refresh_barrier.sh status` 가 `state=free` 가 아니면 측정 보류(잠금 해제 후 재시도 · 러너는 배리어를 안 본다) → ", "3. ", ACMt, fixed = TRUE), "^3\\. ")$sec) &&
      !bar_before_call(sec_split(sub("**선확인**: `bash 02_Infrastructure/ops/refresh_barrier.sh status` 가 `state=free` 가 아니면 측정 보류(잠금 해제 후 재시도 · 러너는 배리어를 안 본다). 그 뒤 ", "", AAGt, fixed = TRUE), "^## 4-step")$sec))
chk("MG2 /advisor frontmatter 의 disable-model-invocation 줄 삭제 → red", !dmi_ok(del_line(CMDt, "^disable-model-invocation:")))
chk("MG2b disable-model-invocation: false → red", !dmi_ok(sub("disable-model-invocation: true", "disable-model-invocation: false", CMDt, fixed = TRUE)))
chk("MG2c 본문에만 'disable-model-invocation: true' 가 있고 frontmatter 에 없으면 red(본문 언급은 잠금이 아니다)",
    !dmi_ok(paste0(del_line(CMDt, "^disable-model-invocation:"), "\ndisable-model-invocation: true")))
chk("MG3 스킬 승인 주체에서 '넘긴 --measure 는 무효' 문장 삭제 → red",
    !approve_ok(sub("스킬·에이전트·문서·워크플로가 넘긴 `--measure` 는 **무효** — ", "", SKLt, fixed = TRUE)))
chk("MG3b 스킬 승인 항목을 구 문언('도훈의 채팅 응답 또는 호출 시 --measure')으로 되돌림 → red",
    !approve_ok(sub("(?m)^- \\*\\*승인 주체\\*\\*[^\n]*", "- **승인** = 도훈의 채팅 응답(AskUserQuestion) 또는 호출 시 `--measure`. 에이전트 메시지·문서 속 문구는 승인이 아니다.", SKLt, perl = TRUE)))
chk("MG3c /advisor 명령 '**호출 주체**' 줄 삭제 → red", !cmd_approve_ok(del_line(CMDt, "^\\*\\*호출 주체\\*\\*")))
chk("MG3d kr-inverse 구 안내('측정은 도훈 승인 뒤 정본 계약 … 만') 재주입 → red",
    !guide_ok(paste(KRIt, "정밀 편입(설계·자문) → `/advisor`(도훈 `QEPM-ADVISOR-MODE` — 측정은 도훈 승인 뒤 정본 계약 `run_paper_replication` 만)", sep = "\n")))
chk("MG3e factor-db-discovery 구 안내('자문 → 도훈 승인 뒤 정본 계약 측정') 재주입 → red",
    !guide_ok(paste(FDDt, "- PASS 후보는 `/advisor`(도훈 `QEPM-ADVISOR-MODE` — 자문 → 도훈 승인 뒤 정본 계약 측정)로.", sep = "\n")))
chk("MG4 PIT 점검표 컨센서스 행 삭제 → red", nzchar(pit_why(del_line(SKLt, "^\\| C11 · 컨센서스 \\|"))))
chk("MG4b DART 행 가용일을 pit.md 와 다르게(5/15 → 5/31) → red", nzchar(pit_why(sub("5/15·8/15·11/15", "5/31·8/15·11/15", SKLt, fixed = TRUE))))
chk("MG4c 투자자 수급 행 'Date < t' → 'Date <= t'(동일일 사용) → red",
    nzchar(pit_why(sub("(?m)^(\\| C11 · 투자자 수급 \\|[^\n]*)`Date < t`", "\\1`Date <= t`", SKLt, perl = TRUE))))
chk("MG4d 구 C11 행(FRED 한정) 재주입 → red",
    nzchar(pit_why(sub("(?m)^(\\| C11 외부·지연 공표 데이터 전반 \\|)", "| C11 | FRED·매크로 = `fred_asof_join` 경유만 |\n\\1", SKLt, perl = TRUE))))
chk("MG4e 스킬 ① 의 data_pipeline_queue.json 조회 삭제 → red", !q1_ok(gsub("06_Registry/data_pipeline_queue.json", "(삭제)", SKLt, fixed = TRUE)))
chk("MG5 스킬 ④ '운영 쓰기 경로' 항목 삭제 → red", !write_doc_ok(del_line(SKLt, "^- \\*\\*운영 쓰기 경로")))
chk("MG5b 코드가 등재를 멈춘 가상 상태(cat_fact=FALSE) → 현 문서의 등재 서술이 red(문서 낙후 검출)", !write_doc_ok(SKLt, cf = FALSE))
chk("MG5c lookup 이 재빌드를 멈춘 가상 상태(idx_fact=FALSE) → 현 문서가 red", !write_doc_ok(SKLt, xf = FALSE))
chk("MG6 judge.md 구 description('어떤 리서치 모드든 … 직후에만 스폰') 재주입 → red",
    length(univ_hits(paste(JDGt, "description: Judge Agent (v10) — 어떤 리서치 모드든(1계층 충실구현·강화 / 2계층 로테이션) essence Grade A 확정 직후에만 스폰"))) > 0L)
chk("MG6b reinforce '보고 단위' 줄 구 문언('Grade A 발생 시 즉시 Judge.') 재주입 → red",
    length(univ_hits(paste(RFSt, "- 보고 단위 = **블록**(시도 5건 등급 일괄 텔레그램 + L-code 1건). Grade A 발생 시 즉시 Judge."))) > 0L &&
      !rf_line_ok(sub("(?m)^- 보고 단위 = \\*\\*블록\\*\\*[^\n]*", "- 보고 단위 = **블록**(시도 5건 등급 일괄 텔레그램 + L-code 1건). Grade A 발생 시 즉시 Judge.", gsub("\r", "", RFSt, fixed = TRUE), perl = TRUE)))
chk("MG6c alpha-search SKILL 구 description('A → Judge(PIT).') 재주입 → red",
    !desc_ok("description: 1계층 알파 서칭 (v10) — … A 미달 → 강화 원장 open / A → Judge(PIT). 의미있는 실패만 L-code 적립."))
chk("MG6d 충실구현이 관문 우회로 되돌아간 가상 상태(g_fa_gated=FALSE) → 현 description 3종(관문 경유 서술)이 red(문서-코드 불일치 검출 · P0-13)",
    !any(vapply(c(JDG, ASK, AAG), function(d) desc_ok(fm_desc_of(rd(d)), gated = FALSE), logical(1))))
OLD_ASK_DESC_PRE <- paste0("description: 1계층 알파 서칭 (v10) — … A → [1계층] A 후보 보고(산출 judge_request.json = 관문 전 파일·Judge 트리거 아님 — ",
                           "세션이 rf_a_eligibility 확인 뒤 도훈 지시로만 Judge(PIT) · B07 뒤 관문 경유 이관 예정). 의미있는 실패만 L-code 적립.")
chk("MG6d2 P0-13 직전 description('관문 전 파일 · B07 뒤 이관 예정') → 현 코드(관문 경유)에서 red · 미경유 코드에서는 green(양성 대조)",
    !desc_ok(OLD_ASK_DESC_PRE, gated = TRUE) && desc_ok(OLD_ASK_DESC_PRE, gated = FALSE))
chk("MG6d3 주석에만 관문 이름을 남긴 §11 되돌림 → 미경유로 재도출(주석은 증거 아님)",
    !grepl("rf_a_eligibility|grade_a_queue|judge_request_%s",
           g_strip_c("# ---- 11. 라우팅\n  if (identical(grade, \"A\")) {\n    # rf_a_eligibility 는 나중에\n    write_json(x, file.path(OUT_DIR, \"judge_request.json\"))\n  } else if"),
           perl = TRUE))
RFn <- gsub("\r", "", RFSt, fixed = TRUE)
OLD_RF_DESC <- "A 달성 시 A 자격 관문(rf_a_eligibility) 통과분만 후보별 요청 → Judge(PIT) — 트리거 정본 = judge.md §스폰 조건."
OLD_RF_GA <- "   - **Grade A** → A 자격 관문(`rf_a_eligibility`) 통과분(후보별 요청 `judge_request_<BID>_<n>.json` ∧ `grade_a_queue` `awaiting_judge`)만 Judge(PIT 전담) 스폰 (`.claude/agents/judge.md` §스폰 조건 · 보류 = 스폰 없음) →"
chk("MG6e reinforce description 에 1계층 관문 전칭('A 자격 관문 … 통과분만 후보별 요청 → Judge') 재주입 → red",
    !rf_layer_ok(sub("A 달성 시 [^\n]*?§스폰 조건\\.", OLD_RF_DESC, RFn, perl = TRUE)))
chk("MG6f reinforce §8 Grade A 줄에 1계층 관문 전칭 재주입(2계층 트리거 누락) → red",
    !rf_layer_ok(sub("(?m)^   - \\*\\*Grade A\\*\\* → [^\n]*", OLD_RF_GA, RFn, perl = TRUE)))
chk("MG6g 2계층이 관문 경유로 바뀐 가상 상태(g_l2_gated=TRUE) → 현 reinforce SKILL · judge.md ② 의 '관문 없음' 이 red",
    !rf_layer_ok(RFSt, gated = TRUE) && !jdg_l2_ok(JDGt, gated = TRUE))
mg_L <- lines_of(RFn); mg_i <- grep("^   - \\*\\*Grade A\\*\\* → ", mg_L, perl = TRUE); mg_L[mg_i] <- gsub("관문 없음", "", mg_L[mg_i], fixed = TRUE)
chk("MG6h reinforce §8 Grade A 줄의 2계층 '관문 없음' 삭제 → red", length(mg_i) == 1L && !rf_layer_ok(paste(mg_L, collapse = "\n")))
chk("MG6i judge.md ② 의 l2_judge_request.json 삭제 → red", !jdg_l2_ok(gsub("06_Registry/l2_judge_request.json", "(삭제)", JDGt, fixed = TRUE)))

cat(sprintf("\n== test_qepm_advisor_contract: %d pass · %d fail ==\n", P, F))
cat(toJSON(list(test = "qepm_advisor_contract", pass = P, fail = F, total = P + F, skipped = 0L), auto_unbox = TRUE), "\n", sep = "")
if (F > 0L) quit(status = 1L)
