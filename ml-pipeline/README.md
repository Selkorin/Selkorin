# SEVAS ML Pipeline

Image generation system based on FLUX.1 [pro] with custom LoRA styles.

## Directory Structure

```
ml-pipeline/
├── datasets/
│   └── smoke-cinematic/          # First style dataset
│       ├── raw/                  # Original downloaded images
│       ├── processed/            # Resized to 768x768 (for training)
│       ├── captions/             # Text descriptions (2-3 per image)
│       └── metadata.json         # Dataset info and status
│
├── training/
│   ├── configs/
│   │   └── smoke-cinematic-flux.json    # LoRA training hyperparameters
│   ├── logs/                     # TensorBoard logs
│   ├── checkpoints/              # Intermediate training checkpoints
│   └── results/                  # Final LoRA files (.safetensors)
│
├── validation/
│   ├── prompts/
│   │   └── smoke-cinematic.txt   # Test prompts for quality checking
│   └── results/                  # Generated validation images
│
└── README.md                      # This file
```

## Status: smoke-cinematic Style

| Phase | Status | Progress | Due |
|-------|--------|----------|-----|
| Dataset Collection | ⏳ Pending | 0/250 images | Week 3 |
| Caption Generation | ⏳ Pending | 0/250 captions | Week 4 |
| LoRA Training | ⏳ Pending | 0% | Week 5-6 |
| Quality Validation | ⏳ Pending | - | Week 7 |
| Production Deployment | ⏳ Pending | - | Week 8 |

## Quick Start

### 1. Collect Dataset (Week 3-4)

Download 250-300 images with smoke/dark atmospheric aesthetic from:
- **Unsplash**: unsplash.com (CC0) → ~80-120 images
- **Pexels**: pexels.com (CC0) → ~40-60 images
- **Pixabay**: pixabay.com (CC0) → ~40-60 images
- **Custom**: Your own photography → ~30-50 images

Save to: `datasets/smoke-cinematic/raw/`

```bash
# Example (manual download or via API)
curl https://unsplash.com/api/search/photos?query=dark+smoke \
  -H "Authorization: Bearer YOUR_KEY" \
  | jq '.results[].urls.raw' | xargs -I {} wget {}
```

**Quality Criteria**:
- Dark, moody aesthetic
- Visible smoke or fog effects
- Professional photography quality
- Varied angles, subjects, lighting
- Check licenses (CC0, CC-BY preferred)

### 2. Preprocess Images

Resize all images to 768x768:

```bash
# TODO: Create preprocessing script
python ml-scripts/preprocess-images.py \
  --input datasets/smoke-cinematic/raw \
  --output datasets/smoke-cinematic/processed \
  --size 768
```

### 3. Generate Captions

Create 2-3 text descriptions per image:

```bash
# TODO: Create captioning script (uses Claude API)
python ml-scripts/generate-captions.py \
  --images datasets/smoke-cinematic/processed \
  --output datasets/smoke-cinematic/captions \
  --style smoke-cinematic
```

Example captions for one image:
```
Caption 1: dark cinematic photograph with thick volumetric smoke, moody professional lighting
Caption 2: atmospheric smoky scene, dramatic chiaroscuro lighting, premium aesthetic
Caption 3: noir style image with heavy smoke effects, sophisticated color palette
```

### 4. Validate Dataset

Check quality before training:

```bash
# TODO: Create validation script
npm run validate:dataset smoke-cinematic
```

Expected output:
- ✅ 250+ valid 768x768 images
- ✅ No duplicates or corrupted files
- ✅ Each image has 2-3 captions
- ✅ Diversity score ≥ 0.85
- ✅ Quality score ≥ 0.85

### 5. Train LoRA

Start LoRA training using Kohya SS:

```bash
# Install Kohya SS
git clone https://github.com/kohya-ss/sd-scripts.git
cd sd-scripts && pip install -r requirements.txt

# Train
cd /path/to/Selkorin/ml-pipeline
python ../sd-scripts/train_network.py \
  --config_file training/configs/smoke-cinematic-flux.json
```

**Estimated time**: 8-12 hours on RTX 4090
**Estimated cost**: $20-30 on Lambda Labs

### 6. Validate Results

