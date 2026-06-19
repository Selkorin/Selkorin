# SEVAS Image Quality Criteria

Comprehensive scoring system for evaluating generated images and model quality.

## Overall Quality Score (0-10)

### 10/10: Excellent
- Perfect style match (99%+ fidelity)
- No visible artifacts
- Professional photography quality
- Rich details and textures
- Proper lighting and composition
- Could be sold/published as-is

### 8-9/10: Very Good
- Strong style match (95%+ fidelity)
- Minimal artifacts (none visible at normal viewing)
- High quality, ready for use
- Good lighting and composition
- Minor imperfections acceptable

### 7/10: Good
- Clear style match (85%+ fidelity)
- Few small artifacts (not intrusive)
- Acceptable for marketing/ads
- Good composition
- Slight quality issues
- May need minor editing

### 5-6/10: Average
- Moderate style match (70%+ fidelity)
- Noticeable artifacts
- Okay for social media
- Composition decent but not perfect
- Lighting could be better

### 3-4/10: Poor
- Weak style match (50%+ fidelity)
- Significant artifacts
- Only for internal use/testing
- Bad composition or lighting

### 0-2/10: Failed
- No style match
- Many artifacts/distortion
- Not usable
- Reject and investigate

---

## Detailed Scoring Rubric

### 1. Style Fidelity (0-10)

**Smoke-cinematic Style Checklist**:
- [ ] **Smoke/Fog Visible**: Volumetric smoke should be clear and present
  - 10/10: Dense, realistic volumetric smoke
  - 5/10: Barely visible smoke effect
  - 0/10: No smoke at all

- [ ] **Dark Tones**: Image should be dark, moody, not bright
  - 10/10: Deep blacks, shadows, low-key lighting
  - 5/10: Medium darkness, some bright areas
  - 0/10: Bright image, opposite of style

- [ ] **Cinematic Look**: Professional, film-like quality
  - 10/10: Looks like professional cinema photography
  - 5/10: Somewhat cinematic
  - 0/10: Generic/flat look

- [ ] **Atmospheric Mood**: Moody, mysterious, premium aesthetic
  - 10/10: Strong emotional impact, premium feel
  - 5/10: Neutral mood
  - 0/10: Wrong mood (cheerful, bright, cheap)

**Formula**: Average of visible metrics

### 2. Technical Quality (0-10)

- [ ] **Sharpness**: Details are crisp and defined
  - 10: Everything sharp
  - 5: Some blur, most sharp
  - 0: Blurry overall

- [ ] **Color Accuracy**: Colors look natural and appealing
  - 10: Professional color grading
  - 5: Acceptable colors
  - 0: Over/under saturated, wrong tones

- [ ] **Lighting**: Light sources and shadows are realistic
  - 10: Professional 3-point lighting
  - 5: Basic lighting setup
  - 0: Flat or strange lighting

- [ ] **Composition**: Framing and balance are good
  - 10: Professional composition, rule of thirds
  - 5: Okay composition
  - 0: Poor framing, awkward composition

**Formula**: Average of technical metrics

### 3. Artifacts (0-10, inverted scoring)

Count visible artifacts:
- **0 artifacts** = 10/10 score
- **1-2 small artifacts** = 8-9/10 (acceptable)
- **3-5 artifacts** = 6-7/10 (noticeable)
- **6-10 artifacts** = 3-5/10 (significant)
- **10+ artifacts** = 0-2/10 (reject)

**Artifact Types**:
- Distorted fingers/hands
- Malformed text
- Weird textures
- Strange color patches
- Duplicated objects
- Structural errors (broken geometry)
- Floating objects

### 4. Prompt Fidelity (0-10)

Does the image match the written prompt?

**Example Prompt**: "smokecinematic style, person silhouette in thick smoke, dark moody atmosphere"

- 10/10: All elements present (person, smoke, darkness, mood)
- 8/10: Most elements (missing minor detail)
- 6/10: Some elements (missing important element)
- 4/10: Few elements (ignored major requirement)
- 0/10: Completely different image

