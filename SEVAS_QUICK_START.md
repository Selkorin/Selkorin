# SEVAS Quick Start Guide

**Read this first!** Everything you need to know in 5 minutes.

---

## What is SEVAS?

SEVAS (Sevastopol Visual AI System) — Your own image generation system based on FLUX.1 [pro] with custom trainable LoRA styles.

## Why SEVAS?

- 🎯 **Not just a wrapper** around someone else's API
- 🎨 **Own the system** — customize styles, fine-tune quality
- 💾 **Full control** — keep data on-premises or choose deployment
- 📈 **Scalable** — from MVP to commercial product
- 🔬 **Research-ready** — can evolve to proprietary models

---

## Architecture in 30 Seconds

```
┌─────────────────────────────────────┐
│  User Types Prompt in Web UI        │
└────────────────┬────────────────────┘
                 ↓
         ┌───────────────┐
         │ Backend Node  │
         │ (Express)     │
         └───────┬───────┘
                 ↓
    ┌────────────────────────┐
    │ Python Worker          │
    │ (FLUX.1 + LoRA)        │
    │ Generates Image        │
    │ 10-12 seconds          │
    └────────────┬───────────┘
                 ↓
         ┌───────────────┐
         │ Save & Return │
         │ Image URL     │
         └───────────────┘
```

## Timeline

| Phase | Time | What You Get |
|-------|------|--------------|
| **MVP** | Week 1-2 | Can generate images locally |
| **Dataset** | Week 3-4 | 250+ smoke-cinematic images ready |
| **LoRA** | Week 5-6 | First trained style (8-9/10 quality) |
| **UI** | Week 7-8 | Web interface + style selector |
| **Styles** | Week 9-10 | 3-4 custom styles |
| **Production** | Week 11-12 | Ready to launch |

**Total**: 12 weeks. **Cost**: $100-200 (GPU rental + storage).

---

## Three Key Decisions Already Made

### 1. Base Model: FLUX.1 [pro]
- ✅ **Why**: Best open-source (late 2024), cinematic quality, fast inference
- ❌ **Not**: SD 3.5 (slower), training from scratch (unrealistic)
- 📊 **Stats**: 24GB VRAM, ~10-12 sec per image, ~24MB model file

### 2. Style Training: LoRA
- ✅ **Why**: Fast (4-12h), cheap ($20-30), small files (100MB)
- ❌ **Not**: DreamBooth (slower), full fine-tuning (too expensive)
- 📊 **Stats**: 250 images per style, 8000 training steps

### 3. Quality Target: 8-9/10
- ✅ **Why**: Commercial grade, competitive with Midjourney
- ❌ **Not**: 5-6/10 (looks cheap), 10/10 (unrealistic)
- 📊 **Metrics**: No visible artifacts, strong style match, professional look

---

## Quick Reference

### Key Files

**Architecture & Planning**:
- 📖 `docs/SEVAS_ARCHITECTURE.md` - System design
- 📊 `docs/QUALITY_CRITERIA.md` - How to score images (0-10)
- 🗺️ `SEVAS_ROADMAP_DETAILED.md` - Day-by-day plan
- 🚀 `ml-pipeline/README.md` - ML pipeline guide

**Configuration**:
- ⚙️ `ml-pipeline/training/configs/smoke-cinematic-flux.json` - LoRA hyperparameters
- 📝 `ml-pipeline/validation/prompts/smoke-cinematic.txt` - Test prompts
- 📋 `ml-pipeline/datasets/smoke-cinematic/metadata.json` - Dataset tracking

### Commands (When Ready)

```bash
# Download 250 images
python ml-scripts/download-images.py --style smoke-cinematic

# Process images (resize to 768x768)
python ml-scripts/preprocess-images.py --style smoke-cinematic

# Generate captions (2-3 per image)
python ml-scripts/generate-captions.py --style smoke-cinematic

# Validate dataset quality
python ml-scripts/validate-dataset.py --style smoke-cinematic

# Train LoRA (on GPU)
python ml-scripts/train-lora.py --config smoke-cinematic-flux.json

# Validate quality at each checkpoint
python ml-scripts/validate-lora.py --checkpoint step_4000
```

---

## Starting Point: TODAY (June 20)

### What's Done ✅
- [x] Full architecture designed
- [x] Directory structure created
- [x] Config files ready
- [x] Documentation complete
- [x] All committed to git

### What's Next (This Week)

**Option 1: Dive In** (if you have GPU)
1. Create `src/services/image-generation/ImageGenerationService.ts`
2. Download FLUX.1 model (~24GB, takes 1-2 hours)
3. Test: generate first image via API
4. **Time**: 2-3 days

**Option 2: Plan First** (if you want to understand deeply)
1. Read `docs/SEVAS_ARCHITECTURE.md` (30 min)
2. Read `ml-pipeline/README.md` (30 min)
3. Start coding from Week 1 of `SEVAS_ROADMAP_DETAILED.md`
4. **Time**: 1 day planning + 2 days coding