Test quality at each checkpoint:

```bash
# TODO: Create validation script
npm run validate:lora smoke-cinematic
```

This will:
- Load each checkpoint
- Generate images from validation prompts
- Compute quality metrics
- Save results to `validation/results/`

**Select checkpoint with best visual quality**, not lowest loss (overfitting risk).

### 7. Deploy

Move best LoRA to production:

```bash
cp training/results/smoke-cinematic-flux-best.safetensors \
   ../../src/ml/loras/smoke-cinematic.safetensors
```

## Next Steps

**TODAY (2026-06-20)**:
- [x] Create directory structure
- [x] Create config files (metadata.json, training config)
- [x] Create validation prompts
- [ ] Commit to git

**WEEK 3 (2026-06-24)**:
- [ ] Start collecting dataset (~50-100 images)
- [ ] Verify licenses
- [ ] Setup preprocessing pipeline

**WEEK 4 (2026-07-01)**:
- [ ] Complete dataset (250+ images)
- [ ] Generate all captions
- [ ] Run validation check

**WEEK 5-6 (2026-07-08)**:
- [ ] Rent GPU (Lambda Labs)
- [ ] Run LoRA training
- [ ] Monitor training progress

**WEEK 7 (2026-07-15)**:
- [ ] Validate quality on all checkpoints
- [ ] Select best checkpoint
- [ ] Generate example gallery

**WEEK 8 (2026-07-22)**:
- [ ] Deploy to production
- [ ] Integrate with web UI
- [ ] Monitor first user feedback

## Tools & Resources

### Dataset Collection
- Unsplash API: https://unsplash.com/developers
- Pexels API: https://www.pexels.com/api/
- Pixabay API: https://pixabay.com/api/docs/

### Training
- Kohya SS: https://github.com/kohya-ss/sd-scripts
- FLUX.1 Hugging Face: https://huggingface.co/black-forest-labs/FLUX.1-pro

### GPU Rental
- Lambda Labs: https://lambdalabs.com/ ($1.99/hr RTX A100)
- Fal.ai: https://fal.ai/ (good for inference)
- Replicate: https://replicate.com/ (FLUX.1 available)

## Parameters Reference

### LoRA Training
- **Model**: FLUX.1 [pro]
- **Resolution**: 768x768
- **Batch Size**: 2 (per GPU)
- **Learning Rate**: 0.0001
- **Total Steps**: 8000 (~50 epochs on 250 images)
- **LoRA Rank**: 32
- **LoRA Dropout**: 0.05
- **Optimizer**: AdamW 8-bit (memory efficient)

### Inference
- **Model**: FLUX.1 [pro]
- **Steps**: 12 (good balance speed/quality)
- **Guidance Scale**: 7.5 (follow prompt closely)
- **Time per image**: ~10-12 sec on RTX 4090

## Troubleshooting

### Out of Memory during training
- Reduce batch_size from 2 to 1
- Increase gradient_accumulation_steps from 2 to 4
- Use 8-bit optimizer (already enabled)

### Poor quality results
- Check dataset diversity (not all same type of image)
- Improve captions (more detailed, 30-50 words each)
- Ensure dataset has 250+ images
- Train longer or use higher learning rate

### Overfitting (model memorizes dataset)
- Select earlier checkpoint (step 4000 instead of 8000)
- Check validation loss curve (should not increase)
- Use more diverse dataset

## Files to Create

Priority order:
1. ✅ `metadata.json` - Dataset tracking
2. ✅ `smoke-cinematic-flux.json` - Training config
3. ✅ `smoke-cinematic.txt` - Validation prompts
4. ⏳ `preprocess-images.py` - Image preprocessing
5. ⏳ `generate-captions.py` - Caption generation
6. ⏳ `validate-dataset.py` - Dataset quality check
7. ⏳ `train-lora.py` - Training wrapper
8. ⏳ `validate-lora.py` - Quality validation

## Contributing

When adding new styles:
1. Create new folder: `datasets/{style-name}/`
2. Add `metadata.json` with style description
3. Create training config: `training/configs/{style-name}-flux.json`
4. Add validation prompts: `validation/prompts/{style-name}.txt`
5. Follow same training/validation pipeline
