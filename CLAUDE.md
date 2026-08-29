# Quant Module Moltbot — Claude Code Instructions

## Active Version

**Qvest v9.21 — 논문 알파리서치 → 강화 프로세스 · 등급 일원화(essence 단일) · 게이트 2층** (세션 모델 정본 `claude-fable-5`. 2026-08-24 도훈 지시 6건 — ①강화 목표 등급 B→A ②등급체계 1개로 ③팩터 로테이션→전략 로테이션 개명 ④QEPM = A등급 이상 심층리서치로 재배치 ⑤기본 단계 = 논문 알파리서치 → 강화 ⑥RAMP 모드 퇴임(Track1 흡수) + 후속 지시 "MDD 탈락은 빼줘 — hard_fail 조건에서 MDD만 걷어내면 되는거 아냐?". 플랜 `~/.claude/plans/bright-dancing-snowflake.md`. 등록 훅 12 · 배터리 182 스위트. 직전 판 = v9.2/v9.0 Lean Loop(2026-08-23). 롤백 태그 `pre-v9-lean-loop`)

> **★버전·모델 표기 단일 출처**: 위 줄이 유일한 정본이다(`boot_currency_check.sh` C0가 여기서 파생해 배너·상태라인 C1~C3를 대조). 다른 문서·룰은 재기입하지 말고 "정본 = 본 절"로 위임할 것.

**★ Active SOT**: `.claude/rules/lean-loop.md`(v9 루프 정본) · `02_Infrastructure/docs/qvest_v8_4_asymmetry_ml_sot.md`(리서치 방향) · `02_Infrastructure/docs/CHANGELOG_constitution.md`(계보 + v8.4 헌법 전문 아카이브)

---

## 존재의의 — 이 시스템은 알파시킹 기계다

프로세스·하네스·게이트는 알파 발굴을 **신뢰할 수 있게 만드는 수단**이지 목적이 아니다. 세션 자원의 기본값은 **라운드 전진**이고, 인프라 작업은 ①라운드를 실제로 막는 결함 ②측정 신뢰를 훼손하는 결함(PIT·proxy·침묵 실패)에만 쓴다. 사이클이 생기면 "인프라를 더 다듬을까"가 아니라 **"다음 가설이 무엇인가"**를 먼저 묻는다.

- **제1목표**: 미래참조 없는 전략 설계(PIT 완전 준수) — 성과보다 우선.
- **제2목표(= 자본 계층 목표)**: SR 2.5+ / CAGR 16%+ / MDD <25%. **리서치 층의 통과 기준이 아니다** — 리서치 층은 **권위 등급**(`essence_score.R`)으로 판정한다. ★이 줄의 `MDD <25%`는 **목표 서술이지 게이트가 아니다** — 게이트에서는 Calmar 비율(=16%/25%=0.64)로만 걸린다(아래 「등급」 절).

---

## Session Startup

`/qvest` — 부팅 5줄(상태만; 수리·테스트·백그라운드 0) 후 `Queue:` 상단 1건으로 **즉시 lean loop 1단계**. WARN은 보고 대상이지 그 세션의 과제가 아니다.

## Lean Loop (6단계)

1. **읽기** — 논문/가설 1건에서 신호 정의·비중 방법·유니버스·리밸 주기·저자 주장 성과.
2. **구현** — 논문 명시값 복제, 미명시분만 고정 축으로. 하드 게이트 = `detect_lookahead`.
3. **실행** — `run_alpha_search(name, idea, engine, n_holdings=<논문>, weight_method="<논문>")` (`deep=FALSE` 기본).
4. **판정** — **권위 등급**(`authoritative_remeasure.json::essence_grade`) 값만 인용. 손계산·재구성 금지. Grade A = PORT_t ≥2.95 ∧ OOS retention ∧ SR ≥0.8 ∧ CAGR ≥16% ∧ Calmar ≥0.64. `hurdle_result.json` 등급은 **진단(proxy)**이며 판정 근거가 아니다.
5. **교훈** — 의미있는 실패(기전이 특정되는 실패)만 L-code 적립.
6. **다음** — 큐 다음 항목. 보고는 3줄.

