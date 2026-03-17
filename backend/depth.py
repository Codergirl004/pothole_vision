import torch
import cv2
import numpy as np
import os
from sklearn.linear_model import RANSACRegressor

class PotholeAnalyzer:
    def __init__(self, camera_height_cm=150, focal_length=1200):
        """
        camera_height_cm: H (Vertical distance from camera to road)
        focal_length: f (Intrinsic focal length in pixels)
        """
        self.device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
        
        # Load MiDaS Small
        self.midas = torch.hub.load("intel-isl/MiDaS", "MiDaS_small").to(self.device).eval()
        self.transform = torch.hub.load("intel-isl/MiDaS", "transforms").small_transform
        
        self.H = camera_height_cm
        self.f = focal_length
        
        if not os.path.exists("debug_heatmaps"):
            os.makedirs("debug_heatmaps")

    def get_depth_map(self, img):
        """Generates raw disparity map."""
        img_rgb = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
        input_batch = self.transform(img_rgb).to(self.device)
        
        with torch.no_grad():
            prediction = self.midas(input_batch)
            prediction = torch.nn.functional.interpolate(
                prediction.unsqueeze(1), 
                size=img.shape[:2], 
                mode="bicubic", 
                align_corners=False
            ).squeeze()
            
        return prediction.cpu().numpy()

    def save_debug_heatmap(self, diff_map):
        """Saves depth visualization for verification."""
        view = cv2.normalize(diff_map, None, 0, 255, cv2.NORM_MINMAX).astype(np.uint8)
        heatmap = cv2.applyColorMap(view, cv2.COLORMAP_JET)
        filename = f"debug_heatmaps/heatmap_{np.random.randint(0, 10000)}.jpg"
        cv2.imwrite(filename, heatmap)

    def calculate_metrics(self, depth_map, box, img_h, img_w, camera_matrix=None):
        """
        Calculates Area using linear projection (H/f) 
        Calculates Depth using RANSAC Plane Subtraction
        """
        x1, y1, x2, y2 = map(int, box)
        w_px = x2 - x1
        h_px = y2 - y1

        fx = camera_matrix.get("fx", self.f) if camera_matrix else self.f
        fy = camera_matrix.get("fy", self.f) if camera_matrix else self.f

        # 1. AREA CALCULATION
        # Scale (cm/px) = Camera Height / Focal Length
        scale_x_cm_px = self.H / fx
        scale_y_cm_px = self.H / fy
        
        real_w = w_px * scale_x_cm_px
        real_h = h_px * scale_y_cm_px
        real_area = real_w * real_h

        # 2. RANSAC DEPTH ESTIMATION (Baseline Logic)
        pad = 120 
        lx1, ly1 = max(0, x1-pad), max(0, y1-pad)
        lx2, ly2 = min(img_w, x2+pad), min(img_h, y2+pad)
        
        try:
            # ROI for Plane Fitting
            roi_depth = depth_map[ly1:ly2, lx1:lx2]
            yy_roi, xx_roi = np.mgrid[ly1:ly2, lx1:lx2]
            X_roi = np.column_stack((xx_roi.ravel(), yy_roi.ravel()))
            y_roi = roi_depth.ravel()

            # Fit RANSAC to road surface
            ransac = RANSACRegressor(residual_threshold=0.2, random_state=42)
            ransac.fit(X_roi, y_roi)
            
            # Predict Road Plane
            yy, xx = np.mgrid[y1:y2, x1:x2]
            pothole_coords = np.column_stack((xx.ravel(), yy.ravel()))
            predicted_road = ransac.predict(pothole_coords).reshape(y2-y1, x2-x1)
            
            actual_pit = depth_map[y1:y2, x1:x2]
            diff = predicted_road - actual_pit
            
            self.save_debug_heatmap(diff)

            # Use 65th percentile for depth consistency
            disparity_diff = np.percentile(diff, 50) 
            disparity_diff = max(0, disparity_diff)

            # Scaling Factors
            avg_f = (fx + fy) / 2
            depth_scale = (self.H / avg_f) * 6.0
            real_depth = disparity_diff * depth_scale
            
            # Constraints
            real_depth = max(1.5, min(real_depth, 22.0))

        except Exception as e:
            print(f"RANSAC Error: {e}")
            real_depth = 5.0 

        # 3. VOLUME CALCULATION
        real_volume = real_area * real_depth * 0.6

        return {
            "area": round(float(real_area), 2),
            "depth": round(float(real_depth), 2),
            "volume": round(float(real_volume), 2),
            "bbox_coords": [int(x1), int(y1), int(x2), int(y2)]
        }