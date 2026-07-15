import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:url_launcher/url_launcher.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import '../utils/constants.dart';
import '../widgets/unigrid_loader.dart';
import 'web_ui_helper.dart' if (dart.library.html) 'web_ui_helper_web.dart';

class FileViewerScreen extends StatefulWidget {
  final String fileName;
  final String? fileUrl;

  const FileViewerScreen({
    super.key,
    required this.fileName,
    this.fileUrl,
  });

  @override
  State<FileViewerScreen> createState() => _FileViewerScreenState();
}

class _FileViewerScreenState extends State<FileViewerScreen> {
  String get _fullUrl => widget.fileUrl ?? '';
  bool _isPdfLoading = true;
  String? _pdfLoadError;

  bool get _isBase64 => _fullUrl.startsWith('data:');

  bool get _isImage {
    final lowerName = widget.fileName.toLowerCase();
    final lowerUrl = _fullUrl.toLowerCase();
    
    if (lowerName.endsWith('.png') ||
        lowerName.endsWith('.jpg') ||
        lowerName.endsWith('.jpeg') ||
        lowerName.endsWith('.gif') ||
        lowerName.endsWith('.webp')) {
      return true;
    }
    
    if (_fullUrl.startsWith('data:image/') ||
        lowerUrl.contains('.png') ||
        lowerUrl.contains('.jpg') ||
        lowerUrl.contains('.jpeg') ||
        lowerUrl.contains('.gif') ||
        lowerUrl.contains('.webp')) {
      return true;
    }
    
    return false;
  }

  bool get _isPdf {
    final lowerName = widget.fileName.toLowerCase();
    final lowerUrl = _fullUrl.toLowerCase();
    
    return lowerName.endsWith('.pdf') || lowerUrl.contains('.pdf');
  }