**Option 3: Outsource** (if you want to delegate)
1. Send architecture docs to contractor
2. Ask them to implement Week 1-2 MVP
3. Review and iterate
4. **Time**: 3-5 days for contractor

---

## Common Questions

### Q: Can I start with SD 3.5 instead of FLUX.1?
**A**: Yes, but quality will be worse (~7/10 instead of 8.5/10). FLUX.1 is worth it.

### Q: How much does it cost to train one LoRA?
**A**: $20-30 on Lambda Labs GPU (8-12 hour rental). One-time per style.

### Q: Can I use images from Instagram / Pinterest for training?
**A**: No, copyright issues. Use only CC0/CC-BY licensed images from Unsplash, Pexels, Pixabay.

### Q: How many images do I need for a good LoRA?
**A**: 250 minimum (average quality), 500-800 for excellent quality (takes longer to train).

### Q: Will FLUX.1 stay open-source?
**A**: Unknown. License can change. Plan for SD 3.5 fallback if needed.

### Q: How do I make money with SEVAS?
**A**: Options:
1. **SaaS**: Charge users per generation ($0.01-0.10/image)
2. **Custom models**: Train on client's brand (white-label)
3. **Stock images**: Generate and sell on stock sites
4. **Licensing**: Sell style LoRAs to other creators

---

## File Structure After Week 1

```
Selkorin/
├── src/
│   ├── services/image-generation/
│   │   ├── ImageGenerationService.ts (NEW)
│   │   ├── ModelManager.ts (NEW)
│   │   └── LoRAManager.ts (NEW)
│   ├── controllers/
│   │   └── ImageGenerationController.ts (NEW)
│   └── entities/
│       └── GeneratedImage.ts (NEW)
│
├── web/
│   └── src/
│       ├── pages/
│       │   └── ImageGeneration.tsx (NEW)
│       └── components/
│           └── ImageGenerator/ (NEW)
│
├── ml-pipeline/ (NEW)
│   ├── datasets/smoke-cinematic/ (will fill)
│   ├── training/
│   └── validation/
│
├── ml-scripts/ (NEW)
│   ├── preprocess-images.py
│   ├── generate-captions.py
│   └── validate-dataset.py
│
├── docs/
│   ├── SEVAS_ARCHITECTURE.md (NEW)
│   └── QUALITY_CRITERIA.md (NEW)
│
└── SEVAS_ROADMAP_DETAILED.md (NEW)
```

---

## Next Steps (Pick One)

### 🚀 Fast Track (Start coding now)
```
Go to SEVAS_ROADMAP_DETAILED.md
Jump to WEEK 1-2
Copy the TypeScript templates
Start building
```

### 📚 Learning Track (Understand first)
```
1. Read SEVAS_ARCHITECTURE.md
2. Read QUALITY_CRITERIA.md
3. Understand the flow
4. Then code Week 1
```

### 🤝 Delegation Track (Get help)
```
1. Share SEVAS_ROADMAP_DETAILED.md with contractor
2. Share ml-pipeline/ folder
3. Ask for Week 1-2 MVP implementation
4. Review code when done
```

---

## Key Metrics to Track

Every week, measure:
- **Progress**: Lines of code written, features completed
- **Quality**: Average image score (0-10)
- **Speed**: Time per generation (target: 10-12 sec)
- **Cost**: Total spent on GPU rental
- **Health**: No memory leaks, error rate &lt; 1%

---

## How to Get Help

1. **Architecture questions**: Read `docs/SEVAS_ARCHITECTURE.md`
2. **Training questions**: Read `ml-pipeline/README.md`
3. **Quality issues**: Use rubric in `docs/QUALITY_CRITERIA.md`
4. **Timeline questions**: Check `SEVAS_ROADMAP_DETAILED.md`
5. **Code questions**: Check relevant week in roadmap for examples

---

## Success Definition

**SEVAS is successful when...**

- ✅ Users can type a prompt and get a beautiful image
- ✅ Image quality is 8+/10 (commercial grade)
- ✅ System generates images in 10-12 seconds
- ✅ You control the style (not dependent on OpenAI/Midjourney)
- ✅ Cost per image is &lt; $0.001 (at scale)
- ✅ System is documented and can be maintained by others
- ✅ (Bonus) Making money or gaining competitive advantage

---

## One More Thing

**This architecture is realistic.**

Not promising:
- ❌ Custom model from scratch (would take 6+ months)
- ❌ Competing with Midjourney (not yet possible at MVP)
- ❌ 100% free GPU (you need to rent or buy)

IS delivering:
- ✅ Production-ready system in 12 weeks
- ✅ Professional image quality
- ✅ Your own intellectual property
- ✅ Foundation for future AI research

**Good luck! 🚀**

Questions? Check the docs. Stuck? Check the roadmap. Ready? Start coding!
