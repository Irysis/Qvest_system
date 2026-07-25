# L-code ID 충돌 판정표 (2026-07-25)

**출처**: `lcode_harvester.py` 재실행 시 `REASSIGN_ID 대상 검토` WARN 5건.
**전제**: harvester는 충돌 시 **양쪽 레코드를 모두 적재**한다(dedup 키 = 절대경로). 따라서 **내용 손실은 없고**, 문제는 ID로 조회할 때 어느 기록인지 모호해지는 것.
**실측**: corpus 416항목 / 고유 ID 410. **중복 ID 5개, 여분 레코드 6건**(L-601이 3-way라 이벤트 2회).
⚠ 두 숫자는 다른 것을 센다 — harvester `n_id_collisions`(=6)는 *충돌 이벤트 수*(= 여분 레코드), `duplicate_ids`(=5)는 *중복된 ID 개수*. 코드 확인: `lcode_harvester.py:483` 루프에서 이미 본 ID를 만날 때마다 +1이므로 3-way는 2 증가. 다이제스트 문구에 둘을 병기하도록 수정 완료.
**제약**: 하드 리넘버 금지([[reference-code-identity-stability]]) — 기존 ID 보존이 기본값. 아래 "신규 발급"은 리넘버가 아니라 **미발급 번호를 새로 주는 것**이라 blast 없음.

---

## 갈래 A — 교차전략 충돌 (서로 다른 전략이 같은 번호): 신규 ID 발급 필요

| ID | 레코드 | 전략 | 등급 | 요지 |
|---|---|---|---|---|
| **L-601** | ①전략트리 | STR_1423_volvol_quality_s5_m2 | B | Aggressive DD brake(5/15, min_exp 0.35) on D01+Q07 — stress 3/3, MDD 26.5% |
| | ②전략트리 | STR_1571_bayesian_bl_c11fix | A | Bayesian Black-Litterman 5-sleeve 앙상블 + C11 FRED t-1 fix |
| | ③전략트리 | STR_1614_roic_skewness_defense | F | Q17_ROIC + D43_Skewness EW 블렌드 MDD 59.7% hard fail |
| **L-602** | ①전략트리 | STR_1423_volvol_quality_s5_m3 | B | Baltussen(2018) vol-of-vol + Dichev-Tang(2009) earnings stability 결합 |
| | ②전략트리 | STR_1615_accrual_vol_cashconv | F | AC22 + Q28 EW 블렌드 MDD 64.8% hard fail, Score 49.2 |

**권고**: 각 ID의 **최초 기록 1건만 번호 유지**, 나머지는 미발급 번호로 신규 발급. 어느 것을 최초로 볼지는 mtime이 동률(전부 2026-06-08)이라 **전략 번호 오름차순**(STR_1423 → 유지)을 제안. 총 3건 재발급 필요(L-601 2건, L-602 1건).

## 갈래 B — 동일 전략·다른 내용 (루트 사본 vs 전략트리 사본): 병합 판정

| ID | 위치 | 전략 | 내용 차이 |
|---|---|---|---|
| **L-160** | 루트 (06-08 00:14) | STR_1683 | *신호 품질* 관점 — IC 0.2207 / ICIR 1.879 / FM t=16.887 극강 |
| | 전략트리 (06-08 06:09) | STR_1683 | *포트 전이 실패* 관점 — 4-variant sweep 전수 hard fail, MDD 70~95% |
| **L-166** | 루트 (06-08 00:14) | (strategy_id 없음) | ANTI_pattern 스텁 — **gist 비어 있음** |
| | 전략트리 (06-08 06:08) | STR_1687 | AX-005 EXCLUSION 3개 검증 기록(실내용) |

**권고**: 같은 실험의 두 측면이라 **번호는 하나로 유지하고 내용 병합**이 자연스러움. L-160은 두 기록이 상보적(신호는 강한데 포트 전이가 실패 = `signal_portfolio_translation_failure` family와 정확히 일치)이라 병합 시 오히려 서사가 완성됨. L-166 루트 사본은 내용이 비어 있어 폐기 후보.

## 갈래 C — 순수 중복 (같은 전략·같은 내용, 파일명만 다름): 자동 dedupe 가능

| ID | 파일 | 비고 |
|---|---|---|
| **L-789** | `STR_1563_.../stage_artifacts/l_code.json` | STR_943 C9+C11 fix, SR 1.312→0.988 |
| | `STR_1563_.../stage_artifacts/l_code_STR_1563.json` | 동일 내용(한글/영문 서술 차이만) |

