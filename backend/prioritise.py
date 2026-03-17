import math

class PotholePrioritizer:
    def get_priority_score(self, depth_cm, area_cm2, is_busy_area=False, complaint_count=1):
        # 1. Normalize Physical Data (0-10 scale)
        # 15cm depth is 'Critical', 5000cm2 area is 'Large'
        depth_score = min((depth_cm / 15.0) * 10, 10)
        area_score = min((area_cm2 / 5000.0) * 10, 10)
        
        # 2. Contextual Factors
        traffic_score = 10 if is_busy_area else 2
        
        # 3. Crowd-Sourcing Factor (Logarithmic)
        # 1 report = 0, 10 reports = 5.0, 100 reports = 10.0
        complaint_score = min(math.log10(max(1, complaint_count)) * 5, 10)

        # 4. Weighted Total
        final_score = (
            (depth_score * 0.40) + 
            (traffic_score * 0.25) + 
            (complaint_score * 0.20) + 
            (area_score * 0.15)
        )
        
        return round(float(final_score), 2)

    def get_label(self, score):
        if score >= 8.5: return "CRITICAL"
        if score >= 6.5: return "HIGH"
        if score >= 4.0: return "MEDIUM"
        return "LOW"