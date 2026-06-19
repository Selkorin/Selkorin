# SEVAS Detailed Roadmap (90 Days)

**Project**: Собственная система генерации изображений SEVAS  
**Status**: ✅ Архитектура завершена, ready for implementation  
**Timeline**: 12 недель (от 2026-06-20 до 2026-09-12)

---

## 📊 High-Level Timeline

```
Week  1-2   | 3-4  | 5-6 | 7-8  | 9-10 | 11-12
MVP Gen    | Dataset | LoRA | WebUI | Styles | Prod
Complete  | Ready  | Ready | Ready | Ready | Ready
```

---

## WEEK 1-2: Local Generation MVP (June 20 - July 3)

### Deliverables
- ✅ Backend: POST /api/images/generate endpoint (working)
- ✅ FLUX.1 model loaded and generating images
- ✅ Basic React UI for prompt input
- ✅ Images saved to disk with metadata
- ✅ No critical errors, no OOM issues

### Detailed Tasks

#### Day 1 (June 20) - TODAY
- [x] Create directory structure (`ml-pipeline/`, `docs/`, etc.)
- [x] Create config files (metadata.json, training configs)
- [x] Create documentation (SEVAS_ARCHITECTURE.md, QUALITY_CRITERIA.md)
- [x] Commit to git
- [ ] Next: Backend integration

**Time**: 4-5 hours  
**Status**: ✅ DONE

---

#### Days 2-3 (June 21-22)

**Backend Setup**:
- [ ] Create `src/services/image-generation/ImageGenerationService.ts`
  - Basic class structure
  - TODO: Python subprocess integration
  - Memory management for model

- [ ] Create `src/services/image-generation/ModelManager.ts`
  - Load FLUX.1 model (lazy load, keep in memory)
  - Handle OOM errors gracefully
  - Cache model instance

- [ ] Create `src/controllers/ImageGenerationController.ts`
  - POST /api/images/generate endpoint
  - Validate request, check rate limits
  - Return image URL + metadata

- [ ] Update Express routes to include new controller

- [ ] Create `src/entities/GeneratedImage.ts` (TypeORM)
  - Save generation metadata to database

**Testing**:
- Manual test: generate 1 image via API
- Check: image saved to disk, no errors

**Estimated time**: 6-8 hours

---

#### Days 4-5 (June 23-24)

**Frontend Integration**:
- [ ] Create page `web/src/pages/ImageGeneration.tsx`
  - Simple layout: prompt input + generate button + results

- [ ] Create component `web/src/components/ImageGenerator/Prompt.tsx`
  - Textarea for prompt
  - "Generate" button (disabled while processing)
  - Show error if any

- [ ] Create component `web/src/components/ImageGenerator/Results.tsx`
  - Display generated image
  - Show loading state
  - Show generation time

- [ ] Connect to API endpoint

**Testing**:
- [ ] Manual test: submit prompt → see image generated
- [ ] Check: image displayed in browser
- [ ] Check: no console errors

**Estimated time**: 4-6 hours

---

#### Days 6-7 (June 25-26) - Weekend/Buffer

**Optimization & Testing**:
- [ ] Add queue system (prevent 3+ concurrent generations)
- [ ] Enable xformers attention (faster, less VRAM)
- [ ] Test 5+ consecutive generations (check for memory leaks)
- [ ] Test with different prompts

**Success Criteria**:
- ✅ Can generate images via API and web UI
- ✅ No OOM errors after 5+ generations
- ✅ Images save correctly
- ✅ Database has all metadata
- ✅ No critical bugs

---

### Week 1-2 Deliverables Summary

**Files created**:
- `src/services/image-generation/ImageGenerationService.ts`
- `src/services/image-generation/ModelManager.ts`
- `src/controllers/ImageGenerationController.ts`
- `src/entities/GeneratedImage.ts`
- `web/src/pages/ImageGeneration.tsx`
- `web/src/components/ImageGenerator/Prompt.tsx`
- `web/src/components/ImageGenerator/Results.tsx`

