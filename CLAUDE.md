# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Comandos esenciales

### Flutter (app móvil — directorio `local_med/`)
```bash
cd local_med
flutter pub get          # instalar dependencias
flutter run              # correr en dispositivo/emulador conectado
flutter build apk        # compilar APK debug
flutter test             # correr tests (el widget_test.dart por defecto está desactualizado)
flutter analyze          # lint estático
```

### Scripts Python (Colab — raíz del repo)
Los scripts `data_sintetica.py` y `embedding.py` están pensados para correr en **Google Colab**, no localmente. Montan Google Drive en `/content/drive/MyDrive/fundamentos_eval_rag/` y usan `ANTHROPIC_API_KEY` desde los Secrets de Colab.

## Arquitectura

### Tres capas de respuesta (orden de prioridad)
| Capa | Implementación | Cuándo se usa |
|------|----------------|---------------|
| 1 — Crítica | Código Dart hardcodeado, cero IA | RCP, Heimlich, hemorragia severa: situaciones de vida o muerte |
| 2 — Conversacional | Gemma 4 E2B GGUF Q4_K_M vía llama.cpp | Síntomas y consultas de segundo nivel |
| 3 — RAG local | SQLite + FTS5 + vectores precomputados + flutter_embedder | Consultas complejas, fallback por baja confianza |

**Los protocolos de capa 1 deben permanecer hardcodeados.** Son la única garantía contra alucinaciones en emergencias.

### Pipeline de datos (fuera de la app)
```
data_sintetica.py (Colab)
  → dataset_rag_medico_es.json       500 queries médicas en español
  → [enriquecimiento manual/LLM]
  → dataset_rag_medico_es_enriched_with_ids.json

embedding.py (Colab)
  → model.onnx                       (copia a assets/models/)
  → tokenizer.json                   (copia a assets/models/)
  → vectors.json                     (copia a assets/data/)
  → enriquecimientos.json            (copia a assets/data/)
  → golden_test.json                 (copia a assets/data/) — vector de paridad
```

Los archivos en `local_med/assets/` son artefactos generados en Colab y copiados manualmente.

### Estado actual de la app Flutter
`lib/main.dart` es una pantalla de **smoke test** (no la UI final). Verifica paridad de embeddings: compara el vector que produce `flutter_embedder` en el dispositivo contra el `golden_test.json` generado en Colab con el mismo modelo ONNX. Una similarity > 0.999 indica paridad perfecta.

### Modelo de embeddings
- Modelo: `paraphrase-multilingual-MiniLM-L12-v2` cuantizado (ONNX Q)
- Dimensión de salida: 384
- Pooling: mean pooling ponderado por attention mask
- Normalización: L2 (vectores con norma ≈ 1.0)
- Pipeline en Dart: `flutter_embedder` maneja tokenización + inferencia ONNX on-device

### Dependencias Flutter clave
- `flutter_embedder` — inferencia ONNX on-device para embeddings
- `sqlite3` — base de datos local con FTS5
- `flutter_riverpod` — state management
- `path_provider` — rutas del sistema de archivos del dispositivo

## Decisiones de diseño relevantes

- **Offline-first obligatorio**: todo funciona sin internet. El modelo GGUF y el modelo de embeddings se descargan por WiFi en el primer uso (~1.45 GB total).
- **Gemma 4 E2B** es el LLM elegido (descartados Gemma 4 26B A4B y E4B por tamaño).
- El `widget_test.dart` en `test/` referencia `MyApp` que no existe; está pendiente de actualizar a `SmokeTestScreen`.
- Fine-tuning con QLoRA + Unsloth sobre Colab T4 gratuito; solo se entrena ~1–3% de parámetros del modelo base.
