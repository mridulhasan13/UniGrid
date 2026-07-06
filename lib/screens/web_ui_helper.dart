import '../utils/constants.dart';
import 'package:flutter/material.dart';

Widget buildWebViewer(String url, String fileName) {
  return Center(
    child: Text(
      'Document preview is only available on Web.\nPlease use the download button to view the file.',
      textAlign: TextAlign.center,
      style: TextStyle(color: AppColors.textSecondary),
    ),
  );
}

void downloadWebFile(String url, String fileName) {
  // Mobile uses url_launcher instead
}

void printWebFile(String url) {
  // Mobile uses url_launcher instead
}
