import os
import uuid
import cv2
import numpy as np
import imagehash  # For duplicate detection
from PIL import Image
from fpdf import FPDF  # For PDF generation
from datetime import datetime
import firebase_admin
from flask import Flask, request, jsonify
from flask_cors import CORS
from firebase_admin import credentials, firestore, storage

# Import your custom modules
from depth import PotholeAnalyzer
from detect import Detector
from cost_estimation import CostEstimator
from prioritise import PotholePrioritizer

app = Flask(__name__)
CORS(app)  # Enable CORS for Flutter app access

# --- FIREBASE SETUP ---
cred = credentials.Certificate("serviceAccountKey.json")
firebase_admin.initialize_app(cred, {
    'storageBucket': 'pothole-vision-bd61e.firebasestorage.app' 
})
db = firestore.client()
bucket = storage.bucket()

# --- INITIALIZE MODELS ---
analyzer = PotholeAnalyzer()
detector = Detector(os.path.join("model", "best.pt"))
prioritizer = PotholePrioritizer()
estimator = CostEstimator("LMR_Rates.xlsx") 

def generate_pdf_report(potholes_list, total_cost):
    """Generates a detailed PDF report with annotated images and individual metrics."""
    pdf = FPDF()
    pdf.set_auto_page_break(auto=True, margin=15)
    pdf.add_page()
    
    # Header
    pdf.set_font("Arial", 'B', 20)
    pdf.cell(200, 20, "Pothole Analysis & Cost Report", ln=True, align='C')
    
    # Summary Table
    pdf.set_font("Arial", size=12)
    pdf.cell(200, 10, f"Date: {datetime.now().strftime('%Y-%m-%d %H:%M')}", ln=True)
    pdf.cell(200, 10, f"Detections in this Batch: {len(potholes_list)}", ln=True)
    pdf.set_font("Arial", 'B', 14)
    pdf.cell(200, 10, f"Batch Estimated Total: Rs. {total_cost}", ln=True)
    pdf.ln(10)

    for i, p in enumerate(potholes_list):
        pdf.set_font("Arial", 'B', 12)
        pdf.cell(0, 10, f"Detection #{i+1} | Severity: {p['priority']['label']}", ln=True)
        
        # Add the specific annotated image
        pdf.image(p['local_temp_img'], x=10, w=100)
        
        pdf.set_font("Arial", size=10)
        pdf.ln(2)
        pdf.cell(0, 5, f"Location ID: {p['location_id']}", ln=True)
        pdf.cell(0, 5, f"Metrics: Area {p['metrics']['area_cm2']} cm2, Depth {p['metrics']['depth_cm']} cm", ln=True)
        pdf.cell(0, 5, f"Est. Cost: Rs. {p['estimation']['total_cost']}", ln=True)
        pdf.ln(10)

    report_filename = f"Report_{uuid.uuid4().hex}.pdf"
    pdf.output(report_filename)
    return report_filename

@app.route("/api/health", methods=["GET"])
def health_check():
    return jsonify({"status": "ok", "message": "Pothole Vision Backend is running"})

@app.route("/api/calibrate", methods=["POST"])
def calibrate_camera_api():
    if 'files' not in request.files:
        return jsonify({"success": False, "message": "No files uploaded"}), 400

    files = request.files.getlist("files")
    temp_files = []
    
    try:
        from calibrate import CameraCalibrator
        # The user's provided chessboard has 9x9 squares, which means 8x8 inner intersections
        calibrator = CameraCalibrator(chessboard_size=(8, 8), square_size_cm=2.5) 
        
        for idx, file in enumerate(files):
            temp_path = f"temp_calib_{uuid.uuid4().hex}_{idx}.jpg"
            file.save(temp_path)
            temp_files.append(temp_path)
            
        success, camera_matrix, msg = calibrator.calibrate(temp_files)
        
        if success:
            return jsonify({
                "success": True,
                "camera_matrix": camera_matrix,
                "message": msg
            })
        else:
            return jsonify({
                "success": False,
                "message": msg
            }), 400
            
    except Exception as e:
        print(f"Calibration API Error: {e}")
        return jsonify({"success": False, "message": str(e)}), 500
    finally:
        for temp_file in temp_files:
            if os.path.exists(temp_file):
                os.remove(temp_file)