**Database**:
- Migration: Create `generated_images` table

**Testing**:
- ✅ E2E: prompt → generation → save → display

---

## WEEK 3-4: Dataset "Дымное фото" (July 7 - July 20)

### Deliverables
- ✅ 250+ smoke-cinematic images collected
- ✅ All images 768x768, preprocessed
- ✅ 2-3 captions per image (generated)
- ✅ Dataset validated (quality_score ≥ 0.85)
- ✅ Ready for training

### Detailed Tasks

#### Days 1-2 (July 7-8)

**Image Collection**:
- [ ] Download from Unsplash (~80-100 images)
  - Search: "dark smoke", "cinematic smoke", "noir photography"
  - API or manual download
  - Save to `ml-pipeline/datasets/smoke-cinematic/raw/`

- [ ] Download from Pexels (~40-60 images)
  - Similar searches

- [ ] Download from Pixabay (~40-60 images)

- [ ] Collect custom images if available (~30 images)

**License Check**:
- ✅ Verify all have CC0 or CC-BY license
- ✅ Save license info in metadata

**Target**: 200-250 images in `raw/` folder

**Estimated time**: 4-6 hours

---

#### Days 3-4 (July 9-10)

**Image Preprocessing**:
- [ ] Create `ml-scripts/preprocess-images.py`
  ```python
  - Load image
  - Resize to 768x768 (keep aspect ratio or crop center)
  - Convert to PNG/JPG
  - Save to processed/
  ```

- [ ] Run preprocessing on all collected images

- [ ] Verify: all 250+ files in `processed/` folder, all 768x768

**Estimated time**: 2-3 hours

---

#### Day 5 (July 11) - Friday

**Caption Generation**:
- [ ] Create `ml-scripts/generate-captions.py`
  ```python
  - For each image:
    - Use Claude API to generate 2-3 captions
    - Captions should mention: smoke, dark, cinematic, mood
    - Save to captions/{number}.txt (one prompt per line)
  ```

- [ ] Example prompt for Claude:
  ```
  Ты — эксперт по描述 фотографий для Stable Diffusion.
  Напиши 3 разных промта (20-40 слов каждый) для этого изображения.
  
  Требования:
  - На английском
  - Фокус на дымность, темноту, кинематичность
  - Натуральный язык, без "trending on artstation"
  - Примеры слов: volumetric, cinematic, dark, moody, smoke, shadows
  ```

- [ ] Run for all 250+ images

**Cost**: ~$1-2 (Claude API calls)

**Estimated time**: 4-5 hours

---

#### Days 6-7 (July 12-13)

**Dataset Validation**:
- [ ] Create `ml-scripts/validate-dataset.py`
  ```python
  class DatasetValidator:
    - Check all images are 768x768
    - Check all have captions
    - Check no duplicates (perceptual hash)
    - Analyze color diversity
    - Generate quality report
  ```

- [ ] Run validation
  ```bash
  python ml-scripts/validate-dataset.py \
    --dataset ml-pipeline/datasets/smoke-cinematic
  ```

- [ ] Expected output:
  ```json
  {
    "total_images": 250,
    "valid_images": 250,
    "errors": [],
    "quality_score": 0.87,
    "status": "approved"
  }
  ```

- [ ] If quality_score < 0.85: add more images or fix issues

**Estimated time**: 2-3 hours

---

### Week 3-4 Deliverables Summary

**Folder structure**:
```
ml-pipeline/datasets/smoke-cinematic/
├── raw/           (250+ original images)
├── processed/     (250+ resized 768x768)
├── captions/      (250+ text files with 2-3 prompts each)
├── metadata.json  (updated with totals)
└── quality_report.json (validation results)
```

**Files created**:
- `ml-scripts/preprocess-images.py`
- `ml-scripts/generate-captions.py`
- `ml-scripts/validate-dataset.py`

