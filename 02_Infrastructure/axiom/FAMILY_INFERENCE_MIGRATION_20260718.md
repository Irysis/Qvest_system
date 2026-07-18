# L-code family 추론 substring→word-boundary 수리 + 재분류 마이그레이션

**발효 대상 브랜치**: `claude/nostalgic-wescoff-b89c27` (worktree — **미병합 = 게이트**)
**날짜**: 2026-07-18
**근본원인 출처**: W29 `/cleaner` chip task_07f3ac0e (2026-07-18 일부 선-수리분의 잔여 근본원인)
**연관**: [[project-axiom-cluster-ghost-misclustering-fix]] (cluster_extractor `_polarity` v3 = 하류 증상 수리, 완료). 본 건 = **상류 family 오추론** 수리.

---

## 1. 결함 (근본원인)

`02_Infrastructure/axiom/lcode_harvester.py::_infer_family()` 가 키워드를 **naive substring**
(`kw.lower() in text_lower`) 으로 매치 → 짧은 팩터코드 키워드가 무관 토큰에 오매치:

| 오매치 | 키워드 | 결과 |
|---|---|---|
| `FQ011` (챔피언 캐리어 전략명) ⊃ `q01` | `Q01` | `quality_profitability` 오귀속 |
| `deep`/`step`/`concept`/`repo` ⊃ `ep`/`bp` | `EP`/`BP` | `value` 오귀속 (코퍼스 전반) |
| `2012-11` (날짜) ⊃ `12-1` | `12-1` | `momentum` 오귀속 |
| `GPARSE` ⊃ `gpa` | `GPA` | `quality_profitability` 오귀속 |

**하류 피해 (이미 수리됨)**: 오추론 family가 cluster_extractor 의 `_similarity` family-매치
(+0.4 = 임계 0.35 초과) 로 무관 L-code를 접착 → tag 교집합 ∅·text jaccard ~0.05 인데도 한
CAND/DIST 로 묶임 (DIST-AR-022/016 = 실측 성공 전무한데 'positive' 라벨). DIST 카드는 만료됐고
positive fallthrough 는 `_polarity` v3 로 수리됨. **family 오추론 자체는 미수리 → 재발 지속**이던 것을
본 건에서 상류 수리.

부차 결함: `_infer_family` best-hits 동점 시 dict 순서로 임의 tie-break (override 로 해소).

## 2. 수리 (본 브랜치 코드)

`lcode_harvester.py`:
- **word-boundary 매처** `_kw_pattern`/`_kw_hit`: `(?<![a-z0-9])<kw>(?![a-z0-9])`.
  - ASCII/alnum 키워드는 단어경계로 격리 (artifact 기각).
  - 한글 문맥 문자는 `[a-z0-9]` 아님 → 경계 항상 성립 → **한글 키워드('모멘텀'/'추세'…)는 종전
    substring 의미 유지** (한국어=공백 없는 교착어, substring 이 옳음).
  - 밑줄(`_`)은 alnum 아님 → 팩터코드 구분자 경계 (`Q07_D29` 내 `Q07` 매치 유지).
- **family 결정 4단 우선순위** (harvest): ① explicit `family` 필드 → ② 큐레이션 override
  (`06_Registry/lcode_family_override.json`, 키워드보다 우선) → ③ word-boundary 키워드 →
  ④ distill-plan 폴백. `family_source` 감사 필드 기록.

`lcode_emit.R`: optional `family=` 파라미터 (prefer-explicit emit-side 절반 — 명시 시 harvester ①로 소비).

검증: `"$QVEST_PY" 02_Infrastructure/axiom/test_lcode_harvester_family.py` (26 assert ALL PASS).

## 3. 영향 (실측, MAIN 라이브 코퍼스 대비 read-only)

`harvest(MAIN)` in-memory (쓰기 없음) vs 라이브 `.cache/lcode_corpus.json` (315건):

- **재분류 94/316** (신규 L-code FQ055 1건 포함).
  - `A_explicit_now_honored` 10 — emit이 명시했으나 구 harvester가 무시하던 family (신뢰, override 불필요).
  - `B1_value_substring_artifact_recls` 67 — 구 `value`(대부분 EP/BP artifact) 재분류. **새 라벨 케이스별 확인 필요.**
  - `B2_other_keyword_recls` 9.
  - `C_lost_match_to_unknown` 8 — 유일 매치가 artifact → unknown 강등.
- family_distribution 이동: `value` 89→19, `momentum` 90→98, `unknown` 17→25, `defense` 13→24, `ml_complexity` 10→23, `overlay_regime` 27→40 등.
- **94 중 59가 refined DIST 카드에 기여** (아래 §4).

⚠ 핵심 caveat (task 경고 재확인): B1/B2 의 word-boundary 라벨이 **반드시 옳은 것은 아니다**
(예: `NO_JUDGE_SWEEP → ml_complexity`, FQ011 reval → overlay_regime 은 stretch). = 게이트 리뷰 대상.
→ 이를 위해 Q가 94건 전건 `proposed_family`(내용기반) 사전채움 완료(§5.1): needs_override=true **50건**만
승격 대상, confidence high 42 / medium 39 / low 13.

