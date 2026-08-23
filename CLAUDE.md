# Quant Module Moltbot — Claude Code Instructions

## Active Version

**Qvest v9.0 — Lean Loop · 4-Mode 헌법 · 게이트 2층 · 라운드 우선** (세션 모델 정본 `claude-fable-5`. 2026-08-23 도훈 결정 — 플랜 `~/.claude/plans/qvest-encapsulated-wave.md` 승인 + 결정 4항 선택(①게이트 2층+자본층 재보정 ②Stop 훅 해제→L-code 발행 시점 ③6-agent는 자본층 입구만 ④강한 감산): Stop 차단 훅 0 · 등록 훅 11 · 헌법 ≤8KB · autoload 룰 2종 · 부팅 5줄. 직전 판 = v8.4(2026-08-13 비대칭 알파 재편). 롤백 태그 `pre-v9-lean-loop`)

> **★버전·모델 표기 단일 출처**: 위 줄이 유일한 정본이다(`boot_currency_check.sh` C0가 여기서 파생해 배너·상태라인 C1~C3를 대조). 다른 문서·룰은 재기입하지 말고 "정본 = 본 절"로 위임할 것.

**★ Active SOT**: `.claude/rules/lean-loop.md`(v9 루프 정본) · `02_Infrastructure/docs/qvest_v8_4_asymmetry_ml_sot.md`(리서치 방향) · `02_Infrastructure/docs/CHANGELOG_constitution.md`(계보 + v8.4 헌법 전문 아카이브)

---

## 존재의의 — 이 시스템은 알파시킹 기계다

프로세스·하네스·게이트는 알파 발굴을 **신뢰할 수 있게 만드는 수단**이지 목적이 아니다. 세션 자원의 기본값은 **라운드 전진**이고, 인프라 작업은 ①라운드를 실제로 막는 결함 ②측정 신뢰를 훼손하는 결함(PIT·proxy·침묵 실패)에만 쓴다. 사이클이 생기면 "인프라를 더 다듬을까"가 아니라 **"다음 가설이 무엇인가"**를 먼저 묻는다.

- **제1목표**: 미래참조 없는 전략 설계(PIT 완전 준수) — 성과보다 우선.
- **제2목표(= 자본 계층 목표)**: SR 2.5+ / CAGR 16%+ / MDD <25%. **리서치 층의 통과 기준이 아니다** — 리서치 층은 `hurdle_gate.R` 등급으로 판정한다.

---

## Session Startup

`/qvest` — 부팅 5줄(상태만; 수리·테스트·백그라운드 0) 후 `Queue:` 상단 1건으로 **즉시 lean loop 1단계**. WARN은 보고 대상이지 그 세션의 과제가 아니다.

## Lean Loop (6단계)

1. **읽기** — 논문/가설 1건에서 신호 정의·비중 방법·유니버스·리밸 주기·저자 주장 성과.
2. **구현** — 논문 명시값 복제, 미명시분만 고정 축으로. 하드 게이트 = `detect_lookahead`.
3. **실행** — `run_alpha_search(name, idea, engine, n_holdings=<논문>, weight_method="<논문>")` (`deep=FALSE` 기본).
4. **판정** — `hurdle_result.json` 값만 인용. Grade A = CAGR ≥16% ∧ SR ≥0.8 ∧ score ≥40 ∧ hard_fail 없음.
5. **교훈** — 의미있는 실패(기전이 특정되는 실패)만 L-code 적립.
6. **다음** — 큐 다음 항목. 보고는 3줄.

**절차 정본 = `.claude/rules/lean-loop.md`**(autoload) — 예산 ≤40분·≤120K 토큰·하네스 쓰기 0 / 연속성 계약 1지점 / 하지 않는 것 목록.

---

## Production Constraints

<!-- FRONTIER_AXES_START — 기계 앵커. axiom_context_inject.sh · gap_vector_steering.R 이 이 구간을 런타임 파싱한다(캐시 없음 = 여기를 고치면 다음 spawn 부터 반영). -->
> **★고정 축은 배포 현실이 정의한 문제의 정의다 — 최적화로 없앨 변수가 아니다.** AX-000 따름정리: 제약 완화(>25종·short·유동성 하향)를 레버로 제시하는 것은 게임을 이기는 게 아니라 바꾸는 것이다(INV-7). 조건-안 레버만 프론티어 — 현행(v9.0): ① **비대칭 표적**(분포-표적 학습 · 일별 축 정보 회수 · 수리통계 구조 추정 — 주력) ② screen-tier 재고 회수(overlay 큐) ③ EW-대비/cap-tier 재분류 ④ overlay 잔여·잔차 sleeve·multi-sleeve·composite. DPL(06-26)·regime-conditional 교차결합(07-05)·ML/uncertainty sizing(07-05 2세션)은 settled-negative — 레버 아님(부활신호 발화 시에만 재검토).
⚠**①이 과거 ML 실패의 부활이 아님을 구분할 것**: 죽은 것은 ML 을 **결합기·사이징·평균 예측기**로 쓴 경로이고, ①은 표적 자체를 분포로 바꾸는 미측정 축이다.
<!-- FRONTIER_AXES_END -->

