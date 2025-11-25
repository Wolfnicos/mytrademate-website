# GodModel v6 Training Container
# ================================
# Complete environment for training GodModel v6

FROM tensorflow/tensorflow:2.14.0-gpu

# Set working directory
WORKDIR /training

# Install system dependencies
RUN apt-get update && apt-get install -y \
    git \
    wget \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Install Python dependencies
COPY requirements.txt /training/
RUN pip install --no-cache-dir -r requirements.txt

# Copy training scripts
COPY feature_engineering_v6.py /training/
COPY train_god_model.py /training/
COPY quantize_to_tflite.py /training/

# Create output directory
RUN mkdir -p /training/trained_models

# Default command: full training pipeline
CMD ["bash", "-c", "python train_god_model.py && python quantize_to_tflite.py"]
