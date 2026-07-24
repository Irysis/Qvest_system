# firm_level_scaffold — FQ-064/065 온보딩 스캐폴드 (data.go.kr 키 랜딩 대기)

**목적**: FQ-064(국민연금 헤드카운트 모멘텀)·FQ-065(나라장터 정부조달 수주 magnitude) firm-level
비-return SELECTION 신호를 data.go.kr 키 발급 **前**에 배관 완성 → 키 랜딩 즉시 **1커맨드** canonical 측정.
**규율**: KR long-only · K200∪KQ150 · top-25 · [0,0.20] · Σw=1 · liq≥2e8 · 15bps · PIT C1~C15 · canonical_screen_bt 계약(자체합성 없음).

## 산출물 (이 디렉토리)

| 파일 | 내용 | 상태 |
|---|---|---|
| `build_crosswalk.R` | bizr_no↔corp_code↔stock_code crosswalk 빌더(DART 15034604) | ✅ 실행완료 |
| `firm_crosswalk.parquet` / `.json` | **474 상장사** crosswalk(bizr_no 474/474, 결측0) | ✅ 실데이터 |
| `crosswalk_coverage.json` | 커버리지 리포트(매칭474/474·bizr_no6 충돌121 경고) | ✅ |
| `factor_stubs.R` / `factor_declarations.json` | 2팩터 선언 스텁(id·방향·PIT·compute경로) | ✅ |
| `run_fq064_headcount.R` | FQ-064 측정 러너(STEP1 pull=placeholder, 2~5 실배선) | ✅ dry-run OK |
| `run_fq065_procurement.R` | FQ-065 측정 러너(동상) | ✅ dry-run OK |
| `PIT_plan.md` | usable_date·vintage 고정·조인 무결성 규약 | ✅ |
| `data_pull/` | 키 랜딩 시 pull 산출 자리(nps_headcount_raw / g2b_awards_raw) | ⏳ 키-대기 |

## crosswalk 실측 요약

- 474 상장사(2023+ K200∪KQ150 univ 합집합), **full bizr_no 474/474·중복0** = firm-unique 정본키.
- corp_cls: Y(KOSPI) 237 · K(KOSDAQ) 225 · E(기타) 12.
- ★**bizr_no6(6자리) 충돌 121건** — 국민연금 6자리 마스킹 공표 시 단독조인 금지(PIT_plan §3).

## one_command (키 랜딩 후)

키 랜딩 → pull 스크립트(`data_pull/`에 raw parquet 생성) → 각 러너 1커맨드:
```bash
bash 02_Infrastructure/ops/safe_run.sh Rscript stage_artifacts/method_frontier/firm_level_scaffold/run_fq064_headcount.R
bash 02_Infrastructure/ops/safe_run.sh Rscript stage_artifacts/method_frontier/firm_level_scaffold/run_fq065_procurement.R
```
→ `fq064_out/fq064_canonical.json` · `fq065_out/fq065_canonical.json`(PORT_t·IR·SR·dual-basis diag).
현재는 raw pull 부재 → 러너가 **dry-run(배관검증)** 후 clean exit(양쪽 확인됨).

## 남은 blockers

1. **★도훈: data.go.kr 무료 서비스키 발급** — 유일한 외생 게이트(FQ-064·065 공통, `access_gate=dohoon_register_datagokr`).
2. pull 스크립트 2종(`pull_nps.R`/`pull_g2b.R`) 미작성 — 키 랜딩 후 작성(엔드포인트·스키마는 러너 STEP1 주석에 명시). **API 스펙 실존 확인 의무**: FQ-065 '낙찰기업 사업자번호' 필드가 실존하는지 pull 前 확인(추측 금지).
3. FQ-065 계열매핑 테이블(`group_map`) — 비상장 자회사→상장모기업 귀속(현 러너는 직접 상장사만=보수적 하한).
4. 국민연금 공표 마스킹 여부 실측(6자리면 disambiguation 필요).
5. backfill depth 미측정 → canonical n_months 범위 랜딩 시 확정.

## EV / 벽 (정직 라벨)

- 두 신호 = firm-level **SELECTION**(수익 병목=선별 계층 직접 작용) → sector-rotation의 EV 상한 회피. hypothesis_index virgin.
- 최종 관문 = **IC→PORT_t top-25 cap-w 전이 벽**(비-return 신호도 이 벽이 판정 — FQ-001 insider 삼각-null 선례). canonical PORT_t 2.95 HARD가 자본 게이트.
- sector-rotation(FQ-066/067)과 달리 SELECTION이라 '기존 대비 증분' 관문 아님 — firm-level 신규 원천.
