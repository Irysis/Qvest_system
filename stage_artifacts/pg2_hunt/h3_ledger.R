## h3 — 이관 2건 원장 기입 + x1 통제 결과 등재
suppressPackageStartupMessages({ library(jsonlite); library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
say <- function(fmt, ...) { cat(sprintf(paste0("[h3] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/ops/frontier_queue_io.R")

Q <- read_frontier_queue(); ids <- vapply(Q$entries, function(e) as.character(e$id)[1], "")
n0 <- length(Q$entries)

## ── ① FQ-163 정정 (병렬 세션 이관 · 내 실측으로 교차 확인) ────────────────────
i <- which(ids == "FQ-163")
if (length(i) == 1L) {
  Q$entries[[i]]$next_action <- paste0(as.character(Q$entries[[i]]$next_action)[1],
    " ★정정(2026-08-09 Q-Lead session 832fa2fc · 병렬 세션 WT-D20260809_005 이관 요청 + **내 331 전수 실측 교차확인**): ",
    "'C15 300개월 실림' 진술은 실측과 불일치한다. 팩터DB 적격 331 목록에도 `coverage.csv` 에도 ",
    "**C15 로 시작하는 팩터가 한 건도 없다**. `compute_consensus.R:125` 가 C15 를 이력 블록으로 언급하나 ",
    "배출 결과가 없다(병렬 세션 진술 `not_emitted_zero_variance` 와 정합). ",
    "⇒ C15 기반 서술은 근거 없음. 재사용 전 배출 여부부터 확인할 것.")
  say("① FQ-163 정정 기입")
} else say("① ★FQ-163 미발견 — 건너뜀")

## ── ② 중복 배출 + 2026 배출 중단 (신규 등재) ─────────────────────────────────
nums <- suppressWarnings(as.integer(sub("^FQ-", "", ids[grepl("^FQ-\\d+$", ids)])))
nx <- max(nums, na.rm=TRUE)
mk <- function(id, title, ev, wall, na, cs, rc) list(
  id=id, title=title, status="frontier_open", owner="Q-Lead session 832fa2fc",
  claim=list(state="complete", session="832fa2fc", note="병렬 세션 이관 + 교차확인 2026-08-09"),
  ev_rationale=ev, wall_check=wall, next_action=na,
  consumer_surfaces=cs, revival_condition=rc, created="2026-08-09")

E <- list()
E[[1]] <- mk(sprintf("FQ-%03d", nx+1L),
  "★C10⊂C01 · C13⊂C04 완전 중복 배출 + 2026-01 이후 배출 중단",
  paste0("병렬 세션(WT-D20260809_005/FQ-198, alpha-hypothesis)이 compute_consensus.R 의 중복 배출을 ",
    "Q-Lead 이관. 원장 쓰기 권한이 내 쪽이라 처리하되 **그 진술을 받지 않고 331 전수로 교차 확인**했다."),
  paste0("★실측: `C01_SUE` vs `C10_SUE_Persistence` — 교집합 66,543행에서 **Pearson·Spearman 둘 다 1.000000 · ",
    "identical TRUE · 최대절대차 0.000e+00**. `C04_ESBR` vs `C13_Revision_Breadth_3m` 동일(교집합 73,282행). ",
    "★포함관계: **C10 단독 0행 / C01 단독 1,748행** · **C13 단독 0행 / C04 단독 1,910행** ⇒ C10⊂C01, C13⊂C04 진부분집합. ",
    "★부수 결함: 차이 나는 6개월이 전부 **2026-01~06 이고 그 달 C10/C13 종목수가 0** — 2026 들어 배출이 끊겼다. ",
    "★Pearson 만 보지 않았다 — 같은 날 insider 패널에서 이상치 하나가 Pearson 을 1.0 으로 만든 전례가 있어 Spearman 병행. ",
    "★내 자가 검거: h2 스크립트 자동 판정이 '단순 차단 시 정보 손실 가능' 이라 했는데 **방향이 반대**다 — ",
    "C10 만 있는 달이 0 이므로 지워도 잃을 것이 없다."),
  paste0("★next_probe(3) = ①`compute_consensus.R` 배출 차단/deprecated 처분 — factor_db **생산 변경**이므로 ",
    "도훈 판단 대상(칩 분리 권고). C10⊂C01 이므로 차단 시 정보 손실 없음이 실측으로 확인됨. ",
    "②**2026-01 이후 C10/C13 배출 중단의 원인 규명** — 중복 처분과 별개 결함이다(이력 블록 `.cons_history()` 의존). ",
    "③중복 전수 재산출 — 종합이 추정한 유효 독립 295~307 을 실제 z 벡터 identical 검사로 확정(오늘은 근접 30건만 봤다)."),
  c("factor_db 배출", "유효 독립 재료 수 계산", "합성/composite 설계", "factor_registry 위생"),
  "compute_consensus.R 이 수정되거나 C10/C13 배출이 재개되면 재확인")

E[[2]] <- mk(sprintf("FQ-%03d", nx+2L),
  "★★계약 슬리브의 직교성은 유니버스가 아니라 **신호**에서 온다 (통제 통과) + IR 2성분 분해",
  paste0("계약 슬리브(rho 0.140 · IR 0.758)가 331 전수에서 유일하게 통과 셀에 있었는데, ",
    "패널이 130종목뿐이라 **좁은 유니버스 아티팩트**일 가능성이 미검이었다. 결정적 통제."),
  paste0("★3-arm 실측(각 무작위 100회, parked arm): ",
    "A 계약신호 rho **+0.140** · IR **+0.758** / ",
    "B 계약유니버스 무작위 rho +0.273 [0.237, 0.318] · IR +0.062 / ",
    "C 전체유니버스 무작위 rho +0.277 [0.203, 0.331] · IR **-0.289**. ",
    "①**B ≈ C** ⇒ 좁은 유니버스는 직교성을 만들지 않는다. ",
    "②A(0.140) 가 B 의 5% 분위(0.237) **밖** ⇒ 직교성은 **신호**가 만든다. ",
    "③uncond 에서는 A 0.564 ≈ B 0.581 ≈ C 0.558 로 셋이 같다 ⇒ **파킹과 결합했을 때만** 신호가 상관을 낮춘다. ",
    "★★IR 2성분 분해: 전체무작위 -0.289 → 계약유니버스무작위 +0.062 (**유니버스 효과 +0.351**) ",
    "→ 계약신호 +0.758 (**신호 효과 +0.696**). 즉 '계약 공시를 낸 회사' 라는 선별 자체에 정보가 있다."),
  paste0("★next_probe(3) = ①**유니버스 필터 소비면** — '계약 공시 발생 종목' 을 신호 없이 유니버스 제약으로만 ",
    "쓰면 IR +0.351 을 얻는다. 이건 슬리브가 아니라 **북 종목 필터**로 소비 가능하다(오늘 확립: 소비 경로가 판정을 바꾼다). ",
    "②**파킹 상호작용 규명** — uncond 에서 A≈B≈C 인데 parked 에서만 A 가 갈린다. 신호가 국면 ON 월에서만 ",
    "직교 정보를 갖는다는 뜻인가, 아니면 파킹이 신호의 어떤 성분을 남기는가. ON 월만의 rho 를 직접 산출. ",
    "③insider 대조 재해석 — insider 도 사건-구동인데 파킹 후 rho 0.291(무작위 0.273 과 구분 안 됨)이었다. ",
    "즉 **사건-구동만으로는 부족**하고 계약 특유의 무언가가 있다. 두 원천의 차이를 직접 분해."),
  c("유니버스 필터(북 종목 제약)", "오버레이 국면 입력", "book-marginal 후보", "비-return 원천 평가 기준"),
  "계약 신호의 국면 ON 월이 누적되거나, 같은 3-arm 통제를 통과하는 다른 원천이 나오면 확장")

for (e in E) Q$entries[[length(Q$entries)+1L]] <- e
Q$updated <- "2026-08-09"; write_frontier_queue(Q)
Q2 <- read_frontier_queue()
say("원장 %d → %d (신규 %d · 순수추가 %s)", n0, length(Q2$entries), length(E),
    length(Q2$entries) == n0 + length(E))
for (e in E) say("  등재 %s — %s", e$id, substr(e$title, 1, 54))
say("=== h3 완료 ===")
