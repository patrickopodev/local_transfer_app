import 'dart:io';

/// A file selected for sending, plus its picker category.
class TransferFile {
  final String name;
  final String path;
  final int size;
  final String type;

  const TransferFile({
    required this.name,
    required this.path,
    required this.size,
    required this.type,
  });

  static TransferFile fromFile(File file, {String type = 'Files'}) {
    final name = file.uri.pathSegments.last;
    return TransferFile(
      name: name,
      path: file.path,
      size: file.lengthSync(),
      type: _inferType(name) ?? type,
    );
  }

  static String? _inferType(String name) {
    final lower = name.toLowerCase();
    const images = ['jpg', 'jpeg', 'png', 'gif', 'webp', 'heic', 'bmp'];
    const videos = ['mp4', 'mov', 'mkv', 'avi', 'webm', 'wmv'];
    const docs = ['pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt'];
    final ext = lower.contains('.') ? lower.split('.').last : '';
    if (images.contains(ext)) return 'Photos';
    if (videos.contains(ext)) return 'Videos';
    if (docs.contains(ext)) return 'Documents';
    return 'Files';
  }
}