---

## Scoring Template

### For Each Generated Image:

```json
{
  "image_id": "gen-12345-001",
  "prompt": "smokecinematic style, dark portrait with smoke",
  "style": "smoke-cinematic",
  "checkpoint": "step_4000",
  
  "style_fidelity": {
    "smoke_presence": 9,
    "darkness": 9,
    "cinematic_look": 8,
    "atmospheric_mood": 9,
    "average": 8.75
  },
  
  "technical_quality": {
    "sharpness": 8,
    "color_accuracy": 8,
    "lighting": 9,
    "composition": 8,
    "average": 8.25
  },
  
  "artifacts": {
    "count": 0,
    "severity": "none",
    "score": 10
  },
  
  "prompt_fidelity": 9,
  
  "overall_score": 9,
  "verdict": "excellent",
  "notes": "Strong style match, excellent smoke effect, professional lighting",
  "usable": true,
  "timestamp": "2026-06-20T10:30:00Z"
}
```

---

## Batch Validation Process

### For Each Training Checkpoint:

```python
def validate_checkpoint(checkpoint_path: str) -> ValidationReport:
    """
    Generate 10-20 validation images and score them.
    """
    
    # 1. Load checkpoint
    model = load_checkpoint(checkpoint_path)
    
    # 2. Generate images from validation prompts
    validation_prompts = [
        "smokecinematic style, portrait in smoke",
        "smokecinematic, dark moody room with smoke",
        # ... 8-18 more prompts
    ]
    
    results = []
    for prompt in validation_prompts:
        image = model.generate(prompt)
        
        # 3. Score each image
        score = score_image(image, prompt)
        results.append({
            "prompt": prompt,
            "image": image,
            "score": score
        })
    
    # 4. Aggregate metrics
    report = {
        "checkpoint": checkpoint_path,
        "total_images": len(results),
        "avg_score": np.mean([r["score"] for r in results]),
        "min_score": min([r["score"] for r in results]),
        "max_score": max([r["score"] for r in results]),
        "usable_count": sum(1 for r in results if r["score"] >= 7),
        "unusable_count": sum(1 for r in results if r["score"] < 5),
        "artifact_rate": calculate_artifact_rate(results),
        "style_consistency": calculate_style_consistency(results),
    }
    
    return report
```

---

## Quality Metrics During Training

### What to Track:

```
Epoch 10/50:
  - training_loss: 0.0234 ← Should decrease
  - val_loss: 0.0248 ← Should not increase (overfitting)
  - avg_quality_score: 6.5/10 ← Visual quality
  - artifact_rate: 0.15 ← Fewer artifacts better
  - style_consistency: 0.72 ← Higher better
  - learning_rate: 0.0001
```

### Good Training Curve:

```
Quality Score vs Training Step:

10 |
   |                  ▲
   |                 ╱ ▲
   |              ▲╱  ▲─── Validation (should plateau ~8-9)
8  |           ▲╱
   |         ▲╱
   |      ▲╱
6  |   ▲╱
   |▲╱─────────────── Training (can go lower than validation)
4  +─────────────────────────────────→ Training Step
   0        4000       8000

SELECT CHECKPOINT at step 4000-6000 (peak validation score)
NOT at step 8000 (training still improving but validation plateau/decline)
```

### Warning Signs:

**Overfitting**:
```
Quality vs Step:

9 |    ▲
   |   ╱▲
   |  ╱  ▲
   | ╱    ▲─── Validation drops (OVERFITTING)
7  |╱      ▼
   |         ▼
   |          ▼ ← Don't use these checkpoints
5  +──────────────→ Step
   0        4000   8000
```

**Underfitting**:
```
Quality is stuck ~5-6/10, loss not improving
→ Dataset too small or training too short
→ Increase epochs or add more training data
```

**Diverging**:
```
Loss suddenly spikes, quality crashes
→ Learning rate too high
→ Restart with lower LR (0.00005 instead of 0.0001)
```

