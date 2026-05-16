<div align="center">

<img src="https://capsule-render.vercel.app/api?type=waving&color=00599C&height=250&section=header&text=FPGA%20Neural%20Accelerator&fontSize=60&animation=fadeIn&fontAlignY=38&desc=Custom%20Hardware%20AI%20Inference&descAlignY=60&descAlign=62" width="100%" alt="Header Banner" />

<a href="https://github.com/DenverCoder1/readme-typing-svg">
    <img src="https://readme-typing-svg.herokuapp.com?font=Fira+Code&weight=600&size=20&pause=1000&color=36BCF7&center=true&vCenter=true&width=600&lines=Hardware+AI+Inference+in+Verilog;Weight-Stationary+Systolic+Array;Custom+Fixed-Point+Quantization;100MHz+Custom+RTL+Architecture;Sub-Microsecond+Compute+Latency" alt="Typing SVG" />
</a>

<p align="center">
  <strong>
    A custom hardware neural network accelerator designed entirely in Verilog,
    featuring a 4x4 Weight-Stationary Systolic Array and a Python/PyTorch bridge
    for ultra-fast MNIST digit recognition on FPGA.
  </strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Hardware-Verilog-00599C?style=for-the-badge&logo=intel" alt="Verilog" />
  <img src="https://img.shields.io/badge/Software-PyTorch-EE4C2C?style=for-the-badge&logo=pytorch" alt="PyTorch" />
  <img src="https://img.shields.io/badge/Architecture-Systolic_Array-blueviolet?style=for-the-badge" alt="Architecture" />
  <img src="https://img.shields.io/badge/Accuracy-79.8%25-success?style=for-the-badge" alt="Accuracy" />
  <img src="https://img.shields.io/badge/Compute_Time-%3C1μs-blue?style=for-the-badge" alt="Latency" />
</p>

</div>

---

# ⚡ FPGA Neural Accelerator

This project implements a complete end-to-end Machine Learning inference pipeline on FPGA.

A PyTorch-trained Multi-Layer Perceptron (MLP) is quantized into fixed-point integer arithmetic and executed physically on custom RTL hardware using a **Weight-Stationary Systolic Array** architecture.

The design was written entirely in Verilog and deployed on FPGA hardware running at **100 MHz**.

---

# 🧠 Project Highlights

- Custom RTL neural accelerator in Verilog
- 4×4 Weight-Stationary systolic array
- Fixed-point quantized inference (`Q8.7`)
- Fully hardware-based matrix multiplication
- UART communication protocol
- PyTorch-to-FPGA deployment pipeline
- Sub-microsecond compute time
- End-to-end FPGA inference testing

---

# 🛠 Tech Stack

<div align="center">

<a href="https://skillicons.dev">
<img src="https://skillicons.dev/icons?i=python,pytorch,c,linux,github&theme=dark" alt="Tech Stack" />
</a>

<br><br>

<img src="https://img.shields.io/badge/RTL-Verilog-orange?style=flat-square" />
<img src="https://img.shields.io/badge/ML-PyTorch-red?style=flat-square" />
<img src="https://img.shields.io/badge/Communication-UART-green?style=flat-square" />
<img src="https://img.shields.io/badge/Deployment-FPGA-blue?style=flat-square" />
<img src="https://img.shields.io/badge/Math-Fixed_Point-purple?style=flat-square" />

</div>

---

# 🏗 Hardware Architecture

The FPGA accelerator is composed of several tightly integrated hardware modules.

GitHub automatically renders the Mermaid diagram below:

```mermaid
graph TD;

    PC[PC / Python Host] <-->|UART 9600 Baud| UART[cmd_parser.v]

    UART -->|16 Features| CTRL[systolic_control.v]

    ROM[ROM.v] -->|Weights & Biases| CTRL

    CTRL -->|Load Weights| SA[sys_arr_4x4.v]

    SA -->|Partial Sums| CTRL

    CTRL -->|Argmax Result| UART

    PE[pe.v] --> SA
