#!/usr/bin/env python
# =============================================================================
# paper_extract.py — 논문 PDF -> 텍스트 추출 (alpha-search 외부논문 주입 유틸)
# =============================================================================
# 알파 서칭 모드의 "외부 논문 지속 주입"을 위한 재사용 유틸. arxiv/SSRN PDF를
# 텍스트로 추출해 방법론(signal/비중/decile/리밸/long-short/universe/기간)을
# 사람이 읽고 factor_engine.R로 완전 복제(제1원칙)하도록 돕는다.
#
# Usage:
#   python paper_extract.py <pdf_path> [max_pages] [out_txt_path]
#   - max_pages 생략 시 전체. out_txt 생략 시 stdout(UTF-8).
# 추출 백엔드 우선순위: PyMuPDF(fitz) > pdfplumber > pypdf/PyPDF2.
# =============================================================================
import sys


def extract(path, max_pages=None):
    # 1) PyMuPDF (최고 품질)
    try:
        import fitz
        d = fitz.open(path)
        n = len(d) if max_pages is None else min(max_pages, len(d))
        return "\n".join(d[i].get_text() for i in range(n)), "pymupdf"
    except Exception:
        pass
    # 2) pdfplumber
    try:
        import pdfplumber
        out = []
        with pdfplumber.open(path) as pdf:
            pages = pdf.pages if max_pages is None else pdf.pages[:max_pages]
            for p in pages:
                out.append(p.extract_text() or "")
        return "\n".join(out), "pdfplumber"
    except Exception:
        pass
    # 3) pypdf / PyPDF2
    try:
        try:
            from pypdf import PdfReader
        except Exception:
            from PyPDF2 import PdfReader
        r = PdfReader(path)
        pages = r.pages if max_pages is None else r.pages[:max_pages]
        return "\n".join((p.extract_text() or "") for p in pages), "pypdf"
    except Exception as e:
        return f"[paper_extract] ALL BACKENDS FAILED: {e}", "none"


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("usage: python paper_extract.py <pdf_path> [max_pages] [out_txt]")
        sys.exit(1)
    path = sys.argv[1]
    mp = int(sys.argv[2]) if len(sys.argv) > 2 and sys.argv[2].isdigit() else None
    out = sys.argv[3] if len(sys.argv) > 3 else None
    txt, backend = extract(path, mp)
    sys.stderr.write(f"[paper_extract] backend={backend} chars={len(txt)}\n")
    if out:
        with open(out, "w", encoding="utf-8", errors="replace") as f:
            f.write(txt)
        sys.stderr.write(f"[paper_extract] wrote {out}\n")
    else:
        sys.stdout.buffer.write(txt.encode("utf-8", "replace"))
