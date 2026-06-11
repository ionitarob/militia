import 'package:flutter/cupertino.dart';
import 'package:pdfrx/pdfrx.dart';

class PdfPreviewScreen extends StatelessWidget {
  final String url;
  final String title;

  const PdfPreviewScreen({super.key, required this.url, required this.title});

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cerrar'),
        ),
      ),
      child: SafeArea(
        child: PdfViewer.uri(
          Uri.parse(url),
          params: PdfViewerParams(
            backgroundColor: const Color(0xFFE5E7EB),
            loadingBannerBuilder: (context, bytesDownloaded, totalBytes) =>
                const Center(child: CupertinoActivityIndicator()),
            errorBannerBuilder: (context, error, stackTrace, documentRef) =>
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        CupertinoIcons.exclamationmark_circle,
                        size: 40,
                        color: Color(0xFFDC2626),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'No se pudo cargar el documento.',
                        style: TextStyle(
                          fontSize: 15,
                          color: Color(0xFF374151),
                        ),
                      ),
                    ],
                  ),
                ),
          ),
        ),
      ),
    );
  }
}
