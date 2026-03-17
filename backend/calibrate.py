import cv2
import numpy as np
import os

class CameraCalibrator:
    def __init__(self, chessboard_size=(9, 6), square_size_cm=2.5):
        """
        chessboard_size: Tuple representing the number of inner corners per a chessboard row and column.
        square_size_cm: Physical size of each chessboard square in centimeters.
        """
        self.chessboard_size = chessboard_size
        self.square_size_cm = square_size_cm
        
        # Prepare object points, like (0,0,0), (1,0,0), (2,0,0) ....,(8,5,0)
        self.objp = np.zeros((chessboard_size[0] * chessboard_size[1], 3), np.float32)
        # We need the points to be properly shaped for OpenCV's coordinate standards
        self.objp[:, :2] = np.mgrid[0:chessboard_size[0], 0:chessboard_size[1]].T.reshape(-1, 2)
        self.objp *= square_size_cm

    def calibrate(self, image_paths):
        """
        Takes a list of file paths to images, detects the chessboard, and computes the camera matrix.
        Returns:
            success (bool): True if calibration succeeded
            metadata (dict or None): Contains camera_matrix values
            message (str): descriptive error or success message
        """
        objpoints = [] # 3d point in real world space
        imgpoints = [] # 2d points in image plane.

        # Termination criteria for subpixel accuracy
        criteria = (cv2.TERM_CRITERIA_EPS + cv2.TERM_CRITERIA_MAX_ITER, 30, 0.001)

        valid_images = 0
        img_shape = None

        for fname in image_paths:
            img = cv2.imread(fname)
            if img is None:
                continue
                
            gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
            
            if img_shape is None:
                img_shape = gray.shape[::-1] # (width, height)

            # Find the chess board corners
            ret, corners = cv2.findChessboardCorners(gray, self.chessboard_size, None)

            if ret:
                objpoints.append(self.objp)
                # Refine corner locations
                corners2 = cv2.cornerSubPix(gray, corners, (11, 11), (-1, -1), criteria)
                imgpoints.append(corners2)
                valid_images += 1

        if valid_images < 5:
            # Need at least a few valid images to get a reliable matrix
            return False, None, f"Calibration failed: Only found clear corners in {valid_images} images. Try capturing from different angles and distances, ensuring the whole pattern is visible."

        try:
            # Calibrate camera
            ret, mtx, dist, rvecs, tvecs = cv2.calibrateCamera(objpoints, imgpoints, img_shape, None, None)
            
            error = self._calculate_reprojection_error(objpoints, imgpoints, rvecs, tvecs, mtx, dist)

            return True, {
                "fx": float(mtx[0][0]),
                "fy": float(mtx[1][1]),
                "cx": float(mtx[0][2]),
                "cy": float(mtx[1][2]),
                "error": float(error),
                "valid_images": valid_images
            }, "Calibration completed successfully!"

        except Exception as e:
            return False, None, f"Error during calibration math: {str(e)}"

    def _calculate_reprojection_error(self, objpoints, imgpoints, rvecs, tvecs, mtx, dist):
        mean_error = 0
        for i in range(len(objpoints)):
            imgpoints2, _ = cv2.projectPoints(objpoints[i], rvecs[i], tvecs[i], mtx, dist)
            error = cv2.norm(imgpoints[i], imgpoints2, cv2.NORM_L2) / len(imgpoints2)
            mean_error += error
        return mean_error / len(objpoints)