**Success Criteria**:
- ✅ 250+ validated images
- ✅ Each with 2-3 quality captions
- ✅ No duplicates or corrupted files
- ✅ Quality score ≥ 0.85

---

## WEEK 5-6: LoRA Training (July 21 - Aug 3)

### Deliverables
- ✅ LoRA trained on smoke-cinematic dataset
- ✅ Best checkpoint selected (quality-based)
- ✅ LoRA file saved: `smoke-cinematic-flux-v1.safetensors` (~100MB)
- ✅ Quality validated: avg 7.5-8.5/10

### Prerequisites
- Lambda Labs account with GPU rental active
- RTX A100 40GB (~$2/hr) or RTX 6000 (~$4/hr)
- Budget: $20-30 for full training

### Detailed Tasks

#### Days 1-2 (July 21-22)

**Setup**:
- [ ] Rent GPU on Lambda Labs
  - Choose: RTX A100 40GB ($1.99/hr)
  - Request: Ubuntu 20.04 instance
  - Get: IP, SSH access

- [ ] SSH into instance and setup:
  ```bash
  ssh ubuntu@<instance-ip>
  
  # Install dependencies
  curl https://raw.githubusercontent.com/pyenv/pyenv-installer/master/bin/pyenv-installer | bash
  pyenv install 3.10.12
  
  # Clone kohya-ss
  git clone https://github.com/kohya-ss/sd-scripts.git
  cd sd-scripts
  pip install -r requirements.txt
  pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu118
  
  # Download FLUX.1 checkpoint (large!)
  # Use huggingface_hub or manual download
  huggingface-cli download black-forest-labs/FLUX.1-pro \
    --cache-dir /tmp/models
  ```

- [ ] Copy dataset to instance
  ```bash
  scp -r ml-pipeline/datasets/smoke-cinematic ubuntu@<ip>:/home/ubuntu/data/
  ```

- [ ] Copy training config
  ```bash
  scp ml-pipeline/training/configs/smoke-cinematic-flux.json \
    ubuntu@<ip>:/home/ubuntu/config.json
  ```

**Estimated time**: 1-2 hours

---

#### Days 3-5 (July 23-25)

**Training**:
- [ ] Start training on GPU instance:
  ```bash
  cd ~/sd-scripts
  python train_network.py \
    --config_file ~/config.json \
    --output_dir ~/lora_results \
    --save_state_dir ~/checkpoints
  ```

- [ ] Monitor training:
  ```bash
  # In another SSH session
  watch -n 10 nvidia-smi  # GPU usage
  tail -f ~/training.log   # Loss logs
  ```

- [ ] Expected timeline:
  - 0-1h: Setup and compilation
  - 1-8h: Actual training (8000 steps)
  - Total: ~8-12 hours

- [ ] Checkpoints saved every 500 steps:
  ```
  checkpoints/
  ├── step_500/
  ├── step_1000/
  ├── step_4000/   ← Likely best
  ├── step_6000/
  └── step_8000/
  ```

**Estimated cost**: $16-24 GPU rental

---

#### Days 6-7 (July 26-27)

**Validation & Selection**:
- [ ] Create `ml-scripts/validate-lora.py`
  ```python
  def validate_checkpoint(checkpoint_path, prompts, output_dir):
    - Load checkpoint
    - Generate images from 10 validation prompts
    - Score each image (0-10)
    - Save results to output_dir
    - Return average score
  ```

- [ ] Validate each checkpoint:
  ```bash
  for checkpoint in step_500 step_1000 step_4000 step_6000 step_8000; do
    python validate-lora.py \
      --checkpoint checkpoints/$checkpoint \
      --prompts validation/prompts/smoke-cinematic.txt \
      --output validation/results/$checkpoint
  done
  ```

- [ ] Compare results:
  ```
  step_500:  quality 5.2/10 (too early)
  step_1000: quality 6.8/10 (getting better)
  step_4000: quality 8.4/10 ⭐ BEST
  step_6000: quality 8.2/10 (plateau)
  step_8000: quality 7.8/10 (overfitting)
  ```

