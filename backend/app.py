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
# Updated to use JSON-based CostEstimator
estimator = CostEstimator("lmr.json") 

def cleanup_backend():
    """Removes all temporary files and clears debug artifacts."""
    patterns = ["temp_*.jpg", "det_*.jpg", "Report_*.pdf"]
    import glob
    for pattern in patterns:
        for f in glob.glob(pattern):
            try: os.remove(f)
            except: pass
    
    # Clear heatmaps
    heatmap_dir = "debug_heatmaps"
    if os.path.exists(heatmap_dir):
        for f in os.listdir(heatmap_dir):
            try: os.remove(os.path.join(heatmap_dir, f))
            except: pass
    
    # Clear log
    if os.path.exists("debug.log"):
        with open("debug.log", "w") as f:
            f.write(f"--- LOG RESTARTED AT {datetime.now()} ---\n")

cleanup_backend() # Run on startup

# --- TRANSACTIONAL HELPERS ---
@firestore.transactional
def update_metrics_transactional(transaction, doc_ref, new_area, new_depth, new_weight, new_quality, new_url, new_phash, new_orb):
    snapshot = doc_ref.get(transaction=transaction)
    data = snapshot.to_dict()
    
    weight_sum = data.get('metrics_weight_sum', 1.0)
    current_metrics = data.get('metrics', {})
    curr_area = current_metrics.get('area_cm2', new_area)
    curr_depth = current_metrics.get('depth_cm', new_depth)
    
    updated_area = (curr_area * weight_sum + new_area * new_weight) / (weight_sum + new_weight)
    updated_depth = (curr_depth * weight_sum + new_depth * new_weight) / (weight_sum + new_weight)
    
    # Recalculate Priority based on new averaged depth
    updated_score = prioritizer.get_priority_score(updated_depth)
    updated_label = prioritizer.get_label(updated_score)
    
    update_data = {
        "metrics": {
            "area_cm2": round(float(updated_area), 2),
            "depth_cm": round(float(updated_depth), 2),
            "volume_cm3": round(float(updated_area * updated_depth * 0.8), 2)
        },
        "priority": {"score": updated_score, "label": updated_label},
        "metrics_weight_sum": weight_sum + new_weight,
        "last_updated": firestore.SERVER_TIMESTAMP
    }
    
    if new_quality > data.get('representative_quality', 0):
        update_data.update({
            "representative_image_url": new_url,
            "representative_quality": new_quality,
            "representative_phash": new_phash,
            "representative_orb": new_orb
        })
    
    transaction.update(doc_ref, update_data)
    return updated_area, updated_depth

@firestore.transactional
def update_complaint_count_transactional(transaction, doc_ref):
    snapshot = doc_ref.get(transaction=transaction)
    count = snapshot.to_dict().get("complaint_count", 0) if snapshot.exists else 0
    transaction.update(doc_ref, {
        "complaint_count": count + 1,
        "last_updated": firestore.SERVER_TIMESTAMP
    })

