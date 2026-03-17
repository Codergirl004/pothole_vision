from ultralytics import YOLO

class Detector:
    def __init__(self, model_path):
        self.model = YOLO(model_path)

    def run(self, source, is_video=False, conf=0.4):
        if is_video:
            # .track() enables the unique 'id' attribute to prevent duplicates
            # In detect.py
            return self.model.track(source, conf=0.4, persist=True, tracker="bytetrack.yaml")
        else:
            return self.model.predict(source, conf=conf)