- [ ] Select best checkpoint: **step_4000**

- [ ] Download final LoRA:
  ```bash
  scp ubuntu@<ip>:~/checkpoints/step_4000/smoke_cinematic_flux.safetensors \
    ml-pipeline/training/results/
  ```

- [ ] Copy to production:
  ```bash
  cp ml-pipeline/training/results/smoke_cinematic_flux.safetensors \
    src/ml/loras/smoke-cinematic.safetensors
  ```

**Estimated time**: 4-6 hours

---

### Week 5-6 Deliverables Summary

**Files**:
- `ml-pipeline/training/results/smoke-cinematic-flux-v1.safetensors` (~100MB)
- `ml-pipeline/validation/results/step_*/` (validation images and scores)
- `src/ml/loras/smoke-cinematic.safetensors` (production copy)

**Database**:
- Create `lora_versions` table tracking models and versions

**Success Criteria**:
- ✅ LoRA trained successfully
- ✅ Average quality ≥ 7.5/10
- ✅ No artifacts on test prompts
- ✅ Style consistency clear

---

## WEEK 7-8: Web UI & Integration (Aug 4 - Aug 17)

### Deliverables
- ✅ StyleSelector component with smoke-cinematic option
- ✅ LoRA loaded and applied in generations
- ✅ Image gallery with filtering and favorites
- ✅ All integrated, tested, and working

### Detailed Tasks

#### Days 1-2 (Aug 4-5)

**Style Integration**:
- [ ] Update `src/services/image-generation/LoRAManager.ts`
  ```typescript
  class LoRAManager {
    private registry = {
      "smoke-cinematic": {
        path: "src/ml/loras/smoke-cinematic.safetensors",
        weight: 1.0,
        status: "active"
      }
    };
    
    async loadLoRA(styleId: string): Promise<any> {
      // Load from registry
      // Handle errors gracefully
    }
  }
  ```

- [ ] Update ImageGenerationService to use LoRA

- [ ] Test: generation with LoRA applied

**Estimated time**: 2-3 hours

---

#### Days 3-4 (Aug 6-7)

**Frontend Components**:
- [ ] Create `web/src/components/StyleSelector.tsx`
  ```typescript
  - Dropdown with styles
  - Preview image for each style
  - Save selection to localStorage
  - Show trigger words hint
  ```

- [ ] Update PromptBuilder with style-specific help
  ```typescript
  - When style changes, show example prompts
  - Auto-add trigger words to prompt
  - Show "Enhance with Claude" button
  ```

- [ ] Create ResultsGallery improvements:
  ```typescript
  - Grid display (3 columns)
  - Like/Unlike
  - Download as PNG
  - Copy prompt
  - Add to favorites
  ```

**Estimated time**: 4-6 hours

---

#### Days 5-7 (Aug 8-10)

**Gallery & History**:
- [ ] Create `/api/images/library` endpoint
  ```
  GET /api/images/library?page=1&limit=20&style=smoke-cinematic
  Response: { total, images: [...] }
  ```

- [ ] Create `web/src/pages/ImageLibrary.tsx`
  - All user's generated images
  - Filter by style
  - Search by prompt
  - Sort by date, likes
  - Export options

- [ ] Add to database:
  ```sql
  ALTER TABLE generated_images ADD liked BOOLEAN DEFAULT false;
  ALTER TABLE generated_images ADD tags TEXT[];
  ALTER TABLE generated_images ADD notes TEXT;
  ```

- [ ] E2E Testing:
  - Generate image → check appears in library
  - Like image → check like persists
  - Filter by style → works correctly

**Estimated time**: 6-8 hours

---

### Week 7-8 Deliverables Summary

**Components created**:
- `web/src/components/StyleSelector.tsx`
- `web/src/components/ResultsGallery.tsx` (improved)
- `web/src/pages/ImageLibrary.tsx`

