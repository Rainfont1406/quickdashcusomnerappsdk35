import 'dart:io';

import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_view/photo_view.dart';

class FullScreenImageViewer extends StatefulWidget {
  final String imageUrl;
  final File? imageFile;

  const FullScreenImageViewer({Key? key, required this.imageUrl, this.imageFile}) : super(key: key);

  @override
  State<FullScreenImageViewer> createState() => _FullScreenImageViewerState();
}

class _FullScreenImageViewerState extends State<FullScreenImageViewer>
    with SingleTickerProviderStateMixin {
  bool _uiVisible = true;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
      value: 1,
    );
    _fadeAnimation = CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _fadeController.dispose();
    super.dispose();
  }

  void _toggleUI() {
    setState(() => _uiVisible = !_uiVisible);
    if (_uiVisible) {
      _fadeController.forward();
    } else {
      _fadeController.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ImageProvider provider = widget.imageFile != null
        ? FileImage(widget.imageFile!) as ImageProvider
        : NetworkImage(widget.imageUrl);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Zoomable image
          GestureDetector(
            onTap: _toggleUI,
            child: Hero(
              tag: widget.imageUrl,
              child: PhotoView(
                imageProvider: provider,
                minScale: PhotoViewComputedScale.contained,
                maxScale: PhotoViewComputedScale.covered * 4,
                initialScale: PhotoViewComputedScale.contained,
                backgroundDecoration: const BoxDecoration(color: Colors.black),
                loadingBuilder: (context, event) => Center(
                  child: CircularProgressIndicator(
                    value: event == null || event.expectedTotalBytes == null
                        ? null
                        : event.cumulativeBytesLoaded / event.expectedTotalBytes!,
                    valueColor: const AlwaysStoppedAnimation<Color>(AppThemeData.primary500),
                    strokeWidth: 2.5,
                  ),
                ),
                errorBuilder: (context, error, stackTrace) => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.broken_image_rounded, color: Colors.white38, size: 64),
                      const SizedBox(height: 12),
                      Text(
                        'Failed to load image',
                        style: TextStyle(color: Colors.white54, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Top controls
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: IgnorePointer(
                ignoring: !_uiVisible,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.black.withValues(alpha: 0.6), Colors.transparent],
                    ),
                  ),
                  padding: EdgeInsets.fromLTRB(8, MediaQuery.of(context).padding.top + 4, 8, 16),
                  child: Row(
                    children: [
                      _iconBtn(
                        icon: Icons.arrow_back_ios_new_rounded,
                        onTap: () => Navigator.pop(context),
                      ),
                      const Spacer(),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Bottom hint
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: IgnorePointer(
                ignoring: !_uiVisible,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [Colors.black.withValues(alpha: 0.5), Colors.transparent],
                    ),
                  ),
                  padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).padding.bottom + 16),
                  child: Text(
                    'Pinch to zoom  •  Tap to toggle controls',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 12,
                      fontFamily: AppThemeData.regular,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _iconBtn({required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.4),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 18),
      ),
    );
  }
}
