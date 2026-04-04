import math

class PotholePrioritizer:
    def get_priority_score(self, depth_cm, area_cm2=None):
        # 1. Direct Depth-based Score (0-10 scale)
        # Depth is the 100% driver of priority
        # Let 20cm be the maximum score (10.0)
        final_score = min((depth_cm / 20.0) * 10, 10)
        
        return round(float(final_score), 2)

    def get_label(self, score):
        # Labels based on the 20cm scale (Score = Depth/2)
        if score >= 9.0: return "CRITICAL"    # >18cm
        if score >= 5.0: return "HIGH"        # >10cm
        if score >= 2.0: return "MEDIUM"      # >4cm
        return "LOW"