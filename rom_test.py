"""
rom_test.py – sends an address (0-1241), reads the 16-bit ROM value back.
Compares against expected values from the .mem files.
"""

import serial, time, argparse, sys

# Load expected data from .mem files
def load_mem(filename):
    data = []
    with open(filename, 'r') as f:
        for line in f:
            line = line.strip()
            if line:
                data.append(int(line, 16))
    return data

# Map address to expected value
w1 = load_mem('./mem/w1.mem')  # 512 entries
b1 = load_mem('./mem/b1.mem')  # 32
w2 = load_mem('./mem/w2.mem')  # 512
b2 = load_mem('./mem/b2.mem')  # 16
w3 = load_mem('./mem/w3.mem')  # 160
b3 = load_mem('./mem/b3.mem')  # 10

full_mem = w1 + b1 + w2 + b2 + w3 + b3
print(f"Total ROM size: {len(full_mem)} entries (should be 1242)")

if len(full_mem) != 1242:
    print("ERROR: ROM data size mismatch. Check .mem files.")
    sys.exit(1)

# Connect to FPGA
parser = argparse.ArgumentParser()
parser.add_argument('--port', default='/dev/ttyUSB1', help='Serial port')
parser.add_argument('--start', type=int, default=0, help='Start address')
parser.add_argument('--count', type=int, default=5, help='Number of addresses to test')
args = parser.parse_args()

ser = serial.Serial(args.port, 9600, timeout=2)

passed = 0
failed = 0
for addr in range(args.start, min(args.start + args.count, len(full_mem))):
    # Send command 0x03 then address low, high
    ser.write(bytes([0x03]))
    time.sleep(0.001)
    ser.write(bytes([addr & 0xFF, (addr >> 8) & 0xFF]))
    time.sleep(0.001)

    # Read response (2 bytes: low, high)
    resp = ser.read(2)
    if len(resp) < 2:
        print(f"Addr {addr:4d}: Timeout or incomplete response")
        failed += 1
        continue

    data_received = resp[0] | (resp[1] << 8)
    expected = full_mem[addr]
    match = "OK" if data_received == expected else "FAIL"
    print(f"Addr {addr:4d}: expected 0x{expected:04x}, received 0x{data_received:04x} {match}")
    if data_received == expected:
        passed += 1
    else:
        failed += 1

ser.close()
print(f"\nPassed: {passed}, Failed: {failed}")
