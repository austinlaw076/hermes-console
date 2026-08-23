import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hermes_android/core/services/huggingface_client.dart';

void main() {
  group('HfModel / HfFile', () {
    test('HfModel parsea id, downloads, likes, owner/name', () {
      final m = HfModel.fromJson({
        'id': 'TheBloke/Llama-2-7B-GGUF',
        'downloads': 1234,
        'likes': 56,
        'tags': ['gguf', 'llama'],
      });
      expect(m.owner, 'TheBloke');
      expect(m.name, 'Llama-2-7B-GGUF');
      expect(m.downloads, 1234);
      expect(m.likes, 56);
    });

    test('HfFile.humanSize y isGguf', () {
      expect(HfFile(path: 'model.Q4.gguf', sizeBytes: 0).isGguf, isTrue);
      expect(HfFile(path: 'readme.md', sizeBytes: 0).isGguf, isFalse);
      expect(HfFile(path: 'a', sizeBytes: 1536).humanSize, '1.5 KB');
      expect(
        HfFile(path: 'a', sizeBytes: 2 * 1024 * 1024 * 1024).humanSize,
        '2.0 GB',
      );
    });

    HfModel m(String id) =>
        HfModel(id: id, downloads: 0, likes: 0, tags: const []);

    test('paramsB deduce el total (MoE cuenta total, no activos)', () {
      expect(m('unsloth/Qwen3.6-35B-A3B-GGUF').paramsB, 35);
      expect(m('owner/gemma-4-26B-A4B-it-GGUF').paramsB, 26);
      expect(m('owner/Qwen3.5-9B-GGUF').paramsB, 9);
      expect(m('owner/Llama-3.2-1B-GGUF').paramsB, 1);
      expect(m('owner/some-embed-model').paramsB, isNull);
    });

    test('fitsIn estima Q4 y compara con ~55% de la RAM', () {
      // 7B → ~0.55*7+0.7 ≈ 4.55 GB. Usable a 8 GB = 4.4 → no cabe; a 12 GB = 6.6 → cabe.
      final seven = m('owner/Model-7B-GGUF');
      expect(seven.fitsIn(8), isFalse);
      expect(seven.fitsIn(12), isTrue);
      // 1B → ~1.25 GB, cabe hasta en 4 GB (usable 2.2).
      expect(m('owner/Tiny-1B-GGUF').fitsIn(4), isTrue);
    });

    test('downloadUrl construye la URL resolve/main', () {
      final uri = HuggingFaceClient.downloadUrl('owner/repo', 'm.gguf');
      expect(
        uri.toString(),
        'https://huggingface.co/owner/repo/resolve/main/m.gguf?download=true',
      );
    });
  });

  group('HuggingFaceClient.searchGgufModels', () {
    test('parsea la lista y filtra a objetos modelo', () async {
      final client = HuggingFaceClient(
        client: MockClient((req) async {
          expect(req.url.host, 'huggingface.co');
          expect(req.url.queryParameters['filter'], 'gguf');
          return http.Response(
            '[{"id":"a/b","downloads":10,"likes":2,"tags":["gguf"]},'
            '{"id":"c/d","downloads":5,"likes":1,"tags":["gguf"]}]',
            200,
          );
        }),
      );
      final models = await client.searchGgufModels(query: 'qwen');
      expect(models.length, 2);
      expect(models.first.id, 'a/b');
    });

    test('lanza en error HTTP', () async {
      final client = HuggingFaceClient(
        client: MockClient((_) async => http.Response('nope', 500)),
      );
      expect(client.searchGgufModels(), throwsException);
    });
  });
}
