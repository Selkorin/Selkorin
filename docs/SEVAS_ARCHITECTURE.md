# SEVAS Architecture & Implementation Guide

**SEVAS** = Sevastopol Visual AI System — Custom image generation system based on FLUX.1 [pro] with trainable LoRA styles.

## System Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        SEVAS Architecture                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  Web UI (React)          Backend (Node.js/Express)              │
│  ┌──────────────┐        ┌────────────────────────┐             │
│  │ Generate     │        │ ImageGenerationCtrl    │             │
│  │ PromptBuild  │───────→│ ValidationService      │             │
│  │ StyleSelect  │        │ ModelManager           │             │
│  │ ResultGal    │◄───────│ LoRAManager            │             │
│  └──────────────┘        │ QueueManager           │             │
│                          └──────────────┬─────────┘             │
│                                         │                       │
│                                         ▼                       │
│                          ┌──────────────────────┐               │
│                          │  Python Worker       │               │
│                          │ (diffusers/torch)    │               │
│                          │                      │               │
│                          │ FLUX.1 Model (24GB)  │               │
│                          │ LoRA Weights (100MB) │               │
│                          │                      │               │
│                          │ Generate Images      │               │
│                          │ (10-12 sec/image)    │               │
│                          └──────────────────────┘               │
│                                         │                       │
│                  ┌──────────────────────┼──────────────────┐   │
│                  ▼                      ▼                  ▼   │
│             ┌─────────┐            ┌─────────┐       ┌─────────┐
│             │ Database│            │Local FS │       │S3/Cloud │
│             │Metadata │            │  Images │       │ Images  │
│             └─────────┘            └─────────┘       └─────────┘
│                                                                   │
└─────────────────────────────────────────────────────────────────┘

ML Training Pipeline (separate, Lambda Labs GPU):
┌─────────────────────────────────────────────────────────────────┐
│                                                                   │
│  Dataset → Preprocessing → Caption → Kohya SS → LoRA → Results  │
│  (250 img) (768x768)      (2-3/img)  (8-12h)   (100MB)(gallery) │
│                                                                   │
└─────────────────────────────────────────────────────────────────┘
```

## Data Flow

### Generation Request
```
1. User submits prompt + style in Web UI
   ↓
2. Frontend validates, sends to /api/images/generate
   ↓
3. Backend receives request:
   - Check auth token
   - Validate prompt (no injection)
   - Check rate limits
   - Add to generation queue
   ↓
4. Queue Manager (Node):
   - If queue empty, process immediately
   - If processing, add to queue (max 10 pending)
   ↓
5. Python Worker (subprocess):
   - Load base FLUX.1 model (cached in memory)
   - Load LoRA for selected style
   - Generate image (diffusers inference)
   - Return image bytes
   ↓
6. Backend post-processing:
   - Save to S3 or local filesystem
   - Update database with metadata
   - Return image URL + metadata
   ↓
7. Frontend displays image, stores in gallery
```

### Training Pipeline (Offline, Kohya SS)
```
1. Collect dataset: 250+ images
   ↓
2. Preprocess: Resize all to 768x768
   ↓
3. Generate captions: 2-3 descriptions per image
   ↓
4. Validate dataset: quality_score ≥ 0.85
   ↓
5. Kohya SS Training:
   - Load FLUX.1 checkpoint
   - Attach LoRA adapter
   - Run training loop (8000 steps)
   - Save checkpoints every 500 steps
   ↓
6. Validation at each checkpoint:
   - Generate test images
   - Score quality (0-10)
   - Track metrics
   ↓
7. Select best checkpoint:
   - Lowest validation loss OR
   - Best visual quality (manual inspection)
   ↓
8. Save final LoRA: smoke-cinematic-flux-v1.safetensors (100MB)
   ↓
