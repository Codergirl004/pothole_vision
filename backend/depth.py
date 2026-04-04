import torch
import cv2
import numpy as np
import os
from sklearn.linear_model import RANSACRegressor
import imagehash
from PIL import Image

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
            
        # Initialize ORB for similarity matching
        self.orb = cv2.ORB_create(nfeatures=500)
        self.bf = cv2.BFMatcher(cv2.NORM_HAMMING, crossCheck=True)

    def compute_quality_score(self, img, bbox, detection_confidence):
        """
        Computes a quality score based on brightness, contrast, sharpness, and confidence.
        """
        x1, y1, x2, y2 = map(int, bbox)
        crop = img[y1:y2, x1:x2]
        if crop.size == 0:
            return 0.0
            
        gray = cv2.cvtColor(crop, cv2.COLOR_BGR2GRAY)
        
        # 1. Brightness (0-255, ideal around 127)
        brightness = np.mean(gray)
        brightness_score = 1.0 - abs(brightness - 127.5) / 127.5
        
        # 2. Contrast (std dev)
        contrast = np.std(gray)
        contrast_score = min(contrast / 50.0, 1.0) # Assume 50 is "good enough" contrast
        
        # 3. Sharpness (Laplacian variance)
        sharpness = cv2.Laplacian(gray, cv2.CV_64F).var()
        sharpness_score = min(sharpness / 500.0, 1.0) # Assume 500 is "sharp"
        
        # Weighted average
        total_score = (brightness_score * 0.2) + (contrast_score * 0.2) + (sharpness_score * 0.3) + (detection_confidence * 0.3)
        return round(float(total_score), 4)

    def get_image_hash(self, img, bbox):
        """
        Computes the perceptual hash of the pothole crop.
        """
        x1, y1, x2, y2 = map(int, bbox)
        crop = img[max(0, y1):max(0, y2), max(0, x1):max(0, x2)]
        if crop.size == 0:
            return None
        
        img_pil = Image.fromarray(cv2.cvtColor(crop, cv2.COLOR_BGR2RGB))
        return str(imagehash.phash(img_pil))

    def get_orb_features(self, img, bbox):
        """
        Extracts ORB descriptors and keypoint coordinates for the pothole crop.
        Returns a hex string of the descriptors and keypoints for storage.
        """
        x1, y1, x2, y2 = map(int, bbox)
        crop = img[max(0, y1):max(0, y2), max(0, x1):max(0, x2)]
        if crop.size == 0:
            return None
        
        gray = cv2.cvtColor(crop, cv2.COLOR_BGR2GRAY)
        kp, des = self.orb.detectAndCompute(gray, None)
        
        if des is None or len(kp) == 0:
            return None
            
        # Extract (x, y) coordinates from keypoints
        kp_coords = np.array([p.pt for p in kp], dtype=np.float32)
        
        # Pack into hex string: [4 bytes count][descriptors][kp_coords]
        count = np.array([len(kp)], dtype=np.int32)
        packed = count.tobytes() + des.tobytes() + kp_coords.tobytes()
        return packed.hex()

    def compare_similarity(self, hash1, hash2):
        """
        Compares two perceptual hashes. 
        Returns a similarity score (1.0 - normalized distance).
        """
        if not hash1 or not hash2:
            return 0.0
        
        h1 = imagehash.hex_to_hash(hash1)
        h2 = imagehash.hex_to_hash(hash2)
        
        # Distance = number of bits that are different (out of 64)
        distance = h1 - h2
        similarity = 1.0 - (distance / 64.0)
        return similarity

    def compare_orb(self, hex_data1, hex_data2):
        """
        Compares two ORB sets using RANSAC Geometric Verification.
        Returns the number of inlier matches.
        """
        if not hex_data1 or not hex_data2:
            return 0
            
        try:
            # Unpack hex data
            raw1 = bytes.fromhex(hex_data1)
            raw2 = bytes.fromhex(hex_data2)
            
            count1 = np.frombuffer(raw1[:4], dtype=np.int32)[0]
            des1 = np.frombuffer(raw1[4:4 + count1*32], dtype=np.uint8).reshape(count1, 32)
            kp1 = np.frombuffer(raw1[4 + count1*32:], dtype=np.float32).reshape(count1, 2)
            
            count2 = np.frombuffer(raw2[:4], dtype=np.int32)[0]
            des2 = np.frombuffer(raw2[4:4 + count2*32], dtype=np.uint8).reshape(count2, 32)
            kp2 = np.frombuffer(raw2[4 + count2*32:], dtype=np.float32).reshape(count2, 2)
            
            # 1. Match Descriptors
            matches = self.bf.match(des1, des2)
            if len(matches) < 8: # Minimum needed for homography + significance
                return 0
                
            # 2. Geometric Verification (RANSAC)
            src_pts = np.float32([kp1[m.queryIdx] for m in matches]).reshape(-1, 1, 2)
            dst_pts = np.float32([kp2[m.trainIdx] for m in matches]).reshape(-1, 1, 2)
            
            # Find homography matrix
            M, mask = cv2.findHomography(src_pts, dst_pts, cv2.RANSAC, 5.0)
            
            if mask is None:
                return 0
                
            inliers = int(np.sum(mask))
            return inliers
            
        except Exception as e:
            print(f"ORB RANSAC Match Error: {e}")
            return 0

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

        # Better fallback: typical mobile camera focal length is roughly equal to image width (~53 deg FOV)
        fallback_fx = img_w * 1.0
        fallback_fy = img_w * 1.0
        
        # Override the camera height to a more realistic waist-level assumption (100 cm) 
        # to prevent huge area overestimations when users take close-up photos
        self.H = 100 
        
        # Ignore legacy cached matrices from the phone that lack resolution data 
        # because they might have horribly distorted focal lengths from bad test runs.
        if camera_matrix and "img_width" not in camera_matrix:
            camera_matrix = None
            
        fx = camera_matrix.get("fx", fallback_fx) if camera_matrix else fallback_fx
        fy = camera_matrix.get("fy", fallback_fy) if camera_matrix else fallback_fy
        
        # If the user calibrated at a different resolution, scale the focal length
        if camera_matrix and "img_width" in camera_matrix:
            fx *= (img_w / camera_matrix.get("img_width", img_w))
            fy *= (img_h / camera_matrix.get("img_height", img_h))

        # 1. AREA CALCULATION
        # Scale (cm/px) = Camera Height / Focal Length
        scale_x_cm_px = self.H / fx
        scale_y_cm_px = self.H / fy
        
        real_w = min(w_px * scale_x_cm_px, 200.0) # Cap at 2 meters max realistic width
        real_h = min(h_px * scale_y_cm_px, 200.0) # Cap at 2 meters max realistic length
        
        # Potholes are usually elliptical, not perfectly rectangular bounding boxes.
        # Area of ellipse = pi * (w/2) * (h/2) = 0.785 * w * h
        real_area = 0.785 * real_w * real_h

        # 2. RANSAC DEPTH ESTIMATION (Baseline Logic)
        pad = 120 
        lx1, ly1 = max(0, x1-pad), max(0, y1-pad)
        lx2, ly2 = min(img_w, x2+pad), min(img_h, y2+pad)
        
        try:
            # 1. PREPARE DATA FOR PLANE FITTING
            roi_depth = depth_map[ly1:ly2, lx1:lx2]
            yy_grid, xx_grid = np.mgrid[ly1:ly2, lx1:lx2]
            
            # --- IMPROVEMENT: EXCLUDE POTHOLE FROM ROAD PLANE FITTING ---
            # Create a mask that is True for road surface and False for the pothole area
            mask = np.ones(roi_depth.shape, dtype=bool)
            # Map global bounding box to ROI-relative coordinates
            px1, py1 = x1 - lx1, y1 - ly1
            px2, py2 = x2 - lx1, y2 - ly1
            
            # Ensure indices are within ROI bounds (should be true due to pad and min/max)
            mask[max(0, py1):min(roi_depth.shape[0], py2), 
                 max(0, px1):min(roi_depth.shape[1], px2)] = False
            
            # Only use pixels OUTSIDE the pothole to fit the road plane
            X_road = np.column_stack((xx_grid[mask], yy_grid[mask]))
            y_road = roi_depth[mask]

            # Fallback if the pothole takes up the entire padded ROI (extremely rare)
            if len(y_road) < 100:
                X_road = np.column_stack((xx_grid.ravel(), yy_grid.ravel()))
                y_road = roi_depth.ravel()

            # 2. FIT ROAD PLANE
            # Lowered residual_threshold for tighter road surface alignment
            ransac = RANSACRegressor(residual_threshold=0.15, random_state=42)
            ransac.fit(X_road, y_road)
            
            # Predict the "ideal" road level for the pixels INSIDE the pothole
            yy_pit, xx_pit = np.mgrid[y1:y2, x1:x2]
            pothole_coords = np.column_stack((xx_pit.ravel(), yy_pit.ravel()))
            predicted_road = ransac.predict(pothole_coords).reshape(y2-y1, x2-x1)
            
            # 3. CALCULATE DIFFERENCE
            actual_pit = depth_map[y1:y2, x1:x2]
            diff = predicted_road - actual_pit
            
            self.save_debug_heatmap(diff)

            # --- IMPROVEMENT: USE AVERAGE OF DEEPEST 10% ---
            # Instead of a single 95th percentile point, which can be noisy, 
            # use the average of the top 10% deepest pixels.
            diff_flat = diff.ravel()
            deepest_indices = np.argsort(diff_flat)[-int(len(diff_flat)*0.1):]
            if len(deepest_indices) > 0:
                disparity_diff = np.mean(diff_flat[deepest_indices])
            else:
                disparity_diff = np.percentile(diff_flat, 95)
            
            disparity_diff = max(0.1, disparity_diff)

            # 4. SCALE TO CENTIMETERS
            avg_f = (fx + fy) / 2
            
            # Heuristic adjustment: Depth in MiDaS is relative, so we use H/f 
            # Increased multiplier from 7.0 to 12.0 as MiDaS Small has condensed ranges
            depth_scale = (self.H / avg_f) * 12.0
            real_depth = disparity_diff * depth_scale
            
            print(f"Debug Depth -> Diff: {disparity_diff:.2f}, Scale: {depth_scale:.4f}, Depth: {real_depth:.2f}cm")

            # Constraints
            real_depth = max(1.5, min(real_depth, 28.0))

        except Exception as e:
            print(f"Depth Estimation Error: {e}")
            real_depth = 5.0 

        # 3. VOLUME CALCULATION
        real_volume = real_area * real_depth * 0.8

        return {
            "area": round(float(real_area), 2),
            "depth": round(float(real_depth), 2),
            "volume": round(float(real_volume), 2),
            "bbox_coords": [int(x1), int(y1), int(x2), int(y2)]
        }