import 'dart:io';

import 'package:emartconsumer/services/helper.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';

class FullScreenImage extends StatelessWidget {
  final String? imageUrl;
  final File? imageFile;

  const FullScreenImage({Key? key, this.imageUrl, this.imageFile}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        backgroundColor: isDarkMode(context) ? AppThemeData.surfaceDark : AppThemeData.surface,
        appBar: AppBar(
          elevation: 0.0,
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: Container(
          color: Colors.black,
          child: PhotoView(
            imageProvider: imageFile == null ? NetworkImage(imageUrl!) : Image.file(imageFile!).image,
          ),
        ));
  }
}