9. Deploy: Copy to production, update model registry
```

## Component Details

### 1. Frontend (React)

**Page**: `/images/generate`

**Components**:
```
ImageGenerationPage
├── StyleSelector
│   ├── Dropdown with preview
│   └── Save selection to localStorage
├── PromptBuilder
│   ├── Textarea with auto-complete
│   ├── Enhance button (Claude API)
│   └── Character counter
├── AdvancedOptions (collapsible)
│   ├── Resolution selector (768, 1024)
│   ├── Guidance scale slider (1-15)
│   ├── Steps selector (8-25)
│   └── Model selector (FLUX, SD3.5)
├── GenerateButton
│   └── Disabled when processing
└── ResultsGallery
    ├── Grid display (3 cols)
    ├── Like/Unlike
    ├── Download PNG
    ├── Copy prompt
    └── Add to favorites
```

**State Management**:
```typescript
interface GenerationState {
  prompt: string;
  style: string;
  width: number;
  height: number;
  guidance_scale: number;
  num_steps: number;
  negative_prompt: string;
  
  // Status
  isProcessing: boolean;
  progress: number; // 0-100
  error: string | null;
  
  // Results
  generatedImages: Image[];
  selectedImage: Image | null;
}
```

### 2. Backend (Express)

**Endpoints**:
```
POST /api/images/generate
  Request:  { prompt, style, width, height, guidance_scale, ... }
  Response: { job_id, status, images: [...] }

GET /api/images/jobs/{job_id}
  Response: { status, images, error }

GET /api/images/styles
  Response: [{ id, name, description, trigger_words, ... }]

GET /api/images/library?page=1&limit=20&style=...
  Response: { total, images: [...] }

PUT /api/images/{image_id}
  Request:  { liked, tags, notes }
  Response: { id, liked, tags, notes }
```

**Key Services**:

**ImageGenerationService**:
```typescript
class ImageGenerationService {
  async generate(params: GenerationParams): Promise<GenerationResult> {
    // 1. Validate prompt
    // 2. Check rate limits
    // 3. Load model + LoRA
    // 4. Call Python worker
    // 5. Save results
    // 6. Return metadata
  }
}
```

**ModelManager**:
```typescript
class ModelManager {
  private model: any = null; // FLUX.1 cached
  private loraCache: Map<string, LoRA> = new Map();
  
  async loadModel(modelName: string): Promise<any> {
    // Load base model once, keep in memory
    // Handle OOM gracefully
  }
  
  async loadLoRA(styleId: string, weight: number): Promise<LoRA> {
    // Load style LoRA
    // Cache in memory
  }
  
  async unloadLoRA(styleId: string): void {
    // Free memory when not needed
  }
}
```

**LoRAManager**:
```typescript
class LoRAManager {
  private loraRegistry: Map<string, LoRAInfo> = new Map();
  
  // Track all available LoRAs
  // Version management
  // Fallback to base model if LoRA missing
  // Monitor memory usage
}
```

**QueueManager**:
```typescript
class QueueManager {
  private queue: GenerationJob[] = [];
  private processing: boolean = false;
  
  async add(job: GenerationJob): Promise<string> {
    // Add to queue
    // Return job_id for status checking
    // Process next in queue
  }
  
  private async processNext(): Promise<void> {
    // Load next job from queue
    // Call ImageGenerationService
    // Update job status
  }
}
```

### 3. Python Worker (Inference)

**Purpose**: Run FLUX.1 model and generate images

**Communication**: Subprocess with stdin/stdout JSON

```python
# ml-scripts/generate-image.py
import json
import torch
from diffusers import FluxPipeline, FluxLoraLoading

class ImageGenerator:
    def __init__(self):
        self.model = FluxPipeline.from_pretrained(
            "black-forest-labs/FLUX.1-pro",
            torch_dtype=torch.float8,  # FP8 for memory
        )
        self.model.enable_attention_slicing()
        self.loras = {}
    
    def load_lora(self, style_id: str, weight: float = 1.0):
        if style_id not in self.loras:
            self.model.load_lora(f"loras/{style_id}.safetensors")
        return self.model.set_lora_scale(weight)
    
    def generate(self, prompt: str, style: str, **kwargs) -> bytes:
        # Generate image
        # Return as PNG bytes
        return image.tobytes()