@app.route("/api/detect_batch", methods=["POST"])
def detect_batch_api():
    if 'files' not in request.files:
        return jsonify({"success": False, "message": "No files uploaded"}), 400

    files = request.files.getlist("files")
    lat = float(request.form.get("lat", 0))
    lng = float(request.form.get("lng", 0))
    user_id = request.form.get("user_id", "")
    firestore_doc_id = request.form.get("firestore_doc_id", "")
    
    import json
    camera_matrix_str = request.form.get("camera_matrix", "{}")
    try:
        camera_matrix = json.loads(camera_matrix_str)
    except:
        camera_matrix = {}
    location_id = f"{round(lat, 4)}_{round(lng, 4)}"
    
    all_potholes_data = []
    seen_hashes = set()
    total_batch_cost = 0
    total_batch_severity = 0
    temp_files_to_cleanup = []

    try:
        # Reference for the main location document
        location_ref = db.collection("aggregated_potholes").document(location_id)

        for file in files:
            # --- 1. DUPLICATE DETECTION (PIXEL HASHING) ---
            img_pil = Image.open(file)
            phash = str(imagehash.phash(img_pil))
            
            if phash in seen_hashes:
                continue
            seen_hashes.add(phash)

            temp_path = f"temp_{uuid.uuid4().hex}_{file.filename}"
            file.seek(0) 
            file.save(temp_path)
            temp_files_to_cleanup.append(temp_path)

            results = detector.run(temp_path, is_video=False)
            
            for res in results:
                if res.boxes:
                    depth_map = analyzer.get_depth_map(res.orig_img)
                    
                    for box in res.boxes:
                        # Metrics and Cost Calculation
                        coords = box.xyxy[0].cpu().numpy()
                        metrics = analyzer.calculate_metrics(depth_map, coords, *res.orig_img.shape[:2], camera_matrix=camera_matrix)
                        area, depth, volume = metrics["area"], metrics["depth"], metrics["volume"]
                        costs = estimator.estimate_cost(float(volume))
                        
                        score = prioritizer.get_priority_score(float(depth), float(area))
                        total_batch_cost += costs['total_cost']
                        total_batch_severity += float(score)

                        # Annotate Image
                        annotated_img = res.orig_img.copy()
                        x1, y1, x2, y2 = map(int, coords)
                        cv2.rectangle(annotated_img, (x1, y1), (x2, y2), (255, 0, 0), 3)
                        cv2.putText(annotated_img, f"Rs. {costs['total_cost']}", (x1, y1 - 10), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 255, 0), 2)

                        img_name = f"det_{uuid.uuid4().hex}.jpg"
                        cv2.imwrite(img_name, annotated_img)
                        temp_files_to_cleanup.append(img_name)

                        # Upload to Firebase Storage
                        blob = bucket.blob(f"detections/{img_name}")
                        blob.upload_from_filename(img_name)
                        blob.make_public()

                        # --- 3. SAVE INDIVIDUAL DETECTION TO SUB-COLLECTION ---
                        detection_id = f"det_{uuid.uuid4().hex}"
                        report = {
                            "location_id": location_id,
                            "detection_id": detection_id,
                            "coords": {"lat": lat, "lng": lng},
                            "metrics": {"area_cm2": area, "depth_cm": depth, "volume_cm3": volume},
                            "priority": {"score": float(score), "label": prioritizer.get_label(score)},
                            "estimation": {"total_cost": costs['total_cost'], "currency": "Rs."},
                            "image_url": blob.public_url,
                            "complaint_instance": 1, 
                            "timestamp": firestore.SERVER_TIMESTAMP
                        }
                        
                        # Store in detections sub-collection
                        location_ref.collection("detections").document(detection_id).set(report)
                        
                        # Store locally for PDF generator
                        report["local_temp_img"] = img_name
                        all_potholes_data.append(report)

        # --- 4. BATCH-LEVEL COMPLAINT INCREMENT ---
        if all_potholes_data:
            @firestore.transactional
            def update_complaint_count(transaction, loc_ref):
                snapshot = loc_ref.get(transaction=transaction)
                count = 0
                if snapshot.exists:
                    count = snapshot.to_dict().get("complaint_count", 0)
                
                new_count = count + 1
                transaction.set(loc_ref, {
                    "complaint_count": new_count,
                    "last_updated": firestore.SERVER_TIMESTAMP,
                    "coords": {"lat": lat, "lng": lng}
                }, merge=True)
                return new_count

            transaction = db.transaction()
            current_complaint_total = update_complaint_count(transaction, location_ref)

            # --- 5. PDF GENERATION ---
            pdf_file = generate_pdf_report(all_potholes_data, total_batch_cost)
            pdf_blob = bucket.blob(f"reports/{pdf_file}")
            pdf_blob.upload_from_filename(pdf_file)
            pdf_blob.make_public()
            pdf_url = pdf_blob.public_url
            os.remove(pdf_file)
            # --- 6. DATA AGGREGATION & REPORTING ---
            if not all_potholes_data:
                return jsonify({"success": False, "message": "No potholes detected"}), 404
                
            first_detection = all_potholes_data[0]
            avg_score = total_batch_severity / len(all_potholes_data)

            # --- 7. UPDATE USER'S POTHOLES DOCUMENT ---
            if firestore_doc_id:
                db.collection("potholes").document(firestore_doc_id).set({
                    "analysisStatus": "analyzed",
                    "pdfUrl": pdf_url,
                    "severity": prioritizer.get_label(avg_score),
                    "severityScore": total_batch_severity, # USE SUM AS REQUESTED
                    "depthCm": first_detection['metrics']['depth_cm'],
                    "areaCm2": first_detection['metrics']['area_cm2'],
                    "volumeCm3": first_detection['metrics']['volume_cm3'],
                    "estimatedCost": first_detection['estimation']['total_cost'],
                    "totalBatchCost": total_batch_cost,
                    "potholesDetected": len(all_potholes_data),
                    "analyzedAt": firestore.SERVER_TIMESTAMP,
                }, merge=True)

            # --- 8. ADD TO AGGREGATED REPORTS SUB-COLLECTION ---
            location_ref.collection("reports").add({
                "pdf_url": pdf_url,
                "detection_count": len(all_potholes_data),
                "total_cost": total_batch_cost,
                "severity": prioritizer.get_label(avg_score),
                "timestamp": firestore.SERVER_TIMESTAMP
            })

            return jsonify({
                "success": True, 
                "pdf_url": pdf_url,
                "total_batch_cost": total_batch_cost,
                "total_batch_severity": total_batch_severity,
                "potholes_processed": len(all_potholes_data),
                "severity": prioritizer.get_label(total_batch_severity / len(all_potholes_data)),
                "severity_score": total_batch_severity,
                "depth_cm": first_detection['metrics']['depth_cm'],
                "area_cm2": first_detection['metrics']['area_cm2'],
                "estimated_cost": first_detection['estimation']['total_cost'],
            })
        
        # No pothole detected — update doc status
        if firestore_doc_id:
            db.collection("potholes").document(firestore_doc_id).set({
                "analysisStatus": "no_pothole",
                "analyzedAt": firestore.SERVER_TIMESTAMP,
            }, merge=True)

        return jsonify({"success": False, "message": "No potholes detected in the image"}), 404

    except Exception as e:
        print(f"Backend Error: {e}")
        # Update doc with error status
        if firestore_doc_id:
            try:
                db.collection("potholes").document(firestore_doc_id).set({
                    "analysisStatus": "error",
                    "analysisError": str(e),
                }, merge=True)
            except Exception:
                pass
        return jsonify({"success": False, "message": str(e)}), 500
    finally:
        for temp_file in temp_files_to_cleanup:
            if os.path.exists(temp_file):
                os.remove(temp_file)

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=True)