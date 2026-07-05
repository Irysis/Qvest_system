# DART Insider 역사 백필 — document.xml 원문파서 빌드

**목적**: DART insider(임원ㆍ주요주주 특정증권등 소유상황) 신호를 2005~2024 역사 백필.
elestock.json API 가 rolling ~23개월만 제공하는 한계를 **document.xml 원문 직접 파싱**으로 우회.
비-수익 정보원 = KR post-2017 수익-감쇠벽과 무관한 유일 직교 새 정보(W3: score_eff cor −0.016·IC t3.3~4.9).

**격리**: 모든 산출 `stage_artifacts/dart_parser_build/` 내. 기존 `02_Infrastructure` 파일 무수정.

## 구성

```
code/
  dart_document_parser.py    # 원문파서: document.xml ZIP→XML→ACODE/AUNIT 추출. form v2.8~4.1 robust.
  dart_backfill_pipeline.py  # 파이프라인: list.json → document.xml fetch → parse → 월별 parquet. resumable·budget-guard.
  parity_check.py            # 파리티: 파서 vs elestock 24m 대조.
  consolidate_netbuy.py      # 통합: 월별 체크포인트 → net-buy 신호 패널(PIT lag).
cache/monthly/               # 월별 체크포인트(resumable). {YYYYMM}.parquet.
data/                        # insider_netbuy_monthly.parquet (통합 신호 패널).
reports/                     # PARITY_VERDICT.md, parity_report.json, netbuy_panel_meta.json.
```

## 접근 (final report §1)

- **DART OpenAPI key**: `.env` 의 `DART_API_KEY` (40자, 유효). rate 일 10,000 call.
- **엔드포인트**: `list.json`(pblntf_ty="D" 지분공시 목록) + `document.xml`(rcept_no 원문 ZIP).
- **universe**: `.cache/dart/universe_corpcodes.csv` (348 corp_code, K200∪KQ150).

## 실행

```bash
source .venv_qvest_ml/Scripts/activate   # (Windows venv)

# 역사 백필 (resumable — 완료 월 skip). ~62k call 총량 → 6500/run 기준 ~10 run(days).
MODE=backfill BF_START=2005-01 BF_END=2024-02 DART_DAILY_BUDGET=6500 \
  python -u stage_artifacts/dart_parser_build/code/dart_backfill_pipeline.py

# 파리티 재확인
python stage_artifacts/dart_parser_build/code/parity_check.py

# 신호 패널 통합 (백필 진행 중에도 부분 통합 가능)
python stage_artifacts/dart_parser_build/code/consolidate_netbuy.py
```

## PIT 규율

- **signal date = rcept_dt (공시 접수일)** — 시장은 접수 시점 인지. MDF_DM(변동일자)은 정보용만
  (late-filing 존재: 2009 거래를 2010 접수한 사례 실측).
- consolidate: `usable_month = sig_month + 1` (t-1 lag, 보수적 PIT).
- 자체합성 백테스트 없음 — 순수 신호 패널만 산출. alpha/forge 가 build_bt_result 로 소비.

## 파리티 결과 (reports/PARITY_VERDICT.md)

net_change_qty **100% 일치**(256/256), ticker-month net qty **상관 1.0000**. 파서 검증 완료.

## 한계

- reporter-type(officer vs 10%주주) 분류: 2010+(v3.1+) 완전. 2005~06(v2.8)은 필드 sparse → net-buy
  신호는 무결하나 임원-only 필터는 2010+ 신뢰. 레코드에 플래그 마킹.