---

## Style-Specific Criteria

### Smoke-cinematic

| Criterion | Poor (0-3) | Average (4-6) | Good (7-8) | Excellent (9-10) |
|-----------|-----------|---------------|-----------|-----------------|
| Smoke Effect | No smoke or faint | Barely visible | Clear smoke | Dense, volumetric |
| Darkness | Bright image | Medium gray | Dark tones | Deep blacks |
| Lighting | Flat | Basic directional | Professional | Cinematic 3-point |
| Mood | Cheerful | Neutral | Moody | Mysterious, premium |
| Details | Blurry | Soft | Sharp | Crisp, professional |
| Artifacts | Many (10+) | Several (3-5) | Few (0-2) | None |
| Overall | Reject | Acceptable | Good | Use/Sell |

### Cinematic Poster (future style)

| Criterion | Poor | Average | Good | Excellent |
|-----------|------|---------|------|-----------|
| Bold Colors | Muted | Medium saturation | Vibrant | Rich, striking |
| Composition | Unbalanced | Okay | Strong | Professional |
| Typography | Absent/Bad | Readable | Good placement | Integrated |
| Drama | Flat | Some tension | Dramatic | Cinematic impact |
| Size/Scale | Awkward | Okay | Good hierarchy | Perfect balance |

---

## Scoring Examples

### Example 1: Good Generation ✅

```
Prompt: "smokecinematic style, person silhouette in thick smoke, dark moody"
Generated Image: [portrait with smoke, dark background, professional lighting]

Evaluation:
- Style Fidelity: 8.5/10 (smoke present, dark, cinematic, moody)
- Technical Quality: 8/10 (sharp, good colors, professional lighting)
- Artifacts: 10/10 (no artifacts visible)
- Prompt Fidelity: 9/10 (all elements present)

Overall: (8.5 + 8 + 10 + 9) / 4 = 8.9/10 ✅ EXCELLENT
Verdict: Use for marketing/portfolio
```

### Example 2: Poor Generation ❌

```
Prompt: "smokecinematic style, dark room with smoke"
Generated Image: [bright room, no smoke, strange textures]

Evaluation:
- Style Fidelity: 2/10 (no smoke, too bright, not cinematic)
- Technical Quality: 3/10 (artifacts, weird colors)
- Artifacts: 4/10 (distorted walls, strange textures)
- Prompt Fidelity: 1/10 (completely wrong aesthetic)

Overall: (2 + 3 + 4 + 1) / 4 = 2.5/10 ❌ REJECT
Verdict: Investigate model issue, re-train
```

### Example 3: Borderline Generation ⚠️

```
Prompt: "smokecinematic style, portrait with smoke"
Generated Image: [portrait with faint smoke, slightly dark, okay quality]

Evaluation:
- Style Fidelity: 6/10 (smoke barely visible, somewhat dark)
- Technical Quality: 6.5/10 (slight blur, okay colors)
- Artifacts: 8/10 (1-2 small artifacts in background)
- Prompt Fidelity: 7/10 (portrait good, smoke weak)

Overall: (6 + 6.5 + 8 + 7) / 4 = 6.9/10 ⚠️ ACCEPTABLE
Verdict: Okay for social media, needs improvement for ads
Action: Consider earlier checkpoint or improve dataset
```

---

## Automated Quality Assessment

### Python Implementation:

