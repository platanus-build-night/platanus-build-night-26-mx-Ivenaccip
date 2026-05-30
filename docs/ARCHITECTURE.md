# Arquitectura

## Capas de respuesta de la app

La lógica de respuesta médica está dividida en tres capas con prioridad descendente:

```
Consulta del usuario
        │
        ▼
┌───────────────────────────────┐
│  Capa 1 — CRÍTICA             │  Hardcoded en Dart
│  RCP, Heimlich, hemorragia,   │  Sin IA. Respuesta determinista.
│  posición de recuperación     │  Nunca falla, nunca alucina.
└───────────┬───────────────────┘
            │ (si no aplica)
            ▼
┌───────────────────────────────┐
│  Capa 2 — CONVERSACIONAL      │  Gemma 4 E2B GGUF Q4_K_M
│  Síntomas, procedimientos     │  llama.cpp via JNI / Swift bindings
│  de segundo nivel             │  On-device inference
└───────────┬───────────────────┘
            │ (si confianza < umbral)
            ▼
┌───────────────────────────────┐
│  Capa 3 — RAG LOCAL           │  SQLite + FTS5
│  Consultas complejas,         │  + embeddings vectoriales on-device
│  protocolos completos         │  (flutter_embedder / MiniLM)
└───────────────────────────────┘
```

**Invariante crítica:** la capa 1 nunca delega a IA. Los protocolos de vida o muerte deben estar hardcodeados para eliminar el riesgo de alucinaciones.

---

## Estructura de directorios

```
local-med/
├── local_med/                  # App Flutter
│   ├── lib/
│   │   └── main.dart           # Smoke test de embeddings (UI provisional)
│   ├── assets/
│   │   ├── models/
│   │   │   ├── model.onnx      # MiniLM cuantizado (generado en Colab)
│   │   │   └── tokenizer.json  # Tokenizer del modelo
│   │   └── data/
│   │       ├── vectors.json        # Vectores precomputados del dataset
│   │       ├── enriquecimientos.json  # Metadata canónica para UI
│   │       └── golden_test.json    # Vector de referencia para test de paridad
│   ├── android/
│   │   └── app/
│   │       ├── build.gradle.kts    # namespace: com.localmed.local_med, Java 17
│   │       └── src/main/
│   │           ├── AndroidManifest.xml
│   │           └── kotlin/.../MainActivity.kt  # Boilerplate FlutterActivity
│   ├── test/
│   │   └── widget_test.dart    # STALE: referencia MyApp inexistente
│   └── pubspec.yaml
│
├── data_sintetica.py           # Colab: genera dataset médico via Claude API
├── embedding.py                # Colab: computa vectores y exporta assets
├── context.md                  # Decisiones de diseño y roadmap
└── docs/                       # Esta documentación
```

---

## Dependencias Flutter

### Directas

| Paquete | Versión | Rol |
|---------|---------|-----|
| `flutter_embedder` | 0.1.7 | Inferencia ONNX on-device para embeddings |
| `sqlite3` | 3.3.2 | Base de datos local (RAG, capa 3) |
| `path_provider` | 2.1.5 | Rutas del filesystem del dispositivo |
| `flutter_riverpod` | 3.3.1 | State management |
| `cupertino_icons` | 1.0.9 | Iconos iOS-style |

### Transitivas relevantes

| Paquete | Versión | Por qué importa |
|---------|---------|-----------------|
| `flutter_rust_bridge` | 2.11.1 | Transporta llamadas Dart ↔ código nativo en `flutter_embedder` |
| `jni` / `jni_flutter` | 1.0.0 / 1.0.1 | Binding JNI para Android en `flutter_embedder` |
| `ffi` | 2.2.0 | FFI base para código nativo |
| `riverpod` | 3.2.1 | Core de `flutter_riverpod` |

---

## Pipeline de datos

El pipeline corre **fuera de la app**, en Google Colab, y produce artefactos que se copian manualmente a `assets/`:

```
[1] data_sintetica.py
    Claude API (claude-sonnet-4-6)
    → dataset_rag_medico_es.json
      500 queries en español, 10 áreas médicas × 50 queries
      con campos: query, registro, demografía, sistemas, complejidad, área, tipo

[2] Enriquecimiento (paso manual o LLM)
    → dataset_rag_medico_es_enriched_with_ids.json
      Añade campo "enriquecimiento" y "id" secuencial

[3] embedding.py
    Descarga model_optimized.onnx de Hugging Face (Qdrant/paraphrase-multilingual-MiniLM-L12-v2-onnx-Q)
    → golden_test.json      {"text": "hola mundo", "vector": [...384 floats...]}
    → vectors.json          [[...384 floats...], ...]  — una fila por query/variante
    → enriquecimientos.json [{id, area, tipo, complejidad, enriquecimiento}, ...]

[4] Copiar manualmente a local_med/assets/data/ y local_med/assets/models/
```

### Especificación del modelo de embeddings

- **Modelo:** `paraphrase-multilingual-MiniLM-L12-v2` (variante ONNX cuantizada de Qdrant)
- **Dimensión de salida:** 384
- **Pooling:** mean pooling ponderado por attention mask
- **Normalización:** L2 (vectores con norma ≈ 1.0)
- **max_length:** 128 tokens
- **Métrica de similaridad:** cosine similarity (equivale a producto punto con vectores normalizados)

---

## Pipeline de inferencia en Flutter (Capa 3)

```
Consulta del usuario (String)
        │
        ▼
MiniLmEmbedder.embed(texts: [query])
  — tokenización en Dart via flutter_embedder
  — inferencia ONNX on-device
  — mean pooling + L2 normalize
        │
        ▼
Vector de query [384 floats]
        │
        ▼
Búsqueda de vecinos más cercanos en vectors.json
  (cosine similarity contra todos los vectores precomputados)
        │
        ▼
Top-K ids → lookup en enriquecimientos.json → respuesta
```

---

## Fine-tuning (fuera del repo)

El LLM de capa 2 se entrena en Google Colab (GPU T4 gratuita) con QLoRA + Unsloth sobre Gemma 4 E2B:

```
Configuración LoRA
  r = 16, alpha = 16, dropout = 0
  target_modules: q_proj, k_proj, v_proj, o_proj, gate_proj, up_proj, down_proj

Entrenamiento
  batch_size = 2, gradient_accumulation = 4  →  batch efectivo = 8
  learning_rate = 2e-4, epochs = 3
  scheduler = cosine, optimizer = adamw_8bit
  max_seq_length = 2048

Exportación
  GGUF Q4_K_M via llama.cpp convert
```

Solo se entrena ~1–3% de los parámetros del modelo base. El modelo exportado (.gguf) va al dispositivo via descarga WiFi inicial.

---

## Decisiones de diseño que no se derivan del código

- **Por qué Gemma 4 E2B y no E4B o 26B A4B:** E4B es más pesado sin beneficio suficiente; 26B carga los parámetros completos (~17 GB), inviable en móvil.
- **Por qué MiniLM y no Gemini Embedding 2:** Gemini Embedding requiere internet, incompatible con offline-first.
- **Por qué protocolos críticos hardcodeados:** Eliminar el riesgo de alucinaciones en situaciones de vida o muerte. No hay umbral de confianza que sea suficiente para RCP o hemorragia severa.
- **Por qué SQLite + FTS5 para RAG:** Ya disponible en el dispositivo, sin dependencias adicionales, y FTS5 permite búsqueda lexical como fallback cuando la búsqueda vectorial no basta.
