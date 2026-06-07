"""
nlp_parser.py
─────────────
Layer 1 — NLP Module
Reads uploaded documents (PDF / image) using OCR + spaCy
and extracts key financial features needed by the ML model.
"""

import re
import os
import spacy
import pytesseract
from PIL import Image
from pdf2image import convert_from_path
import pypdf

# Load spaCy English model
# Run once: python -m spacy download en_core_web_sm
try:
    nlp = spacy.load("en_core_web_sm")
except OSError:
    raise RuntimeError(
        "spaCy model not found. Run: python -m spacy download en_core_web_sm"
    )


# ── Main entry point ──────────────────────────────────────────────────────────

def extract_features(file_path: str) -> dict:
    """
    Takes a file path (PDF or image).
    Returns a dict of financial features for the ML model.
    """
    raw_text = _file_to_text(file_path)
    doc      = nlp(raw_text)

    features = {
        "applicant_name":   _extract_name(doc),
        "monthly_income":   _extract_number(raw_text, [
                                r"net\s+pay[^\d]*?([\d,.]+)",
                                r"take\s+home[^\d]*?([\d,.]+)",
                                r"(?:monthly\s+)?(?:salary|income|ctc)[^\d]*?([\d,.]+)",
                            ], exclude_years=True),
        "loan_amount":      _extract_number(raw_text, [
                                r"loan\s+amount[^\d]*?([\d,.]+)",
                                r"principal[^\d]*?([\d,.]+)",
                                r"amount\s+requested[^\d]*?([\d,.]+)",
                            ], get_max=True),
        "existing_emis":    _extract_number(raw_text, [
                                r"(?:existing\s+)?emi[^\d]*?([\d,.]+)",
                                r"monthly\s+obligation[^\d]*?([\d,.]+)",
                            ], get_max=True),
        "employment_years": _extract_number(raw_text, [
                                r"experience[^\d]*?([\d]+)",
                                r"(\d+)\s+years?\s+(?:of\s+)?(?:work|experience|service)",
                                r"employment\s+years[^\d]*?([\d]+)",
                            ], get_max=True),
        "credit_score":     _extract_number(raw_text, [
                                r"cibil[^\d]*?([\d]{3})",
                                r"credit\s+score[^\d]*?([\d]{3})",
                                r"score[^\d]*?([\d]{3})",
                            ], get_max=True),
        "num_dependents":   _extract_number(raw_text, [
                                r"dependents?[^\d]*?([\d])",
                                r"family\s+members?[^\d]*?([\d])",
                            ]),
        "raw_text_length":  len(raw_text),
    }

    # Fallback sensible defaults if not found
    features["monthly_income"]   = features["monthly_income"]   or 30000.0
    features["loan_amount"]      = features["loan_amount"]      or 100000.0
    features["existing_emis"]    = features["existing_emis"]    or 0.0
    features["employment_years"] = features["employment_years"] or 1.0
    features["credit_score"]     = features["credit_score"]     or 650.0
    features["num_dependents"]   = features["num_dependents"]   or 1.0

    return features


# ── Helpers ───────────────────────────────────────────────────────────────────

def _file_to_text(file_path: str) -> str:
    """Convert PDF or image file to raw text using OCR."""
    ext = os.path.splitext(file_path)[1].lower()

    try:
        if ext == ".pdf":
            # 1. Try direct text extraction (No Poppler required)
            try:
                text = ""
                with open(file_path, "rb") as f:
                    reader = pypdf.PdfReader(f)
                    for page in reader.pages:
                        page_text = page.extract_text()
                        if page_text:
                            text += page_text + "\n"
                
                # If we got meaningful text, return it
                if len(text.strip()) > 50:
                    print(f"[NLP] Direct PDF extraction successful ({len(text)} chars)")
                    return text
                else:
                    print("[NLP] Direct extraction yielded little text. Falling back to OCR...")
            except Exception as e:
                print(f"[NLP] pypdf extraction failed: {e}. Falling back to OCR...")

            # 2. Fallback: Convert each PDF page to image then OCR (Requires Poppler)
            try:
                pages = convert_from_path(file_path, dpi=200)
            except Exception as e:
                if "poppler" in str(e).lower():
                    raise RuntimeError(
                        "Poppler is not installed or not in your PATH. "
                        "Digital PDFs are supported, but this file appears to be a scan "
                        "and requires Poppler for OCR. See README/Plan for installation."
                    )
                raise e

            text = ""
            for page in pages:
                text += pytesseract.image_to_string(page)
            return text
        else:
            # Direct image OCR (jpg, jpeg, png)
            # Requires Tesseract-OCR installed + in PATH
            image = Image.open(file_path)
            return pytesseract.image_to_string(image)

    except pytesseract.TesseractNotFoundError:
        raise RuntimeError(
            "Tesseract OCR is not installed or not in your PATH. "
            "Please install Tesseract and add it to your System PATH."
        )
    except Exception as e:
        # Catch-all for other OCR/PDF issues
        if "tesseract" in str(e).lower():
            raise RuntimeError(
                "Tesseract error: Ensure Tesseract-OCR is installed and in your PATH."
            )
        raise e


def _extract_number(text: str, patterns: list, get_max: bool = False, exclude_years: bool = False) -> float:
    """
    Try each regex pattern on the text.
    Return the match as a float, or 0.0 if none found.
    - get_max: If True, returns the largest number across all matches and patterns.
    - exclude_years: If True, skips numbers between 2000 and 2100 (likely years).
    """
    matches = []
    for pattern in patterns:
        all_found = re.finditer(pattern, text, flags=re.IGNORECASE | re.MULTILINE)
        for m in all_found:
            # Handle thousands separators: "45.000" or "45,000"
            raw = m.group(1).strip()
            
            # Heuristic: if a dot is followed by 3 digits at the end of the match or group, 
            # and there are other digits before it, it's likely a separator, not a decimal.
            # Example: "60.300" (Indian style or OCR error) vs "60.30" (decimal)
            if '.' in raw:
                parts = raw.split('.')
                if len(parts) > 1 and len(parts[-1]) == 3:
                    raw = raw.replace('.', '')
            
            raw = raw.replace(',', '')
            
            try:
                val = float(raw)
                if exclude_years and 2000 <= val <= 2100:
                    continue
                matches.append(val)
                if not get_max:
                    return val
            except ValueError:
                continue
    
    if get_max and matches:
        return max(matches)
    
    return 0.0


def _extract_name(doc) -> str:
    """Use spaCy NER to find a PERSON entity as applicant name."""
    # Common words in salary slips that AI misidentifies as names
    blacklist = ["deductions", "amount", "employee", "earnings", "salary", "slip", "details", "designation", "technology"]
    
    for ent in doc.ents:
        if ent.label_ == "PERSON":
            text = ent.text.strip()
            text_lower = text.lower()
            
            # Simple heuristic: ignore common table headers misidentified as people
            if any(word in text_lower for word in blacklist):
                continue
                
            # Filter out names that are too short or likely just noise
            if len(text.split()) >= 2: # Prefer full names like "Ravi Kumar"
                return text
                
    return "Unknown Applicant"
