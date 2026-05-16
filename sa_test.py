"""
sa_test.py – send a 4x4 weight matrix and 4-element input vector to the FPGA,
             receive the 4x1 result vector and compare with expected.
"""

import serial, time, argparse, struct, random, sys

def matvec_mult(w, x):
    """w: 4x4 list of lists of ints, x: 4 ints. Returns 4 ints (32-bit)."""
    res = [0,0,0,0]
    for i in range(4):
        for j in range(4):
            res[i] += w[i][j] * x[j]
    return res

parser = argparse.ArgumentParser()
parser.add_argument('--port', default='/dev/ttyUSB1')
args = parser.parse_args()

# Generate a random test
random.seed(42)
weights = [[random.randint(-128,127) for _ in range(4)] for _ in range(4)]
inputs = [random.randint(0,16320) for _ in range(4)]  # typical Q8.7 input range

print("Weight matrix:")
for row in weights:
    print(f"  {[f'{v:4d}' for v in row]}")
print(f"Input vector: {inputs}")
expected = matvec_mult(weights, inputs)
print(f"Expected output: {expected}")

ser = serial.Serial(args.port, 9600, timeout=2)

# Send command 0x10
ser.write(bytes([0x10]))
time.sleep(0.001)

# Send weights (row-major, 16-bit LE)
for row in weights:
    for w in row:
        val = w & 0xFFFF
        ser.write(bytes([val & 0xFF, (val >> 8) & 0xFF]))
        time.sleep(0.0001)

# Send inputs (4 values, 16-bit LE)
for x in inputs:
    val = x & 0xFFFF
    ser.write(bytes([val & 0xFF, (val >> 8) & 0xFF]))
    time.sleep(0.0001)

time.sleep(0.1)  # let FPGA compute

# Receive 16 bytes (4 x 32-bit LE)
data = ser.read(16)
if len(data) < 16:
    print(f"Timeout: received {len(data)} bytes: {data.hex()}")
    sys.exit(1)

# Parse
results = []
for i in range(4):
    val = int.from_bytes(data[i*4:(i+1)*4], byteorder='little', signed=True)
    results.append(val)

print(f"Received output: {results}")

# Compare
match = all(a == b for a,b in zip(results, expected))
print("PASS" if match else "FAIL")

ser.close()
