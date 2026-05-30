# Contexto del proyecto: local-med

## ¿Qué estamos construyendo?

Una app móvil de primeros auxilios con IA completamente **offline**. El usuario puede consultar protocolos de emergencia desde cualquier lugar, incluso sin señal. Apunta al mercado LATAM, donde la conectividad es limitada en muchas zonas.

---

## Modelo de IA elegido

**Gemma 4 E2B** (Google, 2025)

| Parámetro | Valor |
|-----------|-------|
| Formato | GGUF Q4_K_M (cuantización 4-bit) |
| Peso en disco | ~1.3 GB |
| RAM requerida | ~1.5 GB en INT4 |
| Android mínimo | 6 GB RAM+, Snapdragon 8-series, Android 10+ |
| iOS mínimo | A15 Bionic o superior, iOS 16+ |
| Velocidad de inferencia | 10–25 tokens/seg en gama alta |

**Modelos descartados:**
- Gemma 4 26B A4B — carga los 26B completos (~17 GB), inviable en móvil
- Gemma 4 E4B — más pesado que E2B sin beneficio suficiente

---

## Arquitectura de la app (3 capas)

| Capa | Mecanismo | Casos de uso |
|------|-----------|--------------|
| 1 — Crítica | Hardcodeada (sin IA) | RCP adulto/pediátrico, Heimlich, hemorragia severa, posición de recuperación |
| 2 — Conversacional | Gemma 4 E2B fine-tuneado, on-device | Síntomas, procedimientos de segundo nivel, contexto del usuario |
| 3 — RAG local | SQLite + FTS5 + embeddings vectoriales | Consultas complejas, protocolos completos, fallback por baja confianza |

Los protocolos críticos (capa 1) están **hardcodeados deliberadamente** para eliminar el riesgo de alucinaciones en situaciones de vida o muerte.

---

## Stack tecnológico

| Componente | Tecnología |
|------------|------------|
| Framework móvil | Flutter |
| Runtime de inferencia | llama.cpp (JNI en Android / Swift bindings en iOS) |
| Embedding on-device | `paraphrase-multilingual-MiniLM-L12-v2` (~117 MB) |
| Base de datos local | SQLite + FTS5 |
| Fine-tuning | QLoRA + Unsloth en Google Colab (GPU T4 gratuita) |
| Exportación del modelo | GGUF Q4_K_M via llama.cpp |

**Modelo de embeddings — decisión tomada:**
- Elegido: `paraphrase-multilingual-MiniLM-L12-v2` (~117 MB) — soporta español nativo (50+ idiomas), corre completamente on-device
- Descartado: Gemini Embedding 2 — requiere internet
- Descartado: all-MiniLM-L6-v2 — solo inglés de base

---

## Fine-tuning

Pipeline **QLoRA + Unsloth** sobre Google Colab gratuito (GPU T4, 15 GB VRAM). Solo se entrenan ~1–3% de los parámetros del modelo base.

```
Configuración LoRA
  r = 16, alpha = 16, dropout = 0
  target_modules: q_proj, k_proj, v_proj, o_proj, gate_proj, up_proj, down_proj

Configuración de entrenamiento
  batch_size = 2
  gradient_accumulation_steps = 4  →  batch efectivo = 8
  learning_rate = 2e-4
  epochs = 3
  scheduler = cosine
  optimizer = adamw_8bit
  max_seq_length = 2048
```

**Tiempo estimado:**
- 200 ejemplos × 3 épocas → 20–30 min
- 1,000 ejemplos × 3 épocas → 60–90 min

---

## Dataset — estado actual (en progreso)

### Formato requerido

El fine-tuning con Unsloth sobre Gemma usa el **chat template de Gemma**. Dos formatos compatibles:

**Formato conversacional (preferido):**
```json
{
  "conversations": [
    {"role": "user", "content": "¿Qué hago si alguien no respira?"},
    {"role": "assistant", "content": "Llama al 112, inclina la cabeza..."}
  ]
}
```

**Formato instrucción/respuesta (también válido para Unsloth):**
```json
{
  "instruction": "¿Qué hago si alguien no respira?",
  "output": "Llama al 112, inclina la cabeza..."
}
```

### Fuentes objetivo
- Cruz Roja Internacional — protocolos de primeros auxilios
- American Heart Association (AHA) — guías RCP actualizadas (~cada 5 años)
- PHTLS (Prehospital Trauma Life Support)
- Guías OPS/OMS

### Criterios de evaluación para datasets encontrados
Al analizar cualquier dataset candidato se revisa:
1. **Formato** — compatible o necesita conversión
2. **Idioma** — en español o requiere traducción
3. **Cobertura temática** — RCP, Heimlich, hemorragias, quemaduras, fracturas, shock, etc.
4. **Calidad médica** — alineado con guías AHA/Cruz Roja vigentes
5. **Licencia** — uso permitido para entrenamiento

---

## Descarga inicial en el dispositivo

| Componente | Tamaño |
|------------|--------|
| Gemma 4 E2B (GGUF Q4_K_M) | ~1.3 GB |
| Modelo de embeddings | ~117 MB |
| Protocolos + vectores (SQLite) | ~15–20 MB |
| **Total estimado** | **~1.45 GB** |

Descarga obligatoria por WiFi en el primer uso.

---

## Riesgos y mitigaciones

| Riesgo | Mitigación |
|--------|------------|
| Alucinaciones en contexto médico | Protocolos críticos hardcodeados; modelo solo para consultas secundarias |
| Thermal throttling | Pausas entre respuestas; sin inferencia en loop continuo |
| Descarga inicial de 1.45 GB | WiFi obligatoria; descarga incremental si es posible |
| Actualización de protocolos médicos | RAG local actualizable (JSON vía CDN) sin reentrenar el modelo |
| Marco legal (SaMD) | Pendiente: COFEPRIS (México), ARCSA (Ecuador), FDA (EEUU) |

---

## Roadmap

- [ ] **Curar dataset médico** (AHA, Cruz Roja, PHTLS) en español ← **estamos aquí**
- [ ] Fine-tuning en Colab con dataset real
- [ ] Evaluar modelo fine-tuneado vs modelo base
- [ ] Elegir runtime móvil (Android primero)
- [ ] Integrar GGUF en app móvil — prueba de velocidad en dispositivo real
- [ ] Definir estrategia de actualización de protocolos
- [ ] Consultar marco legal según mercado objetivo