★4단계 뒤 **기본 2단계(강화 프로세스)**가 붙는다 — 세션이 수동으로 부르는 것이 아니라 무인 러너 뒤에 자동으로 돈다(아래 「파이프라인」).

**절차 정본 = `.claude/rules/lean-loop.md`**(autoload) — 예산 ≤40분·≤120K 토큰·하네스 쓰기 0 / 연속성 계약 1지점 / 하지 않는 것 목록.

---

## Production Constraints

<!-- FRONTIER_AXES_START — 기계 앵커. axiom_context_inject.sh · gap_vector_steering.R 이 이 구간을 런타임 파싱한다(캐시 없음 = 여기를 고치면 다음 spawn 부터 반영). -->
> **★고정 축은 배포 현실이 정의한 문제의 정의다 — 최적화로 없앨 변수가 아니다.** AX-000 따름정리: 제약 완화(>25종·short·유동성 하향)를 레버로 제시하는 것은 게임을 이기는 게 아니라 바꾸는 것이다(INV-7). 조건-안 레버만 프론티어 — 현행(v9.0): ① **비대칭 표적**(분포-표적 학습 · 일별 축 정보 회수 · 수리통계 구조 추정 — 주력) ② screen-tier 재고 회수(overlay 큐) ③ EW-대비/cap-tier 재분류 ④ overlay 잔여·잔차 sleeve·multi-sleeve·composite.
> 과거 실측 negative 는 `Rscript 02_Infrastructure/tools/hypothesis_index.R lookup <kw>` 로 조회한다 — 사실 기록이지 금지 목록이 아니다. 재시도는 새 각도·새 통제·새 표적일 때 정당하다(AX-000). 철회되는 것은 금지이지 측정 규율이 아니다: 어떤 축이든 `verify_adapter`·sweep/DSR·book-marginal ΔIR≥0.05·PIT 를 통과해야 한다.
⚠**①이 과거 ML 실패의 부활이 아님을 구분할 것**: 과거 negative 는 ML 을 **결합기·사이징·평균 예측기**로 쓴 구성에서 나왔고, ①은 표적을 분포로 바꾸는 미측정 축이다.
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

## 등급 — 하나뿐이다 (v9.21, 도훈 지시 "여러개면 헷갈린다")

**권위 등급 = `02_Infrastructure/contracts/essence_score.R`. enum = A / B / C / F 4값.**
`hurdle_gate.R` 등급은 2026-05-31에 이미 **DEMOTED**(`authoritative=FALSE` · `grade_basis="proxy_diagnostic_18component"`)됐다 — 둘이 병존한 게 아니라 문서가 강등을 안 따라갔던 것이다.

- **lean 라운드도 권위 등급을 항상 산출한다**(v9.21 §1-a). 구판은 proxy 등급이 "권위 등급을 계산할지"를 정하는 **순환 의존**이라 lean에는 권위 등급이 아예 없었다(생존편향 구조 — `docs/qvest_ast_v1_1_sot.md:84` 반증 기록).
- 계약 미경유 = **등급 미발행(NA)**. 사유는 `metric_type="uncertain"`이 보존한다. `"uncertain"`은 등급이 아니다.
- 축 이름: `grade`=권위(essence) · `grade_proxy`=진단(hurdle). 출처는 `grade_basis`가 못박는다.
- ★**MDD는 어느 층에서도 등급을 접지 않는다**(도훈 지시 2026-08-24 "hard_fail 조건에서 MDD만 걷어내면 되는거 아냐?"). 위험 축은 **Calmar 비율 하나**(=CAGR/\|MDD\| ≥ 0.64 = 16%/25%). `hard_fail`은 **외부(judge) 주입 전용**이고, 구조 낙폭은 `structural_drawdown` **라벨**로만 남아 오버레이 라우팅 근거가 된다. 문서 정합 중 MDD 직접 문턱을 되살리지 말 것 — `08_Tests/contracts/test_grade_unification.R` B4~B6이 잡는다.

## 게이트 2층