  @override
  void initState() {
    super.initState();
    // Auto-launch the file externally on mobile if it is not an image/PDF and url is present
    if (!kIsWeb && !_isImage && !_isPdf && _fullUrl.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _downloadFile();
      });
    }
  }

  @override
  void didUpdateWidget(covariant FileViewerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!kIsWeb && !_isImage && !_isPdf) {
      // If the URL goes from empty/null to non-empty (finished uploading), auto-launch
      if (oldWidget.fileUrl != widget.fileUrl && _fullUrl.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _downloadFile();
        });
      }
    }
  }

  void _downloadFile() async {
    if (_fullUrl.isEmpty) return;
    if (kIsWeb) {
      downloadWebFile(_fullUrl, widget.fileName);
    } else {
      var targetUrl = _fullUrl;
      if (_isPdf) {
        // Use Google Docs Viewer to display PDFs directly on mobile browsers
        targetUrl = 'https://docs.google.com/gview?embedded=true&url=${Uri.encodeComponent(_fullUrl)}';
      }
      final uri = Uri.parse(targetUrl);
      try {
        await launchUrl(uri, mode: LaunchMode.platformDefault);
      } catch (e) {
        try {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } catch (e2) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Could not open file: $e2'),
                backgroundColor: const Color(0xFF1E293B),
              ),
            );
          }
        }
      }
    }
  }

  void _printFile() async {
    if (_fullUrl.isEmpty) return;
    if (kIsWeb) {
      printWebFile(_fullUrl);
    } else {
      var targetUrl = _fullUrl;
      if (_isPdf) {
        targetUrl = 'https://docs.google.com/gview?embedded=true&url=${Uri.encodeComponent(_fullUrl)}';
      }
      final uri = Uri.parse(targetUrl);
      try {
        await launchUrl(uri, mode: LaunchMode.platformDefault);
      } catch (e) {
        try {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } catch (e2) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Could not print/open file: $e2'),
                backgroundColor: const Color(0xFF1E293B),
              ),
            );
          }
        }
      }
    }
  }

  Widget _buildMobileDocumentView() {
    final ext = widget.fileName.split('.').last.toUpperCase();
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.primary.withOpacity(0.3), width: 2),
              ),
              child: Icon(
                _isPdf ? Icons.picture_as_pdf : Icons.insert_drive_file,
                color: _isPdf ? Colors.redAccent : AppColors.primary,
                size: 72,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              widget.fileName,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.glassCardBorder,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '$ext Document',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w500),
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: _downloadFile,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.onPrimary,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
                elevation: 4,
              ),
              icon: const Icon(Icons.open_in_new, size: 20),
              label: Text(
                _isPdf ? 'Open PDF in Viewer' : 'Open Document',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'The document will open directly in your phone\'s browser or native viewer.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingView({
    String title = 'Securing Your File',
    String subtitle = 'Uploading attachment to cloud storage...',
  }) {
    return UniGridLoader(
      title: title,
      subtitle: subtitle,
      showBackground: false,
    );
  }

  Widget _buildBase64View() {
    try {
      final base64String = _fullUrl.split(',').last;
      final bytes = base64Decode(base64String);
      return Image.memory(
        bytes,
        fit: BoxFit.contain,
      );
    } catch (e) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.broken_image, color: AppColors.textSecondary.withOpacity(0.3), size: 64),
            SizedBox(height: 12),
            Text(
              'Could not decode image.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundTop,
      appBar: AppBar(
        title: Text(
          widget.fileName,
          style: TextStyle(color: AppColors.textPrimary, fontSize: 16),
          overflow: TextOverflow.ellipsis,
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: AppColors.textPrimary),
        actions: [
          if (_fullUrl.isNotEmpty && !_isBase64) ...[
            IconButton(
              icon: Icon(Icons.print, color: AppColors.textPrimary),
              onPressed: _printFile,
              tooltip: 'Print / Open externally',
            ),
            IconButton(
              icon: Icon(Icons.download, color: AppColors.primary),
              onPressed: _downloadFile,
              tooltip: kIsWeb ? 'Download' : 'Open in Browser',
            ),
          ],
        ],
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(gradient: AppGradients.mainBackground),
        child: _fullUrl.isEmpty
            ? _buildLoadingView()
            : Container(
                margin: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.textPrimary.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.textPrimary.withOpacity(0.1)),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: _isBase64
                      ? _buildBase64View()
                      : (_isImage
                          ? Image.network(
                              _fullUrl,
                              fit: BoxFit.contain,
                              loadingBuilder: (context, child, progress) {
                                if (progress == null) return child;
                                return Center(
                                  child: CircularProgressIndicator(
                                      color: AppColors.primary),
                                );
                              },
                              errorBuilder: (context, error, stackTrace) =>
                                  Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.broken_image,
                                        color: AppColors.textSecondary.withOpacity(0.3), size: 64),
                                    SizedBox(height: 12),
                                    Text(
                                      'Could not load image.',
                                      style: TextStyle(color: AppColors.textSecondary),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : (_isPdf
                              ? Stack(
                                  children: [
                                    SfPdfViewer.network(
                                      _fullUrl,
                                      onDocumentLoaded: (details) {
                                        setState(() {
                                          _isPdfLoading = false;
                                          _pdfLoadError = null;
                                        });
                                      },
                                      onDocumentLoadFailed: (details) {
                                        setState(() {
                                          _isPdfLoading = false;
                                          _pdfLoadError = details.description;
                                        });
                                      },
                                    ),
                                    if (_isPdfLoading)
                                      Positioned.fill(
                                        child: Container(
                                          color: AppColors.backgroundTop,
                                          child: UniGridLoader(
                                            title: 'Opening PDF',
                                            subtitle: 'Initializing document viewer...',
                                            showBackground: false,
                                          ),
                                        ),
                                      ),
                                    if (_pdfLoadError != null)
                                      Positioned.fill(
                                        child: Container(
                                          color: AppColors.backgroundTop,
                                          padding: const EdgeInsets.all(24),
                                          child: Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              const Icon(Icons.error_outline,
                                                  color: Colors.redAccent, size: 48),
                                              const SizedBox(height: 16),
                                              Text(
                                                'Failed to load PDF in-app',
                                                style: TextStyle(
                                                    color: AppColors.textPrimary,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 16),
                                              ),
                                              const SizedBox(height: 8),
                                              Text(
                                                _pdfLoadError!,
                                                style: TextStyle(
                                                    color: AppColors.textSecondary,
                                                    fontSize: 12),
                                                textAlign: TextAlign.center,
                                              ),
                                              const SizedBox(height: 24),
                                              ElevatedButton.icon(
                                                onPressed: _downloadFile,
                                                icon: const Icon(Icons.open_in_new),
                                                label: const Text('Open in Browser / External App'),
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: AppColors.primary,
                                                  foregroundColor: AppColors.onPrimary,
                                                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius: BorderRadius.circular(10),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                  ],
                                )
                              : (kIsWeb
                                  ? buildWebViewer(_fullUrl, widget.fileName)
                                  : _buildMobileDocumentView()))),
                ),
              ),
      ),
    );
  }
}