**예상 최종 분포 (전 proposal 수용 시, in-memory 실측 preview)** — raw word-boundary와 대조:
| family | old(구) | word-boundary raw | 전-proposal 수용 |
|---|---|---|---|
| value | 89 | 19 | **26** (artifact 제거·value-arc 보존) |
| momentum | 90 | 98 | 95 |
| infra_process | 12 | 19 | **32** (catalog/PIT/wiring 정직화) |
| unknown | 17 | 25 | 24 (혼합 blend) |
| quality_earnings | 25 | 18 | 21 |
| overlay_regime | 27 | 40 | 33 |
| ml_complexity | 10 | 23 | 21 |

= 구(artifact 팽창)와 raw word-boundary(과분산) 사이의 내용정합 분포. 이 표가 §5.4 검증 타깃.

## 4. refined DIST 카드 보존 — 실측 blast radius (당초 우려 정정)

**당초 우려("16 refined 카드 orphan")는 과대평가였다 — 실측으로 정정**:

- `build_distilled` 는 **DIST 파일을 삭제하지 않는다** (cluster_key 매치 시 draft 갱신 / 불일치 시 신규 생성만
  — `os.remove` 는 CAND 측 superset-dedup 에만 존재). ∴ **refined `statement_refined`/status 는 regen 을 넘어
  디스크에 보존된다.**
- refined 카드의 cluster_key 재현율은 **현 family 로도 이미 낮다**: 16건 중 OLD 재현 4 / NEW 재현 3
  (재현=현 코퍼스 재클러스터링이 동일 supporting-set 생성). 즉 refined 카드는 설계상 라이브 재클러스터링과
  이미 디커플됨. 본 변경의 순delta = 재현 4→3 (AR-001·QPM-015 재현 상실, AR-008 재현 획득).
- cluster_key churn: NEW-only 39 / OLD-only 25 (파일은 보존, 신규 클러스터가 추가로 형성).

**결론**: gated regen 은 refined 내용에 **비파괴적**. 리스크 = (a) 새 CAND/DIST 가 교정 family 로 재형성되고
(b) 일부 refined 카드가 stale(구 클러스터 지시) 상태로 남는 것 — 지식 손실 아님. 도훈이 원하면 stale refined 를
새 클러스터에 재연결(수동).

## 5. Gated Regen 런북 (도훈/게이트 — 병합 시 1회 감독 실행)

> 전제: 본 브랜치는 **미병합**. MAIN 라이브 시스템은 병합 전까지 구 로직으로 무변경 가동 = 자연 게이트.

1. **리뷰** (Q가 `proposed_family` 사전채움 완료 — 도훈은 confirm/정정만): `06_Registry/lcode_family_override.json`
   `review_queue` 94건 각각 `{old_family, word_boundary_family, proposed_family, confidence, proposal_reason,
   needs_override, feeds_refined_dist}` 보유.
   - **`needs_override=true` 50건만 `overrides`로 승격**하면 됨 (proposed ≠ word-boundary인 항목 = Q가 word-boundary가
     틀렸다고 판단한 케이스). `needs_override=false` 44건은 word-boundary 결과와 일치 = 무조치.
   - `confidence=low` 13건 특히 확인 요망(혼합 blend → `unknown` / non-return forensic → 근사 라벨).
   - 승격 방법: 확정된 항목의 `{l_code: proposed_family}`를 `overrides`에 복사. 정정 시 값만 교체.
   - 진행 통계: `proposal_stats`(applied 84 / missing 0). refined-feeding 59건은 `feeds_refined_dist=true`로 필터.
2. **스냅샷**: `cp -r qepm/memory/axioms/{candidates,distilled} <backup>` + `.cache/lcode_corpus.json` 백업
   (regen 은 비파괴적이나 롤백 안전망).
3. **병합** 후 **1회 regen**:
   `"$QVEST_PY" 02_Infrastructure/axiom/lcode_harvester.py` → `"$QVEST_PY" 02_Infrastructure/axiom/cluster_extractor.py`
   (또는 `/qvest` bootstrap 이 자동 트리거 — 단 감독 하 실행 권장).
4. **검증**: `family_distribution` 이 §3 예측과 일치하는지 · refined 카드 `statement_refined` 전건 온존
   (grep `statement_refined` count 불변) · `distilled_knowledge.json` `n_distilled` 비감소.
5. **stale refined 재연결(선택)**: cluster_key 상실한 refined 카드의 supporting_l_codes 가 새 CAND 클러스터에
   흡수됐으면, 그 새 DIST 로 `statement_refined`/`retry_condition` 이관 (수동, `/cleaner` 규율 — INV-6 무인 정제 금지).

## 6. 후속(범위 밖, 기록)

- `_CONSTRUCTION_KEYWORDS` (construction_type 추론) 도 동일 substring 방식(`" ep"`/`" gp"` 선행 공백으로
  임시 회피 — 작성자가 문제를 인지했던 흔적). 재분류 유발하므로 본 마이그레이션과 분리 — 별도 검토.
- alpha_search 139-megacluster (ubiquitous-tag 연쇄) = 별개 pathology, 도훈 결정 대기 ([[project-axiom-cluster-ghost-misclustering-fix]]).
