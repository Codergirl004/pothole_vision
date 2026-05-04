import json
import pdfplumber
import re
import os

class CostEstimator:
    def __init__(self, lmr_path):
        self.lmr_path = lmr_path
        self.load_rates()
        # Cache for parsed PDF data to avoid redundant processing
        # Structure: { pdf_path: [ {code: str, qty: float, rate: float}, ... ] }
        self._cache = {}
        # New minimum charge for realistic reporting
        self.min_repair_cost = 500.0 

    def load_rates(self):
        if os.path.exists(self.lmr_path):
            with open(self.lmr_path, 'r') as f:
                self.new_rates = json.load(f)
        else:
            print(f"Warning: {self.lmr_path} not found. Using empty rates.")
            self.new_rates = {}
        
        # Policy: max repairable depth
        self.max_repair_depth = self.new_rates.get("MAX_REPAIR_DEPTH_CM", 15.0)

    # ---------------------------
    # 1. Extract Items from PDF (Optimized)
    # ---------------------------
    def extract_pdf_data(self, pdf_path):
        """Extracts item codes, quantities, and rates from a PDF file."""
        if pdf_path in self._cache:
            return self._cache[pdf_path]
            
        items = []
        if not os.path.exists(pdf_path):
            return items

        try:
            with pdfplumber.open(pdf_path) as pdf:
                for page in pdf.pages:
                    text = page.extract_text()
                    if not text:
                        continue
                        
                    lines = text.split("\n")
                    pending_code = None
                    for line in lines:
                        # Skip administrative lines
                        if any(x in line.upper() for x in ["TOTAL", "PAGE", "DATE", "SUBTOTAL"]):
                            continue

                        # Find matching material/item code
                        match = re.search(r'(?<![\d.])\b(MR\d+|M-\d+|\d{4})\b(?![\d.])', line)
                        
                        if match:
                            code = match.group(1)
                            # CRITICAL: Search for values only AFTER the code position
                            remainder = line[match.end():]
                            values = re.findall(r'\b\d+(?:\.\d+)?\b', remainder)

                            if values and len(values) >= 2:
                                # Values found on same line
                                qty = float(values[0])
                                rate = float(values[1])
                                items.append({"code": code, "quantity": qty, "pdf_rate": rate})
                                pending_code = None
                            else:
                                # Store code, values might be on next line
                                pending_code = code
                        elif pending_code:
                            # No code here, but check for values for a previous code
                            values = re.findall(r'\b\d+(?:\.\d+)?\b', line)
                            if values and len(values) >= 2:
                                qty = float(values[0])
                                rate = float(values[1])
                                items.append({"code": pending_code, "quantity": qty, "pdf_rate": rate})
                            pending_code = None
                            
            self._cache[pdf_path] = items
        except Exception as e:
            # Silently log errors to potentially prevent crash during API calls
            with open("debug.log", "a") as f:
                f.write(f"Error parsing PDF {pdf_path}: {e}\n")

        return items

    # ---------------------------
    # 2. Compute Base Cost per 1 m³
    # ---------------------------
    def calculate_base_total(self, supply_pdf, data_pdf):
        """Calculates the combined base cost from supply and data sheets."""
        cache_key = f"base:{supply_pdf}:{data_pdf}"
        if cache_key in self._cache:
            return self._cache[cache_key]

        supply_items = self.extract_pdf_data(supply_pdf)
        data_items = self.extract_pdf_data(data_pdf)

        all_items = supply_items + data_items
        base_total = 0

        for item in all_items:
            code = item["code"]
            qty = item["quantity"]
            # Use LMR rate as priority if it's non-zero, fallback to PDF rate
            rate = self.new_rates.get(code)
            if not rate or rate == 0:
                rate = item.get("pdf_rate", 0)
            base_total += qty * rate

        self._cache[cache_key] = base_total
        return base_total

    # ---------------------------
    # 3. Final Cost Estimation
    # ---------------------------
    def estimate_cost(self, depth_cm, area_m2, supply_12, data_12, supply_36=None, data_36=None):
        """Estimates the total repair cost including overhead and profit."""
        
        # 1. Volume Calculation (Parabolic Factor 0.6)
        depth_m = depth_cm / 100
        volume = area_m2 * depth_m * 0.8
        
        # 2. Policy Check: Removed depth limit (as requested by user)

        # 3. PDF Selection & Severity
        if depth_cm <= 4:
            severity = "LOW"
            base_total = self.calculate_base_total(supply_12, data_12)
        else:
            severity = "MEDIUM"
            s_pdf = supply_36 if supply_36 else supply_12
            d_pdf = data_36 if data_36 else data_12
            base_total = self.calculate_base_total(s_pdf, d_pdf)

        # 4. Apply Overhead and Profit (10% each, compounded)
        overhead = base_total * 0.10
        total_with_overhead = base_total + overhead
        
        profit = total_with_overhead * 0.10
        cost_per_m3 = total_with_overhead + profit

        # 5. Final Calculation (Fixed Base Fee + Volume Cost)
        final_cost = (cost_per_m3 * volume) + self.min_repair_cost

        return {
            "status": "REPAIRABLE",
            "severity": severity,
            "volume_m3": round(volume, 6),
            "cost_per_m3": round(cost_per_m3, 2),
            "final_cost": round(final_cost, 2)
        }