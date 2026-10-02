class Category {
  const Category({required this.id, required this.name});

  final int id;
  final String name;

  @override
  bool operator ==(Object other) => other is Category && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
