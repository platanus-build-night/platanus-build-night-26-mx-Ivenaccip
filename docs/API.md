# Referencia de API

---

## Flutter — `lib/main.dart`

### `SmokeTestScreen`

Widget raíz de la app actual. Pantalla provisional que valida la paridad de embeddings entre el pipeline de Colab y flutter_embedder en el dispositivo.

```dart
const SmokeTestScreen({super.key})
```

No recibe parámetros de configuración. Es el `home` del `MaterialApp` en `main()`.

---

### `_SmokeTestScreenState`

Estado interno de `SmokeTestScreen`. Expone cuatro métodos relevantes para el ciclo de vida del smoke test.

---

#### `_copyAssetToFile`

```dart
Future<String> _copyAssetToFile(String assetPath)
```

Copia un asset del bundle de Flutter al filesystem del dispositivo. Si el archivo ya existe en destino, no lo sobreescribe (idempotente).

**Parámetros:**

| Nombre | Tipo | Descripción |
|--------|------|-------------|
| `assetPath` | `String` | Ruta relativa al asset dentro del bundle, e.g. `'assets/models/model.onnx'` |

**Retorna:** ruta absoluta del archivo en `getApplicationSupportDirectory()`.

**Ejemplo:**

```dart
final modelPath = await _copyAssetToFile('assets/models/model.onnx');
// → '/data/user/0/com.localmed.local_med/files/model.onnx'
```

**Por qué existe:** `flutter_embedder` y ONNX Runtime requieren una ruta de filesystem real; los assets del bundle de Flutter no son accesibles como rutas de archivo directas en Android.

---

#### `_cosineSimilarity`

```dart
double _cosineSimilarity(List<double> a, List<double> b)
```

Calcula la similitud coseno entre dos vectores. Asume que ambos están normalizados (norma ≈ 1.0), por lo que el cálculo se reduce a producto punto.

**Parámetros:**

| Nombre | Tipo | Descripción |
|--------|------|-------------|
| `a` | `List<double>` | Primer vector (384 dimensiones) |
| `b` | `List<double>` | Segundo vector (384 dimensiones) |

**Retorna:** `double` en el rango [-1.0, 1.0]. Valores cercanos a 1.0 indican vectores similares.

**Precondición:** `a.length == b.length`. Sin comprobación en runtime.

**Ejemplo:**

```dart
final sim = _cosineSimilarity(queryVector, goldenVector);
if (sim > 0.999) {
  // paridad perfecta
}
```

---

#### `_addLog`

```dart
void _addLog(String s)
```

Agrega una línea al log visible en pantalla y la imprime con `debugPrint`. Llama `setState` para refrescar la UI.

**Parámetros:**

| Nombre | Tipo | Descripción |
|--------|------|-------------|
| `s` | `String` | Línea a agregar |

---

#### `_runSmokeTest`

```dart
Future<void> _runSmokeTest()
```

Orquesta el smoke test completo en 5 pasos. Deshabilitado mientras corre (`_running = true`). Maneja errores con try/catch y los muestra en el log.

**Pasos:**

1. `_copyAssetToFile` para `model.onnx` y `tokenizer.json`
2. `MiniLmEmbedder.create(modelPath:, tokenizerPath:)`
3. `embedder.embed(texts: ['hola mundo'])` — mide latencia con `Stopwatch`
4. Carga `assets/data/golden_test.json` y extrae el vector de referencia
5. `_cosineSimilarity(embedding, goldenVector)` e interpreta el resultado

**Umbrales de paridad:**

| Condición | Diagnóstico |
|-----------|-------------|
| `similarity > 0.999` | Paridad perfecta |
| `0.95 < similarity ≤ 0.999` | Paridad aproximada (verificar retrieval quality) |
| `similarity ≤ 0.95` | Paridad rota — tokenizer, pooling o modelo difieren |

---

## Python — `embedding.py` (Google Colab)

Script que descarga el modelo ONNX, valida el pipeline y genera los tres archivos de assets.

---

#### `mean_pooling`

```python
def mean_pooling(
    token_embeddings: np.ndarray,
    attention_mask: np.ndarray
) -> np.ndarray
```

Promedia los embeddings de tokens ponderados por la attention mask, excluyendo tokens de padding.

**Parámetros:**

| Nombre | Tipo | Shape | Descripción |
|--------|------|-------|-------------|
| `token_embeddings` | `np.ndarray` | `(batch, seq_len, 384)` | Salida del modelo ONNX |
| `attention_mask` | `np.ndarray` | `(batch, seq_len)` | 1 en tokens reales, 0 en padding |

**Retorna:** `np.ndarray` de shape `(batch, 384)`.

**Ejemplo:**

```python
outputs = session.run(None, inputs)
pooled = mean_pooling(outputs[0], enc["attention_mask"])  # (batch, 384)
```

---

#### `l2_normalize`

```python
def l2_normalize(vec: np.ndarray) -> np.ndarray
```

Normaliza cada vector a norma L2 = 1.0. Clip a `1e-9` para evitar división por cero.

**Parámetros:**

| Nombre | Tipo | Shape | Descripción |
|--------|------|-------|-------------|
| `vec` | `np.ndarray` | `(batch, dim)` | Vectores sin normalizar |

**Retorna:** `np.ndarray` del mismo shape con norma ≈ 1.0 por fila.

---

#### `embed`

```python
def embed(text: str) -> list
```

Embebe un único texto. Útil para generar el golden test.

**Parámetros:**

