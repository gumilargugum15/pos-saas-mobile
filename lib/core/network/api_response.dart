/// Success envelope from `Controller::success()` / `Controller::paginated()`
/// in the backend: `{success, message, data[, meta]}`.
class ApiResponse<T> {
  const ApiResponse({
    required this.data,
    required this.message,
    required this.statusCode,
    this.meta,
  });

  final T data;
  final String message;
  final int statusCode;

  /// Present on paginated responses only.
  final PageMeta? meta;
}

class PageMeta {
  const PageMeta({
    required this.currentPage,
    required this.lastPage,
    required this.perPage,
    required this.total,
  });

  factory PageMeta.fromJson(Map<String, dynamic> json) => PageMeta(
        currentPage: (json['current_page'] as num?)?.toInt() ?? 1,
        lastPage: (json['last_page'] as num?)?.toInt() ?? 1,
        perPage: (json['per_page'] as num?)?.toInt() ?? 15,
        total: (json['total'] as num?)?.toInt() ?? 0,
      );

  final int currentPage;
  final int lastPage;
  final int perPage;
  final int total;

  bool get hasMore => currentPage < lastPage;
}

class Paginated<T> {
  const Paginated({required this.items, required this.meta});

  final List<T> items;
  final PageMeta meta;
}
