import json

with open('06_Registry/alpha_frontier_queue.json', 'r', encoding='utf-8') as f:
    fq = json.load(f)

entries = fq['entries']
now = '2026-08-04'

new_entries = [
    {
        "id": "FQ-147",
        "lane": "alpha_search",
        "title": "FX_Hedging_Proxy (파생상품/총자산) — proxy 한계로 config_scoped_negative",
        "hypothesis": "DART 파생상품 보유액/총자산을 FX 헤징 공시 대용으로 사용. 논문 원형(AWARE-FX 2607.27611) proxy 구현.",
        "status": "config_scoped_negative_20260804",
        "result": "Grade F. STR_AS_20260804_074545_39272. IC=-0.0078(음수), PORT_t=-0.258(p=0.797 비유의), MDD 59.01%, CAGR 0.92%, Calmar 0.016. metric_type=backtested. 파생상품 보유액은 FX 헤징 목적이 아닌 규모 측정 — 금리/원자재 헤징 합산으로 FX 노출 감소와 연계 약화. IC 음수 = 방향 역전 가능성.",
        "mechanism": "DART 사업보고서 전문 텍스트 파이프라인 미구축으로 논문 원형(NLP strict FX score) 재현 불가. 재무 proxy IC=-0.0078로 신호 품질 현저히 낮음. OOS 역전(IS SR -0.089 → OOS SR +0.224) = 일관 신호 아님.",
        "next_probe": [
            "FQ-148: DART 전문 텍스트 FX 헤징 공시 NLP (논문 원형, 데이터 구축 필요)",
            "FQ-149: FX 노출 순수 proxy (외화자산/총자산) — 논문 exposure baseline 직접 대응"
        ],
        "consumer_surfaces": [
            "2유니버스 필터: 파생상품 급증 종목 제거 필터 미검",
            "4위험모델: 저베타(0.332) 구조 — 베타 조정 참고"
        ],
        "registered": f"{now} (AS 에이전트 결과 수집)",
        "source_paper": "2607.27611",
        "revival_conditions": [
            "DART 전문 텍스트 파이프라인 구축 시 FQ-148로 재도전",
            "IC 음수(-0.0078) 역방향 검증 후 유의 시 FQ-149 방향"
        ]
    },
    {
        "id": "FQ-148",
        "lane": "non_return",
        "title": "DART 사업보고서 전문 텍스트 FX 헤징 공시 NLP — 논문 원형 재현",
        "hypothesis": "AWARE-FX(2607.27611) 핵심 신호: 사업보고서 FX 헤지 파생상품 사용 여부 NLP 점수화 → FX 위험 관리 강도 이진/연속 점수. KR DART 전문 텍스트 접근 필요.",
        "ev_rationale": "FQ-074(DART 전문 감성)와 동일 데이터 경로. FQ-074 착수 후 텍스트 파이프라인 구축 시 파생 착수 가능. 현재 data_gate=미구축.",
        "wall_check": "비-return 원천. PIT C4 의무(사업보고서 lag = 익년 3/31). 텍스트 파이프라인 구축 선행 필수.",
        "data_gate": "DART 사업보고서 전문 텍스트 파이프라인 미구축 — FQ-074 완료 후 착수 가능.",
        "status": "blocked_by_FQ-074",
        "owner": "Q-Lead",
        "registered": f"{now} (FQ-147 next_probe 파생)",
        "source_paper": "2607.27611"
    },
    {
        "id": "FQ-149",
        "lane": "alpha_search",
        "title": "FX 노출 순수 proxy — 외화자산/총자산 (논문 exposure baseline)",
        "hypothesis": "AWARE-FX 논문의 FX exposure baseline에 직접 대응: dart_raw_financials 외화표시현금 계정 비중(외화자산/총자산). 헤징 활동이 아닌 노출 수준 측정.",
        "ev_rationale": "FQ-147의 IC 음수(-0.0078) = 파생상품 보유가 역방향. 논문은 FX 노출 기업이 헤징으로 안정화 → 프리미엄이라는 구조 — 노출 측면을 별도 측정.",
        "wall_check": "RAWDATA/dart_raw_financials에 외화 계정 존재 여부 사전 확인 필수. 기존 DB에 외화-관련 팩터 없음 확인됨.",
        "data_gate": "dart_raw_financials.parquet 외화표시현금/외화자산 계정 존재 여부 precheck 필요.",
        "status": "frontier_open",
        "owner": "Q-Lead",
        "registered": f"{now} (FQ-147 next_probe 파생)",
        "source_paper": "2607.27611",
        "next_action": "1 dart_raw_financials 외화 계정 precheck 2 커버리지 확인 3 alpha-search 경량 백테"
    }
]

entries.extend(new_entries)
fq['entries'] = entries
fq['updated'] = f'{now} (FQ-147/148/149 AWARE-FX 결과 등재)'

with open('06_Registry/alpha_frontier_queue.json', 'w', encoding='utf-8') as f:
    json.dump(fq, f, ensure_ascii=False, indent=2)

print(f'FQ-147, FQ-148, FQ-149 등재 완료. 총 항목: {len(entries)}')
