import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/library_provider.dart';
import 'library_search_results.dart';

/// Show a bottom sheet with author info and books.
void showAuthorDetailSheet(BuildContext context, {
  required String authorId,
  required String authorName,
}) {
  FocusManager.instance.primaryFocus?.unfocus();
  final auth = context.read<AuthProvider>();
  final lib = context.read<LibraryProvider>();
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.05, snap: true,
      maxChildSize: 0.9,
      expand: false,
      builder: (ctx, scrollController) => AuthorBooksSheet(
        libraryId: lib.selectedLibraryId ?? '',
        authorId: authorId,
        authorName: authorName,
        serverUrl: auth.serverUrl,
        token: auth.token,
        scrollController: scrollController,
      ),
    ),
  );
}

class AuthorBooksSheet extends StatefulWidget {
  final String libraryId;
  final String authorId;
  final String authorName;
  final String? serverUrl;
  final String? token;
  final ScrollController scrollController;

  const AuthorBooksSheet({
    super.key,
    required this.libraryId,
    required this.authorId,
    required this.authorName,
    required this.serverUrl,
    required this.token,
    required this.scrollController,
  });

  @override
  State<AuthorBooksSheet> createState() => _AuthorBooksSheetState();
}

class _AuthorBooksSheetState extends State<AuthorBooksSheet> {
  List<Map<String, dynamic>> _books = [];
  bool _isLoading = true;
  String? _description;
  String? _imageUrl;
  bool _descExpanded = false;

  @override
  void initState() {
    super.initState();
    _loadAuthorAndBooks();
  }

  Future<void> _loadAuthorAndBooks() async {
    final auth = context.read<AuthProvider>();
    final api = auth.apiService;
    if (api == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    // Fetch author details and books in parallel
    final futures = await Future.wait([
      api.getAuthorById(widget.authorId, libraryId: widget.libraryId),
      _fetchBooks(auth),
    ]);

    final authorData = futures[0] as Map<String, dynamic>?;

    if (mounted) {
      setState(() {
        if (authorData != null) {
          _description = authorData['description'] as String?;
          if (authorData['imagePath'] != null && (authorData['imagePath'] as String).isNotEmpty) {
            final ts = (authorData['updatedAt'] as num?)?.toInt();
            _imageUrl = api.getAuthorImageUrl(widget.authorId, updatedAt: ts);
          }
        }
        _isLoading = false;
      });
    }
  }

  Future<List<Map<String, dynamic>>> _fetchBooks(AuthProvider auth) async {
    try {
      final filterValue = base64Encode(utf8.encode(widget.authorId));
      final cleanUrl = (auth.serverUrl ?? '').endsWith('/')
          ? auth.serverUrl!.substring(0, auth.serverUrl!.length - 1)
          : auth.serverUrl!;
      final url =
          '$cleanUrl/api/libraries/${widget.libraryId}/items'
          '?filter=authors.$filterValue&sort=media.metadata.title&limit=200&collapseseries=0';

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer ${auth.token}',
        },
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200 && mounted) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final results = (data['results'] as List<dynamic>?) ?? [];
        final books = results.whereType<Map<String, dynamic>>().toList();
        if (mounted) setState(() => _books = books);
        return books;
      }
    } catch (_) {}
    return [];
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final lib = context.read<LibraryProvider>();
    final headers = lib.mediaHeaders;

    if (_isLoading) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(cs, tt, headers),
          const Expanded(child: Center(child: CircularProgressIndicator())),
        ],
      );
    }

    // Single scrollable list: header + description + books
    final bottomPad = 24 + MediaQuery.of(context).viewPadding.bottom;
    final hasDesc = _description != null && _description!.isNotEmpty;
    // header + optional description + books (or empty message)
    final itemCount = 1 + (hasDesc ? 1 : 0) + (_books.isEmpty ? 1 : _books.length);
    final descOffset = 1;
    final booksOffset = 1 + (hasDesc ? 1 : 0);

    return ListView.builder(
      controller: widget.scrollController,
      padding: EdgeInsets.fromLTRB(0, 0, 0, bottomPad),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        if (index == 0) return _buildHeader(cs, tt, headers);
        if (hasDesc && index == descOffset) return _buildDescription(cs, tt);
        if (_books.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.only(top: 48),
              child: Text('No books found',
                  style: tt.bodyLarge?.copyWith(color: cs.onSurfaceVariant)),
            ),
          );
        }
        final bookIndex = index - booksOffset;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: BookResultTile(
            item: _books[bookIndex],
            serverUrl: widget.serverUrl,
            token: widget.token,
          ),
        );
      },
    );
  }

  Widget _buildHeader(ColorScheme cs, TextTheme tt, Map<String, String> headers) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: cs.secondaryContainer,
            ),
            clipBehavior: Clip.antiAlias,
            child: _imageUrl != null
                ? CachedNetworkImage(
                    imageUrl: _imageUrl!,
                    fit: BoxFit.cover,
                    httpHeaders: headers,
                    placeholder: (_, __) => _avatarPlaceholder(cs),
                    errorWidget: (_, __, ___) => _avatarPlaceholder(cs),
                  )
                : _avatarPlaceholder(cs),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(widget.authorName,
                    style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
                if (_books.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '${_books.length} ${_books.length == 1 ? 'book' : 'books'}',
                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDescription(ColorScheme cs, TextTheme tt) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
      child: GestureDetector(
        onTap: () => setState(() => _descExpanded = !_descExpanded),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _description!,
              maxLines: _descExpanded ? null : 4,
              overflow: _descExpanded ? null : TextOverflow.ellipsis,
              style: tt.bodySmall?.copyWith(
                color: cs.onSurface.withValues(alpha: 0.7),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _descExpanded ? 'Show less' : 'Read more',
              style: tt.labelSmall?.copyWith(
                color: cs.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _avatarPlaceholder(ColorScheme cs) {
    return Center(
      child: Icon(Icons.person_rounded,
          size: 32, color: cs.onSecondaryContainer.withValues(alpha: 0.5)),
    );
  }
}
