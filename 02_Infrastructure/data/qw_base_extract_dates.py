# -*- coding: utf-8 -*-
"""qw_base_extract_dates.py — 퀀티 기본 수출본 OHLCVS.xlsx 에서 **지정 날짜 행만** 스트리밍으로 뽑는다 (2026-10-17)

왜: 기본 수출본은 893MB(시트당 XML ~800MB)라 통째 파싱(readxl · openpyxl)이 느리고 메모리를 크게 쓴다. 한 날짜를 되살릴 때
  (첫 사용 = 도훈 결정 CAL-20241230-REAL-SESSION '하루 복원해' — 2024-12-30) 그 날짜 행만 압축을 풀며 찾는다(실측 2분 52초).
  ★앞뒤 날짜를 함께 뽑아 RAWDATA 와 6필드 비트 일치를 먼저 확인할 것(같은 수출본 · 같은 수정주가 기준인지의 증거).
레이아웃 = incremental_update_file.R::incremental_ohlcvs 와 같은 가정: 8행 = 열 이름(종목 코드) · 9~13행 = 메타 5행 · 14행~ = A열 날짜 serial.
  시트 1~6 = Open · High · Low · Close · Vol · Size (workbook.xml rId1~6 실측).
사용: python -I qw_base_extract_dates.py <OHLCVS.xlsx> <out.parquet> 2024-12-27,2024-12-30,2025-01-02
출력: parquet(Date, Ticker, Open, High, Low, Close, Vol, Size) — RAWDATA 를 쓰지 않는다(삽입은 호출부 · writer 잠금 안).
"""
import re, sys, zipfile, datetime as dt
import pandas as pd

SRC, OUT = sys.argv[1], sys.argv[2]
DATES = [dt.date.fromisoformat(s) for s in sys.argv[3].split(",")]
SER = {(d - dt.date(1899, 12, 30)).days: d for d in DATES}
SHEETS = [("Open", "xl/worksheets/sheet1.xml"), ("High", "xl/worksheets/sheet2.xml"), ("Low", "xl/worksheets/sheet3.xml"),
          ("Close", "xl/worksheets/sheet4.xml"), ("Vol", "xl/worksheets/sheet5.xml"), ("Size", "xl/worksheets/sheet6.xml")]

z = zipfile.ZipFile(SRC)
ss = z.read("xl/sharedStrings.xml").decode("utf-8")
SST = [re.sub(r"<[^>]+>", "", m) for m in re.findall(r"<si>(.*?)</si>", ss, re.S)]

CELL = re.compile(r'<c r="([A-Z]+)(\d+)"([^>]*?)(?:/>|>(.*?)</c>)', re.S)
VAL = re.compile(r"<v>(.*?)</v>", re.S)
INL = re.compile(r"<t[^>]*>(.*?)</t>", re.S)

def cells(row_xml):
    out = {}
    for col, _r, attrs, inner in CELL.findall(row_xml):
        if not inner:
            continue
        if 't="s"' in attrs:
            m = VAL.search(inner); out[col] = SST[int(m.group(1))] if m else None
        elif 't="inlineStr"' in attrs:
            m = INL.search(inner); out[col] = m.group(1) if m else None
        else:
            m = VAL.search(inner); out[col] = m.group(1) if m else None
    return out

ROWSTART = re.compile(rb'<row r="(\d+)"')
frames = {}
for var, part in SHEETS:
    header, found, buf = None, {}, b""
    with z.open(part) as f:
        done = False
        while not done:
            chunk = f.read(32 << 20)
            if not chunk:
                done = True
            buf += chunk
            while True:
                m = ROWSTART.search(buf)
                if not m:
                    buf = buf[-64:] if not done else b""
                    break
                end = buf.find(b"</row>", m.start())
                if end < 0:
                    buf = buf[m.start():]
                    break
                rnum = int(m.group(1))
                row = buf[m.start():end + 6]
                buf = buf[end + 6:]
                if rnum == 8:
                    header = cells(row.decode("utf-8"))
                elif rnum >= 14:
                    a = re.search(rb'<c r="A\d+"[^>]*><v>([^<]*)</v>', row)
                    if a:
                        try:
                            s = int(float(a.group(1)))
                        except ValueError:
                            continue
                        if s in SER:
                            found[SER[s]] = cells(row.decode("utf-8"))
                        elif s > max(SER):
                            done = True; break
    if header is None:
        sys.exit(f"FAIL {var}: header row 8 not found")
    recs = []
    for d, cl in found.items():
        for col, v in cl.items():
            if col == "A" or v in (None, ""):
                continue
            tk = header.get(col)
            if not tk:
                continue
            try:
                recs.append((d, tk, float(v)))
            except ValueError:
                pass
    frames[var] = pd.DataFrame(recs, columns=["Date", "Ticker", var])
    print(f"{var}: dates found {sorted(str(d) for d in found)} · cells {len(recs)} · header cols {len(header)}", flush=True)

out = None
for var, df in frames.items():
    out = df if out is None else out.merge(df, on=["Date", "Ticker"], how="outer")
out.to_parquet(OUT, index=False)
print("rows", len(out), "->", OUT)
