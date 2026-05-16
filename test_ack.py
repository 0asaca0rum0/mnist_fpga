import serial, time, argparse
import numpy as np
import torch
from torchvision import datasets, transforms

def extract_zones(img):
    zones = img.reshape(4, 7, 4, 7)
    means = zones.mean(axis=(1, 3))
    scaled = np.round(means * 64).clip(0, 16320).astype(np.int32)
    return scaled.flatten()

class FPGA:
    def __init__(self, port='/dev/ttyUSB1', baud=9600):
        self.ser = serial.Serial(port, baud, timeout=2)

    def send_image(self, features, verbose=False):
        self.ser.write(bytes([0x01]))   # CMD_START
        time.sleep(0.001)
        for i, val in enumerate(features):
            lo, hi = val & 0xFF, (val >> 8) & 0xFF
            self.ser.write(bytes([lo, hi]))
            if verbose:
                print(f"  feature[{i}] = {val:5d}  -> 0x{lo:02x} 0x{hi:02x}")
            time.sleep(0.0001)

    def get_prediction(self, verbose=False):
        self.ser.write(bytes([0x02]))   # CMD_RESULT
        if verbose: print("  Sent CMD_RESULT (0x02)")
        b = self.ser.read(1)
        if b:
            if verbose: print(f"  Received byte: 0x{b[0]:02x}")
            return b[0]
        else:
            if verbose: print("  Timeout – no byte received")
            return None

    def close(self):
        self.ser.close()

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--port', default='/dev/ttyUSB1')
    parser.add_argument('--num-images', type=int, default=100)
    parser.add_argument('--verbose', action='store_true', help='Show sent/received bytes')
    args = parser.parse_args()

    # Load MNIST dataset
    test_ds = datasets.MNIST('./data/mnist', train=False, download=True,
                             transform=transforms.ToTensor())
    fpga = FPGA(args.port)

    # Statistics Trackers
    y_true = []
    y_pred = []
    latencies = []

    print(f"Starting hardware inference on {args.num_images} images...")

    for idx in range(args.num_images):
        img_tensor, label = test_ds[idx]
        img_arr = (img_tensor.squeeze().numpy() * 255).astype(np.uint8)
        feats = extract_zones(img_arr)

        if args.verbose:
            print(f"\nImage {idx} (true label {label}):")

        # Start timer
        start_time = time.time()
        
        fpga.send_image(feats, verbose=args.verbose)
        
        # Reduced sleep drastically since FPGA calculates in microseconds
        time.sleep(0.02)   
        
        pred = fpga.get_prediction(verbose=args.verbose)
        
        # Stop timer
        end_time = time.time()

        if pred is not None:
            if args.verbose:
                print(f"  Prediction: {pred}")
            # Keep progress updated on a single line if not verbose
            if not args.verbose:
                print(f"\rProcessing image {idx+1}/{args.num_images}...", end="")
                
            y_true.append(label)
            y_pred.append(pred)
            latencies.append(end_time - start_time)
        else:
            print(f"\nImage {idx}: No response from FPGA (Timeout)")

    fpga.close()

    # ==========================================
    # STATISTICS & REPORTING
    # ==========================================
    if len(y_pred) == 0:
        print("\nNo successful predictions to analyze.")
        exit()

    y_true = np.array(y_true)
    y_pred = np.array(y_pred)

    total_correct = np.sum(y_true == y_pred)
    total_images = len(y_true)
    overall_acc = 100 * total_correct / total_images

    print("\n\n" + "="*45)
    print("           FPGA ACCELERATOR RESULTS          ")
    print("="*45)
    print(f"Total Images Tested : {total_images}")
    print(f"Overall Accuracy    : {total_correct}/{total_images} ({overall_acc:.2f}%)")
    # Note: Latency includes Python USB overhead + UART transmission (9600 baud)
    print(f"Average Latency     : {np.mean(latencies)*1000:.2f} ms per frame") 

    # Per-class accuracy
    print("\n--- Per-Class Accuracy ---")
    for cls in range(10):
        cls_mask = (y_true == cls)
        cls_total = np.sum(cls_mask)
        if cls_total > 0:
            cls_correct = np.sum((y_pred == cls) & cls_mask)
            print(f" Digit {cls}: {cls_correct:3d} / {cls_total:3d} ({100*cls_correct/cls_total:5.1f}%)")

    # Confusion Matrix
    print("\n--- Confusion Matrix ---")
    print("       Predicted Class")
    print("       " + "   ".join([f"{i}" for i in range(10)]))
    print("     " + "-"*38)
    
    cm = np.zeros((10, 10), dtype=int)
    for t, p in zip(y_true, y_pred):
        if 0 <= p <= 9: # Safety check
            cm[t, p] += 1
    
    for i in range(10):
        row_str = " ".join([f"{val:3d}" for val in cm[i]])
        print(f" T {i} | {row_str}")
    print("="*45 + "\n")