| Nombre | Tipo | Descripción |
|--------|------|-------------|
| `text` | `str` | Texto a embeber |

**Retorna:** `list` de 384 floats, norma ≈ 1.0.

**Ejemplo:**

```python
vec = embed("hola mundo")
print(len(vec))           # 384
print(np.linalg.norm(vec))  # ~1.0

golden = {"text": "hola mundo", "vector": vec}
with open("golden_test.json", "w") as f:
    json.dump(golden, f)
```

---

#### `embed_batch`

```python
def embed_batch(texts: list, batch_size: int = 32) -> list
```

Embebe una lista de textos en lotes. Significativamente más rápido que llamar `embed` en un loop.

**Parámetros:**

| Nombre | Tipo | Default | Descripción |
|--------|------|---------|-------------|
| `texts` | `list[str]` | — | Lista de textos a embeber |
| `batch_size` | `int` | `32` | Tamaño de cada lote |

**Retorna:** `list` de listas de 384 floats, una por texto. Orden preservado.

**Ejemplo:**

```python
queries = [e["query"] for e in dataset]
vectors = embed_batch(queries, batch_size=64)
# vectors[i] corresponde a queries[i]

with open("vectors.json", "w") as f:
    json.dump(vectors, f)
```

---

## Python — `data_sintetica.py` (Google Colab)

Script que genera 500 queries médicas en español usando Claude API, con checkpoint para reanudar si se interrumpe.

**Constantes clave:**

| Constante | Valor | Descripción |
|-----------|-------|-------------|
| `MODELO` | `"claude-sonnet-4-6"` | Modelo de Claude usado para generación |
| `AREAS` | 10 strings | Especialidades médicas objetivo |
| `DISTRIBUCION` | dict | 5 tipos de query con sus cantidades (suma 50) |
| `SAVE_EVERY` | `10` | Autosave cada N queries nuevas |

---

#### `construir_prompt`

```python
def construir_prompt(area: str, cat_info: dict) -> str
```

Rellena `PROMPT_TEMPLATE` con el área médica y la descripción del tipo de query.

**Parámetros:**

| Nombre | Tipo | Descripción |
|--------|------|-------------|
| `area` | `str` | Una de las 10 especialidades en `AREAS` |
| `cat_info` | `dict` | Entrada de `DISTRIBUCION` con claves `"n"` y `"descripcion"` |

**Retorna:** `str` — el prompt completo listo para enviar a Claude.

---

#### `extraer_json`

```python
def extraer_json(texto: str)
```

Parsea el texto de respuesta de Claude como array JSON. Limpia fences de markdown (` ```json ... ``` `) y recorta al primer `[` y último `]` para tolerar texto extra.

**Parámetros:**

| Nombre | Tipo | Descripción |
|--------|------|-------------|
| `texto` | `str` | Respuesta cruda de Claude |

**Retorna:** objeto Python (lista de dicts).

**Lanza:** `json.JSONDecodeError` si no se puede parsear tras la limpieza.

---

#### `generar_lote`

```python
def generar_lote(
    area: str,
    cat_key: str,
    cat_info: dict,
    reintentos: int = 3
) -> list
```

Llama a Claude API y devuelve las queries parseadas para una combinación área × tipo. Reintenta hasta `reintentos` veces ante errores de parsing o de API; devuelve lista vacía si todos los intentos fallan.

**Parámetros:**

| Nombre | Tipo | Default | Descripción |
|--------|------|---------|-------------|
| `area` | `str` | — | Especialidad médica |
| `cat_key` | `str` | — | Clave del tipo en `DISTRIBUCION` |
| `cat_info` | `dict` | — | Config del tipo (`n`, `descripcion`) |
| `reintentos` | `int` | `3` | Intentos máximos ante fallos |

**Retorna:** `list[dict]` — cada dict tiene `query`, `registro`, `demografia`, `sistemas`, `complejidad`, `area`, `tipo`.

**Ejemplo de un elemento:**

```python
{
  "query": "desde hace 3 días me duele la cabeza por las tardes",
  "registro": "informal",
  "demografia": "adulto_joven",
  "sistemas": ["nervioso"],
  "complejidad": "simple",
  "area": "Medicina general / familiar",
  "tipo": "sintomas_primera_persona"
}
```

---

#### `ejecutar`

```python
def ejecutar() -> list
```

Loop principal de generación. Itera sobre todas las combinaciones `AREAS × DISTRIBUCION` (50 lotes), saltando las ya completadas según el checkpoint. Autosave cada `SAVE_EVERY` queries.

**Retorna:** `list[dict]` — el dataset completo (500 queries esperadas).

**Archivos producidos:**

| Archivo | Descripción |
|---------|-------------|
| `dataset_rag_medico_es.json` | Dataset completo |
| `dataset_rag_medico_es_checkpoint.json` | Estado de progreso para reanudar |

---

#### `auditar`

```python
def auditar(resultados: list) -> None
```

Imprime estadísticas del dataset: totales, distribución por área, tipo, registro, demografía y complejidad. Muestra 3 ejemplos aleatorios.

**Parámetros:**

| Nombre | Tipo | Descripción |
|--------|------|-------------|
| `resultados` | `list[dict]` | Dataset completo devuelto por `ejecutar()` |

**Ejemplo de salida:**

```
📊 Total: 500
   Esperado: 500 = 10 áreas × 50

Por área:
  Medicina general / familiar: 50
  Cardiología: 50
  ...

Por tipo:
  sintomas_primera_persona: 200
  medicamentos: 100
  ...
```
