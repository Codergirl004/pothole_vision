import pandas as pd
import os

class CostEstimator:
    def __init__(self, lmr_path):
        self.lmr_path = lmr_path
        self.rates = self.load_lmr_rates()

    def load_lmr_rates(self):
        # FIX: header=None treats the first row as data, enabling integer indexing [0] and [3]
        try:
            df = pd.read_excel(self.lmr_path, header=None)
        except Exception as e:
            print(f"Error reading Excel: {e}")
            return {"bitumen_rate_per_m3": 8500, "labour_rate_per_day": 700}

        rates = {}
        for index, row in df.iterrows():
            # Check if row has enough columns to avoid further IndexErrors
            if len(row) < 4:
                continue
                
            description = str(row[0]).lower()

            if "bituminous concrete" in description:
                rates["bitumen_rate_per_m3"] = float(row[3])

            if "labour" in description or "mazdoor" in description:
                rates["labour_rate_per_day"] = float(row[3])

        # Default values if not found in the specific Excel file
        rates.setdefault("bitumen_rate_per_m3", 8500)
        rates.setdefault("labour_rate_per_day", 700)

        return rates

    def estimate_cost(self, volume_cm3):
        volume_m3 = volume_cm3 / 1_000_000
        material_cost = volume_m3 * self.rates["bitumen_rate_per_m3"]
        # Assuming 0.2 days of labor per unit of work for a pothole
        labour_cost = self.rates["labour_rate_per_day"] * 0.2
        total_cost = material_cost + labour_cost

        return {
            "volume_m3": round(float(volume_m3), 6),
            "material_cost": round(float(material_cost), 2),
            "labour_cost": round(float(labour_cost), 2),
            "total_cost": round(float(total_cost), 2)
        }