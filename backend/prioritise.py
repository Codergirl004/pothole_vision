import math

class PotholePrioritizer:
    def get_priority_score(self, depth_cm, area_cm2):
        # 1. Normalize Physical Data (0-10 scale)
        # 15cm depth is 'Critical', 5000cm2 area is 'Large'
        depth_score = min((depth_cm / 15.0) * 10, 10)
        area_score = min((area_cm2 / 5000.0) * 10, 10)
        
        # 2. Weighted Total
        # Only Depth (70%) and Area (30%)
        final_score = (depth_score * 0.70) + (area_score * 0.30)
        
        return round(float(final_score), 2)

    def get_label(self, score):
        if score >= 8.5: return "CRITICAL"
        if score >= 6.5: return "HIGH"
        if score >= 4.0: return "MEDIUM"
        return "LOW"