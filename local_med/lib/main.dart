import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_embedder/flutter_embedder.dart';
import 'package:path_provider/path_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initFlutterEmbedder();
  runApp(const MaterialApp(home: SmokeTestScreen()));
}

class SmokeTestScreen extends StatefulWidget {
  const SmokeTestScreen({super.key});
  @override
  State<SmokeTestScreen> createState() => _SmokeTestScreenState();
}

class _SmokeTestScreenState extends State<SmokeTestScreen> {
  String _log = 'Listo. Presiona el botón para correr el smoke test.';
  bool _running = false;

  Future<String> _copyAssetToFile(String assetPath) async {
    final dir = await getApplicationSupportDirectory();
    final fileName = assetPath.split('/').last;
    final outFile = File('${dir.path}/$fileName');
    if (!await outFile.exists()) {
      final bytes = await rootBundle.load(assetPath);
      await outFile.writeAsBytes(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        flush: true,
      );
    }
    return outFile.path;
  }

  double _cosineSimilarity(List<double> a, List<double> b) {
    // Asume vectores normalizados (norma ≈ 1). Si no, dividir entre normas.
    double dot = 0.0;
    for (int i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
    }
    return dot;
  }

  void _addLog(String s) {
    setState(() => _log = '$_log\n$s');
    debugPrint(s);
  }

  Future<void> _runSmokeTest() async {
    setState(() {
      _log = '';
      _running = true;
    });

    try {
      _addLog('1/5 Copiando assets a filesystem...');
      final modelPath = await _copyAssetToFile('assets/models/model.onnx');
      final tokenizerPath = await _copyAssetToFile('assets/models/tokenizer.json');
      _addLog('   Modelo: $modelPath');

      _addLog('2/5 Inicializando MiniLmEmbedder...');
      final embedder = MiniLmEmbedder.create(
        modelPath: modelPath,
        tokenizerPath: tokenizerPath,
      );

      _addLog('3/5 Embebiendo "hola mundo"...');
      final sw = Stopwatch()..start();
      final embedding = embedder.embed(texts: ['hola mundo']).first;
      sw.stop();
      _addLog('   Latencia: ${sw.elapsedMilliseconds} ms');
      _addLog('   Dimensiones: ${embedding.length}');
      _addLog('   Primeros 5 valores: ${embedding.take(5).toList()}');

      // Verificar normalización
      double norma = 0;
      for (final v in embedding) {
        norma += v * v;
      }
      norma = math.sqrt(norma);
      _addLog('   Norma del vector: ${norma.toStringAsFixed(4)}');

      _addLog('4/5 Cargando golden_test.json...');
      final goldenJson = await rootBundle.loadString('assets/data/golden_test.json');
      final golden = jsonDecode(goldenJson) as Map<String, dynamic>;
      final goldenVector = (golden['vector'] as List).cast<double>();
      _addLog('   Texto esperado: "${golden['text']}"');

      _addLog('5/5 Calculando paridad (cosine similarity)...');
      final similarity = _cosineSimilarity(
        embedding.cast<double>(),
        goldenVector,
      );
      _addLog('   Similarity: ${similarity.toStringAsFixed(6)}');

      if (similarity > 0.999) {
        _addLog('\n✅ PARIDAD OK — Flutter y Colab producen el mismo vector');
      } else if (similarity > 0.95) {
        _addLog('\n⚠️  PARIDAD APROXIMADA — diferencias menores (¿cuantización?)');
        _addLog('   Puede ser usable pero verifica retrieval quality con eval set');
      } else {
        _addLog('\n❌ PARIDAD ROTA — los vectores son inconsistentes');
        _addLog('   Causas posibles: tokenizer distinto, pooling distinto,');
        _addLog('   normalización distinta, o modelo distinto entre Colab y Flutter');
      }
    } catch (e, st) {
      _addLog('\n❌ ERROR: $e');
      _addLog('Stack:\n$st');
    } finally {
      setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('local_med — Smoke Test')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton(
              onPressed: _running ? null : _runSmokeTest,
              child: Text(_running ? 'Corriendo...' : 'Correr smoke test'),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    _log,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      color: Colors.greenAccent,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}