def generate_pdf_report(potholes_list, total_cost):
    """Generates a professional standardized PDF report."""
    pdf = FPDF()
    pdf.set_auto_page_break(auto=True, margin=15)
    pdf.add_page()
    
    # --- HEADER ---
    pdf.set_fill_color(33, 47, 61) # Dark Gray-Blue
    pdf.rect(0, 0, 210, 40, 'F')
    
    pdf.set_font("Arial", 'B', 24)
    pdf.set_text_color(255, 255, 255)
    pdf.cell(200, 25, "Pothole Analysis Report", ln=True, align='C')
    
    pdf.set_font("Arial", size=10)
    pdf.cell(200, 5, f"Generated on: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}", ln=True, align='C')
    pdf.ln(15)
    
    # --- SUMMARY SECTION ---
    pdf.set_text_color(0, 0, 0)
    pdf.set_font("Arial", 'B', 14)
    pdf.cell(0, 10, "Summary of Detections", ln=True)
    pdf.line(10, pdf.get_y(), 200, pdf.get_y())
    pdf.ln(5)
    
    pdf.set_font("Arial", size=11)
    pdf.cell(100, 10, f"Total Detections in Batch: {len(potholes_list)}", ln=False)
    pdf.set_font("Arial", 'B', 14)
    pdf.set_text_color(200, 0, 0) # Red for cost
    pdf.cell(100, 10, f"Estimated Batch Total: Rs. {total_cost:,.2f}", ln=True, align='R')
    pdf.set_text_color(0, 0, 0)
    pdf.ln(10)

    # --- INDIVIDUAL DETECTIONS ---
    for i, p in enumerate(potholes_list):
        # Increased threshold to prevent headers from being marooned at the bottom of a page
        if pdf.get_y() > 185: 
            pdf.add_page()
            
        pdf.set_font("Arial", 'B', 12)
        pdf.set_fill_color(240, 240, 240)
        pdf.cell(0, 10, f" Detection #{i+1}", ln=True, fill=True)
        pdf.ln(5)
        
        # Detection Image - Dynamic Height Calculation
        y_before_img = pdf.get_y()
        img_h_mm = 70 # Default fallback
        try:
            # Measure image for accurate vertical spacing
            img_cv = cv2.imread(p['local_temp_img'])
            if img_cv is not None:
                h_px, w_px = img_cv.shape[:2]
                img_h_mm = (110.0 / w_px) * h_px
        except: pass
        
        pdf.image(p['local_temp_img'], x=10, w=110)
        
        # Details next to image
        pdf.set_xy(125, y_before_img)
        pdf.set_font("Arial", 'B', 11)
        pdf.set_font("Arial", size=10)
        pdf.set_x(125)
        pdf.cell(0, 6, f"- Area: {p['metrics']['area_cm2']:,} cm\u00b2 ({(p['metrics']['area_cm2']/10000.0):.4f} m\u00b2)", ln=True)
        pdf.set_x(125)
        pdf.cell(0, 6, f"- Depth: {p['metrics']['depth_cm']} cm", ln=True)
        pdf.set_x(125)
        # Volume converted to m3 for cost relevance
        vol_m3 = p['metrics']['area_cm2']/10000.0 * (p['metrics']['depth_cm']/100.0) * 0.6
        pdf.cell(0, 6, f"- Volume: {vol_m3:.6f} m\u00b3", ln=True)
        
        # Estimation Details (Final Cost Only)
        pdf.ln(4)
        pdf.set_x(125)
        pdf.set_font("Arial", 'B', 11)
        pdf.cell(0, 8, f"Severity: {p['priority']['label']}", ln=True)
        
        pdf.ln(2)
        pdf.set_x(125)
        pdf.set_text_color(200, 0, 0)
        pdf.set_font("Arial", 'B', 12)
        pdf.cell(0, 10, f"Est. Cost: Rs. {p['estimation']['final_cost']:,.2f}", ln=True)
        pdf.set_text_color(0, 0, 0)
        
        # Coordinate link
        pdf.set_x(125)
        pdf.set_font("Arial", size=9, style='I')
        pdf.cell(0, 6, f"Lat: {p['coords']['lat']:.6f}, Lng: {p['coords']['lng']:.6f}", ln=True)
        
        # Final spacing: find the lowest point of the current detection row
        # Use the actual calculated image height for perfect spacing
        y_text_bottom = pdf.get_y()
        y_img_bottom = y_before_img + img_h_mm 
        
        pdf.set_y(max(y_text_bottom, y_img_bottom) + 15)
        # Separator line between detections
        pdf.set_draw_color(200, 200, 200)
        pdf.line(10, pdf.get_y() - 5, 200, pdf.get_y() - 5)

    # --- FOOTER ---
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

    # NEW: Support for individual locations per image
    locations_json = request.form.get("locations", "[]")
    try:
        per_image_locations = json.loads(locations_json)
    except:
        per_image_locations = []

    temp_files_to_cleanup = []
    all_potholes_data = []
    seen_hashes = set()
    total_batch_cost = 0
    total_batch_severity = 0
    
    # --- DEDUPLICATION: FETCH ALL POTHOLES FOR IMAGE-BASED MATCHING ---
    existing_potholes = []
    try:
        # Load all canonical potholes (ignoring GPS proximity for matching)
        query = db.collection("aggregated_potholes").stream()
        for doc in query:
            data = doc.to_dict()
            data['doc_id'] = doc.id
            existing_potholes.append(data)
        
        with open("debug.log", "a") as f:
            f.write(f"DEBUG: Loaded {len(existing_potholes)} potholes for global image-matching.\n")
    except Exception as e:
        with open("debug.log", "a") as f:
            f.write(f"Warning: Database query failed: {e}\n")

    try:
        for idx, file in enumerate(files):
            # --- 1. SET LOCATION FOR THIS FILE ---
            # Use per-image location if available, otherwise fallback to global batch location
            file_lat, file_lng = lat, lng
            if idx < len(per_image_locations):
                loc = per_image_locations[idx]
                file_lat = loc.get('lat', lat)
                file_lng = loc.get('lng', lng)

            # --- 2. DUPLICATE DETECTION (PIXEL HASHING) ---
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
                        
                        # New PDF-based Cost Estimation logic
                        costs = estimator.estimate_cost(
                            depth_cm=float(depth),
                            area_m2=float(area) / 10000.0,
                            supply_12="supplychain_12mm.pdf",
                            data_12="datasheet_12mm.pdf",
                            supply_36="supplychain_36mm.pdf",
                            data_36="datasheet_36mm.pdf"
                        )
                        
                        score = prioritizer.get_priority_score(float(depth), float(area))
                        total_batch_cost += costs['final_cost']
                        total_batch_severity += float(score)

                        # Annotate Image
                        annotated_img = res.orig_img.copy()
                        x1, y1, x2, y2 = map(int, coords)
                        # Label formatting: Increased size and thickness as requested
                        cv2.rectangle(annotated_img, (x1, y1), (x2, y2), (255, 0, 0), 3)
                        cv2.putText(annotated_img, f"Rs. {costs['final_cost']:,}", (x1, y1 - 25), cv2.FONT_HERSHEY_SIMPLEX, 1.8, (0, 0, 255), 4)

                        img_name = f"det_{uuid.uuid4().hex}.jpg"
                        cv2.imwrite(img_name, annotated_img)
                        temp_files_to_cleanup.append(img_name)

                        # Upload to Firebase Storage
                        blob = bucket.blob(f"detections/{img_name}")
                        blob.upload_from_filename(img_name)
                        blob.make_public()

                        # --- 2. QUALITY SCORING & DEDUPLICATION ---
                        quality_score = analyzer.compute_quality_score(res.orig_img, coords, box.conf[0].item())
                        pothole_hash = analyzer.get_image_hash(res.orig_img, coords)
                        pothole_orb = analyzer.get_orb_features(res.orig_img, coords)
                        
                        match_found = False
                        matched_doc_id = None
                        
                        for existing in existing_potholes:
                            similarity = analyzer.compare_similarity(pothole_hash, existing.get('representative_phash'))
                            ransac_inliers = analyzer.compare_orb(pothole_orb, existing.get('representative_orb'))
                            
                            with open("debug.log", "a") as f:
                                f.write(f"DEBUG: Comparing with {existing.get('doc_id')}. PHash: {similarity:.4f}, RANSAC Inliers: {ransac_inliers}\n")
                            
                            # LOGIC REPLACEMENT: HIGH-CONFIDENCE MATCHING
                            # 1. ORB/RANSAC is robust for many viewpoints, but pavement texture can be repetitive.
                            # 2. GPS check: if coordinates are IDENTICAL, they are likely fallback values (home/upload spot).
                            
                            existing_coords = existing.get('coords', {})
                            is_same_location = (file_lat == existing_coords.get('lat') and file_lng == existing_coords.get('lng'))
                            
                            has_orb = bool(pothole_orb) and bool(existing.get('representative_orb'))
                            is_match = False
                            
                            if has_orb:
                                # Regular match: must have decent visual similarity AND enough keypoint matches
                                if ransac_inliers >= 30 and similarity >= 0.60:
                                    is_match = True
                                
                                # Fallback location protection: if they share the exact same location, 
                                # they are likely different potholes reported from the same spot (home).
                                # Require extremely high confidence in this case.
                                if is_same_location:
                                    if ransac_inliers < 40 and similarity < 0.95:
                                        is_match = False # Override previous match to be more skeptical
                            else:
                                # Legacy or pHash fallback (nearly identical image)
                                if similarity > 0.99: 
                                    is_match = True

                            if is_match:
                                with open("debug.log", "a") as f:
                                    f.write(f"DEBUG: MATCH FOUND with {existing['doc_id']} (RANSAC:{ransac_inliers}, PHash:{similarity:.4f}, SameLoc:{is_same_location})\n")
                                match_found = True
                                matched_doc_id = existing['doc_id']
                                
                                p_ref = db.collection("aggregated_potholes").document(matched_doc_id)
                                transaction = db.transaction()
                                final_avg_area, final_avg_depth = update_metrics_transactional(transaction, p_ref, area, depth, quality_score, quality_score, blob.public_url, pothole_hash, pothole_orb)
                                
                                # Use aggregated metrics for the report to ensure consistency
                                area, depth = final_avg_area, final_avg_depth
                                break
                        
                        if not match_found:
                            # Create a new canonical record in aggregated_potholes
                            new_pothole_id = f"pothole_{uuid.uuid4().hex}"
                            db.collection("aggregated_potholes").document(new_pothole_id).set({
                                "coords": {"lat": file_lat, "lng": file_lng},
                                "representative_image_url": blob.public_url,
                                "representative_quality": quality_score,
                                "representative_phash": pothole_hash,
                                "representative_orb": pothole_orb,
                                "metrics": {"area_cm2": area, "depth_cm": depth, "volume_cm3": volume},
                                "metrics_weight_sum": quality_score,
                                "priority": {"score": float(score), "label": prioritizer.get_label(score)},
                                "complaint_count": 1,
                                "created_at": firestore.SERVER_TIMESTAMP,
                                "last_updated": firestore.SERVER_TIMESTAMP
                            })
                            matched_doc_id = new_pothole_id
                            # Refresh local candidates to prevent duplicate creation in same batch if they match
                            existing_potholes.append({
                                "doc_id": new_pothole_id,
                                "coords": {"lat": file_lat, "lng": file_lng},
                                "representative_phash": pothole_hash,
                                "representative_orb": pothole_orb,
                                "representative_quality": quality_score
                            })

                        # --- 3. SAVE INDIVIDUAL DETECTION TO SUB-COLLECTION ---
                        detection_id = f"det_{uuid.uuid4().hex}"
                        report = {
                            "location_id": matched_doc_id, # Canonical record ID
                            "detection_id": detection_id,
                            "coords": {"lat": file_lat, "lng": file_lng},
                            "metrics": {"area_cm2": area, "depth_cm": depth, "volume_cm3": volume},
                            "priority": {"score": float(score), "label": prioritizer.get_label(score)},
                            "estimation": {
                                "final_cost": costs['final_cost'], 
                                "cost_per_m3": costs['cost_per_m3'],
                                "currency": "Rs."
                            },
                            "quality": quality_score,
                            "image_url": blob.public_url,
                            "timestamp": firestore.SERVER_TIMESTAMP
                        }
                        
                        # Store in detections sub-collection of the canonical pothole
                        db.collection("aggregated_potholes").document(matched_doc_id).collection("detections").document(detection_id).set(report)
                        
                        # Store locally for PDF generator
                        report["local_temp_img"] = img_name
                        all_potholes_data.append(report)

        # --- 4. BATCH-LEVEL COMPLAINT INCREMENT ---
        if all_potholes_data:
            # Update complaint counts for all unique potholes found in this batch
            unique_matched_ids = list(set([p['location_id'] for p in all_potholes_data]))
            for p_id in unique_matched_ids:
                p_ref = db.collection("aggregated_potholes").document(p_id)
                transaction = db.transaction()
                update_complaint_count_transactional(transaction, p_ref)

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
                    "estimatedCost": first_detection['estimation']['final_cost'],
                    "totalBatchCost": total_batch_cost,
                    "potholesDetected": len(all_potholes_data),
                    "analyzedAt": firestore.SERVER_TIMESTAMP,
                }, merge=True)

            # --- 8. LINK REPORT TO AGGREGATED POTHOLES (ADMIN VIEW) ---
            # This allows the admin to see the PDF report history for each canonical pothole
            for p_id in unique_matched_ids:
                db.collection("aggregated_potholes").document(p_id).collection("reports").add({
                    "pdf_url": pdf_url,
                    "timestamp": firestore.SERVER_TIMESTAMP,
                    "severity": prioritizer.get_label(avg_score),
                    "detection_count": len(all_potholes_data),
                    "total_cost": total_batch_cost
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
                "estimated_cost": first_detection['estimation']['final_cost'],
            })
        
        # No pothole detected — skip Firebase update as requested

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