**권고**: 한쪽 파일만 남기면 해소. 판정 부담 없음.

---

## 조치 요약

| 갈래 | 건수 | 조치 | 승인 필요 |
|---|---|---|---|
| A 교차전략 | ID 2개(레코드 3건 재발급) | 미발급 번호 신규 발급 | ✅ 도훈 |
| B 동일전략·다른내용 | ID 2개 | 내용 병합 (L-166 루트 스텁은 폐기) | ✅ 도훈 |
| C 순수 중복 | ID 1개 | 파일 1개 정리 | 판정 부담 없음 |

**감지 배선(완료)**: `weekly_cleaner_sweep.R` `axiom_candidates_summary`에 `lcode_integrity` 추가 — 중복 존재 시 콘솔 WARN + pending JSON + 텔레그램 섹션으로 표면화. 종전에는 harvester stderr WARN만이라 매주 찍히고도 도달 0이었음.

**자동 분류기(완료)**: 위 3갈래를 결정적 규칙으로 판정해 다이제스트에 실음 — `strategy_id` 2종 이상 → `cross_strategy` / 같은 전략·같은 디렉토리 → `same_dir_duplicate` / 같은 전략·다른 디렉토리 → `cross_zone_variant`. **수동 판정 5/5 재현 검증 완료**(A 2 · B 2 · C 1). ID를 자동으로 바꾸지는 않음 — 조치 *종류*만 판정해 반복 분류 노동을 제거.

**텔레그램 도달 사전검증(완료)**: `tg_agent_brief(dry_run=TRUE)`로 실제 렌더링 확인 — ok=TRUE, 728바이트, 4-bullet 정상 출력. ⚠ 표시 아티팩트 1건: 자동 용어풀이가 목록 첫 ID에 붙어 `L-160 (교훈), L-166, ...`로 렌더됨(내용 오류 아님, 비전공자 3장치 설계 동작).

---

## 소비면 참조 실측 (별도 세션 추가, 2026-07-25)

> 위 A/B/C 분류는 **레코드 속성**(전략 동일성·디렉토리)으로 갈랐다. 아래는 **조치 안전성**을 가르는 축 —
> "그 ID를 실제로 인용하는 소비자가 있는가". 두 축이 독립이라 병기해야 조치 판단이 선다.

`06_Registry/` · `qepm/memory/` · `02_Infrastructure/docs/` · `00_Lawbook/` 전수 grep:

| ID | 갈래 | 인용 소비자 | 재발급 안전성 |
|---|---|---|---|
| L-601 / L-602 / L-789 | A · C | **없음** (`knowledge_index`만 = 자기 파생물) | **안전** — 끊길 인용이 없음 |
| L-160 / L-166 | B | `distilled_knowledge` · `hypothesis_index` · `axiom_recert_queue_20260704` · `knowledge_recheck_queue` | **불가** — 인용 파손 |

★**전례 증거**: `knowledge_recheck_queue.json`에 `DIST-QPM-001` 항목으로
**"L-160 ID 재발급 오링크 — DIST-QPM-005가 정정본"**(2026-07-04)이 **미해결로 남아 있다**.
즉 갈래 B 대상에 대한 ID 재발급은 *과거에 이미 오링크를 만든 전례*가 있다.

**함의 (위 권고와 정합)**: 갈래 A의 "신규 발급" 권고가 성립하는 이유는 분류가 아니라 **소비자 0**이고,
갈래 B의 "병합" 권고가 필수인 이유는 상보성뿐 아니라 **인용 파손 + 재발급 실패 전례**다.
- 갈래 A 착수 시 **소비자 0을 재확인한 뒤** 발급할 것 (본 측정 이후 인용이 생겼을 수 있음).
- 갈래 B(L-160) 병합은 **DIST-QPM-001 오링크 해소와 함께** 처리해야 같은 실패가 반복되지 않는다.

**무재번호 완화(배선 완료)**: `build_knowledge_index.R`가 `id_collision_with` · `source_file`을 코퍼스 행에
전달하도록 수정 — 종전에는 인덱스가 두 필드를 버려 소비면에서 충돌 자체를 볼 수 없었다(이것이 위 오링크의
발생 경로). 현재 **416/416 행이 `source_file` 보유**, 충돌 행 표시됨 → **승인 전에도 소비면이 분기 가능**.
