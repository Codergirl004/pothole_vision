# Pothole Vision

Pothole Vision is an application designed to detect, analyze, and estimate the cost of repairing potholes. It consists of a **Flutter mobile frontend** and a **Flask Python backend** powered by OpenCV and Machine Learning (Ultralytics YOLO, PyTorch, etc.). 

The system guides users to capture calibration images, detects potholes from user-uploaded images, measures depth/volume, assesses severity, and prioritizes repairs.

## 🚀 Features
- **Pothole Detection**: Uses an ML model to identify potholes from images.
- **Depth & Volume Analysis**: Computes the dimensions of the pothole using camera calibration.
- **Severity & Prioritization**: Automatically categorizes the severity of the damage.
- **Cost Estimation**: Estimates repair costs based on volume and provided rates.
- **Admin Dashboard**: View detected potholes on a map, view reports, and analyze data.

---

## 🛠️ Prerequisites
Before running this project, ensure you have the following installed:
- **[Flutter SDK](https://docs.flutter.dev/get-started/install)** (for running the mobile app)
- **[Python 3.8+](https://www.python.org/downloads/)** (for the Flask backend)
- **Git**

---

## ⚙️ Backend Setup (Flask + ML)

The backend handles all the image processing, machine learning model inference, and database interactions.

1. **Navigate to the backend directory:**
   ```bash
   cd backend
   ```

2. **Create a virtual environment (Recommended):**
   ```bash
   python -m venv venv
   ```

3. **Activate the virtual environment:**
   - **Windows:**
     ```bash
     venv\Scripts\activate
     ```
   - **Mac/Linux:**
     ```bash
     source venv/bin/activate
     ```

4. **Install the required dependencies:**
   ```bash
   pip install -r requirements.txt
   ```

5. **Add Firebase Credentials:**
   You will need a Firebase Admin service account key to allow the backend to communicate with Firebase Firestore/Storage.
   - Go to your Firebase Console -> Project Settings -> Service Accounts.
   - Click "Generate new private key".
   - Save the downloaded JSON file as `serviceAccountKey.json` and place it inside the `backend/` folder.

6. **Run the Flask server:**
   ```bash
   python app.py
   ```
   The server should now be running on `http://127.0.0.1:5000` (or `http://<your-ip>:5000`).

---

## 📱 Frontend Setup (Flutter)

The frontend is a Flutter application that interacts with the user and communicating with the Flask server.

1. **Navigate to the frontend directory:**
   ```bash
   cd ../frontend
   ```
   *(Or just `cd frontend` from the root directory).*

2. **Install Flutter packages:**
   ```bash
   flutter pub get
   ```

3. **Add Firebase Configurations:**
   Since the app uses Firebase for authentication and database services, you must connect your own Firebase project.
   - For **Android**: Download `google-services.json` from Firebase console and place it in `frontend/android/app/`.
   - For **iOS**: Download `GoogleService-Info.plist` and place it in `frontend/ios/Runner/`.

4. **Update the Backend IP Address:**
   If you are testing on a physical device, ensure both your computer and phone are on the same Wi-Fi network. Update the API endpoints in your Flutter code (usually in a `constants.dart` or `api_service.dart` file) from `127.0.0.1` to your computer's local IPv4 address (e.g., `192.168.1.x`).

5. **Run the app:**
   ```bash
   flutter run
   ```

---

## 📦 Tech Stack
- **Frontend**: Flutter, Dart
- **Backend**: Python, Flask, OpenCV, PyTorch, Ultralytics YOLO
- **Database / Cloud**: Firebase Authentication, Cloud Firestore, Firebase Storage
- **Maps**: Google Maps Flutter API