```python
import numpy as np
from PIL import Image
from skimage import color
import cv2

class QualityAssessor:
    """Automated quality scoring for generated images."""
    
    def assess(self, image: Image.Image, 
               expected_style: str = "smoke-cinematic") -> dict:
        """Assess image quality automatically."""
        
        img_array = np.array(image)
        
        # 1. Detect smoke/fog
        smoke_score = self.detect_smoke(img_array)
        
        # 2. Check darkness
        darkness_score = self.assess_darkness(img_array)
        
        # 3. Detect artifacts
        artifact_score = self.detect_artifacts(img_array)
        
        # 4. Check sharpness
        sharpness_score = self.assess_sharpness(img_array)
        
        # 5. Color analysis
        color_score = self.assess_colors(img_array)
        
        # Average
        overall = np.mean([
            smoke_score * 0.3,
            darkness_score * 0.25,
            artifact_score * 0.2,
            sharpness_score * 0.15,
            color_score * 0.1
        ])
        
        return {
            "overall_score": overall,
            "smoke_score": smoke_score,
            "darkness_score": darkness_score,
            "artifact_score": artifact_score,
            "sharpness_score": sharpness_score,
            "color_score": color_score,
            "verdict": "excellent" if overall >= 8 else "good" if overall >= 7 else "acceptable"
        }
    
    def detect_smoke(self, img: np.ndarray) -> float:
        """Detect presence of smoke/fog."""
        # Convert to HSV
        hsv = cv2.cvtColor(img, cv2.COLOR_RGB2HSV)
        
        # Smoke/fog typically has low saturation, medium-dark value
        low_sat = (hsv[:,:,1] < 50).sum() / img.size * 100
        
        # Score: 0-10
        return min(10, low_sat / 10)
    
    def assess_darkness(self, img: np.ndarray) -> float:
        """Check if image is sufficiently dark."""
        # Convert to grayscale
        gray = cv2.cvtColor(img, cv2.COLOR_RGB2GRAY)
        mean_brightness = gray.mean()
        
        # Ideal for dark cinematic: 60-100 (out of 255)
        if mean_brightness < 60:
            return 10
        elif mean_brightness < 100:
            return 8
        elif mean_brightness < 150:
            return 5
        else:
            return 2
    
    def detect_artifacts(self, img: np.ndarray) -> float:
        """Detect anomalies/artifacts."""
        # Look for abnormal color blocks, strange edges
        # Simplified: check entropy
        gray = cv2.cvtColor(img, cv2.COLOR_RGB2GRAY)
        
        # Normal images have good entropy distribution
        # Artifacts appear as unusual pixel patterns
        # This is simplified; real implementation uses more ML
        
        # Score: invert (fewer artifacts = higher score)
        artifact_likelihood = 0.1  # placeholder
        return max(0, 10 - artifact_likelihood * 10)
    
    def assess_sharpness(self, img: np.ndarray) -> float:
        """Assess image sharpness."""
        gray = cv2.cvtColor(img, cv2.COLOR_RGB2GRAY)
        
        # Use Laplacian variance as sharpness metric
        laplacian_var = cv2.Laplacian(gray, cv2.CV_64F).var()
        
        # Sharpness score
        if laplacian_var > 500:
            return 10
        elif laplacian_var > 300:
            return 8
        elif laplacian_var > 100:
            return 5
        else:
            return 2
    
    def assess_colors(self, img: np.ndarray) -> float:
        """Assess color balance and naturalness."""
        # Check if color distribution looks natural
        # Placeholder: return 7.0
        return 7.0
```

---

## Acceptance Criteria

### For MVP Release:
- ✅ Average quality ≥ 7/10
- ✅ No image scores below 5/10
- ✅ Artifact rate < 5%
- ✅ Style consistency ≥ 0.85

### For Production (paid product):
- ✅ Average quality ≥ 8/10
- ✅ 95%+ of images ≥ 7/10
- ✅ Artifact rate < 1%
- ✅ Style consistency ≥ 0.95
- ✅ Prompt fidelity ≥ 0.9

---

## Continuous Quality Monitoring

### Daily Metrics:
```python
# Track these in production
daily_metrics = {
    "total_generations": count,
    "avg_quality_score": mean,
    "artifact_rate": percent,
    "style_consistency": score,
    "error_rate": percent,
    "user_satisfaction": rating
}
```

### Weekly Review:
- Check quality trends
- Identify failing prompts
- Monitor LoRA drift
- Plan retraining if needed
