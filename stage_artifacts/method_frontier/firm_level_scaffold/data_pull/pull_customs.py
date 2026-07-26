# -*- coding: utf-8 -*-
"""pull_customs.py — FQ-073 관세청 품목별(HS) 수출입실적 월별 패널 pull
#
#  ★2026-07-25 도훈 활용신청 승인 후 열림 (그 전 403 Forbidden → 현재 HTTP 200 resultCode 00).
#  데이터셋 15101609 / 엔드포인트 apis.data.go.kr/1220000/Itemtrade/getItemtradeList
#
#  API 제약 (명세 실측):
#    - 필수 strtYymm/endYymm(YYYYMM), 옵션 hsSgn(HS, 최대 10자리)
#    - **조회기간 1년 이내** → 연도별 루프 필수
#    - **페이지네이션 없음** → HS 지정 단위로 쪼개서 수집
#    - 반환: hsCode(10자리 세부), statKor(품목명), expDlr/impDlr(USD), expWgt/impWgt, balPayments, year(YYYY.MM)
#
#  수집 전략: HS 2자리(01~97) x 연도 루프. hsSgn=2자리면 그 류 전체 세부코드가 반환된다.
#  PIT: 관세청 월별 수출입은 익월 15일경 확정 공표(잠정→확정 개정 있음).
#       first-release 보존은 불가(과거 재조회 시 확정치가 옴) → 러너에서 발표시차 lag로 방어.
"""
import os, sys, json, time, urllib.parse, urllib.request, urllib.error
import xml.etree.ElementTree as ET
import pandas as pd

ROOT = os.environ.get("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
SCAF = os.path.join(ROOT, "stage_artifacts/method_frontier/firm_level_scaffold")
OUTD = os.path.join(SCAF, "fq073")
os.makedirs(OUTD, exist_ok=True)
OUTP = os.path.join(OUTD, "customs_hs_monthly.parquet")

key = None
for line in open(os.path.join(ROOT, ".env"), encoding="utf-8"):
    if line.startswith("DATA_GO_API_KEY="):
        key = line.split("=", 1)[1].strip()
if not key:
    sys.exit("[customs] DATA_GO_API_KEY 부재")
K = urllib.parse.quote(key, safe="")
BASE = "https://apis.data.go.kr/1220000/Itemtrade/getItemtradeList"

YEARS = range(2015, 2027)
HS2 = [f"{i:02d}" for i in range(1, 98)]


def fetch(hs, y):
    end = f"{y}12" if y < 2026 else "202606"
    url = f"{BASE}?serviceKey={K}&strtYymm={y}01&endYymm={end}&hsSgn={hs}"
    with urllib.request.urlopen(url, timeout=90) as r:
        return r.read().decode("utf-8", "replace")


def parse(xml):
    try:
        root = ET.fromstring(xml)
    except ET.ParseError:
        return []
    out = []
    for it in root.iter("item"):
        g = lambda t: (it.findtext(t) or "").strip()
        out.append({
            "hs": g("hsCode"), "stat_kor": g("statKor"), "ym": g("year"),
            "exp_usd": pd.to_numeric(g("expDlr"), errors="coerce"),
            "imp_usd": pd.to_numeric(g("impDlr"), errors="coerce"),
            "exp_wgt": pd.to_numeric(g("expWgt"), errors="coerce"),
            "imp_wgt": pd.to_numeric(g("impWgt"), errors="coerce"),
        })
    return out


def main():
    rows, fail = [], []
    total = len(HS2) * len(YEARS)
    i = 0
    for hs in HS2:
        for y in YEARS:
            i += 1
            try:
                recs = parse(fetch(hs, y))
                rows.extend(recs)
                if i % 50 == 0:
                    print(f"[{i}/{total}] hs={hs} y={y} 누적 {len(rows)}행", flush=True)
            except urllib.error.HTTPError as ex:
                fail.append((hs, y, ex.code))
            except Exception as ex:
                fail.append((hs, y, type(ex).__name__))
            time.sleep(0.05)
    if not rows:
        sys.exit(f"[customs] 수집 0행 — 실패 {len(fail)}건 샘플 {fail[:5]}")
    df = pd.DataFrame(rows)
    df = df[df.ym.str.len() == 7]                    # 'YYYY.MM' 월별 행만(연 합계 행 배제)
    df["ym"] = df.ym.str.replace(".", "-", regex=False)
    df = df.drop_duplicates(subset=["hs", "ym"])
    df.to_parquet(OUTP, index=False)
    print(f"[customs] 완료 — {len(df)}행 / HS {df.hs.nunique()} / 월 {df.ym.nunique()} "
          f"({df.ym.min()}~{df.ym.max()}) / 실패 {len(fail)}건 → {OUTP}", flush=True)
    if fail:
        json.dump(fail, open(os.path.join(OUTD, "customs_pull_failures.json"), "w"), ensure_ascii=False)


if __name__ == "__main__":
    main()
