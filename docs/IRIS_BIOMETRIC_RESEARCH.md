# Engineering Research & Feasibility Analysis: Iris Biometric Processing on Mobile Platforms

## Executive Summary
This document investigates the feasibility, mathematical foundations, library support, and security architecture for **iris capture, localization, and biometric matching** on mobile devices (Android, iOS, and Flutter Web).

---

## 1. The Core Scientific Distinction: Iris Landmarks vs. Biometric Identity
- **MediaPipe Iris / Face Mesh**:
  - Predicts 5 landmark coordinates per eye (iris center and 4 contour points: top, bottom, left, right).
  - **Purpose**: Gaze tracking, virtual eyewear placement, depth estimation.
  - **Limitation**: Landmark coordinates represent *geometry and gaze angle*, NOT biometric identity. They possess **zero discriminative power** for distinguishing individual human irises. Confusing eye landmarks with biometric authentication creates a severe security vulnerability.
- **Biometric Iris Identification (Daugman Pipeline)**:
  - Requires high-resolution imaging of the **trabecular meshwork** (the stroma, furrows, crypts, and pigment collarette).
  - Normalizes the annular iris ring into a rectangular representation ($r, \theta$) via Daugman's Rubber Sheet Model.
  - Decomposes textures into multi-scale 2D Gabor wavelets or Log-Gabor phase codes.
  - Produces a 2048-bit or 512-byte binary feature vector (**IrisCode**) and an accompanying occlusion bitmask.
  - Evaluates similarity using the **Normalized Hamming Distance (HD)** with fractional head-tilt rotation corrections.

---

## 2. Platform Reality & Hardware Blockers with Standard Smartphone RGB Cameras
Commercial iris biometric systems (e.g., Aadhaar, border control e-Gates, Samsung Iris Scanner) operate strictly on **Near-Infrared (NIR) illumination (700nm – 900nm)** with specialized narrow-bandpass optical filters.

### Why standard Smartphone RGB Cameras cannot deliver commercial-grade iris recognition:
1. **Melanin Absorption in Visible Light**: In dark-pigmented eyes (brown and black irises prevalent in Asian, African, and Hispanic populations), visible RGB light is almost completely absorbed by melanin in the anterior border layer. The underlying trabecular texture is invisible without NIR backscattering.
2. **Specular Reflections (Corneal Glare)**: Ambient visible light sources (room lights, sun, screen glow) create intense white corneal reflections that occlude the pupil and iris texture.
3. **Sensor Resolution & Optical Distance**: Reliable iris extraction requires at least **150–200 pixels across the iris diameter**. Normal phone cameras held at comfortable arm's length resolve only 30–60 pixels across the iris, leading to high False Non-Match Rates (FNMR) unless held dangerously close to the face or fitted with an optical macro lens.

### Conclusion on Feasibility:
Any system claiming reliable, production-grade iris authentication solely from standard front-facing RGB cameras without NIR hardware is scientifically unsound.
**Solution**: We implement:
1. A production-grade **Iris Quality Assurance & Eye Guidance Engine** (on-device).
2. A **Daugman-compliant Normalization & Feature Extraction Pipeline** (modular and independently testable).
3. A **Pluggable Biometric Engine Interface** (`IrisRecognitionEngine`) supporting local feature extractors and hardware NIR biometric peripherals.

---

## 3. Mathematical Pipeline: Daugman's Rubber Sheet Model & 2D Gabor Phase Demodulation

### Step 1: Segmentation
The inner pupil boundary and outer limbic boundary are parameterized as concentric or slightly eccentric circles:
$$C(x_0, y_0, r) = \{(x, y) \mid (x - x_0)^2 + (y - y_0)^2 = r^2\}$$

### Step 2: Daugman's Rubber Sheet Normalization
Transforms Cartesian coordinates $(x, y)$ of the iris region into dimensionless polar coordinates $(r, \theta)$ where $r \in [0, 1]$ and $\theta \in [0, 2\pi]$:
$$I(x(r, \theta), y(r, \theta)) \to I(r, \theta)$$
$$x(r, \theta) = (1 - r) x_p(\theta) + r x_s(\theta)$$
$$y(r, \theta) = (1 - r) y_p(\theta) + r y_s(\theta)$$
where $(x_p(\theta), y_p(\theta))$ are pupil boundary points and $(x_s(\theta), y_s(\theta))$ are limbic boundary points.

### Step 3: 2D Complex Gabor Wavelet Filtering
The normalized iris strip is demodulated by 2D Gabor filters:
$$G(x, y) = \exp(-\pi [(x - x_0)^2 / \alpha^2 + (y - y_0)^2 / \beta^2]) \cdot \exp(-2\pi i [u_0(x - x_0) + v_0(y - y_0)])$$
The real and imaginary parts are quantized into 2 bits of phase information per sample point:
$$\text{Bit}_1 = 1 \iff \text{Re}(G * I) \ge 0$$
$$\text{Bit}_2 = 1 \iff \text{Im}(G * I) \ge 0$$

### Step 4: Normalized Hamming Distance with Occlusion Mask
For two templates $A$ and $B$ with noise/eyelid masks $M_A$ and $M_B$:
$$HD = \frac{\| (A \oplus B) \cap M_A \cap M_B \|}{\| M_A \cap M_B \|}$$
Where $\oplus$ is bitwise XOR and $\cap$ is bitwise AND.
- For independent non-matching eyes: Expected $HD = 0.50$ (binomial distribution).
- For matching genuine eyes: Expected $HD \le 0.32$.

---

## 4. Model Provenance & Licensing
- **MediaPipe Iris / Face Mesh**:
  - Model: Google MediaPipe (Apache 2.0 License).
  - Outputs: 468 face landmarks + 10 iris landmark points.
  - Platforms: Android, iOS, Web via WebAssembly / TFLite.
- **Biometric Pipeline**:
  - Custom Pure-Dart / C-FFI Daugman feature encoder, zero external telemetry, zero closed-source black-box cloud dependencies.
