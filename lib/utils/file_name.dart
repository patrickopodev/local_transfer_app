/// Extensions the app treats as viewable video in the Media tab.
const Set<String> kVideoExtensions = {
  'mp4',
  'mov',
  'mkv',
  'avi',
  'webm',
  'm4v',
};

/// Extensions the app treats as viewable images in the Media tab.
const Set<String> kImageExtensions = {
  'jpg',
  'jpeg',
  'png',
  'gif',
  'webp',
  'bmp',
};

/// Extensions shown in the Media tab (images + videos).
const Set<String> kMediaExtensions = {...kImageExtensions, ...kVideoExtensions};

/// Lowercased extension of [filename] without the dot, or `''` when the name
/// has no extension. Dotfiles like `.env` are treated as having no extension.
String fileExtension(String filename) {
  final base = filename.split('/').last;
  final dot = base.lastIndexOf('.');
  if (dot <= 0 || dot == base.length - 1) return '';
  return base.substring(dot + 1).toLowerCase();
}

bool isVideoFile(String filename) =>
    kVideoExtensions.contains(fileExtension(filename));

bool isImageFile(String filename) =>
    kImageExtensions.contains(fileExtension(filename));

bool isMediaFile(String filename) =>
    kMediaExtensions.contains(fileExtension(filename));

/// Reduces an untrusted, peer-supplied filename to a single safe path segment.
///
/// Incoming filenames come from any device on the LAN and are never trusted:
/// the receiver joins this onto the save directory, so a value containing
/// `../` or an absolute path would otherwise write outside it. This strips
/// path separators and drive letters, collapses `.`/`..` segments, and removes
/// characters that are illegal or dangerous in a filename (including NUL and
/// control characters) on every platform the app targets.
///
/// Returns `'unnamed'` when nothing usable survives, so the caller always gets
/// a usable name.
String sanitizeFileName(String raw) {
  // Normalize separators first: a Windows-style path would survive a naive
  // scan for '/' alone.
  var name = raw.replaceAll('\\', '/');
  // Take the last segment so `a/b/c.txt` becomes `c.txt` rather than losing the
  // whole name to the separator stripping below.
  name = name.split('/').last;

  // Strip a Windows drive/UNC prefix (e.g. `C:`, `C:\..\..\`).
  name = name.replaceFirst(RegExp(r'^[A-Za-z]:'), '');

  final buffer = StringBuffer();
  for (final rune in name.runes) {
    // Drop NUL and all control characters, plus the characters Windows rejects.
    if (rune < 0x20 || rune == 0x7f) continue;
    if (const {
      '<',
      '>',
      ':',
      '"',
      '/',
      '\\',
      '|',
      '?',
      '*',
    }.contains(String.fromCharCode(rune))) {
      continue;
    }
    buffer.writeCharCode(rune);
  }

  var cleaned = buffer.toString().trim();
  // A name of only dots ('.' or '..') would still escape or resolve to the
  // directory itself.
  while (cleaned.isNotEmpty && cleaned.split('').every((c) => c == '.')) {
    cleaned = '';
  }
  // Leading/trailing dots and spaces are silently stripped by some filesystems,
  // which could turn a sanitized name back into '.' or '..'.
  cleaned = cleaned.replaceAll(RegExp(r'^\.+|\.+$'), '').trim();

  if (cleaned.isEmpty) return 'unnamed';
  return cleaned;
}
