import serial, time, numpy as np
from torchvision import datasets, transforms

def extract_zones(img):
    zones = img.reshape(4, 7, 4, 7)
    means = zones.mean(axis=(1, 3))
    scaled = np.round(means * 64).clip(0, 16320).astype(np.int32)
    return scaled.flatten()

ser = serial.Serial('/dev/ttyUSB1', 9600, timeout=2)

test_ds = datasets.MNIST('./data/mnist', train=False, download=True,
                         transform=transforms.ToTensor())
img_tensor, label = test_ds[0]
img_arr = (img_tensor.squeeze().numpy() * 255).astype(np.uint8)
feats = extract_zones(img_arr)

print(f"True label: {label}")
print("Sending image...")
ser.write(bytes([0x01]))          # CMD_START
time.sleep(0.001)
for val in feats:
    ser.write(bytes([val & 0xFF, (val >> 8) & 0xFF]))
    time.sleep(0.0001)
time.sleep(3)   # allow MLP to compute

print("Requesting result...")
ser.write(bytes([0x02]))          # CMD_RESULT
resp = ser.read(1)
if resp:
    print(f"Predicted class: {resp[0]}")
else:
    print("No response – check LEDs")
ser.close()
