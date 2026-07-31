import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:http/http.dart' as http;

const _kBunnyApiBase = 'https://admin.quickdash.co.in';

/// Uploads [image] to Bunny Storage via the server proxy.
/// [folder] must be one of the allowed folders configured on the server:
/// profiles, store/products, store/photos, documents, story/images.
Future<String> uploadImageToBunny(File image, String folder) async {
  final idToken = await auth.FirebaseAuth.instance.currentUser?.getIdToken();
  if (idToken == null) throw Exception('Not signed in.');

  final request = http.MultipartRequest(
    'POST',
    Uri.parse('$_kBunnyApiBase/api/bunny/image/upload'),
  )
    ..headers['Authorization'] = 'Bearer $idToken'
    ..fields['folder'] = folder
    ..files.add(await http.MultipartFile.fromPath('file', image.path));

  final streamedResp = await request.send().timeout(const Duration(seconds: 60));
  final resp = await http.Response.fromStream(streamedResp);

  if (resp.statusCode != 200) {
    throw Exception('Bunny image upload failed (folder=$folder): ${resp.body}');
  }
  return (jsonDecode(resp.body) as Map<String, dynamic>)['url'] as String;
}