**Endpoints created**:
- GET /api/images/styles
- GET /api/images/library
- PUT /api/images/{id} (like, tags)

**Success Criteria**:
- ✅ Can select smoke-cinematic style
- ✅ LoRA applied to generations
- ✅ Gallery shows all images
- ✅ Can like and filter images
- ✅ No critical bugs

---

## WEEK 9-10: Additional Styles (Aug 18 - Aug 31)

### Deliverables
- ✅ 2-3 additional styles fully trained and integrated
- ✅ Each style has ≥ 7/10 average quality
- ✅ UI supports style switching

### Process for Each Style

**Repeat 2-3 times**:

1. **Dataset** (Days 1-2): Collect 250+ images
2. **Preprocessing** (Day 3): Resize, validate
3. **Captions** (Day 4): Generate descriptions
4. **Training** (Days 5-7): Kohya SS LoRA training
5. **Validation** (Day 8): Quality check
6. **Integration** (Day 9): Add to UI

### Recommended Styles

**Style #2: Cinematic Poster**
- Bold colors, dramatic composition
- Use cases: Movie posters, marketing
- Trigger: "cinemaposters", "posterart"

**Style #3: Luxury Minimal**
- Clean, premium aesthetic
- Use cases: Product shots, fashion
- Trigger: "luxuryminimal", "premiumaesthetic"

**Style #4 (Optional): Concept Art**
- Futuristic, detailed, digital painting
- Trigger: "conceptart", "scifiart"

---

## WEEK 11-12: Production & Optimization (Sept 1-12)

### Deliverables
- ✅ System optimized for production
- ✅ Deployed to cloud (or optimized locally)
- ✅ Security review completed
- ✅ Full documentation
- ✅ Ready for users

### Detailed Tasks

#### Days 1-3 (Sept 1-3)

**Optimization**:
- [ ] Enable FP8 quantization (reduce VRAM 24GB → 12GB)
- [ ] Enable tensor offloading
- [ ] Add result caching (same prompt → same image)
- [ ] Batch generation for queue

**Expected improvement**:
- VRAM: 24GB → 12GB
- Speed: no change (still 10-12 sec/image)
- Cost: lower hardware requirements

---

#### Days 4-5 (Sept 4-5)

**Cloud Deployment**:
- [ ] Choose deployment option:
  - **Option A**: Replicate API (simple, $0.04/image)
  - **Option B**: Lambda Labs (own GPU, $0.0001/image at scale)
  - **Option C**: Self-hosted on RTX 4090 ($1500 one-time)

- [ ] Set up S3 for image storage
  - Create bucket: `sevas-images`
  - Configure CORS
  - Add lifecycle policies (delete old images)

- [ ] Docker container
  ```dockerfile
  FROM pytorch/pytorch:2.0-cuda11.8-devel-ubuntu22.04
  
  COPY requirements.txt .
  RUN pip install -r requirements.txt
  
  COPY src /app/src
  COPY ml /app/ml
  
  EXPOSE 3000
  CMD ["npm", "run", "start"]
  ```

**Estimated time**: 4-6 hours

---

#### Days 6-7 (Sept 6-7)

**Security & Documentation**:
- [ ] Security review:
  - [ ] Prompt validation (no injection)
  - [ ] Rate limiting (10 requests/min per user)
  - [ ] Auth checks on endpoints
  - [ ] File upload validation

- [ ] Documentation:
  - [ ] README with setup instructions
  - [ ] API documentation
  - [ ] Deployment guide
  - [ ] Troubleshooting guide
  - [ ] FAQ

- [ ] Testing:
  - [ ] Load test (10+ concurrent users)
  - [ ] Quality test (all styles)
  - [ ] Error handling test
  - [ ] Security audit

**Estimated time**: 6-8 hours

---

### Week 11-12 Deliverables Summary

**Files**:
- `Dockerfile` (production container)
- `DEPLOYMENT.md` (deployment guide)
- `API_DOCS.md` (API reference)
- `.env.production` (config template)