# Main loop
generator = ImageGenerator()
while True:
    request = json.loads(input())
    try:
        image_bytes = generator.generate(**request)
        response = {"status": "success", "image": image_bytes.hex()}
    except Exception as e:
        response = {"status": "error", "error": str(e)}
    print(json.dumps(response))
```

### 4. Database Schema

```typescript
// GeneratedImage entity
@Entity()
export class GeneratedImage {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column()
  userId: string;

  @Column('text')
  prompt: string;

  @Column('text')
  negativePrompt: string;

  @Column()
  style: string; // smoke-cinematic, poster, etc

  @Column()
  modelVersion: string; // flux, sd35

  @Column()
  loraVersion: string; // smoke-cinematic-flux-v1

  @Column()
  width: number;

  @Column()
  height: number;

  @Column()
  guidanceScale: number;

  @Column()
  numSteps: number;

  @Column()
  seed: number;

  @Column()
  imageUrl: string; // S3 or local path

  @Column()
  generationTime: number; // milliseconds

  @Column('timestamp')
  createdAt: Date;

  @Column()
  liked: boolean;

  @Column('text', { nullable: true })
  tags: string[]; // JSON array

  @Column('text', { nullable: true })
  notes: string;
}

// GenerationJob entity (temporary, for status tracking)
@Entity()
export class GenerationJob {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column()
  userId: string;

  @Column()
  status: 'queued' | 'processing' | 'completed' | 'failed';

  @Column()
  position: number; // In queue

  @Column('timestamp')
  createdAt: Date;

  @Column('timestamp', { nullable: true })
  startedAt: Date;

  @Column('timestamp', { nullable: true })
  completedAt: Date;

