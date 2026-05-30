# local-med — Documentación

App móvil de primeros auxilios con IA completamente offline. El modelo corre en el dispositivo: sin servidores, sin internet, sin latencia de red.

---

## Requisitos de hardware

| Plataforma | Mínimo |
|------------|--------|
| Android | 6 GB RAM, Snapdragon 8-series o equivalente, Android 10+ |
| iOS | Chip A15 Bionic, iOS 16+ |

El dispositivo necesita ~1.45 GB libres en almacenamiento para la descarga inicial.

---

## Requisitos de desarrollo

| Herramienta | Versión mínima |
|-------------|----------------|
| Flutter SDK | 3.38.4 |
| Dart SDK | 3.12.0 |
| Android NDK | el que fija `flutter.ndkVersion` en `build.gradle.kts` |
| Java | 17 |

---

## Instalación

```bash
# 1. Clonar el repositorio
git clone <url-del-repo>
cd local-med

# 2. Instalar dependencias Flutter
cd local_med
flutter pub get

# 3. Conectar un dispositivo o iniciar un emulador con ≥6 GB RAM configurados
flutter devices

# 4. Correr la app
flutter run
```

> **Nota:** La app actual es una pantalla de smoke test, no la UI final de producción. Ver [uso](#uso).

---

## Assets requeridos

Los assets en `local_med/assets/` son artefactos **generados en Google Colab** y commiteados manualmente. No se generan automáticamente al compilar.

| Archivo | Origen | Descripción |
|---------|--------|-------------|
| `assets/models/model.onnx` | Colab (`embedding.py`) | Modelo `paraphrase-multilingual-MiniLM-L12-v2` cuantizado |
| `assets/models/tokenizer.json` | Colab (`embedding.py`) | Tokenizer del mismo modelo |
| `assets/data/vectors.json` | Colab (`embedding.py`) | Vectores precomputados del dataset |
| `assets/data/enriquecimientos.json` | Colab (`embedding.py`) | Metadata canónica de cada entrada |
| `assets/data/golden_test.json` | Colab (`embedding.py`) | Vector de referencia para test de paridad |

Si necesitas regenerar los assets, sigue el pipeline descrito en [ARCHITECTURE.md](./ARCHITECTURE.md#pipeline-de-datos).

---

## Uso

### Smoke test de embeddings

La pantalla principal ejecuta un test de 5 pasos que verifica que el modelo ONNX en Flutter produce los mismos vectores que en Colab (paridad):

1. Copia `model.onnx` y `tokenizer.json` al filesystem del dispositivo
2. Inicializa `MiniLmEmbedder`
3. Embebe el texto `"hola mundo"` y mide latencia
4. Carga `golden_test.json` (vector de referencia generado en Colab)
5. Calcula cosine similarity entre ambos vectores

**Interpretación del resultado:**

| Similarity | Significado |
|------------|-------------|
| > 0.999 | Paridad perfecta — el pipeline es consistente |
| 0.95–0.999 | Paridad aproximada — revisar retrieval quality con eval set |
| < 0.95 | Paridad rota — tokenizer, pooling o modelo difieren entre Colab y Flutter |

### Lint y análisis estático

```bash
cd local_med
flutter analyze
```

### Tests

```bash
cd local_med
flutter test
```

> **Aviso:** `test/widget_test.dart` referencia `MyApp` que no existe en la versión actual; el test fallará hasta que se actualice.

### Compilar APK

```bash
cd local_med
flutter build apk          # debug
flutter build apk --release
```

---

## Scripts de datos (Google Colab)

Estos scripts corren en Colab, no localmente. Requieren `ANTHROPIC_API_KEY` en los Secrets de Colab.

| Script | Propósito |
|--------|-----------|
| `data_sintetica.py` | Genera 500 queries médicas en español usando Claude API |
| `embedding.py` | Descarga el modelo ONNX, computa vectores y exporta los assets |

Ver [ARCHITECTURE.md](./ARCHITECTURE.md#pipeline-de-datos) para el flujo completo.

---

## Descarga inicial en el dispositivo (producción)

| Componente | Tamaño |
|------------|--------|
| Gemma 4 E2B (GGUF Q4_K_M) | ~1.3 GB |
| Modelo de embeddings | ~117 MB |
| Protocolos + vectores (SQLite) | ~15–20 MB |
| **Total** | **~1.45 GB** |

La descarga se hará por WiFi en el primer uso. No está implementada aún en la app actual.
