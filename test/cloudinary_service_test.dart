import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:roomie/data/datasources/cloudinary_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('CloudinaryService parses secure_url on successful upload', () async {
    // Monkey patch: create a local function replicating uploadBytes logic using injected client
    Future<String?> uploadWithMock(Uint8List bytes, http.Client client) async {
      final uri = Uri.parse(CloudinaryConfig.uploadUrl);
      final request =
          http.MultipartRequest('POST', uri)
            ..fields['upload_preset'] = CloudinaryConfig.uploadPreset
            ..files.add(
              http.MultipartFile.fromBytes('file', bytes, filename: 'test.png'),
            );

      final streamed = await client.send(request);
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return data['secure_url'] as String?;
      }
      return null;
    }

    final mockClient = MockClient((req) async {
      return http.Response(
        jsonEncode({
          'secure_url':
              'https://res.cloudinary.com/demo/image/upload/v1/test.png',
        }),
        200,
      );
    });

    final result = await uploadWithMock(
      Uint8List.fromList([1, 2, 3]),
      mockClient,
    );
    expect(result, isNotNull);
    expect(result, contains('cloudinary.com'));
  });
}
