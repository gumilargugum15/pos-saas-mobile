/// Makes backend media URLs (product images) loadable from the device.
///
/// The backend builds them with `asset('storage/…')`, i.e. from its own
/// idea of its address. That breaks on a phone when it says `localhost`
/// (local development) or `http` behind an HTTPS proxy without trusted
/// proxies (release builds block cleartext). Media served by the same
/// backend is therefore re-based onto the API's scheme, host and port;
/// URLs pointing to any other host (e.g. a CDN) are left untouched.
abstract final class MediaUrl {
  static const _loopbackHosts = {'localhost', '127.0.0.1', '0.0.0.0', '10.0.2.2', '::1'};

  static String? resolve(String? raw, String apiBaseUrl) {
    if (raw == null || raw.trim().isEmpty) return null;
    final media = Uri.tryParse(raw.trim());
    final api = Uri.tryParse(apiBaseUrl);
    if (media == null || api == null || !media.hasScheme || media.host.isEmpty) return null;

    final sameBackend = media.host == api.host || _loopbackHosts.contains(media.host);
    if (!sameBackend) return media.toString();

    return Uri(
      scheme: api.scheme,
      host: api.host,
      port: api.hasPort ? api.port : null,
      path: media.path,
      query: media.hasQuery ? media.query : null,
    ).toString();
  }
}
