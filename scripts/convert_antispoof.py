"""Rebuild Resources/AntiSpoof.mlpkgdata from upstream weights and verify it against PyTorch.

Usage:
  git clone https://github.com/minivision-ai/Silent-Face-Anti-Spoofing
  pip install torch coremltools opencv-python-headless==4.10.0.84 pillow
  cd Silent-Face-Anti-Spoofing && python /path/to/convert_antispoof.py OUT.mlpackage
  # then replace Sources/FaceUnlockCore/Resources/AntiSpoof.mlpkgdata with OUT.mlpackage

Preprocessing facts this relies on (from upstream source, not its docstrings):
  - src/data_io/functional.py to_tensor does NOT divide by 255 -> scale=1.0
  - images come from cv2.imread -> BGR channel order
  - test.py: label 1 = real face
"""
import os
import sys
from collections import OrderedDict

sys.path.insert(0, os.getcwd())  # upstream's `src` package lives in the clone we run from

import coremltools as ct
import cv2
import numpy as np
import torch
import torch.nn as nn
from PIL import Image

from src.anti_spoof_predict import AntiSpoofPredict
from src.generate_patches import CropImage
from src.model_lib.MiniFASNet import MiniFASNetV2

WEIGHTS = "resources/anti_spoof_models/2.7_80x80_MiniFASNetV2.pth"
out_path = sys.argv[1]

net = MiniFASNetV2(conv6_kernel=(5, 5))
state = torch.load(WEIGHTS, map_location="cpu")
if next(iter(state)).startswith("module."):
    state = OrderedDict((k[7:], v) for k, v in state.items())
net.load_state_dict(state)
net.eval()


class WithSoftmax(nn.Module):
    def __init__(self, model):
        super().__init__()
        self.model = model

    def forward(self, x):
        return torch.softmax(self.model(x), dim=1)


traced = torch.jit.trace(WithSoftmax(net).eval(), torch.rand(1, 3, 80, 80) * 255)
mlmodel = ct.convert(
    traced,
    inputs=[ct.ImageType(name="input_image", shape=(1, 3, 80, 80), color_layout=ct.colorlayout.BGR, scale=1.0)],
    outputs=[ct.TensorType(name="probabilities")],
    compute_precision=ct.precision.FLOAT32,
    minimum_deployment_target=ct.target.macOS14,
)
mlmodel.short_description = "MiniFASNetV2 (2.7_80x80) anti-spoof. Softmax, index 1 = real face. Input BGR raw 0-255."
mlmodel.save(out_path)

predictor, cropper = AntiSpoofPredict(-1), CropImage()
converted = ct.models.MLModel(out_path)
worst = 0.0
for name in ["image_T1.jpg", "image_F1.jpg", "image_F2.jpg"]:
    img = cv2.imread("images/sample/" + name)
    patch = cropper.crop(org_img=img, bbox=predictor.get_bbox(img), scale=2.7, out_w=80, out_h=80, crop=True)
    reference = predictor.predict(patch, WEIGHTS)[0]
    got = np.array(converted.predict({"input_image": Image.fromarray(cv2.cvtColor(patch, cv2.COLOR_BGR2RGB))})["probabilities"][0])
    worst = max(worst, float(np.abs(reference - got).max()))
    print(f"{name}: torch={np.round(reference, 4)} coreml={np.round(got, 4)}")
print("max abs diff vs PyTorch:", worst)
sys.exit(0 if worst < 1e-3 else 1)