- **리서치 층(모든 lean 라운드)** = **권위 등급**(essence A/B/C/F) + PIT(`detect_lookahead` 차단). **추가 수치 허들 0.** 사전등록·검정력 계약·무신호 대조·β-통제 α·`DISTRIBUTION_TARGET`은 **선택 도구**이지 부과 의무가 아니다. (`hurdle_gate.R`는 지우지 않는다 — `screen_route` 라우팅 라벨의 생산자다.)
- **자본 층(Grade A 또는 도훈 지명 후)** = 심층 QEPM 6-agent → dossier → **forge-authoritative 수치**로 HARD 4종 판정 → governor. 값 정본 = `02_Infrastructure/worktask/constraint_defaults.json::tier_graduation`이며 **재보정은 도훈 권한**(INV-7 "게이트 완화 제안 금지"는 자본 층 한정). `qepm/mailbox/governor/book_state.json` 쓰기 = **도훈만**(자동화 금지).
- 자본 층 규범 전문 = `.claude/rules/measurement-graduation.md`(경로 트리거 지연 적재).

---

## 파이프라인 (v9.21 — 모드 표를 대체한다)

```
기본 1단계   논문 알파리서치 (lean loop)                    ← 세션 기본값
     ↓
기본 2단계   강화 프로세스 (reinforce_ladder · 무인 러너 뒤 자동)
             ①팩터 컴포지트 → ②비중 방법론 교체 → ③리스크 오버레이
     ↓  (Grade A 또는 도훈 지명)
심층        QEPM 6-agent — A등급 이상 전략의 스펙 강화
     ↓
소비 계층    전략 로테이션 — Track1 레짐엔진 · Track2 모듈 배분
```

**해상도로 가른다**: 강화 프로세스 = intra-strategy(전략 1개의 축 교체) · 전략 로테이션 Track2 = inter-strategy(완성 모듈 배합) · Track1 = 국면 정의/예측(둘의 토대). 순수팩터 추출(PCA/FWL/hclust)은 Track1이 필요할 때 부르는 **도구**이지 별도 모드가 아니다.

| Command | 용도 |
|---|---|
| `/qvest` | 세션 시작 → 부팅 5줄 → lean loop (기본 1단계) |
| `/alpha-search` | 논문 1편 경량 검증 (기본 1단계 레인) |
| `/worktask` | 심층 QEPM 6-agent — **A등급 이상 스펙 강화** |
| `/strategy-rotation <track>` | 소비 계층 — 국면조건부 모듈 배합 |

**강화 프로세스는 전용 command가 없다** — 무인 러너(`alpha_search_queue_run.sh`) 뒤에 자동으로 1후보가 붙는다(도훈 결정 2026-08-24). 수동 기동은 `Rscript 02_Infrastructure/ops/reinforce_ladder.R --top=1`, 정지는 `QVEST_LADDER_NORUN=1`.

★**RAMP는 모드에서 퇴임했다**(도훈 결정 2026-08-24). 선언 산출물(`RAMP_XXXX`·`FG_*`·`MCODE_M0~M4`·Gate 0~11 심사)이 **각 0건**이고, "RAMP" 라벨 아래 실제로 돈 것은 팩터배분 파이프라인이 아니라 **국면 조건부 리서치**(L-code 73건)였다 — 그건 전략 로테이션 Track1이 이미 선언한 일이다. **코드·데이터·L-code 73건은 삭제하지 않는다**(`ramp`는 L-code enum에 역사 라벨로 존치 — 선례 = `qepm_legacy`). 진입점에서만 내린다.

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
- 스킬·에이전트·훅은 **문서로 세지 않는다** — 파일시스템이 정본(`.claude/skills/` · `.claude/agents/` · `02_Infrastructure/hooks/`). 현행 등록 = settings.json **12** distinct .sh (직접 등록만 — 라우터 dispatch 폐지 2026-08-23 v9; 목록 = 02_Infrastructure/hooks/_archive_v8_enforcement/MANIFEST.md). ★2026-08-24 `backtest_contract_audit.sh` 재등록(11→12) — 해제 사유였던 `.py` 자체합성 오탐만 제거. 발화 실증 = `08_Tests/hooks/test_backtest_contract_audit_gate.R` 10축
- 계보·릴리스 상세·**v8.4 헌법 전문 아카이브** = `02_Infrastructure/docs/CHANGELOG_constitution.md`.