  @Column('text', { nullable: true })
  error: string;
}
```

## Implementation Checklist

### Week 1-2: MVP (Local Generation)

**Backend**:
- [ ] Create ImageGenerationService skeleton
- [ ] Create ModelManager (load FLUX.1)
- [ ] Create ImageGenerationController + POST /api/images/generate
- [ ] Create GeneratedImage entity
- [ ] Add to database migrations
- [ ] Create QueueManager (basic)
- [ ] Handle CUDA memory management

**Frontend**:
- [ ] Create ImageGenerationPage component
- [ ] Create PromptBuilder component
- [ ] Create ResultGallery component
- [ ] Connect to API endpoint
- [ ] Display generated images
- [ ] Add loading state

**Infrastructure**:
- [ ] Download FLUX.1 model (~24GB) to ml/ folder
- [ ] Create directories for outputs
- [ ] Test end-to-end generation

**Testing**:
- [ ] Manual test: 5+ generations
- [ ] No memory leaks on repeated calls
- [ ] Images save to correct location

### Week 3-4: Dataset (Smoke-cinematic)

**Data Collection**:
- [ ] Download 250+ images from free sources
- [ ] Verify licenses (CC0, CC-BY)
- [ ] Organize into datasets/smoke-cinematic/raw/

**Processing**:
- [ ] Create preprocess-images.py script
- [ ] Resize all to 768x768
- [ ] Save to datasets/smoke-cinematic/processed/

**Captioning**:
- [ ] Create generate-captions.py script
- [ ] Generate 2-3 captions per image using Claude
- [ ] Save to datasets/smoke-cinematic/captions/

**Validation**:
- [ ] Create validate-dataset.py script
- [ ] Check diversity, duplicates, quality
- [ ] Generate quality_report.json
- [ ] Approve dataset (quality_score ≥ 0.85)

### Week 5-6: LoRA Training

**Setup**:
- [ ] Install Kohya SS
- [ ] Set up training environment (Python, PyTorch)
- [ ] Download FLUX.1 checkpoint for training

**Training**:
- [ ] Configure training/configs/smoke-cinematic-flux.json
- [ ] Start training (on rented GPU)
- [ ] Monitor loss graphs
- [ ] Save checkpoints

**Validation**:
- [ ] Create validate-lora.py script
- [ ] Generate images from validation prompts
- [ ] Score each checkpoint (0-10)
- [ ] Select best checkpoint

**Deployment**:
- [ ] Copy best LoRA to src/ml/loras/
- [ ] Add to LoRAManager registry
- [ ] Update model version in database

### Week 7-8: Web UI + Validation

**UI Enhancements**:
- [ ] Add StyleSelector component
- [ ] Update PromptBuilder with style-specific help
- [ ] Add AdvancedOptions panel
- [ ] Add ResultGallery actions (like, download)

**Integration**:
- [ ] Load smoke-cinematic style in StyleSelector
- [ ] Test end-to-end generation with LoRA
- [ ] Verify style is applied correctly

**Gallery**:
- [ ] Create /api/images/library endpoint
- [ ] Create ImageLibrary page component
- [ ] Add filtering (by style, date)
- [ ] Add search functionality

### Week 9-10: Multiple Styles

Repeat for:
- [ ] Style #2: "cinematic-poster"
- [ ] Style #3: "luxury-minimal"

Each style:
- [ ] Collect dataset (200+ images)
- [ ] Generate captions
- [ ] Train LoRA (8-12 hours)
- [ ] Validate quality
- [ ] Deploy to production

### Week 11-12: Production

**Optimization**:
- [ ] Enable tensor offloading
- [ ] Enable FP8 quantization (reduce VRAM to 12GB)
- [ ] Add result caching
- [ ] Add batch generation

**Infrastructure**:
- [ ] Migrate to cloud GPU (Lambda Labs or similar)
- [ ] Set up S3 for image storage
- [ ] Add proper logging + monitoring
- [ ] Set up rate limiting

**Security**:
- [ ] Sanitize prompts (no injection)
- [ ] Add auth checks
- [ ] Validate file uploads
- [ ] Add CORS security

**Documentation**:
- [ ] Write SEVAS_ARCHITECTURE.md (this file)
- [ ] Write TRAINING_GUIDE.md
- [ ] Write DEPLOYMENT_GUIDE.md
- [ ] Create API docs

**Testing**:
- [ ] Load test (100+ concurrent requests)
- [ ] Quality test (all styles)
- [ ] Uptime monitoring
- [ ] Error handling

## Key Metrics

**Generation Performance**:
- Time per image: 10-12 sec (FLUX.1 with 12 steps)
- VRAM usage: 24GB (unoptimized), 12GB (FP8 + offloading)
- Cost per image: $0.0001 (selfhosted), $0.04 (cloud API)

**Quality Metrics**:
- Style consistency: 8.5/10 (LoRA quality)
- Prompt fidelity: 8/10 (FLUX.1 accuracy)
- Artifact score: &lt;2 artifacts per 100 images

**Training Metrics**:
- Time per LoRA: 8-12 hours (RTX 4090)
- Dataset size: 250-300 images per style
- Training cost: $20-30 per LoRA

## Troubleshooting

### Memory Issues
- Reduce generation batch size
- Enable xformers attention
- Use FP8 quantization
- Unload unused LoRAs

### Poor Quality
- Check dataset diversity
- Improve captions (more detailed)
- Use higher guidance_scale (7-10)
- Increase training steps

### Slow Generation
- Reduce num_inference_steps (min 8)
- Use smaller model (SD 3.5 instead of FLUX)
- Cache model in memory
- Parallel batch processing

## Future Improvements

1. **Custom Architecture**: Move from LoRA to full model fine-tuning
2. **Multi-LoRA Blending**: Combine multiple styles
3. **Image-to-Image**: Edit existing images
4. **Inpainting**: Fill regions with generated content
5. **Video Generation**: Extend to video with motion
6. **DreamBooth**: Fine-tune on specific subjects (faces, objects)
7. **ControlNet**: Pose/edge/depth control
8. **Async Training**: Auto-train new styles on dataset changes