| 제약 | 값 |
|---|---|
| 종목수 | max 25 |
| 유동성 | 20일 평균 거래대금 ≥ 2e8 KRW (LIQ_THRESHOLD) |
| Long-only | weights ≥ 0 |
| Weight bounds | [0, 0.20] · Σw = 1 (absolute) |
| Universe | KOSPI200 ∪ KOSDAQ150 |
| 기간 · 비용 | 2005-01-01~ · 15bps one-way (v2.4_kr_retail_15bps, delta-based) |
| PIT | C1~C15 전체 (`.claude/rules/pit.md`) |

---

## 게이트 2층

- **리서치 층(모든 lean 라운드)** = `hurdle_gate.R` 등급(A/B/C/F) + PIT(`detect_lookahead` 차단). **추가 수치 허들 0.** 사전등록·검정력 계약·무신호 대조·β-통제 α·`DISTRIBUTION_TARGET`은 **선택 도구**이지 부과 의무가 아니다.
- **자본 층(Grade A 또는 도훈 지명 후)** = `/worktask` → 6-agent → dossier → **forge-authoritative 수치**로 HARD 3종 판정 → governor. 값 정본 = `02_Infrastructure/worktask/constraint_defaults.json::tier_graduation`이며 **재보정은 도훈 권한**(INV-7 "게이트 완화 제안 금지"는 자본 층 한정). `qepm/mailbox/governor/book_state.json` 쓰기 = **도훈만**(자동화 금지).
- 자본 층 규범 전문 = `.claude/rules/measurement-graduation.md`(경로 트리거 지연 적재).

---

## 모드 / 진입점

| Command | 용도 |
|---|---|
| `/qvest` | 세션 시작 → 부팅 5줄 → lean loop |
| `/alpha-search` | ② alpha-search — 논문 1편 경량 검증 (기본 레인) |
| `/worktask` | ① QEPM 6-agent — **자본 층 입구** |
| `/factor-rotation <track>` | ③ 국면조건부 모듈 배합 (모듈 소비) |
| `/ramp <stage>` | ④ K-RAMP 팩터배분 (전략풀 소비) |

## 절대 규칙

- **PIT C1~C15** = `.claude/rules/pit.md`. 위반은 계층 무관 절대 기각.
- `05_Production/` **NEVER modify**(`promote_to_production()`만 예외) · `01_Literature/` read-only.
- 모든 산출물은 `04_Research/` 와 `06_Registry/` 에만 쓴다.
- 텔레그램은 `tg_agent_brief()` 단일 진입점 (직접 호출 차단).

## Key Paths · 실행 · 톤

- Root `C:/Users/99922/OneDrive/Quant_Module_Moltbot/` (Git Bash `/c/Users/99922/OneDrive/Quant_Module_Moltbot`) · 인프라 `02_Infrastructure/` · 전략 `04_Research/strategies/STR_*/` · WT `qepm/mailbox/worktask/{WT_ID}/` · 산출물 `stage_artifacts/`
- Env(User scope 영구): `QM_ROOT` + `QVEST_PY` + `~/.Renviron` 동일값 (경로 이전 시 이 3곳 + config.R 후보만 갱신). Memory: `C:/Users/99922/.claude/projects/C--Users-99922-OneDrive-Quant-Module-Moltbot/memory/MEMORY.md`
- R 실행: 전략 디렉터리로 `cd` 후 `Rscript -e 'source("run_all.R")'` (한글 경로 인코딩 회피 — `--file=` 금지).
- **R + Python 공히 1급**(Python venv `.venv_qvest_ml`). 언어 선택은 도구적이며 PIT·계약·고정 축을 면제하지 않는다.
- 톤: 한국어 존댓말. User = Dohoon Kim(도훈), 나를 "Q"라 부른다.

## 포인터

- 룰 = autoload 2종(`pit.md` · `lean-loop.md`). 같은 폴더의 나머지 4종(`axioms` · `backtest-contract` · `measurement-graduation` · `python-policy`)은 `paths:` 프론트매터로 경로 트리거 지연 적재. 확장 룰은 `02_Infrastructure/docs/rules/`에서 해당 작업 시 Read(`answer-principles` 포함).
- 스킬·에이전트·훅은 **문서로 세지 않는다** — 파일시스템이 정본(`.claude/skills/` · `.claude/agents/` · `02_Infrastructure/hooks/`). 현행 등록 = settings.json 11 distinct .sh (직접 등록만 — 라우터 dispatch 폐지 2026-08-23 v9; 목록 = 02_Infrastructure/hooks/_archive_v8_enforcement/MANIFEST.md)
- 계보·릴리스 상세·**v8.4 헌법 전문 아카이브** = `02_Infrastructure/docs/CHANGELOG_constitution.md`.
