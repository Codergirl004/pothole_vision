import cv2
import numpy as np
import os

class CameraCalibrator:
    def __init__(self, chessboard_size=(9, 6), square_size_cm=2.5):
        """
        chessboard_size: the preferred size, but we will fallback to others.
        square_size_cm: Physical size of each chessboard square in centimeters.
        """
        self.preferred_size = chessboard_size
        self.square_size_cm = square_size_cm
        
        # Try preferred size first, then standard common ones
        sizes = [chessboard_size, (9, 6), (8, 8), (7, 7), (10, 7), (7, 6), (6, 5)]
        self.sizes_to_try = []
        for s in sizes:
            if s not in self.sizes_to_try:
                self.sizes_to_try.append(s)

    def _get_objp(self, size):
        objp = np.zeros((size[0] * size[1], 3), np.float32)
        objp[:, :2] = np.mgrid[0:size[0], 0:size[1]].T.reshape(-1, 2)
        objp *= self.square_size_cm
        return objp

    def calibrate(self, image_paths):
        objpoints = [] # 3d point in real world space
        imgpoints = [] # 2d points in image plane.

        criteria = (cv2.TERM_CRITERIA_EPS + cv2.TERM_CRITERIA_MAX_ITER, 30, 0.001)
        valid_images = 0
        img_shape = None
        
        detected_size = None
        current_objp = None

        for fname in image_paths:
            img = cv2.imread(fname)
            if img is None: continue
            
            gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
            if img_shape is None:
                img_shape = gray.shape[::-1]

            flags = cv2.CALIB_CB_ADAPTIVE_THRESH + cv2.CALIB_CB_NORMALIZE_IMAGE + cv2.CALIB_CB_FAST_CHECK
            
            # If we haven't locked onto a grid size yet, try all configurations
            sizes = [detected_size] if detected_size else self.sizes_to_try
            
            ret = False
            for size in sizes:
                ret, corners = cv2.findChessboardCorners(gray, size, flags)
                if ret:
                    if detected_size is None:
                        detected_size = size
                        current_objp = self._get_objp(size)
                    break

            if ret:
                objpoints.append(current_objp)
                corners2 = cv2.cornerSubPix(gray, corners, (11, 11), (-1, -1), criteria)
                imgpoints.append(corners2)
                valid_images += 1
            else:
                # If FAST_CHECK failed, try without fast check for robustness
                if detected_size is None:
                     for size in sizes:
                         ret, corners = cv2.findChessboardCorners(gray, size, cv2.CALIB_CB_ADAPTIVE_THRESH + cv2.CALIB_CB_NORMALIZE_IMAGE)
                         if ret:
                             detected_size = size
                             current_objp = self._get_objp(size)
                             break
                     if ret:
                         objpoints.append(current_objp)
                         corners2 = cv2.cornerSubPix(gray, corners, (11, 11), (-1, -1), criteria)
                         imgpoints.append(corners2)
                         valid_images += 1

        if valid_images < 3:
            return False, None, f"Calibration failed: Found corners in only {valid_images} images. Make sure the chessboard pattern is completely visible. Tried sizes: {self.sizes_to_try}"

        try:
            ret, mtx, dist, rvecs, tvecs = cv2.calibrateCamera(objpoints, imgpoints, img_shape, None, None)
            error = self._calculate_reprojection_error(objpoints, imgpoints, rvecs, tvecs, mtx, dist)
            return True, {
                "fx": float(mtx[0][0]), "fy": float(mtx[1][1]),
                "cx": float(mtx[0][2]), "cy": float(mtx[1][2]),
                "error": float(error), "valid_images": valid_images,
                "detected_grid": detected_size,
                "img_width": int(img_shape[0]), "img_height": int(img_shape[1])
            }, f"Calibration successful! Detected grid: {detected_size[0]}x{detected_size[1]}"

        except Exception as e:
            return False, None, f"Error during calibration math: {str(e)}"

    def _calculate_reprojection_error(self, objpoints, imgpoints, rvecs, tvecs, mtx, dist):
        mean_error = 0
        for i in range(len(objpoints)):
            imgpoints2, _ = cv2.projectPoints(objpoints[i], rvecs[i], tvecs[i], mtx, dist)
            error = cv2.norm(imgpoints[i], imgpoints2, cv2.NORM_L2) / len(imgpoints2)
            mean_error += error
        return mean_error / len(objpoints)