**Metrics**:
- ✅ 0 critical security issues
- ✅ 99%+ uptime expected
- ✅ &lt;2 sec response time (not including generation)
- ✅ &lt;$1 cost per image at scale

---

## 🎯 Success Criteria by Phase

### MVP (Week 1-2)
- ✅ API generates images
- ✅ Images save correctly
- ✅ No memory leaks
- ✅ Basic UI works

### Dataset (Week 3-4)
- ✅ 250+ validated images
- ✅ Quality score ≥ 0.85
- ✅ Captions ready

### LoRA (Week 5-6)
- ✅ Model trained
- ✅ Quality ≥ 7.5/10
- ✅ No overfitting

### Integration (Week 7-8)
- ✅ Style selector works
- ✅ Gallery functional
- ✅ No bugs

### Styles (Week 9-10)
- ✅ 3-4 styles active
- ✅ Each ≥ 7/10 quality
- ✅ UI updated

### Production (Week 11-12)
- ✅ Deployed
- ✅ Documented
- ✅ Secure
- ✅ Ready for users

---

## 📝 Files to Create (Priority Order)

### WEEK 1-2:
1. ✅ `docs/SEVAS_ARCHITECTURE.md`
2. ✅ `docs/QUALITY_CRITERIA.md`
3. ✅ `ml-pipeline/README.md`
4. [ ] `src/services/image-generation/ImageGenerationService.ts`
5. [ ] `src/services/image-generation/ModelManager.ts`
6. [ ] `src/controllers/ImageGenerationController.ts`

### WEEK 3-4:
7. [ ] `ml-scripts/preprocess-images.py`
8. [ ] `ml-scripts/generate-captions.py`
9. [ ] `ml-scripts/validate-dataset.py`

### WEEK 5-6:
10. [ ] `ml-scripts/validate-lora.py`
11. [ ] Database migrations

### WEEK 7-8:
12. [ ] `web/src/pages/ImageGeneration.tsx`
13. [ ] `web/src/components/StyleSelector.tsx`
14. [ ] `web/src/pages/ImageLibrary.tsx`
15. [ ] `src/services/image-generation/LoRAManager.ts`

### WEEK 11-12:
16. [ ] `Dockerfile`
17. [ ] `DEPLOYMENT.md`
18. [ ] `API_DOCS.md`

---

## 💰 Budget Estimate

| Item | Cost | When |
|------|------|------|
| GPU Rental (LoRA training) | $20-30 | Week 5-6 |
| GPU Rental (3 more LoRAs) | $60-90 | Week 9-10 |
| S3 Storage (first month) | $5-10 | Week 11 |
| Domain/Hosting | $10-50 | Ongoing |
| **Total MVP** | **$95-180** | Week 11 |

**Per-image cost (at scale)**:
- Cloud API (Replicate): $0.04/image
- Self-hosted: $0.0001/image (after $1500 GPU purchase)

---

## 🚀 Launch Checklist

- [ ] All code committed and pushed
- [ ] Tests passing (unit + e2e)
- [ ] Security audit complete
- [ ] Documentation complete
- [ ] Performance tested (load test)
- [ ] Monitoring set up (errors, uptime)
- [ ] Backup strategy defined
- [ ] Rollback plan ready
- [ ] User feedback mechanism
- [ ] Analytics tracking

---

## 📞 Questions & Support

If stuck on any phase:

1. **MVP (Week 1-2)**: Check `SEVAS_ARCHITECTURE.md` for component details
2. **Dataset (Week 3-4)**: See `ml-pipeline/README.md` for sources
3. **LoRA Training (Week 5-6)**: Reference `training/configs/smoke-cinematic-flux.json`
4. **Quality Issues**: Use `QUALITY_CRITERIA.md` scoring rubric
5. **Deployment**: Check `DEPLOYMENT.md` (when created)

---

**Good luck! SEVAS is going to be amazing! 🎨**
